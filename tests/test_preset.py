"""The FAKE/READ_ONLY demo preset of XauUsdEntryOrchestrator: complete, labelled, no input of the EA blocks, no real transport; every required input, reverted to its UNSET default, blocks (offline
rules AND, where the Python mirror can see it, the mirrored pipeline). The rules in tests/preset_check.py are pinned to the EA source."""
import os
import itertools
import re
import sys
import unittest
from dataclasses import replace

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import entry_gate_reference as eg  # noqa: E402
import entry_reference as en  # noqa: E402
import eo_reference as eo  # noqa: E402
import preset_check as pc  # noqa: E402
import spb_reference as sp  # noqa: E402
import t007_planning_reference as tp  # noqa: E402
import test_eo as teo  # noqa: E402
import t004_reference as m4  # noqa: E402 (via test_eo)

EA, ENUMS = pc.parse_ea()
VALUES, LABELS, DUPS = pc.parse_preset()
V = pc.typed(VALUES, EA)


def read(*parts):
    with open(os.path.join(pc.ROOT, *parts), encoding='ascii') as f:
        return f.read()


def with_default(name, base=None):
    v = dict(base or V)
    v[name] = EA[name][1]
    return v


def pipeline(v, direction):
    """the mirrored chain with the values of an input set -> the step outcome of the first real signal"""
    w = teo.World(direction)
    src = {1: 'T003_PROTOTYPE'}.get(v['InpContextSource'], '')
    sel = sp.Selection(context_source=src, swing_selector=sp.SWING_LATEST_FRACTAL_PROPOSAL if v['InpM15Level'] == 1 else sp.SWING_UNSET,
                       timing_policy=m4.A_AT_OR_AFTER_BREAK if v['InpFvgTiming'] == 1 else m4.UNSET, candidate_selector=sp.CAND_SOLE_ELIGIBLE if v['InpCandidate'] == 2 else sp.CAND_UNSET,
                       entry_edge={1: sp.EDGE_NEAR_SIDE, 2: sp.EDGE_FAR_SIDE}.get(v['InpEntryEdge'], sp.EDGE_UNSET), sl_rule=sp.SL_BROKEN_LEVEL_PRICE if v['InpSlRule'] == 1 else sp.SL_UNSET,
                       sl_buffer_set=v['InpSlBuffer'] >= 0, sl_buffer=max(0.0, v['InpSlBuffer']), target_rule=sp.TGT_NONE_2R_MINIMUM if v['InpTargetRule'] == 1 else sp.TGT_UNSET,
                       live_after=teo.START)
    w.cfg = eo.Config(sel=sel, risk_budget=v['InpRiskBudget'], risk_source=v['InpRiskSource'], lot_cap=v['InpLotCap'], model_tolerance=v['InpModelTolerance'], max_quote_age=v['InpMaxQuoteAgeSeconds'],
                      open_positions=0, trades_today=v['InpTradesToday'], existing_risk=0.0, max_positions=v['InpMaxPositions'], max_trades=v['InpMaxTrades'], risk_cap=v['InpCombinedRiskCap'],
                      gate=eg.GateConfig(max_age=v['InpGateMaxAgeSeconds']),
                      exec=en.Config(enabled=True, ea_magic=v['InpEaMagic'], symbol='XAUUSD', filling=en.FILL_RETURN if v['InpFilling'] == 1 else en.FILL_UNSET,
                                     expiry_mode=en.EXP_GTC if v['InpExpiryMode'] == 1 else en.EXP_UNSET, permit_max_age=v['InpPermitMaxAgeSeconds'], quote_max_age=v['InpMaxQuoteAgeSeconds']))
    w.mk.session = tp.SESSION_OPEN if v['InpSessionClock'] else tp.SESSION_UNKNOWN
    w.mk.news = tp.NEWS_CLEAR if v['InpNewsCalendar'] else tp.NEWS_UNKNOWN
    w.mk.spread = tp.SPREAD_CLEAR if v['InpMaxSpreadPoints'] > 0 else tp.SPREAD_UNKNOWN
    daily_items = [b for b in pc.blockers(v) if b[1].startswith('InpDaily') and b[1] != 'InpDailyBridge']
    if daily_items or not v['InpDailyHistoryBridge']:
        w.mk.daily_result = (False, w.mk.daily_result[1])
    w.mk.bal = eo.Balance(True, 10000.0, w.tr.now, True)
    ob, lvl, out = w.live_candidate(unittest.TestCase())
    return out


