#!/bin/bash
# Static checks for the T016 entry orchestrator: geometry, broker probe, final plan, EG_Submit in order; recovery and context changes rebase; the EA and the feed
# never send an order, never CAPTURE, never include a real transport, expose no transport selector and label every virtual request; protected modules are untouched. NOT a compiler, NOT an MT5 run.
# Usage: bash tools/entry-orchestrator-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
BASE=e8968bd
CORE=src/include/EntryOrchestrator.mqh
FEED=src/include/EntryOrchestratorFeed.mqh
EA=src/XauUsdEntryOrchestrator.mq5
TS=src/tests/EntryOrchestratorTest.mq5
FILES="$CORE $FEED $EA $TS tests/eo_reference.py tests/test_eo.py tools/entry-orchestrator-static-checks.sh"

echo "=== O1: files exist, ASCII only ==="
for f in $FILES; do
  [ -s "$f" ] || { echo "  FAIL $f missing or empty"; FAIL=1; continue; }
  if LC_ALL=C grep -nP '[^\x00-\x7F]' "$f" >/dev/null; then echo "  FAIL $f has non-ASCII characters"; FAIL=1; else echo "  PASS $f exists, ASCII"; fi
done

echo "=== O2: the core reuses the modules, in the pinned order, and touches no terminal ==="
cat > "$NEG/o2.py" <<'PYEOF'
import re, sys
t = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
assert t.count('SPB_Geometry(') == 1 and t.count('SPB_Build(') == 1 and t.count('EG_Submit(') == 1 and t.count('PB_ProbeTickValue(') == 1, 'call sites'
for w in ('OrderSend', 'OrderCheck', 'OrderCalcProfit', 'TP_Authorize', 'DG_FinalPreview', 'FileOpen', 'FileWrite', 'GlobalVariable', 'TimeCurrent', 'TimeGMT', 'TimeLocal', 'Sleep', 'AccountInfo', 'SymbolInfo',
          'DBS_Capture', 'DBS_Load', 'CAPTURE', 'TP_BuildPlan', 'TG_Compute', 'PS_Compute', 'M4Step(', 'M4Replay', 'H3Evaluate', 'EntryTransportReal', 'ExitTransportReal', 'EN_Place(', 'store.Write', 'store.Lock', 'MathMax(baseline,0'):
    assert w not in t, w
step = t[t.index('void Step('):]
order = ['if(!feed_ok)', 'Defect();', '!M4ContextEqual(st.context,previous_context)) rebase=true', 'baseline=MathMax(baseline,(long)cut)', 'if(halted!="")', 'EO_UnsetConfig(c)', 'mk.Symbol(sym)', 'mk.Quote(q)', 'sel.live_after=baseline',
         'SPB_Geometry(sel,m,st,f,broken,cut,r1,geo)', 'Handled(r1.signal_id)', 'mk.CalcProfit(buy,sym.vol_min', 'PB_ProbeTickValue(', 'm.tick_value=tick', 'SPB_Build(sel,m,st,f,broken,cut,r2)',
         'mk.CalcProfit(buy,r2.plan.volume_out', 'mk.Filters(', 'chk.daily_present=mk.Daily(', 'EG_Submit(', 'Remember(r2.signal_id)', 'halted="HALTED after']
for o in order:
    assert o in step, 'missing step: ' + o
