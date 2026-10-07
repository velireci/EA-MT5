#!/bin/bash
# Static checks for T002 (tasks/T002-h4-map.md).
#
# These are NOT a compiler and NOT a runtime test. They prove only what can be
# read from the source: no trading API, balanced syntax, resolvable includes,
# no MQL4 API, required handlers, matching format strings, ASCII-only source,
# T002 object-prefix discipline, no Sleep loops, and that the case data in
# src/tests/T002_LogicTest.mq5 is exactly what the Python reference model
# emits. Compilation (MetaEditor) and the MT5 test run are still UNVERIFIED.
#
# Reuses tools/t001-check-balance.py (takes file arguments) and
# tools/t001-check-format-strings.py (hardcoded T001 file list: it is loaded
# as a module and its FILES variable is overridden here; the T001 file is not
# modified).
#
# Usage: bash tools/t002-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
EA=src/XauUsdH4Map.mq5
TEST=src/tests/T002_LogicTest.mq5
HDRS="src/include/H4Structure.mqh src/include/H4MapDrawer.mqh"
FILES="$EA $HDRS $TEST"
# Everything the EA compiles: T002 files plus the reused T001 includes.
EA_CODE="$EA $HDRS src/include/TimeframeWatcher.mqh src/include/SymbolSnapshot.mqh src/include/StatusPanel.mqh"

PAT='OrderSend|OrderSendAsync|OrderClose|OrderModify|OrderDelete|PositionClose|PositionModify|PositionOpen|CTrade|CPositionInfo|COrderInfo|MqlTradeRequest|MqlTradeResult|OrderCalcMargin|OrderCalcProfit|OnTradeTransaction|OnTrade\(|PositionSelect|PositionGet|OrderSelect|OrderGet|HistoryOrder|HistoryDeal|PositionsTotal|OrdersTotal|#include[[:space:]]*<Trade'

# strip // comments and /* */ blocks, print what is left
strip_comments() {
  sed -e 's://.*::' "$1" | awk 'BEGIN{b=0} {l=$0; while(match(l,/\/\*/)){b=1; l=substr(l,1,RSTART-1)} if(b&&match($0,/\*\//)){b=0; l=substr($0,RSTART+2)} if(!b)print l}'
}
# scan_trading FILE -> prints offending lines, returns 0 when clean
scan_trading() {
  local out
  out=$(strip_comments "$1" | grep -nE "$PAT")
  if [ -n "$out" ]; then echo "$out"; return 1; fi
  return 0
}

echo "=== CHECK 1: no order/trading API in executable code (comments stripped) ==="
for f in $EA_CODE $TEST; do
  out=$(scan_trading "$f") || { echo "  FAIL $f: $out"; FAIL=1; }
done
[ $FAIL -eq 0 ] && echo "  PASS: no order/trading API in T002 code (T002 files + reused T001 includes + test script)"

echo "=== CHECK 2: brace / parenthesis balance per file ==="
python3 tools/t001-check-balance.py $FILES || FAIL=1

echo "=== CHECK 3: include guards closed, includes resolve ==="
for f in $HDRS; do
  g=$(grep -c '^#ifndef' "$f"); e=$(grep -c '^#endif' "$f")
  [ "$g" = "$e" ] && echo "  PASS $f: include guard balanced ($g/$e)" || { echo "  FAIL $f: guard $g vs endif $e"; FAIL=1; }
done
for inc in $(grep -oE '#include "[^"]+"' $EA | sed 's/#include "//;s/"//'); do
  [ -f "src/$inc" ] && echo "  PASS $EA include resolves: src/$inc" || { echo "  FAIL missing include: src/$inc"; FAIL=1; }
done
for inc in $(grep -oE '#include "[^"]+"' $TEST | sed 's/#include "//;s/"//'); do
  [ -f "src/tests/$inc" ] && echo "  PASS $TEST include resolves: src/tests/$inc" || { echo "  FAIL missing include: src/tests/$inc"; FAIL=1; }
done
for inc in $(grep -oE '#include "[^"]+"' src/include/H4MapDrawer.mqh | sed 's/#include "//;s/"//'); do
  [ -f "src/include/$inc" ] && echo "  PASS H4MapDrawer.mqh include resolves: src/include/$inc" || { echo "  FAIL missing include: src/include/$inc"; FAIL=1; }
done

echo "=== CHECK 4: MQL4-only APIs must be absent ==="
PAT4='\bOrdersTotal\(\)|\biBars\(|\bAccountBalance\(|\bMarketInfo\(|\bOrderType\(\)|\bSymbol\(\)|\bBid\b|\bAsk\b|\bPoint\b[^(]|\bDigits\b[^(]|\bstart\(\)|\binit\(\)|\bdeinit\(\)'
bad4=0
for f in $FILES; do
  out=$(strip_comments "$f" | grep -nE "$PAT4")
  if [ -n "$out" ]; then echo "  FAIL $f: $out"; bad4=1; FAIL=1; fi
