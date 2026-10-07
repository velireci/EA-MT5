# Current project state

Updated: 2026-10-07 (Europe/Tirane)

- Phase: T001 foundation implemented in code; compilation and MT5 runtime NOT YET VERIFIED.
- Current task: tasks/T001-foundation.md — code complete, two review rounds applied; awaiting a recompile of the current code and the MT5 runtime checks. Open as PR velireci/EA-MT5#1 into main. Do not merge and do not start T002 yet.
- Branch: `claude/amazing-darwin-icpcjd`. Next writer: Codex (read-only review). No agent owns an active edit.
- Source: inputs/client-E27N93/pergjigjet.json and associated TXT/photos.
- Strategy review completed; no strategy logic implemented and none invented.
- Client approval: broad questionnaire answers supplied; disputed/undefined rules remain open.
- Current strategy dependency: Q01-Q04 (direction, H4 zone, return, M15 confirmation). Not required to close T001.
- Next owner action: recompile (C1, report section 5A), then run C2-C6 in MT5 (section 5B), writing the actual results into the report.
- Next developer action: after C1-C6, hand the changed files and the report to Codex; then assign T002.

## Files added in T001
- `src/XauUsdFoundation.mq5` — main EA. OnInit/OnDeinit/OnTick/OnTimer, configurable magic (stored, unused), symbol resolution, status logging on change only, chart panel.
- `src/include/SymbolSnapshot.mqh` — broker symbol specification + account netting/hedging; OnInit fails when digits/point/tick size/volume step are missing.
- `src/include/TimeframeWatcher.mqh` — one instance per H4/H1/M15: explicit throttled history request for the depth that timeframe needs, history readiness, forming (position 0) vs closed (position 1) separation, one new-bar event per timeframe, unobserved-bar counter.
- `src/include/StatusPanel.mqh` — OBJ_LABEL panel, prefix `velo_t001_`, cleaned in Init and OnDeinit.
- `tools/t001-static-checks.sh`, `tools/t001-check-balance.py`, `tools/t001-check-format-strings.py` — re-runnable static checks; the two Python checkers exit non-zero on failure and the shell script folds that into its own exit code.
- `README.md` — install, compile and log-inspection instructions for MT5.
- `reports/T001-verification.md` — verification record.

## Verification status
Compilation and MT5 runtime testing are separate evidence and are reported separately.

- COMPILATION: Codex compiled `c810f90` and got 0 errors, 1 warning (warning 68, `#property version` format). That warning is fixed in this round. The CURRENT code is UNCOMPILED — the fixes touched `src/XauUsdFoundation.mq5` and `src/include/TimeframeWatcher.mqh` after `c810f90`. Expected on recompile: 0 errors, 0 warnings. My own container has no MetaEditor (`find / -iname 'metaeditor*'` empty), so I cannot produce this evidence myself.
- MT5 RUNTIME TESTS: NONE have been run, on any commit. Readiness during history load, new-bar events, clean restart, and the actual absence of trading activity on an account are all unverified. A clean compile says nothing about any of them.
- STATIC CHECKS: pass on the current code, `bash tools/t001-static-checks.sh`, exit 0. Codex found that check 2 printed FAIL without affecting the exit code; it is fixed and tested with a deliberately unbalanced copy (exit 1, STATIC CHECKS FAILED) as well as the real tree (exit 0).
- INDEPENDENT STATIC REVIEW: round 1 raised 4 defects, 2 questions, 2 untested risks — all fixed. Round 2 (Codex, with compilation) raised 4 items — all fixed. Details in reports/T001-verification.md section 6.
- No trading order was sent, modified or closed; the code contains no function capable of it.

## Latest handoff
Foundation EA and three helper modules written, statically checked and independently reviewed; all review findings fixed. The EA observes XAUUSD H4/H1/M15 data and reports readiness; it contains no strategy and no order functions. Compilation and runtime evidence are the owner's next step (C1-C6).

## Environment
- MetaEditor path: not present in the development container; owner compiles locally (F7, or `metaeditor64.exe /compile:...`).
- MT5 data folder: not discovered yet; owner uses File -> Open Data Folder.
- Broker/account details: unverified. Client wrote Tauro / XAUUSD.r / USD; confirm the exact symbol name, digits, point, tick size/value, contract size, volume min/step, stops level and netting vs hedging from the EA's OnInit log (check C6).
- Git baseline: branch `claude/amazing-darwin-icpcjd`.

## Repository
The project lives in `velireci/EA-MT5` (PRIVATE, verified 2026-10-07 via the GitHub API). It is the only remote of this working copy, and branch `claude/amazing-darwin-icpcjd` tracks it.

`inputs/client-E27N93/` holds the original client submission including four screenshots taken on the client's own phone; `docs/reference/` holds the full strategy analysis. Both are tracked. The repository must stay private, and no public remote may be added to this working copy.

History note: the project started in `velireci/velo`, which was public. The T001 code commit was pushed there before EA-MT5 existed; no client submission and no photos ever reached it. The owner deleted that repository on 2026-10-07. Its earlier commits (`c8038fd` to `235993a`, including the unrelated `MQL5/Experts/MA_Crossover_EA.mq5` and `jessy`) survive as ancestors of this branch in EA-MT5, so nothing was lost.

Repository setting to confirm: EA-MT5's default branch is currently `claude/amazing-darwin-icpcjd`, because that was the first branch pushed to an empty repository. Decide whether to make `main` the default before opening pull requests.

## Pre-existing files not part of this project
`MQL5/Experts/MA_Crossover_EA.mq5` and `jessy` were in the repository before this project. `MA_Crossover_EA.mq5` is an unrelated EA that does place real trades (MA crossover). It was not modified and must not be confused with `src/XauUsdFoundation.mq5`.
