import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/sync/outbox_command.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// How a checklist line captures its reading.
///
/// Mirrors `MaintenanceItem.VALUE_TYPE_CHOICES` in the Django backend.
enum MaintenanceValueType {
  status('STATUS'),
  yesNo('YES_NO'),
  number('NUMBER'),
  decimal('DECIMAL'),
  text('TEXT'),
  ryb('RYB'),
  voltAmp('VOLT_AMP'),
  unknown('UNKNOWN');

  const MaintenanceValueType(this.code);
  final String code;

  /// Component keys for the multi-part value types, in display order.
  /// The labels are the exact keys the web client reads and writes.
  List<String> get componentKeys {
    switch (this) {
      case MaintenanceValueType.ryb:
        return const ['R', 'Y', 'B'];
      case MaintenanceValueType.voltAmp:
        return const ['Volt', 'Amp'];
      default:
        return const [];
    }
  }

  bool get isMultiPart => componentKeys.isNotEmpty;

  bool get isNumeric =>
      this == MaintenanceValueType.number || this == MaintenanceValueType.decimal;

  static MaintenanceValueType fromString(String? code) {
    if (code == null) return MaintenanceValueType.unknown;
    final normalized = code.trim().toUpperCase();
    for (final t in MaintenanceValueType.values) {
      if (t.code == normalized) return t;
    }
    return MaintenanceValueType.unknown;
  }
}

/// Whether a line is a pass/fail inspection point or a recorded measurement.
enum MaintenanceItemKind {
  inspectionPoint('INSPECTION_POINT'),
  recordParameter('RECORD_PARAMETER'),
  unknown('UNKNOWN');

  const MaintenanceItemKind(this.code);
  final String code;

  static MaintenanceItemKind fromString(String? code) {
    if (code == null) return MaintenanceItemKind.unknown;
    final normalized = code.trim().toUpperCase();
    for (final k in MaintenanceItemKind.values) {
      if (k.code == normalized) return k;
    }
    return MaintenanceItemKind.unknown;
  }
}

/// An "action taken" choice. The backend only accepts an action that belongs to
/// the status option currently selected on the line, so these are nested rather
/// than offered as one flat list.
class MaintenanceActionOption extends Equatable {
  const MaintenanceActionOption({
    required this.id,
    required this.label,
    this.isDeficiency = false,
  });

  final int id;
  final String label;
  final bool isDeficiency;

  factory MaintenanceActionOption.fromJson(Map<String, dynamic> json) {
    return MaintenanceActionOption(
      id: asJsonInt(json['id']) ?? 0,
      label: asJsonString(json['label']) ?? asJsonString(json['name']) ?? '',
      isDeficiency: asJsonBool(json['is_deficiency']) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'is_deficiency': isDeficiency,
      };

  @override
  List<Object?> get props => [id, label, isDeficiency];
}

class MaintenanceStatusOption extends Equatable {
  const MaintenanceStatusOption({
    required this.id,
    required this.label,
    this.semantic,
    this.isDeficiency = false,
    this.actionOptions = const [],
  });

  final int id;
  final String label;
  final String? semantic;
  final bool isDeficiency;
  final List<MaintenanceActionOption> actionOptions;

