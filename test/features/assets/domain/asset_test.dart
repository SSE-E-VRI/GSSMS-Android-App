import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';

void main() {
  group('Asset Domain Model Tests', () {
    /// Field-for-field from a live GET /api/v1/assets/ response. The register
    /// has no `name` column: an asset is identified by `unique_id` and
    /// described by its category and type.
    Map<String, dynamic> payload() => {
          'id': 218,
          'unique_id': 'VRI-STN-CLS-MAIN-001',
          'station': 17,
          'infrastructure': 18,
          'infrastructure_name': 'Station General',
          'depot': 23,
          'depot_name': 'Vriddhachalam Depot',
          'station_name': 'Vriddhachalam',
          'station_code': 'VRI',
          'location_label': 'VRI STN/Vriddhachalam Depot',
          'asset_category_name': 'CLS Panels',
          'asset_category_code': 'CLS',
          'asset_type_name': 'Main Panel',
          'asset_type_code': 'MAIN',
          'micro_location': 'Panel Room',
          'make': 'SUNTRON',
          'model': '-',
          'serial_number': '24042502',
          'capacity': '150A',
          'installation_date': '2025-05-30',
          'criticality': 'CRITICAL',
          'warranty_status': 'IN_WARRANTY',
          'warranty_expiry_date': '2027-05-30',
          'last_maintenance_date': null,
          'remarks': null,
          'is_deleted': false,
        };

    test('parses the asset payload the server actually returns', () {
      final asset = Asset.fromJson(payload());

      expect(asset.id, 218);
      expect(asset.uniqueId, 'VRI-STN-CLS-MAIN-001');
      expect(asset.assetCategoryName, 'CLS Panels');
      expect(asset.assetTypeName, 'Main Panel');
      expect(asset.make, 'SUNTRON');
      expect(asset.serialNumber, '24042502');
      expect(asset.capacity, '150A');
      expect(asset.criticality, AssetCriticality.critical);
      expect(asset.warrantyStatus, AssetWarrantyStatus.inWarranty);
      expect(asset.stationName, 'Vriddhachalam');
      expect(asset.microLocation, 'Panel Room');
      expect(asset.installationDate, DateTime(2025, 5, 30));
      expect(asset.isDeleted, isFalse);
    });

    test('falls back through type, category, then id for a display name', () {
      expect(Asset.fromJson(payload()).displayName, 'Main Panel');

      final noType = Asset.fromJson({...payload(), 'asset_type_name': null});
      expect(noType.displayName, 'CLS Panels');

      final bare = Asset.fromJson({
        ...payload(),
        'asset_type_name': null,
        'asset_category_name': null,
      });
      expect(bare.displayName, 'VRI-STN-CLS-MAIN-001');
    });

    test('prefers the server-composed location label', () {
      expect(
        Asset.fromJson(payload()).displayLocation,
        'VRI STN/Vriddhachalam Depot',
      );

      final noLabel = Asset.fromJson({...payload(), 'location_label': null});
      expect(noLabel.displayLocation, 'Vriddhachalam • Vriddhachalam Depot');
    });

    test('omits placeholder model values from the make/model line', () {
      // The register stores "-" where a model is unknown.
      expect(Asset.fromJson(payload()).makeModel, 'SUNTRON');
      expect(
        Asset.fromJson({...payload(), 'model': 'CLS-200'}).makeModel,
        'SUNTRON CLS-200',
      );
    });

    test('matches a scanned code only on an exact identifier', () {
      final asset = Asset.fromJson(payload());

      expect(asset.matchesCode('VRI-STN-CLS-MAIN-001'), isTrue);
      expect(asset.matchesCode('vri-stn-cls-main-001'), isTrue);
      expect(asset.matchesCode('24042502'), isTrue, reason: 'serial number');
      expect(
        asset.matchesCode('VRI-STN-CLS'),
        isFalse,
        reason: 'a partial code must not resolve to this asset',
      );
      expect(asset.matchesCode('   '), isFalse);
    });

    test('AssetCriticality.fromString defaults to medium safely', () {
      expect(AssetCriticality.fromString('CRITICAL'), AssetCriticality.critical);
      expect(AssetCriticality.fromString('HIGH'), AssetCriticality.high);
      expect(AssetCriticality.fromString('MEDIUM'), AssetCriticality.medium);
      expect(AssetCriticality.fromString('LOW'), AssetCriticality.low);
      expect(AssetCriticality.fromString(null), AssetCriticality.medium);
    });

    test('AssetWarrantyStatus.fromString parses safely', () {
      expect(
        AssetWarrantyStatus.fromString('IN_WARRANTY'),
        AssetWarrantyStatus.inWarranty,
      );
      expect(
        AssetWarrantyStatus.fromString('EXPIRED'),
        AssetWarrantyStatus.expired,
      );
      expect(AssetWarrantyStatus.fromString(null), AssetWarrantyStatus.unknown);
      expect(AssetWarrantyStatus.fromString(''), AssetWarrantyStatus.unknown);
    });
  });
}
