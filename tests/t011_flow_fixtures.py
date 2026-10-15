"""T011 restart-flow scenarios: a stored record (written by the persistence codec from a state built by the real activation) + raw terminal data (hand-written, as
in the adapter fixtures: BUY level 2000.0, 0.5 lot, step 0.01, request 0.4 lot = 40 steps on position IDENTIFIER 7, order map [501]) -> the flow. Expected finals,
flags, decisions and the state ON DISK after the flow are hand-written. emit_mql() produces the flat data block of src/tests/T011_FlowTest.mq5 (equality is tested)."""
import t011_activation_reference as act
import t011_adapter_reference as ad
import t011_persist_reference as p

IDENT = p.Identity('MetaQuotes-Demo', 5001234, 'XAUUSD', 7)
RID = 'X2R80-7'
ROWS = []
GEN = 4


def IN_B():
    return ad.RawDeal(100, 400, 7, ad.ENTRY_IN, ad.DEAL_BUY, 0.5)


def OUT(ticket, order, vol, sell=True):
    return ad.RawDeal(ticket, order, 7, ad.ENTRY_OUT, ad.DEAL_SELL if sell else ad.DEAL_BUY, vol)


def raw(deals, orders, **kw):
    r = ad.Raw(deals=list(deals), orders=list(orders))
    for k, v in kw.items():
        setattr(r, k, v)
    return r


FILLED = lambda vi, vc: ad.RawOrder(501, ad.WHERE_HISTORY, ad.ORD_FILLED, vi, vc, 7)
PROFILES = [
    ('FULL', raw([IN_B(), OUT(1001, 501, 0.4)], [FILLED(0.4, 0.0)], pos_volume=0.1)),
    ('DUPLICATE_DEAL', raw([IN_B(), OUT(1001, 501, 0.4), OUT(1001, 501, 0.4)], [FILLED(0.4, 0.0)], pos_volume=0.1)),
    ('NOT_YET_IN_HISTORY', raw([IN_B()], [ad.RawOrder(501, ad.WHERE_ACTIVE, ad.ORD_PLACED, 0.4, 0.4, 7)], pos_volume=0.5)),
    ('INCOMPLETE_HISTORY', raw([OUT(1001, 501, 0.4)], [FILLED(0.4, 0.0)], pos_volume=0.1)),
    ('PARTIAL_FILL_CANCELED', raw([IN_B(), OUT(1001, 501, 0.1)], [ad.RawOrder(501, ad.WHERE_HISTORY, ad.ORD_CANCELED, 0.4, 0.3, 7)], pos_volume=0.4)),
    ('API_ERROR', raw([], [], api_ok=False)),
    ('EXIT_DEAL_OF_THE_SAME_SIDE', raw([IN_B(), OUT(1001, 501, 0.4, sell=False)], [FILLED(0.4, 0.0)], pos_volume=0.1)),
    ('NOTHING_EXECUTED_CANCELED', raw([IN_B()], [ad.RawOrder(501, ad.WHERE_HISTORY, ad.ORD_CANCELED, 0.4, 0.4, 7)], pos_volume=0.5)),
]
PI = {name: i for i, (name, _) in enumerate(PROFILES)}


def below():
    s = act.State()
    act.on_quote(s, 7, act.BUY, 2000.0, 1999.0, 1999.3, 0.5, 0.5, 0.01, 0.01, 100.0)
    return s


