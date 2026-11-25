import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/app/app.dart';
import 'package:gssms_mobile/core/services/profile_photo_cache.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_profile.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';
import 'package:gssms_mobile/features/auth/presentation/controllers/auth_controller.dart';
import 'package:gssms_mobile/features/auth/presentation/screens/change_password_screen.dart';
import 'package:gssms_mobile/features/auth/presentation/screens/user_profile_screen.dart';
import 'package:gssms_mobile/features/home/presentation/screens/home_screen.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements IAuthRepository {}

void main() {
  group('S8-1a Contract Staff Session Expiry', () {
    test('cs=true expired valid_until throws ContractExpiredException, not GuestExpiredException', () {
      final expired = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final claims = {
        'username': 'amc_tech_1',
        'user_id': 42,
        'role': 'MAINTENANCE_STAFF',
        'roles': ['MAINTENANCE_STAFF'],
        'permissions': ['maintenance.view'],
        'cs': true,
        'valid_until': expired.toIso8601String(),
      };

      expect(
        () => UserSession.fromClaims(claims, 'tok'),
        throwsA(
          isA<ContractExpiredException>().having(
            (e) => e.message,
            'message',
            'Contract account access has expired.',
          ),
        ),
      );
    });

    test('guest expired valid_until (cs absent/false) still throws GuestExpiredException', () {
      final expired = DateTime.now().toUtc().subtract(const Duration(minutes: 5));
      final claims = {
        'username': 'qr-guest',
        'user_id': 99,
        'role': 'GUEST',
        'roles': ['GUEST'],
        'permissions': ['maintenance.view'],
        'valid_until': expired.toIso8601String(),
      };

      expect(
        () => UserSession.fromClaims(claims, 'tok'),
        throwsA(
          isA<GuestExpiredException>().having(
            (e) => e.message,
            'message',
            'Demo access has expired.',
          ),
        ),
      );
    });
  });

  group('S8-1a Forced Password Change Gate & Screen', () {
    late MockAuthRepository mockRepo;

    setUp(() {
      mockRepo = MockAuthRepository();
      when(() => mockRepo.currentAccessToken).thenReturn('tok_1');
      when(() => mockRepo.restoreSession()).thenAnswer((_) async => null);
      when(() => mockRepo.logout()).thenAnswer((_) async {});
    });

    testWidgets('must_change_password=true lands on ChangePasswordScreen and Home is not reachable',
        (tester) async {
      const flaggedSession = UserSession(
        accessToken: 'tok_1',
        username: 'amc_tech_1',
        userId: 42,
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
        isContractStaff: true,
        mustChangePassword: true,
      );
      when(() => mockRepo.restoreSession()).thenAnswer((_) async => flaggedSession);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
          child: const GssmsApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });

    testWidgets('successful password change stores new tokens and reaches HomeScreen',
        (tester) async {
      const flaggedSession = UserSession(
        accessToken: 'tok_1',
        username: 'amc_tech_1',
        userId: 42,
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
        isContractStaff: true,
        mustChangePassword: true,
      );
      const clearedSession = UserSession(
        accessToken: 'tok_2',
        username: 'amc_tech_1',
        userId: 42,
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
        isContractStaff: true,
        mustChangePassword: false,
      );
      when(() => mockRepo.restoreSession()).thenAnswer((_) async => flaggedSession);
      when(
        () => mockRepo.changeOwnPassword(
          currentPassword: 'TempPass123!',
          newPassword: 'NewStrongPass123!',
        ),
      ).thenAnswer((_) async => clearedSession);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
          child: const GssmsApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('change_pw_current_field')), 'TempPass123!');
      await tester.enterText(
          find.byKey(const Key('change_pw_new_field')), 'NewStrongPass123!');
      await tester.enterText(
          find.byKey(const Key('change_pw_confirm_field')), 'NewStrongPass123!');
      await tester.tap(find.byKey(const Key('change_pw_submit_button')));
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.changeOwnPassword(
          currentPassword: 'TempPass123!',
          newPassword: 'NewStrongPass123!',
        ),
      ).called(1);
      expect(find.byType(ChangePasswordScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
    });

    testWidgets('server validation error is displayed verbatim on ChangePasswordScreen',
        (tester) async {
      const flaggedSession = UserSession(
        accessToken: 'tok_1',
        username: 'amc_tech_1',
        userId: 42,
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
        isContractStaff: true,
        mustChangePassword: true,
      );
      when(() => mockRepo.restoreSession()).thenAnswer((_) async => flaggedSession);
      when(
        () => mockRepo.changeOwnPassword(
          currentPassword: 'WrongPass!',
          newPassword: 'NewStrongPass123!',
        ),
      ).thenThrow(const AuthException('Current password is incorrect.'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [authRepositoryProvider.overrideWithValue(mockRepo)],
          child: const GssmsApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('change_pw_current_field')), 'WrongPass!');
      await tester.enterText(
          find.byKey(const Key('change_pw_new_field')), 'NewStrongPass123!');
      await tester.enterText(
          find.byKey(const Key('change_pw_confirm_field')), 'NewStrongPass123!');
      await tester.tap(find.byKey(const Key('change_pw_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Current password is incorrect.'), findsOneWidget);
      expect(find.byType(ChangePasswordScreen), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
    });
  });

  group('D117 UserProfileScreen Password Change Routing', () {
    late MockAuthRepository mockRepo;
    late Directory testDir;

    const profile = UserProfile(
      id: 42,
      username: 'amc_tech_1',
      role: 'MAINTENANCE_STAFF',
      email: 'tech@sr-electricals.com',
      phoneNumber: '9876543210',
      designation: 'AMC Tech',
    );

    setUp(() {
      testDir = Directory.systemTemp.createTempSync('s8_1a_profile_');
      mockRepo = MockAuthRepository();
      when(() => mockRepo.getProfile()).thenAnswer((_) async => profile);
    });

    tearDown(() {
      if (testDir.existsSync()) testDir.deleteSync(recursive: true);
    });

    testWidgets('cs=true uses POST auth/change-password/ via changeOwnPassword', (tester) async {
      const contractSession = UserSession(
        accessToken: 'tok_1',
        username: 'amc_tech_1',
        userId: 42,
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
        isContractStaff: true,
      );
      when(() => mockRepo.currentSession).thenReturn(contractSession);
      when(
        () => mockRepo.changeOwnPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
        ),
      ).thenAnswer((_) async => contractSession.copyWith(accessToken: 'tok_2'));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(mockRepo),
            profilePhotoCacheProvider.overrideWithValue(
              ProfilePhotoCache(baseUrl: 'http://localhost:8000', storageDir: testDir),
            ),
          ],
          child: const MaterialApp(home: UserProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('profile_current_password_field')), 'OldPass123!');
      await tester.enterText(
          find.byKey(const Key('profile_new_password_field')), 'NewPass456!');
      await tester.enterText(
          find.byKey(const Key('profile_confirm_password_field')), 'NewPass456!');
      await tester.ensureVisible(
          find.byKey(const Key('profile_update_password_button')));
      await tester.tap(find.byKey(const Key('profile_update_password_button')));
      await tester.pumpAndSettle();

      verify(
        () => mockRepo.changeOwnPassword(
          currentPassword: 'OldPass123!',
          newPassword: 'NewPass456!',
        ),
      ).called(1);
      verifyNever(() => mockRepo.changePassword(any()));
      expect(find.text('Password changed successfully.'), findsOneWidget);
    });

    testWidgets('departmental user (cs=false) keeps PATCH users/{id}/ via changePassword',
        (tester) async {
      const deptSession = UserSession(
        accessToken: 'tok_1',
        username: 'dept_tech',
        userId: 7,
        primaryRole: AuthRole.maintenanceStaff,
        roles: [AuthRole.maintenanceStaff],
        permissions: ['maintenance.view'],
        isContractStaff: false,
      );
      when(() => mockRepo.currentSession).thenReturn(deptSession);
      when(() => mockRepo.changePassword('NewPass456!')).thenAnswer((_) async {});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(mockRepo),
            profilePhotoCacheProvider.overrideWithValue(
              ProfilePhotoCache(baseUrl: 'http://localhost:8000', storageDir: testDir),
            ),
          ],
          child: const MaterialApp(home: UserProfileScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('profile_current_password_field')), findsNothing);
      await tester.enterText(
          find.byKey(const Key('profile_new_password_field')), 'NewPass456!');
      await tester.enterText(
          find.byKey(const Key('profile_confirm_password_field')), 'NewPass456!');
      await tester.ensureVisible(
          find.byKey(const Key('profile_update_password_button')));
      await tester.tap(find.byKey(const Key('profile_update_password_button')));
      await tester.pumpAndSettle();

      verify(() => mockRepo.changePassword('NewPass456!')).called(1);
      verifyNever(
        () => mockRepo.changeOwnPassword(
          currentPassword: any(named: 'currentPassword'),
          newPassword: any(named: 'newPassword'),
        ),
      );
      expect(find.text('Password changed successfully.'), findsOneWidget);
    });
  });
}
