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


def assert_nothing_reported(tc, res):
    tc.assertFalse(res.computed)
    for f in ('e_ticks', 's_ticks', 't_ticks', 'e_out', 's_out', 'r_ticks', 'r_geom', 'two_r_ticks', 'level_2r',
              'tp_ticks', 'tp', 'partial_price', 'min_distance'):
        tc.assertEqual(getattr(res, f), 0, f)
    tc.assertFalse(res.tp_equals_2r)
    tc.assertEqual(res.pending_check, 'NOT_CHECKED')


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
                if c['why']:
                    self.assertTrue(res.reason.startswith(c['why']), res.reason)
                    self.assert_nothing_reported(res)

    def assert_nothing_reported(self, res):
        assert_nothing_reported(self, res)

    def test_table_covers_buy_and_sell_and_all_statuses(self):
        self.assertGreaterEqual(len(CASES), 40)
        self.assertEqual({c['status'] for c in CASES},
                         {'OK', 'INVALID_DIRECTION', 'INVALID_INPUT', 'SL_WRONG_SIDE', 'ZERO_RISK',
                          'TARGET_WRONG_SIDE', 'BELOW_STOPS_LEVEL', 'PENDING_TOO_CLOSE'})
        for d in ('BUY', 'SELL'):
            cs = {c['exp'][5] for c in CASES if c['d'] == d and c['exp']}
            self.assertEqual(cs, {'NONE', 'NEARER_THAN_2R', 'EQUAL_TO_2R', 'FARTHER_THAN_2R'}, d)


def sym_run(d, e, s, tick, digits, point=0.01, stops=0, t=None, **kw):
    return g.compute(d, e, s, tick, digits, point, stops, t, **kw)


