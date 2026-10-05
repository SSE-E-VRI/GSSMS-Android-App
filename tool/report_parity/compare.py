"""
compare.py
Compares Web (Chrome) vs Android report PDFs using PyMuPDF and Pillow.

Metrics per fixture
  pages            page counts
  words            sequence diff of words in reading order (page, round(baseline/1.5), x);
                   position delta uses the first-glyph ORIGIN (x = origin x, y = BASELINE),
                   not the bbox y0 (which is biased by the font ascender)
  style %          matched words whose weight class (R/SB/B, italic counts as R), size (+-0.05)
                   and colour (max channel delta <= 8) agree
  vector recall/precision
                   words+images redacted, rasterised at 150 dpi cropped to the common rect
                   (0,0,595.0,841.5); ink = grey<245; colour-aware palette masks (dRGB<=24);
                   MaxFilter(7) dilation. Representation independent.
  image %          get_image_info bboxes matched within 1.5pt
  raster           raw / blurred mismatch at 150 dpi, cropped to the common rect
  legacy_bbox_match_pct  old greedy drawing-bbox match (informational only)

Writes build/report_parity/summary.json, prints a table, exits 1 on any failure.
Options: --fixture ID, --ledger, --golden, --update-golden
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
ANDROID_PDF_DIR = os.environ.get('REPORT_PARITY_ANDROID_DIR') or os.path.join(ROOT_DIR, 'build', 'report_parity', 'android')
OUT_DIR = os.environ.get('REPORT_PARITY_OUTDIR') or os.path.join(ROOT_DIR, 'build', 'report_parity')
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
    ('checklist_pm_stress', 'Checklist'),
    ('breakdown_long', 'Breakdown'),
    ('rectification_long', 'Rectification'),
    ('register_checklist', 'Checklist'),
]

DPI = 150
SCALE = DPI / 72.0
COMMON_RECT = fitz.Rect(0, 0, 595.0, 841.5)
PAGE_H = 842.0
BASELINE_ROW = 1.5   # pt, reading-order row quantisation
IMAGE_TOL = 1.5      # pt
PALETTE_TOL = 24     # max-channel delta for palette masks
DILATE = 7           # MaxFilter size (3px radius @150dpi ~ 1.44pt)
INK_GREY = 245


def percentile(data, p):
    if not data:
        return 0.0
    s = sorted(data)
    k = (len(s) - 1) * (p / 100.0)
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return s[int(k)]
    return s[int(f)] * (c - k) + s[int(c)] * (k - f)


# --------------------------------------------------------------------------- words

def weight_class(font):
    n = font.split('+')[-1]
    if 'Semibold' in n:
        return 'SB'
    if 'Bold' in n:
        return 'B'
    return 'R'  # Regular and Italic


def extract_words(doc):
    """Words (split on whitespace) from rawdict, positioned by first char origin."""
    out = []
    for pn, p in enumerate(doc):
        d = p.get_text('rawdict')
        for b in d['blocks']:
            for l in b.get('lines', []):
                for s in l['spans']:
                    cur = []
                    for ch in s['chars'] + [None]:
                        if ch is None or ch['c'].isspace():
                            if cur:
                                out.append(dict(
                                    p=pn,
                                    t=''.join(c['c'] for c in cur),
                                    x=cur[0]['origin'][0],
                                    y=cur[0]['origin'][1],
                                    x1=cur[-1]['bbox'][2],
                                    font=s['font'].split('+')[-1],
                                    size=s['size'],
                                    color=s['color'],
                                ))
                            cur = []
                        else:
                            cur.append(ch)
    return reading_order(out)


def reading_order(words):
    """Reading order = (page, baseline row, x). Rows are chained clusters of baselines
    (consecutive baselines <= BASELINE_ROW apart), which is robust to the bucket-edge
    flips of a plain round(baseline/1.5) key."""
    words = sorted(words, key=lambda w: (w['p'], w['y']))
    out = []
    row = []
    row_id = 0
    last = None
    for w in words:
        if last is not None and (w['p'] != last['p'] or w['y'] - last['y'] > BASELINE_ROW):
            row_id += 1
        w['row'] = row_id
        last = w
    return sorted(words, key=lambda w: (w['p'], w['row'], w['x']))


def colour_delta(c1, c2):
    return max(abs(((c1 >> s) & 255) - ((c2 >> s) & 255)) for s in (16, 8, 0))


def style_ok(a, b):
    return (weight_class(a['font']) == weight_class(b['font'])
            and abs(a['size'] - b['size']) <= 0.05
            and colour_delta(a['color'], b['color']) <= 8)


def match_words(doc_web, doc_and):
    ww = extract_words(doc_web)
    aw = extract_words(doc_and)
    sm = difflib.SequenceMatcher(None, [w['t'] for w in ww], [w['t'] for w in aw], autojunk=False)
    pairs = []
    inserts = []   # in android only
    deletes = []   # in web only
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == 'equal':
            pairs += [(ww[i1 + k], aw[j1 + k]) for k in range(i2 - i1)]
        else:
            deletes += [(w['p'] + 1, w['t']) for w in ww[i1:i2]]
            inserts += [(w['p'] + 1, w['t']) for w in aw[j1:j2]]
    return ww, aw, pairs, deletes, inserts


def compare_words(doc_web, doc_and):
    ww, aw, pairs, deletes, inserts = match_words(doc_web, doc_and)
    identical = [w['t'] for w in ww] == [w['t'] for w in aw]
    deltas = []
    worst = []
    style_hits = 0
    for a, b in pairs:
        dx = b['x'] - a['x']
        dy = (b['y'] - a['y']) + (b['p'] - a['p']) * PAGE_H
        dist = math.hypot(dx, dy)
        deltas.append(dist)
        worst.append((dist, dx, dy, a, b))
        if style_ok(a, b):
            style_hits += 1
    worst.sort(key=lambda x: x[0], reverse=True)
    style_pct = (style_hits / len(pairs) * 100.0) if pairs else 100.0
    return {
        "identical": identical,
        "total_web": len(ww),
        "total_android": len(aw),
        "matched_count": len(pairs),
        "p95_delta_pt": round(percentile(deltas, 95), 2),
        "max_delta_pt": round(max(deltas) if deltas else 0.0, 2),
        "mean_delta_pt": round(sum(deltas) / len(deltas) if deltas else 0.0, 2),
        "style_match_pct": round(style_pct, 2),
        "deleted_from_web": deletes[:40],
        "inserted_in_android": inserts[:40],
        "worst_10": [
            {
                "word": w[3]['t'],
                "page": w[3]['p'] + 1,
                "dist_pt": round(w[0], 2),
                "dx_pt": round(w[1], 2),
                "dy_pt": round(w[2], 2),
                "web_pos": [round(w[3]['x'], 2), round(w[3]['y'], 2)],
                "and_pos": [round(w[4]['x'], 2), round(w[4]['y'], 2)],
            }
            for w in worst[:10]
        ],
    }


def print_ledger(doc_web, doc_and, fid, n=25):
    """First n vertical steps: places where the Android-minus-web baseline offset changes."""
    ww, aw, pairs, deletes, inserts = match_words(doc_web, doc_and)
    print(f"\n--- ledger {fid}: web {len(ww)} android {len(aw)} matched {len(pairs)} "
          f"(deleted {len(deletes)}, inserted {len(inserts)})")
    for p, t in deletes[:10]:
        print(f"    [web only] p{p} {t}")
    for p, t in inserts[:10]:
        print(f"    [android only] p{p} {t}")
    prev = None
    steps = 0
    for i, (a, b) in enumerate(pairs):
        if a['p'] != b['p']:
            continue
        dy = b['y'] - a['y']
        dx = b['x'] - a['x']
        if prev is not None and abs(a['y'] - prev[2]) > 0.5 and abs(dy - prev[1]) > 0.6 and a['p'] == prev[3]:
            print(f"  #{i:4} p{a['p'] + 1} {a['t'][:16]:16} web_y={a['y']:7.1f} dy {prev[1]:+.2f} -> {dy:+.2f} "
                  f"(step {dy - prev[1]:+.2f}) dx={dx:+.1f} {weight_class(a['font'])}/{a['size']:.2f} "
                  f"vs {weight_class(b['font'])}/{b['size']:.2f}")
            steps += 1
            if steps >= n:
                break
        prev = (a['t'], dy, a['y'], a['p'])
    if steps == 0:
        print("  (no vertical steps > 0.6pt)")


# --------------------------------------------------------------------------- vectors

def _clean_page_image(page):
    """Rasterise page with words and images removed, cropped to the common rect."""
    for w in page.get_text('words'):
        page.add_redact_annot(fitz.Rect(w[:4]), fill=False)
    for info in page.get_image_info():
        page.add_redact_annot(fitz.Rect(info['bbox']), fill=False)
    page.apply_redactions(images=fitz.PDF_REDACT_IMAGE_REMOVE,
                          graphics=fitz.PDF_REDACT_LINE_ART_NONE,
                          text=fitz.PDF_REDACT_TEXT_REMOVE)
    pix = page.get_pixmap(matrix=fitz.Matrix(SCALE, SCALE), alpha=False, clip=COMMON_RECT)
    return Image.frombytes('RGB', [pix.width, pix.height], pix.samples)


def _ink(im):
    return im.convert('L').point(lambda v: 255 if v < INK_GREY else 0)


def _colour_mask(im, ink, rgb):
    solid = Image.new('RGB', im.size, rgb)
    d = ImageChops.difference(im, solid)
    r, g, b = d.split()
    m = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v <= PALETTE_TOL else 0)
    return ImageChops.multiply(m, ink)  # both binary 0/255 -> logical and


def _palette(doc):
    """Distinct non-white drawing colours (clustered within PALETTE_TOL)."""
    cols = []
    for page in doc:
        for d in page.get_drawings():
            for key in ('fill', 'color'):
                c = d.get(key)
                if not c:
                    continue
                rgb = tuple(int(round(v * 255)) for v in c)
                if len(rgb) == 1:
                    rgb = rgb * 3
                if len(rgb) != 3 or sum(1 for v in rgb if v > 250) == 3:
                    continue
                cols.append(rgb)
    pal = []
    for c in cols:
        if not any(max(abs(a - b) for a, b in zip(c, p)) <= PALETTE_TOL for p in pal):
            pal.append(c)
    return pal


def _count(mask):
    return mask.histogram()[255]


def compare_vectors(web_path, and_path):
    """Returns recall/precision over the pages both documents have."""
    dw = fitz.open(web_path)
    da = fitz.open(and_path)
    pal_w = _palette(dw)
    pal_a = _palette(da)
    n = min(len(dw), len(da))
    tot_w = tot_a = hit_w = hit_a = 0
    for p in range(n):
        iw = _clean_page_image(dw[p])
        ia = _clean_page_image(da[p])
        inkw = _ink(iw)
        inka = _ink(ia)
        for rgb in pal_w:
            mw = _colour_mask(iw, inkw, rgb)
            nw = _count(mw)
            if not nw:
                continue
            ma = _colour_mask(ia, inka, rgb).filter(ImageFilter.MaxFilter(DILATE))
            tot_w += nw
            hit_w += _count(ImageChops.multiply(mw, ma))
        for rgb in pal_a:
            ma = _colour_mask(ia, inka, rgb)
            na = _count(ma)
            if not na:
                continue
            mw = _colour_mask(iw, inkw, rgb).filter(ImageFilter.MaxFilter(DILATE))
            tot_a += na
            hit_a += _count(ImageChops.multiply(ma, mw))
    return {
        "vector_recall_pct": round(hit_w / tot_w * 100.0, 2) if tot_w else 100.0,
        "vector_precision_pct": round(hit_a / tot_a * 100.0, 2) if tot_a else 100.0,
        "web_ink_px": tot_w,
        "android_ink_px": tot_a,
    }


def compare_images(doc_web, doc_and):
    total = matched = 0
    extra = 0
    for p in range(max(len(doc_web), len(doc_and))):
        bw = [fitz.Rect(i['bbox']) for i in doc_web[p].get_image_info()] if p < len(doc_web) else []
        ba = [fitz.Rect(i['bbox']) for i in doc_and[p].get_image_info()] if p < len(doc_and) else []
        total += len(bw)
        used = set()
        for r in bw:
            for k, r2 in enumerate(ba):
                if k in used:
                    continue
                if max(abs(r.x0 - r2.x0), abs(r.y0 - r2.y0), abs(r.x1 - r2.x1), abs(r.y1 - r2.y1)) <= IMAGE_TOL:
                    used.add(k)
                    matched += 1
                    break
        extra += len(ba) - len(used)
    pct = (matched / total * 100.0) if total else (100.0 if extra == 0 else 0.0)
    return {"image_match_pct": round(pct, 2), "images_web": total, "images_matched": matched,
            "images_android_unmatched": extra}


def legacy_bbox_match(doc_web, doc_android):
    """Old greedy drawing-bbox matcher (informational only; biased by representation)."""
    total_web = matched_web = 0
    for p_no in range(min(len(doc_web), len(doc_android))):
        d_web = doc_web[p_no].get_drawings()
        d_and = doc_android[p_no].get_drawings()
        total_web += len(d_web)
        used = set()
        for w in d_web:
            wr = w.get("rect")
            if not wr:
                continue
            for idx, a in enumerate(d_and):
                if idx in used:
                    continue
                ar = a.get("rect")
                if ar and all(abs(wr[k] - ar[k]) <= 1.5 for k in range(4)):
                    used.add(idx)
                    matched_web += 1
                    break
    return round(matched_web / total_web * 100.0, 2) if total_web else 100.0


# --------------------------------------------------------------------------- raster

def _page_image(page):
    pix = page.get_pixmap(matrix=fitz.Matrix(SCALE, SCALE), alpha=False, clip=COMMON_RECT)
    return Image.frombytes("RGB", [pix.width, pix.height], pix.samples)


def _over(im, thr):
    return im.point(lambda v: 255 if v > thr else 0)


def compare_rasters(web_page, android_page, prefix):
    os.makedirs(OUT_DIR, exist_ok=True)
    img_web = _page_image(web_page)
    img_and = _page_image(android_page)
    img_web.save(f"{prefix}_web.png")
    img_and.save(f"{prefix}_android.png")
    total = img_web.width * img_web.height

    diff_grey = ImageChops.difference(img_web, img_and).convert("L")
    over = _over(diff_grey, 32)
    raw_pct = _count(over) / total * 100.0

    red = Image.new("RGB", img_web.size, (255, 0, 0))
    white = Image.new("RGB", img_web.size, (255, 255, 255))
    Image.composite(red, white, over).save(f"{prefix}_diff.png")

    Image.merge("RGB", (img_web.convert("L"), img_and.convert("L"), img_and.convert("L"))).save(f"{prefix}_overlay.png")

    bw = img_web.filter(ImageFilter.GaussianBlur(1.5)).convert("L")
    ba = img_and.filter(ImageFilter.GaussianBlur(1.5)).convert("L")
    blur_pct = _count(_over(ImageChops.difference(bw, ba), 48)) / total * 100.0
    return {"raw_mismatch_pct": round(raw_pct, 2), "blurred_mismatch_pct": round(blur_pct, 2)}


# --------------------------------------------------------------------------- driver

def check_thresholds(s, th):
    """Returns a list of failure strings."""
    fails = []
    if th.get("pages_equal") and not s["pages_equal"]:
        fails.append("pages")
    if th.get("words_identical") and not s["words_identical"]:
        fails.append("words")
    if s["word_p95_delta_pt"] > th.get("word_delta_p95_max", 999):
        fails.append(f"p95 {s['word_p95_delta_pt']}>{th['word_delta_p95_max']}")
    if s["word_max_delta_pt"] > th.get("word_delta_max", 999):
        fails.append(f"max {s['word_max_delta_pt']}>{th['word_delta_max']}")
    if s["style_match_pct"] < th.get("style_match_min", 0):
        fails.append(f"style {s['style_match_pct']}<{th['style_match_min']}")
    if s["vector_recall_pct"] < th.get("vector_recall_min", 0):
        fails.append(f"recall {s['vector_recall_pct']}<{th['vector_recall_min']}")
    if s["vector_precision_pct"] < th.get("vector_precision_min", 0):
        fails.append(f"precision {s['vector_precision_pct']}<{th['vector_precision_min']}")
    if s["image_match_pct"] < th.get("image_match_min", 0):
        fails.append(f"image {s['image_match_pct']}<{th['image_match_min']}")
    if s["avg_blurred_mismatch_pct"] > th.get("blurred_mismatch_max", 999):
        fails.append(f"blur {s['avg_blurred_mismatch_pct']}>{th['blurred_mismatch_max']}")
    if s["avg_raw_mismatch_pct"] > th.get("raw_mismatch_max", 999):
        fails.append(f"raw {s['avg_raw_mismatch_pct']}>{th['raw_mismatch_max']}")
    return fails


def run_comparison(target_fixture=None, update_golden=False, check_golden=False, ledger=False):
    fixtures = [f for f in ALL_FIXTURES if target_fixture is None or f[0] == target_fixture]

    thresholds = {}
    if os.path.exists(THRESHOLDS_FILE):
        with open(THRESHOLDS_FILE, 'r', encoding='utf-8') as f:
            thresholds = json.load(f)

    results = {}
    failures = {}
    all_passed = True

    header = (f"{'Fixture':<22} | {'Pg W/A':<6} | {'Words':<5} | {'Style%':>6} | {'Word p95/max':<13} | "
              f"{'VecRec/Prec':<11} | {'Img%':>5} | {'Blur/Raw %':<11} | {'legacy%':>7}")
    print("\n" + "=" * len(header))
    print(header)
    print("-" * len(header))

    for fid, kind in fixtures:
        web_pdf = os.path.join(WEB_PDF_DIR, f"{fid}.pdf")
        and_pdf = os.path.join(ANDROID_PDF_DIR, f"{fid}.pdf")

        if not os.path.exists(web_pdf) or not os.path.exists(and_pdf):
            print(f"{fid:<22} | MISSING PDF FILE(S)")
            failures[fid] = ["missing pdf"]
            all_passed = False
            continue

        doc_web = fitz.open(web_pdf)
        doc_and = fitz.open(and_pdf)
        pages_web = len(doc_web)
        pages_and = len(doc_and)
        pages_equal = pages_web == pages_and

        word_res = compare_words(doc_web, doc_and)
        vec_res = compare_vectors(web_pdf, and_pdf)
        img_res = compare_images(doc_web, doc_and)
        legacy = legacy_bbox_match(doc_web, doc_and)

        raster_pages = []
        for p in range(min(pages_web, pages_and)):
            prefix = os.path.join(OUT_DIR, f"{fid}_p{p + 1}")
            raster_pages.append(compare_rasters(doc_web[p], doc_and[p], prefix))

        if update_golden:
            os.makedirs(GOLDEN_DIR, exist_ok=True)
            mat = fitz.Matrix(SCALE, SCALE)
            for p in range(pages_and):
                pix_and = doc_and[p].get_pixmap(matrix=mat, alpha=False)
                pix_and.save(os.path.join(GOLDEN_DIR, f"{fid}_p{p + 1}.png"))
            print(f"Updated golden for {fid} ({pages_and} page(s)) in {GOLDEN_DIR}")

        if check_golden:
            mat = fitz.Matrix(SCALE, SCALE)
            for p in range(pages_and):
                g_path = os.path.join(GOLDEN_DIR, f"{fid}_p{p + 1}.png")
                if not os.path.exists(g_path):
                    print(f"ERROR: Missing golden file {g_path}")
                    all_passed = False
                    continue
                pix_and = doc_and[p].get_pixmap(matrix=mat, alpha=False)
                img_and = Image.frombytes("RGB", [pix_and.width, pix_and.height], pix_and.samples)
                img_gold = Image.open(g_path).convert("RGB")
                if img_and.size != img_gold.size:
                    print(f"ERROR: Golden size mismatch for {fid} p{p + 1}: {img_and.size} vs {img_gold.size}")
                    all_passed = False
                    continue
                n_diff = _count(_over(ImageChops.difference(img_and, img_gold).convert("L"), 0))
                if n_diff > 0:
                    pct = n_diff / (img_and.width * img_and.height) * 100.0
                    print(f"GOLDEN REGRESSION: {fid} p{p + 1} differs from golden by {n_diff} px ({pct:.2f}%)")
                    all_passed = False
                else:
                    print(f"Golden match: {fid} p{p + 1} matches golden reference (0 px difference)")

        avg_raw = round(sum(r["raw_mismatch_pct"] for r in raster_pages) / len(raster_pages), 2) if raster_pages else 0.0
        avg_blur = round(sum(r["blurred_mismatch_pct"] for r in raster_pages) / len(raster_pages), 2) if raster_pages else 0.0

        summary = {
            "kind": kind,
            "pages_web": pages_web,
            "pages_android": pages_and,
            "pages_equal": pages_equal,
            "words_identical": word_res["identical"],
            "style_match_pct": word_res["style_match_pct"],
            "word_p95_delta_pt": word_res["p95_delta_pt"],
            "word_max_delta_pt": word_res["max_delta_pt"],
            "word_details": word_res,
            "vector_recall_pct": vec_res["vector_recall_pct"],
            "vector_precision_pct": vec_res["vector_precision_pct"],
            "vector_details": vec_res,
            "image_match_pct": img_res["image_match_pct"],
            "image_details": img_res,
            "legacy_bbox_match_pct": legacy,
            "avg_raw_mismatch_pct": avg_raw,
            "avg_blurred_mismatch_pct": avg_blur,
            "page_rasters": raster_pages,
        }
        fails = check_thresholds(summary, thresholds.get(kind, {}))
        summary["failures"] = fails
        results[fid] = summary
        if fails:
            failures[fid] = fails
            all_passed = False

        print(f"{fid:<22} | {pages_web} / {pages_and:<2} | {'YES' if word_res['identical'] else 'NO':<5} | "
              f"{word_res['style_match_pct']:>6.1f} | {word_res['p95_delta_pt']:>5} / {word_res['max_delta_pt']:<6} | "
              f"{vec_res['vector_recall_pct']:>5.1f}/{vec_res['vector_precision_pct']:<5.1f} | "
              f"{img_res['image_match_pct']:>5.0f} | {avg_blur:>4}/{avg_raw:<6} | {legacy:>6.1f}%")

        if ledger:
            print_ledger(doc_web, doc_and, fid)

    print("=" * len(header))
    if failures:
        print("\nFAILURES:")
        for fid, f in failures.items():
            print(f"  {fid}: {', '.join(f)}")
    else:
        print("\nAll fixtures pass thresholds.")

    os.makedirs(OUT_DIR, exist_ok=True)
    summary_file = os.path.join(OUT_DIR, "summary.json")
    with open(summary_file, "w", encoding="utf-8") as f:
        json.dump(results, f, indent=2)
    print(f"Summary written to {summary_file}")

    return results, all_passed


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixture", help="Single fixture ID to compare")
    parser.add_argument("--ledger", action="store_true", help="Print the first 25 vertical baseline steps")
    parser.add_argument("--update-golden", action="store_true", help="Update golden reference rasters")
    parser.add_argument("--golden", action="store_true", help="Compare against golden references")
    args = parser.parse_args()

    _, ok = run_comparison(args.fixture, update_golden=args.update_golden,
                           check_golden=args.golden, ledger=args.ledger)
    if not ok:
        sys.exit(1)
