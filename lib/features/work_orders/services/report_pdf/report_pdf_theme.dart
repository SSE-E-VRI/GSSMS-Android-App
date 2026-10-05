import 'package:pdf/pdf.dart';

/// CSS styling tokens and metrics ported exactly from:
/// GSSMS/frontend/src/components/reports/reportTheme.module.css
class ReportPdfTheme {
  const ReportPdfTheme._();

  // CSS px to PDF pt (1 CSS px = 0.75 pt)
  static double px(double v) => v * 0.75;

  // CSS rem to PDF pt (1 rem = 16px = 12pt)
  static double rem(double v) => v * 12.0;

  // Colors from reportTheme.module.css (.reportRoot block)
  static const inkPrint = PdfColor.fromInt(0xFF000000);
  static const ink = PdfColor.fromInt(0xFF111827);
  static const muted = PdfColor.fromInt(0xFF4B5563);
  static const faint = PdfColor.fromInt(0xFF9CA3AF);
  static const border = PdfColor.fromInt(0xFFD1D5DB);
  static const borderPrint = PdfColor.fromInt(0xFF4B5563);
  static const surface = PdfColor.fromInt(0xFFF9FAFB);

  static const accent = PdfColor.fromInt(0xFF1F4E79);
  static const accentTint = PdfColor.fromInt(0xFFE8EEF5);

  /// Slate heading ink used by the inspection h2 and rectification item
  /// titles (#1e293b).
  static const headingInk = PdfColor.fromInt(0xFF1E293B);

  // Status badge colours: --rpt-{ok,bad,warn,neutral}-{fg,bg,border}
  static const okFg = PdfColor.fromInt(0xFF14532D);
  static const okBg = PdfColor.fromInt(0xFFDCFCE7);
  static const okBorder = PdfColor.fromInt(0xFF15803D);

  static const badFg = PdfColor.fromInt(0xFF7F1D1D);
  static const badBg = PdfColor.fromInt(0xFFFEE2E2);
  static const badBorder = PdfColor.fromInt(0xFFB91C1C);

  static const warnFg = PdfColor.fromInt(0xFF78350F);
  static const warnBg = PdfColor.fromInt(0xFFFEF3C7);
  static const warnBorder = PdfColor.fromInt(0xFFB45309);

  static const neutralFg = PdfColor.fromInt(0xFF374151);
  static const neutralBg = PdfColor.fromInt(0xFFF3F4F6);
  static const neutralBorder = PdfColor.fromInt(0xFF6B7280);

  // Bootstrap secondary & warning border
  static const textSecondary = PdfColor.fromInt(0xFF6C757D);
  static const borderWarning = PdfColor.fromInt(0xFFFFC107);

  // Badge metrics (.badge): 0.75rem bold, lh 1.3, padding 0.1rem 0.45rem.
  static const double badgeFontPt = 9.0;
  static const double badgeLineHeight = 1.3;
  static const double badgePadV = 1.2;
  static const double badgePadH = 5.4;
  static const double badgeRadius = 2.25;
}
