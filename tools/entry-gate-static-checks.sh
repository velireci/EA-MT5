#!/bin/bash
# Static checks for the T015 entry gate: one TP_CheckPermit, one PB_CheckLoss, one EN_Place; the T012 result is mandatory (no MANUAL exception); no registration (no TP_Authorize); no state, no file, no clock,
# no real transport; permit only after every check; the executor only after an allowing decision; protected modules untouched. NOT a compiler, NOT an MT5 run.
# Usage: bash tools/entry-gate-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=9950ab7
HD=src/include/EntryGate.mqh
TS=src/tests/EntryGateTest.mq5
FILES="$HD $TS tests/entry_gate_reference.py tests/test_entry_gate.py tools/entry-gate-static-checks.sh"

echo "=== G1: files exist, ASCII only ==="
for f in $FILES; do
  [ -s "$f" ] || { echo "  FAIL $f missing or empty"; FAIL=1; continue; }
  if LC_ALL=C grep -nP '[^\x00-\x7F]' "$f" >/dev/null; then echo "  FAIL $f has non-ASCII characters"; FAIL=1; else echo "  PASS $f exists, ASCII"; fi
done

echo "=== G2: the gate reuses the checks, keeps no state and decides in the right order ==="
cat > "$NEG/g2.py" <<'PYEOF'
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
assert t.count('TP_CheckPermit(') == 1 and t.count('PB_CheckLoss(') == 1 and t.count('EN_Place(') == 1 and t.count('EN_PermitFrom(') == 1, 'call sites'
for w in ('TP_Authorize', 'DG_FinalPreview', 'DG_Evaluate', 'DB_Check(', 'DL_Check(', 'TG_Compute', 'PS_Compute', 'TP_BuildPlan', 'OrderSend', 'OrderCheck', 'FileOpen', 'FileWrite', 'GlobalVariable',
          'TimeCurrent', 'TimeGMT', 'TimeLocal', 'Sleep', 'AccountInfo', 'SymbolInfo', 'store.Write', 'store.Lock', 'store.Read', 'EN_Commit', 'EN_Load', 'M4Step(', 'EntryTransportReal', 'ExitTransportReal'):
    assert w not in t, w
dec = t[t.index('void EG_Decide('):t.index('void EG_Submit(')]
order = ['g.max_age>0', 'spb.plan_ready', 'EN_PlanDigest(spb.plan)', 'EG_Fresh(d,"SNAPSHOT"', 'EG_Fresh(d,"LOSS_CHECK"', 'EG_Fresh(d,"DAILY"', 'PB_CheckLoss(', 'TP_CheckPermit(',
         'DAILY_NOT_EVALUATED', 'DAILY_NOT_CALLED', 'DAILY_BLOCK', 'if(d.reasons!="") return;', 'd.allow=true;', 'EN_PermitFrom(']
for o in order:
    assert o in dec, 'missing step: ' + o
