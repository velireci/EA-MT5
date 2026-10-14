#!/usr/bin/env python3
"""T003 DIAGNOSTIC: which swing is the PROTECTING level? (SYNTHETIC generic units, model only).

NOT PRODUCT, NOT A TEST OF THE PRODUCT, NOT A CLIENT RULE. This script does not change or replace
anything in tests/t003_reference_test.py / src/include/H4Bias.mqh; it only IMPORTS the Python model.

Two mechanisms are compared on the same synthetic closed H4 bars (generic units, no real price,
no real candle, no photo value):

  (A) the CURRENT model: tests/t003_reference_test.py `replay` (P2 pair level + revision 10 ratchet).
      The real functions are called, nothing is modified.
  (B) 'diagnostic variant, not product': the protecting level is the LATEST confirmed 2/2 lower high
      (bearish bias) / higher low (bullish bias), at the moment it is confirmed. Implemented ONLY here.
      Rules of B (all causal):
        * B starts with the bias direction and bar at which (A) seeds its first bias (same seed, so
          that the comparison concerns the LEVEL, not the start-up).
        * after the close of bar t, level_B = the latest swing high h (bearish) / swing low (bullish)
          that is confirmed by the close of t (pivot index + 2 <= t), is lower (higher) than the
          previous confirmed swing of its kind, and has not been closed through by a body close in
          (pivot, t]. No such swing -> no level.
        * bar t is judged against the level_B known after bar t-1: a close strictly beyond it flips the
          direction (FLIP); a high/low beyond it with the close inside is a WICK (no flip).
        * after a flip the new direction takes its own level by the same rule.
The goal is NOT convergence or profit: it is to show, bar by bar, where (A) and (B) differ, so that the
differences can be compared with the client's recorded statements (reports/T003-verification.md
section 18). Output counts at the end are real counts of the checks in THIS script.

Usage:  python3 tests/t003_structural_level_diag.py [--quiet]     (--quiet: summary table only)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t003_reference_test as m  # noqa: E402  (imported, never modified)

QUIET = '--quiet' in sys.argv
T0 = m.T0
PERIOD = m.PERIOD
BULL, BEAR = m.BULL, m.BEAR
RIGHT = 2

PASS = 0
FAIL = 0


def check(cond, label):
    global PASS, FAIL
    if cond:
        PASS += 1
        print('  PASS: %s' % label)
    else:
        FAIL += 1
        print('  FAIL: %s' % label)


def out(s=''):
    if not QUIET:
        print(s)


def idx_of(t):
    return (t - T0) // PERIOD


def tshort(i):
    return '%d(%s)' % (i, m.ts(T0 + i * PERIOD))


def pf(x):
    return '%.2f' % x


# ---------------------------------------------------------------- (B) -----
def b_candidate(sw, nk, d, bars, t):
    """(B) diagnostic variant: latest confirmed LH (d=-1) / HL (d=+1) not closed through"""
    want_high = (d < 0)
    seq = [s for s in sw[:nk] if s.is_high == want_high]
    cand = None
    for j in range(len(seq) - 1, 0, -1):
        if (d < 0 and seq[j].price < seq[j - 1].price) or (d > 0 and seq[j].price > seq[j - 1].price):
            cand = seq[j]
            break
    if cand is None:
        return None
    if m.close_beyond_any(bars, cand.index + 1, t, cand.price, -d):
        return None
    return cand


class BRec(object):
    def __init__(self):
        self.dir = 0
        self.lvl = None      # swing
        self.events = []


def run_b(bars, sw, start_t, start_dir):
    n = len(bars)
    recs = []
    d = 0
    lvl = None
    for t in range(n):
        r = BRec()
        if t == start_t:
            d = start_dir
        elif t > start_t and d != 0:
            s = -d
            if lvl is not None:
                P = lvl.price
                if s * (bars[t].close - P) > 0:
                    r.events.append('FLIP->%s' % m.dir_name(-d))
                    d = -d
                elif s * (m.adverse_ext(bars[t], s) - P) > 0:
                    r.events.append('WICK')
        if d != 0:
            nk = m.known_count(sw, RIGHT, t)
            lvl = b_candidate(sw, nk, d, bars, t)
        r.dir = d
        r.lvl = lvl
        recs.append(r)
    return recs


# ------------------------------------------- SP1 classification (text) ----
def sp1_verdict(bars, sw, nk, d, t, h):
    """Explains, at the close of bar t, whether swing `h` (a swing high for d=-1, a swing low for d=+1)
    is STRUCTURAL by the proposal SP1 (= the P2 pair condition stated as the promotion rule) or LOCAL.
    Returns (is_structural, text). Only swings confirmed by t (the first nk) are used."""
    lvl_is_high = (d < 0)
    kind = [s for s in sw[:nk] if s.is_high == lvl_is_high]
    other = [s for s in sw[:nk] if s.is_high != lvl_is_high]
    k = kind.index(h)
    nm = 'LH' if d < 0 else 'HL'
    # informational label only: P2 does NOT require the level to be a LH/HL relative to the previous swing
    # of its kind (the highest high between two lows may even be higher than the high before them)
    label = 'first of its kind'
    if k > 0:
        prev = kind[k - 1]
        label = ('%s (vs bar %d)' % (nm, prev.index)) if ((d < 0 and h.price < prev.price) or (d > 0 and h.price > prev.price)) \
            else ('not a %s (vs bar %d)' % (nm, prev.index))
    cons = -1
    for i in range(h.index + 1, t + 1):
        if -d * (bars[i].close - h.price) > 0:
            cons = i
            break
    if cons >= 0:
        return False, 'CONSUMED: a body close beyond it at bar %d (already judged by the machine)' % cons
    before = [s for s in other if s.pivot_time < h.pivot_time]
    after = [s for s in other if s.pivot_time > h.pivot_time]
    if not before:
        return False, 'LOCAL: no confirmed %s before it (%s)' % ('low' if lvl_is_high else 'high', label)
    if not after:
        return False, 'LOCAL: no confirmed %s after it yet (known by bar %d): the reaction is not confirmed [%s]' % (
            'low' if lvl_is_high else 'high', t, label)
    lb, la = before[-1], after[0]
    if not ((d < 0 and la.price < lb.price) or (d > 0 and la.price > lb.price)):
        return False, 'LOCAL: the next confirmed %s after it (bar %d, %s) is not %s than the one before it (bar %d, %s): no %s [%s]' % (
            'low' if lvl_is_high else 'high', la.index, pf(la.price), 'lower' if d < 0 else 'higher',
            lb.index, pf(lb.price), 'LL' if d < 0 else 'HH', label)
    between = [s for s in kind if lb.pivot_time < s.pivot_time < la.pivot_time]
    best = None
    for s in between:
        if best is None or d * s.price < d * best.price:
            best = s
    if best is not h:
        return False, 'LOCAL: not the %s %s between the two %ss (bar %d %s and bar %d %s): bar %d (%s) is [%s]' % (
            'highest' if d < 0 else 'lowest', 'high' if d < 0 else 'low', 'low' if d < 0 else 'high',
            lb.index, pf(lb.price), la.index, pf(la.price), best.index, pf(best.price), label)
    use = max(h.index + RIGHT, la.index + RIGHT) + 1
    return True, 'STRUCTURAL: the %s %s between the %ss at bars %d (%s) and %d (%s), the second being a %s; usable from bar %d [%s]' % (
        'highest' if d < 0 else 'lowest', 'high' if d < 0 else 'low', 'low' if d < 0 else 'high',
        lb.index, pf(lb.price), la.index, pf(la.price), 'LL' if d < 0 else 'HH', use, label)


# ----------------------------------------------------------- one case -----
def t2short(sw, nk):
    r = m.t2_dir_name(sw, nk)
    return {'BULLISH': 'HH/HL', 'BEARISH': 'LH/LL', 'MIXED': 'MIXED'}.get(r, 'UNK')


class Res(object):
    pass


def analyse(name, bars, show):
    """runs (A) on every prefix is NOT needed: (A) is one causal replay; a prefix self-check is done on a
    subset of bars. Returns Res with flips and per-bar records."""
    n = len(bars)
    p = m.Params(lookback=300, rebuild=1000)
    rep = m.replay(bars, n, p)
    sw, _ = m.t2.find_swings(bars, n, 2, 2, PERIOD)
    hist = rep.hist
    start_t = -1
    start_dir = 0
    for t in range(n):
        if hist[t][0] != 0:
            start_t = t
            start_dir = hist[t][0]
            break
    brec = run_b(bars, sw, start_t, start_dir) if start_t >= 0 else [BRec() for _ in range(n)]
    ev_by_bar = {}
    for e in rep.events:
        ev_by_bar.setdefault(idx_of(e.bar_time), []).append(e)
    r = Res()
    r.n = n
    r.bars = bars
    r.rep = rep
    r.sw = sw
    r.hist = hist
    r.brec = brec
    r.start_t = start_t
    r.start_dir = start_dir
    r.ev = ev_by_bar
    r.a_flips = [(idx_of(e.bar_time), m.dir_name(-1 if 'dir=BEAR' in e.detail else 1)) for e in rep.events if e.type == m.EV_FLIP]
    r.b_flips = [(t, e.split('->')[1]) for t in range(n) for e in brec[t].events if e.startswith('FLIP')]
    r.a_wicks = [idx_of(e.bar_time) for e in rep.events if e.type == m.EV_WICK]
    r.b_wicks = [t for t in range(n) for e in brec[t].events if e == 'WICK']
    r.t2 = [t2short(sw, m.known_count(sw, RIGHT, t)) for t in range(n)]
    return r


def a_level(r, t):
    h = r.hist[t]
    if h[0] != 0 and h[4]:
        return h[5]
    return None


def a_level_text(r, t):
    h = r.hist[t]
    if h[0] == 0:
        return '-'
    if not h[4]:
        return 'none'
    return pf(h[5])


def b_level_text(r, t):
    b = r.brec[t]
    if b.dir == 0:
        return '-'
    if b.lvl is None:
        return 'none'
    return '%s@%d' % (pf(b.lvl.price), b.lvl.index)


def a_level_pivot(r, t):
    """the swing behind (A)'s level after bar t. Identified by the pivot TIME in the state of a prefix replay
    (never by price: two swings may have the same price). Cached; the prefix replay is made only where the
    level changed."""
    if not hasattr(r, 'alv'):
        r.alv = {}
    if t in r.alv:
        return r.alv[t]
    h = r.hist[t]
    if h[0] == 0 or not h[4]:
        r.alv[t] = None
        return None
    if t > 0 and r.hist[t - 1][0] == h[0] and r.hist[t - 1][4] and r.hist[t - 1][5] == h[5]:
        r.alv[t] = a_level_pivot(r, t - 1)
        return r.alv[t]
    rp = m.replay(r.bars[:t + 1], t + 1, m.Params(lookback=300, rebuild=1000))
    pt = rp.state.lv_pivot
    nk = m.known_count(r.sw, RIGHT, t)
    c = [s for s in r.sw[:nk] if s.pivot_time == pt and s.is_high == (h[0] < 0)]
    r.alv[t] = c[0] if c else None
    return r.alv[t]


def print_case(name, side, desc, r):
    out('')
    out('=== CASE %s [%s] %s ===' % (name, side, desc))
    out('bars: %d, absolute time of bar i = 2026-01-05 00:00 + i*4h (bar 0 = %s, last = %s)' % (
        r.n, m.ts(T0), tshort(r.n - 1)))
    out('swings (2/2, confirmed when pivot+2 bars have closed; usable from the bar after the confirming close):')
    prev = {True: None, False: None}
    for s in r.sw:
        cls = ''
        pv = prev[s.is_high]
        if pv is not None:
            if s.is_high:
                cls = 'HH' if s.price > pv.price else ('EQ' if s.price == pv.price else 'LH')
            else:
                cls = 'HL' if s.price > pv.price else ('EQ' if s.price == pv.price else 'LL')
        prev[s.is_high] = s
        out('  bar %3d %s %s %-2s pivot=%s confirmed at close of bar %d (%s) usable from bar %d' % (
            s.index, 'H' if s.is_high else 'L', pf(s.price), cls, m.ts(s.pivot_time), s.index + RIGHT,
            m.ts(s.confirm_time), s.index + RIGHT + 1))
    out('first bias of (A) (seed): ' + ('bar %d dir=%s (B starts at the same bar)' % (r.start_t, m.dir_name(r.start_dir))
                                         if r.start_t >= 0 else 'none'))
    out('timeline (state AFTER the close of the bar; level = used for the NEXT bar; only changing bars):')
    last_a = None
    last_b = None
    last_t2 = None
    for t in range(r.n):
        b = bars_row = r.bars[t]
        a_ev = [e for e in r.ev.get(t, []) if e.type in (m.EV_FLIP, m.EV_WICK, m.EV_INT_SWEEP, m.EV_INT_BREAK,
                                                          m.EV_SEED, m.EV_CONTINUATION, m.EV_SETUP_ENDED)]
        b_ev = r.brec[t].events
        a_state = (m.dir_name(r.hist[t][0]), a_level_text(r, t), r.hist[t][1])
        b_state = (m.dir_name(r.brec[t].dir) if r.brec[t].dir else '-', b_level_text(r, t))
        newsw = [s for s in r.sw if s.index + RIGHT == t]
        changed = (a_state != last_a) or (b_state != last_b) or (r.t2[t] != last_t2)
        if a_ev or b_ev or newsw or changed or t == r.n - 1:
            conf = ' '.join('conf:%s%s@%d' % ('H' if s.is_high else 'L', pf(s.price), s.index) for s in newsw)
            aev = ','.join(e.type + ('' if e.type != m.EV_FLIP else '') for e in a_ev)
            out('  t=%3d %s H=%s L=%s C=%s | T002 %-5s | A %-4s lvl=%-7s %-9s ev=%-22s | B %-4s lvl=%-10s ev=%-10s %s' % (
                t, m.ts(b.time)[2:], pf(b.high), pf(b.low), pf(b.close), r.t2[t], a_state[0], a_state[1], a_state[2],
                aev or '-', b_state[0], b_state[1], ','.join(b_ev) or '-', conf))
        last_a, last_b, last_t2 = a_state, b_state, r.t2[t]
    out('why a local swing is accepted or rejected (rule SP1 text) at the moments where a level appears:')
    seen = set()
    for t in range(r.n):
        d = r.hist[t][0]
        if d == 0:
            continue
        nk = m.known_count(r.sw, RIGHT, t)
        bl = r.brec[t].lvl
        if bl is not None and (t, 'B') not in seen and (t == 0 or r.brec[t - 1].lvl is None or r.brec[t - 1].lvl is not bl):
            seen.add((t, 'B'))
            if r.brec[t].dir == d:
                ok, tx = sp1_verdict(r.bars, r.sw, nk, d, t, bl)
                out('  t=%d B takes swing bar %d (%s): SP1 says -> %s' % (t, bl.index, pf(bl.price), tx))
        al = a_level_pivot(r, t)
        if al is not None and (t == 0 or a_level_pivot(r, t - 1) is not al):
            ok, tx = sp1_verdict(r.bars, r.sw, nk, d, t, al)
            out('  t=%d A takes swing bar %d (%s): SP1 says -> %s' % (t, al.index, pf(al.price), tx))
    t = r.n - 1
    d = r.hist[t][0]
    if d != 0:
        nk = m.known_count(r.sw, RIGHT, t)
        out('classification of every confirmed level-type swing at the as-of bar t=%d:' % t)
        for s in [x for x in r.sw[:nk] if x.is_high == (d < 0)]:
            ok, tx = sp1_verdict(r.bars, r.sw, nk, d, t, s)
            mark = ''
            al = a_level_pivot(r, t)
            if al is s:
                mark += ' <== (A) level'
            bl = r.brec[t].lvl
            if bl is s:
                mark += ' <== (B) level'
            out('  bar %3d %s: %s%s' % (s.index, pf(s.price), tx, mark))
    out('SUMMARY %s: A flips %s | B flips %s | A wicks %s | B wicks %s | as-of: A lvl %s, B lvl %s, T002 %s' % (
        name, r.a_flips, r.b_flips, r.a_wicks, r.b_wicks, a_level_text(r, r.n - 1), b_level_text(r, r.n - 1), r.t2[r.n - 1]))


# ------------------------------------------------------------- cases ------
def pre_owner():
    """generic-unit mirror of the owner's evidence: highs 125 -> 95, lows 75 -> 55 (two lows, a LL;
    the high 125 between them; the later LH 95 is not yet in a P2 pair). H0 135 precedes."""
    return m.Series(100).to(130).to(80).to(120).to(60).to(90)


def c_k1():
    return pre_owner().to(72).bars()


def c_k2():
    s = pre_owner().to(72).to(112)
    m.pad(s, 6)
    return s.bars()


def c_k3():
    s = pre_owner().to(72).to(135)
    m.pad(s, 4)
    return s.bars()


def c_k4():
    s = pre_owner().to(78)
    s.bar(99, 84, 90)        # high 99 > 95 (the LH), close 90 < 95: wick only
    s.c = 90
    s.to(70)
    m.pad(s, 4)
    return s.bars()


def c_k5():
    s = pre_owner().to(78)
    s.bar(130, 82, 85)       # high 130 > 125 (the structural level), close 85 inside
    s.c = 85
    s.to(66)
    m.pad(s, 4)
    return s.bars()


def c_k5b():
    s = pre_owner().to(78)
    s.bar(130, 82, 85)       # wick over 125, close inside
    s.bar(132, 120, 128)     # next bar: body close beyond 125
    s.c = 128
    m.pad(s, 4)
    return s.bars()


def c_k6a():
    # small correction INSIDE the structure, then a rally that closes above it BEFORE the next low forms
    s = m.Series(100).to(130).to(95).to(120).to(85).to(100).to(88).to(108).to(60)
    m.pad(s, 4)
    return s.bars()


def c_k6b():
    # the same bounce, the decline continues (a LL2 follows): the bounce becomes part of a P2 pair
    s = m.Series(100).to(130).to(95).to(120).to(85).to(100).to(60).to(78)
    m.pad(s, 2)
    return s.bars()


def c_k6c():
    # as-of the bar where the bounce LH is confirmed and nothing else is known yet
    s = m.Series(100).to(130).to(95).to(120).to(85).to(100).to(88)
    return s.bars()


def c_k7a():
    # structural correction: LL, counter-leg to a LH (110), a pullback that forms a HL (65 > 55), a rally closing above the LH
    s = m.Series(100).to(130).to(80).to(120).to(60).to(105).to(70).to(115)
    m.pad(s, 4)
    return s.bars()


def c_k7b():
    s = m.Series(100).to(130).to(80).to(120).to(60).to(105).to(70).to(115).to(70).to(135)
    m.pad(s, 4)
    return s.bars()


def c_k7c():
    # the counter-leg's LH (110) is followed by a NEW lower low (45): the LH joins a P2 pair
    s = m.Series(100).to(130).to(80).to(120).to(60).to(105).to(50).to(112)
    m.pad(s, 4)
    return s.bars()


CASES = [
    ('K1', 'owner-mirror: LL (75->55), high 125 between the lows, later LH 95 (not yet in a P2 pair); as-of at the LH+3', c_k1),
    ('K2', 'K1 then a rally whose BODY closes at 112: above the LH 95, below the structural 125', c_k2),
    ('K3', 'K1 then a rally whose BODY closes at 135: above the structural 125 as well', c_k3),
    ('K4', 'K1 then a WICK over the LH only (high 99, close 90), then the decline continues', c_k4),
    ('K5', 'K1 then a WICK over the structural 125 only (high 130, close 85), then the decline continues', c_k5),
    ('K5b', 'K5 and the NEXT bar closes (BODY) at 128 above 125', c_k5b),
    ('K6c', 'small correction inside the structure: bounce LH 105 just confirmed (LL1 80 known, LL2 not yet)', c_k6c),
    ('K6a', 'K6 then the bounce high is closed through (112) BEFORE a new low, then LL2', c_k6a),
    ('K6b', 'K6 then the decline continues to LL2 (55): the bounce LH joins a P2 pair', c_k6b),
    ('K7a', 'structural correction: LL 55 -> LH 110 -> HL 65 -> rally closing 115 (below the structural 125)', c_k7a),
    ('K7b', 'K7a then the rally continues to a close 135 (above 125)', c_k7b),
    ('K7c', 'LL 55 -> LH 110 -> NEW LL 45 -> rally closing 112 (the LH joined a P2 pair)', c_k7c),
]


MIRROR_AT = 200.0     # generic mirror axis (price -> 200 - price); keeps the BUY cases in generic units


def mirror_bars(bars):
    return m.t2.mirror(bars, MIRROR_AT)


def flips_signature(fl):
    return [(t, 'BULL' if d == 'BEAR' else 'BEAR') for (t, d) in fl]


def main():
    global PASS, FAIL
    results = {}
    print('T003 structural-level DIAGNOSTIC (SYNTHETIC generic units; model only; variant B is NOT product)')
    print('Mechanism A = tests/t003_reference_test.py replay (P2 pair + ratchet); B = latest confirmed LH/HL (diagnostic).')
    for name, desc, fn in CASES:
        bars = fn()
        r = analyse(name, bars, True)
        results[(name, 'SELL')] = r
        print_case(name, 'SELL', desc, r)
        # BUY mirror
        rb = analyse(name + 'm', mirror_bars(bars), True)
        results[(name, 'BUY')] = rb
    # one BUY timeline in full and the rest summarised
    for nm in ('K2', 'K7a'):
        print_case(nm, 'BUY (mirror)', dict((a, b) for a, b, c in CASES)[nm], results[(nm, 'BUY')])

    print('')
    print('=== PER-CASE TABLE (A = current model, B = diagnostic latest-LH/HL) ===')
    print('case side | seed bar | A level at as-of | B level at as-of | A flip bars | B flip bars | A wick bars | B wick bars | T002 at as-of')
    for name, desc, fn in CASES:
        for side in ('SELL', 'BUY'):
            r = results[(name, side)]
            print('%-4s %-4s | %s | %-7s | %-10s | %s | %s | %s | %s | %s' % (
                name, side, r.start_t, a_level_text(r, r.n - 1), b_level_text(r, r.n - 1),
                [(t, d) for t, d in r.a_flips], [(t, d) for t, d in r.b_flips], r.a_wicks, r.b_wicks, r.t2[r.n - 1]))

    print('')
    print('=== CHECKS of this diagnostic script (real counts) ===')
    # 1 mirror symmetry
    for name, desc, fn in CASES:
        a = results[(name, 'SELL')]
        b = results[(name, 'BUY')]
        check(flips_signature(a.a_flips) == b.a_flips and flips_signature(a.b_flips) == b.b_flips
              and a.a_wicks == b.a_wicks and a.b_wicks == b.b_wicks and a.start_t == b.start_t
              and a.start_dir == -b.start_dir,
              '%s: BUY mirror gives the same bars of A/B flips and wicks (direction negated)' % name)
    # 2 causality of (A): the state after bar t does not change when later bars are removed
    ok_all = True
    for (name, side), r in results.items():
        if side != 'SELL':
            continue
        for cut in range(10, r.n, 7):
            rp = m.replay(r.bars[:cut], cut, m.Params(lookback=300, rebuild=1000))
            for t in range(cut):
                if rp.hist[t] != r.hist[t]:
                    ok_all = False
    check(ok_all, '(A) causality: per-bar state of every prefix replay equals the full replay (SELL cases, cut every 7 bars)')
    # 3 causality of (B)
    ok_b = True
    for (name, side), r in results.items():
        if side != 'SELL' or r.start_t < 0:
            continue
        for cut in range(r.start_t + 1, r.n, 7):
            swp, _ = m.t2.find_swings(r.bars[:cut], cut, 2, 2, PERIOD)
            br = run_b(r.bars[:cut], swp, r.start_t, r.start_dir)
            for t in range(cut):
                same = (br[t].dir == r.brec[t].dir and br[t].events == r.brec[t].events and
                        ((br[t].lvl is None) == (r.brec[t].lvl is None)) and
                        (br[t].lvl is None or br[t].lvl.index == r.brec[t].lvl.index))
                if not same:
                    ok_b = False
    check(ok_b, '(B) causality: per-bar state of every prefix run equals the full run (SELL cases, cut every 7 bars)')
    # 4 designed properties of the cases (derived from the definitions, not from tuning)
    R = lambda n: results[(n, 'SELL')]
    k1 = R('K1')
    t = k1.n - 1
    check(k1.start_dir == BEAR and a_level_text(k1, t) == '125.00' and k1.brec[t].lvl is not None
          and abs(k1.brec[t].lvl.price - 95.0) < 1e-9,
          'K1: (A) level 125.00 (high between the two lows), (B) level 95.00 (latest LH) at the as-of bar; no flip in either')
    check(k1.a_flips == [] and k1.b_flips == [], 'K1: no flip under A or B at the as-of bar (owner evidence: level chosen, nothing crossed)')
    k2 = R('K2')
    check(len(k2.b_flips) >= 1 and k2.a_flips == [], 'K2: B flips on the body close above the LH, A does not flip (no close above 125)')
    k3 = R('K3')
    check(len(k3.b_flips) >= 1 and len(k3.a_flips) == 1 and k3.b_flips[0][0] < k3.a_flips[0][0],
          'K3: B flips strictly earlier than A; A flips at the first close above 125')
    k4 = R('K4')
    check(k4.a_flips == [] and k4.b_flips == [] and len(k4.b_wicks) == 1 and k4.a_wicks == [],
          'K4: wick over the local LH only: B records a WICK (no flip), A no WICK/HOLD (a local sweep is observation only), no flip')
    k5 = R('K5')
    check(k5.a_flips == [] and k5.b_flips == [] and len(k5.a_wicks) == 1 and len(k5.b_wicks) == 1,
          'K5: wick over the structural level only: A WICK (HOLD), B WICK, no flip anywhere')
    k5b = R('K5b')
    check(len(k5b.a_flips) == 1 and len(k5b.b_flips) == 1 and k5b.a_flips[0][0] == k5b.b_flips[0][0],
          'K5b: wick then a body close beyond: A and B flip on the same bar (the close, not the wick)')
    k6c = R('K6c')
    t = k6c.n - 1
    check(a_level_text(k6c, t) == '125.00' and k6c.brec[t].lvl is not None and abs(k6c.brec[t].lvl.price - 105.0) < 1e-9,
          'K6c: bounce LH 105 confirmed but no LL after it: A keeps 125.00, B takes 105.00')
    k6a = R('K6a')
    check(len(k6a.b_flips) >= 1 and k6a.a_flips == [],
          'K6a: B flips BULL on the close through the minor bounce; A keeps the bearish bias')
    k6b = R('K6b')
    t = k6b.n - 1
    check(k6b.a_flips == [] and k6b.b_flips == [] and a_level_text(k6b, t) == '105.00',
          'K6b: when LL2 follows, A moves the level to the bounce high 105.00 (P2 pair + ratchet), no flip')
    k7a = R('K7a')
    check(len(k7a.b_flips) >= 1 and k7a.a_flips == [], 'K7a: B flips on the close above the counter-leg LH 110; A keeps the bearish bias (125 not closed beyond)')
    k7b = R('K7b')
    check(len(k7b.a_flips) == 1 and k7b.b_flips[0][0] < k7b.a_flips[0][0], 'K7b: A flips at the close above 125, later than B')
    k7c = R('K7c')
    check(len(k7c.a_flips) >= 1 and len(k7c.b_flips) >= 1 and k7c.a_flips[0][0] == k7c.b_flips[0][0],
          'K7c: once the counter-leg LH is in a P2 pair (a new LL followed), A and B flip on the SAME bar')
    # 5 SP1 vs A: the level A uses is always classified STRUCTURAL by SP1 at the bar it is taken
    bad = 0
    tot = 0
    moments = 0
    for (name, side), r in results.items():
        if side != 'SELL':
            continue
        for t in range(r.n):
            d = r.hist[t][0]
            if d == 0:
                continue
            al = a_level_pivot(r, t)
            if al is None:
                continue
            nk = m.known_count(r.sw, RIGHT, t)
            ok, tx = sp1_verdict(r.bars, r.sw, nk, d, t, al)
            tot += 1
            # a level held by the ratchet may be CONSUMED/older-pair text at later bars: only the moment of taking is asserted
            if t == 0 or a_level_pivot(r, t - 1) is not al:
                moments += 1
                if not ok:
                    bad += 1
    check(bad == 0, 'SP1 vs (A): every swing (A) takes as protecting level is classified STRUCTURAL by SP1 at the bar it is taken (%d moments of taking, %d level-bar samples examined)' % (moments, tot))
    print('')
    print('DIAGNOSTIC RESULT: %d passed, %d failed' % (PASS, FAIL))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
