import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/config/app_config.dart';
import 'package:gssms_mobile/core/network/certificate_pinning.dart';
import 'package:gssms_mobile/core/network/dio_client.dart';

// Self-signed test certificate (CN=pin.test), DER, base64.
const _certDerB64 =
    'MIIDMTCCAhmgAwIBAgIUa/u2LHz0rBbkfrIrTQexN4VRVNIwDQYJKoZIhvcNAQELBQAwKDERMA8GA1UEAwwIcGluLnRlc3QxEzARBgNVBAoMCkdTU01TIFRlc3QwHhcNMjYxMDIzMDk1NTM1WhcNMzYxMDIwMDk1NTM1WjAoMREwDwYDVQQDDAhwaW4udGVzdDETMBEGA1UECgwKR1NTTVMgVGVzdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALSRjPR3xkXWEgzRX2nA0hI/Pj034yOls4G97PU+K27e4UmrOIFybIDb9PKURqIv+tAjQdFMU4qGCIO8oyt/iKg7O4Kyq32m1s7id5WffHMfe0yRp8dvJF1Zfw7VY3G7l/mnxmge/2un4W2BnIg5EBE+GRRWkVSZo2MjWquOC2X50ZaKDQLfee515Zr71ynGeTrZx2QOG4xmU3KM1MYyQX4/ZvggARJSu41NRmZGT/HTCT6KPmRba+aYVCrEPK13YeYF19xAV3C86fai/+/NwpSDyNP6QyXXbAbATengion1Ax82OYmFQfn1JosxBh7H7F09NlS8RLX2sRgJYI4qj8UCAwEAAaNTMFEwHQYDVR0OBBYEFFzPI0CwR4cBwtT5ppAy9eXDrDCqMB8GA1UdIwQYMBaAFFzPI0CwR4cBwtT5ppAy9eXDrDCqMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcNAQELBQADggEBAJloDPklgvcRXBJ/sYNJMVwo8T1Qg4uLw24hwPKqkWLjmQuMTtrvtSXMFJoRfqYKPUmbO/c6bQwQZTYyrQm+ZO52dJNOXTIQKmwNyQZEIfQFve2qI2SwE7b6RvTN/7hUwLrHLcA2D8j57N9jQeGUgSyS7zLVeKmS7MG6XaOAg8ksvsNhhtyTjR6WVc4ww41TLKeeX5qZ48yQGhePF+VKkZVVtHPlpFh3WEROOuys4nD3Lr4QUWUzNkcKGm/ymPhvp+WFg33t1B6DuY8PtB7sdbQRNL8+vnBgKCex69VRq6eSUnbOlkx4lHWxFs8MMsJdS3Pm+rp2FIe69IL2W40dYa0=';

// Expected pin, computed with openssl (pubkey -> DER -> sha256 -> base64).
const _expectedPin = 'M69fHMsXEFzNO4/cIitXADrqhY40/Cvr4VxDi96dJeM=';

class _FakeCert implements X509Certificate {
  _FakeCert(this._der);
  final Uint8List _der;

  @override
  Uint8List get der => _der;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final der = base64.decode(_certDerB64);

  group('spkiMatches', () {
    test('extractSpki + pin equals the openssl-computed pin', () {
      expect(spkiPin(der), _expectedPin);
    });

    test('true when pin matches', () {
      expect(spkiMatches(_FakeCert(der), {_expectedPin}), isTrue);
    });

    test('true when one of several pins matches', () {
      final other = base64.encode(List<int>.filled(32, 7));
      expect(spkiMatches(_FakeCert(der), {other, _expectedPin}), isTrue);
    });

    test('false on mismatch', () {
      final other = base64.encode(List<int>.filled(32, 7));
      expect(spkiMatches(_FakeCert(der), {other}), isFalse);
    });

    test('false on null certificate', () {
      expect(spkiMatches(null, {_expectedPin}), isFalse);
    });

    test('false on empty pin set', () {
      expect(spkiMatches(_FakeCert(der), <String>{}), isFalse);
    });

    test('false on malformed or truncated DER', () {
      expect(spkiMatches(_FakeCert(Uint8List(0)), {_expectedPin}), isFalse);
      expect(
        spkiMatches(
            _FakeCert(Uint8List.fromList(der.sublist(0, 60))), {_expectedPin}),
        isFalse,
      );
      expect(
        spkiMatches(
            _FakeCert(Uint8List.fromList([0x04, 0x01, 0x00])), {_expectedPin}),
        isFalse,
      );
    });
  });

  group('DioClient pinning', () {
    Future<void> noop() async {}

    test('no pins keeps the default adapter (no certificate validation hook)',
        () {
      final dio = DioClient.create(
        config: const AppConfig(baseUrl: 'https://example.test'),
        tokenProvider: () => null,
        refreshTokenHandler: () async => null,
        onSessionExpired: noop,
      );
      final adapter = dio.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        expect(adapter.validateCertificate, isNull);
      }
    });

    test('with pins installs an IOHttpClientAdapter with validation', () {
      final dio = DioClient.create(
        config: const AppConfig(
          baseUrl: 'https://example.test',
          spkiPins: [_expectedPin],
        ),
        tokenProvider: () => null,
        refreshTokenHandler: () async => null,
        onSessionExpired: noop,
      );
      final adapter = dio.httpClientAdapter;
      expect(adapter, isA<IOHttpClientAdapter>());
      final validate = (adapter as IOHttpClientAdapter).validateCertificate;
      expect(validate, isNotNull);
      expect(validate!(_FakeCert(der), 'example.test', 443), isTrue);
      expect(validate(null, 'example.test', 443), isFalse);
    });
  });
}
