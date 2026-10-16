"""Static tests for the chart view of the entry orchestrator (src/include/EntryOrchestratorView.mqh, EA v1.16, input InpChartView) and its synthetic MT5 test (src/tests/EntryViewTest.mq5).
They prove what a source test CAN prove: the view reads only, runs after the decision, keeps its own prefix, adds nothing to the decision path of the feed, speaks only in the four decision words,
covers every reason code of the gate chain, never draws an entry arrow, makes gold exclusive to the plan bridge's selection, and its words about confirmed / temporary choices equal the labels of the
simulation preset. They do NOT prove that the chart is readable or that the marks are well placed: that needs the MT5 run of EntryViewTest.mq5 and the screenshots listed in
docs/T016-entry-orchestrator.md. Nothing here compiles MQL5."""
import hashlib
import os
import re
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import preset_check as pc  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE_SHA256 = '398ddb39439a237138832221198fd2e05d122f4ffd795113e0f8b62bca74d623'   # sha256 of the comment-stripped feed at 25fc190: used when the git base is not available locally
BASE = '25fc190'          # the last commit before the view: the feed's decision path must still equal it


def read(*parts):
    with open(os.path.join(ROOT, *parts), encoding='ascii') as f:
        return f.read()


def code(text):
    return re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', text))


RAW = read('src', 'include', 'EntryOrchestratorView.mqh')
VIEW = code(RAW)
FEED = code(read('src', 'include', 'EntryOrchestratorFeed.mqh'))
EA = code(read('src', 'XauUsdEntryOrchestrator.mq5'))
TEST_RAW = read('src', 'tests', 'EntryViewTest.mq5')
TEST = code(TEST_RAW)
PANEL = VIEW[VIEW.index('void DrawPanels'):VIEW.index('public:\n   CEoView(void)')]


def fn(name_start, name_end):
    return VIEW[VIEW.index(name_start):VIEW.index(name_end)]


