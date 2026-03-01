# Roadmap: Degenerus Protocol Security Audit

## Overview

This audit progresses from the foundational storage layer outward through the core state machine, individual game modules, accounting integrity, economic attack surface, access control, and finally cross-contract synthesis. Each phase gates the next: storage layout must be verified before any module is trusted, VRF semantics must be understood before module safety can be assessed, and accounting invariants must be confirmed before economic modeling is meaningful. The deliverable is a prioritized findings report across all 22 mainnet contracts and 10 delegatecall modules.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (3a, 3b, 3c): Sub-phases within Phase 3 for comprehensive module coverage

- [ ] **Phase 1: Storage Foundation Verification** - Verify slot layout consistency across all 10 delegatecall modules and confirm ContractAddresses constants
- [ ] **Phase 2: Core State Machine and VRF Lifecycle** - Audit the FSM, VRF request/fulfill/retry cycle, and RNG lock semantics end-to-end
- [ ] **Phase 3a: Core ETH Flow Modules** - Audit MintModule, JackpotModule, and EndgameModule — the three modules with the highest ETH value at risk
- [ ] **Phase 3b: VRF-Dependent Modules** - Audit LootboxModule and GameOverModule — the two modules where VRF word derivation and terminal settlement create the highest complexity
- [ ] **Phase 3c: Supporting Mechanics Modules** - Audit WhaleModule, BoonModule, DecimatorModule, DegeneretteModule, and MintStreakUtils
- [ ] **Phase 4: ETH and Token Accounting Integrity** - Verify the core accounting invariant holds across all call paths including stETH rebasing, fee splits, and game-over settlement
- [ ] **Phase 5: Economic Attack Surface** - Model Sybil, MEV, whale bundle, affiliate, and activity score extraction vectors
- [ ] **Phase 6: Access Control and Privilege Model** - Enumerate all privileged entry points, operator approval abuse, and VRF subscription management
- [ ] **Phase 7: Cross-Contract Integration Synthesis** - Integrating pass across all phase findings — reentrancy, callback safety, constructor ordering, composite findings

## Phase Details

### Phase 1: Storage Foundation Verification
**Goal**: Confirmed storage slot layout map for all 10 delegatecall modules with no collision risk and no testnet configuration bleed
**Depends on**: Nothing (first phase)
**Requirements**: STOR-01, STOR-02, STOR-03, STOR-04
**Success Criteria** (what must be TRUE):
  1. A slot-by-slot comparison table exists for all 10 modules versus DegenerusGame storage layout, produced by `forge inspect`, with any divergence explicitly documented
  2. No module contract is found to declare instance-level storage variables outside of DegenerusGameStorage inheritance
  3. ContractAddresses compile-time constants are mapped to their expected mainnet addresses — no address(0) found in the deployed bytecode constant slots
  4. A search for `TESTNET_ETH_DIVISOR` across all mainnet-scoped contracts confirms no conditional path routes through testnet logic at runtime
**Plans**: TBD

Plans:
- [ ] 01-01: Run `forge inspect` on all 10 modules and DegenerusGame; produce slot comparison table
- [ ] 01-02: Grep all module contracts for instance variable declarations; confirm clean inheritance from DegenerusGameStorage
- [ ] 01-03: Trace ContractAddresses constants through build pipeline; verify no address(0) in deployed artifacts
- [ ] 01-04: Search for TESTNET_ETH_DIVISOR usage across all mainnet contract files; confirm scope isolation

### Phase 2: Core State Machine and VRF Lifecycle
**Goal**: Complete understanding of all FSM transitions and VRF lifecycle states with no exploitable windows identified or all identified windows documented as findings
**Depends on**: Phase 1
**Requirements**: RNG-01, RNG-02, RNG-03, RNG-04, RNG-05, RNG-06, RNG-07, RNG-08, RNG-09, RNG-10, FSM-01, FSM-02, FSM-03
**Success Criteria** (what must be TRUE):
  1. The `rngLockedFlag` state transitions are traced through every path from VRF request to word consumption in `advanceGame` — the nudge window is either confirmed closed or documented as a critical finding with a concrete exploit scenario
  2. `rawFulfillRandomWords` gas cost is measured at worst-case lootbox state and documented; the result is either "safe under 200k gas" or a severity-rated finding
  3. All `requestId` matching paths are traced; any scenario where a stale or mismatched ID could apply the wrong VRF word to wrong game state is documented
  4. The complete FSM transition graph (PURCHASE to JACKPOT to gameOver) is enumerated with all legal transitions confirmed and all illegal transitions confirmed unreachable
  5. All stuck-state recovery paths (18h timeout, 3-day emergency, 30-day sweep) are confirmed reachable and not prematurely triggerable
