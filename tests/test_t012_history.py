"""T012 tests: read-only daily history FACTS (pure core; no MT5, no order, no policy)."""
import copy
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t012_history_fixtures as fx  # noqa: E402
import t012_history_reference as h  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def facts_text(x):
    F = lambda v: '%.6f' % (v + 0.0)
    cell = lambda c: '%d,%s' % (c.count, ','.join(F(v) for v in (c.volume, c.profit, c.commission, c.swap, c.fee)))
    pos = ','.join('%d:%d:%d:%s:%s:%s:%s:%s:%s:%s' % (p.position_id, p.n_in, p.n_out, F(p.volume_in), F(p.volume_out), F(p.profit), F(p.commission), F(p.swap), F(p.fee), p.state)
                   for p in x.positions)
    return ('day=%d;win=%d-%d;dw=%d;dup=%d;out=%d;other=%d;exnot=%d;nt=%d,%s;IN=%s;OUT=%s;INOUT=%s;OUT_BY=%s;OTHER=%s;pos=%s;cand=%s;formula=%s;bal=%d;complete=%d' %
            (x.day_key, x.window_start, x.window_end, x.deals_in_window, x.duplicates, x.outside_window, x.other_trade_deals, x.exits_not_by_ea_magic, x.nontrade_count,
             ','.join(F(v) for v in (x.nontrade_profit, x.nontrade_commission, x.nontrade_swap, x.nontrade_fee)), cell(x.matrix['IN']), cell(x.matrix['OUT']), cell(x.matrix['INOUT']),
             cell(x.matrix['OUT_BY']), cell(x.matrix['OTHER']), pos,
             ','.join(F(v) for v in (x.candidate_profit, x.candidate_profit_commission_swap, x.candidate_profit_commission_swap_fee)), x.result_formula, int(x.balance_start_known),
             int(x.complete)))


def make(r):
    cfg = h.Cfg(r['magic'], r['utc'], r['offset'], bool(r['asserted']))
    w = r['raw']
    raw = h.Raw(bool(w['api_ok']), 'terminal error', bool(w['hist_ok']), bool(w['positions_ok']), bool(w['margin_ok']), w['margin_mode'], w['vol_step'], bool(w['deals_trunc']),
                bool(w['pos_trunc']), [h.RawDeal(*d) for d in r['deals']], [h.RawPos(p[0], bool(p[1]), p[2], p[3], p[4], bool(p[5])) for p in r['positions']])
    return cfg, raw


def run_rows(mod):
    bad = []
    for r in fx.ROWS:
        cfg, raw = make(r)
        raw_before = copy.deepcopy(raw)
        o = mod.build(cfg, raw, bool(r['stable']))
        if raw != raw_before:
            bad.append((r['name'], 'the core changed its input'))
        if o.verdict != r['verdict']:
            bad.append((r['name'], 'verdict', o.verdict, r['verdict'], o.reason))
            continue
        if r['why'] and not o.reason.startswith(r['why']):
            bad.append((r['name'], 'reason', o.reason))
        if o.verdict == 'READY':
            a, b = facts_text(o.facts), fx.canon(r['exp'])
            if a != b:
                bad.append((r['name'], 'facts', a, b))
        elif o.facts is not None:
            bad.append((r['name'], 'facts with a non-READY verdict'))
    return bad