pos = [step.index(o) for o in order]
assert pos == sorted(pos), pos
assert 'baseline=MathMax(baseline' in step and 'baseline=cut' not in step and 'baseline=0' not in step, 'baseline can move backwards'
assert 'if(!(tick>0.0))' in step and 'tick=sym.reported_tick_value' not in step, 'tick value'
assert '{Defect(); EO_Set(out,"MARKET_NOT_READY","SYMBOL_UNREADABLE_OR_NOT_TRADABLE")' in step, 'symbol recovery baseline'
assert '{Defect(); EO_Set(out,"MARKET_NOT_READY","QUOTE_NOT_READY_OR_STALE")' in step, 'quote recovery baseline'
assert 'chk.snap_digest=digest' in step and 'chk.loss_digest=digest' in step and 'chk.daily_digest=digest' in step, 'plan digest binding'
assert 'chk.snap_time=now' in step and 'chk.loss_time=now' in step and 'chk.daily_time=now' in step, 'shared instant'
assert 'EN_RuntimeInit(rt)' in step and step.index('EN_RuntimeInit(rt)') < step.index('EG_Submit('), 'fresh runtime per signal'
assert 'out.res,out.dec,pre_send);' in step and 'CEgPreSend *pre_send=NULL' in step, 'the pre-send hook is passed to the gate'
assert 'RESERVATION_FAILED' in step and step.index('GATE_BLOCKED') < step.index('RESERVATION_FAILED') < step.index('out.request=true'), 'a refused reservation is reported and does not consume the signal'
assert 'EN_R_CANCEL_UNCERTAIN' in step and 'EN_R_RECOVERY' in step and 'EN_R_BLOCKED' in step, 'halt results'
assert 'EO_FAKE_LABEL' in step and 'out.request=true' in step, 'label'
assert re.search(r'out\.request=true;\s*out\.label=EO_FAKE_LABEL', step), 'request without label'
assert 'EO_FactsInit(facts);' in step and step.index('EO_FactsInit(facts);') < step.index('if(!feed_ok)'), 'the facts are cleared at every step'
assert 'st.context.ready && st.context.reliable && st.context.selected && (st.context.direction==1 || st.context.direction==-1)' in step, 'the context direction is a fact only when the context is known'
assert 'if(facts.valid) {facts.signal_direction=st.context.direction; facts.signal_id=r1.signal_id;}' in step, 'a signal fact exists only when the geometry produced a live signal'
assert step.index('facts.valid=true;') < step.index('if(halted!="")') and step.index('facts.signal_id=r1.signal_id;') < step.index('Handled(r1.signal_id)'), 'order of the facts'
assert 'EO_RISK_PCT_DEMO 1.0' in t, 'the demo policy is exactly 1%'
assert 'if(c.risk_source==EO_RISK_SOURCE_DEMO_BALANCE_PCT || sim)' in step and 'mk.Balance(bal);' in step and step.count('mk.Balance(') == 1, 'the balance is read at every step, inside the policy branch only'
assert 'bool sim=(c.risk_source==EO_RISK_SOURCE_SIMULATION_BALANCE_PCT);' in step and 'if(sim && tr.IsReal())' in step and step.index('if(sim && tr.IsReal())') < step.index('mk.Balance('), 'the simulation policy is refused with a real transport BEFORE the balance is read'
assert 'SIMULATION_ONLY_REQUIRES_THE_FAKE_ENTRY_TRANSPORT' in step and 'label=(sim ? "SIMULATION ONLY" : "DEMO");' in step and 'out.risk_label=label;' in step and 'out.account_mode=mode;' in step, 'the label and the raw account mode are reported'
assert 'bal.demo || sim' in step and step.count('sim') <= 14, 'the simulation policy relaxes ONLY the classification check, nowhere else'
assert 'EO_RISK_SOURCE_SIMULATION_BALANCE_PCT 2' in t, 'one new source value'
assert 'bal.read_ok && (bal.demo || sim) && TG_Finite(bal.amount) && bal.amount>0.0 && now-bal.time>=0 && now-bal.time<=c.max_quote_age' in step, 'read ok, demo, finite, positive and fresh'
assert 'RISK_BASE_NOT_READY' in step and step.count('mk.Balance(') == 1, 'a failed read blocks (no fallback)'
assert 'budget=bal.amount*EO_RISK_PCT_DEMO/100.0;' in step and 'm.risk_budget=budget;' in step and 'chk.risk_budget=budget;' in step and 'c.risk_budget' not in step.replace('double budget=c.risk_budget;', ''), 'one budget sizes the plan and checks the loss'
balance_part = step[step.index('mk.Balance(bal);'):step.index('m.risk_budget=budget;')]
assert 'now=mk.Now();' in balance_part and balance_part.index('now=mk.Now();') < balance_part.index('now-bal.time>=0'), 'balance clock must be sampled after the read'
assert 'now<before_balance' in balance_part and 'QUOTE_EXPIRED_DURING_BALANCE_READ' in balance_part, 'backwards clock and quote age after balance are checked'
for code in ('BALANCE_READ_FAILED', 'ACCOUNT_NOT_DEMO', 'BALANCE_INVALID_AMOUNT', 'BALANCE_TIME_INVALID', 'BALANCE_FROM_FUTURE', 'BALANCE_STALE'):
    assert code in balance_part, 'specific balance refusal: ' + code
