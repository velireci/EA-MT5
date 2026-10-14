#!/usr/bin/env python3
"""Pattern checks for tools/t004-static-checks.sh (comments and string literals are stripped first).

Usage: t004-static-check.py trading|nofeed|isolation FILE...
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
    r'\b(SymbolInfoTick|SymbolInfoDouble|SymbolInfoInteger|SYMBOL_BID|SYMBOL_ASK|SYMBOL_LAST|iClose|iOpen|iHigh|iLow|'
    r'iMA|iRSI|iATR|iBands|iMACD|iStochastic|CopyTicks\w*|CopyBuffer|CopyClose|CopyHigh|CopyLow|CopyOpen|'
    r'TimeCurrent|TimeLocal|TimeTradeServer|TimeGMT|GetMicrosecondCount|Sleep|MarketBookGet|Bid|Ask)\b')


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
        raw = open(f, encoding='ascii').read()
        t = strip(raw)
        for m in FEED.finditer(t):
            print('%s: live price/clock/indicator access %s' % (f, m.group(1)))
            bad = 1
        for m in re.finditer(r'\bGetTickCount\w*\s*\(', t):
            line = t[:m.start()].count('\n')
            text = t.splitlines()[line].strip()
            only_ea = f.endswith('XauUsdM15Observer.mq5')
            allowed = only_ea and (text.startswith('uint began=GetTickCount();') or
                                   text.startswith('g_duration=GetTickCount()-began;'))
            if not allowed:
                print('%s: GetTickCount outside the replay-duration use: %s' % (f, text))
                bad = 1
    return bad


def check_isolation(files):
    bad = 0
    for f in files:
        raw = open(f, encoding='ascii').read()
        t = strip(raw, keep_strings=True)
        if not re.search(r'string\s+PREFIX\s*=\s*"velo_t004_"\s*;', t):
            print('%s: PREFIX is not exactly "velo_t004_"' % f)
            bad = 1
        calls = re.findall(r'ObjectsDeleteAll\s*\(([^;]*)\)\s*;', t)
        if not calls:
            print('%s: no ObjectsDeleteAll call found (vacuous check)' % f)
            bad = 1
        for a in calls:
            if a.replace(' ', '') != '0,PREFIX':
                print('%s: ObjectsDeleteAll with a non-PREFIX argument (%s)' % (f, a))
                bad = 1
        creates = re.findall(r'ObjectCreate\s*\(\s*0\s*,\s*([^,]+),', t)
        if not creates:
            print('%s: no ObjectCreate call found (vacuous check)' % f)
            bad = 1
        for a in creates:
            a = a.strip()
            if not (a in ('name', 'bg') or a.startswith('PREFIX+')):
                print('%s: ObjectCreate with a name not derived from PREFIX (%s)' % (f, a))
                bad = 1
        for m in re.finditer(r'\b(name|bg)\s*=\s*([^;]+);', t):
            if not m.group(2).strip().startswith('PREFIX'):
                print('%s: ObjectCreate name variable %s not PREFIX-based (%s)' % (f, m.group(1), m.group(2)))
                bad = 1
        if 'ObjectCreate(' in t and 'ObjectDelete(' in t:
            print('%s: single-object ObjectDelete found (review)' % f)
            bad = 1
    return bad


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    kind, files = argv[1], argv[2:]
    fn = {'trading': check_trading, 'nofeed': check_nofeed, 'isolation': check_isolation}.get(kind)
    if fn is None:
        print('unknown check', kind)
        return 2
    return fn(files)


if __name__ == '__main__':
    sys.exit(main(sys.argv))
