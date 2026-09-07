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

class MaintenanceRegisterEntry extends Equatable {
  const MaintenanceRegisterEntry({
    required this.id,
    required this.masterName,
    this.date,
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
  final String? depotName;
  final String? stationName;
  final String? registerTitle;
  final String? technician;
  final String? supervisor;
  final String? remarks;
  final List<RegisterLineItem> items;

  factory MaintenanceRegisterEntry.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final org = json['organization'] as Map<String, dynamic>?;

    return MaintenanceRegisterEntry(
      id: json['id'] as int? ?? 0,
      masterName: asJsonString(json['master']) ?? asJsonString(json['master_name']) ?? 'Maintenance Schedule',
      date: json['date'] != null ? DateTime.tryParse(json['date'].toString()) : null,
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
        depotName,
        stationName,
        registerTitle,
        technician,
        supervisor,
        remarks,
        items,
      ];
}
