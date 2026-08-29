import 'dart:convert';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ILocalCacheService {
  Future<void> cacheWorkOrders(List<WorkOrder> workOrders);
  Future<List<WorkOrder>> getCachedWorkOrders();

  Future<void> cacheWorkOrderDetail(WorkOrder workOrder);
  Future<WorkOrder?> getCachedWorkOrderDetail(int id);

  Future<void> cacheMaintenanceRecord(MaintenanceRecord record);
  Future<MaintenanceRecord?> getCachedMaintenanceRecord(int id);

  Future<void> saveOutboxCommands(List<OutboxCommand> commands);
  Future<List<OutboxCommand>> getOutboxCommands();

  Future<void> clearAllCache();
}

class LocalCacheService implements ILocalCacheService {
  LocalCacheService([SharedPreferences? prefs]) : _prefs = prefs;

  SharedPreferences? _prefs;

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  static const String _kWorkOrdersListKey = 'gssms_cache_work_orders_list';
  static const String _kWorkOrderDetailPrefix = 'gssms_cache_wo_detail_';
  static const String _kRecordPrefix = 'gssms_cache_record_';
  static const String _kOutboxCommandsKey = 'gssms_cache_outbox_commands';

  @override
  Future<void> cacheWorkOrders(List<WorkOrder> workOrders) async {
    final prefs = await _getPrefs();
    final jsonList = workOrders.map((wo) => {
      'id': wo.id,
      'status': wo.status.code,
      'type': wo.type.code,
      'title': wo.title,
      'description': wo.description,
      'priority': wo.priority.code,
      'asset': wo.assetId,
      'asset_name': wo.assetName,
      'asset_criticality': wo.assetCriticality,
      'depot': wo.depotId,
      'depot_name': wo.depotName,
      'station_name': wo.stationName,
      'infrastructure_name': wo.infrastructureName,
      'infrastructure_type': wo.infrastructureType,
      'assigned_to': wo.assignedToId,
      'assigned_to_name': wo.assignedToName,
      'reported_by_name': wo.reportedByName,
      'verified_by_name': wo.verifiedByName,
      'due_date': wo.dueDate?.toIso8601String(),
      'created_at': wo.createdAt?.toIso8601String(),
      'report_completed_at': wo.reportCompletedAt?.toIso8601String(),
      'linked_record_id': wo.linkedRecordId,
      'ticket_number': wo.ticketNumber,
      'maintenance_master_name': wo.maintenanceMasterName,
      'sla_status': wo.slaStatus,
      'escalation_level': wo.escalationLevel,
      'station': wo.stationId,
    }).toList();

    await prefs.setString(_kWorkOrdersListKey, jsonEncode(jsonList));
  }

  @override
  Future<List<WorkOrder>> getCachedWorkOrders() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_kWorkOrdersListKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => WorkOrder.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> cacheWorkOrderDetail(WorkOrder workOrder) async {
    final prefs = await _getPrefs();
    final jsonMap = {
      'id': workOrder.id,
      'status': workOrder.status.code,
      'type': workOrder.type.code,
      'title': workOrder.title,
      'description': workOrder.description,
      'priority': workOrder.priority.code,
      'asset': workOrder.assetId,
      'asset_name': workOrder.assetName,
      'asset_criticality': workOrder.assetCriticality,
      'depot': workOrder.depotId,
      'depot_name': workOrder.depotName,
      'station_name': workOrder.stationName,
      'infrastructure_name': workOrder.infrastructureName,
      'infrastructure_type': workOrder.infrastructureType,
      'assigned_to': workOrder.assignedToId,
      'assigned_to_name': workOrder.assignedToName,
      'reported_by_name': workOrder.reportedByName,
      'verified_by_name': workOrder.verifiedByName,
      'due_date': workOrder.dueDate?.toIso8601String(),
      'created_at': workOrder.createdAt?.toIso8601String(),
      'report_completed_at': workOrder.reportCompletedAt?.toIso8601String(),
      'linked_record_id': workOrder.linkedRecordId,
      'ticket_number': workOrder.ticketNumber,
      'maintenance_master_name': workOrder.maintenanceMasterName,
      'sla_status': workOrder.slaStatus,
      'escalation_level': workOrder.escalationLevel,
      'station': workOrder.stationId,
      if (workOrder.latestEventSummary != null)
        'latest_event_summary': {
          'event_type': workOrder.latestEventSummary!.eventType,
          'actor': workOrder.latestEventSummary!.actor,
          'timestamp': workOrder.latestEventSummary!.createdAt?.toIso8601String(),
          'remarks': workOrder.latestEventSummary!.remarks,
        },
    };
    await prefs.setString('$_kWorkOrderDetailPrefix${workOrder.id}', jsonEncode(jsonMap));
  }

  @override
  Future<WorkOrder?> getCachedWorkOrderDetail(int id) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString('$_kWorkOrderDetailPrefix$id');
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return WorkOrder.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cacheMaintenanceRecord(MaintenanceRecord record) async {
    final prefs = await _getPrefs();
    // The model serialises itself with the same keys the API returns, so a
    // cached record reads back through the ordinary parser without a second,
    // drifting mapping to maintain here.
    await prefs.setString(
      '$_kRecordPrefix${record.id}',
      jsonEncode(record.toCacheJson()),
    );
  }

  @override
  Future<MaintenanceRecord?> getCachedMaintenanceRecord(int id) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString('$_kRecordPrefix$id');
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return MaintenanceRecord.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveOutboxCommands(List<OutboxCommand> commands) async {
    final prefs = await _getPrefs();
    final rawList = commands.map((c) => c.toJson()).toList();
    await prefs.setString(_kOutboxCommandsKey, jsonEncode(rawList));
  }

  @override
  Future<List<OutboxCommand>> getOutboxCommands() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_kOutboxCommandsKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((e) => OutboxCommand.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> clearAllCache() async {
    final prefs = await _getPrefs();
    await prefs.clear();
  }
}

class InMemoryLocalCacheService implements ILocalCacheService {
  final Map<String, dynamic> _storage = {};

  @override
  Future<void> cacheWorkOrders(List<WorkOrder> workOrders) async {
    _storage['work_orders'] = workOrders;
  }

  @override
  Future<List<WorkOrder>> getCachedWorkOrders() async {
    return (_storage['work_orders'] as List<WorkOrder>?) ?? [];
  }

  @override
  Future<void> cacheWorkOrderDetail(WorkOrder workOrder) async {
    _storage['wo_${workOrder.id}'] = workOrder;
  }

  @override
  Future<WorkOrder?> getCachedWorkOrderDetail(int id) async {
    return _storage['wo_$id'] as WorkOrder?;
  }

  @override
  Future<void> cacheMaintenanceRecord(MaintenanceRecord record) async {
    _storage['record_${record.id}'] = record;
  }

  @override
  Future<MaintenanceRecord?> getCachedMaintenanceRecord(int id) async {
    return _storage['record_$id'] as MaintenanceRecord?;
  }

  @override
  Future<void> saveOutboxCommands(List<OutboxCommand> commands) async {
    _storage['outbox'] = List<OutboxCommand>.from(commands);
  }

  @override
  Future<List<OutboxCommand>> getOutboxCommands() async {
    return (_storage['outbox'] as List<OutboxCommand>?) ?? [];
  }

  @override
  Future<void> clearAllCache() async {
    _storage.clear();
  }
}
