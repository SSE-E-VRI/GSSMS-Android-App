"""
compare.py
Compares Web vs Android generated report PDFs using PyMuPDF and Pillow.
Measures:
  (a) Page counts
  (b) Raster: raw and blurred mismatch % at 150 dpi (saves _web.png, _android.png, _diff.png, _overlay.png)
  (c) Word geometry: word sequence diff and |delta x0|, |delta y0| distribution in pt (mean, p95, max)
  (d) Drawings: vector fills and strokes match % within 1.5pt bbox tolerance
Writes summary to build/report_parity/summary.json and prints console table.
"""

import os
import sys
import json
import math
import argparse
import difflib
import fitz  # PyMuPDF
from PIL import Image, ImageChops, ImageFilter

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
WEB_PDF_DIR = os.path.join(ROOT_DIR, 'build', 'report_parity', 'web')
ANDROID_PDF_DIR = os.path.join(ROOT_DIR, 'build', 'report_parity', 'android')
OUT_DIR = os.path.join(ROOT_DIR, 'build', 'report_parity')
THRESHOLDS_FILE = os.path.join(os.path.dirname(__file__), 'thresholds.json')
GOLDEN_DIR = os.path.join(os.path.dirname(__file__), 'golden', 'android')

ALL_FIXTURES = [
    ('checklist_pm_full', 'Checklist'),
    ('checklist_pm_minimal', 'Checklist'),
    ('checklist_pm_long', 'Checklist'),
    ('breakdown_deficiency', 'Breakdown'),
    ('breakdown_complaint', 'Breakdown'),
    ('breakdown_jobwork', 'Breakdown'),
    ('inspection_pointwise', 'Inspection'),
    ('inspection_legacy', 'Inspection'),
    ('rectification_mixed', 'Rectification'),
    ('rectification_single', 'Rectification'),
]

DPI = 150
SCALE = DPI / 72.0

