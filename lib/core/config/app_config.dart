/// The deployment / runtime environment of the mobile application.
enum AppEnvironment {
  dev,
  staging,
  prod;

  /// Parse environment from string, defaulting to [prod].
  static AppEnvironment fromString(String? raw) {
    switch (raw?.toLowerCase().trim()) {
      case 'dev':
      case 'development':
        return AppEnvironment.dev;
      case 'staging':
      case 'stage':
        return AppEnvironment.staging;
      case 'prod':
      case 'production':
      default:
        return AppEnvironment.prod;
    }
  }

  /// Default backend URL per environment.
  String get defaultBaseUrl {
    switch (this) {
      case AppEnvironment.dev:
        return 'http://10.0.2.2:8000';
      case AppEnvironment.staging:
        return 'https://gssms-staging.share.zrok.io';
      case AppEnvironment.prod:
        return 'https://gssms.share.zrok.io';
    }
  }

  /// Whether verbose logging and diagnostics are enabled.
  bool get enableVerboseLogging {
    switch (this) {
      case AppEnvironment.dev:
      case AppEnvironment.staging:
        return true;
      case AppEnvironment.prod:
        return false;
    }
  }

  /// Whether certificate pinning is enforced.
  bool get enableCertPinning {
    switch (this) {
      case AppEnvironment.dev:
      case AppEnvironment.staging:
        return false;
      case AppEnvironment.prod:
        return true;
    }
  }
}

/// Application configuration for GSSMS mobile.
class AppConfig {
  const AppConfig({
    required this.baseUrl,
    this.environment = AppEnvironment.prod,
  });

  /// The runtime environment flavour.
  final AppEnvironment environment;

  /// The backend base URL (e.g. 'https://gssms.share.zrok.io').
  final String baseUrl;

  /// Default production URL fallback if not provided via --dart-define.
  static const String defaultBaseUrl = 'https://gssms.share.zrok.io';

  /// Convenient environment checks.
  bool get isDev => environment == AppEnvironment.dev;
  bool get isStaging => environment == AppEnvironment.staging;
  bool get isProd => environment == AppEnvironment.prod;

  /// Factory constructor to load configuration from environment defines.
  /// Reads `APP_ENV` (or `ENVIRONMENT`) and `GSSMS_BASE_URL`.
  factory AppConfig.fromEnvironment() {
    const envString = String.fromEnvironment('APP_ENV', defaultValue: '');
    final fallbackEnv = envString.isEmpty
        ? const String.fromEnvironment('ENVIRONMENT', defaultValue: 'prod')
        : envString;
    final environment = AppEnvironment.fromString(fallbackEnv);

    const explicitBaseUrl = String.fromEnvironment('GSSMS_BASE_URL');
    final baseUrl = explicitBaseUrl.isNotEmpty
        ? explicitBaseUrl
        : (environment == AppEnvironment.prod ? defaultBaseUrl : environment.defaultBaseUrl);

    return AppConfig(
      baseUrl: baseUrl,
      environment: environment,
    );
  }

  /// Construct an API v1 Uri for a given relative path.
  Uri apiUri(String path) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final normalizedBase = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    return Uri.parse('${normalizedBase}api/v1/$cleanPath');
  }

  /// Construct a WebSocket Uri derived from the configured base URL.
  /// Enforces secure WSS unless explicitly communicating over loopback / localhost.
  Uri wsUri(String path) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final uri = Uri.parse(baseUrl);
    final isLoopback = uri.host == 'localhost' ||
        uri.host == '127.0.0.1' ||
        uri.host == '::1' ||
        uri.host == '10.0.2.2'; // Android emulator localhost alias

    final wsScheme = (uri.scheme == 'http' && isLoopback) ? 'ws' : 'wss';
    final portPart = uri.hasPort ? ':${uri.port}' : '';
    return Uri.parse('$wsScheme://${uri.host}$portPart/$cleanPath');
  }
}
