import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/sync/sync_manager.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/maintenance_record.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_controllers.dart';
import 'package:gssms_mobile/features/work_orders/presentation/screens/work_order_detail_screen.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';

class _Repository extends Mock implements IWorkOrderRepository {}

void main() {
  for (final scenario in [
    'owned',
    'foreign cache',
    'foreign assignment',
    'not downloaded',
    'wrong record',
    'assigned',
    'closed',
    'server forbidden'
  ]) {
    testWidgets('offline checklist entry: $scenario', (tester) async {
      final repository = _Repository();
      final cache = InMemoryLocalCacheService();
      await cache.setCacheOwnerUserId(scenario == 'foreign cache' ? 2 : 1);
      if (scenario != 'not downloaded') {
        await cache.cacheMaintenanceRecord(MaintenanceRecord(
            id: 55, workOrderId: scenario == 'wrong record' ? 99 : 1));
      }
      final order = WorkOrder(
          id: 1,
          type: WorkOrderType.preventive,
          title: 'Downloaded',
          assignedToId: scenario == 'foreign assignment' ? 2 : 1,
          linkedRecordId: 55,
          status: scenario == 'assigned'
              ? WorkOrderStatus.assigned
              : scenario == 'closed'
                  ? WorkOrderStatus.closed
                  : WorkOrderStatus.inProgress);
      final error = DioException(
          requestOptions: RequestOptions(path: '/'),
          type: scenario == 'server forbidden'
              ? DioExceptionType.badResponse
              : DioExceptionType.connectionError,
          response: scenario == 'server forbidden'
              ? Response(
                  requestOptions: RequestOptions(path: '/'), statusCode: 403)
              : null);
      when(() => repository.fetchWorkOrderById(1))
          .thenAnswer((_) async => order);
      when(() => repository.fetchAllowedActions(1)).thenAnswer((_) async => throw error);
      when(() => repository.fetchAudit(1)).thenAnswer((_) async => throw error);
      await tester.pumpWidget(ProviderScope(
          overrides: [
            workOrderRepositoryProvider.overrideWithValue(repository),
            localCacheServiceProvider.overrideWithValue(cache),
            authControllerProvider.overrideWith(() =>
                FakeAuthenticatedController(
                    fakeSession(role: AuthRole.maintenanceStaff, userId: 1))),
          ],
          child:
              const MaterialApp(home: WorkOrderDetailScreen(workOrderId: 1))));
      await tester.pumpAndSettle();
      expect(find.text('Open Checklist'),
          scenario == 'owned' ? findsOneWidget : findsNothing);
      expect(find.text('Start Execution'), findsNothing);
      expect(find.text('Verify'), findsNothing);
      expect(find.text('Close'), findsNothing);
    });
  }
}