class Scenarios(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(h), [])

    def test_coverage(self):
        names = {r['name'] for r in fx.ROWS}
        for need in ('ONE_ROBOT_TRADE_OPENED_AND_CLOSED_TODAY', 'PARTIAL_EXIT_80_PERCENT_POSITION_STILL_OPEN', 'TWO_PARTIAL_EXITS_THEN_CLOSED_THREE_DEALS_ONE_POSITION',
                     'MANUAL_TRADE_IS_NOT_COUNTED', 'DUPLICATE_DEAL_TICKET_COUNTED_ONCE', 'DEPOSIT_AND_WITHDRAWAL_STAY_APART', 'FALL_BACK_DAY_IS_25_HOURS_A_DEAL_AT_22_30_UTC_IS_INSIDE',
                     'SPRING_FORWARD_DAY_IS_23_HOURS_A_DEAL_AT_22_30_UTC_IS_OUTSIDE', 'THE_FOUR_MONEY_FIELDS_STAY_SEPARATE_AND_NO_FORMULA_IS_SELECTED', 'NETTING_BLOCKS', 'API_ERROR'):
            self.assertIn(need, names)
        self.assertEqual({r['verdict'] for r in fx.ROWS}, {'READY', 'UNKNOWN', 'BLOCK'})

    def test_windows_agree_with_independent_tzdata(self):
        from datetime import datetime, timedelta, timezone
        from zoneinfo import ZoneInfo
        tz = ZoneInfo('Europe/Tirane')
        for r in fx.ROWS:
            if r['verdict'] != 'READY':
                continue
            x = r['exp']
            local = datetime.fromtimestamp(r['utc'], timezone.utc).astimezone(tz)
            mid = datetime(local.year, local.month, local.day, tzinfo=tz)
            nxt = datetime(local.year, local.month, local.day, tzinfo=tz) + timedelta(days=1)
            self.assertEqual((x['start'], x['end']), (int(mid.astimezone(timezone.utc).timestamp()), int(nxt.astimezone(timezone.utc).timestamp())), r['name'])
            self.assertEqual(x['day'], local.year * 10000 + local.month * 100 + local.day)

    def test_window_sweep_every_hour_of_two_years(self):
        from datetime import datetime, timedelta, timezone
        from zoneinfo import ZoneInfo
        tz = ZoneInfo('Europe/Tirane')
        d = datetime(2026, 1, 1, tzinfo=timezone.utc)
        while d < datetime(2028, 1, 1, tzinfo=timezone.utc):
            t = int(d.timestamp())
            day, start, end = h.day_window(t)
            local = d.astimezone(tz)
            mid = datetime(local.year, local.month, local.day, tzinfo=tz)
            nxt = datetime(local.year, local.month, local.day, tzinfo=tz) + timedelta(days=1)
            nxt_utc = int(datetime(nxt.year, nxt.month, nxt.day, tzinfo=tz).astimezone(timezone.utc).timestamp())
            self.assertEqual((start, end), (int(datetime(local.year, local.month, local.day, tzinfo=tz).astimezone(timezone.utc).timestamp()), nxt_utc), t)
            d += timedelta(hours=1)

    def test_deal_count_is_not_trade_count_and_nothing_is_classified(self):
        r = next(x for x in fx.ROWS if x['name'] == 'TWO_PARTIAL_EXITS_THEN_CLOSED_THREE_DEALS_ONE_POSITION')
        cfg, raw = make(r)
        f = h.build(cfg, raw, True).facts
        self.assertEqual((f.deals_in_window, len(f.positions)), (3, 1))
        names = {a for a in dir(f) if not a.startswith('_')}
        for word in ('win', 'loss', 'breakeven', 'trades', 'trade_count', 'result', 'balance_start'):
            self.assertFalse([n for n in names if n in ('wins', 'losses', 'breakeven', 'trades', 'trade_count', 'closed_result', 'result')], names)
        self.assertEqual(f.result_formula, 'UNSET')
        self.assertFalse(f.balance_start_known)
        hdr = _read('src', 'include', 'DailyHistory.mqh')
        for word in ('wins_today', 'consecutive_losses', 'trades_today', 'DL_Check', 'DL_WIN_STOP_AT', 'breakeven'):
            self.assertNotIn(word, re.sub(r'(?s)/\*.*?\*/|//[^\n]*', '', hdr))

    def test_balance_start_is_never_reconstructed(self):
        for r in fx.ROWS:
            if r['verdict'] == 'READY':
                cfg, raw = make(r)
                f = h.build(cfg, raw, True).facts
                self.assertFalse(f.balance_start_known)
                self.assertIn('NOT RECONSTRUCTED', f.balance_start_note)
        hdr = _read('src', 'include', 'DailyHistory.mqh')
        self.assertNotIn('ACCOUNT_BALANCE', hdr)
        self.assertNotIn('AccountInfoDouble', hdr)

    def test_unclassified_data_never_becomes_zero_or_clear(self):
        # an UNKNOWN / BLOCK verdict carries no facts at all (no zeroes that could be mistaken for a quiet day)
        for r in fx.ROWS:
            if r['verdict'] != 'READY':
                cfg, raw = make(r)
                self.assertIsNone(h.build(cfg, raw, bool(r['stable'])).facts, r['name'])

    def test_all_robot_money_goes_to_the_matrix_and_nothing_to_nontrade(self):
        r = next(x for x in fx.ROWS if x['name'] == 'DEPOSIT_DOES_NOT_ENTER_THE_ROBOT_SUMS')
        cfg, raw = make(r)
        f = h.build(cfg, raw, True).facts
        self.assertEqual(f.nontrade_profit, 5000.0)
        self.assertEqual(f.candidate_profit_commission_swap_fee, -0.5)

    def test_unstable_read_detected_by_comparing_two_reads(self):
        r = next(x for x in fx.ROWS if x['name'] == 'ONE_ROBOT_TRADE_OPENED_AND_CLOSED_TODAY')
        _, a = make(r)
        _, b = make(r)
        self.assertTrue(h.raw_equal(a, b))
        b.deals[1].profit = 12.0
        self.assertFalse(h.raw_equal(a, b))
        _, c = make(r)
        c.positions[0].is_open = True
        self.assertFalse(h.raw_equal(a, c))

    def test_no_trading_no_persistence_no_clock_and_t009_reused(self):
        src = _read('tests', 't012_history_reference.py').split('"""', 2)[2]
        self.assertIn('t009.evaluate(', src)
        for word in ('open(', 'import os', 'time.', 'zoneinfo', 'timedelta'):
            self.assertNotIn(word, src)
        hdr = _read('src', 'include', 'DailyHistory.mqh')
        for word in ('SP_Edge', 'SP_Offset', 'StructToTime', 'OrderSend', 'CTrade', 'TimeCurrent', 'TimeGMT', 'FileOpen'):
            self.assertNotIn(word, hdr)
        self.assertIn('SP_Evaluate(', hdr)
        self.assertIn('PS_GridSteps(', hdr)


