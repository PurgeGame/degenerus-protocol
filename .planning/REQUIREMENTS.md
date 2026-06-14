# Requirements: Milestone v63.0 — Post-v62 Audit (Critical Invariants + Reward Game-Theory)

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

**Milestone goal:** Run the established cross-model-led, foundation-first audit over the ~60 commits (40 contract files, +4322/−3489) that landed since the v62.0 close `77580320` **without** a formal audit-milestone close — storage packing, the BURNIE zero-start emission rework, gas-identity refactors, four new permissionless/keeper entrypoints, and the reward/economic rebalances — confirming **solvency, RNG-freeze, storage-layout correctness**, and the **game-theory of the rebalanced rewards** all hold, then ship `audit/FINDINGS-v63.0.md` + closure. Per USER (2026-06-14), **fold in** the deferred audit debt (full mutation campaign + capBucketCounts exactness + the v50/v51/v52 consolidated cross-model debt).

**Baseline:** v62.0 closure subject `77580320` (last formally audited frozen point).
**Subject:** HEAD `a8b702a7` — byte-frozen at FOUNDATION (USER: freeze at HEAD now; working tree clean except the untracked player-facing `PLAYER-PURCHASE-REWARDS.html`).
**Method:** **Council + Claude BOTH** — the Gemini+Codex cross-model council (`gemini`/`codex` CLIs) AND deep Claude-led adversarial Workflows run as two independent finding nets in every sweep phase; Claude builds the foundation, orchestrates, adjudicates against the frozen subject, runs the skeptic gate, and synthesizes. Honors the v62 cross-model premise and adds the Claude Workflow net.
**Posture:** AUDIT-ONLY by default — no NEW contract change planned; a council/Workflow-surfaced, adjudicated, skeptic-passed finding routes to a gated fix (USER hand-review, batched, never pre-approved); otherwise document-only.
**Design-intent anchor:** the reward rebalances are documented in `.planning/PAPER-REWARD-CHANGES-BRIEF.md` (mostly EV-neutral redistributions; only the EV-multiplier lift + recycle-bonus relaxation change EV) → the ECON sweep VERIFIES those stated claims rather than re-litigating intent.
**Surface-map foundation:** seven read-only dimension maps (`.planning/v63-surface-map/`) verified against source found **0 HIGH on inspection** — the change set preserves the `claimablePool` identity, the sDGNRS backing identity, the RNG-freeze spine, and the packing value-identities; the MED design-intent leads they surfaced are the prime sweep targets.

---

## v63.0 Requirements

### FND — Foundation (green baseline + subject freeze)
- [ ] **FND-01**: The audit subject is byte-frozen at HEAD `a8b702a7`; the baseline diff vs `77580320` is recorded; `git diff` against the frozen SHA is empty throughout the sweep phases.
- [ ] **FND-02**: The authoritative storage layout is re-derived via `forge inspect storageLayout` at `a8b702a7`; all slot-hardcoded harnesses are recalibrated against the packing-phase slot shifts (Game tail, sDGNRS, BurnieCoinflip, Admin).
- [ ] **FND-03**: A GREEN forge + JS regression baseline is established and recorded (supersedes any carried-red ledger); 0 deterministic failures.
- [ ] **FND-04**: Verifier oracle holes are closed (each invariant test actually exercises its target code); the seven surface-maps are intaken as tracked finding-candidates routed to their sweep phases.

### STORAGE — Packing correctness
- [ ] **STORAGE-01**: Every narrowed packed field's width is ≥ its real-world maximum (no silent truncating cast); each narrowing is enumerated with the bound that makes it safe.
- [ ] **STORAGE-02**: Masked read-modify-write helpers (`_set*`/`_add*`/`_get*`) preserve every co-resident field; round-trip property checks pass.
- [ ] **STORAGE-03**: Cross-module readers and writers of a delegatecall-shared packed slot use identical shift/mask conventions (slot agreement holds by construction).
- [ ] **STORAGE-04**: Level/day-stamped window packs (the two-window `lootboxEvCapPacked`) never evict a still-live key under the real resolve-cursor-lag bound (the 10 ETH EV cap cannot be re-earned).
- [ ] **STORAGE-05**: External ABI getters are preserved for every privatized/packed field (no interface break for off-chain consumers).
- [ ] **STORAGE-06**: No test or harness depends on a hard-coded storage slot that the packing moved (runtime correctness over compile-only green).
- [ ] **STORAGE-07**: capBucketCounts cap-exactness — the `≤ maxTotal+4` imprecision is characterized and proven defended by downstream clamps, or tightened. *(folded debt)*

### GASID — Gas / refactor behavior-identity
- [ ] **GASID-01**: The raw `delegatecall(msg.data)` dispatch resolves the same selector and ABI-decodes identically to the prior typed dispatch for every routed function.
- [ ] **GASID-02**: The hash1/hash2 RNG-byte migrations produce byte-identical keccak preimages (the RNG byte-image is preserved).
- [ ] **GASID-03**: The PriceLookup nibble-table is output-identical to the prior table over the full input domain.
- [ ] **GASID-04**: The trait-roll consolidation and `_farFutureSeed` extraction are equivalent to the pre-refactor semantics across all inputs, boundaries, and revert paths.
- [ ] **GASID-05**: No gas/refactor edit changed an externally-observable behavior (output / revert / event) — behavior-identity is asserted, not assumed.

