"""T004 round 4: ORDINARY H4 FVG-touch context source. TECHNICAL PROPOSAL, not a client rule.

Reuses the T002 reference model (swings, trend, interval, FVG FRESH/TOUCHED/INVALID, IRL class,
nearest-first ordering, ERL state, setup-active test) UNCHANGED. Adds only the chronological
bookkeeping that T002 (stateless drawing) does not have: which FVG a touching H4 candle records,
until when that record lives, and what a later touch does.

Rules (each is labelled in docs/T004-m15.md; reused vs proposed):
 * At every H4 close j the analysis uses ONLY the last `window` closed bars ending at j (post) and
   ending at j-1 (pre). The final H4 state is never used for an earlier moment.
 * A touch is judged against the state KNOWN BEFORE the touching candle opens (pre): trending
   direction, valid interval, ERL untouched, and the FVG is an IRL candidate (FRESH/TOUCHED, same
   direction, inside the interval). The FVG's candle C therefore closed at or before the touching
   candle's open. The touching candle's wick range must intersect the zone (inclusive).
 * The touch is RECORDED at the CLOSE of the touching candle (valid_from = known = open + H4 period).
   The record only exists if the same FVG is still a valid IRL candidate with an active setup in
   the post state (a close strictly beyond the far edge on the touching candle itself = INVALID wins).
 * With several touched candidates the T002 nearest-first ordering decides (reference price = close
   of the last bar closed before the touching candle: T002's historical selection price convention).
 * While a record is open, later touches do not change it (no churn). It is revoked at the first H4
   close where it no longer holds (reasons below). No expiry by bar count is invented.
 * After revocation a later touch can record again. RETOUCH_AFTER_LOSS: any valid IRL candidate,
   also one recorded before (T002: a touch does not remove a zone, no re-use limit).
   RETOUCH_FIRST_ONLY: an FVG id is recorded at most once per scan.
 * RETOUCH_UNSET (default) leaves every context unselected: the observer blocks.
"""
from dataclasses import dataclass, field
import math
import t002_reference_test as t2
from t004_reference import Context

H4 = 14400
SOURCE_ID = 'T002_H4_TOUCH_PROPOSAL'
T003_SOURCE_ID = 'T003_PROTOTYPE'
RETOUCH_UNSET, RETOUCH_AFTER_LOSS, RETOUCH_FIRST_ONLY = 0, 1, 2


@dataclass
class OrdUpdate:
    known: int
    context: Context
    kind: str          # OPEN / REPLACE / CLOSE
    reason: str


@dataclass
class OrdScan:
    status: str = 'EMPTY'
    updates: list = field(default_factory=list)
    steps: int = 0
    opened: int = 0
    closed: int = 0
    replaced: int = 0


def direction_agreement(direction, other):
    """Display flag only. Never resolves a disagreement."""
    o = 1 if other.startswith('BULL') else (-1 if other.startswith('BEAR') else 0)
    if direction == 0 or o == 0:
        return 'NO_DIRECTION'
    return 'AGREE' if direction == o else 'DISAGREE'


def setup_active(res, selectable):
    return (res.range_state == 'VALID' and res.direction in ('BULLISH', 'BEARISH')
            and res.erl_state == 'UNTOUCHED' and selectable > 0)


def survival(direction, fvg_id, post, reliable):
    """'' while the record holds, else the reason. Order is only a labelling priority."""
    if not reliable:
        return 'HISTORY_PARTIAL'
    r = post.res
    if r.direction != ('BULLISH' if direction > 0 else 'BEARISH'):
        return 'TREND_CHANGE'
    f = next((x for x in post.fvgs if x.id == fvg_id), None)
    if f is None:
        return 'FVG_NOT_IN_WINDOW'
    if f.state == 'INVALID':
        return 'FVG_INVALID'
    if r.range_state != 'VALID':
        return 'INTERVAL_LOST'
    if r.erl_state != 'UNTOUCHED':
        return 'ERL_TAKEN'
    if f.cls != 'IRL':
        return 'NOT_IRL'
    return ''


def _valid_bars(bars):
    for i, b in enumerate(bars):
        if (b.time <= 0 or b.time % H4 or not all(math.isfinite(x) for x in (b.high, b.low, b.close))
                or b.low <= 0 or b.high < b.low or not b.low <= b.close <= b.high
                or (i and b.time <= bars[i - 1].time)):
            return False
    return True


def scan(bars, scan_from, left=2, right=2, window=300, retouch=RETOUCH_UNSET):
    out = OrdScan('INVALID_INPUT')
    n = len(bars)
    if (scan_from < 0 or not 1 <= left <= 10 or not 1 <= right <= 10 or not 50 <= window <= 1000
            or retouch not in (0, 1, 2)):
        return out
    if not _valid_bars(bars):
        out.status = 'INVALID_H4'
        return out
    gate = retouch != RETOUCH_UNSET
    held = None            # (direction, fvg_id)
    recorded = set()
    for j in range(max(scan_from, 1), n):
        known = bars[j].time + H4
        pre = bars[max(0, j - window):j]
        post = bars[max(0, j + 1 - window):j + 1]
        reliable = len(pre) >= window and len(post) >= window and len(pre) >= 2 * (left + right) + 3
        apost = t2.analyze(post, len(post), left, right, H4)
        lost = ''
        if held is not None:
            lost = survival(held[0], held[1], apost, reliable)
            if lost:
                held = None
        chosen = None
        if held is None and reliable:
            apre = t2.analyze(pre, len(pre), left, right, H4)
            order = t2.select_irl(apre.fvgs, apre.res, pre[-1].close)
            if setup_active(apre.res, len(order)):
                b = bars[j]
                for f in order:
                    if retouch == RETOUCH_FIRST_ONLY and f.id in recorded:
                        continue
                    if not (b.low <= f.upper and b.high >= f.lower):
                        continue
                    d = 1 if f.bullish else -1
                    if survival(d, f.id, apost, reliable):
                        continue
                    chosen = f
                    break
        if chosen is not None:
            d = 1 if chosen.bullish else -1
            ctx = Context('T002TOUCH-%s-%s' % (t2.ts(known), chosen.id), d, SOURCE_ID, chosen.id,
                          chosen.lower, chosen.upper, chosen.confirm_time, known, True, True, gate)
            held = (d, chosen.id)
            recorded.add(chosen.id)
            out.opened += 1
            if lost:
                out.replaced += 1
            out.updates.append(OrdUpdate(known, ctx, 'REPLACE' if lost else 'OPEN',
                                         ('after ' + lost) if lost else ''))
        elif lost:
            out.closed += 1
            out.updates.append(OrdUpdate(known, Context(), 'CLOSE', lost))
        out.steps += 1
    out.status = 'OK' if out.steps else 'EMPTY'
    return out
