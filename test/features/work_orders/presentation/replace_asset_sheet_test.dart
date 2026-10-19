import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/replace_asset_sheet.dart';
import 'package:intl/intl.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/fake_auth.dart';

class MockReplacementRepository extends Mock implements IReplacementRepository {}

class FakeAssetReplacementRequest extends Fake
    implements AssetReplacementRequest {}

void main() {
  late MockReplacementRepository repo;
  bool? result;

  const withAsset = ReplacementJobWork(
    recordId: 1,
    workOrderId: 10,
    stationId: 9,
    infrastructureId: 4,
    stationName: 'Vriddhachalam',
    assetId: 501,
    assetUniqueId: 'STN-001',
    assetName: 'Signal',
  );
  const noAsset = ReplacementJobWork(
    recordId: 1,
    workOrderId: 10,
    stationId: 9,
    infrastructureId: 4,
    stationName: 'Vriddhachalam',
  );
  const noStation = ReplacementJobWork(recordId: 1, workOrderId: 10);

  setUpAll(() => registerFallbackValue(FakeAssetReplacementRequest()));

  setUp(() {
    repo = MockReplacementRepository();
    result = null;
    when(() => repo.fetchStationAssets(
          stationId: any(named: 'stationId'),
          infrastructureId: any(named: 'infrastructureId'),
        )).thenAnswer(
      (_) async => const AssetPage(
        assets: [
          Asset(id: 1, uniqueId: 'A-001', make: 'Siemens', model: 'X1'),
          Asset(id: 2, uniqueId: 'B-002', assetCategoryName: 'Lamp'),
        ],
        truncated: false,
      ),
    );
  });

  Future<void> open(
    WidgetTester tester,
    ReplacementJobWork jw, {
    bool canReplace = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          replacementRepositoryProvider.overrideWithValue(repo),
          authControllerProvider.overrideWith(
            () => FakeAuthenticatedController(fakeSession(
              role: AuthRole.maintenanceStaff,
              permissions: canReplace
                  ? const ['maintenance.view', 'assets.replace']
                  : const ['maintenance.view'],
            )),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showReplaceAssetSheet(context, ref, jw),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> fillRequired(WidgetTester tester) async {
    await tester.enterText(
        find.byKey(const Key('replace_asset_new_make')), 'Siemens');
    await tester.enterText(
        find.byKey(const Key('replace_asset_reason')), 'Burnt out');
  }

  Future<void> submit(WidgetTester tester) async {
    final btn = find.byKey(const Key('replace_asset_submit'));
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    await tester.pumpAndSettle();
  }

  testWidgets('pre-filled asset: title, badge, no Change Asset',
      (tester) async {
    await open(tester, withAsset);
    expect(find.text('Replace Asset: STN-001'), findsOneWidget);
    expect(find.byKey(const Key('replace_asset_linked_badge')), findsOneWidget);
    expect(find.byKey(const Key('replace_asset_change')), findsNothing);
    verifyNever(() => repo.fetchStationAssets(
        stationId: any(named: 'stationId'),
        infrastructureId: any(named: 'infrastructureId')));
  });

  testWidgets('empty form shows required messages; date is pre-filled',
      (tester) async {
    await open(tester, withAsset);
    final today = DateFormat('dd MMM yyyy').format(DateTime.now());
    expect(find.text(today), findsOneWidget);
    await submit(tester);
    expect(find.text('New Make is required.'), findsOneWidget);
    expect(find.text('Reason for Replacement is required.'), findsOneWidget);
    verifyNever(() => repo.replaceAsset(any(), any()));
  });

  testWidgets('happy path confirms, sends request, pops true', (tester) async {
    when(() => repo.replaceAsset(any(), any())).thenAnswer((_) async {});
    await open(tester, withAsset);
    await fillRequired(tester);
    await submit(tester);
    expect(find.text('Are you sure you want to replace this asset? '
        'This action is recorded.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('replace_asset_confirm_dialog')));
    await tester.pumpAndSettle();
    final captured = verify(() => repo.replaceAsset(501, captureAny()))
        .captured
        .single as AssetReplacementRequest;
    expect(captured.workOrderId, 10);
    expect(captured.toJson()['new_serial_number'], '');
    expect(captured.toJson()['new_make'], 'Siemens');
    expect(captured.toJson()['replacement_date'],
        DateFormat('yyyy-MM-dd').format(DateTime.now()));
    expect(result, isTrue);
    expect(find.text('Replace Asset: STN-001'), findsNothing);
  });

  testWidgets('403 scope denied shows mapped message and stays open',
      (tester) async {
    when(() => repo.replaceAsset(any(), any())).thenThrow(DioException(
      requestOptions: RequestOptions(path: '/x'),
      response: Response(
        requestOptions: RequestOptions(path: '/x'),
        statusCode: 403,
        data: {
          'detail': 'WorkOrder is not assigned for this asset.',
          'code': 'WORK_ORDER_SCOPE_DENIED',
        },
      ),
      type: DioExceptionType.badResponse,
    ));
    await open(tester, withAsset);
    await fillRequired(tester);
    await submit(tester);
    await tester.tap(find.byKey(const Key('replace_asset_confirm_dialog')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('replace_asset_error')), findsOneWidget);
    expect(find.textContaining('Only the asset this Job Work was raised for'),
        findsOneWidget);
    expect(find.text('Replace Asset: STN-001'), findsOneWidget);
    expect(result, isNull);
  });

  testWidgets('canReplace false shows Unauthorized and never calls repo',
      (tester) async {
    await open(tester, withAsset, canReplace: false);
    await fillRequired(tester);
    await submit(tester);
    expect(
        find.text('Unauthorized: Only Maintenance Staff can replace assets.'),
        findsOneWidget);
    verifyNever(() => repo.replaceAsset(any(), any()));
  });

  testWidgets('no Job Work asset: station-scoped picker, filter, pick, change',
      (tester) async {
    await open(tester, noAsset);
    verify(() => repo.fetchStationAssets(stationId: 9, infrastructureId: 4))
        .called(1);
    expect(find.text('Assets at Vriddhachalam'), findsOneWidget);
    expect(find.byKey(const Key('station_asset_tile_1')), findsOneWidget);
    expect(find.byKey(const Key('station_asset_tile_2')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('station_asset_search')), 'siemens');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('station_asset_tile_1')), findsOneWidget);
    expect(find.byKey(const Key('station_asset_tile_2')), findsNothing);

    await tester.enterText(
        find.byKey(const Key('station_asset_search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No assets found matching "zzz".'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('station_asset_search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('station_asset_tile_2')));
    await tester.pumpAndSettle();
    expect(find.text('Replace Asset: B-002'), findsOneWidget);
    expect(find.byKey(const Key('replace_asset_change')), findsOneWidget);

    await tester.tap(find.byKey(const Key('replace_asset_change')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('station_asset_tile_1')));
    await tester.pumpAndSettle();
    expect(find.text('Replace Asset: A-001'), findsOneWidget);
  });

  testWidgets('no station: message shown and assets never fetched',
      (tester) async {
    await open(tester, noStation);
    expect(
        find.text(
            "This Job Work has no station, so registered assets can't be listed."),
        findsOneWidget);
    verifyNever(() => repo.fetchStationAssets(
        stationId: any(named: 'stationId'),
        infrastructureId: any(named: 'infrastructureId')));
    await tester.tap(find.byKey(const Key('station_asset_cancel')));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
