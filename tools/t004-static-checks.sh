#!/bin/bash
# Static checks for the T004 files (observer, selector, timeline, ordinary H4 touch source, EA, test scripts).
#
# These are NOT a compiler, NOT an MT5 run and NOT a chart observation. They prove only what can be read from
# the source text: no trading API, no live price / tick / indicator access, no clock-based price input,
# ObjectsDeleteAll / ObjectCreate confined to the velo_t004_ prefix, balanced syntax, format strings, ASCII,
# resolvable includes, and that T001-T003 source/tests/tools are byte-identical to the T003 base commit.
# Every checker is shown to fail on a mutated copy (negative controls).
# MetaEditor compilation and the MT5 run are still UNVERIFIED.
#
# Usage: bash tools/t004-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=6676a01
INC="src/include/M15Confirmation.mqh src/include/H4M15Bridge.mqh src/include/M15SwingProposal.mqh src/include/M15Timeline.mqh src/include/H4TouchContext.mqh"
EA=src/XauUsdM15Observer.mq5
TESTS="src/tests/T004_LogicTest.mq5 src/tests/T004_SelectorTest.mq5 src/tests/T004_TimelineTest.mq5 src/tests/T004_OrdinaryTest.mq5"
ALL="$INC $EA $TESTS"
CHK="python3 -I tools/t004-static-check.py"

echo "=== S1: files exist ==="
for f in $ALL tools/t004-static-check.py; do
  [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }
done

echo "=== S2: no trading API, no live price/tick/indicator, no clock input (comments and strings stripped) ==="
out=$($CHK trading $ALL) && echo "  PASS no trading API in $(echo $ALL | wc -w) T004 files" || { echo "$out"; echo "  FAIL trading API present"; FAIL=1; }
out=$($CHK nofeed $ALL) && echo "  PASS no quote/tick/indicator access, no wall-clock function; GetTickCount only for the replay duration in the EA" || { echo "$out"; echo "  FAIL live price or clock input"; FAIL=1; }

echo "=== S3: chart-object isolation ==="
out=$($CHK isolation $EA) && echo "  PASS every ObjectsDeleteAll uses PREFIX, PREFIX is velo_t004_, every ObjectCreate name is PREFIX-based" || { echo "$out"; echo "  FAIL isolation"; FAIL=1; }
grep -q 'velo_t00[123]_' $ALL && { echo "  FAIL a T004 file mentions a foreign prefix"; FAIL=1; } || echo "  PASS no foreign velo_t001_/velo_t002_/velo_t003_ prefix in T004 files"

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
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every file above"

echo "=== S5: T001-T003 source, tests and tools unchanged versus $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  PATHS="src/include/H4Structure.mqh src/include/H4Bias.mqh src/include/H4BiasLayers.mqh src/include/H4BiasDrawer.mqh src/include/H4MapDrawer.mqh src/include/StatusPanel.mqh src/include/SymbolSnapshot.mqh src/include/TimeframeWatcher.mqh src/XauUsdFoundation.mq5 src/XauUsdH4Map.mq5 src/XauUsdH4Bias.mq5 src/tests/T002_LogicTest.mq5 src/tests/T002_SetupScan.mq5 src/tests/T003_LogicTest.mq5 src/tests/T003_LayersTest.mq5 tests/t002_reference_test.py tests/t003_reference_test.py tests/t003_explore_synthetic.py tests/t003_replay_csv.py tests/t003_structural_level_diag.py tools/t001-static-checks.sh tools/t001-check-balance.py tools/t001-check-format-strings.py tools/t002-static-checks.sh tools/t003-static-checks.sh tools/t003-visual-static-checks.sh tools/t003-visual-check.py"
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
neg() {  # neg LABEL CHECK SRC OLD NEW SUBSTRING
  local label="$1" chk="$2" src="$3" old="$4" new="$5" sub="$6" f="$NEG/$(basename "$3")"
  if ! mut "$src" "$f" "$old" "$new"; then echo "  FAIL $label: mutation target absent (vacuous control)"; FAIL=1; return; fi
  local out; out=$($CHK "$chk" "$f" 2>&1); local rc=$?
  if [ $rc -ne 0 ] && echo "$out" | grep -qF -- "$sub"; then echo "  PASS $label (detected: $sub)"
  else echo "  FAIL $label: rc=$rc output: $out"; FAIL=1; fi
}
neg "order API in the logic header" trading src/include/H4TouchContext.mqh "bool gate=(retouch!=M4_RETOUCH_UNSET);" "bool gate=(retouch!=M4_RETOUCH_UNSET); OrderSend(req,res);" "OrderSend"
neg "trade class in the EA" trading $EA "bool Ordinary()" "CTrade trade; bool Ordinary()" "CTrade"
neg "live bid in the EA" nofeed $EA "bool Ordinary()" "double px=SymbolInfoDouble(_Symbol,SYMBOL_BID); bool Ordinary()" "SymbolInfoDouble"
neg "wall clock in the logic header" nofeed src/include/H4TouchContext.mqh "bool gate=(retouch!=M4_RETOUCH_UNSET);" "bool gate=(retouch!=M4_RETOUCH_UNSET); datetime now=TimeCurrent();" "TimeCurrent"
neg "GetTickCount outside the EA" nofeed src/include/M15Timeline.mqh "M4Init(state,f,events,policy);" "M4Init(state,f,events,policy); uint z=GetTickCount();" "GetTickCount"
neg "unprefixed ObjectsDeleteAll" isolation $EA "ObjectsDeleteAll(0,PREFIX);" "ObjectsDeleteAll(0,\"\");" "ObjectsDeleteAll"
neg "foreign object name" isolation $EA 'string name=PREFIX+"f"+IntegerToString(i);' 'string name="other_"+IntegerToString(i);' "ObjectCreate"
neg "wrong prefix value" isolation $EA 'string PREFIX="velo_t004_";' 'string PREFIX="velo_t003_";' "PREFIX"

echo
[ $FAIL -eq 0 ] && echo "T004 STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T004 STATIC CHECKS: FAILURES"
exit $FAIL
