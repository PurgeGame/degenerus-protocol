# Project Research Summary

**Project:** Degenerus Protocol v49.0 — Unified Keeper "Do-Work" Router + Bounty Recalibration + AfKing Keeper Sweep
**Domain:** On-chain adversarial real-money game — permissionless keeper subsystem on an existing audited Solidity codebase
**Researched:** 2026-05-26
**Confidence:** HIGH

## Executive Summary

This is a subsequent-milestone (v49.0) feature for a shipped, audited on-chain game. The work is narrow and well-scoped: add one `doWork(maxCount)` entrypoint to `AfKing.sol` that routes to exactly one keeper category per call (advance-if-due → `autoOpen` → `autoBuy`; `autoResolve` deliberately excluded), re-home the `advanceGame` caller-reward from `AdvanceModule.sol` into the router, and recalibrate all keeper bounties to break-even at 0.5 gwei in BURNIE flip-credit. Every comparable mature keeper system (Chainlink Automation, Keep3r v2, MakerDAO Liquidations 2.0, Gelato) validates the same fundamental shape: one action type per call, off-chain work detection, flat fee covers gas, liveness escalation for stalls. The critical divergence from those precedents is that Degenerus pays from a **finite minted faucet** (not an externally-funded treasury or LINK balance), which requires tighter discipline: break-even not margin, capped escalation not uncapped redo(), one-category not do-all.

The load-bearing architectural decision is already locked: the router lives on `AfKing.sol`. This keeps the money-moving `autoBuy` path internal (no new cross-contract trust edges on the money path), reuses AfKing's existing `creditFlip` authorization and stall-multiplier logic, and avoids introducing the game-as-caller-of-AfKing trust inversion. The advance bounty moves to the router; standalone `advanceGame()` becomes an unrewarded liveness fallback. The stall multiplier (1/2/4/6, possibly extended ceiling) is the sole liveness lever — the base bounty is intentionally calibrated below gas at normal prices so only the stall-escalated reward pulls in keepers for lagging work. Mid-day ticket processing (the `day == dailyIdx` partial-drain case, rewarded at AdvanceModule.sol line 225) counts as router-rewardable advance-leg work.

The milestone's top risk is the **advance-timing / VRF-freeze surface**: re-homing the advance bounty into a router that also runs `autoBuy`/`autoOpen` means a single keeper tx now bundles the daily-tick consume with other state-mutating work. `_applyDailyRng` adds `totalFlipReversals` (player-controllable) to the raw VRF word at AdvanceModule.sol lines 1838-1844 — that nudge must remain frozen between rng-request and unlock even when the consume fires from inside the router. The v45 VRF-freeze invariant is the hard floor and must be re-attested at SPEC. A second risk is the **one-category-per-call structural invariant**: the router must structurally early-return after the first rewarded category (no fall-through), or a single tx can stack advance + open + buy bounties and break the faucet bound. Both must be locked at SPEC and proven at TST/TERMINAL before the diff ships.

---

## Key Findings

### Recommended Stack

No new dependencies. The toolchain (Foundry + Hardhat, solc 0.8.34, via_ir=true, evm_version=paris, optimizer_runs=200) and the reward rail (BurnieCoinflip.creditFlip, illiquid flip-credit bounty, finite faucet pool) are already in tree. The router reuses every existing pattern without reinvention.

**Core technologies (all existing, no change):**
- `AfKing.sol` (v48.0 HEAD 0cc5d10f): `BOUNTY_ETH_TARGET`, stall multiplier ladder lines 823-838, single `creditFlip` at line 846, cursor/self-partition — the router's home contract.
- `DegenerusGameAdvanceModule.sol`: `ADVANCE_BOUNTY_ETH = 0.005 ether` line 147, three advance-bounty `creditFlip` sites lines 189/225/468 (all to be deleted), stall multiplier lines 238-255, day-start offset formula (day-1 + DEPLOY_DAY_BOUNDARY)*1days + 82620 lines 243-246 — single source of truth for the multiplier.
- `DegenerusGame.sol` lines 1536-1632: `AUTO_GAS_PRICE_REF = 0.5 gwei` line 1539, fixed gas-unit constants, autoOpen/autoResolve, VRF-orphan skip gate, per-item try/catch isolation.
- `test/gas/CrankOpenBoxWorstCaseGas.t.sol` and `CrankResolveBetWorstCaseGas.t.sol` and `SweepPerPlayerWorstCaseGas.t.sol`: established worst-case-first / per-item-marginal gas harness idiom. The router needs a `RouterWorstCaseGas.t.sol` in the same idiom.
- Foundry --isolate mode: required for vm.snapshotGas section snapshots; use for per-tx router overhead derivation.

