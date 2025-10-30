#ifndef XAU_GUARDIAN_ANALYTICS_MQH
#define XAU_GUARDIAN_ANALYTICS_MQH

#include <Object.mqh>
#include "Utils.mqh"

struct GuardianTradeStats
  {
   int    total;
   int    wins;
   int    losses;
   double netProfit;
   double grossProfit;
   double grossLoss;
   double bestTrade;
   double worstTrade;
   GuardianTradeStats():total(0),wins(0),losses(0),netProfit(0.0),grossProfit(0.0),grossLoss(0.0),
                        bestTrade(-1e9),worstTrade(1e9)
     {
     }
  };

class Analytics : public CObject
  {
private:
   string             m_symbol;
   int                m_magic;
   bool               m_debug;
   GuardianTradeStats m_stats;

   void LogSummary()
     {
      string line=StringFormat("%s total=%d wins=%d losses=%d net=%.2f",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                               m_stats.total,m_stats.wins,m_stats.losses,m_stats.netProfit);
      GuardianUtils::AppendLog("analytics.log",line);
     }

public:
   Analytics():m_symbol(""),m_magic(0),m_debug(false)
     {
     }

   void Init(const string symbol,const int magic,const bool debug)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_debug=debug;
     }

   void RecordTrade(const double profit)
     {
      m_stats.total++;
      m_stats.netProfit+=profit;
      if(profit>=0.0)
        {
         m_stats.wins++;
         m_stats.grossProfit+=profit;
         if(profit>m_stats.bestTrade) m_stats.bestTrade=profit;
        }
      else
        {
         m_stats.losses++;
         m_stats.grossLoss+=profit;
         if(profit<m_stats.worstTrade) m_stats.worstTrade=profit;
        }
      LogSummary();
     }

   void SnapshotPositions()
     {
      int longCount=0,shortCount=0;
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
         if(type==POSITION_TYPE_BUY) longCount++; else if(type==POSITION_TYPE_SELL) shortCount++;
        }
      string line=StringFormat("%s open_long=%d open_short=%d floating=%.2f",
                               TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                               longCount,shortCount,GuardianUtils::SumUnrealized(m_symbol,m_magic));
      GuardianUtils::AppendLog("positions.log",line);
     }
  };

#endif // XAU_GUARDIAN_ANALYTICS_MQH
