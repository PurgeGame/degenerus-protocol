# Project Research Summary

**Project:** Degenerus Protocol — Adversarial Security Audit v2.0 (Code4rena Preparation)
**Domain:** Smart contract security audit — VRF-based on-chain game with delegatecall modules, ETH prize pools, and complex token economics
**Researched:** 2026-03-04
**Confidence:** HIGH

## Executive Summary

The Degenerus Protocol is a 22-contract on-chain game with 10 delegatecall modules, Chainlink VRF V2.5, Lido stETH integration, and a three-asset token system (COIN/DGNRS/DEITY NFTs). The v1.0 audit completed static analysis (Slither, Aderyn), access control mapping, delegatecall storage layout verification, VRF lifecycle review, FSM transition enumeration, and found one HIGH finding (F01: whale bundle level eligibility bypass). The v2.0 adversarial audit is a Code4rena contest preparation pass that must complete the work v1.0 explicitly deferred: ETH accounting invariant verification (8 of 9 Phase 4 plans unexecuted), advanceGame() gas worst-case analysis, Sybil bloat modeling, admin power abuse enumeration, VRF griefing vectors, and cross-function reentrancy synthesis.

The recommended approach is to treat this audit as a Code4rena warden would: prioritize the highest-severity unconfirmed attack surfaces first, build coded PoC tests for each finding before classifying severity, and do not spend time re-running areas v1.0 already closed. The tool stack adds Medusa v1.5.0 coverage-guided fuzzing (primary) and Echidna 2.3.1 (cross-validation) for invariant testing, Halmos v0.3.3 bounded symbolic execution for critical math formulas, and Foundry forge gas-report harnesses for advanceGame() worst-case measurement — all running alongside the existing 884-test Hardhat suite without replacing it. The ETH accounting invariant is the master dependency: it cannot be declared clean until reentrancy, BPS rounding, game-over settlement, and stETH rebasing are each individually confirmed safe.

The two highest-risk unconfirmed surfaces are: (1) the `_creditClaimable` utility function, which is called by every jackpot winner payout path and is suspected to not increment `claimablePool` — if confirmed, aggregate claimable liability exceeds the tracked pool, breaking solvency and likely constituting a Code4rena HIGH finding; and (2) `advanceGame()` gas under adversarial state, where composition of processTicketBatch (up to 11M gas cold), payDailyJackpot winner loop, and BAF multi-level scatter jackpot could approach or breach the 16M block limit with a Sybil-bloated player set costing as little as 25 ETH to construct. All other v2.0 surfaces are MEDIUM-range unless specific conditions hold.

## Key Findings

### Recommended Stack

The v1.0 tooling (Slither 0.11.5, Aderyn, forge inspect, Hardhat) carries forward unchanged. V2.0 adds three new tool categories not used in v1.0: fuzzing, formal verification, and targeted gas profiling. The primary fuzzer is Medusa v1.5.0 (Trail of Bits, Feb 2025), which uses coverage-guided parallel fuzzing with Slither-enhanced mutation — superior to Echidna for invariant discovery speed. Echidna 2.3.1 is the secondary cross-validator. Halmos v0.3.3 handles bounded symbolic execution for specific arithmetic formulas (deity pass T(n), ticket cost formula `(priceWei * qty) / 400`, BPS splits). Foundry v1.0 provides standalone gas-report harnesses for advanceGame() worst-case measurement without touching the existing Hardhat ESM setup.

