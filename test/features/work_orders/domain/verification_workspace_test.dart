import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/verification_workspace.dart';

void main() {
  group('VerificationWorkspace.fromJson', () {
    test('parses record, can_verify, disabled_reasons, and severity-aggregated deficiencies', () {
      // The real shape from ExecutionChecklistService.get_verification_workspace:
      // one row per severity with a count, not one row per deficient line.
      final workspace = VerificationWorkspace.fromJson(const {
        'can_verify': false,
        'disabled_reasons': ['Checklist incomplete'],
        'deficiencies': [
          {'severity': 'CRITICAL', 'count': 2},
          {'severity': 'MAJOR', 'count': 1},
        ],
        'record': {
          'id': 55,
          'work_order': 101,
          'lines': [
            {
              'id': 1,
              'item_name': 'TR-01',
              'inspection_point': 'Oil level',
              'status': 'OK',
            },
          ],
        },
      });

      expect(workspace.canVerify, isFalse);
      expect(workspace.disabledReasons, ['Checklist incomplete']);
      expect(workspace.deficiencyCount, 3, reason: 'sums the per-severity counts, not the number of rows');
      expect(workspace.deficiencies, ['2 CRITICAL', '1 MAJOR']);
      expect(workspace.record?.id, 55);
      expect(workspace.record?.lines.single.displayTitle, 'Oil level');
    });

    test('falls back to a per-item label for an unrecognized deficiency shape', () {
      final workspace = VerificationWorkspace.fromJson(const {
        'deficiencies': [
          {'label': 'Oil leak'},
          'Loose earth',
        ],
      });

      expect(workspace.deficiencyCount, 2);
      expect(workspace.deficiencies, ['Oil leak', 'Loose earth']);
    });

    test('defaults can_verify to false when the key is absent', () {
      final workspace = VerificationWorkspace.fromJson(const {});
      expect(workspace.canVerify, isFalse);
      expect(workspace.record, isNull);
      expect(workspace.deficiencyCount, 0);
    });
  });
}
