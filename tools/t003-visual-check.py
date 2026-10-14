#!/usr/bin/env python3
"""Static checks for the T003 visual EA (src/XauUsdH4Bias.mq5, src/include/H4BiasDrawer.mqh).

NOT a compiler and NOT a runtime test: these read the source text only.
Usage: t003-visual-check.py CHECK FILE...   (exit 0 = clean, 1 = problems printed)

CHECK names: trading, isolation, flow, nopricefeed, collision, diag, nofrozen, disagree, liquidity, limited, layers,
             noclock, names, asof, compact, resize, labels, baseline, export, since
  trading      no order/trading API in executable code (comments stripped)
  isolation    chart-object deletion and creation are confined to the T003 prefix
  flow         live/historical flow: closed bars only, no live price, baseline cursor
  nopricefeed  no quote, tick, indicator-series or other-timeframe access
  collision    the T003 prefixes cannot collide with the T001/T002 prefixes
  nofrozen     no FROZEN / frozen / thaw text anywhere in the visual files (revision 10 removed the freeze)
  disagree     MODEL DISAGREEMENT: the definition (BULLISH vs BEAR, BEARISH vs BULL only), the text, once-per-change log
  liquidity    the historical liquidity layer is read-only, wick-based, limited, switchable, prefix-only, labelled
  limited      LIMITED_BY_HISTORY: no setup, no liquidity, no disagreement, no market event is drawn / reported
  layers       H4BiasLayers.mqh is pure (no object, chart, series, file, clock, trading)
  noclock      no live clock in the visual files (everything comes from the closed bars)
  names        object names are short and built from stable parts (no long logic id in a name)
  asof         as-of flow: server time input, historical never reads a quote, Draw reads only the evaluated window
  compact      panel: compact default (InpShowDetails false), every line has a priority, details after the compact return, Experts log holds the details
  resize       panel fits the chart (rows/columns/budget), CHARTEVENT_CHART_CHANGE re-lays it out without a new evaluation, font not shrunk
  labels       chart labels: short text + tooltip, stable slot (not draw order), only the text anchor is offset, level coordinates untouched
  baseline     the T002 baseline (lookback = InpLookbackBars, same functions as the T002 EA) is computed and named apart from the replay-window structure
  export       the CSV key includes the bar count and a content hash; the file is rewritten when the set changes
  since        clear / recovery zeroes the values labelled 'since baseline'; the session log is Experts only
"""
import re
import sys

TRADING = (r'OrderSend|OrderSendAsync|OrderClose|OrderModify|OrderDelete|PositionClose|PositionModify|PositionOpen|'
           r'CTrade|CPositionInfo|COrderInfo|MqlTradeRequest|MqlTradeResult|MqlTradeCheckResult|OrderCalcMargin|'
           r'OrderCalcProfit|OrderCheck|OnTradeTransaction|OnTrade\(|PositionSelect|PositionGet|OrderSelect|OrderGet|'
           r'HistoryOrder|HistoryDeal|PositionsTotal|OrdersTotal|TRADE_ACTION_|ORDER_TYPE_|POSITION_TYPE_|'
           r'#include\s*<Trade')


def strip(src, keep_strings=True):
    """Remove // and /* */ comments; string and char literals are kept (or blanked)."""
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '/' and i + 1 < n and src[i + 1] == '/':
            while i < n and src[i] != '\n':
                i += 1
            continue
        if c == '/' and i + 1 < n and src[i + 1] == '*':
            j = src.find('*/', i + 2)
            i = n if j < 0 else j + 2
            out.append(' ')
            continue
        if c in '"\'':
            q = c
            j = i + 1
            while j < n and src[j] != q:
                j += 2 if src[j] == '\\' else 1
            lit = src[i:j + 1]
            out.append(lit if keep_strings else q + ' ' * max(0, len(lit) - 2) + q)
            i = j + 1
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def split_args(body):
    args, depth, cur, i = [], 0, '', 0
    while i < len(body):
        c = body[i]
        if c in '"\'':
            q = c
            j = i + 1
            while j < len(body) and body[j] != q:
                j += 2 if body[j] == '\\' else 1
            cur += body[i:j + 1]
            i = j + 1
            continue
        if c in '([{':
            depth += 1
        elif c in ')]}':
            depth -= 1
        if c == ',' and depth == 0:
            args.append(cur.strip())
            cur = ''
        else:
            cur += c
        i += 1
    if cur.strip() or args:
        args.append(cur.strip())
    return args


def calls(code, name):
    """[(pos, [args])] for every call `name(...)` (definitions are included; callers filter)."""
    res = []
    for m in re.finditer(r'(?<![A-Za-z0-9_])' + re.escape(name) + r'\s*\(', code):
        i, depth = m.end(), 1
        start = i
        while i < len(code) and depth > 0:
            c = code[i]
            if c in '"\'':
                q = c
                i += 1
                while i < len(code) and code[i] != q:
                    i += 2 if code[i] == '\\' else 1
            elif c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
            i += 1
        res.append((m.start(), split_args(code[start:i - 1])))
    return res


def is_definition(code, pos):
    """True when the call at pos is a function definition/declaration (preceded by a return type)."""
    head = code[max(0, pos - 24):pos]
    return re.search(r'(void|string|bool|int|double|color|datetime)\s+$', head) is not None


def body_of(code, header_re):
    """Body (with braces) of the DEFINITION whose header matches; forward declarations are skipped."""
    for m in re.finditer(header_re, code):
        i = m.end()
        depth = 1 if code[i - 1] == '(' else 0
        # advance to the end of the parameter list
        while i < len(code) and (depth > 0 or code[i] not in '{;'):
            if code[i] == '(':
                depth += 1
            elif code[i] == ')':
                depth -= 1
            i += 1
        if i >= len(code) or code[i] != '{':
            continue                      # a declaration ends with ';'
        d = 0
        for j in range(i, len(code)):
            if code[j] == '{':
                d += 1
            elif code[j] == '}':
                d -= 1
                if d == 0:
                    return code[i:j + 1]
    return None


def read(path):
    with open(path, encoding='ascii', errors='replace') as fh:
        return fh.read()


# --------------------------------------------------------------------------- checks
def check_trading(paths):
    bad = []
    for p in paths:
        code = strip(read(p), keep_strings=False)
        for ln, line in enumerate(code.split('\n'), 1):
            if re.search(TRADING, line):
                bad.append(f'{p}:{ln}: trading API: {line.strip()}')
    return bad


def check_collision(paths):
    bad = []
    mine = ['velo_t003_', 'velo_t003_pnl_']
    others = ['velo_t001_', 'velo_t002_', 'velo_t002_pnl_']
    for a in mine:
        for b in others:
            if a.startswith(b) or b.startswith(a):
                bad.append(f'prefix collision: {a} / {b}')
    for p in paths:
        code = strip(read(p))
        m = re.search(r'#define\s+H3V_PREFIX\s+"([^"]*)"', code)
        if m:
            if m.group(1) != 'velo_t003_':
                bad.append(f'{p}: H3V_PREFIX is "{m.group(1)}", expected velo_t003_')
        m2 = re.search(r'#define\s+H3V_PANEL_PREFIX\s+"([^"]*)"', code)
        if m2:
            if not m2.group(1).startswith('velo_t003_'):
                bad.append(f'{p}: H3V_PANEL_PREFIX "{m2.group(1)}" does not start with velo_t003_')
        for lit in re.findall(r'"(velo_t00[0-9]_[^"]*)"', code):
            if not lit.startswith('velo_t003_'):
                bad.append(f'{p}: string literal with another task prefix: {lit}')
        if re.search(r'"velo_t00[12]', code) or re.search(r'"velo_"', code):
            bad.append(f'{p}: a T001/T002 or bare velo_ prefix is spelled out')
    return bad


