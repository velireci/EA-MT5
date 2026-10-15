# T011 executor contract (minimal)

Corrected after a70fde6 (see section 9): a failed save is never proof that the old file is still on disk; every uncertainty is RECOVERY_REQUIRED; no rejection class exists until the return-code table is verified.

Base 377643f. Evidence relayed (not my runs): Codex Python 11/0 and MetaEditor 0/0; owner MT5 T011_FlowTest 261 passed / 0 failed; the diagnostic showed SAVE failure -> RECOVERY_REQUIRED,
a saved DONE, and a repeat with one confirmation. These are FIXTURE runs of the flow: no broker execution, no trading-EA restart. This file defines what the still-unbuilt executor must do
with the existing modules (ExitSplit, ExitActivation, ExitReconciliation, ExitSnapshotAdapter, ExitStateCodec/File, ExitRestartFlow); it changes none of them and chooses no strategy policy.
Terminal trading API facts below (OrderSend structure, return codes, hedging `position` field) are from memory and UNVERIFIED: the official MQL5 documentation could not be opened from the build
environment; Codex / the owner must check them before the executor is written.

## 1. Where the single request comes from
`EA_OnQuote(state, position_id, direction, level_2R, bid, ask, volume_initial, volume_current, volume_min, volume_step, volume_max, result)` is the ONLY producer. It returns true once, on the quote that
moves the state IDLE -> REQUEST_PENDING, with `action = REQUEST_PARTIAL_CLOSE`, `request_id = "X2R80-<position identifier>"`, `request_volume` (80% of the INITIAL volume on the volume grid) and
`request_steps`. Preconditions it enforces (the executor must not duplicate them, only honour the answer): valid inputs; volume parameters valid on every quote (`ES_Split`); the first valid quote binds
position, direction, level and initial volume (a later change -> BLOCKED); BUY reaches 2R when Bid >= level, SELL when Ask <= level (technical convention, not a client rule); current volume must equal the
initial volume in steps (else NEEDS_RECONCILIATION); `SPLIT_POLICY_UNSET` when 80/20 is not exactly realisable (no request). Any other state (PENDING, DONE, NEEDS_RECONCILIATION, BLOCKED) never
produces a request. `ExitRestartFlow`, `ExitStateCodec` and the adapter never call `EA_OnQuote`.

## 2. What is stored BEFORE sending (persist-before-send)
Per position, one file `ESF_FileName(login, position_id)` (`ExitStateFile`):
1. At the moment the executor opens/registers a position it owns: `ESF_InitFresh` (IDLE, generation 1, identity = server, login, symbol, position identifier). A missing file later is RECOVERY_REQUIRED, never "start over".
2. When `EA_OnQuote` returns the request: build the record = the whole `SEaState` (REQUEST_PENDING, request id, plan, step, level, initial volume, confirmations 0), send phase INTENT, no order tickets,
   generation + 1; `ESF_Save` MUST return true (temp file, read-back, move, read-back). If it returns false -> do NOT send; the state stays blocked for this position (RECOVERY_REQUIRED path).
3. Only after step 2 may the single trading call be made. Level / volume values are passed normalised to the symbol (the codec refuses values not exact with 12 decimals; the activation compares with `==`).

## 3. Linking request id, position identifier, order ticket and deal tickets
`request_id` exists in no MT5 field and is never matched to a comment, magic or volume. The chain is (adapter header): `request_id` --(map written by the executor, `SXaMap`)--> order ticket(s)
--`DEAL_ORDER`--> exit deals --`DEAL_POSITION_ID`--> position identifier. The position is found by POSITION_IDENTIFIER; the position TICKET (needed in a hedging close request) is a different number and is
read at send time (the adapter fixtures use ticket 9 for identifier 7 on purpose). Deals are de-duplicated by deal ticket; only exit deals (not IN/INOUT/OUT_BY) of a mapped order on the same position and
direction count; a deal of another position, or a same-side exit, is UNKNOWN / BLOCK. The executor stores ONLY order tickets (<= 8, distinct, positive) and the flag `orders_complete`; deal tickets are never
stored (they are re-derived from the history on every reconciliation).

