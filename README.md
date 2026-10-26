# GSSMS Mobile

Flutter Android application for field maintenance, assets, complaints,
inspections, job work, approvals, offline evidence and PDF reports.

## Development

Use Flutter **3.47.3** (see `.fvmrc`) and the committed `pubspec.lock`.
Android requires API 24 or later; compile/target SDK is 36.

```powershell
flutter pub get
flutter run --flavor dev --dart-define=APP_ENV=dev
```

The development default is `http://10.0.2.2:8000`. Override it with
`--dart-define=GSSMS_BASE_URL=...`. Native flavor and APP_ENV must match.
Staging and production require remote HTTPS endpoints. Cleartext loopback
exceptions exist only in debug builds.

Build-time defines (`--dart-define=NAME=value`):

- `GSSMS_BASE_URL`: API base URL (see above).
- `GSSMS_SPKI_PINS` (optional): comma-separated base64 SHA-256 SPKI hashes for
  certificate pinning. When absent, no pinning is applied. Always ship at least
  a current pin and a backup pin. Do not pin a `*.zrok.io` tunnel certificate;
  pin only a domain you control.

Compute a pin from a certificate:

```bash
openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64
```

The `crypto` package is now a direct dependency; run `flutter pub get` after
updating.

## Validation

```powershell
flutter analyze
flutter test --coverage
cd android
.\gradlew.bat :app:lintDevDebug --console=plain
```

Optional report rendering uses local fixtures only:

```powershell
$env:REPORT_PARITY_OUT="$PWD/build/report-pdfs"
flutter test test/report_parity/render_android_test.dart
```

`python tool/check_pub_advisories.py` queries OSV for the public hosted Dart
packages in `pubspec.lock`. Export `prodReleaseRuntimeClasspath` as described
in the readiness report, then run `python tool/check_maven_advisories.py` for
resolved Android Maven coordinates. CI runs both checks; bundled SDK binaries
still require separate security review.

## Release candidate

Current version: **0.3.10+15**: Execution forms now wait for edits made during autosave before submission or navigation. Includes 0.3.9+14: Depot Incharge sees all photo evidence (checklist, proof, inspection, deficiency), report photos print again, Breakdown form matches the web, and upload hardening; requires web/backend 1.9.17 (migration 0112) deployed first. It includes 0.3.8+13, which fixes photo uploads being rejected with 403 by the public edge (uploads are now sent encoded; see [photo upload diagnosis](docs/PHOTO_UPLOAD_DIAGNOSIS_2026-10-24.md)). It includes 0.3.7+12, a hotfix for latest offline checklist edits and pending-value restoration. The saved queue format is unchanged. Full offline reopen remains a separate follow-up; see [phone acceptance](docs/PHONE_ACCEPTANCE_2026-10-24.md). Includes the existing separate Job Work cancellation and due-period skip requests. The matching backend still requires maintenance migration 0111 for those workflows. See [photo upload permission fix](docs/PHOTO_UPLOAD_PERMISSION_FIX_2026-10-23.md). See
[production readiness](docs/PRODUCTION_READINESS_2026-10-23.md) for verification
results and remaining field-validation gates.

Keep `android/key.properties` and its keystore outside version control.
Production refuses to build without the existing release key. Never substitute
another key when updating an installed application.

```powershell
flutter build apk --release --flavor prod --dart-define=APP_ENV=prod
```

For smaller per-device APKs, split by ABI:

```powershell
flutter build apk --release --flavor prod --dart-define=APP_ENV=prod --split-per-abi
```

Output: `build/app/outputs/flutter-apk/app-prod-release.apk`.
Building does not publish or deploy the application. Energy and Solar meter
capture, bills and consumption workflows are outside this release scope.

Production-server records must not be modified for testing. Use a nonproduction
backend and disposable accounts for mutation, role and offline-sync acceptance.
