import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_profile.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/screens/user_profile_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  late MockAuthRepository mockRepository;

  const profile = UserProfile(
    id: 7,
    username: 'srdee',
    role: 'ADMIN',
    email: 'srdee@example.com',
    phoneNumber: '9990001111',
    designation: 'SrDEE',
  );

  setUp(() {
    mockRepository = MockAuthRepository();
    when(() => mockRepository.getProfile()).thenAnswer((_) async => profile);
  });

  Widget wrap(Widget child) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockRepository),
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('renders email, phone, designation and password fields only', (tester) async {
    await tester.pumpWidget(wrap(const UserProfileScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Personal Information'), findsOneWidget);
    expect(find.byKey(const Key('profile_email_field')), findsOneWidget);
    expect(find.byKey(const Key('profile_phone_field')), findsOneWidget);
    expect(find.byKey(const Key('profile_designation_field')), findsOneWidget);
    expect(find.byKey(const Key('profile_save_changes_button')), findsOneWidget);

    expect(find.text('Change Password'), findsOneWidget);
    expect(find.byKey(const Key('profile_new_password_field')), findsOneWidget);
    expect(find.byKey(const Key('profile_confirm_password_field')), findsOneWidget);
    expect(find.byKey(const Key('profile_update_password_button')), findsOneWidget);

    expect(find.text('HRMS ID'), findsNothing);
    expect(find.text('Telegram Chat ID'), findsNothing);
    expect(find.text('Setup 2FA'), findsNothing);

    expect(find.text('srdee@example.com'), findsOneWidget);
    expect(find.text('9990001111'), findsOneWidget);
    expect(find.text('SrDEE'), findsOneWidget);
  });

  testWidgets('Save Changes PATCHes email, phone_number and designation', (tester) async {
    when(
      () => mockRepository.updateProfile(
        email: any(named: 'email'),
        phoneNumber: any(named: 'phoneNumber'),
        designation: any(named: 'designation'),
      ),
    ).thenAnswer((_) async => profile);

    await tester.pumpWidget(wrap(const UserProfileScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('profile_email_field')), 'new@example.com');
    await tester.enterText(find.byKey(const Key('profile_phone_field')), '123');
    await tester.enterText(find.byKey(const Key('profile_designation_field')), 'DEN');
    await tester.tap(find.byKey(const Key('profile_save_changes_button')));
    await tester.pumpAndSettle();

    verify(
      () => mockRepository.updateProfile(
        email: 'new@example.com',
        phoneNumber: '123',
        designation: 'DEN',
      ),
    ).called(1);
    expect(find.text('Profile updated successfully!'), findsOneWidget);
  });

  testWidgets('Update Password rejects mismatched confirmation', (tester) async {
    await tester.pumpWidget(wrap(const UserProfileScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('profile_new_password_field')), 'secret1');
    await tester.enterText(find.byKey(const Key('profile_confirm_password_field')), 'secret2');
    await tester.ensureVisible(find.byKey(const Key('profile_update_password_button')));
    await tester.tap(find.byKey(const Key('profile_update_password_button')));
    await tester.pump();

    expect(find.text('New passwords do not match.'), findsOneWidget);
    verifyNever(() => mockRepository.changePassword(any()));
  });

  testWidgets('Update Password sends new password when confirmation matches', (tester) async {
    when(() => mockRepository.changePassword(any())).thenAnswer((_) async {});

    await tester.pumpWidget(wrap(const UserProfileScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('profile_new_password_field')), 'secret1');
    await tester.enterText(find.byKey(const Key('profile_confirm_password_field')), 'secret1');
    await tester.ensureVisible(find.byKey(const Key('profile_update_password_button')));
    await tester.tap(find.byKey(const Key('profile_update_password_button')));
    await tester.pumpAndSettle();

    verify(() => mockRepository.changePassword('secret1')).called(1);
    expect(find.text('Password changed successfully.'), findsOneWidget);
  });
}
