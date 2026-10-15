"""T018 exposure reader (pure core + port). READ-ONLY account exposure of THIS EA for the entry gate: owned positions / pending orders (by magic only), the loss-at-SL risk of what is owned.
No accounting is invented: a manual / other-EA position is never counted as owned; a netting account (ownership not separable) , an incomplete list, a missing SL, an unreadable broker calculation or an UNSET
pending policy never becomes zero - the value is UNKNOWN (-1) and the gate blocks. Mirror of src/include/ExposureReader.mqh."""
from dataclasses import dataclass, field

PEND_UNSET, PEND_COUNT, PEND_IGNORE = 0, 1, 2      # does an owned pending order RESERVE a position (count policy)
RISK_UNSET, RISK_INCLUDE, RISK_EXCLUDE = 0, 1, 2    # is the risk of an owned pending order part of the existing risk (a separate owner decision)
HEDGING = 2


@dataclass
class Pos:
    ticket: int
    symbol: str
    magic: int
    kind: int          # 0 buy, 1 sell, other = unknown
    volume: float
    price: float
    sl: float


@dataclass
class Ord:
    ticket: int
    symbol: str
    magic: int
    kind: int          # 0 buy side, 1 sell side, other = unknown
    volume: float
    price: float
    sl: float


@dataclass
class Port:
    account_ok: bool = True
    margin_mode: int = HEDGING
    positions: list = field(default_factory=list)
    pos_complete: bool = True
    orders: list = field(default_factory=list)
    ord_complete: bool = True
    calc_fail_ticket: int = 0
    change_positions: object = None   # callable(list) -> list: the second read of the positions differs
    change_orders: object = None
    pos_reads: int = 0
    calls: int = 0
    reads_orders: int = 0

    def calc(self, buy, symbol, volume, open_, sl):
        self.calls += 1
        if volume <= 0:
            return None
        return volume * ((sl - open_) if buy else (open_ - sl)) * 100.0     # scripted broker: profit at the stop

    def calc_for(self, ticket, buy, symbol, volume, open_, sl):
        if ticket == self.calc_fail_ticket:
            return None
        return self.calc(buy, symbol, volume, open_, sl)


@dataclass
class Result:
    ok: bool = False            # the counts are trustworthy
    reason: str = ''
    open_positions: int = -1
    pending: int = -1
    foreign_positions: int = 0
    foreign_pending: int = 0
    risk_known: bool = False
    existing_risk: float = -1.0
    risk_reason: str = ''

    def gate_positions(self):
        """what the gate gets: positions (+ pending when the policy says so); -1 = unknown"""
        return self.open_positions if self.ok else -1

    def gate_risk(self):
        return self.existing_risk if (self.ok and self.risk_known) else -1.0


def _finite(x):
    return x == x and x not in (float('inf'), float('-inf'))


def _same(a, b):
    return len(a) == len(b) and all(x == y for x, y in zip(a, b))


def _read(port, which):
    """two reads of the same list; a difference between them = the list changed while it was read = unknown"""
    if which == 'pos':
        first = list(port.positions)
        port.pos_reads += 1
        second = list(port.change_positions(first)) if port.change_positions else list(port.positions)
        complete = port.pos_complete
    else:
        first = list(port.orders)
        second = list(port.change_orders(first)) if port.change_orders else list(port.orders)
        complete = port.ord_complete
    return first, complete, _same(first, second)


def compute(magic, symbol, pend_policy, port, risk_policy=RISK_UNSET):
    r = Result()
    if magic <= 0 or not symbol or pend_policy not in (PEND_COUNT, PEND_IGNORE) or risk_policy not in (RISK_UNSET, RISK_INCLUDE, RISK_EXCLUDE):
        r.reason = 'INPUT_UNSET'
        return r
    if not port.account_ok:
        r.reason = 'ACCOUNT_UNREADABLE'
        return r
    if port.margin_mode != HEDGING:
        r.reason = 'OWNERSHIP_NOT_SEPARABLE'
        return r
    positions, complete, stable = _read(port, 'pos')
    if not complete or len(positions) > 64:
        r.reason = 'POSITIONS_INCOMPLETE'
        return r
    if not stable:
        r.reason = 'POSITIONS_CHANGED'
        return r
    owned_pos = []
    for p in positions:
        if p.magic == magic:
            if p.kind not in (0, 1):
                r.reason = 'POSITION_TYPE_UNKNOWN'
                return r
            owned_pos.append(p)
        else:
            r.foreign_positions += 1
    owned_ord = []
    port.reads_orders += 1
    orders, ocomplete, ostable = _read(port, 'ord')
    if not ocomplete or len(orders) > 64:
        r.reason = 'ORDERS_INCOMPLETE'
        return r
    if not ostable:
        r.reason = 'ORDERS_CHANGED'
        return r
    for o in orders:
        if o.magic == magic:
            if o.kind not in (0, 1):
                r.reason = 'ORDER_TYPE_UNKNOWN'
                return r
            owned_ord.append(o)
        else:
            r.foreign_pending += 1
    r.ok = True
    r.reason = 'OK'
    r.pending = len(owned_ord)
    r.open_positions = len(owned_pos) + (r.pending if pend_policy == PEND_COUNT else 0)
    total = 0.0
    r.risk_known = True
    if owned_ord and risk_policy == RISK_UNSET:
        r.risk_known, r.risk_reason = False, 'PENDING_RISK_POLICY_UNSET: %d owned pending order(s)' % len(owned_ord)
    risk_items = [('position', p) for p in owned_pos] + ([('order', o) for o in owned_ord] if risk_policy == RISK_INCLUDE else [])
    for kind, item in (risk_items if r.risk_known else []):
        if not (item.sl > 0 and _finite(item.sl) and item.price > 0 and _finite(item.price) and item.volume > 0):
            r.risk_known, r.risk_reason = False, '%s %d: no usable SL / price / volume' % (kind, item.ticket)
            break
        profit = port.calc_for(item.ticket, item.kind == 0, item.symbol, item.volume, item.price, item.sl)
        if profit is None or not _finite(profit):
            r.risk_known, r.risk_reason = False, '%s %d: broker calculation not obtained' % (kind, item.ticket)
            break
        total += max(0.0, -profit)          # a stop already past break-even carries no risk
    r.existing_risk = total if r.risk_known else -1.0
    return r