**Core technologies:**
- Medusa v1.5.0: PRIMARY fuzzer — coverage-guided parallel fuzzing with Slither-enhanced mutation; best tool for ETH accounting invariants and behavioral state-dependent bugs
- Echidna 2.3.1: SECONDARY fuzzer — mature Hardhat integration, corpus-based approach catches narrow FSM state-transition windows Medusa's coverage guidance may miss; generates Foundry reproducers
- Halmos v0.3.3: Bounded symbolic execution for arithmetic overflow proofs — uses Foundry test syntax, no new DSL; placed in standalone `audit-harnesses/` directory separate from Hardhat project
- Foundry forge v1.0: Gas profiling harnesses for advanceGame() worst-case scenarios — does not replace or migrate the Hardhat project; used only for targeted audit harnesses
- Slither 0.11.5 with `vars-and-auth` and `call-graph` printers: Admin privilege map and full advanceGame() call tree for gas path enumeration
- Hardhat `REPORT_GAS=true`: Baseline gas measurement across existing 884 tests before Foundry targeted adversarial scenarios

**Excluded tools (do not use):** Mythril (SMT stalls on contracts >300 lines; default max-depth 22 insufficient for multi-step FSM); MythX (same underlying engine, adds cost); Securify2 (unmaintained, no Solidity 0.8.x support); Certora Prover (CVL learning curve not justified for time-boxed audit — Halmos covers the critical math properties); Foundry as primary test environment (do not migrate the 884-test Hardhat suite).

### Expected Features (Audit Scope)

The audit scope is a three-phase Code4rena preparation pass. Phase 1 completes explicitly deferred v1.0 gaps. Phase 2 covers new v2.0 adversarial attack surfaces. Phase 3 synthesizes findings into a Code4rena-format report. Code4rena severity calibration: HIGH = assets directly at risk (requires coded PoC); MEDIUM = function/availability impact with stated assumptions; admin/centralization defaults to QA/LOW unless a non-hypothetical harm path exists without admin bad faith.

**Must have (table stakes — missing means audit is incomplete):**
- ETH accounting invariant: `sum(deposits) == prizePool + futurePool + claimablePool + fees` across all game states — the master invariant every Code4rena warden checks first
- claimWinnings() CEI cross-function reentrancy: same-function reentrancy confirmed safe by sentinel pattern; cross-function path (purchase() during ETH callback) is unverified
- BPS split correctness: all splits must sum to input with correct rounding direction; the `_creditClaimable` call site audit is the critical sub-task
- advanceGame() worst-case gas: complete call graph documented in ARCHITECTURE.md; must measure against 16M block limit with Foundry harnesses
- COIN/DGNRS mint authorization: vaultMintAllowance bypass paths and claimWhalePass double-mint check
- Final prioritized findings report: Code4rena severity classification applied to all confirmed findings

**Should have (differentiators — likely MEDIUM findings):**
- Sybil bloat calculation: per-player storage cost, O(n) growth in processTicketBatch, breakeven player count N vs. 16M gas ceiling; economic cost to reach N
- Admin power abuse: wireVrf coordinator substitution risk, adminStakeEthForStEth solvency guard absence, 3-day stall bypass mechanics
- VRF retry window exploitation: 18h window timing vs. any state-changing calls permissible during RNG lock period
- BurnieCoinflip entropy source verification (HIGH if block-level data found; MEDIUM if VRF-based with incorrect EV)
- Whale/deity combined EV model: can high-activity-score whale extract positive EV from bundle + lootbox combination?
- Cross-function reentrancy synthesis: full ETH-touching call site map, ERC721 `onERC721Received` callback paths
- BURNIE 30-day guard completeness across all purchase paths (not just the one in commit 4592d8c)

**Defer (Code4rena does not credit these):**
- Gas optimization recommendations — separate scoring track at Code4rena, explicitly out of scope per PROJECT.md
- Testnet contract review — TESTNET_ETH_DIVISOR=1,000,000 makes findings non-transferable to mainnet
- Full formal verification of all 22 contracts — months-long engagement, not a time-boxed audit
- Re-running v1.0 completed checks: access control matrix, delegatecall storage layout, VRF lifecycle 8-point checklist, FSM transition graph, per-module reentrancy (each confirmed complete and should not be repeated)

### Architecture Approach

