"""Unit tests for the T006 pure position-sizing reference. Run: python3 -m unittest test_t006_sizing (from tests/).
Expected values come from tests/t006_sizing_fixtures.py (hand-computed, not by the code formula). These tests prove the
CONTRACT of a side-effect-free LINEAR-MODEL sizing helper only; they say nothing about the real broker loss, the base of
the 1%, costs, or entry quality. The geometry fed to the sizer comes from the real T005 reference."""
import math
import os
import random
import re
import sys
import unittest
from fractions import Fraction

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t005_geometry_reference as g5  # noqa: E402
import t006_sizing_reference as p  # noqa: E402
from t006_sizing_fixtures import CASES, emit_mql  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAN, INF = float('nan'), float('inf')


def geo_of(g):
    d, e, s, sym = g
    return g5.compute(d, e, s, sym[0], sym[1], 0.01, 0)


def geo_ticks(e, s, status='OK', computed=True):
    """A geometry result built directly (the sizer reads only status, computed, e_ticks, s_ticks)."""
    return g5.Result(status=status, reason='', direction='BUY', e_raw=0.0, s_raw=0.0, t_raw=None, computed=computed,
                     e_ticks=e, s_ticks=s)


def run(c, sizer=None):
    return (sizer or p.size)(geo_of(c['geo']), *c['p'])


def same(a, b):
    return abs(a - b) <= 1e-9 * max(1.0, abs(b))


def assert_nothing_reported(tc, res):
    tc.assertFalse(res.computed)
    for f in ('stop_ticks', 'loss_per_lot', 'risk_per_step', 'volume_raw', 'steps_rounded', 'min_steps', 'max_steps',
              'cap_steps', 'volume_out', 'risk_realized', 'volume_rounding_loss', 'risk_unused'):
        tc.assertEqual(getattr(res, f), 0, f)
    tc.assertFalse(res.step_rounded)


def table_failures(sizer):
    """Names of the table rows for which `sizer` differs from the hand-computed expectation."""
    bad = []
    for c in CASES:
        res = run(c, sizer)
        ok = res.status == c['status']
        if ok and c['why']:
            ok = res.reason.startswith(c['why'])
        if ok and c['exp'] is not None:
            stop, loss, steps, vol, risk = c['exp']
            ok = (res.stop_ticks == stop and same(res.loss_per_lot, loss) and res.steps_rounded == steps and
                  same(res.volume_out, vol) and same(res.risk_realized, risk))
        if not ok:
            bad.append(c['name'])
    return bad


class TableTests(unittest.TestCase):
    def test_every_hand_computed_case(self):
        for c in CASES:
            with self.subTest(c['name']):
                res = run(c)
                self.assertEqual(res.status, c['status'], res.reason)
                if c['status'] != 'OK':
                    self.assertTrue(res.reason)
                if c['why']:
                    self.assertTrue(res.reason.startswith(c['why']), res.reason)
                if c['exp'] is None:
                    assert_nothing_reported(self, res)
                    continue
                stop, loss, steps, vol, risk = c['exp']
                self.assertTrue(res.computed)
                self.assertEqual(res.stop_ticks, stop)
                self.assertTrue(same(res.loss_per_lot, loss), (res.loss_per_lot, loss))
                self.assertEqual(res.steps_rounded, steps)
                self.assertTrue(same(res.volume_out, vol), (res.volume_out, vol))
                self.assertTrue(same(res.risk_realized, risk), (res.risk_realized, risk))
                if c['status'] != 'OK':      # a skip keeps diagnostics only, never a volume to act on
                    self.assertEqual((res.volume_out, res.risk_realized, res.step_rounded, res.volume_rounding_loss,
                                      res.risk_unused), (0.0, 0.0, False, 0.0, 0.0))

    def test_table_covers_every_status_and_both_directions(self):
        self.assertGreaterEqual(len(CASES), 55)
        self.assertEqual({c['status'] for c in CASES},
                         {'OK', 'INVALID_INPUT', 'GEOMETRY_NOT_OK', 'SKIP_BELOW_MIN_VOLUME', 'SKIP_ABOVE_MAX_VOLUME',
                          'SKIP_ABOVE_CAP'})
        for d in ('BUY', 'SELL'):
            self.assertGreaterEqual(len([c for c in CASES if c['geo'][0] == d and c['exp']]), 8, d)
        steps = {c['p'][3] for c in CASES}
        self.assertTrue({0.01, 0.1, 0.05, 1.0, 0.001, 0.5} <= steps)
        tags = {c['why'] for c in CASES if c['why']}
        self.assertTrue({'INVALID_RISK_BUDGET', 'INVALID_TICK_VALUE', 'INVALID_VOLUME_MIN', 'INVALID_VOLUME_STEP',
                         'INVALID_VOLUME_MAX', 'INVALID_CAP', 'VOLUME_MAX_BELOW_MIN', 'STEP_RANGE',
                         'VOLUME_NOT_ON_GRID', 'NUMERIC_OVERFLOW', 'GEOMETRY_NOT_OK'} <= tags)

    def test_buy_and_sell_rows_with_equal_stop_ticks_agree(self):
        by = {c['name']: c for c in CASES}
        pairs = [('BUY_STEP_001', 'SELL_STEP_001'), ('BUY_STEP_01', 'SELL_STEP_01'), ('BUY_STEP_0001', 'SELL_STEP_0001'),
                 ('BUY_TICK005_TV5', 'SELL_TICK005_TV5'), ('BUY_BELOW_MIN', 'SELL_BELOW_MIN'),
                 ('BUY_ABOVE_MAX', 'SELL_ABOVE_MAX'), ('BUY_ABOVE_CAP', 'SELL_ABOVE_CAP')]
        for b, s in pairs:
            rb, rs = run(by[b]), run(by[s])
            self.assertEqual((rb.status, rb.stop_ticks, rb.steps_rounded, rb.volume_out, rb.risk_realized),
                             (rs.status, rs.stop_ticks, rs.steps_rounded, rs.volume_out, rs.risk_realized), (b, s))


