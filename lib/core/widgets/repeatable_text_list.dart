import 'package:flutter/material.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';

/// A numbered list of short text entries (web `RepeatableTextList`).
///
/// Entries show as "1. text" rows with a delete button; new text is typed into
/// a field and added with the "Add" button. Typed-but-not-added text is
/// committed when the field loses focus and when the owner calls
/// [RepeatableTextListState.commitPending] (e.g. before validating a form).
///
/// Widget keys derive from [keyPrefix]: input `<prefix>_field`, add button
/// `<prefix>_add`, rows `<prefix>_item_<i>`, delete `<prefix>_remove_<i>`.
class RepeatableTextList extends StatefulWidget {
  const RepeatableTextList({
    super.key,
    required this.onChanged,
    this.initial = const [],
    this.label,
    this.hint,
    this.enabled = true,
    this.keyPrefix = 'repeatable',
    this.errorText,
  });

  final List<String> initial;
  final ValueChanged<List<String>> onChanged;
  final String? label;
  final String? hint;
  final bool enabled;
  final String keyPrefix;
  final String? errorText;

  @override
  State<RepeatableTextList> createState() => RepeatableTextListState();
}

class RepeatableTextListState extends State<RepeatableTextList> {
  late List<String> _values;
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// The committed entries (does not include uncommitted typed text).
  List<String> get values => List.unmodifiable(_values);

  @override
  void initState() {
    super.initState();
    _values = widget.initial
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) commitPending();
  }

  /// Adds any typed text as an entry and returns the full committed list.
  List<String> commitPending() {
    final text = _input.text.trim();
    if (text.isNotEmpty) {
      setState(() {
        _values = [..._values, text];
        _input.clear();
      });
      widget.onChanged(List.unmodifiable(_values));
    }
    return values;
  }

  void _remove(int index) {
    setState(() => _values = [..._values]..removeAt(index));
    widget.onChanged(List.unmodifiable(_values));
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final tokens = context.gssms;
    final prefix = widget.keyPrefix;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null)
          Text(widget.label!, style: textTheme.labelLarge),
        for (var i = 0; i < _values.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: GssmsSpacing.s4),
            child: Row(
              key: Key('${prefix}_item_$i'),
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text('${i + 1}. ${_values[i]}',
                      style: textTheme.bodyMedium),
                ),
                IconButton(
                  key: Key('${prefix}_remove_$i'),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove entry ${i + 1}',
                  onPressed: widget.enabled ? () => _remove(i) : null,
                ),
              ],
            ),
          ),
        const SizedBox(height: GssmsSpacing.s4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: Key('${prefix}_field'),
                controller: _input,
                focusNode: _focus,
                enabled: widget.enabled,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: widget.hint,
                  isDense: true,
                  errorText: widget.errorText,
                ),
              ),
            ),
            const SizedBox(width: GssmsSpacing.s8),
            OutlinedButton(
              key: Key('${prefix}_add'),
              onPressed: widget.enabled ? commitPending : null,
              child: const Text('Add'),
            ),
          ],
        ),
        if (_values.isEmpty && widget.errorText == null)
          Padding(
            padding: const EdgeInsets.only(top: GssmsSpacing.s4),
            child: Text(
              'No entries yet.',
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
      ],
    );
  }
}
