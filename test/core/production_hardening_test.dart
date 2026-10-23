import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:gssms_mobile/core/config/app_config.dart';
import 'package:gssms_mobile/core/database/local_cache_service.dart';
import 'package:gssms_mobile/core/storage/secure_storage_service.dart';
import 'package:gssms_mobile/core/widgets/protected_network_image.dart';
import 'package:gssms_mobile/features/auth/data/auth_api_service.dart';
import 'package:gssms_mobile/features/auth/data/auth_repository.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_tokens.dart';
import 'package:gssms_mobile/features/auth/domain/models/auth_exceptions.dart';
import 'package:gssms_mobile/features/work_orders/data/evidence_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

class _Api extends Mock implements AuthApiService {}

class _Storage extends Mock implements FlutterSecureStorage {}

class _Prefs extends Mock implements SharedPreferences {}

class _SuspendedStorage extends InMemorySecureStorageService {
  final started = Completer<void>();
  final release = Completer<void>();
  bool suspend = true;
  @override
  Future<void> saveRefreshToken(String token) async {
    if (suspend) {
      started.complete();
      await release.future;
    }
    await super.saveRefreshToken(token);
  }
}

String _jwt(int user) =>
    '${base64Url.encode(utf8.encode('{}'))}.${base64Url.encode(utf8.encode(jsonEncode({
          'user_id': user,
          'username': 'test',
          'exp': 4102444800
        })))}.';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Production media origin policy', () {
    const config = AppConfig(baseUrl: 'https://backend.example');
    test('accepts relative and exact origin only', () {
      expect(trustedMediaUri('/media/photo.jpg', config).toString(),
          'https://backend.example/media/photo.jpg');
      expect(trustedMediaUri('https://backend.example:443/media/p.jpg', config),
          isNotNull);
      for (final url in [
        'https://evil.example/p.jpg',
        '//evil.example/p.jpg',
        'https://sub.backend.example/p.jpg',
        'http://backend.example/p.jpg',
        'https://backend.example:444/p.jpg',
        'https://user@backend.example/p.jpg',
        'file:///etc/passwd',
        'https://[',
        ''
      ]) {
        expect(trustedMediaUri(url, config), isNull, reason: url);
      }
    });
    test('allows dev transport only for the configured origin', () {
      const dev = AppConfig(
          baseUrl: 'http://10.0.2.2:8000', environment: AppEnvironment.dev);
      expect(trustedMediaUri('/media/p.jpg', dev), isNotNull);
      expect(trustedMediaUri('http://10.0.2.2:8001/p.jpg', dev), isNull);
    });
    test('redirect is rejected without contacting its destination', () async {
      final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final destination =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var destinationRequests = 0;
      String? receivedAuthorization;
      final originSubscription = origin.listen((request) async {
        receivedAuthorization = request.headers.value('authorization');
        request.response.statusCode = HttpStatus.found;
        request.response.headers
            .set('location', 'http://127.0.0.1:${destination.port}/stolen');
        await request.response.close();
      });
      final destinationSubscription = destination.listen((request) async {
        destinationRequests++;
        await request.response.close();
      });
      try {
        final provider = ProtectedMediaImage(
            Uri.parse('http://127.0.0.1:${origin.port}/photo'), 'test-token');
        await expectLater(
            HttpOverrides.runWithHttpOverrides(
                () => provider.loadBytes(), _RealHttpOverrides()),
            throwsA(isA<HttpException>()));
        expect(receivedAuthorization, 'Bearer test-token');
        expect(destinationRequests, 0);
      } finally {
        await origin.close(force: true);
        await destination.close(force: true);
        await originSubscription.cancel();
        await destinationSubscription.cancel();
      }
    });
    test('image cache separates identities and rotated tokens', () {
      final uri = Uri.parse('https://backend.example/media/p.jpg');
      expect(
          ProtectedMediaImage(uri, 'a'), isNot(ProtectedMediaImage(uri, 'b')));
      expect(
          ProtectedMediaImage(uri, 'a'), isNot(ProtectedMediaImage(uri, null)));
    });
  });

  group('Release environment checks', () {
    test('rejects flavor mismatch for every environment', () {
      for (final env in AppEnvironment.values) {
        for (final flavor in ['dev', 'staging', 'prod']) {
          if (env.name == flavor) {
            expect(
                () => AppConfig.validateFlavor(flavor, env), returnsNormally);
          } else {
            expect(() => AppConfig.validateFlavor(flavor, env),
                throwsArgumentError);
          }
        }
      }
    });
    test('rejects insecure and local release endpoints', () {
      for (final env in [AppEnvironment.prod, AppEnvironment.staging]) {
        for (final url in [
          'http://backend.example',
          'https://localhost',
          'https://127.0.0.1',
          'https://10.0.2.2',
          'ftp://backend.example',
          'https://user:pass@backend.example',
          'garbage'
        ]) {
          expect(() => AppConfig.validateBaseUrl(url, env), throwsArgumentError,
              reason: url);
        }
        expect(() => AppConfig.validateBaseUrl('https://backend.example', env),
            returnsNormally);
      }
    });
  });

  group('Session race regressions', () {
    test('late restore cannot undo logout or rotate stored token', () async {
      final api = _Api();
      final storage = InMemorySecureStorageService();
      await storage.saveRefreshToken('old');
      final response = Completer<AuthTokens>();
      final entered = Completer<void>();
      when(() => api.refreshToken('old')).thenAnswer((_) {
        entered.complete();
        return response.future;
      });
      final repo = AuthRepository(apiService: api, secureStorage: storage);
      final restoring = repo.restoreSession();
      await entered.future;
      await repo.logout();
      response
          .complete(AuthTokens(accessToken: _jwt(1), refreshToken: 'rotated'));
      expect(await restoring, isNull);
      expect(repo.currentAccessToken, isNull);
      expect(await storage.getRefreshToken(), isNull);
    });
    test('logout waits for suspended token write and clears it afterwards',
        () async {
      final api = _Api();
      final storage = _SuspendedStorage();
      when(() => api.login(username: 'test', password: 'password')).thenAnswer(
          (_) async => AuthTokens(accessToken: _jwt(1), refreshToken: 'new'));
      final repo = AuthRepository(apiService: api, secureStorage: storage);
      final login = repo.login(username: 'test', password: 'password');
      final rejected =
          expectLater(login, throwsA(isA<UnauthorizedException>()));
      await storage.started.future;
      final logout = repo.logout();
      storage.release.complete();
      await logout;
      await rejected;
      expect(repo.currentSession, isNull);
      expect(await storage.getRefreshToken(), isNull);
    });
    for (final operation in ['restore', 'refresh']) {
      test('$operation token write cannot survive concurrent logout', () async {
        final api = _Api();
        final storage = _SuspendedStorage()..suspend = false;
        await storage.saveRefreshToken('old');
        storage.suspend = true;
        when(() => api.refreshToken('old')).thenAnswer((_) async =>
            AuthTokens(accessToken: _jwt(1), refreshToken: 'rotated'));
        final repo = AuthRepository(apiService: api, secureStorage: storage);
        final pending = operation == 'restore'
            ? repo.restoreSession()
            : repo.refreshToken();
        await storage.started.future;
        final logout = repo.logout();
        storage.release.complete();
        await logout;
        expect(await pending, isNull);
        expect(repo.currentSession, isNull);
        expect(await storage.getRefreshToken(), isNull);
      });
    }
    test('transient refresh failure preserves the saved refresh token',
        () async {
      final api = _Api();
      final storage = InMemorySecureStorageService();
      await storage.saveRefreshToken('retained');
      when(() => api.refreshToken('retained')).thenThrow(StateError('offline'));
      final repo = AuthRepository(apiService: api, secureStorage: storage);
      await expectLater(repo.refreshToken(), throwsStateError);
      expect(await storage.getRefreshToken(), 'retained');
    });
    test('new login supersedes startup restore', () async {
      final api = _Api();
      final storage = InMemorySecureStorageService();
      await storage.saveRefreshToken('old');
      final response = Completer<AuthTokens>();
      final entered = Completer<void>();
      when(() => api.refreshToken('old')).thenAnswer((_) {
        entered.complete();
        return response.future;
      });
      when(() => api.login(username: 'test', password: 'password')).thenAnswer(
          (_) async => AuthTokens(accessToken: _jwt(2), refreshToken: 'user2'));
      final repo = AuthRepository(apiService: api, secureStorage: storage);
      final restoring = repo.restoreSession();
      await entered.future;
      await repo.login(username: 'test', password: 'password');
      response
          .complete(AuthTokens(accessToken: _jwt(1), refreshToken: 'user1'));
      expect(await restoring, isNull);
      expect(repo.currentSession?.userId, 2);
      expect(await storage.getRefreshToken(), 'user2');
    });
  });

  group('Credential persistence failures', () {
    test('transient storage read does not masquerade as an absent token',
        () async {
      final storage = _Storage();
      when(() => storage.read(key: any(named: 'key')))
          .thenThrow(StateError('locked'));
      await expectLater(SecureStorageService(storage).getRefreshToken(),
          throwsA(isA<CredentialStorageException>()));
      verifyNever(() => storage.delete(key: any(named: 'key')));
      verifyNever(() => storage.deleteAll());
    });
    test('default Android options do not wipe storage on read errors', () {
      expect(
          SecureStorageService.defaultAndroidOptions.toMap()['resetOnError'],
          'false');
    });
    test('failed delete is surfaced and restart refuses stale token', () async {
      final storage = _Storage();
      when(() => storage.delete(key: any(named: 'key')))
          .thenThrow(StateError('disk failure'));
      when(() => storage.deleteAll()).thenThrow(StateError('disk failure'));
      final service = SecureStorageService(storage);
      await expectLater(service.clearTokens(), throwsStateError);
      expect(await SecureStorageService(storage).getRefreshToken(), isNull);
      verifyNever(() => storage.read(key: any(named: 'key')));
    });
    test('failed write retry is surfaced and blocks stale restoration',
        () async {
      final storage = _Storage();
      when(() =>
              storage.write(key: any(named: 'key'), value: any(named: 'value')))
          .thenThrow(StateError('disk failure'));
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});
      final service = SecureStorageService(storage);
      await expectLater(service.saveRefreshToken('new'), throwsStateError);
      expect(await service.getRefreshToken(), isNull);
    });
  });

  group('Offline persistence failures', () {
    test('failed primary save reloads cache and rejects acknowledgment',
        () async {
      final prefs = _Prefs();
      when(() => prefs.setString(any(), any())).thenAnswer((_) async => false);
      when(() => prefs.reload()).thenAnswer((_) async {});
      await expectLater(
          LocalCacheService(prefs).saveOutboxCommands([]), throwsStateError);
      verify(() => prefs.reload()).called(1);
    });
    test('failed removal is surfaced after attempting all keys', () async {
      final prefs = _Prefs();
      when(() => prefs.getKeys())
          .thenReturn({'gssms_cache_a', 'gssms_cache_b', 'other'});
      when(() => prefs.remove(any())).thenAnswer((_) async => false);
      when(() => prefs.reload()).thenAnswer((_) async {});
      await expectLater(
          LocalCacheService(prefs).clearAllCache(), throwsStateError);
      verify(() => prefs.remove('gssms_cache_a')).called(1);
      verify(() => prefs.remove('gssms_cache_b')).called(1);
      verifyNever(() => prefs.remove('other'));
    });
  });

  group('Evidence normalization', () {
    test('output JPEG removes EXIF metadata', () {
      final image = img.Image(width: 4, height: 4);
      image.exif.imageIfd['Make'] = 'private-device';
      final original = img.encodeJpg(image);
      expect(img.decodeJpg(original)!.exif.imageIfd['Make'], isNotNull);
      final clean = normalizeEvidenceJpeg(Uint8List.fromList(original))!;
      expect(img.decodeJpg(clean)!.exif.imageIfd['Make'], isNull);
    });
    test('rejects excessive JPEG dimensions before pixel allocation', () {
      final data =
          Uint8List.fromList(img.encodeJpg(img.Image(width: 4, height: 4)));
      for (var i = 0; i < data.length - 9; i++) {
        if (data[i] == 0xff && data[i + 1] == 0xc0) {
          data[i + 5] = 0xff;
          data[i + 6] = 0xff;
          data[i + 7] = 0xff;
          data[i + 8] = 0xff;
          break;
        }
      }
      expect(normalizeEvidenceJpeg(data), isNull);
    });
    test('decode failure rejects original bytes instead of copying them',
        () async {
      final dir = await Directory.systemTemp.createTemp('gssms_sanitize_');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => dir.path);
      try {
        final source = File('${dir.path}/source.jpg');
        await source.writeAsBytes([1, 2, 3, 4]);
        final service = EvidenceService()
          ..processImageOverride = (_) async => null;
        await expectLater(
            service.persist(source.path, kind: EvidenceKind.proof),
            throwsA(isA<FileSystemException>()));
        expect(Directory('${dir.path}/gssms_evidence').listSync(), isEmpty);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await dir.delete(recursive: true);
      }
    });
  });
}
