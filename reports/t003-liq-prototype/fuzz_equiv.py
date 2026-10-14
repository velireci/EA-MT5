"""Random-series equivalence: the isolated prototype (proto_liq.py, patched baseline d7a201f) versus the
implementation in tests/t003_reference_test.py (revision 14). Synthetic random walks with wide wicks (no market
data). Compared per bar: bias, phase, protecting level price, setup id, the unconsumed-set key; and every event
(type, bar, ref, detail without restart=). Usage: python3 reports/t003-liq-prototype/fuzz_equiv.py [seeds] [bars]"""
import os, random, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', '..', 'tests'))
import proto_liq  # noqa: F401  (registers t003_proto and t003_baseline)
prt = sys.modules['t003_proto']
import t003_reference_test as impl

def series(seed, n):
    rnd = random.Random(seed)
    c = 100.0
    rows = []
    for i in range(n):
        c += rnd.uniform(-6, 6)
        hw = rnd.uniform(0.5, 7)
        rows.append((c + hw * rnd.uniform(0.2, 1.6), c - hw * rnd.uniform(0.2, 1.6), c + rnd.uniform(-hw, hw) * 0.8))
    out = []
    for i, (h, l, cl) in enumerate(rows):
        h = max(h, cl); l = min(l, cl)
        out.append(impl.Bar(impl.T0 + i * impl.PERIOD, round(h, 2), round(l, 2), round(cl, 2)))
    return out

def run(mod, bars):
    p = mod.Params(left=2, right=2, period=mod.PERIOD, lookback=300, rebuild=1000, hard_cap=5000)
    per = []
    orig = mod.process_bar
    def pb(t, b, sw, fv, p_, st, tr, ev):
        orig(t, b, sw, fv, p_, st, tr, ev)
        per.append((st.dir, st.phase, st.lv_price if st.has_level else None, st.setup_id,
                    getattr(st, 'liq_key', getattr(st, 'li_key', '-'))))
    mod.process_bar = pb
    try:
        rep = mod.replay(bars, len(bars), p)
    finally:
        mod.process_bar = orig
    evs = [(e.type, e.bar_time, e.ref, ';'.join(x for x in e.detail.split(';') if not x.startswith('restart='))) for e in rep.events]
    return per, evs

def main():
    seeds = int(sys.argv[1]) if len(sys.argv) > 1 else 40
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 400
    bad = 0
    tot_ev = tot_sw = 0
    for sd in range(seeds):
        bars = series(sd, n)
        a = run(prt, bars)
        b = run(impl, bars)
        tot_ev += len(b[1])
        tot_sw += sum(1 for e in b[1] if e[0] == 'INTERNAL_SWEEP')
        if a != b:
            bad += 1
            print('DIFFER seed', sd)
    print('FUZZ: %d series x %d bars, %d events (%d INTERNAL_SWEEP), %d series differ' % (seeds, n, tot_ev, tot_sw, bad))
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