**What NOT to use:** Chainlink Automation, Gelato resolver, Keep3r Network job registration, or any new dedicated keeper-relayer contract. Never read tx.gasprice/gasleft() for reward sizing (REW-03 gameable surface). Never use `forge test --gas-report` numbers as the calibration peg.

### Expected Features

**Must have (all v49.0):**
- Single `doWork(maxCount)` entrypoint: one category per call, priority advance-if-due → autoOpen → autoBuy. Structural early-return after first rewarded category — not a comment, a code invariant.
- Cheap no-work no-op / early-revert: O(1) predicates only (never loops over growable sets).
- Advance bounty re-homed; standalone `advanceGame()` = unrewarded fallback (fully functional, just unpaid); `ADVANCE_BOUNTY_ETH` deleted from AdvanceModule.
- `advanceGame` returns (uint8 mult, bool rewardable) — design 1, single source of truth for stall math stays in the module.
- Break-even at 0.5 gwei BURNIE peg, derived from worst-case-first per-item marginal gas (CR-01: marginal not single-item total).
- 1/2/4/6 stall multiplier kept; possibly one or two higher tiers for extreme stalls (decide at SPEC after GAS phase sizing).
- Faucet bound + no-self-crank-loop proof re-attested under the new router composition.
- No-cost gas micro-opts: MintModule nested-mapping storage pointer (DegenerusGameMintModule.sol lines 671/398), AfKing autoBuy claimable hoist (lines 691/722). Both behavior-identical, gas-only.

**Should have (decide at SPEC from GAS data):**
- Extended stall ceiling beyond 6x — only if GAS phase shows 6x insufficient at stressed gas price; bounded against finite faucet pool.

**Defer (explicitly out of v49.0):**
- autoResolve in the router — deliberately excluded (different gas profile, WWXRP zero-reward carve-out).
- Off-chain keeper indexer / discovery UI — separate frontend track.
- SWAP cash-share tighten — USER accepted current value as canonical.

### Architecture Approach

The router lives on `AfKing.sol` as a new `doWork(maxCount)` function. `autoBuy` is refactored to internal `_autoBuy(maxCount)` with a thin external wrapper (behavior-identical). The router calls IGame(GAME).advanceGame() and IGame(GAME).autoOpen(maxCount) as external calls to already-permissionless game entrypoints; callee-paid bounties stay in-callee and the router does NOT double-pay them. The only bounty the router itself pays is the re-homed advance bounty via AfKing's existing creditFlip authorization. The three creditFlip sites in AdvanceModule.sol (lines 189/225/468) are deleted; advanceGame becomes unrewarded and returns (uint8 mult, bool rewardable).

**Major components:**
1. `AfKing.doWork(maxCount)` — new unified entrypoint; O(1) priority predicates; dispatches one category; pays re-homed advance bounty only; structural early-return; no double-pay on open/buy branches.
2. `DegenerusGameAdvanceModule.advanceGame` (modified) — unrewarded; returns (uint8 mult, bool rewardable); all timing/stall math stays here (single source of truth for day-start epoch).
3. `DegenerusGame.advanceGame` wrapper (line 275, modified) — decodes and forwards the delegatecall return to external callers.
4. `DegenerusGame.autoOpen`/`autoResolve` — unchanged in behavior; each pays its own in-callee gas-peg reward.
5. `BurnieCoinflip.creditFlip` — shared bounty rail; AfKing already authorized; no new authorization edge.
6. New O(1) discovery views: advanceDue() (covers both new-day and partial-drain cases), boxesPending() (boxPlayers[activeIndex].length > boxCursor AND lootboxRngWordByIndex[activeIndex] != 0); buys-pending via AfKing-local cursor reads.

