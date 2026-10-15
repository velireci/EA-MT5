#!/bin/bash
# Static checks for T012 (pure daily limits). NOT a compiler, NOT an MT5 run: MetaEditor compile and the MT5 run are UNVERIFIED.
# Usage: bash tools/t012-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=ca3bd57
HDR=src/include/DailyLimits.mqh
TST=src/tests/T012_DailyLimitsTest.mq5
REF=tests/t012_daily_reference.py
NEWFILES="$HDR $TST $REF tests/t012_daily_fixtures.py tests/test_t012_daily.py tools/t012-static-checks.sh tasks/T012-daily-limits.md reports/T012-verification.md"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading API, no persistence, no account / position / clock / price read ==="
out=$(python3 -I tools/t010-static-check.py trading $HDR $TST) && echo "  PASS no order/position API" || { echo "$out"; FAIL=1; }
out=$(python3 -I tools/t010-static-check.py persist $HDR $TST $REF) && echo "  PASS no file, global-variable, network or mail access" || { echo "$out"; FAIL=1; }
for f in $HDR $TST; do
  if grep -nE 'Account(Info|InfoDouble|InfoInteger)|SymbolInfo|Position[A-Z]|Orders?[A-Z]|History(Select|Deal|Order)|TimeCurrent|TimeLocal|TimeGMT|TimeTradeServer|GetTickCount|EventSetTimer|iClose|CopyRates|MathRand' "$f" >/dev/null; then
    echo "  FAIL $f reads account, positions, history, clock or prices"; FAIL=1
  else echo "  PASS $f: no account, position, history, clock or price read"; fi
done

echo "=== S3: T009 reused (no DST copy), rules present ==="
grep -q 'SP_Evaluate(' $HDR && grep -q '#include "SessionPolicy.mqh"' $HDR && ! grep -qE 'SP_Edge|SP_Offset|StructToTime|TimeToStruct|7200|3600' $HDR \
  && echo "  PASS the Tirane day comes from SP_Evaluate; no DST rule, offset or time conversion of its own" || { echo "  FAIL T009 reuse"; FAIL=1; }
for pat in 'DL_WIN_STOP_AT 1' 'DL_CONSECUTIVE_LOSS_STOP_AT 2' 'DL_LOSS_DIVISOR 50.0' 'in.snapshot_day!=day' 'POLICY_UNSET:max_trades_per_day' 'DAILY_WIN_STOP' 'CONSECUTIVE_LOSSES_STOP' 'DAILY_LOSS_LIMIT' 'MAX_TRADES_REACHED' 'STALE_SNAPSHOT_DAY' 'INCONSISTENT_COUNTERS:wins_plus_losses_exceed_trades' 'r.cancel_pending_due=limit;'; do
  grep -qF -- "$pat" $HDR && echo "  PASS header has: $pat" || { echo "  FAIL header lacks: $pat"; FAIL=1; }
done
[ "$(grep -c 'cancel_pending_due=' $HDR)" = "2" ] && echo "  PASS cancel_pending_due is assigned only to false (reset) and to the proven-limit flag" || { echo "  FAIL cancel_pending_due assignments"; FAIL=1; }
grep -qE 'cancel_pending_due=(true|!|r\.n_reasons)' $HDR && { echo "  FAIL cancel_pending_due derived from reasons or true"; FAIL=1; } || echo "  PASS cancel_pending_due is not derived from the reason count"

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
if grep -nE '\[[0-9A-Za-z_]*\] *= *\{[^}]*\b(nan|inf|[a-z_]+\[)' $TST >/dev/null; then echo "  FAIL non-constant array initializer"; FAIL=1; else echo "  PASS array initializers are constants"; fi
for f in $NEWFILES; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every T012 file"

echo "=== S5: the verified modules are identical to $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in docs/PROJECT_CHECKLIST.md docs/PROJECT_PROGRESS.html src/include/SessionPolicy.mqh tests/t009_session_reference.py src/include/TradePlanning.mqh src/include/ExitSplit.mqh src/include/ExitActivation.mqh src/include/ExitReconciliation.mqh src/include/ExitSnapshotAdapter.mqh src/include/PositionSizing.mqh src/include/TradeGeometry.mqh; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S6: negative controls ==="
mutate() {  # mutate LABEL SRC OLD NEW CHECKCMD... : the check must FAIL on the mutated copy
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
mutate "order structure in the header" $HDR "bool DL_Finite(" "MqlTradeRequest rq; bool DL_Finite(" python3 -I tools/t010-static-check.py trading
mutate "file access in the header" $HDR "bool DL_Finite(" 'int h=FileOpen("x",FILE_WRITE); bool DL_Finite(' python3 -I tools/t010-static-check.py persist
cp $HDR "$NEG/Dst.mqh"; echo 'int zz = 7200;' >> "$NEG/Dst.mqh"
grep -qE 'SP_Edge|SP_Offset|StructToTime|TimeToStruct|7200|3600' "$NEG/Dst.mqh" && echo "  PASS a DST offset of its own is detected" || { echo "  FAIL DST copy not detected"; FAIL=1; }
cp $HDR "$NEG/Cancel.mqh"; sed -i 's/r.cancel_pending_due=limit;/r.cancel_pending_due=(r.n_reasons>0);/' "$NEG/Cancel.mqh"
grep -qF 'r.cancel_pending_due=limit;' "$NEG/Cancel.mqh" && { echo "  FAIL cancel mutation did not apply"; FAIL=1; } || echo "  PASS a cancel flag derived from the reason count is detected (pin lost)"
cp $HDR "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"
cp $HDR "$NEG/NonAscii.mqh"; printf '// caf\xc3\xa9\n' >> "$NEG/NonAscii.mqh"
n=$(LC_ALL=C grep -c '[^ -~	]' "$NEG/NonAscii.mqh" || true)
[ "$n" != "0" ] && echo "  PASS non-ASCII byte detected" || { echo "  FAIL non-ASCII not detected"; FAIL=1; }

echo
[ $FAIL -eq 0 ] && echo "T012 STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T012 STATIC CHECKS: FAILURES"
exit $FAIL
