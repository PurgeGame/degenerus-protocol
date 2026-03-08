# Independent Security Audit Prompt — Degenerus Protocol

Use this prompt with a different model (Codex 5.3, GPT-4.1, Gemini, etc.) to get an independent security review that avoids same-auditor bias.

---

## THE PROMPT

You are performing a comprehensive, adversarial security audit of the Degenerus Protocol — a Solidity smart contract suite for an on-chain multi-level ticket purchasing game. Your job is to find every exploitable vulnerability, economic attack, and edge-case failure. Think like a Code4rena warden with a 1,000 ETH budget trying to break this game.

### Protocol Overview

- **23 deployable contracts** (13 core + 10 delegatecall game modules sharing storage via `DegenerusGameStorage`) + 7 inlined libraries
- Solidity 0.8.34 (ContractAddresses: ^0.8.26), viaIR enabled, optimizer runs=200
- All contracts under 24KB (DegenerusGame largest at 19KB)
- External dependencies: Chainlink VRF V2.5, Lido stETH, LINK token
- Deploy via nonce-predicted addresses patched into `ContractAddresses.sol` at compile time

### Core Mechanics

- **Ticket purchasing** with price escalation curves across multiple levels
- **Prize pool split**: 90% current level / 10% future levels
- **VRF-based randomness** for level advancement (RNG lock state machine: request → fulfill → unlock)
- **Jackpot system** with daily drawings
- **Lootbox** system with EV multiplier based on activity score
- **Whale bundles** (2.4-4 ETH), **lazy passes** (0.24 ETH+), **deity passes** (24 + T(n) ETH triangular)
- **Degenerette** betting and resolution
- **BurnieCoin** ERC20 with coinflip mechanics
- **Affiliate referral** tracking and bonus points
- **Quest streak** system with activity score
- **DegenerusVault** for stETH yield
- **Pull-pattern ETH/stETH withdrawals** (no push payments)
- **Game over** is multi-step: advanceGame→VRF request→fulfill→advanceGame→gameOver=true
- **Deity pass refund** on gameOver: flat 20 ETH/pass (levels 0-9), budget-capped, first-purchased-first-paid

### Threat Model

- **10,000 ETH whale** + coordinated Sybil group
- **Block proposer/validator** with MEV capabilities
- **Compromised admin** (single EOA CREATOR key)
- **Flash loan attacker** with unlimited capital for single transactions

### Architecture (Key Files)

**Start here:**
- `contracts/DegenerusGame.sol` — main game contract, delegatecall dispatcher
- `contracts/DegenerusGameStorage.sol` — shared storage layout for all modules
- `contracts/lib/BitPackingLib.sol` — bit packing for storage optimization
- `contracts/lib/PriceLookupLib.sol` — price curve lookup tables
- `contracts/lib/ContractAddresses.sol` — compile-time address constants

**10 delegatecall modules (all share DegenerusGame storage):**
- `contracts/modules/DegenerusGameMintModule.sol` — ticket purchasing, ETH splitting
- `contracts/modules/DegenerusGameJackpotModule.sol` — jackpot drawings, daily mechanics
- `contracts/modules/DegenerusGameEndgameModule.sol` — endgame logic
- `contracts/modules/DegenerusGameLootboxModule.sol` — lootbox opening, EV calculation
- `contracts/modules/DegenerusGameGameOverModule.sol` — game over distribution
- `contracts/modules/DegenerusGameWhaleModule.sol` — whale/lazy/deity passes
- `contracts/modules/DegenerusGameBoonModule.sol` — boon effects
- `contracts/modules/DegenerusGameDecimatorModule.sol` — decimator mechanics
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — betting
- `contracts/modules/DegenerusGameAdvanceModule.sol` — level advancement, VRF

**Supporting contracts:**
- `contracts/BurnieCoin.sol` + `contracts/BurnieCoinflip.sol` — ERC20 + coinflip
- `contracts/DegenerusVault.sol` — stETH vault with share math
- `contracts/DegenerusStonk.sol` — token mechanics
- `contracts/DegenerusDeityPass.sol` — ERC721 deity pass NFT
- `contracts/DegenerusAdmin.sol` — admin functions, VRF wiring

**Test infrastructure:**
- `test/` — 1,184 Hardhat tests
- `test/fuzz/` — Foundry invariant fuzzing harnesses

### What to Audit

Perform a BLIND audit. Do not assume any prior findings or safety conclusions. For each area below, read the actual source code and form your own opinion:

#### 1. Storage Layout and Delegatecall Safety
- Verify storage slot assignments across all 10 modules sharing `DegenerusGameStorage`
- Check for slot collisions, especially with `BitPackingLib` packed fields
- Verify all 46 delegatecall sites (31 in Game + 15 cascading in modules) handle return values correctly
- Check for function selector collisions across module boundaries