**Plans:** 6 plans

Plans:
- [ ] 02-01-PLAN.md — Trace `rngLockedFlag` state machine through all paths; map every set/clear site; evaluate nudge window timing
- [ ] 02-02-PLAN.md — Measure `rawFulfillRandomWords` gas cost at worst-case state; compare against 300k VRF_CALLBACK_GAS_LIMIT
- [ ] 02-03-PLAN.md — Apply Chainlink VRF V2.5 8-point security checklist; document pass/fail for each point including requestId handling and concurrent request safety
- [ ] 02-04-PLAN.md — Map complete FSM transition graph for PURCHASE/JACKPOT/gameOver; enumerate all guard conditions
- [ ] 02-05-PLAN.md — Trace all stuck-state recovery paths; verify timeout preconditions and premature-trigger resistance
- [ ] 02-06-PLAN.md — Review EntropyLib.entropyStep() XOR-shift derivation; verify no exploitable bias; confirm no block.timestamp/blockhash randomness sources

### Phase 3a: Core ETH Flow Modules
**Goal**: MintModule, JackpotModule, and EndgameModule are audited for correct ETH inflow/outflow handling, price formula integrity, and input validation
**Depends on**: Phase 2
**Requirements**: MATH-01, MATH-02, MATH-03, MATH-04, INPT-01, INPT-02, INPT-03, INPT-04, DOS-01
**Success Criteria** (what must be TRUE):
  1. Ticket price escalation formula (PriceLookupLib) is confirmed monotonically increasing with no overflow at maximum level — or a finding documents the specific level at which overflow occurs
  2. Deity pass T(n) = n*(n+1)/2 + 24 ETH pricing is verified non-overflowing at n=100 and n=1000 with arithmetic shown
  3. Ticket quantity bounds, lootbox amount limits, and MintPaymentKind enum bounds are confirmed enforced or documented as bypass paths
  4. A Slither + Aderyn scan of all three modules is completed with every HIGH/MEDIUM finding triaged (confirmed, false positive, or new finding)
  5. No unbounded iteration is found in MintModule, JackpotModule, or EndgameModule that could exhaust the block gas limit
**Plans:** 6/7 plans executed

Plans:
- [ ] 03a-01-PLAN.md — Audit MintModule: ETH inflow paths, purchase cost formula, BPS splits, payment kind routing
- [ ] 03a-02-PLAN.md — Audit JackpotModule: ETH outflow paths, prize pool credit, 90/10 split, loop bounds
- [ ] 03a-03-PLAN.md — Audit EndgameModule: level transition guards, phase boundary conditions, state mutation safety
- [ ] 03a-04-PLAN.md — Verify PriceLookupLib ticket escalation (saw-tooth monotonicity, overflow) and lazy pass summation
- [ ] 03a-05-PLAN.md — Verify deity pass T(n) triangular formula at n=100 and n=1000; verify k bound
- [ ] 03a-06-PLAN.md — Input validation sweep across all three modules: quantity bounds, enum bounds, zero-address guards
- [ ] 03a-07-PLAN.md — Run Slither on modules; triage all HIGH/MEDIUM detections; attempt Aderyn

### Phase 3b: VRF-Dependent Modules
**Goal**: LootboxModule and GameOverModule are audited for correct VRF word usage, lootbox EV formula integrity, and terminal settlement correctness
**Depends on**: Phase 2
**Requirements**: MATH-05, MATH-06, DOS-02, DOS-03
**Success Criteria** (what must be TRUE):
  1. The lootbox EV multiplier formula is traced from activity score input to final payout; any path that creates guaranteed positive-EV extraction is documented as a finding with numeric example
  2. Degenerette bet resolution timing relative to VRF fulfillment is verified — no bet placed before VRF request can have foreknowledge of outcome
  3. The daily ETH distribution bucket cursor is confirmed resistant to griefing — no sequence of calls can advance the cursor past unfilled buckets
  4. Trait burn ticket iteration in GameOverModule is confirmed bounded — an explicit maximum trait count is enforced preventing gas exhaustion at phase transitions