**Files touched:**
- AfKing.sol — MODIFIED (add doWork, refactor autoBuy to internal, re-peg BOUNTY_ETH_TARGET, pay re-homed advance bounty, claimable-hoist micro-opt)
- DegenerusGameAdvanceModule.sol — MODIFIED (delete 3 creditFlip sites, add return value)
- DegenerusGame.sol — MODIFIED (forward advanceGame return, add discovery views; MintModule pointer micro-opt)
- IDegenerusGame.sol + IDegenerusGameModules.sol — MODIFIED (new views, updated advanceGame signature)

### Critical Pitfalls

1. **Advance-timing / VRF-freeze violation** — _applyDailyRng adds player-controllable totalFlipReversals to the raw VRF word at AdvanceModule lines 1838-1844. A paid router advance leg creates incentive to be the actor who sets this nudge before the consume tx. Prevention: hold v45 freeze invariant as hard floor — re-verify every in-window SLOAD is frozen between rng-request and unlock even when the consume fires from inside the router in the same tx as autoBuy/autoOpen. Lock router's internal ordering at SPEC. Address at: SPEC + TST (freeze-invariant fuzz) + TERMINAL (zero-day-hunter explicit charge).

2. **Bounty-stacking across categories** — if the router falls through to a second category after paying for the first, one tx collects two bounties and the faucet is open. Prevention: structural early-return after the first rewarded category. Assert in tests that no single tx earns more than one category's bounty. Address at: SPEC (lock invariant) + IMPL (structural early-return) + TST + TERMINAL.

3. **Break-even mis-calibration — too-low kills liveness; too-high drains faucet** — peg may not cover stressed mainnet gas and drifts with level if conversion math is not level-invariant. Prevention: worst-case-first gas derivation per category (paper first, then test), peg to per-item marginal (CR-01 lesson), confirm level-invariance, verify extended ceiling covers stressed gas. Address at: GAS phase (primary) + SPEC (ceiling decision) + TERMINAL.

4. **Stall-multiplier recomputed in two places (day-convention off-by-one)** — AfKing _currentDay() uses (ts-82620)/1days (line 887); AdvanceModule uses (day-1+DEPLOY_DAY_BOUNDARY)*1days+82620 (line 243). These are different conventions. Copying the multiplier into the router introduces a money-path off-by-one. Prevention: design 1 — advanceGame returns the multiplier; router never recomputes it. Address at: SPEC (lock design 1) + IMPL + TST.

5. **Unrewarded advance = second-order liveness risk** — after re-homing, standalone advanceGame() is unpaid; rational keepers always go through doWork; a router bug leaves the daily tick depending on charitable/self-interested parties. Prevention: (a) standalone advanceGame remains fully functional; (b) at least one structurally-guaranteed free-fallback caller identified (VAULT/sDGNRS protocol-owned subs, any player with pending jackpot); (c) stall multiplier on router's advance leg as primary backstop; (d) ~120-day death-clock still latches as tertiary. Address at: SPEC + IMPL + TST + TERMINAL.

---

## Implications for Roadmap

Suggested phase shape matches v46.0 (dedicated GAS phase between IMPL and TST). Five phases, 329-333.

### Phase 329: SPEC

**Rationale:** All locked decisions require line-level attestation against v48.0 HEAD (0cc5d10f) before any patch. Four structural invariants (one-category early-return, frozen-state advance consume, single day-start epoch, guaranteed free fallback caller) must be locked in writing before IMPL authors the diff.
**Delivers:** Phase SPEC doc; stall-multiplier design locked (returns from AdvanceModule, design 1); router ordering locked; discovery-view signatures settled (including partial-drain case in advanceDue()); break-even peg targets as placeholders (numbers from GAS); mid-day partial-drain explicitly rewardable; micro-opt scope confirmed; OPEN-C disposition decided (reentrancy guard or composed-CEI proof).
**Addresses:** Features: advance bounty re-home, one-category routing, unrewarded fallback. Avoids: Pitfalls 3 (VRF-freeze ordering), 4 (multiplier dual-convention), 5 (liveness fallback real).
**Research flag:** No additional research needed — attestation and design-finalization only.

### Phase 330: IMPL

**Rationale:** ONE batched USER-APPROVED contracts diff per feedback_batch_contract_approval. Author in producer-before-consumer order: (1) AdvanceModule (delete 3 creditFlip sites, add return value), (2) Game wrapper + discovery views, (3) interfaces, (4) AfKing router + autoBuy refactor + re-peg + micro-opts. HARD STOP at the contract-review boundary.
**Delivers:** The single batched diff (locally compiled/tested, NOT submitted without USER hand-review). Micro-opts ride in the same diff.
**Avoids:** Pitfall 2 (bounty-stacking: structural early-return enforced), Pitfall 4 (no multiplier duplication), Pitfall 6 (reentrancy: CEI on every leg; creditFlip last).
**Research flag:** Standard patterns — no research needed.

