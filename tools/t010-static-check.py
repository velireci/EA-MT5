#!/usr/bin/env python3
"""Static checks for T010 (news and spread filters). Source-text checks only: NOT a compiler, NOT an MT5 run.
Usage: t010-static-check.py KIND FILE...   (exit 1 on a finding)"""
import importlib.util
import re
import sys

spec = importlib.util.spec_from_file_location('t005chk', 'tools/t005-static-check.py')
t5 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(t5)

TRADING = re.compile(r'\b(OrderSend|OrderSendAsync|OrderCheck|OrderClose|OrderModify|OrderDelete|PositionClose|PositionModify|'
                     r'PositionOpen|MqlTradeRequest|MqlTradeResult|MqlTradeCheckResult|CTrade|CPositionInfo|COrderInfo|PositionSelect|OrderSelect|OnTradeTransaction)\b')
CLOCK = re.compile(r'\b(TimeLocal|TimeGMT|TimeCurrent|TimeGMTOffset|TimeDaylightSavings|GetTickCount|EventSetTimer|EventSetMillisecondTimer|Sleep)\s*\(')
PERSIST = re.compile(r'\b(File[A-Z]\w*|GlobalVariable\w*|WebRequest|Socket\w*|Database\w*|ResourceCreate|SendMail|SendNotification|SendFTP)\s*\(')
CAL = re.compile(r'\bCalendar\w+\s*\(')
PY_BAD = re.compile(r'^\s*(import|from)\s+(os|sys_exit|time|datetime|random|json|pickle|sqlite3|socket|subprocess)\b|open\(|print\(', re.M)


def read(f):
    return open(f, encoding='ascii').read()


def body(code, start_marker, end_marker):
    i = code.find(start_marker)
    if i < 0:
        return None
    j = code.find(end_marker, i + len(start_marker))
    return code[i:j] if j >= 0 else code[i:]


def reader_body(code):
    return body(code, 'int ReadUsdCalendar(', 'void Evaluate()')


def news_block(code):
    return body(code, 'if(InpNewsSource==NEWS_SRC_CALENDAR_AUTO)', 'if(InpSpreadSource==SPREAD_SRC_QUOTE_AUTO)')


def fail(f, msg):
    print('%s: %s' % (f, msg))
    return 1


def check_trading(files):
    bad = 0
    for f in files:
        code = t5.strip(read(f))
        if f.endswith('.py'):
            continue
        m = TRADING.search(code)
        if m:
            bad |= fail(f, 'trading API %s' % m.group(0))
    return bad


def check_persist(files):
    bad = 0
    for f in files:
        if f.endswith('.py'):
            m = PY_BAD.search(re.sub(r'(?s)""".*?"""|#[^\n]*', '', read(f)))
        else:
            m = PERSIST.search(t5.strip(read(f)))
        if m:
            bad |= fail(f, 'persistence / file / network / process access %s' % m.group(0).strip())
    return bad


def check_calendar_confined(files):
    """files: header, test, EA. Calendar calls only inside ReadUsdCalendar."""
    hdr, tst, ea = files
    bad = 0
    for f in (hdr, tst):
        if CAL.search(t5.strip(read(f))):
            bad |= fail(f, 'calendar call outside the reader')
    code = t5.strip(read(ea))
    rb = reader_body(code)
    if rb is None:
        return fail(ea, 'ReadUsdCalendar not found')
    rest = code.replace(rb, '')
    if CAL.search(rest):
        bad |= fail(ea, 'calendar call outside ReadUsdCalendar')
    for need in ('CalendarValueHistory(', 'CalendarEventById(', 'CalendarCountryById('):
        if need not in rb:
            bad |= fail(ea, 'reader lacks %s' % need)
    return bad


def check_tester(files):
    ea = files[0]
    rb = reader_body(t5.strip(read(ea)))
    if rb is None:
        return fail(ea, 'ReadUsdCalendar not found')
    i, j = rb.find('MQLInfoInteger(MQL_TESTER)'), rb.find('CalendarValueHistory(')
    if i < 0 or j < 0 or i > j or 'NF_Q_TESTER' not in rb[i:j]:
        return fail(ea, 'tester guard missing or after the first calendar call')
    return 0


def check_server_time(files):
    hdr, ea = files
    bad = 0
    code = t5.strip(read(ea))
    for name, text in (('header', t5.strip(read(hdr))), ('reader', reader_body(code) or ''), ('news block', news_block(code) or '')):
        if not text:
            bad |= fail(ea, '%s not found' % name)
        m = CLOCK.search(text)
        if m:
            bad |= fail(ea, 'clock call %s in %s' % (m.group(0), name))
    if 'datetime now=TimeTradeServer();' not in code:
        bad |= fail(ea, 'now is not TimeTradeServer()')
    if 'ReadUsdCalendar(now,' not in code or 'NF_NewsEvaluate(now,' not in code:
        bad |= fail(ea, 'news path does not use the server-time now')
    return bad


def check_wiring(files):
    """MANUAL stays the default; automatic spread reuses the preview quote; no second quote read; no timer."""
    ea = t5.strip(read(files[0]))
    bad = 0
    for need in ('InpNewsSource=NEWS_SRC_MANUAL', 'InpSpreadSource=SPREAD_SRC_MANUAL', 'InpMaxSpreadPoints=-1',
                 'NF_SpreadEvaluate(quote.bid,quote.ask,symbol.point,InpMaxSpreadPoints,spread)'):
        if need not in ea:
            bad |= fail(files[0], 'missing %s' % need)
    if ea.count('SymbolInfoTick(') != 1 or 'SymbolInfoDouble(_Symbol,SYMBOL_BID' in ea or 'SymbolInfoDouble(_Symbol,SYMBOL_ASK' in ea:
        bad |= fail(files[0], 'a second quote read exists')
    for forbidden in ('OnTimer', 'EventSetTimer', 'OnTick'):
        if forbidden in ea:
            bad |= fail(files[0], 'continuous monitoring hook %s' % forbidden)
    return bad


def check_guards(files):
    hdr = t5.strip(read(files[0]), keep_strings=True)
    bad = 0
    for need in ('d>=-NF_WINDOW_SECONDS && d<=NF_WINDOW_SECONDS', 'spread<=threshold+tolerance',
                 'if(!events[i].fetch_ok) {out.unknown++;continue;}', 'events[i].currency!="USD" || events[i].importance!=NF_IMP_HIGH',
                 'if(!events[i].time_ok || events[i].time<=0) {out.unknown++;continue;}',
                 'if(query_status==NF_Q_TESTER)', 'max_points==NF_SPREAD_UNSET', 'ask<bid'):
        if need not in hdr:
            bad |= fail(files[0], 'guard expression missing: %s' % need)
    return bad


def check_contract(files):
    raw = read(files[0])
    bad = 0
    for req in ('SERVER time', 'both boundaries INCLUDED', 'BLOCKED wins over UNKNOWN', 'NO default', 'NOT decided'):
        if req not in raw:
            bad |= fail(files[0], 'contract text missing: %s' % req)
    return bad


CHECKS = {'trading': check_trading, 'persist': check_persist, 'calendar': check_calendar_confined, 'tester': check_tester,
          'servertime': check_server_time, 'wiring': check_wiring, 'guards': check_guards, 'contract': check_contract}

if __name__ == '__main__':
    if len(sys.argv) < 3 or sys.argv[1] not in CHECKS:
        print(__doc__)
        sys.exit(2)
    sys.exit(CHECKS[sys.argv[1]](sys.argv[2:]))
