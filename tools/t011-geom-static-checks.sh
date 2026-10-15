#!/bin/bash
# Static checks for the T011 R_GEOM wiring (Part 14): codec VERSION 3 basis, geometry derivation in the executor, the tick driver, the tick-path EA and the registration script.
# NOT a compiler, NOT an MT5 run; the real transport is never executed.  Usage: bash tools/t011-geom-static-checks.sh (from anywhere; it cd's to the repo root)
set -u
cd "$(dirname "$0")/.."
FAIL=0
NEG=$(mktemp -d); trap 'rm -rf "$NEG"' EXIT
EXE=src/include/ExitExecutor.mqh
DRV=src/include/ExitTickDriver.mqh
COD=src/include/ExitStateCodec.mqh
FLW=src/include/ExitRestartFlow.mqh
EA=src/XauUsdT011ExitManager.mq5
REG=src/XauUsdT011ExitRegister.mq5
GT=src/tests/T011_GeomTest.mq5
DT=src/tests/T011_DriverTest.mq5
FILES="$EXE $DRV $COD $FLW $EA $REG $GT $DT src/include/ExitTransport.mqh src/include/ExitTransportFake.mqh src/include/ExitTransportReal.mqh"
NEWFILES="$DRV $EA $REG $GT $DT src/presets/XauUsdT011ExitManager.set src/presets/XauUsdT011ExitRegister.set tests/t011_geom_fixtures.py tests/test_t011_geom.py tests/t011_driver_reference.py tests/test_t011_driver.py tools/t011-geom-static-checks.sh"

echo "=== S1: files exist ==="
for f in $NEWFILES; do [ -s "$f" ] && echo "  PASS $f exists" || { echo "  FAIL $f missing or empty"; FAIL=1; }; done

echo "=== S2: no trading call outside the transports and the open-position script; the real transport only where intended; no deletion / registration at init ==="
python3 -I - $EXE $DRV $EA $REG $GT $DT <<'PYEOF' && echo "  PASS no OrderSend / order structure in the driver, the EA, the register script or the tests; real header only in the harness, the EA and the register script" || { echo "  FAIL"; FAIL=1; }
import glob, re, sys
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
exe, drv, ea, reg, gt, dt = [strip(open(f, encoding='ascii').read()) for f in sys.argv[1:7]]
for name, code in (('executor', exe), ('driver', drv), ('ea', ea), ('register', reg), ('geom test', gt), ('driver test', dt)):
    assert not re.search(r'\bOrderSend\w*\s*\(|OrderCheck|CTrade|PositionClose|PositionOpen|OrderDelete|OrderModify|MqlTradeRequest', code), (name, 'trading call')
    assert not re.search(r'\b(iHigh|iLow|iClose|iOpen|CopyRates|CopyHigh|CopyLow|CopyClose|OnChartEvent)\b', code), (name, 'price-series / signal code')
for name, code in (('executor', exe), ('driver', drv), ('ea', ea), ('register', reg)):
    assert not re.search(r'FileDelete|GlobalVariableDel|GlobalVariablesDeleteAll|FileMove', code), (name, 'deletes something')
for name, code in (('driver', drv), ('ea', ea), ('register', reg)):
    assert not re.search(r'\bFile\w+\s*\(', code), (name, 'direct file access (records go through ExitStateFile only)')
holders = sorted(f for f in glob.glob('src/**/*.mq[h5]', recursive=True) if re.search(r'#include\s+"[^"]*ExitTransportReal\.mqh"', open(f, encoding='ascii').read()))
assert holders == ['src/XauUsdEntryOrchestrator.mq5', 'src/XauUsdT011DemoHarness.mq5', 'src/XauUsdT011ExitManager.mq5', 'src/XauUsdT011ExitRegister.mq5', 'src/tests/T011_ExecutorRealCompile.mq5'], holders
assert 'ExitTransportReal' not in drv and 'ExitTransportReal' not in gt and 'ExitTransportReal' not in dt
# registration is never done by OnInit / OnTick / OnTimer / the driver's init and tick
assert 'EX_Register' not in ea and 'ETD_Register' not in ea
init = drv[drv.index('bool ETD_Init('):drv.index('bool ETD_Tick(')]
tick = drv[drv.index('bool ETD_Tick('):drv.index('bool ETD_Timer(')]
for body in (init, tick):
    assert 'EX_Register' not in body and 'ESF_InitFresh' not in body and 'ESF_WriteAll' not in body and 'ESF_Save' not in body
