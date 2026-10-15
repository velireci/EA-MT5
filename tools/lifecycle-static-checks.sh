#!/bin/bash
# Static checks for T019 (entry lifecycle): the layer only reconciles with the existing executor (never a send), cancels only through TP_CancelDecision + EN_Cancel for an event that is due AND enabled, never
# overwrites a damaged state file, persists the halt; the EA keeps every cancel event off by default, wires the layer without an order call or a T011 registration; protected modules are untouched. NOT a compiler.
# Usage: bash tools/lifecycle-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=21f7ade
HD=src/include/EntryLifecycle.mqh
EA=src/XauUsdEntryOrchestrator.mq5
TS=src/tests/EntryLifecycleTest.mq5
FILES="$HD $EA $TS tests/lifecycle_reference.py tests/test_lifecycle.py tools/lifecycle-static-checks.sh"

echo "=== L1: files exist, ASCII only ==="
for f in $FILES; do
  [ -s "$f" ] || { echo "  FAIL $f missing or empty"; FAIL=1; continue; }
  if LC_ALL=C grep -nP '[^\x00-\x7F]' "$f" >/dev/null; then echo "  FAIL $f has non-ASCII characters"; FAIL=1; else echo "  PASS $f exists, ASCII"; fi
done

echo "=== L2: the layer reuses the executor, never sends, cancels only for a due AND enabled event ==="
cat > "$NEG/l2.py" <<'PYEOF'
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
for w in ('OrderSend', 'OrderCheck', 'EN_Place(', 'EN_PlaceLocked', '.Send(', 'tr.Cancel(', 'PositionClose', 'FileOpen', 'FileWrite', 'FileDelete', 'GlobalVariable', 'TimeCurrent', 'TimeGMT', 'TimeLocal', 'Sleep',
          'AccountInfo', 'SymbolInfo', 'ETD_', 'EX_Register', 'ExitStateFile', 'ExitExecutor', 'EntryTransportReal', 'TP_Authorize', 'store.Lock'):
    assert w not in t, w
assert sorted(re.findall(r'#include "([^"]+)"', t)) == ['EntryExecutor.mqh'], 'includes'
assert t.count('EN_Reconcile(') == 2 and t.count('EN_Cancel(') == 1 and t.count('TP_CancelDecision(') == 1, 'call sites'
sweep = t[t.index('void LC_Sweep('):t.index('bool LC_Startup(')]
assert 'EN_Reconcile(' in sweep and 'EN_Cancel(' not in sweep, 'the sweep only reconciles'
tick = t[t.index('void LC_Tick('):]
assert 'int events=(due & enabled);' in tick, 'cancel events must be due AND enabled'
assert tick.index('LC_Sweep(') < tick.index('if(events!=0)') < tick.index('TP_CancelDecision(') < tick.index('EN_Cancel('), 'order'
assert 'dec.status!=TP_CANCEL_REQUEST) continue;' in tick, 'cancel without a request'
assert 'EN_RuntimeInit(rt)' in tick and tick.index('EN_RuntimeInit(rt)') < tick.index('EN_Cancel('), 'fresh runtime per cancel'
assert 'TP_CancelDecision(true,open_ids[i],false,events,dec)' in tick, 'cancel decision inputs'
assert 'CANCEL_NOT_CONFIRMED' in tick and 'r.outcome==EN_R_CANCELLED' in tick, 'an unconfirmed cancel halts'
start = t[t.index('bool LC_Startup('):t.index('int LC_DueEvents(')]
assert 'if(kind==LC_DAMAGED) {LC_Note(notes,s.halted); return(true);}' in start, 'a damaged file returns before anything is written'
assert start.index('if(kind==LC_DAMAGED)') < start.index('LC_Sweep(') < start.index('if(acknowledge') < start.index('LC_Persist('), 'startup order'
assert 'if(acknowledge && s.halted!="")' in start and 's.halted="";' in start, 'acknowledgement'
assert 'LC_Remove(s,i);' in start and 'FileDelete' not in start and 'store.Write' not in start, 'an acknowledgement keeps the record'
ver = t[t.index('int LC_Verdict('):t.index('void LC_Sweep(')]
assert 'return(LC_V_HALT);' in ver and ver.count('LC_V_HALT') >= 2, 'unknown results halt'
assert 'if(f==EN_R_CANCELLED || f==EN_R_EXPIRED) return(LC_V_CLOSED);' in ver and 'if(f==EN_R_FILLED) return(LC_V_FILLED);' in ver, 'unknown results halt: only these outcomes close or fill'
assert 'if(r.reason=="ACTIVE") return(LC_V_OPEN);' in ver, 'only a proven ACTIVE order stays open'
dec = t[t.index('bool LC_Decode('):t.index('int LC_Load(')]
for w in ('CRC_MISMATCH', 'LOGIN_MISMATCH', 'BAD_COUNT', 'BAD_HEADER', 'NO_CRC'):
    assert w in dec, w
