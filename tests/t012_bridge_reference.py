"""T012 BRIDGE from the history FACTS to the daily-limit check (Python mirror of src/include/DailyBridge.mqh).

PURPOSE: turn READY + complete daily-history FACTS (t012_history_reference.Facts) plus EXPLICIT policy inputs into the arguments of the
existing t012_daily_reference.check (reused, NOT copied: no limit, tolerance or reason of the check is repeated here). PURE: no terminal read,
no account or history API, no clock, no order, no persistence, no real reset, no EA wiring. It chooses NO policy.

WHAT THE BRIDGE REQUIRES (every missing item is a BLOCK with its own reason; all missing items are listed, in this order):
  1 verdict READY                      HISTORY_NOT_READY:<UNKNOWN|BLOCK|?>   (an UNKNOWN / BLOCK carries no facts; nothing else about the facts is read)
  2 facts.complete == True             HISTORY_INCOMPLETE                    (the owner assertion plus every detectable check, set by the history layer)
  3 balance at the start of the day    BALANCE_START_UNSET                   (never reconstructed from the facts: balance_start_known stays False)
  4 ... for the SAME Tirane day        BALANCE_DAY_MISMATCH                  (balance.day != facts.day_key)
  5 result formula policy              POLICY_UNSET:result_formula | POLICY_UNSUPPORTED:result_formula
  6 trade / win / loss classification  POLICY_UNSET:trade_classification | POLICY_UNSUPPORTED:trade_classification
  7 classification vs facts            CLASSIFICATION_CONTRADICTS_FACTS:trades_without_positions   (trades > 0 while the facts hold no robot position)
SUPPORTED POLICIES (the only ones; anything else is UNSUPPORTED and blocks, no alternative is guessed):
  result_formula   : PROFIT | PROFIT_COMMISSION_SWAP | PROFIT_COMMISSION_SWAP_FEE  = which of the three candidate sums of the facts is the closed
                     result of the day. UNSET is the history layer's own value and blocks. Which one is right is a CLIENT / OWNER decision (open).
  classification   : CALLER_CLASSIFIED = the caller states trades_today / wins_today / consecutive_losses AFTER applying ITS OWN definition of
                     trade, win, loss and breakeven (partial exits, costs, breakeven). The bridge cannot verify that definition; it only refuses to
                     run without it. A deal count is never used as a trade count; a missing count is never turned into zero (a negative / absurd
                     value reaches the daily check as INVALID_SNAPSHOT). UNSET blocks.
The trade limit (2 or 3) stays an input: max_trades_set False reaches the daily check as POLICY_UNSET:max_trades_per_day (it still proves the
other limits and sets cancel_pending_due only then, exactly as the daily check does).
THE WRONG DAY: the facts day is passed as snapshot_day, so a history of another Tirane day than the one of `utc` ends as STALE_SNAPSHOT_DAY from the
daily check (that check owns the Tirane day through T009).
When any bridge reason exists the daily check is NOT called: entry_allowed False, cancel_pending_due False, daily_limit_reached False (no limit is
proven by missing data). Otherwise the result of the daily check is propagated unchanged.
"""
import math
from dataclasses import dataclass, field

import t012_daily_reference as dl

READY, UNKNOWN, BLOCK = 'READY', 'UNKNOWN', 'BLOCK'
RESULT_FORMULAS = {'PROFIT': 'candidate_profit',
                   'PROFIT_COMMISSION_SWAP': 'candidate_profit_commission_swap',
                   'PROFIT_COMMISSION_SWAP_FEE': 'candidate_profit_commission_swap_fee'}
CLASSIFICATION_SUPPORTED = 'CALLER_CLASSIFIED'
UNSET = 'UNSET'
MAX_REASONS = 16


@dataclass
class Balance:
    known: bool = False
    day: int = 0
    amount: float = 0.0


@dataclass
class Policy:
    result_formula: str = UNSET
    classification: str = UNSET


@dataclass
class Classified:
    trades: int = -1
    wins: int = -1
    consecutive_losses: int = -1


@dataclass
class Result:
    entry_allowed: bool = False
    primary: str = ''
    reasons: list = field(default_factory=list)
    dl_called: bool = False
    closed_result: float = float('nan')
    cancel_pending_due: bool = False
    daily_limit_reached: bool = False
    day_key: int = 0


def _policy_reason(name, value, supported):
    if value == UNSET:
        return 'POLICY_UNSET:' + name
    if value not in supported:
        return 'POLICY_UNSUPPORTED:' + name
    return ''


def check(verdict, facts, utc, balance, policy, cls, max_trades, max_trades_set):
    r = Result()
    bad = []
    ready = verdict == READY
    if not ready:
        bad.append('HISTORY_NOT_READY:' + (verdict if verdict in (UNKNOWN, BLOCK) else '?'))
    elif not facts.complete:
        bad.append('HISTORY_INCOMPLETE')
    if not balance.known:
        bad.append('BALANCE_START_UNSET')
    elif ready and balance.day != facts.day_key:
        bad.append('BALANCE_DAY_MISMATCH')
    rf = _policy_reason('result_formula', policy.result_formula, RESULT_FORMULAS)
    if rf:
        bad.append(rf)
    cf = _policy_reason('trade_classification', policy.classification, (CLASSIFICATION_SUPPORTED,))
    if cf:
        bad.append(cf)
    elif ready and cls.trades > 0 and len(facts.positions) == 0:
        bad.append('CLASSIFICATION_CONTRADICTS_FACTS:trades_without_positions')
    if bad:
        r.reasons = bad[:MAX_REASONS]
        r.primary = bad[0]
        return r
    r.closed_result = getattr(facts, RESULT_FORMULAS[policy.result_formula])
    d = dl.check(utc, facts.day_key, balance.amount, r.closed_result, cls.trades, cls.wins, cls.consecutive_losses, max_trades, max_trades_set)
    r.dl_called = True
    r.entry_allowed = d.entry_allowed
    r.primary = d.primary
    r.reasons = list(d.reasons)
    r.cancel_pending_due = d.cancel_pending_due
    r.daily_limit_reached = d.daily_limit_reached
    r.day_key = d.day_key
    return r
