import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/inspections/data/inspection_repository.dart';
import 'package:gssms_mobile/features/inspections/domain/models/inspection.dart';
import 'package:gssms_mobile/features/inspections/presentation/controllers/inspection_controllers.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_create_screen.dart';
import 'package:gssms_mobile/features/inspections/presentation/screens/inspection_list_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockInspectionRepository extends Mock implements IInspectionRepository {}

void main() {
  group('Inspection Screens Widget Tests', () {
    late MockInspectionRepository mockRepo;

    const testInspections = [
      Inspection(
        id: 1,
        inspectionNumber: 'INSP-001',
        title: 'EB Bunk Monthly Check',
        description: 'Earth resistance and cleaning',
        priority: InspectionPriority.high,
        status: InspectionStatus.pending,
        stationName: 'Thalanallur',
      ),
    ];

    setUp(() {
      mockRepo = MockInspectionRepository();
    });

    testWidgets('InspectionListScreen renders inspections and log button', (tester) async {
      when(() => mockRepo.fetchInspections()).thenAnswer((_) async => testInspections);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [inspectionRepositoryProvider.overrideWithValue(mockRepo)],
          child: const MaterialApp(home: InspectionListScreen()),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Field Inspections'), findsOneWidget);
      expect(find.text('EB Bunk Monthly Check'), findsOneWidget);
      expect(find.text('INSP-001'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.byKey(const Key('fab_create_inspection')), findsOneWidget);
    });

    testWidgets('InspectionCreateScreen validates inputs and submits', (tester) async {
      when(() => mockRepo.createInspection(
            title: any(named: 'title'),
            description: any(named: 'description'),
            priority: any(named: 'priority'),
            assetId: any(named: 'assetId'),
          )).thenAnswer((_) async => testInspections[0]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [inspectionRepositoryProvider.overrideWithValue(mockRepo)],
          child: const MaterialApp(home: InspectionCreateScreen()),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_inspection_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a title'), findsOneWidget);
      expect(find.text('Please enter detailed findings'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('inspection_title_field')), 'Test Title');
      await tester.enterText(find.byKey(const Key('inspection_description_field')), 'Detailed findings');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_inspection_button')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.createInspection(
            title: 'Test Title',
            description: 'Detailed findings',
            priority: 'MEDIUM',
            assetId: null,
          )).called(1);
    });
  });
}
