# Project Research Summary

**Project:** Degenerus Protocol Security Audit
**Domain:** Smart Contract Security Audit — VRF-based on-chain game with delegatecall modules, prize pools, and complex token economics
**Researched:** 2026-02-28
**Confidence:** HIGH

## Executive Summary

The Degenerus Protocol is a 22-contract Solidity 0.8.x on-chain game with Chainlink VRF V2.5 randomness, a delegatecall module dispatch architecture, stETH integration via Lido, and multi-phase prize pool economics. This is a full security audit of an existing protocol — not a new build — so the work is analysis, not construction. Expert audit methodology for this class of protocol is well-documented: begin with storage layout verification before any module review, then work outward from the core state machine through module logic, accounting integrity, and finally economic attack surface. The 884-test suite is a specification baseline, not a security proof, and the audit must deliberately focus on paths the protocol team did not write tests for.

The recommended audit toolchain centers on Slither (primary static analysis, including its `variable-order` and `vars-and-auth` printers), Aderyn (complementary AST analysis), Semgrep with Decurity rules (proxy-storage-collision patterns), and Medusa (coverage-guided fuzzing for accounting invariants). Foundry can be installed alongside the existing Hardhat project to write invariant test harnesses and run `forge inspect` for storage layout verification. The critical constraint on tooling is that the Hardhat ESM project must be handled carefully — some tools require the `--hardhat-ignore-compile` flag or `--build-system hardhat` overrides. Formal verification via Halmos is appropriate only for bounded checks on the deity pass triangular pricing formula and ticket cost formula; full formal verification of 22 contracts is out of scope.

The four highest-severity risk areas in this protocol — all requiring deep investigation — are: (1) the VRF callback gas limit creating a permanent-DOS path if the callback reverts; (2) the nudge mechanism allowing a block proposer to front-run `advanceGame` with a known VRF word and shift jackpot outcomes; (3) storage slot layout drift in the 10 delegatecall modules causing silent state corruption; and (4) the prize pool accounting invariant (`balance + stETH >= claimablePool`) breaking under stETH rebasing or reentrancy. These four are not independent — they connect. A storage slot collision in the AdvanceModule could break the RNG lock state machine, which creates the window for nudge manipulation. Audit phases must be sequenced to detect this kind of compound failure.

## Key Findings

### Recommended Stack

The audit toolchain is a layered stack where each tool serves a distinct purpose. Static analysis with Slither and Aderyn runs in under 30 seconds per contract and provides the base vulnerability scan. Slither's printer suite — specifically `variable-order` for storage layout comparison and `vars-and-auth` for access control matrix generation — is directly purpose-built for the delegatecall and access control surfaces in this protocol. Semgrep with the Decurity ruleset adds DeFi-specific exploit pattern matching that Slither's general detectors miss, including a `proxy-storage-collision` rule directly relevant to the 10-module delegatecall pattern. Do not use Mythril — it has SMT solver timeouts on contracts above 300 lines and cannot complete analysis on this codebase.

For dynamic analysis, Medusa (Trail of Bits, released Feb 2025) is the primary fuzzer. It is faster than Echidna for coverage discovery and parallelizes across CPU cores. The highest-value target for Medusa is the ETH accounting invariant: total ETH deposited must equal prize pools plus fees plus vault allocations across all code paths. Echidna should be used as a fallback when Medusa's Hardhat crytic-compile integration causes issues with the ESM project format. Foundry should be installed separately (not as a replacement for Hardhat) to enable `forge inspect` storage layout verification and Forge invariant harnesses for the highest-priority accounting properties.

**Core technologies:**
- Slither (latest): Primary static analysis, 100+ detectors, critical printer commands for storage layout and access control mapping — industry standard from Trail of Bits
- Aderyn (latest): Secondary static analysis, AST-based Rust analyzer with low false-positive rate — complementary to Slither, catches different pattern classes
- Semgrep + Decurity rules: Pattern-matching for DeFi-specific exploit patterns including proxy-storage-collision — directly relevant to delegatecall pattern
- Medusa (latest): Primary fuzzer, coverage-guided, parallel execution — best tool for accounting invariant violations and EV multiplier math
- Foundry v1.3.0+: Standalone installation for `forge inspect` storage layout verification and Forge invariant harnesses — do not migrate the Hardhat project
- Halmos (latest): Bounded symbolic execution for specific math formulas (deity pass T(n), ticket cost formula) — use narrowly, not for full protocol verification
- Tenderly: Transaction simulation and cross-contract state tracing — essential for multi-step game-over sequence debugging
- Chainlink VRF V2.5 8-point security checklist: Official mandatory review item for all VRF consumer contracts

