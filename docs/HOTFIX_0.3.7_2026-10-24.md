# 0.3.7+12 offline data-loss hotfix

Status: signed artifact prepared and verified; no production installation or
external publication was performed by this task. A later read-only check found
the exact artifact already installed on the connected phone (0.3.7+12, update
time 14:08:56). See the [reacceptance report](OFFLINE_REOPEN_REACCEPTANCE_2026-10-24.md).

## Why release this separately

The installed 0.3.6 predates the latest-edit and queued-value restoration fixes.
Those fixes passed the original phone tests. They prevent an older partial
reading from replacing the final offline value and restore pending values from
the existing queue after a session is restored.

F1/F2 prevent the complete offline reopen journey but are not prerequisites for
delivering this narrower data-loss fix. F1/F2/F3 follow-up runtime changes are
excluded from this APK.

## Artifact

- APK: `build/releases/gssms-mobile-0.3.7+12-prod.apk`
- Source: `29edc81657c6a261da74b3d9763bc4281c73e2fc`, exported to an isolated
  source copy so concurrent workspace edits could not enter the build.
- Package/version: `com.ssee_vri.gssms_mobile`, 0.3.7, versionCode 12.
- SHA-256: `bc60c99cdd51bc19f37d863d1591182aa997fd0d53c7632a15de1bb36214684a`.
- Signing certificate SHA-256:
  `58c383f0fef111f6d6b4299031f5a3ca1a17446f996b4ac84cdbab6369e41c0f`.
  This is the existing GSSMS release identity; APK v2 verification passed.
- Build: locked dependencies, prod release flavor, `APP_ENV=prod`, existing
  default HTTPS backend. No test endpoint or new pin configuration was used.

The runtime source includes data fixes `69104a8` and `f5e0c83`, plus the prior
geolocator notification-permission/lint correction already on the branch. The
saved queue JSON format, command types and status codes are unchanged. No new
backend migration is introduced by this hotfix. Existing 0.3.6 workflow/backend
requirements remain in effect.

## Verification

- Exact isolated-source version and hotfix regression suites: **14 passed**.
- Earlier phone tests verified final numeric autosaves, persisted queues and
  read-time pending overlays; see `docs/PHONE_ACCEPTANCE_2026-10-24.md` for the
  limits and failed full-workflow acceptance.
- APK signature and package/version verified with Android Build Tools.
- ZIP integrity/case checks: pass. Native alignment: 21 libraries, zero
  reported problems. ZIP alignment check with `-P 16`: pass.
- A broader isolated rerun exhausted host memory and is not claimed as passed.
  The targeted rerun completed with one worker. This does not replace every
  release/field validation gate.

Local logs: `build/hotfix-037-final-targeted.log`,
`build/hotfix-037-signature.log`, `build/hotfix-037-prod-build.log`.

## Remaining limits

- Does not enable cold offline sign-in/restore or fix the missing offline
  checklist navigation button; those have separate commits and acceptance.
- Does not add backend duplicate-key enforcement or simultaneous-edit/version
  conflict resolution. Numeric-assignment repeat safety is not a guarantee for
  other line types, photos, start, status transitions or completion.
- No production phone update, production record mutation, remote push or
  external distribution was performed. The APK is ready for the existing
  distribution process; keep the existing signing identity for updates.
