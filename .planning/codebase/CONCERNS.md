# Codebase Concerns

**Analysis Date:** 2025-02-28

## Tech Debt

**Delegatecall Module Complexity:**
- Issue: Game logic is split across 10 delegatecall modules (DegenerusGameMintModule, DegenerusGameAdvanceModule, DegenerusGameLootboxModule, DegenerusGameWhaleModule, DegenerusGameJackpotModule, DegenerusGameDecimatorModule, DegenerusGameEndgameModule, DegenerusGameGameOverModule, DegenerusGameBoonModule, DegenerusGameDegeneretteModule). Storage is centralized in DegenerusGameStorage but logic is distributed.
- Files: `contracts/DegenerusGame.sol`, `contracts/storage/DegenerusGameStorage.sol`, `contracts/modules/*.sol`
- Impact: Testing requires understanding module interdependencies and storage layout. Debugging delegatecall failures requires inspecting module source due to error resolution. State mutations across modules are implicit.
- Fix approach: Consider documenting delegatecall contract invariants explicitly. Add module-level docstrings showing what state each module reads/writes.

**Compile-Time Address Patching:**
- Issue: All contract addresses in ContractAddresses.sol are zeroed in source; the deploy pipeline generates a concrete version by patching the file before compilation. This means the production contract differs from source on-disk.
- Files: `contracts/ContractAddresses.sol`, `scripts/lib/patchContractAddresses.js`, `scripts/lib/predictAddresses.js`
- Impact: Verification tools (block explorers, security audits) receive the patched version, not the source. The gap between what's in git and what's deployed could cause confusion.
- Fix approach: Document the patching process in README. Consider storing both the template (source) and concrete (patched) versions post-deployment for audit trails.

**VRF Coordinator Mutation:**
- Issue: `DegenerusAdmin.updateVrfCoordinatorAndSub()` allows emergency replacement of the VRF coordinator address and subscription ID (stored in DegenerusGame state). This is necessary for recovery from VRF failures but creates a critical trust point.
- Files: `contracts/DegenerusAdmin.sol`, `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`
- Impact: Admin can redirect randomness requests to a malicious coordinator during recovery. The `rngStalledForThreeDays()` guard limits when this can happen, but an admin compromise during a genuine stall is exploitable.
- Fix approach: Consider multi-signature requirement or timelock for VRF coordinator updates. Document the recovery procedure clearly for auditors.

## Known Issues

**Chainlink VRF V2.5 Sepolia Unreliability:**
- Symptoms: VRF fulfillment requests on Sepolia have low success rates (very low fulfillment rate as of Feb 2025). Mock coordinator used for testnet deployment works reliably.
- Files: `scripts/deploy-sepolia-testnet.js`, `scripts/testnet/run-sepolia.js`
- Trigger: Any call to advanceGame() during RNG request phase on Sepolia testnet may timeout waiting for fulfillment.
- Workaround: Testnet uses MockVRFCoordinator instead of real Chainlink (see lines 19-22 of deploy-sepolia-testnet.js). Mainnet will use real Chainlink V2.5 (0x271682DEB8C4E0901D1a1550aD2e64D568E69909).
- Current state: Expected behavior for testnet. Not a concern for mainnet where Chainlink is reliable.

**Deploy Order Fragility:**
- Symptoms: Deployment fails at ADMIN contract if dependencies are out of order or addresses are not correctly predicted.
- Files: `scripts/lib/predictAddresses.js` (DEPLOY_ORDER array), `scripts/deploy-sepolia-testnet.js`
- Trigger: Manual deploy or nonce miscalculation causing address predictions to diverge from actual CREATE addresses.
- Current: Deploy script is careful and tested. Documented in DEPLOY_ORDER comments (lines 6-14 of predictAddresses.js). Constraints: COIN before VAULT, GAME+modules before DGNRS, GAME before ADMIN.
- Safe modification: Always use the automated deploy script. Do not manually deploy contracts out of order.

