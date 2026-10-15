"""T012 READ-ONLY daily history FACTS for the robot - pure core (Python mirror of src/include/DailyHistory.mqh).

PURPOSE: turn what the MT5 terminal shows about deals of ONE Tirane day into separated FACTS. It deliberately does NOT count trades, does NOT
assign win / loss / breakeven, does NOT choose the formula of the daily result and does NOT reconstruct the balance at the start of the day.
Those are POLICY decisions (open client questions) and must stay explicit. Nothing here is wired to the real permit; unclassified data is
never turned into zero or CLEAR. No order, no modification, no persistence, no real reset. The terminal reads live only in the thin MQL5
reader of the header (UNVERIFIED) and in the owner's read-only diagnostic script; this core takes the already-read raw data.

DAY: the Tirane day comes from T009 (t009_session_reference.evaluate): start = midnight_utc of the day of cfg.utc_in_day, end = the midnight of
the next day (evaluated 30 h after the start, always inside the next day: days last 23-25 h). The window is [start, end) in UTC. Deal times are
SERVER time: utc = deal_time - cfg.server_offset_seconds. The offset is an EXPLICIT input (multiple of 900 s, |x| <= 14 h); a change of the server
offset (broker DST) INSIDE the day cannot be detected from deal data - a documented gap; the diagnostic prints TimeTradeServer() - TimeGMT().

OWNERSHIP (what is provable): the EA identity is the explicit magic number cfg.ea_magic (> 0; 0 is the magic of manual, mobile and web orders and
is refused). A POSITION belongs to the robot iff its OPENING deal (the first DEAL_ENTRY_IN, found with HistorySelectByPosition(identifier)) carries
DEAL_MAGIC == ea_magic; every deal of that position identifier (exits, partial exits, SL/TP) is then a robot-position deal. Limits that stay: a
magic number is NOT unique proof of the EA (another EA, a script or a person can use the same number: a collision cannot be detected); the magic
of an exit deal is NOT used for ownership (a manual close of a robot position keeps the position the robot's and is counted separately in
exits_not_by_ea_magic); the position identifier (not the ticket) links the deals; netting/exchange accounts are not supported (BLOCK): there all
trades of a symbol share one position, so robot and manual trades cannot be separated.

FACTS (separate fields, nothing merged): per entry class IN / OUT / INOUT / OUT_BY / OTHER of the robot-position deals inside the day: count, volume,
profit, commission, swap, fee; the same four money fields of the NON-TRADE deals (balance, credit, charge, correction, bonus ...: deposits and
withdrawals live there) kept apart and never mixed into the robot sums; counts of other (manual / other-EA) trade deals, duplicates, deals outside
the window; per robot position touched: how many entry and exit deals, volume, the four money fields, and its state - OPEN_NO_EXIT,
OPEN_PARTIALLY_CLOSED, CLOSED (all-time exit volume equals entry volume in volume steps) - positions whose volumes do not add up are UNKNOWN.
DEAL COUNT IS NOT TRADE COUNT: a position with one entry and two partial exits is three deals and one position. Three candidate result
formulas are printed side by side and NONE is selected: result_formula is the constant UNSET.
BALANCE AT THE START OF THE DAY is never reconstructed (current balance minus profit ignores deposits, withdrawals, credits and costs): the facts say
balance_start_known = False; it must be supplied by the owner or read by a later, separately verified step.
VERDICT: READY (facts built; `complete` is True only when the owner asserts the history is fully loaded AND every detectable check passed), UNKNOWN
(invalid config, API error, history or positions unreadable, capacity exceeded - 200 deals / 32 positions, two reads differing, a conflicting
duplicate ticket, an opening deal not found, a trade deal whose position is not described, inconsistent position volumes), BLOCK (account mode
other than HEDGING). A READY with complete=False is for display only.
"""
import math
from dataclasses import dataclass, field

import t006_sizing_reference as t006
import t009_session_reference as t009

MAX_DEALS, MAX_POS = 200, 32
ENTRY_IN, ENTRY_OUT, ENTRY_INOUT, ENTRY_OUT_BY = 0, 1, 2, 3
CLASSES = ('IN', 'OUT', 'INOUT', 'OUT_BY', 'OTHER')
DEAL_BUY, DEAL_SELL = 0, 1
MARGIN_HEDGING = 2
READY, UNKNOWN, BLOCK = 'READY', 'UNKNOWN', 'BLOCK'
RESULT_FORMULA = 'UNSET'


@dataclass
class Cfg:
    ea_magic: int
    utc_in_day: int
    server_offset_seconds: int
    history_complete_asserted: bool = False


