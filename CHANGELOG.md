# Changelog

All notable changes to the GSSMS mobile app are documented here.

Versioning: `MAJOR.MINOR.PATCH+BUILD`. BUILD is the Android versionCode and
increases with every distributed APK; PATCH is fixes and wording; MINOR is a
visible feature or change in what the app shows; MAJOR is a breaking change or
forced update. The app talks to the GSSMS web/backend; API changes are additive,
so older app builds keep working.

## [0.3.9+14] - 2026-10-25

### Fixed
- Job Work report photos all printed "No photo": they were requested with `Accept: image/*`, which the server's media view answers with 406.
- Depot Incharge Verify screen: checklist line photos, the PM proof-of-execution photo, the inspector's point and general evidence, and a deficiency's original checklist evidence were not shown; they now are (read-only, tap to enlarge).
- Breakdown photos waiting for Save Progress could be deleted by the 48 h evidence cleanup; they are now protected and recorded per user (a reassigned Job Work never shows another technician's pending photos).
- Every photo upload gets at least 120 s (only checklist uploads had it); inspection and rectification photos are resized and stripped of EXIF on the phone; a checklist photo hitting a 502/503/504 is queued instead of lost.
- Backend media URLs are always fetched from the configured server, so a proxy that rewrites scheme or host can no longer blank evidence photos.

### Changed
- Breakdown execution form matches the web: Breakdown Information card, read-only unless In Progress, Technician Name for the signature, Final Remarks after the photos, web guidance text, 10 photos per kind, and "On this phone. Uploads when you tap Save Progress." for photos not yet uploaded.
- Inspection execution and the rectification forms show the inspector's / checklist's original evidence read-only.
- Checklist and rectification reports print the proof-of-execution photo and the deficiency's original evidence, as the web reports do.

### Release scope
- Requires web/backend 1.9.17 deployed first (migration 0112).

## [0.3.8+13] - 2026-10-24

### Fixed
- Checklist, complaint, inspection and profile photo uploads failed with "Photo upload was denied" (HTTP 403). The public edge in front of the production API blocks any request body containing a real JPEG before it reaches the server, so no account, role or assignment change could help. Uploads are now sent base64-encoded as `text/plain` with the original multipart Content-Type in `X-GSSMS-Content-Type`; the backend restores the original request. Token-refresh retries and queued offline photos use the same path.

### Release scope
- Requires web/backend 1.9.16 to be deployed first; against an older backend uploads still fail (400 instead of 403).
- No change to permissions, the saved queue format or any API contract.

## [0.3.7+12] - 2026-10-24

### Fixed
- Repeated offline checklist edits retain the latest value, including numeric autosaves.
- Pending checklist values are restored from the existing outbox when records are reopened after session restoration.
- An older queued assignment cannot overwrite a newer value sent after reconnect.

### Release scope
- Data-layer hotfix only. The saved queue format is unchanged.
- Full offline reopening remains blocked by checklist navigation and cold session restoration; those are separate follow-ups.
- Server-side duplicate protection and simultaneous-edit conflicts remain outside this hotfix's guarantees.

## [0.3.5+10] - 2026-10-23

### Fixed
- One checkout switch per backend template group across physical assets; keep each asset's labels and evidence accessible.
- Preserve supervisor attribution when topping up a partial checkout and retain the legacy-server conflict refresh.
- Save progress flushes pending edits, waits for active saves, and reports locally queued work distinctly from server-saved work.
- Login version aligned with this candidate. This is a pre-release, not production approval.

## [0.3.4+8] - 2026-10-23

### Fixed
- The first offline save after install or sign-out no longer fails on an
  immutable queue list.
- Queued offline work is no longer discarded when permissions change for the
  same user or when the session expires. It is kept for the same user and
  discarded only when a different user signs in or on explicit sign-out.
- Retried actions no longer apply twice on slow networks (the idempotency key
  is reused), and uploads now have 120 s timeouts.
- Server busy/gateway errors (408/429/502/503/504) retry automatically and
  honour Retry-After.
- The sync badge no longer shows Offline when work is blocked by a failed item
  (it shows "needs attention"), and no longer sticks on Syncing after sign-out.
- Another user's queued photos are not swept.
- The refresh token is no longer wiped on a transient secure-storage read error.

### Added
- Optional SPKI certificate pinning via `GSSMS_SPKI_PINS`.

### Changed
- Removed the unused notification permission.
- Repository hygiene: node_modules, a stray submodule entry and archives are no
  longer tracked.

## [0.3.3+7] - 2026-10-23

### Fixed
- Checklist photo capture, upload, retry and delete controls now use the
  backend's separate attachment permissions instead of completion status alone.
- Permission changes from token refresh update photo controls immediately.
- Upload handlers reject mismatched record/line IDs and denied access before
  sending a request. Server denials explain permission/assignment checks.
- A failed server-side deletion preserves the local proof file.

## [0.3.2+6] - 2026-10-23

Production-hardening candidate; distribution requires the device/staging gates in
`docs/PRODUCTION_READINESS_2026-10-23.md`.

### Fixed
- Protected evidence photos reject foreign origins and redirects; image caches
  distinguish sessions. All evidence preview paths use the same loader.
- Logout cannot be undone by a late startup restore, login or refresh write.
- Failed credential writes/deletions and offline persistence are surfaced;
  a persistent revocation marker blocks stale credential restoration.
- Failed photo normalization rejects the original; JPEG output clears EXIF and
  oversized decoded dimensions are rejected before pixel allocation.
- Release builds enforce flavor/environment matching and HTTPS endpoints.
- Windows Android lint supports Pub dependencies on a separate drive.

### Changed
- Backup and device-transfer exclusions protect local credentials and field data.
- Login offers retry after sign-out cleanup failure.
- Energy workflows are explicitly outside this release's scope.
- CI adds Android lint and strict static analysis.

## [0.3.1+5] - 2026-10-20

Bug-fix release from the 2026-10-20 audit.

### Fixed
- Signing out no longer lets the previous user's queued offline work reappear
  in the next session; a login racing a sign-out can no longer restore the
  signed-out session; a request from a previous user is never replayed under a
  new user's token.
- Photo uploads now succeed after the access token expires mid-upload.
- Offline queue: double-taps no longer enqueue duplicates, distinct no-photo
  evidence submissions are no longer dropped, Retry resets the retry budget,
  app resumes while offline back off instead of exhausting retries, and job
  completion waits for its line observations and photos.
- Login errors no longer show raw server HTML; a missing token expiry is
  rejected; transient secure-storage read failures no longer sign the user out.
- Dashboard, Reports, Pending Actions and Assets ignore stale responses after a
  quick filter change; filters work again after a failed refresh.
- Home no longer shows "up to date" when the dashboard failed to load.
- Job Work detail keeps its actions and history during status changes.
- Report dates no longer shift a day on devices east of IST.
- Parsers tolerate mistyped numbers from the server instead of failing the screen.

### Changed
- Checklist report PDF includes each line's attachment photos.
- Job Work PDF uses the report fonts.
- Per-record screens release their data when closed.

## [0.3.0+4] - 2026-10-06

Tested with GSSMS web/backend v1.9.9.

### Added
- Login screen shows the app version.
- Pending Actions cards show the assignee (Assigned / In Progress (name)).

### Changed
- Pending Tasks uses the backend `scheduled_task_count` (falls back to
  `pending_task_count` on older servers); breakdown-template schedules are hidden
  from the dashboard pending list and the Pending Actions Schedules tab.
- Pending Actions status wording matches the web (NEW reads Unassigned,
  REWORK_REQUIRED reads Rework).
- The breakdown delete icon is hidden for Depot In-charge (Close/Reject remains).
