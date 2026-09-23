import 'dart:convert';
import 'package:flutter/foundation.dart';
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

  Future<int?> getCacheOwnerUserId();
  Future<void> setCacheOwnerUserId(int userId);

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
  static const String _kOutboxBackupKey = 'gssms_cache_outbox_commands_bak';
  static const String _kCacheOwnerUserIdKey = 'gssms_cache_owner_user_id';

  /// Last-good outbox decoded in this process. If the persisted JSON is
  /// corrupt at the top level, we return this instead of `[]` so a single
  /// bad write can never discard the entire queued-mutation backlog.
  static List<OutboxCommand> _lastGoodOutbox = const [];

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
      final result = <WorkOrder>[];
      var corrupt = 0;
      for (final e in decoded) {
        if (e is! Map) {
          corrupt++;
          continue;
        }
        try {
          result.add(WorkOrder.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {
          corrupt++;
        }
      }
      if (corrupt > 0) debugPrint('getCachedWorkOrders: quarantined $corrupt corrupt entries');
      return result;
    } catch (e) {
      debugPrint('getCachedWorkOrders: top-level corrupt, returning empty: $e');
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
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WorkOrder.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('getCachedWorkOrderDetail($id): corrupt entry quarantined: $e');
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
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return MaintenanceRecord.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('getCachedMaintenanceRecord($id): corrupt entry quarantined: $e');
      return null;
    }
  }

  @override
  Future<void> saveOutboxCommands(List<OutboxCommand> commands) async {
    final prefs = await _getPrefs();
    final rawList = commands.map((c) => c.toJson()).toList();
    final encoded = jsonEncode(rawList);
    final ok = await prefs.setString(_kOutboxCommandsKey, encoded);
    if (!ok) debugPrint('saveOutboxCommands: setString failed for ${commands.length} commands');
    // Keep a backup copy so a torn write can be recovered on next read.
    try {
      await prefs.setString(_kOutboxBackupKey, encoded);
    } catch (_) {}
    _lastGoodOutbox = List<OutboxCommand>.from(commands);
  }

  @override
  Future<List<OutboxCommand>> getOutboxCommands() async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_kOutboxCommandsKey);
    if (raw == null || raw.isEmpty) return List<OutboxCommand>.from(_lastGoodOutbox);

    List<dynamic>? decoded;
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) {
        decoded = parsed;
      } else {
        throw const FormatException('outbox top-level is not a List');
      }
    } catch (e) {
      // Try the backup copy before falling back to last-good memory.
      debugPrint('getOutboxCommands: top-level corrupt, trying backup: $e');
      try {
        final bak = prefs.getString(_kOutboxBackupKey);
        if (bak != null && bak.isNotEmpty) {
          final parsedBak = jsonDecode(bak);
          if (parsedBak is List) decoded = parsedBak;
        }
      } catch (_) {}
      if (decoded == null) {
        return List<OutboxCommand>.from(_lastGoodOutbox);
      }
    }

    final validCommands = <OutboxCommand>[];
    var corrupt = 0;
    final items = decoded ?? const [];
    for (final item in items) {
      if (item is Map) {
        try {
          validCommands.add(OutboxCommand.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {
          corrupt++;
          // Skip corrupted command entry without dropping remaining valid outbox items
        }
      } else {
        corrupt++;
      }
    }
    if (corrupt > 0) debugPrint('getOutboxCommands: quarantined $corrupt corrupt entries');
    _lastGoodOutbox = List<OutboxCommand>.from(validCommands);
    return validCommands;
  }

  @override
  Future<int?> getCacheOwnerUserId() async {
    final prefs = await _getPrefs();
    return prefs.getInt(_kCacheOwnerUserIdKey);
  }

  @override
  Future<void> setCacheOwnerUserId(int userId) async {
    final prefs = await _getPrefs();
    await prefs.setInt(_kCacheOwnerUserIdKey, userId);
  }

  @override
  Future<void> clearAllCache() async {
    final prefs = await _getPrefs();
    final keys = prefs.getKeys();
    for (final key in keys) {
      if (key.startsWith('gssms_cache_')) {
        await prefs.remove(key);
      }
    }
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
    final stored = _storage['outbox'] as List<OutboxCommand>?;
    // Return a copy: callers mutate (add/removeWhere) before save, and must
    // never mutate the store's live list pre-save.
    if (stored == null) return [];
    return List<OutboxCommand>.from(stored);
  }

  @override
  Future<int?> getCacheOwnerUserId() async {
    return _storage['owner_user_id'] as int?;
  }

  @override
  Future<void> setCacheOwnerUserId(int userId) async {
    _storage['owner_user_id'] = userId;
  }

  @override
  Future<void> clearAllCache() async {
    _storage.clear();
  }
}