def check_isolation(paths):
    bad = []
    seen_delete_all = 0
    seen_clearmap = False
    for p in paths:
        code = strip(read(p))
        # a. ObjectsDeleteAll: only with the task prefix fields as 2nd argument
        for pos, args in calls(code, 'ObjectsDeleteAll'):
            seen_delete_all += 1
            if len(args) < 2:
                bad.append(f'{p}: ObjectsDeleteAll without a prefix argument ({args})')
            elif args[1] not in ('m_prefix', 'm_panel_prefix'):
                bad.append(f'{p}: ObjectsDeleteAll with prefix argument {args[1]} (only m_prefix / m_panel_prefix allowed)')
        # b. ObjectDelete only inside ClearMap (prefix-tested) and the panel's own labels
        for pos, args in calls(code, 'ObjectDelete'):
            if is_definition(code, pos):
                continue
            before = code[:pos]
            fn = None
            for mm in re.finditer(r'\bvoid\s+(\w+)\s*\(', before):
                fn = mm.group(1)
            if fn not in ('ClearMap', 'End'):
                bad.append(f'{p}: ObjectDelete outside ClearMap/End (in {fn})')
        cm = body_of(code, r'\bvoid\s+ClearMap\s*\(\s*void\s*\)')
        if cm is not None:
            seen_clearmap = True
            if not re.search(r'StringFind\(\s*name\s*,\s*m_prefix\s*\)\s*!=\s*0\s*\)\s*continue', cm):
                bad.append(f'{p}: ClearMap does not skip objects whose name does not start with m_prefix')
            if not re.search(r'StringFind\(\s*name\s*,\s*m_panel_prefix\s*\)\s*==\s*0\s*\)\s*continue', cm):
                bad.append(f'{p}: ClearMap does not leave the panel sub-prefix alone')
            if re.search(r'ObjectsDeleteAll', cm):
                bad.append(f'{p}: ClearMap must delete one object at a time, after the prefix test')
        pe = body_of(code, r'\bvoid\s+End\s*\(\s*void\s*\)')
        if pe is not None:
            for pos, args in calls(pe, 'ObjectDelete'):
                if not re.search(r'LabelName\(|nm2', args[1] if len(args) > 1 else ''):
                    bad.append(f'{p}: panel ObjectDelete of something that is not one of its labels: {args}')
            if 'string nm2 = LabelName(' not in pe:
                bad.append(f'{p}: panel End() does not derive the deleted names from LabelName()')
        # c. ObjectCreate: only through Ensure() (name) or the panel (m_bg / label name)
        for pos, args in calls(code, 'ObjectCreate'):
            if len(args) < 2 or args[1] not in ('name', 'm_bg'):
                bad.append(f'{p}: ObjectCreate with an unexpected name argument {args[1:2]}')
        for pos, args in calls(code, 'Ensure'):
            if is_definition(code, pos):
                continue
            if args and args[0] != 'name':
                bad.append(f'{p}: Ensure() called with {args[0]} (must be the helper parameter name)')
        for helper in ('Segment', 'Note', 'Rect'):
            for pos, args in calls(code, helper):
                if is_definition(code, pos):
                    continue
                if not args or not args[0].startswith('m_prefix + '):
                    bad.append(f'{p}: {helper}() first argument does not start with m_prefix: {args[:1]}')
        # d. names must be stable: no clock, no counter, no random in an object name
        for pos, args in calls(code, 'Note') + calls(code, 'Segment') + calls(code, 'Rect'):
            if args and re.search(r'GetTickCount|TimeCurrent|TimeLocal|MathRand|IntegerToString\(\s*(i|k|j|q|s)\s*\)', args[0]):
                bad.append(f'{p}: object name depends on a clock, counter or random value: {args[0]}')
        if re.search(r'ObjectsDeleteAll\s*\(\s*0\s*\)|ObjectsDeleteAll\s*\([^,)]*\)', code):
            bad.append(f'{p}: ObjectsDeleteAll with a single argument deletes everything')
    if seen_delete_all < 2:
        bad.append(f'vacuous check: only {seen_delete_all} ObjectsDeleteAll call(s) found')
    if not seen_clearmap:
        bad.append('vacuous check: ClearMap() not found')
    return bad


PRICE = (r'SymbolInfoDouble|SymbolInfoTick|SYMBOL_BID|SYMBOL_ASK|SYMBOL_LAST|CopyTicks|CopyTicksRange|iClose|iHigh|iLow|'
         r'iOpen|iTime|iBars|CopyClose\(|CopyHigh\(|CopyLow\(|CopyOpen\(|CopyTime\(|MarketBookGet|GetFormingBar|\bBid\b|\bAsk\b|'
         r'PERIOD_M1\b|PERIOD_M2\b|PERIOD_M3\b|PERIOD_M4\b|PERIOD_M5\b|PERIOD_M6\b|PERIOD_M10\b|PERIOD_M12\b|PERIOD_M15\b|'
         r'PERIOD_M20\b|PERIOD_M30\b|PERIOD_H1\b|PERIOD_H2\b|PERIOD_H3\b|PERIOD_H6\b|PERIOD_H8\b|PERIOD_H12\b|PERIOD_D1\b|'
         r'PERIOD_W1\b|PERIOD_MN1\b|PERIOD_CURRENT\b')
UNWANTED = r'(?i)overlay|intrabar|\btarget|OrderLots|StopLoss|TakeProfit'


def check_nopricefeed(paths):
    bad = []
    for p in paths:
        code = strip(read(p), keep_strings=False)
        for ln, line in enumerate(code.split('\n'), 1):
            if re.search(PRICE, line):
                bad.append(f'{p}:{ln}: quote/tick/indicator/other-timeframe access: {line.strip()}')
            if re.search(UNWANTED, line):
                bad.append(f'{p}:{ln}: out-of-scope construct (overlay/target/SLTP): {line.strip()}')
    return bad


