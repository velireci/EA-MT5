"""T012 bridge tests: history FACTS -> DL_Check with explicit policies. Hand-written scenarios, individual and combined gaps, propagation, mutants."""
import itertools
import math
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t012_bridge_fixtures as fx  # noqa: E402
import t012_bridge_reference as br  # noqa: E402
import t012_daily_reference as dl  # noqa: E402
import t012_history_reference as hist  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def strip_comments(text):
    text = re.sub(r'(?s)/\*.*?\*/', '', text)
    return re.sub(r'//[^\n]*', '', text)


def facts_of(r):
    f = hist.Facts()
    f.day_key = r['fday']
    f.complete = bool(r['complete'])
    f.deals_in_window = r['deals']
    f.positions = [hist.PosFact(position_id=100 + i) for i in range(r['npos'])]
    f.candidate_profit = float('nan') if r['nanp'] else r['cp']
    f.candidate_profit_commission_swap = r['cpcs']
    f.candidate_profit_commission_swap_fee = r['cpcsf']
    return f


def run(mod, r):
    return mod.check(fx.VERDICT[r['verdict']], facts_of(r), r['utc'], mod.Balance(bool(r['bknown']), r['bday'], r['bamt']),
                     mod.Policy(r['formula'], r['classif']), mod.Classified(r['trades'], r['wins'], r['losses']), r['maxt'], bool(r['maxset']))


def run_rows(mod):
    bad = []
    for r in fx.ROWS:
        res = run(mod, r)
        got = (int(res.entry_allowed), '|'.join(res.reasons), int(res.dl_called), int(res.cancel_pending_due))
        exp = (r['allowed'], r['reasons'], r['called'], r['cancel'])
        if r['called'] and not r['nanp'] or r['called'] and r['nanp'] and r['formula'] != 'PROFIT':
            if not math.isclose(res.closed_result, r['closed']):
                got += ('closed %r' % res.closed_result,)
                exp += ('closed %r' % r['closed'],)
        if got != exp:
            bad.append((r['name'], got, exp))
    return bad


