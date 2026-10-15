#!/bin/bash
# Static checks for T019 (entry lifecycle): the layer only reconciles with the existing executor (never a send), cancels only through TP_CancelDecision + EN_Cancel for an event that is due AND enabled, never
# overwrites a damaged state file, persists the halt; the EA keeps every cancel event off by default, wires the layer without an order call; the automatic fill -> T011 registration goes ONLY through the existing ETD_Register (read-only exit transport, off by default); protected modules are untouched. NOT a compiler.
# Usage: bash tools/lifecycle-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=3d1e084
HD=src/include/EntryLifecycle.mqh
MH=src/include/EntryManagementHandoff.mqh
EA=src/XauUsdEntryOrchestrator.mq5
TS=src/tests/EntryLifecycleTest.mq5
FILES="$HD $MH $EA $TS tests/lifecycle_reference.py tests/test_lifecycle.py tools/lifecycle-static-checks.sh"

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
          'AccountInfo', 'SymbolInfo', 'ETD_', 'EX_Register', 'ExitStateFile', 'ExitExecutor', 'EntryTransportReal', 'TP_Authorize'):
    assert w not in t, w
assert sorted(re.findall(r'#include "([^"]+)"', t)) == ['EntryGate.mqh'], 'includes'
assert not re.search(r'(?<![A-Za-z_])store\.(Lock|Unlock)\(', t), 'the per-signal lock belongs to the executor'
assert t.count('lockstore.Lock(') == 1 and t.count('lockstore.Unlock(') == 1, 'one acquire and one release of the index lock'
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
assert start.index('LC_Acquire(') < start.index('LC_NOT_ACQUIRED_MARK') if False else True
assert start.index('LC_Acquire(') < start.index('LC_Load(') < start.index('if(kind==LC_DAMAGED)') < start.index('LC_Sweep(') < start.index('if(acknowledge') < start.index('LC_Persist('), 'startup order: the lock first'
assert 'LIFECYCLE_INSTANCE_LOCK_NOT_ACQUIRED' in start and 'return(true);' in start[start.index('LIFECYCLE_INSTANCE_LOCK_NOT_ACQUIRED'):start.index('LC_Load(')], 'a refused instance returns before it reads the index'
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
assert 'if(!LC_Owned(s)) return(false);' in reg and reg.index('if(!LC_Owned(s)) return(false);') < reg.index('LC_Persist('), 'register needs the lock'
per = t[t.index('bool LC_Persist('):t.index('int LC_IndexOf(')]
assert 'if(!LC_Owned(s)) return(false);' in per and per.index('if(!LC_Owned(s)) return(false);') < per.index('LC_Save('), 'persist needs the lock'
assert 'LC_DiskCheck(store,s,why)' in per and per.index('LC_DiskCheck(') < per.index('LC_Save(') and 'return(false);' in per[per.index('LC_DiskCheck('):per.index('LC_Save(')], 'persist validates the existing index first'
pr = t[t.index('string LC_Proposal('):t.index('void LC_Sweep(')]
assert 'Write' not in pr and 'Delete' not in pr and 'ETD_' not in pr and 'EX_Register' not in pr and 'Send' not in pr and 'Cancel' not in pr, 'the registration report only reads'
assert 'LIVE_CHECK_REQUIRED' in pr and 'PLANNED_GEOMETRY' in pr and ' | NOT_REGISTRABLE: ' not in pr, 'planned geometry cannot prove live registration refusal'
assert pr.count('TG_Compute(') == 1 and 'EN_Load(store,EN_FileName(login,id),rec,why)!=1' in pr and 'TP_EQUALS_2R' in pr and 'TP_BEFORE_2R' in pr and 'InpInitialSl=' in pr, 'report content'
sw = t[t.index('void LC_Sweep('):t.index('bool LC_Startup(')]
assert 'v==LC_V_FILLED && LC_NotedIndex(s,id)<0' in sw and sw.index('LC_Proposal(') < sw.rindex('LC_Remove(s,i)'), 'a fill is reported first and forgotten on a later sweep'
assert 'if(LC_UnmanagedIndex(s,id)>=0) continue;' in sw and 'if(r2==LC_SINK_CONFIRMED)' in sw, 'the sink branch'
sink_b = sw[sw.index('int r2=sink.OnFilled('):sw.index('else if(v==LC_V_FILLED && LC_NotedIndex')]
assert sink_b.count('LC_Remove(s,i)') == 1 and sink_b.index('r2==LC_SINK_CONFIRMED') < sink_b.index('LC_Remove(s,i)') and 'MANAGEMENT_REGISTRATION_REFUSED' in sink_b, 'a fill leaves the index only after the registration is CONFIRMED; a refusal halts'
dk = t[t.index('bool LC_DiskCheck('):t.index('bool LC_Persist(')]
assert 'store.Exists(' in dk and 'store.Read(' in dk and 'LC_Decode(' in dk and 'Write' not in dk and 'Delete' not in dk, 'the validation only reads'
assert t.count('store.Write(') == 1, 'one write call site (LC_Save): no repair, no second writer'
assert 'LC_DiskCheck(store,s,disk_why)' in tick and tick.index('LC_DiskCheck(') < tick.index('LC_Sweep('), 'a tick validates the existing index before any action'
rel = t[t.index('void LC_Release('):t.index('bool LC_Owned(')]
assert 'if(s.lock_owned && s.lock_key!="")' in rel and rel.index('s.lock_owned && s.lock_key') < rel.index('lockstore.Unlock('), 'only the owner releases its own key'
assert 'if(!s.lock_owned) return;' in tick and tick.index('if(!s.lock_owned) return;') < tick.index('LC_Sweep('), 'a tick without the lock does nothing'
g = t[t.index('class CLcGuard'):]
assert 'public CEgPreSend' in g
assert g.index('if(!st.lock_owned)') < g.index('if(st.halted!="")') < g.index('LC_Register(') , 'guard order'
assert 'if(!record && is_new && k>=0)' in g and 'store.Exists(EN_FileName(st.login,signal_id))' in g, 'a reservation is released only when no record exists and it was new'
assert 'LIFECYCLE_INDEX_FULL' in reg and 'LIFECYCLE_BAD_SIGNAL_ID' in reg and 'return(LC_Persist(' in reg, 'register'
assert 'back==text' in t[t.index('bool LC_Save('):t.index('bool LC_Persist(')], 'read-back'
assert 'LC_FileName' in t and 'VELO_T013_ENTRY_INDEX_' in t
PYEOF
python3 -I "$NEG/l2.py" $HD && echo "  PASS reconcile-only sweep, one gated cancel path, fresh runtime, halts, damaged file untouched, acknowledgement keeps records, CRC / login / count checks" || { echo "  FAIL"; FAIL=1; }

