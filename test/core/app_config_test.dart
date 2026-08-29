import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/config/app_config.dart';

void main() {
  group('AppEnvironment', () {
    test('fromString parses dev, staging, prod and handles fallbacks', () {
      expect(AppEnvironment.fromString('dev'), AppEnvironment.dev);
      expect(AppEnvironment.fromString('development'), AppEnvironment.dev);
      expect(AppEnvironment.fromString('DEV'), AppEnvironment.dev);

      expect(AppEnvironment.fromString('staging'), AppEnvironment.staging);
      expect(AppEnvironment.fromString('stage'), AppEnvironment.staging);
      expect(AppEnvironment.fromString('STAGING'), AppEnvironment.staging);

      expect(AppEnvironment.fromString('prod'), AppEnvironment.prod);
      expect(AppEnvironment.fromString('production'), AppEnvironment.prod);
      expect(AppEnvironment.fromString(null), AppEnvironment.prod);
      expect(AppEnvironment.fromString('invalid'), AppEnvironment.prod);
    });

    test('defaultBaseUrl returns correct URL per environment', () {
      expect(AppEnvironment.dev.defaultBaseUrl, 'http://10.0.2.2:8000');
      expect(AppEnvironment.staging.defaultBaseUrl, 'https://gssms-staging.share.zrok.io');
      expect(AppEnvironment.prod.defaultBaseUrl, 'https://gssms.share.zrok.io');
    });

    test('enableVerboseLogging is true for dev/staging and false for prod', () {
      expect(AppEnvironment.dev.enableVerboseLogging, isTrue);
      expect(AppEnvironment.staging.enableVerboseLogging, isTrue);
      expect(AppEnvironment.prod.enableVerboseLogging, isFalse);
    });

    test('enableCertPinning is true only for prod', () {
      expect(AppEnvironment.dev.enableCertPinning, isFalse);
      expect(AppEnvironment.staging.enableCertPinning, isFalse);
      expect(AppEnvironment.prod.enableCertPinning, isTrue);
    });
  });

  group('AppConfig', () {
    test('uses injected baseUrl and environment correctly', () {
      const config = AppConfig(
        baseUrl: 'https://custom.backend.org',
        environment: AppEnvironment.staging,
      );
      expect(config.baseUrl, 'https://custom.backend.org');
      expect(config.environment, AppEnvironment.staging);
      expect(config.isDev, isFalse);
      expect(config.isStaging, isTrue);
      expect(config.isProd, isFalse);
    });

    test('fromEnvironment returns default production configuration when unconfigured', () {
      final config = AppConfig.fromEnvironment();
      expect(config.baseUrl, AppConfig.defaultBaseUrl);
      expect(config.environment, AppEnvironment.prod);
      expect(config.isProd, isTrue);
    });

    test('constructs apiUri accurately with or without leading slash', () {
      const config = AppConfig(baseUrl: 'https://gssms.share.zrok.io');
      expect(
        config.apiUri('auth/login/').toString(),
        'https://gssms.share.zrok.io/api/v1/auth/login/',
      );
      expect(
        config.apiUri('/auth/login/').toString(),
        'https://gssms.share.zrok.io/api/v1/auth/login/',
      );
    });

    test('constructs wsUri correctly deriving wss from https', () {
      const config = AppConfig(baseUrl: 'https://gssms.share.zrok.io');
      expect(
        config.wsUri('ws/notifications/').toString(),
        'wss://gssms.share.zrok.io/ws/notifications/',
      );
    });

    test('constructs wsUri allowing ws only for localhost or loopback', () {
      const localhostConfig = AppConfig(baseUrl: 'http://localhost:8000');
      expect(
        localhostConfig.wsUri('ws/notifications/').toString(),
        'ws://localhost:8000/ws/notifications/',
      );

      const loopbackConfig = AppConfig(baseUrl: 'http://127.0.0.1:8000');
      expect(
        loopbackConfig.wsUri('ws/notifications/').toString(),
        'ws://127.0.0.1:8000/ws/notifications/',
      );

      const emulatorConfig = AppConfig(baseUrl: 'http://10.0.2.2:8000');
      expect(
        emulatorConfig.wsUri('ws/notifications/').toString(),
        'ws://10.0.2.2:8000/ws/notifications/',
      );
    });

    test('upgrades non-loopback http URL to wss for security', () {
      const stagingHttpConfig = AppConfig(baseUrl: 'http://staging.example.com');
      expect(
        stagingHttpConfig.wsUri('ws/notifications/').toString(),
        'wss://staging.example.com/ws/notifications/',
      );
    });
  });
}
