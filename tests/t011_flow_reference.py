"""T011 restart flow: LOAD -> identity check -> snapshot -> ER_Reconcile -> SAVE (Python mirror of src/include/ExitRestartFlow.mqh).

ONE FLOW, NO NEW STATE MACHINE, NO COPIED VALIDATION: it composes the existing pieces - the persistence file layer / codec (t011_persist_reference: FileStore.load,
.save, restore verdicts and the record validation), the read-only snapshot adapter (t011_adapter_reference.build) and the reconciliation (t011_reconcile_reference.reconcile).
It sends no order, produces no request in any path, retries nothing and never invents an order map.

ORDER OF THE GATES (each stops the flow; nothing after it runs):
  1 LOAD            an unusable record (missing, damaged, truncated, other version, other identity [the identity check is part of the restore], leftover temp file, invalid
                    combination)                                   -> RECOVERY_REQUIRED "LOAD_UNUSABLE: ..."; the file is NOT written; no snapshot is read.
  2 state           stored BLOCKED -> BLOCKED (no read, no write); stored IDLE -> NOTHING_TO_RECONCILE (no read, no write, never a request).
  3 order map       a request-bearing record WITHOUT order tickets (an uncertain send, or DONE without a map) -> RECOVERY_REQUIRED "NO_MAP"; no snapshot is read; not written.
  4 snapshot        only a READY adapter verdict may reach the reconciliation. UNKNOWN -> STILL_OPEN (reason kept); BLOCK -> BLOCKED outcome without calling the reconciliation. The
                    file is never trusted as proof of execution: DONE can only come from the existing reconciliation (CONFIRMED needs executions_complete).
  5 reconcile       ER_Reconcile on the restored state (the same SEaState); the decision is reported.
  6 SAVE            only when the reconciled state differs from the loaded one: generation + 1, send phase MAPPED, the same order map. If the save fails (or the new state cannot be
                    encoded) -> RECOVERY_REQUIRED, persisted False, and the state returned to the caller is the one that IS on disk (not the unsaved reconciled one).
LIMITS: the flow is not atomic with the broker nor guaranteed atomic on disk (see tasks/T011-exit-persistence.md); a crash after the reconciliation and before the save repeats the
reconciliation on the next run (it is idempotent: confirmations stay 1); the live terminal read of the adapter is UNVERIFIED and is exercised only through fixtures.
"""
import copy
from dataclasses import dataclass, field

import t011_activation_reference as act
import t011_adapter_reference as ad
import t011_persist_reference as p
import t011_reconcile_reference as rec

DONE, STILL_OPEN, BLOCKED, RECOVERY_REQUIRED, NOTHING = 'DONE', 'STILL_OPEN', 'BLOCKED', 'RECOVERY_REQUIRED', 'NOTHING_TO_RECONCILE'


@dataclass
class FlowResult:
    final: str
    reason: str = ''
    snapshot_called: bool = False
    reconcile_called: bool = False
    save_needed: bool = False
    saved: bool = False
    decision: str = ''
    adapter_verdict: str = ''
    state: act.State = field(default_factory=act.State)       # the state that is safe to use: reconciled and saved, or the one on disk
    generation: int = 0                                         # the generation on disk after the flow
    request_produced: bool = False                              # always False: no path produces a request


def _rec(o, generation, identity, st):
    """the record of a request-bearing state with its order map AND the authorised plan carried over unchanged from the restore"""
    return p.Record(generation, identity, st, p.SEND_MAPPED, bool(o.map_complete), list(o.orders), o.plan_set, o.plan_tp, o.plan_vol_min, o.plan_vol_step, o.plan_vol_max,
                    o.plan_rpol, o.plan_e_src, o.plan_s_src, o.plan_e_out, o.plan_s_out)


def run(store, name, identity, raw_a=None, raw_b=None, fail_save=False):
    out = FlowResult(RECOVERY_REQUIRED)
    o = store.load(name, identity)
    out.state = o.state
    out.generation = o.generation
    if o.generation == 0:
        out.reason = 'LOAD_UNUSABLE: ' + o.reason
        return out
    st = o.state
    if o.verdict == p.USABLE_BLOCKED:
        out.final, out.reason = BLOCKED, 'BLOCKED restored as stored; nothing is read or written'
        return out
    if o.verdict == p.USABLE_IDLE:
        out.final, out.reason = NOTHING, 'IDLE: there is no request to reconcile; no request is produced here'
        return out
    if not o.orders:
        out.reason = 'NO_MAP: the record holds no order ticket; the snapshot is not read and no map is invented. ' + o.reason
        return out
    mp = ad.Map(st.request_id, st.position_id, identity.symbol, list(o.orders), bool(o.map_complete))
    raw_b = raw_a if raw_b is None else raw_b
    out.snapshot_called = True
    res = ad.build(st, mp, raw_a, ad.raw_equal(raw_a, raw_b))
    out.adapter_verdict = res.verdict
    if res.verdict == ad.UNKNOWN:
        out.final, out.reason = STILL_OPEN, 'SNAPSHOT_UNKNOWN: ' + res.reason
        return out
    if res.verdict == ad.BLOCK:
        out.final, out.reason = BLOCKED, 'SNAPSHOT_BLOCK: ' + res.reason
        return out
    disk = copy.deepcopy(st)
    before_ok, before_text = p.encode(_rec(o, o.generation, identity, st))
    outcome = rec.reconcile(st, res.snapshot)
    out.reconcile_called = True
    out.decision = outcome.decision
    if outcome.decision == 'INVALID_INPUT':
        out.state = disk
        out.reason = 'RECONCILE_INVALID_INPUT: ' + outcome.reason
        return out
    after_ok, after_text = p.encode(_rec(o, o.generation, identity, st))
    out.save_needed = not (before_ok and after_ok and before_text == after_text)
    if out.save_needed:
        if not after_ok:
            out.state, out.reason = disk, 'SAVE_FAILED: the reconciled state cannot be encoded (' + after_text + '); it was NOT persisted'
            return out
        if fail_save:
            ok, why = False, 'TEST_SAVE_FAILURE'
        else:
            ok, why = store.save(name, _rec(o, o.generation + 1, identity, st))
        if not ok:
            out.state, out.reason = disk, 'SAVE_FAILED: ' + why + '; the reconciled state was NOT persisted'
            return out
        out.saved = True
        out.generation = o.generation + 1
    out.state = st
    out.final = DONE if st.status == act.DONE else (BLOCKED if st.status == act.BLOCKED else STILL_OPEN)
    out.reason = 'RECONCILED: ' + outcome.decision + (' ' + outcome.reason if outcome.reason else '')
    return out
