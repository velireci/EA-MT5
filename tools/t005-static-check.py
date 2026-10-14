#!/usr/bin/env python3
"""Pattern checks for tools/t005-static-checks.sh (comments and string literals are stripped first).

Usage: t005-static-check.py trading|nofeed|novolume|contract|parity|guards FILE...
  trading  : no order / position / trade-class API
  nofeed   : no quote, tick, indicator, series or clock access (the module takes every price as an argument)
  novolume : no volume / lot / sizing identifier in code
  contract : the module header and strings keep the required labels (costs, partial, unenforced, proposals)
  parity   : status / target / pending names in the .mqh equal those of tests/t005_geometry_reference.py
             (FILE... = the .mqh followed by the reference .py)
  guards   : the validation guards exist in BOTH languages (FILE... = the .mqh followed by the reference .py): the
             three reason tags, the tick/digits compatibility test, positivity tests and the same MAX_TICKS value
Exit 0 = pass, 1 = findings printed.
"""
import re
import sys


def strip(text, keep_strings=False):
    out = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if text.startswith('//', i):
            while i < n and text[i] != '\n':
                i += 1
        elif text.startswith('/*', i):
            j = text.find('*/', i + 2)
            i = n if j < 0 else j + 2
        elif c == '"':
            j = i + 1
            while j < n and text[j] != '"':
                j += 2 if text[j] == '\\' else 1
            out.append(text[i:j + 1] if keep_strings else '""')
            i = j + 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)


TRADING = re.compile(
    r'\b(OrderSend|OrderSendAsync|OrderCheck|OrderClose|OrderModify|OrderDelete|PositionClose|PositionModify|'
    r'PositionOpen|CTrade|CPositionInfo|COrderInfo|MqlTradeRequest|MqlTradeResult|MqlTradeCheckResult|'
    r'OrderCalcMargin|OrderCalcProfit|OnTradeTransaction|OnTrade|PositionSelect|PositionGet\w*|OrderSelect|'
    r'OrderGet\w*|HistoryOrder\w*|HistoryDeal\w*|PositionsTotal|OrdersTotal|TradeRequest)\b|#include\s*<Trade')
FEED = re.compile(
    r'\b(SymbolInfoTick|SymbolInfoDouble|SymbolInfoInteger|SymbolInfoString|SYMBOL_\w+|iClose|iOpen|iHigh|iLow|'
    r'iMA|iRSI|iATR|iBands|iMACD|iStochastic|CopyTicks\w*|CopyBuffer|CopyClose|CopyHigh|CopyLow|CopyOpen|CopyRates|'
    r'CopyTime|TimeCurrent|TimeLocal|TimeTradeServer|TimeGMT|GetTickCount\w*|GetMicrosecondCount|Sleep|'
    r'MarketBookGet|AccountInfo\w*|Bid|Ask|Close|Open|High|Low)\b\s*(\(|\[)?')
VOLUME = re.compile(r'\b(\w*[Vv]olume\w*|\w*[Ll]ots?\w*|SYMBOL_VOLUME\w*|AccountInfo\w*|OrderCalc\w*)\b')

REQUIRED = ['COSTS_NOT_MODELLED', 'PARTIAL_AT_2R', 'client answer: 80% of initial volume', 'NOT enforced',
            'PROPOSAL', 'exact half tick goes UP', 'AWAY from the entry', 'NOT the client', 'NOT wired',
            'level_2R = E_out +/- 2*R_geom', 'computed from one SL while another SL is reported']


def check_trading(files):
    bad = 0
    for f in files:
        t = strip(open(f, encoding='ascii').read())
        for m in TRADING.finditer(t):
            print('%s: trading API %s' % (f, m.group(0)))
            bad = 1
    return bad


def check_nofeed(files):
    bad = 0
    for f in files:
        t = strip(open(f, encoding='ascii').read())
        for m in FEED.finditer(t):
            name = m.group(1)
            # Close/Open/High/Low only count when used as a call or an array access (series access), not as words
            if name in ('Close', 'Open', 'High', 'Low') and not m.group(2):
                continue
            print('%s: live price/series/clock access %s' % (f, name))
            bad = 1
    return bad


def check_novolume(files):
    bad = 0
    for f in files:
        t = strip(open(f, encoding='ascii').read())
        for m in VOLUME.finditer(t):
            print('%s: volume/lot/sizing identifier %s' % (f, m.group(0)))
            bad = 1
    return bad


