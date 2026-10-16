"""OFFLINE preset check for XauUsdEntryOrchestrator: replays the EA's own blocking rules (Configure, EO_UnsetConfig, the SetupPlanBridge selection, the gate inputs, the filters, the T012 daily source)
over a .set file and lists everything that would still block, so that an MT5 round never has to discover an UNSET input. It reads the EA source for the input list and the defaults, so a new input
without a preset line is reported. Usage: python3 tests/preset_check.py [preset.set]   (default: the FAKE/READ_ONLY demo preset).
The rules are a PYTHON REPLICA of the MQL5 conditions (pinned by tests/test_preset.py against the EA source); it proves nothing about the broker, the calendar or the history, which are listed as
PRE-STEPS that only the terminal can answer."""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EA = os.path.join(ROOT, 'src', 'XauUsdEntryOrchestrator.mq5')
EXIT_EXECUTOR = os.path.join(ROOT, 'src', 'include', 'ExitExecutor.mqh')
DEFAULT_PRESET = os.path.join(ROOT, 'src', 'presets', 'XauUsdEntryOrchestrator_demo_fake.set')
SIMULATION_PRESET = os.path.join(ROOT, 'src', 'presets', 'XauUsdEntryOrchestrator_simulation_fake.set')
LABELS = ('CONFIRMED', 'DEMO-PROPOSAL', 'TECHNICAL', 'OFF', 'OWNER-FILL', 'MANUAL-DAILY', 'NOT-USED')
EN_PHRASE = 'I_AUTHORISE_REAL_ENTRY_ORDERS_ON_THIS_DEMO_ACCOUNT'
EX_PHRASE = 'I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE'
FORMULAS = ('PROFIT', 'PROFIT_COMMISSION_SWAP', 'PROFIT_COMMISSION_SWAP_FEE')

# which client question (docs/EA_INTEGRATION_PLAN.md list B) a blocking input belongs to
DECISION = {'InpContextSource': 'D4', 'InpM15Level': 'D5', 'InpFvgTiming': 'D5', 'InpCandidate': 'D5', 'InpEntryEdge': 'point 5', 'InpSlRule': 'D6', 'InpSlBuffer': 'D6', 'InpTargetRule': 'D7',
            'InpRiskBudget': 'D2', 'InpRiskSource': 'D2', 'InpLotCap': 'S:66-68', 'InpPendingPolicy': 'D3', 'InpPendingRiskPolicy': 'D3', 'InpMaxTrades': 'D1', 'InpMaxPositions': 'S:70',
            'InpCombinedRiskCap': 'S:71', 'InpDailyResultFormula': 'D12', 'InpDailyClassification': 'D12', 'InpDailyWins': 'D12', 'InpDailyConsecutiveLosses': 'D12', 'InpTradesToday': 'D12',
            'InpSessionClock': 'S:86-94', 'InpNewsCalendar': 'S:95-98', 'InpMaxSpreadPoints': 'S:39,176', 'InpDailyHistoryBridge': 'S:73-83'}


def parse_enums(*paths):
    enums = {}
    for path in paths:
        text = open(path, encoding='ascii').read()
        for m in re.finditer(r'enum\s+(\w+)\s*\{([^}]*)\}', text):
            members, nxt = {}, 0
            for part in m.group(2).split(','):
                part = re.sub(r'//[^\n]*', '', part).strip()
                if not part:
                    continue
                if '=' in part:
                    k, v = part.split('=')
                    nxt = int(v.strip())
                    members[k.strip()] = nxt
                else:
                    members[part] = nxt
                nxt += 1
            enums[m.group(1)] = members
    return enums


def parse_ea(path=EA):
    """-> ordered dict name -> (type, default) with enum defaults resolved to their numbers"""
    enums = parse_enums(path, EXIT_EXECUTOR)
    out = {}
    for m in re.finditer(r'^input\s+(\w+)\s+(\w+)\s*=\s*([^;]+);', open(path, encoding='ascii').read(), re.M):
        typ, name, raw = m.group(1), m.group(2), m.group(3).strip()
        if typ in enums:
            out[name] = (typ, enums[typ][raw])
        elif typ == 'bool':
            out[name] = (typ, raw == 'true')
        elif typ == 'string':
            out[name] = (typ, raw.strip('"'))
        elif typ in ('int', 'long'):
            out[name] = (typ, int(raw))
        else:
            out[name] = (typ, float(raw))
    return out, enums


