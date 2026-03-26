# Redundancy Audit -- Phase 125

Generated: 2026-03-26
Scope: 90 test files (44 Hardhat, 42 Foundry fuzz, 4 Halmos)

## Summary

| Verdict | Count | Files |
|---------|-------|-------|
| DELETE | 13 | 7 poc/ + 3 adversarial/ + 2 simulation/ + 1 validation/ |
| KEEP | 75 | 19 unit/ + 6 edge/ + 2 integration/ + 1 deploy/ + 1 access/ + 1 gas/ + 1 validation/ + 42 fuzz/ + 4 halmos/ (includes helpers) |
| KEEP (borderline) | 2 | EthInvariant.test.js, DGNRSLiquid.test.js |

Total DELETE: **13 files** (1,763 + 1,004 + 809 + 211 = 3,787 lines removed)

## Ghost Tests (poc/ -- excluded from runner)

The 7 poc/ files are NOT listed in `hardhat.config.js` `TEST_DIR_ORDER` (which lists: access, deploy, unit, integration, edge, validation, gas, adversarial, simulation). These files exist on disk but never run during `npx hardhat test`.

| File | Lines | Verdict | Justification |
|------|-------|---------|---------------|
| test/poc/Coercion.test.js | 238 | DELETE | Ghost test -- excluded from Hardhat runner. Access control checks covered by test/access/AccessControl.test.js (498 lines, 29 contracts). Admin swap/stake tests covered by test/unit/DegenerusGame.test.js. VRF governance gate covered by test/unit/VRFGovernance.test.js (828 lines). |
| test/poc/NationState.test.js | 204 | DELETE | Ghost test -- excluded from Hardhat runner. All 13 DEFENSE- checks are access control reversions, fully covered by test/access/AccessControl.test.js which systematically tests every external function's access guard across all 29 contracts. |
| test/poc/Phase24_FormalMethods.test.js | 190 | DELETE | Ghost test -- excluded from Hardhat runner. PriceLookupLib properties covered by test/validation/PaperParity.test.js (PAR-01, 30+ level checks) + test/fuzz/PriceLookupInvariants.t.sol (100 lines, fuzz). BPS split covered by PaperParity PAR-03. ETH solvency covered by test/unit/EthInvariant.test.js + test/fuzz/invariant/EthSolvency.inv.t.sol. Sentinel pattern covered by SecurityEconHardening FIX-10. Access control covered by AccessControl.test.js. |
| test/poc/Phase25_DependencyIntegration.test.js | 359 | DELETE | Ghost test -- excluded from Hardhat runner. VRF retry (VRF-01) covered by test/edge/RngStall.test.js (723 lines) + test/fuzz/StallResilience.t.sol + VRFStallEdgeCases.t.sol. VRF governance gate (VRF-02) covered by test/unit/VRFGovernance.test.js. VRF callback validation (VRF-03) covered by test/fuzz/VRFCore.t.sol. Zero-word correction (VRF-04) covered by VRFCore.t.sol. LINK onTokenTransfer tests covered by test/unit/DegenerusAdmin.test.js. Many tests are `expect(true).to.be.true` attestations with no actual contract interaction. |
| test/poc/Phase26_GasGriefing.test.js | 262 | DELETE | Ghost test -- excluded from Hardhat runner. Whale bundle gas test (DEFENSE-01) is the only test with actual assertions -- covered more rigorously by test/gas/AdvanceGameGas.test.js (1005 lines) and test/edge/WhaleBundle.test.js (729 lines). Remaining 7 tests are `expect(true).to.be.true` attestations with zero contract interaction. |
| test/poc/Phase27_WhiteHat.test.js | 128 | DELETE | Ghost test -- excluded from Hardhat runner. ERC20 zero/self transfer tests covered by test/unit/BurnieCoin.test.js (902 lines). DeityPass ERC721 tests covered by test/unit/DegenerusDeityPass.test.js (659 lines). Operator approval covered by DegenerusGame.test.js. claimWinnings revert covered by EthInvariant.test.js and SecurityEconHardening.test.js FIX-10. WWXRP mintPrize guard covered by WrappedWrappedXRP.test.js. |
| test/poc/Phase28_GameTheory.test.js | 382 | DELETE | Ghost test -- excluded from Hardhat runner. Solvency invariant covered by test/unit/EthInvariant.test.js + test/fuzz/invariant/EthSolvency.inv.t.sol (1000 run fuzz). Prize pool split covered by PaperParity.test.js PAR-03. GAMEOVER conditions (912 days) covered by SecurityEconHardening.test.js FIX-08 + test/edge/GameOver.test.js. Price escalation covered by PaperParity PAR-01 + PriceLookupInvariants.t.sol. Deity pass T(n) pricing covered by PaperParity PAR-12. |

