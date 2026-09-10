# GSSMS — Single API Contract Source of Truth (SSOT)

**Document:** `GSSMS_API_CONTRACT_SSOT.md`  
**System:** General Service Sub-Station Management System (GSSMS)  
**Clients:** GSSMS Web + GSSMS Android  
**API:** Django REST Framework, versioned under `/api/v1/`  
**Contract owner:** GSSMS Backend/API  
**Status:** Baseline contract derived from the latest uploaded Web and Android source trees  
**Baseline date:** 09 September 2026

---

## 0. Purpose

This document is the **single API contract source of truth for GSSMS Web and Android**.

The objective is to prevent API contract drift between:

```text
GSSMS Backend
      │
      ├── Web Application
      │
      └── Android Application
```

The backend API contract is authoritative.

Neither the Web client nor the Android client may invent API field names, enum values, status values, source values, filter parameters, or lifecycle transitions independently.

---

# 1. Non-Negotiable Contract Rules

## Rule 1 — Backend is authoritative

The following backend layers define the contract:

```text
Django Model
      ↓
Serializer
      ↓
ViewSet / API action
      ↓
Service / lifecycle rules
      ↓
API response
```

The Web and Android applications are consumers.

---

## Rule 2 — Do not infer contracts from UI models

A Flutter/Dart enum is not an API contract.

A Vue/JavaScript form object is not an API contract.

The following are not allowed to become API values merely because a client needs them:

```text
MOBILE
IN_PROGRESS
RESOLVED
PENDING
MEDIUM
etc.
```

A value must exist in the backend contract before a client sends it.

---

## Rule 3 — API field names are exact

Do not silently translate:

```text
notes → description
inspection_date → scheduled_date
scheduled_date → due_date
```

unless the API explicitly defines such aliases.

---

## Rule 4 — Enum values are exact

Display labels are separate from API values.

Example:

```text
API value:       ACTION_REQUIRED
Display label:   Action Required
```

Never send the display label unless the API explicitly requires it.

---

## Rule 5 — Server owns lifecycle transitions

Clients must not directly manipulate state fields when the backend provides a lifecycle/action endpoint.

Example:

```text
WorkOrder.status
```

must be changed through the authorised Work Order lifecycle mechanism.

---

## Rule 6 — Server owns defaults

If the backend has a default value, clients should normally omit the field unless there is a documented reason to override it.

Example:

```text
Complaint.source defaults to MANUAL
```

Android should not send:

```json
{"source": "MOBILE"}
```

---

# 2. Base API

Production API base:

```text
https://gssms.share.zrok.io/api/v1/
```

The Android application may receive the base URL through runtime configuration.

The canonical API prefix is:

```text
/api/v1/
```

Legacy `/api/` endpoints exist for the current Web application, but new Android API integrations must use `/api/v1/`.

---

# 3. Authentication

## 3.1 Login

```http
POST /api/v1/auth/login/
Content-Type: application/json
```

Request:

```json
{
  "username": "string",
  "password": "string"
}
```

Optional:

```json
{
  "username": "string",
  "password": "string",
  "otp": "string"
}
```

Successful response:

```json
{
  "access": "JWT_ACCESS_TOKEN",
  "refresh": "JWT_REFRESH_TOKEN"
}
```

---

## 3.2 Refresh

```http
POST /api/v1/auth/refresh/
```

Request:

```json
{
  "refresh": "JWT_REFRESH_TOKEN"
}
```

Response:

```json
{
  "access": "JWT_ACCESS_TOKEN",
  "refresh": "JWT_REFRESH_TOKEN"
}
```

The client must retain the previous refresh token if the response does not provide a replacement.

---

## 3.3 OTP Request

```http
POST /api/v1/auth/otp/request/
```

Request:

```json
{
  "email": "user@example.com",
  "purpose": "LOGIN"
}
```

Supported purpose values must be taken from the backend authentication implementation. Clients must not invent new purposes.

---

## 3.4 OTP Login

```http
POST /api/v1/auth/otp/login/
```

Request:

```json
{
  "email": "user@example.com",
  "otp_code": "123456",
  "purpose": "LOGIN"
}
```

Response:

```json
{
  "access": "JWT_ACCESS_TOKEN",
  "refresh": "JWT_REFRESH_TOKEN"
}
```

---

## 3.5 Password Reset

```http
POST /api/v1/auth/reset-password/
```

Request:

```json
{
  "email": "user@example.com",
  "otp_code": "123456",
  "new_password": "..."
}
```

---

## 3.6 TOTP

```text
POST /api/v1/auth/totp/setup/
POST /api/v1/auth/totp/verify/
POST /api/v1/auth/totp/validate/
```

TOTP-specific request/response fields are owned by the backend authentication implementation.

---

# 4. Authentication Header

Authenticated requests use:

```http
Authorization: Bearer <ACCESS_TOKEN>
```

Content type:

```http
Content-Type: application/json
```

unless the endpoint explicitly requires multipart/form-data.

---

# 5. Common HTTP Semantics

| Status | Meaning |
|---:|---|
| 200 | Successful read/update/action |
| 201 | Successful creation |
| 204 | Successful deletion/no content |
| 400 | Validation/business-rule error |
| 401 | Authentication required/invalid |
| 403 | Authenticated but not authorised |
| 404 | Resource not found or outside visible scope |
| 409 | Conflict, such as duplicate/lifecycle conflict |
| 422 | Only if explicitly introduced by the API contract |
| 429 | Rate limit |
| 500 | Server defect; client must not treat as validation |

---

# 6. Standard Validation Error Contract

DRF validation errors may be field based:

```json
{
  "field_name": [
    "Human-readable validation message."
  ]
}
```

or general:

```json
{
  "detail": "Human-readable message."
}
```

or action/service based:

```json
{
  "error": "Human-readable message."
}
```

or conflict:

```json
{
  "error": "Conflict description.",
  "existing_ticket": "WO-..."
}
```

## Client requirement

Android must extract the server response body.

It must NOT display raw Dio exceptions such as:

```text
DioException [bad response]
RequestOptions.validateStatus...
```

Production UI should display a concise message while development logging retains the structured server response.

---

# 7. Pagination Contract

Some endpoints return a bare list:

```json
[
  {...},
  {...}
]
```

Paginated endpoints return:

```json
{
  "count": 123,
  "next": "https://.../api/v1/...",
  "previous": null,
  "results": [
    {...}
  ]
}
```

Android must support both forms.

## Pagination rules

- Follow the server `next` link.
- Do not manufacture page URLs.
- Respect server page limits.
- Do not silently display a truncated result set as complete.
- If the client intentionally limits page traversal, the UI must indicate that results may be incomplete.

---

# 8. Organisation Scope

The backend is the authority for organisation scope.

Relevant dimensions include:

```text
zone
division
depot
station
```

Clients may provide supported filter parameters, but must never rely on client-side filtering for security.

The backend must enforce:

```text
authenticated user
        ↓
role
        ↓
organisation scope
        ↓
visible records
```

A user must never gain access to another organisation/depot by modifying a query parameter.

---

# 9. Lookup API

## Public authenticated lookup

```http
GET /api/v1/lookup-options/{domain}/
```

Response:

```json
{
  "domain": "complaint_department",
  "options": [
    {
      "id": 1,
      "domain": "complaint_department",
      "key": "ELECTRICAL",
      "label": "Electrical",
      "display_order": 1
    }
  ]
}
```

The client submits the `key`, not the display label.

---

## Current canonical lookup domains

```text
complaint_department
station_category
smi_sop_document_type
smi_sop_audience
```

Lookup domains are backend-owned.

Do not hard-code department choices in Android when the backend provides the lookup domain.

---

# 10. Complaint API Contract

## Endpoint

```http
GET    /api/v1/complaints/
POST   /api/v1/complaints/
GET    /api/v1/complaints/{id}/
PATCH  /api/v1/complaints/{id}/
DELETE /api/v1/complaints/{id}/
```

Additional action:

```http
POST /api/v1/complaints/{id}/convert_to_work_order/
```

---

## 10.1 Complaint canonical fields

Backend model fields:

```text
id
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

Additional serializer response fields include:

```text
station_name
depot_name
infrastructure_name
infrastructure_type
lc_gate_number
service_building_name
staff_quarter_name
asset_unique_id
is_converted
wo_id
wo_status
wo_ticket_number
```

---

## 10.2 Complaint source

Canonical values:

```text
MANUAL
IOT
```

Default:

```text
MANUAL
```

### IMPORTANT

`MOBILE` is **NOT** a valid Complaint source.

Android must NOT send:

```json
{
  "source": "MOBILE"
}
```

For a normal user-created complaint, omit `source` unless the API explicitly requires it.

---

## 10.3 Complaint status

Canonical values:

```text
OPEN
CONVERTED
CLOSED
```

Manual transition:

```text
OPEN
 ├── CONVERTED
 └── CLOSED
```

Once converted, the effective operational status is derived from the linked Work Order.

Android must not invent:

```text
IN_PROGRESS
RESOLVED
REJECTED
```

as Complaint status values.

---

## 10.4 Complaint department

The canonical domain is:

```text
complaint_department
```

Example:

```json
{
  "department": "ELECTRICAL"
}
```

The key must be obtained from the lookup API.

---

## 10.5 Complaint creation

Minimum business fields:

```json
{
  "title": "Station lighting failure",
  "description": "Platform lighting not functioning.",
  "department": "ELECTRICAL",
  "depot": 12
}
```

Optional relations:

```json
{
  "station": 45,
  "infrastructure": 78,
  "asset": 123
}
```

The user's depot may be enforced server-side for non-admin users.

If `infrastructure` is supplied:

```text
infrastructure.station must equal station
```

The backend may automatically derive station from infrastructure.

---

## 10.6 Complaint list filters

Supported canonical parameters:

```text
status
depot
division
zone
start_date
end_date
```

Example:

```http
GET /api/v1/complaints/?status=OPEN&depot=12&start_date=2026-09-01&end_date=2026-09-09
```

There is currently **no backend complaint severity field/filter**.

Android must not send:

```text
severity=HIGH
```

as a functional server-side complaint filter.

---

# 11. Inspection API Contract

## Endpoints

```http
GET  /api/v1/inspections/
POST /api/v1/inspections/
GET  /api/v1/inspections/{id}/
PATCH /api/v1/inspections/{id}/
```

Conversion:

```http
POST /api/v1/inspections/{id}/convert_to_work_order/
```

Pending-by-station:

```http
GET /api/v1/inspections/pending-by-station/
```

Export:

```http
GET /api/v1/inspections/export/
```

---

## 11.1 Inspection canonical fields

```text
id
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

Serializer adds:

```text
depot_name
created_by_name
created_by_first_name
created_by_last_name
created_by_role
created_by_designation
station_name
infrastructure_name
infrastructure_type
lc_gate_number
service_building_name
staff_quarter_name
is_converted
wo_status
wo_id
```

---

## 11.2 Inspection status

Canonical values:

```text
OPEN
ACTION_REQUIRED
CONVERTED
CLOSED
```

Manual transitions:

```text
OPEN
 ├── ACTION_REQUIRED
 └── CLOSED
```

Conversion:

```text
OPEN/ACTION_REQUIRED
        ↓
convert_to_work_order
        ↓
CONVERTED
```

Once converted, lifecycle state is tied to the linked Work Order.

Android must not use:

```text
PENDING
IN_PROGRESS
COMPLETED
CANCELLED
```

as backend Inspection status values.

---

## 11.3 Inspection creation

Canonical request:

```json
{
  "title": "Station inspection",
  "notes": "Observed abnormal condition in panel room.",
  "inspection_date": "2026-09-09T14:30:00+05:30",
  "depot": 12,
  "station": 45,
  "infrastructure": 78
}
```

Do NOT send the following unless the backend contract is explicitly extended:

```text
description
priority
source
asset
scheduled_date
inspection_points
```

---

## 11.4 Inspection list filters

Canonical backend parameters:

```text
status
depot
division
zone
start_date
end_date
pending_conversion
```

Example:

```http
GET /api/v1/inspections/?status=OPEN&depot=12&start_date=2026-09-01&end_date=2026-09-09
```

---

# 12. Work Order API Contract

## Base endpoint

```text
/api/v1/maintenance/work-orders/
```

