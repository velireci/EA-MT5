#!/bin/bash
# Static checks for the T006 pure position-sizing files.
#
# These are NOT a compiler, NOT an MT5 run. They prove only what can be read from the source text: no trading API,
# no quote / tick / symbol / account / series / clock access, no hidden 0.01 step or 10-lot cap literal, required contract
# labels present in code, MQL5/Python parity (statuses, reason tags in the same first-failure order, numeric constants,
# round-down and never-exceed expressions, limit order), balanced syntax, format strings, ASCII, resolvable includes, and
# that T001-T005 source, tests and tools are byte-identical to the T005 integration commit. Each checker is shown to fail
# on a mutated copy (negative controls). MetaEditor compilation and the MT5 run are UNVERIFIED.
#
# Usage: bash tools/t006-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=25dbb10
MOD=src/include/PositionSizing.mqh
TST=src/tests/T006_SizingTest.mq5
REF=tests/t006_sizing_reference.py
ALL="$MOD $TST"
CHK="python3 -I tools/t006-static-check.py"

echo "=== S1: files exist ==="
for f in $ALL $REF tests/t006_sizing_fixtures.py tests/test_t006_sizing.py tools/t006-static-check.py; do
  [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }
done

echo "=== S2: no trading API, no quote/tick/symbol/account/series/clock, no hidden defaults ==="
out=$($CHK trading $ALL) && echo "  PASS no trading API in module and test" || { echo "$out"; echo "  FAIL trading API present"; FAIL=1; }
out=$($CHK nofeed $ALL) && echo "  PASS no quote, tick, symbol, account, indicator, series or clock access" || { echo "$out"; echo "  FAIL live input"; FAIL=1; }
out=$($CHK nodefaults $MOD $REF) && echo "  PASS no hidden 0.01 step or 10-lot cap literal in module and reference" || { echo "$out"; echo "  FAIL hidden default"; FAIL=1; }

echo "=== S3: contract labels in the module and reference, parity, sizing guards ==="
out=$($CHK contract $MOD $REF) && echo "  PASS headers keep the contract; labels are returned by code" || { echo "$out"; echo "  FAIL contract text"; FAIL=1; }
out=$($CHK parity $MOD $REF) && echo "  PASS status enum, reason tags (same first-failure order), constants and labels equal" || { echo "$out"; echo "  FAIL parity"; FAIL=1; }
out=$($CHK guards $MOD $REF) && echo "  PASS round-down / never-exceed expressions equal in MQL5 and Python; no ceil; limits min -> max -> cap" || { echo "$out"; echo "  FAIL sizing guards"; FAIL=1; }

echo "=== S4: balance, format strings, includes, ASCII ==="
python3 tools/t001-check-balance.py $ALL || FAIL=1
python3 - $ALL <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $ALL; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
for f in $ALL $REF tests/t006_sizing_fixtures.py tests/test_t006_sizing.py tools/t006-static-check.py tools/t006-static-checks.sh; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every T006 file"

echo "=== S5: T001-T005 source, tests and tools unchanged versus $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  PATHS="src/include/H4Structure.mqh src/include/H4Bias.mqh src/include/H4BiasLayers.mqh src/include/H4BiasDrawer.mqh src/include/H4MapDrawer.mqh src/include/StatusPanel.mqh src/include/SymbolSnapshot.mqh src/include/TimeframeWatcher.mqh src/include/M15Confirmation.mqh src/include/H4M15Bridge.mqh src/include/M15SwingProposal.mqh src/include/M15Timeline.mqh src/include/H4TouchContext.mqh src/XauUsdFoundation.mq5 src/XauUsdH4Map.mq5 src/XauUsdH4Bias.mq5 src/XauUsdM15Observer.mq5 src/tests/T002_LogicTest.mq5 src/tests/T002_SetupScan.mq5 src/tests/T003_LogicTest.mq5 src/tests/T003_LayersTest.mq5 src/tests/T004_LogicTest.mq5 src/tests/T004_SelectorTest.mq5 src/tests/T004_TimelineTest.mq5 src/tests/T004_OrdinaryTest.mq5 tests/t002_reference_test.py tests/t003_reference_test.py tests/t003_explore_synthetic.py tests/t003_replay_csv.py tests/t003_structural_level_diag.py tests/t004_reference.py tests/t004_selector_reference.py tests/t004_timeline_reference.py tests/t004_ordinary_reference.py tests/t004_ordinary_fixtures.py tests/test_t004.py tests/test_t004_selector.py tests/test_t004_timeline.py tests/test_t004_ordinary.py tools/t001-static-checks.sh tools/t001-check-balance.py tools/t001-check-format-strings.py tools/t002-static-checks.sh tools/t003-static-checks.sh tools/t003-visual-static-checks.sh tools/t003-visual-check.py tools/t004-static-checks.sh tools/t004-static-check.py src/include/TradeGeometry.mqh src/tests/T005_GeometryTest.mq5 tests/t005_geometry_reference.py tests/t005_geometry_fixtures.py tests/test_t005_geometry.py tools/t005-static-checks.sh tools/t005-static-check.py"
  for p in $PATHS; do
    [ -e "$p" ] || { echo "  FAIL $p missing"; FAIL=1; continue; }
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S6: negative controls (each checker must fail for the intended reason) ==="
mut() {  # mut SRC DST OLD NEW : exit 3 if OLD absent
  python3 -I - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding='ascii').read()
