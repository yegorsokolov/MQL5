#property copyright "XAU_Guardian"
#property link      "https://example.com"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 2
#property indicator_plots   2
#property indicator_label1  "Squeeze"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2
#property indicator_label2  "BreakoutProb"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDodgerBlue
#property indicator_style2  STYLE_SOLID
#property indicator_width2  2

input int    InpBollPeriod   = 20;
input double InpBollDev      = 2.0;
input int    InpKeltPeriod   = 20;
input double InpKeltMult     = 1.5;
input int    InpMomentumPeriod = 12;

double SqueezeBuffer[];
double BreakoutBuffer[];

int handleBands;
int handleATR;
int handleMA;

double Clamp(const double value,const double limit)
  {
   if(value>limit) return limit;
   if(value<-limit) return -limit;
   return value;
  }

int OnInit()
  {
   SetIndexBuffer(0,SqueezeBuffer,INDICATOR_DATA);
   SetIndexBuffer(1,BreakoutBuffer,INDICATOR_DATA);
   PlotIndexSetInteger(0,PLOT_DRAW_BEGIN,InpBollPeriod);
   PlotIndexSetInteger(1,PLOT_DRAW_BEGIN,InpBollPeriod);
   IndicatorSetString(INDICATOR_SHORTNAME,"XAU_Squeeze");
   handleBands=iBands(_Symbol,_Period,InpBollPeriod,0,InpBollDev,PRICE_CLOSE);
   handleATR=iATR(_Symbol,_Period,InpKeltPeriod);
   handleMA=iMA(_Symbol,_Period,InpMomentumPeriod,0,MODE_EMA,PRICE_CLOSE);
   if(handleBands==INVALID_HANDLE || handleATR==INVALID_HANDLE || handleMA==INVALID_HANDLE)
     {
      Print("XAU_Squeeze: failed to create handles");
      return INIT_FAILED;
     }
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(handleBands!=INVALID_HANDLE) IndicatorRelease(handleBands);
   if(handleATR!=INVALID_HANDLE) IndicatorRelease(handleATR);
   if(handleMA!=INVALID_HANDLE) IndicatorRelease(handleMA);
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
   if(rates_total<=InpBollPeriod)
      return 0;

   int start=prev_calculated-1;
   if(start<InpBollPeriod)
      start=InpBollPeriod;

   double upper[],middle[],lower[];
   double atr[];
   double ma[];
   ArraySetAsSeries(upper,true);
   ArraySetAsSeries(middle,true);
   ArraySetAsSeries(lower,true);
   ArraySetAsSeries(atr,true);
   ArraySetAsSeries(ma,true);

   if(CopyBuffer(handleBands,0,0,rates_total,upper)<=0) return prev_calculated;
   if(CopyBuffer(handleBands,1,0,rates_total,middle)<=0) return prev_calculated;
   if(CopyBuffer(handleBands,2,0,rates_total,lower)<=0) return prev_calculated;
   if(CopyBuffer(handleATR,0,0,rates_total,atr)<=0) return prev_calculated;
   if(CopyBuffer(handleMA,0,0,rates_total,ma)<=0) return prev_calculated;

   for(int i=start;i<rates_total;++i)
     {
      double bandWidth=upper[i]-lower[i];
      double keltWidth=atr[i]*InpKeltMult*2.0;
      bool squeeze=(bandWidth<keltWidth);
      SqueezeBuffer[i]=squeeze?1.0:0.0;
      double momentum=close[i]-ma[i];
      double breakout=0.0;
      if(!squeeze)
        {
         double normalization=(atr[i]>_Point)?atr[i]:_Point;
         breakout=Clamp(momentum/normalization,3.0);
        }
      else
        {
         double normalization=(keltWidth>_Point)?keltWidth:_Point;
         breakout=Clamp(momentum/normalization,3.0);
        }
      BreakoutBuffer[i]=breakout;
     }

   return rates_total;
  }
