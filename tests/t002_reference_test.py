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


# ------------------------------------------------- pure EA decisions ----
# Mirrors of the pure helpers at the end of src/include/H4Structure.mqh.
HIST_INSUFFICIENT, HIST_PARTIAL, HIST_COMPLETE = 0, 1, 2
ACT_NONE, ACT_CLEAR, ACT_REBUILT, ACT_REFRESHED = 0, 1, 2, 3


def history_state(got, requested, left, right):
    if got < 2 * (left + right) + 3:
        return HIST_INSUFFICIENT
    if got < requested:
        return HIST_PARTIAL
    return HIST_COMPLETE


def history_text(state, got, requested, stalled):
    if state == HIST_INSUFFICIENT:
        return 'INSUFFICIENT HISTORY (%d of %d bars%s)' % (
            got, requested, ', loading stalled; retrying' if stalled else '')
    if state == HIST_PARTIAL:
        return 'PARTIAL HISTORY (%d of %d, %s)' % (
            got, requested, 'loading stalled; retrying' if stalled else 'refreshing')
    return 'HISTORY COMPLETE (%d of %d)' % (got, requested)


def history_improved(prev_got, prev_oldest, new_got, new_oldest):
    if new_got > prev_got:
        return True
    return prev_oldest != 0 and new_oldest != 0 and new_oldest < prev_oldest


def hist_stalled(state, noprogress, max_noprogress):
    return state != HIST_COMPLETE and noprogress >= max_noprogress


U32 = 0xFFFFFFFF


def elapsed_ms(now_ms, last_ms):
    """uint subtraction of H4ElapsedMs (wraps like GetTickCount)."""
    return (now_ms - last_ms) & U32


def map_transition(had_map, build_ok):
    if had_map:
        return ACT_REFRESHED if build_ok else ACT_CLEAR
    return ACT_REBUILT if build_ok else ACT_NONE


# ---- map lifecycle step functions: mirror of SH4Life / H4LifeDecide /
# ---- H4LifeOnCopy in src/include/H4Structure.mqh (same order of statements).
RETRY_MS = 3000
SLOW_RETRY_MS = 30000
MAX_NOPROG = 20
ATT_NONE, ATT_BUILD, ATT_PROBE = 0, 1, 2


class Life(object):
    def __init__(self):
        self.have_map = False
        self.tried_once = False
        self.last_try = 0
        self.hist_state = HIST_COMPLETE
        self.hist_got = 0
        self.hist_oldest = 0
        self.noprog = 0
        self.hist_text = ''
        self.cleared_reason = ''


class LifeOut(object):
    def __init__(self):
        self.attempt = ATT_NONE
        self.do_clear = False
        self.clear_reason = ''
        self.rebuilt = False
        self.log_rebuilt = ''
        self.log_hist = False


def life_clear(st, reason, out):
    had = st.have_map
    st.have_map = False
    if map_transition(had, False) == ACT_CLEAR:
        out.do_clear = True
        out.clear_reason = reason
        st.cleared_reason = reason


def life_set_status(st, state, got, lookback, out):
    t = history_text(state, got, lookback, hist_stalled(state, st.noprog, MAX_NOPROG))
    st.hist_state = state
    st.hist_got = got
    if t != st.hist_text:
        st.hist_text = t
        out.log_hist = True


def life_decide(st, series_ready, not_ready_reason, new_bar, now_ms, lookback):
    out = LifeOut()
    if not series_ready:
        life_clear(st, not_ready_reason, out)
        st.noprog = 0
        if st.hist_text != '':
            life_set_status(st, st.hist_state, st.hist_got, lookback, out)
        return out
    if new_bar or not st.tried_once:
        if new_bar:
            st.noprog = 0
        st.last_try = now_ms
        st.tried_once = True
        out.attempt = ATT_BUILD
        return out
    interval = RETRY_MS
    if hist_stalled(st.hist_state, st.noprog, MAX_NOPROG):
        interval = SLOW_RETRY_MS
    if elapsed_ms(now_ms, st.last_try) < interval:
        return out
    if not st.have_map:
        st.last_try = now_ms
        out.attempt = ATT_BUILD
    elif st.hist_state != HIST_COMPLETE:
        st.last_try = now_ms
        out.attempt = ATT_PROBE
    return out


