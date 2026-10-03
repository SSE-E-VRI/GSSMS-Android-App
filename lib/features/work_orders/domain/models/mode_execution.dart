import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';

/// Which technician execution UI a Job Work needs. The server owns the
/// bucket (`WorkOrder.execution_mode`); the app only routes to the matching
/// form — never invents a mode.
enum ExecutionRoute {
  checklist,
  complaint,
  inspection,
  rectification,
}

/// Mirrors the server's execution-mode contract: COMPLAINT /
/// RECTIFICATION / INSPECTION modes each have a dedicated execution form
/// and submit endpoint, while CHECKLIST (and legacy rows without a mode)
/// use the generic checklist record flow. Origin wins over the mode
/// string, matching web's `jobWorkType` check order.
ExecutionRoute executionRouteFor(WorkOrder workOrder) {
  if (workOrder.originalComplaintId != null) {
    return ExecutionRoute.complaint;
  }
  if (workOrder.originalDeficiencyId != null ||
      (workOrder.executionMode ?? '').toUpperCase().trim() ==
          'RECTIFICATION') {
    return ExecutionRoute.rectification;
  }
  if (workOrder.originalInspectionId != null ||
      (workOrder.executionMode ?? '').toUpperCase().trim() ==
          'INSPECTION') {
    return ExecutionRoute.inspection;
  }
  switch ((workOrder.executionMode ?? '').toUpperCase().trim()) {
    case 'COMPLAINT':
      return ExecutionRoute.complaint;
    case 'RECTIFICATION':
      return ExecutionRoute.rectification;
    case 'INSPECTION':
      return ExecutionRoute.inspection;
    default:
      return ExecutionRoute.checklist;
  }
}

/// One Before/After evidence photo on a mode execution. Shapes differ
/// slightly per serializer (`locked` vs `locked_by_submission`,
/// `photo_type` vs `kind`, `url` vs `image`) — all coerced here.
class ExecutionPhoto extends Equatable {
  const ExecutionPhoto({
    required this.id,
    this.kind,
    this.url,
    this.locked = false,
    this.fromComplaint = false,
    this.uploadedAt,
    this.uploadedByName,
    this.caption,
  });

  final int id;
  final String? kind;
  final String? url;
  final bool locked;
  final bool fromComplaint;
  final DateTime? uploadedAt;
  final String? uploadedByName;
  final String? caption;

  bool get isBefore => (kind ?? '').toUpperCase() == 'BEFORE';
  bool get isAfter => (kind ?? '').toUpperCase() == 'AFTER';

  static List<ExecutionPhoto> listOf(dynamic v) {
    if (v is! List) return const [];
    return v
        .whereType<Map>()
        .map((e) => ExecutionPhoto.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  factory ExecutionPhoto.fromJson(Map<String, dynamic> json) {
    final rawUrl = json['url'] ?? json['image'];
    final lockedBy = json['locked_by_submission'];
    return ExecutionPhoto(
      id: asJsonInt(json['id']) ?? 0,
      kind: asJsonString(json['kind']) ?? asJsonString(json['photo_type']),
      url: rawUrl == null ? null : rawUrl.toString(),
      locked: asJsonBool(json['locked']) ??
          (lockedBy != null && lockedBy.toString().isNotEmpty),
      fromComplaint: asJsonBool(json['from_complaint']) ??
          (asJsonInt(json['source_complaint_photo_id']) ?? 0) != 0,
      uploadedAt: asJsonDateTime(json['uploaded_at']),
      uploadedByName: asJsonString(json['uploaded_by_name']) ??
          asJsonString(json['uploaded_by']),
      caption: asJsonString(json['caption']),
    );
  }

  @override
  List<Object?> get props =>
      [id, kind, url, locked, fromComplaint, uploadedAt, uploadedByName, caption];
}

/// Technician's complaint (Breakdown) execution record.
class ComplaintExecution extends Equatable {
  const ComplaintExecution({
    required this.id,
    this.initialFindings = '',
    this.actionTaken = '',
    this.finalRemarks = '',
    this.parameters = const [],
    this.photos = const [],
    this.updatedByName,
    this.updatedAt,
  });

  final int id;
  final String initialFindings;
  final String actionTaken;
  final String finalRemarks;
  final List<Map<String, String>> parameters;
  final List<ExecutionPhoto> photos;
  final String? updatedByName;
  final DateTime? updatedAt;

  bool get hasBefore => photos.any((p) => p.isBefore);
  bool get hasAfter => photos.any((p) => p.isAfter);

  static List<Map<String, String>> _params(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return {
        'parameter': asJsonString(m['parameter']) ?? '',
        'value': asJsonString(m['value']) ?? '',
        'unit': asJsonString(m['unit']) ?? '',
      };
    }).toList();
  }

