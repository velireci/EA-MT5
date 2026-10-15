"""T012 integration tests for the observation-only preview: gate mapping, final decision, and the wiring of the preview source file."""
import difflib
import itertools
import os
import re
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t012_daily_reference as dl  # noqa: E402
import t012_gate_fixtures as fx  # noqa: E402
import t012_gate_reference as g  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EA = ('src', 'XauUsdTradePreview.mq5')


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def strip_comments(text):
    text = re.sub(r'(?s)/\*.*?\*/', '', text)
    return re.sub(r'//[^\n]*', '', text)


def run_rows(mod):
    bad = []
    for r in fx.ROWS:
        ev, res = mod.evaluate(bool(r['src']), r['utc'], r['day'], r['bal'], bool(r['known']), r['res'], r['trades'], r['wins'], r['losses'], r['maxt'])
        allowed = res.entry_allowed if ev else True
        reasons = '|'.join(res.reasons) if ev else ''
        cancel = res.cancel_pending_due if ev else False
        final = mod.final_preview(bool(r['loss_ok']), bool(r['permit']), ev, allowed)
        got = (int(ev), int(allowed), reasons, int(final), int(cancel))
        exp = (r['evaluated'], r['allowed'], r['reasons'], r['final'], r['cancel'])
        if got != exp:
            bad.append((r['name'], got, exp))
    return bad


class Gate(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(g), [])

    def test_a_daily_block_can_never_be_ignored_in_the_final_result(self):
        for loss_ok, permit in itertools.product((True, False), repeat=2):
            self.assertFalse(g.final_preview(loss_ok, permit, True, False))          # daily BLOCK: always blocked
            self.assertEqual(g.final_preview(loss_ok, permit, True, True), loss_ok and permit)
            self.assertEqual(g.final_preview(loss_ok, permit, False, False), loss_ok and permit)   # MANUAL: unchanged whatever the daily value
            self.assertEqual(g.final_preview(loss_ok, permit, False, True), loss_ok and permit)

    def test_manual_preserves_the_existing_result_for_every_figure(self):
        import random
        rnd = random.Random(7)
        for _ in range(2000):
            kw = dict(utc=rnd.choice([0, fx.BASE['utc']]), snapshot_day=rnd.choice([0, 20260715, 20260101]), balance_start=rnd.choice([-1.0, 0.0, 10000.0]),
                      result_known=rnd.random() < 0.5, closed_result=rnd.choice([-9999.0, 0.0, 77.0]), trades_today=rnd.choice([-1, 0, 5]),
                      wins_today=rnd.choice([-1, 0, 3]), consecutive_losses=rnd.choice([-1, 0, 4]), max_trades=rnd.choice([-1, 0, 2]))
            ev, res = g.evaluate(False, **kw)
            self.assertEqual((ev, res), (False, None))
            for loss_ok, permit in itertools.product((True, False), repeat=2):
                self.assertEqual(g.final_preview(loss_ok, permit, ev, False), loss_ok and permit)

    def test_preview_defaults_are_unknown_and_block_without_a_limit(self):
        ev, res = g.evaluate(True, fx.BASE['utc'], 0, -1.0, False, 0.0, -1, -1, -1, -1)
        self.assertTrue(ev)
        self.assertFalse(res.entry_allowed)
        self.assertFalse(res.cancel_pending_due or res.daily_limit_reached)
        self.assertFalse(any(x in (dl.R_WIN, dl.R_STREAK, dl.R_LOSS, dl.R_TRADES) for x in res.reasons))

    def test_the_trade_limit_stays_unset_by_default(self):
        ea = strip_comments(_read(*EA))
        self.assertIn('input long InpMaxTrades=-1;', ea)
        ev, res = g.evaluate(True, fx.BASE['utc'], 20260715, 10000.0, True, 0.0, 0, 0, 0, -1)
        self.assertEqual(res.reasons, [dl.R_UNSET])

    def test_gate_reuses_dailylimits_and_copies_no_formula(self):
        hdr = _read('src', 'include', 'DailyPreviewGate.mqh')
        self.assertIn('DL_Check(', hdr)
        for word in ('DL_LOSS_DIVISOR', 'DBL_EPSILON', 'threshold', 'SP_Evaluate', 'TimeGMT', 'TimeCurrent', 'AccountInfo', 'History', 'OrderSend', 'Position'):
            self.assertNotIn(word, hdr)
        src = _read('tests', 't012_gate_reference.py').split('"""', 2)[2]
        self.assertIn('dl.check(', src)
        self.assertNotIn('LOSS_FRACTION', src)