def life_on_copy(st, kind, got, oldest, newest_ok, lookback, left, right):
    out = LifeOut()
    if got <= 0:
        life_clear(st, 'history probe: CopyRates returned no closed H4 bars' if kind == ATT_PROBE
                   else 'CopyRates returned no closed H4 bars', out)
        return out
    if kind == ATT_PROBE:
        if history_improved(st.hist_got, st.hist_oldest, got, oldest):
            st.noprog = 0
            out.attempt = ATT_BUILD
            return out
        st.noprog += 1
        life_set_status(st, st.hist_state, st.hist_got, lookback, out)
        return out
    hs = history_state(got, lookback, left, right)
    if hs != HIST_COMPLETE:
        if st.hist_got == 0 or history_improved(st.hist_got, st.hist_oldest, got, oldest):
            st.noprog = 0
        else:
            st.noprog += 1
    else:
        st.noprog = 0
    st.hist_oldest = oldest
    life_set_status(st, hs, got, lookback, out)
    if hs == HIST_INSUFFICIENT:
        life_clear(st, st.hist_text, out)
        return out
    if not newest_ok:
        life_clear(st, 'newest copied bar does not match the watcher (history catching up)', out)
        return out
    act = map_transition(st.have_map, True)
    st.have_map = True
    out.rebuilt = True
    if act == ACT_REBUILT and st.cleared_reason != '':
        out.log_rebuilt = st.cleared_reason
    st.cleared_reason = ''
    return out


# ---- scripted fake data source + thin wrapper = Python twin of Poll /
# ---- HistoryProbe / RecomputeMap in src/XauUsdH4Map.mq5 (the real CopyRates,
# ---- drawing and logging are replaced by this fake; the decisions are the
# ---- step functions above).
OP_FIRST, OP_LAST, OP_READY, OP_FAIL, OP_MISMATCH, OP_NOP = 0, 1, 2, 3, 4, 9
BASE_IDX = 1000
LOOKBACK = 300
SIM_LEFT = SIM_RIGHT = 2


def sim_time(k):
    return T0 + (BASE_IDX + k) * PERIOD


class Sim(object):
    def __init__(self, first, last, start_ms):
        self.first, self.last = first, last
        self.start_ms = start_ms
        self.ready, self.fail, self.mismatch = True, False, False
        self.seen_last = -1
        self.drawn = False
        self.life = Life()
        self.t = 0
        self.ev = []            # (t, kind, text)
        self.snap = {}          # t -> (have_map, noprog, drawn)

    def add(self, kind, text):
        self.ev.append((self.t, kind, text))

    def copy(self, kind_char):
        self.add(kind_char, '')
        if self.fail:
            return -1, 0, False
        got = min(LOOKBACK, self.last - self.first + 1)
        return got, sim_time(self.last - got + 1), not self.mismatch

    def apply(self, o):
        if o.log_hist:
            self.add('HIST', self.life.hist_text)
        if o.do_clear:
            self.add('CLEAR', o.clear_reason)
            self.drawn = False

    def build(self):
        got, oldest, ok = self.copy('B')
        o = life_on_copy(self.life, ATT_BUILD, got, oldest, ok, LOOKBACK, SIM_LEFT, SIM_RIGHT)
        self.apply(o)
        if not o.rebuilt:
            return False
        if o.log_rebuilt != '':
            self.add('REBUILT', o.log_rebuilt)
        self.add('MAP', '%d' % got)
        self.drawn = True
        return True

    def probe(self):
        got, oldest, ok = self.copy('P')
        o = life_on_copy(self.life, ATT_PROBE, got, oldest, True, LOOKBACK, SIM_LEFT, SIM_RIGHT)
        self.apply(o)
        if o.attempt == ATT_BUILD:
            return self.build()
        return False

    def poll(self, t):
        self.t = t
        new_bar = False
        if self.ready:
            new_bar = self.seen_last >= 0 and self.last > self.seen_last
            self.seen_last = self.last
        now = (self.start_ms + t * 1000) & U32
        o = life_decide(self.life, self.ready, 'H4 series not ready: SIM', new_bar, now, LOOKBACK)
        self.apply(o)
        if self.ready:
            if o.attempt == ATT_PROBE:
                self.probe()
            elif o.attempt == ATT_BUILD:
                self.build()
        self.snap[t] = (self.life.have_map, self.life.noprog, self.drawn)

    def act(self, op, val):
        if op == OP_FIRST:
            self.first = val
        elif op == OP_LAST:
            self.last = val
        elif op == OP_READY:
            self.ready = val != 0
        elif op == OP_FAIL:
            self.fail = val != 0
        elif op == OP_MISMATCH:
            self.mismatch = val != 0

    def transcript(self):
        parts = ['t=%d %s' % (t, k if tx == '' else '%s:%s' % (k, tx)) for (t, k, tx) in self.ev]
        parts.append('END map=%d drawn=%d noprog=%d text=%s' % (
            1 if self.life.have_map else 0, 1 if self.drawn else 0, self.life.noprog, self.life.hist_text))
        return ' | '.join(parts)


