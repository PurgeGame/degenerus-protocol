# Phase 113: sDGNRS + DGNRS - Context

**Gathered:** 2026-03-25 (auto mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of StakedDegenerusStonk.sol (sDGNRS) and DegenerusStonk.sol (DGNRS) -- the soulbound token with reserves and its transferable ERC20 wrapper. This phase examines every state-changing function in both contracts using the three-agent system (Taskmaster -> Mad Genius -> Skeptic). The contracts handle:

**StakedDegenerusStonk (sDGNRS) -- 839 lines:**
- Soulbound token backed by ETH, stETH, and BURNIE reserves
- Pre-minted supply: 1T tokens split into 20% creator (to DGNRS wrapper) + 5 reward pools
- Pool spending: game distributes sDGNRS from pools to players (Whale/Affiliate/Lootbox/Reward/Earlybird)
- Pool rebalancing: game moves tokens between pools
- Deterministic burn: post-gameOver proportional ETH + stETH payout
- Gambling burn redemption system: submit -> resolve -> claim cycle with RNG roll (25%-175%)
  - Submit: burns sDGNRS, segregates proportional ETH/BURNIE value, records pending claim
  - Resolve: game resolves period with dice roll, adjusts segregated ETH, returns BURNIE amount for coinflip
  - Claim: player claims rolled ETH (50/50 direct + lootbox) and BURNIE (via coinflip win/loss)
- 50% supply cap per period, 160 ETH daily EV cap per wallet
- Wrapper functions: DGNRS contract moves sDGNRS between addresses
- Deposits: game sends ETH and stETH to reserve
- Player actions: proxy game advance and whale pass claim
- BURNIE payout drawn from balance + coinflip claimables
- ETH payout with stETH fallback when ETH insufficient

**DegenerusStonk (DGNRS) -- 251 lines:**
- Transferable ERC20 wrapper around sDGNRS
- Constructor mints totalSupply = sDGNRS.balanceOf(DGNRS) to CREATOR
- Standard transfer/transferFrom/approve
- Creator-only unwrap: burns DGNRS, moves sDGNRS to recipient (VRF stall guard: blocked if >5h since lastVrfProcessed)
- Public burn: post-gameOver only, burns DGNRS then calls sDGNRS.burn() for proportional ETH + stETH + BURNIE
- burnForSdgnrs: sDGNRS-only callable, burns DGNRS from player for wrapped gambling burns
- receive(): accepts ETH only from sDGNRS during burn-through

This phase does NOT re-audit internals of the game contract, coinflip contract, or any module called via delegatecall. Cross-contract calls are traced far enough to verify state coherence in the calling context.

**SPECIAL INVESTIGATION AREAS:**
1. Gambling burn redemption system: the submit/resolve/claim pipeline with RNG roll, segregation accounting, and multi-asset payout
2. VRF governance guard on unwrapTo (prevents vote-stacking during VRF stall)
3. Cross-contract interaction: sDGNRS <-> DGNRS mutual calls (burn, burnWrapped, burnForSdgnrs, wrapperTransferTo)
4. Pending redemption accounting: ETH segregation (pendingRedemptionEthValue), BURNIE reservation (pendingRedemptionBurnie), period tracking

</domain>

<decisions>
## Implementation Decisions

### Function Categorization
- **D-01:** Use Categories B/C/D only -- no Category A. These are standalone contracts, not delegatecall modules. External/public state-changing functions -> Category B. Internal/private state-changing helpers -> Category C. View/pure functions -> Category D.
- **D-02:** Category B functions get full Mad Genius treatment: recursive call tree with line numbers, storage-write map, cached-local-vs-storage check, 10-angle attack analysis.
- **D-03:** Category C functions are traced as part of their parent's call tree. They get standalone attack sections when called from multiple parents with different cached-local states (MULTI-PARENT pattern).

### Two-Contract Scope
- **D-04:** Both StakedDegenerusStonk.sol and DegenerusStonk.sol are audited as a single unit. The contracts are tightly coupled (mutual calls, shared accounting).
- **D-05:** Cross-contract calls between sDGNRS and DGNRS are fully traced -- these are within scope. Calls to external contracts (Game, Coinflip, stETH) are traced far enough to verify state coherence.

### Gambling Burn Priority
- **D-06:** The gambling burn redemption pipeline (submit -> resolve -> claim) is the PRIORITY investigation area. The multi-step flow with segregated accounting, RNG resolution, partial claims, and multi-asset payouts is the highest-risk subsystem.
- **D-07:** Particular attention to: uint96 truncation in ethValueOwed/burnieOwed, period index transitions, stacking behavior, 50% supply cap enforcement, 160 ETH EV cap enforcement, and the partial claim (ETH claimed, BURNIE pending) state.

### Fresh Analysis
- **D-08:** Fresh adversarial analysis on ALL functions -- do not reference or trust prior findings from v1.0-v4.4. Prior audit results are not input to this phase.
- **D-09:** VRF stall guard on unwrapTo() gets full scrutiny -- verify the 5-hour window cannot be gamed.

### Cross-Module Call Boundary
- **D-10:** When sDGNRS calls game.claimWinnings(), game.resolveRedemptionLootbox(), coinflip.claimCoinflipsForRedemption(), etc., trace far enough to verify state coherence. Full internals of those contracts are in their own unit phases.
- **D-11:** If a subordinate call writes to storage that sDGNRS/DGNRS has cached locally, that IS a finding regardless of which contract the subordinate lives in.

### Report Format
- **D-12:** Follow ULTIMATE-AUDIT-DESIGN.md format: per-function sections with Call Tree, Storage Writes (Full Tree), Cached-Local-vs-Storage Check, Attack Analysis with verdicts.

### Claude's Discretion
- Ordering of function analysis within the report (suggest risk-tier ordering)
- Level of detail in cross-contract subordinate call traces (enough to verify state coherence, no more)
- Whether to split long sections for readability

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Audit Design
- `.planning/ULTIMATE-AUDIT-DESIGN.md` -- Three-agent system design (Mad Genius / Skeptic / Taskmaster), attack angles, anti-shortcuts doctrine, output format

### Target Contracts
- `contracts/StakedDegenerusStonk.sol` -- sDGNRS: soulbound token with reserves and gambling burn (839 lines)
- `contracts/DegenerusStonk.sol` -- DGNRS: transferable ERC20 wrapper (251 lines)

### Contract Addresses
- `contracts/ContractAddresses.sol` -- Deployment addresses for all protocol contracts

### Interface Dependencies
- `contracts/interfaces/IStETH.sol` -- stETH interface used by both contracts

### Prior Phase Outputs (methodology reference only -- do NOT trust findings)
- `.planning/phases/111-lootbox-boons/111-CONTEXT.md` -- Recent phase context (pattern reference)
- `audit/unit-09/COVERAGE-CHECKLIST.md` -- Recent Taskmaster output (format reference)
- `audit/unit-09/ATTACK-REPORT.md` -- Recent Mad Genius output (format reference)

### Prior Audit Context (known issues -- do not re-report)
- `audit/KNOWN-ISSUES.md` -- Known issues from v1.0-v4.4

</canonical_refs>

<code_context>
## Existing Code Insights

### Key Functions -- StakedDegenerusStonk

**Category B (External State-Changing):**
- `burn(uint256)` (L443) -- Public burn: deterministic post-gameOver OR gambling burn during game
- `burnWrapped(uint256)` (L461) -- Burns DGNRS wrapper tokens via sDGNRS gambling/deterministic path
- `claimRedemption()` (L573) -- Claim resolved gambling burn: ETH (50/50 direct+lootbox) + BURNIE (coinflip)
- `resolveRedemptionPeriod(uint16, uint48)` (L540) -- Game resolves current period with roll
- `transferFromPool(Pool, address, uint256)` (L376) -- Game distributes sDGNRS from pool to player
- `transferBetweenPools(Pool, Pool, uint256)` (L401) -- Game rebalances between pools
- `burnRemainingPools()` (L420) -- Game burns undistributed pool tokens at game over
- `wrapperTransferTo(address, uint256)` (L310) -- DGNRS wrapper moves sDGNRS
- `depositSteth(uint256)` (L352) -- Game deposits stETH
- `receive() payable` (L343) -- Game deposits ETH
- `gameAdvance()` (L327) -- Proxy game advance
- `gameClaimWhalePass()` (L332) -- Proxy whale pass claim

**Category C (Internal State-Changing):**
- `_deterministicBurnFrom(address, address, uint256)` (L481) -- Core deterministic burn + payout
- `_submitGamblingClaimFrom(address, address, uint256)` (L707) -- Core gambling claim submission
- `_payEth(address, uint256)` (L772) -- ETH payout with stETH fallback
- `_payBurnie(address, uint256)` (L797) -- BURNIE payout from balance + coinflip
- `_mint(address, uint256)` (L829) -- Internal mint (constructor only)

**Category D (View/Pure):**
- `previewBurn(uint256)` (L653) -- Preview burn outputs
- `hasPendingRedemptions()` (L531) -- Check for unresolved redemptions
- `burnieReserve()` (L688) -- BURNIE backing available
- `poolBalance(Pool)` (L364) -- Pool remaining balance
- `_claimableWinnings()` (L812) -- Claimable game winnings
- `_poolIndex(Pool)` (L821) -- Pool enum to array index

### Key Functions -- DegenerusStonk

**Category B (External State-Changing):**
- `transfer(address, uint256)` (L112) -- Standard ERC20 transfer
- `transferFrom(address, address, uint256)` (L125) -- Standard ERC20 transferFrom
- `approve(address, uint256)` (L140) -- Standard ERC20 approve
- `unwrapTo(address, uint256)` (L152) -- Creator unwraps DGNRS to sDGNRS (VRF stall guard)
- `burn(uint256)` (L171) -- Public burn post-gameOver: burns DGNRS, claims ETH+stETH+BURNIE
- `burnForSdgnrs(address, uint256)` (L241) -- sDGNRS burns DGNRS for wrapped gambling path
- `receive() payable` (L97) -- Accept ETH from sDGNRS during burn-through

**Category C (Internal State-Changing):**
- `_transfer(address, address, uint256)` (L209) -- Internal transfer logic
- `_burn(address, uint256)` (L222) -- Internal burn logic

**Category D (View/Pure):**
- `previewBurn(uint256)` (L201) -- Delegates to sDGNRS.previewBurn

### Integration Points
- sDGNRS.burn() calls game.gameOver(), game.rngLocked()
- sDGNRS.burnWrapped() calls dgnrsWrapper.burnForSdgnrs()
- sDGNRS._deterministicBurnFrom() calls game.claimWinnings()
- sDGNRS._submitGamblingClaimFrom() calls game.currentDayView(), game.playerActivityScore()
- sDGNRS.claimRedemption() calls coinflip.getCoinflipDayResult(), game.rngWordForDay(), game.resolveRedemptionLootbox()
- sDGNRS._payEth() calls game.claimWinnings()
- sDGNRS._payBurnie() calls coinflip.claimCoinflipsForRedemption()
- DGNRS.burn() calls game.gameOver(), stonk.burn()
- DGNRS.unwrapTo() calls game.lastVrfProcessed(), stonk.wrapperTransferTo()

</code_context>

<specifics>
## Specific Ideas

### Priority Investigation: Gambling Burn Accounting
The gambling burn system is the most complex subsystem. Key areas:
1. **uint96 truncation**: ethValueOwed and burnieOwed are stored as uint96 in PendingRedemption. Verify the 160 ETH cap and realistic BURNIE max prevent overflow.
2. **Period transition race**: What happens if a player submits a claim, the period resolves, and then they submit again before claiming? The UnresolvedClaim check (L751-753) should prevent this.
3. **Partial claim state**: When coinflip is unresolved, ETH is paid but BURNIE portion kept. Can this lead to accounting inconsistency?
4. **50% supply cap**: Takes snapshot on first burn of new period. Can this be manipulated?
5. **pendingRedemptionEthValue accounting**: Segregation is added at submit, adjusted at resolve, released at claim. Do the increments and decrements balance exactly?

### Priority Investigation: Cross-Contract Burns
- DGNRS.burn() calls sDGNRS.burn() which may call game.claimWinnings(). Trace the full call chain.
- DGNRS.burnForSdgnrs() is called by sDGNRS.burnWrapped(). Verify no reentrancy or state desync.
- DGNRS.unwrapTo() calls sDGNRS.wrapperTransferTo(). Verify VRF stall guard cannot be bypassed.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 119 coordination**: Cross-contract integration sweep will verify ETH conservation across sDGNRS + DGNRS + Game + Vault
- **Phase 112 dependency**: BurnieCoinflip audit (Unit 10) covers coinflip.claimCoinflipsForRedemption() and coinflip.getCoinflipDayResult() internals

</deferred>

---

*Phase: 113-sdgnrs-dgnrs*
*Context gathered: 2026-03-25*