Degenerus uses a delegatecall hub-and-spoke pattern: DegenerusGame (19KB) owns all ETH and storage (135 variables in DegenerusGameStorage) and dispatches every complex operation via delegatecall to 10 modules that execute in Game's storage context. This eliminates upgrade-proxy attack surface but creates three architecture-level audit constraints relevant to v2.0: (1) `nonReentrant` guards at the module level do not protect Game's storage during reentrant calls — guards must be at the DegenerusGame entry point level; (2) all ETH, claimable balances, and pool accounting live in Game's storage, so any module that modifies these without updating the corresponding aggregate pool variable breaks the solvency invariant; (3) cursor state (`ticketCursor`, `ticketLevel`) is shared between `processTicketBatch` and `processFutureTicketBatch` — documented as mutually exclusive but not verified, and a corruption here would cause mid-batch level skips.

**Major components:**
1. DegenerusGame — FSM orchestrator and ETH custodian; delegates all complex logic via delegatecall; direct functions: recordMint, claimWinnings, operator approvals; all ETH in/out flows through here
2. DegenerusGameAdvanceModule — advanceGame() tick logic, VRF request/receive, RNG gate; central DoS surface; complete call graph documented in ARCHITECTURE.md
3. DegenerusGameJackpotModule — daily ETH distribution, ticket batch processing (processTicketBatch with 550-write budget per call, up to 11M gas cold); contains 40 unchecked blocks (highest density in codebase)
4. DegenerusGamePayoutUtils — shared credit helpers including `_creditClaimable`; SUSPECTED to not update `claimablePool` — the most important unresolved finding candidate
5. DegenerusAdmin — VRF subscription owner, emergency coordinator rotation; sole admin power choke point; wireVrf is the highest-risk admin function
6. Peripheral contracts (BurnieCoinflip, DegenerusVault, DegenerusStonk, DegenerusAffiliate, DegenerusJackpots, DegenerusDeityPass) — external call targets from within delegatecall context; callback reentrancy vectors from COIN, JACKPOTS, and DEITY_PASS

**Key architectural patterns confirmed in v1.0 (do not re-verify):**
- Pull-withdrawal with 1 wei sentinel — claimableWinnings[player] = 1 before transfer; same-function reentrancy blocked
- Delegatecall storage layout — zero slot collisions confirmed across all 10 modules
- VRF lifecycle (8-point Chainlink checklist) — all PASS

### Critical Pitfalls

1. **`_creditClaimable` does not update `claimablePool` (ARCHITECTURE.md Anti-Pattern 2)** — Every call to `_creditClaimable` in JackpotModule, EndgameModule, and PayoutUtils may write to `claimableWinnings[player]` without incrementing `claimablePool`. If any caller omits the separate `claimablePool +=`, aggregate claimable liability silently exceeds the tracked pool. Prevention: audit every call site of `_creditClaimable` and confirm `claimablePool +=` is present in the same code path. This is the most likely unconfirmed HIGH finding in the protocol.

2. **advanceGame() gas composition under adversarial state (PITFALL 19)** — processTicketBatch uses up to 550 cold SSTOREs (~11M gas). `_prepareFinalDayFutureTickets` calls processTicketBatch 4 times per tick. payDailyJackpot winner loop adds ~8M. A Sybil attack creating 10K wallets at minimum cost (~25 ETH) could force 19 consecutive advanceGame() calls before the level can proceed. Prevention: measure with Foundry gas-report under worst-case adversarial state; flag any path >12.8M (80% of 16M limit) as HIGH DoS risk.

3. **VRF callback gas limit overflow causes silent DOS (PITFALL 1)** — `rawFulfillRandomWords` runs inside a delegatecall within a 300,000-gas limit set by VRF_CALLBACK_GAS_LIMIT. The Chainlink coordinator does not retry on revert. If lootbox pending state grows over the game's lifetime and pushes the callback above the limit, the game is permanently stalled until the 18h timeout. Prevention: measure callback gas with worst-case lootbox state using forge gas snapshots; keep under 200K with headroom.

