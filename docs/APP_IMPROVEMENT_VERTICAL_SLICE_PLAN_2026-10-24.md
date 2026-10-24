# GSSMS app improvement plan: smallest working vertical slices

Date: 24 October 2026
Status: Approved approach with review changes incorporated; no implementation or new device validation completed by this document.

## 1. Objective

Improve execution speed, reduce RAM usage, make the essential field workflow reliable offline, and fix verified security vulnerabilities. Deliver working, reviewable increments instead of starting with a broad rewrite.

Apply these principles throughout:

1. **Thinnest vertical slice:** implement one user action through UI, local persistence, synchronization and server confirmation.
2. **Working software first:** every slice ends with a runnable app and evidence that the workflow works.
3. **Simplest thing that works (YAGNI):** reuse existing components; introduce infrastructure only when a demonstrated requirement cannot be met safely with them.

The first deliverable is one reliable offline checklist submission. It is not a claim that every app feature works offline or that the entire app has been security-certified.

**Slice 1 is an offline-reliability delivery. Speed and RAM improvement work starts after this slice unless an observed performance problem justifies an earlier bounded fix.** Security triage and optional performance investigation run as separate work tracks, not extra sequential prerequisites for demonstrating the offline save. Confirmed serious security issues still require immediate attention and block unsafe rollout.

## 2. Current starting point

Source inspection identified existing capabilities that should be retained and verified before extending them:

| Area | Existing implementation | Planning implication |
| --- | --- | --- |
| App | Flutter with Riverpod and Dio | Improve the current application incrementally. |
| Cache | `lib/core/database/local_cache_service.dart` stores work-order lists, details, maintenance records and outbox JSON using SharedPreferences | Start here; assess persistence and scale through tests rather than assume a database rewrite is needed. |
| Offline mutations | `lib/core/sync/outbox_command.dart` defines command types, ownership, idempotency keys and pending/failed/conflict states | Reuse these contracts and avoid a second queue. |
| Replay | `lib/core/sync/sync_manager.dart` contains retry/backoff and replay handling | Verify and repair the actual behavior before adding new scheduling. |
| Work-order rules | `lib/features/work_orders/data/work_order_repository.dart` supports offline actions and explicitly requires connectivity for verification/closure | Preserve business rules; do not make privileged actions offline merely for convenience. |
| Server-created records | Starting execution offline queues a request but does not provide a real maintenance-record ID | Use an existing server-created record for the first editable offline workflow. |
| Images | Evidence normalization already uses an isolate; source bytes are read into memory | Profile before changing the pipeline; an isolate alone does not establish lower total RAM. |
| Lists | `lib/core/network/paginated_fetch.dart` walks pages with a cap | Investigate actual first-screen delay and memory before replacing list behavior. |
| Android release | R8/resource shrinking is disabled with a documented plugin compatibility issue | Treat shrinking as a separate experiment, not the first RAM fix. |
| Prior validation | `docs/PRODUCTION_READINESS_2026-10-23.md` records historical checks and remaining acceptance gates | Rerun relevant checks against the current source; historical success is not current acceptance. |

These observations are not measured performance findings or confirmed vulnerabilities. App-wide offline coverage and backend security remain to be established.

### Known gaps from the implementation review

The reviewer identified the following by reading code; they have not yet been reproduced on a phone. Treat them as known code-review findings to reproduce and fix, rather than open-ended discovery tasks:

1. **Later offline edits are silently dropped.** Pending-line duplicate matching keeps the older value for the same line. Auto-save can queue a partial number such as `1` or `12` while the user finishes typing `12.5`, then falsely report later edits as saved. First priority: replace/coalesce an unsent pending value with the newest successfully persisted value for the same owner, record and line.
2. **Pending values disappear from the displayed checklist after restart.** The cached maintenance record retains the old server value. Restore the visible pending value from the persisted outbox and overlay it on cached data; do not add an independent draft store.
3. **Backend idempotency enforcement is missing for most maintenance actions.** The reviewer found a backend note deferring handling to Phase 3. Sending a client key is not server deduplication. The exact disposable-backend revision and endpoint behavior must be recorded during Step 1.

