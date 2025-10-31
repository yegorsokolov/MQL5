#ifndef XAU_GUARDIAN_DIAGNOSTICS_MQH
#define XAU_GUARDIAN_DIAGNOSTICS_MQH
// Improved, auto-wrapping, resizable, and nicer-looking diagnostics panel.

#include <Trade/Trade.mqh>
#include "Utils.mqh"

namespace Diag
{
class Panel
{
private:
   // ---------- Inputs / configuration ----------
   string   m_name;
   int      m_magic;

   bool     m_show;                 // show/hide panel
   int      m_refreshSec;           // draw throttle (seconds)
   int      m_targetSpreadPts;      // target spread limit to show
   bool     m_disableNewsInTester;  // suppress news lock in tester
   bool     m_enableProbeOnce;      // open/close 1 tiny probetrade (tester/demos only)

   // Layout customizations (new)
   int      m_corner;               // CORNER_*
   int      m_x;                    // x distance
   int      m_y;                    // y distance
   int      m_fontSize;             // body font size
   int      m_titleFontSize;        // title font size
   int      m_maxWidthPx;           // desired max width before wrapping
   bool     m_collapseWhenReady;    // collapse to a tiny chip when READY & no warnings

   // ---------- Runtime ----------
   datetime m_lastCollect;
   datetime m_lastDraw;
   bool     m_block;
   bool     m_hasWarns;
   string   m_status;
   int      m_lastSpread;

   string   m_lines[];
   bool     m_lineBlocks[];

   string   m_customReasons[];
   bool     m_customBlocks[];

   bool     m_probeDone;
   string   m_probeNote;

   CTrade   m_trade;

   // ---------- Helpers ----------
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
      if(blocking) m_block=true;
      if(!blocking) m_hasWarns=true;
   }

   void PushBlock(const string text){ PushLine(text,true);  }
   void PushWarn (const string text){ PushLine(text,false); }

   // crude monospace wrap (Consolas): wrap by character count
   string WrapMonospace(const string s,const int maxCols)
   {
      if(maxCols<=8) return s;
      string out="";
      int len=(int)StringLen(s);
      int col=0;
      for(int i=0;i<len;i++)
      {
         uint ch=StringGetCharacter(s,i);
         out+=StringFormat("%c",ch);
         if(ch=='\n'){ col=0; continue; }
         col++;
         if(col>=maxCols)
         {
            // avoid splitting bullets "• " or "✖ "
            if(i+1<len && StringGetCharacter(s,i+1)!='\n') out+="\n";
            col=0;
         }
      }
      return out;
   }

   // Estimate character width in pixels for Consolas at given font size.
   // Empirical average ~0.56 * fontSize * 16/9 on MT5; use a conservative 7 px at 10pt.
   int CharPx(int fontSize) const
   {
      // Keep it simple and stable across platforms
      return MathMax(6, (int)MathRound(0.7 * fontSize + 0.5));
   }

   int LineHeightPx(int fontSize) const
   {
      return MathMax(12, fontSize + 6);
   }

   void MaybeProbe()
   {
      if(!m_enableProbeOnce || m_probeDone) return;

      m_probeDone=true;
      m_probeNote="";

      if(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL && !IsTester())
      { m_probeNote="Probe skipped on real account"; return; }

      if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && PositionSelect(_Symbol))
      { m_probeNote="Probe skipped: netting position open"; return; }

      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
      { m_probeNote="Probe skipped: AlgoTrading disabled"; return; }

      MqlTick tick;
      if(!SymbolInfoTick(_Symbol,tick))
      { PushBlock("Probe FAIL (no market tick)"); m_probeNote="Probe failed: no tick data"; return; }

      double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
      double step  =SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
      double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
      if(minLot<=0.0) minLot=step;
      if(minLot<=0.0) minLot=0.01;

