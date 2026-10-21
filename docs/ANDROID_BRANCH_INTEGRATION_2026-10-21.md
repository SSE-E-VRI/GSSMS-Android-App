# Remaining Android branch integration

The user explicitly authorized merging every remaining Android feature branch after the production-readiness audit was published. The audit directory remains a historical baseline for revision 83b3460; its original inventory and test counts do not describe this later integration.

## Branches included

- `feat/checklist-kinds-s-v4`: reconciled with main's newer production signing guard. Preserved the guard that only requires a keystore for prod-release tasks and retained disabled resource shortening/minification settings already on main.
- `feat/phase6-schedule-asset-parity`: merged asset-scoped schedule/dashboard fields, eligibility and template metadata, upcoming/conversion APIs, per-item batch outcomes, coded conflict handling and device completion timestamps.
- `fix/api-contract-checklist-template-conversion`: included through the schedule branch ancestry.
- `feat/mobile-narrative-execution`: merged narrative models/API/forms and record-based mode selection. Retained the existing checklist implementation as ChecklistFormScreen, including incomplete-line highlighting, replacement controls and offline support. Kept the newer work-order RectificationExecutionScreen unchanged; preserved the branch's record-based grouped form under RecordRectificationExecutionScreen so the old constructor and models cannot displace the newer failure-details workflow.

## Conflict decisions

Combined the existing batch result ticket summaries with the branch's structured schedule outcomes. Kept main's breakdown/skipped flags, organization and deficiency filters, FK parsing, version snapshots and execution modes while adding template/asset fields. Retained test cases from both sides and adapted the old create-conflict test to the current required-checklist form. Formatting was limited to merge-touched Dart files.

## Local validation

- `flutter test --no-pub --reporter expanded`: 996 passed, 1 skipped, 0 failed (1m50s). The optional report-parity renderer remains skipped without REPORT_PARITY_OUT.
- `flutter analyze --no-pub --no-fatal-infos`: exit 0; 133 informational diagnostics, no warning/error diagnostics. Existing CI policy is unchanged.
- Production packaging/signing and live backend/device verification were not run. Passing host tests and CI do not resolve the audit's production release blockers.

GitHub CI must additionally pass on the integration PR and the merged main commit. Existing backend checkout pointer and local .claude settings are outside this Android branch merge.
