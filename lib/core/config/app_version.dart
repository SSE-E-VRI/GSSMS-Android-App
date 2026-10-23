/// Release version shown on the login screen: the `version:` line in
/// pubspec.yaml without its `+build` suffix (the build number is an internal
/// Android versionCode, not something users need to see).
/// `test/core/app_version_test.dart` fails if they drift.
const String appVersion = '0.3.5';
