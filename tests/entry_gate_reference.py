"""T015 ENTRY GATE (Python mirror of src/include/EntryGate.mqh): the ONE place where a T014 plan, the existing checks and the entry executor meet. PURE decision + a thin submit.

  plan (T014, plan_ready) + T007 permit data (TP_CheckPermit: data, session, news, spread, exposure, limits, duplicates) + the broker loss check (PB_CheckLoss) + the T012 daily result
  -> ONE decision. Only when EVERY check allows, an executor permit (SEnPermit) is built FOR THAT PLAN (canonical digest) and stamped with the decision time. Any block builds no permit and the
  executor is not called: no intent, no lock, no Send, no signal registered.

It copies no rule: the permit is t007 check_permit (never authorize, so nothing is registered), the loss check is t008 check, the daily result is the T012 bridge result. In THIS path a daily result that
is missing, not evaluated, not called or not allowing BLOCKS; the preview's MANUAL exception (daily not evaluated = no condition) is never used. The T007 allow alone never reaches the executor.
Every check input carries the plan digest it was computed for and the instant it was observed: another plan, a future instant or an instant older than max_age BLOCKS. max_age <= 0 is UNSET = BLOCK.
The durable duplicate guard stays in the entry executor (one record per signal); this module has no state of its own."""
from dataclasses import dataclass, field, replace

import entry_reference as en
import t007_planning_reference as tp
import t008_broker_loss as bl
import t012_bridge_reference as br


@dataclass
class GateConfig:
    max_age: int = -1                      # seconds a check may be old; <= 0 = UNSET = BLOCK


@dataclass
class Checks:
    snapshot: tp.Snapshot = None
    snapshot_time: int = 0
    snapshot_digest: str = ''
    limits: tp.Limits = None
    registry: tp.Registry = None           # read only: the gate never registers a signal
    calc_ok: bool = False
    profit: float = 0.0
    tolerance: float = -1.0
    risk_budget: float = -1.0
    loss_time: int = 0
    loss_digest: str = ''
    daily_present: bool = False
    daily: br.Result = None
    daily_time: int = 0
    daily_digest: str = ''


@dataclass
class Decision:
    allow: bool = False
    reasons: list = field(default_factory=list)
    permit: en.Permit = field(default_factory=en.Permit)
    loss_check: str = ''


def entry_plan(plan):
    """the executor takes the signed direction of the MQL plan"""
    return replace(plan, direction=1 if plan.direction == 'BUY' else -1)


def _fresh(name, t, digest, want, now, max_age, reasons):
    if not 0 < t <= now:
        reasons.append('%s_TIME_INVALID' % name)
    elif now - t > max_age:
        reasons.append('%s_STALE' % name)
    if digest != want:
        reasons.append('%s_FOR_ANOTHER_PLAN' % name)


def decide(gcfg, spb, checks, now):
    d = Decision()
    if not gcfg.max_age > 0:
        d.reasons = ['INPUT_UNSET: gate_max_age']
        return d
    if not spb.plan_ready or spb.plan is None:
        d.reasons = ['PLAN_NOT_READY: ' + spb.reason]
        return d
    plan = entry_plan(spb.plan)
    digest = en.plan_digest(plan)
    if digest == '':
        d.reasons = ['PLAN_INVALID']
        return d
    if not now > 0:
        d.reasons = ['NOW_UNSET']
        return d
    r = d.reasons
    _fresh('SNAPSHOT', checks.snapshot_time, checks.snapshot_digest, digest, now, gcfg.max_age, r)
    _fresh('LOSS_CHECK', checks.loss_time, checks.loss_digest, digest, now, gcfg.max_age, r)
    _fresh('DAILY', checks.daily_time, checks.daily_digest, digest, now, gcfg.max_age, r)
    d.loss_check = bl.check(checks.calc_ok, checks.profit, spb.plan.risk_model, checks.risk_budget, checks.tolerance)
    guarded = spb.plan
    if d.loss_check != 'OK':
        r.append('BROKER_LOSS_CHECK:' + d.loss_check)
    else:
        guarded = replace(spb.plan, risk_model=bl.permit_risk(checks.profit, spb.plan.risk_model))
    if checks.snapshot is None or checks.limits is None or checks.registry is None:
        r.append('PERMIT_INPUT_MISSING')
        tpermit = None
    else:
        tpermit = tp.check_permit(guarded, checks.snapshot, checks.limits, checks.registry)
        if tpermit.decision != tp.ALLOW:
            r.extend('PERMIT:' + x for x in tpermit.reasons)
    if not checks.daily_present or checks.daily is None:
        r.append('DAILY_NOT_EVALUATED')
    elif not checks.daily.dl_called:
        r.append('DAILY_NOT_CALLED: ' + checks.daily.primary)
    elif not checks.daily.entry_allowed:
        r.append('DAILY_BLOCK: ' + checks.daily.primary)
    if r:
        return d
    d.allow = True
    d.permit = en.permit_from(plan, tpermit, now)
    return d


def submit(gcfg, cfg, tr, store, rt, spb, checks):
    """-> (executor result, decision). A block never reaches the executor."""
    now = tr.server_time()
    dec = decide(gcfg, spb, checks, now)
    if not dec.allow:
        return en.Result(en.R_REFUSED, 'GATE_BLOCKED: ' + ' | '.join(dec.reasons)), dec
    return en.place(cfg, tr, store, rt, entry_plan(spb.plan), dec.permit), dec