Setting the same existing checklist-line value is the best first candidate because repeating an assignment may converge on the same value. This is a hypothesis to verify, including audit/events and other side effects, not an exactly-once guarantee. Starting execution, status transitions, completion and photo uploads must be treated as unsafe to repeat until endpoint-specific backend protection is implemented and tested.

### Dependencies and disposable-backend ownership

- **Execution owner:** the implementing assistant is responsible for preparing the relocated disposable backend and test users used on 23 October, recording its revision and resetting its fixtures. This is a responsibility assignment, not authorization to message another chat or modify production.
- **Phone-test dependency only:** the group check-out mismatch fix from 23 October, reported as being handled by another assistant, must be verified in the disposable backend before affected phone tests. Alternatively, use a test work order whose checklist is already fully checked out and verify that this avoids the mismatch. This dependency does not block app code fixes or unit tests. Record the patch reference or checked-out fixture used; do not assume the fix has landed or duplicate another assistant's work.
- **Setup:** verify that the backend uses an isolated disposable database, local media directory and test-only configuration; create/reset disposable technician users and one assigned work order with an existing maintenance record and numeric checklist line. Record the phone-reachable endpoint and use the existing dev flavor/environment policy.
- **Reset:** provide one documented, repeatable fixture reset command against the explicitly identified disposable database and media directory only. Reseed the baseline fixture before each destructive/replay scenario and record fixture IDs. Do not reset production or reuse production credentials/data.
- **Readiness evidence:** write down the owner, backend path/revision, reset command, endpoint, fixture identifiers and check-out fix reference in the acceptance notes before device mutation tests. If yesterday's copy cannot be located or is not isolated, backend readiness remains blocked; do not invent its location or report staging acceptance as passed.

### Readiness notes — 24 October implementation

- Moved `D:\GSSMS-Android-APP\build\uitest\backend` to **`D:\gssms-test-backend\backend`**.
- Moved `D:\GSSMS-Android-APP\build\uitest\ui.sqlite3` to **`D:\gssms-test-backend\ui.sqlite3`**. Both original paths are absent after the move. The backend and database are now outside Flutter's `build` cleanup scope.
- No running Python process referencing `uitest` was reported by the pre-move process check. A read-only SQLite `PRAGMA quick_check` after relocation returned `ok`.
- Post-move database SHA-256: `AC85ED3E3EE104FB329F59CE4328AF245AE4F21537DEDB7E828A8F830816EB8D`.
- Owner: implementing assistant. App-side work proceeds independently of backend readiness. No phone mutation test or production mutation was performed for these app fixes.
- Before phone tests, explicitly configure the relocated backend to use `D:\gssms-test-backend\ui.sqlite3`; the inspected stock settings otherwise default to `backend\db.sqlite3` (or `backend\db_test.sqlite3` for test settings). Moving files does not prove the launch configuration uses the intended database.
- Backend revision, launch command, reset/reseed command, fixture IDs, phone-reachable endpoint and check-out patch/alternative fixture still require recording before phone acceptance. The relocation and database integrity check do not establish those gates as complete.
- Saved queue JSON keys, command types and status codes remain unchanged by the two app fixes; existing queued commands continue to use the current decoder.

### App-side implementation evidence — 24 October

