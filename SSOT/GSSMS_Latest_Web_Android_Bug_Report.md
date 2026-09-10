# GSSMS Web ↔ Android — Latest Cross-Application Bug Report

**Scope:** Latest uploaded GSSMS Web project + latest uploaded GSSMS Android project  
**Analysis date:** 09 September 2026  
**Analysis type:** Static source/code-contract audit, endpoint comparison, model/serializer comparison, test-gap review  
**Production symptom reviewed:** Android "Log New Complaint" returns HTTP 400

> **Important:** This report is based on the latest uploaded source trees. It is not based on the earlier ZIPs. A live production API call was not executed from this analysis environment.

---

# 1. Executive Summary

The latest Android and Web applications are **not currently contract-compatible in several important areas**.

The complaint error shown in production is real and has a clear source:

```text
Android sends:
source = MOBILE

Backend accepts:
MANUAL
IOT
```

The same design mistake exists in **Inspection creation** and **Work Order creation**, making those additional high-risk production defects.

There are also read-side contract mismatches that will cause incorrect status/severity/warranty displays and filters even when HTTP requests succeed.

## Severity summary

| ID | Severity | Area | Finding |
|---|---|---|---|
| BUG-001 | **P0 / Critical** | Complaints | Android sends invalid `source=MOBILE`; backend only accepts `MANUAL` / `IOT` |
| BUG-002 | **P0 / Critical** | Inspections | Android create payload does not match backend model at all |
| BUG-003 | **P0 / Critical** | Work Orders | Android sends invalid `source=MOBILE`; backend only accepts `MANUAL_ENTRY`, `IOT_ALERT`, `SCHEDULED_PM` |
| BUG-004 | **P1 / High** | Complaints | Android uses non-existent `severity` field/status filters |
| BUG-005 | **P1 / High** | Inspections | Android status model and filters do not match backend statuses |
| BUG-006 | **P1 / High** | Inspections | Android parses `description` / `scheduled_date`; backend returns `notes` / `inspection_date` |
| BUG-007 | **P1 / High** | Work Orders | `assignedToMe` filters are sent with parameter names the staff endpoint ignores |
| BUG-008 | **P1 / High** | Assets | Android warranty-status enum does not match backend warranty-status values |
| BUG-009 | **P1 / High** | Error UX | Production exposes raw Dio technical exception instead of server validation message |
| BUG-010 | **P1 / High** | Offline | Android sends idempotency headers for mutations, but backend only implements idempotency for asset creation |
| BUG-011 | **P2 / Medium** | Security | Production "certificate pinning" is only HTTPS enforcement; no SPKI pinning exists |
| BUG-012 | **P2 / Medium** | Testing | Android tests validate mocked API shapes but do not validate complete Android repository → production serializer contracts |

---

# 2. BUG-001 — Complaint Creation Sends Invalid Source

**Severity:** P0 / Critical  
**Production confirmed:** Yes, consistent with the screenshot's HTTP 400.

## Android

File:

```text
lib/features/complaints/data/complaint_repository.dart
```

The repository builds:

```dart
final payload = {
  'title': title,
  'description': description,
  'department': department,
  'source': 'MOBILE',
  ...
};
```

## Backend

File:

```text
backend/complaints/models.py
```

The model defines:

```python
SOURCE_CHOICES = (
    ("MANUAL", "Manual"),
    ("IOT", "IoT"),
)
```

`MOBILE` is not a valid value.

The serializer is a `ModelSerializer` using:

```python
fields = "__all__"
```

Therefore the production API rejects the Android payload with HTTP 400.

## Correct fix

Prefer removing `source` from the Android complaint payload completely:

```dart
final payload = {
  'title': title,
  'description': description,
  'department': department,
  if (depotId != null) 'depot': depotId,
  if (stationId != null) 'station': stationId,
  if (infrastructureId != null) 'infrastructure': infrastructureId,
  if (assetId != null) 'asset': assetId,
};
```

The backend default then supplies:

```text
source = MANUAL
```

Do **not** add `MOBILE` to the backend unless the product explicitly requires platform provenance.

---

# 3. BUG-002 — Inspection Creation Is Contract-Broken

**Severity:** P0 / Critical

This is more serious than the complaint issue.

## Backend Inspection model

File:

```text
backend/inspections/models.py
```

The actual fields are:

