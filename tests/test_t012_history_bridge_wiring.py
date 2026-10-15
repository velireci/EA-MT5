"""T012 HISTORY_BRIDGE source of the observation-only preview: wiring of DH_ReadAndBuild -> DB_Check -> final preview result, preservation of the
MANUAL and DAILY_SNAPSHOT sources, defaults, presets, and a Python model of the glue over the existing pure references (no new rule)."""
import difflib
import os
import re
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t012_bridge_reference as br  # noqa: E402
import t012_gate_fixtures as gfx  # noqa: E402
import t012_gate_reference as g  # noqa: E402
import t012_history_fixtures as hfx  # noqa: E402
import t012_history_reference as hist  # noqa: E402
import test_t012_gate as tg  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EA = ('src', 'XauUsdTradePreview.mq5')
BASE = 'f1db94c'
SET_BRIDGE = ('src', 'presets', 'XauUsdTradePreview_T012_history_bridge_readonly.set')
SET_HYP = ('src', 'presets', 'XauUsdTradePreview_T012_hypothetical_daily_block.set')


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def strip_comments(text):
    text = re.sub(r'(?s)/\*.*?\*/', '', text)
    return re.sub(r'//[^\n]*', '', text)


def bridge_block(ea):
    i = ea.index('if(daily_bridge)\n     {')
    j = ea.index('\n     }', i)
    return ea[i:j]


def read_set(*parts):
    vals = {}
    for line in _read(*parts).splitlines():
        line = line.strip()
        if not line or line.startswith(';'):
            continue
        k, v = line.split('=', 1)
        assert k not in vals, k
        vals[k] = v
    return vals


def ea_inputs(ea):
    return dict((n, v.strip()) for n, v in re.findall(r'^input\s+\w+\s+(Inp\w+)\s*=\s*([^;]+);', ea, re.M))


