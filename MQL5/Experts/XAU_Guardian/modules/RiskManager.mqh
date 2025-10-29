#pragma once
#include "Utils.mqh"

class RiskManager
  {
private:
   string   m_symbol;
   int      m_magic;
   double   m_virtualBalance;
   double   m_floatLimit;
   double   m_dailyLimit;
   int      m_cooldownMinutes;
   bool     m_debug;
   GuardianPersistedState *m_state;
   datetime m_lastAnchorCheck;
   int      m_lossStreakLimit;
   double   m_softDrawdownPct;
   int      m_softCooldownBars;

   double FloatingThreshold() const { return m_virtualBalance*m_floatLimit; }
   double DailyThreshold() const { return m_virtualBalance*m_dailyLimit; }

public:
   RiskManager():m_symbol(""),m_magic(0),m_virtualBalance(0.0),m_floatLimit(0.0),m_dailyLimit(0.0),
                 m_cooldownMinutes(60),m_debug(false),m_state(NULL),m_lastAnchorCheck(0),
                 m_lossStreakLimit(0),m_softDrawdownPct(0.0),m_softCooldownBars(0)
     {
     }

   bool Init(GuardianPersistedState &state,const string symbol,const int magic,const double virtualBalance,
             const double floatingLimit,const double dailyLimit,const int cooldownMinutes,const bool debug,
             const int lossStreakLimit,const double softDrawdownPct,const int softCooldownBars)
     {
      m_symbol=symbol;
      m_magic=magic;
      m_virtualBalance=virtualBalance;
      m_floatLimit=floatingLimit;
      m_dailyLimit=dailyLimit;
      m_cooldownMinutes=cooldownMinutes;
      m_debug=debug;
      m_state=&state;
      m_lossStreakLimit=lossStreakLimit;
      m_softDrawdownPct=softDrawdownPct;
      m_softCooldownBars=softCooldownBars;
      if(m_state.anchor_equity<=0.0)
         m_state.anchor_equity=virtualBalance;
      if(m_state.anchor_day==0)
         m_state.anchor_day=GuardianUtils::BrokerDayStart(TimeCurrent());
      m_lastAnchorCheck=m_state.anchor_day;
      return true;
     }

   void RefreshDailyAnchor()
     {
      datetime today=GuardianUtils::BrokerDayStart(TimeCurrent());
      if(today==m_lastAnchorCheck)
         return;
      m_lastAnchorCheck=today;
      if(m_state==NULL)
         return;
      m_state.anchor_day=today;
      m_state.anchor_equity=m_virtualBalance;
      m_state.daily_lock=false;
      if(m_state.cooldown_until>today)
         m_state.cooldown_until=today;
      GuardianUtils::PrintInfo("Reset daily anchor to "+DoubleToString(m_state.anchor_equity,2));
      GuardianStateStore::Save(*m_state);
     }

   bool IsTradingBlocked() const
     {
      if(m_state==NULL)
         return false;
      if(m_state.daily_lock)
         return true;
      if(m_state.cooldown_until>TimeCurrent())
         return true;
      if(m_state.soft_cooldown_bars>0)
         return true;
      return false;
     }

   void SetCooldownMinutes(const int minutes)
     {
      m_cooldownMinutes=minutes;
     }

   void ForceCooldown()
     {
      if(m_state==NULL)
         return;
      m_state.cooldown_until=TimeCurrent()+(m_cooldownMinutes*60);
      GuardianStateStore::Save(*m_state);
      GuardianUtils::PrintInfo("Cooldown activated for "+IntegerToString(m_cooldownMinutes)+" minutes");
     }

   void ForceDailyLock()
     {
      if(m_state==NULL)
         return;
      datetime nextDay=GuardianUtils::BrokerDayStart(TimeCurrent()+86400);
      m_state.cooldown_until=nextDay;
      m_state.daily_lock=true;
      GuardianStateStore::Save(*m_state);
      GuardianUtils::PrintInfo("Daily lock engaged until next session");
     }

   double TodaysPLVirtual() const
     {
      datetime anchor=(m_state!=NULL && m_state.anchor_day>0)?m_state.anchor_day:GuardianUtils::BrokerDayStart(TimeCurrent());
      double closed=GuardianUtils::ClosedPLSince(m_symbol,m_magic,anchor);
      double floating=GuardianUtils::SumUnrealized(m_symbol,m_magic);
      return closed+floating;
     }

   bool CheckFloatingDDAndAct(CTrade &trade)
     {
      double floating=GuardianUtils::SumUnrealized(m_symbol,m_magic);
      double limit=-FloatingThreshold();
      if(floating<=limit)
        {
         GuardianUtils::PrintInfo("Floating DD breach: "+DoubleToString(floating,2)+" <= "
                                  +DoubleToString(limit,2));
         GuardianUtils::CloseAll(trade,m_symbol,m_magic);
         ForceCooldown();
         return true;
        }
      return false;
     }

   bool CheckDailyDDAndAct(CTrade &trade)
     {
      double todaysPL=TodaysPLVirtual();
      double limit=-DailyThreshold();
      if(todaysPL<=limit)
        {
         GuardianUtils::PrintInfo("Daily DD breach: "+DoubleToString(todaysPL,2)+" <= "
                                  +DoubleToString(limit,2));
         GuardianUtils::CloseAll(trade,m_symbol,m_magic);
         ForceDailyLock();
         return true;
        }
      return false;
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

   void UpdateSmallestLotFromPositions()
     {
      if(m_state==NULL)
         return;
      double smallest=0.0;
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
        }
      if(smallest==0.0)
         smallest=0.0;
      if(MathAbs(smallest-m_state.smallest_lot)>0.00001)
        {
         m_state.smallest_lot=smallest;
         GuardianStateStore::Save(*m_state);
        }
     }

   void ResetIfFlat()
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
         return;
        }
      if(m_state!=NULL)
        {
         m_state.smallest_lot=0.0;
         m_state.soft_loss_streak=0;
         m_state.soft_loss_sum=0.0;
         GuardianStateStore::Save(*m_state);
        }
     }

   double SessionMinLot(const double baseLot) const
     {
      if(m_state==NULL || m_state.smallest_lot<=0.0)
         return baseLot;
      return m_state.smallest_lot;
     }

   void ActivateSoftCooldown()
     {
      if(m_state==NULL || m_softCooldownBars<=0)
         return;
      m_state.soft_cooldown_bars=m_softCooldownBars;
      GuardianStateStore::Save(*m_state);
      GuardianUtils::PrintInfo("Soft cooldown engaged for "
                               +IntegerToString(m_softCooldownBars)+" bars after loss streak");
     }

   void OnTradeClosed(const double profit)
     {
      if(m_state==NULL)
         return;
      if(profit<0.0)
        {
         m_state.soft_loss_streak++;
         m_state.soft_loss_sum+=MathAbs(profit)/m_virtualBalance;
         if((m_lossStreakLimit>0 && m_state.soft_loss_streak>=m_lossStreakLimit) ||
            (m_softDrawdownPct>0.0 && m_state.soft_loss_sum>=m_softDrawdownPct))
           {
            ActivateSoftCooldown();
            m_state.soft_loss_streak=0;
            m_state.soft_loss_sum=0.0;
           }
        }
      else
        {
         m_state.soft_loss_streak=0;
         if(profit>0.0)
           {
            double recovery=MathAbs(profit)/m_virtualBalance;
            m_state.soft_loss_sum=MathMax(0.0,m_state.soft_loss_sum-recovery);
           }
        }
      GuardianStateStore::Save(*m_state);
     }

   void OnBar()
     {
      if(m_state==NULL)
         return;
      if(m_state.soft_cooldown_bars>0)
        {
         m_state.soft_cooldown_bars--;
         if(m_state.soft_cooldown_bars==0)
           {
            bool reset=false;
            if(m_state.soft_loss_sum>0.0)
              {
               m_state.soft_loss_sum=0.0;
               reset=true;
              }
            if(m_state.soft_loss_streak>0)
              {
               m_state.soft_loss_streak=0;
               reset=true;
              }
            GuardianUtils::PrintDebug("Soft cooldown expired",m_debug);
            if(reset)
               GuardianUtils::PrintDebug("Soft-loss counters reset after cooldown",m_debug);
           }
         GuardianStateStore::Save(*m_state);
        }
     }

   double CooldownMinutesRemaining() const
     {
      if(m_state==NULL)
         return 0.0;
      if(m_state.cooldown_until<=TimeCurrent())
         return 0.0;
      return (m_state.cooldown_until-TimeCurrent())/60.0;
     }

   bool DailyLockActive() const
     {
      return (m_state!=NULL && m_state.daily_lock);
     }

   void OnTimer()
     {
      RefreshDailyAnchor();
      if(m_state!=NULL && m_state.cooldown_until<=TimeCurrent() && m_state.daily_lock &&
         GuardianUtils::BrokerDayStart(TimeCurrent())>m_state.anchor_day)
        {
         m_state.daily_lock=false;
         GuardianStateStore::Save(*m_state);
         GuardianUtils::PrintInfo("Daily lock cleared on new session");
        }
     }
  };
