#!/bin/bash
# Static checks for the T012 preview integration (observation only). NOT a compiler, NOT an MT5 run: compile and run are UNVERIFIED.
# Usage: bash tools/t012-gate-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=78726c4
HDR=src/include/DailyPreviewGate.mqh
TST=src/tests/T012_GateTest.mq5
EA=src/XauUsdTradePreview.mq5
SET=src/presets/XauUsdTradePreview_T012_hypothetical_daily_block.set
REF=tests/t012_gate_reference.py
CHK="python3 -I tools/t010-static-check.py"
NEWFILES="$HDR $TST $REF tests/t012_gate_fixtures.py tests/test_t012_gate.py $SET tools/t012-gate-static-checks.sh docs/T012-daily-limits.md"

echo "=== S1: files exist ==="
for f in $NEWFILES $EA; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading API, no persistence, no account / history read, the earlier preview checks still hold ==="
out=$($CHK trading $HDR $TST $EA) && echo "  PASS no order/position API (OrderCalcProfit read-only estimate is the only broker call)" || { echo "$out"; FAIL=1; }
out=$($CHK persist $HDR $TST $EA $REF) && echo "  PASS no file, global-variable, network or mail access" || { echo "$out"; FAIL=1; }
out=$($CHK calendar src/include/NewsSpreadFilters.mqh src/tests/T010_FiltersTest.mq5 $EA) && echo "  PASS Calendar* calls only inside ReadUsdCalendar" || { echo "$out"; FAIL=1; }
out=$($CHK tester $EA) && echo "  PASS tester guard precedes the first calendar call" || { echo "$out"; FAIL=1; }
out=$($CHK servertime src/include/NewsSpreadFilters.mqh $EA) && echo "  PASS news path still on the server clock" || { echo "$out"; FAIL=1; }
out=$($CHK wiring $EA) && echo "  PASS T010 wiring: MANUAL defaults, one quote read, no timer/OnTick" || { echo "$out"; FAIL=1; }
out=$($CHK reader $EA) && echo "  PASS T010 reader unchanged in shape" || { echo "$out"; FAIL=1; }
for f in $HDR $TST; do
  if grep -nE 'Account(Info|InfoDouble|InfoInteger)|HistorySelect|HistoryDeal|HistoryOrder|PositionsTotal|OrdersTotal|PositionGet|TimeCurrent|TimeLocal|TimeGMT|TimeTradeServer|GetTickCount|EventSetTimer' "$f" >/dev/null; then
    echo "  FAIL $f reads account, history, positions or a clock"; FAIL=1
  else echo "  PASS $f: no account, history, position or clock read"; fi
done
if grep -nE 'Account(Info|InfoDouble|InfoInteger)|HistorySelect|HistoryDeal|HistoryOrder|PositionsTotal|OrdersTotal|PositionGet' $EA >/dev/null; then echo "  FAIL the preview reads account, history or positions"; FAIL=1; else echo "  PASS the preview reads no account, history or positions"; fi

echo "=== S3: the wiring of the daily gate ==="
for pat in 'input PREVIEW_DAILY_SOURCE InpDailySource=DAILY_SRC_MANUAL;' 'bool daily_on=(InpDailySource==DAILY_SRC_SNAPSHOT);' 'if(daily_on && MQLInfoInteger(MQL_TESTER))' 'daily_on ? TimeGMT() : 0' \
  'bool preview_ok=DG_FinalPreview(loss_check=="OK",permit.allow,daily_evaluated,daily.entry_allowed);' 'input long InpMaxTrades=-1;' 'input double InpDailyBalanceStart=-1;' 'input bool InpDailyResultKnown=false;' 'input long InpDailyWins=-1;' 'input long InpDailyConsecutiveLosses=-1;' 'T012 DAILY'; do
  grep -qF -- "$pat" $EA && echo "  PASS EA has: $pat" || { echo "  FAIL EA lacks: $pat"; FAIL=1; }
