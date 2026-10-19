import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset_component.dart';
import 'package:gssms_mobile/features/work_orders/data/replacement_repository.dart';
import 'package:gssms_mobile/features/work_orders/domain/models/replacement_requests.dart';
import 'package:gssms_mobile/features/work_orders/presentation/widgets/replace_component_sheet.dart';
import 'package:mocktail/mocktail.dart';

class MockReplacementRepository extends Mock implements IReplacementRepository {}

class FakeInstalledRequest extends Fake
    implements InstalledComponentReplacementRequest {}

class FakeJobWorkRequest extends Fake
    implements JobWorkComponentReplacementRequest {}

void main() {
  late MockReplacementRepository repo;
  bool? result;

  const jobWork = ReplacementJobWork(
    recordId: 5,
    workOrderId: 10,
    stationId: 9,
    infrastructureId: 4,
    stationName: 'Vriddhachalam',
    assetId: 501,
    assetUniqueId: 'STN-001',
  );
  const noStationJobWork = ReplacementJobWork(recordId: 5, workOrderId: 10);

  const asset501 = Asset(
    id: 501,
    uniqueId: 'STN-001',
    assetCategoryName: 'Signal',
  );
  const asset502 = Asset(id: 502, uniqueId: 'STN-002');

  const lamp = AssetComponent(
    sourceId: '77',
    name: 'Indication Lamp',
    componentCode: 'LAMP-01',
    make: 'Old Make',
    serialNumber: 'OLD-001',
    status: 'IN_SERVICE',
    sourceType: 'INSTALLED_COMPONENT',
  );

  setUpAll(() {
    registerFallbackValue(FakeInstalledRequest());
    registerFallbackValue(FakeJobWorkRequest());
  });

  setUp(() {
    repo = MockReplacementRepository();
    result = null;
    when(() => repo.fetchStationAssets(
          stationId: any(named: 'stationId'),
          infrastructureId: any(named: 'infrastructureId'),
        )).thenAnswer(
      (_) async =>
          const AssetPage(assets: [asset501, asset502], truncated: false),
    );
    when(() => repo.fetchReplaceableComponents(501))
        .thenAnswer((_) async => const [lamp]);
  });

  Future<void> open(
    WidgetTester tester, {
    ReplacementJobWork jw = jobWork,
  }) async {
    tester.view.physicalSize = const Size(900, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [replacementRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await showReplaceComponentSheet(context, ref, jw),
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

  Future<void> type(WidgetTester tester, String key, String text) async {
    await tester.enterText(find.byKey(Key('replace_component_$key')), text);
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('replace_component_submit')));
    await tester.pumpAndSettle();
  }

  Future<void> selectLamp(WidgetTester tester) async {
    await tester
        .tap(find.byKey(const Key('replace_component_component_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('LAMP-01').last);
    await tester.pumpAndSettle();
  }

  String errorText(WidgetTester tester) => tester
      .widget<Text>(find.byKey(const Key('replace_component_error')))
      .data!;

  testWidgets('non-registered path logs a Job Work replacement',
      (tester) async {
    when(() => repo.logJobWorkReplacement(any(), any()))
        .thenAnswer((_) async {});
    await open(tester);
    await tester.tap(find.text('Non-registered asset'));
    await tester.pumpAndSettle();

    await type(tester, 'asset_reference', 'Legacy CLS Panel');
    await type(tester, 'name', 'Indication Lamp');
    await type(tester, 'new_make', 'Siemens');
    await type(tester, 'new_serial', 'LAMP-2026-001');
    await type(tester, 'reason', 'Lamp failed');
    await submit(tester);

    final captured = verify(
      () => repo.logJobWorkReplacement(captureAny(), captureAny()),
    ).captured;
    expect(captured[0], 10);
    final req = captured[1] as JobWorkComponentReplacementRequest;
    expect(req.assetReference, 'Legacy CLS Panel');
    expect(req.componentName, 'Indication Lamp');
    expect(req.newMake, 'Siemens');
    expect(req.newSerialNumber, 'LAMP-2026-001');
    expect(req.reason, 'Lamp failed');
    expect(req.toJson().containsKey('new_warranty_expiry_date'), isFalse);
    expect(result, isTrue);
    verifyNever(() => repo.replaceInstalledComponent(any(), any()));
  });

  testWidgets('registered path pre-selects Job Work asset and replaces',
      (tester) async {
    when(() => repo.replaceInstalledComponent(any(), any()))
        .thenAnswer((_) async {});
    await open(tester);

    verify(() => repo.fetchStationAssets(stationId: 9, infrastructureId: 4))
        .called(1);
    expect(find.textContaining('STN-001 — Signal'), findsOneWidget);
    expect(find.textContaining('Record a component replaced within asset STN-001'),
        findsOneWidget);

    await selectLamp(tester);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('replace_component_name')))
          .controller!
          .text,
      'Indication Lamp',
    );
    expect(
      tester
          .widget<TextFormField>(
              find.byKey(const Key('replace_component_old_serial')))
          .controller!
          .text,
      'OLD-001',
    );

    await type(tester, 'new_make', 'New Make');
    await type(tester, 'new_serial', 'NEW-001');
    await type(tester, 'reason', 'Burnt out');
    await submit(tester);

    final captured = verify(
      () => repo.replaceInstalledComponent(captureAny(), captureAny()),
    ).captured;
    expect(captured[0], '77');
    expect((captured[1] as InstalledComponentReplacementRequest).toJson(), {
      'replacement_work_order': 10,
      'replacement_reason': 'Burnt out',
      'new_component': {
        'component_code': 'LAMP-01',
        'name': 'Indication Lamp',
        'make': 'New Make',
        'serial_number': 'NEW-001',
      },
    });
    expect(result, isTrue);
  });

  testWidgets('non-replaceable components are filtered into the empty warning',
      (tester) async {
    // The repository contract returns only replaceable rows; an empty list
    // must surface the web warning.
    when(() => repo.fetchReplaceableComponents(501))
        .thenAnswer((_) async => const []);
    await open(tester);
    expect(find.byKey(const Key('replace_component_no_components')),
        findsOneWidget);
    expect(find.textContaining('No replaceable registered components'),
        findsOneWidget);
  });

  test('isReplaceableInstalled drops REPLACED and ASSET_SET_MEMBER rows', () {
    const replaced = AssetComponent(
        sourceId: '1',
        name: 'a',
        status: 'REPLACED',
        sourceType: 'INSTALLED_COMPONENT');
    const member = AssetComponent(
        sourceId: '2',
        name: 'b',
        status: 'IN_SERVICE',
        sourceType: 'ASSET_SET_MEMBER');
    expect(replaced.isReplaceableInstalled, isFalse);
    expect(member.isReplaceableInstalled, isFalse);
    expect(lamp.isReplaceableInstalled, isTrue);
  });

  testWidgets('validation messages appear in the web order', (tester) async {
    await open(tester);

    // 1. registered, no component.
    await submit(tester);
    expect(errorText(tester), 'Please select a registered component.');

    // 2. non-registered, no reference.
    await tester.tap(find.text('Non-registered asset'));
    await tester.pumpAndSettle();
    await submit(tester);
    expect(errorText(tester),
        'Please enter the non-registered asset name or identifier.');

    // 3. required fields.
    await type(tester, 'asset_reference', 'Panel');
    await submit(tester);
    expect(
      errorText(tester),
      'Please fill in required fields (Component Name, Make, Serial No, Reason).',
    );
    expect(find.text('Required'), findsNWidgets(4));
    verifyNever(() => repo.logJobWorkReplacement(any(), any()));
    verifyNever(() => repo.replaceInstalledComponent(any(), any()));
  });

  testWidgets('registered mode without an asset asks for an asset too',
      (tester) async {
    await open(tester, jw: const ReplacementJobWork(
      recordId: 5,
      workOrderId: 10,
      stationId: 9,
      infrastructureId: 4,
    ));
    expect(find.textContaining('-- Select registered asset --'), findsOneWidget);
    await submit(tester);
    expect(errorText(tester), 'Please select a registered component.');
    expect(find.text('Please select a registered asset.'), findsOneWidget);
  });

  testWidgets('no station: warns, starts non-registered, never lists assets',
      (tester) async {
    await open(tester, jw: noStationJobWork);
    expect(find.byKey(const Key('replace_component_no_station')),
        findsOneWidget);
    expect(find.byKey(const Key('replace_component_asset_reference')),
        findsOneWidget);
    verifyNever(() => repo.fetchStationAssets(
        stationId: any(named: 'stationId'),
        infrastructureId: any(named: 'infrastructureId')));
  });

  testWidgets('server failure is shown inline and the sheet stays open',
      (tester) async {
    when(() => repo.logJobWorkReplacement(any(), any())).thenThrow(
      DioException(
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
      ),
    );
    await open(tester);
    await tester.tap(find.text('Non-registered asset'));
    await tester.pumpAndSettle();
    await type(tester, 'asset_reference', 'Panel');
    await type(tester, 'name', 'Lamp');
    await type(tester, 'new_make', 'Siemens');
    await type(tester, 'new_serial', 'S1');
    await type(tester, 'reason', 'Failed');
    await submit(tester);

    expect(errorText(tester), startsWith('Failed to save component replacement: '));
    expect(find.textContaining('work order'), findsNothing);
    expect(find.text('Replace Component'), findsOneWidget);
    expect(result, isNull);
  });
}
