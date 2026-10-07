//+------------------------------------------------------------------+
//| StatusPanel.mqh                                                  |
//|                                                                  |
//| Minimal text panel drawn with OBJ_LABEL objects. All objects      |
//| share one name prefix and are deleted in Destroy(), so reloading  |
//| the EA leaves no leftovers on the chart.                          |
//+------------------------------------------------------------------+
#ifndef VELO_STATUS_PANEL_MQH
#define VELO_STATUS_PANEL_MQH

class CStatusPanel
  {
private:
   string            m_prefix;
   long              m_chart;
   bool              m_enabled;
   ENUM_BASE_CORNER  m_corner;
   int               m_x;
   int               m_y;
   int               m_line_height;
   int               m_font_size;
   string            m_font;

   int               m_cursor;   // next line index to write
   int               m_created;  // highest line count ever created

   string            LabelName(const int index) const
     {
      return(StringFormat("%s%03d", m_prefix, index));
     }

public:
                     CStatusPanel(void)
     {
      m_prefix      = "velo_t001_";
      m_chart       = 0;
      m_enabled     = false;
      m_corner      = CORNER_LEFT_UPPER;
      m_x           = 10;
      m_y           = 20;
      m_line_height = 14;
      m_font_size   = 9;
      m_font        = "Consolas";
      m_cursor      = 0;
      m_created     = 0;
     }

   void              Init(const string prefix, const bool enabled, const ENUM_BASE_CORNER corner)
     {
      m_prefix  = prefix;
      m_enabled = enabled;
      m_corner  = corner;
      m_chart   = ChartID();
      m_cursor  = 0;
      m_created = 0;
      //--- Clear labels left behind by a previous instance whose OnDeinit
      //--- never ran (terminal crash), so a reload starts from a clean chart.
      ObjectsDeleteAll(m_chart, m_prefix, 0, OBJ_LABEL);
     }

   void              Begin(void) { m_cursor = 0; }

   void              Line(const string text, const color clr)
     {
      if(!m_enabled)
         return;
      string name = LabelName(m_cursor);
      if(ObjectFind(m_chart, name) < 0)
        {
         if(!ObjectCreate(m_chart, name, OBJ_LABEL, 0, 0, 0))
           {
            ResetLastError();
            return;
           }
         ObjectSetInteger(m_chart, name, OBJPROP_CORNER,     m_corner);
         ObjectSetInteger(m_chart, name, OBJPROP_ANCHOR,
                          m_corner == CORNER_RIGHT_UPPER || m_corner == CORNER_RIGHT_LOWER
                             ? ANCHOR_RIGHT_UPPER : ANCHOR_LEFT_UPPER);
         ObjectSetInteger(m_chart, name, OBJPROP_XDISTANCE,  m_x);
         ObjectSetInteger(m_chart, name, OBJPROP_YDISTANCE,  m_y + m_cursor * m_line_height);
         ObjectSetInteger(m_chart, name, OBJPROP_FONTSIZE,   m_font_size);
         ObjectSetString(m_chart,  name, OBJPROP_FONT,       m_font);
         ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN,     true);
         ObjectSetInteger(m_chart, name, OBJPROP_BACK,       false);
         if(m_cursor + 1 > m_created)
            m_created = m_cursor + 1;
        }
      ObjectSetString(m_chart,  name, OBJPROP_TEXT,  text);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, clr);
      m_cursor++;
     }

   //--- Remove labels left over from a previous, longer render.
   void              End(void)
     {
      if(!m_enabled)
         return;
      for(int i = m_cursor; i < m_created; i++)
        {
         string name = LabelName(i);
         if(ObjectFind(m_chart, name) >= 0)
            ObjectDelete(m_chart, name);
        }
      if(m_created > m_cursor)
         m_created = m_cursor;
      ChartRedraw(m_chart);
     }

   void              Destroy(void)
     {
      ObjectsDeleteAll(m_chart, m_prefix, 0, OBJ_LABEL);
      m_cursor  = 0;
      m_created = 0;
      ChartRedraw(m_chart);
     }
  };

#endif // VELO_STATUS_PANEL_MQH
