# Project inventory and audit plan

Audit date: 21 October 2026 (Asia/Calcutta). Scope: Phase 0 discovery and safe baseline audit of the root mobile application. This is an interim production readiness assessment, not certification that every source file or runtime path was exhaustively reviewed. No source fixes, production signing or APK generation authorized or performed.

## Baseline

- Revision: `83b34602af6db8c6663de3dd3f9fdcc4c148921a`.
- Existing workspace changes: `GSSMS-complaint` gitlink and untracked `.claude/settings.json`; preserved. Nested `GSSMS`, `GSSMS-complaint`, SSOT and Improvement content is contextual material, not an independently audited backend deployment.
- Flutter 3.47.3 stable, Dart 3.13.3; `.fvmrc` matches CI. Dart constraint >=3.4.0 <4.0.0; Flutter >=3.47.0 <3.48.0.
- Feature-oriented Dart presentation/controller/domain/repository/API structure. Riverpod providers/notifiers; Material widgets; imperative Navigator/MaterialPageRoute. Android native entry point is a single Kotlin FlutterActivity; no custom native fragments discovered.
- 202 application Dart files; 127 root test files; 32 screen files. Full tracked-file list and screen-by-screen inventory: [evidence](evidence/screen-inventory.md), [tracked files](evidence/tracked-inventory.txt).
- AGP 9.1.0; Kotlin plugin 2.4.0; Gradle wrapper 9.3.1; Java source/target 17; installed JDK 17.0.20. Android compilation compatibility still requires successful Gradle execution.
- Namespace/application ID `com.ssee_vri.gssms_mobile`; min SDK 24, target/compile SDK 36; version 0.3.1 (code 5).
- Flavors dev (`.dev`), staging (`.staging`), prod (base ID), debug/profile/release Flutter modes. Dart APP_ENV is separately configured; no flavor-to-Dart environment enforcement established.

## Components and data

Modules: password/OTP/TOTP authentication, profile/password/photo management, home, dashboard, assets/QR, complaints, inspections, deficiencies, maintenance schedules, work orders, assignment/reassignment, verification, checklists, complaint/inspection/rectification execution, replacement requests, approvals/pending actions, PDF reports/registers, derived notifications, More/theme controls. Energy & Solar is explicitly a placeholder.

App startup restores session; foreground resume drains pending sync. No application-defined Android service/receiver, push notification SDK, WorkManager or native database declared in reviewed mobile sources. Notifications derive from fetched work orders; read markers are in memory. No OS background-delivery guarantee should be inferred.

JWT access tokens held in memory; refresh token uses flutter_secure_storage. SharedPreferences stores serialized work orders, details, records, owner ID and outbox plus backup. Durable evidence photos in application documents; profile photo disk cache. Offline replay has owner/session guards, idempotency keys and bounded retries. These mechanisms need interrupted-operation/device testing.

Permissions: Internet/network state, camera, coarse/fine foreground location, media images, legacy external read <=32, vibration. Camera hardware optional. Launcher activity exported; backup disabled. Shared network security config blocks general cleartext but permits emulator/loopback hosts for every flavor.

API base URLs are selected in `lib/core/config/app_config.dart`: emulator development :8000, staging and production HTTPS zrok hosts. JWT bearer auth, refresh after 401, multipart evidence and profile uploads. API inventory: [calls with source lines](evidence/api-calls.txt). Backend behavior and authorization are not verified by client source.

Dependencies: Riverpod, Dio, secure storage, JWT decoder, Equatable, intl, shared_preferences, image_picker/image, path_provider, fl_chart, pdf/printing, mobile_scanner, geolocator, permission_handler, meta/vector_math. Dev: flutter_test, mocktail, flutter_lints, custom_lint and local gssms_lints. Exact lock versions: [resolved inventory](evidence/resolved-dependencies.txt). No current vulnerability clearance established.

CI `.github/workflows/mobile_ci.yml`: formatting report only, analyzer with nonfatal infos, unit/widget coverage, dev debug APK. No connected-device, staging, performance or vulnerability release gate in this workflow. Separate custom lints are not invoked there.

## Execution plan

1. Preserve baseline and record inventory/configuration; completed before report creation.
2. Run installed SDK version, no-pub Flutter analyzer, existing unit/widget suite, offline Android Lint and ADB discovery; capture real outputs.
3. Review auth, networking, storage/outbox, permissions, manifest, release configuration and representative screen/test implementation. Register evidence-backed source defects without changing code.
4. With approved targeted fixes, add race/persistence/origin regressions and rerun affected suites. Explain side effects first: stricter origins can break external media; persistence errors change login/logout/offline error flows; generation guards discard stale responses.
5. Obtain disposable staging accounts for each role and seed data. Execute positive/negative/boundary/regression cases in the functional matrix, including server authorization and duplicate request replay.
6. Test API 24 and 36 plus current supported platform, small phone/tablet, both navigation modes, rotation, 200% text, dark/light, TalkBack, offline/reconnect, low memory/process death and permission denial. Capture screenshots and logs.
7. Profile real devices against agreed budgets; test migration/corruption/recovery using representative nonproduction data; scan resolved dependencies against current advisories.
8. Review merged release manifest/dependencies/native ABI packaging and unsigned release compilation only through an explicitly safe task graph. Production packaging/signing remains prohibited until all gates pass and explicit authorization is supplied.

Reports in this directory distinguish executed baseline evidence from deferred device/backend work. Readiness remains NO-GO until blockers and unverified mandatory gates are resolved.
