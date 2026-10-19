import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/presentation/pending_action_status_labels.dart';

void main() {
  group('pendingActionStatusLabel (web DashboardView / jobWorkStatus parity)', () {
    const expected = {
      'NEW': 'Unassigned',
      'ASSIGNED': 'Assigned - Not Started',
      'IN_PROGRESS': 'In Progress',
      'TECH_COMPLETED': 'Pending Verification',
      'REWORK_REQUIRED': 'Rework Required',
      'ON_HOLD': 'On Hold',
      'VERIFIED': 'Verified',
      'CLOSED': 'Closed',
      'CANCELLED': 'Cancelled',
      'OPEN': 'Open',
      'ACTION_REQUIRED': 'Action Required',
      'CONVERTED': 'Converted',
      'RESOLVED': 'Resolved',
      'PARTIALLY_CONVERTED': 'Partially Converted',
      'UNDER_SUPERVISOR_REVIEW': 'Under Review',
      'REPLACEMENT_PENDING_APPROVAL': 'Replacement Pending Approval',
      'REPLACEMENT_APPROVED': 'Replacement Approved',
    };

    for (final entry in expected.entries) {
      test('${entry.key} -> ${entry.value}', () {
        expect(pendingActionStatusLabel(entry.key), entry.value);
      });
    }

    test('is case- and whitespace-tolerant', () {
      expect(pendingActionStatusLabel(' new '), 'Unassigned');
    });

    test('unknown codes are title-cased', () {
      expect(pendingActionStatusLabel('SOME_FUTURE_STATUS'), 'Some Future Status');
    });

    test('null and blank give an empty string', () {
      expect(pendingActionStatusLabel(null), '');
      expect(pendingActionStatusLabel('  '), '');
    });
  });

  group('pendingActionStatusLabelWithAssignee (web Action-cell wording)', () {
    test('ASSIGNED with a name reads "Assigned (name)"', () {
      expect(pendingActionStatusLabelWithAssignee('ASSIGNED', 'krishna'),
          'Assigned (krishna)');
    });

    test('IN_PROGRESS with a name reads "In Progress (name)"', () {
      expect(pendingActionStatusLabelWithAssignee('IN_PROGRESS', 'krishna'),
          'In Progress (krishna)');
    });

    test('REWORK_REQUIRED reads "Rework" (web chip), with or without a name', () {
      expect(pendingActionStatusLabelWithAssignee('REWORK_REQUIRED', 'krishna'),
          'Rework');
      expect(pendingActionStatusLabelWithAssignee('REWORK_REQUIRED', null),
          'Rework');
    });

    test('NEW with a name stays "Unassigned"', () {
      expect(
          pendingActionStatusLabelWithAssignee('NEW', 'krishna'), 'Unassigned');
    });

    test('missing or blank name keeps the base label', () {
      expect(pendingActionStatusLabelWithAssignee('ASSIGNED', null),
          'Assigned - Not Started');
      expect(pendingActionStatusLabelWithAssignee('ASSIGNED', ''),
          'Assigned - Not Started');
      expect(pendingActionStatusLabelWithAssignee('ASSIGNED', '  '),
          'Assigned - Not Started');
      expect(pendingActionStatusLabelWithAssignee('IN_PROGRESS', null),
          'In Progress');
    });

    test('other statuses ignore the name', () {
      expect(pendingActionStatusLabelWithAssignee('TECH_COMPLETED', 'x'),
          'Pending Verification');
      expect(pendingActionStatusLabelWithAssignee('VERIFIED', 'x'), 'Verified');
    });
  });
}
