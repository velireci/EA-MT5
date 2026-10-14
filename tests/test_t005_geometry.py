"""Unit tests for the T005 pure trade-geometry reference. Run: python3 -m unittest tests.test_t005_geometry
(or from tests/). Expected values come from tests/t005_geometry_fixtures.py (hand-computed, not by the code formula).
These tests prove the CONTRACT of a side-effect-free geometry helper only; they say nothing about entry quality."""
import math
import os
import random
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t005_geometry_reference as g  # noqa: E402
from t005_geometry_fixtures import CASES, emit_mql  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(c):
    sym, q = c['sym'], c['quote']
    return g.compute(c['d'], c['e'], c['s'], sym[0], sym[1], sym[2], sym[3], c['t'], *(q if q else (None, None)))


def numbers(res):
    return (res.e_out, res.s_out, res.r_geom, res.level_2r, res.tp, res.target_case, res.tp_equals_2r)


def same(got, exp):
    return all(abs(a - b) < 1e-9 if isinstance(a, float) else a == b for a, b in zip(got, exp))


def numeric_failures(fn):
    """Names of the OK cases with expected numbers for which fn(case) -> tuple differs from the hand value."""
    return [c['name'] for c in CASES if c['exp'] is not None and not same(fn(c), c['exp'])]


class TableTests(unittest.TestCase):
    def test_every_hand_computed_case(self):
        for c in CASES:
            with self.subTest(c['name']):
                res = run(c)
                self.assertEqual(res.status, c['status'], res.reason)
                self.assertEqual(res.pending_check, c['pend'])
                if c['exp'] is not None:
                    self.assertTrue(same(numbers(res), c['exp']), (c['name'], numbers(res), c['exp']))
                if c['status'] != 'OK':
                    self.assertTrue(res.reason)

    def test_table_covers_buy_and_sell_and_all_statuses(self):
        self.assertGreaterEqual(len(CASES), 40)
        self.assertEqual({c['status'] for c in CASES},
                         {'OK', 'INVALID_DIRECTION', 'INVALID_INPUT', 'SL_WRONG_SIDE', 'ZERO_RISK',
                          'TARGET_WRONG_SIDE', 'BELOW_STOPS_LEVEL', 'PENDING_TOO_CLOSE'})
        for d in ('BUY', 'SELL'):
            cs = {c['exp'][5] for c in CASES if c['d'] == d and c['exp']}
            self.assertEqual(cs, {'NONE', 'NEARER_THAN_2R', 'EQUAL_TO_2R', 'FARTHER_THAN_2R'}, d)


