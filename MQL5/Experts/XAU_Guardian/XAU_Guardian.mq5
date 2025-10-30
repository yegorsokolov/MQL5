//+------------------------------------------------------------------+
//|                                                  XAU_Guardian.mq5|
//|  Main EA entry wiring for the XAU Guardian bot                   |
//+------------------------------------------------------------------+
#property strict

//--- standard trading include (exposes trade/transaction enums)
#include <Trade/Trade.mqh>

//--- bot modules
#include "modules/Utils.mqh"
#include "modules/RiskManager.mqh"
#include "modules/Positioning.mqh"
#include "modules/Indicators.mqh"
#include "modules/OnlineLearner.mqh"
#include "modules/Trailing.mqh"
#include "modules/Analytics.mqh"
#include "modules/Strategy.mqh"

//==================================================================//
//============================= INPUTS =============================//
//==================================================================//
input long   Inp_Magic                    = 220392288;

// general controls
input bool   Inp_AllowLongs               = true;
input bool   Inp_AllowShorts              = true;
input double Inp_VirtualBalance           = 10000.0;
input double Inp_FloatingDD_Limit         = 0.009;   // 0.9%
input double Inp_DailyDD_Limit            = 0.0385;  // 3.85%
input int    Inp_CooldownMinutes          = 60;
input double Inp_BaseLot                  = 0.10;
input double Inp_MaxLotMultiplier         = 1.9;
input double Inp_RiskPerTrade             = 0.0;
input double Inp_TP_Points                = 1200.0;
input double Inp_SL_Points                = 850.0;
input double Inp_TrailStart               = 700.0;
input double Inp_TrailStep                = 200.0;
input double Inp_MinTrend                 = 0.6;
input double Inp_MinADX                   = 20.0;
input double Inp_RSI_Long                 = 55.0;
input double Inp_RSI_Short                = 45.0;
input double Inp_SpreadLimit              = 40.0;
input double Inp_MinLearnerProb           = 0.55;

// soft drawdown/ATR adverse handling
input double Inp_ATR_AdverseFactor        = 0.0;
input int    Inp_LossStreakLimit          = 3;
input double Inp_SoftDrawdownPct          = 0.02;
input int    Inp_SoftCooldownBars         = 3;

// session/night block
input bool   Inp_NightBlock               = false;
input int    Inp_NightStartHour           = 22;
input int    Inp_NightEndHour             = 1;

// regime inputs
input double Inp_ADX_Trend                = 25.0;
input double Inp_ADX_MR                   = 18.0;
input double Inp_ADX_Regime               = 22.0;
input double Inp_Vol_Regime               = 0.001;
input double Inp_RSI_MR_Buy               = 35.0;
input double Inp_RSI_MR_Sell              = 65.0;
input double Inp_ATR_Trend_SL             = 0.0;
input double Inp_ATR_Trend_TP             = 0.0;
input double Inp_ATR_MR_SL                = 0.0;
input double Inp_ATR_MR_TP                = 0.0;
enum RegimeExternalMode { extMODE_AUTO=0, extMODE_TREND=1, extMODE_MEAN=2 };
input RegimeExternalMode Inp_RegimeMode   = extMODE_AUTO;

// exit guard inputs
input double Inp_MinLearnerExit           = 0.40;
input int    Inp_ExitConfirmBars          = 2;
input double Inp_ADX_Floor                = 15.0;

// session/news controls
input bool   Inp_LondonNY_Only            = false;
input int    Inp_LondonStart              = 7;
input int    Inp_LondonEnd                = 17;
input int    Inp_NYStart                  = 13;
input int    Inp_NYEnd                    = 22;

input int    Inp_NewsFreezeMinutes        = 0;      // 0 = off; else +/- minutes
input bool   Inp_UseNewsCalendar          = false;
input string Inp_ManualNewsFile           = "ManualNews.csv";
input int    Inp_NewsLookaheadMinutes     = 720;

// feature stack / learner inputs
input ENUM_TIMEFRAMES Inp_TF1              = PERIOD_M15;
input ENUM_TIMEFRAMES Inp_TF2              = PERIOD_H1;
input ENUM_TIMEFRAMES Inp_TF3              = PERIOD_H4;
input int    Inp_FeatureWindow            = 120;
input bool   Inp_UseOnlineLearning        = true;
input double Inp_LearnRate                = 0.01;
input double Inp_L2Lambda                 = 0.0;
input double Inp_LearnDecay               = 0.0;
input int    Inp_SnapshotBars             = 96;

