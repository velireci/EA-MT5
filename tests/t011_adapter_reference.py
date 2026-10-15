"""T011 read-only snapshot ADAPTER, pure core (Python mirror of src/include/ExitSnapshotAdapter.mqh).

PURPOSE: build the SErSnapshot / Snapshot that t011_reconcile_reference.reconcile() judges, from what the MT5 terminal shows about positions,
orders and deals. The MT5 reads themselves live only in the thin MQL5 reader of the header (UNVERIFIED, owner diagnostic script); this
core takes the already-read raw data, so that every decision is testable. NOTHING here sends, modifies, cancels or closes anything, and the
adapter NEVER writes the activation state (the caller applies reconcile on READY; BLOCK/UNKNOWN are verdicts to act on, see below).

HOW IDENTITIES ARE LINKED (what is provable and what is not)
  * request_id (ours, "X2R80-<position id>") exists in no MT5 field. It is NOT equated with a broker comment, and magic/volume/time are NOT
    accepted as proof of a link.
  * position identifier: POSITION_IDENTIFIER / DEAL_POSITION_ID / ORDER_POSITION_ID is the stable id of the position over its life. The position
    is found by IDENTIFIER (never by assuming ticket == identifier; the fixtures use ticket != identifier). state.position_id must be that
    identifier.
  * order ticket: a closing DEAL carries DEAL_ORDER, the ticket of the order that produced it. The ONLY provable chain is
        request_id --(map supplied by the executor)--> order ticket(s) --DEAL_ORDER--> deal ticket --DEAL_POSITION_ID--> position identifier.
    The executor that sends the close order does not exist yet. Its identity map (request_id, position identifier, symbol, every order ticket it
    received, and its assertion `orders_complete`) is therefore an INPUT. Without a map, or with a map without order tickets: UNKNOWN. This is
    the exact gap: the part that records the order tickets at send time is not built; no alternative link is invented.
  * deal ticket: identifies an execution (deduplicated by it); only EXIT deals (DEAL_ENTRY_OUT) of a mapped order on this position count.
    Entries (IN), deals of unmapped orders (manual trades, SL/TP, other requests), OUT_BY / INOUT, balance deals are excluded and counted.
VERDICTS: READY (a snapshot is built; reconcile judges it), UNKNOWN (no snapshot: API error, history unavailable, read unstable, capacity
exceeded, no/invalid map, no request), BLOCK (no snapshot, must not be retried into a confirmation: unsupported account mode, ambiguous or
inconsistent identity, wrong direction/symbol, conflicting map). Nothing is truncated silently: more than 64 deals or more than 16 linked
executions is UNKNOWN.
ACCOUNT MODE: HEDGING is supported (positions are separate, selected by identifier). NETTING and EXCHANGE are NOT supported: all trades of
the symbol share one position there, so our fills cannot be separated from other trades -> BLOCK. Any other value -> BLOCK.
executions_complete is True ONLY when ALL of these are proven (each is listed in `proof` when missing):
  1 the executor asserts the order tickets are complete (map.orders_complete);
  2 every mapped order is found in the HISTORY in a final state (FILLED, CANCELED, REJECTED, EXPIRED), none is still active or missing;
  3 for every mapped order the sum of its linked exit deals equals its executed volume (ORDER_VOLUME_INITIAL - ORDER_VOLUME_CURRENT) in volume steps;
  4 every mapped order that executed anything belongs to this position (ORDER_POSITION_ID == identifier);
  5 the position's opening (IN) deal is present in the deal list, so the history reaches back to the open;
  6 two consecutive reads were identical (stability), the caller passes stable=True.
A failed read, an unstable read or a capacity overflow is UNKNOWN instead (no snapshot at all). The real broker volume step is read and
passed as snapshot.volume_step (it is NOT copied from the state, so a changed step is seen and blocked by reconcile).
The state is only READ (request_id, position_id, direction, status); a BLOCKED state gives BLOCK, an IDLE state UNKNOWN.
"""
import math
from dataclasses import dataclass, field

import t006_sizing_reference as t006
import t011_activation_reference as act
import t011_reconcile_reference as rec

