#!/bin/bash
# Static checks for the T013 entry executor: ONE send call and ONE cancel call in the whole code base of the module, both inside the fake/real seam implementations and the executor in the right places, reconcile
# without any send / cancel, step order, no T011 executor / demo module, no TradePlanning logic, no strategy token, protected modules untouched. NOT a compiler, NOT an MT5 run.
# Usage: bash tools/entry-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=6026989
EX=src/include/EntryExecutor.mqh
TR=src/include/EntryTransport.mqh
FK=src/include/EntryTransportFake.mqh
RL=src/include/EntryTransportReal.mqh
TS=src/tests/EntryExecutorTest.mq5
PR=src/tests/EntryExecutorRealCompile.mq5
FILES="$EX $TR $FK $RL $TS $PR tests/entry_reference.py tests/test_entry_executor.py tools/entry-static-checks.sh"

echo "=== E1: files exist, ASCII only ==="
for f in $FILES; do
  [ -s "$f" ] || { echo "  FAIL $f missing or empty"; FAIL=1; continue; }
  if LC_ALL=C grep -nP '[^\x00-\x7F]' "$f" >/dev/null; then echo "  FAIL $f has non-ASCII characters"; FAIL=1; else echo "  PASS $f exists, ASCII"; fi
done

echo "=== E2: the trading API appears ONLY in the real transport; tests never include it ==="
cat > "$NEG/e2.py" <<'PYEOF'
import re, sys
bad = []
for f in sys.argv[1:]:
    t = re.sub(r'//[^\n]*', '', open(f, encoding='ascii').read())
    if re.search(r'OrderSend|OrderCheck|CTrade|PositionClose|PositionOpen|PositionModify|TRADE_ACTION', t):
        bad.append(f)
assert not bad, bad
PYEOF
python3 -I "$NEG/e2.py" $EX $TR $FK $TS && echo "  PASS no trading call in the executor, the seam, the fake or the test" || { echo "  FAIL a trading call outside the real transport"; FAIL=1; }
if grep -nE 'EntryTransportReal|ExitTransportReal' $EX $FK $TS >/dev/null; then echo "  FAIL the executor, the fake or the test includes a real transport"; FAIL=1; else echo "  PASS no real transport is included by the executor, the fake or the test"; fi
if [ "$(grep -c 'OrderSend(' $RL)" -ne 2 ]; then echo "  FAIL the real transport must hold exactly two OrderSend calls (place, cancel)"; FAIL=1; else echo "  PASS exactly two OrderSend calls (place, cancel) in the real transport"; fi
grep -nE 'ExitExecutor|ExitTickDriver|DemoOpen|DemoHarness|ExitTransport\.mqh|ExitTransportFake|XauUsdT011' $EX $TR $FK $RL $TS $PR >/dev/null && { echo "  FAIL a T011 executor / demo module is used"; FAIL=1; } || echo "  PASS no T011 executor, driver or demo module is used (only the codec primitives and the instance lock)"

echo "=== E3: call sites and order inside the executor ==="
cat > "$NEG/e3.py" <<'PYEOF'
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
assert t.count('tr.Send(') == 1 and t.count('tr.Cancel(') == 1, 'send / cancel call sites'
def body(name, nxt):
    i = t.index(name); j = t.index(nxt, i); return t[i:j]
place = body('void EN_PlaceLocked(', 'void EN_Place(')
assert place.count('tr.Send(') == 1
order = ['EN_Load(store,name,ex,why)', 'EN_MarketRefusal(', 'tr.ListOrders(', 'store.Write(name,text)', 'store.Read(name,back)', 'tr.PreCheck(req)', 'rt.send_calls++', 'tr.Send(req,sr)', 'tr.ReadOrder(sr.order,o)']
pos = [place.index(o) for o in order]
assert pos == sorted(pos), pos
pub = body('void EN_Place(', 'void EN_ScanForOrder(')
order2 = ['EN_ConfigUnset(cfg)', 'rt.latched', 'rt.send_calls>=1', 'EN_PlanRefusal(plan)', 'tr.ServerTime()', 'EN_PermitRefusal(', 'tr.ReadAccount(acct)', 'EN_RealGate(', 'store.Lock(key)', 'EN_PlaceLocked(', 'store.Unlock(key)']
pos = [pub.index(o) for o in order2]
assert pos == sorted(pos), pos
rec = body('void EN_ScanForOrder(', 'void EN_CancelLocked(')
assert 'Send(' not in rec and 'Cancel(' not in rec and 'send_calls' not in rec and 'cancel_calls' not in rec, 'reconcile must neither send nor cancel'
assert 'EN_PermitRefusal(' in place and 'EN_MarketRefusal(' in place, 'no re-check inside the locked placement'
assert place.rindex('EN_PermitRefusal(') > place.index('tr.PreCheck(req)') and place.rindex('EN_PermitRefusal(') < place.index('tr.Send(req,sr)'), 'permit not re-checked right before the send'
assert place.rindex('EN_MarketRefusal(') > place.index('tr.PreCheck(req)') and place.rindex('EN_MarketRefusal(') < place.index('tr.Send(req,sr)'), 'quote not re-checked right before the send'
recon = body('string EN_DiskState(', 'void EN_Reconcile(')
assert recon.count('EN_Commit(') == 1, 'every state save in recovery must go through EN_Transition (checked result)'
assert recon.index('EN_Commit(') < recon.index('void EN_ScanForOrder(')
canc = body('void EN_CancelLocked(', 'void EN_Cancel(')
assert 'rec.cancel_attempts>=1' in canc and canc.index('rec.cancel_attempts>=1') < canc.index('tr.Cancel(ticket,cr)'), 'the stored cancel attempt is not checked'
assert 'EN_FILL_RETURN' in t[t.index('string EN_ConfigUnset('):t.index('string EN_PlanRefusal(')], 'filling rule'