### Phase 331: GAS

**Rationale:** Break-even peg cannot be set before worst-case marginal gas is measured. This is the v46 Phase 319 shape exactly. The CR-01 lesson mandates this phase: peg from the amortized per-item marginal over N>=32 items, never a single-item total.
**Delivers:** RouterWorstCaseGas.t.sol; worst-case marginal gas per category + router overhead; calibrated break-even peg constants; stall-multiplier ceiling decision; faucet bound + no-self-crank round-trip check (WR-01-style regression); liveness gas-price band documented.
**Addresses:** Pitfall 2 (mis-calibration), Pitfall 1 (faucet drain), Pitfall 7 (stall multiplier cap to stressed-gas bound).
**Research flag:** No external research needed — all methodology established.

### Phase 332: TST

**Rationale:** Behavioral coverage of the new router composition, especially the structural invariants from SPEC that were not individually testable before the diff exists.
**Delivers:** Router priority-ordering tests (advance>open>buy). Advance UNREWARDED via direct game.advanceGame(); REWARDED via doWork; multiplier honored. No-double-pay across all three branches. Freeze-invariant fuzz extending the v43 RngLockDeterminism harness (perturb totalFlipReversals + in-window SLOADs; assert byte-identical consumed output). Reentrancy regression. Standalone advanceGame drives full tick. Self-crank/Sybil round-trip less-than-or-equal-to 0. Full suite non-widening vs v48 baseline.
**Addresses:** Pitfall 3 (freeze fuzz), Pitfall 4 (single-category-reward-per-tx), Pitfall 5 (non-brick; DoS resistance), Pitfall 6 (reentrancy), Pitfall 8 (standalone advance; death-clock latches).
**Research flag:** No research needed.

### Phase 333: TERMINAL

**Rationale:** 3-skill adversarial sweep + delta-audit + FINDINGS-v49.0 + closure flip. Same shape as v46/v47/v48 TERMINAL.
**Delivers:** Delta-audit (blast radius: AfKing, AdvanceModule, Game wrapper, interfaces); 3-skill sweep (advance-timing/MEV, composed reentrancy, bounty-stacking, stall-multiplier force, router-as-SPOF, faucet drain); audit/FINDINGS-v49.0.md; closure signal MILESTONE_V49_AT_HEAD_<sha>; 5-doc flip. USER-gate at closure boundary (autonomous: false).
**Addresses:** All pitfalls — economic-analyst on faucet/composition; zero-day-hunter on advance-timing, reentrancy, SPOF; contract-auditor on CEI + interface changes.
**Research flag:** Advance-timing MEV surface (Pitfall 3) and composed reentrancy (Pitfall 6) are highest-risk sweep targets — zero-day-hunter should be explicitly charged against same-tx-bundling of advance-consume + buy/open.

### Phase Ordering Rationale

- SPEC before IMPL: four structural invariants must be locked in writing; advanceGame return-signature decision affects all downstream files.
- GAS between IMPL and TST: peg constants are a function of measured worst-case marginal gas — they cannot be a guess (Phase 319 CR-01 proof). Tests must exercise calibrated constants, not placeholders.
- TST before TERMINAL: freeze-invariant fuzz and single-category-reward test are the primary safety net for the two highest-risk pitfalls; sweep must build on a green TST gate.
- Single batched diff: producer-before-consumer authoring order (AdvanceModule → Game wrapper → interfaces → AfKing router) ensures no intermediate state ever ships where advancing is unrewarded.

### Research Flags

