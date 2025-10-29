#pragma once
#include "Utils.mqh"

class Positioning
  {
private:
   string   m_symbol;
   int      m_magic;
   double   m_baseLot;
   double   m_maxMultiplier;
   bool     m_debug;
   GuardianPersistedState *m_state;
   double   m_virtualBalance;
   double   m_riskFraction;

public:
   Positioning():m_symbol(""),m_magic(0),m_baseLot(0.1),m_maxMultiplier(1.9),m_debug(false),m_state(NULL),
                  m_virtualBalance(0.0),m_riskFraction(0.0)
     {
     }

   bool Init(GuardianPersistedState &state,const string symbol,const int magic,const double baseLot,
             const double maxMultiplier,const bool debug,const double virtualBalance,const double riskFraction)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_baseLot=baseLot;
      m_maxMultiplier=maxMultiplier;
      m_debug=debug;
      m_state=&state;
      m_virtualBalance=virtualBalance;
      m_riskFraction=MathMax(0.0,riskFraction);
      return true;
     }

   double ComputeNextLot(const double atrPoints,const double slPoints,const double atrEwmaPoints,
                         const double dailyLossLeft)
     {
      double minLot=0.0,maxLot=0.0,step=0.0;
      SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN,minLot);
      SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX,maxLot);
      SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP,step);
      double sessionMin=m_baseLot;
      if(m_state!=NULL && m_state.smallest_lot>0.0)
         sessionMin=MathMax(m_baseLot,m_state.smallest_lot);
      double lot=MathMax(sessionMin,m_baseLot);
      if(m_state!=NULL && m_state.smallest_lot>0.0)
         lot=MathMin(lot,m_state.smallest_lot*m_maxMultiplier);
      lot=GuardianUtils::NormalizeLot(step,MathMax(minLot,m_baseLot),maxLot,lot);

      double effectiveStop=slPoints;
      if(effectiveStop<=0.0)
         effectiveStop=atrEwmaPoints;
      if(effectiveStop<=0.0)
         effectiveStop=atrPoints;

      double tickValue=0.0;
      double tickSize=0.0;
      SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_VALUE,tickValue);
      SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE,tickSize);
      if(tickValue>0.0 && tickSize>0.0 && effectiveStop>0.0)
        {
         double pointValue=tickValue/tickSize;
         double maxRiskAmount=(m_riskFraction>0.0 && m_virtualBalance>0.0)?(m_virtualBalance*m_riskFraction):0.0;
         if(dailyLossLeft>0.0)
           {
            double throttle=dailyLossLeft*0.25;
            if(throttle>0.0)
              {
               if(maxRiskAmount>0.0)
                  maxRiskAmount=MathMin(maxRiskAmount,throttle);
               else
                  maxRiskAmount=throttle;
              }
           }
         if(pointValue>0.0 && maxRiskAmount>0.0)
           {
            double riskLot=maxRiskAmount/(effectiveStop*pointValue);
            riskLot=GuardianUtils::NormalizeLot(step,MathMax(minLot,m_baseLot),maxLot,riskLot);
            if(riskLot>0.0)
               lot=MathMin(lot,riskLot);
           }
        }
      return lot;
     }

   void RegisterExecutedLot(const double lot)
     {
      if(m_state==NULL)
         return;
      if(m_state.smallest_lot<=0.0 || lot<m_state.smallest_lot)
        {
         m_state.smallest_lot=lot;
         GuardianStateStore::Save(*m_state);
        }
     }

   bool HasOppositePosition(const int dir) const
     {
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
         if((dir>0 && type==POSITION_TYPE_SELL) || (dir<0 && type==POSITION_TYPE_BUY))
            return true;
        }
      return false;
     }

   double CurrentSmallestLot() const
     {
      if(m_state==NULL || m_state.smallest_lot<=0.0)
         return m_baseLot;
      return m_state.smallest_lot;
     }

   int ActiveDirectionCount(const int dir) const
     {
      int count=0;
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
         if((dir>0 && type==POSITION_TYPE_BUY) || (dir<0 && type==POSITION_TYPE_SELL))
            count++;
      }
      return count;
     }

   void EnforceLotRatio(CTrade &trade)
     {
      double smallest=0.0;
      double largest=0.0;
      ulong largestTicket=0;
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol)
            continue;
         if(m_magic>0 && (int)PositionGetInteger(POSITION_MAGIC)!=m_magic)
            continue;
         double lot=PositionGetDouble(POSITION_VOLUME);
         if(smallest==0.0 || lot<smallest)
            smallest=lot;
         if(lot>largest)
           {
            largest=lot;
            largestTicket=ticket;
           }
        }
      if(smallest<=0.0 || largest<=0.0)
         return;
      if(largest>smallest*m_maxMultiplier+0.000001)
        {
         GuardianUtils::PrintInfo("Lot ratio breach detected; closing ticket "+IntegerToString((int)largestTicket));
         if(!trade.PositionClose(largestTicket))
            GuardianUtils::PrintDebug("Failed to enforce lot ratio",m_debug);
        }
     }
  };
