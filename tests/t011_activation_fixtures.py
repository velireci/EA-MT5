"""T011 activation scenarios: each scenario is a sequence of events (quote Q or report R) with the hand-written expected
event status, state, action, result request id/steps and counters after EACH event. emit_mql() produces the flat data block
kept in src/tests/T011_ActivationTest.mq5 (equality is tested). BUY level 2000.0, SELL level 1990.0, 0.10 lot, grid 0.01."""
import t011_activation_reference as a

ROWS = []
_scn = [None]


def scenario(name):
    _scn[0] = name


def Q(pos=7, d=a.BUY, level=2000.0, bid=1999.0, ask=1999.3, vinit=0.10, vcur=0.10, vmin=0.01, step=0.01, vmax=100.0,
      ev='OK', st=a.IDLE, act='NONE', rid='', rs=0, conf=0, dup=0):
    ROWS.append(dict(scn=_scn[0], kind='Q', pos=pos, d=d, level=level, bid=bid, ask=ask, vinit=vinit, vcur=vcur, vmin=vmin,
                     step=step, vmax=vmax, rid='', rkind=0, rvol=0.0, ev=ev, st=st, act=act, xrid=rid, rs=rs, conf=conf, dup=dup))


def R(rid='X2R80-7', kind=a.FULL, vol=0.08, step=0.01, ev='OK', st=a.DONE, act='NONE', conf=0, dup=0):
    ROWS.append(dict(scn=_scn[0], kind='R', pos=0, d=0, level=0.0, bid=0.0, ask=0.0, vinit=0.0, vcur=0.0, vmin=0.0, step=step,
                     vmax=0.0, rid=rid, rkind=kind, rvol=vol, ev=ev, st=st, act=act, xrid='', rs=0, conf=conf, dup=dup))