class ValidationTests(unittest.TestCase):
    assert_nothing_reported = assert_nothing_reported
    """Codex defects at 5c3af40: incompatible tick/digits, non-positive results, overflow."""

    def test_codex_case_incompatible_tick_digits(self):
        res = sym_run('BUY', 1.004, 1.003, 0.001, 2)
        self.assertEqual(res.status, 'INVALID_INPUT')
        self.assertTrue(res.reason.startswith('INCOMPATIBLE_TICK_DIGITS'))

    def test_codex_case_negative_2r(self):
        res = sym_run('SELL', 100.0, 160.0, 0.01, 2)
        self.assertEqual(res.status, 'INVALID_INPUT')
        self.assertTrue(res.reason.startswith('NONPOSITIVE_PRICE'))
        self.assertIn('level_2R', res.reason)

    def test_codex_case_sl_rounds_to_zero(self):
        res = sym_run('BUY', 0.6, 0.4, 1.0, 0, 1.0)
        self.assertEqual(res.status, 'INVALID_INPUT')
        self.assertTrue(res.reason.startswith('NONPOSITIVE_PRICE'))

    def test_tick_digits_compatibility_matrix(self):
        ok = [(0.01, 2), (0.05, 2), (0.25, 2), (1.0, 0), (0.5, 1), (0.1, 1), (0.1, 2), (10.0, 0), (0.00001, 5)]
        bad = [(0.001, 2), (0.015, 2), (0.5, 0), (0.05, 1), (0.25, 1), (0.001, 0), (1e308, 2), (1e-9, 8)]
        for tick, digits in ok:
            res = sym_run('BUY', 2000.0, 1000.0, tick, digits)
            self.assertEqual(res.status, 'OK', (tick, digits, res.reason))
        for tick, digits in bad:
            res = sym_run('BUY', 2000.0, 1000.0, tick, digits)
            self.assertEqual(res.status, 'INVALID_INPUT', (tick, digits))
            self.assertTrue(res.reason.startswith('INCOMPATIBLE_TICK_DIGITS'), (tick, digits, res.reason))
        # point is independent of digits (not related by the contract)
        self.assertEqual(sym_run('BUY', 2000.0, 1995.0, 0.01, 2, 0.5).status, 'OK')

    def test_nothing_reported_on_every_new_failure(self):
        for args in [('BUY', 1.004, 1.003, 0.001, 2), ('SELL', 100.0, 160.0, 0.01, 2), ('BUY', 0.6, 0.4, 1.0, 0, 1.0),
                     ('SELL', 5.0, 7.0, 1.0, 0, 1.0, 0, 0.4), ('BUY', 1e300, 1e299, 0.01, 2),
                     ('BUY', 1.5e308, 1.0e308, 1e308, 0, 1.0)]:
            with self.subTest(args):
                self.assert_nothing_reported(sym_run(*args))

    def test_failure_order(self):
        # tick/digits compatibility comes before price positivity and range
        r = sym_run('BUY', -1.0, 1e300, 0.001, 2)
        self.assertTrue(r.reason.startswith('INCOMPATIBLE_TICK_DIGITS'))
        # positivity of E_out/S_out comes before ZERO_RISK and SL_WRONG_SIDE
        self.assertTrue(sym_run('BUY', 0.4, 0.3, 1.0, 0, 1.0).reason.startswith('NONPOSITIVE_PRICE'))   # both 0
        self.assertTrue(sym_run('BUY', 0.6, 0.7, 1.0, 0, 1.0).status == 'ZERO_RISK')                    # 1 and 1
        self.assertEqual(sym_run('SELL', 0.4, 0.2, 1.0, 0, 1.0).status, 'INVALID_INPUT')
        # SL on the wrong side still wins over a later non-positive level
        self.assertEqual(sym_run('SELL', 100.0, 90.0, 0.01, 2).status, 'SL_WRONG_SIDE')
        # non-positive level comes before TARGET_WRONG_SIDE / BELOW_STOPS_LEVEL
        r = sym_run('SELL', 100.0, 160.0, 0.01, 2, 0.01, 10**6, 150.0)
        self.assertTrue(r.reason.startswith('NONPOSITIVE_PRICE'))

    def test_buy_mirror_of_nonpositive_is_fine(self):
        res = sym_run('BUY', 160.0, 100.0, 0.01, 2)    # BUY 2R is above entry: valid
        self.assertEqual((res.status, res.level_2r), ('OK', 280.0))

    def test_nonpositive_target_and_tp_guard(self):
        r = sym_run('SELL', 5.0, 7.0, 1.0, 0, 1.0, 0, 0.4)
        self.assertTrue(r.reason.startswith('NONPOSITIVE_PRICE') and 'target' in r.reason)
        self.assertEqual(sym_run('SELL', 5.0, 7.0, 1.0, 0, 1.0, 0, 1.2).tp, 1.0)    # T 1.2 -> 1 tick, still > 0

    def test_overflow_and_non_finite(self):
        inf, nan = float('inf'), float('nan')
        # (direction, E, S, tick, digits, point, stops, T)
        for args in [('BUY', inf, 1995.0, 0.01, 2, 0.01, 0, None), ('SELL', 2000.0, nan, 0.01, 2, 0.01, 0, None),
                     ('BUY', 2000.0, 1995.0, 0.01, 2, 0.01, 0, inf), ('BUY', 1e300, 1e299, 0.01, 2, 0.01, 0, None),
                     ('BUY', 2000.0, 1995.0, 0.01, 2, 0.01, 0, 1e300),
                     ('BUY', 1.5e308, 1.0e308, 1e308, 0, 1.0, 0, None),     # E_out = 2e308 overflows
                     ('BUY', 2000.0, 1995.0, 1e-300, 8, 0.01, 0, None)]:   # tick incompatible / too many ticks
            with self.subTest(args):
                res = g.compute(*args)
                self.assertEqual(res.status, 'INVALID_INPUT')
                self.assertTrue(res.reason.split(':')[0] in ('NUMERIC_OVERFLOW', 'INCOMPATIBLE_TICK_DIGITS') or
                                'non-finite' in res.reason, res.reason)
                self.assert_nothing_reported(res)
        # 2R/R_geom overflow (finite E_out, S_out but 2*R exceeds the double range)
        res = g.compute('BUY', 1.0e308, 5.0e307, 1e307, 0, 1.0, 0)
        self.assertEqual(res.status, 'INVALID_INPUT')
        self.assertTrue(res.reason.startswith('NUMERIC_OVERFLOW'), res.reason)
        self.assert_nothing_reported(res)
        # range limit exactly at 1e12 ticks is accepted, one tick more is not
        self.assertEqual(sym_run('BUY', 1.0e10, 9.0e9, 0.01, 2).status, 'OK')
        r = sym_run('BUY', 1.0e10 + 0.02, 9.0e9, 0.01, 2)
        self.assertTrue(r.reason.startswith('NUMERIC_OVERFLOW'))
        r = sym_run('BUY', 2000.0, 1995.0, 0.01, 2, 0.01, 0, None, bid=1999.0, ask=1e300)
        self.assertTrue(r.reason.startswith('NUMERIC_OVERFLOW'))
        self.assertLess(g.MAX_TICKS * 4, 2 ** 53)    # every derived tick count stays exact

    def test_on_grid_prices_are_never_changed_by_normalization(self):
        rnd = random.Random(55)
        n_checked = 0
        for tick, digits in [(0.01, 2), (0.05, 2), (0.25, 2), (0.5, 1), (1.0, 0), (0.1, 1), (0.00001, 5), (1e-8, 8)]:
            for _ in range(20000):
                n = rnd.randint(1, 10 ** rnd.randint(1, 11))
                if n * tick > 1e9:
                    continue
                p = g.ticks_to_price(n, tick, digits)
                self.assertEqual(p, round(n * tick, digits))
                self.assertLessEqual(abs(p - n * tick), 1e-3 * tick, (n, tick, digits))
                self.assertEqual(g.nearest_ticks(p, tick), n)
                n_checked += 1
        self.assertGreater(n_checked, 100000)

    def test_valid_cases_unchanged_by_the_new_guards(self):
        old = [c for c in CASES if not c['why']]
        self.assertGreaterEqual(len(old), 49)
        for c in old:
            self.assertEqual(run(c).status, c['status'], c['name'])


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


