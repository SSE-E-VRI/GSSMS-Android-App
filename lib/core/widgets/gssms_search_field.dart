import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// Search box for list screens.
///
/// The clear button listens to [controller] directly, so typing rebuilds only
/// the suffix icon — not the whole screen (the list screens used to
/// `setState` on every keystroke just to toggle this button).
class GssmsSearchField extends StatelessWidget {
  const GssmsSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onChanged,
    this.fieldKey,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    return TextField(
      key: fieldKey,
      controller: controller,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.clear, size: 18),
              tooltip: 'Clear search',
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            );
          },
        ),
        filled: true,
        fillColor: tokens.surfaceInset,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: GssmsSpacing.s16,
          vertical: GssmsSpacing.s12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(GssmsRadius.r12),
          borderSide: BorderSide(color: tokens.border),
        ),
      ),
    );
  }
}

/// Background band for the filter block at the top of a list screen.
class FilterStrip extends StatelessWidget {
  const FilterStrip({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(
      GssmsSpacing.s16,
      GssmsSpacing.s8,
      GssmsSpacing.s16,
      GssmsSpacing.s8,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.gssms.surfaceRaised,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// "12 of 40 shown · Clear filters" line under a list's filter block.
///
/// Makes filter state visible (SSOT-driven lists are otherwise easy to read
/// as complete when a filter is hiding rows) and gives a one-tap reset.
class ListResultHeader extends StatelessWidget {
  const ListResultHeader({
    super.key,
    required this.shown,
    required this.total,
    required this.noun,
    this.onClearFilters,
  });

  final int shown;
  final int total;

  /// Plural noun, e.g. `complaints`.
  final String noun;

  /// Non-null when any filter/search is active.
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final tokens = context.gssms;
    final filtered = onClearFilters != null;
    final text = filtered && shown != total
        ? '$shown of $total $noun'
        : '$total $noun';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        GssmsSpacing.s16,
        GssmsSpacing.s4,
        GssmsSpacing.s4,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              liveRegion: true,
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: tokens.textSecondary),
              ),
            ),
          ),
          if (filtered)
            TextButton.icon(
              key: const Key('list_clear_filters'),
              onPressed: onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              label: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }
}
