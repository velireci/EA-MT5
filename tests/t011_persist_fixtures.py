"""T011 persistence scenarios (pure codec + restore). Records are built by hand; the texts come from the reference encoder, the corrupted ones by hand-written
edits (some re-sealed with a valid CRC to reach the semantic validation). Expected verdicts / statuses / flags are written by hand per row.
emit_mql() produces the flat data block of src/tests/T011_PersistTest.mq5 (equality is tested)."""
import t011_activation_reference as act
import t011_persist_reference as p

IDENT = p.Identity('MetaQuotes-Demo', 5001234, 'XAUUSD.r', 987654)
RID = act.request_id_for(987654)
ROWS = []


def bound(**kw):
    s = act.State(status=act.IDLE, bound=True, position_id=987654, direction=1, level=4310.5, volume_initial=0.5)
    for k, v in kw.items():
        setattr(s, k, v)
    return s


def pending(**kw):
    d = dict(status=act.REQUEST_PENDING, volume_step=0.01, request_id=RID, request_steps=40, close_volume=0.4, initial_steps=50)
    d.update(kw)
    return bound(**d)


PLAN = dict(plan_set=True, plan_tp=4320.5, plan_vol_min=0.01, plan_vol_step=0.01, plan_vol_max=100.0, plan_rpol=p.RPOL_TYPED)       # diagnostic typed level: no E / S
# R_GEOM: the declared basis (source and TG-normalized E and S) is stored; the level (bound(): 4310.5) and the direction live in the bound state
PLAN_GEOM = dict(plan_set=True, plan_tp=4320.5, plan_vol_min=0.01, plan_vol_step=0.01, plan_vol_max=100.0, plan_rpol=p.RPOL_R_GEOM,
                 plan_e_src=4300.0, plan_s_src=4295.0, plan_e_out=4300.0, plan_s_out=4295.0)
PLAN_GEOM_SELL = dict(PLAN_GEOM, plan_tp=4280.5, plan_e_src=4300.0, plan_s_src=4305.0, plan_e_out=4300.0, plan_s_out=4305.0)


def rec(state, phase=p.SEND_NONE, orders=(), complete=False, gen=3, ident=IDENT, plan=False):
    """plan: False / True (typed diagnostic) / 'geom' (BUY R_GEOM) / 'sell' (SELL R_GEOM)"""
    kw = {'geom': PLAN_GEOM, 'sell': PLAN_GEOM_SELL}.get(plan, PLAN if plan else {})
    return p.Record(gen, ident, state, phase, complete, list(orders), **kw)


def text_of(r):
    ok, t = p.encode(r)
    assert ok, t
    return t


def reseal(text, old, new):
    """replace `old` by `new` inside the body and compute a valid CRC again (reaches the semantic validation)."""
    body = text[:text.index('CRC=')]
    assert old in body, old
    body = body.replace(old, new, 1)
    return body + 'CRC=%08X\n' % p.crc32(body)


def row(name, text, verdict, status, new_req=0, recon=0, reason='', kind='text', canon=0, conf=0, executed=0, ident=IDENT, nord=0, gen=0, plan=0):
    ROWS.append(dict(name=name, kind=kind, text=text, ident=ident, verdict=verdict, status=status, new_req=new_req, recon=recon, reason=reason, canon=canon, conf=conf,
                     executed=executed, nord=nord, gen=gen, plan=plan))


PZ = ('PLAN_SET=0\nPLAN_TP=0.000000000000\nPLAN_VOL_MIN=0.000000000000\nPLAN_VOL_STEP=0.000000000000\nPLAN_VOL_MAX=0.000000000000\nPLAN_RPOL=0\n'
      'PLAN_E_SRC=0.000000000000\nPLAN_S_SRC=0.000000000000\nPLAN_E_OUT=0.000000000000\nPLAN_S_OUT=0.000000000000\n')
