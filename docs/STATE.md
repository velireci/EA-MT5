# Current project state
Updated: 2026-10-14 (Europe/Tirane). Snapshot, not a transcript.

## Resume here
- T004 branch codex/t004-m15-confirmation (PR #4) on exact T003 commit 6676a01. T001-T003 logic/tests/tools byte-identical to 6676a01 (checked by tools/t004-static-checks.sh).
- Read tasks/T004-m15-confirmation.md (four rounds, decision inventory) and reports/T004-verification.md first.
- Delivered: pure H4-to-M15 observer, disabled-by-default M15 swing proposal, chronological read-only EA XauUsdM15Observer v1.02, and (round 4) the ORDINARY H4 FVG-touch context source H4TouchContext.mqh, distinct from the T003 RECONFIRMED source. No orders, SL/TP, risk or M5. All events are REPLAY facts; RETURN_OBSERVED is not entry permission.
- Four opt-ins, all UNSELECTED by default: context source (T003 RECONF, or ordinary T002 touch with AFTER_LOSS / FIRST_ONLY re-touch policy), M15 level (latest fractal), FVG timing (A at/after BOS). Ordinary source rules are TECHNICAL PROPOSALS (open decisions OD1-OD6 in the task file). T002/T003 direction disagreement is flagged, never resolved. Q04 stays open.
- Relayed owner MT5 evidence (not our runs): LogicTest 49/0 at 51884ec; SelectorTest 37/0 at 786568a; TimelineTest 19/0 at cfa5f00; EA eedbe92 historical 2026.10.06: H4 BEAR/RECONFIRMED/CONVERGED, RETURN_OBSERVED, BOS 4152.00, 8 FVGs, 69 facts, survived M15->H4->M15 (rebuild after timeframe change verified, not strategy validity). Codex relayed: Python 67 tests, EA and updated Timeline script compile 0/0; updated TimelineTest MT5 run pending.
- Round 4 executed in this environment: Python 94 tests (67 + 27 new) pass; T001-T003 checks rerun; no C++ compiler. MetaEditor compile of EA v1.02, H4TouchContext.mqh and T004_OrdinaryTest.mq5: UNVERIFIED. MT5 runs UNVERIFIED.
- Next action: Codex compiles XauUsdM15Observer, T004_OrdinaryTest and the updated T004_TimelineTest in MetaEditor; the owner runs both scripts in MT5, then observes the EA historically with source 2 or 3 plus the other two opt-ins. Replay cost of the ordinary scan is unmeasured.
- Claude must not continue T004 writing on the T003 branch.

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
- Q05/Q07-Q11: entry edge, SL/buffer, target, sizing, costs, partial exit, ownership/restart, limits/session/news/expiry and re-entry.
- Ask only what blocks the current step; build independent infrastructure. Never silently invent a client rule.

## Environment and handoff
- Private repo velireci/EA-MT5. Local Codex workspace is an isolated source export, not a Git checkout; publication uses GitHub Git objects with the actual parent/tree.
- MetaEditor is available on the owner's Windows machine. Test terminal: MetaQuotes-Demo XAUUSD, EUR hedging; target Tauro XAUUSD.r/USD properties are unverified.
- No project module can send, modify or close orders. Unrelated legacy MA_Crossover_EA.mq5 DOES trade; do not use it as the project EA.