class Wiring(unittest.TestCase):
    def setUp(self):
        self.raw = _read(*EA)
        self.ea = strip_comments(self.raw)
        self.blk = bridge_block(self.ea)

    def test_new_source_and_the_two_existing_ones(self):
        self.assertIn('enum PREVIEW_DAILY_SOURCE {DAILY_SRC_MANUAL=0,DAILY_SRC_SNAPSHOT=1,DAILY_SRC_HISTORY_BRIDGE=2};', self.ea)
        self.assertIn('input PREVIEW_DAILY_SOURCE InpDailySource=DAILY_SRC_MANUAL;', self.ea)      # MANUAL stays the default
        self.assertIn('#include "include/DailyBridge.mqh"', self.ea)
        self.assertIn('bool daily_on=(InpDailySource==DAILY_SRC_SNAPSHOT);', self.ea)
        self.assertIn('bool daily_bridge=(InpDailySource==DAILY_SRC_HISTORY_BRIDGE);', self.ea)
        self.assertIn('#property version "1.05"', self.ea)

    def test_snapshot_and_manual_lines_are_preserved(self):
        base = subprocess.run(['git', 'show', BASE + ':src/XauUsdTradePreview.mq5'], cwd=ROOT, capture_output=True, text=True).stdout
        if not base:
            self.skipTest('base commit not available')
        old = [l.rstrip() for l in base.splitlines()]
        new = [l.rstrip() for l in self.raw.splitlines()]
        removed = [l[2:] for l in difflib.ndiff(old, new) if l.startswith('- ')]
        allowed_prefix = ('#property version "1.04"', 'enum PREVIEW_DAILY_SOURCE {DAILY_SRC_MANUAL=0,DAILY_SRC_SNAPSHOT=1};', 'input PREVIEW_DAILY_SOURCE InpDailySource=',
                          'input int InpDailySnapshotDay=0;', 'input double InpDailyBalanceStart=-1;',
                          'else Print("T012 DAILY source=MANUAL: not evaluated, the preview behaves as before");')
        for l in removed:
            self.assertTrue(l.strip().startswith(allowed_prefix), 'an existing line changed: ' + l)
        self.assertEqual(len(removed), 6)
        # the SNAPSHOT call and its refusal in the tester are byte-identical
        for need in ('if(daily_on && MQLInfoInteger(MQL_TESTER)) {StopPreview("DAILY_UTC_UNAVAILABLE_IN_TESTER");return;}',
                     'bool daily_evaluated=DG_Evaluate(daily_on,daily_on ? TimeGMT() : 0,InpDailySnapshotDay,InpDailyBalanceStart,InpDailyResultKnown,InpDailyClosedResult,',
                     'InpTradesToday,InpDailyWins,InpDailyConsecutiveLosses,InpMaxTrades,daily);'):
            self.assertIn(need, self.ea)
        self.assertIn('else if(!daily_bridge) Print("T012 DAILY source=MANUAL: not evaluated, the preview behaves as before");', self.ea)

    def test_chain_history_read_then_bridge_then_final_result(self):
        self.assertEqual(self.ea.count('DH_ReadAndBuild('), 1)
        self.assertEqual(self.ea.count('DB_Check('), 1)
        self.assertEqual(self.ea.count('DB_Check('), len(re.findall(r'DB_Check\(', self.blk)))
        self.assertEqual(self.ea.count('DH_ReadAndBuild('), len(re.findall(r'DH_ReadAndBuild\(', self.blk)))
        self.assertLess(self.blk.index('DH_ReadAndBuild('), self.blk.index('DB_Check('))
        self.assertIn('daily_evaluated=true;', self.blk)
        # the bridge result becomes the daily result that the one and only final assignment consumes
        lines = [l.strip() for l in self.ea.splitlines() if 'bool preview_ok' in l]
        self.assertEqual(lines, ['bool preview_ok=DG_FinalPreview(loss_check=="OK",permit.allow,daily_evaluated,daily.entry_allowed);'])
        self.assertEqual(len(re.findall(r'\bpreview_ok\s*=[^=]', self.ea)), 1)
        for field in ('entry_allowed', 'primary', 'n_reasons', 'cancel_pending_due', 'daily_limit_reached', 'day_key'):
            self.assertRegex(self.blk, r'daily\.%s=hbridge\.%s;' % (field, field))
        self.assertIn('daily.reasons[hi]=', self.blk)

    def test_the_tester_refusal_precedes_any_history_read(self):
        i = self.ea.index('if(daily_bridge && MQLInfoInteger(MQL_TESTER)) {StopPreview("DAILY_HISTORY_UNAVAILABLE_IN_TESTER");return;}')
        self.assertLess(i, self.ea.index('DH_ReadAndBuild('))

    def test_every_policy_and_figure_is_an_explicit_input(self):
        for need in ('hcfg.ea_magic=InpDailyEaMagic;', 'hcfg.server_offset_seconds=InpDailyServerOffsetSeconds;',
                     'hcfg.history_complete_asserted=InpDailyHistoryComplete;', 'hcfg.utc_in_day=TimeGMT();', 'hbalance.amount=InpDailyBalanceStart;',
                     'hbalance.day=InpDailySnapshotDay;', 'hbalance.known=(InpDailyBalanceStart>0.0);', 'hpolicy.result_formula=InpDailyResultFormula;',
                     'hpolicy.classification=InpDailyClassification;', 'hclassified.trades=DG_Counter(InpTradesToday);', 'hclassified.wins=DG_Counter(InpDailyWins);',
                     'hclassified.consecutive_losses=DG_Counter(InpDailyConsecutiveLosses);', 'InpMaxTrades>=0'):
            self.assertIn(need, self.blk)
        self.assertNotIn('InpDailyClosedResult', self.blk)       # the result comes from the facts through the chosen formula, never from the manual figure
        self.assertNotIn('InpDailyResultKnown', self.blk)

    def test_nothing_is_derived_or_chosen_in_the_bridge_block(self):
        for word in ('TimeTradeServer', 'TimeCurrent', 'TimeLocal', 'AccountInfo', 'HistorySelect', 'HistoryDeal', 'HistoryOrder', 'PositionsTotal', 'OrdersTotal',
                     'PositionGet', 'OrderSend', 'OrderDelete', 'PositionClose', 'CTrade', 'MqlTradeRequest', 'FileOpen', 'GlobalVariable', 'SymbolInfo'):
            self.assertNotIn(word, self.blk)
        self.assertNotRegex(self.blk, r'(result_formula|classification)\s*=\s*"')      # no policy literal assigned
        self.assertNotRegex(self.blk, r'(ea_magic|server_offset_seconds)\s*=\s*\d')    # no magic / offset literal
        self.assertNotRegex(self.blk, r'max_trades\s*=\s*[23]\b')                      # the 2/3 conflict is not resolved
        self.assertNotIn('"PROFIT', self.blk)

    def test_defaults_stay_unset_unknown_and_not_complete(self):
        inp = ea_inputs(self.ea)
        want = {'InpDailySource': 'DAILY_SRC_MANUAL', 'InpDailyEaMagic': '0', 'InpDailyServerOffsetSeconds': '99999', 'InpDailyHistoryComplete': 'false',
                'InpDailyResultFormula': '"UNSET"', 'InpDailyClassification': '"UNSET"', 'InpDailyBalanceStart': '-1', 'InpDailySnapshotDay': '0',
                'InpDailyWins': '-1', 'InpDailyConsecutiveLosses': '-1', 'InpTradesToday': '-1', 'InpMaxTrades': '-1'}
        for k, v in want.items():
            self.assertEqual(inp.get(k), v, k)

    def test_the_history_reason_is_visible(self):
        self.assertIn('hreason', self.blk)
        self.assertIn('history_reason=%s', self.raw)
        self.assertIn('DB_Joined(hbridge)', self.blk)
        self.assertIn('source=HISTORY_BRIDGE', self.raw)

    def test_no_order_cancellation_or_persistence_in_the_ea(self):
        for word in ('OrderSend', 'OrderDelete', 'PositionClose', 'CTrade', 'OrderModify', 'MqlTradeRequest', 'FileOpen', 'GlobalVariableSet', 'HistorySelect',
                     'AccountInfo', 'PositionsTotal', 'OrdersTotal'):
            self.assertNotIn(word, self.ea)


