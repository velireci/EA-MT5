import math
import unittest
from t008_broker_loss import check, permit_risk, probe_tick_value
from t007_planning_reference import _risk_exceeded


class BrokerLossTests(unittest.TestCase):
    def test_matching_loss_both_directions(self):
        for loss in (100, 5.25):
            self.assertEqual(check(True, -loss, loss, loss, .01), 'OK')

    def test_failed_calculation(self):
        self.assertEqual(check(False, -100, 100, 100, .01), 'CALC_FAILED')

    def test_nonloss_and_invalid(self):
        for value in (0, 1):
            self.assertEqual(check(True, value, 100, 100, .01), 'NOT_A_LOSS')
        for value in (math.nan, math.inf, -math.inf):
            self.assertEqual(check(True, value, 100, 100, .01), 'INVALID_INPUT')
        for tolerance in (-.1, 1.1, math.nan):
            self.assertEqual(check(True, -100, 100, 100, tolerance), 'INVALID_INPUT')

    def test_budget_wins_over_discrepancy(self):
        self.assertEqual(check(True, -100.01, 100, 100, .1), 'BUDGET_EXCEEDED')
        self.assertEqual(check(True, -100, 100, 100, 0), 'OK')

    def test_discrepancy_boundary(self):
        self.assertEqual(check(True, -99, 100, 200, .01), 'OK')
        self.assertEqual(check(True, -98.99, 100, 200, .01), 'MODEL_MISMATCH')

    def test_extreme_valid_loss_does_not_overflow(self):
        self.assertEqual(check(True, -1e308, 1e308, 1e308, .01), 'OK')

    def test_combined_cap_uses_larger_estimate(self):
        self.assertEqual(check(True, -10.05, 10, 11, .01), 'OK')
        self.assertTrue(_risk_exceeded(90, permit_risk(-10.05, 10), 100))
        self.assertEqual(permit_risk(-9.95, 10), 10)
        self.assertFalse(_risk_exceeded(90, permit_risk(-10, 10), 100))

    def test_invalid_permit_risk(self):
        for p, model in [(math.nan, 1), (1, 1), (-1, 0)]:
            self.assertEqual(permit_risk(p, model), 0)

    def test_tick_estimate_from_broker_probe(self):
        self.assertAlmostEqual(probe_tick_value(True, -8.98, .01, 1000), .898)
        self.assertAlmostEqual(probe_tick_value(True, -89.79, .1, 1000), .8979)

    def test_failed_or_invalid_probe_never_falls_back(self):
        for args in [(False,-10,.01,1000),(True,1,.01,1000),(True,-10,0,1000),
                     (True,-10,.01,0),(True,math.nan,.01,1000)]:
            self.assertEqual(probe_tick_value(*args), 0)

if __name__ == '__main__':
    unittest.main()
