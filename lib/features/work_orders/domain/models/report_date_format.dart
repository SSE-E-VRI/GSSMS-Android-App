// Port of GSSMS/frontend/src/utils/date.js formatDate and formatReportDateTime
// lines 14-27 and 119-155, forced IST (UTC+05:30) independent of device timezone.

const _naiveDateTime =
    r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?)?$';
final _naiveDateTimeRegex = RegExp(_naiveDateTime);

const _naiveTime = r'^(\d{2}):(\d{2})(?::\d{2}(?:\.\d+)?)?$';
final _naiveTimeRegex = RegExp(_naiveTime);

const Duration _istOffset = Duration(hours: 5, minutes: 30);

/// Port of formatDate(ts) from date.js:14-27
/// Formats a date as dd/mm/yyyy. Empty/invalid returns '—' (em dash).
String webFormatDate(Object? raw) {
  if (raw == null || raw == '') return '—';

  if (raw is String) {
    final s = raw.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      final parts = s.split('-');
      return '${parts[2]}/${parts[1]}/${parts[0]}';
    }
  }

  final DateTime? dt;
  if (raw is DateTime) {
    dt = raw;
  } else if (raw is String) {
    dt = DateTime.tryParse(raw.trim());
  } else {
    return '—';
  }

  if (dt == null) return '—';

  // Convert to IST
  final ist = dt.toUtc().add(_istOffset);
  final d = ist.day.toString().padLeft(2, '0');
  final m = ist.month.toString().padLeft(2, '0');
  final y = ist.year.toString();
  return '$d/$m/$y';
}

/// Port of formatReportDateTime(value, time) from date.js:119-155
/// `dd/mm/yyyy HH:mm` (24h), or `dd/mm/yyyy` for a bare date, or '—'.
String webFormatReportDateTime(Object? value, [String? time]) {
  if (value == null || value == '') return '—';

  if (value is String) {
    final s = value.trim();
    // Only treat as naive wall-clock if it does NOT have timezone indicator (Z or +/-)
    if (!s.endsWith('Z') && !RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(s)) {
      final m = _naiveDateTimeRegex.firstMatch(s);
      if (m != null) {
        final y = m.group(1)!;
        final mo = m.group(2)!;
        final d = m.group(3)!;
        final hh = m.group(4);
        final mm = m.group(5);
        String clock = (hh != null && mm != null) ? '$hh:$mm' : '';
        if (clock.isEmpty && time != null) {
          final tm = _naiveTimeRegex.firstMatch(time.trim());
          if (tm != null) {
            clock = '${tm.group(1)}:${tm.group(2)}';
          }
        }
        return clock.isNotEmpty ? '$d/$mo/$y $clock' : '$d/$mo/$y';
      }
    }
  }

  final DateTime? dt;
  if (value is DateTime) {
    dt = value;
  } else if (value is String) {
    dt = DateTime.tryParse(value.trim());
  } else {
    return '—';
  }

  if (dt == null) return '—';

  // Convert to IST
  final ist = dt.toUtc().add(_istOffset);
  final d = ist.day.toString().padLeft(2, '0');
  final mo = ist.month.toString().padLeft(2, '0');
  final y = ist.year.toString();
  final h = ist.hour.toString().padLeft(2, '0');
  final min = ist.minute.toString().padLeft(2, '0');
  return '$d/$mo/$y $h:$min';
}

/// Formats generatedAt date-time in IST dd/mm/yyyy HH:mm
String formatGeneratedAt(DateTime dt) {
  final ist = dt.toUtc().add(_istOffset);
  final d = ist.day.toString().padLeft(2, '0');
  final mo = ist.month.toString().padLeft(2, '0');
  final y = ist.year.toString();
  final h = ist.hour.toString().padLeft(2, '0');
  final min = ist.minute.toString().padLeft(2, '0');
  return '$d/$mo/$y $h:$min';
}
