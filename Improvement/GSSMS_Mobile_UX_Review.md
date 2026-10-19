# GSSMS Mobile — UI/UX Review

**Reviewed build:** `gssms_mobile 0.1.0+2` (Flutter, Material 3)
**Evidence base:** 15 device screenshots (1080×2412, OPPO CPH2381, Android 14) + full `lib/` source (97 Dart files, ~21,800 LOC)
**Reviewer:** Claude
**Date:** 09 September 2026

---

## 1. Verdict in one paragraph

The information architecture is sound and the domain modelling is unusually disciplined for a v0.1 — permission-gated modules, honest placeholders instead of fake demo data, error states that keep the last-good list visible, offline sync badges. What lets it down is **screen real estate and visual hierarchy**. On a checklist with 56 items, roughly half the viewport is permanently occupied by chrome, and the single most important button in the entire app (**Sign & Submit**) is parked off-screen inside a horizontally-scrolling toolbar of six equally-weighted, six-differently-coloured buttons. Fix the two P0 items below and the app jumps from "a competent internal tool" to "a tool a technician can use one-handed on a platform in the sun".

**Overall scores** (1–5, 5 = ship-quality):

| Dimension | Score | Note |
|---|---|---|
| Information architecture | 4 | Module grid maps cleanly to RBAC; no top-level nav is the gap |
| Visual hierarchy | 2 | Every action looks equally important; six-colour toolbars |
| Screen-space efficiency | 2 | Fixed chrome dominates the task screens |
| Consistency / design system | 2 | Theme exists but ~60 hardcoded colours bypass it |
| Feedback & error states | 4 | Best part of the app — stale-data banners, retry, honest fallbacks |
| Accessibility | 1 | 1 `Semantics` widget app-wide; 10–12 px labels; no scale tolerance |
| Field-readiness (gloves, sun, gaps) | 2 | Touch targets, contrast, and the fake scanner |

---

## 2. P0 — Fix before the next field rollout

### P0-1. The primary action is off-screen

`lib/features/work_orders/presentation/screens/checklist_screen.dart:400–487`

The `bottomNavigationBar` is a horizontal `SingleChildScrollView` containing six buttons in this order:

| # | Label | Colour | Visible on a 1080 px screen? |
|---|---|---|---|
| 1 | Enter Replaced Asset | `0xFFD32F2F` red outline | Yes |
| 2 | Enter Replaced Component | `0xFFE65100` orange outline | Half |
| 3 | Save Progress | `0xFFFFC107` amber | **No** |
| 4 | Preview | `0xFF00BCD4` cyan | **No** |
| 5 | Sign & Submit | green | **No** |
| 6 | Back | `0xFF546E7A` blue-grey | **No** |

Screenshots 14 and 15 confirm it: the technician sees two destructive-looking red/orange buttons and nothing else. Nothing indicates the bar scrolls. The completion action for a 56-line inspection is four swipes away, and the two rarest actions have the loudest colours (red = replacement entry, which is an exception path). `Back` also duplicates the system back gesture and the app-bar arrow, so it costs space for nothing.

**Fix**

- One primary button, full-width, always visible: **Sign & Submit** (disabled with a reason when required lines are incomplete — "12 of 56 required items remaining").
- **Save Progress** should not exist at all. Your own comment at line 491 admits it: every line already saves or queues on entry, and the button only triggers a reload. Replace it with a passive per-line sync indicator (✓ saved / ↻ queued) and a "Last synced 2 min ago" line.
- `Enter Replaced Asset`, `Enter Replaced Component`, `Preview` → an overflow menu (⋮) in the app bar, or a single "More actions" sheet.
- Delete `Back`.

```dart
bottomNavigationBar: SafeArea(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
    child: FilledButton.icon(
      onPressed: state.canSubmit ? _showCompletionDialog : null,
      icon: const Icon(Icons.check_circle_outline),
      label: Text(state.canSubmit
          ? 'Sign & Submit'
          : '${state.remainingRequired} required items left'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    ),
  ),
),
```

