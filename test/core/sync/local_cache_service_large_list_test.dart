import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/work_order.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('round-trips 500 work orders through isolate encode/decode', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = LocalCacheService(prefs);

    final orders = List.generate(
      500,
      (i) => WorkOrder(
        id: i + 1,
        status: WorkOrderStatus.assigned,
        type: WorkOrderType.preventive,
        title: 'Job Work number ${i + 1} ${'x' * 200}',
        assetName: 'ASSET-$i',
      ),
    );

    await service.cacheWorkOrders(orders);
    expect(prefs.getString('gssms_cache_work_orders_list')!.length, greaterThan(100000));

    final back = await service.getCachedWorkOrders();
    expect(back.length, 500);
    expect(back.first.id, 1);
    expect(back.last.id, 500);
    expect(back[250].title, orders[250].title);
    expect(back[250].assetName, 'ASSET-250');
  });
}