## Cross-Suite Duplicates

For each Hardhat file that has a Foundry fuzz/invariant equivalent testing the same behaviors across many more inputs:

| Hardhat File | Foundry Equivalent | Verdict | Justification |
|---|---|---|---|
| test/unit/EthInvariant.test.js (240 lines) | test/fuzz/invariant/EthSolvency.inv.t.sol (92 lines, 256 runs/depth 128) | KEEP (borderline) | EthInvariant tests 7 specific lifecycle states (deploy, purchase, advanceGame, VRF, claim, stake, gameOver). EthSolvency.inv.t.sol fuzz-tests the same solvency invariant across random sequences. The Hardhat file's named scenarios are useful for human debugging, but the invariant version is strictly more thorough. Keeping because each test tells a different story and maintaining both is low-cost. |
| test/unit/DGNRSLiquid.test.js (487 lines) | test/fuzz/ShareMathInvariants.t.sol (142 lines, 1000 runs) | KEEP (borderline) | DGNRSLiquid tests wrap/unwrap, transfer, soulbound enforcement. ShareMathInvariants fuzz-tests share math conservation. The Hardhat version covers behavioral correctness (transfer events, approval, ownership) that the fuzz test does not. Keeping both. |
| test/unit/DegenerusVault.test.js (561 lines) | test/fuzz/invariant/VaultShare.inv.t.sol (73 lines) + VaultShareMath.inv.t.sol (107 lines) | KEEP | Hardhat covers full vault lifecycle (deposit, withdrawal, share calculation, edge cases). Foundry covers share math invariants. Complementary -- different dimensions. |
| test/edge/RngStall.test.js (723 lines) | test/fuzz/StallResilience.t.sol (215 lines) + VRFStallEdgeCases.t.sol (684 lines) | KEEP | RngStall.test.js tests named stall scenarios with exact timing assertions. Foundry tests fuzz timing parameters. Complementary. |
| test/edge/WhaleBundle.test.js (729 lines) | test/fuzz/invariant/WhaleSybil.inv.t.sol (91 lines) | KEEP | WhaleBundle covers pricing, quantity limits, access control, gameOver blocking. WhaleSybil invariant fuzz-tests sybil resistance. Different dimensions. |
| test/edge/CompressedJackpot.test.js (566 lines) | test/fuzz/JackpotCombinedPool.t.sol (311 lines) | KEEP | CompressedJackpot tests compression tier transitions and compressed jackpot behavior. JackpotCombinedPool tests combined ticket pool selection. Different focus areas. |
| test/integration/VRFIntegration.test.js (429 lines) | test/fuzz/VRFCore.t.sol (616 lines) + VRFLifecycle.t.sol (158 lines) + VRFPathCoverage.t.sol (359 lines) | KEEP | VRFIntegration covers end-to-end VRF lifecycle through the actual Game contract. Foundry tests focus on individual VRF paths and coverage. The integration test exercises the full purchase->advance->VRF->jackpot flow that Foundry unit tests don't assemble. |

**Result:** No cross-suite DELETE verdicts. The Hardhat tests and Foundry fuzz tests are complementary -- Hardhat covers named scenarios with exact assertions while Foundry covers random input spaces. Both are worth keeping.

## Within-Suite Overlaps

### adversarial/ vs unit/