// equity curve watchdog
input int    Inp_ECS_PeriodMinutes        = 360;
input double Inp_ECS_Drawdown             = 0.02;

// liquidity / order book filter
input double Inp_MinBookVolume            = 0.0;
input int    Inp_BookDepthLevels          = 0;

// trailing extras
input double Inp_BE_TriggerATR            = 0.0;
input double Inp_BE_OffsetPoints          = 0.0;
input double Inp_ChandelierATR            = 0.0;
input int    Inp_ChandelierPeriod         = 20;
input int    Inp_MaxBarsInTrade           = 0;
input double Inp_GivebackPct              = 0.0;

// trade density / retry / position caps
input int    Inp_MaxPositionsPerSide      = 1;
input int    Inp_MaxRetries               = 0;
input int    Inp_MaxTradesPerHour         = 0;
input int    Inp_MinMinutesBetweenTrades  = 0;

// diagnostics
input bool   Inp_Debug                    = true;

//==================================================================//
//========================== GLOBAL STATE ==========================//
//==================================================================//
CTrade          g_trade;

RiskManager     g_risk;
Positioning     g_positioning;
IndicatorSuite  g_indicators;
OnlineLearner   g_learner;
TrailingManager g_trailing;
Analytics       g_analytics;
StrategyEngine  g_strategy;
GuardianPersistedState g_state;

//==================================================================//
//============================= ON_INIT ============================//
//==================================================================//
int OnInit()
{
   GuardianUtils::EnsurePaths();

   if(!GuardianStateStore::Load(g_state, GUARDIAN_FEATURE_COUNT))
      GuardianStateStore::Save(g_state);

   double virtualBalance = (Inp_VirtualBalance>0.0)?Inp_VirtualBalance:AccountInfoDouble(ACCOUNT_BALANCE);
   if(virtualBalance<=0.0)
      virtualBalance = AccountInfoDouble(ACCOUNT_EQUITY);
   if(virtualBalance<=0.0)
      virtualBalance = 10000.0;

   if(!g_risk.Init(g_state,
                   _Symbol,
                   (int)Inp_Magic,
                   virtualBalance,
                   Inp_FloatingDD_Limit,
                   Inp_DailyDD_Limit,
                   Inp_CooldownMinutes,
                   Inp_Debug,
                   Inp_LossStreakLimit,
                   Inp_SoftDrawdownPct,
                   Inp_SoftCooldownBars,
                   Inp_ECS_Drawdown,
                   Inp_ECS_PeriodMinutes))
   {
      GuardianUtils::PrintInfo("Risk manager initialisation failed");
      return(INIT_FAILED);
   }

   if(!g_positioning.Init(g_state,
                          _Symbol,
                          (int)Inp_Magic,
                          Inp_BaseLot,
                          Inp_MaxLotMultiplier,
                          Inp_Debug,
                          virtualBalance,
                          Inp_RiskPerTrade))
   {
      GuardianUtils::PrintInfo("Positioning initialisation failed");
      return(INIT_FAILED);
   }

   if(!g_indicators.Init(_Symbol,
                         Inp_TF1,
                         Inp_TF2,
                         Inp_TF3,
                         Inp_FeatureWindow,
                         Inp_Debug))
   {
      GuardianUtils::PrintInfo("Indicator initialisation failed");
      return(INIT_FAILED);
   }

   double learnRate = (Inp_UseOnlineLearning?Inp_LearnRate:0.0);
   if(!g_learner.Init(g_state,
                      GUARDIAN_FEATURE_COUNT,
                      learnRate,
                      Inp_Debug,
                      Inp_L2Lambda,
                      Inp_LearnDecay,
                      Inp_SnapshotBars))
   {
      GuardianUtils::PrintInfo("Online learner initialisation failed");
      return(INIT_FAILED);
   }

   g_trailing.Init(_Symbol,(int)Inp_Magic,Inp_Debug);
   g_analytics.Init(_Symbol,(int)Inp_Magic,Inp_Debug);

   if(!g_strategy.Init(_Symbol,
                       (int)Inp_Magic,
                       g_trade,
                       g_risk,
                       g_positioning,
                       g_indicators,
                       g_learner,
                       g_trailing,
                       g_analytics,
                       Inp_AllowLongs,
                       Inp_AllowShorts,
                       Inp_TP_Points,
                       Inp_SL_Points,
                       Inp_TrailStart,
                       Inp_TrailStep,
                       Inp_MinTrend,
                       Inp_MinADX,
                       Inp_RSI_Long,
                       Inp_RSI_Short,
                       Inp_SpreadLimit,
                       Inp_MinLearnerProb,
                       Inp_NightBlock,
                       Inp_NightStartHour,
                       Inp_NightEndHour,
                       Inp_ATR_AdverseFactor,
                       Inp_Debug,
                       Inp_ADX_Trend,
                       Inp_ADX_MR,
                       Inp_ADX_Regime,
                       Inp_Vol_Regime,
                       Inp_RSI_MR_Buy,
                       Inp_RSI_MR_Sell,
                       Inp_ATR_Trend_SL,
                       Inp_ATR_Trend_TP,
                       Inp_ATR_MR_SL,
                       Inp_ATR_MR_TP,
                       (int)Inp_RegimeMode,
                       Inp_MinLearnerExit,
                       Inp_ExitConfirmBars,
                       Inp_ADX_Floor,
                       Inp_LondonNY_Only,
                       Inp_LondonStart,
                       Inp_LondonEnd,
                       Inp_NYStart,
                       Inp_NYEnd,
                       Inp_NewsFreezeMinutes,
                       Inp_UseNewsCalendar,
                       Inp_ManualNewsFile,
                       Inp_NewsLookaheadMinutes,
                       Inp_MinBookVolume,
                       Inp_BookDepthLevels,
                       Inp_MaxPositionsPerSide,
                       Inp_BE_TriggerATR,
                       Inp_BE_OffsetPoints,
                       Inp_ChandelierATR,
                       Inp_ChandelierPeriod,
                       Inp_MaxBarsInTrade,
                       Inp_GivebackPct,
                       Inp_MaxRetries,
                       Inp_MaxTradesPerHour,
                       Inp_MinMinutesBetweenTrades))
   {
      GuardianUtils::PrintInfo("Strategy initialisation failed");
      return(INIT_FAILED);
   }

   EventSetTimer(1);

   return(INIT_SUCCEEDED);
}