4. **adminStakeEthForStEth without solvency guard (ARCHITECTURE.md Anti-Pattern 4)** — ADMIN can stake any ETH amount from Game's balance into Lido without checking that `address(this).balance - amount >= claimablePool`. Players with pending claimWinnings() would receive stETH instead of ETH if the liquid ETH balance is exhausted. Prevention: verify whether Game enforces a solvency guard before staking; if absent, classify as MEDIUM admin power finding.

5. **BURNIE 30-day guard completeness across all purchase paths (PITFALL 26)** — Commit 4592d8c added a 30-day BURNIE purchase block before liveness-guard timeout, but only for the tested path. All other purchase entry points (operator-proxied, whale bundle, lazy pass, deity pass) must apply the same guard with identical timestamp comparison. This is the mitigation-bypass pattern Code4rena wardens prioritize in second-pass reviews. Prevention: enumerate all purchase paths; fuzz boundary timestamps.

## Implications for Roadmap

The v2.0 audit has a dependency-driven phase build order confirmed by ARCHITECTURE.md. Two phases (1 and 2) can run in parallel if resourced. All phases precede the synthesis report.

### Phase 1: ETH Accounting Invariant and CEI Verification
**Rationale:** This is the v1.0 Phase 4 gap (8 of 9 plans unexecuted) and the master dependency. The `_creditClaimable` call site audit cannot wait. ETH accounting is what every Code4rena warden checks first — it is the primary path to HIGH severity. Cannot complete cross-function reentrancy synthesis (Phase 5) until accounting paths are mapped.
**Delivers:** Confirmed or refuted `_creditClaimable` claimablePool gap; CEI status of all ETH transfer sites (claimWinnings, refundDeityPass, degenerette resolution, endgame auto-rebuy); BPS split correctness across all fee paths; game-over zero-balance proof; stETH rebasing handling verification
**Addresses:** Table stakes: ETH accounting invariant, claimWinnings() CEI, BPS splits, game-over settlement
**Avoids:** Pitfalls 6, 7, 22 (stETH rebasing, rounding accumulation, ETH accounting completeness)
**Tool:** Medusa invariant harness + manual CEI trace of all ETH transfer sites in ARCHITECTURE.md
**Research flag:** No additional research needed — all ETH transfer sites documented in ARCHITECTURE.md

### Phase 2: advanceGame() Gas Analysis and Sybil Bloat Modeling
**Rationale:** Independent of Phase 1; can run in parallel. The call graph is complete in ARCHITECTURE.md. Gas analysis determines whether Sybil DoS attacks are economically feasible against the 1000 ETH threat model, which constrains all subsequent economic attack scoping. Must read JackpotModule source to confirm DAILY_ETH_MAX_WINNERS constant before analysis is complete.
**Delivers:** Worst-case gas measurement for every advanceGame() code path branch; Sybil bloat breakeven analysis (player count N where gas exceeds 16M); ETH cost to reach N Sybil wallets; verdict on whether DoS is exploitable within 1000 ETH threat model budget
**Addresses:** Differentiator: advanceGame() gas ceiling, Sybil bloat permanent game brick
**Avoids:** Pitfalls 19, 24 (advanceGame() gas ceiling, last-mover economic advantage)
**Tool:** Foundry forge `--gas-report` with adversarial state harnesses; REPORT_GAS=true Hardhat baseline; Slither `call-graph` printer for path enumeration
**Research flag:** No additional research needed; DAILY_ETH_MAX_WINNERS must be read from JackpotModule source

