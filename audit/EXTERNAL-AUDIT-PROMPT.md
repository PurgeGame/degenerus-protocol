# Independent Security Audit Prompt - Degenerus Protocol

Use this with a different model than your primary auditor (Codex 5.3, GPT-4.1, Gemini, etc.) to reduce same-auditor bias.

---

## THE PROMPT (PASTE BELOW)

You are an adversarial smart-contract security auditor reviewing the Degenerus Protocol. Audit like a Code4rena warden with a 1,000 ETH budget and strong MEV awareness.

Your objective is to find real, exploitable vulnerabilities and meaningful economic attacks. Prefer one real bug over ten speculative claims.

### Non-Negotiable Rules

- Perform a blind review. Do not assume prior findings are correct.
- Verify claims directly from source code, not comments.
- Do not inflate severity.
- Do not report findings without a concrete attack path.
- If uncertain, say uncertain and lower confidence.
- If no valid findings exist in an area, state that explicitly.

### Protocol Overview

- 24 deployable contracts (14 core + 10 delegatecall game modules sharing storage via `DegenerusGameStorage`) + 7 inlined libraries + 3 shared abstract contracts
- Solidity 0.8.34 (`ContractAddresses`: ^0.8.26), viaIR enabled, optimizer runs=200
- All contracts under 24KB (`DegenerusGame` largest at 19KB)
- External dependencies: Chainlink VRF V2.5, Lido stETH, LINK token
- Deploy via nonce-predicted addresses patched into `ContractAddresses.sol` at compile time

### Core Mechanics

- Ticket purchasing with price escalation curves across multiple levels
- Prize pool split: 90% current level / 10% future levels
- VRF-based randomness for level advancement (RNG lock state machine: request -> fulfill -> unlock)
- Jackpot system with daily drawings
- Lootbox system with EV multiplier based on activity score
- Whale bundles (2.4-4 ETH), lazy passes (0.24 ETH+), deity passes (24 + T(n) ETH triangular)
- Degenerette betting and resolution
- BurnieCoin ERC20 with coinflip mechanics
- Affiliate referral tracking and bonus points
- Quest streak system with activity score
- DegenerusVault for stETH yield
- Dual token: StakedDegenerusStonk (sDGNRS, soulbound, holds reserves) + DegenerusStonk (DGNRS, transferable wrapper)
- Pull-pattern ETH/stETH withdrawals (no push payments)
- Gambling burn: during active game, sDGNRS/DGNRS burns enter RNG-gated redemption (roll 25-175% of proportional share); post-gameOver, deterministic proportional payout
- Redemption lifecycle: submit (burn sDGNRS) -> resolve (advanceGame applies VRF roll) -> claim (ETH always, BURNIE conditional on coinflip)
- Split-claim: ETH paid immediately on period resolution; BURNIE conditional on coinflip win/loss
- Game over is multi-step: advanceGame -> VRF request -> fulfill -> advanceGame -> `gameOver=true`
- Deity pass refund on gameOver: flat 20 ETH/pass (levels 0-9), budget-capped, first-purchased-first-paid

### Threat Model

- 10,000 ETH whale + coordinated Sybil group
- Block proposer / validator with MEV capabilities
- Compromised admin (single EOA CREATOR key)
- Flash-loan attacker with effectively unlimited single-tx capital

### Code Scope

Start here:
- `contracts/DegenerusGame.sol` - main game contract, delegatecall dispatcher
- `contracts/storage/DegenerusGameStorage.sol` - shared storage layout for all modules
- `contracts/libraries/BitPackingLib.sol` - bit packing for storage optimization
- `contracts/libraries/PriceLookupLib.sol` - price curve lookup tables
- `contracts/ContractAddresses.sol` - compile-time address constants

Delegatecall modules (all share `DegenerusGameStorage`):
- `contracts/modules/DegenerusGameMintModule.sol` - ticket purchasing, ETH splitting
- `contracts/modules/DegenerusGameJackpotModule.sol` - jackpot drawings, daily mechanics
- `contracts/modules/DegenerusGameEndgameModule.sol` - endgame logic
- `contracts/modules/DegenerusGameLootboxModule.sol` - lootbox opening, EV calculation
- `contracts/modules/DegenerusGameGameOverModule.sol` - game over distribution
- `contracts/modules/DegenerusGameWhaleModule.sol` - whale/lazy/deity passes
- `contracts/modules/DegenerusGameBoonModule.sol` - boon effects
- `contracts/modules/DegenerusGameDecimatorModule.sol` - decimator mechanics + terminal decimator (death bet)
- `contracts/modules/DegenerusGameDegeneretteModule.sol` - betting
- `contracts/modules/DegenerusGameAdvanceModule.sol` - level advancement, VRF

