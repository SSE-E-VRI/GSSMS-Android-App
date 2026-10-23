# Android checklist photo permission fix

Release candidate: **0.3.3+7**, 23 October 2026.

## Confirmed Android defect

Both the grouped Before/After evidence widget in the supplied screenshot and
per-line photo widgets enabled capture based on photo count and completion
status. They did not check `maintenance.attachment_add` or
`maintenance.attachment_delete`. `maintenance.edit` is insufficient under the
backend contract in this workspace. This allowed users to attempt actions the
server would reject with 403.

This finding explains a possible path to the screenshot's error; the actual
production account claims, assignment, server version and permission decision
were not inspected. No assertion is made that Django has no separate issue.

## Changes

- Separate fail-closed upload and delete checks match the backend's accepted
  roles and exact permission codes. No permission is inferred from a role or
  from `maintenance.edit` alone.
- Grouped and per-line capture/gallery/delete/retry controls reflect current
  claims, including refresh and revocation, while existing photos remain viewable.
- Capture and deletion handlers recheck access after native permission dialogs
  or delete confirmation. The controller also checks permission, completion
  state, the open record ID and line membership before a repository request.
- Retry rejects attachments outside the open record.
- A server 403 preserves existing photos and local proof and explains that
  photo permissions or job assignment may have changed. It does not claim a
  successful upload or bypass server authorization.
- Local proof is removed only after a successful server deletion, so a denied
  delete cannot silently discard the local photo.

The backend remains authoritative for depot/organisation scope and technician
assignment; the record response does not expose sufficient assignment data to
reproduce those decisions reliably on Android. The app deliberately does not
guess assignment from a technician name.

## Verification

Twenty targeted permission regressions cover missing/sessionless access,
accepted and rejected roles, independent upload/delete grants, refreshed and
revoked claims, completion locks, record/line mismatch, authorized upload IDs,
server 403 handling and preservation of proof on denied deletion. Existing
capture, group-holder selection, deletion and retry tests use explicit photo
permissions for their authorized fixtures.

Final full-suite, analysis and release-artifact results are recorded below
when completed. All upload responses in these tests are mocked. No real
production upload, delete, role change, database migration or account change
was performed. The production app installed on the phone was not replaced.

## Remaining boundary

A legitimate backend denial can still occur if the server has not granted the
attachment permission, the job is outside the user's scope, assignment changed,
or the deployed server differs from this workspace. Installing this APK cannot
grant server access. Actual production upload success is not certified here.

The prior 0.3.2+6 artifact is preserved separately at
`build/releases/gssms-mobile-0.3.2+6.apk`. The new candidate is delivered as
`build/releases/gssms-mobile-0.3.3+7.apk` after build and signature verification.

## Final verification results

- Full Flutter suite, including the optional PDF fixture renderer: **1,041
  passed, zero skipped, zero failures** (2m33s).
- Strict analysis of `lib`, `test` and `packages`: **zero issues**.
- Signed production APK built successfully; manifest version **0.3.3+7**.
- APK signature, ZIP integrity, case-collision check, ZIP alignment and all
  21 native-library alignment checks: **PASS**.
- Previous 0.3.2+6 signed APK preserved with its original checksum.
- No production-server changes and no replacement of the installed production
  app were performed during this fix.

APK SHA-256: `b674b2cb8a69d97776999ad3208f7cd38e5a937c1b734cddd9e7b193c2825243`. Size: 93,251,943 bytes.