### Phase 3: Admin Power Enumeration and VRF Griefing
**Rationale:** Admin and VRF griefing are partially independent but share wireVrf as a connecting vector. wireVrf is both the highest-risk admin function (coordinator substitution) and the key VRF griefing vector. Analyze once, classify in both. Admin findings default to MEDIUM at Code4rena — careful classification prevents score penalty from overseverity.
**Delivers:** Complete admin power map (every admin function with worst-case consequence if key compromised); wireVrf coordinator substitution analysis; VRF retry window timing analysis (18h window vs. state-changing calls during lock); subscription drain economics; 3-day stall bypass mechanics
**Addresses:** Differentiator: admin emergency stall, VRF retry window, VRF subscription drain
**Avoids:** Pitfalls 18, 21 (admin power vectors, VRF subscription owner attack)
**Tool:** Slither `vars-and-auth` printer + manual review of DegenerusAdmin.sol; Chainlink VRF V2.5 security docs (already confirmed in STACK.md)
**Research flag:** No additional research needed

### Phase 4: Token Security and Economic Attack Modeling
**Rationale:** Token mint authorization (COIN/DGNRS) is HIGH-severity class if a bypass exists. Requires Phase 3 admin map because vaultMintAllowance and claimWhalePass authorization models depend on knowing admin powers. BurnieCoinflip entropy source is an independent check but lower priority — it is either a simple confirmation (VRF-based, safe) or an immediate HIGH (block-level data).
**Delivers:** vaultMintAllowance bypass verdict; claimWhalePass double-mint verdict; BurnieCoinflip entropy source confirmation; whale+lootbox combined EV model (can EV exceed 1.0 for high-activity-score whale?); activity score inflation cost analysis; BURNIE 30-day guard completeness verification across all purchase paths
**Addresses:** Differentiator: COIN/DGNRS mint authorization, BurnieCoinflip house edge, whale/deity EV model
**Avoids:** Pitfalls 26, 27, 28 (BURNIE guard bypass, degenerette CEI, vaultMintAllowance abuse)
**Tool:** Manual code review + Halmos for T(n) overflow and ticket cost formula arithmetic; Medusa for BURNIE/COIN economics; targeted source reads of DegenerusGameMintStreakUtils and DecimatorModule

### Phase 5: Cross-Function Reentrancy Synthesis and Unchecked Block Audit
**Rationale:** Must be last of the analysis phases — integrates findings from Phases 1-4. Cross-function reentrancy requires knowing all ETH-touching call sites (Phase 1), delegatecall module call boundaries, and which external contracts can callback into Game (Phases 3-4). Unchecked block audit (225 blocks total, 40 in JackpotModule) must verify recent fixes (capBucketCounts underflow, 1 wei sentinel) did not leave adjacent unchecked decrements exposed.
**Delivers:** Full cross-function reentrancy matrix covering all ETH transfer sites; ERC721 `onERC721Received` callback reentrancy verdict; multicall/operator-proxy delegatecall reentrancy verdict; complete unchecked block audit with adversarial state sequence tests for all 40 JackpotModule blocks; shared cursor corruption verification between processTicketBatch and processFutureTicketBatch
**Addresses:** Differentiator: cross-function reentrancy synthesis; architecture anti-patterns 1, 2, 3
**Avoids:** Pitfalls 20, 23, 25 (ERC721 callback reentrancy, multicall reentrancy, unchecked underflow)
**Tool:** Manual code review with adversarial scenario Foundry tests; Echidna corpus for unchecked block state sequences

### Phase 6: Final Synthesis Report
**Rationale:** Required deliverable for Code4rena contest submission. Code4rena requires PoC for all HIGH/MEDIUM findings. Admin/centralization findings must be correctly classified as QA/MEDIUM (not HIGH) — overseverity reduces warden score. Gas findings are a separate scoring track and must not be mixed with security findings.
**Delivers:** Prioritized findings report with CRITICAL / HIGH / MEDIUM / LOW / Gas / QA sections; coded PoC for all HIGH/MEDIUM findings; Code4rena severity methodology applied throughout; remediation guidance per finding
**Addresses:** Must-have deliverable: final prioritized findings report (plan 07-05 from v1.0)
**Avoids:** Anti-feature: admin findings submitted as HIGH (damages warden score at Code4rena)

### Phase Ordering Rationale

