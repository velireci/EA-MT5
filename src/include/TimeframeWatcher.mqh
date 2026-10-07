//+------------------------------------------------------------------+
//| TimeframeWatcher.mqh                                             |
//|                                                                  |
//| Read-only access to one symbol/timeframe series:                 |
//|   - history readiness, with an explicit throttled request for the|
//|     depth each timeframe needs (no blocking wait, not per tick)  |
//|   - strict separation of the FORMING bar (position 0, still      |
//|     changing) and the last CLOSED bar (position 1, final)        |
//|   - one new-bar event per timeframe per new bar                  |
//|                                                                  |
//| Contains no trading calls. T001 scope only.                      |
//+------------------------------------------------------------------+
#ifndef VELO_TIMEFRAME_WATCHER_MQH
#define VELO_TIMEFRAME_WATCHER_MQH

//--- Readiness of a single series. Only TF_STATE_READY allows reads.
enum ENUM_TF_STATE
  {
   TF_STATE_UNKNOWN = 0,   // never polled
   TF_STATE_NO_HISTORY,    // server has not delivered any bar yet
   TF_STATE_LOADING,       // bars arriving, below the required depth
   TF_STATE_DESYNC,        // series not synchronised / inconsistent
   TF_STATE_READY          // enough synchronised bars, data usable
  };

string TfStateToString(const ENUM_TF_STATE state)
  {
   switch(state)
     {
      case TF_STATE_NO_HISTORY: return("NO_HISTORY");
      case TF_STATE_LOADING:    return("LOADING");
      case TF_STATE_DESYNC:     return("DESYNC");
      case TF_STATE_READY:      return("READY");
      default:                  return("UNKNOWN");
     }
  }

//--- Short timeframe name for logs and the chart panel.
string TfShortName(const ENUM_TIMEFRAMES period)
  {
   string s = EnumToString(period);
   string head = "PERIOD_";
   if(StringFind(s, head) == 0)
      s = StringSubstr(s, StringLen(head));
   return(s);
  }

//+------------------------------------------------------------------+
//| CTimeframeWatcher                                                |
//+------------------------------------------------------------------+
class CTimeframeWatcher
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_period;
   int               m_min_bars;

   ENUM_TF_STATE     m_state;
   string            m_detail;
   int               m_bars;

   bool              m_bars_valid;    // m_forming / m_closed hold real data
   MqlRates          m_forming;       // series position 0 - STILL CHANGING, never final
   MqlRates          m_closed;        // series position 1 - CLOSED, final

   bool              m_baseline_set;  // first ready poll seen (no event fired)
   datetime          m_forming_open;  // open time of the forming bar
   long              m_new_bar_count;
   int               m_skipped_bars;  // bars that closed unobserved before the last event

   //--- History request throttle. Without it the request below would be
   //--- re-issued on every tick while the download is still running.
   uint              m_request_interval_ms;
   uint              m_last_request_ms;
   bool              m_request_sent;
   int               m_request_count;

   //--- Ask the terminal to build this series down to m_min_bars.
   //--- CopyTime at the deepest required position is the documented way to
   //--- trigger that build; asking for a single element keeps it cheap.
   //--- It returns immediately - there is no wait loop and no Sleep here,
   //--- so a slow download never blocks OnTick or OnTimer.
   void              RequestHistory(void)
     {
      uint now = GetTickCount();
      //--- Unsigned arithmetic makes the GetTickCount wrap-around harmless.
      if(m_request_sent && (now - m_last_request_ms) < m_request_interval_ms)
         return;

      m_last_request_ms = now;
      m_request_sent    = true;
      m_request_count++;

      datetime probe[];
      if(CopyTime(m_symbol, m_period, m_min_bars - 1, 1, probe) < 0)
         ResetLastError();   // expected while the terminal is still loading
     }

