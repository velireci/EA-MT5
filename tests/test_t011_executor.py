"""T011 executor tests (FAKE transport only): zero sends when any check / SAVE fails, exactly one send, uncertain response without retry, map not saved, partial fill,
restart after INTENT, duplicate call, DONE only from the reconciliation, mutants, and source-level separation of the real transport."""
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_executor_fixtures as fx  # noqa: E402
import t011_executor_reference as ex  # noqa: E402
import t011_flow_fixtures as ffx  # noqa: E402
import t011_flow_reference as fl  # noqa: E402
import t011_persist_reference as p  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = 'VELO_T011_EXEC_TEST.state'


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def strip_comments(t):
    return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))


def prepare(store, kind):
    if kind != fx.K_MISSING:
        ok, t = p.encode(fx.start_record(kind))
        assert ok, t
        with open(store.path(NAME), 'wb') as f:
            f.write(t.encode('latin-1'))


def disk(store):
    if not store.exists(NAME):
        return '', 0, 0
    ok, rc = p.decode(store.read(NAME))
    return (rc.state.status, rc.generation, len(rc.orders)) if ok else ('CORRUPT', 0, 0)


def run_rows(mod_ex):
    bad = []
    for r in fx.ROWS:
        with tempfile.TemporaryDirectory() as d:
            store = p.FileStore(d)
            prepare(store, r['start'])
            cfg, tr, q = fx.setup(r['tweak'], r['resp'])
            cfg.test_save_fault, cfg.test_fault_save_no = r['fault'], r['fault_no']
            res = mod_ex.process(cfg, tr, mod_ex.Runtime(), store, NAME, fx.IDENT, q)
            dk, gen, orders = disk(store)
            got = (res.final, len(tr.sends), dk, gen, orders)
            exp = (r['final'], r['sends'], r['disk'], r['gen'], r['orders'])
            if got != exp or r['reason'] not in res.reason or store.exists(NAME + '.tmp') or res.sends != len(tr.sends):
                bad.append((r['name'], got, exp, res.reason))
    return bad


class Lying(p.FileStore):
    """a store whose save claims success without writing: the independent re-load must catch it"""

    def save(self, name, rec, fault=None):
        return True, ''


def run_behaviour(mod_ex):
    """rows + the checks that the rows cannot show: the position ticket in the request, the duplicate call, the latch, a store that lies about a save"""
    bad = list(run_rows(mod_ex))
    with tempfile.TemporaryDirectory() as d:
        store = p.FileStore(d)
        prepare(store, fx.K_IDLE)
        cfg, tr, q = fx.setup(0, 0)
        rt = mod_ex.Runtime()
        a = mod_ex.process(cfg, tr, rt, store, NAME, fx.IDENT, q)
        b = mod_ex.process(cfg, tr, rt, store, NAME, fx.IDENT, q)
        if not (a.final == mod_ex.SENT_MAPPED and b.final == mod_ex.BLOCKED and len(tr.sends) == 1 and tr.sends[0].position == 9):
            bad.append(('duplicate / ticket', a.final, b.final, len(tr.sends)))
    with tempfile.TemporaryDirectory() as d:
        store = p.FileStore(d)
        prepare(store, fx.K_IDLE)
        cfg, tr, q = fx.setup(0, 0)
        cfg.test_save_fault, cfg.test_fault_save_no = mod_ex.SAVE_BEFORE, 1
        rt = mod_ex.Runtime()
        a = mod_ex.process(cfg, tr, rt, store, NAME, fx.IDENT, q)
        cfg.test_save_fault = mod_ex.SAVE_NONE
        b = mod_ex.process(cfg, tr, rt, store, NAME, fx.IDENT, q)
        if not (a.final == mod_ex.RECOVERY_REQUIRED and b.final == mod_ex.BLOCKED and not tr.sends):
            bad.append(('latch', a.final, b.final, len(tr.sends)))
    with tempfile.TemporaryDirectory() as d:
        store = Lying(d)
        prepare(store, fx.K_IDLE)
        cfg, tr, q = fx.setup(0, 0)
        a = mod_ex.process(cfg, tr, mod_ex.Runtime(), store, NAME, fx.IDENT, q)
        if not (a.final == mod_ex.RECOVERY_REQUIRED and not tr.sends and 'INTENT_NOT_VERIFIED' in a.reason):
            bad.append(('lying store', a.final, len(tr.sends), a.reason))
    return bad


