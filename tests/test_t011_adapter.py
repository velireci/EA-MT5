"""T011 tests: read-only snapshot adapter, pure core (no MT5, no broker, no order)."""
import copy
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_activation_reference as act  # noqa: E402
import t011_adapter_reference as ad  # noqa: E402
import t011_adapter_fixtures as fx  # noqa: E402
import t011_reconcile_reference as rec  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def make(row):
    m = ad.Map(row['map']['request_id'], row['map']['position_id'], row['map']['symbol'], list(row['map']['orders']), bool(row['map']['orders_complete']))
    w = row['raw']
    raw = ad.Raw(bool(w['api_ok']), 'terminal error', bool(w['symbol_ok']), w['vol_step'], w['vol_min'], w['vol_max'], bool(w['margin_ok']), w['margin_mode'],
                 w['n_pos'], w['pos_ticket'], w['pos_type'], w['pos_volume'], w['pos_symbol'], bool(w['hist_ok']), bool(w['truncated']),
                 [ad.RawDeal(*d) for d in row['deals']], [ad.RawOrder(*o) for o in row['orders']])
    return m, raw


def run_rows(mod_ad):
    bad = []
    for row in fx.ROWS:
        st = fx.setup(row['setup'])
        before = copy.deepcopy(st)
        m, raw = make(row)
        res = mod_ad.build(st, m, raw, bool(row['stable']))
        if st != before:
            bad.append((row['scn'], 'the adapter changed the state'))
        if res.verdict != row['verdict']:
            bad.append((row['scn'], 'verdict', res.verdict, row['verdict'], res.reason))
            continue
        if row['why'] and not res.reason.startswith(row['why']):
            bad.append((row['scn'], 'reason', res.reason))
        if res.verdict == 'READY':
            s = res.snapshot
            got = (int(res.complete), res.linked_deals, res.duplicate_deals, res.excluded_entries, res.excluded_other, ','.join(e.exec_id for e in s.executions),
                   int(s.position_found), s.volume_current, s.volume_step, int(s.position_closed_proven))
            exp = (row['complete'], row['linked'], row['dup'], row['exe'], row['exo'], row['execs'], row['found'], row['vcur'], row['vstep'], row['closed'])
            if got != exp:
                bad.append((row['scn'], 'fields', got, exp))
            o = rec.reconcile(st, s)
            if (o.decision, st.status) != (row['decision'], row['state']):
                bad.append((row['scn'], 'reconcile', o.decision, st.status, row['decision'], row['state'], o.reason))
        elif res.snapshot is not None:
            bad.append((row['scn'], 'a snapshot with a non-READY verdict'))
    return bad


