# Current project state

Updated: 2026-10-13 (Europe/Tirane)

## Resume here
- T003 REVISION 10 PROTOTYPE (this round, nothing committed by me): the owner authorised a prototype with the current information. Implemented in `src/include/H4Bias.mqh`, the Python model, the MQL5 test script and the static checks: structure (bias, protecting level) updates on every closed bar in every phase; a separate setup context (setup_id, snapshot, wick/sweep record, FVG tracks); the revision 9 RATCHET as a labelled working proposal; variant A; the CURRENT level decides FLIP, the snapshot is a reference only; RECONF_LOST keeps the setup; SETUP_ENDED only INVALIDATED_BY_FLIP and REPLACED; no expiry; A/B by function (AB_STRUCTURE_DIFF / AB_SETUP_DIFF / AB_EVENT_DIFF / ANCHOR_*, ORG_DIFF informational). Task: tasks/T003-h4-bias-change.md section 12 (corrections, decisions D1-D9, R1-R22 status). Report: reports/T003-verification.md section 13.
- RESUME HERE: Codex compiles (MetaEditor) and reviews the prototype. The CLIENT ANSWER to the level-update question (does the protecting level move to the new high/low or does the old level stay?) is still PENDING: the ratchet is a PROPOSAL / PROTOTYPE awaiting it, not a confirmed rule. Visual EA files were NOT touched (still need an integration round after the review; the pure-logic API kept every name and field the visual EA uses, `frozen` is a deprecated always-false field).
- PRIVATE REPLAY (parent's run of tests/t003_replay_csv.py on the owner's CSV, which stays outside the repo): the prototype model gives CONVERGED (depth 2000 vs 1700), both replays BEAR/SWEEP_WAIT, same level, all 12 compared fields equal, 228 identical events in the zone; state keys differ only on the first 222 of 1700 common bars. The old EA result in the CSV header (LIMITED_BY_HISTORY) is from the pre-prototype code, so the script prints NOT REPRODUCED. CONVERGED is NOT a validation: flips 36/29 over the window are many; it needs Codex's review, the client's level-update answer and a visual comparison.
- Spec corrections found while implementing (task 12.2): confirm_time = open of the real bar index p+RightBars plus one period (T002 and the T003 layer already did this; only the revision 9 text was wrong); a new level is used from the following bar; A/B also compares wait_start, source time, FVG bounds/times and pending-candidate consumption; the origin name is provenance (ORG_DIFF); M15_OUTCOME is not an event, only read-only setup context is exposed.
- Honest limits: SC-1 type series (no newer leg) stay LIMITED_BY_HISTORY; the prototype produces about twice as many FLIP/WICK events on random walks (report 13.5); the real CSV may stay LIMITED.
- Do not start: P12, P13, M5/M15, orders, positions. No merge of PR #1, #2 or #3.

## Branches and PRs (verified from the GitHub API and git on 2026-10-13)
- PR #1 (T001): branch `claude/amazing-darwin-icpcjd`, head `56c9570`, base `main`, open, NOT merged. Tested version `763227d`.
- PR #2 (T002), draft: branch `claude/t002-h4-map`, head `dd571f6`, base the T001 branch. Commit `6a8c0c6` (T002_SetupScan.mq5 and docs/T002-setup-scan.md) is an ancestor of this head, so the SetupScan IS delivered in PR #2 (its body already says so; no correction needed). Tested EA code is `97ce7b4`; later commits are docs, one tools fix (check 15) and the scan script.
- PR #3 (T003), draft: branch `claude/t003-h4-bias`, head `62a0747` (revision 7, tested by Codex/owner as relayed above; the visual EA files are uncommitted in the working tree), base `claude/t002-h4-map` (`dd571f6`).
- `main` has moved to `91091d2` ("Delete jessy", the unrelated pre-existing file; not done by this agent). The T001/T002/T003 branches still contain `jessy`. PR #1 may need `main` merged in when the owner decides about it; nothing was done.
- This handoff was committed on the T003 branch only (a descendant of the T002 branch), to avoid STATE.md conflicts between stacked PRs; the STATE.md on the T002 branch is older.