def pending():
    s = act.State()
    act.on_quote(s, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
    return s


def needs_rec():
    s = pending()
    act.on_report(s, RID, act.TIMEOUT, 0.0, 0.01)
    return s


def done():
    s = pending()
    act.on_report(s, RID, act.FULL, 0.4, 0.01)
    return s


def blocked():
    s = pending()
    act.on_report(s, 'X2R80-8', act.FULL, 0.4, 0.01)
    return s


# start kinds
IDLE, PEND_MAP, PEND_INTENT, NR_MAP, DONE_MAP, BLOCKED_MAP, MISSING, CORRUPT, OTHER_IDENT, PEND_MAP_777 = range(10)


def start_record(kind):
    if kind == IDLE:
        return p.Record(1, IDENT, below())
    if kind == PEND_MAP:
        return p.Record(GEN, IDENT, pending(), p.SEND_MAPPED, True, [501])
    if kind == PEND_MAP_777:
        return p.Record(GEN, IDENT, pending(), p.SEND_MAPPED, True, [777])
    if kind == PEND_INTENT:
        return p.Record(GEN, IDENT, pending(), p.SEND_INTENT)
    if kind == NR_MAP:
        return p.Record(GEN, IDENT, needs_rec(), p.SEND_MAPPED, True, [501])
    if kind == DONE_MAP:
        return p.Record(GEN, IDENT, done(), p.SEND_MAPPED, True, [501])
    if kind == BLOCKED_MAP:
        return p.Record(GEN, IDENT, blocked(), p.SEND_MAPPED, True, [501])
    return None


def row(name, start, a, b=None, fail=0, final='', snap=0, recon=0, save_needed=0, saved=0, gen=0, disk='', conf=0, decision='', adapter='', reason=''):
    ROWS.append(dict(name=name, start=start, a=PI[a] if a else -1, b=PI[b or a] if a else -1, fail=int(fail), final=final, snap=snap, recon=recon, save_needed=save_needed,
                     saved=saved, gen=gen, disk=disk, conf=conf, decision=decision, adapter=adapter, reason=reason))


F = 'FULL'
# ---- a stored request with its map + complete evidence -> DONE through the existing reconciliation, saved with generation + 1
row('PENDING_WITH_MAP_FULL_EVIDENCE_IS_DONE_AND_SAVED', PEND_MAP, F, final='DONE', snap=1, recon=1, save_needed=1, saved=1, gen=GEN + 1, disk='DONE', conf=1, decision='CONFIRMED', adapter='READY')
row('NEEDS_RECONCILIATION_WITH_MAP_FULL_EVIDENCE_IS_DONE', NR_MAP, F, final='DONE', snap=1, recon=1, save_needed=1, saved=1, gen=GEN + 1, disk='DONE', conf=1, decision='CONFIRMED', adapter='READY')
row('DUPLICATE_DEAL_COUNTS_ONCE', PEND_MAP, 'DUPLICATE_DEAL', final='DONE', snap=1, recon=1, save_needed=1, saved=1, gen=GEN + 1, disk='DONE', conf=1, decision='CONFIRMED', adapter='READY')
row('DONE_STORED_AND_CONFIRMED_AGAIN_ADDS_NOTHING', DONE_MAP, F, final='DONE', snap=1, recon=1, save_needed=0, saved=0, gen=GEN, disk='DONE', conf=1, decision='CONFIRMED', adapter='READY')
row('DONE_STORED_BUT_NO_EVIDENCE_IS_NOT_KEPT_AS_PROOF', DONE_MAP, 'NOT_YET_IN_HISTORY', final='STILL_OPEN', snap=1, recon=1, save_needed=1, saved=1, gen=GEN + 1, disk='NEEDS_RECONCILIATION', conf=1,
    decision='UNKNOWN', adapter='READY')
# ---- evidence not (yet) conclusive: nothing is promoted, nothing is written
row('LATE_FILL_NOT_YET_IN_HISTORY_STAYS_OPEN', PEND_MAP, 'NOT_YET_IN_HISTORY', final='STILL_OPEN', snap=1, recon=1, save_needed=0, saved=0, gen=GEN, disk='REQUEST_PENDING', conf=0,
    decision='UNKNOWN', adapter='READY')
row('INCOMPLETE_HISTORY_STAYS_OPEN', PEND_MAP, 'INCOMPLETE_HISTORY', final='STILL_OPEN', snap=1, recon=1, save_needed=0, saved=0, gen=GEN, disk='REQUEST_PENDING', conf=0, decision='UNKNOWN',
    adapter='READY')
row('PARTIAL_FILL_GOES_TO_RECONCILIATION_AND_IS_SAVED', PEND_MAP, 'PARTIAL_FILL_CANCELED', final='STILL_OPEN', snap=1, recon=1, save_needed=1, saved=1, gen=GEN + 1, disk='NEEDS_RECONCILIATION',
    conf=0, decision='PARTIAL', adapter='READY')
row('NOTHING_EXECUTED_NEVER_BECOMES_A_NEW_REQUEST', NR_MAP, 'NOTHING_EXECUTED_CANCELED', final='STILL_OPEN', snap=1, recon=1, save_needed=0, saved=0, gen=GEN, disk='NEEDS_RECONCILIATION', conf=0,
    decision='NOT_EXECUTED', adapter='READY')
row('THE_STORED_ORDER_MAP_IS_USED_NOT_A_GUESS', PEND_MAP_777, F, final='STILL_OPEN', snap=1, recon=1, save_needed=0, saved=0, gen=GEN, disk='REQUEST_PENDING', conf=0, decision='UNKNOWN',
    adapter='READY')
# ---- snapshot verdicts that must not be bypassed
row('API_ERROR_SNAPSHOT_UNKNOWN_SKIPS_THE_RECONCILIATION', PEND_MAP, 'API_ERROR', final='STILL_OPEN', snap=1, recon=0, gen=GEN, disk='REQUEST_PENDING', adapter='UNKNOWN', reason='SNAPSHOT_UNKNOWN')
row('UNSTABLE_READ_SNAPSHOT_UNKNOWN', PEND_MAP, F, 'NOT_YET_IN_HISTORY', final='STILL_OPEN', snap=1, recon=0, gen=GEN, disk='REQUEST_PENDING', adapter='UNKNOWN', reason='SNAPSHOT_UNKNOWN: READ_UNSTABLE')
row('ADAPTER_BLOCK_SKIPS_THE_RECONCILIATION_AND_THE_SAVE', PEND_MAP, 'EXIT_DEAL_OF_THE_SAME_SIDE', final='BLOCKED', snap=1, recon=0, gen=GEN, disk='REQUEST_PENDING', adapter='BLOCK', reason='SNAPSHOT_BLOCK')
# ---- save failure
row('SAVE_FAILURE_IS_RECOVERY_REQUIRED_AND_NOT_EXPOSED_AS_SAVED', PEND_MAP, F, fail=1, final='RECOVERY_REQUIRED', snap=1, recon=1, save_needed=1, saved=0, gen=GEN, disk='REQUEST_PENDING', conf=0,
    decision='CONFIRMED', adapter='READY', reason='SAVE_FAILED')
# ---- gates before any read
row('MISSING_FILE_BLOCKS_BEFORE_ANY_READ', MISSING, F, final='RECOVERY_REQUIRED', reason='LOAD_UNUSABLE: MISSING')
row('DAMAGED_FILE_BLOCKS_BEFORE_ANY_READ', CORRUPT, F, final='RECOVERY_REQUIRED', reason='LOAD_UNUSABLE: CRC_MISMATCH')
row('OTHER_IDENTITY_BLOCKS_BEFORE_ANY_READ', OTHER_IDENT, F, final='RECOVERY_REQUIRED', gen=0, disk='REQUEST_PENDING', reason='LOAD_UNUSABLE: IDENTITY_MISMATCH')
row('MISSING_ORDER_MAP_AFTER_AN_UNCERTAIN_SEND_BLOCKS_BEFORE_THE_SNAPSHOT', PEND_INTENT, F, final='RECOVERY_REQUIRED', gen=GEN, disk='REQUEST_PENDING', reason='NO_MAP')
row('STORED_BLOCKED_IS_NOT_READ_OR_WRITTEN', BLOCKED_MAP, F, final='BLOCKED', gen=GEN, disk='BLOCKED')
row('STORED_IDLE_IS_NOTHING_TO_RECONCILE_AND_NEVER_A_REQUEST', IDLE, F, final='NOTHING_TO_RECONCILE', gen=1, disk='IDLE')


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t011_flow_fixtures.py emit_mql)']
    NP, MD, MO = len(PROFILES), 4, 1
    out.append('#define NROWS %d' % len(ROWS))
    out.append('#define NPROF %d' % NP)
    out.append('#define MAXD %d' % MD)

    def q(v):
        return '"' + v + '"'

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    arr('string', 'P_NAME', [q(n) for n, _ in PROFILES])
    arr('int', 'P_API', [str(int(r.api_ok)) for _, r in PROFILES])
    arr('double', 'P_POSVOL', [repr(float(r.pos_volume)) for _, r in PROFILES])
    arr('int', 'P_ND', [str(len(r.deals)) for _, r in PROFILES])
    pad = lambda lst, n, z: lst + [z] * (n - len(lst))
    for field, nm, typ, conv in (('ticket', 'D_TICKET', 'int', str), ('order', 'D_ORDER', 'int', str), ('entry', 'D_ENTRY', 'int', str), ('type', 'D_TYPE', 'int', str),
                                 ('volume', 'D_VOL', 'double', lambda v: repr(float(v)))):
        vals = []
        for _, r in PROFILES:
            ds = [getattr(d, field) for d in r.deals]
            assert len(ds) <= MD
            vals += [conv(v) for v in pad(ds, MD, 0)]
        arr(typ, nm, vals)
    arr('int', 'P_HASORD', [str(len(r.orders)) for _, r in PROFILES])
    for field, nm, typ, conv in (('where', 'O_WHERE', 'int', str), ('state', 'O_STATE', 'int', str), ('vol_initial', 'O_VI', 'double', lambda v: repr(float(v))),
                                 ('vol_current', 'O_VC', 'double', lambda v: repr(float(v)))):
        vals = []
        for _, r in PROFILES:
            os_ = [getattr(o, field) for o in r.orders]
            assert len(os_) <= MO
            vals += [conv(v) for v in pad(os_, MO, 0)]
        arr(typ, nm, vals)
    arr('string', 'R_NAME', [q(r['name']) for r in ROWS])
    for key, nm in (('start', 'R_START'), ('a', 'R_A'), ('b', 'R_B'), ('fail', 'R_FAIL'), ('snap', 'X_SNAP'), ('recon', 'X_RECON'), ('save_needed', 'X_SAVENEED'), ('saved', 'X_SAVED'),
                    ('gen', 'X_GEN'), ('conf', 'X_CONF')):
        arr('int', nm, [str(r[key]) for r in ROWS])
    arr('string', 'X_FINAL', [q(r['final']) for r in ROWS])
    arr('string', 'X_DISK', [q(r['disk']) for r in ROWS])
    arr('string', 'X_DECISION', [q(r['decision']) for r in ROWS])
    arr('string', 'X_ADAPTER', [q(r['adapter']) for r in ROWS])
    arr('string', 'X_REASON', [q(r['reason']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)
