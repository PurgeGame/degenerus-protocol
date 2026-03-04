# Roadmap: Degenerus Protocol Security Audit

## Milestones

- ✅ **v1.0 Audit** — Phases 1–7 (shipped 2026-03-04, 74% complete by plan count)
- 🚧 **v2.0 Adversarial Audit** — Phases 8–13 (in progress)

## Phases

<details>
<summary>✅ v1.0 Audit (Phases 1–7) — SHIPPED 2026-03-04</summary>

- [x] Phase 1: Storage Foundation Verification (4/4 plans) — completed 2026-02-28
- [x] Phase 2: Core State Machine and VRF Lifecycle (6/6 plans) — completed 2026-03-01
- [x] Phase 3a: Core ETH Flow Modules (7/7 plans) — completed 2026-03-01
- [x] Phase 3b: VRF-Dependent Modules (6/6 plans) — completed 2026-03-01
- [x] Phase 3c: Supporting Mechanics Modules (6/6 plans) — completed 2026-03-01
- [~] Phase 4: ETH and Token Accounting Integrity (1/9 plans) — INCOMPLETE (accepted gap)
- [x] Phase 5: Economic Attack Surface (7/7 plans) — completed 2026-03-04
- [x] Phase 6: Access Control and Privilege Model (7/7 plans) — completed 2026-03-04
- [x] Phase 7: Cross-Contract Integration Synthesis (5/5 plans) — completed 2026-03-04 (07-04 + 07-05 backfilled in v2.0)

**Known Gaps:** Phase 4 ETH accounting invariant (closed by Phase 8 in v2.0)

See: `.planning/milestones/v1.0-ROADMAP.md` for full phase details and findings.

</details>

### v2.0 Adversarial Audit (In Progress)

**Milestone Goal:** Exhaustive adversarial security audit of all Degenerus Protocol contracts for Code4rena contest preparation — close Phase 4 and Phase 7 gaps, model new attack surfaces, and deliver a prioritized findings report.

**Note on parallel execution:** Phases 8 and 9 are independent work streams. Phase 8 covers ETH accounting paths; Phase 9 covers gas paths. They share no dependencies and can run concurrently. All phases preceding Phase 12 must complete before the reentrancy synthesis pass begins.

- [x] **Phase 8: ETH Accounting Invariant and CEI Verification** - Verify ETH solvency invariant, _creditClaimable call site audit, BPS rounding, and all ETH-transfer CEI patterns — completed 2026-03-04
- [x] **Phase 9: advanceGame() Gas Analysis and Sybil Bloat** - Measure worst-case gas by code path and derive Sybil breakeven under the 16M block limit (completed 2026-03-04)
- [x] **Phase 10: Admin Power, VRF Griefing, and Assembly Safety** - Map all admin rug vectors, enumerate VRF griefing paths, and verify assembly slot calculations (completed 2026-03-04)
- [x] **Phase 11: Token Security, Economic Attacks, Vault and Timing** - Confirm mint authorization, EV model correctness, BURNIE guard completeness, vault formulas, and timestamp tolerance (completed 2026-03-04)
- [ ] **Phase 12: Cross-Function Reentrancy Synthesis and Unchecked Blocks** - Integrate all ETH-touching call sites into a reentrancy matrix and audit all JackpotModule unchecked blocks
- [ ] **Phase 13: Final Synthesis Report** - Deliver Code4rena-format findings report with coded PoC for every HIGH and MEDIUM finding

## Phase Details

### Phase 8: ETH Accounting Invariant and CEI Verification
**Goal**: The ETH solvency invariant is confirmed true (or a specific violation is identified and severity-rated) for every reachable game state; every ETH-transfer call site follows CEI order
**Depends on**: Nothing (parallel with Phase 9; v1.0 Phase 4 gap closed here)
**Requirements**: ACCT-01, ACCT-02, ACCT-03, ACCT-04, ACCT-05, ACCT-06, ACCT-07, ACCT-08, ACCT-09, ACCT-10
**Success Criteria** (what must be TRUE):
  1. ACCT-01 verdict confirmed: `sum(deposits) == prizePool + futurePool + claimablePool + fees` holds across all tested game states, or a specific state sequence that breaks it is documented with ETH amounts
  2. ACCT-02 verdict confirmed: every call site of `_creditClaimable` either has `claimablePool +=` in the same code path (PASS) or is identified as a missing increment with exact function name and line (HIGH finding candidate)
  3. ACCT-03 verdict confirmed: all BPS fee splits verified to sum to input value with rounding remainder explicitly directed — no rounding path that silently loses ETH or directs it to wrong pool
  4. ACCT-04 and ACCT-05 verdict confirmed: `claimWinnings()` cross-function reentrancy path via `purchase()` callback and Lido/LINK callback paths formally traced — either safe or specific re-entry scenario documented
  5. ACCT-06 through ACCT-10 verdict confirmed: Vault share rounding direction safe, BurnieCoin supply invariant holds, game-over zero-balance proof complete, admin stake guard present or MEDIUM finding raised, receive() donation cannot trigger game-state transitions
