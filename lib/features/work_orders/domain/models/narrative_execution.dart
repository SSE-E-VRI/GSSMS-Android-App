import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/mode_execution.dart'
    show ExecutionPhoto;

/// Narrative execution (SSOT JOB_WORK_ORIGINATION_AND_DEFICIENCY_SSOT RULE 5.1):
/// the findings / action / photos form used for breakdowns, deficiency
/// rectifications, manual Corrective, escalated inspection points and legacy
/// inspection conversions. The backend calls this mode `COMPLAINT`.
const String kNarrativeExecutionMode = 'COMPLAINT';

enum NarrativePhotoKind {
  before('BEFORE'),
  after('AFTER');

  const NarrativePhotoKind(this.code);
  final String code;
}

class NarrativePhoto extends Equatable {
  const NarrativePhoto({
    required this.id,
    required this.kind,
    required this.url,
    this.locked = false,
  });

  final int id;
  final String kind;
  final String url;

  /// Locked photos (already part of a submission, or copied from the
  /// breakdown report) cannot be removed by the technician.
  final bool locked;

  factory NarrativePhoto.fromJson(Map<String, dynamic> json) => NarrativePhoto(
        id: asJsonInt(json['id']) ?? 0,
        kind: (asJsonString(json['kind']) ?? '').toUpperCase(),
        url: asJsonString(json['url']) ?? asJsonString(json['image']) ?? '',
        locked: asJsonBool(json['locked']) ?? false,
      );

  @override
  List<Object?> get props => [id, kind, url, locked];
}

/// One Parameter / Value / Unit row. The backend rejects a row with a blank
/// parameter or value, so [isComplete] is the same rule applied locally.
class NarrativeParameter extends Equatable {
  const NarrativeParameter(
      {this.parameter = '', this.value = '', this.unit = ''});

  final String parameter;
  final String value;
  final String unit;

  bool get isComplete => parameter.trim().isNotEmpty && value.trim().isNotEmpty;

  NarrativeParameter copyWith(
          {String? parameter, String? value, String? unit}) =>
      NarrativeParameter(
        parameter: parameter ?? this.parameter,
        value: value ?? this.value,
        unit: unit ?? this.unit,
      );

  factory NarrativeParameter.fromJson(Map<String, dynamic> json) =>
      NarrativeParameter(
        parameter: asJsonString(json['parameter']) ?? '',
        value: asJsonString(json['value']) ?? '',
        unit: asJsonString(json['unit']) ?? '',
      );

  Map<String, dynamic> toJson() => {
        'parameter': parameter.trim(),
        'value': value.trim(),
        'unit': unit.trim(),
      };

  @override
  List<Object?> get props => [parameter, value, unit];
}

class NarrativeExecution extends Equatable {
  const NarrativeExecution({
    this.initialFindings = '',
    this.actionTaken = '',
    this.finalRemarks = '',
    this.parameters = const [],
    this.photos = const [],
  });

  final String initialFindings;
  final String actionTaken;
  final String finalRemarks;
  final List<NarrativeParameter> parameters;
  final List<NarrativePhoto> photos;

  List<NarrativePhoto> photosOf(NarrativePhotoKind kind) =>
      photos.where((p) => p.kind == kind.code).toList();

