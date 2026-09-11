import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// One cadence's Last Done / Next Due, as returned per key in
/// `schedule_type_summary` (`get_asset_maintenance_summary` on the backend).
class ScheduleCadenceStatus extends Equatable {
  const ScheduleCadenceStatus({this.lastDoneDate, this.nextDueDate});

  final DateTime? lastDoneDate;
  final DateTime? nextDueDate;

  factory ScheduleCadenceStatus.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : asJsonDateTime(v);
    return ScheduleCadenceStatus(
      lastDoneDate: parse(json['last_done_date']),
      nextDueDate: parse(json['next_due_date']),
    );
  }

  @override
  List<Object?> get props => [lastDoneDate, nextDueDate];
}

/// One work order row from `open_work_orders`/`completed_work_orders`.
class AssetMaintenanceWorkOrder extends Equatable {
  const AssetMaintenanceWorkOrder({
    required this.id,
    required this.title,
    required this.status,
    this.ticketNumber,
    this.dueDate,
    this.scheduledDate,
  });

  final int id;
  final String title;
  final String status;
  final String? ticketNumber;
  final DateTime? dueDate;
  final DateTime? scheduledDate;

  factory AssetMaintenanceWorkOrder.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : asJsonDateTime(v);
    return AssetMaintenanceWorkOrder(
      id: asJsonInt(json['id']) ?? 0,
      title: asJsonString(json['title']) ?? 'Job Work',
      status: asJsonString(json['status']) ?? 'UNKNOWN',
      ticketNumber: asJsonString(json['ticket_number']),
      dueDate: parse(json['due_date']),
      scheduledDate: parse(json['scheduled_date']),
    );
  }

  @override
  List<Object?> get props => [id, title, status, ticketNumber, dueDate, scheduledDate];
}

/// `GET /api/v1/assets/{id}/maintenance-summary/` — backs both web's
/// "Asset Maintenance Status" panel (via [scheduleTypeSummary]) and the
/// Maintenance tab (via [openWorkOrders]/[completedWorkOrders]).
class AssetMaintenanceSummary extends Equatable {
  const AssetMaintenanceSummary({
    this.nextDueDate,
    this.lastDoneDate,
    this.scheduleTypeSummary = const {},
    this.openWorkOrders = const [],
    this.completedWorkOrders = const [],
  });

  final DateTime? nextDueDate;
  final DateTime? lastDoneDate;

  /// Keyed by MONTHLY/QUARTERLY/HALF_YEARLY/YEARLY — the four cadences
  /// `get_asset_maintenance_summary` breaks out (DAILY/WEEKLY are computed
  /// server-side too but not surfaced in this card, mirroring web).
  final Map<String, ScheduleCadenceStatus> scheduleTypeSummary;
  final List<AssetMaintenanceWorkOrder> openWorkOrders;
  final List<AssetMaintenanceWorkOrder> completedWorkOrders;

  factory AssetMaintenanceSummary.fromJson(Map<String, dynamic> json) {
    DateTime? parse(dynamic v) =>
        v == null ? null : asJsonDateTime(v);
    final rawSummary = json['schedule_type_summary'];
    final summary = <String, ScheduleCadenceStatus>{};
    if (rawSummary is Map) {
      rawSummary.forEach((key, value) {
        if (value is Map) {
          summary[key.toString()] =
              ScheduleCadenceStatus.fromJson(Map<String, dynamic>.from(value));
        }
      });
    }
    List<AssetMaintenanceWorkOrder> parseWos(dynamic raw) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => AssetMaintenanceWorkOrder.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return AssetMaintenanceSummary(
      nextDueDate: parse(json['next_due_date']),
      lastDoneDate: parse(json['last_done_date']),
      scheduleTypeSummary: summary,
      openWorkOrders: parseWos(json['open_work_orders']),
      completedWorkOrders: parseWos(json['completed_work_orders']),
    );
  }

  @override
  List<Object?> get props => [
        nextDueDate,
        lastDoneDate,
        scheduleTypeSummary,
        openWorkOrders,
        completedWorkOrders,
      ];
}
