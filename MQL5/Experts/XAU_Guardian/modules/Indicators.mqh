#pragma once
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

   int m_handleATR;
   int m_handleRSI1;
   int m_handleRSI2;
   int m_handleRSI3;
   int m_handleCCI;
   int m_handleADX;
   int m_handleBands;
   int m_handleMAFast;
   int m_handleMASlow;
   int m_handleTVF;
   int m_handleSqueeze;

   bool Copy(const int handle,const int buffer,const int count,double &out[]) const
     {
      ArraySetAsSeries(out,true);
      if(CopyBuffer(handle,buffer,0,count,out)<count)
         return false;
      return true;
     }

public:
   IndicatorSuite():m_symbol(""),m_tf1(PERIOD_M15),m_tf2(PERIOD_H1),m_tf3(PERIOD_H4),m_window(120),m_debug(false),
                    m_handleATR(INVALID_HANDLE),m_handleRSI1(INVALID_HANDLE),m_handleRSI2(INVALID_HANDLE),
                    m_handleRSI3(INVALID_HANDLE),m_handleCCI(INVALID_HANDLE),m_handleADX(INVALID_HANDLE),
                    m_handleBands(INVALID_HANDLE),m_handleMAFast(INVALID_HANDLE),m_handleMASlow(INVALID_HANDLE),
                    m_handleTVF(INVALID_HANDLE),m_handleSqueeze(INVALID_HANDLE)
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
      m_handleATR=iATR(symbol,tf1,14);
      m_handleRSI1=iRSI(symbol,tf1,14,PRICE_CLOSE);
      m_handleRSI2=iRSI(symbol,tf2,14,PRICE_CLOSE);
      m_handleRSI3=iRSI(symbol,tf3,14,PRICE_CLOSE);
      m_handleCCI=iCCI(symbol,tf1,20,PRICE_TYPICAL);
      m_handleADX=iADX(symbol,tf1,14);
      m_handleBands=iBands(symbol,tf1,20,2.0,0,PRICE_CLOSE);
      m_handleMAFast=iMA(symbol,tf1,21,0,MODE_EMA,PRICE_CLOSE);
      m_handleMASlow=iMA(symbol,tf1,55,0,MODE_EMA,PRICE_CLOSE);
      m_handleTVF=iCustom(symbol,tf1,"XAU_TVF");
      m_handleSqueeze=iCustom(symbol,tf1,"XAU_Squeeze");
      bool ok=(m_handleATR!=INVALID_HANDLE && m_handleRSI1!=INVALID_HANDLE && m_handleRSI2!=INVALID_HANDLE &&
               m_handleRSI3!=INVALID_HANDLE && m_handleCCI!=INVALID_HANDLE && m_handleADX!=INVALID_HANDLE &&
               m_handleBands!=INVALID_HANDLE && m_handleMAFast!=INVALID_HANDLE && m_handleMASlow!=INVALID_HANDLE &&
               m_handleTVF!=INVALID_HANDLE && m_handleSqueeze!=INVALID_HANDLE);
      if(!ok)
         GuardianUtils::PrintInfo("Indicator initialization failed");
      return ok;
     }

   void Shutdown()
     {
      if(m_handleATR!=INVALID_HANDLE)IndicatorRelease(m_handleATR);
      if(m_handleRSI1!=INVALID_HANDLE)IndicatorRelease(m_handleRSI1);
      if(m_handleRSI2!=INVALID_HANDLE)IndicatorRelease(m_handleRSI2);
      if(m_handleRSI3!=INVALID_HANDLE)IndicatorRelease(m_handleRSI3);
      if(m_handleCCI!=INVALID_HANDLE)IndicatorRelease(m_handleCCI);
      if(m_handleADX!=INVALID_HANDLE)IndicatorRelease(m_handleADX);
      if(m_handleBands!=INVALID_HANDLE)IndicatorRelease(m_handleBands);
      if(m_handleMAFast!=INVALID_HANDLE)IndicatorRelease(m_handleMAFast);
      if(m_handleMASlow!=INVALID_HANDLE)IndicatorRelease(m_handleMASlow);
      if(m_handleTVF!=INVALID_HANDLE)IndicatorRelease(m_handleTVF);
      if(m_handleSqueeze!=INVALID_HANDLE)IndicatorRelease(m_handleSqueeze);
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

   double Close(const int shift) const
     {
      double buf[5];
      ArraySetAsSeries(buf,true);
      if(CopyClose(m_symbol,m_tf1,shift,1,buf)<1)
         return 0.0;
      return buf[0];
     }

   ENUM_TIMEFRAMES PrimaryTimeframe() const { return m_tf1; }
   const string &Symbol() const { return m_symbol; }
  };
