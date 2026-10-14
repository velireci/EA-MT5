import sys,time,collections
import os; HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE); sys.path.insert(0,os.path.join(HERE,'..','..','tests'))
import proto_liq
import t003_replay_csv as r
prt=sys.modules['t003_proto']; cur=sys.modules['t003_baseline']   # cur = the model BEFORE revision 14 (frozen baseline)
F=sys.argv[1]
hdr,bars,_=r.read_csv(F)
p0=r.params_from_header(hdr,{})
def T(t): return time.strftime('%Y.%m.%d %H:%M',time.gmtime(t))
def cutasof(s):
    a=r.parse_server_time(s); return [b for b in bars if b.time+p0.period<=a]
def mkp(mod): return mod.Params(left=p0.left,right=p0.right,period=p0.period,lookback=p0.lookback,rebuild=p0.rebuild,hard_cap=p0.hard_cap)
def analyse(mod,cut,label):
    p=mkp(mod); n=len(cut)
    phases=collections.Counter(); per_bar=[]
    orig=mod.process_bar
    def pb(t,b,sw,fv,p_,st,tr,ev):
        orig(t,b,sw,fv,p_,st,tr,ev); per_bar.append((t,st.dir,st.phase))
    mod.process_bar=pb
    rep=mod.replay(cut,n,p)
    mod.process_bar=orig
    evs=rep.events
    ct=collections.Counter(e.type for e in evs)
    ph=collections.Counter(x[2] for x in per_bar if x[1]!=0)
    ended=collections.Counter(e.detail.split('reason=')[-1].split(';')[0] if 'reason=' in e.detail else e.detail[:30] for e in evs if e.type=='SETUP_ENDED')
    ev=mod.evaluate(cut,n,p)
    return dict(label=label,events=evs,counts=ct,phase=ph,ended=ended,flag=ev.flag,reason=ev.reason,n=n,per_bar=per_bar)
for asof in ('2026.09.26 00:00','2026.10.06 00:00'):
    cut=cutasof(asof)
    print('=== as-of',asof,'bars',len(cut),'last',T(cut[-1].time))
    A=analyse(cur,cut,'current'); B=analyse(prt,cut,'proto')
    for X in (A,B):
        print(X['label'],'A/B:',X['flag'],X['reason'])
        print('  events',dict(X['counts']))
        print('  bars by phase',dict(X['phase']),' SETUP_ENDED',dict(X['ended']))
    # differences
    def sigset(X,types): return collections.Counter((e.type,e.bar_time) for e in X['events'] if e.type in types)
    for ty in ('FLIP','BREAK_SET','SEED','WICK','RECONFIRMED','RECONF_LOST','SETUP_ENDED','CONFLICT'):
        sa=sigset(A,(ty,)); sb=sigset(B,(ty,))
        if sa!=sb:
            print(' DIFF',ty,'only current:',[T(k[1]) for k in (sa-sb)][:6],'| only proto:',[T(k[1]) for k in (sb-sa)][:6])
        else:
            print(' same',ty,sum(sa.values()))
    # bias/phase per-bar divergence
    pa={t:(d,ph) for t,d,ph in A['per_bar']}; pb_={t:(d,ph) for t,d,ph in B['per_bar']}
    dif=[t for t in pa if pa[t]!=pb_.get(t)]
    print(' bars where (bias,phase) differs:',len(dif),'first',T(cut[dif[0]].time) if dif else '-','last',T(cut[dif[-1]].time) if dif else '-')
    bd=[t for t in pa if pa[t][0]!=pb_.get(t,(None,))[0]]
    print(' bars where BIAS differs:',len(bd))
    # internal events lists, last 10 of proto
    for X in (A,B):
        ie=[e for e in X['events'] if e.type in ('INTERNAL_SWEEP','INTERNAL_BREAK')]
        print(X['label'],'internal events',len(ie),'sweep',sum(1 for e in ie if e.type=='INTERNAL_SWEEP'),'break',sum(1 for e in ie if e.type=='INTERNAL_BREAK'))
    print(' proto last internal/sweep-setup events:')
    for e in [e for e in B['events'] if e.type in ('INTERNAL_SWEEP','INTERNAL_BREAK')][-6:]:
        print('   ',T(e.bar_time),e.type,e.ref,e.detail[-60:])
    # 25.09 12:00
    t0=r.parse_server_time('2026.09.25 12:00')
    for X in (A,B):
        es=[(e.type,e.ref) for e in X['events'] if e.bar_time==t0]
        print(X['label'],'events at 2026.09.25 12:00:',es)
