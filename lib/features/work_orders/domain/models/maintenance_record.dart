import 'dart:convert';

import 'package:equatable/equatable.dart';

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
      id: json['id'] as int? ?? 0,
      label: json['label'] as String? ?? json['name'] as String? ?? '',
      isDeficiency: json['is_deficiency'] as bool? ?? false,
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
    final rawActions = json['action_options'] as List<dynamic>? ?? const [];
    return MaintenanceStatusOption(
      id: json['id'] as int? ?? 0,
      label: json['label'] as String? ?? json['name'] as String? ?? '',
      semantic: json['semantic'] as String?,
      isDeficiency: json['is_deficiency'] as bool? ?? false,
      actionOptions: rawActions
          .whereType<Map<String, dynamic>>()
          .map(MaintenanceActionOption.fromJson)
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
    );
  }

  factory MaintenanceRecordLine.fromJson(Map<String, dynamic> json) {
    final rawStatusOptions = json['status_options'] as List<dynamic>? ?? const [];

    return MaintenanceRecordLine(
      id: json['id'] as int? ?? 0,
      itemName: json['item_name'] as String? ??
          json['asset_name_snapshot'] as String? ??
          'Checklist Item',
      inspectionPoint: json['inspection_point'] as String? ??
          json['checkpoint_snapshot'] as String?,
      valueType: MaintenanceValueType.fromString(json['value_type'] as String?),
      itemKind: MaintenanceItemKind.fromString(json['item_kind'] as String?),
      isRequired: json['required'] as bool? ?? false,
      assetCategory: json['asset_category'] as String?,
      unit: json['unit_snapshot'] as String?,
      referenceValue: json['reference_value_snapshot'] as String?,
      statusOptions: rawStatusOptions
          .whereType<Map<String, dynamic>>()
          .map(MaintenanceStatusOption.fromJson)
          .toList(),
      recordedValue: json['recorded_value'],
      status: json['status'] as String? ?? 'OK',
      statusOptionId: _asInt(json['status_option']),
      actionOptionId: _asInt(json['action_option']),
      failureCodeId: _asInt(json['failure_code']),
      observationAction: json['observation_action'] as String?,
      deficiency: json['deficiency'] as String?,
      deficiencyAttended: json['deficiency_attended'] as bool? ?? false,
      excluded: json['excluded'] as bool? ?? false,
      exclusionReason: json['exclusion_reason'] as String?,
      isSaved: true,
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
      };

  @override
  List<Object?> get props => [
        id,
        itemName,
        inspectionPoint,
        valueType,
        itemKind,
        assetCategory,
        statusOptions,
        recordedValue,
        status,
        statusOptionId,
        actionOptionId,
        observationAction,
        deficiency,
        deficiencyAttended,
        excluded,
        isSaved,
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
  final String? technicianName;
  final DateTime? dateOfMaintenance;
  final List<MaintenanceRecordLine> lines;
  final String? remarks;
  final String? status;

  /// Excluded lines are not part of this record's work, so they are left out of
  /// both the checklist and its progress.
  List<MaintenanceRecordLine> get activeLines =>
      lines.where((l) => !l.excluded).toList();

  int get totalLines => activeLines.length;
  int get completedLines => activeLines.where((l) => l.isCompleted).length;
  double get progress => totalLines == 0 ? 0.0 : completedLines / totalLines;

  factory MaintenanceRecord.fromJson(Map<String, dynamic> json) {
    final rawLines = json['lines'] as List<dynamic>? ?? const [];
    final schedule = json['schedule_details'] as Map<String, dynamic>?;

    return MaintenanceRecord(
      id: json['id'] as int? ?? 0,
      workOrderId: _asInt(json['work_order']) ??
          _asInt(json['work_order_id']) ??
          _asInt(schedule?['work_order_id']),
      workOrderTicket: schedule?['work_order_ticket'] as String?,
      scheduleId: _asInt(json['schedule']) ?? _asInt(json['schedule_id']),
      templateName: schedule?['template_name'] as String? ??
          schedule?['maintenance_master_name'] as String?,
      stationName: schedule?['station_name'] as String?,
      technicianName: json['technician_name'] as String?,
      dateOfMaintenance: _asDate(json['date_of_maintenance']),
      lines: rawLines
          .whereType<Map<String, dynamic>>()
          .map(MaintenanceRecordLine.fromJson)
          .toList(),
      remarks: json['remarks'] as String?,
      status: json['status'] as String?,
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