## T002 state (no strategy rule is confirmed: all H4 rules are PROPOSALS awaiting the client's visual validation)
Documented evidence. Items marked (relayed) come from Codex or the owner, not from runs of mine; no logs or screenshots are in the repository.
- Compilation of `XauUsdH4Map.mq5` and `T002_LogicTest.mq5` at `97ce7b4`: 0 errors, 0 warnings (Codex, relayed).
- `T002_LogicTest` in MT5: 208 passed, 0 failed (owner, relayed).
- Python model tests: 197 passed, 0 failed (mine; also by Codex on `a92b033`, relayed). Static checks T002 PASS, including check 15 and its negative mutations; the check-15 fix was verified in the Codex environment where it had failed (mine; Codex, relayed).
- `T002_SetupScan.mq5` at `6a8c0c6`: compiled 0/0 (Codex, relayed); run by the owner: 529 active moments in 147 runs (relayed).
- EA historical mode at AsOfTime 2026.10.06 00:00 (server time) reproduced a scan setup: BEARISH, interval 4103.67-4226.45, IRL FRESH 4144.02-4150.84, ERL 4103.67 UNTOUCHED; the owner checked the FVG bounds and the 2/2 swing low at 4103.67 manually (relayed).
- Weekend as-of case (2026.10.04 12:00, last candle 2026.10.02 20:00, close 4147.62; same 70 swings and 53 FVGs after a restart) and remove/re-attach: object lists before and after matched and a manual line remained (relayed).
Pending: a log showing the map rebuilt ONCE on a new H4 candle in LIVE. The log of 2026.10.13 20:07:52 (relayed) shows a clear and a recovery from DESYNC but analysed the 16:00 candle again, so it is NOT evidence of the new-candle rebuild.
Out of T002 scope: M5/M15 and the 2R policy. Declared limits: Tauro versus TradingView candle and time alignment is not verified; the client's validation is pending; label readability; the 12 interpretations in reports/T002-verification.md section 5. T002 is NOT closed. See reports/T002-verification.md and the PR #2 body.

