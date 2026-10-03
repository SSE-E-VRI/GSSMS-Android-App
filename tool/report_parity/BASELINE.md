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