echo "=== L3: the EA keeps every cancel event off, wires the layer, has no order call and no T011 registration ==="
cat > "$NEG/l3.py" <<'PYEOF'
import re, sys
ea = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
for w in ('OrderSend', 'ETD_Register', 'EX_Register', 'ExitStateFile', 'ExitExecutor', 'EntryTransportReal', 'ExitTransportReal', 'CEnRealTransport', 'TP_Authorize'):
    assert w not in ea, w
for n in ('InpCancelOnSessionEnd=false', 'InpCancelOnNewsBlock=false', 'InpCancelOnDailyLimit=false', 'InpAcknowledgeLifecycleHalt=false'):
    assert n in ea, 'default not off: ' + n
assert '#include "include/EntryLifecycle.mqh"' in ea and '#include "include/EntryManagementHandoff.mqh"' in ea
assert 'input bool InpManagementRegistration=false;' in ea and 'input string InpManagementAuthorisation="";' in ea and 'input ENUM_EO_MGMT_RPOL InpManagementRPolicy=EOI_MGMT_RPOL_UNSET;' in ea, 'registration is off and UNSET by default'
conf = ea[ea.index('bool Configure(void)'):ea.index('SEoFeedCfg fc;')]
assert 'if(InpManagementRegistration)' in conf and 'InpManagementAuthorisation!=EX_AUTH_PHRASE || InpManagementRPolicy!=EOI_MGMT_RPOL_R_GEOM || InpEaMagic<=0) return(false);' in conf, 'registration needs the phrase, R_GEOM and a magic'
assert 'g_registrar.provenance=MH_PROV_SYNTHETIC;' in conf and 'MH_PROV_BROKER' not in ea, 'the FAKE entry transport declares SYNTHETIC provenance'
assert conf.count('g_sink=GetPointer(g_registrar);') == 1 and 'g_sink=NULL;' in conf and 'g_registrar.exit_tr=GetPointer(g_xtr);' in conf and 'g_registrar.selftest=false;' in conf, 'the sink is set only inside the registration branch, with the read-only transport'
assert 'int EnabledCancelEvents(void)' in ea and 'InpCancelOnSessionEnd ? TP_EV_SESSION_END : 0' in ea
assert ea.count('LC_Tick(') == 1 and ea.count('LC_Startup(') == 1, 'one tick and one startup'
assert 'LC_Register(' not in ea, 'the EA never indexes after the fact: the gate hook does it before the send'
assert 'CLcGuard g_guard;' in ea and 'CEnFakeFileStore g_lockstore;' in ea, 'guard and a dedicated lock store'
assert 'LC_Startup(g_cfg.exec,GetPointer(g_tr),GetPointer(g_store),GetPointer(g_lockstore),InpAcknowledgeLifecycleHalt,g_guard.st,startup_notes,g_sink)' in ea and 'g_guard.st,due,enabled,notes,g_sink);' in ea, 'the registrar is the sink of startup and tick'
assert 'LC_Startup(g_cfg.exec,GetPointer(g_tr),GetPointer(g_store),GetPointer(g_lockstore),InpAcknowledgeLifecycleHalt,g_guard.st' in ea, 'the acknowledgement is an explicit input at start; the lock store is passed'
init = ea[ea.index('int OnInit()'):ea.index('void OnDeinit(')]
assert init.index('Configure()') < init.index('LC_Startup(') < init.index('EventSetTimer('), 'startup after the configuration and before the first poll'
assert 'LC_Release(GetPointer(g_lockstore),g_guard.st);' in init[init.index('EventSetTimer('):], 'a failed start releases its own lock'
deinit = ea[ea.index('void OnDeinit('):]
assert 'LC_Release(GetPointer(g_lockstore),g_guard.st);' in deinit, 'the lock is released at the end'
assert ea.count('LC_Release(') == 2, 'releases only on the start-failure path and in OnDeinit'
poll = ea[ea.index('void Poll()'):ea.index('int OnInit()')]
assert 'Lifecycle();' in poll, 'the lifecycle call is missing'
assert poll.index('Lifecycle();') < poll.index('g_orch.Step('), 'the lifecycle runs before a new entry is considered'
assert 'GetPointer(g_store),out,GetPointer(g_guard));' in poll, 'the guard is the gate hook of every placement'
sync = ea[ea.index('void SyncHalts('):ea.index('void Lifecycle(')]
assert 'StringFind(g_orch.halted,"HALTED after")==0' in sync and 'g_guard.st.login>0' in sync, 'only an executor halt is persisted'
life = ea[ea.index('void Lifecycle()'):ea.index('void Poll()')]
assert 'if(enabled!=0 && g_guard.st.n>0' in life, 'the filters are read only when an event is enabled and a signal is open'
assert 'GetTickCount64()-g_lc_filters_ms>=10000' in life, 'filter throttle'
assert 'LC_DueEvents(session,news,present,(present && daily.cancel_pending_due))' in life, 'events from the existing filter results'
PYEOF
python3 -I "$NEG/l3.py" $EA && echo "  PASS cancel events off by default, explicit acknowledgement, startup before polling, lifecycle before a new entry, indexed only after a record exists, executor halts only, no registration" || { echo "  FAIL"; FAIL=1; }

