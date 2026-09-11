# GSSMS Android — Baseline Audit (Phase A)

**Date:** 2026-09-11 · **Branch:** `fix/api-contract-checklist-template-conversion` @ `4ceae84` · **Version:** 0.2.0+3
**Contract:** `SSOT/GSSMS_API_CONTRACT_SSOT.md` (baseline 2026-09-09) · **Backend/Web reference:** `GSSMS/backend`, `GSSMS/frontend`

## 1. Toolchain baseline

| Check | Result |
|---|---|
| Flutter / Dart | 3.24.5 / 3.5.4 (pinned via `.fvmrc`) |
| `flutter analyze` | **No issues** |
| `flutter test` | **393 / 393 pass** (72 test files, incl. text-scale golden tests) |
| `dart run custom_lint` | **250 warnings**, all `avoid_bare_font_size`; 0 `avoid_hardcoded_color` |
| Source size | 131 Dart files, ~30.5k lines in `lib/` |

The colour lint only catches `Color(0x…)` literals, so it reports zero while screens hold
~450 brightness-blind colour references (see §4).

## 2. Architecture

- **State:** Riverpod 2 (`Notifier`/`FamilyNotifier`), sealed-ish state classes per feature (`*Loading / *Loaded / *Error(previousLoaded)`), stale-data-with-banner pattern on list errors.
- **Layers:** `features/<x>/{data (api_service, repository), domain/models, presentation/{controllers, screens, widgets}}`, `core/{network, sync, database, theme, widgets}`.
- **Network:** Dio + `AuthInterceptor` (refresh with retained refresh token), HTTPS guard in prod, `fetchAllPages` follows server `next` links with a page cap and `truncated` flag.
- **Offline:** SharedPreferences-backed cache + durable outbox (`OutboxCommand`, idempotency keys, per-user ownership, session epoch, FAILED/CONFLICT attention state).
- **Navigation:** imperative `Navigator.push(MaterialPageRoute)`; `HomeScreen` = `IndexedStack` + M3 `NavigationBar` (Home / Work / Assets / More), RBAC-filtered.
- **Theme:** `AppTheme` static constants + `lightTheme`/`darkTheme`; `themeModeProvider` persisted (System/Light/Dark) — switching works without restart.
- **Design tokens present but unused:** `GssmsSpacing`, `GssmsRadius`; shared `StatusChip`, `SeverityChip`, `EmptyStateView`, `ErrorBanner`, `SectionHeader` are **imported by zero screens** (tests only).

## 3. API contract spot-check (read side)

No outbound payload violations found in this pass (FIX-001…008 already applied and tested). Read-side
mismatches against the serializers in `GSSMS/backend`:

| # | Finding | Evidence | Impact |
|---|---|---|---|
| C1 | `Complaint.severity` parsed from a field the backend does not have; defaults to MEDIUM | `complaints/models.py` has no severity; SSOT §10.6, FIX-002 | Every complaint card/detail shows a fabricated **"Medium"** badge |
| C2 | `Inspection.priority` parsed from non-existent `priority`/`severity`; defaults to MEDIUM | `inspections/models.py`; SSOT §11.3 | Every inspection card/detail shows a fabricated **"Medium"** badge |
| C3 | Complaint reads `asset_name`, `complaint_number`, `reported_by_name`, `resolved_at` — none are serialized | `ComplaintSerializer` | Asset always "—"; reference is a made-up `CMP-{id}` |
| C4 | Contract fields ignored: complaint `department`, `infrastructure_name`, `asset_unique_id`, `wo_ticket_number`, `wo_status`; inspection `infrastructure_name`, `created_by_first/last_name` | SSOT §10.1, §11.1 | Web shows these; Android cannot |

These are display-only; fixing them changes no request payload.

## 4. Dark theme