**Local Hardhat VRF Mocking Breaks at ADMIN:**
- Symptoms: Full deploy passes through GAME contract (N+13) but fails at ADMIN (N+21) when calling wireVrf() because VRF coordinator is an EOA locally (not a real contract).
- Files: `test/helpers/deployFixture.js`, `contracts/DegenerusAdmin.sol` (line 325+)
- Trigger: Running full protocol deployment on local Hardhat without Mock VRF setup.
- Workaround: deployFixture.js handles this with MockVRFCoordinator for local tests. Documented in memory.
- Impact: None - this is expected behavior for local testing. Mainnet uses real Chainlink.

## Security Considerations

**RNG Lock During VRF Callback Window:**
- Risk: When advanceGame() issues a VRF request, rngLockedFlag is set to true. Certain operations (opening lootboxes, Degenerette bets, coinflip deposits) revert with RngLocked if called during this window. A player cannot dispute what happened during a locked window.
- Files: `contracts/modules/DegenerusGameAdvanceModule.sol` (rngLockedFlag state), `contracts/modules/DegenerusGameLootboxModule.sol` (lines 545, 622), `contracts/interfaces/IBurnieCoinflip.sol` (RngLocked errors)
- Current mitigation: RNG is locked for at most ~18 hours (VRF_RETRY_TIMEOUT), after which a new request is issued. The lock prevents state mutations during VRF callback execution.
- Recommendations: Document the RNG lock period in player-facing docs. Consider reducing lock window if possible (currently tied to VRF reliability).

**Delegatecall Attack Surface:**
- Risk: All delegatecall modules must trust DegenerusGame's storage layout. A module that writes to the wrong storage slot could corrupt game state silently.
- Files: All `contracts/modules/*.sol` files (10 modules), `contracts/storage/DegenerusGameStorage.sol`
- Current mitigation: All modules inherit from DegenerusGameStorage and use defined state variables. No low-level storage manipulation. Modules are immutable post-deployment (defined in ContractAddresses.sol).
- Recommendations: In future upgrades, add storage slot layout tests to prevent accidental misalignment.

**Vault Mint Allowance Underflow Risk:**
- Risk: `DegenerusVault.vaultMintAllowance()` represents a virtual reserve (initialized to 2M BURNIE). Players can "buy" BURNIE from this allowance. If consumption exceeds the allowance, new player mints could fail.
- Files: `contracts/DegenerusVault.sol` (lines 350-360), `contracts/modules/DegenerusGameMintModule.sol` (coinMintFromVault call)
- Current mitigation: The allowance is "virtual" — no actual token is held. When a player uses vault allowance, the contract mints new BURNIE to that player. The allowance decreases but no token leaves the vault.
- Recommendations: Monitor vault allowance consumption post-launch. If consumption accelerates beyond projections, the CREATOR can inject additional ETH to increase the allowance via vaultMintAllowance tracking.

**stETH Yield Dependency:**
- Risk: Prize pools are funded entirely from stETH yield. If Lido staking yield drops below 1% APY or stETH enters a price spiral, prize pools grow too slowly to satisfy payout expectations.
- Files: `contracts/DegenerusGame.sol` (prize pool accumulation logic), `contracts/interfaces/IStETH.sol`
- Current mitigation: Economic analysis (ECONOMIC_ANALYSIS.md) assumes 3-5% stETH yield. Protocol is solvent as long as yield > 0. The 50 ETH BOOTSTRAP_PRIZE_POOL ensures minimum starting prizes.
- Recommendations: Monitor stETH yield monthly. Consider dynamic prize pool rebalancing if yield dips below 2%.

## Performance Bottlenecks