class GeometryInterfaceTests(unittest.TestCase):
    def test_stop_ticks_come_from_the_reported_geometry_ticks(self):
        # T005 normalization moves S: raw prices give 1994.93 -> 1994.95; reported ticks 40000 / 39899 = 101 ticks
        res_geo = g5.compute('BUY', 2000.02, 1994.93, 0.05, 2, 0.01, 0)
        self.assertEqual((res_geo.e_ticks, res_geo.s_ticks, res_geo.r_ticks), (40000, 39899, 101))
        r = p.size(res_geo, 505.0, 5.0, 0.01, 0.01, 100.0, 10.0)
        self.assertEqual((r.status, r.stop_ticks, r.loss_per_lot, r.steps_rounded), ('OK', 101, 505.0, 100))   # 505/505 = 1.00 lot

    def test_raw_prices_and_other_geometry_fields_are_ignored(self):
        g = g5.Result(status='OK', reason='', direction='SELL', e_raw=1.0, s_raw=2.0, t_raw=3.0, computed=True,
                      e_ticks=195040, s_ticks=194415, r_ticks=7, r_geom=99.0, tp=1.0)
        self.assertEqual(p.size(g, 1234.56, 1.0, 0.01, 0.01, 100.0, 10.0).stop_ticks, 625)

    def test_buy_sell_mirror_from_real_t005_results(self):
        rnd = random.Random(606)
        for _ in range(500):
            d = rnd.randint(1, 5000)
            tick, digits = rnd.choice([(0.01, 2), (0.05, 2), (0.5, 1), (1.0, 0)])
            base = rnd.randint(1000, 4000) + 2 * math.ceil(d * tick) + 100
            buy = g5.compute('BUY', base + d * tick, base, tick, digits, 0.01, 0)
            sell = g5.compute('SELL', base, base + d * tick, tick, digits, 0.01, 0)
            self.assertEqual((buy.status, sell.status, buy.r_ticks, sell.r_ticks), ('OK', 'OK', d, d))
            args = (rnd.uniform(1, 5000), rnd.uniform(0.05, 5), 0.01, 0.01, 1000.0, 1000.0)
            self.assertEqual(p.size(buy, *args), p.size(sell, *args))

    def test_every_geometry_failure_is_geometry_not_ok_and_nothing_is_recomputed(self):
        bad = [g5.compute('BUY', 1950.4, 1950.4, 0.01, 2, 0.01, 0),                       # ZERO_RISK
               g5.compute('BUY', 1950.4, 1955.0, 0.01, 2, 0.01, 0),                       # SL_WRONG_SIDE
               g5.compute('HOLD', 1950.4, 1944.15, 0.01, 2, 0.01, 0),                     # INVALID_DIRECTION
               g5.compute('BUY', 1950.4, 1944.15, 0.001, 2, 0.01, 0),                     # INVALID_INPUT
               g5.compute('BUY', 1950.4, 1944.15, 0.01, 2, 0.01, 10 ** 6),                # BELOW_STOPS_LEVEL
               g5.compute('BUY', 1950.4, 1944.15, 0.01, 2, 0.01, 0, 1950.4),              # TARGET_WRONG_SIDE
               g5.compute('BUY', 1950.4, 1944.15, 0.01, 2, 0.01, 0, None, 1950.0, 1950.2)]   # PENDING_TOO_CLOSE
        self.assertEqual([b.status for b in bad], ['ZERO_RISK', 'SL_WRONG_SIDE', 'INVALID_DIRECTION', 'INVALID_INPUT',
                                                   'BELOW_STOPS_LEVEL', 'TARGET_WRONG_SIDE', 'PENDING_TOO_CLOSE'])
        for b in bad:
            with self.subTest(b.status):
                r = p.size(b, 1000.0, 1.0, 0.01, 0.01, 100.0, 10.0)
                self.assertEqual(r.status, 'GEOMETRY_NOT_OK')
                self.assertTrue(r.reason.startswith('GEOMETRY_NOT_OK'))
                assert_nothing_reported(self, r)

    def test_geometry_shaped_defects(self):
        a = (1000.0, 1.0, 0.01, 0.01, 100.0, 10.0)
        self.assertEqual(p.size(geo_ticks(195040, 195040), *a).reason.split(':')[0], 'INVALID_STOP_TICKS')    # zero distance
        self.assertEqual(p.size(geo_ticks(195040, 194415, computed=False), *a).status, 'GEOMETRY_NOT_OK')
        self.assertEqual(p.size(geo_ticks(195040, 194415, status='OK', computed=False), *a).status, 'GEOMETRY_NOT_OK')
        self.assertEqual(p.size(geo_ticks(10 ** 14, 1), *a).reason.split(':')[0], 'INVALID_STOP_TICKS')
        self.assertEqual(p.size(geo_ticks(1.5, 1), *a).reason.split(':')[0], 'INVALID_STOP_TICKS')
        self.assertEqual(p.size(geo_ticks(True, 0), *a).reason.split(':')[0], 'INVALID_STOP_TICKS')
        for junk in (None, 5, 'OK', object()):
            self.assertEqual(p.size(junk, *a).status, 'GEOMETRY_NOT_OK')
        # |E - S| is used, so a reversed order of the two tick counts gives the same stop distance
        self.assertEqual(p.size(geo_ticks(194415, 195040), *a), p.size(geo_ticks(195040, 194415), *a))
        for r in (p.size(geo_ticks(195040, 195040), *a), p.size(geo_ticks(1, 1, computed=False), *a)):
            assert_nothing_reported(self, r)