assert step.index('mk.Balance(') < step.index('m.risk_budget=budget;') < step.index('SPB_Geometry('), 'the budget is known before the plan is sized'
assert 'virtual void Balance(SEoBalance &b) {b.read_ok=false;' in t, 'the default market gives no balance'
inc = re.findall(r'#include "([^"]+)"', t)
assert inc == ['EntryGate.mqh'], inc
PYEOF
python3 -I "$NEG/o2.py" $CORE && echo "  PASS call sites, no terminal / file / clock / real transport, order, baseline, probe, shared instant and digest, fresh runtime, halt, label" || { echo "  FAIL"; FAIL=1; }

echo "=== O3: the EA and the feed: fake transport by default, real transports only by explicit authorised inputs, read-only feed, LOAD only, labelled ==="
cat > "$NEG/o3.py" <<'PYEOF'
import re, sys
ea = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
fd = re.sub(r'//[^\n]*', '', open(sys.argv[2], encoding='ascii').read())
for name, t in (('EA', ea), ('feed', fd)):
    for w in ('OrderSend', 'OrderSendAsync', 'OrderCheck', 'OrderDelete', 'PositionClose', 'CTrade', 'DBS_Capture', 'DBS_Write', 'CAPTURE', 'TP_Authorize', 'DG_FinalPreview', 'FileOpen', 'FileWrite', 'FileDelete',
              'GlobalVariableSet', 'ExitStateFile', 'ExitExecutor', 'ObjectCreate', 'real=true', 'real = true'):
        assert w not in t, name + ': ' + w
for w in ('EntryTransportReal', 'ExitTransportReal', 'CEnRealTransport', 'CEnRealStore', 'CRealTransport'):
    assert w not in fd, 'feed: ' + w
poll = ea[ea.index('void Poll()'):ea.index('int OnInit()')]
pre_step = poll[:poll.index('g_orch.Step(')]
assert 'g_feed.Poll(feed_ok);' in pre_step and 'return;' not in pre_step, 'timer must recheck the market with cached feed'
assert poll.count('g_feed.Poll(') == 1 and poll.count('g_orch.Step(') == 1, 'one feed refresh and market evaluation per poll'
assert 'if(exposure!=g_last_exposure)' in poll, 'unchanged exposure logs are suppressed'
assert 'DBS_Load(' in fd and fd.count('DBS_Load(') == 1, 'the store is read with LOAD only'
# the daily glue of the real market: the stored day balance is LOADED, fed to the bridge, and only then checked; one offset serves the history window and the store; nothing is captured or invented
daily_fn = fd[fd.index('virtual bool Daily('):]
for needle in ('DBS_Load(port,stored);', 'DBS_ForBridge(stored,balance);', 'DB_Check(verdict,facts,hcfg.utc_in_day,balance,policy,cl,'):
    assert needle in daily_fn, 'daily glue: ' + needle
assert daily_fn.index('DH_ReadAndBuild(') < daily_fn.index('DBS_Load(port,stored);') < daily_fn.index('DBS_ForBridge(stored,balance);') < daily_fn.index('DB_Check('), 'daily glue order: history, LOAD, bridge feed, check'
assert 'hcfg.server_offset_seconds=daily_offset;' in daily_fn and 'CDbsRealPort port(mc.daily_magic,daily_offset,' in daily_fn, 'one offset for the history window and the store port'
assert 'EO_OffsetSeconds(mc.daily_offset_seconds,daily_offset)' in daily_fn and daily_fn.index('EO_OffsetSeconds(') < daily_fn.index('DH_ReadAndBuild('), 'an invalid offset returns before any history read'
# the status diagnostics reuse the existing T003 evaluation of the build; no second evaluation, nothing in a decision reads them
assert fd.count('H3Evaluate(') == 1 and fd.count('H3SetupContext(') == 1, 'diagnostics: no second H3Evaluate / H3SetupContext'
snap = fd[fd.index('void Snapshot('):fd.index('void BrokenLevel(')]
assert snap.index('T003View(n,e,c);') < snap.index('dg_ctx_ok=M4ContextFromH3(c,e.reliable,') < snap.index('dg_reliable=e.reliable; dg_flag=e.flag; dg_reason=e.reason;') and 'dg_phase=c.phase;' in snap, 'diagnostics keep the result of the existing evaluation'
diag = fd[fd.index('string Diag(void)'):fd.index('bool Poll(bool &feed_ok)')]
for w in ('H3Evaluate', 'H3SetupContext', 'M4ContextFromH3', 'CopyRates', 'Refresh(', 'Build(', 'Reset('):
    assert w not in diag, 'diagnostics must be read only: ' + w