def run_scenario(scn):
    name, start_ms, first, last, duration, acts = scn
    sim = Sim(first, last, start_ms)
    for t in range(0, duration + 1):
        for (at, op, val) in acts:
            if at == t:
                sim.act(op, val)
        sim.poll(t)
    return sim


def times(sim, kind):
    return [t for (t, k, _) in sim.ev if k == kind]


def texts(sim, kind):
    return [(t, tx) for (t, k, tx) in sim.ev if k == kind]


def build_scenarios():
    s = []
    P = (880, 999)          # 120 closed bars (PARTIAL for lookback 300)
    FULL = (700, 999)       # 300 closed bars (COMPLETE)
    nop = (0, OP_NOP, 0)
    s.append(('a_complete_after_20th', 100000, P[0], P[1], 200, [nop, (100, OP_FIRST, 700)]))
    s.append(('a2_stalled_then_partial_progress', 100000, P[0], P[1], 130, [nop, (70, OP_FIRST, 780)]))
    s.append(('b_complete_before_20th', 100000, P[0], P[1], 100, [nop, (25, OP_FIRST, 700)]))
    s.append(('c_probe_failure_recovers', 100000, P[0], P[1], 120, [(16, OP_FAIL, 1), (40, OP_FAIL, 0)]))
    s.append(('c2_probe_failure_long', 100000, P[0], P[1], 130, [(16, OP_FAIL, 1), (100, OP_FAIL, 0)]))
    s.append(('c3_build_failure_complete', 100000, FULL[0], FULL[1], 100,
              [(50, OP_FAIL, 1), (50, OP_LAST, 1000), (70, OP_FAIL, 0)]))
    s.append(('d_series_not_ready', 100000, P[0], P[1], 60, [(16, OP_READY, 0), (30, OP_READY, 1)]))
    s.append(('e1_insufficient_then_sufficient', 100000, 994, 999, 40, [nop, (10, OP_FIRST, 700)]))
    s.append(('e2_map_then_insufficient', 100000, P[0], P[1], 100,
              [(50, OP_FIRST, 995), (50, OP_LAST, 1000), (79, OP_FIRST, 700)]))
    s.append(('e3_insufficient_stalled', 100000, 994, 999, 130, [nop, (100, OP_FIRST, 700)]))
    s.append(('f_newest_mismatch', 100000, FULL[0], FULL[1], 60,
              [(30, OP_LAST, 1000), (30, OP_MISMATCH, 1), (45, OP_MISMATCH, 0)]))
    s.append(('g_complete_no_rechecks', 100000, FULL[0], FULL[1], 600, [nop]))
    s.append(('h_new_bar_resets_stall', 100000, P[0], P[1], 140, [(70, OP_LAST, 1000)]))
    ref_acts = [nop, (100, OP_FIRST, 700)]
    s.append(('i_ref_unwrapped', 100000, P[0], P[1], 130, ref_acts))
    s.append(('i_wrap_early', 4294959296, P[0], P[1], 130, ref_acts))     # wraps at t=8
    s.append(('i_wrap_while_slow', 4294892296, P[0], P[1], 130, ref_acts))  # wraps at t=75
    return s