class ValidationTests(unittest.TestCase):
    A = dict(risk_budget=1000.0, tick_value=1.0, volume_min=0.01, volume_step=0.01, volume_max=100.0, cap_lots=10.0)
    GEO = geo_ticks(195040, 194415)

    def go(self, **kw):
        a = dict(self.A, **kw)
        return p.size(self.GEO, a['risk_budget'], a['tick_value'], a['volume_min'], a['volume_step'], a['volume_max'],
                      a['cap_lots'])

    def test_each_parameter_rejects_non_finite_non_positive_and_non_numeric(self):
        tags = {'risk_budget': 'INVALID_RISK_BUDGET', 'tick_value': 'INVALID_TICK_VALUE', 'volume_min': 'INVALID_VOLUME_MIN',
                'volume_step': 'INVALID_VOLUME_STEP', 'volume_max': 'INVALID_VOLUME_MAX', 'cap_lots': 'INVALID_CAP'}
        for name, tag in tags.items():
            for bad in (0.0, -1.0, NAN, INF, -INF, None, 'x', True):
                with self.subTest((name, bad)):
                    r = self.go(**{name: bad})
                    self.assertEqual(r.status, 'INVALID_INPUT')
                    self.assertTrue(r.reason.startswith(tag), r.reason)
                    assert_nothing_reported(self, r)

    def test_first_failure_wins_order(self):
        bad = dict(risk_budget=0.0, tick_value=0.0, volume_min=0.0, volume_step=0.0, volume_max=0.0, cap_lots=0.0)
        seq = ['risk_budget', 'tick_value', 'volume_min', 'volume_step', 'volume_max', 'cap_lots']
        tags = ['INVALID_RISK_BUDGET', 'INVALID_TICK_VALUE', 'INVALID_VOLUME_MIN', 'INVALID_VOLUME_STEP',
                'INVALID_VOLUME_MAX', 'INVALID_CAP']
        for i in range(6):
            kw = {k: bad[k] for k in seq[i:]}
            self.assertTrue(self.go(**kw).reason.startswith(tags[i]), tags[i])
        # tag order: positivity < MAX_BELOW_MIN < STEP_RANGE < NOT_ON_GRID < NUMERIC_OVERFLOW
        r = self.go(volume_min=5.0, volume_max=1e-3 * 5e9, volume_step=1e-3)       # max/step 5e12 and ... max >= min
        self.assertTrue(r.reason.startswith('STEP_RANGE'))
        r = self.go(volume_min=0.015, volume_max=0.01)
        self.assertTrue(r.reason.startswith('VOLUME_MAX_BELOW_MIN'), r.reason)
        r = self.go(volume_min=0.015, volume_max=1e9)                                # range before grid
        self.assertTrue(r.reason.startswith('STEP_RANGE'), r.reason)
        r = self.go(volume_min=0.015, volume_max=5.005)                              # min grid before max grid
        self.assertTrue(r.reason.startswith('VOLUME_NOT_ON_GRID: volume_min'), r.reason)
        r = self.go(volume_max=5.005)
        self.assertTrue(r.reason.startswith('VOLUME_NOT_ON_GRID: volume_max'), r.reason)
        r = self.go(volume_min=0.015, risk_budget=1e300)                             # grid before overflow
        self.assertTrue(r.reason.startswith('VOLUME_NOT_ON_GRID'))
        r = p.size(geo_ticks(5, 5), -1.0, 1.0, 0.01, 0.01, 100.0, 10.0)             # stop ticks before the budget
        self.assertTrue(r.reason.startswith('INVALID_STOP_TICKS'))
        r = p.size(geo_ticks(5, 5, status='ZERO_RISK'), -1.0, 1.0, 0.01, 0.01, 100.0, 10.0)   # geometry first
        self.assertEqual(r.status, 'GEOMETRY_NOT_OK')

    def test_step_is_never_assumed_to_be_001(self):
        for step in (0.01, 0.1, 0.05, 1.0, 0.001, 0.5, 0.25, 0.02):
            r = self.go(volume_min=step, volume_step=step, volume_max=100.0, cap_lots=100.0, risk_budget=1234.56)
            self.assertEqual(r.status, 'OK', step)
            self.assertEqual(r.steps_rounded, int(math.floor(1234.56 / 625.0 / step + 1e-9)), step)
            self.assertLessEqual(r.volume_out, 1234.56 / 625.0 + 1e-12)
            self.assertAlmostEqual(r.volume_out, r.steps_rounded * step, places=12)
        # 0.01 as a volume that is not on the grid of a 0.05 step
        self.assertTrue(self.go(volume_min=0.01, volume_step=0.05).reason.startswith('VOLUME_NOT_ON_GRID'))

    def test_grid_tolerance_boundaries(self):
        self.assertEqual(self.go(volume_min=0.3, volume_step=0.1, volume_max=5.0, cap_lots=5.0).status, 'OK')
        self.assertEqual(self.go(volume_min=0.30000000000000004, volume_step=0.1, volume_max=5.0, cap_lots=5.0).status, 'OK')
        self.assertEqual(self.go(volume_min=0.1 * (1 + 9e-7), volume_step=0.1, volume_max=5.0).status, 'OK')       # 9e-7 step
        self.assertTrue(self.go(volume_min=0.1 * (1 + 2e-6), volume_step=0.1, volume_max=5.0).reason.startswith('VOLUME_NOT_ON_GRID'))
        self.assertTrue(self.go(volume_min=0.14, volume_step=0.1, volume_max=5.0).reason.startswith('VOLUME_NOT_ON_GRID'))
        self.assertEqual(self.go(volume_min=1.6, volume_max=1.6, cap_lots=10.0).status, 'OK')                      # min == max
        self.assertTrue(self.go(volume_min=1.01, volume_max=1.0).reason.startswith('VOLUME_MAX_BELOW_MIN'))

    def test_step_range_boundaries(self):
        r = self.go(volume_min=1e-3, volume_step=1e-3, volume_max=9e5, cap_lots=1.0, risk_budget=1e9)    # 9e8 steps
        self.assertNotEqual(r.reason[:10], 'STEP_RANGE')
        r = self.go(volume_min=1e-3, volume_step=1e-3, volume_max=1.1e6, cap_lots=1.0)                    # 1.1e9 steps
        self.assertTrue(r.reason.startswith('STEP_RANGE'))
        self.assertTrue(self.go(cap_lots=1e7 + 1).reason.startswith('STEP_RANGE'))                        # cap alone: > 1e9 steps
        self.assertNotEqual(self.go(cap_lots=9e6).reason[:10], 'STEP_RANGE')
        self.assertTrue(self.go(volume_step=1e-300, volume_min=1e-300, volume_max=1.0).reason.startswith('STEP_RANGE'))
        self.assertTrue(self.go(volume_step=1e-320, volume_min=1e-320, volume_max=1e308).reason.startswith('STEP_RANGE'))

    def test_numeric_overflow_tags(self):
        for kw in (dict(risk_budget=1e300), dict(risk_budget=1e100, tick_value=1e-300), dict(tick_value=1e308),
                   dict(risk_budget=1e16 * 6.25 * 1.0001)):
            r = self.go(**kw)
            self.assertEqual((r.status, r.reason.split(':')[0]), ('INVALID_INPUT', 'NUMERIC_OVERFLOW'), kw)
            assert_nothing_reported(self, r)
        r = p.size(geo_ticks(1, 10 ** 13), 1e200, 1e300, 0.01, 0.01, 100.0, 10.0)                              # loss per lot overflows
        self.assertEqual(r.reason.split(':')[0], 'NUMERIC_OVERFLOW')
        # exactly at 1e15 raw steps is not an overflow (it is far above the broker maximum -> skip)
        r = self.go(risk_budget=6.25e15)
        self.assertEqual(r.status, 'SKIP_ABOVE_MAX_VOLUME')

    def test_every_invalid_result_reports_nothing(self):
        for c in CASES:
            if c['status'] in ('INVALID_INPUT', 'GEOMETRY_NOT_OK'):
                with self.subTest(c['name']):
                    assert_nothing_reported(self, run(c))