def check_flow(paths):
    bad = []
    ea = [p for p in paths if p.endswith('.mq5')]
    dr = [p for p in paths if p.endswith('H4BiasDrawer.mqh')]
    if len(ea) != 1:
        return ['flow check needs exactly one .mq5 file']
    code = strip(read(ea[0]))
    # closed bars only: exactly two CopyRates sites, live from position 1, historical from the as-of time
    cr = [a for pos, a in calls(code, 'CopyRates')]
    if len(cr) != 2:
        bad.append(f'expected exactly 2 CopyRates calls, found {len(cr)}')
    live = [a for a in cr if len(a) >= 4 and a[2] == '1']
    hist = [a for a in cr if len(a) >= 4 and a[2] == 'g_asof_eff']
    if len(live) != 1:
        bad.append('no live CopyRates(..., start_pos 1, ...) (the forming bar at position 0 would be read)')
    if len(hist) != 1:
        bad.append('no historical CopyRates(..., g_asof_eff, ...)')
    for a in cr:
        if len(a) >= 3 and a[2] in ('0', '-1'):
            bad.append(f'CopyRates from position {a[2]}: reads the forming bar')
    cc = body_of(code, r'\bint\s+CopyClosedSet\s*\(')
    if cc is None:
        bad.append('CopyClosedSet not found')
    else:
        for need in ('H4EffectiveAsOf(g_asof', 'H4ClosedCountAsOf(', 'H4AsOfSetStart(', 'if(!g_hist)'):
            if need not in cc:
                bad.append(f'CopyClosedSet lacks {need}')
    # new bars never start a rebuild in historical mode
    if 'H4NewBarForLife(g_hist, new_bar)' not in code:
        bad.append('Poll does not pass H4NewBarForLife(g_hist, new_bar) (historical mode would rebuild on new bars)')
    ed = body_of(code, r'\bvoid\s+EvaluateAndDraw\s*\(')
    if ed is None:
        bad.append('EvaluateAndDraw not found')
    else:
        if not re.search(r'if\(g_hist\)\s*H3Evaluate\(', ed) or 'H3EvaluateLatest(' not in ed:
            bad.append('EvaluateAndDraw does not use H3Evaluate for historical and H3EvaluateLatest for live')
        if not re.search(r'if\(!g_hist\)\s*ConsumeEvents\(\)', ed):
            bad.append('ConsumeEvents is not restricted to live mode')
        if not re.search(r'if\(!g_hist\)\s*TrackChanges\(\)', ed):
            bad.append('TrackChanges is not restricted to live mode')
        if 'g_drawer.Draw(' not in ed:
            bad.append('EvaluateAndDraw does not draw')
    # init/restart/recovery: history is silent (baseline cursor), reliable events only
    ce = body_of(code, r'\bvoid\s+ConsumeEvents\s*\(')
    if ce is None:
        bad.append('ConsumeEvents not found')
    else:
        for need in ('H3BaselineCursor(', 'H3ConsumeNew(', 'g_cursor == 0', '!g_ev.reliable'):
            if need not in ce:
                bad.append(f'ConsumeEvents lacks {need}')
        if ce.find('H3BaselineCursor(') > ce.find('H3ConsumeNew('):
            bad.append('ConsumeEvents calls H3ConsumeNew before establishing the baseline')
    cl = body_of(code, r'\bvoid\s+ClearBiasState\s*\(')
    if cl is None:
        bad.append('ClearBiasState not found')
    else:
        for need in ('g_cursor = 0', 'g_drawer.Reset()', 'ResetEval()'):
            if need not in cl:
                bad.append(f'ClearBiasState lacks {need} (recovery would not rebuild from a clean baseline)')
    ao = body_of(code, r'\bvoid\s+ApplyLifeOut\s*\(')
    if ao is None or 'do_clear' not in ao or 'ClearBiasState(' not in ao:
        bad.append('ApplyLifeOut does not clear the picture when the life machine asks for it')
    po = body_of(code, r'\bvoid\s+Poll\s*\(')
    if po is None or 'g_h4.IsReady()' not in po or 'H4LifeDecide(' not in po:
        bad.append('Poll does not gate on series readiness through H4LifeDecide')
    # nothing proposal-derived is drawn from an unreliable evaluation
    for d in dr:
        dcode = strip(read(d))
        dd = body_of(dcode, r'\bvoid\s+Draw\s*\(')
        if dd is None:
            bad.append(f'{d}: Draw not found')
        elif not re.search(r'if\(\s*!ev\.reliable', dd):
            bad.append(f'{d}: Draw does not stop on an unreliable evaluation')
    return bad


def check_diag(paths):
    """diagnostics, candle export and TrackChanges (source reading only)"""
    bad = []
    ea = [p for p in paths if p.endswith('.mq5')]
    if len(ea) != 1:
        return ['diag check needs exactly one .mq5 file']
    raw = read(ea[0])
    code = strip(raw)
    # the export is OFF by default
    if not re.search(r'input\s+bool\s+InpExportCandles\s*=\s*false\s*;', code):
        bad.append('InpExportCandles is not declared with the default false (export must be off by default)')
    if not re.search(r'input\s+bool\s+InpDiagnostics\s*=', code):
        bad.append('InpDiagnostics input missing')
    ex = body_of(code, r'\bvoid\s+ExportCandles\s*\(')
    if ex is None:
        return bad + ['ExportCandles not found']
    # file functions only inside ExportCandles (everywhere else in the EA and the drawer: none)
    start = code.find(ex)
    for m_ in re.finditer(r'\bFile[A-Z][A-Za-z]*\s*\(', code):
        if not (start <= m_.start() < start + len(ex)):
            bad.append(f'{m_.group(0)} used outside ExportCandles (file access must stay in the export)')
    for d in [p for p in paths if p.endswith('.mqh')]:
        if re.search(r'\bFile[A-Z][A-Za-z]*\s*\(', strip(read(d))):
            bad.append(f'{d}: file access outside the EA export')
    if 'FileOpen(' not in ex or 'FileClose(' not in ex:
        bad.append('ExportCandles does not open and close the file')
    if not re.search(r'if\(\s*!InpExportCandles', ex):
        bad.append('ExportCandles is not gated by InpExportCandles')
    # closed bars only: it writes g_bars (the evaluated set) and reads no series, tick, quote or indicator
    for pat, why in ((r'\bCopy[A-Za-z]*\s*\(', 'a series/tick copy'), (r'\bSymbolInfo[A-Za-z]*\s*\(', 'a quote'), (r'\bi(Open|High|Low|Close|Time|Volume|Bars)\s*\(', 'an indicator-style series read'),
                     (r'\bMarketBook[A-Za-z]*\s*\(', 'the order book'), (r'\bH3Evaluate[A-Za-z]*\s*\(', 'a new evaluation')):
        if re.search(pat, ex):
            bad.append(f'ExportCandles contains {why}: the export must write only the closed-bar set of the evaluation')
    if 'g_bars[' not in ex or 'H3CsvRow(' not in ex or 'H3CsvHeader(' not in ex:
        bad.append('ExportCandles does not write g_bars through H3CsvHeader / H3CsvRow')
    if 'TERMINAL_DATA_PATH' not in ex:
        bad.append('ExportCandles does not report the full path of the file')
    # called from EvaluateAndDraw only
    calls_ = [m_.start() for m_ in re.finditer(r'\bExportCandles\s*\(\s*\)\s*;', code)]
    ed = body_of(code, r'\bvoid\s+EvaluateAndDraw\s*\(')
    if ed is None or 'ExportCandles();' not in ed or len(calls_) != 1:
        bad.append('ExportCandles must be called exactly once, from EvaluateAndDraw')
    # diagnostics: only when LIMITED, read-only
    rd = body_of(code, r'\bvoid\s+RunDiagnostics\s*\(')
    if rd is None:
        bad.append('RunDiagnostics not found')
    else:
        if 'InpDiagnostics' not in rd or 'g_ev.reliable' not in rd:
            bad.append('RunDiagnostics is not restricted to InpDiagnostics and an unreliable evaluation')
        if 'H3Diagnose(g_bars, g_n, g_params, g_ev, g_diag)' not in rd:
            bad.append('RunDiagnostics does not call H3Diagnose on the evaluated set')
        if re.search(r'\bg_ev\.[A-Za-z_]+\s*=[^=]', rd) or re.search(r'\bH3Evaluate[A-Za-z]*\s*\(', rd):
            bad.append('RunDiagnostics changes or recomputes the evaluation')
    if ed is not None and 'RunDiagnostics();' not in ed:
        bad.append('EvaluateAndDraw does not run the diagnostics')
    # TrackChanges: a change is reported only for the decision REPORT, a rebuild difference never is
    tc = body_of(code, r'\bvoid\s+TrackChanges\s*\(')
    if tc is None:
        bad.append('TrackChanges not found')
    else:
        if 'H3TrackChangesMode(g_cons_status, g_prev_valid)' not in tc:
            bad.append('TrackChanges does not take its decision from H3TrackChangesMode(g_cons_status, g_prev_valid)')
        i_rep = tc.find('if(mode == H3_TC_REPORT)')
        i_else = tc.find('else', i_rep + 1) if i_rep >= 0 else -1
        total = len(re.findall(r'\bPushChange\s*\(', tc))
        if i_rep < 0 or i_else < 0:
            bad.append('TrackChanges has no if(mode == H3_TC_REPORT) ... else structure')
        else:
            inside = len(re.findall(r'\bPushChange\s*\(', tc[i_rep:i_else]))
            if total < 3 or inside != total:
                bad.append('PushChange is called outside the H3_TC_REPORT branch (a rebuild difference could be shown as a market change)')
            if 'RE-DERIVATION' not in tc[i_else:] or 'NOT reported as a market change' not in tc[i_else:]:
                bad.append('the re-derivation branch of TrackChanges does not log that it is not a market change')
    cs = body_of(code, r'\bvoid\s+ConsumeEvents\s*\(')
    if cs is None or 'g_cons_status = H3_C_BASELINE' not in cs or 'g_cons_status = cs' not in cs:
        bad.append('ConsumeEvents does not record the consumer status for TrackChanges')
    return bad


