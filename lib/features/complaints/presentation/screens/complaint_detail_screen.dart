import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/data/lookup_options_service.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/core/widgets/confirmation_dialog.dart';
import 'package:gssms_mobile/core/widgets/section_card.dart';
import 'package:gssms_mobile/core/widgets/status_chip.dart';
import 'package:gssms_mobile/core/widgets/sticky_action_bar.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/complaint_status_style.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_navigation.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_status_style.dart';
import 'package:intl/intl.dart';

/// Read-only detail view for one logged complaint, plus the Convert to Job
/// Work action web offers from the same place.
///
/// Mirrors web's "Complaint Details" view (ComplaintListView.jsx): reference,
/// date logged, title, description, location, asset, current status and the
/// linked Job Work. There is no edit endpoint for complaints on web either, so
/// this screen stays display-only apart from the conversion action.
class ComplaintDetailScreen extends ConsumerStatefulWidget {
  const ComplaintDetailScreen({super.key, required this.complaint});

  final Complaint complaint;

  @override
  ConsumerState<ComplaintDetailScreen> createState() =>
      _ComplaintDetailScreenState();
}

class _ComplaintDetailScreenState extends ConsumerState<ComplaintDetailScreen> {
  late Complaint _complaint;
  bool _converting = false;

  static final DateFormat _dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

  @override
  void initState() {
    super.initState();
    _complaint = widget.complaint;
  }

  /// Conversion is gated to the depot roles ConversionService actually
  /// accepts — same `_validate_scope` gate as inspections.
  bool _canConvert(UserSession? session) {
    if (session == null) return false;
    if (_complaint.isConverted) return false;
    return canConvertComplaint(session);
  }

  Future<void> _confirmConvert() async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Convert to Job Work?',
      icon: Icons.build_circle_outlined,
      message:
          'A Job Work will be created from complaint ${_complaint.reference} and '
          'the complaint will be marked Converted. From then on its progress '
          'is tracked through that Job Work.',
      confirmLabel: 'Convert',
      confirmKey: const Key('confirm_convert_button'),
    );
    if (!confirmed || !mounted) return;

    setState(() => _converting = true);
    try {
      final result = await ref
          .read(complaintRepositoryProvider)
          .convertToWorkOrder(_complaint.id);
      if (!mounted) return;
      final workOrderId = result['work_order_id'] as int?;
      setState(() {
        _converting = false;
        _complaint = _complaint.markConverted(workOrderId: workOrderId);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Converted. A Job Work has been created.'),
          action: workOrderId == null ||
                  !sessionAllows(sessionOf(ref), 'maintenance.view')
              ? null
              : SnackBarAction(
                  label: 'View',
                  onPressed: () => _openJobWork(workOrderId),
                ),
        ),
      );
      // Stay on this screen: it now shows the converted state, and the list
      // behind it re-fetches when the user backs out.
    } catch (e) {
      if (!mounted) return;
      setState(() => _converting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not convert: ${workOrderReadableError(e)}'),
        ),
      );
    }
  }

  void _openJobWork(int workOrderId) {
    openWorkOrderGuarded(
      context: context,
      session: sessionOf(ref),
      workOrderId: workOrderId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = 'Complaint ${_complaint.reference}';
    if (!sessionAllows(sessionOf(ref), 'complaints.view')) {
      return Scaffold(
        appBar: AppBar(title: Text(title)),
        body: const PermissionDeniedView(),
      );
    }

    final session = sessionOf(ref);
    final tokens = context.gssms;
    final textTheme = Theme.of(context).textTheme;
    final department = _complaint.department;
    final departmentOptions = department == null
        ? null
        : ref.watch(lookupOptionsProvider('complaint_department')).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(GssmsSpacing.s16),
        children: [
          // WHAT IS THIS / WHAT STATE IS IT IN — first thing on screen.
          SectionCard(
            children: [
              Wrap(
                spacing: GssmsSpacing.s8,
                runSpacing: GssmsSpacing.s8,
                children: [
                  ComplaintStatusChip(complaint: _complaint),
                  ComplaintJobWorkChip(complaint: _complaint),
                ],
              ),
              const SizedBox(height: GssmsSpacing.s12),
              Text(_complaint.title, style: textTheme.titleLarge),
              const SizedBox(height: GssmsSpacing.s4),
              Text(
                _complaint.createdAt != null
                    ? 'Logged ${_dateFormat.format(_complaint.createdAt!)}'
                    : 'Date logged not available',
                style: textTheme.bodySmall?.copyWith(color: tokens.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: GssmsSpacing.s12),
          SectionCard(
            title: 'Description',
            icon: Icons.notes_outlined,
            children: [
              TextWell(
                text: _complaint.description,
                placeholder: 'No description provided.',
              ),
            ],
          ),
          const SizedBox(height: GssmsSpacing.s12),
          SectionCard(
            title: 'Details',
            icon: Icons.info_outline,
            children: [
              InfoRow(label: 'Reference ID', value: _complaint.reference),
              if (department != null)
                InfoRow(
                  label: 'Department',
                  value: lookupLabel(departmentOptions, department),
                ),
              InfoRow(
                label: 'Location',
                value: _complaint.locationLabel,
                emptyText: 'Location not set',
              ),
              if (_complaint.depotName != null)
                InfoRow(label: 'Depot', value: _complaint.depotName),
              InfoRow(label: 'Asset', value: _complaint.assetUniqueId),
            ],
          ),
          if (_complaint.isConverted) ...[
            const SizedBox(height: GssmsSpacing.s12),
            _LinkedJobWorkCard(
              complaint: _complaint,
              onOpen: _complaint.workOrderId == null ||
                      !sessionAllows(session, 'maintenance.view')
                  ? null
                  : () => _openJobWork(_complaint.workOrderId!),
            ),
          ],
          const SizedBox(height: GssmsSpacing.s24),
        ],
      ),
      bottomNavigationBar: !_complaint.isConverted && _canConvert(session)
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
  const _LinkedJobWorkCard({required this.complaint, this.onOpen});

  final Complaint complaint;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = linkedJobWorkProgress(complaint.workOrderStatus);
    final reference = complaint.workOrderTicketNumber ??
        (complaint.workOrderId != null ? 'Job Work #${complaint.workOrderId}' : null);
    return SectionCard(
      title: 'Linked Job Work',
      icon: Icons.link,
      children: [
        if (reference != null) InfoRow(label: 'Job Work', value: reference),
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
            key: const Key('view_linked_job_work_button'),
            onPressed: onOpen,
            icon: const Icon(Icons.open_in_new),
            label: const Text('View Linked Job Work'),
          ),
        ],
      ],
    );
  }
}