## Standard endpoints

```http
GET    /api/v1/maintenance/work-orders/
POST   /api/v1/maintenance/work-orders/
GET    /api/v1/maintenance/work-orders/{id}/
PATCH  /api/v1/maintenance/work-orders/{id}/
DELETE /api/v1/maintenance/work-orders/{id}/
```

Actions:

```http
GET  /api/v1/maintenance/work-orders/{id}/allowed-actions/
GET  /api/v1/maintenance/work-orders/{id}/audit/
POST /api/v1/maintenance/work-orders/{id}/verify/
GET  /api/v1/maintenance/work-orders/{id}/verification-workspace/
POST /api/v1/maintenance/work-orders/{id}/change-status/
```

Related staff execution endpoint:

```http
POST /api/v1/staff-workorders/{id}/execute/
```

---

# 13. Work Order Canonical Enums

## Type

```text
PREVENTIVE
CORRECTIVE
BREAKDOWN
CALIBRATION
INSTALLATION
OTHER
```

## Priority

```text
CRITICAL
HIGH
MEDIUM
LOW
```

## Status

```text
NEW
ASSIGNED
IN_PROGRESS
TECH_COMPLETED
VERIFIED
CLOSED
ON_HOLD
CANCELLED
REWORK_REQUIRED
```

## Source

```text
MANUAL_ENTRY
IOT_ALERT
SCHEDULED_PM
```

### IMPORTANT

`MOBILE` is **not** a valid Work Order source.

---

# 14. Work Order Creation

Canonical business fields include:

```json
{
  "title": "Station Monthly Maintenance",
  "description": "Monthly maintenance work.",
  "type": "PREVENTIVE",
  "priority": "MEDIUM",
  "depot": 12,
  "station": 45,
  "infrastructure": 78,
  "asset": 123
}
```

`source` must be one of:

```text
MANUAL_ENTRY
IOT_ALERT
SCHEDULED_PM
```

For a normal manually created Work Order:

```text
source = MANUAL_ENTRY
```

If the backend already provides that default, clients should omit it.

---

# 15. Work Order Date Contract

The Work Order model contains:

```text
scheduled_date
```

The serializer exposes:

```text
due_date
```

as a **read-only derived field** from:

```text
original_schedule.due_date
```

Therefore:

### Creation

Do not treat:

```text
due_date
```

as the generic creation field.

### Read

`due_date` may appear in the response as a derived value.

This distinction is mandatory.

---

# 16. Work Order Assignment

Assignment uses:

```http
PATCH /api/v1/maintenance/work-orders/{id}/
```

Request:

```json
{
  "assigned_to": 456
}
```

The backend validates that the assignee is a maintenance technician:

```text
MAINTENANCE_STAFF
```

and enforces applicable depot restrictions.

---

# 17. Allowed Actions

Android must use:

```http
GET /api/v1/maintenance/work-orders/{id}/allowed-actions/
```

to discover server-authorised transitions.

Do not hard-code lifecycle permissions solely in Flutter.

The server remains authoritative.

---

# 18. Work Order Status Transition

Use:

```http
POST /api/v1/maintenance/work-orders/{id}/change-status/
```

Example:

```json
{
  "status": "IN_PROGRESS",
  "remarks": "Execution started."
}
```

Optional contract fields currently supported by Android:

```json
{
  "status": "TECH_COMPLETED",
  "remarks": "Maintenance completed successfully.",
  "checklist": {},
  "evidence": [101, 102]
}
```

The server decides whether the transition is allowed.

---

# 19. Work Order Verification

```http
POST /api/v1/maintenance/work-orders/{id}/verify/
```

Optional:

```json
{
  "remarks": "Verified at site."
}
```

Verification must use the dedicated endpoint because verification also controls `verified_by` and lifecycle/audit behaviour.

---

# 20. Assigned Technician Work Orders

Endpoint:

```text
/api/v1/staff-workorders/
```

Execution:

```http
POST /api/v1/staff-workorders/{id}/execute/
```

The endpoint is inherently scoped to the authenticated technician's assigned work.

Do not assume that arbitrary Work Order filters are supported by this endpoint.

Only parameters explicitly implemented by the backend should be sent.