pos = [dec.index(o) for o in order]
assert pos == sorted(pos), pos
assert 'd.loss_check=PB_CheckLoss(' in dec, 'the broker loss result is not used'
assert 'c.daily.dl_called' in dec and 'c.daily.entry_allowed' in dec and 'c.daily_present' in dec
assert 'DAILY_NOT_EVALUATED' in dec and dec.index('if(!c.daily_present) EG_Add') < dec.index('c.daily.entry_allowed')
# the permit exists only when no reason was collected
assert dec.count('EN_PermitFrom(') == 1 and dec.index('if(d.reasons!="") return;') < dec.index('EN_PermitFrom(')
# the permit of T007 is only the INPUT of the executor permit, never forwarded on its own
assert 'tpermit.allow' in dec
assert 'd.permit.valid_until=MathMin(c.snap_time,MathMin(c.loss_time,c.daily_time))+g.max_age' in dec, 'the permit deadline is not the oldest evidence'
assert dec.index('EN_PermitFrom(') < dec.index('d.permit.valid_until=')
sub = t[t.index('void EG_Submit('):]
assert sub.index('EG_Decide(') < sub.index('if(!d.allow)') < sub.index('EN_Place(')
assert 'if(!d.allow) {EN_Res(res,EN_R_REFUSED,"GATE_BLOCKED: "+d.reasons); return;}' in sub, 'executor reached after a block'
# the optional pre-send hook: only after the gate allowed, before the executor, and a refusal places nothing; Settled after the executor
assert 'CEgPreSend *pre_send=NULL' in sub and 'class CEgPreSend' in t, 'hook'
assert sub.index('if(!d.allow)') < sub.index('pre_send.Reserve(') < sub.index('EN_Place(') < sub.index('pre_send.Settled('), 'hook order'
assert 'PRE_SEND_RESERVATION_FAILED' in sub and 'return;' in sub[sub.index('pre_send.Reserve('):sub.index('EN_Place(')], 'a refused reservation must stop before the executor'
assert sub.count('pre_send.Reserve(') == 1 and sub.count('pre_send.Settled(') == 1, 'hook call sites'
assert 'ServerTime()' in sub
inc = re.findall(r'#include "([^"]+)"', t)
assert sorted(inc) == ['BrokerLossCheck.mqh', 'DailyBridge.mqh', 'EntryExecutor.mqh', 'SetupPlanBridge.mqh'], inc
PYEOF
python3 -I "$NEG/g2.py" $HD && echo "  PASS call sites, no registration, no state / file / clock / real transport, check order, T012 mandatory, permit only after every check, executor only after an allowing decision" || { echo "  FAIL"; FAIL=1; }

echo "=== G3: the test never includes a real transport ==="
grep -nE 'EntryTransportReal|ExitTransportReal|OrderSend' $TS >/dev/null && { echo "  FAIL the test touches the real side"; FAIL=1; } || echo "  PASS the test uses the fake transport and the fake store only"

echo "=== G4: protected modules are untouched since $BASE ==="
for p in src/include/EntryTransport.mqh src/include/EntryTransportFake.mqh src/include/TradePlanning.mqh \
         src/include/BrokerLossCheck.mqh src/include/DailyBridge.mqh src/include/DailyLimits.mqh src/include/DailyPreviewGate.mqh src/include/DailyBalanceStore.mqh src/include/M15Confirmation.mqh \
         src/include/ExitExecutor.mqh src/include/ExitTickDriver.mqh src/XauUsdTradePreview.mq5 src/XauUsdT011DemoOpenPosition.mq5; do
  if git cat-file -e $BASE:$p 2>/dev/null; then
    if git diff --quiet $BASE -- $p; then echo "  PASS $p identical to $BASE"; else echo "  FAIL $p differs from $BASE"; FAIL=1; fi
  else echo "  SKIP $p (base not available)"; fi
done

