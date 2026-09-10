import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:intl/intl.dart';

/// Read-only detail view for one logged complaint, plus the Convert to Job
/// Work action web offers from the same place.
///
/// Mirrors web's "Complaint Details" view modal (ComplaintListView.jsx) field
/// for field: reference number, date logged, title, description, location,
/// asset, and current status. There is no edit endpoint on the backend for
/// complaints — web's own detail view is view-only too — so this screen stays
/// display-only apart from the conversion action.
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Convert to Job Work'),
        content: const Text(
          'Are you sure you want to convert this complaint to a Job Work?',
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
          .read(complaintRepositoryProvider)
          .convertToWorkOrder(_complaint.id);
      if (!mounted) return;
      final workOrderId = result['work_order_id'] as int?;
      setState(() {
        _converting = false;
        _complaint = Complaint(
          id: _complaint.id,
          complaintNumber: _complaint.complaintNumber,
          title: _complaint.title,
          description: _complaint.description,
          status: ComplaintStatus.converted,
          severity: _complaint.severity,
          stationId: _complaint.stationId,
          stationName: _complaint.stationName,
          depotId: _complaint.depotId,
          depotName: _complaint.depotName,
          assetId: _complaint.assetId,
          assetName: _complaint.assetName,
          reportedByName: _complaint.reportedByName,
          createdAt: _complaint.createdAt,
          resolvedAt: _complaint.resolvedAt,
          isConverted: true,
          workOrderId: workOrderId,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Converted successfully. Job Work created.')),
      );
      // Stay on this screen, same reasoning as InspectionDetailScreen: it now
      // shows the converted badge, and the list behind it re-fetches when the
      // user backs out.
    } catch (e) {
      if (!mounted) return;
      setState(() => _converting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Failed to convert complaint: ${workOrderReadableError(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!sessionAllows(sessionOf(ref), 'complaints.view')) {
      return Scaffold(
        appBar: AppBar(title: Text(_complaint.complaintNumber)),
        body: const PermissionDeniedView(),
      );
    }

    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');
    final session = sessionOf(ref);

    return Scaffold(
      appBar: AppBar(title: Text(_complaint.complaintNumber)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _complaint.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              _buildSeverityBadge(_complaint.severity),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatusBadge(_complaint.status),
          const SizedBox(height: 20),
          _sectionCard(
            children: [
              _field('Reference ID', '#${_complaint.id}'),
              _field(
                'Date Logged',
                _complaint.createdAt != null
                    ? dateFormat.format(_complaint.createdAt!)
                    : '—',
              ),
              if (_complaint.reportedByName != null)
                _field('Reported By', _complaint.reportedByName!),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            children: [
              _fieldLabel('Description'),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  (_complaint.description == null ||
                          _complaint.description!.isEmpty)
                      ? 'No description provided.'
                      : _complaint.description!,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            children: [
              _field(
                'Location',
                _complaint.stationName ?? _complaint.depotName ?? 'Location N/A',
              ),
              _field('Asset', _complaint.assetName ?? '—'),
              if (_complaint.resolvedAt != null)
                _field('Resolved', dateFormat.format(_complaint.resolvedAt!)),
            ],
          ),
          if (_complaint.isConverted) ...[
            const SizedBox(height: 12),
            _sectionCard(
              children: [
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: AppTheme.railwayGreen, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _complaint.workOrderId != null
                            ? 'Converted to Job Work #${_complaint.workOrderId}'
                            : 'Converted to Job Work',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else if (_canConvert(session)) ...[
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                key: const Key('convert_to_work_order_button'),
                onPressed: _converting ? null : _confirmConvert,
                icon: _converting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.build_circle_outlined, size: 18),
                label: Text(
                    _converting ? 'Converting...' : 'Convert to Job Work'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.railwayBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
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
          Text(value, style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildSeverityBadge(ComplaintSeverity severity) {
    final color = _severityColor(severity);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        severity.displayName,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildStatusBadge(ComplaintStatus status) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.displayName,
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _severityColor(ComplaintSeverity severity) {
    switch (severity) {
      case ComplaintSeverity.critical:
        return Colors.red.shade900;
      case ComplaintSeverity.high:
        return AppTheme.errorRed;
      case ComplaintSeverity.medium:
        return Colors.orange.shade700;
      case ComplaintSeverity.low:
        return Colors.green;
    }
  }

  // OPEN amber, CONVERTED blue, CLOSED/UNKNOWN grey.
  Color _statusColor(ComplaintStatus status) {
    switch (status) {
      case ComplaintStatus.open:
        return AppTheme.warningAmber;
      case ComplaintStatus.converted:
        return AppTheme.railwayBlue;
      case ComplaintStatus.closed:
      case ComplaintStatus.unknown:
        return AppTheme.textSecondary;
    }
  }
}
