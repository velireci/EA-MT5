"""T011 adapter scenarios (pure core): the state is built by the activation functions, the raw MT5 data is written by hand, and the
expected verdict, completeness, counts, snapshot and the decision of reconcile() on that snapshot are hand-written too. BUY level 2000.0
(SELL 1990.0), initial 0.5 lot, grid 0.01: request 0.4 lot = 40 steps on position IDENTIFIER 7 whose TICKET is 9 (not the same on purpose).
emit_mql() produces the flat data block of src/tests/T011_AdapterTest.mq5 (equality is tested)."""
import t011_activation_reference as act
import t011_adapter_reference as ad
import t011_reconcile_reference as rec

ROWS = []
MAXD, MAXO, MAXM = 20, 4, 4
RID = 'X2R80-7'
IN_B = (100, 400, 7, ad.ENTRY_IN, ad.DEAL_BUY, 0.5)           # opening deal of the BUY position
IN_S = (100, 400, 7, ad.ENTRY_IN, ad.DEAL_SELL, 0.5)
FILLED = lambda t, vi, vc, pos=7: (t, ad.WHERE_HISTORY, ad.ORD_FILLED, vi, vc, pos)
CANCELED = lambda t, vi, vc, pos=7: (t, ad.WHERE_HISTORY, ad.ORD_CANCELED, vi, vc, pos)


def OUT(ticket, order, vol, sell_side=True):
    return (ticket, order, 7, ad.ENTRY_OUT, ad.DEAL_SELL if sell_side else ad.DEAL_BUY, vol)


def setup(name):
    st = act.State()
    if name == 'IDLE':
        act.on_quote(st, 7, act.BUY, 2000.0, 1999.0, 1999.3, 0.5, 0.5, 0.01, 0.01, 100.0)
        return st
    if name.endswith('SELL'):
        act.on_quote(st, 7, act.SELL, 1990.0, 1989.0, 1989.4, 0.5, 0.5, 0.01, 0.01, 100.0)
    else:
        act.on_quote(st, 7, act.BUY, 2000.0, 2000.0, 2000.3, 0.5, 0.5, 0.01, 0.01, 100.0)
    if name.startswith('REC'):
        act.on_report(st, RID, act.TIMEOUT, 0.0, 0.01)
    if name.startswith('DONE'):
        act.on_report(st, RID, act.FULL, 0.4, 0.01)
    if name == 'BLOCKED':
        act.on_report(st, 'X2R80-8', act.FULL, 0.4, 0.01)
    return st


def row(name, setup_name='PEND', deals=(), orders=(), raw=None, mp=None, stable=True, verdict='READY', why='', complete=0, linked=0,
        dup=0, exe=0, exo=0, execs='', found=1, vcur=0.1, vstep=0.01, decision='', state=''):
    r = dict(scn=name, setup=setup_name, stable=int(stable), deals=list(deals), orders=list(orders), verdict=verdict, why=why, complete=complete,
             linked=linked, dup=dup, exe=exe, exo=exo, execs=execs, found=found, vcur=vcur, vstep=vstep, decision=decision, state=state)
    m = dict(request_id=RID, position_id=7, symbol='XAUUSD', orders=[501], orders_complete=True)
    m.update(mp or {})
    w = dict(api_ok=1, symbol_ok=1, vol_step=0.01, vol_min=0.01, vol_max=100.0, margin_ok=1, margin_mode=ad.MARGIN_HEDGING, n_pos=1, pos_ticket=9,
             pos_type=ad.POS_BUY, pos_volume=0.1, pos_symbol='XAUUSD', hist_ok=1, truncated=0)
    w.update(raw or {})
    r['map'], r['raw'] = m, w
    ROWS.append(r)


