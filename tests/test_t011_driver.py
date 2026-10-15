"""T011 tick-driver tests (Part 14, FAKE transport only): recovery before activation, one lock for init / tick / timer / registration, no EX_Process for a record that needs reconciliation,
no registration at init, no I/O below the level, disabled by default."""
import copy
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_adapter_reference as ad  # noqa: E402
import t011_driver_reference as dr  # noqa: E402
import t011_executor_reference as ex  # noqa: E402
import t011_flow_reference as fl  # noqa: E402
import t011_geom_fixtures as gx  # noqa: E402
import t011_persist_reference as p  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = 'VELO_T011_DRIVERTEST.state'
KEY = dr.lock_key(gx.IDENT)


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


class Locks:
    def __init__(self):
        self.held = set()
        self.acquires = 0

    def acquire(self, k):
        self.acquires += 1
        if k in self.held:
            return False
        self.held.add(k)
        return True

    def release(self, k):
        self.held.discard(k)


def IN_B():
    return ad.RawDeal(100, 400, 7, ad.ENTRY_IN, ad.DEAL_BUY, 0.5)


def OUT(ticket, order, vol):
    return ad.RawDeal(ticket, order, 7, ad.ENTRY_OUT, ad.DEAL_SELL, vol)


FILLED = ad.RawOrder(501, ad.WHERE_HISTORY, ad.ORD_FILLED, 0.4, 0.0, 7)
RAW_FULL = ad.Raw(deals=[IN_B(), OUT(1001, 501, 0.4)], orders=[FILLED], pos_volume=0.1)
RAW_CLOSED = ad.Raw(deals=[IN_B(), OUT(1001, 501, 0.4), OUT(1005, 900, 0.1)], orders=[FILLED], n_pos=0, pos_volume=0.0)
RAW_NOT_YET = ad.Raw(deals=[IN_B()], orders=[ad.RawOrder(501, ad.WHERE_NONE, 0, 0.0, 0.0, 0)], pos_volume=0.5)


class World:
    def __init__(self, start=gx.S_GEOM, side=1, sets=None):
        self.dir = tempfile.TemporaryDirectory()
        self.store = p.FileStore(self.dir.name)
        txt = gx.start_text(start, side)
        if txt is not None:
            with open(self.store.path(NAME), 'wb') as f:
                f.write(txt.encode('latin-1'))
        self.cfg, self.tr, self.q, self.rt = gx.world(side, sets or {})
        self.locks = Locks()
        self.s = dr.State()

    def init(self, raw_a=None, raw_b=None):
        return dr.init(self.cfg, self.tr, self.store, NAME, gx.IDENT, raw_a or RAW_NOT_YET, raw_b or raw_a or RAW_NOT_YET, self.s, self.locks)

    def tick(self, bid=None, ask=None):
        if bid is not None:
            self.q.bid = bid
        if ask is not None:
            self.q.ask = ask
        return dr.tick(self.cfg, self.tr, self.rt, self.store, NAME, gx.IDENT, self.q, self.s, self.locks)

    def disk(self):
        ok, rec = p.decode(self.store.read(NAME)) if self.store.exists(NAME) else (False, None)
        return (rec.state.status, rec.generation) if ok else ('MISSING', 0)

    def close(self):
        self.dir.cleanup()


