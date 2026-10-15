# T011 exit manager: ONE demo SELL test (package for the Codex review; nothing here is activated)

Status: presets and steps only. No code was added or changed for this package; the real path has never been run. MetaEditor and MT5 runs of the code are the relayed ones (see reports/T011-verification.md Part 15). Demo account, one terminal, no other EA or script on XAUUSD that touches magic 778.

## What is reused and what is separate from the first test
| step | script (existing) | preset | notes |
|---|---|---|---|
| 1 open | `XauUsdT011DemoOpenPosition.mq5` | `XauUsdT011ExitDemoSell_01_open.set` | SELL 0.05, SL distance 5.00, TP distance 15.00, magic **778** |
| 2 register | `XauUsdT011ExitRegister.mq5` | `XauUsdT011ExitDemoSell_02_register.set` | explicit; fill only position id, SL, TP from the step-1 log |
| 3 manager | `XauUsdT011ExitManager.mq5` | `XauUsdT011ExitDemoSell_03_manager.set` | same three values; the 2R level is derived, never typed |
Separate from the earlier test: magic 778 (the first test used 777) gives a new open-intent file `VELO_T011_DEMO_OPEN_INTENT_<login>_778.txt` and a new lock key; the new position has a new identifier, hence a new state file `VELO_T011_EXIT_<login>_<identifier>.state`. Nothing of the first test (position 58913478802, its state and intent files) is read, changed or deleted. Volume 0.05 = 5 steps -> 4 / 1: 0.04 is closed, 0.01 remains (it then runs to its TP/SL; no trailing, BE and +0.2% are open and not used).
The distances are DIAGNOSTIC: R_GEOM = 5.00, the geometric 2R level is 10.00 BELOW the open price, TP is 15.00 below it (beyond 2R, so TP == 2R and TP before 2R are avoided). R_GEOM is not the client's final R and no cost is modelled. No artificial threshold is used and the SL is NOT moved to provoke the test.

## Steps (after the Codex review; the owner acts, one step at a time)
1. **Open.** Load preset 01, `InpEnabled=true`, type `I_AUTHORISE_T011_DEMO_OPEN_POSITION`, run once. Keep the log lines: position ticket, **POSITION_IDENTIFIER**, open price, volume, **SL**, **TP**, magic. Check: SELL, volume 0.05, SL = open + 5.00, TP = open - 15.00. If the script prints UNCERTAIN or an intent file for magic 778 exists, STOP.
2. **Register.** Load preset 02; fill ONLY `InpPositionId` (the identifier), `InpInitialSl` (the SL printed), `InpTpPrice` (the TP printed); `InpEnabled=true`, type `I_AUTHORISE_T011_DEMO_PARTIAL_CLOSE`; run once. Expected: `REGISTERED`. Any refusal (for example INITIAL_SL_NOT_PROVEN) means STOP; do not edit the position.
3. **Manager.** Load preset 03 on the XAUUSD chart; fill the SAME three values; `InpEnabled=true`, the phrase, `InpConfirmAutoSend=true`. Read the INIT line: `armed 1`, direction -1 and the derived level. Compare it by hand with `open price - 2 * (SL - open price)` from the step-1 log. If it differs or `armed 0`: remove the EA, STOP.
4. **Wait.** Do not move the SL or the TP, do not close anything. The EA acts only when the Ask reaches the level (SELL: Ask <= level).
5. **After the request.** The timer reconciles (INIT/TIMER lines). Keep the Experts log and the account history of the position.
6. **Restart.** After DONE close and reopen MT5 completely with the EA attached: the INIT line must show the recovery (DONE / ALREADY_DONE) and no new request.
Abort rule: any SEND_UNCERTAIN, RECOVERY_REQUIRED, lock failure or unexpected line = no retry, no cleanup; send the full log to Codex. Nothing deletes the state or intent files; the owner decides.

## Acceptance criteria (all four must hold for SUCCESS)
1. **Zero requests before the level:** no closing order or deal of magic 778 in the history and no send line in the log until the Ask first reaches the level.
2. **At most one request at the level:** exactly one closing order of 0.04, request id `X2R80-<identifier>`, no second order on later ticks.
3. **Reconciliation from the broker:** the timer reaches DONE with confirmations 1 from the history (linked deals = 0.04 on the position identifier), not from the return value of the send.
4. **Restart without a second send:** after the full restart no further order; the state stays DONE (ALREADY_DONE).
Reporting: if the Ask never reaches the level the test is a **PENDING proof** (neither success nor failure). Closing the position or removing the EA before the level is INCONCLUSIVE. A violated criterion is a FAILURE to be analysed by Codex before anything else is run. This package does not prove profitability, strategy behaviour, cost-inclusive R, SELL/BUY generality or a live account.
