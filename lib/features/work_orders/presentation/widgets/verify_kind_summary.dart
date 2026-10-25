import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/execution_widgets.dart';

/// Read-only summary of what the technician recorded for non-checklist Job
/// Work modes (COMPLAINT / RECTIFICATION / INSPECTION). Renders nothing for
/// CHECKLIST mode.
class VerifyKindSummary extends StatelessWidget {
  const VerifyKindSummary({super.key, required this.workspace});

  final VerificationWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    switch (workspace.mode) {
      case 'COMPLAINT':
        return _complaint(context, workspace.complaintExecution);
      case 'RECTIFICATION':
        return _rectification(context, workspace.rectification);
      case 'INSPECTION':
        return _inspection(context, workspace.inspectionExecution);
      default:
        return const SizedBox.shrink();
    }
  }

  static Widget _photos(List<ExecutionPhoto> photos) {
    if (photos.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: GssmsSpacing.s8),
      child: ExecutionPhotoGrid(
        photos: photos,
        canManage: false,
        busy: false,
        onAdd: (_) {},
        onDelete: (_) {},
      ),
    );
  }

  static Widget _label(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(bottom: GssmsSpacing.s4),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: context.gssms.textSecondary),
        ),
      );

  static Widget _params(BuildContext context, List<Map<String, String>> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    final tokens = context.gssms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: GssmsSpacing.s8),
        Text('Parameters', style: Theme.of(context).textTheme.labelLarge),
        for (final p in rows)
          Padding(
            padding: const EdgeInsets.only(top: GssmsSpacing.s4),
            child: Text(
              [
                p['parameter'] ?? '',
                p['value'] ?? '',
                p['unit'] ?? '',
              ].where((s) => s.trim().isNotEmpty).join(' - '),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _complaint(BuildContext context, ComplaintExecution? exec) {
    if (exec == null) {
      return const SectionCard(
        key: Key('verify_kind_complaint'),
        title: 'Complaint execution',
        icon: Icons.report_problem_outlined,
        children: [TextWell(text: null, placeholder: 'No execution recorded.')],
      );
    }
    return SectionCard(
      key: const Key('verify_kind_complaint'),
      title: 'Complaint execution',
      icon: Icons.report_problem_outlined,
      children: [
        _label(context, 'Initial findings'),
        TextWell(text: exec.initialFindings),
        const SizedBox(height: GssmsSpacing.s8),
        _label(context, 'Action taken'),
        TextWell(text: exec.actionTaken),
        const SizedBox(height: GssmsSpacing.s8),
        _label(context, 'Final remarks'),
        TextWell(text: exec.finalRemarks),
        _params(context, exec.parameters),
        _photos(exec.photos),
      ],
    );
  }

  static String _outcomeLabel(String outcome) {
    switch (outcome.toUpperCase()) {
      case 'RECTIFIED':
        return 'Rectified';
      case 'NOT_RECTIFIED':
        return 'Not rectified';
      default:
        return outcome.isEmpty ? 'Pending' : outcome;
    }
  }

  Widget _rectification(BuildContext context, RectificationPayload? payload) {
    if (payload == null) {
      return const SectionCard(
        key: Key('verify_kind_rectification'),
        title: 'Rectification',
        icon: Icons.build_circle_outlined,
        children: [TextWell(text: null, placeholder: 'No execution recorded.')],
      );
    }
    final items = payload.items.where((i) => i.isActive).toList();
    return Column(
      key: const Key('verify_kind_rectification'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) ...[
          SectionCard(
            title: [item.asset, item.checkpoint]
                .where((s) => s.trim().isNotEmpty)
                .join(' - '),
            icon: Icons.build_circle_outlined,
            children: [
              InfoRow(label: 'Finding', value: item.finding),
              InfoRow(label: 'Severity', value: item.severity),
              InfoRow(label: 'Action taken', value: item.actionTaken),
              InfoRow(label: 'Outcome', value: _outcomeLabel(item.outcome)),
              if (item.reason.trim().isNotEmpty)
                InfoRow(label: 'Reason', value: item.reason),
              if (item.sourcePhotos.isNotEmpty)
                Padding(
                  key: Key('verify_rect_source_photos_${item.id}'),
                  padding: const EdgeInsets.only(top: GssmsSpacing.s8),
                  child: InspectorEvidenceStrip(
                    label: 'Original evidence (checklist)',
                    photos: item.sourcePhotos,
                  ),
                ),
              _photos(item.photos),
            ],
          ),
          const SizedBox(height: GssmsSpacing.s12),
        ],
        SectionCard(
          title: 'Summary',
          icon: Icons.fact_check_outlined,
          children: [
            InfoRow(label: 'Final outcome', value: payload.finalRemarks),
            InfoRow(label: 'Other staff', value: payload.otherStaff),
          ],
        ),
      ],
    );
  }

  Widget _inspection(
    BuildContext context,
    PointwiseInspectionExecution? exec,
  ) {
    final points = exec?.points ?? const <InspectionPointExecutionEntry>[];
    final general = exec?.generalEvidencePhotos ?? const <ExecutionPhoto>[];
    final executionPhotos = exec?.executionPhotos ?? const <ExecutionPhoto>[];
    // The inspector's own photos, as the web Verify view and report show
    // them: on the server a point's inspection evidence counts as its
    // Before photo, so the verifier must be able to see it.
    final generalCard = general.isEmpty
        ? null
        : SectionCard(
            key: const Key('verify_inspection_general_evidence'),
            title: 'Inspection evidence',
            icon: Icons.camera_alt_outlined,
            children: [
              InspectorEvidenceStrip(label: 'General photos', photos: general),
            ],
          );
    if (points.isEmpty) {
      return Column(
        key: const Key('verify_kind_inspection'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (generalCard != null) ...[
            generalCard,
            const SizedBox(height: GssmsSpacing.s12),
          ],
          SectionCard(
            title: 'Inspection points',
            icon: Icons.fact_check_outlined,
            children: [
              if (executionPhotos.isEmpty)
                const TextWell(text: null, placeholder: 'No points recorded.')
              else
                // A legacy (non-pointwise) Job Work keeps its Before/After
                // on the execution itself.
                _photos(executionPhotos),
            ],
          ),
        ],
      );
    }
    return Column(
      key: const Key('verify_kind_inspection'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (generalCard != null) ...[
          generalCard,
          const SizedBox(height: GssmsSpacing.s12),
        ],
        for (final p in points) ...[
          SectionCard(
            title: 'Point #${p.pointNumber}',
            icon: Icons.fact_check_outlined,
            children: [
              InfoRow(label: 'Observation', value: p.observation),
              InfoRow(label: 'Findings', value: p.initialFindings),
              InfoRow(label: 'Action', value: p.actionTaken),
              InfoRow(label: 'Remarks', value: p.finalRemarks),
              InfoRow(
                label: 'Corrective action performed',
                value: p.correctiveActionPerformed ? 'Yes' : 'No',
              ),
              _params(context, p.technicalParameters),
              if (p.inspectionEvidencePhotos.isNotEmpty)
                Padding(
                  key: Key('verify_point_inspector_photos_${p.pointJobWorkId}'),
                  padding: const EdgeInsets.only(top: GssmsSpacing.s8),
                  child: InspectorEvidenceStrip(
                    label: 'From the inspection',
                    photos: p.inspectionEvidencePhotos,
                  ),
                ),
              _photos(p.photos),
            ],
          ),
          const SizedBox(height: GssmsSpacing.s12),
        ],
      ],
    );
  }
}
