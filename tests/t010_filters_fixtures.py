"""Hand-derived T010 cases (shared by tests/test_t010_filters.py and src/tests/T010_FiltersTest.mq5).

NEWS: now = NOW (server-time seconds, arbitrary). An event row is (delta, time_ok, currency, importance, fetch_ok, name) with the
event time = NOW + delta, i.e. delta +1800 means now is exactly 30:00 BEFORE the event (blocks), +1801 is one second outside.
delta -1800 means now is exactly 30:00 AFTER the event (blocks), -1801 is outside. delta None = event time 0 (undefined).
Expected values were reasoned by hand from the contract (window [-1800,+1800] inclusive, USD + HIGH only, BLOCKED beats UNKNOWN,
nearest = smallest |delta|, first one wins a tie), not produced by the code.
SPREAD: bid, ask, point, max; spread = (ask-bid)/point. Real-world quotes like 2000.00/2000.20 compute to 20.000000000004547 in
binary (noise, decimal truth 20) and must be ALLOWED at max 20; 2000.00/2000.20001 is a real 0.001-point excess and must BLOCK.
Special doubles are encoded by markers (NaN / +inf / -inf) so the same table feeds MQL5 (no literal NaN there).
"""
NOW = 1800000000
NAN_M, INF_M, NINF_M = -9.87654321e+250, 9.87654321e+250, -9.87654321e+251
USD, EUR = 'USD', 'EUR'
NONE, LOW, MOD, HIGH = 0, 1, 2, 3
OK, ERR, NOTREADY, TESTER = 0, 1, 2, 3


def ev(delta, cur=USD, imp=HIGH, name='EV', time_ok=True, fetch_ok=True):
    return (delta, time_ok, cur, imp, fetch_ok, name)


# name, events, query_status, now (None = NOW), state, status, blocking, unknown, nearest_delta (None = none), nearest_name
NEWS_CASES = []


def news(name, events, state, status, blocking=0, unknown=0, nearest=None, nname='', q=OK, now=None):
    NEWS_CASES.append(dict(name=name, events=events, q=q, now=NOW if now is None else now, state=state, status=status,
                           blocking=blocking, unknown=unknown, nearest=nearest, nname=nname))


news('EMPTY_NO_ERROR', [], 'CLEAR', 'CLEAR')
news('BEFORE_1800_INCLUDED', [ev(1800, name='A')], 'BLOCKED', 'BLOCKED_WINDOW', 1, 0, 1800, 'A')
news('BEFORE_1799', [ev(1799, name='A')], 'BLOCKED', 'BLOCKED_WINDOW', 1, 0, 1799, 'A')
news('BEFORE_1801_OUTSIDE', [ev(1801)], 'CLEAR', 'CLEAR')
news('AFTER_1800_INCLUDED', [ev(-1800, name='A')], 'BLOCKED', 'BLOCKED_WINDOW', 1, 0, -1800, 'A')
news('AFTER_1799', [ev(-1799, name='A')], 'BLOCKED', 'BLOCKED_WINDOW', 1, 0, -1799, 'A')
news('AFTER_1801_OUTSIDE', [ev(-1801)], 'CLEAR', 'CLEAR')
news('AT_EVENT', [ev(0, name='A')], 'BLOCKED', 'BLOCKED_WINDOW', 1, 0, 0, 'A')
news('EUR_HIGH_IGNORED', [ev(0, cur=EUR)], 'CLEAR', 'CLEAR')
news('USD_MEDIUM_IGNORED', [ev(0, imp=MOD)], 'CLEAR', 'CLEAR')
news('USD_LOW_IGNORED', [ev(0, imp=LOW)], 'CLEAR', 'CLEAR')
news('USD_NONE_IGNORED', [ev(0, imp=NONE)], 'CLEAR', 'CLEAR')
news('EUR_MEDIUM_IGNORED', [ev(0, cur=EUR, imp=MOD)], 'CLEAR', 'CLEAR')
news('FAR_USD_HIGH', [ev(7200), ev(-7200)], 'CLEAR', 'CLEAR')
news('SEVERAL_ONE_BLOCKS', [ev(7200, name='FAR'), ev(600, name='NFP'), ev(-9000, name='OLD')],
     'BLOCKED', 'BLOCKED_WINDOW', 1, 0, 600, 'NFP')