      double lot=GuardianUtils::NormalizeLot(step,minLot,maxLot,minLot);
      if(lot<=0.0)
      { PushBlock("Probe FAIL (volume limits)"); m_probeNote="Probe failed: invalid lot sizing"; return; }

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
      // success: no spam
   }

   // -------------- Objects --------------
   void EnsureObjects()
   {
      // Background rectangle
      if(ObjectFind(0,"DIAG_PANEL_BG")<0)
      {
         ObjectCreate(0,"DIAG_PANEL_BG",OBJ_RECTANGLE_LABEL,0,0,0);
         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_CORNER,     m_corner);
         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_XDISTANCE,  m_x);
         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_YDISTANCE,  m_y);
         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_BACK,       true);
         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_ZORDER,     0);
         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_XSIZE,      420);
         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_YSIZE,      140);
      }

      // Title bar
      if(ObjectFind(0,"DIAG_TITLE")<0)
      {
         ObjectCreate(0,"DIAG_TITLE",OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_CORNER,     m_corner);
         ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_XDISTANCE,  m_x+12);
         ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_YDISTANCE,  m_y+8);
         ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_BACK,       false);
         ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_ZORDER,     2);
         ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_FONTSIZE,   m_titleFontSize);
         ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_BOLD,       true);
         ObjectSetString (0,"DIAG_TITLE",OBJPROP_FONT,       "Consolas");
      }

      // Status dot (separate so we can recolor)
      if(ObjectFind(0,"DIAG_DOT")<0)
      {
         ObjectCreate(0,"DIAG_DOT",OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,"DIAG_DOT",OBJPROP_CORNER,     m_corner);
         ObjectSetInteger(0,"DIAG_DOT",OBJPROP_XDISTANCE,  m_x+8);
         ObjectSetInteger(0,"DIAG_DOT",OBJPROP_YDISTANCE,  m_y+9);
         ObjectSetInteger(0,"DIAG_DOT",OBJPROP_BACK,       false);
         ObjectSetInteger(0,"DIAG_DOT",OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0,"DIAG_DOT",OBJPROP_ZORDER,     3);
         ObjectSetInteger(0,"DIAG_DOT",OBJPROP_FONTSIZE,   m_titleFontSize+2);
         ObjectSetString (0,"DIAG_DOT",OBJPROP_FONT,       "Consolas");
         ObjectSetString (0,"DIAG_DOT",OBJPROP_TEXT,       "●");
      }

      // Body text
      if(ObjectFind(0,"DIAG_TEXT")<0)
      {
         ObjectCreate(0,"DIAG_TEXT",OBJ_LABEL,0,0,0);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_CORNER,     m_corner);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_XDISTANCE,  m_x+12);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_YDISTANCE,  m_y+8 + m_titleFontSize + 10);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_BACK,       false);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_ZORDER,     2);
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_FONTSIZE,   m_fontSize);
         ObjectSetString (0,"DIAG_TEXT",OBJPROP_FONT,       "Consolas");
      }
   }

   void RemoveObjects()
   {
      ObjectDelete(0,"DIAG_PANEL_BG");
      ObjectDelete(0,"DIAG_TITLE");
      ObjectDelete(0,"DIAG_DOT");
      ObjectDelete(0,"DIAG_TEXT");
   }

   // -------------- Layout --------------
   void ApplyCornerAndOffsets()
   {
      ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_CORNER,    m_corner);
      ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_XDISTANCE, m_x);
      ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_YDISTANCE, m_y);

      ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_CORNER,    m_corner);
      ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_XDISTANCE, m_x+12);
      ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_YDISTANCE, m_y+8);

      ObjectSetInteger(0,"DIAG_DOT",OBJPROP_CORNER,    m_corner);
      ObjectSetInteger(0,"DIAG_DOT",OBJPROP_XDISTANCE, m_x+8);
      ObjectSetInteger(0,"DIAG_DOT",OBJPROP_YDISTANCE, m_y+9);

      ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_CORNER,    m_corner);
      ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_XDISTANCE, m_x+12);
      ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_YDISTANCE, m_y+8 + m_titleFontSize + 10);
   }

