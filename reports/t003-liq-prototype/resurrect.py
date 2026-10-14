import sys,time,collections,bisect
import os; HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE); sys.path.insert(0,os.path.join(HERE,'..','..','tests'))
import proto_liq
import t003_replay_csv as r
prt=sys.modules['t003_proto']
hdr,bars,_=r.read_csv(sys.argv[1]); p0=r.params_from_header(hdr,{})
cut=bars; n=len(cut)
p=prt.Params(left=p0.left,right=p0.right,period=p0.period,lookback=p0.lookback,rebuild=p0.rebuild,hard_cap=p0.hard_cap)
def T(t): return time.strftime('%Y.%m.%d %H:%M',time.gmtime(t))
def events(variant):
    orig_scope=prt.liq_scope; orig_fc=prt.liq_first_cross
    if variant=='since_scope_entry':
        times=[b.time for b in cut]
        def scope(st,sw,p_,s,at):
            out=orig_scope(st,sw,p_,s,at)
            ent=st.__dict__.setdefault('liq_entered',{})
            for x in out:
                ent.setdefault(x.pivot_time,at)
            return out
        def fc(st,bars_,p_,x,upto):
            ent=st.__dict__.setdefault('liq_entered',{})
            lc=st.__dict__.setdefault('liq_cache',{})
            c0=lc.get(x.pivot_time)
            if c0 and c0[1] is not None: return c0[1]
            s=1 if x.is_high else -1
            e=ent.get(x.pivot_time)
            if e is None: return None
            j0=bisect.bisect_left(times,e)
            cache=st.__dict__.setdefault('liq_cache2',{})
            scanned,first=cache.get(x.pivot_time,(j0-1,None))
            if first is None and scanned<upto:
                for j in range(scanned+1,upto+1):
                    if s*(prt.adverse_ext(bars_[j],s)-x.price)>0: first=j;break
                scanned=upto; cache[x.pivot_time]=(scanned,first)
            return first
        prt.liq_scope=scope; prt.liq_first_cross=fc
        # proto_internal marks consumption in liq_cache directly; make the variant mark liq_cache2 too
    rep=prt.replay(cut,n,p)
    prt.liq_scope=orig_scope; prt.liq_first_cross=orig_fc
    return rep
A=events('history'); B=events('since_scope_entry')
def ie(rep): return collections.Counter((e.type,e.bar_time,e.ref) for e in rep.events if e.type in ('INTERNAL_SWEEP','INTERNAL_BREAK'))
a,b=ie(A),ie(B)
print('history-consumption events:',sum(a.values()),' since-scope-entry events:',sum(b.values()))
extra=b-a; miss=a-b
print('events only with since-scope-entry (would be resurrected/double):',len(extra))
for k in sorted(extra)[:10]: print('  ',k[0],T(k[1]),k[2])
print('events only with history:',len(miss))