assert reg.count('ETD_Register(') == 1 and 'EX_Process' not in reg and 'ETD_Tick' not in reg
assert ea.count('ETD_Tick(') == 1 and ea.count('ETD_Init(') == 1 and ea.count('ETD_Timer(') == 1 and 'EX_Process' not in ea
PYEOF

echo "=== S3: disabled by default, UNSET blocks, one lock, recovery before activation, the level derived only by TG_Compute ==="
python3 -I - $EXE $DRV $EA $REG $COD $FLW <<'PYEOF' && echo "  PASS defaults, lock and recovery order, geometry in one place, codec / flow carry the basis" || { echo "  FAIL"; FAIL=1; }
import re, sys
strip = lambda t: re.sub(r'//[^\n]*', '', re.sub(r'(?s)/\*.*?\*/', '', t))
exe, drv, ea, reg, cod, flw = [strip(open(f, encoding='ascii').read()) for f in sys.argv[1:7]]
for need in ('input bool InpEnabled=false;', 'input string InpAuthorisation="";', 'input bool InpConfirmAutoSend=false;', 'input ENUM_ETD_RPOLICY InpRPolicy=ETD_RPOL_UNSET;', 'input long InpEaMagic=0;',
             'input long InpPositionId=0;', 'input string InpSymbol="";', 'input ENUM_ETD_DIRECTION InpDirection=ETD_DIR_UNSET;', 'input ENUM_EX_FILLING InpFilling=EX_FILL_UNSET;', 'input long InpDeviation=-1;',
             'input ENUM_EX_FILTER_POLICY InpFilterPolicy=EX_POL_UNSET;'):
    assert need in ea, need
for need in ('input bool InpEnabled=false;', 'input string InpAuthorisation="";', 'input ENUM_ETD_RPOLICY InpRPolicy=ETD_RPOL_UNSET;', 'input long InpEaMagic=0;', 'input long InpPositionId=0;',
             'input ENUM_ETD_DIRECTION InpDirection=ETD_DIR_UNSET;'):
    assert need in reg, need
assert 'ETD_RPOL_R_GEOM=2' in drv and 'TYPED' not in drv[drv.index('enum ENUM_ETD_RPOLICY'):drv.index('struct SEtdState')], 'the typed diagnostic policy must not be selectable'
assert '(int)InpDirection!=(int)ETD_DIR_BUY && (int)InpDirection!=(int)ETD_DIR_SELL' in ea and '(int)InpDirection!=(int)ETD_DIR_BUY && (int)InpDirection!=(int)ETD_DIR_SELL' in reg, 'direction must be a known BUY / SELL'
oi = ea[ea.index('int OnInit()'):ea.index('void OnDeinit(')]
assert oi.index('!InpEnabled') < oi.index('EX_AUTH_PHRASE') < oi.index('InpConfirmAutoSend') < oi.index('ETD_Init(') < oi.index('EventSetTimer(')
assert 'ETD_Tick(' in ea[ea.index('void OnTick()'):ea.index('void OnTimer()')] and 'ETD_Timer(' in ea[ea.index('void OnTimer()'):]
# the driver: one lock key, recovery before arming, no EX_Process for a record that is not IDLE
assert drv.count('EL_Key(id.login,id.position_id)') == 4
init = drv[drv.index('bool ETD_Init('):drv.index('bool ETD_Tick(')]
tick = drv[drv.index('bool ETD_Tick('):drv.index('bool ETD_Timer(')]
assert init.index('!cfg.enabled') < init.index('EL_Acquire(') < init.index('EX_Reconcile(') < init.index('s.armed=true;')
assert tick.index('s.direction==1 ?') < tick.index('EL_Acquire(') < tick.index('ESF_Load(') < tick.index('ESC_USABLE_IDLE') < tick.index('EX_Process(')
assert 'EX_Process' not in init and tick.count('EX_Process(') == 1
# the executor: the level is derived in ONE place, with no 2R arithmetic of its own
assert exe.count('TG_Compute(') == 1 and 'bool EX_Geometry(' in exe
assert not re.search(r'2\.0\s*\*|\*\s*2\.0|\b2\s*\*|\*\s*2\b', exe[exe.index('bool EX_Geometry('):exe.index('bool EX_Process(')].replace('sym.tick_size/2.0', '')), 'no 2R arithmetic in the executor'
pr = exe[exe.index('bool EX_Process('):exe.index('bool EX_Register(')]
assert pr.index('EX_RPOL_UNSET') < pr.index('tr.ReadAccount(') and pr.index('EX_Geometry(') < pr.index('EA_OnQuote(') < pr.index('tr.PreCheck(')
assert 'sl_initial' in pr and 'pos.sl' not in pr, 'the live SL is never used by the tick path'
rg = exe[exe.index('bool EX_Register('):exe.index('bool EX_Reconcile(')]
assert 'pos.sl' in rg and 'pos.price_open' in rg and rg.index('INITIAL_SL_NOT_PROVEN') < rg.index('EX_Geometry(') < rg.index('BASE_CHANGED_BY_NORMALIZATION') < rg.index('EX_Save(')
assert 'tr.Send(' not in rg
for need in ('#define ESC_VERSION 3', '"PLAN_RPOL"', '"PLAN_E_SRC"', '"PLAN_S_SRC"', '"PLAN_E_OUT"', '"PLAN_S_OUT"', 'string v[34];', 'v[33]'):
    assert need in cod, need
