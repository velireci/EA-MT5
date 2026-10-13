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

echo "=== CHECK 14: EA is a thin wrapper over the shared lifecycle step; no stale 'stop' logic ==="
bad14=0
EAS=$(strip_comments $EA)
# 14a: the EA calls the same pure step functions the tests drive
for fn in H4LifeInit H4LifeDecide H4LifeOnCopy; do
  echo "$EAS" | grep -q "$fn(" && echo "  PASS EA calls $fn" || { echo "  FAIL EA does not call $fn"; bad14=1; FAIL=1; }
done
# 14b: the LifeOnCopy kinds are both wired (probe and build)
for k in H4_ATT_PROBE H4_ATT_BUILD; do
  echo "$EAS" | grep -q "$k" && echo "  PASS EA uses $k" || { echo "  FAIL EA never uses $k"; bad14=1; FAIL=1; }
done
# 14c: removed constructs and the unsupported claim must not come back in production code
for f in $EA_CODE; do
  out=$(strip_comments "$f" | grep -nE 'no more on server|H4RefreshDue|g_hist_exhausted|g_hist_noprog|HIST_MAX_NOPROG[^_]|[^_]HIST_MAX_NOPROG')
  if [ -n "$out" ]; then
    # the shared constant H4_HIST_MAX_NOPROG is allowed; anything else is stale
    out2=$(echo "$out" | grep -vE 'H4_HIST_MAX_NOPROG')
    [ -n "$out2" ] && { echo "  FAIL $f: stale stop/exhausted logic or claim: $out2"; bad14=1; FAIL=1; }
  fi
done
# 14d: no mutable lifecycle flag is kept outside g_life in the EA
out=$(echo "$EAS" | grep -nE '\bg_have_map\b|\bg_tried_once\b|\bg_last_try\b|\bg_hist_(state|got|oldest|text)\b')
[ -n "$out" ] && { echo "  FAIL EA keeps lifecycle state outside g_life: $out"; bad14=1; FAIL=1; }
# 14e: the cadence is unsigned arithmetic via H4ElapsedMs (no signed GetTickCount compare in the step)
strip_comments src/include/H4Structure.mqh | grep -q 'now_ms - last_ms' && echo "  PASS step uses unsigned now_ms - last_ms" || { echo "  FAIL H4ElapsedMs unsigned subtraction missing"; bad14=1; FAIL=1; }
[ $bad14 -eq 0 ] && echo "  PASS: EA wiring and stale-logic checks"
# 14f: negative control: the stale-logic grep must detect the old claim and old call
printf 'string t = "no more on server"; bool b = H4RefreshDue(1, 2, 3);\n' > "$TMPD/stale.mqh"
strip_comments "$TMPD/stale.mqh" | grep -qE 'no more on server|H4RefreshDue' && echo "  PASS 14f: stale claim / H4RefreshDue detected" || { echo "  FAIL 14f: stale logic not detected"; FAIL=1; }

