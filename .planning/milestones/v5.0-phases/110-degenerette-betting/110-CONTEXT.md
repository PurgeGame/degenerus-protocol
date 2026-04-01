# Phase 110: Degenerette Betting - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of DegenerusGameDegeneretteModule.sol -- the Degenerette symbol-roll betting module. This phase examines every state-changing function in the module using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The module handles:
- Full Ticket bet placement (4-trait matching with custom tickets, multi-spin support)
- Bet resolution with lootbox RNG words (deterministic outcome derivation)
- Multi-currency support: ETH, BURNIE, and WWXRP with per-currency payout paths
- Activity score computation (streak, quest, affiliate, deity/whale bonuses)
- Per-outcome EV normalization (product-of-ratios trait weight equalization)
- Hero quadrant boost/penalty system (EV-neutral per-match-count multipliers)
- ETH payout distribution: 25% ETH (capped at 10% of pool), 75% lootbox conversion
- Direct lootbox resolution via delegatecall to LootboxModule
- sDGNRS rewards from Reward pool on 6+ match ETH bets
- Consolation prizes (1 WWXRP) for qualifying losing bets
- Hero wager tracking (daily hero symbol wagers packed per quadrant)
- Per-player per-level ETH wagered leaderboard

This phase does NOT re-audit module internals of LootboxModule (resolveLootboxDirect), BurnieCoin, WWXRP, sDGNRS, Affiliate, or Quests contracts. Cross-module calls are traced far enough to verify state coherence in the calling context.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. This is a module, not the router. Category A (delegatecall dispatchers) does not apply. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states (MULTI-PARENT).

### Fresh Analysis Mandate
- **D-06:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v3.7/v3.8 or any prior audit. The entire point of v5.0 is catching bugs that survived 24 prior milestones. Prior audit results are not input to this phase.
- **D-07:** All payout math, EV normalization, and trait matching functions get the same full treatment as every other function. No reduced scrutiny for "math looks correct."

### Cross-Module Call Boundary
- **D-08:** When Degenerette functions chain into delegatecall targets (resolveLootboxDirect), external calls (coin.burnCoin, coin.mintForGame, wwxrp.burnForGame, wwxrp.mintPrize, sdgnrs.poolBalance, sdgnrs.transferFromPool), or inherited helpers (_creditClaimable, _getPrizePools, _setPrizePools, _getFuturePrizePool, _setFuturePrizePool), trace the subordinate calls far enough to verify the parent's state coherence -- specifically the cached-local-vs-storage check.
- **D-09:** If a subordinate call writes to storage that the parent has cached locally, that IS a finding for this phase regardless of which module the subordinate lives in. The BAF pattern is what we're hunting.

### Multi-Currency Payout Paths
- **D-10:** Each currency (ETH/BURNIE/WWXRP) has a distinct payout distribution path. ETH path involves futurePrizePool deduction + lootbox conversion via delegatecall. BURNIE path mints via coin.mintForGame. WWXRP path mints via wwxrp.mintPrize. All three paths must be traced for state coherence independently.

### Report Format
- **D-11:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering)
- Level of detail in cross-module subordinate call traces (enough to verify state coherence, no more)
- Whether to split the attack report into multiple files if it exceeds reasonable length

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contract
- `contracts/modules/DegenerusGameDegeneretteModule.sol` -- The audit target (1,179 lines, 2 external entry points, ~25 private helpers)

### Inherited Contracts
- `contracts/modules/DegenerusGamePayoutUtils.sol` -- Parent class (ETH credit helpers, auto-rebuy calc)
- `contracts/modules/DegenerusGameMintStreakUtils.sol` -- Grandparent class (62 lines, mint streak tracking)
- `contracts/storage/DegenerusGameStorage.sol` -- Shared storage layout and helpers

### External Call Targets
- `contracts/BurnieCoin.sol` -- burnCoin, mintForGame, notifyQuestDegenerette
- `contracts/WrappedWrappedXRP.sol` -- burnForGame, mintPrize
- `contracts/StakedDegenerusStonk.sol` -- poolBalance, transferFromPool
- `contracts/DegenerusAffiliate.sol` -- affiliateBonusPointsBest
- `contracts/DegenerusQuests.sol` -- playerQuestStates (view)

### Module Interface
- `contracts/interfaces/IDegenerusGameModules.sol` -- Module function signatures

