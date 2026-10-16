"""Static tests for the chart view of the entry orchestrator (src/include/EntryOrchestratorView.mqh, EA v1.15, input InpChartView).
They prove what a source test CAN prove: the view reads only, runs after the decision, keeps its own prefix, adds nothing to the decision path of the feed, and its provenance tags
([K] confirmed / [P] temporary simulation choice) equal the labels of the simulation preset. They do NOT prove that the chart is readable or that the objects are placed well: that needs
the MT5 screenshots listed in docs/T016-entry-orchestrator.md. Nothing here compiles MQL5."""
import os
import re
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import preset_check as pc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = '25fc190'          # the last commit before the view: the feed's decision path must still equal it


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='ascii') as f:
        return f.read()


def code(text):
    return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', text))


VIEW = code(read('src', 'include', 'EntryOrchestratorView.mqh'))
FEED = code(read('src', 'include', 'EntryOrchestratorFeed.mqh'))
EA = code(read('src', 'XauUsdEntryOrchestrator.mq5'))


class ViewIsReadOnly(unittest.TestCase):
    def test_the_view_has_no_trading_io_or_decision_call(self):
        for w in ('OrderSend', 'OrderCheck', 'CTrade', 'PositionClose', 'SendNotification', 'FileOpen', 'FileWrite', 'FileDelete', 'GlobalVariableSet', 'DBS_Capture', 'DBS_Write',
                  'g_orch', 'Step(', 'EG_Submit', 'EN_', 'TP_Authorize', 'CopyRates', 'CalendarValueHistory', 'real=true'):
            self.assertNotIn(w, VIEW, w)

    def test_it_takes_the_outcome_and_the_feed_as_const_and_never_writes_them(self):
        self.assertIn('void Update(const SEoOutcome &out,const CEoFeed &feed,const bool real_entry,const bool mgmt_read_only)', VIEW)
        self.assertIsNone(re.search(r'\b(out|feed)\.[\w.\[\]]+\s*(=|\+=|-=)[^=]', VIEW), 'an assignment into the outcome or the feed')
        self.assertIsNone(re.search(r'\bfeed\.\w+\([^)]*\)', VIEW), 'a call of a feed method (the feed is read through its members)')

    def test_every_object_it_creates_has_its_own_prefix_and_deletion_is_by_prefix_only(self):
        names = re.findall(r'(?:Segment|Box|Note)\((EV_PREFIX\+"\w+"|[^,]+),', VIEW)
        names = [n for n in names if n not in ('const string name',)]
        for n in names:
            self.assertTrue(n.startswith('EV_PREFIX+') or n.startswith('EV_PREFIX +'), n)
        self.assertIn('#define EV_PREFIX        "velo_t016v_"', read('src', 'include', 'EntryOrchestratorView.mqh'))
        self.assertNotIn('ObjectsDeleteAll(m_chart,"")', VIEW)
        for m in re.finditer(r'ObjectsDeleteAll\(([^)]*)\)', VIEW):
            self.assertIn(m.group(1), ('m_chart,EV_PREFIX',), m.group(0))
        self.assertIn('if(StringFind(name,EV_PREFIX)!=0) continue;', VIEW, 'the object loop skips foreign names (manual drawings)')
        self.assertIn('if(StringFind(name,EV_PANEL_PREFIX)==0) continue;', VIEW)
        self.assertNotIn('velo_t003', VIEW, 'the H4 objects belong to the existing drawer and its prefix; the view names none itself')

    def test_the_h4_layer_is_the_existing_drawer_fed_with_the_arrays_the_build_computed(self):
        self.assertIn('m_h4.Draw(feed.hbars,feed.dv_n,feed.params,feed.dv_ev,feed.dv_tracks,feed.dv_events,', VIEW)
        for w in ('H3Evaluate', 'H3SetupContext', 'H4FindSwings', 'H4FindFvgs', 'M4ReplayTimeline', 'M4SetContext', 'SPB_'):
            self.assertNotIn(w, VIEW, 'the view recomputes nothing: ' + w)

    def test_the_text_is_ascii_albanian_and_covers_every_status_of_the_step(self):
        raw = read('src', 'include', 'EntryOrchestratorView.mqh')
        self.assertTrue(all(ord(ch) < 128 for ch in raw))
        core = code(read('src', 'include', 'EntryOrchestrator.mqh'))
        statuses = set(re.findall(r'EO_Set\(out,"(\w+)"', core)) | {'EXECUTOR', 'GATE_BLOCKED'}
        fn = VIEW[VIEW.index('string EV_StatusText'):VIEW.index('class CEoView')]
        for st in sorted(statuses):
            self.assertIn('"%s"' % st, fn, 'no Albanian text for the status ' + st)

    def test_simulation_fake_read_only_is_always_shown_and_a_real_transport_is_flagged(self):
        panel = VIEW[VIEW.index('void DrawPanel'):VIEW.index('public:')]
        self.assertIn('SIMULIM / FAKE / READ_ONLY', panel)
        self.assertIn('if(real_entry || !mgmt_read_only)', panel)
        self.assertIn('TRANSPORT REAL I ZGJEDHUR', panel)
        self.assertIn('jo strategji e vleresuar nga klienti', panel)