order3 = ['EN_Load(', 'tr.ReadOrder(rec.order_ticket,o)', 'EN_Commit(store,rec,nx)', 'rt.cancel_calls++', 'tr.Cancel(ticket,cr)']
pos = [canc.index(o) for o in order3]
assert pos == sorted(pos), pos
cpub = t[t.index('void EN_Cancel('):]
assert cpub.index('decision.cancel_pending') < cpub.index('store.Lock(key)') < cpub.index('EN_CancelLocked(') < cpub.index('store.Unlock(key)')
for lockfn in ('EN_Place(', 'EN_Reconcile(', 'EN_Cancel('):
    seg = t[t.index('void ' + lockfn):]
    seg = seg[:seg.index('\n  }\n') + 5]
    assert seg.count('store.Lock(') == 1 and seg.count('store.Unlock(') == 1, lockfn
for w in ('FileDelete', 'FileMove', 'GlobalVariable', 'TimeCurrent', 'TimeGMT', 'TimeLocal', 'Sleep', 'AccountInfo', 'HistorySelect', 'PositionGet'):
    assert w not in t, w
PYEOF
python3 -I "$NEG/e3.py" $EX && echo "  PASS one send, one cancel, the step order, lock around every action, reconcile sends and cancels nothing" || { echo "  FAIL"; FAIL=1; }

echo "=== E4: no TradePlanning logic, no strategy choice, no T011 record function ==="
cat > "$NEG/e4.py" <<'PYEOF'
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
for w in ('TP_BuildPlan', 'TP_CheckPermit', 'TP_Authorize', 'TG_Compute', 'PS_Compute', 'H4', 'FVG', 'M15', 'RETURN_OBSERVED', 'DH_', 'DB_Check', 'DL_Check', 'EX_', 'ETD_', 'ESF_Save', 'ESC_Encode', 'ESC_Decode'):
    assert w not in t, w
used = set(re.findall(r'\b(ESC_\w+)\s*\(', t))
assert used <= {'ESC_Crc32', 'ESC_Escape', 'ESC_Unescape', 'ESC_Fnum', 'ESC_ParseInt', 'ESC_ParseDouble', 'ESC_Lines', 'ESC_Field'}, used
assert 'TP_OK' in t and 'TP_STAGE_COMPLETE' in t and 'TP_CANCEL_REQUEST' in t
PYEOF
python3 -I "$NEG/e4.py" $EX && echo "  PASS only types / statuses of TradePlanning, only the listed codec primitives" || { echo "  FAIL"; FAIL=1; }

echo "=== E5: no reserved MQL5 word as an identifier ==="
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $EX $TR $FK $RL $TS; do
  if grep -nE "\b[A-Za-z_][A-Za-z0-9_]*\s+($RESERVED)\s*[;,)=]" "$f" | grep -vE '^[0-9]+:\s*(//|return|else)' >/dev/null || grep -nE "\.($RESERVED)\b" "$f" >/dev/null; then echo "  FAIL $f uses a reserved MQL5 word as a name"; FAIL=1; else echo "  PASS $f: no reserved word as a name"; fi
done

echo "=== E6: protected modules are untouched since $BASE ==="
for p in src/include/TradePlanning.mqh src/include/TradeGeometry.mqh src/include/PositionSizing.mqh src/include/ExitStateCodec.mqh src/include/ExitStateFile.mqh src/include/ExitInstanceLock.mqh \
         src/include/ExitExecutor.mqh src/include/ExitTickDriver.mqh src/include/ExitTransport.mqh src/include/ExitTransportFake.mqh src/include/ExitTransportReal.mqh src/include/DailyBalanceStore.mqh \
         src/include/DailyBridge.mqh src/include/DailyLimits.mqh src/include/DailyHistory.mqh src/XauUsdTradePreview.mq5 src/XauUsdT011DemoOpenPosition.mq5; do
  if git cat-file -e $BASE:$p 2>/dev/null; then
    if git diff --quiet $BASE -- $p; then echo "  PASS $p identical to $BASE"; else echo "  FAIL $p differs from $BASE"; FAIL=1; fi
  else echo "  SKIP $p (base not available)"; fi