echo "=== CHECK 15: historical review wiring (single copy helper, no live price, static map) ==="
# fn_body FILE PREFIX -> stripped source of the function whose DEFINITION line starts with the
# literal text PREFIX (prototypes, which end with ';', are skipped). The prefix is matched with
# index() and handed over through the environment: `awk -v` would process backslash escapes in a
# regex (gawk warns about "\(" and silently turns it into "("), so no regex crosses awk -v here.
# Definitions end with a line of exactly two spaces and a closing brace, as in the EA.
fn_body() { strip_comments "$1" | FN_PREFIX="$2" awk 'index($0, ENVIRON["FN_PREFIX"]) == 1 && $0 !~ /;[ \t]*$/ {p=1} p{print} p&&/^  }$/{exit}'; }
# check_hist_wiring FILE -> prints violations, returns 0 when the wiring is intact
check_hist_wiring() {
  local f="$1" bad=0 s cl rb hp rp po b fn
  s=$(strip_comments "$f")
  cl=$(fn_body "$f" 'int CopyClosedSet(')
  rb=$(fn_body "$f" 'bool RecomputeMap(void)')
  hp=$(fn_body "$f" 'bool HistoryProbe(void)')
  rp=$(fn_body "$f" 'void RefreshPrice(')
  po=$(fn_body "$f" 'void Poll(void)')
  [ -n "$cl" ] && [ -n "$rb" ] && [ -n "$hp" ] && [ -n "$rp" ] && [ -n "$po" ] || { echo "    function body not found"; return 1; }
  # a) exactly two CopyRates calls in the whole EA, both inside CopyClosedSet
  [ "$(echo "$s" | grep -c 'CopyRates(')" = "2" ] && [ "$(echo "$cl" | grep -c 'CopyRates(')" = "2" ] || { echo "    CopyRates must appear exactly twice, both in CopyClosedSet"; bad=1; }
  # b) RecomputeMap and HistoryProbe use the helper and never copy themselves
  for b in "$rb" "$hp"; do
    echo "$b" | grep -q 'CopyClosedSet(' || { echo "    RecomputeMap/HistoryProbe must call CopyClosedSet"; bad=1; }
    echo "$b" | grep -q 'CopyRates(' && { echo "    RecomputeMap/HistoryProbe must not call CopyRates"; bad=1; }
  done
  # c) the helper applies the shared pure filter and newest-bar rule
  for fn in H4ClosedCountAsOf H4AsOfSetStart H4EffectiveAsOf H4NewestOk; do
    echo "$cl" | grep -q "$fn(" || { echo "    CopyClosedSet must use $fn"; bad=1; }
  done
  # d) the only live price read is guarded by !g_hist; no other live-price or clock API
  [ "$(echo "$s" | grep -c 'SymbolInfoDouble(')" = "1" ] && [ "$(echo "$s" | grep -c 'SYMBOL_BID')" = "1" ] || { echo "    exactly one SymbolInfoDouble(SYMBOL_BID) expected"; bad=1; }
  echo "$s" | grep -B3 'SymbolInfoDouble(' | head -3 | grep -q '!g_hist' || { echo "    the bid read is not guarded by !g_hist"; bad=1; }
  echo "$s" | grep -qE 'SymbolInfoTick|SYMBOL_ASK|SYMBOL_LAST|TimeCurrent\(|TimeLocal\(|TimeTradeServer\(|\biClose\(|\biTime\(' && { echo "    live price / clock API in the EA"; bad=1; }
  echo "$rp" | grep -q 'H4SelectionPrice(g_hist' || { echo "    RefreshPrice must take its price from H4SelectionPrice(g_hist, ...)"; bad=1; }
  # e) historical mode never passes the raw new_bar to the lifecycle
  echo "$po" | grep -q 'H4NewBarForLife(g_hist, new_bar)' || { echo "    Poll must pass H4NewBarForLife(g_hist, new_bar)"; bad=1; }
  echo "$po" | grep -E 'H4LifeDecide' -A2 | grep -qE '[ ,]new_bar,' && { echo "    Poll passes the raw new_bar to H4LifeDecide"; bad=1; }
  return $bad
}
out=$(check_hist_wiring $EA) && echo "  PASS $EA: one copy helper (CopyClosedSet) for RecomputeMap and HistoryProbe; bid read only when !g_hist; new bars gated by H4NewBarForLife" || { echo "$out"; echo "  FAIL historical wiring in $EA"; FAIL=1; }
grep -q '^input datetime[[:space:]]*InpAsOfTime[[:space:]]*=[[:space:]]*0;' $EA && grep -q 'NOT UTC, NOT TradingView' $EA && echo "  PASS InpAsOfTime input present (default 0) with the broker/server time warning" || { echo "  FAIL InpAsOfTime input or its time-base warning missing"; FAIL=1; }
# every function body the wiring check depends on must be found (no vacuous pass)
for sig in 'int CopyClosedSet(' 'bool RecomputeMap(void)' 'bool HistoryProbe(void)' 'void RefreshPrice(' 'void Poll(void)'; do
  [ -n "$(fn_body $EA "$sig")" ] && echo "  PASS fn_body finds '$sig'" || { echo "  FAIL fn_body does not find '$sig'"; FAIL=1; }
