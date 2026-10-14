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
