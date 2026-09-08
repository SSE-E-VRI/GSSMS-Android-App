import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_state.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/work_order_navigation.dart';
import 'package:intl/intl.dart';

/// Read-only detail view for one logged inspection, plus the Convert to Job
/// Work action web offers from the same place.
///
/// Mirrors web's "Inspection Details" view modal (InspectionListView.jsx)
/// field for field: reference number, date, title, notes, location,
/// inspected-by, and — once converted — a link to the resulting Work Order.
/// There is no edit endpoint on the backend for inspections, so this stays
/// display-only rather than reopening the create form.
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convert to Job Work'),
        content: const Text(
          'Are you sure you want to convert this inspection to a Job Work?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Convert')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _converting = true);
    try {
      final result = await ref
          .read(inspectionRepositoryProvider)
          .convertToWorkOrder(_inspection.id);
      if (!mounted) return;
      final workOrderId = result['work_order_id'] as int?;
      setState(() {
        _converting = false;
        _inspection = Inspection(
          id: _inspection.id,
          inspectionNumber: _inspection.inspectionNumber,
          title: _inspection.title,
          description: _inspection.description,
          status: InspectionStatus.converted,
          priority: _inspection.priority,
          stationId: _inspection.stationId,
          stationName: _inspection.stationName,
          depotId: _inspection.depotId,
          depotName: _inspection.depotName,
          assetId: _inspection.assetId,
          assetName: _inspection.assetName,
          scheduledDate: _inspection.scheduledDate,
          completedDate: _inspection.completedDate,
          createdAt: _inspection.createdAt,
          reportedByName: _inspection.reportedByName,
          isConverted: true,
          workOrderId: workOrderId,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Converted successfully. Job Work created.')),
      );
      // Stay on this screen — it now shows the converted badge and a link to
      // the new Work Order, same as web leaves the record visible rather than
      // navigating away underneath the user. The list behind this screen
      // re-fetches unconditionally once the user backs out (see
      // InspectionListScreen), so its own "Converted" chip catches up then.
    } catch (e) {
      if (!mounted) return;
      setState(() => _converting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Failed to convert inspection: ${workOrderReadableError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final session = authState is Authenticated ? authState.session : null;

    // RBAC-04: this screen is only ever pushed from InspectionListScreen,
    // which already gates `inspections.view` — but a permission revoked
    // mid-session (a refreshed JWT with a narrower `permissions` claim)
    // must not leave an already-pushed detail route rendering stale data.
    if (!sessionAllows(session, 'inspections.view')) {
      return Scaffold(
        appBar: AppBar(title: Text(_inspection.inspectionNumber)),
        body: const PermissionDeniedView(),
      );
    }

    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final inspection = _inspection;

    return Scaffold(
      appBar: AppBar(title: Text(inspection.inspectionNumber)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  inspection.title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              _buildPriorityBadge(inspection.priority),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatusBadge(inspection),
          const SizedBox(height: 20),
          _sectionCard(
            children: [
              _field('Reference ID', '#${inspection.id}'),
              _field(
                'Date',
                inspection.scheduledDate != null
                    ? dateFormat.format(inspection.scheduledDate!)
                    : (inspection.createdAt != null
                        ? dateFormat.format(inspection.createdAt!)
                        : '—'),
              ),
              if (inspection.reportedByName != null)
                _field('Inspected By', inspection.reportedByName!),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            children: [
              _fieldLabel('Notes'),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  (inspection.description == null ||
                          inspection.description!.isEmpty)
                      ? 'No notes provided.'
                      : inspection.description!,
                  style: const TextStyle(
                      fontSize: 14, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            children: [
              _field(
                'Location',
                inspection.stationName ??
                    inspection.depotName ??
                    'Location N/A',
              ),
              _field('Asset', inspection.assetName ?? '—'),
              if (inspection.completedDate != null)
                _field(
                    'Completed', dateFormat.format(inspection.completedDate!)),
            ],
          ),
          if (inspection.isConverted &&
              inspection.workOrderId != null &&
              sessionAllows(session, 'maintenance.view')) ...[
            const SizedBox(height: 12),
            _sectionCard(
              children: [
                _fieldLabel('Job Work'),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const Key('view_linked_work_order'),
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('View Linked Job Work'),
                  onPressed: () {
                    openWorkOrderGuarded(
                      context: context,
                      session: session,
                      workOrderId: inspection.workOrderId!,
                    );
                  },
                ),
              ],
            ),
          ],
        ],
      ),
      bottomNavigationBar: _canConvert(session)
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton.icon(
                  key: const Key('convert_to_work_order_button'),
                  onPressed: _converting ? null : _confirmConvert,
                  icon: _converting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.play_arrow),
                  label:
                      Text(_converting ? 'Converting…' : 'Convert to Job Work'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.railwayGreen,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: AppTheme.textSecondary,
        letterSpacing: 0.4,
      ),
    );
  }

  Widget _field(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel(label),
          const SizedBox(height: 4),
          Text(value,
              style:
                  const TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildPriorityBadge(InspectionPriority priority) {
    final color = _priorityColor(priority);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        priority.displayName,
        style:
            TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildStatusBadge(Inspection inspection) {
    final color = _statusColor(inspection);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(
        inspection.isConverted
            ? 'Converted to Work Order'
            : inspection.status.displayName,
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _priorityColor(InspectionPriority priority) {
    switch (priority) {
      case InspectionPriority.critical:
        return Colors.red.shade900;
      case InspectionPriority.high:
        return AppTheme.errorRed;
      case InspectionPriority.medium:
        return Colors.orange.shade700;
      case InspectionPriority.low:
        return Colors.green;
    }
  }

  // Mirrors the list screen's chip colours: converted grey, completed green,
  // in-progress blue, pending amber.
  Color _statusColor(Inspection inspection) {
    if (inspection.isConverted) return AppTheme.textSecondary;
    switch (inspection.status) {
      case InspectionStatus.pending:
        return AppTheme.warningAmber;
      case InspectionStatus.inProgress:
        return AppTheme.railwayBlue;
      case InspectionStatus.completed:
        return AppTheme.railwayGreen;
      case InspectionStatus.converted:
        return AppTheme.textSecondary;
      case InspectionStatus.cancelled:
      case InspectionStatus.unknown:
        return AppTheme.textSecondary;
    }
  }
}
