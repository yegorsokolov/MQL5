#ifndef XAU_GUARDIAN_STRATEGY_MQH
#define XAU_GUARDIAN_STRATEGY_MQH

#include <Trade/Trade.mqh>
#include <Object.mqh>
#include "Utils.mqh"
#include "RiskManager.mqh"
#include "Positioning.mqh"
#include "Indicators.mqh"
#include "OnlineLearner.mqh"
#include "Trailing.mqh"
#include "Analytics.mqh"
#include "news/calendar_native.mqh"
#include "filters/liquidity_spread.mqh"

class OnlineLearnerHandle
  {
private:
   OnlineLearner *m_ptr;

public:
   OnlineLearnerHandle():m_ptr(NULL){}

   void Bind(OnlineLearner &learner)
     {
      m_ptr=&learner;
     }

   bool IsReady() const
     {
      return(m_ptr!=NULL);
     }

   double Score(const double &features[]) const
     {
      if(m_ptr==NULL)
         return 0.5;
      return (*m_ptr).Score(features);
     }

   void Update(const double &features[],const double label)
     {
      if(m_ptr==NULL)
         return;
      (*m_ptr).Update(features,label);
     }
  };

class StrategyEngine
  {
private:
   // --- Regime enums
   enum Regime { REGIME_TREND=0, REGIME_MEAN=1 };
   enum RegimeMode { MODE_AUTO=0, MODE_TREND=1, MODE_MEAN=2 };

   // --- Collaborators (objects, not pointers)
   string           m_symbol;
   int              m_magic;
   CTrade           m_trade;
   RiskManager     *m_risk;
   Positioning     *m_positioning;
   IndicatorSuite  *m_indicators;
   OnlineLearnerHandle m_learner;
   TrailingManager *m_trailing;
   Analytics       *m_analytics;

   // --- General inputs
   bool    m_debug;
   bool    m_allowLongs;
   bool    m_allowShorts;
   double  m_fixedTP;
   double  m_fixedSL;
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

   // --- Regime inputs
   double  m_adxTrend;
   double  m_adxMR;
   double  m_adxRegime;
   double  m_volRegime;
   double  m_rsiMRBuy;
   double  m_rsiMRSell;
   double  m_atrTrendSL;
   double  m_atrTrendTP;
   double  m_atrMRSL;
   double  m_atrMRTP;
   int     m_regimeMode;

   // --- Exit guard inputs
   double  m_minLearnerExit;
   int     m_exitConfirmBars;
   double  m_adxFloor;

   // --- Session/news controls
   bool    m_londonNYOnly;
   int     m_londonStart;
   int     m_londonEnd;
   int     m_nyStart;
   int     m_nyEnd;
   int     m_newsFreezeMinutes;
   bool    m_useNewsCalendar;
   string  m_manualNewsFile;
   datetime m_newsStarts[];
   datetime m_newsEnds[];
   GuardianNewsCalendar m_calendar;
   int     m_newsLookaheadMinutes;
   datetime m_manualNewsTimestamp;
   bool    m_manualNewsMissingLogged;

   // --- Trailing extras
   double  m_beTriggerATR;
   double  m_beOffsetPoints;
   double  m_chandelierATR;
   int     m_chandelierPeriod;
   int     m_maxBarsInTrade;
   double  m_givebackPct;

   // --- Position controls
   int     m_maxPositionsPerSide;
   int     m_maxRetries;

   // --- Flip-guard tracking
   ulong   m_guardTickets[];
   int     m_guardCounts[];

   // --- Liquidity filter
   LiquiditySpreadFilter m_liquidityFilter;
   double  m_minBookVolume;
   int     m_bookDepthLevels;

   // --- Trade density control
   int     m_maxTradesPerHour;
   int     m_minMinutesBetweenTrades;
   datetime m_recentEntries[];

   // ---------------------- helpers ----------------------

   bool ParseMinutesOverride(const string text,int &minutes) const
     {
      string cleaned = GuardianUtils::Trim(text);
      if(StringLen(cleaned)==0) return false;
      for(int i=0;i<StringLen(cleaned);++i)
        {
         int ch = StringGetCharacter(cleaned,i);
         if(ch<'0' || ch>'9') return false;
        }
      minutes = (int)StringToInteger(cleaned);
      if(minutes<0) return false;
      return true;
     }

   void CleanupGuards()
     {
      for(int i=ArraySize(m_guardTickets)-1;i>=0;--i)
        {
         ulong ticket=m_guardTickets[i];
         if(!PositionSelectByTicket(ticket))
            EraseGuard(i);
        }
     }

   void EraseGuard(const int idx)
     {
      int last=ArraySize(m_guardTickets)-1;
      if(idx<0 || last<0) return;
      if(idx!=last)
        {
         m_guardTickets[idx]=m_guardTickets[last];
         m_guardCounts[idx]=m_guardCounts[last];
        }
      ArrayResize(m_guardTickets,last);
      ArrayResize(m_guardCounts,last);
     }

   int GuardIndex(const ulong ticket) const
     {
      int total=ArraySize(m_guardTickets);
      for(int i=0;i<total;++i)
         if(m_guardTickets[i]==ticket) return i;
      return -1;
     }

   void ResetGuard(const ulong ticket)
     {
      int idx=GuardIndex(ticket);
      if(idx==-1) return;
      m_guardCounts[idx]=0;
     }

   void IncrementGuard(const ulong ticket)
     {
      int idx=GuardIndex(ticket);
      if(idx==-1)
        {
         int size=ArraySize(m_guardTickets);
         ArrayResize(m_guardTickets,size+1);
         ArrayResize(m_guardCounts,size+1);
         m_guardTickets[size]=ticket;
         m_guardCounts[size]=1;
        }
      else
        {
         m_guardCounts[idx]++;
        }
     }

   void PruneRecentEntries(const datetime now)
     {
      int total=ArraySize(m_recentEntries);
      int keep=0;
      for(int i=0;i<total;++i)
        {
         if(now-m_recentEntries[i]<=3600)
           {
            m_recentEntries[keep]=m_recentEntries[i];
            keep++;
           }
        }
      ArrayResize(m_recentEntries,keep);
     }

   bool TradeDensityAllows(const datetime now)
     {
      if(m_maxTradesPerHour<=0 && m_minMinutesBetweenTrades<=0)
         return true;
      PruneRecentEntries(now);
      int total=ArraySize(m_recentEntries);
      if(m_maxTradesPerHour>0 && total>=m_maxTradesPerHour)
         return false;
      if(m_minMinutesBetweenTrades>0 && total>0)
        {
         datetime last=m_recentEntries[total-1];
         if((now-last)<(m_minMinutesBetweenTrades*60))
            return false;
        }
      return true;
     }

   void RegisterTradeTimestamp(const datetime now)
     {
      PruneRecentEntries(now);
      int size=ArraySize(m_recentEntries);
      ArrayResize(m_recentEntries,size+1);
      m_recentEntries[size]=now;
     }

   bool MarginCheck(const ENUM_ORDER_TYPE type,const double lot,const double price,const double /*sl*/) const
     {
      double margin=0.0;
      if(!OrderCalcMargin(type,m_symbol,lot,price,margin)) return false;
      double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      return (freeMargin>margin*1.1);
     }

   bool SessionAllowed(const datetime time) const
     {
      if(!m_londonNYOnly) return true;
      if(GuardianUtils::IsWithinHours(time,m_londonStart,m_londonEnd)) return true;
      if(GuardianUtils::IsWithinHours(time,m_nyStart,m_nyEnd)) return true;
      return false;
     }

   bool NewsBlocked(const datetime time) const
     {
      if(m_newsFreezeMinutes<=0)
        return (m_useNewsCalendar && m_calendar.IsBlocked(time));

      int total=ArraySize(m_newsStarts);
      for(int i=0;i<total;++i)
        {
         if(time>=m_newsStarts[i] && time<=m_newsEnds[i])
            return true;
        }
      if(m_useNewsCalendar && m_calendar.IsBlocked(time)) return true;
      return false;
     }

   bool TimeBlocked() const
     {
      datetime now=TimeCurrent();
      if(m_nightBlock && GuardianUtils::IsWithinHours(now,m_nightStart,m_nightEnd)) return true;
      if(!SessionAllowed(now)) return true;
      if(NewsBlocked(now)) return true;
      return false;
     }

   void LoadManualNewsWindows()
     {
      if(StringLen(m_manualNewsFile)==0 || m_newsFreezeMinutes<=0)
        {
         m_manualNewsTimestamp=0;
         ArrayResize(m_newsStarts,0);
         ArrayResize(m_newsEnds,0);
         return;
        }

      string path=GuardianUtils::FilesRoot()+m_manualNewsFile;
      if(!GuardianUtils::FileExists(path))
        {
         if(!m_manualNewsMissingLogged)
            GuardianUtils::PrintDebug("Manual news file not found: "+m_manualNewsFile+
                                      ". See ManualNewsExample.csv for the expected format.",m_debug);
         m_manualNewsMissingLogged=true;
         m_manualNewsTimestamp=0;
         ArrayResize(m_newsStarts,0);
         ArrayResize(m_newsEnds,0);
         return;
        }

      datetime modified=GuardianUtils::FileModifiedTime(path);
      if(modified>0 && m_manualNewsTimestamp>0 && modified==m_manualNewsTimestamp && ArraySize(m_newsStarts)>0)
         return;

      string text;
      if(!GuardianUtils::LoadText(path,text))
        {
         if(!m_manualNewsMissingLogged)
            GuardianUtils::PrintDebug("Manual news file not readable: "+m_manualNewsFile+", check permissions.",m_debug);
         m_manualNewsMissingLogged=true;
         m_manualNewsTimestamp=0;
         ArrayResize(m_newsStarts,0);
         ArrayResize(m_newsEnds,0);
         return;
        }

      m_manualNewsMissingLogged=false;
      m_manualNewsTimestamp=modified;
      ArrayResize(m_newsStarts,0);
      ArrayResize(m_newsEnds,0);

      string lines[];
      int count=StringSplit(text,'\n',lines);
      for(int i=0;i<count;++i)
        {
         string line=GuardianUtils::Trim(lines[i]);
         if(StringLen(line)==0) continue;
         if(StringGetCharacter(line,0)=='#') continue;

         string parts[];
         int partsCount=StringSplit(line,',',parts);
         string stamp=(partsCount>0)?GuardianUtils::Trim(parts[0]):"";
         if(StringLen(stamp)==0) continue;

         datetime ts=(datetime)StringToTime(stamp);
         if(ts<=0) continue;

         int freezeMinutes=m_newsFreezeMinutes;
         if(partsCount>1)
           {
            int parsed=0;
            if(ParseMinutesOverride(parts[1],parsed)) freezeMinutes=parsed;
           }
         if(freezeMinutes<=0) continue;

         datetime startTime=ts-(freezeMinutes*60);
         datetime endTime  =ts+(freezeMinutes*60);

         int sz=ArraySize(m_newsStarts);
         ArrayResize(m_newsStarts,sz+1);
         ArrayResize(m_newsEnds,sz+1);
         m_newsStarts[sz]=startTime;
         m_newsEnds[sz]=endTime;
        }
     }

   Regime DetermineRegime(const double adx,const double vol) const
     {
      if(m_regimeMode==MODE_TREND) return REGIME_TREND;
      if(m_regimeMode==MODE_MEAN)  return REGIME_MEAN;
      if(adx>=m_adxRegime && vol>=m_volRegime) return REGIME_TREND;
      return REGIME_MEAN;
     }

   void ComputeSignals(const Regime regime,const double learnerProb,const double trend,const double adx,
                       const bool squeeze,const double squeezeBreak,const double rsiH1,const double close,
                       const double atrPoints,double &slPoints,double &tpPoints,bool &longSignal,bool &shortSignal)
     {
      longSignal=false;
      shortSignal=false;
      slPoints=m_fixedSL;
      tpPoints=m_fixedTP;

      if(m_indicators==NULL)
         return;

      IndicatorSuite &ind=*m_indicators;

      if(regime==REGIME_TREND)
        {
         double donchianHigh = ind.DonchianHigh(0,20);
         double donchianLow  = ind.DonchianLow(0,20);
         double keltnerUpper = ind.KeltnerUpper(0,1.5);
         double keltnerLower = ind.KeltnerLower(0,1.5);
         double emaSlope     = ind.EMASlopeTF2();

         if(m_allowLongs)
           {
            bool filters     = (adx>=m_adxTrend && trend>=m_minTrend && rsiH1>=m_rsiLong);
            bool breakout    = (close>=donchianHigh || close>=keltnerUpper);
            bool directionOk = (squeezeBreak>=0.0 && emaSlope>=0.0);
            if(filters && breakout && directionOk && learnerProb>=m_minLearnerProb)
               longSignal=true;
           }
         if(m_allowShorts)
           {
            double learnerShort=1.0-learnerProb;
            bool filters     = (adx>=m_adxTrend && trend<=-m_minTrend && rsiH1<=m_rsiShort);
            bool breakout    = (close<=donchianLow || close<=keltnerLower);
            bool directionOk = (squeezeBreak<=0.0 && emaSlope<=0.0);
            if(filters && breakout && directionOk && learnerShort>=m_minLearnerProb)
               shortSignal=true;
           }

         if(m_atrTrendSL>0.0 && atrPoints>0.0) slPoints=m_atrTrendSL*atrPoints;
         if(m_atrTrendTP>0.0 && atrPoints>0.0) tpPoints=m_atrTrendTP*atrPoints;
        }
      else
        {
         double bbUpper = ind.BollingerUpper(0);
         double bbLower = ind.BollingerLower(0);
         double rsiFast = ind.RSI1(0);
         bool baseFilter = (adx<=m_adxMR && squeeze);

         if(m_allowLongs)
           {
            if(baseFilter && close<=bbLower && rsiFast<=m_rsiMRBuy && learnerProb>=m_minLearnerProb)
               longSignal=true;
           }
         if(m_allowShorts)
           {
            double learnerShort=1.0-learnerProb;
            if(baseFilter && close>=bbUpper && rsiFast>=m_rsiMRSell && learnerShort>=m_minLearnerProb)
               shortSignal=true;
           }

         if(m_atrMRSL>0.0 && atrPoints>0.0) slPoints=m_atrMRSL*atrPoints;
         if(m_atrMRTP>0.0 && atrPoints>0.0) tpPoints=m_atrMRTP*atrPoints;
        }
     }

      void ApplyDirectionFlipGuard(CTrade &trade,
                                   const double learnerProb,
                                   const double trend,
                                   const double emaSlope,
                                   const double adx)
      {
         CleanupGuards();
      
         // iterate by index -> get ticket -> select by ticket
         for(int i = PositionsTotal()-1; i >= 0; --i)
         {
            ulong ticket_i = PositionGetTicket(i);
            if(ticket_i == 0)                 continue;
            if(!PositionSelectByTicket(ticket_i)) continue;   // select the position
      
            if(PositionGetString(POSITION_SYMBOL) != m_symbol)                   continue;
            if(m_magic > 0 && (int)PositionGetInteger(POSITION_MAGIC) != m_magic) continue;
      
            // now you can read properties of the selected position
            ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            int dir = (type == POSITION_TYPE_BUY) ? 1 : -1;
      
            int triggers = 0;
            if((dir > 0 && trend < 0.0) || (dir < 0 && trend > 0.0)) triggers++;
            if((dir > 0 && emaSlope < 0.0) || (dir < 0 && emaSlope > 0.0)) triggers++;
            double exitProb = (dir > 0) ? learnerProb : (1.0 - learnerProb);
            if(exitProb < m_minLearnerExit) triggers++;
            if(adx < m_adxFloor)           triggers++;
      
            if(triggers >= 2)
            {
               IncrementGuard(ticket);
               int idx = GuardIndex(ticket);
               if(idx != -1 && m_guardCounts[idx] >= m_exitConfirmBars)
               {
                  string sym = PositionGetString(POSITION_SYMBOL);
                  if(!trade.PositionClose(sym))
                     GuardianUtils::PrintDebug("Direction flip guard failed to close position: " + sym, m_debug);
                  else
                     EraseGuard(idx);
               }
            }
            else
            {
               ResetGuard(ticket);
            }
         }
      }

public:
   // --- Constructor with sane defaults
   StrategyEngine()
     : m_symbol(""),
       m_magic(0),
       m_trade(),
       m_risk(NULL),
       m_positioning(NULL),
       m_indicators(NULL),
       m_learner(),
       m_trailing(NULL),
       m_analytics(NULL),
       m_debug(false),
       m_allowLongs(true),
       m_allowShorts(true),
       m_fixedTP(1200.0),
       m_fixedSL(850.0),
       m_trailStart(700.0),
       m_trailStep(200.0),
       m_minTrend(0.6),
       m_minADX(20.0),
       m_rsiLong(55.0),
       m_rsiShort(45.0),
       m_spreadLimit(40.0),
       m_minLearnerProb(0.55),
       m_nightBlock(false),
       m_nightStart(22),
       m_nightEnd(1),
       m_atrAdverseFactor(0.0),
       m_lastBarTime(0),
       m_adxTrend(25.0),
       m_adxMR(18.0),
       m_adxRegime(22.0),
       m_volRegime(0.001),
       m_rsiMRBuy(35.0),
       m_rsiMRSell(65.0),
       m_atrTrendSL(0.0),
       m_atrTrendTP(0.0),
       m_atrMRSL(0.0),
       m_atrMRTP(0.0),
       m_regimeMode(MODE_AUTO),
       m_minLearnerExit(0.4),
       m_exitConfirmBars(2),
       m_adxFloor(15.0),
       m_londonNYOnly(false),
       m_londonStart(7),
       m_londonEnd(17),
       m_nyStart(13),
       m_nyEnd(22),
       m_newsFreezeMinutes(0),
       m_useNewsCalendar(false),
       m_newsLookaheadMinutes(720),
       m_manualNewsTimestamp(0),
       m_manualNewsMissingLogged(false),
       m_beTriggerATR(0.0),
       m_beOffsetPoints(0.0),
       m_chandelierATR(0.0),
       m_chandelierPeriod(20),
       m_maxBarsInTrade(0),
       m_givebackPct(0.0),
       m_maxPositionsPerSide(1),
       m_maxRetries(0),
       m_minBookVolume(0.0),
       m_bookDepthLevels(0),
       m_maxTradesPerHour(0),
       m_minMinutesBetweenTrades(0)
   {
      ArrayResize(m_newsStarts,0);
      ArrayResize(m_newsEnds,0);
      ArrayResize(m_guardTickets,0);
      ArrayResize(m_guardCounts,0);
      ArrayResize(m_recentEntries,0);
   }

   // --- Init all collaborators and settings
   bool Init(const string symbol,const int magic,CTrade &trade,RiskManager &risk,Positioning &positioning,
             IndicatorSuite &indicators,OnlineLearner &learner,TrailingManager &trailing,Analytics &analytics,
             const bool allowLongs,const bool allowShorts,const double tpPoints,const double slPoints,
             const double trailStart,const double trailStep,const double minTrend,const double minAdx,
             const double rsiLong,const double rsiShort,const double spreadLimit,const double minProb,
             const bool nightBlock,const int nightStart,const int nightEnd,const double adverseFactor,
             const bool debug,const double adxTrend,const double adxMR,const double adxRegime,const double volRegime,
             const double rsiMRBuy,const double rsiMRSell,const double atrTrendSL,const double atrTrendTP,
             const double atrMRSL,const double atrMRTP,const int regimeMode,const double minLearnerExit,
             const int exitConfirmBars,const double adxFloor,const bool londonNYOnly,const int londonStart,
             const int londonEnd,const int nyStart,const int nyEnd,const int newsFreezeMinutes,
             const bool useNewsCalendar,const string manualNewsFile,const int newsLookaheadMinutes,
             const double minBookVolume,const int bookDepthLevels,const int maxPositionsPerSide,
             const double beTriggerATR,const double beOffsetPoints,const double chandelierATR,const int chandelierPeriod,
             const int maxBarsInTrade,const double givebackPct,const int maxRetries,
             const int maxTradesPerHour,const int minMinutesBetweenTrades)
     {
      m_symbol=symbol;
      m_magic=magic;

      // bind collaborators into members
      m_trade       = trade;
      m_risk        = &risk;
      m_positioning = &positioning;
      m_indicators  = &indicators;
      m_learner.Bind(learner);
      m_trailing    = &trailing;
      m_analytics   = &analytics;

      m_allowLongs=allowLongs;
      m_allowShorts=allowShorts;
      m_fixedTP=tpPoints;
      m_fixedSL=slPoints;
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

      m_adxTrend=adxTrend;
      m_adxMR=adxMR;
      m_adxRegime=adxRegime;
      m_volRegime=volRegime;
      m_rsiMRBuy=rsiMRBuy;
      m_rsiMRSell=rsiMRSell;
      m_atrTrendSL=atrTrendSL;
      m_atrTrendTP=atrTrendTP;
      m_atrMRSL=atrMRSL;
      m_atrMRTP=atrMRTP;
      m_regimeMode=regimeMode;

      m_minLearnerExit=minLearnerExit;
      m_exitConfirmBars=MathMax(1,exitConfirmBars);
      m_adxFloor=adxFloor;

      m_londonNYOnly=londonNYOnly;
      m_londonStart=londonStart;
      m_londonEnd=londonEnd;
      m_nyStart=nyStart;
      m_nyEnd=nyEnd;

      m_newsFreezeMinutes=newsFreezeMinutes;
      m_useNewsCalendar=useNewsCalendar;
      m_manualNewsFile=manualNewsFile;
      m_newsLookaheadMinutes=MathMax(60,newsLookaheadMinutes);
      m_manualNewsTimestamp=0;
      m_manualNewsMissingLogged=false;

      m_maxPositionsPerSide=MathMax(1,maxPositionsPerSide);
      m_beTriggerATR=beTriggerATR;
      m_beOffsetPoints=beOffsetPoints;
      m_chandelierATR=chandelierATR;
      m_chandelierPeriod=chandelierPeriod;
      m_maxBarsInTrade=maxBarsInTrade;
      m_givebackPct=givebackPct;

      m_maxRetries=MathMax(0,maxRetries);
      m_minBookVolume=MathMax(0.0,minBookVolume);
      m_bookDepthLevels=MathMax(0,bookDepthLevels);
      m_maxTradesPerHour=MathMax(0,maxTradesPerHour);
      m_minMinutesBetweenTrades=MathMax(0,minMinutesBetweenTrades);
      ArrayResize(m_recentEntries,0);

      // init liquidity filter
      m_liquidityFilter.Init(symbol,m_spreadLimit,m_minBookVolume,m_bookDepthLevels,m_debug);

      // init news calendar
      if(m_useNewsCalendar)
        {
         int freeze=(m_newsFreezeMinutes>0)?m_newsFreezeMinutes:6;
         int padding=MathMax(1,freeze);
         m_calendar.Init(symbol,padding,padding,m_newsLookaheadMinutes,m_debug);
         m_calendar.SetImportanceThreshold(CALENDAR_IMPORTANCE_HIGH);
         m_calendar.Refresh(true);
        }

      LoadManualNewsWindows();
      m_lastBarTime=0;
      return true;
     }

   // --- Manage open positions (trailing + flip guard)
   void ManagePositions(CTrade &trade_ref)
     {
      if(m_indicators==NULL || !m_learner.IsReady() || m_positioning==NULL || m_trailing==NULL)
         return;

      double features[];
      double learnerProb=0.5;
      double trend=0.0;
      double emaSlope=0.0;
      double adx=0.0;

      if((*m_indicators).BuildFeatureVector(0,features))
        {
         learnerProb = m_learner.Score(features);
         trend       = (*m_indicators).TrendScore(0);
         emaSlope    = (*m_indicators).EMASlopeTF2();
         adx         = (*m_indicators).ADX(0);
        }

      (*m_positioning).EnforceLotRatio(trade_ref);
      (*m_trailing).TrailAll(trade_ref,m_trailStart,m_trailStep,m_atrAdverseFactor,
                           m_beTriggerATR,m_beOffsetPoints,m_chandelierATR,m_chandelierPeriod,
                           m_maxBarsInTrade,m_givebackPct,*m_indicators);

      ApplyDirectionFlipGuard(trade_ref,learnerProb,trend,emaSlope,adx);
     }

   // --- Entry logic
   void TryEnter()
     {
      if(m_risk==NULL || m_positioning==NULL || m_indicators==NULL || !m_learner.IsReady())
         return;

      if((*m_risk).IsTradingBlocked())
        {
         GuardianUtils::PrintDebug("Entry blocked by risk manager",m_debug);
         return;
        }
      if(TimeBlocked())
        {
         GuardianUtils::PrintDebug("Entry blocked by session/news filter",m_debug);
         return;
        }

      double spread=0.0;
      if(!m_liquidityFilter.IsSpreadAcceptable(spread))
        {
         GuardianUtils::PrintDebug("Spread too high: "+DoubleToString(spread,1),m_debug);
         return;
        }
      if(!m_liquidityFilter.IsLiquidityAcceptable())
        {
         GuardianUtils::PrintDebug("Liquidity filter blocked entry",m_debug);
         return;
        }

      datetime now=TimeCurrent();
      if(!TradeDensityAllows(now))
        {
         GuardianUtils::PrintDebug("Trade density guard active",m_debug);
         return;
      }

      double features[];
      if(!(*m_indicators).BuildFeatureVector(0,features))
         return;

      double learnerProb = m_learner.Score(features);
      double trend       = (*m_indicators).TrendScore(0);
      double adx         = (*m_indicators).ADX(0);
      bool   squeeze     = (*m_indicators).IsSqueezeActive(0);
      double squeezeBreak= (*m_indicators).SqueezeBreakoutScore(0);
      double rsiH1       = (*m_indicators).RSI2(0);
      double close       = (*m_indicators).Close(0);
      double vol         = (*m_indicators).RealizedVolatility();

      double dailyLossLeft = (*m_risk).DailyLossLeftAmount();
      if(dailyLossLeft<=0.0)
        {
         GuardianUtils::PrintDebug("Daily loss buffer exhausted",m_debug);
         return;
        }

      double atrSmoothed = (*m_indicators).ATREWMA(0.06);
      double atrRaw      = (*m_indicators).ATR(0);
      double point       = SymbolInfoDouble(m_symbol,SYMBOL_POINT);
      double atrEwmaPts  = (atrSmoothed>0.0?atrSmoothed:(atrRaw>0.0?atrRaw:0.0))/point;
      double atrBasePts  = (atrRaw>0.0)?(atrRaw/point):atrEwmaPts;

      Regime regime = DetermineRegime(adx,vol);
      double slPoints=0.0, tpPoints=0.0;
      bool longSignal=false, shortSignal=false;
      ComputeSignals(regime,learnerProb,trend,adx,squeeze,squeezeBreak,rsiH1,close,atrEwmaPts,
                     slPoints,tpPoints,longSignal,shortSignal);

      if(!longSignal && !shortSignal) return;

      int direction = 0;
      if(longSignal && shortSignal) direction = (learnerProb>=0.5)?1:-1;
      else if(longSignal) direction=1;
      else direction=-1;

      if((*m_positioning).HasOppositePosition(direction))
        {
         GuardianUtils::PrintDebug("Opposite position prevents hedge",m_debug);
         return;
        }
      if(m_maxPositionsPerSide>0 && (*m_positioning).ActiveDirectionCount(direction)>=m_maxPositionsPerSide)
        {
         GuardianUtils::PrintDebug("Max positions per side reached",m_debug);
         return;
        }

      double lot = (*m_positioning).ComputeNextLot(atrBasePts,slPoints,atrEwmaPts,dailyLossLeft);
      if(lot<=0.0) return;

      int digits = (int)SymbolInfoInteger(m_symbol,SYMBOL_DIGITS);
      double slUse = (slPoints>0.0)?slPoints:m_fixedSL;
      double tpUse = (tpPoints>0.0)?tpPoints:m_fixedTP;

      bool executed=false;
      for(int attempt=0;attempt<=m_maxRetries && !executed;++attempt)
        {
         if(direction>0)
           {
            double ask=SymbolInfoDouble(m_symbol,SYMBOL_ASK);
            double sl = NormalizeDouble(ask - slUse*point, digits);
            double tp = NormalizeDouble(ask + tpUse*point, digits);
            if(!MarginCheck(ORDER_TYPE_BUY,lot,ask,sl))
              {
               GuardianUtils::PrintDebug("Margin check failed for buy",m_debug);
               return;
              }
            executed = m_trade.Buy(lot,m_symbol,ask,sl,tp);
           }
         else
           {
            double bid=SymbolInfoDouble(m_symbol,SYMBOL_BID);
            double sl = NormalizeDouble(bid + slUse*point, digits);
            double tp = NormalizeDouble(bid - tpUse*point, digits);
            if(!MarginCheck(ORDER_TYPE_SELL,lot,bid,sl))
              {
               GuardianUtils::PrintDebug("Margin check failed for sell",m_debug);
               return;
              }
            executed = m_trade.Sell(lot,m_symbol,bid,sl,tp);
           }

         if(!executed)
           {
            uint retcode = m_trade.ResultRetcode();
            if(retcode!=TRADE_RETCODE_REQUOTE && retcode!=TRADE_RETCODE_PRICE_CHANGED)
               break; // do not retry on other errors
           }
        }

      if(executed)
        {
         (*m_positioning).RegisterExecutedLot(lot);
         (*m_risk).RegisterExecutedLot(lot);
         if(m_analytics!=NULL)
            (*m_analytics).SnapshotPositions();
         RegisterTradeTimestamp(TimeCurrent());
         GuardianUtils::AppendLog("orders.log",
           StringFormat("%s %s %.2f",
                        TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
                        (direction>0)?"BUY":"SELL", lot));
        }
     }

   // --- Online learning + risk heartbeat on new bar
   void UpdateLearner()
     {
      if(m_indicators==NULL || !m_learner.IsReady() || m_risk==NULL)
         return;

      datetime barTime = iTime((*m_indicators).Symbol(), (*m_indicators).PrimaryTimeframe(), 0);
      if(barTime==0) return;

      if(m_lastBarTime==0)
        {
         m_lastBarTime=barTime;
         return;
        }
      if(barTime==m_lastBarTime) return;

      double features[];
      if((*m_indicators).BuildFeatureVector(1,features))
        {
         double close0 = iClose((*m_indicators).Symbol(), (*m_indicators).PrimaryTimeframe(), 0);
         double close1 = iClose((*m_indicators).Symbol(), (*m_indicators).PrimaryTimeframe(), 1);
         double label  = (close0>close1)?1.0:0.0;
         m_learner.Update(features,label);
        }

      (*m_risk).OnBar();
      m_lastBarTime=barTime;
     }

   // --- Timer tasks
   void OnTimer()
     {
      if(m_useNewsCalendar)
         m_calendar.Refresh(false);
      LoadManualNewsWindows();
     }

   // --- Shutdown hooks
   void Shutdown()
     {
      m_liquidityFilter.Shutdown();
      if(m_useNewsCalendar)
         m_calendar.Shutdown();
     }
  };

#endif // XAU_GUARDIAN_STRATEGY_MQH