class InvariantTests(unittest.TestCase):
    def check_ok(self, res, tick, digits):
        sign = 1 if res.direction == 'BUY' else -1
        self.assertEqual(res.status, 'OK')
        # R and 2R come from exactly the reported prices
        self.assertAlmostEqual(abs(res.e_out - res.s_out), res.r_geom, places=9)
        self.assertAlmostEqual(res.level_2r, res.e_out + sign * 2 * res.r_geom, places=9)
        self.assertEqual(res.r_ticks, abs(res.e_ticks - res.s_ticks))
        self.assertEqual(res.two_r_ticks, res.e_ticks + sign * 2 * res.r_ticks)
        for price in (res.e_out, res.s_out, res.r_geom, res.level_2r, res.tp, res.partial_price):
            self.assertAlmostEqual(price / tick, round(price / tick), places=6)
        self.assertEqual(res.partial_price, res.level_2r)
        self.assertGreater(sign * (res.tp - res.e_out), 0)
        self.assertGreaterEqual(sign * (res.tp - res.level_2r), -1e-9)   # TP never nearer than 2R
        self.assertEqual(res.tp_equals_2r, res.tp_ticks == res.two_r_ticks)
        self.assertEqual(res.partial_label, 'PARTIAL_AT_2R (client answer: 80% of initial volume)')
        self.assertEqual(res.costs_label, 'COSTS_NOT_MODELLED')
        self.assertEqual(sign * (res.s_out - res.e_out) < 0, True)

    def test_invariants_on_table(self):
        for c in CASES:
            res = run(c)
            if res.status == 'OK':
                with self.subTest(c['name']):
                    self.check_ok(res, c['sym'][0], c['sym'][1])

    def test_invariants_on_random_sweep(self):
        rnd = random.Random(20261014)
        n = 0
        for _ in range(4000):
            tick, digits = rnd.choice([(0.01, 2), (0.05, 2), (0.1, 1), (0.5, 1), (1.0, 0), (0.25, 2)])
            d = rnd.choice(['BUY', 'SELL'])
            e = round(rnd.uniform(1500, 3500), 4)
            dist = rnd.uniform(0.0, 30)
            s = e - dist if d == 'BUY' else e + dist
            t = None if rnd.random() < 0.3 else e + (1 if d == 'BUY' else -1) * rnd.uniform(-5, 80)
            res = g.compute(d, e, round(s, 4), tick, digits, 0.01, 0, None if t is None else round(t, 4))
            if res.status == 'OK':
                n += 1
                self.check_ok(res, tick, digits)
            else:
                self.assertIn(res.status, ('ZERO_RISK', 'TARGET_WRONG_SIDE'))
        self.assertGreater(n, 2000)

    def test_buy_sell_mirror_when_no_tie(self):
        """Reflecting every price about a grid-aligned constant maps BUY results onto SELL results."""
        rnd = random.Random(7)
        for _ in range(1500):
            tick, digits = rnd.choice([(0.01, 2), (0.05, 2), (0.5, 1)])
            c = 6000.0
            e = round(rnd.uniform(2000, 3000) + 0.0137, 4)
            s = e - rnd.uniform(0.2, 25) + 0.0071
            t = e + rnd.uniform(0.2, 90) + 0.0033
            xs = [e, s, t]
            if any(abs((x / tick) % 1 - 0.5) < 1e-3 for x in xs):   # skip near-ties (tie direction is not mirrored)
                continue
            a = g.compute('BUY', e, s, tick, digits, 0.01, 0, t)
            b = g.compute('SELL', c - e, c - s, tick, digits, 0.01, 0, c - t)
            self.assertEqual(a.status, b.status)
            if a.status != 'OK':
                continue
            self.assertAlmostEqual(c - a.e_out, b.e_out, places=6)
            self.assertAlmostEqual(c - a.s_out, b.s_out, places=6)
            self.assertAlmostEqual(a.r_geom, b.r_geom, places=6)
            self.assertAlmostEqual(c - a.level_2r, b.level_2r, places=6)
            self.assertAlmostEqual(c - a.tp, b.tp, places=6)
            self.assertEqual(a.target_case, b.target_case)


class RoundingTests(unittest.TestCase):
    def test_nearest_and_half_up(self):
        self.assertEqual(g.nearest_ticks(2000.02, 0.05), 40000)
        self.assertEqual(g.nearest_ticks(2000.03, 0.05), 40001)
        self.assertEqual(g.nearest_ticks(2000.025, 0.05), 40001)     # exact half goes up
        self.assertEqual(g.nearest_ticks(1999.975, 0.05), 40000)
        self.assertEqual(g.nearest_ticks(2310.15, 0.05), 46203)      # inexact in binary, still on the grid
        self.assertEqual(g.nearest_ticks(1507.5, 1.0), 1508)

    def test_target_rounds_away(self):
        self.assertEqual(g.away_ticks(2012.33, 0.05, 'BUY'), 40247)
        self.assertEqual(g.away_ticks(2012.33, 0.05, 'SELL'), 40246)
        self.assertEqual(g.away_ticks(2012.35, 0.05, 'BUY'), 40247)  # already on the grid: unchanged
        self.assertEqual(g.away_ticks(2012.35, 0.05, 'SELL'), 40247)

    def test_normalization_changes_e_and_r_follows_reported_prices(self):
        res = g.compute('BUY', 2000.02, 1994.93, 0.05, 2, 0.01, 0)
        self.assertEqual((res.e_out, res.s_out), (2000.00, 1994.95))
        self.assertNotAlmostEqual(res.e_out, res.e_raw, places=6)
        self.assertAlmostEqual(res.r_geom, 5.05)            # not the raw 5.09 or 5.07
        self.assertAlmostEqual(res.level_2r, 2010.10)       # not the raw-based 2010.20 / 2010.14

    def test_target_exactly_on_grid_beyond_2r_is_kept(self):
        res = g.compute('SELL', 2310.20, 2316.45, 0.01, 2, 0.01, 0, 2297.69)
        self.assertEqual(res.target_case, 'FARTHER_THAN_2R')
        self.assertAlmostEqual(res.tp, 2297.69)


