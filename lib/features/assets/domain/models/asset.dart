import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Criticality grades used across the asset register.
enum AssetCriticality {
  critical('CRITICAL', 'Critical'),
  high('HIGH', 'High'),
  medium('MEDIUM', 'Medium'),
  low('LOW', 'Low');

  const AssetCriticality(this.code, this.displayName);
  final String code;
  final String displayName;

  static AssetCriticality fromString(String? code) {
    if (code == null) return AssetCriticality.medium;
    final upper = code.toUpperCase().trim();
    for (final c in AssetCriticality.values) {
      if (c.code == upper) return c;
    }
    return AssetCriticality.medium;
  }
}

/// Warranty state the server computes for an asset (SSOT §28).
enum AssetWarrantyStatus {
  inWarranty('IN_WARRANTY', 'In Warranty'),
  outOfWarranty('OUT_OF_WARRANTY', 'Out of Warranty'),
  warrantyYearPrecision('WARRANTY_YEAR_PRECISION', 'Warranty valid through year-end'),
  warrantyMonthPrecision('WARRANTY_MONTH_PRECISION', 'Warranty valid through month-end'),
  unknown('UNKNOWN', 'Unknown');

  const AssetWarrantyStatus(this.code, this.displayName);
  final String code;
  final String displayName;

  static AssetWarrantyStatus fromString(String? code) {
    if (code == null || code.trim().isEmpty) return AssetWarrantyStatus.unknown;
    final upper = code.toUpperCase().trim().replaceAll(' ', '_');
    for (final s in AssetWarrantyStatus.values) {
      if (s.code == upper) return s;
    }
    return AssetWarrantyStatus.unknown;
  }
}

/// An entry in the asset register.
///
/// Field names follow the Django `AssetSerializer`. Note there is no `name`
/// column: an asset is identified by its `unique_id` and described by its
/// category and type, exactly as the web register lists it.
class Asset extends Equatable {
  const Asset({
    required this.id,
    required this.uniqueId,
    this.assetCategoryName,
    this.assetCategoryCode,
    this.assetTypeName,
    this.assetTypeCode,
    this.make,
    this.model,
    this.serialNumber,
    this.capacity,
    this.criticality = AssetCriticality.medium,
    this.warrantyStatus = AssetWarrantyStatus.unknown,
    this.stationName,
    this.stationCode,
    this.depotName,
    this.infrastructureName,
    this.locationLabel,
    this.microLocation,
    this.installationDate,
    this.warrantyExpiryDate,
    this.lastMaintenanceDate,
    this.remarks,
    this.isDeleted = false,
  });

  final int id;

  /// Human-facing asset identifier, e.g. "VRI-STN-CLS-MAIN-001".
  final String uniqueId;

  final String? assetCategoryName;
  final String? assetCategoryCode;
  final String? assetTypeName;
  final String? assetTypeCode;
  final String? make;
  final String? model;
  final String? serialNumber;
  final String? capacity;
  final AssetCriticality criticality;
  final AssetWarrantyStatus warrantyStatus;
  final String? stationName;
  final String? stationCode;
  final String? depotName;
  final String? infrastructureName;

  /// Server-composed location string, e.g. "VRI STN/Vriddhachalam Depot".
  final String? locationLabel;
  final String? microLocation;

  final DateTime? installationDate;
  final DateTime? warrantyExpiryDate;
  final DateTime? lastMaintenanceDate;
  final String? remarks;
  final bool isDeleted;

  /// What to show as the asset's title. There is no name column, so the type
  /// (falling back to the category) is the closest thing to one.
  String get displayName {
    final type = assetTypeName?.trim();
    if (type != null && type.isNotEmpty) return type;
    final category = assetCategoryName?.trim();
    if (category != null && category.isNotEmpty) return category;
    return uniqueId;
  }

  /// Where the asset sits, preferring the server's composed label.
  String get displayLocation {
    final label = locationLabel?.trim();
    if (label != null && label.isNotEmpty) return label;
    return [stationName, depotName]
        .where((s) => s != null && s.trim().isNotEmpty)
        .join(' • ');
  }

  /// Make and model as one line, for the list card subtitle.
  String get makeModel {
    final parts = [make, model]
        .where((s) => s != null && s.trim().isNotEmpty && s.trim() != '-')
        .toList();
    return parts.join(' ');
  }

  /// True when a scanned or typed code identifies this asset.
  bool matchesCode(String code) {
    final needle = code.trim().toLowerCase();
    if (needle.isEmpty) return false;
    return uniqueId.toLowerCase() == needle ||
        (serialNumber?.toLowerCase() == needle);
  }

  factory Asset.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(dynamic d) {
      if (d == null || d == '') return null;
      return asJsonDateTime(d);
    }

    return Asset(
      id: json['id'] as int? ?? 0,
      uniqueId: json['unique_id'] as String? ??
          json['asset_code'] as String? ??
          'AST-${json['id']}',
      assetCategoryName: json['asset_category_name'] as String?,
      assetCategoryCode: json['asset_category_code'] as String?,
      assetTypeName: json['asset_type_name'] as String?,
      assetTypeCode: json['asset_type_code'] as String?,
      make: json['make'] as String?,
      model: json['model'] as String?,
      serialNumber: json['serial_number'] as String?,
      capacity: json['capacity'] as String?,
      criticality: AssetCriticality.fromString(json['criticality'] as String?),
      warrantyStatus:
          AssetWarrantyStatus.fromString(json['warranty_status'] as String?),
      stationName: json['station_name'] as String?,
      stationCode: json['station_code'] as String?,
      depotName: json['depot_name'] as String?,
      infrastructureName: json['infrastructure_name'] as String?,
      locationLabel: json['location_label'] as String?,
      microLocation: json['micro_location'] as String?,
      installationDate: parseDate(json['installation_date']),
      warrantyExpiryDate: parseDate(json['warranty_expiry_date']),
      lastMaintenanceDate: parseDate(json['last_maintenance_date']),
      remarks: json['remarks'] as String?,
      isDeleted: json['is_deleted'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [
        id,
        uniqueId,
        assetCategoryName,
        assetTypeName,
        make,
        model,
        serialNumber,
        capacity,
        criticality,
        warrantyStatus,
        stationName,
        depotName,
        locationLabel,
        microLocation,
        installationDate,
        warrantyExpiryDate,
        lastMaintenanceDate,
        remarks,
        isDeleted,
      ];
}
