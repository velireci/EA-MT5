# T010 verification - 2026-10-14 (Claude, sole writer, base 8c562fe)

Evidence by source. Executed here: Python tests and static checks (below). Relayed: nothing for T010. UNVERIFIED: MetaEditor compile, MT5 run of T010_FiltersTest and the preview, live calendar behaviour, Strategy Tester behaviour, MQL5 documentation (site unreachable from the sandbox; see tasks/T010-news-spread-filters.md).

Executed here (from tests/): python3 -m unittest test_t010_filters test_t009_session test_t008_broker_loss test_t007_planning -> Ran 78 tests, OK (test_t010_filters = 19 tests: every fixture row, second-level boundaries, currency/importance, unknown never clear, spread noise vs real 0.001 excess, unset sentinel, end-to-end with the unchanged T007 permit, 17 mutation checks, MQL fixture block equality, header constant parity).
Executed here: bash tools/t010-static-checks.sh -> ALL PASS (no trading API, no persistence, Calendar* confined to ReadUsdCalendar, tester guard first, no TimeGMT/TimeLocal in the news path, one quote read, T001-T009 and checklist/progress files identical to 8c562fe, 10 negative controls).
Not run: MetaEditor compile (UNVERIFIED, EA and T010_FiltersTest), MT5 execution, live calendar, Strategy Tester. MQL5 documentation could not be fetched; calendar API usage is from memory.
