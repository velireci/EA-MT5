"""T011 restart probe: the PREPARE -> (terminal restart) -> RESTORE flow of the two diagnostic scripts, modelled over the reference, and source-level checks that the
scripts use only the existing modules, the probe's own file names, a declared position and no trading / position / symbol access."""
import os
import re
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import t011_activation_reference as act  # noqa: E402
import t011_persist_reference as p  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='utf-8') as f:
        return f.read()


def strip_comments(text):
    return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', text))


PROBE = _read('src', 'include', 'T011RestartProbe.mqh')
PREP = strip_comments(_read('src', 'XauUsdT011RestartPrepare.mq5'))
REST = strip_comments(_read('src', 'XauUsdT011RestartRestore.mq5'))


def const(name):
    m = re.search(r'#define %s\s+("?)([^\s/]+)\1' % name, PROBE)
    assert m, name
    v = m.group(2)
    return v if m.group(1) else (float(v) if '.' in v else int(v))


class Flow(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.pos = const('RP_POSITION')
        self.ident = p.Identity('MetaQuotes-Demo', 5001234, const('RP_SYMBOL'), self.pos)
        self.name = const('RP_FILE')

    def tearDown(self):
        self.tmp.cleanup()

    def quote(self, s, bid):
        return act.on_quote(s, self.pos, const('RP_DIRECTION'), const('RP_LEVEL'), bid, bid + (const('RP_ASK') - const('RP_BID')), const('RP_VOLUME_INITIAL'),
                            const('RP_VOLUME_INITIAL'), const('RP_VOLUME_MIN'), const('RP_VOLUME_STEP'), const('RP_VOLUME_MAX'))

    def prepare(self, fs):
        s = act.State()
        res = self.quote(s, const('RP_BID'))
        self.assertEqual(res.action, act.REQUEST_ACTION)
        self.assertEqual((s.request_steps, s.initial_steps), (const('RP_EXPECT_REQUEST_STEPS'), const('RP_EXPECT_INITIAL_STEPS')))
        self.assertAlmostEqual(s.close_volume, const('RP_EXPECT_CLOSE_VOLUME'))
        self.assertTrue(fs.init_fresh(self.name, self.ident)[0])
        ok, why = fs.save(self.name, p.Record(const('RP_EXPECT_GENERATION'), self.ident, s, p.SEND_INTENT))
        self.assertTrue(ok, why)
        return s

    def test_prepare_restart_restore(self):
        s = self.prepare(p.FileStore(self.tmp.name))
        fs2 = p.FileStore(self.tmp.name)            # "the terminal restarted": a new process, only the file survives
        o = fs2.load(self.name, self.ident)
        self.assertEqual((o.verdict, o.state.status, o.generation, o.new_request_allowed, o.reconcile_required, o.orders, o.map_complete),
                         (p.RECOVERY_REQUIRED, act.NEEDS_RECONCILIATION, const('RP_EXPECT_GENERATION'), False, True, [], False))
        st = o.state
        self.assertEqual(st.request_id, act.request_id_for(self.pos))
        self.assertEqual((st.initial_steps, st.request_steps, st.volume_step, st.confirmations, st.executed_steps),
                         (const('RP_EXPECT_INITIAL_STEPS'), const('RP_EXPECT_REQUEST_STEPS'), const('RP_VOLUME_STEP'), 0, 0))
        self.assertEqual((st.position_id, st.direction, st.level, st.volume_initial), (self.pos, const('RP_DIRECTION'), const('RP_LEVEL'), const('RP_VOLUME_INITIAL')))
        for k in range(3):
            res = self.quote(st, const('RP_BID') + 0.5 * (k + 1))
            self.assertEqual((res.event, res.action), ('RECONCILE_REQUIRED', act.NONE_ACTION))
        self.assertNotEqual(st.status, act.DONE)

    def test_prepare_refuses_an_existing_file_and_restore_does_not_write(self):
        fs = p.FileStore(self.tmp.name)
        self.prepare(fs)
        before = fs.read(self.name)
        self.assertFalse(fs.init_fresh(self.name, self.ident)[0])          # PREPARE's guard: never overwrite
        fs.load(self.name, self.ident)
        self.assertEqual(fs.read(self.name), before)                      # RESTORE (load) never writes

    def test_restore_on_another_account_or_without_prepare_is_recovery(self):
        fs = p.FileStore(self.tmp.name)
        self.assertEqual(fs.load(self.name, self.ident).generation, 0)
        self.prepare(fs)
        other = p.Identity('MetaQuotes-Demo', 5001235, const('RP_SYMBOL'), self.pos)
        o = fs.load(self.name, other)
        self.assertEqual((o.verdict, o.generation), (p.RECOVERY_REQUIRED, 0))


class Sources(unittest.TestCase):
    def test_scripts_use_the_existing_modules_only(self):
        for src in (PREP, REST):
            self.assertIn('#include "include/T011RestartProbe.mqh"', src)
        self.assertIn('#include "ExitStateFile.mqh"', PROBE)
        for src in (PROBE, PREP, REST):
            for word in ('OrderSend', 'OrderDelete', 'OrderModify', 'CTrade', 'MqlTradeRequest', 'PositionSelect', 'PositionGet', 'PositionsTotal', 'OrdersTotal',
                         'HistorySelect', 'HistoryDeal', 'SymbolInfo', 'TimeCurrent', 'TimeGMT', 'TimeLocal', 'TimeTradeServer', 'Sleep', 'FILE_COMMON', 'FileOpen',
                         'FileMove', 'FileWrite', 'ESC_Encode', 'ESC_Decode'):
                self.assertNotIn(word, src)

    def test_account_reads_are_the_identity_only(self):
        reads = re.findall(r'Account\w+\(([A-Z_]+)\)', PROBE + PREP + REST)
        self.assertEqual(sorted(set(reads)), ['ACCOUNT_LOGIN', 'ACCOUNT_SERVER'])

    def test_file_names_are_the_probes_own(self):
        self.assertEqual(const('RP_FILE'), 'VELO_T011_RESTART_PROBE.state')
        for other in ('VELO_T011_EXIT_', 'VELO_T011_PERSIST_SELFTEST'):
            self.assertNotIn(other, PROBE + PREP + REST)
        deletes = re.findall(r'FileDelete\(([^)]*)\)', PREP + REST)
        self.assertEqual(sorted(set(deletes)), ['RP_FILE', 'RP_FILE+ESF_TMP_SUFFIX'])
        self.assertEqual(PREP.count('FileDelete'), 0)                      # PREPARE never deletes
        self.assertNotIn('ESF_Save(RP_FILE', REST)                          # RESTORE never writes the record
        self.assertNotIn('ESF_InitFresh', REST)

    def test_prepare_never_overwrites_and_saves_the_intent_without_a_map(self):
        i_guard = PREP.index('ESF_Exists(RP_FILE)')
        self.assertLess(i_guard, PREP.index('ESF_InitFresh(RP_FILE'))
        self.assertLess(PREP.index('ESF_InitFresh(RP_FILE'), PREP.index('ESF_Save(RP_FILE'))
        self.assertIn('rec.send_phase=ESC_SEND_INTENT;', PREP)
        self.assertNotIn('n_orders', PREP)                                  # no order map
        self.assertNotIn('ESC_SEND_MAPPED', PREP + REST)

    def test_restore_checks_what_was_asked(self):
        for need in ('st.request_id==EA_RequestId((ulong)RP_POSITION)', 'st.initial_steps==RP_EXPECT_INITIAL_STEPS', 'st.request_steps==RP_EXPECT_REQUEST_STEPS',
                     'st.volume_step==RP_VOLUME_STEP', 'st.confirmations==0', 'o.n_orders==0', 'o.reconcile_required', '!o.new_request_allowed',
                     'EA_EV_RECONCILE_REQUIRED', 'requests==0'):
            self.assertIn(need, REST)
        self.assertNotIn('EA_OnReport', REST)                               # no execution is reported or confirmed
        self.assertNotIn('ER_Reconcile', REST)

    def test_parameters_are_filled_in_and_cleanup_is_explicit(self):
        self.assertEqual(PREP.count('input '), 0)                           # PREPARE needs no input at all
        self.assertEqual(len(re.findall(r'^input ', REST, re.M)), 1)
        self.assertIn('input bool InpCleanupProbeFile=false;', REST)
        self.assertIn('if(InpCleanupProbeFile)', REST)
        self.assertLess(REST.index('if(InpCleanupProbeFile)'), REST.index('RP_Identity('))


if __name__ == '__main__':
    unittest.main()
