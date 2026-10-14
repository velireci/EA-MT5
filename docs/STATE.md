# Current project state
Updated: 2026-10-14 (Europe/Tirane). Snapshot, not a transcript.

## Resume here
- Branch codex/t004-m15-confirmation, PR4, base 8c562fe (T009). T010 (owner-approved, Claude sole writer) adds USD-HIGH news and spread filters to the preview EA v1.03; UNCOMMITTED until the parent commits. No merge, no order activation.
- T010: pure src/include/NewsSpreadFilters.mqh (news window +-1800 s inclusive, SERVER time, USD+HIGH only, unknown/error/tester -> UNKNOWN; spread (Ask-Bid)/point vs InpMaxSpreadPoints, -1 = UNSET, noise tolerance 16*DBL_EPSILON-scaled). Thin calendar reader inside the EA. MANUAL stays default per filter; results feed only the T007 permit snapshot. Docs: tasks/T010-news-spread-filters.md, docs/T010-news-spread.md, reports/T010-verification.md.
- T010 evidence (Claude, sandbox): Python test_t010_filters 19 tests OK with 17 mutation checks; T007-T009 78 tests total OK; tools/t010-static-checks.sh ALL PASS. UNVERIFIED: MetaEditor compile, T010_FiltersTest in MT5, live calendar, tester, official MQL5 docs (site unreachable; signatures from memory).
- NEXT: Codex reviews and compiles XauUsdTradePreview.mq5 and T010_FiltersTest.mq5, checks calendar API signatures/time semantics against the official docs. Then owner runs T010_FiltersTest, then the preview with MANUAL, then with CALENDAR_AUTO + QUOTE_AUTO (send T010 CALENDAR/NEWS/SPREAD log lines).
- Not decided: spread threshold value, action after spread block, positions at news/session end, calendar history in tester.
- T009 owner step still pending: T009_SessionTest in MT5 and preview SESSION_TIRANE_CLOCK log T009 SESSION. Other unknown policy gates stay blocked.
- T008 owner 4b6a5b5 helper 25/0 and hypothetical BUY preview model/broker 8.98 EUR at .01 lot/budget 10 EUR, unknown-policy BLOCK. T007 owner 40fede0 MT5 1092/0; T006 559794a 710/0; T005 67f02e5 572/0. Pure scopes verified, not strategy/broker execution.
- Open: signal/FVG/SL/target selection, direction priority, risk base/costs, exposure accounting, persistence, pending lifecycle, partial management and actual order APIs. Updated T004 TimelineTest owner run pending.

## Verified T003 baseline: 6676a01
- Codex MetaEditor: XauUsdH4Bias, T003_LogicTest and T003_LayersTest each 0 errors / 0 warnings.
- Owner MT5: LogicTest 484 passed, 0 failed, 5 deferred; LayersTest 105 passed, 0 failed (2026-10-14).
- Codex Python: 476 passed, 0 failed, 5 deferred; private_regression.py FAILURES 0 on the owner's CSV for as-of 2026.09.26 and 2026.10.06.
- Owner historical EA observation: as-of 2026.09.26 00:00, 2000 H4 bars, last closed 09.25 20:00, BEAR / SWEEP_WAIT / CONVERGED, protecting level 4371.20; SWEEP@202609251200, reason INTERNAL.
- The per-level selector records the 09.25 wick above 4303.22 without a FLIP. Private replay agrees with the isolated prototype; no source CSV is in the repository.
- T003 is NOT fully client-validated. T002 and prototype T003 can disagree on direction; CONVERGED only means agreement at tested replay depths.
- Deferred/unfinished areas include intrabar P12, target P13 and broader EA/drawing/lifecycle validation. Do not count deferred as PASS.
- The initial single-candidate selector analysis was corrected: has_lint was false at the relevant Sept 25 bar, not an active candidate at 4371.20.

## T002 evidence and limits
- Tested EA 97ce7b4: Codex compilation 0/0; owner LogicTest 208/0; Python 197/0.
- SetupScan 6a8c0c6 is included in PR #2. Codex compile 0/0; owner 529 moments in 147 runs.
- Owner historical as-of 2026.10.06: BEARISH, interval 4103.67-4226.45, FRESH IRL 4144.02-4150.84, ERL 4103.67 UNTOUCHED; bounds/swing low manually checked.
- Weekend/restart and remove/re-attach observed; manual line preserved.
- LIVE new-H4 evidence: owner log supplied to Codex shows one boundary recompute at log 2026.10.14 03:00:00.079 for closed H4 00:00 and at 07:00:00.062 for closed H4 04:00. DESYNC recovery recomputes are separate. No further H4 wait is required for this check.
- This evidence is recorded here from the conversation/Codex review; raw logs/screenshots remain outside the repo. T002 report/PR body may still lag this snapshot.
- Mechanical zone/direction rules remain proposals; broker/TradingView alignment and client visual validation are unverified.

## T001 and PRs
- T001 tested code 763227d: Codex compile 0/0, partial owner demo observation. Remaining foundation gaps are listed in reports/T001-verification.md; not all acceptance checks are fully observed.
- PR #1: claude/amazing-darwin-icpcjd, last known head 56c9570; open, unmerged.
- PR #2: claude/t002-h4-map, last known head dd571f6; draft, stacked on T001.
- PR #3: claude/t003-h4-bias, verified head 6676a01 when T004 began; draft, stacked on T002. Its old PR description is stale.
- No PR merged. main's previously observed 91091d2 deletion of jessy was unrelated; no base was moved.

## Confirmed flow versus proposals
- H4 context only; trend direction HH+HL / LH+LL. Algorithmic structural swing selection is not client-approved.
- IRL is H4 FVG context, not entry. Wick touch allowed; wait for H4 touching candle close, then M15 structure break, then M15 FVG/return.
- After liquidity grab, a NEW H4 FVG is required. Exact three-candle timing remains a labelled proposal.
- M15 only: M5 was removed by client N5. Minimum TP 2R when target is nearer, per N6; execution/risk mechanics remain later work.
- Current structure, old liquidity levels, H4 FVG context and setup are separate concepts. Old unbroken liquidity is not by itself a confirmed rule for freezing direction.
- Strategy prices/dates/BOS counts in examples are illustrations, never constants.

## Open choices for relevant later steps
- Q04: actual M15 structural swing, break definition and FVG association/timing.
- Direction-source selection when prototype bias contradicts T002; structural-versus-local H4 swing.
- Q05/Q07-Q11: CORRECTED: entry edge (beginning of the M15 FVG) and SL principle (broken-structure extreme) are client-written; open are FVG choice among several, structure algorithm, buffer, target algorithm, sizing, costs, partial remainder, ownership/restart, limits/session/news/expiry and re-entry. See tasks/T005-entry-sl-tp-plan.md.
- Ask only what blocks the current step; build independent infrastructure. Never silently invent a client rule.

## Environment and handoff
- Private repo velireci/EA-MT5. Local Codex workspace is an isolated source export, not a Git checkout; publication uses GitHub Git objects with the actual parent/tree.
- MetaEditor is available on the owner's Windows machine. Test terminal: MetaQuotes-Demo XAUUSD, EUR hedging; target Tauro XAUUSD.r/USD properties are unverified.
- No project module can send, modify or close orders. Unrelated legacy MA_Crossover_EA.mq5 DOES trade; do not use it as the project EA.