class ViewIsReadOnly(unittest.TestCase):
    def test_the_view_has_no_trading_io_or_decision_call(self):
        for w in ('OrderSend', 'OrderCheck', 'CTrade', 'PositionClose', 'SendNotification', 'FileOpen', 'FileWrite', 'FileDelete', 'GlobalVariableSet', 'DBS_Capture', 'DBS_Write',
                  'g_orch', 'Step(', 'EG_Submit', 'EN_Place', 'EN_Cancel', 'EN_Run', 'TP_Authorize', 'CopyRates', 'CalendarValueHistory', 'real=true', 'AccountInfo'):
            self.assertNotIn(w, VIEW, w)

    def test_it_takes_the_outcome_and_the_feed_as_const_and_never_writes_them(self):
        self.assertIn('void Update(const SEoOutcome &out,const CEoFeed &feed,const bool real_entry,const bool mgmt_read_only)', VIEW)
        self.assertIsNone(re.search(r'\b(out|feed)\.[\w.\[\]]+\s*(=|\+=|-=)[^=]', VIEW), 'an assignment into the outcome or the feed')
        self.assertIsNone(re.search(r'\bfeed\.\w+\([^)]*\)', VIEW), 'a call of a feed method (the feed is read through its members)')

    def test_every_mark_has_its_own_prefix_and_deletion_is_by_prefix_only(self):
        for m in re.finditer(r'\b(?:Segment|Zone|Note|Dot)\((EV_PREFIX\+"\w+"|[^,]+),', VIEW):
            n = m.group(1)
            if n == 'const string name':
                continue
            self.assertTrue(n.startswith('EV_PREFIX+'), n)
        self.assertIn('#define EV_PREFIX        "velo_t016v_"', RAW)
        for m in re.finditer(r'ObjectsDeleteAll\(([^)]*)\)', VIEW):
            self.assertIn(m.group(1), ('m_chart,EV_PREFIX', 'm_chart,m_prefix'), m.group(0))
        self.assertEqual(sorted(re.findall(r'\.Init\((EV_PANEL_PREFIX\+"\w+"),\d\)', VIEW)), ['EV_PANEL_PREFIX+"leg_"', 'EV_PANEL_PREFIX+"main_"'], 'the boxes delete only their own prefix, below the panel prefix')
        self.assertIn('if(StringFind(name,EV_PREFIX)!=0) continue;', VIEW, 'the object loop skips foreign names (manual drawings)')
        self.assertIn('if(StringFind(name,EV_PANEL_PREFIX)==0) continue;', VIEW)
        self.assertNotIn('velo_t003', VIEW)
        self.assertNotIn('H4BiasDrawer', VIEW, 'the view draws its own limited marks from the decision data; the T003 map is not used')

    def test_the_view_recomputes_nothing(self):
        for w in ('H3Evaluate', 'H3SetupContext', 'H4FindSwings', 'H4FindFvgs', 'M4ReplayTimeline', 'M4SetContext', 'M4SelectSwingProposal', 'SPB_', 'TG_Compute'):
            self.assertNotIn(w, VIEW, w)
        # the swept level of an internal sweep is the bar named by the decision's own event id (a lookup), never a new swing search
        draw = fn('void DrawH4', 'void DrawM15(')
        self.assertIn('EV_ParseInteriorId(feed.dv_events[j].ref,pivot,is_high)', draw)
        self.assertIn('FindH4Bar(feed,pivot)', draw)
        self.assertIn('if(feed.dv_ev.st.dir==H3_NONE || feed.dv_ev.st.setup_id=="") return;', draw, 'no setup: nothing is drawn')
        self.assertIn('if(level>0.0)', draw, 'no level, no line')
        self.assertIn('if(si>=0)', draw, 'no candle, no mark')
        self.assertIn('if(!feed.st.has_context) return;', fn('void DrawM15(', 'void DrawM15Zone'), 'without a context the view draws no M15 mark')
        self.assertIn('if(!m_plan.have) return;', fn('void DrawPlan', 'void DrawPanel'), 'without a plan the view draws no entry, SL or TP')

    def test_the_text_is_ascii_and_the_technical_ids_stay_in_tooltips(self):
        self.assertTrue(all(ord(ch) < 128 for ch in RAW))
        panel = PANEL
        self.assertIsNone(re.search(r'\+\s*[\w.\[\]]*(?:\.id|signal_id|bos_level|setup_id|dg_reason)\b', panel), 'a technical id or code appended to a panel line')
        self.assertNotIn('out.reason', panel)
        self.assertIn('"FVG M15 "+state+" "+EV_Price(feed.f[i].lower,m_digits)+" - "+EV_Price(feed.f[i].upper,m_digits)+" | "+feed.f[i].id', VIEW, 'the id is in the tooltip')

    def test_the_view_speaks_in_the_four_decision_words_and_covers_every_status(self):
        verdict = fn('void EV_Verdict', 'color EV_VerdictColor')
        labels = set(re.findall(r'label="([A-Z ]+)"', verdict))
        self.assertEqual(labels, {'PRET', 'BLLOKUAR', 'PLAN GATI', 'KERKESE VIRTUALE', 'KERKESE REALE'}, 'the four decision words, and the request word follows the transport')
        core = code(read('src', 'include', 'EntryOrchestrator.mqh'))
        statuses = set(re.findall(r'EO_Set\(out,"(\w+)"', core)) | {'EXECUTOR', 'GATE_BLOCKED', 'RESERVATION_FAILED'}
        for st in sorted(statuses):
            self.assertIn('"%s"' % st, verdict, 'no Albanian verdict for the status ' + st)
        panel = PANEL
        self.assertIn('"VENDIMI: "+label+" - "', panel)
        self.assertIn('SIMULIM - PA URDHRA REALE', panel)
        self.assertIn('FAKE / READ_ONLY', panel)
        self.assertIn('if(real_entry || !mgmt_read_only)', panel)
        self.assertIn('ATENCION: TRANSPORT REAL I ZGJEDHUR', panel)

    def test_every_reason_code_of_the_gate_chain_has_a_short_meaning(self):
        short = fn('string EV_ReasonShort', 'bool EV_IsWaitingReason')
        prefixes = re.findall(r'EV_Starts\(code,"([A-Za-z_:]+)"\)', short)
        self.assertGreater(len(prefixes), 30)
        codes = set()
        spb = code(read('src', 'include', 'SetupPlanBridge.mqh'))
        codes |= set(re.findall(r'SPB_Block\((?:out|r),"([A-Z_]+)', spb))
        codes |= set(re.findall(r'TP_AddReason\(out,"([A-Za-z_:]+)', code(read('src', 'include', 'TradePlanning.mqh'))))
        codes |= set(re.findall(r'DL_Add\(r,"([A-Za-z_:]+)', code(read('src', 'include', 'DailyLimits.mqh'))))
        codes |= set(re.findall(r'DB_Add\(r,"([A-Za-z_:]+)', code(read('src', 'include', 'DailyBridge.mqh'))))
        codes |= set(re.findall(r'EG_Add\(d,"([A-Za-z_:]+)', code(read('src', 'include', 'EntryGate.mqh'))))
        self.assertGreater(len(codes), 50)
        unmapped = sorted(c for c in codes if not any(c.startswith(p) for p in prefixes))
        self.assertEqual(unmapped, [], 'codes that would show the generic fallback')
        self.assertIn('return("arsye teknike (shih Experts)");', short, 'an unknown code still falls back to a sentence that points to the log')

    def test_the_phase_texts_translate_the_t003_phases_and_the_m15_phases(self):
        h4 = fn('string EV_H4PhaseText', 'string EV_M15PhaseText')
        for ph in ('H3_PH_SWEEP_WAIT', 'H3_PH_HOLD', 'H3_PH_RECONFIRMED'):
            self.assertIn(ph, h4)
        m15 = fn('string EV_M15PhaseText', 'string EV_FirstReason')
        core = code(read('src', 'include', 'M15Confirmation.mqh'))
        for ph in sorted(set(re.findall(r'"((?:WAIT|RETURN|REPLAY)_[A-Z]+)"', core))):
            self.assertIn('"%s"' % ph, m15, 'no Albanian text for the M15 phase ' + ph)