class Presets(unittest.TestCase):
    def setUp(self):
        self.inputs = ea_inputs(strip_comments(_read(*EA)))

    def test_both_presets_list_every_input_exactly_once(self):
        for parts in (SET_BRIDGE, SET_HYP):
            vals = read_set(*parts)
            self.assertEqual(sorted(vals), sorted(self.inputs), parts[-1])

    def test_the_readonly_bridge_preset(self):
        v = read_set(*SET_BRIDGE)
        self.assertEqual(v['InpDailySource'], '2')
        self.assertEqual(v['InpDailyHistoryComplete'], 'false')          # HISTORY_INCOMPLETE is what the preset proves
        self.assertEqual(v['InpDailyResultFormula'], 'UNSET')
        self.assertEqual(v['InpDailyClassification'], 'UNSET')
        self.assertEqual(v['InpDailyBalanceStart'], '-1')
        for k in ('InpDailyWins', 'InpDailyConsecutiveLosses', 'InpTradesToday', 'InpMaxTrades'):
            self.assertEqual(v[k], '-1')
        self.assertEqual(v['InpDailyResultKnown'], 'false')
        self.assertGreater(int(v['InpDailyEaMagic']), 0)
        self.assertEqual(int(v['InpDailyServerOffsetSeconds']) % 900, 0)
        self.assertNotEqual(v['InpDailyServerOffsetSeconds'], '99999')
        text = _read(*SET_BRIDGE)
        for need in ('HISTORY_INCOMPLETE', 'BALANCE_START_UNSET', 'POLICY_UNSET:result_formula', 'POLICY_UNSET:trade_classification', 'daily_check_called=0',
                     'no order is sent'):
            self.assertIn(need, text)

    def test_the_older_hypothetical_preset_keeps_its_snapshot_behaviour(self):
        v = read_set(*SET_HYP)
        self.assertEqual((v['InpDailySource'], v['InpDailyClosedResult'], v['InpDailyResultKnown'], v['InpDailyBalanceStart']), ('1', '-250.00', 'true', '10000.00'))
        self.assertEqual((v['InpDailyEaMagic'], v['InpDailyServerOffsetSeconds'], v['InpDailyHistoryComplete'], v['InpDailyResultFormula'], v['InpDailyClassification']),
                         ('0', '99999', 'false', 'UNSET', 'UNSET'))


UTC = gfx.BASE['utc']          # 2026-07-15 09:00 UTC, Tirane day 20260715


def history(row_name, asserted):
    r = next(x for x in hfx.ROWS if x['name'] == row_name)
    cfg, raw = tg_make(r)
    cfg.history_complete_asserted = bool(asserted)
    return hist.build(cfg, raw, True)


def tg_make(r):
    from test_t012_history import make
    return make(r)


def glue(outcome, balance_known, balance_day, balance, formula, classification, trades, wins, losses, max_trades, loss_ok=True, permit=True):
    """Python model of the EA branch: DB_Check over the history outcome, then the existing final result."""
    facts = outcome.facts if outcome.facts is not None else hist.Facts()
    res = br.check(outcome.verdict, facts, UTC, br.Balance(balance_known, balance_day, balance), br.Policy(formula, classification),
                   br.Classified(trades, wins, losses), max_trades, max_trades >= 0)
    return res, g.final_preview(loss_ok, permit, True, res.entry_allowed)


