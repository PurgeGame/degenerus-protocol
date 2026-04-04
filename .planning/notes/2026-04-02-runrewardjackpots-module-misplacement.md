---
date: "2026-04-02 00:00"
promoted: false
---

runRewardJackpots lives in EndgameModule but is pure BAF/Decimator jackpot resolution — not endgame logic. Creates an unnecessary double-hop: AdvanceModule → delegatecall EndgameModule → call Game → delegatecall DecimatorModule. Consider moving it to JackpotModule or inlining the pool math in AdvanceModule to eliminate the extra delegatecall.
