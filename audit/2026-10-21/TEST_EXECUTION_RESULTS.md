# Baseline test execution results

Environment: Windows PowerShell, root revision `83b34602af6db8c6663de3dd3f9fdcc4c148921a`; Flutter 3.47.3 stable, Dart 3.13.3, JDK 17.0.20, Android project min/target 24/36. Existing dirty backend gitlink preserved. Test doubles supply API data; printed production-shaped URLs in test logs are not proof of live integration.

| Check | Command | Result | Evidence/reason |
|---|---|---|---|
| SDK version | `flutter --version` | PASS | Flutter 3.47.3/Dart 3.13.3 observed; matches .fvmrc |
| Existing unit/widget/model/PDF/layout suite | `flutter test --no-pub --reporter expanded` | PASS, exit 0 | [full log](evidence/flutter-test.txt): 944 passed, 1 skipped, 0 failed, 4m32s |
| Optional report parity renderer | included in suite | NOT RUN (skipped) | REPORT_PARITY_OUT absent; test/report_parity/render_android_test.dart explicit skip |
| Strict static analyzer | `flutter analyze --no-pub` | FAIL, exit 1 | [log](evidence/flutter-analyze.txt): 112 informational issues, 270.3s; no warning/error diagnostics. This is strict-policy failure, not a proven compile failure |
| Android Lint | `./gradlew.bat :app:lintDevDebug --offline --console=plain` from android | BLOCKED, exit 1 | [log](evidence/android-lint.txt): mobile_scanner test task cross-drive path failure, 4m23s; lint analysis did not complete (AUD-08) |
| Android device discovery | SDK platform-tools `adb.exe devices -l` | PASS discovery; device tests BLOCKED | [log](evidence/adb-devices.txt): empty device list |
| Native app compilation | no separate packaging task invoked | NOT RUN | Gradle plugin tasks up-to-date are not app compilation evidence |
| Instrumented/UI/device integration tests | none run | BLOCKED | no Android device; root pubspec has no integration_test dependency |
| Staging integration/server RBAC | none run | BLOCKED | no supplied staging account/fixture; no production mutation |
| Performance/soak | none run | BLOCKED | no device or approved budgets |
| Current dependency vulnerability scan | none run | NOT RUN | lockfile inventory is not a vulnerability scan |
| Separate custom_lint | none run | NOT RUN | not part of current analyzer plugin config/CI |
| Formatting check | none run | NOT RUN | no source rewrite performed; CI formatting is report-only |
| Release artifact/merged prod manifest/ABI validation | none run | NOT RUN | production packaging/signing prohibited pending gates/authorization |

Counts: 945 suite outcomes: 944 PASS, 1 skipped, 0 FAIL. Baseline commands are reported separately and are not added to the unit-test count. No coverage percentage measured in this run (no --coverage flag). Per-test names, progress and actual events are in the full suite log.

Initial sandbox attempts could not complete Flutter startup and blocked ADB daemon/Gradle lock access. Commands were retried with elevated execution authorization. ADB discovery and Flutter checks completed; elevated Gradle reached the real cross-drive failure. No dependencies upgraded, no tests added, no source/config files modified. Tool caches and generated test/build reports may change as normal test side effects.