**Large Contract Sizes Near Compilation Limits:**
- Problem: DegenerusGame (19KB), DegenerusGameJackpotModule (2.7KB), DegenerusGameLootboxModule (1.7KB), BurnieCoinflip (1.2KB) are all substantial contracts. All are under the 24KB limit, but bytecode is approaching optimization limits.
- Files: All main contracts listed above
- Cause: Comprehensive game logic (10+ module functions) in a single contract or module. No unused functions that can be removed.
- Improvement path: Future version could split lottery/jackpot logic into a separate proxy. For now, contracts compile successfully with viaIR optimizer enabled.

**Ticket Processing in Batches:**
- Problem: advanceGame() processes tickets in batches via _runProcessTicketBatch() and _processFutureTicketBatch(). If a level accumulates millions of tickets, draining them across multiple advanceGame() calls could take weeks.
- Files: `contracts/modules/DegenerusGameAdvanceModule.sol` (lines 182-188, 211-215), `contracts/storage/DegenerusGameStorage.sol`
- Cause: Ticket processing is deterministic and cannot be parallelized. Each batch is processed by a single advanceGame() call.
- Improvement path: Increase batch size (currently ~BATCH_SIZE tickets per call) or allow CREATOR to force-batch drain tickets after 7 days of processing. Not currently a risk if player acquisition grows gradually.

**O(n) Affiliate Upline Traversal:**
- Problem: Recording affiliate mints via DegenerusAffiliate.recordMint() walks the upline chain (upline1 -> upline2 -> upline3). A deep referral tree (10+ levels) with high-volume mints could add gas costs per transaction.
- Files: `contracts/DegenerusAffiliate.sol`
- Cause: Affiliate structure is 3-tier (upline1, upline2, upline3) by design, so max depth is 3. Not actually O(n) — it's O(1) with max 3 iterations.
- Impact: None — this is not a bottleneck.

## Fragile Areas

**Phase Transition State Machine:**
- Files: `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol` (phase transition logic), `contracts/storage/DegenerusGameStorage.sol` (phaseTransitionActive state)
- Why fragile: The 2-state FSM (PURCHASE <-> JACKPOT) with multiple sub-phases (TRANSITION_WORKING, TRANSITION_DONE) is managed through several state flags (jackpotPhaseFlag, phaseTransitionActive, levelJackpotPaid). A single flag mutation in the wrong order could break the phase cycle.
- Safe modification: Never modify phase transition logic without comprehensive integration tests. The GameLifecycle.test.js and VRFIntegration.test.js files should be updated for any changes.
- Test coverage: Phase transitions are covered in integration tests. Edge case: What if VRF fails during TRANSITION_WORKING? Covered by RngStall.test.js and recovery logic.

**Decimator Bucket Assignment:**
- Files: `contracts/modules/DegenerusGameDecimatorModule.sol`
- Why fragile: Bucket assignment is deterministic from `keccak256(player, level, bucket)`. If the hash algorithm is changed or the level counter diverges, bucket assignments become non-deterministic and prize distributions break.
- Safe modification: Do not change the decimator bucket assignment formula. If a bug is found, consider adding a migration layer rather than changing the core formula.
- Test coverage: Decimator bucket assignment has edge case tests. Edge case: what if two players have identical (player, level, bucket) hash? Probability is 1 in 2^256; not a concern.

**Lootbox EV Scoring Curves:**
- Files: `contracts/libraries/PriceLookupLib.sol`, `contracts/modules/DegenerusGameLootboxModule.sol` (EV calculation), `contracts/modules/DegenerusGameDegeneretteModule.sol` (activity score multiplier)
- Why fragile: Lootbox EV ranges 80% - 135% based on activity score. The activity score formula compounds streak bonuses, mint bonuses, and affiliate bonuses. A small change in one multiplier cascades through all EV calculations.
- Safe modification: Changes to EV scoring must be validated against the ECONOMIC_ANALYSIS.md projections. Any change risks destabilizing the +EV promise to high-activity players.
- Test coverage: Edge cases (activity score 0%, 305% max, fractional multipliers) are tested. Missing: stress test EV calculation under extreme activity scores.