  factory ComplaintExecution.fromJson(Map<String, dynamic> json) {
    return ComplaintExecution(
      id: asJsonInt(json['id']) ?? 0,
      initialFindings: asJsonString(json['initial_findings']) ?? '',
      actionTaken: asJsonString(json['action_taken']) ?? '',
      finalRemarks: asJsonString(json['final_remarks']) ?? '',
      parameters: _params(json['parameters']),
      photos: ExecutionPhoto.listOf(json['photos']),
      updatedByName: asJsonString(json['updated_by_name']),
      updatedAt: asJsonDateTime(json['updated_at']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        initialFindings,
        actionTaken,
        finalRemarks,
        parameters,
        photos,
        updatedByName,
        updatedAt,
      ];
}

/// One deficiency item on a grouped rectification Job Work.
class RectificationItem extends Equatable {
  const RectificationItem({
    required this.id,
    this.deficiencyId,
    this.asset = '',
    this.checkpoint = '',
    this.finding = '',
    this.severity,
    this.targetDate,
    this.detectedAt,
    this.sourceTicket,
    this.actionTaken = '',
    this.outcome = '',
    this.reason = '',
    this.photos = const [],
    this.isActive = true,
  });

  final int id;
  final int? deficiencyId;
  final String asset;
  final String checkpoint;
  final String finding;
  final String? severity;
  final DateTime? targetDate;
  final DateTime? detectedAt;
  final String? sourceTicket;
  final String actionTaken;
  final String outcome;
  final String reason;
  final List<ExecutionPhoto> photos;
  final bool isActive;

  bool get isRectified => outcome.toUpperCase() == 'RECTIFIED';

  factory RectificationItem.fromJson(Map<String, dynamic> json) {
    DateTime? date(dynamic v) {
      if (v == null || v == '') return null;
      return asJsonDateTime(v);
    }

    return RectificationItem(
      id: asJsonInt(json['id']) ?? 0,
      deficiencyId: asJsonInt(json['deficiency_id']),
      asset: asJsonString(json['asset']) ?? '',
      checkpoint: asJsonString(json['checkpoint']) ?? '',
      finding: asJsonString(json['finding']) ?? '',
      severity: asJsonString(json['severity']),
      targetDate: date(json['target_date']),
      detectedAt: date(json['detected_at']),
      sourceTicket: asJsonString(json['source_ticket']),
      actionTaken: asJsonString(json['action_taken']) ?? '',
      outcome: asJsonString(json['outcome']) ?? '',
      reason: asJsonString(json['reason']) ?? '',
      photos: ExecutionPhoto.listOf(json['photos']),
      isActive: asJsonBool(json['is_active']) ?? true,
    );
  }

  @override
  List<Object?> get props => [
        id,
        deficiencyId,
        asset,
        checkpoint,
        finding,
        severity,
        targetDate,
        detectedAt,
        sourceTicket,
        actionTaken,
        outcome,
        reason,
        photos,
        isActive,
      ];
}

/// Rectification execution payload (form + verify modal + report share it).
class RectificationPayload extends Equatable {
  const RectificationPayload({
    this.workOrderId,
    this.ticketNumber,
    this.status,
    this.editable = false,
    this.finalRemarks = '',
    this.otherStaff = '',
    this.items = const [],
    this.technician,
    this.stationName,
  });

  final int? workOrderId;
  final String? ticketNumber;
  final String? status;
  final bool editable;
  final String finalRemarks;
  final String otherStaff;
  final List<RectificationItem> items;
  final String? technician;
  final String? stationName;

  factory RectificationPayload.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    return RectificationPayload(
      workOrderId: asJsonInt(json['work_order_id']),
      ticketNumber: asJsonString(json['ticket_number']),
      status: asJsonString(json['status']),
      editable: asJsonBool(json['editable']) ?? false,
      finalRemarks: asJsonString(json['final_remarks']) ?? '',
      otherStaff: asJsonString(json['other_staff']) ?? '',
      items: rawItems is List
          ? rawItems
              .whereType<Map>()
              .map((e) =>
                  RectificationItem.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      technician: asJsonString(json['technician']),
      stationName: asJsonString(json['station_name']),
    );
  }

  @override
  List<Object?> get props => [
        workOrderId,
        ticketNumber,
        status,
        editable,
        finalRemarks,
        otherStaff,
        items,
        technician,
        stationName,
      ];
}

/// One point's execution inside a pointwise inspection Job Work. The GET
/// response merges static point metadata with the live execution object
/// (`points[].execution`); both shapes are accepted here.
class InspectionPointExecutionEntry extends Equatable {
  const InspectionPointExecutionEntry({
    required this.pointJobWorkId,
    this.pointId,
    this.pointNumber = 0,
    this.observation = '',
    this.assetName,
    this.priority,
    this.sequence = 1,
    this.hasExecution = false,
    this.initialFindings = '',
    this.actionTaken = '',
    this.finalRemarks = '',
    this.correctiveActionPerformed = true,
    this.technicalParameters = const [],
    this.photos = const [],
  });

  final int pointJobWorkId;
  final int? pointId;
  final int pointNumber;
  final String observation;
  final String? assetName;
  final String? priority;
  final int sequence;
  final bool hasExecution;
  final String initialFindings;
  final String actionTaken;
  final String finalRemarks;
  final bool correctiveActionPerformed;
  final List<Map<String, String>> technicalParameters;
  final List<ExecutionPhoto> photos;

  static List<Map<String, String>> paramsOf(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) {
      final m = Map<String, dynamic>.from(e);
      return {
        'parameter': asJsonString(m['parameter']) ?? '',
        'value': asJsonString(m['value']) ?? '',
        'unit': asJsonString(m['unit']) ?? '',
      };
    }).toList();
  }

