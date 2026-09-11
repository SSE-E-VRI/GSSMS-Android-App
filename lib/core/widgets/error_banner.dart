import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Inline error strip for the stale-data-with-banner pattern: keep the
/// last-good list visible and show this banner above it with Retry.
///
/// [message] must already be user-facing (see `userFacingError`).
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
    this.icon = Icons.cloud_off,
  });

  final String message;
  final VoidCallback onRetry;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.gssms.danger;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: palette.background,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            GssmsSpacing.s16,
            GssmsSpacing.s4,
            GssmsSpacing.s4,
            GssmsSpacing.s4,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: palette.foreground),
              const SizedBox(width: GssmsSpacing.s8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: palette.foreground,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: palette.foreground),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
