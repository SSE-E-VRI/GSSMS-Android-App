import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/reports/domain/register_job_work_adapter.dart';
import 'package:gssms_mobile/features/work_orders/data/work_order_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:mocktail/mocktail.dart';

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

Map<String, dynamic> _record({int? workOrder}) => {
      'id': 900,
      'work_order': workOrder,
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

void main() {
  late MockWorkOrderRepository mockRepo;
  late RegisterJobWorkAdapter adapter;

  setUp(() {
    mockRepo = MockWorkOrderRepository();
    adapter = RegisterJobWorkAdapter(mockRepo);
  });

  group('RegisterJobWorkAdapter', () {
    test('uses the record attached to the Job Work first', () async {
      when(() => mockRepo.fetchMaintenanceRecords(
            workOrderId: any(named: 'workOrderId'),
            scheduleId: any(named: 'scheduleId'),
          )).thenAnswer((_) async => [_record(workOrder: 42)]);

      final report = await adapter.resolve(_wo);

      expect(report.ticket, 'VRI-202609-0042');
      expect(report.showJobWork, isTrue);
      // Register date rule: completion date is absent here, so the
      // maintenance date applies.
      expect(report.dateLabel, '12/09/2026');
      verify(() => mockRepo.fetchMaintenanceRecords(workOrderId: 42))
          .called(1);
      verifyNever(() => mockRepo.fetchMaintenanceRecords(
          scheduleId: any(named: 'scheduleId')));
    });

    test('prefers report_completed_at over date_of_maintenance', () async {
      when(() => mockRepo.fetchMaintenanceRecords(
            workOrderId: any(named: 'workOrderId'),
            scheduleId: any(named: 'scheduleId'),
          )).thenAnswer((_) async => [_record(workOrder: 42)]);

      const completed = WorkOrder(
        id: 42,
        status: WorkOrderStatus.verified,
        type: WorkOrderType.preventive,
        ticketNumber: 'VRI-202609-0042',
        reportCompletedAt: null,
      );
      final wo = completed.copyWith(
        reportCompletedAt: DateTime.utc(2026, 9, 15, 10, 0),
      );
      final report = await adapter.resolve(wo);

      // 15 Sep 2026 10:00 UTC = 15:30 IST.
      expect(report.dateLabel, '15/09/2026');
    });

    test('falls back to the schedule-only record, never another Job Work',
        () async {
      when(() => mockRepo.fetchMaintenanceRecords(
            workOrderId: any(named: 'workOrderId'),
            scheduleId: any(named: 'scheduleId'),
          )).thenAnswer((invocation) async {
        final woId =
            invocation.namedArguments[#workOrderId] as int?;
        if (woId != null) return const [];
        return [
          _record(workOrder: 99),
          _record(workOrder: null),
        ];
      });

      final report = await adapter.resolve(_wo);

      expect(report.station, 'Neyveli');
      expect(report.schedule, 'Station Monthly Maintenance');
    });

    test('throws when no record resolves (error state, never empty)', () async {
      when(() => mockRepo.fetchMaintenanceRecords(
            workOrderId: any(named: 'workOrderId'),
            scheduleId: any(named: 'scheduleId'),
          )).thenAnswer((_) async => const []);

      expect(() => adapter.resolve(_wo), throwsStateError);
    });
  });
}
