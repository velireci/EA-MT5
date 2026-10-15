// T011 R_GEOM executor test (FAKE transport only; Part 14): EX_Register / EX_Process over ExitExecutor.mqh with CFakeTransport, the real ExitStateFile (sandbox file
// VELO_T011_GEOMTEST_A.state, deleted before and after) and TradeGeometry (TG_Compute). Mirrors tests/test_t011_geom.py; the rows below are the generated scenario table of
// tests/t011_geom_fixtures.py (equality is tested). The 2R level comes ONLY from the stored basis (E, S): never from the live SL, never from the quote's level input.
// NEVER includes the real transport; no terminal read of positions, no order, no trade. NOT YET COMPILED OR RUN (UNVERIFIED).
#property strict
#property script_show_inputs
#property version "1.00"
#include "../include/ExitExecutor.mqh"
#include "../include/ExitTransportFake.mqh"
int g_pass=0,g_fail=0;
void Check(const bool ok,const string message)
  {
   if(ok) {g_pass++; Print("PASS ",message);}
   else {g_fail++; Print("FAIL ",message);}
  }
#define FN "VELO_T011_GEOMTEST_A.state"
#define S_MISSING 0
#define S_GEOM 1
#define S_TYPED 2
#define S_NOPLAN 3
#define S_OLD_V2 4
#define S_TAMPER_LEVEL 5
#define S_PEND_MAP 6
// BEGIN GENERATED FIXTURES (tests/t011_geom_fixtures.py emit_mql)
#define NROWS 55
#define MAXSET 4
string R_NAME[]={"BUY_REGISTERS_FROM_THE_OPEN_PRICE_AND_THE_ASSERTED_SL","SELL_REGISTERS_FROM_THE_OPEN_PRICE_AND_THE_ASSERTED_SL","BUY_POLICY_UNSET_BLOCKS","BUY_POLICY_UNKNOWN_BLOCKS","BUY_ASSERTED_SL_MISSING_BLOCKS","BUY_LIVE_SL_MOVED_TO_BREAK_EVEN_IS_NOT_THE_INITIAL_SL","BUY_LIVE_SL_MOVED_CLOSER_IS_NOT_THE_INITIAL_SL","BUY_LIVE_SL_ABSENT_IS_NOT_THE_INITIAL_SL","SELL_SELL_LIVE_SL_MOVED","BUY_OPEN_PRICE_UNAVAILABLE","BUY_OPEN_PRICE_OFF_THE_TICK_GRID","BUY_ASSERTED_SL_OFF_THE_TICK_GRID","BUY_BUY_STOP_ABOVE_ENTRY_GEOMETRY_REFUSED","SELL_SELL_STOP_BELOW_ENTRY_GEOMETRY_REFUSED","BUY_ZERO_RISK_GEOMETRY_REFUSED","BUY_TICK_DIGITS_INCOMPATIBLE_GEOMETRY_REFUSED","BUY_TP_EQUALS_2R_BLOCKS","BUY_TP_BEFORE_2R_BLOCKS","SELL_SELL_TP_BEFORE_2R_BLOCKS","BUY_FOREIGN_MAGIC_IS_NEVER_ADOPTED","BUY_POSITION_NOT_FOUND","BUY_POSITION_VOLUME_DIFFERS_FROM_THE_PLAN","BUY_SPLIT_NOT_REALISABLE","BUY_DISABLED_BLOCKS","BUY_EXISTING_RECORD_IS_NEVER_OVERWRITTEN","BUY_EXISTING_OLD_V2_FILE_IS_NEVER_TOUCHED","BUY_SENDS_ONCE_AT_THE_LEVEL","SELL_SENDS_ONCE_AT_THE_LEVEL","BUY_BID_JUST_BELOW_THE_LEVEL_NO_REQUEST","BUY_ONLY_THE_ASK_AT_THE_LEVEL_IS_NOT_ENOUGH_FOR_A_BUY","SELL_ONLY_THE_BID_AT_THE_LEVEL_IS_NOT_ENOUGH_FOR_A_SELL","SELL_ASK_JUST_ABOVE_THE_LEVEL_SELL_NO_REQUEST","BUY_LIVE_SL_AT_BREAK_EVEN_DOES_NOT_CHANGE_THE_LEVEL","BUY_LIVE_SL_MOVED_CLOSER_DOES_NOT_CHANGE_THE_LEVEL","SELL_SELL_LIVE_SL_AT_BREAK_EVEN_DOES_NOT_CHANGE_THE_LEVEL","BUY_LIVE_SL_ABSENT_DOES_NOT_CHANGE_THE_LEVEL","BUY_THE_QUOTE_LEVEL_INPUT_IS_IGNORED","BUY_THE_QUOTE_LEVEL_INPUT_CANNOT_ARM_EARLIER","BUY_CONFIGURED_INITIAL_SL_DIFFERS_FROM_THE_STORED_ONE","BUY_CONFIGURED_INITIAL_SL_MISSING","BUY_POLICY_UNSET_BLOCKS","BUY_TYPED_POLICY_AGAINST_A_GEOMETRY_RECORD","BUY_GEOMETRY_POLICY_AGAINST_A_TYPED_RECORD","BUY_STORED_LEVEL_DIFFERS_FROM_THE_ONE_DERIVED_FROM_THE_BASIS","SELL_SELL_STORED_LEVEL_DIFFERS_FROM_THE_ONE_DERIVED_FROM_THE_BASIS","BUY_CONFIGURED_TP_CHANGED","BUY_GEOMETRY_REFUSED_WHEN_THE_SYMBOL_DIGITS_CHANGED","BUY_RECORD_WITHOUT_A_PLAN_IS_NEVER_FILLED_IN","BUY_MISSING_FILE_NEVER_STARTS_FROM_SCRATCH","BUY_OLD_VERSION_2_FILE_IS_REFUSED_AND_LEFT_UNCHANGED","BUY_RECORD_THAT_NEEDS_RECONCILIATION_IS_NOT_PROCESSED","BUY_FOREIGN_MAGIC_BLOCKS_BEFORE_ANY_SEND","BUY_POSITION_VOLUME_CHANGED_BLOCKS","BUY_LATCHED_RUNTIME_BLOCKS","BUY_DISABLED_BLOCKS"};
int R_OP[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1};
int R_START[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,4,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2,5,5,1,1,3,0,4,6,1,1,1,1};
int R_SIDE[]={1,-1,1,1,1,1,1,1,-1,1,1,1,1,-1,1,1,1,1,-1,1,1,1,1,1,1,1,1,-1,1,1,-1,-1,1,1,-1,1,1,1,1,1,1,1,1,1,-1,1,1,1,1,1,1,1,1,1,1};
int S_N[]={0,0,1,1,1,1,1,1,1,1,1,2,2,2,2,1,1,1,1,1,1,1,2,1,0,0,0,0,2,2,2,2,1,3,1,1,1,3,1,1,1,2,0,0,0,1,1,0,0,0,0,1,1,1,1};
int S_KEY[]={-1,-1,-1,-1,-1,-1,-1,-1,0,-1,-1,-1,0,-1,-1,-1,1,-1,-1,-1,6,-1,-1,-1,6,-1,-1,-1,6,-1,-1,-1,6,-1,-1,-1,5,-1,-1,-1,5,-1,-1,-1,2,6,-1,-1,2,6,-1,-1,2,6,-1,-1,2,6,-1,-1,10,-1,-1,-1,3,-1,-1,-1,3,-1,-1,-1,3,-1,-1,-1,7,-1,-1,-1,9,-1,-1,-1,8,-1,-1,-1,8,14,-1,-1,4,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,12,13,-1,-1,12,13,-1,-1,12,13,-1,-1,12,13,-1,-1,6,-1,-1,-1,6,12,13,-1,6,-1,-1,-1,6,-1,-1,-1,11,-1,-1,-1,11,12,13,-1,2,-1,-1,-1,1,-1,-1,-1,0,-1,-1,-1,0,11,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,3,-1,-1,-1,10,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,7,-1,-1,-1,8,-1,-1,-1,16,-1,-1,-1,4,-1,-1,-1};
double S_VAL[]={0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,9.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2000.0,0.0,0.0,0.0,1999.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2000.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2000.004,0.0,0.0,0.0,1995.004,1995.004,0.0,0.0,2005.0,2005.0,0.0,0.0,1995.0,1995.0,0.0,0.0,2000.0,2000.0,0.0,0.0,1.0,0.0,0.0,0.0,2010.0,0.0,0.0,0.0,2005.0,0.0,0.0,0.0,1995.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,0.52,0.52,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2009.99,2010.3,0.0,0.0,2009.9,2010.1,0.0,0.0,1989.9,1990.1,0.0,0.0,1990.0,1990.01,0.0,0.0,2000.0,0.0,0.0,0.0,1999.0,2005.0,2005.3,0.0,2000.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2005.0,0.0,0.0,0.0,2005.0,2006.0,2006.3,0.0,1996.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,1.0,2010.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2016.0,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.4,0.0,0.0,0.0,1.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0};
string X_FINAL[]={"REGISTERED","REGISTERED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","SENT_MAPPED","SENT_MAPPED","NO_REQUEST","NO_REQUEST","NO_REQUEST","NO_REQUEST","SENT_MAPPED","NO_REQUEST","SENT_MAPPED","SENT_MAPPED","SENT_MAPPED","NO_REQUEST","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","BLOCKED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","RECOVERY_REQUIRED","NOT_IDLE","BLOCKED","BLOCKED","BLOCKED","BLOCKED"};
int X_SENDS[]={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,0,0,0,0,1,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0};
string X_DISK[]={"IDLE","IDLE","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","MISSING","IDLE","CORRUPT","REQUEST_PENDING","REQUEST_PENDING","IDLE","IDLE","IDLE","IDLE","REQUEST_PENDING","IDLE","REQUEST_PENDING","REQUEST_PENDING","REQUEST_PENDING","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","IDLE","MISSING","CORRUPT","REQUEST_PENDING","IDLE","IDLE","IDLE","IDLE"};
int X_GEN[]={1,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,3,3,1,1,1,1,3,1,3,3,3,1,1,1,1,1,1,1,1,1,1,1,0,0,3,1,1,1,1};
string X_REASON[]={"","","INPUT_UNSET: r_policy","INVALID_INPUT: r_policy","INPUT_UNSET: initial_sl","INITIAL_SL_NOT_PROVEN","INITIAL_SL_NOT_PROVEN","INITIAL_SL_NOT_PROVEN","INITIAL_SL_NOT_PROVEN","ENTRY_UNAVAILABLE","BASE_NOT_ON_SYMBOL_GRID","BASE_NOT_ON_SYMBOL_GRID","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","GEOMETRY_REFUSED","TP_EQUALS_2R","TP_BEFORE_2R","TP_BEFORE_2R","OWNERSHIP_NOT_PROVEN","POSITION_NOT_FOUND","POSITION_VOLUME_DIFFERS","REGISTRATION_REFUSED","DISABLED","ALREADY_EXISTS","ALREADY_EXISTS","","","","","","","","","","","","","PLAN_CHANGED: initial_sl","INPUT_UNSET: initial_sl","INPUT_UNSET: r_policy","PLAN_CHANGED: r_policy","PLAN_CHANGED: r_policy","PLAN_CHANGED: level_2R","PLAN_CHANGED: level_2R","PLAN_CHANGED: tp","GEOMETRY_REFUSED","PLAN_MISSING","LOAD_UNUSABLE","UNSUPPORTED_VERSION","","OWNERSHIP_NOT_PROVEN","","LATCHED","DISABLED"};
double X_LEVEL[]={2010.0,1990.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,2010.0,0.0,2010.0,1990.0,2010.0,2010.0,1990.0,1990.0,2010.0,2010.0,1990.0,2010.0,2010.0,2010.0,2010.0,2010.0,2010.0,2010.0,2010.0,2011.0,1991.0,2010.0,2010.0,0.0,0.0,0.0,2010.0,2010.0,2010.0,2010.0,2010.0};
// END GENERATED FIXTURES
SEsIdentity Ident()
  {
   SEsIdentity i;
   i.server="MetaQuotes-Demo";
   i.login=5001234;
   i.symbol="XAUUSD";
   i.position_id=7;
   return(i);
  }
