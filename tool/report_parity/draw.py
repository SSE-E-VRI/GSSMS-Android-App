"""Helper (WP-M port): legacy normalised drawing matcher (diagnostic only; compare.py vector metric supersedes)."""
import fitz, collections, sys
import os, sys as _s
_HERE=os.path.dirname(os.path.abspath(__file__)); _s.path.insert(0,_HERE)
from compare import ALL_FIXTURES
R=os.path.join(_HERE,'..','..','build','report_parity')
FIX=[f for f,_ in ALL_FIXTURES]
def norm(d):
    out=[]
    for x in d:
        r=fitz.Rect(x['rect']); w=x.get('width') or 0
        fill=x.get('fill'); col=x.get('color')
        if x['type']=='f' and fill and all(c>0.995 for c in fill): continue  # white bg
        if x['type'] in ('s','fs') and w: r=fitz.Rect(r.x0-w/2,r.y0-w/2,r.x1+w/2,r.y1+w/2)
        c = col if x['type']=='s' else (fill if x['type']=='f' else col)
        out.append((r,tuple(round(v*255) for v in (c or (0,0,0))),x['type'],x))
    return out
def match(W,A,tol=1.5,ctol=16):
    used=set(); m=0; unmatched=[]
    for r,c,t,x in W:
        hit=False
        for i,(r2,c2,t2,x2) in enumerate(A):
            if i in used: continue
            if max(abs(r.x0-r2.x0),abs(r.y0-r2.y0),abs(r.x1-r2.x1),abs(r.y1-r2.y1))<=tol and max(abs(a-b) for a,b in zip(c,c2))<=ctol:
                used.add(i); m+=1; hit=True; break
        if not hit: unmatched.append((r,c,t))
    return m,unmatched
for f in (sys.argv[1:] or FIX):
    dw=fitz.open(f'{R}/web/{f}.pdf'); da=fitz.open(f'{R}/android/{f}.pdf')
    tw=ta=mw=0; allw=0; types=collections.Counter(); typesA=collections.Counter(); um=[]
    loose=0
    for p in range(min(len(dw),len(da))):
        rw=dw[p].get_drawings(); ra=da[p].get_drawings(); allw+=len(rw)
        W=norm(rw); A=norm(ra); tw+=len(W); ta+=len(A)
        types.update((t,len(x['items'])) for _,_,t,x in W); typesA.update((t,len(x['items'])) for _,_,t,x in A)
        m,u=match(W,A); mw+=m; um+=[(p+1,)+q for q in u]
        m2,_=match(W,A,tol=6,ctol=255); loose+=m2
    print(f'{f:22} web_all={allw} web_nonwhite={tw} and={ta} matched(1.5pt,colour)={mw} ({100*mw/max(tw,1):.0f}%) loose(6pt,anycolour)={loose} ({100*loose/max(tw,1):.0f}%)')
    print('   web types',dict(types.most_common(6)),' and types',dict(typesA.most_common(6)))
    for q in um[:6]: print('   unmatched',q[0],[round(v,1) for v in q[1]],q[2],q[3])
