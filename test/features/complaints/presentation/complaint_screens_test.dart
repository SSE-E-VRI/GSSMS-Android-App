import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/app_theme.dart';
import 'package:gssms_mobile/features/complaints/data/complaint_repository.dart';
import 'package:gssms_mobile/features/complaints/domain/models/complaint.dart';
import 'package:gssms_mobile/features/complaints/presentation/controllers/complaint_controllers.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_create_screen.dart';
import 'package:gssms_mobile/features/complaints/presentation/screens/complaint_list_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockComplaintRepository extends Mock implements IComplaintRepository {}

void main() {
  group('Complaint Screens Widget Tests', () {
    late MockComplaintRepository mockRepo;

    const testComplaints = [
      Complaint(
        id: 1,
        complaintNumber: 'CMP-001',
        title: 'Transformer Leakage',
        description: 'Oil leaking near base valve',
        severity: ComplaintSeverity.high,
        status: ComplaintStatus.open,
        stationName: 'VRI',
      ),
    ];

    setUp(() {
      mockRepo = MockComplaintRepository();
    });

    testWidgets('ComplaintListScreen renders complaints and log button', (tester) async {
      when(() => mockRepo.fetchComplaints()).thenAnswer((_) async => testComplaints);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            complaintRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const ComplaintListScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Complaints & Issues'), findsOneWidget);
      expect(find.byKey(const Key('date_range_from')), findsOneWidget);
      expect(find.text('Transformer Leakage'), findsOneWidget);
      expect(find.text('CMP-001'), findsOneWidget);
      expect(find.text('High'), findsOneWidget);
      expect(find.byKey(const Key('fab_create_complaint')), findsOneWidget);
    });

    testWidgets('ComplaintCreateScreen validates inputs and submits', (tester) async {
      when(() => mockRepo.createComplaint(
            title: any(named: 'title'),
            description: any(named: 'description'),
            severity: any(named: 'severity'),
            assetId: any(named: 'assetId'),
          )).thenAnswer((_) async => testComplaints[0]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            complaintRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const MaterialApp(
            home: ComplaintCreateScreen(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap submit with empty fields -> shows validation errors
      await tester.tap(find.byKey(const Key('submit_complaint_button')));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a complaint title'), findsOneWidget);
      expect(find.text('Please enter detailed description'), findsOneWidget);

      // Enter valid fields
      await tester.enterText(find.byKey(const Key('complaint_title_field')), 'Test Title');
      await tester.enterText(find.byKey(const Key('complaint_description_field')), 'Detailed failure description');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('submit_complaint_button')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.createComplaint(
            title: 'Test Title',
            description: 'Detailed failure description',
            severity: 'MEDIUM',
            assetId: null,
          )).called(1);
    });
  });
}