news('TWO_OVERLAPPING_NEAREST', [ev(600, name='A'), ev(-300, name='B')], 'BLOCKED', 'BLOCKED_WINDOW', 2, 0, -300, 'B')
news('TWO_TIE_FIRST_WINS', [ev(300, name='A'), ev(-300, name='B')], 'BLOCKED', 'BLOCKED_WINDOW', 2, 0, 300, 'A')
news('UNKNOWN_AND_BLOCK_BLOCK_WINS', [ev(0, fetch_ok=False), ev(60, name='A')], 'BLOCKED', 'BLOCKED_WINDOW', 1, 1, 60, 'A')
news('UNDEFINED_TIME_AND_BLOCK', [ev(5, time_ok=False), ev(-60, name='A')], 'BLOCKED', 'BLOCKED_WINDOW', 1, 1, -60, 'A')
news('FAR_AND_UNKNOWN', [ev(7200), ev(0, fetch_ok=False)], 'UNKNOWN', 'UNKNOWN_EVENT_DATA', 0, 1)
news('FETCH_FAILED_ALONE', [ev(0, fetch_ok=False)], 'UNKNOWN', 'UNKNOWN_EVENT_DATA', 0, 1)
news('FETCH_FAILED_EVEN_IF_FIELDS_SAY_EUR', [ev(0, cur=EUR, imp=LOW, fetch_ok=False)], 'UNKNOWN', 'UNKNOWN_EVENT_DATA', 0, 1)
news('INCOMPLETE_TWO_UNKNOWN', [ev(0, fetch_ok=False), ev(7200, time_ok=False)], 'UNKNOWN', 'UNKNOWN_EVENT_DATA', 0, 2)
news('TIME_MODE_NOT_DATETIME', [ev(0, time_ok=False)], 'UNKNOWN', 'UNKNOWN_EVENT_DATA', 0, 1)
news('TIME_ZERO', [ev(None)], 'UNKNOWN', 'UNKNOWN_EVENT_DATA', 0, 1)
news('TIME_ZERO_BUT_TIME_OK_FLAG', [ev(None, time_ok=True)], 'UNKNOWN', 'UNKNOWN_EVENT_DATA', 0, 1)
news('EUR_UNDEFINED_TIME_IRRELEVANT', [ev(None, cur=EUR, time_ok=False)], 'CLEAR', 'CLEAR')
news('USD_MEDIUM_TIME_ZERO_IRRELEVANT', [ev(None, imp=MOD)], 'CLEAR', 'CLEAR')
news('QUERY_ERROR', [], 'UNKNOWN', 'UNKNOWN_CALENDAR_ERROR', q=ERR)
news('QUERY_ERROR_WINS_OVER_EVENTS', [ev(0)], 'UNKNOWN', 'UNKNOWN_CALENDAR_ERROR', q=ERR)
news('CALENDAR_NOT_READY', [], 'UNKNOWN', 'UNKNOWN_CALENDAR_NOT_READY', q=NOTREADY)
news('TESTER_UNSUPPORTED', [], 'UNKNOWN', 'UNKNOWN_TESTER_UNSUPPORTED', q=TESTER)
news('TESTER_UNSUPPORTED_WITH_EVENTS', [ev(7200)], 'UNKNOWN', 'UNKNOWN_TESTER_UNSUPPORTED', q=TESTER)
news('INVALID_QUERY_STATUS', [], 'UNKNOWN', 'UNKNOWN_CALENDAR_ERROR', q=9)
news('NOW_ZERO', [], 'UNKNOWN', 'UNKNOWN_INVALID_INPUT', now=0)
news('NOW_NEGATIVE', [], 'UNKNOWN', 'UNKNOWN_INVALID_INPUT', now=-5)

# name, bid, ask, point, max, state, status
SPREAD_CASES = []


def spr(name, bid, ask, point, mx, state, status):
    SPREAD_CASES.append(dict(name=name, bid=bid, ask=ask, point=point, mx=mx, state=state, status=status))