SELLRAW = dict(pos_type=ad.POS_SELL)
# ---- full fills, complete evidence -> READY complete -> reconcile CONFIRMED
row('BUY_FULL_ONE_DEAL_COMPLETE', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], complete=1, linked=1, exe=1, execs='1001', decision='CONFIRMED', state='DONE')
row('SELL_FULL_ONE_DEAL_COMPLETE', 'PEND_SELL', deals=[IN_S, OUT(1001, 501, 0.4, False)], orders=[FILLED(501, 0.4, 0.0)], raw=SELLRAW, complete=1, linked=1, exe=1, execs='1001', decision='CONFIRMED', state='DONE')
row('BUY_ONE_ORDER_TWO_DEALS', deals=[IN_B, OUT(1001, 501, 0.25), OUT(1002, 501, 0.15)], orders=[FILLED(501, 0.4, 0.0)], complete=1, linked=2, exe=1, execs='1001,1002', decision='CONFIRMED', state='DONE')
row('BUY_TWO_ORDERS', mp=dict(orders=[501, 502]), deals=[IN_B, OUT(1001, 501, 0.3), OUT(1002, 502, 0.1)], orders=[FILLED(501, 0.3, 0.0), FILLED(502, 0.1, 0.0)],
    complete=1, linked=2, exe=1, execs='1001,1002', decision='CONFIRMED', state='DONE')
row('SELL_TWO_ORDERS', 'PEND_SELL', mp=dict(orders=[501, 502]), deals=[IN_S, OUT(1001, 501, 0.3, False), OUT(1002, 502, 0.1, False)],
    orders=[FILLED(501, 0.3, 0.0), FILLED(502, 0.1, 0.0)], raw=SELLRAW, complete=1, linked=2, exe=1, execs='1001,1002', decision='CONFIRMED', state='DONE')
# ---- deduplication by deal ticket
row('BUY_DUPLICATE_DEAL_TICKET', deals=[IN_B, OUT(1001, 501, 0.4), OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], complete=1, linked=1, dup=1, exe=1, execs='1001', decision='CONFIRMED', state='DONE')
row('SELL_THREE_COPIES_OF_A_DEAL', 'PEND_SELL', deals=[IN_S, OUT(1001, 501, 0.4, False), OUT(1001, 501, 0.4, False), OUT(1001, 501, 0.4, False)], orders=[FILLED(501, 0.4, 0.0)],
    raw=SELLRAW, complete=1, linked=1, dup=2, exe=1, execs='1001', decision='CONFIRMED', state='DONE')
row('BUY_SAME_TICKET_DIFFERENT_CONTENT', deals=[IN_B, OUT(1001, 501, 0.4), OUT(1001, 501, 0.3)], orders=[FILLED(501, 0.4, 0.0)], verdict='UNKNOWN', why='READ_INCONSISTENT')
# ---- exclusions: entries, manual trades, other requests
row('BUY_ENTRY_INOUT_OUTBY_EXCLUDED', deals=[IN_B, (101, 401, 7, ad.ENTRY_IN, ad.DEAL_BUY, 0.0 + 0.01), (102, 402, 7, ad.ENTRY_INOUT, ad.DEAL_SELL, 0.01), (103, 403, 7, ad.ENTRY_OUT_BY, ad.DEAL_SELL, 0.01), OUT(1001, 501, 0.4)],
    orders=[FILLED(501, 0.4, 0.0)], complete=1, linked=1, exe=4, execs='1001', decision='CONFIRMED', state='DONE')
row('BUY_MANUAL_EXIT_NOT_COUNTED_AND_POSITION_MISMATCH', deals=[IN_B, OUT(1001, 501, 0.4), OUT(1003, 900, 0.05)], orders=[FILLED(501, 0.4, 0.0)],
    raw=dict(pos_volume=0.05), complete=1, linked=1, exe=1, exo=1, execs='1001', vcur=0.05, decision='BLOCK', state='BLOCKED')
row('SELL_OTHER_REQUEST_EXIT_NOT_COUNTED', 'PEND_SELL', deals=[IN_S, OUT(1001, 501, 0.4, False), OUT(1002, 777, 0.05, False)], orders=[FILLED(501, 0.4, 0.0)],
    raw=dict(pos_type=ad.POS_SELL, pos_volume=0.05), complete=1, linked=1, exe=1, exo=1, execs='1001', vcur=0.05, decision='BLOCK', state='BLOCKED')