class TheMarksFollowTheRules(unittest.TestCase):
    def test_no_entry_arrow_and_the_only_arrow_objects_are_the_two_dots(self):
        for w in ('OBJ_ARROW_UP', 'OBJ_ARROW_DOWN', 'OBJ_ARROW_BUY', 'OBJ_ARROW_SELL', 'OBJ_ARROW_LEFT_PRICE', 'OBJ_ARROW_RIGHT_PRICE', 'OBJ_ARROW_THUMB'):
            self.assertNotIn(w, VIEW, w)
        self.assertEqual(VIEW.count('Ensure(name,OBJ_ARROW)'), 1)
        dots = re.findall(r'\bDot\(EV_PREFIX\+"(\w+)"', VIEW)
        self.assertEqual(sorted(dots), ['brk_dot', 'sweep_dot'])

    def test_gold_belongs_to_the_fvg_the_plan_bridge_selected_and_nothing_else(self):
        self.assertEqual(VIEW.count('clrGold'), 1)
        zone = fn('void DrawM15Zone', 'void DrawPlan')
        self.assertIn('color clr=(chosen ? clrGold :', zone)
        m15 = fn('void DrawM15(', 'void DrawM15Zone')
        self.assertIn('if(out.spb.candidate_id=="" || feed.f[i].id!=out.spb.candidate_id) continue;', m15, 'chosen = the id the plan bridge selected')
        self.assertIn('DrawM15Zone(feed,i,true,shown,end);', m15)
        self.assertEqual(m15.count('DrawM15Zone(feed,i,true'), 1)
        self.assertLess(m15.index('DrawM15Zone(feed,i,true,shown,end);'), m15.index('for(int pass=0;pass<2;pass++)'), 'the selected FVG is drawn first, before the cap applies')

    def test_the_candidate_confirmed_and_invalid_states_are_named_on_the_zones(self):
        self.assertIn('"rikonfirmuar"', VIEW)
        self.assertIn('"kandidat"', VIEW)
        self.assertIn('"i pavlefshem"', VIEW)
        self.assertIn('ZGJEDHUR nga plani', VIEW)
        h4 = fn('void DrawH4', 'void DrawM15(')
        self.assertIn('(rec ? STYLE_SOLID : (inv ? STYLE_DOT : STYLE_DASH))', h4, 'solid = reconfirmed, dashed = candidate, dotted = invalid: not only a colour')
        self.assertIn('"H4 "+state', h4)
        self.assertIn('OBJPROP_FILL,false', VIEW, 'zones are outlines')

    def test_the_number_of_marks_is_limited(self):
        self.assertIn('#define EV_MAX_H4_FVG    4', RAW)
        self.assertIn('#define EV_MAX_M15_FVG   4', RAW)
        self.assertIn('while(shown<EV_MAX_H4_FVG && taken<limit)', VIEW)
        self.assertIn('while(shown<EV_MAX_M15_FVG)', VIEW)

    def test_the_break_is_a_prototype_break_and_never_a_validated_mss(self):
        for m in re.finditer(r'MSS', VIEW):
            ctx = VIEW[max(0, m.start() - 12):m.end() + 2]
            self.assertTrue('NUK eshte MSS' in ctx or 'jo MSS' in ctx, ctx)
        self.assertIn('"Thyerje M15 "', VIEW)

    def test_the_plan_is_lines_with_names_and_prices_and_tp_equal_2r_is_one_line(self):
        plan = fn('void DrawPlan', 'void DrawPanel')
        for key in ('"entry"', '"sl"', '"tp"', '"r2"', '"entry_txt"', '"sl_txt"', '"tp_txt"', '"r2_txt"'):
            self.assertIn(key, plan)
        self.assertIn('(m_plan.tp_is_2r ? "TP = 2R " : "TP ")+EV_Price(m_plan.tp,m_digits)', plan)
        self.assertEqual(plan.count('if(!m_plan.tp_is_2r)'), 2, 'a separate 2R line and label only when TP is beyond 2R')
        self.assertIn('"HYRJA LIMIT "+ds+" "+EV_Price(m_plan.entry,m_digits)', plan)

    def test_there_is_a_legend_on_the_chart_that_explains_every_kind_of_mark(self):
        legend = PANEL
        for part in ("'H4'", 'Sweep H4', 'Fitil H4', 'Thyerje M15', 'ARTE', 'HYRJA LIMIT / SL / 2R / TP', 'kandidat', 'rikonfirmuar', 'pavlefshme'):
            self.assertIn(part, legend, part)
        self.assertIn('m_legend.Line(', legend)
        self.assertIn('EV_PANEL_PREFIX+"leg_"', VIEW)


