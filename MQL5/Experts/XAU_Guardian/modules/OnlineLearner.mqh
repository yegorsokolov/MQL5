#ifndef XAU_GUARDIAN_ONLINELEARNER_MQH
#define XAU_GUARDIAN_ONLINELEARNER_MQH

#include <Object.mqh>
#include "Utils.mqh"

class OnlineLearner : public CObject
  {
private:
   GuardianPersistedState *m_state;
   int      m_featureCount;
   double   m_baseLearnRate;
   double   m_lambda;
   double   m_decay;
   int      m_snapshotBars;
   bool     m_debug;
   datetime m_lastUpdate;
   int      m_updateCount;
   int      m_updatesSinceSnapshot;
   double   m_recentResults[GUARDIAN_MAX_RECENT_RESULTS];
   int      m_recentIndex;
   int      m_recentCount;

   double Sigmoid(const double x) const
     {
      if(x>50.0) return 1.0;
      if(x<-50.0) return 0.0;
      return 1.0/(1.0+MathExp(-x));
     }

   double FeatureStd(const int index) const
     {
      if(m_state==NULL)
         return 1.0;
      if((*m_state).feature_updates<=1)
         return 1.0;
      double variance=(*m_state).feature_vars[index]/(double)((*m_state).feature_updates-1);
      if(variance<=1e-12)
         return 1.0;
      return MathSqrt(variance);
     }

   void UpdateMoments(const double &features[])
     {
      if(m_state==NULL)
         return;
      (*m_state).feature_updates++;
      for(int i=0;i<m_featureCount;++i)
        {
         double value=features[i];
         double mean=(*m_state).feature_means[i];
         double delta=value-mean;
         double count=(double)(*m_state).feature_updates;
         double newMean=mean+delta/count;
         double delta2=value-newMean;
         (*m_state).feature_means[i]=newMean;
         (*m_state).feature_vars[i]+=delta*delta2;
        }
     }

   void ScaleFeatures(const double &features[],double &scaled[]) const
     {
      ArrayResize(scaled,m_featureCount);
      for(int i=0;i<m_featureCount;++i)
        {
         double mean=(m_state!=NULL)?(*m_state).feature_means[i]:0.0;
         double std=(m_state!=NULL)?FeatureStd(i):1.0;
         if(std<=1e-6)
            scaled[i]=features[i]-mean;
         else
            scaled[i]=(features[i]-mean)/std;
        }
     }

   void PrepareScaled(const double &features[],double &scaled[],const bool updateStats)
     {
      if(updateStats)
         UpdateMoments(features);
      ScaleFeatures(features,scaled);
     }

   void TakeSnapshot()
     {
      if(m_state==NULL)
         return;
      ArrayCopy((*m_state).snapshot_weights,(*m_state).weights,m_featureCount);
      (*m_state).snapshot_bias=(*m_state).bias;
      (*m_state).snapshot_timestamp=TimeCurrent();
      m_updatesSinceSnapshot=0;
      GuardianStateStore::Save(*m_state);
     }

   void RollbackToSnapshot()
     {
      if(m_state==NULL)
         return;
      if((*m_state).snapshot_timestamp==0)
         return;
      ArrayCopy((*m_state).weights,(*m_state).snapshot_weights,m_featureCount);
      (*m_state).bias=(*m_state).snapshot_bias;
      (*m_state).weights_timestamp=TimeCurrent();
      GuardianStateStore::Save(*m_state);
      GuardianUtils::PrintInfo("Online learner rolled back to last snapshot");
     }

public:
   OnlineLearner():m_state(NULL),m_featureCount(0),m_baseLearnRate(0.01),m_lambda(0.0),m_decay(0.0),
                   m_snapshotBars(0),m_debug(false),m_lastUpdate(0),m_updateCount(0),
                   m_updatesSinceSnapshot(0),m_recentIndex(0),m_recentCount(0)
     {
      ArrayInitialize(m_recentResults,0.0);
     }

   bool Init(GuardianPersistedState &state,const int featureCount,const double learnRate,const bool debug,
             const double lambda,const double decay,const int snapshotBars)
     {
      m_state=&state;
      m_featureCount=MathMin(featureCount,GUARDIAN_MAX_FEATURES);
      m_baseLearnRate=learnRate;
      m_lambda=MathMax(0.0,lambda);
      m_decay=MathMax(0.0,decay);
      m_snapshotBars=snapshotBars;
      m_debug=debug;
      if((*m_state).weights_count!=m_featureCount)
        {
         (*m_state).weights_count=m_featureCount;
         ArrayInitialize((*m_state).weights,0.0);
         (*m_state).bias=0.0;
         ArrayInitialize((*m_state).feature_means,0.0);
         ArrayInitialize((*m_state).feature_vars,0.0);
         (*m_state).feature_updates=0;
         ArrayInitialize((*m_state).snapshot_weights,0.0);
         (*m_state).snapshot_bias=0.0;
         (*m_state).snapshot_timestamp=0;
         GuardianStateStore::Save(*m_state);
        }
      m_updateCount=((*m_state).feature_updates>0)?(*m_state).feature_updates:0;
      m_updatesSinceSnapshot=0;
      m_lastUpdate=(*m_state).weights_timestamp;
      return true;
     }

   double Score(const double &features[]) const
     {
      if(m_state==NULL)
         return 0.5;
      double scaled[];
      ScaleFeatures(features,scaled);
      double sum=(*m_state).bias;
      for(int i=0;i<m_featureCount;++i)
         sum+=(*m_state).weights[i]*scaled[i];
      return Sigmoid(sum);
     }

   void Update(const double &features[],const double label)
     {
      if(m_state==NULL || m_baseLearnRate<=0.0)
         return;
      double scaled[];
      PrepareScaled(features,scaled,true);
      double lr=m_baseLearnRate/(1.0+m_decay*m_updateCount);
      m_updateCount++;
      double pred;
      // compute dot product using scaled features
      double sum=(*m_state).bias;
      for(int i=0;i<m_featureCount;++i)
         sum+=(*m_state).weights[i]*scaled[i];
      pred=Sigmoid(sum);
      double error=pred-label;
      for(int i=0;i<m_featureCount;++i)
        {
         double grad=error*scaled[i]+m_lambda*(*m_state).weights[i];
         (*m_state).weights[i]-=lr*grad;
        }
      (*m_state).bias-=lr*error;
      (*m_state).weights_timestamp=TimeCurrent();
      m_lastUpdate=(*m_state).weights_timestamp;
      m_updatesSinceSnapshot++;
      GuardianStateStore::Save(*m_state);
      if(m_snapshotBars>0 && m_updatesSinceSnapshot>=m_snapshotBars)
         TakeSnapshot();
     }

   void Decay(const double factor)
     {
      if(m_state==NULL || m_baseLearnRate<=0.0)
         return;
      for(int i=0;i<m_featureCount;++i)
         (*m_state).weights[i]*=factor;
      (*m_state).bias*=factor;
      GuardianStateStore::Save(*m_state);
     }

   void OnTradeClosed(const double profit)
     {
      if(m_state==NULL)
         return;
      m_recentResults[m_recentIndex]=profit;
      m_recentIndex=(m_recentIndex+1)%GUARDIAN_MAX_RECENT_RESULTS;
      if(m_recentCount<GUARDIAN_MAX_RECENT_RESULTS)
         m_recentCount++;
      int losses=0;
      for(int i=0;i<m_recentCount;++i)
        {
         if(m_recentResults[i]<0.0)
            losses++;
        }
      if(m_recentCount==GUARDIAN_MAX_RECENT_RESULTS && losses>=3)
         RollbackToSnapshot();
     }

   datetime LastUpdateTime() const { return m_lastUpdate; }
  };

#endif // XAU_GUARDIAN_ONLINELEARNER_MQH
