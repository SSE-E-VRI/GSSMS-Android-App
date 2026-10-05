import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/job_work_report.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

/// Resolves a Maintenance Register work order into its signed checklist
/// report, mirroring web `ReportsView.viewReport` (checklist branch): the
/// record attached to the Job Work first, else the schedule-only record
/// (never a record belonging to a different execution Job Work), shaped by
/// `ChecklistJobWorkReport.fromRecordJson` with the Register presentation
/// rules (`showJobWork: true`, `report_completed_at || date_of_maintenance`).
///
/// Throws on unresolved / denied / network failures — the detail screen
/// maps those to an error state with Retry, never an empty report.
class RegisterJobWorkAdapter {
  RegisterJobWorkAdapter(this._workOrders);

  final IWorkOrderRepository _workOrders;

  Future<ChecklistJobWorkReport> resolve(WorkOrder wo) async {
    final attached =
        await _workOrders.fetchMaintenanceRecords(workOrderId: wo.id);
    Map<String, dynamic>? record =
        attached.isNotEmpty ? attached.first : null;

    if (record == null && wo.originalScheduleId != null) {
      final scheduled = await _workOrders.fetchMaintenanceRecords(
          scheduleId: wo.originalScheduleId!);
      for (final candidate in scheduled) {
        // Legacy fallback is only for schedule-only records. Never use a
        // record belonging to a different execution Job Work.
        if (candidate['work_order'] == null) {
          record = candidate;
          break;
        }
      }
    }

    if (record == null) {
      throw StateError(
          'No checklist record found for this Job Work yet.');
    }
    return ChecklistJobWorkReport.fromRecordJson(
      record,
      wo,
      showJobWork: true,
      preferReportCompletedAt: true,
    );
  }
}