U, R, B, X = p.USABLE_IDLE, p.USABLE_REQUEST, p.USABLE_BLOCKED, p.RECOVERY_REQUIRED
# ---- usable records
t_idle0 = text_of(rec(act.State(), gen=1))
t_idle1 = text_of(rec(bound(), gen=2))
t_pend = text_of(rec(pending(), p.SEND_MAPPED, [111222], gen=4))
t_pend_intent = text_of(rec(pending(), p.SEND_INTENT, gen=4))
t_done = text_of(rec(pending(status=act.DONE, executed_steps=40, confirmations=1, duplicates_ignored=2), p.SEND_MAPPED, [111222, 111223], True, gen=7))
t_nr = text_of(rec(pending(status=act.NEEDS_RECONCILIATION, executed_steps=10, reason='PARTIAL_EXECUTION: 10 of 40 steps executed; reconcile with the broker, no automatic retry'),
                   p.SEND_MAPPED, [111222], gen=6))
t_blk = text_of(rec(bound(status=act.BLOCKED, reason='IDENTITY_CHANGED: position, direction, level_2R or initial volume differs from the bound values'), gen=5))
t_sell = text_of(rec(pending(direction=-1, level=4290.25), p.SEND_MAPPED, [9], gen=2))
row('IDLE_NOT_BOUND', t_idle0, U, 'IDLE', new_req=1, canon=1, gen=1)
row('IDLE_BOUND', t_idle1, U, 'IDLE', new_req=1, canon=1, gen=2)
row('PENDING_WITH_ORDER_MAP', t_pend, R, 'REQUEST_PENDING', recon=1, canon=1, nord=1, gen=4)
row('PENDING_SELL_WITH_ORDER_MAP', t_sell, R, 'REQUEST_PENDING', recon=1, canon=1, nord=1, gen=2)
row('DONE_KEEPS_ONE_CONFIRMATION', t_done, R, 'DONE', recon=1, canon=1, conf=1, executed=40, nord=2, gen=7)
row('NEEDS_RECONCILIATION_PARTIAL_KEEPS_EXECUTED_STEPS', t_nr, R, 'NEEDS_RECONCILIATION', recon=1, canon=1, executed=10, nord=1, gen=6)
row('BLOCKED_STAYS_BLOCKED', t_blk, B, 'BLOCKED', canon=1, gen=5)
# ---- the uncertain send: intent persisted, no order map
row('PENDING_SEND_INTENT_WITHOUT_MAP_IS_RECOVERY', t_pend_intent, X, 'NEEDS_RECONCILIATION', recon=1, reason='RECOVERY_REQUIRED: SEND_UNCERTAIN', gen=4)
t_nr_intent = text_of(rec(pending(status=act.NEEDS_RECONCILIATION, reason='TIMEOUT: request X2R80-987654 not confirmed; reconcile with the broker, no automatic retry'), p.SEND_INTENT, gen=5))
row('RECONCILIATION_WITHOUT_MAP_IS_RECOVERY', t_nr_intent, X, 'NEEDS_RECONCILIATION', recon=1, reason='RECOVERY_REQUIRED: SEND_UNCERTAIN', gen=5)
t_done_intent = text_of(rec(pending(status=act.DONE, executed_steps=40, confirmations=1), p.SEND_INTENT, gen=6))
row('DONE_WITHOUT_MAP_IS_STILL_RESTORED_FOR_RECONCILIATION', t_done_intent, R, 'DONE', recon=1, canon=1, conf=1, executed=40, gen=6)
# ---- absent / unusable files
row('FILE_MISSING', '', X, 'BLOCKED', reason='MISSING', kind='missing')
row('LEFTOVER_TMP_FILE', t_idle1, X, 'BLOCKED', reason='LEFTOVER_TMP', kind='tmp')
row('EMPTY_FILE', '', X, 'BLOCKED', reason='EMPTY')
row('TRUNCATED_HALF', t_pend[:len(t_pend) // 2], X, 'BLOCKED', reason='TRUNCATED')
row('TRUNCATED_BEFORE_CRC', t_pend[:t_pend.index('CRC=')], X, 'BLOCKED', reason='TRUNCATED')
row('TRUNCATED_LAST_BYTE', t_pend[:-1], X, 'BLOCKED', reason='TRUNCATED')
row('TRUNCATED_INSIDE_CRC', t_pend[:-4] + '\n', X, 'BLOCKED', reason='BAD_TRAILER')
row('ONE_BYTE_FLIPPED', t_pend.replace('LEVEL=4310.500000000000', 'LEVEL=4311.500000000000', 1), X, 'BLOCKED', reason='CRC_MISMATCH')
row('STATUS_EDITED_WITHOUT_CRC', t_pend.replace('STATUS=1', 'STATUS=2', 1), X, 'BLOCKED', reason='CRC_MISMATCH')
row('TRAILING_GARBAGE', t_pend + 'X', X, 'BLOCKED', reason='TRUNCATED')
row('TWO_RECORDS_CONCATENATED', t_pend + t_pend, X, 'BLOCKED', reason='TRUNCATED')
row('GARBAGE_TEXT', 'not a state file\n', X, 'BLOCKED', reason='TRUNCATED')
row('WRONG_VERSION_WITH_VALID_CRC', reseal(t_pend, 'VERSION=3', 'VERSION=4'), X, 'BLOCKED', reason='UNSUPPORTED_VERSION')
# a genuine version 1 record: the same text without the PLAN block, version 1, valid CRC. It has no complete plan and is NEVER migrated.
_b1 = '\n'.join(l for l in t_pend[:t_pend.index('CRC=')].split('\n') if not l.startswith('PLAN_')).replace('VERSION=3', 'VERSION=1', 1)
row('OLD_VERSION_1_RECORD_WITHOUT_A_PLAN_IS_NOT_MIGRATED', _b1 + 'CRC=%08X\n' % p.crc32(_b1), X, 'BLOCKED', reason='UNSUPPORTED_VERSION: 1')
t_reg = text_of(rec(bound(), gen=1, plan=True))
t_pend_plan = text_of(rec(pending(), p.SEND_MAPPED, [111222], gen=4, plan=True))
row('REGISTERED_IDLE_WITH_THE_AUTHORISED_PLAN', t_reg, U, 'IDLE', new_req=1, canon=1, gen=1, plan=1)
row('PENDING_KEEPS_THE_AUTHORISED_PLAN', t_pend_plan, R, 'REQUEST_PENDING', recon=1, canon=1, nord=1, gen=4, plan=1)
row('PLAN_TP_ZERO_WITH_VALID_CRC', reseal(t_reg, 'PLAN_TP=4320.500000000000', 'PLAN_TP=0.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('PLAN_MAX_BELOW_MIN_WITH_VALID_CRC', reseal(t_reg, 'PLAN_VOL_MAX=100.000000000000', 'PLAN_VOL_MAX=0.001000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('PLAN_VALUES_WITHOUT_PLAN_SET', reseal(t_idle1, 'PLAN_TP=0.000000000000', 'PLAN_TP=1.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN: values without plan_set')
row('PLAN_SET_ON_AN_UNBOUND_STATE', reseal(t_idle0, 'PLAN_SET=0\nPLAN_TP=0.000000000000\nPLAN_VOL_MIN=0.000000000000\nPLAN_VOL_STEP=0.000000000000\nPLAN_VOL_MAX=0.000000000000\nPLAN_RPOL=0',
                                            'PLAN_SET=1\nPLAN_TP=1.000000000000\nPLAN_VOL_MIN=0.010000000000\nPLAN_VOL_STEP=0.010000000000\nPLAN_VOL_MAX=1.000000000000\nPLAN_RPOL=1'),
    X, 'BLOCKED', reason='INVALID_PLAN: a plan needs a bound state')
row('PLAN_STEP_DIFFERS_FROM_THE_REQUEST_STEP', reseal(t_pend_plan, 'PLAN_VOL_STEP=0.010000000000', 'PLAN_VOL_STEP=0.020000000000'), X, 'BLOCKED', reason='INVALID_PLAN: the request step differs')
# ---- VERSION 3 (Part 14): the declared R basis. Version 2 records (no PLAN_RPOL / E / S) are rejected for the configured file only, never migrated.
t_geom = text_of(rec(bound(), gen=1, plan='geom'))
t_geom_sell = text_of(rec(bound(direction=-1, level=4290.5), gen=1, plan='sell'))
t_geom_pend = text_of(rec(pending(), p.SEND_MAPPED, [111222], gen=4, plan='geom'))
row('REGISTERED_IDLE_WITH_THE_R_GEOM_BASIS', t_geom, U, 'IDLE', new_req=1, canon=1, gen=1, plan=2)
row('REGISTERED_SELL_WITH_THE_R_GEOM_BASIS', t_geom_sell, U, 'IDLE', new_req=1, canon=1, gen=1, plan=2)
row('PENDING_KEEPS_THE_R_GEOM_BASIS', t_geom_pend, R, 'REQUEST_PENDING', recon=1, canon=1, nord=1, gen=4, plan=2)
_v2 = t_reg[:t_reg.index('CRC=')]
_v2 = '\n'.join(l for l in _v2.split('\n') if not l.startswith(('PLAN_RPOL', 'PLAN_E_', 'PLAN_S_'))).replace('VERSION=3', 'VERSION=2', 1)
row('OLD_VERSION_2_RECORD_WITHOUT_THE_BASIS_IS_NOT_MIGRATED', _v2 + 'CRC=%08X\n' % p.crc32(_v2), X, 'BLOCKED', reason='UNSUPPORTED_VERSION: 2')
row('R_GEOM_E_SRC_ZERO', reseal(t_geom, 'PLAN_E_SRC=4300.000000000000', 'PLAN_E_SRC=0.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('R_GEOM_S_SRC_ZERO', reseal(t_geom, 'PLAN_S_SRC=4295.000000000000', 'PLAN_S_SRC=0.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('R_GEOM_E_OUT_ZERO', reseal(t_geom, 'PLAN_E_OUT=4300.000000000000', 'PLAN_E_OUT=0.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('R_GEOM_S_OUT_ZERO', reseal(t_geom, 'PLAN_S_OUT=4295.000000000000', 'PLAN_S_OUT=0.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('R_GEOM_BUY_STOP_ABOVE_ENTRY', reseal(t_geom, 'PLAN_S_OUT=4295.000000000000', 'PLAN_S_OUT=4305.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('R_GEOM_SELL_STOP_BELOW_ENTRY', reseal(t_geom_sell, 'PLAN_S_OUT=4305.000000000000', 'PLAN_S_OUT=4295.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('R_GEOM_LEVEL_NOT_BEYOND_ENTRY', reseal(t_geom, 'PLAN_E_OUT=4300.000000000000', 'PLAN_E_OUT=4311.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('R_GEOM_NORMALIZED_BASIS_DIFFERS_FROM_THE_SOURCE', reseal(t_geom, 'PLAN_E_OUT=4300.000000000000', 'PLAN_E_OUT=4300.010000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('PLAN_RPOL_UNSET_WITH_A_PLAN', reseal(t_reg, 'PLAN_RPOL=1', 'PLAN_RPOL=0'), X, 'BLOCKED', reason='INVALID_PLAN')
row('PLAN_RPOL_UNKNOWN_VALUE', reseal(t_reg, 'PLAN_RPOL=1', 'PLAN_RPOL=3'), X, 'BLOCKED', reason='BAD_ENUM')
row('TYPED_PLAN_CARRIES_A_BASIS', reseal(t_reg, 'PLAN_E_SRC=0.000000000000', 'PLAN_E_SRC=4300.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('BASIS_WITHOUT_PLAN_SET', reseal(t_idle1, 'PLAN_S_OUT=0.000000000000', 'PLAN_S_OUT=1.000000000000'), X, 'BLOCKED', reason='INVALID_PLAN')
row('RPOL_WITHOUT_PLAN_SET', reseal(t_idle1, 'PLAN_RPOL=0', 'PLAN_RPOL=2'), X, 'BLOCKED', reason='INVALID_PLAN')
row('WRONG_HEADER_WITH_VALID_CRC', reseal(t_pend, 'VELO_EXIT_STATE', 'VELO_OTHER_STATE'), X, 'BLOCKED', reason='BAD_HEADER')
row('FIELDS_OUT_OF_ORDER_WITH_VALID_CRC', reseal(t_pend, 'GEN=4\nSERVER=MetaQuotes-Demo', 'SERVER=MetaQuotes-Demo\nGEN=4'), X, 'BLOCKED', reason='BAD_FIELD_ORDER')
row('LEADING_ZERO_NUMBER_WITH_VALID_CRC', reseal(t_pend, 'GEN=4', 'GEN=04'), X, 'BLOCKED', reason='BAD_NUMBER')
row('SHORT_DECIMAL_WITH_VALID_CRC', reseal(t_pend, 'LEVEL=4310.500000000000', 'LEVEL=4310.5'), X, 'BLOCKED', reason='BAD_NUMBER')
row('EXTRA_ORDER_TICKET_LINE_WITH_VALID_CRC', reseal(t_pend, 'MAP_ORDER_0=111222\n', 'MAP_ORDER_0=111222\nMAP_ORDER_1=5\n'), X, 'BLOCKED', reason='BAD_LENGTH')
# ---- another identity
row('OTHER_SERVER', t_pend, X, 'BLOCKED', reason='IDENTITY_MISMATCH', ident=p.Identity('Other-Server', 5001234, 'XAUUSD.r', 987654))
row('OTHER_LOGIN', t_pend, X, 'BLOCKED', reason='IDENTITY_MISMATCH', ident=p.Identity('MetaQuotes-Demo', 5001235, 'XAUUSD.r', 987654))
row('OTHER_SYMBOL', t_pend, X, 'BLOCKED', reason='IDENTITY_MISMATCH', ident=p.Identity('MetaQuotes-Demo', 5001234, 'XAUUSD', 987654))
row('OTHER_POSITION', t_pend, X, 'BLOCKED', reason='IDENTITY_MISMATCH', ident=p.Identity('MetaQuotes-Demo', 5001234, 'XAUUSD.r', 987655))
# ---- valid CRC but an impossible combination (reaches the semantic validation)
row('DONE_WITHOUT_CONFIRMATION', reseal(t_done, 'CONFIRMATIONS=1', 'CONFIRMATIONS=0'), X, 'BLOCKED', reason='INVALID_STATE: DONE without exactly one confirmation')
row('DONE_WITH_TWO_CONFIRMATIONS', reseal(t_done, 'CONFIRMATIONS=1', 'CONFIRMATIONS=2'), X, 'BLOCKED', reason='INVALID_STATE: executed steps or confirmations')
row('PENDING_WITH_A_CONFIRMATION', reseal(t_pend, 'CONFIRMATIONS=0', 'CONFIRMATIONS=1'), X, 'BLOCKED', reason='INVALID_STATE: PENDING with executions or a confirmation')
row('PENDING_WITHOUT_SEND_INTENT', reseal(t_pend, 'SEND_PHASE=2\nMAP_COMPLETE=0\n' + PZ + 'MAP_N=1\nMAP_ORDER_0=111222\n', 'SEND_PHASE=0\nMAP_COMPLETE=0\n' + PZ + 'MAP_N=0\n'), X, 'BLOCKED',
    reason='INVALID_STATE: request without a persisted send intent')
row('MAPPED_PHASE_WITHOUT_ORDER', reseal(t_pend, 'SEND_PHASE=2\nMAP_COMPLETE=0\n' + PZ + 'MAP_N=1\nMAP_ORDER_0=111222\n', 'SEND_PHASE=2\nMAP_COMPLETE=0\n' + PZ + 'MAP_N=0\n'), X, 'BLOCKED',
    reason='INVALID_MAP: send phase MAPPED without an order ticket')
row('DUPLICATE_ORDER_TICKETS', reseal(t_done, 'MAP_ORDER_1=111223', 'MAP_ORDER_1=111222'), X, 'BLOCKED', reason='INVALID_MAP')
row('REQUEST_ID_OF_ANOTHER_POSITION', reseal(t_pend, 'REQUEST_ID=X2R80-987654', 'REQUEST_ID=X2R80-987655'), X, 'BLOCKED', reason='INVALID_STATE: request id or 80% steps do not match the plan')
row('REQUEST_STEPS_NOT_80_PERCENT', reseal(t_pend, 'REQUEST_STEPS=40', 'REQUEST_STEPS=45'), X, 'BLOCKED', reason='INVALID_STATE: request id or 80% steps do not match the plan')
row('CLOSE_VOLUME_NOT_ON_THE_PLAN', reseal(t_pend, 'CLOSE_VOLUME=0.400000000000', 'CLOSE_VOLUME=0.450000000000'), X, 'BLOCKED', reason='INVALID_STATE: volumes do not match the steps')
row('IDLE_WITH_A_SEND_PHASE', reseal(t_idle1, 'SEND_PHASE=0', 'SEND_PHASE=1'), X, 'BLOCKED', reason='INVALID_STATE: IDLE with request data or a send phase')
row('BOUND_STATE_OF_ANOTHER_POSITION', reseal(t_idle1, 'STATE_POSITION=987654', 'STATE_POSITION=987655'), X, 'BLOCKED', reason='INVALID_STATE: bound state does not match')
BLK_REASON = 'IDENTITY_CHANGED: position, direction, level_2R or initial volume differs from the bound values'
row('BLOCKED_WITHOUT_A_REASON', reseal(t_blk, 'REASON=' + p.esc(BLK_REASON) + '\n', 'REASON=\n'), X, 'BLOCKED', reason='INVALID_STATE: BLOCKED without a reason')
row('STATUS_OUT_OF_RANGE', reseal(t_pend, 'STATUS=1', 'STATUS=9'), X, 'BLOCKED', reason='BAD_ENUM')


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t011_persist_fixtures.py emit_mql)', '#define NROWS %d' % len(ROWS)]

    def q(v):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    arr('string', 'R_NAME', [q(r['name']) for r in ROWS])
    arr('string', 'R_TEXT', [q(r['text']) for r in ROWS])
    arr('int', 'R_KIND', [str({'text': 0, 'missing': 1, 'tmp': 2}[r['kind']]) for r in ROWS])
    arr('string', 'R_SERVER', [q(r['ident'].server) for r in ROWS])
    arr('long', 'R_LOGIN', [str(r['ident'].login) for r in ROWS])
    arr('string', 'R_SYMBOL', [q(r['ident'].symbol) for r in ROWS])
    arr('long', 'R_POS', [str(r['ident'].position_id) for r in ROWS])
    arr('int', 'X_VERDICT', [str({U: 0, R: 1, B: 2, X: 3}[r['verdict']]) for r in ROWS])
    arr('int', 'X_STATUS', [str(p.STATUSES.index(r['status'])) for r in ROWS])
    arr('int', 'X_NEWREQ', [str(r['new_req']) for r in ROWS])
    arr('int', 'X_RECON', [str(r['recon']) for r in ROWS])
    arr('string', 'X_REASON', [q(r['reason']) for r in ROWS])
    arr('int', 'X_CANON', [str(r['canon']) for r in ROWS])
    arr('int', 'X_CONF', [str(r['conf']) for r in ROWS])
    arr('long', 'X_EXEC', [str(r['executed']) for r in ROWS])
    arr('int', 'X_NORD', [str(r['nord']) for r in ROWS])
    arr('int', 'X_GEN', [str(r['gen']) for r in ROWS])
    arr('int', 'X_PLAN', [str(r['plan']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)