**Plans:** 6 plans

Plans:
- [ ] 03b-01-PLAN.md — Audit LootboxModule — VRF word derivation path, activity score EV multiplier formula, payout calculation
- [ ] 03b-02-PLAN.md — Audit GameOverModule — terminal settlement logic, fund distribution sequence, all-paths coverage
- [ ] 03b-03-PLAN.md — Model lootbox EV multiplier mathematically; verify activity score cannot produce guaranteed positive EV
- [ ] 03b-04-PLAN.md — Audit degenerette bet resolution relative to VRF timing; verify no pre-VRF bet can exploit known outcomes
- [ ] 03b-05-PLAN.md — Verify daily ETH distribution bucket cursor logic; test griefing resistance
- [ ] 03b-06-PLAN.md — Confirm trait burn iteration bound; verify gas ceiling at maximum realistic trait count

### Phase 3c: Supporting Mechanics Modules
**Goal**: WhaleModule, BoonModule, DecimatorModule, DegeneretteModule, and MintStreakUtils are audited for pricing correctness, bit packing integrity, and behavioral safety
**Depends on**: Phase 2
**Requirements**: MATH-07, MATH-08
**Success Criteria** (what must be TRUE):
  1. Whale bundle pricing (2.4 ETH levels 0-3, 4 ETH x49/x99) is confirmed enforced on every purchase path — no bypass or underpricing path exists
  2. Lazy pass pricing (sum-of-10-level-prices at level 3+) correctly accumulates the price curve — verified arithmetically with specific level examples
  3. BurnieCoinflip 50-150% bonus range is confirmed correctly bounded — edge cases at exactly 50% and 150% are tested and pay correctly
  4. BitPackingLib 24-bit field operations are confirmed correct — no field overflow or cross-field bleed identified in any packing/unpacking path
**Plans**: 6 plans

Plans:
- [ ] 03c-01: Audit WhaleModule — bundle and lazy pass pricing enforcement across all purchase paths
- [ ] 03c-02: Verify whale bundle and lazy pass pricing formulas arithmetically; trace all conditional pricing branches
- [ ] 03c-03: Audit BoonModule and DecimatorModule — boon issuance guards, decimator mechanics
- [ ] 03c-04: Audit DegeneretteModule and MintStreakUtils — streak accounting, quest bonus computation
- [ ] 03c-05: Audit BurnieCoinflip bonus range — edge cases at 50% and 150% boundaries
- [ ] 03c-06: Audit BitPackingLib — 24-bit field packing/unpacking correctness, overflow guards, field bleed

### Phase 4: ETH and Token Accounting Integrity
**Goal**: The core accounting invariant (`address(this).balance + stETH.balanceOf(this) >= claimablePool`) is confirmed to hold after every possible transaction, or violations are documented as findings
**Depends on**: Phase 3a, Phase 3b, Phase 3c
**Requirements**: ACCT-01, ACCT-02, ACCT-03, ACCT-04, ACCT-05, ACCT-06, ACCT-07, ACCT-08, ACCT-09, ACCT-10
**Success Criteria** (what must be TRUE):
  1. A systematic manual trace of all 16 claimablePool mutation sites confirms `balance + stETH >= claimablePool` holds across all mapped inflow/outflow paths — or violations found are documented as critical findings
  2. All BPS fee splits (90/10 pool, affiliate BPS, any other split) are confirmed to sum to their input amount — any rounding accumulation gap is quantified (in wei) and rated by severity
  3. `claimWinnings()` is confirmed non-reenterable — CEI pattern confirmed safe with exhaustive reachability analysis of all functions callable from ETH callback
  4. No code path is found that caches `steth.balanceOf(this)` in a state variable — stETH rebasing behavior is documented as handled correctly or a finding is raised
  5. Game-over settlement terminal distribution is confirmed to reach a zero-balance state with no funds permanently locked
