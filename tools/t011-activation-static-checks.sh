#!/bin/bash
# Static checks for the T011 activation state machine (ExitActivation). NOT a compiler, NOT an MT5 run: MetaEditor compile and the
# MT5 run are UNVERIFIED. Usage: bash tools/t011-activation-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=35e8740
HDR=src/include/ExitActivation.mqh
TST=src/tests/T011_ActivationTest.mq5
REF=tests/t011_activation_reference.py
NEWFILES="$HDR $TST $REF tests/t011_activation_fixtures.py tests/test_t011_activation.py tools/t011-activation-static-checks.sh tasks/T011-exit-activation.md"

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

echo "=== S3: split and grid reused, transitions present ==="
grep -q 'ES_Split(' $HDR && grep -q 'PS_GridSteps(' $HDR && grep -q '#include "ExitSplit.mqh"' $HDR && ! grep -q 'ES_CLOSE_NUM\|ES_CLOSE_DEN\|PS_GRID_ULPS\|DBL_EPSILON' $HDR \
  && echo "  PASS ES_Split and PS_GridSteps are called, no 4/5 or grid tolerance of its own" || { echo "  FAIL split/grid reuse"; FAIL=1; }
for pat in 'bid>=level_2r : ask<=level_2r' 'EA_ST_REQUEST_PENDING' 'EA_ST_NEEDS_RECONCILIATION' 'EA_ST_BLOCKED' 'WRONG_REQUEST_ID' 'DUPLICATE_IGNORED' 'steps!=s.request_steps' 'cur!=sp.initial_steps' 'volume_step!=s.volume_step' 'PS_GridSteps(executed_volume,s.volume_step)' 'sp.status==ES_INVALID_INPUT'; do
  grep -qF -- "$pat" $HDR && echo "  PASS header has: $pat" || { echo "  FAIL header lacks: $pat"; FAIL=1; }
done
grep -c 'EA_ACT_REQUEST_PARTIAL_CLOSE' $HDR | grep -qx 3 && echo "  PASS the request action is set in exactly one place (plus enum and name)" || { echo "  FAIL request action count"; FAIL=1; }

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
echo "  INFO ASCII-only checked for every activation file"

echo "=== S5: the files the activation must not change are identical to $BASE (the tree has moved on: reconciliation) ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/ExitSplit.mqh tests/t011_split_reference.py src/include/PositionSizing.mqh src/include/TradeGeometry.mqh src/include/H4Bias.mqh src/include/H4Structure.mqh src/include/TradePlanning.mqh src/include/NewsSpreadFilters.mqh src/include/SessionPolicy.mqh src/include/BrokerLossCheck.mqh src/include/H4BiasDrawer.mqh src/include/H4BiasLayers.mqh; do
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
mutate "order structure in the header" $HDR "bool EA_PositiveFinite(" "MqlTradeRequest rq; bool EA_PositiveFinite(" python3 -I tools/t010-static-check.py trading
mutate "file access in the header" $HDR "bool EA_PositiveFinite(" 'int h=FileOpen("x",FILE_WRITE); bool EA_PositiveFinite(' python3 -I tools/t010-static-check.py persist
cp $HDR "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"
cp $HDR "$NEG/NonAscii.mqh"; printf '// caf\xc3\xa9\n' >> "$NEG/NonAscii.mqh"
n=$(LC_ALL=C grep -c '[^ -~	]' "$NEG/NonAscii.mqh" || true)
[ "$n" != "0" ] && echo "  PASS non-ASCII byte detected" || { echo "  FAIL non-ASCII not detected"; FAIL=1; }

echo
[ $FAIL -eq 0 ] && echo "T011 ACTIVATION STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T011 ACTIVATION STATIC CHECKS: FAILURES"
exit $FAIL