rest = fd.replace(snap, '').replace(diag, '')
for ln in rest.split('\n'):
    if 'dg_' in ln:
        assert re.match(r'^\s*(bool|int|string|datetime) dg_\w+;\s*$', ln) or ln.strip() == 'dg_have=false;', 'diagnostic members outside Snapshot / Diag are declarations and the Reset clear only: ' + ln
assert 'dg_' not in ea, 'the EA does not read the diagnostic members'
assert ea.count('g_feed.Diag()') == 1 and 'text+=" | "+g_feed.Diag();' in poll, 'one diagnostic suffix in the status text'
assert poll.index('text+=" | "+g_feed.Diag();') > poll.index('g_orch.Step('), 'the diagnostics are appended after the decision step'
assert 'class CEoTerminalFake : public CEnFakeTransport' in ea, 'fake transport class'
assert ea.count('CEoTerminalFake g_tr;') == 1 and 'g_trp=GetPointer(g_tr);' in ea, 'the FAKE transport is the default'
assert 'EO_FAKE_LABEL' in ea and 'CEnFakeTransport::Send(req,res)' in ea, 'virtual request label'
assert 'MQL_TESTER' in ea and 'INIT_FAILED' in ea, 'tester refused'
assert 'CEnFakeFileStore g_store;' in ea, 'persistent FAKE store'
assert 'g_cfg.exec.symbol=_Symbol;' in ea and 'XAUUSD' not in ea.replace('XauUsdEntryOrchestrator', ''), 'chart symbol only'
inputs = re.findall(r'^input\s+\S+\s+(\w+)', ea, re.M)
assert inputs, 'inputs'
SELECTORS = ('InpEntryTransport', 'InpEntryAuthorisation', 'InpManagementTransport', 'InpManagementConfirmAutoSend')
for n in inputs:
    if re.search(r'(?i)transport|real|live|send|order', n):
        assert n in SELECTORS, 'a transport selector input: ' + n
# the REAL transports are compiled in but selected only by the explicit, default-off, authorised inputs; the FAKE transport is the default
for d in ('InpEntryTransport=EOI_ETR_FAKE', 'InpEntryAuthorisation=""', 'InpManagementTransport=EOI_MTR_READ_ONLY', 'InpManagementConfirmAutoSend=false', 'InpManagementRegistration=false', 'InpMgmtFilling=EX_FILL_UNSET',
          'InpMgmtDeviation=-1', 'InpMgmtFilterPolicy=EX_POL_UNSET'):
    assert d in ea, 'default not off / UNSET: ' + d