assert not re.search(r'plan_r\b|"PLAN_R="|"R="|plan_risk', cod), 'R must not be stored'
for need in ('rec.plan_rpol=o.plan_rpol;', 'rec.plan_e_src=o.plan_e_src;', 'rec.plan_s_src=o.plan_s_src;', 'rec.plan_e_out=o.plan_e_out;', 'rec.plan_s_out=o.plan_s_out;'):
    assert need in flw, need
assert exe.count('rec.plan_rpol=o.plan_rpol;') == 1 and exe.count('mapped.plan_rpol=o.plan_rpol;') == 1
PYEOF

echo "=== S4: balance, format strings, includes, ASCII, reserved words ==="
python3 tools/t001-check-balance.py $FILES || FAIL=1
python3 - $FILES <<'PYEOF' || FAIL=1
import importlib.util, sys
spec = importlib.util.spec_from_file_location('t001fmt', 'tools/t001-check-format-strings.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.FILES = sys.argv[1:]
sys.exit(mod.main())
PYEOF
for f in $FILES; do
  d=$(dirname "$f"); bad=0
  for inc in $(grep -oE '#include "[^"]+"' "$f" | sed 's/#include "//;s/"//'); do
    [ -f "$d/$inc" ] || { echo "  FAIL $f: missing include $d/$inc"; bad=1; FAIL=1; }
  done
  [ $bad -eq 0 ] && echo "  PASS $f: every include resolves"
done
for f in $NEWFILES $FILES; do n=$(LC_ALL=C grep -c '[^ -~	]' "$f" || true); [ "$n" = "0" ] || { echo "  FAIL $f: $n line(s) with non-ASCII bytes"; FAIL=1; }; done
echo "  INFO ASCII-only checked"
RESERVED='final|override|sealed|explicit|delete|new|virtual|template|typename|operator|this|static|class|struct|union|enum|public|private|protected|extern|input|sinput|void|auto|namespace|using|typedef|interface|implements'
for f in $FILES; do
  if grep -nE "\b(bool|int|long|double|string|ulong|uint|datetime|color|char|short|uchar|ushort|float)\s+($RESERVED)\b\s*(=|;|,|\))" "$f" >/dev/null; then echo "  FAIL $f reserved word as a variable"; FAIL=1; else echo "  PASS $f: no variable is named with a reserved MQL5 word"; fi
done

echo "=== S5: negative controls ==="
cp $EA "$NEG/A.mq5"; sed -i 's/input bool InpEnabled=false;/input bool InpEnabled=true;/' "$NEG/A.mq5"
grep -qF 'input bool InpEnabled=false;' "$NEG/A.mq5" && { echo "  FAIL EA default control"; FAIL=1; } || echo "  PASS an EA enabled by default loses the pin"
cp $EA "$NEG/B.mq5"; sed -i 's/input ENUM_ETD_RPOLICY InpRPolicy=ETD_RPOL_UNSET;/input ENUM_ETD_RPOLICY InpRPolicy=ETD_RPOL_R_GEOM;/' "$NEG/B.mq5"
grep -qF 'InpRPolicy=ETD_RPOL_UNSET;' "$NEG/B.mq5" && { echo "  FAIL policy default control"; FAIL=1; } || echo "  PASS a default R policy other than UNSET loses the pin"
cp $EA "$NEG/C.mq5"; sed -i 's/   bool armed=ETD_Init(/   EX_Register(g_cfg,GetPointer(g_transport),g_rt,g_name,g_id,SExQuote(),SExResult()); bool armed=ETD_Init(/' "$NEG/C.mq5"
python3 -I - "$NEG/C.mq5" <<'PYEOF' && { echo "  FAIL registration at init not detected"; FAIL=1; } || echo "  PASS a registration call in the EA is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
sys.exit(1 if ('EX_Register' in code or 'ETD_Register' in code) else 0)
PYEOF
cp $DRV "$NEG/D.mqh"; python3 - "$NEG/D.mqh" <<'PYEOF'
import sys
t = open(sys.argv[1]).read()
n = t.count('   ESF_Load(name,id,st,o);\n   if(o.generation==0 || o.verdict!=ESC_USABLE_IDLE)')
assert n == 1, 'the control could not be built'
t = t.replace('   ESF_Load(name,id,st,o);\n   if(o.generation==0 || o.verdict!=ESC_USABLE_IDLE)', '   if(o.generation==0 || o.verdict!=ESC_USABLE_IDLE)', 1)
open(sys.argv[1], 'w').write(t)
PYEOF
python3 -I - "$NEG/D.mqh" <<'PYEOF' && { echo "  FAIL missing record re-load not detected"; FAIL=1; } || echo "  PASS a tick that does not re-load the record before EX_Process is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
tick = code[code.index('bool ETD_Tick('):code.index('bool ETD_Timer(')]
i, j = tick.find('ESF_Load('), tick.find('EX_Process(')
sys.exit(0 if (i >= 0 and j >= 0 and i < j) else 1)
PYEOF
cp $DRV "$NEG/E.mqh"; sed -i 's/   if(!EL_Acquire(key,held,why))/   if(false)/' "$NEG/E.mqh"
python3 -I - "$NEG/E.mqh" <<'PYEOF' && { echo "  FAIL missing lock not detected"; FAIL=1; } || echo "  PASS a driver without its lock is detected"
import re, sys
code = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
sys.exit(0 if code.count('EL_Acquire(') >= 4 else 1)
PYEOF
cp $EXE "$NEG/F.mqh"; sed -i 's/^bool EX_Geometry(/double zz2r(double e,double r){return(e+2.0*r);}\nbool EX_Geometry(/' "$NEG/F.mqh"
python3 -I - "$NEG/F.mqh" <<'PYEOF' && { echo "  FAIL 2R arithmetic not detected"; FAIL=1; } || echo "  PASS a copied 2R formula in the executor is detected"
import re, sys
exe = re.sub(r'//[^\n]*', '', open(sys.argv[1], encoding='ascii').read())
pre = exe[:exe.index('bool EX_Geometry(')]
sys.exit(1 if re.search(r'2\.0\s*\*|\*\s*2\.0|\b2\s*\*|\*\s*2\b', pre[pre.index('enum ENUM_EX_R_POLICY'):].replace('/2.0', '')) else 0)
PYEOF
cp $COD "$NEG/G.mqh"; sed -i 's/#define ESC_VERSION 3/#define ESC_VERSION 2/' "$NEG/G.mqh"
grep -qF '#define ESC_VERSION 3' "$NEG/G.mqh" && { echo "  FAIL version control"; FAIL=1; } || echo "  PASS a codec that is not VERSION 3 loses the pin"
cp $DRV "$NEG/H.mqh"; echo "void x(){" >> "$NEG/H.mqh"
python3 tools/t001-check-balance.py "$NEG/H.mqh" >/dev/null 2>&1 && { echo "  FAIL unbalanced brace"; FAIL=1; } || echo "  PASS unbalanced brace detected"

echo
[ $FAIL -eq 0 ] && echo "T011 GEOM STATIC CHECKS: ALL PASS (static only; MetaEditor compile and MT5 run UNVERIFIED; the real transport is never executed)" || echo "T011 GEOM STATIC CHECKS: FAILURES"
exit $FAIL