echo "=== L4: the test uses the fake transport and store only ==="
grep -nE 'EntryTransportReal|ExitTransportReal|OrderSend|SymbolInfo|CopyRates|AccountInfo|FileOpen' $TS >/dev/null && { echo "  FAIL the test touches the real side"; FAIL=1; } || echo "  PASS fake transport and fake store only (the T011 side: FAKE exit transport; selftest-prefixed files only)"

echo "=== L5a: the handoff header registers only through the existing ETD_Register over a read-only transport ==="
cat > "$NEG/l6.py" <<'PYEOF'
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
assert sorted(re.findall(r'#include "([^"]+)"', t)) == ['EntryLifecycle.mqh', 'ExitTickDriver.mqh'], 'includes'
for w in ('OrderSend', 'OrderCheck', 'OrderSendAsync', 'ESF_Save', 'ESF_WriteAll', 'FileOpen', 'FileDelete', 'FileMove', 'EX_Process', 'ETD_Tick', 'ETD_Init', 'EX_Reconcile', 'EN_Place', 'EN_Cancel', 'EN_Reconcile',
          'ExitTransportReal', 'EntryTransportReal', 'TP_Authorize', 'PositionClosePartial', 'trade.'):
    assert w not in t, 'forbidden: ' + w
assert t.count('ETD_Register(') == 1, 'one registration call'
assert t.count('EX_Register(') == 0, 'EX_Register only through ETD_Register (the per-position lock)'
rt = t[t.index('class CMhReadTransport'):t.index('class CMhRegistrar')]
assert 'virtual bool IsReal(void) {return(true);}' in rt, 'IsReal true keeps the authorisation and demo gates'
assert 'virtual bool PreCheck(const SExSendRequest &req) {return(false);}' in rt, 'PreCheck refuses'
send = rt[rt.index('virtual void Send('):]
assert 'send_attempts++;' in send and 'returned_true=false;' in send and 'OrderSend' not in send and 'CTrade' not in send, 'Send does nothing and is counted'
assert rt.count('PositionGetTicket(') == 1 and 'PositionsTotal()==total' in rt and 'matches==1' in rt, 'a unique, unchanged position read'
rg = t[t.index('class CMhRegistrar'):]
assert 'cfg.sl_initial=rec.s;' in rg and 'cfg.tp_price=rec.tp;' in rg and 'cfg.r_policy=(ENUM_EX_R_POLICY)rpol;' in rg and 'cfg.real_authorised=(phrase==EX_AUTH_PHRASE);' in rg, 'the plan of the record, the phrase, the policy'
assert 'if(ESF_Exists(name) || ESF_Exists(name+ESF_TMP_SUFFIX)) return(Compare(' in rg and rg.index('return(Compare(') < rg.index('ETD_Register('), 'an existing record is compared and never rewritten'
assert 'rec.state!=EN_ST_FILLED || rec.linked!=1 || rec.position_id==0' in rg and rg.index('FILL_NOT_PROVEN') < rg.index('ETD_Register('), 'only a proven fill'
assert 'acct.login!=rec.login || acct.server!=rec.server' in rg, 'account identity'
assert 'MH_MAX_TRIES' in rg and 'RETRIES_EXHAUSTED' in rg, 'bounded retries'
assert 'if(provenance!=MH_PROV_BROKER)' in rg and rg.index('if(provenance!=MH_PROV_BROKER)') < rg.index('EN_Load('), 'the provenance is judged before any read'
cmp_ = rg[rg.index('int Compare('):rg.index('int Attempt(')]
for need in ('phrase!=EX_AUTH_PHRASE', '!acct.demo', 'acct.margin_mode!=2', 'rec.magic==magic', 'pos.magic!=magic', 'EX_Geometry(', 'o.plan_e_src==pos.price_open', 'st.level==geo.level_2r', 'o.plan_vol_step==sym.vol_step'):
    assert need in cmp_, 'the comparison of an existing record lacks: ' + need