assert ea.count('CEnRealTransport g_etr;') == 1 and ea.count('CRealTransport g_mreal;') == 1 and ea.count('GetPointer(g_etr)') == 1 and ea.count('GetPointer(g_mreal)') == 1, 'each real transport is declared once and selected at one place'
conf = ea[ea.index('bool Configure(void)'):ea.index('// an unknown enum value') if '// an unknown enum value' in ea else ea.index('SEoFeedCfg fc;')]
sel = conf[conf.index('if(InpEntryTransport==EOI_ETR_BROKER_DEMO)'):]
assert 'if(InpEntryAuthorisation!=EN_AUTH_PHRASE || !InpManagementRegistration || InpEaMagic<=0 || InpFilling!=EOI_FILL_RETURN) return(false);' in sel, 'the real entry transport needs the phrase, registration, a magic and filling RETURN'
assert sel.index('InpEntryAuthorisation!=EN_AUTH_PHRASE') < sel.index('GetPointer(g_etr)'), 'the phrase is checked before the real entry transport is selected'
assert 'if(InpManagementTransport==EOI_MTR_BROKER_DEMO && (!InpManagementConfirmAutoSend || !InpManagementRegistration)) return(false);' in conf, 'real closing requests need the confirmation and registration'
assert conf.index('!InpManagementConfirmAutoSend') < conf.index('GetPointer(g_mreal)'), 'the confirmation is checked before the real closing transport is selected'
assert 'g_registrar.provenance=(g_real_entry ? MH_PROV_BROKER : MH_PROV_SYNTHETIC);' in conf, 'provenance follows the entry transport'
assert 'g_cfg.exec.real_authorised=g_real_entry;' in ea, 'the executor authorisation follows the explicit selection'
SIM = 'if(InpRiskSource==EOI_RISK_SIMULATION_1PCT_CURRENT_BALANCE && (InpEntryTransport!=EOI_ETR_FAKE || InpManagementTransport!=EOI_MTR_READ_ONLY || InpManagementConfirmAutoSend || InpEntryAuthorisation!=\"\")) return(false);'
assert SIM in conf, 'SIMULATION ONLY is allowed only with the FAKE entry, READ_ONLY management, no confirmation and no phrase'
assert conf.index(SIM) < conf.index('GetPointer(g_etr)'), 'the simulation refusal comes before any real transport is selected'
# every selection / policy input is UNSET by default
for n in ('InpContextSource=EOI_SRC_UNSELECTED', 'InpM15Level=EOI_SWING_UNSELECTED', 'InpFvgTiming=EOI_TIMING_UNSELECTED', 'InpCandidate=EOI_CAND_UNSELECTED', 'InpEntryEdge=EOI_EDGE_UNSELECTED',
          'InpSlRule=EOI_SL_UNSELECTED', 'InpRiskSource=EOI_RISK_AMOUNT', 'InpSlBuffer=-1', 'InpTargetRule=EOI_TGT_UNSELECTED', 'InpRiskBudget=-1', 'InpLotCap=-1', 'InpModelTolerance=-1', 'InpMaxQuoteAgeSeconds=-1', 'InpGateMaxAgeSeconds=-1',
          'InpPermitMaxAgeSeconds=-1', 'InpOpenPositions=-1', 'InpTradesToday=-1', 'InpExistingRisk=-1', 'InpMaxPositions=-1', 'InpMaxTrades=-1', 'InpCombinedRiskCap=-1', 'InpSessionClock=false',
          'InpNewsCalendar=false', 'InpMaxSpreadPoints=-1', 'InpDailyHistoryBridge=false', 'InpDailyServerOffsetSeconds=99999', 'InpDailyHistoryComplete=false', 'InpFilling=EOI_FILL_UNSET', 'InpExpiryMode=EOI_EXP_UNSET'):
    assert n in ea, 'default not UNSET: ' + n
assert sorted(re.findall(r'#include "([^"]+)"', ea)) == sorted(['include/EntryOrchestratorFeed.mqh', 'include/EntryStateFile.mqh', 'include/EntryTransportFake.mqh', 'include/EntryLifecycle.mqh', 'include/EntryManagementHandoff.mqh', 'include/EntryNotify.mqh', 'include/EntryTransportReal.mqh', 'include/ExitTransportReal.mqh', 'include/ExposureReaderReal.mqh']), 'EA includes'
assert 'daily_on=InpDailyHistoryBridge' in ea
daily = fd[fd.index('virtual bool Daily('):]
assert 'EO_OffsetSeconds(mc.daily_offset_seconds,daily_offset)' in daily, 'offset validation'
assert daily.index('EO_OffsetSeconds(mc.daily_offset_seconds,daily_offset)') < daily.index('hcfg.server_offset_seconds=daily_offset'), 'offset validation'
assert 'CDbsRealPort port(mc.daily_magic,daily_offset,' in daily, 'validated store offset'
PYEOF
python3 -I "$NEG/o3.py" $EA $FEED && echo "  PASS no direct order / CAPTURE / file write, the feed has no real transport, FAKE by default, real transports only behind the phrase and confirmations, UNSET defaults, tester refused, chart symbol, LOAD only" || { echo "  FAIL"; FAIL=1; }

echo "=== O4: the test never includes a real transport or reads the terminal ==="
grep -nE 'EntryTransportReal|ExitTransportReal|OrderSend|SymbolInfo|OrderCalcProfit|TimeCurrent|FileOpen|CopyRates|AccountInfo|DBS_' $TS >/dev/null && { echo "  FAIL the test touches the real side"; FAIL=1; } || echo "  PASS the test uses the fake transport, the fake store and a scripted market only"

echo "=== O5: protected modules are untouched since $BASE ==="
for p in src/include/EntryTransport.mqh src/include/EntryTransportFake.mqh src/include/EntryExecutor.mqh \
         src/include/TradePlanning.mqh src/include/BrokerLossCheck.mqh src/include/DailyBridge.mqh src/include/DailyLimits.mqh src/include/DailyPreviewGate.mqh src/include/DailyBalanceStore.mqh \
         src/include/M15Confirmation.mqh src/include/M15Timeline.mqh src/include/H4M15Bridge.mqh src/include/H4TouchContext.mqh src/include/TimeframeWatcher.mqh src/include/NewsSpreadFilters.mqh \
         src/include/SessionPolicy.mqh src/include/SymbolSnapshot.mqh src/include/ExitExecutor.mqh src/include/ExitTickDriver.mqh src/include/ExitStateFile.mqh src/XauUsdTradePreview.mq5 \
         src/XauUsdM15Observer.mq5 src/XauUsdT011DemoOpenPosition.mq5 src/XauUsdT011ExitManager.mq5; do
  if git cat-file -e $BASE:$p 2>/dev/null; then
    if git diff --quiet $BASE -- $p; then echo "  PASS $p identical to $BASE"; else echo "  FAIL $p differs from $BASE"; FAIL=1; fi
  else echo "  SKIP $p (base not available)"; fi