Current date parameters implemented by the staff endpoint are:

```text
start_date
end_date
```

not:

```text
date_from
date_to
```

unless the backend contract is deliberately extended.

---

# 21. Maintenance Record API

Base:

```text
/api/v1/maintenance/records/
```

Standard:

```http
GET    /api/v1/maintenance/records/
GET    /api/v1/maintenance/records/{id}/
PATCH  /api/v1/maintenance/records/{id}/
```

Checklist:

```http
POST /api/v1/maintenance/records/{id}/submit_line/
```

Completion:

```http
POST /api/v1/maintenance/records/{id}/complete/
```

Report registration:

```http
POST /api/v1/maintenance/records/register_report/
```

---

# 22. Maintenance Record Checklist

Android currently submits:

```http
POST /api/v1/maintenance/records/{record_id}/submit_line/
```

The request body must match the current `MaintenanceRecordViewSet.submit_line` service/serializer contract.

### Rule

Do not define checklist line fields independently in Android.

If the checklist schema changes, update this contract first, then Web and Android.

---

# 23. Record Evidence

## Whole-record evidence

```http
PATCH /api/v1/maintenance/records/{record_id}/
Content-Type: multipart/form-data
```

Android uses:

```text
proof_of_execution_upload
remarks
other_staff
```

The current server-side limit used by Android is:

```text
JPEG
maximum 5 MB
```

---

## Line-scoped evidence

```http
POST /api/v1/maintenance/records/{record_id}/lines/{line_id}/attachments/
```

Multipart fields:

```text
kind
captured_at
image
```

`kind` is sent uppercase by Android.

---

## Delete line evidence

```http
DELETE /api/v1/maintenance/records/{record_id}/lines/{line_id}/attachments/{attachment_id}/
```

---

# 24. Complete Maintenance Record

```http
POST /api/v1/maintenance/records/{record_id}/complete/
```

Current Android request:

```json
{
  "technician_name": "Technician Name",
  "technician_signature": "SIGNED_DIGITALLY",
  "remarks": "Closing remarks of sufficient length.",
  "supervisor_name": "Supervisor Name",
  "supervisor_signature": "..."
}
```

Closing remarks must satisfy the backend lifecycle requirement.

Android currently enforces a minimum of:

```text
10 characters
```

The server remains authoritative.

---

# 25. Asset API Contract

## Endpoints

```http
GET /api/v1/assets/
GET /api/v1/assets/{id}/
```

The current Android implementation resolves QR/typed asset codes by searching the asset register and requiring an exact match.

There is currently no dedicated Android-only QR lookup endpoint.

---

# 26. Asset List Filters

Canonical parameters:

```text
search
asset_category
zone
division
depot
station
```

`asset_category` uses the **asset category code**, not the display name.

Example:

```http
GET /api/v1/assets/?search=VRI-STN-001&asset_category=CLS&depot=12
```

---

# 27. Asset Response Identity

Canonical identity fields include:

```text
id
unique_id
station
infrastructure
depot
asset_category
asset_type
sequence_number
serial_number
```

Display fields include:

```text
station_name
station_code
location_label
asset_category_name
asset_category_code
asset_type_name
asset_type_code
```

`unique_id` is server-generated and read-only.

---

# 28. Asset Warranty Status

Canonical backend response values:

```text
IN_WARRANTY
OUT_OF_WARRANTY
WARRANTY_YEAR_PRECISION
WARRANTY_MONTH_PRECISION
```

Android must use these exact API values.

UI labels may be different.

Example:

```text
WARRANTY_YEAR_PRECISION
        ↓
Warranty valid through year-end
```

Do not send:

```text
EXPIRING_SOON
EXPIRED
```

as backend warranty values unless the API is explicitly changed.

---

# 29. QR / Asset Resolution

The canonical client workflow is:

```text
QR / typed code
      ↓
GET /api/v1/assets/?search=<code>
      ↓
exact unique_id / serial_number match
      ↓
asset detail
```

A QR scan must never select the first partial search result.

---

# 30. Organisation API

Current endpoints:

```http
GET /api/v1/zones/
GET /api/v1/divisions/
GET /api/v1/depots/
GET /api/v1/stations/
```