**Plans:** 9 plans

Plans:
- [ ] 04-01-PLAN.md — Trace all ETH inflow/outflow paths across all contracts; verify pool attribution matches msg.value/payout exactly
- [ ] 04-02-PLAN.md — Systematic manual trace of all 16 claimablePool mutation sites for invariant symmetry and ETH backing
- [ ] 04-03-PLAN.md — Audit all BPS fee splits across all modules; verify sum-to-input with remainder pattern analysis
- [ ] 04-04-PLAN.md — Audit claimWinnings() for reentrancy; exhaustive CEI analysis with no reentrancy guard present
- [ ] 04-05-PLAN.md — Search for cached stETH balance; document stETH rebasing impact (pre-confirmed PASS, formal documentation)
- [ ] 04-06-PLAN.md — Trace game-over settlement to zero terminal balance; verify handleGameOverDrain and handleFinalSweep
- [ ] 04-07-PLAN.md — Audit stall recovery paths accounting impact; verify timeout arithmetic and premature-trigger resistance
- [ ] 04-08-PLAN.md — Audit DegenerusVault share-based redemption formulas and stETH yield accrual
- [ ] 04-09-PLAN.md — Audit BurnieCoin supply invariant; trace all mint/burn paths through packed Supply struct

### Phase 5: Economic Attack Surface
**Goal**: All identified economic attack vectors (Sybil, MEV/block proposer, whale, affiliate) are modeled and assessed — either confirmed non-exploitable with reasoning, or documented as findings with quantified impact
**Depends on**: Phase 4
**Requirements**: ECON-01, ECON-02, ECON-03, ECON-04, ECON-05, ECON-06, ECON-07
**Success Criteria** (what must be TRUE):
  1. A mathematical model of Sybil majority ticket ownership EV exists — the model either proves group EV is negative or documents the specific conditions under which it turns positive
  2. Activity score inflation vectors (quest streaks, affiliate self-referral, coordinated chains) are enumerated — cost-to-inflate versus EV-unlocked ratio is computed for each vector
  3. MEV/block proposer attack surface on ticket purchase price escalation at phase boundaries is analyzed — any profitable sandwich or reorder strategy is documented with specific transaction sequences
  4. Whale bundle plus lootbox purchase EV at levels 0-3 is computed — any combination that extracts more than deposited is documented as a finding
  5. AfKing mode transition windows are confirmed free from double-spend or double-credit opportunities
**Plans:** 7 plans

Plans:
- [ ] 05-01-PLAN.md — Build Sybil EV model: prize pool mechanics, group ticket fraction, expected payout vs deposit
- [ ] 05-02-PLAN.md — Enumerate activity score inflation vectors; compute cost-per-EV-unit for quest streaks and affiliate self-referral
- [ ] 05-03-PLAN.md — Model affiliate referral extraction: circular structures, referrer+referee combined EV vs deposited (BURNIE denomination)
- [ ] 05-04-PLAN.md — Analyze MEV attack surface on phase boundaries: sandwich attacks on ticket purchase escalation
- [x] 05-05-PLAN.md — Model block proposer advanceGame timing manipulation: level transition control and outcome influence
- [ ] 05-06-PLAN.md — Quantify whale bundle economic impact at arbitrary levels (Phase 3c F01 HIGH finding)
- [ ] 05-07-PLAN.md — Audit AfKing mode transitions: verify no double-spend or double-credit window exists

### Phase 6: Access Control and Privilege Model
**Goal**: Complete authorization matrix for all 22 contracts produced with all privileged entry points confirmed correctly gated and no escalation paths identified
**Depends on**: Phase 4, Phase 5
**Requirements**: AUTH-01, AUTH-02, AUTH-03, AUTH-04, AUTH-05, AUTH-06
**Success Criteria** (what must be TRUE):
  1. Slither `vars-and-auth` printer output exists for all 22 contracts and all HIGH/MEDIUM findings are triaged — any ungated admin function is rated and documented
  2. `rawFulfillRandomWords` caller validation is confirmed restricted to the VRF coordinator address — the check is present and cannot be bypassed
  3. All delegatecall module entry points are confirmed unreachable via direct external calls — only accessible through DegenerusGame's delegatecall dispatch
  4. Every `_resolvePlayer()` call site is audited — value flows to `player` not `msg.sender` in all cases, or the exception is documented
  5. `operatorApprovals` delegation is confirmed non-escalating — operator cannot exceed player permissions, revocation takes immediate effect
