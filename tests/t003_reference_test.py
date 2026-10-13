#!/usr/bin/env python3
"""T003 reference model and controlled-data tests (PROPOSED H4 bias rules).

IMPORTANT - what this file proves and what it does not:
  * It is a Python re-implementation (a MODEL) of the PROPOSED algorithm in
    tasks/T003-h4-bias-change.md revision 5. The tests verify THIS MODEL.
    They do NOT execute or compile the MQL5 source src/include/H4Bias.mqh.
  * src/tests/T003_LogicTest.mq5 runs the same cases inside MT5, but it has
    NOT been compiled and NOT been run (MetaEditor was not available).
    MQL5/Python equivalence is therefore UNPROVEN.
  * Every T003 rule is a developer PROPOSAL awaiting the client's visual
    validation. Nothing here is a client answer or a trading rule.
  * Controlled data only; no price, date or candle index of the client's
    pictures is used.
  * Deferred (printed as DEFERRED, never counted as PASS): task tests 9, 18,
    20 and the drawing/panel and M5/M15 items.

Every place where the task text is unclear is marked "AMBIGUITY n" in
src/include/H4Bias.mqh (list in its header); this model takes the same reading.
(AMBIGUITY 1, 5, 10, 11, 20 are also marked below.)

T002 code is reused unchanged (tests/t002_reference_test.py: swings, FVGs,
direction). Window indexes are used inside the replay only; identities,
comparisons and reports use absolute times and IDs built from them.

Usage:
  python3 tests/t003_reference_test.py              run all tests
  python3 tests/t003_reference_test.py --emit-mql   print the generated case
                                                    data block for the MQL5 test
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t002_reference_test as t2  # noqa: E402  (reused, not modified)

PERIOD = t2.PERIOD
T0 = t2.T0
Bar = t2.Bar
ts = t2.ts

BULL = 1
BEAR = -1

# event types
EV_BREAK_SET = 'BREAK_SET'
EV_FLIP = 'FLIP'
EV_SEED = 'SEED'
EV_CONFLICT = 'CONFLICT'
EV_WICK = 'WICK'
EV_NONE_WICK = 'NONE_WICK'
EV_RECONFIRMED = 'RECONFIRMED'
EV_RECONF_LOST = 'RECONF_LOST'
EV_INT_SWEEP = 'INTERNAL_SWEEP'
EV_CONTINUATION = 'CONTINUATION'
EV_INT_BREAK = 'INTERNAL_BREAK'
MARKET_TYPES = (EV_BREAK_SET, EV_FLIP, EV_SEED, EV_WICK, EV_RECONFIRMED,
                EV_RECONF_LOST, EV_INT_SWEEP)


# ------------------------------------------------------------- helpers ----
def tx(t):
    return '0' if t == 0 else ts(t)


def pf(x):
    # the MQL5 side uses DoubleToString(x, 2): refuse values on an exact rounding tie
    frac = x * 100.0 - math.floor(x * 100.0)
    if abs(frac - 0.5) < 1e-7:
        raise ValueError('price on a rounding tie: %r' % x)
    return '%.2f' % x


def dir_name(d):
    if d == BULL:
        return 'BULL'
    if d == BEAR:
        return 'BEAR'
    return 'NONE'


class Params(object):
    def __init__(self, left=2, right=2, period=PERIOD, lookback=300,
                 rebuild=1000, hard_cap=5000):
        self.left = left
        self.right = right
        self.period = period
        self.lookback = lookback
        self.rebuild = rebuild
        self.hard_cap = hard_cap


def warm_up(p):
    return p.lookback


def check_depth(p):
    return warm_up(p)


# ----------------------------------------------------- identities (P2) ----
# IDs are built from ABSOLUTE times only (pivot times). Window indexes never
# enter an ID. (Requirement a.)
def level_id(kind, t_level, t_ext, t_prev):
    return '%s%s_%s_%s' % (kind, ts(t_level), ts(t_ext), ts(t_prev))


def ext_id(kind, t_ext, t_prev):
    return '%s%s_%s' % (kind, ts(t_ext), ts(t_prev))


def interior_id(kind, t_int, t_ext):
    return '%s%s_%s' % (kind, ts(t_int), ts(t_ext))


def event_id(etype, bar_time, ref):
    return '%s@%s#%s' % (etype, ts(bar_time), ref)


class Cand(object):
    def __init__(self):
        self.id = ''
        self.price = 0.0
        self.pivot_time = 0
        self.ext_time = 0
        self.prev_time = 0
        self.known = 0
        self.idx = -1          # window index of the pivot: INTERNAL only


def known_count(sw, right, upto):
    """number of swings confirmed by the close of bar `upto` (window index)"""
    c = 0
    for s in sw:
        if s.index + right <= upto:
            c += 1
        else:
            break
    return c


def derive_level(sw, nk, d):
    """P2 / P14 candidates from the first nk swings, context direction d.
    d=+1 bullish context: extremes are highs, level is a low.
    d=-1 bearish context: extremes are lows, level is a high.
    Returns (level, ext, lint); each Cand or None.
    level: most adverse swing strictly between the previous extreme and the
           latest higher-high (bull) / lower-low (bear); ties -> earliest.
    ext:   the latest higher-high (bull) / lower-low (bear).
    lint:  most adverse swing after the pivot of ext (interior liquidity)."""
    ext_hi = (d > 0)
    exts = []
    oths = []
    for i in range(nk):
        if sw[i].is_high == ext_hi:
            exts.append(sw[i])
        else:
            oths.append(sw[i])
    k = -1
    for j in range(len(exts) - 1, 0, -1):
        if d * exts[j].price > d * exts[j - 1].price:
            k = j
            break
    if k < 0:
        return None, None, None
    e = exts[k]
    pe = exts[k - 1]
    ex = Cand()
    ex.id = ext_id('HH' if d > 0 else 'LL', e.pivot_time, pe.pivot_time)
    ex.price = e.price
    ex.pivot_time = e.pivot_time
    ex.prev_time = pe.pivot_time
    ex.known = e.confirm_time
    ex.idx = e.index
    best = None
    for s in oths:
        if pe.pivot_time < s.pivot_time and s.pivot_time < e.pivot_time:
            if best is None or d * s.price < d * best.price:
                best = s
    lvl = None
    lint = None
    if best is not None:
        lvl = Cand()
        lvl.id = level_id('SL' if d > 0 else 'SH', best.pivot_time, e.pivot_time, pe.pivot_time)
        lvl.price = best.price
        lvl.pivot_time = best.pivot_time
        lvl.ext_time = e.pivot_time
        lvl.prev_time = pe.pivot_time
        lvl.known = max(best.confirm_time, e.confirm_time)
        lvl.idx = best.index
        bi = None
        for s in oths:
            if s.pivot_time > e.pivot_time:
                if bi is None or d * s.price < d * bi.price:
                    bi = s
        if bi is not None:
            lint = Cand()
            lint.id = interior_id('IL' if d > 0 else 'IH', bi.pivot_time, e.pivot_time)
            lint.price = bi.price
            lint.pivot_time = bi.pivot_time
            lint.ext_time = e.pivot_time
            lint.known = bi.confirm_time
            lint.idx = bi.index
    return lvl, ex, lint


def adverse_ext(bar, s):
    return bar.high if s > 0 else bar.low


def scan_level(bars, i_from, i_to, price, s):
    """bars i_from..i_to: (body_broken, last wick index or -1).
    s = adverse sign (+1: above the level is adverse)."""
    wick = -1
    for i in range(i_from, i_to + 1):
        if s * (bars[i].close - price) > 0:
            return True, -1
        if s * (adverse_ext(bars[i], s) - price) > 0:
            wick = i
    return False, wick


def close_beyond_any(bars, i_from, i_to, price, s):
    for i in range(i_from, i_to + 1):
        if s * (bars[i].close - price) > 0:
            return True
    return False


# ---------------------------------------------------------------- state ----
class Track(object):
    def __init__(self, fi, fid):
        self.f = fi          # index into the FVG list: INTERNAL
        self.id = fid
        self.invalid = False
        self.recorded = False


class St(object):
    def __init__(self):
        self.dir = 0
        self.origin = 'NONE'
        self.none_reason = 'NO_EVIDENCE'
        self.phase = 'ACTIVE'
        self.recon_reason = ''
        self.bias_start = 0
        self.origin_ref = 0
        self.has_level = False
        self.lv_id = ''
        self.lv_price = 0.0
        self.lv_pivot = 0
        self.lv_ext = 0
        self.lv_prev = 0
        self.lv_known = 0
        self.frozen = False
        self.has_ext = False
        self.ex_id = ''
        self.ex_price = 0.0
        self.ex_consumed = False
        self.has_lint = False
        self.li_id = ''
        self.li_price = 0.0
        self.li_consumed = False
        self.has_wick = False
        self.wk_src = 0
        self.wk_known = 0
        self.wk_det = 0
        self.wk_retro = False
        self.sweep_time = 0
        self.src_time = 0
        self.wait_start = 0
        self.rec_id = ''
        self.pre = ''
        self.t2dir = 'UNKNOWN'


def wick_text(st):
    if not st.has_wick:
        return '-'
    return '%s/%s/%s/%d' % (tx(st.wk_src), tx(st.wk_known), tx(st.wk_det), 1 if st.wk_retro else 0)


def tracks_text(tracks):
    if not tracks:
        return '-'
    out = []
    for tr in tracks:
        if tr.invalid:
            sname = 'INVALID'
        elif tr.recorded:
            sname = 'RECORDED'
        else:
            sname = 'FRESH'
        out.append('%s:%s' % (tr.id, sname))
    return ','.join(out)


def state_key(st, tracks):
    """what replays A and B must agree on. No window index, no depth."""
    return ('BIAS=%s;PH=%s;ORG=%s;NR=%s;LV=%s;FRZ=%d;WK=%s;SW=%s;REC=%s;RSN=%s;EL=%s' % (
        dir_name(st.dir), st.phase if st.dir != 0 else '-', st.origin,
        st.none_reason if st.dir == 0 else '-',
        ('%s@%s' % (st.lv_id, pf(st.lv_price))) if st.has_level else '-',
        1 if st.frozen else 0, wick_text(st), tx(st.sweep_time),
        st.rec_id if st.rec_id else '-', st.recon_reason if st.recon_reason else '-',
        tracks_text(tracks)))


def hold_block(st):
    """S3 (client): new entries of the previous setup are blocked in HOLD"""
    return st.dir != 0 and st.phase == 'HOLD'


def sweep_block(st):
    """TECHNICAL PROPOSAL (F8, not a client statement): block during SWEEP_WAIT.
    A separate flag so the owner decides; nothing here acts on it."""
    return st.dir != 0 and st.phase == 'SWEEP_WAIT'


def state_text(st, tracks):
    return '%s;LI=%s;PRE=%s;T2=%s;BLKH=%d;BLKS=%d' % (
        state_key(st, tracks), st.li_id if st.has_lint else '-',
        st.pre if st.pre else '-', st.t2dir,
        1 if hold_block(st) else 0, 1 if sweep_block(st) else 0)


class Event(object):
    def __init__(self, etype, bar_time, ref, detail):
        self.type = etype
        self.bar_time = bar_time
        self.ref = ref
        self.detail = detail
        self.market = etype in MARKET_TYPES

    def id(self):
        return event_id(self.type, self.bar_time, self.ref)

    def text(self):
        return '%s{%s}' % (self.id(), self.detail)


class Rep(object):
    pass


# --------------------------------------------------------------- replay ----
def fvg_eligible(f, st, bull):
    """P5 / P14: type = bias direction, candle A open time at or after the source
    time (the physical wick bar, or the sweep bar). Not detected_at."""
    return f.bullish == bull and f.time_a >= st.src_time


def build_tracks(st, tracks, fv, bars, t, bull):
    """(re)build the eligible FVG tracks for the current wait (P5 / P14).
    Eligible: type = bias direction, candle A open >= src_time, C closed by t."""
    del tracks[:]
    for fi in range(len(fv)):
        f = fv[fi]
        if f.index_a + 2 > t:
            continue
        if not fvg_eligible(f, st, bull):
            continue
        tr = Track(fi, f.id)
        i = f.index_a + 3
        while i <= t:
            if f.bullish:
                if bars[i].close < f.lower:
                    tr.invalid = True
            else:
                if bars[i].close > f.upper:
                    tr.invalid = True
            i += 1
        tracks.append(tr)


def t2_dir_name(sw, nk):
    return t2.derive_direction(sw[:nk])


def origin_ref_of(open_t, cands):
    r = open_t
    for c in cands:
        for v in (c.pivot_time, c.ext_time, c.prev_time):
            if v != 0 and v < r:
                r = v
    return r


def p10_resolve(n_up, n_dn, seed_dir):
    """P10 precedence for one bar in NONE.
    Returns (result, direction): a break outranks the seed, breaks of both
    kinds give CONFLICT and the seed never overwrites a CONFLICT on that bar."""
    if n_up > 0 and n_dn > 0:
        return 'CONFLICT', 0
    if n_up > 0:
        return 'BREAK', BULL
    if n_dn > 0:
        return 'BREAK', BEAR
    if seed_dir != 0:
        return 'SEED', seed_dir
    return 'NONE', 0


def none_step(t, bars, sw, p, st, events):
    """P10: start from NONE only."""
    bar = bars[t]
    open_t = bar.time
    close_t = open_t + p.period
    nkb = known_count(sw, p.right, t - 1)
    nki = known_count(sw, p.right, t)
    hit = {1: [], -1: []}       # direction of the break -> triggering candidates
    for ctx in (BEAR, BULL):
        lvl, ex, lint = derive_level(sw, nkb, ctx)
        s = -ctx
        if lvl is not None:
            if not close_beyond_any(bars, lvl.idx + 1, t - 1, lvl.price, s):
                if s * (bar.close - lvl.price) > 0:
                    hit[s].append(lvl)
                elif s * (adverse_ext(bar, s) - lvl.price) > 0:
                    events.append(Event(EV_NONE_WICK, open_t, lvl.id,
                                        'lvl=%s;src=%s' % (lvl.id, ts(open_t))))
        if ex is not None:
            # favourable break of the latest HH (ctx=+1) / LL (ctx=-1)
            if not close_beyond_any(bars, ex.idx + 1, t - 1, ex.price, ctx):
                if ctx * (bar.close - ex.price) > 0:
                    hit[ctx].append(ex)
    up = hit[1]
    dn = hit[-1]
    # seed candidate (only used when step 1 produced neither a bias nor a conflict)
    seed_dir = 0
    seed_lvl = None
    t2n = t2_dir_name(sw, nki)
    if len(up) == 0 and len(dn) == 0 and (t2n == 'BEARISH' or t2n == 'BULLISH'):
        d = BULL if t2n == 'BULLISH' else BEAR
        lvl, ex, lint = derive_level(sw, nki, d)
        # AMBIGUITY 10: "defined" = not body-broken by a bar up to t-1 (P2 wording);
        # bar t closing beyond its own seed level is handled by the retroactive scan.
        if lvl is not None and not close_beyond_any(bars, lvl.idx + 1, t - 1, lvl.price, -d):
            seed_dir = d
            seed_lvl = lvl
    res, rdir = p10_resolve(len(up), len(dn), seed_dir)
    st.none_reason = 'NO_EVIDENCE'
    if res == 'CONFLICT':
        st.none_reason = 'CONFLICT'
        events.append(Event(EV_CONFLICT, open_t, '%s+%s' % (up[0].id, dn[0].id),
                            'up=%s;dn=%s' % (up[0].id, dn[0].id)))
        return
    if res == 'BREAK':
        d = rdir
        cands = up if d == BULL else dn
        st.dir = d
        st.origin = 'BREAK'
        st.phase = 'ACTIVE'
        st.bias_start = close_t
        st.origin_ref = origin_ref_of(open_t, cands)
        events.append(Event(EV_BREAK_SET, open_t, cands[0].id,
                            'dir=%s;from=NONE;known=%s;t002=%s' % (dir_name(d), ts(cands[0].known), t2n)))
        return
    if res == 'SEED':
        d = rdir
        refs = Cand()
        refs.pivot_time = seed_lvl.pivot_time
        refs.ext_time = seed_lvl.ext_time
        refs.prev_time = seed_lvl.prev_time
        # the swings the T002 direction used: last two highs and last two lows
        lo = open_t
        nh = 0
        nl = 0
        for i in range(nki - 1, -1, -1):
            if sw[i].is_high:
                if nh < 2:
                    nh += 1
                    if sw[i].pivot_time < lo:
                        lo = sw[i].pivot_time
            else:
                if nl < 2:
                    nl += 1
                    if sw[i].pivot_time < lo:
                        lo = sw[i].pivot_time
        st.dir = d
        st.origin = 'SEED'
        st.phase = 'ACTIVE'
        st.bias_start = close_t
        st.origin_ref = origin_ref_of(lo, [refs])
        events.append(Event(EV_SEED, open_t, seed_lvl.id,
                            'dir=%s;t002=%s' % (dir_name(d), t2n)))


def do_flip(t, bars, p, st, tracks, events):
    open_t = bars[t].time
    close_t = open_t + p.period
    old = st.dir
    ref = st.lv_id
    c = Cand()
    c.pivot_time = st.lv_pivot
    c.ext_time = st.lv_ext
    c.prev_time = st.lv_prev
    st.origin_ref = origin_ref_of(open_t, [c])
    st.dir = -old
    st.origin = 'BREAK'
    st.phase = 'ACTIVE'
    st.recon_reason = ''
    st.bias_start = close_t
    st.has_level = False
    st.lv_id = ''
    st.frozen = False
    st.has_ext = False
    st.has_lint = False
    st.has_wick = False
    st.wk_retro = False
    st.sweep_time = 0
    st.src_time = 0
    st.wait_start = 0
    st.rec_id = ''
    del tracks[:]
    events.append(Event(EV_FLIP, open_t, ref, 'dir=%s;from=%s;known=%s' % (
        dir_name(st.dir), dir_name(old), ts(st.lv_known))))


def start_hold(t, bars, p, fv, st, tracks, wk_src, wk_det, retro):
    """common part of every HOLD start (wick at t, restart, retroactive)"""
    st.phase = 'HOLD'
    st.frozen = True
    st.recon_reason = ''
    st.rec_id = ''
    st.has_wick = True
    st.wk_src = wk_src
    st.wk_known = wk_src + p.period
    st.wk_det = wk_det
    st.wk_retro = retro
    st.sweep_time = 0
    st.src_time = wk_src
    st.wait_start = wk_det
    st.has_ext = False
    st.has_lint = False
    build_tracks(st, tracks, fv, bars, t, st.dir == BULL)


def wick_event(open_t, st, restart):
    return Event(EV_WICK, open_t, st.lv_id,
                 'dir=%s;lvl=%s;sw=%s;sk=%s;det=%s;retro=%d;restart=%d' % (
                     dir_name(st.dir), st.lv_id, ts(st.wk_src), ts(st.wk_known),
                     ts(st.wk_det), 1 if st.wk_retro else 0, 1 if restart else 0))


def bias_step(t, bars, sw, fv, p, st, tracks, events):
    """step (2) of the order inside one bar. Returns True when the bias flipped."""
    bar = bars[t]
    open_t = bar.time
    close_t = open_t + p.period
    d = st.dir
    s = -d
    ph = st.phase
    if st.has_level:
        P = st.lv_price
        if s * (bar.close - P) > 0:
            do_flip(t, bars, p, st, tracks, events)
            return True
        if s * (adverse_ext(bar, s) - P) > 0:
            restart = (ph == 'HOLD' or ph == 'RECONFIRMED')
            start_hold(t, bars, p, fv, st, tracks, open_t, close_t, False)
            events.append(wick_event(open_t, st, restart))
            return False
    if ph != 'ACTIVE' and ph != 'SWEEP_WAIT':
        return False
    if st.has_ext and (not st.ex_consumed) and d * (bar.close - st.ex_price) > 0:
        st.ex_consumed = True
        events.append(Event(EV_CONTINUATION, open_t, st.ex_id,
                            'dir=%s;ext=%s' % (dir_name(d), st.ex_id)))
    if st.has_level and st.has_lint and (not st.li_consumed):
        if s * (bar.close - st.li_price) > 0:
            st.li_consumed = True
            events.append(Event(EV_INT_BREAK, open_t, st.li_id,
                                'dir=%s;lint=%s' % (dir_name(d), st.li_id)))
        elif s * (adverse_ext(bar, s) - st.li_price) > 0:
            restart = (ph == 'SWEEP_WAIT')
            st.phase = 'SWEEP_WAIT'
            st.sweep_time = open_t
            st.src_time = open_t
            st.wait_start = close_t
            st.rec_id = ''
            build_tracks(st, tracks, fv, bars, t, d == BULL)
            events.append(Event(EV_INT_SWEEP, open_t, st.li_id,
                                'dir=%s;lint=%s;sweep=%s;restart=%d' % (
                                    dir_name(d), st.li_id, ts(open_t), 1 if restart else 0)))
    return False


def dist_to_zone(f, price):
    if f.lower <= price and price <= f.upper:
        return 0.0
    if price < f.lower:
        return f.lower - price
    return price - f.upper


def sel_before(fa, da, fb, db):
    if da != db:
        return da < db
    if fa.confirm_time != fb.confirm_time:
        return fa.confirm_time > fb.confirm_time
    return fa.id < fb.id


def fvg_step(t, bars, fv, p, st, tracks, events):
    """step (3): FVG eligibility / invalidation / touch for bar t (revision 7).
    RECONFIRMED(INTERNAL) freezes the level known before bar t; when its FVG is lost the
    level thaws on this bar and the derive step (step 4) of the SAME bar re-derives it
    (used from bar t+1) unless another FVG is touched on this bar (frozen again)."""
    bar = bars[t]
    open_t = bar.time
    d = st.dir
    ph = st.phase
    if ph != 'HOLD' and ph != 'SWEEP_WAIT' and ph != 'RECONFIRMED':
        return
    # newly confirmed eligible FVG (candle C = bar t)
    a = t - 2
    if a >= 0:
        for fi in range(len(fv)):
            f = fv[fi]
            if f.index_a == a and fvg_eligible(f, st, d == BULL):
                tracks.append(Track(fi, f.id))
    for tr in tracks:
        f = fv[tr.f]
        if f.index_a + 3 > t:
            continue
        if not tr.invalid:
            if f.bullish:
                if bar.close < f.lower:
                    tr.invalid = True
            else:
                if bar.close > f.upper:
                    tr.invalid = True
    if st.phase == 'RECONFIRMED':
        for tr in tracks:
            if tr.recorded and tr.invalid:
                tr.recorded = False
                to = 'HOLD' if st.recon_reason == 'STRUCT' else 'SWEEP_WAIT'
                events.append(Event(EV_RECONF_LOST, open_t, tr.id,
                                    'fvg=%s;to=%s' % (tr.id, to)))
                if st.recon_reason == 'INTERNAL':
                    # THAW: the level was frozen by the internal reconfirmation only; the
                    # wait is open again. The derive step of THIS bar re-derives the level
                    # (from the closed bars up to t) for use from bar t+1.
                    st.frozen = False
                st.phase = to
                st.recon_reason = ''
                st.rec_id = ''
    if st.phase == 'HOLD' or st.phase == 'SWEEP_WAIT':
        best = None
        bestd = 0.0
        # AMBIGUITY 20a (revision 7): a touch while NO protecting level is defined is not
        # recorded (no trustworthy RECONFIRMED(INTERNAL) without a level to freeze); the
        # bar is not remembered and a later touch with a level can record. HOLD always has one.
        for tr in tracks:
            if st.phase == 'SWEEP_WAIT' and not st.has_level:
                break
            if tr.invalid:
                continue
            f = fv[tr.f]
            if f.index_a + 3 > t:
                continue
            if bar.time >= st.wait_start and bar.low <= f.upper and bar.high >= f.lower:
                dd = dist_to_zone(f, bar.close)
                if best is None or sel_before(f, dd, fv[best.f], bestd):
                    best = tr
                    bestd = dd
        if best is not None:
            reason = 'STRUCT' if st.phase == 'HOLD' else 'INTERNAL'
            if reason == 'INTERNAL':
                # FREEZE (P3): the level KNOWN BEFORE the touching candle stays; the derive
                # step of this bar is skipped (frozen), so a swing confirmed by the touching
                # candle cannot change the event's level. The continuation / interior
                # candidates are kept (not used while RECONFIRMED, refreshed at the thaw).
                st.frozen = True
            st.phase = 'RECONFIRMED'
            st.recon_reason = reason
            st.rec_id = best.id
            best.recorded = True
            events.append(Event(EV_RECONFIRMED, open_t, best.id,
                                'fvg=%s;reason=%s' % (best.id, reason)))


def derive_step(t, bars, sw, fv, p, st, tracks, events):
    """step (4): candidates for the NEXT bar from the prefix including bar t"""
    if st.dir == 0 or st.frozen:
        return
    open_t = bars[t].time
    d = st.dir
    s = -d
    nki = known_count(sw, p.right, t)
    lvl, ex, lint = derive_level(sw, nki, d)
    # latest HH/LL (continuation)
    if ex is None:
        st.has_ext = False
    else:
        st.has_ext = True
        st.ex_id = ex.id
        st.ex_price = ex.price
        st.ex_consumed = close_beyond_any(bars, ex.idx + 1, t, ex.price, d)
    # protecting level
    if lvl is None:
        st.has_level = False
        st.has_lint = False
        return
    if not (st.has_level and st.lv_id == lvl.id):
        body, wick_idx = scan_level(bars, lvl.idx + 1, t, lvl.price, s)
        if body:
            st.has_level = False
            st.has_lint = False
            return
        st.has_level = True
        st.lv_id = lvl.id
        st.lv_price = lvl.price
        st.lv_pivot = lvl.pivot_time
        st.lv_ext = lvl.ext_time
        st.lv_prev = lvl.prev_time
        st.lv_known = lvl.known
        if wick_idx >= 0:
            # retroactive wick: HOLD starts at detected_at, not at the wick
            wk_src = bars[wick_idx].time
            wk_known = wk_src + p.period
            det = max(lvl.known, wk_known, st.bias_start)
            start_hold(t, bars, p, fv, st, tracks, wk_src, det, det > wk_known)
            events.append(wick_event(open_t, st, False))
            return
    # interior liquidity (needs the protecting level)
    if lint is None:
        st.has_lint = False
    else:
        st.has_lint = True
        st.li_id = lint.id
        st.li_price = lint.price
        st.li_consumed = close_beyond_any(bars, lint.idx + 1, t, lint.price, s)


def process_bar(t, bars, sw, fv, p, st, tracks, events):
    if st.dir == 0:
        none_step(t, bars, sw, p, st, events)
    else:
        flipped = bias_step(t, bars, sw, fv, p, st, tracks, events)
        if not flipped:
            fvg_step(t, bars, fv, p, st, tracks, events)
    derive_step(t, bars, sw, fv, p, st, tracks, events)


def pre_wick_ids(st, fv, n):
    """FVGs of the bias type that are older than the wick: reporting only"""
    if st.dir == 0 or st.src_time == 0 or st.phase == 'ACTIVE':
        return ''
    ids = []
    cnt = 0
    for k in range(len(fv) - 1, -1, -1):
        f = fv[k]
        if f.index_a + 2 > n - 1:
            continue
        if f.bullish != (st.dir == BULL):
            continue
        if f.time_a < st.src_time:
            cnt += 1
            if len(ids) < 6:
                ids.append(f.id)
    if cnt == 0:
        return ''
    extra = ''
    if cnt > len(ids):
        extra = '+%d' % (cnt - len(ids))
    return '%s%s' % (','.join(ids), extra)


def replay(bars, n, p):
    rep = Rep()
    rep.events = []
    rep.tracks = []
    st = St()
    sw, amb = t2.find_swings(bars, n, p.left, p.right, p.period)
    fv = t2.find_fvgs(bars, n, p.period)
    rep.key_before_last = ''
    rep.keys = []
    for t in range(n):
        if t == n - 1:
            rep.key_before_last = state_key(st, rep.tracks)
        process_bar(t, bars, sw, fv, p, st, rep.tracks, rep.events)
        rep.keys.append(state_key(st, rep.tracks))
    if n > 0:
        nkf = known_count(sw, p.right, n - 1)
        st.t2dir = t2_dir_name(sw, nkf)
    st.pre = pre_wick_ids(st, fv, n)
    rep.state = st
    rep.n = n
    rep.last_time = bars[n - 1].time if n > 0 else 0
    return rep


def bar_index_by_time(bars, n, t):
    """index of the bar that OPENS at exactly t in bars[0..n-1] (chronological), or -1"""
    lo = 0
    hi = n - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        if bars[mid].time == t:
            return mid
        if bars[mid].time < t:
            lo = mid + 1
        else:
            hi = mid - 1
    return -1


def anchor_refs(st):
    """absolute reference times the state depends on (AMBIGUITY 5). Frozen states (HOLD,
    RECONFIRMED): the source wick, the frozen level's pivots (if a level exists) and the
    sweep that started an internal wait (RECONFIRMED(INTERNAL) only); origin ignored."""
    refs = []
    if st.frozen:
        refs = [st.wk_src] if st.has_wick else []
        if st.has_level:
            refs += [st.lv_pivot, st.lv_ext, st.lv_prev]
        refs.append(st.sweep_time)
    else:
        refs = [st.origin_ref]
        if st.has_level:
            refs += [st.lv_pivot, st.lv_ext, st.lv_prev]
        if st.sweep_time != 0:
            refs.append(st.sweep_time)
    return [r for r in refs if r != 0]


def anchor_time(st, p, bars, n):
    """FINDING 1: earliest bar time the state depends on, by EXISTING bars.
    Each reference is located by its absolute open time in the chronological series
    bars[0..n-1]; the bars that confirm it are the p.left EXISTING bars before it (index
    based, converted back to the absolute open time of that bar). Weekends and holes
    in the history therefore never produce a time that is not a bar.
    Returns (anchor, missing): anchor = 0 when not applicable (NONE, no reference) or
    when the history lacks a needed bar; missing = '' or the reason (reference not found
    in the series / fewer than left bars before it). Nothing is ever fabricated."""
    if st.dir == 0:
        return 0, ''
    a = 0
    for r in anchor_refs(st):
        i = bar_index_by_time(bars, n, r)
        if i < 0:
            return 0, 'ANCHOR_REF_NOT_IN_SERIES %s' % ts(r)
        if i < p.left:
            return 0, 'ANCHOR_NEEDS_%d_BARS_BEFORE %s' % (p.left, ts(r))
        c = bars[i - p.left].time
        if a == 0 or c < a:
            a = c
    return a, ''


def events_text(events, t_from):
    out = []
    for e in events:
        if e.bar_time >= t_from:
            out.append(e.text())
    if not out:
        return '-'
    return '|'.join(out)


def replay_text(rep):
    return 'REPLAY;ST=%s;EV=%s' % (state_text(rep.state, rep.tracks), events_text(rep.events, 0))


# ----------------------------------------------------------- P11 evaluate ----
FLAG_CONVERGED = 'CONVERGED'
FLAG_SEEDED = 'SEEDED'
FLAG_LIMITED = 'LIMITED_BY_HISTORY'


class Eval(object):
    pass


def ab_reasons(key_a, key_b, ev_text_a, ev_text_b, dir_a, anchor_a, trusted_a, anchor_missing=''):
    """P11 (ii)/(iii): why a rebuild is not reliable ('' = reliable).
    ev_text_* are the events dated inside B's trusted region only.
    anchor_missing != '': the history lacks a bar the anchor needs (FINDING 1)."""
    why = []
    if key_a != key_b:
        why.append('AB_STATE_DIFF')
    if ev_text_a != ev_text_b:
        why.append('AB_EVENT_DIFF')
    if dir_a != 0 and anchor_missing != '':
        why.append('ANCHOR_HISTORY_MISSING')
    elif dir_a != 0 and anchor_a < trusted_a:
        why.append('ANCHOR_IN_WARMUP')
    return '+'.join(why)


def consumer_prev_ok(cur_reliable, prev_reliable, cur_key_prev, prev_key):
    """the state before the latest bar counts only if it was RELIABLE and the
    current window reproduces it"""
    return cur_reliable and prev_reliable and cur_key_prev == prev_key


def evaluate(bars_all, n_avail, p):
    """Stateless fixed-depth rebuild with the A/B depth check (P11).
    Only bars_all[0..n_avail-1] are read."""
    ev = Eval()
    ev.r_request = p.rebuild
    ev.r_req = max(p.rebuild, 3 * p.lookback)
    ev.r_eff = min(ev.r_req, p.hard_cap, n_avail)
    ev.warm = warm_up(p)
    ev.chk = check_depth(p)
    ev.b_depth = 0
    ev.reliable = False
    ev.flag = FLAG_LIMITED
    ev.reason = ''
    ev.note = ''
    ev.events = []
    ev.key = ''
    ev.key_prev = ''
    ev.state = None
    ev.tracks = []
    ev.last_time = 0
    ev.prev_ok = False
    ev.cause = ''
    ev.anchor = 0
    ev.anchor_missing = ''
    ev.n_avail = n_avail
    ev.trusted_from = 0
    notes = []
    if p.rebuild < 3 * p.lookback:
        notes.append('R raised to 3*L %d' % ev.r_req)
    if ev.r_req > p.hard_cap:
        notes.append('request %d clamped to HARD_CAP %d' % (ev.r_req, p.hard_cap))
    if n_avail <= 0:
        ev.reason = 'NO_BARS'
        ev.note = ';'.join(notes)
        return ev
    if n_avail < min(ev.r_req, p.hard_cap):
        notes.append('reduced depth %d of %d' % (ev.r_eff, ev.r_req))
    ev.note = ';'.join(notes)
    if ev.r_eff < 3 * p.lookback:
        ev.reason = 'SHORT_HISTORY'
        return ev
    startA = n_avail - ev.r_eff
    winA = bars_all[startA:n_avail]
    repA = replay(winA, ev.r_eff, p)
    ev.b_depth = ev.r_eff - ev.chk
    winB = bars_all[n_avail - ev.b_depth:n_avail]
    repB = replay(winB, ev.b_depth, p)
    trB = winB[ev.warm].time
    trA = winA[ev.warm].time
    keyA = state_key(repA.state, repA.tracks)
    keyB = state_key(repB.state, repB.tracks)
    # the anchor is located in the FULL available series (not only in window A)
    ev.anchor, ev.anchor_missing = anchor_time(repA.state, p, bars_all, n_avail)
    why = ab_reasons(keyA, keyB, events_text(repA.events, trB), events_text(repB.events, trB),
                     repA.state.dir, ev.anchor, trA, ev.anchor_missing)
    if ev.anchor_missing != '':
        ev.note = (ev.note + ';' if ev.note else '') + 'missing history: ' + ev.anchor_missing
    ev.state = repA.state
    ev.tracks = repA.tracks
    ev.key = keyA
    ev.key_prev = repA.key_before_last
    ev.last_time = repA.last_time
    ev.trusted_from = trB
    if why == '':
        ev.reliable = True
        if repA.state.dir != 0 and repA.state.origin == 'SEED' and not repA.state.frozen:
            ev.flag = FLAG_SEEDED
        else:
            ev.flag = FLAG_CONVERGED
        ev.reason = 'converged at depth %d vs %d' % (ev.r_eff, ev.b_depth)
        ev.events = repA.events
    else:
        ev.flag = FLAG_LIMITED
        ev.reason = why
        ev.events = []
    return ev


def reported_direction(ev):
    if not ev.reliable:
        return 'UNKNOWN'
    return dir_name(ev.state.dir)


def eval_text(ev):
    s = 'EVAL;FLAG=%s;REASON=%s;DIR=%s;DEPTHS=req:%d,eff:%d,b:%d,warm:%d,chk:%d;ANCH=%s;NOTE=%s' % (
        ev.flag, ev.reason, reported_direction(ev), ev.r_req, ev.r_eff, ev.b_depth,
        ev.warm, ev.chk, tx(ev.anchor), ev.note if ev.note else '-')
    if ev.reliable:
        s += ';ST=%s;EV=%s' % (state_text(ev.state, ev.tracks), events_text(ev.events, 0))
    elif ev.state is not None:
        s += ';DIAG=%s' % ev.key
    return s


def evaluate_latest(bars_all, n, p):
    """evaluation at the last bar plus the check of the state before it"""
    cur = evaluate(bars_all, n, p)
    prev = evaluate(bars_all, n - 1 if n > 1 else 0, p)
    cur.prev_ok = consumer_prev_ok(cur.reliable, prev.reliable, cur.key_prev, prev.key)
    cur.cause = ''
    if cur.reliable and not prev.reliable:
        cur.cause = 'REDERIVATION:LIMITED_EXIT'
    elif (not cur.reliable) and prev.reliable:
        cur.cause = 'REDERIVATION:LIMITED_ENTER'
    elif cur.reliable and prev.reliable and cur.key_prev != prev.key:
        if cur.r_eff != prev.r_eff:
            cur.cause = 'REDERIVATION:DEPTH_CHANGED'
        else:
            cur.cause = 'REDERIVATION:WINDOW_SLID'
    return cur


# consumer (requirement b): cursor = open time of the last bar already consumed
C_OK = 'OK'
C_NOTHING_NEW = 'NOTHING_NEW'
C_NOT_RELIABLE = 'NOT_RELIABLE'
C_REDERIVED = 'REDERIVED'
C_GAP = 'GAP'


def baseline_cursor(ev):
    return ev.last_time


def consume_new(ev, cursor, period):
    """returns (status, [events newer than the cursor]). Events are returned
    only for the latest closed bar and only when the state before and after
    it are both RELIABLE and A/B agree (ev.prev_ok from evaluate_latest)."""
    if not ev.reliable:
        return C_NOT_RELIABLE, []
    if cursor >= ev.last_time:
        return C_NOTHING_NEW, []
    if cursor == 0 or cursor < ev.last_time - period:
        return C_GAP, []
    if not ev.prev_ok:
        return C_REDERIVED, []
    out = []
    for e in ev.events:
        if e.bar_time > cursor:
            out.append(e)
    return C_OK, out


# ================================================================ builders ====
import math  # noqa: E402

HW = 5.0
MIRROR = t2.MIRROR


class Series(object):
    """Controlled-data bar builder. A bar is centre +/- HW, close = centre,
    unless an explicit (high, low, close) row is given. Swing prices are
    centre +/- HW. Steps of at most 4 never create an FVG (gap between A and
    C needs more than 2*HW)."""

    def __init__(self, start, hw=HW):
        self.rows = []
        self.c = start
        self.hw = hw
        self.rows.append((start + hw, start - hw, float(start)))

    def to(self, target, step=4.0):
        k = int(math.ceil(abs(target - self.c) / step))
        c0 = self.c
        for j in range(1, k + 1):
            c = c0 + (target - c0) * j / float(k)
            self.rows.append((c + self.hw, c - self.hw, c))
        self.c = target
        return self

    def pts(self, lst):
        for c in lst:
            self.rows.append((c + self.hw, c - self.hw, float(c)))
            self.c = c
        return self

    def bar(self, h, l, c):
        self.rows.append((float(h), float(l), float(c)))
        return self

    def n(self):
        return len(self.rows)

    def bars(self):
        out = []
        for i in range(len(self.rows)):
            r = self.rows[i]
            out.append(Bar(T0 + i * PERIOD, float(r[0]), float(r[1]), float(r[2])))
        return out


def mirror(bars):
    return t2.mirror(bars)


def set_c(s, c):
    s.c = c
    return s


def pad(s, k):
    """k quiet alternating bars around the current centre: no swing, no FVG"""
    c0 = s.c
    for i in range(k):
        s.pts([c0 + (4 if i % 2 == 0 else 0)])
    s.c = c0
    return s


# ------------------------------------------------------------ scenarios ----
def bear_leg():
    """BEAR template: H0 125, L0 95, S 117, down leg with two bearish FVGs, L1 73
    (pivot at index 23). T002 turns BEARISH when L1 is confirmed -> SEED."""
    s = Series(90).to(120).to(100).to(112)
    s.pts([108, 106, 96, 86, 86, 82, 78])
    return s


def bear_rally():
    return bear_leg().to(108)


def sc_wick_family(kind):
    s = bear_rally()
    if kind == 'break':
        s.bar(119, 108, 118)
    elif kind == 'wick':
        s.bar(120, 106, 110)
    elif kind == 'eqclose':
        s.bar(118, 106, 117)
    elif kind == 'eqhigh':
        s.bar(117, 106, 112)
    elif kind == 'eqboth':
        s.bar(117, 106, 117)
    elif kind == 'pre_touched':
        s.bar(120, 106, 110)
        s.pts([106, 102, 98, 94, 90, 86, 82, 86, 90, 94, 96])
    elif kind == 'a_is_wick':
        s.bar(120, 108, 112)
        s.bar(111, 101, 106)
        s.bar(105, 95, 100)
        s.pts([96, 92, 88, 92, 96])
        s.bar(106, 94, 100)
        s.pts([98, 96])
    elif kind == 'a_before_wick':
        s.bar(120, 100, 104)
        s.bar(101, 91, 96)
        s.bar(101, 89, 94)
        s.pts([90, 86, 90, 94])
        s.bar(104, 98, 100)
        s.pts([98, 96])
    elif kind == 'invalid_same_bar':
        s.bar(120, 108, 112)
        s.bar(111, 101, 106)
        s.bar(105, 95, 100)
        s.pts([96, 92, 88, 92, 96])
        s.bar(112, 104, 110)
        s.pts([108, 104])
    elif kind == 'second_wick_hold':
        s.bar(120, 108, 112)
        s.bar(111, 101, 106)
        s.bar(105, 95, 100)
        s.pts([96, 92])
        s.bar(119, 95, 100)
        s.pts([98, 96])
    elif kind == 'second_wick_reconf':
        s.bar(120, 108, 112)
        s.bar(111, 101, 106)
        s.bar(105, 95, 100)
        s.pts([96, 92])
        s.to(108)
        s.bar(119, 107, 111)
        s.pts([106, 102])
    elif kind == 'invalid_before_touch':
        s.bar(120, 108, 112)
        s.bar(111, 101, 106)
        s.bar(105, 95, 100)
        s.pts([96, 92, 90])
        s.bar(115, 103, 113)
        s.pts([110, 108])
    elif kind == 'invalid_after_reconf':
        s.bar(120, 108, 112)
        s.bar(111, 101, 106)
        s.bar(105, 95, 100)
        s.pts([96, 92, 88, 92, 96])
        s.bar(106, 94, 100)
        s.pts([98, 100])
        s.bar(112, 100, 110)
        s.pts([108, 104])
    elif kind == 'break_in_hold':
        s.bar(120, 108, 112)
        s.bar(111, 101, 106)
        s.bar(105, 95, 100)
        s.pts([96, 92])
        s.bar(121, 109, 119)
        s.pts([115, 112])
    elif kind == 'break_in_reconf':
        s.bar(120, 108, 112)
        s.bar(111, 101, 106)
        s.bar(105, 95, 100)
        s.pts([96, 92, 88, 92, 96])
        s.bar(106, 94, 100)
        s.pts([98, 100])
        s.bar(122, 100, 119)
        s.pts([115, 112])
    return s.bars()


def sc_correction():
    s = bear_leg().to(98)
    s.to(86)
    s.to(94)
    s.pts([92, 90])
    return s.bars()


def sc_minor_swings():
    s = Series(90).to(120).to(100).to(112)
    s.pts([108, 106, 106, 110])          # plateau dip (no swing low), minor high 115
    s.to(78)                              # L1
    s.to(88).to(84).to(92)                # corrective bounce / higher low
    s.pts([90, 88])
    return s.bars()


def sc_no_bound():
    s = Series(90).to(120).to(100).to(112).to(104)
    s.pts([106, 108])
    return s.bars()


def sc_consumed_before_known():
    s = bear_leg()
    s.bar(119, 88, 118)            # p+1: body close above S before L1 is confirmed
    s.bar(100, 83, 90)
    s.pts([88, 86])
    return s.bars()


def sc_seed_bar_closes_beyond():
    s = bear_leg()
    s.bar(100, 83, 90)             # p+1
    s.bar(119, 84, 118)            # p+2 confirms L1 and closes above S itself
    s.pts([114, 110])
    return s.bars()


def sc_case_a(kind):
    """NONE until the break: one high only, so T002 stays UNKNOWN"""
    s = Series(100).to(90).to(112).to(85).to(106)
    if kind == 'break':
        s.bar(121, 110, 119)
    elif kind == 'wick_then_break':
        s.bar(125, 104, 106)
        s.pts([102, 98, 94])
        s.bar(121, 110, 119)
        s.pts([116, 112])
    elif kind == 'wick_only':
        s.bar(125, 104, 106)
        s.pts([102, 98])
    elif kind == 'equal_close':
        s.bar(121, 110, 117)
    return s.bars()


def sc_b2_active(kind):
    s = Series(90).to(120).to(100).to(112)
    s.pts([108, 106, 96, 86, 86, 82, 78])
    s.to(100)
    s.pts([96, 92, 88, 84, 80, 76, 72, 68, 64])
    if kind == 'retro':
        s.bar(112, 62, 100)
    else:
        s.bar(112, 62, 107)           # body close beyond the candidate before it is known
    s.bar(100, 63, 70)
    s.pts([72, 74])
    return s.bars()


def sc_b2_none(kind):
    s = Series(100).to(90).to(112).to(85).to(106)
    s.bar(125, 108, 112)
    s.bar(111, 101, 106)
    s.bar(105, 95, 100)
    s.pts([96, 96])
    s.pts([100])
    s.bar(106, 94, 100)
    s.pts([104, 108, 104, 100])
    if kind == 'untouched':
        s.pts([96, 92, 88])
    elif kind == 'touched':
        s.pts([96, 92, 88, 92, 96])
        s.bar(106, 94, 100)
        s.pts([98])
    elif kind == 'body_before':
        pass
    return s.bars()


def sc_case_c(padn=0, front=False):
    s = Series(110)
    pad(s, padn)
    s.to(100).to(112).to(90).to(108)
    s.bar(122, 110, 119)
    set_c(s, 119)
    s.to(126).to(114).to(132).to(140).to(128).to(136).to(130)
    s.pts([132, 134])
    return s


def sc_case_d(kind):
    s = Series(85).to(75).to(95).pts([93, 93]).to(105).to(90).to(100).to(80)
    s.pts([84])
    if kind == 'break':
        s.bar(114, 82, 112)
    elif kind == 'seed':
        s.bar(104, 82, 103)
    return s.bars()


def sc_no_evidence():
    return Series(100).to(90).to(112).to(85).to(100).bars()


def sc_e(kind):
    s = sc_case_c()
    if kind == 'cont':
        s.bar(150, 134, 148)
    elif kind == 'int_break':
        s.bar(133, 118, 121)
    elif kind == 'flip':
        s.bar(133, 104, 106)
        set_c(s, 106)
        s.pts([110, 114, 118, 122, 126])
    elif kind == 'no_level_crash':
        s.bar(133, 104, 106)
        set_c(s, 106)
        s.pts([100, 92, 84, 76, 70])
    elif kind == 'wick_struct':
        s.bar(135, 107, 120)
    elif kind == 'sweep_fvg_touch':
        s.bar(135, 118, 130)
        s.bar(142, 129, 138)
        s.bar(148, 139, 143)
        s.pts([141])
        s.bar(140, 130, 136)
        s.pts([138])
    return s.bars()


def sc_hh_below_level():
    """BEAR bias with S=117; a later higher high H3 (109) exists, a close above it is
    NOT a flip (only the protecting level flips) but an INTERNAL_BREAK observation"""
    s = bear_leg().to(98)
    s.to(90).to(104).to(96)
    s.bar(114, 100, 112)
    s.pts([108, 104])
    return s.bars()


def sc_no_level_no_sweep():
    """break of the HH candidate sets BULL with NO protecting low (plateau below the
    HH); a sweep-like bar afterwards must raise nothing because S_low is undefined"""
    s = Series(85).to(75).to(95).pts([93, 93]).to(105).to(90).to(100).to(80)
    s.pts([84])
    s.bar(114, 82, 112)
    set_c(s, 112)
    s.pts([114])
    s.bar(122, 70, 80)             # low below the lowest low after the HH, close above it
    set_c(s, 80)
    s.pts([78, 76, 74])
    return s.bars()


def sc_bos(k):
    """k successive breaks (no fixed count): bull run with k up-legs"""
    s = Series(110).to(100).to(112).to(90).to(108)
    s.bar(122, 110, 119)
    set_c(s, 119)
    top = 126
    low = 114
    for j in range(k - 1):
        s.to(top).to(low).to(top + 6)
        top += 14
        low += 14
    s.to(top).to(top - 10)
    s.pts([top - 8, top - 6])
    return s.bars()


def sc_thaw_family(kind):
    """Revision 7 scenarios (SELL). Prefix: bear_leg().to(100).to(88) (level 117, interior high
    105 at bar 29). Bar 33 sweeps the interior high (high 111 > 105, close 95 <= 105). Every
    kind below keeps bars 0..32 identical."""
    s = bear_leg().to(100).to(88)
    two = kind in ('recon_two_fvg', 'recon_two_fvg_ctl')
    if kind.startswith('recon_nolevel'):
        # a touch while no protecting level is defined (body close above the new candidate 111)
        s.bar(111, 90, 95)             # 33 sweep
        s.bar(92, 86, 88)              # 34
        s.bar(87, 80, 83)              # 35: FVG [87,90] (A=33, C=35)
        s.bar(86, 76, 80)              # 36: does not reach the FVG
        set_c(s, 80)
        s.to(60)                       # fall, new lower low (low 55 at the last bar)
        if kind == 'recon_nolevel':
            s.bar(115, 56, 113)        # closes above 111: candidate level rejected, FVG invalid
        else:
            s.bar(110, 56, 109)        # control: stays below 111, the level 111 is defined
        s.bar(112 if kind == 'recon_nolevel' else 110, 100, 108)
        s.bar(107, 98, 100)            # A of a new bearish FVG
        s.bar(99, 90, 92)
        s.bar(89, 80, 85)              # C: FVG [89,98]
        s.bar(95, 84, 90)              # touches the new FVG (level undefined / defined)
        s.pts([88])
        return s
    if two:
        s.bar(111, 90, 95)             # 33 sweep (A of FVG2 [87,90])
        s.bar(92, 84, 88)              # 34 (A of FVG1)
        s.bar(87, 78, 82)              # 35: FVG2 = [87,90]
        s.bar(83, 76, 80)              # 36: FVG1 = [83,84]
        s.bar(85, 79, 83.5)            # 37: touches FVG1 only (high 85 < 87): RECONFIRMED
        set_c(s, 80)
        upper_close = 84
    else:
        s.bar(111, 90, 95)             # 33 sweep
        s.bar(92, 86, 88)              # 34
        s.bar(87, 80, 83)              # 35: FVG [87,90]
        s.bar(91, 79, 82)              # 36: touches it (wide bar): RECONFIRMED(INTERNAL), level 117
        set_c(s, 82)
        upper_close = 90
    s.to(60)                           # new lower low (pivot at the last bar, low 55)
    s.to(80)                           # rally with closes at or below the FVG's upper edge
    s.bar(95, 80, 84)                  # interior high 95 (swing high)
    s.bar(90, 78, 80)
    s.bar(88, 76, 78)
    # T: closes above the recorded FVG's upper edge (invalidated) -> thaw bar
    if two:
        s.bar(93, 80, 88)              # T: also touches FVG2 (close 88 <= 90): frozen again
    else:
        s.bar(93, 82, 92)              # T: close 92 > 90
    # T+1
    if kind in ('recon_thaw', 'recon_two_fvg', 'recon_two_fvg_ctl'):
        s.bar(92, 84, 90)
    elif kind == 'recon_thaw_wick':
        s.bar(112, 90, 100)            # high above the level re-derived at T (111)
    elif kind == 'recon_thaw_break':
        s.bar(114, 90, 113)            # body close above the level re-derived at T (111)
    elif kind == 'recon_thaw_cont':
        s.bar(92, 40, 50)              # close below the latest lower low (55): CONTINUATION
    elif kind == 'recon_thaw_isweep':
        s.bar(100, 88, 93)             # high above the interior high 95, close below it
    elif kind == 'recon_thaw_ibreak':
        s.bar(100, 88, 98)             # close above the interior high 95, below the level
    return s


def sc_bear_sweep(kind):
    s = bear_leg().to(100).to(88)
    if kind == 'sweep_fvg_touch':
        s.bar(111, 99, 103)
        s.bar(100, 90, 94)
        s.bar(95, 85, 90)
        s.pts([88, 86])
        s.bar(100, 92, 96)
        s.pts([94])
    elif kind == 'restart':
        s.bar(111, 99, 103)
        s.pts([100, 96, 92])
        s.bar(112, 100, 104)
        s.pts([100])
    elif kind == 'wick_instead':
        s.bar(120, 100, 108)
    elif kind == 'break_instead':
        s.bar(121, 100, 119)
    elif kind == 'int_break':
        s.bar(113, 100, 110)
    elif kind == 'wait_wick':
        s.bar(111, 99, 103)
        s.bar(120, 100, 108)
    elif kind == 'wait_break':
        s.bar(111, 99, 103)
        s.bar(121, 100, 119)
    elif kind == 'no_level_after_flip':
        s.bar(121, 100, 119)
        set_c(s, 119)
        s.pts([110, 104, 98, 92, 86])
    elif kind in ('recon_wick', 'recon_break'):
        # FINDING 2 (c): the same sweep -> FVG -> touch as sweep_fvg_touch, then a wick
        # (high 120 > 117, close 108) / a body break (close 119 > 117) during RECONFIRMED(INTERNAL)
        s.bar(111, 99, 103)
        s.bar(100, 90, 94)
        s.bar(95, 85, 90)
        s.pts([88, 86])
        s.bar(100, 92, 96)
        s.pts([94])
        if kind == 'recon_wick':
            s.bar(120, 100, 108)
        else:
            s.bar(121, 100, 119)
    elif kind == 'recon_touch_swing':
        # FINDING 2 (a): bar 38 touches the FVG AND confirms a new lower low (pivot at 36,
        # confirmed by the touching candle). The level known before the touch (117) stays.
        s.bar(111, 99, 103)
        s.bar(100, 90, 94)
        s.bar(95, 85, 90)
        s.bar(90, 60, 65)
        s.bar(80, 68, 75)
        s.bar(100, 80, 96)
        s.pts([94])
    elif kind == 'recon_later_swing':
        # FINDING 2 (a): the touch is on bar 38; a new lower low (pivot 48) is confirmed long
        # after the reconfirmation and would replace the level (117 -> 100) if unfrozen.
        s.bar(111, 99, 103)
        s.bar(100, 90, 94)
        s.bar(95, 85, 90)
        s.pts([88, 86])
        s.bar(100, 92, 96)
        s.pts([94])
        s.to(60).to(80)
    elif kind.startswith('recon_thaw') or kind.startswith('recon_nolevel') or kind == 'recon_two_fvg':
        s = sc_thaw_family(kind)
    return s.bars()


# ---- P11 scenarios (lookback 20)
def sc16_converged_break():
    return sc_case_c(24).bars()


def sc16_converged_seed():
    s = Series(95)
    pad(s, 24)
    for t in (85, 100, 90, 105, 95, 110, 100, 115, 105, 120, 110, 125, 115, 130, 120):
        s.to(t, step=5.0)
    s.c = 120
    pad(s, 6)
    return s.bars()


def sc16_ab_diff():
    s = sc_case_c(8)
    s.to(132).to(116).to(122).pts([118, 114])
    s.bar(118, 104, 112)
    s.pts([114, 116])
    s.c = 116
    pad(s, 4)
    return s.bars()


def sc16_event_only():
    """older bear seed (outside B) then a new structure and a break above its level:
    A flips (FLIP), B starts from NONE (BREAK_SET): same final state, different event"""
    s = Series(100)
    s.to(130, 5.0).to(110, 5.0).to(125, 5.0).to(100, 5.0)
    s.to(105, 5.0)
    s.to(85, 5.0)
    s.to(112, 5.0)
    s.to(70, 5.0)
    s.to(108, 5.0)
    s.bar(122, 110, 119)
    s.c = 119
    pad(s, 12)
    return s.bars()


def sc16_anchor_warmup():
    s = Series(95)
    for t in (85, 100, 90, 105, 95, 110, 100, 115, 105, 120, 110, 125, 115, 130, 120):
        s.to(t, step=5.0)
    s.c = 120
    pad(s, 25)
    return s.bars()


def sc16_limit():
    s = Series(100)
    for t in (60, 100, 70, 150):
        s.to(t, step=5.0)
    s.to(140, step=5.0)
    s.c = 140
    pad(s, 60)
    for t in (148, 130, 142, 115, 125):
        s.to(t, step=5.0)
    s.c = 125
    pad(s, 22)
    return s.bars()


def sc17_first_event_at_3l():
    """exactly 3*L = 60 bars; the 60th bar is a real break. The state before it
    is built from 59 bars (< 3*L): LIMITED, so the event must NOT be emitted."""
    s = Series(100)
    pad(s, 36)
    s.to(90).to(112).to(85).to(106)
    s.bar(121, 110, 119)
    return s.bars()


def sc17_quiet_tail():
    return sc_case_c(24).bars()


def sc_consumer_series():
    """converged BULL ACTIVE series (n = 64), the 65th bar is a structural wick"""
    s = sc_case_c(24)
    return s


# ----------------------------------------------------------- case table ----
def retime(bars, slots):
    """same prices, new open times: slots[i] = number of 4h periods after T0 (strictly increasing).
    Used for weekend and history-gap cases (FINDING 1)."""
    assert len(slots) == len(bars)
    return [Bar(T0 + slots[i] * PERIOD, b.high, b.low, b.close) for i, b in enumerate(bars)]


def weekend_slots(n, start_pos):
    """H4 bars Monday..Friday (6 per day = 30 per week) with the weekend missing:
    trading position p = start_pos + i maps to week (p // 30) * 42 + p % 30 slots after
    Monday 00:00 (T0 is a Monday). The last bar of a week opens Friday 20:00, the next
    one Monday 00:00 (12 empty slots in between)."""
    return [((start_pos + i) // 30) * 42 + (start_pos + i) % 30 for i in range(n)]


class Case(object):
    def __init__(self, name, kind, bars, lookback=20, rebuild=1000, hard_cap=5000, n_use=None):
        self.name = name
        self.kind = kind          # 'R' raw replay, 'E' evaluate
        self.bars = bars
        self.lookback = lookback
        self.rebuild = rebuild
        self.hard_cap = hard_cap
        self.n_use = len(bars) if n_use is None else n_use

    def params(self):
        return Params(lookback=self.lookback, rebuild=self.rebuild, hard_cap=self.hard_cap)


def run_case(c):
    p = c.params()
    if c.kind == 'R':
        return replay_text(replay(c.bars, c.n_use, p))
    return eval_text(evaluate(c.bars, c.n_use, p))


WICK_KINDS = ('break', 'wick', 'eqclose', 'eqhigh', 'eqboth', 'pre_touched', 'a_is_wick',
              'a_before_wick', 'invalid_same_bar', 'second_wick_hold', 'second_wick_reconf',
              'invalid_before_touch', 'invalid_after_reconf', 'break_in_hold', 'break_in_reconf')
SWEEP_KINDS = ('sweep_fvg_touch', 'restart', 'wick_instead', 'break_instead', 'int_break',
               'wait_wick', 'wait_break', 'no_level_after_flip',
               'recon_wick', 'recon_break', 'recon_touch_swing', 'recon_later_swing',
               'recon_thaw', 'recon_thaw_wick', 'recon_thaw_break', 'recon_thaw_cont',
               'recon_thaw_isweep', 'recon_thaw_ibreak', 'recon_two_fvg',
               'recon_nolevel', 'recon_nolevel_ctl')
E_KINDS = ('cont', 'int_break', 'flip', 'no_level_crash', 'wick_struct', 'sweep_fvg_touch')

_CASES = None


def build_cases():
    global _CASES
    if _CASES is not None:
        return _CASES
    cs = []

    def add(name, bars, kind='R', **kw):
        cs.append(Case(name, kind, bars, **kw))

    for k in WICK_KINDS:
        add('w_' + k, sc_wick_family(k))
        add('m_w_' + k, mirror(sc_wick_family(k)))
    add('t2_correction', sc_correction())
    add('m_t2_correction', mirror(sc_correction()))
    add('t7_minor_swings', sc_minor_swings())
    add('t7_no_bound', sc_no_bound())
    add('t7_consumed_before_known', sc_consumed_before_known())
    add('t10_seed_bar_closes_beyond', sc_seed_bar_closes_beyond())
    for k in ('break', 'wick_then_break', 'wick_only', 'equal_close'):
        add('a_' + k, sc_case_a(k))
        add('m_a_' + k, mirror(sc_case_a(k)))
    add('b2_active_retro', sc_b2_active('retro'))
    add('m_b2_active_retro', mirror(sc_b2_active('retro')))
    add('b2_active_rejected', sc_b2_active('rejected'))
    add('m_b2_active_rejected', mirror(sc_b2_active('rejected')))
    for k in ('untouched', 'touched'):
        add('b2_none_' + k, sc_b2_none(k))
        add('m_b2_none_' + k, mirror(sc_b2_none(k)))
    add('c_history', sc_case_c().bars())
    add('m_c_history', mirror(sc_case_c().bars()))
    for st in (12, 16):
        add('c_suffix_%d' % st, sc_case_c().bars()[st:])
    add('d_break_vs_seed', sc_case_d('break'))
    add('d_seed_control', sc_case_d('seed'))
    add('d_no_evidence', sc_no_evidence())
    for k in E_KINDS:
        add('e_' + k, sc_e(k))
    add('e_hh_below_level', sc_hh_below_level())
    add('d_no_level_no_sweep', sc_no_level_no_sweep())
    for k in (1, 2, 3):
        add('bos_%d' % k, sc_bos(k))
    for k in SWEEP_KINDS:
        add('s_' + k, sc_bear_sweep(k))
        add('m_s_' + k, mirror(sc_bear_sweep(k)))
    # P11 / evaluate cases (lookback 20)
    b = sc16_converged_break()
    add('p16a_converged_break', b, 'E', rebuild=len(b))
    b = sc16_converged_seed()
    add('p16a_converged_seed', b, 'E', rebuild=len(b))
    b = sc16_ab_diff()
    add('p16b_ab_difference', b, 'E', rebuild=len(b))
    b = sc16_anchor_warmup()
    add('p16c_anchor_warmup', b, 'E', rebuild=len(b))
    b = sc16_event_only()
    add('p16e_event_only_diff', b, 'E', rebuild=len(b))
    # FINDING 1: anchor by existing bars (same prices as p16a_converged_break, other open times)
    b = sc16_converged_break()
    add('f1_weekend_gap', retime(b, weekend_slots(len(b), 4)), 'E', rebuild=len(b))
    add('f1_history_gap', retime(b, [i + (3 if i >= 26 else 0) for i in range(len(b))]), 'E', rebuild=len(b))
    b = sc16_limit()
    add('p16d_limit_r60', b, 'E', rebuild=60)
    add('p16d_limit_r140', b, 'E', rebuild=140)
    b = sc17_first_event_at_3l()
    add('p17_first_event_n60', b, 'E', rebuild=60)
    add('p17_reduced_depth', sc16_converged_break()[:50], 'E', rebuild=60)
    add('p17_reduced_depth_ok', sc16_converged_break(), 'E', rebuild=200)
    add('p17_failed_copy', sc16_converged_break(), 'E', rebuild=60, n_use=0)
    add('p17_hard_cap', sc16_converged_break(), 'E', rebuild=1000, hard_cap=61)
    _CASES = cs
    return cs


def case_by_name(name):
    for c in build_cases():
        if c.name == name:
            return c
    raise KeyError(name)


# ================================================================== tests ====
FAILS = []
PASSES = []
DEFERRED = []


def check(cond, label):
    if cond:
        PASSES.append(label)
        print('  PASS ' + label)
    else:
        FAILS.append(label)
        print('  FAIL ' + label)


def deferred(label):
    DEFERRED.append(label)
    print('  DEFERRED (not implemented in this round): ' + label)


_REPS = {}


def rep_of(name):
    if name not in _REPS:
        c = case_by_name(name)
        _REPS[name] = replay(c.bars, c.n_use, c.params())
    return _REPS[name]


def types_of(rep):
    return [e.type for e in rep.events]


def events_of(rep, etype):
    return [e for e in rep.events if e.type == etype]


def last_time(name):
    c = case_by_name(name)
    return c.bars[c.n_use - 1].time


SWAP_MAP = {'BULLISH': 'BEARISH', 'BEARISH': 'BULLISH', 'BULL': 'BEAR', 'BEAR': 'BULL',
            'SH': 'SL', 'SL': 'SH', 'IH': 'IL', 'IL': 'IH', 'HH': 'LL', 'LL': 'HH'}


def swap_sides(text):
    """exchange the roles of BUY and SELL in a transcript (prices dropped)"""
    import re
    text = re.sub(r'@\d+\.\d\d', '', text)
    text = re.sub(r'(F\d{12})([UD])', lambda m: m.group(1) + ('D' if m.group(2) == 'U' else 'U'), text)
    return re.sub(r'BULLISH|BEARISH|BULL|BEAR|(?:SH|SL|IH|IL|HH|LL)(?=\d{12})',
                  lambda m: SWAP_MAP[m.group(0)], text)


def strip_prices(text):
    import re
    return re.sub(r'@\d+\.\d\d', '', text)


def test_01_body_vs_wick():
    print('--- 1. body break versus wick (both directions, equality is not a break)')
    for pref, d0, d1 in (('', 'BEAR', 'BULL'), ('m_', 'BULL', 'BEAR')):
        tag = 'SELL' if pref == '' else 'BUY'
        r = rep_of(pref + 'w_break')
        check(types_of(r)[-1] == EV_FLIP and r.state.dir_name_ok if False else types_of(r)[-1] == EV_FLIP,
              '%s: close beyond the level is a FLIP' % tag)
        check(dir_name(r.state.dir) == d1 and r.state.phase == 'ACTIVE' and not r.state.has_level,
              '%s: bias reversed, new bias has no level yet' % tag)
        r = rep_of(pref + 'w_wick')
        check(types_of(r)[-1] == EV_WICK and EV_FLIP not in types_of(r) and dir_name(r.state.dir) == d0
              and r.state.phase == 'HOLD', '%s: high beyond, close not beyond is a wick: HOLD, bias unchanged' % tag)
        r = rep_of(pref + 'w_eqclose')
        check(types_of(r)[-1] == EV_WICK and EV_FLIP not in types_of(r),
              '%s: close exactly on the level is not a break (wick only)' % tag)
        r = rep_of(pref + 'w_eqhigh')
        check(types_of(r) == [EV_SEED] and r.state.phase == 'ACTIVE',
              '%s: high exactly on the level is not a wick (no event)' % tag)
        r = rep_of(pref + 'w_eqboth')
        check(types_of(r) == [EV_SEED] and r.state.phase == 'ACTIVE',
              '%s: high and close exactly on the level: nothing happens' % tag)


def test_02_correction():
    print('--- 2. correction that does not change the bias')
    for pref, d0 in (('', 'BEAR'), ('m_', 'BULL')):
        r = rep_of(pref + 't2_correction')
        check(r.state.t2dir == 'MIXED' and dir_name(r.state.dir) == d0 and r.state.phase == 'ACTIVE'
              and EV_FLIP not in types_of(r) and EV_WICK not in types_of(r),
              '%s: T002 MIXED while the bias stays (no break of the protecting level)' % ('SELL' if pref == '' else 'BUY'))


def test_03_wick_blocks():
    print('--- 3. a wick blocks new entries (HOLD, block time = close of the wick bar)')
    c = case_by_name('w_wick')
    wick_bar = c.bars[-1]
    r = rep_of('w_wick')
    st = r.state
    check(st.phase == 'HOLD' and hold_block(st) and not sweep_block(st), 'HOLD raises the hold block (S3), not the sweep block')
    check(st.wk_src == wick_bar.time and st.wk_known == wick_bar.time + PERIOD and st.wk_det == wick_bar.time + PERIOD
          and not st.wk_retro, 'source_wick_time = wick bar open, known = detected_at = its close, not retroactive')
    check(st.wait_start == st.wk_det and st.frozen, 'HOLD starts at detected_at and the level is frozen')
    ev = events_of(r, EV_WICK)[0]
    check(ev.bar_time == wick_bar.time, 'the WICK event is dated by the wick bar')
    prefix = replay(c.bars, c.n_use - 1, c.params())
    check(prefix.state.phase == 'ACTIVE', 'one bar earlier there is no HOLD (known only at the close)')


def fvg_touch_bars(bars, fvg_a_time, from_time, bull):
    """bars (open times) that intersect the FVG zone starting at from_time"""
    f = None
    for x in t2.find_fvgs(bars, len(bars), PERIOD):
        if x.time_a == fvg_a_time:
            f = x
    out = []
    if f is None:
        return out
    for i in range(f.index_a + 3, len(bars)):
        if bars[i].time >= from_time and bars[i].low <= f.upper and bars[i].high >= f.lower:
            out.append(bars[i].time)
    return out


def test_04_prewick():
    print('--- 4. a pre-wick FVG is not eligible even when touched again')
    for pref in ('', 'm_'):
        tag = 'SELL' if pref == '' else 'BUY'
        r = rep_of(pref + 'w_pre_touched')
        c = case_by_name(pref + 'w_pre_touched')
        old = [f for f in t2.find_fvgs(c.bars, len(c.bars), PERIOD) if f.bullish == (pref == 'm_')]
        touched_after = [fvg_touch_bars(c.bars, f.time_a, r.state.wk_det, f.bullish) for f in old]
        check(any(len(x) > 0 for x in touched_after), '%s: the old FVG zones are really touched after the wick (not vacuous)' % tag)
        check(r.state.phase == 'HOLD' and len(r.tracks) == 0 and EV_RECONFIRMED not in types_of(r) and r.state.pre != '',
              '%s: no reconfirmation by pre-wick FVGs; they are listed as PRE_WICK' % tag)
        r = rep_of(pref + 'w_a_before_wick')
        c = case_by_name(pref + 'w_a_before_wick')
        wick_time = r.state.wk_src
        fv = [f for f in t2.find_fvgs(c.bars, len(c.bars), PERIOD) if f.bullish == (pref == 'm_') and f.time_a == wick_time - PERIOD]
        check(len(fv) == 1, '%s: there is an FVG whose candle A is the bar just before the wick (C after the wick)' % tag)
        tb = fvg_touch_bars(c.bars, wick_time - PERIOD, r.state.wk_det, fv[0].bullish) if fv else []
        check(len(tb) > 0 and len(r.tracks) == 0 and EV_RECONFIRMED not in types_of(r),
              '%s: A before the wick is rejected although touched again' % tag)


def test_05_new_fvg():
    print('--- 5. new FVG after the wick: A = wick candle accepted, touch counted at the close')
    for pref in ('', 'm_'):
        tag = 'SELL' if pref == '' else 'BUY'
        r = rep_of(pref + 'w_a_is_wick')
        c = case_by_name(pref + 'w_a_is_wick')
        evs = events_of(r, EV_RECONFIRMED)
        fid = 'F%s%s' % (ts(r.state.wk_src), 'U' if pref == 'm_' else 'D')
        check(len(evs) == 1 and evs[0].ref == fid, '%s: the FVG whose candle A is the wick candle is eligible and reconfirms' % tag)
        tb = fvg_touch_bars(c.bars, r.state.wk_src, r.state.wk_det, pref == 'm_')
        check(len(tb) >= 1 and evs[0].bar_time == tb[0], '%s: reconfirmation dated by the first touching bar (counted at its close)' % tag)
        idx = [i for i in range(len(c.bars)) if c.bars[i].time == evs[0].bar_time][0]
        before = replay(c.bars, idx, c.params())
        after = replay(c.bars, idx + 1, c.params())
        check(before.state.phase == 'HOLD' and after.state.phase == 'RECONFIRMED',
              '%s: the touch is known only once the touching candle has closed' % tag)
        check(r.state.phase == 'RECONFIRMED' and r.state.rec_id == fid and r.state.recon_reason == 'STRUCT',
              '%s: RECONFIRMED_H4 records the FVG id (M15 phase not part of T003)' % tag)
        r = rep_of(pref + 'w_invalid_same_bar')
        check(EV_RECONFIRMED not in types_of(r) and 'INVALID' in tracks_text(r.tracks) and r.state.phase == 'HOLD',
              '%s: a bar touching the zone but closing beyond the far edge is INVALID, not a touch' % tag)


def test_06_repeated():
    print('--- 6. repeated events')
    for pref in ('', 'm_'):
        tag = 'SELL' if pref == '' else 'BUY'
        d0 = 'BEAR' if pref == '' else 'BULL'
        d1 = 'BULL' if pref == '' else 'BEAR'
        r = rep_of(pref + 'w_second_wick_hold')
        w = events_of(r, EV_WICK)
        check(len(w) == 2 and ' restart=1' not in w[0].detail and w[1].detail.endswith('restart=1')
              and r.state.wk_src == w[1].bar_time and len(r.tracks) == 0 and r.state.pre.count('F') >= 3,
              '%s: a second wick restarts HOLD from the latest wick; the earlier eligible FVG becomes PRE_WICK' % tag)
        r = rep_of(pref + 'w_second_wick_reconf')
        t = types_of(r)
        check(t.count(EV_RECONFIRMED) == 1 and t[-1] == EV_WICK and r.state.phase == 'HOLD' and r.state.rec_id == '',
              '%s: a wick during RECONFIRMED returns to HOLD' % tag)
        r = rep_of(pref + 'w_invalid_before_touch')
        check(EV_RECONFIRMED not in types_of(r) and 'INVALID' in tracks_text(r.tracks) and r.state.phase == 'HOLD',
              '%s: invalidation before the touch drops the FVG, HOLD continues' % tag)
        r = rep_of(pref + 'w_invalid_after_reconf')
        lost = events_of(r, EV_RECONF_LOST)
        check(len(lost) == 1 and lost[0].detail.endswith('to=HOLD') and r.state.phase == 'HOLD' and r.state.rec_id == '',
              '%s: invalidation after RECONFIRMED returns to HOLD' % tag)
        r = rep_of(pref + 'w_break_in_hold')
        check(types_of(r)[-1] == EV_FLIP and dir_name(r.state.dir) == d1 and r.state.phase == 'ACTIVE' and not r.state.has_wick
              and len(r.tracks) == 0, '%s: body break during HOLD flips the bias and discards the waiting' % tag)
        r = rep_of(pref + 'w_break_in_reconf')
        check(types_of(r)[-2:] == [EV_RECONFIRMED, EV_FLIP] and dir_name(r.state.dir) == d1 and r.state.rec_id == ''
              and len(r.tracks) == 0, '%s: body break during RECONFIRMED flips and discards the reconfirmation' % tag)


def test_07_level_selection():
    print('--- 7. level selection (P2)')
    r = rep_of('t7_minor_swings')
    sh_pivot = T0 + 16 * PERIOD
    check(r.state.has_level and r.state.lv_pivot == sh_pivot and r.state.lv_price == 117.0 and r.state.lv_id.startswith('SH' + ts(sh_pivot)),
          'the leg top (117) is the level; the minor high (115), the higher high before the leg (125) and the corrective bounce are not')
    check(rep_of('t7_no_bound').state.dir == 0 and not rep_of('t7_no_bound').state.has_level,
          'undefined when a bound is missing (no lower low): nothing is invented')
    r = rep_of('t7_consumed_before_known')
    base = rep_of('w_break')
    check(EV_SEED in types_of(base) and EV_SEED not in types_of(r) and r.state.dir == 0 and r.state.none_reason == 'NO_EVIDENCE',
          'a candidate already body-broken before it became known is undefined (no seed), unlike the same structure without that close')
    r = rep_of('t10_seed_bar_closes_beyond')
    check(types_of(r) == [EV_SEED] and r.state.dir == BEAR and not r.state.has_level,
          'AMBIGUITY 10: the seeding bar closing beyond its own level seeds a bias without a level (retroactive scan rejects the level)')
    r = rep_of('a_break')
    c = case_by_name('a_break')
    br = events_of(r, EV_BREAK_SET)[0]
    check(br.bar_time == c.bars[-1].time and br.ref.startswith('SH'),
          'the evaluated bar crossing the candidate is a BODY BREAK event on the level, not a reason to discard it')
    # direct unit tests of derive_level
    def sw(spec):
        out = []
        for i, (hi, price) in enumerate(spec):
            t = T0 + (i * 6) * PERIOD
            out.append(t2.Swing('S%s%s' % (ts(t), 'H' if hi else 'L'), hi, i * 6, t, t + 3 * PERIOD, price))
        return out
    lv, ex, li = derive_level(sw([(False, 95), (True, 117), (False, 73)]), 3, BEAR)
    check(lv is not None and lv.price == 117 and li is None, 'unit: L0, S, L1 (lower) -> level S')
    lv, ex, li = derive_level(sw([(False, 95), (True, 117), (False, 95)]), 3, BEAR)
    check(lv is None, 'unit: an equal low is not a lower low (strict) -> undefined')
    lv, ex, li = derive_level(sw([(False, 95), (True, 117), (True, 117), (False, 73)]), 4, BEAR)
    check(lv is not None and lv.pivot_time == T0 + 6 * PERIOD, 'unit: equal highs -> the earliest one is the level (AMBIGUITY 11)')
    lv, ex, li = derive_level(sw([(False, 95), (True, 117), (False, 73), (True, 100), (False, 80)]), 5, BEAR)
    check(lv is not None and lv.price == 117 and li is not None and li.price == 100,
          'unit: latest LL stays L1; the corrective high is the interior level, not the level')
    lv, ex, li = derive_level(sw([(False, 95), (True, 117)]), 2, BEAR)
    check(lv is None and ex is None, 'unit: a single low -> no lower low -> no level and no LL candidate')
    lv, ex, li = derive_level(sw([(True, 100), (False, 80), (True, 110)]), 3, BULL)
    check(lv is not None and lv.price == 80, 'unit: bullish mirror (HH, lowest low between)')


def test_08_no_lookahead():
    print('--- 8. historical analysis: no look-ahead')
    names = ['a_wick_then_break', 'b2_active_retro', 'b2_none_touched', 'w_a_is_wick', 'c_history', 'e_sweep_fvg_touch',
             's_sweep_fvg_touch', 'w_invalid_after_reconf', 'm_w_break_in_reconf']
    total = 0
    ok_garbage = True
    ok_prefix = True
    ok_keys = True
    for name in names:
        c = case_by_name(name)
        n = len(c.bars)
        full = replay(c.bars, n, c.params())
        for T_off in range(6, n * 2 + 1):
            # as-of time in half-bar steps
            asof = c.bars[0].time + (T_off * PERIOD) // 2
            cnt = t2.closed_count_asof(c.bars, n, asof, PERIOD)
            if cnt < 6:
                continue
            garbage = list(c.bars[:cnt])
            for i in range(cnt, n):
                b = c.bars[i]
                garbage.append(Bar(b.time, 9000.0 + i, 8000.0 - i, 8500.0 + (i % 7)))
            cnt_g = t2.closed_count_asof(garbage, n, asof, PERIOD)
            a = replay(c.bars, cnt, c.params())
            g = replay(garbage, cnt_g, c.params())
            if cnt_g != cnt or replay_text(a) != replay_text(g):
                ok_garbage = False
            # prefix equals the full replay restricted to what was knowable at T
            fe = [e.text() for e in full.events if e.bar_time + PERIOD <= asof]
            pe = [e.text() for e in a.events]
            if fe != pe:
                ok_prefix = False
            if full.keys[cnt - 1] != state_key(a.state, a.tracks):
                ok_keys = False
            total += 1
    check(total > 200 and ok_garbage, 'as-of results identical when later bars are replaced by garbage (%d as-of times, %d cases)' % (total, len(names)))
    check(ok_prefix, 'events of a prefix replay equal the full replay restricted to what was knowable at T')
    check(ok_keys, 'the machine state at T of the full replay equals the state of the prefix replay')


def test_10_buy_mirror():
    print('--- 10. BUY mirror (one symmetric implementation) and a grab -> FVG -> touch sequence')
    pairs = []
    for c in build_cases():
        if c.kind == 'R' and not c.name.startswith('m_') and ('m_' + c.name) in [x.name for x in build_cases()]:
            pairs.append(c.name)
    bad = []
    for nm in pairs:
        a = strip_prices(replay_text(rep_of(nm)))
        b = strip_prices(replay_text(rep_of('m_' + nm)))
        if swap_sides(a) != b:
            bad.append(nm)
    check(len(pairs) >= 25 and not bad, 'BUY results are the exact mirror of SELL results on %d mirrored controlled series %s' % (len(pairs), bad))
    r = rep_of('e_sweep_fvg_touch')
    t = types_of(r)
    sw = events_of(r, EV_INT_SWEEP)[0]
    rc = events_of(r, EV_RECONFIRMED)[0]
    fid_ok = rc.ref.endswith('U') and ts(sw.bar_time) <= rc.ref[1:13]
    check(EV_FLIP not in t and EV_WICK not in t and dir_name(r.state.dir) == 'BULL' and t.index(EV_INT_SWEEP) < t.index(EV_RECONFIRMED),
          'BUY grab: INTERNAL_SWEEP without a change of bias, then the new FVG and its touch (native bullish data)')
    check(fid_ok and rc.detail.endswith('reason=INTERNAL') and r.state.phase == 'RECONFIRMED' and r.state.recon_reason == 'INTERNAL',
          'the FVG formed after the grab (A at or after the sweep bar) is touched -> RECONFIRMED_H4 reason INTERNAL; M15 not modelled')


def test_11_acceptance_ab():
    print('--- 11. acceptance A (real break) and B (wick)')
    for pref, d1 in (('', 'BULL'), ('m_', 'BEAR')):
        tag = 'SELL-side level' if pref == '' else 'BUY-side level'
        r = rep_of(pref + 'a_break')
        c = case_by_name(pref + 'a_break')
        br = events_of(r, EV_BREAK_SET)
        check(len(br) == 1 and br[0].bar_time == c.bars[-1].time and r.state.origin == 'BREAK' and dir_name(r.state.dir) == d1
              and 'known=' in br[0].detail, 'A (%s): BODY BREAK at t sets the bias in the break direction, level and known time reported' % tag)
        # same when t is the last bar of the as-of set and when later bars are garbage
        garbage = list(c.bars)
        for i in range(8):
            garbage.append(Bar(c.bars[-1].time + (i + 1) * PERIOD, 9000.0 + i, 8000.0 - i, 8300.0 + i))
        asof = c.bars[-1].time + PERIOD
        cnt = t2.closed_count_asof(garbage, len(garbage), asof, PERIOD)
        g = replay(garbage, cnt, c.params())
        check(cnt == len(c.bars) and replay_text(g) == replay_text(r), 'A (%s): identical when bars after t are replaced by garbage' % tag)
        r = rep_of(pref + 'a_wick_only')
        check(types_of(r) == [EV_NONE_WICK] and r.state.dir == 0 and r.state.phase == 'ACTIVE',
              'B (%s): from NONE a wick changes no bias; it is stored on the candidate (NONE_WICK)' % tag)
        r = rep_of(pref + 'a_wick_then_break')
        t = types_of(r)
        check(t == [EV_NONE_WICK, EV_BREAK_SET] and events_of(r, EV_NONE_WICK)[0].ref == events_of(r, EV_BREAK_SET)[0].ref,
              'B (%s): a later body close beyond the same wicked candidate is still a BODY BREAK' % tag)
        r = rep_of(pref + 'a_equal_close')
        check(EV_BREAK_SET not in types_of(r), 'A (%s): a close exactly on the level is not a break' % tag)
    r = rep_of('w_wick')
    check(r.state.frozen and r.state.lv_id == events_of(r, EV_WICK)[0].ref and r.state.lv_price == 117.0,
          'B (ACTIVE): the consumed candidate is kept as the frozen protecting level (not re-derived, not rejected)')


def test_12_retro():
    print('--- 12. retroactive wick (B2)')
    for pref in ('', 'm_'):
        tag = 'SELL' if pref == '' else 'BUY'
        r = rep_of(pref + 'b2_active_retro')
        c = case_by_name(pref + 'b2_active_retro')
        w = events_of(r, EV_WICK)
        st = r.state
        wbar = c.bars[39]
        check(len(w) == 1 and st.wk_src == wbar.time and st.wk_known == wbar.time + PERIOD and st.wk_det == wbar.time + 2 * PERIOD and st.wk_retro,
              '%s: source_wick_time, source_wick_known_time and detected_at are kept apart; retroactive = true' % tag)
        check(w[0].bar_time == wbar.time + PERIOD and st.phase == 'HOLD' and st.wait_start == st.wk_det,
              '%s: HOLD starts at detected_at (the discovery close), never at source_wick_time' % tag)
        r = rep_of(pref + 'b2_active_rejected')
        check(EV_WICK not in types_of(r) and not r.state.has_level and r.state.phase == 'ACTIVE',
              '%s: a body close beyond the candidate before discovery rejects it (no HOLD, no level)' % tag)
        for kind in ('untouched', 'touched'):
            r = rep_of(pref + 'b2_none_' + kind)
            c = case_by_name(pref + 'b2_none_' + kind)
            t = types_of(r)
            nw = events_of(r, EV_NONE_WICK)[0]
            seed = events_of(r, EV_SEED)[0]
            w = events_of(r, EV_WICK)[0]
            st = r.state
            check(t[0] == EV_NONE_WICK and nw.bar_time == st.wk_src and seed.bar_time == w.bar_time and st.wk_det == seed.bar_time + PERIOD
                  and st.wk_retro and st.wk_det > st.wk_known and st.wk_det == st.bias_start,
                  '%s/%s: NONE stores the wick without HOLD; the later seed starts HOLD at the seed time (retroactive)' % (tag, kind))
            fid = 'F%s%s' % (ts(st.wk_src), 'U' if pref == 'm_' else 'D')
            check(any(tr.id == fid for tr in r.tracks), '%s/%s: an FVG formed between the wick and the discovery qualifies by its timing (A = wick bar)' % (tag, kind))
            before = [x for x in fvg_touch_bars(c.bars, st.wk_src, st.wk_known, pref == 'm_') if x < st.wk_det]
            check(len(before) >= 1, '%s/%s: the zone is really touched before the discovery (not vacuous)' % (tag, kind))
            if kind == 'untouched':
                check(EV_RECONFIRMED not in t and r.state.phase == 'HOLD', '%s: touches before detected_at (and on the seed bar) do not count' % tag)
            else:
                rc = events_of(r, EV_RECONFIRMED)
                check(len(rc) == 1 and rc[0].bar_time >= st.wk_det, '%s: a touch on a bar opening at or after detected_at counts' % tag)


def test_13_one_flip_trigger():
    print('--- 13. one flip trigger, NONE-only candidates')
    r = rep_of('e_cont')
    check(types_of(r)[-1] == EV_CONTINUATION and EV_FLIP not in types_of(r) and dir_name(r.state.dir) == 'BULL',
          'a close beyond the latest HH is a CONTINUATION event, never a flip')
    r = rep_of('e_int_break')
    check(types_of(r)[-1] == EV_INT_BREAK and EV_FLIP not in types_of(r) and dir_name(r.state.dir) == 'BULL' and r.state.phase == 'ACTIVE',
          'a close below an interior low (not the protecting level) is an INTERNAL_BREAK observation, never a flip')
    r = rep_of('e_flip')
    fl = events_of(r, EV_FLIP)
    check(len(fl) == 1 and fl[0].ref.startswith('SL') and 'dir=BEAR' in fl[0].detail and EV_WICK not in types_of(r),
          'only a close beyond the current protecting level flips (here the protecting low 109)')
    r = rep_of('e_wick_struct')
    check(types_of(r)[-1] == EV_WICK and r.state.phase == 'HOLD' and EV_FLIP not in types_of(r), 'a wick through the protecting level is HOLD, not a flip')
    r = rep_of('e_hh_below_level')
    check(EV_FLIP not in types_of(r) and EV_INT_BREAK in types_of(r) and dir_name(r.state.dir) == 'BEAR',
          'a close above a higher high that lies below the protecting level does not flip (candidates are NONE-only)')
    bad = []
    for c in build_cases():
        if c.kind != 'R':
            continue
        r = rep_of(c.name)
        starts = [i for i, e in enumerate(r.events) if e.type in (EV_BREAK_SET, EV_SEED)]
        first_bias = starts[0] if starts else len(r.events)
        pre = [e.type for e in r.events[:first_bias] if e.market]
        if len(starts) > 1 or pre:
            bad.append(c.name)
    check(not bad, 'BREAK_SET/SEED happen at most once, first, only from NONE; no flip/wick before a bias exists %s' % bad)
    r = rep_of('e_no_level_crash')
    flips = events_of(r, EV_FLIP)
    check(len(flips) == 1 and r.state.dir == BEAR and not r.state.has_level and r.state.t2dir in ('BEARISH', 'MIXED'),
          'a bias without a level cannot flip (price keeps moving, no second FLIP)')
    r = rep_of('d_no_level_no_sweep')
    check(r.state.dir == BULL and not r.state.has_level and r.state.t2dir == 'BEARISH' and EV_FLIP not in types_of(r),
          'bias BULL without level while T002 says BEARISH and price falls under old lows: no flip, the disagreement is visible')


def test_14_history_and_precedence():
    print('--- 14. bias rebuilt from break history (C) and precedence (D)')
    r = rep_of('c_history')
    check(dir_name(r.state.dir) == 'BULL' and r.state.lv_price == 109.0 and r.state.t2dir == 'MIXED' and r.state.phase == 'ACTIVE'
          and r.state.origin == 'BREAK' and types_of(r) == [EV_BREAK_SET, EV_CONTINUATION],
          'C: two successive breaks, then a correction (T002 MIXED): BIAS_BULL with the protecting low of the last up-leg')
    for nm in ('c_suffix_12', 'c_suffix_16'):
        s = rep_of(nm)
        check(dir_name(s.state.dir) == 'BULL' and s.state.lv_id == r.state.lv_id and s.state.lv_price == 109.0 and s.state.t2dir == 'MIXED',
              'C: same bias and same protecting low when the window starts later (%s; origin %s)' % (nm, s.state.origin))
    c = case_by_name('c_history')
    garbage = list(c.bars)
    for i in range(6):
        garbage.append(Bar(c.bars[-1].time + (i + 1) * PERIOD, 9100.0 + i, 8100.0 - i, 8700.0))
    asof = c.bars[-1].time + PERIOD
    cnt = t2.closed_count_asof(garbage, len(garbage), asof, PERIOD)
    check(replay_text(replay(garbage, cnt, c.params())) == replay_text(r), 'C: same result when bars after the evaluation time are garbage')
    r = rep_of('d_break_vs_seed')
    ctl = rep_of('d_seed_control')
    check(types_of(ctl) == [EV_SEED] and dir_name(ctl.state.dir) == 'BEAR',
          'D: control: the same structure without the break gives a T002 seed in the opposite direction (not vacuous)')
    check(types_of(r) == [EV_BREAK_SET] and dir_name(r.state.dir) == 'BULL' and 't002=BEARISH' in r.events[0].detail,
          'D: the break outranks the seed; T002 BEARISH is shown as the disagreement')
    r = rep_of('d_no_evidence')
    check(r.state.dir == 0 and r.state.none_reason == 'NO_EVIDENCE' and r.events == [], 'D: no levels and no seed: NONE (NO_EVIDENCE)')
    res = [p10_resolve(1, 1, BEAR), p10_resolve(1, 1, 0), p10_resolve(1, 0, BEAR), p10_resolve(0, 1, BULL), p10_resolve(0, 0, BEAR), p10_resolve(0, 0, 0)]
    check(res == [('CONFLICT', 0), ('CONFLICT', 0), ('BREAK', BULL), ('BREAK', BEAR), ('SEED', BEAR), ('NONE', 0)],
          'D: CONFLICT is never overwritten by the seed on that bar; the seed applies again on the next bar (pure resolver)')
    # CONFLICT is unreachable with consumed candidates excluded: bounded random search
    seed = 12345
    found = 0
    for k in range(120):
        rows = []
        c0 = 100.0
        for i in range(70):
            seed = (seed * 1103515245 + 12345) % 2147483648
            step = ((seed >> 8) % 21) - 10
            c0 = c0 + step * 0.9
            seed = (seed * 1103515245 + 12345) % 2147483648
            hw = 2.0 + ((seed >> 8) % 5)
            rows.append(Bar(T0 + i * PERIOD, c0 + hw, c0 - hw, c0 + (((seed >> 12) % 5) - 2) * 0.5))
        found += len(events_of(replay(rows, 70, Params(lookback=20)), EV_CONFLICT))
    check(found == 0, 'D: CONFLICT never occurs in 120 random series (argued unreachable when consumed candidates are excluded; evidence, not proof)')
    r = rep_of('d_no_level_no_sweep')
    c = case_by_name('d_no_level_no_sweep')
    check(types_of(r) == [EV_BREAK_SET] and not r.state.has_level, 'P14: without a defined protecting level nothing is raised (no sweep, no internal break)')
    sw, amb = t2.find_swings(c.bars, len(c.bars), 2, 2, PERIOD)
    lows_after = [s_.price for s_ in sw if not s_.is_high and s_.pivot_time > T0 + 13 * PERIOD]
    sweep_bar = c.bars[29]
    check(len(lows_after) > 0 and sweep_bar.low < min(lows_after) and sweep_bar.close >= min(lows_after),
          'P14: the bar would have been an interior sweep geometrically (not vacuous)')


def test_15_determinism():
    print('--- 15. determinism and restart (no stored state)')
    ok = True
    for c in build_cases():
        a = run_case(c)
        b = run_case(Case(c.name, c.kind, list(c.bars), c.lookback, c.rebuild, c.hard_cap, c.n_use))
        if a != b:
            ok = False
    check(ok, 'the same bars always give the same state, events and flag (%d cases evaluated twice from fresh copies)' % len(build_cases()))
    c = case_by_name('p16a_converged_break')
    p = c.params()
    first = eval_text(evaluate(c.bars, len(c.bars), p))
    evaluate(c.bars[:50], 50, p)
    evaluate(c.bars[:61], 61, p)
    second = eval_text(evaluate(c.bars, len(c.bars), p))
    check(first == second, 'a restart (other evaluations in between) rebuilds the same state: nothing is kept between calls')


def quiet_older(m, first_time, centre):
    """m quiet alternating bars ending right before first_time (older times)"""
    rows = []
    for i in range(m):
        cc = centre + (4 if i % 2 == 0 else 0)
        rows.append(Bar(first_time - (m - i) * PERIOD, cc + HW, cc - HW, float(cc)))
    return rows


def test_16_depth_check():
    print('--- 16. depth-sensitivity check (P11)')
    c = case_by_name('p16a_converged_break')
    e = evaluate(c.bars, len(c.bars), c.params())
    check(e.reliable and e.flag == FLAG_CONVERGED and 'converged at depth 64 vs 44' in e.reason and reported_direction(e) == 'BULL',
          'a: A and B agree: CONVERGED, text says "converged at depth 64 vs 44"')
    check(e.r_eff == 64 and e.b_depth == 44 and e.warm == 20 and e.chk == 20 and e.r_req == 64,
          'a: the depths used are reported (request, effective, B depth, warm-up, check depth)')
    c2 = case_by_name('p16a_converged_seed')
    e2 = evaluate(c2.bars, len(c2.bars), c2.params())
    check(e2.reliable and e2.flag == FLAG_SEEDED and e2.state.origin == 'SEED', 'a: origin SEED_SWINGS gives SEEDED (weaker)')
    same = True
    for cc, nm in ((c, 'break'), (c2, 'seed')):
        base = evaluate(cc.bars, len(cc.bars), Params(lookback=20, rebuild=1000))
        for m in (0, 7, 19, 33):
            older = quiet_older(m, cc.bars[0].time, 100)
            allb = older + cc.bars
            x = evaluate(allb, len(allb), Params(lookback=20, rebuild=1000))
            if not (x.reliable and x.key == base.key and events_text(x.events, 0) == events_text(base.events, 0)):
                same = False
    check(same, 'a: extra older (quiet) bars added in a property test leave the final state and events identical')
    c = case_by_name('p16b_ab_difference')
    e = evaluate(c.bars, len(c.bars), c.params())
    a_only = replay(c.bars, len(c.bars), c.params())
    b_only = replay(c.bars[20:], len(c.bars) - 20, c.params())
    check(not e.reliable and e.flag == FLAG_LIMITED and reported_direction(e) == 'UNKNOWN' and 'AB_STATE_DIFF' in e.reason and e.events == [],
          'b: older bias exists, the shorter window seeds differently: LIMITED_BY_HISTORY, direction UNKNOWN, no market event')
    check(state_key(a_only.state, a_only.tracks) != state_key(b_only.state, b_only.tracks),
          'b: the replays really disagree (A %s %s %s, B %s %s %s)' % (
              dir_name(a_only.state.dir), a_only.state.phase, a_only.state.origin,
              dir_name(b_only.state.dir), b_only.state.phase, b_only.state.origin))
    check('ST=' not in eval_text(e) and 'EV=' not in eval_text(e) and 'DIAG=' in eval_text(e), 'b: the report asserts no state and no event, only a diagnostic')
    c = case_by_name('p16c_anchor_warmup')
    e = evaluate(c.bars, len(c.bars), c.params())
    a_only = replay(c.bars, len(c.bars), c.params())
    b_only = replay(c.bars[len(c.bars) - (e.r_eff - e.chk):], e.r_eff - e.chk, c.params())
    check(not e.reliable and e.reason == 'ANCHOR_IN_WARMUP' and state_key(a_only.state, a_only.tracks) == state_key(b_only.state, b_only.tracks),
          'c: the anchor lies in the warm-up: LIMITED although A and B agree')
    c = case_by_name('p16e_event_only_diff')
    e = evaluate(c.bars, len(c.bars), c.params())
    a_only = replay(c.bars, len(c.bars), c.params())
    b_only = replay(c.bars[len(c.bars) - (e.r_eff - e.chk):], e.r_eff - e.chk, c.params())
    fa = [x.type for x in a_only.events if x.bar_time >= e.trusted_from]
    fb = [x.type for x in b_only.events if x.bar_time >= e.trusted_from]
    check(not e.reliable and e.reason == 'AB_EVENT_DIFF' and state_key(a_only.state, a_only.tracks) == state_key(b_only.state, b_only.tracks)
          and EV_FLIP in fa and EV_BREAK_SET in fb and EV_FLIP not in fb,
          'e: same final state but A flips (older bias) where B starts from NONE (BREAK_SET): LIMITED on the event difference alone')
    c60 = case_by_name('p16d_limit_r60')
    c140 = case_by_name('p16d_limit_r140')
    e60 = evaluate(c60.bars, len(c60.bars), c60.params())
    e140 = evaluate(c140.bars, len(c140.bars), c140.params())
    check(e60.reliable and e60.flag == FLAG_SEEDED and e60.reason == 'converged at depth 60 vs 40' and reported_direction(e60) == 'BEAR',
          'd: documented limitation: at depth 60 the state is reliable ("converged at depth 60 vs 40")')
    check(e140.key != e60.key and dir_name(e140.state.dir) == 'BULL',
          'd: more history (depth 140) gives a different state: the older difference is undetectable at depth 60 (LIMIT recorded, not detected)')
    print('  LIMIT (documented, undetectable at depth 60): R=60 -> %s | R=140 -> %s' % (e60.key[:60], e140.key[:60]))
    texts = [eval_text(evaluate(x.bars, x.n_use, x.params())) for x in build_cases() if x.kind == 'E']
    check(all('unchanged' not in t_ and 'additional history' not in t_ and 'more history' not in t_ for t_ in texts),
          'no report text claims the state is unchanged by more/additional history')
    check(all(('converged at depth' in t_) or ('FLAG=LIMITED_BY_HISTORY' in t_) for t_ in texts), 'every flag text is "converged at depth X vs Y" or LIMITED_BY_HISTORY')


def test_16u_units():
    print('--- 16 (units). A/B comparison and previous-state rule as pure functions')
    check(ab_reasons('K', 'K', 'E1', 'E1', BULL, 100, 50) == '', 'agreement on state, events and anchor: reliable')
    check(ab_reasons('K', 'K', 'E1', 'E2', BULL, 100, 50) == 'AB_EVENT_DIFF', 'same state, an event differs inside B\'s trusted region: LIMITED (event reason only)')
    check(ab_reasons('K1', 'K2', 'E', 'E', BULL, 100, 50) == 'AB_STATE_DIFF', 'a different final state: LIMITED (state reason only)')
    check(ab_reasons('K', 'K', 'E', 'E', BULL, 40, 50) == 'ANCHOR_IN_WARMUP', 'the anchor before A\'s warm-up end: LIMITED (anchor reason only)')
    check(ab_reasons('K', 'K', 'E', 'E', 0, 0, 50) == '', 'NONE has no anchor: the anchor rule does not apply')
    check(ab_reasons('K1', 'K2', 'E1', 'E2', BEAR, 10, 50) == 'AB_STATE_DIFF+AB_EVENT_DIFF+ANCHOR_IN_WARMUP', 'reasons are combined in a fixed order')
    # events that differ only BEFORE B's trusted region are not compared (AMBIGUITY 9)
    ea = [Event(EV_WICK, 1000, 'L', 'x'), Event(EV_FLIP, 5000, 'L', 'y')]
    eb = [Event(EV_FLIP, 5000, 'L', 'y')]
    check(events_text(ea, 4000) == events_text(eb, 4000) and events_text(ea, 0) != events_text(eb, 0),
          'events older than B\'s trusted region are ignored by the comparison')
    check(consumer_prev_ok(True, True, 'K', 'K') and not consumer_prev_ok(True, False, 'K', 'K') and not consumer_prev_ok(False, True, 'K', 'K')
          and not consumer_prev_ok(True, True, 'K', 'J'),
          'the state before the bar counts only if RELIABLE and reproduced by the current window')
    st = St()
    st.src_time = 1000
    f = t2.Fvg()
    f.bullish = True
    f.time_a = 1000
    ok1 = fvg_eligible(f, st, True)
    f.time_a = 999
    ok2 = fvg_eligible(f, st, True)
    f.time_a = 1000
    ok3 = fvg_eligible(f, st, False)
    check(ok1 and not ok2 and not ok3, 'eligibility: A at the source time qualifies, A one bar earlier or the wrong type does not')


def test_17_depth_and_window():
    print('--- 17. depth and window behaviour')
    e = evaluate(case_by_name('p17_reduced_depth').bars, 50, case_by_name('p17_reduced_depth').params())
    check(e.flag == FLAG_LIMITED and e.reason == 'SHORT_HISTORY' and 'reduced depth 50 of 60' in e.note and reported_direction(e) == 'UNKNOWN' and e.events == [],
          'depth below 3*L: "reduced depth 50 of 60", LIMITED, UNKNOWN, no event')
    cc = case_by_name('p17_reduced_depth_ok')
    e = evaluate(cc.bars, len(cc.bars), cc.params())
    check(e.reliable and 'reduced depth 64 of 200' in e.note, 'depth below R but at least 3*L: evaluated, "reduced depth 64 of 200" logged')
    cc = case_by_name('p17_failed_copy')
    e = evaluate(cc.bars, 0, cc.params())
    check(e.state is None and e.events == [] and e.reason == 'NO_BARS' and consume_new(e, 0, PERIOD)[0] == C_NOT_RELIABLE,
          'a failed/empty copy: no state, no event')
    cc = case_by_name('p17_hard_cap')
    e = evaluate(cc.bars, len(cc.bars), cc.params())
    check(e.r_eff == 61 and 'clamped to HARD_CAP 61' in e.note, 'a request above HARD_CAP is clamped and logged')
    check(Params().rebuild == 1000 and Params().hard_cap == 5000 and Params().lookback == 300 and warm_up(Params()) == 300 and check_depth(Params()) == 300,
          'defaults: R 1000, HARD_CAP 5000, L 300, warm-up = check depth = L')
    # sliding over a quiet tail keeps the final state of a converged window
    base = sc17_quiet_tail()
    s2 = Series(0)
    s2.rows = []
    allb = list(base)
    for i in range(12):
        t = allb[-1].time + PERIOD
        cc_ = 134 + (4 if i % 2 == 0 else 0)
        allb.append(Bar(t, cc_ + HW, cc_ - HW, float(cc_)))
    p = Params(lookback=20, rebuild=64)
    stable = True
    quiet_nothing = True
    for n in range(64, 70):
        ev = evaluate_latest(allb, n, p)
        if not (ev.reliable and ev.prev_ok and ev.cause == ''):
            stable = False
        st_, evs = consume_new(ev, allb[n - 2].time, PERIOD)
        if st_ != C_OK or evs != []:
            quiet_nothing = False
    check(stable and quiet_nothing, 'sliding by one bar keeps the final state of a converged window (no re-derivation, no event)')
    late = [evaluate_latest(allb, n, p) for n in range(70, len(allb) + 1)]
    check(late[0].cause == 'REDERIVATION:LIMITED_ENTER' and not late[0].reliable and all(not x.reliable for x in late)
          and all(consume_new(x, allb[0].time, PERIOD)[1] == [] for x in late),
          'a state that depends on bars leaving the window becomes LIMITED (a RE-DERIVATION), never an event')
    # first reliable evaluation: the event of that bar must not be emitted
    cc = case_by_name('p17_first_event_n60')
    p = cc.params()
    ev = evaluate_latest(cc.bars, 60, p)
    status, evs = consume_new(ev, cc.bars[58].time, PERIOD)
    check(ev.reliable and EV_BREAK_SET in [x.type for x in ev.events] and ev.cause == 'REDERIVATION:LIMITED_EXIT'
          and status == C_REDERIVED and evs == [], 'the state before the bar is LIMITED (59 < 3L): the BREAK_SET of the 60th bar is a RE-DERIVATION, not an event')
    ev = evaluate_latest(cc.bars + [Bar(cc.bars[-1].time + PERIOD, 125.0, 115.0, 120.0)], 61, p)
    check(ev.reliable and ev.prev_ok and ev.cause == '' and consume_new(ev, cc.bars[-1].time, PERIOD) == (C_OK, []),
          'one bar later both states are reliable: no event for a quiet bar')
    # the window slides past a structure: re-derivation, never an event
    s = sc16_limit()
    ext = list(s)
    for i in range(80):
        t = ext[-1].time + PERIOD
        cc_ = 125 + (4 if i % 2 == 0 else 0)
        ext.append(Bar(t, cc_ + HW, cc_ - HW, float(cc_)))
    p = Params(lookback=20, rebuild=60)
    seeds = 0
    slid = 0
    leak = 0
    for n in range(100, len(ext) + 1):
        ev = evaluate_latest(ext, n, p)
        st_, evs = consume_new(ev, ext[n - 2].time, PERIOD)
        if st_ == C_OK:
            seeds += len([x for x in evs if x.type == EV_SEED])
        if ev.cause.startswith('REDERIVATION'):
            slid += 1
            if evs:
                leak += 1
    check(seeds == 1, 'the SEED of the structure is emitted exactly once while the window moves over it')
    check(slid >= 1 and leak == 0, 'when the structure leaves the window the change is a RE-DERIVATION (%d times) and no event leaks through it' % slid)
    # invariant over every n of several series: events only when both states are reliable and A/B agree
    viol = 0
    for nm in ('p16a_converged_break', 'p16a_converged_seed', 'p16b_ab_difference', 'p16c_anchor_warmup'):
        bb = case_by_name(nm).bars
        for n in range(61, len(bb) + 1):
            ev = evaluate_latest(bb, n, Params(lookback=20, rebuild=60))
            st_, evs = consume_new(ev, bb[n - 2].time, PERIOD)
            if evs and not (ev.reliable and ev.prev_ok):
                viol += 1
    check(viol == 0, 'events are consumed only when the state before and after the bar are RELIABLE and A/B agree')


def test_19_internal_liquidity():
    print('--- 19. internal liquidity (P14)')
    for pref in ('', 'm_'):
        tag = 'SELL' if pref == '' else 'BUY'
        d0 = 'BEAR' if pref == '' else 'BULL'
        r = rep_of(pref + 's_sweep_fvg_touch')
        t = types_of(r)
        sw = events_of(r, EV_INT_SWEEP)[0]
        check(t == [EV_SEED, EV_INT_SWEEP, EV_RECONFIRMED] and dir_name(r.state.dir) == d0 and r.state.recon_reason == 'INTERNAL',
              '%s: interior sweep with the protecting level not crossed: INTERNAL_SWEEP, SWEEP_WAIT, bias unchanged, FVG after the sweep, RECONFIRMED (INTERNAL)' % tag)
        cb = case_by_name(pref + 's_sweep_fvg_touch')
        sidx = [i for i in range(len(cb.bars)) if cb.bars[i].time == sw.bar_time][0]
        mid = replay(cb.bars, sidx + 1, cb.params())
        check(mid.state.phase == 'SWEEP_WAIT' and sweep_block(mid.state) and not hold_block(mid.state),
              '%s: SWEEP_WAIT exposes the entries-block as a separate TECHNICAL-PROPOSAL flag (not the S3 hold flag)' % tag)
        r = rep_of(pref + 's_wick_instead')
        check(EV_INT_SWEEP not in types_of(r) and types_of(r)[-1] == EV_WICK and r.state.phase == 'HOLD',
              '%s: a wick through the protecting level is the structural wick (HOLD), not a sweep' % tag)
        r = rep_of(pref + 's_break_instead')
        check(EV_INT_SWEEP not in types_of(r) and types_of(r)[-1] == EV_FLIP, '%s: a body break is a flip, not a sweep' % tag)
        r = rep_of(pref + 's_int_break')
        check(types_of(r) == [EV_SEED, EV_INT_BREAK] and r.state.phase == 'ACTIVE' and dir_name(r.state.dir) == d0,
              '%s: a body close beyond an interior level is only an INTERNAL_BREAK observation' % tag)
        r = rep_of(pref + 's_restart')
        sws = events_of(r, EV_INT_SWEEP)
        check(len(sws) == 2 and sws[1].detail.endswith('restart=1') and r.state.sweep_time == sws[1].bar_time,
              '%s: a further internal sweep restarts the wait from the latest sweep' % tag)
        r = rep_of(pref + 's_wait_wick')
        check(types_of(r) == [EV_SEED, EV_INT_SWEEP, EV_WICK] and r.state.phase == 'HOLD' and r.state.sweep_time == 0,
              '%s: in SWEEP_WAIT the structural wick supersedes the wait' % tag)
        r = rep_of(pref + 's_wait_break')
        check(types_of(r) == [EV_SEED, EV_INT_SWEEP, EV_FLIP], '%s: in SWEEP_WAIT a body break flips (structural logic supersedes)' % tag)
        r = rep_of(pref + 's_no_level_after_flip')
        cb = case_by_name(pref + 's_no_level_after_flip')
        fidx = [i for i in range(len(cb.bars)) if cb.bars[i].time == events_of(r, EV_FLIP)[0].bar_time][0]
        just = replay(cb.bars, fidx + 1, cb.params())
        check(not just.state.has_level and just.state.phase == 'ACTIVE',
              '%s: right after a flip the new bias has no protecting level' % tag)
    bad = []
    for c in build_cases():
        if c.kind != 'R':
            continue
        r = rep_of(c.name)
        first = {}
        for e in r.events:
            if e.type in (EV_INT_SWEEP, EV_INT_BREAK):
                idx = [i for i in range(len(c.bars)) if c.bars[i].time == e.bar_time][0]
                if r.keys[idx - 1].split(';LV=')[1].split(';')[0] == '-':
                    bad.append(c.name)
    check(not bad, 'every INTERNAL_SWEEP / INTERNAL_BREAK was raised with a defined protecting level %s' % bad)


def lv_of_key(key):
    return key.split(';LV=')[1].split(';')[0]


def lv_id_of_key(key):
    return lv_of_key(key).split('@')[0]


def derive_id_at(c, upto, d):
    """id of the protecting level a derivation from the closed prefix bars[0..upto] would give"""
    sw, _ = t2.find_swings(c.bars, c.n_use, 2, 2, PERIOD)
    lvl, ex, lint = derive_level(sw, known_count(sw, 2, upto), d)
    return lvl.id if lvl is not None else '-'


def bar_idx(c, t):
    return [i for i in range(c.n_use) if c.bars[i].time == t][0]


def test_22_freeze_internal():
    print('--- 22. FINDING 2 (revision 7): the level is frozen during RECONFIRMED(INTERNAL); thaw and re-derivation at the end of the thaw bar')
    for pref in ('', 'm_'):
        tag = 'SELL' if pref == '' else 'BUY'
        d0 = BEAR if pref == '' else BULL
        # (a) a swing confirmed long after the reconfirmation must not change the level
        name = pref + 's_recon_later_swing'
        c = case_by_name(name)
        r = rep_of(name)
        ri = bar_idx(c, events_of(r, EV_RECONFIRMED)[0].bar_time)
        frozen_id = lv_id_of_key(r.keys[ri - 1])
        check(r.state.phase == 'RECONFIRMED' and r.state.recon_reason == 'INTERNAL' and r.state.frozen
              and lv_id_of_key(r.keys[-1]) == frozen_id and frozen_id != '-',
              '%s (a): RECONFIRMED(INTERNAL) freezes the level that was known before the touch (FRZ=1) to the end of the case' % tag)
        check(derive_id_at(c, c.n_use - 1, d0) not in (frozen_id, '-'),
              '%s (a): control: a derivation from the same bars WOULD give another level (so the freeze is what keeps it)' % tag)
        check(all(lv_id_of_key(r.keys[i]) == frozen_id for i in range(ri - 1, c.n_use)),
              '%s (a): the level is identical at every bar from the touch to the end' % tag)
        check(all(e.bar_time <= c.bars[ri].time for e in r.events if e.type in (EV_INT_SWEEP, EV_INT_BREAK, EV_CONTINUATION)),
              '%s (a): no internal or continuation event is raised while frozen' % tag)
        # (a2) the touching candle itself confirms a swing
        name = pref + 's_recon_touch_swing'
        c = case_by_name(name)
        r = rep_of(name)
        ri = bar_idx(c, events_of(r, EV_RECONFIRMED)[0].bar_time)
        before = lv_id_of_key(r.keys[ri - 1])
        check(lv_id_of_key(r.keys[ri]) == before and before != '-' and r.state.frozen,
              '%s (a2): the touching candle confirms a new swing, the level of the event stays the one known before it' % tag)
        check(derive_id_at(c, ri - 1, d0) == before and derive_id_at(c, ri, d0) not in (before, '-'),
              '%s (a2): control: a derivation including the touching candle would give another level' % tag)
        # (b) the recorded FVG is invalidated on T: thaw, the level is re-derived at the END of T and used from T+1
        name = pref + 's_recon_thaw'
        c = case_by_name(name)
        r = rep_of(name)
        lost = events_of(r, EV_RECONF_LOST)
        ti = bar_idx(c, lost[0].bar_time)
        frozen_id = lv_id_of_key(r.keys[ti - 1])
        new_id = lv_id_of_key(r.keys[ti])
        check(len(lost) == 1 and lost[0].detail.endswith('to=SWEEP_WAIT')
              and 'PH=SWEEP_WAIT' in r.keys[ti] and 'FRZ=0' in r.keys[ti] and 'PH=RECONFIRMED' in r.keys[ti - 1],
              '%s (b): the invalidated FVG sends RECONFIRMED(INTERNAL) back to SWEEP_WAIT and thaws the level' % tag)
        check(new_id not in (frozen_id, '-') and derive_id_at(c, ti, d0) == new_id and lv_id_of_key(r.keys[-1]) == new_id,
              '%s (b): the level is re-derived at the end of the thaw bar T (the level a derivation up to T gives) and used from T+1' % tag)
        check(r.state.phase == 'SWEEP_WAIT' and not r.state.frozen and sweep_block(r.state),
              '%s (b): the wait continues: SWEEP_WAIT, level thawed, entries-block flag (technical proposal) raised again' % tag)
        # (b2) the following bar is judged against the level re-derived at T
        r = rep_of(pref + 's_recon_thaw_wick')
        w = events_of(r, EV_WICK)
        check(len(w) == 1 and w[0].ref == new_id and w[0].detail.endswith('restart=0') and r.state.phase == 'HOLD'
              and lv_id_of_key(r.keys[-1]) == new_id,
              '%s (b2): a wick on T+1 is judged against the level re-derived at the end of T, HOLD keeps it' % tag)
        r = rep_of(pref + 's_recon_thaw_break')
        fl = events_of(r, EV_FLIP)
        check(len(fl) == 1 and fl[0].ref == new_id and dir_name(r.state.dir) == dir_name(-d0),
              '%s (b2): a body close on T+1 beyond the level re-derived at T flips the bias' % tag)
        # (b3) no event lost on T+1 after a thaw
        for kname, etype, label in (('cont', EV_CONTINUATION, 'CONTINUATION'), ('isweep', EV_INT_SWEEP, 'INTERNAL_SWEEP'),
                                    ('ibreak', EV_INT_BREAK, 'INTERNAL_BREAK')):
            name = pref + 's_recon_thaw_' + kname
            c = case_by_name(name)
            r = rep_of(name)
            late = [e for e in r.events if e.type == etype and e.bar_time == c.bars[c.n_use - 1].time]
            ti = bar_idx(c, events_of(r, EV_RECONF_LOST)[0].bar_time)
            check(len(late) == 1 and ti == c.n_use - 2 and r.state.dir == d0,
                  '%s (b3): %s is still raised on T+1 after the thaw (no event lost)' % (tag, label))
        # (c) wick / body break during RECONFIRMED(INTERNAL)
        name = pref + 's_recon_wick'
        c = case_by_name(name)
        r = rep_of(name)
        w = events_of(r, EV_WICK)
        prev_key = r.keys[c.n_use - 2]
        check(len(w) == 1 and w[0].detail.endswith('restart=1') and r.state.phase == 'HOLD' and r.state.frozen
              and 'PH=RECONFIRMED' in prev_key and 'RSN=INTERNAL' in prev_key
              and lv_id_of_key(r.keys[-1]) == lv_id_of_key(prev_key) and r.state.sweep_time == 0 and not r.state.rec_id,
              '%s (c): a wick through the frozen level during RECONFIRMED(INTERNAL) starts HOLD (restart) with the same level' % tag)
        name = pref + 's_recon_break'
        c = case_by_name(name)
        r = rep_of(name)
        fl = events_of(r, EV_FLIP)
        prev_key = r.keys[c.n_use - 2]
        check(len(fl) == 1 and fl[0].ref == lv_id_of_key(prev_key) and 'PH=RECONFIRMED' in prev_key and 'RSN=INTERNAL' in prev_key
              and EV_RECONF_LOST not in types_of(r) and dir_name(r.state.dir) == dir_name(-d0),
              '%s (c): a body close beyond the frozen level during RECONFIRMED(INTERNAL) flips the bias (priority before reconfirmation)' % tag)
        # (d) invalidation of the recorded FVG and a touch of ANOTHER FVG on the same bar
        name = pref + 's_recon_two_fvg'
        c = case_by_name(name)
        r = rep_of(name)
        lost = events_of(r, EV_RECONF_LOST)
        rec = events_of(r, EV_RECONFIRMED)
        ti = bar_idx(c, lost[0].bar_time)
        frozen_id = lv_id_of_key(r.keys[ti - 1])
        check(len(lost) == 1 and len(rec) == 2 and rec[1].bar_time == lost[0].bar_time and rec[1].ref != lost[0].ref
              and r.state.phase == 'RECONFIRMED' and r.state.recon_reason == 'INTERNAL' and r.state.rec_id == rec[1].ref,
              '%s (d): the recorded FVG is invalidated and another one is touched on the same bar: RECONFIRMED(INTERNAL) again with the other FVG' % tag)
        check(r.state.frozen and all(lv_id_of_key(r.keys[i]) == frozen_id for i in range(ti - 1, c.n_use)) and frozen_id != '-',
              '%s (d): the level stays frozen at the one known before the bar T' % tag)
        check(derive_id_at(c, ti, d0) not in (frozen_id, '-'),
              '%s (d): control: a derivation up to T would have given another level' % tag)
        # (e) AMBIGUITY 20a: no recorded reconfirmation while no protecting level is defined
        name = pref + 's_recon_nolevel'
        c = case_by_name(name)
        r = rep_of(name)
        tb = c.n_use - 2
        touched = False
        sw_, _ = t2.find_swings(c.bars, c.n_use, 2, 2, PERIOD)
        for f in t2.find_fvgs(c.bars, c.n_use, PERIOD):
            tr_ = [x for x in r.tracks if x.id == f.id]
            if tr_ and not tr_[0].invalid and f.index_a + 3 <= tb and c.bars[tb].low <= f.upper and c.bars[tb].high >= f.lower:
                touched = True
        check(touched and 'LV=-' in r.keys[tb - 1] and 'PH=SWEEP_WAIT' in r.keys[tb - 1],
              '%s (e): a valid eligible FVG is touched while the state is SWEEP_WAIT and no protecting level is defined' % tag)
        check(EV_RECONFIRMED not in types_of(r) and r.state.phase == 'SWEEP_WAIT' and not r.state.frozen and not r.state.has_level
              and not any(x.recorded for x in r.tracks),
              '%s (e): that touch is not recorded: no RECONFIRMED, nothing frozen, the wait continues (technical proposal)' % tag)
        name = pref + 's_recon_nolevel_ctl'
        c = case_by_name(name)
        r = rep_of(name)
        rec = events_of(r, EV_RECONFIRMED)
        check(len(rec) == 1 and rec[0].bar_time == c.bars[c.n_use - 2].time and r.state.frozen and r.state.has_level,
              '%s (e): control: the same touch with a defined level is recorded as RECONFIRMED(INTERNAL) and freezes the level' % tag)
        # the structural reconfirmation keeps freezing and falls back to HOLD, not to a thaw
        r = rep_of(pref + 'w_invalid_after_reconf')
        check(r.state.phase == 'HOLD' and r.state.frozen and EV_RECONF_LOST in types_of(r),
              '%s: a structural RECONFIRMED lost to FVG invalidation returns to HOLD and stays frozen (no thaw)' % tag)


def test_23_anchor_by_bars():
    print('--- 23. FINDING 1: anchor located by EXISTING bars (weekend, history gap, window start)')
    base = case_by_name('p16a_converged_break')
    e0 = evaluate(base.bars, base.n_use, base.params())
    refs0 = anchor_refs(e0.state)
    r0 = min(refs0)
    check(e0.reliable and e0.anchor == r0 - 2 * PERIOD,
          'contiguous series: the anchor equals the old arithmetic result (2 existing bars before the earliest reference)')
    for nm, label in (('f1_weekend_gap', 'weekend gap'), ('f1_history_gap', 'history gap (3 missing bars)')):
        c = case_by_name(nm)
        e = evaluate(c.bars, c.n_use, c.params())
        times = [b.time for b in c.bars]
        rmin = min(anchor_refs(e.state))
        i = bar_index_by_time(c.bars, c.n_use, rmin)
        old = rmin - 2 * PERIOD
        check(e.reliable and e.anchor == c.bars[i - 2].time and e.anchor in times and e.anchor_missing == '',
              '%s: the anchor is the open time of the 2nd EXISTING bar before the reference' % label)
        check(old not in times and e.anchor != old,
              '%s: control: the old arithmetic result (reference minus 2 periods) is not a bar of the series' % label)
        check([x.type for x in e.events] == [x.type for x in e0.events] and e.flag == e0.flag and dir_name(e.state.dir) == dir_name(e0.state.dir),
              '%s: same structure and events as the contiguous series (only the absolute times differ)' % label)
    # window start: a reference with exactly Left bars before it, one bar fewer, and the very first bar
    p = Params(left=2)
    bars = [Bar(T0 + i * PERIOD, 110.0, 100.0, 105.0) for i in range(10)]
    st = St()
    st.dir = BULL
    st.origin_ref = bars[2].time
    a, miss = anchor_time(st, p, bars, 10)
    check(a == bars[0].time and miss == '', 'window start: a reference with exactly Left bars before it anchors at the first bar')
    st.origin_ref = bars[1].time
    a, miss = anchor_time(st, p, bars, 10)
    check(a == 0 and miss.startswith('ANCHOR_NEEDS_2_BARS_BEFORE'), 'window start: one bar fewer than Left: missing history reported, no time fabricated (anchor 0)')
    st.origin_ref = bars[0].time
    a, miss = anchor_time(st, p, bars, 10)
    check(a == 0 and miss.startswith('ANCHOR_NEEDS_2_BARS_BEFORE'), 'window start: a reference at the very first bar: missing history')
    # a reference that is not a bar of the series (missing bar): reported, not substituted
    st.origin_ref = bars[5].time + 3600
    a, miss = anchor_time(st, p, bars, 10)
    check(a == 0 and miss.startswith('ANCHOR_REF_NOT_IN_SERIES'), 'a reference that is not in the series: missing history reported, no time fabricated')
    hole = bars[:4] + bars[5:]
    st.origin_ref = bars[4].time
    a, miss = anchor_time(st, p, hole, 9)
    check(a == 0 and miss.startswith('ANCHOR_REF_NOT_IN_SERIES'), 'history gap on the reference bar itself: the reference is missing, reported')
    # one missing bar before the reference: Left EXISTING bars are used, the hole is skipped
    st.origin_ref = bars[6].time
    a, miss = anchor_time(st, p, hole, 9)
    check(a == bars[3].time and miss == '', 'a hole before the reference: the Left existing bars are used (the missing slot is skipped)')
    # several references: the earliest anchor wins, one missing reference makes the whole anchor missing
    st.origin_ref = bars[8].time
    st.has_level = True
    st.lv_pivot = bars[6].time
    st.lv_ext = bars[7].time
    st.lv_prev = bars[3].time
    a, miss = anchor_time(st, p, bars, 10)
    check(a == bars[1].time and miss == '', 'several references: the earliest anchor wins')
    st.lv_prev = bars[1].time
    a, miss = anchor_time(st, p, bars, 10)
    check(a == 0 and miss != '', 'several references: one reference without Left bars before it makes the anchor missing (never partial)')
    # which references count
    r = rep_of('s_recon_later_swing')
    refs = anchor_refs(r.state)
    check(r.state.sweep_time in refs and r.state.lv_pivot in refs and r.state.origin_ref not in refs and r.state.wk_src not in refs,
          'frozen RECONFIRMED(INTERNAL): the references are the sweep and the frozen level pivots (origin ignored, as for HOLD)')
    r = rep_of('w_wick')
    refs = anchor_refs(r.state)
    check(r.state.wk_src in refs and r.state.lv_pivot in refs and r.state.origin_ref not in refs and 0 not in refs,
          'HOLD: the references are the source wick and the frozen level pivots (origin ignored)')
    r = rep_of('s_recon_thaw')
    refs = anchor_refs(r.state)
    check(r.state.origin_ref in refs and r.state.sweep_time in refs and r.state.lv_pivot in refs,
          'thawed SWEEP_WAIT (not frozen): the references are the origin, the level pivots and the sweep')
    # the reliability rule
    check(ab_reasons('K', 'K', 'E', 'E', BULL, 0, 50, 'ANCHOR_NEEDS_2_BARS_BEFORE x') == 'ANCHOR_HISTORY_MISSING',
          'missing anchor history: LIMITED_BY_HISTORY with its own reason (not reported as a warm-up case)')
    check(ab_reasons('K1', 'K2', 'E', 'E', BULL, 0, 50, 'm') == 'AB_STATE_DIFF+ANCHOR_HISTORY_MISSING',
          'missing anchor history combines with the other reasons in the fixed order')
    check(ab_reasons('K', 'K', 'E', 'E', 0, 0, 50, 'm') == '', 'NONE has no anchor: missing-history text cannot make it LIMITED')
    c = case_by_name('p16c_anchor_warmup')
    e = evaluate(c.bars, c.n_use, c.params())
    check(not e.reliable and e.reason == 'ANCHOR_IN_WARMUP' and e.anchor == c.bars[0].time and e.anchor_missing == '',
          'reference close to the start of the series (Left bars exist): the anchor is the first bar and the case is LIMITED by the warm-up rule')


def test_21_no_fixed_count():
    print('--- 21. no fixed BOS count')
    levels = []
    for k in (1, 2, 3):
        r = rep_of('bos_%d' % k)
        t = types_of(r)
        check(dir_name(r.state.dir) == 'BULL' and r.state.phase == 'ACTIVE' and r.state.origin == 'BREAK' and t[0] == EV_BREAK_SET
              and t.count(EV_CONTINUATION) == k - 1 and EV_FLIP not in t, '%d successive break(s): same bias rule (BREAK_SET + %d CONTINUATION), no flip' % (k, k - 1))
        levels.append(r.state.lv_price if r.state.has_level else 0)
    check(levels[0] < levels[1] < levels[2], 'the protecting low follows the last up-leg whatever the number of breaks')


def test_ids_and_windows():
    print('--- technical requirement (a): identities use absolute times, stable under window shifts')
    import re
    id_pat = re.compile(r'^(SH|SL)\d{12}_\d{12}_\d{12}$|^(HH|LL|IH|IL)\d{12}_\d{12}$|^F\d{12}[UD]$')
    ev_pat = re.compile(r'^[A-Z_]+@\d{12}#[A-Za-z0-9_+]+$')
    bad = 0
    for c in build_cases():
        if c.kind != 'R':
            continue
        r = rep_of(c.name)
        for e in r.events:
            if not ev_pat.match(e.id()):
                bad += 1
            for part in e.ref.split('+'):
                if not id_pat.match(part):
                    bad += 1
        for tr in r.tracks:
            if not id_pat.match(tr.id):
                bad += 1
        if r.state.has_level and not id_pat.match(r.state.lv_id):
            bad += 1
    check(bad == 0, 'all level, FVG and event IDs consist only of type letters and 12-digit absolute time stamps')
    common_total = 0
    stable = True
    for name, shifts in (('w_a_is_wick', (1, 2, 3, 5)), ('b2_none_touched', (1, 2, 4)), ('e_sweep_fvg_touch', (1, 3, 6)),
                         ('c_history', (1, 2, 3)), ('b2_active_retro', (1, 2, 3, 5)), ('m_w_a_is_wick', (1, 2, 3))):
        c = case_by_name(name)
        full = replay(c.bars, len(c.bars), c.params())
        fmap = dict(((e.type, e.bar_time), e.id()) for e in full.events)
        for sft in shifts:
            sh = replay(c.bars[sft:], len(c.bars) - sft, c.params())
            for e in sh.events:
                k = (e.type, e.bar_time)
                if k in fmap:
                    common_total += 1
                    if fmap[k] != e.id():
                        stable = False
            if sh.state.has_level and full.state.has_level and sh.state.lv_price == full.state.lv_price and sh.state.lv_id != full.state.lv_id:
                stable = False
            ft = dict((tr.id, 1) for tr in full.tracks)
            for tr in sh.tracks:
                if tr.id not in ft and full.state.phase == sh.state.phase:
                    stable = False
    check(common_total >= 10 and stable, 'the same event/level/FVG keeps the same ID when the window start moves (%d common events compared)' % common_total)


def test_consumer():
    print('--- technical requirement (b): history of events versus new events for the consumer')
    p = Params(lookback=20, rebuild=1000)
    c = case_by_name('p16a_converged_break')
    base = c.bars
    last = Bar(base[-1].time + PERIOD, 135.0, 104.0, 112.0)          # structural wick through the protecting low (109)
    e0 = evaluate_latest(base, len(base), p)
    cur = baseline_cursor(e0)
    check(e0.reliable and len(e0.events) >= 2 and cur == base[-1].time, 'the replay carries the full event log (history) with absolute bar times')
    st_, evs = consume_new(e0, cur, PERIOD)
    check(st_ == C_NOTHING_NEW and evs == [], 'init/restart: the cursor is set to the last closed bar, no historical event is re-emitted')
    st_, evs = consume_new(e0, 0, PERIOD)
    check(st_ == C_GAP and evs == [], 'an uninitialised cursor emits nothing (it must be baselined first)')
    e0b = evaluate_latest(base, len(base), p)
    check(consume_new(e0b, cur, PERIOD)[0] == C_NOTHING_NEW, 're-evaluation at the same bar emits nothing')
    nb = base + [last]
    e1 = evaluate_latest(nb, len(nb), p)
    st_, evs = consume_new(e1, cur, PERIOD)
    check(st_ == C_OK and [x.type for x in evs] == [EV_WICK] and evs[0].bar_time == last.time, 'the next closed bar emits its event (WICK) once')
    cur = baseline_cursor(e1)
    st_, evs = consume_new(evaluate_latest(nb, len(nb), p), cur, PERIOD)
    check(st_ == C_NOTHING_NEW and evs == [], 'and not a second time')
    # a restart on the same bars: baseline again, nothing is re-emitted although the log holds the WICK
    e2 = evaluate_latest(nb, len(nb), p)
    check(any(x.type == EV_WICK for x in e2.events) and consume_new(e2, baseline_cursor(e2), PERIOD)[1] == [],
          'a restart sets the baseline again: the WICK stays in the history and is not a new signal')
    gap = nb + [Bar(nb[-1].time + PERIOD, 115.0, 105.0, 110.0), Bar(nb[-1].time + 2 * PERIOD, 116.0, 106.0, 111.0)]
    e3 = evaluate_latest(gap, len(gap), p)
    st_, evs = consume_new(e3, baseline_cursor(e1), PERIOD)
    check(st_ == C_GAP and evs == [], 'a cursor older than the previous bar (missed bars) emits nothing and must be re-baselined')
    # a limited evaluation emits nothing
    lim = case_by_name('p16b_ab_difference')
    el = evaluate_latest(lim.bars, len(lim.bars), lim.params())
    check(consume_new(el, lim.bars[-2].time, PERIOD) == (C_NOT_RELIABLE, []), 'a LIMITED_BY_HISTORY evaluation emits no event')


def test_deferred():
    print('--- deferred groups (NOT counted as PASS)')
    deferred('test 9 (EA lifecycle and reload: no duplicate objects, clear/rebuild as in T002)')
    deferred('test 18 (intrabar overlay P12: crossing blocks only, wick-only close -> HOLD, body close -> flip, equality)')
    deferred('test 20 (target candidate P13: latest HH shown, pullback level not, newer HH changes it, T002 ERL unchanged)')
    deferred('drawing/panel tests (criterion 10: labels, panel, LIMITED_BY_HISTORY display)')
    deferred('M5/M15 logic (out of scope)')


# ------------------------------------------------------------ MQL5 emit ----
def chunks(text, n=700):
    return [text[i:i + n] for i in range(0, len(text), n)]


def emit_mql():
    cases = build_cases()
    out = ['// BEGIN GENERATED CASE DATA (tests/t003_reference_test.py --emit-mql)']
    out.append('#define T3_CASE_COUNT %d' % len(cases))
    out.append('void T3LoadCase(const int id, MqlRates &bars[], int &n, int &kind, int &lookback, int &rebuild, int &hard_cap, string &name, string &expected)')
    out.append('  {')
    out.append('   switch(id)')
    out.append('     {')
    for i, c in enumerate(cases):
        exp = run_case(c)
        assert '"' not in exp and '\\' not in exp
        flat = ','.join('%r,%r,%r' % (b.high, b.low, b.close) for b in c.bars)
        out.append('      case %d:' % i)
        out.append('        {')
        out.append('         double d[] = {%s};' % flat)
        out.append('         name = "%s"; kind = %d; lookback = %d; rebuild = %d; hard_cap = %d;' % (
            c.name, 0 if c.kind == 'R' else 1, c.lookback, c.rebuild, c.hard_cap))
        out.append('         expected = "";')
        for part in chunks(exp):
            out.append('         expected += "%s";' % part)
        first = (c.bars[0].time - T0) // PERIOD
        assert T0 + first * PERIOD == c.bars[0].time
        slots = [(b.time - T0) // PERIOD for b in c.bars]
        for b, sl in zip(c.bars, slots):
            assert T0 + sl * PERIOD == b.time
        if slots == list(range(first, first + len(c.bars))):
            out.append('         T3FillBars(d, %d, %d, bars);' % (len(c.bars), first))
        else:
            # open times with holes (weekend / missing history): explicit 4h slot numbers
            out.append('         int sl[] = {%s};' % ','.join(str(x) for x in slots))
            out.append('         T3FillBarsAt(d, %d, sl, bars);' % len(c.bars))
        out.append('         n = %d;' % c.n_use)
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
    print('T003 reference model tests - these verify the PYTHON MODEL of the PROPOSED rules,')
    print('NOT the MQL5 source. T003_LogicTest.mq5 has not been compiled or run.')
    test_01_body_vs_wick()
    test_02_correction()
    test_03_wick_blocks()
    test_04_prewick()
    test_05_new_fvg()
    test_06_repeated()
    test_07_level_selection()
    test_08_no_lookahead()
    test_10_buy_mirror()
    test_11_acceptance_ab()
    test_12_retro()
    test_13_one_flip_trigger()
    test_14_history_and_precedence()
    test_15_determinism()
    test_16_depth_check()
    test_16u_units()
    test_17_depth_and_window()
    test_19_internal_liquidity()
    test_21_no_fixed_count()
    test_22_freeze_internal()
    test_23_anchor_by_bars()
    test_ids_and_windows()
    test_consumer()
    test_deferred()
    print('')
    print('%d passed, %d failed, %d deferred (deferred are NOT passes)' % (len(PASSES), len(FAILS), len(DEFERRED)))
    if FAILS:
        for f in FAILS:
            print('  FAILED: ' + f)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