if old not in t:
    sys.exit(3)
open(dst, 'w', encoding='ascii').write(t.replace(old, new, 1))
PYEOF
}
neg() {  # neg LABEL CHECK SRC OLD NEW SUBSTRING [REF]  (SRC is the mutated module; REF the unmodified second file)
  local label="$1" chk="$2" src="$3" old="$4" new="$5" sub="$6" extra="${7:-}" f="$NEG/$(basename "$3")"
  if ! mut "$src" "$f" "$old" "$new"; then echo "  FAIL $label: mutation target absent (vacuous control)"; FAIL=1; return; fi
  local out rc
  if [ -n "$extra" ]; then out=$($CHK "$chk" "$f" "$extra" 2>&1); rc=$?; else out=$($CHK "$chk" "$f" 2>&1); rc=$?; fi
  if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$sub"; then echo "  PASS $label (detected: $sub)"
  else echo "  FAIL $label: rc=$rc output: $out"; FAIL=1; fi
}
negpy() {  # negpy LABEL CHECK OLD NEW SUBSTRING : mutated Python reference, unmodified module first
  local label="$1" chk="$2" old="$3" new="$4" sub="$5" f="$NEG/ref_mut.py"
  if ! mut $REF "$f" "$old" "$new"; then echo "  FAIL $label: mutation target absent (vacuous control)"; FAIL=1; return; fi
  local out rc
  out=$($CHK "$chk" $MOD "$f" 2>&1); rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$sub"; then echo "  PASS $label (detected: $sub)"
  else echo "  FAIL $label: rc=$rc output: $out"; FAIL=1; fi
}
neg "order API in the module" trading $MOD "   return(true);
  }

#endif" "   OrderSend(req,res); return(true);
  }

#endif" "OrderSend"
neg "trade class in the module" trading $MOD "bool PS_Compute(" "CTrade trade; bool PS_Compute(" "CTrade"
neg "symbol read in the module" nofeed $MOD "double loss_per_lot=(double)stop_ticks*tick_value;" "double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE); double loss_per_lot=(double)stop_ticks*tick_value;" "SymbolInfoDouble"
neg "account read in the module" nofeed $MOD "double loss_per_lot=(double)stop_ticks*tick_value;" "double eq=AccountInfoDouble(ACCOUNT_EQUITY); double loss_per_lot=(double)stop_ticks*tick_value;" "AccountInfoDouble"
neg "wall clock in the module" nofeed $MOD "double loss_per_lot=(double)stop_ticks*tick_value;" "datetime now=TimeCurrent(); double loss_per_lot=(double)stop_ticks*tick_value;" "TimeCurrent"
neg "hidden 0.01 step in the module" nodefaults $MOD "long cap_steps=(long)MathFloor(cap_x+PS_CAP_ULPS*DBL_EPSILON*MathMax(1.0,cap_x));" "long cap_steps=(long)MathFloor(cap_x+PS_CAP_ULPS*DBL_EPSILON*MathMax(1.0,cap_x)); double hidden_step=0.01;" "hidden default literal 0.01" $REF
neg "hidden 10-lot cap in the module" nodefaults $MOD "long cap_steps=(long)MathFloor(cap_x+PS_CAP_ULPS*DBL_EPSILON*MathMax(1.0,cap_x));" "long cap_steps=(long)MathFloor(cap_x+PS_CAP_ULPS*DBL_EPSILON*MathMax(1.0,cap_x)); double hidden_cap=10.0;" "hidden default literal 10.0" $REF
neg "costs label removed from code" contract $MOD 'string PS_CostsLabel() {return("COSTS_NOT_MODELLED");}' 'string PS_CostsLabel() {return("");}' "COSTS_NOT_MODELLED" $REF
neg "no-reduction label removed from code" contract $MOD 'return("NO_REDUCTION_TO_LIMIT (a limit' 'return("(a limit' "NO_REDUCTION_TO_LIMIT" $REF
neg "status dropped from the MQL5 enum" parity $MOD "   PS_SKIP_ABOVE_CAP
  };" "  };" "status enum differs" $REF
