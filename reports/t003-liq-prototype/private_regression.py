#!/usr/bin/env python3
"""PRIVATE-DATA regression + comparison (revision 14). Needs the owner's candle CSV (PRIVATE, NOT in the repository).
Usage: python3 private_regression.py <csv>   (no argument / missing file => prints SKIPPED, never PASS)
Compares the IMPLEMENTED model (tests/t003_reference_test.py) with the PROTOTYPE (patched frozen baseline d7a201f)
and with the frozen baseline, as-of 2026.09.26 00:00 and 2026.10.06 00:00 (server time); then checks the 2026.09.25 12:00
sweep chain. The expected chain below are DERIVED FACTS (times, ids) taken from the prototype run, not candles."""
import os, sys, time, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, '..', '..', 'tests'))
if len(sys.argv) < 2 or not os.path.exists(sys.argv[1]):
    print('SKIPPED: no private CSV given (not a pass)')
    sys.exit(0)
import proto_liq  # noqa: F401  (registers t003_proto and t003_baseline)
import t003_replay_csv as r
import t003_reference_test as impl
prt = sys.modules['t003_proto']; base = sys.modules['t003_baseline']
hdr, bars, _ = r.read_csv(sys.argv[1]); p0 = r.params_from_header(hdr, {})
def T(t): return time.strftime('%Y.%m.%d %H:%M', time.gmtime(t))
def run(mod, cut):
    p = mod.Params(left=p0.left, right=p0.right, period=p0.period, lookback=p0.lookback, rebuild=p0.rebuild, hard_cap=p0.hard_cap)
    per = {}
    orig = mod.process_bar
    def pb(t, b, sw, fv, p_, st, tr, ev):
        orig(t, b, sw, fv, p_, st, tr, ev)
        per[t] = (st.dir, st.phase, round(st.lv_price, 2) if st.has_level else None, st.setup_id)
    mod.process_bar = pb
    try:
        rep = mod.replay(cut, len(cut), p)
    finally:
        mod.process_bar = orig
    ev = mod.evaluate(cut, len(cut), p)
    return rep, per, ev
fails = 0
def check(ok, text):
    global fails
    print(('  PASS ' if ok else '  FAIL ') + text)
    if not ok: fails += 1
EXPECT_CHAIN = [  # (time, type, ref prefix) derived from the prototype run on the owner's CSV, as-of 2026.10.06
    ('2026.09.25 12:00', 'INTERNAL_SWEEP', 'IH202609240400'),
    ('2026.09.29 16:00', 'RECONFIRMED', 'F202609280400D'),
    ('2026.09.30 08:00', 'RECONF_LOST', 'F202609280400D'),
    ('2026.09.30 08:00', 'RECONFIRMED', 'F202609280000D')]
for asof in ('2026.09.26 00:00', '2026.10.06 00:00'):
    a = r.parse_server_time(asof); cut = [b for b in bars if b.time + p0.period <= a]
    print('=== as-of', asof, 'bars', len(cut), 'last', T(cut[-1].time))
    R = {n: run(m, cut) for n, m in (('baseline', base), ('proto', prt), ('impl', impl))}
    for n, (rep, per, ev) in R.items():
        c = collections.Counter(e.type for e in rep.events)
        print('  %-8s A/B %s | FLIP %d WICK %d SWEEP %d BREAK %d RECONF %d LOST %d ENDED %d | bars SWEEP_WAIT %d RECONFIRMED %d' % (
            n, ev.flag, c['FLIP'], c['WICK'], c['INTERNAL_SWEEP'], c['INTERNAL_BREAK'], c['RECONFIRMED'], c['RECONF_LOST'], c['SETUP_ENDED'],
            sum(1 for x in per.values() if x[1] == 'SWEEP_WAIT'), sum(1 for x in per.values() if x[1] == 'RECONFIRMED')))
    ri, pi, ei = R['impl']; rp, pp, ep = R['proto']
    key = lambda e: (e.type, e.bar_time, e.ref)
    ki = collections.Counter(key(e) for e in ri.events); kp = collections.Counter(key(e) for e in rp.events)
    check(ki == kp, 'impl events == prototype events by (type, bar, ref): only impl %d, only proto %d' % (len(ki - kp), len(kp - ki)))
    for k in sorted(ki - kp)[:5]: print('     only impl:', k[0], T(k[1]), k[2])
    for k in sorted(kp - ki)[:5]: print('     only proto:', k[0], T(k[1]), k[2])
    dif = [t for t in pp if pp[t] != pi.get(t)]
    check(not dif, 'per-bar (bias, phase, level, setup_id) impl == prototype: %d differing bars' % len(dif))
    if dif: print('     first differing bar', T(cut[dif[0]].time), pp[dif[0]], pi.get(dif[0]))
    check(ei.flag == ep.flag, 'A/B flag impl %s (%s) vs prototype %s (%s)' % (ei.flag, ei.reason, ep.flag, ep.reason))
    pb = R['baseline'][1]
    check(all(pb[t][0] == pi[t][0] for t in pi), 'bias identical to the frozen baseline on every bar (structure untouched)')
    check(sum(1 for e in ri.events if e.type == 'FLIP') == sum(1 for e in R['baseline'][0].events if e.type == 'FLIP'), 'FLIP count equal to the baseline')
    t0 = r.parse_server_time('2026.09.25 12:00')
    check(not [e for e in R['baseline'][0].events if e.bar_time == t0], 'baseline: no event on 2026.09.25 12:00')
    s = [e for e in ri.events if e.bar_time == t0]
    check(len(s) == 1 and s[0].type == 'INTERNAL_SWEEP' and s[0].ref == 'IH202609240400' and 'setup=1' in s[0].detail, 'impl: 2026.09.25 12:00 = INTERNAL_SWEEP of IH202609240400 (4303.22, pivot 09.24 04:00) with a setup')
    ix = [t for t in range(len(cut)) if cut[t].time == t0][0]
    check(pi[ix][1] == 'SWEEP_WAIT' and pi[ix][0] == -1, 'impl: phase SWEEP_WAIT, bias BEAR from that bar; protecting level %s unchanged' % pi[ix][2])
    if asof.startswith('2026.10'):
        sid = pi[ix][3]
        got = [(T(e.bar_time), e.type, e.ref) for e in ri.events if e.type in ('INTERNAL_SWEEP', 'RECONFIRMED', 'RECONF_LOST') and t0 <= e.bar_time <= r.parse_server_time('2026.09.30 12:00')]
        check(got == [x for x in EXPECT_CHAIN], 'chain 09.25 -> 09.30 events %s' % got)
        ids = set(pi[t][3] for t in range(ix, len(cut)) if cut[t].time <= r.parse_server_time('2026.09.30 12:00'))
        check(ids == {sid}, 'one setup_id %s from the sweep through the reconfirmations of 29-30 September' % sid[:34])
print('FAILURES:', fails)
sys.exit(1 if fails else 0)
