# T003 internal-liquidity prototype (ISOLATED, NOT product, NOT a test of the product)

Revision 13 PROPOSAL, prototype round (tasks/T003-h4-bias-change.md section 15.7). `proto_liq.py` loads a COPY of
`tests/t003_reference_test.py` in memory, patches the interior-liquidity step (per-level, historical consumption) and
leaves every product file untouched. Nothing here is imported by the product, the visual EA or the static checks.

- `demo_liq.py`: synthetic cases (no data needed): close breaks a lower level while a wick sweeps a higher one;
  touch versus strict crossing; the protecting level touched versus exceeded. Run: `python3 reports/t003-liq-prototype/demo_liq.py`
- `cmp_liq.py <csv>`, `final_liq.py <csv>`, `resurrect.py <csv>`: comparison with the current model on a candle CSV
  written by the EA (InpExportCandles). The owner's real CSV is PRIVATE and is NOT in the repository; these scripts
  need it and cannot be re-run from the repository alone.

REVISION 14 (2026-10-14): the rule of this prototype is now IMPLEMENTED in `tests/t003_reference_test.py` and `src/include/H4Bias.mqh`
(tasks/T003-h4-bias-change.md section 16; a technical proposal, not validated by the client). Consequences for these scripts:
- `baseline_t003_reference_d7a201f.py` is a FROZEN copy of `tests/t003_reference_test.py` at commit d7a201f (the single-candidate selector).
  `proto_liq.py` now patches THIS copy (the product file no longer contains the text it patched) and registers it unpatched as
  `sys.modules['t003_baseline']`; `cmp_liq.py` and `final_liq.py` use that module as "current" (= before revision 14).
- `demo_liq.py` prints three columns (baseline, prototype, implementation) and `AGREE` / `DIFFER` per demo (exit 1 on a difference; the only
  expected textual difference is the superset `restart=` field of INTERNAL_SWEEP, which the comparison drops).
- `fuzz_equiv.py [seeds] [bars]`: random series, prototype versus implementation, per bar (bias, phase, level, setup id, LI key) and per event
  (type, bar, ref, detail without `restart=`). Synthetic data only.

