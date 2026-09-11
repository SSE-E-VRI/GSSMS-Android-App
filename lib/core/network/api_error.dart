import 'package:dio/dio.dart';

/// The failure classes SSOT §42 requires clients to keep distinct.
enum ApiFailureKind {
  network,
  validation,
  auth,
  permission,
  notFound,
  conflict,
  rateLimited,
  server,
  unexpected,
}

/// Classifies [error] per SSOT §42 (network / 400 / 401 / 403 / 404 / 409 /
/// 429 / 5xx). Non-HTTP errors are [ApiFailureKind.unexpected].
ApiFailureKind classifyApiFailure(Object error) {
  if (error is! DioException) return ApiFailureKind.unexpected;
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
    case DioExceptionType.connectionError:
      return ApiFailureKind.network;
    default:
      break;
  }
  final status = error.response?.statusCode;
  if (status == null) return ApiFailureKind.network;
  if (status == 401) return ApiFailureKind.auth;
  if (status == 403) return ApiFailureKind.permission;
  if (status == 404) return ApiFailureKind.notFound;
  if (status == 409) return ApiFailureKind.conflict;
  if (status == 429) return ApiFailureKind.rateLimited;
  if (status >= 500) return ApiFailureKind.server;
  if (status >= 400) return ApiFailureKind.validation;
  return ApiFailureKind.unexpected;
}

const String kNetworkErrorMessage =
    'Unable to connect. Please check your network and try again.';
const String kTimeoutErrorMessage =
    'The server took too long to respond. Please check your connection and try again.';
const String kValidationErrorMessage = 'Please correct the highlighted fields.';
const String kAuthErrorMessage =
    'Your session has expired. Please sign in again.';
const String kPermissionErrorMessage =
    'You do not have permission to perform this action.';
const String kNotFoundErrorMessage =
    'This record is no longer available, or is outside your organisation scope.';
const String kConflictErrorMessage =
    'This record was changed by another user. Refresh and try again.';
const String kRateLimitErrorMessage =
    'Too many requests. Please wait a moment and try again.';
const String kServerErrorMessage =
    'The service is temporarily unavailable. Please try again.';
const String kUnexpectedResponseMessage =
    'The server sent an unexpected response. Please try again.';

/// Turns any error into a concise message safe to show a production user.
///
/// SSOT §6: never show `DioException`, `RequestOptions`, stack traces, URLs or
/// raw HTML bodies. 4xx responses surface the server's own human-readable
/// message (`detail` / `error` / first field error) because the backend writes
/// those for users; 5xx bodies are never shown.
String userFacingError(Object error) {
  if (error is DioException) return _dioMessage(error);

  // Malformed/unexpected payloads surface as Dart type/parse errors — their
  // text ("type 'Null' is not a subtype of …") means nothing to a user.
  if (error is TypeError ||
      error is FormatException ||
      error is NoSuchMethodError ||
      error is RangeError) {
    return kUnexpectedResponseMessage;
  }

  // Repository/business exceptions carry human-authored text; drop Dart's
  // "Exception: " prefix so it reads as a sentence.
  final text = error.toString();
  const prefix = 'Exception: ';
  final cleaned = text.startsWith(prefix) ? text.substring(prefix.length) : text;
  return cleaned.trim().isEmpty ? kUnexpectedResponseMessage : cleaned.trim();
}

String _dioMessage(DioException error) {
  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return kTimeoutErrorMessage;
    case DioExceptionType.connectionError:
      return kNetworkErrorMessage;
    case DioExceptionType.cancel:
      return 'The request was cancelled.';
    case DioExceptionType.badCertificate:
      return 'A secure connection to the server could not be established.';
    default:
      break;
  }

  switch (classifyApiFailure(error)) {
    case ApiFailureKind.network:
      return kNetworkErrorMessage;
    case ApiFailureKind.auth:
      return kAuthErrorMessage;
    case ApiFailureKind.server:
      return kServerErrorMessage;
    case ApiFailureKind.rateLimited:
      return kRateLimitErrorMessage;
    case ApiFailureKind.permission:
      return serverMessage(error.response?.data) ?? kPermissionErrorMessage;
    case ApiFailureKind.notFound:
      return serverMessage(error.response?.data, allowDetail: false) ??
          kNotFoundErrorMessage;
    case ApiFailureKind.conflict:
      return _conflictMessage(error.response?.data);
    case ApiFailureKind.validation:
      return serverMessage(error.response?.data) ?? kValidationErrorMessage;
    case ApiFailureKind.unexpected:
      return kUnexpectedResponseMessage;
  }
}

String _conflictMessage(Object? data) {
  final base = serverMessage(data) ?? kConflictErrorMessage;
  if (data is Map) {
    final ticket = data['existing_ticket'];
    if (ticket is String && ticket.isNotEmpty && !base.contains(ticket)) {
      return '$base ($ticket)';
    }
  }
  return base;
}

/// Extracts the human-readable message from a DRF error body (SSOT §6):
/// `{"detail": …}`, `{"error": …}`, `{"non_field_errors": [...]}`,
/// `{"field": ["msg"]}` or `["msg"]`. Returns null when there is nothing a
/// user should read (HTML pages, empty bodies, oversized dumps).
///
/// [allowDetail] is false for 404s: DRF's stock "No X matches the given
/// query." is less useful than the scope-aware default.
String? serverMessage(Object? data, {bool allowDetail = true}) {
  if (data is Map) {
    for (final key in const ['error', 'detail', 'message']) {
      if (key == 'detail' && !allowDetail) continue;
      final value = _plain(data[key]);
      if (value != null) return value;
    }
    final nonField = _plain(data['non_field_errors']);
    if (nonField != null) return nonField;
    for (final entry in data.entries) {
      // Already considered above, or machine-readable metadata.
      if (_nonFieldKeys.contains(entry.key)) continue;
      final value = _plain(entry.value);
      if (value == null) continue;
      final field = _humanizeField(entry.key.toString());
      return field.isEmpty ? value : '$field: $value';
    }
    return null;
  }
  if (data is List) return _plain(data);
  if (data is String) return _plain(data);
  return null;
}

const _nonFieldKeys = {
  'error',
  'detail',
  'message',
  'non_field_errors',
  'code',
  'existing_ticket',
  'messages',
};

String? _plain(Object? value) {
  if (value is List) {
    for (final item in value) {
      final text = _plain(item);
      if (text != null) return text;
    }
    return null;
  }
  if (value is Map) return serverMessage(value);
  if (value is! String) return null;
  final text = value.trim();
  if (text.isEmpty || text.length > 300) return null;
  // An HTML error page (proxy 502, Django debug page) is not a message.
  if (text.startsWith('<') || text.contains('<html') || text.contains('Traceback')) {
    return null;
  }
  return text;
}

String _humanizeField(String key) {
  final words = key.replaceAll('_', ' ').trim();
  if (words.isEmpty) return '';
  return words[0].toUpperCase() + words.substring(1);
}
