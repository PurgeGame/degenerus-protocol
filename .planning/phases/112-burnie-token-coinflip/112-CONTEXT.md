# Phase 112: BURNIE Token + Coinflip - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of BurnieCoin.sol and BurnieCoinflip.sol -- the ERC20 token and daily coinflip wagering system (Unit 10). This phase examines every state-changing function across both contracts using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The contracts handle:

- ERC20 standard (transfer, transferFrom, approve) with game-contract transfer bypass
- Mint/burn authority gates for game, coinflip, vault, and admin
- Vault escrow: 2M BURNIE virtual reserve, minted only on VAULT withdrawal
- Flip credit accounting delegated to BurnieCoinflip
- Decimator burns with activity-weighted bucket calculation
- Terminal decimator (death bet) burns
- Quest integration hub: daily quest rolls, streak tracking, mint/lootbox/degenerette/affiliate quest notifications
- Daily coinflip system: deposit, claim, auto-rebuy, bounty system, day resolution
- afKing mode recycling bonuses with deity pass scaling
- BAF leaderboard credit recording during coinflip claim processing
- Bounty system: record-breaking flip detection, bounty arming/resolution
- Coinflip payout processing (called by game during advanceGame)
- WWXRP consolation prizes on coinflip losses
- Coinflip lock during BAF resolution to prevent front-running

This phase does NOT re-audit module internals of DegenerusGame, DegenerusQuests, DegenerusJackpots, or other contracts called via subordinate paths. Cross-module calls are traced far enough to verify state coherence in the calling context.