## 4. The uncertain response (no resend, ever)
The executor makes ONE trading call per request and never repeats it (no retry loop, no second request, no "fix-up" order).
* Result with an accepted order ticket (the terminal returned an order number): go to section 5.
* Rejection with a definitive code (nothing was created): persist, then `EA_OnReport(REJECTED)` -> NEEDS_RECONCILIATION (no automatic retry exists); reconciliation with the broker decides.
* Timeout, lost connection, no result, order ticket 0/unknown, process death after the call: the record on disk is PENDING + INTENT without a map. On restart `ESC_Restore` returns RECOVERY_REQUIRED
  (state NEEDS_RECONCILIATION, "SEND_UNCERTAIN"); `ERF_Run` stops at NO_MAP before any terminal read. NO map is invented and the order is NOT searched by comment / magic / volume, because the existing
  identity chain does not accept those as proof. Resolution is manual (owner) until a separately verified discovery rule is agreed (open decision, section 8).
* A synchronous "filled" result is a HINT only: the executor does not call `EA_OnReport(FULL)` to reach DONE (that path accepts a report without broker evidence). DONE comes from `ER_Reconcile` on a READY
  snapshot through `ERF_Run` (CONFIRMED needs `executions_complete`). This is a recommendation for review; the activation module itself would still accept a FULL report.

## 5. After the response: the map, and how ExitRestartFlow starts
1. Save PENDING + MAPPED: same state, send phase MAPPED, the order ticket(s), `orders_complete = true` only if the executor asserts that this one request created exactly the recorded order(s) and that no
   other order was ever sent for it; generation + 1. If this save fails, the record stays INTENT-without-map (uncertain send) - the safe direction.
2. Activation of `ExitRestartFlow::ERF_Run(file, identity, input, result)`: (a) at every start / re-attach of the executor, for each registered position, BEFORE any quote handling; (b) after each
   accepted request, repeatedly (throttled, e.g. on trade events or a timer) until the result is DONE or BLOCKED. `EA_OnQuote` is allowed only for a position whose load is `USABLE_IDLE`.
   Results: DONE -> stop; STILL_OPEN -> wait/repeat (never resend); BLOCKED / RECOVERY_REQUIRED -> stop and report to the owner; NOTHING_TO_RECONCILE -> only IDLE.
3. Every state change (`EA_OnReport`, `ER_Reconcile`) is saved before it is acted on; a failed save is RECOVERY_REQUIRED and the caller uses the state that is on disk.

## 6. What blocks the executor (it must not send)
| Condition | Source today | Executor behaviour |
|---|---|---|
| 80/20 not exactly realisable (initial steps not a multiple of 5, or remainder below the minimum volume) | `ES_Split` -> SPLIT_POLICY_UNSET | no request; no rounding, no full close, no skip is invented |
| Final TP equal to the 2R level (or the 2R level not strictly before TP) | not detected by any module (the spec leaves the interaction open) | arm no partial close until a rule exists (TP_EQUALS_2R_POLICY_UNSET); the detection itself is technical |
| Ownership / identity unproven | record identity; position opening magic == the executor's explicit magic (> 0); symbol; registered by the executor at open | never act on a position without a matching record, a manual / other-EA position, magic 0, or another account / server |
| Netting or exchange account | adapter BLOCK (hedging only); `DH`/adapter margin-mode read | check the margin mode again at send time; block otherwise |
| Volume changed (current != initial steps, step / min / max changed) | `EA_OnQuote` (VOLUME_MISMATCH_BEFORE_REQUEST, STEP_CHANGED, SPLIT_INVALID) | live symbol parameters read at send time must equal the persisted plan; otherwise no send |
| State not persisted | `ESF_Save` false / `ESF_Load` unusable / leftover temp file | no send; RECOVERY_REQUIRED |
| Uncertain earlier send, DONE without map, stored BLOCKED | restore + flow gates | no send, no reconciliation without a map |
| Trading not allowed now (account / symbol / terminal trade permission, market closed) | not covered by any module | a broker-constraint check before the call (technical, section 7) |

## 7. Technical work (implementable now, no client decision needed)
* The executor module itself: init / register, quote loop, persist-before-send, the single trading call, response classification, order-ticket map save, scheduling `ERF_Run`, startup recovery.
* A read-only pre-send check set: margin mode, symbol trade mode, volume min / step / max against the persisted plan, position found by identifier with magic / symbol / direction / volume, trading permissions.
* Position ticket lookup from the identifier for the hedging close request; normalisation of level and volume to the symbol.
* A demo-only test plan: PREPARE-style synthetic checks first, then one real partial close on a demo position with the owner present; logs of the return code, order ticket, deals and the flow result.
* Verification of the terminal trading API facts against the official documentation (unavailable here) before writing the call.

