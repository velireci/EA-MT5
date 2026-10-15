#!/bin/bash
# Static checks for the T012 read-only daily-history facts. NOT a compiler, NOT an MT5 run: compile and every terminal API call are UNVERIFIED.
# Usage: bash tools/t012-history-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=01877b5
HDR=src/include/DailyHistory.mqh
TST=src/tests/T012_HistoryTest.mq5
DIAG=src/XauUsdDailyHistoryDiag.mq5
REF=tests/t012_history_reference.py
NEWFILES="$HDR $TST $DIAG $REF tests/t012_history_fixtures.py tests/test_t012_history.py tools/t012-history-static-checks.sh docs/T012-daily-history.md"
WRITE='OrderSend|OrderSendAsync|OrderCheck|OrderClose|OrderModify|OrderDelete|PositionClose|PositionModify|PositionOpen|MqlTradeRequest|MqlTradeResult|MqlTradeCheckResult|CTrade|CPositionInfo|COrderInfo|OnTradeTransaction|OnTrade|OrderCalcMargin|OrderCalcProfit|HistoryDealsDelete|HistoryOrdersDelete|TradeRequest'
PERSIST='File[A-Z][A-Za-z]*|GlobalVariable[A-Za-z]*|WebRequest|Socket[A-Za-z]*|Database[A-Za-z]*|ResourceCreate|SendMail|SendNotification|SendFTP'
READS='PositionsTotal|PositionGetTicket|PositionGetInteger|HistorySelect|HistorySelectByPosition|HistoryDealsTotal|HistoryDealGetTicket|HistoryDealGetInteger|HistoryDealGetDouble|SymbolInfoDouble|AccountInfoInteger|GetLastError|ResetLastError|TimeGMT|TimeTradeServer'
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'

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