row('BUY_BALANCE_DEAL_TYPE_IS_NOT_ATTRIBUTED_BY_MAGIC_OR_VOLUME', deals=[IN_B, OUT(1001, 501, 0.4), OUT(1004, 888, 0.4)], orders=[FILLED(501, 0.4, 0.0)],
    raw=dict(pos_volume=0.1), complete=1, linked=1, exe=1, exo=1, execs='1001', decision='CONFIRMED', state='DONE')
# ---- identity map problems
row('NO_MAP_ORDER_TICKETS', mp=dict(orders=[]), deals=[IN_B, OUT(1001, 501, 0.4)], verdict='UNKNOWN', why='NO_ORDER_TICKETS')
row('MAP_OTHER_REQUEST', mp=dict(request_id='X2R80-8'), deals=[IN_B], verdict='BLOCK', why='MAP_REQUEST_MISMATCH')
row('MAP_OTHER_POSITION', mp=dict(position_id=8), deals=[IN_B], verdict='BLOCK', why='MAP_POSITION_MISMATCH')
row('MAP_DUPLICATE_ORDER_TICKETS', mp=dict(orders=[501, 501]), deals=[IN_B], verdict='UNKNOWN', why='MAP_INVALID')
row('DEAL_OF_ANOTHER_POSITION_IN_THE_LIST', deals=[IN_B, (1001, 501, 8, ad.ENTRY_OUT, ad.DEAL_SELL, 0.4)], orders=[FILLED(501, 0.4, 0.0)], verdict='UNKNOWN', why='READ_INCONSISTENT')
row('BUY_EXIT_DEAL_OF_THE_SAME_SIDE', deals=[IN_B, OUT(1001, 501, 0.4, False)], orders=[FILLED(501, 0.4, 0.0)], verdict='BLOCK', why='DEAL_DIRECTION_MISMATCH')
row('ORDER_EXECUTED_ON_ANOTHER_POSITION', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0, pos=8)], verdict='BLOCK', why='ORDER_POSITION_MISMATCH')
# ---- completeness is not claimed without proof (READY with complete = 0)
row('EXECUTOR_DOES_NOT_ASSERT_ORDER_LIST_COMPLETE', mp=dict(orders_complete=False), deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], complete=0, linked=1, exe=1,
    execs='1001', decision='UNKNOWN', state='REQUEST_PENDING')
row('ORDER_STILL_ACTIVE', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[(501, ad.WHERE_ACTIVE, ad.ORD_PARTIAL, 0.4, 0.0, 7)], complete=0, linked=1, exe=1, execs='1001', decision='UNKNOWN', state='REQUEST_PENDING')
row('ORDER_NOT_FOUND_ANYWHERE', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[(501, ad.WHERE_NONE, 0, 0.0, 0.0, 0)], complete=0, linked=1, exe=1, execs='1001', decision='UNKNOWN', state='REQUEST_PENDING')
row('ORDER_IN_HISTORY_BUT_NOT_FINAL', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[(501, ad.WHERE_HISTORY, ad.ORD_PLACED, 0.4, 0.0, 7)], complete=0, linked=1, exe=1, execs='1001', decision='UNKNOWN', state='REQUEST_PENDING')
row('ORDER_EXECUTED_MORE_THAN_ITS_DEALS', deals=[IN_B, OUT(1001, 501, 0.3)], orders=[FILLED(501, 0.4, 0.0)], raw=dict(pos_volume=0.2), complete=0, linked=1, exe=1, execs='1001', vcur=0.2, decision='PARTIAL', state='NEEDS_RECONCILIATION')
row('OPENING_DEAL_NOT_IN_THE_HISTORY_LIST', deals=[OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], complete=0, linked=1, exe=0, execs='1001', decision='UNKNOWN', state='REQUEST_PENDING')
row('A_MAPPED_ORDER_MISSING_FROM_THE_ORDER_READ', mp=dict(orders=[501, 502]), deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], complete=0, linked=1, exe=1, execs='1001', decision='UNKNOWN', state='REQUEST_PENDING')
# ---- partial fills, nothing executed, a volume drop alone
row('BUY_PARTIAL_FILL_CANCELED_REMAINDER', deals=[IN_B, OUT(1001, 501, 0.1)], orders=[CANCELED(501, 0.4, 0.3)], raw=dict(pos_volume=0.4), complete=1, linked=1, exe=1, execs='1001', vcur=0.4, decision='PARTIAL', state='NEEDS_RECONCILIATION')
row('SELL_PARTIAL_FILL_CANCELED_REMAINDER', 'PEND_SELL', deals=[IN_S, OUT(1001, 501, 0.2, False)], orders=[CANCELED(501, 0.4, 0.2)], raw=dict(pos_type=ad.POS_SELL, pos_volume=0.3), complete=1,
    linked=1, exe=1, execs='1001', vcur=0.3, decision='PARTIAL', state='NEEDS_RECONCILIATION')