```text
title
notes
inspection_date
status
station
infrastructure
depot
created_by
created_at
updated_at
```

There is no:

```text
description
priority
source
asset
scheduled_date
inspection_points
```

## Android sends

File:

```text
lib/features/inspections/data/inspection_repository.dart
```

Android sends:

```dart
{
  'title': title,
  'description': description,
  'priority': priority,
  'source': 'MOBILE',
  'asset': assetId,
  'station': stationId,
  'infrastructure': infrastructureId,
  'depot': depotId,
  'scheduled_date': scheduledDate,
  'inspection_points': inspectionPoints,
}
```

This is not the backend Inspection contract.

## Consequence

Inspection creation from Android is expected to fail with HTTP 400 because the request does not contain the backend's required `notes` / `inspection_date` contract and includes fields that are not part of the model serializer.

## Correct payload

The Android contract should mirror the Web form:

```json
{
  "title": "...",
  "inspection_date": "2026-09-09",
  "notes": "1. Observation...\n2. Observation...",
  "depot": 123,
  "station": 456,
  "infrastructure": 789
}
```

Do not send `priority`, `source`, `asset`, `scheduled_date`, or `inspection_points` unless the backend is intentionally changed to support them.

---

# 4. BUG-003 — Work Order Creation Sends Invalid Source

**Severity:** P0 / Critical

## Backend

File:

```text
backend/maintenance/models.py
```

Work Order source choices are:

```python
SOURCE_CHOICES = (
    ('MANUAL_ENTRY', 'Manual Entry'),
    ('IOT_ALERT', 'IoT Alert'),
    ('SCHEDULED_PM', 'Scheduled PM'),
)
```

## Android

File:

```text
lib/features/work_orders/data/work_order_repository.dart
```

Android sends:

```dart
'source': 'MOBILE',
```

`MOBILE` is invalid.

## Additional Work Order issue

Android sends:

```dart
'due_date': dueDate,
```

The backend serializer exposes `due_date` as a read-only derived field:

```python
due_date = serializers.ReadOnlyField(source='original_schedule.due_date')
```

The actual WorkOrder model contains:

```text
scheduled_date
```

Therefore the Android `due_date` value is not the correct creation field.

## Recommended correction

For manually created work orders:

```dart
'type': type,
'priority': priority,
```

Do not send `source: MOBILE`.

If scheduling is required, align the payload with the actual backend creation contract, likely using `scheduled_date`, subject to the backend's service/business rules.

---

# 5. BUG-004 — Complaint Severity Does Not Exist in Backend

**Severity:** P1 / High

Android defines:

```text
ComplaintSeverity
CRITICAL
HIGH
MEDIUM
LOW
```

and the complaint UI displays severity.

Android also sends/reads:

```text
severity
```

and supports severity filtering.

The current backend Complaint model contains no `severity` field.

Backend Complaint fields are:

```text
title
description
source
status
department
station
infrastructure
asset
depot
created_by
created_at
updated_at
```

## Consequences

### UI problem

Android will default missing severity to:

```text
MEDIUM
```

because:

```dart
this.severity = ComplaintSeverity.medium
```

So complaints can appear to have "Medium" severity even though the backend has no such field.

### Filter problem

Android may request:

```text
?severity=HIGH
```

but the backend `ComplaintViewSet.get_queryset()` does not apply a severity filter.

The UI can therefore show a count/filter that does not correspond to the server.

## Recommendation

Choose one:

### Option A — Remove severity from Android

Recommended if severity is not part of the current GSSMS complaint domain.

### Option B — Add severity properly to Web/backend

If severity is a required business feature, add it to:

- Django model
- migration
- serializer
- Web form
- API documentation
- filters
- Android model
- Android UI
- tests

Do not maintain a phantom Android-only field.

---

# 6. BUG-005 — Inspection Statuses Do Not Match Backend

**Severity:** P1 / High

## Backend

Inspection statuses:

```text
OPEN
ACTION_REQUIRED
CONVERTED
CLOSED
```

## Android

Android defines:

```text
PENDING
IN_PROGRESS
COMPLETED
CONVERTED
CANCELLED
UNKNOWN
```

Only:

```text
CONVERTED
```

matches.

Therefore normal backend inspection statuses such as:

```text
OPEN
ACTION_REQUIRED
CLOSED
```

