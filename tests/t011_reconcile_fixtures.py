"""T011 reconciliation scenarios: activation events (Q quote, R report) build the state, S rows are caller-supplied snapshots.
Hand-written expectations after EACH row. BUY level 2000.0 (SELL 1990.0), initial 0.5 lot, grid 0.01: the request is 0.4 lot = 40 steps,
the remainder 0.1 lot. emit_mql() produces the flat data block of src/tests/T011_ReconcileTest.mq5 (equality is tested)."""
import t011_activation_reference as a

ROWS = []
_scn = [None]
RID = 'X2R80-7'
MAXE = 4


def scenario(name):
    _scn[0] = name


def _blank():
    return dict(scn=_scn[0], kind='', pos=0, d=0, level=0.0, bid=0.0, ask=0.0, vinit=0.0, vcur=0.0, vmin=0.0, step=0.01, vmax=0.0,
                rid='', rkind=0, rvol=0.0, found=1, comp=0, ex=[], dec='', st='', lk=0, dup=0, unl=0, chg=0, conf=-1)


def Q(d=a.BUY, level=2000.0, bid=2000.0, ask=2000.3, vinit=0.5, vcur=0.5, st=a.REQUEST_PENDING, pos=7, vmin=0.01, step=0.01, conf=-1):
    r = _blank()
    r.update(kind='Q', pos=pos, d=d, level=level, bid=bid, ask=ask, vinit=vinit, vcur=vcur, vmin=vmin, step=step, vmax=100.0, st=st, conf=conf)
    ROWS.append(r)


def R(kind, vol=0.0, st=a.NEEDS_RECONCILIATION, rid=RID, step=0.01, conf=-1):
    r = _blank()
    r.update(kind='R', rid=rid, rkind=kind, rvol=vol, step=step, st=st, conf=conf)
    ROWS.append(r)


def S(dec, st, ex=(), vcur=0.1, comp=None, found=1, pos=7, rid=RID, step=0.01, lk=0, dup=0, unl=0, chg=0, conf=-1):
    if comp is None:                    # only a complete list can be CONFIRMED (round of 7ac7f4b review)
        comp = 1 if dec == 'CONFIRMED' else 0
    r = _blank()
    r.update(kind='S', found=found, pos=pos, rid=rid, step=step, vcur=vcur, comp=comp, ex=list(ex), dec=dec, st=st, lk=lk, dup=dup,
             unl=unl, chg=chg, conf=(0 if conf == -1 else conf))
    ROWS.append(r)


def E(i, vol, rid=RID):
    return (i, rid, vol)