def _body_or_fail(code, header, what, bad):
    b = body_of(code, header)
    if b is None:
        bad.append(f'{what} not found')
    return b


def check_nofrozen(paths):
    """FROZEN / thaw text must not appear in the EA, the drawer or the layers (comments included)."""
    bad = []
    for p in paths:
        for ln, line in enumerate(read(p).split('\n'), 1):
            if re.search(r'(?i)frozen|thaw', line):
                bad.append(f'{p}:{ln}: obsolete FROZEN / thaw text: {line.strip()}')
    if not paths:
        bad.append('vacuous check: no file given')
    return bad


def _split_files(paths):
    ea = [p for p in paths if p.endswith('.mq5')]
    drw = [p for p in paths if p.endswith('H4BiasDrawer.mqh')]
    lay = [p for p in paths if p.endswith('H4BiasLayers.mqh')]
    return ea, drw, lay


def check_disagree(paths):
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(ea) != 1 or len(drw) != 1 or len(lay) != 1:
        return ['disagree check needs the EA, H4BiasDrawer.mqh and H4BiasLayers.mqh']
    lraw = read(lay[0])
    lcode = strip(lraw)
    dis = _body_or_fail(lcode, r'\bbool\s+H3LDisagree\s*\(', 'H3LDisagree', bad)
    if dis is not None:
        if len(re.findall(r'return\(true\)', dis)) != 2:
            bad.append('H3LDisagree must return true in exactly two cases (BULLISH vs BEAR, BEARISH vs BULL)')
        if not re.search(r't2dir\s*==\s*H4_DIR_BULLISH\s*&&\s*bias\s*==\s*H3_BEAR', dis):
            bad.append('H3LDisagree lacks the case T002 BULLISH against T003 BEAR')
        if not re.search(r't2dir\s*==\s*H4_DIR_BEARISH\s*&&\s*bias\s*==\s*H3_BULL', dis):
            bad.append('H3LDisagree lacks the case T002 BEARISH against T003 BULL')
        if re.search(r'H4_DIR_MIXED|H4_DIR_UNKNOWN|H3_NONE|!=', dis):
            bad.append('H3LDisagree mentions MIXED / UNKNOWN / NONE or uses != : those must never count as a disagreement')
        if not re.search(r'return\(false\)\s*;\s*}\s*$', dis.strip()):
            bad.append('H3LDisagree does not end with return(false)')
    if 'MODEL DISAGREEMENT - client validation pending' not in lcode:
        bad.append('the text "MODEL DISAGREEMENT - client validation pending" is missing from H4BiasLayers.mqh')
    if 'baseline (lookback ' not in lcode or 'replay-window structure' not in lcode:
        bad.append('the disagreement text does not name the T002 baseline (lookback N) / the replay-window structure')
    if 'MIXED / UNKNOWN' not in lraw or 'NOT a disagreement' not in lraw:
        bad.append('the definition (MIXED / UNKNOWN is NOT a disagreement) is not stated in the H4BiasLayers.mqh header')
    run = _body_or_fail(lcode, r'\bvoid\s+H3LDisagreeRun\s*\(', 'H3LDisagreeRun', bad)
    if run is not None:
        for need in ('H3LBiasAtBar(events, ne, win[t].time)', 'H3KnownCount(sw, ns, right, t)', 'win[last].time', 'int stop = (warm < last ? warm : last);'):
            if need not in run:
                bad.append(f'H3LDisagreeRun lacks {need} (absolute bar times / swings known at the bar / trusted region)')
        if re.search(r'\bnw\s*\+|\blast\s*\+\s*[0-9]|win\[nw\]', run):
            bad.append('H3LDisagreeRun reads beyond the last evaluated bar')
    rb = _body_or_fail(lcode, r'\bvoid\s+H3LDisagreeRunBase\s*\(', 'H3LDisagreeRunBase', bad)
    if rb is not None:
        for need in ('H3LBiasAtBar(events, ne, win[t].time)', 'H3LBaselineDir(win, t + 1, lookback, left, right, period, nb)',
                     'win[last].time', 'int stop = (warm < last ? warm : last);', 'H3LDisagree(r.t2dir, r.bias)'):
            if need not in rb:
                bad.append(f'H3LDisagreeRunBase lacks {need} (baseline at every bar / absolute bar times / trusted region)')
        if re.search(r'\bnw\s*\+|\blast\s*\+\s*[0-9]|win\[nw\]', rb):
            bad.append('H3LDisagreeRunBase reads beyond the last evaluated bar')
    ba = _body_or_fail(lcode, r'\bint\s+H3LBiasAtBar\s*\(', 'H3LBiasAtBar', bad)
    if ba is not None and 'events[i].bar_time > bar_open' not in ba:
        bad.append('H3LBiasAtBar does not stop at events after the bar')
    dcode = strip(read(drw[0]))
    dd = _body_or_fail(dcode, r'\bvoid\s+Draw\s*\(', 'Draw', bad)
    if dd is not None:
        for need in ('H3LDisagreeRunBase(win, nw, p.lookback, p.left, p.right, p.period, H3WarmUp(p), events, ev.ne, v.dis)', 'H3LDisagreeText(v.dis, p.period)', 'if(v.dis.active)'):
            if need not in dd:
                bad.append(f'Draw lacks {need}')
    ecode = strip(read(ea[0]))
    rp = _body_or_fail(ecode, r'\bvoid\s+RenderPanel\s*\(', 'RenderPanel', bad)
    if rp is not None:
        if 'H3LDisagreeText(g_view.dis, g_params.period)' not in rp:
            bad.append('RenderPanel does not show the MODEL DISAGREEMENT text')
        if 'T002 baseline BULLISH vs T003 BEAR or T002 baseline BEARISH vs T003 BULL only' not in rp or 'in terms of the T002 BASELINE' not in rp:
            bad.append('RenderPanel does not state the disagreement definition in terms of the T002 BASELINE')
    ld = _body_or_fail(ecode, r'\bvoid\s+LogDisagreement\s*\(', 'LogDisagreement', bad)
    if ld is not None:
        if 'H3LDisagreeKey(g_view.dis)' not in ld or not re.search(r'if\(key == g_dis_key\)\s*return;', ld):
            bad.append('LogDisagreement is not once-per-change (key comparison missing)')
        if 'g_tc_mode == H3_TC_REPORT' not in ld or 'NOT reported as a market change' not in ld:
            bad.append('LogDisagreement does not separate a real change (H3_TC_REPORT) from a rebuild / historical state')
    ed = _body_or_fail(ecode, r'\bvoid\s+EvaluateAndDraw\s*\(', 'EvaluateAndDraw', bad)
    if ed is not None and 'LogDisagreement();' not in ed:
        bad.append('EvaluateAndDraw does not call LogDisagreement')
    if 'MODEL DISAGREEMENT' not in ecode:
        bad.append('the EA never mentions MODEL DISAGREEMENT')
    return bad


FORBIDDEN_LOGIC = (r'H3Evaluate|H3EvaluateLatest|H3Replay|H3ProcessBar|H3BiasStep|H3DeriveStep|H3DoFlip|H3StartHold|'
                   r'H3ClearSetup|H3FvgStep|H3NoneStep|H3SetupEnded|H3AddEvent|H3Diagnose|H3BuildTracks|H3TrackFill')


