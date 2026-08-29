import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Placeholder for the Energy & Solar module.
///
/// The EB clerk meter-photo and bill-upload workflow is blocked on
/// backend GAP-04 (Attachment model) and GAP-06. Until that lands the
/// mobile app honestly reports the state rather than pretending the
/// feature works — fixing the misleading SnackBar the plan flagged
/// in `home_screen.dart`.
class EnergyPlaceholderScreen extends StatelessWidget {
  const EnergyPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Energy & Solar')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(height: 32),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.1),
                borderRadius: BorderRadius.circular(48),
              ),
              child: const Icon(Icons.solar_power_outlined, size: 56, color: Colors.indigo),
            ),
            const SizedBox(height: 24),
            const Text(
              'Energy Module — Coming Soon',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textDark),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Meter photography, bill upload and consumption trends are planned for Phase 5. '
              'They depend on backend work that has not yet shipped:',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Text(
                        'Pending backend prerequisites',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '• GAP-04 — Attachment model for meter/bill photos\n'
                    '• GAP-06 — Conflict signal for offline energy readings\n'
                    'Until these land, energy data remains read-only on the web dashboard.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade800, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back to Operations'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'If you need to record a meter reading urgently, please use the web portal.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
