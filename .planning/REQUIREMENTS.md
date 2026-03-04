# Requirements: Degenerus Protocol Security Audit

**Defined:** 2026-03-04
**Milestone:** v2.0 — Adversarial Audit (Code4rena Preparation)
**Core Value:** Every ETH that enters the protocol must be accounted for, every RNG outcome must be unmanipulable, and no actor — whale, Sybil group, or block proposer — can extract value beyond what the game mechanics intend.

## v2.0 Requirements

### ETH Accounting Integrity (ACCT)
*Closes the v1.0 Phase 4 gap. Master dependency for reentrancy synthesis.*

- [x] **ACCT-01**: ETH accounting invariant verified: `sum(deposits) == prizePool + futurePool + claimablePool + fees` holds across all game states — **PASS** (7/7 invariant checkpoints pass, EthInvariant.test.js)
- [x] **ACCT-02**: `_creditClaimable` call site audit: every call site confirmed to update `claimablePool` in same code path (likely HIGH if any are missing) — **PASS** (11/11 sites CORRECT, Pattern A or B)
- [x] **ACCT-03**: BPS fee split correctness: all splits sum to input with correct rounding direction across all fee paths — **PASS** (all 4 sites use subtraction pattern)
- [x] **ACCT-04**: `claimWinnings()` cross-function reentrancy: `purchase()` re-entry during ETH callback formally traced — **PASS** (strict CEI, sentinel before external call)
- [x] **ACCT-05**: stETH/LINK reentrancy: Lido callback and LINK ERC-677 callback paths formally traced — **PASS+INFO+LOW** (adminStakeEthForStEth CEI-compliant; onTokenTransfer formal deviation not exploitable; creditLinkReward not implemented in BurnieCoin — LOW)
- [x] **ACCT-06**: DegenerusVault share-based redemption: no solvency gap — rounding direction and precision loss verified under realistic deposit/redemption sequences — **PASS** (floor division safe; no partial-burn extraction)
- [x] **ACCT-07**: BurnieCoin supply invariant: total minted equals sum of all credit sources; no free-mint path confirmed — **PASS** (packed struct + VAULT-routing; 6 mint paths enumerated and authorized)
- [x] **ACCT-08**: Game-over terminal settlement: zero-balance proof — all claimable amounts resolvable after game-over — **PASS** (912-day level-0 timeout; gameOver=true; invariant holds)
- [x] **ACCT-09**: `adminStakeEthForStEth` solvency guard: admin cannot stake ETH below `claimablePool` threshold; guard confirmed or MEDIUM finding raised — **PASS** (guard confirmed claimablePool-based)
- [x] **ACCT-10**: `receive()` donation to `futurePrizePool`: inflating pool via direct ETH send cannot artificially trigger game conditions (level transition thresholds, BAF activation, etc.); selfdestruct forced ETH that bypasses `receive()` does not create extractable solvency surplus — **PASS+INFO** (futurePrizePool only; no triggers; selfdestruct is protocol reserve)

### Gas Analysis and Sybil Bloat (GAS)
*Quantifies permanent DoS feasibility. Independent of ACCT, runs in parallel.*

- [x] **GAS-01**: `advanceGame()` complete call graph: worst-case gas measured for every code path branch via Foundry `--gas-report` adversarial harnesses
- [x] **GAS-02**: `processTicketBatch` gas ceiling: maximum cold SSTORE cost confirmed against 16M block limit
- [x] **GAS-03**: Sybil breakeven: minimum wallet count N where `advanceGame()` exceeds 16M gas derived
- [x] **GAS-04**: Sybil DoS cost: ETH required to reach N wallets computed and compared against 1000 ETH threat model budget
- [x] **GAS-05**: `payDailyJackpot` winner loop ceiling: `DAILY_ETH_MAX_WINNERS` constant read and worst-case gas measured
- [x] **GAS-06**: VRF callback gas measured under worst-case lootbox state: confirmed under 200K with margin
- [x] **GAS-07**: Rational inaction liveness: dominant whale's dominant strategy analyzed — delaying `advanceGame()` cannot produce better outcomes than advancing; protocol liveness guarantee assessed

### Admin Power and VRF Griefing (ADMIN)
*wireVrf is the central connecting vector for both admin abuse and VRF griefing.*

