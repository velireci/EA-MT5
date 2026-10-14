# Current project state
Updated: 2026-10-14 (Europe/Tirane). Snapshot, not a transcript.

## Resume here
- Codex is the sole writer for the first T004 round, authorised by the owner while Claude is paused.
- T004 branch: codex/t004-m15-confirmation, based on exact T003 commit 6676a01b63992261b63a9938ace17300658a012f.
- Read tasks/T004-m15-confirmation.md and reports/T004-verification.md before continuing.
- Delivered scope: pure H4-to-M15 observer, external level interface, T003 adapter, disabled-by-default swing proposal and a separate chronological read-only observer EA. Only T003 RECONFIRMED contexts are integrated; ordinary H4 touch path remains unfinished. No trading.
- Default source and timing gates block. The opt-in FVG timing proposal is candle A at/after BOS candle. RETURN_OBSERVED is not entry permission.
- Owner ran T004_LogicTest-51884ec in MT5: 49 passed, 0 failed (2026.10.14 14:21:21.639, relayed). Observer/bridge/source script remain unchanged since that version.
- Owner ran T004_SelectorTest-786568a in MT5: 37 passed, 0 failed (2026.10.14 14:32:33.054, relayed).
- Current round: Codex Python 66/0; MetaEditor T004_TimelineTest and XauUsdM15Observer each 0 errors / 0 warnings. Read-only review found a missing current-level drawing; fixed and re-reviewed with no outstanding concrete findings.
- Next action: owner runs TimelineTest in MT5, then attaches XauUsdM15Observer on a new XAUUSD M15 chart for historical 2026.10.06 00:00, explicitly opting into all three proposals. EA runtime/chart/loading/recovery and replay cost are UNVERIFIED.
- All EA events are REPLAY facts, never NEW or entry permission. Historical mode is static after successful copy; live replays on boundaries/recovery. Q04 remains open; a fractal candidate is not client approval. See docs/T004-m15.md for settings and limits.
- Owner TimelineTest-cfa5f00: 19/0. Historical EA observed RETURN_OBSERVED, H4 BEAR/RECONFIRMED/CONVERGED, BOS4152, 69 facts/8 FVGs, 3531ms. Switching H4->M15 exposed an actual restart-cache defect (empty context with stale BOS). EA v1.01 fixes full OnInit/cache reset; Python67/0, re-reviewed. Updated TimelineTest and actual chart-switch retest pending. No strategy change.
- Claude must switch to this branch only after handoff; do not continue writing T004 on the T003 branch.

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