def check_liquidity(paths):
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(ea) != 1 or len(drw) != 1 or len(lay) != 1:
        return ['liquidity check needs the EA, H4BiasDrawer.mqh and H4BiasLayers.mqh']
    lcode = strip(read(lay[0]))
    dcode = strip(read(drw[0]))
    ecode = strip(read(ea[0]))
    lq = _body_or_fail(lcode, r'\bint\s+H3LLiquidity\s*\(', 'H3LLiquidity', bad)
    if re.search(r'\bint\s+H3LLiquidity\s*\(\s*const\s+MqlRates\s*&\s*win\s*\[\s*\]\s*,\s*const\s+int\s+nw\s*,\s*const\s+SH4Swing\s*&\s*sw\s*\[\s*\]', lcode) is None:
        bad.append('H3LLiquidity must take the bars and the swings as const references')
    if lq is not None:
        for need in ('win[j].high > sw[i].price', 'win[j].low < sw[i].price', 'H3KnownCount(sw, ns, right, nw - 1)', 'int maxn'):
            if need not in lq and not (need == 'int maxn' and 'maxn' in lq):
                bad.append(f'H3LLiquidity lacks {need} (wick based, confirmed swings only, limited)')
        if re.search(r'win\[j\]\.(close|open)', lq):
            bad.append('H3LLiquidity compares closes / opens: the exceed test must be a WICK (high / low)')
        if re.search(r'\bnw\s*\+|win\[nw\]', lq):
            bad.append('H3LLiquidity reads beyond the last evaluated bar')
    # read-only with respect to the bias: no write into the state, the evaluation, the tracks or the events
    for name, code in (('H4BiasLayers.mqh', lcode), ('H4BiasDrawer.mqh', dcode)):
        for ln, line in enumerate(code.split('\n'), 1):
            if re.search(r'\b(st|ev|g_ev|tracks|events|g_params|g_tracks|g_events)\b(\.\w+|\[[^\]]*\](\.\w+)?)?\s*(=|\+=|-=|\*=)(?!=)', line):
                bad.append(f'{name}:{ln}: write into the bias state / evaluation / tracks / events: {line.strip()}')
            if re.search(FORBIDDEN_LOGIC, line):
                bad.append(f'{name}:{ln}: call of a T003 logic function that changes or recomputes the bias: {line.strip()}')
        for pos, args in calls(code, 'H3StateCopy'):
            if is_definition(code, pos):
                continue
            if len(args) != 2 or args[1] != 'st':
                bad.append(f'{name}: H3StateCopy into something other than the local copy st: {args}')
        for pos, args in calls(code, 'H3StateInit'):
            if is_definition(code, pos):
                continue
            if args != ['s0']:
                bad.append(f'{name}: H3StateInit on something other than the local s0: {args}')
    for hdr in (r'#include\s+"H4Bias\.mqh"',):
        pass
    for f in ('src/include/H4Bias.mqh', 'src/include/H4Structure.mqh'):
        import os
        base = os.path.dirname(lay[0])
        fp = os.path.join(base, os.path.basename(f))
        if os.path.exists(fp) and re.search(r'H4BiasLayers|H4BiasDrawer', read(fp)):
            bad.append(f'{fp} includes the visual layer: the bias would depend on it')
    dd = _body_or_fail(dcode, r'\bvoid\s+Draw\s*\(', 'Draw', bad)
    if dd is not None:
        sig = re.search(r'\bvoid\s+Draw\s*\(([^)]*)\)', dcode)
        s = sig.group(1) if sig else ''
        for need in ('const SH3Eval &ev', 'const SH3Track &tracks[]', 'const SH3Event &events[]', 'const bool show_liq', 'const int liq_max'):
            if need not in s:
                bad.append(f'Draw signature lacks "{need}"')
        if 'if(show_liq && liq_max > 0)' not in dd or 'H3LLiquidity(win, nw, sw, ns, p.right, liq_max,' not in dd:
            bad.append('Draw does not apply the switch and the limit to the liquidity layer')
        if 'Segment(m_prefix + "liq_"' not in dd or 'Note(m_prefix + "liq_lbl_"' not in dd:
            bad.append('liquidity objects do not carry the liq_ name under the T003 prefix')
    ed = _body_or_fail(ecode, r'\bvoid\s+EvaluateAndDraw\s*\(', 'EvaluateAndDraw', bad)
    if ed is not None and 'InpShowLiquidity, MathMax(0, MathMin(50, InpLiqMax))' not in ed:
        bad.append('EvaluateAndDraw does not pass InpShowLiquidity and the clamped InpLiqMax to Draw')
    if not re.search(r'input\s+bool\s+InpShowLiquidity\s*=\s*true\s*;', ecode):
        bad.append('input bool InpShowLiquidity (default true) missing: the layer needs an off switch')
    if not re.search(r'input\s+int\s+InpLiqMax\s*=\s*6\s*;', ecode):
        bad.append('input int InpLiqMax (default 6) missing: the layer needs a limit')
    if 'PROPOSAL - historical liquidity, not ERL / target / protecting level' not in ecode:
        bad.append('the panel does not label the layer "PROPOSAL - historical liquidity, not ERL / target / protecting level"')
    if 'Fractal 2/2 and this definition are proposals' not in ecode:
        bad.append('the panel does not say that fractal 2/2 and the definition are proposals')
    return bad


def check_limited(paths):
    """LIMITED_BY_HISTORY: the early exits that keep every proposal-derived thing off the chart / the log."""
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(ea) != 1 or len(drw) != 1:
        return ['limited check needs the EA and H4BiasDrawer.mqh']
    ecode = strip(read(ea[0]))
    dcode = strip(read(drw[0]))
    dd = _body_or_fail(dcode, r'\bvoid\s+Draw\s*\(', 'Draw', bad)
    if dd is not None:
        i_ret = dd.find('if(!ev.reliable')
        j = dd.find('return;', i_ret) if i_ret >= 0 else -1
        if i_ret < 0 or j < 0:
            bad.append('Draw has no early return for an unreliable evaluation')
        else:
            for later in ('H3SetupContext(', 'H3LLiquidity(', 'Note(', 'Segment(', 'Rect(', 'H3LDisagreeRun('):
                k = dd.find(later)
                if k >= 0 and k < j:
                    bad.append(f'Draw uses {later} before the early return for an unreliable evaluation')
    rp = _body_or_fail(ecode, r'\bvoid\s+RenderPanel\s*\(', 'RenderPanel', bad)
    if rp is not None:
        i_un = rp.find('if(!g_ev.reliable)')
        j = rp.find('return;', i_un) if i_un >= 0 else -1
        if i_un < 0 or j < 0:
            bad.append('RenderPanel has no early return for an unreliable evaluation')
        else:
            for later in ('SETUP', 'g_view.ctx', 'liquidity', 'MODEL DISAGREEMENT', 'H3LDisagreeText(', 'T002 structure'):
                k = rp.find(later, i_un)
                # the unreliable block itself may say that nothing is drawn; only code after its return counts
                if 0 <= k < j and later in ('g_view.ctx', 'H3LDisagreeText('):
                    bad.append(f'RenderPanel uses {later} inside / before the unreliable block')
            if 'no market event' not in rp[i_un:j] and 'no event' not in rp[i_un:j]:
                bad.append('the unreliable panel block does not say that no market event is emitted')
    ce = _body_or_fail(ecode, r'\bvoid\s+ConsumeEvents\s*\(', 'ConsumeEvents', bad)
    if ce is not None:
        i_un = ce.find('if(!g_ev.reliable)')
        if i_un < 0 or i_un > ce.find('H3ConsumeNew(') or i_un > ce.find('g_cursor == 0'):
            bad.append('ConsumeEvents does not leave early when the evaluation is not reliable')
    ld = _body_or_fail(ecode, r'\bvoid\s+LogDisagreement\s*\(', 'LogDisagreement', bad)
    if ld is not None:
        i_un = ld.find('if(!g_ev.reliable)')
        if i_un < 0 or i_un > ld.find('PrintFormat('):
            bad.append('LogDisagreement does not check that the evaluation is reliable before it logs')
    tc = _body_or_fail(ecode, r'\bvoid\s+TrackChanges\s*\(', 'TrackChanges', bad)
    if tc is not None and not re.search(r'if\(!g_ev\.reliable\)\s*\{\s*g_prev_valid = false;\s*return;', tc):
        bad.append('TrackChanges does not drop the previous snapshot when the evaluation is not reliable')
    ev = _body_or_fail(ecode, r'\bvoid\s+EvaluateAndDraw\s*\(', 'EvaluateAndDraw', bad)
    if ev is not None and 'unreliable' in ev:
        pass
    return bad


