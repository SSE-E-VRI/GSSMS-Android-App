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
          Icon(Icons.keyboard_alt_outlined, color: AppTheme.railwayBlue),
          SizedBox(width: 8),
          Text('Enter Asset Code'),
        ],
      ),
      content: TextField(
        key: const Key('manual_code_input'),
        controller: _codeController,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        autocorrect: false,
        enableSuggestions: false,
        keyboardType: TextInputType.text,
        decoration: const InputDecoration(
          labelText: 'Asset / Serial Code',
          hintText: 'e.g. TR-VRI-01 or AST-101',
          border: OutlineInputBorder(),
          isDense: true,
        ),
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
