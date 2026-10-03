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
    test('parses severity, remark, group and mode keys', () {
      final workspace = VerificationWorkspace.fromJson(const {
        'can_verify': true,
        'work_order': {
          'status': 'TECH_COMPLETED',
          'execution_mode': 'INSPECTION',
          'inspection_execution': {
            'points': [
              {'point_number': 1, 'observation': 'Crack'},
            ],
          },
        },
        'record': {'id': 55, 'work_order': 101, 'lines': []},
        'deficiency_rows': [
          {
            'id': 7,
            'asset': 'TR-01',
            'checkpoint': 'Oil level',
            'finding': 'Low',
            'action': 'Top up',
            'severity': 'MAJOR',
            'deficiency_id': 12,
            'deficiency_version': 3,
            'severity_id': 2,
            'will_raise_on_verification': false,
          },
        ],
        'remark_deficiency_rows': [
          {
            'id': 'remark-0',
            'remark_index': 0,
            'asset': null,
            'checkpoint': 'Technician Remark',
            'finding': 'Rust on frame',
            'deficiency_id': null,
            'is_remark': true,
            'is_flagged': false,
          },
        ],
        'remark_asset_options': [
          {'key': 'A-1', 'label': 'Transformer A-1'},
        ],
        'asset_groups': [
          {
            'key': 'g1',
            'asset_category_id': 4,
            'asset_name': 'TR-01',
            'display_name': 'Transformer TR-01',
            'checked_out': true,
            'checkout_source': 'SUPERVISOR',
            'lines': [],
          },
        ],
        'complaint_execution': {'id': 9, 'initial_findings': 'Noise'},
        'rectification': null,
      });

      expect(workspace.workOrderStatus, 'TECH_COMPLETED');
      expect(workspace.executionMode, 'INSPECTION');
      expect(workspace.mode, 'INSPECTION');
      expect(workspace.recordId, 55);
      expect(workspace.inspectionExecution!.points.single.pointNumber, 1);
      final row = workspace.deficiencyRows.single;
      expect(row.rowKey, '7');
      expect(row.deficiencyId, 12);
      expect(row.deficiencyVersion, 3);
      expect(row.severityId, 2);
      expect(row.isRemark, isFalse);
      final remark = workspace.remarkDeficiencyRows.single;
      expect(remark.rowKey, 'remark-0');
      expect(remark.remarkIndex, 0);
      expect(remark.isRemark, isTrue);
      expect(remark.isFlagged, isFalse);
      expect(workspace.remarkAssetOptions.single.key, 'A-1');
      final group = workspace.assetGroups.single;
      expect(group.displayName, 'Transformer TR-01');
      expect(group.checkedOut, isTrue);
      expect(group.checkoutSource, 'SUPERVISOR');
      expect(workspace.complaintExecution!.initialFindings, 'Noise');
      expect(workspace.rectification, isNull);
    });

    test('mode defaults to CHECKLIST when absent', () {
      expect(VerificationWorkspace.fromJson(const {}).mode, 'CHECKLIST');
    });
  });
}
