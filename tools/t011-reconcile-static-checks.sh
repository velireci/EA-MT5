#!/bin/bash
# Static checks for the T011 reconciliation (ExitReconciliation). NOT a compiler, NOT an MT5 run: MetaEditor compile and the
# MT5 run are UNVERIFIED. Usage: bash tools/t011-reconcile-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=d83426a
HDR=src/include/ExitReconciliation.mqh
TST=src/tests/T011_ReconcileTest.mq5
REF=tests/t011_reconcile_reference.py
NEWFILES="$HDR $TST $REF tests/t011_reconcile_fixtures.py tests/test_t011_reconcile.py tools/t011-reconcile-static-checks.sh tasks/T011-exit-reconciliation.md"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading API, no persistence, no account / symbol / clock / price read ==="
out=$(python3 -I tools/t010-static-check.py trading $HDR $TST) && echo "  PASS no order/position API" || { echo "$out"; FAIL=1; }
out=$(python3 -I tools/t010-static-check.py persist $HDR $TST $REF) && echo "  PASS no file, global-variable, network or mail access" || { echo "$out"; FAIL=1; }
for f in $HDR $TST; do
  if grep -nE 'Account(Info|InfoDouble|InfoInteger)|SymbolInfo|SymbolSelect|TimeCurrent|TimeLocal|TimeGMT|TimeTradeServer|GetTickCount|EventSetTimer|iClose|iOpen|CopyRates|OrderCalcProfit|HistorySelect|PositionSelect|PositionGet|MathRand' "$f" >/dev/null; then
    echo "  FAIL $f reads account, symbol, positions, clock or prices"; FAIL=1
  else echo "  PASS $f: no account, symbol, position, clock or price read"; fi
done

echo "=== S3: grid reused, one source of state, no request, no re-planning ==="
grep -q 'PS_GridSteps(' $HDR && grep -q '#include "ExitActivation.mqh"' $HDR && ! grep -q 'PS_GRID_ULPS\|DBL_EPSILON\|ES_CLOSE_NUM\|ES_CLOSE_DEN' $HDR \
  && echo "  PASS PS_GridSteps is called, SEaState of ExitActivation is the only state, no grid tolerance or 4/5 of its own" || { echo "  FAIL grid / state reuse"; FAIL=1; }
for bad in 'EA_OnQuote' 'EA_OnReport' 'ES_Split' 'EA_ACT_REQUEST_PARTIAL_CLOSE' 'EA_RequestId' 'st\.request_steps *=[^=]' 'st\.initial_steps *=[^=]' 'st\.volume_step *=[^=]' 'st\.request_id *=[^=]' 'st\.position_id *=[^=]' 'st\.close_volume *=[^=]'; do
  if grep -qE -- "$bad" $HDR; then echo "  FAIL header contains $bad (it must neither request nor re-plan)"; FAIL=1; else echo "  PASS header does not contain $bad"; fi
done
for pat in 'st.status=EA_ST_DONE' 'st.confirmations++' 'linked>req' 'cur!=expected' 'snap.volume_step!=st.volume_step' 'snap.position_id!=st.position_id' 'snap.request_id!=st.request_id' '!snap.position_found' 'EXEC_ID_CONFLICT' 'if(complete)' 'ALREADY_BLOCKED'; do
  grep -qF -- "$pat" $HDR && echo "  PASS header has: $pat" || { echo "  FAIL header lacks: $pat"; FAIL=1; }
done
[ "$(grep -c 'st.status=EA_ST_DONE' $HDR)" = "1" ] && echo "  PASS DONE is set in exactly one place" || { echo "  FAIL DONE count"; FAIL=1; }

echo "=== S4: balance, format strings, includes, ASCII ==="
python3 tools/t001-check-balance.py $HDR $TST || FAIL=1
python3 - $HDR $TST <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $HDR $TST; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
# MQL5 array initializers must be constants (a variable inside {..} is a compile error)
if grep -nE '\[[0-9]*\] *= *\{[^}]*\b(nan|inf|[a-z_]+\[)' $TST >/dev/null; then echo "  FAIL non-constant array initializer"; FAIL=1; else echo "  PASS array initializers are constants"; fi
for f in $NEWFILES; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every reconciliation file"

echo "=== S5: nothing else changed relative to $BASE (T001-T010, the split module, the panel, the checklist untouched) ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  changed=$(git diff --name-only "$BASE" -- . ; git ls-files --others --exclude-standard)
  printf '%s\n' docs/STATE.md reports/T011-verification.md $NEWFILES > "$NEG/allowed.txt"
  extra=$(echo "$changed" | sort -u | grep -v '^$' | grep -vxFf "$NEG/allowed.txt" || true)
  if [ -z "$extra" ]; then echo "  PASS changed/new paths are only the reconciliation files, T011 docs and docs/STATE.md"
  else echo "$extra" | sed 's/^/  FAIL unexpected change: /'; FAIL=1; fi
  for p in docs/PROJECT_CHECKLIST.md docs/PROJECT_PROGRESS.html src/include/ExitSplit.mqh src/include/ExitActivation.mqh tests/t011_split_reference.py tests/t011_activation_reference.py src/include/PositionSizing.mqh src/include/TradeGeometry.mqh src/include/H4Bias.mqh src/include/H4Structure.mqh src/include/TradePlanning.mqh src/include/NewsSpreadFilters.mqh src/include/SessionPolicy.mqh src/include/BrokerLossCheck.mqh src/include/H4BiasDrawer.mqh src/include/H4BiasLayers.mqh; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S6: negative controls ==="
mutate() {  # mutate LABEL SRC OLD NEW CHECKCMD...  : the check must FAIL on the mutated copy
  local label="$1" src="$2" old="$3" new="$4"; shift 4
  local f="$NEG/$(basename "$src")"
  python3 -I - "$src" "$f" "$old" "$new" <<'PYEOF' || { echo "  FAIL $label: mutation target absent (vacuous control)"; FAIL=1; return; }
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding='ascii').read()
if old not in t:
    sys.exit(3)
open(dst, 'w', encoding='ascii').write(t.replace(old, new, 1))
PYEOF
  if "$@" "$f" >/dev/null 2>&1; then echo "  FAIL $label: not detected"; FAIL=1; else echo "  PASS $label (detected)"; fi
}
mutate "order structure in the header" $HDR "string ER_DecisionName(" "MqlTradeRequest rq; string ER_DecisionName(" python3 -I tools/t010-static-check.py trading
mutate "file access in the header" $HDR "string ER_DecisionName(" 'int h=FileOpen("x",FILE_WRITE); string ER_DecisionName(' python3 -I tools/t010-static-check.py persist
cp $HDR "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"
cp $HDR "$NEG/NonAscii.mqh"; printf '// caf\xc3\xa9\n' >> "$NEG/NonAscii.mqh"
n=$(LC_ALL=C grep -c '[^ -~	]' "$NEG/NonAscii.mqh" || true)
[ "$n" != "0" ] && echo "  PASS non-ASCII byte detected" || { echo "  FAIL non-ASCII not detected"; FAIL=1; }

echo
[ $FAIL -eq 0 ] && echo "T011 RECONCILE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T011 RECONCILE STATIC CHECKS: FAILURES"
exit $FAIL
