# API and data integrity baseline

Actual backend integration: BLOCKED pending authorized staging accounts/data and contract fixtures. No live login, mutation, production read or backend penetration probe performed. Existing API tests use local test doubles; any passing result must be described as mocked verification.

[API call inventory with source lines](evidence/api-calls.txt) records concrete calls including method, path and file. Common roots:

| Service | Contract surface |
|---|---|
| Auth | POST auth/login, refresh, otp/request, otp/login, reset-password, totp/setup/verify/validate; GET/PATCH users/{id}; profile multipart |
| Assets | GET assets/list/detail/specifications/components/replacement-history/maintenance-summary; replacement POST operations |
| Complaints | GET list/detail; POST create, convert_to_work_order, close, photos |
| Inspections | GET inspections/points; POST create, convert, create-job-work, close; point resolution/disposal/escalation; multipart evidence |
| Work orders | maintenance/work-orders, records, masters, schedules; CRUD/action calls, mandates, groups, severity/remarks, reassign, checklist and evidence |
| Execution | staff-workorders/{id}/ complaint-execution, rectification, inspection mode drafts, photos, initialization and submit |
| Dashboard/reports | GET attention and summary, maintenance register, job work report |
| Scope/lookups | GET zones/divisions/depots/stations/infrastructure/lookup-options |

Dio uses Accept/Content-Type JSON, multipart for photo uploads; bearer injection skips specific unauthenticated auth endpoints. Refresh on 401, one retry, FormData clone and superseded-identity protection present. AUD-02 and AUD-03 remain session risks. Auth interceptor treats null refresh (including transient repository failure) as expired and invokes logout; confirm desired transient failure policy in staging.

Pagination helper bounds traversal to 20 requests with preferred page size 100 and truncation indicator, strips next-link origin to a path and avoids repeated pages. Server-side unpaginated bodies still need size testing. Idempotency headers are sent for selected queued operations, not evidence of actual server deduplication. Verify every mutating endpoint's retry-after-timeout semantics.

Required nonproduction integration: payload/schema compatibility, enum/null/empty responses, field-validation errors, 400/401/403/404/409/429/5xx, token rotation, duplicate commits, mixed-role/org denial, timeout/disconnection/recovery, upload size/type rules, pagination extremes and server version drift.

## Data integrity and migration

No Room/SQLite schema/migrations in the root mobile app. Persistence is serialized model JSON in SharedPreferences plus filesystem evidence, so schema evolution still needs old-version fixture tests. Cache detail/list serializers differ and must be compared against intended display/offline fields. Owner changes trigger wipe and replay filters user scope; these are source observations, not proof of isolation under I/O failure.

Test old serialized records/outbox with missing/unknown fields, partial/corrupt writes, both primary/backup failures, orphan photos, concurrent queue updates, conflict resolution, full disk, process kill after remote commit and before local acknowledgement, retention/deletion and restart. AUD-04 blocks data durability acceptance. No production data modified and no migration declared PASS.