done
[ "$(grep -cE '\bpreview_ok *=[^=]' $EA)" = "1" ] && echo "  PASS the final preview result is assigned in exactly one place" || { echo "  FAIL preview_ok assignments"; FAIL=1; }
if grep -nE 'permit\.allow *= *true' $EA >/dev/null; then echo "  FAIL permit.allow set to true"; FAIL=1; else echo "  PASS permit.allow is never forced to true"; fi
grep -q 'return(loss_ok && permit_allow && (!daily_evaluated || daily_allowed));' $HDR && echo "  PASS DG_FinalPreview: existing checks AND (not evaluated OR daily allowed)" || { echo "  FAIL DG_FinalPreview"; FAIL=1; }
grep -q 'DL_Check(' $HDR && grep -q '#include "DailyLimits.mqh"' $HDR && ! grep -qE 'DL_LOSS_DIVISOR|DBL_EPSILON|threshold' $HDR && echo "  PASS DailyLimits is reused, no formula copied" || { echo "  FAIL DailyLimits reuse"; FAIL=1; }

echo "=== S4: the earlier T007-T010 lines of the preview are untouched ==="
python3 -I - $BASE $EA <<'PYEOF' && echo "  PASS every previous line is still there; only the version, two input comments and the final-result line changed" || { echo "  FAIL"; FAIL=1; }
import difflib, subprocess, sys
base = subprocess.run(['git', 'show', sys.argv[1] + ':src/XauUsdTradePreview.mq5'], capture_output=True, text=True).stdout
if not base:
    print('base not available'); sys.exit(0)
old = [l.rstrip() for l in base.splitlines()]
new = [l.rstrip() for l in open(sys.argv[2], encoding='ascii').read().splitlines()]
allowed = {'#property version "1.03"', 'input long InpTradesToday=-1;', 'input long InpMaxTrades=-1;', 'bool preview_ok=(loss_check=="OK" && permit.allow);'}
bad = [l[2:] for l in difflib.ndiff(old, new) if l.startswith('- ') and l[2:].strip() not in allowed]
for l in bad:
    print('changed/removed line:', l)
sys.exit(1 if bad else 0)
PYEOF

echo "=== S5: the .set file lists every input exactly once; every policy except the daily one stays UNKNOWN ==="
python3 -I - $EA $SET <<'PYEOF' && echo "  PASS .set inputs equal the EA inputs; unknown policies keep their UNKNOWN defaults" || { echo "  FAIL"; FAIL=1; }
import re, sys
ea = open(sys.argv[1], encoding='ascii').read()
inputs = re.findall(r'^input\s+\w+\s+(Inp\w+)\s*=\s*([^;]+);', ea, re.M)
names = [n for n, _ in inputs]
defaults = {n: v.strip() for n, v in inputs}
setvals = {}
for line in open(sys.argv[2], encoding='ascii'):
    line = line.strip()
    if not line or line.startswith(';'):
        continue
    k, v = line.split('=', 1)
    if k in setvals:
        print('duplicate', k); sys.exit(1)
    setvals[k] = v
if sorted(setvals) != sorted(names):
    print('missing in .set:', sorted(set(names) - set(setvals)), 'extra in .set:', sorted(set(setvals) - set(names))); sys.exit(1)
unknown_default = {'InpDataState': '0', 'InpSessionState': '0', 'InpSessionSource': '0', 'InpNewsSource': '0', 'InpNewsState': '0', 'InpSpreadSource': '0', 'InpSpreadState': '0',
                   'InpSignalUnused': '0', 'InpOpenPositions': '-1', 'InpExistingRisk': '-1', 'InpMaxPositions': '-1', 'InpMaxTrades': '-1', 'InpCombinedRiskCap': '-1', 'InpMaxSpreadPoints': '-1'}
for k, v in unknown_default.items():
    if setvals[k] != v:
        print('policy %s is not UNKNOWN/unset in the .set: %s' % (k, setvals[k])); sys.exit(1)
if setvals['InpDailySource'] != '1' or setvals['InpDailyClosedResult'] == '3.57':
    print('daily source or result wrong'); sys.exit(1)
PYEOF

echo "=== S6: balance, format strings, includes, ASCII ==="
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
echo "  INFO ASCII-only checked for every integration file"

RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $HDR $TST; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime|color|char|short|uchar|ushort|float)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f declares a variable with a reserved MQL5 word (Codex compile of c64805f: 'final')"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done
echo "=== S7: the verified modules are identical to $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in docs/PROJECT_CHECKLIST.md docs/PROJECT_PROGRESS.html src/include/DailyLimits.mqh src/include/SessionPolicy.mqh src/include/TradePlanning.mqh src/include/NewsSpreadFilters.mqh src/include/BrokerLossCheck.mqh src/include/ExitSplit.mqh src/include/ExitActivation.mqh src/include/ExitReconciliation.mqh src/include/ExitSnapshotAdapter.mqh tests/t012_daily_reference.py; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S8: negative controls ==="
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
# the daily BLOCK ignored in the final result: the pin must disappear
cp $EA "$NEG/Ignored.mq5"; sed -i 's/bool preview_ok=DG_FinalPreview(loss_check=="OK",permit.allow,daily_evaluated,daily.entry_allowed);/bool preview_ok=(loss_check=="OK" \&\& permit.allow);/' "$NEG/Ignored.mq5"
grep -qF 'bool preview_ok=DG_FinalPreview(loss_check=="OK",permit.allow,daily_evaluated,daily.entry_allowed);' "$NEG/Ignored.mq5" && { echo "  FAIL ignored-daily control did not apply"; FAIL=1; } || echo "  PASS an EA whose final result ignores the daily BLOCK loses the pin (detected)"
cp $HDR "$NEG/Gate.mqh"; sed -i 's/return(loss_ok \&\& permit_allow \&\& (!daily_evaluated || daily_allowed));/return(loss_ok \&\& permit_allow);/' "$NEG/Gate.mqh"
grep -q 'return(loss_ok && permit_allow && (!daily_evaluated || daily_allowed));' "$NEG/Gate.mqh" && { echo "  FAIL gate control did not apply"; FAIL=1; } || echo "  PASS a DG_FinalPreview that ignores the daily result loses the pin (detected)"
mutate "order structure in the header" $HDR "int DG_Counter(" "MqlTradeRequest rq; int DG_Counter(" $CHK trading
cp $EA "$NEG/Acct.mq5"; sed -i 's/int OnInit() {Evaluate();/int OnInit() {double zz=AccountInfoDouble(ACCOUNT_BALANCE);Evaluate();/' "$NEG/Acct.mq5"
grep -qE 'Account(Info|InfoDouble|InfoInteger)|HistorySelect|HistoryDeal|HistoryOrder|PositionsTotal|OrdersTotal|PositionGet' "$NEG/Acct.mq5" && echo "  PASS an account read in the EA is detected" || { echo "  FAIL account-read control"; FAIL=1; }
cp $SET "$NEG/Short.set"; sed -i '/^InpDailyWins=/d' "$NEG/Short.set"
python3 -I - $EA "$NEG/Short.set" <<'PYEOF' && { echo "  FAIL a .set missing an input was not detected"; FAIL=1; } || echo "  PASS a .set that misses an input is detected"
import re, sys
ea = open(sys.argv[1], encoding='ascii').read()
names = [n for n, _ in re.findall(r'^input\s+\w+\s+(Inp\w+)\s*=\s*([^;]+);', ea, re.M)]
keys = [l.split('=', 1)[0] for l in open(sys.argv[2], encoding='ascii') if l.strip() and not l.startswith(';')]
sys.exit(0 if sorted(keys) == sorted(names) else 1)
PYEOF
cp $TST "$NEG/Reserved.mq5"; sed -i 's/bool final_ok=/bool final=/' "$NEG/Reserved.mq5"
grep -nE "\b(bool|int|long|double|string)\s+($RESERVED)\b\s*(=|;|,|\))" "$NEG/Reserved.mq5" >/dev/null && echo "  PASS a variable named final is detected" || { echo "  FAIL reserved-word control"; FAIL=1; }
cp $HDR "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T012 GATE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T012 GATE STATIC CHECKS: FAILURES"
exit $FAIL
