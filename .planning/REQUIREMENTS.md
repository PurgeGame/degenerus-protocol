# Requirements: Degenerus Protocol Security Audit

**Defined:** 2026-02-28
**Core Value:** Every ETH that enters the protocol must be accounted for, every RNG outcome must be unmanipulable, and no actor can extract value beyond what the game mechanics intend.

## v1 Requirements

Requirements for the security audit. Each maps to roadmap phases.

### Storage Foundation

- [x] **STOR-01**: All 10 delegatecall modules have identical storage layout to DegenerusGame — no module declares instance storage variables
- [ ] **STOR-02**: Storage slot ordering in DegenerusGameStorage matches `forge inspect` output for all module contracts
- [ ] **STOR-03**: ContractAddresses compile-time constants are correctly mapped — no address(0) values remain in deployed bytecode
- [x] **STOR-04**: No testnet configuration (`TESTNET_ETH_DIVISOR`) bleeds into mainnet contract logic

### RNG State Machine

- [x] **RNG-01**: `rngLockedFlag` remains set continuously from VRF request through word consumption in `advanceGame` — no window exists for nudge manipulation
- [x] **RNG-02**: `rawFulfillRandomWords` cannot revert under any condition (gas limit, panic, require) — VRF coordinator does not retry failed callbacks
- [x] **RNG-03**: `rawFulfillRandomWords` gas cost stays under 200,000 gas with headroom against VRF_CALLBACK_GAS_LIMIT (300,000)
- [x] **RNG-04**: `requestId` matching is correct — no mismatch can cause wrong VRF word applied to wrong game state
- [x] **RNG-05**: Concurrent VRF requests (daily RNG vs lootbox mid-day RNG) cannot create requestId ordering conflicts
- [x] **RNG-06**: RNG lock cannot be bypassed or stuck permanently — all stuck states are recoverable via stall recovery
- [x] **RNG-07**: 18-hour VRF retry timeout cannot be abused by a validator to selectively trigger or delay fulfillment
- [x] **RNG-08**: `reverseFlip()` nudge mechanism cannot be exploited by a block proposer who sees the fulfilled VRF word in mempool
- [x] **RNG-09**: `EntropyLib.entropyStep()` XOR-shift derivation from VRF seed does not introduce predictable patterns exploitable by an attacker
- [x] **RNG-10**: No code path uses `block.timestamp` or `blockhash` as a randomness source beyond VRF integration

### ETH Accounting

- [ ] **ACCT-01**: Core invariant holds: `address(this).balance + stETH.balanceOf(this) >= claimablePool` after every possible transaction
- [ ] **ACCT-02**: Prize pool 90%/10% split (currentPrizePool / futurePrizePool) sums correctly — no wei leak from rounding
- [ ] **ACCT-03**: All BPS-based fee splits sum to the original input amount — no rounding accumulation drains the protocol
- [ ] **ACCT-04**: `claimWinnings()` pull-pattern ETH/stETH withdrawal cannot be reentered to drain funds
- [ ] **ACCT-05**: stETH rebasing (daily Lido yield or slashing) does not break accounting — no cached stETH balance used for payout calculations
- [ ] **ACCT-06**: `receive()` ETH routing correctly attributes all incoming ETH to the right pool — no unattributed ETH
- [ ] **ACCT-07**: Game-over settlement distributes all prize pool funds correctly — no funds remain locked after terminal state
- [ ] **ACCT-08**: Stall recovery paths (3-day emergency, 30-day final sweep) correctly attribute all pool funds and cannot be triggered prematurely
- [ ] **ACCT-09**: DegenerusVault stETH yield accounting is consistent — vault mints match expected COIN supply
- [ ] **ACCT-10**: BurnieCoin supply invariant holds — total minted minus burned equals circulating supply across all paths

### Token and Pricing Math

- [x] **MATH-01**: Ticket price escalation formula (PriceLookupLib) is monotonically increasing and does not overflow at max level
- [x] **MATH-02**: Deity pass pricing T(n) = n*(n+1)/2 + 24 ETH does not overflow at realistic pass counts (n=100, n=1000)
- [ ] **MATH-03**: Whale bundle pricing (2.4 ETH levels 0-3, 4 ETH x49/x99) is correctly enforced across all purchase paths
- [x] **MATH-04**: Lazy pass pricing (sum-of-10-level-prices at level 3+) correctly sums the price curve
- [x] **MATH-05**: Lootbox EV multiplier formula produces expected values — activity score cannot create guaranteed positive EV extraction
- [x] **MATH-06**: Degenerette bet resolution pays out correctly — no bet timing relative to VRF creates advantaged positions
- [x] **MATH-07**: Coinflip 50-150% bonus range is correctly bounded — edge cases at 50% and 150% do not over/underpay
- [x] **MATH-08**: BitPackingLib 24-bit field packing/unpacking is correct — no field overflow or bleed across boundaries