class Scenarios(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(ad), [])

    def test_coverage(self):
        self.assertEqual({r['verdict'] for r in fx.ROWS}, {'READY', 'UNKNOWN', 'BLOCK'})
        self.assertEqual({r['decision'] for r in fx.ROWS if r['verdict'] == 'READY'}, {'CONFIRMED', 'PARTIAL', 'NOT_EXECUTED', 'UNKNOWN', 'BLOCK'})
        names = {r['scn'] for r in fx.ROWS}
        for need in ('BUY_FULL_ONE_DEAL_COMPLETE', 'SELL_FULL_ONE_DEAL_COMPLETE', 'BUY_DUPLICATE_DEAL_TICKET', 'BUY_TIMEOUT_THEN_LATE_FILL_THROUGH_THE_ADAPTER',
                     'NO_MAP_ORDER_TICKETS', 'NETTING_ACCOUNT_BLOCKS', 'API_ERROR', 'READ_CHANGED_BETWEEN_TWO_READS', 'POSITION_IDENTIFIER_NOT_TICKET',
                     'BUY_VOLUME_DROP_ALONE_WITH_COMPLETE_EVIDENCE_BLOCKS', 'BROKER_STEP_CHANGED_IS_PASSED_ON'):
            self.assertIn(need, names)

    def test_ticket_and_identifier_differ_in_the_base_fixture(self):
        self.assertEqual(fx.ROWS[0]['raw']['pos_ticket'], 9)
        self.assertEqual(fx.ROWS[0]['map']['position_id'], 7)

    def test_complete_only_with_all_six_proofs(self):
        base = next(r for r in fx.ROWS if r['scn'] == 'BUY_FULL_ONE_DEAL_COMPLETE')
        st = fx.setup('PEND')
        m, raw = make(base)
        res = ad.build(st, m, raw, True)
        self.assertTrue(res.complete)
        for name, mutate in (('executor assertion', lambda m, r: setattr(m, 'orders_complete', False)),
                             ('order active', lambda m, r: setattr(r.orders[0], 'where', ad.WHERE_ACTIVE)),
                             ('order missing', lambda m, r: setattr(r.orders[0], 'where', ad.WHERE_NONE)),
                             ('order not final', lambda m, r: setattr(r.orders[0], 'state', ad.ORD_PLACED)),
                             ('executed != deals', lambda m, r: setattr(r.orders[0], 'vol_current', 0.1)),
                             ('no opening deal', lambda m, r: r.deals.pop(0)),
                             ('extra mapped order unread', lambda m, r: m.orders.append(502))):
            st = fx.setup('PEND')
            m, raw = make(base)
            mutate(m, raw)
            res = ad.build(st, m, raw, True)
            self.assertEqual(res.verdict, 'READY', name)
            self.assertFalse(res.complete, name)
            self.assertIn(res.proof.split(';')[0][:3], res.proof)

    def test_margin_mode_read_zero_is_a_valid_value_and_netting_blocks(self):
        self.assertEqual(ad.mode_read(0, 0), (0, True))                 # retail netting: valid value, NOT a failure
        self.assertEqual(ad.mode_read(2, 0), (2, True))
        self.assertEqual(ad.mode_read(2, 4001), (-1, False))            # an error code, whatever the value
        self.assertEqual(ad.mode_read(0, 4001), (-1, False))
        row = next(r for r in fx.ROWS if r['scn'] == 'NETTING_ACCOUNT_BLOCKS')
        self.assertEqual((row['raw']['margin_mode'], row['raw']['margin_ok'], row['verdict'], row['why']), (0, 1, 'BLOCK', 'UNSUPPORTED_ACCOUNT_MODE'))
        hdr = _read('src', 'include', 'ExitSnapshotAdapter.mqh')
        self.assertIn('AccountInfoInteger(ACCOUNT_MARGIN_MODE);', hdr)
        self.assertNotIn('AccountInfoInteger(ACCOUNT_MARGIN_MODE,', hdr)

    def test_unstable_read_is_detected_by_comparing_two_reads(self):
        base = next(r for r in fx.ROWS if r['scn'] == 'BUY_FULL_ONE_DEAL_COMPLETE')
        _, a = make(base)
        _, b = make(base)
        self.assertTrue(ad.raw_equal(a, b))
        b.deals[1].volume = 0.3
        self.assertFalse(ad.raw_equal(a, b))
        _, c = make(base)
        c.pos_volume = 0.09
        self.assertFalse(ad.raw_equal(a, c))
        _, d = make(base)
        d.orders[0].where = ad.WHERE_ACTIVE
        self.assertFalse(ad.raw_equal(a, d))

    def test_adapter_never_writes_the_state_and_has_no_broker_vocabulary(self):
        src = _read('tests', 't011_adapter_reference.py').split('"""', 2)[2]
        self.assertIsNone(re.search(r'\bstate\.\w+ *(\+|-)?=[^=]', src), 'the adapter writes the state')
        for word in ('open(', 'import os', 'time.'):
            self.assertNotIn(word, src)
        hdr = _read('src', 'include', 'ExitSnapshotAdapter.mqh')
        self.assertIsNone(re.search(r'\bst\.\w+ *(\+\+|--|[-+]?=[^=])', hdr), 'the adapter writes the state')
        for word in ('ES_Split', 'EA_OnQuote', 'EA_OnReport', 'ER_Reconcile('):
            self.assertNotIn(word, hdr)
        self.assertIn('PS_GridSteps(', hdr)
        self.assertNotIn('DEAL_COMMENT', hdr)
        self.assertNotIn('DEAL_MAGIC', hdr)
        self.assertNotIn('POSITION_COMMENT', hdr)

    def test_request_id_is_not_matched_to_a_comment_or_magic(self):
        row = next(r for r in fx.ROWS if r['scn'] == 'BUY_BALANCE_DEAL_TYPE_IS_NOT_ATTRIBUTED_BY_MAGIC_OR_VOLUME')
        st = fx.setup('PEND')
        m, raw = make(row)
        res = ad.build(st, m, raw, True)
        self.assertEqual((res.linked_deals, res.excluded_other), (1, 1))      # same volume as ours but another order: not counted


