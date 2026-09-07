import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/widgets/org_scope_filter_bar.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_repository.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:mocktail/mocktail.dart';

class MockInspectionRepository extends Mock implements IInspectionRepository {}

void main() {
  late MockInspectionRepository mockRepo;
  late ProviderContainer container;

  const inspections = [
    Inspection(
      id: 1,
      inspectionNumber: 'INSP-001',
      title: 'Check',
      description: 'Desc',
      priority: InspectionPriority.medium,
      status: InspectionStatus.pending,
    ),
  ];

  setUp(() {
    mockRepo = MockInspectionRepository();
    container = ProviderContainer(
      overrides: [inspectionRepositoryProvider.overrideWithValue(mockRepo)],
    );
  });

  tearDown(() => container.dispose());

  test('setDateRange re-fetches with start_date/end_date', () async {
    when(() => mockRepo.fetchInspections()).thenAnswer((_) async => inspections);
    when(
      () => mockRepo.fetchInspections(
        dateFrom: '2026-09-01',
        dateTo: '2026-09-07',
      ),
    ).thenAnswer((_) async => inspections);

    final controller = container.read(inspectionListControllerProvider.notifier);
    await controller.fetchInspections();
    await controller.setDateRange(DateTime(2026, 9, 1), DateTime(2026, 9, 7));

    verify(
      () => mockRepo.fetchInspections(
        dateFrom: '2026-09-01',
        dateTo: '2026-09-07',
      ),
    ).called(1);
    final state = container.read(inspectionListControllerProvider) as InspectionListLoaded;
    expect(state.dateFrom, DateTime(2026, 9, 1));
    expect(state.dateTo, DateTime(2026, 9, 7));
  });

  // Regression: InspectionViewSet.get_queryset reads depot/division/zone
  // with NO `_id` suffix (unlike WorkOrderViewSet) — pins the param names.
  test('setOrgScope sends depot/division/zone with no _id suffix', () async {
    when(() => mockRepo.fetchInspections()).thenAnswer((_) async => inspections);
    when(
      () => mockRepo.fetchInspections(zoneId: 1, divisionId: 2, depotId: 9),
    ).thenAnswer((_) async => inspections);

    final controller = container.read(inspectionListControllerProvider.notifier);
    await controller.fetchInspections();
    await controller.setOrgScope(const OrgScopeSelection(zoneId: 1, divisionId: 2, depotId: 9));

    verify(() => mockRepo.fetchInspections(zoneId: 1, divisionId: 2, depotId: 9)).called(1);
    final state = container.read(inspectionListControllerProvider) as InspectionListLoaded;
    expect(state.orgScope, const OrgScopeSelection(zoneId: 1, divisionId: 2, depotId: 9));
  });
}