**Plans**: TBD

Plans:
- [ ] 06-01: Run Slither `vars-and-auth` printer on all 22 contracts; triage all findings against expected privilege model
- [ ] 06-02: Audit all `msg.sender == CREATOR` guards — enumerate every admin-only function; verify no bypass exists
- [ ] 06-03: Confirm `rawFulfillRandomWords` VRF coordinator check — trace caller validation in DegenerusGame and AdvanceModule
- [ ] 06-04: Audit module entry point accessibility — verify all 10 modules are unreachable via direct external calls
- [ ] 06-05: Audit all `_resolvePlayer()` call sites — confirm value routing to `player`; document any `msg.sender` routing
- [ ] 06-06: Audit `operatorApprovals` delegation — non-escalation guarantee, immediate revocation effectiveness
- [ ] 06-07: Audit DegenerusAdmin VRF subscription management — external caller griefing resistance

### Phase 7: Cross-Contract Integration Synthesis
**Goal**: All cross-contract interaction paths are confirmed safe or documented as findings, and all findings from prior phases are synthesized into a prioritized report
**Depends on**: Phase 6
**Requirements**: XCON-01, XCON-02, XCON-03, XCON-04, XCON-05, XCON-06, XCON-07
**Success Criteria** (what must be TRUE):
  1. All delegatecall return values are confirmed checked — any unchecked delegatecall return is a documented finding with exploitability assessment
  2. stETH.submit(), stETH.transfer(), and LINK.transferAndCall() return values are confirmed checked at every call site — any unchecked return is documented
  3. Cross-function reentrancy via ETH callback from `claimWinnings` is traced — confirmed it cannot reenter `purchase` or other state-changing functions
  4. Constructor-time cross-contract call ordering is confirmed correct relative to the documented deploy sequence — no constructor references a contract not yet deployed at that nonce offset
  5. A final findings report exists with all findings severity-rated (Critical/High/Medium/Low/Informational) and with remediation guidance for each finding
**Plans**: TBD

Plans:
- [ ] 07-01: Audit all delegatecall sites in DegenerusGame — confirm return value checking on all 10 module dispatches
- [ ] 07-02: Audit stETH.submit(), stETH.transfer() call sites — return value checking; Lido callback reentrancy safety
- [ ] 07-03: Audit LINK.transferAndCall() and BurnieCoin.burnCoin() call sites — return value checking and reentrancy
- [ ] 07-04: Trace cross-function reentrancy from `claimWinnings` ETH callback — test reentry into purchase, advanceGame, and other state-changing functions
- [ ] 07-05: Audit constructor-time cross-contract calls against the deploy sequence nonce offsets
- [ ] 07-06: Synthesize all phase findings — deduplicate, rate severity, write remediation guidance; produce final prioritized findings report

## Progress

**Execution Order:**
Phases execute in order: 1 -> 2 -> 3a -> 3b -> 3c -> 4 -> 5 -> 6 -> 7
Note: Phase 3a, 3b, and 3c all depend on Phase 2 and can be partially parallelized.

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Storage Foundation Verification | 4/4 | Complete | 2026-02-28 |
| 2. Core State Machine and VRF Lifecycle | 6/6 | Complete | 2026-03-01 |
| 3a. Core ETH Flow Modules | 0/7 | Planned | - |
| 3b. VRF-Dependent Modules | 6/6 | Complete | 2026-03-01 |
| 3c. Supporting Mechanics Modules | 6/6 | Complete | 2026-03-01 |
| 4. ETH and Token Accounting Integrity | 0/9 | Planned | - |
| 5. Economic Attack Surface | 0/7 | Planned | - |
| 6. Access Control and Privilege Model | 0/7 | Not started | - |
| 7. Cross-Contract Integration Synthesis | 0/6 | Not started | - |
