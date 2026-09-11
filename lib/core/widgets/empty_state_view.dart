import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Full-page empty or terminal-error state: icon + title + optional body and
/// action (Retry, Clear filters, …).
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  /// Terminal load failure with a Retry button. [message] must already be
  /// user-facing (see `userFacingError`).
  factory EmptyStateView.error({
    Key? key,
    required String message,
    required VoidCallback onRetry,
    String title = 'Could not load',
  }) {
    return EmptyStateView(
      key: key,
      icon: const _ToneIcon(Icons.cloud_off_outlined, GssmsTone.danger),
      title: title,
      body: message,
      action: OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh),
        label: const Text('Retry'),
      ),
    );
  }

  /// "Nothing here" state. Pass [onClearFilters] when filters/search are
  /// active so the user has a one-tap way back to the full list.
  factory EmptyStateView.noResults({
    Key? key,
    required String title,
    IconData icon = Icons.inbox_outlined,
    String? body,
    VoidCallback? onClearFilters,
  }) {
    return EmptyStateView(
      key: key,
      icon: _ToneIcon(icon, GssmsTone.neutral),
      title: title,
      body: body ??
          (onClearFilters != null
              ? 'Try clearing the filters or widening the date range.'
              : null),
      action: onClearFilters == null
          ? null
          : OutlinedButton.icon(
              key: const Key('empty_state_clear_filters'),
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear filters'),
            ),
    );
  }

  final Widget icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(GssmsSpacing.s24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: GssmsSpacing.s12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            if (body != null && body!.isNotEmpty) ...[
              const SizedBox(height: GssmsSpacing.s8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: AppTheme.mutedText(context),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: GssmsSpacing.s16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _ToneIcon extends StatelessWidget {
  const _ToneIcon(this.icon, this.tone);

  final IconData icon;
  final GssmsTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.gssms.tone(tone);
    return Container(
      padding: const EdgeInsets.all(GssmsSpacing.s16),
      decoration: BoxDecoration(
        color: palette.background,
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 32, color: palette.foreground),
    );
  }
}
