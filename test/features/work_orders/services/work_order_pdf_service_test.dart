import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order_audit.dart';
import 'package:gssms_mobile/features/work_orders/services/work_order_pdf_service.dart';

void main() {
  test('WorkOrderPdfService builds a document with meta + history', () async {
    const wo = WorkOrder(
      id: 101,
      status: WorkOrderStatus.assigned,
      type: WorkOrderType.preventive,
      ticketNumber: 'VRI-202609-0101',
      title: 'Station monthly maintenance',
      assetName: 'TR-01',
      stationName: 'VRI',
      depotName: 'Vriddhachalam Depot',
      assignedToName: 'tech_ramesh',
    );
    const audit = WorkOrderAudit(
      workOrderId: 101,
      ticketNumber: 'VRI-202609-0101',
      events: [
        WorkOrderAuditEvent(
          eventId: 'e1',
          eventType: 'STATUS_CHANGE',
          fromState: 'NEW',
          toState: 'ASSIGNED',
          actor: 'incharge_kumar',
          reason: 'Assigned to Ramesh',
        ),
      ],
    );
    final doc = await WorkOrderPdfService.build(wo, audit: audit);
    final bytes = await doc.save();
    expect(bytes.isNotEmpty, isTrue);
  });
}
