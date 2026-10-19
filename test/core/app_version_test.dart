import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/config/app_version.dart';

void main() {
  test('appVersion matches the version: line in pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final pubspecVersion = line.substring('version:'.length).trim();
    expect(appVersion, pubspecVersion,
        reason: 'Bump lib/core/config/app_version.dart together with pubspec.yaml');
  });
}
