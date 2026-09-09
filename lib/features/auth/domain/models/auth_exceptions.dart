/// Base class for authentication exceptions.
class AuthException implements Exception {
  const AuthException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'AuthException: $message (code: $code)';
}

/// Thrown when username or password is invalid or user not found during login (HTTP 400).
class InvalidCredentialsException extends AuthException {
  const InvalidCredentialsException([super.message = 'Invalid username or password'])
      : super(code: 'INVALID_CREDENTIALS');
}

/// Thrown when account is disabled.
class AccountDisabledException extends AuthException {
  const AccountDisabledException([super.message = 'This account is disabled.'])
      : super(code: 'ACCOUNT_DISABLED');
}

/// Thrown when 2FA TOTP is required to complete login.
class TwoFactorRequiredException extends AuthException {
  const TwoFactorRequiredException([super.message = 'Two-factor authentication code required'])
      : super(code: '2FA_REQUIRED');
}

/// Thrown when the submitted 2FA or OTP code is invalid.
class InvalidOtpException extends AuthException {
  const InvalidOtpException([
    super.message = 'Invalid 2FA code',
    this.attemptsRemaining,
  ]) : super(code: 'INVALID_OTP');

  final int? attemptsRemaining;
}

/// Thrown when maximum OTP verification attempts (5) are exceeded (HTTP 429 code: OTP_LOCKED_OUT).
class OtpLockoutException extends AuthException {
  const OtpLockoutException([
    super.message =
        'Too many incorrect attempts. Please request a new OTP and try again later.',
  ]) : super(code: 'OTP_LOCKED_OUT');
}

/// Thrown when 2FA rate limit is exceeded.
class RateLimitExceededException extends AuthException {
  const RateLimitExceededException([super.message = 'Too many attempts. Please try again later.'])
      : super(code: 'RATE_LIMIT_EXCEEDED');
}

/// Thrown when temporary / guest demo access has expired (HTTP 401 code: GUEST_EXPIRED).
class GuestExpiredException extends AuthException {
  const GuestExpiredException([super.message = 'Demo access has expired.'])
      : super(code: 'GUEST_EXPIRED');
}

/// Thrown when credentials or token are expired or invalid (HTTP 401).
class UnauthorizedException extends AuthException {
  const UnauthorizedException([super.message = 'Unauthorized or session expired.'])
      : super(code: 'UNAUTHORIZED');
}

/// Thrown when permission is denied (HTTP 403).
class ForbiddenException extends AuthException {
  const ForbiddenException([super.message = 'You do not have permission to perform this action.'])
      : super(code: 'FORBIDDEN');
}

/// Thrown on network or communication failures.
class NetworkAuthException extends AuthException {
  const NetworkAuthException([super.message = 'Network connection failed. Please check your connectivity.'])
      : super(code: 'NETWORK_ERROR');
}
