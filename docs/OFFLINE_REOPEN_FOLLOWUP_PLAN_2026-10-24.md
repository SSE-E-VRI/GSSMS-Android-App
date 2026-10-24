# Offline reopen follow-up and hotfix separation

## Release boundary

0.3.7+12 is the data-loss hotfix built from `29edc81657c6a261da74b3d9763bc4281c73e2fc`.
Its signed APK was exported before F1/F2/F3 implementation. Those follow-ups must
not delay or silently enter that artifact. The source also inherits the prior
geolocator manifest/lint correction; no new backend contract is introduced by
the hotfix. No production installation or external distribution is claimed.

## F1 and F3

F1/F3 implementation is isolated in `3e89183`:

- A failed network lookup of allowed-actions can expose Open Checklist only for
  the signed-in owner's downloaded, assigned In Progress record.
- A server permission denial does not enable that fallback.
- Start, transitions and approvals gain no offline fallback.
- Queued line status is derived from the existing outbox and is not added to
  its saved format. Pending/failed values show local-save wording and suppress
  the checklist's earlier Last synced label.

## F2 policy approved by the user

**Eight hours (one shift)** after the last successful online sign-in or refresh.
Offline use must not renew that window. An earlier server profile validity
deadline shortens it.

Implementation requirements:

1. Persist the last server-verified identity and timestamps in platform secure
   storage, alongside credential protection, not in operational preferences.
2. Restore only a Maintenance Staff profile matching the signed-in/cache owner.
   Reject expired windows, malformed data, owner mismatches and backward time
   relative to verified/last-used timestamps.
3. Use a dedicated saved-checklist landing page. Allow only previously
   downloaded, owned In Progress checklists and local queued line saves.
4. Do not use the expired network access token as an online credential. Reject
   authenticated operational API requests while restricted mode is active.
5. Disable attachments, checkout changes, completion, approvals and other
   modules in restricted mode. Revalidate before queue replay or full access.
6. On reconnect/resume, refresh the session. A transport failure can retain
   eligible local access; an authentication refusal ends it and preserves the
   existing owned outbox for reauthentication.
7. Expiry while the app is open also ends restricted access. Sign-out removes
   the protected snapshot and continues to warn before discarding queued work.

The window relies on device time with a backward-clock guard, not an external
trusted clock. It does not provide instantaneous offline revocation. The server
remains authoritative when work is replayed.

## Verification and named open items

Rerun A1 and A3 end to end on the connected phone, and a quick A10 account
switch. Include a refused-refresh check and assert the queued value remains
owned/persisted when the session ends. Record results in a new report rather
than replacing the original failed acceptance evidence.

Keep these named items open unless separately proven:

- **A11 simultaneous edits/version conflicts:** the copied backend still lacks
  its deferred version-token contract. Assignment-denial checks do not prove
  conflict resolution.
- **A9 refused refresh:** verify the new restricted-session refusal path both
  in unit tests and on the disposable backend; access-token auto-refresh alone
  is insufficient.
- **Other line types and commands:** repeat safety for numeric assignment does
  not prove safety for deficiency/measurement side effects, photos, start,
  transitions or completion. Server duplicate protection remains a dependency.
- **Group check-out mismatch:** use a fully checked-out disposable fixture for
  this slice; do not certify the separate check-out fix from that workaround.

Dev acceptance must not install or mutate production. Keep the test backend,
baseline and completed-run database snapshots outside Flutter's `build` folder.

## Implemented and rechecked

F2 is implemented in `ff3cb91`. The focused A1/A3/A10 phone checks and the tested
401 refused-refresh path passed; see [the reacceptance report](OFFLINE_REOPEN_REACCEPTANCE_2026-10-24.md).
The signed 0.3.7 artifact remains separate. Its exact binary was independently
observed installed on the connected phone; no production install command was
issued during dev acceptance.

**New named open item F4:** after home-screen replay clears an acknowledged line
command, the downloaded read model can still show its older value until an online
record refresh. Make owner-safe acknowledged-cache reconciliation the next small
slice. Test a cold offline read immediately after home-only sync and ownership/
interrupted-persistence cases, without changing the saved queue format.
