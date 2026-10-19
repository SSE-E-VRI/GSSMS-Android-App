import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/reports/presentation/screens/register_job_work_detail_screen.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import '../../../helpers/fake_auth.dart';

class MockWorkOrderRepository extends Mock implements IWorkOrderRepository {}

const _wo = WorkOrder(
  id: 42,
  status: WorkOrderStatus.verified,
  type: WorkOrderType.preventive,
  ticketNumber: 'VRI-202609-0042',
  title: 'Station Monthly Maintenance',
  stationName: 'Neyveli',
  depotName: 'Vriddhachalam Depot',
  originalScheduleId: 7,
);

Map<String, dynamic> _record() => {
      'id': 900,
      'work_order': 42,
      'date_of_maintenance': '2026-09-12T00:00:00+05:30',
      'technician_name': 'tech_ramesh',
      'remarks': '',
      'other_staff': '',
      'schedule_details': {
        'station_name': 'Neyveli',
        'template_name': 'Station Monthly Maintenance',
        'organization': {'depot_name': 'Vriddhachalam Depot'},
      },
      'lines': [],
    };

DioException _forbidden() => DioException(
      requestOptions: RequestOptions(path: '/api/v1/maintenance/records/'),
      response: Response(
        requestOptions: RequestOptions(path: '/api/v1/maintenance/records/'),
        statusCode: 403,
        data: const {'error': 'Permission denied'},
      ),
      type: DioExceptionType.badResponse,
    );

void main() {
  late MockWorkOrderRepository mockRepo;

  setUp(() {
    mockRepo = MockWorkOrderRepository();
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<String> permissions,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workOrderRepositoryProvider.overrideWithValue(mockRepo),
          authControllerProvider.overrideWith(
            () => FakeAuthenticatedController(fakeSession(
              permissions: permissions,
            )),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: const RegisterJobWorkDetailScreen(workOrder: _wo),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('RegisterJobWorkDetailScreen', () {
    testWidgets('shows error with Retry when record resolution fails',
        (tester) async {
      when(() => mockRepo.fetchMaintenanceRecords(
            workOrderId: any(named: 'workOrderId'),
            scheduleId: any(named: 'scheduleId'),
          )).thenThrow(_forbidden());

      await pump(tester, permissions: const ['reports.view']);

      expect(find.textContaining('permission'), findsOneWidget);
      expect(
          find.byKey(const Key('register_detail_retry_button')),
          findsOneWidget);
      expect(find.byKey(const Key('action_download_register_pdf')),
          findsNothing);
    });

    testWidgets('shows report summary and enables Print with export grant',
        (tester) async {
      when(() => mockRepo.fetchMaintenanceRecords(
            workOrderId: any(named: 'workOrderId'),
            scheduleId: any(named: 'scheduleId'),
          )).thenAnswer((_) async => [_record()]);

      await pump(tester,
          permissions: const ['reports.view', 'reports.export']);

      expect(find.text('VRI-202609-0042'), findsWidgets);
      expect(
          find.byKey(const Key('action_download_register_pdf')),
          findsOneWidget);
    });
  });
}