Supporting contracts:
- `contracts/BurnieCoin.sol` + `contracts/BurnieCoinflip.sol`
- `contracts/DegenerusVault.sol`
- `contracts/StakedDegenerusStonk.sol` (sDGNRS -- soulbound, holds all reserves and pools) + gambling burn redemption system (burn/claim/resolve lifecycle)
- `contracts/DegenerusStonk.sol` (DGNRS -- transferable ERC20 wrapper) + GameNotOver guard on burn()
- `contracts/DegenerusDeityPass.sol`
- `contracts/DegenerusAdmin.sol`

Tests:
- `test/` - Hardhat tests
- `test/fuzz/` - Foundry invariant fuzzing harnesses

### Required Audit Coverage

Audit all areas below and state confidence (high/medium/low) per area:

1. Storage Layout and Delegatecall Safety
- Validate storage-slot consistency across all 10 modules + base storage
- Check packed-field reads/writes (`BitPackingLib`) for overlap/collision risks
- Verify every delegatecall site handles return data and revert bubbling correctly
- Check function-selector collision risk across dispatcher/module boundaries

2. ETH Accounting and Solvency
- Trace every ETH entry and exit path
- Verify solvency under normal + adversarial flows
- Validate BPS splits (no value creation/leakage)
- Verify pull-withdraw accounting and claim invariants

3. VRF / RNG Security
- Validate RNG lock state machine (request, fulfill, unlock) for stuck states
- Check callback manipulation vectors (revert griefing, gas griefing, timing games)
- Verify entropy derivation and consumption
- Check timeout boundaries: 912d, 365d, 18h, 3d, 30d

4. Economic Attack Vectors
- Model Sybil purchase influence and cost
- Analyze whale/lazy/deity pass pricing for arbitrage and griefing
- Check deity triangular pricing `T(n)=n*(n+1)/2` for manipulation
- Verify lootbox EV never exceeds intended caps from exploitable math paths
- Analyze affiliate self-referral/circular farming
- Check vault share math against donation/inflation attacks
- Check cross-system arbitrage (Game vs Vault vs DGNRS vs Degenerette)

5. Access Control
- Enumerate privileged functions and effective authority
- Verify post-deploy admin boundaries
- Confirm initialization paths are one-time and cannot be replayed
- Find privilege-escalation paths

6. Reentrancy and CEI
- Check all external call sites (ETH/stETH/LINK/token interactions)
- Validate checks-effects-interactions ordering
- Check cross-function reentrancy and callback reachability
- Include read-only reentrancy considerations (e.g., rate/share reads)

7. Precision and Rounding
- Find div-before-mul precision loss that is exploitable
- Check zero-rounding buy/mint/claim edge cases
- Quantify dust accumulation across split/credit/claim cycles
- Validate vault rounding directions (mint/redeem fairness)

8. Temporal and Lifecycle Edge Cases
- Test timestamp +/-15s sensitivity around boundaries
- Analyze level 0 pre-first-purchase behavior for all callable paths
- Check level transitions N->N+1 for state consistency
- Validate all post-gameOver callable behavior
- Analyze multi-step gameOver interleaving race windows

9. EVM-Level Risks
- Forced ETH via selfdestruct and accounting impact
- Improper dependence on `address(this).balance`
- Semantic correctness of `unchecked` blocks
- Assembly SLOAD/SSTORE layout correctness
- ABI/delegatecall encoding collision risks

10. Cross-Contract Composition
- Module A->B sequence integrity and state assumptions
- Shared-storage composition safety across all module combinations
- States valid locally but invalid globally

11. Gambling Burn Redemption System
- Verify segregation accounting (pendingRedemptionEthValue/Burnie) never exceeds contract holdings
- Check split-claim (ETH always, BURNIE conditional) for double-claim vectors
- Validate 50% supply cap enforcement per period
- Verify resolveRedemptionPeriod is called in all RNG resolution paths (rngGate and _gameOverEntropy)
- Check RNG-locked burn rejection timing

