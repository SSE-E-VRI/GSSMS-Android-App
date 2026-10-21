# Functional verification matrix

Screen-by-screen paths and device status: [32-screen inventory](evidence/screen-inventory.md). Existing suite execution is recorded separately; source presence or a mocked widget assertion does not imply a feature PASS against Android/staging.

All scenarios below are planned acceptance cases, NOT RUN on a device/backend. Existing tests offer partial mock coverage, not complete acceptance coverage. Each row includes positive (P), negative (N), boundary (B), regression (R) cases.

| Feature/screens | P | N | B | R |
|---|---|---|---|---|
| Login | valid password login | wrong/disabled/unknown account | blank, whitespace, long credentials | double submit, logout during login |
| OTP email/verification | request and submit valid OTP; password reset | wrong/expired/locked/rate-limited code | resend interval, 6-digit inputs, pasted whitespace | cancel challenge, delayed response, app background |
| Profile | read/update fields, photo, password | invalid field, denied gallery, network failure | max lengths, empty response, large photo | rotate, restart, logout, server-side photo change |
| Home/Work/Maintenance/More | navigate allowed modules, theme persistence | permission absent/removed | empty assigned jobs, unknown role | back stack, session refresh, user switch |
| Dashboard | KPIs and attention render | summary failure and retry | zero and large counts | refresh, org scope changes |
| Assets list/detail + QR | filter/search, scan/manual lookup | invalid code, denied camera, missing asset | repeated scan, long spec/history, 2,000-row cap | background scanner, permission revocation, scope changes |
| Complaints list/detail/create | create, upload, convert, close | missing fields, 403/409/500 | max descriptions, duplicate tap, cancelled photo | return refresh, network timeout after committed POST |
| Inspections list/detail/create | points, evidence, resolution, escalation, job work | invalid transitions, wrong role, stale data | no points, many photos, large datasets | convert/close races, parent/point evidence parity |
| Deficiency list | filter/group, open linked record | unauthorized org scope | no records, unknown status | refresh following rectification |
| Work order list/detail/create | create, assign/reassign, start, filter/sort | role/mandate/transition rejection | due dates/timezones, unassigned work, double taps | logout race, stale response, interrupted create |
| Checklist | prepare, group inclusion, replace, save, submit | required unanswered, missing proof, denied permission | 0/1/many groups, long notes, many evidence files | autosave/dispose race, retry and process death |
| Complaint/inspection/rectification execution | draft, evidence, final submission | invalid mode/status, attachment errors | empty/large input, unsupported image | repeated submit, offline, retry after 401 |
| Verification workspace/pending actions | review, approve, reject with remarks | unauthorized/stale action | zero/all pending, changed role | concurrent approvers, report consistency |
| Job work/report register/detail/PDF | read, export if authorized, print/share | no reports.export, PDF/font/media failure | long labels, many pages, missing photos | parity fixtures, changed status, temporary file cleanup |
| Notifications | derived alerts, mark read/all, refresh | work order load failure, denied access | no alerts, many alerts | session switch, restart (read state in memory) |
| Energy placeholder | honest availability text/back | full meter/bill operation unavailable | small screen and large text | approved release scope; AUD-06 |
| Offline outbox (background within process) | queue, resume foreground, replay once | 401/403/409/5xx/offline, owner mismatch | retry cap/backoff, full disk, corrupt entry | kill between server commit and local persist, duplicate idempotency key |
| Auth/session and cache | refresh once, restore, wipe | expired guest, storage error | concurrent 401s, absent expiry claims | AUD-01 through AUD-04 fault injection |

## Evidence requirements

Record scenario ID, role, device/API, data fixture ID, steps, expected/actual, screenshots/logs and PASS/FAIL/BLOCKED. Test server authorization by requesting another user's/org's record directly in staging; hiding a control alone is insufficient. Mutations must use disposable nonproduction records only. Back navigation, keyboard, rotation, empty/loading/error states and duplicate interactions apply to every applicable screen.

No new test source added: the request requires approval for missing tests. Proposed regressions are documented in DEFECT_REGISTER.md.