These are reference/master data APIs.

Returned IDs must be used for relation fields.

Clients must not submit names where a Primary Key is required.

---

# 31. User/Profile API

```http
GET   /api/v1/users/
GET   /api/v1/users/{id}/
PATCH /api/v1/users/{id}/
```

Android currently uses:

```text
role=MAINTENANCE_STAFF
depot=<id>
```

for technician discovery.

Server-side permission/scope filtering is authoritative.

---

# 32. Dashboard API

Current Android endpoints include:

```http
GET /api/v1/maintenance/dashboard/summary/
```

and maintenance attention/schedule endpoints.

Dashboard data is a read projection.

The Android UI must not derive authoritative organisational counts from a subset of mobile records.

## 32.1 Organisation-scope filter parameters

`dashboard/summary/` accepts `zone_id`/`division_id`/`depot_id`, matching `maintenance/schedules/attention/`'s existing precedence — most-specific wins (`depot_id` > `division_id` > `zone_id`), sent as separate params, never combined into one AND'd filter. Previously this endpoint accepted `depot_id` only, which is why the Zone/Division filter did not appear for GLOBAL/ZONE-scoped roles (Super Admin/Zonal Admin) on the Dashboard and Maintenance Management screens — both screens' `OrgScopeAppBarFilter` are now `enableZoneDivision: true` (the default) to match.

