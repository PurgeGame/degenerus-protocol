# Phase 116: Affiliate + Quests + Jackpots - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for execution

<domain>
## Phase Boundary

Adversarial audit of three standalone peripheral contracts as a single unit (Unit 14):
- **DegenerusAffiliate.sol** (~840 lines) -- Multi-tier affiliate referral system with configurable kickback, leaderboard tracking, and lootbox activity taper
- **DegenerusQuests.sol** (~1598 lines) -- Daily quest rolling via VRF entropy, per-player progress tracking with version-gated resets, streak accounting
- **DegenerusJackpots.sol** (~650 lines) -- BAF (Big Ass Flip) jackpot system with leaderboard-based ETH distribution, scatter rounds, far-future ticket draws

These are standalone contracts (NOT delegatecall modules). They maintain their own storage and are called by the game contract and BurnieCoin via fixed addresses (ContractAddresses.sol). Each has its own access control (onlyCoin, onlyGame, onlyAuthorized modifiers).

**Key attack surfaces:**
- Affiliate self-referral loops and circular upline chains
- Commission cap bypass via multi-sender coordination
- Quest reward farming through progress manipulation
- BAF leaderboard manipulation via epoch/score gaming
- Weighted random winner selection with deterministic PRNG
- Unchecked arithmetic in unchecked blocks (overflow in bafTotals)
- Cross-contract state assumptions (game level, mint price, presale flag)

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. These are standalone contracts, not delegatecall modules. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They get standalone attack sections only when called from multiple parents with different cached-local states (MULTI-PARENT standalone).

### Audit Approach
- **D-04:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v1.0-v4.4. The entire point of v5.0 is catching bugs that survived 24 prior milestones.
- **D-05:** Cross-module trace for state coherence: when these contracts call into the game contract or BurnieCoin, trace the subordinate calls far enough to verify state assumptions are valid. Full internals of those contracts are audited in their own unit phases.
- **D-06:** Three-contract scope treated as single unit. Affiliate<->Quests interaction via affiliateQuestReward() is a priority cross-contract trace.

### Report Format
- **D-07:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering)
- Level of detail in cross-contract subordinate call traces (enough to verify state coherence, no more)
- Whether to split the attack report into sections per contract or interleave by risk tier

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contracts
- `contracts/DegenerusAffiliate.sol` -- Multi-tier affiliate referral (~840 lines, 15+ functions)
- `contracts/DegenerusQuests.sol` -- Daily quest system (~1598 lines, 30+ functions)
- `contracts/DegenerusJackpots.sol` -- BAF jackpot system (~650 lines, 12+ functions)

### Interfaces
- `contracts/interfaces/IDegenerusAffiliate.sol` -- Affiliate interface
- `contracts/interfaces/IDegenerusQuests.sol` -- Quests interface with shared structs
- `contracts/interfaces/IDegenerusJackpots.sol` -- Jackpots interface