| Defect | Scale |
|---|---|
| Dark `ColorScheme` pins `primary` to `#0F4C81` (light-theme brand blue) | Primary-coloured text/icons ≈1.9:1 on dark surfaces |
| `textPrimary`/`textDark` (`#1E293B`) used as text colour; dark card colour is also `#1E293B` | **Invisible text** — e.g. Home "Operational Modules", module titles, complaint detail fields (29 sites) |
| `textSecondary`/`textMuted` hard-wired light-theme grey | 132 sites |
| `Colors.white` as surface (filter strips, bottom action bars, scanner error view) | 60 sites → white bands in dark mode |
| `backgroundLight`, `surfaceCard`, `borderGrey`, `Colors.grey.shadeNNN` | ~80 sites |
| White text on amber/orange/teal status chips | fails WCAG AA in both themes |

## 5. Bugs found

| ID | Severity | Bug |
|---|---|---|
| B1 | High | Raw exceptions still reach the UI: ~20 sites interpolate `$e`/`e.toString()` (`'Failed to load complaints: $e'`, `WorkOrderListError(e.toString())`, checklist load/save, dashboard, assets, reports, PDF, photo) → users see `DioException [connection timeout]: … RequestOptions…` (SSOT §6) |
| B2 | High | Error mapper shows an HTML/plain-text body verbatim (e.g. a proxy 502 page) and does not distinguish 401/403/404/409/429/5xx (SSOT §42) |
| B3 | High | One-tap **Sign Out** (next to the bell) wipes the offline outbox — unsynced checklist readings/photos are lost with no warning |
| B4 | High | Outbox never drains on app start or on resume; queued work waits until another mutation or a manual tap |
| B5 | Medium | Home **Scan Asset** discards the scan result — scanning does nothing; chip also shown without `assets.view` |
| B6 | Medium | `WorkOrderListController.setDateRange/setOrgScope` rebuild state without type/infra filters → filters silently dropped while dropdowns still show them; no stale-response guard on rapid filter changes |
| B7 | Medium | Complaint/Inspection list cards show no status badge (only the fabricated severity/priority) |
| B8 | Low | `'WO #${ticketNumber ?? id}'` renders `WO #TLNR-202608-0015`; detail app bar shows `Work Order #<db id>` instead of the ticket |
| B9 | Low | Work-order bottom action bar: white in dark mode, no `SafeArea`, 3–4 server actions squeezed into one `Row` |
| B10 | Low | Sync strip says "Offline — N queued" while online after a restart |

## 6. UX / semantics

- **Terminology:** Web says "Job Work" 132× vs "Work Order" 1×; Android still shows "Work Order(s)" in 14 visible strings.
- **Confirmations:** "Are you sure you want to convert…?" style copy; no consequence stated.
- **Status meaning is colour-only** in 8 per-screen `_statusColor` implementations (no icon/glyph).
- **Loading:** full-screen spinners everywhere; list skeletons absent.
- **Empty states:** plain centred `Text` (no icon, no clear-filters action).
- **Search:** complaint/inspection/WO lists `setState` the whole screen on each keystroke to toggle the clear icon.

## 7. Performance / resources

- Lists are lazy (`SliverList`/builders) — good. `DateFormat` re-created per card build; minor.
- Controllers/FocusNodes/scanner are disposed correctly (checked all 16 files that create them).
- QR: single-shot guard present; `mobile_scanner` 5 controller keeps camera running while in manual-entry mode.

## 8. Plan (highest value first)

1. **Design system + dark theme** — `GssmsColors` `ThemeExtension` (semantic text/surface/border/status tokens for light & dark), corrected dark `ColorScheme`, full component themes; one `status_semantics` mapping (API value → label + tone + icon); adopt `StatusChip`/`EmptyStateView`/`ErrorBanner`.
2. **Bugs B1–B10** with regression tests (central `userFacingError`, sign-out guard, drain on start/resume, scan flow, filter-preserving list controller).
3. **Screen migration** to tokens, module by module (Home → Work Orders → Checklist → Complaints → Inspections → Assets → Dashboard/Reports/Auth), fixing C1–C4 and terminology as each module is touched.
4. Tests: dark-theme widget tests, error-mapper table tests, contract payload tests kept green.
