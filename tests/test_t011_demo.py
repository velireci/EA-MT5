"""T011 demo harness tests (FAKE transport only): disabled by default, mandatory parameters, gates, the whole pipeline once, a re-run without a second request, restart / reconciliation,
the instance lock, no deletion, presets and source-level separation of the real transport."""
import glob
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_demo_open_reference as og  # noqa: E402
import t011_demo_reference as dm  # noqa: E402
import t011_executor_fixtures as efx  # noqa: E402
import t011_executor_reference as ex  # noqa: E402
import t011_flow_fixtures as ffx  # noqa: E402
import t011_persist_reference as p  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = 'VELO_T011_DEMOTEST_A.state'
KEY = 'VELO_T011_LOCKTEST_A'


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def strip_comments(t):
    return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))


def params(step, **kw):
    prm = dm.Params(step=step, magic=777, position_id=7, symbol='XAUUSD', direction=1, level_2r=2000.0, tp_price=2010.0, volume_initial=0.5, filling=ex.FILL_IOC, deviation=20,
                    filter_policy=ex.POL_IGNORE, filter_state=ex.FS_CLEAR, file_name=NAME, lock_key=KEY)
    for k, v in kw.items():
        setattr(prm, k, v)
    return prm


QUOTE = dm.Quote(True, 2000.0, 2000.3)
FULL = ffx.PROFILES[ffx.PI['FULL']][1]
NOT_YET = ffx.PROFILES[ffx.PI['NOT_YET_IN_HISTORY']][1]


