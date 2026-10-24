# Production hardening - 23 October 2026

## APK build update ? 24 October 2026

Version **0.3.6+11**, built from Android commit `a8d71d0`, includes the
separate Cancel Job Work and Skip this due period flows and the intervening
committed dashboard/checklist updates. The production-flavour release APK uses
`https://gssms.share.zrok.io` and package `com.ssee_vri.gssms_mobile`.

- Artifact: `build/releases/gssms-mobile-0.3.6+11-prod.apk` (89.1 MiB).
- SHA-256: `717b8aabeb542da92d0698bcd792d4c1a6fffae0708ece3f4f188300d3b9d9ac`.
- Existing release certificate matches the preceding APK; APK v2 signature verified.
- ZIP integrity, 21 native libraries, ELF alignment and ZIP 16 KB alignment passed.
- Manifest verified: versionName 0.3.6, versionCode 11, min SDK 24, target SDK 36.
- 528 targeted Flutter tests passed; prior full and focused analysis found no issues.
- Deploy backend commit `049c72f` with migration
  `maintenance.0111_legacy_skip_terminal_constraints` before using legacy skips.
- No installation, physical-device acceptance test or backend deployment was
  performed. Earlier field-acceptance gates below remain applicable. This APK
  build does not constitute production acceptance.

The report below records earlier hardening evidence for 0.3.2+6.

Candidate: 0.3.2+6. This report supersedes the source-remediation status of the
21 October baseline, not its historical evidence. No production-server data
changes, deployment, distribution or authenticated mutation tests were performed.

## Remediation

| Finding | Change | Evidence |
| --- | --- | --- |
| AUD-01 | Central protected media loader rejects foreign schemes/hosts/ports/userinfo and all redirects; current token is read at render time and included in cache identity. All evidence thumbnails and previews migrated. | Origin policy, redirect loopback server and widget regressions |
| AUD-02 | Serialize credential writes, cache binding and logout; generation guards prevent startup restore/login/refresh from committing after logout or newer login. Publish session only after cache ownership is safe. | Suspended-write logout, late restore and newer-login regressions |
| AUD-03 | Secure-storage failures propagate; persistent revocation marker prevents restart restoration after failed deletion; retry sign-out UI and expiry handlers surface cleanup failure. | Failed write/deletion and controller regressions |
| AUD-04 | Reject false/throwing primary outbox writes, reload preference memory after failure, validate cache removal and ownership writes, fail closed on foreign/unowned cache. | Persistence-failure, cache-owner and existing sync tests |
| AUD-05 | Reject failed normalization instead of copying original; clear EXIF before JPEG encode; bound compressed size and decoded pixel count. | EXIF, malformed image and oversized-dimension regressions |
| AUD-06 | Energy workflows explicitly excluded from current release; existing screen labels the exclusion. | Source and role-navigation tests |
| AUD-07 | Release task and runtime checks bind flavor/environment; non-dev endpoints require remote HTTPS; debug-only loopback policy. | Flavor/endpoint matrix tests and release build |
| AUD-08 | Put cross-drive Windows plugin build outputs in same-drive Gradle cache, outside Pub source directories. | Android lint now completes successfully |
| AUD-09 | Apply analyzer migrations; preserve PDF geometry through replacement APIs and golden tests; CI uses strict analysis. | Final strict-analysis result below |

Additional hardening declares Android 14 selected-photo access, adds Android 12+
cloud/device-transfer exclusions and preserves disabled backup on older Android.
The geolocator dependency's optional notification path has its required manifest
permission; this application does not request background location or notification
access during evidence capture.

## Executed validation

- Final complete Flutter suite with `REPORT_PARITY_OUT` set: **1,021 passed,
  zero skipped, zero failures** (5m26s).
- Subsequent targeted authentication, media, theme and PDF suite: 167 passed.
- Android `:app:lintDevDebug`: PASS, zero errors, three warnings (newer Gradle
  available, ignored pre-33 back attribute, redundant drawable-v21 qualifier).
- OSV hosted Pub scan: 144 locked packages checked, zero reported advisories.
- OSV Maven scan: 135 resolved release coordinates checked, zero reported
  advisories. Neither scan certifies bundled Flutter/SDK binaries or unpublished
  vulnerabilities.