reg = t[t.index('bool LC_Register('):t.index('void LC_Halt(')]
assert 'LIFECYCLE_INDEX_FULL' in reg and 'LIFECYCLE_BAD_SIGNAL_ID' in reg and 'return(LC_Persist(' in reg, 'register'
assert 'back==text' in t[t.index('bool LC_Save('):t.index('bool LC_Persist(')], 'read-back'
assert 'LC_FileName' in t and 'VELO_T013_ENTRY_INDEX_' in t
PYEOF
python3 -I "$NEG/l2.py" $HD && echo "  PASS reconcile-only sweep, one gated cancel path, fresh runtime, halts, damaged file untouched, acknowledgement keeps records, CRC / login / count checks" || { echo "  FAIL"; FAIL=1; }

echo "=== L3: the EA keeps every cancel event off, wires the layer, has no order call and no T011 registration ==="
cat > "$NEG/l3.py" <<'PYEOF'
import re, sys
ea = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
for w in ('OrderSend', 'ETD_Register', 'EX_Register', 'ExitStateFile', 'ExitExecutor', 'EntryTransportReal', 'CEnRealTransport', 'TP_Authorize'):
    assert w not in ea, w
for n in ('InpCancelOnSessionEnd=false', 'InpCancelOnNewsBlock=false', 'InpCancelOnDailyLimit=false', 'InpAcknowledgeLifecycleHalt=false'):
    assert n in ea, 'default not off: ' + n
assert '#include "include/EntryLifecycle.mqh"' in ea
assert 'int EnabledCancelEvents(void)' in ea and 'InpCancelOnSessionEnd ? TP_EV_SESSION_END : 0' in ea
assert ea.count('LC_Tick(') == 1 and ea.count('LC_Startup(') == 1, 'one tick and one startup'
assert 'LC_Startup(g_cfg.exec,GetPointer(g_tr),GetPointer(g_store),InpAcknowledgeLifecycleHalt' in ea, 'the acknowledgement is an explicit input at start'
assert ea.index('LC_Startup(') < ea.index('EventSetTimer('), 'startup before the first poll'
poll = ea[ea.index('void Poll()'):ea.index('int OnInit()')]
assert 'Lifecycle();' in poll, 'the lifecycle call is missing'
assert poll.index('Lifecycle();') < poll.index('g_orch.Step('), 'the lifecycle runs before a new entry is considered'
assert 'EntryTouched(out.res.outcome)' in poll and 'LC_Register(' in poll, 'indexed after the executor reached the intent'
et = ea[ea.index('bool EntryTouched('):ea.index('int EnabledCancelEvents')]
assert 'EN_R_DUPLICATE' not in et and 'EN_R_REFUSED' not in et and 'EN_R_LOCK_FAILED' not in et, 'only outcomes with a record are indexed'
sync = ea[ea.index('void SyncHalts('):ea.index('void Lifecycle(')]
assert 'StringFind(g_orch.halted,"HALTED after")==0' in sync and 'g_lc.login>0' in sync, 'only an executor halt is persisted'
life = ea[ea.index('void Lifecycle()'):ea.index('void Poll()')]
assert 'if(enabled!=0 && g_lc.n>0' in life, 'the filters are read only when an event is enabled and a signal is open'
assert 'GetTickCount64()-g_lc_filters_ms>=10000' in life, 'filter throttle'
assert 'LC_DueEvents(session,news,present,(present && daily.cancel_pending_due))' in life, 'events from the existing filter results'
PYEOF
python3 -I "$NEG/l3.py" $EA && echo "  PASS cancel events off by default, explicit acknowledgement, startup before polling, lifecycle before a new entry, indexed only after a record exists, executor halts only, no registration" || { echo "  FAIL"; FAIL=1; }

echo "=== L4: the test uses the fake transport and store only ==="
grep -nE 'EntryTransportReal|ExitTransportReal|OrderSend|SymbolInfo|CopyRates|AccountInfo|FileOpen' $TS >/dev/null && { echo "  FAIL the test touches the real side"; FAIL=1; } || echo "  PASS fake transport and fake store only"