Apply the same rule to `work_order_detail_screen.dart:490–540` (screenshot 13): **Open Checklist** and **Tech Completed** are both heavyweight filled buttons in blue and green. One of them is the next step; the other is a state transition. Make Open Checklist the filled primary and Tech Completed a `TextButton`/`OutlinedButton`, or better, move Tech Completed into the checklist's completion flow where it belongs.

---

### P0-2. Fixed chrome eats the checklist screen

`checklist_screen.dart:132–164`

The body is a `Column` with four fixed children before the `Expanded` list:

```
Android status bar          ~ 90 px
AppBar                      ~ 112 px
_buildRailwayHeader         ~ 210 px   ← always visible, never changes
_buildProgressCard          ~ 100 px
_buildAssetHeader           ~  70 px
_buildCategoryFilter        ~  90 px
bottom action bar           ~ 100 px
Android nav bar             ~  90 px
------------------------------------
fixed:                      ~ 862 px of 2412  (36%)
usable list area:           ~1550 px  → roughly 1.5 checklist cards
```

56 items at 1.5 per screen is ~37 scroll actions to walk one inspection, with the org identity block ("SOUTHERN RAILWAY / Tiruchchirappalli Division · Vriddhachalam Depot") re-asserted the entire time. A technician who opened that record knows which railway they work for.

**Fix**

- Convert the header into a `SliverAppBar` with `pinned: true, expandedHeight: 180`. Expanded shows the full railway/location/schedule block; collapsed keeps only "Thalanallur · Station Monthly · 7%" in the title. It scrolls away on the first swipe and comes back on scroll-up.
- Keep the progress bar as a 4 px `LinearProgressIndicator` at the bottom edge of the pinned app bar, with the "4 of 56" as `subtitle` text — not a 100 px card.
- Keep only the subsystem chips pinned (`SliverPersistentHeader`) — that is the one control used mid-task.
- Move "Checked out by supervisor" out of the sticky asset header; it's a once-per-record decision, so it belongs in the completion dialog, not in permanent view.

Expected result: ~4 checklist cards visible instead of 1.5.

**Related:** the same `Column` + fixed filter-row pattern costs ~90 px on Dashboard, Maintenance, Complaints, Inspections, Assets, and Reports (see screenshots 2–10). On Dashboard the "Depot: All" dropdown occupies prime screen space while showing the default value. Make it a compact app-bar filter chip that opens a bottom sheet, and label it with the active value: `Depot: All ▾` → tap → sheet. When the scope is at default, show a plain filter icon with no chip at all.

---

## 3. P1 — Fix in the next sprint

### P1-1. The QR scanner does not scan

`lib/features/assets/presentation/widgets/qr_scanner_dialog.dart`

The dialog renders a black rectangle with a green targeting frame and the caption "Ready to Scan Barcode / QR" — and then requires the user to type the asset code. There is no scanner package in `pubspec.yaml`. A technician standing in front of an asset label will hold the phone up and wait.

This is the one place where the app is not honest with the user, which is a shame given the care taken elsewhere (your placeholder comment at `checklist_screen.dart:171` is exactly the right instinct).

**Fix:** either add `mobile_scanner: ^5.x` and ship the real thing (the asset code convention `VRI-SS01-HTSTR-2POLE-001` is ideal for Code128), or, until then, change the dialog to "Enter Asset Code", drop the fake viewport, and use a `qr_code_scanner_outlined` icon only after the real scanner lands. Also swap the keyboard to `TextInputType.visibleText` with `textCapitalization: TextCapitalization.characters` and `autofocus: true` so typing a code is at least fast.

### P1-2. No top-level navigation

Every module is a `MaterialPageRoute.push` from the home grid (`home_screen.dart:150–290`). Switching from a work order to a complaint is: back, back, home, tap Complaints. Field staff move between Work Orders, Complaints, and Assets constantly.

**Fix:** a `NavigationBar` with 3–4 role-filtered destinations (Home · Work · Assets · Alerts) hosting an `IndexedStack`, so tab state survives switching. Keep the module grid as the Home tab for the long tail of modules.

