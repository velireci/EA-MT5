import sys,time
import os; HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE); sys.path.insert(0,os.path.join(HERE,'..','..','tests'))
import proto_liq
prt=sys.modules['t003_proto']; import t003_reference_test as cur
def build(cross, after=None):
    s=prt.bear_leg().to(100).to(88).to(60).to(95).to(70).to(85).to(72)
    s.pts([71,70])
    base=s.n()
    s.bar(*cross)
    for x in (after or []): s.bar(*x)
    s.pts([80,79,78])
    return s,base
def run(mod,s):
    bars=s.bars(); n=len(bars)
    p=mod.Params(left=2,right=2,period=mod.PERIOD,lookback=300,rebuild=1000,hard_cap=5000)
    lv={}
    orig=mod.process_bar
    def pb(t,b,sw,fv,p_,st,tr,ev):
        orig(t,b,sw,fv,p_,st,tr,ev); lv[t]=(st.dir,st.phase,st.lv_price if st.has_level else None,getattr(st,'liq_key','-'))
    mod.process_bar=pb
    rep=mod.replay(bars,n,p)
    mod.process_bar=orig
    return bars,rep,lv
def show(title,cross,after=None):
    print('---',title)
    for name,mod in (('current',cur),('proto',prt)):
        s,base=build(cross,after)
        bars,rep,lv=run(mod,s)
        evs=[e for e in rep.events if e.bar_time>=bars[base-1].time]
        print(' ',name,'bar',base,'cross row',cross,'| state before:',lv[base-1][:3],'liq_key:',lv[base-1][3])
        for e in evs:
            k=int((e.bar_time-bars[0].time)//(4*3600))
            print('    bar',k,e.type,e.ref,e.detail[:70])
        print('    state after crossing bar:',lv[base][:3],'liq_key:',lv[base][3])
# the highs: level 105, interior swing highs 100 (pivot after LL) and 90
show('S2 close breaks the LOWER interior level 90, wick sweeps the HIGHER 100 (high 103 < level 105)',(103,88,95))
show('S3a touch is not a crossing: high == 100 exactly, close 95 (breaks 90 only)',(100,88,95),[(100.5,88,96)])
show('S3b protecting-level touch: high == 105 exactly (no structural wick), close 95',(105,88,95))
show('S3c strictly beyond the protecting level 105: structural WICK, interior levels not given INTERNAL_*',(106,88,95))