def parse_preset(path=DEFAULT_PRESET):
    """-> (values as strings, labels, duplicates); a label comment applies to the keys that follow it until the next label comment"""
    values, labels, dups, label = {}, {}, [], None
    for line in open(path, encoding='ascii').read().splitlines():
        if line.startswith(';'):
            m = re.match(r';\s*\[([A-Z-]+)[^\]]*\]', line)
            if m:
                label = m.group(1)
            continue
        if not line.strip():
            continue
        k, _, v = line.partition('=')
        if k in values:
            dups.append(k)
        values[k] = v
        labels[k] = label
    return values, labels, dups


def typed(values, ea):
    out = {}
    for name, (typ, default) in ea.items():
        if name not in values:
            out[name] = default
            continue
        raw = values[name]
        if typ == 'bool':
            out[name] = raw.strip().lower() == 'true'
        elif typ == 'string':
            out[name] = raw
        elif typ in ('int', 'long') or typ.startswith('ENUM_') or typ.startswith('ENUM'):
            out[name] = int(raw)
        else:
            out[name] = float(raw)
    return out


def blockers(v):
    """-> list of (stage, input or item, why). Empty = nothing in the EA's own rules blocks. A PYTHON REPLICA of the MQL5 conditions."""
    b = []

    def add(stage, item, why):
        b.append((stage, item, why))
    # ---- Configure() refusals: the EA does not start
    if v['InpRiskSource'] not in (0, 1, 2):
        add('START', 'InpRiskSource', 'unknown value')
    if v['InpRiskSource'] == 2 and (v['InpEntryTransport'] != 0 or v['InpManagementTransport'] != 0 or v['InpManagementConfirmAutoSend'] or v['InpEntryAuthorisation'] != ''):
        add('START', 'InpRiskSource', 'SIMULATION ONLY is allowed only with the FAKE entry transport, the READ_ONLY management transport, no confirmation and no entry phrase')
    if v['InpEntryTransport'] not in (0, 1) or v['InpManagementTransport'] not in (0, 1):
        add('START', 'InpEntryTransport/InpManagementTransport', 'unknown value')
    if v['InpEntryTransport'] == 1 and (v['InpEntryAuthorisation'] != EN_PHRASE or not v['InpManagementRegistration'] or v['InpEaMagic'] <= 0 or v['InpFilling'] != 1):
        add('START', 'InpEntryTransport', 'BROKER_DEMO needs the phrase, registration on, magic > 0, filling RETURN')
    if v['InpManagementTransport'] == 1 and (not v['InpManagementConfirmAutoSend'] or not v['InpManagementRegistration']):
        add('START', 'InpManagementTransport', 'BROKER_DEMO needs the confirmation and registration on')
    if v['InpManagementRegistration']:
        if v['InpManagementAuthorisation'] != EX_PHRASE:
            add('START', 'InpManagementAuthorisation', 'registration needs the T011 phrase')
        if v['InpManagementRPolicy'] != 1:
            add('START', 'InpManagementRPolicy', 'registration needs R_GEOM (1)')
        if v['InpEaMagic'] <= 0:
            add('START', 'InpEaMagic', 'registration needs magic > 0')
        if v['InpMgmtFilling'] not in (1, 2, 3):
            add('START', 'InpMgmtFilling', 'UNSET')
        if v['InpMgmtDeviation'] < 0:
            add('START', 'InpMgmtDeviation', 'UNSET')
        if v['InpMgmtFilterPolicy'] not in (1, 2):
            add('START', 'InpMgmtFilterPolicy', 'UNSET')
        if v['InpMgmtFilterState'] not in (0, 1, 2):
            add('START', 'InpMgmtFilterState', 'unknown value')
    if v['InpExposureSource'] not in (0, 1):
        add('START', 'InpExposureSource', 'unknown value')
    if v['InpPendingPolicy'] not in (0, 1, 2):
        add('START', 'InpPendingPolicy', 'unknown value')
    if v['InpPendingRiskPolicy'] not in (0, 1, 2):
        add('START', 'InpPendingRiskPolicy', 'unknown value')
    src, bars = v['InpContextSource'], v
    feed_ok = (1 <= src <= 3 and v['InpM15Level'] == 1 and v['InpFvgTiming'] == 1 and 50 <= bars['InpH4LookbackBars'] <= 1000 and 3 * bars['InpH4LookbackBars'] <= bars['InpH4RebuildBars'] <= 5000
               and 1 <= bars['InpH4LeftBars'] <= 10 and 1 <= bars['InpH4RightBars'] <= 10 and 1 <= bars['InpM15LeftBars'] <= 10 and 1 <= bars['InpM15RightBars'] <= 10
               and bars['InpM15LeftBars'] + bars['InpM15RightBars'] + 1 <= bars['InpM15LookbackBars'] <= 1000 and 10 <= bars['InpOrdinaryWarmBars'] <= 1000 and 16 <= bars['InpM15ReplayBars'] <= 5000)
    if not feed_ok:
        for n in ('InpContextSource', 'InpM15Level', 'InpFvgTiming'):
            if (n == 'InpContextSource' and not 1 <= src <= 3) or (n != 'InpContextSource' and v[n] != 1):
                add('START', n, 'UNSELECTED')
        if all(v[n] == 1 for n in ('InpM15Level', 'InpFvgTiming')) and 1 <= src <= 3:
            add('START', 'observer windows', 'outside the validated ranges')
    # ---- first Step(): EO_UnsetConfig and the selection
    if v['InpRiskSource'] == 0 and not v['InpRiskBudget'] > 0:
        add('STEP', 'InpRiskBudget', 'UNSET (-1)')
    if not v['InpLotCap'] > 0:
        add('STEP', 'InpLotCap', 'UNSET')
    if not 0 <= v['InpModelTolerance'] <= 1:
        add('STEP', 'InpModelTolerance', 'UNSET')
    if not v['InpMaxQuoteAgeSeconds'] > 0:
        add('STEP', 'InpMaxQuoteAgeSeconds', 'UNSET')
    if v['InpCandidate'] != 2:
        add('PLAN', 'InpCandidate', 'UNSELECTED')
    if v['InpEntryEdge'] not in (1, 2):
        add('PLAN', 'InpEntryEdge', 'UNSELECTED')
    if v['InpSlRule'] != 1:
        add('PLAN', 'InpSlRule', 'UNSELECTED')
    if v['InpSlBuffer'] < 0:
        add('PLAN', 'InpSlBuffer', 'UNSET (-1)')
    if v['InpTargetRule'] != 1:
        add('PLAN', 'InpTargetRule', 'UNSELECTED')
    # ---- executor / gate inputs
    if v['InpFilling'] != 1:
        add('EXECUTOR', 'InpFilling', 'UNSET (pending orders use RETURN)')
    if v['InpExpiryMode'] not in (1, 2) or (v['InpExpiryMode'] == 2 and v['InpExpirySeconds'] <= 0):
        add('EXECUTOR', 'InpExpiryMode', 'UNSET')
    if v['InpEaMagic'] <= 0:
        add('EXECUTOR', 'InpEaMagic', 'UNSET')
    if not v['InpPermitMaxAgeSeconds'] > 0:
        add('EXECUTOR', 'InpPermitMaxAgeSeconds', 'UNSET')
    if not v['InpGateMaxAgeSeconds'] > 0:
        add('GATE', 'InpGateMaxAgeSeconds', 'UNSET')
    if v['InpExposureSource'] == 1:
        if v['InpPendingPolicy'] == 0:
            add('GATE', 'InpPendingPolicy', 'UNSET (D3)')
        if v['InpPendingRiskPolicy'] == 0:
            add('GATE', 'InpPendingRiskPolicy', 'UNSET (D3)')
    else:
        if v['InpOpenPositions'] < 0:
            add('GATE', 'InpOpenPositions', 'unknown (-1)')
        if v['InpExistingRisk'] < 0:
            add('GATE', 'InpExistingRisk', 'unknown (-1)')
    if v['InpTradesToday'] < 0:
        add('GATE', 'InpTradesToday', 'unknown (-1)')
    if v['InpMaxPositions'] < 0:
        add('GATE', 'InpMaxPositions', 'UNSET')
    if v['InpMaxTrades'] < 0:
        add('GATE', 'InpMaxTrades', 'UNSET (D1)')
    if v['InpCombinedRiskCap'] < 0:
        add('GATE', 'InpCombinedRiskCap', 'UNSET')
    if not v['InpSessionClock']:
        add('GATE', 'InpSessionClock', 'session UNKNOWN')
    if not v['InpNewsCalendar']:
        add('GATE', 'InpNewsCalendar', 'news UNKNOWN')
    if not v['InpMaxSpreadPoints'] > 0:
        add('GATE', 'InpMaxSpreadPoints', 'spread UNKNOWN')
    # ---- the T012 daily source
    if not v['InpDailyHistoryBridge']:
        add('GATE', 'InpDailyHistoryBridge', 'no daily result')
    else:
        off = v['InpDailyServerOffsetSeconds']
        if v['InpDailyEaMagic'] <= 0:
            add('GATE', 'InpDailyEaMagic', 'UNSET')
        if off == 99999 or off % 900 != 0 or abs(off) > 14 * 3600:
            add('GATE', 'InpDailyServerOffsetSeconds', 'UNSET / invalid')
        if not v['InpDailyHistoryComplete']:
            add('GATE', 'InpDailyHistoryComplete', 'HISTORY_INCOMPLETE')
        if v['InpDailyResultFormula'] not in FORMULAS:
            add('GATE', 'InpDailyResultFormula', 'POLICY_UNSET (D12)')
        if v['InpDailyClassification'] != 'CALLER_CLASSIFIED':
            add('GATE', 'InpDailyClassification', 'POLICY_UNSET (D12)')
        if v['InpDailyWins'] < 0:
            add('GATE', 'InpDailyWins', 'unknown (-1)')
        if v['InpDailyConsecutiveLosses'] < 0:
            add('GATE', 'InpDailyConsecutiveLosses', 'unknown (-1)')
    return b