PEND, REC, DONE, BLK = a.REQUEST_PENDING, a.NEEDS_RECONCILIATION, a.DONE, a.BLOCKED
QSELL = dict(d=a.SELL, level=1990.0, bid=1989.0, ask=1989.4)
# ---- full fills
scenario('BUY_FULL_FILL_ONE_EXECUTION'); Q(); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
scenario('SELL_FULL_FILL_ONE_EXECUTION'); Q(**QSELL); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
scenario('BUY_FULL_FILL_TWO_EXECUTIONS'); Q(); S('CONFIRMED', DONE, [E('e1', 0.25), E('e2', 0.15)], lk=40, chg=1, conf=1)
scenario('BUY_FULL_FILL_FOUR_EXECUTIONS'); Q(); S('CONFIRMED', DONE, [E('e1', 0.1), E('e2', 0.1), E('e3', 0.1), E('e4', 0.1)], lk=40, chg=1, conf=1)
scenario('BUY_CONFIRMED_AGAIN_IS_NOT_COUNTED_AGAIN')
Q(); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=0, conf=1)
# ---- several partial fills over time
scenario('BUY_PARTIAL_FILLS_THEN_FULL')
Q(); S('PARTIAL', REC, [E('e1', 0.1)], vcur=0.4, lk=10, chg=1)
S('PARTIAL', REC, [E('e1', 0.1), E('e2', 0.2)], vcur=0.2, lk=30, chg=1)
S('PARTIAL', REC, [E('e1', 0.1), E('e2', 0.2)], vcur=0.2, lk=30, chg=0)
S('CONFIRMED', DONE, [E('e1', 0.1), E('e2', 0.2), E('e3', 0.1)], lk=40, chg=1, conf=1)
scenario('SELL_PARTIAL_FILLS_THEN_FULL')
Q(**QSELL); S('PARTIAL', REC, [E('e1', 0.3)], vcur=0.2, lk=30, chg=1); S('CONFIRMED', DONE, [E('e1', 0.3), E('e2', 0.1)], lk=40, chg=1, conf=1)
scenario('BUY_PARTIAL_REPORT_THEN_SNAPSHOT_FULL')
Q(); R(a.PARTIAL, 0.1); S('CONFIRMED', DONE, [E('e1', 0.1), E('e2', 0.3)], lk=40, chg=1, conf=1)
# ---- duplicates inside a snapshot
scenario('BUY_DUPLICATE_EXECUTION_COUNTED_ONCE')
Q(); S('CONFIRMED', DONE, [E('e1', 0.4), E('e1', 0.4)], lk=40, dup=1, chg=1, conf=1)
scenario('SELL_DUPLICATE_EXECUTION_COUNTED_ONCE')
Q(**QSELL); S('PARTIAL', REC, [E('e1', 0.2), E('e1', 0.2)], vcur=0.3, lk=20, dup=1, chg=1)
scenario('BUY_THREE_COPIES_OF_ONE_EXECUTION')
Q(); S('PARTIAL', REC, [E('e1', 0.2), E('e1', 0.2), E('e1', 0.2)], vcur=0.3, lk=20, dup=2, chg=1)
scenario('BUY_EXECUTION_ID_CONFLICT_VOLUME')
Q(); S('BLOCK', BLK, [E('e1', 0.2), E('e1', 0.1)], vcur=0.3, chg=1)
scenario('BUY_EXECUTION_ID_CONFLICT_REQUEST')
Q(); S('BLOCK', BLK, [E('e1', 0.2), E('e1', 0.2, 'X2R80-9')], vcur=0.3, chg=1)
scenario('BUY_UNLINKED_EXECUTION_IGNORED')
Q(); S('CONFIRMED', DONE, [E('o1', 0.4, 'X2R80-9'), E('e1', 0.4)], lk=40, unl=1, chg=1, conf=1)
# ---- late fill after timeout / rejection; a quote never unblocks
scenario('BUY_TIMEOUT_THEN_LATE_FILL')
Q(); R(a.TIMEOUT)
Q(bid=2001.0, ask=2001.3, st=REC); Q(bid=2002.0, ask=2002.3, st=REC)
R(a.FULL, 0.4, st=REC)
S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
Q(bid=2003.0, ask=2003.3, vcur=0.1, st=DONE)
scenario('SELL_TIMEOUT_THEN_LATE_FILL')
Q(**QSELL); R(a.TIMEOUT); Q(d=a.SELL, level=1990.0, bid=1988.0, ask=1988.4, st=REC)
S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
scenario('BUY_TIMEOUT_THEN_PARTIAL_LATE_FILL_STAYS_FOR_RECONCILIATION')
Q(); R(a.TIMEOUT); S('PARTIAL', REC, [E('e1', 0.15)], vcur=0.35, lk=15, chg=1)
Q(bid=2001.0, ask=2001.3, st=REC)
scenario('BUY_TIMEOUT_THEN_SNAPSHOT_WITHOUT_FILL')
Q(); R(a.TIMEOUT); S('NOT_EXECUTED', REC, [], vcur=0.5, comp=1); S('UNKNOWN', REC, [], vcur=0.5, comp=0)
scenario('BUY_REJECTED_THEN_FILL_EVIDENCE')
Q(); R(a.REJECTED); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
# ---- a volume drop alone, manual change
scenario('BUY_VOLUME_DROP_ALONE_INCOMPLETE')
Q(); R(a.TIMEOUT); S('UNKNOWN', REC, [], vcur=0.1, comp=0); S('UNKNOWN', REC, [], vcur=0.1, comp=0)
scenario('BUY_VOLUME_DROP_ALONE_COMPLETE_BLOCKS')
Q(); S('BLOCK', BLK, [], vcur=0.1, comp=1, chg=1)
scenario('SELL_VOLUME_DROP_ALONE_PENDING_STAYS')
Q(**QSELL); S('UNKNOWN', PEND, [], vcur=0.2, comp=0)
scenario('BUY_MANUAL_EXTRA_CLOSE_AFTER_FULL_FILL')
Q(); S('BLOCK', BLK, [E('e1', 0.4)], vcur=0.07, chg=1, lk=40)
scenario('BUY_MANUAL_PARTIAL_UNDO_AFTER_FULL_FILL')
Q(); S('BLOCK', BLK, [E('e1', 0.4)], vcur=0.15, chg=1, lk=40)
scenario('BUY_MANUAL_CHANGE_DURING_PARTIAL_INCOMPLETE_IS_UNKNOWN')
Q(); S('UNKNOWN', PEND, [E('e1', 0.1)], vcur=0.3, comp=0, lk=10)
scenario('BUY_MANUAL_CHANGE_DURING_PARTIAL_COMPLETE_BLOCKS')
Q(); S('BLOCK', BLK, [E('e1', 0.1)], vcur=0.3, comp=1, chg=1, lk=10)
scenario('BUY_VOLUME_OFF_GRID')
Q(); S('BLOCK', BLK, [E('e1', 0.4)], vcur=0.105, chg=1, lk=40)
# ---- identity, grid, missing position, overfill: block; a later snapshot or event changes nothing
scenario('BUY_WRONG_POSITION'); Q(); S('BLOCK', BLK, [E('e1', 0.4)], pos=8, chg=1); S('BLOCK', BLK, [E('e1', 0.4)], chg=0); Q(bid=2001.0, ask=2001.3, st=BLK)
scenario('SELL_WRONG_REQUEST_ID'); Q(**QSELL); S('BLOCK', BLK, [E('e1', 0.4)], rid='X2R80-8', chg=1)
scenario('BUY_STEP_CHANGED'); Q(); S('BLOCK', BLK, [E('e1', 0.04)], step=0.001, chg=1)
scenario('SELL_STEP_CHANGED_SAME_VOLUME'); Q(**QSELL); S('BLOCK', BLK, [E('e1', 0.4)], step=0.001, chg=1)
scenario('BUY_POSITION_MISSING'); Q(); S('BLOCK', BLK, [E('e1', 0.4)], found=0, chg=1)
scenario('BUY_POSITION_MISSING_NO_PROOF'); Q(); R(a.TIMEOUT); S('BLOCK', BLK, [], found=0, comp=0, chg=1)
scenario('BUY_OVERFILL'); Q(); S('BLOCK', BLK, [E('e1', 0.4), E('e2', 0.1)], vcur=0.05, chg=1, lk=50)
scenario('BUY_EXECUTION_OFF_GRID'); Q(); S('BLOCK', BLK, [E('e1', 0.075)], vcur=0.425, chg=1)
scenario('BUY_ALREADY_BLOCKED_SNAPSHOT_CHANGES_NOTHING')
Q(); R(a.FULL, 0.3, st=BLK); S('BLOCK', BLK, [E('e1', 0.4)], chg=0)
# ---- no request / invalid snapshots
scenario('BUY_NO_REQUEST_BEFORE_2R'); Q(bid=1999.0, ask=1999.3, st=a.IDLE); S('UNKNOWN', a.IDLE, [], vcur=0.5)
scenario('BUY_NO_REQUEST_SPLIT_POLICY_UNSET'); Q(vinit=0.07, vcur=0.07, st=a.IDLE); S('UNKNOWN', a.IDLE, [], vcur=0.07)
scenario('BUY_NO_REQUEST_VOLUME_MISMATCH_BEFORE_REQUEST'); Q(vcur=0.45, st=REC); S('UNKNOWN', REC, [E('e1', 0.4)], vcur=0.1)
scenario('BUY_INVALID_SNAPSHOTS_CHANGE_NOTHING')
Q(); S('INVALID_INPUT', PEND, [], rid=''); S('INVALID_INPUT', PEND, [], vcur=0.0); S('INVALID_INPUT', PEND, [], step=0.0)
S('INVALID_INPUT', PEND, [E('', 0.4)]); S('INVALID_INPUT', PEND, [E('e1', 0.0)]); S('INVALID_INPUT', PEND, [], pos=0)
S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
# ---- a DONE state is re-checked, never silently kept
scenario('BUY_DONE_THEN_CONSISTENT_SNAPSHOT'); Q(); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=0, conf=1)
scenario('BUY_DONE_THEN_MANUAL_CHANGE'); Q(); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1); S('BLOCK', BLK, [E('e1', 0.4)], vcur=0.07, lk=40, chg=1, conf=1)
scenario('BUY_DONE_THEN_FEWER_EXECUTIONS'); Q(); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1); S('PARTIAL', REC, [E('e1', 0.1)], vcur=0.4, lk=10, chg=1, conf=1)
scenario('BUY_DONE_THEN_UNKNOWN_EVIDENCE'); Q(); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1); S('UNKNOWN', REC, [], vcur=0.5, comp=0, chg=1, conf=1)

