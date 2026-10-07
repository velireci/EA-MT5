//+------------------------------------------------------------------+
//| SymbolSnapshot.mqh                                               |
//|                                                                  |
//| Reads the broker's specification for one symbol and the account  |
//| position mode, so later stages never guess units or limits.      |
//| Read-only: no trading calls, no strategy decisions.              |
//+------------------------------------------------------------------+
#ifndef VELO_SYMBOL_SNAPSHOT_MQH
#define VELO_SYMBOL_SNAPSHOT_MQH

struct SSymbolSnapshot
  {
   bool     ok;
   string   problem;

   string   name;
   int      digits;
   double   point;
   double   tick_size;
   double   tick_value;
   double   contract_size;

   double   volume_min;
   double   volume_max;
   double   volume_step;

   long     stops_level;      // minimum SL/TP distance in points
   long     freeze_level;     // freeze distance in points
   long     spread_points;
   bool     spread_float;

   long     trade_mode;       // ENUM_SYMBOL_TRADE_MODE
   long     filling_mode;     // bit mask of allowed fillings
   long     expiration_mode;  // bit mask of allowed expirations

   long     margin_mode;      // account: netting / exchange / hedging
   string   account_currency;
   string   server_name;
  };

string SymbolTradeModeText(const long mode)
  {
   switch((ENUM_SYMBOL_TRADE_MODE)mode)
     {
      case SYMBOL_TRADE_MODE_DISABLED:  return("DISABLED");
      case SYMBOL_TRADE_MODE_LONGONLY:  return("LONG_ONLY");
      case SYMBOL_TRADE_MODE_SHORTONLY: return("SHORT_ONLY");
      case SYMBOL_TRADE_MODE_CLOSEONLY: return("CLOSE_ONLY");
      case SYMBOL_TRADE_MODE_FULL:      return("FULL");
      default:                          return("UNKNOWN");
     }
  }

string AccountMarginModeText(const long mode)
  {
   switch((ENUM_ACCOUNT_MARGIN_MODE)mode)
     {
      case ACCOUNT_MARGIN_MODE_RETAIL_NETTING: return("RETAIL_NETTING");
      case ACCOUNT_MARGIN_MODE_EXCHANGE:       return("EXCHANGE");
      case ACCOUNT_MARGIN_MODE_RETAIL_HEDGING: return("RETAIL_HEDGING");
      default:                                 return("UNKNOWN");
     }
  }

string FillingModeText(const long mask)
  {
   string s = "";
   if((mask & SYMBOL_FILLING_FOK) != 0)
      s += "FOK ";
   if((mask & SYMBOL_FILLING_IOC) != 0)
      s += "IOC ";
   if(s == "")
      s = "none reported ";
   return(StringSubstr(s, 0, StringLen(s) - 1));
  }

//--- Load the snapshot. Returns false and fills .problem when the symbol
//--- cannot be used as a data source at all.
bool SymbolSnapshotLoad(const string symbol, SSymbolSnapshot &snap)
  {
   //--- Explicit reset: this structure holds strings, so every field is
   //--- initialised by hand instead of relying on a memory wipe.
   snap.ok               = false;
   snap.problem          = "";
   snap.name             = symbol;
   snap.digits           = 0;
   snap.point            = 0.0;
   snap.tick_size        = 0.0;
   snap.tick_value       = 0.0;
   snap.contract_size    = 0.0;
   snap.volume_min       = 0.0;
   snap.volume_max       = 0.0;
   snap.volume_step      = 0.0;
   snap.stops_level      = 0;
   snap.freeze_level     = 0;
   snap.spread_points    = 0;
   snap.spread_float     = false;
   snap.trade_mode       = 0;
   snap.filling_mode     = 0;
   snap.expiration_mode  = 0;
   snap.margin_mode      = 0;
   snap.account_currency = "";
   snap.server_name      = "";

   if(symbol == "")
     {
      snap.problem = "empty symbol name";
      return(false);
     }
   if(SymbolInfoInteger(symbol, SYMBOL_EXIST) == 0)
     {
      snap.problem = "symbol does not exist on this broker";
      return(false);
     }
   //--- Market Watch selection is required before series data is served.
   if(SymbolInfoInteger(symbol, SYMBOL_SELECT) == 0)
     {
      if(!SymbolSelect(symbol, true))
        {
         snap.problem = StringFormat("SymbolSelect failed, error %d", GetLastError());
         ResetLastError();
         return(false);
        }
     }

   snap.digits        = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   snap.point         = SymbolInfoDouble(symbol, SYMBOL_POINT);
   snap.tick_size     = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   snap.tick_value    = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   snap.contract_size = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);

   snap.volume_min    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   snap.volume_max    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   snap.volume_step   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);

   snap.stops_level   = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   snap.freeze_level  = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   snap.spread_points = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   snap.spread_float  = (bool)SymbolInfoInteger(symbol, SYMBOL_SPREAD_FLOAT);

   snap.trade_mode      = SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
   snap.filling_mode    = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   snap.expiration_mode = SymbolInfoInteger(symbol, SYMBOL_EXPIRATION_MODE);

   snap.margin_mode      = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   snap.account_currency = AccountInfoString(ACCOUNT_CURRENCY);
   snap.server_name      = AccountInfoString(ACCOUNT_SERVER);

   //--- Values the later stages divide by must be present.
   if(snap.digits <= 0 || snap.point <= 0.0)
     {
      snap.problem = "digits/point not reported by the broker";
      return(false);
     }
   if(snap.tick_size <= 0.0)
     {
      snap.problem = "tick size not reported by the broker";
      return(false);
     }
   if(snap.volume_step <= 0.0 || snap.volume_min <= 0.0)
     {
      snap.problem = "volume step/minimum not reported by the broker";
      return(false);
     }

   snap.ok = true;
   return(true);
  }

//--- Multi-line report for the Experts log.
string SymbolSnapshotReport(const SSymbolSnapshot &snap)
  {
   string r = "";
   r += StringFormat("symbol=%s server=%s account currency=%s position mode=%s\n",
                     snap.name, snap.server_name, snap.account_currency,
                     AccountMarginModeText(snap.margin_mode));
   r += StringFormat("digits=%d point=%s tick size=%s tick value=%s contract size=%s\n",
                     snap.digits,
                     DoubleToString(snap.point, snap.digits),
                     DoubleToString(snap.tick_size, snap.digits),
                     DoubleToString(snap.tick_value, 5),
                     DoubleToString(snap.contract_size, 2));
   r += StringFormat("volume min=%s max=%s step=%s\n",
                     DoubleToString(snap.volume_min,  2),
                     DoubleToString(snap.volume_max,  2),
                     DoubleToString(snap.volume_step, 2));
   r += StringFormat("stops level=%d points freeze level=%d points spread=%d points (%s)\n",
                     (int)snap.stops_level, (int)snap.freeze_level, (int)snap.spread_points,
                     snap.spread_float ? "floating" : "fixed");
   r += StringFormat("symbol trade mode=%s allowed filling=%s expiration mask=%d",
                     SymbolTradeModeText(snap.trade_mode),
                     FillingModeText(snap.filling_mode),
                     (int)snap.expiration_mode);
   return(r);
  }

#endif // VELO_SYMBOL_SNAPSHOT_MQH