### P1-3. App-bar titles truncate on every screen

Screenshots 5, 6, 7, 8, 9, 10, 12, 14: "Maintenan…", "Complaints…", "Field Inspe…", "Asset …", "Reports & …", "Checklist #…".

Cause: the title competes with a `SyncStatusBadge` ("Online" pill) plus a refresh `IconButton` plus sometimes a scan button. Three of those are low-value:

- The **Online pill** is chrome that is correct 95% of the time. Invert it: show nothing when online, show a full-width amber strip **"Offline — 3 changes queued"** when not. That is the state that needs the space.
- The **refresh icon** duplicates pull-to-refresh, which is already implemented on all seven list screens. Remove it.
- Shorten titles: "Field Inspections" → "Inspections"; "Reports & Audit" → "Reports"; "Checklist #123" → "Checklist" with the ID in a subtitle.

### P1-4. Horizontal chip rows cut off mid-word

`complaint_list_screen.dart:198–230`, `asset_list_screen.dart:238–278`, `checklist_screen.dart` category filter. Screenshots 7 ("Resolve…"), 8 ("Com…"), 9 ("CLS…"), 14 ("EI…").

A chip sliced by the screen edge reads as a rendering bug, not as an affordance. Worse, the user can't see how many filters exist.

**Fix:** use `Wrap` with `spacing: 8, runSpacing: 8` and let it take two lines (chips are short), or keep the scroller but add a right-edge gradient fade mask and 24 px trailing padding so a partial chip is clearly a partial chip. Add counts to the labels — `Open (4)`, `In Progress (8)` — which turns the filter row into a summary and removes the need to tap through to find out.

### P1-5. Hardcoded colours bypass the theme

`AppTheme` (`lib/core/theme/app_theme.dart`) defines a good token set, then ~60 `Color(0xFF…)` literals outside it override it:

| File | Count |
|---|---|
| `inspection_create_screen.dart` | 24 |
| `checklist_screen.dart` | 19 |
| `complaint_create_screen.dart` | 8 |
| `work_order_create_screen.dart` | 5 |
| others | 6 |

Several are near-duplicates of existing tokens (`0xFFD32F2F` vs `errorRed 0xFFEF4444`; `0xFF0D3B66` vs `primaryDark 0xFF0A2540`). The home grid additionally assigns `Colors.purple`, `Colors.teal`, `Colors.indigo`, `Colors.deepOrange` straight from the Material palette — and gives **Inspections and Assets the same teal**, so the colour carries no information.

**Fix:** add semantic tokens and ban raw literals with a lint.

```dart
// app_theme.dart
static const Color moduleDashboard   = primaryBlue;
static const Color moduleMaintenance = Color(0xFF6D4C9F);
static const Color moduleComplaints  = accentOrange;
static const Color moduleInspections = Color(0xFF0F766E);
static const Color moduleAssets      = Color(0xFF1D4ED8);
static const Color moduleReports     = Color(0xFFB45309);
static const Color moduleEnergy      = Color(0xFF3730A3);
```

```yaml
# analysis_options.yaml
linter:
  rules:
    - avoid_hardcoded_color   # or a custom_lint rule banning Color(0xFF in lib/features/
```

### P1-6. No type scale

Inline `TextStyle(fontSize: 10/11/12/13/14/15/16)` appears throughout; `textTheme` is never configured. The result is visible in screenshot 14, where the checkbox label "Checked out by supervisor" is 10 px and the button labels are 12 px — on a device held at arm's length, in daylight, possibly with gloves.

**Fix:** define the scale once and use `Theme.of(context).textTheme.*` everywhere. Floor for anything interactive: 14 sp.

```dart
textTheme: const TextTheme(
  titleLarge:  TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.25),
  titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
  bodyLarge:   TextStyle(fontSize: 16, height: 1.45),
  bodyMedium:  TextStyle(fontSize: 14, height: 1.45),
  labelLarge:  TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  labelSmall:  TextStyle(fontSize: 12, fontWeight: FontWeight.w500),  // metadata only
),
```