REQ = dict(ev='OK', st=a.REQUEST_PENDING, act=a.REQUEST_ACTION, rid='X2R80-7', rs=8)
PEND = dict(ev='IGNORED', st=a.REQUEST_PENDING)
S_LVL, S_BID, S_ASK = 1990.0, 1989.5, 1990.0
# ---- BUY / SELL before, at and beyond 2R
scenario('BUY_BEFORE_2R'); Q(bid=1999.99, ask=2000.4)
scenario('BUY_AT_2R'); Q(bid=2000.0, ask=2000.3, **REQ)
scenario('BUY_BEYOND_2R'); Q(bid=2005.0, ask=2005.3, **REQ)
scenario('BUY_USES_BID_NOT_ASK'); Q(bid=1999.8, ask=2000.5)
scenario('SELL_BEFORE_2R'); Q(d=a.SELL, level=S_LVL, bid=1989.9, ask=1990.01)
scenario('SELL_AT_2R'); Q(d=a.SELL, level=S_LVL, bid=1989.7, ask=1990.0, **REQ)
scenario('SELL_BEYOND_2R'); Q(d=a.SELL, level=S_LVL, bid=1984.0, ask=1984.3, **REQ)
scenario('SELL_USES_ASK_NOT_BID'); Q(d=a.SELL, level=S_LVL, bid=1989.5, ask=1990.4)
# ---- repeated quotes, full confirmation, duplicates
scenario('REPEATED_QUOTES_PENDING')
Q(bid=2000.0, ask=2000.3, **REQ); Q(bid=2000.5, ask=2000.8, **PEND); Q(bid=1999.0, ask=1999.3, **PEND); Q(bid=2010.0, ask=2010.3, **PEND)
scenario('FULL_CONFIRMATION_THEN_QUOTES')
Q(bid=2000.0, ask=2000.3, **REQ); R(conf=1, st=a.DONE)
Q(bid=2001.0, ask=2001.3, vcur=0.02, ev='IGNORED', st=a.DONE, conf=1)
Q(bid=1990.0, ask=1990.3, vcur=0.02, ev='IGNORED', st=a.DONE, conf=1)
scenario('DUPLICATE_CONFIRMATION')
Q(bid=2000.0, ask=2000.3, **REQ); R(conf=1, st=a.DONE)
R(ev='DUPLICATE_IGNORED', st=a.DONE, conf=1, dup=1); R(ev='DUPLICATE_IGNORED', st=a.DONE, conf=1, dup=2)
scenario('SELL_FULL_CONFIRMATION'); Q(d=a.SELL, level=S_LVL, bid=1989.0, ask=1989.4, **REQ); R(conf=1, st=a.DONE)
# ---- rejection, timeout, partial execution: reconcile, no retry, no late acceptance
scenario('REJECTED')
Q(bid=2000.0, ask=2000.3, **REQ); R(kind=a.REJECTED, vol=0.0, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
Q(bid=2001.0, ask=2001.3, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
R(kind=a.FULL, vol=0.08, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
R(kind=a.REJECTED, vol=0.0, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
scenario('TIMEOUT')
Q(bid=2000.0, ask=2000.3, **REQ); R(kind=a.TIMEOUT, vol=0.0, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
Q(bid=2002.0, ask=2002.3, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
R(kind=a.FULL, vol=0.08, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
scenario('PARTIAL_EXECUTION')
Q(bid=2000.0, ask=2000.3, **REQ); R(kind=a.PARTIAL, vol=0.05, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
Q(bid=2003.0, ask=2003.3, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
R(kind=a.FULL, vol=0.08, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
scenario('PARTIAL_ONE_STEP'); Q(bid=2000.0, ask=2000.3, **REQ); R(kind=a.PARTIAL, vol=0.01, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
scenario('PARTIAL_SEVEN_STEPS'); Q(bid=2000.0, ask=2000.3, **REQ); R(kind=a.PARTIAL, vol=0.07, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
# ---- wrong id / wrong volume block
scenario('WRONG_ID')
Q(bid=2000.0, ask=2000.3, **REQ); R(rid='X2R80-8', ev='BLOCKED', st=a.BLOCKED)
Q(bid=2001.0, ask=2001.3, ev='BLOCKED', st=a.BLOCKED); R(ev='BLOCKED', st=a.BLOCKED)
scenario('FULL_WRONG_VOLUME_LOW'); Q(bid=2000.0, ask=2000.3, **REQ); R(vol=0.07, ev='BLOCKED', st=a.BLOCKED)
scenario('FULL_WRONG_VOLUME_HIGH'); Q(bid=2000.0, ask=2000.3, **REQ); R(vol=0.10, ev='BLOCKED', st=a.BLOCKED)
scenario('FULL_ZERO_VOLUME'); Q(bid=2000.0, ask=2000.3, **REQ); R(vol=0.0, ev='BLOCKED', st=a.BLOCKED)
scenario('FULL_OFF_GRID'); Q(bid=2000.0, ask=2000.3, **REQ); R(vol=0.075, ev='BLOCKED', st=a.BLOCKED)
scenario('PARTIAL_EQUAL_TO_REQUEST'); Q(bid=2000.0, ask=2000.3, **REQ); R(kind=a.PARTIAL, vol=0.08, ev='BLOCKED', st=a.BLOCKED)
scenario('PARTIAL_ZERO'); Q(bid=2000.0, ask=2000.3, **REQ); R(kind=a.PARTIAL, vol=0.0, ev='BLOCKED', st=a.BLOCKED)
scenario('PARTIAL_ABOVE_REQUEST'); Q(bid=2000.0, ask=2000.3, **REQ); R(kind=a.PARTIAL, vol=0.09, ev='BLOCKED', st=a.BLOCKED)
scenario('REPORT_WITHOUT_REQUEST'); R(ev='BLOCKED', st=a.BLOCKED)
scenario('REPORT_BEFORE_2R'); Q(bid=1999.0, ask=1999.3); R(ev='BLOCKED', st=a.BLOCKED)
scenario('CONFLICTING_REPORT_AFTER_DONE')
Q(bid=2000.0, ask=2000.3, **REQ); R(conf=1, st=a.DONE); R(vol=0.07, ev='BLOCKED', st=a.BLOCKED, conf=1)
scenario('REJECTED_AFTER_DONE')
Q(bid=2000.0, ask=2000.3, **REQ); R(conf=1, st=a.DONE); R(kind=a.REJECTED, vol=0.0, ev='BLOCKED', st=a.BLOCKED, conf=1)
# ---- impossible split and volume reconciliation
scenario('SPLIT_POLICY_UNSET_SEVEN_STEPS')
Q(vinit=0.07, vcur=0.07, bid=2000.0, ask=2000.3, ev='SPLIT_POLICY_UNSET', st=a.IDLE)
Q(vinit=0.07, vcur=0.07, bid=2001.0, ask=2001.3, ev='SPLIT_POLICY_UNSET', st=a.IDLE)
R(ev='BLOCKED', st=a.BLOCKED)
scenario('SPLIT_POLICY_UNSET_REMAINDER_BELOW_MIN'); Q(vinit=0.05, vcur=0.05, vmin=0.02, bid=2000.0, ask=2000.3, ev='SPLIT_POLICY_UNSET', st=a.IDLE)
scenario('SPLIT_POLICY_UNSET_SELL'); Q(d=a.SELL, level=S_LVL, vinit=0.11, vcur=0.11, bid=1989.0, ask=1989.3, ev='SPLIT_POLICY_UNSET', st=a.IDLE)
scenario('SPLIT_BEFORE_2R_IS_NOT_JUDGED'); Q(vinit=0.07, vcur=0.07, bid=1999.0, ask=1999.3)
scenario('VOLUME_MISMATCH_BEFORE_REQUEST')
Q(vcur=0.09, bid=2000.0, ask=2000.3, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
Q(bid=2000.0, ask=2000.3, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION)
scenario('VOLUME_MISMATCH_AFTER_DONE')
Q(bid=2000.0, ask=2000.3, **REQ); R(conf=1, st=a.DONE); Q(bid=2001.0, ask=2001.3, vcur=0.03, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION, conf=1)
Q(bid=2001.0, ask=2001.3, vcur=0.02, ev='RECONCILE_REQUIRED', st=a.NEEDS_RECONCILIATION, conf=1)
scenario('VOLUME_AHEAD_OF_CONFIRMATION_WHILE_PENDING')
Q(bid=2000.0, ask=2000.3, **REQ); Q(bid=2001.0, ask=2001.3, vcur=0.02, **PEND); R(conf=1, st=a.DONE)
# ---- identity
scenario('IDENTITY_POSITION'); Q(bid=1999.0, ask=1999.3); Q(pos=8, bid=2000.0, ask=2000.3, ev='BLOCKED', st=a.BLOCKED)
scenario('IDENTITY_DIRECTION'); Q(bid=1999.0, ask=1999.3); Q(d=a.SELL, bid=2000.0, ask=2000.3, ev='BLOCKED', st=a.BLOCKED)
scenario('IDENTITY_LEVEL'); Q(bid=1999.0, ask=1999.3); Q(level=1999.5, bid=2000.0, ask=2000.3, ev='BLOCKED', st=a.BLOCKED)
scenario('IDENTITY_INITIAL_VOLUME'); Q(bid=1999.0, ask=1999.3); Q(vinit=0.20, vcur=0.20, bid=2000.0, ask=2000.3, ev='BLOCKED', st=a.BLOCKED)
scenario('STABLE_ID_LARGE_POSITION'); Q(pos=123456789012, bid=2000.0, ask=2000.3, ev='OK', st=a.REQUEST_PENDING, act=a.REQUEST_ACTION, rid='X2R80-123456789012', rs=8)
# ---- invalid input changes nothing
scenario('INVALID_QUOTES_THEN_VALID')
Q(pos=0, ev='INVALID_INPUT'); Q(d=0, ev='INVALID_INPUT'); Q(level=0.0, ev='INVALID_INPUT'); Q(bid=0.0, ev='INVALID_INPUT')
Q(bid=2000.4, ask=2000.0, ev='INVALID_INPUT'); Q(vcur=0.0, ev='INVALID_INPUT'); Q(vinit=-0.1, ev='INVALID_INPUT')
Q(bid=2000.0, ask=2000.3, **REQ)
scenario('INVALID_VOLUME_PARAMS_AT_2R'); Q(step=0.0, bid=2000.0, ask=2000.3, ev='INVALID_INPUT'); Q(bid=2000.0, ask=2000.3, **REQ)
scenario('INVALID_REPORTS_KEEP_PENDING')
Q(bid=2000.0, ask=2000.3, **REQ); R(rid='', ev='INVALID_INPUT', st=a.REQUEST_PENDING); R(kind=9, ev='INVALID_INPUT', st=a.REQUEST_PENDING)
R(vol=-0.08, ev='INVALID_INPUT', st=a.REQUEST_PENDING); R(step=0.0, ev='INVALID_INPUT', st=a.REQUEST_PENDING); R(conf=1, st=a.DONE)


def _n(v):
    return repr(float(v))


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t011_activation_fixtures.py emit_mql)']
    out.append('#define NROWS %d' % len(ROWS))

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    names = []
    for r in ROWS:
        if r['scn'] not in names:
            names.append(r['scn'])
    arr('string', 'R_SCN', ['"%s"' % r['scn'] for r in ROWS])
    arr('int', 'R_IS_Q', ['1' if r['kind'] == 'Q' else '0' for r in ROWS])
    arr('long', 'R_POS', [str(r['pos']) for r in ROWS])
    arr('int', 'R_DIR', [str(r['d']) for r in ROWS])
    for nm, k in (('R_LEVEL', 'level'), ('R_BID', 'bid'), ('R_ASK', 'ask'), ('R_VINIT', 'vinit'), ('R_VCUR', 'vcur'),
                  ('R_VMIN', 'vmin'), ('R_STEP', 'step'), ('R_VMAX', 'vmax'), ('R_RVOL', 'rvol')):
        arr('double', nm, [_n(r[k]) for r in ROWS])
    arr('string', 'R_RID', ['"%s"' % r['rid'] for r in ROWS])
    arr('int', 'R_RKIND', [str(r['rkind']) for r in ROWS])
    arr('string', 'X_EVENT', ['"%s"' % r['ev'] for r in ROWS])
    arr('string', 'X_STATE', ['"%s"' % r['st'] for r in ROWS])
    arr('string', 'X_ACTION', ['"%s"' % r['act'] for r in ROWS])
    arr('string', 'X_RID', ['"%s"' % r['xrid'] for r in ROWS])
    arr('long', 'X_RSTEPS', [str(r['rs']) for r in ROWS])
    arr('int', 'X_CONF', [str(r['conf']) for r in ROWS])
    arr('int', 'X_DUP', [str(r['dup']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