- [x] **ADMIN-01**: Complete admin function inventory: every privilege mapped with worst-case compromise consequence if admin key is lost or malicious
- [x] **ADMIN-02**: `wireVrf` coordinator substitution analysis: admin RNG control path via emergency coordinator rotation confirmed or refuted
- [x] **ADMIN-03**: 3-day emergency stall trigger: all conditions under which admin can deliberately force the stall confirmed; attacker sequence enumerated
- [x] **ADMIN-04**: VRF retry window analysis: all state-changing calls permissible during 18h RNG lock period identified; any that produce advantaged outcomes flagged
- [x] **ADMIN-05**: VRF subscription drain economics: LINK cost to halt game computed; griefing feasibility assessed against threat model
- [x] **ADMIN-06**: Player-specific grief vectors: any admin path to selectively block a specific wallet's advancement, lootbox resolution, or withdrawal identified

### Assembly Safety (ASSY)
*Raw storage writes bypass Solidity overflow checks and type safety.*

- [x] **ASSY-01**: JackpotModule assembly SSTORE slot calculation: `elem = levelSlot + traitId` verified to match actual Solidity storage declaration for `traitBurnTicket` — mismatch would cause storage corruption (potential CRITICAL)
- [x] **ASSY-02**: MintModule assembly SSTORE slot calculation: same verification for the parallel batch-write pattern
- [x] **ASSY-03**: All other assembly blocks (AdvanceModule, DecimatorModule, DegeneretteModule, DegenerusGame, DegenerusJackpots): error propagation, return data handling, and memory bounds verified

### Token Security and Economic Attacks (TOKEN)
*Requires admin map from ADMIN — vaultMintAllowance authorization model depends on it.*

- [ ] **TOKEN-01**: `vaultMintAllowance` bypass verdict: no path to unbounded COIN minting confirmed
- [ ] **TOKEN-02**: `claimWhalePass` double-mint check: no replay or re-entry minting path confirmed
- [ ] **TOKEN-03**: BurnieCoinflip entropy source: VRF vs. block-level data determined — HIGH if block-level data found
- [x] **TOKEN-04**: Whale + lootbox combined EV model: no ticket-level combination produces EV > 1.0 for any player at any activity score
- [x] **TOKEN-05**: Activity score inflation cost: minimum ETH required to extract maximum EV benefit bounded against cost; no positive-return inflation path
- [x] **TOKEN-06**: BURNIE 30-day guard completeness: all purchase paths (operator-proxied, whale bundle, lazy pass, deity pass) confirmed to apply the guard with identical timestamp comparison
- [x] **TOKEN-07**: Affiliate economic exploits: self-referral, wash trading, and circular referral ring EV modeled and bounded
- [x] **TOKEN-08**: DGNRS `lockForLevel`/`unlock` cap reset: users cannot repeatedly lock/unlock to reset per-level ETH/BURNIE spending caps and extract double EV via level transition timing

### Vault and Stonk Economics (VAULT)
*DegenerusVault and DegenerusStonk share the `(reserve * burned) / supply` redemption formula.*

- [x] **VAULT-01**: DegenerusVault ETH donation via `receive()`: direct ETH send to vault cannot manipulate the share redemption formula to benefit one shareholder class at the expense of another
- [x] **VAULT-02**: DegenerusStonk burn-to-claim formula: `claimAmount = (reserveBalance * sharesBurned) / totalSupply` rounding direction verified; no path for disproportionate extraction via partial burns or supply manipulation

### Timestamp and Timing Attacks (TIME)
*Validators can shift `block.timestamp` by ±900s on mainnet.*

- [ ] **TIME-01**: Daily boundary validator manipulation: ±900s drift cannot allow a player to trigger two daily jackpot allocations in one real day or skip another player's daily window
- [ ] **TIME-02**: Quest streak griefing: a validator cannot selectively delay another player's streak-claiming transaction past the day boundary to break their streak

### Cross-Function Reentrancy and Unchecked Blocks (REENT)
*Integration pass — must follow ACCT, ADMIN, TOKEN, VAULT. Synthesizes all ETH-touching call sites.*

- [ ] **REENT-01**: Cross-function reentrancy matrix: all ETH transfer sites mapped with every reentrant call path enumerated
- [ ] **REENT-02**: ERC721 `onERC721Received` callback reentrancy: all `safeMint` paths in DegenerusNFT formally verified — most commonly missed finding class in C4 game audits
- [ ] **REENT-03**: Delegatecall multicall/operator-proxy reentrancy: no re-entry through operator delegation chain confirmed
- [ ] **REENT-04**: 40 JackpotModule unchecked blocks audited with adversarial state sequences; recent fix commits (4592d8c, cbbafa0, 9539c6d) tested for bypass across all purchase paths
- [ ] **REENT-05**: Shared cursor corruption: `ticketCursor`/`ticketLevel` mutual exclusion formally verified between `processTicketBatch` and `processFutureTicketBatch`
- [ ] **REENT-06**: DecimatorModule `claimDecimatorJackpot` CEI: ETH transfer vs. state update ordering confirmed safe
- [ ] **REENT-07**: `adminSwapEthForStEth` accounting integrity: admin ETH↔stETH swap preserves pool accounting invariant; no extraction path via the swap