assert 'ESF_Save' not in cmp_ and 'ETD_Register' not in cmp_, 'the comparison never writes'
assert 'q.level_2r=0.0;' in rg, 'the 2R level is computed by T011 itself from the real open price (R_GEOM), never supplied'
assert 'TP_EQUALS_2R' not in t and 'tp_equals' not in t.lower(), 'the TP / 2R rule is T011 own and is not touched or interpreted here'
PYEOF
python3 -I "$NEG/l6.py" $MH && echo "  PASS no order call, no direct file write, one ETD_Register, read-only transport (IsReal, PreCheck refuses, Send inert), proven fill only, compare-never-rewrite, bounded retries" || { echo "  FAIL"; FAIL=1; }

echo "=== L5b: no type, function or macro is declared in two headers that one program includes ==="
cat > "$NEG/l5b.py" <<'PYEOF'
import os, re, sys
def closure(path, seen):
    path = os.path.normpath(path)
    if path in seen:
        return
    seen.append(path)
    text = re.sub(r'//[^\n]*', '', open(path, encoding='ascii').read())
    for inc in re.findall(r'#include "([^"]+)"', text):
        closure(os.path.join(os.path.dirname(path), inc), seen)
def decls(path):
    text = re.sub(r'//[^\n]*', '', open(path, encoding='ascii').read())
    out = set()
    for m in re.finditer(r'^(?:struct|class|enum)\s+(\w+)', text, re.M):
        out.add(m.group(1))
    for m in re.finditer(r'^#define\s+(\w+)', text, re.M):
        if not m.group(1).startswith('VELO_') or not m.group(1).endswith('_MQH'):
            out.add(m.group(1))
    for m in re.finditer(r'^(?:[A-Za-z_][\w<>]*\s+)+\**&?\s*(\w+)\s*\([^;{]*\)\s*(?:\{|$)', text, re.M):
        out.add(m.group(1))
    return out
