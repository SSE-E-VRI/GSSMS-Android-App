import 'package:equatable/equatable.dart';
import '../../domain/models/user_session.dart';

sealed class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading([this.message]);
  final String? message;

  @override
  List<Object?> get props => [message];
}

class Unauthenticated extends AuthState {
  const Unauthenticated();
}

class OtpRequired extends AuthState {
  const OtpRequired({
    required this.username,
    this.errorMessage,
    this.isSubmitting = false,
  });

  final String username;
  final String? errorMessage;
  final bool isSubmitting;

  @override
  List<Object?> get props => [username, errorMessage, isSubmitting];

  @override
  String toString() => 'OtpRequired(username: $username, errorMessage: $errorMessage, isSubmitting: $isSubmitting)';
}

class Authenticated extends AuthState {
  const Authenticated(this.session);
  final UserSession session;

  @override
  List<Object?> get props => [session];
}

class AuthError extends AuthState {
  const AuthError(this.message, {this.code});
  final String message;
  final String? code;

  @override
  List<Object?> get props => [message, code];
}