void Clean(void)
  {
   if(FileIsExist(FN)) FileDelete(FN);
   if(FileIsExist(FN+ESF_TMP_SUFFIX)) FileDelete(FN+ESF_TMP_SUFFIX);
  }
bool ReasonOk(const string expected,const string reason)
  {
   if(expected=="") return(true);
   return(StringFind(reason,expected)>=0);
  }
double BaseSl(const int side) {return(side==1 ? 1995.0 : 2005.0);}
double BaseLevel(const int side) {return(side==1 ? 2010.0 : 1990.0);}
double BaseTp(const int side) {return(side==1 ? 2015.0 : 1985.0);}
// BUY world: price_open 2000.0, live SL 1995.0 (= the asserted initial SL), R = 5.0, level 2R = 2010.0, TP 2015.0. SELL world: SL 2005.0, level 1990.0, TP 1985.0
void World(const int row,SExConfig &cfg,CFakeTransport &t,SExQuote &q,SExRuntime &rt)
  {
   int side=R_SIDE[row];
   EX_ConfigInit(cfg);
   cfg.enabled=true;
   cfg.r_policy=EX_RPOL_R_GEOM;
   cfg.sl_initial_set=true;
   cfg.sl_initial=BaseSl(side);
   cfg.ea_magic=777;
   cfg.filling=EX_FILL_IOC;
   cfg.deviation=20;
   cfg.filter_policy=EX_POL_IGNORE;
   cfg.filter_state=EX_FS_CLEAR;
   cfg.tp_set=true;
   cfg.tp_price=BaseTp(side);
   SExSendResult r;
   r.returned_true=true;
   r.have_result=true;
   r.retcode=10009;
   r.order=501;
   r.deal=1001;
   r.volume=0.4;
   r.price=2000.0;
   t.response=r;
   t.position.type=(side==1 ? 0 : 1);
   t.position.price_open=2000.0;
   t.position.sl=BaseSl(side);
   t.position.volume=0.5;
   q.direction=side;
   q.level_2r=0.0;
   q.bid=(side==1 ? 2010.0 : 1989.7);
   q.ask=(side==1 ? 2010.3 : 1990.0);
   q.volume_initial=0.5;
   EX_RuntimeInit(rt);
   for(int k=0;k<S_N[row];k++)
     {
      double v=S_VAL[row*MAXSET+k];
      switch(S_KEY[row*MAXSET+k])
        {
         case 0: cfg.r_policy=(ENUM_EX_R_POLICY)(int)v; break;
         case 1: cfg.sl_initial_set=(v!=0.0); break;
         case 2: cfg.sl_initial=v; break;
         case 3: cfg.tp_price=v; break;
         case 4: cfg.enabled=(v!=0.0); break;
         case 5: t.position.price_open=v; break;
         case 6: t.position.sl=v; break;
         case 7: t.position.magic=(long)v; break;
         case 8: t.position.volume=v; break;
         case 9: t.position.found=(v!=0.0); break;
         case 10: t.symbol.digits=(int)v; break;
         case 11: q.level_2r=v; break;
         case 12: q.bid=v; break;
         case 13: q.ask=v; break;
         case 14: q.volume_initial=v; break;
         case 15: cfg.tp_set=(v!=0.0); break;
         case 16: rt.latched=(v!=0.0); break;
        }
     }
  }