def load_mutated_reference(*pairs):
    with open(os.path.join(ROOT, 'tests', 't005_geometry_reference.py'), encoding='ascii') as fh:
        src = fh.read()
    for old, new in pairs:
        assert src.count(old) == 1, old
        src = src.replace(old, new)
    mod = type(sys)('t005_mutant')
    exec(compile(src, 't005_mutant', 'exec'), mod.__dict__)
    return mod


class GuardMutationTests(unittest.TestCase):
    """Removing any one new guard must make the validation cases fail (status or reason tag)."""
    # Guards overlap on purpose (defence in depth), so each mutant removes every check of one kind together.
    F = 'if False:'
    GUARDS = [
        ('tick/digits compatibility', [('if not math.isfinite(q) or qr < 1 or abs(q - qr) > EPS_TICKS:', F)]),
        ('E_out/S_out positivity', [('if e_out <= 0 or s_out <= 0:', F)]),
        ('level/target/TP positivity', [('if level_2r <= 0:', F), ('if t_price <= 0:', F),
                                        ('if tp <= 0 or level_2r <= 0:', F)]),
        ('range limit', [('abs(bid or 0.0), abs(ask or 0.0)) / tick_size > MAX_TICKS:',
                          'abs(bid or 0.0), abs(ask or 0.0)) / tick_size > 1e300:')]),
        ('finite results', [('if not (math.isfinite(e_out) and math.isfinite(s_out)):', F),
                            ('if not (math.isfinite(r_geom) and math.isfinite(level_2r)):', F),
                            ('if not math.isfinite(t_price):', F), ('if not math.isfinite(tp):', F),
                            ('if not (math.isfinite(sl_points) and math.isfinite(tp_points)):', F),
                            ('if not math.isfinite(gap):', F)]),
    ]

    def failing(self, mod):
        bad = []
        for c in CASES:
            if not c['why']:
                continue
            sym, q = c['sym'], c['quote']
            try:
                res = mod.compute(c['d'], c['e'], c['s'], sym[0], sym[1], sym[2], sym[3], c['t'], *(q if q else (None, None)))
                good = res.status == 'INVALID_INPUT' and res.reason.startswith(c['why'])
            except Exception:
                good = False
            if not good:
                bad.append(c['name'])
        return bad

    def test_unmutated_reference_passes_all_guard_cases(self):
        self.assertEqual(self.failing(g), [])

    def test_each_removed_guard_is_detected(self):
        for name, pairs in self.GUARDS:
            with self.subTest(name):
                self.assertTrue(self.failing(load_mutated_reference(*pairs)), name + ' guard removal escaped')

    def test_codex_cases_detect_the_specific_guards(self):
        by = {n: self.failing(load_mutated_reference(*p)) for n, p in self.GUARDS}
        self.assertIn('BUY_TICK_DIGITS_MISMATCH', by['tick/digits compatibility'])
        self.assertIn('SELL_2R_NEGATIVE', by['level/target/TP positivity'])
        self.assertIn('BUY_SL_ROUNDS_TO_ZERO', by['E_out/S_out positivity'])
        self.assertIn('BUY_RANGE_AT_LIMIT_PLUS', by['range limit'])
        self.assertIn('BUY_2R_OVERFLOW_TO_INF', by['finite results'])


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
