import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection_evidence_photo.dart';

/// Point-level priority. Web `PRIORITY_CHOICES` + InspectionForm options.
enum InspectionPointPriority {
  high('HIGH', 'High'),
  medium('MEDIUM', 'Medium'),
  low('LOW', 'Low'),
  unknown('UNKNOWN', 'Unknown');

  const InspectionPointPriority(this.code, this.displayName);
  final String code;
  final String displayName;

  static InspectionPointPriority fromString(String? code) {
    if (code == null) return InspectionPointPriority.medium;
    final upper = code.toUpperCase().trim();
    for (final p in InspectionPointPriority.values) {
      if (p.code == upper) return p;
    }
    return InspectionPointPriority.unknown;
  }
}

/// Point disposition FSM (DOC-CMMS-INSP-001 §6).
enum PointDispositionStatus {
  unassigned('UNASSIGNED', 'Unassigned'),
  assigned('ASSIGNED', 'Assigned'),
  resolved('RESOLVED', 'Resolved'),
  disposed('DISPOSED', 'Disposed'),
  unresolved('UNRESOLVED', 'Unresolved'),
  approvedForJw2('APPROVED_FOR_JW2', 'Approved for JW2'),
  unknown('UNKNOWN', 'Unknown');

  const PointDispositionStatus(this.code, this.displayName);
  final String code;
  final String displayName;

  static PointDispositionStatus fromString(String? code) {
    if (code == null) return PointDispositionStatus.unknown;
    final upper = code.toUpperCase().trim();
    for (final s in PointDispositionStatus.values) {
      if (s.code == upper) return s;
    }
    return PointDispositionStatus.unknown;
  }

  bool get isTerminal =>
      this == PointDispositionStatus.resolved ||
      this == PointDispositionStatus.disposed;
}

/// One clubbed Job Work assignment on a point (web `get_job_works` on point).
class PointJobWorkRef extends Equatable {
  const PointJobWorkRef({
    required this.sequence,
    this.workOrderId,
    this.ticketNumber,
    this.workOrderStatus,
    this.createdAt,
  });

  final int sequence;
  final int? workOrderId;
  final String? ticketNumber;
  final String? workOrderStatus;
  final DateTime? createdAt;

  factory PointJobWorkRef.fromJson(Map<String, dynamic> json) {
    return PointJobWorkRef(
      sequence: asJsonInt(json['sequence']) ?? 0,
      workOrderId: asJsonInt(json['work_order_id']),
      ticketNumber: asJsonString(json['ticket_number']),
      workOrderStatus: asJsonString(json['work_order_status']),
      createdAt: asJsonDateTime(json['created_at']),
    );
  }

  @override
  List<Object?> get props =>
      [sequence, workOrderId, ticketNumber, workOrderStatus, createdAt];
}

/// Post-JW2 escalation WorkOrder linked to a point (web `get_escalated_work_orders`).
class EscalatedWorkOrderRef extends Equatable {
  const EscalatedWorkOrderRef({
    this.id,
    this.ticketNumber,
    this.title,
    this.type,
    this.status,
    this.isActive,
    this.createdAt,
  });

  final int? id;
  final String? ticketNumber;
  final String? title;
  final String? type;
  final String? status;
  final bool? isActive;
  final DateTime? createdAt;

  factory EscalatedWorkOrderRef.fromJson(Map<String, dynamic> json) {
    return EscalatedWorkOrderRef(
      id: asJsonInt(json['id']),
      ticketNumber: asJsonString(json['ticket_number']),
      title: asJsonString(json['title']),
      type: asJsonString(json['type']),
      status: asJsonString(json['status']),
      isActive: asJsonBool(json['is_active']),
      createdAt: asJsonDateTime(json['created_at']),
    );
  }

  @override
  List<Object?> get props =>
      [id, ticketNumber, title, type, status, isActive, createdAt];
}