`maintenance/records/register_report/` (the Reports screen's Maintenance Register) similarly now accepts `zone_id`/`division_id` alongside its existing `depot_id`/`station_id`, with the same most-specific-wins precedence among the org-scope params; `station_id`/legacy infrastructure-type params remain a separate, independently-applied filter.

`maintenance/work-orders/aging/`, `.../sla/`, `.../performance/`, `.../productivity/` similarly now accept `zone_id`/`division_id` alongside `depot_id`.

---

# 33. API Versioning

Current version:

```text
v1
```

All new mobile API calls must use:

```text
/api/v1/
```

When a breaking contract change is required:

```text
v1
 ↓
v2
```

Do not silently change the meaning of an existing v1 field.

---

# 34. Backward Compatibility Policy

A change is **breaking** if it changes:

- field name
- field type
- required/optional semantics
- enum values
- status meanings
- lifecycle transition rules
- response shape
- authentication requirements
- permission semantics

A breaking change requires:

1. Contract update
2. Backend implementation
3. Web update
4. Android update
5. Automated tests
6. Staging verification
7. Migration/deprecation plan where required

---

# 35. Client Development Rules

## Android

Android repositories/services must contain only values defined by this contract.

Before adding:

```dart
'new_field': ...
```

confirm that the backend contract contains it.

Before adding:

```dart
enum SomeStatus
```

confirm that the backend API exposes those values.

---

## Web

The Web application must use the same API semantics as Android.

If Web uses an unversioned `/api/` endpoint today, the corresponding `/api/v1/` contract must still be kept compatible.

---

# 36. Required API Contract Tests

Every writable API must have a server-side integration test covering the real serializer/service.

## Complaint

```text
POST valid complaint
POST invalid source
POST invalid department
POST mismatched station/infrastructure
PATCH allowed status transition
PATCH forbidden status transition
convert to work order
```

## Inspection

```text
POST valid inspection
POST invalid field
PATCH valid status transition
PATCH CONVERTED directly
convert to work order
duplicate conversion
```

## Work Order

```text
POST valid work order
POST invalid source
POST invalid type
POST invalid priority
assignment
allowed transition
forbidden transition
verification
duplicate complaint conversion
duplicate inspection conversion
```

## Maintenance

```text
execute
submit checklist line
upload evidence
complete
verify
close
retry
duplicate retry
```

---

# 37. Android Contract Tests

Android tests must validate the **repository-generated payload**, not only a manually supplied API-service payload.

Example:

```text
UI
 ↓
Repository
 ↓
Payload
 ↓
API Service
 ↓
HTTP mock
```

The test must inspect the final JSON body.

For Complaint, the regression test must prove:

```text
source != MOBILE
```

and preferably:

```text
source is omitted
```

so the backend default applies.

---

# 38. Contract Test Matrix

| Domain | Android → API | Backend | Required Result |
|---|---|---|---|
| Complaint source | MANUAL/default | MANUAL/IOT | PASS |
| Complaint status | OPEN/CONVERTED/CLOSED | Same | PASS |
| Complaint severity | Must not be sent | No field | PASS |
| Inspection fields | title/notes/inspection_date/relations | Same | PASS |
| Inspection status | OPEN/ACTION_REQUIRED/CONVERTED/CLOSED | Same | PASS |
| Work Order source | MANUAL_ENTRY/IOT_ALERT/SCHEDULED_PM | Same | PASS |
| Work Order type | Defined enum | Same | PASS |
| Work Order priority | Defined enum | Same | PASS |
| Work Order status | Defined enum | Same | PASS |
| Asset category | Code | Code | PASS |
| Asset warranty status | Backend values | Same | PASS |
| Date filters | start_date/end_date where supported | Same | PASS |
| Organisation scope | Server enforced | Server | PASS |
| Error body | Parsed | Structured | PASS |

---

# 39. Current Known Contract Corrections Required

These are mandatory before treating the latest Android build as fully compatible.

## FIX-001 — Complaint

Remove:

```dart
'source': 'MOBILE'
```

Use backend default:

```text
MANUAL
```

---

## FIX-002 — Complaint model

Remove Android-only server semantics for:

```text
severity
IN_PROGRESS
RESOLVED
REJECTED
```

unless the backend is deliberately extended.

---

## FIX-003 — Inspection

Change Android from:

```text
description
priority
source
asset
scheduled_date
inspection_points
```

to:

```text
notes
inspection_date
station
infrastructure
depot
```

as applicable.

---

## FIX-004 — Inspection status

Replace Android status vocabulary with:

```text
OPEN
ACTION_REQUIRED
CONVERTED
CLOSED
```

---

## FIX-005 — Work Order source

Remove:

```dart
'source': 'MOBILE'
```

Use:

```text
MANUAL_ENTRY
```

or omit it where backend default applies.

---

## FIX-006 — Work Order dates

Do not submit:

```text
due_date
```

as a generic creation field.

Use:

```text
scheduled_date
```

where creation requires a planned date.

---

## FIX-007 — Assigned Work filters

Use the exact staff endpoint parameters implemented by the backend.

Current staff date parameters:

```text
start_date
end_date
```

---

## FIX-008 — Asset warranty enum

Align Android with:

```text
IN_WARRANTY
OUT_OF_WARRANTY
WARRANTY_YEAR_PRECISION
WARRANTY_MONTH_PRECISION
```

---

# 40. Idempotency Contract

Idempotency must be treated as an API feature, not merely an Android header.

When supported by an endpoint:

```http
Idempotency-Key: <unique-key>
```

and optionally:

```http
X-Idempotency-Key: <same-key>
```

The server must define:

```text
key scope
key lifetime
payload binding
replay behaviour
conflict behaviour
```

## Required replay semantics

Same:

```text
authenticated user
+
endpoint
+
idempotency key
+
same request
```

must return the original operation result rather than creating a duplicate.

Same key with a different payload must return a conflict.

---

# 41. Offline Contract

Offline support is a **client capability**, but the server must provide deterministic mutation semantics.

Architecture:

```text
Field action
    ↓
Local durable outbox
    ↓
Idempotency key
    ↓
Server mutation
    ↓
Authoritative result
    ↓
Outbox completion
```

A queued operation must not invent a fake server ID.

The client must not mark a server-side operation complete until the server acknowledges it.

---

# 42. Conflict Handling

The client must distinguish:

```text
NETWORK FAILURE
VALIDATION FAILURE
AUTH FAILURE
PERMISSION FAILURE
CONFLICT
SERVER FAILURE
```

These are not interchangeable.

Examples:

```text
Network failure
→ retry

400 validation
→ user correction

401
→ refresh/re-authenticate

403
→ permission message

404
→ resource unavailable/outside scope

409
→ conflict workflow

500
→ report/retry according to policy
```

---

# 43. Security Contract

Authenticated API traffic must use HTTPS in staging/production.

Tokens must not be logged.

Sensitive request/response bodies must not be written to production logs.

Error logs must redact:

```text
password
access token
refresh token
OTP
TOTP secrets
```

Certificate pinning, if enabled, must be a real documented implementation with a rotation procedure. A configuration flag alone is not a pinning contract.

---

# 44. Generated OpenAPI Schema

The backend exposes:

```http
GET /api/v1/schema/
```

This endpoint should eventually become the machine-readable representation of this contract.

Recommended future architecture:

```text
Django models/services
        ↓
DRF serializers
        ↓
OpenAPI schema
        ↓
GSSMS_API_CONTRACT_SSOT.md
        ↓
Web client
        ↓
Android client
```

The Markdown document remains the human-readable engineering SSOT; OpenAPI should become the machine-verifiable contract.

---

# 45. API Change Procedure

No developer should directly modify Android and Web payloads independently.

Required workflow:

```text
1. Identify business/API change
        ↓
2. Update this SSOT
        ↓
3. Update backend serializer/service
        ↓
4. Add backend integration tests
        ↓
5. Update Web client
        ↓
6. Update Android client
        ↓
7. Add Android contract test
        ↓
8. Run staging smoke test
        ↓
9. Deploy backend
        ↓
10. Deploy compatible Android/Web clients
```

---

# 46. Production Release Gate

An Android release must not be promoted to production unless:

```text
[ ] Authentication works
[ ] Complaint create works
[ ] Inspection create works
[ ] Work Order create works
[ ] Asset search works
[ ] QR asset resolution works
[ ] Work Order lifecycle works
[ ] Checklist works
[ ] Evidence upload works
[ ] Completion works
[ ] Verification works
[ ] Offline read works
[ ] Offline mutation replay works
[ ] Duplicate replay is safe
[ ] 400 responses are correctly handled
[ ] 401/403 are correctly handled
[ ] Scope isolation is verified
[ ] Production API version matches client
```

---

# 47. Current Contract Status

## Backend

**AUTHORITATIVE**

The latest backend implementation is the source of truth.

## Web

**REFERENCE CLIENT**

Web behaviour is useful for UX/business-flow reference, but backend serializers/services override client assumptions.

## Android

**CONSUMER**

Android must conform to the backend contract.

---

# 48. Golden Rule for AI Coding Agents

When using Claude, Gemini, Codex, OpenCode or another coding agent:

> **Do not allow the agent to infer the GSSMS API contract from existing Android models, Web forms or old code.**

Give the agent this document first.

Required instruction:

```text
This file is the GSSMS API Contract SSOT.

The backend API contract is authoritative.

Before changing any API call:
1. Read this SSOT.
2. Inspect the current backend serializer/view/service.
3. Verify the endpoint and field names.
4. Do not invent enum/status/source values.
5. Do not change the contract silently.
6. If a required API change is discovered, update the SSOT first.
7. Update backend, Web, Android and tests consistently.
8. Report any contract mismatch instead of guessing.
```

---

# 49. Contract Ownership

This file should be stored in the GSSMS repository at a stable path such as:

```text
/docs/GSSMS_API_CONTRACT_SSOT.md
```

or:

```text
/GSSMS_API_CONTRACT_SSOT.md
```

There must be **one canonical copy** used by:

```text
Backend developers
Web developers
Android developers
QA
AI coding agents
DevOps/release process
```

Do not maintain separate competing copies such as:

```text
ANDROID_API.md
WEB_API.md
MOBILE_API.md
OLD_API.md
```

If a module needs additional implementation documentation, it should reference this contract rather than redefining it.

---

# 50. Final Contract Principle

The GSSMS API contract is not:

```text
whatever currently works on Android
```

and it is not:

```text
whatever currently works on Web
```

It is:

```text
                    GSSMS API
                       │
            Backend serializer/service
                       │
              ┌────────┴────────┐
              │                 │
             Web             Android
```

Both clients must implement the same server-defined semantics.

### Final rule

> **One business concept = one canonical API field, one canonical enum, one canonical lifecycle, one documented contract.**

This is the mechanism that prevents the `source=MOBILE` production failure and the related Complaint, Inspection and Work Order contract drift identified in the latest Web ↔ Android audit.
