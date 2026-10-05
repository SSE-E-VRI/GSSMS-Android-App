# Stage 0 Baseline Report: Job Work Report Parity Harness

Generated: 2026-10-03
Reference Environment: Chrome on Windows, A4, 1 cm margins, headers/footers OFF, background graphics OFF.

## 1. Summary of Baseline Numbers

As expected prior to Stage 1 and Stage 2 implementation, baseline comparison between Chrome web reports and current Android reports exhibits substantial layout, typography, and page count differences.

| Fixture | Pages (Web / Android) | Words Identical | Word Δ (p95 / max pt) | Drawings Matched | Raw Mismatch % | Blurred Mismatch % |
|---|---|---|---|---|---|---|
| `checklist_pm_full` | 2 / 1 | NO | 401.72 / 504.21 | 0.0% | 15.30% | 16.95% |
| `checklist_pm_minimal` | 1 / 1 | NO | 356.34 / 459.32 | 0.0% | 9.00% | 9.10% |
| `checklist_pm_long` | 5 / 3 | NO | 663.73 / 695.33 | 0.0% | 10.61% | 11.16% |
| `breakdown_deficiency` | 1 / 1 | NO | 274.95 / 409.11 | 0.0% | 16.67% | 15.97% |
| `breakdown_complaint` | 1 / 1 | NO | 309.93 / 433.01 | 0.0% | 7.60% | 7.61% |
| `breakdown_jobwork` | 1 / 1 | NO | 194.13 / 425.29 | 0.0% | 6.58% | 5.95% |
| `inspection_pointwise` | 2 / 2 | NO | 436.98 / 703.11 | 0.0% | 12.74% | 12.71% |
| `inspection_legacy` | 1 / 1 | NO | 367.69 / 407.37 | 0.0% | 12.35% | 12.61% |
| `rectification_mixed` | 2 / 2 | NO | 360.18 / 410.78 | 0.0% | 8.13% | 7.78% |
| `rectification_single` | 1 / 1 | NO | 316.64 / 407.59 | 0.0% | 9.25% | 8.73% |

## 2. Key Observations & Inaccuracies in Current Android Reports

1. **Page Counts:**
   - `checklist_pm_full`: Web is 2 pages, Android fits onto 1 page (missing sections, compact table format, and missing line attachment hiding).
   - `checklist_pm_long`: Web is 5 pages, Android is 3 pages (spacing, padding, and row heights differ markedly).
2. **Typography & Font:**
   - Web uses Segoe UI on Windows Chrome; Android currently uses Helvetica with ASCII replacements (`pdfSafe`).
3. **Margins & Header/Footer:**
   - Android adds an artificial bottom margin with "Generated: ... / Page x of y" footer, reducing printable height.
4. **Drawing Matches:**
   - 0.0% of drawing boxes and strokes currently match due to differences in table border colors, cards, and absence of section border wrappers in current Android code.
5. **Determinism Verification:**
   - Consecutive runs of `render_web.mjs` produce 100% byte-and-geometry-identical output in `extract_spec.py`.

---

# WP-M update (2026-10-05): metric and harness corrections

The Stage 0 table above is historical (old metric, old Android layout). The harness now reports:

- **Words**: first-glyph origin, BASELINE y (not bbox y0, which is biased +0.089 x size for Selawik vs Segoe), reading order = (page, baseline row, x) where a row is a chain of baselines <= 1.5pt apart. Words that swap rows because Android drifts more than 1.5pt show up as "words not identical" (insert/delete listing); this is a real drift symptom, not a metric artefact.
- **Style %**: weight class (R / SB / B, italic = R), size +-0.05, colour max-channel delta <= 8.
- **Vector recall / precision** (replaces "Drawings matched"): words and images redacted, 150 dpi, cropped to (0,0,595.0,841.5), ink = grey < 245, colour-aware palette masks (delta RGB <= 24), MaxFilter(7). `legacy_bbox_match_pct` is kept in summary.json for information only.
- **Image placement %**: `get_image_info` bboxes within 1.5pt.
- **Raster**: both pages cropped to the common rect (no white padding).
- `compare.py` exits 1 on any failed threshold; `run_all.py` runs `npx vite build` first; bootstrap pinned to 5.3.8 (production lock).
- Thresholds: word p95/max and blurred/raw UNCHANGED; new `vector_recall_min` / `vector_precision_min` 95 (Inspection 93), `image_match_min` 100, `style_match_min` 100.
- New helpers: `drift2.py`, `draw.py`, `gfx.py`, `floor.py`, `check_reference.py`, `generate_stress_fixtures.py`.
- New fixtures: `checklist_pm_stress` (multi-line remarks, 120+ char schedule, 3-line cells), `breakdown_long` (3-paragraph pre-wrap bodies, 7 BEFORE + 4 AFTER photos), `rectification_long` (6 items, multi-line reasons).

