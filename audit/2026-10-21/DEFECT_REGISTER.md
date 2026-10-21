# Defect register

All findings below are source-confirmed observations with proposed reproduction procedures; those procedures were not executed as new tests during this baseline. P0 critical, P1 high release blocker, P2 medium, P3 low. No P0 established. Runtime impact is described conditionally where fault injection is required. No fixes applied.

## AUD-01 — P1 — Bearer credentials sent to unvalidated media origins

- Feature/location: `lib/core/widgets/authenticated_image_thumbnail.dart:93`, `:100`, `:107` and preview `:74`.
- Reproduce in an isolated test: supply a fixture photo URL on a controlled second HTTPS origin while authenticated; record outbound headers without logging the token value.
- Expected: authorization only to the trusted media origin; external/invalid origins rejected or fetched anonymously. Actual source: current access token attached to any nonempty supplied URL, in thumbnail and preview.
- Root cause: Image.network bypasses Dio policy; no scheme/host/port allowlist.
- Correction: central validated media URL resolver and origin-aware headers; validate redirect behavior as well. Side effect: external media may require explicit trusted configuration.
- Regression: trusted same-origin path, cross-origin HTTPS, HTTP, unusual ports, malformed URLs, redirects and signed-out state; assert absence/presence of header without exposing it.

## AUD-02 — P1 — Startup restore can repopulate a logged-out repository

- Feature/location: `lib/features/auth/data/auth_repository.dart:114`, assignments `:130`, logout `:326`.
- Reproduce: hold restore refresh response with a controlled future; call logout; release a valid response. Inspect repository session, bearer getter, persisted refresh token and cache owner.
- Expected: completed logout remains authoritative. Actual source: restore has no `_opGeneration` check and writes session/rotated token after logout. Controller checks its generation, but does not undo repository side effects.
- Root cause: restore lacks repository guards present in login/refresh.
- Correction: generation check around each awaited persistence/session operation; serialize credential writes with logout where necessary. Side effect: superseded restores ignored.
- Regression: restore/logout, restore/new login, token rotation during logout, cache binding interruption. Also exercise refresh/logout while secure storage write is suspended (`:175` to `:179`).

## AUD-03 — P1 — Credential deletion/persistence failure reported as success

- Feature/location: `lib/core/storage/secure_storage_service.dart:40`, `:52`, nested catches `:47`, `:60`; repository logout `lib/features/auth/data/auth_repository.dart:326`.
- Reproduce: mock secure storage so delete and deleteAll both throw while a refresh token exists; call logout, then allow reads and restart/restore.
- Expected: deletion failure surfaced with safe recovery; stale credentials cannot silently restore signed-out access. Actual source: both failures swallowed and logout completes; save similarly suppresses final failure.
- Root cause: void success contract conflates persisted success and suppressed failure.
- Correction: return a reliable result/typed failure, persist a safe session-revocation marker where possible, handle error explicitly; evaluate server revocation support. Side effects: visible logout/storage failure state and login persistence warnings.
- Regression: primary/fallback delete failures, write retry failure, restart and shared-device handoff, no sensitive error logging.

## AUD-04 — P1 — Offline queue can acknowledge nondurable persistence

- Feature/location: `lib/core/database/local_cache_service.dart:167`–`:178`; removal `:271`.
- Reproduce: prefs.setString returns false for primary and backup; enqueue mutation, terminate process, reopen cache. Separately make remove return false on logout.
- Expected: queue success only after durable save, wipe failure surfaced. Actual source: false primary result only logged, backup bool ignored, last-good memory updated; removal bool ignored. Process death can lose acknowledged queued work; wipe can retain prior data.
- Root cause: persistence return values not propagated; memory fallback cannot survive termination.
- Correction: fail closed on both writes failing, verify deletion outcomes, serialize/atomically persist queue with explicit recovery contract. Side effects: offline submission can display a storage error and must retain unsaved UI data.
- Regression: false vs throwing writes, partial backup success, disk full, interrupted save, restart, owner change and failed deletion.

## AUD-05 — P2 — Image-normalization failure preserves original metadata

- Feature/location: `lib/features/work_orders/data/evidence_service.dart:380` (raw copy fallback), `_runImageProcessing` immediately below.
- Reproduce: processImageOverride returns null for a JPEG with EXIF; persist photo and inspect resulting bytes/metadata.
- Expected: privacy promise of EXIF stripping and JPEG normalization upheld, or safe failure. Actual source: original file copied on decode/isolate failure, potentially preserving GPS/device metadata and original size/format under .jpg name.
- Root cause: raw-copy fallback bypasses normalization contract.
- Correction: fail safely or use a verified alternate sanitizer; avoid silently copying original. Side effect: previously accepted malformed photos may require recapture.
- Regression: decode failure, isolate exception, EXIF-bearing inputs, non-JPEG input, oversized pixel dimensions.