  factory InspectionPointExecutionEntry.fromJson(Map<String, dynamic> json) {
    final execRaw = json['execution'];
    final exec = execRaw is Map<String, dynamic>
        ? execRaw
        : execRaw is Map
            ? Map<String, dynamic>.from(execRaw)
            : <String, dynamic>{};

    T pick<T>(String key, T fallback) {
      final v = exec.containsKey(key) ? exec[key] : json[key];
      return (v as T?) ?? fallback;
    }

    bool corrective(dynamic v, bool fallback) {
      if (v == null) return fallback;
      if (v is bool) return v;
      return v.toString().toLowerCase() == 'true' ||
          v.toString() == '1';
    }

    final techParams = paramsOf(
        exec['technical_parameters'] ?? exec['parameters'] ?? json['technical_parameters'] ?? json['parameters']);

    return InspectionPointExecutionEntry(
      pointJobWorkId: asJsonInt(
              json['point_job_work_id'] ?? exec['point_job_work_id']) ??
          0,
      pointId: asJsonInt(json['point_id'] ?? exec['point_id']),
      pointNumber: asJsonInt(json['point_number'] ?? exec['point_number']) ?? 0,
      observation: asJsonString(json['observation'] ?? exec['observation']) ?? '',
      assetName: asJsonString(json['asset_name'] ?? exec['asset_name']),
      priority: asJsonString(json['priority'] ?? exec['priority']),
      sequence:
          asJsonInt(json['sequence'] ?? exec['sequence']) ?? 1,
      hasExecution:
          asJsonBool(json['has_execution']) ?? exec['id'] != null,
      initialFindings: pick<String>('initial_findings', ''),
      actionTaken: pick<String>('action_taken', ''),
      finalRemarks: pick<String>('final_remarks', ''),
      correctiveActionPerformed: corrective(
          exec.containsKey('corrective_action_performed')
              ? exec['corrective_action_performed']
              : json['corrective_action_performed'],
          true),
      technicalParameters: techParams,
      photos: ExecutionPhoto.listOf(exec['photos'] ?? json['photos']),
    );
  }

  Map<String, dynamic> toSubmitJson() => {
        'point_job_work_id': pointJobWorkId,
        'id': pointJobWorkId,
        'initial_findings': initialFindings,
        'action_taken': actionTaken,
        'final_remarks': finalRemarks,
        'corrective_action_performed': correctiveActionPerformed,
        'technical_parameters': technicalParameters,
        'parameters': technicalParameters,
      };

  @override
  List<Object?> get props => [
        pointJobWorkId,
        pointId,
        pointNumber,
        observation,
        assetName,
        priority,
        sequence,
        hasExecution,
        initialFindings,
        actionTaken,
        finalRemarks,
        correctiveActionPerformed,
        technicalParameters,
        photos,
      ];
}

/// Pointwise inspection execution aggregate (GET/PATCH/submit share it).
class PointwiseInspectionExecution extends Equatable {
  const PointwiseInspectionExecution({
    this.workOrderId,
    this.ticketNumber,
    this.points = const [],
    this.inspectionNumber,
    this.inspectionTitle,
    this.inspectionDate,
    this.stationName,
    this.inspectorName,
    this.overallRemarks,
  });

  final int? workOrderId;
  final String? ticketNumber;
  final List<InspectionPointExecutionEntry> points;
  final String? inspectionNumber;
  final String? inspectionTitle;
  final String? inspectionDate;
  final String? stationName;
  final String? inspectorName;
  final String? overallRemarks;

  factory PointwiseInspectionExecution.fromJson(Map<String, dynamic> json) {
    final rawPoints = json['points'];
    final detailsRaw = json['inspection_details'];
    final details = detailsRaw is Map
        ? Map<String, dynamic>.from(detailsRaw)
        : <String, dynamic>{};
    return PointwiseInspectionExecution(
      workOrderId: asJsonInt(json['work_order']),
      ticketNumber: asJsonString(json['ticket_number']),
      points: rawPoints is List
          ? rawPoints
              .whereType<Map>()
              .map((e) => InspectionPointExecutionEntry.fromJson(
                  Map<String, dynamic>.from(e)))
              .toList()
          : const [],
      inspectionNumber: asJsonString(details['inspection_number']),
      inspectionTitle: asJsonString(details['inspection_title']),
      inspectionDate: asJsonString(details['inspection_date']),
      stationName: asJsonString(details['station_name']),
      inspectorName: asJsonString(details['inspector_name']),
      overallRemarks: asJsonString(details['inspection_remarks']),
    );
  }

  @override
  List<Object?> get props => [
        workOrderId,
        ticketNumber,
        points,
        inspectionNumber,
        inspectionTitle,
        inspectionDate,
        stationName,
        inspectorName,
        overallRemarks,
      ];
}
