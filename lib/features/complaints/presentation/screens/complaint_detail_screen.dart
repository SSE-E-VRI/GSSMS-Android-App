import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:intl/intl.dart';

/// Read-only detail view for one logged complaint.
///
/// Mirrors web's "Complaint Details" view modal (ComplaintListView.jsx) field
/// for field: reference number, date logged, title, description, location,
/// asset, and current status. There is no edit endpoint on the backend for
/// complaints — web's own detail view is view-only too — so this screen is
/// display-only rather than a reopened create form.
class ComplaintDetailScreen extends StatelessWidget {
  const ComplaintDetailScreen({super.key, required this.complaint});

  final Complaint complaint;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd MMM yyyy, hh:mm a');

    return Scaffold(
      appBar: AppBar(title: Text(complaint.complaintNumber)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  complaint.title,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              _buildSeverityBadge(complaint.severity),
            ],
          ),
          const SizedBox(height: 16),
          _buildStatusBadge(complaint.status),
          const SizedBox(height: 20),
          _sectionCard(
            children: [
              _field('Reference ID', '#${complaint.id}'),
              _field(
                'Date Logged',
                complaint.createdAt != null ? dateFormat.format(complaint.createdAt!) : '—',
              ),
              if (complaint.reportedByName != null)
                _field('Reported By', complaint.reportedByName!),
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
                  (complaint.description == null || complaint.description!.isEmpty)
                      ? 'No description provided.'
                      : complaint.description!,
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
                complaint.stationName ?? complaint.depotName ?? 'Location N/A',
              ),
              _field('Asset', complaint.assetName ?? '—'),
              if (complaint.resolvedAt != null)
                _field('Resolved', dateFormat.format(complaint.resolvedAt!)),
            ],
          ),
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

  // Mirrors the web view modal's status badge colours (ComplaintListView.jsx
  // view modal): OPEN/PENDING amber, IN_PROGRESS blue, RESOLVED green,
  // everything else (CLOSED/REJECTED/UNKNOWN) grey.
  Color _statusColor(ComplaintStatus status) {
    switch (status) {
      case ComplaintStatus.open:
        return AppTheme.warningAmber;
      case ComplaintStatus.inProgress:
        return AppTheme.railwayBlue;
      case ComplaintStatus.resolved:
        return AppTheme.railwayGreen;
      case ComplaintStatus.closed:
      case ComplaintStatus.rejected:
      case ComplaintStatus.unknown:
        return AppTheme.textSecondary;
    }
  }
}
