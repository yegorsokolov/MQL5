#property copyright "XAU_Guardian"
#property link      "https://example.com"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include "modules/Utils.mqh"
#include "modules/RiskManager.mqh"
#include "modules/Positioning.mqh"
#include "modules/Indicators.mqh"
#include "modules/OnlineLearner.mqh"
#include "modules/Trailing.mqh"
#include "modules/Analytics.mqh"
#include "modules/Strategy.mqh"

input double Inp_VirtualBalance      = 100000.0;
input double Inp_FloatingDD_Limit    = 0.009;
input double Inp_DailyDD_Limit       = 0.0385;
input double Inp_BaseLot             = 0.10;
input double Inp_MaxLotMultiplier    = 1.9;
input double Inp_RiskPerTrade        = 0.0;
input int    Inp_Magic               = 46015;
input bool   Inp_AllowLongs          = true;
input bool   Inp_AllowShorts         = true;
input int    Inp_SlippagePoints      = 30;
input int    Inp_TP_Points           = 1200;
input int    Inp_SL_Points           = 850;
input int    Inp_TrailStartPoints    = 700;
input int    Inp_TrailStepPoints     = 200;
input int    Inp_CooldownMinutes     = 60;
input double Inp_MinTrendScore       = 0.6;
input double Inp_MinADX              = 20.0;
input double Inp_RSI_Long            = 55.0;
input double Inp_RSI_Short           = 45.0;
input double Inp_SpreadLimit         = 40.0;
input bool   Inp_NightBlock          = false;
input int    Inp_NightStartHour      = 21;
input int    Inp_NightEndHour        = 1;
input ENUM_TIMEFRAMES Inp_TF1        = PERIOD_M15;
input ENUM_TIMEFRAMES Inp_TF2        = PERIOD_H1;
input ENUM_TIMEFRAMES Inp_TF3        = PERIOD_H4;
input int    Inp_FeatureWindow       = 120;
input bool   Inp_UseOnlineLearning   = true;
input double Inp_LearnRate           = 0.02;
input double Inp_MinLearnerProb      = 0.55;
input double Inp_AdverseATRF         = 1.2;
input bool   Inp_DebugLogs           = true;
input double Inp_ADX_Trend           = 25.0;
input double Inp_ADX_MR              = 18.0;
input double Inp_ADX_Regime          = 22.0;
input double Inp_Vol_Regime          = 0.001;
input double Inp_RSI_MR_Buy          = 35.0;
input double Inp_RSI_MR_Sell         = 65.0;
input double Inp_ATR_SL_Trend        = 1.8;
input double Inp_ATR_TP_Trend        = 3.0;
input double Inp_ATR_SL_MR           = 1.2;
input double Inp_ATR_TP_MR           = 2.0;
enum ENUM_RegimeMode { Regime_Auto=0, Regime_Trend=1, Regime_Mean=2 };
input ENUM_RegimeMode Inp_RegimeMode = Regime_Auto;
input double Inp_MinLearnerProbExit  = 0.45;
input int    Inp_ExitConfirmBars     = 2;
input double Inp_ADX_Floor           = 15.0;
input bool   Inp_LondonNYOnly        = false;
input int    Inp_LondonStartHour     = 7;
input int    Inp_LondonEndHour       = 17;
input int    Inp_NYStartHour         = 13;
input int    Inp_NYEndHour           = 22;
input int    Inp_NewsFreezeMinutes   = 6;
input bool   Inp_UseCalendar         = true;
input int    Inp_NewsLookaheadMinutes= 720;
input string Inp_ManualNewsFile      = "";
input double Inp_MinBookVolume       = 20.0;
input int    Inp_BookDepthLevels     = 3;
input int    Inp_MaxPositionsPerSide = 1;
input double Inp_BE_Trigger_ATR      = 1.0;
input double Inp_BE_Offset_Points    = 50.0;
input double Inp_Chandelier_ATR      = 2.5;
input int    Inp_Chandelier_Period   = 22;
input int    Inp_MaxBarsInTrade      = 0;
input double Inp_GivebackPct         = 0.35;
input int    Inp_MaxRetries          = 1;
input int    Inp_MaxTradesPerHour    = 3;
input int    Inp_MinMinutesBetweenTrades = 5;
input int    Inp_LossStreakLimit     = 3;
input double Inp_SoftDrawdownPct     = 0.02;
input int    Inp_SoftCooldownBars    = 5;
input int    Inp_ECS_PeriodMinutes   = 240;
input double Inp_ECS_Drawdown        = 1.5;
input double Inp_L2Lambda            = 0.0005;
input double Inp_LearnDecay          = 0.0001;
input int    Inp_SnapshotBars        = 20;

CTrade                 g_trade;
GuardianPersistedState g_state;
RiskManager            g_risk;
Positioning            g_positioning;
IndicatorSuite         g_indicators;
OnlineLearner          g_learner;
TrailingManager        g_trailing;
Analytics              g_analytics;
StrategyEngine         g_strategy;