- Strict Flutter analysis: PASS, zero issues.
- Optional PDF fixture renderer: PASS, all 14 local fixture PDFs generated.
- Phone smoke: PASS for isolated-package installation, launch, empty username/
  password validation and email-OTP navigation. No OTP was sent.
- Signed APK: v2 signature verified with the existing GSSMS release certificate;
  min SDK 24, target SDK 36. Final APK ZIP integrity, case-collision check,
  ZIP alignment and all 21 native-library alignment checks: PASS. Packaged
  production network policy permits no cleartext.

Local command logs are in `build/production-*.txt`, outside version control.
Public dependency scan details: `build/production-pub-advisories.json`.

## Device and backend acceptance

The user connected an Android 14 CPH2381 test phone and specified that the server
is production and must not be changed. Its installed production package is
preserved. The temporary `.dev` test package was removed after verification. Smoke validation uses the separate `.dev` package with a loopback
unused-port endpoint; no production login, queue replay or record mutations.

Clean evidence: `build/production-phone-login.png`,
`build/production-phone-validation.png`, `build/production-phone-otp.png` and
`build/production-phone-smoke.json`. A connection-refused message was observed
on the deliberately unreachable test endpoint and replaced with a safe,
plain-language message in the final source; its regression tests passed.

This establishes only the observed install/launch/UI behavior. Full role
permissions, live uploads, offline replay/conflicts, process death and upgrades
with real operational data still require disposable nonproduction fixtures.
Physical minimum-API coverage, TalkBack, measured performance/soak budgets and
bundled SDK/native binary security review remain acceptance gates. Do not describe host
unit tests or a login-screen smoke as completion of these gates.

Energy & Solar workflows are outside scope. Production backend availability,
configuration, security and deployment have not been changed or certified here.

## Distribution gate

A signed candidate can be reviewed and tested locally. Broad production rollout
requires the outstanding nonproduction workflow and field acceptance gates.
Do not use production records to make those tests pass. Existing audit documents
remain unchanged as historical baselines.

## Reproducible artifact checks

```powershell
python tool/check_pub_advisories.py
cd android
.\gradlew.bat :app:dependencies --configuration prodReleaseRuntimeClasspath --console=plain > ../build/production-maven-dependencies.txt
cd ..
python tool/check_maven_advisories.py
python tool/verify_apk.py build/app/outputs/flutter-apk/app-prod-release.apk
```

`apksigner verify --verbose --print-certs` and `zipalign -c -P 16 4` are run
separately with Android Build Tools 36. The ELF check requires 16 KB alignment
for 64-bit libraries and 4 KB for 32-bit libraries, following the
[Android NDK maintainer guidance](https://android.googlesource.com/platform/ndk/+/master/docs/BuildSystemMaintainers.md).
It does not replace an on-device 16 KB runtime test.

Transient credential reads and refresh-network failures now remain distinct
from invalid credentials; they preserve the saved refresh token. Auth expiry
cleanup failures cannot leave Dio requests hanging. The final targeted auth
suite passed 74 tests; the network-error sanitization suite passed 16 tests.

## Final local artifact

- Path: `build/releases/gssms-mobile-0.3.2+6.apk`
- Version: 0.3.2, Android versionCode 6
- Signing: existing GSSMS release certificate, APK v2 verified; no debug signer
- Signing certificate SHA-256:
  `58c383f0fef111f6d6b4299031f5a3ca1a17446f996b4ac84cdbab6369e41c0f`
- APK SHA-256:
  `81cac4d1d1415e626f55f90ff9f69a7ddfc9556129e12cf55dc8067fe34eb746`
- Size: 93,251,943 bytes
- Artifact has not been distributed or installed over the phone's production app.

The source changes remain local for review. CI configuration is updated; no
claim is made that GitHub CI has run on these uncommitted changes. Existing
backend checkout changes and independently created verification directories or
patch/archive artifacts were preserved.

Final status: **signed release candidate ready for review and nonproduction
acceptance; broad production rollout remains gated by live workflow/role,
field reliability, accessibility and performance acceptance**. The restriction
on production mutations was honored throughout this task.
