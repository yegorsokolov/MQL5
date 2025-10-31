#ifndef XAU_GUARDIAN_UTILS_MQH
#define XAU_GUARDIAN_UTILS_MQH

#include <Trade/Trade.mqh>

#define GUARDIAN_MAX_FEATURES 32
#define GUARDIAN_FEATURE_COUNT 14

//--- helper constants for persisted buffers
#define GUARDIAN_MAX_RECENT_RESULTS 5

class GuardianPersistedState
  {
public:
   datetime anchor_day;
   double   anchor_equity;
   bool     daily_lock;
   datetime cooldown_until;
   double   smallest_lot;
   int      weights_count;
   double   weights[GUARDIAN_MAX_FEATURES];
   double   bias;
   datetime weights_timestamp;
   int      feature_updates;
   double   feature_means[GUARDIAN_MAX_FEATURES];
   double   feature_vars[GUARDIAN_MAX_FEATURES];
   double   snapshot_weights[GUARDIAN_MAX_FEATURES];
   double   snapshot_bias;
   datetime snapshot_timestamp;
   int      soft_loss_streak;
   double   soft_loss_sum;
   int      soft_cooldown_bars;
   double   equity_curve_ema;
   datetime equity_curve_timestamp;
   bool     equity_curve_lock;
   double   peak_equity;
   datetime peak_equity_day;
  };

