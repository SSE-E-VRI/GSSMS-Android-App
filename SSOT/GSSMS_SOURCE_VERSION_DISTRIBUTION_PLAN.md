# GSSMS — Complaint Channel Tracing, Forced App-Version Gating, Web-Hosted App Distribution

**Document:** `GSSMS_SOURCE_VERSION_DISTRIBUTION_PLAN.md`
**Status:** Proposed — not yet implemented.
**Depends on:** `GSSMS_API_CONTRACT_SSOT.md` (any field/enum introduced here becomes an SSOT addition before clients use it), `MOBILE_APP_IMPLEMENTATION_PLAN.md` (this plan's mobile work slots into Phase 5/7 of that tracker).
**Scope:** three related but independent features. They can ship in any order; Feature 2 (version gating) should land first because Feature 3 (web distribution) is what makes forced-update actually enforceable without a store.

---

## Feature 1 — Trace complaint origin (Web / Android / iOS)

### Why `source` can't be reused

`Complaint.source` (`backend/complaints/models.py`) is a **business-meaning** field — `MANUAL` vs `IOT` — not a client-platform field. Overloading it with `WEB`/`ANDROID`/`IOS` would break `10.2` of the API contract SSOT (every consumer that filters/reports on `source=MANUAL` today) and conflate "a human filed this" with "which app they used." These need to stay two separate axes.

### Design

Add a new field, not a new `source` value:

```python
# backend/complaints/models.py
class Complaint(models.Model):
    CHANNEL_WEB = "WEB"
    CHANNEL_ANDROID = "ANDROID"
    CHANNEL_IOS = "IOS"
    CHANNEL_SYSTEM = "SYSTEM"     # IoT-generated, backfilled, admin console, etc.
    CHANNEL_CHOICES = (
        (CHANNEL_WEB, "Web"),
        (CHANNEL_ANDROID, "Android"),
        (CHANNEL_IOS, "iOS"),
        (CHANNEL_SYSTEM, "System"),
    )
    channel = models.CharField(max_length=10, choices=CHANNEL_CHOICES, default=CHANNEL_SYSTEM)
```

`channel` is **server-derived**, not client-supplied: a client can lie about its platform in a JSON body, but it can't fake the `User-Agent` / a dedicated header as easily if the server also cross-checks. Two acceptable implementations, in order of robustness:

1. **Recommended:** the mobile Dio client and the web Axios client each set a fixed custom header on every request — `X-Client-Platform: ANDROID|IOS|WEB` — and a small DRF middleware/serializer `create()` hook stamps `channel` from that header (falling back to `SYSTEM` if absent/unrecognized), **ignoring any `channel` value in the request body** so it can never be spoofed by copying the mobile app's JSON payload from a browser devtools console.
2. Cheaper but weaker: derive it purely from `User-Agent` string matching. Don't use this alone — Android/iOS Dio user agents are easy to spoof from a scripted client; combine with (1) if you want real audit value.

Apply the same `channel` field + header convention to **Inspection** and **WorkOrder** at the same time (same migration pattern, same header) — the report that will consume this (see below) is far more useful if it's consistent across all three write paths rather than complaint-only. This is additive and low-risk.

### Backend work

1. Migration: add `channel` to `Complaint`, `Inspection`, `WorkOrder` (nullable-safe default `SYSTEM`; backfill existing rows to `SYSTEM` since origin is genuinely unknown for historical data — do not guess).
2. New shared middleware `core/middleware/client_channel.py`: reads `X-Client-Platform`, validates against the allowed set, attaches `request.client_channel` (default `SYSTEM` for anything missing/unrecognized — never trust an unvalidated free-text value).
3. In each `create()` (serializer or viewset `perform_create`), set `channel = request.client_channel` — never accept `channel` from the request body (drop it in `to_internal_value`/explicitly `read_only_fields` if `"__all__"` serializers are used, per the same pattern that already burned you with `source=MOBILE`).
4. Expose `channel` as a **read-only** response field (same treatment as `source`/`status`) and add it to the SSOT (`§10.1`, `§11.1`, plus a new WorkOrder fields note) once implemented — SSOT first, then code, per the existing change-control rule in `GSSMS_API_CONTRACT_SSOT.md` §45.
5. Add `channel` as a list filter (`?channel=ANDROID`) next to the existing `status`/`depot`/`division`/`zone`/date filters, so Web can build a "complaints by channel" report.
6. Add the required contract tests (SSOT §36 pattern): channel stamped correctly per header, channel in body is ignored/can't override, missing header defaults to `SYSTEM`, filter works.

### Web work

- `axios` instance: add `X-Client-Platform: WEB` to every request (one line in the shared Axios config, e.g. `frontend/src/...api.js` default headers).
- Add a "Channel" column/filter to the complaints (and inspections/work-orders) list view, and a small breakdown chart if there's an existing dashboard chart component (`chart.js` is already a dependency) — e.g. a donut of Web vs Android vs iOS vs System for the selected date range.

### Mobile work

- `lib/core/network/dio_client.dart`: add `'X-Client-Platform': Platform.isIOS ? 'IOS' : 'ANDROID'` to the base `Dio` options headers (one place, applies to every request automatically — don't scatter it per-repository).
- No repository/payload changes needed — `channel` is never sent in the body, only the header, consistent with Rule 6 (server owns defaults) in the API contract.

### Effort / risk

Low-medium. Three migrations, one middleware, one header on each client, one filter. No lifecycle/state-machine impact. Safe to ship independently of Features 2/3.

---

## Feature 2 — Minimum-supported-version gating (forced update)

### Why this needs a server-owned source of truth

The Android app already has no such mechanism (`lib/core/config/app_config.dart` has no version-check code; `pubspec.yaml` is currently `0.1.0+2`). Hard-coding a minimum version *in* the app itself is useless — the whole point is to invalidate app builds that are already installed, so the check must be server-driven and evaluated on every relevant launch/request, not baked into the binary you're trying to deprecate.

### Design

**Backend — new `core` app content** (the `core` Django app already exists at `backend/core/` but is currently empty scaffolding — this is exactly what it's for):

```python
# backend/core/models.py
class AppVersionPolicy(models.Model):
    PLATFORM_ANDROID = "ANDROID"
    PLATFORM_IOS = "IOS"
    PLATFORM_CHOICES = ((PLATFORM_ANDROID, "Android"), (PLATFORM_IOS, "iOS"))

    platform = models.CharField(max_length=10, choices=PLATFORM_CHOICES, unique=True)
    minimum_supported_version = models.CharField(max_length=20)   # e.g. "1.4.0"
    latest_version = models.CharField(max_length=20)              # e.g. "1.6.2"
    latest_build_number = models.PositiveIntegerField()
    update_url = models.URLField()          # the web download page from Feature 3
    release_notes = models.TextField(blank=True)
    force_update_message = models.TextField(blank=True)
    updated_at = models.DateTimeField(auto_now=True)
```

Endpoint, unauthenticated (must be callable *before* login, since a blocked user must see the message even if their stored token is stale/rejected):

```http
GET /api/v1/app-version/?platform=ANDROID&current_version=1.3.0&current_build=17
```

Response:

```json
{
  "platform": "ANDROID",
  "minimum_supported_version": "1.4.0",
  "latest_version": "1.6.2",
  "update_required": true,
  "update_url": "https://gssms.example.com/download/android",
  "release_notes": "...",
  "message": "A required update is available. Please update to continue."
}
```

`update_required` is computed server-side via semver comparison of `current_version` against `minimum_supported_version` — don't push that comparison logic into Dart, so a bug in the client's own version-parsing can never be the thing that *lets an outdated client back in*.

Admin-manageable via Django admin (register `AppVersionPolicy` — you already have `SUPER_ADMIN`-gated admin patterns elsewhere) so ops can bump `minimum_supported_version` without a deploy when a critical mobile bug needs to be killed fleet-wide.

### Enforcement points (defense in depth — do both)

1. **App-launch gate (primary UX):** mobile app calls `/api/v1/app-version/` on splash/startup, *before* attempting login/token-restore. If `update_required`, show a **non-dismissible** full-screen dialog: version, what changed, a button that opens `update_url` (Feature 3's download page) in the system browser. No skip/close affordance. If the version-check call itself fails (offline, DNS), **fail open** — let the user continue into the app's normal offline-read flow — a version check must never become a new way to lock users out during a network blip.
2. **Per-request enforcement (defense against a user who already has the app open when the minimum bumps):** mobile sends `X-App-Version` / `X-App-Platform` headers (same convention as Feature 1's `X-Client-Platform` — can literally be the same header set) on every authenticated request. A DRF middleware checks the version against the live `AppVersionPolicy` and returns **`426 Upgrade Required`** with the same payload shape as the dedicated endpoint if the caller is below minimum. Mobile's Dio error interceptor recognizes `426` specifically (distinct from the existing 400/401/403/404/409/5xx bucket in `work_order_repository.dart`'s error mapping) and routes straight to the same non-dismissible update screen instead of a generic error toast.

This two-layer approach means: a fresh launch is blocked before it does anything, and a session that was already open when you bump the minimum gets caught on its next mutating call rather than being allowed to keep working indefinitely.

### iOS note

Apple's own App Store versioning doesn't apply here since you're not distributing through the Store (see Feature 3) — this mechanism is your *only* update-enforcement lever on iOS, so it matters equally on both platforms. `current_build` matters more than `current_version` for iOS ad-hoc/enterprise builds where you might ship a hotfix under the same marketing version with a bumped build number — compare build number as the tiebreaker when versions are equal.

### Mobile work

- `lib/core/config/app_config.dart`: read `package_info_plus` (new dependency) for the running version/build instead of hand-tracking it.
- New `lib/core/version/version_gate_service.dart` + a splash-screen check before the existing auth-restore flow.
- New `lib/core/version/force_update_screen.dart` — full-screen, non-dismissible, "Update Required" with an "Update Now" button (`url_launcher`, already likely available or trivial to add) opening `update_url`.
- `dio_client.dart`: add `X-App-Version`/`X-App-Build`/`X-App-Platform` headers; add a `426` branch to the response-error interceptor that surfaces the same force-update screen instead of a normal error.

### Effort / risk

Medium. One new backend app surface (model + endpoint + middleware + admin registration), one new mobile splash-gate flow, one new interceptor branch. Genuinely low risk to existing functionality since the "fail open on network error" rule keeps it from ever becoming a new outage vector.

---

## Feature 3 — Web-hosted Android/iOS distribution (no app stores)

This is the feature that makes Feature 2 actually actionable, and it's the one with real external constraints — read the iOS section before committing to a plan with the team, since it involves either an ongoing Apple fee or a real device-management ceiling.

### Android — straightforward

Android has no gatekeeper for sideloaded installs beyond the device's own "install unknown apps" permission (per-source toggle since Android 8; the user grants it to your web domain/browser the first time).

1. **Build:** signed **release AAB → APK** (not AAB — Play-only bundles can't be sideloaded; you need a universal/signed APK). Add a `flutter build apk --release --flavor prod` step to CI (`.github/workflows/mobile_ci.yml` already exists — extend it) that uploads the signed APK as a build artifact.
2. **Sign consistently:** use one stable release keystore forever — if the signing key ever changes, every existing install must fully uninstall/reinstall (Android refuses to install a differently-signed update over an existing app), which defeats the whole point of the update flow in Feature 2. Store the keystore + passwords in your CI secrets, never in the repo.
3. **Host:** the web app (`frontend/`, served by whatever serves it today) gets a `/download/android` page: version number, release notes (pull from `AppVersionPolicy.release_notes`), a big "Download APK" button, and plain-language install instructions ("you'll need to allow installs from this site — Android will prompt you"). Serve the `.apk` from the Django backend behind `protected_media`-style handling (already exists for other file types) or a plain static/media URL — either is fine since it's not a secret, just gate the *page* behind login if you want only authenticated staff to find it.
4. **Auto-checksum:** publish the APK's SHA-256 next to the download link so a technician (or IT) can verify integrity, since there's no store-level signing verification here.

### iOS — the real constraint: pick one deliberately, don't default into it

Apple does not allow arbitrary `.ipa` sideloading the way Android does. Three real options, in increasing cost/decreasing friction:

| Option | Cost | Device cap | UX | Notes |
|---|---|---|---|---|
| **Ad-hoc distribution** | Free (with a normal Apple Developer account, $99/yr) | **100 devices per membership year**, each device UDID must be pre-registered in the provisioning profile before it can install | Install via a web page + `itms-services://` manifest link, or a QR code | Every new phone needs its UDID collected and a rebuild/re-provision; painful past a handful of devices; fine for a pilot depot |
| **Apple Business/Enterprise Program** | $299/yr | **Unlimited**, internal-use only, org must qualify (D-U-N-S number, is a real organization) | Same `itms-services://` web-install flow, no per-device registration | This is the standard answer for "unlimited internal distribution without the App Store" — recommended if GSSMS is rolling out beyond a small pilot |
| **TestFlight (internal or external testing)** | Free (same $99/yr account) | Internal: 100 testers on your team. External: up to 10,000, but **requires an App Store Review pass** even for external TestFlight builds | Apple's own TestFlight app | Technically still "through Apple," and external tester review reintroduces exactly the store-review dependency you said you want to avoid — only worth it if "not published to the public App Store" (vs. "no Apple review at all") is the actual constraint |

**Recommendation:** if the eventual rollout is more than ~15-20 field devices, don't start with ad-hoc — the UDID-collection treadmill doesn't scale and every device-list change requires re-signing the build. Get the **Apple Developer Enterprise Program** enrolled early (it has real lead time — weeks, and requires a D-U-N-S-verifiable organization) and build the distribution page around `itms-services://` from day one. If the pilot really is small and permanent for a while, ad-hoc is fine to start and you migrate the signing/provisioning later — but say so explicitly as a decision, don't let it default silently, since the two need different provisioning profiles and can't be swapped without re-signing.

This decision already exists as an **open item** in `MOBILE_APP_SSOT.md`/`MOBILE_APP_IMPLEMENTATION_PLAN.md` (Phase 7: "Apple Developer enrollment ... start early, multi-week lead time"; "distribution channel" is listed among decisions #4–8/#10–14 still unresolved there) — resolve it there, this plan just spells out the concrete mechanics once you do.

### `/download/ios` page mechanics (once enrollment is settled)

1. Build a signed `.ipa` (CI, same idea as the Android APK job).
2. Host a `manifest.plist` describing the app (bundle id, version, icon URL, `.ipa` URL) over **HTTPS** (required — `itms-services` refuses `http://`).
3. The download page's "Install" button is an `<a href="itms-services://?action=download-manifest&url=https://.../manifest.plist">` link — tapping it from Safari on the device triggers the native "Install GSSMS?" prompt.
4. First launch after install requires the user to go to **Settings → General → VPN & Device Management** and manually trust the distribution certificate — document this step on the same page, it trips up every first-time installer.

### Shared web-app work

- One `/download` landing page (linked from both `AppVersionPolicy.update_url` values) that detects the visiting platform (`navigator.userAgent`) and shows the right one of the two flows by default, with a manual toggle for someone downloading from a desktop to send to a device.
- Gate the page behind the existing web-app login if you don't want the APK/manifest URLs guessable by the public — even though the files aren't secret, unlisted-but-public download links are an easy way for a build to circulate somewhere you didn't intend.

### Effort / risk

- Android: **low**. CI job + one static page.
- iOS: **medium-to-high**, dominated by the Apple enrollment decision and lead time, not by engineering effort. The actual `itms-services` plumbing is small once a provisioning strategy is chosen.

---

## Suggested delivery order

1. **Feature 2 backend** (`AppVersionPolicy` model/endpoint/middleware) — nothing else depends on client behavior, ships safely alone, and gives ops an immediate kill-switch even before the mobile UI for it exists.
2. **Feature 2 mobile** (splash gate + 426 interceptor) — now the enforcement is real.
3. **Feature 3 Android** — unblocks actually getting updated builds to the fleet without a store.
4. **Feature 1** (channel tracing) — independent, can be done in parallel with any of the above; lowest external risk.
5. **Feature 3 iOS** — start the Apple enrollment decision **now**, in parallel with 1–4, because its lead time is the long pole, not its engineering effort.

---

## Open decisions requiring a product/ops call before implementation starts

- [ ] Ad-hoc vs. Enterprise vs. TestFlight for iOS (table above) — drives provisioning strategy and whether UDID collection tooling is needed.
- [ ] Who can see `/download`: gated behind existing web login, or a separate lighter-weight internal-only auth?
- [ ] Does `channel` belong on WorkOrder/Inspection too in this pass, or complaint-only for now? (Plan above assumes "all three, same migration wave" — cheap to do together, expensive to retrofit later.)
- [ ] Minimum-version *policy*: who owns bumping `AppVersionPolicy` in production, and what's the internal process/SLA for warning field staff before a forced update goes live?
