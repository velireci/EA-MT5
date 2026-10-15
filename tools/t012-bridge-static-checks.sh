#!/bin/bash
# Static checks for the T012 bridge (history FACTS -> DL_Check). NOT a compiler, NOT an MT5 run: compile and run are UNVERIFIED.
# Usage: bash tools/t012-bridge-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=365a0e9
HDR=src/include/DailyBridge.mqh
TST=src/tests/T012_BridgeTest.mq5
REF=tests/t012_bridge_reference.py
CHK="python3 -I tools/t010-static-check.py"
NEWFILES="$HDR $TST $REF tests/t012_bridge_fixtures.py tests/test_t012_bridge.py tools/t012-bridge-static-checks.sh docs/T012-daily-bridge.md"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: pure module: no trading API, no persistence, no terminal read, no clock ==="
out=$($CHK trading $HDR $TST) && echo "  PASS no order/position API" || { echo "$out"; FAIL=1; }
out=$($CHK persist $HDR $TST $REF) && echo "  PASS no file, global-variable, network or mail access" || { echo "$out"; FAIL=1; }
READ='Account(Info|InfoDouble|InfoInteger)|HistorySelect|HistoryDeal|HistoryOrder|HistoryOrdersTotal|HistoryDealsTotal|PositionsTotal|OrdersTotal|PositionGet|SymbolInfo|TimeCurrent|TimeLocal|TimeGMT|TimeTradeServer|GetTickCount|EventSetTimer|DH_Read'
for f in $HDR $TST; do
  if grep -nE "$READ" "$f" >/dev/null; then echo "  FAIL $f reads the terminal, history or a clock"; FAIL=1; else echo "  PASS $f: no terminal, history or clock read"; fi
done

echo "=== S3: the bridge reuses DL_Check, copies no rule, and picks no policy ==="
grep -q 'DL_Check(' $HDR && ! grep -qE 'DL_LOSS_DIVISOR|DL_WIN_STOP_AT|DL_CONSECUTIVE_LOSS_STOP_AT|DBL_EPSILON|threshold|SP_Evaluate' $HDR && echo "  PASS DL_Check is called; no limit, tolerance or day rule is copied" || { echo "  FAIL DL_Check reuse"; FAIL=1; }
python3 -I - $HDR <<'PYEOF' && echo "  PASS the supported policy ids are exactly the three candidate sums and CALLER_CLASSIFIED; the facts members read are the documented six" || { echo "  FAIL"; FAIL=1; }
import re, sys
t = open(sys.argv[1], encoding='ascii').read()
code = re.sub(r'//[^\n]*', '', t)
ids = sorted(set(re.findall(r'#define DB_(?:FORMULA|CLASSIFICATION)\w*\s+"([A-Z_]+)"', code)))
want_ids = ['CALLER_CLASSIFIED', 'PROFIT', 'PROFIT_COMMISSION_SWAP', 'PROFIT_COMMISSION_SWAP_FEE']
members = sorted(set(re.findall(r'\bfacts\.(\w+)', code)))
want_members = sorted(['day_key', 'complete', 'n_pos', 'candidate_profit', 'candidate_profit_commission_swap', 'candidate_profit_commission_swap_fee'])
if ids != want_ids:
    print('policy ids', ids); sys.exit(1)
if members != want_members:
    print('facts members', members); sys.exit(1)
if re.search(r'result_formula\s*=\s*"|classification\s*=\s*"', code):
    print('a policy value is assigned inside the bridge'); sys.exit(1)
PYEOF
grep -q 'return(false);' $HDR && grep -qE 'if\(r\.n_reasons>0\)' $HDR && echo "  PASS a bridge gap returns before DL_Check" || { echo "  FAIL early return"; FAIL=1; }

echo "=== S4: the header declares its dependencies itself (Codex compile of 3b963d7) ==="
python3 -I - $HDR <<'PYEOF' && echo "  PASS every dependency used by the header is included directly" || { echo "  FAIL"; FAIL=1; }
import re, sys
t = open(sys.argv[1], encoding='ascii').read()
code = re.sub(r'//[^\n]*', '', t)
incs = re.findall(r'#include "([^"]+)"', code)
need = []
if re.search(r'\b(SDhFacts|ENUM_DH_VERDICT|DH_READY|DH_UNKNOWN|DH_BLOCK)\b', code): need.append('DailyHistory.mqh')
if re.search(r'\b(SDlInput|SDlResult|DL_Check)\b', code): need.append('DailyLimits.mqh')
miss = [n for n in need if n not in incs]
if miss:
    print('missing direct include:', miss); sys.exit(1)