| File | Overlaps With | Verdict | Justification |
|---|---|---|---|
| test/adversarial/EconomicAdversarial.test.js (302 lines) | test/unit/AffiliateHardening.test.js + test/unit/BurnieCoinflip.test.js + test/edge/CompressedAffiliateBonus.test.js | DELETE | **4 tests total.** (1) `caps non-deity recycling extraction at 1000 BURNIE` -- this exact scenario is tested in BurnieCoinflip.test.js which tests coinflip stake caps more thoroughly across many edge cases. (2) `enforces Degenerette ETH payout cap at 10%` -- DegeneretteBet.inv.t.sol (Foundry invariant, 94 lines, 256 runs) fuzz-tests the payout cap across random inputs. (3) `locks self-referral to vault fallback` -- AffiliateHardening.test.js tests self-referral blocking with 25 test cases across caps, tiers, and reset. (4) `deity affiliate claim flip bonus as 20% of score` -- AffiliateDgnrsClaim.t.sol (404 lines) fuzz-tests the claim path. All 4 scenarios are covered more thoroughly by dedicated unit/fuzz tests. |
| test/adversarial/SepoliaActorAdversarial.test.js (498 lines) | None (unique: requires Sepolia fork + events DB) | DELETE | **Requires external infrastructure.** Gated by `RUN_SEPOLIA_ACTOR_TESTS=1` env var, needs Sepolia RPC fork URL, events database (SQLite), or Etherscan API key. Never runs in CI or standard `npx hardhat test`. Tests are behavioral replays of real Sepolia actors -- but the same attack surfaces (privileged pathway blocking, operator approval, recycling cap) are already tested by AccessControl.test.js, BurnieCoinflip.test.js, and DegenerusGame.test.js using deterministic local Hardhat fixtures. The Sepolia-specific infrastructure dependency makes this unmaintainable. |
| test/adversarial/TechnicalAdversarial.test.js (204 lines) | test/edge/RngStall.test.js + test/unit/VRFGovernance.test.js + test/unit/BurnieCoinflip.test.js | DELETE | **4 tests total.** (1) `blocks requestLootboxRng during 15-minute pre-reset window` -- tested in RngStall.test.js (723 lines) with named stall scenarios. (2) `midday lootbox RNG griefing retries after 18h` -- tested by RngStall.test.js + StallResilience.t.sol. (3) `gates VRF governance propose behind stall detection` -- tested by VRFGovernance.test.js (828 lines, 16 governance tests including propose gating). (4) `reverseFlip cost escalates` -- tested by DegenerusGame.test.js and AdvanceGameRewrite.t.sol. All scenarios are covered by dedicated test files with more thorough coverage. |

### simulation/ vs integration/

| File | Overlaps With | Verdict | Justification |
|---|---|---|---|
| test/simulation/simulation-2-levels.test.js (436 lines) | test/integration/GameLifecycle.test.js (593 lines) + test/fuzz/invariant/MultiLevel.inv.t.sol (104 lines) | DELETE | **1 test case** that runs a multi-level game simulation with 20 players across 2 levels. GameLifecycle.test.js covers the same multi-level progression with explicit state assertions at each transition. MultiLevel.inv.t.sol fuzz-tests multi-level invariants across random sequences with 256 runs/128 depth. The simulation primarily generates console.log output for human inspection -- it has no meaningful `expect()` assertions beyond the basic loop structure. The GameLifecycle integration test and Foundry invariant test both exercise the same progression with stronger coverage guarantees. |
| test/simulation/simulation-5-levels.test.js (373 lines) | test/integration/GameLifecycle.test.js (593 lines) + test/fuzz/invariant/MultiLevel.inv.t.sol (104 lines) | DELETE | Same reasoning as simulation-2-levels. **1 test case** running 5 levels with the same PlayerManager/StatsTracker infrastructure. Generates console output only. No meaningful `expect()` assertions. The 5-level variant adds no unique coverage beyond what the 2-level version already provides -- it just runs longer. Both GameLifecycle.test.js and MultiLevel.inv.t.sol cover multi-level progression more rigorously. |

### validation/ content

