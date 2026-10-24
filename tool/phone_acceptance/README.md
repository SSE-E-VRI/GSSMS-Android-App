# Local phone acceptance tools

These tools were used for the 24 October 2026 acceptance run. See
[`docs/PHONE_ACCEPTANCE_2026-10-24.md`](../../docs/PHONE_ACCEPTANCE_2026-10-24.md)
for results, tested fixture state, limitations and cleanup.

They deliberately target one disposable setup:

- Backend: `D:\gssms-test-backend\backend`
- SQLite: `D:\gssms-test-backend\ui.sqlite3`
- Phone serial: `61ac9e71`
- App: `com.ssee_vri.gssms_mobile.dev`
- Endpoint: `http://127.0.0.1:8765`, over ADB reverse

`run.py` isolates the backend import path and settings. Settings use a test-only
signing key, local email/cache/broker, and 15-second access tokens to exercise
expiry. This is not deployment configuration.

Stop the disposable server before `database.py reset`. That command restores
only the named SQLite file from `ui.phone-baseline-20261024.sqlite3`. `seed`
prepares the synthetic fixture and generates credentials under the ignored
`build/phone-acceptance/credentials.json`; do not commit that file. Resetting
does not clear phone data or reset test media. Slice 1 did not upload media.

The UI helpers are stateful acceptance aids, not a general test framework.
`navigate.py` verifies screen labels before tapping. Numeric input and the
storage/interruption helpers require the screen positions recorded in this run.
Do not run fault scripts on arbitrary screens. Keep the app awake/unlocked,
verify the dev package, and restore temporary device settings after testing.

`faults.py` supports controlled submit-line status/delay faults only in this
local runner. `interrupt.py` waits for a recorded request boundary before
force-stopping the dev app. `storage_fault.py` restores the tested preference
permissions in a finally block. ADB/process interruption outside those scripts
still needs explicit cleanup.

Selected sanitized evidence is retained under `docs/acceptance/`; additional
screenshots and logs under `build/phone-acceptance/` are disposable. No live
production endpoint or production credentials are needed for this setup.

For a separate run, set `GSSMS_PHONE_TEST_OUTPUT` to its workspace output folder
before running the seed, server and ADB helpers. The reopen reacceptance used
`build/phone-reacceptance/` and loopback port 8766, preserving the first run.
`audit_evidence.py` scans selected retained text against generated test passwords,
JWT/Bearer patterns and XML password fields without printing matched secrets.
