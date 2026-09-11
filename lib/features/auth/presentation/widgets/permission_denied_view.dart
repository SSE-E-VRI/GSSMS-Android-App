import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

class PermissionDeniedView extends StatelessWidget {
  const PermissionDeniedView({
    super.key,
    this.message = 'You do not have permission to view this screen.',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 48, color: context.gssms.textSecondary),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: context.gssms.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

void showPermissionDeniedSnackBar(
  BuildContext context, {
  String message = 'You do not have permission to perform this action.',
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: context.gssms.danger.solid,
    ),
  );
}