### SOLV — Solvency spine
- [ ] **SOLV-01**: The `claimablePool == Σ claimable + Σ afking` identity holds across every changed credit/debit path (the `_debitClaimableAndAfking` per-half guards).
- [ ] **SOLV-02**: The sDGNRS `pendingRedemptionEthValue` backing identity is preserved; `balance + steth.balanceOf(this) ≥ obligations` under the redemption rework.
- [ ] **SOLV-03**: Redemption submit/claim conservation — ethDirect + lootboxEth + forfeitEth equals the released value; no path double-counts or leaks.
- [ ] **SOLV-04**: The dust-lootbox forfeit self-credit is always backed by value actually leaving sDGNRS and never bumps claimable beyond the pending release.
- [ ] **SOLV-05**: The redemption CLAIM path's liveness-window ordering cannot strand or double-credit across the `handleGameOverDrain` totalFunds snapshot / `livenessTriggered()→gameOver()` latch.
- [ ] **SOLV-06**: CEI / yield-surplus reentrancy is closed on the ETH/stETH payout legs (stETH-before-ETH ordering; the V62-03 class).
- [ ] **SOLV-07**: JackpotModule delta-fold completeness — no pool is credited or deleted twice across the rework.

### RNG — Freeze spine
- [ ] **RNG-01**: Every new/changed RNG consumer is traced backward to confirm the VRF word was unknown when the player committed their input.
- [ ] **RNG-02**: The decimator `uint32` claim-seed retains an adequate entropy floor, is non-grindable, and yields an unbiased aggregate per-bucket reward distribution across many winners of one level.
- [ ] **RNG-03**: The box-spin resolvers (WWXRP / BURNIE / ETH spins) are one-shot and replay-safe (no double-resolve via `lastOpenedDay` or the spin cursor).
- [ ] **RNG-04**: `resolveLootboxDirect` and the spin seeds are domain-separated (no cross-consumer seed collision).
- [ ] **RNG-05**: The redemption day+1 pre-draw gate (`BurnsBlockedBeforeDailyRng`) holds on the burn side; no zero-seed grind.
- [ ] **RNG-06**: Every SLOAD inside an rng-window over the repacked slots is freeze-invariant (no player-controllable non-VRF read consumed alongside the word).

### ECON — Reward game-theory
- [ ] **ECON-01**: Reward accrual saturates below every hard ceiling (activity-score cap, EV/ROI band, decimator clamps); no unbounded grind exists.
- [ ] **ECON-02**: EV-neutrality is re-verified in code for each redistribution against the documented claims (spins, ticket-roll budget ×11/9, far-future 1.5×/0.875×, variance ranges centered on the old EV).
- [ ] **ECON-03**: The two genuine EV changes match documented intent (floor 90% / ceiling 145% / score-to-ceiling 40,000; recycle bonus ≥3-whole-ticket gate).
- [ ] **ECON-04**: No closed positive-EV money pump exists across the recycle / spin / recirc / carry / affiliate compositions.
- [ ] **ECON-05**: Scarce-asset invariants hold under the new channels — the box WWXRP-spin whale-half-pass (15% of opens, S=9) stays near-unfarmable (quantify P(S=9) × boxes-per-pass).
- [ ] **ECON-06**: The quest-streak (now uncapped, halved) is rate-bounded and decay-gated; the activity-score ceiling is reachable only by the intended sustained effort.

### BURNIE — Coinflip / emission subsystem
- [ ] **BURNIE-01**: The survive-a-coinflip-before-mint invariant holds across every BURNIE source (seed stakes, spin double-or-nothing, normal mint).
- [ ] **BURNIE-02**: Total emission is conserved versus the removed 2M+2M lumps (the 200k/day × 20d seed schedule sums correctly; no over/under-emission).
- [ ] **BURNIE-03**: The auto-rebuy latch (`sdgnrsAutoRebuyArmed`) is monotonic and cannot be entered/exited to double-claim or strand funds.
- [ ] **BURNIE-04**: `claimCoinflipCarry` accounting is correct and the redemption BURNIE backing is complete — the auto-rebuy carry is reflected in the sDGNRS redemption backing (the surface-map FA-1 lead).
- [ ] **BURNIE-05**: The VAULT seed-stakes (days 1-20) window-aging forfeiture is confirmed intended or fixed (the FA-2 lead; ~half the seeded initial emission at risk).
- [ ] **BURNIE-06**: The packed stake lanes + the 8-bit 3-state day-result round-trip losslessly; BURNIE stays off the ETH/`claimablePool` solvency path.

