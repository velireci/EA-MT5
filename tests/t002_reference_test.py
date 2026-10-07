#!/usr/bin/env python3
"""T002 reference model and controlled-data tests (PROPOSED H4 rules).

IMPORTANT - what this file proves and what it does not:
  * It is a Python re-implementation of the PROPOSED algorithm in
    tasks/T002-h4-map.md. The tests verify THIS MODEL.
  * It does NOT execute or compile the MQL5 source (src/include/H4Structure.mqh).
    src/tests/T002_LogicTest.mq5 mirrors the same cases inside MT5, but it has
    NOT been run. MQL5 equivalence is therefore unproven until it is run.
  * The rules tested are developer proposals awaiting client validation,
    not client answers.

Usage:
  python3 tests/t002_reference_test.py              run all tests
  python3 tests/t002_reference_test.py --emit-mql   print the generated case
                                                    data block for the MQL5 test
"""
import calendar
import math
import sys
import time
from collections import namedtuple

PERIOD = 14400                       # H4 seconds
T0 = calendar.timegm((2026, 1, 5, 0, 0, 0))
MIRROR = 4200.0

Bar = namedtuple('Bar', 'time high low close')


# ---------------------------------------------------------------- model ----
class Swing(object):
    def __init__(self, sid, is_high, index, pivot_time, confirm_time, price):
        self.id = sid
        self.is_high = is_high
        self.index = index
        self.pivot_time = pivot_time
        self.confirm_time = confirm_time
        self.price = price


class Fvg(object):
    def __init__(self):
        self.id = ''
        self.bullish = False
        self.index_a = 0
        self.time_a = 0
        self.confirm_time = 0
        self.lower = 0.0
        self.upper = 0.0
        self.state = 'FRESH'
        self.cls = 'NONE'


class Result(object):
    def __init__(self):
        self.direction = 'UNKNOWN'
        self.range_state = 'NONE'
        self.range_high = 0.0
        self.range_low = 0.0
        self.range_known_time = 0
        self.erl_price = 0.0
        self.erl_state = 'NA'
        self.erl_taken_time = 0
        self.ambiguous = 0


class Analysis(object):
    def __init__(self):
        self.swings = []
        self.fvgs = []
        self.res = Result()


def ts(t):
    return time.strftime('%Y%m%d%H%M', time.gmtime(t))


def find_swings(bars, n, left, right, period):
    swings = []
    ambiguous = 0
    for i in range(left, n - right):
        is_h = True
        is_l = True
        for j in range(i - left, i + right + 1):
            if j == i:
                continue
            if not bars[i].high > bars[j].high:
                is_h = False
            if not bars[i].low < bars[j].low:
                is_l = False
        if is_h and is_l:
            ambiguous += 1
            continue
        if is_h:
            swings.append(Swing('S%sH' % ts(bars[i].time), True, i, bars[i].time,
                                bars[i + right].time + period, bars[i].high))
        elif is_l:
            swings.append(Swing('S%sL' % ts(bars[i].time), False, i, bars[i].time,
                                bars[i + right].time + period, bars[i].low))
    return swings, ambiguous


def derive_direction(swings):
    highs = [s for s in swings if s.is_high]
    lows = [s for s in swings if not s.is_high]
    if len(highs) < 2 or len(lows) < 2:
        return 'UNKNOWN'
    h1, h2 = highs[-2].price, highs[-1].price
    l1, l2 = lows[-2].price, lows[-1].price
    if h2 < h1 and l2 < l1:
        return 'BEARISH'
    if h2 > h1 and l2 > l1:
        return 'BULLISH'
    return 'MIXED'


def derive_interval(swings, direction):
    """returns (state, high, low, known_time); state NONE/UNDEFINED/VALID"""
    if direction not in ('BULLISH', 'BEARISH'):
        return 'NONE', 0.0, 0.0, 0
    highs = [s for s in swings if s.is_high]
    lows = [s for s in swings if not s.is_high]
    if direction == 'BEARISH':
        anchor = lows[-1]
        other = None
        for s in reversed(highs):
            if s.pivot_time < anchor.pivot_time:
                other = s
                break
        if other is None:
            return 'UNDEFINED', 0.0, 0.0, 0
        hi, lo = other, anchor
    else:
        anchor = highs[-1]
        other = None
        for s in reversed(lows):
            if s.pivot_time < anchor.pivot_time:
                other = s
                break
        if other is None:
            return 'UNDEFINED', 0.0, 0.0, 0
        hi, lo = anchor, other
    if hi.price <= lo.price:
        return 'UNDEFINED', 0.0, 0.0, 0
    later = hi if hi.pivot_time > lo.pivot_time else lo
    return 'VALID', hi.price, lo.price, later.confirm_time