row('BUY_NOTHING_EXECUTED_COMPLETE_EVIDENCE', 'REC_BUY', deals=[IN_B], orders=[CANCELED(501, 0.4, 0.4)], raw=dict(pos_volume=0.5), complete=1, exe=1, vcur=0.5, decision='NOT_EXECUTED', state='NEEDS_RECONCILIATION')
row('BUY_VOLUME_DROP_ALONE_WITH_COMPLETE_EVIDENCE_BLOCKS', 'REC_BUY', deals=[IN_B, OUT(1003, 900, 0.4)], orders=[CANCELED(501, 0.4, 0.4)], complete=1, exe=1, exo=1, decision='BLOCK', state='BLOCKED')
row('BUY_VOLUME_DROP_ALONE_WITHOUT_PROOF_IS_UNKNOWN', 'REC_BUY', mp=dict(orders_complete=False), deals=[IN_B, OUT(1003, 900, 0.4)], orders=[CANCELED(501, 0.4, 0.4)], complete=0, exe=1, exo=1, decision='UNKNOWN', state='NEEDS_RECONCILIATION')
row('BUY_TIMEOUT_THEN_LATE_FILL_THROUGH_THE_ADAPTER', 'REC_BUY', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], complete=1, linked=1, exe=1, execs='1001', decision='CONFIRMED', state='DONE')
row('SELL_TIMEOUT_THEN_LATE_FILL_THROUGH_THE_ADAPTER', 'REC_SELL', deals=[IN_S, OUT(1001, 501, 0.4, False)], orders=[FILLED(501, 0.4, 0.0)], raw=SELLRAW, complete=1, linked=1, exe=1, execs='1001', decision='CONFIRMED', state='DONE')
row('BUY_DONE_STATE_REVERIFIED', 'DONE_BUY', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], complete=1, linked=1, exe=1, execs='1001', decision='CONFIRMED', state='DONE')
row('BUY_DONE_STATE_LOST_WHEN_THE_EVIDENCE_VANISHES', 'DONE_BUY', deals=[IN_B], orders=[CANCELED(501, 0.4, 0.4)], raw=dict(pos_volume=0.1), complete=1, exe=1, decision='BLOCK', state='BLOCKED')
# ---- position states
row('BUY_POSITION_NOT_OPEN_ANYMORE', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], raw=dict(n_pos=0), complete=1, linked=1, exe=1, execs='1001', found=0, vcur=0.0, decision='BLOCK', state='BLOCKED')
row('TWO_OPEN_POSITIONS_WITH_THE_SAME_IDENTIFIER', deals=[IN_B], raw=dict(n_pos=2), verdict='BLOCK', why='AMBIGUOUS_POSITION')
row('POSITION_SYMBOL_MISMATCH', deals=[IN_B], raw=dict(pos_symbol='EURUSD'), verdict='BLOCK', why='SYMBOL_MISMATCH')
row('POSITION_DIRECTION_MISMATCH', deals=[IN_B], raw=dict(pos_type=ad.POS_SELL), verdict='BLOCK', why='DIRECTION_MISMATCH')
row('POSITION_IDENTIFIER_NOT_TICKET', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], raw=dict(pos_ticket=7), complete=1, linked=1, exe=1, execs='1001', decision='CONFIRMED', state='DONE')
# ---- real broker parameters
row('BROKER_STEP_CHANGED_IS_PASSED_ON', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], raw=dict(vol_step=0.001), complete=1, linked=1, exe=1, execs='1001', vstep=0.001, decision='BLOCK', state='BLOCKED')
row('BROKER_STEP_UNREADABLE', deals=[IN_B], raw=dict(vol_step=0.0), verdict='UNKNOWN', why='SYMBOL_PARAMETERS_UNAVAILABLE')
row('SYMBOL_READ_FAILED', deals=[IN_B], raw=dict(symbol_ok=0), verdict='UNKNOWN', why='SYMBOL_PARAMETERS_UNAVAILABLE')
# ---- unreliable reads
row('API_ERROR', raw=dict(api_ok=0), verdict='UNKNOWN', why='API_ERROR')
row('HISTORY_UNAVAILABLE', raw=dict(hist_ok=0), verdict='UNKNOWN', why='HISTORY_UNAVAILABLE')
row('DEAL_LIST_TRUNCATED_BY_THE_READER', deals=[IN_B], raw=dict(truncated=1), verdict='UNKNOWN', why='CAPACITY')
row('TWENTY_DEALS_AND_THE_TRUNCATION_FLAG', deals=[IN_B] + [OUT(2000 + k, 900, 0.01) for k in range(19)], raw=dict(truncated=1), verdict='UNKNOWN', why='CAPACITY')
row('SEVENTEEN_LINKED_EXECUTIONS_EXCEED_A_SNAPSHOT', deals=[IN_B] + [OUT(3000 + k, 501, 0.01) for k in range(17)], orders=[FILLED(501, 0.17, 0.0)], raw=dict(pos_volume=0.33), verdict='UNKNOWN', why='CAPACITY')
row('READ_CHANGED_BETWEEN_TWO_READS', stable=False, deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], verdict='UNKNOWN', why='READ_UNSTABLE')
row('ACCOUNT_MODE_UNREADABLE', deals=[IN_B], raw=dict(margin_ok=0), verdict='UNKNOWN', why='ACCOUNT_MODE_UNAVAILABLE')
row('NETTING_ACCOUNT_BLOCKS', deals=[IN_B], raw=dict(margin_mode=ad.MARGIN_NETTING), verdict='BLOCK', why='UNSUPPORTED_ACCOUNT_MODE')
row('EXCHANGE_ACCOUNT_BLOCKS', deals=[IN_B], raw=dict(margin_mode=ad.MARGIN_EXCHANGE), verdict='BLOCK', why='UNSUPPORTED_ACCOUNT_MODE')
row('UNKNOWN_ACCOUNT_MODE_BLOCKS', deals=[IN_B], raw=dict(margin_mode=7), verdict='BLOCK', why='UNSUPPORTED_ACCOUNT_MODE')
# ---- state gate
row('STATE_IDLE_HAS_NO_REQUEST', 'IDLE', deals=[IN_B], verdict='UNKNOWN', why='NO_REQUEST')
row('STATE_BLOCKED_STAYS_BLOCKED', 'BLOCKED', deals=[IN_B, OUT(1001, 501, 0.4)], orders=[FILLED(501, 0.4, 0.0)], verdict='BLOCK', why='ALREADY_BLOCKED')


