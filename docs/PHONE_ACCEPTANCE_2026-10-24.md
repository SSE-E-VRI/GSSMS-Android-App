# Phone acceptance: offline checklist slice

Date: 24 October 2026 (Asia/Calcutta)

## Verdict

**FAIL for the complete offline workflow.** The latest-edit and queued-value-overlay fixes work on the phone, but two additional blockers prevent a user from reopening prepared work entirely offline:

1. The work-order detail loses **Open Checklist** when the live allowed-actions request fails.
2. A cold offline app restart returns to sign-in because session restoration requires a network refresh.

No application code was changed during this acceptance run. These failures are recorded for a separate, focused implementation decision. No production records were used or changed.

## Tested configuration

| Item | Value |
| --- | --- |
| Phone | Connected CPH2381, Android 14; ADB device `61ac9e71` |
| Source | `e120746`, including fixes `69104a8` and `f5e0c83` |
| Test application | `com.ssee_vri.gssms_mobile.dev`, version 0.3.6+11, debug build |
| APK | `build/app/outputs/flutter-apk/app-dev-debug.apk` |
| APK SHA-256 | `9DA75F3F5583D293A30CF9E31D471D08CE4F24B4E5FF1AC071766CEAB0E36710` |
| Build defines | `APP_ENV=dev`, `GSSMS_BASE_URL=http://127.0.0.1:8765` |
| Connection | ADB reverse `tcp:8765`; backend bound to host loopback only |
| Backend source | `D:\gssms-test-backend\backend` |
| Disposable database | `D:\gssms-test-backend\ui.sqlite3` |
| Settings/runner | `tool/phone_acceptance/settings.py` and `run.py` |
| Fixture | Work order 1, `AUDIT-MIG-1`, title `OFFLINE ACCEPTANCE ONLY`; existing maintenance record 1; numeric checklist line 1; both fixture lines checked out |
| Test users | `audit_seed_tech` (ID 1) and `phone_slice_other` (ID 3), Maintenance Staff; generated local-only passwords |
| Check-out dependency | Avoided with a fully checked-out fixture. Group check-out/uncheck was not exercised and its separate fix is not certified. |

The backend was a copy with schema older than its source. A pre-test database snapshot was saved before applying its local migrations. The copied source has maintenance migrations through 0110; this run does not validate newer skip/cancellation features. This is an offline checklist test against the stated copy, not acceptance of every app/backend contract.

The backend is not identified by a clean Git revision. For source identification, SHA-256 of its `maintenance/services/execution_checklist_service.py` was `77ED5892B27B04D248D2BD4A1B5416049560788A517DB1936AAA06B5054F111F`. Its submit-line code still explicitly defers idempotency/version tokens to Phase 3.

This debug/dev run does not certify release performance, production TLS, release signing, all roles, other Android versions, or other offline command types.

## Acceptance results