**Time-Based Prize Pool Allocation (_applyTimeBasedFutureTake):**
- Files: `contracts/modules/DegenerusGameAdvanceModule.sol` (around line 221)
- Why fragile: A time-based "take" from futurePrizePool to nextPrizePool depends on days elapsed since last allocation. If the block.timestamp jumps (block time manipulation, rare but theoretically possible) or dayIndex calculation diverges, allocations could be skipped or doubled.
- Safe modification: Validate block.timestamp consistency across all time-based operations. dayIndex = (timestamp - JACKPOT_RESET_TIME) / 86400 must be consistent.
- Test coverage: Time advancement is tested in GameLifecycle.test.js. Missing: test for block.timestamp reorg scenarios.

## Scaling Limits

**Staking Yield on Locked ETH:**
- Current capacity: Total stETH accrued is unbounded (contract has no deposit cap). As TVL grows to 1000 ETH, 10,000 ETH, etc., stETH yield scales linearly (e.g., at 5% APY, 1000 ETH generates 50 ETH/year in yield).
- Limit: Solidity contract can hold arbitrary stETH amounts (ERC20 balance is uint256). No technical limit until 2^256 wei.
- Scaling path: Monitor TVL growth monthly. At extreme scales (e.g., 100,000+ ETH), consider deploying secondary vault contracts or splitting liquidity across multiple staking providers.

**BURNIE Token Supply:**
- Current capacity: BURNIE supply is minted on-demand from ETH ticket purchases and quest rewards. Total supply can grow unbounded.
- Limit: BURNIE max supply is uint256 (no cap in the contract). Token is deflationary (coinflip burns ~1.6% of stakes) but synthetic mints (quests, bounties, recycling bonuses) are inflationary.
- Scaling path: Monitor BURNIE supply:burn ratio monthly. If inflation exceeds 10% of ticket burn rate, consider increasing burn mechanisms or reducing synthetic mint rates.

**Daily Jackpot Claimant Count:**
- Current capacity: Daily jackpot is claimed in a single transaction via payDailyJackpot(). If more than ~50-100 eligible players per level, the transaction might exceed gas limits when distributing payouts.
- Limit: Each payout adds ~5,000 gas (storage write + event). At 30M gas block limit, max ~6,000 payouts per transaction. Typically <100 claimants per level.
- Scaling path: If daily jackpot claimant count exceeds 500, implement a multi-step distribution (batch claims over 2-3 advanceGame() calls).

**Deity Pass Concentration:**
- Current capacity: Deity passes are capped at 32 total (hardcoded). Early passes cost less (24 ETH base), late passes cost more (24 + T(n) where n is pass number).
- Limit: At pass #32, cost is 24 + (32*33/2) = 24 + 528 = 552 ETH. All 32 passes will eventually sell if the game succeeds.
- Scaling path: Once all 32 passes are sold, the system is "maxed out." If player demand still exceeds supply, consider a governance vote to increase the cap (hard fork or replacement contract).

## Dependencies at Risk

**Lido stETH Smart Contract Risk:**
- Risk: If Lido staking contract is upgraded with a breaking change (e.g., changes to balanceOf() or approve() semantics), DegenerusVault and DegenerusGame ETH accounting could break.
- Impact: Prize pools denominated in stETH would become unsellable or misdirected.
- Migration plan: Monitor Lido governance announcements. Keep a mirror backup of stETH interface (IStETH) locally to catch API changes. In the event of a breaking change, deploy a migration contract to swap stETH for wrapped ETH or another staking provider (e.g., Rocket Pool rETH).

**Chainlink VRF V2.5:**
- Risk: Chainlink VRF V2.5 is the sole source of randomness. A critical bug in Chainlink's coordinator could enable predictable random words, breaking game fairness.
- Impact: A predictable random source breaks Degenerette jackpot (100,000x) and all phase transitions. Attackers could predict lootbox contents before opening.
- Migration plan: If VRF becomes unreliable, activate emergency recovery via DegenerusAdmin.updateVrfCoordinatorAndSub() to point to an alternative RNG provider (e.g., drand, API3, or a decentralized oracle network). This requires admin action and is documented in DegenerusAdmin.sol.