will become:

```text
UNKNOWN
```

in Android.

## Consequences

- Incorrect status chips
- Incorrect list filters
- Incorrect counts
- Incorrect detail screen
- Potentially incorrect conversion logic
- User confusion

## Fix

Align Android enum exactly with the backend:

```text
OPEN
ACTION_REQUIRED
CONVERTED
CLOSED
```

Use display labels separately:

```text
OPEN            → Open
ACTION_REQUIRED → Action Required
CONVERTED       → Converted
CLOSED          → Closed
```

---

# 7. BUG-006 — Inspection Read Model Uses Wrong Field Names

**Severity:** P1 / High

## Backend returns

```text
notes
inspection_date
```

## Android reads

```dart
description: json['description']
scheduledDate: json['scheduled_date']
```

The Android model therefore does not correctly represent important backend data.

## Consequences

Inspection descriptions/notes can appear empty.

Inspection dates can appear missing.

The detail screen can show:

```text
N/A
```

even though the server has the information.

## Fix

Android should map:

```dart
description: asJsonString(json['notes']),
inspectionDate: parseDate(json['inspection_date']),
```

Prefer naming the domain property `notes` rather than pretending the backend field is `description`.

---

# 8. BUG-007 — Assigned-To-Me Work Order Filters Are Incorrect

**Severity:** P1 / High

Android uses:

```text
/api/v1/staff-workorders/
```

when:

```text
assignedToMe = true
```

This is correct for getting the technician's own work.

However Android sends:

```text
status
type
date_from
date_to
zone_id
division_id
depot_id
station_id
```

The StaffWorkOrderViewSet currently reads only:

```text
start_date
end_date
```

and inherently scopes to:

```text
assigned_to = request.user
```

It does not implement the other filters shown above.

## Consequence

A technician selecting filters in the Android UI can receive results that do not respect those filters.

Most importantly:

```text
date_from/date_to
```

are not the names expected by the staff endpoint.

## Fix

Either:

### Option A

Make the Android UI use only filters actually supported by `/staff-workorders/`.

### Option B — Recommended

Extend the backend staff endpoint with the same filter contract intentionally required by mobile.

Do not silently send unsupported parameters.

---

# 9. BUG-008 — Asset Warranty Status Contract Mismatch

**Severity:** P1 / High

## Android expects

```text
IN_WARRANTY
EXPIRING_SOON
EXPIRED
UNKNOWN
```

## Backend AssetSerializer returns

```text
IN_WARRANTY
OUT_OF_WARRANTY
WARRANTY_YEAR_PRECISION
WARRANTY_MONTH_PRECISION
```

Therefore Android's parser will classify several legitimate backend values as:

```text
UNKNOWN
```

## Consequence

Warranty information displayed on the Asset screen can be wrong or incomplete.

## Fix

Use the backend's canonical values.

Do not invent a separate mobile warranty vocabulary unless the mapping is explicit.

For example:

```text
IN_WARRANTY
OUT_OF_WARRANTY
WARRANTY_YEAR_PRECISION
WARRANTY_MONTH_PRECISION
```

Then provide friendly UI labels separately.

---

# 10. BUG-009 — Production Error Handling Is Too Technical

**Severity:** P1 / High

The Android complaint screen displays the raw Dio exception:

```text
DioException [bad response]
RequestOptions.validateStatus...
status code 400...
developer.mozilla.org...
```

This is unsuitable for production.

More importantly, the useful server validation body is not being presented clearly.

## Recommended architecture

### Development

Log:

```text
HTTP status
endpoint
request payload
server response
```

with secrets redacted.

### Production

Show:

```text
Unable to log complaint.

The server rejected the submitted details.

Please check the required fields and try again.
```

If the server returns structured field validation:

```json
{
  "source": ["\"MOBILE\" is not a valid choice."]
}
```

the app should convert it into a readable error.

---

# 11. BUG-010 — Offline Idempotency Is Not Yet End-to-End

**Severity:** P1 / High

Android correctly sends:

```text
Idempotency-Key
X-Idempotency-Key
```

for several work-order mutations.

However the latest backend implements idempotency specifically around Asset creation.

Repo-wide backend inspection did not find a general idempotency mechanism for:

- Complaint creation
- Inspection creation
- Work-order transitions
- Checklist line submission
- Maintenance record completion
- Evidence uploads

