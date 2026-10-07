#!/bin/bash
# Static checks for T001 (tasks/T001-foundation.md).
#
# These are NOT a compiler and NOT a runtime test. They only prove what can be
# proven by reading the source: no trading API, balanced syntax, resolvable
# includes, no MQL4 API, the MQL5 event handlers, and format strings whose
# specifiers match their arguments. Compilation and MT5 behavior must still be
# verified in MetaEditor/MT5 - see reports/T001-verification.md section 5.
#
# Usage: bash tools/t001-static-checks.sh   (from the repository root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
FILES="src/XauUsdFoundation.mq5 src/include/TimeframeWatcher.mqh src/include/SymbolSnapshot.mqh src/include/StatusPanel.mqh"

echo "=== CHECK 1: no order/trading API in executable code (comments stripped) ==="
PAT='OrderSend|OrderSendAsync|OrderClose|OrderModify|OrderDelete|PositionClose|PositionModify|PositionOpen|CTrade|CPositionInfo|COrderInfo|MqlTradeRequest|MqlTradeResult|OrderCalcMargin|OrderCalcProfit|OnTradeTransaction|OnTrade\(|PositionSelect|OrderSelect|#include[[:space:]]*<Trade'
for f in $FILES; do
  # strip // comments and /* */ blocks, then search
  out=$(sed -e 's://.*::' "$f" | awk 'BEGIN{b=0} {l=$0; while(match(l,/\/\*/)){b=1; l=substr(l,1,RSTART-1)} if(b&&match($0,/\*\//)){b=0; l=substr($0,RSTART+2)} if(!b)print l}' | grep -nE "$PAT")
  if [ -n "$out" ]; then echo "  FAIL $f: $out"; FAIL=1; fi
done
[ $FAIL -eq 0 ] && echo "  PASS: no order/trading API in code"

echo "=== CHECK 2: brace / parenthesis balance per file ==="
for f in $FILES; do
  python3 - "$f" <<'PY'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r'/\*.*?\*/','',s,flags=re.S)
s=re.sub(r'//[^\n]*','',s)
s=re.sub(r'"(\\.|[^"\\])*"','""',s)
s=re.sub(r"'(\\.|[^'\\])*'","''",s)
ok=True
for o,c,n in (('{','}','braces'),('(',')','parens'),('[',']','brackets')):
    d=s.count(o)-s.count(c)
    if d: ok=False; print(f"  FAIL {p}: {n} unbalanced by {d}")
if ok: print(f"  PASS {p}: braces/parens/brackets balanced")
PY
done

echo "=== CHECK 3: every #ifndef guard closed, includes resolve ==="
for f in src/include/*.mqh; do
  g=$(grep -c '^#ifndef' "$f"); e=$(grep -c '^#endif' "$f")
  [ "$g" = "$e" ] && echo "  PASS $f: include guard balanced ($g/$e)" || { echo "  FAIL $f: guard $g vs endif $e"; FAIL=1; }
done
for inc in $(grep -oE '#include "[^"]+"' src/XauUsdFoundation.mq5 | sed 's/#include "//;s/"//'); do
  [ -f "src/$inc" ] && echo "  PASS include resolves: src/$inc" || { echo "  FAIL missing include: src/$inc"; FAIL=1; }
done

echo "=== CHECK 4: MQL4-only APIs must be absent ==="
PAT4='\bOrdersTotal\(\)|\biBars\(|\bAccountBalance\(|\bMarketInfo\(|\bOrderType\(\)|\bSymbol\(\)|\bBid\b|\bAsk\b|\bPoint\b[^(]|\bDigits\b[^(]|\bstart\(\)|\binit\(\)|\bdeinit\(\)'
for f in $FILES; do
  out=$(sed -e 's://.*::' "$f" | grep -nE "$PAT4")
  if [ -n "$out" ]; then echo "  WARN $f: $out"; fi
done
echo "  (empty above = no MQL4-style API used)"

echo "=== CHECK 5: required MQL5 event handlers present ==="
for h in OnInit OnDeinit OnTick OnTimer; do
  grep -qE "^(int|void) $h\(" src/XauUsdFoundation.mq5 && echo "  PASS $h defined" || { echo "  FAIL $h missing"; FAIL=1; }
done

echo "=== CHECK 6: StringFormat/PrintFormat specifiers match argument count ==="
python3 tools/t001-check-format-strings.py || FAIL=1

echo "=== CHECK 7: source must stay pure ASCII ==="
for f in $FILES; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  if [ "$n" != "0" ]; then
    echo "  FAIL $f: $n line(s) with non-ASCII bytes (MetaEditor may mangle them without a BOM)"; FAIL=1
  else
    echo "  PASS $f: ASCII only"
  fi
done

echo "=== RESULT ==="
[ $FAIL -eq 0 ] && echo "ALL STATIC CHECKS PASSED" || echo "STATIC CHECKS FAILED"
exit $FAIL