**Plans**: 5 plans

Plans:
- [x] 08-01-PLAN.md — ACCT-02: _creditClaimable 11-call-site audit across 5 modules — PASS
- [x] 08-02-PLAN.md — ACCT-04 + ACCT-05: CEI reentrancy tracing (claimWinnings, LINK onTokenTransfer, stETH) — PASS, PASS+INFO+LOW
- [x] 08-03-PLAN.md — ACCT-06 + ACCT-07: DegenerusVault share rounding + BurnieCoin supply invariant — PASS, PASS
- [x] 08-04-PLAN.md — ACCT-01 + ACCT-08: Hardhat invariant helper + 7-state-sequence test + game-over proof — PASS, PASS
- [x] 08-05-PLAN.md — ACCT-03 + ACCT-09 + ACCT-10: BPS fee splits, stake guard, receive() donation safety — PASS, PASS, PASS+INFO

### Phase 9: advanceGame() Gas Analysis and Sybil Bloat
**Goal**: The worst-case gas for every `advanceGame()` code path is measured against the 16M block limit, and the ETH cost required to create a Sybil set large enough to trigger permanent DoS is computed against the 1000 ETH threat model
**Depends on**: Nothing (parallel with Phase 8)
**Requirements**: GAS-01, GAS-02, GAS-03, GAS-04, GAS-05, GAS-06, GAS-07
**Success Criteria** (what must be TRUE):
  1. GAS-01 verdict confirmed: complete `advanceGame()` call graph gas measured for every branch via Hardhat gas harnesses — the specific code path and adversarial state that produces maximum gas is named with measured value in gas units
  2. GAS-03 breakeven N documented: minimum wallet count N where `advanceGame()` exceeds 16M gas derived from measured per-wallet cold SSTORE cost — N stated as an integer with supporting calculation
  3. GAS-04 Sybil DoS cost confirmed: ETH required to reach N wallets computed (minimum ticket cost × N) and compared against 1000 ETH threat model — verdict is either "economically feasible (MEDIUM/HIGH)" or "exceeds budget (LOW)"
  4. GAS-06 VRF callback ceiling confirmed: callback gas measured under worst-case lootbox pending state and confirmed below 200K with explicit headroom margin, or flagged as overflow risk
  5. GAS-07 rational inaction verdict delivered: dominant whale's expected-value calculation for delaying vs. advancing `advanceGame()` modeled — protocol liveness guarantee either confirmed or specific dominant strategy that harms liveness identified
**Plans**: 4 plans

Plans:
- [x] 09-01-PLAN.md — GAS-01: advanceGame() complete call graph gas measurement (all 13+ stages)
- [ ] 09-02-PLAN.md — GAS-02 + GAS-03 + GAS-04: Sybil Bloat ticket batch analysis and DoS economics
- [ ] 09-03-PLAN.md — GAS-05 + GAS-06: payDailyJackpot ceiling + VRF callback gas measurement
- [ ] 09-04-PLAN.md — GAS-07: Rational inaction liveness analysis

### Phase 10: Admin Power, VRF Griefing, and Assembly Safety
**Goal**: Every admin privilege is mapped with its worst-case consequence, VRF griefing vectors through `wireVrf` and the retry window are fully enumerated, and all assembly SSTORE slot calculations are verified against the Solidity storage layout
**Depends on**: Phase 8 (admin staking solvency consequence requires accounting model from Phase 8 to classify correctly)
**Requirements**: ADMIN-01, ADMIN-02, ADMIN-03, ADMIN-04, ADMIN-05, ADMIN-06, ASSY-01, ASSY-02, ASSY-03
**Success Criteria** (what must be TRUE):
  1. ADMIN-01 complete power map delivered: every admin function listed with specific worst-case consequence if key is lost or malicious — no admin function is unclassified
  2. ASSY-01 verdict confirmed: JackpotModule assembly SSTORE slot calculation `elem = levelSlot + traitId` verified to match actual Solidity storage declaration for `traitBurnTicket` — match is PASS; mismatch produces a named corrupted slot with consequence severity
  3. ASSY-02 verdict confirmed: MintModule assembly SSTORE slot calculation verified with same method — match is PASS; mismatch produces a named corrupted slot with consequence severity
  4. ADMIN-02 verdict confirmed: `wireVrf` coordinator substitution path either allows admin to substitute an attacker-controlled coordinator that returns manipulated randomness (finding) or the authorization chain prevents this (PASS with reasoning)
  5. ADMIN-03 through ADMIN-06 verdicts confirmed: 3-day stall trigger conditions enumerated, retry window state-changing calls identified, LINK drain economics computed, player-specific grief vectors either found or ruled out
