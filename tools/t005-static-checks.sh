#!/bin/bash
# Static checks for the T005 pure trade-geometry files.
#
# These are NOT a compiler, NOT an MT5 run. They prove only what can be read from the source text: no trading API,
# no quote / tick / series / clock access, no volume identifier, required contract labels present in code,
# MQL5/Python status parity, balanced syntax, format strings, ASCII, resolvable includes, and that T001-T004
# source, tests and tools are byte-identical to the T004 base commit. Each checker is shown to fail on a mutated
# copy (negative controls). MetaEditor compilation and the MT5 run are UNVERIFIED.
#
# Usage: bash tools/t005-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=5447ef3
MOD=src/include/TradeGeometry.mqh
TST=src/tests/T005_GeometryTest.mq5
REF=tests/t005_geometry_reference.py
ALL="$MOD $TST"
CHK="python3 -I tools/t005-static-check.py"

echo "=== S1: files exist ==="
for f in $ALL $REF tests/t005_geometry_fixtures.py tests/test_t005_geometry.py tools/t005-static-check.py; do
  [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }
done

echo "=== S2: no trading API, no quote/tick/series/clock, no volume identifier ==="
out=$($CHK trading $ALL) && echo "  PASS no trading API in module and test" || { echo "$out"; echo "  FAIL trading API present"; FAIL=1; }
out=$($CHK nofeed $ALL) && echo "  PASS no quote, tick, indicator, series or clock access" || { echo "$out"; echo "  FAIL live price or clock input"; FAIL=1; }
out=$($CHK novolume $ALL) && echo "  PASS no volume / lot / account identifier" || { echo "$out"; echo "  FAIL volume identifier"; FAIL=1; }

echo "=== S3: contract labels in the module, status parity with the Python reference ==="
out=$($CHK contract $MOD) && echo "  PASS header keeps the contract; labels are returned by code" || { echo "$out"; echo "  FAIL contract text"; FAIL=1; }
out=$($CHK parity $MOD $REF) && echo "  PASS MQL5 status enum and labels equal the reference" || { echo "$out"; echo "  FAIL parity"; FAIL=1; }

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
for f in $ALL $REF tests/t005_geometry_fixtures.py tests/test_t005_geometry.py tools/t005-static-check.py tools/t005-static-checks.sh; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every T005 file"

echo "=== S5: T001-T004 source, tests and tools unchanged versus $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  PATHS="src/include/H4Structure.mqh src/include/H4Bias.mqh src/include/H4BiasLayers.mqh src/include/H4BiasDrawer.mqh src/include/H4MapDrawer.mqh src/include/StatusPanel.mqh src/include/SymbolSnapshot.mqh src/include/TimeframeWatcher.mqh src/include/M15Confirmation.mqh src/include/H4M15Bridge.mqh src/include/M15SwingProposal.mqh src/include/M15Timeline.mqh src/include/H4TouchContext.mqh src/XauUsdFoundation.mq5 src/XauUsdH4Map.mq5 src/XauUsdH4Bias.mq5 src/XauUsdM15Observer.mq5 src/tests/T002_LogicTest.mq5 src/tests/T002_SetupScan.mq5 src/tests/T003_LogicTest.mq5 src/tests/T003_LayersTest.mq5 src/tests/T004_LogicTest.mq5 src/tests/T004_SelectorTest.mq5 src/tests/T004_TimelineTest.mq5 src/tests/T004_OrdinaryTest.mq5 tests/t002_reference_test.py tests/t003_reference_test.py tests/t003_explore_synthetic.py tests/t003_replay_csv.py tests/t003_structural_level_diag.py tests/t004_reference.py tests/t004_selector_reference.py tests/t004_timeline_reference.py tests/t004_ordinary_reference.py tests/t004_ordinary_fixtures.py tests/test_t004.py tests/test_t004_selector.py tests/test_t004_timeline.py tests/test_t004_ordinary.py tools/t001-static-checks.sh tools/t001-check-balance.py tools/t001-check-format-strings.py tools/t002-static-checks.sh tools/t003-static-checks.sh tools/t003-visual-static-checks.sh tools/t003-visual-check.py tools/t004-static-checks.sh tools/t004-static-check.py"
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
neg() {  # neg LABEL CHECK SRC OLD NEW SUBSTRING [EXTRA_ARG]
  local label="$1" chk="$2" src="$3" old="$4" new="$5" sub="$6" extra="${7:-}" f="$NEG/$(basename "$3")"
  if ! mut "$src" "$f" "$old" "$new"; then echo "  FAIL $label: mutation target absent (vacuous control)"; FAIL=1; return; fi
  local out rc
  if [ "$chk" = "parity" ]; then out=$($CHK parity "$f" "$extra" 2>&1); rc=$?; else out=$($CHK "$chk" "$f" 2>&1); rc=$?; fi
  if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$sub"; then echo "  PASS $label (detected: $sub)"
  else echo "  FAIL $label: rc=$rc output: $out"; FAIL=1; fi
}
neg "order API in the module" trading $MOD "return(true);
  }

#endif" "OrderSend(req,res); return(true);
  }

#endif" "OrderSend"
neg "trade class in the module" trading $MOD "int sign=(direction==TG_BUY ? 1 : -1);" "CTrade trade; int sign=(direction==TG_BUY ? 1 : -1);" "CTrade"
neg "live ask in the module" nofeed $MOD "int sign=(direction==TG_BUY ? 1 : -1);" "double px=SymbolInfoDouble(_Symbol,SYMBOL_ASK); int sign=(direction==TG_BUY ? 1 : -1);" "SymbolInfoDouble"
neg "wall clock in the module" nofeed $MOD "int sign=(direction==TG_BUY ? 1 : -1);" "datetime now=TimeCurrent(); int sign=(direction==TG_BUY ? 1 : -1);" "TimeCurrent"
neg "series access in the module" nofeed $MOD "int sign=(direction==TG_BUY ? 1 : -1);" "double c=iClose(_Symbol,PERIOD_M15,0); int sign=(direction==TG_BUY ? 1 : -1);" "iClose"
neg "volume identifier in the module" novolume $MOD "int sign=(direction==TG_BUY ? 1 : -1);" "double lots=0.1; int sign=(direction==TG_BUY ? 1 : -1);" "lots"
neg "costs label removed from code" contract $MOD 'return("COSTS_NOT_MODELLED");' 'return("");' "COSTS_NOT_MODELLED"
neg "unenforced note removed from code" contract $MOD "limit NOT enforced (unit unconfirmed)" "limit (unit unconfirmed)" "not returned by code"
neg "status dropped from the MQL5 enum" parity $MOD "   TG_PENDING_TOO_CLOSE
  };" "  };" "status enum differs" $REF
neg "target label changed in the MQL5 module" parity $MOD 'return("EQUAL_TO_2R");' 'return("EQUAL");' "EQUAL_TO_2R" $REF
# syntax / format / ASCII controls use the shared checkers
cp $MOD "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"
mut $MOD "$NEG/BadFmt.mqh" 'StringFormat("SL distance %.10g points < stops level %d",sl_points,stops_level)' 'StringFormat("SL distance %.10g points < stops level %d",sl_points)' >/dev/null && \
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
[ $FAIL -eq 0 ] && echo "T005 STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T005 STATIC CHECKS: FAILURES"
exit $FAIL