PYEOF

echo "=== S5: balance, format strings, includes, ASCII, reserved words ==="
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
echo "  INFO ASCII-only checked for every bridge file"
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $HDR $TST; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime|color|char|short|uchar|ushort|float)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f declares a variable with a reserved MQL5 word"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done
# array initializers must be constants: the generated block holds literals only
python3 -I - $TST <<'PYEOF' && echo "  PASS generated arrays hold literals only" || { echo "  FAIL"; FAIL=1; }
import re, sys
t = open(sys.argv[1], encoding='ascii').read()
blk = t[t.index('// BEGIN GENERATED'):t.index('// END GENERATED')]
for m in re.finditer(r'^(?:string|int|long|double) \w+\[\]=\{(.*)\};$', blk, re.M):
    body = re.sub(r'"[^"]*"', '', m.group(1))
    if re.search(r'[A-Za-z_(]', body.replace('e-', '').replace('e+', '').replace('nan', '')):
        print('non-literal initializer:', m.group(0)[:80]); sys.exit(1)
PYEOF

echo "=== S6: the verified modules are identical to $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/DailyHistory.mqh src/include/DailyLimits.mqh src/include/DailyPreviewGate.mqh src/include/SessionPolicy.mqh src/include/ExitSnapshotAdapter.mqh src/XauUsdDailyHistoryDiag.mq5 tests/t012_daily_reference.py tests/t012_history_reference.py; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S7: negative controls ==="
cp $HDR "$NEG/NoLimits.mqh"; sed -i '/#include "DailyLimits.mqh"/d' "$NEG/NoLimits.mqh"
python3 -I - "$NEG/NoLimits.mqh" <<'PYEOF' && { echo "  FAIL a missing DailyLimits include was not detected"; FAIL=1; } || echo "  PASS a header without the DailyLimits include is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
sys.exit(0 if ('DailyLimits.mqh' in re.findall(r'#include "([^"]+)"', code)) else 1)
PYEOF
cp $HDR "$NEG/Terminal.mqh"; sed -i 's/^void DB_Add(/double zz=AccountInfoDouble(ACCOUNT_BALANCE);\nvoid DB_Add(/' "$NEG/Terminal.mqh"
grep -qE "$READ" "$NEG/Terminal.mqh" && echo "  PASS a terminal read in the bridge is detected" || { echo "  FAIL terminal-read control"; FAIL=1; }
cp $HDR "$NEG/Order.mqh"; sed -i 's/^void DB_Add(/MqlTradeRequest rq;\nvoid DB_Add(/' "$NEG/Order.mqh"
$CHK trading "$NEG/Order.mqh" >/dev/null 2>&1 && { echo "  FAIL trading-API control"; FAIL=1; } || echo "  PASS an order structure in the bridge is detected"
cp $HDR "$NEG/Copied.mqh"; sed -i 's/^void DB_Add(/double th=DL_LOSS_DIVISOR;\nvoid DB_Add(/' "$NEG/Copied.mqh"
grep -qE 'DL_LOSS_DIVISOR' "$NEG/Copied.mqh" && echo "  PASS a copied limit constant is detected" || { echo "  FAIL copied-rule control"; FAIL=1; }
cp $HDR "$NEG/Default.mqh"; sed -i 's/^void DB_Add(/#define DB_FORMULA_DEFAULT "AUTO"\nvoid DB_Add(/' "$NEG/Default.mqh"
python3 -I - "$NEG/Default.mqh" <<'PYEOF' && { echo "  FAIL an extra policy id was not detected"; FAIL=1; } || echo "  PASS an extra (guessed) policy id is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
ids = sorted(set(re.findall(r'#define DB_(?:FORMULA|CLASSIFICATION)\w*\s+"([A-Z_]+)"', code)))
sys.exit(0 if ids == ['CALLER_CLASSIFIED', 'PROFIT', 'PROFIT_COMMISSION_SWAP', 'PROFIT_COMMISSION_SWAP_FEE'] else 1)
PYEOF
cp $TST "$NEG/Reserved.mq5"; sed -i 's/bool allowed=/bool final=/' "$NEG/Reserved.mq5"
grep -nE "\b(bool|int|long|double|string)\s+($RESERVED)\b\s*(=|;|,|\))" "$NEG/Reserved.mq5" >/dev/null && echo "  PASS a variable named final is detected" || { echo "  FAIL reserved-word control"; FAIL=1; }
cp $HDR "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T012 BRIDGE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "T012 BRIDGE STATIC CHECKS: FAILURES"
exit $FAIL