# ---- review of 7ac7f4b: ONE confirmation per request, also when DONE is lost and regained
FULL_OK = dict(ex=[E('e1', 0.4)], lk=40)
scenario('BUY_FULL_THEN_UNKNOWN_THEN_SAME_FULL')
Q(); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
S('UNKNOWN', REC, [], vcur=0.1, comp=0, chg=1, conf=1)
S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
scenario('SELL_FULL_THEN_UNKNOWN_THEN_SAME_FULL')
Q(**QSELL); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
S('UNKNOWN', REC, [], vcur=0.1, comp=0, chg=1, conf=1)
S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
scenario('BUY_REPEATED_LOSS_AND_REGAIN_CYCLES')
Q()
for _i in range(4):
    S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
    S('UNKNOWN', REC, [], vcur=0.1, comp=0, chg=1, conf=1)
scenario('SELL_REPEATED_LOSS_AND_REGAIN_CYCLES')
Q(**QSELL)
for _i in range(4):
    S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
    S('PARTIAL', REC, [E('e1', 0.1)], vcur=0.4, lk=10, chg=1, conf=1)
scenario('BUY_LOSS_THEN_PLAIN_REPORT_AND_QUOTES_CANNOT_REGAIN_DONE')
Q(); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1); S('UNKNOWN', REC, [], vcur=0.1, comp=0, chg=1, conf=1)
R(a.FULL, 0.4, st=REC, conf=1); R(a.TIMEOUT, 0.0, st=REC, conf=1); Q(bid=2003.0, ask=2003.3, vcur=0.1, st=REC, conf=1)
S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
scenario('SELL_LOSS_THEN_PLAIN_REPORT_AND_QUOTES_CANNOT_REGAIN_DONE')
Q(**QSELL); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1); S('UNKNOWN', REC, [], vcur=0.1, comp=0, chg=1, conf=1)
R(a.FULL, 0.4, st=REC, conf=1); Q(d=a.SELL, level=1990.0, bid=1988.0, ask=1988.4, vcur=0.1, st=REC, conf=1)
S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
scenario('BUY_BLOCKED_AFTER_LOSS_KEEPS_ONE_CONFIRMATION')
Q(); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1); S('BLOCK', BLK, [E('e1', 0.4)], vcur=0.07, lk=40, chg=1, conf=1)
S('BLOCK', BLK, [E('e1', 0.4)], lk=0, chg=0, conf=1)
# ---- review of 7ac7f4b: CONFIRMED needs a complete list; a matching sum of volume does not make the list complete
scenario('BUY_MATCHING_SUM_BUT_INCOMPLETE_LIST_IS_UNKNOWN')
Q(); S('UNKNOWN', PEND, [E('e1', 0.4)], lk=40, comp=0); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
scenario('SELL_MATCHING_SUM_BUT_INCOMPLETE_LIST_IS_UNKNOWN')
Q(**QSELL); S('UNKNOWN', PEND, [E('e1', 0.3), E('e2', 0.1)], lk=40, comp=0); S('CONFIRMED', DONE, [E('e1', 0.3), E('e2', 0.1)], lk=40, chg=1, conf=1)
scenario('BUY_TIMEOUT_THEN_INCOMPLETE_FULL_STAYS_FOR_RECONCILIATION')
Q(); R(a.TIMEOUT); S('UNKNOWN', REC, [E('e1', 0.4)], lk=40, comp=0); S('CONFIRMED', DONE, [E('e1', 0.4)], lk=40, chg=1, conf=1)
scenario('BUY_INCOMPLETE_LIST_WITH_DUPLICATE_STILL_UNKNOWN')
Q(); S('UNKNOWN', PEND, [E('e1', 0.4), E('e1', 0.4)], lk=40, dup=1, comp=0)
scenario('BUY_INCOMPLETE_FULL_WITH_MANUAL_CHANGE_STILL_BLOCKS')
Q(); S('BLOCK', BLK, [E('e1', 0.4)], vcur=0.07, comp=0, lk=40, chg=1)