- Phases 1 and 2 can run in parallel — Phase 1 focuses on accounting paths, Phase 2 focuses on gas paths; both are independent
- Phase 3 must come after Phase 1 is scoped (admin staking can affect solvency — understanding Phase 1 accounting model helps classify Phase 3 findings correctly)
- Phase 4 must come after Phase 3 (admin power map informs token authorization analysis; vaultMintAllowance abuse requires knowing admin capabilities)
- Phase 5 must come after Phases 1-4 (integrating pass that synthesizes all ETH-touching call sites found in prior phases)
- Phase 6 must be last (synthesis of all confirmed findings with severity classification)

### Research Flags

Phases with well-documented patterns (no additional research needed):
- **Phase 1:** CEI and accounting invariant patterns are established; all ETH transfer sites documented in ARCHITECTURE.md; methodology is a direct application of known patterns
- **Phase 2:** Gas profiling methodology is standard; advanceGame() call graph is complete; methodology is direct application
- **Phase 3:** Chainlink VRF V2.5 security checklist already confirmed in STACK.md; admin function inventory in ARCHITECTURE.md

Phases with potential mid-execution research needs:
- **Phase 4 (BurnieCoinflip):** If entropy source is block-level data rather than VRF, research the MEV-Boost proposer/builder separation attack mechanics specific to Ethereum mainnet (2025 PBS model differs from 2023 documentation)
- **Phase 4 (EV modeling):** Whale+lootbox combined EV requires understanding DegenerusGameMintStreakUtils activity score implementation — read source before modeling; no external research needed
- **Phase 5 (unchecked blocks):** JackpotModule source must be fully read before Phase 5 begins; a targeted source read (not a research pass) is needed

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All tools verified by primary sources: Trail of Bits (Medusa), Paradigm (Foundry v1.0), a16z (Halmos production use), official Chainlink docs. Only Halmos version (v0.3.3) has MEDIUM confidence — GitHub release date not confirmed, may be late 2024. |
| Features | HIGH | Code4rena severity rubric sourced from official docs.code4rena.com. AI Arena C4 audit report reviewed as direct analogue (same game contract category). Scope gaps confirmed against PROJECT.md. |
| Architecture | HIGH | All claims derived from direct source code inspection (113,562 lines Solidity). Call graph, ETH flow paths, admin surfaces, and anti-patterns are from source code, not inference. DecimatorModule and JackpotModule (full text) not yet read — these are execution-time gaps, not confidence gaps. |
| Pitfalls | HIGH | All critical pitfalls (1-7, 18-28) confirmed from source code inspection + corroboration against real-world exploits (Balancer rounding, Euler composability, AI Arena C4, LooksRare Infiltration, Audius storage collision). |

**Overall confidence:** HIGH

### Gaps to Address

- **`_creditClaimable` claimablePool update — unconfirmed:** ARCHITECTURE.md flags this as "suspected missing" from reading PayoutUtils. Must be confirmed by auditing every call site of `_creditClaimable` in JackpotModule, EndgameModule, and all other callers during Phase 1. If confirmed missing, this is an immediate HIGH finding and expands Phase 1 scope.

- **DAILY_ETH_MAX_WINNERS constant — not yet read:** The payDailyJackpot winner loop gas estimate (~8M) depends on this constant in JackpotModule. Must be read before Phase 2 gas analysis conclusions are finalized.

- **JackpotModule cursor reset behavior — unconfirmed:** Anti-Pattern 1 in ARCHITECTURE.md identifies `ticketCursor`/`ticketLevel` sharing between processTicketBatch and processFutureTicketBatch as "documented mutually exclusive but not verified." The cursor reset path when `ticketLevel != lvl` must be read in JackpotModule source before Phase 2 and Phase 5.

- **DecimatorModule CEI — not yet read:** ARCHITECTURE.md flags `claimDecimatorJackpot` as needing CEI verification. DecimatorModule was not fully read during architecture research. Phase 1 and Phase 5 must include this source file.