void Prepare(const int start,const int side)
  {
   Clean();
   if(start==S_MISSING) return;
   SEsRecord rec;
   ESC_RecordInit(rec);
   rec.id=Ident();
   rec.generation=1;
   EA_StateInit(rec.state);
   string text,why;
   if(start==S_NOPLAN)
     {
      if(!ESC_Encode(rec,text,why)) {Print("FAIL fixture record not encodable: ",why); g_fail++; return;}
      ESF_WriteAll(FN,text);
      return;
     }
   rec.state.bound=true;
   rec.state.position_id=7;
   rec.state.direction=side;
   rec.state.level=(start==S_TAMPER_LEVEL ? BaseLevel(side)+1.0 : BaseLevel(side));
   rec.state.volume_initial=0.5;
   rec.plan_set=true;
   rec.plan_tp=BaseTp(side);
   rec.plan_vol_min=0.01;
   rec.plan_vol_step=0.01;
   rec.plan_vol_max=100.0;
   rec.plan_rpol=(start==S_TYPED ? ESC_RPOL_TYPED : ESC_RPOL_R_GEOM);
   if(start!=S_TYPED)
     {
      rec.plan_e_src=2000.0;
      rec.plan_s_src=BaseSl(side);
      rec.plan_e_out=2000.0;
      rec.plan_s_out=BaseSl(side);
     }
   if(start==S_PEND_MAP)
     {
      SEaResult r;
      EA_OnQuote(rec.state,7,side,BaseLevel(side),(side==1 ? 2010.0 : 1989.7),(side==1 ? 2010.3 : 1990.0),0.5,0.5,0.01,0.01,100.0,r);
      rec.generation=3;
      rec.send_phase=ESC_SEND_MAPPED;
      rec.map_complete=true;
      rec.n_orders=1;
      rec.orders[0]=501;
     }
   if(!ESC_Encode(rec,text,why)) {Print("FAIL fixture record not encodable: ",why); g_fail++; return;}
   if(start==S_OLD_V2)
     {
      string lines[];
      string body=StringSubstr(text,0,StringFind(text,"CRC="));
      int n=ESC_Lines(body,lines);
      string out="";
      for(int i=0;i<n;i++)
        {
         if(StringFind(lines[i],"PLAN_RPOL")==0 || StringFind(lines[i],"PLAN_E_")==0 || StringFind(lines[i],"PLAN_S_")==0) continue;
         out+=lines[i]+"\n";
        }
      StringReplace(out,"VERSION=3","VERSION=2");
      text=out+"CRC="+StringFormat("%08X",ESC_Crc32(out))+"\n";
     }
   ESF_WriteAll(FN,text);
  }