## Consequence

The Android outbox can replay a mutation with an idempotency key, but the backend may simply ignore the key.

A retry can therefore result in:

- duplicate operations
- conflicting state transitions
- duplicate evidence
- duplicate records
- inconsistent audit history

The exact duplicate behaviour varies by endpoint.

## Fix

Before declaring offline mutation delivery production-safe:

1. Define a server-wide idempotency contract.
2. Persist idempotency keys server-side.
3. Bind key to authenticated user.
4. Bind key to request/payload hash.
5. Return the original result on replay.
6. Return conflict if the same key is reused with a different payload.
7. Add expiry/retention policy.
8. Add endpoint-specific tests.

---

# 12. BUG-011 — Certificate Pinning Is Not Actually Implemented

**Severity:** P2 / Medium security risk

The Android configuration calls this:

```text
enableCertPinning
```

for production.

However `dio_client.dart` explicitly says the implementation is only:

```text
HTTPS-only enforcement
```

There is no SPKI certificate pin set.

Therefore:

```text
TLS encryption: YES
SPKI certificate pinning: NO
```

This is an architectural/security gap, not a cosmetic issue.

## Recommendation

Either:

1. Implement proper SPKI pinning with a rotation procedure, or
2. Rename the setting to accurately describe what it does.

Do not claim certificate pinning in release/security documentation until it actually exists.

---

# 13. BUG-012 — Test Suite Has Contract Blind Spots

**Severity:** P2 / Medium

The Android API tests use mocked responses and therefore can pass while the production Django serializer rejects the request.

For example, the complaint API test validates that:

```text
POST /api/v1/complaints/
```

is called.

It does not validate the repository's actual production payload containing:

```text
source = MOBILE
```

Likewise the inspection tests accept payload shapes that do not correspond to the current Django Inspection model.

## Required test layer

Add cross-contract tests covering:

```text
Android Repository
       ↓
Payload
       ↓
Django Serializer
       ↓
Expected response
```

The highest-value cases are:

- Complaint create
- Inspection create
- Work Order create
- Work Order transition
- Checklist line submission
- Evidence upload
- Asset retrieval
- QR lookup
- Authentication
- Assigned work-order filters

---

# 14. Additional Architecture Findings

## 14.1 Production URL

Android defaults to:

```text
https://gssms.share.zrok.io
```

This is a tunnel-style hostname.

If this is intentionally your production ingress, document its operational guarantees, certificate lifecycle and availability characteristics.

For a long-lived production railway application, a controlled permanent production hostname/reverse proxy is preferable.

---

## 14.2 Offline cache uses SharedPreferences

The Android implementation currently stores operational cache/outbox data using:

```text
SharedPreferences
```

The mobile SSOT already identifies Drift as the future durable store.

This is acceptable for the current limited implementation but is not an ideal long-term store for a growing operational outbox containing:

- work-order mutations
- checklist lines
- evidence paths
- sync state
- conflict state

Move to a proper local database before the offline workload becomes large.

---

## 14.3 Background sync is not complete

The Android SSOT identifies background sync as unfinished.

Current synchronization is primarily foreground/application-triggered.

Therefore do not advertise:

> reliable background offline synchronization

until Android background execution and recovery have been tested on real devices.

---

# 15. Cross-Application Contract Matrix

| Domain | Web | Backend | Android | Result |
|---|---|---|---|---|
| Complaint source | Manual | MANUAL/IOT | MOBILE | **FAIL** |
| Complaint severity | Not present | Not present | Present | **FAIL** |
| Complaint status | Backend-driven | OPEN/CONVERTED/CLOSED | OPEN/IN_PROGRESS/RESOLVED/CLOSED/REJECTED | **FAIL** |
| Inspection create fields | notes/date | notes/date | description/priority/source/asset/scheduled_date/points | **FAIL** |
| Inspection status | Backend-driven | OPEN/ACTION_REQUIRED/CONVERTED/CLOSED | PENDING/IN_PROGRESS/COMPLETED/... | **FAIL** |
| Inspection read fields | notes/date | notes/date | description/scheduled_date | **FAIL** |
| Work order source | Backend-driven | MANUAL_ENTRY/IOT_ALERT/SCHEDULED_PM | MOBILE | **FAIL** |
| Work order type | Supported | Same | Same | PASS |
| Work order priority | Supported | Same | Same | PASS |
| Work order status | Supported | Same | Same | PASS |
| Work order actions | Supported | Server state machine | Uses allowed-actions | PASS |
| Assigned WO filters | Web filters | Staff endpoint limited | Sends unsupported filters | **FAIL** |
| Asset unique ID | Supported | Same | Same | PASS |
| Asset category filter | Supported | Code-based | Code-based | PASS |
| Asset warranty status | Backend-derived | OUT_OF_WARRANTY etc. | Different enum | **FAIL** |
| QR scan | Supported | by-code + QR infrastructure | Camera scanner | PASS |
| Evidence attachment | Supported | Server endpoint exists | Endpoint exists | CONDITIONAL |
| Offline mutation idempotency | Not required by Web | Mostly absent | Headers sent | **RISK** |
| HTTPS | Yes | Yes | Yes | PASS |
| SPKI pinning | N/A | N/A | Not implemented | **OPEN** |