No phase in this milestone needs a research sub-phase. All patterns, precedents, and design decisions are fully resolved:
- Phase 329 (SPEC): attestation and design-finalization only. Standard patterns.
- Phase 330 (IMPL): all in-tree. Standard patterns.
- Phase 331 (GAS): methodology established in existing test/gas/ harnesses. Standard patterns.
- Phase 332 (TST): test patterns established from prior milestones. Standard patterns.
- Phase 333 (TERMINAL): adversarial sweep shape identical to v46/v47/v48 TERMINAL. Standard patterns.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Direct source reads of v48.0-closure tree; all patterns in-repo, verified line-level. |
| Features | HIGH | Locked decisions from PROJECT.md; industry precedents well-documented and directly applicable. Stall ceiling extension deferred to GAS-phase data. |
| Architecture | HIGH | All cited file:line grep-verified vs v48.0 HEAD. Router-on-AfKing decision fully reasoned with explicit tradeoff table; design 1 recommended with clear rationale. |
| Pitfalls | HIGH | Source-grounded; all 8 pitfalls anchored to specific mechanisms with phase-to-prevention mappings. |

**Overall confidence:** HIGH

### Gaps to Address

- **Break-even peg constants are placeholders until GAS phase.** BOUNTY_ETH_TARGET and the advance peg must be derived from the worst-case marginal gas harness. GAS phase (Phase 331) is the blocking dependency.
- **Stall ceiling extension decision.** Whether to add tiers beyond 6x and their values cannot be settled at SPEC — depends on whether 6x covers stressed gas at a plausible deep stall. Lock the process at SPEC; GAS derives the answer.
- **Mid-day advance predicate exact form.** The advanceDue() view must cover both new-day (currentDayView() != dailyIdx) AND partial-drain (day == dailyIdx but tickets not fully processed). SPEC must confirm the rewardable flag returned by advanceGame covers both line 189 and line 225 sites.
- **OPEN-C reentrancy disposition.** The router introduces a new multi-boundary composition surface. PLAN-CRANK-DO-WORK-INCENTIVE.md section 9 OPEN-C was not closed for the router. SPEC must decide: strict composed-CEI proof OR nonReentrant guard on doWork. Given feedback_security_over_gas, the guard is cheap insurance.
- **VAULT registered affiliate code pre-condition.** The v48 KEEP-04 wiring must be confirmed valid at v49 HEAD before SPEC can attest the autoBuy affiliate-code passthrough survives the _autoBuy internal refactor.

---

## Sources

### Primary (HIGH confidence)
- contracts/AfKing.sol (v48.0 HEAD 0cc5d10f) — autoBuy line 567, bounty formula line 845, stall ladder lines 823-838, creditFlip line 846, cursor line 577, CEI invariant lines 99-106, day convention line 887
- contracts/DegenerusGame.sol — advanceGame wrapper line 275, autoOpen line 1636, autoResolve line 1587, gas-peg constants lines 1539-1546, rngLocked line 2413, currentDayView line 462
- contracts/modules/DegenerusGameAdvanceModule.sol — ADVANCE_BOUNTY_ETH line 147, creditFlip sites lines 189/225/468, stall multiplier lines 238-255, day-start offset lines 243-246, totalFlipReversals nudge lines 1838-1844
- contracts/interfaces/IDegenerusGame.sol + IDegenerusGameModules.sol — current signatures
- contracts/ContractAddresses.sol — pinned addresses, DEPLOY_DAY_BOUNDARY line 7
- test/gas/CrankOpenBoxWorstCaseGas.t.sol, CrankResolveBetWorstCaseGas.t.sol, SweepPerPlayerWorstCaseGas.t.sol — worst-case-first / per-item-marginal harness idiom
- .planning/PLAN-CRANK-DO-WORK-INCENTIVE.md — section 7 three faucet locks, section 9 OPEN-C/OPEN-D
- .planning/PROJECT.md — v49.0 locked design decisions

### Secondary (MEDIUM confidence)
- Chainlink Automation docs (docs.chain.link) — off-chain-network model to NOT adopt
- Keep3r v2 job docs (github.com/keep3r-network) — per-job work model
- MakerDAO Liquidations 2.0 docs (docs.makerdao.com) — flat tip + redo() cumulative re-incentive
- Gelato resolver docs (docs.gelato.network) — off-chain exec model
- StableSims arXiv 2201.03519 — flat tip more cost-effective than proportional chip for time-to-action
- Foundry gas/snapshotGas docs (getfoundry.sh) — gas-report variance caveat; snapshotGas requires --isolate
- Project memory: v45-vrf-freeze-invariant, feedback_rng_backward_trace, feedback_gas_worst_case, feedback_security_over_gas

---
*Research completed: 2026-05-26*
*Ready for roadmap: yes*