def erl_taken(bars, n, erl_price, is_sell, known_time):
    """first closed bar with open time >= known_time touching the ERL; 0 if none"""
    for i in range(n):
        if bars[i].time < known_time:
            continue
        if is_sell and bars[i].low <= erl_price:
            return bars[i].time
        if (not is_sell) and bars[i].high >= erl_price:
            return bars[i].time
    return 0


def find_fvgs(bars, n, period):
    out = []
    for a in range(0, n - 2):
        c = a + 2
        f = None
        if bars[c].low > bars[a].high:
            f = Fvg()
            f.bullish = True
            f.lower = bars[a].high
            f.upper = bars[c].low
        elif bars[c].high < bars[a].low:
            f = Fvg()
            f.bullish = False
            f.lower = bars[c].high
            f.upper = bars[a].low
        if f is not None:
            f.index_a = a
            f.time_a = bars[a].time
            f.confirm_time = bars[c].time + period
            f.id = 'F%s%s' % (ts(bars[a].time), 'U' if f.bullish else 'D')
            out.append(f)
    return out


def eval_fvg_states(bars, n, fvgs):
    for f in fvgs:
        f.state = 'FRESH'
        touched = False
        invalid = False
        for i in range(f.index_a + 3, n):
            if f.bullish:
                if bars[i].close < f.lower:
                    invalid = True
            else:
                if bars[i].close > f.upper:
                    invalid = True
            if bars[i].low <= f.upper and bars[i].high >= f.lower:
                touched = True
        if invalid:
            f.state = 'INVALID'
        elif touched:
            f.state = 'TOUCHED'


def classify(fvgs, res):
    for f in fvgs:
        f.cls = 'NONE'
        if f.state == 'INVALID':
            continue
        if res.range_state != 'VALID':
            continue
        want_bull = (res.direction == 'BULLISH')
        if f.bullish != want_bull:
            f.cls = 'OPPOSITE'
        elif f.lower >= res.range_low and f.upper <= res.range_high:
            f.cls = 'IRL'
        else:
            f.cls = 'OUTSIDE'


def analyze(bars, n=None, left=2, right=2, period=PERIOD):
    if n is None:
        n = len(bars)
    a = Analysis()
    a.swings, a.res.ambiguous = find_swings(bars, n, left, right, period)
    r = a.res
    r.direction = derive_direction(a.swings)
    r.range_state, r.range_high, r.range_low, r.range_known_time = \
        derive_interval(a.swings, r.direction)
    if r.range_state == 'VALID':
        is_sell = (r.direction == 'BEARISH')
        r.erl_price = r.range_low if is_sell else r.range_high
        t = erl_taken(bars, n, r.erl_price, is_sell, r.range_known_time)
        r.erl_state = 'TAKEN' if t else 'UNTOUCHED'
        r.erl_taken_time = t
    a.fvgs = find_fvgs(bars, n, period)
    eval_fvg_states(bars, n, a.fvgs)
    classify(a.fvgs, r)
    return a


def select_irl(fvgs, res, price):
    if res.range_state != 'VALID':
        return []
    sell = (res.direction == 'BEARISH')
    keyed = []
    for f in fvgs:
        if f.cls != 'IRL':
            continue
        inside = (f.lower <= price <= f.upper)
        if inside:
            dist = 0.0
        elif sell and f.lower > price:
            dist = f.lower - price
        elif (not sell) and f.upper < price:
            dist = price - f.upper
        else:
            continue
        keyed.append((dist, -f.confirm_time, f.id, f))
    keyed.sort(key=lambda k: (k[0], k[1], k[2]))
    return [k[3] for k in keyed]


def summary(a, price):
    r = a.res
    sel = select_irl(a.fvgs, r, price)
    return ('DIR=%s;RNG=%s;H=%.2f;L=%.2f;K=%d;ERL=%s;ERLP=%.2f;TT=%d;AMB=%d;SW=%s;FV=%s;SEL=%s' % (
        r.direction, r.range_state, r.range_high, r.range_low, r.range_known_time,
        r.erl_state, r.erl_price, r.erl_taken_time, r.ambiguous,
        ','.join('%s@%d:%.2f' % (s.id, s.confirm_time, s.price) for s in a.swings),
        ','.join('%s:%s:%s:%.2f:%.2f' % (f.id, f.state, f.cls, f.lower, f.upper) for f in a.fvgs),
        ','.join(f.id for f in sel)))