MAX_DEALS, MAX_ORDERS = 64, 8
ENTRY_IN, ENTRY_OUT, ENTRY_INOUT, ENTRY_OUT_BY = 0, 1, 2, 3
DEAL_BUY, DEAL_SELL = 0, 1
POS_BUY, POS_SELL = 0, 1
ORD_CANCELED, ORD_PARTIAL, ORD_FILLED, ORD_REJECTED, ORD_EXPIRED, ORD_PLACED = 2, 3, 4, 5, 6, 1
FINAL_STATES = (ORD_CANCELED, ORD_FILLED, ORD_REJECTED, ORD_EXPIRED)
MARGIN_NETTING, MARGIN_EXCHANGE, MARGIN_HEDGING = 0, 1, 2
WHERE_NONE, WHERE_ACTIVE, WHERE_HISTORY = 0, 1, 2
READY, UNKNOWN, BLOCK = 'READY', 'UNKNOWN', 'BLOCK'


@dataclass
class Map:
    request_id: str
    position_id: int
    symbol: str
    orders: list = field(default_factory=list)
    orders_complete: bool = False


@dataclass
class RawDeal:
    ticket: int
    order: int
    position_id: int
    entry: int
    type: int
    volume: float


@dataclass
class RawOrder:
    ticket: int
    where: int
    state: int = 0
    vol_initial: float = 0.0
    vol_current: float = 0.0
    position_id: int = 0


@dataclass
class Raw:
    api_ok: bool = True
    api_error: str = ''
    symbol_ok: bool = True
    vol_step: float = 0.01
    vol_min: float = 0.01
    vol_max: float = 100.0
    margin_ok: bool = True
    margin_mode: int = MARGIN_HEDGING
    n_pos: int = 1
    pos_ticket: int = 9
    pos_type: int = POS_BUY
    pos_volume: float = 0.1
    pos_symbol: str = 'XAUUSD'
    hist_ok: bool = True
    deals_truncated: bool = False
    deals: list = field(default_factory=list)
    orders: list = field(default_factory=list)


@dataclass
class Result:
    verdict: str
    reason: str = ''
    snapshot: object = None
    complete: bool = False
    proof: str = ''
    linked_deals: int = 0
    duplicate_deals: int = 0
    excluded_entries: int = 0
    excluded_other: int = 0


def _unknown(reason):
    return Result(UNKNOWN, reason)


def _block(reason):
    return Result(BLOCK, reason)


def raw_equal(a, b):
    """Two reads are the same read (stability)."""
    return a == b