class ConfirmedAndTemporaryWordsEqualThePresetLabels(unittest.TestCase):
    def labels(self):
        _, labels, _ = pc.parse_preset(pc.SIMULATION_PRESET)
        return labels

    def test_what_the_panel_calls_confirmed_is_confirmed_and_what_it_calls_temporary_is_a_proposal(self):
        lab = self.labels()
        panel = PANEL
        conf = re.search(r'"Konfirmuar nga klienti: ([^"]+)"', panel).group(1)
        temp = re.search(r'"E perkohshme \(prototip\): ([^"]+)"', panel).group(1)
        for word, key in (('hyrja LIMIT ne skaj te FVG', 'InpEntryEdge'), ('seanca', 'InpSessionClock'), ('lajmet', 'InpNewsCalendar'), ('kufijte ditore', 'InpMaxPositions')):
            self.assertIn(word, conf)
            self.assertEqual(lab[key], 'CONFIRMED', key)
        for word, key in (('burimi H4', 'InpContextSource'), ('niveli M15 i thyer', 'InpM15Level'), ('zgjedhja e FVG', 'InpCandidate'), ('SL', 'InpSlRule'), ('TP/2R', 'InpTargetRule'), ('risku 1%', 'InpRiskSource')):
            self.assertIn(word, temp)
            self.assertEqual(lab[key], 'DEMO-PROPOSAL', key)

    def test_the_risk_line_names_the_simulation_policy(self):
        panel = PANEL
        self.assertIn('(out.risk_label!="" ? " ("+out.risk_label+": 1% e balances)" : "")', panel)


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
            self.assertEqual(hashlib.sha256(code(base).encode('ascii')).hexdigest(), BASE_SHA256, 'the recorded hash is the hash of the base')
        except subprocess.CalledProcessError:
            base = None                                    # no git base locally: the recorded hash of the base is used instead
        text = read('src', 'include', 'EntryOrchestratorFeed.mqh')
        text = re.sub(r'   // chart view only \(InpChartView\)[^\n]*\n(?:   (?:bool keep_view|bool dv_have|int dv_n|SH3Eval dv_ev|SH3Track dv_tracks\[\]|SH3Event dv_events\[\])[^\n]*\n)+', '', text)
        text = re.sub(r'   // copy for the chart view;[^\n]*\n   void KeepView\(.*?\n     \}\n(?=   void T003View)', '', text, flags=re.S)
        for line in ("      keep_view=false;                         // the EA switches it on AFTER Init when the chart view is requested\n", "      dv_n=0;\n", "      dv_have=false;\n",
                     "      if(keep_view) KeepView(n,e,tracks,events);\n"):
            self.assertIn(line, text, line)
            text = text.replace(line, '', 1)
        self.assertEqual(hashlib.sha256(code(text).encode('ascii')).hexdigest(), BASE_SHA256, 'the feed differs from the base outside the view additions')

    def test_the_copy_is_gated_and_nothing_in_the_decision_reads_it(self):
        self.assertEqual(len(re.findall(r'if\(keep_view\) KeepView\(', FEED)), 1)
        body = FEED[FEED.index('bool Build('):FEED.index('bool Poll(bool &feed_ok)')]
        self.assertNotIn('dv_', body, 'Build does not read the view copies')
        self.assertNotIn('keep_view', body)
        self.assertNotIn('dv_', FEED[FEED.index('bool Poll(bool &feed_ok)'):FEED.index('struct SEoMarketCfg')])
        self.assertNotIn('dv_', EA)


