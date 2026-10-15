#!/bin/bash
# Static checks for the T011 read-only snapshot adapter. NOT a compiler, NOT an MT5 run: MetaEditor compile and every terminal API call are
# UNVERIFIED. Usage: bash tools/t011-adapter-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=848a456
HDR=src/include/ExitSnapshotAdapter.mqh
TST=src/tests/T011_AdapterTest.mq5
DIAG=src/XauUsdSnapshotDiag.mq5
REF=tests/t011_adapter_reference.py
NEWFILES="$HDR $TST $DIAG $REF tests/t011_adapter_fixtures.py tests/test_t011_adapter.py tools/t011-adapter-static-checks.sh tasks/T011-exit-snapshot-adapter.md"
# WRITE / TRADE vocabulary: never allowed anywhere in the adapter files
WRITE='OrderSend|OrderSendAsync|OrderCheck|OrderClose|OrderModify|OrderDelete|PositionClose|PositionModify|PositionOpen|MqlTradeRequest|MqlTradeResult|MqlTradeCheckResult|CTrade|CPositionInfo|COrderInfo|OnTradeTransaction|OnTrade|OrderCalcMargin|OrderCalcProfit|HistoryDealsDelete|HistoryOrdersDelete|TradeRequest'
# PERSISTENCE: never
PERSIST='File[A-Z][A-Za-z]*|GlobalVariable[A-Za-z]*|WebRequest|Socket[A-Za-z]*|Database[A-Za-z]*|ResourceCreate|SendMail|SendNotification|SendFTP'
# the ONLY terminal reads allowed (all read-only), and only inside XA_ReadRaw / the diagnostic script
READS='PositionsTotal|PositionGetTicket|PositionGetInteger|PositionGetDouble|PositionGetString|OrderSelect|HistorySelectByPosition|HistoryDealsTotal|HistoryDealGetTicket|HistoryDealGetInteger|HistoryDealGetDouble|HistoryOrderSelect|HistoryOrderGetInteger|HistoryOrderGetDouble|OrderGetInteger|SymbolInfoDouble|AccountInfoInteger|GetLastError|ResetLastError'

strip() { python3 -I - "$1" <<'PYEOF'
import re, sys
t = open(sys.argv[1], encoding='ascii').read()
t = re.sub(r'(?s)/\*.*?\*/', '', t)
t = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', t)
t = re.sub(r'//[^\n]*', '', t)
print(t)
PYEOF
}

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no write / trade API, no persistence ==="
for f in $HDR $TST $DIAG; do
  if strip $f | grep -nE "\b($WRITE)\b" >/dev/null; then echo "  FAIL $f: trade or write vocabulary"; FAIL=1; else echo "  PASS $f: no trade or write vocabulary"; fi
  if strip $f | grep -nE "\b($PERSIST)\s*\(" >/dev/null; then echo "  FAIL $f: persistence / network"; FAIL=1; else echo "  PASS $f: no persistence or network"; fi
done

