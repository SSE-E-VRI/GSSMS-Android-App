import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/features/work_orders/data/job_work_report_api_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:image/image.dart' as img;

final jobWorkReportRepositoryProvider =
    Provider<JobWorkReportRepository>((ref) {
  return JobWorkReportRepository(ref.watch(jobWorkReportApiServiceProvider));
});

/// Loads a Job Work report and preloads its photos.
///
/// Online-only by design: nothing is cached or queued; errors propagate so
/// the screen can show a retry state.
class JobWorkReportRepository {
  JobWorkReportRepository(this._api);
  final JobWorkReportApiService _api;

  static const int _photoConcurrency = 4;

  Future<LoadedJobWorkReport> load(WorkOrder wo) async {
    final JobWorkReport report;
    switch (executionRouteFor(wo)) {
      case ExecutionRoute.rectification:
        report = RectificationJobWorkReport.fromJson(
          await _api.fetchRectification(wo.id),
          fallbackTicket: wo.displayReference,
          fallbackStation: null,
        );
      case ExecutionRoute.complaint:
        final results = await Future.wait([
          _api.fetchComplaintExecution(wo.id),
          _api.fetchWorkOrder(wo.id),
        ]);
        report = ComplaintJobWorkReport.fromJson(
          results[0],
          results[1],
          fallbackTicket: wo.displayReference,
        );
      case ExecutionRoute.inspection:
        report = InspectionJobWorkReport.fromJson(
          await _api.fetchInspectionExecution(wo.id),
          fallbackTicket: wo.displayReference,
        );
      case ExecutionRoute.checklist:
        final record = await _api.fetchChecklistRecord(
          wo.id,
          scheduleId: wo.originalScheduleId,
        );
        report = record == null
            ? ChecklistJobWorkReport.empty(wo)
            : ChecklistJobWorkReport.fromRecordJson(record, wo);
    }
    final photos = await _preloadPhotos(report.allPhotos);
    return LoadedJobWorkReport(report: report, photos: photos);
  }

  /// Fetches + downscales every photo (4 at a time). A failed photo maps to
  /// null and never fails the report.
  Future<Map<String, Uint8List?>> _preloadPhotos(
    List<ReportPhoto> photos,
  ) async {
    final result = <String, Uint8List?>{};
    final queue = [
      for (final p in photos)
        if (p.url.isNotEmpty) p,
    ];
    var next = 0;
    Future<void> worker() async {
      while (next < queue.length) {
        final photo = queue[next++];
        try {
          final raw = await _api.fetchPhotoBytes(photo.url);
          result[photo.key] = await compute(downscalePhoto, raw);
        } catch (_) {
          result[photo.key] = null;
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < _photoConcurrency && i < queue.length; i++) worker(),
    ]);
    return result;
  }
}

/// Decode, shrink to at most 640px wide and re-encode as JPEG q70. Throws on
/// undecodable bytes (the caller maps that to a missing photo). Top-level so
/// it can run in an isolate.
@visibleForTesting
Uint8List downscalePhoto(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Undecodable image');
  final resized =
      decoded.width > 640 ? img.copyResize(decoded, width: 640) : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
}