### ACCESS — New permissionless entrypoints, access control & reentrancy
- [ ] **ACCESS-01**: Every permissionless claim credits only the beneficiary (no third-party ETH push or forced-credit grief).
- [ ] **ACCESS-02**: The keeper box-bounty is net-negative versus real prevailing gas (5–50+ gwei, not the 0.5-gwei `AUTO_GAS_PRICE_REF` peg) plus flip-credit illiquidity, and is un-manufacturable.
- [ ] **ACCESS-03**: Forced claim-timing by a permissionless caller cannot materially reduce a winner's reward or steer an outcome.
- [ ] **ACCESS-04**: Partial-balance redemption-leg solvency holds under same-block bursts.
- [ ] **ACCESS-05**: The freeze / rngLocked / liveness / gameOver gates are intact on all new and widened entrypoints; reentrancy is closed across the ETH/stETH legs.

### MUT — Mutation campaign *(folded debt)*
- [ ] **MUT-01**: The full mutation campaign is run over the frozen subject with fix-site functions + a comprehensive oracle scope (per the mutation-oracle lesson — narrow per-file oracles produce false survivors); via_ir, CI/overnight pacing.
- [ ] **MUT-02**: The mutation score is measured and recorded; surviving mutants are triaged (false-survivor vs genuine oracle gap).
- [ ] **MUT-03**: Each genuine surviving mutant is either killed by a new test or routed to a finding.

### LEGACY — v50/v51/v52 consolidated debt *(folded)*
- [ ] **LEGACY-01**: The v50 surface is swept — the whale-pass O(1) deferred-claim path + the box-open record.
- [ ] **LEGACY-02**: The v50 surface — AFSUB pass-gating (`validThroughLevel` eviction/refresh + OPEN-E re-attest) + the MINTDIV index alignment.
- [ ] **LEGACY-03**: The v51 surface — claimBingo color-completion / BingoModule (3-tier reward selection, per-player `(level,quadrant)` dedup, freeze-safety of the post-resolution `traitBurnTicket` read).
- [ ] **LEGACY-04**: The v51 surface — the sDGNRS `Pool.Reward` rebalance + the jackpot final-day `Pool.Reward` deletion side-effects.
- [ ] **LEGACY-05**: `audit/FINDINGS-v50.0.md` is authored (the deferred v50 deliverable).
- [ ] **LEGACY-06**: `audit/FINDINGS-v51.0.md` is authored (the deferred v51 deliverable).

### TERM — Terminal close
- [ ] **TERM-01**: The two finding nets (council + Claude) are consolidated + deduped; the council is re-run on all Claude-REFUTED findings (the v60 LIFECYCLE lesson); the skeptic gate clears before any CATASTROPHE/HIGH.
- [ ] **TERM-02**: Every lead and finding is adjudicated vs the frozen subject; `audit/FINDINGS-v63.0.md` (chmod 444) + `AUDIT-V63-REPORT.html` are produced; any CONFIRMED finding routes to a gated fix (USER hand-review) else document-only.
- [ ] **TERM-03**: Contracts are re-frozen; the closure signal `MILESTONE_V63_AT_HEAD_<sha>` is emitted; all requirements are re-attested; the milestone is flipped.

---

## Future Requirements (deferred)
- None deferred at scoping — the USER folded the previously-deferred debt (mutation campaign, capBucketCounts, v50/v51/v52) INTO this milestone.

## Out of Scope (explicit exclusions)
- **The untracked `PLAYER-PURCHASE-REWARDS.html`** — a player-facing document, not a contract; not part of the audit subject.
- **New gameplay/economic features** — v63 is an audit of the existing post-v62 surface, not a feature rotation. Any new mechanic is a future milestone.
- **The CI mutation/static stack as a product** — the pre-C4A-hardening CI (Slither/Aderyn/size-gate) already exists; v63 consumes it as a tool, it is not a deliverable.

---

## Traceability (requirement → phase)
*Filled by the roadmap. Each requirement maps to exactly one phase (388-396).*

| Category | Requirements | Phase |
|----------|--------------|-------|
| FND | FND-01..04 | 388 FOUNDATION |
| STORAGE | STORAGE-01..07 | 389 PACKING-IDENTITY |
| GASID | GASID-01..05 | 389 PACKING-IDENTITY |
| SOLV | SOLV-01..07 | 390 SOLVENCY-SPINE |
| RNG | RNG-01..06 | 391 RNG-SPINE |
| ECON | ECON-01..06 | 392 ENTROPY-AND-ECON |
| BURNIE | BURNIE-01..06 | 392 ENTROPY-AND-ECON |
| ACCESS | ACCESS-01..05 | 393 PERMISSIONLESS-COMPOSITION |
| LEGACY | LEGACY-01..06 | 394 LEGACY-DEBT |
| MUT | MUT-01..03 | 395 MUTATION |
| TERM | TERM-01..03 | 396 TERMINAL |

**Coverage:** 58 requirements → 9 phases, each requirement mapped to exactly one phase; 0 orphaned, 0 duplicated.