@dataclass
class RawDeal:
    ticket: int
    position_id: int
    time: int          # server time
    entry: int
    type: int
    magic: int
    volume: float
    profit: float
    commission: float
    swap: float
    fee: float


@dataclass
class RawPos:
    position_id: int
    opened_known: bool        # the opening deal was found by HistorySelectByPosition
    opened_magic: int
    open_volume_total: float  # all-time sum of IN volumes
    closed_volume_total: float  # all-time sum of OUT / INOUT / OUT_BY volumes
    is_open: bool             # found among the open positions (by identifier)


@dataclass
class Raw:
    api_ok: bool = True
    api_error: str = ''
    hist_ok: bool = True
    positions_ok: bool = True
    margin_ok: bool = True
    margin_mode: int = MARGIN_HEDGING
    vol_step: float = 0.01
    deals_truncated: bool = False
    pos_truncated: bool = False
    deals: list = field(default_factory=list)
    positions: list = field(default_factory=list)


@dataclass
class Cell:
    count: int = 0
    volume: float = 0.0
    profit: float = 0.0
    commission: float = 0.0
    swap: float = 0.0
    fee: float = 0.0


@dataclass
class PosFact:
    position_id: int
    n_in: int = 0
    n_out: int = 0
    volume_in: float = 0.0
    volume_out: float = 0.0
    profit: float = 0.0
    commission: float = 0.0
    swap: float = 0.0
    fee: float = 0.0
    state: str = ''


@dataclass
class Facts:
    day_key: int = 0
    window_start: int = 0
    window_end: int = 0
    deals_in_window: int = 0
    duplicates: int = 0
    outside_window: int = 0
    other_trade_deals: int = 0
    exits_not_by_ea_magic: int = 0
    nontrade_count: int = 0
    nontrade_profit: float = 0.0
    nontrade_commission: float = 0.0
    nontrade_swap: float = 0.0
    nontrade_fee: float = 0.0
    matrix: dict = field(default_factory=lambda: {c: Cell() for c in CLASSES})
    positions: list = field(default_factory=list)
    candidate_profit: float = 0.0
    candidate_profit_commission_swap: float = 0.0
    candidate_profit_commission_swap_fee: float = 0.0
    result_formula: str = RESULT_FORMULA
    balance_start_known: bool = False
    balance_start_note: str = 'NOT RECONSTRUCTED: current balance minus profit ignores deposits, withdrawals, credits and costs; supply it or read it in a separately verified step'
    complete: bool = False
    proof: str = ''


@dataclass
class Outcome:
    verdict: str
    reason: str = ''
    facts: object = None


def _u(reason):
    return Outcome(UNKNOWN, reason)


def day_window(utc):
    s = t009.evaluate(utc)
    if s['status'] != 'OK':
        return None
    start = s['midnight_utc']
    nxt = t009.evaluate(start + 30 * 3600)
    if nxt['status'] != 'OK':
        return None
    return s['day'], start, nxt['midnight_utc']


def raw_equal(a, b):
    return a == b


def _entry_class(e):
    return {ENTRY_IN: 'IN', ENTRY_OUT: 'OUT', ENTRY_INOUT: 'INOUT', ENTRY_OUT_BY: 'OUT_BY'}.get(e, 'OTHER')