---

# 16. Priority Fix Plan

## P0 — Fix before next production APK

### P0.1 Complaint

Remove:

```dart
'source': 'MOBILE'
```

### P0.2 Inspection

Replace Android inspection payload with the actual backend contract:

```text
title
notes
inspection_date
depot
station
infrastructure
```

Align the model and status enum.

### P0.3 Work Order

Remove:

```dart
'source': 'MOBILE'
```

and replace incorrect `due_date` creation semantics with the actual backend field/workflow.

---

# 17. P1 — Fix before broad field deployment

1. Remove or properly implement complaint severity.
2. Align complaint statuses.
3. Align inspection statuses.
4. Align inspection response field names.
5. Fix assigned-work filters.
6. Align asset warranty statuses.
7. Replace raw Dio error display.
8. Complete server-side idempotency.
9. Verify offline replay behaviour.
10. Add real integration/contract tests.

---

# 18. P2 — Hardening

1. Implement true SPKI pinning.
2. Move operational outbox to Drift.
3. Implement reliable background sync.
4. Establish permanent production ingress if appropriate.
5. Add automated OpenAPI/client contract validation.
6. Add release smoke tests against staging.
7. Add role/scope matrix testing.

---

# 19. Recommended Release Gate

Do not release the next Android APK to all field users until this test matrix passes.

```text
AUTH
 ├── Login
 ├── Token refresh
 ├── Logout
 └── Role/scope

COMPLAINT
 ├── Create
 ├── List
 ├── Detail
 ├── Filters
 └── Conversion

INSPECTION
 ├── Create
 ├── List
 ├── Detail
 ├── Filters
 └── Conversion

ASSET
 ├── List
 ├── Search
 ├── Filter
 ├── Detail
 └── QR

WORK ORDER
 ├── List
 ├── Assigned work
 ├── Detail
 ├── Assignment
 ├── Start
 ├── Checklist
 ├── Evidence
 ├── Technician completion
 ├── Supervisor verification
 └── Closure

OFFLINE
 ├── Read cache
 ├── Mutation queue
 ├── Retry
 ├── Duplicate retry
 ├── Conflict
 ├── Logout/re-login
 └── Process death

SECURITY
 ├── HTTPS
 ├── Token handling
 ├── RBAC
 ├── Scope
 ├── Media access
 └── Certificate policy
```

---

# 20. Final Assessment

The latest projects are **not yet API-contract synchronized**.

The production complaint failure is only the first visible symptom.

The most important discovery is that the same Android/Web contract drift appears in multiple modules:

```text
Complaint       → source mismatch
Inspection      → payload + status + response mismatch
Work Order      → source + date semantics mismatch
Assigned Work   → filter contract mismatch
Assets          → warranty status mismatch
```

This means the correct response is **not to patch only the complaint screen**.

## Recommended engineering approach

Create one canonical API contract for each operational domain:

```text
ComplaintContract
InspectionContract
AssetContract
WorkOrderContract
MaintenanceRecordContract
EvidenceContract
AuthContract
```

The Web and Android clients must consume the same contract.

Django remains the server authority.

The Android client should not invent:

- new status values
- new source values
- new field names
- new filter parameters

unless the backend contract is changed deliberately first.

### Release principle

> **Every Android write operation must be proven against the current Django serializer/service contract before the APK is promoted to production.**