# ------------------------------------------------------------- builders ----
def hl_bars(rows):
    """rows of (high, low) or (high, low, close)"""
    out = []
    for i, r in enumerate(rows):
        c = r[2] if len(r) > 2 else (r[0] + r[1]) / 2.0
        out.append(Bar(T0 + i * PERIOD, float(r[0]), float(r[1]), float(c)))
    return out


def zz(pivots, hw=5.0, step=4.0, tail=2, extra_centers=(), extra_bars=()):
    """Monotone zigzag of bar centres. pivots: (kind, centre[, [mid centres]]).
    Bar = centre +/- hw. Swing price = centre +/- hw. Step <= hw gives no FVG
    unless an explicit larger step is placed in a mid list."""
    k0, v0 = pivots[0][0], pivots[0][1]
    start = v0 + (-3 * step if k0 == 'H' else 3 * step)
    vals = [start + (v0 - start) * j / 3.0 for j in range(3)] + [v0]
    prev = v0
    for p in pivots[1:]:
        v = p[1]
        if len(p) > 2:
            mid = list(p[2])
        else:
            k = int(math.ceil(abs(v - prev) / step))
            mid = [prev + (v - prev) * j / k for j in range(1, k)]
        vals += mid + [v]
        prev = v
    d = -1 if pivots[-1][0] == 'H' else 1
    for j in range(1, tail + 1):
        vals.append(prev + d * step * j)
    vals += list(extra_centers)
    rows = [(v + hw, v - hw, v) for v in vals] + list(extra_bars)
    return hl_bars(rows)


def mirror(bars, m=MIRROR):
    return [Bar(b.time, m - b.low, m - b.high, m - b.close) for b in bars]


# Each mid list is attached to the leg that ENDS at that pivot.
BEAR_PIVOTS = [
    ('H', 2100),
    ('L', 2060, [2096, 2092, 2088, 2074, 2070, 2066, 2062]),
    ('H', 2092, [2064, 2068, 2072, 2084, 2088]),
    ('L', 2044),
    ('H', 2076),
    ('L', 2028, [2072, 2068, 2064, 2052, 2048, 2044, 2040, 2036, 2032]),
]


def bear_base():
    return zz(BEAR_PIVOTS)


def bear_touched():
    return zz(BEAR_PIVOTS, extra_centers=[2040, 2044, 2048, 2052])


def bear_invalid_eq():
    # touched scenario + one bar closing exactly on the upper bound of the
    # 2057..2063 zone (equality) and above the 2053..2059 zone (invalid)
    return zz(BEAR_PIVOTS, extra_centers=[2040, 2044, 2048, 2052],
              extra_bars=[(2066.0, 2056.0, 2063.0)])


def bear_erl_taken_eq():
    return zz(BEAR_PIVOTS, extra_bars=[(2040.0, 2023.0, 2030.0)])


def bear_erl_near():
    return zz(BEAR_PIVOTS, extra_bars=[(2040.0, 2023.5, 2030.0)])


def idx_of(a, ident):
    for f in a.fvgs:
        if f.id == ident:
            return f
    return None


def fid(bars, index_a, kind):
    return 'F%s%s' % (ts(bars[index_a].time), kind)


