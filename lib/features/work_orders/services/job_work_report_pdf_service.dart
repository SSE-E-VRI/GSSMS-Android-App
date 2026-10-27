import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:intl/intl.dart';
import 'package:gssms_mobile/core/config/app_config.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/checklist_report_pdf.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/complaint_report_pdf.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/inspection_report_pdf.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/rectification_report_pdf.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';

/// Builds the printable Job Work report (technician "Report Preview") for the
/// four Job Work kinds. Mirrors the web FormPreview,
/// ComplaintExecutionPrintPreview, InspectionReportPreview and
/// RectificationReportPreview sections and labels.
class JobWorkReportPdfService {
  const JobWorkReportPdfService._();

  static Future<pw.Document> build(
    JobWorkReport r, {
    Map<String, Uint8List?> photos = const {},
    DateTime? generatedAt,
    @visibleForTesting bool compress = true,
  }) async {
    await ReportFonts.load();
    final at = generatedAt ?? DateTime.now();
    // The web report root's inherited line-height: Bootstrap body 1.5 for the
    // Checklist and Inspection reports, `.reportContainer` 1.4 for Breakdown
    // and Rectification.
    ReportRoot.lineHeight = switch (r) {
      ChecklistJobWorkReport() || InspectionJobWorkReport() => 1.5,
      ComplaintJobWorkReport() || RectificationJobWorkReport() => 1.4,
    };
    final registerPrint = r is ChecklistJobWorkReport && r.showJobWork;
    ReportRoot.contentWidth = registerPrint
        ? checklistRegisterContentWidth / checklistRegisterScale
        : reportContentWidth;
    final List<pw.Widget> body = switch (r) {
      ChecklistJobWorkReport() => buildChecklistReportPdf(r, photos, at),
      ComplaintJobWorkReport() => buildComplaintReportPdf(r, photos, at),
      InspectionJobWorkReport() => buildInspectionReportPdf(r, photos, at),
      RectificationJobWorkReport() => buildRectificationReportPdf(r, photos, at),
    };
    final doc = pw.Document(compress: compress, title: r.pdfFileName.replaceFirst('.pdf', ''));
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: registerPrint ? checklistRegisterPageFormat : reportPageFormat,
          buildForeground: registerPrint ? (context) => _registerPageFrame(r, at, context) : null,
          theme: pw.ThemeData.withFont(
            base: ReportFonts.regular,
            bold: ReportFonts.bold,
          ),
        ),
        build: (context) => registerPrint
            ? [for (final widget in body) ChecklistPrintScale(child: widget)]
            : body,
      ),
    );
    return doc;
  }
}

/// Browser-style print furniture from the web reference, outside the report
/// area so the header/footer cannot change group pagination.
pw.Widget _registerPageFrame(JobWorkReport report, DateTime at, pw.Context context) {
  final baseUrl = AppConfig.fromEnvironment().baseUrl;
  final url = Uri.parse(baseUrl).resolve('/reports').toString();
  final local = at.toUtc().add(const Duration(hours: 5, minutes: 30));
  final textStyle = pw.TextStyle(font: pw.Font.helvetica(), fontSize: 7.995);
  pw.Widget text(String value, {pw.TextAlign? align}) =>
      pw.Text(value, style: textStyle, textAlign: align);
  return pw.FullPage(ignoreMargins: true, child: pw.Stack(children: [
    pw.Positioned(left: 24, top: 14.5, child: text(DateFormat('M/d/yy, h:mm a').format(local))),
    pw.Positioned(left: 198, right: 99, top: 14.5,
        child: text(report.pdfFileName.replaceFirst('.pdf', ''), align: pw.TextAlign.center)),
    pw.Positioned(left: 24, bottom: 14.5, child: text(url)),
    pw.Positioned(right: 24, bottom: 14.5,
        child: text('${context.pageNumber}/${context.pagesCount}')),
  ]));
}