class Mutants(unittest.TestCase):
    def _build(self, pairs):
        src = _read('tests', 't011_adapter_reference.py')
        for old, new in pairs:
            self.assertIn(old, src, 'mutation target absent (vacuous): ' + old[:50])
            src = src.replace(old, new, 1)
        ns = {'__name__': 't011_adapter_mutant'}
        exec(compile(src, 't011_adapter_mutant', 'exec'), ns)

        class M:
            pass
        m = M()
        for k, v in ns.items():
            setattr(m, k, v)
        return m

    def test_mutants_are_caught(self):
        cases = [
            ('unmapped exit deals counted', [("        if d.order not in mp.orders:\n            ex_other += 1\n            continue", "        if False:\n            continue")]),
            ('entries counted', [("        if d.entry != ENTRY_OUT:\n            ex_entry += 1\n            unsupported = True                                  # INOUT, OUT_BY or an unknown kind never proves a close\n            continue", "        if False:\n            continue")]),
            ('duplicate tickets counted', [("            if seen[d.ticket] == d:\n                dup += 1\n                continue", "            if seen[d.ticket] == d:\n                dup += 1")]),
            ('executor assertion ignored', [("    if not mp.orders_complete:\n        missing.append", "    if False:\n        missing.append")]),
            ('active order accepted', [("        if o.where != WHERE_HISTORY or o.state not in FINAL_STATES:", "        if False:")]),
            ('missing order accepted', [("        if o is None or o.where == WHERE_NONE:", "        if False:")]),
            ('executed volume not compared', [("        if e_steps < 0 or e_steps != d_steps:", "        if False:")]),
            ('opening deal not required', [("    if not has_entry_in:", "    if False:")]),
            ('netting allowed', [("    if raw.margin_mode != MARGIN_HEDGING:", "    if False:")]),
            ('unstable read accepted', [("    if not stable:", "    if False:")]),
            ('truncation ignored', [("    if raw.deals_truncated or len(raw.deals) > MAX_DEALS", "    if len(raw.deals) > MAX_DEALS")]),
            ('step copied from the state', [("[rec.Exec(str(d.ticket), state.request_id, d.volume) for d in linked], complete, closed)", "[rec.Exec(str(d.ticket), state.request_id, d.volume) for d in linked], complete, closed)"),
                                           ("snap = rec.Snapshot(found, mp.position_id, state.request_id, raw.vol_step,", "snap = rec.Snapshot(found, mp.position_id, state.request_id, state.volume_step,")]),
            ('empty order map accepted', [("    if not isinstance(mp.orders, list) or len(mp.orders) == 0:", "    if False:")]),
            ('order of another position accepted', [("        if e_steps != 0 and o.position_id != mp.position_id:", "        if False:")]),
            ('direction ignored', [("        if raw.pos_type != want:", "        if False:")]),
            ('exit deal side ignored', [("        if d.type not in (DEAL_BUY, DEAL_SELL) or d.type != wrong:", "        if False:")]),
            ('ambiguous position accepted', [("    if raw.n_pos > 1:", "    if False:")]),
            ('api error ignored', [("    if not raw.api_ok:", "    if False:")]),
            ('history error ignored', [("    if not raw.hist_ok:", "    if False:")]),
            ('map request mismatch ignored', [("    if mp.request_id != state.request_id:", "    if False:")]),
            ('capacity of a snapshot truncated', [("    if len(linked) > rec.MAX_EXEC:", "    linked = linked[:rec.MAX_EXEC]\n    if False:")]),
            ('blocked state ignored', [("    if state.status == act.BLOCKED:", "    if False:")]),
            ('closed: INOUT / OUT_BY / unknown entry ignored', [("            unsupported = True                                  # INOUT, OUT_BY", "            pass                                                # INOUT, OUT_BY")]),
            ('closed: opening volume not compared with the stored initial volume', [("in_steps == state.initial_steps", "True")]),
            ('closed: exit total not compared with the opening volume', [("\n              and out_steps == in_steps)", ")")]),
            ('closed: unmapped exit deals not counted', [("        k_out = t006._grid_steps(d.volume, raw.vol_step) if t006._num(d.volume) and d.volume > 0 else -1\n        if k_out <= 0:\n            unsupported = True\n        else:\n            out_steps += k_out\n        if d.order not in mp.orders:", "        if d.order not in mp.orders:")]),
            ('closed: incomplete evidence accepted', [("closed = (not found and complete and not unsupported", "closed = (not found and not unsupported")]),
            ('closed: an open position accepted', [("closed = (not found and complete", "closed = (complete")]),
            ('closed: opening deal side ignored', [("if d.type != want_in or k <= 0:", "if k <= 0:")]),
            ('closed: broker step vs request step ignored', [(" and raw.vol_step == state.volume_step", "")]),
            ('closed: identical duplicate deals counted twice', [("                dup += 1\n                continue", "                dup += 1")]),
            ('closed: off-grid volume accepted', [("            if d.type != want_in or k <= 0:", "            if d.type != want_in or False:"), ("        if k_out <= 0:\n            unsupported = True", "        if False:\n            unsupported = True")]),
        ]
        for name, pairs in cases:
            with self.subTest(name):
                m = self._build(pairs)
                try:
                    bad = run_rows(m)
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


class MqlBlock(unittest.TestCase):
    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T011_AdapterTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
