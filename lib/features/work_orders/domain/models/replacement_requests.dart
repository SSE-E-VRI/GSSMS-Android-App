import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:intl/intl.dart';

/// Local-calendar `yyyy-MM-dd`. The web's `toISOString()` yields the previous
/// day before 05:30 IST, so mobile formats the local date instead.
String _isoDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// The Job Work context a replacement is recorded against, taken from the
/// checklist record the technician has open.
class ReplacementJobWork extends Equatable {
  const ReplacementJobWork({
    required this.recordId,
    required this.workOrderId,
    this.stationId,
    this.infrastructureId,
    this.stationName,
    this.assetId,
    this.assetUniqueId,
    this.assetName,
  });

  final int recordId;
  final int workOrderId;
  final int? stationId;
  final int? infrastructureId;
  final String? stationName;
  final int? assetId;
  final String? assetUniqueId;
  final String? assetName;

  /// Null when the record is not linked to a Job Work (nothing to record
  /// a replacement against).
  static ReplacementJobWork? fromRecord(MaintenanceRecord r) {
    final workOrderId = r.workOrderId;
    if (workOrderId == null) return null;
    return ReplacementJobWork(
      recordId: r.id,
      workOrderId: workOrderId,
      stationId: r.stationId,
      infrastructureId: r.infrastructureId,
      stationName: r.stationName,
      assetId: r.jobWorkAssetId,
      assetUniqueId: r.jobWorkAssetUniqueId,
      assetName: r.jobWorkAssetName,
    );
  }

  @override
  List<Object?> get props => [
        recordId,
        workOrderId,
        stationId,
        infrastructureId,
        stationName,
        assetId,
        assetUniqueId,
        assetName,
      ];
}

/// Body for `POST /assets/{id}/replace_asset/`.
class AssetReplacementRequest extends Equatable {
  const AssetReplacementRequest({
    required this.workOrderId,
    required this.newMake,
    required this.replacementDate,
    required this.reason,
    this.newModel = '',
    this.newSerialNumber = '',
    this.newWarrantyExpiry,
    this.remarks = '',
  });

  final int workOrderId;
  final String newMake;
  final String newModel;
  final String newSerialNumber;
  final DateTime? newWarrantyExpiry;
  final DateTime replacementDate;
  final String reason;
  final String remarks;

  /// `new_serial_number` is always sent (as `''` when blank): the server logs a
  /// NOT NULL `ComponentReplacement.new_serial_number` from it.
  Map<String, dynamic> toJson() => {
        'new_make': newMake.trim(),
        'new_model': newModel.trim(),
        'new_serial_number': newSerialNumber.trim(),
        'new_warranty_expiry_date':
            newWarrantyExpiry == null ? '' : _isoDate(newWarrantyExpiry!),
        'replacement_date': _isoDate(replacementDate),
        'reason': reason.trim(),
        'remarks': remarks.trim(),
        'work_order_id': workOrderId,
      };

  @override
  List<Object?> get props => [
        workOrderId,
        newMake,
        newModel,
        newSerialNumber,
        newWarrantyExpiry,
        replacementDate,
        reason,
        remarks,
      ];
}

/// Body for `POST /installed-components/{id}/replace/` (registered component).
class InstalledComponentReplacementRequest extends Equatable {
  const InstalledComponentReplacementRequest({
    required this.workOrderId,
    required this.reason,
    required this.name,
    required this.make,
    required this.serialNumber,
    this.componentCode,
    this.model = '',
  });

  final int workOrderId;
  final String reason;
  final String? componentCode;
  final String name;
  final String make;
  final String model;
  final String serialNumber;

  Map<String, dynamic> toJson() {
    final code = componentCode?.trim();
    final modelText = model.trim();
    return {
      'replacement_work_order': workOrderId,
      'replacement_reason': reason.trim(),
      'new_component': {
        if (code != null && code.isNotEmpty) 'component_code': code,
        'name': name.trim(),
        'make': make.trim(),
        if (modelText.isNotEmpty) 'model': modelText,
        'serial_number': serialNumber.trim(),
      },
    };
  }

  @override
  List<Object?> get props =>
      [workOrderId, reason, componentCode, name, make, model, serialNumber];
}

/// Body for `POST /maintenance/work-orders/{id}/log_replacement/`
/// (non-registered component).
class JobWorkComponentReplacementRequest extends Equatable {
  const JobWorkComponentReplacementRequest({
    required this.assetReference,
    required this.componentName,
    required this.newMake,
    required this.newSerialNumber,
    required this.reason,
    this.oldMake = '',
    this.oldModel = '',
    this.oldSerialNumber = '',
    this.newModel = '',
    this.newWarrantyExpiry,
    this.remarks = '',
  });

  final String assetReference;
  final String componentName;
  final String oldMake;
  final String oldModel;
  final String oldSerialNumber;
  final String newMake;
  final String newModel;
  final String newSerialNumber;
  final DateTime? newWarrantyExpiry;
  final String reason;
  final String remarks;

  /// `new_warranty_expiry_date` is omitted when blank: the server feeds the raw
  /// value to a DateField, and `''` makes the unguarded view return a 500.
  Map<String, dynamic> toJson() => {
        'asset_reference': assetReference.trim(),
        'component_name': componentName.trim(),
        'old_serial_number': oldSerialNumber.trim(),
        'old_make': oldMake.trim(),
        'old_model': oldModel.trim(),
        'new_make': newMake.trim(),
        'new_model': newModel.trim(),
        'new_serial_number': newSerialNumber.trim(),
        if (newWarrantyExpiry != null)
          'new_warranty_expiry_date': _isoDate(newWarrantyExpiry!),
        'reason': reason.trim(),
        'remarks': remarks.trim(),
      };

  @override
  List<Object?> get props => [
        assetReference,
        componentName,
        oldMake,
        oldModel,
        oldSerialNumber,
        newMake,
        newModel,
        newSerialNumber,
        newWarrantyExpiry,
        reason,
        remarks,
      ];
}
