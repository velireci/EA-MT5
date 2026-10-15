"""T012 read-only integration of the day-balance store into the preview's HISTORY_BRIDGE source: an explicit balance source (MANUAL default, unchanged), STORE only on the bridge path and only
through DBS_Load (never DBS_Capture), a usable record feeds SDbBalance with its origin kept in the diagnostics, every other outcome is an unknown balance that blocks with no silent fallback
to the manual input and no use of the current balance, and a valid balance bypasses no other missing item. Python model over the existing references + source pins. No order, no file write."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t012_balance_fixtures as fx  # noqa: E402
import t012_balance_reference as b  # noqa: E402
import t012_bridge_reference as br  # noqa: E402
import test_t012_balance as tb  # noqa: E402
import test_t012_history_bridge_wiring as hw  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EA = ('src', 'XauUsdTradePreview.mq5')
HDR = ('src', 'include', 'DailyBalanceStore.mqh')
SET_BRIDGE = ('src', 'presets', 'XauUsdTradePreview_T012_history_bridge_readonly.set')
SET_STORE = ('src', 'presets', 'XauUsdTradePreview_T012_balance_store_readonly.set')


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def load_results():
    out = []
    for r in fx.ROWS:
        if r['op'] != fx.LOAD:
            continue
        port = fx.FakePort(r['start'], r['sets'])
        out.append((r, b.load(port)))
    return out


def bridge(res_store, facts_out, formula='PROFIT', cls='CALLER_CLASSIFIED', day=None):
    """what the preview does: the store result -> SDbBalance -> DB_Check. The manual balance input is NOT an argument (no fallback exists)."""
    bal, text = b.for_bridge(res_store)
    if day is not None and bal.known:
        bal.day = day
    facts = facts_out.facts if facts_out.facts is not None else hw.hist.Facts()
    return br.check(facts_out.verdict, facts, hw.UTC, bal, br.Policy(formula, cls), br.Classified(1, 0, 0), 2, True), bal, text


class Mapping(unittest.TestCase):
    def test_only_a_usable_record_gives_a_known_balance_and_everything_else_is_unknown_and_zero(self):
        seen = set()
        for r, res in load_results():
            bal, text = b.for_bridge(res)
            seen.add(res.status)
            if res.status == b.USABLE:
                self.assertEqual((bal.known, bal.day, bal.amount), (True, res.day, res.amount), r['name'])
                self.assertIn(res.source, text, r['name'])             # the origin is kept in the diagnostics
                self.assertIn(res.source, ('WINDOW_EMPTY', 'OWNER_ASSERTED'))
            else:
                self.assertEqual((bal.known, bal.day, bal.amount), (False, 0, 0.0), r['name'])
                self.assertTrue(text.startswith('STORE_' + res.status), text)
                self.assertIn(res.reason.split(':')[0], text, r['name'])
        self.assertEqual(seen, {b.USABLE, b.NONE, b.UNKNOWN, b.BLOCK})   # every status is exercised by the existing LOAD rows

    def test_both_origins_stay_distinguishable(self):
        texts = {}
        for r, res in load_results():
            if res.status == b.USABLE:
                texts[res.source] = b.for_bridge(res)[1]
        self.assertEqual(set(texts), {'WINDOW_EMPTY', 'OWNER_ASSERTED'})
        self.assertNotEqual(texts['WINDOW_EMPTY'], texts['OWNER_ASSERTED'])

    def test_a_wrong_account_or_day_in_the_record_is_unknown(self):
        names = [r['name'] for r, _ in load_results()]
        wrong = [(r, res) for r, res in load_results() if r['reason'] in ('WRONG_ACCOUNT', 'WRONG_DAY_IN_RECORD')]
        self.assertTrue(wrong)
        for r, res in wrong:
            self.assertEqual(b.for_bridge(res)[0].known, False, r['name'])
        self.assertIn('LOAD_MISSING_FILE_IS_NONE_AND_NOTHING_IS_CREATED', names)


class Chain(unittest.TestCase):
    def setUp(self):
        self.out = hw.history('ONE_ROBOT_TRADE_OPENED_AND_CLOSED_TODAY', asserted=1)
        self.assertEqual(self.out.verdict, 'READY')
        self.assertTrue(self.out.facts.complete)

    def test_a_usable_record_removes_exactly_the_balance_reasons(self):
        used = False
        for r, res in load_results():
            if res.status != b.USABLE:
                continue
            used = True
            result, bal, _ = bridge(res, self.out, day=self.out.facts.day_key)
            self.assertTrue(result.dl_called, r['name'])
            self.assertFalse([x for x in result.reasons if x.startswith('BALANCE')], r['name'])
            self.assertEqual(bal.amount, res.amount)
        self.assertTrue(used)

    def test_none_unknown_block_and_a_wrong_day_block_with_an_unknown_balance_and_no_daily_check(self):
        for r, res in load_results():
            if res.status == b.USABLE:
                continue
            result, bal, _ = bridge(res, self.out)
            self.assertIn('BALANCE_START_UNSET', result.reasons, r['name'])
            self.assertFalse(result.entry_allowed or result.dl_called or result.cancel_pending_due or result.daily_limit_reached, r['name'])
        for r, res in load_results():                                  # a usable record of another Tirane day than the history
            if res.status == b.USABLE:
                result, _, _ = bridge(res, self.out, day=self.out.facts.day_key - 1)
                self.assertIn('BALANCE_DAY_MISMATCH', result.reasons)
                self.assertFalse(result.entry_allowed or result.dl_called)
                break

    def test_a_valid_balance_bypasses_no_other_missing_item(self):
        res = next(res for r, res in load_results() if res.status == b.USABLE)
        for formula, cls, expect in (('UNSET', 'CALLER_CLASSIFIED', 'POLICY_UNSET:result_formula'), ('PROFIT', 'UNSET', 'POLICY_UNSET:trade_classification')):
            result, _, _ = bridge(res, self.out, formula, cls, day=self.out.facts.day_key)
            self.assertIn(expect, result.reasons)
            self.assertFalse(result.entry_allowed or result.dl_called)
        incomplete = hw.history('ONE_ROBOT_TRADE_OPENED_AND_CLOSED_TODAY', asserted=0)
        result, _, _ = bridge(res, incomplete, day=incomplete.facts.day_key)
        self.assertIn('HISTORY_INCOMPLETE', result.reasons)
        self.assertFalse(result.entry_allowed or result.dl_called)

    def test_the_store_balance_never_falls_back_to_a_manual_amount(self):
        # the model has no manual argument at all; the real code must overwrite every manual field (see the source pins)
        res = next(res for r, res in load_results() if res.status == b.NONE)
        result, bal, _ = bridge(res, self.out)
        self.assertEqual((bal.known, bal.amount), (False, 0.0))
        self.assertIn('BALANCE_START_UNSET', result.reasons)


class MqlTest(unittest.TestCase):
    def test_the_mql_test_checks_the_feed_for_every_row_with_poisoned_start_values(self):
        src = hw.strip_comments(_read('src', 'tests', 'T012_BalanceStoreTest.mq5'))
        self.assertIn('DBS_ForBridge(res,fb)', src)
        self.assertIn('fb.known=true;', src)
        self.assertIn('fb.amount=55.0;', src)


class Sources(unittest.TestCase):
    def setUp(self):
        self.ea = hw.strip_comments(_read(*EA))
        self.hdr = hw.strip_comments(_read(*HDR))

    def block(self):
        return hw.bridge_block(self.ea)

    def test_the_source_input_defaults_to_manual_and_is_a_known_enum(self):
        self.assertIn('enum PREVIEW_BALANCE_SOURCE {BALANCE_SRC_MANUAL=0,BALANCE_SRC_STORE=1};', self.ea)
        self.assertEqual(hw.ea_inputs(self.ea)['InpDailyBalanceSource'], 'BALANCE_SRC_MANUAL')
        self.assertIn('StopPreview("BALANCE_SOURCE_UNKNOWN")', self.ea)
        self.assertIn('StopPreview("BALANCE_STORE_ONLY_WITH_HISTORY_BRIDGE")', self.ea)

    def test_store_is_read_only_load_only_and_only_in_the_bridge_branch(self):
        self.assertEqual(self.ea.count('DBS_Load('), 1)
        self.assertEqual(self.block().count('DBS_Load('), 1)
        for w in ('DBS_Capture', 'DBS_SRC_WE', 'DBS_SRC_OA', 'WriteFile', 'FileOpen', 'FileDelete', 'ACCOUNT_BALANCE', 'ACCOUNT_EQUITY', 'AccountInfo', 'EL_Acquire', 'ESF_Write', 'GlobalVariable'):
            self.assertNotIn(w, self.ea, w)
        self.assertEqual(self.ea.count('CDbsRealPort'), 1)
        self.assertIn('if(balance_store)', self.block())

    def test_the_store_branch_overwrites_every_manual_field_before_db_check_and_has_no_fallback(self):
        blk = self.block()
        assign = blk.index('hbalance.amount=InpDailyBalanceStart;')
        load = blk.index('DBS_Load(')
        forb = blk.index('DBS_ForBridge(')
        check = blk.index('DB_Check(')
        self.assertTrue(assign < load < forb < check)
        self.assertEqual(blk.count('DBS_ForBridge('), 1)
        self.assertIn('DBS_ForBridge(hstore,hbalance)', blk)
        store = blk[blk.index('if(balance_store)'):blk.index('SDbPolicy hpolicy;')]
        self.assertNotIn('InpDailyBalanceStart', store)
        self.assertNotIn('InpDailySnapshotDay', store)
        self.assertNotRegex(store, r'else')

    def test_the_helper_overwrites_all_three_fields_on_every_path_and_reads_nothing(self):
        h = self.hdr[self.hdr.index('string DBS_ForBridge('):]
        h = h[:h.index('\n  }\n') + 5]
        for f in ('b.known=false;', 'b.day=0;', 'b.amount=0.0;'):
            self.assertIn(f, h)
        self.assertIn('DBS_USABLE', h)
        for w in ('port.', 'Account', 'ACCOUNT_', 'File', 'TimeGMT', 'InpDaily'):
            self.assertNotIn(w, h, w)

    def test_manual_and_snapshot_paths_are_not_touched_by_the_store(self):
        self.assertIn('DG_Evaluate(daily_on,', self.ea)
        self.assertIn('hbalance.known=(InpDailyBalanceStart>0.0);', self.ea)
        self.assertEqual(self.ea.count('DG_Evaluate('), 1)
        code = re.sub(r'"[^"\n]*"', '""', self.ea)             # string literals are text, not calls
        self.assertEqual(code.count('DBS_'), code.count('DBS_Load(') + code.count('DBS_ForBridge('))

    def test_the_policies_stay_explicit_inputs(self):
        blk = self.block()
        self.assertNotRegex(blk, r'(result_formula|classification)\s*=\s*"')
        self.assertIn('hpolicy.result_formula=InpDailyResultFormula;', blk)
        self.assertIn('hpolicy.classification=InpDailyClassification;', blk)

    def test_the_store_preset_exists_with_the_store_selected_and_every_policy_unset(self):
        vals = hw.read_set(*SET_STORE)
        self.assertEqual((vals['InpDailySource'], vals['InpDailyBalanceSource']), ('2', '1'))
        self.assertEqual((vals['InpDailyResultFormula'], vals['InpDailyClassification'], vals['InpMaxTrades']), ('UNSET', 'UNSET', '-1'))
        self.assertEqual(vals['InpDailyHistoryComplete'], 'false')
        for k in ('InpDailyBalanceStart', 'InpDailySnapshotDay'):
            self.assertIn(vals[k], ('-1', '0'))

    def test_the_older_presets_list_the_new_input_with_the_manual_value(self):
        for parts in (SET_BRIDGE, ('src', 'presets', 'XauUsdTradePreview_T012_hypothetical_daily_block.set')):
            self.assertEqual(hw.read_set(*parts)['InpDailyBalanceSource'], '0', parts[-1])


if __name__ == '__main__':
    unittest.main()