**OpenZeppelin / Hardhat Dependencies:**
- Risk: Hardhat and OpenZeppelin are widely used but rely on third-party packages (ethers.js, chai, etc.). A supply chain attack on any dependency could compromise the build/test pipeline.
- Impact: Compromised test infrastructure could hide vulnerabilities before mainnet deployment.
- Migration plan: Use lockfile (package-lock.json exists) and regularly audit dependencies with `npm audit`. Before mainnet deployment, audit all transitive dependencies.

## Missing Critical Features

**Admin Key Rotation:**
- Problem: The CREATOR address (ContractAddresses.CREATOR) is immutable post-deployment. If the private key is compromised, there is no way to revoke admin access.
- Blocks: Rotation of admin credentials, emergency pause mechanisms.
- Recommendation: For mainnet, use a multisig wallet (e.g., Gnosis Safe) as the CREATOR address instead of an EOA. This provides key recovery and rotation capability.

**Pause Mechanism:**
- Problem: There is no global pause/unpause function. If a critical bug is discovered post-launch, the only option is to let the game progress until it hits a natural stopping point or game-over.
- Blocks: Emergency response to security vulnerabilities.
- Recommendation: Consider adding a paused state to DegenerusGame that blocks new mints/bets but allows winners to claim existing prizes. This would require careful test coverage (all state-changing functions check the pause flag).

**Upgrade Mechanism:**
- Problem: All contracts are immutable. If a bug is discovered in a module, the only fix is to redeploy and migrate all state (expensive and risky).
- Blocks: Bug fixes, balance adjustments, feature additions.
- Recommendation: For future versions, consider a minimal proxy pattern for DegenerusGame to allow storage layout upgrades while keeping the game contract address constant. This trades immutability for flexibility.

## Test Coverage Gaps

**Extreme Activity Score Edge Cases:**
- What's not tested: Behavior at activity scores outside the tested range (0%, 305%+, or with extreme affiliate chain depth).
- Files: `contracts/modules/DegenerusGameDegeneretteModule.sol` (activity score calculation), test files missing extreme-case suites.
- Risk: A bug in activity score clamping could cause overflow or unexpected EV multipliers at extreme values.
- Priority: High — activity score is the primary EV lever for players.

**Lootbox EV Multiplier Under Pool Starvation:**
- What's not tested: Behavior when currentPrizePool or nextPrizePool are depleted (e.g., after massive jackpot hit or long player drought).
- Files: `contracts/modules/DegenerusGameLootboxModule.sol` (EV scoring), integration tests.
- Risk: If a pool is empty, lootbox tickets may resolve to zero ETH despite EV % multiplier being high.
- Priority: Medium — depends on prize pool dynamics post-launch.

**VRF Fulfillment Stale Request Scenario:**
- What's not tested: Receiving a VRF fulfillment for a request that was superseded by a retry (old requestId with new requestId active).
- Files: `contracts/modules/DegenerusGameAdvanceModule.sol` (VRF fulfillment handling).
- Risk: If a stale fulfillment is processed as current, game state could diverge (e.g., wrong level advancement).
- Priority: Medium — rare but catastrophic if it occurs.

**Bankruptcy Recovery After Game-Over:**
- What's not tested: Claiming prizes, refunds, and vault sweeps after gameOver=true is set.
- Files: `contracts/modules/DegenerusGameGameOverModule.sol`, `contracts/DegenerusGame.sol` (claimWinnings, claimableWinningsOf).
- Risk: Game-over logic may have edge cases where some players cannot fully claim their entitled winnings.
- Priority: Medium — affects final payout fairness.

---

*Concerns audit: 2025-02-28*
