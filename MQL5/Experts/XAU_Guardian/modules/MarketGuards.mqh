// MarketGuards.mqh — MT5-safe helper for spread/stop validation
#ifndef __MARKET_GUARDS_MQH__
#define __MARKET_GUARDS_MQH__

// No dependency on <Trade/Trade.mqh>.
// We only use built-in MQL5 types, SymbolInfo* APIs and constants.

// Simple modes to evaluate spread reasonableness
enum SpreadMode { SPREAD_FIXED = 0, SPREAD_MA_MULT = 1 };

class MarketGuards
{
private:
   string m_symbol;
   double m_point;
   int    m_digits;
   double m_tick_size;
   double m_tick_value;
   long   m_stops_level_pts;

   // rolling spread estimate (EMA-like)
   double m_ma_spread_pts;
   int    m_ma_lookback;
   int    m_ma_cnt;

public:
   // public “inputs” you wire from your EA
   int    InpSpreadLimitPts;      // fixed spread cap (points)
   int    InpSpreadLookback;      // lookback length for rolling MA (ticks/seconds proxy)
   double InpSpreadMult;          // multiplier of MA when using SPREAD_MA_MULT
   int    InpSpreadMode;          // 0=fixed, 1=MA multiple
   bool   InpAutoStopPad;         // pad SL/TP to satisfy broker stops level
   int    InpMinSLPts;            // minimum SL in points (extra safety)

   // ctor
   MarketGuards(const string sym="") :
      m_symbol(sym),
      m_point(0.0),
      m_digits(0),
      m_tick_size(0.0),
      m_tick_value(0.0),
      m_stops_level_pts(0),
      m_ma_spread_pts(0.0),
      m_ma_lookback(60),
      m_ma_cnt(0),
      InpSpreadLimitPts(1000),
      InpSpreadLookback(120),
      InpSpreadMult(1.5),
      InpSpreadMode(SPREAD_FIXED),
      InpAutoStopPad(true),
      InpMinSLPts(100)
   {
      if(m_symbol=="") m_symbol = _Symbol;

      m_point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_stops_level_pts = (long)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);

      // carry the configured lookback to the internal variable
      m_ma_lookback = InpSpreadLookback;
   }

   // call once you’ve set public inputs (e.g., from OnInit)
   void RefreshSymbolCaps()
   {
      if(m_symbol=="") m_symbol = _Symbol;
      m_point  = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_stops_level_pts = (long)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_ma_lookback = InpSpreadLookback;
   }

   // compute current spread in POINTS from live Bid/Ask (robust under real-tick backtests)
   int SpreadPts() const
   {
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      if(bid<=0 || ask<=0)
      {
         long sp = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
         return (int)sp;
      }
      return (int)MathRound((ask - bid) / m_point);
   }

   // Update rolling mean of spread; call on every tick
   void OnTickUpdate()
   {
      int sp = SpreadPts();
      if(sp <= 0) return;

      m_ma_cnt++;
      // EMA smoothing: during warmup use increasing window, then fixed
      double alpha = (m_ma_cnt < m_ma_lookback ? (1.0 / (double)m_ma_cnt)
                                               : (2.0 / (m_ma_lookback + 1.0)));
      if(m_ma_spread_pts<=0.0)
         m_ma_spread_pts = (double)sp;
      else
         m_ma_spread_pts = alpha * (double)sp + (1.0 - alpha) * m_ma_spread_pts;
   }

   // Is spread acceptable right now?
   bool SpreadOK(string &why) const
   {
      const int sp = SpreadPts();
      if(InpSpreadMode == SPREAD_FIXED)
      {
         if(sp > InpSpreadLimitPts) { why = StringFormat("spread %d > limit %d pts", sp, InpSpreadLimitPts); return false; }
         return true;
      }
      // MA-multiple mode
      const double base = (m_ma_spread_pts>0.0 ? m_ma_spread_pts : (double)sp);
      const int lim = (int)MathRound(base * InpSpreadMult);
      if(sp > lim) { why = StringFormat("spread %d > %.2fxMA(%d)=%d pts", sp, InpSpreadMult, (int)MathRound(m_ma_spread_pts), lim); return false; }
      return true;
   }

   // Adjust SL/TP to satisfy broker stop-level & user min SL; normalize to digits
   // dir: ORDER_TYPE_BUY or ORDER_TYPE_SELL
   void ConformStops(const int dir, const double entry, double &sl, double &tp) const
   {
      const bool isSell = (dir==ORDER_TYPE_SELL);
      const double min_dist_price = (double)m_stops_level_pts * m_point;
      const double min_sl_price   = MathMax((double)InpMinSLPts * m_point, min_dist_price);

      if(InpAutoStopPad)
      {
         if(!isSell) // BUY
         {
            if(sl>0 && (entry - sl) < min_sl_price) sl = entry - min_sl_price;
            if(tp>0 && (tp - entry) < min_dist_price) tp = entry + min_dist_price;
         }
         else        // SELL
         {
            if(sl>0 && (sl - entry) < min_sl_price) sl = entry + min_sl_price;
            if(tp>0 && (entry - tp) < min_dist_price) tp = entry - min_dist_price;
         }
      }

      if(sl>0) sl = NormalizeDouble(sl, m_digits);
      if(tp>0) tp = NormalizeDouble(tp, m_digits);
   }

   // optional: print symbol constraints on init
   void DumpSymbolCaps() const
   {
      const double volmin = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      const double volmax = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      const double volstep= SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      PrintFormat("[SYMBOL] %s digits=%d point=%.5f tick_size=%.5f stops_level=%d pts vol[min=%.2f, max=%.2f, step=%.2f]",
                  m_symbol, m_digits, m_point, m_tick_size, (int)m_stops_level_pts, volmin, volmax, volstep);
   }
};

#endif // __MARKET_GUARDS_MQH__
