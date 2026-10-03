import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/empty_state_view.dart';
import 'package:gssms_mobile/core/widgets/feedback.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/skeleton_list.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/core/widgets/sticky_action_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/data/job_work_report_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_service.dart';
import 'package:printing/printing.dart';

/// Technician "Report Preview" of a finished Job Work (checklist, Breakdown,
/// inspection or rectification) with Print and Share. Online-only: the report
/// and its photos are always fetched live.
class JobWorkReportScreen extends ConsumerStatefulWidget {
  const JobWorkReportScreen({super.key, required this.workOrder});

  final WorkOrder workOrder;

  /// Statuses for which the web offers the "View" report button.
  static const reportStatuses = {
    WorkOrderStatus.techCompleted,
    WorkOrderStatus.verified,
    WorkOrderStatus.closed,
    WorkOrderStatus.cancelled,
  };

  /// Fail-closed gate: assigned MAINTENANCE_STAFF with `maintenance.view`
  /// on a reportable Job Work. Deliberately independent of `reports.export`.
  static bool canShow(WorkOrder wo, UserSession? session) =>
      session != null &&
      sessionAllows(session, 'maintenance.view') &&
      session.roles.contains(AuthRole.maintenanceStaff) &&
      reportStatuses.contains(wo.status) &&
      session.userId != null &&
      wo.assignedToId == session.userId;

  @override
  ConsumerState<JobWorkReportScreen> createState() =>
      _JobWorkReportScreenState();
}

class _JobWorkReportScreenState extends ConsumerState<JobWorkReportScreen> {
  Future<LoadedJobWorkReport>? _future;
  bool _busy = false;

  Future<LoadedJobWorkReport> _load() =>
      ref.read(jobWorkReportRepositoryProvider).load(widget.workOrder);

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  String _fileName(JobWorkReport r) {
    final safe = r.ticket.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'JobWork-$safe-Report.pdf';
  }