LAYERS_FORBIDDEN = (r'\bObject[A-Z]\w*\s*\(|\bChart[A-Z]\w*\s*\(|\bCopy\w*\s*\(|\bFile[A-Z]\w*\s*\(|\bSymbolInfo\w*\s*\(|'
                    r'\bTime(Current|Local|GMT|TradeServer)\s*\(|\bGetTickCount\w*\s*\(|\bSleep\s*\(|\bi(Open|High|Low|Close|Time|Bars)\s*\(|'
                    r'\bPrint\w*\s*\(|\bAlert\s*\(|\bSendNotification|\bWebRequest')


def check_layers(paths):
    bad = []
    _, _, lay = _split_files(paths)
    if len(lay) != 1:
        return ['layers check needs H4BiasLayers.mqh']
    raw = read(lay[0])
    code = strip(raw, keep_strings=False)
    for ln, line in enumerate(code.split('\n'), 1):
        if re.search(LAYERS_FORBIDDEN, line):
            bad.append(f'{lay[0]}:{ln}: the layers header must be pure (no object, chart, series, file, clock, log): {line.strip()}')
    incs = re.findall(r'#include\s+"([^"]+)"', strip(raw))
    if incs != ['H4Bias.mqh']:
        bad.append(f'{lay[0]}: includes {incs}, expected only H4Bias.mqh')
    if re.search(TRADING, code):
        bad.append(f'{lay[0]}: trading API')
    return bad


def check_noclock(paths):
    bad = []
    for p in paths:
        code = strip(read(p), keep_strings=False)
        for ln, line in enumerate(code.split('\n'), 1):
            if re.search(r'\bTime(Current|Local|GMT|TradeServer)\s*\(|\bGetMicrosecondCount|\bSeriesInfo|\bTimeToStruct\s*\(\s*TimeCurrent', line):
                bad.append(f'{p}:{ln}: live clock access: {line.strip()}')
    return bad


def check_names(paths):
    bad = []
    _, drw, _ = _split_files(paths)
    if len(drw) != 1:
        return ['names check needs H4BiasDrawer.mqh']
    code = strip(read(drw[0]))
    n_calls = 0
    for helper in ('Note', 'Segment', 'Rect'):
        for pos, args in calls(code, helper):
            if is_definition(code, pos) or not args:
                continue
            n_calls += 1
            if re.search(r'H3VSanitize\(\s*(st\.|H3EventId|events\[)|H3EventId\(|\.(lv_id|snap_id|li_id|setup_id|rec_id)\b', args[0]) and 'H3LShort(' not in args[0]:
                bad.append(f'{drw[0]}: a long logic id is used raw in an object name ({helper}): {args[0]}')
    if n_calls < 15:
        bad.append(f'vacuous check: only {n_calls} drawing calls found')
    if 'H3LShort(' not in code:
        bad.append('the drawer never shortens an id with H3LShort')
    return bad


def check_asof(paths):
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(ea) != 1 or len(drw) != 1:
        return ['asof check needs the EA and H4BiasDrawer.mqh']
    ecode = strip(read(ea[0]))
    eraw = read(ea[0])
    if not re.search(r'input\s+datetime\s+InpAsOfTime\s*=\s*0\s*;', ecode):
        bad.append('input datetime InpAsOfTime = 0 missing')
    if 'BROKER/SERVER time' not in eraw or 'NOT UTC' not in eraw:
        bad.append('the AsOfTime input is not documented as BROKER/SERVER time, not UTC')
    for need in ('g_asof = InpAsOfTime;', 'g_hist = (g_asof > 0);', 'InpAsOfTime < 0'):
        if need not in ecode:
            bad.append(f'EA lacks {need}')
    dcode = strip(read(drw[0]), keep_strings=False)
    dd = body_of(dcode, r'\bvoid\s+Draw\s*\(')
    if dd is None:
        bad.append('Draw not found')
    else:
        uses = re.findall(r'\bbars\b', dd)
        if uses != ['bars'] or 'ArrayCopy(win, bars, 0, w0, nw);' not in dd:
            bad.append('Draw reads the bars array other than through the single ArrayCopy into the evaluated window')
        if re.search(r'\bn\b\s*\[|\bbars\s*\[', dd):
            bad.append('Draw indexes the full bars array (bars after the evaluation could be read)')
    if len(lay) == 1:
        lc = strip(read(lay[0]), keep_strings=False)
        if re.search(r'\bbars\s*\[|MqlRates\s*&\s*bars', lc):
            bad.append('the layers header refers to a full bars array: it must work on the evaluated window only')
    return bad


def check_compact(paths):
    """compact panel by default; priorities; the details come after the compact return; the Experts log holds the details"""
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(ea) != 1 or len(drw) != 1:
        return ['compact check needs the EA and H4BiasDrawer.mqh']
    ecode = strip(read(ea[0]))
    dcode = strip(read(drw[0]))
    if not re.search(r'input\s+bool\s+InpShowDetails\s*=\s*false\s*;', ecode):
        bad.append('input bool InpShowDetails = false (compact view by default) missing')
    rp = _body_or_fail(ecode, r'\bvoid\s+RenderPanel\s*\(', 'RenderPanel', bad)
    if rp is not None:
        lines = [a for pos, a in calls(rp, 'g_panel.Line')]
        if len(lines) < 25:
            bad.append(f'vacuous check: only {len(lines)} g_panel.Line calls in RenderPanel')
        for a in lines:
            if len(a) != 3 or not re.fullmatch(r'\d+', a[2]):
                bad.append(f'a panel line without an integer priority as the third argument: {a[:1]}')
        ess = [a for a in lines if len(a) == 3 and a[2] == '0']
        if len(ess) < 10:
            bad.append(f'fewer than 10 essential (priority 0) lines in RenderPanel ({len(ess)})')
        i_cmp = rp.find('if(!InpShowDetails)')
        j_ret = rp.find('return;', i_cmp) if i_cmp >= 0 else -1
        k_det = rp.find('--- STRUCTURE')
        if i_cmp < 0 or j_ret < 0:
            bad.append('RenderPanel has no if(!InpShowDetails) ... return; compact exit')
        elif not (0 <= j_ret < k_det):
            bad.append('the long view (--- STRUCTURE) is not placed after the compact return')
        head = rp[:i_cmp] if i_cmp >= 0 else rp
        for need in ('T003 bias (PROTOTYPE', 'H3LT2Name(g_view.t2_base_look)', 'current level', 'READY', 'FVG: ', 'reliability: ', 'H3LDisagreeText(g_view.dis, g_params.period)'):
            if need not in head:
                bad.append(f'the compact view lacks {need}')
        for pat in ('SETUP %s', '--- SETUP', '--- EVENTS', 'depths:', 'T002 sources'):
            if pat in head:
                bad.append(f'the compact view contains the long-view text {pat!r}')
    if not re.search(r'void\s+Line\s*\(\s*const\s+string\s+text\s*,\s*const\s+color\s+clr\s*,\s*const\s+int\s+prio\s*\)', dcode):
        bad.append('CH3Panel::Line has no priority parameter')
    ld = _body_or_fail(ecode, r'\bvoid\s+LogDetails\s*\(', 'LogDetails', bad)
    if ld is not None:
        for need in ('T003 SUMMARY', 'T003 DETAIL', 'if(!g_ev.reliable)'):
            if need not in ld:
                bad.append(f'LogDetails lacks {need}')
    ed = _body_or_fail(ecode, r'\bvoid\s+EvaluateAndDraw\s*\(', 'EvaluateAndDraw', bad)
    if ed is not None and 'LogDetails();' not in ed:
        bad.append('EvaluateAndDraw does not call LogDetails (the details must reach the Experts log)')
    return bad


