# Current project state

Updated: 2026-10-07 (Europe/Tirane)

- Phase: T001 foundation implemented in code; compilation and MT5 runtime NOT YET VERIFIED.
- Current task: tasks/T001-foundation.md — code complete, awaiting MetaEditor/MT5 evidence and Codex review.
- Branch: `claude/amazing-darwin-icpcjd`. Next writer: Codex (read-only review). No agent owns an active edit.
- Source: inputs/client-E27N93/pergjigjet.json and associated TXT/photos.
- Strategy review completed; no strategy logic implemented and none invented.
- Client approval: broad questionnaire answers supplied; disputed/undefined rules remain open.
- Current strategy dependency: Q01-Q04 (direction, H4 zone, return, M15 confirmation). Not required to close T001.
- Next owner action: run checks C1-C6 in reports/T001-verification.md section 5 on MT5 and write the actual results there.
- Next developer action: after C1-C6, hand the changed files and the report to Codex; then assign T002.

## Files added in T001
- `src/XauUsdFoundation.mq5` — main EA. OnInit/OnDeinit/OnTick/OnTimer, configurable magic (stored, unused), symbol resolution, status logging on change only, chart panel.
- `src/include/SymbolSnapshot.mqh` — broker symbol specification + account netting/hedging; OnInit fails when digits/point/tick size/volume step are missing.
- `src/include/TimeframeWatcher.mqh` — one instance per H4/H1/M15: history readiness, forming (position 0) vs closed (position 1) separation, one new-bar event per timeframe, unobserved-bar counter.
- `src/include/StatusPanel.mqh` — OBJ_LABEL panel, prefix `velo_t001_`, cleaned in Init and OnDeinit.
- `tools/t001-static-checks.sh`, `tools/t001-check-format-strings.py` — re-runnable static checks.
- `README.md` — install, compile and log-inspection instructions for MT5.
- `reports/T001-verification.md` — verification record.

## Verification status
- VERIFIED (static, re-runnable via `bash tools/t001-static-checks.sh`): no order/trading API in code; balanced syntax; include guards and include paths; no MQL4 API; all four MQL5 handlers present; every format string matches its argument count; source is ASCII only. Result: ALL STATIC CHECKS PASSED.
- VERIFIED (independent read-only review, static): candle timing, history-readiness gating, one-event-per-bar, init/deinit lifecycle, MQL5 API usage. The review raised 4 defects, 2 questions and 2 untested risks; all 8 were confirmed in code and fixed. Details in reports/T001-verification.md section 6.
- UNVERIFIED: compilation (no MetaEditor in the development container; `find / -iname 'metaeditor*'` empty), and all MT5 runtime behavior — readiness during history load, new-bar events on a live chart, clean restart without log spam, and the absence of trading activity on an account.
- No trading order was sent, modified or closed; the code contains no function capable of it.

## Latest handoff
Foundation EA and three helper modules written, statically checked and independently reviewed; all review findings fixed. The EA observes XAUUSD H4/H1/M15 data and reports readiness; it contains no strategy and no order functions. Compilation and runtime evidence are the owner's next step (C1-C6).

## Environment
- MetaEditor path: not present in the development container; owner compiles locally (F7, or `metaeditor64.exe /compile:...`).
- MT5 data folder: not discovered yet; owner uses File -> Open Data Folder.
- Broker/account details: unverified. Client wrote Tauro / XAUUSD.r / USD; confirm the exact symbol name, digits, point, tick size/value, contract size, volume min/step, stops level and netting vs hedging from the EA's OnInit log (check C6).
- Git baseline: branch `claude/amazing-darwin-icpcjd`.

## Repositories: client material belongs in the private one only
Two remotes exist for this working copy (verified 2026-10-07 via the GitHub API):

| Remote | Repository | Visibility | Holds client material |
|---|---|---|---|
| `ea-mt5` | velireci/EA-MT5 | PRIVATE | yes - this is the project home |
| `origin` | velireci/velo | PUBLIC | no - never push client material here |

`inputs/client-E27N93/` (the original submission, including screenshots from the client's own phone) and `docs/reference/` (the full strategy analysis) are tracked and pushed to `ea-mt5` only.

Branch `claude/amazing-darwin-icpcjd` tracks `ea-mt5`. Before any push, confirm the target remote.

OPEN ITEM for the owner: the T001 code commit was pushed to the public `velireci/velo` before EA-MT5 existed. It carries no client submission and no photos, but `docs/STRATEGY_SPEC.md`, `docs/OPEN_QUESTIONS.md` and `tasks/` do summarise the client's method and are publicly readable there. Decide whether to delete branch `claude/amazing-darwin-icpcjd` from velo, or make velo private as well.

## Pre-existing files not part of this project
`MQL5/Experts/MA_Crossover_EA.mq5` and `jessy` were in the repository before this project. `MA_Crossover_EA.mq5` is an unrelated EA that does place real trades (MA crossover). It was not modified and must not be confused with `src/XauUsdFoundation.mq5`.
