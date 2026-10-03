import 'package:pdf/pdf.dart';

/// CSS styling tokens and metrics ported exactly from:
/// GSSMS/frontend/src/components/reports/reportTheme.module.css
class ReportPdfTheme {
  const ReportPdfTheme._();

  // CSS px to PDF pt (1 CSS px = 0.75 pt)
  static double px(double v) => v * 0.75;

  // CSS rem to PDF pt (1 rem = 16px = 12pt)
  static double rem(double v) => v * 12.0;

  // Colors from reportTheme.module.css lines 12-35
  static const inkPrint = PdfColor.fromInt(0xFF000000);
  static const ink = PdfColor.fromInt(0xFF111827);
  static const muted = PdfColor.fromInt(0xFF4B5563);
  static const faint = PdfColor.fromInt(0xFF9CA3AF);
  static const border = PdfColor.fromInt(0xFFD1D5DB);
  static const borderPrint = PdfColor.fromInt(0xFF4B5563);
  static const surface = PdfColor.fromInt(0xFFF9FAFB);

  static const accent = PdfColor.fromInt(0xFF1F4E79);
  static const accentTint = PdfColor.fromInt(0xFFE8EEF5);

  // Status badge colors
  static const okFg = PdfColor.fromInt(0xFF166534);
  static const okBg = PdfColor.fromInt(0xFFDCFCE7);
  static const okBorder = PdfColor.fromInt(0xFF86EFAC);

  static const badFg = PdfColor.fromInt(0xFF991B1B);
  static const badBg = PdfColor.fromInt(0xFFFEE2E2);
  static const badBorder = PdfColor.fromInt(0xFFFCA5A5);

  static const warnFg = PdfColor.fromInt(0xFF854D0E);
  static const warnBg = PdfColor.fromInt(0xFFFEF9C3);
  static const warnBorder = PdfColor.fromInt(0xFFFDE047);

  static const neutralFg = PdfColor.fromInt(0xFF374151);
  static const neutralBg = PdfColor.fromInt(0xFFF3F4F6);
  static const neutralBorder = PdfColor.fromInt(0xFFD1D5DB);

  // Bootstrap secondary & warning border
  static const textSecondary = PdfColor.fromInt(0xFF6C757D);
  static const borderWarning = PdfColor.fromInt(0xFFFFC107);
}
