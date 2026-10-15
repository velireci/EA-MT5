"""T018 exposure-reader tests: ownership by magic on a hedging account only, pending policy explicit, risk from the broker calculation, unknown never becomes zero, the gate gets -1 for unknown."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import exposure_reference as ex  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MAGIC = 777
SCENARIOS = ['inputs_unset_block', 'account_not_separable', 'ownership_by_magic', 'pending_policy', 'risk_from_broker', 'risk_unknown_never_zero', 'lists_incomplete', 'list_changes_during_read', 'pending_risk_separate', 'gate_mapping']


def pos(ticket, magic=MAGIC, kind=0, vol=0.1, price=100.0, sl=99.0):
    return ex.Pos(ticket, 'XAUUSD', magic, kind, vol, price, sl)


def od(ticket, magic=MAGIC, kind=0, vol=0.1, price=100.0, sl=99.0):
    return ex.Ord(ticket, 'XAUUSD', magic, kind, vol, price, sl)


def run(port, policy=ex.PEND_COUNT, magic=MAGIC, symbol='XAUUSD', risk=ex.RISK_INCLUDE):
    return ex.compute(magic, symbol, policy, port, risk)


class Blocks(unittest.TestCase):
    def test_inputs_unset_block(self):
        for args in ({'magic': 0}, {'magic': -1}, {'symbol': ''}, {'policy': ex.PEND_UNSET}, {'policy': 9}, {'risk': 9}):
            port = ex.Port(positions=[pos(1)])
            r = run(port, args.get('policy', ex.PEND_COUNT), args.get('magic', MAGIC), args.get('symbol', 'XAUUSD'), args.get('risk', ex.RISK_INCLUDE))
            self.assertFalse(r.ok)
            self.assertEqual(r.reason, 'INPUT_UNSET')
            self.assertEqual((r.gate_positions(), r.gate_risk(), port.calls), (-1, -1.0, 0))

    def test_account_not_separable(self):
        for mode in (0, 1, 7):
            r = run(ex.Port(margin_mode=mode, positions=[pos(1)]))
            self.assertEqual((r.ok, r.reason, r.gate_positions()), (False, 'OWNERSHIP_NOT_SEPARABLE', -1))
        r = run(ex.Port(account_ok=False))
        self.assertEqual((r.ok, r.reason), (False, 'ACCOUNT_UNREADABLE'))

    def test_ownership_by_magic(self):
        port = ex.Port(positions=[pos(1), pos(2, magic=0), pos(3, magic=778), pos(4)], orders=[od(5, magic=0)])
        r = run(port)
        self.assertTrue(r.ok)
        self.assertEqual((r.open_positions, r.foreign_positions, r.foreign_pending, r.pending), (2, 2, 1, 0))
        self.assertEqual(port.calls, 2, 'foreign items are never evaluated')

    def test_pending_policy(self):
        port = ex.Port(positions=[pos(1)], orders=[od(2), od(3, kind=1, sl=101.0), od(4, magic=0)])
        r = run(port, ex.PEND_COUNT)
        self.assertEqual((r.open_positions, r.pending, r.foreign_pending), (3, 2, 1))
        port2 = ex.Port(positions=[pos(1)], orders=[od(2), od(3)])
        r2 = run(port2, ex.PEND_IGNORE)
        self.assertEqual((r2.ok, r2.open_positions, r2.pending, port2.reads_orders), (True, 1, 2, 1), 'IGNORE does not reserve a position but the orders are still read and known')
        port3 = ex.Port(positions=[pos(1)], orders=[od(2)], ord_complete=False)
        for policy in (ex.PEND_COUNT, ex.PEND_IGNORE):
            self.assertEqual(run(port3, policy).reason, 'ORDERS_INCOMPLETE', 'an unreadable order list is unknown whatever the counting policy')

    def test_risk_from_broker(self):
        # buy 0.1 @100 sl 99: loss 0.1*1*100 = 10; sell 0.2 @100 sl 101: loss 20; buy with a stop above the open (past break-even) = 0
        port = ex.Port(positions=[pos(1), pos(2, kind=1, vol=0.2, sl=101.0), pos(3, sl=100.5)])
        r = run(port)
        self.assertTrue(r.risk_known)
        self.assertAlmostEqual(r.existing_risk, 30.0)
        self.assertAlmostEqual(r.gate_risk(), 30.0)
        r2 = run(ex.Port(positions=[pos(1)], orders=[od(2, kind=1, vol=0.3, sl=101.0)]))
        self.assertAlmostEqual(r2.existing_risk, 40.0)
        r3 = run(ex.Port())
        self.assertEqual((r3.ok, r3.open_positions, r3.risk_known, r3.existing_risk), (True, 0, True, 0.0))

    def test_risk_unknown_never_zero(self):
        for label, port in (('no sl', ex.Port(positions=[pos(1, sl=0.0)])),
                            ('nan sl', ex.Port(positions=[pos(1, sl=float('nan'))])),
                            ('no volume', ex.Port(positions=[pos(1, vol=0.0)])),
                            ('calc fails', ex.Port(positions=[pos(1), pos(2)], calc_fail_ticket=2)),
                            ('order no sl', ex.Port(orders=[od(1, sl=0.0)]))):
            r = run(port)
            self.assertTrue(r.ok, label)
            self.assertFalse(r.risk_known, label)
            self.assertEqual((r.gate_risk(), r.existing_risk), (-1.0, -1.0), label)
            self.assertNotEqual(r.risk_reason, '', label)
        r = run(ex.Port(positions=[pos(1, sl=0.0)]), ex.PEND_IGNORE)
        self.assertEqual(r.open_positions, 1, 'the count stays known when only the risk is unknown')

    def test_lists_incomplete(self):
        r = run(ex.Port(pos_complete=False, positions=[pos(1)]))
        self.assertEqual((r.ok, r.reason, r.gate_positions(), r.gate_risk()), (False, 'POSITIONS_INCOMPLETE', -1, -1.0))
        r = run(ex.Port(positions=[pos(i) for i in range(1, 66)]))
        self.assertEqual(r.reason, 'POSITIONS_INCOMPLETE')
        r = run(ex.Port(positions=[pos(1, kind=5)]))
        self.assertEqual((r.ok, r.reason), (False, 'POSITION_TYPE_UNKNOWN'))
        r = run(ex.Port(orders=[od(1, kind=5)]))
        self.assertEqual((r.ok, r.reason), (False, 'ORDER_TYPE_UNKNOWN'))
        r = run(ex.Port(orders=[od(i) for i in range(1, 66)]))
        self.assertEqual(r.reason, 'ORDERS_INCOMPLETE')

    def test_list_changes_during_read(self):
        grow = lambda cur: cur + [pos(99)]
        r = run(ex.Port(positions=[pos(1)], change_positions=grow))
        self.assertEqual((r.ok, r.reason, r.gate_positions(), r.gate_risk()), (False, 'POSITIONS_CHANGED', -1, -1.0))
        r = run(ex.Port(positions=[pos(1)], change_positions=lambda cur: [pos(1, vol=0.2)]))
        self.assertEqual(r.reason, 'POSITIONS_CHANGED', 'a changed volume is a change')
        r = run(ex.Port(positions=[pos(1)], change_positions=lambda cur: [pos(1, magic=0)]))
        self.assertEqual(r.reason, 'POSITIONS_CHANGED', 'a magic that flips between reads is a change, not a manual position')
        r = run(ex.Port(orders=[od(1)], change_orders=lambda cur: cur + [od(2)]))
        self.assertEqual((r.ok, r.reason), (False, 'ORDERS_CHANGED'))
        r = run(ex.Port(positions=[pos(1)], orders=[od(2)], change_positions=lambda cur: list(cur), change_orders=lambda cur: list(cur)))
        self.assertTrue(r.ok, 'identical reads are stable')

    def test_pending_risk_separate(self):
        port = ex.Port(positions=[pos(1)], orders=[od(2, kind=1, vol=0.1, price=100.0, sl=101.0)])      # position risk 10, pending risk 10
        both = run(port, ex.PEND_COUNT, risk=ex.RISK_INCLUDE)
        self.assertAlmostEqual(both.existing_risk, 20.0)
        # IGNORE the reservation but INCLUDE the risk: the two decisions are independent
        ign_inc = run(port, ex.PEND_IGNORE, risk=ex.RISK_INCLUDE)
        self.assertEqual((ign_inc.open_positions, ign_inc.pending), (1, 1))
        self.assertAlmostEqual(ign_inc.existing_risk, 20.0, msg='IGNORE must not drop the risk of a pending order')
        # COUNT the reservation but EXCLUDE the risk
        cnt_exc = run(port, ex.PEND_COUNT, risk=ex.RISK_EXCLUDE)
        self.assertEqual(cnt_exc.open_positions, 2)
        self.assertAlmostEqual(cnt_exc.existing_risk, 10.0)
        # the risk policy UNSET: the risk is UNKNOWN as soon as an owned pending order exists, the count stays known
        for pol in (ex.PEND_COUNT, ex.PEND_IGNORE):
            unset = run(port, pol, risk=ex.RISK_UNSET)
            self.assertTrue(unset.ok)
            self.assertEqual((unset.risk_known, unset.gate_risk(), unset.open_positions), (False, -1.0, 2 if pol == ex.PEND_COUNT else 1))
            self.assertIn('PENDING_RISK_POLICY_UNSET', unset.risk_reason)
        # no owned pending order: nothing to decide, the risk is known
        none = run(ex.Port(positions=[pos(1)], orders=[od(2, magic=0)]), ex.PEND_IGNORE, risk=ex.RISK_UNSET)
        self.assertTrue(none.risk_known)
        self.assertAlmostEqual(none.existing_risk, 10.0)

    def test_gate_mapping(self):
        r = run(ex.Port(positions=[pos(1)], orders=[od(2)]))
        self.assertEqual((r.gate_positions(), r.pending), (2, 1))
        bad = ex.Result()
        self.assertEqual((bad.gate_positions(), bad.gate_risk()), (-1, -1.0))


class Sources(unittest.TestCase):
    def test_mql_scenarios_pinned(self):
        with open(os.path.join(ROOT, 'src', 'tests', 'ExposureReaderTest.mq5'), encoding='ascii') as f:
            t = f.read()
        calls = re.findall(r'^\s+Scenario_(\w+)\(\);', t, re.M)
        self.assertEqual(calls, SCENARIOS)
        for n in SCENARIOS:
            self.assertEqual(len(re.findall(r'void Scenario_%s\(void\)' % n, t)), 1, n)

    def test_python_mirror_and_header_agree_on_rules(self):
        with open(os.path.join(ROOT, 'src', 'include', 'ExposureReader.mqh'), encoding='ascii') as f:
            h = f.read()
        for token in ('INPUT_UNSET', 'ACCOUNT_UNREADABLE', 'OWNERSHIP_NOT_SEPARABLE', 'POSITIONS_INCOMPLETE', 'ORDERS_INCOMPLETE', 'POSITION_TYPE_UNKNOWN', 'ORDER_TYPE_UNKNOWN',
                      'MathMax(0.0,-profit)', 'mode!=EX_HEDGING', 'pos[i].magic!=magic'):
            self.assertIn(token, h)
        for w in ('OrderSend', 'OrderCheck', 'PositionClose', 'FileOpen', 'TimeCurrent', 'AccountInfo', 'PositionGet', 'OrderGet', 'SymbolInfo'):
            self.assertNotIn(w, re.sub(r'//[^\n]*', '', h), w)


class Mutants(unittest.TestCase):
    """each mutant of the reference must be caught by this very suite"""
    SRC = os.path.join(ROOT, 'tests', 'exposure_reference.py')

    def _run_mutant(self, old, new):
        with open(self.SRC, encoding='utf-8') as f:
            text = f.read()
        self.assertEqual(text.count(old), 1, old)
        mod = type(sys)('exposure_mutant')
        exec(compile(text.replace(old, new), 'mutant', 'exec'), mod.__dict__)
        global ex
        saved = ex
        ex = mod
        try:
            suite = unittest.TestSuite()
            for n in ('test_inputs_unset_block', 'test_account_not_separable', 'test_ownership_by_magic', 'test_pending_policy', 'test_risk_from_broker', 'test_risk_unknown_never_zero',
                      'test_lists_incomplete', 'test_list_changes_during_read', 'test_pending_risk_separate', 'test_gate_mapping'):
                suite.addTest(Blocks(n))
            res = unittest.TestResult()
            suite.run(res)
            return len(res.failures) + len(res.errors)
        finally:
            ex = saved

    def test_each_mutant_is_caught(self):
        muts = [("if port.margin_mode != HEDGING:", "if False:"),
                ("        if p.magic == magic:", "        if True:"),
                ("    r.open_positions = len(owned_pos) + (r.pending if pend_policy == PEND_COUNT else 0)", "    r.open_positions = len(owned_pos) + r.pending"),
                ("    risk_items = [('position', p) for p in owned_pos] + ([('order', o) for o in owned_ord] if risk_policy == RISK_INCLUDE else [])", "    risk_items = [('position', p) for p in owned_pos] + ([('order', o) for o in owned_ord] if pend_policy == PEND_COUNT else [])"),
                ("    if owned_ord and risk_policy == RISK_UNSET:", "    if False:"),
                ("    if not stable:\n        r.reason = 'POSITIONS_CHANGED'", "    if False:\n        r.reason = 'POSITIONS_CHANGED'"),
                ("    if not ostable:\n        r.reason = 'ORDERS_CHANGED'", "    if False:\n        r.reason = 'ORDERS_CHANGED'"),
                ("total += max(0.0, -profit)", "total += -profit"),
                ("r.risk_known, r.risk_reason = False, '%s %d: no usable SL / price / volume' % (kind, item.ticket)\n            break", "continue"),
                ("    r.existing_risk = total if r.risk_known else -1.0", "    r.existing_risk = total"),
                ("    if not ocomplete or len(orders) > 64:", "    if False:"),
                ("    if not complete or len(positions) > 64:", "    if False:"),
                ("pend_policy not in (PEND_COUNT, PEND_IGNORE)", "pend_policy not in (PEND_COUNT, PEND_IGNORE, PEND_UNSET)")]
        for old, new in muts:
            self.assertGreater(self._run_mutant(old, new), 0, 'not caught: ' + old)


if __name__ == '__main__':
    unittest.main()