class Rows(unittest.TestCase):
    def test_every_row(self):
        self.assertEqual(run_rows(ex), [])

    def test_behaviour_checks_beyond_the_rows(self):
        self.assertEqual(run_behaviour(ex), [])

    def test_the_executor_is_disabled_and_unset_by_default(self):
        c = ex.Config()
        self.assertEqual((c.enabled, c.real_authorised, c.authorisation, c.ea_magic, c.filling, c.deviation, c.filter_policy, c.tp_set),
                         (False, False, '', 0, ex.FILL_UNSET, -1, ex.POL_UNSET, False))
        with tempfile.TemporaryDirectory() as d:
            store = p.FileStore(d)
            prepare(store, fx.K_IDLE)
            _, tr, q = fx.setup(0, 0)
            res = ex.process(ex.Config(), tr, ex.Runtime(), store, NAME, fx.IDENT, q)
            self.assertEqual((res.final, len(tr.sends)), (ex.BLOCKED, 0))

    def test_zero_sends_whenever_any_check_or_save_fails(self):
        for r in fx.ROWS:
            if r['final'] in (ex.BLOCKED, ex.NOT_IDLE, ex.NO_REQUEST) or (r['final'] == ex.RECOVERY_REQUIRED and r['sends'] == 0):
                self.assertEqual(r['sends'], 0, r['name'])
        self.assertTrue(any(r['final'] == ex.RECOVERY_REQUIRED and r['sends'] == 0 for r in fx.ROWS))