class RoundingTests(unittest.TestCase):
    GEO = geo_ticks(195040, 194415)

    def test_eps_bump_restores_float_noise_on_an_exact_fit(self):
        # 10 ticks, step .001, budget .29 = 29 steps; .29/.01 style division gives 28.999999999999996
        g = geo_ticks(100010, 100000)
        rps = 0.001 * (10.0 * 1.0)
        self.assertLess(math.floor(0.29 / rps), 29)          # the plain floor would lose a step
        r = p.size(g, 0.29, 1.0, 0.001, 0.001, 100.0, 10.0)
        self.assertEqual((r.status, r.steps_rounded), ('OK', 29))
        self.assertFalse(r.step_rounded)

    def test_guard_loop_removes_a_step_when_the_tolerance_overshoots(self):
        # 3 - 5e-7 steps: within the 1e-6 tolerance, but 3 steps would cost 187.5 > budget 187.49996875
        r = p.size(self.GEO, 187.49996875, 1.0, 0.1, 0.1, 100.0, 10.0)
        self.assertEqual((r.status, r.steps_rounded), ('OK', 2))
        self.assertLessEqual(r.risk_realized, 187.49996875)
        r = p.size(self.GEO, 187.5, 1.0, 0.1, 0.1, 100.0, 10.0)
        self.assertEqual(r.steps_rounded, 3)

    def test_documented_conservative_ulp_tie(self):
        # 47 ticks, step .1: 249.1 fits 53 steps exactly in decimal (249.1/4.7 = 53.0) but 53 * (0.1*47.0) = 249.10000000000002
        # in binary, so the NEVER-EXCEED rule gives 52 steps (one step lost, never one gained). Reviewable convention.
        g = geo_ticks(195047, 195000)
        r = p.size(g, 249.1, 1.0, 0.1, 0.1, 100.0, 10.0)
        self.assertEqual(r.steps_rounded, 52)
        self.assertGreater(53 * (0.1 * 47.0), 249.1)
        self.assertLessEqual(r.risk_realized, 249.1)

    def test_step_rounding_report(self):
        r = p.size(self.GEO, 1234.56, 1.0, 0.01, 0.01, 100.0, 10.0)      # raw 1.975296 -> 1.97
        self.assertTrue(r.step_rounded)
        self.assertAlmostEqual(r.volume_raw, 1.975296, places=12)
        self.assertAlmostEqual(r.volume_rounding_loss, 0.005296, places=9)
        self.assertAlmostEqual(r.risk_unused, 1234.56 - 1231.25, places=9)
        self.assertEqual(r.volume_out, 197 * 0.01)
        r = p.size(self.GEO, 187.5, 1.0, 0.1, 0.1, 100.0, 10.0)           # exact fit
        self.assertFalse(r.step_rounded)
        self.assertEqual((r.volume_rounding_loss, r.risk_unused), (0.0, 0.0))
        self.assertTrue(hasattr(r, 'volume_rounding_loss') and not hasattr(r, 'reduced_to_limit'))

    def random_case(self, rnd):
        stop = rnd.choice([1, 2, 3, 7, 47, 101, 152, 625, 3000, rnd.randint(1, 100000)])
        step = rnd.choice([0.01, 0.1, 0.05, 1.0, 0.001, 0.5, 0.02, 0.25])
        tv = rnd.choice([1.0, 0.8, 5.0, 0.1, round(rnd.uniform(0.01, 12), 4), rnd.uniform(0.01, 12)])
        budget = rnd.choice([round(rnd.uniform(0.5, 5000), 2), rnd.uniform(0.001, 50000), float(rnd.randint(1, 3000))])
        return geo_ticks(500000 + stop, 500000), budget, tv, step

    def test_property_sweep_risk_never_exceeds_budget_and_never_rounds_up(self):
        rnd = random.Random(20261014)
        ok = skips = 0
        for _ in range(20000):
            g, budget, tv, step = self.random_case(rnd)
            r = p.size(g, budget, tv, step, step, 1e5 * step, 1e5 * step)
            if r.status != 'OK':
                self.assertTrue(r.status.startswith('SKIP') or r.reason.startswith('NUMERIC_OVERFLOW'), (budget, tv, step, r))
                self.assertEqual((r.volume_out, r.risk_realized), (0.0, 0.0))
                skips += 1
                continue
            ok += 1
            stop = r.stop_ticks
            self.assertLessEqual(r.risk_realized, budget)                                  # the defined double expression
            self.assertEqual(r.risk_realized, r.steps_rounded * r.risk_per_step)
            self.assertEqual(r.volume_out, r.steps_rounded * step)
            self.assertLessEqual(r.volume_out, r.volume_raw + 1e-6 * step + 1e-12)            # never rounded up (beyond float noise)
            self.assertGreaterEqual(r.volume_out, r.volume_raw - step - 1e-12)                # at most one step lost
            self.assertGreater((r.steps_rounded + 1) * r.risk_per_step, budget)               # maximal under the same expression
            exact = Fraction(r.steps_rounded) * Fraction(step) * stop * Fraction(tv)           # exact real arithmetic of the inputs
            self.assertLessEqual((exact - Fraction(budget)) / Fraction(budget), Fraction(1, 10 ** 14))   # only float rounding
            self.assertLessEqual(abs(r.volume_out * r.loss_per_lot - r.risk_realized), 4e-15 * budget + 1e-300)
            self.assertGreaterEqual(r.risk_unused, 0.0)
        self.assertGreater(ok, 10000)
        self.assertGreater(skips, 100)

    def test_on_step_sweep_loses_at_most_one_step_and_never_gains_one(self):
        rnd = random.Random(7)
        demoted = total = 0
        for _ in range(20000):
            stop = rnd.randint(1, 3000)
            step = rnd.choice([0.01, 0.1, 0.05, 1.0, 0.001, 0.5])
            n0 = rnd.randint(2, 2000)
            budget = round(n0 * step * stop, 6)                    # decimal-exact fit by construction (tick value 1)
            r = p.size(geo_ticks(500000 + stop, 500000), budget, 1.0, step, step, 1e5 * step, 1e5 * step)
            self.assertEqual(r.status, 'OK')
            self.assertIn(r.steps_rounded, (n0, n0 - 1), (stop, step, n0, budget))
            demoted += r.steps_rounded != n0
            total += 1
        self.assertLess(demoted / total, 0.35)       # conservative ulp ties are a minority (about 19% of contrived exact fits; reported, not hidden)

    def test_float_sensitive_hand_cases(self):
        g = self.GEO
        for budget, step, n in ((187.5, 0.1, 3), (43.75, 0.01, 7), (181.25, 0.01, 29), (1000.0, 0.01, 160),
                                (62.5, 0.1, 1), (6.25, 0.01, 1), (31.25, 0.05, 1)):
            r = p.size(g, budget, 1.0, step, step, 100.0, 100.0)
            self.assertEqual((r.status, r.steps_rounded), ('OK', n), (budget, step))


