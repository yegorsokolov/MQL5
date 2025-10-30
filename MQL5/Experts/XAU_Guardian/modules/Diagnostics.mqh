#ifndef XAU_GUARDIAN_DIAGNOSTICS_MQH
#define XAU_GUARDIAN_DIAGNOSTICS_MQH

#include <Trade/Trade.mqh>
#include "Utils.mqh"

namespace Diag
  {
class Panel
  {
private:
   string   m_name;
   int      m_magic;
   bool     m_show;
   int      m_refreshSec;
   int      m_targetSpreadPts;
   bool     m_disableNewsInTester;
   bool     m_enableProbeOnce;

   datetime m_lastCollect;
   datetime m_lastDraw;
   bool     m_block;
   string   m_status;
   int      m_lastSpread;

   string   m_lines[];
   bool     m_lineBlocks[];

   string   m_customReasons[];
   bool     m_customBlocks[];

   bool     m_probeDone;
   string   m_probeNote;

   CTrade   m_trade;

   int SpreadPts() const
     {
      return (int)SymbolInfoInteger(_Symbol,SYMBOL_SPREAD);
     }

   bool IsTester() const
     {
      return (bool)MQLInfoInteger(MQL_TESTER);
     }

   void PushLine(const string text,const bool blocking)
     {
      int pos=ArraySize(m_lines);
      ArrayResize(m_lines,pos+1);
      ArrayResize(m_lineBlocks,pos+1);
      m_lines[pos]=text;
      m_lineBlocks[pos]=blocking;
      if(blocking)
         m_block=true;
     }

   void PushBlock(const string text)
     {
      PushLine(text,true);
     }

   void PushWarn(const string text)
     {
      PushLine(text,false);
     }

   void MaybeProbe()
     {
      if(!m_enableProbeOnce || m_probeDone)
         return;

      m_probeDone=true;
      m_probeNote="";

      if(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL && !IsTester())
        {
         m_probeNote="Probe skipped on real account";
         return;
        }

      if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && PositionSelect(_Symbol))
        {
         m_probeNote="Probe skipped: netting position open";
         return;
        }

      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
        {
         m_probeNote="Probe skipped: AlgoTrading disabled";
         return;
        }

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol,tick))
        {
         PushBlock("Probe FAIL (no market tick)");
         m_probeNote="Probe failed: no tick data";
         return;
        }

      double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
      if(minLot<=0.0)
         minLot=step;
      if(minLot<=0.0)
         minLot=0.01;

      double lot=GuardianUtils::NormalizeLot(step,minLot,maxLot,minLot);
      if(lot<=0.0)
        {
         PushBlock("Probe FAIL (volume limits)");
         m_probeNote="Probe failed: invalid lot sizing";
         return;
        }

      m_trade.SetExpertMagicNumber(m_magic);
      bool ok=m_trade.Buy(lot,_Symbol,tick.ask,0.0,0.0);
      uint ret=m_trade.ResultRetcode();
      string desc=m_trade.ResultRetcodeDescription();
      if(!ok)
        {
         PushBlock(StringFormat("Probe FAIL ret=%u (%s)",ret,desc));
         m_probeNote=StringFormat("Probe ret=%u (%s)",ret,desc);
         return;
        }

      m_trade.PositionClose(_Symbol);
      // Do not spam panel on success; leave note empty.
     }

   void EnsureObjects()
     {
      if(ObjectFind(0,"DIAG_PANEL")<0)
        {
         ObjectCreate(0,"DIAG_PANEL",OBJ_RECTANGLE_LABEL,0,0,0);
         ObjectSetInteger(0,"DIAG_PANEL",OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,"DIAG_PANEL",OBJPROP_XDISTANCE,10);
         ObjectSetInteger(0,"DIAG_PANEL",OBJPROP_YDISTANCE,25);
         ObjectSetInteger(0,"DIAG_PANEL",OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,"DIAG_PANEL",OBJPROP_SELECTED,false);
         ObjectSetInteger(0,"DIAG_PANEL",OBJPROP_BACK,true);
        }

      if(ObjectFind(0,"DIAG_TEXT")<0)
        {
         ObjectCreate(0,"DIAG_TEXT",OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_CORNER,CORNER_LEFT_UPPER);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_XDISTANCE,16);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_YDISTANCE,32);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_SELECTABLE,false);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_SELECTED,false);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_BACK,false);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_FONTSIZE,9);
        }
     }

   void RemoveObjects()
     {
      ObjectDelete(0,"DIAG_PANEL");
      ObjectDelete(0,"DIAG_TEXT");
     }

