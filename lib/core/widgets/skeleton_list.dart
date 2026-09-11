import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Static placeholder cards shown while a list loads for the first time.
///
/// Deliberately not animated: a shimmer on every card costs a repaint per
/// frame for no information, and operational screens should feel still and
/// fast. The shapes mirror a record card (reference line, title, meta line)
/// so the layout does not jump when data arrives.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: ExcludeSemantics(
        child: Column(
          children: [
            for (var i = 0; i < itemCount; i++) const _SkeletonCard(),
          ],
        ),
      ),
    );
  }
}

/// Sliver form of [SkeletonList] for `CustomScrollView` bodies.
class SliverSkeletonList extends StatelessWidget {
  const SliverSkeletonList({super.key, this.itemCount = 5});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.only(top: GssmsSpacing.s8),
      sliver: SliverToBoxAdapter(child: SkeletonList(itemCount: itemCount)),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(GssmsSpacing.s16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Bar(widthFactor: 0.3, height: 10),
                Spacer(),
                _Bar(widthFactor: 0.2, height: 16),
              ],
            ),
            SizedBox(height: GssmsSpacing.s12),
            _Bar(widthFactor: 0.8, height: 14),
            SizedBox(height: GssmsSpacing.s8),
            _Bar(widthFactor: 0.55, height: 10),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.widthFactor, required this.height});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final max = constraints.maxWidth.isFinite ? constraints.maxWidth : 300.0;
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
