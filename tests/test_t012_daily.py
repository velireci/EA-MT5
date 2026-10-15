"""T012 tests: pure daily-limit check (no order, no account read, no persistence)."""
import math
import os
import random
import re
import sys
import unittest
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t009_session_reference as t009  # noqa: E402
import t012_daily_fixtures as fx  # noqa: E402
import t012_daily_reference as dl  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ORDER = [None]


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def run_rows(mod):
    bad = []
    for r in fx.ROWS:
        o = mod.check(r['utc'], r['snap'], r['bal'], r['res'], r['trades'], r['wins'], r['loss'], r['mtr'], bool(r['mset']))
        exp = (bool(r['allowed']), r['primary'], r['reasons'], bool(r['cancel']), bool(r['cancel']), r['day'])
        got = (o.entry_allowed, o.primary, o.reasons, o.cancel_pending_due, o.daily_limit_reached, o.day_key)
        if got != exp:
            bad.append((r['name'], got, exp))
    return bad


CANONICAL = ['UNSUPPORTED_YEAR', 'INVALID_UTC', 'INVALID_SNAPSHOT:snapshot_day', 'STALE_SNAPSHOT_DAY', 'INVALID_SNAPSHOT:balance_start',
             'INVALID_SNAPSHOT:closed_result', 'INVALID_SNAPSHOT:trades_today', 'INVALID_SNAPSHOT:wins_today', 'INVALID_SNAPSHOT:consecutive_losses',
             'INVALID_SNAPSHOT:max_trades_per_day', 'INCONSISTENT_COUNTERS:wins_exceed_trades', 'INCONSISTENT_COUNTERS:losses_exceed_trades',
             'INCONSISTENT_COUNTERS:wins_plus_losses_exceed_trades', 'DAILY_WIN_STOP', 'CONSECUTIVE_LOSSES_STOP', 'DAILY_LOSS_LIMIT',
             'MAX_TRADES_REACHED', 'POLICY_UNSET:max_trades_per_day']