class CodexReviewRegressions(unittest.TestCase):
    """Codex review of eeddf39: (1) Comment() under the panel, (2) a panel without background that does not fit the chart, (3) every request called virtual whatever the transport"""

    def test_1_status_clears_the_comment_when_the_view_is_on_and_keeps_the_text_when_it_is_off(self):
        status = EA[EA.index('void Status('):EA.index('bool Configure(void)')]
        self.assertIn('if(InpChartView) Comment("");', status)
        self.assertRegex(status, r'else\s+Comment\(\(g_real_entry \? "T016 ENTRY ORCHESTRATOR - REAL DEMO ORDERS ENABLED BY THE OWNER\\n" : "T016 ENTRY ORCHESTRATOR - FAKE EXECUTION ONLY, nothing is sent to the terminal\\n"\)')
        self.assertIn('Print("T016 ",text);', status, 'the diagnostics stay in the Experts log')
        self.assertLess(status.index('Print("T016 ",text);'), status.index('Comment('))
        self.assertEqual(EA.count('Comment('), 3, 'Status (view on / off) and OnDeinit only')
        self.assertEqual(EA.count('Comment("")'), 2)

    def test_2_the_panel_has_a_background_and_fits_the_chart_inside_the_view(self):
        self.assertNotIn('CStatusPanel', VIEW)
        self.assertNotIn('StatusPanel.mqh', VIEW)
        self.assertIn('class CEvBox', VIEW)
        self.assertIn('OBJ_RECTANGLE_LABEL', VIEW)
        self.assertIn('CHART_WIDTH_IN_PIXELS', VIEW)
        self.assertIn('CHART_HEIGHT_IN_PIXELS', VIEW)
        self.assertIn('int EV_Select(', VIEW)
        self.assertIn('int EV_Wrap(', VIEW)
        box = VIEW[VIEW.index('class CEvBox'):VIEW.index('class CEoView')]
        self.assertIn('EV_Select(', box, 'the box chooses its rows by the space it has')
        self.assertIn('BGCOLOR', box)
        self.assertEqual(len(re.findall(r'new CStatusPanel|CStatusPanel ', read('src', 'include', 'EntryOrchestratorView.mqh'))), 0)
        draw = PANEL
        self.assertLess(draw.index('m_legend.Render('), draw.index('m_panel.Render('), 'the legend is laid out first; the panel takes the rest of the height')
        self.assertIn('CORNER_LEFT_UPPER', box, 'one corner for every object: no corner-dependent anchor is assumed')
        self.assertNotIn('CORNER_LEFT_LOWER', VIEW)
        self.assertIn('priority', RAW.lower())

    def test_3_the_verdict_and_the_kept_plan_carry_the_mode_of_the_request(self):
        self.assertIn('void EV_Verdict(const SEoOutcome &o,const SEvPlan &kept,const bool real,string &label,string &reason)', VIEW)
        verdict = fn('void EV_Verdict', 'color EV_VerdictColor')
        self.assertRegex(verdict, r'if\(o\.request\)\s*\{\s*if\(real\)\s*\{label="KERKESE REALE"')
        self.assertIn('label="KERKESE VIRTUALE"', verdict)
        self.assertLess(verdict.index('label="KERKESE REALE"'), verdict.index('label="KERKESE VIRTUALE"'))
        self.assertIn('bool     real;', RAW.replace('\t', ' '))
        track = fn('void TrackPlan', 'int FindH4Bar')
        self.assertIn('const bool real', track)
        self.assertIn('m_plan.real=real;', track)
        self.assertIn('EV_Verdict(out,m_plan,real,m_plan.verdict,m_plan.reason);', track)
        self.assertIn('TrackPlan(out,feed,real_entry);', VIEW)
        panel = PANEL
        self.assertIn('EV_Verdict(out,m_plan,real_entry,label,reason);', panel)
        self.assertIn('modaliteti: ', panel)
        self.assertIn('"REAL (DEMO)"', panel)
        self.assertIn('"FAKE (virtuale)"', panel)
        self.assertEqual(VIEW.count('KERKESE REALE'), 2, 'the verdict and its colour: no other place may use the word')

    def test_the_layout_helpers_are_mirrored_in_python_and_in_the_mt5_test(self):
        for name in ('EV_Wrap', 'EV_Select'):
            self.assertIn(name, TEST_RAW)
        mirror = read('tests', 'view_layout_reference.py')
        self.assertIn('def wrap(', mirror)
        self.assertIn('def select(', mirror)
        for needle in ('layout: a long line wraps', 'layout: low priorities leave first', 'layout: priority 0 is never dropped', 'layout: a wide chart keeps every line',
                       'KERKESE REALE', 'modaliteti: REAL (DEMO)', 'modaliteti: FAKE (virtuale)'):
            self.assertIn(needle, TEST_RAW, needle)


