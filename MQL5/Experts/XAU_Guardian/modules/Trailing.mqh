#ifndef XAU_GUARDIAN_TRAILING_MQH
#define XAU_GUARDIAN_TRAILING_MQH

#include "Utils.mqh"

class TrailingManager
  {
private:
   string   m_symbol;
   int      m_magic;
   bool     m_debug;
   ulong    m_ticketIds[];
   double   m_peakPrices[];
   double   m_troughPrices[];
   datetime m_entryTimes[];

   int FindIndex(const ulong ticket) const
     {
      int total=ArraySize(m_ticketIds);
      for(int i=0;i<total;++i)
         if(m_ticketIds[i]==ticket)
            return i;
      return -1;
     }

   void EnsureState(const ulong ticket,const double open,const datetime entryTime)
     {
      int idx=FindIndex(ticket);
      if(idx==-1)
        {
         int size=ArraySize(m_ticketIds);
         ArrayResize(m_ticketIds,size+1);
         ArrayResize(m_peakPrices,size+1);
         ArrayResize(m_troughPrices,size+1);
         ArrayResize(m_entryTimes,size+1);
         m_ticketIds[size]=ticket;
         m_peakPrices[size]=open;
         m_troughPrices[size]=open;
         m_entryTimes[size]=entryTime;
        }
      else
        {
         m_entryTimes[idx]=entryTime;
        }
     }

   void UpdateExtrema(const int idx,const ENUM_POSITION_TYPE type,const double price)
     {
      if(idx<0)
         return;
      if(type==POSITION_TYPE_BUY)
        {
         if(price>m_peakPrices[idx])
            m_peakPrices[idx]=price;
         if(price<m_troughPrices[idx])
            m_troughPrices[idx]=price;
        }
      else
        {
         if(price<m_troughPrices[idx])
            m_troughPrices[idx]=price;
         if(price>m_peakPrices[idx])
            m_peakPrices[idx]=price;
        }
     }

   void EraseIndex(const int idx)
     {
      int last=ArraySize(m_ticketIds)-1;
      if(idx<0 || last<0)
         return;
      if(idx!=last)
        {
         m_ticketIds[idx]=m_ticketIds[last];
         m_peakPrices[idx]=m_peakPrices[last];
         m_troughPrices[idx]=m_troughPrices[last];
         m_entryTimes[idx]=m_entryTimes[last];
        }
      ArrayResize(m_ticketIds,last);
      ArrayResize(m_peakPrices,last);
      ArrayResize(m_troughPrices,last);
      ArrayResize(m_entryTimes,last);
     }

   void CleanupStale()
     {
      for(int i=ArraySize(m_ticketIds)-1;i>=0;--i)
        {
         ulong ticket=m_ticketIds[i];
         if(!PositionSelectByTicket(ticket))
            EraseIndex(i);
        }
     }

public:
   TrailingManager():m_symbol(""),m_magic(0),m_debug(false)
     {
      ArrayResize(m_ticketIds,0);
      ArrayResize(m_peakPrices,0);
      ArrayResize(m_troughPrices,0);
      ArrayResize(m_entryTimes,0);
     }

   void Init(const string symbol,const int magic,const bool debug)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_debug=debug;
     }

   void TrailAll(CTrade &trade,const double startPoints,const double stepPoints,const double atrFactor,
                 const double beTriggerATR,const double beOffsetPoints,const double chandelierATR,
                 const int chandelierPeriod,const int maxBarsInTrade,const double givebackPct,
                 IndicatorSuite &indicators)
     {
      CleanupStale();
      double point=_Point;
      int tfSeconds=PeriodSeconds(indicators.PrimaryTimeframe());
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol)
            continue;
         if(m_magic>0 && (int)PositionGetInteger(POSITION_MAGIC)!=m_magic)
            continue;
         ENUM_POSITION_TYPE type=(ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP);
         double current=PositionGetDouble(POSITION_PRICE_CURRENT);
         datetime entryTime=(datetime)PositionGetInteger(POSITION_TIME);

         EnsureState(ticket,open,entryTime);
         int idx=FindIndex(ticket);
         UpdateExtrema(idx,type,current);

         double profitPoints=(type==POSITION_TYPE_BUY)?(current-open)/point:(open-current)/point;
         double newSL=sl;
         double atr=indicators.ATR(0);
         double atrPoints=(atr>0.0)?(atr/point):0.0;

         bool shouldClose=false;
         if(maxBarsInTrade>0 && tfSeconds>0 && idx>=0)
           {
            int bars=(int)((TimeCurrent()-m_entryTimes[idx])/tfSeconds);
            if(bars>=maxBarsInTrade)
               shouldClose=true;
           }
         if(!shouldClose && givebackPct>0.0 && idx>=0)
           {
            double mfePoints=0.0;
            double givebackPoints=0.0;
            if(type==POSITION_TYPE_BUY)
              {
               mfePoints=(m_peakPrices[idx]-open)/point;
               givebackPoints=(m_peakPrices[idx]-current)/point;
              }
            else
              {
               mfePoints=(open-m_troughPrices[idx])/point;
               givebackPoints=(current-m_troughPrices[idx])/point;
              }
            if(mfePoints>0.0 && givebackPoints>0.0 && givebackPoints/mfePoints>=givebackPct)
               shouldClose=true;
           }
         if(shouldClose)
           {
            if(!trade.PositionClose(ticket))
               GuardianUtils::PrintDebug("Failed to close ticket "+IntegerToString((int)ticket)+" via guard",m_debug);
            else
               EraseIndex(idx);
            continue;
           }

         if(beTriggerATR>0.0 && beOffsetPoints>0.0 && atrPoints>0.0 && profitPoints>=beTriggerATR*atrPoints)
           {
            if(type==POSITION_TYPE_BUY)
               newSL=MathMax(newSL,open+beOffsetPoints*point);
            else
               newSL=MathMin(newSL,open-beOffsetPoints*point);
           }

         if(profitPoints>=startPoints)
           {
            if(type==POSITION_TYPE_BUY)
               newSL=MathMax(newSL,current-stepPoints*point);
            else
               newSL=MathMin(newSL,current+stepPoints*point);

            if(chandelierATR>0.0 && chandelierPeriod>0)
              {
               double chandStop=0.0;
               if(type==POSITION_TYPE_BUY)
                 {
                  double highest=indicators.DonchianHigh(0,chandelierPeriod);
                  chandStop=highest-chandelierATR*atr;
                  newSL=MathMax(newSL,chandStop);
                 }
               else
                 {
                  double lowest=indicators.DonchianLow(0,chandelierPeriod);
                  chandStop=lowest+chandelierATR*atr;
                  newSL=MathMin(newSL,chandStop);
                 }
              }
           }
         else if(atrFactor>0.0 && atr>0.0)
           {
            double cap=atrFactor*atr;
            if(type==POSITION_TYPE_BUY)
               newSL=MathMax(newSL,open-cap);
            else
               newSL=MathMin(newSL,open+cap);
           }

         if(newSL!=sl)
           {
            if(type==POSITION_TYPE_BUY && newSL>current)
               newSL=current-stepPoints*point;
            if(type==POSITION_TYPE_SELL && newSL<current)
               newSL=current+stepPoints*point;
            newSL=NormalizeDouble(newSL,(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS));
            if(newSL!=sl)
              {
               if(!trade.PositionModify(ticket,newSL,tp))
                  GuardianUtils::PrintDebug("Failed to trail ticket "+IntegerToString((int)ticket),m_debug);
              }
           }
        }
     }
  };

#endif // XAU_GUARDIAN_TRAILING_MQH
