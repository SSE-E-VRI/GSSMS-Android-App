import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';

class RegisterEntryDetailScreen extends StatelessWidget {
  const RegisterEntryDetailScreen({super.key, required this.entry});

  final MaintenanceRegisterEntry entry;

  @override
  Widget build(BuildContext context) {
    final dateStr = entry.date != null ? DateFormat('dd/MM/yyyy').format(entry.date!) : 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.masterName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.masterName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.railwayBlue),
                  ),
                  const SizedBox(height: 8),
                  _buildMetaRow('Date of Completion', dateStr),
                  if (entry.depotName != null) _buildMetaRow('Depot', entry.depotName!),
                  if (entry.stationName != null) _buildMetaRow('Location / Station', entry.stationName!),
                  if (entry.technician != null) _buildMetaRow('Technician', entry.technician!),
                  if (entry.supervisor != null) _buildMetaRow('Supervisor', entry.supervisor!),
                  if (entry.remarks != null && entry.remarks!.isNotEmpty)
                    _buildMetaRow('Remarks', entry.remarks!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Checklist Register Items',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.railwayBlue),
          ),
          const SizedBox(height: 10),
          if (entry.items.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No recorded line items found for this entry.', style: TextStyle(color: AppTheme.textSecondary)),
              ),
            )
          else
            ...entry.items.map((item) => _buildItemCard(item)),
        ],
      ),
    );
  }

  Widget _buildMetaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(RegisterLineItem item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.inspection,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getStatusColor(item.status).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.statusLabel ?? item.status ?? 'OK',
                    style: TextStyle(color: _getStatusColor(item.status), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('Equipment: ${item.assetName}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            if (item.value != null && item.value!.isNotEmpty)
              Text('Reading: ${item.value}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            if (item.action != null && item.action!.isNotEmpty)
              Text('Action Taken: ${item.action}', style: const TextStyle(fontSize: 12, color: AppTheme.railwayBlue)),
            if (item.remarks != null && item.remarks!.isNotEmpty)
              Text('Remarks: ${item.remarks}', style: const TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String? status) {
    if (status == null) return AppTheme.railwayGreen;
    final lower = status.toLowerCase();
    if (lower.contains('dirty') || lower.contains('defect') || lower.contains('fail') || lower.contains('abnormal')) {
      return AppTheme.errorRed;
    }
    return AppTheme.railwayGreen;
  }
}
