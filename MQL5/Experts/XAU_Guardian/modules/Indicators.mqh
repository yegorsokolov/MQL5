#ifndef XAU_GUARDIAN_INDICATORS_MQH
#define XAU_GUARDIAN_INDICATORS_MQH

#include "Utils.mqh"

class IndicatorSuite
  {
private:
   string           m_symbol;
   ENUM_TIMEFRAMES  m_tf1;
   ENUM_TIMEFRAMES  m_tf2;
   ENUM_TIMEFRAMES  m_tf3;
   int              m_window;
   bool             m_debug;
   double           m_atrEwma;
   datetime         m_atrEwmaBar;
   bool             m_atrEwmaInitialized;

   int m_handleATR;
   int m_handleATRKeltner;
   int m_handleRSI1;
   int m_handleRSI2;
   int m_handleRSI3;
   int m_handleCCI;
   int m_handleADX;
   int m_handleBands;
   int m_handleMAFast;
   int m_handleMASlow;
   int m_handleMATF2;
   int m_handleTVF;
   int m_handleSqueeze;
   int m_handleMFI;
   int m_handleOBV;

   bool Copy(const int handle,const int buffer,const int count,double &out[]) const
     {
      ArraySetAsSeries(out,true);
      if(CopyBuffer(handle,buffer,0,count,out)<count)
         return false;
      return true;
     }

public:
   IndicatorSuite():m_symbol(""),m_tf1(PERIOD_M15),m_tf2(PERIOD_H1),m_tf3(PERIOD_H4),m_window(120),m_debug(false),
                    m_atrEwma(0.0),m_atrEwmaBar(0),m_atrEwmaInitialized(false),
                    m_handleATR(INVALID_HANDLE),m_handleATRKeltner(INVALID_HANDLE),m_handleRSI1(INVALID_HANDLE),
                    m_handleRSI2(INVALID_HANDLE),m_handleRSI3(INVALID_HANDLE),m_handleCCI(INVALID_HANDLE),
                    m_handleADX(INVALID_HANDLE),m_handleBands(INVALID_HANDLE),m_handleMAFast(INVALID_HANDLE),
                    m_handleMASlow(INVALID_HANDLE),m_handleMATF2(INVALID_HANDLE),m_handleTVF(INVALID_HANDLE),
                    m_handleSqueeze(INVALID_HANDLE),m_handleMFI(INVALID_HANDLE),m_handleOBV(INVALID_HANDLE)
     {
     }

   bool Init(const string symbol,const ENUM_TIMEFRAMES tf1,const ENUM_TIMEFRAMES tf2,const ENUM_TIMEFRAMES tf3,
             const int window,const bool debug)
     {
      m_symbol=symbol;
      m_tf1=tf1;
      m_tf2=tf2;
      m_tf3=tf3;
      m_window=window;
      m_debug=debug;
      m_atrEwma=0.0;
      m_atrEwmaBar=0;
      m_atrEwmaInitialized=false;
      m_handleATR=iATR(symbol,tf1,14);
      m_handleATRKeltner=iATR(symbol,tf1,10);
      m_handleRSI1=iRSI(symbol,tf1,14,PRICE_CLOSE);
      m_handleRSI2=iRSI(symbol,tf2,14,PRICE_CLOSE);
      m_handleRSI3=iRSI(symbol,tf3,14,PRICE_CLOSE);
      m_handleCCI=iCCI(symbol,tf1,20,PRICE_TYPICAL);
      m_handleADX=iADX(symbol,tf1,14);
      m_handleBands=iBands(symbol,tf1,20,2.0,0,PRICE_CLOSE);
      m_handleMAFast=iMA(symbol,tf1,21,0,MODE_EMA,PRICE_CLOSE);
      m_handleMASlow=iMA(symbol,tf1,55,0,MODE_EMA,PRICE_CLOSE);
      m_handleMATF2=iMA(symbol,tf2,34,0,MODE_EMA,PRICE_CLOSE);
      m_handleTVF=iCustom(symbol,tf1,"XAU_TVF");
      m_handleSqueeze=iCustom(symbol,tf1,"XAU_Squeeze");
      m_handleMFI=iMFI(symbol,tf1,14,VOLUME_TICK);
      m_handleOBV=iOBV(symbol,tf1,PRICE_CLOSE,VOLUME_TICK);
      bool ok=(m_handleATR!=INVALID_HANDLE && m_handleATRKeltner!=INVALID_HANDLE &&
               m_handleRSI1!=INVALID_HANDLE && m_handleRSI2!=INVALID_HANDLE && m_handleRSI3!=INVALID_HANDLE &&
               m_handleCCI!=INVALID_HANDLE && m_handleADX!=INVALID_HANDLE && m_handleBands!=INVALID_HANDLE &&
               m_handleMAFast!=INVALID_HANDLE && m_handleMASlow!=INVALID_HANDLE && m_handleMATF2!=INVALID_HANDLE &&
               m_handleTVF!=INVALID_HANDLE && m_handleSqueeze!=INVALID_HANDLE &&
               m_handleMFI!=INVALID_HANDLE && m_handleOBV!=INVALID_HANDLE);
      if(!ok)
         GuardianUtils::PrintInfo("Indicator initialization failed");
      return ok;
     }

   void Shutdown()
     {
      if(m_handleATR!=INVALID_HANDLE)IndicatorRelease(m_handleATR);
      if(m_handleATRKeltner!=INVALID_HANDLE)IndicatorRelease(m_handleATRKeltner);
      if(m_handleRSI1!=INVALID_HANDLE)IndicatorRelease(m_handleRSI1);
      if(m_handleRSI2!=INVALID_HANDLE)IndicatorRelease(m_handleRSI2);
      if(m_handleRSI3!=INVALID_HANDLE)IndicatorRelease(m_handleRSI3);
      if(m_handleCCI!=INVALID_HANDLE)IndicatorRelease(m_handleCCI);
      if(m_handleADX!=INVALID_HANDLE)IndicatorRelease(m_handleADX);
      if(m_handleBands!=INVALID_HANDLE)IndicatorRelease(m_handleBands);
      if(m_handleMAFast!=INVALID_HANDLE)IndicatorRelease(m_handleMAFast);
      if(m_handleMASlow!=INVALID_HANDLE)IndicatorRelease(m_handleMASlow);
      if(m_handleMATF2!=INVALID_HANDLE)IndicatorRelease(m_handleMATF2);
      if(m_handleTVF!=INVALID_HANDLE)IndicatorRelease(m_handleTVF);
      if(m_handleSqueeze!=INVALID_HANDLE)IndicatorRelease(m_handleSqueeze);
      if(m_handleMFI!=INVALID_HANDLE)IndicatorRelease(m_handleMFI);
      if(m_handleOBV!=INVALID_HANDLE)IndicatorRelease(m_handleOBV);
     }

   bool BuildFeatureVector(const int shift,double &features[]) const
     {
      ArrayResize(features,GUARDIAN_FEATURE_COUNT);
      ArrayInitialize(features,0.0);

      double atrBuf[10];
      double rsi1[10];
      double rsi2[10];
      double rsi3[10];
      double cci[10];
      double adx[10];
      double maFast[10];
      double maSlow[10];
      double upper[10];
      double middle[10];
      double lower[10];
      double tvfTrend[10];
      double tvfVol[10];
      double sqState[10];
      double sqBreak[10];

      if(!Copy(m_handleATR,0,shift+2,atrBuf)) return false;
      if(!Copy(m_handleRSI1,0,shift+2,rsi1)) return false;
      if(!Copy(m_handleRSI2,0,shift+2,rsi2)) return false;
      if(!Copy(m_handleRSI3,0,shift+2,rsi3)) return false;
      if(!Copy(m_handleCCI,0,shift+2,cci)) return false;
      if(!Copy(m_handleADX,0,shift+2,adx)) return false;
      if(!Copy(m_handleMAFast,0,shift+2,maFast)) return false;
      if(!Copy(m_handleMASlow,0,shift+2,maSlow)) return false;
      if(CopyBuffer(m_handleBands,0,0,shift+2,upper)<shift+2) return false;
      if(CopyBuffer(m_handleBands,1,0,shift+2,middle)<shift+2) return false;
      if(CopyBuffer(m_handleBands,2,0,shift+2,lower)<shift+2) return false;
      if(CopyBuffer(m_handleTVF,0,0,shift+2,tvfTrend)<shift+2) return false;
      if(CopyBuffer(m_handleTVF,1,0,shift+2,tvfVol)<shift+2) return false;
      if(CopyBuffer(m_handleSqueeze,0,0,shift+2,sqState)<shift+2) return false;
      if(CopyBuffer(m_handleSqueeze,1,0,shift+2,sqBreak)<shift+2) return false;

      double priceClose[10];
      ArraySetAsSeries(priceClose,true);
      if(CopyClose(m_symbol,m_tf1,0,shift+2,priceClose)<shift+2)
         return false;

      double spread=GuardianUtils::SpreadPoints(m_symbol);

      double atr=atrBuf[shift];
      double close0=priceClose[shift];
      double close1=priceClose[shift+1];
      double priceChange=(close0-close1);
      double normChange=(atr>_Point?priceChange/(atr):0.0);

      features[0]=normChange;
      features[1]=(rsi1[shift]-50.0)/50.0;
      features[2]=(rsi2[shift]-50.0)/50.0;
      features[3]=(rsi3[shift]-50.0)/50.0;
      features[4]=cci[shift]/200.0;
      features[5]=(atr/close0);
      features[6]=adx[shift]/50.0;
      double bandWidth=(upper[shift]-lower[shift]);
      features[7]=(bandWidth>0?bandWidth/close0:0.0);
      features[8]=sqState[shift];
      features[9]=sqBreak[shift];
      features[10]=tvfTrend[shift];
      features[11]=tvfVol[shift];
      double slope=(maFast[shift]-maFast[shift+1]);
      features[12]=(atr>_Point?slope/atr:0.0);
      features[13]=spread/100.0;

      return true;
     }

   double TrendScore(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleTVF,0,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double VolatilityPressure(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleTVF,1,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   bool IsSqueezeActive(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleSqueeze,0,shift,1,buf)<1)
         return false;
      return (buf[0]>0.5);
     }

   double SqueezeBreakoutScore(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleSqueeze,1,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double ADX(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleADX,0,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double ATR(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleATR,0,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double ATREWMA(const double lambda=0.06)
     {
      double atr=ATR(0);
      if(atr<=0.0)
         return (m_atrEwmaInitialized)?m_atrEwma:0.0;
      double alpha=(lambda>0.0 && lambda<1.0)?lambda:0.06;
      datetime barTime=iTime(m_symbol,m_tf1,0);
      if(!m_atrEwmaInitialized)
        {
         m_atrEwma=atr;
         m_atrEwmaInitialized=true;
         m_atrEwmaBar=barTime;
        }
      else if(barTime!=m_atrEwmaBar)
        {
         m_atrEwma=alpha*atr+(1.0-alpha)*m_atrEwma;
         m_atrEwmaBar=barTime;
        }
      return (m_atrEwma>0.0)?m_atrEwma:atr;
     }

   double ATRKeltner(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleATRKeltner,0,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double RSI1(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleRSI1,0,shift,1,buf)<1)
         return 50.0;
      return buf[0];
     }

   double RSI2(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleRSI2,0,shift,1,buf)<1)
         return 50.0;
      return buf[0];
     }

   double EMAFast(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleMAFast,0,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double MASlow(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleMASlow,0,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double EMASlopeTF2() const
     {
      double buf[3];
      if(CopyBuffer(m_handleMATF2,0,0,2,buf)<2)
         return 0.0;
      double slope=buf[0]-buf[1];
      double atr=ATR(0);
      if(atr<=_Point)
         return slope;
      return slope/atr;
     }

   double Close(const int shift) const
     {
      double buf[5];
      ArraySetAsSeries(buf,true);
      if(CopyClose(m_symbol,m_tf1,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double High(const int shift) const
     {
      double buf[5];
      ArraySetAsSeries(buf,true);
      if(CopyHigh(m_symbol,m_tf1,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double Low(const int shift) const
     {
      double buf[5];
      ArraySetAsSeries(buf,true);
      if(CopyLow(m_symbol,m_tf1,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double DonchianHigh(const int shift,const int period=20) const
     {
      double highs[];
      ArraySetAsSeries(highs,true);
      if(CopyHigh(m_symbol,m_tf1,shift,period,highs)<period)
         return 0.0;
      double maxValue=highs[0];
      for(int i=0;i<period;++i)
         if(highs[i]>maxValue)
            maxValue=highs[i];
      return maxValue;
     }

  double DonchianLow(const int shift,const int period=20) const
     {
      double lows[];
      ArraySetAsSeries(lows,true);
      if(CopyLow(m_symbol,m_tf1,shift,period,lows)<period)
         return 0.0;
      double minValue=lows[0];
      for(int i=0;i<period;++i)
         if(lows[i]<minValue)
            minValue=lows[i];
      return minValue;
     }

   double BollingerUpper(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleBands,0,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double BollingerLower(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleBands,2,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double KeltnerUpper(const int shift,const double multiplier=1.5) const
     {
      double ema=EMAFast(shift);
      double atr=ATRKeltner(shift);
      return ema+multiplier*atr;
     }

   double KeltnerLower(const int shift,const double multiplier=1.5) const
     {
      double ema=EMAFast(shift);
      double atr=ATRKeltner(shift);
      return ema-multiplier*atr;
     }

   double MoneyFlowIndex(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleMFI,0,shift,1,buf)<1)
         return 50.0;
      return buf[0];
     }

   double OnBalanceVolume(const int shift) const
     {
      double buf[5];
      if(CopyBuffer(m_handleOBV,0,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   double RealizedVolatility(const int period=20) const
     {
      double closes[];
      ArraySetAsSeries(closes,true);
      if(CopyClose(m_symbol,m_tf1,0,period+1,closes)<period+1)
         return 0.0;
      double mean=0.0;
      double count=0.0;
      double m2=0.0;
      for(int i=0;i<period;++i)
        {
         double ret=0.0;
         if(closes[i+1]>0.0)
            ret=closes[i]/closes[i+1]-1.0;
         count+=1.0;
         double delta=ret-mean;
         mean+=delta/count;
         double delta2=ret-mean;
         m2+=delta*delta2;
        }
      if(count<=1.0)
         return 0.0;
      double variance=m2/(count-1.0);
      if(variance<0.0)
         variance=0.0;
      return MathSqrt(variance);
     }

   double SuperTrendBaseline(const int shift,const int period=10,const double multiplier=3.0) const
     {
      int target=shift;
      if(target<0)
         target=0;
      if(target>=m_window-1)
        {
         double baseHigh=High(target);
         double baseLow=Low(target);
         if(baseHigh==0.0 && baseLow==0.0)
            return 0.0;
         return (baseHigh+baseLow)/2.0;
        }

      int baseIndex=m_window-1;
      double highBase=High(baseIndex);
      double lowBase=Low(baseIndex);
      if(highBase==0.0 && lowBase==0.0)
         return 0.0;
      double baseline=(highBase+lowBase)/2.0;

      for(int idx=baseIndex-1; idx>=target; --idx)
        {
         double high=High(idx);
         double low=Low(idx);
         if(high==0.0 && low==0.0)
            break;
         double atr=ATRKeltner(idx);
         double hl2=(high+low)/2.0;
         double upper=hl2+multiplier*atr;
         double lower=hl2-multiplier*atr;
         double prevClose=Close(idx+1);
         if(prevClose>baseline)
            baseline=MathMax(lower,baseline);
         else
            baseline=MathMin(upper,baseline);
        }
      return baseline;
     }

   ENUM_TIMEFRAMES PrimaryTimeframe() const { return m_tf1; }
   ENUM_TIMEFRAMES SecondaryTimeframe() const { return m_tf2; }
   const string &Symbol() const { return m_symbol; }
  };

#endif // XAU_GUARDIAN_INDICATORS_MQH