- Pending same-line assignments now persist the latest value under the queue lock; identical payloads retain normal deduplication. Different accounts and failed/conflicting commands are not silently coalesced.
- Checklist autosaves execute in invocation order. An existing pending line assignment takes the queue path on reconnect, preventing an older queued value from replaying over a newer direct save.
- Record loads overlay outstanding owned line assignments from the persisted queue on cached or freshly fetched server data. The underlying server cache and queued command format are unchanged. Clearing a reading or option is preserved.
- Unit regressions cover numeric autosaves through `12.5`, repeated edits, persistence failure, in-flight acknowledgment, reconnect ordering, fresh-instance restore, explicit clears, foreign/unowned commands and failed/conflicting commands.
- Sync and work-order data/presentation regression suites: **407 passed** using `flutter test --no-pub --concurrency=2 test/core/sync test/features/work_orders/data test/features/work_orders/presentation`. Evidence: `build/offline-slice-regression-20261024.log`.
- An earlier higher-concurrency run exhausted host memory; the completed lower-concurrency run above is the acceptance result.
- Direct Dart analysis of the two changed implementation files and two regression-test files: **no issues found**. Evidence: `build/offline-slice-analysis-20261024.log`. A workspace-wide `flutter analyze --no-pub` invocation stalled without diagnostics and was stopped; no workspace-wide analysis pass is claimed.
- These are app-side automated results. A1–A14 phone acceptance and integrated server replay guarantees remain unproven; no backend duplicate protection is claimed.

## 3. First slice: one offline checklist submission

### User story

As an authenticated field technician, I can open a work order and its existing maintenance checklist while online, reopen that prepared checklist offline, submit one permitted checklist-line change, restart the app without losing the saved change, reconnect, explicitly sync, and see the server-confirmed result without duplicate mutations.

### Preconditions

- A nonproduction backend and disposable technician account are available for mutation tests.
- The work order is assigned and the server has already created the maintenance record.
- The technician opened the necessary work-order detail and maintenance record online before disconnecting.
- The selected checklist line supports an existing offline command and does not require an attachment or an online-only approval.
- Required line definitions/options are cached. If they are not, cache only the data necessary for this selected line type.
- Existing session and offline-access rules apply. Offline access must not bypass login or session restrictions.

### Exact journey

1. Sign in online and open the selected work order and maintenance record.
2. Turn on airplane mode.
3. Open the cached record and change one supported checklist line.
4. Submit the change. Display a local-save confirmation only after persistence succeeds.
5. Close and reopen the app while still offline.
6. Show the pending value and its pending-sync state from persisted data.
7. Reconnect and tap the existing sync/retry control.
8. Replay with the original idempotency key and owning account.
9. Reconcile the response with local state and show the server-confirmed value.
10. Repeat sync and verify that the server has not applied a duplicate mutation.

Use explicit foreground sync for the first acceptance path. Preserve existing automatic behavior, but do not make a new background scheduler a prerequisite.

### Included

- One supported checklist-line mutation on an existing maintenance record.
- Persisted pending state and restoration after a normal app restart/process death.
- Overlay of pending values on cached server data so the UI does not revert after reopening.
- Clear saved-locally, pending-sync, syncing, synced and needs-attention feedback where needed.
- Recoverable network errors and distinct permission/validation/conflict feedback.
- Account ownership and stable retry identity.
- Correctness checks for ownership and replay; separate security/performance tracks as described below.

### Excluded from the first slice

- Creating a new maintenance record entirely offline or inventing temporary record IDs.
- Photos, large attachments, PDF generation, all-screen offline coverage and bulk predownload.
- Offline verification, closure, approval or role administration.
- A new database, repository framework, event bus, state-management system or synchronization engine.
- Guaranteed synchronization while the app is terminated.
- Production record mutations and production security probing.

## 4. Implementation sequence

### Step 1 — Reproduce the existing journey (backend preparation does not block app fixes)

Tasks:

- Trace the chosen screen, controller, repository, cache and replay handler.
- Identify the exact cached record and reference data required to render and edit the chosen line.
- Run existing targeted offline, ownership and idempotency tests.
- Verify disposable-backend ownership, isolation/reset instructions and the group check-out dependency or already-checked-out fixture before phone tests. Implement and unit-test the two known app defects immediately, without waiting for this preparation.
- Attempt the journey with disposable backend data; reproduce the two known client bugs and record any additional failure.
- Distinguish an app defect from a backend contract or environment problem.

Deliverable: reproduction evidence for the known bugs, a short additional-gap list and a ready disposable backend. A formal speed/RAM baseline is not required here. Avoid rewriting behavior that already works.

