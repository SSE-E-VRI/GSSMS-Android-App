import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// A status transition the server says this user may (or may not) perform on a
/// work order, from `GET /maintenance/work-orders/{id}/allowed-actions/`.
///
/// The mobile client renders exactly what the server permits rather than
/// re-deriving transitions from the viewer's role: Django owns the workflow,
/// and a client-side guess drifts from it silently.
class WorkOrderAction extends Equatable {
  const WorkOrderAction({
    required this.targetStatus,
    required this.label,
    this.enabled = false,
    this.disabledReason,
    this.requiresReason = false,
    this.requiresFailureCode = false,
    this.guardStatus,
  });

  final String targetStatus;
  final String label;
  final bool enabled;
  final String? disabledReason;

  /// Server requires remarks with this transition.
  final bool requiresReason;

  /// Server requires a failure code with this transition.
  final bool requiresFailureCode;

  final String? guardStatus;

  factory WorkOrderAction.fromJson(Map<String, dynamic> json) {
    final req = json['requirements'];
    final requirements = req is Map ? Map<String, dynamic>.from(req) : null;
    return WorkOrderAction(
      targetStatus: asJsonString(json['target_status']) ?? '',
      label: asJsonString(json['label']) ?? asJsonString(json['target_status']) ?? '',
      enabled: asJsonBool(json['enabled']) ?? false,
      disabledReason: asJsonString(json['disabled_reason']),
      requiresReason: asJsonBool(json['requires_reason']) ??
          asJsonBool(requirements?['remarks']) ??
          false,
      requiresFailureCode: asJsonBool(requirements?['failure_code']) ?? false,
      guardStatus: asJsonString(json['guard_status']),
    );
  }

  @override
  List<Object?> get props => [
        targetStatus,
        label,
        enabled,
        disabledReason,
        requiresReason,
        requiresFailureCode,
        guardStatus,
      ];
}

/// The full allowed-actions response: what is permitted now, plus what is
/// visible-but-blocked so the technician can see *why* an action is unavailable.
class WorkOrderActionSet extends Equatable {
  const WorkOrderActionSet({
    required this.workOrderId,
    this.currentStatus,
    this.allowed = const [],
    this.blocked = const [],
  });

  final int workOrderId;
  final String? currentStatus;
  final List<WorkOrderAction> allowed;
  final List<WorkOrderAction> blocked;

  bool get hasAnyAction => allowed.isNotEmpty || blocked.isNotEmpty;

  factory WorkOrderActionSet.fromJson(Map<String, dynamic> json) {
    List<WorkOrderAction> parse(String key) {
      final raw = json[key];
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => WorkOrderAction.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    return WorkOrderActionSet(
      workOrderId: asJsonInt(json['work_order'] ?? json['work_order_id']) ?? 0,
      currentStatus: asJsonString(json['current_status']),
      allowed: parse('allowed_actions'),
      blocked: parse('blocked_actions'),
    );
  }

  @override
  List<Object?> get props => [workOrderId, currentStatus, allowed, blocked];
}