def check_resize(paths):
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(ea) != 1 or len(drw) != 1 or len(lay) != 1:
        return ['resize check needs the EA, H4BiasDrawer.mqh and H4BiasLayers.mqh']
    ecode = strip(read(ea[0]))
    dcode = strip(read(drw[0]))
    lcode = strip(read(lay[0]))
    oc = _body_or_fail(ecode, r'\bvoid\s+OnChartEvent\s*\(', 'OnChartEvent', bad)
    if oc is not None:
        if 'CHARTEVENT_CHART_CHANGE' not in oc or 'g_panel.Relayout()' not in oc:
            bad.append('OnChartEvent does not lay the panel out again on CHARTEVENT_CHART_CHANGE')
        if re.search(r'Draw\s*\(|EvaluateAndDraw|RebuildBias|HistoryProbe|H3Evaluate|ClearBiasState', oc):
            bad.append('OnChartEvent redraws or re-evaluates (a resize must only re-lay out the panel)')
    rl = _body_or_fail(dcode, r'\bvoid\s+Relayout\s*\(', 'Relayout', bad)
    if rl is not None:
        for need in ('CHART_WIDTH_IN_PIXELS', 'CHART_HEIGHT_IN_PIXELS', 'cw == m_last_w && ch == m_last_h', 'End();'):
            if need not in rl:
                bad.append(f'Relayout lacks {need}')
        if 'ObjectDelete' in rl or 'ObjectsDeleteAll' in rl:
            bad.append('Relayout deletes objects')
    en = _body_or_fail(dcode, r'\bvoid\s+End\s*\(\s*void\s*\)', 'panel End', bad)
    if en is not None:
        for need in ('CHART_WIDTH_IN_PIXELS', 'CHART_HEIGHT_IN_PIXELS', 'H3LPanelRows(', 'H3LPanelCols(', 'H3LWrap(', 'H3LPanelBudget(', 'm_last_w = cw', 'm_last_h = ch'):
            if need not in en:
                bad.append(f'panel End() lacks {need} (layout from the chart size and the line budget)')
    ini = _body_or_fail(dcode, r'\bvoid\s+Init\s*\(\s*const\s+bool\s+enabled', 'panel Init', bad)
    if ini is not None and not re.search(r'font_size\s*<\s*7\s*\?\s*7', ini):
        bad.append('panel Init does not keep the font between 7 and 24')
    if len(re.findall(r'\bm_font\s*=[^=]', dcode)) > 4:
        bad.append('the font member is assigned in more places than the constructors / Init: the font must not be shrunk to fit')
    if re.search(r'm_font\s*(-=|\*=|/=)|OBJPROP_FONTSIZE\s*,\s*[^,]*m_font\s*[-*/]', dcode):
        bad.append('the panel changes the font size to fit')
    for fn in ('H3LWrap', 'H3LPanelRows', 'H3LPanelCols', 'H3LPanelBudget'):
        if not re.search(r'\b(int)\s+' + fn + r'\s*\(', lcode):
            bad.append(f'{fn} missing from H4BiasLayers.mqh')
    pb = _body_or_fail(lcode, r'\bint\s+H3LPanelBudget\s*\(', 'H3LPanelBudget', bad)
    if pb is not None:
        for need in ('prio[j] < prio[best]', 'int budget = rows_avail - 1;', 'if(used + need > budget)'):
            if need not in pb:
                bad.append(f'H3LPanelBudget lacks {need}')
    if not re.search(r'g_panel\.Init\(InpShowPanel,\s*\(int\)InpPanelCorner,\s*InpPanelFontSize,', ecode):
        bad.append('the panel is not initialised with the configurable InpPanelFontSize')
    return bad


def check_labels(paths):
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(drw) != 1 or len(lay) != 1:
        return ['labels check needs H4BiasDrawer.mqh and H4BiasLayers.mqh']
    dcode = strip(read(drw[0]))
    lcode = strip(read(lay[0]))
    nt = _body_or_fail(dcode, r'\bvoid\s+Note\s*\(', 'Note', bad)
    if nt is not None and 'OBJPROP_TOOLTIP' not in nt:
        bad.append('Note does not set OBJPROP_TOOLTIP (the full text of a short label)')
    dd = _body_or_fail(dcode, r'\bvoid\s+Draw\s*\(', 'Draw', bad)
    if dd is not None:
        n_tip = 0
        n_note = 0
        for pos, args in calls(dd, 'Note'):
            n_note += 1
            if len(args) >= 8:
                n_tip += 1
        if n_note < 10 or n_tip < n_note - 2:
            bad.append(f'dynamic chart labels without a tooltip: {n_note - n_tip} of {n_note}')
        if 'H3LLabelSlot(events[e].bar_time, p.period, seq, 3)' not in dd or 'H3VEventShort(' not in dd:
            bad.append('event labels do not use the stable slot H3LLabelSlot(bar time, rank in the same bar) and the short text')
        if re.search(r'drawn_bars|\bstack\b', dd):
            bad.append('event label offsets still depend on the draw order (drawn_bars / stack)')
        if 'step * (5.0 + slot * 1.0)' not in dd:
            bad.append('the event label price offset is not a function of the slot')
        # level coordinates must stay real: price arguments of lines and rectangles never contain an offset
        for pos, args in calls(dd, 'Segment'):
            if len(args) >= 5 and re.search(r'"(lvl_|snap_|lint_|liq_)"', args[0]):
                for ix in (2, 4):
                    if not re.fullmatch(r'(st\.\w+|sw\[kz\]\.price)', args[ix]):
                        bad.append(f'level line price argument is not the real level price: {args[ix]}')
        for pos, args in calls(dd, 'Rect'):
            if len(args) >= 5:
                for ix in (2, 4):
                    if not re.fullmatch(r'fv\[fk\]\.(upper|lower)', args[ix]):
                        bad.append(f'FVG rectangle price argument is not the real FVG bound: {args[ix]}')
        # level, snapshot and FVG stay distinguishable
        if 'STYLE_SOLID' not in dd or 'STYLE_DASH' not in dd or 'STYLE_DOT' not in dd:
            bad.append('solid / dashed / dotted styles are missing (current level / snapshot / liquidity)')
        for lab in ('"CURRENT %s"', '"SNAPSHOT %s (ref)%s"', '"FVG %s %s"'):
            if lab not in dd:
                bad.append(f'distinct short label {lab} missing')
    ls = _body_or_fail(lcode, r'\bint\s+H3LLabelSlot\s*\(', 'H3LLabelSlot', bad)
    if ls is not None and re.search(r'Rand|Tick|Time[A-Z]|GetMicro', ls):
        bad.append('H3LLabelSlot depends on a clock or a random value')
    return bad