done

echo "=== O6: negative controls ==="
expect_assert() {   # $1 script, $2 file(s), $3 message, $4 text the assertion message must contain
  if err=$(python3 -I "$1" $2 2>&1 >/dev/null); then echo "  FAIL $3 NOT detected"; FAIL=1;
  elif echo "$err" | grep -q "AssertionError.*$4"; then echo "  PASS $3 is detected";
  else echo "  FAIL $3: the control broke for another reason: $(echo "$err" | tail -1)"; FAIL=1; fi
}
mut() {   # $1 name, $2 source, $3 sed expression
  cp "$2" "$NEG/$1"; sed -i "$3" "$NEG/$1"; cmp -s "$2" "$NEG/$1" && { echo "  FAIL control $1 changed nothing"; FAIL=1; }
}
mut A.mqh $CORE 's/      baseline=MathMax(baseline,(long)cut);/      baseline=(long)cut;/'
expect_assert "$NEG/o2.py" "$NEG/A.mqh" "a baseline that can move backwards" "missing step: baseline=MathMax"
mut B.mqh $CORE 's/   if(halted!="") {EO_Set(out,"HALTED",halted); return;}/   if(false) {}/'
expect_assert "$NEG/o2.py" "$NEG/B.mqh" "no halt after an uncertain outcome" "missing step: if(halted"
mut C.mqh $CORE 's/if(!(tick>0.0))/if(false)/'
expect_assert "$NEG/o2.py" "$NEG/C.mqh" "a missing probe that does not block" "tick value"
mut D.mqh $CORE 's/      chk.snap_digest=digest;/      chk.snap_digest="";/'
expect_assert "$NEG/o2.py" "$NEG/D.mqh" "evidence not bound to the plan digest" "plan digest binding"
mut E.mqh $CORE 's/      chk.loss_time=now;/      chk.loss_time=0;/'
expect_assert "$NEG/o2.py" "$NEG/E.mqh" "evidence without the shared instant" "shared instant"
mut F.mqh $CORE 's/      EN_RuntimeInit(rt);/      \/\/ none/'
expect_assert "$NEG/o2.py" "$NEG/F.mqh" "a runtime reused across signals" "missing step: \|fresh runtime"
mut G.mqh $CORE 's/      SPB_Build(sel,m,st,f,broken,cut,r2);   /      OrderSend(); SPB_Build(sel,m,st,f,broken,cut,r2);   /'
expect_assert "$NEG/o2.py" "$NEG/G.mqh" "an order call in the core" "OrderSend"
mut H.mqh $CORE 's/         out.label=EO_FAKE_LABEL;/         out.label="";/'
expect_assert "$NEG/o2.py" "$NEG/H.mqh" "a virtual request without the label" "label\|request without label"
mut I.mqh $EA 's/#include "include\/EntryTransportFake.mqh"/#include "include\/EntryTransportFake.mqh"\n#include "include\/EntryExecutorExtra.mqh"/'
expect_assert "$NEG/o3.py" "$NEG/I.mqh $FEED" "an unexpected include in the EA" "EA includes"
mut J.mqh $EA 's/^input long InpEaMagic=0; /input bool InpRealTransport=false; \/\/ x\ninput long InpEaMagic=0; /'
expect_assert "$NEG/o3.py" "$NEG/J.mqh $FEED" "a transport selector input" "transport selector input"
mut K.mqh $EA 's/^input double InpRiskBudget=-1; /input double InpRiskBudget=100; /'
expect_assert "$NEG/o3.py" "$NEG/K.mqh $FEED" "a policy input with a default value" "default not UNSET"
mut SM5.mqh $EA 's/InpManagementTransport!=EOI_MTR_READ_ONLY || InpManagementConfirmAutoSend || //'
expect_assert "$NEG/o3.py" "$NEG/SM5.mqh $FEED" "a simulation policy allowed with a real management transport" "SIMULATION ONLY is allowed only"
mut DG1.mqh $FEED 's/      dg_have=true; dg_state=e.has_state;/      H3Evaluate(hbars,n,params,e,tracks,events); dg_have=true; dg_state=e.has_state;/'
expect_assert "$NEG/o3.py" "$EA $NEG/DG1.mqh" "a second evaluation for the diagnostics" "diagnostics"
mut DG3.mqh $FEED 's/      DBS_ForBridge(stored,balance);/      balance.known=true; balance.amount=10000.0; balance.day=facts.day_key;/'
expect_assert "$NEG/o3.py" "$EA $NEG/DG3.mqh" "a balance that does not come from the store" "daily glue"
mut DG4.mqh $FEED 's/CDbsRealPort port(mc.daily_magic,daily_offset,/CDbsRealPort port(mc.daily_magic,0,/'
expect_assert "$NEG/o3.py" "$EA $NEG/DG4.mqh" "a different offset for the store port" "one offset"
mut DG2.mqh $EA 's/   text+=" | "+g_feed.Diag();/   text+="";/'
expect_assert "$NEG/o3.py" "$NEG/DG2.mqh $FEED" "a status without the diagnostics" "diagnostic suffix"
mut L.mqh $FEED 's/      DBS_Load(port,stored);/      DBS_Load(port,stored); DBS_Capture(port,stored);/'
expect_assert "$NEG/o3.py" "$EA $NEG/L.mqh" "a CAPTURE in the feed" "DBS_Capture\|LOAD only"
mut M.mqh $EA 's/   virtual void Send(const SEnRequest \&req,SEnSendResult \&res)/   virtual void Send(const SEnRequest \&req,SEnSendResult \&res) {OrderSend(); }\n   virtual void SendUnused(const SEnRequest \&req,SEnSendResult \&res)/'
expect_assert "$NEG/o3.py" "$NEG/M.mqh $FEED" "an OrderSend in the EA" "OrderSend"
mut N.mqh $CORE 's/{Defect(); EO_Set(out,"MARKET_NOT_READY","SYMBOL_UNREADABLE_OR_NOT_TRADABLE")/{EO_Set(out,"MARKET_NOT_READY","SYMBOL_UNREADABLE_OR_NOT_TRADABLE")/'
expect_assert "$NEG/o2.py" "$NEG/N.mqh" "symbol recovery without rebase" "symbol recovery baseline"
mut O.mqh $CORE 's/{Defect(); EO_Set(out,"MARKET_NOT_READY","QUOTE_NOT_READY_OR_STALE")/{EO_Set(out,"MARKET_NOT_READY","QUOTE_NOT_READY_OR_STALE")/'
expect_assert "$NEG/o2.py" "$NEG/O.mqh" "quote recovery without rebase" "quote recovery baseline"
mut P.mqh $CORE 's/!M4ContextEqual(st.context,previous_context)/k!=key/'
expect_assert "$NEG/o2.py" "$NEG/P.mqh" "context comparison using IDs only" "missing step"
mut Q.mqh $FEED 's/if(!EO_OffsetSeconds(mc.daily_offset_seconds,daily_offset))/if(false)/'
expect_assert "$NEG/o3.py" "$EA $NEG/Q.mqh" "offset narrowed without validation" "offset\|substring not found"

