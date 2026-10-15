# T011 demo package: one controlled partial close on a DEMO account

Status: code, tests and presets written; **nothing was compiled or run by the author, and the real transport was never executed**. Codex reviews and compiles first; only then does the owner authorise and perform the demo test.
Relayed evidence (not my runs) at 0356f39: owner MT5 Persist 395/0, Flow 261/0, Executor 750/0; Codex Python 21/0, Persist/Flow compile 0/0, Executor compile with one unused-variable warning in the test (removed in this package).

## What is in the package
| File | Role |
|---|---|
| `src/include/DemoHarness.mqh` | harness core `DM_Run` (steps NONE / STATUS / REGISTER / ACTIVATE / RECONCILE) over `ExitExecutor.mqh`; no transport, no trading call, no deletion |
| `src/XauUsdT011DemoHarness.mq5` | the script: inputs, live quote, the REAL transport (only here and in the compile stub); **disabled by default (`InpStep = NONE`)** |
| `src/include/ExitInstanceLock.mqh` | instance lock (temporary terminal global variable) |
| `src/include/DemoOpenGuard.mqh`, `src/tests/T011_DemoOpenGuardTest.mq5` | the locked decision sequence of the open-position step (lock → intent → position → order → pre-check → intent write → ONE send) behind a small port, and its fake-port test (not general infrastructure) |
| `src/XauUsdT011DemoOpenPosition.mq5` | **separate, disabled** demo-only step that opens ONE owned test position (explicit volume, SL/TP distances, magic); the only `OrderSend` besides the real transport |
| `src/tests/T011_DemoHarnessTest.mq5` | MQL5 test, FAKE transport only (also exercises the lock) |
| `tests/t011_demo_reference.py`, `tests/test_t011_demo.py` | Python mirror and tests; `tools/t011-demo-static-checks.sh` static checks |
| `src/presets/XauUsdT011Demo_01_status.set` ... `_04_reconcile.set`, `XauUsdT011DemoOpenPosition.set` | complete presets (every input listed once) |
Also: the unused variable of `T011_ExecutorTest.mq5` was removed (Codex warning) and a static check now rejects a declared-but-unused local in that test.

## Gates (nothing acts unless ALL hold)
* Harness `InpStep` is not NONE; for REGISTER / ACTIVATE / RECONCILE the instance lock is free. A real transport additionally needs `InpAuthorisation = I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE` AND a DEMO account (enforced in `ExitExecutor.mqh` before any trading call), HEDGING, trading allowed, the same login / server as the record.
* ACTIVATE (the only step that can send) also needs `InpConfirmSendOnce = true`, a quote, a REGISTERED plan, an IDLE record, the position found by identifier with magic == `InpEaMagic` (> 0), and every mandatory parameter: filling, deviation, exit-filter policy, level, TP, volume. **UNSET always means BLOCK.**
* The unknown policies stay unknown: `InpFilling`, `InpDeviation`, `InpFilterPolicy`, `InpFilterState` are DIAGNOSTIC TEST PARAMETERS chosen for this one test (the presets use IOC, 20 points, "exits ignore filters", filters CLEAR); they are not strategy rules and are not defaults of the project.
* The test plan avoids the open decisions: volume 0.10 (10 steps: 8 close / 2 remain, realisable, remainder above the minimum), TP strictly beyond the level (never TP == level), BUY.
* No H4 / M15 signal, no live trading, no strategy code anywhere in the package.

## Isolation: what the lock does and does NOT do
* It stops two instances (two scripts, or a script and another script) on the **same terminal** from acting on the same account + position at the same time (`VELO_T011_LOCK_<login>_<position>`; the open-position step uses its own key per account + magic).
* It does **NOT** protect between different terminals (even on the same account or computer): each terminal has its own global variables and its own `MQL5/Files` folder. Run ONE terminal against the demo account for this test.
* A script that dies without releasing leaves the lock held until the terminal restarts (a temporary variable) or the owner resets it by hand: that blocks, which is the safe direction. Nothing deletes it automatically.
* It does not stop a manual action of the owner in the terminal, and it does not protect a record restored from a backup.

