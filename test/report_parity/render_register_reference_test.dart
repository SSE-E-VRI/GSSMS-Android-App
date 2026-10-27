import 'dart:convert';
import 'dart:io';
import 'fixture_loader.dart';
import '../features/work_orders/services/pdf_layout_probe.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_service.dart';

// Optional local-data visual check. Keep production payloads outside the repo.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('station monthly register matches the four-page web structure', () async {
    final fixture = await FixtureLoader.load('register_station_monthly');
    final doc = await JobWorkReportPdfService.build(fixture.report,
        generatedAt: fixture.generatedAt, compress: false);
    final bytes = await doc.save();
    expect(doc.document.pdfPageList.pages.length, 4);
    final words = probePdfLayout(bytes)['words'] as List;
    final printed = words.map((w) => (w as Map)['text']).join(' ');
    expect(printed, isNot(contains('No photo')));
    expect(printed, contains('Submersible'));
    expect(printed, contains('SIGN-OFF'));
    expect(fixture.report.pdfFileName, 'JobWork-TEST-202610-0019-Verification.pdf');
  });
  final input = Platform.environment['REGISTER_REFERENCE_INPUT'];
  final output = Platform.environment['REGISTER_REFERENCE_OUTPUT'];
  test('render register reference for visual comparison', () async {
    final json = jsonDecode(File(input!).readAsStringSync()) as Map<String, dynamic>;
    final report = ChecklistJobWorkReport.fromRecordJson(
      json['payload'] as Map<String, dynamic>,
      WorkOrder.fromJson(json['workOrder'] as Map<String, dynamic>),
      showJobWork: true, preferReportCompletedAt: true,
    );
    final doc = await JobWorkReportPdfService.build(report,
      generatedAt: DateTime.parse('2026-10-27T05:34:00Z'));
    final file = File(output!);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(await doc.save());
    expect(doc.document.pdfPageList.pages.length, 4);
  }, skip: input == null || output == null ? 'Set REGISTER_REFERENCE_INPUT and REGISTER_REFERENCE_OUTPUT' : false);
}