## Best-achievable floor (`py tool/report_parity/floor.py glyph|span`)

Re-typesets every web text span in Selawik at Chrome's exact origin and keeps web graphics. `glyph` = per-glyph placement (glyph-shape difference only); `span` = per-span placement with Selawik advances (no kerning, Semibold widths not metric compatible, no real italic). Averages over pages; "worst page" is the per-page maximum blurred figure for `span`.

| Fixture | glyph raw % | glyph blur % | span raw % | span blur % | span worst-page blur % |
|---|---|---|---|---|---|
| `checklist_pm_full` | 0.71 | 0.01 | 1.70 | 0.66 | 1.15 |
| `checklist_pm_minimal` | 0.54 | 0.01 | 1.29 | 0.58 | 0.58 |
| `checklist_pm_long` | 0.78 | 0.03 | 1.66 | 0.57 | 0.78 |
| `breakdown_deficiency` | 0.32 | 0.01 | 1.01 | 0.33 | 0.64 |
| `breakdown_complaint` | 0.77 | 0.03 | 2.39 | 0.81 | 0.81 |
| `breakdown_jobwork` | 0.58 | 0.02 | 2.01 | 0.73 | 0.73 |
| `inspection_pointwise` | 0.71 | 0.01 | 1.59 | 0.37 | 0.58 |
| `inspection_legacy` | 0.66 | 0.02 | 1.66 | 0.43 | 0.43 |
| `rectification_mixed` | 0.51 | 0.01 | 1.58 | 0.54 | 0.91 |
| `rectification_single` | 0.46 | 0.02 | 1.43 | 0.55 | 0.55 |
| `checklist_pm_stress` | 1.09 | 0.01 | 2.48 | 0.90 | 1.44 |
| `breakdown_long` | 0.56 | 0.01 | 1.56 | 0.34 | 0.57 |
| `rectification_long` | 0.72 | 0.01 | 2.16 | 0.58 | 0.97 |

All floors are well inside the blurred (1.5 / 2.0) and raw (6 / 7) thresholds.

## Harness limitations (known, unresolved)

1. **The reference is unverified against a real print dialog.** The web reference is Playwright `page.pdf` (A4 595.92 x 842.88, margins 1 cm = 27.75pt, headers/footers OFF, backgrounds OFF). Chrome's print dialog defaults to Headers and footers ON and its "Default" margins may differ. Print one real report (Save as PDF, usual settings) and run `py tool/report_parity/check_reference.py <real.pdf>` to compare page size, first text x/y and any text in the margins.
2. **Fixture realism.** Fixtures are synthetic: no Indic text, solid-colour placeholder photos, at most 11 photos, short strings except in the three stress fixtures. `inspection_pointwise` sits within about 1pt of a page break (tests rounding more than layout).
3. **Web renders the light theme only.** If the dark app theme is active when a user prints, `[data-theme="dark"]` rules (`.text-muted`, h1–h6) may leak into the print output; this is not exercised.
4. Chrome pixel snapping (+-0.375pt), kerning on uppercase titles, the skewed Selawik italic and Selawik Semibold advance widths (about 1.6% wide vs Segoe) set the floor for word p95 and cannot be removed without a derived font.

---

# Final state (2026-10-05, commit a94291c; web v1.9.1 reference)