### Step 2 — Close the smallest end-to-end gap

First fix the two known gaps, then make only additional changes justified by reproduction:

- **First fix: latest unsent edit wins.** Atomically replace the pending payload for the same owner, record and line and persist it before acknowledging the edit. Cover repeated edits and numeric auto-save with regression tests.
- Keep retry identity stable for an unchanged operation. A command already dispatched or of uncertain delivery must keep its original payload/key; a newer edit needs a subsequent operation and must not be removed by the older acknowledgment. Preserve ordering and test this race without broadening the queue architecture.
- **Second fix: restore the pending overlay.** Rebuild the visible line value from persisted pending commands after restart and when cached server data is refreshed. For the same line, the newest outstanding edit wins without hiding failed/conflicting status.

- Cache the selected record and minimal dependencies through existing services.
- Route the selected mutation through the existing outbox contract.
- Await a successful persistence result before claiming the change is saved locally.
- Reconstruct pending UI values after restart from the existing persisted command payload, rather than introducing a second independent draft store.
- Preserve queue ordering for mutations affecting the same record.
- Prevent repeated taps from creating unintended duplicate logical submissions.
- Surface save failures and allow the user to retry without falsely reporting success.

Deliverable: the selected line can be saved offline and reopened with the pending value visible.

### Step 3 — Verify replay and reconciliation

Tasks:

- Keep the idempotency key stable across retries and restarts.
- Classify the selected line-setting endpoint through integrated tests: repeat assignment after a lost response and inspect the final value plus audit/events and other side effects. Do not claim key-based deduplication while the backend ignores keys.
- For the selected endpoint only, establish whether timeout-after-server-commit retry is safe. If side effects make repetition unsafe, this endpoint also requires the backend fix before acceptance.
- Retain unsynced work on transient failures.
- Distinguish transport failure, expired authentication, forbidden access, invalid data and conflict.
- After acknowledgment, reconcile the cached record with server data without hiding a newer pending edit.
- Make conflicts visible and preserve the local value for review; do not introduce generic automatic merging.

Deliverable: the latest server-confirmed line value, with predictable recovery and a precisely stated replay guarantee for this endpoint.

Backend enforcement for unsafe actions is an explicit prerequisite for later slices in Section 10. Slice 1 may proceed on verified repeat-safe assignment semantics; it must not imply that the other endpoints are protected.

### Track 4 — Focused security work alongside delivery

Tasks:

- Verify that queue commands cannot be replayed by another account.
- Check that cached data is not exposed to a different user during restore, login or logout races.
- Verify token handling and ensure logs/errors do not expose tokens or sensitive payloads.
- Verify that requests use the intended HTTPS endpoint and do not bypass certificate validation.
- Confirm the server enforces record access and current permissions during replay.
- Inspect the selected persisted payload for sensitive data and assess its storage protection.
- Refresh dependency advisory checks and triage findings by affected version, reachability and severity.

Fix confirmed high-impact issues immediately. YAGNI is not a reason to retain an established security defect. If a storage protection requirement is demonstrated, make the smallest safe change and verify upgrades and key-loss behavior before shipping.

Deliverable: a scoped findings record, fixes with regression coverage, and clearly identified unresolved risks. This track does not require a new agent or parallel execution. Its full checklist does not block a working slice-1 demonstration; ownership/permission correctness and any confirmed serious issue remain release gates. Do not claim an app-wide security audit from these checks.

### Track 5 — Performance work after slice 1, or earlier on evidence

Tasks:

- Start after the offline slice is delivered unless an observed slowdown or memory problem warrants earlier investigation. This track does not block delivery merely because optimization is unfinished.
- Profile the affected journey on a physical representative phone using Flutter profile mode.
- Measure cold launch, prepared-record opening, local submission latency and peak process memory.
- Identify the dominant cost before modifying code.
- Select one bounded change: remove a duplicate request, narrow a provider subscription, avoid repeated decoding, release a retained object, or reduce unnecessarily loaded data.
- Repeat the same measurements after the change.

