import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/assets/data/asset_repository.dart';
import 'package:gssms_mobile/features/assets/domain/models/asset.dart';
import 'package:gssms_mobile/features/assets/presentation/controllers/asset_controllers.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_detail_screen.dart';
import 'package:gssms_mobile/features/assets/presentation/screens/asset_list_screen.dart';
import 'package:mocktail/mocktail.dart';

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
      when(() => mockRepo.fetchAssets()).thenAnswer((_) async => testAssets);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetRepositoryProvider.overrideWithValue(mockRepo),
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

    testWidgets('AssetDetailScreen renders technical details and complaint log button', (tester) async {
      when(() => mockRepo.fetchAssetById(42)).thenAnswer((_) async => testAssets[0]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: AssetDetailScreen(assetId: 42),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Asset #42'), findsOneWidget);
      expect(find.text('Main Panel'), findsOneWidget);
      expect(find.text('SUNTRON'), findsOneWidget);
      expect(find.byKey(const Key('action_log_asset_complaint')), findsOneWidget);
    });
  });
}
