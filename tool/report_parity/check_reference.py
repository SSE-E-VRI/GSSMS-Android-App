"""
check_reference.py <real.pdf> [--margin 27.75]
Sanity-checks a PDF printed from the REAL Chrome print dialog (Save as PDF, user's usual settings)
against the harness assumptions: A4 page size (Chrome: 595.92 x 842.88), 1 cm (27.75pt) margins,
no header/footer. Prints page size, first text x/y (baseline origin) per page and any text that
sits inside the margins (typical of Chrome's default "Headers and footers" option).
"""
import sys
import fitz

EXPECT_W, EXPECT_H = 595.92, 842.88


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    margin = 27.75
    if '--margin' in sys.argv:
        margin = float(sys.argv[sys.argv.index('--margin') + 1])
        args = [a for a in args if a != str(margin) and a != sys.argv[sys.argv.index('--margin') + 1]]
    if not args:
        print(__doc__)
        sys.exit(2)
    doc = fitz.open(args[0])
    print(f"{args[0]}: {len(doc)} page(s)")
    bad = False
    for i, p in enumerate(doc):
        w, h = p.rect.width, p.rect.height
        size_ok = abs(w - EXPECT_W) < 0.5 and abs(h - EXPECT_H) < 0.5
        print(f"\nPage {i + 1}: size {w:.2f} x {h:.2f} pt "
              f"({'matches' if size_ok else 'DIFFERS from'} harness {EXPECT_W} x {EXPECT_H})")
        bad |= not size_ok
        words = p.get_text('rawdict')
        first = None
        margin_hits = []
        for b in words['blocks']:
            for l in b.get('lines', []):
                for s in l['spans']:
                    txt = ''.join(c['c'] for c in s['chars']).strip()
                    if not txt:
                        continue
                    ox, oy = s['chars'][0]['origin']
                    x0, y0, x1, y1 = s['bbox']
                    if first is None or (oy, ox) < (first[1], first[0]):
                        first = (ox, oy, txt)
                    if x0 < margin - 1 or x1 > w - margin + 1 or y0 < margin - 1 or y1 > h - margin + 1:
                        margin_hits.append((x0, y0, x1, y1, txt))
        if first:
            print(f"  first text: x={first[0]:.2f} baseline y={first[1]:.2f}  '{first[2][:40]}'")
            print(f"  (harness expects content left x={margin:.2f}; top text baseline > {margin:.2f})")
        else:
            print("  no text found")
        if margin_hits:
            bad = True
            print(f"  TEXT IN MARGINS ({len(margin_hits)}): probably header/footer or different margins")
            for x0, y0, x1, y1, t in margin_hits[:15]:
                print(f"    [{x0:.1f},{y0:.1f},{x1:.1f},{y1:.1f}] {t[:60]}")
        else:
            print("  no text inside the margins")
        fonts = sorted({f[3] for f in p.get_fonts()})
        print(f"  fonts: {', '.join(fonts)}")
    print("\nRESULT:", "DIFFERS from harness assumptions" if bad else "consistent with harness assumptions")
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