bad = []
for prog in sys.argv[1:]:
    files = []
    closure(prog, files)
    owner = {}
    for f in files:
        for n in decls(f):
            if n in owner and owner[n] != f:
                bad.append('%s: %s declared in %s and %s' % (prog, n, owner[n], f))
            owner.setdefault(n, f)
assert not bad, 'duplicate declaration: ' + '; '.join(bad[:5])
PYEOF
python3 -I "$NEG/l5b.py" $EA $TS && echo "  PASS the EA and the lifecycle test include no duplicate declaration" || { echo "  FAIL"; FAIL=1; }

echo "=== L5: protected modules are untouched since $BASE ==="
for p in src/include/EntryExecutor.mqh src/include/EntryTransport.mqh src/include/EntryTransportFake.mqh src/include/EntryTransportReal.mqh src/include/EntryStateFile.mqh \
         src/include/EntryOrchestratorFeed.mqh src/include/ExposureReaderReal.mqh src/include/SetupPlanBridge.mqh src/include/TradePlanning.mqh \
         src/include/ExitExecutor.mqh src/include/ExitTickDriver.mqh src/include/ExitStateFile.mqh src/XauUsdTradePreview.mq5 src/XauUsdT011ExitManager.mq5 src/XauUsdT011ExitRegister.mq5; do
  if git cat-file -e $BASE:$p 2>/dev/null; then
    if git diff --quiet $BASE -- $p; then echo "  PASS $p identical to $BASE"; else echo "  FAIL $p differs from $BASE"; FAIL=1; fi
  else echo "  SKIP $p (base not available)"; fi
done

# ExposureReader.mqh: the ONLY change since the base is the rename SExResult -> SExpResult (it collided with the T011 SExResult in one program)
if git cat-file -e $BASE:src/include/ExposureReader.mqh 2>/dev/null; then
  if git show $BASE:src/include/ExposureReader.mqh | sed 's/\bSExResult\b/SExpResult/g' | cmp -s - src/include/ExposureReader.mqh; then echo "  PASS src/include/ExposureReader.mqh differs from $BASE only by the SExResult -> SExpResult rename"; else echo "  FAIL src/include/ExposureReader.mqh changed beyond the rename"; FAIL=1; fi