  factory MaintenanceStatusOption.fromJson(Map<String, dynamic> json) {
    final rawActions = json['action_options'];
    final actionList = rawActions is List ? rawActions : const [];
    return MaintenanceStatusOption(
      id: asJsonInt(json['id']) ?? 0,
      label: asJsonString(json['label']) ?? asJsonString(json['name']) ?? '',
      semantic: asJsonString(json['semantic']),
      isDeficiency: asJsonBool(json['is_deficiency']) ?? false,
      actionOptions: actionList
          .whereType<Map>()
          .map((e) => MaintenanceActionOption.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'semantic': semantic,
        'is_deficiency': isDeficiency,
        'action_options': actionOptions.map((a) => a.toJson()).toList(),
      };

  @override
  List<Object?> get props => [id, label, semantic, isDeficiency, actionOptions];
}

class LineAttachment extends Equatable {
  const LineAttachment({
    required this.id,
    required this.kind,
    this.url = '',
    this.uploadedBy,
    this.capturedAt,
    this.sha256,
    this.sizeBytes,
    this.displayOrder = 0,
    this.uploadedAt,
    this.localPath,
    this.syncStatus,
    this.syncError,
    this.idempotencyKey,
  });

  final int id;
  final String kind;
  final String url;
  final String? uploadedBy;
  final DateTime? capturedAt;
  final String? sha256;
  final int? sizeBytes;
  final int displayOrder;
  final DateTime? uploadedAt;
  final String? localPath;
  final OutboxCommandStatus? syncStatus;
  final String? syncError;
  final String? idempotencyKey;

  bool get isSynced =>
      syncStatus == OutboxCommandStatus.synced ||
      (url.isNotEmpty && (syncStatus == null || syncStatus == OutboxCommandStatus.synced));

  bool get isPending =>
      syncStatus == OutboxCommandStatus.pending ||
      syncStatus == OutboxCommandStatus.syncing;

  bool get isFailed =>
      syncStatus == OutboxCommandStatus.failed ||
      syncStatus == OutboxCommandStatus.conflict;

  LineAttachment copyWith({
    int? id,
    String? kind,
    String? url,
    String? uploadedBy,
    DateTime? capturedAt,
    String? sha256,
    int? sizeBytes,
    int? displayOrder,
    DateTime? uploadedAt,
    String? localPath,
    OutboxCommandStatus? syncStatus,
    String? syncError,
    bool clearError = false,
    String? idempotencyKey,
  }) {
    return LineAttachment(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      url: url ?? this.url,
      uploadedBy: uploadedBy ?? this.uploadedBy,
      capturedAt: capturedAt ?? this.capturedAt,
      sha256: sha256 ?? this.sha256,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      displayOrder: displayOrder ?? this.displayOrder,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      localPath: localPath ?? this.localPath,
      syncStatus: syncStatus ?? this.syncStatus,
      syncError: clearError ? null : (syncError ?? this.syncError),
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
    );
  }

  factory LineAttachment.fromJson(Map<String, dynamic> json) {
    final statusStr = json['sync_status']?.toString();
    return LineAttachment(
      id: asJsonInt(json['id']) ?? 0,
      kind: asJsonString(json['kind'])?.toUpperCase() ?? 'BEFORE',
      url: asJsonString(json['url']) ?? asJsonString(json['image']) ?? '',
      uploadedBy: asJsonString(json['uploaded_by']),
      capturedAt: _asDate(json['captured_at']),
      sha256: asJsonString(json['sha256']),
      sizeBytes: asJsonInt(json['size_bytes']),
      displayOrder: asJsonInt(json['display_order']) ?? 0,
      uploadedAt: _asDate(json['uploaded_at']),
      localPath: asJsonString(json['local_path']),
      syncStatus: statusStr != null ? OutboxCommandStatus.fromCode(statusStr) : null,
      syncError: asJsonString(json['sync_error']),
      idempotencyKey: asJsonString(json['idempotency_key']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind,
        'url': url,
        'uploaded_by': uploadedBy,
        'captured_at': capturedAt?.toIso8601String(),
        'sha256': sha256,
        'size_bytes': sizeBytes,
        'display_order': displayOrder,
        'uploaded_at': uploadedAt?.toIso8601String(),
        if (localPath != null) 'local_path': localPath,
        if (syncStatus != null) 'sync_status': syncStatus!.code,
        if (syncError != null) 'sync_error': syncError,
        if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
      };

  @override
  List<Object?> get props => [
        id,
        kind,
        url,
        uploadedBy,
        capturedAt,
        sha256,
        sizeBytes,
        displayOrder,
        uploadedAt,
        localPath,
        syncStatus,
        syncError,
        idempotencyKey,
      ];
}

class MaintenanceRecordLine extends Equatable {
  const MaintenanceRecordLine({
    required this.id,
    required this.itemName,
    this.inspectionPoint,
    this.valueType = MaintenanceValueType.text,
    this.itemKind = MaintenanceItemKind.inspectionPoint,
    this.isRequired = false,
    this.assetCategory,
    this.unit,
    this.referenceValue,
    this.statusOptions = const [],
    this.recordedValue,
    this.status = 'OK',
    this.statusOptionId,
    this.actionOptionId,
    this.failureCodeId,
    this.observationAction,
    this.deficiency,
    this.deficiencyAttended = false,
    this.excluded = false,
    this.exclusionReason,
    this.isSaved = true,
    this.attachments = const [],
  });

  final int id;

  /// Equipment/group this line belongs to (`item_name`), e.g. "EB Bunk".
  final String itemName;

  /// The checkpoint being performed (`inspection_point`), e.g. "Voltage".
  final String? inspectionPoint;

  final MaintenanceValueType valueType;
  final MaintenanceItemKind itemKind;
  final bool isRequired;

  /// Category used to group lines into subsystems on screen.
  final String? assetCategory;

  /// Unit suffix for the reading, e.g. "V", "Ohms".
  final String? unit;
  final String? referenceValue;

  final List<MaintenanceStatusOption> statusOptions;

  /// Raw server value. A plain scalar for most types; a `{R,Y,B}` or
  /// `{Volt,Amp}` map for the multi-part types. The backend has historically
  /// stored the multi-part form as a JSON string, so both are accepted.
  final Object? recordedValue;

  final String status;
  final int? statusOptionId;
  final int? actionOptionId;
  final int? failureCodeId;
  final String? observationAction;
  final String? deficiency;
  final bool deficiencyAttended;

  /// Lines excluded from this record's checklist by the supervisor.
  final bool excluded;
  final String? exclusionReason;

  final bool isSaved;

  /// Line-scoped attachments (before/after photos).
  final List<LineAttachment> attachments;

  /// Label shown as the line's heading.
  String get displayTitle {
    final point = inspectionPoint?.trim();
    if (point != null && point.isNotEmpty) return point;
    return itemName;
  }

  /// The actions selectable for the currently chosen status. The backend
  /// rejects an action that is not mapped to the selected status.
  List<MaintenanceActionOption> get availableActionOptions {
    if (statusOptionId == null) return const [];
    for (final option in statusOptions) {
      if (option.id == statusOptionId) return option.actionOptions;
    }
    return const [];
  }

  /// Single-value reading as text (empty for the multi-part types).
  String get scalarValue {
    final value = recordedValue;
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map) return '';
    return value.toString();
  }

  /// Component readings for RYB / VOLT_AMP, keyed by component label.
  Map<String, String> get componentValues {
    final value = _decodedValue();
    if (value is! Map) return const {};
    return {
      for (final key in valueType.componentKeys)
        key: value[key]?.toString() ?? '',
    };
  }

  Object? _decodedValue() {
    final value = recordedValue;
    if (value is String && valueType.isMultiPart && value.trim().isNotEmpty) {
      try {
        return jsonDecode(value);
      } catch (_) {
        return null;
      }
    }
    return value;
  }

  bool get _hasValue {
    if (valueType.isMultiPart) {
      return componentValues.values.any((v) => v.trim().isNotEmpty);
    }
    return scalarValue.trim().isNotEmpty;
  }

  /// Mirrors the web client's completion rule so mobile progress matches the
  /// register: measurements need a reading, inspection points need a status and
  /// — where the chosen status offers actions — an action taken.
  bool get isCompleted {
    if (itemKind == MaintenanceItemKind.recordParameter) {
      return _hasValue;
    }
    if (statusOptionId != null) {
      return availableActionOptions.isEmpty || actionOptionId != null;
    }
    return _hasValue ||
        (observationAction != null && observationAction!.trim().isNotEmpty);
  }

  MaintenanceRecordLine copyWith({
    Object? recordedValue = _unset,
    String? status,
    Object? statusOptionId = _unset,
    Object? actionOptionId = _unset,
    Object? observationAction = _unset,
    Object? deficiency = _unset,
    bool? deficiencyAttended,
    bool? isSaved,
    List<LineAttachment>? attachments,
  }) {
    return MaintenanceRecordLine(
      id: id,
      itemName: itemName,
      inspectionPoint: inspectionPoint,
      valueType: valueType,
      itemKind: itemKind,
      isRequired: isRequired,
      assetCategory: assetCategory,
      unit: unit,
      referenceValue: referenceValue,
      statusOptions: statusOptions,
      recordedValue:
          identical(recordedValue, _unset) ? this.recordedValue : recordedValue,
      status: status ?? this.status,
      statusOptionId: identical(statusOptionId, _unset)
          ? this.statusOptionId
          : statusOptionId as int?,
      actionOptionId: identical(actionOptionId, _unset)
          ? this.actionOptionId
          : actionOptionId as int?,
      failureCodeId: failureCodeId,
      observationAction: identical(observationAction, _unset)
          ? this.observationAction
          : observationAction as String?,
      deficiency:
          identical(deficiency, _unset) ? this.deficiency : deficiency as String?,
      deficiencyAttended: deficiencyAttended ?? this.deficiencyAttended,
      excluded: excluded,
      exclusionReason: exclusionReason,
      isSaved: isSaved ?? this.isSaved,
      attachments: attachments ?? this.attachments,
    );
  }

  factory MaintenanceRecordLine.fromJson(Map<String, dynamic> json) {
    final rawStatusOptions = json['status_options'];
    final statusOptionList = rawStatusOptions is List ? rawStatusOptions : const [];
    final rawAttachments = json['attachments'];
    final attachmentList = rawAttachments is List ? rawAttachments : const [];

    return MaintenanceRecordLine(
      id: asJsonInt(json['id']) ?? 0,
      itemName: asJsonString(json['item_name']) ??
          asJsonString(json['asset_name_snapshot']) ??
          'Checklist Item',
      inspectionPoint: asJsonString(json['inspection_point']) ??
          asJsonString(json['checkpoint_snapshot']),
      valueType: MaintenanceValueType.fromString(asJsonString(json['value_type'])),
      itemKind: MaintenanceItemKind.fromString(asJsonString(json['item_kind'])),
      isRequired: asJsonBool(json['required'] ?? json['is_required']) ?? false,
      assetCategory: asJsonString(json['asset_category']),
      unit: asJsonString(json['unit_snapshot'] ?? json['unit']),
      referenceValue: asJsonString(
          json['reference_value_snapshot'] ?? json['reference_value']),
      statusOptions: statusOptionList
          .whereType<Map>()
          .map((e) => MaintenanceStatusOption.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      recordedValue: json['recorded_value'],
      status: asJsonString(json['status']) ?? 'OK',
      statusOptionId: _asInt(json['status_option']),
      actionOptionId: _asInt(json['action_option']),
      failureCodeId: _asInt(json['failure_code']),
      observationAction: asJsonString(json['observation_action']),
      deficiency: asJsonString(json['deficiency']),
      deficiencyAttended: asJsonBool(json['deficiency_attended']) ?? false,
      excluded: asJsonBool(json['excluded']) ?? false,
      exclusionReason: asJsonString(json['exclusion_reason']),
      isSaved: true,
      attachments: attachmentList
          .whereType<Map>()
          .map((e) => LineAttachment.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  /// Serialised for the offline cache. Uses the same keys the API returns so
  /// [MaintenanceRecordLine.fromJson] reads a cached line back unchanged.
  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'item_name': itemName,
        'inspection_point': inspectionPoint,
        'value_type': valueType.code,
        'item_kind': itemKind.code,
        'required': isRequired,
        'asset_category': assetCategory,
        'unit_snapshot': unit,
        'reference_value_snapshot': referenceValue,
        'status_options': statusOptions.map((o) => o.toJson()).toList(),
        'recorded_value': recordedValue,
        'status': status,
        'status_option': statusOptionId,
        'action_option': actionOptionId,
        'failure_code': failureCodeId,
        'observation_action': observationAction,
        'deficiency': deficiency,
        'deficiency_attended': deficiencyAttended,
        'excluded': excluded,
        'exclusion_reason': exclusionReason,
        'attachments': attachments.map((a) => a.toJson()).toList(),
      };

  @override
  List<Object?> get props => [
        id,
        itemName,
        inspectionPoint,
        valueType,
        itemKind,
        isRequired,
        assetCategory,
        unit,
        referenceValue,
        statusOptions,
        recordedValue,
        status,
        statusOptionId,
        actionOptionId,
        failureCodeId,
        observationAction,
        deficiency,
        deficiencyAttended,
        excluded,
        exclusionReason,
        isSaved,
        attachments,
      ];
}

/// Sentinel allowing [MaintenanceRecordLine.copyWith] to distinguish "leave as
/// is" from an explicit null, which is what clearing a reading requires.
const Object _unset = Object();

class MaintenanceRecord extends Equatable {
  const MaintenanceRecord({
    required this.id,
    this.workOrderId,
    this.workOrderTicket,
    this.scheduleId,
    this.templateName,
    this.stationName,
    this.depotName,
    this.divisionName,
    this.technicianName,
    this.dateOfMaintenance,
    this.lines = const [],
    this.remarks,
    this.status,
  });

  final int id;
  final int? workOrderId;
  final String? workOrderTicket;
  final int? scheduleId;
  final String? templateName;
  final String? stationName;
  final String? depotName;
  final String? divisionName;
  final String? technicianName;
  final DateTime? dateOfMaintenance;
  final List<MaintenanceRecordLine> lines;
  final String? remarks;
  final String? status;

  /// Returns true if the record is at or past technician completion.
  bool get isPastTechCompleted {
    final s = status?.toUpperCase();
    return s == 'TECH_COMPLETED' ||
        s == 'VERIFIED' ||
        s == 'CLOSED' ||
        s == 'CANCELLED';
  }

  /// Excluded lines are not part of this record's work, so they are left out of
  /// both the checklist and its progress.
  List<MaintenanceRecordLine> get activeLines =>
      lines.where((l) => !l.excluded).toList();

  int get totalLines => activeLines.length;
  int get completedLines => activeLines.where((l) => l.isCompleted).length;
  double get progress => totalLines == 0 ? 0.0 : completedLines / totalLines;

  factory MaintenanceRecord.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'];
    final lineList = rawLines is List ? rawLines : const [];
    final sched = json['schedule_details'];
    final schedule = sched is Map ? Map<String, dynamic>.from(sched) : null;

    return MaintenanceRecord(
      id: asJsonInt(json['id']) ?? 0,
      workOrderId: _asInt(json['work_order']) ??
          _asInt(json['work_order_id']) ??
          _asInt(schedule?['work_order_id']),
      workOrderTicket: asJsonString(schedule?['work_order_ticket']),
      scheduleId: _asInt(json['schedule']) ?? _asInt(json['schedule_id']),
      templateName: asJsonString(schedule?['template_name']) ??
          asJsonString(schedule?['maintenance_master_name']),
      stationName: asJsonString(schedule?['station_name']),
      depotName: asJsonString(schedule?['depot_name']),
      divisionName: asJsonString(schedule?['division_name']),
      technicianName: asJsonString(json['technician_name']),
      dateOfMaintenance: _asDate(json['date_of_maintenance']),
      lines: lineList
          .whereType<Map>()
          .map((e) => MaintenanceRecordLine.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      remarks: asJsonString(json['remarks']),
      status: asJsonString(json['status']),
    );
  }

  Map<String, dynamic> toCacheJson() => {
        'id': id,
        'work_order': workOrderId,
        'schedule': scheduleId,
        'technician_name': technicianName,
        'date_of_maintenance': dateOfMaintenance?.toIso8601String(),
        'remarks': remarks,
        'status': status,
        'schedule_details': {
          'work_order_id': workOrderId,
          'work_order_ticket': workOrderTicket,
          'template_name': templateName,
          'station_name': stationName,
          'depot_name': depotName,
          'division_name': divisionName,
        },
        'lines': lines.map((l) => l.toCacheJson()).toList(),
      };

  MaintenanceRecord copyWith({List<MaintenanceRecordLine>? lines}) {
    return MaintenanceRecord(
      id: id,
      workOrderId: workOrderId,
      workOrderTicket: workOrderTicket,
      scheduleId: scheduleId,
      templateName: templateName,
      stationName: stationName,
      depotName: depotName,
      divisionName: divisionName,
      technicianName: technicianName,
      dateOfMaintenance: dateOfMaintenance,
      lines: lines ?? this.lines,
      remarks: remarks,
      status: status,
    );
  }

  @override
  List<Object?> get props => [
        id,
        workOrderId,
        workOrderTicket,
        scheduleId,
        templateName,
        stationName,
        depotName,
        divisionName,
        technicianName,
        dateOfMaintenance,
        lines,
        remarks,
        status,
      ];
}

int? _asInt(dynamic value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

DateTime? _asDate(dynamic value) {
  if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
  return null;
}