**Plans**: 4 plans

Plans:
- [ ] 10-01-PLAN.md — ASSY-01 + ASSY-02 + ASSY-03: assembly slot verification (JackpotModule, MintModule) + _revertDelegate + array-shrink patterns
- [ ] 10-02-PLAN.md — ADMIN-01 + ADMIN-02: complete admin power map + wireVrf coordinator substitution verdict
- [ ] 10-03-PLAN.md — ADMIN-03 + ADMIN-04: 3-day stall trigger enumeration + 18h RNG lock window analysis
- [ ] 10-04-PLAN.md — ADMIN-05 + ADMIN-06: LINK drain economics + player-specific grief vector survey

### Phase 11: Token Security, Economic Attacks, Vault and Timing
**Goal**: All COIN/DGNRS mint authorization paths are confirmed safe, EV models for whale and lootbox combinations produce no extractable surplus, vault redemption rounding is shareholder-neutral, and ±900s timestamp manipulation produces no advantaged game outcomes
**Depends on**: Phase 10 (admin power map required to scope vaultMintAllowance and claimWhalePass authorization models correctly)
**Requirements**: TOKEN-01, TOKEN-02, TOKEN-03, TOKEN-04, TOKEN-05, TOKEN-06, TOKEN-07, TOKEN-08, VAULT-01, VAULT-02, TIME-01, TIME-02
**Success Criteria** (what must be TRUE):
  1. TOKEN-01 verdict confirmed: no path to unbounded COIN minting via `vaultMintAllowance` bypass — every code path that calls mint is traced to an authorization check; any gap named and severity-rated
  2. TOKEN-03 verdict confirmed: BurnieCoinflip entropy source determined — if VRF-based, PASS; if any block-level data (timestamp, blockhash, prevrandao) is used without VRF, finding raised at HIGH with specific line reference
  3. TOKEN-06 verdict confirmed: BURNIE 30-day guard applied identically across all purchase entry points (direct, operator-proxied, whale bundle, lazy pass, deity pass) with same timestamp comparison — any path that skips or weakens the guard named as bypass finding
  4. VAULT-02 verdict confirmed: DegenerusStonk `claimAmount = (reserveBalance * sharesBurned) / totalSupply` rounding direction verified — rounding consistently favors protocol over claimer (PASS) or specific partial-burn sequence that extracts disproportionate value is demonstrated
  5. TIME-01 and TIME-02 verdicts confirmed: ±900s validator timestamp drift cannot allow double daily jackpot allocation or break a target player's quest streak — either bounded by design (PASS with reasoning) or specific block timestamp sequence that exploits the window is documented
**Plans**: 5 plans

Plans:
- [ ] 11-01-PLAN.md — TOKEN-01 + TOKEN-02 + TOKEN-03: vaultMintAllowance bypass, claimWhalePass CEI, BurnieCoinflip entropy source
- [ ] 11-02-PLAN.md — TOKEN-04 + TOKEN-05 + TOKEN-06: lootbox EV cap model, activity score inflation cost, BURNIE 30-day guard completeness
- [ ] 11-03-PLAN.md — TOKEN-07 + TOKEN-08: affiliate circular ring EV, DGNRS lock/unlock level-transition timing exploit
- [ ] 11-04-PLAN.md — VAULT-01 + VAULT-02: DegenerusVault receive() donation safety, DegenerusStonk burn-to-claim rounding
- [ ] 11-05-PLAN.md — TIME-01 + TIME-02: daily jackpot double-trigger analysis, quest streak griefing via validator timestamp drift

