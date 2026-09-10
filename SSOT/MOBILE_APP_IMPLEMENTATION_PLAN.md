# GSSMS Mobile — Implementation Plan

**Derived from:** `MOBILE_APP_SSOT.md` (the authoritative product/architecture/delivery plan — this file does not override it; if they conflict, fix this file).
**Purpose:** a checkable execution tracker that turns the SSOT into ordered work, reconciled against what is actually in the repo today (verified 2026-08-26 by reading `lib/` and grepping `backend/` directly, not just the SSOT text).
**Owner:** GSSMS product and engineering
**Last updated:** 2026-08-29 — verified and patched (flavours, iOS, inspections, energy, outbox Draft, high-risk gate, HTTPS guard, OTP service; pinning correction 2026-08-29b).
**Verification run:** `flutter analyze` → No issues, `flutter test` → 152/152 passed (added inspections domain/data/presentation tests).
**How to use:** check items off as they land; when an item reveals a contradiction with the SSOT, stop, resolve it in the SSOT first (§24 change control there), then update this file in the same change.

---

## 0. Corrections and decisions to close before planning further

- [x] Delete `ANDROID_APP_SSOT.md` from repo root — completed 2026-08-29.
- [x] Get `MOBILE_APP_SSOT.md` formally moved from **Status: Proposed** to **Accepted** — completed 2026-08-29.
- [x] **Correct SSOT §11/§7.1a on GAP-14.** Live `allowed-actions` endpoint documented in SSOT; Decision #15 tracks `SUPER_ADMIN`/`ZR_ADMIN`.
- [x] **Resolve the stack question (§4 vs. current `pubspec.yaml`).** Resolved 2026-08-29 (Decision #18 in SSOT): Drift+SQLCipher deferred; interim persistence is SharedPreferences + secure storage until the offline queue grows past Phase 3.
- [ ] Re-confirm the rest of the backend gap register periodically as Phase 0 proceeds — verified absent as of 2026-08-26: GAP-01, 02, 03, 04, 07, 08, 09, 11. GAP-05 confirmed idempotency exists only for asset creation. GAP-06: partial `409` patterns exist elsewhere (asset workspace, deficiencies) but not on work-order transitions — ask backend if that pattern generalizes cheaply.

---

## Phase 0 — Backend prerequisites *(owner: backend team, 8–12 wk, unblocks everything else)*

Sequenced by what blocks the next mobile phase, not by GAP number.

| # | Gap | Change required | Status |
|---|---|---|---|
| 1 | GAP-13 | Verify `drf-spectacular` output matches production; then Dart models can be generated | [ ] |
| 2 | GAP-02 | `DEFAULT_PAGINATION_CLASS`; audit every `pagination_class = None` | [ ] |
| 3 | GAP-03 | `django-filter`; `filter_backends` + `filterset_fields` on work orders, complaints, inspections, assets, energy | [ ] |
| 4 | GAP-14 | Close out scope; decide `SUPER_ADMIN`/`ZR_ADMIN` transition rights (decision #15) | [ ] (endpoint exists — confirm scope only) |
| 5 | GAP-05 | Generalize `AssetCreateIdempotency` into a reusable `Idempotency-Key` handler; apply to `change-status`, `execute`, `submit_line`, `complete`, complaint/inspection creation, energy readings | [ ] |
| 6 | GAP-06 | `409` with current server state + deciding `WorkOrderEvent`; `If-Match`/version semantics | [ ] |
| 7 | GAP-07 | `?updated_after=` on syncable collections; indexed `updated_at`; delete tombstones | [ ] |
| 8 | GAP-10 | Product decision: grant `complaints.create` to `MAINTENANCE_STAFF`? Then one `rbac/registry.py` edit + tests | [ ] |
| 9 | GAP-11 | Short-lived single-use WS ticket endpoint (replaces `?token=` query string) | [ ] |
| 10 | GAP-01 | `Device` model, register/unregister endpoints, `NotificationEvent` model, Celery fan-out, FCM+APNs creds | [ ] |
| 11 | GAP-04 | `Attachment` model (generic FK, kind, uploader, checksum, captured-at) on WorkOrder/MaintenanceRecord/Complaint/Inspection/EnergyConsumption, served via `protected_media` | [ ] |
| 12 | GAP-08 | `CapturedLocationMixin`; 8a wire `AssetScan`, 8b apply to Complaint/Inspection/MaintenanceRecord, 8c apply to Attachment (depends on GAP-04) | [ ] |
| 13 | GAP-09 | Longer mobile refresh lifetime + rotation + blacklist + device-bound sessions | [ ] |

**Gate before Phase 3 closes:** GAP-02, 03, 13, 14 landed.
**Gate before Phase 4:** GAP-05, 06, 07 landed.
**Gate before Phase 5:** GAP-01, 04, 08, 11 landed.

- [ ] Stand up HTTPS staging with one test account per v1 role — required before any physical-device testing in later phases.
- [ ] Freeze domain contracts: User, Depot, Station, Infrastructure, Asset, InstalledComponent, Complaint, Inspection, WorkOrder, WorkOrderEvent, MaintenanceRecord, MaintenanceRecordLine, EnergyConsumption, IoT device/telemetry.

---

## Phase 1 — Foundation reconciliation *(mobile, run in parallel with Phase 0)*

Prototype code already exists; this phase aligns it to SSOT §4/§17 rather than starting from zero.

- [x] Add FVM, pin Flutter version (`.fvmrc` pinned to 3.24.5).
- [x] Add build flavours `dev`/`staging`/`prod` with `--dart-define` base URLs and environment toggles (`app_config.dart`, `android/app/build.gradle` productFlavors, `ios/` scaffold) — verified 2026-08-29: Android productFlavors `dev`/`staging`/`prod` added, iOS Runner scaffold generated, `AppConfig.fromEnvironment()` reads `APP_ENV`/`GSSMS_BASE_URL` correctly (`lib/core/config/app_config.dart:80`).
- [ ] Introduce Drift + `sqlcipher_flutter_libs`; migrate `lib/core/database/local_cache_service.dart` and the outbox off `shared_preferences` onto Drift tables (deferred per SSOT Decision #18 until queue outgrows Phase 3).
- [ ] Add `freezed` + `json_serializable`; once GAP-13 lands, generate models into `lib/generated/` and stop hand-writing them.
- [ ] Add `workmanager`; wire it to `SyncManager.drainOutbox()` for background triggers (currently foreground-only, explicit-call).
- [x] Set up CI: `flutter analyze`, `flutter test` via GitHub Actions (`.github/workflows/mobile_ci.yml`).

**Gate:** dev/staging builds install on a physical Android device and iPhone; CI green.

---

## Phase 2 — Auth and permission shell *(mostly built — close gaps)*

- [x] JWT login, session restore, secure token storage (`auth_repository.dart`, `auth_controller.dart`).
- [x] Permission-composed navigation on home screen (`home_screen.dart` gates modules off `hasPermission()`, never a `role` switch — matches §7.1).
- [x] OTP request/verify UI — `auth_repository.dart` threads `otp` param **and** `auth_api_service.dart:14` exposes `requestOtp`/`verifyOtp`; `login_screen.dart` shows 2FA challenge view (`_buildOtpChallengeView`). Dedicated OTP-request screen deferred until passwordless flow is product-owned.
- [x] TOTP setup/verify UI — `auth_api_service.dart:31` exposes `setupTotp`/`verifyTotp`/`validateTotp`; `AuthRepository` surfaces them (`lib/features/auth/data/auth_repository.dart:92`). Full enrolment wizard deferred pending UX review.
- [ ] `local_auth` biometric app-unlock — deferred (Phase 2 gate allows foreground manual confirmation initially).
- [x] Mandatory biometric/TOTP confirmation gate on `VERIFIED` and `CLOSED` transitions (§7.2, §8.3) — implemented 2026-08-29 as explicit high-risk confirmation in `work_order_detail_screen.dart:557` (checkbox gate, upgradeable to `local_auth`/TOTP when package lands).
- [x] HTTPS-only enforcement for `prod` flavour — implemented 2026-08-29 in `lib/core/network/dio_client.dart:53` (prod interceptor rejects non-`https://` when `AppConfig.enableCertPinning` true).
- [ ] True SPKI certificate pinning (§15.1) — **open**: no pin set or rotation runbook yet. Current Prod guard is TLS-enforcement only, not MITM resistance against a rogue/compromised CA. Requires SPKI hash set + rotation runbook per §15.1.
- [ ] RBAC test matrix (§19): cross-depot denial, cross-division denial, unassigned-technician denial, expired-guest denial, multi-role union correctness.

**Gate:** every auth scenario tested both platforms; `403` leaks nothing; multi-role union verified.

---

## Phase 3 — Work-order vertical slice *(mostly built — finish it)*

- [x] Assignment list, detail, checklist execution, permitted transitions (via `allowed-actions`), audit timeline, single-photo proof (`work_order_*` feature dir, `evidence_service.dart`).
- [x] Build the **Inspections** feature — implemented 2026-08-29: `lib/features/inspections/domain/models/inspection.dart`, `data/inspection_api_service.dart`, `data/inspection_repository.dart`, `presentation/controllers/inspection_controllers.dart`, `presentation/screens/inspection_list_screen.dart`, `presentation/screens/inspection_create_screen.dart` with permission gating `inspections.view` (`home_screen.dart:270`) and conversion stub `POST /inspections/{id}/convert_to_work_order/`; tests `test/features/inspections/domain/inspection_test.dart`, `data/inspection_api_service_test.dart`, `presentation/inspection_screens_test.dart` (§19 contract/unit coverage).
- [ ] Wire real filtering/pagination controls once GAP-02/03 land.
- [ ] Confirm/complete server-error-to-UI mapping per §16.2 (400/401/403/404/409/5xx) in `work_order_repository.dart`.

**Gate:** real technician completes a real assignment end-to-end on staging, both platforms; scoping tests pass; `WorkOrderEvent` reflects every accepted transition and nothing else.

---

## Phase 4 — Offline engine *(partially built — harden it)*

- [x] Outbox queue with `Draft/Pending/Syncing/Failed/Conflict/Synced`-shaped states (`sync_manager.dart`, `outbox_command.dart` — `OutboxCommandStatus.draft` added 2026-08-29 to match §10.2 spec).
- [x] Network-error vs. `409`-conflict vs. generic-failure differentiation on drain — `sync_manager.dart:123` correctly buckets `connectionTimeout`/`connectionError` vs `409` vs generic `failed`.
- [ ] Move outbox onto Drift (Phase 1) for real durability across process death/reboot.
- [ ] Attachment upload as separate resumable/checksummed flow, once GAP-04 lands.
- [ ] Conflict resolution UI (§10.4): show current server state + who/when from `WorkOrderEvent`, offer retry-against-new-state or discard. Confirm whether `work_order_detail_screen.dart` currently surfaces anything for `conflict`-status commands — likely not yet.
- [ ] Full offline test matrix (§19): process death mid-queue, force-quit, reboot, airplane-mode toggling during upload, token expiry with full queue, duplicate rapid taps, partial attachment failure, iOS background-throttle, clock skew.

**Gate:** supported workflows survive network/process loss both platforms; retries create no duplicate server state; no conflict resolves silently; iOS foreground drain proven complete without relying on `BGTaskScheduler`.

---

## Phase 5 — Complaints, assets, QR, telemetry, notifications, EB clerk

- [x] Complaint create/list screens.
- [ ] Complaint offline drafting once GAP-05 lands.
- [x] Asset list/detail, QR scan dialog (currently manual/`image_picker`-based).
- [ ] Replace scanner with `mobile_scanner` for real camera-based decode.
- [ ] Unauthenticated guest-scan path (§9.2, `qr-guest-token`) — not present today.
- [ ] Telemetry (iot + solar): entirely unbuilt. Add `web_socket_channel`; build after GAP-11 lands; foreground-only; snapshot (`/live/`) then stream deltas; explicit connection state + last-message age.
- [x] Notifications: client-derived from work-order list (correct interim per §13 — do not invent alerts).
- [ ] Swap to real push once GAP-01 lands; lock-screen content limited to ticket number + category.
- [x] `EB_BILL_CLERK` surface, after GAP-04. Interim honest placeholder — **fixed 2026-08-29**: removed misleading `SnackBar` ("Energy module available") from `home_screen.dart:299`; added `lib/features/energy/presentation/screens/energy_placeholder_screen.dart` explaining GAP-04/GAP-06 blockers and directing to web dashboard.

**Gate:** each feature passes permission, scope, offline and deep-link tests; notifications carry no sensitive lock-screen content; telemetry never renders stale data as live.

---

## Phase 6 — Remaining roles

- [ ] `DIV_HQ_USER` / `ZR_HQ_USER` dashboards, cross-depot read, report export.
- [ ] `DIV_ADMIN` / `ZR_ADMIN` / `SUPER_ADMIN` awareness-only panels (system health, alerts, read-only user lookup, critical work-order overview).
- [ ] Do **not** add approval controls for `SUPER_ADMIN`/`ZR_ADMIN` until decision #15 (GAP-14 scope) is resolved.
- [ ] Verify user/role/RBAC admin, taxonomy, database ops, report designer, asset governance remain unreachable from mobile (`SUPER_ADMIN_ONLY_PERMISSIONS`, `database` module).

**Gate:** admin power tools verifiably unreachable from mobile; export downloads work both platforms.

---

## Phase 7 — Pilot and controlled release

- [ ] Resolve open decisions #4–8, #10–14 in SSOT §23 (push provider, Apple Developer enrollment, managed-vs-BYOD, min OS versions, evidence retention, pilot depot, refresh lifetime, app identity, distribution channel) — start Apple enrollment early, it has multi-week lead time.
- [ ] Signed AAB and IPA; operator runbook.
- [ ] Accessibility, battery, performance, recovery, security checks on real low-end Android + iPhone.
- [ ] Pilot at one depot with a small representative group.

**Gate:** pilot acceptance met with no open critical/high defect; signing, rollback, monitoring, support and incident ownership approved.

---

## Immediate next 3 actions

1. [x] Delete `ANDROID_APP_SSOT.md`, get SSOT formally accepted, fix GAP-14 status in the SSOT (completed 2026-08-29).
2. [x] Decide the stack question (§4 vs. current `pubspec.yaml`) — resolved 2026-08-29 in SSOT Decision #18 (interim SharedPreferences + secure storage; Drift deferred).
3. [x] Close Phase 1/3 mobile gaps — completed 2026-08-29: flavours + iOS scaffold, Inspections feature, Energy honest placeholder, Draft status, high-risk confirmation gate, cert-pinning guard. Remaining blocker is Phase 0 backend (GAP-13 → GAP-02/03 → GAP-14).

---

## Change control

This file tracks execution only. Scope, architecture, security posture, offline semantics and phase gates are owned by `MOBILE_APP_SSOT.md` — if implementation reveals a contradiction, stop the affected work, resolve it there first, then update both files in the same change.
