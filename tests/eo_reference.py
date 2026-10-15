"""T016 ENTRY ORCHESTRATOR core (Python mirror of src/include/EntryOrchestrator.mqh): the decision layer of the EA that links the EXISTING flow
  H4/M15 observer state (T004) -> SetupPlanBridge (T014) -> EntryGate (T015) -> EntryExecutor (T013)
with a FAKE transport fixed in this delivery. It re-implements no H4 / M15 algorithm, no geometry or sizing formula, no filter and no limit: every step is a call into the existing module.

What this layer adds (and nothing else):
  * BASELINE: the first successful build after the start, after ANY data defect, after the context was lost or CHANGED sets the baseline = the cut of that build (monotone). A candidate confirmed at or
    before the baseline is historical / replayed and is never a signal (SPB live_after). So the replay at start, the recovery after a defect and a restart never produce a signal.
  * geometry without sizing: SPB_Geometry selects the candidate and calls TG_Compute. The broker probe (OrderCalcProfit for the minimum volume over that stop)
    gives the EFFECTIVE tick value (no property fallback); only then does SPB_Build size the plan the gate sees. No provisional plan uses the REPORTED tick value.
  * real data only: symbol, quote (fresh), the loss estimate, the existing filters and the daily result come from the market port; a missing value is never zero / CLEAR (UNKNOWN or a block).
  * exposure, counters and policies that no existing module proves are EXPLICIT inputs, unknown by default (-1): nothing is invented.
  * the checks of one decision share one instant and the plan digest (T015 binds and ages them); the in-memory handled list feeds TP_CheckPermit's duplicate check, the durable guard stays in the entry
    executor's record.
  * a fresh executor runtime per signal (the executor allows one send per runtime); an uncertain outcome HALTS the layer until restart.
Nothing here can reach a real transport: the caller passes the transport; the EA fixes a FAKE one."""
from dataclasses import dataclass, field, replace
import copy

import entry_gate_reference as eg
import entry_reference as en
import spb_reference as sp
import t007_planning_reference as tp
import t008_broker_loss as bl
import t012_bridge_reference as br

FAKE_LABEL = 'FAKE EXECUTION: a virtual request, nothing is sent to the terminal'


@dataclass
class Config:
    sel: sp.Selection = field(default_factory=sp.Selection)
    risk_budget: float = -1.0
    risk_source: int = 0                   # 0 = the explicit amount above (-1 blocks); 1 = DEMO policy: 1% of the CURRENT account balance, read at every step (a failed / invalid / stale / non-demo read blocks; no fallback)
    lot_cap: float = -1.0
    model_tolerance: float = -1.0
    max_quote_age: int = -1
    open_positions: int = -1               # exposure and counters: explicit inputs, unknown by default (no accounting is invented)
    trades_today: int = -1
    existing_risk: float = -1.0
    max_positions: int = -1                # limits: -1 = UNSET
    max_trades: int = -1
    risk_cap: float = -1.0
    gate: eg.GateConfig = field(default_factory=eg.GateConfig)
    exec: en.Config = field(default_factory=en.Config)


@dataclass
class Sym:
    read_ok: bool = False
    tick_size: float = 0.0
    digits: int = -1
    point: float = 0.0
    stops_level: int = -1
    vol_min: float = 0.0
    vol_step: float = 0.0
    vol_max: float = 0.0
    reported_tick_value: float = 0.0
    trade_ok: bool = False


@dataclass
class Quote:
    read_ok: bool = False
    bid: float = 0.0
    ask: float = 0.0
    time: int = 0


@dataclass
class Facts:
    """what the step knows about the direction (the lifecycle evaluates it per record): unknown or incomplete data is valid=False / direction 0 and proves nothing"""
    valid: bool = False
    ctx_direction: int = 0
    signal_direction: int = 0
    signal_id: str = ''
    time: int = 0


RISK_SOURCE_AMOUNT, RISK_SOURCE_DEMO_BALANCE_PCT = 0, 1
RISK_PCT_DEMO = 1.0                         # fixed: the demo policy is 1% and nothing else; it is NOT a client confirmation for live (D2)


@dataclass
class Balance:
    read_ok: bool = False
    amount: float = 0.0
    time: int = 0
    demo: bool = False


@dataclass
class Outcome:
    status: str = ''
    reason: str = ''
    request: bool = False                  # a virtual (fake) request was accepted by the fake transport
    result: object = None
    decision: object = None
    spb: object = None
    label: str = ''
    risk_budget: float = -1.0              # the budget this step sized the plan with AND checked the loss against (one value)
    risk_base: float = -1.0                # the balance it came from (policy 1), else -1