echo "=== G5: negative controls ==="
expect_assert() {   # $1 script, $2 file, $3 message, $4 text the assertion message must contain
  if err=$(python3 -I "$1" "$2" 2>&1 >/dev/null); then echo "  FAIL $3 NOT detected"; FAIL=1;
  elif echo "$err" | grep -q "AssertionError.*$4"; then echo "  PASS $3 is detected";
  else echo "  FAIL $3: the control broke for another reason: $(echo "$err" | tail -1)"; FAIL=1; fi
}
cp $HD "$NEG/A.mqh"; sed -i 's/TP_CheckPermit(guarded,c.snap,c.lim,reg_ids,reg_count,tpermit);/TP_Authorize(guarded,c.snap,c.lim,(string\&)reg_ids,(int\&)reg_count,tpermit);/' "$NEG/A.mqh"
expect_assert "$NEG/g2.py" "$NEG/A.mqh" "a registering permit call (TP_Authorize)" "TP_Authorize\|call sites"
cp $HD "$NEG/B.mqh"; sed -i 's/   if(!c.daily_present) EG_Add(d,"DAILY_NOT_EVALUATED");/   if(!c.daily_present) {}/' "$NEG/B.mqh"
expect_assert "$NEG/g2.py" "$NEG/B.mqh" "the MANUAL exception (daily not evaluated passes)" "missing step: DAILY_NOT_EVALUATED"
cp $HD "$NEG/C.mqh"; sed -i 's/   if(d.reasons!="") return;/   if(false) return;/' "$NEG/C.mqh"
expect_assert "$NEG/g2.py" "$NEG/C.mqh" "a permit built although a reason exists" "missing step: if(d.reasons"
cp $HD "$NEG/D.mqh"; sed -i 's/   if(!d.allow) {EN_Res(res,EN_R_REFUSED,"GATE_BLOCKED: "+d.reasons); return;}/   if(!d.allow) {EN_Res(res,EN_R_REFUSED,"GATE_BLOCKED: "+d.reasons);}/' "$NEG/D.mqh"
expect_assert "$NEG/g2.py" "$NEG/D.mqh" "the executor called after a block" "executor reached after a block"
cp $HD "$NEG/E.mqh"; sed -i 's/   d.loss_check=PB_CheckLoss(/   d.loss_check="OK"; PB_CheckLoss(/' "$NEG/E.mqh"
expect_assert "$NEG/g2.py" "$NEG/E.mqh" "a skipped broker loss result" "broker loss result is not used"
cp $HD "$NEG/F.mqh"; sed -i 's/bool EG_Fresh_unused//; s/   TP_CheckPermit(guarded/   DG_FinalPreview(true,true,false,false); TP_CheckPermit(guarded/' "$NEG/F.mqh"
expect_assert "$NEG/g2.py" "$NEG/F.mqh" "the preview final decision (MANUAL semantics)" "DG_FinalPreview"
cp $HD "$NEG/G.mqh"; sed -i 's/   EN_Place(cfg,tr,store,rt,spb.plan,d.permit,res);/   EN_Place(cfg,tr,store,rt,spb.plan,d.permit,res);\n   store.Write("x","y");/' "$NEG/G.mqh"
expect_assert "$NEG/g2.py" "$NEG/G.mqh" "a write by the gate" "store.Write"

cp $HD "$NEG/H.mqh"; sed -i '/d.permit.valid_until=MathMin/d' "$NEG/H.mqh"
expect_assert "$NEG/g2.py" "$NEG/H.mqh" "a permit without the deadline of the oldest evidence" "permit deadline is not the oldest evidence"
cp $HD "$NEG/I.mqh"; sed -i 's/d.permit.valid_until=MathMin(c.snap_time,MathMin(c.loss_time,c.daily_time))+g.max_age;/d.permit.valid_until=now+g.max_age;/' "$NEG/I.mqh"
expect_assert "$NEG/g2.py" "$NEG/I.mqh" "a deadline counted from the decision time" "permit deadline is not the oldest evidence"

cp $HD "$NEG/J.mqh"; sed -i 's/      if(!pre_send.Reserve(spb.plan.signal_id,why)) {EN_Res(res,EN_R_REFUSED,"PRE_SEND_RESERVATION_FAILED: "+why); return;}/      pre_send.Reserve(spb.plan.signal_id,why);/' "$NEG/J.mqh"
expect_assert "$NEG/g2.py" "$NEG/J.mqh" "a refused reservation that still reaches the executor" "refused reservation must stop"
cp $HD "$NEG/K.mqh"; sed -i 's/   EN_Place(cfg,tr,store,rt,spb.plan,d.permit,res);/   EN_Place(cfg,tr,store,rt,spb.plan,d.permit,res);\n   store.Write("x","y");/; s/   if(pre_send!=NULL) pre_send.Settled(spb.plan.signal_id,res);//' "$NEG/K.mqh"
expect_assert "$NEG/g2.py" "$NEG/K.mqh" "a hook that is never settled" "store.Write\|hook call sites"

[ $FAIL -eq 0 ] && echo "ENTRY GATE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "ENTRY GATE STATIC CHECKS: FAILURES"
exit $FAIL