class Scenarios(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(dl), [])

    def test_coverage(self):
        names = {r['name'] for r in fx.ROWS}
        for need in ('LOSS_BELOW_2_PERCENT', 'LOSS_AT_2_PERCENT_BLOCKS', 'LOSS_AFTER_2_PERCENT_BLOCKS', 'ONE_WIN_STOPS_THE_DAY', 'TWO_CONSECUTIVE_LOSSES_STOP',
                     'TRADES_AT_THE_SUPPLIED_LIMIT', 'POLICY_UNSET_BLOCKS_WITHOUT_A_DAILY_LIMIT', 'ALL_FOUR_LIMITS', 'INVALID_INPUT_HIDES_A_PROVEN_LIMIT',
                     'SNAPSHOT_OF_THE_NEXT_DAY', 'SUMMER_MIDNIGHT_NEW_DAY', 'WINTER_MIDNIGHT_NEW_DAY', 'SPRING_FORWARD_NEXT_DAY', 'FALL_BACK_REPEATED_HOUR'):
            self.assertIn(need, names)

    def test_days_agree_with_an_independent_tzdata_computation(self):
        tz = ZoneInfo('Europe/Tirane')
        for r in fx.ROWS:
            if r['day'] == 0:
                continue
            local = datetime.fromtimestamp(r['utc'], timezone.utc).astimezone(tz)
            self.assertEqual(local.year * 10000 + local.month * 100 + local.day, r['day'], r['name'])

    def test_day_boundary_sweep_around_every_local_midnight(self):
        tz = ZoneInfo('Europe/Tirane')
        d = datetime(2026, 1, 1, tzinfo=timezone.utc)
        n = 0
        while d < datetime(2028, 1, 1, tzinfo=timezone.utc):
            for delta in (-1, 0, 1):
                t = int(d.timestamp()) + delta
                local = datetime.fromtimestamp(t, timezone.utc).astimezone(tz)
                want = local.year * 10000 + local.month * 100 + local.day
                o = dl.check(t, want, 10000.0, 0.0, 0, 0, 0, 3, True)
                self.assertEqual((o.entry_allowed, o.day_key), (True, want), t)
                o = dl.check(t, want + 1 if want % 100 < 28 else want - 1, 10000.0, 0.0, 0, 0, 0, 3, True)
                self.assertIn('STALE_SNAPSHOT_DAY', o.reasons)
                n += 1
            d += timedelta(hours=1)
        self.assertGreater(n, 40000)

    def test_two_percent_line_is_exact_around_many_balances(self):
        for bal in (100.0, 1234.56, 10000.0, 12345.67, 99999.99, 250000.0, 0.01 * 100):
            limit = bal / 50.0
            for res, blocked in ((-(limit - 0.01), False), (-limit, True), (-(limit + 0.01), True), (0.0, False), (limit, False)):
                o = dl.check(fx.BASE['utc'], 20260715, bal, res, 1, 0, 0, 3, True)
                self.assertEqual(dl.R_LOSS in o.reasons, blocked, (bal, res))

    def test_zero_or_positive_result_never_a_daily_loss_for_any_balance(self):
        balances = [5e-324, 1e-320, 1e-310, 1e-307, 3e-308, 2.2250738585072014e-308, 1e-300, 1e-200, 1e-100, 1e-30, 1e-15, 1e-9, 1e-3, 0.01, 0.5, 1.0,
                    49.0, 50.0, 51.0, 100.0, 12345.67, 1e6, 1e15, 1e100, 1e300, 1.7e308]
        for bal in balances:
            for res in (0.0, 1e-300, 1e-30, 0.5, 1.0, 1e6, 1e300):
                o = dl.check(fx.BASE['utc'], 20260715, bal, res, 0, 0, 0, 2, True)
                self.assertNotIn(dl.R_LOSS, o.reasons, (bal, res))
                self.assertFalse(o.cancel_pending_due, (bal, res))
        rnd = random.Random(1234)
        for _ in range(20000):
            bal = 10 ** rnd.uniform(-320, 308)
            res = rnd.choice([0.0, 10 ** rnd.uniform(-320, 300)])
            o = dl.check(fx.BASE['utc'], 20260715, bal, res, 0, 0, 0, 2, True)
            self.assertNotIn(dl.R_LOSS, o.reasons, (bal, res))

    def test_underflowing_threshold_is_refused_not_turned_into_a_limit(self):
        for bal in (5e-324, 1e-320, 1e-310, 1e-307, 3e-308, 2.2250738585072014e-308):
            o = dl.check(fx.BASE['utc'], 20260715, bal, -1.0, 0, 0, 0, 2, True)
            self.assertEqual(o.reasons, ['INVALID_SNAPSHOT:balance_start'], bal)
            self.assertFalse(o.cancel_pending_due or o.daily_limit_reached)
        o = dl.check(fx.BASE['utc'], 20260715, 1.2e-306, 0.0, 0, 0, 0, 2, True)
        self.assertTrue(o.entry_allowed)

    def test_tolerance_is_smaller_than_the_threshold_and_equality_still_blocks(self):
        for bal in (1e-15, 0.01, 1.0, 1234.56, 10000.0, 12345.67, 1e9, 1e300):
            threshold = bal / dl.LOSS_FRACTION_DIVISOR
            self.assertLess(4 * dl.DBL_EPSILON * threshold, threshold)
            self.assertIn(dl.R_LOSS, dl.check(fx.BASE['utc'], 20260715, bal, -threshold, 1, 0, 0, 3, True).reasons, bal)
            self.assertIn(dl.R_LOSS, dl.check(fx.BASE['utc'], 20260715, bal, -(threshold * (1 - 1e-16)), 1, 0, 0, 3, True).reasons, bal)   # 1 ulp of noise
            self.assertNotIn(dl.R_LOSS, dl.check(fx.BASE['utc'], 20260715, bal, -(threshold * (1 - 1e-9)), 1, 0, 0, 3, True).reasons, bal)   # a real shortfall

    def test_no_cancel_flag_without_a_proven_limit(self):
        for r in fx.ROWS:
            o = dl.check(r['utc'], r['snap'], r['bal'], r['res'], r['trades'], r['wins'], r['loss'], r['mtr'], bool(r['mset']))
            limit = any(x in (dl.R_WIN, dl.R_STREAK, dl.R_LOSS, dl.R_TRADES) for x in o.reasons)
            self.assertEqual(o.cancel_pending_due, limit, r['name'])
            self.assertEqual(o.daily_limit_reached, limit, r['name'])
            if o.reasons == [dl.R_UNSET] or any(x.startswith(('INVALID', 'STALE', 'UNSUPPORTED', 'INCONSISTENT')) for x in o.reasons):
                self.assertFalse(o.cancel_pending_due or o.daily_limit_reached, r['name'])

    def test_unknown_and_wrong_types_are_invalid_and_never_a_limit(self):
        good = dict(utc=fx.BASE['utc'], snapshot_day=20260715, balance_start=10000.0, closed_result=0.0, trades_today=0, wins_today=0,
                    consecutive_losses=0, max_trades=3, max_trades_set=True)
        nan, inf = float('nan'), float('inf')
        cases = [('utc', None, 'INVALID_UTC'), ('utc', 1.5, 'INVALID_UTC'), ('utc', True, 'INVALID_UTC'), ('snapshot_day', None, 'INVALID_SNAPSHOT:snapshot_day'),
                 ('snapshot_day', 20260715.0, 'INVALID_SNAPSHOT:snapshot_day'), ('balance_start', None, 'INVALID_SNAPSHOT:balance_start'),
                 ('balance_start', nan, 'INVALID_SNAPSHOT:balance_start'), ('balance_start', inf, 'INVALID_SNAPSHOT:balance_start'),
                 ('balance_start', '100', 'INVALID_SNAPSHOT:balance_start'), ('balance_start', True, 'INVALID_SNAPSHOT:balance_start'),
                 ('closed_result', None, 'INVALID_SNAPSHOT:closed_result'), ('closed_result', nan, 'INVALID_SNAPSHOT:closed_result'),
                 ('closed_result', -inf, 'INVALID_SNAPSHOT:closed_result'), ('trades_today', None, 'INVALID_SNAPSHOT:trades_today'),
                 ('trades_today', 1.0, 'INVALID_SNAPSHOT:trades_today'), ('trades_today', True, 'INVALID_SNAPSHOT:trades_today'),
                 ('wins_today', '1', 'INVALID_SNAPSHOT:wins_today'), ('consecutive_losses', 2.0, 'INVALID_SNAPSHOT:consecutive_losses'),
                 ('max_trades', None, 'INVALID_SNAPSHOT:max_trades_per_day'), ('max_trades', 3.0, 'INVALID_SNAPSHOT:max_trades_per_day'),
                 ('max_trades_set', 1, 'INVALID_SNAPSHOT:max_trades_per_day'), ('max_trades_set', None, 'INVALID_SNAPSHOT:max_trades_per_day')]
        for key, bad, tag in cases:
            kw = dict(good, **{key: bad})
            o = dl.check(**kw)
            self.assertFalse(o.entry_allowed, (key, bad))
            self.assertEqual(o.primary, tag, (key, bad, o.reasons))
            self.assertFalse(o.cancel_pending_due or o.daily_limit_reached, (key, bad))

    def test_fuzz_invariants(self):
        rnd = random.Random(20261016)
        for _ in range(5000):
            utc = rnd.choice([fx.BASE['utc'], fx.BASE['utc'] + 86400, 0, -5, fx.BASE['utc'] + 3600])
            snap = rnd.choice([20260715, 20260715, 20260715, 20260716, 20260714, 0])
            bal = rnd.choice([10000.0, 10000.0, 500.0, 0.0, -3.0, float('nan')])
            res = rnd.choice([0.0, -50.0, -200.0, -400.0, 120.0, float('nan'), -float('inf')])
            tr = rnd.choice([0, 1, 2, 3, 4, -1])
            w = rnd.choice([0, 0, 1, 2, -1])
            ls = rnd.choice([0, 1, 2, 3, -1])
            mset = rnd.random() < 0.8
            mtr = rnd.choice([1, 2, 3, 0, -2])
            o = dl.check(utc, snap, bal, res, tr, w, ls, mtr, mset)
            self.assertEqual(o.entry_allowed, not o.reasons)
            self.assertEqual(o.primary, o.reasons[0] if o.reasons else '')
            self.assertEqual(o.reasons, sorted(o.reasons, key=CANONICAL.index))
            self.assertEqual(len(set(o.reasons)), len(o.reasons))
            invalid = any(x.startswith(('INVALID', 'STALE', 'UNSUPPORTED', 'INCONSISTENT')) for x in o.reasons)
            if invalid:
                self.assertTrue(all(x.startswith(('INVALID', 'STALE', 'UNSUPPORTED', 'INCONSISTENT')) for x in o.reasons))
                self.assertFalse(o.cancel_pending_due or o.daily_limit_reached)
            self.assertEqual(o, dl.check(utc, snap, bal, res, tr, w, ls, mtr, mset))

    def test_t009_is_reused_for_the_day_and_dst_is_not_copied(self):
        src = _read('tests', 't012_daily_reference.py')
        self.assertIn('t009.evaluate(', src)
        for word in ('timedelta', 'zoneinfo', 'last Sunday', '_offset'):
            self.assertNotIn(word, src.split('"""', 2)[2])
        hdr = _read('src', 'include', 'DailyLimits.mqh')
        self.assertIn('SP_Evaluate(', hdr)
        self.assertIn('#include "SessionPolicy.mqh"', hdr)
        for word in ('SP_Edge', 'SP_Offset', 'StructToTime', 'TimeToStruct', 'TimeCurrent', 'TimeGMT', 'TimeLocal', 'AccountInfo', 'Position', 'OrderSend', 'File'):
            self.assertNotIn(word, hdr)


