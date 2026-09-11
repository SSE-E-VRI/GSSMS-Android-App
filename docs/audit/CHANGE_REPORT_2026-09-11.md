# GSSMS Android — UI/UX, Quality & Dark Theme: Change Report

**Date:** 2026-09-11 · **Branch:** `fix/api-contract-checklist-template-conversion`
**Baseline:** `docs/audit/BASELINE_AUDIT_2026-09-11.md`

## Verification summary

| Check | Baseline | Now |
|---|---|---|
| `flutter analyze` | clean | **clean** |
| `flutter test` | 393 pass | **477 pass** (+84; 0 failing) |
| Layout harness (overflow at text scale 1.0/1.3/1.5) | 7 screens, light only | **7 screens × light + dark** with long-name fixtures |
| WCAG contrast tests | none | **every text token and tone pair measured ≥ 4.5:1 in both themes** |
| `dart run custom_lint` (bare `fontSize:`) | 250 warnings | **165** |
| Brightness-blind colour references in `lib/` (excl. PDF) | ~450 | **119**, all reviewed (white on the navy app-bar/identity bands, shadows, camera overlay) |
| Release APK (`flutter build apk --release --flavor prod --dart-define=APP_ENV=prod`) | 37.8 MB (10 Sep build) | **builds, 35.7 MB**. Note: plain `flutter build apk --debug` (as in `mobile_ci.yml`) reports a false failure because the project has flavours — Gradle does build all three debug APKs |

Not verified: no run on a physical device/emulator, no calls against a live backend, and the repository has no integration-test suite to run. Visual checks were done by rendering screens to PNG with real fonts in both themes.

## 1. Files changed
72 files in `lib/`, 19 in `test/` (see `git diff --stat`). Largest rewrites: Home, More, Job Work list/detail, Complaint list/detail, Inspection list/detail, checklist screen + line card, theme.

## 2. Files deleted
None. The five "unused" shared widgets found in the baseline (`StatusChip`, `SeverityChip`, `EmptyStateView`, `ErrorBanner`, `SectionHeader`) are now adopted by the screens rather than deleted.

## 3. New reusable components
| Component | Purpose |
|---|---|
| `core/theme/gssms_colors.dart` | `GssmsColors` ThemeExtension: text/border/surface tokens + 6 tone palettes (fg/bg/border/solid/onSolid); `context.gssms`, `context.moduleColor()` |
| `core/network/api_error.dart` | `userFacingError` / `classifyApiFailure` — SSOT §6/§42 error mapping |
| `core/sync/mutation_outcome.dart` | `MutationOutcome.synced/queued` for honest offline feedback |
| `core/widgets/section_card.dart` | `SectionCard`, `InfoRow` (stacks at large text), `TextWell` |
| `core/widgets/gssms_search_field.dart` | Search field (no per-keystroke screen rebuild), `FilterStrip`, `ListResultHeader` (count + Clear filters) |
| `core/widgets/sticky_action_bar.dart` | Bottom primary/secondary action bar (SafeArea, wraps instead of squeezing) |
| `core/widgets/skeleton_list.dart` | Static loading placeholders |
| `core/widgets/confirmation_dialog.dart` | Consequence-stating confirmation |
| `core/widgets/feedback.dart` | Tone snackbars with AA contrast |
| `core/domain/location_label.dart` | Web `getInfraName` location label |
| `*_status_style.dart` (work orders, complaints, inspections) | API value → label + tone + icon; linked Job Work progress |
| `assets/presentation/asset_scan_flow.dart` | Scan → exact-match resolve → open (SSOT §29) from anywhere |
| `auth/presentation/widgets/sign_out_confirmation.dart` | Sign-out guard that counts unsynced changes |