Deliverable when an optimization is undertaken: working software plus a before/after result. If no meaningful bottleneck is found, defer optimization; formal profiling is not required to finish slice 1.

### Step 6 — Package and demonstrate

- Run relevant checks and device acceptance scenarios.
- Build a reviewable Android candidate using the existing flavor/signing rules.
- Record source revision, build configuration, device, fixture size and backend version.
- Demonstrate the complete online → offline → restart → reconnect → confirmed result journey.
- Document known limitations and the next selected slice.

Deliverable: a runnable APK, test evidence and concise release notes. Building the candidate does not authorize production deployment.

## 5. First-slice acceptance criteria

| ID | Scenario | Required outcome |
| --- | --- | --- |
| A1 | Open the prepared record in airplane mode | Required cached content is usable; unavailable content has an honest message. |
| A2 | Submit the selected line offline | Local confirmation appears only after successful persistence. |
| A3 | Restart the app offline after confirmation | The saved value and pending status remain visible. |
| A4 | Reconnect and explicitly sync | The server accepts the permitted change and the UI reconciles it. |
| A5 | Retry after a response is lost following server commit | For the selected existing-line assignment, verify repeat-safe final value and side effects; reuse the same key/payload for the retry. Key-based backend deduplication is not claimed. Start/status/complete/photo endpoints wait for the backend protection in Section 10. |
| A6 | Repeated submit/sync taps | No accidental duplicate operation or overlapping queue drain. |
| A7 | Backend becomes unreachable | Saved work remains recoverable; status and retry are understandable. |
| A8 | Storage write fails | No false local-save confirmation; the user can recover/retry. |
| A9 | Authentication expires before replay | Replay pauses or follows existing reauthentication rules without discarding saved work. |
| A10 | Another account signs in | No foreign cached content or command replay; logout behavior follows the existing data-loss warning/policy. |
| A11 | Permission revoked or record changed on server | No unauthorized update; rejected/conflicting work remains visible for attention. |
| A12 | Process stops while syncing | On the dev package, delay the disposable backend response, start sync, confirm dispatch, then run `adb shell am force-stop <verified-dev-application-id>`. Relaunch manually and retry. Test interruption before commit and after commit/before response using controlled backend delays; retain the command/latest value and satisfy A5. Force-stop alone does not establish the server commit boundary. |
| A13 | Edit the same line twice while offline | The second persisted value replaces the older unsent value, survives restart and becomes the server value after sync. |
| A14 | Type `12.5` into an offline numeric field with auto-save | Intermediate saves do not discard the final accepted value; the persisted queue/overlay and server end with `12.5`. Test in-flight edit/save races as well as sequential input. |

Do not require unsynced work to survive an explicit, confirmed account-data deletion if existing policy intentionally deletes it. Make that consequence visible before deletion.

## 6. Performance measurement and targets

### Baseline protocol

Apply the five-run timings, 20-loop soak and process-memory readings below only when making a specific speed/RAM change or investigating an observed regression. They are not slice-1 delivery prerequisites. Correctness/recovery tests remain mandatory regardless of profiling.

- Use a physical low-memory phone representative of field devices; record model, Android version and RAM.
- Use profile mode for diagnosis and a release build for final user-experience confirmation.
- Hold device, fixtures, build settings and network conditions constant for comparisons.
- Measure cold launch separately from warm navigation and cached versus network loading.
- Run at least five comparable timing trials; report the median and range. Treat this as a directional baseline, not a statistically strong tail-latency study.
- Capture Android process PSS as well as Dart heap observations; native images and plugins also consume memory.
- Repeat record open/edit/back navigation 20 times and inspect retained memory after settling/GC rather than judging a single peak.
- Exclude credentials and sensitive field data from captured traces.