class LimitTests(unittest.TestCase):
    GEO = geo_ticks(195040, 194415)

    def go(self, budget=1234.56, vmin=0.01, vmax=100.0, cap=10.0, step=0.01):
        return p.size(self.GEO, budget, 1.0, vmin, step, vmax, cap)

    def test_never_raised_to_the_minimum(self):
        r = self.go(budget=50.0, vmin=0.10)         # raw .08 lots
        self.assertEqual((r.status, r.volume_out, r.risk_realized), ('SKIP_BELOW_MIN_VOLUME', 0.0, 0.0))
        r = self.go(budget=5.0)                       # rounds to zero
        self.assertEqual((r.status, r.steps_rounded), ('SKIP_BELOW_MIN_VOLUME', 0))
        r = self.go(budget=0.0001)
        self.assertEqual((r.status, r.steps_rounded, r.volume_out), ('SKIP_BELOW_MIN_VOLUME', 0, 0.0))

    def test_never_clamped_to_max_or_cap(self):
        for kw, st in ((dict(vmax=1.5), 'SKIP_ABOVE_MAX_VOLUME'), (dict(cap=1.5), 'SKIP_ABOVE_CAP'),
                       (dict(vmax=1.5, cap=1.0), 'SKIP_ABOVE_MAX_VOLUME')):
            r = self.go(**kw)
            self.assertEqual((r.status, r.volume_out, r.risk_realized, r.steps_rounded), (st, 0.0, 0.0, 197), kw)

    def test_boundaries_one_step_either_side(self):
        # 197 steps are available; max/cap/min set one step below, at, above
        self.assertEqual(self.go(vmax=1.96).status, 'SKIP_ABOVE_MAX_VOLUME')
        self.assertEqual(self.go(vmax=1.97).status, 'OK')
        self.assertEqual(self.go(vmax=1.98).status, 'OK')
        self.assertEqual(self.go(cap=1.96).status, 'SKIP_ABOVE_CAP')
        self.assertEqual(self.go(cap=1.97).status, 'OK')
        self.assertEqual(self.go(cap=1.98).status, 'OK')
        self.assertEqual(self.go(vmin=1.97).status, 'OK')
        self.assertEqual(self.go(vmin=1.98).status, 'SKIP_BELOW_MIN_VOLUME')

    def test_cap_off_grid_is_compared_after_flooring_never_used_as_a_volume(self):
        self.assertEqual(self.go(cap=1.975).status, 'OK')           # floor(197.5) = 197
        self.assertEqual(self.go(cap=1.969).status, 'SKIP_ABOVE_CAP')   # floor(196.9) = 196
        r = self.go(cap=1.975)
        self.assertEqual(r.cap_steps, 197)
        self.assertEqual(r.volume_out, 197 * 0.01)                  # not the cap
        # float-sensitive cap: 0.3 / 0.1 = 2.9999999999999996 must still allow 3 steps
        r = p.size(self.GEO, 187.5, 1.0, 0.1, 0.1, 100.0, 0.3)
        self.assertEqual((r.status, r.cap_steps), ('OK', 3))
        r = p.size(self.GEO, 187.5, 1.0, 0.1, 0.1, 100.0, 0.29)
        self.assertEqual((r.status, r.cap_steps), ('SKIP_ABOVE_CAP', 2))

    def test_cap_and_max_are_checked_separately_max_first(self):
        self.assertEqual(self.go(vmax=100.0, cap=1.5).status, 'SKIP_ABOVE_CAP')          # cap smaller than max
        self.assertEqual(self.go(vmax=1.5, cap=10.0).status, 'SKIP_ABOVE_MAX_VOLUME')    # cap greater than max
        self.assertEqual(self.go(vmax=1.5, cap=1.0).status, 'SKIP_ABOVE_MAX_VOLUME')     # both exceeded: max first
        self.assertEqual(self.go(vmax=3.0, cap=10.0, vmin=3.0).status, 'SKIP_BELOW_MIN_VOLUME')   # min before max/cap
        self.assertEqual(self.go(vmin=0.10, cap=0.05).status, 'SKIP_ABOVE_CAP')          # cap below min is valid input

    def test_client_cap_ten_is_passed_not_defaulted(self):
        r = self.go(budget=10000.0, cap=10.0)       # raw 16 lots
        self.assertEqual((r.status, r.steps_rounded), ('SKIP_ABOVE_CAP', 1600))
        r = self.go(budget=6250.0, cap=10.0)        # exactly 10.00 lots
        self.assertEqual((r.status, r.steps_rounded, r.volume_out), ('OK', 1000, 10.0))
        self.assertEqual(self.go(budget=10000.0, cap=20.0).status, 'OK')
        sig = p.size.__code__.co_varnames[:p.size.__code__.co_argcount]
        self.assertEqual(sig, ('geo', 'risk_budget', 'tick_value', 'volume_min', 'volume_step', 'volume_max', 'cap_lots'))
        self.assertIsNone(p.size.__defaults__)