# ---------------------------------------------------------------- cases ----
def build_cases():
    """(name, left, right, bars, price) - also emitted for the MQL5 test."""
    c = []
    c.append(('unconfirmed_5bars', 2, 2, hl_bars([(10, 9), (11, 10), (15, 12), (12, 10), (11, 9)]), 0.0))
    b5 = hl_bars([(10, 9), (11, 10), (15, 12), (12, 10), (11, 9)])
    c.append(('unconfirmed_4bars', 2, 2, b5[:4], 0.0))
    c.append(('equal_highs', 2, 2, hl_bars([(10, 9), (11, 10), (15, 13), (15, 13), (11, 10), (10, 9)]), 0.0))
    c.append(('equal_far_high', 2, 2, hl_bars([(15, 14), (11, 10), (15, 12), (12, 10), (11, 9)]), 0.0))
    c.append(('equal_lows', 2, 2, hl_bars([(21, 20), (20, 19), (15, 10), (15, 10), (20, 19), (21, 20)]), 0.0))
    c.append(('ambiguous_outside_bar', 2, 2, hl_bars([(10, 9), (11, 8), (15, 5), (11, 8), (10, 9)]), 0.0))
    c.append(('fvg_bullish', 2, 2, hl_bars([(100, 90), (112, 99), (120, 105)]), 0.0))
    c.append(('fvg_bullish_equal_edge', 2, 2, hl_bars([(100, 90), (112, 99), (120, 100)]), 0.0))
    c.append(('fvg_bearish', 2, 2, hl_bars([(110, 100), (101, 88), (95, 80)]), 0.0))
    c.append(('fvg_bear_fresh', 2, 2, hl_bars([(110, 100), (101, 88), (95, 80), (92, 85, 88)]), 0.0))
    c.append(('fvg_bear_touch', 2, 2, hl_bars([(110, 100), (101, 88), (95, 80), (98, 90, 92)]), 0.0))
    c.append(('fvg_bear_close_above', 2, 2, hl_bars([(110, 100), (101, 88), (95, 80), (98, 90, 92), (103, 96, 101)]), 0.0))
    c.append(('fvg_bear_close_equal', 2, 2, hl_bars([(110, 100), (101, 88), (95, 80), (98, 90, 92), (103, 96, 100)]), 0.0))
    c.append(('fvg_bull_touch', 2, 2, hl_bars([(100, 90), (112, 99), (120, 105), (108, 102, 103)]), 0.0))
    c.append(('fvg_bull_close_below', 2, 2, hl_bars([(100, 90), (112, 99), (120, 105), (108, 102, 103), (104, 97, 99)]), 0.0))
    c.append(('fvg_bull_close_equal', 2, 2, hl_bars([(100, 90), (112, 99), (120, 105), (108, 102, 103), (104, 97, 100)]), 0.0))
    c.append(('mixed_equal_highs', 2, 2,
              zz([('H', 2100), ('L', 2060), ('H', 2100), ('L', 2040)]), 0.0))
    c.append(('mixed_expanding', 2, 2,
              zz([('H', 2100), ('L', 2060), ('H', 2112), ('L', 2040)]), 0.0))
    c.append(('unknown_few_swings', 2, 2,
              zz([('H', 2100), ('L', 2060), ('H', 2092)]), 0.0))
    c.append(('bear_base', 2, 2, bear_base(), 2036.0))
    c.append(('bear_touched_inside_one', 2, 2, bear_touched(), 2055.0))
    c.append(('bear_touched_inside_two', 2, 2, bear_touched(), 2058.0))
    c.append(('bear_touched_above', 2, 2, bear_touched(), 2070.0))
    c.append(('bear_invalid_eq', 2, 2, bear_invalid_eq(), 2040.0))
    c.append(('bear_erl_taken_eq', 2, 2, bear_erl_taken_eq(), 2036.0))
    c.append(('bear_erl_near', 2, 2, bear_erl_near(), 2036.0))
    for nm, fn, p in (('bull_base', bear_base, 2036.0), ('bull_touched_inside_two', bear_touched, 2058.0),
                      ('bull_touched_below', bear_touched, 2070.0), ('bull_invalid_eq', bear_invalid_eq, 2040.0),
                      ('bull_erl_taken_eq', bear_erl_taken_eq, 2036.0)):
        c.append((nm, 2, 2, mirror(fn()), MIRROR - p))
    return c


# ----------------------------------------------------------------- tests ----
FAILS = []
PASSES = []


def check(cond, label):
    if cond:
        PASSES.append(label)
        print('  PASS ' + label)
    else:
        FAILS.append(label)
        print('  FAIL ' + label)


def case(name):
    for c in build_cases():
        if c[0] == name:
            return c
    raise KeyError(name)


def run(name):
    _, l, r, bars, price = case(name)
    return analyze(bars, len(bars), l, r), bars, price


def test_swings():
    print('--- swings')
    a, bars, _ = run('unconfirmed_5bars')
    check(len(a.swings) == 1 and a.swings[0].is_high and a.swings[0].index == 2, 'swing high confirmed with 2 right bars')
    check(a.swings[0].pivot_time == bars[2].time and a.swings[0].confirm_time == bars[4].time + PERIOD,
          'confirm_time = close time of bar i+RightBars')
    a, bars, _ = run('unconfirmed_4bars')
    check(len(a.swings) == 0, 'swing with only 1 right bar is NOT confirmed')
    for nm in ('equal_highs', 'equal_far_high', 'equal_lows'):
        a, _, _ = run(nm)
        check(len(a.swings) == 0, 'equal values do not qualify (%s)' % nm)
    a, _, _ = run('ambiguous_outside_bar')
    check(len(a.swings) == 0 and a.res.ambiguous == 1, 'bar qualifying as high and low is AMBIGUOUS and unused')


