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
