import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Full-page empty or terminal-error state.
///
/// Matches the no-stale-data fallback in
/// `complaint_list_screen.dart` (icon + message + Retry), parameterized as
/// [icon], [title], optional [body], optional [action].
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final Widget icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(GssmsSpacing.s24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(height: GssmsSpacing.s12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (body != null && body!.isNotEmpty) ...[
              const SizedBox(height: GssmsSpacing.s8),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textMuted,
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