done

expect_assert() {   # $1 script, $2 file, $3 message
  if err=$(python3 -I "$1" "$2" 2>&1 >/dev/null); then echo "  FAIL $3 NOT detected"; FAIL=1;
  elif echo "$err" | grep -q AssertionError; then echo "  PASS $3 is detected";
  else echo "  FAIL $3: the control broke for another reason: $(echo "$err" | tail -1)"; FAIL=1; fi
}
echo "=== E7: negative controls ==="
cp $EX "$NEG/A.mqh"; sed -i 's/   tr.Send(req,sr);/   tr.Send(req,sr);\n   tr.Send(req,sr);/' "$NEG/A.mqh"
expect_assert "$NEG/e3.py" "$NEG/A.mqh" "a second send"
cp $EX "$NEG/B.mqh"; sed -i 's/   tr.ListOrders(rec.symbol,rec.t_intent-EN_TIME_TOL,lst);/   SEnSendResult zz; SEnRequest qq; tr.Send(qq,zz);\n   tr.ListOrders(rec.symbol,rec.t_intent-EN_TIME_TOL,lst);/' "$NEG/B.mqh"
expect_assert "$NEG/e3.py" "$NEG/B.mqh" "a send inside reconcile"
cp $EX "$NEG/C.mqh"; python3 - "$NEG/C.mqh" <<'PYEOF'
import sys
t = open(sys.argv[1]).read()
a = '   if(!store.Write(name,text)) {EN_Res(res,EN_R_BLOCKED,"INTENT_NOT_SAVED: zero sends"); return;}'
assert a in t
t = t.replace(a, '')
t = t.replace('   SEnRequest req;\n   req.type=EN_OType(plan.direction);', a + '\n   SEnRequest req;\n   req.type=EN_OType(plan.direction);', 1)
open(sys.argv[1], 'w').write(t)
PYEOF
expect_assert "$NEG/e3.py" "$NEG/C.mqh" "an intent that is not saved before the pre-check and the send"
cp $EX "$NEG/H.mqh"; sed -i 's/   EN_Transition(store,rec,nx,EN_R_PLACED,"RECOVERED_ACTIVE",tk,0,res);/   EN_Commit(store,rec,nx);/' "$NEG/H.mqh"
expect_assert "$NEG/e3.py" "$NEG/H.mqh" "an unchecked state save in recovery"
cp $EX "$NEG/J.mqh"; python3 - "$NEG/J.mqh" <<'PYEOF'
import sys
t = open(sys.argv[1]).read()
a = '   if(bad=="") bad=EN_PermitRefusal(cfg,plan,permit,now2);\n'
assert a in t
open(sys.argv[1], 'w').write(t.replace(a, ''))
PYEOF
expect_assert "$NEG/e3.py" "$NEG/J.mqh" "a missing permit re-check right before the send"
cp $EX "$NEG/D.mqh"; sed -i 's/TP_CANCEL_REQUEST/TP_CANCEL_NO_EVENT/' "$NEG/D.mqh"
expect_assert "$NEG/e4.py" "$NEG/D.mqh" "a changed cancel decision status pin"
cp $EX "$NEG/E.mqh"; sed -i 's/ESC_Fnum(r.e,e);/ESC_Fnum(r.e,e); TP_BuildPlan("a","b",1,1.0,1.0,false,0.0,1.0,1.0,0.01,2,0.01,0,false,1.0,1.0,0.01,0.01,1.0,1.0,*(STpPlan*)0);/' "$NEG/E.mqh"
expect_assert "$NEG/e4.py" "$NEG/E.mqh" "a call into the TradePlanning logic"
cp $EX "$NEG/G.mqh"; sed -i 's/ENUM_EN_RESULT outcome;/ENUM_EN_RESULT final;/' "$NEG/G.mqh"
if grep -nE "\b[A-Za-z_][A-Za-z0-9_]*\s+($RESERVED)\s*[;,)=]" "$NEG/G.mqh" >/dev/null; then echo "  PASS a reserved word used as a member name is detected"; else echo "  FAIL a reserved member name not detected"; FAIL=1; fi
cp $FK "$NEG/F.mqh"; sed -i 's/      sends++;/      sends++; OrderSend(0,0);/' "$NEG/F.mqh"
if grep -nE 'OrderSend|OrderCheck|CTrade|PositionClose|PositionOpen|PositionModify|TRADE_ACTION' "$NEG/F.mqh" >/dev/null; then echo "  PASS a trading call in the fake is detected by the E2 pattern"; else echo "  FAIL"; FAIL=1; fi

[ $FAIL -eq 0 ] && echo "ENTRY EXECUTOR STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "ENTRY EXECUTOR STATIC CHECKS: FAILURES"
exit $FAIL
