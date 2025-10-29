#pragma once
#include <Trade/Trade.mqh>
#include "Utils.mqh"
#include "RiskManager.mqh"
#include "Positioning.mqh"
#include "Indicators.mqh"
#include "OnlineLearner.mqh"
#include "Trailing.mqh"
#include "Analytics.mqh"

class StrategyEngine
  {
private:
   string          m_symbol;
   CTrade         *m_trade;
   RiskManager    *m_risk;
   Positioning    *m_positioning;
   IndicatorSuite *m_indicators;
   OnlineLearner  *m_learner;
   TrailingManager *m_trailing;
   Analytics      *m_analytics;

   bool    m_debug;
   bool    m_allowLongs;
   bool    m_allowShorts;
   double  m_tpPoints;
   double  m_slPoints;
   double  m_trailStart;
   double  m_trailStep;
   double  m_minTrend;
   double  m_minADX;
   double  m_rsiLong;
   double  m_rsiShort;
   double  m_spreadLimit;
   double  m_minLearnerProb;
   bool    m_nightBlock;
   int     m_nightStart;
   int     m_nightEnd;
   double  m_atrAdverseFactor;
   datetime m_lastBarTime;

   bool TimeBlocked() const
     {
      if(!m_nightBlock)
         return false;
      return GuardianUtils::IsWithinHours(TimeCurrent(),m_nightStart,m_nightEnd);
     }

   bool MarginCheck(const ENUM_ORDER_TYPE type,const double lot,const double price,const double sl) const
     {
      double margin=0.0;
      if(!OrderCalcMargin(type,m_symbol,lot,price,margin))
         return false;
      double freeMargin=AccountInfoDouble(ACCOUNT_FREEMARGIN);
      return (freeMargin>margin*1.1);
     }

public:
   StrategyEngine():m_symbol(""),m_trade(NULL),m_risk(NULL),m_positioning(NULL),m_indicators(NULL),
                    m_learner(NULL),m_trailing(NULL),m_analytics(NULL),m_debug(false),m_allowLongs(true),
                    m_allowShorts(true),m_tpPoints(1200.0),m_slPoints(850.0),m_trailStart(700.0),
                    m_trailStep(200.0),m_minTrend(0.6),m_minADX(20.0),m_rsiLong(55.0),m_rsiShort(45.0),
                    m_spreadLimit(40.0),m_minLearnerProb(0.55),m_nightBlock(false),m_nightStart(22),m_nightEnd(1),
                    m_atrAdverseFactor(0.0),m_lastBarTime(0)
     {
     }

   bool Init(const string symbol,CTrade &trade,RiskManager &risk,Positioning &positioning,
             IndicatorSuite &indicators,OnlineLearner &learner,TrailingManager &trailing,Analytics &analytics,
             const bool allowLongs,const bool allowShorts,const double tpPoints,const double slPoints,
             const double trailStart,const double trailStep,const double minTrend,const double minAdx,
             const double rsiLong,const double rsiShort,const double spreadLimit,const double minProb,
             const bool nightBlock,const int nightStart,const int nightEnd,const double adverseFactor,
             const bool debug)
     {
      m_symbol=symbol;
      m_trade=&trade;
      m_risk=&risk;
      m_positioning=&positioning;
      m_indicators=&indicators;
      m_learner=&learner;
      m_trailing=&trailing;
      m_analytics=&analytics;
      m_allowLongs=allowLongs;
      m_allowShorts=allowShorts;
      m_tpPoints=tpPoints;
      m_slPoints=slPoints;
      m_trailStart=trailStart;
      m_trailStep=trailStep;
      m_minTrend=minTrend;
      m_minADX=minAdx;
      m_rsiLong=rsiLong;
      m_rsiShort=rsiShort;
      m_spreadLimit=spreadLimit;
      m_minLearnerProb=minProb;
      m_nightBlock=nightBlock;
      m_nightStart=nightStart;
      m_nightEnd=nightEnd;
      m_atrAdverseFactor=adverseFactor;
      m_debug=debug;
      m_lastBarTime=0;
      return true;
     }

   void TryEnter()
     {
      if(m_trade==NULL || m_risk==NULL || m_positioning==NULL || m_indicators==NULL || m_learner==NULL)
         return;
      if(m_risk->IsTradingBlocked())
        {
         GuardianUtils::PrintDebug("Entry blocked by risk manager",m_debug);
         return;
        }
      if(TimeBlocked())
        {
         GuardianUtils::PrintDebug("Entry blocked by session filter",m_debug);
         return;
        }
      double spread=GuardianUtils::SpreadPoints(m_symbol);
      if(spread>m_spreadLimit)
        {
         GuardianUtils::PrintDebug("Spread too high: "+DoubleToString(spread,1),m_debug);
         return;
        }
      double features[];
      if(!m_indicators->BuildFeatureVector(0,features))
         return;
      double learnerProb=m_learner->Score(features);
      double trend=m_indicators->TrendScore(0);
      double adx=m_indicators->ADX(0);
      bool squeeze=m_indicators->IsSqueezeActive(0);
      double squeezeBreak=m_indicators->SqueezeBreakoutScore(0);
      double rsiH1=m_indicators->RSI2(0);

      bool longSignal=false;
      bool shortSignal=false;

      if(m_allowLongs)
        {
         longSignal=(trend>=m_minTrend && adx>=m_minADX && rsiH1>=m_rsiLong && (!squeeze || squeezeBreak>0.0));
         if(learnerProb<m_minLearnerProb)
            longSignal=false;
        }
      if(m_allowShorts)
        {
         double learnerShort=1.0-learnerProb;
         shortSignal=(trend<=-m_minTrend && adx>=m_minADX && rsiH1<=m_rsiShort && (!squeeze || squeezeBreak<0.0));
         if(learnerShort<m_minLearnerProb)
            shortSignal=false;
        }

      if(!longSignal && !shortSignal)
         return;

      int direction=0;
      if(longSignal && shortSignal)
         direction=(learnerProb>=0.5)?1:-1;
      else if(longSignal)
         direction=1;
      else
         direction=-1;

      if(m_positioning->HasOppositePosition(direction))
        {
         GuardianUtils::PrintDebug("Opposite position prevents hedge",m_debug);
         return;
        }

      double lot=m_positioning->ComputeNextLot();
      if(lot<=0.0)
         return;

      int digits=(int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      double point=_Point;

      if(direction>0)
        {
         double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
         double sl=NormalizeDouble(ask-m_slPoints*point,digits);
         double tp=NormalizeDouble(ask+m_tpPoints*point,digits);
         if(!MarginCheck(ORDER_TYPE_BUY,lot,ask,sl))
           {
            GuardianUtils::PrintDebug("Margin check failed for buy",m_debug);
            return;
           }
         if(m_trade->Buy(lot,m_symbol,ask,sl,tp))
           {
            m_positioning->RegisterExecutedLot(lot);
            m_risk->RegisterExecutedLot(lot);
            m_analytics->SnapshotPositions();
            GuardianUtils::AppendLog("orders.log",
              StringFormat("%s BUY %.2f @ %.2f",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),lot,ask));
           }
        }
      else if(direction<0)
        {
         double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
         double sl=NormalizeDouble(bid+m_slPoints*point,digits);
         double tp=NormalizeDouble(bid-m_tpPoints*point,digits);
         if(!MarginCheck(ORDER_TYPE_SELL,lot,bid,sl))
           {
            GuardianUtils::PrintDebug("Margin check failed for sell",m_debug);
            return;
           }
         if(m_trade->Sell(lot,m_symbol,bid,sl,tp))
           {
            m_positioning->RegisterExecutedLot(lot);
            m_risk->RegisterExecutedLot(lot);
            m_analytics->SnapshotPositions();
            GuardianUtils::AppendLog("orders.log",
              StringFormat("%s SELL %.2f @ %.2f",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),lot,bid));
           }
        }
     }

   void Trail(CTrade &trade)
     {
      if(m_trailing==NULL || m_indicators==NULL)
         return;
      m_trailing->TrailAll(trade,m_trailStart,m_trailStep,m_atrAdverseFactor,*m_indicators);
     }

   void UpdateLearner()
     {
      if(m_indicators==NULL || m_learner==NULL)
         return;
      datetime barTime=iTime(m_indicators->Symbol(),m_indicators->PrimaryTimeframe(),0);
      if(barTime==0)
         return;
      if(m_lastBarTime==0)
        {
         m_lastBarTime=barTime;
         return;
        }
      if(barTime==m_lastBarTime)
         return;
      double features[];
      if(m_indicators->BuildFeatureVector(1,features))
        {
         double close0=iClose(m_indicators->Symbol(),m_indicators->PrimaryTimeframe(),0);
         double close1=iClose(m_indicators->Symbol(),m_indicators->PrimaryTimeframe(),1);
         double label=(close0>close1)?1.0:0.0;
         m_learner->Update(features,label);
        }
      m_lastBarTime=barTime;
     }
  };