## API verification (what waited for Codex)
RELAYED 2026-10-15 (owner/Codex, details not seen by me): Codex has read the official OrderSend and MqlTradeRequest pages. Status below: from my side the pages stay unread and the item list is the checklist Codex compared; I do not know which items were confirmed beyond that statement. The real demo cycle (owner-relayed) behaved consistently with the list. MT5 lock tests passed (relayed, no counts given); that does NOT yet prove two real competing instances. The text below is the historical record of what I could and could not read.
The official pages could not be opened from the build environment (proxy 403 / host not resolvable), also this time: `https://www.mql5.com/en/docs/trading/ordersend`, `.../constants/structures/mqltraderequest`, `.../globals/globalvariablesetoncondition`. Only search snippets were seen: OrderSend returning true is not a fill proof (Codex's reading of the documentation confirms it);
GlobalVariableSetOnCondition is atomic within one terminal and fails without creating the variable when it is missing. **Codex must verify before any demo run:** the OrderSend / MqlTradeRequest / MqlTradeResult fields used (`action`, `symbol`, `volume`, `type`, `position` = the current position TICKET on a hedging account, `magic`, `deviation`, `type_filling`, `price`, `sl`, `tp`, `comment`);
the retcodes 10008 / 10009 / 10010 and the meaning of `MqlTradeResult.order` for a market deal; `OrderCheck` success (`retcode == 0` assumed, DONE also accepted); `GlobalVariableTemp` (initial value 0 assumed) with `GlobalVariableSetOnCondition(key, 1, 0)`; the constants `ACCOUNT_TRADE_MODE_DEMO`, `ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`,
`SYMBOL_TRADE_MODE_*`, `ORDER_FILLING_*`; that `PositionGetTicket(i)` selects the position for the following `PositionGet*` calls; `SymbolInfoTick`.

## Exact steps (after Codex's review and compile)
0. One terminal, a DEMO account, AutoTrading allowed for scripts. Compile everything. Run `T011_DemoHarnessTest`, `T011_ExecutorTest`, `T011_FlowTest`, `T011_PersistTest` (fake transport; all must report 0 failed). Run `T011_ExecutorRealCompile` only to see that it compiles (it calls nothing).
1. **Open the owned test position (separate authorisation).** Load `XauUsdT011DemoOpenPosition.set` on an XAUUSD chart, set `InpEnabled = true`, type `I_AUTHORISE_T011_DEMO_OPEN_POSITION` in `InpAuthorisation`, run once. It sends ONE request (volume 0.10, SL 5.00 and TP 10.00 distances) and prints the `POSITION_IDENTIFIER`, open price, SL, TP. If it prints UNCERTAIN, stop. Inside the instance lock the script checks, in this order: no open-intent file, no position and no pending order of this magic on the symbol; only then OrderCheck, then it writes and reads back the **open-intent file** `MQL5/Files/VELO_T011_DEMO_OPEN_INTENT_<login>_<magic>.txt`, then sends ONE request. The intent file is **never removed by any code**: while it exists every later run is blocked (also after a restart and also when no position is visible yet, because an uncertain answer does not prove the request was refused). **Explicit reconciliation (owner, by hand):** look at the terminal's positions, orders and history for this magic; if the request produced nothing and you accept a new test, delete that one file yourself and only then run the script again; if it produced a position, keep the file and continue with the harness. A direction other than exactly BUY or SELL is refused. The lock protects one terminal only.
2. **STATUS.** Load `XauUsdT011Demo_01_status.set`, set `InpPositionId` to the printed identifier, run: it prints the quote, the tick size and "MISSING" for the record. Choose the diagnostic level: a price ON the tick grid at or just below the BUY bid (so that the activation is reached at once), e.g. the bid itself rounded down to the tick. Write it into `InpLevel2R`; put the position's TP into `InpTpPrice` (strictly above the level); `InpVolumeInitial = 0.10`.
3. **REGISTER.** Load `..._02_register.set` with the same filled values, run: expected `REGISTERED`, STATUS then shows `plan_set 1`, state IDLE, generation 1. A manual position or a different magic is refused.
4. **ACTIVATE (one partial close).** Load `..._03_activate.set` with the same values, type `I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE`, set `InpConfirmSendOnce = true`, run once. Expected: `SENT_MAPPED`, sends 1 (a closing deal of 0.08 on the position; 0.02 remains), the log shows the order ticket. If the status is `RECOVERY_REQUIRED` (an uncertain answer) STOP: do not run again, send the log lines; nothing is retried.
5. **Re-run without a second request.** Run step 4 again unchanged: expected `NOT_IDLE`, sends 0 (check the terminal history: still one closing deal).
6. **Reconcile.** Load `..._04_reconcile.set` with the same values, run: expected `DONE` once the history shows the fill (otherwise `STILL_OPEN`: wait and re-run; never re-send). Run it again: `DONE`, unchanged, confirmations 1.
7. **Restart.** Close MT5 completely and reopen it, log in to the same account, run STATUS (record restored, state DONE, confirmations 1, plan stored) and ACTIVATE again (`NOT_IDLE`, sends 0).
8. **Send the Experts log lines** starting `T011 DEMO` and `T011 DEMO OPEN POSITION`.
**Abort rule:** any `BLOCKED`, `RECOVERY_REQUIRED` or unexpected line = stop and report. Nothing is retried, and nothing deletes a record or clears a `RECOVERY_REQUIRED`.

## Clean-up (manual, owner only)
The remaining 0.02 of the test position is closed by the owner in the terminal. The demo record `MQL5/Files/VELO_T011_DEMO_<login>_<position>.state` may be deleted by hand once the test is over. No script cleans anything; real records and any `RECOVERY_REQUIRED` record are never deleted by this package.

## What this proves and what it does not
Proves (if it passes): the existing modules work together against a demo terminal for ONE partial close with the real order API: registration of an owned position, stored plan, activation, INTENT, one send, map, reconciliation from the terminal history, save and restore across a terminal restart, and no second request.
Does NOT prove: any strategy rule, profitability, behaviour on the client's Tauro account (symbol properties, filling modes, costs, netting), behaviour under rejects / requotes / partial fills (only the fake transport covered those), protection between terminals, or that the unknown exit policies are right.