class Wiring(unittest.TestCase):
    """The preview source file: the daily gate must be wired into the FINAL decision, and nothing else of T008-T010 may change."""

    def setUp(self):
        self.ea = strip_comments(_read(*EA))

    def test_final_result_is_the_gate_of_the_three_parts(self):
        lines = [l.strip() for l in self.ea.splitlines() if 'preview_ok' in l and '=' in l and 'bool preview_ok' in l]
        self.assertEqual(lines, ['bool preview_ok=DG_FinalPreview(loss_check=="OK",permit.allow,daily_evaluated,daily.entry_allowed);'])
        self.assertEqual(len(re.findall(r'\bpreview_ok\s*=[^=]', self.ea)), 1)               # no other write to the final result
        self.assertNotIn('permit.allow=true', self.ea)

    def test_manual_is_the_default_and_the_source_is_explicit(self):
        self.assertIn('input PREVIEW_DAILY_SOURCE InpDailySource=DAILY_SRC_MANUAL;', self.ea)
        self.assertIn('DG_Evaluate(daily_on,', self.ea)
        self.assertIn('bool daily_on=(InpDailySource==DAILY_SRC_SNAPSHOT);', self.ea)

    def test_tester_refuses_the_daily_snapshot_before_any_utc_is_used(self):
        i = self.ea.index('if(daily_on && MQLInfoInteger(MQL_TESTER))')
        j = self.ea.index('DG_Evaluate(daily_on,')
        self.assertLess(i, j)
        self.assertIn('StopPreview("DAILY_UTC_UNAVAILABLE_IN_TESTER")', self.ea)
        self.assertIn('daily_on ? TimeGMT() : 0', self.ea)

    def test_inputs_come_from_explicit_preview_inputs_only(self):
        call = self.ea[self.ea.index('DG_Evaluate(daily_on,'):]
        call = call[:call.index(';')]
        for name in ('InpDailySnapshotDay', 'InpDailyBalanceStart', 'InpDailyResultKnown', 'InpDailyClosedResult', 'InpTradesToday', 'InpDailyWins',
                     'InpDailyConsecutiveLosses', 'InpMaxTrades'):
            self.assertIn(name, call)
        for forbidden in ('AccountInfo', 'HistorySelect', 'HistoryDeal', 'HistoryOrder', 'PositionsTotal', 'OrdersTotal', '3.57'):
            self.assertNotIn(forbidden, self.ea)

    def test_the_diagnostic_flag_cancels_nothing(self):
        self.assertIn('cancel_pending_due', self.ea)
        for word in ('OrderSend', 'OrderDelete', 'PositionClose', 'CTrade', 'OrderModify', 'MqlTradeRequest'):
            self.assertNotIn(word, self.ea)

    def test_defaults_of_the_new_inputs_are_unknown(self):
        for line in ('input int InpDailySnapshotDay=0;', 'input double InpDailyBalanceStart=-1;', 'input bool InpDailyResultKnown=false;',
                     'input long InpDailyWins=-1;', 'input long InpDailyConsecutiveLosses=-1;'):
            self.assertIn(line, self.ea)

    def test_t008_to_t010_and_t007_blocks_are_untouched(self):
        """Every line of the previous version of the file (c = ca3bd57's tree: 78726c4) must still be present, in order, except the allowed few."""
        base = subprocess.run(['git', 'show', '78726c4:src/XauUsdTradePreview.mq5'], cwd=ROOT, capture_output=True, text=True).stdout
        if not base:
            self.skipTest('base commit not available')
        old = [l.rstrip() for l in base.splitlines()]
        new = [l.rstrip() for l in _read(*EA).splitlines()]
        removed = [l[2:] for l in difflib.ndiff(old, new) if l.startswith('- ')]
        allowed_removed = ('#property version "1.03"', 'bool preview_ok=(loss_check=="OK" && permit.allow);',
                           'input long InpTradesToday=-1;', 'input long InpMaxTrades=-1;')    # the two inputs only gained a comment
        for l in removed:
            self.assertIn(l.strip(), [a.strip() for a in allowed_removed], 'an existing line changed: ' + l)


class Mutants(unittest.TestCase):
    def test_mutants_are_caught(self):
        src = _read('tests', 't012_gate_reference.py')
        cases = [('daily block ignored in the final result', "((not daily_evaluated) or daily_allowed)", "True"),
                 ('daily allow can override a failed existing check', "return bool(loss_ok and permit_allow and ((not daily_evaluated) or daily_allowed))", "return bool(loss_ok and permit_allow) or bool(daily_evaluated and daily_allowed)"),
                 ('manual evaluates anyway', "    if not use_snapshot:\n        return False, None", "    if False:\n        return False, None"),
                 ('unknown result treated as zero', "closed_result if result_known else float('nan')", "closed_result"),
                 ('unset limit treated as a default', "max_set = isinstance(max_trades, int) and not isinstance(max_trades, bool) and max_trades >= 0", "max_set = True"),
                 ('unknown counter passed through as 0', "return value if isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= MAX_COUNT else -1", "return max(0, value)")]
        for name, old, new in cases:
            with self.subTest(name):
                self.assertIn(old, src, 'vacuous mutant')
                ns = {'__name__': 'gate_mutant'}
                exec(compile(src.replace(old, new, 1), 'gate_mutant', 'exec'), ns)

                class M:
                    pass
                m = M()
                for k, v in ns.items():
                    setattr(m, k, v)
                bad = run_rows(m)
                if not bad and name == 'daily allow can override a failed existing check':
                    bad = [] if m.final_preview(False, True, True, True) is False else ['override']
                self.assertTrue(bad, 'mutant not caught: ' + name)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T012_GateTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
