"""floor.py [glyph|span]: best-achievable raster floor, re-typesetting web text in Selawik at Chrome origins."""
# Estimate the physically achievable raster floor: re-typeset every web span with Selawik at the SAME origin, keep web graphics/images.
import fitz, sys
from PIL import Image, ImageChops, ImageFilter
import os, sys as _s
_HERE=os.path.dirname(os.path.abspath(__file__)); _s.path.insert(0,_HERE)
from compare import ALL_FIXTURES
R=os.path.join(_HERE,'..','..','build','report_parity')
FD=os.path.join(_HERE,'..','..','assets','fonts','report')+os.sep
FIX=[f for f,_ in ALL_FIXTURES]
S=150/72
def fontfile(name):
    n=name.split('+')[-1]
    if 'Bold' in n: return FD+'selawkb.ttf','b'
    if 'Semibold' in n: return FD+'selawksb.ttf','sb'
    return FD+'selawk.ttf','r'
def synth(path, mode):
    src=fitz.open(path)
    bg=fitz.open(path)
    for p in bg:
        for w in p.get_text('words'): p.add_redact_annot(fitz.Rect(w[:4]))
        p.apply_redactions(images=fitz.PDF_REDACT_IMAGE_NONE, graphics=fitz.PDF_REDACT_LINE_ART_NONE, text=fitz.PDF_REDACT_TEXT_REMOVE)
    out=fitz.open()
    for i,p in enumerate(src):
        np_=out.new_page(width=p.rect.width,height=p.rect.height)
        np_.show_pdf_page(np_.rect,bg,i)
        for b in p.get_text('rawdict')['blocks']:
            for l in b.get('lines',[]):
                for s in l['spans']:
                    ff,fn=fontfile(s['font']); c=s['color']; col=((c>>16)&255)/255,((c>>8)&255)/255,(c&255)/255
                    if mode=='glyph':  # per-glyph placement = glyph shape difference only
                        for ch in s['chars']:
                            if ch['c'].strip(): np_.insert_text(ch['origin'],ch['c'],fontfile=ff,fontname=fn,fontsize=s['size'],color=col)
                    else:
                        t=''.join(ch['c'] for ch in s['chars'])
                        np_.insert_text(s['origin'],t,fontfile=ff,fontname=fn,fontsize=s['size'],color=col)
    return src,out
def rast(page):
    pix=page.get_pixmap(matrix=fitz.Matrix(S,S),alpha=False,clip=fitz.Rect(0,0,595.0,841.5))
    return Image.frombytes('RGB',[pix.width,pix.height],pix.samples)
def cmp(a,b):
    n=a.width*a.height
    d=ImageChops.difference(a,b).convert('L'); raw=sum(1 for v in d.getdata() if v>32)/n*100
    ba=a.filter(ImageFilter.GaussianBlur(1.5)).convert('L'); bb=b.filter(ImageFilter.GaussianBlur(1.5)).convert('L')
    blur=sum(1 for v in ImageChops.difference(ba,bb).getdata() if v>48)/n*100
    return raw,blur
mode=sys.argv[1] if len(sys.argv)>1 else 'glyph'
for f in FIX:
    src,out=synth(f'{R}/web/{f}.pdf',mode)
    res=[cmp(rast(src[i]),rast(out[i])) for i in range(len(src))]
    print(f'{f:22} mode={mode} raw={sum(r[0] for r in res)/len(res):.2f}% blurred={sum(r[1] for r in res)/len(res):.2f}%  per-page-max raw={max(r[0] for r in res):.2f} blur={max(r[1] for r in res):.2f}')
