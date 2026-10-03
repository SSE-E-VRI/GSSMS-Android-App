import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_component.dart';

void main() {
  group('AssetComponent source_type', () {
    Map<String, dynamic> row(String source, String status) => {
          'source_id': '77',
          'name': 'Lamp',
          'component_code': 'LAMP-01',
          'source_type': source,
          'status': status,
        };

    test('parses sourceType', () {
      expect(AssetComponent.fromJson(row('INSTALLED_COMPONENT', 'IN_SERVICE')).sourceType,
          'INSTALLED_COMPONENT');
      expect(AssetComponent.fromJson(const {'source_id': '1', 'name': 'x'}).sourceType, isNull);
    });

    test('isReplaceableInstalled needs installed component in service', () {
      expect(AssetComponent.fromJson(row('INSTALLED_COMPONENT', 'IN_SERVICE')).isReplaceableInstalled,
          isTrue);
      expect(AssetComponent.fromJson(row('INSTALLED_COMPONENT', 'REPLACED')).isReplaceableInstalled,
          isFalse);
      expect(AssetComponent.fromJson(row('ASSET_SET_MEMBER', 'IN_SERVICE')).isReplaceableInstalled,
          isFalse);
    });
  });
}
