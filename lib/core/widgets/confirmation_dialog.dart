import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Confirmation for an irreversible or workflow-changing action.
///
/// [message] must state the consequence in workflow terms ("A Job Work will be
/// created and this complaint will be marked Converted"), not "Are you sure?".
/// Returns true only when the user confirms.
Future<bool> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData? icon,
  bool destructive = false,
  Key? confirmKey,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final tokens = ctx.gssms;
      return AlertDialog(
        icon: icon == null
            ? null
            : Icon(icon, color: destructive ? tokens.danger.foreground : null),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(cancelLabel),
          ),
          FilledButton(
            key: confirmKey,
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: tokens.danger.solid,
                    foregroundColor: tokens.danger.onSolid,
                  )
                : null,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      );
    },
  );
  return result == true;
}
