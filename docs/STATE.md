# Current project state

Updated: 2026-10-13 (Europe/Tirane)

## Resume here
- T003 revision 6 is in the WORKING TREE of branch `claude/t003-h4-bias` (PR #3), NOT committed or pushed: two review findings of `72b2557` fixed (anchor by existing bars; level frozen during RECONFIRMED(INTERNAL) with thaw and re-derivation from the following bar). Owner-relayed for `72b2557` only: Codex compiled 0/0 and the owner ran 166 passed, 0 failed, 5 deferred; that does not cover the corrected code. Revision 6 MetaEditor compile and MT5 run: UNVERIFIED.
- Next step: the parent reviews and commits revision 6; then Codex compiles `src/include/H4Bias.mqh` and `src/tests/T003_LogicTest.mq5` (static expectation 234 passed, 0 failed, 5 deferred, not a result), runs it in MT5 and reviews the 20 `AMBIGUITY` markers and the contradictions in `reports/T003-verification.md` (notably: CONFLICT is unreachable under the current candidate definitions).
- The owner is waiting on the log of the first NEW H4 candle in LIVE for the technical closure of T002 (see the T002 state below).
- Do not start: the visual T003 EA, the intrabar overlay P12, the target P13, M5/M15, orders or position handling. No merge of PR #1, #2 or #3.

## Branches and PRs (verified from the GitHub API and git on 2026-10-13)
- PR #1 (T001): branch `claude/amazing-darwin-icpcjd`, head `56c9570`, base `main`, open, NOT merged. Tested version `763227d`.
- PR #2 (T002), draft: branch `claude/t002-h4-map`, head `dd571f6`, base the T001 branch. Commit `6a8c0c6` (T002_SetupScan.mq5 and docs/T002-setup-scan.md) is an ancestor of this head, so the SetupScan IS delivered in PR #2 (its body already says so; no correction needed). Tested EA code is `97ce7b4`; later commits are docs, one tools fix (check 15) and the scan script.
- PR #3 (T003), draft: branch `claude/t003-h4-bias`, head `08368d8` (code tested by Codex/owner at `72b2557`; revision 6 changes are uncommitted in the working tree), base `claude/t002-h4-map` (`dd571f6`).
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
- Specification: tasks/T003-h4-bias-change.md revision 6 (client statements S1-S6 and BUY example E1-E6 kept apart from proposals P1-P14). Client statements are in docs/DECISIONS.md.
- Implemented, first limited round only: pure logic `src/include/H4Bias.mqh`, MQL5 test script `src/tests/T003_LogicTest.mq5`, Python model `tests/t003_reference_test.py`, `tools/t003-static-checks.sh`. No T001/T002 file changed. Not implemented: visual EA, intrabar overlay P12, target P13, M5/M15, orders, positions; tests 9, 18, 20 and the drawing tests are DEFERRED (printed as DEFERRED, never PASS).
- Revision 6 results (mine, this environment): Python model tests 240 passed, 0 failed, 5 deferred; T003 static checks PASS (62 PASS lines, new check 12b and negative controls 13s/13t); T002 and T001 static checks PASS, T002 model tests 197 passed. These are model and static evidence only.
- Pending: MetaEditor compilation and MT5 run of the revision 6 code (UNVERIFIED) and Codex's review. The 20 interpretations (`AMBIGUITY n` markers; 1, 5, 19 changed and 20 new in revision 6) are in reports/T003-verification.md section 5, the contradictions in section 6. The thaw/re-derivation rule is a technical proposal in the task file (P14), not a client statement.

## Open decisions and next owner actions
- Have Codex review T003 and answer or defer F1-F8 (see tasks/T003-h4-bias-change.md section 8): exact time definition of the new FVG after the wick, M5/M15, policy below 2R, positions already open, ERL selection and reconfirmation validity, the intrabar block proposed by Codex, entries while LIMITED_BY_HISTORY (technical proposal), interior liquidity.
- Supply the candles the client marked for the section-10 visual comparison; send the LIVE new-candle log for T002; decide about PR #1, PR #2, PR #3 and the moved `main`.
- Client screenshots are illustrations (not stored in the repository); text clarifications take priority; no price or BOS count is a rule.

## Basics
- Source: inputs/client-E27N93/pergjigjet.json and associated TXT/photos. No strategy logic was invented; disputed or undefined rules remain open (Q01-Q12).
- Next developer action: none until the parent commits revision 6, Codex compiles and reviews T003 and the owner gives the go for the later rounds.

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
