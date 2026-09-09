import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/reports/data/reports_repository.dart';
import 'package:gssms_mobile/features/reports/domain/models/infrastructure_option.dart';
import 'package:gssms_mobile/features/reports/domain/models/maintenance_register_entry.dart';
import 'package:gssms_mobile/features/reports/presentation/controllers/reports_controller.dart';
import 'package:gssms_mobile/features/reports/presentation/screens/reports_screen.dart';
import '../../../helpers/fake_auth.dart';

class MockReportsRepository extends Mock implements IReportsRepository {}

void main() {
  late MockReportsRepository mockRepo;

  setUpAll(() {
    registerFallbackValue(InfraFilterType.all);
  });

  setUp(() {
    mockRepo = MockReportsRepository();
  });

  group('ReportsScreen Widget Tests', () {
    testWidgets('renders Reports & Audit date filter and register list cards under AppTheme', (tester) async {
      final entries = [
        MaintenanceRegisterEntry(
          id: 101,
          masterName: 'Monthly Transformer Maintenance',
          stationName: 'Sendurai',
          technician: 'Krishna',
          date: DateTime(2026, 9, 7),
          items: const [
            RegisterLineItem(assetName: 'Transformer #1', inspection: 'Check Oil Level', status: 'OK'),
          ],
        ),
      ];

      when(() => mockRepo.fetchMaintenanceRegister(
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            infraType: any(named: 'infraType'),
            infraId: any(named: 'infraId'),
          )).thenAnswer((_) async => entries);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            reportsRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(fakeSession(
                permissions: const ['reports.view'],
              )),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ReportsScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Reports'), findsOneWidget);
      expect(find.byKey(const Key('reports_infra_type')), findsOneWidget);
      expect(find.byKey(const Key('reports_infra_item')), findsOneWidget);
      expect(find.byKey(const Key('date_range_from')), findsOneWidget);
      expect(find.text('Monthly Transformer Maintenance'), findsOneWidget);
      expect(find.text('#1'), findsOneWidget);
    });
  });
}
