# Current project state

> T002 (branch `claude/t002-h4-map`, draft PR velireci/EA-MT5#2 against the T001 branch, base head `56c9570`): H4 map visual prototype, NOT complete. Evidence by source, tested code `97ce7b4`: Codex compiled `XauUsdH4Map.mq5` and `T002_LogicTest.mq5` with 0 errors, 0 warnings (relayed); the owner ran `T002_LogicTest` in MT5: 208 passed, 0 failed (relayed); the owner ran the historical mode at AsOfTime 2026.10.05 12:00:00 server time (HISTORICAL REVIEW, last candle 08:00-12:00, close 4166.59, MIXED) and at 2026.10.04 12:00 (a Sunday: last candle 2026.10.02 20:00, close 4147.62; after a restart the same 70 swings and 53 FVGs; no duplicates in the visible part of the object list, full list not checked; some labels overlap the panel and candles) - all relayed by Codex, screenshots not attached, not run by me. I ran Python model tests 197/197 and the static checks; Codex verified the check-15 fix in `a92b033` (relayed). Still open for T002: more weekend/gap as-of cases, full duplicate-object check after reload, label readability, Tauro vs TradingView candle alignment. Direction rule (swing 2/2) unchanged and PROPOSED. See reports/T002-verification.md sections 11-13. PR #1 not merged.

Updated: 2026-10-13 (Europe/Tirane)

- Phase: T001 foundation compiled by Codex and partly observed in MT5 (PR #1 open); T002 H4 map prototype compiled and partly observed (PR #2 draft); T003 H4 direction-change specification drafted (revision 3) from the client's 2026-10-13 text clarifications and BUY example (including the closing statement E6), with Codex's remarks applied (documents only, not implemented). Awaiting Codex's review of the specification and the owner's decisions.
- Current task: documents only: tasks/T003-h4-bias-change.md (DRAFT rev. 3), docs/STRATEGY_SPEC.md and docs/DECISIONS.md separate client statements (S1-S6, BUY example E1-E6), earlier authorised decisions, proposals (P1-P13) and open questions (F1-F8). PR velireci/EA-MT5#1 (T001, `main`) is open and NOT merged; tested version `763227d494115126a801d7e9cebe48a49977eb76`. T003 is NOT started; nothing in it is implemented or tested, and neither T002 nor T003 is complete.
- Branch: `claude/t002-h4-map` (PR #2). No agent owns an active edit; the T001 branch `claude/amazing-darwin-icpcjd` is unchanged.
- Source: inputs/client-E27N93/pergjigjet.json and associated TXT/photos.
- Strategy review completed; no strategy logic implemented and none invented.
- Client approval: broad questionnaire answers supplied; disputed/undefined rules remain open.
- Current strategy dependency: Q01-Q04. Client clarifications of 2026-10-13 (S1-S6, BUY example E1-E6) are in DECISIONS.md; E6 adds BUY-side evidence for new H4 FVG -> return/touch -> M15 break (entry at the M15 FVG). Screenshots are illustrations (not stored in the repo); text takes priority; no price or BOS count is a rule; the example's target (last HH) is not a universal rule; internal liquidity is not the structural level. Still open: M5 role, policy below 2R.
- Next owner action: have Codex review tasks/T003-h4-bias-change.md rev. 3; decide or defer F1-F8 (exact time definition of the new FVG after the wick, M5/M15, policy below 2R, positions already open, ERL selection and reconfirmation validity, whether the intrabar block proposed by Codex is wanted, how an entry module treats LIMITED_BY_HISTORY, whether a sweep of internal liquidity needs the same HOLD and new-FVG reconfirmation as a structural wick); supply the candles the client marked for the section-10 visual comparison; decide about PR #1 and PR #2.
- Next developer action: none until Codex's review of the T003 specification and the owner's go. No MQL5, `src/` or `tools/` change was made in this documentation step.

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
- Git: branch `claude/amazing-darwin-icpcjd`, tracks `ea-mt5` (velireci/EA-MT5).

## Repository
The project lives in `velireci/EA-MT5` (PRIVATE, verified 2026-10-07 via the GitHub API). It is the only remote of this working copy, and branch `claude/amazing-darwin-icpcjd` tracks it. The default branch is `main` (set by the owner).

`inputs/client-E27N93/` holds the original client submission including four screenshots taken on the client's own phone; `docs/reference/` holds the full strategy analysis. Both are tracked. The repository must stay private, and no public remote may be added to this working copy.

History note: the project started in `velireci/velo`, which was public. The T001 code commit was pushed there before EA-MT5 existed; no client submission and no photos ever reached it. The owner deleted that repository on 2026-10-07. Its earlier commits (`c8038fd` to `235993a`, including the unrelated `MQL5/Experts/MA_Crossover_EA.mq5` and `jessy`) survive as ancestors of this branch in EA-MT5, so nothing was lost.

## Pre-existing files not part of this project
`MQL5/Experts/MA_Crossover_EA.mq5` and `jessy` were in the repository before this project. `MA_Crossover_EA.mq5` is an unrelated EA that does place real trades (MA crossover). It was not modified and must not be confused with `src/XauUsdFoundation.mq5`.