string DiskStatus(int &generation,double &level)
  {
   generation=0;
   level=0.0;
   string text,why;
   SEsRecord rec;
   if(!FileIsExist(FN) || !ESF_ReadAll(FN,text)) return("MISSING");
   if(!ESC_Decode(text,rec,why)) return("CORRUPT");
   generation=rec.generation;
   level=rec.state.level;
   return(EA_StateName(rec.state.status));
  }
void RunRows(void)
  {
   for(int i=0;i<NROWS;i++)
     {
      string tag=R_NAME[i]+": ";
      SExConfig cfg;
      CFakeTransport t;
      SExQuote q;
      SExRuntime rt;
      World(i,cfg,t,q,rt);
      Prepare(R_START[i],R_SIDE[i]);
      SExResult res;
      if(R_OP[i]==0) EX_Register(cfg,GetPointer(t),rt,FN,Ident(),q,res);
      else EX_Process(cfg,GetPointer(t),rt,FN,Ident(),q,res);
      Print(tag,EX_FinalName(res.final_state)," sends ",t.sends," | ",res.reason);
      Check(EX_FinalName(res.final_state)==X_FINAL[i],tag+"final "+EX_FinalName(res.final_state));
      Check(t.sends==X_SENDS[i],tag+"sends "+IntegerToString(t.sends));
      Check(ReasonOk(X_REASON[i],res.reason),tag+"reason contains '"+X_REASON[i]+"' got '"+res.reason+"'");
      int g;
      double lv;
      string disk=DiskStatus(g,lv);
      Check(disk==X_DISK[i],tag+"status on disk '"+disk+"'");
      Check(g==X_GEN[i] && lv==X_LEVEL[i],tag+"generation "+IntegerToString(g)+" and level on disk "+DoubleToString(lv,2));
      Check(!FileIsExist(FN+ESF_TMP_SUFFIX),tag+"no temporary file is left");
      if(t.sends>0) Check(t.last_request.position==9 && t.last_request.volume==0.4 && (t.last_request.price==q.bid || t.last_request.price==q.ask),tag+"the request carries the position TICKET and the planned volume");
     }
  }