| ID | Result | Phone evidence and limits |
| --- | --- | --- |
| A1 | **FAIL** | After caching detail/checklist online, enabled airplane mode and removed the test USB reverse port. Returning to detail removed Open Checklist. The prepared form could be edited if it was already open, but could not be reopened through the normal offline route. |
| A2 | **PASS, with UI caveat** | Offline value `1` was persisted as an owned pending command. The final edited value was persisted before it was inspected. The storage-failure case did not report a successful save. The checklist's generic Saved/Last synced wording still needs improvement; see finding F3. |
| A3 | **FAIL end to end; overlay component passed** | After force-stop and cold offline launch, the app showed sign-in. The persisted queue still held `12.5`. Separately, after online session restoration with replay deliberately blocked by 503, a fresh checklist load displayed queued `44.5` while the server remained at `33.5`. Thus the implemented overlay works, but offline session/navigation prevent the promised full journey. |
| A4 | **PASS** | Reconnect/resume sent `12.5` and cleared the queue. A later explicit tap on the home sync banner sent `44.5`, with server value and queue state verified. |
| A5 | **PASS for the selected assignment only** | Committed `33.5`, held the response, and force-stopped the app. The persisted command remained. Recovery retried the same key/payload and retained `33.5`, without extra rows/events in the checked tables. This is convergence for the selected simple assignment, not server-side key deduplication or a claim about other line types/side effects. |
| A6 | **PASS for tested controls** | Three rapid taps on the home sync banner while one request was delayed produced one new request. Repeated line autosaves left one pending assignment. |
| A7 | **PASS** | With airplane mode and no USB reverse route, offline edits stayed queued. A temporary 503 retained the command; removing the fault and explicit retry recovered it. |
| A8 | **PASS with scoped fault injection** | Made only dev `shared_prefs`/its operational XML unwritable. Editing showed `Could not save the reading: ... Could not save offline work...`; persisted queue was empty. Restored permissions, edited to `21.5`, and verified the pending command. Device-wide storage was not filled. |
| A9 | **PASS for access-token expiry** | Disposable backend issued 15-second access tokens. Queued `66.5` as user 3 while offline and waited beyond expiry. On explicit sync the endpoint returned 401, refresh returned 200, and retried submission returned 200. Queue cleared and server held `66.5`. Invalid/revoked refresh-token recovery was not tested. |
| A10 | **PASS for explicit sign-out/account switch** | With failed unsynced `55.5`, sign-out warned that the change would be lost. Cancel retained it. Confirmed discard and second-account login left no foreign queue; the second account saw server `44.5`, not discarded `55.5`. The record had been reassigned to that account, so its online access was legitimate. |
| A11 | **PARTIAL** | After offline `55.5`, reassigned the disposable work order from user 1 to user 3. User 1's replay was refused, command became FAILED/needs attention, and server stayed at `44.5`. Concurrent-version conflict resolution was not verified; the backend's version-token contract is still deferred. |
| A12 | **PASS for selected assignment/recovery setup** | Used server-controlled delays before the handler and after a committed handler result. Observed the chosen boundary, then ran `am force-stop` against the dev package. Before-commit kill retained `21.5` and server still held `12.5`; recovery reused the key and stored `21.5`. After-commit kill retained `33.5` until retry acknowledged it. The disposable backend was restarted to clear deliberately delayed requests before recovery; see limits below. |
| A13 | **PASS** | Same-line offline edits coalesced to the last value. Queue held one `12.5` command and the server ultimately held `12.5`. |
| A14 | **PASS** | Typed through `1` → `12` → `12.` → `12.5`, with pauses long enough to trigger intermediate autosaves. Final displayed and persisted value was `12.5`, not an earlier partial number. |

## Blocking findings

### F1 — Prepared checklist cannot be reopened from detail offline

Reproduction:

1. Open assigned work order and its checklist online.
2. Enable airplane mode and remove `tcp:8765` reverse mapping.
3. Return to work-order detail.
4. Observe that Open Checklist is absent, including after the detail screen settles.

Source: `lib/features/work_orders/presentation/screens/work_order_detail_screen.dart` requires server allowed-actions before rendering the resume button; `loadActionsAndAudit` drops actions on request failure.

Next focused change: provide a narrow way to open an already downloaded, owned, existing checklist under the offline-access policy. Preserve online-only transition/approval gates and server permission checks during replay. Do not invent allowed transitions or let cached status alone authorize privileged actions.

Evidence: [offline detail screenshot](acceptance/evidence-2026-10-24/11-offline-detail.png), [UI dump](acceptance/evidence-2026-10-24/11-offline-detail.xml).

### F2 — Offline cold launch cannot restore a working session

Reproduction:

1. Sign in and prepare the checklist online.
2. Disconnect, save `12.5`, and verify it is pending on disk.
3. Force-stop only the dev package and relaunch while disconnected.
4. Observe sign-in instead of access to the prepared work.

Source: `AuthRepository.restoreSession()` calls the refresh endpoint and returns null on transport failure. There is no offline session restoration path in this implementation.

The queued value was not lost: after reconnect/online restoration it synced. Do not fix this by bypassing authentication or granting permissions from an unbound cache. Define the permitted offline session lifetime and local access requirements, then implement the smallest bounded session-restoration path with owner isolation and server revalidation on reconnect.

Evidence: [offline restart screenshot](acceptance/evidence-2026-10-24/19-offline-restart-settled.png), [persisted queue after restart](acceptance/evidence-2026-10-24/18-after-restart-queue.json).

### F3 — Checklist sync wording can imply a server sync while work is pending

While line 1 was pending and disconnected, the checklist displayed a generic Saved marker and Last synced just now. The home page did correctly identify one change saved on the device. The screenshot does not establish which earlier timestamp update produced that wording: an earlier completed sync can remain visible after a new edit is queued. On the tested branch, `drainOutbox()` also assigns `lastSyncTime` after its main loop without checking that pending work is empty. Neither observation establishes the precise timestamp origin in this capture. The demonstrated defect is that the checklist renders Last synced while it has unsent changes.

This did not discard data in the tests, but it weakens confidence in whether a field reading reached the server. Follow-up should distinguish local persistence, attempted sync and acknowledged server sync. Keep this separate from the data-format changes, which remain unnecessary.