mut R1.mqh $EA 's/^input ENUM_EO_ENTRY_TRANSPORT InpEntryTransport=EOI_ETR_FAKE;/input ENUM_EO_ENTRY_TRANSPORT InpEntryTransport=EOI_ETR_BROKER_DEMO;/'
expect_assert "$NEG/o3.py" "$NEG/R1.mqh $FEED" "real entry orders on by default" "default not off"
mut R2.mqh $EA 's/InpEntryAuthorisation!=EN_AUTH_PHRASE || //'
expect_assert "$NEG/o3.py" "$NEG/R2.mqh $FEED" "the real entry transport without the phrase" "needs the phrase"
mut R3.mqh $EA 's/(!InpManagementConfirmAutoSend || !InpManagementRegistration)/(!InpManagementRegistration)/'
expect_assert "$NEG/o3.py" "$NEG/R3.mqh $FEED" "real closing requests without the confirmation" "need the confirmation"
mut R4.mqh $EA 's/g_registrar.provenance=(g_real_entry ? MH_PROV_BROKER : MH_PROV_SYNTHETIC);/g_registrar.provenance=MH_PROV_BROKER;/'
expect_assert "$NEG/o3.py" "$NEG/R4.mqh $FEED" "a FAKE entry transport declared as a broker" "provenance follows"
mut R5.mqh $FEED 's/      DBS_Load(port,stored);/      DBS_Load(port,stored); CEnRealTransport x;/'
expect_assert "$NEG/o3.py" "$EA $NEG/R5.mqh" "the real transport in the feed" "feed: CEnRealTransport"