PRE_STEPS = [
    ('T012 day balance', 'run XauUsdT012BalanceStore (CAPTURE) once per Tirane day before the first signal; without the stored start-of-day balance the daily check blocks (BALANCE_START_UNSET). The -2% base is unchanged.'),
    ('manual daily counters', 'InpTradesToday / InpDailyWins / InpDailyConsecutiveLosses are NOT derived by the EA (D12); set them to the real counts of the Tirane day before the start.'),
    ('server offset', 'InpDailyServerOffsetSeconds must equal TimeTradeServer()-TimeGMT() of the broker (DST changes it); a wrong value does not block, it changes which deals count as today\'s.'),
    ('combined risk cap', 'InpCombinedRiskCap is an AMOUNT: 2% of the real balance, not a percentage; edit it when the balance changes.'),
    ('terminal', 'MT5 connected, XAUUSD.fx chart, algo trading allowed for reads, the USD economic calendar readable, hedging demo account (the executor refuses anything else).'),
    ('real fills', 'with TP at the 2R level of the plan T011 may refuse the registration of a REAL fill (TP_EQUALS_2R / TP_BEFORE_2R depends on the real fill price, D8); the FAKE transport never fills.'),
]


def report(path=DEFAULT_PRESET):
    ea, enums = parse_ea()
    values, labels, dups = parse_preset(path)
    problems = []
    for n in ea:
        if n not in values:
            problems.append('MISSING in the preset: ' + n)
    for n in values:
        if n not in ea:
            problems.append('UNKNOWN input in the preset: ' + n)
    for n in dups:
        problems.append('DUPLICATE in the preset: ' + n)
    for n, (typ, _) in ea.items():
        if typ in enums and n in values and int(values[n]) not in enums[typ].values():
            problems.append('%s=%s is not a member of %s' % (n, values[n], typ))
    for n in values:
        if labels.get(n) not in LABELS:
            problems.append('no label above ' + n)
    v = typed(values, ea)
    return problems, blockers(v), v


if __name__ == '__main__':
    p = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_PRESET
    problems, bl, v = report(p)
    print('PRESET', os.path.relpath(p, ROOT))
    for x in problems:
        print('  PROBLEM', x)
    for stage, item, why in bl:
        print('  BLOCKS %-8s %-32s %s %s' % (stage, item, why, DECISION.get(item, '')))
    if not problems and not bl:
        print('  no input of the EA blocks: the plan and the gate can be reached (the PRE-STEPS below are the only open items)')
    for name, text in PRE_STEPS:
        print('  PRE-STEP %-22s %s' % (name, text))
    sys.exit(1 if problems or bl else 0)
