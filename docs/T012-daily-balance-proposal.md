# T012 proposal: keeping the balance at the START of the Tirane day (PROPOSAL ONLY, nothing implemented)

Scope: only the persistence and the decision about the balance at the start of the day. It does not touch T011 (manager, position, state files), the result formula, the 80/20 classification or the 2/3 limit, sends no order or cancellation and is not wired into any trading EA.

## What exists and is reused (nothing is copied)
| need | existing piece |
|---|---|
| Tirane day and its [midnight, next midnight) window in UTC, DST included | T009 `SP_Evaluate` through `DH_DayWindow`; `day_key = yyyymmdd` |
| all deals of the day window (any magic, trade and non-trade), dedup, truncation / stability / owner `complete` assertion | `DailyHistory.mqh`: `DH_ReadAndBuild`, `SDhFacts.deals_in_window`, `nontrade_count`, `outside_window`, `complete`, verdict READY/UNKNOWN/BLOCK |
| the form in which the balance reaches the check | `SDbBalance {known, day, amount}` of `DailyBridge.mqh`; `DB_Check` already blocks `BALANCE_START_UNSET` and `BALANCE_DAY_MISMATCH` and calls `DL_Check` unchanged |
| text record, CRC-32, escaping, exact numbers, safe file read / write | primitives `ESC_Crc32`, `ESC_Escape`, `ESC_Fnum`, `ESC_ParseInt/Double`, `ESF_ReadAll/WriteAll/Exists` (read-only use; the T011 headers stay untouched) |
Not covered today and therefore the only new thing: a small record of "account + Tirane day + balance + how it was obtained", and the rule that decides when a balance may be called the start-of-day balance. Proposed as ONE small header `DailyBalanceStore.mqh` (pure codec + decision core, thin file layer) and one read-only diagnostic script; no change to DailyHistory / DailyBridge / DailyLimits / the preview.

## What the terminal can prove and what stays the owner's statement
| item | status |
|---|---|
| login, server, currency of the account (`ACCOUNT_LOGIN`, `ACCOUNT_SERVER`, `ACCOUNT_CURRENCY`) | TERMINAL (read) |
| the Tirane day D of the instant of the read (T009) | TERMINAL + T009 rules |
| the balance NOW (`ACCOUNT_BALANCE`, two equal reads) | TERMINAL; it is the balance at the START of day D only under the rule below |
| "no deal of any kind in [midnight D, now] and the history was readable, not truncated, stable" | TERMINAL (`deals_in_window == 0`, `outside_window` irrelevant, READY, no truncation, two equal reads) |
| the history held by the terminal is the full server history | OWNER (existing `history_complete_asserted`); the terminal cannot prove it |
| the broker server offset / DST of the deal times | OWNER input (existing) |
| what "balance" means for the -2% rule (balance, equity, credit) | OWNER / CLIENT decision, not taken here |
| a balance typed by the owner as the start-of-day balance | OWNER statement; stored with the source `OWNER_ASSERTED`, never promoted |

## The rule (one sentence)
A balance read at instant t of Tirane day D is stored as the start-of-day balance of D ONLY when the history window [midnight D, t] is proven empty of every deal (trade and non-trade) with the existing READY + `complete` facts and two equal balance reads; otherwise it is a mid-day observation, is NOT stored and the answer stays UNKNOWN. Nothing is ever reconstructed by subtracting profits from the current balance.

## Decision table (pure core `DBS_Decide`; output = `SDbBalance` + an action + a reason)
1. identity of the account unreadable / balance unreadable, non-finite, <= 0 or two reads differ -> UNKNOWN, no write.
2. stored file for (account, day D): valid, same login + server, day D -> USE_STORED (restart inside the day never changes it; the current balance is ignored, not even compared).
3. file missing -> continue to 5. File of another day (D-1 ...) -> ignored as if missing, never copied, never carried; its counters do not exist in the record.
4. file damaged (CRC, truncation, bad field, version, day in the future, creation instant outside day D) or of another account -> BLOCK, nothing written, nothing used; only the owner removes it.
5. no usable file: history verdict not READY / not `complete` / truncated / unstable -> UNKNOWN. READY and `deals_in_window == 0` -> CREATE source `WINDOW_EMPTY` (written once, read back, then used). READY and `deals_in_window > 0` -> UNKNOWN `MID_DAY_NOT_PROVEN` (no write) unless the owner supplied an explicit amount for day D -> CREATE source `OWNER_ASSERTED`.
6. a failed write or read-back -> UNKNOWN (the value is not used from memory either).
A terminal closed at midnight and restarted at 09:00 with night deals therefore ends UNKNOWN (or OWNER_ASSERTED if the owner states it). The record is write-once per account and day: `VELO_T012_BALANCE_<login>_<yyyymmdd>.txt` (no overwrite, no deletion by code; old days stay as small files; retention is the owner's).
Record: header, version, login, server, currency, day_key, amount (12-decimal exact), source (`WINDOW_EMPTY` / `OWNER_ASSERTED`), creation instant (UTC), CRC-32.

## Limits (not hidden)
* `WINDOW_EMPTY` assumes the terminal's history is synchronized and that a start-of-day balance changes only through deals (deposits, withdrawals, credits, charges, corrections are deals; a broker adjustment that creates no deal would be invisible). Both are statements about the broker; compile and MT5 behaviour of `HistorySelect` after a long closure are UNVERIFIED.
* The balance in the record is `ACCOUNT_BALANCE`; whether the client's rule uses balance, equity or credit is open and not decided here.
* One terminal only; no protection between terminals; a manual edit of the file is detected only by the CRC.
* Equity, floating profit and pending orders are not part of it.

## Test criteria (before the implementation; Python reference + MQL5 mirror + static checks)
1. Codec: round trip, CRC, truncation / bad field / bad enum / old version / negative or zero or non-finite amount / day in the future / creation instant outside the day -> rejected.
2. Decision rows (each with day, account, history verdict and facts, balance reads, stored file state): the 6 rules above, incl. empty window at 00:00:05 and at 15:00, window with one trade deal, with only a balance deal, with a deposit, facts of day D-1 against a record of D (`BALANCE_DAY_MISMATCH` stays in `DB_Check`), record of D-1 read on D, restart inside the day (amount unchanged even if the current balance differs), another login or server, damaged file, write failure, unreadable account, second call idempotent.
3. Day change inside one run: the new day decides alone; nothing of the old day is carried (no counters exist in the record).
4. Midnight-closure case: night deals + restart -> UNKNOWN, and a static check that the store never reads `candidate_*`, `nontrade_profit`, `nontrade_commission` or any profit field (no subtraction).
5. Mutants: balance accepted with deals in the window; stored value replaced by the current balance; old day accepted; other account accepted; damaged file accepted; overwrite of an existing file; owner value promoted to WINDOW_EMPTY; day taken from the record without the check; unstable reads accepted.
6. Static: no trading call, no `FileDelete` / `FileMove`, no policy identifier (result formula, classification, limit 2/3), no T011 file touched, ASCII, balance of braces.
7. MQL5: `T012_BalanceStoreTest.mq5` with the same rows (fixture block generated and compared) and a sandbox file; owner diagnostic script reads the live account and prints the decision without writing unless explicitly enabled (default read-only).
Completion: Python + static green, Codex compile 0/0, owner MT5 test run, one read-only diagnostic on the demo account; T012 stays open for the formula, classification, 2/3, `complete` assertion and the permit wiring.