def test_direction():
    print('--- direction and interval')
    for nm in ('mixed_equal_highs', 'mixed_expanding'):
        a, _, _ = run(nm)
        check(a.res.direction == 'MIXED' and a.res.range_state == 'NONE' and
              all(f.cls == 'NONE' for f in a.fvgs) and select_irl(a.fvgs, a.res, 2000.0) == [],
              'MIXED (%s): no interval, no IRL candidates' % nm)
    a, _, _ = run('unknown_few_swings')
    check(a.res.direction == 'UNKNOWN', 'fewer than two lows -> UNKNOWN')
    a, bars, _ = run('bear_base')
    check(a.res.direction == 'BEARISH' and a.res.range_state == 'VALID', 'bearish zigzag -> BEARISH, VALID interval')
    check(a.res.range_high == 2081.0 and a.res.range_low == 2023.0 and a.res.erl_price == 2023.0,
          'interval = [2023, 2081], ERL(SELL) = interval low')
    low_sw = [s for s in a.swings if not s.is_high][-1]
    check(a.res.range_known_time == low_sw.confirm_time, 'range_known_time = confirm_time of the later pivot')
    m, _, _ = run('bull_base')
    check(m.res.direction == 'BULLISH' and m.res.range_state == 'VALID' and
          m.res.range_high == MIRROR - 2023.0 and m.res.erl_price == m.res.range_high,
          'mirrored series -> BULLISH, ERL(BUY) = interval high')


def mk_swing(is_high, idx, price):
    return Swing('S%d%s' % (idx, 'H' if is_high else 'L'), is_high, idx, T0 + idx * PERIOD,
                 T0 + (idx + 2) * PERIOD + PERIOD, price)


def test_missing_interval():
    print('--- missing interval (synthetic swing lists)')
    # bearish by values, but both highs come AFTER the latest low -> no chronological pair
    sw = [mk_swing(False, 1, 20.0), mk_swing(False, 3, 10.0), mk_swing(True, 5, 40.0), mk_swing(True, 7, 30.0)]
    d = derive_direction(sw)
    st = derive_interval(sw, d)[0]
    check(d == 'BEARISH' and st == 'UNDEFINED', 'no swing high before the latest low -> RANGE_UNDEFINED')
    # high before low exists but H <= L
    sw = [mk_swing(False, 1, 25.0), mk_swing(True, 2, 30.0), mk_swing(True, 4, 8.0), mk_swing(False, 6, 20.0)]
    d = derive_direction(sw)
    st = derive_interval(sw, d)
    check(d == 'BEARISH' and st[0] == 'UNDEFINED', 'H <= L -> RANGE_UNDEFINED')
    # bullish mirror: lows only after the latest high
    sw = [mk_swing(True, 1, 20.0), mk_swing(True, 3, 30.0), mk_swing(False, 5, 5.0), mk_swing(False, 7, 8.0)]
    d = derive_direction(sw)
    check(d == 'BULLISH' and derive_interval(sw, d)[0] == 'UNDEFINED', 'bullish: no swing low before latest high -> UNDEFINED')
    # and no IRL link / candidates when undefined
    res = Result()
    res.direction = d
    res.range_state = 'UNDEFINED'
    f = Fvg()
    f.bullish = True
    f.state = 'FRESH'
    classify([f], res)
    check(f.cls == 'NONE', 'undefined interval -> FVG is never an IRL candidate')


def test_fvg():
    print('--- FVG')
    a, bars, _ = run('fvg_bullish')
    f = a.fvgs[0]
    check(len(a.fvgs) == 1 and f.bullish and f.lower == 100.0 and f.upper == 105.0, 'bullish FVG zone [High(A), Low(C)]')
    check(f.confirm_time == bars[2].time + PERIOD and f.id == 'F202601050000U', 'FVG confirmed at close of C; ID derived from bar A + type')
    a, _, _ = run('fvg_bullish_equal_edge')
    check(len(a.fvgs) == 0, 'Low(C) == High(A) is not a gap')
    a, bars, _ = run('fvg_bearish')
    f = a.fvgs[0]
    check(len(a.fvgs) == 1 and (not f.bullish) and f.lower == 95.0 and f.upper == 100.0 and f.id == 'F202601050000D',
          'bearish FVG zone [High(C), Low(A)]')
    check(len(a.swings) == 0, 'FVG tables are too short for any swing')