## 8. Decisions that are NOT technical (client / owner)
1. What to do when 80/20 is not realisable on the grid (SPLIT_POLICY_UNSET): round, close another share, close all, or skip.
2. The interaction when the final TP equals 2R, and the treatment of the remainder (spec section 7, open H).
3. How an uncertain send is resolved and whether a verified discovery rule (for example by order history) may ever link an order to a request.
4. Execution parameters of the close: order type, deviation (slippage), filling type, behaviour when the price is beyond the level at send time; whether spread / news / session filters apply to an exit.
5. Ownership model for existing positions (magic reuse, positions opened before the executor, manual intervention) and who may clear a RECOVERY_REQUIRED.
6. Cost / +0.2% / breakeven handling and the move of the stop-loss after the partial close (not part of this contract; not built; STILL OPEN). DECIDED (2026-10-15, owner message): the remainder runs to its TP/SL with no trailing.

## 9. Corrections (executor stage, base a70fde6)
* SAVE = false does NOT prove the old file stayed on disk: the move may have happened and the read-back may have failed. The executor therefore treats ANY save failure (INTENT or MAP) as RECOVERY_REQUIRED,
  latches the position in memory, sends nothing (or nothing more) and relies on the next `ESF_Load` after a restart. After a successful INTENT save it re-loads the file independently and requires
  exactly generation + 1, PENDING + INTENT, no map; anything else is RECOVERY_REQUIRED and nothing is sent.
* Section 4 is replaced: there is no "definitive rejection" class. Only an ACCEPTED answer (the call returned true AND a result exists AND retcode is 10008 / 10009 / 10010 AND an order ticket > 0) maps an order;
  every other answer, including a clear-looking reject code, leaves the intent on disk and is RECOVERY_REQUIRED without retry. A rejection table may be added only after the return codes are verified.
* Returned true is not a fill proof; a fill is proven only by the reconciliation. The executor never calls `EA_OnReport(FULL)`.
* Implemented (detached, DISABLED by default, fake transport in tests, real transport never executed): `ExitExecutor.mqh`, `ExitTransport.mqh`, `ExitTransportFake.mqh`, `ExitTransportReal.mqh`. Open points: docs/T011-executor-api-verification.md.

## 10. The authorised plan (executor stage, base 129a267)
Gap closed: a change of the plan or of the volume parameters between the registration of a position and the 2R quote could pass undetected, because nothing but the bound direction / level / initial volume was stored.
* What was already stored (not duplicated): the bound `SEaState` of an IDLE record holds direction, level 2R and initial volume (and the position id). What was missing, and is now stored: TP and the symbol volume minimum / step / maximum.
* Codec change (necessary): record format VERSION 2 adds `PLAN_SET`, `PLAN_TP`, `PLAN_VOL_MIN`, `PLAN_VOL_STEP`, `PLAN_VOL_MAX` before the order map. Validation: a plan needs a bound state, positive values, min <= max, exact 12-decimal values, and for a request-bearing state the request step must equal the plan step.
  `ExitRestartFlow` carries the plan over unchanged when it saves. A VERSION 1 record has no plan: it is rejected as UNSUPPORTED_VERSION (RECOVERY_REQUIRED) and is NEVER migrated or completed from the current inputs; an IDLE record of version 2 without a plan is PLAN_MISSING (RECOVERY_REQUIRED).
* Registration (`EX_Register`, explicit, never automatic): requires the executor enabled, the position found by identifier with magic == the configured magic (> 0), the same symbol and direction, a volume equal to the plan's initial volume, level and TP exactly on the tick grid and
  exactly representable in the record, TP beyond 2R, a realisable 80/20 split (`ES_Split`), HEDGING, the real-transport authorisation and a DEMO account when the transport is real; it never overwrites an existing file or temporary file, never rounds, saves generation 1 and re-loads it to verify.
  A manual or foreign position (magic 0 or another magic) is never adopted. Without a file the executor never starts from scratch: `EX_Process` returns RECOVERY_REQUIRED (LOAD_UNUSABLE: MISSING).
* Before every request `EX_Process` compares direction, level 2R, initial volume, TP and the live volume min / step / max with the stored plan (exact equality). A difference is BLOCKED ("PLAN_CHANGED: <field>") with zero sends and NO new INTENT; a missing plan is RECOVERY_REQUIRED.
* Not changed: exit policies, the activation / reconciliation modules, the strategy.
* Ownership proof remains the magic number plus the registration by the executor; a magic collision with another instance or script cannot be detected.
