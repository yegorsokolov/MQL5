#property copyright "XAU_Guardian"
#property link      "https://example.com"
#property version   "1.00"
#property indicator_separate_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_label1  "TrendScore"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_label2  "VolPressure"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_style2  STYLE_DASH
#property indicator_width2  2

input int    InpFastMAPeriod = 21;
input int    InpSlowMAPeriod = 55;
input int    InpATRPeriod    = 14;
input int    InpADXPeriod    = 14;

double TrendBuffer[];
double PressureBuffer[];

int handleFastMA;
int handleSlowMA;
int handleATR;
int handleADX;

double Clamp(const double value,const double limit)
  {
   if(value>limit) return limit;
   if(value<-limit) return -limit;
   return value;
  }

int OnInit()
  {
   SetIndexBuffer(0,TrendBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,PressureBuffer,INDICATOR_DATA);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,InpSlowMAPeriod);
   PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,InpSlowMAPeriod);
   IndicatorSetString(INDICATOR_SHORTNAME,"XAU_TVF");

   handleFastMA=iMA(_Symbol,_Period,InpFastMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   handleSlowMA=iMA(_Symbol,_Period,InpSlowMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   handleATR=iATR(_Symbol,_Period,InpATRPeriod);
   handleADX=iADX(_Symbol,_Period,InpADXPeriod);
   if(handleFastMA==INVALID_HANDLE || handleSlowMA==INVALID_HANDLE || handleATR==INVALID_HANDLE || handleADX==INVALID_HANDLE)
     {
      Print("XAU_TVF: indicator handle error");
      return INIT_FAILED;
     }
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(handleFastMA!=INVALID_HANDLE) IndicatorRelease(handleFastMA);
   if(handleSlowMA!=INVALID_HANDLE) IndicatorRelease(handleSlowMA);
   if(handleATR!=INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleADX!=INVALID_HANDLE) IndicatorRelease(handleADX);
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total<=InpSlowMAPeriod)
      return 0;

   int start=prev_calculated-1;
   if(start<InpSlowMAPeriod)
      start=InpSlowMAPeriod;

   double fast[],slow[],atr[],adx[];
   ArraySetAsSeries(fast,true);
   ArraySetAsSeries(slow,true);
   ArraySetAsSeries(atr,true);
   ArraySetAsSeries(adx,true);

   if(CopyBuffer(handleFastMA,0,0,rates_total,fast)<=0) return prev_calculated;
   if(CopyBuffer(handleSlowMA,0,0,rates_total,slow)<=0) return prev_calculated;
   if(CopyBuffer(handleATR,0,0,rates_total,atr)<=0) return prev_calculated;
   if(CopyBuffer(handleADX,0,0,rates_total,adx)<=0) return prev_calculated;

   for(int i=start;i<rates_total;++i)
     {
      double atrVal=atr[i];
      if(atrVal<_Point) atrVal=_Point;
      double trend=(fast[i]-slow[i])/atrVal;
      double prevFast=(i+1<rates_total)?fast[i+1]:fast[i];
      double slope=(fast[i]-prevFast)/atrVal;
      TrendBuffer[i]=Clamp((trend+slope)/2.0,3.0);
      double closePrice=close[i];
      if(closePrice<=0.0) closePrice=1.0;
      double volPressure=(atr[i]/closePrice)*(adx[i]/50.0);
      PressureBuffer[i]=Clamp(volPressure,3.0);
     }

   return rates_total;
  }