class Mutants(unittest.TestCase):
    def _build(self, pairs):
        src = _read('tests', 't012_history_reference.py')
        for old, new in pairs:
            self.assertIn(old, src, 'mutation target absent (vacuous): ' + old[:50])
            src = src.replace(old, new, 1)
        ns = {'__name__': 't012_history_mutant'}
        exec(compile(src, 't012_history_mutant', 'exec'), ns)

        class M:
            pass
        m = M()
        for k, v in ns.items():
            setattr(m, k, v)
        return m

    def test_mutants_are_caught(self):
        cases = [
            ('duplicates counted', "                f.duplicates += 1\n                continue", "                f.duplicates += 1"),
            ('window end inclusive', "if not (start <= utc < end):", "if not (start <= utc <= end):"),
            ('window start exclusive', "if not (start <= utc < end):", "if not (start < utc < end):"),
            ('server offset ignored', "        utc = d.time - off", "        utc = d.time"),
            ('server offset added', "        utc = d.time - off", "        utc = d.time + off"),
            ('non-trade deals counted as robot', "        if d.type not in (DEAL_BUY, DEAL_SELL):", "        if False:"),
            ('manual trades counted', "        if p.opened_magic != cfg.ea_magic:", "        if False:"),
            ('ownership from the exit deal magic', "        if p.opened_magic != cfg.ea_magic:", "        if d.magic != cfg.ea_magic:"),
            ('manual close of a robot position not flagged', "        if cls != 'IN' and d.magic != cfg.ea_magic:", "        if False:"),
            ('unknown opening deal accepted', "        if p is None or not p.opened_known:", "        if p is None:"),
            ('netting allowed', "    if raw.margin_mode != MARGIN_HEDGING:", "    if False:"),
            ('unstable read accepted', "    if not stable:", "    if False:"),
            ('truncation ignored', "    if raw.deals_truncated or raw.pos_truncated or len(raw.deals) > MAX_DEALS or len(raw.positions) > MAX_POS:", "    if len(raw.deals) > MAX_DEALS:"),
            ('api error ignored', "    if not raw.api_ok:", "    if False:"),
            ('magic zero accepted', "cfg.ea_magic <= 0:", "cfg.ea_magic < 0:"),
            ('volume mismatch accepted', "            if closed != opened:", "            if False:"),
            ('open position covered by exits accepted', "            if closed >= opened:", "            if False:"),
            ('complete without the owner assertion', "    f.complete = bool(cfg.history_complete_asserted)", "    f.complete = True"),
            ('balance start claimed known', "    balance_start_known: bool = False", "    balance_start_known: bool = True"),
            ('a result formula selected', "RESULT_FORMULA = 'UNSET'", "RESULT_FORMULA = 'PROFIT_ONLY'"),
            ('commission folded into profit', "        c.profit += d.profit\n        c.commission += d.commission", "        c.profit += d.profit + d.commission\n        c.commission += d.commission"),
            ('fee dropped', "        c.fee += d.fee\n", "        pass\n"),
            ('nontrade money folded into the robot candidate', "    f.candidate_profit = sum(c.profit for c in cells)", "    f.candidate_profit = sum(c.profit for c in cells) + f.nontrade_profit"),
            ('offset not validated', "off % 900 != 0 or abs(off) > 50400", "False"),
        ]
        for name, old, new in cases:
            with self.subTest(name):
                m = self._build([(old, new)])
                try:
                    bad = run_rows(m)
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T012_HistoryTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
