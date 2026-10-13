#!/bin/bash
# Static checks for T003 (tasks/T003-h4-bias-change.md, revision 5).
#
# These are NOT a compiler and NOT a runtime test. They prove only what can be
# read from the source: no trading API / Sleep / clock in the T003 logic and
# test script, balanced syntax, resolvable includes, no MQL4 API, matching
# format strings, ASCII-only source, no global mutable state and no window
# index inside identity builders in H4Bias.mqh, that the case data in
# src/tests/T003_LogicTest.mq5 is exactly what the Python reference model
# emits, that the Python model tests pass, that no existing T001/T002 file was
# modified, and that deferred test groups are never counted as passes.
# Compilation (MetaEditor) and the MT5 test run are still UNVERIFIED.
#
# Reuses tools/t001-check-balance.py (takes file arguments) and
# tools/t001-check-format-strings.py (hardcoded T001 file list: it is loaded
# as a module and its FILES variable is overridden here; the T001 file is not
# modified).
#
# Usage: bash tools/t003-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
HDR=src/include/H4Bias.mqh
TEST=src/tests/T003_LogicTest.mq5
PYT=tests/t003_reference_test.py
FILES="$HDR $TEST"

# trading API (same list as T002)
PAT='OrderSend|OrderSendAsync|OrderClose|OrderModify|OrderDelete|PositionClose|PositionModify|PositionOpen|CTrade|CPositionInfo|COrderInfo|MqlTradeRequest|MqlTradeResult|OrderCalcMargin|OrderCalcProfit|OnTradeTransaction|OnTrade\(|PositionSelect|PositionGet|OrderSelect|OrderGet|HistoryOrder|HistoryDeal|PositionsTotal|OrdersTotal|#include[[:space:]]*<Trade'
# blocking waits, clock and terminal/series access: none of it belongs in pure logic
PATIMPURE='\bSleep\(|\bTimeCurrent\(|\bTimeLocal\(|\bTimeTradeServer\(|\bTimeGMT\(|\bGetTickCount|\bGetMicrosecondCount|\bObject[A-Z][A-Za-z]*\(|\bChart[A-Z][A-Za-z]*\(|\bCopyRates\(|\bCopyTime\(|\bCopyHigh\(|\bCopyLow\(|\bCopyClose\(|\biTime\(|\biHigh\(|\biLow\(|\biClose\(|\biBars\(|\bSymbolInfo[A-Za-z]*\(|\bAccountInfo[A-Za-z]*\(|\bTerminalInfo[A-Za-z]*\(|\bMQLInfo[A-Za-z]*\(|\bFile[A-Z][A-Za-z]*\(|\bGlobalVariable[A-Za-z]*\(|\bEventSet[A-Za-z]*\(|\bWebRequest\(|\bSend[A-Z][A-Za-z]*\('

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
# scan_impure FILE -> prints offending lines, returns 0 when clean
scan_impure() {
  local out
  out=$(strip_comments "$1" | grep -nE "$PATIMPURE")
  if [ -n "$out" ]; then echo "$out"; return 1; fi
  return 0
}

echo "=== CHECK 1: no order/trading API in executable code (comments stripped) ==="
bad1=0
for f in $FILES; do
  out=$(scan_trading "$f") || { echo "  FAIL $f: $out"; FAIL=1; bad1=1; }
done
[ $bad1 -eq 0 ] && echo "  PASS: no order/trading API in H4Bias.mqh or T003_LogicTest.mq5"

echo "=== CHECK 2: brace / parenthesis balance per file ==="
python3 tools/t001-check-balance.py $FILES || FAIL=1