def percentile(data, p):
    if not data:
        return 0.0
    sorted_d = sorted(data)
    k = (len(sorted_d) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return sorted_d[int(k)]
    return sorted_d[int(f)] * (c - k) + sorted_d[int(c)] * (k - f)

def compare_rasters(web_page, android_page, prefix):
    # Render at 150 DPI
    mat = fitz.Matrix(SCALE, SCALE)
    pix_web = web_page.get_pixmap(matrix=mat, alpha=False)
    pix_and = android_page.get_pixmap(matrix=mat, alpha=False)

    img_web = Image.frombytes("RGB", [pix_web.width, pix_web.height], pix_web.samples)
    img_and = Image.frombytes("RGB", [pix_and.width, pix_and.height], pix_and.samples)

    # Save images
    os.makedirs(OUT_DIR, exist_ok=True)
    img_web.save(f"{prefix}_web.png")
    img_and.save(f"{prefix}_android.png")

    # Crop/pad if dimensions differ
    max_w = max(img_web.width, img_and.width)
    max_h = max(img_web.height, img_and.height)

    def pad(im):
        if im.width == max_w and im.height == max_h:
            return im
        new_im = Image.new("RGB", (max_w, max_h), (255, 255, 255))
        new_im.paste(im, (0, 0))
        return new_im

    img_web = pad(img_web)
    img_and = pad(img_and)

    total_pixels = max_w * max_h

    # Grayscale difference
    diff_rgb = ImageChops.difference(img_web, img_and)
    diff_grey = diff_rgb.convert("L")

    # Raw mismatch: |grey_diff| > 32
    diff_data = list(diff_grey.getdata())
    raw_mismatch_count = sum(1 for p in diff_data if p > 32)
    raw_mismatch_pct = (raw_mismatch_count / total_pixels) * 100.0

    # Diff visual image (red where > 32)
    diff_visual = Image.new("RGB", (max_w, max_h), (255, 255, 255))
    diff_vis_pixels = diff_visual.load()
    grey_pixels = diff_grey.load()
    for y in range(max_h):
        for x in range(max_w):
            if grey_pixels[x, y] > 32:
                diff_vis_pixels[x, y] = (255, 0, 0)
    diff_visual.save(f"{prefix}_diff.png")

    # Overlay: web in R, android in G & B
    r_chan = img_web.convert("L")
    g_chan = img_and.convert("L")
    b_chan = img_and.convert("L")
    overlay = Image.merge("RGB", (r_chan, g_chan, b_chan))
    overlay.save(f"{prefix}_overlay.png")

    # Blurred mismatch: GaussianBlur radius 1.5, threshold 48
    blur_web = img_web.filter(ImageFilter.GaussianBlur(1.5)).convert("L")
    blur_and = img_and.filter(ImageFilter.GaussianBlur(1.5)).convert("L")
    blur_diff = ImageChops.difference(blur_web, blur_and)
    blur_data = list(blur_diff.getdata())
    blur_mismatch_count = sum(1 for p in blur_data if p > 48)
    blurred_mismatch_pct = (blur_mismatch_count / total_pixels) * 100.0

    return {
        "raw_mismatch_pct": round(raw_mismatch_pct, 2),
        "blurred_mismatch_pct": round(blurred_mismatch_pct, 2),
    }

def normalize_word(w):
    return w.strip().lower()

def compare_words(doc_web, doc_android):
    words_web = []
    for p_no, page in enumerate(doc_web):
        # page.get_text("words"): (x0, y0, x1, y1, word, block_no, line_no, word_no)
        for w in page.get_text("words"):
            words_web.append((p_no, w[0], w[1], w[2], w[3], w[4]))

    words_and = []
    for p_no, page in enumerate(doc_android):
        for w in page.get_text("words"):
            words_and.append((p_no, w[0], w[1], w[2], w[3], w[4]))

    str_web = [w[5] for w in words_web]
    str_and = [w[5] for w in words_and]

    matcher = difflib.SequenceMatcher(None, str_web, str_and)
    identical = (str_web == str_and)

    dx_list = []
    dy_list = []
    worst_words = []

    for tag, i1, i2, j1, j2 in matcher.get_opcodes():
        if tag == 'equal':
            for k in range(i2 - i1):
                w1 = words_web[i1 + k]
                w2 = words_and[j1 + k]
                dx = abs(w1[1] - w2[1])
                dy = abs(w1[2] - w2[2])
                dist = math.hypot(dx, dy)
                dx_list.append(dx)
                dy_list.append(dy)
                worst_words.append((dist, dx, dy, w1[5], w1[0], w1[1], w1[2], w2[1], w2[2]))

    worst_words.sort(key=lambda x: x[0], reverse=True)

    delta_all = [math.hypot(x, y) for x, y in zip(dx_list, dy_list)] if dx_list else [0.0]

    return {
        "identical": identical,
        "total_web": len(str_web),
        "total_android": len(str_and),
        "matched_count": len(dx_list),
        "p95_delta_pt": round(percentile(delta_all, 95), 2),
        "max_delta_pt": round(max(delta_all) if delta_all else 0.0, 2),
        "mean_delta_pt": round(sum(delta_all) / len(delta_all) if delta_all else 0.0, 2),
        "worst_10": [
            {
                "word": w[3],
                "page": w[4] + 1,
                "dist_pt": round(w[0], 2),
                "dx_pt": round(w[1], 2),
                "dy_pt": round(w[2], 2),
                "web_pos": [round(w[5], 2), round(w[6], 2)],
                "and_pos": [round(w[7], 2), round(w[8], 2)],
            }
            for w in worst_words[:10]
        ],
    }

def compare_drawings(doc_web, doc_android):
    # Match drawings within 1.5pt by bbox
    total_web = 0
    matched_web = 0

    for p_no in range(min(len(doc_web), len(doc_android))):
        d_web = doc_web[p_no].get_drawings()
        d_and = doc_android[p_no].get_drawings()
        total_web += len(d_web)

        # Greedily match
        used_and = set()
        for w in d_web:
            wr = w.get("rect")
            if not wr:
                continue
            for idx, a in enumerate(d_and):
                if idx in used_and:
                    continue
                ar = a.get("rect")
                if not ar:
                    continue
                if (abs(wr[0] - ar[0]) <= 1.5 and
                    abs(wr[1] - ar[1]) <= 1.5 and
                    abs(wr[2] - ar[2]) <= 1.5 and
                    abs(wr[3] - ar[3]) <= 1.5):
                    used_and.add(idx)
                    matched_web += 1
                    break

    pct = (matched_web / total_web * 100.0) if total_web > 0 else 100.0
    return {
        "total_web": total_web,
        "matched": matched_web,
        "matched_pct": round(pct, 2),
    }

def run_comparison(target_fixture=None, update_golden=False, check_golden=False):
    fixtures = [f for f in ALL_FIXTURES if target_fixture is None or f[0] == target_fixture]

    thresholds = {}
    if os.path.exists(THRESHOLDS_FILE):
        with open(THRESHOLDS_FILE, 'r', encoding='utf-8') as f:
            thresholds = json.load(f)

    results = {}

    print("\n" + "=" * 90)
    print(f"{'Fixture':<24} | {'Pages (W/A)':<11} | {'Words Ident':<11} | {'Word Delta p95/max':<16} | {'Drawings':<9} | {'Raw/Blur %':<12}")
    print("-" * 90)

    all_passed = True

    for fid, kind in fixtures:
        web_pdf = os.path.join(WEB_PDF_DIR, f"{fid}.pdf")
        and_pdf = os.path.join(ANDROID_PDF_DIR, f"{fid}.pdf")

        if not os.path.exists(web_pdf) or not os.path.exists(and_pdf):
            print(f"{fid:<24} | MISSING PDF FILE(S)")
            all_passed = False
            continue

        doc_web = fitz.open(web_pdf)
        doc_and = fitz.open(and_pdf)

        pages_web = len(doc_web)
        pages_and = len(doc_and)
        pages_equal = (pages_web == pages_and)

        # Word comparison
        word_res = compare_words(doc_web, doc_and)

        # Drawings comparison
        draw_res = compare_drawings(doc_web, doc_and)

        # Page rasters comparison
        raster_pages = []
        for p in range(min(pages_web, pages_and)):
            prefix = os.path.join(OUT_DIR, f"{fid}_p{p+1}")
            r_res = compare_rasters(doc_web[p], doc_and[p], prefix)
            raster_pages.append(r_res)

        avg_raw = round(sum(r["raw_mismatch_pct"] for r in raster_pages) / len(raster_pages), 2) if raster_pages else 0.0
        avg_blur = round(sum(r["blurred_mismatch_pct"] for r in raster_pages) / len(raster_pages), 2) if raster_pages else 0.0

        fixture_summary = {
            "kind": kind,
            "pages_web": pages_web,
            "pages_android": pages_and,
            "pages_equal": pages_equal,
            "words_identical": word_res["identical"],
            "word_p95_delta_pt": word_res["p95_delta_pt"],
            "word_max_delta_pt": word_res["max_delta_pt"],
            "word_details": word_res,
            "drawings_matched_pct": draw_res["matched_pct"],
            "avg_raw_mismatch_pct": avg_raw,
            "avg_blurred_mismatch_pct": avg_blur,
            "page_rasters": raster_pages,
        }
        results[fid] = fixture_summary

        # Check threshold if configured
        k_thresh = thresholds.get(kind, {})
        # Note: during baseline, numbers will NOT meet threshold
        pass_p = pages_equal if k_thresh.get("pages_equal") else True
        pass_w = word_res["identical"] if k_thresh.get("words_identical") else True
        pass_d = word_res["p95_delta_pt"] <= k_thresh.get("word_delta_p95_max", 999)

        ident_str = "YES" if word_res["identical"] else "NO"
        delta_str = f"{word_res['p95_delta_pt']} / {word_res['max_delta_pt']}"
        raw_blur_str = f"{avg_raw}% / {avg_blur}%"
        pages_str = f"{pages_web} / {pages_and}"

        print(f"{fid:<24} | {pages_str:<11} | {ident_str:<11} | {delta_str:<16} | {draw_res['matched_pct']:>6.1f}%  | {raw_blur_str:<12}")

    print("=" * 90 + "\n")

    summary_file = os.path.join(OUT_DIR, "summary.json")
    with open(summary_file, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"Summary written to {summary_file}")

    return results

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", help="Single fixture ID to compare")
    parser.add_argument("--update-golden", action="store_true", help="Update golden reference rasters")
    parser.add_argument("--golden", action="store_true", help="Compare against golden references")
    args = parser.parse_args()

    run_comparison(args.fixture, update_golden=args.update_golden, check_golden=args.golden)