### Access Control

- [ ] **AUTH-01**: All admin-only functions (`msg.sender == CREATOR`) are correctly gated — no privilege escalation path exists
- [ ] **AUTH-02**: VRF coordinator callback (`rawFulfillRandomWords`) is restricted to the coordinator address only
- [ ] **AUTH-03**: Module-only entry points cannot be called directly — only reachable via DegenerusGame delegatecall
- [ ] **AUTH-04**: `operatorApprovals` delegation cannot grant more permissions than the player has — revocation is immediate
- [ ] **AUTH-05**: `_resolvePlayer()` correctly routes value flows to `player` not `msg.sender` across all call sites
- [ ] **AUTH-06**: DegenerusAdmin VRF subscription management cannot be griefed by external callers

### Cross-Contract Interactions

- [ ] **XCON-01**: All delegatecall return values are checked — no failing module silently succeeds
- [ ] **XCON-02**: stETH.submit() and stETH.transfer() return values are checked — no silent failure desynchronizes state
- [ ] **XCON-03**: LINK.transferAndCall() return value is checked and cannot create reentrancy
- [ ] **XCON-04**: BurnieCoin.burnCoin() behavior on insufficient balance is safe — no path creates free nudges or coinflips
- [ ] **XCON-05**: Cross-function reentrancy — ETH callback from `claimWinnings` cannot reenter `purchase` or other state-changing functions
- [ ] **XCON-06**: stETH rebasing cannot create a reentrancy vector via Lido internal callbacks during staking paths
- [ ] **XCON-07**: Constructor-time cross-contract calls execute in correct order given the deploy sequence

### Input Validation

- [x] **INPT-01**: Ticket quantity bounds prevent overflow and enforce minimum/maximum constraints
- [x] **INPT-02**: Lootbox amount limits are enforced — no quantity creates gas exhaustion or unbounded iteration
- [x] **INPT-03**: MintPaymentKind enum bounds are validated — invalid enum values cannot corrupt state
- [x] **INPT-04**: Zero-address guards are present on all external-facing functions that accept addresses

### Denial of Service

- [x] **DOS-01**: No unbounded loop exists that can be exploited to exhaust block gas limit
- [x] **DOS-02**: Daily ETH distribution bucket cursor cannot be griefed to skip distributions
- [x] **DOS-03**: Trait burn ticket iteration is bounded — large trait counts cannot block phase transitions

### Economic Attack Surface

- [x] **ECON-01**: Sybil group with 51%+ ticket ownership cannot extract positive group EV from prize pool mechanics
- [x] **ECON-02**: Activity score cannot be cheaply inflated via quest streaks, affiliate self-referral, or coordinated chains to unlock high-EV lootboxes
- [x] **ECON-03**: Affiliate referral system does not create positive-sum extraction where referrer+referee extract more than deposited
- [x] **ECON-04**: MEV/sandwich attacks on ticket purchase price escalation cannot extract value at phase boundaries
- [x] **ECON-05**: Block proposer cannot manipulate `advanceGame` timing to control which level transitions occur
- [x] **ECON-06**: Whale bundle + lootbox purchase sequences cannot extract more than deposited at levels 0-3
- [x] **ECON-07**: AfKing mode transitions do not create windows for double-spend or double-credit

### Game State Machine

- [x] **FSM-01**: FSM transitions PURCHASE ↔ JACKPOT → gameOver are complete — no illegal transitions possible
- [x] **FSM-02**: No game state exists that cannot be exited — all stuck states have recovery paths
- [x] **FSM-03**: Multi-step game-over sequence (advanceGame→VRF→fulfill→advanceGame→gameOver) correctly handles all intermediate states

## v2 Requirements

Deferred to future audit engagement. Tracked but not in current roadmap.

### Formal Verification

