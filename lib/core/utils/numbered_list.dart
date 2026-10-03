// Numbered-list text codec for repeatable technician remarks, matching web
// `frontend/src/utils/repeatableText.js`. `record.remarks` stores
// `"1. first\n2. second"`.

final RegExp _numberPrefix = RegExp(r'^\d+\.\s+');

/// Joins values into `"1. a\n2. b"`. An empty list joins to `''`.
String joinNumberedList(List<String> values) {
  final buf = <String>[];
  for (var i = 0; i < values.length; i++) {
    buf.add('${i + 1}. ${values[i]}');
  }
  return buf.join('\n');
}

/// Splits stored remarks back into items. Text where every non-empty line has
/// a `N. ` prefix is split per line (prefix stripped); any other text (legacy
/// free paragraph) is returned as a single item.
List<String> splitNumberedList(String? text) {
  final trimmed = (text ?? '').trim();
  if (trimmed.isEmpty) return const [];
  final lines = trimmed
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.isNotEmpty && lines.every(_numberPrefix.hasMatch)) {
    return lines.map((l) => l.replaceFirst(_numberPrefix, '')).toList();
  }
  return [trimmed];
}
