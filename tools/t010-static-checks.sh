#!/bin/bash
# Static checks for T010 (news + spread filters). NOT a compiler, NOT an MT5 run: MetaEditor compile, the MT5 run, the live
# calendar and the Strategy Tester behaviour are UNVERIFIED. Each checker is shown to fail on a mutated copy (negative controls).
# Usage: bash tools/t010-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=8c562fe
HDR=src/include/NewsSpreadFilters.mqh
TST=src/tests/T010_FiltersTest.mq5
EA=src/XauUsdTradePreview.mq5
REF=tests/t010_filters_reference.py
CHK="python3 -I tools/t010-static-check.py"
NEWFILES="$HDR $TST $REF tests/t010_filters_fixtures.py tests/test_t010_filters.py tools/t010-static-check.py tools/t010-static-checks.sh tasks/T010-news-spread-filters.md docs/T010-news-spread.md reports/T010-verification.md"

echo "=== S1: files exist ==="
for f in $NEWFILES $EA; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading API, no persistence / network ==="
out=$($CHK trading $HDR $TST $EA) && echo "  PASS no order/position API (OrderCalcProfit read-only estimate is the only broker call)" || { echo "$out"; FAIL=1; }
out=$($CHK persist $HDR $TST $EA $REF) && echo "  PASS no file, global-variable, network or mail access" || { echo "$out"; FAIL=1; }

echo "=== S3: calendar confined to the reader, tester guard, server-time basis, wiring ==="
out=$($CHK calendar $HDR $TST $EA) && echo "  PASS Calendar* calls only inside ReadUsdCalendar" || { echo "$out"; FAIL=1; }
out=$($CHK tester $EA) && echo "  PASS tester guard precedes the first calendar call" || { echo "$out"; FAIL=1; }
out=$($CHK servertime $HDR $EA) && echo "  PASS no TimeLocal/TimeGMT/TimeCurrent in header, reader or news block; now=TimeTradeServer()" || { echo "$out"; FAIL=1; }
out=$($CHK wiring $EA) && echo "  PASS MANUAL defaults, one quote read, spread uses it, no timer/OnTick" || { echo "$out"; FAIL=1; }
out=$($CHK reader $EA) && echo "  PASS reader: range helper -> int CalendarValueHistory -> GetLastError -> pure classifier -> conversion; no bool, no now+-1800 query" || { echo "$out"; FAIL=1; }
out=$($CHK guards $HDR) && echo "  PASS boundary, tolerance, unknown and unset guards present" || { echo "$out"; FAIL=1; }
out=$($CHK contract $HDR) && echo "  PASS header keeps the contract text" || { echo "$out"; FAIL=1; }

echo "=== S4: balance, format strings, includes, ASCII ==="
python3 tools/t001-check-balance.py $HDR $TST $EA || FAIL=1
python3 - $HDR $TST $EA <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $HDR $TST $EA; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
for f in $NEWFILES $EA; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every T010 file and the preview EA"

echo "=== S5: everything else identical to $BASE (only the preview EA may differ) ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  changed=$(git diff --name-only "$BASE" -- . ; git ls-files --others --exclude-standard)
  printf '%s\n' "$EA" docs/STATE.md $NEWFILES > "$NEG/allowed.txt"
  extra=$(echo "$changed" | sort -u | grep -v '^$' | grep -vxFf "$NEG/allowed.txt" || true)
  if [ -z "$extra" ]; then echo "  PASS changed/new paths are only the preview EA, T010 files and docs/STATE.md"
  else echo "$extra" | sed 's/^/  FAIL unexpected change: /'; FAIL=1; fi
  for p in docs/PROJECT_CHECKLIST.md docs/PROJECT_PROGRESS.html src/include/SessionPolicy.mqh src/include/TradePlanning.mqh src/include/BrokerLossCheck.mqh src/tests/T009_SessionTest.mq5 tests/test_t009_session.py tests/t009_session_reference.py; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S6: negative controls ==="
mut() { python3 -I - "$1" "$2" "$3" "$4" <<'PYEOF'
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding='ascii').read()
if old not in t:
    sys.exit(3)