## Replay observations and limitations

- For the lost-response test, checked counts remained: one maintenance record, two lines, zero specification measurements, zero deficiencies, one work-order event, zero core activity logs.
- The selected fixture has no linked measurement specification or deficiency-producing status. Unchanged counts do not prove repeat safety for lines that create those effects, uploads, start execution, transitions or completion.
- Same keys appeared on original interrupted requests and recovery requests. The backend does not consume those keys for general duplicate protection.
- The delay middleware affects only submit-line requests on this loopback-only disposable server. In the pre-commit case a cancelled ASGI request lingered and delayed session refresh; restarting the disposable server removed that test fault before recovery. No actual cellular packet shaping or server-crash durability guarantee is claimed.
- The expiry test used real JWT expiry and the normal client refresh/retry path, not a fabricated 401 response.
- A first UI dump taken too early after launch returned no root and could have reused stale XML. It was excluded from the verdict. The helper was corrected to delete the old dump and require a fresh successful dump; the settled restart evidence is `19-offline-restart-settled`.
- An earlier lost-response setup attempt encountered the phone's lock screen and queued nothing; it was excluded. The completed cases are the numbered evidence described above.

## Evidence and reproducibility

Durable selected evidence is in `docs/acceptance/evidence-2026-10-24/`. It includes the two failure screenshots, restored-overlay screenshot, UI dumps, sanitized queue snapshots, request boundaries/keys, server-state counts and expiry logs. Generated passwords and token material are not included.

`python tool/phone_acceptance/verify_evidence.py` passed cross-checks of the retained queues, server values/counts, retry keys, repeated-tap count and failure/overlay UI dumps. These checks validate the recorded observations; they do not convert the failed overall acceptance into a pass.

Additional local-only screenshots/logs and generated test passwords are under `build/phone-acceptance/`; they may be removed by Flutter cleanup. No backend/database lives there.

The local runner explicitly chooses `D:\gssms-test-backend\ui.sqlite3`, a test signing key, in-memory email/cache/broker configuration, test media storage and loopback hosts. It does not use the stock settings' default database path.

Owner for setup/reset: the implementing assistant. To reproduce on this same machine, with the disposable server stopped:

```powershell
# Preserve existing snapshots; reset only the known seeded disposable database.
python tool/phone_acceptance/database.py reset

# Recreate local generated credentials if build artifacts were removed.
python tool/phone_acceptance/run.py seed

# Run only on loopback. USB reverse is needed for the phone.
python tool/phone_acceptance/run.py runserver 127.0.0.1:8765 --noreload
```

Use the explicit Python installation if the Windows `python` alias is not configured. The tested interpreter was `C:\Users\ADMIN\AppData\Local\Programs\Python\Python314\python.exe` with Django 6.0. ADB helpers are deliberately scoped to this phone serial and dev package; `edit.py`, storage-fault and interruption helpers require the observed screen/fixture state, not arbitrary unattended execution.

Database snapshots outside Flutter cleanup:

- `D:\gssms-test-backend\ui.before-phone-20261024.sqlite3`: pre-migration/pre-test copy.
- `D:\gssms-test-backend\ui.phone-baseline-20261024.sqlite3`: migrated, seeded reset baseline.
- `D:\gssms-test-backend\ui.after-phone-20261024.sqlite3`: completed-run database before reset.

## Cleanup and release decision

- Stopped the dev app and disposable server; cleared fault controls and removed only the test reverse mapping.
- Restored airplane mode to 0, Wi-Fi to 1, and USB stay-awake to 0, matching their initial settings.
- Restored dev preference permissions to directory 771/file 660.
- Preserved the completed-run database, then restored `ui.sqlite3` from the seeded baseline.
- Left the dev APK installed and stopped for later inspection. The production package was not updated, cleared or uninstalled.
- Production metadata before and after: versionCode 11, versionName 0.3.6, lastUpdateTime `2026-10-24 10:51:11`; [after-test metadata](acceptance/evidence-2026-10-24/production-package-after.txt).
- Final read-only cleanup verification is retained in [cleanup.json](acceptance/evidence-2026-10-24/cleanup.json); the local test port was not listening and no reverse mappings remained.

**Do not mark slice 1 accepted or ready for rollout.** Fix F1/F2 in focused increments, decide the offline-access policy, and rerun the full offline reopen journey. F3 and the unverified A11 conflict contract remain explicit follow-ups. The phone results support the two implemented data-layer fixes; they do not remove these release gates.
