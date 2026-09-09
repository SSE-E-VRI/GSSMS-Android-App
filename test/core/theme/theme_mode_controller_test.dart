import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gssms_mobile/core/theme/theme_mode_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to ThemeMode.system', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('restores a persisted dark preference', () async {
    SharedPreferences.setMockInitialValues({
      kGssmsThemeModePrefKey: 'dark',
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container.read(themeModeProvider.notifier).restore();
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test('setThemeMode persists the choice', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.light);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(kGssmsThemeModePrefKey), 'light');
    expect(container.read(themeModeProvider), ThemeMode.light);
  });
}
