# GSSMS Android App Business Logic Baseline — MBLF-0001

| Field | Value |
|---|---|
| Record ID | MBLF-0001 |
| Status | APPROVED_FROZEN for the 21 rule IDs in section 1; every other register row keeps the status stated in section 2 |
| Approver | D. Manikandan / SSE/E/VRI (Product Owner) |
| Approval date | 2026-10-19 |
| Baseline commit / tree | `b4c5024c62c212d266700e78d76300ce9e977f17` / `1c8606e74610f52e65c34760f5af15d8c2cee78b` (PROVISIONAL) |
| App version at baseline | `0.3.0+4` (tag `v0.3.0` plus later commits on branch `feat/checklist-kinds-s-v4`) |
| Register | `docs/governance/mobile_rule_register.csv` |
| Web baseline it depends on | `BLF-0001`, `docs/governance/BUSINESS_LOGIC_BASELINE.md` in the GSSMS web repository |
| Evidence basis | Code reading. `flutter test` on the baseline commit: 893 passed, 1 skipped, 0 failed. `flutter analyze` at the baseline: 141 issues, 136 info and 5 warnings (3 unused imports, 1 unused `ref.refresh` result, 1 deprecated analyzer plugin entry); the warnings were cleared in `fix(lint)` after the baseline and CI is green on `main` (`b9dea6a`: analyze, tests, dev-flavour debug APK build). No device, emulator or live-backend run. |

## What "frozen" means here

A frozen rule records what the app does at the baseline commit. It does not say the behaviour is the desired target. A frozen rule may change only through change control (section 6). The uncommitted working-tree changes that existed on the baseline branch when this record was written are **not** part of the baseline.

## 1. Frozen rules (21)

`MOB-AUTH-01`, `MOB-AUTH-02`, `MOB-AUTH-03`, `MOB-AUTH-04`, `MOB-AUTH-05`, `MOB-RBAC-01`, `MOB-RBAC-02`, `MOB-RBAC-03`, `MOB-RBAC-04`, `MOB-RBAC-05`, `MOB-RBAC-07`, `MOB-RBAC-08`, `MOB-RBAC-09`, `MOB-INS-03`, `MOB-INS-04`, `MOB-CMP-01`, `MOB-CMP-02`, `MOB-RTE-02`, `MOB-OFF-02`, `MOB-OFF-03`, `MOB-OFF-04`

## 2. Rules that are not frozen

| Status | Rules | Meaning |
|---|---|---|
| RECORDED_NOT_RATIFIED | `MOB-INS-01`, `MOB-INS-02`, `MOB-BG-01` | Accurate as built, held because an owner decision is still open (see each row's note) |
| OPEN_DEFECT | `MOB-RTE-01` | Mobile routes by origin first; the server routes by `execution_mode`. Read from both sides, not reproduced at runtime. |
| OPEN_GAP | `MOB-INS-05` | Inspection action buttons are offered to roles the server refuses. Fails closed. |
| PARTIAL | `MOB-INS-06`, `MOB-OFF-01`, `MOB-QR-01` | Behaviour partly read |
| UNVERIFIED | `MOB-RBAC-06`, `MOB-IOS-01` | `MOB-RBAC-06`: client policy read, server policy not read. `MOB-IOS-01`: iOS not reviewed. |
| NOT_IMPLEMENTED | `MOB-AUTH-06`, `MOB-GEO-01`, `MOB-NOT-01` | Called for by `MOBILE_APP_SSOT.md` (forced-update policy, geo-tagging, push notifications) but absent from the code |

The open defect and gap are scheduled for a separate test-first code slice that needs its own approval.

## 3. Documents

| Document | Role |
|---|---|
| `MOBILE_APP_SSOT.md` | A plan (Phases 0-7, 2026-08-29), not a record of what shipped. Its status refresh is a later housekeeping step. |
| `MOBILE_APP_IMPLEMENTATION_PLAN.md` | Delivery plan. |
| `SSOT/` | Holds byte-identical copies of the two documents above plus the API contract. Which copy is canonical is a later housekeeping decision. |
| `lib/features/auth/domain/rbac.dart` | The client-side role policy. The server stays the authority. |
| `CHANGELOG.md` | Stops at `0.3.0+4`; catching it up is a later step. |

## 4. Scope statements

- This record covers the Android app. iOS behaviour was not reviewed.
- Geo-tagging, push notifications and a forced-update check are not built.
- Web business rules are owned by `BLF-0001`; this record cites them and does not restate them.

## 5. Outstanding evidence and decisions

- ADD-05 / Q6: which Android builds are in the field, and how many point-less inspections exist in production.
- Runtime probe of `MOB-RTE-01` (a legacy-converted inspection Job Work opened from the app).
- Runtime check of the offline queue on a device (`MOB-OFF-01`, `MOB-OFF-04`, `MOB-BG-01`).
- Fate of the local-only branch `feat/mobile-narrative-execution` (2 commits not on any remote): merge, archive or discard.
- Re-baseline at the next mobile release tag.

## 6. Change control

- A change request names rule IDs.
- The owner's decision is recorded with date and approver.
- The register row and the governing document are updated together.
- An independent reviewer confirms code and test evidence.
- The record revision is bumped.
- A frozen rule may not change in a code-only commit.


## PM cancellation and due-period skip ? 23 October 2026

Android distinguishes **Cancel Job Work** from **Skip this due period**.
Cancelling a Job Work sends `USER_ERROR` cancellation metadata: the due remains
open and a replacement Job Work may be created. It does not skip maintenance.
The skip request is available from the Job Work overflow menu and the calendar
action in Pending Actions, including eligible legacy schedules without a Job
Work. Only existing authorised depot roles can request it; Division Admin
approval remains server-owned. Submission alone does not cancel work or clear
the due. Approval skips only the selected period, cancels eligible unstarted
linked Job Works, and preserves future maintenance; later periods can remain
overdue.

Before enabling submission, Android fetches the schedule and checks
`skip_supported`, `template_locked`, `has_pending_approval` and open status.
Recorded work from earlier attempts still blocks skipping. Failed lookups block
submission; server validation remains authoritative against concurrent changes.
Checklist-change eligibility remains obligation-based. Older servers fall back
to obligation-based skip eligibility; legacy support requires the backend skip
release and migration 0111 before rollout.

Validation: 528 targeted Flutter tests passed (work orders, pending actions,
maintenance schedules and version consistency; rerun on 24 October 2026). Full-app analysis and focused changed-source analysis
reported no issues. The signed production APK 0.3.6+11 was subsequently built and verified on
24 October 2026; see `docs/PRODUCTION_READINESS_2026-10-23.md`. No physical-device
test, production write or deployment was performed for this change.