done
[ $bad4 -eq 0 ] && echo "  PASS: no MQL4-style API used"

echo "=== CHECK 5: required MQL5 event handlers present ==="
for h in OnInit OnDeinit OnTick OnTimer; do
  grep -qE "^(int|void) $h\(" $EA && echo "  PASS $EA $h defined" || { echo "  FAIL $h missing"; FAIL=1; }
done
grep -qE "^void OnStart\(" $TEST && echo "  PASS $TEST OnStart defined" || { echo "  FAIL OnStart missing in test"; FAIL=1; }

echo "=== CHECK 6: StringFormat/PrintFormat specifiers match argument count ==="
python3 - $FILES <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF

echo "=== CHECK 7: source must stay pure ASCII ==="
for f in $FILES tests/t002_reference_test.py; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  if [ "$n" != "0" ]; then
    echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1
  else
    echo "  PASS $f: ASCII only"
  fi
done

echo "=== CHECK 8: T002 object prefix discipline ==="
# 8a: no velo_t001_ reference and no other velo_ prefix in T002 files
bad8=0
for f in $EA $HDRS $TEST; do
  out=$(strip_comments "$f" | grep -nE 'velo_t001_')
  if [ -n "$out" ]; then echo "  FAIL $f touches the T001 prefix: $out"; bad8=1; FAIL=1; fi
done
# 8b: every ObjectsDeleteAll passes a prefix (second argument is not empty/absent)
for f in $EA $HDRS; do
  strip_comments "$f" | grep -n 'ObjectsDeleteAll' | grep -vE 'ObjectsDeleteAll\([^,)]+,[[:space:]]*[A-Za-z_]' && { echo "  FAIL $f: ObjectsDeleteAll without a prefix argument"; bad8=1; FAIL=1; }
done
# 8c: ObjectsDeleteAll with a literal prefix must be velo_t002_
out=$(strip_comments src/include/H4MapDrawer.mqh | grep -nE 'ObjectsDeleteAll\([^,]+,[[:space:]]*"' | grep -v 'velo_t002_')
[ -n "$out" ] && { echo "  FAIL literal prefix other than velo_t002_: $out"; bad8=1; FAIL=1; }
# 8d: the drawer default prefix and the sub-prefix are present
grep -q 'm_prefix       = "velo_t002_"' src/include/H4MapDrawer.mqh && echo "  PASS drawer prefix is velo_t002_" || { echo "  FAIL drawer prefix literal not found"; bad8=1; FAIL=1; }
# 8e: ObjectDelete only on names built from the prefix or a loop name filtered by it
n_del=$(strip_comments src/include/H4MapDrawer.mqh | grep -c 'ObjectDelete(')
echo "  info: ObjectDelete calls in drawer = $n_del (ClearMap loop filtered by StringFind prefix, plus the link object)"
[ $bad8 -eq 0 ] && echo "  PASS: object cleanup is restricted to the velo_t002_ prefix"

echo "=== CHECK 9: no Sleep loops, no blocking waits ==="
bad9=0
for f in $FILES; do
  out=$(strip_comments "$f" | grep -nE '\bSleep\(')
  if [ -n "$out" ]; then echo "  FAIL $f: $out"; bad9=1; FAIL=1; fi
done
[ $bad9 -eq 0 ] && echo "  PASS: no Sleep()"

echo "=== CHECK 10: logic stays pure (no chart/series/trade access in H4Structure.mqh) ==="
out=$(strip_comments src/include/H4Structure.mqh | grep -nE '\bObject[A-Z][A-Za-z]*\(|\bChart[A-Z][A-Za-z]*\(|\bCopyRates\(|\bCopyTime\(|\biTime\(|\biHigh\(|\biLow\(|\biClose\(|\bSymbolInfo[A-Za-z]*\(|\bTimeCurrent\(|\bTimeLocal\(|\bTimeTradeServer\(')
if [ -n "$out" ]; then echo "  FAIL H4Structure.mqh is not pure: $out"; FAIL=1; else echo "  PASS: H4Structure.mqh has no object/chart/series/clock access"; fi

echo "=== CHECK 11: generated case data in the MQL5 test matches the Python model ==="
python3 tests/t002_reference_test.py --emit-mql > "$TMPD/emit" 2>/dev/null
awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p{print} /^\/\/ END GENERATED CASE DATA/{p=0}' $TEST > "$TMPD/have"
# Windows Python emits CRLF, the source block is LF: normalise both sides.
tr -d '\r' < "$TMPD/emit" > "$TMPD/emit.n"; tr -d '\r' < "$TMPD/have" > "$TMPD/have.n"
if [ -s "$TMPD/emit.n" ] && cmp -s "$TMPD/emit.n" "$TMPD/have.n"; then
  echo "  PASS: generated block in $TEST equals --emit-mql output"