  Future<void> _export(LoadedJobWorkReport loaded,
      {required bool share}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final doc = await JobWorkReportPdfService.build(
        loaded.report,
        photos: loaded.photos,
      );
      final bytes = await doc.save();
      final name = _fileName(loaded.report);
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: name);
      } else {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      }
    } catch (e) {
      if (mounted) {
        showGssmsSnackBar(
          context,
          'Could not generate the PDF. ${userFacingError(e)}',
          tone: GssmsTone.danger,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // RBAC-04: re-check against the live session.
    if (!JobWorkReportScreen.canShow(widget.workOrder, sessionOf(ref))) {
      return Scaffold(
        appBar: AppBar(title: const Text('Job Work Report')),
        body: const PermissionDeniedView(),
      );
    }
    return FutureBuilder<LoadedJobWorkReport>(
      future: _future ??= _load(),
      builder: (context, snap) {
        final loaded =
            snap.connectionState == ConnectionState.done ? snap.data : null;
        final report = loaded?.report;
        final empty = report is ChecklistJobWorkReport && report.isEmpty;
        final ready = loaded != null && !empty && !_busy;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Job Work Report'),
            actions: [
              IconButton(
                key: const Key('job_work_report_refresh'),
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh),
                onPressed: _reload,
              ),
            ],
          ),
          body: _body(context, snap, loaded, empty),
          bottomNavigationBar: StickyActionBar(
            child: FilledButton.icon(
              key: const Key('job_work_report_print'),
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print'),
              onPressed: ready ? () => _export(loaded, share: false) : null,
            ),
            children: [
              OutlinedButton.icon(
                key: const Key('job_work_report_share'),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Share'),
                onPressed: ready ? () => _export(loaded, share: true) : null,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    AsyncSnapshot<LoadedJobWorkReport> snap,
    LoadedJobWorkReport? loaded,
    bool empty,
  ) {
    if (snap.hasError) {
      return EmptyStateView.error(
        title: 'Could not load this report',
        message: userFacingError(snap.error!),
        onRetry: _reload,
      );
    }
    if (loaded == null) {
      return SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(GssmsSpacing.s16),
              child: Text(
                'Loading report and photos...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SkeletonList(itemCount: 4),
          ],
        ),
      );
    }
    if (empty) {
      return const EmptyStateView(
        icon: Icon(Icons.description_outlined),
        title: 'No details available for this report.',
      );
    }
    return _ReportBody(loaded: loaded);
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.loaded});

  final LoadedJobWorkReport loaded;

  Map<String, Uint8List?> get photos => loaded.photos;

  @override
  Widget build(BuildContext context) {
    final r = loaded.report;
    final cards = <Widget>[
      _header(r),
      ...switch (r) {
        ChecklistJobWorkReport() => _checklist(context, r),
        ComplaintJobWorkReport() => _complaint(r),
        InspectionJobWorkReport() => _inspection(r),
        RectificationJobWorkReport() => _rectification(r),
      },
      _signOff(r),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GssmsSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in cards) ...[
            c,
            const SizedBox(height: GssmsSpacing.s12),
          ],
        ],
      ),
    );
  }

  // ----- shared pieces ------------------------------------------------------

  Widget _header(JobWorkReport r) {
    return SectionCard(
      title: r.title,
      icon: Icons.description_outlined,
      children: [
        InfoRow(label: 'Railway', value: r.org.railwayName),
        InfoRow(label: 'Division', value: r.org.divisionName),
        InfoRow(label: 'Depot', value: r.org.depotName),
        InfoRow(label: 'Job Work', value: r.ticket),
        InfoRow(label: 'Location', value: r.location),
        InfoRow(label: 'Date', value: r.dateLabel),
        if (r is ChecklistJobWorkReport)
          InfoRow(label: 'Schedule', value: r.schedule),
      ],
    );
  }

  Widget _text(String label, String value, {String empty = 'None recorded'}) {
    return InfoRow(label: label, value: value, emptyText: empty);
  }

  Widget _photoWrap(String label, List<ReportPhoto> list, String emptyLabel) {
    return Builder(builder: (context) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: GssmsSpacing.s6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const SizedBox(height: GssmsSpacing.s4),
            if (list.isEmpty)
              Text(emptyLabel, style: theme.textTheme.bodySmall)
            else
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: GssmsSpacing.s8),
                  itemBuilder: (_, i) => _photo(context, list[i]),
                ),
              ),
          ],
        ),
      );
    });
  }

  Widget _photo(BuildContext context, ReportPhoto p) {
    final bytes = photos[p.key];
    final tokens = context.gssms;
    Widget placeholder() => ColoredBox(
          color: tokens.surfaceInset,
          child: Icon(Icons.broken_image_outlined, color: tokens.textSecondary),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 128,
        height: 96,
        child: bytes == null
            ? placeholder()
            : Image.memory(
                bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder(),
              ),
      ),
    );
  }

  Widget _params(String title, List<ReportParameter> list) {
    if (list.isEmpty) return const SizedBox.shrink();
    return SectionCard(
      title: title,
      icon: Icons.tune,
      children: [
        for (final p in list)
          InfoRow(
            label: p.parameter,
            value: p.unit.isEmpty ? p.value : '${p.value} ${p.unit}',
          ),
      ],
    );
  }

  Widget _signOff(JobWorkReport r) {
    final v = r.verification;
    final String technician;
    var otherStaff = '';
    ReportSubmission? submission;
    switch (r) {
      case ChecklistJobWorkReport():
        technician = r.technician;
        otherStaff = r.otherStaff;
      case ComplaintJobWorkReport():
        technician = r.submitter;
        submission = r.submission;
      case InspectionJobWorkReport():
        technician = r.technician;
        submission = r.submission;
      case RectificationJobWorkReport():
        technician = r.technician;
        otherStaff = r.otherStaff;
    }
    return SectionCard(
      title: 'Sign-off',
      icon: Icons.verified_outlined,
      children: [
        InfoRow(label: 'Technician', value: technician),
        if (otherStaff.isNotEmpty)
          InfoRow(label: 'Maintenance Staff', value: otherStaff),
        InfoRow(
          label: 'Supervisor',
          value: v == null
              ? 'Pending verification'
              : (v.verifiedAtLabel.isEmpty
                  ? v.verifiedByName
                  : '${v.verifiedByName} | ${v.verifiedAtLabel}'),
        ),
        if (v != null && v.remarks.isNotEmpty)
          InfoRow(label: 'Supervisor Remarks', value: v.remarks),
        if (submission != null && submission.number.isNotEmpty)
          InfoRow(
            label: 'Submission',
            value: submission.timestampLabel.isEmpty
                ? '#${submission.number}'
                : '#${submission.number} | ${submission.timestampLabel}',
          ),
      ],
    );
  }

  // ----- Checklist ----------------------------------------------------------

  List<Widget> _checklist(BuildContext context, ChecklistJobWorkReport r) {
    return [
      for (final g in r.groups)
        SectionCard(
          title: g.name,
          icon: Icons.checklist,
          children: [
            for (final row in g.rows) _checklistRow(context, row),
          ],
        ),
      SectionCard(
        title: 'Deficiency Summary',
        icon: Icons.report_problem_outlined,
        trailing: StatusChip(
          label: '${r.deficiencies.length}',
          tone: r.deficiencies.isEmpty ? GssmsTone.neutral : GssmsTone.warning,
        ),
        children: [
          if (r.deficiencies.isEmpty)
            const InfoRow(label: 'Result', value: 'No deficiencies selected.'),
          for (final d in r.deficiencies) ...[
            InfoRow(label: 'Asset', value: d.asset),
            InfoRow(label: 'Checkpoint', value: d.checkpoint),
            InfoRow(label: 'Finding', value: d.finding),
            InfoRow(label: 'Action', value: d.action),
            InfoRow(label: 'Severity', value: d.severity),
            const Divider(),
          ],
        ],
      ),
      SectionCard(
        title: 'Additional Details',
        icon: Icons.notes,
        children: [
          InfoRow(
            label: 'Technician Remarks',
            value: r.remarks,
            emptyText: 'No remarks recorded.',
          ),
        ],
      ),
    ];
  }

  Widget _checklistRow(BuildContext context, ChecklistReportRow row) {
    final theme = Theme.of(context);
    final tokens = context.gssms;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GssmsSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (row.itemSpanStart && row.itemName.isNotEmpty)
            Text(row.itemName, style: theme.textTheme.titleSmall),
          if (row.paramSpanStart)
            Text('Record Parameters',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: tokens.textSecondary)),
          if (row.isRecordParameter)
            Text(
              '${row.checkpoint}: '
              '${row.hasValue ? row.formattedValue : '--'}'
              '${row.unit.isEmpty ? '' : ' (${row.unit})'}',
              style: theme.textTheme.bodyMedium,
            )
          else ...[
            Text(row.checkpoint, style: theme.textTheme.bodyMedium),
            const SizedBox(height: GssmsSpacing.s4),
            Wrap(
              spacing: GssmsSpacing.s8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                StatusChip(label: row.statusLabel, tone: GssmsTone.neutral),
                Text('Action: ${row.actionDisplay}',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ],
          if (row.attachments.isNotEmpty)
            _photoWrap('Attachments', row.attachments, ''),
        ],
      ),
    );
  }

  // ----- Breakdown ----------------------------------------------------------

  List<Widget> _complaint(ComplaintJobWorkReport r) {
    final Widget section1;
    switch (r.section1Kind) {
      case ComplaintSection1Kind.deficiency:
        final d = r.deficiencyDetails!;
        section1 = SectionCard(
          title: '1. Deficiency Details',
          icon: Icons.report_problem_outlined,
          children: [
            InfoRow(label: 'Found in', value: d.sourceTicket),
            InfoRow(label: 'Severity', value: d.severity),
            InfoRow(label: 'Target date', value: d.targetDate),
            InfoRow(label: 'Asset / Equipment', value: d.equipment),
            InfoRow(label: 'Checkpoint', value: d.checkpoint),
            _text('Finding', d.finding, empty: 'No finding recorded'),
          ],
        );
      case ComplaintSection1Kind.complaint:
        final c = r.complaintDetails!;
        section1 = SectionCard(
          title: '1. Breakdown Information',
          icon: Icons.build_circle_outlined,
          children: [
            InfoRow(label: 'Breakdown No', value: c.complaintNumber),
            InfoRow(label: 'Failure Date & Time', value: c.failureDateTime),
            InfoRow(label: 'Complainant', value: c.complainant),
            InfoRow(label: 'Reported Asset', value: c.reportedAsset),
            _text('Original Description', c.description),
          ],
        );
      case ComplaintSection1Kind.jobWork:
        section1 = SectionCard(
          title: '1. Job Work Details',
          icon: Icons.work_outline,
          children: [
            InfoRow(label: 'Location', value: r.station),
            InfoRow(label: 'Asset / Equipment', value: r.assetName),
            _text('Work to be done', r.workToBeDone),
          ],
        );
    }
    return [
      section1,
      SectionCard(
        title: 'Initial Assessment & Findings',
        icon: Icons.search,
        children: [_text('Findings', r.initialFindings)],
      ),
      SectionCard(
        title: 'Rectification / Action Taken',
        icon: Icons.handyman_outlined,
        children: [_text('Action', r.actionTaken)],
      ),
      _params('Technical Parameters', r.parameters),
      SectionCard(
        title: 'Photo Evidence',
        icon: Icons.photo_library_outlined,
        children: [
          _photoWrap(
              'Before / Initial Condition', r.beforePhotos, 'No photo uploaded'),
          _photoWrap('After / Rectification Result', r.afterPhotos,
              'No photo uploaded'),
        ],
      ),
      SectionCard(
        title: 'Final Remarks',
        icon: Icons.notes,
        children: [_text('Remarks', r.finalRemarks)],
      ),
    ];
  }

  // ----- Inspection ---------------------------------------------------------

  List<Widget> _inspection(InspectionJobWorkReport r) {
    return [
      SectionCard(
        title: 'Inspection Details',
        icon: Icons.fact_check_outlined,
        children: [
          if (r.inspectionTitle.isNotEmpty)
            InfoRow(label: 'Inspection Title', value: r.inspectionTitle),
          InfoRow(label: 'Inspection No.', value: r.inspectionNumber),
          InfoRow(label: 'Inspector', value: r.inspector),
          if (r.inspectionRemarks.isNotEmpty)
            InfoRow(label: 'Inspection Remarks', value: r.inspectionRemarks),
          if (r.generalEvidencePhotos.isNotEmpty)
            _photoWrap('General Evidence Photos', r.generalEvidencePhotos, ''),
        ],
      ),
      for (final pt in r.points) _inspectionPoint(r, pt),
    ];
  }

  Widget _inspectionPoint(InspectionJobWorkReport r, InspectionReportPoint pt) {
    final observationOnly = pt.correctiveActionPerformed == false;
    final tag =
        [pt.assetName, pt.priority].where((s) => s.isNotEmpty).join(' | ');
    return SectionCard(
      title: pt.isLegacy
          ? 'TECHNICIAN EXECUTION'
          : 'Point #${pt.pointNumber}: ${pt.observation}',
      icon: Icons.pin_drop_outlined,
      trailing:
          tag.isEmpty ? null : StatusChip(label: tag, tone: GssmsTone.info),
      children: [
        if (pt.isLegacy)
          for (final c in r.coveredPoints)
            InfoRow(
              label: 'Point ${c.number}',
              value: c.priority.isEmpty ? c.text : '${c.text} (${c.priority})',
            ),
        _text('Initial Findings', pt.initialFindings),
        _text('Action Taken', pt.actionTaken),
        _text('Final Remarks', pt.finalRemarks),
        for (final p in pt.technicalParameters)
          InfoRow(
            label: p.parameter,
            value: p.unit.isEmpty ? p.value : '${p.value} ${p.unit}',
          ),
        if (!pt.isLegacy)
          _photoWrap('Before Photos (From Inspection)',
              pt.inspectionEvidencePhotos, 'None'),
        _photoWrap('Before Photos', pt.beforePhotos, 'None uploaded'),
        if (observationOnly)
          const InfoRow(
            label: 'Note',
            value: 'Observation only - no corrective action required',
          ),
        _photoWrap('After Photos', pt.afterPhotos,
            observationOnly ? 'Not applicable' : 'None uploaded'),
      ],
    );
  }

  // ----- Rectification ------------------------------------------------------

  List<Widget> _rectification(RectificationJobWorkReport r) {
    return [
      SectionCard(
        title: 'Summary',
        icon: Icons.summarize_outlined,
        children: [Text(r.summaryLine)],
      ),
      for (var i = 0; i < r.items.length; i++) _rectItem(i, r.items[i]),
      SectionCard(
        title: 'Final Outcome',
        icon: Icons.flag_outlined,
        children: [
          _text('Remarks', r.finalRemarks, empty: 'No final remarks recorded'),
        ],
      ),
    ];
  }

  Widget _rectItem(int index, RectificationReportItem it) {
    final (label, tone) = switch (it.outcome) {
      RectificationOutcome.rectified => ('Rectified', GssmsTone.success),
      RectificationOutcome.notRectified => ('Not rectified', GssmsTone.danger),
      RectificationOutcome.pending => ('Pending', GssmsTone.warning),
    };
    return SectionCard(
      title: 'Item ${index + 1}: ${it.asset}',
      icon: Icons.build_outlined,
      trailing: StatusChip(label: label, tone: tone),
      children: [
        InfoRow(label: 'Source', value: it.sourceLabel),
        InfoRow(label: 'Checkpoint', value: it.checkpoint),
        InfoRow(label: 'Severity', value: it.severity),
        _text('Finding', it.finding, empty: 'No finding recorded'),
        _text('Action Taken', it.actionTaken, empty: 'No action recorded'),
        if (it.outcome == RectificationOutcome.notRectified)
          InfoRow(label: 'Reason it could not be rectified', value: it.reason),
        _photoWrap('Before Evidence', it.beforePhotos, 'No before photo'),
        _photoWrap('After Evidence', it.afterPhotos, 'No after photo'),
      ],
    );
  }
}