### P1-7. Home tiles carry two icons for one idea

`home_screen.dart:320–360`: each tile renders a Material outline icon in a tinted circle **and** an emoji badge overlapping it (📊 on the dashboard icon, 🚨 on the complaint icon). Screenshot 1 shows the collision — the emoji sits half outside the circle and clips against the card's top-left. Two symbols for the same concept halves the recognition speed of each.

**Fix:** drop the emoji. If you want warmth, keep the emoji *instead* of the icon at 28 px, not on top of it. Emoji also render differently across Android skins and don't tint, which is why they look out of place against your otherwise flat icon set.

### P1-8. Layout will break at larger font sizes

- `GridView.count(childAspectRatio: 1.15)` (`home_screen.dart:307`) — fixed aspect ratio + 2-line subtitle overflows at 1.3× text scale.
- No `themeMode` / `darkTheme` anywhere in `lib/app/app.dart`. Railway staff on early-morning shifts (your own screenshots are 06:57) will want dark.
- `SizedBox(height: 20, width: 20)` around a `Checkbox` (`checklist_screen.dart:288`) gives a 20 dp touch target; Android's minimum is 48 dp.

**Fix:** test at `MediaQuery(textScaler: TextScaler.linear(1.3))` in a widget test for each screen; replace the fixed `childAspectRatio` with `mainAxisExtent: 150`; wrap the checkbox in an `InkWell` sized to 48 dp (or use `CheckboxListTile`); add a dark theme derived from the same tokens.

### P1-9. Accessibility is effectively absent

One `Semantics` widget in 97 files. Consequences for TalkBack users and for anyone using a screen reader in a noisy depot:

- Icon-only buttons (scan, refresh, chevrons) announce as "button".
- The donut chart announces nothing — the numbers exist only as chart segments plus a legend.
- Status is encoded by colour alone in several places (green "OK" column in screenshot 11; red/amber/green donut). ~8% of male technicians have some form of colour vision deficiency.

**Fix:**
- `Semantics(label: 'Job work status: 12 verified, 8 in progress, 4 open')` wrapping `StatusDonutChart`.
- `tooltip:` on every `IconButton` (you already do this on Home — extend it).
- Pair every colour signal with a glyph: ✓ OK, ! Deficient, ✕ Failed. The severity badges ("Critical", "Medium") already have text; the checklist status column doesn't.

---

## 4. P2 — Polish

| # | Issue | Location | Fix |
|---|---|---|---|
| P2-1 | Empty states are one bare sentence with no icon, no cause, no way out | `complaint_list_screen.dart:307`, `asset_list_screen.dart:313` | Shared `EmptyStateView(icon, title, body, action)` with a "Clear filters" button — the current copy says "matching criteria" without showing which criteria |
| P2-2 | Search fires a controller update on every keystroke, no debounce, no "searching" state | `asset_list_screen.dart:232` | 300 ms debounce (you already have the pattern at `checklist_screen.dart:1313`); show result count "24 assets" under the field |
| P2-3 | Three date formats in one app: `05 Sep 2026, 12:10 PM`, `03/09/2026`, `09/08/2026` | complaints, reports, checklist header | One `AppDate` helper: `dd MMM yyyy` for dates, relative ("2 days ago") for anything under a week |
| P2-4 | "N/A" and "Not specified" both used for missing values | `work_order_detail_screen.dart`, `checklist_screen.dart:170` | Pick "Not specified"; render it in `textMuted` italic so it's visibly not data |
| P2-5 | Dashboard pending-actions list has identical titles ("Pending action" × 6), differentiated only by station | screenshot 4 | Title should be the work item; station is the subtitle. As shown, the list can't be scanned |
| P2-6 | "+2 more in the work queues" is plain text, not a link | dashboard attention card | Make it a `TextButton` that deep-links to the filtered queue |
| P2-7 | Extended FAB overlaps card content and never hides | screenshots 7, 8 | Shrink to icon-only on scroll-down (`AnimatedSlide` on a `ScrollController`), or use `FloatingActionButton` regular size — "Log Complaint" is discoverable enough as an icon + tooltip |
| P2-8 | Reports list uses `#1 #2 #3` rank circles for what is a filtered list, not a ranking | screenshot 10 | Drop the numbers; use the date or depot as the leading element |
| P2-9 | `checklist_screen.dart` is 1,665 lines with 5 widget classes inline | — | Extract `_ChecklistLineCard`, the header, and the bottom bar into `widgets/`; this is what makes the layout hard to change |
| P2-10 | Save failures surface as a transient red `SnackBar` | `checklist_screen.dart:63` | For offline field work, a dismissed snackbar means a silently lost observation. Mark the line itself with a persistent ⚠ + inline "Retry" |
| P2-11 | Compliance card shows "50.0%" with a warning triangle but no target | screenshots 5, 12 | Add the target ("target 90%") — a bare percentage with a warning icon doesn't tell a supervisor how bad 50% is |
| P2-12 | Deficiency banner is black-on-amber full-bleed inside the card | screenshot 14 | Works, but the amber block competes with the required-field red. Use amber text + amber left border instead of a filled block |

