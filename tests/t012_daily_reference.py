"""T012 pure daily-limit check (Python mirror of src/include/DailyLimits.mqh).

NOT a trading module: no order, no cancellation, no account or position read, no clock, no persistence, no real reset, no EA wiring. Every
number is an ARGUMENT supplied by the caller. It only answers whether NEW ENTRIES are blocked for the Tirane day of the supplied instant and
whether a daily limit is PROVEN reached (flag cancel_pending_due); it never touches existing positions.
The Tirane day is NOT recomputed here: it comes from T009 (t009_session_reference.evaluate / SP_Evaluate), which owns the DST rules.

CLIENT RULES (STRATEGY_SPEC section 9, K B1; named constants, not inputs): entries are blocked when
  at least 1 win today;   at least 2 consecutive losses today;   the closed result is <= -2% of the balance at the start of the day;
  and, for a limit that the CALLER supplies, when the number of trades reaches it. 2 versus 3 trades is NOT decided here (open client question):
  the limit is an input, a missing limit is POLICY_UNSET -> blocked.
NOT done here: classifying partial exits, costs or breakeven as win/loss/trade (the caller supplies wins, consecutive losses and the trade count
already classified), floating results (only the closed result of the robot is an input), the balance at the start of the day (supplied).

INPUTS: utc (int seconds), snapshot_day (int yyyymmdd, the Tirane day the figures belong to), balance_start (> 0), closed_result (monetary, any
sign), trades_today (int >= 0), wins_today (int >= 0), consecutive_losses (int >= 0), max_trades (int >= 1) and max_trades_set (bool).
Unknown = None / non-finite / negative counter / wrong type -> INVALID_SNAPSHOT:<name>.

CONSISTENCY CHECKS (counting identities only; no new definition of a trade is invented):
  wins <= trades;  consecutive_losses <= trades;  wins + consecutive_losses <= trades  (a trade in the loss streak is not a win).
  The sign of closed_result is NOT compared with wins or losses: a partial exit, a cost or a breakeven makes that comparison undefined.
  A snapshot of another Tirane day than the day of utc is STALE_SNAPSHOT_DAY (no figures of yesterday are used today). The midnight reset
  itself (zeroing the counters) is the caller's; this module only refuses to mix days.

OUTPUT: entry_allowed, primary (first reason or ''), reasons (all reasons in a FIXED order), cancel_pending_due, daily_limit_reached, day_key.
REASON ORDER: validity reasons (INVALID_UTC | UNSUPPORTED_YEAR, STALE_SNAPSHOT_DAY, INVALID_SNAPSHOT:snapshot_day, :balance_start, :closed_result,
:trades_today, :wins_today, :consecutive_losses, :max_trades_per_day, INCONSISTENT_COUNTERS:wins_exceed_trades, :losses_exceed_trades,
:wins_plus_losses_exceed_trades). If ANY validity reason exists, ONLY those are returned (the figures are not trusted, so no limit is judged)
and cancel_pending_due / daily_limit_reached are False. With valid inputs: DAILY_WIN_STOP, CONSECUTIVE_LOSSES_STOP, DAILY_LOSS_LIMIT,
MAX_TRADES_REACHED (only with a supplied limit), then POLICY_UNSET:max_trades_per_day when no limit is supplied.
cancel_pending_due / daily_limit_reached are True ONLY when one of the four limit reasons is proven with valid inputs. An error or a missing
policy never invents a daily limit. Existing positions are never touched (nothing here refers to them).
"""
import math
from dataclasses import dataclass, field

import t009_session_reference as t009

WIN_STOP_AT = 1
CONSECUTIVE_LOSS_STOP_AT = 2
LOSS_FRACTION_DIVISOR = 50.0            # 2% = 1/50 of the balance at the start of the day
DBL_EPSILON = 2.220446049250313e-16
MAX_COUNT = 100000

R_WIN, R_STREAK, R_LOSS, R_TRADES, R_UNSET = ('DAILY_WIN_STOP', 'CONSECUTIVE_LOSSES_STOP', 'DAILY_LOSS_LIMIT', 'MAX_TRADES_REACHED',
                                              'POLICY_UNSET:max_trades_per_day')


@dataclass
class Result:
    entry_allowed: bool
    primary: str = ''
    reasons: list = field(default_factory=list)
    cancel_pending_due: bool = False
    daily_limit_reached: bool = False
    day_key: int = 0


def _num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool) and math.isfinite(x)


def _count(x):
    return isinstance(x, int) and not isinstance(x, bool) and 0 <= x <= MAX_COUNT


def check(utc, snapshot_day, balance_start, closed_result, trades_today, wins_today, consecutive_losses, max_trades, max_trades_set):
    bad = []
    s = t009.evaluate(utc) if isinstance(utc, int) and not isinstance(utc, bool) else {'status': 'INVALID_INPUT'}
    day = 0
    if s['status'] == 'OK':
        day = s['day']
    elif s['status'] == 'UNSUPPORTED_YEAR':
        bad.append('UNSUPPORTED_YEAR')
    else:
        bad.append('INVALID_UTC')
    if isinstance(snapshot_day, bool) or not isinstance(snapshot_day, int) or not (19960101 <= snapshot_day <= 20991231):
        bad.append('INVALID_SNAPSHOT:snapshot_day')
    elif day and snapshot_day != day:
        bad.append('STALE_SNAPSHOT_DAY')
    if not _num(balance_start) or balance_start <= 0:
        bad.append('INVALID_SNAPSHOT:balance_start')
    if not _num(closed_result):
        bad.append('INVALID_SNAPSHOT:closed_result')
    t_ok, w_ok, l_ok = _count(trades_today), _count(wins_today), _count(consecutive_losses)
    if not t_ok:
        bad.append('INVALID_SNAPSHOT:trades_today')
    if not w_ok:
        bad.append('INVALID_SNAPSHOT:wins_today')
    if not l_ok:
        bad.append('INVALID_SNAPSHOT:consecutive_losses')
    if not isinstance(max_trades_set, bool):
        bad.append('INVALID_SNAPSHOT:max_trades_per_day')
    elif max_trades_set and (isinstance(max_trades, bool) or not isinstance(max_trades, int) or not (1 <= max_trades <= MAX_COUNT)):
        bad.append('INVALID_SNAPSHOT:max_trades_per_day')
    if t_ok and w_ok and wins_today > trades_today:
        bad.append('INCONSISTENT_COUNTERS:wins_exceed_trades')
    if t_ok and l_ok and consecutive_losses > trades_today:
        bad.append('INCONSISTENT_COUNTERS:losses_exceed_trades')
    if t_ok and w_ok and l_ok and wins_today <= trades_today and consecutive_losses <= trades_today and wins_today + consecutive_losses > trades_today:
        bad.append('INCONSISTENT_COUNTERS:wins_plus_losses_exceed_trades')
    if bad:
        return Result(False, bad[0], bad, False, False, day)
    limits = []
    if wins_today >= WIN_STOP_AT:
        limits.append(R_WIN)
    if consecutive_losses >= CONSECUTIVE_LOSS_STOP_AT:
        limits.append(R_STREAK)
    threshold = balance_start / LOSS_FRACTION_DIVISOR
    if closed_result <= -threshold + 4 * DBL_EPSILON * max(1.0, threshold):
        limits.append(R_LOSS)
    if max_trades_set and trades_today >= max_trades:
        limits.append(R_TRADES)
    reasons = list(limits)
    if not max_trades_set:
        reasons.append(R_UNSET)
    return Result(not reasons, reasons[0] if reasons else '', reasons, bool(limits), bool(limits), day)
