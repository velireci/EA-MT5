# T011 verification - 80/20 exit volume split (pure module)

Base 1e34b34, branch codex/t004-m15-confirmation. Scope and contract: tasks/T011-exit-split.md and the header of tests/t011_split_reference.py.

Executed here (Claude, sandbox, from tests/): python3 -m unittest test_t011_split -> 9 tests OK. Coverage: 36 hand-computed fixtures (12 exact
splits incl. step 0.1/0.05/0.001, minimum-lot split 0.05 -> 0.04+0.01, noisy divisions 0.35/0.15/3.0, remainder equal to minimum;
9 not-splittable or part-below-minimum cases -> SPLIT_POLICY_UNSET; 15 invalid inputs with first-failure ordering), a sweep over
steps 0.01/0.1/0.001/0.05 and 1..800 steps (OK exactly when N%5==0, sum conserved), non-finite and wrong-type inputs, mutants
(rounding to nearest, full close, skipped partial, lost volume) all caught, proof that the T006 grid function is reused rather than copied,
and equality of the MQL5 fixture block with the generator. bash tools/t011-static-checks.sh -> ALL PASS (static only).

UNVERIFIED: MetaEditor compile of ExitSplit.mqh and T011_SplitTest.mq5 (Codex), the MT5 run of T011_SplitTest (owner; it also sweeps 1..2000 steps).

Limits: no BE, costs, trailing, 2R detection, account read or order. The behaviour on SPLIT_POLICY_UNSET (round, close fully, skip the partial)
is NOT decided here; it is an open client/owner question. A volume that is exactly splittable says nothing about the strategy.

## Part 2 - 2R activation state machine (base 35e8740)

Relayed (Codex / owner, NOT my runs): ExitSplit at `e3abea2`: Codex Python 9/0, MetaEditor 0/0; owner MT5 SplitTest 234/0.
New (UNCOMMITTED until the parent commits): `src/include/ExitActivation.mqh`, `src/tests/T011_ActivationTest.mq5`, `tests/t011_activation_{reference,fixtures}.py`, `tests/test_t011_activation.py`, `tools/t011-activation-static-checks.sh`, `tasks/T011-exit-activation.md`. Transitions and limits: tasks/T011-exit-activation.md and the reference header.
Executed here (Claude, sandbox, from tests/): python3 -m unittest test_t011_activation -> 9 tests OK: 106 hand-written event rows in 44 scenarios (BUY/SELL before, at and beyond 2R; Bid for BUY and Ask for SELL; repeated quotes in REQUEST_PENDING and DONE; full confirmation; duplicates; rejection; timeout; partial execution at 1, 5 and 7 of 8 steps and the illegal partials 0, 8, 9; wrong id; wrong, zero and off-grid volume; report without request; conflicting report after DONE; SPLIT_POLICY_UNSET for 7 steps, remainder below minimum and SELL; volume mismatch before the request, after DONE, and the volume running ahead of the confirmation while pending; identity changes; a 12-digit position id; invalid quotes and reports changing nothing), a seeded fuzz of 400 random runs (at most one request, confirmations <= 1 and monotone, stop states absorbing), non-finite and wrong-type inputs, 15 mutants (BUY on Ask, SELL on Bid, strict comparison, pending re-request, partial or rejected/timeout becoming DONE, duplicate counted twice, wrong id or volume accepted, reconcile left by a quote, volume mismatches ignored, identity unchecked, unstable id, unset split still requesting) all caught, proof that ES_Split / PS_GridSteps are reused, and equality of the MQL5 fixture block with the generator.
UNVERIFIED: MetaEditor compile of ExitActivation.mqh and T011_ActivationTest.mq5 (Codex), the MT5 run of T011_ActivationTest (owner), any behaviour with a real broker. The C++ transliteration tool could not translate these headers (its shim lacks what TradeGeometry needs), so there is no second-language run of the MQL5 code.

### Correction after the Codex review of 23180cb (relayed: Python 9/0, MetaEditor ActivationTest 0/0, defect reproduced by Codex)

Defect: BUY at 2R, initial/current 0.5, step 0.01, min 0.01, max 100 requested 0.4 lot (40 steps); a FULL report with the same request id, executed 0.04 and step 0.001 (also 40 steps) was accepted as DONE with confirmations 1. Second finding: the identity was bound before the volume parameters were validated, so an invalid first quote could bind the position.
Fix (T011 activation only): `volume_step` of the request is stored in the state; a report or duplicate with another step is BLOCKED (STEP_CHANGED) and the executed volume is converted with the stored step; a quote in DONE with another step is NEEDS_RECONCILIATION; the volume parameters are validated with ExitSplit on every quote before the stop-state check and the binding. Regressions: BUY and SELL for 0.4 -> 0.04 (also same volume 0.4 on the other grid, PARTIAL and REJECTED reports on the other grid), the step changed after DONE (duplicate report and quote, where the changed grid makes the volume alias the expected remainder), invalid step / min / max / min off grid / initial off grid on the first quote (also before 2R) followed by a valid quote of another position, invalid parameters while pending. Rows: 149 in 62 scenarios (was 106 / 44). Mutants: 19 (4 new: step not compared; the original defect = no comparison plus conversion on the reported step; step change after DONE ignored; invalid parameters bind the identity), all caught.
Executed here: python3 -m unittest test_t011_activation test_t011_split -> 20 tests OK; static checks: see the hand-off. UNVERIFIED: MetaEditor recompile of the changed ExitActivation.mqh and T011_ActivationTest.mq5 (Codex), MT5 run (owner).

### Test-only fix after the owner's MT5 run at 82060cc (relayed: 990 passed, 1 failed)

Failing check: "unknown report kind is invalid and changes nothing" in `TestInvalid`. Cause (relayed from Codex, consistent with the code): the BUY/SELL loop before it leaves `st` in BLOCKED (STEP_CHANGED) and the check expected IDLE without re-initialising the state. `EA_OnReport` refuses the enum before any mutation, so the BLOCKED state was correctly preserved: a test defect, the activation logic is unchanged. Fix in `src/tests/T011_ActivationTest.mq5` (and a Python twin in `tests/test_t011_activation.py`): for each of IDLE, REQUEST_PENDING, DONE, NEEDS_RECONCILIATION and BLOCKED the state is built explicitly, copied before the call (`SameState` compares every field), and the unknown kinds 9 and -1 must return INVALID_INPUT and leave the whole state identical. UNVERIFIED: MetaEditor recompile and the MT5 rerun of the test.