echo "=== S3: terminal reads only in XA_ReadRaw (header) and in the diagnostic script; none in the pure core or the test ==="
core=$(strip $HDR | python3 -I -c "
import re,sys
t=sys.stdin.read()
i=t.index('void XA_ReadRaw(')
j=t.index('bool XA_ReadAndBuild(')
print(t[:i]+t[j:])")
if echo "$core" | grep -nE "\b($READS|SymbolInfo[A-Za-z]*|Account[A-Za-z]*|Position[A-Za-z]*|HistorySelect[A-Za-z]*|HistoryOrder[A-Za-z]*|HistoryDeal[A-Za-z]*|OrdersTotal|OrderGet[A-Za-z]*|TimeCurrent|TimeLocal|TimeGMT)\s*\(" >/dev/null; then echo "  FAIL terminal call outside XA_ReadRaw"; FAIL=1; else echo "  PASS no terminal call outside XA_ReadRaw"; fi
if strip $TST | grep -nE "\b($READS|HistorySelect[A-Za-z]*|OrdersTotal)\s*\(" | grep -v "GetLastError\|ResetLastError" >/dev/null; then echo "  FAIL the test script calls the terminal"; FAIL=1; else echo "  PASS the test script calls no terminal API"; fi
# every terminal call in the reader and the diagnostic must be in the READ whitelist
bad=$( (strip $HDR | python3 -I -c "
import sys
t=sys.stdin.read()
i=t.index('void XA_ReadRaw('); j=t.index('bool XA_ReadAndBuild(')
print(t[i:j])"; strip $DIAG) | grep -oE "\b(Position|Order|History|Symbol|Account|Terminal|MQL|Time|Copy|Chart|Object|Global|File|Event)[A-Za-z0-9_]*\s*\(" | sed 's/\s*($//' | sort -u | grep -vxE "($READS)" | grep -vE "^(PositionsTotal|OrderSelect)$" || true)
if [ -z "$bad" ]; then echo "  PASS every terminal call of the reader and the diagnostic is on the read-only whitelist"; else echo "$bad" | sed 's/^/  FAIL not on the whitelist: /'; FAIL=1; fi

echo "=== S3b: argument counts of the terminal calls (a wrong overload such as AccountInfoInteger(prop, long&) does not exist) ==="
arity() { # arity FILE... : counts the top-level arguments of every whitelisted terminal call
  for f in "$@"; do strip $f; done | python3 -I -c "
import re, sys
text = sys.stdin.read()
# allowed argument counts per call; AccountInfoInteger has ONE form only (it returns the value)
ALLOWED = {'PositionsTotal': (0,), 'PositionGetTicket': (1,), 'PositionGetInteger': (1, 2), 'PositionGetDouble': (1, 2), 'PositionGetString': (1, 2),
           'OrderSelect': (1,), 'HistorySelectByPosition': (1,), 'HistoryDealsTotal': (0,), 'HistoryDealGetTicket': (1,),
           'HistoryDealGetInteger': (2, 3), 'HistoryDealGetDouble': (2, 3), 'HistoryOrderSelect': (1,), 'HistoryOrderGetInteger': (2, 3),
           'HistoryOrderGetDouble': (2, 3), 'OrderGetInteger': (1, 2), 'SymbolInfoDouble': (2, 3), 'AccountInfoInteger': (1,),
           'GetLastError': (0,), 'ResetLastError': (0,)}
bad = 0
for m in re.finditer(r'\b(' + '|'.join(ALLOWED) + r')\s*\(', text):
    depth, i, n, any_arg = 1, m.end(), 0, False
    while i < len(text) and depth:
        c = text[i]
        if c in '([': depth += 1
        elif c in ')]': depth -= 1
        elif c == ',' and depth == 1: n += 1
        elif not c.isspace() and depth == 1: any_arg = True
        i += 1
    args = (n + 1) if (any_arg or n) else 0
    if args not in ALLOWED[m.group(1)]:
        print('%s called with %d argument(s), allowed %s' % (m.group(1), args, ALLOWED[m.group(1)]))
        bad = 1
sys.exit(bad)
"
}
out=$(arity $HDR $DIAG) && echo "  PASS every terminal call in the adapter and the diagnostic has an existing argument count" || { echo "$out" | sed 's/^/  FAIL /'; FAIL=1; }
grep -qF 'AccountInfoInteger(ACCOUNT_MARGIN_MODE);' $HDR && echo "  PASS the margin mode is the RETURNED value of AccountInfoInteger" || { echo "  FAIL margin mode read"; FAIL=1; }

echo "=== S4: identity rules in the header ==="
for pat in 'POSITION_IDENTIFIER' 'DEAL_POSITION_ID' 'DEAL_ORDER' 'DEAL_ENTRY' 'ORDER_POSITION_ID' 'HistorySelectByPosition' 'XA_MARGIN_HEDGING' 'UNSUPPORTED_ACCOUNT_MODE' 'READ_UNSTABLE' 'CAPACITY' 'NO_ORDER_TICKETS' 'XA_RawEqual(' 'PS_GridSteps(' 'raw.vol_step'; do
  grep -qF -- "$pat" $HDR && echo "  PASS header has: $pat" || { echo "  FAIL header lacks: $pat"; FAIL=1; }
done
for bad in 'DEAL_COMMENT' 'DEAL_MAGIC' 'POSITION_COMMENT' 'ORDER_COMMENT' 'ORDER_MAGIC' 'POSITION_MAGIC' 'ES_Split' 'EA_OnQuote' 'EA_OnReport' 'ER_Reconcile('; do
  if strip $HDR | grep -qF -- "$bad"; then echo "  FAIL header uses $bad"; FAIL=1; else echo "  PASS header does not use $bad"; fi
done
if strip $HDR | grep -nE "\bst\.[A-Za-z_]+ *(\+\+|--|[-+]?=[^=])" >/dev/null; then echo "  FAIL the adapter writes the state"; FAIL=1; else echo "  PASS the adapter never writes the state"; fi
[ "$(strip $HDR | grep -c 'complete=(missing==\"\")')" = "1" ] && echo "  PASS executions_complete derives from the proof list only" || { echo "  FAIL completeness derivation"; FAIL=1; }
if strip $HDR | grep -nE "executions_complete *= *true|complete *= *true" >/dev/null; then echo "  FAIL a literal complete = true"; FAIL=1; else echo "  PASS no literal complete = true"; fi

echo "=== S5: balance, format strings, includes, ASCII ==="
python3 tools/t001-check-balance.py $HDR $TST $DIAG || FAIL=1
python3 - $HDR $TST $DIAG <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $HDR $TST $DIAG; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
if grep -nE '\[[0-9A-Za-z_]*\] *= *\{[^}]*\b(nan|inf|[a-z_]+\[)' $TST $DIAG >/dev/null; then echo "  FAIL non-constant array initializer"; FAIL=1; else echo "  PASS array initializers are constants"; fi
for f in $NEWFILES; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every adapter file"

echo "=== S6: the verified modules are identical to $BASE (the tree moves on, so only the protected files are compared) ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in docs/PROJECT_CHECKLIST.md docs/PROJECT_PROGRESS.html src/include/ExitSplit.mqh src/include/ExitActivation.mqh src/include/ExitReconciliation.mqh tests/t011_split_reference.py tests/t011_activation_reference.py tests/t011_reconcile_reference.py src/include/PositionSizing.mqh src/include/TradeGeometry.mqh; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S7: negative controls ==="
mutate() {  # mutate LABEL SRC OLD NEW EXPECTED_PATTERN : the grep pattern must match the mutated, stripped copy
  local label="$1" src="$2" old="$3" new="$4" pat="$5"
  local f="$NEG/$(basename "$src")"
  python3 -I - "$src" "$f" "$old" "$new" <<'PYEOF' || { echo "  FAIL $label: mutation target absent (vacuous control)"; FAIL=1; return; }
import sys
src, dst, old, new = sys.argv[1:5]
t = open(src, encoding='ascii').read()
if old not in t:
    sys.exit(3)
open(dst, 'w', encoding='ascii').write(t.replace(old, new, 1))
PYEOF
  if strip "$f" | grep -qE "$pat"; then echo "  PASS $label (detected)"; else echo "  FAIL $label: not detected"; FAIL=1; fi
}
mutate "an order is sent from the header" $HDR "bool XA_InMap(" "MqlTradeRequest rq; bool XA_InMap(" "\b($WRITE)\b"
mutate "a file is written from the header" $HDR "bool XA_InMap(" 'int h=FileOpen("x",FILE_WRITE); bool XA_InMap(' "\b($PERSIST)\s*\("
mutate "the adapter writes the state" $HDR "bool found=(raw.n_pos==1);" "bool found=(raw.n_pos==1); st.status=EA_ST_DONE;" "\bst\.[A-Za-z_]+ *(\+\+|--|[-+]?=[^=])"
mutate "a literal complete = true" $HDR "bool complete=(missing==\"\");" "bool complete=true;" "complete *= *true"
mutate "a terminal read inside the pure core" $HDR "bool XA_FinalOrderState(" "int zz=PositionsTotal(); bool XA_FinalOrderState(" "PositionsTotal"
mutate "the comment is used as a link" $HDR "bool XA_InMap(" "string zc=\"\"; long q=DEAL_COMMENT; bool XA_InMap(" "DEAL_COMMENT"
# the wrong AccountInfoInteger signature that the first version used must now be caught by the arity check
python3 -I - $HDR "$NEG/WrongSig.mqh" <<'PYEOF' || { echo "  FAIL wrong-signature control: mutation target absent (vacuous)"; FAIL=1; }
import sys
t = open(sys.argv[1], encoding='ascii').read()
old = 'long mm=AccountInfoInteger(ACCOUNT_MARGIN_MODE);'
if old not in t:
    sys.exit(3)
open(sys.argv[2], 'w', encoding='ascii').write(t.replace(old, 'long mm=0; bool okm=AccountInfoInteger(ACCOUNT_MARGIN_MODE,mm);', 1))
PYEOF
if [ -f "$NEG/WrongSig.mqh" ]; then
  if arity "$NEG/WrongSig.mqh" >/dev/null 2>&1; then echo "  FAIL the two-argument AccountInfoInteger was not detected"; FAIL=1; else echo "  PASS the two-argument AccountInfoInteger is detected (the error of fc42cb6)"; fi
fi
# a swallowed-zero control: treating the returned value 0 as a failure
python3 -I - $HDR "$NEG/ZeroFail.mqh" <<'PYEOF' || { echo "  FAIL zero-failure control: mutation target absent (vacuous)"; FAIL=1; }
import sys
t = open(sys.argv[1], encoding='ascii').read()
old = 'ok=(error_code==0);'
if old not in t:
    sys.exit(3)
open(sys.argv[2], 'w', encoding='ascii').write(t.replace(old, 'ok=(error_code==0 && value!=0);', 1))
PYEOF
if [ -f "$NEG/ZeroFail.mqh" ]; then
  if strip "$NEG/ZeroFail.mqh" | grep -qE 'value *!= *0'; then echo "  PASS treating margin mode 0 as a failure is detected"; else echo "  FAIL zero-as-failure not detected"; FAIL=1; fi
fi
if strip $HDR | grep -qE 'value *!= *0|mm *== *0|mm *!= *0'; then echo "  FAIL the header treats a margin mode value of 0 as a failure"; FAIL=1; else echo "  PASS the header never treats a margin mode value of 0 as a failure"; fi
cp $HDR "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"
cp $HDR "$NEG/NonAscii.mqh"; printf '// caf\xc3\xa9\n' >> "$NEG/NonAscii.mqh"
n=$(LC_ALL=C grep -c '[^ -~	]' "$NEG/NonAscii.mqh" || true)
[ "$n" != "0" ] && echo "  PASS non-ASCII byte detected" || { echo "  FAIL non-ASCII not detected"; FAIL=1; }

echo
[ $FAIL -eq 0 ] && echo "T011 ADAPTER STATIC CHECKS: ALL PASS (static only; MetaEditor compile and every terminal API call UNVERIFIED)" || echo "T011 ADAPTER STATIC CHECKS: FAILURES"
exit $FAIL