### Final Report (REPORT)
- [ ] **REPORT-01**: Final prioritized findings report delivered with CRITICAL / HIGH / MEDIUM / LOW / Gas / QA sections and Code4rena severity methodology applied throughout
- [ ] **REPORT-02**: Coded PoC (pseudocode or tx sequence) provided for every HIGH and MEDIUM finding
- [ ] **REPORT-03**: Gas report: `advanceGame()` worst-case gas by code path with the specific adversarial state that triggers each maximum

## Future Requirements (v3.0)

- Formal verification (Halmos full FSM) — path explosion makes this infeasible in bounded time
- Coverage-guided fuzzing campaign (Medusa) — after v2.0 confirms attack surface scope
- Full Aderyn run — requires Rust 1.89+, deferred until toolchain upgrade

## Out of Scope

| Feature | Reason |
|---------|--------|
| Gas optimization recommendations | Separate scoring track at Code4rena; explicitly not security |
| Frontend / off-chain code | Contracts only |
| Testnet-specific contracts | TESTNET_ETH_DIVISOR makes findings non-transferable to mainnet |
| Mock contracts | Test infrastructure only |
| Deployment scripts | Operational, not security surface |
| Creator vault drain | CREATOR holds initial 1T shares intentionally — this is the fee mechanism by design |
| Re-running v1.0 completed checks | Storage layout, VRF lifecycle 8-point checklist, FSM transitions, per-module reentrancy — all confirmed complete |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| ACCT-01 | Phase 8 | Pending |
| ACCT-02 | Phase 8 | Pending |
| ACCT-03 | Phase 8 | Pending |
| ACCT-04 | Phase 8 | Pending |
| ACCT-05 | Phase 8 | Pending |
| ACCT-06 | Phase 8 | Pending |
| ACCT-07 | Phase 8 | Pending |
| ACCT-08 | Phase 8 | Pending |
| ACCT-09 | Phase 8 | Pending |
| ACCT-10 | Phase 8 | Pending |
| GAS-01 | Phase 9 | Complete |
| GAS-02 | Phase 9 | Complete |
| GAS-03 | Phase 9 | Complete |
| GAS-04 | Phase 9 | Complete |
| GAS-05 | Phase 9 | Complete |
| GAS-06 | Phase 9 | Complete |
| GAS-07 | Phase 9 | Complete |
| ADMIN-01 | Phase 10 | Complete |
| ADMIN-02 | Phase 10 | Complete |
| ADMIN-03 | Phase 10 | Complete |
| ADMIN-04 | Phase 10 | Complete |
| ADMIN-05 | Phase 10 | Complete |
| ADMIN-06 | Phase 10 | Complete |
| ASSY-01 | Phase 10 | Complete |
| ASSY-02 | Phase 10 | Complete |
| ASSY-03 | Phase 10 | Complete |
| TOKEN-01 | Phase 11 | Pending |
| TOKEN-02 | Phase 11 | Pending |
| TOKEN-03 | Phase 11 | Pending |
| TOKEN-04 | Phase 11 | Complete |
| TOKEN-05 | Phase 11 | Complete |
| TOKEN-06 | Phase 11 | Complete |
| TOKEN-07 | Phase 11 | Complete |
| TOKEN-08 | Phase 11 | Complete |
| VAULT-01 | Phase 11 | Complete |
| VAULT-02 | Phase 11 | Complete |
| TIME-01 | Phase 11 | Pending |
| TIME-02 | Phase 11 | Pending |
| REENT-01 | Phase 12 | Pending |
| REENT-02 | Phase 12 | Pending |
| REENT-03 | Phase 12 | Pending |
| REENT-04 | Phase 12 | Pending |
| REENT-05 | Phase 12 | Pending |
| REENT-06 | Phase 12 | Pending |
| REENT-07 | Phase 12 | Pending |
| REPORT-01 | Phase 13 | Pending |
| REPORT-02 | Phase 13 | Pending |
| REPORT-03 | Phase 13 | Pending |

**Coverage:**
- v2.0 requirements: 48 total
- Mapped to phases: 48
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-04*
*Last updated: 2026-03-04 after roadmap creation (Phases 8–13)*