**KEY ARCHITECTURAL FEATURE:** BurnieCoin and BurnieCoinflip are STANDALONE contracts (not modules executing via delegatecall in Game's storage). They have their own storage. Cross-contract interactions go through external calls, not delegatecall. This means the BAF cache-overwrite pattern manifests differently here -- the risk is that BurnieCoin caches a balance or supply value, calls into BurnieCoinflip which calls back into BurnieCoin (e.g., mintForCoinflip/burnForCoinflip), and the original cached value is now stale.

**CRITICAL INTERACTION PATTERN:** BurnieCoin._claimCoinflipShortfall auto-claims coinflip winnings when a player's balance is insufficient for a transfer/burn. This creates a re-entrant-like flow: BurnieCoin.transfer -> _claimCoinflipShortfall -> BurnieCoinflip.claimCoinflipsFromBurnie -> BurnieCoin.mintForCoinflip -> _mint. The auto-claim path modifies balanceOf[] and _supply before the parent transfer completes.

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. These are standalone contracts, not the delegatecall router. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They do NOT get standalone attack sections unless they are called from multiple parents with different cached-local states (MULTI-PARENT).

### Two-Contract Scope
- **D-04:** Both BurnieCoin.sol and BurnieCoinflip.sol are audited as a single unit. BurnieCoinflip is the extracted coinflip system that relies on BurnieCoin for token burn/mint operations. They are architecturally one system split for contract size management.
- **D-05:** BurnieCoin functions that serve as permission gates for BurnieCoinflip (burnForCoinflip, mintForCoinflip) are Category B for this unit -- they are external entry points callable only by the coinflip contract.

### Cross-Contract Callback Investigation
- **D-06:** The auto-claim pattern (transfer -> _claimCoinflipShortfall -> BurnieCoinflip -> mintForCoinflip -> _mint) is a PRIORITY investigation area. The Mad Genius must verify that no storage cached locally in _transfer or the calling function is written by the _mint triggered through BurnieCoinflip callback.
- **D-07:** The _consumeCoinflipShortfall pattern in burnCoin and decimatorBurn follows the same auto-claim chain. Must verify CEI ordering is correct -- burns must complete before downstream calls.

### Fresh Analysis Mandate
- **D-08:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v1.0-v4.4. The entire point of v5.0 is catching bugs that survived 24 prior milestones.
- **D-09:** Coinflip payout resolution (processCoinflipPayouts) and auto-rebuy carry mechanics get the same full treatment. No reduced scrutiny for "already audited" code.

### Cross-Module Call Boundary
- **D-10:** When functions chain into code from other contracts (DegenerusQuests, DegenerusJackpots, DegenerusGame, WWXRP), trace the subordinate calls far enough to verify the parent's state coherence. Full internals are audited in their own unit phases.
- **D-11:** If a subordinate call (e.g., BurnieCoinflip calling back BurnieCoin.mintForCoinflip) writes to storage that the parent has cached locally, that IS a finding for this phase.

### Report Format
- **D-12:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

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

### Target Contracts
- `contracts/BurnieCoin.sol` -- ERC20 token with mint/burn authority, vault escrow, quest hub, decimator burns (~1,075 lines)
- `contracts/BurnieCoinflip.sol` -- Daily coinflip system with auto-rebuy, bounty, BAF credit, day resolution (~1,129 lines)

### Contract Address Constants
- `contracts/ContractAddresses.sol` -- Compile-time address constants (COIN, COINFLIP, GAME, VAULT, etc.)

### Interface Definitions
- `contracts/interfaces/IDegenerusGame.sol` -- Game contract interface (rngLocked, purchaseInfo, afKingModeFor, etc.)
- `contracts/interfaces/IDegenerusQuests.sol` -- Quest module interface (handleFlip, handleMint, etc.)
- `contracts/interfaces/IDegenerusJackpots.sol` -- Jackpots interface (recordBafFlip, getLastBafResolvedDay)

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/103-game-router-storage-layout/103-CONTEXT.md` -- Phase 103 context (Category A/B/C/D pattern, report format)
- `audit/unit-01/COVERAGE-CHECKLIST.md` -- Phase 103 Taskmaster output (format reference)
- `audit/unit-01/ATTACK-REPORT.md` -- Phase 103 Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions -- BurnieCoin.sol (from line-by-line read)

**External Entry Points (Category B candidates):**
- `approve(address, uint256)` (L394) -- ERC20 approve
- `transfer(address, uint256)` (L408) -- ERC20 transfer with auto-claim shortfall
- `transferFrom(address, address, uint256)` (L422) -- ERC20 transferFrom with game bypass and auto-claim
- `burnForCoinflip(address, uint256)` (L528) -- Permission gate: coinflip contract burns
- `mintForCoinflip(address, uint256)` (L537) -- Permission gate: coinflip contract mints
- `mintForGame(address, uint256)` (L546) -- Permission gate: game contract mints
- `creditCoin(address, uint256)` (L556) -- Mint BURNIE directly to player (GAME/AFFILIATE)
- `creditFlip(address, uint256)` (L566) -- Forward flip credit to BurnieCoinflip (GAME/AFFILIATE)
- `creditFlipBatch(address[3], uint256[3])` (L574) -- Batch flip credit forwarding
- `creditLinkReward(address, uint256)` (L584) -- ADMIN-only LINK reward credit
- `vaultEscrow(uint256)` (L688) -- Increase vault mint allowance (GAME/VAULT)
- `vaultMintTo(address, uint256)` (L705) -- Mint from vault allowance (VAULT only)
- `affiliateQuestReward(address, uint256)` (L724) -- Affiliate quest processing
- `rollDailyQuest(uint48, uint256)` (L759) -- Quest roll (GAME only)
- `notifyQuestMint(address, uint32, bool)` (L782) -- Mint quest notification (GAME only)
- `notifyQuestLootBox(address, uint256)` (L814) -- Lootbox quest notification (GAME only)
- `notifyQuestDegenerette(address, uint256, bool)` (L841) -- Degenerette quest notification (GAME only)
- `burnCoin(address, uint256)` (L869) -- Gameplay burn (GAME/AFFILIATE) with auto-consume shortfall
- `decimatorBurn(address, uint256)` (L890) -- Decimator window burn with quest + bucket calculation
- `terminalDecimatorBurn(address, uint256)` (L981) -- Death bet burn

**Critical Internal Functions (Category C candidates):**
- `_transfer(address, address, uint256)` (L453) -- Core transfer with vault redirect
- `_mint(address, uint256)` (L479) -- Core mint with vault redirect
- `_burn(address, uint256)` (L499) -- Core burn with vault allowance handling
- `_claimCoinflipShortfall(address, uint256)` (L590) -- Auto-claim on transfer/transferFrom
- `_consumeCoinflipShortfall(address, uint256)` (L603) -- Auto-consume on burn (no mint)
- `_questApplyReward(address, uint256, uint8, uint32, bool)` (L1059) -- Quest reward event emitter
- `_adjustDecimatorBucket(uint256, uint8)` (L1028) -- Bucket calculation (pure)
- `_decimatorBurnMultiplier(uint256)` (L1047) -- Burn multiplier (pure)
- `_toUint128(uint256)` (L443) -- Safe downcast

### Key Functions -- BurnieCoinflip.sol (from line-by-line read)

**External Entry Points (Category B candidates):**
- `settleFlipModeChange(address)` (L215) -- Pre-settle before afKing mode change (GAME only)
- `depositCoinflip(address, uint256)` (L225) -- Deposit BURNIE into daily flip
- `claimCoinflips(address, uint256)` (L326) -- Claim winnings (exact amount)
- `claimCoinflipsFromBurnie(address, uint256)` (L335) -- Claim via BurnieCoin (BURNIE only)
- `claimCoinflipsForRedemption(address, uint256)` (L345) -- Claim for sDGNRS redemption (sDGNRS only)
- `consumeCoinflipsForBurn(address, uint256)` (L365) -- Consume without minting (BURNIE only)
- `setCoinflipAutoRebuy(address, bool, uint256)` (L674) -- Configure auto-rebuy
- `setCoinflipAutoRebuyTakeProfit(address, uint256)` (L689) -- Set take-profit threshold
- `processCoinflipPayouts(bool, uint256, uint48)` (L778) -- Day resolution (GAME only)
- `creditFlip(address, uint256)` (L869) -- Credit flip stake (GAME/BURNIE)
- `creditFlipBatch(address[3], uint256[3])` (L878) -- Batch credit (GAME/BURNIE)

**Critical Internal Functions (Category C candidates):**
- `_depositCoinflip(address, uint256, bool)` (L242) -- Core deposit logic: burn, quest, bonus, stake
- `_claimCoinflipsAmount(address, uint256, bool)` (L373) -- Core claim: process days + mint
- `_claimCoinflipsInternal(address, bool)` (L400) -- Day-by-day claim loop with auto-rebuy carry, BAF credit, WWXRP consolation
- `_addDailyFlip(address, uint256, uint256, bool, bool)` (L608) -- Stake management + bounty arming
- `_setCoinflipAutoRebuy(address, bool, uint256, bool)` (L698) -- Auto-rebuy toggle with settlement
- `_setCoinflipAutoRebuyTakeProfit(address, uint256)` (L752) -- Take-profit update
- `_coinflipLockedDuringTransition()` (L1000) -- BAF resolution lock check
- `_recyclingBonus(uint256)` (L1016) -- 1% bonus capped at 1000 BURNIE
- `_afKingRecyclingBonus(uint256, uint16)` (L1027) -- afKing recycling with deity bonus
- `_afKingDeityBonusHalfBpsWithLevel(address, uint24)` (L1043) -- Deity bonus calculation
- `_targetFlipDay()` (L1060) -- Next coinflip day
- `_updateTopDayBettor(address, uint256, uint48)` (L1092) -- Leaderboard update
- `_bafBracketLevel(uint24)` (L1106) -- Round level to BAF bracket
- `_resolvePlayer(address)` (L1113) -- Player resolution with operator check
- `_requireApproved(address)` (L1124) -- Operator approval check
- `_questApplyReward(...)` (L1065) -- Quest reward event emitter
- `_score96(uint256)` (L1083) -- Score truncation

### Established Pattern (from prior phases)
- 4-plan structure: Taskmaster checklist -> Mad Genius attack -> Skeptic review -> Final report
- Category B/C/D classification with risk tiers for Category B
- Taskmaster must achieve 100% coverage before unit advances to Skeptic
- Output goes to `audit/unit-10/` directory

### Integration Points
- BurnieCoin.transfer/transferFrom -> _claimCoinflipShortfall -> BurnieCoinflip.claimCoinflipsFromBurnie -> BurnieCoin.mintForCoinflip
- BurnieCoin.burnCoin -> _consumeCoinflipShortfall -> BurnieCoinflip.consumeCoinflipsForBurn (no callback to BurnieCoin)
- BurnieCoinflip.depositCoinflip -> BurnieCoin.burnForCoinflip -> _burn
- BurnieCoinflip._claimCoinflipsInternal -> BurnieCoin.mintForCoinflip -> _mint (on claim path)
- BurnieCoinflip._claimCoinflipsInternal -> jackpots.recordBafFlip (BAF credit)
- BurnieCoinflip._claimCoinflipsInternal -> wwxrp.mintPrize (loss consolation)
- BurnieCoinflip.processCoinflipPayouts -> game.payCoinflipBountyDgnrs (DGNRS reward)
- BurnieCoin.decimatorBurn -> game.recordDecBurn / game.consumeDecimatorBoon
- BurnieCoin quest notification functions -> questModule.handle* (external calls)

</code_context>

<specifics>
## Specific Ideas

### Auto-Claim Callback State Coherence (PRIORITY)
The _claimCoinflipShortfall / _consumeCoinflipShortfall patterns create cross-contract callback chains:
1. transfer() reads balanceOf[from], calls _claimCoinflipShortfall which calls BurnieCoinflip.claimCoinflipsFromBurnie
2. BurnieCoinflip processes days, then calls BurnieCoin.mintForCoinflip which calls _mint
3. _mint increases balanceOf[player] and _supply.totalSupply
4. Control returns to transfer() which then calls _transfer() subtracting from balanceOf[from]
5. VERIFY: Is the balance correctly updated? Is there a double-spend window? Does the mint + transfer net correctly?

### Vault Redirect in _transfer/_mint/_burn
All three core functions have special vault handling:
- _transfer to VAULT: decreases totalSupply, increases vaultAllowance (acts as burn + escrow)
- _mint to VAULT: only increases vaultAllowance (no circulating supply change)
- _burn from VAULT: only decreases vaultAllowance (no circulating supply change)
Verify the supply invariant: totalSupply + vaultAllowance = supplyIncUncirculated holds across all paths.

### Auto-Rebuy Carry Extraction via RNG Lock Bypass
- setCoinflipAutoRebuy correctly reverts when rngLocked() is true
- But: does processCoinflipPayouts (called by game during advanceGame WHILE rng is locked) update carry in a way that could be extracted?
- processCoinflipPayouts calls _claimCoinflipsInternal(sDGNRS, false) at the end -- is sDGNRS carry correctly handled?

### Bounty Manipulation via RNG Knowledge
- _addDailyFlip checks !game.rngLocked() before allowing bounty arming
- But: processCoinflipPayouts itself can arm bounty via _addDailyFlip(to, slice, 0, false, false) -- the canArmBounty=false parameter prevents this
- Verify all call sites of _addDailyFlip correctly set the bounty flags

### uint128 Truncation in PlayerCoinflipState
- claimableStored, autoRebuyStop, autoRebuyCarry are uint128
- Verify no scenario where accumulated claimable exceeds uint128 range and silently truncates

### Coinflip Day Claim Window Expiry
- Non-auto-rebuy players have a 90-day claim window (30 days for first claim)
- After window expires, unclaimed winnings are forfeit
- Verify this cannot be gamed: can a player intentionally delay claiming to manipulate BAF credit timing?

</specifics>

<deferred>
## Deferred Ideas

- **Phase 116 coordination:** DegenerusQuests module internals are called extensively from BurnieCoin quest hub functions. Phase 116 (Affiliate + Quests + Jackpots) should verify quest module correctness.
- **Phase 113 coordination:** sDGNRS calls BurnieCoinflip.claimCoinflipsForRedemption -- Phase 113 should verify the redemption flow end-to-end.
- **Phase 114 coordination:** DegenerusVault calls BurnieCoin.vaultMintTo and vaultEscrow -- Phase 114 should verify vault share calculations use correct supply values.
- **Phase 118:** Full cross-module state coherence verification is deferred to the integration sweep.

</deferred>

---

*Phase: 112-burnie-token-coinflip*
*Context gathered: 2026-03-25*