def _n(v):
    return repr(float(v))


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t011_reconcile_fixtures.py emit_mql)']
    out.append('#define NROWS %d' % len(ROWS))
    out.append('#define MAXE %d' % MAXE)

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    kinds = {'Q': 0, 'R': 1, 'S': 2}
    arr('string', 'R_SCN', ['"%s"' % r['scn'] for r in ROWS])
    arr('int', 'R_KIND', [str(kinds[r['kind']]) for r in ROWS])
    arr('long', 'R_POS', [str(r['pos']) for r in ROWS])
    arr('int', 'R_DIR', [str(r['d']) for r in ROWS])
    for nm, k in (('R_LEVEL', 'level'), ('R_BID', 'bid'), ('R_ASK', 'ask'), ('R_VINIT', 'vinit'), ('R_VCUR', 'vcur'), ('R_VMIN', 'vmin'),
                  ('R_STEP', 'step'), ('R_VMAX', 'vmax'), ('R_RVOL', 'rvol')):
        arr('double', nm, [_n(r[k]) for r in ROWS])
    arr('string', 'R_RID', ['"%s"' % r['rid'] for r in ROWS])
    arr('int', 'R_RKIND', [str(r['rkind']) for r in ROWS])
    arr('int', 'R_FOUND', [str(r['found']) for r in ROWS])
    arr('int', 'R_COMP', [str(r['comp']) for r in ROWS])
    arr('int', 'R_NEX', [str(len(r['ex'])) for r in ROWS])
    ids, reqs, vols = [], [], []
    for r in ROWS:
        for k in range(MAXE):
            e = r['ex'][k] if k < len(r['ex']) else ('', '', 0.0)
            ids.append('"%s"' % e[0])
            reqs.append('"%s"' % e[1])
            vols.append(_n(e[2]))
    arr('string', 'E_ID', ids)
    arr('string', 'E_REQ', reqs)
    arr('double', 'E_VOL', vols)
    arr('string', 'X_DEC', ['"%s"' % r['dec'] for r in ROWS])
    arr('string', 'X_STATE', ['"%s"' % r['st'] for r in ROWS])
    arr('long', 'X_LINKED', [str(r['lk']) for r in ROWS])
    arr('int', 'X_DUP', [str(r['dup']) for r in ROWS])
    arr('int', 'X_UNL', [str(r['unl']) for r in ROWS])
    arr('int', 'X_CHG', [str(r['chg']) for r in ROWS])
    arr('int', 'X_CONF', [str(r['conf']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
