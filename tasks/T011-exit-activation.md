# T011 part 2 - 2R partial-close activation (pure state machine)

Branch `codex/t004-m15-confirmation` (PR #4), base `35e8740` (T003 panel 1.13 carried; ExitSplit `e3abea2` verified by Codex: Python 9/0, MetaEditor 0/0; owner MT5 SplitTest 234/0 - relayed, not my runs). Writer: Claude. Codex reviews and compiles; the owner runs MT5.

Scope: decide when a request to close 80% of the INITIAL volume is produced at 2R, and track the caller-supplied execution reports. No order API, account read, persistence, retry, BE, costs, trailing or EA wiring.

Inputs (all supplied by the caller): position id, BUY/SELL, level_2R (T005 partial_price), Bid/Ask, initial and current volume, volume min/step/max, and later execution reports (request id, kind FULL / PARTIAL / REJECTED / TIMEOUT, executed volume). The state object is in memory and owned by the caller: no guarantee after a restart, not atomic.
Technical convention for review (NOT a client rule): BUY reaches 2R when Bid >= level; SELL when Ask <= level.
The 80/20 split is ES_Split (reused; it reuses the T006 grid); the executed volume is compared in volume steps with PS_GridSteps (reused).

Transitions (full table in the header of tests/t011_activation_reference.py):
- IDLE: before 2R nothing. At/after 2R with an exact split and actual volume == initial: ONE request, id `X2R80-<position_id>`, state REQUEST_PENDING. Split impossible: event SPLIT_POLICY_UNSET, no request (no rounding, full close or skip). Actual volume != initial: NEEDS_RECONCILIATION (plan not changed). A report in IDLE: BLOCKED.
- REQUEST_PENDING: repeated quotes are ignored (no second request). FULL report with the request id and exactly the requested volume (steps): DONE, confirmation counted once. REJECTED, TIMEOUT or PARTIAL execution: NEEDS_RECONCILIATION (no retry). Wrong id, wrong FULL volume, PARTIAL outside (0, request), volume off the grid: BLOCKED.
- DONE: quotes ignored unless the actual volume differs from initial - closed (then NEEDS_RECONCILIATION). The same confirmation again: DUPLICATE_IGNORED (not counted). Any other report: BLOCKED.
- NEEDS_RECONCILIATION and BLOCKED are absorbing: later events change nothing (a late fill after a timeout is NOT accepted here; the caller reconciles with the broker and starts a new state).
- The first valid quote binds position, direction, level and initial volume; a change is BLOCKED. Invalid input changes nothing: the volume parameters (ExitSplit validation) are checked on EVERY quote before anything is bound.
- The volume step of the request is stored in the state. A report or duplicate with another step is BLOCKED (STEP_CHANGED); a quote in DONE with another step is NEEDS_RECONCILIATION. The executed volume is converted to steps with the stored step only (Codex review of 23180cb: 0.5 lot on a 0.01 grid requests 40 steps; 0.04 lot on a 0.001 grid is also 40 steps and must not confirm it).

Limits: nothing about how the request is sent, retried or reconciled; no restart recovery; the policy for SPLIT_POLICY_UNSET (round, close fully, skip) and the TP == 2R interaction stay open client/owner decisions; the plan is never changed automatically.
Files: src/include/ExitActivation.mqh, src/tests/T011_ActivationTest.mq5, tests/t011_activation_reference.py, tests/t011_activation_fixtures.py, tests/test_t011_activation.py, tools/t011-activation-static-checks.sh.
