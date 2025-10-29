#pragma once
#include "Utils.mqh"

class TrailingManager
  {
private:
   string m_symbol;
   int    m_magic;
   bool   m_debug;

public:
   TrailingManager():m_symbol(""),m_magic(0),m_debug(false)
     {
     }

   void Init(const string symbol,const int magic,const bool debug)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_debug=debug;
     }

   void TrailAll(CTrade &trade,const double startPoints,const double stepPoints,const double atrFactor,
                 IndicatorSuite &indicators)
     {
      double point=_Point;
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
         double profitPoints=(type==POSITION_TYPE_BUY)?(current-open)/point:(open-current)/point;
         double newSL=sl;
         if(profitPoints>=startPoints)
           {
            if(type==POSITION_TYPE_BUY)
               newSL=MathMax(sl,current-stepPoints*point);
            else
               newSL=MathMin(sl,current+stepPoints*point);
           }
         else if(atrFactor>0.0)
           {
            double features[GUARDIAN_FEATURE_COUNT];
            if(indicators.BuildFeatureVector(0,features))
              {
               double atrScaled=MathAbs(features[5])*open;
               double cap=atrScaled*atrFactor;
               if(type==POSITION_TYPE_BUY)
                  newSL=MathMax(sl,open-cap);
               else
                  newSL=MathMin(sl,open+cap);
              }
           }
         if(newSL!=sl)
           {
            if(type==POSITION_TYPE_BUY && newSL>current)
               newSL=current-stepPoints*point;
            if(type==POSITION_TYPE_SELL && newSL<current)
               newSL=current+stepPoints*point;
            newSL=NormalizeDouble(newSL,(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS));
            if(!trade.PositionModify(ticket,newSL,tp))
               GuardianUtils::PrintDebug("Failed to trail ticket "+IntegerToString((int)ticket),m_debug);
           }
        }
     }
  };
