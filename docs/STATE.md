# Current project state
Updated: 2026-10-14 (Europe/Tirane). Snapshot, not a transcript.

## Resume here
- Branch codex/t004-m15-confirmation (PR #4), T004 delivered at 5447ef3 plus the T005 work below (UNCOMMITTED when written; the parent commits). T001-T004 logic/tests/tools byte-identical to 5447ef3 (checked by tools/t005-static-checks.sh).
- Read tasks/T005-entry-sl-tp-plan.md and reports/T005-verification.md first; T004 detail is in tasks/T004-m15-confirmation.md and reports/T004-verification.md.
- CORRECTION (2026-10-14, Codex found it, parent verified): the client WROTE the entry and SL. "Entry eshte te fillimi i FVG ne M15 dhe Stop Loss ne piken me te lart te struktures se thyer ne M15 ne rastin e Sell ose ne piken me te ulet ... ne rastin e Buy dhe Profit eshte Likujditeti i jashten" (inputs/client-E27N93/pergjigjet.json:187, specifikimi.txt:24; pd_level :189 repeats the SL rule with "likuiditeti i rradhes"). Entry = beginning of the M15 FVG, SL = extreme of the broken M15 structure (SELL highest, BUY lowest): CLIENT STATEMENTS, not reviewer readings. sl_method = "?" does not cancel them. Do NOT ask the client again about start/middle/end of the FVG or whether SL follows the structure.
- Codex-relayed visual interpretation (Codex viewed the photos, we did not; not a citation): SELL examples draw the entry at the LOWER FVG edge, the unactivated BUY at the UPPER edge ("first edge met on the return").
- Still open (no value invented, zero NOT confirmed): which M15 FVG among several (C1); the algorithm identifying the whole broken structure and any buffer (C2, with Q04); target algorithm ("Likujditeti i jashten" vs "likuiditeti i rradhes", C5); R/cost definition (C3/C4); sizing; expiry/re-entry; T002 vs T003 priority; post-partial; the 50-unit limit.
- NEW T005 geometry helper (pure, side-effect free, NOT wired to any EA or order, no sizing/volume): src/include/TradeGeometry.mqh, mirror tests/t005_geometry_reference.py, tests/t005_geometry_fixtures.py, tests/test_t005_geometry.py (34 tests), src/tests/T005_GeometryTest.mq5, tools/t005-static-checks.sh + t005-static-check.py. Caller supplies direction, E, S, optional T; the module normalizes E and S to integer ticks FIRST (nearest, half tick up: proposal), reports E_out/S_out, computes R_geom and level_2R only from them, TP = farther of target (rounded away) and 2R (N6), partial point = 2R, TP/partial coincidence flagged, COSTS_NOT_MODELLED, statuses incl. pending distance when bid/ask supplied. The 50-limit is NOT enforced.
- Evidence executed here: T005 unit tests 34 OK; all T004 tests 94 OK (128 together); T002 reference 197/0, T003 reference 476/0 (5 deferred); static checks t001, t002, t003-visual, t004, t005 ALL PASS; t003-static-checks CHECK 12 fails only because the documentation corrections are still uncommitted (rerun after the commit; details in reports/T005-verification.md). MetaEditor compile and MT5 run of the T005 files: UNVERIFIED (no tools here). Nothing relayed for T005 yet.
- T005 validation fix (Codex review of 5c3af40, UNCOMMITTED when written): INVALID_INPUT now also covers INCOMPATIBLE_TICK_DIGITS (tick_size must be an integer multiple of 10^-digits, >= 10^-digits), NONPOSITIVE_PRICE (E_out, S_out, level_2R, target, TP, partial must be > 0) and NUMERIC_OVERFLOW (non-finite results; price/tick_size <= 1e12 in both languages); nothing is reported on those failures. Same rules in Python and MQL5; order in tasks/T005 item 8; details in reports/T005-verification.md. MQL5 changes not compiled or run (UNVERIFIED).
- Next action: Codex compiles src/tests/T005_GeometryTest.mq5 (and TradeGeometry.mqh) with MetaEditor and reviews the conventions in section D of the T005 plan; the owner then runs T005_GeometryTest in MT5 and reports passed/failed. Separately the owner still runs the UPDATED T004 TimelineTest (pending since 78879cd). No order code until C1, C2, C6, C8, C9, C10 are settled.
- T004 relayed evidence (NOT our runs): owner MT5 LogicTest 49/0, SelectorTest 37/0, TimelineTest 19/0 at earlier commits, OrdinaryTest 79/0 at 78879cd; Codex Python 94 pass and compiles 0/0 at 78879cd; updated TimelineTest MT5 run PENDING. Owner historical EA observation 2026.09.18 (sources M4_T002_TOUCH_AFTER_LOSS / M4_LATEST_FRACTAL / M4_A_AFTER_BOS) showed the proposals in sequence (WAIT_BREAK, BOS_CANDIDATE, FVG_CANDIDATE, RETURN_OBSERVED, FVG_INVALIDATED, ERL_TAKEN); observed behaviour of UNVALIDATED proposals only, RETURN_OBSERVED is not entry permission, T002/T003 disagreement flagged not resolved. T004 and the strategy are NOT fully validated.
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
- Q05/Q07-Q11: CORRECTED: entry edge (beginning of the M15 FVG) and SL principle (broken-structure extreme) are client-written; open are FVG choice among several, structure algorithm, buffer, target algorithm, sizing, costs, partial remainder, ownership/restart, limits/session/news/expiry and re-entry. See tasks/T005-entry-sl-tp-plan.md.
- Ask only what blocks the current step; build independent infrastructure. Never silently invent a client rule.

## Environment and handoff
- Private repo velireci/EA-MT5. Local Codex workspace is an isolated source export, not a Git checkout; publication uses GitHub Git objects with the actual parent/tree.
- MetaEditor is available on the owner's Windows machine. Test terminal: MetaQuotes-Demo XAUUSD, EUR hedging; target Tauro XAUUSD.r/USD properties are unverified.
- No project module can send, modify or close orders. Unrelated legacy MA_Crossover_EA.mq5 DOES trade; do not use it as the project EA.
