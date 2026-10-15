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


def prepare(store, kind, inputs=None):
    t = fx.start_text(kind, inputs)
    if t is not None:
        with open(store.path(NAME), 'wb') as f:
            f.write(t.encode('latin-1'))


def disk(store):
    if not store.exists(NAME):
        return '', 0, 0, 0
    ok, rc = p.decode(store.read(NAME))
    return (rc.state.status, rc.generation, len(rc.orders), int(rc.plan_set)) if ok else ('CORRUPT', 0, 0, 0)


def run_rows(mod_ex):
    bad = []
    for r in fx.ROWS:
        with tempfile.TemporaryDirectory() as d:
            store = p.FileStore(d)
            cfg, tr, q = fx.setup(r['tweak'], r['resp'])
            prepare(store, r['start'], None if fx.uses_default_plan(r['tweak']) else (cfg, tr, q))
            if r['fault']:
                cfg.test_save_fault, cfg.test_fault_save_no = r['fault'], r['fault_no']
            res = (mod_ex.register if r['reg'] else mod_ex.process)(cfg, tr, mod_ex.Runtime(), store, NAME, fx.IDENT, q)
            dk, gen, orders, plan = disk(store)
            got = (res.final, len(tr.sends), dk, gen, orders, plan)
            exp = (r['final'], r['sends'], r['disk'], r['gen'], r['orders'], r['plan'])
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
    for case in Grid.CASES:
        if len(case) == 3 and mod_ex._on_grid(case[0], case[1]) != case[2]:
            bad.append(('grid', case))
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
        store = p.FileStore(d)
        cfg, tr, q = fx.setup(0, 0)
        tr.position.magic = 0
        r1 = mod_ex.register(cfg, tr, mod_ex.Runtime(), store, NAME, fx.IDENT, q)
        cfg, tr, q = fx.setup(0, 0)
        r2 = mod_ex.register(cfg, tr, mod_ex.Runtime(), store, NAME, fx.IDENT, q)
        r3 = mod_ex.register(cfg, tr, mod_ex.Runtime(), store, NAME, fx.IDENT, q)
        c2, t2, q2 = fx.setup(0, 0)
        q2.level_2r, q2.bid, q2.ask = 2000.5, 2000.5, 2000.8
        n = mod_ex.process(c2, t2, mod_ex.Runtime(), store, NAME, fx.IDENT, q2)
        if not (r1.final == mod_ex.BLOCKED and r2.final == mod_ex.REGISTERED and r3.final == mod_ex.BLOCKED and n.final == mod_ex.BLOCKED and not t2.sends):
            bad.append(('registration / plan', r1.final, r2.final, r3.final, n.final))
    with tempfile.TemporaryDirectory() as d:
        store = Lying(d)
        prepare(store, fx.K_IDLE)
        cfg, tr, q = fx.setup(0, 0)
        a = mod_ex.process(cfg, tr, mod_ex.Runtime(), store, NAME, fx.IDENT, q)
        if not (a.final == mod_ex.RECOVERY_REQUIRED and not tr.sends and 'INTENT_NOT_VERIFIED' in a.reason):
            bad.append(('lying store', a.final, len(tr.sends), a.reason))
    return bad


