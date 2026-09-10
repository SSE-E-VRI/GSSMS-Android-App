# GSSMS Mobile Application — Single Source of Truth

**Status:** Accepted
**Supersedes:** `ANDROID_APP_SSOT.md` (deleted 2026-08-29).
**Owner:** GSSMS product and engineering
**Last updated:** 2026-08-29
**Repository location:** `mobile/`
**Canonical rule:** This file is the authoritative product, architecture and delivery plan for the GSSMS mobile application on Android and iOS. Any later mobile decision updates this file rather than creating a parallel plan.

**Owning documents referenced, not duplicated:**
`docs/api_manual.md` (HTTP contracts) · `docs/RBAC_MANUAL.md` and `backend/rbac/registry.py` (roles, permissions, scope) · `docs/🏗️ GSSMS – System Architecture Reference.md` (platform architecture).

---

## 1. Objective

Build one secure, offline-capable Flutter client for Android and iOS that serves GSSMS field and supervisory operations. Django remains the sole authority for authentication, RBAC, organisational scope, workflow transitions, validation and audit history.

The mobile application is a **field-operations client**, not a mobile rendering of the React web application. The web application keeps master data, configuration, taxonomy, RBAC administration, database operations, dense analytics and report design. Mobile takes the work that happens away from a desk: executing assignments, capturing evidence, raising and approving records, scanning assets, and glancing at live plant status.

### 1.1 The single design rule

> If the task requires a keyboard, a wide table or a decision made with ten columns in view, it stays on web.
> If the task happens standing in front of an asset, it belongs on mobile.

Every scope argument in this document resolves against that rule.

---

## 2. Verified baseline — what the repository actually provides

This section is the factual floor for every plan below. Each row was read from source in this repository, not inferred.

### 2.1 Ready to consume as-is

| Capability | Evidence in repo |
|---|---|
| Versioned REST surface `/api/v1/` | `backend/gssms_project/urls.py` — every app mounted under `api/v1/`; a legacy unversioned `/api/` mount also exists and **must not** be used by mobile |
| JWT authentication with rich claims | `accounts/serializers.py::MyTokenObtainPairSerializer.get_token` — emits `role`, `roles[]`, `permissions[]` (or `["*"]`), `scope{level,zone,division,depot}`, `depot_id`, `depot_name`, `has_2fa`, `valid_until` |
| OTP and TOTP flows | `/api/v1/auth/otp/request/`, `/auth/otp/verify/`, `/auth/totp/setup/`, `/auth/totp/verify/`, `/auth/totp/validate/` (`accounts/urls.py`) |
| 11-role RBAC with 5-level scope | `rbac/registry.py::CANONICAL_ROLES`; scope `GLOBAL > ZONE > DIVISION > DEPOT > SELF` anchored on `User.org_zone` / `org_division` / `org_depot` |
| Server-enforced work-order state machine | `maintenance/services/workorder_lifecycle_service.py::TRANSITION_MAP`; `WorkOrder.save()` raises `ValidationError` if status changes outside `WorkOrderLifecycleService.transition()` |
| Append-only work-order audit log | `maintenance/models.py::WorkOrderEvent` — documented in source as the single source of truth for reporting and audit |
| Asset QR generation and scan lookup | `assets/views.py` — `{id}/qr`, `{id}/label-pdf`, `by-code/{unique_id}`; signed scan code via `assets/utils.py::sign_asset_scan_code` |
| Unauthenticated QR guest scan | `POST /api/v1/accounts/qr-guest-token/` returns a JWT locked to one asset via the `qr_asset_id` claim; throttled `20/hour` (`settings.REST_FRAMEWORK.DEFAULT_THROTTLE_RATES`) |
| Live + historical telemetry | `GET /api/v1/v3/devices/{id}/live/`, `/history/`; `GET /api/v1/v3/solar/{plant_id}/live/`, `/history/` |
| Telemetry WebSockets | `ws/v3/devices/{device_id}/` and `ws/v3/solar/{plant_id}/` (`iot_v3/routing.py`, `solar_v3/routing.py`), authenticated by `accounts/middleware.py::JWTAuthMiddleware` |
| Scope-checked media serving | `documents/views.py::protected_media` — object-level scope check before the file is served, with optional `X-Accel-Redirect` |
| Energy / TANGEDCO CRUD | `/api/v1/energy/service-connections/`, `/consumption/`, `/history/` |
| Aggregated dashboards | `/api/v1/analytics/dashboard/`, `/analytics/energy/`, `/analytics/asset_dashboard/`, `/analytics/location-performance/` |
| Digital signature groundwork | `maintenance/models.py::MaintenanceSignature` — base64 technician and supervisor signatures on a maintenance record |
| Async task runner for future push fan-out | `celery==5.5.3` in `backend/requirements.txt`, `gssms_project/celery.py` |

### 2.2 Absent — and required before the corresponding mobile feature ships

| Missing capability | Verification | Blocks |
|---|---|---|
| **Any notification model or push infrastructure** | Repo-wide grep for `fcm`, `firebase`, `apns`, `device_token`, `class Notification` returns **zero** matches in `backend/` | All push notification features in every prior draft |
| **Idempotency for anything except asset creation** | Only `assets/models.py::AssetCreateIdempotency` exists (unique on `user`+`key`). No idempotency on work-order transitions, checklist lines, complaints, inspections or energy readings | Safe offline mutation replay |
| **Default pagination** | `REST_FRAMEWORK` in `settings.py` sets no `DEFAULT_PAGINATION_CLASS`. `WorkOrderViewSet` declares no `pagination_class`; many viewsets set `pagination_class = None` explicitly | Every list screen on a metered/2G connection |
| **Any filtering or search backend** | Repo-wide grep for `filter_backends`, `DjangoFilterBackend`, `django_filters` returns zero matches; `django-filter` is not in `requirements.txt` | Server-side filtering; forces the client to over-fetch |
| **Delta-sync parameters** | Grep for `updated_after`, `modified_since` returns zero matches. No `ETag` or `Last-Modified` handling anywhere | Incremental sync; forces full re-download each cycle |
| **Multi-photo evidence on work orders** | The only maintenance image field is `MaintenanceRecord.proof_of_execution` — a **single** `ImageField`, validator restricts to `image/jpeg` at ≤5 MB | "Before / during / after" evidence in drafts 1 and 4 |
| **Any attachment on complaints or inspections** | `complaints/models.py::Complaint` and `inspections/models.py::Inspection` have no `FileField` or `ImageField` | Photo-backed complaint logging in every prior draft |
| **GPS field on any operational record** | No latitude/longitude/accuracy field on Complaint, Inspection, WorkOrder, MaintenanceRecord or MaintenanceRecordLine. `assets/models.py::AssetScan` **does** carry `lat`, `lon`, `scanned_at`, `synced_at` — but nothing writes it; see §2.3 | Geotagged proof-of-presence in drafts 1, 3, 4 |
| **WebSocket channels for CMMS events** | ASGI router (`gssms_project/asgi.py`) mounts **only** `iot_v3` and `solar_v3` patterns | Live work-order / complaint / alert streams claimed in drafts 2, 3, 4 |
| **Refresh-token rotation or blacklist** | `SIMPLE_JWT = {'ACCESS_TOKEN_LIFETIME': 60 min, 'REFRESH_TOKEN_LIFETIME': 1 day}` — nothing else configured | Remote session revocation; multi-day offline field work |

### 2.3 Dormant mobile groundwork already in the schema

`assets/migrations/0016_qr_groundwork.py` created two models that anticipate exactly this project, and application code writes neither:

- **`AssetScan`** — `asset`, `user`, `lat`, `lon`, `scanned_at`, `synced_at`. A scan-event log with coordinates and a **sync marker**. This is the closest thing GSSMS has to proof-of-presence, and `synced_at` shows it was designed for an offline client. Nothing references it outside tests.
- **`AssetCreateIdempotency`** — `user` + `key` unique, with an expiry. The reusable idempotency handler GAP-05 needs is a generalisation of this, not a new invention.

