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
- [x] **FND-01**: The audit subject is byte-frozen at HEAD `a8b702a7`; the baseline diff vs `77580320` is recorded; `git diff` against the frozen SHA is empty throughout the sweep phases. ✅ 388-03 (`388-03-BASELINE-DIFF.md`: pin = `contracts` tree `2934d3d8987a09c5f073549a0cb499f6c5f28620` == `HEAD:contracts`, content sha256 `0c684378…`, `git diff a8b702a7 -- contracts/` empty; the 40-file +4322/−3489 audit-delta recorded with per-family characterization routed to 389-394).
- [x] **FND-02**: The authoritative storage layout is re-derived via `forge inspect storageLayout` at `a8b702a7`; all slot-hardcoded harnesses are recalibrated against the packing-phase slot shifts (Game tail, sDGNRS, BurnieCoinflip, Admin). ✅ 388-01 (layout key + per-harness reconciliation ledger; every moved-field poke confirmed correct, 0 re-derivations; StorageFoundation tail-pack canary 25/25).
- [x] **FND-03**: A GREEN forge + JS regression baseline is established and recorded (supersedes any carried-red ledger); 0 deterministic failures. ✅ 388-03 (`test/REGRESSION-BASELINE-v63.md`: forge **854/0/110**, 122 suites all green, 0 deterministic failures, ZERO carried bucket-A reds — v62's 3 VRF-path invariants now pass 7/7; supersedes the carried-red ledger; Hardhat 1105/121/5 corroborating, carried gameover-VRF-drive harness drift with no hard-floor breach; forge declared PRIMARY).
- [x] **FND-04**: Verifier oracle holes are closed (each invariant test actually exercises its target code); the seven surface-maps are intaken as tracked finding-candidates routed to their sweep phases. ✅ 388-02 (9 changed-surface tests slot-validated vs `forge inspect` @ subject: 7 EXERCISED, 1 game-side+gap-routed, 1 HOLE [legacy RedemptionInvariants 7-INV un-wired claim+stETH leg + stale slots → routed 390, superseded]; decimator-uint32 distribution = missing property → routed 391; `388-02-FINDING-CANDIDATES.md` intakes 45/45 leads from all 7 maps routed 389-394 with per-phase rollup; commits `1e5fd2f7`/`ccf620f1`).

### STORAGE — Packing correctness
- [x] **STORAGE-01**: Every narrowed packed field's width is ≥ its real-world maximum (no silent truncating cast); each narrowing is enumerated with the bound that makes it safe. ✅ ATTESTED 389-02 (both nets; each cast enumerated with its bound — 389-FINDINGS §2a / 389-02-CLAUDE-NET §STORAGE-01).
- [x] **STORAGE-02**: Masked read-modify-write helpers (`_set*`/`_add*`/`_get*`) preserve every co-resident field; round-trip property checks pass. ✅ ATTESTED 389-02 (mask construction + green-baseline pokes; 389-FINDINGS §2a).
- [x] **STORAGE-03**: Cross-module readers and writers of a delegatecall-shared packed slot use identical shift/mask conventions (slot agreement holds by construction). ✅ ATTESTED 389-02 (one inherited storage base + single-sourced helpers; 389-FINDINGS §2a).
- [x] **STORAGE-04**: Level/day-stamped window packs (the two-window `lootboxEvCapPacked`) never evict a still-live key under the real resolve-cursor-lag bound (the 10 ETH EV cap cannot be re-earned). ✅ ATTESTED 389-02 via a cursor-lag PROOF (deferred opens write no cap + live level+1 keying + +1-monotone level → live key set ⊆ {currentLevel,+1}; 389-FINDINGS §2a / 389-02-CLAUDE-NET §STORAGE-04).
- [x] **STORAGE-05**: External ABI getters are preserved for every privatized/packed field (no interface break for off-chain consumers). ✅ ATTESTED 389-02 (sDGNRS + Admin getters preserved; 389-FINDINGS §2a).
- [ ] **STORAGE-06**: No test or harness depends on a hard-coded storage slot that the packing moved (runtime correctness over compile-only green). ⚠ FINDING R-389-01 (389-02): 2 stale test harnesses CONFIRMED vs fresh `forge inspect` — Composition `mintPacked_` slot-10 (is slot 9) vacuous canary + HeroOverride JS `lootboxRngPacked` slot-35 (is slot 34) no-op seed; LOW oracle-integrity, test-only fix, contract unaffected, forge primary baseline intact; DOCUMENTED + ROUTED (not fixed). Council box-cursor candidate REFUTED. See 389-FINDINGS §4a.
- [x] **STORAGE-07**: capBucketCounts cap-exactness — the `≤ maxTotal+4` imprecision is characterized and proven defended by downstream clamps, or tightened. *(folded debt)* ✅ ATTESTED 389-02 (bounds to ≤ maxTotal by trim/remainder construction + 250-clamp + remainder-share; "+4" is a TEST-slack constant, not a contract property; 389-FINDINGS §2a).

### GASID — Gas / refactor behavior-identity
- [x] **GASID-01**: The raw `delegatecall(msg.data)` dispatch resolves the same selector and ABI-decodes identically to the prior typed dispatch for every routed function. ✅ ATTESTED 389-02 (30/30 selectors + shared ABI decoder; 389-FINDINGS §2b).
- [x] **GASID-02**: The hash1/hash2 RNG-byte migrations produce byte-identical keccak preimages (the RNG byte-image is preserved). ✅ ATTESTED 389-02 (operand-width rule: every migrated operand is 32-byte; 389-FINDINGS §2b).
- [x] **GASID-03**: The PriceLookup nibble-table is output-identical to the prior table over the full input domain. ✅ ATTESTED 389-02 (differential = 0 mismatches over the domain; 389-FINDINGS §2b).
- [x] **GASID-04**: The trait-roll consolidation and `_farFutureSeed` extraction are equivalent to the pre-refactor semantics across all inputs, boundaries, and revert paths. ✅ ATTESTED 389-02 (single-hero roll trace + literal seed extraction; 389-FINDINGS §2b).
- [x] **GASID-05**: No gas/refactor edit changed an externally-observable behavior (output / revert / event) — behavior-identity is asserted, not assumed. ✅ ATTESTED 389-02 (anchored on GASID-01..04 + empty expected-red name-set; 389-FINDINGS §2b).

### SOLV — Solvency spine (✅ ATTESTED at `a8b702a7`, Phase 390, both nets on record, 0 CONFIRMED)
- [x] **SOLV-01**: The `claimablePool == Σ claimable + Σ afking` identity holds across every changed credit/debit path (the `_debitClaimableAndAfking` per-half guards). — REFUTED (every spine touch pairs a pool move; 390-FINDINGS §2a).
- [x] **SOLV-02**: The sDGNRS `pendingRedemptionEthValue` backing identity is preserved; `balance + steth.balanceOf(this) ≥ obligations` under the redemption rework. — REFUTED (backing read excludes pending; widths bounded).
- [x] **SOLV-03**: Redemption submit/claim conservation — ethDirect + lootboxEth + forfeitEth equals the released value; no path double-counts or leaks. — REFUTED (legs sum = rolled = release in every branch).
- [x] **SOLV-04**: The dust-lootbox forfeit self-credit is always backed by value actually leaving sDGNRS and never bumps claimable beyond the pending release. — REFUTED (GAME pulls stETH remainder fail-closed before crediting; backed under MAX reservation).
- [x] **SOLV-05**: The redemption CLAIM path's liveness-window ordering cannot strand or double-credit across the `handleGameOverDrain` totalFunds snapshot / `livenessTriggered()→gameOver()` latch. — REFUTED (reserve segregated out of drain totalFunds; tx-atomicity + single snapshot + atomic release/slot-delete).
- [x] **SOLV-06**: CEI / yield-surplus reentrancy is closed on the ETH/stETH payout legs (stETH-before-ETH ordering; the V62-03 class). — REFUTED (CEI on all 4 payout legs; RedemptionStethFallback 10/10 anchor).
- [x] **SOLV-07**: JackpotModule delta-fold completeness — no pool is credited or deleted twice across the rework. — REFUTED (whalePassCost single-counted; cross-model divergence resolved, gemini HIGH lead REFUTED at frozen source).

### RNG — Freeze spine
- [x] **RNG-01**: Every new/changed RNG consumer is traced backward to confirm the VRF word was unknown when the player committed their input. ✅ ATTESTED 391-02 (both nets; per-consumer commitment points — 391-FINDINGS §2a / 391-02-CLAUDE-NET §A).
- [x] **RNG-02**: The decimator `uint32` claim-seed retains an adequate entropy floor, is non-grindable, and yields an unbiased aggregate per-bucket reward distribution across many winners of one level. ✅ ATTESTED 391-02 (both nets; dedicated keccak random-oracle distribution argument = unbiased + non-grindable; missing distribution oracle ROUTED test-hardening — 391-FINDINGS §3b).
- [x] **RNG-03**: The box-spin resolvers (WWXRP / BURNIE / ETH spins) are one-shot and replay-safe (no double-resolve via `lastOpenedDay` or the spin cursor). ✅ ATTESTED 391-02 (both nets; record-clear-before-resolution + delegatecall `address(this)!=GAME` guard — 391-FINDINGS §2a).
- [x] **RNG-04**: `resolveLootboxDirect` and the spin seeds are domain-separated (no cross-consumer seed collision). ✅ ATTESTED 391-02 (both nets; per-caller domain separation; the cross-round `uint32` collision REFUTED-as-break = benign INFO/LOW via the skeptic dual-gate — 391-FINDINGS §3a).
- [x] **RNG-05**: The redemption day+1 pre-draw gate (`BurnsBlockedBeforeDailyRng`) holds on the burn side; no zero-seed grind. ✅ ATTESTED 391-02 (both nets; the gate pins `currentPeriod <= dailyIdx` so day+1 is undrawn at burn time — 391-FINDINGS §2a).
- [x] **RNG-06**: Every SLOAD inside an rng-window over the repacked slots is freeze-invariant (no player-controllable non-VRF read consumed alongside the word). ✅ ATTESTED 391-02 (both nets; in-window SLOAD enumeration over slots 10/34/35+dailyIdx; EntropyLib byte-identity + activityScore frozen-snapshot — 391-FINDINGS §2a).

### ECON — Reward game-theory
- [x] **ECON-01**: Reward accrual saturates below every hard ceiling (activity-score cap, EV/ROI band, decimator clamps); no unbounded grind exists. ✅ ATTESTED at `a8b702a7` (392-03, both nets; per-surface bounded-accrual sweep — every consumer saturates below the 65,534 hard cap [EV 40,000 / ROI 30,500 / decimator streak-clamp 100]; the uncapped quest-streak widens no ceiling).
- [x] **ECON-02**: EV-neutrality is re-verified in code for each redistribution against the documented claims (spins, ticket-roll budget ×11/9, far-future 1.5×/0.875×, variance ranges centered on the old EV). ✅ ATTESTED at `a8b702a7` (392-03, both nets; in-code arithmetic — split 40/15/15/15/10/5 (roll%20), ×11/9=19,678 → 8,855==8,855, far/near 1.000, variance Σ=0.78595==0.786×).
- [x] **ECON-03**: The two genuine EV changes match documented intent (floor 90% / ceiling 145% / score-to-ceiling 40,000; recycle bonus ≥3-whole-ticket gate). ✅ ATTESTED at `a8b702a7` (392-03, both nets; band 9000-14500 @ 40,000 confirmed in code; recycle gate ≥3-whole-ticket with drain-detection deleted).
- [x] **ECON-04**: No closed positive-EV money pump exists across the recycle / spin / recirc / carry / affiliate compositions. ✅ ATTESTED at `a8b702a7` (392-03, both nets; the gemini HIGH money-pump candidate REFUTED via per-leg liquid accounting + the skeptic dual-gate — value-out < won-claimable value-in every iteration: kicker illiquid/flip-gated ≈0.030·V, box sub-unity, value-in won-first, recirc depth 1, EV uplift 10-ETH-capped).
- [x] **ECON-05**: Scarce-asset invariants hold under the new channels — the box WWXRP-spin whale-half-pass (15% of opens, S=9) stays near-unfarmable (quantify P(S=9) × boxes-per-pass). ✅ ATTESTED at `a8b702a7` (392-03, both nets; P(S=9)≈6.74e-8 / ~99M boxes-per-pass; the global per-bracket flag caps supply at one per bracket across box+bet routes — BY-DESIGN cost-curve change, supply intact).
- [x] **ECON-06**: The quest-streak (now uncapped, halved) is rate-bounded and decay-gated; the activity-score ceiling is reachable only by the intended sustained effort. ✅ ATTESTED at `a8b702a7` (392-03, both nets; the gemini HIGH streak-pump candidate REFUTED at source + skeptic dual-gate — the afking↔manual same-day double-channel does not exist [completionMask dedup + afking slot-0 skip + mutually-exclusive compute]; ≤3/day rate-bound, slot-0-only decay anchor).

### BURNIE — Coinflip / emission subsystem
- [x] **BURNIE-01**: The survive-a-coinflip-before-mint invariant holds across every BURNIE source (seed stakes, spin double-or-nothing, normal mint). ✅ ATTESTED at `a8b702a7` (392-04, both nets; per-source survive-gate enumeration — seeds win-gated, per-bet survival flip nets once, box spins survival-flip mint-only, keeper bounty + afking = flip stakes that survive a later flip, redemption leg net-new-BURNIE=0; FC-392-19 no-box-on-BURNIE-bet).
- [x] **BURNIE-02**: Total emission is conserved versus the removed 2M+2M lumps (the 200k/day × 20d seed schedule sums correctly; no over/under-emission). ✅ ATTESTED at `a8b702a7` (392-04, both nets; 200k×20×2 = 8M stake / ~4M EV replaces 2M+2M; zero-start supply; seed→arm handoff off-by-one-clean; BurnieEmissionSeeds 5/5).
- [x] **BURNIE-03**: The auto-rebuy latch (`sdgnrsAutoRebuyArmed`) is monotonic and cannot be entered/exited to double-claim or strand funds. ✅ ATTESTED at `a8b702a7` (392-04, both nets; set once at epoch≥20, never cleared, no double-mint, no carry-extraction toggle [`setCoinflipAutoRebuy(sDGNRS)` never called]; FC-392-18 latent branch unreachable).
- [ ] **BURNIE-04**: `claimCoinflipCarry` accounting is correct and the redemption BURNIE backing is complete — the auto-rebuy carry is reflected in the sDGNRS redemption backing (the surface-map FA-1 lead). ⚠ ADJUDICATED at `a8b702a7` (392-04, both nets) = **FINDING (CONFIRMED MED — under-credit/strand)**: `claimCoinflipCarry` accounting is correct (FC-392-13 disjoint-partition REFUTED), BUT the redemption backing is NOT complete — the `autoRebuyCarry` is INVISIBLE to `previewClaimCoinflips` + the `redeemBurnieShare` waterfall and has no sDGNRS-reachable liquidation path ⇒ redeemers progressively under-credited post-seed (conservative, off the ETH spine). ROUTED to a gated USER-hand-review boundary (USER may rule BY-DESIGN). Resolution pending the gated decision → `392-FINDINGS-BURNIE.md` §4a/§5a.
- [ ] **BURNIE-05**: The VAULT seed-stakes (days 1-20) window-aging forfeiture is confirmed intended or fixed (the FA-2 lead; ~half the seeded initial emission at risk). ⚠ ADJUDICATED at `a8b702a7` (392-04, both nets) = **FINDING (CONFIRMED-as-risk MED — lost-emission window)**: the VAULT day-1-20 ~2M-expected seed is silently+irreversibly forfeited if the owner does not claim OR arm within the first 30 resolved days (no auto-claim safety net unlike sDGNRS; bounded by the protocol-owned-address timeline + two escape hatches). NOT yet confirmed-intended-or-fixed — ROUTED to a gated USER-hand-review boundary (the lead "most likely to need a contract change"; USER may rule BY-DESIGN with a deploy-runbook MUST). Resolution pending the gated decision → `392-FINDINGS-BURNIE.md` §4b/§5b.
- [x] **BURNIE-06**: The packed stake lanes + the 8-bit 3-state day-result round-trip losslessly; BURNIE stays off the ETH/`claimablePool` solvency path. ✅ ATTESTED at `a8b702a7` (392-04, both nets; 128-bit wei stake lanes + 8-bit 3-state day-result [win∈[50,156], no win in [2,49]] round-trip losslessly, masked sibling preservation; BURNIE minted/burned only, off the ETH spine).

### ACCESS — New permissionless entrypoints, access control & reentrancy
- [x] **ACCESS-01**: Every permissionless claim credits only the beneficiary (no third-party ETH push or forced-credit grief). ✅ ATTESTED 393-02 (both nets; per-entrypoint beneficiary credit — value to `player` never `msg.sender`; post-gameOver self-claim-only; 393-FINDINGS §2a).
- [x] **ACCESS-02**: The keeper box-bounty is net-negative versus real prevailing gas (5–50+ gwei, not the 0.5-gwei `AUTO_GAS_PRICE_REF` peg) plus flip-credit illiquidity, and is un-manufacturable. ✅ ATTESTED 393-02 (both nets; net-negative 10x/40x/100x @5/20/50 gwei × ~0.30 illiquidity + un-manufacturable per real burn + FC-390-06 issuance bound; redemption 24e12 / decimator 15e12 distinct, both net-negative; real-gas number + redemption-bounty regression mirror ROUTED test-hardening — 393-FINDINGS §2a/§3/§4b).
- [x] **ACCESS-03**: Forced claim-timing by a permissionless caller cannot materially reduce a winner's reward or steer an outcome. ✅ ATTESTED 393-02 (both nets; magnitude inert — reward frozen at resolution, `_rollTargetLevel` offset distribution frozen-seed-invariant, only the level anchor moves, forced earlier beneficial/neutral; MONITOR posture — 393-FINDINGS §2a/§2b).
- [x] **ACCESS-04**: Partial-balance redemption-leg solvency holds under same-block bursts. ✅ ATTESTED 393-02 (both nets; Σ legs == Σ rolled == Σ released, each leg fresh-`bal` + stETH-remainder fail-closed, MAX(175%) reservation covers, ETH-drain shifts to stETH leg — no strand/under-pull; same-block-burst oracle ROUTED test-hardening — 393-FINDINGS §2a/§2b).
- [x] **ACCESS-05**: The freeze / rngLocked / liveness / gameOver gates are intact on all new and widened entrypoints; reentrancy is closed across the ETH/stETH legs. ✅ ATTESTED 393-02 (both nets; per-entrypoint gates + slot-delete-before-untrusted-call CEI + stETH-first/ETH-last + SDGNRS-gated callees + internal-only yield-surplus + V62-03 reorder intact — 393-FINDINGS §2a).

### MUT — Mutation campaign *(folded debt)*
- [x] **MUT-01** *(BOUNDED — 395-01/-02/-03)*: The mutation campaign is run over the frozen subject with fix-site functions + a comprehensive oracle scope (per the mutation-oracle lesson — narrow per-file oracles produce false survivors); via_ir, CI/overnight pacing. **Corrected harness built+validated; the campaign ran BOUNDED — 3 of 6 SPINE targets fully scored (`BitPackingLib` · `DegenerusGameStorage` · `StakedDegenerusStonk`), the 3 RNG/v63-changed modules (`BurnieCoinflip` · `DegenerusGameLootboxModule` · `DegenerusGameDecimatorModule`) CI-DEFERRED with the exact `run-campaign-v63.sh --single <Contract>` resume command (via_ir ≈ overnight; surface already covered by the 389-394 dual-net).** The corrected comprehensive-oracle harness runs (the 395-01 false-survivor mistake replaced); subject byte-frozen `a8b702a7` throughout. (commits `2bbda9c1`/`865a780e`/`ca1fe55a` harness, `e067c714` run+score, `b46ac5ba` bounded close)
- [x] **MUT-02** *(395-02/-03)*: The mutation score is measured and recorded; surviving mutants are triaged (false-survivor vs genuine oracle gap). **3 SPINE targets scored: `BitPackingLib` (23/78 = 29.5%, 55 survivors) · `DegenerusGameStorage` (1 real survivor) · `StakedDegenerusStonk` (killed=152 uncaught=78, 76 distinct survivors); 132 distinct survivors total — EVERY survivor triaged in SURVIVOR-TRIAGE-v63.md = 125 FALSE + 7 GENUINE (G-BPL-01 + K1-K6).** Per-target scores append on the CI-deferred resume of the 3 RNG modules. (commits `e067c714`, `af44ea1b`, `b46ac5ba`)
- [x] **MUT-03** *(395-03)*: Each genuine surviving mutant is either killed by a new test or routed to a finding. **All 7 GENUINE survivors KILLED-BY-TEST in `test/mutation/MutationKills.t.sol` (8 tests, each validated fail-with-mutation / pass-without); 0 ROUTED, 0 contract defects (matches the 389-394 dual-net 0-defect result). MUTATION-FINDINGS-v63.md carries the per-survivor disposition ledger; subject byte-frozen `a8b702a7` (tree `2934d3d8…`) throughout.** (commits `c9dbc7ea` kill-tests, `b46ac5ba` triage+report, `fd3eb053` findings)

### LEGACY — v50/v51/v52 consolidated debt *(folded)*
- [x] **LEGACY-01**: The v50 surface is swept — the whale-pass O(1) deferred-claim path + the box-open record. *(394-03: both nets on record; 0 CONFIRMED; value-equivalence + freeze attested, claim-time horizon BY-DESIGN D-04/D-20.)*
- [x] **LEGACY-02**: The v50 surface — AFSUB pass-gating (`validThroughLevel` eviction/refresh + OPEN-E re-attest) + the MINTDIV index alignment. *(394-03: both nets on record; 0 CONFIRMED; AFSUB boundary/consent as-coded BY-DESIGN, MINTDIV count-lockstep exact, quadrant REFUTED.)*
- [x] **LEGACY-03**: The v51 surface — claimBingo color-completion / BingoModule (3-tier reward selection, per-player `(level,quadrant)` dedup, freeze-safety of the post-resolution `traitBurnTicket` read). *(394-04: both nets on record; 0 CONFIRMED; freeze REFUTED [read over a frozen population, sole writer in the swapped/frozen buffer], tier-precedence + dedup + CEI + empty-pool + gameOver REFUTED [CEI-tight].)*
- [x] **LEGACY-04**: The v51 surface — the sDGNRS `Pool.Reward` rebalance + the jackpot final-day `Pool.Reward` deletion side-effects. *(394-04: both nets on record; 0 CONFIRMED; rebalance REFUTED [split conserved sum=BPS_DENOM, every draw clamps, no stale-split consumer]; final-day deletion REFUTED — premise VACUOUS [no sDGNRS Reward final-day path; orphaned at v51 D-12; real surface = ETH pools, FUZZ-05-conserved] + 1 INFO stale-comment.)*
- [x] **LEGACY-05**: `audit/FINDINGS-v50.0.md` is authored (the deferred v50 deliverable). *(394-03: authored matching the FINDINGS-v62.0 format; both nets attested; 0 actionable.)*
- [x] **LEGACY-06**: `audit/FINDINGS-v51.0.md` is authored (the deferred v51 deliverable). *(394-04: authored matching the FINDINGS-v62.0 format; both nets attested; 0 actionable; LEGACY-04b premise VACUOUS recorded.)*

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