def _n(v):
    return repr(float(v))


def emit_mql():
    out = ['// BEGIN GENERATED FIXTURES (tests/t011_adapter_fixtures.py emit_mql)']
    out.append('#define NROWS %d' % len(ROWS))
    out.append('#define FMAXD %d' % MAXD)
    out.append('#define FMAXO %d' % MAXO)
    out.append('#define FMAXM %d' % MAXM)

    def arr(typ, name, vals):
        out.append('%s %s[]={%s};' % (typ, name, ','.join(vals)))

    q = lambda v: '"%s"' % v
    arr('string', 'R_NAME', [q(r['scn']) for r in ROWS])
    arr('string', 'R_SETUP', [q(r['setup']) for r in ROWS])
    arr('int', 'R_STABLE', [str(r['stable']) for r in ROWS])
    arr('string', 'M_REQ', [q(r['map']['request_id']) for r in ROWS])
    arr('long', 'M_POS', [str(r['map']['position_id']) for r in ROWS])
    arr('string', 'M_SYM', [q(r['map']['symbol']) for r in ROWS])
    arr('int', 'M_NORD', [str(len(r['map']['orders'])) for r in ROWS])
    arr('long', 'M_ORD', [str(r['map']['orders'][k]) if k < len(r['map']['orders']) else '0' for r in ROWS for k in range(MAXM)])
    arr('int', 'M_COMPLETE', [str(int(r['map']['orders_complete'])) for r in ROWS])
    for nm, k in (('W_APIOK', 'api_ok'), ('W_SYMOK', 'symbol_ok'), ('W_MARGINOK', 'margin_ok'), ('W_MODE', 'margin_mode'), ('W_NPOS', 'n_pos'),
                  ('W_POSTYPE', 'pos_type'), ('W_HISTOK', 'hist_ok'), ('W_TRUNC', 'truncated')):
        arr('int', nm, [str(r['raw'][k]) for r in ROWS])
    for nm, k in (('W_STEP', 'vol_step'), ('W_MIN', 'vol_min'), ('W_MAX', 'vol_max'), ('W_POSVOL', 'pos_volume')):
        arr('double', nm, [_n(r['raw'][k]) for r in ROWS])
    arr('long', 'W_POSTICKET', [str(r['raw']['pos_ticket']) for r in ROWS])
    arr('string', 'W_POSSYM', [q(r['raw']['pos_symbol']) for r in ROWS])
    arr('int', 'D_N', [str(len(r['deals'])) for r in ROWS])
    pad = (0, 0, 0, 0, 0, 0.0)
    flat = [(r['deals'][k] if k < len(r['deals']) else pad) for r in ROWS for k in range(MAXD)]
    arr('long', 'D_TICKET', [str(d[0]) for d in flat])
    arr('long', 'D_ORDER', [str(d[1]) for d in flat])
    arr('long', 'D_POS', [str(d[2]) for d in flat])
    arr('int', 'D_ENTRY', [str(d[3]) for d in flat])
    arr('int', 'D_TYPE', [str(d[4]) for d in flat])
    arr('double', 'D_VOL', [_n(d[5]) for d in flat])
    arr('int', 'O_N', [str(len(r['orders'])) for r in ROWS])
    pado = (0, 0, 0, 0.0, 0.0, 0)
    fo = [(r['orders'][k] if k < len(r['orders']) else pado) for r in ROWS for k in range(MAXO)]
    arr('long', 'O_TICKET', [str(o[0]) for o in fo])
    arr('int', 'O_WHERE', [str(o[1]) for o in fo])
    arr('int', 'O_STATE', [str(o[2]) for o in fo])
    arr('double', 'O_VINIT', [_n(o[3]) for o in fo])
    arr('double', 'O_VCUR', [_n(o[4]) for o in fo])
    arr('long', 'O_POS', [str(o[5]) for o in fo])
    arr('string', 'X_VERDICT', [q(r['verdict']) for r in ROWS])
    arr('string', 'X_WHY', [q(r['why']) for r in ROWS])
    arr('int', 'X_COMPLETE', [str(r['complete']) for r in ROWS])
    arr('int', 'X_LINKED', [str(r['linked']) for r in ROWS])
    arr('int', 'X_DUP', [str(r['dup']) for r in ROWS])
    arr('int', 'X_EXE', [str(r['exe']) for r in ROWS])
    arr('int', 'X_EXO', [str(r['exo']) for r in ROWS])
    arr('string', 'X_EXECS', [q(r['execs']) for r in ROWS])
    arr('int', 'X_FOUND', [str(r['found']) for r in ROWS])
    arr('double', 'X_VCUR', [_n(r['vcur']) for r in ROWS])
    arr('double', 'X_VSTEP', [_n(r['vstep']) for r in ROWS])
    arr('string', 'X_DECISION', [q(r['decision']) for r in ROWS])
    arr('string', 'X_STATE', [q(r['state']) for r in ROWS])
    out.append('// END GENERATED FIXTURES')
    return '\n'.join(out)


if __name__ == '__main__':
    print(emit_mql())