def test_fvg_states():
    print('--- FVG state')
    st = lambda n: run(n)[0].fvgs[0].state
    check(st('fvg_bear_fresh') == 'FRESH', 'no intersection -> FRESH')
    check(st('fvg_bear_touch') == 'TOUCHED', 'bearish: wick touch, close back inside/below -> TOUCHED (zone kept)')
    check(st('fvg_bear_close_above') == 'INVALID', 'bearish: close strictly above upper bound -> INVALID (beats TOUCHED)')
    check(st('fvg_bear_close_equal') == 'TOUCHED', 'bearish: close == upper bound does NOT invalidate')
    check(st('fvg_bull_touch') == 'TOUCHED', 'bullish: wick touch -> TOUCHED')
    check(st('fvg_bull_close_below') == 'INVALID', 'bullish: close strictly below lower bound -> INVALID')
    check(st('fvg_bull_close_equal') == 'TOUCHED', 'bullish: close == lower bound does NOT invalidate')
    # bars that precede / are C itself are not part of the state evaluation
    a, bars, _ = run('fvg_bear_fresh')
    check(a.fvgs[0].index_a + 3 == 3, 'state evaluation starts at the bar after C')


def test_scenario_zones():
    print('--- bearish scenario: zones, classification, selection')
    a, bars, price = run('bear_base')
    # locate the two final-leg zones by their geometry instead of by index
    zs = {(f.lower, f.upper): f for f in a.fvgs}
    z1, z2 = zs.get((2057.0, 2063.0)), zs.get((2053.0, 2059.0))
    check(z1 is not None and z2 is not None, 'two overlapping bearish FVGs inside the leg exist')
    check(z1.cls == 'IRL' and z2.cls == 'IRL' and z1.state == 'FRESH' and z2.state == 'FRESH',
          'fully inside the interval -> IRL candidates, FRESH')
    out = [f for f in a.fvgs if f.cls == 'OUTSIDE']
    check(len(out) == 0, 'outside leg-1 zones were invalidated by the later rally (class NONE, not OUTSIDE)')
    inv = [f for f in a.fvgs if f.state == 'INVALID' and not f.bullish]
    check(len(inv) == 2 and all(f.cls == 'NONE' for f in inv), 'INVALID zones are never candidates')
    opp = [f for f in a.fvgs if f.bullish and f.state != 'INVALID']
    # bullish FVGs of the up-leg are invalid after the later decline; none opposite-and-valid remains
    check(len(opp) == 0, 'opposite-type bullish FVGs were invalidated by the later decline')
    sel = select_irl(a.fvgs, a.res, 2036.0)
    check([f.id for f in sel] == [z2.id, z1.id], 'SELL ordering by lower bound ascending (nearest first)')
    check(len(set(f.id for f in a.fvgs)) == len(a.fvgs), 'FVG IDs are unique')
    m, mb, mprice = run('bull_base')
    mz = {(f.lower, f.upper): f for f in m.fvgs if f.cls == 'IRL'}
    exp = [mz[(MIRROR - 2059.0, MIRROR - 2053.0)].id, mz[(MIRROR - 2063.0, MIRROR - 2057.0)].id]
    check([f.id for f in select_irl(m.fvgs, m.res, mprice)] == exp,
          'BUY (mirror): zones below price, ordered by upper bound descending')

    a, bars, _ = run('bear_touched_inside_one')
    zs = {(f.lower, f.upper): f for f in a.fvgs}
    z1, z2 = zs[(2057.0, 2063.0)], zs[(2053.0, 2059.0)]
    check(z1.state == 'TOUCHED' and z2.state == 'TOUCHED', 'touch (incl. wick equal to bound) -> TOUCHED, zones kept')
    sel = select_irl(a.fvgs, a.res, 2055.0)
    check(len(sel) == 2 and sel[0].id == z2.id, 'price inside a zone: INSIDE zone listed first, farther one not preferred')
    a, bars, _ = run('bear_touched_inside_two')
    zs = {(f.lower, f.upper): f for f in a.fvgs}
    z1, z2 = zs[(2057.0, 2063.0)], zs[(2053.0, 2059.0)]
    sel = select_irl(a.fvgs, a.res, 2058.0)
    check(z2.confirm_time > z1.confirm_time and [f.id for f in sel] == [z2.id, z1.id],
          'overlap, price inside both: tie on distance -> newer confirm_time first; zones not merged')
    a, bars, _ = run('bear_touched_above')
    check(select_irl(a.fvgs, a.res, 2070.0) == [], 'SELL: zones below price are not on the way -> no selection')

    a, bars, _ = run('bear_invalid_eq')
    zs = {(f.lower, f.upper): f for f in a.fvgs}
    z1, z2 = zs[(2057.0, 2063.0)], zs[(2053.0, 2059.0)]
    check(z1.state == 'TOUCHED' and z2.state == 'INVALID' and z2.cls == 'NONE',
          'close == upper keeps TOUCHED; close above another upper -> INVALID')
    check([f.id for f in select_irl(a.fvgs, a.res, 2040.0)] == [z1.id], 'INVALID zone dropped from selection')


