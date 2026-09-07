/// Defensively coerces a decoded JSON value to a string.
///
/// A field that is normally a string can arrive as a number (or any other
/// JSON scalar) when the server's field type doesn't match what the mobile
/// model assumes — an `as String?` cast then throws and takes down the whole
/// screen. This coerces instead of crashing: `2` becomes `"2"`, `null` stays
/// `null`, and an already-correct `String` passes through unchanged.
String? asJsonString(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  return value.toString();
}

/// Defensively coerces a decoded JSON value to an int.
///
/// Same reasoning as [asJsonString]: a field normally sent as a JSON number
/// can arrive as a numeric string, or a double with no fractional part —
/// `as int?` throws on either instead of coercing, taking down the whole
/// parse (and the screen it feeds) over one mistyped field.
int? asJsonInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

/// Defensively coerces a decoded JSON value to a bool.
///
/// Handles the common non-bool encodings of a boolean a server might send
/// (`0`/`1`, `"true"`/`"false"`) instead of throwing via `as bool?`.
bool? asJsonBool(dynamic value) {
  if (value == null) return null;
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true' || lower == '1') return true;
    if (lower == 'false' || lower == '0') return false;
  }
  return null;
}