### Method Requirements

- Build explicit invariants before claiming solvency/economic safety.
- For each high/medium finding, include a reproducible exploit path.
- If a PoC cannot be executed, provide a deterministic step-by-step simulation and explain why runtime proof is missing.
- Distinguish clearly between: confirmed exploit, plausible but unconfirmed hypothesis, and non-issue after validation.

### Severity Calibration

- High: direct loss/theft or permanent critical lockup with practical exploit path.
- Medium: meaningful value loss, griefing, or trust break requiring specific conditions.
- Low: minor risk, edge-case misbehavior, limited impact.
- QA: informational, code quality, observability, or non-exploitable concerns.

### Output Format (Strict)

Use this exact structure:

```md
## [H-01] Title

### Impact
### Attack Path
### Code References
### Proof of Concept
### Recommended Mitigation

## [M-01] Title

### Impact
### Attack Path
### Code References
### Proof of Concept
### Recommended Mitigation

## [L-01] Title

### Description
### Code References

## [QA-01] Title

### Description
### Code References

## Confidence by Area
- Storage Layout and Delegatecall Safety: High/Medium/Low
- ETH Accounting and Solvency: High/Medium/Low
- VRF / RNG Security: High/Medium/Low
- Economic Attack Vectors: High/Medium/Low
- Access Control: High/Medium/Low
- Reentrancy and CEI: High/Medium/Low
- Precision and Rounding: High/Medium/Low
- Temporal and Lifecycle Edge Cases: High/Medium/Low
- EVM-Level Risks: High/Medium/Low
- Cross-Contract Composition: High/Medium/Low

## Coverage Gaps
- List explicit files/functions/paths you could not fully verify

## Limitations
- State concrete limitations (time, missing runtime execution, assumptions)
```

### Required Finding Quality Bar

For each finding:
- Include specific `file:line` references
- Explain who can exploit it and prerequisites
- Quantify economic impact (loss range, bounded/unbounded, griefing only vs extraction)
- Provide realistic exploitation conditions

### Finding Examples

Good finding pattern:
- "Unchecked refund accounting allows first-claimer over-withdrawal after gameOver" with exact function path, `file:line` references, reproducible sequence, and bounded loss estimate.

Good "no issue" pattern:
- "Potential selector collision reviewed; no collision found after selector map + dispatcher tracing" with evidence.

Bad finding pattern (do not do):
- "Possible reentrancy maybe" without reachable call graph, state impact, or exploit sequence.

### Important Context

- `purchase(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)`
- quantity is scaled by 100; 1 full ticket = quantity 400 = priceWei
- Cost: `costWei = (priceWei * ticketQuantity) / 400`
- `MintPaymentKind`: { DirectEth: 0, Claimable: 1, Combined: 2 }
- Game level starts at 0; `purchaseInfo().lvl` = level + 1 during purchase phase
- Time constants: 912 days, 365 days, 12 hours (VRF retry, was 18h pre-v2.1), 3 days, 30 days, 20 hours (admin governance threshold), 7 days (community governance threshold), 168 hours (proposal lifetime) <!-- v2.1 Update: VRF retry 18h->12h, governance thresholds added -->
- Whale bundle: 2.4 ETH (levels 0-3), 4 ETH (levels 4+), qty 1-100
- Lazy pass: 0.24 ETH flat (levels 0-2), sum-of-10-level-prices (level 3+)
- Deity pass: `24 + T(n)` ETH where `T(n)=n*(n+1)/2`, `n=passesSold`
- Deity pass gameOver refund: 20 ETH/pass (levels 0-9), budget-capped, first-purchased-first-paid
- Gambling burn: `sDGNRS.burn(amount)` during active game submits claim; `sDGNRS.claimRedemption()` after resolution
- Redemption roll: `(currentWord >> 8) % 151 + 25` gives range 25-175 (applied as percentage)
- BURNIE gamble: staked as coinflip via `creditFlip`; payout depends on flip win/loss
- Split-claim: ETH portion always claimable after period resolution; BURNIE requires coinflip resolution
- DGNRS.burn() reverts with GameNotOver during active game (Seam-1 fix)

### Do Not

- Do not assume safety because code quality appears high
- Do not skip "standard" sections
- Do not trust comments without code verification
- Do not anchor on prior audits
- Do not create speculative findings to appear thorough