def test_outside_and_opposite():
    print('--- OUTSIDE / OPPOSITE classification (leg-1 zones before the rally)')
    # Series: bearish leg with a partial-overlap zone, evaluated BEFORE price rallies.
    res = Result()
    res.direction = 'BEARISH'
    res.range_state = 'VALID'
    res.range_high, res.range_low = 2081.0, 2023.0
    fs = []
    for lo, up, bull in ((2079.0, 2087.0, False), (2075.0, 2083.0, False), (2057.0, 2063.0, False),
                         (2073.0, 2079.0, True)):
        f = Fvg()
        f.bullish, f.lower, f.upper, f.state = bull, lo, up, 'FRESH'
        fs.append(f)
    classify(fs, res)
    check([f.cls for f in fs] == ['OUTSIDE', 'OUTSIDE', 'IRL', 'OPPOSITE'],
          'partial overlap and outside -> OUTSIDE (never IRL); inside -> IRL; wrong type -> OPPOSITE')
    # exactly on the interval edges counts as inside (inclusive containment)
    g = Fvg()
    g.bullish, g.lower, g.upper, g.state = False, 2023.0, 2081.0, 'FRESH'
    classify([g], res)
    check(g.cls == 'IRL', 'containment is inclusive at the interval edges')


def test_erl():
    print('--- ERL taken')
    a, _, _ = run('bear_base')
    check(a.res.erl_state == 'UNTOUCHED', 'ERL untouched when no later bar reaches it')
    a, bars, _ = run('bear_erl_taken_eq')
    check(a.res.erl_state == 'TAKEN' and a.res.erl_taken_time == bars[-1].time, 'wick low == ERL marks TAKEN (touch is enough)')
    a, _, _ = run('bear_erl_near')
    check(a.res.erl_state == 'UNTOUCHED', 'wick 0.5 above ERL does not take it')
    m, mb, _ = run('bull_erl_taken_eq')
    check(m.res.direction == 'BULLISH' and m.res.erl_state == 'TAKEN', 'BUY: High >= ERL marks TAKEN')
    # bars before range_known_time are ignored; TAKEN never restored
    bars = hl_bars([(50, 40), (60, 20), (55, 45), (56, 46), (57, 47)])
    t = erl_taken(bars, 5, 21.0, True, bars[2].time)
    check(t == 0, 'a touch BEFORE range_known_time does not count')
    bars = hl_bars([(50, 40), (60, 20), (55, 45), (56, 18), (90, 80), (95, 85)])
    t = erl_taken(bars, 6, 21.0, True, bars[2].time)
    check(t == bars[3].time, 'TAKEN keeps the first touching bar even if price moves far away afterwards')
    t2 = erl_taken(bars, 6, 21.0, True, bars[4].time)
    check(t2 == 0, 'same bars, later known_time: not taken (only bars after range_known_time)')


def test_no_lookahead():
    print('--- prefix analysis vs full analysis (no look-ahead)')
    for nm in ('bear_invalid_eq', 'bull_invalid_eq', 'bear_touched_inside_two'):
        _, l, r, bars, price = case(nm)
        full = analyze(bars, len(bars), l, r)
        ok = True
        poisoned_ok = True
        for k in range(8, len(bars) + 1):
            T = bars[k - 1].time + PERIOD            # knowable at close of bar k-1
            pre = analyze(bars[:k], k, l, r)
            # (1) swings: prefix == full swings confirmed by T
            fs = [(s.id, s.confirm_time, s.price) for s in full.swings if s.confirm_time <= T]
            ps = [(s.id, s.confirm_time, s.price) for s in pre.swings]
            # (2) FVG identity/geometry confirmed by T
            ff = [(f.id, f.confirm_time, f.lower, f.upper) for f in full.fvgs if f.confirm_time <= T]
            pf = [(f.id, f.confirm_time, f.lower, f.upper) for f in pre.fvgs]
            # (3) direction/interval derived from the full swings restricted to T
            rs = [s for s in full.swings if s.confirm_time <= T]
            d = derive_direction(rs)
            iv = derive_interval(rs, d)
            same = (fs == ps and ff == pf and d == pre.res.direction and
                    iv == (pre.res.range_state, pre.res.range_high, pre.res.range_low, pre.res.range_known_time))
            # (4) states as known at T: recomputed on the full list but limited to k bars
            tmp = find_fvgs(bars, len(bars), PERIOD)
            tmp = [f for f in tmp if f.confirm_time <= T]
            eval_fvg_states(bars, k, tmp)
            same = same and ([(f.id, f.state) for f in tmp] == [(f.id, f.state) for f in pre.fvgs])
            ok = ok and same
            # poison: arbitrary future bars after k must not change the prefix analysis
            bad = list(bars[:k]) + [Bar(bars[k - 1].time + (j + 1) * PERIOD, 99999.0, -99999.0, 0.0)
                                    for j in range(5)]
            pz = analyze(bad, k, l, r)
            poisoned_ok = poisoned_ok and (summary(pz, price) == summary(pre, price))
        check(ok, 'prefix == full restricted to what was knowable at T (%s)' % nm)
        check(poisoned_ok, 'bars after the analysed count never influence the result (%s)' % nm)