### Phase 12: Cross-Function Reentrancy Synthesis and Unchecked Blocks
**Goal**: A complete cross-function reentrancy matrix covers every ETH-transfer site in the protocol, ERC721 callback paths are formally traced, and every unchecked block in JackpotModule is verified safe against adversarial state sequences including the three recent fix commits
**Depends on**: Phase 8 (ETH-transfer site map), Phase 10 (admin call paths), Phase 11 (token callback paths); all must complete before this integration pass
**Requirements**: REENT-01, REENT-02, REENT-03, REENT-04, REENT-05, REENT-06, REENT-07
**Success Criteria** (what must be TRUE):
  1. REENT-01 cross-function reentrancy matrix delivered: all ETH transfer sites listed with every reentrant call path from that site — matrix is complete (no transfer site omitted) and each path is either proven safe or a finding is raised
  2. REENT-02 ERC721 callback verdict confirmed: all `safeMint` paths in DegenerusNFT formally traced through `onERC721Received` — either no re-entry path exists into Game state-mutating functions (PASS) or specific callback sequence is demonstrated
  3. REENT-04 unchecked block audit complete: all 40 JackpotModule unchecked blocks audited with adversarial state sequences; commits 4592d8c, cbbafa0, and 9539c6d each tested for bypass across all purchase paths — each block either confirmed safe or adjacent vulnerability identified
  4. REENT-05 cursor mutual exclusion confirmed: `ticketCursor`/`ticketLevel` sharing between `processTicketBatch` and `processFutureTicketBatch` is either formally proved mutually exclusive (with the code path that enforces it cited) or a state sequence producing concurrent access is demonstrated
  5. REENT-06 and REENT-07 verdicts confirmed: `claimDecimatorJackpot` CEI ordering verified safe; `adminSwapEthForStEth` pool accounting invariant preserved — each either confirmed PASS or finding raised with extraction path
**Plans**: TBD

### Phase 13: Final Synthesis Report
**Goal**: A complete Code4rena-format findings report is delivered covering all confirmed findings from Phases 8–12, with coded PoC for every HIGH and MEDIUM finding and a dedicated gas report
**Depends on**: Phase 12 (all analysis phases must be complete)
**Requirements**: REPORT-01, REPORT-02, REPORT-03
**Success Criteria** (what must be TRUE):
  1. REPORT-01 prioritized findings report delivered: every confirmed finding from Phases 8–12 appears in exactly one severity section (CRITICAL / HIGH / MEDIUM / LOW / Gas / QA) with Code4rena severity methodology applied — no finding classified inconsistently with the methodology (e.g., admin-key-required paths not rated HIGH)
  2. REPORT-02 coded PoC provided for every HIGH and MEDIUM finding: each PoC is a concrete transaction sequence or pseudocode trace that a Code4rena judge can reproduce — no HIGH or MEDIUM finding is present without its PoC
  3. REPORT-03 gas report delivered: `advanceGame()` worst-case gas listed by code path with the specific adversarial state (player count, lootbox pending count, BAF activation status) that triggers each measured maximum
**Plans**: TBD

## Progress

**Execution Order:**
Phases 8 and 9 can run in parallel. Phase 10 requires Phase 8 complete. Phase 11 requires Phase 10 complete. Phase 12 requires Phases 8–11 complete. Phase 13 requires Phase 12 complete.

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 1. Storage Foundation Verification | v1.0 | 4/4 | Complete | 2026-02-28 |
| 2. Core State Machine and VRF Lifecycle | v1.0 | 6/6 | Complete | 2026-03-01 |
| 3a. Core ETH Flow Modules | v1.0 | 7/7 | Complete | 2026-03-01 |
| 3b. VRF-Dependent Modules | v1.0 | 6/6 | Complete | 2026-03-01 |
| 3c. Supporting Mechanics Modules | v1.0 | 6/6 | Complete | 2026-03-01 |
| 4. ETH and Token Accounting Integrity | v1.0 | 1/9 | Incomplete — gap accepted | - |
| 5. Economic Attack Surface | v1.0 | 7/7 | Complete | 2026-03-04 |
| 6. Access Control and Privilege Model | v1.0 | 7/7 | Complete | 2026-03-04 |
| 7. Cross-Contract Integration Synthesis | 4/5 | In Progress|  | - |
| 8. ETH Accounting Invariant and CEI Verification | v2.0 | 5/5 | Complete | 2026-03-04 |
| 9. advanceGame() Gas Analysis and Sybil Bloat | 4/4 | Complete   | 2026-03-04 | - |
| 10. Admin Power, VRF Griefing, and Assembly Safety | 4/4 | Complete    | 2026-03-04 | - |
| 11. Token Security, Economic Attacks, Vault and Timing | 5/5 | Complete   | 2026-03-04 | - |
| 12. Cross-Function Reentrancy Synthesis and Unchecked Blocks | v2.0 | 0/TBD | Not started | - |
| 13. Final Synthesis Report | v2.0 | 0/TBD | Not started | - |