## T003 state (PR #3; proposals, not confirmed strategy)
- Specification: tasks/T003-h4-bias-change.md (client statements S1-S6 and BUY example E1-E6 kept apart from proposals P1-P14); revision 10 PROTOTYPE in section 12 (PROPOSAL / PROTOTYPE, awaiting the client: ratchet / level update). Client statements are in docs/DECISIONS.md (the owner's authorisation of the prototype is not logged there: parent to decide).
- Implemented (uncommitted): pure logic `src/include/H4Bias.mqh`, Python model `tests/t003_reference_test.py`, MQL5 test script `src/tests/T003_LogicTest.mq5`, `tools/t003-static-checks.sh`, new evidence tool `tools/t003-xlate-check.sh` + `tools/t003_xlate/` (MQL5 -> C++ transliteration run; NOT MetaEditor). Visual EA files untouched (byte-identical to 47a25d9). No T001/T002 file changed.
- Results (mine, this environment): Python T003 model 394 passed, 0 failed, 5 deferred (exit 0); T002 model 197 passed; T003 static ALL PASSED (95 PASS lines); visual static 72 PASS; T002 static 60 PASS; T001 static 25 PASS; C++ transliteration of the MQL5 test script 404 passed, 0 failed, 5 deferred (NOT MetaEditor / MT5), with a failing negative control (389/15).
- UNVERIFIED: MetaEditor compilation of the revision 10 code and tests; any MT5 run; the visual EA against the changed header; the private CSV replay; behaviour on real data. DEFERRED test groups: 9, 18, 20, drawing tests, M5/M15.
- Known limits: SC-1 type series and a setup older than the check depth stay LIMITED_BY_HISTORY (variant A); about twice as many FLIP/WICK events on random walks (reports/T003-verification.md 13.5, 13.7).

## Open decisions and next owner actions
- Have Codex review T003 and answer or defer F1-F8 (see tasks/T003-h4-bias-change.md section 8): exact time definition of the new FVG after the wick, M5/M15, policy below 2R, positions already open, ERL selection and reconfirmation validity, the intrabar block proposed by Codex, entries while LIMITED_BY_HISTORY (technical proposal), interior liquidity.
- Supply the candles the client marked for the section-10 visual comparison; send the LIVE new-candle log for T002; decide about PR #1, PR #2, PR #3 and the moved `main`.
- Client screenshots are illustrations (not stored in the repository); text clarifications take priority; no price or BOS count is a rule.

## Basics
- Source: inputs/client-E27N93/pergjigjet.json and associated TXT/photos. No strategy logic was invented; disputed or undefined rules remain open (Q01-Q12).
- Next developer action: none until the parent commits this round, Codex compiles it and the owner sends the CSV and the DIAG lines.

## Files added in T001
- `src/XauUsdFoundation.mq5` — main EA. OnInit/OnDeinit/OnTick/OnTimer, configurable magic (stored, unused), symbol resolution, status logging on change only, chart panel.
- `src/include/SymbolSnapshot.mqh` — broker symbol specification + account netting/hedging; OnInit fails when digits/point/tick size/volume step are missing.
- `src/include/TimeframeWatcher.mqh` — one instance per H4/H1/M15: explicit throttled history request for the depth that timeframe needs, history readiness, forming (position 0) vs closed (position 1) separation, one new-bar event per timeframe, unobserved-bar counter.
- `src/include/StatusPanel.mqh` — OBJ_LABEL panel, prefix `velo_t001_`, cleaned in Init and OnDeinit.
- `tools/t001-static-checks.sh`, `tools/t001-check-balance.py`, `tools/t001-check-format-strings.py` — re-runnable static checks; the two Python checkers exit non-zero on failure and the shell script folds that into its own exit code.
- `README.md` — install, compile and log-inspection instructions for MT5.
- `reports/T001-verification.md` — verification record, with observed and untested parts separated per check.

## Verification status
Compilation, independent static checks and MT5 runtime observation are separate evidence from different people. Tested version `763227d`; `src/` and `tools/` are unchanged since.

- COMPILATION (Codex, MetaEditor): 0 errors, 0 warnings. Warning 68 (`#property version` format, seen on `c810f90`) is gone.
- STATIC CHECKS (Codex, independent run): PASS. The balance check was also run on a deliberately broken file and failed as it should. I ran the same checks earlier, including a copy with a missing brace (exit 1) and the real tree (exit 0).
- MT5 RUNTIME (owner, MetaQuotes-Demo, XAUUSD, EUR account, RETAIL_HEDGING, 2026-10-07). Partially observed; no check is marked PASS as a whole:
  - C2 readiness: H4/H1/M15 reached DATA READY. With the H4 minimum temporarily 1000000: H4 LOADING and data NOT READY, H1/M15 READY; back to 200: data READY. NOT tested: download from a terminal with no history. The 2000 ms request throttle was reviewed in code only; its frequency was not measured.
  - C3 new bars: M15 events at 15:30 and 15:45 and H4/H1/M15 at 16:00, with no repeats during the observation. Closed-bar OHLC matched the Data Window for M15 15:45, H1 15:00 and H4 12:00. NOT tested: a run of an hour or longer, the unobserved-bars path.
  - C4 restart: changing inputs gave a stop with "inputs changed", a restart and DATA READY, with no false NEW BAR in the excerpt provided. NOT tested: remove/re-attach, recompile while running, chart close, terminal restart.
  - C5 no trading: Algo Trading off, Trade tab empty, no trade requests in the Journal during the observation. The EA's own log message is not independent proof, and with Algo Trading off the terminal blocks EA orders anyway. The evidence that the EA cannot trade is the absence of trading functions in the code (static check 1).
  - C6 symbol: only three facts from the demo (XAUUSD, EUR, RETAIL_HEDGING). Tauro's specifications are NOT confirmed.
- Not attached to the repo: raw compile log, Journal excerpt, screenshots. The record is built from reports relayed in the conversation.
- The code contains no function able to send, modify or close an order (static check 1, run by me and by Codex).

## Latest handoff
T001 code `763227d` compiled clean in MetaEditor (Codex) and was observed on a demo account (owner). The remaining gaps are listed above and in reports/T001-verification.md section 9, which also maps the result to the five completion-evidence items of the task. This update changed documentation only. The C2 description was corrected: the history-request counter refreshes in the panel, and STATUS is logged only when the state changes.

## Environment
- MetaEditor: used by Codex; not present in the development container.
- MT5 test terminal: MetaQuotes-Demo, XAUUSD, EUR account, RETAIL_HEDGING. MT5 build number not recorded.
- Target broker: Tauro (client wrote XAUUSD.r and a USD account). NOT confirmed: symbol name, digits, tick size/value, contract size, volume min/step, stops level, netting vs hedging. The demo's EUR differs from the client's stated USD; this matters for sizing (Q08).
- Git: the working copy is on branch `claude/t003-h4-bias` (tracks `ea-mt5`, velireci/EA-MT5); the other branches are `claude/amazing-darwin-icpcjd` (T001) and `claude/t002-h4-map` (T002).

## Repository
The project lives in `velireci/EA-MT5` (PRIVATE, verified 2026-10-07 via the GitHub API). It is the only remote of this working copy, and branch `claude/amazing-darwin-icpcjd` tracks it. The default branch is `main` (set by the owner).

`inputs/client-E27N93/` holds the original client submission including four screenshots taken on the client's own phone; `docs/reference/` holds the full strategy analysis. Both are tracked. The repository must stay private, and no public remote may be added to this working copy.

History note: the project started in `velireci/velo`, which was public. The T001 code commit was pushed there before EA-MT5 existed; no client submission and no photos ever reached it. The owner deleted that repository on 2026-10-07. Its earlier commits (`c8038fd` to `235993a`, including the unrelated `MQL5/Experts/MA_Crossover_EA.mq5` and `jessy`) survive as ancestors of this branch in EA-MT5, so nothing was lost.

## Pre-existing files not part of this project
`MQL5/Experts/MA_Crossover_EA.mq5` and `jessy` were in the repository before this project (`jessy` has since been deleted on `main`, commit `91091d2`, not by this agent). `MA_Crossover_EA.mq5` is an unrelated EA that does place real trades (MA crossover). It was not modified and must not be confused with `src/XauUsdFoundation.mq5`.