## AUD-06 — P2 — Energy workflow incomplete

- Feature/location: `lib/features/energy/presentation/screens/energy_placeholder_screen.dart:11`.
- Reproduce: open Energy & Solar as an authorized clerk.
- Expected for a release that includes energy operations: working meter/photo/bill workflow. Actual source: explicit Coming Soon page with backend prerequisites; no mobile workflow.
- Root cause: intentionally deferred backend/mobile implementation.
- Correction: formally exclude module from approved release scope or implement against staging contracts. Side effect: scope/UI availability change; do not remove without approval.
- Regression: role navigation, approved feature availability, complete workflow if implemented.

## AUD-07 — P2 — Release configuration permits environment mismatch

- Feature/location: `android/app/build.gradle:58`, `lib/core/config/app_config.dart:82`, `android/app/src/main/res/xml/network_security_config.xml:4`.
- Reproduce only after separate build authorization: evaluate prod variant with APP_ENV=dev; inspect resolved endpoint/policy without contacting production.
- Expected: production flavor rejects development environment/endpoints. Actual source: Gradle flavor and Dart environment are independent; shared manifest policy permits loopback cleartext and dev disables Dio HTTPS guard.
- Root cause: no binding/validation between flavor and runtime defines.
- Correction: enforce release environment mapping and use flavor-specific debug-only network exceptions. Side effect: invalid legacy build invocations fail intentionally.
- Regression: all flavor/environment combinations, custom URL scheme and loopback rejection in prod.

## AUD-08 — P1 — Android Lint task graph fails on Windows cross-drive paths

- Feature/location: `android/build.gradle:10` (root build directory assignment) and `android/app/build.gradle:1` (plugin configuration); external dependency mobile_scanner 7.4.2. Exact originating plugin stack frame requires a follow-up stacktrace. Evidence: `evidence/android-lint.txt`.
- Reproduction executed: from android, `./gradlew.bat :app:lintDevDebug --offline --console=plain` with project/build on D: and pub cache on C:.
- Expected: lint completes and reports Android findings. Actual: exit 1 while resolving `:mobile_scanner:generateDebugUnitTestLintModel`; cannot create testDebugUnitTest because build and plugin files have different roots. No lint PASS or application Kotlin compilation established.
- Root cause indicated by diagnostic: plugin unit-test task relativizes cross-drive paths. Precise plugin implementation cause not yet isolated.
- Correction proposal: reproduce with stacktrace in an isolated environment, evaluate same-drive project/pub cache or supported plugin/toolchain adjustment; do not change source/configuration until approved. Side effects: dependency resolution/cache location and build reproducibility change.
- Regression: lintDevDebug on Windows and Linux, native debug compilation, all supported flavors; verify no source migration or release signing occurs.

## AUD-09 — P3 — Strict analyzer baseline has informational debt

- Feature/location: `lib/core/widgets/org_scope_filter_bar.dart:343` and other paths listed in `evidence/flutter-analyze.txt`; `.github/workflows/mobile_ci.yml:35` configures nonfatal infos.
- Reproduction executed: `flutter analyze --no-pub` exits 1 with 112 informational issues (deprecated members and style recommendations); no warning/error severity diagnostics reported.
- Expected for strict baseline: exit 0. Actual: strict invocation fails; CI deliberately uses a weaker info policy. Not evidence of a compilation defect.
- Root cause: deprecated DropdownButtonFormField.value and accumulated style/info diagnostics.
- Correction: targeted initialValue migrations and small style cleanups; agree analyzer acceptance policy explicitly. Side effects: form reset/initial-selection behavior must be checked.
- Regression: affected dropdown initial selection/update/reset tests and strict analyzer rerun.

## Verification gaps (not invented code defects)

No connected Android device, no authorized staging fixture/accounts, no measured performance budgets/results, no current advisory scan, no approved production artifact validation. CI alone cannot establish these gates. Disabled shrinking is a size/hardening tradeoff, not by itself a proven vulnerability. Pinning absent despite `enableCertPinning` name; current HTTPS guard is not certificate pinning. Assess against the actual threat model rather than treating missing pinning alone as a critical defect.