class Driver(unittest.TestCase):
    def test_init_arms_an_idle_r_geom_record_and_reads_nothing_else(self):
        w = World()
        armed, flow = w.init()
        self.assertEqual((armed, flow, w.s.armed, w.s.level, w.s.direction), (True, None, True, 2010.0, 1))
        self.assertEqual((w.disk(), len(w.tr.sends), w.locks.held), (('IDLE', 1), 0, set()))
        w.close()

    def test_init_never_registers_or_creates_a_file(self):
        w = World(start=gx.S_MISSING)
        armed, _ = w.init()
        self.assertFalse(armed)
        self.assertIn('INIT_LOAD_UNUSABLE', w.s.reason)
        self.assertFalse(w.store.exists(NAME))
        self.assertEqual(w.tick(bid=2010.0).final, ex.BLOCKED)
        self.assertEqual((len(w.tr.sends), w.store.exists(NAME)), (0, False))
        w.close()

    def test_init_with_an_old_version_file_leaves_it_untouched(self):
        w = World(start=gx.S_OLD_V2)
        before = w.store.read(NAME)
        self.assertFalse(w.init()[0])
        self.assertEqual(w.store.read(NAME), before)
        self.assertEqual(w.tick(bid=2010.0).final, ex.BLOCKED)
        self.assertEqual(len(w.tr.sends), 0)
        w.close()

    def test_a_typed_diagnostic_record_never_arms_the_tick_path(self):
        w = World(start=gx.S_TYPED)
        self.assertFalse(w.init()[0])
        self.assertIn('INIT_PLAN_NOT_R_GEOM', w.s.reason)
        w.close()

    def test_disabled_by_default_nothing_is_locked_or_read(self):
        w = World(sets={'cfg.enabled': 0})
        self.assertFalse(w.init()[0])
        self.assertEqual(w.locks.acquires, 0)
        self.assertIn('INIT_DISABLED', w.s.reason)
        w.close()

    def test_recovery_runs_before_activation_and_a_request_bearing_record_never_arms(self):
        for start, raw, final in ((gx.S_PEND_MAP, RAW_FULL, fl.DONE), (gx.S_PEND_MAP, RAW_NOT_YET, fl.STILL_OPEN)):
            w = World(start=start)
            armed, flow = w.init(raw)
            self.assertFalse(armed)
            self.assertEqual(flow.final, final)
            self.assertEqual(w.s.reconcile_due, final == fl.STILL_OPEN)
            for bid in (2009.0, 2010.0, 2050.0):
                self.assertEqual(w.tick(bid=bid).final in (ex.BLOCKED,), True)
            self.assertEqual((len(w.tr.sends), w.s.process_calls), (0, 0))
            w.close()

    def test_a_finished_position_after_done_is_already_done_and_unchanged(self):
        w = World(start=gx.S_PEND_MAP)
        w.init(RAW_FULL)                                           # DONE saved
        gen = w.disk()
        armed, flow = w.init(RAW_CLOSED)                           # position later closed by hand: restart
        self.assertFalse(armed)
        self.assertEqual((flow.final, flow.decision, w.disk()), (fl.DONE, 'CONFIRMED', gen))
        w.close()

    def test_an_uncertain_send_record_never_arms_and_sends_nothing(self):
        w = World(start=gx.S_PEND_MAP)
        # the INTENT without a map: the flow reports NO_MAP / RECOVERY_REQUIRED
        ok, rec = p.decode(w.store.read(NAME))
        rec = p.Record(2, rec.identity, rec.state, p.SEND_INTENT, False, [], rec.plan_set, rec.plan_tp, rec.plan_vol_min, rec.plan_vol_step, rec.plan_vol_max, rec.plan_rpol,
                       rec.plan_e_src, rec.plan_s_src, rec.plan_e_out, rec.plan_s_out)
        ok, txt = p.encode(rec)
        with open(w.store.path(NAME), 'wb') as f:
            f.write(txt.encode('latin-1'))
        armed, flow = w.init(RAW_FULL)
        self.assertEqual((armed, flow.final, w.s.reconcile_due), (False, fl.RECOVERY_REQUIRED, False))
        self.assertEqual(len(w.tr.sends), 0)
        w.close()

    def test_lock_failure_at_init_arms_nothing_and_reads_nothing(self):
        w = World()
        w.locks.held.add(KEY)
        armed, _ = w.init()
        self.assertEqual((armed, w.s.lock_failures, w.s.armed), (False, 1, False))
        self.assertIn('INIT_LOCK_FAILED', w.s.reason)
        self.assertEqual((w.disk(), len(w.tr.sends)), (('IDLE', 1), 0))
        w.close()

    def test_below_the_level_there_is_no_lock_no_file_and_no_executor_call(self):
        for side, below, level in ((1, dict(bid=2009.99), 2010.0), (-1, dict(ask=1990.01), 1990.0)):
            w = World(side=side)
            w.init()
            n = w.locks.acquires
            res = w.tick(**below)
            self.assertEqual((res.final, w.locks.acquires, w.s.process_calls, len(w.tr.sends)), (ex.NO_REQUEST, n, 0, 0))
            w.close()

    def test_buy_bid_and_sell_ask_at_the_level_send_once_and_disarm(self):
        for side, kw in ((1, dict(bid=2010.0, ask=2010.3)), (-1, dict(bid=1989.7, ask=1990.0))):
            w = World(side=side)
            w.init()
            res = w.tick(**kw)
            self.assertEqual((res.final, len(w.tr.sends), w.s.armed, w.s.reconcile_due, w.locks.held), (ex.SENT_MAPPED, 1, False, True, set()))
            self.assertEqual(w.disk()[0], 'REQUEST_PENDING')
            for _ in range(3):                                       # more ticks above the level: nothing more
                self.assertEqual(w.tick(**kw).final, ex.BLOCKED)
            self.assertEqual((len(w.tr.sends), w.s.process_calls), (1, 1))
            w.close()

    def test_the_other_side_of_the_quote_does_not_arm_the_level(self):
        w = World(side=1)
        w.init()
        self.assertEqual(w.tick(bid=2009.9, ask=2010.1).final, ex.NO_REQUEST)       # a BUY needs the BID
        w.close()
        w = World(side=-1)
        w.init()
        self.assertEqual(w.tick(bid=1989.9, ask=1990.1).final, ex.NO_REQUEST)       # a SELL needs the ASK
        w.close()

    def test_a_lock_held_elsewhere_gives_zero_sends_and_keeps_the_tick_path_armed(self):
        w = World()
        w.init()
        w.locks.held.add(KEY)
        res = w.tick(bid=2010.0)
        self.assertEqual((res.final, len(w.tr.sends), w.s.armed, w.s.lock_failures, w.s.process_calls), (ex.BLOCKED, 0, True, 1, 0))
        self.assertIn('TICK_LOCK_FAILED', res.reason)
        w.locks.held.discard(KEY)
        self.assertEqual(w.tick(bid=2010.0).final, ex.SENT_MAPPED)
        w.close()

    def test_a_record_that_changed_under_the_driver_is_not_given_to_the_executor(self):
        w = World()
        w.init()
        ok, txt = p.encode(gx.geom_record(1, phase=p.SEND_MAPPED))          # another writer: the record now needs reconciliation
        with open(w.store.path(NAME), 'wb') as f:
            f.write(txt.encode('latin-1'))
        res = w.tick(bid=2010.0)
        self.assertEqual((res.final, w.s.armed, w.s.process_calls, len(w.tr.sends)), (ex.BLOCKED, False, 0, 0))
        w.close()

    def test_the_level_survives_a_live_sl_moved_to_break_even_after_arming(self):
        w = World()
        w.init()
        w.tr.position.sl = 2000.0
        self.assertEqual(w.tick(bid=2009.0).final, ex.NO_REQUEST)
        self.assertEqual(w.tick(bid=2010.0).final, ex.SENT_MAPPED)
        self.assertEqual(w.tr.sends[0].price, 2010.0)
        w.close()

    def test_restart_between_ticks_reconciles_first_and_sends_nothing_more(self):
        w = World()
        w.init()
        self.assertEqual(w.tick(bid=2010.0).final, ex.SENT_MAPPED)
        w.s = dr.State()                                                    # EA restart: a new driver state, the same disk
        w.rt = ex.Runtime()
        armed, flow = w.init(RAW_FULL)
        self.assertEqual((armed, flow.final), (False, fl.DONE))
        self.assertEqual(w.tick(bid=2050.0).final, ex.BLOCKED)
        self.assertEqual(len(w.tr.sends), 1)
        w.close()

    def test_timer_reconciles_under_the_lock_and_never_produces_a_request(self):
        w = World()
        w.init()
        w.tick(bid=2010.0)
        self.assertEqual(dr.timer(w.store, NAME, gx.IDENT, RAW_NOT_YET, RAW_NOT_YET, w.s, w.locks).final, fl.STILL_OPEN)
        self.assertTrue(w.s.reconcile_due)
        w.locks.held.add(KEY)
        self.assertIsNone(dr.timer(w.store, NAME, gx.IDENT, RAW_FULL, RAW_FULL, w.s, w.locks))
        self.assertTrue(w.s.reconcile_due)
        w.locks.held.discard(KEY)
        flow = dr.timer(w.store, NAME, gx.IDENT, RAW_FULL, RAW_FULL, w.s, w.locks)
        self.assertEqual((flow.final, w.s.reconcile_due, w.locks.held, len(w.tr.sends), flow.request_produced), (fl.DONE, False, set(), 1, False))
        n = w.locks.acquires
        self.assertIsNone(dr.timer(w.store, NAME, gx.IDENT, RAW_FULL, RAW_FULL, w.s, w.locks))      # nothing due: no lock
        self.assertEqual(w.locks.acquires, n)
        w.close()

    def test_registration_is_explicit_locked_and_released(self):
        w = World(start=gx.S_MISSING)
        w.locks.held.add(KEY)
        res = dr.register(w.cfg, w.tr, w.rt, w.store, NAME, gx.IDENT, w.q, w.locks)
        self.assertEqual((res.final, w.store.exists(NAME)), (ex.BLOCKED, False))
        w.locks.held.discard(KEY)
        res = dr.register(w.cfg, w.tr, w.rt, w.store, NAME, gx.IDENT, w.q, w.locks)
        self.assertEqual((res.final, w.locks.held, w.disk()), (ex.REGISTERED, set(), ('IDLE', 1)))
        w.close()

    def test_the_executor_refusals_stay_blocks_and_keep_the_driver_armed(self):
        w = World(sets={'pos.magic': 0})
        w.init()
        res = w.tick(bid=2010.0)
        self.assertEqual((res.final, len(w.tr.sends), w.s.armed), (ex.BLOCKED, 0, True))
        self.assertIn('OWNERSHIP_NOT_PROVEN', res.reason)
        w.close()

    def test_every_path_releases_the_lock(self):
        for fn in (lambda w: w.init(), lambda w: (w.init(), w.tick(bid=2010.0)), lambda w: (w.init(), w.tick(bid=1.0)), lambda w: (w.init(), w.tick(bid=2010.0), dr.timer(w.store, NAME, gx.IDENT, RAW_FULL, RAW_FULL, w.s, w.locks))):
            w = World()
            fn(w)
            self.assertEqual(w.locks.held, set())
            w.close()