class RuleTests(unittest.TestCase):
    def test_determinism_and_no_mutation_of_inputs(self):
        g = geo_ticks(195040, 194415)
        args = [1234.56, 0.8, 0.01, 0.01, 100.0, 10.0]
        before = (g, list(args))
        a, b = p.size(g, *args), p.size(g, *args)
        self.assertEqual(a, b)
        self.assertEqual((g, args), before)
        with self.assertRaises(Exception):
            a.volume_out = 5.0            # result is immutable
        with self.assertRaises(Exception):
            g.e_ticks = 1                 # geometry is immutable

    def test_labels_and_scope_statements(self):
        r = p.size(geo_ticks(195040, 194415), 1000.0, 1.0, 0.01, 0.01, 100.0, 10.0)
        self.assertEqual(r.costs_label, 'COSTS_NOT_MODELLED')
        self.assertTrue(r.model_label.startswith('LINEAR_MODEL'))
        self.assertIn('NO_REDUCTION_TO_LIMIT', p.NO_REDUCTION_LABEL)
        doc = p.__doc__
        for text in ('LINEAR MODEL', 'NOT a guarantee', 'COSTS_NOT_MODELLED', 'does NOT choose the base of the 1%',
                     'NEVER raised to volume_min', 'There is no\n  reduced_to_limit field', 'first failure wins',
                     'combined 2% risk', '80/20 partial volume rounding'):
            self.assertIn(text, doc)

    def test_linear_model_only(self):
        # loss per lot = stop ticks * tick value; volume = budget / loss; nothing else enters
        for stop, tv, budget in ((625, 1.0, 1000.0), (101, 5.0, 505.0), (3, 0.3, 9.0)):
            r = p.size(geo_ticks(500000 + stop, 500000), budget, tv, 0.001, 0.001, 1e5, 1e5)
            self.assertEqual(r.loss_per_lot, stop * tv)
            self.assertAlmostEqual(r.volume_raw, budget / (stop * tv), places=12)


