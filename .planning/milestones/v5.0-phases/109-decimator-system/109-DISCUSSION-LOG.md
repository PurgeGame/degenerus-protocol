# Phase 109: Decimator System - Discussion Log

## 2026-03-25: Phase Initialization

**Decision:** Phase 109 covers DegenerusGameDecimatorModule.sol as Unit 7 of the v5.0 Ultimate Adversarial Audit.

**Key decisions locked in CONTEXT.md:**
- Categories B/C/D only, no Category A (module, not router)
- Full Mad Genius treatment on all Category B functions
- MULTI-PARENT standalone analysis where applicable
- Auto-rebuy BAF pattern is #1 priority investigation
- Terminal decimator storage collision with regular decimator needs analysis
- Fresh analysis mandate -- no trust of prior audit findings

**Auto-rebuy BAF pattern concern:**
The claimDecimatorJackpot function at line 336 reads _getFuturePrizePool(), then calls _creditDecJackpotClaimCore which chains into _addClaimableEth -> _processAutoRebuy -> _setFuturePrizePool(). This is the exact pattern that caused the original BAF cache-overwrite bug. The Mad Genius must trace whether the outer read is cached in a local variable before the inner write occurs, or if it re-reads from storage after the subordinate returns.

**Terminal decimator / regular decimator offset collision:**
Both runDecimatorJackpot and runTerminalDecimatorJackpot write to decBucketOffsetPacked[lvl]. If both run at the same level, the second write would overwrite the first. This needs analysis: can both execute at the same level?

---

*No further discussion items at this time.*