def setup_active(direction, range_state, erl_state, selectable):
    return (range_state == 'VALID' and direction in ('BULLISH', 'BEARISH')
            and erl_state == 'UNTOUCHED' and selectable > 0)


def irl_panel_text(active, erl_name, zone, inside):
    if active:
        return 'nearest IRL: %s %s -> ERL' % (zone, 'INSIDE' if inside else 'ahead')
    return 'candidate (inactive: ERL %s): %s %s' % (erl_name, zone, 'inside' if inside else 'ahead')


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


def test_pure_decisions():
    print('--- history state, stall, tick arithmetic, map transitions, panel wording')
    check(history_state(6, 300, 2, 2) == HIST_INSUFFICIENT, 'history 6 of 300 (min 11) -> INSUFFICIENT')
    check(history_state(11, 300, 2, 2) == HIST_PARTIAL, 'history 11 of 300 -> PARTIAL')
    check(history_state(299, 300, 2, 2) == HIST_PARTIAL, 'history 299 of 300 -> PARTIAL')
    check(history_state(300, 300, 2, 2) == HIST_COMPLETE, 'history 300 of 300 -> COMPLETE')
    check(history_text(HIST_INSUFFICIENT, 6, 300, False) == 'INSUFFICIENT HISTORY (6 of 300 bars)', 'text INSUFFICIENT')
    check(history_text(HIST_INSUFFICIENT, 6, 300, True) == 'INSUFFICIENT HISTORY (6 of 300 bars, loading stalled; retrying)',
          'text INSUFFICIENT stalled')
    check(history_text(HIST_PARTIAL, 120, 300, False) == 'PARTIAL HISTORY (120 of 300, refreshing)', 'text PARTIAL refreshing')
    check(history_text(HIST_PARTIAL, 120, 300, True) == 'PARTIAL HISTORY (120 of 300, loading stalled; retrying)',
          'text PARTIAL stalled')
    check(history_text(HIST_COMPLETE, 300, 300, False) == 'HISTORY COMPLETE (300 of 300)', 'text COMPLETE')
    check(all('no more on server' not in history_text(st, 100, 300, sl)
              for st in (HIST_INSUFFICIENT, HIST_PARTIAL, HIST_COMPLETE) for sl in (False, True)),
          'no history text claims "no more on server"')
    t1 = T0
    t0 = T0 - PERIOD
    check(history_improved(100, t1, 101, t1), 'more bars -> improved')
    check(history_improved(100, t1, 100, t0), 'older first bar -> improved')
    check(not history_improved(100, t1, 100, t1), 'same count and first bar -> not improved')
    check(not history_improved(100, t1, 99, t1), 'fewer bars -> not improved')
    check(not history_improved(0, 0, 0, 0), 'nothing yet -> not improved')
    check(not hist_stalled(HIST_PARTIAL, 19, 20), 'partial, 19 idle checks -> not stalled yet')
    check(hist_stalled(HIST_PARTIAL, 20, 20), 'partial, 20 idle checks -> stalled (slower cadence, NOT stopped)')
    check(hist_stalled(HIST_INSUFFICIENT, 25, 20), 'insufficient, 25 idle checks -> stalled')
    check(not hist_stalled(HIST_COMPLETE, 99, 20), 'complete -> never stalled')
    check(elapsed_ms(5000, 2000) == 3000, 'elapsed ms without wrap')
    check(elapsed_ms(5, U32 - 5) == 11, 'elapsed ms across the GetTickCount wrap (unsigned subtraction)')
    check(elapsed_ms(0x200, 0xFFFFFF00) == 0x300, 'elapsed ms across the wrap, second sample')
    check(map_transition(True, False) == ACT_CLEAR, 'map + failed build -> CLEAR')
    check(map_transition(False, True) == ACT_REBUILT, 'no map + ok build -> REBUILT')
    check(map_transition(True, True) == ACT_REFRESHED, 'map + ok build -> REFRESHED')
    check(map_transition(False, False) == ACT_NONE, 'no map + failed build -> NONE')
    check(setup_active('BEARISH', 'VALID', 'UNTOUCHED', 1), 'bearish, valid, ERL untouched, 1 candidate -> active')
    check(not setup_active('BEARISH', 'VALID', 'UNTOUCHED', 0), 'no selectable candidate -> inactive')
    check(not setup_active('BEARISH', 'VALID', 'TAKEN', 1), 'ERL TAKEN -> inactive')
    check(not setup_active('BEARISH', 'UNDEFINED', 'UNTOUCHED', 1), 'interval not valid -> inactive')
    check(not setup_active('MIXED', 'VALID', 'UNTOUCHED', 1), 'direction not trending -> inactive')
    z = 'F1 FRESH [10.00 - 12.00]'
    check(irl_panel_text(True, 'UNTOUCHED', z, False) == 'nearest IRL: F1 FRESH [10.00 - 12.00] ahead -> ERL', 'UNTOUCHED ahead wording')
    check(irl_panel_text(True, 'UNTOUCHED', z, True) == 'nearest IRL: F1 FRESH [10.00 - 12.00] INSIDE -> ERL', 'UNTOUCHED inside wording')
    check(irl_panel_text(False, 'TAKEN', z, False) == 'candidate (inactive: ERL TAKEN): F1 FRESH [10.00 - 12.00] ahead', 'TAKEN wording has no -> ERL')
    check('-> ERL' not in irl_panel_text(False, 'TAKEN', z, True), 'TAKEN inside wording has no -> ERL')
    # end to end on a model case: ERL TAKEN scenario yields candidates but an inactive setup
    a, _, price = run('bear_erl_taken_eq')
    sel = select_irl(a.fvgs, a.res, price)
    act = setup_active(a.res.direction, a.res.range_state, a.res.erl_state, len(sel))
    check(a.res.erl_state == 'TAKEN' and not act, 'model case with ERL TAKEN is never an active setup')


