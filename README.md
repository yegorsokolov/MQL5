# XAU Guardian Expert Advisor

XAU Guardian is a production-focused MetaTrader 5 Expert Advisor tailored for **XAUUSD**. It enforces strict floating and daily drawdown protections, blocks hedging, maintains constrained lot sizing, and ships with a self-learning signal booster that runs entirely in MQL5 (VPS-friendly).

## Repository layout

```
MQL5/
  Experts/
    XAU_Guardian/
      XAU_Guardian.mq5             # Main EA entry point
      modules/
        Utils.mqh                  # Helpers, persistence, filesystem utilities
        RiskManager.mqh            # Floating & daily drawdown guards, cooldown logic
        Positioning.mqh            # Lot sizing, 1.9× ratio enforcement, hedge checks
        Indicators.mqh             # Indicator handle management + feature builder
        Strategy.mqh               # Signal evaluation, order flow, session filters
        Trailing.mqh               # Two-sided trailing management
        OnlineLearner.mqh          # Logistic online learner, state sync
        Analytics.mqh              # Lightweight trade/position logs
  Indicators/
    XAU_TVF.mq5                   # Trend–Volatility Fusion custom indicator
    XAU_Squeeze.mq5               # Volatility squeeze + breakout probability indicator
  Files/
    XAU_Guardian/
      state.json                  # Persisted risk & learner state (auto-created)
      logs/                       # Rotating analytics + order logs (auto-created)
```

Place the folders inside your terminal's **MQL5** data directory and compile the EA plus the two indicators from MetaEditor.

## Core features

- **Hard risk limits**
  - Floating drawdown capped at `Inp_VirtualBalance * Inp_FloatingDD_Limit` (default 0.9%). If breached, all trades close and a cooldown timer blocks new entries.
  - Daily drawdown capped at `Inp_VirtualBalance * Inp_DailyDD_Limit` (default 3.85%). Breach forces flat and locks trading until the next broker day.
  - Both limits operate on a configurable *virtual balance*, independent of the live account balance.
- **No hedging** and lot-ratio discipline: the largest active position may not exceed `Inp_MaxLotMultiplier` × the smallest open lot (default multiplier 1.9).
- **Session controls**: optional night-session block, automatic next-day unlock, and spread guard.
- **Signal stack**
  - Built-in indicators (ATR, RSI multi-timeframe, CCI, ADX, Bollinger Bands, EMA slope).
  - Custom indicators:
    - `XAU_TVF.mq5` exposes a normalised trend score and volatility pressure blend.
    - `XAU_Squeeze.mq5` flags squeeze conditions and outputs a breakout bias.
  - All readings are transformed into a 14-feature vector for the strategy and learner.
- **Execution flow**
  - Every order carries TP/SL and feeds into a symmetric trailing manager once profit exceeds `Inp_TrailStartPoints`.
  - Trailing also softens adverse moves using ATR-derived caps when enabled.
  - Risk checks run on every tick, timer pulse, and trade transaction.
- **Online learner**
  - Pure MQL5 logistic regression updated per completed bar (default timeframe `Inp_TF1`).
  - Weights plus bias persist to `MQL5/Files/XAU_Guardian/state.json` so MetaQuotes VPS migrations keep the adaptive signal.
  - Set `Inp_UseOnlineLearning=false` to freeze the learner (weights stay but stop updating).
- **Analytics & logging**
  - Trade results, floating P/L snapshots, and executed orders append to `logs/` under the EA files directory for quick audits.

## Inputs overview

| Input | Description |
| --- | --- |
| `Inp_VirtualBalance` | Risk model balance used for DD caps. |
| `Inp_FloatingDD_Limit` / `Inp_DailyDD_Limit` | Fractional drawdown limits. |
| `Inp_BaseLot`, `Inp_MaxLotMultiplier` | Session base lot and max ratio constraint. |
| `Inp_TP_Points`, `Inp_SL_Points` | Initial TP/SL in points. |
| `Inp_TrailStartPoints`, `Inp_TrailStepPoints` | Profit threshold and trail step for the two-sided trailing logic. |
| `Inp_CooldownMinutes` | Minutes to block entries after floating DD breach. |
| `Inp_MinTrendScore`, `Inp_MinADX`, `Inp_RSI_Long`, `Inp_RSI_Short` | Indicator thresholds for long/short regimes. |
| `Inp_SpreadLimit` | Maximum allowed spread (points) for entries. |
| `Inp_NightBlock`, `Inp_NightStartHour`, `Inp_NightEndHour` | Optional time-of-day block window (broker time). |
| `Inp_TF1`, `Inp_TF2`, `Inp_TF3`, `Inp_FeatureWindow` | Feature timeframe mix and lookback. |
| `Inp_UseOnlineLearning`, `Inp_LearnRate`, `Inp_MinLearnerProb` | Online learner controls. |
| `Inp_AdverseATRF` | ATR multiple for adverse trailing soft-stop (0 disables). |
| `Inp_DebugLogs` | Enables verbose Print logs for diagnostics. |

## Operation & lifecycle

1. **OnInit** sets up folders, loads persisted state, initialises indicator handles, and schedules a 60-second timer.
2. **OnTick**
   - Runs daily and floating drawdown guards (hard exits + cooldown/lock management).
   - Applies trailing stop adjustments across EA positions.
   - Evaluates the strategy stack and issues new trades if all filters pass.
3. **OnTimer** refreshes the daily anchor, performs learner updates on completed bars, and emits lightweight analytics.
4. **OnTradeTransaction** reacts to fills/closures to keep statistics, session lot floors, and risk state synchronized.

## MetaQuotes VPS migration checklist

1. Attach `XAU_Guardian.mq5` to **XAUUSD** on your chosen chart timeframe (defaults tuned for M15).
2. Ensure `XAU_TVF.mq5` and `XAU_Squeeze.mq5` are compiled under *Indicators*.
3. Verify `MQL5/Files/XAU_Guardian/` is writable (state + logs appear after first run).
4. Migrate using *Register a Virtual Server → Migrate experts and indicators*. Check the VPS journal for success.

## Notes

- The EA closes and blocks trading immediately upon risk-limit breaches—manual intervention is rarely required.
- All persistence uses simple JSON in `state.json`; deleting the file resets session lot floors, locks, and learner weights.
- The online learner updates once per completed bar on `Inp_TF1`. Consider lowering `Inp_LearnRate` if deploying to live capital.

Happy guarding!
