#!/bin/bash
# Static checks for the T007 pure trade-planning files.
#
# These are NOT a compiler, NOT an MT5 run. They prove only what can be read from the source text: no trading API, no quote /
# tick / symbol / account / series / clock access, no file / global-variable / network access, required contract labels present
# in code, MQL5/Python parity (statuses, stages, reason tags in the same first-failure order, event order, constants, states,
# labels), the boundary comparisons and the register-only-on-ALLOW order, no rounding of its own, balanced syntax, format
# strings, ASCII, resolvable includes, and that T001-T006 source, tests and tools are byte-identical to the T006 baseline
# commit. Each checker is shown to fail on a mutated copy (negative controls). MetaEditor compilation and the MT5 run are
# UNVERIFIED.
#
# Usage: bash tools/t007-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=559794a
MOD=src/include/TradePlanning.mqh
TST=src/tests/T007_PlanningTest.mq5
REF=tests/t007_planning_reference.py
ALL="$MOD $TST"
CHK="python3 -I tools/t007-static-check.py"

echo "=== S1: files exist ==="
for f in $ALL $REF tests/t007_planning_fixtures.py tests/test_t007_planning.py tools/t007-static-check.py; do
  [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }
done

echo "=== S2: no trading API, no quote/tick/symbol/account/series/clock, no file or persistence access ==="
out=$($CHK trading $ALL) && echo "  PASS no trading API in module and test" || { echo "$out"; echo "  FAIL trading API present"; FAIL=1; }
out=$($CHK nofeed $ALL) && echo "  PASS no quote, tick, symbol, account, indicator, series or clock access" || { echo "$out"; echo "  FAIL live input"; FAIL=1; }
out=$($CHK nopersist $ALL $REF) && echo "  PASS no file, global-variable, network, clock or process access in module, test and reference" || { echo "$out"; echo "  FAIL persistence or I/O"; FAIL=1; }

echo "=== S3: contract labels, parity, guards ==="
out=$($CHK contract $MOD $REF) && echo "  PASS headers keep the contract; labels are returned by code" || { echo "$out"; echo "  FAIL contract text"; FAIL=1; }
out=$($CHK parity $MOD $REF) && echo "  PASS statuses, stages, reason tags (same first-failure order), events, constants, states and labels equal" || { echo "$out"; echo "  FAIL parity"; FAIL=1; }
out=$($CHK guards $MOD $REF) && echo "  PASS boundary comparisons, register-only-on-ALLOW, POLICY_UNSET guards, geometry before sizing, positions untouched, no own rounding" || { echo "$out"; echo "  FAIL planning guards"; FAIL=1; }

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
for f in $ALL $REF tests/t007_planning_fixtures.py tests/test_t007_planning.py tools/t007-static-check.py tools/t007-static-checks.sh; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every T007 file"

