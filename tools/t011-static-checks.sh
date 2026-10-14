#!/bin/bash
# Static checks for T011 (pure 80/20 exit split). NOT a compiler, NOT an MT5 run: MetaEditor compile and the MT5 run are UNVERIFIED.
# Usage: bash tools/t011-static-checks.sh   (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=1e34b34   # the base of the split module; the checklist and progress page are Codex-owned and were not changed by T011
HDR=src/include/ExitSplit.mqh
TST=src/tests/T011_SplitTest.mq5
REF=tests/t011_split_reference.py
NEWFILES="$HDR $TST $REF tests/t011_split_fixtures.py tests/test_t011_split.py tools/t011-static-checks.sh tasks/T011-exit-split.md reports/T011-verification.md"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading API, no persistence / network / account / symbol read ==="
out=$(python3 -I tools/t010-static-check.py trading $HDR $TST) && echo "  PASS no order/position API" || { echo "$out"; FAIL=1; }
out=$(python3 -I tools/t010-static-check.py persist $HDR $TST $REF) && echo "  PASS no file, global-variable, network or mail access" || { echo "$out"; FAIL=1; }
for f in $HDR $TST; do
  if grep -nE 'Account(Info|InfoDouble|InfoInteger)|SymbolInfo|SymbolSelect|TimeCurrent|TimeLocal|TimeGMT|TimeTradeServer|iClose|iOpen|CopyRates|OrderCalcProfit' "$f" >/dev/null; then
    echo "  FAIL $f reads account, symbol, clock or prices"; FAIL=1
  else echo "  PASS $f: no account, symbol, clock or price read"; fi
done

echo "=== S3: T006 grid reused, not copied; contract ==="
grep -q 'PS_GridSteps(' $HDR && grep -q '#include "PositionSizing.mqh"' $HDR && ! grep -q 'PS_GRID_ULPS\|DBL_EPSILON' $HDR \
  && echo "  PASS header calls PS_GridSteps from PositionSizing.mqh, no grid tolerance of its own" || { echo "  FAIL grid reuse"; FAIL=1; }
grep -q 'n%ES_CLOSE_DEN!=0' $HDR && grep -q 'ES_SPLIT_POLICY_UNSET' $HDR && echo "  PASS exact-or-nothing guard present" || { echo "  FAIL exact guard"; FAIL=1; }
for f in $HDR $TST; do grep -q 'MathRound\|MathCeil\|NormalizeDouble' "$f" && { echo "  FAIL $f rounds"; FAIL=1; } || echo "  PASS $f: no rounding function"; done

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
for f in $NEWFILES; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every T011 file"

echo "=== S5: the files T011 must not change are identical to $BASE (the tree has moved on since: T003 panel, activation) ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/PositionSizing.mqh src/include/TradeGeometry.mqh tests/t006_sizing_reference.py src/include/H4Bias.mqh src/include/H4Structure.mqh; do
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
mutate "order structure in the header" $HDR "bool ES_Fail(" "MqlTradeRequest rq; bool ES_Fail(" python3 -I tools/t010-static-check.py trading
mutate "file access in the header" $HDR "bool ES_Fail(" 'int h=FileOpen("x",FILE_WRITE); bool ES_Fail(' python3 -I tools/t010-static-check.py persist
cp $HDR "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"
cp $HDR "$NEG/NonAscii.mqh"; printf '// caf\xc3\xa9\n' >> "$NEG/NonAscii.mqh"
n=$(LC_ALL=C grep -c '[^ -~	]' "$NEG/NonAscii.mqh" || true)
[ "$n" != "0" ] && echo "  PASS non-ASCII byte detected" || { echo "  FAIL non-ASCII not detected"; FAIL=1; }

echo
[ $FAIL -eq 0 ] && echo "T011 STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T011 STATIC CHECKS: FAILURES"
exit $FAIL