class Grid(unittest.TestCase):
    CASES = [(4000.004, 0.01, False), (2010.004, 0.01, False), (2000.005, 0.01, False), (4000.0, 0.01, True), (2000.1, 0.01, True), (3999.9100000000003, 0.01, True), (0.1 + 0.2, 0.1, True),
             (float('nan'), 0.01, False), (float('inf'), 0.01, False), (-1.0, 0.01, False), (0.0, 0.01, False), (1.0, 0.0, False), (1.0, float('nan')), (1.0, -0.01, False), (1e300, 0.01, False)]

    def test_grid_tolerance_is_floating_point_noise_only(self):
        for case in self.CASES:
            if len(case) == 3:
                self.assertEqual(ex._on_grid(case[0], case[1]), case[2], case)
        self.assertFalse(ex._on_grid(1.0, float('nan')))
        # every real offset of at least 1/1000 of a tick is refused, at several price levels and ticks
        for tick in (0.01, 0.1, 0.00001, 0.5):
            for base in (100.0, 2000.0, 4000.0, 100000.0):
                k = round(base / tick)
                for frac in (0.001, 0.01, 0.25, 0.4, 0.5):
                    self.assertFalse(ex._on_grid(k * tick + frac * tick, tick), (tick, base, frac))
                self.assertTrue(ex._on_grid(k * tick, tick), (tick, base))

    def test_unknown_enum_values_are_blocked_whatever_their_value(self):
        for field, vals in (('filling', (-1, 4, 99)), ('filter_policy', (-1, 3, 99)), ('filter_state', (-1, 3, 99)), ('test_save_fault', (-1, 3, 99))):
            for v in vals:
                with tempfile.TemporaryDirectory() as d:
                    store = p.FileStore(d)
                    prepare(store, fx.K_IDLE)
                    cfg, tr, q = fx.setup(0, 0)
                    setattr(cfg, field, v)
                    res = ex.process(cfg, tr, ex.Runtime(), store, NAME, fx.IDENT, q)
                    self.assertEqual((res.final, len(tr.sends), disk(store)[:2]), (ex.BLOCKED, 0, ('IDLE', 1)), (field, v))
                    self.assertIn('INVALID_INPUT', res.reason)
        for bad in (0, 2, -2, 99):
            with tempfile.TemporaryDirectory() as d:
                store = p.FileStore(d)
                prepare(store, fx.K_IDLE)
                cfg, tr, q = fx.setup(0, 0)
                q.direction = bad
                res = ex.process(cfg, tr, ex.Runtime(), store, NAME, fx.IDENT, q)
                self.assertEqual((res.final, len(tr.sends)), (ex.BLOCKED, 0), bad)


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
            prepare(st2, fx.K_IDLE, (cfg, tr, q))
            a = ex.process(cfg, tr, ex.Runtime(), st2, NAME, fx.IDENT, q)
            self.assertEqual(a.final, ex.SENT_MAPPED)
            self.assertEqual((tr.sends[0].type, tr.sends[0].price), (0, 1989.4))


