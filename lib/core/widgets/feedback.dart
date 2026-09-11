import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Shows a transient message with a semantic tone.
///
/// Neutral uses the theme's default snackbar; the other tones use the tone's
/// solid/onSolid pair so text keeps AA contrast in both themes (a raw red
/// background with default white text does not).
void showGssmsSnackBar(
  BuildContext context,
  String message, {
  GssmsTone tone = GssmsTone.neutral,
  SnackBarAction? action,
  Duration duration = const Duration(seconds: 4),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final palette = context.gssms.tone(tone);
  final toned = tone != GssmsTone.neutral;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: toned ? TextStyle(color: palette.onSolid) : null,
        ),
        backgroundColor: toned ? palette.solid : null,
        action: action,
        duration: duration,
      ),
    );
}