public:
                     CTimeframeWatcher(void)
     {
      m_symbol              = "";
      m_period              = PERIOD_CURRENT;
      m_min_bars            = 3;
      m_request_interval_ms = 2000;
      Reset();
     }

   void              Configure(const string symbol, const ENUM_TIMEFRAMES period, const int min_bars)
     {
      m_symbol   = symbol;
      m_period   = period;
      //--- two bars are read, so three is the lowest sensible depth
      m_min_bars = (min_bars < 3 ? 3 : min_bars);
      Reset();
     }

   void              Reset(void)
     {
      m_state         = TF_STATE_UNKNOWN;
      m_detail        = "not polled yet";
      m_bars            = 0;
      m_bars_valid      = false;
      m_baseline_set    = false;
      m_forming_open    = 0;
      m_new_bar_count   = 0;
      m_skipped_bars    = 0;
      m_last_request_ms = 0;
      m_request_sent    = false;
      m_request_count   = 0;
      ZeroMemory(m_forming);
      ZeroMemory(m_closed);
     }

   //--- Poll the series. Returns the readiness state; sets new_bar to true
   //--- at most once per newly opened bar. Never returns true on partial data.
   bool              Refresh(bool &new_bar)
     {
      new_bar      = false;
      m_bars_valid = false;

      m_bars = Bars(m_symbol, m_period);

      //--- Short of the depth this timeframe needs: ask for it explicitly
      //--- (throttled) BEFORE reporting that history is missing, so the
      //--- download is actually under way while this returns false.
      if(m_bars < m_min_bars)
        {
         RequestHistory();
         if(m_bars <= 0)
           {
            m_state  = TF_STATE_NO_HISTORY;
            m_detail = StringFormat("no bars yet, %d history request(s) sent", m_request_count);
            ResetLastError();
           }
         else
           {
            m_state  = TF_STATE_LOADING;
            m_detail = StringFormat("%d/%d bars, %d history request(s) sent",
                                    m_bars, m_min_bars, m_request_count);
           }
         return(false);
        }

      long synchronized = 0;
      if(!SeriesInfoInteger(m_symbol, m_period, SERIES_SYNCHRONIZED, synchronized) || synchronized == 0)
        {
         m_state  = TF_STATE_DESYNC;
         m_detail = "series not synchronised with the server";
         return(false);
        }

      //--- Positions 0 and 1 of the series: the forming bar and the one
      //--- before it, cross-checked against SERIES_LASTBAR_DATE. Those are
      //--- two separate reads, so a bar opening between them would look like
      //--- a mismatch. The pair is therefore read again once before any
      //--- disagreement is reported as a desync.
      MqlRates rates[];
      int  i_new      = 1;
      int  i_old      = 0;
      bool consistent = false;

      for(int attempt = 0; attempt < 2 && !consistent; attempt++)
        {
         int copied = CopyRates(m_symbol, m_period, 0, 2, rates);
         if(copied < 2)
           {
            m_state  = TF_STATE_LOADING;
            m_detail = StringFormat("CopyRates returned %d (error %d)", copied, GetLastError());
            ResetLastError();
            return(false);
           }

         //--- Do not assume which element is newer: decide from the timestamps.
         i_new = 1;
         i_old = 0;
         if(rates[0].time > rates[1].time)
           {
            i_new = 0;
            i_old = 1;
           }
         if(rates[i_new].time == rates[i_old].time)
           {
            m_state  = TF_STATE_DESYNC;
            m_detail = "two identical bar timestamps returned";
            return(false);
           }

         datetime series_last = (datetime)SeriesInfoInteger(m_symbol, m_period, SERIES_LASTBAR_DATE);
         if(series_last == rates[i_new].time)
            consistent = true;
         else
            m_detail = StringFormat("forming bar %s disagrees with series last bar %s",
                                    TimeToString(rates[i_new].time, TIME_DATE|TIME_MINUTES),
                                    TimeToString(series_last, TIME_DATE|TIME_MINUTES));
        }

      if(!consistent)
        {
         m_state = TF_STATE_DESYNC;   // m_detail already describes the mismatch
         return(false);
        }

      if(rates[i_new].time > TimeCurrent())
        {
         m_state  = TF_STATE_DESYNC;
         m_detail = "forming bar opens in the future";
         return(false);
        }

      m_forming    = rates[i_new];   // series position 0 - do not treat as final
      m_closed     = rates[i_old];   // series position 1 - final
      m_bars_valid = true;
      m_state      = TF_STATE_READY;
      m_detail     = StringFormat("%d bars", m_bars);

      if(!m_baseline_set)
        {
         //--- First ready poll after attach/restart: take a baseline silently
         //--- so reloading the EA does not fake a new-bar event.
         m_baseline_set = true;
         m_forming_open = m_forming.time;
        }
      else
         if(m_forming.time != m_forming_open)
           {
            datetime previous_open = m_forming_open;
            m_forming_open  = m_forming.time;
            m_new_bar_count++;
            m_skipped_bars  = 0;
            new_bar         = true;
            //--- Bars() counts both ends of the range, so one clean step is 2.
            //--- Anything above that means bars closed while unobserved
            //--- (weekend gap, reconnect, terminal asleep).
            if(m_forming.time > previous_open)
              {
               int span = Bars(m_symbol, m_period, previous_open, m_forming.time);
               if(span > 2)
                  m_skipped_bars = span - 2;
              }
           }

      return(true);
     }

   //--- state -------------------------------------------------------
   bool              IsReady(void)        const { return(m_state == TF_STATE_READY); }
   ENUM_TF_STATE     State(void)          const { return(m_state); }
   string            StateName(void)      const { return(TfStateToString(m_state)); }
   string            Detail(void)         const { return(m_detail); }
   int               BarsAvailable(void)  const { return(m_bars); }
   int               MinBars(void)        const { return(m_min_bars); }
   long              NewBarCount(void)    const { return(m_new_bar_count); }
   int               SkippedBars(void)     const { return(m_skipped_bars); }
   int               HistoryRequests(void) const { return(m_request_count); }
   ENUM_TIMEFRAMES   Period(void)         const { return(m_period); }
   string            PeriodName(void)     const { return(TfShortName(m_period)); }

   //--- data --------------------------------------------------------
   //--- The last CLOSED bar. Final; safe for later decision logic.
   bool              GetClosedBar(MqlRates &out) const
     {
      if(!m_bars_valid)
         return(false);
      out = m_closed;
      return(true);
     }
   //--- The FORMING bar. Values keep changing until the bar closes.
   bool              GetFormingBar(MqlRates &out) const
     {
      if(!m_bars_valid)
         return(false);
      out = m_forming;
      return(true);
     }
   datetime          ClosedOpenTime(void)  const { return(m_bars_valid ? m_closed.time  : 0); }
   datetime          FormingOpenTime(void) const { return(m_bars_valid ? m_forming.time : 0); }

   //--- One line for the chart panel / log.
   string            StatusLine(const int digits) const
     {
      if(!IsReady())
         return(StringFormat("%-4s %-10s %s", PeriodName(), StateName(), m_detail));
      return(StringFormat("%-4s READY      closed %s O%s H%s L%s C%s | forming %s | new bars %d",
                          PeriodName(),
                          TimeToString(m_closed.time, TIME_DATE|TIME_MINUTES),
                          DoubleToString(m_closed.open,  digits),
                          DoubleToString(m_closed.high,  digits),
                          DoubleToString(m_closed.low,   digits),
                          DoubleToString(m_closed.close, digits),
                          TimeToString(m_forming.time, TIME_DATE|TIME_MINUTES),
                          (int)m_new_bar_count));
     }
  };

#endif // VELO_TIMEFRAME_WATCHER_MQH