- **FVER-01**: Bounded symbolic verification of deity pass T(n) pricing formula via Halmos
- **FVER-02**: Bounded symbolic verification of ticket cost escalation formula via Halmos

### Extended Fuzzing

- **FUZZ-01**: Coverage-guided fuzzing of all ETH accounting paths via Medusa
- **FUZZ-02**: Invariant fuzzing of all BPS split formulas across value ranges 1 wei to 1000 ETH

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gas optimization | Separate concern — not security-relevant unless it creates DoS |
| Contract rewrites / code PRs | Deliverable is findings + remediation guidance, not patches |
| Frontend / off-chain code | Cannot change on-chain state guarantees; separate review needed |
| Mock contracts | Test infrastructure only — not deployed |
| Testnet-specific contracts | TESTNET_ETH_DIVISOR configs not representative of mainnet |
| Deployment scripts | Operational tooling — deploy order noted as checklist item only |
| Raw scanner output without triage | False positive rate too high; only manually confirmed findings |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| STOR-01 | Phase 1 | Complete |
| STOR-02 | Phase 1 | Pending |
| STOR-03 | Phase 1 | Pending |
| STOR-04 | Phase 1 | Complete |
| RNG-01 | Phase 2 | Complete |
| RNG-02 | Phase 2 | Complete |
| RNG-03 | Phase 2 | Complete |
| RNG-04 | Phase 2 | Complete |
| RNG-05 | Phase 2 | Complete |
| RNG-06 | Phase 2 | Complete |
| RNG-07 | Phase 2 | Complete |
| RNG-08 | Phase 2 | Complete |
| RNG-09 | Phase 2 | Complete |
| RNG-10 | Phase 2 | Complete |
| FSM-01 | Phase 2 | Complete |
| FSM-02 | Phase 2 | Complete |
| FSM-03 | Phase 2 | Complete |
| MATH-01 | Phase 3a | Complete |
| MATH-02 | Phase 3a | Complete |
| MATH-03 | Phase 3a | Pending |
| MATH-04 | Phase 3a | Complete |
| INPT-01 | Phase 3a | Complete |
| INPT-02 | Phase 3a | Complete |
| INPT-03 | Phase 3a | Complete |
| INPT-04 | Phase 3a | Complete |
| DOS-01 | Phase 3a | Complete |
| MATH-05 | Phase 3b | Complete |
| MATH-06 | Phase 3b | Complete |
| DOS-02 | Phase 3b | Complete |
| DOS-03 | Phase 3b | Complete |
| MATH-07 | Phase 3c | Complete |
| MATH-08 | Phase 3c | Complete |
| ACCT-01 | Phase 4 | Pending |
| ACCT-02 | Phase 4 | Pending |
| ACCT-03 | Phase 4 | Pending |
| ACCT-04 | Phase 4 | Pending |
| ACCT-05 | Phase 4 | Pending |
| ACCT-06 | Phase 4 | Pending |
| ACCT-07 | Phase 4 | Pending |
| ACCT-08 | Phase 4 | Pending |
| ACCT-09 | Phase 4 | Pending |
| ACCT-10 | Phase 4 | Pending |
| ECON-01 | Phase 5 | Complete |
| ECON-02 | Phase 5 | Complete |
| ECON-03 | Phase 5 | Complete |
| ECON-04 | Phase 5 | Complete |
| ECON-05 | Phase 5 | Complete |
| ECON-06 | Phase 5 | Complete |
| ECON-07 | Phase 5 | Complete |
| AUTH-01 | Phase 6 | Pending |
| AUTH-02 | Phase 6 | Pending |
| AUTH-03 | Phase 6 | Pending |
| AUTH-04 | Phase 6 | Pending |
| AUTH-05 | Phase 6 | Pending |
| AUTH-06 | Phase 6 | Pending |
| XCON-01 | Phase 7 | Pending |
| XCON-02 | Phase 7 | Pending |
| XCON-03 | Phase 7 | Pending |
| XCON-04 | Phase 7 | Pending |
| XCON-05 | Phase 7 | Pending |
| XCON-06 | Phase 7 | Pending |
| XCON-07 | Phase 7 | Pending |

**Coverage:**
- v1 requirements: 56 total
- Mapped to phases: 56
- Unmapped: 0 ✓

---
*Requirements defined: 2026-02-28*
*Last updated: 2026-02-28 after roadmap creation (Phase 3 split into 3a/3b/3c)*
