# Offline reopen: focused reacceptance

Date: 24 October 2026, Asia/Calcutta

## Result

**A1, A3 and the requested quick A10 check passed on the phone for the follow-up dev build.**
F3's pending-line wording and a refused-refresh scenario also passed. This is
targeted reacceptance, not a rerun or blanket pass of every A1–A14 scenario.
One additional read-cache freshness gap, F4 below, remains open.

The original [failed acceptance report](PHONE_ACCEPTANCE_2026-10-24.md) remains
the historical baseline. The [0.3.7 production hotfix](HOTFIX_0.3.7_2026-10-24.md)
was built separately and excludes these runtime follow-ups.

## Configuration

- Phone: Android 14 CPH2381, ADB serial `61ac9e71`.
- Package used for all UI mutations: `com.ssee_vri.gssms_mobile.dev`.
- Runtime source: `ff3cb91f12491eb7520ca9f53758b1bafe302b20`, including F1/F3
  commit `3e89183`; exported separately to exclude concurrent photo edits.
- Dev APK SHA-256:
  `62cceb8abbfcbd4daecf7ee11026846c028faad46f337dd9f74cc7de28e64093`.
- This dev snapshot still reports 0.3.7+12; it is not the separately signed
  production hotfix artifact and must not be distributed as that artifact.
- Endpoint: `http://127.0.0.1:8766` over ADB reverse; disposable backend/database
  at `D:\gssms-test-backend\backend` and `D:\gssms-test-backend\ui.sqlite3`.
- Fully checked-out numeric fixture: work order 1, record 1, line 1. No group
  checkout fix, production mutation, upload or completion was tested.
- Independent output directory: `build/phone-reacceptance/`; the original
  acceptance files were not overwritten.

## Approved policy and implementation

The user chose **eight hours, one shift**, from the last successful online
sign-in or refresh. Offline use does not renew the window. A server profile's
earlier validity deadline shortens it.

The last verified identity and timestamps are stored in platform secure storage.
Restricted restore requires the protected profile user to match the cache owner,
Maintenance Staff permissions, an unexpired window and no backward time relative
to verified/last-used timestamps. Operational cache alone cannot create a session.

Restricted mode exposes saved, owned In Progress checklists and local line saves.
It does not send the old access token as a network credential. Operational API
requests and outbox draining are blocked until online revalidation; checkout
changes, attachments and completion are unavailable. Expiry ends access while
preserving the owned queue. Existing sign-out/account-change cleanup remains in
effect.

Boundary expiry, rollback, foreign-owner and profile-validity cases were verified
with unit tests. The phone was not kept offline for eight hours and its clock
was not changed to simulate expiry. The policy relies on device time with a
backward-clock guard, not a trusted external clock or instant offline revocation.

## Phone observations

| Check | Result | Evidence |
| --- | --- | --- |
| A1 / F1 | PASS | After downloading the record, airplane mode plus removal of the test reverse route no longer removed Open Checklist. It reopened the cached owned record. No Start/transition/approval fallback was added. |
| A3 / F2 | PASS | Cold offline restart opened Saved checklists instead of sign-in. Pending `91.5` reappeared. A later clean cycle saved `93.5`, force-stopped/restarted offline, reopened `93.5`, revalidated online and synced it. The final queue was empty and server value was `93.5`; an online reread displayed it. |
| Restricted save/controls | PASS | After cold restore, `92.5` could be saved locally. Connect to submit was disabled; the management menu was absent. Only the saved checklist landing and reconnect/sign-out controls were exposed. |
| F3 | PASS for pending line edits | Pending readings displayed Saved on this phone – waiting to sync, with row wording On phone. Last synced was suppressed while those line changes were queued. |
| A9 refused refresh | PASS for tested 401 scenario | Disabled only the disposable technician, then reconnected. Refresh returned 401; the app returned to sign-in with a queued-work-kept message. The exact owned `92.5` command remained PENDING and server value remained `0`. |
| A10 quick check | PASS | The other technician's online home showed no assigned work. Its cold offline restore showed No assigned checklists downloaded and an empty queue, not the first technician's cached checklist/value. |

