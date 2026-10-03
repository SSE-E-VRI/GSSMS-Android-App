import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/services/job_work_report_pdf_service.dart';

import 'fixture_loader.dart';

const _fixtureIds = [
  'checklist_pm_full',
  'checklist_pm_minimal',
  'checklist_pm_long',
  'breakdown_deficiency',
  'breakdown_complaint',
  'breakdown_jobwork',
  'inspection_pointwise',
  'inspection_legacy',
  'rectification_mixed',
  'rectification_single',
];

void main() {
  final outDir = Platform.environment['REPORT_PARITY_OUT'];

  test(
    'render Android report PDFs for parity harness',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final targetDir = Directory(outDir!);
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      for (final id in _fixtureIds) {
        final fixture = await FixtureLoader.load(id);
        final doc = await JobWorkReportPdfService.build(
          fixture.report,
          photos: fixture.photos,
          generatedAt: fixture.generatedAt,
        );
        final bytes = await doc.save();
        final outFile = File('${targetDir.path}/$id.pdf');
        await outFile.writeAsBytes(bytes);
        // ignore: avoid_print
        print('Rendered Android PDF: ${outFile.path}');
      }
    },
    skip: outDir == null ? 'REPORT_PARITY_OUT environment variable not set' : false,
  );
}
