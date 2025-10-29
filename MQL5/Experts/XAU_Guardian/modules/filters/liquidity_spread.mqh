#ifndef XAU_GUARDIAN_FILTERS_LIQUIDITY_SPREAD_MQH
#define XAU_GUARDIAN_FILTERS_LIQUIDITY_SPREAD_MQH

#include "../Utils.mqh"

class LiquiditySpreadFilter
  {
private:
   string m_symbol;
   double m_spreadLimit;
   double m_minBookVolume;
   int    m_levels;
   bool   m_debug;
   bool   m_bookSubscribed;

   bool EnsureBookSubscription()
     {
      if(m_minBookVolume<=0.0)
         return true;
      if(m_bookSubscribed)
         return true;
      if(MarketBookAdd(m_symbol))
        {
         m_bookSubscribed=true;
         return true;
        }
      if(m_debug)
         GuardianUtils::PrintDebug("MarketBookAdd failed for "+m_symbol,m_debug);
      return false;
     }

public:
   LiquiditySpreadFilter():m_symbol(""),m_spreadLimit(0.0),m_minBookVolume(0.0),m_levels(0),m_debug(false),
                           m_bookSubscribed(false)
     {
     }

   bool Init(const string symbol,const double spreadLimit,const double minBookVolume,const int depthLevels,const bool debug)
     {
      m_symbol=symbol;
      m_spreadLimit=spreadLimit;
      m_minBookVolume=MathMax(0.0,minBookVolume);
      m_levels=MathMax(0,depthLevels);
      m_debug=debug;
      m_bookSubscribed=false;
      if(m_minBookVolume>0.0)
         EnsureBookSubscription();
      return true;
     }

   double SpreadPoints() const
     {
      return GuardianUtils::SpreadPoints(m_symbol);
     }

   bool IsSpreadAcceptable(double &spread) const
     {
      spread=SpreadPoints();
      if(m_spreadLimit<=0.0)
         return true;
      return (spread<=m_spreadLimit);
     }

   bool IsLiquidityAcceptable()
     {
      if(m_minBookVolume<=0.0)
         return true;
      if(!EnsureBookSubscription())
         return true;
      MqlBookInfo book[];
      ArrayResize(book,0);
      if(!MarketBookGet(m_symbol,book))
         return true;
      double bidVolume=0.0;
      double askVolume=0.0;
      int bidLevels=0;
      int askLevels=0;
      int total=ArraySize(book);
      for(int i=0;i<total;++i)
        {
         if(book[i].type==BOOK_TYPE_BUY)
           {
            if(m_levels==0 || bidLevels<m_levels)
              {
               bidVolume+=book[i].volume;
               bidLevels++;
              }
           }
         else if(book[i].type==BOOK_TYPE_SELL)
           {
            if(m_levels==0 || askLevels<m_levels)
              {
               askVolume+=book[i].volume;
               askLevels++;
              }
           }
        }
      return (bidVolume>=m_minBookVolume && askVolume>=m_minBookVolume);
     }

   bool Pass(double &spread)
     {
      bool spreadOk=IsSpreadAcceptable(spread);
      bool liquidityOk=IsLiquidityAcceptable();
      return (spreadOk && liquidityOk);
     }

   void Shutdown()
     {
      if(m_bookSubscribed)
        {
         MarketBookRelease(m_symbol);
         m_bookSubscribed=false;
        }
     }
  };

#endif // XAU_GUARDIAN_FILTERS_LIQUIDITY_SPREAD_MQH

