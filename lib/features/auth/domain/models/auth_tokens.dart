import 'package:equatable/equatable.dart';

class AuthTokens extends Equatable {
  const AuthTokens({
    required this.accessToken,
    this.refreshToken,
    this.mustChangePassword = false,
  });

  final String accessToken;
  final String? refreshToken;
  final bool mustChangePassword;

  @override
  List<Object?> get props => [accessToken, refreshToken, mustChangePassword];
}