#### 2. ETH Accounting and Solvency
- Trace every ETH entry point (receive, payable functions) and exit point (transfers, calls)
- Verify the protocol can always pay out what it owes (solvency invariant)
- Check BPS fee splits sum correctly (no ETH leaked or created)
- Verify pull-pattern withdrawal safety

#### 3. VRF/RNG Security
- Analyze the RNG lock state machine for stuck states and recovery paths
- Check VRF callback for manipulation (revert on unfavorable outcome, gas griefing)
- Verify entropy derivation from VRF randomness
- Check all timeout boundaries (912d, 365d, 18h, 3d, 30d)

#### 4. Economic Attack Vectors
- Model Sybil attacks on ticket purchasing (cost vs. influence)
- Analyze whale pass pricing for arbitrage opportunities
- Check deity pass T(n) triangular pricing for manipulation
- Verify lootbox EV calculation cannot exceed 1.0
- Check affiliate system for circular/self-referral farming
- Analyze vault share math for donation/inflation attacks
- Check cross-system price arbitrage (Game pricing vs Vault shares vs DGNRS vs Degenerette)

#### 5. Access Control
- Map every privileged function and who can call it
- Check admin power boundaries post-deployment
- Verify constructor-only initialization cannot be re-called
- Check for privilege escalation paths

#### 6. Reentrancy and CEI
- Check every external call site for reentrancy (ETH transfers, stETH operations, LINK transfers)
- Verify checks-effects-interactions pattern at all sites
- Check cross-function reentrancy (function A calls external, callback enters function B)
- Check read-only reentrancy via stETH share rate

#### 7. Precision and Rounding
- Audit all division operations for division-before-multiplication chains
- Check for zero-rounding (inputs that round to zero cost while producing non-zero output)
- Analyze dust accumulation across purchase→split→credit→claim cycles
- Verify vault share math ceil/floor rounding directions

#### 8. Temporal and Lifecycle Edge Cases
- Test timestamp ±15s manipulation against all timeout boundaries
- Analyze level 0 (pre-first-purchase) state for every callable function
- Check level boundary transitions (N→N+1) for state consistency
- Test all functions post-gameOver for correct behavior
- Analyze the multi-step gameOver interleaving (state between steps)

#### 9. EVM-Level
- Check for forced ETH via selfdestruct affecting internal accounting
- Verify no `address(this).balance` used to set pool amounts
- Audit all `unchecked` blocks for semantic correctness (not just overflow)
- Verify all assembly SSTORE/SLOAD against storage layout
- Check ABI encoding for collision risk in delegatecall dispatch

#### 10. Cross-Contract Composition
- Test module A→B execution sequences for state corruption
- Verify shared storage assumptions hold across all module combinations
- Check for state that's valid per-module but invalid in composition

### Output Format

Produce a C4A-format findings report:

```
## [H-01] Title (if any HIGH findings)

### Impact
### Proof of Concept
### Recommended Mitigation

## [M-01] Title (if any MEDIUM findings)

### Impact
### Proof of Concept
### Recommended Mitigation

## [L-01] Title (if any LOW findings)

### Description

## [QA-01] Title (for informational/QA)

### Description
```

For each finding:
- Include a specific code reference (file:line)
- Write a proof of concept showing the exploit
- Explain the economic impact (how much can be extracted, by whom)
- Rate severity honestly (don't inflate for engagement)

### Honesty Requirements

- If you find nothing, say so — don't manufacture findings
- Report your confidence level for each area (high/medium/low)
- List explicit coverage gaps (areas you couldn't fully analyze)
- State your limitations honestly

### Important Context

- `purchase(buyer, ticketQuantity, lootBoxAmount, affiliateCode, payKind)` — qty scaled by 100; 1 "full ticket" = quantity 400 = costs priceWei
- Cost formula: `costWei = (priceWei * ticketQuantity) / 400`
- MintPaymentKind: { DirectEth: 0, Claimable: 1, Combined: 2 }
- Game level starts at 0; `purchaseInfo().lvl` = level+1 (active ticket level) during purchase phase
- Time constants: 912 days (pre-game timeout), 365 days (post-game inactivity), 18 hours (VRF retry), 3 days (emergency stall), 30 days (final sweep)
- Whale bundle: 2.4 ETH (levels 0-3), 4 ETH (x49/x99), qty 1-100
- Lazy pass: 0.24 ETH flat (levels 0-2), sum-of-10-level-prices (level 3+)
- Deity pass: 24 + T(n) ETH where T(n) = n*(n+1)/2, n = passes sold
- Deity pass gameOver refund: flat 20 ETH/pass (levels 0-9), budget-capped, first-purchased-first-paid

### DO NOT

- Do not assume the protocol is safe because it "looks well-written"
- Do not skip areas because they "seem standard"
- Do not trust comments — verify against code
- Do not anchor on any prior audit conclusions
- Do not report false positives to appear thorough