class GuardianUtils
  {
public:
   static string FilesRoot()
     {
      return "XAU_Guardian/";
     }

   static string LogsRoot()
     {
      return FilesRoot()+"logs/";
     }

   static string StateFile()
     {
      return FilesRoot()+"state.json";
     }

   static bool EnsurePaths()
     {
      bool ok=true;
      ok &= FolderCreate(FilesRoot());
      ok &= FolderCreate(LogsRoot());
      ok &= FolderCreate(FilesRoot()+"presets/");
      return ok;
     }

   static void PrintInfo(const string text)
     {
      Print("[XAU_Guardian] "+text);
     }

   static void PrintDebug(const string text,const bool enabled,const int throttleSeconds=0)
     {
      if(!enabled)
         return;

      if(throttleSeconds>0)
        {
         static string   lastMessages[];
         static datetime lastTimestamps[];

         int index=-1;
         for(int i=0;i<ArraySize(lastMessages);++i)
            if(lastMessages[i]==text)
              {
               index=i;
               break;
              }

         datetime now=TimeCurrent();
         if(index>=0)
           {
            if(now-lastTimestamps[index]<throttleSeconds)
               return;
            lastTimestamps[index]=now;
           }
         else
           {
            index=ArraySize(lastMessages);
            ArrayResize(lastMessages,index+1);
            ArrayResize(lastTimestamps,index+1);
            lastMessages[index]=text;
            lastTimestamps[index]=now;
           }
        }

      Print("[XAU_Guardian][DBG] "+text);
     }

   static bool AppendLog(const string filename,const string line)
     {
      int handle=FileOpen(LogsRoot()+filename,FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_READ);
      if(handle==INVALID_HANDLE)
         return false;
      FileSeek(handle,0,SEEK_END);
      FileWriteString(handle,line+"\r\n");
      FileClose(handle);
      return true;
     }

   static bool FileExists(const string path)
     {
      return FileIsExist(path);
     }

   static datetime FileModifiedTime(const string path)
     {
      int handle=FileOpen(path,FILE_READ|FILE_BIN|FILE_SHARE_READ);
      if(handle==INVALID_HANDLE)
         return 0;
      datetime modified=(datetime)FileGetInteger(handle,FILE_MODIFY_DATE);
      FileClose(handle);
      return modified;
     }

   static bool LoadText(const string path,string &out)
     {
      int handle=FileOpen(path,FILE_READ|FILE_TXT|FILE_ANSI);
      if(handle==INVALID_HANDLE)
         return false;
      string data="";
      while(!FileIsEnding(handle))
        {
         string line=FileReadString(handle);
         if(StringLen(data)>0)
            data+="\n";
         data+=line;
        }
      FileClose(handle);
      out=data;
      return true;
     }

   static bool SaveText(const string path,const string text)
     {
      int handle=FileOpen(path,FILE_WRITE|FILE_TXT|FILE_ANSI);
      if(handle==INVALID_HANDLE)
         return false;
      FileWriteString(handle,text);
      FileClose(handle);
      return true;
     }

   static double NormalizeLot(const double step,const double minLot,const double maxLot,const double lots)
     {
      double clipped=MathMax(minLot,MathMin(maxLot,lots));
      if(step<=0.0)
         return clipped;
      double steps=MathFloor(clipped/step);
      double normalized=steps*step;
      if(normalized<minLot)
         normalized=minLot;
      if(normalized>maxLot)
         normalized=maxLot;
      return normalized;
     }

   static double SumUnrealized(const string symbol,const int magic)
     {
      double total=0.0;
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=symbol)
            continue;
         if(magic>0 && (int)PositionGetInteger(POSITION_MAGIC)!=magic)
            continue;
         total+=PositionGetDouble(POSITION_PROFIT);
        }
      return total;
     }

   static double ClosedPLSince(const string symbol,const int magic,const datetime from)
     {
      if(!HistorySelect(from,TimeCurrent()))
         return 0.0;
      double sum=0.0;
      int deals=HistoryDealsTotal();
      for(int i=0;i<deals;++i)
        {
         ulong ticket=HistoryDealGetTicket(i);
         if(ticket==0)
            continue;
         if(HistoryDealGetString(ticket,DEAL_SYMBOL)!=symbol)
            continue;
         if(magic>0 && (int)HistoryDealGetInteger(ticket,DEAL_MAGIC)!=magic)
            continue;
         ENUM_DEAL_ENTRY entry=(ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket,DEAL_ENTRY);
         if(entry!=DEAL_ENTRY_OUT && entry!=DEAL_ENTRY_INOUT)
            continue;
         double profit=HistoryDealGetDouble(ticket,DEAL_PROFIT);
         double swap=HistoryDealGetDouble(ticket,DEAL_SWAP);
         double commission=HistoryDealGetDouble(ticket,DEAL_COMMISSION);
         sum+=profit+swap+commission;
        }
      return sum;
     }

   static bool CloseAll(CTrade &trade,const string symbol,const int magic)
     {
      bool ok=true;
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         ulong ticket=PositionGetTicket(i);
         if(!PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL)!=symbol)
            continue;
         if(magic>0 && (int)PositionGetInteger(POSITION_MAGIC)!=magic)
            continue;
         if(!trade.PositionClose(ticket))
            ok=false;
        }
      return ok;
     }

   static double SpreadPoints(const string symbol)
     {
      long spread=0;
      if(SymbolInfoInteger(symbol,SYMBOL_SPREAD,spread))
         return (double)spread;
      double ask=0.0,bid=0.0;
      SymbolInfoDouble(symbol,SYMBOL_ASK,ask);
      SymbolInfoDouble(symbol,SYMBOL_BID,bid);
      return (ask-bid)/_Point;
     }

   static double PointsToPrice(const double points)
     {
      return points*_Point;
     }

   static datetime BrokerDayStart(datetime now)
     {
      MqlDateTime tm;
      TimeToStruct(now,tm);
      tm.hour=0;
      tm.min=0;
      tm.sec=0;
      return StructToTime(tm);
     }

   static bool IsWithinHours(const datetime time,const int startHour,const int endHour)
     {
      MqlDateTime tm;
      TimeToStruct(time,tm);
      int hour=tm.hour;
      if(startHour==endHour)
         return false;
      if(startHour<endHour)
         return (hour>=startHour && hour<endHour);
      return (hour>=startHour || hour<endHour);
     }

   static string Trim(const string value)
     {
      string tmp=value;
      StringTrimLeft(tmp);
      StringTrimRight(tmp);
      return tmp;
     }

   static string ExtractValue(const string text,const string key)
     {
      string pattern="\""+key+"\"";
      int idx=StringFind(text,pattern);
      if(idx==-1)
         return "";
      idx=StringFind(text,":",idx);
      if(idx==-1)
         return "";
      idx++;
      while(idx<StringLen(text) && StringGetCharacter(text,idx)<=32)
         idx++;
      if(idx>=StringLen(text))
         return "";
      int ch=StringGetCharacter(text,idx);
      if(ch=='"')
        {
         idx++;
         int end=idx;
         while(end<StringLen(text) && StringGetCharacter(text,end)!='"')
            end++;
         return StringSubstr(text,idx,end-idx);
        }
      if(ch=='[')
        {
         int depth=1;
         int end=idx+1;
         while(end<StringLen(text) && depth>0)
           {
            int c=StringGetCharacter(text,end);
            if(c=='[')
               depth++;
            else if(c==']')
               depth--;
            end++;
           }
         return StringSubstr(text,idx,end-idx);
        }
      int end=idx;
      while(end<StringLen(text))
        {
         int c=StringGetCharacter(text,end);
         if(c==',' || c=='}' || c=='\n')
            break;
         end++;
        }
      return Trim(StringSubstr(text,idx,end-idx));
     }
  };