public:
   Panel():
      m_name(""),
      m_magic(0),
      m_show(true),
      m_refreshSec(1),
      m_targetSpreadPts(0),
      m_disableNewsInTester(true),
      m_enableProbeOnce(false),
      m_corner(CORNER_LEFT_UPPER),
      m_x(8), m_y(20),
      m_fontSize(10),
      m_titleFontSize(11),
      m_maxWidthPx(460),
      m_collapseWhenReady(true),
      m_lastCollect(0),
      m_lastDraw(0),
      m_block(false),
      m_hasWarns(false),
      m_status("READY"),
      m_lastSpread(0),
      m_probeDone(false),
      m_probeNote("")
   { }

   // ---------- API ----------
   void Init(const string eaName,const int magic)
   {
      m_name=eaName;
      m_magic=magic;
      m_trade.SetExpertMagicNumber(magic);
   }

   // main visual inputs
   void SetInputs(const bool show,const int refreshSec,const int targetSpreadPts,
                  const bool disableNewsInTester,const bool enableProbeOnce)
   {
      m_show=show;
      m_refreshSec=MathMax(1,refreshSec);
      m_targetSpreadPts=MathMax(0,targetSpreadPts);
      m_disableNewsInTester=disableNewsInTester;
      m_enableProbeOnce=enableProbeOnce;
   }

   // extra layout controls (optional)
   void SetLayout(const int corner,const int x,const int y,const int bodyFontSize,
                  const int titleFontSize,const int maxWidthPx,const bool collapseWhenReady)
   {
      m_corner=corner;
      m_x=x; m_y=y;
      m_fontSize = MathMax(8,  bodyFontSize);
      m_titleFontSize = MathMax(m_fontSize, titleFontSize);
      m_maxWidthPx = MathMax(260, maxWidthPx);
      m_collapseWhenReady = collapseWhenReady;
   }

   void ResetExternal()
   {
      ArrayResize(m_customReasons,0);
      ArrayResize(m_customBlocks,0);
   }

   void AddExternal(const string reason,const bool blocking)
   {
      if(StringLen(reason)==0) return;
      for(int i=0;i<ArraySize(m_customReasons);++i)
      {
         if(m_customReasons[i]==reason)
         {
            if(blocking) m_customBlocks[i]=true;
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
      m_hasWarns=false;
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
         if(IsTester() && m_disableNewsInTester) PushWarn("News lock suppressed in tester");
         else                                    PushBlock("News lock (event proximity)");
      }

      if(!rmUnlocked)
         PushBlock("RiskManager lock/cooldown");

      for(int i=0;i<ArraySize(m_customReasons);++i)
      {
         if(m_customBlocks[i]) PushBlock(m_customReasons[i]);
         else                  PushWarn (m_customReasons[i]);
      }

      MaybeProbe();
      if(StringLen(m_probeNote)>0) PushWarn(m_probeNote);

      if(!m_block && !signalAllowLong && !signalAllowShort)
         PushBlock("No valid signal (unfavorable entries)");

      m_status = m_block ? "BLOCK" : "READY";
   }

   void Draw()
   {
      if(!m_show)
      {
         RemoveObjects();
         return;
      }

      datetime now=TimeCurrent();
      if(m_lastDraw!=0 && (now-m_lastDraw)<m_refreshSec) return;
      m_lastDraw=now;

      EnsureObjects();
      ApplyCornerAndOffsets();

      // Colors
      color bg   = m_block ? (color)clrFireBrick : (m_hasWarns ? (color)clrOlive : (color)clrDarkGreen);
      color edge = m_block ? (color)clrMaroon    : (m_hasWarns ? (color)clrOliveDrab : (color)clrForestGreen);
      color text = (color)clrWhite;
      color dot  = m_block ? (color)clrTomato    : (m_hasWarns ? (color)clrGold : (color)clrLime);

      ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_COLOR,edge);

      // Title
      string title=m_name+" ["+m_status+"]";
      ObjectSetString(0,"DIAG_TITLE",OBJPROP_TEXT,title);
      ObjectSetInteger(0,"DIAG_TITLE",OBJPROP_COLOR,text);

      // Status dot color
      ObjectSetInteger(0,"DIAG_DOT",OBJPROP_COLOR,dot);

      // Build body
      string spreadLine="Spread: "+IntegerToString(m_lastSpread);
      if(m_targetSpreadPts>0) spreadLine+=StringFormat(" / %d pts",m_targetSpreadPts);
      else                    spreadLine+=" pts";

      string body=spreadLine+"\n";
      if(ArraySize(m_lines)==0)
      {
         body+="• All gates clear\n";
      }
      else
      {
         for(int i=0;i<ArraySize(m_lines);++i)
         {
            string prefix=m_lineBlocks[i]?"✖ ":"• ";
            body+=prefix+m_lines[i]+"\n";
         }
      }
      body+="Updated: "+TimeToString(m_lastCollect,TIME_DATE|TIME_SECONDS);

      // Collapse if desired
      bool collapse = (m_collapseWhenReady && !m_block && !m_hasWarns);
      if(collapse)
      {
         ObjectSetString (0,"DIAG_TEXT",OBJPROP_TEXT,""); // hide body
         ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_FONTSIZE,m_fontSize);

         int pad=8;
         int titleH = LineHeightPx(m_titleFontSize);
         int totalH = pad + titleH + pad;

         // Compute width to fit title (rough monospace estimate)
         int charPx = CharPx(m_titleFontSize);
         int width  = pad + (int)StringLen(title)*charPx + pad + 22; // + space for dot
         width = MathMin(MathMax(180,width), m_maxWidthPx);

         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_YSIZE,totalH);
         ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_XSIZE,width);

         ChartRedraw(0);
         return;
      }

      // Wrapping
      int charPx = CharPx(m_fontSize);
      int pad    = 10;
      int maxCols= MathMax(20, (m_maxWidthPx - 2*pad - 16) / MathMax(1,charPx)); // -left padding - bullet slack
      string wrapped = WrapMonospace(body, maxCols);

      // Apply text
      ObjectSetString (0,"DIAG_TEXT",OBJPROP_TEXT,wrapped);
      ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_COLOR,text);
      ObjectSetInteger(0,"DIAG_TEXT",OBJPROP_FONTSIZE,m_fontSize);

      // Dynamic sizing
      int lines=1;
      for(int i=0;i<(int)StringLen(wrapped);++i)
         if(StringGetCharacter(wrapped,i)=='\n') lines++;

      int lineH   = LineHeightPx(m_fontSize);
      int titleH  = LineHeightPx(m_titleFontSize);
      int bodyH   = lines*lineH;
      int totalH  = 8 + titleH + 6 + bodyH + 8;

      // compute width by longest line length (approx)
      int maxLineLen=0, cur=0;
      for(int i=0;i<(int)StringLen(wrapped);++i)
      {
         if(StringGetCharacter(wrapped,i)=='\n'){ if(cur>maxLineLen) maxLineLen=cur; cur=0; }
         else cur++;
      }
      if(cur>maxLineLen) maxLineLen=cur;
      int contentW = pad + maxLineLen*charPx + pad + 6;
      int width    = MathMin(MathMax(260,contentW), m_maxWidthPx);

      ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_YSIZE,totalH);
      ObjectSetInteger(0,"DIAG_PANEL_BG",OBJPROP_XSIZE,width);

      ChartRedraw(0);
   }

   bool ShouldBlock() const { return m_block; }

   void OnDeinit(){ RemoveObjects(); }
};