### Expected Features (Audit Coverage)

The audit is structured as three sequential phases with clear completion gates before proceeding. Phase 1 covers the non-negotiable baseline that every credible audit must complete. Phase 2 covers protocol-specific deep dives that require Phase 1 findings to be stable. Phase 3 covers economic and systemic analysis that requires both prior phases.

**Must have — Phase 1 (table stakes, blocks report if incomplete):**
- Access control enumeration — all privileged entry points mapped across all 22 contracts
- Reentrancy analysis — all external call sites reviewed for CEI compliance, with specific focus on `claimWinnings` (ETH + stETH transfer before state clear) and stETH callback paths
- Integer arithmetic and precision review — ticket cost formula, EV multipliers, fee splits (90/10 pool split), deity pass T(n) triangular pricing
- Input validation sweep — ticket quantity bounds, affiliate code format, MintPaymentKind enum bounds, zero-address guards
- ETH/stETH accounting invariant — all inbound and outbound paths traced; invariant: `address(this).balance + stETH.balanceOf(this) >= claimablePool`
- Unchecked external call review — stETH.submit(), stETH.transfer(), LINK.transferAndCall(), VRF coordinator calls

**Should have — Phase 2 (protocol-specific depth):**
- VRF state machine integrity — full request/fulfill/timeout/retry lifecycle; `fulfillRandomWords` non-reversion guarantee; RNG lock completeness
- Delegatecall storage slot collision analysis — all 10 modules verified via `forge inspect` comparison against `DegenerusGame` storage layout
- Game-over settlement correctness — terminal state fund distribution trace across the multi-step sequence
- Stall recovery path security — emergency (3-day) and final sweep (30-day) paths; premature trigger risk
- Cross-contract interaction safety — stETH rebasing desync, BURNIE burn return value, DGNRS transferFromPool
- Operator approval abuse — every `_resolvePlayer()` call site verified that value flows to `player` not `msg.sender`

**Phase 3 (differentiating depth, requires Phase 1+2 complete):**
- Economic invariant / EV analysis — lootbox EV multiplier, whale bundle pricing, activity score gaming
- Sybil/coordinated multi-wallet attack analysis — can 51%+ ticket ownership yield positive group EV?
- MEV / block proposer attack surface — nudge manipulation after VRF fulfillment, sandwich attacks on phase boundaries
- Affiliate extraction analysis — circular affiliate structures, referrer+referee positive-sum scenarios

**Explicitly out of scope (anti-features):**
- Gas optimization recommendations (separate engagement)
- Contract rewrites or code PRs (findings with remediation guidance only)
- Frontend/off-chain code review
- Mock contract or test infrastructure review
- Testnet-specific contract configurations (focus on mainnet only)
- Raw automated scanner output without manual triage and confirmation

### Architecture Approach

The Degenerus Protocol has a strict 7-phase audit dependency graph that cannot be reordered without creating gaps. Phase 1 (storage foundation) gates every subsequent module review because all 10 modules execute in DegenerusGame's storage context — misunderstanding the slot layout invalidates all downstream analysis. Phase 2 (core state machine and VRF lifecycle) must follow because the AdvanceModule controls the entire FSM progression and its VRF lock semantics affect what every other module can safely do. Phases 3a-3f (game modules) are partially parallelizable but all depend on Phases 1-2. Phases 4 (ETH accounting), 5 (economic attack surface), and 6 (access control) form a sequential chain. Phase 7 (cross-contract synthesis) must be last — it is the integrating pass that maps findings across boundaries and is the one phase that must never be split across reviewers.