def load_mutant(old, new, count=1):
    with open(os.path.join(ROOT, 'tests', 't006_sizing_reference.py'), encoding='ascii') as fh:
        src = fh.read()
    assert src.count(old) == count, (old, src.count(old))
    ns = {'__name__': 't006_mutant'}
    exec(compile(src.replace(old, new), 't006_mutant', 'exec'), ns)
    return ns['size']


ROUND = ("    n = int(math.floor(raw_steps + EPS_STEPS))\n    while n > 0 and n * risk_per_step > risk_budget:\n"
         "        n -= 1\n")
LIMITS = "    # LIMITS: a conflict is a skip, never a reduction\n"
CAPLINE = "    cap_steps = int(math.floor(cap_x + EPS_STEPS))\n"
MUTANTS = {
    'round UP instead of down': (ROUND, "    n = int(math.ceil(raw_steps))\n"),
    'no never-exceed guard loop': (ROUND, "    n = int(math.floor(raw_steps + EPS_STEPS))\n"),
    'no float tolerance in floor': (ROUND, "    n = int(math.floor(raw_steps))\n    while n > 0 and n * risk_per_step > risk_budget:\n        n -= 1\n"),
    'clamp to max and cap instead of skip': (LIMITS, LIMITS + "    n = max(min(n, max_steps, cap_steps), 0)\n    diag['steps_rounded'] = n\n"),
    'raise to minimum instead of skip': (LIMITS, LIMITS + "    n = max(n, min_steps)\n    diag['steps_rounded'] = n\n"),
    'ignore tick_value': ("    loss_per_lot = float(stop_ticks) * tick_value\n", "    loss_per_lot = float(stop_ticks)\n"),
    'assume volume_step 0.01': (CAPLINE, CAPLINE + "    volume_step = 0.01\n"),
    'min boundary exclusive': ("    if n < min_steps:\n", "    if n <= min_steps:\n"),
    'max boundary exclusive': ("    if n > max_steps:\n", "    if n >= max_steps:\n"),
    'cap boundary exclusive': ("    if n > cap_steps:\n", "    if n >= cap_steps:\n"),
    'no volume_max < volume_min guard': ("    if volume_max < volume_min:\n", "    if False:\n"),
    'no grid check for volume_min': ("    if min_steps < 0:\n", "    if False:\n"),
    'no grid check for volume_max': ("    if max_steps < 0:\n", "    if False:\n"),
    'no step range guard': ("or max_x > MAX_STEPS or cap_x > MAX_STEPS:", "or False:"),
    'cap floored without tolerance': (CAPLINE, "    cap_steps = int(math.floor(cap_x))\n"),
}