def build(cfg, raw, stable):
    if isinstance(cfg.ea_magic, bool) or not isinstance(cfg.ea_magic, int) or cfg.ea_magic <= 0:
        return _u('INVALID_CONFIG: ea_magic must be an integer > 0 (0 is the magic of manual, mobile and web orders)')
    off = cfg.server_offset_seconds
    if isinstance(off, bool) or not isinstance(off, int) or off % 900 != 0 or abs(off) > 50400:
        return _u('INVALID_CONFIG: server_offset_seconds must be a multiple of 900 and within +-14 h')
    if isinstance(cfg.utc_in_day, bool) or not isinstance(cfg.utc_in_day, int):
        return _u('INVALID_CONFIG: utc_in_day')
    win = day_window(cfg.utc_in_day)
    if win is None:
        return _u('INVALID_CONFIG: utc_in_day is not a supported instant (T009)')
    day, start, end = win
    if not raw.api_ok:
        return _u('API_ERROR: ' + raw.api_error)
    if not raw.margin_ok:
        return _u('ACCOUNT_MODE_UNAVAILABLE')
    if raw.margin_mode != MARGIN_HEDGING:
        return Outcome(BLOCK, 'UNSUPPORTED_ACCOUNT_MODE: margin mode %d; only HEDGING separates robot positions from other trades' % raw.margin_mode)
    if not raw.hist_ok:
        return _u('HISTORY_UNAVAILABLE: the deal history could not be selected')
    if not raw.positions_ok:
        return _u('POSITIONS_UNAVAILABLE: the open positions could not be read')
    if not t006._num(raw.vol_step) or raw.vol_step <= 0:
        return _u('SYMBOL_PARAMETERS_UNAVAILABLE: the real volume step could not be read')
    if raw.deals_truncated or raw.pos_truncated or len(raw.deals) > MAX_DEALS or len(raw.positions) > MAX_POS:
        return _u('CAPACITY: more than %d deals or %d positions; nothing is truncated silently' % (MAX_DEALS, MAX_POS))
    if not stable:
        return _u('READ_UNSTABLE: two consecutive reads differ')
    f = Facts(day_key=day, window_start=start, window_end=end)
    pos_by_id = {}
    for p in raw.positions:
        if p.position_id in pos_by_id:
            return _u('READ_INCONSISTENT: position %d described twice' % p.position_id)
        pos_by_id[p.position_id] = p
    seen = {}
    pfacts = {}
    for d in raw.deals:
        if d.ticket in seen:
            if seen[d.ticket] == d:
                f.duplicates += 1
                continue
            return _u('READ_INCONSISTENT: deal ticket %d appears twice with different content' % d.ticket)
        seen[d.ticket] = d
        for v in (d.volume, d.profit, d.commission, d.swap, d.fee):
            if not t006._num(v):
                return _u('READ_INCONSISTENT: deal %d has a non-finite number' % d.ticket)
        utc = d.time - off
        if not (start <= utc < end):
            f.outside_window += 1
            continue
        f.deals_in_window += 1
        if d.type not in (DEAL_BUY, DEAL_SELL):
            f.nontrade_count += 1
            f.nontrade_profit += d.profit
            f.nontrade_commission += d.commission
            f.nontrade_swap += d.swap
            f.nontrade_fee += d.fee
            continue
        p = pos_by_id.get(d.position_id)
        if p is None or not p.opened_known:
            return _u('OWNERSHIP_UNPROVABLE: position %d of deal %d is not described or its opening deal was not found' % (d.position_id, d.ticket))
        if p.opened_magic != cfg.ea_magic:
            f.other_trade_deals += 1
            continue
        cls = _entry_class(d.entry)
        c = f.matrix[cls]
        c.count += 1
        c.volume += d.volume
        c.profit += d.profit
        c.commission += d.commission
        c.swap += d.swap
        c.fee += d.fee
        if cls != 'IN' and d.magic != cfg.ea_magic:
            f.exits_not_by_ea_magic += 1
        pf = pfacts.setdefault(d.position_id, PosFact(d.position_id))
        if cls == 'IN':
            pf.n_in += 1
            pf.volume_in += d.volume
        else:
            pf.n_out += 1
            pf.volume_out += d.volume
        pf.profit += d.profit
        pf.commission += d.commission
        pf.swap += d.swap
        pf.fee += d.fee
    for pid in sorted(pfacts):
        pf = pfacts[pid]
        p = pos_by_id[pid]
        opened = t006._grid_steps(p.open_volume_total, raw.vol_step) if p.open_volume_total > 0 else 0
        closed = t006._grid_steps(p.closed_volume_total, raw.vol_step) if p.closed_volume_total > 0 else 0
        if opened < 0 or closed < 0 or opened == 0:
            return _u('INCONSISTENT_POSITION_VOLUMES: position %d volumes are not on the step grid or no entry volume' % pid)
        if p.is_open:
            if closed >= opened:
                return _u('INCONSISTENT_POSITION_VOLUMES: position %d is open but exits (%d steps) cover its entries (%d steps)' % (pid, closed, opened))
            pf.state = 'OPEN_NO_EXIT' if closed == 0 else 'OPEN_PARTIALLY_CLOSED'
        else:
            if closed != opened:
                return _u('INCONSISTENT_POSITION_VOLUMES: position %d is not open but exits (%d steps) differ from entries (%d steps)' % (pid, closed, opened))
            pf.state = 'CLOSED'
        f.positions.append(pf)
    cells = f.matrix.values()
    f.candidate_profit = sum(c.profit for c in cells)
    f.candidate_profit_commission_swap = sum(c.profit + c.commission + c.swap for c in cells)
    f.candidate_profit_commission_swap_fee = sum(c.profit + c.commission + c.swap + c.fee for c in cells)
    f.complete = bool(cfg.history_complete_asserted)
    f.proof = ('the owner asserts the history is fully loaded; every detectable check passed' if f.complete else
               'NOT asserted: the terminal cannot prove that the whole account history is loaded')
    return Outcome(READY, '', f)