int OnInit()
  {
   GuardianUtils::EnsurePaths();
   if(!GuardianStateStore::Load(g_state,GUARDIAN_FEATURE_COUNT))
     {
      g_state.anchor_day=GuardianUtils::BrokerDayStart(TimeCurrent());
      g_state.anchor_equity=Inp_VirtualBalance;
      g_state.daily_lock=false;
      g_state.cooldown_until=0;
      g_state.smallest_lot=0.0;
      g_state.weights_count=GUARDIAN_FEATURE_COUNT;
      ArrayInitialize(g_state.weights,0.0);
      g_state.bias=0.0;
      GuardianStateStore::Save(g_state);
     }

   g_trade.SetTypeFillingBySymbol(_Symbol);
   g_trade.SetDeviationInPoints(Inp_SlippagePoints);
   if(!g_risk.Init(g_state,_Symbol,Inp_Magic,Inp_VirtualBalance,Inp_FloatingDD_Limit,Inp_DailyDD_Limit,
                   Inp_CooldownMinutes,Inp_DebugLogs,Inp_LossStreakLimit,Inp_SoftDrawdownPct,Inp_SoftCooldownBars,
                   Inp_ECS_Drawdown/100.0,Inp_ECS_PeriodMinutes))
      return INIT_FAILED;
   g_positioning.Init(g_state,_Symbol,Inp_Magic,Inp_BaseLot,Inp_MaxLotMultiplier,Inp_DebugLogs,
                      Inp_VirtualBalance,Inp_RiskPerTrade);
   if(!g_indicators.Init(_Symbol,Inp_TF1,Inp_TF2,Inp_TF3,Inp_FeatureWindow,Inp_DebugLogs))
      return INIT_FAILED;
   g_trailing.Init(_Symbol,Inp_Magic,Inp_DebugLogs);
   if(Inp_UseOnlineLearning)
      g_learner.Init(g_state,GUARDIAN_FEATURE_COUNT,Inp_LearnRate,Inp_DebugLogs,
                     Inp_L2Lambda,Inp_LearnDecay,Inp_SnapshotBars);
   else
      g_learner.Init(g_state,GUARDIAN_FEATURE_COUNT,0.0,false,0.0,0.0,0);
   g_analytics.Init(_Symbol,Inp_Magic,Inp_DebugLogs);

   g_strategy.Init(_Symbol,Inp_Magic,g_trade,g_risk,g_positioning,g_indicators,g_learner,g_trailing,g_analytics,
                   Inp_AllowLongs,Inp_AllowShorts,Inp_TP_Points,Inp_SL_Points,Inp_TrailStartPoints,
                   Inp_TrailStepPoints,Inp_MinTrendScore,Inp_MinADX,Inp_RSI_Long,Inp_RSI_Short,
                   Inp_SpreadLimit,Inp_MinLearnerProb,Inp_NightBlock,Inp_NightStartHour,Inp_NightEndHour,
                   Inp_AdverseATRF,Inp_DebugLogs,Inp_ADX_Trend,Inp_ADX_MR,Inp_ADX_Regime,Inp_Vol_Regime,
                   Inp_RSI_MR_Buy,Inp_RSI_MR_Sell,Inp_ATR_SL_Trend,Inp_ATR_TP_Trend,
                   Inp_ATR_SL_MR,Inp_ATR_TP_MR,(int)Inp_RegimeMode,Inp_MinLearnerProbExit,
                   Inp_ExitConfirmBars,Inp_ADX_Floor,Inp_LondonNYOnly,Inp_LondonStartHour,Inp_LondonEndHour,
                   Inp_NYStartHour,Inp_NYEndHour,Inp_NewsFreezeMinutes,Inp_UseCalendar,Inp_ManualNewsFile,
                   Inp_NewsLookaheadMinutes,Inp_MinBookVolume,Inp_BookDepthLevels,Inp_MaxPositionsPerSide,
                   Inp_BE_Trigger_ATR,Inp_BE_Offset_Points,Inp_Chandelier_ATR,Inp_Chandelier_Period,
                   Inp_MaxBarsInTrade,Inp_GivebackPct,Inp_MaxRetries,Inp_MaxTradesPerHour,
                   Inp_MinMinutesBetweenTrades);

   EventSetTimer(60);
   GuardianUtils::PrintInfo("XAU_Guardian initialized");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_strategy.Shutdown();
   g_indicators.Shutdown();
   GuardianStateStore::Save(g_state);
  }

void OnTick()
  {
   g_risk.RefreshDailyAnchor();
   if(g_risk.CheckDailyDDAndAct(g_trade))
      return;
   if(g_risk.CheckFloatingDDAndAct(g_trade))
      return;
   g_strategy.ManagePositions(g_trade);
   g_strategy.TryEnter();
   g_risk.UpdateSmallestLotFromPositions();
  }

void OnTimer()
  {
   g_risk.OnTimer();
   g_strategy.OnTimer();
   g_strategy.UpdateLearner();
   g_analytics.SnapshotPositions();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
  {
   if(StringCompare(trans.symbol,_Symbol)!=0)
      return;
   if(trans.magic!=Inp_Magic && trans.magic!=0)
      return;
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
     {
      ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)trans.entry;
      if(entry==DEAL_ENTRY_OUT || entry==DEAL_ENTRY_INOUT)
        {
         double profit=trans.profit+trans.commission+trans.swap;
         g_analytics.RecordTrade(profit);
         g_risk.OnTradeClosed(profit);
         g_learner.OnTradeClosed(profit);
         g_risk.UpdateSmallestLotFromPositions();
         g_risk.ResetIfFlat();
        }
      else if(entry==DEAL_ENTRY_IN)
        {
         g_risk.RegisterExecutedLot(trans.volume);
        }
     }
  }
