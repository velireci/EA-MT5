# T011 exit manager: the executor wired to the quote loop (R_GEOM, disabled by default)

Status: written and tested ONLY with the fake transport (Python sandbox). MetaEditor compile and every MT5 run are UNVERIFIED. The real transport has never been run through this path.
This is wiring, not a new state machine: the only state is the record on disk (ExitStateCodec / ExitActivation / ExitReconciliation), every request still comes from `EX_Process` -> `EA_OnQuote`.

## Files
| file | role |
|---|---|
| `src/XauUsdT011ExitRegister.mq5` | script: the EXPLICIT registration of ONE owned position. The only way to create the state file. Sends nothing |
| `src/XauUsdT011ExitManager.mq5` | EA: OnInit recovery, OnTick at the level, OnTimer reconcile. Never registers, never opens/adopts/modifies a position, no signal |
| `src/include/ExitTickDriver.mqh` | the thin wiring (`ETD_Register`, `ETD_Init`, `ETD_Tick`, `ETD_Timer`); no trading call, no file access, no state of its own |
| `src/include/ExitExecutor.mqh` | `EX_Geometry` (the only place that calls `TG_Compute`), `EX_PlanRefusal`, R policy, the R_GEOM branch of `EX_Register` / `EX_Process` |
| `src/include/ExitStateCodec.mqh` | record VERSION 3: `PLAN_RPOL`, `PLAN_E_SRC`, `PLAN_S_SRC`, `PLAN_E_OUT`, `PLAN_S_OUT` (R itself is NOT stored) |

## The two decisions (owner, 2026-10-15) and what they mean in code
* D1 - `InpRPolicy` (UNSET blocks everywhere). The only value implemented is `R_GEOM`: R = the price distance between the open price of the position (read once at registration) and the INITIAL stop. It does NOT settle the client's final R or the costs (spread, commission, slippage are not modelled; items C3/C4 stay open). The typed diagnostic level of the demo harness is a separate internal policy and is not selectable in the new entry points.
* D2 - variant (a): the initial SL is asserted by the owner (`InpInitialSl`) and registration accepts it only while the live SL of the position still equals it. If the SL was already moved (or is absent) registration is refused: the initial SL is unproven. No history corroboration is implemented.

## How the level is derived and protected
1. Registration: `TG_Compute(direction, E = POSITION_PRICE_OPEN, S = asserted SL, target = TP)` gives the normalized E and S and `level_2r`. Refused when: the policy is UNSET, the SL is not asserted, the live SL differs, E or S is off the symbol tick grid, the geometry status is not OK (wrong side, zero risk, incompatible tick/digits), the normalization would change the declared basis, TP is equal to or before 2R, the position is not owned (magic, symbol, direction), the volume differs, the 80/20 split is not realisable, or a file already exists.
2. Stored BEFORE any activation: source E and S, the normalized E and S (they must agree within floating-point noise), the level (in the state), TP and volume min/step/max.
3. Every request: the level is re-derived from the STORED E and S and compared with the stored level; the configured initial SL, TP, initial volume and the symbol volume parameters are compared with the stored plan. Any difference or absence -> BLOCKED / RECOVERY_REQUIRED, zero sends, no new INTENT. The live SL of the position and the quote's level input are never used. Moving the SL to break-even later changes nothing.
4. Condition (unchanged, in `EA_OnQuote`): BUY Bid >= level, SELL Ask <= level.

## Entry points
* OnInit: gates (enabled, phrase, confirm flag, policy, direction BUY/SELL, magic, position id, symbol, SL/TP/volume) -> `ETD_Init`: lock -> load; a missing, unusable or older-version file arms nothing and is never created or changed; a request-bearing record goes through the EXISTING restart flow FIRST and never arms the tick path; only an IDLE R_GEOM record arms it.
* OnTick: below the level -> no lock, no file, no terminal read. At the level -> lock -> re-load; a record that is not IDLE is NOT given to `EX_Process` -> `EX_Process`. After a send, an uncertainty or a latch the tick path is disarmed.
* OnTimer (only while a record waits for the history): lock -> existing reconciliation (read + the flow's own save); never a request.
* ONE lock (`VELO_T011_LOCK_<login>_<position>`, per terminal only) for init, tick, timer and registration; any lock failure means zero sends and no I/O.

## Owner steps (after the Codex review and the MT5 runs of T011_GeomTest and T011_DriverTest)
1. Demo account, one terminal. The position must already exist and be owned (magic of the robot); nothing here opens one.
2. Load `XauUsdT011ExitRegister.set`; fill `InpPositionId`, `InpInitialSl` (= the current SL of the position), `InpTpPrice` (beyond 2R), `InpVolumeInitial`, `InpDirection`; set `InpRPolicy = 2`, `InpEnabled = true`, type `I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE`. Run once; read the RESULT line (the registration re-loads the file independently).
3. Load `XauUsdT011ExitManager.set` with the SAME plan values plus filling, deviation and the exit-filter policy; `InpRPolicy = 2`, `InpEnabled = true`, phrase, `InpConfirmAutoSend = true`. Read the INIT line: `armed 1`, direction and the derived level. Anything else: nothing is armed.
4. Never remove the state file by hand while a request exists; a stale lock is cleared by a terminal restart.

## Limits (do not overstate)
* Terminal-API semantics, the lock behaviour and every MQL5 file are UNVERIFIED until compiled (Codex) and run (owner). No real run of this path exists.
* R_GEOM is not the final client R; no BE, no +0.2%, no trailing here (the remainder runs to its TP/SL, decided), `SPLIT_POLICY_UNSET` and TP == 2R still block.
* The lock protects one terminal only; manual actions of the owner are not prevented.
* Files created by earlier versions (VERSION 1/2) are refused for the configured file only: they are never changed, migrated or deleted by this code.