The first attempt to reauthenticate the owner after the refusal was interrupted
by a phone-system screen; the login helper refused to type on an unexpected
screen. A subsequent account-switch sequence used the existing cleanup policy,
which clears the previous owner's queue on different-user login. Therefore no
owner-reauthentication recovery is claimed for that `92.5` attempt. The clean
`93.5` restart/reconnect cycle is the evidence for successful complete recovery.
The incidental unrelated screen artifacts were excluded and removed.

## New open item: F4 acknowledged read-cache freshness

After the clean home-screen replay acknowledged `93.5` and cleared the queue,
the downloaded record cache still held `0`. Opening the checklist online fetched
and cached server `93.5`. This was directly measured in the retained before/after
cache evidence; it is not a server data-loss claim.

Until fixed, a later offline visit can show the older downloaded read model if
the user has not refreshed the record online after home-screen replay. The
targeted F1/F2 checks above pass, but this prevents describing the offline cache
as fully reconciled after every sync.

**Next thin slice:** reconcile an acknowledged queued line into the owner-bound
read model before a later offline visit, without replaying an already acknowledged
mutation, changing queue format, or racing logout/account changes. Test home-only
sync followed directly by a cold offline read, persistence interruption and owner
switches. Do not turn this into a generalized sync/database rewrite.

## Automated checks

- Auth, sync and work-order regression run: **567 passed**.
- Final sync/restricted-save/control guard run: **68 passed** (overlaps the
  broader run; these are not 635 unique tests).
- Targeted analysis of changed implementation and new tests: no issues found.
- Retained-evidence cross-check: passed using
  `python tool/phone_acceptance/verify_reopen_evidence.py`.
- Evidence text scan checked actual generated test passwords, JWT structures,
  Bearer syntax and XML password fields. No matches/unmasked password were found.
  This is a bounded scan plus selected screenshot review, not a general secret
  certification. No push was performed.

The workspace-wide regression run includes independently edited photo-error
tests present locally. Those concurrent runtime/test edits were excluded from
both the signed hotfix and the isolated follow-up dev APK. No unrelated changes
were reset or committed by this task.

## Retained evidence

Selected artifacts are under `docs/acceptance/reopen-2026-10-24/`:

- `06-offline-detail`: offline entry button.
- `12-restored-value-visible`: restored pending value and wording.
- `26-final-cold-restore`, `27-final-restored-value`: clean offline restart.
- `25-final-queue`, `28-final-queue`, `28-final-server`: successful replay.
- `13-restricted-queue`, `14-refused-queue`, `14-refused-server`,
  `15-refusal-settled`: refused refresh preserves the queue.
- `20-current-test-state`, `21-other-offline-empty`, `21-other-offline-queue`:
  account isolation.
- `29-cache-before-online-read`, `30-cache-after-online-read`: F4.
- `server-events.txt`, `requests.jsonl`: local-only request evidence without
  tokens or passwords.

## Cleanup and production-package observation

The dev app was signed out and stopped. The test server and reverse mapping were
removed. Airplane mode, Wi-Fi and USB stay-awake were verified at their initial
values `0`, `1`, `0`. A nonzero final stay-awake command was followed by a read-only
check confirming the setting was restored. Cleanup evidence is retained.

Database snapshots outside Flutter cleanup:

- `ui.before-reacceptance-20261024.sqlite3`: prepared baseline.
- `ui.after-reacceptance-20261024.sqlite3`: completed run, preserved before reset.
- `ui.sqlite3`: restored baseline, SQLite quick check `ok`.

Only the dev package was installed by this test run. At cleanup, a read-only
inspection found the production package already at **0.3.7+12**, last updated
`2026-10-24 14:08:56`. Its installed APK checksum exactly matched the separately
prepared hotfix:
`bc60c99cdd51bc19f37d863d1591182aa997fd0d53c7632a15de1bb36214684a`.
That update predates this resumed test run and was not performed by its commands.
No assertion is made that every field phone has been updated or that an external
distribution service was used.

## Still open

- **F4:** acknowledged read-cache freshness, described above.
- **A11:** simultaneous-edit/version conflicts; no backend version-token fix
  was implemented or certified.
- **Other line types/commands:** repeat safety for deficiency/measurement side
  effects, uploads, start, transitions and completion remains unproven; backend
  duplicate protection is still a dependency.
- **Group check-out:** the fully checked-out workaround does not certify its
  separate fix.
- **A9 beyond the tested scenario:** other refresh refusal/failure modes retain
  their separate test/review requirements. The observed 401 path is now covered.