### Trait System
- `contracts/DegenerusTraitUtils.sol` -- packedTraitsFromSeed (generates result tickets from RNG)

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/103-game-router-storage-layout/103-CONTEXT.md` -- Phase 103 context (Category B/C/D pattern, report format)
- `audit/unit-06/COVERAGE-CHECKLIST.md` -- Phase 108 Taskmaster output (format reference)
- `audit/unit-06/ATTACK-REPORT.md` -- Phase 108 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions (from source)
- `placeFullTicketBets(address,uint8,uint128,uint8,uint32,uint8)` (L388) -- External entry point, bet placement
- `resolveBets(address,uint64[])` (L411) -- External entry point, multi-bet resolution
- `_placeFullTicketBets(address,uint8,uint128,uint8,uint32,uint8)` (L430) -- Private: orchestrates bet placement + fund collection + quest notify
- `_placeFullTicketBetsCore(address,uint8,uint128,uint8,uint32,uint8)` (L462) -- Private: validates, packs bet, records hero wagers + leaderboard
- `_collectBetFunds(address,uint8,uint256,uint256)` (L541) -- Private: burns tokens or handles ETH pool accounting
- `_resolveBet(address,uint64)` (L577) -- Private: unpacks bet, dispatches to full ticket resolver
- `_resolveFullTicketBet(address,uint64,uint256)` (L585) -- Private: main resolution loop (spin, match, payout, DGNRS)
- `_distributePayout(address,uint8,uint256,uint256)` (L680) -- Private: per-currency payout distribution with ETH cap + lootbox
- `_resolveLootboxDirect(address,uint256,uint256)` (L741) -- Private: delegatecall to LootboxModule
- `_fullTicketPayout(uint32,uint32,uint8,uint8,uint128,uint256,uint256,bool,uint8)` (L912) -- Private pure: payout calculation with EV normalization
- `_evNormalizationRatio(uint32,uint32)` (L803) -- Private pure: per-outcome probability ratio product
- `_countMatches(uint32,uint32)` (L852) -- Private pure: attribute matching (0-8 matches)
- `_applyHeroMultiplier(uint256,uint32,uint32,uint8,uint8)` (L966) -- Private pure: hero quadrant boost/penalty
- `_playerActivityScoreInternal(address)` (L1005) -- Private view: activity score computation
- `_roiBpsFromScore(uint256)` (L1098) -- Private pure: score-to-ROI mapping curve
- `_wwxrpHighValueRoi(uint256)` (L1135) -- Private pure: WWXRP bonus ROI target
- `_addClaimableEth(address,uint256)` (L1153) -- Private: credits ETH to player claimable balance
- `_awardDegeneretteDgnrs(address,uint256,uint8)` (L1164) -- Private: sDGNRS reward from Reward pool
- `_maybeAwardConsolation(address,uint8,uint128)` (L722) -- Private: consolation WWXRP prize
- `_validateMinBet(uint8,uint128)` (L528) -- Private pure: minimum bet validation
- `_packFullTicketBet(uint32,uint8,uint8,uint128,uint48,uint16,uint8)` (L764) -- Private pure: bit packing
- `_getBasePayoutBps(uint8)` (L990) -- Private pure: match-count to payout table lookup
- `_wwxrpBonusBucket(uint8)` (L880) -- Private pure: bucket assignment
- `_wwxrpBonusRoiForBucket(uint8,uint256)` (L888) -- Private pure: bucket-specific ROI scaling
- `_revertDelegate(bytes)` (L141) -- Private pure: delegatecall error propagation
- `_requireApproved(address)` (L150) -- Private view: operator approval check
- `_resolvePlayer(address)` (L160) -- Private view: player resolution with approval check

### Established Pattern (from Phases 103-108)
- 4-plan structure: Taskmaster checklist -> Mad Genius attack -> Skeptic review -> Final report
- Category B/C/D classification with risk tiers for Category B
- Taskmaster must achieve 100% coverage before unit advances to Skeptic
- Output goes to `audit/unit-08/` directory

### Integration Points
- placeFullTicketBets is dispatched via delegatecall from DegenerusGame.sol router
- resolveBets is dispatched via delegatecall from DegenerusGame.sol router
- _distributePayout ETH path deducts from futurePrizePool -- state coherence with advanceGame is critical
- _resolveLootboxDirect delegatecalls to LootboxModule (which also runs in Game storage context)
- _collectBetFunds ETH path adds to futurePrizePool and lootboxRngPendingEth
- coin.notifyQuestDegenerette updates quest progress externally
- _playerActivityScoreInternal reads from questView and affiliate contracts

</code_context>

<specifics>
## Specific Ideas

No special priority investigations beyond the standard methodology. Key focus areas:

1. **ETH Pool Accounting:** _collectBetFunds adds to futurePrizePool. _distributePayout deducts from futurePrizePool. Race condition if prizePoolFrozen check has gaps.
2. **Delegatecall State Coherence:** _resolveLootboxDirect delegatecalls to LootboxModule. Both modules operate on the same storage. Verify no stale cache after return.
3. **Claimable ETH Pull for Bets:** _collectBetFunds allows partial ETH + partial claimableWinnings. Off-by-one in comparison (`<=` vs `<` at L552).
4. **RNG Commitment Window:** Bets are placed before lootboxRngWordByIndex[index] is fulfilled. Verify player cannot manipulate inputs between VRF request and fulfillment.
5. **Activity Score Snapshot at Bet Time:** Score is computed at placement time and stored in packed bet. Verify resolution correctly uses the stored score, not a re-computed one.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 111 coordination:** `_resolveLootboxDirect` delegatecalls to LootboxModule. Full audit of LootboxModule internals is in Phase 111. This phase traces far enough to verify state coherence post-delegatecall.
- **Phase 117 coordination:** DegenerusTraitUtils.packedTraitsFromSeed is a library function. Full audit of libraries is in Phase 117. This phase verifies the calling context only.
- **Phase 118:** Full cross-module state coherence verification is deferred to the integration sweep.

</deferred>

---

*Phase: 110-degenerette-betting*
*Context gathered: 2026-03-25*
