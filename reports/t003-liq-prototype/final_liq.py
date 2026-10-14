import sys,time,collections
import os; HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE); sys.path.insert(0,os.path.join(HERE,'..','..','tests'))
import proto_liq
import t003_replay_csv as r
prt=sys.modules['t003_proto']; cur=sys.modules['t003_baseline']   # cur = the model BEFORE revision 14 (frozen baseline)
hdr,bars,_=r.read_csv(sys.argv[1]); p0=r.params_from_header(hdr,{})
def T(t): return time.strftime('%Y.%m.%d %H:%M',time.gmtime(t))
for asof in ('2026.09.26 00:00','2026.10.06 00:00'):
    a=r.parse_server_time(asof); cut=[b for b in bars if b.time+p0.period<=a]; n=len(cut)
    print('== as-of',asof)
    for name,mod in (('current',cur),('proto',prt)):
        p=mod.Params(left=p0.left,right=p0.right,period=p0.period,lookback=p0.lookback,rebuild=p0.rebuild,hard_cap=p0.hard_cap)
        rep=mod.replay(cut,n,p); st=rep.state
        sweeps=[e for e in rep.events if e.type=='INTERNAL_SWEEP']
        made=sum(1 for e in sweeps if ('setup=1' in e.detail) or (name=='current'))
        pass
        print(' ',name,'final: bias',st.dir,'phase',st.phase,'level %.2f'%st.lv_price,'setup',st.setup_id[:40],'| sweeps',len(sweeps),'setups from sweeps',made,'| rec/lost',sum(1 for e in rep.events if e.type=='RECONFIRMED'),sum(1 for e in rep.events if e.type=='RECONF_LOST'))
        ev=mod.evaluate(cut,n,p); print('     evaluate:',ev.flag,ev.reason)