class Registration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = p.FileStore(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_register_then_restart_before_2r_then_the_unchanged_flow_sends_once(self):
        cfg, tr, q = fx.setup(0, 0)
        r = ex.register(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        self.assertEqual((r.final, len(tr.sends), disk(self.store)), (ex.REGISTERED, 0, ('IDLE', 1, 0, 1)))
        # "restart" before 2R: a new runtime, quotes below the level produce no request and change nothing on disk
        before = self.store.read(NAME)
        below = ex.Quote(1, 2000.0, 1999.0, 1999.3, 0.5)
        for _ in range(3):
            n = ex.process(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, below)
            self.assertEqual((n.final, len(tr.sends)), (ex.NO_REQUEST, 0))
        self.assertEqual(self.store.read(NAME), before)
        # the plan has not changed: the flow is unchanged and sends exactly once, the plan survives the INTENT and the MAP records
        a = ex.process(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        self.assertEqual((a.final, len(tr.sends), disk(self.store)), (ex.SENT_MAPPED, 1, ('REQUEST_PENDING', 3, 1, 1)))
        res = fl.run(self.store, NAME, fx.IDENT, ffx.PROFILES[ffx.PI['FULL']][1])
        self.assertEqual((res.final, res.saved), (fl.DONE, True))
        self.assertEqual(disk(self.store)[3], 1)                                  # the restart flow carries the plan over

    def test_a_plan_change_after_a_restart_before_2r_blocks_with_zero_sends(self):
        cfg, tr, q = fx.setup(0, 0)
        ex.register(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        before = self.store.read(NAME)
        for name, mut in (('level', lambda c, t, qq: setattr(qq, 'level_2r', 2000.5) or setattr(qq, 'bid', 2000.5) or setattr(qq, 'ask', 2000.8)),
                          ('tp', lambda c, t, qq: setattr(c, 'tp_price', 2020.0)), ('direction', lambda c, t, qq: (setattr(qq, 'direction', -1), setattr(t.position, 'type', 1),
                                                                                                                 setattr(c, 'tp_price', 1990.0), setattr(qq, 'bid', 1999.7), setattr(qq, 'ask', 2000.0))),
                          ('initial volume', lambda c, t, qq: (setattr(qq, 'volume_initial', 0.6), setattr(t.position, 'volume', 0.6))),
                          ('min', lambda c, t, qq: setattr(t.symbol, 'vol_min', 0.05)), ('step', lambda c, t, qq: setattr(t.symbol, 'vol_step', 0.05)),
                          ('max', lambda c, t, qq: setattr(t.symbol, 'vol_max', 10.0))):
            c2, t2, q2 = fx.setup(0, 0)
            mut(c2, t2, q2)
            n = ex.process(c2, t2, ex.Runtime(), self.store, NAME, fx.IDENT, q2)
            self.assertEqual((n.final, len(t2.sends)), (ex.BLOCKED, 0), name)
            self.assertIn('PLAN_CHANGED', n.reason, name)
            self.assertEqual(self.store.read(NAME), before, name)                 # no INTENT, nothing written

    def test_registration_never_adopts_a_manual_position_or_overwrites(self):
        cfg, tr, q = fx.setup(0, 0)
        tr.position.magic = 0
        r = ex.register(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        self.assertEqual((r.final, self.store.exists(NAME)), (ex.BLOCKED, False))
        cfg, tr, q = fx.setup(0, 0)
        self.assertEqual(ex.register(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q).final, ex.REGISTERED)
        again = ex.register(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        self.assertEqual(again.final, ex.BLOCKED)
        self.assertIn('ALREADY_EXISTS', again.reason)

    def test_without_a_file_the_executor_never_starts_from_scratch(self):
        cfg, tr, q = fx.setup(0, 0)
        n = ex.process(cfg, tr, ex.Runtime(), self.store, NAME, fx.IDENT, q)
        self.assertEqual((n.final, len(tr.sends), self.store.exists(NAME)), (ex.RECOVERY_REQUIRED, 0, False))


class Mutants(unittest.TestCase):
    def test_mutants_are_caught(self):
        src = _read('tests', 't011_executor_reference.py')
        cases = [
            ('disabled ignored', "    if not cfg.enabled:\n        return block", "    if False:\n        return block"),
            ('filling not mandatory', "    if cfg.filling == FILL_UNSET:", "    if False:"),
            ('deviation not mandatory', "    if cfg.deviation < 0:", "    if False:"),
            ('filter policy not mandatory', "    if cfg.filter_policy == POL_UNSET:", "    if False:"),
            ('TP equals 2R allowed', "    if abs(cfg.tp_price - level) < sym.tick_size / 2:", "    if False:"),
            ('real transport without authorisation', "        if not (cfg.real_authorised and cfg.authorisation == AUTH_PHRASE):", "        if False:"),
            ('real transport on a live account', "        if not acct.read_ok or not acct.demo:", "        if False:"),
            ('netting allowed', "    if acct.margin_mode != 2:", "    if False:"),
            ('ownership not proven', "    if pos.symbol != identity.symbol or pos.magic != cfg.ea_magic or pos.type != (0 if q.direction == 1 else 1):", "    if False:"),
            ('plan rounded instead of refused', "    if not _on_grid(level, sym.tick_size):", "    if False:"),
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
            ('unknown filling accepted', "    if not _int(cfg.filling) or cfg.filling not in (FILL_UNSET, FILL_FOK, FILL_IOC, FILL_RETURN):", "    if False:"),
            ('unknown filter policy accepted', "    if not _int(cfg.filter_policy) or cfg.filter_policy not in (POL_UNSET, POL_IGNORE, POL_NEEDS_CLEAR):", "    if False:"),
            ('unknown filter state accepted', "    if not _int(cfg.filter_state) or cfg.filter_state not in (FS_UNKNOWN, FS_CLEAR, FS_BLOCKED):", "    if False:"),
            ('unknown direction accepted', "    if not _int(q.direction) or q.direction not in (1, -1):", "    if False:"),
            ('wide grid tolerance', "8 * sys.float_info.epsilon * max(1.0, abs(r))", "1e-6 * max(1.0, abs(r))"),
            ('non finite price on the grid', "    if not _finite(x) or not _finite(tick) or x <= 0 or tick <= 0:\n        return False", "    if False:\n        return False"),
            ('non representable plan persisted', "    if p.fnum(level) is None or p.fnum(cfg.tp_price) is None or (volume is not None and p.fnum(volume) is None):", "    if False:"),
            ('plan not compared', "        if stored != now:", "        if False:"),
            ('missing plan filled in', "    if not o.plan_set:", "    if False:"),
            ('plan not carried into the intent record', "o.plan_set, o.plan_tp, o.plan_vol_min, o.plan_vol_step, o.plan_vol_max, o.plan_rpol, o.plan_e_src, o.plan_s_src,\n                    o.plan_e_out, o.plan_s_out)",
             ")"),
            ('registration adopts any magic', "    if pos.symbol != identity.symbol or pos.magic != cfg.ea_magic or pos.type != (0 if q.direction == 1 else 1):\n        return block('OWNERSHIP_NOT_PROVEN: a manual", "    if False:\n        return block('OWNERSHIP_NOT_PROVEN: a manual"),
            ('registration overwrites', "    if store.exists(name) or store.exists(name + '.tmp'):\n        return block('ALREADY_EXISTS", "    if False:\n        return block('ALREADY_EXISTS"),
            ('registration of a position with another volume', "    if pos.volume != q.volume_initial:", "    if False:"),
            ('registration save failure ignored', "    if not ok:\n        rt.latched = True\n        res.final, res.reason = RECOVERY_REQUIRED, 'REGISTRATION_SAVE_FAILED", "    if False:\n        rt.latched = True\n        res.final, res.reason = RECOVERY_REQUIRED, 'REGISTRATION_SAVE_FAILED"),
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

    def test_unknown_values_never_reach_the_real_request_and_the_grid_is_noise_only_in_the_mql_core(self):
        real = strip_comments(_read('src', 'include', 'ExitTransportReal.mqh'))
        core = strip_comments(_read('src', 'include', 'ExitExecutor.mqh'))
        self.assertNotRegex(real, r'else\s+r\.type_filling\s*=\s*ORDER_FILLING_RETURN')       # no default mapping to RETURN
        self.assertIn('if(req.filling==3) r.type_filling=ORDER_FILLING_RETURN;', real)
        self.assertGreaterEqual(real.count("else return(false);"), 2)
        self.assertIn('if(!Fill(req,r)) return;', real)
        self.assertIn('if(!Fill(req,r)) return(false);', real)
        self.assertLess(real.index('if(!Fill(req,r)) return;'), real.index('OrderSend('))
        self.assertIn('8.0*DBL_EPSILON*MathMax(1.0,MathAbs(r))', core)
        self.assertNotIn('1e-6*MathMax', core)
        for need in ('cfg.filling<(int)EX_FILL_UNSET', 'cfg.filter_policy>(int)EX_POL_NEEDS_CLEAR', 'cfg.filter_state>(int)EX_FS_BLOCKED', 'q.direction!=1 && q.direction!=-1', 'ESC_Fnum(level,exact)'):
            self.assertIn(need.replace('cfg.filling<(int)EX_FILL_UNSET', '(int)cfg.filling<(int)EX_FILL_UNSET').replace('cfg.filter_policy>(int)', '(int)cfg.filter_policy>(int)').replace('cfg.filter_state>(int)', '(int)cfg.filter_state>(int)'), core)
        body = core[core.index('bool EX_Process('):]
        self.assertLess(body.index('INVALID_INPUT: filling'), body.index('tr.ReadAccount('))
        self.assertIn('PLAN_NOT_REPRESENTABLE_IN_RECORD', core)
        self.assertLess(body.index('EX_PlanRefusal('), body.index('EX_Save('))

    def test_fixture_block_equals_generator(self):
        txt = _read('src', 'tests', 'T011_ExecutorTest.mq5')
        m = re.search(r'// BEGIN GENERATED FIXTURES.*?// END GENERATED FIXTURES', txt, re.S)
        self.assertIsNotNone(m)
        self.assertEqual(m.group(0), fx.emit_mql())


if __name__ == '__main__':
    unittest.main()