| File | Overlaps With | Verdict | Justification |
|---|---|---|---|
| test/validation/PaperParity.test.js (1102 lines) | None (unique) | KEEP | **Unique and high-value.** Tests every constant, formula, rate, and threshold from the game theory paper against actual contract code. 18 PAR requirement groups (PAR-01 through PAR-18) covering price tiers, ticket cost formula, pool split BPS, jackpot structure, bucket shares, activity score, lootbox EV, affiliate commission, whale/lazy/deity pricing, gameover drain, coinflip parameters. No other test file systematically verifies paper-to-code parity. This is the "sanity check" suite -- the kind of tests that catch specification drift. |
| test/validation/SimContractParity.test.js (211 lines) | test/validation/PaperParity.test.js (partially) | DELETE | **4 test cases** comparing simBridge.js formulas against contract outputs. (1) Price parity: `priceForLevel(0)` vs `purchaseInfo().priceWei` -- already covered by PaperParity PAR-01 which tests 30+ levels. (2) Pool routing parity: 90/10 split -- already covered by PaperParity PAR-03. (3) Whale bundle pricing: -- covered by PaperParity PAR-10 + WhaleBundle.test.js. (4) Cumulative purchase tracking: -- covered by PaperParity PAR-03 + unit tests. The simBridge.js dependency is only used by this file and adds maintenance burden without unique coverage. |

## All Files -- Final Verdicts

### Foundry (test/fuzz/) -- 42 files

| File | Lines | Verdict | Justification |
|------|-------|---------|---------------|
| test/fuzz/AdvanceGameRewrite.t.sol | 279 | KEEP | Fuzz tests for advanceGame rewrite correctness |
| test/fuzz/AffiliateDgnrsClaim.t.sol | 404 | KEEP | Fuzz tests for affiliate DGNRS claim path |
| test/fuzz/BafRebuyReconciliation.t.sol | 231 | KEEP | Bug fix proof test for BAF rebuy delta |
| test/fuzz/BurnieCoinInvariants.t.sol | 211 | KEEP | Fuzz invariants for BurnieCoin token |
| test/fuzz/DeployCanary.t.sol | 64 | KEEP | Deploy verification canary |
| test/fuzz/DustAccumulation.t.sol | 251 | KEEP | Fuzz tests for dust accumulation edge cases |
| test/fuzz/FarFutureIntegration.t.sol | 214 | KEEP | Fuzz tests for far-future ticket integration |
| test/fuzz/FuturepoolSkim.t.sol | 696 | KEEP | Fuzz tests for future pool skim logic |
| test/fuzz/JackpotCombinedPool.t.sol | 311 | KEEP | Fuzz tests for combined jackpot pool |
| test/fuzz/LockRemoval.t.sol | 213 | KEEP | Fuzz tests for rngLock removal paths |
| test/fuzz/LootboxRngLifecycle.t.sol | 693 | KEEP | Fuzz tests for lootbox RNG lifecycle |
| test/fuzz/PrecisionBoundary.t.sol | 327 | KEEP | Fuzz tests for precision boundary conditions |
| test/fuzz/PriceLookupInvariants.t.sol | 100 | KEEP | Fuzz invariants for PriceLookupLib |
| test/fuzz/PrizePoolFreeze.t.sol | 317 | KEEP | Fuzz tests for prize pool freeze scenarios |
| test/fuzz/QueueDoubleBuffer.t.sol | 359 | KEEP | Fuzz tests for ticket queue double buffering |
| test/fuzz/RedemptionGas.t.sol | 145 | KEEP | Gas profiling for redemption paths |
| test/fuzz/RedemptionSplit.t.sol | 68 | KEEP | Fuzz tests for redemption split logic |
| test/fuzz/ShareMathInvariants.t.sol | 142 | KEEP | Fuzz invariants for share math conservation |
| test/fuzz/StallResilience.t.sol | 215 | KEEP | Fuzz tests for VRF stall resilience |
| test/fuzz/StorageFoundation.t.sol | 363 | KEEP | Storage layout verification tests |
| test/fuzz/TicketEdgeCases.t.sol | 356 | KEEP | Fuzz tests for ticket edge cases |
| test/fuzz/TicketLifecycle.t.sol | 2305 | KEEP | Full ticket lifecycle fuzz tests |
| test/fuzz/TicketProcessingFF.t.sol | 423 | KEEP | Fuzz tests for far-future ticket processing |
| test/fuzz/TicketRouting.t.sol | 204 | KEEP | Fuzz tests for ticket routing logic |
| test/fuzz/TqFarFutureKey.t.sol | 85 | KEEP | Fuzz tests for far-future key derivation |
| test/fuzz/VRFCore.t.sol | 616 | KEEP | Core VRF fuzz tests |
| test/fuzz/VRFLifecycle.t.sol | 158 | KEEP | VRF lifecycle fuzz tests |
| test/fuzz/VRFPathCoverage.t.sol | 359 | KEEP | VRF path coverage fuzz tests |
| test/fuzz/VRFStallEdgeCases.t.sol | 684 | KEEP | VRF stall edge case fuzz tests |
| test/fuzz/helpers/NonceCheck.t.sol | - | KEEP | Helper test (not counted in total) |