echo "=== L5: protected modules are untouched since $BASE ==="
for p in src/include/EntryExecutor.mqh src/include/EntryTransport.mqh src/include/EntryTransportFake.mqh src/include/EntryTransportReal.mqh src/include/EntryStateFile.mqh src/include/EntryGate.mqh \
         src/include/EntryOrchestrator.mqh src/include/EntryOrchestratorFeed.mqh src/include/ExposureReader.mqh src/include/ExposureReaderReal.mqh src/include/SetupPlanBridge.mqh src/include/TradePlanning.mqh \
         src/include/ExitExecutor.mqh src/include/ExitTickDriver.mqh src/include/ExitStateFile.mqh src/XauUsdTradePreview.mq5 src/XauUsdT011ExitManager.mq5 src/XauUsdT011ExitRegister.mq5; do
  if git cat-file -e $BASE:$p 2>/dev/null; then
    if git diff --quiet $BASE -- $p; then echo "  PASS $p identical to $BASE"; else echo "  FAIL $p differs from $BASE"; FAIL=1; fi
  else echo "  SKIP $p (base not available)"; fi
done

echo "=== L6: negative controls ==="
expect_assert() {   # $1 script, $2 file(s), $3 message, $4 text the assertion message must contain
  if err=$(python3 -I "$1" $2 2>&1 >/dev/null); then echo "  FAIL $3 NOT detected"; FAIL=1;
  elif echo "$err" | grep -q "AssertionError.*$4"; then echo "  PASS $3 is detected";
  else echo "  FAIL $3: the control broke for another reason: $(echo "$err" | tail -1)"; FAIL=1; fi
}
mut() {   # $1 name, $2 source, $3 sed expression
  cp "$2" "$NEG/$1"; sed -i "$3" "$NEG/$1"; cmp -s "$2" "$NEG/$1" && { echo "  FAIL control $1 changed nothing"; FAIL=1; }
}
mut A.mqh $HD 's/   int events=(due \& enabled);/   int events=due;/'
expect_assert "$NEG/l2.py" "$NEG/A.mqh" "a cancel for an event the owner did not enable" "due AND enabled"
mut B.mqh $HD 's/      EN_Reconcile(cfg,tr,store,id,r);/      EN_Reconcile(cfg,tr,store,id,r); EN_Cancel(cfg,tr,store,rt,id,dec,r);/'
expect_assert "$NEG/l2.py" "$NEG/B.mqh" "a cancel inside the sweep" "call sites\|only reconciles"
mut C.mqh $HD 's/   if(kind==LC_DAMAGED) {LC_Note(notes,s.halted); return(true);}/   if(kind==LC_DAMAGED) {LC_Note(notes,s.halted);}/'
expect_assert "$NEG/l2.py" "$NEG/C.mqh" "a damaged file that is overwritten" "damaged file returns"
mut D.mqh $HD 's/         EN_RuntimeInit(rt);/         \/\/ none/'
expect_assert "$NEG/l2.py" "$NEG/D.mqh" "a cancel without a fresh runtime" "fresh runtime"
mut E.mqh $HD 's/      if(r.reason=="ACTIVE") return(LC_V_OPEN);/      if(r.reason=="ACTIVE") return(LC_V_CLOSED);/'
expect_assert "$NEG/l2.py" "$NEG/E.mqh" "an active order that is no longer tracked" "ACTIVE"
mut F.mqh $HD 's/   if(f==EN_R_CANCELLED || f==EN_R_EXPIRED) return(LC_V_CLOSED);/   if(f==EN_R_CANCELLED || f==EN_R_EXPIRED || f==EN_R_RECOVERY) return(LC_V_CLOSED);/'
expect_assert "$NEG/l2.py" "$NEG/F.mqh" "an unprovable record treated as closed" "unknown results halt"
mut G.mqh $HD 's/   if(!store.Write(name,text)) return(false);/   if(!store.Write(name,text)) return(false); EN_Place();/'
expect_assert "$NEG/l2.py" "$NEG/G.mqh" "an order placement in the layer" "EN_Place"
mut H.mqh $EA 's/^input bool InpCancelOnSessionEnd=false;/input bool InpCancelOnSessionEnd=true;/'
expect_assert "$NEG/l3.py" "$NEG/H.mqh" "a cancel event on by default" "default not off"
mut I.mqh $EA 's/   Lifecycle();\n//; s/^   Lifecycle();$/   \/\/ none/'
expect_assert "$NEG/l3.py" "$NEG/I.mqh" "no lifecycle before a new entry" "lifecycle call is missing"
mut J.mqh $EA 's/StringFind(g_orch.halted,"HALTED after")==0 \&\& //'
expect_assert "$NEG/l3.py" "$NEG/J.mqh" "every orchestrator halt persisted" "only an executor halt"
mut K.mqh $EA 's/   EventKillTimer();/   EventKillTimer(); ETD_Register();/'
expect_assert "$NEG/l3.py" "$NEG/K.mqh" "a T011 registration in the EA" "ETD_Register"

[ $FAIL -eq 0 ] && echo "LIFECYCLE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "LIFECYCLE STATIC CHECKS: FAILURES"
exit $FAIL