def test_lifecycle_scenarios():
    print('--- map lifecycle: scripted fake data source over simulated time (model of the step functions)')
    S = dict((scn[0], run_scenario(scn)) for scn in build_scenarios())
    check(len(S) == len(build_scenarios()) and all(len(v.transcript()) < 1800 for v in S.values()),
          'every scenario has a unique name and a transcript short enough for an MQL5 string literal')
    check(all('no more on server' not in v.transcript() for v in S.values()),
          'no scenario ever claims "no more on server"')

    # (a) partial history completing AFTER the 20th no-progress check
    a = S['a_complete_after_20th']
    check(times(a, 'P') == list(range(3, 61, 3)) + [90, 120],
          '(a) 20 probes at 3 s, then slower cadence 30 s (probes at 90 and 120 only)')
    check(texts(a, 'HIST') == [(0, 'PARTIAL HISTORY (120 of 300, refreshing)'),
                               (60, 'PARTIAL HISTORY (120 of 300, loading stalled; retrying)'),
                               (120, 'HISTORY COMPLETE (300 of 300)')],
          '(a) status: refreshing -> "loading stalled; retrying" at the 20th idle check -> cleared (COMPLETE)')
    check(a.snap[60][1] == 20 and a.snap[59][1] == 19, '(a) stall begins exactly at the 20th idle check')
    check(texts(a, 'MAP') == [(0, '120'), (120, '300')] and times(a, 'B') == [0, 120],
          '(a) map rebuilt from the complete history at the poll that sees it (t=120)')
    check(a.last == 999 and a.seen_last == 999, '(a) no new H4 bar was involved')
    check(max(t for (t, k, _) in a.ev if k in ('P', 'B')) == 120 and a.snap[200] == (True, 0, True),
          '(a) after completion no further re-checks (t=121..200)')
    check(not times(a, 'CLEAR'), '(a) the map was never cleared while stalled')

    # (a2) stalled, then progress that is still partial -> back to the normal cadence
    a2 = S['a2_stalled_then_partial_progress']
    check(texts(a2, 'HIST')[-1] == (90, 'PARTIAL HISTORY (220 of 300, refreshing)') and 93 in times(a2, 'P')
          and 96 in times(a2, 'P'), '(a2) partial progress while stalled -> rebuilt, "refreshing", 3 s cadence again')

    # (b) history arrives before the 20th check
    b = S['b_complete_before_20th']
    check(times(b, 'P') == list(range(3, 28, 3)) and texts(b, 'MAP') == [(0, '120'), (27, '300')]
          and not any('stalled' in tx for (_, tx) in texts(b, 'HIST')),
          '(b) history before the 20th check: rebuilt at the next probe, never stalled, no later re-checks')

    # (c) probe failure with an existing map
    c = S['c_probe_failure_recovers']
    check(texts(c, 'CLEAR') == [(18, 'history probe: CopyRates returned no closed H4 bars')],
          '(c) failed probe copy with a map -> map cleared once, with its reason')
    check(c.snap[15] == (True, 5, True) and c.snap[18] == (False, 5, False) and c.snap[39] == (False, 5, False),
          '(c) map off, drawings removed, dynamic state off, stall counter NOT incremented (5 stays 5)')
    check(times(c, 'B')[1:] == list(range(21, 43, 3)) and texts(c, 'REBUILT')
          == [(42, 'history probe: CopyRates returned no closed H4 bars')] and texts(c, 'MAP')[-1] == (42, '120'),
          '(c) normal no-map retry picks it up once the copy works; rebuild logged with the clear reason')
    check(c.snap[41][2] is False and c.snap[42] == (True, 6, True),
          '(c) recovery build with identical data counts as ONE idle copy (5 -> 6), not as exhaustion')

    c2 = S['c2_probe_failure_long']
    bs = times(c2, 'B')
    check(all(c2.snap[t][1] == 5 for t in range(18, 102)) and not any('stalled' in tx for (_, tx) in texts(c2, 'HIST'))
          and all(y - x == 3 for x, y in zip(bs[1:], bs[2:])) and len(texts(c2, 'CLEAR')) == 1,
          '(c2) 80 s of failed copies: counter stays 5, no stall status, retries stay at 3 s, one clear logged')
    check(texts(c2, 'REBUILT') != [] and c2.snap[102][0] is True, '(c2) recovery after the long failure')

    c3 = S['c3_build_failure_complete']
    check(texts(c3, 'CLEAR') == [(50, 'CopyRates returned no closed H4 bars')] and not times(c3, 'P')
          and times(c3, 'B') == [0] + list(range(50, 72, 3)) and texts(c3, 'MAP')[-1] == (71, '300')
          and all(v[1] == 0 for v in c3.snap.values()),
          '(c3) failed rebuild on a new bar with complete history: cleared, retried every 3 s, rebuilt, counter 0')

    # (d) series not ready -> clear -> ready -> rebuild
    d = S['d_series_not_ready']
    check([t for t in times(d, 'P') if t < 16] == [3, 6, 9, 12, 15] and texts(d, 'CLEAR') == [(16, 'H4 series not ready: SIM')]
          and d.snap[16] == (False, 0, False), '(d) not ready: map cleared at once, counter reset to 0')
    check(not [e for e in d.ev if 16 < e[0] < 30] and texts(d, 'REBUILT') == [(30, 'H4 series not ready: SIM')]
          and d.snap[30] == (True, 1, True), '(d) no copy while not ready; rebuilt when ready again (rebuild logged)')

    # (e) insufficient history
    e1 = S['e1_insufficient_then_sufficient']
    check(texts(e1, 'HIST')[0] == (0, 'INSUFFICIENT HISTORY (6 of 300 bars)') and not times(e1, 'CLEAR')
          and times(e1, 'B') == [0, 3, 6, 9, 12] and texts(e1, 'MAP') == [(12, '300')],
          '(e1) insufficient at start (nothing to clear), retried every 3 s, built when sufficient')
    e2 = S['e2_map_then_insufficient']
    check(texts(e2, 'CLEAR') == [(50, 'INSUFFICIENT HISTORY (6 of 300 bars)')] and e2.snap[50] == (False, 1, False)
          and texts(e2, 'REBUILT') == [(80, 'INSUFFICIENT HISTORY (6 of 300 bars)')]
          and texts(e2, 'MAP')[-1] == (80, '300'),
          '(e2) existing map + insufficient history -> cleared -> becomes sufficient -> rebuilt')
    e3 = S['e3_insufficient_stalled']
    check(texts(e3, 'HIST')[1] == (60, 'INSUFFICIENT HISTORY (6 of 300 bars, loading stalled; retrying)')
          and times(e3, 'B') == list(range(0, 61, 3)) + [90, 120] and texts(e3, 'MAP') == [(120, '300')],
          '(e3) insufficient + stalled: 30 s cadence (no stop), built at the first check after history arrives')

    # (f) newest-bar mismatch
    f = S['f_newest_mismatch']
    check(texts(f, 'CLEAR') == [(30, 'newest copied bar does not match the watcher (history catching up)')]
          and times(f, 'B') == [0, 30, 33, 36, 39, 42, 45] and texts(f, 'REBUILT')[0][0] == 45
          and not times(f, 'P'), '(f) newest-bar mismatch -> cleared -> retried every 3 s -> rebuilt')

    # (g) complete history: no re-checks
    g = S['g_complete_no_rechecks']
    check([(t, k) for (t, k, _) in g.ev if k in ('P', 'B')] == [(0, 'B')] and g.snap[600] == (True, 0, True),
          '(g) complete history: exactly one copy in 600 s, no re-checks')

    # (h) new H4 bar resets stall state
    h = S['h_new_bar_resets_stall']
    check(h.snap[69][1] == 20 and h.snap[70][1] == 0 and not [t for t in times(h, 'P') if 60 < t < 73]
          and times(h, 'B') == [0, 70] and 73 in times(h, 'P') and texts(h, 'HIST')[2] ==
          (70, 'PARTIAL HISTORY (121 of 300, refreshing)'),
          '(h) a new H4 bar rebuilds at once, resets the stall counter and returns to the 3 s cadence')
    check(texts(h, 'HIST')[3] == (130, 'PARTIAL HISTORY (121 of 300, loading stalled; retrying)'),
          '(h) stalling is possible again after the reset (20 new idle checks)')

    # (i) tick counter wrap-around
    ref = S['i_ref_unwrapped'].transcript()
    check('MAP:300' in ref and 'stalled' in ref, '(i) reference run is non-trivial')
    check(S['i_wrap_early'].transcript() == ref, '(i) GetTickCount wrap at t=8 (fast cadence): identical transcript')
    check(S['i_wrap_while_slow'].transcript() == ref, '(i) wrap at t=75 (inside the 30 s slow interval): identical transcript')

    # a failed copy never moves the stall counter, in any scenario
    ok = True
    for v in S.values():
        for (t, k, tx) in v.ev:
            if k == 'CLEAR' and 'CopyRates' in tx:
                ok = ok and v.snap[t][1] == v.snap[t - 1][1]
    check(ok, 'in every scenario a CopyRates failure leaves the stall counter unchanged')


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
    scns = build_scenarios()
    out.append('#define T2_SCN_COUNT %d' % len(scns))
    out.append('void T2LoadScenario(const int id, string &name, ulong &start_ms, int &first, int &last, int &duration, int &acts[], string &expected)')
    out.append('  {')
    out.append('   switch(id)')
    out.append('     {')
    for i, scn in enumerate(scns):
        nm, start_ms, first, last, duration, acts = scn
        tr = run_scenario(scn).transcript()
        assert len(tr) < 1800 and '"' not in tr and '\\' not in tr
        flat = ','.join('%d,%d,%d' % a for a in acts)
        out.append('      case %d:' % i)
        out.append('        {')
        out.append('         int a[] = {%s};' % flat)
        out.append('         name = "%s"; start_ms = %d; first = %d; last = %d; duration = %d;' % (nm, start_ms, first, last, duration))
        out.append('         expected = "%s";' % tr)
        out.append('         ArrayResize(acts, ArraySize(a));')
        out.append('         for(int k = 0; k < ArraySize(a); k++)')
        out.append('            acts[k] = a[k];')
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
    test_pure_decisions()
    test_lifecycle_scenarios()
    print('')
    print('%d passed, %d failed' % (len(PASSES), len(FAILS)))
    if FAILS:
        for f in FAILS:
            print('  FAILED: ' + f)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
