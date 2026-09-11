import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

class RegisterLineItem extends Equatable {
  const RegisterLineItem({
    required this.assetName,
    required this.inspection,
    this.value,
    this.status,
    this.statusLabel,
    this.action,
    this.remarks,
  });

  final String assetName;
  final String inspection;
  final String? value;
  final String? status;
  final String? statusLabel;
  final String? action;
  final String? remarks;

  /// True for a recorded-parameter row (e.g. Voltage/Current readings) rather
  /// than a pass/fail checkpoint. `register_report` doesn't tag rows with the
  /// `item_kind` the web verification workspace carries, so this mirrors it
  /// heuristically: a reading has a recorded value and no action against it,
  /// while a checkpoint has a status/action and an empty value.
  bool get isRecordedParameter {
    final hasValue = value != null && value!.trim().isNotEmpty && value!.trim() != '-';
    final hasAction = action != null && action!.trim().isNotEmpty && action!.trim() != '-';
    return hasValue && !hasAction;
  }

  factory RegisterLineItem.fromJson(Map<String, dynamic> json) {
    return RegisterLineItem(
      assetName: asJsonString(json['asset_name']) ?? asJsonString(json['equipment']) ?? 'Asset Item',
      inspection: asJsonString(json['inspection']) ?? asJsonString(json['checkpoint']) ?? 'Checkpoint',
      value: asJsonString(json['value']),
      status: asJsonString(json['status']),
      statusLabel: asJsonString(json['status_label']) ?? asJsonString(json['status']),
      action: asJsonString(json['action']) ?? asJsonString(json['action_taken']),
      remarks: asJsonString(json['remarks']),
    );
  }

  @override
  List<Object?> get props => [
        assetName,
        inspection,
        value,
        status,
        statusLabel,
        action,
        remarks,
      ];
}

/// One asset/equipment's checklist rows within a register entry — the unit
/// both the on-screen table and the downloaded PDF are grouped by.
class AssetChecklistGroup extends Equatable {
  const AssetChecklistGroup({required this.assetName, required this.items});

  final String assetName;
  final List<RegisterLineItem> items;

  @override
  List<Object?> get props => [assetName, items];
}

class MaintenanceRegisterEntry extends Equatable {
  const MaintenanceRegisterEntry({
    required this.id,
    required this.masterName,
    this.date,
    this.railwayName,
    this.divisionName,
    this.depotName,
    this.stationName,
    this.registerTitle,
    this.technician,
    this.supervisor,
    this.remarks,
    this.items = const [],
  });

  final int id;
  final String masterName;
  final DateTime? date;
  final String? railwayName;
  final String? divisionName;
  final String? depotName;
  final String? stationName;
  final String? registerTitle;
  final String? technician;
  final String? supervisor;
  final String? remarks;
  final List<RegisterLineItem> items;

  /// [items] grouped by [RegisterLineItem.assetName], in first-appearance
  /// order — mirrors web's FormPreview, which renders one table per asset
  /// group rather than one flat list of checklist rows.
  List<AssetChecklistGroup> get groupedByAsset {
    final order = <String>[];
    final byAsset = <String, List<RegisterLineItem>>{};
    for (final item in items) {
      (byAsset[item.assetName] ??= []).add(item);
      if (byAsset[item.assetName]!.length == 1) order.add(item.assetName);
    }
    return order
        .map((name) => AssetChecklistGroup(assetName: name, items: byAsset[name]!))
        .toList();
  }

  factory MaintenanceRegisterEntry.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final org = json['organization'] as Map<String, dynamic>?;

    return MaintenanceRegisterEntry(
      id: json['id'] as int? ?? 0,
      masterName: asJsonString(json['master']) ?? asJsonString(json['master_name']) ?? 'Maintenance Schedule',
      date: json['date'] != null ? asJsonDateTime(json['date']) : null,
      railwayName: asJsonString(org?['railway_name']),
      divisionName: asJsonString(org?['division_name']),
      depotName: asJsonString(org?['depot_name']) ?? asJsonString(json['depot_name']),
      stationName: asJsonString(org?['station_name']) ?? asJsonString(json['station_name']),
      registerTitle: asJsonString(org?['register_title']),
      technician: asJsonString(json['technician']),
      supervisor: asJsonString(json['supervisor']),
      remarks: asJsonString(json['remarks']),
      items: rawItems.whereType<Map<String, dynamic>>().map(RegisterLineItem.fromJson).toList(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        masterName,
        date,
        railwayName,
        divisionName,
        depotName,
        stationName,
        registerTitle,
        technician,
        supervisor,
        remarks,
        items,
      ];
}