class MutationTests(unittest.TestCase):
    def test_unmutated_reference_passes_the_table(self):
        self.assertEqual(table_failures(None), [])

    def test_each_defect_is_caught_by_the_hand_table_or_the_property(self):
        for name, (old, new) in MUTANTS.items():
            with self.subTest(name):
                sizer = load_mutant(old, new)
                failing = table_failures(sizer)
                caught = bool(failing)
                if not caught:        # fall back to the property: risk <= budget and the volume never above the raw volume
                    rnd = random.Random(5)
                    for _ in range(4000):
                        g, budget, tv, step = RoundingTests().random_case(rnd)
                        r = sizer(g, budget, tv, step, step, 1e5 * step, 1e5 * step)
                        if r.status == 'OK' and (r.risk_realized > budget or r.volume_out > r.volume_raw + 1e-6 * step + 1e-12):
                            caught = True
                            break
                self.assertTrue(caught, name)

    def test_round_up_and_missing_guard_are_caught_by_the_property_sweep_too(self):
        for name in ('round UP instead of down', 'no never-exceed guard loop'):
            sizer = load_mutant(*MUTANTS[name])
            rnd = random.Random(20261014)
            hit = 0
            for _ in range(3000):
                g, budget, tv, step = RoundingTests().random_case(rnd)
                r = sizer(g, budget, tv, step, step, 1e5 * step, 1e5 * step)
                if r.status == 'OK' and r.risk_realized > budget:
                    hit += 1
            self.assertGreater(hit, 0, name)

    def test_specific_hand_cases_catch_specific_defects(self):
        by = {c['name']: c for c in CASES}
        self.assertIn('BUY_STEP_001', table_failures(load_mutant(*MUTANTS['round UP instead of down'])))
        self.assertIn('BUY_ABOVE_MAX', table_failures(load_mutant(*MUTANTS['clamp to max and cap instead of skip'])))
        self.assertIn('BUY_ABOVE_CAP', table_failures(load_mutant(*MUTANTS['clamp to max and cap instead of skip'])))
        self.assertIn('BUY_BELOW_MIN', table_failures(load_mutant(*MUTANTS['raise to minimum instead of skip'])))
        self.assertIn('BUY_TICKVALUE_08', table_failures(load_mutant(*MUTANTS['ignore tick_value'])))
        self.assertIn('BUY_STEP_01', table_failures(load_mutant(*MUTANTS['assume volume_step 0.01'])))
        self.assertIn('BUY_EPS_BUMP_NEEDED', table_failures(load_mutant(*MUTANTS['no float tolerance in floor'])))
        self.assertTrue(by)


class SyncAndScopeTests(unittest.TestCase):
    def test_mql_fixture_block_equals_generated_text(self):
        with open(os.path.join(ROOT, 'src', 'tests', 'T006_SizingTest.mq5'), encoding='ascii') as fh:
            text = fh.read()
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', text, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), emit_mql())

    def test_reference_has_no_trading_clock_or_random_use(self):
        with open(os.path.join(ROOT, 'tests', 't006_sizing_reference.py'), encoding='ascii') as fh:
            src = fh.read()
        for word in ('time', 'datetime', 'random', 'OrderSend', 'os', 'sys'):
            self.assertIsNone(re.search(r'^\s*(import|from)\s+%s\b' % word, src, re.M), word)
        for hidden in ('0.01', '10.0', ' 10)'):
            code = re.sub(r'(?s)""".*?"""|#[^\n]*', '', src)
            self.assertNotIn(hidden, code, 'hidden default %s' % hidden)


if __name__ == '__main__':
    unittest.main()
