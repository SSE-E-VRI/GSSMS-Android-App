import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';

Map<String, dynamic> _line(
  int id, {
  String item = 'UPS',
  String category = 'Power',
  int? categoryId = 1,
  String? uniqueId,
  bool? checkedOut,
  bool excluded = false,
  String source = '',
  bool? assetActive,
  String? applicability,
}) =>
    {
      'id': id,
      'item_name': item,
      'asset_category': category,
      'asset_category_id': categoryId,
      'asset_unique_id': uniqueId,
      'checked_out': checkedOut,
      'excluded': excluded,
      'checkout_source': source,
      'asset_is_active': assetActive,
      'applicability': applicability,
    };

MaintenanceRecord _record(List<Map<String, dynamic>> lines, {String? status}) =>
    MaintenanceRecord.fromJson({'id': 1, 'status': status, 'lines': lines});

void main() {
  group('MaintenanceRecordLine checkout fields', () {
    test('parse and cache round-trip', () {
      final line = MaintenanceRecordLine.fromJson({
        ..._line(5,
            uniqueId: 'AST-1',
            checkedOut: false,
            source: 'SUPERVISOR',
            assetActive: true,
            applicability: 'OPTIONAL_ABSENT'),
        'asset_group_label_override': 'Custom',
        'inclusion_changed_at': '2026-05-01T10:00:00Z',
      });
      expect(line.checkedOut, isFalse);
      expect(line.isCheckedOut, isFalse);
      expect(line.checkoutSource, 'SUPERVISOR');
      expect(line.assetCategoryId, 1);
      expect(line.assetUniqueId, 'AST-1');
      expect(line.assetIsActive, isTrue);
      expect(line.applicability, 'OPTIONAL_ABSENT');
      expect(line.assetGroupLabelOverride, 'Custom');
      expect(line.inclusionChangedAt, isNotNull);

      final back = MaintenanceRecordLine.fromJson(line.toCacheJson());
      expect(back, line);
    });

    test('legacy payload without checked_out counts as checked out', () {
      final line = MaintenanceRecordLine.fromJson({'id': 1, 'item_name': 'X'});
      expect(line.checkedOut, isNull);
      expect(line.isCheckedOut, isTrue);
      expect(line.checkoutSource, '');
    });

    test('copyWith patches checkout state', () {
      final line = MaintenanceRecordLine.fromJson(_line(1, checkedOut: false));
      final patched = line.copyWith(
          checkedOut: true,
          checkoutSource: 'TECHNICIAN',
          excluded: false,
          exclusionReason: null,
          applicability: 'REQUIRED');
      expect(patched.checkedOut, isTrue);
      expect(patched.checkoutSource, 'TECHNICIAN');
      expect(patched.applicability, 'REQUIRED');
      expect(patched.assetCategoryId, 1);
    });
  });

  group('MaintenanceRecord.activeLines', () {
    test('excludes checked_out:false and excluded, keeps legacy null', () {
      final r = _record([
        _line(1, checkedOut: true),
        _line(2, checkedOut: false),
        _line(3, checkedOut: null),
        _line(4, checkedOut: true, excluded: true),
      ]);
      expect(r.activeLines.map((l) => l.id), [1, 3]);
      expect(r.totalLines, 2);
    });
  });

  group('MaintenanceRecord.assetGroups', () {
    test('groups by unique id, else category::name (case-insensitive)', () {
      final r = _record([
        _line(1, item: 'UPS', uniqueId: 'AST-1'),
        _line(2, item: 'ups', uniqueId: 'AST-1'),
        _line(3, item: 'UPS', uniqueId: 'AST-2'),
        _line(4, item: 'Panel'),
        _line(5, item: ' panel '),
      ]);
      final groups = r.assetGroups;
      expect(groups.length, 3);
      expect(groups[0].key, 'AST-1');
      expect(groups[0].lines.map((l) => l.id), [1, 2]);
      expect(groups[0].photoHolder.id, 1);
      expect(groups[1].key, 'AST-2');
      expect(groups[2].key, '1::panel');
      expect(groups[2].lines.map((l) => l.id), [4, 5]);
    });

    test('displayTitle uses asset name only when category has several', () {
      final r = _record([
        _line(1, item: 'UPS', category: 'Power', uniqueId: 'A'),
        _line(2, item: 'Panel', category: 'Power', uniqueId: 'B'),
        _line(3, item: 'Fan', category: 'Cooling', uniqueId: 'C'),
        _line(4, categoryId: null, item: 'Misc', category: ''),
      ]);
      final g = r.assetGroups;
      expect(g[0].displayTitle, 'UPS');
      expect(g[1].displayTitle, 'Panel');
      expect(g[2].displayTitle, 'Cooling');
      expect(g[3].categoryLabel, 'General');
      expect(g[3].key, 'none::misc');
    });

    test('checkedOut, source, applicability and supervisorExcluded', () {
      final r = _record([
        _line(1,
            item: 'A',
            checkedOut: true,
            source: 'TECHNICIAN',
            applicability: 'REQUIRED'),
        _line(2, item: 'A', checkedOut: true),
        _line(3, item: 'B', checkedOut: false),
        _line(4,
            item: 'C', checkedOut: true, excluded: true, source: 'SUPERVISOR'),
        _line(5, item: 'D', checkedOut: null),
      ]);
      final g = {for (final x in r.assetGroups) x.assetName: x};
      expect(g['A']!.checkedOut, isTrue);
      expect(g['A']!.checkoutSource, 'TECHNICIAN');
      expect(g['A']!.applicability, 'REQUIRED');
      expect(g['B']!.checkedOut, isFalse);
      expect(g['C']!.checkedOut, isFalse);
      expect(g['C']!.supervisorExcluded, isTrue);
      expect(g['A']!.supervisorExcluded, isFalse);
      expect(g['D']!.checkedOut, isTrue, reason: 'legacy null');
    });

    test('inactive assets hidden until past tech completion', () {
      final lines = [
        _line(1, item: 'A', assetActive: false),
        _line(2, item: 'B', assetActive: true),
      ];
      expect(_record(lines, status: 'IN_PROGRESS').assetGroups.length, 1);
      expect(_record(lines, status: 'TECH_COMPLETED').assetGroups.length, 2);
    });
  });
}
