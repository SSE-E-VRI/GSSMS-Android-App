import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

class QrScannerDialog extends StatefulWidget {
  const QrScannerDialog({super.key});

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.qr_code_scanner, color: AppTheme.railwayBlue),
          SizedBox(width: 8),
          Text('Scan or Enter Asset Code'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2, size: 64, color: Colors.white70),
                    SizedBox(height: 8),
                    Text(
                      'Ready to Scan Barcode / QR',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppTheme.railwayGreen, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('manual_code_input'),
            controller: _codeController,
            decoration: const InputDecoration(
              labelText: 'Manual Asset / Serial Code',
              hintText: 'e.g. TR-VRI-01 or AST-101',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          key: const Key('confirm_code_lookup_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.railwayBlue,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final code = _codeController.text.trim();
            if (code.isNotEmpty) {
              Navigator.of(context).pop(code);
            }
          },
          child: const Text('Lookup Asset'),
        ),
      ],
    );
  }
}