class ProvenanceTagsEqualThePresetLabels(unittest.TestCase):
    def labels(self):
        _, labels, _ = pc.parse_preset(pc.SIMULATION_PRESET)
        return labels

    def test_what_is_tagged_confirmed_is_confirmed_and_what_is_tagged_proposal_is_a_proposal(self):
        lab = self.labels()
        self.assertIn('#define EV_TAG_CONFIRMED "[K]"', read('src', 'include', 'EntryOrchestratorView.mqh'))
        self.assertIn('#define EV_TAG_PROPOSAL  "[P]"', read('src', 'include', 'EntryOrchestratorView.mqh'))
        self.assertEqual(lab['InpEntryEdge'], 'CONFIRMED')                         # the limit entry edge: [K]
        for k in ('InpContextSource', 'InpM15Level', 'InpFvgTiming', 'InpCandidate', 'InpSlRule', 'InpSlBuffer', 'InpTargetRule', 'InpRiskSource'):
            self.assertEqual(lab[k], 'DEMO-PROPOSAL', k)                           # H4 / M15 / SL / TP / risk: [P]
        panel = VIEW[VIEW.index('void DrawPanel'):VIEW.index('public:')]
        self.assertIn('"H4 "+EV_TAG_PROPOSAL', panel)
        self.assertIn('"M15 "+EV_TAG_PROPOSAL', panel)
        self.assertIn('EV_TAG_CONFIRMED+"skaji', panel)
        self.assertEqual(panel.count('EV_TAG_CONFIRMED'), 2, 'only the entry edge and the legend carry [K]')
        self.assertIn('skaji | SL "+EV_Price(m_plan.sl,m_digits)+" "+EV_TAG_PROPOSAL', panel)
        self.assertIn('EV_TAG_PROPOSAL,(m_plan.direction==1', panel)               # the TP tag

    def test_the_risk_line_names_the_simulation_policy_as_a_proposal(self):
        panel = VIEW[VIEW.index('void DrawPanel'):VIEW.index('public:')]
        self.assertIn('"Risku: "+out.risk_label+" (1% e balances aktuale) "+EV_TAG_PROPOSAL', panel)


