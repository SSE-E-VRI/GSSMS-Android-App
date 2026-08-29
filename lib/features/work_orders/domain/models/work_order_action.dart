import 'package:equatable/equatable.dart';

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
    final requirements = json['requirements'] as Map<String, dynamic>?;
    return WorkOrderAction(
      targetStatus: json['target_status'] as String? ?? '',
      label: json['label'] as String? ?? json['target_status'] as String? ?? '',
      enabled: json['enabled'] as bool? ?? false,
      disabledReason: json['disabled_reason'] as String?,
      requiresReason: json['requires_reason'] as bool? ??
          requirements?['remarks'] as bool? ??
          false,
      requiresFailureCode: requirements?['failure_code'] as bool? ?? false,
      guardStatus: json['guard_status'] as String?,
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
      final raw = json[key] as List<dynamic>? ?? const [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(WorkOrderAction.fromJson)
          .toList();
    }

    return WorkOrderActionSet(
      workOrderId: json['work_order'] as int? ?? 0,
      currentStatus: json['current_status'] as String?,
      allowed: parse('allowed_actions'),
      blocked: parse('blocked_actions'),
    );
  }

  @override
  List<Object?> get props => [workOrderId, currentStatus, allowed, blocked];
}
