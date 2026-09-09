import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Inline error strip for the stale-data-with-banner pattern.
///
/// Extracted from `complaint_list_screen.dart` (error state when
/// `previousLoaded != null`): keep the last-good list visible and show this
/// banner above it with Retry.
///
/// Uses [AppTheme.statusCritical] (darker than [AppTheme.errorRed]) for text
/// and icon so 12sp metadata copy holds outdoor contrast.
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.statusCritical.withOpacity(0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: GssmsSpacing.s16,
          vertical: GssmsSpacing.s8,
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off,
                size: 18, color: AppTheme.statusCritical),
            const SizedBox(width: GssmsSpacing.s8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: AppTheme.statusCritical,
                      fontWeight: FontWeight.w600,
                    ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