class World:
    def __init__(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.store = p.FileStore(self.tmp.name)
        self.locks = dm.Locks()
        self.tr = ex.FakeTransport()
        self.tr.response = efx.response(0)

    def run(self, step, quote=QUOTE, raw_a=None, raw_b=None, **kw):
        return dm.run(params(step, **kw), self.tr, quote, raw_a, raw_b, self.store, self.locks)

    def close(self):
        self.tmp.cleanup()


class Pipeline(unittest.TestCase):
    def setUp(self):
        self.w = World()

    def tearDown(self):
        self.w.close()

    def test_disabled_by_default_and_every_unset_parameter_blocks(self):
        ok, r = dm.run(dm.Params(), self.w.tr, QUOTE, None, None, self.w.store, self.w.locks)
        self.assertEqual((ok, r.status, self.w.store.exists(NAME), len(self.w.tr.sends)), (False, 'DISABLED', False, 0))
        reg_fields = (('magic', 0), ('symbol', ''), ('position_id', 0), ('direction', 0), ('level_2r', -1.0), ('tp_price', -1.0), ('volume_initial', 0.0))
        send_fields = reg_fields + (('filling', ex.FILL_UNSET), ('deviation', -1), ('filter_policy', ex.POL_UNSET))
        for step, fields in ((dm.REGISTER, reg_fields), (dm.ACTIVATE, send_fields)):
            for field, bad in fields:
                w = World()
                try:
                    ok, r = w.run(step, confirm_send_once=True, **{field: bad})
                    self.assertFalse(ok, (step, field))
                    self.assertEqual(len(w.tr.sends), 0, (step, field))
                    self.assertFalse(w.store.exists(NAME), (step, field))
                finally:
                    w.close()

    def test_the_whole_pipeline_once_then_a_rerun_without_a_second_request_and_a_restart(self):
        w = self.w
        ok, r = w.run(dm.STATUS)
        self.assertEqual((ok, r.status, w.store.exists(NAME)), (True, 'STATUS', False))                     # status is read-only: no file appears
        self.assertIn('MISSING', r.detail)
        ok, r = w.run(dm.ACTIVATE, confirm_send_once=True)                                                    # no registration, no file: never starts from scratch
        self.assertEqual((ok, r.status, len(w.tr.sends)), (False, 'RECOVERY_REQUIRED', 0))
        ok, r = w.run(dm.REGISTER)
        self.assertEqual((ok, r.status, len(w.tr.sends)), (True, 'REGISTERED', 0))
        ok, r = w.run(dm.ACTIVATE)                                                                            # without confirm_send_once
        self.assertEqual((ok, r.status, len(w.tr.sends)), (False, 'BLOCKED', 0))
        ok, r = w.run(dm.ACTIVATE, quote=dm.Quote(False, 0.0, 0.0), confirm_send_once=True)
        self.assertEqual((ok, r.status, len(w.tr.sends)), (False, 'BLOCKED', 0))
        ok, r = w.run(dm.ACTIVATE, quote=dm.Quote(True, 1999.0, 1999.3), confirm_send_once=True)             # level not reached
        self.assertEqual((r.status, len(w.tr.sends)), ('NO_REQUEST', 0))
        ok, r = w.run(dm.ACTIVATE, confirm_send_once=True)
        self.assertEqual((ok, r.status, r.sends, len(w.tr.sends)), (True, 'SENT_MAPPED', 1, 1))
        for _ in range(3):                                                                                   # re-run / restart: no second request
            ok, r = w.run(dm.ACTIVATE, confirm_send_once=True)
            self.assertEqual((ok, r.status, len(w.tr.sends)), (False, 'NOT_IDLE', 1))
        ok, r = w.run(dm.RECONCILE, raw_a=NOT_YET, raw_b=NOT_YET)
        self.assertEqual((ok, r.status), (False, 'STILL_OPEN'))
        ok, r = w.run(dm.RECONCILE, raw_a=FULL, raw_b=FULL)
        self.assertEqual((ok, r.status), (True, 'DONE'))
        ok, r = w.run(dm.RECONCILE, raw_a=FULL, raw_b=FULL)
        self.assertEqual((ok, r.status), (True, 'DONE'))
        ok, r = w.run(dm.STATUS)
        self.assertIn('state DONE', r.detail)
        self.assertIn('confirmations 1', r.detail)
        self.assertIn('plan_set 1', r.detail)
        self.assertEqual(len(w.tr.sends), 1)
        self.assertEqual(w.locks.held, set())                                                                # every acting step released the lock

    def test_a_real_transport_needs_the_phrase_and_a_demo_account(self):
        w = self.w
        w.tr.real = True
        ok, r = w.run(dm.REGISTER)
        self.assertEqual((r.status, w.store.exists(NAME)), ('BLOCKED', False))
        self.assertIn('REAL_NOT_AUTHORISED', r.detail)
        w.tr.account.demo = False
        ok, r = w.run(dm.REGISTER, authorisation=ex.AUTH_PHRASE)
        self.assertIn('REAL_REQUIRES_DEMO_ACCOUNT', r.detail)
        w.tr.account.demo = True
        ok, r = w.run(dm.REGISTER, authorisation='wrong phrase')
        self.assertIn('REAL_NOT_AUTHORISED', r.detail)
        ok, r = w.run(dm.REGISTER, authorisation=ex.AUTH_PHRASE)
        self.assertEqual((ok, r.status), (True, 'REGISTERED'))
        ok, r = w.run(dm.ACTIVATE, authorisation=ex.AUTH_PHRASE)                                             # phrase but no confirm_send_once
        self.assertEqual((ok, len(w.tr.sends)), (False, 0))
        ok, r = w.run(dm.ACTIVATE, authorisation=ex.AUTH_PHRASE, confirm_send_once=True)
        self.assertEqual((ok, r.status, len(w.tr.sends)), (True, 'SENT_MAPPED', 1))

    def test_a_manual_position_is_never_adopted(self):
        w = self.w
        w.tr.position.magic = 0
        ok, r = w.run(dm.REGISTER)
        self.assertEqual((ok, r.status, w.store.exists(NAME)), (False, 'BLOCKED', False))
        self.assertIn('OWNERSHIP_NOT_PROVEN', r.detail)

    def test_the_instance_lock_blocks_a_second_instance_and_is_always_released(self):
        w = self.w
        self.assertTrue(w.locks.acquire(KEY))                      # "another instance" holds the lock
        for step in (dm.REGISTER, dm.ACTIVATE, dm.RECONCILE):
            ok, r = w.run(step, confirm_send_once=True, raw_a=FULL, raw_b=FULL)
            self.assertEqual((ok, r.status), (False, 'BLOCKED'), step)
            self.assertIn('INSTANCE_LOCK_HELD', r.detail)
        self.assertEqual((w.store.exists(NAME), len(w.tr.sends)), (False, 0))
        ok, r = w.run(dm.STATUS)                                   # status is read-only and needs no lock
        self.assertTrue(ok)
        w.locks.release(KEY)
        ok, r = w.run(dm.REGISTER)
        self.assertTrue(ok)
        self.assertEqual(w.locks.held, set())
        # a blocked step (bad parameters) releases the lock too
        ok, r = w.run(dm.REGISTER, magic=0)
        self.assertFalse(ok)
        self.assertEqual(w.locks.held, set())

    def test_nothing_is_deleted_and_recovery_required_stays(self):
        w = self.w
        w.run(dm.REGISTER)
        w.tr.response = efx.response(efx.RS['TIMEOUT_NO_ORDER'])
        ok, r = w.run(dm.ACTIVATE, confirm_send_once=True)
        self.assertEqual(r.status, 'RECOVERY_REQUIRED')
        before = w.store.read(NAME)
        for _ in range(3):
            w.run(dm.ACTIVATE, confirm_send_once=True)
            w.run(dm.RECONCILE, raw_a=FULL, raw_b=FULL)
            w.run(dm.STATUS)
        self.assertEqual(w.store.read(NAME), before)
        self.assertEqual(len(w.tr.sends), 1)


class Mutants(unittest.TestCase):
    def test_mutants_are_caught(self):
        src = _read('tests', 't011_demo_reference.py')
        base = Pipeline('test_the_whole_pipeline_once_then_a_rerun_without_a_second_request_and_a_restart')
        cases = [
            ('step NONE acts', "    if prm.step == NONE:\n        return False, res", "    if False:\n        return False, res"),
            ('send without confirm', "            if not prm.confirm_send_once:", "            if False:"),
            ('lock ignored', "        if not locks.acquire(key):", "        if False:"),
            ('lock never released', "        if held:\n            locks.release(key)", "        if False:\n            locks.release(key)"),
            ('status writes via register', "    if prm.step == STATUS:", "    if prm.step == NONE:"),
        ]
        for name, old, new in cases:
            with self.subTest(name):
                self.assertIn(old, src, 'vacuous mutant')
                ns = {'__name__': 'demo_mutant'}
                exec(compile(src.replace(old, new, 1), 'demo_mutant', 'exec'), ns)
                import types
                m = types.SimpleNamespace(**ns)
                caught = False
                global dm
                real = dm
                try:
                    dm = m
                    for t in ('test_the_whole_pipeline_once_then_a_rerun_without_a_second_request_and_a_restart', 'test_a_real_transport_needs_the_phrase_and_a_demo_account',
                              'test_the_instance_lock_blocks_a_second_instance_and_is_always_released', 'test_disabled_by_default_and_every_unset_parameter_blocks'):
                        res = unittest.TestResult()
                        Pipeline(t).run(res)
                        if res.failures or res.errors:
                            caught = True
                            break
                except Exception:
                    caught = True
                finally:
                    dm = real
                self.assertTrue(caught, 'mutant not caught: ' + name)


class Sources(unittest.TestCase):
    def test_trading_calls_exist_only_in_the_real_transport_and_the_separate_open_position_script(self):
        files = glob.glob(os.path.join(ROOT, 'src', '**', '*.mq[h5]'), recursive=True)
        holders = []
        for f in files:
            code = strip_comments(open(f, encoding='utf-8').read())
            if re.search(r'\bOrderSend\s*\(', code):
                holders.append(os.path.relpath(f, ROOT).replace(os.sep, '/'))
            for w in ('OrderSendAsync', 'CTrade', 'PositionClose', 'PositionOpen'):
                self.assertNotRegex(code, r'\b%s\b' % w, f)
        # T013 added its own real entry transport (never executed, compile-only); no other file may hold a trading call
        self.assertEqual(sorted(holders), ['src/XauUsdT011DemoOpenPosition.mq5', 'src/include/EntryTransportReal.mqh', 'src/include/ExitTransportReal.mqh'])

    def test_the_harness_core_has_no_transport_no_trading_and_no_deletion(self):
        core = strip_comments(_read('src', 'include', 'DemoHarness.mqh'))
        for word in ('OrderSend', 'OrderCheck', 'ExitTransportReal', 'FileDelete', 'FileMove', 'GlobalVariableDel', 'ESF_InitFresh', 'iHigh', 'iLow', 'iClose', 'CopyRates', 'Sleep'):
            self.assertNotIn(word, core)
        self.assertIn('step=DM_STEP_NONE;', core)
        self.assertIn('res.status="DISABLED";', core)
        self.assertIn('if(!p.confirm_send_once)', core)
        self.assertIn('EL_Acquire(', core)
        self.assertIn('EL_Release(', core)
        run = core[core.index('bool DM_Run('):]
        self.assertLess(run.index('EL_Acquire('), run.index('EX_Register('))
        self.assertLess(run.index('EX_Register('), run.index('EL_Release('))
        self.assertGreater(run.index('EL_Release('), run.index('EX_Reconcile('))

    def test_the_harness_script_is_disabled_by_default_deletes_nothing_and_has_no_signal(self):
        script = strip_comments(_read('src', 'XauUsdT011DemoHarness.mq5'))
        for need in ('input ENUM_DM_STEP InpStep=DM_STEP_NONE;', 'input string InpAuthorisation="";', 'input bool InpConfirmSendOnce=false;', 'input long InpEaMagic=0;',
                     'input long InpPositionId=0;', 'input string InpSymbol="";', 'input ENUM_DM_DIRECTION InpDirection=DM_DIR_UNSET;', 'input double InpLevel2R=-1;', 'input double InpTpPrice=-1;',
                     'input double InpVolumeInitial=0;', 'input ENUM_EX_FILLING InpFilling=EX_FILL_UNSET;', 'input long InpDeviation=-1;', 'input ENUM_EX_FILTER_POLICY InpFilterPolicy=EX_POL_UNSET;',
                     'input ENUM_EX_FILTER_STATE InpFilterState=EX_FS_UNKNOWN;'):
            self.assertIn(need, script)
        for word in ('FileDelete', 'GlobalVariableDel', 'OrderSend', 'iHigh', 'iLow', 'iClose', 'iOpen', 'CopyRates', 'CopyHigh', 'OnTick', 'OnTimer', 'EventSetTimer', 'Sleep', 'H4', 'M15'):
            self.assertNotIn(word, script)
        self.assertEqual(script.count('DM_Run('), 1)

    def test_the_open_position_script_is_separate_disabled_and_fully_gated(self):
        src = strip_comments(_read('src', 'XauUsdT011DemoOpenPosition.mq5'))
        self.assertIn('input bool InpEnabled=false;', src)
        self.assertEqual(len(re.findall(r'\bOrderSend\s*\(', src)), 1)
        order = ['if(!InpEnabled)', 'InpAuthorisation!=OP_AUTH_PHRASE', 'ACCOUNT_TRADE_MODE_DEMO', 'ACCOUNT_MARGIN_MODE_RETAIL_HEDGING', 'InpEaMagic<=0', 'InpSymbol!=_Symbol',
                 '(int)InpDirection!=(int)OP_DIR_BUY&&(int)InpDirection!=(int)OP_DIR_SELL', 'EX_FILL_FOK', 'InpDeviation<0', 'EX_OnGrid(InpVolume,vstep)', 'ES_Split(',
                 'SL_OR_TP_NOT_ON_THE_TICK_GRID_OR_NOT_POSITIVE', 'OPG_Run(']
        flat = re.sub(r'\s+', '', src)
        at, pos = 0, []
        for s_ in order:
            at = flat.index(re.sub(r'\s+', '', s_), at)
            pos.append(at)
        self.assertEqual(pos, sorted(pos))
        # no look at positions or orders before the guard (the look happens INSIDE the lock); the read-only listing afterwards is fine
        onstart = src[src.index('void OnStart()'):]
        self.assertLess(onstart.index('OPG_Run('), onstart.index('PositionsTotal'))
        self.assertNotIn('OrderCheck(', onstart)
        self.assertNotIn('OrderSend(', onstart)
        self.assertNotIn('EL_Acquire(', onstart)
        self.assertIn('input string InpAuthorisation="";', src)
        self.assertIn('input long InpEaMagic=0;', src)
        self.assertNotRegex(src, r'FileOpen|FileDelete|ESF_|GlobalVariableDel|PositionClose|PositionModify')
        self.assertNotIn('OnTick', src)

    def test_the_lock_header_calls_only_global_variable_apis(self):
        lock = strip_comments(_read('src', 'include', 'ExitInstanceLock.mqh'))
        self.assertIn('GlobalVariableSetOnCondition(key,1.0,0.0)', lock)
        self.assertIn('GlobalVariableTemp(key)', lock)
        self.assertNotRegex(lock, r'GlobalVariablesDeleteAll|GlobalVariableDel|FileDelete')
        self.assertIn('if(!held) return;', lock)


class OpenGuard(unittest.TestCase):
    """the locked sequence of the open-position step (fake port): the scan is inside the lock, an intent is written before the send and never removed"""
    LOGIN, MAGIC = 5001234, 777

    def setUp(self):
        self.files, self.locks = og.Files(), og.Locks()
        self.key, self.name = og.lock_key(self.LOGIN, self.MAGIC), og.intent_name(self.LOGIN, self.MAGIC)

    def run_(self, port, files=None):
        return og.run(port, files or self.files, self.locks, self.key, self.name, 'INTENT-TEXT')

    def test_one_run_scans_inside_the_lock_writes_the_intent_then_sends_once(self):
        port = og.Port()
        seen = {}
        port.on_scan = lambda: seen.setdefault('held', self.key in self.locks.held)
        o = self.run_(port)
        self.assertTrue(o.sent)
        self.assertEqual((o.sends, port.sends), (1, 1))
        self.assertEqual(port.log, ['positions', 'orders', 'precheck', 'send'])
        self.assertTrue(seen['held'])
        self.assertEqual(self.files.data[self.name], 'INTENT-TEXT')
        self.assertEqual(self.locks.held, set())

    def test_two_instances_that_both_saw_no_position_send_only_one_open(self):
        a, b = og.Port(shows_position_after_send=False), og.Port()
        oa = self.run_(a)          # instance 1 passes everything and sends
        ob = self.run_(b)          # instance 2 saw "no position" earlier; it takes the lock AFTER instance 1 released it
        self.assertTrue(oa.sent)
        self.assertFalse(ob.sent)
        self.assertEqual((a.sends, b.sends), (1, 0))
        self.assertIn('OPEN_INTENT_EXISTS', ob.reason)
        self.assertEqual(b.log, [])          # blocked before any scan or send

    def test_the_second_instance_is_blocked_by_the_visible_position_when_the_intent_is_absent(self):
        a = og.Port(shows_position_after_send=True)
        self.assertTrue(self.run_(a).sent)
        self.files.data.clear()              # model: only the position check remains
        b = og.Port(positions=1)
        ob = self.run_(b)
        self.assertFalse(ob.sent)
        self.assertEqual(b.sends, 0)
        self.assertIn('A_POSITION_WITH_THIS_MAGIC_ALREADY_EXISTS', ob.reason)

    def test_an_instance_started_while_the_first_holds_the_lock_does_nothing(self):
        b = og.Port()
        res = {}
        a = og.Port()
        a.on_scan = lambda: res.setdefault('b', self.run_(b))      # instance 2 arrives in the middle of instance 1's locked section
        self.assertTrue(self.run_(a).sent)
        self.assertFalse(res['b'].sent)
        self.assertIn('INSTANCE_LOCK_HELD', res['b'].reason)
        self.assertEqual((a.sends, b.sends, b.log), (1, 0, []))

    def test_a_pending_order_blocks_inside_the_lock_and_nothing_is_written(self):
        port = og.Port(orders=1)
        o = self.run_(port)
        self.assertFalse(o.sent)
        self.assertEqual(port.sends, 0)
        self.assertIn('AN_ORDER_WITH_THIS_MAGIC_ALREADY_EXISTS', o.reason)
        self.assertFalse(self.files.exists(self.name))
        self.assertEqual(self.locks.held, set())

    def test_unreadable_positions_or_orders_block(self):
        for kw, word in ((dict(positions=-1), 'POSITIONS_UNREADABLE'), (dict(orders=-1), 'ORDERS_UNREADABLE')):
            port = og.Port(**kw)
            o = self.run_(port)
            self.assertFalse(o.sent)
            self.assertIn(word, o.reason)
            self.assertEqual(port.sends, 0)
            self.assertFalse(self.files.exists(self.name))

    def test_a_failed_precheck_persists_nothing_and_sends_nothing(self):
        port = og.Port(precheck=False)
        o = self.run_(port)
        self.assertFalse(o.sent)
        self.assertEqual(port.sends, 0)
        self.assertFalse(self.files.exists(self.name))

    def test_an_intent_that_cannot_be_written_or_verified_blocks_the_send(self):
        for f in (og.Files(fail_write=True), og.Files(corrupt_readback=True)):
            port = og.Port()
            o = self.run_(port, f)
            self.assertFalse(o.sent)
            self.assertEqual(port.sends, 0)
            self.assertIn('OPEN_INTENT_NOT_VERIFIED', o.reason)
        self.assertEqual(self.locks.held, set())

    def test_restart_after_an_uncertain_response_stays_blocked_even_with_no_visible_position(self):
        first = og.Port()                      # the request was sent; the position is not visible yet (response uncertain)
        self.assertTrue(self.run_(first).sent)
        self.assertEqual(first.positions, 0)
        for _ in range(3):                     # restarts: the lock is free, no position is visible, the intent is on disk
            again = og.Port()
            o = self.run_(again)
            self.assertFalse(o.sent)
            self.assertEqual(again.sends, 0)
            self.assertIn('OPEN_INTENT_EXISTS', o.reason)
        self.assertEqual(self.files.data[self.name], 'INTENT-TEXT')       # never cleaned, never rewritten
        self.assertEqual(self.files.deletes, 0)

    def test_a_half_written_intent_file_also_blocks(self):
        self.files.data[self.name] = ''
        port = og.Port()
        self.assertFalse(self.run_(port).sent)
        self.assertEqual(port.sends, 0)

    def test_direction_must_be_a_known_buy_or_sell(self):
        self.assertTrue(og.direction_ok(1) and og.direction_ok(-1))
        for bad in (0, 2, -2, 3, 100, -100, 2147483647, None, 1.5, True):
            self.assertFalse(og.direction_ok(bad), bad)

    def test_the_mql_guard_keeps_the_order_and_never_removes_the_intent(self):
        g = strip_comments(_read('src', 'include', 'DemoOpenGuard.mqh'))
        run = g[g.index('bool OPG_Run('):]
        marks = ['EL_Acquire(', 'ESF_Exists(intent_name)', 'CountPositions()', 'CountOrders()', 'PreCheck()', 'ESF_WriteAll(intent_name', 'ESF_ReadAll(intent_name,back)', 'port.Send(', 'EL_Release(']
        at, pos = 0, []
        for m in marks:
            at = run.index(m, at)
            pos.append(at)
        self.assertEqual(pos, sorted(pos))
        self.assertEqual(g.count('port.Send('), 1)
        for word in ('FileDelete', 'FileMove', 'ESF_Save', 'ESF_InitFresh', 'GlobalVariableDel', 'OrderSend', 'OrderCheck', 'PositionClose', 'Sleep', 'for(', 'while('):
            self.assertNotIn(word, g)
        # every exit after a successful acquire releases the lock (the one exit before it is the failed acquire)
        self.assertEqual(run.count('EL_Release('), run.count('return(false);') + run.count('return(true);') - 1)

    def test_the_open_script_validates_direction_with_both_known_values(self):
        src = re.sub(r'\s+', '', strip_comments(_read('src', 'XauUsdT011DemoOpenPosition.mq5')))
        self.assertIn('(int)InpDirection!=(int)OP_DIR_BUY&&(int)InpDirection!=(int)OP_DIR_SELL', src)
        self.assertNotIn('InpDirection==OP_DIR_UNSET', src)


class Presets(unittest.TestCase):
    @staticmethod
    def inputs(path):
        code = strip_comments(_read(*path))
        return dict((n, v.strip()) for n, v in re.findall(r'^input\s+[\w ]+?\s+(Inp\w+)\s*=\s*([^;]+);', code, re.M))

    @staticmethod
    def values(path):
        d = {}
        for line in _read(*path).splitlines():
            line = line.strip()
            if line and not line.startswith(';'):
                k, v = line.split('=', 1)
                assert k not in d, k
                d[k] = v
        return d

    def test_every_preset_lists_every_input_exactly_once_and_leaves_the_authorisation_empty(self):
        harness = ('src', 'XauUsdT011DemoHarness.mq5')
        names = sorted(self.inputs(harness))
        for step in ('01_status', '02_register', '03_activate', '04_reconcile'):
            path = ('src', 'presets', 'XauUsdT011Demo_%s.set' % step)
            v = self.values(path)
            self.assertEqual(sorted(v), names, step)
            self.assertEqual(v['InpAuthorisation'], '', step)             # the owner types the phrase deliberately after the Codex review
            self.assertEqual(v['InpConfirmSendOnce'], 'false', step)
        v3 = self.values(('src', 'presets', 'XauUsdT011Demo_03_activate.set'))
        self.assertEqual(v3['InpStep'], '3')
        for step, num in (('01_status', '1'), ('02_register', '2'), ('04_reconcile', '4')):
            self.assertEqual(self.values(('src', 'presets', 'XauUsdT011Demo_%s.set' % step))['InpStep'], num)

    def test_the_test_plan_avoids_the_open_decisions(self):
        v = self.values(('src', 'presets', 'XauUsdT011Demo_02_register.set'))
        self.assertEqual((v['InpDirection'], v['InpFilling'], v['InpFilterPolicy']), ('1', '2', '1'))
        self.assertEqual(float(v['InpVolumeInitial']), 0.10)                    # 10 steps of 0.01: 8 / 2, realisable; the remainder is above the minimum
        self.assertEqual(float(v['InpLevel2R']), -1.0)                          # the level and the TP are filled in by the owner from the STATUS and open-position logs: unset blocks
        self.assertEqual(float(v['InpTpPrice']), -1.0)

    def test_the_open_position_preset_is_complete_and_disabled(self):
        names = sorted(self.inputs(('src', 'XauUsdT011DemoOpenPosition.mq5')))
        v = self.values(('src', 'presets', 'XauUsdT011DemoOpenPosition.set'))
        self.assertEqual(sorted(v), names)
        self.assertEqual((v['InpEnabled'], v['InpAuthorisation']), ('false', ''))


if __name__ == '__main__':
    unittest.main()
