# GSSMS Android Notifications — Single Source of Truth (SSOT)

Version: 1.0 (design baseline, 2026-10-27)
Baseline: GSSMS Android v0.3.10+15 on main
Implementation branch: feat/notifications-phase1-inbox-foundation
Status: APPROVED FOR INCREMENTAL DEVELOPMENT; NOT RELEASED

## 1. Purpose and boundaries
Deliver an authenticated, auditable, offline-tolerant notification inbox and, after explicit railway IT approval, Android system notifications. The backend is authoritative for recipient, event, authorization and acknowledgement. Existing released app behavior must not regress. No merge, signing, release or deployment without a separate approval.

## 2. Verified current state
- Flutter screen: lib/features/notifications/presentation/screens/notifications_screen.dart.
- Derived alert model: lib/features/notifications/domain/models/notification_item.dart.
- Alerts are calculated from loaded work orders: assignment, rework, overdue, SLA risk.
- Read flags are currently in-memory; there is no server inbox integration.
- AndroidManifest.xml declares POST_NOTIFICATIONS; pubspec.yaml has no FCM or local notification dependency.
- Work-order navigation uses guarded authorization; preserve this behavior.
- Existing widget tests cover derivation, display, read-all and empty state.

## 3. Product requirements
- Server-side events for assignment, reassignment, rework, breakdown, SLA warning/breach and approval actions where corresponding backend business events exist.
- Inbox: newest-first, pagination, unread count, read acknowledgement, refresh, stale/offline indicator, accessible empty/error states.
- Each event opens only a currently authorized target; denied or removed targets show a safe explanation.
- No invented alerts. Existing derived alerts are temporary fallback until server inbox is available; do not show duplicate representations.
- No system notification or background push promise until delivery provider is selected and verified.

## 4. Authoritative event schema
Fields: id (opaque stable string), type (versioned enum/string), created_at (UTC ISO-8601), title, message, work_order_id (nullable positive integer), read_at (nullable UTC ISO-8601). Optional: priority, action_type, expires_at. Client must reject malformed records safely and must not infer permissions from payload.
- Events and per-recipient delivery/read state are distinct.
- Idempotency key is derived from immutable business event and recipient.
- Events must be recorded transactionally with the business action or via transactional outbox.
- Read acknowledgements are monotonic and idempotent.

## 5. Proposed API (pending backend agreement)
- GET /api/notifications/?cursor=<opaque> -> {results: [...], next_cursor: string|null}
- GET /api/notifications/unread-count/ -> {count: integer}
- POST /api/notifications/{id}/read/ -> acknowledgement
- POST /api/notifications/read-all/ -> acknowledgement
- Future device registration and push token endpoints require security and provider review.
- Authentication is mandatory; endpoints enforce recipient and scope on every request.
- Server must define pagination stability, retention, error codes, and versioning before integration.

## 6. Security and privacy invariants
- Recipient resolution and access checks occur server-side, including reassignment and deep-link opening.
- User-specific data must not cross login/logout or role/scope changes on shared devices.
- Do not store JWTs or push secrets in notification payloads, logs, or source control.
- Lock-screen push payloads contain minimal non-sensitive text; details require app unlock and fresh authorization.
- Device tokens are scoped to authenticated identity, revoked on logout/account change, and rotated.
- Never delete unsynced operational work or evidence while clearing notification-only state.
- Respect approved railway IT transport, data residency, credential management and retention policy.

## 7. Architecture and phases
P0 — Freeze contract, tests and threat model (this SSOT).
P1 — Backend durable inbox and authorized API; Flutter typed models/repository, paging, read state, offline-safe UI, migration from derived alerts.
P2 — Android notification channels and permission UX; approved provider integration; foreground/background/terminated deep links.
P3 — Reliability: dedupe, retry, reconnect, token lifecycle, monitoring, user preferences and escalations.
P4 — Production gates: CI, real-device verification, security/privacy review, operational rollout.

## 8. Acceptance tests and release gates
- Event schema parsing, invalid input, deduplication, cursor paging and stable ordering.
- Authorized recipient only; reassignment, permission changes and cross-account isolation.
- Read and read-all persist across app restarts; repeated requests are idempotent.
- Offline cached inbox is visibly stale and reconciles on reconnect without losing read status.
- Notification tap checks current permissions and handles missing work order.
- Push tests, once approved: Android 13+ permission denied/granted, foreground/background/terminated, token rotation, duplicate delivery and reboot.
- Flutter analyze/test, Android build/lint/advisories and device smoke tests must pass.
- Separate reviewer approval before merge, tag, signing or production deployment.

## 9. Decision register
D-01: v0.3.10 main is baseline — confirmed.
D-02: Keep notification work isolated from prior audit remediation — confirmed.
D-03: Server inbox is source of truth — proposed pending backend validation.
D-04: FCM vs alternative transport — OPEN, railway IT approval required.
D-05: Exact backend API paths and event ownership — OPEN.
D-06: Retention, escalation timings and lock-screen policy — OPEN.
D-07: No release without explicit authorization — enforced.

## 10. Change control
This SSOT is the canonical notification requirements document. Any implementation that diverges must update the decision register and tests in the same PR. Keep work in reviewable slices and preserve v0.3.10 until release approval.