//==================================================================//
//============================ ON_DEINIT ===========================//
//==================================================================//
void OnDeinit(const int reason)
{
   EventKillTimer();
   g_strategy.Shutdown();
   g_indicators.Shutdown();
   GuardianStateStore::Save(g_state);
}

//==================================================================//
//============================= ON_TICK ============================//
//==================================================================//
void OnTick()
{
   if(g_risk.CheckFloatingDDAndAct(g_trade))
      return;
   if(g_risk.CheckDailyDDAndAct(g_trade))
      return;

   // trailing/exit management
   g_strategy.ManagePositions(g_trade);

   // entries (risk/session/news guards are inside)
   g_strategy.TryEnter();
}

//==================================================================//
//============================= ON_TIMER ===========================//
//==================================================================//
void OnTimer()
{
   // light housekeeping sync
   g_risk.OnTimer();
   g_strategy.OnTimer();
   g_strategy.UpdateLearner();
   g_analytics.SnapshotPositions();
}

//==================================================================//
//====================== ON_TRADE_TRANSACTION ======================//
//==================================================================//
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest     &request,
                        const MqlTradeResult      &result)
{
   // ignore other symbols
   if(StringCompare(trans.symbol, _Symbol) != 0)
      return;

   // only react when a deal is added
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      if(trans.deal == 0)
         return;

      if(!HistoryDealSelect(trans.deal))
         return;

      const string deal_symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
      if(StringCompare(deal_symbol, _Symbol) != 0)
         return;

      // ignore other magics (allow zero magic for manual/other if you wish)
      const long deal_magic = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
      if(deal_magic != (long)Inp_Magic && deal_magic != 0)
         return;

      const ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);

      // A position was decreased/closed OR netted out
      if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_INOUT || entry == DEAL_ENTRY_OUT_BY)
      {
         const double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
                              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION)
                              + HistoryDealGetDouble(trans.deal, DEAL_SWAP);

         // housekeeping
         g_analytics.RecordTrade(profit);
         g_risk.OnTradeClosed(profit);
         g_learner.OnTradeClosed(profit);

         // keep risk/positioning state in sync (methods exist in your RiskManager)
         g_risk.UpdateSmallestLotFromPositions();
         g_risk.ResetIfFlat();
      }
      // A position was increased/opened
      else if(entry == DEAL_ENTRY_IN)
      {
         const double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
         g_risk.RegisterExecutedLot(volume);
      }
   }
}
//+------------------------------------------------------------------+
