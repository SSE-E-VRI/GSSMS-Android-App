# Photo upload denial — 24 October 2026

Status: **root cause found; fix implemented and verified against the production
edge, pending backend deployment.** See "Root cause" below; the earlier
investigation notes follow it unchanged.

## Root cause

The 403 is not issued by Django. `gssms.share.zrok.io` is served through
zrok's public frontend, which sits behind an AWS load balancer. Its firewall
answers `403 Forbidden` (`Server: awselb/2.0`, HTML body) to **any request
body containing a standard JPEG quantization table** (`FFDB` segment) — i.e.
every real photo — on any path, before the request reaches Daphne. It is not
specific to ALU/MTUR, an account, a role or an assignment; it affects every
JPEG upload from the Android app and the web app (checklist, complaint,
inspection, execution evidence, proof, profile photo).

Earlier probes passed because they used fake image bytes, which the firewall
ignores. Verified with unauthenticated probes to a nonexistent record
(Django can only answer 401; no data written):

| Body | Edge result |
| --- | --- |
| Real JPEG (30 KB or 1.28 MB), multipart or raw | 403 `awselb/2.0` |
| Only the JPEG `FFDB` segment | 403 `awselb/2.0` |
| Fake `FFD8FF` + text, random bytes | 401 `daphne` |
| Base64 body sent with a multipart Content-Type | empty 400 (edge) |
| Base64 multipart body as `text/plain` + headers below | 401 `daphne` |

## Fix

Uploads are sent base64-encoded as `text/plain`, with
`X-GSSMS-Body-Encoding: base64` and the real Content-Type (with boundary) in
`X-GSSMS-Content-Type`. The backend restores the original bytes and
Content-Type before any parsing, so permissions, assignment checks and JPEG
validation run unchanged on exactly the request the client built.

- Backend: `GSSMS/backend/gssms_project/middleware.py`
  (`EncodedBodyMiddleware`, first after CORS; 24 MB encoded cap; CORS
  allow-headers updated). Requests without the header are untouched.
- Web: `GSSMS/frontend/src/services/encodedUpload.js`, applied in the shared
  axios request interceptor to any `FormData` containing a file.
- Android: `lib/core/network/encoded_upload_interceptor.dart`, installed in
  `DioClient.create`; token-refresh retries replay the same encoded bytes, and
  queued outbox photos use the same path.

**Deployment order:** deploy the backend (which also ships the web bundle)
first, then install the new APK. An updated APK against the old backend
gets a 400 instead of today's 403 — uploads already fail there, so this is
no regression, but photos only succeed once the backend is live.

The proper long-term fix is to stop depending on zrok's shared public
frontend for production (own domain/tunnel), or have zrok clear the false
positive; the encoding can then remain harmlessly or be removed.

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