echo "=== S3: terminal reads only in DH_ReadRaw (header) and the diagnostic; none in the pure core or the test; no account balance ==="
core=$(strip $HDR | python3 -I -c "
import sys
t=sys.stdin.read()
i=t.index('void DH_ReadRaw(')
j=t.index('ENUM_DH_VERDICT DH_ReadAndBuild(')
print(t[:i]+t[j:])")
if echo "$core" | grep -nE "\b($READS|SymbolInfo[A-Za-z]*|Account[A-Za-z]*|Position[A-Za-z]*|HistorySelect[A-Za-z]*|HistoryOrder[A-Za-z]*|HistoryDeal[A-Za-z]*|OrdersTotal|OrderGet[A-Za-z]*|TimeCurrent|TimeLocal)\s*\(" | grep -v "PS_GridSteps\|DH_\|XA_" >/dev/null; then echo "  FAIL terminal call outside DH_ReadRaw"; FAIL=1; else echo "  PASS no terminal call outside DH_ReadRaw"; fi
if strip $TST | grep -nE "\b($READS|HistorySelect[A-Za-z]*|OrdersTotal)\s*\(" | grep -v "GetLastError\|ResetLastError" >/dev/null; then echo "  FAIL the test script calls the terminal"; FAIL=1; else echo "  PASS the test script calls no terminal API"; fi
bad=$( (strip $HDR | python3 -I -c "
import sys
t=sys.stdin.read()
i=t.index('void DH_ReadRaw('); j=t.index('ENUM_DH_VERDICT DH_ReadAndBuild(')
print(t[i:j])"; strip $DIAG) | grep -oE "\b(Position|Order|History|Symbol|Account|Terminal|MQL|Time|Copy|Chart|Object|Global|File|Event)[A-Za-z0-9_]*\s*\(" | sed 's/\s*($//' | sort -u | grep -vxE "($READS|TimeToString)" || true)
if [ -z "$bad" ]; then echo "  PASS every terminal call of the reader and the diagnostic is on the read-only whitelist"; else echo "$bad" | sed 's/^/  FAIL not on the whitelist: /'; FAIL=1; fi
for f in $HDR $DIAG; do
  if strip $f | grep -nE "ACCOUNT_BALANCE|ACCOUNT_EQUITY|AccountInfoDouble" >/dev/null; then echo "  FAIL $f reads the account balance or equity (the balance at the start of the day is never reconstructed)"; FAIL=1; else echo "  PASS $f: no account balance or equity"; fi
done
arity() {
  for f in "$@"; do strip $f; done | python3 -I -c "
import re, sys
text = sys.stdin.read()
ALLOWED = {'PositionsTotal': (0,), 'PositionGetTicket': (1,), 'PositionGetInteger': (1, 2), 'HistorySelect': (2,), 'HistorySelectByPosition': (1,), 'HistoryDealsTotal': (0,),
           'HistoryDealGetTicket': (1,), 'HistoryDealGetInteger': (2, 3), 'HistoryDealGetDouble': (2, 3), 'SymbolInfoDouble': (2, 3), 'AccountInfoInteger': (1,),
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
out=$(arity $HDR $DIAG) && echo "  PASS every terminal call has an existing argument count" || { echo "$out" | sed 's/^/  FAIL /'; FAIL=1; }

echo "=== S4: facts only - no policy in the header ==="
for bad in 'wins_today' 'consecutive_losses' 'trades_today' 'DL_Check' 'DL_WIN_STOP_AT' 'breakeven' 'is_win' 'is_loss' 'win_count' 'loss_count' 'trade_count' 'closed_result'; do
  if strip $HDR | grep -qwF -- "$bad"; then echo "  FAIL header contains $bad (a policy, not a fact)"; FAIL=1; else echo "  PASS header does not contain $bad"; fi
done
for pat in 'f.result_formula="UNSET";' 'f.balance_start_known=false;' 'f.complete=cfg.history_complete_asserted;' 'SP_Evaluate(' 'PS_GridSteps(' 'raw.deals_truncated || raw.pos_truncated' 'READ_UNSTABLE' 'UNSUPPORTED_ACCOUNT_MODE' 'OWNERSHIP_UNPROVABLE' 'cfg.ea_magic<=0' 'raw.pos[pi].opened_magic!=cfg.ea_magic' 'DH_DayWindow(' 'f.duplicates++' 'f.outside_window++' 'f.nontrade_count++'; do
  grep -qF -- "$pat" $HDR && echo "  PASS header has: $pat" || { echo "  FAIL header lacks: $pat"; FAIL=1; }
done
for bad in 'DEAL_COMMENT' 'POSITION_COMMENT' 'ORDER_COMMENT'; do
  if strip $HDR | grep -qF -- "$bad"; then echo "  FAIL header uses $bad"; FAIL=1; else echo "  PASS header does not use $bad"; fi
done
[ "$(strip $HDR | grep -c 'f.complete=')" = "2" ] && echo "  PASS complete is initialised to false and set only from the owner's assertion" || { echo "  FAIL complete assignments"; FAIL=1; }
if strip $HDR | grep -nE "f\.complete *= *true" >/dev/null; then echo "  FAIL a literal complete = true"; FAIL=1; else echo "  PASS no literal complete = true"; fi
for f in $HDR $TST; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime|color|char|short|uchar|ushort|float)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f declares a variable with a reserved MQL5 word"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done

echo "=== S4b: the header declares the T009 dependency itself (Codex compile of 3b963d7: SSessionPolicy / SP_Evaluate undeclared) ==="
if strip $HDR | grep -qE '\b(SSessionPolicy|SP_Evaluate)\b'; then
  grep -qF '#include "SessionPolicy.mqh"' $HDR && echo "  PASS the header uses T009 and includes SessionPolicy.mqh directly" || { echo "  FAIL the header uses T009 but does not include SessionPolicy.mqh"; FAIL=1; }
else echo "  FAIL the header no longer uses T009 (the day window must come from T009)"; FAIL=1; fi
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
if grep -nE '%-[0-9]+s|%[0-9]+s' $DIAG $HDR >/dev/null; then echo "  FAIL width flags in a format string (not verified in MQL5)"; FAIL=1; else echo "  PASS no width flags in format strings"; fi
for f in $NEWFILES; do
  n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true)
  [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }
done
echo "  INFO ASCII-only checked for every history file"

echo "=== S6: the verified modules are identical to $BASE ==="
if git cat-file -e "$BASE^{commit}" 2>/dev/null; then
  for p in src/include/DailyLimits.mqh src/include/DailyPreviewGate.mqh src/include/SessionPolicy.mqh src/include/TradePlanning.mqh src/include/ExitSnapshotAdapter.mqh src/include/ExitReconciliation.mqh src/include/ExitActivation.mqh tests/t009_session_reference.py tests/t012_daily_reference.py; do
    git diff --quiet "$BASE" -- "$p" && echo "  PASS $p identical to $BASE" || { echo "  FAIL $p differs from $BASE"; FAIL=1; }
  done
else
  echo "  SKIP base commit $BASE not available in this clone (UNVERIFIED)"
fi

echo "=== S7: negative controls ==="
ctl() { # ctl LABEL FILE OLD NEW REGEX : the mutated, stripped copy must MATCH the regex (i.e. the check would fail)
  local label="$1" src="$2" old="$3" new="$4" pat="$5" f="$NEG/ctl_$(basename "$2")"
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
ctl "an order is sent from the header" $HDR "bool DH_Fin(" "MqlTradeRequest rq; bool DH_Fin(" "\b($WRITE)\b"
ctl "a file is written from the header" $HDR "bool DH_Fin(" 'int h=FileOpen("x",FILE_WRITE); bool DH_Fin(' "\b($PERSIST)\s*\("
ctl "the account balance is read for the start of the day" $HDR "bool DH_Fin(" "double zz=AccountInfoDouble(ACCOUNT_BALANCE); bool DH_Fin(" "ACCOUNT_BALANCE|AccountInfoDouble"
ctl "a win counter appears" $HDR "bool DH_Fin(" "int wins_today=0; bool DH_Fin(" "wins_today"
ctl "a literal complete = true" $HDR "f.complete=cfg.history_complete_asserted;" "f.complete=true;" "f\.complete *= *true"
cp $HDR "$NEG/Sel.mqh"; sed -i 's/f.result_formula="UNSET";/f.result_formula="PROFIT_ONLY";/' "$NEG/Sel.mqh"
grep -qF 'f.result_formula="UNSET";' "$NEG/Sel.mqh" && { echo "  FAIL formula control did not apply"; FAIL=1; } || echo "  PASS a selected result formula loses the UNSET pin (detected)"
cp $HDR "$NEG/Wrong.mqh"; sed -i 's/SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP,step)/SymbolInfoDouble(symbol)/' "$NEG/Wrong.mqh"
grep -qF 'SymbolInfoDouble(symbol)' "$NEG/Wrong.mqh" || { echo "  FAIL arity control did not apply"; FAIL=1; }
if arity "$NEG/Wrong.mqh" >/dev/null 2>&1; then echo "  FAIL the two-argument AccountInfoInteger was not detected"; FAIL=1; else echo "  PASS a wrong-arity terminal call is detected"; fi
cp $HDR "$NEG/NoSp.mqh"; sed -i '/#include "SessionPolicy.mqh"/d' "$NEG/NoSp.mqh"
if strip "$NEG/NoSp.mqh" | grep -qE '\b(SSessionPolicy|SP_Evaluate)\b' && ! grep -qF '#include "SessionPolicy.mqh"' "$NEG/NoSp.mqh"; then echo "  PASS a header that uses T009 without including it is detected"; else echo "  FAIL missing-include control"; FAIL=1; fi
cp $HDR "$NEG/Unbalanced.mqh"; echo "void x(){" >> "$NEG/Unbalanced.mqh"
python3 tools/t001-check-balance.py "$NEG/Unbalanced.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace not detected"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T012 HISTORY STATIC CHECKS: ALL PASS (static only; MetaEditor compile and every terminal API call UNVERIFIED)" || echo "T012 HISTORY STATIC CHECKS: FAILURES"
exit $FAIL