class Chain(unittest.TestCase):
    """History facts -> bridge -> the final preview result, with the existing references. Nothing is re-implemented."""

    def test_default_inputs_block_with_concrete_history_and_policy_reasons(self):
        cfg = hist.Cfg(0, UTC, 99999, False)
        out = hist.build(cfg, hist.Raw(), True)
        self.assertEqual(out.verdict, 'UNKNOWN')
        self.assertIn('INVALID_CONFIG', out.reason)
        res, final = glue(out, False, 0, -1.0, 'UNSET', 'UNSET', -1, -1, -1, -1)
        self.assertEqual(res.reasons, ['HISTORY_NOT_READY:UNKNOWN', 'BALANCE_START_UNSET', 'POLICY_UNSET:result_formula', 'POLICY_UNSET:trade_classification'])
        self.assertFalse(final or res.dl_called or res.cancel_pending_due)

    def test_the_readonly_preset_case_ready_but_incomplete_and_everything_unset(self):
        out = history('ONE_ROBOT_TRADE_OPENED_AND_CLOSED_TODAY', asserted=0)
        self.assertEqual(out.verdict, 'READY')
        self.assertFalse(out.facts.complete)
        res, final = glue(out, False, 0, -1.0, 'UNSET', 'UNSET', -1, -1, -1, -1)
        self.assertEqual(res.primary, 'HISTORY_INCOMPLETE')
        self.assertEqual(res.reasons, ['HISTORY_INCOMPLETE', 'BALANCE_START_UNSET', 'POLICY_UNSET:result_formula', 'POLICY_UNSET:trade_classification'])
        self.assertFalse(final or res.dl_called)
        self.assertFalse(res.cancel_pending_due or res.daily_limit_reached)

    def test_block_verdict_blocks_the_final_result(self):
        r = next(x for x in hfx.ROWS if x['verdict'] == 'BLOCK')
        cfg, raw = tg_make(r)
        out = hist.build(cfg, raw, True)
        self.assertEqual(out.verdict, 'BLOCK')
        res, final = glue(out, True, 20260715, 10000.0, 'PROFIT', 'CALLER_CLASSIFIED', 1, 0, 0, 3)
        self.assertEqual(res.reasons, ['HISTORY_NOT_READY:BLOCK'])
        self.assertFalse(final)

    def test_complete_ready_history_with_every_input_lets_the_daily_check_decide(self):
        out = history('ONE_ROBOT_TRADE_OPENED_AND_CLOSED_TODAY', asserted=1)
        self.assertTrue(out.facts.complete)
        res, final = glue(out, True, 20260715, 10000.0, 'PROFIT_COMMISSION_SWAP', 'CALLER_CLASSIFIED', 1, 1, 0, 3)
        self.assertTrue(res.dl_called)
        self.assertEqual(res.reasons, ['DAILY_WIN_STOP'])      # a caller-classified win; closed result 11.25 comes from the facts
        self.assertAlmostEqual(res.closed_result, 11.25)
        self.assertTrue(res.cancel_pending_due)
        self.assertFalse(final)
        ok, final_ok = glue(out, True, 20260715, 10000.0, 'PROFIT_COMMISSION_SWAP', 'CALLER_CLASSIFIED', 1, 0, 0, 3)
        self.assertEqual(ok.reasons, [])
        self.assertTrue(final_ok)
        self.assertFalse(glue(out, True, 20260715, 10000.0, 'PROFIT_COMMISSION_SWAP', 'CALLER_CLASSIFIED', 1, 0, 0, 3, loss_ok=False)[1])
        self.assertFalse(glue(out, True, 20260715, 10000.0, 'PROFIT_COMMISSION_SWAP', 'CALLER_CLASSIFIED', 1, 0, 0, 3, permit=False)[1])

    def test_the_two_trade_limit_conflict_is_not_resolved(self):
        out = history('ONE_ROBOT_TRADE_OPENED_AND_CLOSED_TODAY', asserted=1)
        res, final = glue(out, True, 20260715, 10000.0, 'PROFIT', 'CALLER_CLASSIFIED', 1, 0, 0, -1)
        self.assertEqual(res.reasons, ['POLICY_UNSET:max_trades_per_day'])
        self.assertFalse(final)

    def test_the_wrong_day_of_the_balance_blocks(self):
        out = history('ONE_ROBOT_TRADE_OPENED_AND_CLOSED_TODAY', asserted=1)
        res, final = glue(out, True, 20260714, 10000.0, 'PROFIT', 'CALLER_CLASSIFIED', 1, 0, 0, 3)
        self.assertEqual(res.reasons, ['BALANCE_DAY_MISMATCH'])
        self.assertFalse(final or res.dl_called)

    def test_manual_and_snapshot_sources_still_follow_the_existing_gate_rows(self):
        self.assertEqual(tg.run_rows(g), [])


if __name__ == '__main__':
    unittest.main()