- **Medusa ESM compatibility:** Medusa v1.5.0 uses crytic-compile's Hardhat integration. This is an ESM project (`"type": "module"`). STACK.md notes ESM projects may need `--build-system hardhat` flag. Verify compilation before writing invariant harnesses; fall back to Echidna if integration fails.

- **Halmos version currency:** v0.3.3 may be from mid-2024. Run `pip install halmos && halmos --version` before Phase 4 to confirm current version and check for updates.

## Sources

### Primary (HIGH confidence)
- Direct contract source analysis: `contracts/DegenerusGame.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`, `contracts/modules/DegenerusGamePayoutUtils.sol`, `contracts/storage/DegenerusGameStorage.sol`, `contracts/DegenerusAdmin.sol` (113,562 lines inspected)
- [Medusa v1 announcement — Trail of Bits Blog (Feb 14, 2025)](https://blog.trailofbits.com/2025/02/14/unleashing-medusa-fast-and-scalable-smart-contract-fuzzing/)
- [Medusa GitHub releases (crytic/medusa)](https://github.com/crytic/medusa/releases) — v1.5.0 Feb 6, 2025
- [Echidna GitHub releases (crytic/echidna)](https://github.com/crytic/echidna/releases) — v2.3.1 Jan 16, 2025
- [Chainlink VRF V2.5 Security Considerations](https://docs.chain.link/vrf/v2-5/security) — 8-point VRF checklist, subscription owner attack
- [Foundry v1.0 Announcement (Paradigm, Feb 2025)](https://www.paradigm.xyz/2025/02/announcing-foundry-v1-0)
- [Code4rena Severity Categorization](https://docs.code4rena.com/competitions/severity-categorization)
- [Code4rena AI Arena Audit Report (Feb 2024)](https://code4rena.com/reports/2024-02-ai-arena) — 8H/9M from game contract; direct analogue
- [Halmos for Pectra formal verification (a16z, 2025)](https://a16zcrypto.com/posts/article/formal-verification-of-pectra-system-contracts-with-halmos/)
- PROJECT.md — v2.0 milestone definition, active requirements, v1.0 gap list, out-of-scope list

### Secondary (MEDIUM confidence)
- [Fuzzing comparison: Foundry vs Echidna vs Medusa (devdacian)](https://github.com/devdacian/solidity-fuzzing-comparison) — Medusa breaks 2 invariants where Echidna breaks 1 within 5 min
- [Halmos GitHub releases (a16z/halmos)](https://github.com/a16z/halmos/releases) — v0.3.3 latest confirmed, date uncertain
- [Aderyn GitHub releases (Cyfrin/aderyn)](https://github.com/Cyfrin/aderyn/releases) — v0.6.8, exact date unconfirmed
- [hardhat-gas-reporter npm (cgewecke)](https://github.com/cgewecke/hardhat-gas-reporter) — v2.x ESM compatibility status
- [Hacken: Top 10 Smart Contract Vulnerabilities 2025](https://hacken.io/discover/smart-contract-vulnerabilities/)
- [Immunefi: The Ultimate Guide to Reentrancy](https://medium.com/immunefi/the-ultimate-guide-to-reentrancy-19526f105ac)
- [Chainlink VRF subscription owner $300K bounty](https://cryptoslate.com/chainlink-vrf-vulnerability-thwarted-by-white-hat-hackers-with-300k-reward/)

### Tertiary (corroborating exploit precedents)
- Sherlock LooksRare Infiltration audit — VRF callback gas overflow HIGH finding
- Code4rena Tigris audit (2022) — admin freeze-withdrawal HIGH pattern
- Euler Finance exploit post-mortem — composable correct-but-dangerous function interaction
- Balancer $128M exploit (Nov 2025) — rounding direction drain
- Audius $6M hack (2022) — delegatecall storage collision

---
*Research completed: 2026-03-04*
*Supersedes: SUMMARY.md dated 2026-02-28 (v1.0 audit)*
*Ready for roadmap: yes*