done
# negative controls: each mutation of the EA must be detected, for the intended reason
NEG15=$(mktemp -d)
sed 's/int got = CopyClosedSet(g_bars, oldest, newest_ok);/int got = CopyRates(g_symbol, PERIOD_H4, 1, g_lookback, g_bars);/' $EA > "$NEG15/m1.mq5"
o15=$(check_hist_wiring "$NEG15/m1.mq5"); r15=$?; { [ $r15 -ne 0 ] && echo "$o15" | grep -q "CopyRates must appear exactly twice\|RecomputeMap/HistoryProbe must call CopyClosedSet\|RecomputeMap/HistoryProbe must not call CopyRates" && ! echo "$o15" | grep -q "function body not found"; } && echo "  PASS 15a: separate CopyRates in RecomputeMap detected (failed for the intended reason)" || { echo "  FAIL 15a: a second CopyRates in RecomputeMap, or it failed for another reason: $o15"; FAIL=1; }
sed 's/if(!g_hist) .*$/if(true)/' $EA > "$NEG15/m2.mq5"
o15=$(check_hist_wiring "$NEG15/m2.mq5"); r15=$?; { [ $r15 -ne 0 ] && echo "$o15" | grep -q "the bid read is not guarded by !g_hist" && ! echo "$o15" | grep -q "function body not found"; } && echo "  PASS 15b: bid read without the !g_hist guard detected (failed for the intended reason)" || { echo "  FAIL 15b: unguarded bid read, or it failed for another reason: $o15"; FAIL=1; }
sed 's/H4NewBarForLife(g_hist, new_bar)/new_bar/' $EA > "$NEG15/m3.mq5"
o15=$(check_hist_wiring "$NEG15/m3.mq5"); r15=$?; { [ $r15 -ne 0 ] && echo "$o15" | grep -q "Poll must pass H4NewBarForLife" && ! echo "$o15" | grep -q "function body not found"; } && echo "  PASS 15c: raw new_bar passed to the lifecycle detected (failed for the intended reason)" || { echo "  FAIL 15c: raw new_bar in Poll, or it failed for another reason: $o15"; FAIL=1; }
sed 's/double bid = 0.0;/double bid = 0.0; datetime tc = TimeCurrent();/' $EA > "$NEG15/m4.mq5"
o15=$(check_hist_wiring "$NEG15/m4.mq5"); r15=$?; { [ $r15 -ne 0 ] && echo "$o15" | grep -q "live price / clock API in the EA" && ! echo "$o15" | grep -q "function body not found"; } && echo "  PASS 15d: clock API in the EA detected (failed for the intended reason)" || { echo "  FAIL 15d: TimeCurrent in the EA, or it failed for another reason: $o15"; FAIL=1; }
sed 's/H4SelectionPrice(g_hist, g_bars\[g_n - 1\].close, bid, g_price)/bid/' $EA > "$NEG15/m5.mq5"
o15=$(check_hist_wiring "$NEG15/m5.mq5"); r15=$?; { [ $r15 -ne 0 ] && echo "$o15" | grep -q "RefreshPrice must take its price from H4SelectionPrice" && ! echo "$o15" | grep -q "function body not found"; } && echo "  PASS 15e: price bypassing H4SelectionPrice detected (failed for the intended reason)" || { echo "  FAIL 15e: price not taken from H4SelectionPrice, or it failed for another reason: $o15"; FAIL=1; }
rm -rf "$NEG15"

echo "=== RESULT ==="
[ $FAIL -eq 0 ] && echo "ALL STATIC CHECKS PASSED (not a compilation, not a runtime test)" || echo "STATIC CHECKS FAILED"
exit $FAIL