Reviving `AssetScan` is the cheapest possible first delivery of GAP-08: the table, the columns and the sync field already exist and are migrated. Every QR scan (§9) writes one row, giving "this technician stood at this asset at this time" independently of whether a photo was taken. Note the scope limit — it records the **scan**, not the photo and not the observation.

### 2.4 The one architectural risk to fix early

`accounts/middleware.py::JWTAuthMiddleware` reads the JWT from the WebSocket **query string** (`?token=…`). Query strings land in proxy logs, browser history and crash reports, and the superseded Android SSOT's own §5.3 forbids tokens in URLs. Before mobile telemetry ships, move WebSocket authentication to a short-lived single-use ticket (`POST /api/v1/v3/ws-ticket/` → opaque token, valid ~30 s, one connection) or to a `Sec-WebSocket-Protocol` subprotocol header. Recorded as **GAP-11** in §11.

---

## 3. Corrections to the five prior idea drafts

The drafts contain good architecture and several factual errors. This SSOT resolves them; the corrected value is binding.

| Claim in a prior draft | Reality in this repository |
|---|---|
| "GSSMS has 7 roles" (drafts 1, 4, 5) | **11 canonical roles** in `rbac/registry.py`, plus legacy aliases `ADMIN→DIV_ADMIN`, `HQ_USER→DIV_HQ_USER`, plus two non-canonical entries in `DEFAULT_ROLES`: `VIEWER` and `QR_GUEST`. Draft 2's list of 11 is correct |
| "GSSMS = Grid Substation Safety Management System" (draft 3) | **General Service Smart Management System** (`README.md`). Draft 3's OSHA/NERC compliance framing, blockchain audit ledger and CRDT sync engine are inventions with no basis in this project. Indian Railways depot operations are the domain |
| "Maintenance staff can report a complaint from mobile" (drafts 1, 4, 5) | `MAINTENANCE_STAFF` holds only `maintenance.view`, `maintenance.edit`, `assets.view`, `assets.replace`. **No `complaints.create`.** Either the button does not exist, or RBAC changes first — a deliberate decision, not a UI detail |
| "Maintenance staff read SMI/SOP on mobile" (draft 5 §2.2) | `MAINTENANCE_STAFF` holds no `smi_sop.view` or `drawings.view` |
| "Control Cell sees work orders / dispatches breakdown tickets" (drafts 2, 4) | `CONTROL_CELL` holds `complaints.view/create`, `iot.view`, `solar.view`, `reports.view`, `dashboard.view`. **No `maintenance.*`, no `assets.view`** — it cannot see a work order or an asset at all |
| "EB clerk views asset/meter context" (drafts 2, 4) | `EB_BILL_CLERK` holds `energy.*` (CRUD), `reports.view`, `dashboard.view`. **No `assets.view`** |
| "WebSocket delivers work-order updates and alerts" (drafts 2, 3, 4) | WebSockets exist **only** for device and solar telemetry. Everything else is REST polling until a CMMS event channel is built |
| "Push notifications are a Phase 1/2 item" (all drafts) | There is no notification model, no device registry, no FCM/APNs integration and no fan-out job. This is **backend greenfield**, roughly 3–4 weeks of server work on its own |
| "Offline sync is a client concern" (drafts 2, 3) | Offline mutation is unsafe until the server supports idempotency keys and returns a conflict signal. This is a **backend prerequisite**, not a client feature |
| "12–14 weeks for MVP" (draft 2) / "3–4 months" (draft 3) | Both omit the backend gap register in §2.2. With Phase 0 included, a two-platform offline-capable v1 for four roles is **26–34 weeks**, and that estimate is dominated by server work, not Flutter |
| "Extend the API with `/api/mobile/*` endpoints" (draft 3) | Rejected. A parallel mobile API surface duplicates RBAC and drifts. Mobile consumes `/api/v1/`; gaps are fixed in `/api/v1/` for all clients |
| "Geofencing restricts app access to depot locations" (draft 3) | Impossible today, and not for a client-side reason: **no asset, station, infrastructure or depot in GSSMS stores a coordinate.** `Depot.location`/`Station.location` are free-text; `Station.*_km` is track chainage. A fence has no computable centre. §15.4 separates geo-tagging (adopted) from geo-validation (blocked on a survey) from geofencing (rejected for v1) |
| "Use CRDTs for conflict-free sync" (draft 3) | Rejected. Work-order state is a server-owned state machine with role guards — it is not a mergeable data type. Conflicts must be surfaced to a human, never auto-merged |
| "React Native + Expo" (drafts 4, 5) | Superseded by the accepted decision in §4 |
| "ADMIN/HQ approve work orders from mobile" (drafts 1, 2, 4) | `TRANSITION_MAP` accepts only `DEPOT_USER`, `DEPOT_INCHARGE`, `ADMIN` (= `DIV_ADMIN`) and `MAINTENANCE_STAFF`. `SUPER_ADMIN`, `ZR_ADMIN` and `DIV_HQ_USER` cannot transition a work order at all today — see §7.1a |
| "Freeze the domain model before starting" (draft 1 §29) | **Accepted and adopted** as the Phase 0 exit gate in §18 |
| "QR → asset → context-aware actions as the central workflow" (draft 1 §13) | **Accepted and adopted** as §9. The backend groundwork already exists |

---

## 4. Platform decision

**Decision: Flutter, single codebase, Android and iOS from Phase 1.** *(Accepted 2026-08-26. Supersedes the native-Kotlin decision in `ANDROID_APP_SSOT.md` §4.1.)*

| Layer | Choice | Note |
|---|---|---|
| Framework | Flutter (stable channel, pinned in `mobile/.fvmrc` via FVM) | One codebase for both platforms |
| Language | Dart | No reuse from the React frontend — accepted cost |
| State | Riverpod | Compile-safe DI, testable without widget mounting |
| Local database | Drift over SQLite | Typed queries, reactive streams, first-class migrations. `sqlcipher_flutter_libs` for encryption at rest |
| HTTP | Dio + interceptors | Single auth interceptor, single retry policy, single correlation-ID injector |
| Serialisation | `freezed` + `json_serializable` | Immutable models; generated `fromJson` matches the OpenAPI schema |
| Background sync | `workmanager` | Android WorkManager / iOS BGTaskScheduler behind one API — see §10.5 for the iOS caveat |
| Secure storage | `flutter_secure_storage` | Android Keystore / iOS Keychain |
| Biometrics | `local_auth` | App unlock and high-risk action confirmation |
| Camera & QR | `camera` + `mobile_scanner` | `mobile_scanner` wraps MLKit/AVFoundation; no separate scanner package |
| Connectivity | `connectivity_plus` + reachability probe | Connectivity state alone lies on captive portals; always confirm with a cheap authenticated probe |
| Push | `firebase_messaging` (FCM + APNs) — **pending §23 decision** | Railway IT may prohibit Google delivery; see GAP-01 |
| WebSocket | `web_socket_channel` | Telemetry screens only, foreground only |
| Charts | `fl_chart` | Sufficient for depot-scale series; do not port web dashboards wholesale |

**Why Flutter here.** This is an industrial forms-and-lists application with heavy offline requirements: Drift is the strongest offline story available on either cross-platform stack, Flutter's rendering is consistent on the low-end Android devices that dominate depot use, and one codebase halves the platform-parity burden that native Kotlin + Swift would impose. The honest cost is that Dart shares nothing with the existing React/TypeScript frontend — validation rules, error mapping and enum definitions must be regenerated from the OpenAPI schema rather than imported. §16.3 makes that generation mandatory so the duplication stays mechanical instead of manual.

> **Architecture note (2026-08-29):** Drift+SQLCipher deferred; interim persistence is SharedPreferences + secure storage until the offline queue grows past Phase 3.

---

## 5. Scope

### 5.1 v1 roles