echo "=== CHECK 3: include guard closed, includes resolve ==="
# unresolved_includes FILE -> prints every #include "x" of FILE that does not exist relative to FILE's directory
unresolved_includes() {
  local f="$1" d inc bad=0
  d=$(dirname "$f")
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "    missing include: $d/$inc"; bad=1; }
  done
  return $bad
}
g=$(grep -c '^#ifndef' "$HDR"); e=$(grep -c '^#endif' "$HDR")
[ "$g" = "$e" ] && echo "  PASS $HDR: include guard balanced ($g/$e)" || { echo "  FAIL $HDR: guard $g vs endif $e"; FAIL=1; }
for f in $FILES; do
  out=$(unresolved_includes "$f") && echo "  PASS $f: every include resolves" || { echo "$out"; echo "  FAIL $f: unresolved include"; FAIL=1; }
  [ "$(grep -c '#include "' "$f")" -ge 1 ] || { echo "  FAIL $f: no include found (vacuous check)"; FAIL=1; }
done

echo "=== CHECK 4: MQL4-only APIs must be absent ==="
PAT4='\bOrdersTotal\(\)|\biBars\(|\bAccountBalance\(|\bMarketInfo\(|\bOrderType\(\)|\bSymbol\(\)|\bBid\b|\bAsk\b|\bPoint\b[^(]|\bDigits\b[^(]|\bstart\(\)|\binit\(\)|\bdeinit\(\)'
bad4=0
for f in $FILES; do
  out=$(strip_comments "$f" | grep -nE "$PAT4")
  if [ -n "$out" ]; then echo "  FAIL $f: $out"; bad4=1; FAIL=1; fi
done
[ $bad4 -eq 0 ] && echo "  PASS: no MQL4-style API used"
grep -qE "^void OnStart\(" $TEST && echo "  PASS $TEST OnStart defined (script)" || { echo "  FAIL OnStart missing in test"; FAIL=1; }

echo "=== CHECK 5: StringFormat/PrintFormat specifiers match argument count ==="
python3 - $FILES <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF

echo "=== CHECK 6: source must stay pure ASCII ==="
for f in $FILES $PYT tools/t003-static-checks.sh; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  if [ "$n" != "0" ]; then
    echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1
  else
    echo "  PASS $f: ASCII only"
  fi
done

echo "=== CHECK 7: pure logic (no Sleep, clock, chart/object/series/terminal access) ==="
bad7=0
for f in $FILES; do
  out=$(scan_impure "$f") || { echo "  FAIL $f is not pure: $out"; FAIL=1; bad7=1; }
done
[ $bad7 -eq 0 ] && echo "  PASS: H4Bias.mqh and T003_LogicTest.mq5 use no Sleep, clock, object, chart or series access"

echo "=== CHECK 8: no global mutable state in H4Bias.mqh (stateless rebuild) ==="
# a global variable declaration starts in column 0 with a type and ends in = or ;
# (functions have a parenthesis after the name; #define and struct are not variables)
glob_vars() { strip_comments "$1" | grep -nE '^(static[[:space:]]+)?(const[[:space:]]+)?(int|uint|long|ulong|double|float|string|bool|datetime|color|char|uchar|short|ushort)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?[[:space:]]*(=|;)'; }
out=$(glob_vars $HDR)
if [ -n "$out" ]; then echo "  FAIL global variable(s) in $HDR: $out"; FAIL=1; else echo "  PASS: $HDR declares no global variable (every function works on its arguments)"; fi
out=$(strip_comments $HDR | grep -nE '\bstatic\b')
if [ -n "$out" ]; then echo "  FAIL static storage in $HDR: $out"; FAIL=1; else echo "  PASS: no 'static' storage in $HDR"; fi

echo "=== CHECK 9: identity builders use absolute times only, never a window index ==="
# fn_body FILE PREFIX -> stripped source of the function whose DEFINITION line starts with the literal
# text PREFIX. The prefix is matched with index() and handed over through the environment (no regex
# crosses awk -v). Definitions end with a line of exactly two spaces and a closing brace.
fn_body() { strip_comments "$1" | FN_PREFIX="$2" awk 'index($0, ENVIRON["FN_PREFIX"]) == 1 && $0 !~ /;[ \t]*$/ {p=1} p{print} p&&/^  }$/{exit}'; }
# check_ids FILE -> prints violations, returns 0 when intact
check_ids() {
  local f="$1" bad=0 fn b sig
  for fn in 'string H3LevelId(' 'string H3ExtId(' 'string H3InteriorId(' 'string H3EventId(' 'string H3EventText('; do
    b=$(fn_body "$f" "$fn")
    [ -n "$b" ] || { echo "    function body not found: $fn"; bad=1; continue; }
    sig=$(echo "$b" | sed -n '1p')
    echo "$sig" | grep -qiE '\b(idx|index|pos|bar_index|window)\b' && { echo "    window index parameter in: $sig"; bad=1; }
    echo "$b" | sed '1d' | grep -qE '\bidx\b|\bindex\b|\.idx\b|\.index\b|\.f\b|\[' && { echo "    window index or array subscript inside: $fn"; bad=1; }
  done
  # the time based builders must use the T002 absolute time stamp helper
  for fn in 'string H3LevelId(' 'string H3ExtId(' 'string H3InteriorId(' 'string H3EventId('; do
    fn_body "$f" "$fn" | grep -q 'H4TimeStamp(' || { echo "    $fn does not build from H4TimeStamp"; bad=1; }
  done
  return $bad
}
out=$(check_ids $HDR) && echo "  PASS: level, extreme, interior and event IDs are built from H4TimeStamp of pivot/bar times; no index in signature or body" || { echo "$out"; echo "  FAIL identity builders"; FAIL=1; }
# the generated expected transcripts must not carry bar counts either: IDs in the data block are 12-digit stamps
n_bad=$(awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p' $TEST | grep -oE '(SH|SL|HH|LL|IH|IL)[0-9]+_' | grep -vE '^(SH|SL|HH|LL|IH|IL)[0-9]{12}_$' | wc -l)
[ "$n_bad" = "0" ] && echo "  PASS: every level/extreme/interior id in the expected transcripts starts with a 12-digit time stamp" || { echo "  FAIL: $n_bad id(s) in the data block are not 12-digit time stamps"; FAIL=1; }

echo "=== CHECK 10: generated case data in the MQL5 test matches the Python model ==="
python3 $PYT --emit-mql > "$TMPD/emit" 2>/dev/null
awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p{print} /^\/\/ END GENERATED CASE DATA/{p=0}' $TEST > "$TMPD/have"
# Windows Python emits CRLF, the source block is LF: normalise both sides.
tr -d '\r' < "$TMPD/emit" > "$TMPD/emit.n"; tr -d '\r' < "$TMPD/have" > "$TMPD/have.n"
if [ -s "$TMPD/emit.n" ] && cmp -s "$TMPD/emit.n" "$TMPD/have.n"; then
  echo "  PASS: generated block in $TEST equals --emit-mql output"
else
  echo "  FAIL: generated block in $TEST differs from $PYT --emit-mql"; FAIL=1
fi
cc=$(grep -c '^      case [0-9]*:' "$TMPD/have.n"); decl=$(grep -oE '#define T3_CASE_COUNT [0-9]+' "$TMPD/have.n" | awk '{print $3}')
[ "$cc" = "$decl" ] && [ "$cc" -gt 0 ] && echo "  PASS: T3_CASE_COUNT ($decl) equals the number of generated cases" || { echo "  FAIL: T3_CASE_COUNT $decl vs $cc cases"; FAIL=1; }

echo "=== CHECK 11: Python reference model tests (verify the MODEL only) ==="
python3 $PYT > "$TMPD/py" 2>&1; rc=$?
if [ $rc -eq 0 ]; then echo "  PASS: $(grep -E '^[0-9]+ passed' "$TMPD/py")"; else tail -5 "$TMPD/py"; echo "  FAIL: reference tests"; FAIL=1; fi
nd=$(grep -c 'DEFERRED (not implemented in this round)' "$TMPD/py")
[ "$nd" -ge 5 ] && echo "  PASS: the Python run prints $nd explicit DEFERRED lines (never counted as PASS)" || { echo "  FAIL: expected at least 5 DEFERRED lines in the Python run, found $nd"; FAIL=1; }
grep -q 'DEFERRED.*PASS' "$TMPD/py" && { echo "  FAIL: a DEFERRED line contains PASS"; FAIL=1; }
# the MQL5 Deferred() helper must not touch the pass counter
db=$(fn_body $TEST 'void Deferred(')
if [ -n "$db" ] && ! echo "$db" | grep -q 'g_pass' && echo "$db" | grep -q 'DEFERRED (not implemented in this round)'; then
  echo "  PASS: MQL5 Deferred() prints DEFERRED and never increments g_pass"
else
  echo "  FAIL: MQL5 Deferred() missing, or it touches g_pass"; FAIL=1
fi
nm=$(strip_comments $TEST | grep -c 'Deferred("')
[ "$nm" -ge 5 ] && echo "  PASS: the MQL5 test lists $nm deferred groups" || { echo "  FAIL: fewer than 5 deferred groups in the MQL5 test"; FAIL=1; }

echo "=== CHECK 12: no existing T001/T002 (or other pre-existing) file was modified ==="
# check_unmodified REPO FILES... -> returns 0 when none of the files differ from HEAD
check_unmodified() {
  local repo="$1"; shift
  git -C "$repo" diff --quiet HEAD -- "$@" 2>/dev/null
}
EXISTING=$(git ls-files)
tracked_new=0
if check_unmodified . $EXISTING; then
  echo "  PASS: every tracked file is identical to HEAD (git diff --quiet HEAD)"
else
  echo "  FAIL: a tracked file differs from HEAD:"; git diff --stat HEAD | tail -5; FAIL=1
fi
if git cat-file -e dd571f6 2>/dev/null; then
  if git diff --quiet dd571f6 -- $(git ls-tree -r --name-only dd571f6) 2>/dev/null; then
    echo "  PASS: every file that exists at base commit dd571f6 is identical to it (working tree)"
  else
    echo "  FAIL: a file of base commit dd571f6 differs in the working tree"; git diff --stat dd571f6 | tail -5; FAIL=1
  fi
else
  echo "  INFO: base commit dd571f6 not available here; the parent must verify against it"
fi
echo "  INFO: new (untracked) files: $(git ls-files --others --exclude-standard | tr '\n' ' ')"
echo "  INFO: the parent still verifies the final change set against the base commit"

echo "=== CHECK 13: negative controls (every checker must actually detect its problem, for the intended reason) ==="
NEG=$(mktemp -d)
cp $HDR "$NEG/h.mqh"
# 13a: injected trading API
printf 'void F(){ MqlTradeRequest r; OrderSend(r, res); }\n' > "$NEG/a.mqh"
out=$(scan_trading "$NEG/a.mqh") && { echo "  FAIL 13a: injected OrderSend was NOT detected"; FAIL=1; } || { echo "$out" | grep -q 'OrderSend' && echo "  PASS 13a: injected OrderSend / MqlTradeRequest detected (reason: trading API)" || { echo "  FAIL 13a: failed for another reason: $out"; FAIL=1; }; }
# 13b: the same words inside comments must NOT be flagged
printf '// OrderSend and Sleep( are forbidden\n/* CTrade\n   PositionClose TimeCurrent() */\nvoid F(){}\n' > "$NEG/b.mqh"
scan_trading "$NEG/b.mqh" >/dev/null && scan_impure "$NEG/b.mqh" >/dev/null && echo "  PASS 13b: trading/clock words in comments are ignored" || { echo "  FAIL 13b: comment-only mention flagged"; FAIL=1; }
# 13c: Sleep, clock and series access in executable code
for snippet in 'void F(){ Sleep(10); }' 'datetime F(){ return(TimeCurrent()); }' 'void F(){ MqlRates r[]; CopyRates(_Symbol, PERIOD_H4, 0, 5, r); }' 'void F(){ ObjectCreate(0, "x", OBJ_LABEL, 0, 0, 0); }' 'double F(){ return(iClose(_Symbol, PERIOD_H4, 1)); }'; do
  printf '%s\n' "$snippet" > "$NEG/c.mqh"
  out=$(scan_impure "$NEG/c.mqh") && { echo "  FAIL 13c: impure construct not detected: $snippet"; FAIL=1; } || echo "  PASS 13c: detected as impure: $snippet"
done
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
sed 's/FLAG=CONVERGED/FLAG=SEEDED/' $TEST | awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p{print} /^\/\/ END GENERATED CASE DATA/{p=0}' > "$NEG/have.txt"
python3 $PYT --emit-mql | tr -d '\r' > "$NEG/emit.txt"
tr -d '\r' < "$NEG/have.txt" > "$NEG/have.n"
cmp -s "$NEG/have.n" "$NEG/emit.txt" && { echo "  FAIL 13f: altered data block not detected"; FAIL=1; } || echo "  PASS 13f: altered generated data detected"
# 13g: a CRLF-converted copy of the (unaltered) block must compare equal after normalisation
awk '/^\/\/ BEGIN GENERATED CASE DATA/{p=1} p{print} /^\/\/ END GENERATED CASE DATA/{p=0}' $TEST | sed 's/$/\r/' > "$NEG/crlf.txt"
cmp -s "$NEG/crlf.txt" "$NEG/emit.txt" && { echo "  FAIL 13g: raw CRLF copy unexpectedly equal (test is vacuous)"; FAIL=1; }
tr -d '\r' < "$NEG/crlf.txt" > "$NEG/crlf.n"
cmp -s "$NEG/crlf.n" "$NEG/emit.txt" && echo "  PASS 13g: CRLF copy of the block equals --emit-mql after line-ending normalisation" || { echo "  FAIL 13g: CRLF copy differs after normalisation"; FAIL=1; }
# 13h: global mutable state must be detected
cp "$NEG/h.mqh" "$NEG/h2.mqh"; printf 'int g_cache = 0;\nstring g_last;\n' >> "$NEG/h2.mqh"
out=$(glob_vars "$NEG/h2.mqh"); echo "$out" | grep -q 'g_cache' && echo "$out" | grep -q 'g_last' && echo "  PASS 13h: injected global variables detected (reason: global state)" || { echo "  FAIL 13h: global variables not detected: $out"; FAIL=1; }
# 13i: a window index in an identity builder must be detected, for the intended reason
sed 's/string H3InteriorId(const string kind, const datetime t_int, const datetime t_ext)/string H3InteriorId(const string kind, const datetime t_int, const datetime t_ext, const int idx)/' "$NEG/h.mqh" > "$NEG/i1.mqh"
o=$(check_ids "$NEG/i1.mqh"); r=$?; { [ $r -ne 0 ] && echo "$o" | grep -q 'window index parameter' && ! echo "$o" | grep -q 'function body not found'; } && echo "  PASS 13i: window index in an ID builder signature detected (intended reason)" || { echo "  FAIL 13i: index parameter not detected, or other reason: $o"; FAIL=1; }
sed 's/   return(kind + H4TimeStamp(t_int) + "_" + H4TimeStamp(t_ext));/   return(kind + H4TimeStamp(t_int) + "_" + IntegerToString(sw[0].index));/' "$NEG/h.mqh" > "$NEG/i2.mqh"
o=$(check_ids "$NEG/i2.mqh"); r=$?; { [ $r -ne 0 ] && echo "$o" | grep -q 'window index or array subscript inside' && ! echo "$o" | grep -q 'function body not found'; } && echo "  PASS 13i: window index / array subscript in an ID builder body detected (intended reason)" || { echo "  FAIL 13i: index in body not detected, or other reason: $o"; FAIL=1; }
sed 's/   return(H3EventName(type) + "@" + H4TimeStamp(bar_time) + "#" + ref);/   return(H3EventName(type) + "@" + IntegerToString(type) + "#" + ref);/' "$NEG/h.mqh" > "$NEG/i3.mqh"
o=$(check_ids "$NEG/i3.mqh"); r=$?; { [ $r -ne 0 ] && echo "$o" | grep -q 'does not build from H4TimeStamp' && ! echo "$o" | grep -q 'function body not found'; } && echo "  PASS 13i: an event ID not built from the absolute bar time detected (intended reason)" || { echo "  FAIL 13i: event id without time stamp not detected, or other reason: $o"; FAIL=1; }
# 13j: MQL4 pattern and non-ASCII detection
printf 'void F(){ int n = iBars(Symbol(), 0); }\n' > "$NEG/j.mqh"
strip_comments "$NEG/j.mqh" | grep -qE "$PAT4" && echo "  PASS 13j: MQL4 pattern iBars/Symbol() detected" || { echo "  FAIL 13j: MQL4 pattern not detected"; FAIL=1; }
printf 'void F(){ } // caf\xc3\xa9\n' > "$NEG/k.mqh"
[ "$(LC_ALL=C grep -c '[^ -~	]' "$NEG/k.mqh")" != "0" ] && echo "  PASS 13k: non-ASCII byte detected" || { echo "  FAIL 13k: non-ASCII byte not detected"; FAIL=1; }
# 13l: a modified tracked file must be detected (temporary repository)
mkdir "$NEG/repo" && git -C "$NEG/repo" init -q && echo 'one' > "$NEG/repo/f.txt" && git -C "$NEG/repo" add f.txt && git -C "$NEG/repo" -c user.email=x@x -c user.name=x commit -q -m base
check_unmodified "$NEG/repo" f.txt && echo "  PASS 13l: an unmodified file passes" || { echo "  FAIL 13l: unmodified file flagged"; FAIL=1; }
echo 'two' > "$NEG/repo/f.txt"
check_unmodified "$NEG/repo" f.txt && { echo "  FAIL 13l: a modified tracked file was NOT detected"; FAIL=1; } || echo "  PASS 13l: a modified tracked file is detected"
# 13m: the Deferred() check must notice a pass-counting deferred helper
sed 's/g_deferred++;/g_deferred++; g_pass++;/' $TEST > "$NEG/t.mq5"
db=$(fn_body "$NEG/t.mq5" 'void Deferred(')
echo "$db" | grep -q 'g_pass' && echo "  PASS 13m: a Deferred() that counts a pass is detected" || { echo "  FAIL 13m: pass-counting Deferred() not detected"; FAIL=1; }
# 13n: a deferred line that says PASS must be caught by the pattern used in CHECK 11
printf '  DEFERRED PASS (not implemented in this round): x\n' > "$NEG/dp.txt"
grep -q 'DEFERRED.*PASS' "$NEG/dp.txt" && echo "  PASS 13n: a pass-labelled deferred line is detected" || { echo "  FAIL 13n: pass-labelled deferred line not detected"; FAIL=1; }
# 13o: an unresolved include must be detected
printf '#include "does_not_exist.mqh"\nvoid F(){}\n' > "$NEG/o.mqh"
out=$(unresolved_includes "$NEG/o.mqh") && { echo "  FAIL 13o: missing include not detected"; FAIL=1; } || { echo "$out" | grep -q 'does_not_exist' && echo "  PASS 13o: a missing include is detected (intended reason)" || { echo "  FAIL 13o: other reason: $out"; FAIL=1; }; }
# 13p: a mutated reference model must make the Python run fail, for the intended reason
mkdir "$NEG/py" && cp tests/t002_reference_test.py "$NEG/py/" && sed 's/if s \* (bar.close - P) > 0:/if s * (bar.close - P) >= 0:/' $PYT > "$NEG/py/t003_reference_test.py"
cmp -s "$NEG/py/t003_reference_test.py" $PYT && { echo "  FAIL 13p: the mutation did not change the model (vacuous)"; FAIL=1; }
( cd "$NEG/py" && python3 t003_reference_test.py > out.txt 2>&1 ); rcm=$?
{ [ $rcm -ne 0 ] && grep -q 'FAILED: SELL: close exactly on the level is not a break' "$NEG/py/out.txt"; } && echo "  PASS 13p: a model that treats equality as a break fails the Python run (intended check failed)" || { echo "  FAIL 13p: mutated model not detected for the intended reason (rc=$rcm)"; FAIL=1; }
# 13q: a case-count mismatch must be detected
sed 's/#define T3_CASE_COUNT [0-9]*/#define T3_CASE_COUNT 1/' "$TMPD/have.n" > "$NEG/cnt.n"
cc2=$(grep -c '^      case [0-9]*:' "$NEG/cnt.n"); decl2=$(grep -oE '#define T3_CASE_COUNT [0-9]+' "$NEG/cnt.n" | awk '{print $3}')
[ "$cc2" != "$decl2" ] && echo "  PASS 13q: a wrong T3_CASE_COUNT is detected" || { echo "  FAIL 13q: count mismatch not detected"; FAIL=1; }
# 13r: fewer than 5 DEFERRED lines must be detected
printf '  DEFERRED (not implemented in this round): a\n' > "$NEG/d5.txt"
[ "$(grep -c 'DEFERRED (not implemented in this round)' "$NEG/d5.txt")" -lt 5 ] && echo "  PASS 13r: too few DEFERRED lines would be detected" || { echo "  FAIL 13r"; FAIL=1; }
rm -rf "$NEG"

echo "=== RESULT ==="
[ $FAIL -eq 0 ] && echo "ALL STATIC CHECKS PASSED (not a compilation, not a runtime test)" || echo "STATIC CHECKS FAILED"
exit $FAIL
