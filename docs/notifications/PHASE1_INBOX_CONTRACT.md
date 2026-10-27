# Notification Phase 1 — Inbox Foundation (v0.3.10 baseline)

Status: proposed contract; implementation requires backend coordination. No push provider selected.

## Verified existing behavior
- Flutter `NotificationsScreen` derives ASSIGNMENT, REWORK, OVERDUE and SLA alerts from the loaded work-order list.
- Read flags live in a Riverpod notifier and are not persisted by a notification backend.
- Android manifest declares POST_NOTIFICATIONS, but no system notification or FCM client dependency is configured.
- Existing guarded work-order navigation and `maintenance.view` permission checks must be retained.

## Backend contract proposal (not yet implemented)
- `GET /api/notifications/?cursor=...`: paginated, user-authorized inbox with opaque event ID, type, created_at, work_order_id, read_at, and cursor.
- `POST /api/notifications/{id}/read/`: idempotent acknowledgement for the authenticated recipient only.
- `POST /api/notifications/read-all/`: idempotent acknowledgement scoped to the authenticated recipient.
- `GET /api/notifications/unread-count/`: count from the authoritative inbox.
- Event producer must commit a durable notification record with the work-order transaction or a transactional outbox, then dispatch asynchronously.
- Recipient must be resolved server-side using the current assignment and role/permission policy. Never trust a recipient ID supplied by the mobile client.

## Invariants and migration
1. A notification has a unique event ID and user-scoped delivery/read record. Replays are idempotent.
2. A reassignment invalidates access to prior recipient content. Every inbox query and deep link re-checks authorization.
3. Never send private work-order details in unauthenticated or lock-screen push payloads.
4. Logout clears user-specific local inbox state and device registration; account switching must not leak data.
5. Keep existing derived alerts as a temporary fallback until the server inbox is operational. Do not silently combine duplicate server and derived events.
6. Offline mode shows the last authorized cached inbox with a visible stale indicator. Reconcile on reconnect.
7. Keep notification events and audit evidence according to a documented retention policy.

## Delivery decision gate
Before adding Firebase Cloud Messaging or another provider, obtain approval from railway IT for transport, data handling, service credentials, and device enrollment. An API inbox is the source of truth regardless of delivery mechanism.

## Acceptance tests
- Authenticated recipient sees only assigned/authorized events.
- Acknowledgement persists after app restart and works repeatedly without duplicate side effects.
- A second signed-in user cannot see cached notifications from the first.
- Pagination, offline/reconnect, duplicate event replay, reassignment, and deleted work-order navigation behave safely.
- No notification is shown on the Android system tray until a delivery provider is explicitly approved and tested.
- Flutter analyze, tests, Android build, lint and advisory checks pass before merge.

## Release boundary
This feature branch starts from main at v0.3.10+15. Do not merge, tag, sign, or deploy as part of the planning slice.
