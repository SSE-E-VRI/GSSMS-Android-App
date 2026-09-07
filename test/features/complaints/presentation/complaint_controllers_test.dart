import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_repository.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:mocktail/mocktail.dart';

class MockComplaintRepository extends Mock implements IComplaintRepository {}

void main() {
  late MockComplaintRepository mockRepo;
  late ProviderContainer container;

  const complaints = [
    Complaint(
      id: 1,
      complaintNumber: 'CMP-001',
      title: 'Leak',
      description: 'Oil',
      severity: ComplaintSeverity.high,
      status: ComplaintStatus.open,
    ),
  ];

  setUp(() {
    mockRepo = MockComplaintRepository();
    container = ProviderContainer(
      overrides: [complaintRepositoryProvider.overrideWithValue(mockRepo)],
    );
  });

  tearDown(() => container.dispose());

  test('setDateRange re-fetches with start_date/end_date', () async {
    when(() => mockRepo.fetchComplaints()).thenAnswer((_) async => complaints);
    when(
      () => mockRepo.fetchComplaints(
        dateFrom: '2026-09-01',
        dateTo: '2026-09-07',
      ),
    ).thenAnswer((_) async => complaints);

    final controller = container.read(complaintListControllerProvider.notifier);
    await controller.fetchComplaints();
    await controller.setDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 7));

    verify(
      () => mockRepo.fetchComplaints(
        dateFrom: '2026-09-01',
        dateTo: '2026-09-07',
      ),
    ).called(1);
    final state = container.read(complaintListControllerProvider) as ComplaintListLoaded;
    expect(state.dateFrom, DateTime(2026, 9, 1));
    expect(state.dateTo, DateTime(2026, 9, 7));
  });

  // Regression: ComplaintViewSet.get_queryset reads depot/division/zone with
  // NO `_id` suffix (unlike WorkOrderViewSet) — pins the param names sent.
  test('setOrgScope sends depot/division/zone with no _id suffix', () async {
    when(() => mockRepo.fetchComplaints()).thenAnswer((_) async => complaints);
    when(
      () => mockRepo.fetchComplaints(zoneId: 1, divisionId: 2),
    ).thenAnswer((_) async => complaints);

    final controller = container.read(complaintListControllerProvider.notifier);
    await controller.fetchComplaints();
    await controller.setOrgScope(const OrgScopeSelection(zoneId: 1, divisionId: 2));

    verify(() => mockRepo.fetchComplaints(zoneId: 1, divisionId: 2)).called(1);
    final state = container.read(complaintListControllerProvider) as ComplaintListLoaded;
    expect(state.orgScope, const OrgScopeSelection(zoneId: 1, divisionId: 2));
  });
}