echo "=== S5: T001-T006 source, tests and tools unchanged versus $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  PATHS="src/include/H4Structure.mqh src/include/H4Bias.mqh src/include/H4BiasLayers.mqh src/include/H4BiasDrawer.mqh src/include/H4MapDrawer.mqh src/include/StatusPanel.mqh src/include/SymbolSnapshot.mqh src/include/TimeframeWatcher.mqh src/include/M15Confirmation.mqh src/include/H4M15Bridge.mqh src/include/M15SwingProposal.mqh src/include/M15Timeline.mqh src/include/H4TouchContext.mqh src/XauUsdFoundation.mq5 src/XauUsdH4Map.mq5 src/XauUsdH4Bias.mq5 src/XauUsdM15Observer.mq5 src/tests/T002_LogicTest.mq5 src/tests/T002_SetupScan.mq5 src/tests/T003_LogicTest.mq5 src/tests/T003_LayersTest.mq5 src/tests/T004_LogicTest.mq5 src/tests/T004_SelectorTest.mq5 src/tests/T004_TimelineTest.mq5 src/tests/T004_OrdinaryTest.mq5 tests/t002_reference_test.py tests/t003_reference_test.py tests/t003_explore_synthetic.py tests/t003_replay_csv.py tests/t003_structural_level_diag.py tests/t004_reference.py tests/t004_selector_reference.py tests/t004_timeline_reference.py tests/t004_ordinary_reference.py tests/t004_ordinary_fixtures.py tests/test_t004.py tests/test_t004_selector.py tests/test_t004_timeline.py tests/test_t004_ordinary.py tools/t001-static-checks.sh tools/t001-check-balance.py tools/t001-check-format-strings.py tools/t002-static-checks.sh tools/t003-static-checks.sh tools/t003-visual-static-checks.sh tools/t003-visual-check.py tools/t004-static-checks.sh tools/t004-static-check.py src/include/TradeGeometry.mqh src/tests/T005_GeometryTest.mq5 tests/t005_geometry_reference.py tests/t005_geometry_fixtures.py tests/test_t005_geometry.py tools/t005-static-checks.sh tools/t005-static-check.py src/include/PositionSizing.mqh src/tests/T006_SizingTest.mq5 tests/t006_sizing_reference.py tests/t006_sizing_fixtures.py tests/test_t006_sizing.py tools/t006-static-checks.sh tools/t006-static-check.py"
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
ANCHOR='bool TP_CountOk(const long v) {return(v>=0);}'
neg "order structure in the module" trading $MOD "$ANCHOR" 'bool TP_CountOk(const long v) {MqlTradeRequest rq; return(v>=0);}' "MqlTradeRequest"
neg "wall clock in the module" nofeed $MOD "$ANCHOR" 'bool TP_CountOk(const long v) {datetime now=TimeCurrent(); return(v>=0);}' "TimeCurrent"
neg "file access in the module" nopersist $MOD "$ANCHOR" 'bool TP_CountOk(const long v) {int h=FileOpen("x",FILE_WRITE); return(v>=0);}' "FileOpen"
neg "process import in the Python reference" nopersist $REF "import math
" "import math
import os
" "import os"
neg "label removed from code" contract $MOD 'string TP_PlanLabel() {return("PLAN_ONLY / NOT_AN_ORDER");}' 'string TP_PlanLabel() {return("");}' "is not returned by code" $REF
neg "registry statement removed from the header" contract $MOD "NOT atomic, NOT persistent" "atomic persistent" "NOT atomic, NOT persistent" $REF
neg "reason tag renamed in the MQL5 module" parity $MOD '"SPREAD_UNKNOWN"' '"SPREAD_UNK"' "first-failure order differ" $REF
neg "constant differs in the MQL5 module" parity $MOD "#define TP_RISK_ULPS 4.0" "#define TP_RISK_ULPS 5.0" "TP_RISK_ULPS / RISK_ULPS differs" $REF
neg "state constant differs from the fixture table" parity $MOD "#define TP_NEWS_BLOCKED 2" "#define TP_NEWS_BLOCKED 5" "state constant NEWS_BLOCKED differs" $REF
neg "positions boundary made exclusive in MQL5" guards $MOD "snap.open_positions>=lim.max_positions" "snap.open_positions>lim.max_positions" "guard expression missing in MQL5" $REF
negpy "trades boundary made exclusive in Python" guards "snap.trades_today >= limits.max_trades_per_day" "snap.trades_today > limits.max_trades_per_day" "guard expression missing in Python"
neg "registering also on BLOCK in MQL5" guards $MOD "      return(false);
   int capacity=ArraySize(reg_ids);" "      {}
   int capacity=ArraySize(reg_ids);" "guard expression missing in MQL5" $REF
neg "naive overflowing risk sum reintroduced in MQL5" guards $MOD "TP_RiskExceeded(snap.existing_risk,plan.risk_model,lim.risk_cap))" "snap.existing_risk+plan.risk_model>lim.risk_cap)" "naive" $REF
neg "plan stage check removed in MQL5" guards $MOD "plan.status==TP_OK && plan.stage==TP_STAGE_COMPLETE" "plan.status==TP_OK" "guard expression missing in MQL5" $REF
neg "plan value validation removed in MQL5" guards $MOD "bool values_ok=TP_PlanValuesOk(plan);" "bool values_ok=true;" "guard expression missing in MQL5" $REF
neg "final registry bounds guard removed in MQL5" guards $MOD "if(reg_count<0 || reg_count>=capacity)     //" "if(false)     //" "guard expression missing in MQL5" $REF
negpy "plan id validation removed in Python" guards "ids_ok = not (_blank(getattr(plan, 'signal_id', None)) or _blank(getattr(plan, 'setup_id', None)))" "ids_ok = True" "guard expression missing in Python"
negpy "registry capacity check removed in Python" guards "    elif registry.count >= capacity:
        reasons.append('REGISTRY_FULL')" "    elif False:
        reasons.append('REGISTRY_FULL')" "guard expression missing in Python"
neg "POLICY_UNSET guard disabled in MQL5" guards $MOD 'if(!lim.max_positions_set) TP_AddReason(out,"POLICY_UNSET:max_positions");' 'if(false) TP_AddReason(out,"POLICY_UNSET:max_positions");' "guard expression missing in MQL5" $REF
neg "own normalization of the plan volume in MQL5" guards $MOD "out.volume_out=siz.volume_out;" "out.volume_out=NormalizeDouble(siz.volume_out,2);" "does its own rounding" $REF
neg "positions_untouched can become false in MQL5" guards $MOD "out.positions_untouched=true;" "out.positions_untouched=false;" "positions_untouched" $REF
# syntax / format / ASCII controls use the shared checkers
cp $MOD "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"
mut $MOD "$NEG/BadFmt.mqh" 'StringFormat("GEOMETRY_REFUSED: geometry %s: %s",out.under_status,geo.reason)' 'StringFormat("GEOMETRY_REFUSED: geometry %s: %s",out.under_status)' >/dev/null && \
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
[ $FAIL -eq 0 ] && echo "T007 STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T007 STATIC CHECKS: FAILURES"
exit $FAIL