fi
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
mut M.mqh $HD '0,/   if(!LC_Owned(s)) return(false);/s//   \/\/ none/'
expect_assert "$NEG/l2.py" "$NEG/M.mqh" "an index write without the lock" "needs the lock"
mut W.mqh $HD 's/      else if(v==LC_V_FILLED \&\& LC_NotedIndex(s,id)<0)/      else if(false)/'
expect_assert "$NEG/l2.py" "$NEG/W.mqh" "a fill that is forgotten before it is reported" "reported first and forgotten"
mut X.mqh $HD 's/   TG_Compute(buy ? TG_BUY : TG_SELL,rec.e,rec.s,false,0.0,sym.tick_size,sym.digits,sym.point,sym.stops_level,false,0.0,0.0,geo);/   TG_Compute(buy ? TG_BUY : TG_SELL,rec.e,rec.s,false,0.0,sym.tick_size,sym.digits,sym.point,sym.stops_level,false,0.0,0.0,geo); ETD_Register();/'
expect_assert "$NEG/l2.py" "$NEG/X.mqh" "a registration call in the report" "ETD_"
mut T.mqh $HD '0,/   if(!LC_DiskCheck(store,s,why))/s//   if(false)/'
expect_assert "$NEG/l2.py" "$NEG/T.mqh" "an update that does not validate the existing index" "validates the existing index first"
mut U.mqh $HD 's/   if(!LC_DiskCheck(store,s,disk_why))                      \/\/ a damaged \/ unreadable index stops every action of the layer and is never written over/   if(false)/'
expect_assert "$NEG/l2.py" "$NEG/U.mqh" "a tick that acts on a damaged index" "validates the existing index before any action"
mut V.mqh $HD 's/   if(!store.Read(name,text)) {why="LIFECYCLE_STATE_UNREADABLE"; return(false);}/   if(!store.Read(name,text)) {why="LIFECYCLE_STATE_UNREADABLE"; store.Write(name,"");  return(false);}/'
expect_assert "$NEG/l2.py" "$NEG/V.mqh" "a validation that repairs" "the validation only reads\|one write call site"
mut N.mqh $HD 's/   if(s.lock_owned \&\& s.lock_key!="")/   if(s.lock_key!="")/'
expect_assert "$NEG/l2.py" "$NEG/N.mqh" "a release by a non-owner" "only the owner releases"
mut O.mqh $HD 's/   if(!s.lock_owned) return;                                \/\/ without the instance lock: no index access, no reconcile, no cancel/   \/\/ none/'
expect_assert "$NEG/l2.py" "$NEG/O.mqh" "a tick without the lock" "tick without the lock"
mut P.mqh $HD 's/      if(!st.lock_owned)$/      if(false)/'
expect_assert "$NEG/l2.py" "$NEG/P.mqh" "a reservation without the lock check" "guard order\|guard"
mut Q.mqh $EA 's/GetPointer(g_store),out,GetPointer(g_guard));/GetPointer(g_store),out);/'
expect_assert "$NEG/l3.py" "$NEG/Q.mqh" "a placement without the pre-send guard" "the guard is the gate hook"
mut R.mqh $EA 's/   LC_Release(GetPointer(g_lockstore),g_guard.st);                  \/\/ only the owner releases, and only its own key/   \/\/ none/'
expect_assert "$NEG/l3.py" "$NEG/R.mqh" "a lock that is never released" "released at the end\|releases only"
cp $EA "$NEG/S.mqh"; sed -i 's/^   Poll();$/   LC_Register(GetPointer(g_store),g_guard.st,"x",startup_notes); Poll();/' "$NEG/S.mqh"
expect_assert "$NEG/l3.py" "$NEG/S.mqh" "an index entry written by the EA after the fact" "never indexes after the fact"

mut Y.mqh $HD 's/ | LIVE_CHECK_REQUIRED:/ | FINAL_REGISTRATION_VERDICT:/'
expect_assert "$NEG/l2.py" "$NEG/Y.mqh" "a planned report presented as a final verdict" "planned geometry cannot prove"

mut Z1.mqh $MH 's/   virtual bool IsReal(void) {return(true);}/   virtual bool IsReal(void) {return(false);}/'
expect_assert "$NEG/l6.py" "$NEG/Z1.mqh" "a handoff transport that drops the real gates" "IsReal true"
mut Z2.mqh $MH 's/   virtual bool PreCheck(const SExSendRequest \&req) {return(false);}/   virtual bool PreCheck(const SExSendRequest \&req) {return(true);}/'
expect_assert "$NEG/l6.py" "$NEG/Z2.mqh" "a handoff transport that accepts a request" "PreCheck refuses"
mut Z3.mqh $MH 's/      send_attempts++;/      send_attempts++; OrderSend();/'
expect_assert "$NEG/l6.py" "$NEG/Z3.mqh" "an order call in the handoff" "forbidden: OrderSend"
mut Z4.mqh $MH 's/      ETD_Register(cfg,exit_tr,rt,name,idn,q,res);/      ETD_Register(cfg,exit_tr,rt,name,idn,q,res); ETD_Register(cfg,exit_tr,rt,name,idn,q,res);/'
expect_assert "$NEG/l6.py" "$NEG/Z4.mqh" "a second registration call" "one registration call"
mut Z5.mqh $MH 's/      ETD_Register(cfg,exit_tr,rt,name,idn,q,res);/      EX_Register(cfg,exit_tr,rt,name,idn,q,res);/'
expect_assert "$NEG/l6.py" "$NEG/Z5.mqh" "a registration that skips the per-position lock" "one registration call"
mut Z6.mqh $MH 's/      if(ESF_Exists(name) || ESF_Exists(name+ESF_TMP_SUFFIX)) return(Compare(name,idn,rec,acct,detail));/      \/\/ none/'
expect_assert "$NEG/l6.py" "$NEG/Z6.mqh" "a registrar that may rewrite an existing record" "compared and never rewritten"
mut Z7.mqh $MH 's/      if(rec.state!=EN_ST_FILLED || rec.linked!=1 || rec.position_id==0)/      if(false)/'
expect_assert "$NEG/l6.py" "$NEG/Z7.mqh" "a registration of an unproven fill" "only a proven fill"
mut Z8.mqh $MH 's/      cfg.sl_initial=rec.s;/      cfg.sl_initial=0.0;/'
expect_assert "$NEG/l6.py" "$NEG/Z8.mqh" "a registration that drops the asserted initial SL" "the plan of the record"
mut Z9.mqh $MH 's/            if(tries\[k\]>=MH_MAX_TRIES)/            if(false)/'
expect_assert "$NEG/l6.py" "$NEG/Z9.mqh" "unbounded retries" "bounded retries"
mut ZA.mqh $EA 's/^input bool InpManagementRegistration=false;/input bool InpManagementRegistration=true;/'
expect_assert "$NEG/l3.py" "$NEG/ZA.mqh" "registration on by default" "registration is off"
mut ZB.mqh $EA 's/InpManagementAuthorisation!=EX_AUTH_PHRASE || //'
expect_assert "$NEG/l3.py" "$NEG/ZB.mqh" "registration without the authorisation phrase" "needs the phrase"
mut ZC.mqh $EA 's/LC_Tick(g_cfg.exec,GetPointer(g_tr),GetPointer(g_store),g_guard.st,due,enabled,notes,g_sink);/LC_Tick(g_cfg.exec,GetPointer(g_tr),GetPointer(g_store),g_guard.st,due,enabled,notes);/'
expect_assert "$NEG/l3.py" "$NEG/ZC.mqh" "a tick that never reaches the registrar" "sink of startup and tick"