### Foundry Invariant (test/fuzz/invariant/) -- 11 files

| File | Lines | Verdict | Justification |
|------|-------|---------|---------------|
| test/fuzz/invariant/CoinSupply.inv.t.sol | 67 | KEEP | Invariant: BURNIE supply conservation |
| test/fuzz/invariant/Composition.inv.t.sol | 79 | KEEP | Invariant: function composition safety |
| test/fuzz/invariant/DegeneretteBet.inv.t.sol | 94 | KEEP | Invariant: Degenerette bet payout cap |
| test/fuzz/invariant/EthSolvency.inv.t.sol | 92 | KEEP | Invariant: ETH solvency (claimable <= balance) |
| test/fuzz/invariant/GameFSM.inv.t.sol | 67 | KEEP | Invariant: game finite state machine |
| test/fuzz/invariant/MultiLevel.inv.t.sol | 104 | KEEP | Invariant: multi-level progression |
| test/fuzz/invariant/RedemptionInvariants.inv.t.sol | 243 | KEEP | Invariant: redemption flow |
| test/fuzz/invariant/TicketQueue.inv.t.sol | 66 | KEEP | Invariant: ticket queue consistency |
| test/fuzz/invariant/VaultShare.inv.t.sol | 73 | KEEP | Invariant: vault share accounting |
| test/fuzz/invariant/VaultShareMath.inv.t.sol | 107 | KEEP | Invariant: vault share math |
| test/fuzz/invariant/VRFPathInvariants.inv.t.sol | 100 | KEEP | Invariant: VRF path invariants |
| test/fuzz/invariant/WhaleSybil.inv.t.sol | 91 | KEEP | Invariant: whale sybil resistance |

### Halmos (test/halmos/) -- 4 files

| File | Lines | Verdict | Justification |
|------|-------|---------|---------------|
| test/halmos/Arithmetic.t.sol | 166 | KEEP | Symbolic verification of arithmetic |
| test/halmos/GameFSM.t.sol | 179 | KEEP | Symbolic verification of game FSM |
| test/halmos/NewProperties.t.sol | 103 | KEEP | Symbolic verification of new properties |
| test/halmos/RedemptionRoll.t.sol | 56 | KEEP | Symbolic verification of redemption roll bounds |

### Hardhat (test/) -- 44 files