public:
   Panel():m_name(""),m_magic(0),m_show(true),m_refreshSec(1),m_targetSpreadPts(0),
           m_disableNewsInTester(true),m_enableProbeOnce(false),m_lastCollect(0),
           m_lastDraw(0),m_block(false),m_status("READY"),m_lastSpread(0),
           m_probeDone(false),m_probeNote("")
     {
     }

   void Init(const string eaName,const int magic)
     {
      m_name=eaName;
      m_magic=magic;
      m_trade.SetExpertMagicNumber(magic);
     }

   void SetInputs(const bool show,const int refreshSec,const int targetSpreadPts,
                  const bool disableNewsInTester,const bool enableProbeOnce)
     {
      m_show=show;
      m_refreshSec=MathMax(1,refreshSec);
      m_targetSpreadPts=MathMax(0,targetSpreadPts);
      m_disableNewsInTester=disableNewsInTester;
      m_enableProbeOnce=enableProbeOnce;
     }

   void ResetExternal()
     {
      ArrayResize(m_customReasons,0);
      ArrayResize(m_customBlocks,0);
     }

   void AddExternal(const string reason,const bool blocking)
     {
      if(StringLen(reason)==0)
         return;
      for(int i=0;i<ArraySize(m_customReasons);++i)
        {
         if(m_customReasons[i]==reason)
           {
            if(blocking)
               m_customBlocks[i]=true;
            return;
           }
        }
      int pos=ArraySize(m_customReasons);
      ArrayResize(m_customReasons,pos+1);
      ArrayResize(m_customBlocks,pos+1);
      m_customReasons[pos]=reason;
      m_customBlocks[pos]=blocking;
     }

   void Collect(const bool signalAllowLong,const bool signalAllowShort,
                const bool rmUnlocked,const bool newsOk,const bool hoursOk)
     {
      m_lastCollect=TimeCurrent();
      ArrayResize(m_lines,0);
      ArrayResize(m_lineBlocks,0);
      m_block=false;
      m_status="READY";
      m_lastSpread=SpreadPts();

      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
         PushBlock("AlgoTrading disabled globally");

      long symMode=(long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
      if(symMode==SYMBOL_TRADE_MODE_DISABLED)
         PushBlock("Symbol trading disabled");
      else if(symMode==SYMBOL_TRADE_MODE_CLOSEONLY)
         PushWarn("Symbol close-only mode");

      long marginMode=(long)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      if(marginMode!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         PushWarn("Account is netting (no hedging)");

      if(m_targetSpreadPts>0 && m_lastSpread>m_targetSpreadPts)
         PushBlock(StringFormat("Spread %d > target %d",m_lastSpread,m_targetSpreadPts));

      if(!hoursOk)
         PushBlock("Outside trading hours/session");

      if(!newsOk)
        {
         if(IsTester() && m_disableNewsInTester)
            PushWarn("News lock suppressed in tester");
         else
            PushBlock("News lock (event proximity)");
        }

      if(!rmUnlocked)
         PushBlock("RiskManager lock/cooldown");

      for(int i=0;i<ArraySize(m_customReasons);++i)
        {
         if(m_customBlocks[i])
            PushBlock(m_customReasons[i]);
         else
            PushWarn(m_customReasons[i]);
        }

      MaybeProbe();
      if(StringLen(m_probeNote)>0)
         PushWarn(m_probeNote);

      if(!m_block && !signalAllowLong && !signalAllowShort)
         PushBlock("No valid signal (unfavorable entries)");

      if(m_block)
         m_status="BLOCK";
      else
         m_status="READY";
     }

   void Draw()
     {
      if(!m_show)
        {
         RemoveObjects();
         return;
        }

      datetime now=TimeCurrent();
      if(m_lastDraw!=0 && (now-m_lastDraw)<m_refreshSec)
         return;
      m_lastDraw=now;

      EnsureObjects();

      color bg=m_block?clrFireBrick:clrDarkGreen;
      color border=m_block?clrMaroon:clrForestGreen;
      ObjectSetInteger(0,"DIAG_PANEL",OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(0,"DIAG_PANEL",OBJPROP_COLOR,border);

      string spreadLine="Spread: "+IntegerToString(m_lastSpread);
      if(m_targetSpreadPts>0)
         spreadLine+=StringFormat(" / %d",m_targetSpreadPts);

      string body=m_name+" ["+m_status+"]\n";
      body+=spreadLine+" pts\n";

      if(ArraySize(m_lines)==0)
         body+="• All gates clear\n";
      else
        {
         for(int i=0;i<ArraySize(m_lines);++i)
           {
            string prefix=m_lineBlocks[i]?"✖ ":"• ";
            body+=prefix+m_lines[i]+"\n";
           }
        }

      body+="Updated: "+TimeToString(m_lastCollect,TIME_DATE|TIME_SECONDS);

      ObjectSetString(0,"DIAG_TEXT",OBJPROP_TEXT,body);
      ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_COLOR,clrWhite);
     }

   bool ShouldBlock() const
     {
      return m_block;
     }

   void OnDeinit()
     {
      RemoveObjects();
     }
  };

static Panel G;

  } // namespace Diag

void Diag_Init(const string eaName,const int magic)
  {
   Diag::G.Init(eaName,magic);
  }

void Diag_SetInputs(const bool show,const int refreshSec,const int targetSpreadPts,
                    const bool disableNewsInTester,const bool enableProbeOnce)
  {
   Diag::G.SetInputs(show,refreshSec,targetSpreadPts,disableNewsInTester,enableProbeOnce);
  }

void Diag_Reset()
  {
   Diag::G.ResetExternal();
  }

void Diag_AddReason(const string reason,const bool blocking)
  {
   Diag::G.AddExternal(reason,blocking);
  }

void Diag_AddWarning(const string reason)
  {
   Diag::G.AddExternal(reason,false);
  }

void Diag_Collect(const bool signalAllowLong,const bool signalAllowShort,
                  const bool rmUnlocked,const bool newsOk,const bool hoursOk)
  {
   Diag::G.Collect(signalAllowLong,signalAllowShort,rmUnlocked,newsOk,hoursOk);
  }

void Diag_Draw()
  {
   Diag::G.Draw();
  }

bool Diag_ShouldBlockEntry()
  {
   return Diag::G.ShouldBlock();
  }

void Diag_OnDeinit()
  {
   Diag::G.OnDeinit();
  }

#endif // XAU_GUARDIAN_DIAGNOSTICS_MQH