| Metric | Initial acceptance rule |
| --- | --- |
| Correctness | No regression in the selected workflow. |
| Offline durability | Every acknowledged local save survives the recovery scenarios above. |
| Replay safety | Verified repeat-safe assignment in slice 1; unsafe endpoints require server deduplication before later-slice acceptance. |
| Loading time | Demonstrated improvement in the selected bottleneck; investigate reproducible regressions elsewhere. |
| RAM | No sustained retained-memory growth during the navigation loop; report peak PSS before/after. |
| UI responsiveness | Inspect frame traces during edit/save and remove demonstrated blocking work. |

The earlier 25% peak-RAM and 30% loading-time reductions are stretch goals, not promises or mandatory work expansion. Set realistic budgets after obtaining the baseline. Do not optimize to an arbitrary number at the expense of reliability.

## 7. Tests and verification

Reuse existing suites before adding new ones:

- `test/features/work_orders/data/work_order_repository_offline_test.dart`
- `test/features/work_orders/data/work_order_repository_idempotency_test.dart`
- `test/core/sync/sync_manager_offline_queue_test.dart`
- `test/core/sync/sync_manager_transient_test.dart`
- `test/core/sync/local_cache_service_owner_test.dart`
- Relevant checklist screen/controller and authentication tests selected after tracing the chosen action.

Add regression tests for demonstrated failures or substantive new behavior. Focus on persistence failure, process recovery, owner isolation, lost responses and reconciliation. Avoid tests that only mirror helper implementations.

Suggested commands, adjusted to the files actually changed:

```powershell
flutter analyze
flutter test test/features/work_orders/data/work_order_repository_offline_test.dart
flutter test test/features/work_orders/data/work_order_repository_idempotency_test.dart
flutter test test/core/sync
python tool/check_pub_advisories.py
```

Before candidate handoff, run the broader suite required by the change and Android lint from the `android` directory:

```powershell
.\gradlew.bat :app:lintDevDebug --console=plain
```

Use the repository's Maven dependency export/advisory procedure and release verification scripts when producing the candidate. Tests involving actual duplicate prevention, permissions and conflicts must run against disposable nonproduction backend fixtures; mocked client tests are insufficient evidence for server behavior.

## 8. Security track beyond the first slice

Maintain a concise issue register with evidence, severity, affected component, fix, regression check and residual limitation. Triage confirmed serious findings as soon as they are discovered rather than waiting for later slices.

After first-slice delivery, expand coverage incrementally to:

1. Sensitive cache, attachment and backup handling.
2. Authentication lifecycle, refresh, revocation and account switching.
3. Authorization and object-level access enforcement on the backend.
4. Authenticated media origins, redirects, upload limits and file validation.
5. Android exported components, permissions and packaged release configuration.
6. Current Dart/Maven advisories and bundled native/SDK dependencies not covered by those scans.

Use OWASP MASVS to organize verification. Dependency scans alone cannot establish the absence of vulnerabilities. Certificate pinning, if required for the deployment threat model, needs a controlled-domain and rotation/recovery plan; do not add it casually as a first-slice checkbox.

## 9. Later slices, selected by observed value

| Order | Smallest useful slice | Add only when |
| --- | --- | --- |
| 2 | Attach one evidence photo offline, restart, then upload and associate it once | Slice 1 is reliable, field users need evidence, and server upload deduplication passes integrated retry tests. |
| 3 | Complete an existing maintenance record after its pending line/photo dependencies sync | Ordering/server validation and backend completion deduplication pass integrated tests. |
| 4 | Open the assigned-work list faster with incremental page loading | Measurements show full-list fetching is a material delay or RAM cost. |
| 5 | Download one assigned work package with its required checklist/options | Manual preparation is a demonstrated usability problem. |
| 6 | Generate one representative PDF with bounded memory | PDF measurements identify a material peak or responsiveness issue. |
| 7 | Extend offline support to the next named field workflow | Its business rules, cache data and replay semantics are explicit. |

For photo work, test full-resolution inputs, cancellation, process death, persistent file paths, sensitive metadata policy, cleanup after acknowledgment and bounded concurrent processing. Add this complexity in its own working increment.

## 10. Triggers for larger changes