class Sources(unittest.TestCase):
    def strip(self, t):
        return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))

    def test_the_driver_has_no_trading_call_no_file_access_no_state_machine_and_no_registration_at_init(self):
        d = self.strip(_read('src', 'include', 'ExitTickDriver.mqh'))
        for word in ('OrderSend', 'OrderCheck', 'tr.Send', 'FileOpen', 'FileDelete', 'FileMove', 'ESF_Save', 'ESF_InitFresh', 'GlobalVariableDel', 'EA_OnQuote', 'EX_Register(', 'Sleep', 'ExitTransportReal'):
            if word == 'EX_Register(':
                init = d[d.index('bool ETD_Init('):d.index('bool ETD_Tick(')]
                self.assertNotIn(word, init)
                tick = d[d.index('bool ETD_Tick('):d.index('bool ETD_Timer(')]
                self.assertNotIn(word, tick)
                continue
            self.assertNotIn(word, d)
        for fnn, nxt in (('bool ETD_Init(', 'bool ETD_Tick('), ('bool ETD_Tick(', 'bool ETD_Timer('), ('bool ETD_Timer(', '#endif'), ('bool ETD_Register(', 'bool ETD_Init(')):
            body = d[d.index(fnn):d.index(nxt)]
            self.assertIn('EL_Acquire(', body)
            self.assertGreaterEqual(body.count('EL_Release('), 1)
            self.assertLess(body.index('EL_Acquire('), body.index('ESF_Load(') if 'ESF_Load(' in body else body.index('EX_'))
        tick = d[d.index('bool ETD_Tick('):d.index('bool ETD_Timer(')]
        self.assertLess(tick.index('ESF_Load('), tick.index('EX_Process('))
        self.assertLess(tick.index('ESC_USABLE_IDLE'), tick.index('EX_Process('))
        self.assertLess(tick.index('s.direction==1 ?'), tick.index('EL_Acquire('))
        init = d[d.index('bool ETD_Init('):d.index('bool ETD_Tick(')]
        self.assertLess(init.index('EX_Reconcile('), init.index('s.armed=true;'))
        self.assertLess(init.index('if(!cfg.enabled)'), init.index('EL_Acquire('))
        self.assertNotIn('EX_Process', init)

    def test_the_python_reference_mirrors_the_header_order(self):
        src = _read('tests', 't011_driver_reference.py')
        self.assertLess(src.index('flow = fl.run('), src.index('s.armed, s.direction, s.level, s.reason = True'))
        tick = src[src.index('def tick('):src.index('def timer(')]
        self.assertLess(tick.index('o = store.load('), tick.index('ex.process('))