class TheViewDoesNotChangeTheDecision(unittest.TestCase):
    def test_the_view_is_off_by_default_and_both_presets_say_what_they_choose(self):
        self.assertIn('input bool InpChartView=false;', EA)
        for name, want in (('demo', 'false'), ('simulation', 'true')):
            v, _, d = pc.parse_preset(os.path.join(ROOT, 'src', 'presets', 'XauUsdEntryOrchestrator_%s_fake.set' % name))
            self.assertEqual((v['InpChartView'], d), (want, []), name)

    def test_the_ea_calls_the_view_once_after_the_decision_and_the_status_and_only_when_asked(self):
        poll = EA[EA.index('void Poll()'):EA.index('int OnInit()')]
        self.assertEqual(poll.count('g_view.Update('), 1)
        self.assertEqual(EA.count('g_view.'), 3)                                    # Init, Update, Destroy
        self.assertIn('if(InpChartView) g_view.Update(out,g_feed,g_real_entry,InpManagementTransport==EOI_MTR_READ_ONLY);', poll)
        self.assertGreater(poll.index('g_view.Update('), poll.index('Status(text);'))
        self.assertGreater(poll.index('Status(text);'), poll.index('g_orch.Step('))
        self.assertNotIn('g_view', poll[:poll.index('g_orch.Step(')], 'the view is not consulted before the decision')
        step = poll[poll.index('g_orch.Step('):poll.index(';', poll.index('g_orch.Step('))]
        self.assertNotIn('g_view', step)

    def test_the_feed_decision_path_is_the_one_before_the_view_plus_a_gated_copy(self):
        try:
            base = subprocess.run(['git', 'show', '%s:src/include/EntryOrchestratorFeed.mqh' % BASE], cwd=ROOT, capture_output=True, text=True, check=True).stdout
        except Exception:
            self.skipTest('the base commit is not available')
        text = read('src', 'include', 'EntryOrchestratorFeed.mqh')
        # remove exactly the view additions
        text = re.sub(r'   // chart view only \(InpChartView\)[^\n]*\n(?:   (?:bool keep_view|bool dv_have|int dv_n|SH3Eval dv_ev|SH3Track dv_tracks\[\]|SH3Event dv_events\[\])[^\n]*\n)+', '', text)
        text = re.sub(r'   // copy for the chart view;[^\n]*\n   void KeepView\(.*?\n     \}\n(?=   void T003View)', '', text, flags=re.S)
        for line in ("      keep_view=false;                         // the EA switches it on AFTER Init when the chart view is requested\n", "      dv_n=0;\n", "      dv_have=false;\n",
                     "      if(keep_view) KeepView(n,e,tracks,events);\n"):
            self.assertIn(line, text, line)
            text = text.replace(line, '', 1)
        self.assertEqual(code(text), code(base), 'the feed differs from the base outside the view additions')

    def test_the_copy_is_gated_and_nothing_in_the_decision_reads_it(self):
        self.assertEqual(len(re.findall(r'if\(keep_view\) KeepView\(', FEED)), 1)
        for m in re.finditer(r'\bdv_\w+', FEED):
            line = FEED[:m.start()].count('\n')
        body = FEED[FEED.index('bool Build('):FEED.index('bool Poll(bool &feed_ok)')]
        self.assertNotIn('dv_', body, 'Build does not read the view copies')
        self.assertNotIn('dv_', FEED[FEED.index('bool Poll(bool &feed_ok)'):FEED.index('struct SEoMarketCfg')])
        self.assertNotIn('dv_', EA)
        self.assertNotIn('keep_view', FEED[FEED.index('bool Build('):FEED.index('bool Poll(bool &feed_ok)')])


class SyntheticDemoScript(unittest.TestCase):
    DEMO = code(read('src', 'XauUsdEntryViewDemo.mq5'))

    def test_the_demo_is_labelled_synthetic_and_touches_nothing_but_the_view(self):
        raw = read('src', 'XauUsdEntryViewDemo.mq5')
        self.assertIn('SYNTHETIC DEMO', raw)
        self.assertIn('NOT a signal', raw)
        for w in ('OrderSend', 'CTrade', 'AccountInfo', 'PositionsTotal', 'OrdersTotal', 'CopyRates', 'Calendar', 'FileOpen', 'GlobalVariableSet', 'SendNotification', 'H3Evaluate', 'M4ReplayTimeline', 'SPB_',
                  'g_orch', 'EG_Submit'):
            self.assertNotIn(w, self.DEMO, w)
        self.assertEqual(re.findall(r'#include "([^"]+)"', self.DEMO), ['include/EntryOrchestratorView.mqh'])
        for m in re.finditer(r'ObjectsDeleteAll\(([^)]*)\)', self.DEMO):
            self.assertEqual(m.group(1), '0,EV_PREFIX')

    def test_the_demo_is_not_an_expert_advisor(self):
        self.assertIn('void OnStart()', self.DEMO)
        self.assertNotIn('OnTick', self.DEMO)
        self.assertNotIn('OnTimer', self.DEMO)


if __name__ == '__main__':
    unittest.main()