**Major components:**
1. `DegenerusGameStorage` + `ContractAddresses` (storage foundation) — canonical slot layout and compile-time address constants; must be verified before any module is opened
2. `DegenerusGame` + `DegenerusGameAdvanceModule` + `GameTimeLib` (core state machine) — FSM, VRF callback handler, delegatecall dispatch, state transition guards; central audit target
3. Game Modules x10 (MintModule, JackpotModule, LootboxModule, EndgameModule, WhaleModule, BoonModule, DecimatorModule, DegeneretteModule, GameOverModule, MintStreakUtils) — all execute via delegatecall in DegenerusGame's context; ordered by ETH value at risk: Mint > Jackpot > Lootbox > Endgame > Whale > supporting
4. ETH/Token Accounting Layer (DegenerusVault, BurnieCoin, BurnieCoinflip, DegenerusStonk) — cross-contract ETH and token accounting invariants; reviewed holistically not per-contract
5. Peripheral Contracts (DegenerusAffiliate, DegenerusQuests, DegenerusDeityPass, DegenerusJackpots) — interact with core via privilege model; access control surface
6. External Integrations (Chainlink VRF V2.5, Lido stETH, LINK ERC-677) — each has protocol-specific audit gotchas documented separately

### Critical Pitfalls

The research identified 7 critical and 7 moderate pitfalls. The five most important for phase planning are:

1. **VRF callback gas limit silent DOS** — If `rawFulfillRandomWords` exceeds 300,000 gas (the VRF coordinator's fixed limit), the coordinator does not retry and the game is permanently stalled. Prevention: measure callback gas cost with `forge` gas snapshots at worst-case lootbox state; callback must stay under 200,000 gas with headroom; all complex post-VRF logic should be deferred to the next `advanceGame` call. Address in Phase 2 (RNG state machine).

2. **Nudge window exploitable by block proposer** — `reverseFlip()` allows BURNIE holders to add +1 offset to the upcoming VRF word. If `rngLockedFlag` is cleared before `rngWordCurrent` is consumed by `advanceGame`, a block proposer can see the fulfilled word, calculate the desired nudge count, and front-run `advanceGame` in the same block to control jackpot outcomes. Prevention: verify `rngLockedFlag` remains set continuously from VRF request through word consumption. Address in Phase 2 (highest priority).

3. **Storage slot layout drift in delegatecall modules** — Any module that inherits from an extra parent or declares an instance variable shifts its slot view relative to `DegenerusGame`, causing silent state corruption. Prevention: run `forge inspect` on all 10 modules and compare slot-by-slot against DegenerusGame storage layout; this is a 30-minute automated check that must be done before any module review begins. Address in Phase 1.

4. **Rounding direction accumulation drains protocol** — Fee splits of the form `amount * bps / 10000` consistently truncate in one direction. At scale, this creates a balance sheet gap that breaks the ETH accounting invariant. Directly analogous to the $128M Balancer exploit (Nov 2025). Prevention: fuzz all fee split formulas with values from 1 wei to 1000 ETH; verify both halves of every split sum to the original amount. Address in Phase 4.

5. **stETH rebasing breaks accounting invariant and game-over settlement** — `steth.balanceOf(this)` changes between blocks without transfers. Any cached stETH balance used for payout calculations drifts. During multi-step game-over, a Lido slashing event could shrink the balance below the committed settlement amount, causing all endgame withdrawals to revert. Prevention: never cache `steth.balanceOf(this)` in a state variable; game-over settlement must use live balances at payout time. Address in Phase 4 and Phase 2 edge cases.

## Implications for Roadmap

The audit dependency graph drives the phase structure directly. This is not a preference — it is a technical requirement of the delegatecall architecture. Reviewing modules before storage layout, or economic attack surface before accounting correctness, produces findings that can be invalidated or missed entirely.

### Phase 1: Storage Foundation Verification
**Rationale:** Every subsequent phase depends on a correct understanding of the storage layout. A slot collision found in Phase 5 is a wasted Phase 3 and Phase 4. This is a 30-minute automated pass that pays for itself immediately.
**Delivers:** Verified storage layout map for all 10 modules; confirmed no module declares instance variables; `ContractAddresses` constants mapped to expected addresses.
**Addresses:** FEATURES.md table stakes — delegatecall storage collision analysis (HIGH audit value, HIGH implementation cost)
**Avoids:** PITFALLS.md Pitfall 5 (storage slot layout drift) — the single most catastrophic bug class in delegatecall systems

### Phase 2: Core State Machine and VRF Lifecycle
**Rationale:** The FSM and VRF state machine are the backbone of the entire protocol. Finding a bug here changes what is possible in all downstream phases. The nudge/VRF-word manipulation (Pitfall 3) is the highest-severity finding candidate in the audit and must be evaluated before any module is reviewed as "safe."
**Delivers:** Complete VRF lifecycle analysis (8-point Chainlink checklist verified); RNG lock state machine traced through all paths; gas budget verified for `rawFulfillRandomWords`; FSM state transition completeness confirmed.
**Uses:** Slither `data-dependency` printer, Foundry gas snapshots, manual Chainlink VRF checklist
**Avoids:** PITFALLS.md Pitfall 1 (VRF callback DOS), Pitfall 2 (stale request ID), Pitfall 3 (nudge window manipulation)

### Phase 3: Game Module Logic
**Rationale:** All 10 modules execute via delegatecall in DegenerusGame's context. They can be partially parallelized within this phase but all depend on Phases 1 and 2. Sub-ordering within the phase is by ETH value at risk: MintModule (ETH inflow) before JackpotModule (ETH outflow) before LootboxModule (VRF-dependent) before EndgameModule (level transitions) before WhaleModule (pricing formulas) before supporting modules.
**Delivers:** Per-module findings for all 10 delegatecall modules; pricing formula correctness; lootbox EV multiplier arithmetic; game-over terminal settlement path.
**Uses:** Slither, Aderyn, Semgrep Decurity rules, Medusa fuzzing on MintModule and JackpotModule
**Implements:** Architecture Phase 3 sub-phases (3a through 3f)

### Phase 4: ETH and Token Accounting Integrity
**Rationale:** The central invariant (`balance + stETH >= claimablePool`) must hold after every possible cross-contract call sequence. This is a holistic pass across DegenerusGame, DegenerusVault, BurnieCoin, and the stETH integration — it cannot be verified per-contract in isolation. Requires all Phase 3 inflow/outflow paths to be mapped first.
**Delivers:** Verified ETH accounting invariant; fee split correctness confirmed (all BPS splits sum to input); stETH rebasing behavior documented; BurnieCoin supply invariants confirmed; `receive()` ETH routing verified.
**Uses:** Medusa invariant harnesses asserting total ETH in == total ETH out; Foundry fuzz tests on all split formulas
**Avoids:** PITFALLS.md Pitfall 6 (stETH rebasing), Pitfall 7 (rounding accumulation), Pitfall 14 (`receive()` routing miscounting)

### Phase 5: Economic Attack Surface
**Rationale:** Economic attacks require a complete picture of all mechanics. A finding here often points back to a Phase 3 implementation detail. This phase validates that the game's incentive structure is robust against coordinated adversaries, not just that individual functions are correct.
**Delivers:** EV model for Sybil group majority ticket ownership; whale bundle and deity pass EV analysis; MEV/block proposer attack surface quantified; affiliate extraction model; activity score manipulation vectors.
**Uses:** Analytical modeling, Slither, Tenderly for multi-step simulation
**Avoids:** PITFALLS.md Pitfall 11 (block proposer phase boundary reordering), Pitfall 12 (Sybil majority ticket extraction)

### Phase 6: Access Control and Privilege Model
**Rationale:** Access control issues are context-dependent — a function that looks properly gated may still be abusable if its accounting or economic effects (Phases 4 and 5) allow secondary extraction. Reviewing access control after understanding those phases produces higher-quality findings.
**Delivers:** Complete authorization matrix for all 22 contracts; operator approval abuse scenarios enumerated; `DegenerusAdmin` privilege model documented; VRF subscription consumer control verified.
**Uses:** Slither `vars-and-auth` printer
**Avoids:** PITFALLS.md Pitfall 8 (operator approval cross-player manipulation), Pitfall 16 (VRF subscription griefing)

### Phase 7: Cross-Contract Integration Synthesis
**Rationale:** Cross-contract interaction bugs are composite — they require understanding both sides of the boundary. This phase synthesizes all prior findings across contract boundaries. It must never be split across reviewers and must be scheduled explicitly, not treated as a byproduct of per-contract work.
**Delivers:** Full call-chain reentrancy analysis; stETH + LINK callback safety; constructor-time cross-call ordering confirmed; `fulfillRandomWords` caller validation confirmed; composite finding synthesis across all phases.
**Uses:** Tenderly, Slither `call-graph` printer, manual cross-contract trace
**Avoids:** FEATURES.md anti-pattern 1 (per-contract isolation missing cross-boundary bugs)

### Phase Ordering Rationale

- **Storage first (Phase 1)** because the delegatecall architecture makes all subsequent analysis invalid if slot assignments are wrong. This is the most unique constraint of this protocol versus a standard multi-contract system.
- **VRF second (Phase 2)** because the nudge/VRF-word manipulation is the highest-severity candidate and its analysis determines whether dozens of module behaviors are exploitable. Finding this after module review wastes module review time.
- **Modules before accounting (Phase 3 before Phase 4)** because the ETH accounting invariant cannot be verified without first mapping all inflow and outflow paths across all modules. Phase 3 produces the path map; Phase 4 verifies the invariant over it.
- **Accounting before economics (Phase 4 before Phase 5)** because economic attacks exploit the gap between intended and actual fund flows. Economic analysis is meaningless without verified accounting.
- **Access control late (Phase 6)** because access control findings are richer when informed by what the attacker can do with elevated access (Phases 4 and 5).
- **Synthesis last (Phase 7)** because cross-boundary findings require per-contract understanding from all prior phases.

### Research Flags

Phases likely needing deeper investigation during execution (known unknowns requiring live codebase inspection):

- **Phase 2 (VRF and RNG):** The nudge window timing (Pitfall 3) depends on the exact sequencing of `rngLockedFlag` state transitions. The research identifies the risk and the verification approach but the pass/fail depends on reading the actual code. This is the audit's highest-risk open question.
- **Phase 3c (LootboxModule):** The activity score EV multiplier formula and its interaction with the lootbox VRF word derivation require careful mathematical modeling. The research flags this but explicit formula analysis is needed.
- **Phase 4 (stETH accounting):** Whether any path caches `steth.balanceOf(this)` in a state variable is determined by code inspection. Research identifies the risk pattern but not its presence or absence.
- **Phase 5 (Economic modeling):** Sybil EV analysis requires building a mathematical model of the prize pool mechanics. No existing source documents whether the Degenerus prize pool structure is provably EV-negative for majority ticket holders.

Phases with well-documented patterns (standard coverage, no additional research needed):

- **Phase 1 (Storage layout):** `forge inspect` comparison is a deterministic, automated check. Methodology is fully documented.
- **Phase 6 (Access control):** Slither `vars-and-auth` printer and the OWASP SC01 checklist provide complete coverage. Well-documented patterns.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Toolchain recommendations based on official sources (Chainlink docs, Trail of Bits blog, Foundry v1.0 announcement). Medusa/Halmos sourced from authoritative producers. Mythril exclusion corroborated by comparative benchmarking. |
| Features | HIGH | OWASP SC Top 10 2026 verified from official OWASP source. Chainlink VRF V2.5 checklist from official docs. Protocol-specific vulnerability classes derived from direct codebase inspection. |
| Architecture | HIGH (codebase) / MEDIUM (methodology) | Architecture analysis from direct inspection of DegenerusGame.sol, DegenerusGameStorage.sol, DegenerusGameAdvanceModule.sol. Methodology sourced from Hacken and Cyfrin audit guides — MEDIUM confidence. |
| Pitfalls | HIGH | Critical pitfalls corroborated: VRF callback gas limit from official Chainlink docs; rounding from Balancer $128M post-mortem; storage collision from Audius/AllianceBlock documented incidents; stETH from official Lido integration guide. |

**Overall confidence:** HIGH

### Gaps to Address

- **Nudge window timing (Phase 2):** The exact state of `rngLockedFlag` between VRF fulfillment and `advanceGame` word consumption is the most important open question. Code inspection during Phase 2 will resolve this. If the window exists, this is a critical finding. If the flag covers the full window, this pitfall is mitigated.
- **BurnieCoin `burnCoin` return behavior (Phase 4):** Whether `burnCoin` reverts on insufficient balance or returns false is not documented in the research. A 5-minute code read resolves this but it is flagged as a gap because the consequence (free nudges/coinflips) is high.
- **EV negativity proof (Phase 5):** Whether the prize pool mechanics guarantee negative EV for a majority Sybil group requires building a mathematical model during the audit. No existing source proves or disproves this for the Degenerus structure.
- **`TESTNET_ETH_DIVISOR` propagation:** Research confirms testnet contracts are out of scope, but auditors should verify that no testnet configuration bleeds into mainnet contract logic (e.g., conditional compilation paths). A brief search during Phase 1 is sufficient.
- **Medusa Hardhat ESM compatibility:** Research notes that Medusa's crytic-compile integration with Hardhat ESM projects may need the `--build-system hardhat` flag. Verify this works before fuzzing campaigns begin; fall back to Echidna if integration fails.

## Sources

### Primary (HIGH confidence)
- [Chainlink VRF V2.5 Security Considerations](https://docs.chain.link/vrf/v2-5/security) — official 8-point VRF consumer audit checklist
- [DegenerusGameStorage.sol, DegenerusGame.sol, DegenerusGameAdvanceModule.sol] — direct codebase inspection (primary source for architecture and pitfalls)
- [Medusa: Trail of Bits Blog (Feb 2025)](https://blog.trailofbits.com/2025/02/14/unleashing-medusa-fast-and-scalable-smart-contract-fuzzing/) — Medusa capabilities and Echidna comparison
- [Foundry v1.0 Announcement (Paradigm)](https://www.paradigm.xyz/2025/02/announcing-foundry-v1-0) — storage layout inspection, invariant testing
- [Lido stETH Integration Guide](https://docs.lido.fi/guides/lido-tokens-integration-guide/) — stETH rebasing behavior, share vs amount distinction
- [OWASP Smart Contract Top 10: 2026](https://scs.owasp.org/sctop10/) — vulnerability class framework
- [Balancer $128M rounding exploit (Check Point Research, Nov 2025)](https://research.checkpoint.com/2025/how-an-attacker-drained-128m-from-balancer-through-rounding-error-exploitation/) — rounding accumulation attack documentation

### Secondary (MEDIUM confidence)
- [Slither GitHub (crytic/slither)](https://github.com/crytic/slither) — printer commands, Hardhat integration
- [Aderyn GitHub (Cyfrin/aderyn)](https://github.com/Cyfrin/aderyn) — AST analysis, MCP support
- [Decurity semgrep-smart-contracts](https://github.com/Decurity/semgrep-smart-contracts) — proxy-storage-collision rule
- [Halmos formal verification (a16z)](https://a16zcrypto.com/posts/article/formal-verification-of-pectra-system-contracts-with-halmos/) — Pectra system contract verification use case
- [Hacken Smart Contracts Audit Methodology](https://docs.hacken.io/methodologies/smart-contracts/) — audit phase structure
- [MixBytes: Collisions of Solidity Storage Layouts](https://mixbytes.io/blog/collisions-solidity-storage-layouts) — delegatecall storage collision patterns
- [Solodit audit checklist](https://solodit.cyfrin.io/checklist) — ~380 community checks from real audits
- [Chainlink VRF white hat $300K bounty (subscription owner attack)](https://cryptoslate.com/chainlink-vrf-vulnerability-thwarted-by-white-hat-hackers-with-300k-reward/) — VRF subscription management risk
- [Fuzzing comparison: Foundry vs Echidna vs Medusa](https://github.com/devdacian/solidity-fuzzing-comparison) — Medusa invariant-breaking advantage over Foundry

### Tertiary (LOW confidence)
- [Certora Goes Open Source](https://www.certora.com/blog/certora-goes-open-source) — verify current licensing before use as Phase 2 fallback
- [Mythril limitations (Vultbase comparison)](https://www.vultbase.com/articles/smart-contract-security-tools-compared) — SMT timeout characterization; verify current tool state

---
*Research completed: 2026-02-28*
*Ready for roadmap: yes*