class Preset(unittest.TestCase):
    def test_the_preset_lists_every_input_once_with_a_label_and_valid_enum_values(self):
        problems, bl, v = pc.report()
        self.assertEqual(problems, [])
        self.assertEqual(DUPS, [])
        self.assertEqual(set(VALUES), set(EA))
        for n, lab in LABELS.items():
            self.assertIn(lab, pc.LABELS, n)

    def test_no_input_of_the_ea_blocks_the_plan_and_the_gate(self):
        self.assertEqual(pc.blockers(V), [])

    def test_the_preset_keeps_every_real_transport_off(self):
        self.assertEqual((V['InpEntryTransport'], V['InpEntryAuthorisation'], V['InpManagementTransport'], V['InpManagementConfirmAutoSend'], V['InpManagementRegistration'],
                          V['InpManagementAuthorisation']), (0, '', 0, False, False, ''))
        self.assertEqual(V['InpRiskSource'], 1)
        self.assertEqual(V['InpAcknowledgeLifecycleHalt'], False)

    def test_demo_proposals_and_open_client_questions_are_labelled(self):
        for n in ('InpContextSource', 'InpM15Level', 'InpFvgTiming', 'InpCandidate', 'InpSlRule', 'InpSlBuffer', 'InpTargetRule', 'InpRiskSource', 'InpPendingPolicy', 'InpPendingRiskPolicy',
                  'InpMaxTrades', 'InpDailyResultFormula'):
            self.assertEqual(LABELS[n], 'DEMO-PROPOSAL', n)
        for n in ('InpEntryEdge', 'InpLotCap', 'InpMaxPositions', 'InpSessionClock', 'InpNewsCalendar', 'InpDailyHistoryBridge', 'InpCancelOnDirectionChange', 'InpCancelOnOppositeSignal'):
            self.assertEqual(LABELS[n], 'CONFIRMED', n)
        text = read('src', 'presets', 'XauUsdEntryOrchestrator_demo_fake.set')
        self.assertIn('NOTHING HERE IS A CLIENT APPROVAL FOR LIVE', text)

    def test_every_required_input_blocks_when_it_returns_to_its_unset_default(self):
        required = []
        for n in EA:
            if pc.blockers(with_default(n)):
                required.append(n)
        for n in ('InpContextSource', 'InpM15Level', 'InpFvgTiming', 'InpCandidate', 'InpEntryEdge', 'InpSlRule', 'InpSlBuffer', 'InpTargetRule', 'InpRiskSource', 'InpLotCap', 'InpModelTolerance',
                  'InpMaxQuoteAgeSeconds', 'InpGateMaxAgeSeconds', 'InpPermitMaxAgeSeconds', 'InpPendingPolicy', 'InpPendingRiskPolicy', 'InpTradesToday', 'InpMaxPositions', 'InpMaxTrades',
                  'InpCombinedRiskCap', 'InpSessionClock', 'InpNewsCalendar', 'InpMaxSpreadPoints', 'InpDailyHistoryBridge', 'InpDailyEaMagic', 'InpDailyServerOffsetSeconds',
                  'InpDailyHistoryComplete', 'InpDailyResultFormula', 'InpDailyClassification', 'InpDailyWins', 'InpDailyConsecutiveLosses', 'InpEaMagic', 'InpFilling', 'InpExpiryMode',
                  'InpExposureSource'):
            if n == 'InpExposureSource':
                continue                                                         # the explicit snapshot is a valid alternative source: its own inputs block instead
            self.assertIn(n, required, n)
        for n in ('InpRiskBudget', 'InpOpenPositions', 'InpExistingRisk', 'InpManagementRegistration', 'InpEntryTransport', 'InpManagementTransport', 'InpCancelOnSessionEnd', 'InpPollSeconds',
                  'InpAcknowledgeLifecycleHalt', 'InpMgmtFilling', 'InpMgmtDeviation', 'InpMgmtFilterPolicy'):
            self.assertNotIn(n, required, n + ' is not needed to reach the plan and the gate of the FAKE preset')

    def test_the_mirrored_pipeline_reaches_a_fake_request_with_the_preset_values(self):
        for d in (1, -1):
            out = pipeline(V, d)
            self.assertEqual((out.status, out.request), ('EXECUTOR', True), '%d: %s %s' % (d, out.status, out.reason))
            self.assertEqual((out.risk_budget, out.risk_base), (100.0, 10000.0))

    def test_every_input_the_mirror_can_see_blocks_the_pipeline_when_unset(self):
        visible = ('InpContextSource', 'InpM15Level', 'InpFvgTiming', 'InpCandidate', 'InpEntryEdge', 'InpSlRule', 'InpSlBuffer', 'InpTargetRule', 'InpLotCap', 'InpModelTolerance',
                   'InpMaxQuoteAgeSeconds', 'InpGateMaxAgeSeconds', 'InpPermitMaxAgeSeconds', 'InpTradesToday', 'InpMaxPositions', 'InpMaxTrades', 'InpCombinedRiskCap', 'InpSessionClock',
                   'InpNewsCalendar', 'InpMaxSpreadPoints', 'InpDailyHistoryBridge', 'InpDailyServerOffsetSeconds', 'InpDailyHistoryComplete', 'InpDailyResultFormula', 'InpDailyClassification',
                   'InpDailyWins', 'InpDailyConsecutiveLosses', 'InpFilling', 'InpExpiryMode')
        for d in (1, -1):
            for n in visible:
                v = with_default(n)
                if n == 'InpExpiryMode':
                    v[n] = 0
                out = pipeline(v, d)
                self.assertFalse(out.request, '%s dir %d: the mirrored pipeline still placed a request' % (n, d))
            v = with_default('InpRiskSource')                                  # source back to the explicit amount, whose default (-1) blocks
            self.assertFalse(pipeline(v, d).request)

    def test_turning_the_registration_on_needs_only_the_phrase_and_the_policy(self):
        v = dict(V, InpManagementRegistration=True, InpManagementAuthorisation=pc.EX_PHRASE, InpManagementRPolicy=1)
        self.assertEqual(pc.blockers(v), [])
        for n in ('InpManagementAuthorisation', 'InpManagementRPolicy'):
            self.assertTrue(pc.blockers(dict(v, **{n: EA[n][1]})), n)

    def test_the_default_ea_inputs_alone_block_everything(self):
        defaults = {n: d for n, (t, d) in EA.items()}
        self.assertGreater(len(pc.blockers(defaults)), 15)

    def test_the_offline_rules_are_pinned_to_the_ea_source(self):
        ea = re.sub(r'//[^\n]*', '', read('src', 'XauUsdEntryOrchestrator.mq5'))
        core = re.sub(r'//[^\n]*', '', read('src', 'include', 'EntryOrchestrator.mqh'))
        for frag in ('if(InpEntryAuthorisation!=EN_AUTH_PHRASE || !InpManagementRegistration || InpEaMagic<=0 || InpFilling!=EOI_FILL_RETURN) return(false);',
                     'if(InpManagementTransport==EOI_MTR_BROKER_DEMO && (!InpManagementConfirmAutoSend || !InpManagementRegistration)) return(false);',
                     'if(InpManagementAuthorisation!=EX_AUTH_PHRASE || InpManagementRPolicy!=EOI_MGMT_RPOL_R_GEOM || InpEaMagic<=0) return(false);',
                     'if(InpMgmtFilling==EX_FILL_UNSET', 'InpMgmtDeviation<0) return(false);', 'InpMgmtFilterPolicy==EX_POL_UNSET', 'g_cfg.risk_source=(int)InpRiskSource;',
                     'g_cfg.exec.filling=(InpFilling==EOI_FILL_RETURN ? EN_FILL_RETURN : EN_FILL_UNSET);', 'g_cfg.exec.permit_max_age=InpPermitMaxAgeSeconds;', 'g_cfg.gate.max_age=InpGateMaxAgeSeconds;'):
            self.assertIn(frag, ea)
        for frag in ('c.risk_source==EO_RISK_SOURCE_AMOUNT && !(c.risk_budget>0.0)', 'if(!(c.lot_cap>0.0))', 'c.model_tolerance>=0.0 && c.model_tolerance<=1.0', 'if(!(c.max_quote_age>0))',
                     'bal.read_ok && (bal.demo || sim) && TG_Finite(bal.amount) && bal.amount>0.0 && now-bal.time>=0 && now-bal.time<=c.max_quote_age', 'budget=bal.amount*EO_RISK_PCT_DEMO/100.0;',
                     'chk.risk_budget=budget;', 'm.risk_budget=budget;'):
            self.assertIn(frag, core)
        self.assertIn('#define EO_RISK_PCT_DEMO 1.0', core)
        self.assertIn('AccountInfoDouble(ACCOUNT_BALANCE)', ea)
        self.assertIn('ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_DEMO', ea)
        self.assertIn('class CEoDemoMarket : public CEoRealMarket', ea)


