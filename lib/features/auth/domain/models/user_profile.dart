import 'package:equatable/equatable.dart';
import 'package:gssms_mobile/core/utils/json_parsing.dart';

/// Editable profile fields from `GET/PATCH /api/v1/users/{id}/`.
class UserProfile extends Equatable {
  const UserProfile({
    required this.id,
    required this.username,
    this.role = '',
    this.email = '',
    this.phoneNumber = '',
    this.designation = '',
  });

  final int id;
  final String username;
  final String role;
  final String email;
  final String phoneNumber;
  final String designation;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: asJsonInt(json['id']) ?? 0,
      username: asJsonString(json['username']) ?? '',
      role: asJsonString(json['role']) ?? '',
      email: asJsonString(json['email']) ?? '',
      phoneNumber: asJsonString(json['phone_number']) ?? '',
      designation: asJsonString(json['designation']) ?? '',
    );
  }

  @override
  List<Object?> get props => [id, username, role, email, phoneNumber, designation];
}
