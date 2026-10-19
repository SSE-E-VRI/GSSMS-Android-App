import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/checklist_report_pdf.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/complaint_report_pdf.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/inspection_report_pdf.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/rectification_report_pdf.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_primitives.dart';
import 'package:gssms_mobile/features/work_orders/services/report_pdf/report_fonts.dart';

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
    final List<pw.Widget> body = switch (r) {
      ChecklistJobWorkReport() => buildChecklistReportPdf(r, photos, at),
      ComplaintJobWorkReport() => buildComplaintReportPdf(r, photos, at),
      InspectionJobWorkReport() => buildInspectionReportPdf(r, photos, at),
      RectificationJobWorkReport() => buildRectificationReportPdf(r, photos, at),
    };
    final doc = pw.Document(compress: compress);
    doc.addPage(
      pw.MultiPage(
        pageFormat: reportPageFormat,
        theme: pw.ThemeData.withFont(
          base: ReportFonts.regular,
          bold: ReportFonts.bold,
        ),
        build: (context) => body,
      ),
    );
    return doc;
  }
}