class SimulationPreset(unittest.TestCase):
    """the SIMULATION ONLY preset (account 358175: portal DEMO, MT5 REAL): complete, labelled, push OFF, FAKE / READ_ONLY, and the policy cannot be combined with any real transport"""

    def setUp(self):
        self.values, self.labels, self.dups = pc.parse_preset(pc.SIMULATION_PRESET)
        self.v = pc.typed(self.values, EA)

    def test_complete_labelled_and_nothing_blocks(self):
        problems, bl, v = pc.report(pc.SIMULATION_PRESET)
        self.assertEqual((problems, bl, self.dups), ([], [], []))
        self.assertEqual(set(self.values), set(EA))

    def test_push_off_fake_read_only_and_the_policy_is_simulation(self):
        v = self.v
        self.assertEqual((v['InpRiskSource'], v['InpPushNotifications'], v['InpEntryTransport'], v['InpManagementTransport'], v['InpManagementConfirmAutoSend'], v['InpEntryAuthorisation'],
                          v['InpManagementRegistration']), (2, False, 0, 0, False, '', False))
        text = read('src', 'presets', 'XauUsdEntryOrchestrator_simulation_fake.set')
        for frag in ('SIMULATION ONLY', '358175', 'NOT a demo proof', 'NOT a client confirmation', 'NOT a live approval'):
            self.assertIn(frag, text)

    def test_it_differs_from_the_demo_preset_in_the_risk_source_and_the_measured_offset_only(self):
        demo, _, _ = pc.parse_preset()
        sim = self.values
        self.assertEqual({k for k in demo if demo[k] != sim.get(k)}, {'InpRiskSource', 'InpDailyServerOffsetSeconds'}, 'only the risk source and the offset MEASURED on Tauro differ')

    def test_every_real_transport_combination_with_the_simulation_policy_is_refused(self):
        for entry, mgmt, confirm, phrase in itertools.product((0, 1), (0, 1), (False, True), ('', pc.EN_PHRASE)):
            v = dict(self.v, InpEntryTransport=entry, InpManagementTransport=mgmt, InpManagementConfirmAutoSend=confirm, InpEntryAuthorisation=phrase)
            refused = any(b[1] == 'InpRiskSource' and 'SIMULATION ONLY' in b[2] for b in pc.blockers(v))
            self.assertEqual(refused, (entry, mgmt, confirm, phrase) != (0, 0, False, ''), (entry, mgmt, confirm, phrase))

    def test_the_demo_policy_and_the_real_transport_rules_are_unchanged_by_the_simulation_policy(self):
        base = dict(self.v, InpRiskSource=1)
        for entry, mgmt, confirm, phrase in itertools.product((0, 1), (0, 1), (False, True), ('', pc.EN_PHRASE)):
            v = dict(base, InpEntryTransport=entry, InpManagementTransport=mgmt, InpManagementConfirmAutoSend=confirm, InpEntryAuthorisation=phrase)
            sim = dict(v, InpRiskSource=2)
            demo_items = [b for b in pc.blockers(v)]
            sim_items = [b for b in pc.blockers(sim) if not (b[1] == 'InpRiskSource')]
            self.assertEqual(demo_items, sim_items, 'the real-transport requirements (phrase, registration, confirmation, magic, filling) are evaluated identically: %s' % ((entry, mgmt, confirm, phrase),))
            self.assertFalse(any(b[1] == 'InpRiskSource' for b in demo_items), 'the DEMO policy adds no simulation refusal')

    def test_the_configure_source_pins_the_combination_and_leaves_the_real_gates_alone(self):
        ea = re.sub(r'//[^\n]*', '', read('src', 'XauUsdEntryOrchestrator.mq5'))
        frag = 'if(InpRiskSource==EOI_RISK_SIMULATION_1PCT_CURRENT_BALANCE && (InpEntryTransport!=EOI_ETR_FAKE || InpManagementTransport!=EOI_MTR_READ_ONLY || InpManagementConfirmAutoSend || InpEntryAuthorisation!="")) return(false);'
        self.assertIn(frag, ea)
        conf = ea[ea.index('bool Configure(void)'):ea.index('SEoFeedCfg fc;')]
        self.assertLess(conf.index(frag), conf.index('g_trp=GetPointer(g_etr)'), 'the refusal comes before any real transport is selected')
        # the real-transport selection rules are exactly the ones of before
        self.assertIn('if(InpEntryAuthorisation!=EN_AUTH_PHRASE || !InpManagementRegistration || InpEaMagic<=0 || InpFilling!=EOI_FILL_RETURN) return(false);', conf)
        self.assertIn('if(InpManagementTransport==EOI_MTR_BROKER_DEMO && (!InpManagementConfirmAutoSend || !InpManagementRegistration)) return(false);', conf)
        self.assertIn('g_cfg.exec.real_authorised=g_real_entry;', ea)
        self.assertNotIn('SIMULATION', re.sub(r'//[^\n]*', '', read('src', 'include', 'EntryExecutor.mqh')))
        self.assertNotIn('SIMULATION', re.sub(r'//[^\n]*', '', read('src', 'include', 'ExitExecutor.mqh')))
        self.assertIn('b.trade_mode=(int)raw_mode;', ea)
        self.assertIn('SIMULATION ONLY', ea)


if __name__ == '__main__':
    unittest.main()
