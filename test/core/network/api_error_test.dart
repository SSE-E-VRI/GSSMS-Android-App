import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/network/api_error.dart';

DioException _response(int status, Object? data) {
  final options = RequestOptions(path: '/api/v1/complaints/');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: data),
  );
}

DioException _transport(DioExceptionType type) => DioException(
      requestOptions: RequestOptions(path: '/api/v1/complaints/'),
      type: type,
    );

void main() {
  group('userFacingError never leaks technical detail', () {
    final cases = <String, Object>{
      'connection error': _transport(DioExceptionType.connectionError),
      'timeout': _transport(DioExceptionType.receiveTimeout),
      '500 HTML page': _response(502, '<html><body>Bad Gateway</body></html>'),
      '500 JSON': _response(500, {'detail': 'IntegrityError at /api/v1/…'}),
      'unknown without response': _transport(DioExceptionType.unknown),
      'type error from malformed payload': TypeError(),
      'format exception': const FormatException('Unexpected character'),
    };
    cases.forEach((name, error) {
      test(name, () {
        final message = userFacingError(error);
        expect(message, isNot(contains('DioException')));
        expect(message, isNot(contains('RequestOptions')));
        expect(message, isNot(contains('/api/')));
        expect(message, isNot(contains('<')));
        expect(message, isNot(contains('subtype')));
        expect(message.trim(), isNotEmpty);
      });
    });
  });

  test('network and timeout failures get connection guidance', () {
    expect(userFacingError(_transport(DioExceptionType.connectionError)),
        kNetworkErrorMessage);
    expect(userFacingError(_transport(DioExceptionType.connectionTimeout)),
        kTimeoutErrorMessage);
  });

  test('400 surfaces the DRF field message with a readable field name', () {
    final e = _response(400, {
      'inspection_date': ['This field is required.'],
    });
    expect(userFacingError(e), 'Inspection date: This field is required.');
    expect(classifyApiFailure(e), ApiFailureKind.validation);
  });

  test('400 prefers detail / error / non_field_errors', () {
    expect(userFacingError(_response(400, {'detail': 'Invalid status.'})),
        'Invalid status.');
    expect(userFacingError(_response(400, {'error': 'Remarks too short.'})),
        'Remarks too short.');
    expect(
      userFacingError(_response(400, {
        'non_field_errors': ['Station must match the infrastructure.'],
      })),
      'Station must match the infrastructure.',
    );
  });

  test('400 without a readable body falls back to the validation message', () {
    expect(userFacingError(_response(400, null)), kValidationErrorMessage);
  });

  test('401 is a session message, not the token error text', () {
    final e = _response(401, {
      'detail': 'Given token not valid for any token type',
      'code': 'token_not_valid',
    });
    expect(userFacingError(e), kAuthErrorMessage);
    expect(classifyApiFailure(e), ApiFailureKind.auth);
  });

  test('403 keeps the server permission detail when present', () {
    expect(
      userFacingError(
          _response(403, {'detail': 'You do not have permission to view users.'})),
      'You do not have permission to view users.',
    );
    expect(userFacingError(_response(403, null)), kPermissionErrorMessage);
  });

  test('404 uses the scope-aware message', () {
    expect(userFacingError(_response(404, {'detail': 'Not found.'})),
        kNotFoundErrorMessage);
  });

  test('409 conflict includes the existing ticket', () {
    final e = _response(409, {
      'error': 'A Job Work already exists for this complaint.',
      'existing_ticket': 'WO-2026-0042',
    });
    expect(userFacingError(e),
        'A Job Work already exists for this complaint. (WO-2026-0042)');
    expect(classifyApiFailure(e), ApiFailureKind.conflict);
  });

  test('429 and 5xx use fixed messages', () {
    expect(userFacingError(_response(429, {'detail': 'Throttled.'})),
        kRateLimitErrorMessage);
    expect(userFacingError(_response(503, {'detail': 'down'})),
        kServerErrorMessage);
  });

  test('business exceptions keep their text without the Dart prefix', () {
    expect(userFacingError(Exception('A technician must be assigned')),
        'A technician must be assigned');
  });
}
