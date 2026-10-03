import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gssms_mobile/features/work_orders/data/job_work_report_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

class ParityFixture {
  const ParityFixture({
    required this.id,
    required this.kind,
    required this.generatedAt,
    required this.ticket,
    required this.report,
    required this.photos,
  });

  final String id;
  final String kind;
  final DateTime generatedAt;
  final String ticket;
  final JobWorkReport report;
  final Map<String, Uint8List?> photos;
}

class FixtureLoader {
  const FixtureLoader._();

  static Future<ParityFixture> load(String fixtureId) async {
    final file = File('tool/report_parity/fixtures/$fixtureId.json');
    if (!await file.exists()) {
      throw ArgumentError('Fixture not found: ${file.path}');
    }
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final kind = raw['kind'] as String;
    final generatedAt = DateTime.parse(raw['generatedAt'] as String);
    final ticket = raw['ticket'] as String;
    final woJson = raw['workOrder'] as Map<String, dynamic>;
    final payloadJson = raw['payload'] as Map<String, dynamic>;

    final wo = WorkOrder.fromJson(woJson);

    final JobWorkReport report;
    switch (kind) {
      case 'checklist':
        report = ChecklistJobWorkReport.fromRecordJson(payloadJson, wo);
      case 'complaint':
        report = ComplaintJobWorkReport.fromJson(
          payloadJson,
          woJson,
          fallbackTicket: wo.displayReference,
        );
      case 'inspection':
        report = InspectionJobWorkReport.fromJson(
          payloadJson,
          fallbackTicket: wo.displayReference,
        );
      case 'rectification':
        report = RectificationJobWorkReport.fromJson(
          payloadJson,
          fallbackTicket: wo.displayReference,
          fallbackStation: wo.stationName ?? wo.depotName,
        );
      default:
        throw ArgumentError('Unknown fixture kind: $kind');
    }

    final photos = <String, Uint8List?>{};
    for (final p in report.allPhotos) {
      if (p.url.isEmpty) continue;
      // p.url is e.g. "/parity-images/before_1.jpg"
      final localPath = p.url.startsWith('/')
          ? 'tool/report_parity/fixtures/public${p.url}'
          : 'tool/report_parity/fixtures/public/$p.url';
      final imgFile = File(localPath);
      if (await imgFile.exists()) {
        final bytes = await imgFile.readAsBytes();
        try {
          photos[p.key] = downscalePhoto(bytes);
        } catch (_) {
          photos[p.key] = null;
        }
      } else {
        photos[p.key] = null;
      }
    }

    return ParityFixture(
      id: fixtureId,
      kind: kind,
      generatedAt: generatedAt,
      ticket: ticket,
      report: report,
      photos: photos,
    );
  }
}
