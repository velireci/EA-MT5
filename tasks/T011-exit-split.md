# T011 - 80/20 exit volume split (pure module)

Branch `codex/t004-m15-confirmation` (PR #4), base `1e34b34`. Writer: Claude. Review and MetaEditor compile: Codex. Owner runs MT5.

Scope: a pure helper answering whether the INITIAL volume can be split exactly 80% / 20% on the broker volume grid with both parts
allowed. Client statement (STRATEGY_SPEC section 8, K B1): at 2R close 80% of the initial volume; the remaining 20% runs to TP or SL; no trailing.

Inputs: volume_initial, volume_min, volume_step, volume_max. Output: status, reason, step diagnostics, close volume, remaining
volume, real percent. Statuses: OK, INVALID_INPUT, SPLIT_POLICY_UNSET.

Rules: T006 grid validation reused (PS_GridSteps), not copied or changed. Exact integer arithmetic on steps: N%5==0, close=4N/5,
remaining=N/5, sum is N. If not exactly realizable or the remainder is below volume_min: SPLIT_POLICY_UNSET. No rounding, no full
close, no skipped partial exit is invented (open client/owner decision).

Out of scope: BE, costs, trailing, 2R detection, account read, order placement, EA wiring, TP==2R interaction, the +0.2% question,
checklist 5 other items. Files: src/include/ExitSplit.mqh, src/tests/T011_SplitTest.mq5, tests/t011_split_*.py, tests/test_t011_split.py,
tools/t011-static-checks.sh, reports/T011-verification.md.
