"""Helper (WP-M port): see compare.py --ledger. Standalone drift ledger / font-width ratios by baseline."""
import fitz, difflib, sys, math, collections, statistics
import os, sys as _s
_HERE=os.path.dirname(os.path.abspath(__file__)); _s.path.insert(0,_HERE)
from compare import ALL_FIXTURES
R=os.path.join(_HERE,'..','..','build','report_parity')
FIX=[f for f,_ in ALL_FIXTURES]
def words(doc):
    """words with baseline origin of first char, end x of last char advance, font, size"""
    out=[]
    for pn,p in enumerate(doc):
        d=p.get_text('rawdict')
        for b in d['blocks']:
            for l in b.get('lines',[]):
                for s in l['spans']:
                    cur=[]
                    for ch in s['chars']+[None]:
                        if ch is None or ch['c'].isspace():
                            if cur:
                                t=''.join(c['c'] for c in cur)
                                out.append(dict(p=pn,t=t,x=cur[0]['origin'][0],y=cur[0]['origin'][1],x1=cur[-1]['bbox'][2],font=s['font'].split('+')[-1],size=s['size'],color=s['color']))
                            cur=[]
                        else: cur.append(ch)
    return out
NAMEMAP={'SegoeUI':'R','Selawik-Regular':'R','SegoeUI-Semibold':'SB','Selawik-Semibold':'SB','SegoeUI-Bold':'B','Selawik-Bold':'B','SegoeUI-Italic':'I','SegoeUI-SemiboldItalic':'SBI'}
sel=[a for a in sys.argv[1:] if not a.startswith('-')] or FIX
N=int(([a for a in sys.argv if a.startswith('-n')] or ['-n15'])[0][2:])
agg=collections.defaultdict(list)
for f in sel:
    W=fitz.open(f'{R}/web/{f}.pdf'); A=fitz.open(f'{R}/android/{f}.pdf')
    ww=words(W); aw=words(A)
    sm=difflib.SequenceMatcher(None,[w['t'] for w in ww],[w['t'] for w in aw],autojunk=False)
    pairs=[]
    for tag,i1,i2,j1,j2 in sm.get_opcodes():
        if tag=='equal': pairs+=[(ww[i1+k],aw[j1+k]) for k in range(i2-i1)]
        else: print(f'  [{tag}] web={[w["t"] for w in ww[i1:i2]][:10]} and={[w["t"] for w in aw[j1:j2]][:10]}')
    ds=[]
    print(f'===== {f}: web {len(ww)} and {len(aw)} matched {len(pairs)}')
    prev=None; jumps=[]; fontdiff=collections.Counter()
    for i,(a,b) in enumerate(pairs):
        dx=b['x']-a['x']; dy=b['y']-a['y'] if a['p']==b['p'] else float('nan')
        if a['p']==b['p']: ds.append(math.hypot(dx,dy))
        wa=a['x1']-a['x']; wb=b['x1']-b['x']; wr=wb/wa if wa>0 else 0
        fa=NAMEMAP.get(a['font'],a['font']); fb=NAMEMAP.get(b['font'],b['font'])
        if fa!=fb or abs(a['size']-b['size'])>0.05: fontdiff[(a['t'][:14],fa,round(a['size'],2),fb,round(b['size'],2))]+=1
        if wa>3 and fa==fb: agg[(fa,len(a['t'])>1)].append(wr)
        if i<N: print(f'  {i:3} p{a["p"]+1} {a["t"][:16]:16} {fa}/{a["size"]:.2f} vs {fb}/{b["size"]:.2f} web({a["x"]:6.1f},{a["y"]:6.1f}) and({b["x"]:6.1f},{b["y"]:6.1f}) dx={dx:+5.1f} dy={dy:+5.1f} w%={wr:.3f}')
        if prev is not None and not math.isnan(dy) and abs(a['y']-prev[2])>0.5 and abs(dy-prev[1])>0.6:
            jumps.append((i,a['t'][:14],f"p{a['p']+1}",round(a['y'],1),f"{prev[1]:+.2f}->{dy:+.2f}",f"step {dy-prev[1]:+.2f}"))
        if not math.isnan(dy): prev=(a['t'],dy,a['y'])
    ds.sort()
    if ds: print(f'  BASELINE delta p50={ds[len(ds)//2]:.2f} p95={ds[int(len(ds)*.95)]:.2f} max={ds[-1]:.2f}')
    print('  font/size diffs:', list(fontdiff.items())[:12])
    print('  vertical steps (where android baseline offset changes):')
    for j in jumps[:30]: print('   ',j)
print('WIDTH RATIOS android/web by font:')
for k,v in sorted(agg.items()):
    v.sort(); print('  ',k,len(v),'median',round(v[len(v)//2],4),'p5',round(v[int(len(v)*.05)],3),'p95',round(v[int(len(v)*.95)],3))