def check_baseline(paths):
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(ea) != 1 or len(drw) != 1 or len(lay) != 1:
        return ['baseline check needs the EA, H4BiasDrawer.mqh and H4BiasLayers.mqh']
    ecode = strip(read(ea[0]))
    dcode = strip(read(drw[0]))
    lcode = strip(read(lay[0]))
    if 'g_params.lookback = MathMax(50, MathMin(1000, InpLookbackBars));' not in ecode:
        bad.append('the T003 EA does not derive the lookback from InpLookbackBars with the T002 clamp (50..1000)')
    import os
    t2 = os.path.join(os.path.dirname(ea[0]), 'XauUsdH4Map.mq5')
    if os.path.exists(t2):
        tcode = strip(read(t2))
        if 'g_lookback = MathMax(50, MathMin(1000, InpLookbackBars));' not in tcode:
            bad.append('the T002 EA clamp changed: the T003 baseline no longer uses the same window')
        if not re.search(r'CopyRates\(g_symbol, PERIOD_H4, 1, g_lookback, out\)', tcode):
            bad.append('the T002 EA no longer copies the last g_lookback closed bars: re-check the baseline window')
    bd = _body_or_fail(lcode, r'\bint\s+H3LBaselineDir\s*\(', 'H3LBaselineDir', bad)
    if bd is not None:
        for need in ('int start = n_end - nbars;', 'ArrayCopy(seg, win, 0, start, nbars)', 'H4FindSwings(seg, nbars, left, right, period, sw, amb)', 'H4DeriveDirection(sw, ns)'):
            if need not in bd:
                bad.append(f'H3LBaselineDir lacks {need} (same functions and window as the T002 EA)')
    if 'return("T002 baseline (lookback "' not in lcode or 'return("T002 replay-window structure")' not in lcode:
        bad.append('H3LT2Name does not give the two distinct names')
    dd = _body_or_fail(dcode, r'\bvoid\s+Draw\s*\(', 'Draw', bad)
    if dd is not None:
        if 'H3LBaselineDir(win, nw, p.lookback, p.left, p.right, p.period, v.t2_base_bars)' not in dd:
            bad.append('Draw does not compute the T002 baseline with p.lookback (InpLookbackBars)')
        if 'v.t2_base_look = p.lookback;' not in dd:
            bad.append('Draw does not record the baseline lookback')
    rp = _body_or_fail(ecode, r'\bvoid\s+RenderPanel\s*\(', 'RenderPanel', bad)
    if rp is not None:
        if 'H3LT2Name(g_view.t2_base_look)' not in rp or 'replay-window structure' not in rp:
            bad.append('the panel does not label the T002 baseline (lookback N) and the replay-window structure apart')
        if 'DIFFERS from the T002 baseline' not in rp:
            bad.append('the panel does not say when the replay-window structure differs from the baseline')
    for name, code in (('XauUsdH4Bias.mq5', ecode), ('H4BiasDrawer.mqh', dcode)):
        for m_ in re.finditer(r'"[^"\n]*(?<!replay-window )(?<!REPLAY-WINDOW )T002 (structure|direction|DIRECTION)[^"\n]*"', code):
            bad.append(f'{name}: an ambiguous T002 label (not baseline / replay-window): {m_.group(0)}')
    return bad


def check_export(paths):
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(ea) != 1 or len(lay) != 1:
        return ['export check needs the EA and H4BiasLayers.mqh']
    ecode = strip(read(ea[0]))
    eraw = read(ea[0])
    lcode = strip(read(lay[0]))
    ek = _body_or_fail(lcode, r'\bstring\s+H3LExportKey\s*\(', 'H3LExportKey', bad)
    if ek is not None:
        for need in ('IntegerToString(n)', 'H3LBarsHash(rates, n, digits)', 'rates[0].time', 'rates[n - 1].time', 'IntegerToString((long)asof)', 'symbol'):
            if need not in ek:
                bad.append(f'H3LExportKey lacks {need} (symbol, as-of, last and first time, count, content hash)')
    bh = _body_or_fail(lcode, r'\bstring\s+H3LBarsHash\s*\(', 'H3LBarsHash', bad)
    if bh is not None:
        for need in ('for(int i = 0; i < n; i++)', 'rates[i].time', 'rates[i].open', 'rates[i].high', 'rates[i].low', 'rates[i].close', 'H3LHashStep('):
            if need not in bh:
                bad.append(f'H3LBarsHash lacks {need} (an order-sensitive hash of the whole series)')
    hs = _body_or_fail(lcode, r'\bulong\s+H3LHashStep\s*\(', 'H3LHashStep', bad)
    if hs is not None and ('1099511628211' not in hs or '^' not in hs):
        bad.append('H3LHashStep is not an FNV-1a step')
    ex = _body_or_fail(ecode, r'\bvoid\s+ExportCandles\s*\(', 'ExportCandles', bad)
    if ex is not None:
        if 'string key = H3LExportKey(g_symbol, g_asof, g_bars, g_n, g_snapshot.digits);' not in ex:
            bad.append('ExportCandles does not build its key with H3LExportKey (count and content hash)')
        if re.search(r'string\s+key\s*=[^;]*g_bars\[\s*g_n\s*-\s*1\s*\]\.time', ex):
            bad.append('the export key is built from the last bar time alone')
        i_set = ex.find('g_export_key = key;')
        i_wr = ex.find('FileClose(')
        if i_set < 0 or i_set < i_wr:
            bad.append('the export key is stored before the file was written completely')
    if 'OVERWRITTEN' not in eraw:
        bad.append('the EA header does not document that the CSV is overwritten when the set changes')
    return bad


def check_since(paths):
    bad = []
    ea, drw, lay = _split_files(paths)
    if len(ea) != 1 or len(lay) != 1:
        return ['since check needs the EA and H4BiasLayers.mqh']
    ecode = strip(read(ea[0]))
    lcode = strip(read(lay[0]))
    cl = _body_or_fail(ecode, r'\bvoid\s+ClearBiasState\s*\(', 'ClearBiasState', bad)
    if cl is not None:
        for need in ('H3LSinceClear(g_since)', 'g_nchanges = 0', 'ArrayResize(g_changes, 0)', 'g_cursor = 0', 'ArrayResize(g_new_ids, 0)', 'Experts only'):
            if need not in cl:
                bad.append(f'ClearBiasState lacks {need} (the since-baseline values must start again from zero)')
    if re.search(r'\bg_new_total\b', ecode):
        bad.append('g_new_total still exists: the NEW count must be g_since.new_total (zeroed by a clear)')
    ce = _body_or_fail(ecode, r'\bvoid\s+ConsumeEvents\s*\(', 'ConsumeEvents', bad)
    if ce is not None and 'H3LSinceNew(g_since);' not in ce:
        bad.append('ConsumeEvents does not count a NEW event through H3LSinceNew')
    pc = _body_or_fail(ecode, r'\bvoid\s+PushChange\s*\(', 'PushChange', bad)
    if pc is not None and 'H3LSinceChange(g_since);' not in pc:
        bad.append('PushChange does not count through H3LSinceChange')
    rp = _body_or_fail(ecode, r'\bvoid\s+RenderPanel\s*\(', 'RenderPanel', bad)
    if rp is not None:
        if 'g_since.new_total' not in rp:
            bad.append('the panel does not show the NEW count from g_since.new_total')
        if re.search(r'g_since\.(sess_|baselines)', rp):
            bad.append('the panel shows the session totals: they belong in the Experts log only')
    od = _body_or_fail(ecode, r'\bvoid\s+OnDeinit\s*\(', 'OnDeinit', bad)
    if od is not None and 'SESSION LOG (Experts only)' not in od:
        bad.append('OnDeinit does not write the session log to the Experts')
    sc = _body_or_fail(lcode, r'\bvoid\s+H3LSinceClear\s*\(', 'H3LSinceClear', bad)
    if sc is not None:
        if 's.new_total = 0;' not in sc or 's.changes   = 0;' not in sc:
            bad.append('H3LSinceClear does not zero new_total and changes')
        if re.search(r's\.sess_', sc):
            bad.append('H3LSinceClear touches the session totals')
    return bad


CHECKS = {
    'trading': check_trading,
    'isolation': check_isolation,
    'flow': check_flow,
    'nopricefeed': check_nopricefeed,
    'collision': check_collision,
    'diag': check_diag,
    'nofrozen': check_nofrozen,
    'disagree': check_disagree,
    'liquidity': check_liquidity,
    'limited': check_limited,
    'layers': check_layers,
    'noclock': check_noclock,
    'names': check_names,
    'asof': check_asof,
    'compact': check_compact,
    'resize': check_resize,
    'labels': check_labels,
    'baseline': check_baseline,
    'export': check_export,
    'since': check_since,
}


def main(argv):
    if len(argv) < 3 or argv[1] not in CHECKS:
        print(__doc__)
        return 2
    problems = CHECKS[argv[1]](argv[2:])
    for p in problems:
        print('    ' + p)
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
