import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/features/auth/domain/models/user_profile.dart';

void main() {
  test('UserProfile.fromJson maps web user payload fields', () {
    final profile = UserProfile.fromJson(const {
      'id': 12,
      'username': 'srdee',
      'role': 'ADMIN',
      'email': 'srdee@sr.railnet.gov.in',
      'phone_number': '9876543210',
      'designation': 'SrDEE',
    });

    expect(profile.id, 12);
    expect(profile.username, 'srdee');
    expect(profile.role, 'ADMIN');
    expect(profile.email, 'srdee@sr.railnet.gov.in');
    expect(profile.phoneNumber, '9876543210');
    expect(profile.designation, 'SrDEE');
  });
}
