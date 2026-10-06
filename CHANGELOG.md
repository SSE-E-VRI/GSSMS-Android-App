# Changelog

All notable changes to the GSSMS mobile app are documented here.

Versioning: `MAJOR.MINOR.PATCH+BUILD`. BUILD is the Android versionCode and
increases with every distributed APK; PATCH is fixes and wording; MINOR is a
visible feature or change in what the app shows; MAJOR is a breaking change or
forced update. The app talks to the GSSMS web/backend; API changes are additive,
so older app builds keep working.

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