### Cross-Contract Integration Points
- `contracts/BurnieCoin.sol` -- Calls quest handlers (handleMint, handleFlip, etc.) and affiliate payAffiliate
- `contracts/BurnieCoinflip.sol` -- Calls recordBafFlip on Jackpots, quest handlers
- `contracts/modules/DegenerusGameMintModule.sol` -- Calls payAffiliate for purchase flows
- `contracts/modules/DegenerusGameEndgameModule.sol` -- Calls runBafJackpot for level-end distribution

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `audit/unit-12/COVERAGE-CHECKLIST.md` -- Recent Taskmaster output (format reference)
- `audit/unit-12/ATTACK-REPORT.md` -- Recent Mad Genius output (format reference)
- `audit/unit-12/SKEPTIC-REVIEW.md` -- Recent Skeptic output (format reference)
- `audit/unit-12/UNIT-12-FINDINGS.md` -- Recent final report (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### DegenerusAffiliate Key Functions
- `createAffiliateCode(bytes32, uint8)` -- External, anyone can create affiliate codes
- `referPlayer(bytes32)` -- External, player registers under affiliate code
- `payAffiliate(uint256, bytes32, address, uint24, bool, uint16)` -- External, coin/game only, core payout logic
- `_createAffiliateCode(address, bytes32, uint8)` -- Private, shared code registration
- `_bootstrapReferral(address, bytes32)` -- Private, constructor-time referral setup
- `_setReferralCode(address, bytes32)` -- Private, referral storage + event
- `_referrerAddress(address)` -- Private view, resolve referrer from stored code
- `_routeAffiliateReward(address, uint256)` -- Private, sends FLIP via coin.creditFlip
- `_rollWeightedAffiliateWinner(...)` -- Private view, deterministic weighted winner selection
- `_updateTopAffiliate(address, uint256, uint24)` -- Private, leaderboard update
- `_applyLootboxTaper(uint256, uint16)` -- Private pure, linear payout reduction
- `_vaultReferralMutable(bytes32)` -- Private view, presale referral mutability check
- `_score96(uint256)` -- Private pure, uint96 capping

### DegenerusQuests Key Functions
- `rollDailyQuest(uint48, uint256)` -- External, coin only, VRF-based quest rolling
- `awardQuestStreakBonus(address, uint16, uint48)` -- External, game only
- `handleMint(address, uint32, bool)` -- External, coin only, mint progress
- `handleFlip(address, uint256)` -- External, coin only, flip progress
- `handleDecimator(address, uint256)` -- External, coin only, decimator progress
- `handleAffiliate(address, uint256)` -- External, coin only, affiliate progress
- `handleLootBox(address, uint256)` -- External, coin only, lootbox progress
- `handleDegenerette(address, uint256, bool)` -- External, coin only, degenerette progress
- `_rollDailyQuest(uint48, uint256)` -- Private, quest rolling logic
- `_questSyncState(...)` -- Private, streak reset + day sync
- `_questSyncProgress(...)` -- Private, progress version invalidation
- `_questComplete(...)` -- Private, slot completion + streak credit
- `_questCompleteWithPair(...)` -- Private, paired completion check
- `_questHandleProgressSlot(...)` -- Private, progress accumulation
- `_bonusQuestType(...)` -- Private pure, weighted random quest selection
- `_questTargetValue(...)` -- Private pure, fixed target calculation
- `_seedQuestType(...)` -- Private, quest slot seeding

### DegenerusJackpots Key Functions
- `recordBafFlip(address, uint24, uint256)` -- External, coin only, leaderboard recording
- `runBafJackpot(uint256, uint24, uint256)` -- External, game only, full BAF distribution
- `_updateBafTop(uint24, address, uint256)` -- Private, sorted top-4 leaderboard maintenance
- `_bafTop(uint24, uint8)` -- Private view, leaderboard position lookup
- `_clearBafTop(uint24)` -- Private, post-resolution leaderboard cleanup
- `_bafScore(address, uint24)` -- Private view, epoch-aware score lookup
- `_score96(uint256)` -- Private pure, uint96 capping
- `_creditOrRefund(...)` -- Private pure, prize crediting helper

### Integration Points
- Affiliate.payAffiliate() calls coin.creditFlip(), coin.creditFlipBatch(), coin.affiliateQuestReward()
- Quests.handleMint/Flip/etc. called by BurnieCoin on every player action
- Quests.rollDailyQuest() called by BurnieCoin on day transitions
- Jackpots.recordBafFlip() called by BurnieCoin/BurnieCoinflip on coinflips
- Jackpots.runBafJackpot() called by game endgame module at level end
- Jackpots.runBafJackpot() calls degenerusGame.sampleFarFutureTickets() and degenerusGame.sampleTraitTicketsAtLevel()

</code_context>

<specifics>
## Specific Ideas

No specific requirements beyond the ULTIMATE-AUDIT-DESIGN.md methodology. The three-agent system (Taskmaster checklist -> Mad Genius attack -> Skeptic review) drives the workflow, same as all prior units.

**Priority attention areas:**
1. **Affiliate self-referral prevention** -- verify _referrerAddress chain cannot loop back to sender
2. **Unchecked overflow in recordBafFlip** -- `unchecked { total += amount; }` at L176 of Jackpots
3. **Deterministic PRNG in affiliate winner roll** -- uses keccak256(day, sender, code), is this exploitable?
4. **Quest slot ordering dependency** -- slot 1 requires slot 0 completion first, verify no bypass
5. **BAF scatter level targeting** -- verify entropy-based level selection cannot be gamed
6. **Commission cap per-referrer-per-level** -- verify cannot be bypassed via affiliate code rotation

</specifics>

<deferred>
## Deferred Ideas

- **Phase 118 coordination**: Cross-contract state coherence for Affiliate<->BurnieCoin<->Game interactions
- **Phase 119**: Access control matrix entry for all external functions in these three contracts

</deferred>

---

*Phase: 116-affiliate-quests-jackpots*
*Context gathered: 2026-03-25*
