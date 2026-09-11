import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/core/widgets/sticky_action_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/inspections/presentation/inspection_status_style.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_navigation.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_status_style.dart';
import 'package:intl/intl.dart';

/// Read-only detail view for one logged inspection, plus the Convert to Job
/// Work action web offers from the same place.
///
/// Mirrors web's "Inspection Details" view (InspectionListView.jsx):
/// reference, date, title, notes, location, inspected-by, and — once
/// converted — a link to the resulting Job Work. There is no edit endpoint
/// for inspections, so this stays display-only.
class InspectionDetailScreen extends ConsumerStatefulWidget {
  const InspectionDetailScreen({super.key, required this.inspection});

  final Inspection inspection;

  @override
  ConsumerState<InspectionDetailScreen> createState() =>
      _InspectionDetailScreenState();
}

class _InspectionDetailScreenState
    extends ConsumerState<InspectionDetailScreen> {
  late Inspection _inspection;
  bool _converting = false;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _inspection = widget.inspection;
  }

  /// Conversion is gated to the depot roles ConversionService actually accepts.
  bool _canConvert(UserSession? session) {
    if (session == null) return false;
    if (_inspection.isConverted) return false;
    return canConvertInspection(session);
  }

  Future<void> _confirmConvert() async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Convert to Job Work?',
      icon: Icons.build_circle_outlined,
      message:
          'A Job Work will be created from inspection ${_inspection.reference} '
          'and the inspection will be marked Converted. From then on its '
          'progress is tracked through that Job Work.',
      confirmLabel: 'Convert',
      confirmKey: const Key('confirm_convert_button'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _converting = true);
    try {
      final result = await ref
          .read(inspectionRepositoryProvider)
          .convertToWorkOrder(_inspection.id);
      if (!mounted) return;
      final workOrderId = result['work_order_id'] as int?;
      setState(() {
        _converting = false;
        _inspection = _inspection.markConverted(workOrderId: workOrderId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Converted. A Job Work has been created.')),
      );
      // Stay on this screen — it now shows the converted badge and a link to
      // the new Job Work. The list behind re-fetches when the user backs out.
    } catch (e) {
      if (!mounted) return;
      setState(() => _converting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not convert: ${workOrderReadableError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final session = authState is Authenticated ? authState.session : null;
    final inspection = _inspection;
    final title = 'Inspection ${inspection.reference}';

    // RBAC-04: a permission revoked mid-session (a refreshed JWT with a
    // narrower `permissions` claim) must not leave an already-pushed detail
    // route rendering stale data.
    if (!sessionAllows(session, 'inspections.view')) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const PermissionDeniedView(),
      );
    }

    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final when = inspection.inspectionDate ?? inspection.createdAt;
    final inspector = [
      inspection.createdByName,
      if (inspection.createdByDesignation != null &&
          inspection.createdByDesignation!.trim().isNotEmpty)
        '(${inspection.createdByDesignation})',
    ].whereType<String>().join(' ');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(GssmsSpacing.s16),
        children: [
          SectionCard(
            children: [
              Wrap(
                spacing: GssmsSpacing.s8,
                runSpacing: GssmsSpacing.s8,
                children: [
                  InspectionStatusChip(inspection: inspection),
                  InspectionJobWorkChip(inspection: inspection),
                ],
              ),
              const SizedBox(height: GssmsSpacing.s12),
              Text(inspection.title, style: textTheme.titleLarge),
              const SizedBox(height: GssmsSpacing.s4),
              Text(
                when != null
                    ? 'Inspected ${_dateFormat.format(when)}'
                    : 'Inspection date not available',
                style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: GssmsSpacing.s12),
          SectionCard(
            title: 'Notes',
            icon: Icons.notes_outlined,
            children: [
              TextWell(text: inspection.notes, placeholder: 'No notes provided.'),
            ],
          ),
          const SizedBox(height: GssmsSpacing.s12),
          SectionCard(
            title: 'Details',
            icon: Icons.info_outline,
            children: [
              InfoRow(label: 'Reference ID', value: inspection.reference),
              InfoRow(
                label: 'Location',
                value: inspection.locationLabel,
                emptyText: 'Location not set',
              ),
              if (inspection.depotName != null)
                InfoRow(label: 'Depot', value: inspection.depotName),
              if (inspector.isNotEmpty)
                InfoRow(label: 'Inspected By', value: inspector),
            ],
          ),
          if (inspection.isConverted) ...[
            const SizedBox(height: GssmsSpacing.s12),
            _LinkedJobWorkCard(
              inspection: inspection,
              onOpen: inspection.workOrderId != null &&
                      sessionAllows(session, 'maintenance.view')
                  ? () => openWorkOrderGuarded(
                        context: context,
                        session: session,
                        workOrderId: inspection.workOrderId!,
                      )
                  : null,
            ),
          ],
          const SizedBox(height: GssmsSpacing.s24),
        ],
      ),
      bottomNavigationBar: _canConvert(session)
          ? StickyActionBar(
              child: FilledButton.icon(
                key: const Key('convert_to_work_order_button'),
                onPressed: _converting ? null : _confirmConvert,
                icon: _converting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.build_circle_outlined),
                label: Text(_converting ? 'Converting…' : 'Convert to Job Work'),
              ),
            )
          : null,
    );
  }
}

class _LinkedJobWorkCard extends StatelessWidget {
  const _LinkedJobWorkCard({required this.inspection, this.onOpen});

  final Inspection inspection;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = linkedJobWorkProgress(inspection.workOrderStatus);
    return SectionCard(
      title: 'Linked Job Work',
      icon: Icons.link,
      children: [
        if (inspection.workOrderId != null)
          InfoRow(label: 'Job Work', value: 'Job Work #${inspection.workOrderId}'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: GssmsSpacing.s6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: StatusChip(
              label: progress.label,
              tone: progress.tone,
              icon: progress.icon,
            ),
          ),
        ),
        if (onOpen != null) ...[
          const SizedBox(height: GssmsSpacing.s8),
          OutlinedButton.icon(
            key: const Key('view_linked_work_order'),
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new),
            label: const Text('View Linked Job Work'),
          ),
        ],
      ],
    );
  }
}