class GuardianStateStore
  {
public:
   static bool Load(GuardianPersistedState &state,const int featureCount)
     {
      GuardianUtils::EnsurePaths();
      state.anchor_day=0;
      state.anchor_equity=0.0;
      state.daily_lock=false;
      state.cooldown_until=0;
      state.smallest_lot=0.0;
      state.weights_count=MathMin(featureCount,GUARDIAN_MAX_FEATURES);
      ArrayInitialize(state.weights,0.0);
      state.bias=0.0;
      state.weights_timestamp=0;
      state.feature_updates=0;
      ArrayInitialize(state.feature_means,0.0);
      ArrayInitialize(state.feature_vars,0.0);
      ArrayInitialize(state.snapshot_weights,0.0);
      state.snapshot_bias=0.0;
      state.snapshot_timestamp=0;
      state.soft_loss_streak=0;
      state.soft_loss_sum=0.0;
      state.soft_cooldown_bars=0;
      state.equity_curve_ema=0.0;
      state.equity_curve_timestamp=0;
      state.equity_curve_lock=false;
      state.peak_equity=0.0;
      state.peak_equity_day=0;
      string text;
      if(!GuardianUtils::LoadText(GuardianUtils::StateFile(),text))
         return false;
      string value;
      value=GuardianUtils::ExtractValue(text,"anchor_day");
      if(StringLen(value)>0)
         state.anchor_day=(datetime)StringToInteger(value);
      value=GuardianUtils::ExtractValue(text,"anchor_equity");
      if(StringLen(value)>0)
         state.anchor_equity=StringToDouble(value);
      value=GuardianUtils::ExtractValue(text,"daily_lock");
      if(StringLen(value)>0)
         state.daily_lock=(StringCompare(value,"true",false)==0 || value=="1");
      value=GuardianUtils::ExtractValue(text,"cooldown_until");
      if(StringLen(value)>0)
         state.cooldown_until=(datetime)StringToInteger(value);
      value=GuardianUtils::ExtractValue(text,"smallest_lot");
      if(StringLen(value)>0)
         state.smallest_lot=StringToDouble(value);
      value=GuardianUtils::ExtractValue(text,"weights_count");
      if(StringLen(value)>0)
         state.weights_count=MathMin((int)StringToInteger(value),GUARDIAN_MAX_FEATURES);
      value=GuardianUtils::ExtractValue(text,"weights");
      if(StringLen(value)>0 && StringGetCharacter(value,0)=='[')
        {
         string arr=StringSubstr(value,1,StringLen(value)-2);
         StringReplace(arr," ","");
         string parts[];
         int n=StringSplit(arr,',',parts);
         int limit=MathMin(n,state.weights_count);
         for(int i=0;i<limit;++i)
            state.weights[i]=StringToDouble(parts[i]);
        }
      value=GuardianUtils::ExtractValue(text,"bias");
      if(StringLen(value)>0)
         state.bias=StringToDouble(value);
      value=GuardianUtils::ExtractValue(text,"weights_timestamp");
      if(StringLen(value)>0)
         state.weights_timestamp=(datetime)StringToInteger(value);
      value=GuardianUtils::ExtractValue(text,"feature_updates");
      if(StringLen(value)>0)
         state.feature_updates=(int)StringToInteger(value);
      value=GuardianUtils::ExtractValue(text,"feature_means");
      if(StringLen(value)>0 && StringGetCharacter(value,0)=='[')
        {
         string arr=StringSubstr(value,1,StringLen(value)-2);
         StringReplace(arr," ","");
         string parts[];
         int n=StringSplit(arr,',',parts);
         int limit=MathMin(n,state.weights_count);
         for(int i=0;i<limit;++i)
            state.feature_means[i]=StringToDouble(parts[i]);
        }
      value=GuardianUtils::ExtractValue(text,"feature_vars");
      if(StringLen(value)>0 && StringGetCharacter(value,0)=='[')
        {
         string arr=StringSubstr(value,1,StringLen(value)-2);
         StringReplace(arr," ","");
         string parts[];
         int n=StringSplit(arr,',',parts);
         int limit=MathMin(n,state.weights_count);
         for(int i=0;i<limit;++i)
            state.feature_vars[i]=StringToDouble(parts[i]);
        }
      value=GuardianUtils::ExtractValue(text,"snapshot_weights");
      if(StringLen(value)>0 && StringGetCharacter(value,0)=='[')
        {
         string arr=StringSubstr(value,1,StringLen(value)-2);
         StringReplace(arr," ","");
         string parts[];
         int n=StringSplit(arr,',',parts);
         int limit=MathMin(n,state.weights_count);
         for(int i=0;i<limit;++i)
            state.snapshot_weights[i]=StringToDouble(parts[i]);
        }
      value=GuardianUtils::ExtractValue(text,"snapshot_bias");
      if(StringLen(value)>0)
         state.snapshot_bias=StringToDouble(value);
      value=GuardianUtils::ExtractValue(text,"snapshot_timestamp");
      if(StringLen(value)>0)
         state.snapshot_timestamp=(datetime)StringToInteger(value);
      value=GuardianUtils::ExtractValue(text,"soft_loss_streak");
      if(StringLen(value)>0)
         state.soft_loss_streak=(int)StringToInteger(value);
      value=GuardianUtils::ExtractValue(text,"soft_loss_sum");
      if(StringLen(value)>0)
         state.soft_loss_sum=StringToDouble(value);
      value=GuardianUtils::ExtractValue(text,"soft_cooldown_bars");
      if(StringLen(value)>0)
         state.soft_cooldown_bars=(int)StringToInteger(value);
      value=GuardianUtils::ExtractValue(text,"equity_curve_ema");
      if(StringLen(value)>0)
         state.equity_curve_ema=StringToDouble(value);
      value=GuardianUtils::ExtractValue(text,"equity_curve_timestamp");
      if(StringLen(value)>0)
         state.equity_curve_timestamp=(datetime)StringToInteger(value);
      value=GuardianUtils::ExtractValue(text,"equity_curve_lock");
      if(StringLen(value)>0)
         state.equity_curve_lock=(StringCompare(value,"true",false)==0 || value=="1");
      value=GuardianUtils::ExtractValue(text,"peak_equity");
      if(StringLen(value)>0)
         state.peak_equity=StringToDouble(value);
      value=GuardianUtils::ExtractValue(text,"peak_equity_day");
      if(StringLen(value)>0)
         state.peak_equity_day=(datetime)StringToInteger(value);
      return true;
     }

   static bool Save(const GuardianPersistedState &state)
     {
      GuardianUtils::EnsurePaths();
      string text="{\n";
      text+=StringFormat("  \"anchor_day\": %I64d,\n",(long)state.anchor_day);
      text+=StringFormat("  \"anchor_equity\": %.2f,\n",state.anchor_equity);
      text+=StringFormat("  \"daily_lock\": %s,\n",state.daily_lock?"true":"false");
      text+=StringFormat("  \"cooldown_until\": %I64d,\n",(long)state.cooldown_until);
      text+=StringFormat("  \"smallest_lot\": %.4f,\n",state.smallest_lot);
      text+=StringFormat("  \"weights_count\": %d,\n",state.weights_count);
      text+="  \"weights\": [";
      for(int i=0;i<state.weights_count;++i)
        {
         if(i>0)
            text+=", ";
         text+=DoubleToString(state.weights[i],8);
        }
      text+="],\n";
      text+=StringFormat("  \"bias\": %.8f,\n",state.bias);
      text+=StringFormat("  \"weights_timestamp\": %I64d,\n",(long)state.weights_timestamp);
      text+=StringFormat("  \"feature_updates\": %d,\n",state.feature_updates);
      text+="  \"feature_means\": [";
      for(int i=0;i<state.weights_count;++i)
        {
         if(i>0) text+=", ";
         text+=DoubleToString(state.feature_means[i],8);
        }
      text+="],\n";
      text+="  \"feature_vars\": [";
      for(int i=0;i<state.weights_count;++i)
        {
         if(i>0) text+=", ";
         text+=DoubleToString(state.feature_vars[i],8);
        }
      text+="],\n";
      text+="  \"snapshot_weights\": [";
      for(int i=0;i<state.weights_count;++i)
        {
         if(i>0) text+=", ";
         text+=DoubleToString(state.snapshot_weights[i],8);
        }
      text+="],\n";
      text+=StringFormat("  \"snapshot_bias\": %.8f,\n",state.snapshot_bias);
      text+=StringFormat("  \"snapshot_timestamp\": %I64d,\n",(long)state.snapshot_timestamp);
      text+=StringFormat("  \"soft_loss_streak\": %d,\n",state.soft_loss_streak);
      text+=StringFormat("  \"soft_loss_sum\": %.8f,\n",state.soft_loss_sum);
      text+=StringFormat("  \"soft_cooldown_bars\": %d,\n",state.soft_cooldown_bars);
      text+=StringFormat("  \"equity_curve_ema\": %.2f,\n",state.equity_curve_ema);
      text+=StringFormat("  \"equity_curve_timestamp\": %I64d,\n",(long)state.equity_curve_timestamp);
      text+=StringFormat("  \"equity_curve_lock\": %s,\n",state.equity_curve_lock?"true":"false");
      text+=StringFormat("  \"peak_equity\": %.2f,\n",state.peak_equity);
      text+=StringFormat("  \"peak_equity_day\": %I64d\n",(long)state.peak_equity_day);
      text+="}\n";
      return GuardianUtils::SaveText(GuardianUtils::StateFile(),text);
     }
  };

#endif // XAU_GUARDIAN_UTILS_MQH
