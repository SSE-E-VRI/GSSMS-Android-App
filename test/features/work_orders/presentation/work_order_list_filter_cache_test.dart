import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:gssms_mobile/features/work_orders/presentation/controllers/work_order_state.dart';

void main() {
  const orders = [
    WorkOrder(
      id: 1,
      status: WorkOrderStatus.newOrder,
      type: WorkOrderType.preventive,
      title: 'Monthly Transformer Inspection',
    ),
    WorkOrder(
      id: 2,
      status: WorkOrderStatus.newOrder,
      type: WorkOrderType.corrective,
      title: 'Fix lift',
    ),
  ];

  test('filteredOrders is cached per state instance', () {
    const state = WorkOrderListLoaded(workOrders: orders);
    expect(identical(state.filteredOrders, state.filteredOrders), isTrue);
    expect(state.filteredOrders, hasLength(2));
  });

  test('copyWith(searchQuery:) recomputes', () {
    const state = WorkOrderListLoaded(workOrders: orders);
    final first = state.filteredOrders;
    final next = state.copyWith(searchQuery: '  TRANSFORMER ');
    expect(identical(next.filteredOrders, first), isFalse);
    expect(next.filteredOrders.map((o) => o.id), [1]);
    expect(state.filteredOrders, hasLength(2));
  });
}