class RuleTests(unittest.TestCase):
    def test_n6_target_never_shortened_never_skipped(self):
        far = g.compute('BUY', 2000.0, 1995.0, 0.01, 2, 0.01, 0, 2100.0)
        near = g.compute('BUY', 2000.0, 1995.0, 0.01, 2, 0.01, 0, 2003.0)
        self.assertEqual((far.status, far.tp), ('OK', 2100.0))
        self.assertEqual((near.status, near.tp), ('OK', 2010.0))

    def test_tp_equals_2r_flag_and_partial(self):
        res = g.compute('SELL', 2000.0, 2005.0, 0.01, 2, 0.01, 0)
        self.assertTrue(res.tp_equals_2r)
        self.assertEqual(res.partial_price, res.tp)

    def test_stops_level_boundary_float(self):
        ok = g.compute('BUY', 2000.0, 1999.70, 0.01, 2, 0.01, 30)
        no = g.compute('BUY', 2000.0, 1999.71, 0.01, 2, 0.01, 30)
        self.assertEqual((ok.status, no.status), ('OK', 'BELOW_STOPS_LEVEL'))
        self.assertAlmostEqual(ok.min_distance, 0.30)

    def test_non_finite_and_bad_types(self):
        nan, inf = float('nan'), float('inf')
        for args in [('BUY', nan, 1995.0), ('BUY', 2000.0, nan), ('SELL', inf, 2005.0), ('BUY', 2000.0, -inf),
                     ('BUY', '2000', 1995.0), ('BUY', True, 1995.0), ('BUY', None, 1995.0)]:
            with self.subTest(args):
                self.assertEqual(g.compute(*args, 0.01, 2, 0.01, 0).status, 'INVALID_INPUT')
        for kw in [dict(t_raw=nan), dict(t_raw=inf), dict(bid=nan, ask=2001.0), dict(bid=1999.0)]:
            with self.subTest(kw):
                self.assertEqual(g.compute('BUY', 2000.0, 1995.0, 0.01, 2, 0.01, 0, **kw).status, 'INVALID_INPUT')
        for tick in (nan, inf, 0.0, -0.01):
            self.assertEqual(g.compute('BUY', 2000.0, 1995.0, tick, 2, 0.01, 0).status, 'INVALID_INPUT')
        for digits in (-1, 9, 2.0, True):
            self.assertEqual(g.compute('BUY', 2000.0, 1995.0, 0.01, digits, 0.01, 0).status, 'INVALID_INPUT')
        self.assertEqual(g.compute('BUY', 2000.0, 1995.0, 0.01, 2, 0.01, 1.5).status, 'INVALID_INPUT')
        self.assertEqual(g.compute('BUY', 1e300, 1e299, 0.01, 2, 0.01, 0).status, 'INVALID_INPUT')
        for d in ('buy', '', None, 1, 'HOLD'):
            self.assertEqual(g.compute(d, 2000.0, 1995.0, 0.01, 2, 0.01, 0).status, 'INVALID_DIRECTION')

    def test_determinism_and_no_mutation(self):
        args = ('SELL', 2500.07, 2507.64, 0.05, 2, 0.01, 30, 2480.03, 2499.0, 2500.2)
        before = repr(args)
        a, b = g.compute(*args), g.compute(*args)
        self.assertEqual(a, b)
        self.assertEqual(repr(args), before)
        with self.assertRaises(Exception):
            a.tp = 1.0     # frozen result

    def test_unenforced_items_are_declared(self):
        self.assertIn('50 stop-distance', g.UNENFORCED)
        self.assertIn('NOT enforced', g.UNENFORCED)
        self.assertIn('not the client final R', g.R_LABEL)
        self.assertEqual(g.compute('BUY', 2000.0, 1999.0, 0.01, 2, 0.01, 0).status, 'OK')   # distance 1.0, no 50 limit
        self.assertEqual(g.compute('BUY', 2100.0, 2000.0, 0.01, 2, 0.01, 0).status, 'OK')   # 100 USD stop is not rejected


