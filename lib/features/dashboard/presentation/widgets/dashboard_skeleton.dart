import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Static placeholder layout shown while the dashboard loads.
///
/// Follows the same philosophy as [SkeletonList]: static shapes that mirror
/// the loaded dashboard structure (Attention card, Donut chart, Pending actions)
/// to eliminate cumulative layout shift (CLS) without costly per-frame shimmers.
class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading dashboard',
      liveRegion: true,
      child: ExcludeSemantics(
        child: ListView(
          padding: const EdgeInsets.all(GssmsSpacing.s16),
          children: [
            // 1. Attention Required Section
            _card(
              context,
              children: const [
                Row(
                  children: [
                    _SkeletonBar(widthFactor: 0.38, height: 14),
                    SizedBox(width: GssmsSpacing.s8),
                    _SkeletonBar(widthFactor: 0.18, height: 16),
                  ],
                ),
                SizedBox(height: GssmsSpacing.s12),
                _SkeletonBar(widthFactor: 0.85, height: 12),
                SizedBox(height: GssmsSpacing.s8),
                _SkeletonBar(widthFactor: 0.6, height: 12),
              ],
            ),
            const SizedBox(height: GssmsSpacing.s16),

            // 2. Status Donut Chart Section
            _card(
              context,
              children: [
                const _SkeletonBar(widthFactor: 0.4, height: 14),
                const SizedBox(height: GssmsSpacing.s16),
                Center(
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: context.gssms.border,
                        width: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: GssmsSpacing.s16),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SkeletonBar(widthFactor: 0.25, height: 10),
                    SizedBox(width: GssmsSpacing.s12),
                    _SkeletonBar(widthFactor: 0.25, height: 10),
                  ],
                ),
              ],
            ),
            const SizedBox(height: GssmsSpacing.s16),

            // 3. Pending Actions Section
            _card(
              context,
              children: [
                const _SkeletonBar(widthFactor: 0.35, height: 14),
                const SizedBox(height: GssmsSpacing.s16),
                for (var i = 0; i < 3; i++) ...[
                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: context.gssms.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: GssmsSpacing.s12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _SkeletonBar(widthFactor: 0.6, height: 12),
                            SizedBox(height: GssmsSpacing.s4),
                            _SkeletonBar(widthFactor: 0.4, height: 10),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (i < 2) const SizedBox(height: GssmsSpacing.s12),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static Widget _card(BuildContext context, {required List<Widget> children}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GssmsRadius.r12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(GssmsSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final max = constraints.maxWidth.isFinite ? constraints.maxWidth : 280.0;
        return Container(
          width: max * widthFactor,
          height: height,
          decoration: BoxDecoration(
            color: context.gssms.border,
            borderRadius: BorderRadius.circular(GssmsRadius.r4),
          ),
        );
      },
    );
  }
}