| Role | Mobile in v1 | Rationale |
|---|---|---|
| `MAINTENANCE_STAFF` | Yes — primary | Entire job happens at the asset |
| `DEPOT_USER` | Yes | Logs complaints and inspections at the point of observation |
| `DEPOT_INCHARGE` | Yes | Approvals and assignment while walking the depot |
| `CONTROL_CELL` | Yes — read-only monitor | Live telemetry and complaint intake; permission set is already narrow |
| `EB_BILL_CLERK` | Phase 5 | Meter photography is genuinely mobile, but needs GAP-04 and GAP-06 first |
| `DIV_HQ_USER`, `ZR_HQ_USER` | Phase 6 | Read + export; low mobility value until dashboards are mobile-shaped |
| `DIV_ADMIN`, `ZR_ADMIN`, `SUPER_ADMIN` | Phase 6 — awareness only | Power tools stay on web permanently |
| `GUEST` | Not in v1 | Demo role; `valid_until` expiry must be handled before it is exposed |
| `QR_GUEST` | Phase 4, scan flow only | Single-asset locked token; never a general login |

A role not listed for a phase **cannot authenticate into the mobile app** until its mobile surface and permission requirements are added to §8 of this file.

### 5.2 v1 capabilities

1. JWT login, refresh, logout, OTP and TOTP.
2. Permission-derived navigation from the `permissions[]` and `scope` JWT claims.
3. Assigned work-order list, filter and detail.
4. Server-permitted work-order transitions only, via `change-status`.
5. Checklist execution with offline drafts.
6. Single-photo proof of execution (multi-photo evidence gated on GAP-04).
7. Complaint creation and status tracking (`DEPOT_USER`, `DEPOT_INCHARGE`, `CONTROL_CELL`).
8. Inspection creation and conversion request.
9. Asset lookup by search and by QR scan.
10. Work-order audit timeline from `WorkOrderEvent`.
11. Offline read of previously synchronised assignments, checklists and asset data.
12. Durable queued writes with explicit conflict surfacing.
13. Live device and solar telemetry, foreground only, for `CONTROL_CELL` and `DEPOT_INCHARGE`.

### 5.3 Explicitly out of scope for v1

User/role/RBAC administration · taxonomy, template and lookup configuration · database backup and restore · manufacturer and product governance · asset creation, assembly, transfer and specification editing · report designer · direct MQTT, PostgreSQL, TimescaleDB or Redis access · vendor solar API access · public app-store listing.

---

## 6. System boundary

```text
                     ┌──────────────────────────────┐
                     │   GSSMS Mobile (Flutter)     │
                     │   Android · iOS              │
                     └───────┬──────────────┬───────┘
                             │              │
                  HTTPS /api/v1/         WSS ws/v3/…
                             │              │
                     ┌───────▼──────────────▼───────┐
                     │  Django 6.0 · DRF · Channels │
                     │  RBAC + scope enforcement    │
                     │  WorkOrderLifecycleService   │
                     └───────┬──────────────┬───────┘
                             │              │
                  ┌──────────▼───────┐  ┌───▼──────┐
                  │ PostgreSQL       │  │  Redis   │
                  │ + TimescaleDB    │  │ channels │
                  └──────────▲───────┘  └──────────┘
                             │
                  ┌──────────┴───────┐
                  │ iot_worker (MQTT)│ ← devices
                  └──────────────────┘
```

The mobile client connects to exactly two things: `https://<host>/api/v1/…` and `wss://<host>/ws/v3/…`. It never speaks MQTT, never reaches a database, never calls a vendor solar API, and never uses the legacy unversioned `/api/` mount.

---

## 7. Identity, authorisation and session

### 7.1 What the token carries

`MyTokenObtainPairSerializer.get_token` puts the full authorisation picture in the access token: `role` (legacy display name), `roles[]` (canonical names — a user may hold several), `permissions[]` or `["*"]`, `scope{level, zone, division, depot}`, `depot_id`, `depot_name`, `has_2fa`, `valid_until`.

Three consequences the client must respect:

1. **`role` is derived, not stored.** `User.role` resolves the highest-priority RBAC assignment (`accounts/models.py`). A user can hold multiple roles. The app must build navigation from `permissions[]`, never from a `switch` on the single `role` string. A `role`-based shell will silently under-serve multi-role users.
2. **`permissions[]` decides what is *shown*. Django decides what is *allowed*.** Hiding a control is a usability choice with no security value. Every mutation must handle a `403` from a server that disagreed with the client's optimism.
3. **`valid_until` is a hard expiry** for `GUEST`. Treat `GUEST_EXPIRED` as terminal — clear credentials, return to login, do not retry.

### 7.1a The transition guard uses legacy display names, not permissions

`WorkOrderLifecycleService.can_transition` does **not** consult `permissions[]`. It compares `actor.role` — the single legacy display string — against a hardcoded list in `TRANSITION_MAP`. `_CANONICAL_TO_LEGACY_DISPLAY` in `accounts/models.py` maps only `DIV_ADMIN → ADMIN` and `DIV_HQ_USER → HQ_USER`.

The consequences are worth stating plainly, because a mobile UI built from `permissions[]` alone will show buttons that the server refuses:

- Only four role strings can move a work order at all: `DEPOT_USER`, `DEPOT_INCHARGE`, `ADMIN` (i.e. `DIV_ADMIN`) and `MAINTENANCE_STAFF`.
- **`SUPER_ADMIN` and `ZR_ADMIN` cannot transition a work order**, despite holding `maintenance.*`. Neither string appears in `TRANSITION_MAP`, and the check is a plain membership test with no superuser bypass.
- `DIV_HQ_USER` resolves to `HQ_USER`, which likewise appears nowhere in the map.
- For a multi-role user, `User.role` returns the **highest-priority** assignment only. A user holding both `DEPOT_INCHARGE` and `MAINTENANCE_STAFF` resolves to `DEPOT_INCHARGE` (priority 50 vs 30) and therefore cannot start their own assigned work.