class Mutants(unittest.TestCase):
    def _build(self, pairs):
        src = _read('tests', 't011_driver_reference.py')
        for old, new in pairs:
            self.assertIn(old, src, 'vacuous: ' + old[:50])
            src = src.replace(old, new, 1)
        ns = {'__name__': 't011_driver_mutant'}
        exec(compile(src, 't011_driver_mutant', 'exec'), ns)

        class M:
            pass
        m = M()
        for k, v in ns.items():
            setattr(m, k, v)
        return m

    def run_all(self, m):
        """the whole behaviour battery against a (mutated) driver module; returns the list of failures"""
        saved = dr.__dict__.copy()
        bad = []
        try:
            for k in ('init', 'tick', 'timer', 'register'):
                setattr(dr, k, getattr(m, k))
            suite = unittest.TestSuite()
            suite.addTests(unittest.defaultTestLoader.loadTestsFromTestCase(Driver))
            r = unittest.TestResult()
            suite.run(r)
            bad = r.failures + r.errors
        finally:
            dr.__dict__.update(saved)
        return bad

    def test_mutants_are_caught(self):
        cases = [
            ('no prefilter side check for a SELL', [("(not q.bid >= s.level) if s.direction == 1 else (not q.ask <= s.level)", "(not q.bid >= s.level)")]),
            ('BUY compares the ask', [("(not q.bid >= s.level) if s.direction == 1", "(not q.ask >= s.level) if s.direction == 1")]),
            ('strict comparison at the level', [("(not q.bid >= s.level) if s.direction == 1 else (not q.ask <= s.level)", "(not q.bid > s.level) if s.direction == 1 else (not q.ask < s.level)")]),
            ('tick without the lock', [("    key = lock_key(identity)\n    if not locks.acquire(key):\n        s.lock_failures += 1\n        return ex.Result(ex.BLOCKED, 'TICK_LOCK_FAILED: zero sends')", "    key = lock_key(identity)\n    locks.acquire(key)")]),
            ('init without the lock', [("    if not locks.acquire(key):\n        s.lock_failures += 1\n        s.reason = 'INIT_LOCK_FAILED: nothing is read, nothing can be sent'\n        return False, None", "    locks.acquire(key)")]),
            ('timer without the lock', [("    if not locks.acquire(key):\n        s.lock_failures += 1\n        s.reason = 'TIMER_LOCK_FAILED'\n        return None", "    locks.acquire(key)")]),
            ('executor called for a record that is not idle', [("        if o.generation == 0 or o.verdict != p.USABLE_IDLE:\n            s.armed = False", "        if False:\n            s.armed = False")]),
            ('request-bearing record arms the tick path', [("        if o.verdict != p.USABLE_IDLE:\n            flow = fl.run(", "        if False:\n            flow = fl.run(")]),
            ('recovery skipped', [("            flow = fl.run(store, name, identity, raw_a, raw_b)       # RECOVERY BEFORE ACTIVATION; never arms the tick path", "            flow = fl.FlowResult(fl.STILL_OPEN)")]),
            ('typed record arms', [("if not o.plan_set or o.plan_rpol != ex.RPOL_R_GEOM or cfg.r_policy != ex.RPOL_R_GEOM:", "if not o.plan_set:")]),
            ('disabled arms', [("    if not cfg.enabled:\n        s.reason = 'INIT_DISABLED", "    if False:\n        s.reason = 'INIT_DISABLED")]),
            ('still armed after a send', [("            s.armed, s.reconcile_due, s.reason = False, True, 'SENT: reconcile on the timer'", "            s.armed, s.reconcile_due, s.reason = True, True, 'SENT: reconcile on the timer'")]),
            ('lock not released after the tick', [("    finally:\n        locks.release(key)\n\n\ndef timer", "    finally:\n        pass\n\n\ndef timer")]),
            ('lock not released after init', [("            return False, None\n        s.armed, s.direction, s.level, s.reason = True, o.state.direction, o.state.level, 'ARMED'\n        return True, None\n    finally:\n        locks.release(key)", "            return False, None\n        s.armed, s.direction, s.level, s.reason = True, o.state.direction, o.state.level, 'ARMED'\n        return True, None\n    finally:\n        pass")]),
            ('timer reconciles when nothing is due', [("    if not s.reconcile_due:\n        return None", "    if False:\n        return None")]),
            ('registration without the lock', [("    key = lock_key(identity)\n    if not locks.acquire(key):\n        return ex.Result(ex.BLOCKED, 'INSTANCE_LOCK_HELD: zero sends')", "    key = lock_key(identity)\n    locks.acquire(key)")]),
        ]
        for name, pairs in cases:
            with self.subTest(name):
                m = self._build(pairs)
                try:
                    bad = self.run_all(m)
                except Exception:
                    bad = ['exception']
                self.assertTrue(bad, 'mutant not caught: ' + name)


if __name__ == '__main__':
    unittest.main()