spr('BELOW', 2000.00, 2000.10, .01, 20.0, 'CLEAR', 'CLEAR')
spr('AT_THRESHOLD_BINARY_NOISE_ABOVE', 2000.00, 2000.20, .01, 20.0, 'CLEAR', 'CLEAR')
spr('AT_THRESHOLD_NOISE_2310', 2310.2, 2310.4, .01, 20.0, 'CLEAR', 'CLEAR')
spr('AT_THRESHOLD_NOISE_BELOW', 1950.4, 1950.6, .01, 20.0, 'CLEAR', 'CLEAR')
spr('AT_THRESHOLD_ONE_ULP_ABOVE_20', 1.0, 21.000000000000004, 1.0, 20.0, 'CLEAR', 'CLEAR')
spr('REAL_EXCESS_0_001_POINT', 2000.00, 2000.20001, .01, 20.0, 'BLOCKED', 'BLOCKED')
spr('ABOVE_ONE_POINT', 2000.00, 2000.21, .01, 20.0, 'BLOCKED', 'BLOCKED')
spr('FAR_ABOVE', 2000.00, 2005.00, .01, 20.0, 'BLOCKED', 'BLOCKED')
spr('ZERO_SPREAD_THRESHOLD_20', 2000.00, 2000.00, .01, 20.0, 'CLEAR', 'CLEAR')
spr('ZERO_SPREAD_THRESHOLD_0', 2000.00, 2000.00, .01, 0.0, 'CLEAR', 'CLEAR')
spr('POSITIVE_SPREAD_THRESHOLD_0', 2000.00, 2000.10, .01, 0.0, 'BLOCKED', 'BLOCKED')
spr('POINT_0_001_AT_THRESHOLD', 100.000, 100.020, .001, 20.0, 'CLEAR', 'CLEAR')
spr('THRESHOLD_UNSET', 2000.00, 2000.10, .01, -1.0, 'UNKNOWN', 'POLICY_UNSET')
spr('THRESHOLD_NAN', 2000.00, 2000.10, .01, NAN_M, 'UNKNOWN', 'INVALID_THRESHOLD')
spr('THRESHOLD_INF', 2000.00, 2000.10, .01, INF_M, 'UNKNOWN', 'INVALID_THRESHOLD')
spr('THRESHOLD_NEG_INF', 2000.00, 2000.10, .01, NINF_M, 'UNKNOWN', 'INVALID_THRESHOLD')
spr('THRESHOLD_NEGATIVE_HALF', 2000.00, 2000.10, .01, -0.5, 'UNKNOWN', 'INVALID_THRESHOLD')
spr('THRESHOLD_NEGATIVE_TWO', 2000.00, 2000.10, .01, -2.0, 'UNKNOWN', 'INVALID_THRESHOLD')
spr('UNSET_WINS_OVER_BAD_QUOTE', NAN_M, 2000.10, .01, -1.0, 'UNKNOWN', 'POLICY_UNSET')
spr('QUOTE_BID_NAN', NAN_M, 2000.10, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_ASK_NAN', 2000.00, NAN_M, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_BID_INF', INF_M, 2000.10, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_ASK_INF', 2000.00, INF_M, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_ASK_NEG_INF', 2000.00, NINF_M, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_BID_ZERO', 0.0, 2000.10, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_BID_NEGATIVE', -1.0, 2000.10, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_ASK_ZERO', 2000.00, 0.0, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_ASK_NEGATIVE', 2000.00, -1.0, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_ASK_BELOW_BID', 2000.10, 2000.00, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('QUOTE_BOTH_ZERO', 0.0, 0.0, .01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('POINT_ZERO', 2000.00, 2000.10, 0.0, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('POINT_NEGATIVE', 2000.00, 2000.10, -.01, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('POINT_NAN', 2000.00, 2000.10, NAN_M, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('POINT_INF', 2000.00, 2000.10, INF_M, 20.0, 'UNKNOWN', 'INVALID_QUOTE')
spr('SPREAD_OVERFLOW', 1.0, 1e+308, 1e-300, 20.0, 'UNKNOWN', 'INVALID_QUOTE')


def real(v):
    return {'NAN': float('nan'), 'INF': float('inf'), 'NINF': float('-inf')}.get(
        {NAN_M: 'NAN', INF_M: 'INF', NINF_M: 'NINF'}.get(v), v)


def _num(v):
    return repr(float(v))


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t010_filters_fixtures.py emit_mql)']

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    def q(s):
        return '"%s"' % s

    out.append('#define NOW_T %d' % NOW)
    out.append('#define NAN_M %s' % _num(NAN_M))
    out.append('#define INF_M %s' % _num(INF_M))
    out.append('#define NINF_M %s' % _num(NINF_M))
    N = NEWS_CASES
    out.append('#define NNEWS %d' % len(N))
    arr('string', 'N_NAME', [q(c['name']) for c in N])
    arr('int', 'N_Q', [str(c['q']) for c in N])
    arr('long', 'N_NOW', [str(c['now']) for c in N])
    arr('string', 'N_STATE', [q(c['state']) for c in N])
    arr('string', 'N_STATUS', [q(c['status']) for c in N])
    arr('int', 'N_BLOCKING', [str(c['blocking']) for c in N])
    arr('int', 'N_UNKNOWN', [str(c['unknown']) for c in N])
    arr('int', 'N_HASNEAR', ['0' if c['nearest'] is None else '1' for c in N])
    arr('long', 'N_NEAR', [str(c['nearest'] or 0) for c in N])
    arr('string', 'N_NEARNAME', [q(c['nname']) for c in N])
    arr('int', 'N_EVFIRST', [str(sum(len(x['events']) for x in N[:i])) for i in range(len(N))])
    arr('int', 'N_EVCOUNT', [str(len(c['events'])) for c in N])
    E = [e for c in N for e in c['events']]
    out.append('#define NEV %d' % len(E))
    arr('int', 'E_ZERO', ['1' if e[0] is None else '0' for e in E])
    arr('long', 'E_DELTA', [str(e[0] or 0) for e in E])
    arr('int', 'E_TIMEOK', ['1' if e[1] else '0' for e in E])
    arr('string', 'E_CUR', [q(e[2]) for e in E])
    arr('int', 'E_IMP', [str(e[3]) for e in E])
    arr('int', 'E_FETCH', ['1' if e[4] else '0' for e in E])
    arr('string', 'E_NAME', [q(e[5]) for e in E])
    S = SPREAD_CASES
    out.append('#define NSPR %d' % len(S))
    arr('string', 'S_NAME', [q(c['name']) for c in S])
    for key, nm in (('bid', 'S_BID'), ('ask', 'S_ASK'), ('point', 'S_POINT'), ('mx', 'S_MAX')):
        arr('double', nm, [_num(c[key]) for c in S])
    arr('string', 'S_STATE', [q(c['state']) for c in S])
    arr('string', 'S_STATUS', [q(c['status']) for c in S])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)
