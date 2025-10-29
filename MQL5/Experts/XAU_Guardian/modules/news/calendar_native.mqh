#ifndef XAU_GUARDIAN_NEWS_CALENDAR_NATIVE_MQH
#define XAU_GUARDIAN_NEWS_CALENDAR_NATIVE_MQH

#include "../Utils.mqh"

class GuardianNewsCalendar
  {
private:
   struct CalendarEventMeta
     {
      ulong   id;
      ENUM_CALENDAR_EVENT_IMPORTANCE importance;
      string  currency;
      string  name;
     };

   struct CalendarWindow
     {
      datetime start;
      datetime end;
      ulong    eventId;
      string   currency;
      string   name;
     };

   string   m_symbol;
   string   m_currencies[];
   CalendarEventMeta m_eventCache[];
   CalendarWindow    m_windows[];
   int      m_minutesBefore;
   int      m_minutesAfter;
   int      m_lookaheadMinutes;
   int      m_refreshSeconds;
   bool     m_debug;
   ENUM_CALENDAR_EVENT_IMPORTANCE m_minImportance;
   datetime m_lastRefresh;

   void ClearWindows()
     {
      ArrayResize(m_windows,0);
     }

   static string NormalizeCurrency(string value)
     {
      string trimmed=GuardianUtils::Trim(value);
      if(StringLen(trimmed)==0)
         return "";
      StringToUpper(trimmed);
      return trimmed;
     }

   void BuildCurrencyList()
     {
      ArrayResize(m_currencies,0);
      string base=NormalizeCurrency(SymbolInfoString(m_symbol,SYMBOL_CURRENCY_BASE));
      string profit=NormalizeCurrency(SymbolInfoString(m_symbol,SYMBOL_CURRENCY_PROFIT));
      string margin=NormalizeCurrency(SymbolInfoString(m_symbol,SYMBOL_CURRENCY_MARGIN));
      AddCurrency(base);
      AddCurrency(profit);
      if(StringLen(margin)>0 && margin!=profit)
         AddCurrency(margin);
     }

   void AddCurrency(const string currency)
     {
      if(StringLen(currency)==0)
         return;
      for(int i=0;i<ArraySize(m_currencies);++i)
        {
         if(m_currencies[i]==currency)
            return;
        }
      int size=ArraySize(m_currencies);
      ArrayResize(m_currencies,size+1);
      m_currencies[size]=currency;
     }

   int EventIndex(const ulong id) const
     {
      int total=ArraySize(m_eventCache);
      for(int i=0;i<total;++i)
         if(m_eventCache[i].id==id)
            return i;
      return -1;
     }

   void CacheEvent(const string currency,const MqlCalendarEvent &event)
     {
      int idx=EventIndex(event.id);
      if(idx==-1)
        {
         int size=ArraySize(m_eventCache);
         ArrayResize(m_eventCache,size+1);
         m_eventCache[size].id=event.id;
         m_eventCache[size].importance=event.importance;
         m_eventCache[size].currency=currency;
         m_eventCache[size].name=event.name;
        }
      else
        {
         m_eventCache[idx].importance=event.importance;
         if(StringLen(m_eventCache[idx].currency)==0)
            m_eventCache[idx].currency=currency;
         if(StringLen(m_eventCache[idx].name)==0 && StringLen(event.name)>0)
            m_eventCache[idx].name=event.name;
        }
     }

   void CacheEventsForCurrency(const string currency)
     {
      MqlCalendarEvent events[];
      ArrayResize(events,0);
      ResetLastError();
      int total=CalendarEventByCurrency(currency,events);
      if(total<=0)
        {
         int err=GetLastError();
         if(err!=0 && m_debug)
            GuardianUtils::PrintDebug("CalendarEventByCurrency failed for "+currency+": "+IntegerToString(err),m_debug);
         return;
        }
      int limit=ArraySize(events);
      for(int i=0;i<limit;++i)
         CacheEvent(currency,events[i]);
     }

   void SortWindows()
     {
      int total=ArraySize(m_windows);
      if(total<=1)
         return;
      for(int i=0;i<total-1;++i)
        {
         for(int j=i+1;j<total;++j)
           {
            if(m_windows[j].start<m_windows[i].start)
              {
               CalendarWindow tmp=m_windows[i];
               m_windows[i]=m_windows[j];
               m_windows[j]=tmp;
              }
           }
        }
     }

   void MergeWindows()
     {
      SortWindows();
      int total=ArraySize(m_windows);
      if(total<=1)
         return;
      CalendarWindow merged[];
      ArrayResize(merged,0);
      CalendarWindow current=m_windows[0];
      for(int i=1;i<total;++i)
        {
         CalendarWindow next=m_windows[i];
         if(next.start<=current.end)
           {
            if(next.end>current.end)
               current.end=next.end;
           }
         else
           {
            int idx=ArraySize(merged);
            ArrayResize(merged,idx+1);
            merged[idx]=current;
            current=next;
           }
        }
      int idx=ArraySize(merged);
      ArrayResize(merged,idx+1);
      merged[idx]=current;
      ArrayResize(m_windows,ArraySize(merged));
      for(int k=0;k<ArraySize(merged);++k)
         m_windows[k]=merged[k];
     }

   void AppendWindow(const datetime start,const datetime end,const ulong eventId,const string currency,const string name)
     {
      if(start>=end)
         return;
      int idx=ArraySize(m_windows);
      ArrayResize(m_windows,idx+1);
      m_windows[idx].start=start;
      m_windows[idx].end=end;
      m_windows[idx].eventId=eventId;
      m_windows[idx].currency=currency;
      m_windows[idx].name=name;
     }

 public:
   GuardianNewsCalendar():m_symbol(""),m_minutesBefore(0),m_minutesAfter(0),m_lookaheadMinutes(720),
                          m_refreshSeconds(300),m_debug(false),m_minImportance(CALENDAR_IMPORTANCE_HIGH),
                          m_lastRefresh(0)
     {
      ArrayResize(m_currencies,0);
      ArrayResize(m_eventCache,0);
      ArrayResize(m_windows,0);
     }

   void SetImportanceThreshold(const ENUM_CALENDAR_EVENT_IMPORTANCE importance)
     {
      m_minImportance=importance;
     }

   bool Init(const string symbol,const int minutesBefore,const int minutesAfter,const int lookaheadMinutes,
             const bool debug)
     {
      m_symbol=symbol;
      m_minutesBefore=MathMax(0,minutesBefore);
      m_minutesAfter=MathMax(0,minutesAfter);
      m_lookaheadMinutes=MathMax(60,lookaheadMinutes);
      m_debug=debug;
      BuildCurrencyList();
      m_lastRefresh=0;
      ClearWindows();
      ArrayResize(m_eventCache,0);
      return true;
     }

   bool Refresh(const bool force=false)
     {
      if((m_minutesBefore==0 && m_minutesAfter==0) || ArraySize(m_currencies)==0)
         return false;
      datetime now=TimeTradeServer();
      if(now==0)
         now=TimeCurrent();
      if(now==0)
         return false;
      if(!force && m_lastRefresh!=0 && (now-m_lastRefresh)<m_refreshSeconds)
         return (ArraySize(m_windows)>0);

      ClearWindows();
      for(int c=0;c<ArraySize(m_currencies);++c)
         CacheEventsForCurrency(m_currencies[c]);

      datetime from=now-(m_minutesAfter*60);
      datetime to=now+(m_lookaheadMinutes*60);
      for(int c=0;c<ArraySize(m_currencies);++c)
        {
         string currency=m_currencies[c];
         MqlCalendarValue values[];
         ArrayResize(values,0);
         ResetLastError();
         int count=CalendarValueHistory(values,from,to,NULL,currency);
         if(count<=0)
           {
            int err=GetLastError();
            if(err!=0 && m_debug)
               GuardianUtils::PrintDebug("CalendarValueHistory failed for "+currency+": "+IntegerToString(err),m_debug);
            continue;
           }
         int total=ArraySize(values);
         for(int i=0;i<total;++i)
           {
            datetime when=values[i].time;
            if(when==0)
               continue;
            if(when<from-(m_minutesBefore*60) || when>to)
               continue;
            ulong eventId=values[i].event_id;
            int eidx=EventIndex(eventId);
            if(eidx==-1)
              {
               MqlCalendarEvent ev;
               if(CalendarEventById(eventId,ev))
                 {
                  CacheEvent(currency,ev);
                  eidx=EventIndex(eventId);
                 }
              }
            ENUM_CALENDAR_EVENT_IMPORTANCE importance=(eidx!=-1)?m_eventCache[eidx].importance:CALENDAR_IMPORTANCE_LOW;
            if(importance<m_minImportance)
               continue;
            string evCurrency=(eidx!=-1)?m_eventCache[eidx].currency:currency;
            string evName=(eidx!=-1)?m_eventCache[eidx].name:"";
            datetime start=when-(m_minutesBefore*60);
            datetime end=when+(m_minutesAfter*60);
            AppendWindow(start,end,eventId,evCurrency,evName);
           }
        }
      MergeWindows();
      m_lastRefresh=now;
      return (ArraySize(m_windows)>0);
     }

   bool IsBlocked(const datetime time) const
     {
      int total=ArraySize(m_windows);
      for(int i=0;i<total;++i)
        {
         if(time>=m_windows[i].start && time<=m_windows[i].end)
            return true;
        }
      return false;
     }

   void Shutdown()
     {
      ArrayResize(m_windows,0);
      ArrayResize(m_eventCache,0);
      ArrayResize(m_currencies,0);
      m_lastRefresh=0;
     }
  };

#endif // XAU_GUARDIAN_NEWS_CALENDAR_NATIVE_MQH

