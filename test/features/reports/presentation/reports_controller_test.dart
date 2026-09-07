import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/reports/data/infrastructure_options_service.dart';
import 'package:gssms_mobile/features/reports/data/reports_repository.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_state.dart';
import 'package:mocktail/mocktail.dart';

class MockReportsRepository extends Mock implements IReportsRepository {}

class MockInfrastructureOptionsService extends Mock
    implements InfrastructureOptionsService {}

void main() {
  setUpAll(() {
    registerFallbackValue(InfraFilterType.all);
  });

  late MockReportsRepository mockRepo;
  late MockInfrastructureOptionsService mockOptions;
  late ProviderContainer container;

  setUp(() {
    mockRepo = MockReportsRepository();
    mockOptions = MockInfrastructureOptionsService();
    when(
      () => mockRepo.fetchMaintenanceRegister(
        startDate: any(named: 'startDate'),
        endDate: any(named: 'endDate'),
        infraType: any(named: 'infraType'),
        infraId: any(named: 'infraId'),
      ),
    ).thenAnswer((_) async => const []);
    container = ProviderContainer(
      overrides: [
        reportsRepositoryProvider.overrideWithValue(mockRepo),
        infrastructureOptionsServiceProvider.overrideWithValue(mockOptions),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('setInfraType fetches options and passes station_id on the next register call', () async {
    when(() => mockOptions.fetchOptions(InfraFilterType.station)).thenAnswer(
      (_) async => const [InfrastructureOption(id: 12, name: 'Sendurai')],
    );

    final controller = container.read(reportsControllerProvider.notifier);
    await controller.loadRegister(
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 7),
    );
    await controller.setInfraType(InfraFilterType.station);
    await controller.setInfraId(12);

    verify(() => mockOptions.fetchOptions(InfraFilterType.station)).called(1);
    verify(
      () => mockRepo.fetchMaintenanceRegister(
        startDate: '2026-09-01',
        endDate: '2026-09-07',
        infraType: InfraFilterType.station,
        infraId: 12,
      ),
    ).called(1);

    final state = container.read(reportsControllerProvider) as ReportsLoaded;
    expect(state.infraType, InfraFilterType.station);
    expect(state.infraId, 12);
    expect(state.infraOptions.single.name, 'Sendurai');
  });

  // Regression: fetching the item dropdown's options is an enrichment, not
  // the register itself — a role lacking infrastructure.view (or a network
  // hiccup) here must not turn an otherwise-successful register load into a
  // full-screen error and lose the already-loaded entries.
  test('setInfraType still loads the register when fetching item options fails', () async {
    when(() => mockOptions.fetchOptions(InfraFilterType.lcGate))
        .thenThrow(Exception('403 forbidden'));

    final controller = container.read(reportsControllerProvider.notifier);
    await controller.loadRegister(
      startDate: DateTime(2026, 9, 1),
      endDate: DateTime(2026, 9, 7),
    );
    await controller.setInfraType(InfraFilterType.lcGate);

    final state = container.read(reportsControllerProvider);
    expect(state, isA<ReportsLoaded>());
    expect((state as ReportsLoaded).infraType, InfraFilterType.lcGate);
    expect(state.infraOptions, isEmpty);
  });
}