open(dst, 'w', encoding='ascii').write(t.replace(old, new, 1))
PYEOF
}
neg() {  # neg LABEL CHECK SRC OLD NEW SUBSTRING [OTHER FILES AFTER...]
  local label="$1" chk="$2" src="$3" old="$4" new="$5" sub="$6"; shift 6
  local f="$NEG/$(basename "$src")" out
  if ! mut "$src" "$f" "$old" "$new"; then echo "  FAIL $label: mutation target absent (vacuous control)"; FAIL=1; return; fi
  out=$($CHK "$chk" "$@" 2>&1)
  echo "$out" | grep -qF -- "$sub" && echo "  PASS $label (detected: $sub)" || { echo "  FAIL $label: $out"; FAIL=1; }
}
# the mutated copy keeps its base name; the checkers receive it in place of the original
neg "order structure in the header" trading $HDR "bool NF_Finite(" "MqlTradeRequest rq; bool NF_Finite(" "MqlTradeRequest" "$NEG/NewsSpreadFilters.mqh"
neg "calendar call in the header" calendar $HDR "bool NF_Finite(" "int xx=CalendarValueHistory(v,0,0); bool NF_Finite(" "calendar call outside the reader" "$NEG/NewsSpreadFilters.mqh" $TST $EA
neg "calendar call outside the reader in the EA" calendar $EA "int OnInit() {Evaluate();" "int OnInit() {MqlCalendarValue qv[];CalendarValueHistory(qv,0,0);Evaluate();" "outside ReadUsdCalendar" $HDR $TST "$NEG/XauUsdTradePreview.mq5"
neg "tester guard removed" tester $EA "if(MQLInfoInteger(MQL_TESTER)) return(NF_Q_TESTER);" "" "tester guard missing" "$NEG/XauUsdTradePreview.mq5"
neg "TimeGMT in the news block" servertime $EA "int news_query=ReadUsdCalendar(now," "datetime g=TimeGMT();int news_query=ReadUsdCalendar(now," "TimeGMT" $HDR "$NEG/XauUsdTradePreview.mq5"
neg "file access in the header" persist $HDR "bool NF_Finite(" "int h=FileOpen(\"x\",FILE_WRITE); bool NF_Finite(" "FileOpen" "$NEG/NewsSpreadFilters.mqh"
neg "query narrowed back to now+-1800" reader $EA "CalendarValueHistory(values,query_from,query_to,NULL,\"USD\")" "CalendarValueHistory(values,now-NF_WINDOW_SECONDS,now+NF_WINDOW_SECONDS,NULL,\"USD\")" "now+-window" "$NEG/XauUsdTradePreview.mq5"
neg "result stored as bool" reader $EA "int ret=CalendarValueHistory(" "bool ret=CalendarValueHistory(" "stored as bool" "$NEG/XauUsdTradePreview.mq5"
neg "classifier call removed from the reader" reader $EA "int read_status=NF_ClassifyCalendarRead(ret,read_error,total);" "int read_status=NF_Q_OK;" "lacks NF_ClassifyCalendarRead" "$NEG/XauUsdTradePreview.mq5"
neg "range helper call removed from the reader" reader $EA "if(!NF_QueryRange(now,query_from,query_to))" "if(false)" "lacks NF_QueryRange" "$NEG/XauUsdTradePreview.mq5"
neg "classifier accepts ret above size" guards $HDR "if(ret>array_size) return(NF_Q_ERROR);" "" "guard expression missing" "$NEG/NewsSpreadFilters.mqh"
neg "range lost the extra day" guards $HDR "NF_FloorDay((long)now-NF_WINDOW_SECONDS)-NF_DAY_SECONDS" "NF_FloorDay((long)now-NF_WINDOW_SECONDS)" "guard expression missing" "$NEG/NewsSpreadFilters.mqh"
neg "boundary made exclusive in the header" guards $HDR "d>=-NF_WINDOW_SECONDS && d<=NF_WINDOW_SECONDS" "d>-NF_WINDOW_SECONDS && d<NF_WINDOW_SECONDS" "guard expression missing" "$NEG/NewsSpreadFilters.mqh"
neg "second quote read in the EA" wiring $EA "int OnInit() {Evaluate();" "int OnInit() {MqlTick q2;SymbolInfoTick(_Symbol,q2);Evaluate();" "second quote read" "$NEG/XauUsdTradePreview.mq5"
cp $HDR "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"
cp $HDR "$NEG/NonAscii.mqh"; printf '// caf\xc3\xa9\n' >> "$NEG/NonAscii.mqh"
n=$(LC_ALL=C grep -c '[^ -~	]' "$NEG/NonAscii.mqh" || true)
[ "$n" != "0" ] && echo "  PASS non-ASCII byte detected" || { echo "  FAIL non-ASCII not detected"; FAIL=1; }

echo
[ $FAIL -eq 0 ] && echo "T010 STATIC CHECKS: ALL PASS (static only; MetaEditor compile, MT5 run, live calendar and tester behaviour UNVERIFIED)" || echo "T010 STATIC CHECKS: FAILURES"
exit $FAIL