def test_ids_and_selection_ties():
    print('--- IDs and tie-break')
    _, l, r, bars, price = case('bear_invalid_eq')
    a1 = analyze(bars, len(bars), l, r)
    a2 = analyze(list(bars), len(bars), l, r)
    check(summary(a1, price) == summary(a2, price), 'analysis is deterministic')
    ids = [f.id for f in a1.fvgs] + [s.id for s in a1.swings]
    check(len(ids) == len(set(ids)), 'swing and FVG IDs are unique within the analysis')
    check(all(i.startswith('F') and i[-1] in 'UD' and len(i) == 14 for i in [f.id for f in a1.fvgs]),
          'FVG ID format F<yyyymmddhhmm of bar A><U|D>')
    check(fid(bars, 0, 'D') == 'F202601050000D', 'ID derives from open time of bar A (UTC struct)')
    # same distance AND same confirm_time -> ID ascending (synthetic)
    res = Result()
    res.direction, res.range_state = 'BEARISH', 'VALID'
    fa, fb = Fvg(), Fvg()
    for f, ident in ((fa, 'F202601050400D'), (fb, 'F202601050000D')):
        f.id, f.lower, f.upper, f.state, f.cls, f.confirm_time = ident, 10.0, 12.0, 'FRESH', 'IRL', 777
    check([f.id for f in select_irl([fa, fb], res, 5.0)] == ['F202601050000D', 'F202601050400D'],
          'distance tie and confirm_time tie -> ID ascending')


def emit_mql():
    out = ['// BEGIN GENERATED CASE DATA (tests/t002_reference_test.py --emit-mql)']
    cases = build_cases()
    out.append('#define T2_CASE_COUNT %d' % len(cases))
    out.append('void T2LoadCase(const int id, MqlRates &bars[], int &n, int &left, int &right, double &price, string &name, string &expected)')
    out.append('  {')
    out.append('   switch(id)')
    out.append('     {')
    for i, (nm, l, r, bars, price) in enumerate(cases):
        a = analyze(bars, len(bars), l, r)
        flat = ','.join('%r,%r,%r' % (b.high, b.low, b.close) for b in bars)
        out.append('      case %d:' % i)
        out.append('        {')
        out.append('         double d[] = {%s};' % flat)
        out.append('         name = "%s"; left = %d; right = %d; price = %r;' % (nm, l, r, price))
        out.append('         expected = "%s";' % summary(a, price))
        out.append('         T2FillBars(d, %d, bars);' % len(bars))
        out.append('         n = %d;' % len(bars))
        out.append('         break;')
        out.append('        }')
    out.append('     }')
    out.append('  }')
    out.append('// END GENERATED CASE DATA')
    return '\n'.join(out)


def main():
    if '--emit-mql' in sys.argv:
        print(emit_mql())
        return 0
    print('T002 reference model tests - these verify the PYTHON MODEL of the PROPOSED rules,')
    print('NOT the MQL5 source. T002_LogicTest.mq5 has not been run.')
    test_swings()
    test_direction()
    test_missing_interval()
    test_fvg()
    test_fvg_states()
    test_scenario_zones()
    test_outside_and_opposite()
    test_erl()
    test_no_lookahead()
    test_ids_and_selection_ties()
    print('')
    print('%d passed, %d failed' % (len(PASSES), len(FAILS)))
    if FAILS:
        for f in FAILS:
            print('  FAILED: ' + f)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
