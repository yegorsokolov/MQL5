#pragma once
#include "Utils.mqh"

class OnlineLearner
  {
private:
   GuardianPersistedState *m_state;
   int      m_featureCount;
   double   m_learnRate;
   bool     m_debug;
   datetime m_lastUpdate;

   double Sigmoid(const double x) const
     {
      if(x>50.0) return 1.0;
      if(x<-50.0) return 0.0;
      return 1.0/(1.0+MathExp(-x));
     }

public:
   OnlineLearner():m_state(NULL),m_featureCount(0),m_learnRate(0.01),m_debug(false),m_lastUpdate(0)
     {
     }

   bool Init(GuardianPersistedState &state,const int featureCount,const double learnRate,const bool debug)
     {
      m_state=&state;
      m_featureCount=MathMin(featureCount,GUARDIAN_MAX_FEATURES);
      m_learnRate=learnRate;
      m_debug=debug;
      if(m_state.weights_count!=m_featureCount)
        {
         m_state.weights_count=m_featureCount;
         ArrayInitialize(m_state.weights,0.0);
         m_state.bias=0.0;
               GuardianStateStore::Save(*m_state);
        }
      return true;
     }

   double Score(double &features[]) const
     {
      if(m_state==NULL)
         return 0.5;
      double sum=m_state.bias;
      for(int i=0;i<m_featureCount;++i)
         sum+=m_state.weights[i]*features[i];
      return Sigmoid(sum);
     }

   void Update(double &features[],const double label)
     {
      if(m_state==NULL || m_learnRate<=0.0)
         return;
      double pred=Score(features);
      double error=pred-label;
      for(int i=0;i<m_featureCount;++i)
        {
         double grad=error*features[i];
         m_state.weights[i]-=m_learnRate*grad;
        }
      m_state.bias-=m_learnRate*error;
      m_state.weights_timestamp=TimeCurrent();
      m_lastUpdate=m_state.weights_timestamp;
      GuardianStateStore::Save(*m_state);
     }

   void Decay(const double factor)
     {
      if(m_state==NULL || m_learnRate<=0.0)
         return;
      for(int i=0;i<m_featureCount;++i)
         m_state.weights[i]*=factor;
      m_state.bias*=factor;
      GuardianStateStore::Save(*m_state);
     }

   datetime LastUpdateTime() const { return m_lastUpdate; }
  };