class Mutants(unittest.TestCase):
    def _build(self, pairs):
        src = _read('tests', 't012_daily_reference.py')
        for old, new in pairs:
            self.assertIn(old, src, 'mutation target absent (vacuous): ' + old[:50])
            src = src.replace(old, new, 1)
        ns = {'__name__': 't012_mutant'}
        exec(compile(src, 't012_mutant', 'exec'), ns)

        class M:
            pass
        m = M()
        for k, v in ns.items():
            setattr(m, k, v)
        return m

    def test_mutants_are_caught(self):
        cases = [
            ('win stop needs 2 wins', "WIN_STOP_AT = 1", "WIN_STOP_AT = 2"),
            ('streak stop needs 3', "CONSECUTIVE_LOSS_STOP_AT = 2", "CONSECUTIVE_LOSS_STOP_AT = 3"),
            ('loss limit is 3 percent', "LOSS_FRACTION_DIVISOR = 50.0", "LOSS_FRACTION_DIVISOR = 33.0"),
            ('tolerance absolute instead of relative', "4 * DBL_EPSILON * threshold:", "4 * DBL_EPSILON * max(1.0, threshold):"),
            ('underflowing threshold accepted', " or balance_start / LOSS_FRACTION_DIVISOR < DBL_MIN", ""),
            ('loss limit exclusive', "if closed_result < 0 and closed_result <= -threshold + 4 * DBL_EPSILON * threshold:", "if closed_result < -threshold:"),
            ('loss compared on the wrong sign', "if closed_result < 0 and closed_result <= -threshold + 4", "if closed_result < 0 and closed_result >= threshold + 4"),
            ('trade limit exclusive', "trades_today >= max_trades", "trades_today > max_trades"),
            ('trade limit ignored when set', "if max_trades_set and trades_today >= max_trades:", "if False:"),
            ('missing policy allowed', "    if not max_trades_set:\n        reasons.append(R_UNSET)", "    if False:\n        reasons.append(R_UNSET)"),
            ('stale day accepted', "    elif day and snapshot_day != day:", "    elif False:"),
            ('invalid input still judges limits', "    if bad:\n        return Result(False, bad[0], bad, False, False, day)", "    if bad and False:\n        return Result(False, bad[0], bad, False, False, day)"),
            ('cancel flag for a missing policy', "    return Result(not reasons, reasons[0] if reasons else '', reasons, bool(limits), bool(limits), day)", "    return Result(not reasons, reasons[0] if reasons else '', reasons, bool(reasons), bool(reasons), day)"),
            ('cancel flag set on errors', "return Result(False, bad[0], bad, False, False, day)", "return Result(False, bad[0], bad, True, True, day)"),
            ('wins may exceed trades', "    if t_ok and w_ok and wins_today > trades_today:", "    if False:"),
            ('streak may exceed trades', "    if t_ok and l_ok and consecutive_losses > trades_today:", "    if False:"),
            ('wins plus streak unchecked', "wins_today + consecutive_losses > trades_today:", "wins_today + consecutive_losses > trades_today + 99:"),
            ('negative counter accepted', "0 <= x <= MAX_COUNT", "x <= MAX_COUNT"),
            ('balance zero accepted', " or balance_start <= 0 or balance_start / LOSS_FRACTION_DIVISOR < DBL_MIN:", ":"),
            ('reasons in another order', "    reasons = list(limits)\n    if not max_trades_set:\n        reasons.append(R_UNSET)", "    reasons = list(reversed(limits))\n    if not max_trades_set:\n        reasons.append(R_UNSET)"),
            ('bool accepted as a count', "return isinstance(x, int) and not isinstance(x, bool) and 0 <= x <= MAX_COUNT", "return isinstance(x, int) and 0 <= x <= MAX_COUNT"),
        ]
        for name, old, new in cases:
            with self.subTest(name):
                m = self._build([(old, new)])
                try:
                    bad = run_rows(m)
                    if not bad:                   # Python-only inputs (a bool is not a count) are not rows of the shared table
                        o = m.check(fx.BASE['utc'], 20260715, 10000.0, 0.0, True, 0, 0, 3, True)
                        if o.primary != 'INVALID_SNAPSHOT:trades_today':
                            bad = ['bool accepted']
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T012_DailyLimitsTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
