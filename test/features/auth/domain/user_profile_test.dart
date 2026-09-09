import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_role.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_profile.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_session.dart';

void main() {
  group('UserProfile', () {
    test('UserProfile.fromJson maps web user payload fields including profile_picture', () {
      final profile = UserProfile.fromJson(const {
        'id': 12,
        'username': 'srdee',
        'role': 'ADMIN',
        'email': 'srdee@sr.railnet.gov.in',
        'phone_number': '9876543210',
        'designation': 'SrDEE',
        'profile_picture': '/media/profile_pictures/srdee.jpg',
      });

      expect(profile.id, 12);
      expect(profile.username, 'srdee');
      expect(profile.role, 'ADMIN');
      expect(profile.email, 'srdee@sr.railnet.gov.in');
      expect(profile.phoneNumber, '9876543210');
      expect(profile.designation, 'SrDEE');
      expect(profile.profilePicture, '/media/profile_pictures/srdee.jpg');
    });

    test('UserProfile.fromJson handles null profile_picture', () {
      final profile = UserProfile.fromJson(const {
        'id': 12,
        'username': 'srdee',
        'profile_picture': null,
      });

      expect(profile.profilePicture, isNull);
    });

    test('UserProfile.copyWith updates and clears profilePicture', () {
      const initial = UserProfile(
        id: 1,
        username: 'user1',
        profilePicture: '/media/photo.jpg',
      );

      final updated = initial.copyWith(profilePicture: '/media/photo2.jpg');
      expect(updated.profilePicture, '/media/photo2.jpg');

      final cleared = updated.copyWith(clearProfilePicture: true);
      expect(cleared.profilePicture, isNull);
    });
  });

  group('UserSession', () {
    test('UserSession.fromClaims maps profile_picture claim', () {
      final session = UserSession.fromClaims(const {
        'username': 'technician1',
        'role': 'MAINTENANCE_STAFF',
        'profile_picture': '/media/profile_pictures/tech.jpg',
      }, 'dummy_token');

      expect(session.profilePicture, '/media/profile_pictures/tech.jpg');
    });

    test('UserSession.fromClaims handles empty or null profile_picture', () {
      final session1 = UserSession.fromClaims(const {
        'username': 'technician1',
        'role': 'MAINTENANCE_STAFF',
        'profile_picture': '',
      }, 'dummy_token');
      expect(session1.profilePicture, isNull);

      final session2 = UserSession.fromClaims(const {
        'username': 'technician1',
        'role': 'MAINTENANCE_STAFF',
      }, 'dummy_token');
      expect(session2.profilePicture, isNull);
    });

    test('UserSession.copyWith updates and clears profilePicture', () {
      const initial = UserSession(
        accessToken: 'token',
        username: 'user1',
        primaryRole: AuthRole.maintenanceStaff,
        profilePicture: '/media/pic1.jpg',
      );

      final updated = initial.copyWith(profilePicture: '/media/pic2.jpg');
      expect(updated.profilePicture, '/media/pic2.jpg');

      final cleared = updated.copyWith(clearProfilePicture: true);
      expect(cleared.profilePicture, isNull);
    });
  });
}

