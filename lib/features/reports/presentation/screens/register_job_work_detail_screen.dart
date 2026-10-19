import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:gssms_mobile/core/network/api_error.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/reports/domain/register_job_work_adapter.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_service.dart';

/// Maintenance Register entry detail for one completed Job Work.
///
/// Resolves the signed checklist record exactly like web
/// `ReportsView.viewReport` (record attached to the Job Work, else the
/// schedule-only record) and prints it through the SAME
/// [JobWorkReportPdfService] pipeline as the Job Work report — one layout,
/// matching the web print. Online-only: a failed resolution shows an error
/// with Retry, never an empty report.
class RegisterJobWorkDetailScreen extends ConsumerStatefulWidget {
  const RegisterJobWorkDetailScreen({super.key, required this.workOrder});

  final WorkOrder workOrder;

  @override
  ConsumerState<RegisterJobWorkDetailScreen> createState() =>
      _RegisterJobWorkDetailScreenState();
}

class _RegisterJobWorkDetailScreenState
    extends ConsumerState<RegisterJobWorkDetailScreen> {
  ChecklistJobWorkReport? _report;
  Object? _error;
  bool _loading = true;
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final adapter = RegisterJobWorkAdapter(
          ref.read(workOrderRepositoryProvider));
      final report = await adapter.resolve(widget.workOrder);
      if (!mounted) return;
      setState(() => _report = report);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorMessage(Object error) {
    if (classifyApiFailure(error) == ApiFailureKind.permission) {
      return 'You do not have permission to view this report. '
          'Ask your depot incharge for access, then retry.';
    }
    return userFacingError(error);
  }

  Future<void> _downloadPdf() async {
    final report = _report;
    if (report == null) return;
    setState(() => _generatingPdf = true);
    try {
      final doc = await JobWorkReportPdfService.build(
        report,
        photos: const {},
        generatedAt: DateTime.now(),
      );
      final bytes = await doc.save();
      if (!mounted) return;
      // Same OS print/share sheet as the Job Work report — the mobile
      // equivalent of web's window.print().
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: '${report.ticket}_Register.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not generate the PDF. ${userFacingError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.workOrder;
    if (!sessionAllows(sessionOf(ref), 'reports.view')) {
      return Scaffold(
        appBar: AppBar(title: Text(order.displayReference)),
        body: const PermissionDeniedView(),
      );
    }

    final dateStr = order.reportCompletedAt != null
        ? DateFormat('dd/MM/yyyy')
            .format(order.reportCompletedAt!.toLocal())
        : 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: Text(order.displayReference),
        actions: [
          if (_report != null && canExportPdf(sessionOf(ref)))
            IconButton(
              key: const Key('action_download_register_pdf'),
              icon: _generatingPdf
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf_outlined),
              tooltip: 'Download PDF',
              onPressed: _generatingPdf ? null : _downloadPdf,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 48,
                            color: context.gssms.danger.foreground),
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage(_error!),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: context.gssms.textSecondary),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          key: const Key('register_detail_retry_button'),
                          onPressed: _resolve,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    SectionCard(
                      children: [
                        Text(
                          order.title?.trim().isNotEmpty == true
                              ? order.title!
                              : order.displayReference,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: GssmsSpacing.s8),
                        InfoRow(
                            label: 'Job Work',
                            value: order.displayReference),
                        InfoRow(
                          label: 'Location',
                          value: _report?.station ?? order.stationName,
                          emptyText: order.depotName ?? 'Location not set',
                        ),
                        InfoRow(
                          label: 'Schedule',
                          value: _report?.schedule,
                          emptyText: order.scheduleCategory,
                        ),
                        InfoRow(
                            label: 'Date of Completion', value: dateStr),
                        if (order.assignedToName != null)
                          InfoRow(
                              label: 'Technician',
                              value: order.assignedToName),
                        InfoRow(
                          label: 'Checklist Groups',
                          value: '${_report?.groups.length ?? 0}',
                        ),
                        InfoRow(
                          label: 'Deficiencies',
                          value: '${_report?.deficiencies.length ?? 0}',
                        ),
                      ],
                    ),
                    const SizedBox(height: GssmsSpacing.s24),
                  ],
                ),
    );
  }
}
