import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/domain/rbac.dart';
import 'package:gssms_mobile/features/auth/presentation/widgets/permission_denied_view.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';
import 'package:gssms_mobile/features/reports/services/register_entry_pdf_service.dart';

class RegisterEntryDetailScreen extends ConsumerStatefulWidget {
  const RegisterEntryDetailScreen({super.key, required this.entry});

  final MaintenanceRegisterEntry entry;

  @override
  ConsumerState<RegisterEntryDetailScreen> createState() =>
      _RegisterEntryDetailScreenState();
}

class _RegisterEntryDetailScreenState
    extends ConsumerState<RegisterEntryDetailScreen> {
  bool _generatingPdf = false;

  Future<void> _downloadPdf() async {
    setState(() => _generatingPdf = true);
    try {
      final doc = await RegisterEntryPdfService.build(widget.entry);
      final bytes = await doc.save();
      if (!mounted) return;
      // Hands the PDF to the OS print/share sheet — the mobile equivalent of
      // web's window.print(), which offers "Save as PDF" as one of its own
      // destinations. There is no separate "download" affordance on Android
      // outside that sheet.
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: '${widget.entry.masterName}_Register.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to generate PDF: $e')),
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;

    // RBAC-04: this screen is only ever pushed from ReportsScreen, which
    // already gates `reports.view` — but a permission revoked mid-session
    // (a refreshed JWT with a narrower `permissions` claim) must not leave
    // an already-pushed detail route rendering stale data.
    if (!sessionAllows(sessionOf(ref), 'reports.view')) {
      return Scaffold(
        appBar: AppBar(title: Text(entry.masterName)),
        body: const PermissionDeniedView(),
      );
    }

    final dateStr = entry.date != null ? DateFormat('dd/MM/yyyy').format(entry.date!) : 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: Text(entry.masterName),
        actions: [
          if (canExportPdf(sessionOf(ref)))
            IconButton(
            key: const Key('action_download_register_pdf'),
            icon: _generatingPdf
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            tooltip: 'Download PDF',
            onPressed: _generatingPdf ? null : _downloadPdf,
          ),
        ],
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
            ...entry.groupedByAsset.map(_buildAssetGroupCard),
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

  /// One card per Asset/Equipment, holding a Checkpoint/Parameter | Status |
  /// Action Taken table for its rows — mirrors web's FormPreview grouping
  /// (one table per asset group) rather than a flat list of checklist rows.
  Widget _buildAssetGroupCard(AssetChecklistGroup group) {
    return Card(
      key: Key('asset_group_${group.assetName}'),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: AppTheme.backgroundLight,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              group.assetName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.railwayBlue),
            ),
          ),
          _buildChecklistTable(group.items),
        ],
      ),
    );
  }

  Widget _buildChecklistTable(List<RegisterLineItem> items) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2.4),
        1: FlexColumnWidth(1.4),
        2: FlexColumnWidth(1.8),
      },
      border: TableBorder(
        horizontalInside: BorderSide(color: Colors.grey.shade300),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(color: Colors.grey.shade100),
          children: const [
            _HeaderCell('Checkpoint/Parameter'),
            _HeaderCell('Status'),
            _HeaderCell('Action Taken'),
          ],
        ),
        for (final item in items)
          TableRow(
            children: [
              _BodyCell(
                item.inspection,
                subtitle: (item.value != null && item.value!.isNotEmpty) ? 'Reading: ${item.value}' : null,
              ),
              _BodyCell(
                item.statusLabel ?? item.status ?? '-',
                color: _statusColor(item.status),
              ),
              _BodyCell(
                (item.action != null && item.action!.isNotEmpty) ? item.action! : '-',
                subtitle: (item.remarks != null && item.remarks!.isNotEmpty) ? item.remarks : null,
              ),
            ],
          ),
      ],
    );
  }

  Color _statusColor(String? status) {
    if (status == null) return AppTheme.railwayGreen;
    final lower = status.toLowerCase();
    if (lower.contains('dirty') || lower.contains('defect') || lower.contains('fail') || lower.contains('abnormal')) {
      return AppTheme.errorRed;
    }
    return AppTheme.railwayGreen;
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
      ),
    );
  }
}

class _BodyCell extends StatelessWidget {
  const _BodyCell(this.text, {this.subtitle, this.color});
  final String text;
  final String? subtitle;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color ?? AppTheme.textPrimary),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: const TextStyle(fontSize: 10, color: AppTheme.textMuted)),
          ],
        ],
      ),
    );
  }
}