---

## 5. What is already good (keep it)

Worth naming explicitly so it doesn't get refactored away:

1. **Stale-data-with-banner error handling** (`complaint_list_screen.dart:238–270`). When a refresh fails you keep the previous list visible and put a slim red "cloud off" strip on top with Retry. That is better than most commercial apps.
2. **Honest placeholders.** The comment at `checklist_screen.dart:167–171` — refusing to invent plausible-looking depot names because a technician might act on them — is the correct safety instinct, and rare.
3. **Permission-driven module grid.** Modules appear from `session.hasPermission`, with an explicit empty state. No dead menu items.
4. **Per-line debounced autosave** on the checklist (800 ms). The right model for field data entry.
5. **The `OrgScopeFilterBar` gating logic** — collapsing to nothing for a depot-scoped user rather than showing a one-option dropdown — is thoughtful. It's the placement that needs work, not the logic.
6. **Pull-to-refresh on all seven list screens**, consistently.

---

## 6. Suggested sequence

**Sprint 1 — field usability (the two P0s)**
- Rebuild the checklist bottom bar around one primary action; move the rest to an overflow menu
- Convert the checklist header to a collapsing `SliverAppBar`
- Move the org-scope filter into an app-bar chip + bottom sheet across all six screens
- Remove the refresh icons; invert the online/offline badge into an offline-only banner

**Sprint 2 — design system**
- Configure `textTheme`; replace inline `TextStyle` app-wide
- Add semantic module colour tokens; lint against raw `Color(0xFF…)` in `lib/features/`
- Add `darkTheme` + `themeMode`
- Extract `EmptyStateView`, `StatusBadge`, `SectionCard` into `core/widgets/`

**Sprint 3 — navigation & scanning**
- `NavigationBar` shell with `IndexedStack`
- Real `mobile_scanner` integration (or rename the dialog in the meantime — do this one in Sprint 1, it's a one-line change)
- Chip rows → `Wrap` with counts

**Sprint 4 — accessibility**
- Semantics labels for charts and icon buttons
- 48 dp minimum touch targets audit
- Golden tests at `textScaler` 1.0 / 1.3 / 1.5 for the seven main screens
- Glyph-plus-colour for every status signal

---

## 7. Two quick tests to run before and after

**The gloved-technician test.** Set the device to 1.3× font size, turn brightness to maximum, and complete one 56-line checklist while standing. Count: scroll actions, mis-taps, and the number of times you had to look for a control. Today that run is ~37 scrolls plus a horizontal scroll to find Submit.

**The five-second test.** Show a supervisor screenshot 14 for five seconds and ask what the primary action is. The current answer will be "Enter Replaced Asset", because it's red, first, and visible.

---

*Prepared from the repository snapshot and screenshots supplied on 09 September 2026. File and line references are to that snapshot.*