HANDLED_FINALS = (en.R_PLACED, en.R_FILLED, en.R_DUPLICATE, en.R_REJECTED, en.R_RECOVERY, en.R_BLOCKED, en.R_PRECHECK_REFUSED, en.R_CANCELLED, en.R_EXPIRED, en.R_NOCHANGE)
HALT_FINALS = (en.R_RECOVERY, en.R_BLOCKED, en.R_CANCEL_UNCERTAIN)


def _key(ob):
    c = ob.context
    return '' if c is None else copy.deepcopy(c)


def _finite(x):
    return x == x and x not in (float('inf'), float('-inf'))


def unset_config(cfg):
    bad = []
    if cfg.risk_source not in (RISK_SOURCE_AMOUNT, RISK_SOURCE_DEMO_BALANCE_PCT):
        bad.append('risk_source')
    elif cfg.risk_source == RISK_SOURCE_AMOUNT and not cfg.risk_budget > 0:
        bad.append('risk_budget')
    if not cfg.lot_cap > 0:
        bad.append('lot_cap')
    if not 0 <= cfg.model_tolerance <= 1:
        bad.append('model_tolerance')
    if not cfg.max_quote_age > 0:
        bad.append('max_quote_age')
    return bad


class Orchestrator:
    def __init__(self):
        self.baseline = 0
        self.rebase = True
        self.key = None
        self.handled = []
        self.halted = ''
        self.signals = 0                    # fake requests accepted
        self.facts = Facts()                # refreshed by every step

    def defect(self):
        """a data defect or a recovery: the next successful build starts a new baseline (an old signal is never revived)"""
        self.rebase = True

    def step(self, cfg, mk, feed_ok, ob, broken, cut, tr, store, pre_send=None):
        self.facts = Facts()
        if not feed_ok or ob is None:
            self.defect()
            return Outcome('FEED_NOT_OK', 'no confirmed data; the baseline restarts with the next successful build')
        key = _key(ob)
        if key == '' or key != self.key:                      # a lost or CHANGED context also starts a new baseline
            self.rebase = True
        self.key = key
        if self.rebase or self.baseline == 0:
            self.baseline = max(self.baseline, cut)
            self.rebase = False
        c = ob.context
        if c is not None and c.ready and c.reliable and c.selected and c.direction in (1, -1):         # the context is KNOWN: only then does a direction prove a change
            self.facts = Facts(True, c.direction, 0, '', mk.now())
        if self.halted:
            return Outcome('HALTED', self.halted)
        bad = unset_config(cfg)
        if bad:
            return Outcome('CONFIG_UNSET', 'INPUT_UNSET: ' + ', '.join(bad))
        sym = mk.symbol()
        if not (sym.read_ok and sym.trade_ok and sym.tick_size > 0 and sym.vol_min > 0 and sym.vol_step > 0):
            self.defect()
            return Outcome('MARKET_NOT_READY', 'SYMBOL_UNREADABLE_OR_NOT_TRADABLE')
        q = mk.quote()
        now = mk.now()
        if not (q.read_ok and q.bid > 0 and q.ask >= q.bid and q.time > 0 and now > 0 and 0 <= now - q.time <= cfg.max_quote_age):
            self.defect()
            return Outcome('MARKET_NOT_READY', 'QUOTE_NOT_READY_OR_STALE')
        budget, base = cfg.risk_budget, -1.0
        if cfg.risk_source == RISK_SOURCE_DEMO_BALANCE_PCT:
            before_balance = now
            b = mk.balance()
            now = mk.now()  # check the balance against a clock sampled AFTER the read
            if now <= 0 or now < before_balance:
                self.defect()
                return Outcome('RISK_BASE_NOT_READY', 'RISK_CLOCK_INVALID: server clock moved backwards or is unavailable; no fallback')
            if not (b.read_ok and b.demo and _finite(b.amount) and b.amount > 0 and 0 <= now - b.time <= cfg.max_quote_age) or b.time <= 0:
                code = ('BALANCE_READ_FAILED' if not b.read_ok else 'ACCOUNT_NOT_DEMO' if not b.demo else
                        'BALANCE_INVALID_AMOUNT' if not _finite(b.amount) or b.amount <= 0 else 'BALANCE_TIME_INVALID' if b.time <= 0 else
                        'BALANCE_FROM_FUTURE' if b.time > now else 'BALANCE_STALE')
                self.defect()
                return Outcome('RISK_BASE_NOT_READY', '%s | read_ok=%d demo=%d balance=%.8f age=%d limit=%d | no fallback' %
                               (code, b.read_ok, b.demo, b.amount, now-b.time, cfg.max_quote_age))
            if not (0 <= now - q.time <= cfg.max_quote_age):
                self.defect()
                return Outcome('MARKET_NOT_READY', 'QUOTE_EXPIRED_DURING_BALANCE_READ')
            base = b.amount
            budget = b.amount * RISK_PCT_DEMO / 100.0
            if not (_finite(budget) and budget > 0):
                self.defect()
                return Outcome('RISK_BASE_NOT_READY', 'RISK_BUDGET_INVALID')
        sel = replace(cfg.sel, live_after=self.baseline)
        mkt = sp.Market(risk_budget=budget, tick_value=sym.reported_tick_value, tick_size=sym.tick_size, digits=sym.digits, point=sym.point, stops_level=sym.stops_level,
                        has_quote=True, bid=q.bid, ask=q.ask, vol_min=sym.vol_min, vol_step=sym.vol_step, vol_max=sym.vol_max, cap_lots=cfg.lot_cap)
        r1, geo = sp.geometry(sel, mkt, ob, broken, cut)
        if geo is None:
            return Outcome('NO_PLAN', r1.reason, spb=r1)
        if self.facts.valid:
            self.facts.signal_direction, self.facts.signal_id = ob.context.direction, r1.signal_id          # a live signal exists in this step
        if r1.signal_id in self.handled:
            return Outcome('ALREADY_HANDLED', r1.signal_id, spb=r1)
        buy = ob.context.direction == 1
        stop_ticks = int(round(geo.r_geom / sym.tick_size))
        ok, profit = mk.calc_profit(buy, sym.vol_min, geo.e_out, geo.s_out)
        tick = bl.probe_tick_value(ok, profit, sym.vol_min, stop_ticks)
        if not tick > 0:
            self.defect()
            return Outcome('PROBE_FAILED', 'BROKER_PROBE_FAILED: no reliable loss estimate; no property fallback', spb=r1)
        r2 = sp.build(sel, replace(mkt, tick_value=tick), ob, broken, cut)       # pass 2: the plan the gate sees
        if not r2.plan_ready:
            return Outcome('NO_PLAN', r2.reason, spb=r2)
        ok, profit = mk.calc_profit(buy, r2.plan.volume_out, r2.plan.e_out, r2.plan.s_out)
        if not ok or not sp._fin(profit):
            self.defect()
        session, news, spread = mk.filters()
        digest = en.plan_digest(eg.entry_plan(r2.plan))
        ctx = ob.context
        snap = tp.Snapshot(data_state=tp.DATA_READY if (ctx.ready and ctx.reliable and ctx.selected) else tp.DATA_NOT_READY, data_reliable=bool(ctx.reliable),
                           session_state=session, news_state=news, spread_state=spread, open_positions=cfg.open_positions, trades_today=cfg.trades_today, existing_risk=cfg.existing_risk)
        lim = tp.Limits(max_positions=cfg.max_positions if cfg.max_positions >= 0 else None, max_trades_per_day=cfg.max_trades if cfg.max_trades >= 0 else None,
                        combined_risk_cap=cfg.risk_cap if cfg.risk_cap >= 0 else None)
        reg = tp.Registry(ids=list(self.handled) + [''], count=len(self.handled))
        present, daily = mk.daily(r2)
        checks = eg.Checks(snapshot=snap, snapshot_time=now, snapshot_digest=digest, limits=lim, registry=reg, calc_ok=ok, profit=profit, tolerance=cfg.model_tolerance,
                           risk_budget=budget, loss_time=now, loss_digest=digest, daily_present=present, daily=daily, daily_time=now, daily_digest=digest)
        res, dec = eg.submit(cfg.gate, cfg.exec, tr, store, en.Runtime(), r2, checks, pre_send)
        out = Outcome('EXECUTOR', res.reason, False, res, dec, r2, risk_budget=budget, risk_base=base)
        if not dec.allow:
            out.status = 'GATE_BLOCKED'
            return out
        if res.reason.startswith('PRE_SEND_RESERVATION_FAILED'):
            out.status = 'RESERVATION_FAILED'                # nothing was placed and the signal is NOT consumed
            return out
        if res.final in (en.R_PLACED, en.R_FILLED):
            out.request = True
            out.label = FAKE_LABEL
            self.signals += 1
        if res.final in HANDLED_FINALS:
            self.handled.append(r2.signal_id)
        if res.final in HALT_FINALS:
            self.halted = 'HALTED after %s: restart and reconcile first' % res.final
        return out