/// Structured observation point. Mirrors `InspectionPointSerializer`.
class InspectionPoint extends Equatable {
  const InspectionPoint({
    required this.id,
    required this.inspectionId,
    required this.pointNumber,
    required this.observation,
    this.priority = InspectionPointPriority.medium,
    this.assetId,
    this.assetUniqueId,
    this.assetName,
    this.itemReference,
    this.dispositionStatus = PointDispositionStatus.unassigned,
    this.disposedReason,
    this.disposedRemarks,
    this.disposedByName,
    this.disposedAt,
    this.resolvedByName,
    this.resolvedAt,
    this.resolutionRemarks,
    this.unresolvedByName,
    this.unresolvedAt,
    this.unresolvedReason,
    this.unresolvedRemarks,
    this.jw2ApprovedByName,
    this.jw2ApprovedAt,
    this.jw2ApprovalRemarks,
    this.jobWorks = const [],
    this.evidencePhotos = const [],
    this.escalatedWorkOrders = const [],
    this.createdAt,
    this.updatedAt,
  });

  final int id;
  final int inspectionId;
  final int pointNumber;
  final String observation;
  final InspectionPointPriority priority;
  final int? assetId;
  final String? assetUniqueId;
  final String? assetName;
  final String? itemReference;
  final PointDispositionStatus dispositionStatus;

  final String? disposedReason;
  final String? disposedRemarks;
  final String? disposedByName;
  final DateTime? disposedAt;

  final String? resolvedByName;
  final DateTime? resolvedAt;
  final String? resolutionRemarks;

  final String? unresolvedByName;
  final DateTime? unresolvedAt;
  final String? unresolvedReason;
  final String? unresolvedRemarks;

  final String? jw2ApprovedByName;
  final DateTime? jw2ApprovedAt;
  final String? jw2ApprovalRemarks;

