# Changelog

All notable changes to the GSSMS mobile app are documented here.

Versioning: `MAJOR.MINOR.PATCH+BUILD`. BUILD is the Android versionCode and
increases with every distributed APK; PATCH is fixes and wording; MINOR is a
visible feature or change in what the app shows; MAJOR is a breaking change or
forced update. The app talks to the GSSMS web/backend; API changes are additive,
so older app builds keep working.

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