def build(state, mp, raw, stable):
    if state.status == act.BLOCKED:
        return _block('ALREADY_BLOCKED: ' + state.reason)
    if not state.bound or state.request_id == '' or state.status == act.IDLE:
        return _unknown('NO_REQUEST: there is no request to reconcile')
    if not isinstance(mp, Map) or not isinstance(mp.request_id, str) or mp.request_id == '':
        return _unknown('NO_MAP: the executor identity map is missing')
    if mp.request_id != state.request_id:
        return _block('MAP_REQUEST_MISMATCH: the map names %s, the state has %s' % (mp.request_id, state.request_id))
    if mp.position_id != state.position_id:
        return _block('MAP_POSITION_MISMATCH: the map names position %s, the state has %s' % (mp.position_id, state.position_id))
    if not isinstance(mp.orders, list) or len(mp.orders) == 0:
        return _unknown('NO_ORDER_TICKETS: the map names no order ticket, so no deal can be linked to the request')
    if len(mp.orders) > MAX_ORDERS or len(set(mp.orders)) != len(mp.orders) or any(isinstance(t, bool) or not isinstance(t, int) or t <= 0 for t in mp.orders):
        return _unknown('MAP_INVALID: order tickets must be distinct positive integers, at most %d' % MAX_ORDERS)
    if not raw.api_ok:
        return _unknown('API_ERROR: ' + raw.api_error)
    if not raw.symbol_ok or not t006._num(raw.vol_step) or raw.vol_step <= 0 or not t006._num(raw.vol_min) or raw.vol_min <= 0 or not t006._num(raw.vol_max) or raw.vol_max <= 0:
        return _unknown('SYMBOL_PARAMETERS_UNAVAILABLE: the real volume step, minimum and maximum could not be read')
    if not raw.margin_ok:
        return _unknown('ACCOUNT_MODE_UNAVAILABLE')
    if raw.margin_mode != MARGIN_HEDGING:
        return _block('UNSUPPORTED_ACCOUNT_MODE: margin mode %d; only HEDGING separates our position from other trades' % raw.margin_mode)
    if not raw.hist_ok:
        return _unknown('HISTORY_UNAVAILABLE: the history of the position could not be selected')
    if raw.deals_truncated or len(raw.deals) > MAX_DEALS or len(raw.orders) > MAX_ORDERS:
        return _unknown('CAPACITY: more than %d deals or %d orders; the list is not truncated silently' % (MAX_DEALS, MAX_ORDERS))
    if not stable:
        return _unknown('READ_UNSTABLE: two consecutive reads differ (position, deals or orders changed while reading)')
    if raw.n_pos > 1:
        return _block('AMBIGUOUS_POSITION: %d open positions share the identifier %d' % (raw.n_pos, mp.position_id))
    found = raw.n_pos == 1
    if found:
        if raw.pos_symbol != mp.symbol:
            return _block('SYMBOL_MISMATCH: position symbol %s is not %s' % (raw.pos_symbol, mp.symbol))
        want = POS_BUY if state.direction == 1 else POS_SELL
        if raw.pos_type != want:
            return _block('DIRECTION_MISMATCH: position type %d does not match the state direction %d' % (raw.pos_type, state.direction))
        if not t006._num(raw.pos_volume) or raw.pos_volume <= 0:
            return _unknown('POSITION_VOLUME_INVALID')
    # ---- deals: de-duplicated by ticket, only exit deals of a mapped order count
    seen = {}
    linked, dup, ex_entry, ex_other, has_entry_in = [], 0, 0, 0, False
    for d in raw.deals:
        if d.position_id != mp.position_id:
            return _unknown('READ_INCONSISTENT: deal %d belongs to position %d, not %d' % (d.ticket, d.position_id, mp.position_id))
        if d.ticket in seen:
            if seen[d.ticket] == d:
                dup += 1
                continue
            return _unknown('READ_INCONSISTENT: deal ticket %d appears twice with different content' % d.ticket)
        seen[d.ticket] = d
        if d.entry == ENTRY_IN:
            has_entry_in = True
            ex_entry += 1
            continue
        if d.entry != ENTRY_OUT:
            ex_entry += 1
            continue
        wrong = DEAL_SELL if state.direction == 1 else DEAL_BUY
        if d.type not in (DEAL_BUY, DEAL_SELL) or d.type != wrong:
            return _block('DEAL_DIRECTION_MISMATCH: exit deal %d has type %d against a position with direction %d' % (d.ticket, d.type, state.direction))
        if d.order not in mp.orders:
            ex_other += 1
            continue
        if not t006._num(d.volume) or d.volume <= 0:
            return _unknown('READ_INCONSISTENT: deal %d has an invalid volume' % d.ticket)
        linked.append(d)
    if len(linked) > rec.MAX_EXEC:
        return _unknown('CAPACITY: %d linked executions exceed the %d of a snapshot; not truncated' % (len(linked), rec.MAX_EXEC))
    # ---- completeness: everything must be proven
    missing = []
    if not mp.orders_complete:
        missing.append('the executor does not assert that the order ticket list is complete')
    by_order = {}
    for o in raw.orders:
        by_order[o.ticket] = o
    for t in mp.orders:
        o = by_order.get(t)
        if o is None or o.where == WHERE_NONE:
            missing.append('order %d not found' % t)
            continue
        if o.where != WHERE_HISTORY or o.state not in FINAL_STATES:
            missing.append('order %d is not final in the history' % t)
            continue
        executed = o.vol_initial - o.vol_current
        e_steps = 0 if abs(executed) < raw.vol_step / 2 else t006._grid_steps(executed, raw.vol_step)
        d_steps = 0
        for d in linked:
            if d.order == t:
                k = t006._grid_steps(d.volume, raw.vol_step)
                d_steps = d_steps + (k if k > 0 else 0)
        if e_steps < 0 or e_steps != d_steps:
            missing.append('order %d executed volume does not match its deals' % t)
        if e_steps != 0 and o.position_id != mp.position_id:
            return _block('ORDER_POSITION_MISMATCH: order %d executed on position %d, not %d' % (t, o.position_id, mp.position_id))
    if not has_entry_in:
        missing.append('the opening deal of the position is not in the history list')
    complete = not missing
    snap = rec.Snapshot(found, mp.position_id, state.request_id, raw.vol_step, raw.pos_volume if found else 0.0,
                        [rec.Exec(str(d.ticket), state.request_id, d.volume) for d in linked], complete)
    return Result(READY, '', snap, complete, '; '.join(missing) if missing else 'complete: all six proofs hold', len(linked), dup, ex_entry, ex_other)