def check_contract(files):
    bad = 0
    for f in files:
        raw = open(f, encoding='ascii').read()
        for req in REQUIRED:
            if req not in raw:
                print('%s: required contract text missing: %s' % (f, req))
                bad = 1
        code = strip(raw, keep_strings=True)
        for lab in ('COSTS_NOT_MODELLED', 'PARTIAL_AT_2R', 'NOT enforced'):
            if lab not in code:
                print('%s: label %s is not returned by code (only in comments)' % (f, lab))
                bad = 1
    return bad


def check_parity(files):
    mqh = strip(open(files[0], encoding='ascii').read())
    ref = open(files[1], encoding='ascii').read()
    bad = 0

    def names(prefix, text):
        return set(re.findall(r'\b%s(\w+)\b' % prefix, text))

    ref_status = set(re.findall(r"^([A-Z_]+) = '\1'$", ref, re.M))
    want_status = {'OK', 'INVALID_DIRECTION', 'INVALID_INPUT', 'SL_WRONG_SIDE', 'ZERO_RISK', 'TARGET_WRONG_SIDE',
                   'BELOW_STOPS_LEVEL', 'PENDING_TOO_CLOSE'}
    if not want_status <= ref_status:
        print('reference lacks statuses: %s' % sorted(want_status - ref_status))
        bad = 1
    enum = re.search(r'enum\s+ENUM_TG_STATUS\s*\{(.*?)\}', mqh, re.S)
    got = {x.strip().split('=')[0].replace('TG_', '', 1) for x in enum.group(1).split(',')} if enum else set()
    if got != want_status:
        print('MQL5 status enum differs: only-mql=%s only-ref=%s' % (sorted(got - want_status), sorted(want_status - got)))
        bad = 1
    for lab in re.findall(r"'((?:NONE|NEARER_THAN_2R|EQUAL_TO_2R|FARTHER_THAN_2R|NOT_CHECKED|PASSED|TOO_CLOSE))'", ref):
        if lab not in open(files[0], encoding='ascii').read():
            print('label %s of the reference is missing in the MQL5 module' % lab)
            bad = 1
    return bad


def check_guards(files):
    mqh = strip(open(files[0], encoding='ascii').read(), keep_strings=True)
    ref = strip_py(open(files[1], encoding='ascii').read())
    bad = 0
    for tag in ('INCOMPATIBLE_TICK_DIGITS', 'NONPOSITIVE_PRICE', 'NUMERIC_OVERFLOW'):
        for name, text in (('mqh', mqh), ('py', ref)):
            if tag not in text:
                print('%s: reason tag %s missing in %s code' % (files[0], tag, name))
                bad = 1
    must_mqh = [r'MathPow\(10\.0,digits\)', r'MathAbs\(q-qr\)>TG_EPS_TICKS', r'qr<1\.0', r'e_px<=0\.0 \|\| s_px<=0\.0',
                r'lvl_px<=0\.0', r't_px<=0\.0', r'tp_px<=0\.0', r'!TG_Finite\(e_px\)', r'!TG_Finite\(lvl_px\)']
    must_py = [r'10\.0 \*\* digits', r'abs\(q - qr\) > EPS_TICKS', r'qr < 1', r'e_out <= 0 or s_out <= 0',
               r'level_2r <= 0', r't_price <= 0', r'tp <= 0', r'isfinite\(e_out\)', r'isfinite\(level_2r\)']
    for pat in must_mqh:
        if not re.search(pat, mqh):
            print('%s: guard missing in MQL5: %s' % (files[0], pat))
            bad = 1
    for pat in must_py:
        if not re.search(pat, ref):
            print('%s: guard missing in Python: %s' % (files[1], pat))
            bad = 1
    a = re.search(r'#define\s+TG_MAX_TICKS\s+(\S+)', mqh)
    b = re.search(r'^MAX_TICKS\s*=\s*(\S+)', ref, re.M)
    if not a or not b or float(a.group(1)) != float(b.group(1)):
        print('MAX_TICKS differs or is missing: mqh=%s py=%s' % (a and a.group(1), b and b.group(1)))
        bad = 1
    return bad


def strip_py(text):
    return re.sub(r'(?s)\"\"\".*?\"\"\"|#[^\n]*', '', text)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    kind, files = argv[1], argv[2:]
    fn = {'trading': check_trading, 'nofeed': check_nofeed, 'novolume': check_novolume,
          'contract': check_contract, 'parity': check_parity, 'guards': check_guards}.get(kind)
    if fn is None:
        print('unknown check', kind)
        return 2
    return fn(files)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
