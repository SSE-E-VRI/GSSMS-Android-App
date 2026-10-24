# Photo upload denial — 24 October 2026

Status: investigation open; no root-cause fix verified yet.

## Report

The production checklist shows a generic photo-upload denial on three phones,
including MTUR job `MTUR-202610-0019`; the user also reports ALU job work.
The user confirms the error persists after signing in again.

## Verified

- Production API: `https://gssms.share.zrok.io/api/v1/`.
- A fresh login for the supplied account resolves to user 183, role
  `MAINTENANCE_STAFF`, depot 23, with both attachment permissions.
- MTUR work order 113 is `IN_PROGRESS`, assigned to user 183, and links to
  maintenance record 88. The record is readable by this account.
- The exact attachment endpoint for record 88, line 4970 passes its access
  gate with that account. Image-free JSON and multipart probes return 400,
  `Image file is required`, rather than 403.
- Deliberately invalid JPEG content at 1,000, 200,000 and 1,500,000 bytes
  returns 400, `Only JPEG images are allowed`. These probes include the
  app's idempotency header names.
- A valid synthetic JPEG with an invalid photo kind returns 400 for that
  kind. It cannot create an attachment. Dart user-agent probes also reach
  validation successfully.
- All 22 tests in
  `test/features/work_orders/presentation/attachment_permissions_test.dart`
  pass, including repeated uploads, independent photo permissions and
  preserving proof after denial. This does not prove production upload success.

No production photo, checklist value, assignment or role was changed by these
checks. Credentials and tokens are excluded from this report.

## Environment distinction

The local listener on port 8000 runs from `GSSMS/backend`, with database
`gssms_dev_restore_20261020_095752`. That database does not contain the
reported job. Its migration/grant state cannot establish the state of the
production service. Do not deploy or edit this local listener assuming it is
the affected production service.

## Next evidence required

Capture the failed request's safe server error through the separate dev
diagnostic package. The controller exposes the server's 403 reason; a subsequent
debug-only interceptor change also logs the readable denial reason so the
short-lived message can be captured. These changes improve diagnosis; they are
not a verified fix for the reported denial. Preserve the production package and
queued work. Do not replay production queues or upload test evidence to
operational jobs. ALU requires the exact affected job/account to verify its
failure independently.

Diagnostic build completed successfully: `build/releases/gssms-photo-diagnostic-dev-20261024.apk`.
Package: `com.ssee_vri.gssms_mobile.dev`; API target: production HTTPS endpoint.
SHA-256: `8ae3e9e698eebda9ebfe4f014b29598ebea7aaa7deab3a17a9b52c1106387335`.
It includes the existing working-tree diagnostic wording and current branch
changes; it is not a production hotfix or proof that uploads are repaired.

The user subsequently reconnected the phone. Diagnostic installation succeeded;
the separate dev package was signed in and opened read-only to the MTUR
checklist. The user was asked to retry their intended legitimate work photo and
leave the error visible. No automatic photo upload or queue replay was performed.

The user's retry reproduced HTTP 403 on
`/api/v1/maintenance/records/88/lines/4970/attachments/` at 16:48 phone-log time.
The message disappeared before its reason could be captured. A later retry
returned to the checklist without a captured new upload error. The exact reason
therefore remains unknown.

A temporary host-side Flutter probe used the actual `WorkOrderApiService` and
Dio transport, an invalid kind and non-JPEG bytes. It passed with the expected
400 validation response. This confirms the host/app transport can reach the
same endpoint's validation; it does not reproduce the phone's 403. The temporary
probe and its artifacts remain under ignored `build/`; no credentials are in
the probe source. The rebuild containing debug-only denial logging completed
successfully at `build/app/outputs/flutter-apk/app-dev-debug.apk`. It has not
been installed; the first installed build does not contain that logging.

Before committing, the combined photo-permission and authentication interceptor
suites passed: **33 tests**, zero failures. The diagnostic APK build also passed.
The separately named release-folder diagnostic APK and its hash above identify
the first build, not the later logging build.

After the failed request is captured, reproduce that cause with disposable
fixtures, implement the smallest fix, and verify both legitimate uploads and
denial for an unassigned technician. Do not broaden permissions speculatively.