// Single static instance
static Panel G;

} // namespace Diag

// -------- C-style façade for easy use --------
void Diag_Init(const string eaName,const int magic)
{
   Diag::G.Init(eaName,magic);
}
void Diag_SetInputs(const bool show,const int refreshSec,const int targetSpreadPts,
                    const bool disableNewsInTester,const bool enableProbeOnce)
{
   Diag::G.SetInputs(show,refreshSec,targetSpreadPts,disableNewsInTester,enableProbeOnce);
}
// Optional layout override (call after Diag_SetInputs if you want custom placement)
void Diag_SetLayout(const int corner,const int x,const int y,const int bodyFontSize=10,
                    const int titleFontSize=11,const int maxWidthPx=460,const bool collapseWhenReady=true)
{
   Diag::G.SetLayout(corner,x,y,bodyFontSize,titleFontSize,maxWidthPx,collapseWhenReady);
}

void Diag_Reset(){ Diag::G.ResetExternal(); }
void Diag_AddReason(const string reason,const bool blocking){ Diag::G.AddExternal(reason,blocking); }
void Diag_AddWarning(const string reason){ Diag::G.AddExternal(reason,false); }
void Diag_Collect(const bool signalAllowLong,const bool signalAllowShort,
                  const bool rmUnlocked,const bool newsOk,const bool hoursOk)
{
   Diag::G.Collect(signalAllowLong,signalAllowShort,rmUnlocked,newsOk,hoursOk);
}
void Diag_Draw(){ Diag::G.Draw(); }
bool Diag_ShouldBlockEntry(){ return Diag::G.ShouldBlock(); }
void Diag_OnDeinit(){ Diag::G.OnDeinit(); }

#endif // XAU_GUARDIAN_DIAGNOSTICS_MQH