# ---- mutation-style checks -------------------------------------------------------------------------------
def mutant(c, kind):
    """Independent mini-implementations with ONE deliberate defect each; they must fail the hand table."""
    tick, digits, _point, _stops = c['sym']
    sign = 1 if c['d'] == 'BUY' else -1
    px = lambda n: round(n * tick, digits)
    nearest = g.nearest_ticks
    if kind == 'ties_down':
        def nearest(p, t):
            x = p / t
            return int(math.floor(x - 0.5 + 1e-6) + 1) if abs(x % 1 - 0.5) > 1e-6 else int(math.floor(x))
    e_t, s_t = nearest(c['e'], tick), nearest(c['s'], tick)
    e_out, s_out = px(e_t), px(s_t)
    r = abs(e_out - s_out)
    two_r = e_out + sign * 2 * r
    if kind == 'raw_sl_2r':            # R reported from normalized prices but 2R computed from the RAW stop
        two_r = e_out + sign * 2 * abs(e_out - c['s'])
    if kind == 'no_normalization':
        e_out, s_out = c['e'], c['s']
        r = abs(e_out - s_out)
        two_r = e_out + sign * 2 * r
    if kind == 'sell_sign_error':
        two_r = e_out + 2 * r
    two_r = round(two_r, digits + 2)
    tp, case = two_r, 'NONE'
    if c['t'] is not None:
        x = c['t'] / tick
        if kind == 'target_nearest':
            tn = px(g.nearest_ticks(c['t'], tick))
        elif kind == 'target_toward_entry':
            tn = px(g.away_ticks(c['t'], tick, 'SELL' if c['d'] == 'BUY' else 'BUY'))
        else:
            tn = px(g.away_ticks(c['t'], tick, c['d']))
        diff = round(sign * (tn - two_r), 6)
        case = 'FARTHER_THAN_2R' if diff > 0 else ('EQUAL_TO_2R' if diff == 0 else 'NEARER_THAN_2R')
        if diff > 0 and kind != 'tp_shortened_to_2r':
            tp = tn
    return (e_out, s_out, round(r, digits + 2), two_r, tp, case, abs(tp - two_r) < 1e-9)


class MutationTests(unittest.TestCase):
    def test_baseline_mutant_without_defect_passes(self):
        self.assertEqual(numeric_failures(lambda c: mutant(c, 'none')), [])

    def test_each_defect_is_caught_by_the_hand_table(self):
        for kind in ('raw_sl_2r', 'no_normalization', 'target_toward_entry', 'target_nearest',
                     'tp_shortened_to_2r', 'ties_down', 'sell_sign_error'):
            with self.subTest(kind):
                self.assertTrue(numeric_failures(lambda c: mutant(c, kind)), kind + ' escaped the table')

    def test_raw_sl_2r_is_caught_specifically_by_rounding_cases(self):
        failing = set(numeric_failures(lambda c: mutant(c, 'raw_sl_2r')))
        self.assertIn('BUY_ROUND_FAR', failing)
        self.assertIn('SELL_ROUND_FAR', failing)
        self.assertNotIn('BUY_FAR', failing)    # no rounding there: this defect is invisible without rounding cases


class SyncAndScopeTests(unittest.TestCase):
    def test_mql_fixture_block_equals_generated_text(self):
        with open(os.path.join(ROOT, 'src', 'tests', 'T005_GeometryTest.mq5'), encoding='ascii') as fh:
            text = fh.read()
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', text, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), emit_mql())

    def test_reference_has_no_trading_or_clock_use(self):
        with open(os.path.join(ROOT, 'tests', 't005_geometry_reference.py'), encoding='ascii') as fh:
            src = fh.read()
        for word in ('time', 'datetime', 'random', 'volume', 'lot', 'OrderSend'):
            self.assertIsNone(re.search(r'^\s*(import|from)\s+%s\b' % word, src, re.M), word)


if __name__ == '__main__':
    unittest.main()
