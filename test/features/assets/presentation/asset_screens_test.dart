import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/assets/data/asset_api_service.dart';
import 'package:gssms_mobile/features/assets/data/asset_repository.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/presentation/controllers/asset_controllers.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_detail_screen.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_list_screen.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:mocktail/mocktail.dart';
import '../../../helpers/fake_auth.dart';

class MockAssetRepository extends Mock implements IAssetRepository {}

void main() {
  group('Asset Screens Widget Tests', () {
    late MockAssetRepository mockRepo;

    const testAssets = [
      Asset(
        id: 42,
        uniqueId: 'VRI-STN-CLS-MAIN-001',
        assetTypeName: 'Main Panel',
        assetCategoryName: 'CLS Panels',
        criticality: AssetCriticality.critical,
        stationName: 'VRI',
        make: 'SUNTRON',
      ),
    ];

    setUp(() {
      mockRepo = MockAssetRepository();
    });

    testWidgets('AssetListScreen renders asset card and QR action', (tester) async {
      when(() => mockRepo.fetchAssets(
        zoneId: any(named: 'zoneId'),
        divisionId: any(named: 'divisionId'),
        depotId: any(named: 'depotId'),
        stationId: any(named: 'stationId'),
      )).thenAnswer(
        (_) async => const AssetPage(assets: testAssets, truncated: false),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(
                fakeSession(permissions: const ['assets.view']),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AssetListScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Asset Registry'), findsOneWidget);
      expect(find.text('VRI-STN-CLS-MAIN-001'), findsOneWidget);
      expect(find.text('Main Panel'), findsOneWidget);
      expect(find.byKey(const Key('action_scan_qr')), findsOneWidget);
    });

    testWidgets('AssetDetailScreen renders technical details without the complaint log button', (tester) async {
      when(() => mockRepo.fetchAssetById(42)).thenAnswer((_) async => testAssets[0]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(
                fakeSession(
                  permissions: const ['assets.view', 'complaints.create'],
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AssetDetailScreen(assetId: 42),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Title reflects the asset's own category, not its internal id.
      expect(find.text('CLS Panels'), findsOneWidget);
      expect(find.text('Main Panel'), findsOneWidget);
      expect(find.text('SUNTRON'), findsOneWidget);
      // "Log Complaint for Asset" was removed — creating a complaint now
      // lives only in the Complaints module's own list screen.
      expect(find.byKey(const Key('action_log_asset_complaint')), findsNothing);
    });

    testWidgets('AssetDetailScreen falls back to the asset id while loading',
        (tester) async {
      final completer = Completer<Asset>();
      when(() => mockRepo.fetchAssetById(42)).thenAnswer((_) => completer.future);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetRepositoryProvider.overrideWithValue(mockRepo),
            authControllerProvider.overrideWith(
              () => FakeAuthenticatedController(
                fakeSession(permissions: const ['assets.view']),
              ),
            ),
          ],
          child: const MaterialApp(
            home: AssetDetailScreen(assetId: 42),
          ),
        ),
      );
      // No pumpAndSettle: the fetch is still pending, so there is no category
      // to title the screen with yet.
      await tester.pump();

      expect(find.text('Asset #42'), findsOneWidget);

      completer.complete(testAssets[0]);
      await tester.pumpAndSettle();
      expect(find.text('CLS Panels'), findsOneWidget);
    });
  });
}