The client rule: derive **navigation** from `permissions[]`, but derive **available transitions** from a server-provided list. Live in backend at `GET /api/v1/maintenance/work-orders/{id}/allowed-actions/` (returning `allowed_actions` and `blocked_actions`), consumed by the mobile client (`lib/features/work_orders/domain/models/work_order_action.dart`). Recorded as **GAP-14** (endpoint delivered; role extension to `SUPER_ADMIN`/`ZR_ADMIN` tracked under Decision #15).

Whether `SUPER_ADMIN` and `ZR_ADMIN` should be able to transition work orders is a backend question this document does not settle — but it must be answered before an admin mobile surface is built in Phase 6, or the awareness panel will be the only honest thing it can offer.

### 7.2 Session rules

- Access token: 60 minutes. Refresh token: 1 day (`SIMPLE_JWT`, `settings.py`).
- **A 1-day refresh lifetime is incompatible with multi-day field work.** A technician who works a two-day outage offline is logged out with an undrained queue. Raise the refresh lifetime for a mobile audience *and* add rotation with blacklisting — recorded as **GAP-09**. Until then, the app must warn the user before the refresh window closes and must never discard a queued mutation on logout.
- Refresh through a **single serialised authenticator**. Concurrent 401s from a sync batch must await one refresh, not fire twenty.
- Distinguish `401` (refresh, then retry once), `403` (permission — never retry, surface to user), `409` (conflict — §10.4) and `5xx` (retry with backoff).
- Store the refresh token in `flutter_secure_storage`. Keep the access token in memory where the lifecycle allows.
- Optional biometric app-unlock; mandatory biometric or TOTP confirmation for `VERIFIED` and `CLOSED` transitions (see §8.3).

---

## 8. Role → mobile surface matrix

Every screen below is annotated with the permission the current registry actually grants. Where a draft's proposed feature exceeds that grant, the row says so — that is a decision for the product owner, not something the app may work around.

### 8.1 `MAINTENANCE_STAFF` — SELF scope

Granted: `maintenance.view`, `maintenance.edit`, `assets.view`, `assets.replace`.

| Screen | Endpoint | Notes |
|---|---|---|
| My assignments | `GET /api/v1/maintenance/work-orders/` filtered to `assigned_to = me` | Needs GAP-02 (pagination) and GAP-03 (filtering); today this returns an unbounded list |
| Work-order detail | `GET /api/v1/maintenance/work-orders/{id}/` | Cache for offline |
| Start work | `POST /api/v1/staff-workorders/{id}/execute/` | Creates or retrieves the `MaintenanceRecord` and drives `ASSIGNED → IN_PROGRESS`, guarded to the assigned technician |
| Checklist execution | `POST /api/v1/maintenance/records/{id}/submit_line/` (and `POST /api/v1/maintenance/records/start/`) | Offline-drafted, queued. Note the underscore — DRF derives the path from the method name |
| Component replacement | `POST /api/v1/maintenance/records/{id}/replace_component/` | The one `assets.replace` path this role holds |
| Finalise record | `POST /api/v1/maintenance/records/{id}/complete/` | Saves `MaintenanceSignature` rows |
| Proof of execution | `MaintenanceRecord.proof_of_execution` | One JPEG, ≤5 MB, enforced server-side |
| Technician complete | `POST …/{id}/change-status/` → `TECH_COMPLETED` | Terminal for this role |
| Rework | `REWORK_REQUIRED → IN_PROGRESS` | Only path back |
| Asset lookup / QR scan | `GET /api/v1/assets/by-code/{unique_id}/` | §9 |
| Audit timeline | `WorkOrderEvent` via work-order detail | Read-only |

**Out of grant:** complaint creation, SMI/SOP reading, drawings. Drafts 1, 4 and 5 all assumed a technician can raise a complaint. **Product decision required (GAP-10)** — either grant `complaints.create` to `MAINTENANCE_STAFF` in `rbac/registry.py`, or accept that a technician who finds an unrelated defect must tell a `DEPOT_USER`. Recommendation: grant it; a technician standing at a failed asset is the best possible complaint source, and the current gap pushes real observations into WhatsApp.

Offline is **mandatory** for this role. Nothing else in v1 is.

### 8.2 `DEPOT_USER` — DEPOT scope

Granted: `complaints.view/create/edit`, `inspections.view/create/edit`, `maintenance.view/create/edit`, `energy.view/create/edit`, `assets.view`, `stations.view`, `infrastructure.view`, `drawings.view`, `smi_sop.view`, `reports.view`, `dashboard.view`, `staff.assign`.

Depot work-order list · complaint create and track (`POST /api/v1/complaints/`) · inspection create (`POST /api/v1/inspections/`) · asset and infrastructure browse · SMI/SOP and drawing read (`/api/v1/smi-sop/`, `/api/v1/drawings/`) · depot energy read.

Offline: read cache and complaint drafts. Complaint creation queues only after GAP-05 (idempotency) lands.

### 8.3 `DEPOT_INCHARGE` — DEPOT scope

Granted: full CRUD on complaints, inspections, maintenance (plus `maintenance.group_uncheckout`), energy; `staff.*` including `assign`; view on assets, stations, infrastructure, drawings, SMI/SOP, IoT, solar, audit, dashboard; `reports.view/export`.

| Screen | Endpoint |
|---|---|
| Depot dashboard | `GET /api/v1/analytics/dashboard/` |
| Approvals inbox | `GET /api/v1/maintenance/work-orders/?status=TECH_COMPLETED` (needs GAP-03) |
| Verify / return for rework | `POST …/change-status/` → `VERIFIED` or `REWORK_REQUIRED` |
| Close | `VERIFIED → CLOSED` |
| Assign / reassign | `POST /api/v1/maintenance-staff/assign_work_orders/` (detail=False, takes `staff_user_id`) |
| Hold / resume / cancel | `ASSIGNED|IN_PROGRESS → ON_HOLD`, `ON_HOLD → ASSIGNED`, `→ CANCELLED` |
| Complaint → work order | `POST /api/v1/complaints/{id}/convert_to_work_order/` |
| Inspection → work order | `POST /api/v1/inspections/{id}/convert_to_work_order/` |
| Checklist un-checkout | `maintenance.group_uncheckout` |
| Depot energy summary | `/api/v1/energy/consumption/` |
| Reports | `/api/v1/maintenance/reports/workorders/` |
| Live telemetry | `iot.view`, `solar.view` — §14 |

`VERIFIED` and `CLOSED` are the transitions that end an audit trail. Require a biometric or TOTP confirmation on both, and **never allow them offline** — a verification made against a stale cached state is exactly the class of error §10.4 exists to prevent.

### 8.4 `CONTROL_CELL` — DIVISION scope

Granted: `complaints.view/create`, `iot.view`, `solar.view`, `reports.view`, `dashboard.view`. **Nothing else.**

Live device grid (`/api/v1/v3/devices/{id}/live/` + `ws/v3/devices/{id}/`) · solar plant status (`/api/v1/v3/solar/{plant_id}/live/`) · complaint intake and division-wide complaint list · division dashboard.

This role **cannot see work orders or assets**. Drafts 2 and 4 proposed breakdown dispatch and asset context for Control Cell; both require an RBAC change first. Recommendation: leave the grant as-is for v1 — Control Cell raising a complaint that a `DEPOT_INCHARGE` converts is already the designed path, and widening it weakens the division/depot boundary.

Read-only. No offline mutations. Telemetry is meaningless when stale, so telemetry screens show an explicit "last updated" and refuse to render cached values as live.

### 8.5 `EB_BILL_CLERK` — DIVISION scope *(Phase 5)*

Granted: `energy.*` (CRUD), `reports.view`, `dashboard.view`. No `assets.view`.

Meter reading entry against `EnergyConsumption` (`kwh_initial_reading`, `kwh_final_reading`, `kvah_*`, `power_factor`, `recorded_demand`) · service-connection list (`consumer_number`, `meter_serial_number`, `sanctioned_load`, `tariff_details`) · payment status · consumption trend.

Meter-photo capture and bill upload are the reason this role is worth mobilising, and **neither exists in the model today** — `EnergyConsumption` has no file field. Blocked on GAP-04. OCR of a meter face is Phase 7 at the earliest and must never write a reading without human confirmation.

### 8.6 `DIV_HQ_USER` / `ZR_HQ_USER` *(Phase 6)*

Aggregated dashboards, cross-depot read, report export. `DIV_HQ_USER` additionally holds create/edit on complaints, inspections, maintenance, energy, stations, infrastructure, drawings and SMI/SOP — but no `users.*` and no `rbac.*`.

### 8.7 `DIV_ADMIN` / `ZR_ADMIN` / `SUPER_ADMIN` *(Phase 6, awareness only)*

System health, active alerts, user lookup (role and depot, read-only), critical work-order overview. Note §7.1a: `SUPER_ADMIN` and `ZR_ADMIN` cannot transition a work order today, and `DIV_ADMIN` can only because it resolves to the legacy display string `ADMIN`. Until GAP-14 is decided, this surface is genuinely awareness-only for two of the three roles — do not build approval controls that the server will refuse.

User creation, depot creation, taxonomy, lookups, manufacturer governance, RBAC and database operations remain **web-only, permanently**. `SUPER_ADMIN_ONLY_PERMISSIONS` and the `database` module must never be reachable from a phone.

### 8.8 `GUEST` and `QR_GUEST`

`GUEST` is a read-only demo login with `valid_until` expiry — not in v1. `QR_GUEST` is not a login at all: it is a single-asset token minted by `POST /api/v1/accounts/qr-guest-token/` from a signed scan code, carrying `qr_asset_id`, throttled at 20/hour. Mobile uses it for the unauthenticated scan path in §9.2 only.

---

## 9. QR → Asset → Action

Draft 1 identified this as the highest-value mobile pattern, and it is the one place where the backend groundwork already exists. It becomes the app's spine.

### 9.1 Authenticated scan

```text
Scan QR  →  extract unique_id + signed t
         →  GET /api/v1/assets/by-code/{unique_id}/
         →  Asset context screen
         →  actions filtered by permissions[] ∩ asset state
```

The action list is composed, not hardcoded: open work orders on this asset (`maintenance.view`) · start assigned work (`maintenance.edit` + assigned) · replace component (`assets.replace`) · raise complaint (`complaints.create`) · raise inspection (`inspections.create`) · maintenance summary (`{id}/maintenance-summary/`) · replacement history (`{id}/replacement-history/`) · components (`{id}/components/`) · specifications (`{id}/specifications/`). A technician and a depot incharge scanning the same label see different buttons, from one code path.

### 9.2 Unauthenticated scan

A scan by someone with no session hits `POST /api/v1/accounts/qr-guest-token/` with `unique_id` and `t`. The returned token is locked to that one asset (`qr_asset_id`) and read-only. Two properties must be preserved in the client: the `t` signature is the possession gate (a `unique_id` alone must never mint a token), and the 20/hour throttle exists to stop `unique_id` enumeration — the app must not retry through it.

### 9.3 Offline scan

A scan with no connectivity resolves against the local Drift cache and shows cached asset context with an unmissable staleness marker. Actions that require server state (transitions, verification) are disabled, not queued optimistically.

---

## 10. Offline and synchronisation contract

This is the hardest part of the project and the one that decides whether the app is trusted. Read §2.2 first: **the server cannot yet support safe offline mutation.**

### 10.1 Staged rollout

| Stage | Behaviour | Prerequisite |
|---|---|---|
| **A — offline read** | Cached assignments, checklists, asset data, SMI/SOP; every write requires connectivity | None. Ships in Phase 2 |
| **B — offline drafts** | Checklist lines and complaint text drafted offline, submitted on reconnect with the user watching | GAP-02, GAP-03 |
| **C — offline queue** | Durable background queue, unattended replay, conflict surfacing | GAP-05 (idempotency), GAP-06 (conflict signal), GAP-07 (delta sync) |

Stage C is the goal. Shipping Stage C without GAP-05 produces duplicate work-order transitions and duplicate audit events, and `WorkOrderEvent` is append-only — a duplicate there is permanent.

### 10.2 Local mutation record

Each queued operation stores: client-generated `idempotency_key` (UUIDv4) · entity type and command · validated payload · local creation timestamp · base server version or `updated_at` at read time · retry count and last error class · attachment references with checksums.

User-visible states: `Draft`, `Pending`, `Syncing`, `Failed`, `Conflict`, `Synced`. These appear on the record itself and in aggregate on the support screen — a technician must always be able to answer "did my work reach the server?" without calling anyone.

### 10.3 Sync rules

- `workmanager` drains the queue on network availability, ordered by dependency (a transition never precedes the record it depends on).
- Network errors and `5xx`: bounded exponential backoff, jittered, capped.
- `401`: one serialised refresh, then one retry; on second failure, pause the whole queue and surface a re-login prompt without discarding anything.
- `400`, `403`, `409`: **never** retried automatically. These are decisions, not failures.
- Attachments upload separately from their parent mutation, resumable or safely repeatable, and never block the parent's replay.
- The queue survives process death, force-quit and reboot. Test all three (§19).

### 10.4 Conflict handling

Work-order state is a server-owned state machine with role guards (`TRANSITION_MAP`). It is **not** mergeable, and draft 3's CRDT proposal does not apply.

When the server rejects a queued transition because the state moved underneath it, the app must: keep the local record intact, show the current server state beside the attempted action, name who changed it and when (from `WorkOrderEvent`), and offer exactly two choices — **retry against the new state** (if the transition is still legal) or **discard my change**. Silent last-write-wins is prohibited. Silent discard is prohibited.

### 10.5 The iOS background caveat

iOS `BGTaskScheduler` gives no delivery guarantee — the system decides when, or whether, a background task runs. An Android-shaped design that assumes WorkManager semantics will lose data on iOS.

The rule: **background sync is an optimisation, never the delivery mechanism.** Every queue drains fully on foreground. The app shows pending count on launch and offers a manual "sync now". A field user must never depend on iOS having chosen to wake the app.

---

## 11. Backend prerequisite register (Phase 0)

Nothing in Phase 3 onward ships until its gaps close. Each is server work in `backend/`, benefiting web and mobile alike.

| ID | Gap | Change required | Blocks | Est. |
|---|---|---|---|---|
| **GAP-01** | No push infrastructure | `Device` model (user, platform, token, app version, last seen); register/unregister endpoints; `NotificationEvent` model; Celery fan-out on work-order assignment, rework, SLA breach and IoT alarm; FCM + APNs credentials | All notifications | 3–4 wk |
| **GAP-02** | No default pagination | `DEFAULT_PAGINATION_CLASS` with a mobile-sane page size; audit every `pagination_class = None` and justify or remove it | Every list screen | 1 wk |
| **GAP-03** | No filtering or search | Add `django-filter`; `filter_backends` + `filterset_fields` on work orders, complaints, inspections, assets, energy | Assignment lists, approval inbox | 1–2 wk |
| **GAP-04** | Single-image evidence only | `Attachment` model (generic FK, kind `BEFORE`/`DURING`/`AFTER`/`METER`/`BILL`, uploader, checksum, captured-at) reachable from WorkOrder, MaintenanceRecord, Complaint, Inspection, EnergyConsumption; served via `protected_media` | Evidence capture, EB bill upload | 2–3 wk |
| **GAP-05** | No mutation idempotency | Generalise `AssetCreateIdempotency` into a reusable `Idempotency-Key` header handler; apply to `change-status`, `staff-workorders/{id}/execute`, `records/{id}/submit_line`, `records/{id}/complete`, complaint and inspection creation, energy readings | Offline Stage C | 2 wk |
| **GAP-06** | No conflict signal | Return `409` with current server state and the deciding `WorkOrderEvent` when a transition is stale; add `If-Match`/version semantics on edits | Conflict resolution | 1–2 wk |
| **GAP-07** | No delta sync | `?updated_after=<iso8601>` on syncable collections; `updated_at` indexed; tombstones for deletes | Incremental sync | 2 wk |
| **GAP-08** | No geotagging on operational records | Three independent steps, see §12.1. **8a** wire the already-migrated `AssetScan` (§2.3) — no schema change. **8b** add a `CapturedLocationMixin` to Complaint, Inspection, MaintenanceRecord — **does not depend on GAP-04**. **8c** same mixin on the GAP-04 `Attachment` for per-photo fixes. Capture at the event, foreground only (§15.4) | Proof of presence (8a/8b), geo-tagged photos (8c) | 3 d + 1 wk + 2 d |
| **GAP-09** | 1-day refresh, no rotation | Longer mobile refresh lifetime, rotation with blacklist, device-bound sessions, remote revocation | Multi-day field work, lost-device response | 1 wk |
| **GAP-10** | `MAINTENANCE_STAFF` lacks `complaints.create` | Product decision; if granted, one edit in `rbac/registry.py` plus RBAC tests | Technician complaint raising | 2 d + decision |
| **GAP-11** | WS token in query string | Short-lived single-use WS ticket endpoint, or subprotocol-header auth | Secure telemetry | 1 wk |
| **GAP-12** | No CMMS event channel | *(Optional)* Channels group per user/depot for assignment and approval pushes | Live inbox — **poll in v1 instead** | 2 wk |
| **GAP-13** | OpenAPI schema not client-trusted | Verify `drf-spectacular` output matches production behaviour for every v1 endpoint; then generate Dart models from it | Contract-safe client | 1–2 wk |
| **GAP-14** | Allowed transitions not exposed | Live at `GET …/allowed-actions/` returning `allowed_actions`/`blocked_actions` (consumed in mobile). Decide separately whether `SUPER_ADMIN`/`ZR_ADMIN` belong in `TRANSITION_MAP` (Decision #15) | Correct action buttons; admin surface in Phase 6 | Delivered (endpoint); decision open |

Sequenced with overlap, Phase 0 is **8–12 weeks** of backend work. GAP-02, GAP-03, GAP-13 and GAP-14 must land before Phase 3. GAP-05, GAP-06 and GAP-07 must land before Phase 4. GAP-01 and GAP-04 must land before Phase 5.

---

## 12. Evidence and attachments

Until GAP-04 lands, mobile evidence is exactly what the server accepts today: one JPEG, ≤5 MB, on `MaintenanceRecord.proof_of_execution`, validated server-side on `content_type` and size.

After GAP-04: client-side compression to a target long edge before upload (a 12 MP phone photo over depot 4G is the single largest source of failed uploads); per-file checksum so a repeated upload is recognised rather than duplicated; app-private storage with a retention policy that deletes local copies after confirmed upload plus a grace window.

**Geo-tagging rule.** Location travels in **database columns on the attachment record**, never in the image's EXIF. EXIF is stripped on the client except orientation. Three reasons this is not a preference: EXIF GPS is trivially editable and therefore worthless as evidence; compression pipelines and OS privacy settings silently drop it, so its absence proves nothing; and it cannot be queried, so "show me every inspection recorded more than 200 m from the asset" is impossible. Columns are `captured_lat`, `captured_lon`, `accuracy_m`, `captured_at` and `location_source` (`GPS` / `NETWORK` / `MANUAL` / `UNAVAILABLE`) — recording *why* a location is missing matters as much as the coordinate, because a technician inside a substation building often genuinely cannot get a fix, and a blank field must not read as evasion.

Treat the result as **corroboration, not proof**. Depot GPS accuracy is degraded by metal structures and overhead lines, and a rooted device can mock a location. It is good enough to catch a form filled in from the canteen; it is not good enough to discipline someone on.

### 12.1 Geo-tagging implementation (GAP-08)

Adopted for v1. Geofencing is **not** in scope — see §15.4 and decision #16.

**Shared field definition.** One abstract mixin, reused everywhere, so the semantics never diverge:

```python
class CapturedLocationMixin(models.Model):
    LOCATION_SOURCE_CHOICES = (
        ('GPS', 'Device GPS'),
        ('NETWORK', 'Network / fused'),
        ('MANUAL', 'Entered by user'),
        ('UNAVAILABLE', 'No fix obtained'),
        ('DENIED', 'Permission denied by user'),
    )
    captured_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    captured_lon = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    accuracy_m = models.FloatField(null=True, blank=True)
    captured_at = models.DateTimeField(null=True, blank=True)
    location_source = models.CharField(max_length=12, choices=LOCATION_SOURCE_CHOICES, blank=True)

    class Meta:
        abstract = True
```

Every field is nullable. A missing fix is a normal outcome in a substation building, not an error, and `location_source` records **why** it is missing — `UNAVAILABLE` and `DENIED` must be distinguishable, because one is physics and the other is a choice.

**Three steps, independently shippable:**

| Step | Change | Depends on | Effort |
|---|---|---|---|
| **8a** | Write `AssetScan` on every QR scan (§9). Columns already migrated in `0016_qr_groundwork` | Nothing | ~3 days |
| **8b** | Apply the mixin to `Complaint`, `Inspection`, `MaintenanceRecord` | Nothing — **not blocked on GAP-04** | ~1 week |
| **8c** | Apply the mixin to the GAP-04 `Attachment` so each photo carries its own fix | GAP-04 | ~2 days |

Steps 8a and 8b deliver record-level proof of presence without waiting for the attachment work. Only 8c is a genuinely geo-tagged *photo*.

**Client rules that decide whether this works in the field:**

1. **Never block the user on a fix.** Request location in parallel with opening the camera, time out at ~10 s, and submit with `location_source='UNAVAILABLE'` rather than making a technician stand in the rain waiting for satellites.
2. **The fix belongs to capture time, not upload time.** An offline record captured at 09:12 and synced at 17:40 stores 09:12's coordinate. `captured_at` is the client's timestamp, distinct from the server's `created_at`; both are kept, and clock skew between them is a diagnostic signal, not something to silently correct.
3. **Store the coordinate in the offline queue with the mutation** (§10.2), never re-derive it at replay.
4. **Permission is `whileInUse` only.** Never request `always` / background location — that is the T3 capability §15.4 rejects, and requesting it would fail App Store review without a background use case to declare.
5. Keep a last-known position with its age and use it only when a fresh fix times out, marked `NETWORK`, never presented as a live GPS fix.
6. Show the fix and its accuracy to the user before submission, and let them proceed without one. Serve everything through `protected_media` so the existing object-level scope check applies — never a direct `MEDIA_URL` path.

Cap total local evidence storage and warn before the device fills. A phone that cannot take the "after" photo has failed the technician at the worst moment.

---

## 13. Notifications

There is no notification system in GSSMS today (§2.2). This is a backend project (GAP-01), not a Flutter package choice.

**v1 behaviour without GAP-01:** foreground polling of the assignment and approval lists on a sane interval with a visible last-refreshed marker. Honest, and cheap to build.

**After GAP-01,** notifications are scoped by role, depot and event, and carry no operational detail on the lock screen — a ticket number and a category only, with the substance behind authentication. Categories: assignment, rework required, SLA breach, approval pending, IoT alarm, energy reading due. Every notification deep-links to the record; the deep link must survive a cold start and re-authentication.

The push-provider decision is open (§23) — Indian Railways IT may prohibit Google-hosted delivery, which would mean a self-hosted alternative for Android and a direct APNs path for iOS.

---

## 14. Real-time telemetry

Only `iot_v3` and `solar_v3` have WebSocket routes. Everything else polls.

`ws/v3/devices/{device_id}/` and `ws/v3/solar/{plant_id}/`, authenticated by `JWTAuthMiddleware` — via the ticket mechanism from GAP-11, not `?token=`.

Rules: **foreground only** — a socket held in the background drains battery for data nobody is looking at, and iOS will kill it anyway. Reconnect with exponential backoff and re-subscribe on network transition (4G↔Wi-Fi is constant in a depot). Snapshot first (`/live/`), then stream deltas, so the screen is never empty while connecting. Show connection state and last-message age explicitly; a frozen chart that looks live is worse than a visibly disconnected one. Cap retained history in memory. Historical series come from `/history/`, never from replaying the socket.

---

## 15. Security

### 15.1 Credentials and transport
Refresh token in `flutter_secure_storage` (Keystore/Keychain). Access token in memory where the lifecycle permits. Never in URLs, logs, analytics, crash reports, screenshots or source control. HTTPS/WSS only outside an explicitly configured local development build. Certificate pinning on the release flavour, with a documented rotation runbook — an unrotatable pin is an outage waiting to happen.

### 15.2 Local data at rest
Drift over SQLCipher; key in the platform keystore. Evidence in app-private storage, never the shared gallery. Retention and deletion rules defined before pilot. Full local wipe on terminal auth failure and on remote revocation (GAP-09).

### 15.3 Client-side authorisation
Permission-derived UI only. Never invent a mobile-only permission string — new permissions go into `rbac/registry.py` first. Every mutation handles `403` gracefully. The RBAC test matrix (§19) covers cross-depot denial, unassigned-technician denial and expired-guest denial for every v1 role.

### 15.4 Location — three different things, deliberately separated

Draft 3 proposed "geofencing: restrict app access to substation/depot locations." That is a materially different feature from geo-tagging, with a different cost and a different risk profile. This SSOT separates them into three tiers and adopts only the first.

| Tier | What it does | What it needs | Status |
|---|---|---|---|
| **T1 — Geo-tagging** | Stamps the coordinate onto the record at the moment of the event. Passive, foreground-only, one fix per event | GAP-08 columns | **Adopted for v1** |
| **T2 — Geo-validation** | At submit time the *server* compares the captured point against the asset's known point and flags or blocks a submission beyond a threshold | T1 **plus authoritative coordinates for every asset** — see below | Open decision #16 |
| **T3 — Geofencing proper** | OS-level region monitoring: the app reacts to entering or leaving a boundary, which requires **background** location and continuous evaluation | T1 + T2 + always-on location permission | **Dropped 2026-08-26** (decision #16) |

**T2 is blocked on master data nobody has costed.** Nothing in GSSMS stores a machine-readable position for anything physical:

- `Depot.location` and `Station.location` are free-text `CharField`s ("Near River Bed, Pump House") — descriptions, not coordinates
- `Station.railway_track_km`, `up_at_km`, `dn_at_km` hold **chainage** — a linear reference along the track, genuinely useful in railway terms but not convertible to a radius without a track alignment dataset
- `Infrastructure` and `Asset` carry no position at all
- The only `lat`/`lon` columns in the entire schema are on the dormant `AssetScan` (§2.3)

So a fence cannot be computed, because the centre of the circle is unknown. Enabling T2 means surveying or geocoding every asset in the division first — a field data-collection programme measured in months, not a sprint. The one honest shortcut: let T1 run for a season and derive each asset's position from the clustered median of real technician scans, then confirm it. That turns a survey into a by-product of normal work.

**T3 is rejected for v1, and the reason is not technical.** Background region monitoring means the app knows where the holder is when nobody has opened it. Whatever the stated purpose, that is a movement-tracking capability, and building it is a labour-relations decision — not an engineering one, and not one this document makes silently. It also degrades badly in practice: iOS throttles region monitoring aggressively, battery cost is real, and depot GPS accuracy (metal structures, overhead lines) produces false boundary crossings that erode trust in every location signal including T1's.

**Adopted rule for v1:** capture location **only at an operationally meaningful event** — a complaint raised, an inspection recorded, a work order completed, an asset scanned — with a visible indicator at the moment of capture, `whileInUse` permission only, no movement history retained. Implementation is §12.1. T3 is dropped (decision #16). If T2 or T3 is revisited, it needs an explicit documented operational and legal justification recorded in §23 before any code is written.

### 15.5 Device posture
Minimum OS versions set from the actual depot device inventory, not from what is convenient. Root/jailbreak detection as a warning signal, not a hard block. Screenshot suppression on evidence and approval screens. Forced-update policy with a defined backend compatibility window.

---

## 16. API contract rules

### 16.1 Binding rules
Mobile consumes `/api/v1/` exclusively; the legacy unversioned `/api/` mount is off-limits. No `/api/mobile/*` parallel surface (draft 3's proposal is rejected — it duplicates RBAC and drifts). No client-side reimplementation of scope filtering. Contract gaps are fixed in Django and documented in `docs/api_manual.md` before the client works around them.

### 16.2 Per-feature contract checklist
Before a feature is implemented, its contract states: endpoint and method · request/response schema · pagination, filtering and ordering · effective permission and scope · behaviour for `400`, `401`, `403`, `404`, `409`, `5xx` · idempotency and concurrency semantics · attachment size, type and upload protocol · cacheability and freshness expectation.

### 16.3 Generated models are mandatory
Once GAP-13 confirms `drf-spectacular` output matches production behaviour, Dart models are **generated** from the OpenAPI schema, not hand-written. Flutter shares no code with the React frontend; generation is what keeps that duplication mechanical rather than a slow divergence nobody notices until a field is silently dropped.

### 16.4 Correlation
Every request carries a non-sensitive correlation ID, logged on both sides. Without it, "the sync failed yesterday afternoon" is unanswerable.

---

## 17. Repository layout

```text
GSSMS/
├── backend/
├── frontend/
├── mobile/                       ← Flutter, both platforms
│   ├── android/
│   ├── ios/
│   ├── lib/
│   │   ├── core/
│   │   │   ├── auth/             # login, refresh, biometrics, session
│   │   │   ├── rbac/             # permission evaluation from claims
│   │   │   ├── network/          # Dio, interceptors, error mapping
│   │   │   ├── db/               # Drift schema, DAOs, migrations
│   │   │   ├── sync/             # queue, replay, conflict engine
│   │   │   ├── notifications/
│   │   │   └── design/           # tokens, components, industrial theme
│   │   ├── features/
│   │   │   ├── auth/
│   │   │   ├── home/             # permission-composed dashboard
│   │   │   ├── workorders/
│   │   │   ├── checklists/
│   │   │   ├── complaints/
│   │   │   ├── inspections/
│   │   │   ├── assets/           # search, QR scan, asset context
│   │   │   ├── telemetry/        # iot + solar
│   │   │   ├── energy/           # phase 5
│   │   │   └── support/          # version, last sync, queue health
│   │   ├── generated/            # OpenAPI-derived models — never hand-edited
│   │   └── main.dart
│   ├── test/
│   ├── integration_test/
│   └── pubspec.yaml
└── docs/
    └── MOBILE_APP_SSOT.md        ← this file
```

Create a feature directory when it has a screen, not in anticipation. Do not scaffold empty modules.

**Build flavours:** `dev` (local/dev HTTPS, verbose redacted logging, debug signing) · `staging` (staging HTTPS, redacted diagnostics, internal key) · `prod` (production HTTPS, minimal logging, protected release key, certificate pinning on). Base URLs come from `--dart-define` at build time, never from a user-editable production setting. A physical phone cannot reach another machine's localhost — an HTTPS staging server is a Phase 0 deliverable, not a convenience.

---

## 18. Delivery plan and exit gates

### Phase 0 — Contract and backend preparation · 8–12 weeks *(backend team)*
Close GAP-02, GAP-03, GAP-13 fully; land GAP-05, GAP-06, GAP-07 designs; decide GAP-10; stand up HTTPS staging with a test account for each v1 role; freeze the domain contracts for User, Depot, Station, Infrastructure, Asset, InstalledComponent, Complaint, Inspection, WorkOrder, WorkOrderEvent, MaintenanceRecord, MaintenanceRecordLine, EnergyConsumption, IoT device and telemetry (draft 1 §29, adopted).

**Gate:** contracts frozen and documented · v1 role matrix approved · staging reachable from a physical device · no unresolved offline-write or security blocker.

### Phase 1 — Foundation · 3–4 weeks
Flutter workspace with FVM; flavours for both platforms; Riverpod, Dio, Drift, routing, logging, design tokens; generated models from OpenAPI; CI running analyze, test and both platform builds.
**Gate:** dev and staging builds install on a physical Android device and a physical iPhone; CI green; app reaches a health-checked staging service.

### Phase 2 — Authentication and permission shell · 3–4 weeks
Login, OTP, TOTP, refresh, logout, session restore, terminal failure; claims hydration; permission-composed navigation; standard error, empty and offline states; Stage A offline read.
**Gate:** every auth scenario tested on both platforms · navigation matches effective permissions for all four v1 roles · a `403` leaks nothing · a multi-role user sees the union of their surfaces.

### Phase 3 — Work-order vertical slice · 5–6 weeks
Assignment list, filters, detail, permitted transitions, checklist execution, single-photo proof, rework reason, audit timeline; server validation and workflow errors mapped to actionable UI.
**Gate:** a real technician completes a real assignment end-to-end on staging, on both platforms · depot, assignment and role scoping tests pass · `WorkOrderEvent` reflects every accepted transition and nothing else.

### Phase 4 — Offline engine · 6–8 weeks
Drift cache, drafts, durable queue, attachment upload, sync state surfacing, conflict resolution UI; delta sync against GAP-07; process death, force-quit, reboot, network loss, token expiry, duplicate-tap and iOS background-throttle testing.
**Gate:** supported workflows survive loss of network and loss of process on both platforms · retries create no duplicate server state · no conflict resolves silently · iOS foreground drain is proven complete without relying on `BGTaskScheduler`.

### Phase 5 — Complaints, assets, QR, telemetry, notifications, EB clerk · 5–6 weeks
Complaint and inspection creation and tracking; asset search; QR scan flow (§9); Control Cell telemetry (§14); push after GAP-01; `EB_BILL_CLERK` surface after GAP-04.
**Gate:** each feature passes permission, scope, offline and deep-link tests · notifications carry no sensitive lock-screen content · telemetry never renders stale data as live.

### Phase 6 — Remaining roles · 3–4 weeks
`DIV_HQ_USER`, `ZR_HQ_USER` dashboards and export; admin awareness panels.
**Gate:** admin power tools verifiably unreachable from mobile · export downloads work on both platforms.

### Phase 7 — Pilot and controlled release · 4–5 weeks
One depot, small representative group, real devices including low-end Android; accessibility, battery, performance, recovery and security checks; signed AAB and IPA; operator runbook.
**Gate:** pilot acceptance met with no open critical or high defect · signing, rollback, monitoring, support and incident ownership approved.

### Total

**26–34 weeks** for a two-platform, offline-capable v1 across four roles, of which **8–12 weeks is backend**. The mobile client is not the hard part — the sync contract and the missing server capabilities are. Draft 2's "12–14 weeks" and draft 3's "3–4 months" are achievable only for a read-only online-only app, which is not what field work needs.

---

## 19. Testing and quality gates

Unit: Riverpod providers, repositories, mapping, queue policy, error classification, permission evaluation. Drift migration and DAO tests. Contract tests against recorded representative server responses. Widget and `integration_test` coverage of the critical journeys.

**RBAC matrix — mandatory, every v1 role:** own-scope allowed · cross-depot denied · cross-division denied · unassigned technician denied `IN_PROGRESS` and `TECH_COMPLETED` · expired guest denied · multi-role union correct · every permission-hidden control confirmed to also be server-denied.

**Offline matrix — mandatory:** process death mid-queue · force-quit · device reboot · airplane mode toggling during upload · token expiry with a full queue · duplicate rapid taps · partial attachment failure · stale-state conflict · iOS background task never firing · clock skew between device and server.

**Security:** token leakage in logs and crash reports · cleartext transport · exported components (Android) and URL schemes (iOS) · backup exclusion of the encrypted database · release-build configuration · pin rotation.

A release candidate passes: analyze, unit tests, integration tests on both platforms, backend contract and RBAC tests, and a manual smoke test on at least one low-end physical Android device and one physical iPhone. Emulator-only sign-off is not sign-off.

---

## 20. Distribution and operations

Android: Play internal/closed testing or managed enterprise distribution. Direct APK only as a controlled interim path with version and checksum tracking.
iOS: **an Apple Developer Program account is a hard prerequisite** — TestFlight for pilot, and either App Store or Apple Business Manager custom distribution for production. Decide this in Phase 0; the enrolment itself can take weeks for an organisational account, which is exactly the kind of delay that surprises a project at Phase 6.

Before production: crash and performance monitoring with approved data handling and redaction · a support screen showing app version, build, environment, last sync time and queue health · minimum OS baseline from the real device inventory · forced/soft update policy and backend compatibility window · documented signing-key custody and recovery for both platforms · a rollback-ready prior release.

---

## 21. Success metrics

≥95% crash-free pilot sessions on both platforms · zero confirmed RBAC or cross-scope data exposure · zero duplicate work-order transitions caused by retry · ≥95% of valid queued operations sync without manual support after connectivity returns · median time to open a cached assignment under two seconds on the lowest-spec supported device · pilot users complete the primary work-order journey without returning to the web application · median evidence upload success rate ≥98% over depot connectivity.

Revise after baseline measurement, and record the revision here.

---

## 22. Risks and controls

| Risk | Control |
|---|---|
| Offline mutation ships before server idempotency | Stage gating in §10.1; Phase 4 cannot start until GAP-05 and GAP-06 land |
| Duplicate `WorkOrderEvent` rows from retry | Idempotency keys, durable command IDs, retry classification; append-only log makes duplicates permanent |
| Stale offline state overwrites newer workflow state | Version checks, `409` with server state, explicit human resolution; never last-write-wins |
| iOS background sync assumed reliable | Foreground drain is the contract; background is optimisation only (§10.5) |
| Client duplicates authorisation policy | Permission-derived UI only; Django authoritative; full RBAC matrix in CI |
| Role-based `switch` under-serves multi-role users | Navigation composed from `permissions[]`, never from `role` |
| Push provider blocked by railway IT | Decide in Phase 0 (§23); v1 polls, so a block delays a feature rather than the release |
| Apple Developer enrolment delays iOS | Start enrolment in Phase 0 |
| Evidence uploads fail on depot connectivity | Client compression, resumable upload, checksum dedupe, visible queue |
| Scope creep into a web rewrite | §5.3 and the phase gates; deferred features need an edit to this file |
| Dart/TypeScript model divergence | Generated models from OpenAPI (§16.3); hand-edited files in `lib/generated/` rejected in review |
| Location capture drifts into staff tracking | §15.4; any change requires a documented justification recorded in §23 |

---

## 23. Open decisions

Record resolutions in this table. Do not create a separate decision document.

| # | Decision | Status | Owner |
|---|---|---|---|
| 1 | Flutter for Android + iOS | **Resolved 2026-08-26** — accepted; supersedes native Kotlin | Product owner |
| 2 | v1 roles = field four | **Resolved 2026-08-26** — `MAINTENANCE_STAFF`, `DEPOT_USER`, `DEPOT_INCHARGE`, `CONTROL_CELL`; others phased | Product owner |
| 3 | GAP-10 — grant `complaints.create` to `MAINTENANCE_STAFF`? | Open | Product owner |
| 4 | Push provider — FCM/APNs or self-hosted? | Open | Architecture + railway IT |
| 5 | Apple Developer account — organisational enrolment owner and timeline | Open | Product owner |
| 6 | Managed railway devices or BYOD? | Open | Operations + security |
| 7 | Minimum Android API and iOS version | Open | Mobile lead, from device inventory |
| 8 | Evidence types, size limits, retention, compression targets | Open | Product + security |
| 9 | Geotagging scope — event-only per §15.4 | Open | Operations + product |
| 10 | Pilot depot and user group | Open | Operations |
| 11 | Mobile refresh-token lifetime and rotation policy (GAP-09) | Open | Backend lead + security |
| 12 | App name, bundle ID, package ID, icon, signing custody | Open | Product + release owner |
| 13 | Offline verification — confirmed prohibited for `VERIFIED`/`CLOSED`? | Open | Product owner |
| 14 | Distribution channel per platform | Open | Operations |
| 15 | GAP-14 — should `SUPER_ADMIN`/`ZR_ADMIN` be able to transition work orders? | Open | Backend lead + product owner |
| 16 | Geofencing (T3, §15.4) | **Resolved 2026-08-26** — dropped. Geo-tagging (T1) adopted; see §12.1 | Product owner |
| 17 | Geo-validation (T2, §15.4) — wanted later, and who funds surveying asset coordinates? | Open — revisit after T1 has run a season and positions can be derived from scan clusters | Operations + product owner |
| 18 | Local persistence stack & Drift migration timing | **Resolved 2026-08-29** — Drift+SQLCipher deferred; interim persistence is SharedPreferences + secure storage until the offline queue grows past Phase 3 | Product owner + Mobile lead |

---

## 24. Change control

Scope, architecture, security posture, offline semantics, phase gates and decisions change only by editing this file, reviewed by the relevant owner. Implementation notes may live beside code but must not contradict this document. `docs/api_manual.md` owns HTTP contracts; `docs/RBAC_MANUAL.md` and `backend/rbac/registry.py` own roles, permissions and scope; this file references them rather than restating them.

If mobile implementation reveals a contradiction, stop the affected work, establish the authoritative backend behaviour, and update the owning document and this file together in the same change.