class Bridge(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(br), [])

    def test_names_are_unique_and_cover_every_gap(self):
        names = [r['name'] for r in fx.ROWS]
        self.assertEqual(len(names), len(set(names)))
        seen = set()
        for r in fx.ROWS:
            seen.update(x for x in r['reasons'].split('|') if x)
        for need in ('HISTORY_NOT_READY:UNKNOWN', 'HISTORY_NOT_READY:BLOCK', 'HISTORY_NOT_READY:?', 'HISTORY_INCOMPLETE', 'BALANCE_START_UNSET', 'BALANCE_DAY_MISMATCH',
                     'POLICY_UNSET:result_formula', 'POLICY_UNSUPPORTED:result_formula', 'POLICY_UNSET:trade_classification',
                     'POLICY_UNSUPPORTED:trade_classification', 'CLASSIFICATION_CONTRADICTS_FACTS:trades_without_positions', 'STALE_SNAPSHOT_DAY',
                     'DAILY_WIN_STOP', 'CONSECUTIVE_LOSSES_STOP', 'DAILY_LOSS_LIMIT', 'MAX_TRADES_REACHED', 'POLICY_UNSET:max_trades_per_day'):
            self.assertIn(need, seen)

    def test_individual_and_combined_gaps_exhaustively(self):
        """Every subset of the four independent gaps: the reasons are exactly the gaps present, in the documented order, the daily check is not
        called, and nothing is allowed or proven."""
        gaps = [('verdict', 1, 'HISTORY_NOT_READY:UNKNOWN'), ('bknown', 0, 'BALANCE_START_UNSET'), ('formula', 'UNSET', 'POLICY_UNSET:result_formula'),
                ('classif', 'UNSET', 'POLICY_UNSET:trade_classification')]
        for mask in range(1, 16):
            kw = {}
            want = []
            for i, (k, v, reason) in enumerate(gaps):
                if mask >> i & 1:
                    kw[k] = v
                    want.append(reason)
            r = dict(fx.BASE)
            r.update(kw)
            r.update(wins=1, trades=1, cp=-9999.0)      # data that WOULD prove limits must prove nothing while a gap exists
            res = run(br, r)
            self.assertEqual(res.reasons, want, kw)
            self.assertFalse(res.entry_allowed or res.dl_called or res.cancel_pending_due or res.daily_limit_reached, kw)
            self.assertEqual(res.primary, want[0])

    def test_only_the_three_candidates_are_supported_and_each_selects_its_own_sum(self):
        f = hist.Facts()
        f.day_key = 20260715
        f.complete = True
        f.positions = [hist.PosFact(position_id=1)]
        f.candidate_profit, f.candidate_profit_commission_swap, f.candidate_profit_commission_swap_fee = 1.0, 2.0, 3.0
        for name, want in (('PROFIT', 1.0), ('PROFIT_COMMISSION_SWAP', 2.0), ('PROFIT_COMMISSION_SWAP_FEE', 3.0)):
            res = br.check('READY', f, fx.BASE['utc'], br.Balance(True, 20260715, 1000.0), br.Policy(name, 'CALLER_CLASSIFIED'), br.Classified(1, 0, 0), 3, True)
            self.assertEqual(res.closed_result, want)
        self.assertEqual(sorted(br.RESULT_FORMULAS), ['PROFIT', 'PROFIT_COMMISSION_SWAP', 'PROFIT_COMMISSION_SWAP_FEE'])
        for bogus in ('UNSET', '', 'profit', 'NET', 'PROFIT+FEE', 'AUTO', 'DEFAULT'):
            res = br.check('READY', f, fx.BASE['utc'], br.Balance(True, 20260715, 1000.0), br.Policy(bogus, 'CALLER_CLASSIFIED'), br.Classified(1, 0, 0), 3, True)
            self.assertFalse(res.entry_allowed or res.dl_called)

    def test_propagation_equals_the_daily_check_exactly(self):
        """With everything defined the result IS DL_Check's result for the mapped arguments, over a sweep of counters, results and limits."""
        f = hist.Facts()
        f.day_key = 20260715
        f.complete = True
        f.positions = [hist.PosFact(position_id=1)]
        for cp, trades, wins, losses, maxt, mset, bal in itertools.product((-250.0, -199.99, -200.0, 0.0, 75.0), (0, 1, 2, 3, 4), (0, 1, 2), (0, 1, 2, 3),
                                                                             (1, 2, 3), (True, False), (10000.0, 500.0, -1.0)):
            f.candidate_profit_commission_swap = cp
            res = br.check('READY', f, fx.BASE['utc'], br.Balance(True, 20260715, bal), br.Policy('PROFIT_COMMISSION_SWAP', 'CALLER_CLASSIFIED'),
                           br.Classified(trades, wins, losses), maxt, mset)
            if trades > 0 and not f.positions:
                continue
            ref = dl.check(fx.BASE['utc'], 20260715, bal, cp, trades, wins, losses, maxt, mset)
            self.assertEqual((res.entry_allowed, res.primary, res.reasons, res.cancel_pending_due, res.daily_limit_reached, res.day_key),
                             (ref.entry_allowed, ref.primary, ref.reasons, ref.cancel_pending_due, ref.daily_limit_reached, ref.day_key))
            self.assertTrue(res.dl_called)

    def test_the_deal_count_never_reaches_the_daily_check(self):
        base = run(br, dict(fx.BASE, deals=1))
        for deals in (0, 2, 50, 200):
            res = run(br, dict(fx.BASE, deals=deals))
            self.assertEqual((res.entry_allowed, res.reasons), (base.entry_allowed, base.reasons))

    def test_a_missing_count_is_never_zero(self):
        for kw in ({'trades': -1}, {'wins': -1}, {'losses': -1}):
            res = run(br, dict(fx.BASE, **kw))
            self.assertFalse(res.entry_allowed)
            self.assertTrue(any(x.startswith('INVALID_SNAPSHOT') for x in res.reasons))

    def test_bridge_never_selects_policy_or_balance_on_its_own(self):
        src = _read('tests', 't012_bridge_reference.py').split('"""', 2)[2]
        hdr = strip_comments(_read('src', 'include', 'DailyBridge.mqh'))
        self.assertIn('dl.check(', src)
        self.assertIn('DL_Check(', hdr)
        for word in ('DL_LOSS_DIVISOR', 'DBL_EPSILON', 'DL_WIN_STOP_AT', 'DL_CONSECUTIVE_LOSS_STOP_AT', 'SP_Evaluate', 'TimeGMT', 'TimeCurrent', 'TimeTradeServer',
                     'AccountInfo', 'HistorySelect', 'HistoryDeal', 'HistoryOrder', 'OrderSend', 'Position', 'deals_in_window', 'balance_start_known', 'nontrade', 'GlobalVariable', 'File'):
            self.assertNotIn(word, hdr)
        # no default policy value anywhere in the pure code
        code = strip_comments(hdr)
        self.assertEqual(sorted(set(re.findall(r'#define DB_(?:FORMULA|CLASSIFICATION)\w*\s+"([A-Z_]+)"', code))),
                         ['CALLER_CLASSIFIED', 'PROFIT', 'PROFIT_COMMISSION_SWAP', 'PROFIT_COMMISSION_SWAP_FEE'])

    def test_header_reads_only_the_documented_facts_members(self):
        hdr = strip_comments(_read('src', 'include', 'DailyBridge.mqh'))
        members = set(re.findall(r'\bfacts\.(\w+)', hdr))
        self.assertEqual(members, {'day_key', 'complete', 'n_pos', 'candidate_profit', 'candidate_profit_commission_swap', 'candidate_profit_commission_swap_fee'})

    def test_header_declares_its_dependencies_directly(self):
        hdr = _read('src', 'include', 'DailyBridge.mqh')
        self.assertIn('#include "DailyHistory.mqh"', hdr)
        self.assertIn('#include "DailyLimits.mqh"', hdr)