## 4. UI/UX improvements
- Detail screens lead with reference + status + title; primary action in a sticky bar (Complaint/Inspection convert, Job Work start/checklist/transitions).
- Every list: status on every card, skeleton first load, error banner over stale rows, empty states with **Clear filters**, result counts, stale-while-refresh on pull-to-refresh.
- Consequence-stating confirmations (convert, transitions, delete photo, sign out).
- Terminology aligned to Web: "Job Work(s)", `TECH_COMPLETED` → "Technician Completed", Web location labels, `#id` references.
- Appearance selector (System / Light / Dark) added to More — the theme was previously system-only with no UI.
- Checklist: "N required item(s) left" grammar, completion sheet with grouped fields, replaced asset/component notes now carried into the closing remarks instead of discarded.
- Form labels: `RichText` → `Text.rich` (scales with the user's font size).

## 5. Dark theme
Seed-derived dark `ColorScheme` (the light brand blue is no longer the dark primary), slate surfaces (no pure black), `#E2E8F0` body text (no pure white), and component themes for app bar, tabs, cards, inputs, all button types, chips, dialogs, sheets, snackbars, navigation bar, list tiles, progress, checkbox, popup menus. Tone palettes are designed per theme; a unit test measures every pair.

## 6. Bugs fixed
| ID | Bug |
|---|---|
| B1/B2 | Raw `DioException`/`TypeError` text reached the UI in ~20 places; HTML error pages were shown verbatim; 401/403/404/409/429/5xx not distinguished |
| B3 | One-tap Sign Out silently wiped unsynced offline work |
| B4 | Outbox never drained on app start / resume |
| B5 | Home "Scan Asset" discarded the scan; chip shown without `assets.view` |
| B6 | Job Work date/org filter changes dropped type/infra filters; out-of-order responses could overwrite newer filters (also fixed in Complaint/Inspection lists) |
| B7 | Complaint/Inspection cards showed no status |
| B8 | `WO #TLNR-…` double prefix; detail title showed the DB id |
| B9 | Job Work action bar white in dark mode, no SafeArea, 3–4 actions squeezed into one row |
| B10 | "Offline" shown while online after restart |
| B11 | **Every server timestamp displayed 5 h 30 m early** (offset-bearing ISO parsed to UTC and formatted as-is) |
| B12 | Offline line saves and completion reported as "Saved" / "completed successfully" when only queued; completion could race ahead of its queued proof photo |
| B13 | A second raw "Start" button bypassed the execute endpoint (no maintenance record created) |
| B14 | Replaced asset/component entries were validated then discarded |
| B15 | QR scanner kept the camera running when the app was backgrounded |
| C1–C3 | Fabricated "Medium" severity/priority on every complaint/inspection; complaint asset always "—"; invented `CMP-`/`INSP-` numbers |

## 7. Dead code removed
`ComplaintSeverity`, `InspectionPriority`, reads of non-existent serializer fields (`complaint_number`, `severity`, `asset_name`, `reported_by_name`, `resolved_at`, `inspection_number`, `priority`, `completed_date`), 8 per-screen status/priority colour functions, 3 copies of the list error banner, duplicated fetch paths in three list controllers, the old `workOrderReadableError` body.

## 8. Performance
- No `IntrinsicHeight` per Job Work card / audit row (removed a second layout pass while scrolling).
- Thumbnails decoded at display size (`cacheWidth`) instead of full 12 MP camera frames; no synchronous `File.existsSync()` in `build`.
- Search fields no longer rebuild the whole screen per keystroke.
- Department lookup cached per session (`lookupOptionsProvider`); Home refresh runs its two requests in parallel.
- Stale-response guards prevent wasted state churn on rapid filter changes.

## 9. Accessibility
Status is icon + label (never colour alone) with spoken prefixes; section headers marked as headers; live regions for sync and error banners; 48 dp targets for date chips, retry, submit buttons; labels scale with font size; measured AA contrast.

## 10. Tests added/changed
New: `api_error_test` (error table), `gssms_colors_test` (contrast matrix), controller tests for filter preservation, stale responses, queued saves/completion ordering, home sign-out guard (confirm/cancel/unsynced warning), model tests for serializer-shaped fixtures and timezone conversion; layout harness extended to dark theme. Changed: fixtures that used non-contract fields, copy changes.

## 11. API contract changes
**No API contract changes.** No request field, enum value, endpoint, filter or lifecycle call was added or altered. Model changes are read-side only and bring parsing in line with `ComplaintSerializer` / `InspectionSerializer` (SSOT §10.1, §11.1). Replaced-asset notes travel inside the existing `complete.remarks` field.

## Regression checklist (§39)
Verified by automated tests: login/OTP screens, logout (+guard), token-refresh interceptor, dashboard load, complaint/inspection list, filters, create, detail, conversion, asset list/search/QR resolution, Job Work list/detail/assign/start/checklist/evidence/completion/verification, offline queue, retry, duplicate protection (idempotency keys), light/dark/system theme, loading/empty/error states, controller disposal.
Not verified here: on-device behaviour, live backend, camera hardware, process-death recovery on a real device.

## Remaining recommendations
- Migrate the remaining 165 bare `fontSize:` sites to the type scale (lint already flags them).
- Screens migrated by codemod (dashboard, reports, pending actions, verification, profile, OTP) are dark-mode correct but have not had a layout redesign.
- Add an integration-test target (`integration_test/`) for the Job Work execution path on an emulator.