### Required backend work before unsafe replay slices

Server-side idempotency is a known missing dependency, not a speculative framework improvement. Before accepting slices 2 and 3, implement and test protection for their upload/completion endpoints. Before extending reliable replay claims to execution start or status changes, protect those endpoints too.

- Scope keys to the authenticated owner and operation/endpoint; bind them to a payload identity.
- Repeated requests with the same key/payload must return the original result without repeating record creation, attachment creation, transitions, notifications or other effects.
- Reject incompatible payload reuse explicitly; serialize concurrent duplicates.
- Persist deduplication outcome atomically with the mutation, or provide an equivalent failure-safe mechanism including external side effects.
- Specify retention long enough for the supported offline/retry window and recheck current access rules appropriately.
- Test concurrent requests, process interruption, and response loss after commit against the disposable backend.

Record the backend implementation owner at kickoff: the implementing assistant owns coordination and integration evidence; any separately assigned backend assistant remains responsible for its named patch. Do not treat the app's idempotency header as completion of this prerequisite.

| Proposed change | Evidence required before starting |
| --- | --- |
| Transactional local database | Existing storage cannot meet measured durability, query, queue size or atomic-update requirements with a small safe fix. |
| Encryption/storage redesign | A documented sensitive-data requirement or demonstrated exposure cannot be addressed adequately by current controls. |
| Background scheduler | Foreground replay fails an explicit operational requirement; Android lifecycle constraints and retry semantics are understood. |
| Generalized synchronization framework | Several delivered workflows demonstrate real repeated complexity that warrants extraction. |
| Broad provider/UI refactor | Profiling identifies rebuild or retention costs that local changes cannot address. |
| R8/resource shrinking | Package/native startup investigation justifies it and the documented plugin failure has regression coverage. |

APK size reduction and runtime RAM reduction are separate outcomes. Measure each separately.

## 11. Delivery controls and recovery

- Keep each change focused and independently reviewable; preserve unrelated workspace changes.
- Avoid queue-format changes in the first slice. If unavoidable, verify backward compatibility with existing pending commands before upgrading.
- Never clear the queue or evidence files as a shortcut to recovery.
- Do not use production records for mutation, replay, conflict or role tests.
- Keep existing release signing identity and environment checks intact.
- If a candidate fails acceptance, retain the previous working candidate and capture diagnostics without discarding user work.
- Before installing an older build, verify it can read the newer persisted format; do not assume downgrade safety.

## 12. Definition of done and handoff

The first slice is complete only when:

- The exact user journey works on a physical Android device against disposable nonproduction records.
- All applicable A1–A14 checks pass with recorded evidence, including A5's limited endpoint-specific guarantee.
- Relevant automated checks pass against the delivered source.
- Scoped security findings are resolved or explicitly recorded; confirmed critical/high findings block rollout.
- If a performance change was made, comparable baseline/candidate measurements are included. Otherwise explicitly record performance work as deferred, without blocking offline-slice delivery.
- A reviewable APK and source/build identification are available.
- Release notes explain what works offline, what preparation is required and which actions still require connectivity.

The handoff contains:

1. APK location and checksum.
2. Source revision and build/environment configuration without secrets.
3. Acceptance results and relevant test logs.
4. Before/after timing and memory table when optimization was included; otherwise a clear deferred status.
5. Security findings and remaining limitations.
6. One recommended next slice supported by the evidence.

No fixed delivery estimate is committed before the initial reproduction. After Step 1, estimate the identified gaps and deliver them in short working increments. Backend/environment blockers must be reported precisely rather than bypassed or counted as passed.

## References

- [Flutter performance best practices](https://docs.flutter.dev/perf/best-practices)
- [Flutter performance profiling](https://docs.flutter.dev/perf/ui-performance)
- [OWASP MASVS](https://mas.owasp.org/MASVS/)
- [Android security risks guidance](https://developer.android.com/privacy-and-security/risks)
- Repository historical validation: `docs/PRODUCTION_READINESS_2026-10-23.md`
