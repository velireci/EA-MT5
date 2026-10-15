"""T012 integration helpers for the observation-only preview (Python mirror of src/include/DailyPreviewGate.mqh).

evaluate(): maps the preview's explicit inputs to t012_daily_reference.check (NOT copied). MANUAL (use_snapshot False) evaluates nothing, so the
preview behaves exactly as before. DAILY_SNAPSHOT evaluates the supplied figures; unknown figures (negative counters, unknown result, unset
balance) become invalid input -> BLOCK, never a limit. final_preview(): a daily BLOCK can only block, never allow; MANUAL changes nothing.
cancel_pending_due is DIAGNOSTIC only: nothing is cancelled or closed anywhere. No clock, no account or history read, no persistence.
"""
import t012_daily_reference as dl

MAX_COUNT = dl.MAX_COUNT


def counter(value):
    return value if isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= MAX_COUNT else -1


def evaluate(use_snapshot, utc, snapshot_day, balance_start, result_known, closed_result, trades_today, wins_today, consecutive_losses, max_trades):
    """Returns (evaluated, Result or None)."""
    if not use_snapshot:
        return False, None
    max_set = isinstance(max_trades, int) and not isinstance(max_trades, bool) and max_trades >= 0
    mt = (MAX_COUNT + 1 if max_trades > MAX_COUNT else max_trades) if max_set else 0
    res = dl.check(utc, snapshot_day, balance_start, closed_result if result_known else float('nan'), counter(trades_today), counter(wins_today),
                   counter(consecutive_losses), mt, max_set)
    return True, res


def final_preview(loss_ok, permit_allow, daily_evaluated, daily_allowed):
    return bool(loss_ok and permit_allow and ((not daily_evaluated) or daily_allowed))
