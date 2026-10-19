"""Helper (WP-M port): vector recall/precision prototype (compare.py contains the production version)."""
import fitz, sys
from PIL import Image, ImageChops, ImageFilter
import os, sys as _s
_HERE=os.path.dirname(os.path.abspath(__file__)); _s.path.insert(0,_HERE)
from compare import ALL_FIXTURES
R=os.path.join(_HERE,'..','..','build','report_parity')
FIX=[f for f,_ in ALL_FIXTURES]
DPI=150; S=DPI/72
def gfx_pages(path):
    doc=fitz.open(path)
    out=[]
    for p in doc:
        for b in p.get_text('words'):
            p.add_redact_annot(fitz.Rect(b[:4]))
        p.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE, graphics=fitz.PDF_REDACT_LINE_ART_NONE, text=fitz.PDF_REDACT_TEXT_REMOVE)
        # crop to common A4 at origin
        pix=p.get_pixmap(matrix=fitz.Matrix(S,S),alpha=False, clip=fitz.Rect(0,0,595.0,841.5))
        out.append(Image.frombytes('RGB',[pix.width,pix.height],pix.samples))
    return out
def ink(im):  # non-white pixels mask (L)
    g=im.convert('L'); return g.point(lambda v:255 if v<245 else 0)
def score(a,b,rad):
    ma=ink(a); mb=ink(b)
    db=mb.filter(ImageFilter.MaxFilter(2*rad+1)); da=ma.filter(ImageFilter.MaxFilter(2*rad+1))
    ha=ma.histogram()[255]; hb=mb.histogram()[255]
    rec=ImageChops.logical_and(ma.convert('1'),db.convert('1')).convert('L').histogram()[255]
    pre=ImageChops.logical_and(mb.convert('1'),da.convert('1')).convert('L').histogram()[255]
    return ha,hb,rec,pre
for f in (sys.argv[1:] or FIX):
    W=gfx_pages(f'{R}/web/{f}.pdf'); A=gfx_pages(f'{R}/android/{f}.pdf')
    tot=[0,0,0,0]
    for a,b in zip(W,A):
        s=score(a,b,3)  # 3px @150dpi ~1.44pt
        tot=[x+y for x,y in zip(tot,s)]
    print(f'{f:22} web_ink={tot[0]} and_ink={tot[1]} recall={100*tot[2]/max(tot[0],1):.1f}% precision={100*tot[3]/max(tot[1],1):.1f}%')