| File | Lines | Verdict | Justification |
|------|-------|---------|---------------|
| test/access/AccessControl.test.js | 498 | KEEP | Unique: systematic access guard testing for all 29 contracts |
| test/deploy/DeployScript.test.js | 105 | KEEP | Unique: deploy verification canary |
| test/unit/AffiliateHardening.test.js | 1017 | KEEP | Unique: per-referrer commission cap, lootbox taper, 25+ test cases |
| test/unit/BurnieCoinflip.test.js | 815 | KEEP | Unique: coinflip deposit, settlement, cap, quest interaction |
| test/unit/BurnieCoin.test.js | 902 | KEEP | Unique: ERC20 compliance, mint/burn, vault escrow |
| test/unit/DegenerusAdmin.test.js | 592 | KEEP | Unique: admin functions, LINK handling, price feed |
| test/unit/DegenerusAffiliate.test.js | 1156 | KEEP | Unique: affiliate code creation, referral tracking, commission |
| test/unit/DegenerusDeityPass.test.js | 659 | KEEP | Unique: ERC721 deity pass, T(n) pricing, refund |
| test/unit/DegenerusGame.test.js | 701 | KEEP | Unique: core game operations, purchase, operator approval |
| test/unit/DegenerusJackpots.test.js | 909 | KEEP | Unique: jackpot structure, payout calculation |
| test/unit/DegenerusQuests.test.js | 1041 | KEEP | Unique: quest system, streak tracking |
| test/unit/DegenerusStonk.test.js | 698 | KEEP | Unique: sDGNRS soulbound token, governance |
| test/unit/DegenerusVault.test.js | 561 | KEEP | Unique: vault deposit/withdrawal, share math |
| test/unit/DGNRSLiquid.test.js | 487 | KEEP (borderline) | Some overlap with ShareMathInvariants.t.sol but covers behavioral correctness (transfer, approval, soulbound enforcement) |
| test/unit/DistressLootbox.test.js | 336 | KEEP | Unique: lootbox distress mechanics |
| test/unit/EthInvariant.test.js | 240 | KEEP (borderline) | Some overlap with EthSolvency.inv.t.sol but covers named lifecycle scenarios useful for debugging |
| test/unit/GovernanceGating.test.js | 698 | KEEP | Unique: governance proposal gating, voting, execution |
| test/unit/Icons32Data.test.js | 614 | KEEP | Unique: icon data finalization, path validation |
| test/unit/SecurityEconHardening.test.js | 919 | KEEP | Unique: 10 FIX categories, gameOver blocking, sentinel pattern |
| test/unit/VRFGovernance.test.js | 828 | KEEP | Unique: VRF governance propose/vote/execute lifecycle |
| test/unit/WrappedWrappedXRP.test.js | 855 | KEEP | Unique: WWXRP token, mint/burn, access control |
| test/edge/CompressedAffiliateBonus.test.js | 292 | KEEP | Unique: compressed jackpot affiliate bonus |
| test/edge/CompressedJackpot.test.js | 566 | KEEP | Unique: compression tier transitions |
| test/edge/GameOver.test.js | 427 | KEEP | Unique: gameOver flow, deity refund, terminal jackpot |
| test/edge/PriceEscalation.test.js | 311 | KEEP | Unique: price escalation across level boundaries |
| test/edge/RngStall.test.js | 723 | KEEP | Unique: named RNG stall scenarios with timing assertions |
| test/edge/WhaleBundle.test.js | 729 | KEEP | Unique: whale bundle pricing, quantity limits, gas |
| test/gas/AdvanceGameGas.test.js | 1005 | KEEP | Unique: gas profiling for advanceGame across states |
| test/integration/GameLifecycle.test.js | 593 | KEEP | Unique: end-to-end multi-level game progression |
| test/integration/VRFIntegration.test.js | 429 | KEEP | Unique: VRF request/fulfill through actual Game contract |
| test/validation/PaperParity.test.js | 1102 | KEEP | Unique: paper-to-code constant verification (18 PAR groups) |
| test/validation/SimContractParity.test.js | 211 | DELETE | Covered by PaperParity PAR-01/03/10 + WhaleBundle.test.js |
| test/adversarial/EconomicAdversarial.test.js | 302 | DELETE | Covered by BurnieCoinflip + AffiliateHardening + DegeneretteBet.inv.t.sol + AffiliateDgnrsClaim.t.sol |
| test/adversarial/SepoliaActorAdversarial.test.js | 498 | DELETE | Requires external Sepolia infrastructure; covered by AccessControl + BurnieCoinflip + DegenerusGame |
| test/adversarial/TechnicalAdversarial.test.js | 204 | DELETE | Covered by RngStall + VRFGovernance + DegenerusGame + AdvanceGameRewrite.t.sol |
| test/simulation/simulation-2-levels.test.js | 436 | DELETE | Console-only output, no meaningful assertions; covered by GameLifecycle + MultiLevel.inv.t.sol |
| test/simulation/simulation-5-levels.test.js | 373 | DELETE | Console-only output, no meaningful assertions; covered by GameLifecycle + MultiLevel.inv.t.sol |
| test/poc/Coercion.test.js | 238 | DELETE | Ghost test (excluded from runner); covered by AccessControl + DegenerusGame + VRFGovernance |
| test/poc/NationState.test.js | 204 | DELETE | Ghost test (excluded from runner); covered by AccessControl |
| test/poc/Phase24_FormalMethods.test.js | 190 | DELETE | Ghost test (excluded from runner); covered by PaperParity + EthInvariant + EthSolvency.inv.t.sol |
| test/poc/Phase25_DependencyIntegration.test.js | 359 | DELETE | Ghost test (excluded from runner); covered by RngStall + VRFGovernance + VRFCore.t.sol + DegenerusAdmin |
| test/poc/Phase26_GasGriefing.test.js | 262 | DELETE | Ghost test (excluded from runner); 7 of 8 tests are `expect(true).to.be.true` attestations |
| test/poc/Phase27_WhiteHat.test.js | 128 | DELETE | Ghost test (excluded from runner); covered by BurnieCoin + DegenerusDeityPass + DegenerusGame + WrappedWrappedXRP |
| test/poc/Phase28_GameTheory.test.js | 382 | DELETE | Ghost test (excluded from runner); covered by EthInvariant + PaperParity + SecurityEconHardening + GameOver |