  final List<PointJobWorkRef> jobWorks;
  final List<InspectionEvidencePhoto> evidencePhotos;
  final List<EscalatedWorkOrderRef> escalatedWorkOrders;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static List<PointJobWorkRef> _parseJobWorks(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => PointJobWorkRef.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<EscalatedWorkOrderRef> _parseEscalated(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map(
            (e) => EscalatedWorkOrderRef.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static List<InspectionEvidencePhoto> _parsePhotos(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) =>
            InspectionEvidencePhoto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  factory InspectionPoint.fromJson(Map<String, dynamic> json) {
    int? fkId(dynamic v) => v is Map ? asJsonInt(v['id']) : asJsonInt(v);
    return InspectionPoint(
      id: asJsonInt(json['id']) ?? 0,
      inspectionId: asJsonInt(json['inspection']) ?? 0,
      pointNumber: asJsonInt(json['point_number']) ?? 0,
      observation: asJsonString(json['observation']) ?? '',
      priority: InspectionPointPriority.fromString(
          asJsonString(json['priority'])),
      assetId: fkId(json['asset']),
      assetUniqueId: asJsonString(json['asset_unique_id']),
      assetName: asJsonString(json['asset_name']),
      itemReference: asJsonString(json['item_reference']),
      dispositionStatus: PointDispositionStatus.fromString(
          asJsonString(json['disposition_status'])),
      disposedReason: asJsonString(json['disposed_reason']),
      disposedRemarks: asJsonString(json['disposed_remarks']),
      disposedByName: asJsonString(json['disposed_by_name']),
      disposedAt: asJsonDateTime(json['disposed_at']),
      resolvedByName: asJsonString(json['resolved_by_name']),
      resolvedAt: asJsonDateTime(json['resolved_at']),
      resolutionRemarks: asJsonString(json['resolution_remarks']),
      unresolvedByName: asJsonString(json['unresolved_by_name']),
      unresolvedAt: asJsonDateTime(json['unresolved_at']),
      unresolvedReason: asJsonString(json['unresolved_reason']),
      unresolvedRemarks: asJsonString(json['unresolved_remarks']),
      jw2ApprovedByName: asJsonString(json['jw2_approved_by_name']),
      jw2ApprovedAt: asJsonDateTime(json['jw2_approved_at']),
      jw2ApprovalRemarks: asJsonString(json['jw2_approval_remarks']),
      jobWorks: _parseJobWorks(json['job_works']),
      evidencePhotos: _parsePhotos(json['evidence_photos']),
      escalatedWorkOrders: _parseEscalated(json['escalated_work_orders']),
      createdAt: asJsonDateTime(json['created_at']),
      updatedAt: asJsonDateTime(json['updated_at']),
    );
  }

  /// Display scope: registered asset, else manual item, else general.
  String get scopeLabel {
    if (assetUniqueId != null && assetUniqueId!.trim().isNotEmpty) {
      final name = assetName?.trim();
      return name != null && name.isNotEmpty
          ? '${assetUniqueId!.trim()} ($name)'
          : assetUniqueId!.trim();
    }
    if (itemReference != null && itemReference!.trim().isNotEmpty) {
      return itemReference!.trim();
    }
    return 'General item';
  }

  // ——— Eligibility helpers (mirror web InspectionDetailView.jsx) ———

  bool get hasReachedMaxJw =>
      jobWorks.length >= 2 || jobWorks.any((j) => j.sequence >= 2);

  bool isEligibleForJw1({required bool inspectionClosed}) {
    if (inspectionClosed) return false;
    if (dispositionStatus != PointDispositionStatus.unassigned) return false;
    return jobWorks.isEmpty;
  }

  bool isEligibleForJw2({required bool inspectionClosed}) {
    if (inspectionClosed) return false;
    if (dispositionStatus != PointDispositionStatus.approvedForJw2) {
      return false;
    }
    if (jobWorks.length != 1) return false;
    return jobWorks.first.sequence == 1;
  }

  static const _activeEscalationStatuses = {
    'NEW',
    'ASSIGNED',
    'IN_PROGRESS',
    'ON_HOLD',
    'TECH_COMPLETED',
    'REWORK_REQUIRED',
    'VERIFIED',
  };

  static const _blockingEscalationStatuses = {
    'NEW',
    'ASSIGNED',
    'IN_PROGRESS',
    'ON_HOLD',
    'TECH_COMPLETED',
    'REWORK_REQUIRED',
  };

  bool _hasEscalationIn(Set<String> statuses) {
    if (escalatedWorkOrders.isEmpty) return false;
    return escalatedWorkOrders.any((wo) =>
        statuses.contains((wo.status ?? '').toUpperCase().trim()));
  }

  bool get hasActiveEscalation => _hasEscalationIn(_activeEscalationStatuses);
  bool get hasBlockingEscalation =>
      _hasEscalationIn(_blockingEscalationStatuses);

  bool isEligibleForEscalation({required bool inspectionClosed}) {
    if (inspectionClosed) return false;
    if (dispositionStatus == PointDispositionStatus.resolved ||
        dispositionStatus == PointDispositionStatus.disposed) {
      return false;
    }
    if (hasActiveEscalation) return false;
    if (jobWorks.length != 2) return false;
    final jw1 = jobWorks.where((j) => j.sequence == 1);
    final jw2 = jobWorks.where((j) => j.sequence == 2);
    if (jw1.isEmpty || jw2.isEmpty) return false;
    final s = (jw2.first.workOrderStatus ?? '').toUpperCase();
    return s == 'VERIFIED' || s == 'CLOSED';
  }

  /// Backend only accepts a new point photo while UNASSIGNED.
  bool canUploadPointPhoto({required bool inspectionClosed}) {
    return !inspectionClosed &&
        dispositionStatus == PointDispositionStatus.unassigned;
  }

  @override
  List<Object?> get props => [
        id,
        inspectionId,
        pointNumber,
        observation,
        priority,
        assetId,
        assetUniqueId,
        assetName,
        itemReference,
        dispositionStatus,
        disposedReason,
        disposedRemarks,
        disposedByName,
        disposedAt,
        resolvedByName,
        resolvedAt,
        resolutionRemarks,
        unresolvedByName,
        unresolvedAt,
        unresolvedReason,
        unresolvedRemarks,
        jw2ApprovedByName,
        jw2ApprovedAt,
        jw2ApprovalRemarks,
        jobWorks,
        evidencePhotos,
        escalatedWorkOrders,
        createdAt,
        updatedAt,
      ];
}

/// Canonical reason enums (web DISPOSE_REASONS / UNRESOLVED_REASONS).
class InspectionPointReasons {
  static const disposeReasons = [
    'NOT_APPLICABLE',
    'OBSOLETE',
    'DUPLICATE',
    'FALSE_ALARM',
    'OTHER',
  ];
  static const unresolvedReasons = [
    'DEFECT_PERSISTS',
    'COMPONENT_FAILED',
    'SPECIALIST_REQUIRED',
    'PARTIAL_REPAIR',
    'OTHER',
  ];
}