class Mutants(unittest.TestCase):
    def test_mutants_are_caught(self):
        src = _read('tests', 't012_bridge_reference.py')
        cases = [
            ('not-ready history allowed', "    if not ready:\n        bad.append('HISTORY_NOT_READY:' + (verdict if verdict in (UNKNOWN, BLOCK) else '?'))\n    elif not facts.complete:",
             "    if False:\n        bad.append('x')\n    elif not facts.complete:"),
            ('incomplete history allowed', "    elif not facts.complete:\n        bad.append('HISTORY_INCOMPLETE')", "    elif False:\n        bad.append('HISTORY_INCOMPLETE')"),
            ('balance unset ignored', "    if not balance.known:\n        bad.append('BALANCE_START_UNSET')", "    if False:\n        bad.append('BALANCE_START_UNSET')"),
            ('balance day ignored', "elif ready and balance.day != facts.day_key:", "elif False:"),
            ('formula UNSET accepted', "    if value == UNSET:\n        return 'POLICY_UNSET:' + name", "    if False:\n        return 'POLICY_UNSET:' + name"),
            ('unsupported accepted', "    if value not in supported:\n        return 'POLICY_UNSUPPORTED:' + name", "    if False:\n        return 'POLICY_UNSUPPORTED:' + name"),
            ('contradiction ignored', "elif ready and cls.trades > 0 and len(facts.positions) == 0:", "elif False:"),
            ('wrong candidate for PCSF', "'PROFIT_COMMISSION_SWAP_FEE': 'candidate_profit_commission_swap_fee'", "'PROFIT_COMMISSION_SWAP_FEE': 'candidate_profit_commission_swap'"),
            ('wrong candidate for PROFIT', "'PROFIT': 'candidate_profit',", "'PROFIT': 'candidate_profit_commission_swap',"),
            ('daily check called with a fixed day', "dl.check(utc, facts.day_key,", "dl.check(utc, 20260715,"),
            ('missing count turned into zero', "cls.trades, cls.wins, cls.consecutive_losses, max_trades", "max(0, cls.trades), max(0, cls.wins), max(0, cls.consecutive_losses), max_trades"),
            ('deal count used as the trade count', "cls.trades, cls.wins, cls.consecutive_losses, max_trades", "facts.deals_in_window, cls.wins, cls.consecutive_losses, max_trades"),
            ('limit forced to set', "cls.consecutive_losses, max_trades, max_trades_set)", "cls.consecutive_losses, max_trades, True)"),
            ('cancel flag dropped', "    r.cancel_pending_due = d.cancel_pending_due", "    r.cancel_pending_due = False"),
            ('daily result not propagated', "    r.entry_allowed = d.entry_allowed", "    r.entry_allowed = True"),
            ('daily check called despite a gap', "    if bad:\n        r.reasons = bad[:MAX_REASONS]", "    if False:\n        r.reasons = bad[:MAX_REASONS]"),
        ]
        for name, old, new in cases:
            with self.subTest(name):
                self.assertIn(old, src, 'vacuous mutant')
                ns = {'__name__': 'bridge_mutant'}
                exec(compile(src.replace(old, new, 1), 'bridge_mutant', 'exec'), ns)

                class M:
                    pass
                m = M()
                for k, v in ns.items():
                    setattr(m, k, v)
                try:
                    bad = run_rows(m)
                except Exception:
                    bad = ['raised']
                self.assertTrue(bad, 'mutant not caught: ' + name)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T012_BridgeTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