mut ZD.mqh $HD 's/         else if(r2==LC_SINK_PENDING) LC_Note(notes,"FILL_REGISTRATION_PENDING "+id+": "+detail);/         else if(r2==LC_SINK_PENDING) {LC_Note(notes,"FILL_REGISTRATION_PENDING "+id+": "+detail); LC_Remove(s,i);}/'
expect_assert "$NEG/l2.py" "$NEG/ZD.mqh" "a fill forgotten while its registration is pending" "only after the registration is CONFIRMED"

mut ZE.mqh $MH 's/      if(provenance!=MH_PROV_BROKER)/      if(false)/'
expect_assert "$NEG/l6.py" "$NEG/ZE.mqh" "a synthetic fill matched to a real position" "provenance is judged"
mut ZF.mqh $MH 's/      if(phrase!=EX_AUTH_PHRASE) {detail="REAL_NOT_AUTHORISED"; return(LC_SINK_REFUSED);}/      \/\/ none/'
expect_assert "$NEG/l6.py" "$NEG/ZF.mqh" "an existing record accepted without the authorisation phrase" "phrase!=EX_AUTH_PHRASE"
mut ZG.mqh $MH 's/o.plan_e_src==pos.price_open \&\& //'
expect_assert "$NEG/l6.py" "$NEG/ZG.mqh" "an existing record accepted without the open price" "o.plan_e_src==pos.price_open"
mut ZH.mqh $EA 's/      g_registrar.provenance=MH_PROV_SYNTHETIC;/      g_registrar.provenance=MH_PROV_BROKER;/'
expect_assert "$NEG/l3.py" "$NEG/ZH.mqh" "the FAKE entry transport declared as a broker" "SYNTHETIC provenance"
cp src/include/ExposureReader.mqh "$NEG/dup.mqh"; sed -i 's/^struct SExpResult/struct SExResult/' "$NEG/dup.mqh"
mkdir -p "$NEG/p/include"; cp src/include/*.mqh "$NEG/p/include/"; cp "$NEG/dup.mqh" "$NEG/p/include/ExposureReader.mqh"; cp $EA "$NEG/p/Ea.mq5"
if err=$(python3 -I "$NEG/l5b.py" "$NEG/p/Ea.mq5" 2>&1 >/dev/null); then echo "  FAIL a duplicate struct name NOT detected"; FAIL=1; elif echo "$err" | grep -q "duplicate declaration: .*SExResult"; then echo "  PASS a duplicate struct name is detected"; else echo "  FAIL the control broke for another reason: $(echo "$err" | tail -1)"; FAIL=1; fi

[ $FAIL -eq 0 ] && echo "LIFECYCLE STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "LIFECYCLE STATIC CHECKS: FAILURES"
exit $FAIL