mut S1.mqh $CORE 's/         if(!(bal.read_ok \&\& (bal.demo || sim) \&\& TG_Finite(bal.amount)/         if(!(bal.read_ok \&\& TG_Finite(bal.amount)/'
expect_assert "$NEG/o2.py" "$NEG/S1.mqh" "a balance that is not demo-checked" "read ok, demo"
mut S2.mqh $CORE 's/      chk.risk_budget=budget;/      chk.risk_budget=c.risk_budget;/'
expect_assert "$NEG/o2.py" "$NEG/S2.mqh" "a loss check against another budget than the sized one" "one budget"
mut S3.mqh $CORE 's/#define EO_RISK_PCT_DEMO 1.0/#define EO_RISK_PCT_DEMO 2.0/'
expect_assert "$NEG/o2.py" "$NEG/S3.mqh" "a policy that is not one percent" "exactly 1%"
mut S4.mqh $CORE 's/ \&\& now-bal.time<=c.max_quote_age//'
expect_assert "$NEG/o2.py" "$NEG/S4.mqh" "a stale balance accepted" "fresh"
mut S5.mqh $EA 's/^input ENUM_EO_RISK_SOURCE InpRiskSource=EOI_RISK_AMOUNT;/input ENUM_EO_RISK_SOURCE InpRiskSource=EOI_RISK_DEMO_1PCT_CURRENT_BALANCE;/'
expect_assert "$NEG/o3.py" "$NEG/S5.mqh $FEED" "the demo balance policy on by default" "default not UNSET"

mut S6.mqh $EA 's/   g_feed.Poll(feed_ok);/   if(!g_feed.Poll(feed_ok)) return;/'
expect_assert "$NEG/o3.py" "$NEG/S6.mqh $FEED" "a stale quote waiting for the next closed bar" "timer must recheck"

mut F1.mqh $CORE 's/st.context.ready \&\& st.context.reliable \&\& st.context.selected \&\& (st.context.direction==1/st.context.reliable \&\& (st.context.direction==1/'
expect_assert "$NEG/o2.py" "$NEG/F1.mqh" "a direction taken from an unready context" "known"
mut F2.mqh $CORE 's/      EO_FactsInit(facts);\n      if(!feed_ok)/      if(!feed_ok)/;s/^      EO_FactsInit(facts);$/      \/\/ none/'
expect_assert "$NEG/o2.py" "$NEG/F2.mqh" "facts that survive a defect" "cleared at every step"

mut S7.mqh $CORE 's/         now=mk.Now();/         now=before_balance;/'
expect_assert "$NEG/o2.py" "$NEG/S7.mqh" "a balance compared to the earlier clock" "balance clock must be sampled"

mut SM1.mqh $CORE 's/      if(sim \&\& tr.IsReal())/      if(false)/'
expect_assert "$NEG/o2.py" "$NEG/SM1.mqh" "the simulation policy combined with a real transport" "BEFORE the balance is read"
mut SM2.mqh $CORE 's/(bal.demo || sim) \&\& TG_Finite/true \&\& TG_Finite/'
expect_assert "$NEG/o2.py" "$NEG/SM2.mqh" "a classification check that is dropped for every policy" "read ok, demo"
mut SM3.mqh $CORE 's/ *out.risk_label=label;//'
expect_assert "$NEG/o2.py" "$NEG/SM3.mqh" "a refusal without the SIMULATION ONLY label" "label and the raw account mode"
mut SM4.mqh $CORE 's/EO_RISK_PCT_DEMO\/100.0/EO_RISK_PCT_DEMO\/50.0/'
expect_assert "$NEG/o2.py" "$NEG/SM4.mqh" "a budget that is not one percent" "one budget sizes the plan"

[ $FAIL -eq 0 ] && echo "ENTRY ORCHESTRATOR STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED)" || echo "ENTRY ORCHESTRATOR STATIC CHECKS: FAILURES"
exit $FAIL


