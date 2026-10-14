# T003 internal-liquidity prototype (ISOLATED, NOT product, NOT a test of the product)

Revision 13 PROPOSAL, prototype round (tasks/T003-h4-bias-change.md section 15.7). `proto_liq.py` loads a COPY of
`tests/t003_reference_test.py` in memory, patches the interior-liquidity step (per-level, historical consumption) and
leaves every product file untouched. Nothing here is imported by the product, the visual EA or the static checks.

- `demo_liq.py`: synthetic cases (no data needed): close breaks a lower level while a wick sweeps a higher one;
  touch versus strict crossing; the protecting level touched versus exceeded. Run: `python3 reports/t003-liq-prototype/demo_liq.py`
- `cmp_liq.py <csv>`, `final_liq.py <csv>`, `resurrect.py <csv>`: comparison with the current model on a candle CSV
  written by the EA (InpExportCandles). The owner's real CSV is PRIVATE and is NOT in the repository; these scripts
  need it and cannot be re-run from the repository alone.