void TestBasisOnDisk(void)
  {
   for(int k=0;k<2;k++)
     {
      int side=(k==0 ? 1 : -1);
      SExConfig cfg;
      CFakeTransport t;
      SExQuote q;
      SExRuntime rt;
      // row 0 is the BUY registration, row 1 the SELL one (see the fixtures): reuse their worlds
      World(k,cfg,t,q,rt);
      Clean();
      SExResult res;
      EX_Register(cfg,GetPointer(t),rt,FN,Ident(),q,res);
      string text,why;
      SEsRecord rec;
      bool ok=(ESF_ReadAll(FN,text) && ESC_Decode(text,rec,why));
      Check(ok && res.final_state==EX_REGISTERED,"registration of side "+IntegerToString(side)+" wrote a decodable record");
      if(ok)
        {
         Check(rec.plan_rpol==ESC_RPOL_R_GEOM && rec.plan_e_src==2000.0 && rec.plan_s_src==BaseSl(side) && rec.plan_e_out==2000.0 && rec.plan_s_out==BaseSl(side) && rec.state.level==BaseLevel(side),
               "the declared basis (source and normalized E and S) and the derived level are stored");
         Check(StringFind(text,"R_GEOM=")<0 && StringFind(text,"\nR=")<0 && StringFind(text,"RISK=")<0,"R itself is not stored");
        }
     }
  }