class Sequences(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = p.FileStore(self.tmp.name)
        prepare(self.store, fx.K_IDLE)

    def tearDown(self):
        self.tmp.cleanup()

    def test_only_one_send_for_repeated_calls_with_the_same_or_a_new_runtime(self):
        cfg, tr, q = fx.setup(0, 0)
        rt = ex.Runtime()
        a = ex.process(cfg, tr, rt, self.store, NAME, fx.IDENT, q)
        b = ex.process(cfg, tr, rt, self.store, NAME, fx.IDENT, q)
        c = ex.process(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)      # a new instance / process
        self.assertEqual((a.final, b.final, c.final, len(tr.sends)), (ex.SENT_MAPPED, ex.BLOCKED, ex.NOT_IDLE, 1))
        self.assertIn('DUPLICATE_CALL', b.reason)

    def test_an_uncertain_response_is_never_retried_in_this_run_or_after_a_restart(self):
        cfg, tr, q = fx.setup(0, fx.RS['TIMEOUT_NO_ORDER'])
        rt = ex.Runtime()
        a = ex.process(cfg, tr, rt, self.store, NAME, fx.IDENT, q)
        b = ex.process(cfg, tr, rt, self.store, NAME, fx.IDENT, q)
        c = ex.process(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        self.assertEqual((a.final, b.final, c.final, len(tr.sends)), (ex.RECOVERY_REQUIRED, ex.BLOCKED, ex.NOT_IDLE, 1))
        # the flow reports the uncertain send and reads nothing
        res = fl.run(self.store, NAME, fx.IDENT, ffx.PROFILES[0][1])
        self.assertEqual((res.final, res.snapshot_called), (fl.RECOVERY_REQUIRED, False))
        self.assertIn('NO_MAP', res.reason)

    def test_a_save_failure_latches_this_runtime_even_if_the_old_file_is_back_to_idle(self):
        cfg, tr, q = fx.setup(0, 0)
        cfg.test_save_fault, cfg.test_fault_save_no = ex.SAVE_BEFORE, 1
        rt = ex.Runtime()
        a = ex.process(cfg, tr, rt, self.store, NAME, fx.IDENT, q)
        cfg.test_save_fault = ex.SAVE_NONE
        b = ex.process(cfg, tr, rt, self.store, NAME, fx.IDENT, q)
        self.assertEqual((a.final, b.final, len(tr.sends)), (ex.RECOVERY_REQUIRED, ex.BLOCKED, 0))
        self.assertIn('LATCHED', b.reason)

    def test_accepted_send_then_restart_flow_gives_done_only_from_the_reconciliation(self):
        cfg, tr, q = fx.setup(0, 0)
        a = ex.process(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        self.assertEqual(a.final, ex.SENT_MAPPED)
        self.assertEqual(disk(self.store)[0], 'REQUEST_PENDING')                      # a "filled" response did not make it DONE
        r1 = fl.run(self.store, NAME, fx.IDENT, ffx.PROFILES[ffx.PI['NOT_YET_IN_HISTORY']][1])
        self.assertEqual((r1.final, r1.saved), (fl.STILL_OPEN, False))
        r2 = fl.run(self.store, NAME, fx.IDENT, ffx.PROFILES[ffx.PI['FULL']][1])
        self.assertEqual((r2.final, r2.saved, r2.state.confirmations), (fl.DONE, True, 1))
        self.assertEqual(len(tr.sends), 1)

    def test_a_partial_fill_goes_to_reconciliation_not_to_done_and_never_to_a_second_send(self):
        cfg, tr, q = fx.setup(0, fx.RS['PARTIAL_10010'])
        a = ex.process(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        self.assertEqual(a.final, ex.SENT_MAPPED)
        r = fl.run(self.store, NAME, fx.IDENT, ffx.PROFILES[ffx.PI['PARTIAL_FILL_CANCELED']][1])
        self.assertEqual((r.final, r.decision, r.state.status), (fl.STILL_OPEN, 'PARTIAL', 'NEEDS_RECONCILIATION'))
        c = ex.process(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        self.assertEqual((c.final, len(tr.sends)), (ex.NOT_IDLE, 1))

    def test_the_request_carries_the_current_position_ticket_not_the_identifier_and_the_planned_volume(self):
        cfg, tr, q = fx.setup(0, 0)
        ex.process(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        req = tr.sends[0]
        self.assertEqual((req.position, req.volume, req.type, req.symbol, req.magic, req.deviation, req.filling, req.comment, req.action),
                         (9, 0.4, 1, 'XAUUSD', 777, 20, ex.FILL_IOC, 'X2R80-7', 'DEAL'))
        self.assertNotEqual(req.position, fx.IDENT.position_id)
        # SELL: closed with a buy at the ask
        cfg, tr, q = fx.setup(0, 0)
        tr.position.type, q.direction, q.level_2r, q.bid, q.ask = 1, -1, 1990.0, 1989.0, 1989.4
        cfg.tp_price = 1980.0
        with tempfile.TemporaryDirectory() as d2:
            st2 = p.FileStore(d2)
            prepare(st2, fx.K_IDLE)
            a = ex.process(cfg, tr, ex.Runtime(), st2, NAME, fx.IDENT, q)
            self.assertEqual(a.final, ex.SENT_MAPPED)
            self.assertEqual((tr.sends[0].type, tr.sends[0].price), (0, 1989.4))


class Mutants(unittest.TestCase):
    def test_mutants_are_caught(self):
        src = _read('tests', 't011_executor_reference.py')
        cases = [
            ('disabled ignored', "    if not cfg.enabled:\n        return block", "    if False:\n        return block"),
            ('filling not mandatory', "    if cfg.filling == FILL_UNSET:", "    if False:"),
            ('deviation not mandatory', "    if cfg.deviation < 0:", "    if False:"),
            ('filter policy not mandatory', "    if cfg.filter_policy == POL_UNSET:", "    if False:"),
            ('TP equals 2R allowed', "    if abs(cfg.tp_price - q.level_2r) < sym.tick_size / 2:", "    if False:"),
            ('real transport without authorisation', "        if not (cfg.real_authorised and cfg.authorisation == AUTH_PHRASE):", "        if False:"),
            ('real transport on a live account', "        if not acct.read_ok or not acct.demo:", "        if False:"),
            ('netting allowed', "    if acct.margin_mode != 2:", "    if False:"),
            ('ownership not proven', "    if pos.symbol != identity.symbol or pos.magic != cfg.ea_magic or pos.type != (0 if q.direction == 1 else 1):", "    if False:"),
            ('plan rounded instead of refused', "    if not _on_grid(q.level_2r, sym.tick_size):", "    if False:"),
            ('latch ignored', "    if rt.latched:", "    if False:"),
            ('intent save failure ignored', "    if not ok:\n        return recovery('INTENT_SAVE_FAILED", "    if False:\n        return recovery('INTENT_SAVE_FAILED"),
            ('intent not verified', "    if not (chk.verdict == p.RECOVERY_REQUIRED", "    if False and not (chk.verdict == p.RECOVERY_REQUIRED"),
            ('returned true alone is a fill proof', "    accepted = sr.returned_true and sr.have_result and sr.retcode in ACCEPT_RETCODES and sr.order > 0", "    accepted = sr.returned_true"),
            ('order ticket not required', "    accepted = sr.returned_true and sr.have_result and sr.retcode in ACCEPT_RETCODES and sr.order > 0", "    accepted = sr.returned_true and sr.have_result and sr.retcode in ACCEPT_RETCODES"),
            ('unknown retcode accepted', "sr.retcode in ACCEPT_RETCODES and sr.order > 0", "sr.order > 0"),
            ('uncertain response not recovery', "        return recovery('SEND_UNCERTAIN", "        return block('SEND_UNCERTAIN"),
            ('map save failure ignored', "    if not ok:\n        return recovery('MAP_NOT_SAVED", "    if False:\n        return recovery('MAP_NOT_SAVED"),
            ('identifier sent instead of the ticket', "pos.ticket, cfg.ea_magic", "identity.position_id, cfg.ea_magic"),
            ('precheck skipped', "    if not tr.precheck(req):", "    if False:"),
            ('not idle record still sends', "    if o.verdict != p.USABLE_IDLE:", "    if False:"),
            ('duplicate call allowed', "    if rt.send_calls >= 1:\n        return block('DUPLICATE_CALL", "    if False:\n        return block('DUPLICATE_CALL"),
            ('trading permission ignored', "    if not acct.trade_allowed:", "    if False:"),
            ('login not compared', "    if acct.login != identity.login or acct.server != identity.server:", "    if False:"),
        ]
        for name, old, new in cases:
            with self.subTest(name):
                self.assertIn(old, src, 'vacuous mutant')
                ns = {'__name__': 'exec_mutant'}
                exec(compile(src.replace(old, new, 1), 'exec_mutant', 'exec'), ns)

                class M:
                    pass
                m = M()
                for k, v in ns.items():
                    setattr(m, k, v)
                try:
                    caught = bool(run_behaviour(m))
                except Exception:
                    caught = True
                self.assertTrue(caught, 'mutant not caught: ' + name)


class Sources(unittest.TestCase):
    def test_the_real_transport_is_separate_and_never_included_by_tests_or_the_core(self):
        core = strip_comments(_read('src', 'include', 'ExitExecutor.mqh'))
        fake = strip_comments(_read('src', 'include', 'ExitTransportFake.mqh'))
        real = strip_comments(_read('src', 'include', 'ExitTransportReal.mqh'))
        test = strip_comments(_read('src', 'tests', 'T011_ExecutorTest.mq5'))
        self.assertIn('OrderSend(', real)
        self.assertEqual(real.count('OrderSend('), 1)
        for name, src in (('core', core), ('fake', fake), ('test', test)):
            for word in ('OrderSend', 'OrderSendAsync', 'CTrade', 'PositionClose', 'MqlTradeRequest', 'ExitTransportReal'):
                self.assertNotIn(word, src, name)
        self.assertIn('#include "../include/ExitTransportFake.mqh"', test)
        self.assertNotIn('OrderSendAsync', real)
        self.assertNotIn('CTrade', real)

    def test_the_core_uses_the_abstract_transport_and_one_send_call_site(self):
        core = strip_comments(_read('src', 'include', 'ExitExecutor.mqh'))
        self.assertEqual(core.count('tr.Send('), 1)
        self.assertEqual(core.count('rt.send_calls++'), 1)
        body = core[core.index('bool EX_Process('):]
        order = ['rt.latched', 'tr.ReadAccount(', 'tr.ReadSymbol(', 'tr.FindPosition(', 'ESF_Load(', 'EA_OnQuote(', 'tr.PreCheck(', 'EX_Save(', 'ESF_Load(', 'tr.Send(']
        pos, at = [], 0
        for s in order:
            at = body.index(s, at)
            pos.append(at)
        self.assertEqual(pos, sorted(pos))
        self.assertIn('EX_AUTH_PHRASE', core)

    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T011_ExecutorTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
