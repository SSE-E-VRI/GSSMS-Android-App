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
3. **Web renders the light theme only.** If the dark app theme is active when a user prints, `[data-theme="dark"]` rules (`.text-muted`, h1-h6) may leak into the print output; this is not exercised.
4. Chrome pixel snapping (+-0.375pt), kerning on uppercase titles, the skewed Selawik italic and Selawik Semibold advance widths (about 1.6% wide vs Segoe) set the floor for word p95 and cannot be removed without a derived font.