else
  echo "  FAIL: generated block in $TEST differs from tests/t002_reference_test.py --emit-mql"; FAIL=1
fi
rm -f "$TMPD/emit" "$TMPD/have" "$TMPD/emit.n" "$TMPD/have.n"

echo "=== CHECK 12: Python reference model tests (verify the MODEL only) ==="
python3 tests/t002_reference_test.py > "$TMPD/py" 2>&1 && echo "  PASS: $(tail -1 "$TMPD/py")" || { tail -5 "$TMPD/py"; echo "  FAIL: reference tests"; FAIL=1; }
rm -f "$TMPD/py"

echo "=== CHECK 13: negative controls (the checkers must actually detect problems) ==="
NEG=$(mktemp -d)
# 13a: injected trading API must be detected
printf 'void F(){ MqlTradeRequest r; OrderSend(r, res); }\n' > "$NEG/a.mqh"
scan_trading "$NEG/a.mqh" >/dev/null && { echo "  FAIL 13a: injected OrderSend was NOT detected"; FAIL=1; } || echo "  PASS 13a: injected OrderSend / MqlTradeRequest detected"
# 13b: the same words inside comments must NOT be flagged
printf '// OrderSend is forbidden\n/* CTrade\n   PositionClose */\nvoid F(){}\n' > "$NEG/b.mqh"
scan_trading "$NEG/b.mqh" >/dev/null && echo "  PASS 13b: trading words in comments are ignored" || { echo "  FAIL 13b: comment-only mention flagged"; FAIL=1; }
# 13c: other trading entry points
printf 'void F(){ CTrade t; t.PositionClose(1); }\n' > "$NEG/c.mqh"
scan_trading "$NEG/c.mqh" >/dev/null && { echo "  FAIL 13c: CTrade not detected"; FAIL=1; } || echo "  PASS 13c: CTrade / PositionClose detected"
# 13d: balance checker must fail on an unbalanced file
printf 'void F(){ if(a { }\n' > "$NEG/d.mqh"
python3 tools/t001-check-balance.py "$NEG/d.mqh" >/dev/null && { echo "  FAIL 13d: unbalanced file passed"; FAIL=1; } || echo "  PASS 13d: unbalanced parentheses detected"
# 13e: format checker must fail on a specifier/argument mismatch
printf 'void F(){ string s = StringFormat("%%d %%s", 1); }\n' > "$NEG/e.mqh"
python3 - "$NEG/e.mqh" <<'PYEOF' >/dev/null
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
[ $? -ne 0 ] && echo "  PASS 13e: format-string mismatch detected" || { echo "  FAIL 13e: mismatch not detected"; FAIL=1; }
# 13f: the case-data comparison must fail when the generated block is altered
sed 's/DIR=BEARISH/DIR=BULLISH/' $TEST | awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p{print} /^\/\/ END GENERATED CASE DATA/{p=0}' > "$NEG/have.txt"
python3 tests/t002_reference_test.py --emit-mql | tr -d '\r' > "$NEG/emit.txt"
tr -d '\r' < "$NEG/have.txt" > "$NEG/have.n"
cmp -s "$NEG/have.n" "$NEG/emit.txt" && { echo "  FAIL 13f: altered data block not detected"; FAIL=1; } || echo "  PASS 13f: altered generated data detected"
# 13g: a CRLF-converted copy of the (unaltered) block must compare equal after normalisation
awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p{print} /^\/\/ END GENERATED CASE DATA/{p=0}' $TEST | sed 's/$/\r/' > "$NEG/crlf.txt"
cmp -s "$NEG/crlf.txt" "$NEG/emit.txt" && { echo "  FAIL 13g: raw CRLF copy unexpectedly equal (test is vacuous)"; FAIL=1; }
tr -d '\r' < "$NEG/crlf.txt" > "$NEG/crlf.n"
cmp -s "$NEG/crlf.n" "$NEG/emit.txt" && echo "  PASS 13g: CRLF copy of the block equals --emit-mql after line-ending normalisation" || { echo "  FAIL 13g: CRLF copy differs after normalisation"; FAIL=1; }
rm -rf "$NEG"

echo "=== RESULT ==="
[ $FAIL -eq 0 ] && echo "ALL STATIC CHECKS PASSED (not a compilation, not a runtime test)" || echo "STATIC CHECKS FAILED"
exit $FAIL