neg "reason tag renamed in the MQL5 module" parity $MOD '"INVALID_CAP: ' '"INVALID_CP: ' "reason tags / first-failure order differ" $REF
neg "constant differs in the MQL5 module" parity $MOD "#define PS_MAX_STEPS 1e9" "#define PS_MAX_STEPS 1e10" "PS_MAX_STEPS / MAX_STEPS differs" $REF
neg "round down replaced by round up in MQL5" guards $MOD "MathFloor(raw_steps+PS_EPS_STEPS)" "MathCeil(raw_steps+PS_EPS_STEPS)" "sizing expression missing in MQL5" $REF
neg "never-exceed loop removed from MQL5" guards $MOD "while(n>0 && (double)n*risk_per_step>risk_budget)" "while(false)" "sizing expression missing in MQL5" $REF
neg "NormalizeDouble on the volume in MQL5" guards $MOD "out.volume_out=(double)n*volume_step;" "out.volume_out=NormalizeDouble((double)n*volume_step,2);" "can round UP" $REF
neg "reduced_to_limit field added in MQL5" guards $MOD "   double risk_unused;" "   double risk_unused;
   bool reduced_to_limit;" "reduced_to_limit" $REF
negpy "round down replaced by ceil in Python" guards "n = int(math.floor(raw_steps + EPS_STEPS))" "n = int(math.ceil(raw_steps + EPS_STEPS))" "sizing expression missing in Python"
neg "cap tolerance back to the 1e-6 step in MQL5" guards $MOD "long cap_steps=(long)MathFloor(cap_x+PS_CAP_ULPS*DBL_EPSILON*MathMax(1.0,cap_x));" "long cap_steps=(long)MathFloor(cap_x+PS_EPS_STEPS);" "sizing expression missing in MQL5" $REF
negpy "cap tolerance back to the 1e-6 step in Python" guards "cap_x + CAP_ULPS * DBL_EPSILON * max(1.0, cap_x)" "cap_x + EPS_STEPS" "sizing expression missing in Python"
negpy "cap checked before max in Python" guards "    if n > max_steps:" "    if n > cap_steps:" "limits must be checked min -> max -> cap"
negpy "Python tolerance constant differs" parity "EPS_STEPS = 1e-6          #" "EPS_STEPS = 1e-5          #" "PS_EPS_STEPS / EPS_STEPS differs"
# syntax / format / ASCII controls use the shared checkers
cp $MOD "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"
mut $MOD "$NEG/BadFmt.mqh" 'StringFormat("INVALID_CAP: %.10g must be finite and > 0",cap_lots)' 'StringFormat("INVALID_CAP: %.10g must be finite and > 0")' >/dev/null && \
python3 - "$NEG/BadFmt.mqh" <<'PYEOF' >/dev/null 2>&1 && { echo "  FAIL format-string mismatch not detected"; FAIL=1; } || echo "  PASS format-string mismatch detected"
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
cp $MOD "$NEG/NonAscii.mqh"; printf '// caf\xc3\xa9\n' >> "$NEG/NonAscii.mqh"
n=$(LC_ALL=C grep -c '[^ -~	]' "$NEG/NonAscii.mqh" || true)
[ "$n" != "0" ] && echo "  PASS non-ASCII byte detected" || { echo "  FAIL non-ASCII not detected"; FAIL=1; }

echo
[ $FAIL -eq 0 ] && echo "T006 STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T006 STATIC CHECKS: FAILURES"
exit $FAIL