## Deletion Manifest

Files to delete:

**Ghost Tests (poc/) -- 7 files, 1,763 lines:**
- test/poc/Coercion.test.js -- ghost test excluded from Hardhat runner; access control + admin covered by AccessControl.test.js, DegenerusGame.test.js, VRFGovernance.test.js
- test/poc/NationState.test.js -- ghost test excluded from Hardhat runner; 13 access control tests covered by AccessControl.test.js
- test/poc/Phase24_FormalMethods.test.js -- ghost test excluded from Hardhat runner; formal properties covered by PaperParity.test.js, EthInvariant.test.js, EthSolvency.inv.t.sol
- test/poc/Phase25_DependencyIntegration.test.js -- ghost test excluded from Hardhat runner; VRF/LINK/stETH dependency tests covered by RngStall, VRFGovernance, VRFCore.t.sol, DegenerusAdmin
- test/poc/Phase26_GasGriefing.test.js -- ghost test excluded from Hardhat runner; 7/8 tests are `expect(true).to.be.true` attestations with no contract interaction
- test/poc/Phase27_WhiteHat.test.js -- ghost test excluded from Hardhat runner; ERC20/ERC721/claim tests covered by unit tests for each contract
- test/poc/Phase28_GameTheory.test.js -- ghost test excluded from Hardhat runner; solvency/pricing/gameOver covered by EthInvariant, PaperParity, SecurityEconHardening

**Adversarial Suite -- 3 files, 1,004 lines:**
- test/adversarial/EconomicAdversarial.test.js -- 4 tests covered by BurnieCoinflip, AffiliateHardening, DegeneretteBet.inv.t.sol, AffiliateDgnrsClaim.t.sol
- test/adversarial/SepoliaActorAdversarial.test.js -- requires external Sepolia infrastructure (fork URL + events DB); never runs in standard test suite; covered by AccessControl, BurnieCoinflip, DegenerusGame
- test/adversarial/TechnicalAdversarial.test.js -- 4 tests covered by RngStall, VRFGovernance, DegenerusGame, AdvanceGameRewrite.t.sol

**Simulation Suite -- 2 files, 809 lines:**
- test/simulation/simulation-2-levels.test.js -- console.log simulation with no meaningful assertions; multi-level progression covered by GameLifecycle.test.js + MultiLevel.inv.t.sol
- test/simulation/simulation-5-levels.test.js -- console.log simulation with no meaningful assertions; adds no unique coverage beyond 2-level version

**Validation (partial) -- 1 file, 211 lines:**
- test/validation/SimContractParity.test.js -- 4 tests comparing simBridge.js formulas to contracts; all covered by PaperParity (PAR-01, PAR-03, PAR-10) + WhaleBundle.test.js

**Also delete support file:**
- test/validation/simBridge.js -- only used by SimContractParity.test.js (no other consumer)

**Total: 13 test files + 1 support file = 14 files deleted, ~3,998 lines removed**
