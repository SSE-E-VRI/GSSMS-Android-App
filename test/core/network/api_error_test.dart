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
      userFacingError(_response(
          403, {'detail': 'You do not have permission to view users.'})),
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

  group('S2 §24.1 standard conflict bodies', () {
    test('PM_PENDING_EXISTS names the blocking ticket', () {
      final e = _response(409, {
        'error': 'Another PM Job Work for this obligation is still open.',
        'code': 'PM_PENDING_EXISTS',
        'existing_ticket': 'WO-2026-0142',
        'blocking_work_order': {
          'id': 812,
          'ticket_number': 'WO-2026-0142',
          'status': 'IN_PROGRESS',
          'schedule_id': 311,
        },
        'pending_request': null,
      });
      expect(
        userFacingError(e),
        'Another PM Job Work for this obligation is still open. (WO-2026-0142)',
      );
      expect(conflictCode(e.response?.data), 'PM_PENDING_EXISTS');
      expect(blockingTicket(e.response?.data), 'WO-2026-0142');
    });

    test('blocking ticket falls back to existing_ticket', () {
      expect(
        blockingTicket({
          'code': 'PM_PENDING_EXISTS',
          'existing_ticket': 'WO-2026-0042',
          'blocking_work_order': null,
          'pending_request': null,
        }),
        'WO-2026-0042',
      );
    });

    test('PM_USE_SCHEDULE_CONVERSION code parses', () {
      final data = {
        'error': 'Preventive maintenance for an assigned template must be '
            'created by converting its schedule.',
        'code': 'PM_USE_SCHEDULE_CONVERSION',
        'blocking_work_order': null,
        'pending_request': null,
      };
      expect(conflictCode(data), 'PM_USE_SCHEDULE_CONVERSION');
      expect(blockingTicket(data), isNull);
      expect(userFacingError(_response(409, data)),
          contains('converting its schedule'));
    });

    test('structured fields never leak as field messages', () {
      // Without the _nonFieldKeys guard, serverMessage would render
      // "Blocking Work Order: ..." from the nested map when `error` is
      // absent; it must fall back to the generic conflict text instead.
      final e = _response(409, {
        'code': 'PM_PENDING_EXISTS',
        'blocking_work_order': {'ticket_number': 'WO-1'},
        'pending_request': null,
      });
      expect(userFacingError(e), isNot(contains('Blocking Work Order')));
    });

    test('conflictCode handles legacy and absent codes', () {
      expect(conflictCode({'error': 'x'}), isNull);
      expect(conflictCode(null), isNull);
      expect(
          conflictCode({
            'code': ['PM_PENDING_EXISTS']
          }),
          'PM_PENDING_EXISTS');
    });

    test('409 APPROVAL_PENDING includes approval request type or request_type',
        () {
      final e1 = _response(409, {
        'error': 'An approval request is pending for this occurrence.',
        'code': 'APPROVAL_PENDING',
        'pending_request': {'type': 'SKIP'},
      });
      expect(userFacingError(e1), contains('(approval: SKIP)'));

      final e2 = _response(409, {
        'error': 'An approval request is pending for this occurrence.',
        'code': 'APPROVAL_PENDING',
        'pending_request': {'request_type': 'SKIP'},
      });
      expect(userFacingError(e2), contains('(approval: SKIP)'));
    });
  });
}