void TestOldVersionUntouched(void)
  {
   SExConfig cfg;
   CFakeTransport t;
   SExQuote q;
   SExRuntime rt;
   World(0,cfg,t,q,rt);
   Prepare(S_OLD_V2,1);
   string before,after;
   ESF_ReadAll(FN,before);
   SExResult a,b;
   EX_Process(cfg,GetPointer(t),rt,FN,Ident(),q,a);
   EX_Register(cfg,GetPointer(t),rt,FN,Ident(),q,b);
   ESF_ReadAll(FN,after);
   Check(before==after && t.sends==0,"an old version 2 file is refused and left byte for byte unchanged (never migrated, never deleted)");
   Check(a.final_state==EX_RECOVERY_REQUIRED && StringFind(a.reason,"UNSUPPORTED_VERSION")>=0,"the old version is refused with UNSUPPORTED_VERSION");
  }
void OnStart()
  {
   Print("T011 GEOM TEST: fake transport only; sandbox file VELO_T011_GEOMTEST_A.state; no order, no position read, no trade.");
   Clean();
   RunRows();
   TestBasisOnDisk();
   TestOldVersionUntouched();
   Clean();
   Check(!FileIsExist(FN) && !FileIsExist(FN+ESF_TMP_SUFFIX),"the test leaves no file behind");
   PrintFormat("T011 GEOM TEST finished: %d passed, %d failed",g_pass,g_fail);
  }
