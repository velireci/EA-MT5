#!/usr/bin/env python3
"""Static checks for the T003 visual EA (src/XauUsdH4Bias.mq5, src/include/H4BiasDrawer.mqh).

NOT a compiler and NOT a runtime test: these read the source text only.
Usage: t003-visual-check.py CHECK FILE...   (exit 0 = clean, 1 = problems printed)

CHECK names: trading, isolation, flow, nopricefeed, collision
  trading      no order/trading API in executable code (comments stripped)
  isolation    chart-object deletion and creation are confined to the T003 prefix
  flow         live/historical flow: closed bars only, no live price, baseline cursor
  nopricefeed  no quote, tick, indicator-series or other-timeframe access
  collision    the T003 prefixes cannot collide with the T001/T002 prefixes
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
    dr = [p for p in paths if p.endswith('.mqh')]
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


CHECKS = {
    'trading': check_trading,
    'isolation': check_isolation,
    'flow': check_flow,
    'nopricefeed': check_nopricefeed,
    'collision': check_collision,
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
