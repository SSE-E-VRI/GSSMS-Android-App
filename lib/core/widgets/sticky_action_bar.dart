import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Bottom bar holding a screen's actions — always reachable without
/// scrolling, above the system gesture area, correct in both themes.
///
/// [child] is the primary action and fills the first row. [children] are
/// secondary actions laid out [maxInline] per row, wrapping instead of being
/// squeezed into unreadable slivers when the server offers several.
class StickyActionBar extends StatelessWidget {
  const StickyActionBar({super.key, this.child, this.children, this.maxInline = 2})
      : assert(child != null || children != null);

  final Widget? child;
  final List<Widget>? children;
  final int maxInline;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final secondary = children ?? const <Widget>[];

    Widget row(List<Widget> slice) => Row(
          children: [
            for (var i = 0; i < slice.length; i++) ...[
              if (i > 0) const SizedBox(width: GssmsSpacing.s8),
              Expanded(
                child: SizedBox(height: GssmsSize.primaryAction, child: slice[i]),
              ),
            ],
          ],
        );

    final rows = <Widget>[
      if (child != null) row([child!]),
    ];
    for (var i = 0; i < secondary.length; i += maxInline) {
      final end = (i + maxInline).clamp(0, secondary.length);
      if (rows.isNotEmpty) rows.add(const SizedBox(height: GssmsSpacing.s8));
      rows.add(row(secondary.sublist(i, end)));
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(GssmsSpacing.s12),
          child: Column(mainAxisSize: MainAxisSize.min, children: rows),
        ),
      ),
    );
  }
}