class TheSyntheticMt5Test(unittest.TestCase):
    def test_it_is_a_labelled_synthetic_script_that_touches_nothing_but_the_view(self):
        self.assertIn('SYNTHETIC', TEST_RAW)
        self.assertIn('NOT a signal', TEST_RAW)
        for w in ('OrderSend', 'CTrade', 'AccountInfo', 'PositionsTotal', 'OrdersTotal', 'CopyRates', 'Calendar', 'FileOpen', 'GlobalVariableSet', 'SendNotification', 'H3Evaluate', 'M4ReplayTimeline',
                  'SPB_', 'g_orch', 'EG_Submit'):
            self.assertNotIn(w, TEST, w)
        self.assertEqual(re.findall(r'#include "([^"]+)"', TEST), ['../include/EntryOrchestratorView.mqh'])
        self.assertIn('void OnStart()', TEST)
        for w in ('OnTick', 'OnTimer'):
            self.assertNotIn(w, TEST)
        deleted = re.findall(r'ObjectDelete\(0,([^)]*)\)', TEST)
        self.assertEqual(sorted(set(deleted)), ['"MANUAL_VIEW_TEST_LINE"', 'banner'])

    def test_it_covers_the_requested_scenarios_and_the_assertions_of_the_requested_criteria(self):
        for scen in ('WAIT_CONTEXT SELL', 'WAIT_CONTEXT BUY', 'BUY accepted, TP = 2R', 'SELL accepted, TP = 2R', 'BUY accepted, TP beyond 2R', 'SELL accepted, TP beyond 2R',
                     'BUY blocked by the gate', 'SELL blocked by the gate'):
            self.assertIn(scen, TEST_RAW)
        for needle in ('SIMULIM - PA URDHRA REALE', 'VENDIMI: PRET', 'VENDIMI: BLLOKUAR', 'VENDIMI: KERKESE VIRTUALE', 'CountGoldZones()==1', 'CountGoldZones()==0', 'no entry arrow',
                       'the manual drawing is untouched', 'Thyerje M15', 'NUK eshte MSS', 'TP = 2R ', 'no M15 level, no zone, no plan line is invented', 'trajtuar me pare',
                       'the swept level is dashed', 'the legend is on the chart'):
            self.assertIn(needle, TEST_RAW, needle)

    def test_the_scenario_names_exist_for_the_screenshots_and_the_hold_is_off_by_default(self):
        self.assertIn('input int InpHoldSeconds=0;', TEST)
        self.assertEqual(len(re.findall(r'RunScenario\(view,', TEST)), 8)


if __name__ == '__main__':
    unittest.main()