  factory NarrativeExecution.fromJson(Map<String, dynamic> json) {
    final rawParams = json['parameters'];
    final rawPhotos = json['photos'];
    return NarrativeExecution(
      initialFindings: asJsonString(json['initial_findings']) ?? '',
      actionTaken: asJsonString(json['action_taken']) ?? '',
      finalRemarks: asJsonString(json['final_remarks']) ?? '',
      parameters: rawParams is List
          ? rawParams
              .whereType<Map>()
              .map((m) =>
                  NarrativeParameter.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      photos: rawPhotos is List
          ? rawPhotos
              .whereType<Map>()
              .map((m) => NarrativePhoto.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props =>
      [initialFindings, actionTaken, finalRemarks, parameters, photos];
}

/// Read-only facts about the deficiency a rectification Job Work fixes.
class NarrativeDeficiency extends Equatable {
  const NarrativeDeficiency({
    required this.finding,
    this.equipment,
    this.checkpoint,
    this.severity,
    this.sourceTicket,
    this.stationName,
  });

  final String finding;
  final String? equipment;
  final String? checkpoint;
  final String? severity;
  final String? sourceTicket;
  final String? stationName;

  factory NarrativeDeficiency.fromJson(Map<String, dynamic> json) =>
      NarrativeDeficiency(
        finding: asJsonString(json['finding']) ?? '',
        equipment: asJsonString(json['equipment']),
        checkpoint: asJsonString(json['checkpoint']),
        severity: asJsonString(json['severity']),
        sourceTicket: asJsonString(json['source_ticket']),
        stationName: asJsonString(json['station_name']),
      );

  @override
  List<Object?> get props =>
      [finding, equipment, checkpoint, severity, sourceTicket, stationName];
}

/// What the screen needs to decide whether to use the narrative form and what
/// to show above it. Built from `GET records/<id>/` (`work_order_context`).
class NarrativeContext extends Equatable {
  const NarrativeContext({
    required this.workOrderId,
    required this.executionMode,
    required this.lineCount,
    this.ticketNumber = '',
    this.title = '',
    this.description = '',
    this.stationName,
    this.status = '',
    this.originalComplaintId,
    this.deficiency,
  });

  final int workOrderId;
  final String executionMode;
  final int lineCount;
  final String ticketNumber;
  final String title;
  final String description;
  final String? stationName;
  final String status;
  final int? originalComplaintId;
  final NarrativeDeficiency? deficiency;

  /// Narrative form only when the backend says so AND no checklist lines exist
  /// (mirrors `MaintenanceRecordForm.jsx`: such a Job Work keeps its checklist).
  bool get usesNarrativeForm =>
      executionMode == kNarrativeExecutionMode && lineCount == 0;

  /// Grouped deficiency rectification: the multi-item form.
  bool get usesRectificationForm =>
      executionMode == kRectificationExecutionMode && lineCount == 0;

  /// The backend accepts edits only while the Job Work is IN_PROGRESS.
  bool get isEditable => status == 'IN_PROGRESS';

  factory NarrativeContext.fromRecordJson(Map<String, dynamic> record) {
    final raw = record['work_order_context'];
    final context =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final lines = record['lines'];
    final deficiency = context['deficiency_details'];
    return NarrativeContext(
      workOrderId: asJsonInt(context['work_order_id']) ??
          asJsonInt(record['work_order']) ??
          0,
      executionMode:
          (asJsonString(context['execution_mode']) ?? '').toUpperCase(),
      lineCount: lines is List ? lines.length : 0,
      ticketNumber: asJsonString(context['ticket_number']) ?? '',
      title: asJsonString(context['title']) ?? '',
      description: asJsonString(context['description']) ?? '',
      stationName: asJsonString(context['station_name']),
      status: (asJsonString(context['status']) ?? '').toUpperCase(),
      originalComplaintId: asJsonInt(context['original_complaint_id']),
      deficiency: deficiency is Map
          ? NarrativeDeficiency.fromJson(Map<String, dynamic>.from(deficiency))
          : null,
    );
  }

  @override
  List<Object?> get props => [
        workOrderId,
        executionMode,
        lineCount,
        ticketNumber,
        title,
        description,
        stationName,
        status,
        originalComplaintId,
        deficiency,
      ];
}

/// Backend `execution_mode` for a grouped deficiency rectification
/// (SSOT section 6): one Job Work, one item per deficiency.
const String kRectificationExecutionMode = 'RECTIFICATION';

class RectificationItem extends Equatable {
  const RectificationItem({
    required this.id,
    this.asset = '',
    this.checkpoint = '',
    this.finding = '',
    this.severity,
    this.sourceTicket,
    this.actionTaken = '',
    this.outcome = '',
    this.reason = '',
    this.photos = const [],
    this.sourcePhotos = const [],
  });

  final int id;
  final String asset;
  final String checkpoint;
  final String finding;
  final String? severity;
  final String? sourceTicket;
  final String actionTaken;

  /// The checklist photos the deficiency was raised with (read-only).
  final List<ExecutionPhoto> sourcePhotos;

  /// '', 'RECTIFIED' or 'NOT_RECTIFIED'.
  final String outcome;
  final String reason;
  final List<NarrativePhoto> photos;

  bool get isRectified => outcome == 'RECTIFIED';
  bool get isNotRectified => outcome == 'NOT_RECTIFIED';

  List<NarrativePhoto> photosOf(NarrativePhotoKind kind) =>
      photos.where((p) => p.kind == kind.code).toList();

  /// Same per-item rules as the backend (SSOT 6.5) and the web form.
  List<String> blockers() {
    final label = '$asset — $checkpoint';
    final out = <String>[];
    if (actionTaken.trim().isEmpty) out.add('$label: write the action taken.');
    if (outcome.isEmpty) out.add('$label: choose Rectified or Not rectified.');
    if (photosOf(NarrativePhotoKind.before).isEmpty) {
      out.add('$label: add a Before photo.');
    }
    if (isRectified && photosOf(NarrativePhotoKind.after).isEmpty) {
      out.add('$label: add an After photo.');
    }
    if (isNotRectified && reason.trim().isEmpty) {
      out.add('$label: give the reason it could not be rectified.');
    }
    return out;
  }

  factory RectificationItem.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'];
    return RectificationItem(
      id: asJsonInt(json['id']) ?? 0,
      asset: asJsonString(json['asset']) ?? '',
      checkpoint: asJsonString(json['checkpoint']) ?? '',
      finding: asJsonString(json['finding']) ?? '',
      severity: asJsonString(json['severity']),
      sourceTicket: asJsonString(json['source_ticket']),
      actionTaken: asJsonString(json['action_taken']) ?? '',
      outcome: (asJsonString(json['outcome']) ?? '').toUpperCase(),
      reason: asJsonString(json['reason']) ?? '',
      photos: rawPhotos is List
          ? rawPhotos
              .whereType<Map>()
              .map((m) => NarrativePhoto.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
      sourcePhotos: ExecutionPhoto.listOf(json['source_photos']),
    );
  }

  @override
  List<Object?> get props => [
        id,
        asset,
        checkpoint,
        finding,
        severity,
        sourceTicket,
        actionTaken,
        outcome,
        reason,
        photos,
        sourcePhotos,
      ];
}

class RectificationExecution extends Equatable {
  const RectificationExecution({this.finalRemarks = '', this.items = const []});

  final String finalRemarks;
  final List<RectificationItem> items;

  factory RectificationExecution.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return RectificationExecution(
      finalRemarks: asJsonString(json['final_remarks']) ?? '',
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((m) =>
                  RectificationItem.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props => [finalRemarks, items];
}
