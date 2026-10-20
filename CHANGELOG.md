# Changelog

All notable changes to the GSSMS mobile app are documented here.

Versioning: `MAJOR.MINOR.PATCH+BUILD`. BUILD is the Android versionCode and
increases with every distributed APK; PATCH is fixes and wording; MINOR is a
visible feature or change in what the app shows; MAJOR is a breaking change or
forced update. The app talks to the GSSMS web/backend; API changes are additive,
so older app builds keep working.

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