`py tool/report_parity/run_all.py` after the shared-primitive cleanup (audit items 1–9 all verified done in code; plus one new measured fix: `CssBox` backgrounds paint inset by half the border width per side, matching Chrome's print fill paths on badges/metaGrids/thumbs — commit a94291c, +0.27pt precision on `rectification_long`, no fixture regressed).

| Fixture | Pg W/A | Words | Style% | Word p95/max | VecRec/Prec | Img% | Blur/Raw% | vs thresholds |
|---|---|---|---|---|---|---|---|---|
| `checklist_pm_full` | 2/2 | YES | 100.0 | 0.88/1.18 | 98.0/96.0 | 100 | 0.43/2.16 | PASS |
| `checklist_pm_minimal` | 1/1 | YES | 100.0 | 0.75/0.75 | 100.0/98.5 | 100 | 0.38/1.84 | PASS |
| `checklist_pm_long` | 5/5 | YES | 100.0 | 1.02/1.28 | 97.1/97.8 | 100 | 0.35/1.65 | PASS |
| `breakdown_deficiency` | 2/2 | YES | 100.0 | 0.77/0.94 | 97.5/95.5 | 100 | 0.17/1.80 | PASS |
| `breakdown_complaint` | 1/1 | YES | 100.0 | 1.00/1.13 | 100.0/98.5 | 100 | 0.19/2.17 | PASS |
| `breakdown_jobwork` | 1/1 | YES | 100.0 | 0.75/0.88 | 100.0/96.7 | 100 | 0.21/1.86 | PASS |
| `inspection_pointwise` | 2/2 | YES | 100.0 | 0.76/1.32 | 99.7/99.0 | 100 | 0.16/1.65 | PASS |
| `inspection_legacy` | 1/1 | YES | 100.0 | 0.75/0.99 | 99.9/98.6 | 100 | 0.22/1.82 | PASS |
| `rectification_mixed` | 2/2 | YES | 100.0 | 0.87/2.47 | 95.6/95.3 | 100 | 0.14/1.56 | PASS |
| `rectification_single` | 1/1 | YES | 100.0 | 1.29/2.28 | 99.8/95.1 | 100 | 0.25/1.39 | PASS |
| `checklist_pm_stress` | 2/2 | YES | 100.0 | 0.98/1.40 | 98.0/96.4 | 100 | 0.67/3.11 | PASS |
| `breakdown_long` | 2/2 | YES | 100.0 | 0.60/1.47 | 98.4/96.7 | 100 | 0.14/1.58 | PASS |
| `rectification_long` | 3/3 | YES | 100.0 | 0.75/2.46 | 95.5/91.7 | 100 | 0.19/1.99 | **FAIL: precision 91.7 < 95.0** |

## Per-fixture residuals (why the numbers stop here)

- **Words.** Every remaining ledger step is a ±0.75pt alternation (Chrome whole-px row/box-edge snapping, e.g. `rectification_long` BEFORE/FINDING/ACTION rows) — no first step above 0.5pt is actionable layout drift. Maxima (2.28–2.47 on rectification fixtures) sit on Semibold runs and kerned uppercase headings: accepted D1 residuals (no derived font).
- **Style 100%, image 100%, pages equal, words identical** on all 13 fixtures.
- **Vector.** 12/13 fixtures pass recall and precision. The single failure is `rectification_long` precision 91.7 (recall 95.5 passes). Per-colour analysis: losing colours are badge fills (`#fee2e2` pink 83%, `#dcfce7` green 92%), metaGrid fill (`#f9fafb` 91%) and neutral borders (`#6b7280` 80%), concentrated on pages with item badges. Measured cause: Chrome lays out some badge boxes ~0.7pt (1px) shorter than the CSS box model predicts (a "Pending" badge path of 14.26pt vs our 15.0pt with identical text metrics, baselines and tops — verified with an isolated Chrome probe: badge heights alternate 19/20px by position, i.e. Chrome pixel-snapping of box edges). Our boxes match the CSS values; chasing sub-pixel box heights the CSS does not determine would be tuning to noise. Recorded as **open**: Chrome pixel-snapping residual, geometry agrees within ~0.75pt.
- **Blur/raw.** All inside thresholds (worst `checklist_pm_stress` 0.67/3.11 vs 1.5/6.0), at the `floor.py` span floor.
- No WIP regression: at 7c31ed9 word p95 reached 3.62 and vector fell to 79–85 on rectification; both are now at or near the floor.
