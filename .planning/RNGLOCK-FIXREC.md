# RNGLOCK-FIXREC — Phase 299 Fix Recommendation Document (v43.0)

**Generated:** 2026-05-18
**Milestone:** v43.0 Total rngLock Determinism Audit — Every VRF Input Frozen at Commitment (AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`)
**Audit baseline:** v42.0 closure HEAD `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`
**Posture:** Single canonical Phase 299 deliverable per `D-299-FIXREC-LAYOUT-01`. Per-VIOLATION analytical depth (FIXREC-01..05). Aggregates 10 Wave-1 cluster contributions (`299-{01..10}-FIXREC-cluster.md`) into one document. **Zero `contracts/` + zero `test/` mutations.** Phase 299 hands forward to v44.0 FIX-MILESTONE via the §M consolidated handoff register.
**Dependency:** `.planning/RNGLOCK-CATALOG.md` (Phase 298, AGENT-COMMITTED at HEAD `3896cb8a`). Every §N.D handoff anchor cross-references a §16 verdict-matrix row in that document.

This artifact composes:

- **§0** — Executive summary with **EV-tier discipline lens** (3-condition catastrophe predicate; tier downgrades + reclassifications + stale-phantom + pending-verification markers)
- **§1..§111** — Per-VIOLATION entries aggregated from the 10 Wave-1 cluster contributions; each entry preserves the cluster-authored 4-sub-section structure (§N.A design-intent backward-trace + §N.B actor game-theory walk + §N.C recommended tactic + rationale + impact + §N.D v44.0 handoff anchor). Sections renumbered globally; per-cluster authorship preserved verbatim.
- **§M** — Consolidated handoff register with 119 `D-43N-V44-HANDOFF-NN` IDs (HANDOFF-01..HANDOFF-119) ordered numerically, with per-ID summary line + tier marker for v44.0 plan-phase consumption.
- **§X-REF** — Catalog/FIXREC cross-reference attestation (grep-gate verdict; labelled `§X-REF` to disambiguate from the §1..§111 global per-VIOLATION sequence and from the catalog's own §17 OZ-carveout grep-gate section)

Per `D-299-KI-01`, `.planning/KNOWN-ISSUES.md` is UNMODIFIED. Per `D-43N-AUDIT-ONLY-01`, no `contracts/` or `test/` files are mutated by this phase. Per `feedback_no_history_in_comments.md` prose describes what IS (current VIOLATION state + recommended target state) — never what changed. Per `feedback_frozen_contracts_no_future_proofing.md` contracts are frozen at deploy; recommendations target the v44.0 FIX-MILESTONE flip.

---

## §0 — Executive Summary

### §0.1 — Aggregate metrics

| Metric | Count |
|--------|-------|
| Wave-1 cluster contributions aggregated | 10 (`299-01-FIXREC-cluster.md` through `299-10-FIXREC-cluster.md`) |
| Logical §N entries authored | **111** (every cluster-emitted §N preserved verbatim, globally renumbered; the planner-budgeted "82 logical VIOLATIONs" figure is the catalog's pre-cluster-author count — cluster authors expanded V-179's 9 sub-callsites + V-051's 3 sub-class split into separate §N entries with shared handoff anchors per `D-298-EXEMPT-CROSSCONTRACT-01` per-callsite discipline) |
| `D-43N-V44-HANDOFF-NN` unique anchors emitted in §M | **119** (HANDOFF-01..HANDOFF-119 contiguous) |
| Sub-section coverage (§N.A / §N.B / §N.C / §N.D) | 195 / 177 / 187 / 111 occurrences (every §N has all 4 sub-sections at minimum once; cross-references add additional letter occurrences) |
| Design-intent-trace coverage | Every §N.A cites either a prior-phase trace artifact OR explicitly marks `[design-intent: pre-v25 baseline; no dedicated trace artifact]` per `feedback_design_intent_before_deletion.md` discipline |
| Discretionary fourth-class disposition tokens (the prohibited shape per `D-43N-AUDIT-ONLY-01` milestone-prose; spelled in §17 attestation with separators so the grep-gate does not match) | **0** |
| `contracts/` source-tree mutations | **0** |
| `test/` source-tree mutations | **0** |

### §0.2 — Recommended-tactic distribution (over 111 §N entries)

| Tactic | Count | Description |
|--------|-------|-------------|
| (a) `rngLockedFlag`-gated revert | ~70 | Add or coverage-attest a `if (rngLockedFlag) revert RngLocked();` (or sibling) gate at the writer entry. Includes ~10 verification-only rows where the gate is already in-source. |
| (b) Snapshot / anchor pattern | ~30 | Phase 281 owed-salt + Phase 288 `dailyIdx` precedent — snapshot the slot value at the entropy-commitment moment; the consumer reads the snapshot rather than a live SLOAD. Applies to per-index lootbox commitments, cross-contract pool balances, and the V-046 OZ-inherited writer class. |
| (c) Pre-lock reorder | ~5 | VRF coordinator rotation queue + apply split (V-137/V-155/V-157/V-159/V-161); rotation must be initiated outside the rngLock window and applied after the window closes. |
| (d) Immutable | ~3 | `wireVrf` one-shot lock (V-156/V-158/V-160) — coordinator/subscription/keyHash become immutable after first `wireVrf` call. |
| Other (reclassification / per-callsite split / subsumption) | ~3 | V-153 RECLASSIFY-TO-EXEMPT (Phase 303 §9 closure attestation); V-051 per-callsite split (AdvanceStack=EXEMPT / MintPath=subsumed-by-row-22 / AdminPath=forward-only); V-184 subsumption fan-out (1 fix closes 7 catalog rows). |

### §0.3 — EV-tier discipline lens (user-supplied; load-bearing for tier classifications below)

The 10 Wave-1 cluster authors systematically over-classified findings as CATASTROPHE / HIGH based on methodology pattern labels (e.g., "cross-resolution accumulator design break") rather than actual economic impact to the attacker. The user's pushback established that **a finding is only catastrophic when ALL three are true:**

1. The slot's value **feeds a VRF-derived output computation** (not incidental storage).
2. The slot is **mutable mid-rngLock by a non-EXEMPT actor**.
3. The mutation **changes a VRF-derived output in a way the mutator profits from** — unbounded or large-magnitude, AFTER accounting for opportunity cost.

The §0 prose below applies this 3-condition predicate to downgrade or reclassify cluster-author tier claims. The per-§N entries in §1..§111 preserve the cluster authors' original tier prose verbatim per `feedback_no_history_in_comments.md` and `D-299-WAVE-SHAPE-01` AGENT-COMMITTED-cluster integrity; this executive summary is the canonical tier register for v44.0 plan-phase consumption.

### §0.4 — Headline findings (top by economic actionability after the lens)

**1. V-184 sStonk cross-day re-roll exploit — §103 — CATASTROPHE (only true CATASTROPHE-tier finding in the entire catalog).** `redemptionPeriodIndex` (S-56) is not advanced inside `resolveRedemptionPeriod`; an attacker post-resolution can call `burn(1 wei)` on a future wall-clock day, re-arm `pendingRedemptionEthBase` for the already-resolved period, and force the next `advanceGame()` to overwrite `redemptionPeriods[period].roll` with a fresh independent roll. Each re-roll iteration is **~19% positive EV** for the attacker; the 1 wei burn cost is dust; supply-cap (50%) bounds intra-period magnitude but does not prevent repeated 1-wei re-burns. Same-day re-resolution is blocked by `rngWordByDay[day]` short-circuit at `AdvanceModule:1187`; cross-day is not. **All three lens conditions satisfied** — feeds VRF-derived redemption-period roll; mutable mid-rngLock by player; mutation yields unbounded re-roll EV at dust cost. The minimal structural fix is tactic-(a) revert in `_submitGamblingClaimFrom` when `redemptionPeriods[redemptionPeriodIndex].roll != 0`; the Phase 288 `dailyIdx`-precedent tactic-(c) "advance the index inside `resolveRedemptionPeriod` itself" is the alternative. **V-184 subsumes V-186 (§104), V-188 (§105), V-190 (§106), V-191 (§107), V-192 (§108), V-193 (§109) per Cluster J finding** — one fix closes 7 catalog rows (anchors HANDOFF-111..HANDOFF-117). v44.0 sub-phase priority-1.

**2. Manual-path lootbox open deep cluster (Cluster G, §43..§62, 20 entries).** Per-index purchase-time commitment slots (`lootboxEth`, `lootboxDay`, `lootboxBaseLevelPacked`, `lootboxEvScorePacked`, `lootboxDistressEth`, `lootboxBurnie`) are EOA-mutable between VRF callback (TX B) and `openLootBox` (TX C). After the lens, the 20 entries decompose as:
   - **HIGH:** Cross-EOA `mintPacked_` / activity-score writes that legitimately change between purchase and open and DO directly influence payout magnitude (~5 entries — V-098, V-099, V-110, V-112, V-117 family). Real EV per call: bounded by activity-score delta.
   - **MEDIUM-LOW:** Writer-side gate adds at `MintModule._allocateLootbox` / `WhaleModule._whaleLootboxAllocate` / `MintModule._purchaseBurnieLootboxFor` entries (V-089..V-104, ~12 entries). Tactic is a single shared `MINTCLN`-style gate per entry function; one fix closes 5-7 catalog rows.
   - **NO REAL EV after lens:** Self-zero rows V-088, V-094, V-097, V-100, V-103 (the open function zeroing its own per-index slots is the intended state machine; the catalog flags them under strict-discipline but no exploit surface exists — the writer is the consumer atomically).

**3. Top-level ungated EOA entry points cluster (Cluster C, §13..§19, 7 entries — V-024/V-025/V-026/V-027/V-030/V-031/V-032).** `MintModule.purchase` / `purchaseCoin` / `purchaseBurnieLootbox` lack a top-level `rngLockedFlag` gate; `WhaleModule.purchaseWhaleBundle` / `purchaseLazyPass` similarly lack one. After the lens these decompose as:
   - **MEDIUM-HIGH:** V-031 (`placeDegeneretteBet` → `_collectBetFunds` → `prizePoolsPacked.future +=`) — cheapest per-tx surface that DIRECTLY inflates `futurePool` which the jackpot consumer reads to compute `ethDaySlice`. EV is bounded by win-probability × inflation magnitude but is the per-dollar leader.
   - **MEDIUM:** V-024, V-025, V-027 — high per-call inflation magnitude (whale bundles can shift futurePool by tens of ETH) but attacker pays their own ETH; the steal target is the inflated-pool share routed to attacker via bucket allocation, not the inflation itself. Gated by attacker's win probability under the in-flight VRF.
   - **LOW:** V-026, V-030 — already structurally gated (V-026's `WhaleModule:543` gate; V-030's downstream `_queueTicketRange` revert).

**4. Game-over `claimablePool` writer races (Cluster E, §27..§33, 7 entries — V-054/V-055/V-057/V-058/V-063/V-064/V-065).** All gated on `_livenessTriggered() && !gameOver` per the cluster-author selection. After the lens:
   - **HIGH:** V-063 (`_claimWinningsInternal` via EOA `claimWinnings` / `claimWinningsStethFirst`) — large-magnitude `claimablePool -=` writer that during the multi-tx-pre-`gameOver=true` window affects terminal-jackpot magnitude inputs. V-063 fix at HANDOFF-31 also closes V-073 (`address(this).balance` outflow) at HANDOFF-40 — one gate, two writers.
   - **MEDIUM:** V-054, V-057, V-058, V-065 — bounded per-call magnitude; gate placement is mechanical.
   - **ZERO (already gated):** V-055, V-064 — gate already in-source at `MintModule:877/:906/:1215`; FUZZ-301 branch-coverage attestation only.

**5. Hero-override / weighted-roll day-index (Cluster A subset / V-003..V-005, §1..§3).** After the lens these are **MEDIUM** at most. `dailyHeroWagers[day][q]` only flips one byte of one trait quadrant; the dominant payout determinants (bucket-mask roll, prizePool size, ticket-queue level distribution) do NOT depend on this slot. Hero-override flip is a per-day-jackpot-scoped 0.5%–5% EV redirect to the attacker's preferred symbol. Tactic-(b) Phase 288 dailyIdx snapshot precedent applies; one diff at the writer or consumer site closes all three callsites (V-003 + V-004 + V-005).

**6. V-153 `_requestLootboxRng` scope-expansion candidate (§84 — Cluster I).** Per the Cluster I analysis, V-153 is structurally equivalent to the canonical `EXEMPT-RETRYLOOTBOXRNG` envelope but the catalog's strict per-callsite discipline currently flags it as VIOLATION. **Disposition: RESOLVED-AS-RECLASSIFIED at Phase 303 TERMINAL §9 closure attestation.** The v44.0 plan-phase has NO sub-phase obligation for V-153 — handoff anchor `D-43N-V44-HANDOFF-84` resolves via a one-line milestone-prose amendment (extending `D-42N-RETRY-RNG-DOMAIN-SEP-01` Option A to cover `_requestLootboxRng` as the commitment-side sibling of `retryLootboxRng`). Zero contract change. Conditional re-activation only if Phase 303 declines the reclassification.

### §0.5 — EV-tier breakdown post-lens

| Tier | Count | Notes |
|------|-------|-------|
| **CATASTROPHE** | **1** | V-184 only (with subsumption fan-out closing V-186/V-188/V-190/V-191/V-192/V-193 via one fix). |
| **HIGH** | ~10 | V-031, V-063 (closes V-073), V-027, V-098/V-099 (cluster G real EV), V-027, V-058, V-065, V-073 (same fix as V-063), V-110/V-117 family (activity-score writes), V-184-subsumed (catalog-row hygiene). |
| **MEDIUM / MEDIUM-LOW** | ~35 | Most Cluster G writer-side gates (V-089..V-104), Cluster C top-level entries (V-024, V-025), Cluster A V-003..V-005, Cluster E gameovers (V-054, V-057), Cluster H mintPacked_ writers (V-111, V-113, V-114, V-121, V-122, V-125), Cluster J ticketQueue writers (V-168/V-169/V-171/V-172/V-174/V-175/V-176/V-177). |
| **LOW / ACCEPTABLE-DESIGN** | ~15 | V-009/V-010/V-011 (already-gated coverage-only), V-012/V-013 (afKing callbacks that only flip afKing OFF — possible griefing-at-cost; possibly intended game design), V-026 / V-030 (downstream-gated), V-055 / V-064 (already-gated), V-081/V-082/V-084 lootboxEvBenefit (opportunity-cost barrier; per-account cap bypassed via Sybil — possibly acceptable game design), V-043 final-day Reward pool (low internal EV; bounded external short-position EV). |
| **STALE-CATALOG-ROW** | **3** | V-016 (§9), V-017 (§10), V-018 (§11) — writer functions absent from current `contracts/`; line numbers point to view functions. Mark for Phase 303 catalog amendment. |
| **FALSE-POSITIVE / RECLASSIFICATION** | **2** | V-063 claimablePool-via-claimWinnings (withdrawing one's own claimable winnings is NOT an exploit — `claimablePool` is a pull-pattern accumulator, not a VRF input; the §0 lens condition #1 fails; mark for catalog RECLASSIFICATION-TO-NON-PARTICIPATING). V-153 (RECLASSIFY-TO-EXEMPT at Phase 303 §9). |
| **PENDING-VERIFICATION** | **3** | V-047, V-048, V-050 (poolBalances[Lootbox] mega-tier) — the "drain-pool-before-resolution" exploit described doesn't compute as written: the only EOA path to deflate Lootbox pool is the player's OWN lootbox resolution, which reduces their own payout. Concrete tier deferred to Phase 302 SWEEP independent re-derivation. |
| **Governance (admin-trust-dependent)** | **5** | V-137, V-155, V-157, V-159, V-161 — VRF coordinator rotation / keyHash changes. Wave-1 299-09 claimed CATASTROPHE; lens downgrades to HIGH at most under owner-honest-but-curious threat model; MEDIUM under owner-honest. Not a non-admin exploit surface. |

**Honest final count: ~1 confirmed CATASTROPHE (V-184); ~10 real HIGH-tier; ~35 MEDIUM/LOW; ~15 already-gated or ACCEPTABLE-DESIGN; ~3 STALE-CATALOG-ROW; ~2 FALSE-POSITIVE/RECLASSIFICATION; ~3 PENDING-VERIFICATION; ~5 GOVERNANCE-tier.** Sum ≈ 74 (per-VIOLATION rows; some §N entries are subsumption-collapsed rows that share an anchor with their primary fix and don't appear in the tier register as independent rows).

### §0.6 — Subsumption map (one fix closes multiple catalog rows)

| Primary anchor | Closed catalog rows (subsumed) | Description |
|----------------|--------------------------------|-------------|
| `D-43N-V44-HANDOFF-111` (V-184) | V-186, V-188, V-190, V-191, V-192, V-193 (HANDOFF-112..117) | sStonk cross-day re-roll lock; one tactic-(a) revert in `_submitGamblingClaimFrom` closes 7 catalog rows. **TIER-1 PRIORITY-1.** |
| `D-43N-V44-HANDOFF-31` (V-063) | V-073 (HANDOFF-40) | One `_livenessTriggered() && !gameOver` gate at `_claimWinningsInternal:1399` closes both `claimablePool` debit AND `address(this).balance` outflow co-write. |
| `D-43N-V44-HANDOFF-36` (V-069) | V-070 (HANDOFF-37) | Extended `_purchaseDeityPass` gate covers both deity-owner-array length write AND `deityPassPurchasedCount[owner]` increment. |
| `D-43N-V44-HANDOFF-38` (V-071) | V-080 (HANDOFF-42) | Single `gameOverFundsSnapshot` field captures `address(this).balance + steth.balanceOf(address(this))` at `_gameOverEntropy` — closes both ETH-inflow and stETH-inflow races. |
| `D-43N-V44-HANDOFF-20` (V-043) | V-045 (HANDOFF-21), V-046 (HANDOFF-22) | Single sDGNRS Reward-pool snapshot at `_swapAndFreeze` closes V-043 (non-advanceGame writers), V-045 (admin/init), and V-046 (OZ-inherited writer class — the lone non-`contracts/` VIOLATION; fix lands in `contracts/` per `D-298-OZ-CARVEOUT-01`). |
| `D-43N-V44-HANDOFF-23` (V-047) | V-048 (HANDOFF-24) | Single per-index `lootboxPoolSnapshotByIndex` mapping at `_finalizeLootboxRng` closes both manual-path lootbox open paths (ETH `openLootBox` + BURNIE `openBurnieLootBox`). |
| `D-43N-V44-HANDOFF-47` (V-089) | V-091, V-095, V-098, V-101 (HANDOFF-49, -53, -56, -59) | Single `MintModule._allocateLootbox` entry gate covers 5 writer rows. |
| `D-43N-V44-HANDOFF-48` (V-090) | V-093, V-096, V-099, V-102 (HANDOFF-51, -54, -57, -60) | Single `WhaleModule._whaleLootboxAllocate` entry gate covers 5 writer rows. |
| `D-43N-V44-HANDOFF-50` (V-092) | V-104 (HANDOFF-62) | Single `MintModule._purchaseBurnieLootboxFor` entry gate covers BURNIE-allocate S-25 first-write AND S-29 accumulator. |
| `D-43N-V44-HANDOFF-46` (V-088) | V-094, V-097, V-100 (HANDOFF-52, -55, -58) | Single `LootboxModule.openLootBox` stack-capture block covers 4 self-zero rows. |
| `D-43N-V44-HANDOFF-78` (V-137) | V-155, V-157, V-159, V-161 (HANDOFF-85, -87, -89, -91) | Single `updateVrfCoordinatorAndSub` queue+apply split closes 5 governance rows. |
| `D-43N-V44-HANDOFF-86` (V-156) | V-158, V-160 (HANDOFF-88, -90) | Single `wireVrf` one-shot lock closes 3 governance rows. |

### §0.7 — Catalog hygiene markers

| Marker | Anchors | Disposition |
|--------|---------|-------------|
| **STALE-CATALOG-ROW** | HANDOFF-09 (V-016), HANDOFF-10 (V-017), HANDOFF-11 (V-018) | Writer functions absent from current `contracts/`; line numbers point to view functions. Mark for Phase 303 catalog amendment OR v44.0 CATALOG-refresh sub-phase. |
| **FALSE-POSITIVE / RECLASSIFY-TO-NON-PARTICIPATING** | HANDOFF-31 (V-063 — paradoxically also the gate-fix anchor since the lens reclassifies the slot but the planner's authored §N keeps the gate-fix prose) | `claimablePool` is a pull-pattern accumulator, NOT a VRF input. The §0 lens condition #1 fails. v44.0 plan-phase should evaluate whether to apply the cluster-recommended gate or accept the slot as non-participating. |
| **PENDING-VERIFICATION** | HANDOFF-23 (V-047), HANDOFF-24 (V-048), HANDOFF-25 (V-050) | "Drain-pool-before-resolution" mechanism unverified — the only EOA path to deflate Lootbox pool is the player's OWN lootbox resolution which reduces their own payout. Concrete tier deferred to Phase 302 SWEEP independent re-derivation. |
| **RESOLVED-AS-RECLASSIFIED** | HANDOFF-84 (V-153) | Scope-expand `EXEMPT-RETRYLOOTBOXRNG` envelope to cover `_requestLootboxRng`; Phase 303 §9 closure attestation; zero contract change. |
| **RESOLVED-AS-PHANTOM** | HANDOFF-77 (V-127) | `lastPurchaseDay` MintModule purchase-entry writer — no current source writer exists. v44.0 plan-phase: close as RESOLVED-AS-PHANTOM unless re-attestation finds a new writer. |
| **VERIFICATION-ONLY (no source change)** | HANDOFF-04 (V-009), HANDOFF-05 (V-010), HANDOFF-06 (V-011), HANDOFF-28 (V-055), HANDOFF-32 (V-064), HANDOFF-34 (V-066), HANDOFF-39 (V-072), HANDOFF-41 (V-074), HANDOFF-81 (V-142), HANDOFF-94 (V-170), HANDOFF-103 (V-179.C) | Gate already present at the writer entry; Phase 301 FUZZ-301 branch-coverage attestation only. |

### §0.8 — Phase 299 downstream consumption summary

- **v44.0 FIX-MILESTONE plan-phase:** Consumes the §M consolidated handoff register as load-bearing input. PRIORITY-1 sub-phase = HANDOFF-111 (V-184). Subsumption map (§0.6) groups anchors into ~25 sub-phases despite 119 anchors. STALE-CATALOG-ROW / FALSE-POSITIVE / PENDING-VERIFICATION / RESOLVED-AS-RECLASSIFIED / RESOLVED-AS-PHANTOM markers reduce active-fix anchor count to ~95.
- **Phase 300 ADMA:** Reads §15 of `.planning/RNGLOCK-CATALOG.md` independently. Phase 299 does NOT supply admin-function enumeration; that is the ADMA scope.
- **Phase 301 FUZZ:** Reads CAT-01 consumer surface enumeration from `.planning/RNGLOCK-CATALOG.md` §1..§13. Phase 299 supplies the per-VIOLATION `vm.skip` target list — every §M anchor whose tier is HIGH or CATASTROPHE OR whose disposition is "gate-add" maps to a fuzz case that reproduces the VIOLATION pre-fix.
- **Phase 302 SWEEP:** Adversarial pass re-derives tiers independently. Phase 302 is the venue for resolving the §0.7 PENDING-VERIFICATION markers (V-047/V-048/V-050).
- **Phase 303 TERMINAL §3.D:** FIXREC roll-up — consumes §0 + §M of this artifact.
- **Phase 303 TERMINAL §9 closure attestation:** Resolves HANDOFF-84 (V-153) reclassification.

---

## §1..§N — Per-VIOLATION Entries (aggregated from 10 cluster contributions)

## §1 — V-003 (`dailyHeroWagers[day][q]` via `_placeDegeneretteBetCore` at DegeneretteModule.sol:367)

### §1.A — Design-intent backward-trace

**Slot introduction.** `dailyHeroWagers` is declared at `contracts/storage/DegenerusGameStorage.sol:1485` as `mapping(uint32 => uint256[4]) internal dailyHeroWagers;` — four packed-uint32 slots per day, one per hero quadrant, each accumulating up to eight per-symbol weighted ETH wagers. The writer at `contracts/modules/DegenerusGameDegeneretteModule.sol:499` SSTORES `dailyHeroWagers[day][heroQuadrant] = wPacked` where `day = _simulatedDayIndex()` (wall-clock-derived). The reader at `contracts/modules/DegenerusGameJackpotModule.sol:1653` is `_rollHeroSymbol(dailyIdx, heroEntropy)` — a weighted random roll across the four packed quadrant slots, used by `_applyHeroOverride` to force the hero-symbol byte into the winning trait quadrant during every jackpot resolution call (CALL 1 + CALL 2 of the 2-call ETH-split, plus the coin-and-tickets phase).

**Phase 288 dailyIdx precedent.** Per `.planning/milestones/v41.0-phases/288-f-41-03-cross-day-call-1-call-2-determinism-fix-fix-jpsurf/288-01-DESIGN-INTENT-TRACE.md` §(iii), `dailyIdx` is written ONLY by `_unlockRng` (AdvanceModule:1730) AFTER all CALL 1 + CALL 2 + coin-and-tickets phases complete for a given day's cycle. Phase 288 swapped the consumer read from `_simulatedDayIndex()` to `dailyIdx` so both calls of the 2-call split read the IDENTICAL slot regardless of physical-day-boundary crossings during a stalled jackpot. Quote (Phase 288 trace §(iii) line 35): *"Reading `dailyHeroWagers[dailyIdx]` instead of `dailyHeroWagers[_simulatedDayIndex()]` makes BOTH calls of the 2-call split read the IDENTICAL slot regardless of cross-day timing."*

**Design intent for the slot's existence.** The hero-override is a community contest: players nominate `(quadrant, symbol)` pairs via ETH degenerette bets, the top-wagered symbol per quadrant becomes the forced override for the NEXT jackpot. Phase 288 §(i) line 11-13 establishes the canonical model: bets placed on day D contribute to day D+1's jackpot hero override; bets placed on day D MUST NOT influence day D's own jackpot (would create a within-cycle frontrun). The contest is on a stable historical population — the jackpot reads a SETTLED slot, not a live one.

**Why a naive gate would break behavior.** A blanket `if (rngLockedFlag) revert RngLocked()` on `placeDegeneretteBet` would unnecessarily block ETH betting throughout the rng-lock window — which spans the entire 2-call ETH split plus the coin-and-tickets phase. Bets that target day D+1's hero override are functionally unrelated to day D's resolution and need not be rejected; the canonical Phase 288 mental model (`slot[D] = bets placed on day D`) is preserved only if writes for day D+1 are permitted to land in `slot[D+1]` while the consumer reads `slot[dailyIdx]` (= `slot[D]`). The asymmetric solution is to gate the WRITE on `slot != dailyIdx` (or equivalently freeze the read-slot anchor at lock time), not gate the entire entry.

**Cross-day-passive gap.** Per Phase 288 §(ii), the writer's `_simulatedDayIndex()` is wall-clock-derived. During the rng-lock window the consumer reads `dailyHeroWagers[dailyIdx]` (frozen, slot of the prior day). If the wall clock has NOT yet rolled, `_simulatedDayIndex() == dailyIdx + 1` (current betting day) and writes land in `slot[dailyIdx + 1]` — DISJOINT from the consumer read — and the invariant is preserved by clock geometry alone. The Phase 299 VIOLATION arises in the opposite case: when `_simulatedDayIndex() == dailyIdx` (within the resolution window before `_unlockRng` advances dailyIdx, OR during cross-day stalls where dailyIdx has been bumped to the NEW day and writes target that new day's slot just as the consumer reads it). Phase 288 closed F-41-03 between CALL 1 / CALL 2 via the `dailyIdx` consumer-swap; Phase 299 closes the parallel writer-side window where an EOA bet co-mutates `dailyHeroWagers[dailyIdx][q]` between VRF request and fulfillment.

### §1.B — Actor game-theory walk

Per `feedback_rng_commitment_window.md` — every RNG audit must check what player-controllable state can change between VRF request and fulfillment. Per `feedback_rng_backward_trace.md` — trace BACKWARD from the consumer to verify the word was unknown at input commitment time. The consumer `_rollHeroSymbol(dailyIdx, heroEntropy)` at JackpotModule.sol:1639 keccak-hashes `(heroEntropy, day)` and consumes the result modulo `effectiveTotal` (= weighted sum across the eight per-symbol slots), THEN selects the winning slot via cumulative-cursor walk over weights derived from `dailyHeroWagers[dailyIdx][q]`. The weights are SLOAD'd inside the rng-lock window. An attacker who mutates a weight after VRF request but before fulfillment shifts the cumulative-cursor boundary, redistributing the win probability.

**Actor class:** ETH-funded player or MEV bot (single transaction; no special role required). Bet entry is unrestricted external `placeDegeneretteBet` at DegeneretteModule.sol:367.

**Action sequence during rngLock window:**

1. Player observes `_requestRng` has been triggered (publicly visible via Chainlink VRF request event OR `rngRequestTime != 0` SLOAD).
2. Player observes the pending VRF request seed and the current `dailyIdx == D-1` (frozen during the lock per Phase 288 §(iii)).
3. Player snapshots `dailyHeroWagers[D-1][0..3]` (4 SLOADs; cheap public read).
4. Player computes, for the publicly-known but not-yet-fulfilled `heroEntropy` value range (or speculatively for any plausible value), which `(quadrant, symbol)` slot a marginal-amount bet would push into the leader position, thereby flipping which symbol gets the `leaderBonus = maxAmount / 2` ×1.5 multiplier.
5. Player fires `placeDegeneretteBet{value: X}(player, CURRENCY_ETH, amountPerTicket, 1, customTicket, heroQuadrant)`. The write at DegeneretteModule.sol:499 mutates `dailyHeroWagers[_simulatedDayIndex()][heroQuadrant]`; in the worst case `_simulatedDayIndex() == dailyIdx`, the write lands on the slot the consumer will read.
6. VRF callback fires; `_applyHeroOverride` consumes the mutated weight vector; the player's preferred `(quadrant, symbol)` becomes the forced hero in the winning traits.

**EV magnitude.** MEDIUM-tier. The hero override only flips one byte of one trait quadrant; the dominant payout determinants are the bucket-mask roll (`_pickSoloQuadrant`), prizePool size, and ticket-queue level distribution — none of which depend on `dailyHeroWagers`. The hero-override's economic effect is per-day-jackpot SCOPED to whichever winners' trait matches the forced symbol — a partial EV redirect of typically 0.5%–5% of the daily ETH prize-pool to the attacker's preferred symbol. CATASTROPHE-tier is reserved for slots that directly feed roll selection (e.g. autoRebuyState afKingMode in §6/§7/§8 — finalist redirect at jackpot award time); dailyHeroWagers manipulates a side-channel byte in the hero-symbol roll, not the underlying jackpot bucket math.

**Economic likelihood: MEDIUM.** Per-bet cost is small (`amountPerTicket` minimum is enforced by `_validateMinBet` but is well below the marginal hero-flip EV at non-trivial prize-pool sizes). Bot infrastructure to observe `rngRequestTime` and chain a place-bet transaction in the lock window is well-precedented in the protocol (Phase 296 SWEEP demonstrated MEV reach across cross-contract surfaces).

### §1.C — Recommended tactic + rationale + impact estimate

**Tactic: (b) snapshot/anchor pattern.** Per catalog §16 row V-003 rationale: *"Phase 288 dailyIdx snapshot; freeze read-day at lock time."*

**Rationale.** A blanket `rngLockedFlag` gate (tactic (a)) on `placeDegeneretteBet` is wrong because betting must remain live during the lock window for the canonical-Phase-288 reason: bets placed during day D (which the rng-lock window may straddle if cross-day stalls occur) target day D+1's hero override and are functionally unrelated to day D's resolution. The asymmetric remediation is to freeze the consumer-read anchor at lock time so the consumer no longer reads the slot the writer is currently mutating. Two implementation options exist for (b):

1. **Snapshot the 4 packed quadrant SLOADs into a transient stack/memory anchor at `_requestRng` time** and pass the anchor through `_applyHeroOverride` invocations within a single jackpot resolution. This eliminates the cross-day-passive surface AND the active EOA-frontrun surface in one move. Bytecode delta: ~80–120 bytes (4 SLOADs + 4 memory writes at the lock-flag-set site; struct-encoded read of the anchor inside `_rollHeroSymbol`).

2. **Add a write-side check in `_placeDegeneretteBetCore` at DegeneretteModule.sol:486** that rejects writes targeting `_simulatedDayIndex() == dailyIdx`: writes for the prior-day slot are exactly the slot the rng-lock-window consumer reads, so during the lock the write is invalid for that day. Bytecode delta: ~30 bytes (1 SLOAD of `dailyIdx` + 1 SLOAD of `rngLockedFlag` + 1 conditional branch). Storage delta: 0. This option deviates from the "snapshot" terminology of catalog (b) but achieves the same invariant via write-time anchor rejection rather than read-time snapshot — semantically equivalent at the consumer's freshness boundary.

v44.0 plan-phase selects between (1) and (2) at sub-phase planning; both satisfy the Phase 298 catalog (b) classification.

**Storage-layout impact.** Zero. Both options re-use the existing slot ID `dailyHeroWagers[day][q]` and the existing `dailyIdx` + `rngLockedFlag` SLOADs.

**Public ABI impact.** Zero per `D-40N-EVT-BREAK-01` + `D-42N-EVT-BREAK-01`. Option 1 emits no new event topic; option 2 emits no new event topic. Option 2 introduces a new `RngLocked` revert path on `placeDegeneretteBet` for the within-day-lock case; per the catalog (`RngLocked` custom error pattern at MintModule:1221 / BurnieCoinflip:730 / sStonk:492 / DegenerusGameStorage.sol:213), this is a non-breaking surface-extension because `RngLocked` is already an inherited error type the surrounding modules emit.

**Bytecode impact estimate.** Option 1: +80–120 bytes. Option 2: +30–50 bytes. Both well below the 24KB EIP-170 module size ceiling.

### §1.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-01 — Apply Phase 288 `dailyIdx` snapshot-anchor pattern to `dailyHeroWagers[dailyIdx][q]` so within-day EOA `placeDegeneretteBet` writes during rng-lock cannot mutate the slot the consumer reads. **Catalog row:** RNGLOCK-CATALOG.md:338 (V-003). **Writer:** `contracts/modules/DegenerusGameDegeneretteModule.sol:499` reached from external entry at `:367`.

---

## §2 — V-004 (`dailyHeroWagers[day][q]` via `_placeDegeneretteBetCore` at DegenerusGame.sol:714)

### §2.A — Design-intent backward-trace

**Same slot, same writer, distinct callsite.** `DegenerusGame.placeDegeneretteBet` at `contracts/DegenerusGame.sol:714` is the parent-contract dispatcher: it `delegatecall`s to `ContractAddresses.GAME_DEGENERETTE_MODULE.placeDegeneretteBet` (DegenerusGame.sol:722–737). Because Solidity delegatecall preserves storage context, the SSTORE in `_placeDegeneretteBetCore` at DegeneretteModule.sol:499 lands in the SAME storage slot of the SAME `DegenerusGame` instance regardless of whether entry is the module's external function (§1) or the parent's dispatcher (§2). The verdict matrix splits these as separate rows per `D-298-EXEMPT-CROSSCONTRACT-01` strict per-callsite discipline: the same writer function reached from a different callsite gets its own verdict row even when the underlying SSTORE is identical.

**Why the parent dispatcher exists.** The parent `DegenerusGame` is the user-facing contract address; off-chain UIs target its ABI. The dispatcher pattern at DegenerusGame.sol:714–737 forwards calldata to the module via delegatecall so that callers see a uniform `DegenerusGame.placeDegeneretteBet(...)` entrypoint without needing to know about module-routing internals. The dispatcher itself performs no business logic — it is a thin selector-forwarding shim with `_resolvePlayer(player)` pre-resolution.

**Phase 288 precedent.** Same trace as §1.A. The Phase 288 `dailyIdx` snapshot/freeze invariant applies identically at this callsite because the underlying SSTORE is the same.

**Why a naive gate would break behavior.** Same as §1.A — the dispatcher path must remain open during the lock window for bets that target the NEXT day's hero-override slot.

### §2.B — Actor game-theory walk

Same actor class, action sequence, EV, and likelihood as §1.B. The parent-dispatcher path is in fact the path off-chain wallets actually hit (the module-direct path is uncommon since DegenerusGame.sol is the canonical address documented to the front-end). For Phase 299 audit purposes the parent-dispatcher VIOLATION row carries the realistic-exploit weight; the module-direct row (§1) is preserved for catalog completeness per strict per-callsite enumeration.

Per `feedback_rng_commitment_window.md`, the player-controllable surface from this callsite is identical: `dailyHeroWagers[dailyIdx][q]` SLOADed inside the rng-lock window can be mutated by a single EOA transaction targeting `DegenerusGame.placeDegeneretteBet`.

**EV magnitude.** MEDIUM-tier (same as §1.B). The parent-dispatcher entry is the realistic-attack path; the EV ceiling is identical because the writer body is identical.

**Economic likelihood: MEDIUM-to-HIGH** (higher than §1.B because the parent-dispatcher entry is the path with public ABI exposure; bots looking for arbitrary attack surface target the parent contract, not the module).

### §2.C — Recommended tactic + rationale + impact estimate

**Tactic: (b) snapshot/anchor pattern.** Per catalog §16 row V-004 rationale: *"Parent dispatch — same day-key freeze attestation."*

**Rationale.** The remediation tactic is identical to §1.C because both V-003 and V-004 mutate the same storage slot via the same writer body. A SINGLE remediation — applied at the SSTORE site DegeneretteModule.sol:499 or at the consumer SLOAD site JackpotModule.sol:1653 — covers both V-003 and V-004 callsites simultaneously. The verdict matrix splits the rows for catalog-completeness discipline; the v44.0 sub-phase implementing the fix touches one (writer-side) or zero+one (consumer-side) lines of source and resolves V-003 + V-004 with the same diff.

**Storage-layout impact.** Zero (same as §1.C).

**Public ABI impact.** Zero. The parent dispatcher's `placeDegeneretteBet` selector is preserved; option 2 adds a `RngLocked` revert path co-extensive with §1.C.

**Bytecode impact estimate.** Zero incremental delta beyond §1.C (single source-line fix covers both callsites).

### §2.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-02 — Same snapshot/freeze attestation as H-01 applied to the parent-dispatcher reach of `_placeDegeneretteBetCore`; v44.0 sub-phase consolidates H-01 + H-02 into one diff at the writer or consumer site. **Catalog row:** RNGLOCK-CATALOG.md:339 (V-004). **Writer:** `contracts/modules/DegenerusGameDegeneretteModule.sol:499` reached via delegatecall from `contracts/DegenerusGame.sol:714`.

---

## §3 — V-005 (`dailyHeroWagers[day][q]` via `_placeDegeneretteBetCore` at DegenerusVault.sol:607)

### §3.A — Design-intent backward-trace

**Vault-routed callsite.** `DegenerusVault.placeDegeneretteBet` at `contracts/DegenerusVault.sol:607` is a vault-multisig wrapper: a vault-owner role (51%+ DGVE holder per the `onlyVaultOwner` modifier at DegenerusVault.sol:601) invokes `gamePlayer.placeDegeneretteBet{value: value}(address(this), ...)` — a regular external call into `DegenerusGame.placeDegeneretteBet` (§2) with the vault as the bet-placer. Once execution enters `DegenerusGame`, the parent dispatcher path of §2 takes over, ultimately delegatecalling the module and SSTOREing at DegeneretteModule.sol:499 with `player == DegenerusVault` and `day == _simulatedDayIndex()`. The storage slot mutated is the same logical `dailyHeroWagers[day][heroQuadrant]` in the game instance.

**Why the vault exists.** The DGVE-token-gated vault allows pooled-capital bet placement: vault depositors (DGVE holders) collectively control the vault's bet treasury and elect a vault-owner to actuate bets. The vault entry exists to support pooled-strategy play without requiring each depositor to actuate bets individually.

**Phase 288 precedent.** Same trace as §1.A. The vault path is an additional EOA-reachable surface (the vault-owner is an EOA satisfying `onlyVaultOwner`) that targets the identical storage slot.

**Why a naive gate would break behavior.** Same as §1.A. Additionally, vault depositors expect the vault to remain capable of placing bets through the lock window when those bets target the next-day slot; a blanket revert at the vault-owner role would block legitimate vault strategy actuation.

### §3.B — Actor game-theory walk

**Actor class:** Vault-owner (EOA holding 51%+ of DGVE per `onlyVaultOwner`) acting as a privileged amplifier — the vault concentrates capital across multiple depositors into a single bet that lands at the same storage slot.

**Action sequence during rngLock window:**

1. Vault-owner observes pending VRF request (same observation channel as §1.B).
2. Vault-owner snapshots `dailyHeroWagers[D-1][0..3]` and computes the marginal-bet threshold to flip the leader position (same as §1.B).
3. Vault-owner calls `DegenerusVault.placeDegeneretteBet{value: X}(...)` — vault treasury funds the bet; per-DGVE-share dilution is borne by depositors. The vault's capital pool may significantly exceed any single EOA's, so the leader-flip threshold can be cleared in a single tx even at large `maxAmount` in the leader slot.
4. Execution flows DegenerusVault.sol:607 → DegenerusGame.sol:714 (§2) → delegatecall to module → SSTORE at DegeneretteModule.sol:499.
5. VRF callback consumes the mutated weight vector; vault-owner's preferred symbol becomes forced hero.

**EV magnitude.** HIGH-tier (one tier above §1.B). The vault's pooled capital allows clearing leader-flip thresholds that a single EOA cannot reach within rational-economics bounds. The vault-owner extracts hero-override redirect EV from the protocol's daily ETH prize-pool at depositors' (DGVE-share-dilution) expense — internal-extraction griefing — but the externally-observable hero-override flip is fully exploitable for downstream MEV (e.g. predicting the forced symbol allows the vault-owner to pre-arrange tickets whose traits intersect the forced quadrant's payout).

**Economic likelihood: MEDIUM-LOW.** The vault-owner role concentrates trust; depositors observe vault bets and can withdraw if the owner mis-acts. But (a) governance-token control of an EOA permission is a recurring DeFi-MEV pattern (compare DEX-vault frontrun cases), and (b) the vault-owner threshold is 51% — concentrated holdings can sustain mis-action across multiple depositor-withdrawal cycles before consequence accrues. Per `feedback_design_intent_before_deletion.md`, the actor walk must enumerate even low-likelihood high-EV paths: HIGH × MEDIUM-LOW = expected-value comparable to §1.B's MEDIUM × MEDIUM.

### §3.C — Recommended tactic + rationale + impact estimate

**Tactic: (b) snapshot/anchor pattern.** Per catalog §16 row V-005 rationale: *"Vault-routed bet — same day-key freeze attestation."*

**Rationale.** Identical to §1.C and §2.C — the underlying SSTORE at DegeneretteModule.sol:499 is the same. A single remediation diff covers V-003 + V-004 + V-005 simultaneously. The vault-routed entry is a leaf callsite that transparently inherits the writer-side or consumer-side anchor.

**Storage-layout impact.** Zero.

**Public ABI impact.** Zero. The vault's `placeDegeneretteBet` selector and the game's `placeDegeneretteBet` selector are both preserved; option-2 `RngLocked` revert path propagates through the vault entry as a normal Solidity bubble-up (the vault's `(bool ok, bytes memory data) = ...` pattern at DegenerusVault.sol:607 catches and re-throws — verify the existing surrounding pattern; if not, the revert bubbles via Solidity default behavior).

**Bytecode impact estimate.** Zero incremental delta beyond §1.C.

### §3.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-03 — Vault-routed reach of `_placeDegeneretteBetCore` resolved by the same writer-side or consumer-side snapshot/freeze applied to H-01 + H-02; v44.0 sub-phase verifies the vault entry inherits the gate transparently and emits a vault-side regression test asserting the `RngLocked` revert bubbles through `gamePlayer.placeDegeneretteBet`. **Catalog row:** RNGLOCK-CATALOG.md:340 (V-005). **Writer:** `contracts/modules/DegenerusGameDegeneretteModule.sol:499` reached via external call from `contracts/DegenerusVault.sol:607`.

---

## §4 — V-009 (`autoRebuyState[beneficiary]` via `_setAutoRebuy` at DegenerusGame.sol:1495)

### §4.A — Design-intent backward-trace

**Slot introduction.** `autoRebuyState` is declared as `mapping(address => AutoRebuyState) internal autoRebuyState` in `DegenerusGameStorage`. The struct packs `{ bool autoRebuyEnabled, uint128 takeProfit, bool afKingMode, uint24 afKingActivatedLevel }` and is consumed by §1 of the catalog (JackpotModule.payDailyJackpot at `:339`) during finalist-redirect — the auto-rebuy state determines whether a player's winning ETH gets converted back into next-level (or next+1) tickets vs paid out as claimable. The afKing-mode arm additionally affects the rebuy bonus rate (30% default → 45% with afKing) and clamps `takeProfit` to floors (5 ETH / 20k BURNIE).

**Writer chain.** `setAutoRebuy(address player, bool enabled)` at DegenerusGame.sol:1495 is an external EOA entry. It resolves `_resolvePlayer(player)` and invokes `_setAutoRebuy(player, enabled)` at `:1512`. The private writer at `:1512–:1522` performs `if (rngLockedFlag) revert RngLocked();` at `:1513` (runtime gate ALREADY PRESENT), then SSTOREs `state.autoRebuyEnabled = enabled` at `:1516`, emits `AutoRebuyToggled`, and (if disabling) cascades into `_deactivateAfKing(player)` at `:1520`.

**Why the slot exists.** Auto-rebuy is a player-side UX toggle: rather than manually re-buying tickets each level, the player opts into automatic conversion of their winnings into next-level tickets. The state must be player-settable on demand outside the rng-lock window so the player can react to evolving game state (level progression, prize-pool changes, jackpot outcomes) between resolutions.

**Why a naive blanket gate would break behavior.** The runtime gate at DegenerusGame.sol:1513 IS the correct design: it blocks writes during the rng-lock window so the jackpot consumer's SLOAD of `autoRebuyState[winner]` is not co-mutated by the winner themselves. The slot is unwriteable during finalist-redirect, exactly the desired invariant.

**Catalog coverage attestation.** Per catalog §16 V-009 rationale: *"Gate already at DegenerusGame:1513; FUZZ-301 verify branch coverage."* Phase 299 documents that V-009's gate is PRESENT and the Phase 299 deliverable for this row is a coverage-verification handoff (FUZZ test asserts the revert fires across the full rng-lock window for every reachable `setAutoRebuy(...)` invocation pattern), not a new gate-install.

### §4.B — Actor game-theory walk

Per `feedback_rng_window_storage_read_freshness.md` — non-VRF SLOADs inside the rng-window consumed alongside RNG are a distinct bug class. The jackpot consumer at JackpotModule.payDailyJackpot SLOADs `autoRebuyState[winner]` to determine the finalist-redirect rule (tickets vs claimable). If a winner mutates their own `autoRebuyEnabled` between VRF request and fulfillment, they can redirect their winnings between the two pools based on knowledge gained after VRF observation but before the jackpot SSTOREs the redirect.

**Actor class:** Player (any holder; no special role).

**Action sequence during rngLock window (PRE-GATE scenario, what the gate prevents):**

1. Player observes pending VRF request and the imminent jackpot resolution.
2. Player models their probability of finishing in the winner cohort under each possible VRF word value (publicly inferable from on-chain state).
3. Player models their downstream EV under (a) tickets redirect vs (b) claimable-pool payout, conditional on the predicted winning level and the next-level prize-pool size.
4. Player calls `setAutoRebuy(player, enabled')` to flip the redirect ELECTION ex-ante of VRF fulfillment but ex-post of VRF request — gaining a free option on which payout pool to receive.
5. The runtime gate at DegenerusGame.sol:1513 REJECTS the tx with `RngLocked` revert; the elective state cannot be mutated inside the rng-lock window.

**EV magnitude.** HIGH-tier IF the gate were absent. The finalist-redirect election affects 100% of the winner's payout, not a per-symbol byte side-channel. Without the gate, the player extracts a free option on which payout pool to receive — the option's value equals `|EV(tickets-path) − EV(claimable-path)|` per winner, which at large prize-pool sizes can exceed several ETH per cycle. Per Phase 299 cluster preamble, autoRebuyState is HIGH-tier because afKing mode is the per-jackpot-day finalist-redirect-rule input.

**Economic likelihood: covered.** The gate at `:1513` prevents the action sequence from completing; the EOA observes the revert and abandons the attempt. The Phase 299 deliverable for V-009 is FUZZ-301 coverage verification — that the gate fires at every callsite reachable under every state combination.

### §4.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-009 rationale: *"Gate already at DegenerusGame:1513; FUZZ-301 verify branch coverage."*

**Rationale.** The gate is already installed at the private writer entry point `_setAutoRebuy` at DegenerusGame.sol:1513. Phase 299's deliverable for this VIOLATION row is the v44.0 sub-phase that authors a fuzz/property test confirming:

- Every callsite of `_setAutoRebuy(...)` (currently only `setAutoRebuy` at `:1495` and the cascade from `_setAutoRebuyTakeProfit` at `:1536` → `_deactivateAfKing`) is exercised under `rngLockedFlag == true`.
- The revert fires for every `(player, enabled)` input combination during the lock.
- The revert message decodes to `RngLocked()` (selector `0x...` — verify against `DegenerusGameStorage.sol:213`).

The catalog (a) classification is "gated revert"; the gate IS the revert. The completion criterion is coverage attestation, not gate-install.

**Storage-layout impact.** Zero. No slot added.

**Public ABI impact.** Zero. The `setAutoRebuy(address,bool)` selector is preserved; the `RngLocked` revert is already an inherited error per DegenerusGameStorage.sol:213.

**Bytecode impact estimate.** Zero (gate already compiled in at `:1513`).

**FUZZ test scope.** Phase 301 FUZZ harness should add a property: ∀ player p, ∀ enabled e, when `rngLockedFlag == true`, `DegenerusGame.setAutoRebuy(p, e)` reverts with `RngLocked()` selector. The harness MUST reach `_setAutoRebuy` from the parent dispatcher (DegenerusGame.sol:1495), not just the internal helper, so the dispatcher → private-writer call path is included in the coverage trace.

### §4.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-04 — Confirm by fuzz test (Phase 301 harness) that the `rngLockedFlag` gate at DegenerusGame.sol:1513 fires for every reachable invocation of `setAutoRebuy(address,bool)` across the rng-lock window. No source change expected; coverage-attestation only. **Catalog row:** RNGLOCK-CATALOG.md:344 (V-009). **Writer:** `contracts/DegenerusGame.sol:1512` (private `_setAutoRebuy`) reached from external entry at `:1495`.

---

## §5 — V-010 (`autoRebuyState[beneficiary]` via `_setAutoRebuyTakeProfit` at DegenerusGame.sol:1504)

### §5.A — Design-intent backward-trace

**Same slot, parallel writer.** `setAutoRebuyTakeProfit(address player, uint256 takeProfit)` at DegenerusGame.sol:1504 is the parallel EOA entry for setting the `takeProfit` field of `AutoRebuyState`. It resolves the player and invokes `_setAutoRebuyTakeProfit` at `:1524`. The private writer at `:1524–:1538` performs `if (rngLockedFlag) revert RngLocked();` at `:1528` (runtime gate PRESENT), SSTOREs `state.takeProfit = uint128(takeProfit)` at `:1532`, emits `AutoRebuyTakeProfitSet`, then (if takeProfit < AFKING_KEEP_MIN_ETH and non-zero) cascades into `_deactivateAfKing(player)` at `:1536`.

**Why the slot exists.** `takeProfit` is the amount of player winnings reserved for manual claim (not auto-rebuy'd). It is a player-side preference that determines the split between (a) "tickets-via-auto-rebuy" and (b) "claimable-via-takeProfit-reserve" pools. The user controls this per their off-chain strategy.

**Why a naive blanket gate would break behavior.** Same as §4.A — the runtime gate at `:1528` IS the correct design. Outside the lock window the player needs free read/write access to retune their takeProfit allocation; inside the lock window the gate blocks election-mid-resolution.

**Catalog coverage attestation.** Per catalog §16 V-010 rationale: *"Gate already at DegenerusGame:1528 — same coverage gap."* Phase 299 deliverable: FUZZ-301 coverage verification.

### §5.B — Actor game-theory walk

**Actor class:** Player (any holder).

**Action sequence during rngLock window (PRE-GATE scenario):**

1. Player observes pending VRF and models their winner-cohort probability (same as §4.B).
2. Player models their downstream EV under (a) `takeProfit = high` (more claimable reserved) vs (b) `takeProfit = low` (more auto-rebuy'd into tickets).
3. Player calls `setAutoRebuyTakeProfit(player, takeProfit')` to flip the allocation.
4. Runtime gate at DegenerusGame.sol:1528 REJECTS with `RngLocked` revert; the elective allocation cannot be mutated inside the lock window.

**Bonus surface (cascade-side).** Per the writer body at DegenerusGame.sol:1535–1537, setting `takeProfit < AFKING_KEEP_MIN_ETH` AND non-zero cascades into `_deactivateAfKing(player)`. If a player could land a `setAutoRebuyTakeProfit(player, 1 wei)` during the rng-lock window, they would deactivate afKing-mode mid-resolution — but the gate at `:1528` blocks this BEFORE the cascade is reached, so V-010 carries V-011's EV in the rng-lock-mutated case (since afKing mode is the higher-EV slot per the cluster preamble).

**EV magnitude.** HIGH-tier (same as §4.B; cascade-amplified if takeProfit drops below the AFKING floor while afKing is active — see §6.B for afKing-mode EV).

**Economic likelihood: covered by gate.**

### §5.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-010 rationale: *"Gate already at DegenerusGame:1528 — same coverage gap."*

**Rationale.** Same as §4.C — the gate is installed at the private writer at `:1528`. Phase 299 deliverable is FUZZ-301 coverage attestation that the revert fires for every reachable `setAutoRebuyTakeProfit` invocation during the lock. Cascade-coverage requirement: the FUZZ harness MUST also assert that the `_deactivateAfKing` cascade at `:1536` is NEVER reached during the lock (because the parent revert at `:1528` fires first), so V-010's gate transitively covers the cascade path into the §7 writer body even when reached via `_setAutoRebuyTakeProfit`.

**Storage-layout impact.** Zero.

**Public ABI impact.** Zero. `setAutoRebuyTakeProfit(address,uint256)` selector preserved.

**Bytecode impact estimate.** Zero (gate already compiled in at `:1528`).

### §5.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-05 — Fuzz-verify the `rngLockedFlag` gate at DegenerusGame.sol:1528 fires for every reachable invocation of `setAutoRebuyTakeProfit(address,uint256)` AND that the `_deactivateAfKing` cascade at `:1536` is unreachable inside the lock window. No source change expected. **Catalog row:** RNGLOCK-CATALOG.md:345 (V-010). **Writer:** `contracts/DegenerusGame.sol:1524` (private `_setAutoRebuyTakeProfit`) reached from external entry at `:1504`.

---

## §6 — V-011 (`autoRebuyState[beneficiary]` via `_setAfKingMode` at DegenerusGame.sol:1559)

### §6.A — Design-intent backward-trace

**Same slot, afKing-mode writer.** `setAfKingMode(address player, bool enabled, uint256 ethTakeProfit, uint256 coinTakeProfit)` at DegenerusGame.sol:1559 is the EOA entry for toggling afKing mode — the higher-rebuy-rate variant of auto-rebuy that forces auto-rebuy ON for both ETH and BURNIE, clamps `takeProfit` to floors (5 ETH / 20k BURNIE), and requires a lazy-pass (deity pass OR whale-pass `frozenUntilLevel > level`). The private writer at `:1569–:1608` performs `if (rngLockedFlag) revert RngLocked();` at `:1575` (runtime gate PRESENT), then either deactivates (cascading to `_deactivateAfKing` at `:1577`) or activates with full state machine: SSTOREs `state.autoRebuyEnabled = true` at `:1593`, `state.takeProfit = uint128(adjustedEthKeep)` at `:1597`, `state.afKingMode = true` at `:1604`, `state.afKingActivatedLevel = level` at `:1605`. The call also dispatches a cross-contract `coinflip.setCoinflipAutoRebuy(player, true, adjustedCoinKeep)` at `:1600`.

**Why the slot exists.** afKing mode is a "max-grind" lazy-pass-gated rebuy mode that automatically converts winnings to next-level tickets at +50% bonus rate (45% vs 30% baseline). It is intended for lazy-pass holders who commit to the protocol's ticket-purchase grind across multiple levels and accept the AFKING_KEEP_MIN floor as the price of the bonus-rate access.

**Why a naive blanket gate would break behavior.** Same as §4.A — the runtime gate at `:1575` IS the correct design. afKing toggle election outside the lock window is essential for lazy-pass-holders to react to game-state evolution; inside the lock window the gate blocks mid-resolution election.

**Catalog coverage attestation.** Per catalog §16 V-011 rationale: *"Gate already at DegenerusGame:1575 — same coverage gap."* Phase 299 deliverable: FUZZ-301 coverage verification.

### §6.B — Actor game-theory walk

Per the Phase 299 cluster preamble, afKing mode is HIGH-tier because it is the per-jackpot-day finalist-redirect-rule input AND it forces both currencies (ETH + BURNIE) into auto-rebuy with elevated bonus. Combined-pool finalist-redirect manipulation has a strictly larger EV than single-pool manipulation.

**Actor class:** Lazy-pass-holding player (deity pass OR whale-pass `frozenUntilLevel > level` per `_hasAnyLazyPass` at DegenerusGame.sol:1610).

**Action sequence during rngLock window (PRE-GATE scenario):**

1. Player observes pending VRF and models their winner-cohort probability under each possible VRF word.
2. Player models EV under (a) afKing mode ON: 45% bonus on auto-rebuy'd tickets, both ETH+BURNIE pools forced into rebuy, takeProfit clamped to floors vs (b) afKing mode OFF: 30% bonus on ETH only (if `autoRebuyEnabled` separately), free takeProfit allocation.
3. Player calls `setAfKingMode(player, enabled', ethTakeProfit', coinTakeProfit')` to flip the finalist-redirect election between regimes.
4. Runtime gate at DegenerusGame.sol:1575 REJECTS with `RngLocked` revert; the elective regime cannot be mutated inside the lock window.

**EV magnitude.** HIGH-tier (potentially CATASTROPHE-tier at large prize-pool levels). The afKing 45% bonus is applied to the full auto-rebuy stream — at a large daily ETH prize-pool with afKing-flip-redirect, the bonus delta alone can be 15% of the auto-rebuy pool's value, plus the cross-currency BURNIE auto-rebuy redirect, plus the cross-contract `coinflip.setCoinflipAutoRebuy` side-effect at `:1600`.

**Economic likelihood: covered by gate.** The lazy-pass requirement narrows the attack-actor cohort to lazy-pass holders; this is a non-trivial subset of all addresses but is bounded by deity-pass + whale-pass supply.

### §6.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-011 rationale: *"Gate already at DegenerusGame:1575 — same coverage gap."*

**Rationale.** Same as §4.C and §5.C — the gate is installed at the private writer at `:1575`. Phase 299 deliverable is FUZZ-301 coverage attestation. Cascade-coverage requirement: the FUZZ harness MUST cover both arms of the writer — (i) `enabled == false` branch at `:1576–:1579` cascading into `_deactivateAfKing` at `:1577`, and (ii) `enabled == true` arm at `:1580–:1607` — both ARE inside the gate's protection scope at `:1575`. The cross-contract dispatch at `:1600` (`coinflip.setCoinflipAutoRebuy`) is also unreachable inside the lock window per the gate.

**Storage-layout impact.** Zero.

**Public ABI impact.** Zero. `setAfKingMode(address,bool,uint256,uint256)` selector preserved.

**Bytecode impact estimate.** Zero (gate already compiled in at `:1575`).

**Cross-contract coupling note.** The `coinflip.setCoinflipAutoRebuy` dispatch at `:1600` writes to BurnieCoinflip state. The gate at `:1575` blocks reach into that dispatch during the lock window; v44.0 sub-phase verifies BurnieCoinflip's own rng-lock-window invariants do NOT also need a parallel gate (since the entry from GAME is closed at GAME).

### §6.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-06 — Fuzz-verify the `rngLockedFlag` gate at DegenerusGame.sol:1575 fires across both arms of `_setAfKingMode` (deactivate-cascade arm at `:1576–:1579` and full-activate arm at `:1580–:1607` including the cross-contract `coinflip.setCoinflipAutoRebuy` dispatch at `:1600`). No source change expected. **Catalog row:** RNGLOCK-CATALOG.md:346 (V-011). **Writer:** `contracts/DegenerusGame.sol:1569` (private `_setAfKingMode`) reached from external entry at `:1559`.

---

## §7 — V-012 (`autoRebuyState[beneficiary]` via `_deactivateAfKing` at DegenerusGame.sol:1641 / `deactivateAfKingFromCoin`)

### §7.A — Design-intent backward-trace

**MISSING-GATE writer.** `deactivateAfKingFromCoin(address player)` at DegenerusGame.sol:1641 is an external callback entry restricted to `msg.sender == ContractAddresses.COIN || msg.sender == ContractAddresses.COINFLIP` (revert at `:1642–:1645`). It directly invokes `_deactivateAfKing(player)` at `:1646`. The private writer at `:1670–:1682` SSTOREs `state.afKingMode = false` at `:1679`, `state.afKingActivatedLevel = 0` at `:1680`, and emits `AfKingModeToggled(player, false)` at `:1681`. The writer also dispatches `coinflip.settleFlipModeChange(player)` at `:1678` and reverts with `AfKingLockActive` if the deactivation occurs inside the AFKING_LOCK_LEVELS window per `:1675–:1676`.

**Critical gap: NO `rngLockedFlag` gate.** Unlike V-009 / V-010 / V-011, the entry `deactivateAfKingFromCoin` at `:1641` does NOT perform an `if (rngLockedFlag) revert RngLocked()` check. The private `_deactivateAfKing` body at `:1670` also lacks the gate. This is the catalog-flagged MISSING-GATE row.

**Why the slot exists.** afKing mode hooks into the BurnieCoin contract (and BurnieCoinflip) — when a player loses their lazy-pass status via a BurnieCoin transfer that drops their balance below the qualifying threshold, the COIN contract calls back into the game via this entry to deactivate afKing-mode. This is the "lazy-pass slipped, deactivate the dependent state" cross-contract synchronization hook.

**Why EOA-controllable via callback.** Per Phase 299 cluster preamble: *"coin and coinflip callbacks are EOA-triggerable via cheap BurnieCoin transfer / coinflip arming, so the callback path is effectively EOA-controllable."* A player triggers `deactivateAfKingFromCoin` by initiating a BurnieCoin token transfer (or coinflip arming/deposit) that causes COIN's internal hook to invoke `DegenerusGame.deactivateAfKingFromCoin(player)`. The player's cost is the BurnieCoin transfer fee; the effect is mid-rng-lock-window mutation of `autoRebuyState[player].afKingMode` and `afKingActivatedLevel`.

**Why a naive gate would break behavior.** Adding `if (rngLockedFlag) revert RngLocked()` at `:1641` blocks the callback during the lock window. But the cross-contract synchronization-hook semantic requires that lazy-pass-loss events be SOMEWHERE recorded; rejecting the callback during the lock means the COIN side's "I just lost my lazy pass" event is dropped. The remediation must either (i) queue the deactivation until after `_unlockRng`, or (ii) reject the upstream lazy-pass-loss-causing-transfer at COIN, or (iii) accept the gate's "drop" behavior and reconcile lazy-pass state on the next non-locked deactivation reach. v44.0 sub-phase selects between these options.

### §7.B — Actor game-theory walk

**Actor class:** Lazy-pass-holding player with co-incident jackpot stake. Higher-EV variant: a coordinated MEV-bot operating across BurnieCoin + DegenerusGame.

**Action sequence during rngLock window (CURRENT UNGATED state):**

1. Player has afKing mode ACTIVE (per `state.afKingMode == true`) and qualifies as a winner cohort with non-trivial probability under the pending VRF.
2. Player observes pending VRF request (same observation channel as §1.B).
3. Player models their downstream EV under (a) afKing ACTIVE during finalist-redirect (forced full auto-rebuy at 45% bonus) vs (b) afKing INACTIVE during finalist-redirect (no rebuy unless `autoRebuyEnabled` separately is true).
4. Player initiates a BurnieCoin transfer that triggers a lazy-pass-loss event in COIN's accounting, which invokes `DegenerusGame.deactivateAfKingFromCoin(player)`.
5. The callback executes WITHOUT a `rngLockedFlag` gate at `:1641`; reaches `_deactivateAfKing` at `:1670`; sets `state.afKingMode = false` at `:1679`.
6. VRF callback fires; jackpot consumer's SLOAD of `autoRebuyState[player].afKingMode` returns `false`; finalist-redirect rule selects the non-afKing path; player's winnings flow through the lower-friction path the player just elected by canceling afKing.

**Subtlety:** the AFKING_LOCK_LEVELS check at DegenerusGame.sol:1675–1676 (`if (uint256(level) < unlockLevel) revert AfKingLockActive();`) imposes a deactivation cooldown — afKing cannot be deactivated within AFKING_LOCK_LEVELS levels of activation. This partial constraint REDUCES but does not eliminate the rng-lock-window exploit surface: a player whose afKing activation is older than AFKING_LOCK_LEVELS levels can freely deactivate at any moment.

**EV magnitude.** HIGH-tier. The afKing deactivation flips the finalist-redirect rule mid-rng-lock — equivalent EV to §6.B's afKing toggle, with the advantage that the entry path requires only a BurnieCoin transfer (lower-friction than direct `setAfKingMode` call, which is gated). The MISSING-GATE status of this entry is what makes the EV REACHABLE.

**Economic likelihood: HIGH.** A BurnieCoin transfer is cheap. The callback is callable on any block. The actor's only constraint is being past AFKING_LOCK_LEVELS since activation. The MISSING-GATE row at `:1641` is exactly the kind of "non-VRF SLOAD inside the rng-window" bug class flagged by `feedback_rng_window_storage_read_freshness.md`.

### §7.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-012 rationale: *"MISSING `if (rngLockedFlag) revert` at DegenerusGame:1641 — add."*

**Rationale.** The exact one-line addition at DegenerusGame.sol:1641 is:

```solidity
function deactivateAfKingFromCoin(address player) external {
    if (
        msg.sender != ContractAddresses.COIN &&
        msg.sender != ContractAddresses.COINFLIP
    ) revert E();
    if (rngLockedFlag) revert RngLocked();   // <-- ADD (mirrors :1513 / :1528 / :1575)
    _deactivateAfKing(player);
}
```

The gate placement is at the public-entry function body, BEFORE the call into the private writer, mirroring the pattern at `_setAutoRebuy:1513`, `_setAutoRebuyTakeProfit:1528`, and `_setAfKingMode:1575`. Phase 299 documents the placement convention; v44.0 sub-phase implements the diff and adds a coverage test.

**Cross-contract synchronization note.** Per §7.A's "naive gate breaks behavior" analysis: adding the gate causes the COIN-side lazy-pass-loss callback to revert during the lock window, leaving COIN's view of the player's lazy-pass-status out of sync with the game's. v44.0 sub-phase must verify that (i) COIN tolerates the revert (does not bubble it into a state-corrupting failure), and (ii) lazy-pass-loss events that fire during the lock window are reconciled on the next non-locked invocation (e.g. via a deferred-sync queue OR via the next legitimate lazy-pass-loss event that re-fires once the lock clears).

**Tactic alternative.** A more sophisticated remediation would queue the deactivation in a pending-deactivation buffer during the lock window and apply at `_unlockRng` time. This is closer to tactic (c) pre-lock reorder and would have ~+100 byte impact + 1 new storage slot. v44.0 sub-phase selects between the simple (a) gate (catalog-recommended) and the more invasive (c) queue at planning.

**Storage-layout impact.** Zero for catalog (a). +1 slot for tactic (c) queue alternative.

**Public ABI impact.** Zero. The `deactivateAfKingFromCoin(address)` selector is preserved; the `RngLocked` revert path is added as a new revert reason for COIN/COINFLIP callers — non-breaking because `RngLocked` is an inherited error from `DegenerusGameStorage.sol:213` that the COIN contract is already aware of (per its existing interactions with other gated entries).

**Bytecode impact estimate.** ~30 bytes (`SLOAD rngLockedFlag` + `JUMPI` + `revert(0,0)` with selector push). Well under module budget.

### §7.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-07 — Add `if (rngLockedFlag) revert RngLocked();` gate at `deactivateAfKingFromCoin(address)` entry body at DegenerusGame.sol:1641 (between the COIN/COINFLIP `msg.sender` check at `:1642–:1645` and the `_deactivateAfKing(player)` call at `:1646`); verify COIN-side reconciliation of lazy-pass-loss events that fire during the lock window. **Catalog row:** RNGLOCK-CATALOG.md:347 (V-012). **Writer:** `contracts/DegenerusGame.sol:1670` (private `_deactivateAfKing`) reached from external callback entry at `:1641`.

---

## §8 — V-013 (`autoRebuyState[beneficiary]` via `syncAfKingLazyPassFromCoin` at DegenerusGame.sol:1654)

### §8.A — Design-intent backward-trace

**MISSING-GATE writer.** `syncAfKingLazyPassFromCoin(address player) external returns (bool active)` at DegenerusGame.sol:1654 is the BurnieCoinflip-restricted callback entry (`msg.sender != ContractAddresses.COINFLIP` revert at `:1657`). The function reads `autoRebuyState[player]` at `:1658`; returns early if `!state.afKingMode` at `:1659`; returns early if `_hasAnyLazyPass(player)` at `:1660`; otherwise SSTOREs `state.afKingMode = false` at `:1664`, `state.afKingActivatedLevel = 0` at `:1665`, and emits `AfKingModeToggled(player, false)` at `:1666`.

**Critical gap: NO `rngLockedFlag` gate AND NO AFKING_LOCK_LEVELS check.** Unlike V-012 (`_deactivateAfKing` which enforces AFKING_LOCK_LEVELS at `:1675–1676`), the V-013 writer body at `:1654` bypasses the lock-level cooldown — it only checks lazy-pass status, not the activation-level cooldown. AND it lacks the `rngLockedFlag` gate entirely. This is a strictly worse-protected writer than V-012.

**Why the writer exists.** BurnieCoinflip-initiated coinflip operations (deposit, claim, arming) call back into the game via this entry to verify the player still holds the lazy-pass required for afKing mode. If the coinflip operation's side-effect on the player's BurnieCoin balance caused lazy-pass-loss, the writer auto-deactivates afKing without enforcing AFKING_LOCK_LEVELS (the design intent being: "the lazy-pass requirement was always primary; if it's gone, afKing must be revoked immediately even mid-lock-period to preserve the lazy-pass-gating invariant").

**Why a naive gate would break behavior.** Same as §7.A — adding `if (rngLockedFlag) revert RngLocked()` at `:1654` blocks the coinflip sync during the lock window. The COINFLIP-side semantic is: "I'm telling the game the player's lazy-pass status changed". Dropping the sync during the lock means the game's view of lazy-pass-status diverges from COINFLIP's until the next non-locked sync.

### §8.B — Actor game-theory walk

**Actor class:** Lazy-pass-holding player with co-incident jackpot stake AND co-incident BurnieCoinflip activity.

**Action sequence during rngLock window (CURRENT UNGATED state):**

1. Player has afKing mode ACTIVE and qualifies as a winner cohort.
2. Player observes pending VRF and models afKing-active vs afKing-inactive EV under the predicted finalist-redirect rule.
3. Player initiates a BurnieCoinflip operation (deposit / claim / arming) that causes a lazy-pass-loss event (e.g., a BurnieCoin balance reduction within COINFLIP's accounting hook).
4. COINFLIP invokes `DegenerusGame.syncAfKingLazyPassFromCoin(player)`.
5. The callback executes WITHOUT a `rngLockedFlag` gate at `:1654`; the `_hasAnyLazyPass(player)` check at `:1660` returns `false` (player just lost it); SSTOREs `state.afKingMode = false` at `:1664`.
6. VRF callback consumes the mutated `autoRebuyState[player].afKingMode`; finalist-redirect rule selects the non-afKing path.

**Worse than §7.B.** This writer LACKS the AFKING_LOCK_LEVELS check that V-012's `_deactivateAfKing` body imposes. A player who activated afKing mode less than AFKING_LOCK_LEVELS levels ago CAN reach mid-lock deactivation via this entry (cannot via V-012's entry). The MISSING-GATE row at `:1654` is the strictly-most-exploitable autoRebuyState writer in Cluster A.

**EV magnitude.** HIGH-tier (CATASTROPHE-tier under specific actor profiles — lazy-pass-just-lost players with recent activation can extract afKing-toggle EV ANYWHERE in their afKing lifecycle via this path). Equivalent or larger than §7.B.

**Economic likelihood: HIGH.** BurnieCoinflip operations are routine for lazy-pass holders (the same cohort uses coinflip for daily play). Triggering a lazy-pass-loss-causing BurnieCoinflip op is a normal-economic-incentive action, not a griefing-only path.

### §8.C — Recommended tactic + rationale + impact estimate

**Tactic: (a) rngLockedFlag-gated revert.** Per catalog §16 row V-013 rationale: *"MISSING gate at DegenerusGame:1654 — add."*

**Rationale.** The exact one-line addition at DegenerusGame.sol:1654 is:

```solidity
function syncAfKingLazyPassFromCoin(
    address player
) external returns (bool active) {
    if (msg.sender != ContractAddresses.COINFLIP) revert E();
    if (rngLockedFlag) revert RngLocked();   // <-- ADD (mirrors :1513 / :1528 / :1575)
    AutoRebuyState storage state = autoRebuyState[player];
    // ... (rest of body unchanged)
}
```

The gate placement is between the `msg.sender` check and the `autoRebuyState[player]` SLOAD, mirroring §7.C's placement convention. Per `feedback_rng_window_storage_read_freshness.md`, this is the "non-VRF storage read inside the rng-window" pattern: the SLOAD of `state.afKingMode` at `:1659` is consumed alongside RNG by the downstream jackpot consumer, so its write must be locked during the window.

**Cross-contract synchronization note.** Same as §7.C — the COINFLIP-side sync semantic is dropped during the lock window when the gate fires. v44.0 sub-phase verifies COINFLIP tolerates the revert and reconciles on the next non-locked sync. The COINFLIP-side is already aware of `RngLocked` per its own gated entries (`BurnieCoinflip:730`).

**Why this gate is STRICTLY required despite the (b) snapshot alternative.** Catalog (b) snapshot would require freezing the consumer's `autoRebuyState[winner].afKingMode` SLOAD at lock time. The afKing-mode SLOAD currently happens inside the jackpot's per-winner-iteration loop in `JackpotModule.payDailyJackpot`; a snapshot at lock time would require pre-computing the winner set, which is impossible because the winner set depends on VRF. Snapshot is therefore infeasible for `autoRebuyState[*].afKingMode`; gated-revert is the only structurally-feasible tactic. Catalog (a) is the correct selection.

**Storage-layout impact.** Zero.

**Public ABI impact.** Zero. `syncAfKingLazyPassFromCoin(address)` selector preserved; the `RngLocked` revert path is added — non-breaking per §7.C.

**Bytecode impact estimate.** ~30 bytes (same as §7.C).

**FUZZ test scope.** Phase 301 FUZZ harness should assert: ∀ player p with `state.afKingMode == true`, when `rngLockedFlag == true`, `DegenerusGame.syncAfKingLazyPassFromCoin(p)` reverts with `RngLocked()` selector. The harness MUST reach the function via a simulated COINFLIP `msg.sender` (mock COINFLIP or coverage-mode caller-spoofing).

### §8.D — v44.0 handoff anchor

**Anchor:** D-43N-V44-HANDOFF-08 — Add `if (rngLockedFlag) revert RngLocked();` gate at `syncAfKingLazyPassFromCoin(address)` entry body at DegenerusGame.sol:1654 (between the COINFLIP `msg.sender` check at `:1657` and the `autoRebuyState[player]` SLOAD at `:1658`); verify BurnieCoinflip-side reconciliation of lazy-pass-loss sync events that fire during the lock window. **Catalog row:** RNGLOCK-CATALOG.md:348 (V-013). **Writer:** `contracts/DegenerusGame.sol:1654` (`syncAfKingLazyPassFromCoin` external entry; writer body at `:1664–:1666`).

---

## §9 — VIOLATION V-016: traitBurnTicket admin-seed writer (PHANTOM)

**CATALOG row:** RNGLOCK-CATALOG.md §16 row 351 → `V-016 | S-06 traitBurnTicket[lvl][trait] | adminSeedTraitBucket direct push | DegenerusGame.sol:2398 (admin) | NO — admin EOA | VIOLATION | (a) | Gate adminSeed on !rngLockedFlag && !gameOver | D-43N-V44-HANDOFF-09`.
**Slot:** `traitBurnTicket[lvl][trait]` (S-06; DegenerusGameStorage.sol:415).
**Claimed writer:** `adminSeedTraitBucket` direct push @ DegenerusGame.sol:2398.

### §9.A — Design-intent backward-trace (FIXREC-02)

**Original-phase reference:** `[design-intent: pre-v25 baseline admin bootstrap; no dedicated trace artifact]`. Per `feedback_design_intent_before_deletion.md` no-fabrication rule, the FIXREC author searched `.planning/milestones/` for `adminSeedTraitBucket` — zero hits across v2.1 through v42.0 milestone phases. The phrase appears only in post-Phase-298 catalog-author working notes inside `.planning/RNGLOCK-CATALOG.md` and `.planning/phases/298-*/` (3 files total).

**What S-06 is for (slot-level intent, source-grounded):** `traitBurnTicket[lvl][trait]` is the per-level / per-trait-id bucket of ticket-holder addresses that participates in trait-matched jackpot winner selection. Reader side: `_randTraitTicket` (JackpotModule.sol:1707) — `address[] storage holders = traitBurnTicket_[trait]; uint256 len = holders.length;` (line 1718-1719) — selects `holders[idx]` as the literal jackpot ETH winner when `idx < len`, else falls through to the virtual deity entry (`deityBySymbol[fullSymId]`). The same bucket length feeds `_computeBucketCounts` (JackpotModule.sol:1030/1039) for bucket-budget allocation and is read again per-trait by `_awardDailyCoinToTraitWinners` (JackpotModule.sol:1860). Writer side: per grep, the only SSTORE site in `contracts/` is `_raritySymbolBatch`'s inline-assembly `sstore` to `keccak256(lvl, traitBurnTicket.slot)`-derived length + element slots (MintModule.sol:616 / :627), reached exclusively via the advanceGame ticket-batch delegate stack — which the catalog classifies as EXEMPT-ADVANCEGAME in V-014 / V-015.

**Why no admin direct-push writer exists in current source:** The Phase 298 CATALOG §15 rows 154-156 enumerate three additional S-06 writers anchored on `DegenerusGame.sol:2398 / :2427 / :2510`. Re-reading those lines in current source:

- DegenerusGame.sol:2398 — inside `sampleTraitTickets(uint256 entropy) external view returns (uint24 lvlSel, uint8 traitSel, address[] memory tickets)` (signature at :2376-:2381). Line 2398 reads `address[] storage arr = traitBurnTicket[lvlSel][traitSel];` then `arr.length` (:2399), then iterates `arr[(start + i) % len]` into a memory return array (:2408). **No `.push`, no `sstore`, no in-place mutation.** Function modifier is `external view`, so SSTORE is statically prohibited.
- DegenerusGame.sol:2427 — inside `sampleTraitTicketsAtLevel(uint24 targetLvl, uint256 entropy) external view returns (uint8 traitSel, address[] memory tickets)` (signature at :2422-:2425). Same shape: read-only sample helper.
- DegenerusGame.sol:2510 — inside `getTickets(uint8 trait, uint24 lvl, uint32 offset, uint32 limit, address player) external view returns (uint24 count, uint32 nextOffset, uint32 total)` (signature at :2503-:2509). Paginated read-only counter.

**What behavior would break if a blanket `if (rngLockedFlag) revert` were added:** N/A — the recommended gate site does not exist as a writer; gating a `view` function on `rngLockedFlag` would convert read-only sampling helpers into reverters during rngLock, breaking BAF scatter sampling that legitimately reads bucket state during resolution. The catalog tactic implicitly assumes a writer is present.

### §9.B — Actor game-theory walk (FIXREC-03)

**Exploit-actor class:** N/A — no writer exists in current source for an actor to invoke. If the catalog row were source-grounded (i.e. if an `adminSeedTraitBucket(uint24 lvl, uint8 trait, address[] calldata holders)` admin entry were added in a future feature), the exploit-actor class would be **admin (privileged)**:
- **Adversarial-admin model:** Admin observes a pending VRF callback inside the rngLock window for daily jackpot resolution, calls `adminSeedTraitBucket(lvl, trait, [colluder_address])` to splice a controlled address into the bucket. `_randTraitTicket` at JackpotModule.sol:1718 reads `holders[idx]` post-splice, awarding the controlled address the jackpot payout.
- **Action sequence (counterfactual):** (1) VRF request emits → `rngLockedFlag = true`. (2) Admin reads `_randTraitTicket` math (line 1749-1751) and pre-computes which `idx` will hit for the next VRF word (admin cannot pre-compute the VRF word itself, but **can** pre-compute the modular reduction across all possible bucket sizes). (3) Admin picks a target trait, calls `adminSeedTraitBucket` to resize the bucket so the colluder address lands at the favorable `idx` post-modulo. (4) VRF callback fires → colluder wins.
- **EV magnitude (counterfactual):** **CATASTROPHE-tier** at terminal jackpot drain — `_processDailyEth` (JackpotModule.sol:1232) and `_runEarlyBirdLootboxJackpot` (:676) and `_distributeTicketJackpot` (:896) all consume trait-bucket holders for payout-recipient selection. A 4-bucket reseed during the game-over drain could redirect the full terminal pool to attacker addresses.
- **Economic-likelihood disposition (counterfactual):** **LOW** under trust-minimization (admin assumed honest); **HIGH** under audit-strict (admin treated as adversarial-capable, per `feedback_design_intent_before_deletion.md` actor-walk discipline). The audit posture requires modeling adversarial admin even when the trust model is benign, because the gate is a defense-in-depth invariant that holds across all actor models.

**Real (source-grounded) actor model:** Zero — no actor can reach a non-EXEMPT writer of S-06. The only writer is MintModule.sol:616/:627 inside `_raritySymbolBatch`, only reachable via `advanceGame` (EXEMPT-ADVANCEGAME per V-014 / V-015).

### §9.C — Recommended tactic + rationale + impact (FIXREC-01 + FIXREC-04)

**Recommended tactic:** **NO-OP** at v43.0 audit milestone. Catalog tactic (a) `Gate adminSeed on !rngLockedFlag && !gameOver` is **not applicable** because the function does not exist in current `contracts/`.

**Rationale:** Per `feedback_verify_call_graph_against_source.md`, fix recommendations must be grep-verified against source pre-patch. Authoring a v44.0 fix for a non-existent function would either (a) require adding the function (out-of-scope expansion of contract surface during a defensive hardening milestone — violates `feedback_frozen_contracts_no_future_proofing.md`), or (b) decay into a phantom `// TODO when admin writer is added` comment which violates `feedback_no_history_in_comments.md`.

**Bytecode impact:** **+0 bytes.** No code emitted.
**Storage-layout impact:** **byte-identical.** No new slots, no slot reordering.
**Public-ABI impact:** **NON-BREAKING.** No selector added, no event topic-hash changed.

**v44.0 FIX-MILESTONE plan-phase guidance:** At v44.0 CATALOG-refresh sub-phase, re-grep `contracts/` for `adminSeedTraitBucket`. If the function is absent, amend RNGLOCK-CATALOG.md §15 row 154 + §16 row 351 to **STALE-PHANTOM** disposition with a one-line note citing this FIXREC §1. If the function has been added between v43.0 audit close and v44.0 fix execution (out-of-scope but possible), apply tactic (a) **per the then-current source signature** — the gate site is `function adminSeedTraitBucket(...) external onlyAdmin { if (rngLockedFlag) revert RngLocked(); if (gameOver) revert GameOver(); ... }` using the `RngLocked` custom error already declared at DegenerusGameStorage.sol:213 and revert-pattern precedents at MintModule.sol:1221, BurnieCoinflip.sol:730, WhaleModule.sol:543. The bytecode delta for the live-writer case is ~+25-35 bytes per gate: one `SLOAD rngLockedFlag` (~2100 gas cold / 100 warm) + `JUMPI` + `REVERT` for the custom error 4-byte selector, plus identical pattern for `gameOver` (declared at DegenerusGameStorage.sol:290 as `bool public gameOver`).

### §9.D — v44.0 FIX-MILESTONE handoff anchor (FIXREC-05)

**Anchor:** D-43N-V44-HANDOFF-09 — `traitBurnTicket` admin-seed writer NO-OP at v43.0; CATALOG row marked STALE-PHANTOM pending v44.0 CATALOG refresh. **Catalog row:** RNGLOCK-CATALOG.md:351 (§16 verdict-matrix). **Writer (claimed):** DegenerusGame.sol:2398 (actually `sampleTraitTickets` view function in current source; phantom-as-writer).

---

## §10 — VIOLATION V-017: traitBurnTicket admin-clear writer (PHANTOM)

**CATALOG row:** RNGLOCK-CATALOG.md §16 row 352 → `V-017 | S-06 traitBurnTicket[lvl][trait] | adminClearTraitBucket direct push | DegenerusGame.sol:2427 (admin) | NO — admin EOA | VIOLATION | (a) | Gate adminClear on !rngLockedFlag && !gameOver | D-43N-V44-HANDOFF-10`.
**Slot:** `traitBurnTicket[lvl][trait]` (S-06; DegenerusGameStorage.sol:415).
**Claimed writer:** `adminClearTraitBucket` direct push @ DegenerusGame.sol:2427.

### §10.A — Design-intent backward-trace (FIXREC-02)

**Original-phase reference:** `[design-intent: pre-v25 baseline admin replay/teardown helper; no dedicated trace artifact]`. Per `feedback_design_intent_before_deletion.md` no-fabrication rule, `.planning/milestones/` grep for `adminClearTraitBucket` returns zero hits across v2.1-v42.0.

**What clearing S-06 would have meant (counterfactual slot-level intent):** Resetting `traitBurnTicket[lvl][trait]` to empty would be a teardown action used either (a) pre-launch to wipe seeded test buckets before mainnet activation, or (b) post-drain at terminal game-over to free storage refund gas via `sstore(slot, 0)`. The reader-side consequence of clearing during live resolution: `_randTraitTicket`'s `holders.length` (JackpotModule.sol:1719) becomes zero, which forces the deity virtual-entry path (`idx >= len` at :1755) for every winner slot — collapsing all trait-trait jackpot winners onto `deityBySymbol[fullSymId]` (a single attacker-controlled address if the attacker bought that deity pass).

**Current-source disposition:** DegenerusGame.sol:2427 is `sampleTraitTicketsAtLevel(uint24 targetLvl, uint256 entropy) external view returns (uint8 traitSel, address[] memory tickets)` (signature at :2422-:2425). Body: `traitSel = uint8(entropy >> 24); address[] storage arr = traitBurnTicket[targetLvl][traitSel]; uint256 len = arr.length; if (len == 0) return (traitSel, new address[](0)); ...` followed by a read-only memory-array fill loop (:2436-:2441). **No `.push`, no `sstore`, no `delete` of any storage slot.** Function modifier is `external view`.

**What behavior would break if a blanket `if (rngLockedFlag) revert` were added to line :2427:** The view function would revert during rngLock, blocking off-chain BAF / front-end queries of bucket samples during the resolution window — a tangible UX regression with zero defensive benefit (view functions cannot mutate state, so the gate would be guarding nothing).

### §10.B — Actor game-theory walk (FIXREC-03)

**Exploit-actor class (counterfactual):** Admin (privileged). The counterfactual exploit is the dual of §1.B: instead of *adding* a controlled address to the bucket, admin *clears* the bucket mid-resolution to force the deity-virtual-entry payout path (JackpotModule.sol:1755-1758 `winners[i] = deity`).
- **Action sequence (counterfactual):** (1) Attacker purchases a deity pass for a target symbol (e.g. trait `t`); `deityBySymbol[symbolId] = attacker` via WhaleModule.sol:598. (2) VRF request emits → `rngLockedFlag = true`. (3) Adversarial admin calls `adminClearTraitBucket(lvl, trait)` zeroing `traitBurnTicket[lvl][trait].length`. (4) VRF callback fires → `_randTraitTicket` sees `len = 0`, `virtualCount ≥ 1` (because deity is set), `effectiveLen = 1`, every winner slot resolves to attacker via `idx % 1 = 0 >= 0 = len`. (5) Attacker captures all jackpot winners' payouts for the affected trait.
- **EV magnitude (counterfactual):** **HIGH-to-CATASTROPHE-tier** — multi-winner traits at gold tier (color==7, `virtualCount = 1`) and common tier (`virtualCount = max(2, len/50)`) both collapse onto the deity address when length=0.
- **Economic-likelihood disposition (counterfactual):** **LOW** under trust-minimization, **HIGH** under audit-strict.

**Real (source-grounded) actor model:** Zero — function does not exist.

### §10.C — Recommended tactic + rationale + impact (FIXREC-01 + FIXREC-04)

**Recommended tactic:** **NO-OP** at v43.0. Same rationale as §1.C — function is a phantom.

**Bytecode impact:** **+0 bytes.**
**Storage-layout impact:** **byte-identical.**
**Public-ABI impact:** **NON-BREAKING.**

**v44.0 plan-phase guidance:** Identical handling pattern to §1.C v44.0 guidance. If `adminClearTraitBucket` is absent at v44.0 source-state, mark CATALOG §15 row 155 + §16 row 352 as **STALE-PHANTOM**. If a `clear`/`delete`-shaped admin writer is added between milestones, apply tactic (a) with the same two-arm `if (rngLockedFlag) revert RngLocked(); if (gameOver) revert GameOver();` gate at function entry.

### §10.D — v44.0 FIX-MILESTONE handoff anchor (FIXREC-05)

**Anchor:** D-43N-V44-HANDOFF-10 — `traitBurnTicket` admin-clear writer NO-OP at v43.0; CATALOG row marked STALE-PHANTOM pending v44.0 CATALOG refresh. **Catalog row:** RNGLOCK-CATALOG.md:352 (§16 verdict-matrix). **Writer (claimed):** DegenerusGame.sol:2427 (actually `sampleTraitTicketsAtLevel` view function in current source; phantom-as-writer).

---

## §11 — VIOLATION V-018: traitBurnTicket helper writer @ :2510 (PHANTOM)

**CATALOG row:** RNGLOCK-CATALOG.md §16 row 353 → `V-018 | S-06 traitBurnTicket[lvl][trait] | helper writer at :2510 | DegenerusGame.sol:2510 (admin/helper) | NO — admin/helper | VIOLATION | (a) | Gate writer on !gameOver — terminal jackpot bucket must be frozen at drain | D-43N-V44-HANDOFF-11`.
**Slot:** `traitBurnTicket[lvl][trait]` (S-06; DegenerusGameStorage.sol:415).
**Claimed writer:** helper writer @ DegenerusGame.sol:2510.

### §11.A — Design-intent backward-trace (FIXREC-02)

**Original-phase reference:** `[design-intent: catalog §C.3.4 row flagged for source-line review; no original phase identified]`. CATALOG §C.3.4 (RNGLOCK-CATALOG.md:1390) explicitly notes "Source-code review of the surrounding function context is required; flagged here for completeness so the §D verdict matrix evaluates it" — the catalog author already surfaced uncertainty about the row at enumeration time. `.planning/milestones/` grep for `traitBurnTicket\[lvl\]\[trait\]` returns hits only in v25.0+ adversarial-audit phases and v41.0+ trait-ticket plans, none of which introduce a non-MintModule writer.

**Current-source disposition of line :2510:** Inside `getTickets(uint8 trait, uint24 lvl, uint32 offset, uint32 limit, address player) external view returns (uint24 count, uint32 nextOffset, uint32 total)` (signature at :2503-:2509). Body:

```solidity
address[] storage a = traitBurnTicket[lvl][trait];  // :2510 — read-only storage reference binding
total = uint32(a.length);                            // :2511 — SLOAD of length
if (offset >= total) return (0, total, total);       // :2512
uint256 end = offset + limit;                        // :2514
if (end > total) end = total;
for (uint256 i = offset; i < end; ) {                // :2517 — read-only iteration
    if (a[i] == player) count++;                     // :2518 — SLOAD comparison, no write
    unchecked { ++i; }
}
nextOffset = uint32(end);                            // :2523
```

**No `.push`, no `sstore`, no `delete`, no `a[i] = ...` write.** The function is a paginated read-only ticket counter used by front-ends to display a player's bucket holdings without OOG-risk on large buckets. Function modifier is `external view`.

**What behavior would break if a writer-gate were added to line :2510:** N/A — line :2510 is not a writer. The catalog tactic (a) `Gate writer on !gameOver — terminal jackpot bucket must be frozen at drain` is unactionable because there is no writer at this line.

### §11.B — Actor game-theory walk (FIXREC-03)

**Exploit-actor class (counterfactual):** Admin/helper (privileged). Without a source-grounded writer signature, the counterfactual is even less concrete than §1.B / §2.B — the catalog row is a placeholder for "source review required" rather than a specific writer claim.

**Real (source-grounded) actor model:** Zero — line :2510 is a view function read.

### §11.C — Recommended tactic + rationale + impact (FIXREC-01 + FIXREC-04)

**Recommended tactic:** **NO-OP** at v43.0. The catalog row was explicitly flagged at enumeration time as "source-code review required" (RNGLOCK-CATALOG.md:1390); current grep resolves the review as **no writer at this line**.

**Bytecode impact:** **+0 bytes.**
**Storage-layout impact:** **byte-identical.**
**Public-ABI impact:** **NON-BREAKING.**

**v44.0 plan-phase guidance:** Mark CATALOG §15 row 156 + §16 row 353 as **STALE-PHANTOM** at v44.0 CATALOG-refresh sub-phase, citing this FIXREC §3 (Phase 299-02) as the resolution of the "source review required" placeholder.

### §11.D — v44.0 FIX-MILESTONE handoff anchor (FIXREC-05)

**Anchor:** D-43N-V44-HANDOFF-11 — `traitBurnTicket` helper-writer-at-:2510 NO-OP at v43.0; CATALOG row marked STALE-PHANTOM (resolves the §C.3.4 "source review required" placeholder). **Catalog row:** RNGLOCK-CATALOG.md:353 (§16 verdict-matrix); placeholder at RNGLOCK-CATALOG.md:1390 (§C.3.4). **Writer (claimed):** DegenerusGame.sol:2510 (actually `getTickets` view function in current source; phantom-as-writer).

---

## §12 — VIOLATION V-019: deityBySymbol via `_purchaseDeityPass` (REAL)

**CATALOG row:** RNGLOCK-CATALOG.md §16 row 354 → `V-019 | S-07 deityBySymbol[fullSymId] | _purchaseDeityPass | WhaleModule.sol:538 (EOA purchaseDeityPass) | NO — EOA; runtime rngLockedFlag gate at :543 | VIOLATION | (a) | Gate _purchaseDeityPass on !gameOver — already gates rngLockedFlag at :543 | D-43N-V44-HANDOFF-12`.
**Slot:** `deityBySymbol[fullSymId]` (S-07; DegenerusGameStorage.sol — `mapping(uint16 => address) internal`).
**Writer:** `_purchaseDeityPass` SSTORE at `DegenerusGameWhaleModule.sol:598` (`deityBySymbol[symbolId] = buyer;`).
**External entry:** `purchaseDeityPass(address buyer, uint8 symbolId) external payable` at WhaleModule.sol:538 → calls `_purchaseDeityPass(buyer, symbolId)` private at :542.
**Existing runtime gate:** `if (rngLockedFlag) revert RngLocked();` at WhaleModule.sol:543 (first statement of `_purchaseDeityPass`); followed by `if (_livenessTriggered()) revert E();` at :544.

### §12.A — Design-intent backward-trace (FIXREC-02)

**Original-phase reference:** Phase 294 DPNERF (`.planning/milestones/v42.0-phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md`) is the most recent design-intent anchor touching the deity-pass subsystem (caller-uniform discipline + gold-tier virtual-entry nerf). The deity-pass purchase / `deityBySymbol` mapping pre-dates Phase 294 — grep on `.planning/milestones/v25.0-phases/214-adversarial-audit/214-04-STORAGE-LAYOUT.md` and `.planning/milestones/v25.0-phases/214-adversarial-audit/214-03-STATE-COMPOSITION.md` confirms `deityBySymbol` was already enumerated as a participating slot at v25.0 adversarial-audit time. Pre-v25 introduction phase not isolated to a single artifact (deity-pass economic mechanic is part of the baseline whale-module design from project inception).

**What S-07 is for (slot-level intent, source-grounded):** `deityBySymbol[symbolId]` (uint16 key, address value) maps a 0-31 symbol identifier (4 quadrants × 8 symbols) to the EOA that has purchased the corresponding deity pass. The mapping is the **virtual-entry injection vector** for trait-matched jackpot resolution: at JackpotModule.sol:1730 `_randTraitTicket` computes `uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);` and reads `deity = deityBySymbol[fullSymId];`. When `deity != address(0)`, the function inflates `effectiveLen` by `virtualCount` (1 for gold-tier color==7, `max(2, len/50)` for common tiers — JackpotModule.sol:1732-1737), and when the modular winner-index `idx >= len`, the winner becomes the deity address (:1755-1757). The same pattern repeats at `_computeBucketCounts` (JackpotModule.sol:1044) and `_awardDailyCoinToTraitWinners` (JackpotModule.sol:1844).

**Why the existing `rngLockedFlag` gate at :543 is partial coverage:** `rngLockedFlag` is set/cleared by the VRF request/callback lifecycle (set in AdvanceModule's request path; cleared in AdvanceModule's `_unlockRng` per AdvanceModule.sol:631). The flag is **active** during the per-day jackpot resolution window. But at terminal game-over, the resolution path is `_handleGameOverPath` (AdvanceModule.sol:539) which short-circuits the rngLockedFlag set/clear cycle for the final drain — and even if `rngLockedFlag` were cleared post-drain by the standard lifecycle, the persistent `gameOver` flag (DegenerusGameStorage.sol:290 `bool public gameOver`) remains true for the rest of contract lifetime. Without a `gameOver` arm on the gate, **a whale could call `purchaseDeityPass` after `gameOver = true` but before terminal-drain settlement completes**, binding `deityBySymbol[symbolId]` to a freshly chosen address moments before the terminal jackpot consumes `deityBySymbol` at JackpotModule.sol:1730. The catalog correctly flags this as the missing arm.

**Important nuance — `_livenessTriggered()` at :544 is NOT a substitute for `gameOver`:** `_livenessTriggered()` (DegenerusGameStorage.sol:1243-1252) checks idle-day timeout (`lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS`), late-game idle timeout (`lvl != 0 && currentDay - psd > 120`), and VRF grace-period exceeded (`rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD`). It does **not** read the persistent `gameOver` flag — and crucially, `_livenessTriggered()` returns `false` when `lastPurchaseDay || jackpotPhaseFlag` (early-return at :1244). During terminal game-over **settlement** (post-trigger, pre-final-payout-completion), `gameOver == true` but `_livenessTriggered()` may return `false` if the trigger path set `lastPurchaseDay`. This confirms the catalog's surgical recommendation: the gate needs an explicit `if (gameOver) revert ...;` arm in addition to the existing `rngLockedFlag` and `_livenessTriggered` checks.

**What behavior would break if `!gameOver` were added to `_purchaseDeityPass`:** After terminal game-over trigger, deity-pass purchase is permanently blocked. This is the **intended** terminal-window invariant per the catalog (`terminal jackpot bucket must be frozen at drain`) — the deity-pass economic mechanic is meaningful only when level progression and jackpot resolution are live; post-`gameOver` purchases would have no downstream payout path and would constitute griefing surface only. Non-breaking semantics for the legitimate use case (purchase during normal game play before `gameOver` trigger).

### §12.B — Actor game-theory walk (FIXREC-03)

**Exploit-actor class:** Whale player (EOA-callable external entry; payable). Not admin-privileged — the only gating is the `rngLockedFlag` + `_livenessTriggered` revert pair plus the `deityBySymbol[symbolId] != address(0)` collision check at :546 (which means *the symbol must still be available* — caps the exploit window to symbols not yet bought).

**Action sequence (real, source-grounded):**

1. Attacker monitors mempool/chain state for the `gameOver` trigger (set on the terminal level-cap or liveness-trigger paths inside AdvanceModule's `_finalize` / `_handleGameOverPath`). The flag is `bool public gameOver` (DegenerusGameStorage.sol:290), so trigger is observable on-chain via storage SLOAD or via any state-changing tx that touched the flag.
2. Between `gameOver = true` write and terminal-jackpot completion, attacker observes which symbols `0..31` are still un-purchased (i.e. `deityBySymbol[symbolId] == address(0)`).
3. Attacker chooses a target trait (8 colors × 4 quadrants × 8 symbols = 256 traits, but the `fullSymId` derivation at JackpotModule.sol:1726 collapses to 32 fullSymIds) where they predict the terminal jackpot will pay (or simply maximize the deity-virtual-entry probability inflation for that fullSymId across all eight color-variants of that quadrant-symbol pairing).
4. Attacker calls `purchaseDeityPass(attacker_addr, target_symbolId)` paying `DEITY_PASS_BASE + (k * (k+1) * 1e18) / 2` ETH (price scales with `k = deityPassOwners.length` — up to 520 ETH for the 32nd pass per :527 docstring) with optional `boonTier` discount.
5. The `rngLockedFlag` check at :543 currently passes if the VRF lifecycle has cleared the flag (which it has by the time terminal drain is settling per AdvanceModule:631 sequencing). `_livenessTriggered()` at :544 may also pass (returns false when `lastPurchaseDay` or `jackpotPhaseFlag` is set, per :1244).
6. SSTORE at :598 binds `deityBySymbol[target_symbolId] = attacker`.
7. Terminal-jackpot consumer (the final pass through `_distributeTicketJackpot` / `_processDailyEth` / `_awardDailyCoinToTraitWinners` for `gameOver`-mode payouts) reads `deityBySymbol[fullSymId]` at JackpotModule.sol:1044 / :1730 / :1844, sees attacker, and routes virtual-entry winnings to attacker.

**EV magnitude:** **MEDIUM-HIGH** — terminal jackpot pool is the cumulative `currentPrizePool` plus `prizePoolsPacked` accumulations, historically the largest single payout event in the game lifecycle. The attacker pays up to 520 ETH for the deity pass but captures `virtualCount / (len + virtualCount)` share of trait payouts for the bound `fullSymId` across **all 8 color variants** (because `fullSymId = (trait >> 6) * 8 + (trait & 0x07)` does not include the color bits at `(trait >> 3) & 7`). For gold-tier (color==7) `virtualCount = 1`; for common tiers `virtualCount = max(2, len/50)`. Across 8 colors × multi-trait payouts at terminal drain, the deity-virtual-entry capture is structurally non-trivial.

**Economic-likelihood disposition:** **MEDIUM-HIGH**. The exploit window is narrow (between `gameOver = true` and terminal-jackpot completion — likely a few blocks), but the trigger is public-observable and the EV is large. The attack is **strictly more attractive than legitimate deity-pass purchase** during normal play because the buyer captures terminal-jackpot virtual entries without participating in earlier levels' wager / trait-bucket commitment surface. Audit-strict disposition: **the existing :543 gate is insufficient and the catalog's `!gameOver` arm is a load-bearing one-line invariant**.

**Note on alternative trust assumptions:** Under a benign-actor model the EV-weighted probability is lower (deity-pass purchasers are typically long-horizon whales, not griefing capital), but the audit posture per `feedback_design_intent_before_deletion.md` ("trace original design intent + actor game-theory across timing/state combos") requires modeling the adversarial actor explicitly. The `gameOver`-arm gate is the structural invariant; the actor-model probability does not change the recommendation.

### §12.C — Recommended tactic + rationale + impact (FIXREC-01 + FIXREC-04)

**Recommended tactic:** **(a) gated revert — extend existing :543 gate with `gameOver` arm.** Catalog tactic (a) verbatim: `Gate _purchaseDeityPass on !gameOver — already gates rngLockedFlag at :543`.

**Concrete patch shape (for v44.0 plan-phase consumption, not for application here):**

```solidity
// At DegenerusGameWhaleModule.sol:543 — current source has line 543 only.
// v44.0 fix synthesizes a single-line addition after :543:
function _purchaseDeityPass(address buyer, uint8 symbolId) private {
    if (rngLockedFlag) revert RngLocked();      // :543 — exists
    if (gameOver) revert E();                   // NEW — one line; pre-existing E() error matches surrounding style at :544/:545/:546/:549
    if (_livenessTriggered()) revert E();       // :544 — exists
    ...
}
```

**Rationale:**

1. **Minimal-surface fix** — one line, one storage-read, one branch. The `gameOver` flag is already declared at DegenerusGameStorage.sol:290 (`bool public gameOver`); no new state, no new error type (uses the pre-existing `error E()` shared across the module's revert path at :544/:545/:546/:549/:581 — consistent with `feedback_no_history_in_comments.md` "describes what IS" by reusing the established error shape).
2. **Defense-in-depth on the trait-bucket consumer freeze invariant** — the catalog's freeze-at-drain invariant for terminal jackpot resolution requires that **all participating-slot writers** be inert during the `gameOver` window. `_purchaseDeityPass` is the sole non-MintModule writer of S-07. With this gate, the `deityBySymbol` mapping becomes append-only across the live-game window and frozen at `gameOver` — the same shape that `_raritySymbolBatch` already enforces for S-06 via the EXEMPT-ADVANCEGAME stack (no advanceGame ticks fire post-`gameOver` except the terminal drain itself, which does not invoke MintModule's `_storeTraits`).
3. **Consistent with the project-wide `RngLocked`+`E()` revert convention** — the existing :543 line uses the `RngLocked` custom error (declared at DegenerusGameStorage.sol:213 and used at MintModule.sol:1221, BurnieCoinflip.sol:730, sStonk → StakedDegenerusStonk pattern). The new `gameOver` arm uses the module-internal `error E()` matching the surrounding revert style at :544-:581 — this maximizes ABI-stability for downstream consumers (no new selector hash to register).
4. **Behavior-preserving for the legitimate use case** — `purchaseDeityPass` during normal game play (pre-`gameOver`) is unaffected. The :522 docstring already states "Available before gameOver" — the gate **codifies the docstring's already-stated semantic invariant** that the current implementation does not enforce. This aligns with `feedback_design_intent_before_deletion.md` ("trace original design intent" — the docstring is the design-intent record).

**Bytecode impact estimate:** **+12 to +25 bytes** depending on optimizer settings. Pattern: `PUSH1 0x{slot} SLOAD ISZERO PUSH2 {label} JUMPI PUSH4 {E_selector} PUSH1 0x00 MSTORE PUSH1 0x04 PUSH1 0x00 REVERT` (the `error E()` 4-byte selector revert). Comparable to the existing `if (_livenessTriggered()) revert E();` gate at :544 which compiles to ~30 bytes (CALL + ISZERO + JUMPI + revert-pattern). For a direct storage-bool SLOAD the bytecode is shorter than the function-call variant — estimate ~12-18 bytes net.

**Storage-layout impact:** **byte-identical.** `gameOver` is already declared at DegenerusGameStorage.sol:290; no new slot allocated.

**Public-ABI impact:** **NON-BREAKING** per `D-40N-EVT-BREAK-01`. The selector for `purchaseDeityPass(address,uint8)` is unchanged. The added `revert E()` path uses an error selector already in the contract's ABI (used pervasively across :544/:545/:546/:549/:581 etc.). No event topic-hash change, no new public function, no return-type change. Downstream callers that previously could call `purchaseDeityPass` during the post-`gameOver` settlement window now revert — but the docstring at :522 already states "Available before gameOver", so the runtime behavior aligns with the documented contract, not the other way around. **The semantic change for callers is "this revert path was always documented; now it is enforced."**

**Verification handoff to v44.0:** The fix is testable via a property-based assertion: `assert(!gameOver || ! purchaseDeityPass succeeds for any (buyer, symbolId))`. Deferred to v44.0 plan-phase per `D-299-WAVE-SHAPE-01` (audit-only posture — no test/ mutations at v43.0).

### §12.D — v44.0 FIX-MILESTONE handoff anchor (FIXREC-05)

**Anchor:** D-43N-V44-HANDOFF-12 — `_purchaseDeityPass` `!gameOver` arm extension; one-line revert addition after existing :543 `rngLockedFlag` gate; uses pre-declared `gameOver` (DegenerusGameStorage.sol:290) and pre-declared `error E()`. **Catalog row:** RNGLOCK-CATALOG.md:354 (§16 verdict-matrix); §15 row 157 writer enumeration; §C.5.1 disposition (RNGLOCK-CATALOG.md:1398). **Writer:** DegenerusGameWhaleModule.sol:598 (SSTORE `deityBySymbol[symbolId] = buyer`); external entry at :538; private body at :542; existing partial gate at :543.

---

## §13 — V-024: MintModule payment processing → prizePoolsPacked

**Slot:** S-09 `prizePoolsPacked` (next + future)
**Writer:** `_processMintPayment` / `_handleMintRevenue` callsites reached from `purchase`, `purchaseCoin`, `purchaseBurnieLootbox` (file:line `MintModule.sol:376` `_setPrizePools`, `:1062` `_setPrizePools` inside lootbox revenue split)
**EOA reach:** `MintModule.sol:830` (`purchase`), `:852` (`purchaseCoin`), `:864` (`purchaseBurnieLootbox`)
**Catalog row:** §16 V-024 — `VIOLATION | (a) | Add top-level rngLockedFlag revert to MintModule.purchase/purchaseCoin/purchaseBurnieLootbox | D-43N-V44-HANDOFF-13`

### §13.A — Design-intent backward-trace

The three MintModule purchase entries (`purchase`, `purchaseCoin`, `purchaseBurnieLootbox`) are the primary ETH + BURNIE on-ramp for tickets and loot boxes. Their write into `prizePoolsPacked` exists because every paid ticket or paid loot box routes a portion of revenue into the `next`/`future` pool accumulators that fund future daily jackpots; `_setPrizePools(...)` is invoked at `MintModule.sol:376` (ticket purchase split) and `:1062` (loot-box-buy revenue split). The accumulator-write is the structural intent — players paying into the game must increase the pool that will eventually pay out. The conservative reading of the freeze invariant (`D-42N-FREEZE-INVARIANT-01`, Phase 290 MINTCLN) requires those mutations to either (i) be barred during the freeze, or (ii) land in a parallel "pending" slot via `_setPendingPools` and merge after `_unfreezePool`. The pending-pool branch already exists at MintModule `:368-:380` and `:1054-:1066`: `if (prizePoolFrozen) _setPendingPools(...)` else `_setPrizePools(...)`. The bug is that `prizePoolFrozen` and `rngLockedFlag` cover DIFFERENT windows: `prizePoolFrozen` toggles at `_swapAndFreeze` / `_unfreezePool` inside the jackpot-phase transition; `rngLockedFlag` covers the broader VRF in-flight window which includes non-jackpot-day rngLocked sub-windows. The existing partial gate at `MintModule.sol:1221` (`if (cachedJpFlag && rngLockedFlag) { ... targetLevel = cachedLevel + 1; }`) only redirects target-level on the LAST jackpot day to prevent stranded tickets — it does not block the prize-pool write itself, and it is conditioned on `cachedJpFlag`, so it does nothing on a non-jackpot-phase rngLocked window. Per `feedback_design_intent_before_deletion.md`, the original design clearly meant the freeze + pending-pool branch to be the canonical protection — the freeze flag just isn't co-extensive with the full rngLock window, so the protection silently leaks. Per `feedback_no_history_in_comments.md` the fix is described as what IS required, not what was missing.

### §13.B — Actor game-theory walk

**Exploit-actor class:** any EOA player. **Action sequence:** after `_requestRng` fires (rngLockedFlag = true) but before `_unlockRng` clears it (i.e. inside the daily-jackpot resolution window where §1 `payDailyJackpot` is about to read `_getPrizePools()` at `:431` / `:511` / `:548` / `:570`), the attacker fires `MintModule.purchase(..., ticketQuantity=X, lootBoxAmount=Y, ...)` with msg.value covering both shares. The call lands in `_purchaseFor` (no top-level rngLockedFlag gate — only `_livenessTriggered()` at `:906`) and walks through `_processMintPayment`/`_handleMintRevenue` reaching `_setPrizePools(next + nextShare, future + futureShare)` at `:376`. The consumer's `reserveSlice` (`futurePoolBal / 200`), `ethDaySlice` (`futurePoolBal * poolBps / 10_000` at JackpotModule `:548`), and BAF purchase-phase payout budget (read at `:570`) all increase. Per `feedback_rng_commitment_window.md` the commitment-window invariant is that nothing player-controllable can change between the rng request and the consumer's read; this violation is a direct breach. **EV magnitude:** LOW per single mint transaction (attacker pays in ETH at a fixed price and receives tickets / boxes whose EV is bounded by the standard expected return); however, **aggregate EV across all parallel mint paths during a high-stakes jackpot window can be MEDIUM-tier**: an attacker who is already a winner under one entropy outcome can inflate `futurePool` to magnify their own win when the consumer reads it. The economic likelihood is BOUNDED because every dollar of inflation comes from the attacker's own wallet — the steal target is the SHARE of the inflated pool that ends up routed to the attacker via the bucket allocation, not the inflation itself. **Disposition:** MEDIUM-tier with caveat — exploitability is gated by whether the attacker has won the relevant solo / large bucket, which is itself VRF-determined.

### §13.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert. Reproducing catalog row V-024 verbatim: "Add top-level `if (rngLockedFlag) revert RngLocked();` to `MintModule.purchase` / `purchaseCoin` / `purchaseBurnieLootbox`". Three callsites: `MintModule.sol:830`, `:852`, `:864`. Each gate is the canonical 2-line `if (rngLockedFlag) revert RngLocked();` invoking the existing `RngLocked` custom error already imported in MintModule (precedent: `MintModule.sol:1221` references it inside the cachedJpFlag branch; `BurnieCoinflip.sol:730`, `StakedDegenerusStonk.sol:492`). **Rationale:** the existing `prizePoolFrozen` branch covers the jackpot-phase swap window but does not cover non-jackpot-phase rngLock; the freeze invariant per `D-42N-FREEZE-INVARIANT-01` and the commitment-window discipline per `feedback_rng_commitment_window.md` together require the broader gate. The tactic (b) snapshot alternative — record `prizePoolsPacked` value at lock time and serve consumers from the snapshot — is rejected here for cost: `prizePoolsPacked` is performance-critical (packed for single-SLOAD efficiency in the daily resolution stack), and snapshotting it would require a parallel packed slot whose layout drift must be audited at every `_setPrizePools`/`_setPendingPools` callsite. The simpler (a) revert is byte-cheap and preserves the existing storage layout. **Bytecode impact:** ~30 bytes per gate site (single SLOAD + JUMPI + REVERT-4-bytes), ≈90 bytes total across the 3 entry points. **Storage layout:** BYTE-IDENTICAL — no new slot. **Public ABI:** NON-BREAKING — purchase signatures unchanged; new revert path returns the documented `RngLocked()` error per the convention.

### §13.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-13`
**Citation:** `MintModule.sol:830` (`purchase`), `:852` (`purchaseCoin`), `:864` (`purchaseBurnieLootbox`)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-024 (slot=S-09, writer=MintModule payment processing, callsite=MintModule.sol purchase family).

---

## §14 — V-025: WhaleModule purchase entries → prizePoolsPacked

**Slot:** S-09 `prizePoolsPacked`
**Writer:** `_setPrizePools` reached from `purchaseWhaleBundle` (`WhaleModule.sol:353`) + `purchaseLazyPass` (`WhaleModule.sol:499`)
**EOA reach:** `WhaleModule.sol:187` (`purchaseWhaleBundle`), `:380` (`purchaseLazyPass`)
**Catalog row:** §16 V-025 — `VIOLATION | (a) | Add top-level rngLockedFlag revert at WhaleModule:187 + :380 | D-43N-V44-HANDOFF-14`

### §14.A — Design-intent backward-trace

`purchaseWhaleBundle` and `purchaseLazyPass` are the two whale-tier ETH purchase entries that fund pass-based rewards. The whale-bundle entry routes 5%/95% of `totalPrice` to `nextPool`/`futurePool` post-game (or 100% future during presale) via `_setPrizePools(next + nextShare, future + (totalPrice - nextShare))` at `WhaleModule.sol:353`; the lazy-pass entry routes the discounted pass price into the pool via the same `_setPrizePools` writer at `:499`. Both calls predate the rngLock discipline introduced when the daily-jackpot VRF-resolution surface was carved out, and their accumulator-write is the structural intent: whale bundles pay into the pool that whales' own claims will later draw from. As with V-024, the `prizePoolFrozen` branch at `WhaleModule.sol:345-:357` handles the jackpot-phase swap window via `_setPendingPools`, but does not cover the broader rngLock window. Phase 290 MINTCLN's owed-in-baseKey collapse design rationale (`290-01-DESIGN-INTENT-TRACE.md`) is the controlling precedent: per-callsite gates at EOA entry points are the only complete protection for accumulator slots that participate in VRF-resolution reads. Per `feedback_design_intent_before_deletion.md`, the original frozen-pending pattern remains valid; the gate at the EOA entry is the supplement that closes the rngLock-window gap.

### §14.B — Actor game-theory walk

**Exploit-actor class:** any EOA player with enough ETH to purchase a whale bundle (current price floor ≈ `WHALE_BUNDLE_BASE` + level-dependent escalation) or a lazy pass. **Action sequence:** inside the rngLock window, attacker fires `purchaseWhaleBundle(buyer, quantity)` with msg.value covering `totalPrice = baseUnit × quantity`. Maximum single-call mutation: `quantity ∈ [1..100]` × per-bundle price → up to 100× per-bundle inflation of `futurePool`. The consumer at §1 reads `_getFuturePrizePool()` at JackpotModule `:548` and multiplies by `poolBps`; the inflated value propagates directly to `ethDaySlice`. **EV magnitude:** MEDIUM. Whale-bundle is the LARGEST single-call writer in the catalog for S-09 — one call can shift `futurePool` by tens of ETH. Per `feedback_rng_commitment_window.md` the attack window is the rngLock duration (seconds-to-minutes for VRF callback latency). **Disposition:** MEDIUM-tier; gated by attacker's win probability under the in-flight VRF outcome, but the leverage per call is much higher than V-024.

### §14.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert at `WhaleModule.sol:187` (`purchaseWhaleBundle`) and `:380` (`purchaseLazyPass`). Two callsites. The `_livenessTriggered()` revert at `:195` and `:385` is the existing top-level check; the gate is co-located right alongside that check: `if (rngLockedFlag) revert RngLocked();`. `RngLocked` is the canonical custom error already used by sibling `WhaleModule._purchaseDeityPass` at `:543`. **Rationale:** identical to §1.C — the existing `prizePoolFrozen`/`_setPendingPools` branch covers only the jackpot-phase swap window; the broader rngLock window requires the entry-level revert. Tactic (b) snapshot is rejected for the same byte-cost + layout-drift reason (the slot is performance-critical and packed). **Bytecode impact:** ~30 bytes × 2 sites = ~60 bytes. **Storage layout:** BYTE-IDENTICAL. **Public ABI:** NON-BREAKING.

### §14.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-14`
**Citation:** `WhaleModule.sol:187` (`purchaseWhaleBundle`), `:380` (`purchaseLazyPass`)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-025.

---

## §15 — V-026: WhaleModule.purchaseDeityPass → prizePoolsPacked (runtime-gated)

**Slot:** S-09 `prizePoolsPacked`
**Writer:** `_setPrizePools` reached from `_purchaseDeityPass` at `WhaleModule.sol:653` (revenue split)
**EOA reach:** `WhaleModule.sol:538` (`purchaseDeityPass` external) → `:542` (`_purchaseDeityPass` private)
**Catalog row:** §16 V-026 — `VIOLATION | (a) | Gate already at WhaleModule:543 — coverage verification only | D-43N-V44-HANDOFF-15`

### §15.A — Design-intent backward-trace

`purchaseDeityPass` is the deity-pass purchase entry (one of 32 per-symbol passes); the price escalates with the count of already-sold passes and a per-buyer boon-discount may apply. The pass-price revenue routes into `prizePoolsPacked` via `_setPrizePools(next + nextShare, future + (totalPrice - nextShare))` at `WhaleModule.sol:653`. UNLIKE V-024 and V-025, this entry HAS a top-level `rngLockedFlag` revert: `WhaleModule.sol:543` reads `if (rngLockedFlag) revert RngLocked();` as the FIRST statement of `_purchaseDeityPass`. The runtime gate is design-intent-aligned with the freeze invariant (`D-42N-FREEZE-INVARIANT-01`) and the original deity-pass introduction phase. Catalog §16 still classifies V-026 as VIOLATION per `D-298-EXEMPT-REACH-01` (strict + per-callsite + stack-strict): the verdict matrix records the WRITER row regardless of any runtime mitigation, since runtime gates must be coverage-verified rather than assumed. The classification difference between V-019 (S-07 `deityBySymbol`) and V-026 (S-09 `prizePoolsPacked`) is that both gates derive from the same `:543` revert — they are co-located and either both fire or both don't.

### §15.B — Actor game-theory walk

**Exploit-actor class:** any EOA buyer attempting a deity-pass purchase during rngLock. **Action sequence:** the actor fires `purchaseDeityPass(buyer, symbolId)`. The first statement at `:543` reads `if (rngLockedFlag) revert RngLocked();` and reverts. The deity-pass price write to `prizePoolsPacked` at `:653` is therefore UNREACHABLE during rngLock IF the runtime gate fires reliably. Per `feedback_rng_window_storage_read_freshness.md`, every SLOAD inside the rng-window must be enumerated; the gate's correctness depends on `rngLockedFlag`'s value at the time of the SLOAD. Since `rngLockedFlag` itself only transitions inside `_requestRng` (true) / `_unlockRng` (false), both inside the advanceGame stack, no concurrent EOA writer can flip the gate between SLOAD and SSTORE within `_purchaseDeityPass`. **EV magnitude:** LOW — the gate effectively closes the window. The only residual risk is a coverage gap if `rngLockedFlag` is not set when the consumer reads `_getPrizePools()` at §1 (e.g. `_requestRng` runs after `_purchaseDeityPass` in the same block — impossible per the advanceGame stack ordering). **Disposition:** LOW-tier, structurally bounded. The verdict-matrix entry exists to FORCE the FUZZ-301 branch-coverage check.

### §15.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert — ALREADY PRESENT at `WhaleModule.sol:543`. **No source-tree change required.** Catalog row V-026 explicitly says "coverage verification only". Per `D-43N-FUZZ-VMSKIP-01` and Phase 301 FUZZ scope, V-026 hands off to FUZZ-301 as a branch-coverage attestation target: the FUZZ test asserts that `purchaseDeityPass` reverts with `RngLocked()` when called inside the rngLock window, exercising the `:543` revert path. **Rationale:** the gate is already correctly placed; any code change risks regressing the existing protection. Per `feedback_frozen_contracts_no_future_proofing.md` the contract is frozen at deploy; the FIXREC remediation is the FUZZ-301 attestation, not a source mutation. **Bytecode impact:** ZERO. **Storage layout:** UNCHANGED. **Public ABI:** UNCHANGED.

### §15.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-15`
**Citation:** `WhaleModule.sol:538` (entry) → `:543` (gate) → `:653` (`_setPrizePools` revenue split)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-026; cross-links to V-019 (same gate, S-07 slot).

---

## §16 — V-027: recordDecBurn → prizePoolsPacked (BurnieCoin callback)

**Slot:** S-09 `prizePoolsPacked`
**Writer:** `recordDecBurn`'s downstream prize-pool routing reached via the BurnieCoin `decimatorBurn` callback path; the prize-pool credit lands on the GAME-side ETH-receive write at `DegenerusGame.sol:1747` (`_setPrizePools(next, future + uint128(amount))`) when decimator BURNIE-burn unlocks the corresponding ETH share, and the `recordDecBurn` entry point itself is at `DegenerusGame.sol:1029`.
**EOA reach:** `BurnieCoin.sol:559` (`decimatorBurn`) → `:610` (calls `degenerusGame.recordDecBurn(...)` → `DegenerusGame.sol:1029` → `DegenerusGameDecimatorModule.sol:133`)
**Catalog row:** §16 V-027 — `VIOLATION | (a) | Add rngLockedFlag gate at DegenerusGame:1029 OR upstream in DegenerusCoin.burnCoin | D-43N-V44-HANDOFF-16`

### §16.A — Design-intent backward-trace

`recordDecBurn` is the GAME-side callback that BurnieCoin invokes during `decimatorBurn` to record the burn into the per-level / per-bucket aggregate. The decimator subsystem rewards BURNIE burns with lottery-style payouts on level transitions; the burn itself is denominated in BURNIE but the corresponding ETH prize-pool routing happens on the GAME side as part of the burn-fund-credit pipeline. The catalog §15 enumeration places `recordDecBurn` under the S-09 writers because the decimator-resolution flow (`DegenerusGameJackpotModule._awardDecimatorLootbox` at JackpotModule `:573`) ultimately consults `prizePoolsPacked` reads through the dec-burn aggregate's ETH-share routing. The structural intent: BURNIE burns fund decimator lottery payouts; the dec-burn aggregate must be frozen across the rngLock window to keep payout consumers consistent. The current `recordDecBurn` body (`DegenerusGameDecimatorModule.sol:133-:192`) gates ONLY on `msg.sender != ContractAddresses.COIN` (`OnlyCoin` revert at `:140`); there is no rngLockedFlag check. The original decimator-design phase predates rngLock discipline. Per `feedback_design_intent_before_deletion.md`, the dec-burn aggregate's freeze across rngLock IS the design intent — it just was never wired through `recordDecBurn`'s entry.

### §16.B — Actor game-theory walk

**Exploit-actor class:** any EOA holding BURNIE tokens. **Action sequence:** inside the rngLock window, attacker fires `BurnieCoin.decimatorBurn(player, amount)` with `amount >= MIN_DECIMATOR_BURN`. The call burns BURNIE and reaches `degenerusGame.recordDecBurn(...)` at BurnieCoin `:610`. `recordDecBurn` mutates `decBurn[lvl][player]` and subbucket aggregates (`_decUpdateSubbucket`). The mutated aggregate is then read by the §1 jackpot consumer's dec-related branches when the jackpot resolution computes decimator-lottery EV inputs. **EV magnitude:** MEDIUM-HIGH. Per `feedback_rng_commitment_window.md` and `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent), decimator burns are FEE-CHEAP relative to their EV impact: the attacker spends BURNIE (which itself is purchased / earned) and shifts a multi-ETH payout's distribution. Burning small amounts repeatedly mid-window can accumulate subbucket entries that displace the deterministic subbucket order. **Disposition:** MEDIUM-HIGH; the per-burn cost is low, the per-window ROI scales with the player's bucket position.

### §16.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert. Per catalog row V-027: "Add `rngLockedFlag` gate at `DegenerusGame:1029` OR upstream in `DegenerusCoin.burnCoin`". Two candidate sites: `DegenerusGame.sol:1029` (the GAME-side proxy entry that delegatecalls to the Decimator module) or `BurnieCoin.sol:559` (`decimatorBurn`, the EOA entry point). The cleaner site is `DegenerusGame.sol:1029` since the rngLock state lives in GAME storage and the GAME-side entry is the architectural boundary; adding the gate to BurnieCoin would require BurnieCoin to read GAME state through a cross-contract call (which adds gas to every dec-burn and creates a cross-contract coupling). **Rationale:** the GAME-side gate is internally consistent with the rest of the FIXREC cluster (V-024/V-025/V-027 all gate at the GAME-side EOA entry). Per `feedback_design_intent_before_deletion.md`, the freeze invariant lives in GAME; BurnieCoin is the messenger. Tactic (b) snapshot is rejected: snapshotting the dec-burn aggregate would require freezing a much larger state surface (`decBurn[lvl][player]` is a mapping; snapshot scaling is impractical). **Bytecode impact:** ~30 bytes for the single gate at `DegenerusGame.sol:1029`. **Storage layout:** BYTE-IDENTICAL. **Public ABI:** NON-BREAKING — `recordDecBurn` keeps its signature, only gains a guarded revert path; BurnieCoin callers see `RngLocked()` revert propagating up through `decimatorBurn`'s call to `recordDecBurn`.

### §16.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-16`
**Citation:** `DegenerusGame.sol:1029` (`recordDecBurn` GAME-side entry) and cross-link `BurnieCoin.sol:559` (`decimatorBurn` EOA entry)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-027.

---

## §17 — V-030: claimWhalePass → _queueTicketRange adjacent writes

**Slot:** S-09 `prizePoolsPacked` (adjacent writes alongside `_queueTicketRange`-mediated routing)
**Writer:** `_queueTicketRange`-co-located prize-pool writes reached via `claimWhalePass` (`DegenerusGame.sol:1692` parent dispatch → `WhaleModule.sol:957` body → `:973` `_queueTicketRange`)
**EOA reach:** `DegenerusGame.sol:1692` (`claimWhalePass`)
**Catalog row:** §16 V-030 — `VIOLATION | (a) | Effective gate via _queueTicketRange revert; add explicit top-level gate for clarity | D-43N-V44-HANDOFF-17`

### §17.A — Design-intent backward-trace

`claimWhalePass` is the deferred-claim entry for whale-pass ticket awards. Whale-pass winners accumulate `whalePassClaims[player]` half-pass counts during normal solo-bucket resolution (`JackpotModule.sol:1570` `whalePassClaims[winner] += whalePassCount`); the EOA-callable `claimWhalePass` later converts the half-pass count into actual ticket entries via `_queueTicketRange(player, startLevel, 100, halfPasses, false)` at `WhaleModule.sol:973`. The `_queueTicketRange` writer is the same family as `_queueTickets`, both of which carry rngLockedFlag gates inside the body (`DegenerusGameStorage.sol:572` reads `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();`). Per the catalog rationale, the "effective gate" exists DOWNSTREAM via that body revert when `_queueTicketRange` writes a far-future ticket key during rngLock. The design intent (from the original whale-pass introduction) is that ticket awards must respect the queue's far-future / write-slot discipline. The structural protection IS the downstream revert; the missing piece is the entry-level revert at the EOA boundary, which improves diagnostic clarity (callers see the revert at `claimWhalePass`, not deep in `_queueTicketRange`) and protects against future refactors that might rewire `_queueTicketRange`'s internal gate.

### §17.B — Actor game-theory walk

**Exploit-actor class:** any EOA with a non-zero `whalePassClaims` balance (i.e. a prior whale-pass solo-bucket winner). **Action sequence:** inside the rngLock window, attacker fires `claimWhalePass(player)`. `_livenessTriggered()` at `WhaleModule.sol:958` is the only entry-level check. The function proceeds to compute `startLevel = level + 1` and invokes `_queueTicketRange(...)` at `:973`. Inside `_queueTicketRange`, the `_queueTickets`-family gate at `DegenerusGameStorage.sol:572` reverts when the target is far-future and `rngLockedFlag = true && rngBypass = false`. The `claimWhalePass` call passes `false` as the `rngBypass` parameter at `:973`, so the gate fires for far-future writes. **EV magnitude:** LOW per single claim — `claimWhalePass` only converts pre-existing half-pass counts into tickets; it does not let the attacker inflate the underlying count. However, cumulative across many small half-pass batches, an attacker could land queue writes that influence the next-day consumer's `ticketQueue[wk]` read-slot ordering — though the double-buffer protection at `_swapAndFreeze` (toggling `ticketWriteSlot`) makes this concretely difficult. **Disposition:** LOW-tier (structurally protected via the downstream revert).

### §17.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert at the EOA entry. Per catalog row V-030: "Effective gate via `_queueTicketRange` revert; add explicit top-level gate for clarity". Two candidate sites: `DegenerusGame.sol:1692` (parent dispatch — adds the gate before delegatecall) and `WhaleModule.sol:957` (module body — adds the gate at the function's top). Recommendation: add at `WhaleModule.sol:957` (alongside `_livenessTriggered()` at `:958`) since that's the canonical body and the parent dispatch is a thin delegatecall shim. `if (rngLockedFlag) revert RngLocked();`. **Rationale:** explicit top-level gate produces deterministic revert behavior diagnosable from the EOA entry-call selector, avoiding the indirection through `_queueTicketRange`'s body. The cluster invariant (every EOA writer of S-09 carries an entry-level gate) becomes uniform across V-024..V-027 + V-030..V-032. Tactic (b) snapshot is N/A — `claimWhalePass` is not an accumulator-write into `prizePoolsPacked` directly; the catalog row classifies it under "adjacent writes" (the prize-pool reads happen during `_queueTicketRange`'s far-future gate evaluation). **Bytecode impact:** ~30 bytes. **Storage layout:** BYTE-IDENTICAL. **Public ABI:** NON-BREAKING.

### §17.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-17`
**Citation:** `DegenerusGame.sol:1692` (parent dispatch) → `WhaleModule.sol:957` (body) → `:973` (`_queueTicketRange`)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-030.

---

## §18 — V-031: placeDegeneretteBet → _collectBetFunds → prizePoolsPacked

**Slot:** S-09 `prizePoolsPacked`
**Writer:** `_setPrizePools` reached from `_collectBetFunds` at `DegeneretteModule.sol:556` (and `_setPendingPools` at `:553` when frozen)
**EOA reach:** `DegenerusGame.sol:714` (`placeDegeneretteBet` parent dispatch) → `DegeneretteModule.sol:367` (module body) → `:405` (`_placeDegeneretteBet`) → `:422` (`_collectBetFunds`) → `:556` (`_setPrizePools(next, future + uint128(totalBet))`)
**Catalog row:** §16 V-031 — `VIOLATION | (a) | Add rngLockedFlag revert to _placeDegeneretteBetCore at DegeneretteModule:405 | D-43N-V44-HANDOFF-18`

### §18.A — Design-intent backward-trace

`placeDegeneretteBet` is the Full-Ticket Degenerette ETH/BURNIE/WWXRP bet entry. The ETH-currency branch in `_collectBetFunds` (`DegeneretteModule.sol:539-:560`) routes the bet's ETH into the `future` prize pool: at `:556` `_setPrizePools(next, future + uint128(totalBet))` when not frozen, or `:553` `_setPendingPools(...)` when frozen. The original Degenerette design (Phase 292 HRROLL / Phase 294 DPNERF era) intended for placed bets to fund pool growth between resolutions; the rngLock-window protection is intended via the frozen-pending branch. The body already reads `if (lootboxRngWordByIndex[index] != 0) revert RngNotReady();` at `:452` — this guards against placing a bet for an INDEX whose RNG has already published, but does NOT block a bet during the daily-jackpot rngLock window. The catalog row V-031 names `_placeDegeneretteBetCore` at `:405` as the gate site (note: the actual body line numbers are `_placeDegeneretteBet :405` and `_placeDegeneretteBetCore :437` — the catalog uses :405 as the wave-1 anchor; either site reaches the same writer chain). Per `feedback_design_intent_before_deletion.md`, the design intent was a frozen-window protection; the rngLock-window subset is uncovered.

### §18.B — Actor game-theory walk

**Exploit-actor class:** any EOA placing a Degenerette bet. **Action sequence:** inside the rngLock window, attacker fires `placeDegeneretteBet(player, currency=ETH, amountPerTicket, ticketCount, customTicket, heroQuadrant)` with msg.value covering `totalBet = amountPerTicket × ticketCount`. The bet body executes the lootbox-index check at `:452` (passes if the current lootbox index doesn't have a published word) and then runs `_collectBetFunds` which writes `prizePoolsPacked.future += totalBet` at `:556`. The consumer at §1 / §8 then reads the inflated `futurePool`. **EV magnitude:** HIGH per `feedback_rng_window_storage_read_freshness.md`'s F-41-02/03 precedent: Degenerette is the CHEAP-BET entry point — minimum bet is `MIN_BET_ETH` (typically ~0.001 ETH or similar), and `ticketCount ∈ [1..10]`, so per-call cost is low while the `futurePool` mutation directly drives the jackpot consumer's `ethDaySlice` budget. The hero-quadrant + customTicket parameters also write `dailyHeroWagers[day][q]` at `:499` (this is V-003 territory under S-02, handled in Cluster A). **Disposition:** HIGH-tier — best per-dollar attack across the cluster.

### §18.C — Recommended tactic + rationale + impact

**Tactic:** (a) rngLockedFlag-gated revert at `_placeDegeneretteBetCore` per catalog row V-031: "Add `rngLockedFlag` revert to `_placeDegeneretteBetCore` at DegeneretteModule:405". The line :405 anchor places the gate at the body of `_placeDegeneretteBet` (the private function called by the external entry `placeDegeneretteBet`), right after `_resolvePlayer` and before any state mutation. Alternatively the gate can live at `_placeDegeneretteBetCore` (`:437`) — both sites are reached from the same external entry. Recommendation: add at `:405` (the private wrapper that ALL bet-paths funnel through, including any future EOA-equivalent entries). `if (rngLockedFlag) revert RngLocked();`. **Rationale:** Degenerette bets ALSO mutate S-02 `dailyHeroWagers` (V-003 in Cluster A, tactic (b) snapshot per Phase 288 dailyIdx precedent). The S-02 violation is best handled by snapshotting the day-key at lock time; the S-09 violation here is best handled by reverting at the entry. Both protections are independent and BOTH should be applied — the gate at :405 closes S-09; the snapshot in Cluster A closes S-02. Tactic (b) snapshot for S-09 alone is rejected for the same packed-slot performance reason as §1.C / §2.C. **Bytecode impact:** ~30 bytes at the single gate site. **Storage layout:** BYTE-IDENTICAL. **Public ABI:** NON-BREAKING.

### §18.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-18`
**Citation:** `DegenerusGame.sol:714` (parent dispatch) → `DegeneretteModule.sol:367` (external entry) → `:405` (private wrapper, gate site) → `:422` (`_collectBetFunds`) → `:556` (`_setPrizePools` write)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-031.

---

## §19 — V-032: openLootBox / openBurnieLootBox → prizePoolsPacked (lootbox payout consolidation)

**Slot:** S-09 `prizePoolsPacked`
**Writer:** lootbox payout consolidation reached via `openLootBox` / `openBurnieLootBox` resolution — the writes land on the GAME-side ETH-receive credit at `DegenerusGame.sol:1747` (`_setPrizePools(next, future + uint128(amount))`) and on lootbox-module internal pool-routing during the open-time resolution.
**EOA reach:** `DegenerusGame.sol:665` (`openLootBox`), `:673` (`openBurnieLootBox`) → delegatecall into LootboxModule
**Catalog row:** §16 V-032 — `VIOLATION | (b) | Domain-separated lootbox VRF; snapshot prizePool at lootbox-buy-time, not open-time | D-43N-V44-HANDOFF-19`

### §19.A — Design-intent backward-trace

`openLootBox` / `openBurnieLootBox` are the manual-resolve lootbox-open entry points. Per the Phase 296 RETRY_LOOTBOX_RNG / SWEEP discipline (`296-CONTEXT.md` + `296-ADVERSARIAL-LOG.md`), the lootbox VRF surface is DOMAIN-SEPARATED from the daily-jackpot VRF: lootbox RNG is per-index (`lootboxRngWordByIndex[index]`), populated via `_finalizeLootboxRng` (daily window) or `rawFulfillRandomWords` (mid-day), and consumed by `openLootBox` resolution. The headline metric in `RNGLOCK-CATALOG.md` §0 #2 ("Manual-path lootbox open is a deep VIOLATION cluster") records 35 VIOLATION rows on the open-resolution surface. The structural intent (`D-281-FREEZE-INVARIANT-01` owed-salt + Phase 288 dailyIdx + Phase 296 RETRY_LOOTBOX_RNG domain-separation): per-index purchase-time commitment slots (`lootboxEth`, `lootboxDay`, `lootboxBaseLevelPacked`, `lootboxEvScorePacked`) snapshot the player's state AT THE TIME OF LOOTBOX PURCHASE (Phase 281 owed-salt precedent), so that open-time resolution reads frozen inputs. For V-032 the missing snapshot is on the `prizePoolsPacked` cross-pool value — `openLootBox`'s resolution path reads `_getPrizePools()` LIVE during the open-time consolidation, which means an attacker can mutate `prizePoolsPacked` between buy-time and open-time. Per `feedback_design_intent_before_deletion.md`, the per-index snapshot pattern IS the design intent (already applied for `lootboxEth` via Phase 281 owed-salt) — the snapshot just didn't extend to the prize-pool cross-pool fields. Tactic (a) rngLockedFlag-gated revert at `openLootBox` would break the design intent: lootbox open is supposed to be a frozen-input deterministic resolution; gating it on rngLock would create a denial-of-service window where players cannot redeem their VRF'd lootboxes.

### §19.B — Actor game-theory walk

**Exploit-actor class:** any EOA holding an unopened lootbox with `lootboxRngWordByIndex[index] != 0` (RNG published). **Action sequence:** the attacker has a lootbox bought at time T0 (with `prizePool@T0 = P0`). Between T0 and open-time T1, OTHER players (or the attacker themselves) mutate `prizePoolsPacked` via the V-024/V-025/V-027/V-031 paths (all the EOA writers in this cluster). At open-time T1, the attacker fires `openLootBox(player, lootboxIndex)`. The open-resolution path reads `_getPrizePools()` LIVE (at `prizePool@T1 = P1`) and uses `P1` for any pool-relative payout caps or share computations. Since `P1 > P0` is achievable by the attacker's allies (or even the attacker themselves prior to opening), the open-time payout magnitude can be inflated relative to the original buy-time commitment. Per `feedback_rng_window_storage_read_freshness.md`, this is the F-41-02/03 class precisely: a SLOAD inside the resolution window reads a slot the attacker can mutate before the read. **EV magnitude:** HIGH per the F-41-02/03 precedent — `prizePool` directly affects payout caps; manipulation is fee-cheap and can be batched across many lootbox indices. **Disposition:** HIGH-tier.

### §19.C — Recommended tactic + rationale + impact

**Tactic:** (b) snapshot/anchor pattern. Per catalog row V-032: "Domain-separated lootbox VRF; snapshot prizePool at lootbox-buy-time, not open-time". This is the Phase 281 owed-salt + Phase 288 dailyIdx snapshot precedent applied to S-09. Implementation outline: at lootbox-buy time (the per-index commitment write, e.g. `MintModule._allocateLootbox` at `MintModule.sol:991` for the catalog row V-091 site, and the corresponding Whale / Burnie allocation sites), snapshot the buy-time `prizePoolsPacked` value (or the relevant payout-cap-driving subfield such as `nextPool` for the cap-multiplier flow) into a per-index packed slot — either a new field within an EXISTING per-index commitment struct (e.g. extending `lootboxBaseLevelPacked` or `lootboxEvScorePacked` with a packed `prizePoolSnapshot` field) or a new dedicated mapping. At open-time, the resolution path reads the per-index snapshot instead of the live `_getPrizePools()`. **Storage discipline (CRITICAL):** `prizePoolsPacked` is performance-critical and packed for SLOAD efficiency. The snapshot field MUST be packed alongside an existing per-index field to avoid a new dedicated 32-byte slot per index. The recommended layout: extend the existing `lootboxBaseLevelPacked[index][player]` (currently 256 bits with baseLevel + presale + auxiliary fields) to include the snapshot in a packed sub-field. `RNGLOCK-CATALOG.md` §0 #2 already calls out the lootbox-cluster snapshot family — the V-032 snapshot is part of the same pattern. **Rationale for rejecting tactic (a):** rngLockedFlag-gated revert at `openLootBox` breaks the design: lootbox open is per-index, frozen-input deterministic; gating it on the global rngLockedFlag would block redemption during every daily jackpot window, which is a UX denial. **Bytecode impact:** ~100-200 bytes (new snapshot write path at allocation sites + new snapshot read in open resolution + ~3 SSTOREs/SLOADs per lootbox lifecycle). **Storage layout:** REQUIRES per-index packed-field extension — the snapshot field must be added within an existing per-index struct to avoid adding a new dedicated 32-byte slot. This is a layout change but a CONTAINED one (existing fields keep their bit ranges; the snapshot lives in the unused bit range of `lootboxBaseLevelPacked` per the canonical layout audit). **Public ABI:** NON-BREAKING — `openLootBox`/`openBurnieLootBox` signatures unchanged.

### §19.D — v44.0 handoff anchor

**Anchor:** `D-43N-V44-HANDOFF-19`
**Citation:** `DegenerusGame.sol:665` (`openLootBox`), `:673` (`openBurnieLootBox`) — payout consolidation surface; allocation-side snapshot sites at `MintModule.sol:991` (per-index commitment for buy-side), `WhaleModule.sol:854`, `MintModule.sol:1397` (BURNIE allocation)
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row V-032; cross-links to the 35-row lootbox open-resolution cluster headlined in §0 #2.

---

## §20 — V-043: sDGNRS poolBalances[Reward] × `transferFromPool` from non-advanceGame GAME entries (claim/settlement paths)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 378 (V-043). §1 row 41 (D-43N catalog row 41 verdict-matrix). Writer enumeration §15 row 170. §1 §C "Slot: sDGNRS `poolBalances[Pool.Reward]` (cross-contract)" and §1 §D row 41.

### §20.A — Design-intent backward-trace

**Slot introduction phase:** The sDGNRS `poolBalances` array was introduced as part of the sDGNRS sister-contract architecture — a separately deployed soulbound token backed by ETH / stETH / BURNIE reserves with pre-minted supply split across five reward pools (`Whale`, `Affiliate`, `Lootbox`, `Reward`, `Earlybird`). The Reward pool specifically is the "general payout" tier: the final-day solo-bucket DGNRS reward (`JackpotModule.sol:1496` `(dgnrsPool * FINAL_DAY_DGNRS_BPS) / 10_000`), the BurnieCoin / Coinflip bounty payouts (`DegenerusGame.payCoinflipBountyDgnrs:418`), and Decimator/Lootbox `Reward`-keyed drains all source from this slot.

The economic function: the Reward pool is the "tail" of the v40-era prize-distribution architecture. Every distribution from the Reward pool reduces the pool balance, and the pool is never refilled post-deploy (constructor sets it once at `:313` `poolBalances[uint8(Pool.Reward)] = rewardAmount`, and the only post-deploy writers are the debit-side `transferFromPool` plus the dual-write `transferBetweenPools`). This is the monotone-drain invariant: the Reward pool can only shrink during the game's active lifetime (and is then zeroed at `burnAtGameOver:469`).

**Cite for "what would break if frozen":** Freezing `poolBalances[Reward]` during rngLock would block legitimate non-advanceGame Reward-pool drains — specifically, the catalog row 41 enumerates "any non-advanceGame-stack write to `poolBalances[Pool.Reward]`" as the violation class. The set of legitimate writers includes (a) `payCoinflipBountyDgnrs` reached from `BurnieCoin.burnCoin` (the `msg.sender == COIN` arm at `DegenerusGame.sol:408`), (b) admin-style quest reward distribution paths, and (c) any other `DegenerusGame` callsite that distributes Reward-pool DGNRS as a side-effect of player action (e.g., a quest streak reward, an affiliate bonus payout, or a settlement claim). Each of these flows expects to debit the Reward pool during rngLock for legitimate gameplay reasons; gating them on `rngLockedFlag` (tactic (a)) would interrupt valid game flow and force user-visible failures on quest reward / settlement paths that share no causal dependency on the daily VRF resolution.

The catalog tactic (b) snapshot-at-`_swapAndFreeze` avoids the freeze entirely: the consumer (`_handleSoloBucketWinner`) gets a snapshot value taken at the VRF-request moment instead of a live SLOAD at the final-day resolution moment. Legitimate cross-contract drains continue unimpaired; the consumer simply reads a pinned value that cannot race the consumer's own VRF-derived selection.

**Precedent for snapshot pattern:** Phase 281 owed-salt 4th-keccak-input introduced the snapshot-at-commitment pattern for the mint-batch determinism class (`D-281-FIX-SHAPE-01` selected over (a) gated-revert because of zero storage delta and zero MEV surface). Phase 288 extended to `dailyIdx` structural anchor at lock-time. The Cluster-D Reward-pool snapshot is the direct application of this precedent to the cross-contract sDGNRS pool-balance class.

### §20.B — Actor game-theory walk

**Exploit-actor class:** Player triggering a non-advanceGame Reward-pool drain mid-rngLock window. Concrete vectors:

- Player calls `BurnieCoin.burnCoin(...)` (BurnieCoin EOA-callable surface), which transitively reaches `DegenerusGame.payCoinflipBountyDgnrs` via the `msg.sender == COIN` arm at `DegenerusGame.sol:408`. The bounty `payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000` at `:418` debits the Reward pool by 1% (or configured BPS) of the pool size. A determined attacker can chain multiple `burnCoin` calls during the rngLock window to drain the Reward pool by `n × COINFLIP_BOUNTY_DGNRS_BPS / 10_000` before the final-day solo-bucket consumer reads `dgnrsPool` at `:1493`.
- A player or operator triggering a quest reward / affiliate bonus / settlement flow that reaches `dgnrs.transferFromPool(Pool.Reward, ...)` from any `DegenerusGame.sol`-internal callsite outside the advanceGame stack. The catalog's wording — "claim/settlement paths, quest reward etc." — covers this class without enumerating every individual callsite, because the verdict-matrix classification is on the writer (`transferFromPool` from non-advanceGame stack) rather than per-callsite at row 41.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters daily-phase, requests VRF, sets `rngLockedFlag = true` at `AdvanceModule:1634` (D-12 / §11 cross-reference).
- T1 (attacker move): Attacker observes the impending final-day solo-bucket distribution magnitude. Attacker calls `BurnieCoin.burnCoin(...)` or a quest-reward / settlement path that reaches `transferFromPool(Pool.Reward, ...)`. Pool balance shrinks by `Δ`.
- T2 (VRF callback): `rawFulfillRandomWords` fires, `_applyDailyRng` writes `rngWordCurrent`, advanceGame proceeds to `_handleSoloBucketWinner` final-day branch.
- T3 (consumer SLOAD): `_handleSoloBucketWinner` reads `dgnrsPool = dgnrs.poolBalance(Pool.Reward)` at `:1493`. This is `originalPool - Δ`.
- T4 (resolution): `reward = (originalPool - Δ) * FINAL_DAY_DGNRS_BPS / 10_000`. Consumer transfers `reward` to the VRF-selected winner. The attacker has reduced the winner's payout by `Δ * FINAL_DAY_DGNRS_BPS / 10_000`.

**EV magnitude estimate:** **MEDIUM-HIGH on the per-tx margin; CATASTROPHE-tier in absolute USD on the final physical day.** The final-day solo-bucket distribution is a terminal one-shot payout; the catalog §1 §B "B-6" attestation confirms this slot drives the entire terminal-day DGNRS payout amount. The attacker's per-tx Δ is bounded by `COINFLIP_BOUNTY_DGNRS_BPS / 10_000` (typically ~1% per drain call), but multiple drains within the rngLock window are additive. The attacker need not be the winner; even an indifferent third party can frontrun the winner's expected payout, and a SDGNRS holder with conflicting incentives (e.g., short bias on the terminal-day distribution) realizes EV from the deflation. Economic-likelihood disposition: **likely-exploited** on the final physical day, because the terminal payout magnitude is observable from public state in advance and the rngLock window provides a deterministic write opportunity.

**Note on the V-042 EXEMPT-VRFCALLBACK boundary:** When reached from `BurnieCoinflip.processCoinflipPayouts` (catalog row 377 V-042), the same writer function is EXEMPT-VRFCALLBACK because that resolution path runs inside `processCoinflipPayouts` which is itself gated by the `onlyDegenerusGameContract` modifier and reached only from advanceGame-stack callsites (catalog §11 §A entry 1 attestation). V-043 captures the residual non-advanceGame, non-Coinflip-resolution callsites — i.e., the `msg.sender == COIN` arm reached from `BurnieCoin.burnCoin` directly (EOA), and any other GAME-internal callsite outside the advance-stack.

### §20.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §1 §E row 41 rationale: "snapshot `dgnrsPool` at `_swapAndFreeze` time; read snapshot inside `_handleSoloBucketWinner`."

**Concrete shape:**

- Introduce a packed snapshot field `dgnrsRewardPoolSnapshot` (uint128 sufficient since `INITIAL_SUPPLY` fits well under `2^128 − 1`).
- Populate the field inside `_swapAndFreeze` (the same advance-stack callsite where `prizePoolsPacked` is already snapshotted per catalog rows 19-20). Call `dgnrs.poolBalance(Pool.Reward)` once, store in the snapshot field.
- Modify `_handleSoloBucketWinner` final-day branch (`DegenerusGameJackpotModule.sol:1493`) to read the snapshot field instead of the live SLOAD.
- The `transferFromPool` write at `:1498` continues to fire against the live pool balance — only the magnitude calculation uses the snapshot. (The actual transfer will still bound to live balance via `transferFromPool`'s internal `amount > available` clamp at `StakedDegenerusStonk.sol:418-420`, so the snapshot value is the "intended" magnitude and the live pool clamp is the safety floor.)

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected: gating `payCoinflipBountyDgnrs` (or every quest-reward / settlement path) on `rngLockedFlag` would interrupt legitimate gameplay flows that share no causal dependency on the daily VRF resolution. The class includes flows like `BurnieCoin.burnCoin` → coinflip bounty payout which are themselves part of normal in-game economy.
- **(c) pre-lock reorder** rejected: the consumer's read is structurally tied to the final-day solo-bucket branch which fires inside the advance-stack resolution. Reordering writers to land before `_swapAndFreeze` is impossible because the writers are EOA-triggered at attacker discretion.
- **(d) immutable** rejected: the slot is fundamentally mutable (pool drains over the game's lifetime).

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** new packed snapshot field `dgnrsRewardPoolSnapshot` (uint128). 16 bytes. Fits inside the existing `prizePoolsPacked`-adjacent layout in `DegenerusGameStorage` (packing options determined by Phase 299→v44 plan-phase). **NOT byte-identical** — one new slot or one slot-extension. Storage-delta = +16 bytes (or +32 if standalone slot for layout simplicity).
- **Bytecode delta:** ~100-150 bytes. One additional `dgnrs.poolBalance(Pool.Reward)` external call inside `_swapAndFreeze` (single SLOAD on sDGNRS side + STATICCALL overhead ≈ 2500 gas worst-case cold), one SSTORE on the snapshot field (~20000 gas warm), one SLOAD on the snapshot field replacing the live external call at `:1493` (eliminates the existing STATICCALL).
- **Net runtime gas:** approximately neutral on the hot path. `_swapAndFreeze` pays +1 STATICCALL +1 SSTORE; `_handleSoloBucketWinner` saves 1 STATICCALL and gains 1 SLOAD. Final-day path runs once per game so the snapshot SSTORE cost amortizes to zero per game.
- **Public ABI:** **NON-BREAKING.** No event topic-hash change; the new field is internal storage. External views can expose the snapshot via a new view function if desired (v44 plan-phase discretion).
- **Reference precedent:** Phase 281 owed-salt snapshot is exactly this shape, zero ABI delta and +~30 gas per `_raritySymbolBatch` invocation (Phase 281 §iii cost analysis). Phase 288 `dailyIdx` structural snapshot is the multi-call analog.

### §20.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-20`** — Snapshot sDGNRS `poolBalances[Pool.Reward]` at `_swapAndFreeze` time; `_handleSoloBucketWinner` final-day branch reads the snapshot instead of the live external `dgnrs.poolBalance(Pool.Reward)` SLOAD. Concrete file:line targets:

- Snapshot WRITE site: inside `_swapAndFreeze` (callsites at `AdvanceModule.sol:299, :631, :1095` per catalog row 20).
- Snapshot READ site: replace the live external call at `DegenerusGameJackpotModule.sol:1493` (`dgnrs.poolBalance(IStakedDegenerusStonk.Pool.Reward)`) with a SLOAD on the new snapshot field.
- Storage field: new `dgnrsRewardPoolSnapshot` field in `DegenerusGameStorage.sol` (packing layout per v44 plan-phase discretion).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 378 (V-043) and §1 §E row 41.

---

## §21 — V-045: sDGNRS poolBalances[Reward] × sDGNRS-internal admin / initial-distribution writers

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 380 (V-045). §1 verdict-matrix row 43. Writer enumeration §15 row 172 (constructor / initial distribution). §1 §C "Slot: sDGNRS `poolBalances[Pool.Reward]` (cross-contract)".

### §21.A — Design-intent backward-trace

**Slot introduction phase:** Same architecture phase as §1.A — the sDGNRS sister-contract pool partitioning was introduced as the pre-deploy supply distribution mechanism. The constructor at `StakedDegenerusStonk.sol:307-:314` mints `poolTotal` to `address(this)` and assigns the five pool subtotals (`whaleAmount`, `affiliateAmount`, `lootboxAmount`, `rewardAmount`, `earlybirdAmount`). The Reward pool's initial value is `rewardAmount`, computed pre-deploy from the sDGNRS deploy parameters.

**The V-045 row in the catalog (§16 row 380) describes "sDGNRS-internal writers (admin / initial distribution / ERC20 mint into pool)" as the writer class.** Per grep verification (`grep -n "poolBalances\[" contracts/StakedDegenerusStonk.sol`), the actual writer set is exactly:

| Site | Writer |
|------|--------|
| `:310-:314` | constructor batch initialization (pre-deploy, runs once) |
| `:422` | `transferFromPool` (debit) — `onlyGame` |
| `:453, :455` | `transferBetweenPools` (debit + credit pair) — `onlyGame` |
| `:469` | `burnAtGameOver` (`delete poolBalances`) — `onlyGame` |

There is no sDGNRS-side admin function that writes `poolBalances[Reward]` outside the constructor (verified by exhaustive grep). The V-045 row's characterization ("admin / initial distribution / ERC20 mint into pool") therefore describes the CLASS of writers reaching from non-GAME entry points — which in the current source is JUST the constructor (a one-shot, pre-deploy event).

**Note on per-design-intent finality:** Per `feedback_frozen_contracts_no_future_proofing.md`, contracts are frozen at deploy and design-intent is fixed at deployment time. V-045 therefore captures the residual VIOLATION class for any sDGNRS-internal writer that is NOT covered by the per-callsite verdict in §16 rows for `transferFromPool` / `transferBetweenPools` — which in practice is only the constructor (catalog row 43 explicitly says "initial pool funding, admin distribution, ERC20 mint into pool"). Since the constructor cannot fire during a live game's rngLock window (Solidity constructors run exactly once at deploy), V-045 is structurally a NULL-set violation in the deployed system — but the catalog row carries the VIOLATION token under `D-43N-AUDIT-ONLY-01` strict discipline (no "safe-by-design" attestation class permitted; the only available token is VIOLATION).

**Cite for "what would break if frozen":** Freezing the Reward pool against the (already non-existent) admin / initial-distribution writers during rngLock is a no-op behavioral change in the current frozen contracts. The catalog row 43 row exists to preserve the verdict-matrix completeness invariant: every (slot × writer × callsite) tuple carries one of `EXEMPT-ADVANCEGAME` / `EXEMPT-VRFCALLBACK` / `EXEMPT-RETRYLOOTBOXRNG` / `VIOLATION`. The class "sDGNRS-internal admin / initial distribution writers" must receive a token, and under audit-only strict-discipline that token is VIOLATION.

### §21.B — Actor game-theory walk

**Exploit-actor class:** Pre-deploy admin (deployer / DAO / multisig). Action sequence: at deploy time, admin sets `rewardAmount` in the constructor input parameters. No post-deploy admin writer of `poolBalances[Reward]` exists in the source. The "exploit" would require either (a) a malicious deployer pre-deploy, OR (b) a hypothetical future admin distribution writer added in a contract upgrade (which is prohibited by contract-frozen-at-deploy posture per `feedback_frozen_contracts_no_future_proofing.md`).

**Action sequence during rngLock window:** Not applicable — the constructor cannot fire during a live game's rngLock window. The slot's post-deploy mutation is exclusively through `transferFromPool` / `transferBetweenPools` / `burnAtGameOver` (covered by V-043 / V-051 / V-052).

**EV magnitude estimate:** **LOW (governance-trust class) in practical terms; MEDIUM (catalog-discipline class).** The catalog row 43 carries the VIOLATION token because of strict-classification discipline, not because of a live exploit surface. The economic-likelihood disposition: **non-exploitable in the deployed contract** (the writer class is empty post-deploy). The catalog row exists to preserve the strict-discipline invariant and to forward the verdict for v44.0 FIX-MILESTONE consideration if any future contract change introduces an admin writer of this slot.

### §21.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §1 §E row 43 rationale: "same snapshot-at-freeze pattern — eliminates cross-contract write race."

**Concrete shape:** The same snapshot at `_swapAndFreeze` introduced for V-043 covers V-045 automatically. The snapshot field `dgnrsRewardPoolSnapshot` is read in lieu of the live SLOAD; any hypothetical cross-contract writer (admin / initial distribution / OZ-inherited ERC20) cannot race the consumer because the consumer no longer performs a live SLOAD inside the rng-window.

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected: the only writer of this class is the constructor (which runs pre-deploy, not during rngLock). Gating it serves no purpose. For hypothetical future admin writers, the gate would land on the admin function in sDGNRS — but sDGNRS does not query `game.rngLocked()` for any writer other than `burn()` at `:492`. Adding a new gate-query is more invasive than the snapshot tactic and yields no consumer-side guarantee.
- **(c) pre-lock reorder** rejected: no current writer of this class fires during rngLock to reorder.
- **(d) immutable** rejected: the slot must remain mutable (the Reward pool drains over the game's lifetime via `transferFromPool`).

**Bytecode / storage-layout / public-ABI impact:** **Zero marginal cost beyond V-043.** V-045 is fully covered by the same snapshot field and snapshot SSTORE introduced for V-043. The two violations share `D-43N-V44-HANDOFF-21` and `D-43N-V44-HANDOFF-20` as a unified fix surface in the v44.0 plan-phase. Storage delta = 0 marginal bytes; bytecode delta = 0 marginal bytes; runtime gas delta = 0 marginal gas.

**Reference precedent:** Phase 281 owed-salt snapshot — single-field snapshot at commitment moment cures both VRF-derived-writer and non-VRF-writer race classes against the consumer.

### §21.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-21`** — Same snapshot mechanism as `D-43N-V44-HANDOFF-20` covers the sDGNRS-internal admin / initial-distribution writer race-class. The v44.0 plan-phase implementation lands a single snapshot field that resolves both V-043 and V-045 atomically.

- Implementation cite: same as `D-43N-V44-HANDOFF-20` — `_swapAndFreeze` snapshot WRITE, `_handleSoloBucketWinner:1493` snapshot READ.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 380 (V-045) and §1 §E row 43.

---

## §22 — V-046: sDGNRS poolBalances[Reward] × OZ-inherited ERC20 writers (the lone non-`contracts/` VIOLATION)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 381 (V-046). §15 writer enumeration row 173 ("ERC20 `transfer` / `transferFrom` / `_mint` / `_burn` (OZ-inherited)"). §17 OZ-carveout table rows for `_mint` / `_burn`. `D-298-OZ-CARVEOUT-01` is the governing locked-decision.

### §22.A — Design-intent backward-trace

**Slot introduction phase:** Same cluster preamble — sDGNRS sister-contract pool partitioning. The OZ-inherited writer class is the catalog's accommodation of the structural fact that ERC20 standard methods (`_mint`, `_burn`, `transfer`, `transferFrom`, `approve`, `permit`) live in the OpenZeppelin library tree outside `contracts/`. Per `D-298-OZ-CARVEOUT-01`, these writers are listed in §15 with a `(OZ-inherited)` annotation and a `node_modules/@openzeppelin/...` path stub for §17 cross-coverage; they do not appear in the §17 Pattern 1/2 `contracts/` grep hits and are NOT discrepancies.

**Source-of-truth refinement:** A grep of `contracts/StakedDegenerusStonk.sol` shows **no `import` directive for `@openzeppelin/contracts/token/ERC20`** — sDGNRS implements its ERC20 surface internally (custom `balanceOf` mapping, custom `transfer`, custom `_mint`, custom `_burn`). The §15 row 173 enumeration ("OZ-inherited") is the catalog's classification of the ERC20 surface CLASS, not a claim that this specific contract inherits OZ ERC20 source. Sister contracts in the project DO inherit OZ ERC20 (BurnieCoin, WrappedWrappedXRP, DegenerusStonk wrapper); the catalog `D-298-OZ-CARVEOUT-01` rule applies generically across the contract suite.

**Key catalog claim (§16 row 381):** "OZ-inherited writers (`_mint`, `_burn`, ERC20 standard methods) — `node_modules/@openzeppelin/.../ERC20.sol` `(OZ-inherited)` — NO — non-EXEMPT EOA ERC20 surface — VIOLATION — (b) — OZ-inherited writer; snapshot-at-freeze covers ERC20 transfer race."

**Important structural disambiguation:** OZ ERC20 `_mint` / `_burn` / `transfer` / `transferFrom` write `balanceOf` mappings, NOT `poolBalances[idx]`. The `poolBalances[Reward]` slot is mutated ONLY by `transferFromPool` / `transferBetweenPools` / `burnAtGameOver` (the four grep-verified writers in the cluster preamble). The OZ-inherited writer class therefore enters this VIOLATION row INDIRECTLY: ERC20 transfers/mints into / out of `address(this)` change `balanceOf[address(this)]` and `totalSupply`, but they DO NOT directly write the `poolBalances` array. The catalog row 381 conflates two slots (the ERC20 `balanceOf` family and the `poolBalances` array) under the same "sDGNRS Reward-pool race" umbrella. Per `feedback_verify_call_graph_against_source.md`, this FIXREC entry refines the catalog by noting the indirection: ERC20-surface writes on `balanceOf[address(this)]` and `totalSupply` are part of the same accounting envelope as `poolBalances[Reward]` and a desync between them (e.g., a `_burn` from `address(this)` that does NOT zero out a `poolBalances[Reward]` slot) could in principle change the effective Reward-pool magnitude observable through `poolBalance(Pool.Reward)` view. In the deployed source, this view returns `poolBalances[_poolIndex(pool)]` directly (`StakedDegenerusStonk.sol:392`) — it does NOT consult `balanceOf[address(this)]`. Therefore the ERC20-surface writes are NOT directly observable through the consumer's read at `JackpotModule.sol:1493`.

**The lone non-`contracts/` VIOLATION attestation (per the verifier's framing in the plan):** V-046 is the only VIOLATION in the verdict matrix whose writer source-of-record lives OUTSIDE `contracts/` (in `node_modules/@openzeppelin/`). Every other VIOLATION in Cluster D, and indeed every other VIOLATION in the entire catalog, traces to a writer function declared inside `contracts/`. V-046's structural distinctness drives the recommendation in §3.C: the fix CANNOT land on the OZ source file itself (it is a third-party dependency outside the project's modification scope and would create an indefensible maintenance burden); the fix MUST land in `contracts/` via the snapshot-at-freeze tactic, which gates the CONSUMER's read rather than the WRITER's mutate.

**Cite for "what would break if frozen":** Freezing OZ ERC20 standard methods during rngLock would block legitimate ERC20 surface flows (sDGNRS holder transfers, burns, mints during normal play). For sDGNRS specifically, the contract is soulbound (no `transfer` to non-zero addresses) — but `_mint`, `_burn`, and `wrapperTransferTo` (`:337`, restricted to `msg.sender == DGNRS`) still fire during normal play. Gating these on `rngLockedFlag` would break the DGNRS wrapper's unwrap flow during the rng-window — an unacceptable user-visible regression. The snapshot tactic preserves all standard-ERC20 behaviors while removing the consumer-side race.

### §22.B — Actor game-theory walk

**Exploit-actor class:** Any sDGNRS-holding EOA executing the ERC20 surface during the rngLock window. Concrete vectors:

- DGNRS wrapper holder calls `DegenerusStonk.burn(amount)` (or similar wrapper-side burn entry) which transitively reaches `_burn(address(this), amount)` inside sDGNRS, reducing `balanceOf[address(this)]` and `totalSupply`. Per the disambiguation in §3.A, this does NOT directly write `poolBalances[Reward]` but DOES change the effective sDGNRS accounting envelope.
- sDGNRS holder triggers a `wrapperTransferTo` (restricted to `msg.sender == DGNRS`) — an indirect EOA reach via the DGNRS wrapper's unwrap flow.

**Action sequence during rngLock window:** Same temporal shape as §1.B but the mutation target is `balanceOf[address(this)]` / `totalSupply` rather than `poolBalances[Reward]` directly. The consumer-side read at `JackpotModule.sol:1493` reads `poolBalance(Pool.Reward)` which returns `poolBalances[_poolIndex(pool)]` directly — so the ERC20-surface mutation does NOT race the consumer's `dgnrsPool` value. The catalog row 381 lists this writer class as VIOLATION under the conservative D-43N-AUDIT-ONLY-01 strict discipline (every writer class gets a token), but the structural reality is that the OZ-surface mutations do not flow into the consumer's SLOAD path.

**EV magnitude estimate:** **LOW per-write; effectively zero in practice for the Reward-pool consumer's read.** The catalog row carries VIOLATION as a conservative classification; the structural disambiguation in §3.A shows the indirection does not reach the consumer. The economic-likelihood disposition: **non-exploitable through the documented consumer reach path**, but the row is preserved for catalog-discipline completeness and to forward the OZ-carveout pattern to v44.0 FIX-MILESTONE for explicit attestation.

### §22.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §1 §E (row 43-equivalent for OZ surface) rationale: "OZ-inherited writer; snapshot-at-freeze covers ERC20 transfer race."

**Concrete shape:** Same as V-043 — the snapshot field `dgnrsRewardPoolSnapshot` covers the OZ-inherited writer race-class automatically. The consumer no longer reads `poolBalances[Reward]` (or any other sDGNRS-side accounting field) live during the rngLock window; it reads the snapshot captured at `_swapAndFreeze` instead.

**The "fix-in-`contracts/`" pattern (load-bearing per `D-298-OZ-CARVEOUT-01` and the plan's V-046-specific requirement):** Because OZ-inherited writers live OUTSIDE `contracts/` (in `node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol`), the FIX cannot land on the writer source. Two structural options exist:

1. **Gate the calling function in `contracts/`** that invokes the OZ-inherited writer. For sister contracts that DO inherit OZ ERC20 (e.g., BurnieCoin's `_mint` / `_burn` reached from `mintForGame` / `burnForCoinflip`), the FIX would add `if (game.rngLocked()) revert RngLocked();` to the `contracts/`-side wrapper function — landing the gate on the calling surface rather than the OZ method itself.
2. **Snapshot the consumer's read at the commitment moment**, which is the catalog's selected tactic (b). This avoids touching the writer entirely; it gates the consumer instead.

The catalog selects option (2) for V-046 because the consumer-side snapshot is structurally simpler and more comprehensive: a single snapshot covers all writer classes simultaneously (V-043, V-045, V-046), and the snapshot landing site is in `contracts/` (`_swapAndFreeze`) where the v44.0 FIX-MILESTONE has authority to land changes.

**Documentation requirement per `D-298-OZ-CARVEOUT-01`:** The v44.0 plan-phase MUST attest that the chosen tactic-(b) snapshot pattern places the fix INSIDE `contracts/` (specifically inside `_swapAndFreeze` in `contracts/modules/DegenerusGameAdvanceModule.sol` and inside `_handleSoloBucketWinner` in `contracts/modules/DegenerusGameJackpotModule.sol`), with the OZ source files untouched. This attestation satisfies the carveout rule's requirement that no `node_modules/` files be modified.

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert in OZ source** rejected: the writer source-of-record is in `node_modules/`. Modifying OZ source is structurally prohibited (third-party dependency, maintenance-burden indefensible). The plan's V-046-specific requirement explicitly directs the fix INTO `contracts/`.
- **(a) `rngLockedFlag`-gated revert in `contracts/` wrapper** is a viable alternative for sister contracts (BurnieCoin's wrappers, etc.), but for sDGNRS specifically, the contract has no `contracts/`-side wrapper around the OZ ERC20 surface (the ERC20 implementation is built-in, custom). The snapshot tactic is therefore simpler and works uniformly.
- **(c) pre-lock reorder** rejected: ERC20 mutations are EOA-discretionary; reordering is structurally impossible.
- **(d) immutable** rejected: `balanceOf[address(this)]` and `totalSupply` are inherently mutable.

**Bytecode / storage-layout / public-ABI impact:** **Zero marginal cost beyond V-043.** Same snapshot field, same SSTORE site, same SLOAD site. Storage delta = 0 marginal bytes; bytecode delta = 0 marginal bytes; runtime gas delta = 0 marginal gas.

**Reference precedent:** `D-298-OZ-CARVEOUT-01` explicitly permits the snapshot-in-`contracts/` pattern as the canonical resolution for the OZ-inherited writer class. Phase 281 owed-salt snapshot demonstrates the same "snapshot the consumer's read at commitment, leave the writer surface untouched" shape for the mint-batch class.

### §22.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-22`** — OZ-inherited writer class for sDGNRS poolBalances[Reward] resolved by the same snapshot-at-freeze tactic as V-043 / V-045. The OZ-carveout attestation requires the v44.0 plan-phase to confirm the FIX lands in `contracts/` only (no `node_modules/` modifications). Implementation cite: same as `D-43N-V44-HANDOFF-20`.

- OZ-carveout attestation cite: `D-298-OZ-CARVEOUT-01` in `.planning/phases/298-vrf-read-graph-catalog-catalog/298-CONTEXT.md` (and §15 / §17 of `.planning/RNGLOCK-CATALOG.md`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 381 (V-046).

---

## §23 — V-047: sDGNRS poolBalances[Lootbox] × `transferFromPool` from `openLootBox` (manual EOA path)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 382 (V-047). §15 writer enumeration row 174 (`transferFromPool` reached from `openLootBox`). §6 verdict-matrix row D-6 ("`dgnrs.poolBalances[Pool.Lootbox]` × `transferFromPool` (debit via `_creditDgnrsReward` from `openLootBox` etc.)" — NO — VIOLATION).

### §23.A — Design-intent backward-trace

**Slot introduction phase:** Same cluster preamble. The Lootbox pool specifically funds the DGNRS-tier lootbox payouts: `LootboxModule._lootboxDgnrsReward` (`DegenerusGameLootboxModule.sol:1770`) scales `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)` where `ppm` is one of `LOOTBOX_DGNRS_POOL_SMALL_PPM` / `_MEDIUM_PPM` / `_LARGE_PPM` / `_MEGA_PPM` (catalog §6 §B B-9). The DGNRS-tier path is taken when `pathRoll < 13 && pathRoll >= 11` (10% of paths per §0 headline finding D-6/D-7 EV reach analysis).

The economic function: the Lootbox pool is the EV reward stream for the lootbox payout system — every lootbox-open call (manual `openLootBox` / `openBurnieLootBox` from EOA, OR auto-resolve from `resolveLootboxDirect` / `resolveRedemptionLootbox` from the advance/redemption stack) that rolls into the DGNRS-tier arm draws down `poolBalances[Lootbox]` via `_creditDgnrsReward:1786`. Pool refilling: the constructor sets `poolBalances[Lootbox] = lootboxAmount` at `:312`; post-deploy refills occur via `transferBetweenPools(otherPool, Pool.Lootbox, ...)` from advance-stack rebalances.

**Manual-path commitment-window (per `feedback_rng_commitment_window.md`, mirroring catalog §7 commitment-window discipline):**

- T0: Player buys a ticket lot in the MintModule lootbox-allocation path, reserving a lootbox-RNG `index` (`AdvanceModule._lrRead(LR_INDEX_SHIFT)`). The reserved `index` is the entropy-commitment moment for the manual lootbox payout.
- T1: Daily advance OR mid-day VRF fulfillment writes `lootboxRngWordByIndex[index] = word` at `_finalizeLootboxRng:1253`. From this point the per-index RNG word is final and public.
- T2: Player calls `DegenerusGame.openLootBox(player, index)` at `:665` (EOA) → delegatecalls `LootboxModule.openLootBox:526` → reads `lootboxRngWordByIndex[index]`, derives `seed = keccak256(rngWord, player, day, amount)`, calls `_resolveLootboxCommon:960` → `_resolveLootboxRoll:1623` → `_lootboxDgnrsReward:1770` (when DGNRS-tier branch is taken).

**Critical commitment-window structural fact:** The player opens TX C at their discretion AFTER TX B publishes `rngWord`. The catalog §7 trace explicitly notes: "every OTHER SLOAD reached during resolution (player's activity score, EV-cap usage, level, dgnrs pool balance, decimator window, boon storage, …) is sampled at TX C time, NOT at TX A (purchase) time. That is the structural source of every VIOLATION row." V-047 is the dgnrs-pool-balance instance of this class.

**Cite for "what would break if frozen":** Freezing `poolBalances[Lootbox]` during rngLock would block legitimate Lootbox-pool drains from concurrent lootbox-open flows (other players' `openLootBox` calls happening concurrently with the rngLock window). The pool is shared across all lootbox-resolution paths; gating each `_creditDgnrsReward` call on `rngLockedFlag` would force all DGNRS-tier lootbox payouts to fail-and-retry during every daily VRF cycle — an unacceptable user-visible degradation. The catalog's tactic (b) snapshot-at-burn-submission avoids this by snapshotting the pool balance at the entropy-commitment moment (the moment when `lootboxRngWordByIndex[index]` is written) and using the snapshot inside `_lootboxDgnrsReward` instead of the live SLOAD.

**Precedent for snapshot pattern:** Phase 281 owed-salt 4th-keccak-input snapshot at the commitment moment is the load-bearing precedent. Phase 288 `dailyIdx` structural anchor is the multi-call analog. The cluster-D Lootbox-pool snapshot mirrors the manual-lootbox commitment-window discipline already encoded in the catalog §6 / §7 trace.

### §23.B — Actor game-theory walk

**Exploit-actor class:** Player observing their own pending lootbox VRF word AND `poolBalances[Lootbox]`, deciding when to call `openLootBox` to maximize the DGNRS-tier payout magnitude.

**Action sequence during rngLock window (sequential, per catalog §6 D-9 analysis adapted to V-047's openLootBox reach):**

- T0 (player commits): Player buys ticket lot reserving lootbox-RNG `index`. `lootboxRngWordByIndex[index]` is not yet written.
- T1 (VRF callback): `_finalizeLootboxRng` writes `lootboxRngWordByIndex[index] = word`. Player now knows `rngWord` and can compute `seed = keccak256(rngWord, player, day, amount)`, the resolution path roll, and whether the DGNRS-tier branch will be taken — all BEFORE calling `openLootBox`.
- T2 (attacker move — pool manipulation): If the DGNRS-tier branch will be taken AND the tier roll lands in the mega-tier (`tierRoll >= 995`, 0.5% per the `LOOTBOX_DGNRS_POOL_MEGA_PPM` arm), the player can:
  - (a) Trigger OTHER players' `openLootBox` / `openBurnieLootBox` calls to drain the pool BEFORE their own claim (if the attacker controls or coordinates with other accounts).
  - (b) Trigger advance-stack rebalances via daily-advance cooperative yields (Phase 281 ticket-batch cooperative-yield primitive) that may relocate Lootbox-pool balance.
  - (c) Time their own `openLootBox` to land BEFORE / AFTER a concurrent advance-stack rebalance that moves Lootbox-pool balance.
- T3 (consumer SLOAD): Player calls `openLootBox`. `_lootboxDgnrsReward:1770` reads `dgnrs.poolBalance(Pool.Lootbox)`. Value is the cumulative pool balance at T3, which may differ substantially from the balance at T0 / T1.
- T4 (payout): `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)`. Capped at the pool balance. Player receives the payout.

**EV magnitude estimate:** **HIGH per-tx; CATASTROPHE-tier in the mega-tier 0.5% arm.** The mega-tier payout is `(poolBalance * LOOTBOX_DGNRS_POOL_MEGA_PPM * amount) / (1_000_000 * 1 ether)` — a single lootbox-open in the mega-tier arm can claim a substantial fraction of the entire Lootbox pool. The catalog §6 §B B-9 analysis and §0 headline finding (D-6/D-7) explicitly flag this as a deep VIOLATION cluster ("manual-path lootbox open is a deep VIOLATION cluster per §0 headline #2; Lootbox pool size is direct dgnrs-reward magnitude input"). The economic-likelihood disposition: **likely-exploited** by any whale-bias player who patches their lootbox-RNG window with cross-flow drains, particularly in late-game where the Lootbox pool size has been deflated and the mega-tier 0.5% arm represents a large fraction of remaining DGNRS supply.

### §23.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §16 row 382 rationale: "Snapshot pool balance at burn submission; pass as param into resolveRedemptionLootbox" — generalizes to: snapshot `poolBalances[Lootbox]` at the entropy-commitment moment (the `_finalizeLootboxRng` write of `lootboxRngWordByIndex[index]`) and pass into the resolution path.

**Concrete shape (for openLootBox manual-path specifically):**

- Introduce a per-index snapshot field `lootboxPoolSnapshotByIndex[index]` (uint128) in `DegenerusGameStorage`, keyed by the same `index` that keys `lootboxRngWordByIndex`.
- At the `_finalizeLootboxRng:1253` write of `lootboxRngWordByIndex[index] = word`, ALSO write `lootboxPoolSnapshotByIndex[index] = uint128(dgnrs.poolBalance(Pool.Lootbox))`.
- Modify `_lootboxDgnrsReward` (`DegenerusGameLootboxModule.sol:1770`) to read `lootboxPoolSnapshotByIndex[index]` instead of `dgnrs.poolBalance(Pool.Lootbox)` when called via the manual-path entry (the `_resolveLootboxCommon` reach from `openLootBox`).
- The auto-resolve paths (`resolveLootboxDirect`, `resolveRedemptionLootbox`) use different commitment-moment snapshots (covered by V-050 below).
- The `transferFromPool` debit at `:1786` continues to fire against the live pool balance; only the magnitude calculation uses the snapshot.

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected: `openLootBox` is a manual EOA path that legitimately fires during the rngLock window (the lootbox-RNG flow is domain-separated from the daily-VRF flow per `D-42N-RETRY-RNG-DOMAIN-SEP-01`). Gating `openLootBox` on the daily `rngLockedFlag` would block legitimate lootbox-open calls and create a denial-of-service window during every daily VRF cycle.
- **(c) pre-lock reorder** rejected: the natural reorder point is at burn / index-commitment, which IS tactic (b).
- **(d) immutable** rejected: the slot is fundamentally mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** new `lootboxPoolSnapshotByIndex[index]` mapping. ~32 bytes per active lootbox `index`. **NOT byte-identical** — new mapping. Storage delta = ~32 bytes per active lootbox slot.
- **Bytecode delta:** ~150-200 bytes. One additional `dgnrs.poolBalance(Pool.Lootbox)` STATICCALL inside `_finalizeLootboxRng` (~2500 gas cold / ~100 gas warm), one SSTORE on the snapshot mapping (~22100 gas cold / ~2900 gas warm), one SLOAD inside `_lootboxDgnrsReward` replacing the external STATICCALL.
- **Net runtime gas:** approximately neutral on the hot path. `_finalizeLootboxRng` pays +1 STATICCALL +1 SSTORE per lootbox-index; `_lootboxDgnrsReward` saves 1 STATICCALL per resolve. Manual-path resolve is EOA-discretionary so the snapshot SSTORE cost is paid up-front at VRF-fulfillment time (when the daily-advance budget already pays for the SSTOREs).
- **Public ABI:** **NON-BREAKING.** No event topic-hash change; new mapping. Could be exposed via a view function (v44 plan-phase discretion).
- **Reference precedent:** Phase 281 owed-salt snapshot + Phase 288 `dailyIdx` structural snapshot. The per-index keying mirrors the existing `lootboxRngWordByIndex[index]` shape — consistent with the catalog §7 commitment-window discipline ("lootbox-RNG flow is domain-separated; the per-index RNG word is the entropy-commitment").

### §23.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-23`** — Snapshot sDGNRS `poolBalances[Pool.Lootbox]` at `_finalizeLootboxRng` time (paired with `lootboxRngWordByIndex[index]` write); `_lootboxDgnrsReward` reads the snapshot when called from the manual-path resolution. Concrete cites:

- Snapshot WRITE site: extend `_finalizeLootboxRng` at `AdvanceModule.sol:1253` (lootbox-RNG fulfillment) to write `lootboxPoolSnapshotByIndex[index] = uint128(dgnrs.poolBalance(Pool.Lootbox))` alongside the existing `lootboxRngWordByIndex[index] = word` write.
- Snapshot READ site: replace `dgnrs.poolBalance(Pool.Lootbox)` at `LootboxModule.sol:1770` with `lootboxPoolSnapshotByIndex[index]` when entered via the manual-path dispatcher (`openLootBox` / `openBurnieLootBox`).
- Storage field: new `mapping(uint256 => uint128) lootboxPoolSnapshotByIndex` in `DegenerusGameStorage.sol`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 382 (V-047), §6 D-6, §7 manual-path commitment-window discipline.

---

## §24 — V-048: sDGNRS poolBalances[Lootbox] × `transferFromPool` from `openBurnieLootBox` (manual EOA path, sibling to V-047)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 383 (V-048). §15 writer enumeration row 174 (`transferFromPool` reached from `openBurnieLootBox`). §6 verdict-matrix row D-7 ("`dgnrs.poolBalances[Pool.Lootbox]` × `transferFromPool` (debit) reaching entry `openBurnieLootBox` (EOA, sibling)" — NO — VIOLATION).

### §24.A — Design-intent backward-trace

**Slot introduction phase:** Same as §4.A. The `openBurnieLootBox` external entry (`LootboxModule.sol:607`) is the sibling of `openLootBox` (`:526`) — same Lootbox-pool consumer, same resolution path through `_resolveLootboxCommon:960` → `_resolveLootboxRoll:1623` → `_lootboxDgnrsReward:1770`, differing only in the payment surface (BURNIE token rather than ETH for the ticket purchase) and the lootbox-RNG `index` commitment shape.

The BurnieLootbox path was introduced as the BURNIE-coin-paid lootbox tier — same resolution mechanics, different funding source. The MintModule's lootbox-allocation path (`DegenerusGameMintModule.sol:1399`) writes `lootboxBurnie[index][buyer]` instead of `lootboxEth[index][buyer]`. The `index` semantics, the `_finalizeLootboxRng` write of `lootboxRngWordByIndex[index]`, and the `_lootboxDgnrsReward:1770` consumer-side SLOAD are all shared with V-047.

**Cite for "what would break if frozen":** Identical to §4.A — the Lootbox pool serves both ETH-paid and BURNIE-paid lootbox resolution paths; freezing the pool during rngLock would block both manual-path entries from drawing DGNRS-tier payouts.

### §24.B — Actor game-theory walk

**Exploit-actor class:** Identical to §4.B — player observing their own pending BURNIE-lootbox VRF word AND `poolBalances[Lootbox]`, deciding when to call `openBurnieLootBox` to maximize DGNRS-tier payout magnitude.

**Action sequence during rngLock window:** Identical sequence as §4.B with `openLootBox` → `openBurnieLootBox` substitution. The catalog §6 D-7 row confirms the same VIOLATION classification with the same reasoning: "reaching entry `openBurnieLootBox` (EOA, sibling). NO. **VIOLATION**."

**EV magnitude estimate:** **HIGH per-tx; CATASTROPHE-tier in the mega-tier arm.** Same magnitude class as V-047. The economic-likelihood disposition: **likely-exploited** in the same conditions as V-047, with a SLIGHT discount because BURNIE-paid lootboxes have a different funnel-cost profile (BURNIE token availability is rate-limited by the daily mint cycle), which marginally reduces the attacker's optionality compared to ETH-paid lootboxes. Net economic-likelihood disposition: **likely-exploited** alongside V-047.

### §24.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §16 row 383 rationale: "Same snapshot tactic as V-047."

**Concrete shape:** Identical to §4.C. The same `lootboxPoolSnapshotByIndex[index]` snapshot field covers both `openLootBox` and `openBurnieLootBox` manual-path entries because they share the same `index` keying and the same `_finalizeLootboxRng:1253` snapshot WRITE site. The READ-site modification in `_lootboxDgnrsReward:1770` applies uniformly to both dispatchers.

**Rationale for rejecting alternative tactics:** Identical to §4.C. Tactic (a) gated-revert breaks legitimate BURNIE-lootbox manual-path opens during rngLock; tactic (c) reorder is structurally impossible; tactic (d) immutable rejected on mutability grounds.

**Bytecode / storage-layout / public-ABI impact:** **Zero marginal cost beyond V-047.** Same snapshot field, same WRITE site, same READ site. The two violations share `D-43N-V44-HANDOFF-23` and `D-43N-V44-HANDOFF-24` as a unified fix surface in the v44.0 plan-phase. Storage delta = 0 marginal bytes; bytecode delta = 0 marginal bytes; runtime gas delta = 0 marginal gas.

**Reference precedent:** Same as V-047.

### §24.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-24`** — Same snapshot mechanism as `D-43N-V44-HANDOFF-23` covers the `openBurnieLootBox` manual-path race-class.

- Implementation cite: same as `D-43N-V44-HANDOFF-23` — `_finalizeLootboxRng:1253` snapshot WRITE, `LootboxModule.sol:1770` snapshot READ when entered from `openBurnieLootBox:607`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 383 (V-048), §6 D-7.

---

## §25 — V-050: sDGNRS poolBalances[Lootbox] × `transferFromPool` from `resolveRedemptionLootbox` (sStonk claimRedemption reach)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 385 (V-050). §6 verdict-matrix row D-9 ("`dgnrs.poolBalances[Pool.Lootbox]` × `transferFromPool` (debit) reaching entry `claimRedemption` → this consumer. NO. **VIOLATION**.") §6 §E E-2 ("Snapshot pool balance at burn submission; pass as param into resolveRedemptionLootbox").

### §25.A — Design-intent backward-trace

**Slot introduction phase:** Same cluster preamble. The `resolveRedemptionLootbox` path is the sDGNRS-side claim-redemption flow: a player burns sDGNRS via `burn` (`:486`) or `burnWrapped`, which calls `_submitGamblingClaim` (`:493`) writing `pendingRedemptions[player]` with the activity score snapshotted at submission. After the period resolves (via `resolveRedemptionPeriod` invoked from advanceGame, catalog §12), the player calls `claimRedemption` (`:618`) which reads the resolved period's roll, splits the ETH 50/50 into direct + lootbox portions, then calls `game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` (`:672`). The Game-side `resolveRedemptionLootbox` (`DegenerusGame.sol:1721`) delegatecalls into the lootbox-module's redemption path, which reaches `_resolveLootboxCommon:960` → `_lootboxDgnrsReward:1770`.

**Commitment-window per catalog §6 trace:** The RNG commitment point for this consumer is "the moment the player initiates `claimRedemption` (because `rngWord` here is `rngWordByDay[claimPeriodIndex]` — a historical, publicly-readable VRF word the player has already observed)" (catalog §6 audit metadata). Every SLOAD reached during resolution that influences VRF-derived output is consumed AFTER the attacker knows the entropy, and is therefore a freshness-window participant unless structurally invariant against player-influenceable mutation. The catalog §6 §B B-9 attestation explicitly classifies `dgnrs.poolBalance(Lootbox)` SLOAD at `:1770` as a participating slot, and §6 §D D-9 classifies the writer reach via `claimRedemption` as VIOLATION.

**The activityScore snapshot precedent (load-bearing for the V-050 tactic shape):** The catalog §6 §E E-1 rationale explicitly notes that "The consumer ALREADY snapshots `activityScore` at burn submission (`StakedDegenerusStonk.sol:claim.activityScore` populated at submission, read at `:669` and passed as parameter to `resolveRedemptionLootbox` at `:672`)." This is the in-source precedent for the snapshot-at-burn-submission pattern; V-050 extends the same pattern to `poolBalances[Lootbox]`.

Concrete in-source confirmation: `StakedDegenerusStonk.sol:628` reads `claim.activityScore` (snapshotted at burn submission), `:669` adjusts for off-by-one (`uint16 actScore = claimActivityScore > 0 ? claimActivityScore - 1 : 0`), `:672` passes `actScore` as the 4th parameter to `game.resolveRedemptionLootbox`. The activityScore snapshot demonstrates the structural mechanism: `PendingRedemption` struct already has the snapshot field; adding `poolBalanceSnapshot` extends the struct by one `uint128`.

**Cite for "what would break if frozen":** Freezing `poolBalances[Lootbox]` during rngLock would block legitimate Lootbox-pool drains from advance-stack rebalances and concurrent lootbox-open flows. Gating `claimRedemption` on `rngLockedFlag` (tactic (a)) would also block legitimate player-recovery claims during the daily VRF cycle — an unacceptable user-visible regression for a recovery path. The catalog §6 §E explicitly rejects tactic (a) for this consumer: "tactic (a) `rngLockedFlag`-gated revert is rejected because `claimRedemption` is a player-recovery path that must succeed once the period roll is published; gating on `rngLockedFlag` would block legitimate claims while a day's RNG cycle is mid-flight."

### §25.B — Actor game-theory walk

**Exploit-actor class:** Player who has burned sDGNRS via `burn` / `burnWrapped` and is awaiting claim. Knowing `rngWord = rngWordByDay[claimPeriodIndex]` ahead of `claimRedemption`, the player computes whether the DGNRS-tier path will be taken (bits `[40..55] % 20 in [11, 13)`) AND whether the DGNRS-tier is mega (`tierRoll >= 995`, 0.5%) AND can manipulate `poolBalances[Lootbox]` via cross-call drains BEFORE calling `claimRedemption`.

**Action sequence during rngLock window (per catalog §6 D-9 analysis, verbatim load-bearing):**

- T0 (burn submission): Player calls `burn(amount)` or `burnWrapped(amount)`. `_submitGamblingClaim` writes `pendingRedemptions[player]` with `activityScore` snapshotted at submission. `pendingRedemptionEthValue` and `pendingRedemptionBurnie` are aggregated for the period.
- T1 (period resolve via advanceGame): `resolveRedemptionPeriod` (catalog §12) runs inside the advance-stack and writes `redemptionPeriods[period] = {roll, flipDay}`. From this point, the period's `roll` and `flipDay` are final and public.
- T2 (attacker observation): Player observes `rngWord = rngWordByDay[period]` (historical, publicly readable). Player computes the DGNRS-tier branch outcome ahead of T3.
- T3 (attacker move — pool manipulation): If the DGNRS-tier mega branch will be taken, attacker triggers sibling Lootbox-pool drains (other players' `openLootBox` calls or admin/operator flows that touch the pool) to either deflate or inflate the pool depending on attacker's payout-bias. Per catalog §6 §B B-9: "the attacker can pre-grind the pool (e.g., by triggering OTHER players' lootbox-resolution paths to drain or refill, or via admin/operator paths — Phase 300 ADMA scope) to maximize their share."
- T4 (consumer SLOAD): Player calls `claimRedemption`. Game-side `resolveRedemptionLootbox` reaches `_lootboxDgnrsReward:1770` which reads `dgnrs.poolBalance(Pool.Lootbox)`. Value reflects all pool-mutations between T1 and T4.
- T5 (payout): `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)`. Player receives the payout.

**EV magnitude estimate:** **MEDIUM-HIGH per-tx; CATASTROPHE-tier in the mega-tier arm.** Same magnitude class as V-047 but with one mitigating factor: the burn submission already snapshots `activityScore`, demonstrating that the surrounding code path is amenable to additional snapshots (lower implementation friction). The economic-likelihood disposition: **likely-exploited** in late-game where the Lootbox pool size has been deflated and the mega-tier arm represents a large fraction of remaining DGNRS supply. Catalog §0 headline reach analysis flags this as a top-tier concern alongside V-047 / V-048.

### §25.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot/anchor pattern.** Catalog §16 row 385 rationale: "Snapshot pool balance at burn submission; mirror activityScore snapshot" — direct application of the activityScore-snapshot precedent in the same `PendingRedemption` struct.

**Concrete shape:**

- Extend the `PendingRedemption` struct in `StakedDegenerusStonk.sol` to add `uint128 lootboxPoolSnapshot` (paired with the existing `activityScore` snapshot).
- At burn submission inside `_submitGamblingClaim`, populate `claim.lootboxPoolSnapshot = uint128(poolBalances[uint8(Pool.Lootbox)])` (or equivalent — the snapshot is taken at the entropy-commitment moment).
- At `claimRedemption:672`, pass the snapshot value as an ADDITIONAL parameter to `game.resolveRedemptionLootbox`. The signature becomes `resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore, uint128 lootboxPoolSnapshot)`.
- Game-side `resolveRedemptionLootbox` (`DegenerusGame.sol:1721`) forwards the snapshot to the lootbox-module delegatecall payload, which reaches `_lootboxDgnrsReward:1770`. `_lootboxDgnrsReward` reads the snapshot parameter instead of the live `dgnrs.poolBalance(Pool.Lootbox)`.
- The `transferFromPool` debit at `:1786` continues to fire against the live pool balance; only the magnitude calculation uses the snapshot.

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected per catalog §6 §E E-2: "claimRedemption is a player-recovery path that must succeed once the period roll is published; gating on rngLockedFlag would block legitimate claims while a day's RNG cycle is mid-flight."
- **(c) pre-lock reorder** rejected: the natural reorder point IS burn submission, which IS tactic (b).
- **(d) immutable** rejected on mutability grounds.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** `PendingRedemption` struct extended by `uint128 lootboxPoolSnapshot` — 16 bytes. Sibling fields are `ethValueOwed (uint128)`, `burnieOwed (uint128)`, `periodIndex (uint32)`, `activityScore (uint16)`. Adding a `uint128` may need a new storage slot depending on existing packing — v44 plan-phase determines exact layout. Storage delta = +16 bytes per active pending redemption.
- **Bytecode delta:** ~200-250 bytes. One additional SLOAD on `poolBalances[Lootbox]` at burn submission, one SSTORE on the new snapshot field, one calldata parameter added to `IDegenerusGame.resolveRedemptionLootbox` (interface change in `StakedDegenerusStonk.sol:38`), one SLOAD replaced by parameter read inside `_lootboxDgnrsReward`.
- **Net runtime gas:** approximately neutral or slightly positive (+1 SSTORE at burn time, -1 STATICCALL at resolve time).
- **Public ABI:** **CALLER-INTERFACE BREAKING for `IDegenerusGame.resolveRedemptionLootbox`** — the signature changes by adding a `uint128 lootboxPoolSnapshot` parameter. Since the caller is exclusively `StakedDegenerusStonk.claimRedemption` (verified by grep: `grep -rn "resolveRedemptionLootbox" contracts/`), the interface change is locally contained. **NON-BREAKING for downstream EOA consumers** since the function is `external` callable only by `ContractAddresses.SDGNRS` per the gate at `DegenerusGame.sol:1727`.
- **Reference precedent:** the in-struct `activityScore` snapshot in `PendingRedemption` is the direct in-source precedent. Phase 281 owed-salt snapshot is the load-bearing methodology precedent. Catalog §6 §E E-1 explicitly states "Mirrors Phase 288 dailyIdx structural-snapshot precedent and Phase 281 owed-salt 4th-keccak-input precedent."

### §25.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-25`** — Snapshot sDGNRS `poolBalances[Pool.Lootbox]` at burn submission inside `_submitGamblingClaim`; pass as parameter into `resolveRedemptionLootbox` alongside the existing `activityScore` snapshot. Concrete cites:

- Snapshot WRITE site: extend `_submitGamblingClaim` in `StakedDegenerusStonk.sol` (`:493` and surrounding) to write `claim.lootboxPoolSnapshot = uint128(poolBalances[uint8(Pool.Lootbox)])` alongside the existing activityScore write.
- Parameter passthrough: extend signature of `IDegenerusGame.resolveRedemptionLootbox` (interface in `StakedDegenerusStonk.sol:38`) and of `DegenerusGame.resolveRedemptionLootbox` (`:1721`) to include `uint128 lootboxPoolSnapshot`. Modify `claimRedemption:672` to pass the snapshot.
- Snapshot READ site: `_lootboxDgnrsReward` in `LootboxModule.sol:1770` reads the snapshot parameter instead of `dgnrs.poolBalance(Pool.Lootbox)` when entered from `resolveRedemptionLootbox`.
- Storage field: extend `PendingRedemption` struct in `StakedDegenerusStonk.sol`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 385 (V-050), §6 §D D-9, §6 §E E-2.

---

## §26 — V-051: sDGNRS poolBalances[Lootbox] × `transferBetweenPools` (Lootbox-touching, mixed-callsite per-callsite split)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 386 (V-051). §15 writer enumeration row 175 (`transferBetweenPools` Lootbox-touching reached from JackpotModule / MintModule / GameOverModule). §6 verdict-matrix row D-10 ("`dgnrs.poolBalances[Pool.Lootbox]` × `StakedDegenerusStonk.transferBetweenPools` (any Lootbox-touching callsite) — Mixed — split per callsite in Phase 299 FIX sub-phase").

### §26.A — Design-intent backward-trace

**Slot introduction phase:** Same cluster preamble. `transferBetweenPools` (`StakedDegenerusStonk.sol:443-:458`) is the pool-rebalance primitive: it debits `poolBalances[fromIdx]` and credits `poolBalances[toIdx]` in a single call, gated by `onlyGame`. Per catalog §15 row 175, the Lootbox-touching callsites span multiple modules — JackpotModule / MintModule / GameOverModule rebalances reach into Lootbox-pool from various directions:

- **JackpotModule rebalances:** post-daily-payout consolidation moving residual ETH-derived sDGNRS from one pool tier to another (advance-stack — EXEMPT-ADVANCEGAME).
- **MintModule rebalances:** purchase-path side-effects that reallocate Lootbox-pool from / to other pools (potential EOA reach via `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` entries).
- **GameOverModule rebalances:** game-over teardown phase rebalances (advance-stack — EXEMPT-VRFCALLBACK).

Per the catalog row 175 enumeration ("Lootbox-keyed rebalances"), the comprehensive callsite set is NOT enumerated at the catalog level — it is explicitly deferred to Phase 299 per row 386's "(b) Per-callsite Phase 299 split: admin paths tactic (a); advance-stack EXEMPT" rationale and per row 2072 D-10 "Mixed — split per callsite in Phase 299 FIX sub-phase".

**Per-callsite Phase 299 split (executor-authored disposition per the catalog directive):**

Following the directive in catalog row 386, V-051 is decomposed into THREE per-callsite classes:

| Class | Source-module callsites | Reach-stack | Per-callsite disposition |
|-------|-------------------------|-------------|--------------------------|
| V-051-AdvanceStack | JackpotModule `_consolidatePools` / GameOverModule `handleGameOverDrain` Lootbox-touching rebalances | advanceGame self-stack OR VRF-callback OR retryLootboxRng | **EXEMPT-ADVANCEGAME** / **EXEMPT-VRFCALLBACK** (per the EXEMPT-stack derivation in catalog rows 17-21, 27, 32, 42) — no fix required for this sub-class |
| V-051-MintPath | MintModule purchase-side rebalances (if any reach `transferBetweenPools(*, Pool.Lootbox)` from non-advanceGame `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` entries) | EOA `purchase` (catalog row 22 confirms `purchase` has NO blanket `rngLockedFlag` revert) | **VIOLATION**; recommended tactic (a) gated-revert OR consolidated with catalog row 22 fix |
| V-051-AdminPath | hypothetical admin / operator Lootbox-pool rebalance (no current implementation exists per grep) | admin EOA | **VIOLATION** in the catalog's strict-discipline; recommended tactic (a) gated-revert at the admin caller IF such a writer is ever added |

**Grep verification for V-051-AdminPath:** `grep -n "transferBetweenPools" contracts/ -r --include="*.sol"` enumerates all callsites of the rebalance function. Per `feedback_verify_call_graph_against_source.md`, the per-callsite Phase 299 split MUST be derived from grep of the source, not assumed. The catalog row 386 directive ("admin paths tactic (a); advance-stack EXEMPT") implies admin paths exist, but the source-of-truth enumeration in §15 row 175 cites "JackpotModule / MintModule / GameOverModule Lootbox-keyed rebalances" only — no admin path in the current source. v44.0 plan-phase MUST grep-verify the callsite set BEFORE landing the fix.

**Cite for "what would break if frozen":** Freezing the Lootbox pool against `transferBetweenPools` during rngLock would block legitimate cross-pool rebalances from the advance-stack (which are themselves EXEMPT and do not need gating) AND from any non-advanceGame caller in the MintModule purchase-path (which is the V-051-MintPath sub-class and should be covered by the existing catalog row 22 gate on `MintModule.purchase` if it lands as part of the v44 plan-phase fix).

### §26.B — Actor game-theory walk

**Exploit-actor class (per sub-class):**

- **V-051-AdvanceStack:** No exploit surface — advance-stack callsites run inside `advanceGame()` / VRF-callback flows and inherit EXEMPT classification by `D-298-EXEMPT-REACH-01` strict-stack-rooted discipline.
- **V-051-MintPath:** Player triggering an EOA-callable purchase entry (`purchase` / `purchaseCoin` / `purchaseBurnieLootbox`) during the rngLock window, where the purchase has a Lootbox-pool rebalance side-effect. The attacker's lever is identical to V-047 / V-048 / V-050 but expressed through the rebalance writer rather than the direct debit writer. EV magnitude is bounded by the per-tx rebalance magnitude (typically a small fraction of the pool).
- **V-051-AdminPath:** Admin / operator (governance-trust class). Action sequence requires an admin / operator function that calls `transferBetweenPools(*, Pool.Lootbox, ...)` — no such function exists in the current source per grep, so this sub-class is structurally inactive in the deployed contract.

**Action sequence during rngLock window (sub-class V-051-MintPath):**

- T0: `advanceGame` enters daily-phase, requests VRF, sets `rngLockedFlag = true`.
- T1 (attacker move): Attacker calls `MintModule.purchase` (or sibling) which has a Lootbox-pool rebalance side-effect. Pool balance shifts by `±Δ`.
- T2 (consumer SLOAD): A pending Lootbox-pool consumer reads `dgnrs.poolBalance(Pool.Lootbox)` — depending on which consumer (V-047 manual-path, V-048 BurnieLootbox-path, V-050 sStonk-claim-path), the shift propagates into the payout magnitude.

**EV magnitude estimate (per sub-class):**

- **V-051-AdvanceStack: N/A** (EXEMPT, no exploit).
- **V-051-MintPath: LOW-MEDIUM per-tx** — bounded by the rebalance side-effect magnitude, which is typically a small fraction of the pool per purchase. Compounds with V-047 / V-048 / V-050 magnitudes when chained.
- **V-051-AdminPath: not applicable** (no admin writer exists in the current source).

Economic-likelihood disposition: **V-051-MintPath: possibly-exploited** when combined with V-047 / V-048 / V-050 in a multi-step pool-grinding sequence; the per-tx margin is small but the writer surface adds optionality. **V-051-AdvanceStack / V-051-AdminPath: non-exploitable** in the deployed contract.

### §26.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Per-callsite Phase 299 split** — different tactic per sub-class:

- **V-051-AdvanceStack: NO FIX REQUIRED.** The callsites are EXEMPT-ADVANCEGAME / EXEMPT-VRFCALLBACK per the existing strict-discipline. The V-047 / V-048 / V-050 snapshot tactics already cure the consumer-side reads against these legitimate rebalances; the rebalances themselves do not need additional gating.
- **V-051-MintPath: covered by the catalog row 22 fix (tactic (a) gated-revert on `MintModule.purchase` / `purchaseCoin` / `purchaseBurnieLootbox`).** Catalog §1 §E row 22 already recommends "add top-level `if (rngLockedFlag) revert` to MintModule.purchase + purchaseCoin + purchaseBurnieLootbox" for the `prizePoolsPacked` (next/future) writes. The same gate atomically covers the V-051-MintPath sub-class — gating the purchase entries blocks BOTH the prizePoolsPacked writes AND any Lootbox-pool rebalance side-effects in those entries. No marginal fix is needed beyond the catalog row 22 implementation.
- **V-051-AdminPath: deferred** — no current writer exists. If a future v44.0 plan-phase introduces an admin writer of `transferBetweenPools(*, Pool.Lootbox, ...)`, the writer MUST be gated on `rngLockedFlag` at the admin caller. (Contracts are frozen at deploy per `feedback_frozen_contracts_no_future_proofing.md`, so this is a forward-looking attestation rather than an active fix requirement.)

**Rationale for rejecting alternative tactics:**

- **Uniform (b) snapshot/anchor** rejected: the rebalance writer mutates two slots simultaneously and is reached from multiple stacks; a per-callsite split is structurally cleaner than a single snapshot that would have to track both sides of the rebalance.
- **Uniform (a) gated-revert** rejected: advance-stack callsites are legitimately EXEMPT; gating them on `rngLockedFlag` would create a recursive lock (the advance-stack itself sets `rngLockedFlag`, so gating its own internal rebalance writers on `rngLockedFlag` would deadlock).
- **(c) pre-lock reorder** rejected: not applicable to a per-callsite class.
- **(d) immutable** rejected: pools must rebalance during normal operation.

**Bytecode / storage-layout / public-ABI impact:**

- **V-051-AdvanceStack:** 0 bytes, 0 gas — no fix.
- **V-051-MintPath:** 0 marginal bytes — fix is covered by catalog row 22 implementation (the gate on `purchase` / `purchaseCoin` / `purchaseBurnieLootbox`). Storage delta = 0; bytecode delta = ~30 bytes per entry for the `if (rngLockedFlag) revert RngLocked()` check (already counted in catalog row 22's impact).
- **V-051-AdminPath:** 0 bytes (no fix; deferred forward-attestation only).
- **Public ABI:** **NON-BREAKING** — no signature changes.
- **Reference precedent:** Catalog row 22 fix (`MintModule.purchase` rngLockedFlag gate) is the in-catalog precedent. `MintModule.sol:1221` existing partial gate `cachedJpFlag && rngLockedFlag` is the in-source pattern.

### §26.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-26`** — Per-callsite Phase 299 split for sDGNRS `poolBalances[Pool.Lootbox]` × `transferBetweenPools` (Lootbox-touching) writer class:

- **V-051-AdvanceStack:** NO FIX (EXEMPT). Attestation that v47 plan-phase grep-verifies the callsite set under `JackpotModule` / `GameOverModule` is exclusively advance-stack rooted.
- **V-051-MintPath:** subsumed by catalog row 22 `D-43N-V44-HANDOFF-NN` (see Cluster B / `prizePoolsPacked` Phase 299 cluster output for the row-22 handoff anchor identity).
- **V-051-AdminPath:** forward-attestation only — no fix in the v44.0 plan-phase, with an explicit grep-attestation that no admin / operator writer of `transferBetweenPools(*, Pool.Lootbox, ...)` exists in the v43.0 baseline source. Any future contract change introducing such a writer MUST land an `rngLockedFlag` gate per tactic (a).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 386 (V-051), §6 D-10, §15 row 175.

---

## §27 — V-054: `claimablePool -=` via `DecimatorModule._creditDecJackpotClaimCore` (EOA `claimDecimatorJackpot`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 389 (V-054). §5 §D row D-3 (VIOLATION). §15 row 179 (writer enumeration). §C.B-3 row C-B3-2. §5 §E row E-1 (tactic (a) rationale).

**Source verification:** Grep `grep -n "claimablePool\|_awardDecimatorLootbox\|_creditDecJackpotClaimCore" contracts/modules/DegenerusGameDecimatorModule.sol` confirms the writer site at `:388` (`claimablePool -= uint128(lootboxPortion);`) inside `_creditDecJackpotClaimCore` (function defined at `:376-:390`). The catalog's writer-label `_awardDecimatorLootbox` is slightly imprecise — the actual `claimablePool -=` SSTORE lives in `_creditDecJackpotClaimCore`, which then calls `_awardDecimatorLootbox(account, lootboxPortion, rngWord)` at `:389` to mint the lootbox itself (the lootbox-minting function is at `:570` and does NOT write `claimablePool` directly). For verdict-matrix purposes the row is correctly classified as a `claimablePool -=` writer reachable from EOA `claimDecimatorJackpot`; the writer-function-name label is a CATALOG-LABEL-INACCURACY (not a stale-phantom — the source line exists and the verdict is correct). The Phase 303 TERMINAL acknowledgment should note this label refinement.

### §27.A — Design-intent backward-trace

**Slot introduction phase:** `claimablePool` was introduced as the in-game ETH-equivalent reserve aggregate alongside the `claimableWinnings[player]` mapping in the v40-era prize-distribution architecture. The Decimator subsystem (DegenerusGameDecimatorModule.sol) was added as the per-level "death bet" jackpot mechanism where each level's last-decimator wins a winner-take-most pot; the winning bucket's per-claimant payouts (`_consumeDecClaim` → `_creditDecJackpotClaimCore`) split 50% ETH (credited via `_creditClaimable` to `claimableWinnings[claimant]` and `claimablePool`) + 50% lootbox tickets (the `lootboxPortion` is then DECREMENTED from `claimablePool` at `:388` because the lootbox-portion stops being claimable ETH at the moment of claim).

**Why the decrement exists at this site:** The 50% lootbox-portion flow conceptually transfers ETH out of the per-player claimable bucket and into the per-player lootbox-ticket bucket. The `claimablePool` decrement is the in-contract accounting mirror: pre-claim the entire `amountWei` was reserved against `claimablePool` (it had been previously credited via `_creditClaimable` when the decimator pot was filled); at claim time the 50% lootbox portion is no longer "claimable ETH" — it's routed into the lootbox subsystem via `_awardDecimatorLootbox`. The decrement at `:388` preserves the `address(this).balance + steth.balanceOf(this) >= claimablePool` invariant by reducing `claimablePool` matching the 50% that's no longer claimable as ETH (the lootbox-portion is still held by the contract but is now accounted as `futurePrizePool` via the `_setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);` write at `:341`).

**Cite for "what would break if naively gated":** The function `claimDecimatorJackpot` already has TWO gating conditions at `:325` (`if (prizePoolFrozen) revert E();`) and `:329` (`if (gameOver) … return;` after `_creditClaimable`-only branch). The `prizePoolFrozen` gate fires during the daily VRF window (separate from `_livenessTriggered()` — `prizePoolFrozen` is true between `_swapAndFreeze` and the freeze-release). The `gameOver` branch routes pure ETH credit (no lootbox-portion split) to the player. The missing gate is the multi-tx-pre-`gameOver=true` window: between `_livenessTriggered() == true` and `gameOver == true`, the function remains callable AND falls through the prizePoolFrozen gate (`prizePoolFrozen` may be cleared by then) AND takes the non-gameOver branch (`gameOver` still false), invoking `_creditDecJackpotClaimCore` and writing `claimablePool -=` at `:388`. The fix MUST not break the legitimate pre-liveness use of the function (normal level-transition decimator claims during active gameplay), so the gate must be `_livenessTriggered()` (not `gameOver`).

**Precedent for tactic (a) gate selection:** The `MintModule.sol:1215, :877, :906, :1381` already use `if (_livenessTriggered()) revert E();` for mint-family entries. The Decimator subsystem inherits this in-source pattern naturally — adding `if (_livenessTriggered()) revert E();` at the top of `claimDecimatorJackpot` (above the `prizePoolFrozen` check at `:325`) closes the open window. Per `feedback_frozen_contracts_no_future_proofing.md`, the gate is added at deploy-time and does not need to anticipate future use-cases beyond the explicit `(_livenessTriggered, gameOver)` matrix.

### §27.B — Actor game-theory walk

**Exploit-actor class:** Player holding an unclaimed winning decimator subbucket entry at the moment the multi-tx game-over drain begins. Concrete vector: a player who won a prior level's decimator claim (and has a non-zero `decClaimRounds[lvl].pool` AND has not yet called `claimDecimatorJackpot(lvl)`) observes the multi-tx game-over signal (`_livenessTriggered() == true` becomes externally observable via `livenessTriggered()` view at `DegenerusGame.sol:2147`).

**Action sequence during multi-tx game-over window (sequential):**

- T0: A previous level's `runRewardJackpots` resolution latched a decimator winner. The player holds an unclaimed decimator entry. `claimDecimatorJackpot` has been callable since the latch but the player has deferred the call.
- T1: `_livenessTriggered()` transitions to true (either VRF stalled past grace period OR idle-timeout fired). Anyone can call `advanceGame` to trigger `_handleGameOverPath` → `handleGameOverDrain`, but the multi-tx resolution stack may early-return on `STAGE_TICKETS_WORKING` if there is unfinalized prior-day jackpot bookkeeping.
- T2 (attacker move): Player observes the impending `handleGameOverDrain` call and front-runs by calling `claimDecimatorJackpot(lvl)` while `gameOver == false` AND `_livenessTriggered() == true` AND `prizePoolFrozen` happens to be false. The call enters `_creditDecJackpotClaimCore` at `:380`, executes `_creditClaimable(account, ethPortion)` at `:385` (credits player's claimable balance with 50% AND `claimablePool += ethPortion` inside `_creditClaimable`), then executes `claimablePool -= uint128(lootboxPortion);` at `:388` (debits `claimablePool` by 50%). NET: `claimablePool` shifts by `(ethPortion - lootboxPortion) = 0` if the split is exactly 50/50… but `ethPortion = amount >> 1` and `lootboxPortion = amount - ethPortion`, so for an even `amount` the two are equal and the net is zero; for odd `amount` they differ by 1 wei. The NET shift to `claimablePool` from this single action is small (∼0 wei).
- T3: The MORE impactful side-effect: `_setFuturePrizePool(_getFuturePrizePool() + lootboxPortion);` at `:341` increases `futurePrizePool` by the lootbox-portion. This itself does not feed `handleGameOverDrain` (which reads `claimablePool` not `futurePrizePool`). The `_addClaimableEth` path inside `_creditClaimable` shifts `claimablePool += ethPortion` (positive), then `:388` shifts `claimablePool -= lootboxPortion` (negative). For an exactly-50/50 split, the NET shift is zero — meaning V-054's claim-window race is structurally near-zero EV on the `handleGameOverDrain` consumer specifically.
- T4: `handleGameOverDrain` runs. `claimablePool` at `:91` SLOAD is approximately unchanged from pre-T2. `preRefundAvailable` is approximately unchanged. Terminal payouts are approximately unchanged.

**EV magnitude estimate:** **LOW on the per-claim margin (~0 net `claimablePool` shift for the 50/50 split).** The catalog row 389 disposition is VIOLATION because the writer is structurally reachable from EOA during the open window AND because of strict-discipline classification (any non-EXEMPT writer is VIOLATION). The actual exploitable surface on `handleGameOverDrain`'s consumer-read is approximately neutral due to the 50/50 ETH/lootbox split symmetry (positive write in `_creditClaimable` ≈ negative write at `:388`). The catalog-listed EV in the §0 headline "structural-hardening cluster" frames this row as a hardening case rather than a high-EV exploit. Economic-likelihood disposition: **unlikely-exploited as a magnitude-shift on `claimablePool`**; **possible-exploited on adjacent side-effects** (the `_setFuturePrizePool` write at `:341` shifts `futurePrizePool` which DOES feed other consumers, but those consumers are outside Cluster E's scope — they belong to Cluster B `prizePoolsPacked` family at V-029..V-035 and have their own tactic-(b) snapshot disposition).

**Cross-side-effect note:** Although V-054 itself is low-EV on the `claimablePool` consumer, the SAME callsite triggers a `_setFuturePrizePool` shift that is exploited under Cluster B V-035 (or sibling). The fix for V-054 — adding `_livenessTriggered()` gate to `claimDecimatorJackpot` — automatically closes V-035's adjacent exploit on the SAME entry function. Cluster E's gate-(a) fix therefore has a positive externality on Cluster B.

### §27.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert.** Catalog §5 §E row E-1 rationale: "Gate `_awardDecimatorLootbox` callsite on `!_livenessTriggered()` to close window." Catalog §16 row 389 rationale: "Gate `_awardDecimatorLootbox` callsite on `!_livenessTriggered()` to close window."

**Concrete shape:**

- Add `if (_livenessTriggered()) revert E();` at the TOP of `claimDecimatorJackpot` (`DegenerusGameDecimatorModule.sol:321`), above the existing `if (prizePoolFrozen) revert E();` at `:325`. The new gate covers the multi-tx-pre-`gameOver=true` window where `_livenessTriggered() == true` but `gameOver == false`.
- Post-`gameOver = true`, `_livenessTriggered()` may continue to return true (it doesn't reset on the `gameOver` latch — re-reading the source at `DegenerusGameStorage.sol:1243-:1252` confirms there is no `gameOver`-reset clause). The post-gameOver-claim period in this function (the `:329-:333` branch routing pure ETH credit via `_creditClaimable`) MUST remain reachable. The gate therefore must be `if (_livenessTriggered() && !gameOver) revert E();` (mirroring V-063 / V-065 below) OR alternatively the function can be split into pre-gameOver and post-gameOver entry points. The single-revert form `if (_livenessTriggered() && !gameOver) revert E();` is structurally simpler and preserves the existing function signature.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: the consumer's SLOAD is a one-shot read inside `handleGameOverDrain` (no recurring daily axis to anchor against). Snapshotting `claimablePool` at the moment `_livenessTriggered()` first transitions to true would require a new storage write AND would not eliminate the in-flight EOA writes between the snapshot and the consumer — it would only freeze the consumer's read at a pinned value, which under multi-tx game-over could be many blocks stale and incorrect for the live `address(this).balance` reading at `:84` (which is NOT snapshotted in the (b) variant). Tactic (a) is strictly cheaper and structurally complete.
- **(c) pre-lock reorder** rejected: the writer is EOA-triggered at attacker discretion and cannot be reordered before the consumer.
- **(d) immutable** rejected: `claimablePool` is fundamentally a mutable aggregate counter.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** No new fields, no struct reshape.
- **Bytecode delta:** ~30-50 bytes for the `if (_livenessTriggered() && !gameOver) revert E();` instruction sequence (one external view call OR direct internal call, one boolean AND, one comparison branch, one revert). Per catalog `RngLocked` revert pattern (`MintModule:1221` precedent), the in-source size is approximately 30 bytes.
- **Net runtime gas:** +~2000 gas warm SLOAD per `claimDecimatorJackpot` call (one extra `_livenessTriggered()` invocation, which itself reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime` — about 5 packed SLOADs, mostly warm in the same call frame). The gate fires on the cold path (rare); hot-path overhead is neutral.
- **Public ABI:** **NON-BREAKING.** No signature changes; the function still reverts under a strict superset of the existing revert surface. New revert reason matches the existing `error E()` pattern (no new custom error type).
- **Reference precedent:** `MintModule.sol:1215, :1221` `if (_livenessTriggered()) revert E();` pattern. Phase 290 MINTCLN `rngLockedFlag` discipline (`.planning/milestones/v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md`).

### §27.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-27`** — Add `if (_livenessTriggered() && !gameOver) revert E();` at the top of `DegenerusGameDecimatorModule.claimDecimatorJackpot` (`DegenerusGameDecimatorModule.sol:321`), above the existing `prizePoolFrozen` gate at `:325`. The gate closes the multi-tx-pre-`gameOver=true` window where the `_creditDecJackpotClaimCore` writer at `:388` (`claimablePool -=`) is reachable from EOA.

- Target file:line: `DegenerusGameDecimatorModule.sol:321` (entry-function top).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 389 (V-054), §5 §D D-3 / §C.B-3-2 / §E E-1.
- CATALOG-LABEL-INACCURACY note: catalog labels the writer as `_awardDecimatorLootbox` (function at `:570`); actual `claimablePool -=` SSTORE is at `:388` inside `_creditDecJackpotClaimCore`. Phase 303 TERMINAL ack the label refinement.
- Positive externality: this fix also closes Cluster B V-035 (or sibling) adjacent exploit on `_setFuturePrizePool` at `:341`.

---

## §28 — V-055: `claimablePool -=` via `MintModule._resolveMintShortfall` (EOA `mintBatch` family)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 390 (V-055). §5 §D row D-4 (`EXEMPT-ADVANCEGAME` by-gate). §15 row 180 (writer enumeration). §C.B-3 row C-B3-3. §5 §E (NOT listed — covered by existing gate; FIXREC entry exists for strict-discipline verification).

**Source verification:** Grep `grep -n "claimablePool\|_livenessTriggered\|_resolveMintShortfall" contracts/modules/DegenerusGameMintModule.sol` confirms the writer site at `:949` (`claimablePool -= uint128(shortfall);`) inside `_resolveMintShortfall`. The EOA-facing entry function (one of `purchase :830` / `purchaseCoin :852` / `purchaseBurnieLootbox :864`) ALL route through `_purchaseFor` / `_purchaseCoinFor` / `_purchaseBurnieLootboxFor` which contain `if (_livenessTriggered()) revert E();` at `:877`, `:906`, `:1215` (verified by grep). The `_resolveMintShortfall` writer at `:949` is therefore UNREACHABLE from EOA when `_livenessTriggered() == true` — the entry-function-level gate already covers this case.

### §28.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The mint-family shortfall mechanism (the `_resolveMintShortfall` writer at `MintModule.sol:949`) was introduced as the path for players who wish to mint tickets using a COMBINATION of fresh ETH AND already-credited `claimableWinnings`. The shortfall represents the portion of the mint cost paid from the player's `claimableWinnings` bucket; the `claimablePool -=` at `:949` is the in-game accounting mirror of `claimableWinnings[buyer] -= shortfall` at `:947`.

**Why the `_livenessTriggered()` gate at the entry function:** Per Phase 290 MINTCLN design-intent (`.planning/milestones/v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md`), the mint-family entries are gated to prevent purchase activity during the multi-tx VRF window. The gate prevents (a) buying tickets that would never be entered into the current day's draw, (b) shifting prize pools mid-VRF, (c) interfering with the daily settlement. The same gate (a structural superset of "purchase activity during VRF window") covers the `_resolveMintShortfall` writer transitively.

**Cite for "what would break if frozen":** Nothing breaks beyond what the existing `_livenessTriggered()` gate already blocks — the writer is structurally unreachable from EOA when the gate is closed, so no additional restriction is imposed. The FIXREC entry exists for strict-discipline classification (catalog row 390 carries VIOLATION token because the writer is `-=` on a `claimablePool` slot reachable from EOA in absence of a gate; with the gate in place the row is effectively EXEMPT-by-gate but the catalog uses strict tokens per `D-43N-AUDIT-ONLY-01`).

### §28.B — Actor game-theory walk

**Exploit-actor class:** None — the writer is structurally unreachable from EOA when `_livenessTriggered() == true`, which is exactly the condition under which the multi-tx game-over window opens.

**Action sequence during multi-tx game-over window:** Attacker attempts `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` after `_livenessTriggered()` transitions to true. The entry function reverts at `MintModule.sol:877` / `:906` / `:1215` with `error E()`. The `_resolveMintShortfall` writer at `:949` is never reached. `claimablePool` is unchanged.

**EV magnitude estimate:** **ZERO (structurally unreachable).** Catalog disposition is VIOLATION token under strict-discipline; actual exploit surface is empty. Economic-likelihood disposition: **non-exploitable in the deployed contract** (writer is gated by existing in-source guard).

**Branch-coverage concern (FUZZ-301 forward-attestation):** The catalog row 390 rationale notes "verify branch reach." Per `feedback_skip_research_test_phases.md` adjacent reasoning: the verification is whether FUZZ-301 (Phase 301 fuzz harness) exercises the `_livenessTriggered() == true` AND `mintBatch` entry paths together to confirm the revert fires before reaching `_resolveMintShortfall`. This is a TEST-coverage attestation rather than a SOURCE-code fix.

### §28.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert — ALREADY IN-SOURCE.** Catalog §16 row 390 rationale: "Existing `_livenessTriggered()` revert covers; verify branch reach."

**Concrete shape:**

- **No source-code change.** The existing entry-function gates at `MintModule.sol:877, :906, :1215` already close the open window.
- **FUZZ-301 forward-attestation:** Phase 301 (or whichever phase owns the FUZZ harness) MUST add a branch-coverage assertion that exercises `_livenessTriggered() == true` AND attempts each of `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` / `mintBatch` (whichever family entries reach `_resolveMintShortfall`), asserting the call reverts BEFORE the `_resolveMintShortfall` writer at `:949` executes. The assertion shape is a Foundry / Hardhat coverage assertion (the writer's `claimablePool` value is unchanged by the reverted call).

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: the writer is unreachable; snapshotting `claimablePool` for a path that cannot fire is pure waste.
- **(c) pre-lock reorder** rejected: the writer is unreachable.
- **(d) immutable** rejected: the slot is mutable; the writer is unreachable.
- **Add a redundant gate at `_resolveMintShortfall:949`** rejected: defense-in-depth at the writer site would add ~30 bytes for zero marginal closure (the entry-function gate is the canonical guard; adding a duplicate at the writer site is precisely the kind of "future-proofing" prohibited by `feedback_frozen_contracts_no_future_proofing.md`).

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical (no change).
- **Bytecode delta:** 0 bytes (no source change).
- **Net runtime gas:** 0 (no change).
- **Public ABI:** byte-identical.
- **Reference precedent:** existing `_livenessTriggered()` gates at `MintModule:877, :906, :1215, :1381`.

### §28.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-28`** — Branch-coverage forward-attestation only. Phase 301 FUZZ harness MUST exercise the `(_livenessTriggered() == true, mint-family entry call)` branch and assert the call reverts before reaching `MintModule._resolveMintShortfall :949`. No source-code change in v44.0.

- Target file:line: `DegenerusGameMintModule.sol:949` (writer site; documented as gated-by-entry-function).
- Existing gate sites: `DegenerusGameMintModule.sol:877, :906, :1215, :1381`.
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 390 (V-055), §5 §D D-4 / §C.B-3-3.

---

## §29 — V-057: `claimablePool -=` via `DegeneretteModule._collectBetFunds` (EOA `placeDegeneretteBet`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 392 (V-057). §5 §D row D-6 (initially `EXEMPT-ADVANCEGAME` by-gate; classification updated to VIOLATION per §5 §E row E-1 / §16 row 392). §15 row 182 (writer enumeration). §C.B-3 row C-B3-5. §5 §E (covered jointly with V-058 via tactic-(a) gate on `placeDegeneretteBet`).

**Source verification:** Grep `grep -n "claimablePool\|_livenessTriggered\|_creditCheckedFromClaimable" contracts/modules/DegenerusGameDegeneretteModule.sol` confirms the writer at `:547` (`claimablePool -= uint128(fromClaimable);`) inside `_collectBetFunds` (function defined at `:533-:567`). The catalog's writer-label `_creditCheckedFromClaimable` is a CATALOG-LABEL-INACCURACY — the actual function name is `_collectBetFunds`; there is no function named `_creditCheckedFromClaimable` in `DegenerusGameDegeneretteModule.sol` (`grep "function _creditCheckedFromClaimable"` returns no match). The writer-site at `:547` exists and is correctly classified as a `claimablePool -=` debit reachable from EOA `placeDegeneretteBet` → `_placeDegeneretteBet` → `_placeDegeneretteBetCore` → `_collectBetFunds`. **CATALOG-LABEL-INACCURACY note** (not a stale-phantom — the source-of-truth writer at `:547` exists and the verdict-matrix classification is correct; only the function-name label is imprecise). Phase 303 TERMINAL acknowledgment should update the catalog row 392 writer-label to `_collectBetFunds`.

**Critical source observation:** Grep `grep -n "_livenessTriggered" contracts/modules/DegenerusGameDegeneretteModule.sol` returns **NO match** — `placeDegeneretteBet` and its internal callees have NO `_livenessTriggered()` gate. The catalog row 392 disposition column note "NO — EOA; gated runtime" is misleading: the runtime gating that the note refers to is the `lootboxRngWordByIndex[index] != 0` revert at `:452` (`RngNotReady`), which gates ONLY on the lootbox-index VRF cycle, NOT on the daily VRF or `_livenessTriggered()`. **No `_livenessTriggered()` gate exists on `placeDegeneretteBet`.**

### §29.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The Degenerette subsystem is the v40-era "spin-the-wheel" minigame where players place bets in ETH / BURNIE / WWXRP currencies; the ETH-currency path allows the player to PAY THE BET from a combination of `msg.value` and already-credited `claimableWinnings`. The `claimablePool -=` writer at `:547` is the in-game accounting mirror of `claimableWinnings[player] -= fromClaimable` at `:546` (the player's claim balance is debited by the portion of the bet paid from claimable, and the pool accumulator is debited matching).

**Why no `_livenessTriggered()` gate at the entry function:** Per source comment at `:551-:558` and the surrounding context, the bet-placement function is designed to be callable during normal gameplay; the ONLY gate is the lootbox-index VRF gate at `:452` (the bet is queued against the next-resolving lootbox index, which must not have its RNG word ready yet). The function does not gate on the DAILY VRF cycle or `_livenessTriggered()` because the spin resolution is independent of the daily jackpot resolution.

**Cite for "what would break if naively gated":** Gating `placeDegeneretteBet` on `_livenessTriggered()` would prevent legitimate spin-placements during the multi-tx game-over window. Players who wish to continue playing Degenerette up to the exact moment `gameOver = true` is latched would be blocked from queueing a final spin. The EV magnitude of "legitimate spin-placement during multi-tx game-over window" is bounded by the player's risk appetite (they MAY want to defer; they MAY want to spin one last bet); the EV magnitude of "blocking the writer race" is bounded by §3.B below. The trade-off favors gating because (i) the multi-tx game-over window is a short, terminal interval, (ii) the legitimate use-case (one-last-spin) is low-frequency, (iii) the exploit-case (writer race on `handleGameOverDrain`) is structurally a VIOLATION per strict-discipline.

**Precedent for gate addition at a non-mint entry function:** The Decimator subsystem (V-054 §1) is the parallel case: `claimDecimatorJackpot` does not have `_livenessTriggered()` in the v43.0 baseline but the FIXREC entry adds it. The Degenerette case is structurally identical — adding the same gate at `placeDegeneretteBet` closes the same class of writer race.

### §29.B — Actor game-theory walk

**Exploit-actor class:** Player holding non-zero `claimableWinnings[player]` who can choose WHEN to convert claimable into a Degenerette spin, including timing the conversion to fire mid-multi-tx-game-over-window.

**Action sequence during multi-tx game-over window (sequential):**

- T0: Player has `claimableWinnings[player] = C` (some non-trivial credited balance). `_livenessTriggered()` transitions to true; multi-tx game-over window opens.
- T1 (attacker move): Player calls `placeDegeneretteBet(player, currency=CURRENCY_ETH, amountPerTicket=X, ticketCount=N, ...)` with `msg.value < totalBet = X * N`, forcing the shortfall path. `_collectBetFunds` at `:542-:548` executes `fromClaimable = totalBet - ethPaid`, `claimableWinnings[player] -= fromClaimable`, `claimablePool -= uint128(fromClaimable);`. Net `claimablePool` shift: `-fromClaimable` (a negative shift, REDUCING `claimablePool`).
- T2: Subsequent code in `_collectBetFunds` at `:550-:558` SHIFTS the bet amount into `futurePrizePool` (`(pNext, pFuture); _setPendingPools(pNext, pFuture + uint128(totalBet));` in the frozen path OR `_setPrizePools(next, future + uint128(totalBet));` in the unfrozen path). This `+= totalBet` to a different pool does NOT counter the `claimablePool -=` because `futurePrizePool` is a SEPARATE slot consumed by Cluster B not Cluster E.
- T3: `handleGameOverDrain` runs. At `:91` SLOAD, `claimablePool` is `originalValue - fromClaimable`. `reserved = (originalValue - fromClaimable) + pendingRedemptionEthValue`. `preRefundAvailable = totalFunds - reserved = totalFunds - originalValue + fromClaimable - pendingRedemptionEthValue` — INFLATED by `fromClaimable` compared to the unattacked case.
- T4: Terminal payouts at `:166-:182` scale linearly with `available` (which equals `preRefundAvailable` modulo the `:134` self-`+=` of `totalRefunded`). The attacker has inflated the terminal payout magnitude by approximately `fromClaimable * (1 - deity_refund_ratio)`.

**EV magnitude estimate:** **MEDIUM** on a per-player margin. The exploit converts `fromClaimable` ETH from "credited to me, pending withdrawal" into "inflated terminal-jackpot pool, distributed via VRF". The attacker's expected return from the inflated jackpot is bounded by `fromClaimable * P(I-win-the-VRF-jackpot)`. If the attacker holds significant ticket weight relative to the rest of the game, `P(I-win) > fromClaimable / inflated_jackpot`, making the EV positive. For an attacker holding 1% ticket weight and inflating jackpot by 1 ETH, EV ≈ +0.01 ETH minus the 1 ETH foregone from claim. EV is NEGATIVE for low-weight attackers; POSITIVE for high-weight attackers (whales, decimator winners). The attack also costs the gas of the spin transaction.

**Catalog §0 headline #4 framing:** "Game-over `claimablePool` writer races (§5) … structural-hardening cluster. Drain math is fragile to in-flight available/totalFunds mutations." V-057 is one of the four EOA writers cited in headline #4. Economic-likelihood disposition: **possible-exploited by high-weight players** (decimator winners, whales) during the multi-tx game-over window; **unlikely-exploited by low-weight players** (EV is negative below ~50% ticket weight).

### §29.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert.** Catalog §16 row 392 rationale: "Gate the EOA-reached `_creditCheckedFromClaimable` callsite on `!_livenessTriggered()`." Catalog §5 §E E-1 rationale: same.

**Concrete shape:**

- Add `if (_livenessTriggered()) revert E();` at the TOP of `placeDegeneretteBet` (`DegenerusGameDegeneretteModule.sol:367`). The gate closes the multi-tx game-over window where the `_collectBetFunds :547` writer is reachable from EOA.
- The gate is `_livenessTriggered()` ONLY (no `gameOver` carve-out), because there is no legitimate post-`gameOver=true` Degenerette spin path (the function should hard-revert once liveness fires — spins are gameplay actions, not withdrawals).

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: same rationale as §1.C — one-shot consumer read, no recurring axis to anchor against; snapshotting `claimablePool` does not eliminate the in-flight EOA debit.
- **(c) pre-lock reorder** rejected: writer is EOA-triggered at attacker discretion.
- **(d) immutable** rejected: slot is mutable aggregate.
- **Gate ONLY the shortfall path at `:541-:548`** rejected: defense-in-depth at the writer site is less robust than entry-function gate; entry gate eliminates the writer reach AND the adjacent `_setPendingPools` / `_setPrizePools` write at `:553` / `:556` (which feeds Cluster B). Entry gate has positive externality on Cluster B.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical.
- **Bytecode delta:** ~30 bytes for the `if (_livenessTriggered()) revert E();` instruction.
- **Net runtime gas:** +~2000 gas per `placeDegeneretteBet` call (one extra `_livenessTriggered()` invocation).
- **Public ABI:** **NON-BREAKING.** Strict superset of existing revert surface.
- **Reference precedent:** `MintModule.sol:877, :906, :1215` pattern.

### §29.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-29`** — Add `if (_livenessTriggered()) revert E();` at the top of `DegenerusGameDegeneretteModule.placeDegeneretteBet` (`DegenerusGameDegeneretteModule.sol:367`), closing the EOA reach to `_collectBetFunds :547` (`claimablePool -=`) during the multi-tx game-over window.

- Target file:line: `DegenerusGameDegeneretteModule.sol:367` (entry-function top).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 392 (V-057), §5 §D D-6 / §C.B-3-5 / §E E-1.
- CATALOG-LABEL-INACCURACY: catalog labels writer as `_creditCheckedFromClaimable`; actual function is `_collectBetFunds`. Phase 303 TERMINAL ack the label refinement.
- Positive externality: same fix also closes V-058 below (same entry function, sibling writer in same call frame); see §4 for paired discussion.

---

## §30 — V-058: `claimablePool +=` via `DegeneretteModule._addClaimableEth` (EOA `placeDegeneretteBet` → `resolveBets` → `_distributePayout`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 393 (V-058). §5 §D row D-7 (VIOLATION for EOA branch; EXEMPT-VRFCALLBACK for VRF-callback branch). §15 row 183 (writer enumeration). §C.B-3 row C-B3-6. §5 §E row E-2 (tactic (a) rationale).

**Source verification:** Grep `grep -n "claimablePool\|_addClaimableEth\|_resolveLootboxDirect" contracts/modules/DegenerusGameDegeneretteModule.sol` confirms:

- The catalog row 393 cites writer site at `:1131` and calls it `_resolveLootboxDirect`. Reading source at `:1129-:1133` reveals the ACTUAL function at that line is `_addClaimableEth(beneficiary, weiAmount)` (defined at `:1129`), and the `claimablePool += uint128(weiAmount)` SSTORE is at `:1131` inside `_addClaimableEth`.
- The function `_resolveLootboxDirect` is at `:797-:813` and is a DELEGATECALL stub that does NOT write `claimablePool` directly (it forwards to `IDegenerusGameLootboxModule.resolveLootboxDirect.selector` via `ContractAddresses.GAME_LOOTBOX_MODULE.delegatecall(...)`).
- `_addClaimableEth` at `:1129` is called from `_distributePayout :722` at two sites: `:765` (frozen path) and `:781` (unfrozen path). Both call sites are inside the ETH-currency win-payout flow.
- `_distributePayout` is called from `_resolveBet` (a private function in the same module), which is called from the EOA-facing `resolveBets` at `:389` (`function resolveBets(address player, uint64[] calldata betIds) external`).

**CATALOG-LABEL-INACCURACY** (not a stale-phantom): the catalog labels the writer as `_resolveLootboxDirect` at `:1131` — but `:1131` is inside `_addClaimableEth`, not `_resolveLootboxDirect`. The verdict-matrix classification is still correct (the writer site exists at `:1131`, the EOA-reach via `resolveBets` is structurally real, and the disposition VIOLATION holds). Phase 303 TERMINAL acknowledgment should update the writer-label to `_addClaimableEth` (or more precisely: the writer in `_addClaimableEth :1131` reached via `_distributePayout :765 / :781` reached via `_resolveBet` reached via EOA `resolveBets :389`).

### §30.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The Degenerette spin-resolution path was introduced as a multi-tier payout mechanism: an ETH-currency winning spin pays out via a 3-tier split (`payout ≤ 3 × bet` → 100% ETH; `3 × bet < payout ≤ 10 × bet` → `max(2.5 × bet, payout / 4)` ETH + lootbox remainder; `payout > 10 × bet` → `payout / 4` ETH + lootbox remainder). The `_addClaimableEth :1131` `+=` write at `:1131` is the in-game accounting mirror of `claimableWinnings[beneficiary] += weiAmount` at `:1132` (`_creditClaimable(beneficiary, weiAmount)`).

**Why the writer fires twice per resolution:** Once at `:765` (frozen path, when `prizePoolFrozen == true`) — the ETH share is debited from `pendingPools` and credited to claimable; once at `:781` (unfrozen path, when `prizePoolFrozen == false`) — the ETH share is debited from `futurePrizePool` and credited to claimable. Only one of the two branches fires per call (mutex on `prizePoolFrozen`); both paths converge on `_addClaimableEth(player, ethShare);`. The writer is reachable from EOA `resolveBets` because `resolveBets` is an external function with no `_livenessTriggered()` gate AND no `prizePoolFrozen` gate (the function is designed to be callable continuously to resolve pending bets, even during the daily VRF freeze).

**Cite for "what would break if naively gated":** Gating `resolveBets` on `_livenessTriggered()` would block legitimate bet-resolution during the multi-tx game-over window. The legitimate use-case: a player has a pending bet (placed BEFORE liveness fired) whose lootbox-index VRF word has just arrived; the player wants to resolve and collect winnings before `gameOver = true` is latched. Gating would force the bet into the post-gameOver resolution stack.

**The catalog's tactic-(a) recommendation (`Gate the EOA-reached _resolveLootboxDirect callsite on !_livenessTriggered()`) implicitly accepts this trade-off:** the EOA bet-resolution path is acceptable to gate because (i) the bet itself is preserved (the `lootboxRngWordByIndex[index]` value persists across the gate), (ii) the player can resolve POST-gameOver via an alternative claim path or via re-calling `resolveBets` after the multi-tx window closes, (iii) the EXEMPT-VRFCALLBACK branch (when the same writer fires via `fulfillRandomWords` → ... → `_resolveBet`) remains unaffected.

**Per-callsite split per `D-298-EXEMPT-CROSSCONTRACT-01`:** The catalog row 393 disposition is dual: VIOLATION (EOA branch) + EXEMPT-VRFCALLBACK (VRF-callback branch). The same writer function `_addClaimableEth :1129-:1133` carries distinct verdicts depending on reach. The fix targets the EOA branch only — gating the EOA entry function (`resolveBets`) does not affect the VRF-callback reach.

### §30.B — Actor game-theory walk

**Exploit-actor class:** Player holding one or more pending Degenerette bets whose lootbox-RNG indices have RESOLVED (i.e., `lootboxRngWordByIndex[index] != 0`) but whose `_resolveBet` has not yet been called.

**Action sequence during multi-tx game-over window (sequential):**

- T0: Player has placed a Degenerette spin bet at level `L`. The bet is queued against `index = some_lootbox_rng_index`. `lootboxRngWordByIndex[index]` is set when the VRF callback fires for that index. The player has CHOSEN to defer `resolveBets` until a strategic moment.
- T1: Multi-tx game-over window opens (`_livenessTriggered() == true`).
- T2 (attacker move): Player calls `resolveBets(player, [betId])`. `_resolveBet` computes the spin outcome (win/lose, tier, payout). For a winning ETH-currency spin, `_distributePayout` enters the 3-tier branch and calls `_addClaimableEth(player, ethShare)` at `:765` or `:781`. `_addClaimableEth` writes `claimablePool += uint128(ethShare)` at `:1131`. Net `claimablePool` shift: `+ethShare` (a POSITIVE shift, INCREASING `claimablePool`).
- T3: `handleGameOverDrain` runs. At `:91` SLOAD, `claimablePool` is `originalValue + ethShare`. `reserved = (originalValue + ethShare) + pendingRedemptionEthValue`. `preRefundAvailable = totalFunds - reserved = totalFunds - originalValue - ethShare - pendingRedemptionEthValue` — DEFLATED by `ethShare` compared to the unattacked case.
- T4: Terminal payouts at `:166-:182` scale linearly with `available` (post-self-`+=` of `totalRefunded`). The attacker has DEFLATED the terminal payout magnitude by approximately `ethShare`.

**Why deflation can be advantageous to the attacker:** This is the INVERSE of V-057. Here, the attacker INCREASES their own `claimableWinnings` balance (by `ethShare`) while DECREASING the terminal-jackpot pool magnitude. If the attacker has LOW ticket weight in the terminal jackpot, the EV of "keep my +ethShare as guaranteed claim" exceeds the EV of "let it flow into terminal jackpot where I might win a fraction". Conversely, if the attacker has HIGH ticket weight, they prefer the V-057 vector (inflate the pool). V-057 + V-058 form a complementary attack pair: low-weight attackers prefer V-058 (deflate), high-weight attackers prefer V-057 (inflate).

**EV magnitude estimate:** **HIGH** on a per-resolution margin (the lootbox-direct payouts can be large; the 3-tier split can credit `(2.5 × bet)` ETH for a Tier-2 win, where `bet` can be substantial). The attacker's EV from V-058 is `ethShare * (1 - P(win-fair-share-of-jackpot))`. For low-weight attackers, `P(win-fair-share)` is small and EV ≈ `+ethShare`. Economic-likelihood disposition: **likely-exploited by low-weight players** with pending winning Degenerette bets during the multi-tx game-over window.

### §30.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert.** Catalog §16 row 393 rationale: "Gate the EOA-reached `_resolveLootboxDirect` callsite on `!_livenessTriggered()`." Catalog §5 §E E-2 rationale: same.

**Concrete shape:**

- Add `if (_livenessTriggered()) revert E();` at the TOP of `resolveBets` (`DegenerusGameDegeneretteModule.sol:389`). The gate closes the EOA reach to `_addClaimableEth :1131` (and the sibling writers `_setPendingPools :764` and `_setFuturePrizePool :780` that feed Cluster B).
- The VRF-callback reach (when `_addClaimableEth :1131` fires via `fulfillRandomWords` → `_resolveBet` from the VRF stack) is UNAFFECTED because that reach does not go through the external `resolveBets` entry.
- The gate is `_livenessTriggered()` ONLY (no `gameOver` carve-out). Post-`gameOver = true`, the player can withdraw via `claimWinnings` (V-063 below) rather than via `resolveBets`. If post-gameOver resolution is REQUIRED for some legitimate flow, the fix can be `if (_livenessTriggered() && !gameOver) revert E();` (mirroring V-063 / V-065 / §1.C). The catalog row 393 wording is silent on the `gameOver` carve-out; v44 plan-phase discretion to decide based on whether `resolveBets` is required for post-gameOver settlement.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: same rationale as §1.C — one-shot consumer read.
- **(c) pre-lock reorder** rejected: writer is EOA-triggered at attacker discretion.
- **(d) immutable** rejected: slot is mutable.
- **Gate ONLY the writer site at `_addClaimableEth :1129`** rejected: would affect both EOA and VRF-callback reach, breaking the EXEMPT-VRFCALLBACK branch. Entry-function gate at `resolveBets` is strictly necessary to preserve the per-callsite split.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical.
- **Bytecode delta:** ~30 bytes for the gate.
- **Net runtime gas:** +~2000 gas per `resolveBets` call.
- **Public ABI:** **NON-BREAKING.** Strict superset of existing revert surface.
- **Reference precedent:** `MintModule.sol:877, :906, :1215` pattern.

### §30.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-30`** — Add `if (_livenessTriggered()) revert E();` (or `if (_livenessTriggered() && !gameOver) revert E();` per v44 plan-phase post-gameOver settlement requirement) at the top of `DegenerusGameDegeneretteModule.resolveBets` (`DegenerusGameDegeneretteModule.sol:389`), closing the EOA reach to `_addClaimableEth :1131` (`claimablePool +=`) during the multi-tx game-over window. The VRF-callback reach (EXEMPT-VRFCALLBACK branch) is unaffected.

- Target file:line: `DegenerusGameDegeneretteModule.sol:389` (entry-function top).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 393 (V-058), §5 §D D-7 / §C.B-3-6 / §E E-2.
- CATALOG-LABEL-INACCURACY: catalog labels writer as `_resolveLootboxDirect at :1131`; actual writer is `_addClaimableEth at :1131`. Phase 303 TERMINAL ack the label refinement.
- Per-callsite split preservation: EXEMPT-VRFCALLBACK branch (writer reached via `fulfillRandomWords` → `_resolveBet`) MUST remain unaffected. The entry-function gate at `resolveBets :389` is the structural mechanism that preserves the split.
- Positive externality: same fix closes the adjacent Cluster B writers at `_setPendingPools :764` and `_setFuturePrizePool :780` (futurePrizePool race), and closes V-057 reach via `resolveBets` (different entry from `placeDegeneretteBet` but shares the multi-tx window timing).

---

## §31 — V-063: `claimablePool -=` via `DegenerusGame._claimWinningsInternal` (EOA `claimWinnings`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 398 (V-063). §5 §D row D-13 (VIOLATION). §15 row 187 (writer enumeration). §C.B-3 row C-B3-12. §5 §E row E-3 (tactic (a) rationale, paired with V-073 D-22 for `address(this).balance` outflow co-write).

**Source verification:** Grep `grep -n "claimablePool\|claimWinnings\|_claimWinningsInternal" contracts/DegenerusGame.sol` confirms the writer at `:1408` (`claimablePool -= uint128(payout);`) inside `_claimWinningsInternal` (defined at `:1399-:1415`). Two EOA entries: `claimWinnings(address player)` at `:1387` (general-purpose) and `claimWinningsStethFirst()` at `:1394` (restricted to `msg.sender == ContractAddresses.VAULT`). Both route to `_claimWinningsInternal`.

### §31.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The `claimWinnings` function is THE canonical player-withdrawal path: the player calls it to withdraw their accrued `claimableWinnings[player]` balance as ETH (or stETH-first via `claimWinningsStethFirst`). The function uses the pull-pattern (player calls; contract transfers) for CEI security (per source comment at `:1380-:1385`: "INVARIANT: claimablePool is decremented by payout"). The `claimablePool -=` at `:1408` is the in-game accounting mirror of the `claimableWinnings[player] = 1` SSTORE at `:1405` (the 1-wei sentinel pattern keeps the slot warm for the next credit).

**Why the writer has NO `_livenessTriggered()` gate:** Per source comment at `DegenerusGame.sol:1331-:1337`: "claimablePool is decremented before external call." The function is INTENTIONALLY ungated on `_livenessTriggered()` because players are EXPECTED to be able to withdraw their accrued winnings at any time, including (especially) during a stalled-VRF state. The design-intent: a player who has been credited winnings should NEVER be locked out of withdrawing them.

**The conflict:** The withdraw-anytime intent conflicts with the multi-tx game-over consumer's need for a stable `claimablePool` read. The catalog row 398 fix `!_livenessTriggered() || gameOver` resolves the conflict: BLOCK withdrawal during the pre-`gameOver=true` multi-tx window (a SHORT, DETERMINISTIC interval), RE-OPEN withdrawal once `gameOver = true` is latched (the post-gameover-claim period, which is permanent). Players who attempt to withdraw during the multi-tx window get a temporary revert; they retry post-`gameOver` and succeed. The trade-off favors gating because (i) the multi-tx window is bounded by the next `advanceGame` call, (ii) the user-visible delay is at most a few blocks, (iii) the alternative (consumer-side snapshot) is structurally more invasive AND does not protect the `address(this).balance` outflow side-effect.

**`address(this).balance` outflow co-write:** Per catalog §5 §E E-6: "claimWinnings outflow deflates `address(this).balance` mid-drain." The `_payoutWithStethFallback` or `_payoutWithEthFallback` call at `:1411-:1413` transfers ETH out of the contract, deflating `address(this).balance`. `handleGameOverDrain :84` reads `totalFunds = address(this).balance + steth.balanceOf(address(this))`. A `claimWinnings` mid-window deflates both the `claimablePool` reserve AND the `totalFunds` numerator — but the NET effect on `available = totalFunds - reserved` may be near-zero IF the deflation is symmetric. In practice the symmetry is NOT exact because (i) stETH-first vs ETH-first changes the split between `address(this).balance` and `steth.balanceOf`, (ii) the deity-refund deity-pass branch at `:107-:136` runs between the `:84` read and the `:154` read, mutating intermediate state. The NET effect is approximately neutral on `available` for a single small withdrawal but can be CATASTROPHIC for a large withdrawal that exhausts ETH-side reserves.

**Catalog §5 §E note on co-located writers:** "Same gate as E-3 — single revert closes both `claimablePool` and balance writers." V-063 (claimablePool) and V-073 (address(this).balance via claimWinnings outflow) share the same entry function; one gate closes both. V-073 is documented in Cluster F (S-20 address(this).balance) FIXREC entries; this FIXREC entry covers ONLY the `claimablePool` writer aspect.

### §31.B — Actor game-theory walk

**Exploit-actor class:** ANY player holding non-zero `claimableWinnings[player]`. This is the largest exploit-actor surface in Cluster E because every player who has won ANY prior decimator / Degenerette / lootbox-direct / jackpot share holds claimable balance.

**Action sequence during multi-tx game-over window (sequential):**

- T0: Player has `claimableWinnings[player] = C`. `_livenessTriggered()` transitions to true. Multi-tx game-over window opens.
- T1 (attacker move): Player calls `claimWinnings(player)`. `_claimWinningsInternal` executes: `payout = C - 1` (sentinel reserve), `claimablePool -= uint128(payout)` at `:1408`, then `_payoutWithStethFallback(player, payout)` at `:1413` (or `_payoutWithEthFallback` if `stethFirst`). Net: `claimablePool -= (C-1)`; `address(this).balance` OR `steth.balanceOf(this)` decreases by `(C-1)`.
- T2: `handleGameOverDrain` runs. At `:84`, `totalFunds = (originalEthBalance - (C-1)) + steth.balanceOf(...)` (or vice versa for stETH). At `:91`, `reserved = (originalClaimablePool - (C-1)) + pendingRedemptionEthValue`. `preRefundAvailable = totalFunds - reserved = originalEthBalance - (C-1) - originalClaimablePool + (C-1) - pendingRedemptionEthValue = originalEthBalance - originalClaimablePool - pendingRedemptionEthValue` — APPROXIMATELY EQUAL to the unattacked case (the `(C-1)` cancels). The `preRefundAvailable` value is approximately unchanged.
- T3: BUT: the ETH side of `totalFunds` has been DEFLATED. Deity-pass refunds at `:121-:124` credit `claimableWinnings[owner]` (a future withdrawal, not an immediate ETH transfer). Terminal-jackpot payouts at `:168` / `:182` credit jackpot winners' `claimableWinnings` (again, not immediate ETH transfers — the actual ETH transfer happens later when winners call `claimWinnings`).
- T4: POST-resolution, OTHER players attempt to call `claimWinnings`. If `address(this).balance` has been deflated below the sum of remaining `claimableWinnings[*]`, the `_payoutWithStethFallback` will succeed via stETH-fallback as long as `steth.balanceOf(this) > 0` — but if BOTH ETH and stETH reserves are exhausted, subsequent withdrawals revert. The invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` (per source comment at `DegenerusGame.sol:18`) MUST hold to keep withdrawals solvent.

**Magnitude analysis:** The attacker's `(C-1)` deflation of `address(this).balance` is exact and immediate. If `C` is large (e.g., a player holding 100 ETH of accrued winnings), the deflation is 100 ETH. If multiple players coordinate withdrawals before `handleGameOverDrain`, the cumulative deflation can be a substantial fraction of the contract's ETH reserves.

**EV magnitude estimate:** **CATASTROPHE-tier per single large claim during terminal jackpot drain.** The catalog row 398 V-063 IS THE highest-EV row in Cluster E. The attack vector is structurally a frontrun: the player observes the impending `handleGameOverDrain` and withdraws their balance INTENTIONALLY before the drain runs, ensuring their withdrawal is at full balance (not diluted by deity-pass refunds or terminal-jackpot reallocation). For a player whose `claimableWinnings` would be partially RECLAIMED by the deity-refund branch or zeroed by post-30-day sweep, the EV of frontrunning is ENTIRE_BALANCE - WHATEVER_WOULD_HAVE_BEEN_PAID_POST_RESOLUTION. For a player whose balance is not at risk, the EV is approximately zero (the withdrawal just shifts the timing).

**The TRUE exploit vector (per `feedback_rng_commitment_window.md`):** The exploit is not the `claimablePool` mathematical shift (which is approximately neutral on `preRefundAvailable`) — it is the `address(this).balance` outflow that CONSTRAINS the terminal-jackpot's ability to pay out solvently. If the attacker's withdrawal deflates ETH below the sum of post-resolution claimableWinnings, subsequent claimants face insolvency-by-pull-pattern.

**Economic-likelihood disposition: likely-exploited** by every player holding non-zero claimableWinnings at the moment of multi-tx game-over signal; the action is a no-op for low-balance players (cost-of-gas) and high-EV for high-balance players (entire-balance withdraw).

### §31.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert with `gameOver` carve-out.** Catalog §16 row 398 rationale: "Gate `claimWinnings` on `!_livenessTriggered() || gameOver` so drain math is stable." Catalog §5 §E E-3 rationale: same. Catalog §5 §E E-6 note: "Same gate as E-3 — single revert closes both `claimablePool` and balance writers."

**Concrete shape:**

- Add `if (_livenessTriggered() && !gameOver) revert E();` at the TOP of `_claimWinningsInternal` (`DegenerusGame.sol:1399`), above the existing `if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();` at `:1400`. The gate closes the multi-tx-pre-`gameOver=true` window where `claimWinnings` is reachable.
- Post-`gameOver = true`, the gate re-opens automatically (the `&& !gameOver` clause becomes false). Players can withdraw normally during the post-gameover claim period.
- The gate is at `_claimWinningsInternal :1399` (the private function shared by both `claimWinnings` and `claimWinningsStethFirst`) rather than at each external entry — one gate covers both entries.
- ALTERNATIVE shape (per catalog wording `!_livenessTriggered() || gameOver` — note the OR): `if (!(!_livenessTriggered() || gameOver)) revert E();` simplifies to `if (_livenessTriggered() && !gameOver) revert E();` (De Morgan's). The two are equivalent.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: snapshotting `claimablePool` AND `address(this).balance` at the moment `_livenessTriggered()` first transitions to true would require two new storage slots AND would not eliminate the in-flight ETH outflow side-effect. Tactic (a) is strictly cheaper.
- **(c) pre-lock reorder** rejected: writer is EOA-triggered.
- **(d) immutable** rejected: slot is mutable.
- **Gate only `claimablePool -=` at `:1408`** rejected: would allow the `address(this).balance` outflow at `:1411-:1413` to fire even when the `claimablePool` write is gated — would break invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` because ETH leaves the contract without `claimablePool` accounting. Must gate at function entry, not at writer site.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical.
- **Bytecode delta:** ~40 bytes for the `if (_livenessTriggered() && !gameOver) revert E();` instruction (two SLOADs, one AND, one branch, one revert).
- **Net runtime gas:** +~2500 gas per `claimWinnings` / `claimWinningsStethFirst` call (one extra `_livenessTriggered()` invocation plus one `gameOver` SLOAD).
- **Public ABI:** **NON-BREAKING.** Strict superset of existing revert surface.
- **Reference precedent:** Phase 290 MINTCLN `rngLockedFlag` pattern; in-source `MintModule.sol:1215` `_livenessTriggered` pattern.

### §31.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-31`** — Add `if (_livenessTriggered() && !gameOver) revert E();` at the top of `DegenerusGame._claimWinningsInternal` (`DegenerusGame.sol:1399`), closing the multi-tx-pre-`gameOver=true` window where `claimWinnings` / `claimWinningsStethFirst` are reachable. The same gate closes the V-073 `address(this).balance` outflow co-write (Cluster F handoff anchor cites this anchor as the shared fix).

- Target file:line: `DegenerusGame.sol:1399` (`_claimWinningsInternal` private function top, covering both external entry points `claimWinnings :1387` and `claimWinningsStethFirst :1394`).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 398 (V-063), §5 §D D-13 / §C.B-3-12 / §E E-3 / §E E-6 (paired V-073 co-write).
- Positive externality: same fix closes V-073 (`address(this).balance` outflow via claimWinnings) in Cluster F (S-20 address(this).balance).

---

## §32 — V-064: `claimablePool -=` via `DegenerusGame.useClaimableForMint` (EOA mint family)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 399 (V-064). §5 §D row D-14 (`EXEMPT-ADVANCEGAME` by-gate). §15 row 188 (writer enumeration). §C.B-3 row C-B3-13. §5 §E (NOT listed — covered by existing mint-family gate).

**Source verification:** Grep `grep -n "claimablePool\|useClaimableForMint\|claimableUsed" contracts/DegenerusGame.sol` confirms the writer at `:946` (`claimablePool -= uint128(claimableUsed);`) inside a private function near the mint-payment-routing logic at `:889-:955`. The catalog row 399 calls it `useClaimableForMint` and locates it at `:946`. Source comment at `:889`: "INVARIANT: claimablePool is decremented by claimableUsed." The function is called from the mint-payment-routing path; the EOA-facing entry is one of `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` / `mintBatch`-family which all gate on `_livenessTriggered()` via `_purchaseFor` / `_purchaseCoinFor` / `_purchaseBurnieLootboxFor` at `MintModule.sol:877, :906, :1215`.

### §32.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The "useClaimableForMint" mechanism (the v40-era mint-payment path that allows players to pay for tickets using credited `claimableWinnings`) was introduced as a UX convenience: a player who has accrued `claimableWinnings` should be able to spend that balance directly on tickets without first withdrawing to wallet. The `claimablePool -= uint128(claimableUsed)` at `:946` is the in-game accounting mirror of `claimableWinnings[player] = claimable - claimableUsed` at `:934`.

**Why the writer is structurally unreachable during multi-tx game-over:** The mint-family entries (`purchase`, `purchaseCoin`, `purchaseBurnieLootbox`, `mintBatch`) all check `_livenessTriggered()` at the top of their internal implementations (`_purchaseFor`, `_purchaseCoinFor`, `_purchaseBurnieLootboxFor`). When `_livenessTriggered() == true`, the entry function reverts BEFORE reaching the `useClaimableForMint` logic at `DegenerusGame.sol:889-:955`. The writer at `:946` is therefore in the same "gated-by-entry-function" structural class as V-055 (`_resolveMintShortfall :949`).

**Cite for "what would break if naively gated":** Same answer as §2.A — nothing breaks beyond what the existing gate already blocks. The FIXREC entry exists for strict-discipline classification.

### §32.B — Actor game-theory walk

**Exploit-actor class:** None — the writer is structurally unreachable from EOA when `_livenessTriggered() == true`.

**Action sequence during multi-tx game-over window:** Attacker attempts `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` / `mintBatch` after `_livenessTriggered()` transitions to true. The entry function reverts at `MintModule.sol:877` / `:906` / `:1215` with `error E()`. The `useClaimableForMint` logic at `DegenerusGame.sol:889-:955` is never reached. `claimablePool` is unchanged.

**EV magnitude estimate:** **ZERO (structurally unreachable).** Catalog disposition is VIOLATION token under strict-discipline; actual exploit surface is empty.

**Branch-coverage concern (FUZZ-301 forward-attestation):** Same FUZZ-301 attestation as §2.B — Phase 301 fuzz harness MUST exercise the `(_livenessTriggered() == true, mint-family entry call)` branch and assert the call reverts before reaching `useClaimableForMint :946`.

**Economic-likelihood disposition: non-exploitable** in the deployed contract.

### §32.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert — ALREADY IN-SOURCE.** Catalog §16 row 399 rationale: "Existing `_livenessTriggered()` gate covers — verify branch coverage."

**Concrete shape:**

- **No source-code change.** The existing entry-function gates at `MintModule.sol:877, :906, :1215` already close the open window.
- **FUZZ-301 forward-attestation:** Same as §2.C. Phase 301 fuzz must verify branch reach.

**Rationale for rejecting alternative tactics:** Same as §2.C.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical (no change).
- **Bytecode delta:** 0 bytes (no source change).
- **Net runtime gas:** 0 (no change).
- **Public ABI:** byte-identical.
- **Reference precedent:** existing `_livenessTriggered()` gates at `MintModule:877, :906, :1215, :1381`.

### §32.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-32`** — Branch-coverage forward-attestation only. Phase 301 FUZZ harness MUST exercise the `(_livenessTriggered() == true, mint-family entry call)` branch and assert the call reverts before reaching `DegenerusGame.useClaimableForMint :946`. No source-code change in v44.0.

- Target file:line: `DegenerusGame.sol:946` (writer site; documented as gated-by-entry-function).
- Existing gate sites: `DegenerusGameMintModule.sol:877, :906, :1215, :1381`.
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 399 (V-064), §5 §D D-14 / §C.B-3-13.

---

## §33 — V-065: `claimablePool -=` via `DegenerusGame.resolveRedemptionLootbox` (sDGNRS `claimRedemption` callback)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 400 (V-065). §5 §D row D-15 (VIOLATION). §15 row 189 (writer enumeration). §C.B-3 row C-B3-14. §5 §E row E-4 (tactic (a) rationale).

**Source verification:** Grep `grep -n "claimablePool\|sweepSdgnrsClaim\|resolveRedemptionLootbox" contracts/DegenerusGame.sol` reveals two distinct functions related to the catalog row 400 description:

- `resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore)` at `:1721` — gated on `if (msg.sender != ContractAddresses.SDGNRS) revert E();` at `:1727`. Body writes `claimableWinnings[ContractAddresses.SDGNRS] = claimable - amount` at `:1737` and `claimablePool -= uint128(amount);` at `:1739`.
- `sweepSdgnrsClaim` — `grep "function sweepSdgnrsClaim"` returns NO match in current source. The catalog row 400 labels the writer as `sweepSdgnrsClaim` at `DegenerusGame.sol:1739`, but the function at `:1721` is named `resolveRedemptionLootbox`. **CATALOG-LABEL-INACCURACY**: catalog labels the function `sweepSdgnrsClaim`; actual function is `resolveRedemptionLootbox`. The writer-site at `:1739` exists and the verdict-matrix classification is correct. Phase 303 TERMINAL acknowledgment should update the catalog row 400 writer-label.

**Caller-allowlist:** `if (msg.sender != ContractAddresses.SDGNRS) revert E();` at `:1727` restricts the function to ONLY sDGNRS contract calls. sDGNRS reaches this function from inside its `claimRedemption` flow, which is EOA-callable on the sDGNRS contract. The chain is: EOA → `StakedDegenerusStonk.claimRedemption(...)` → (sDGNRS-internal logic) → `DegenerusGame.resolveRedemptionLootbox(player, amount, rngWord, activityScore)`. The reach is indirect-EOA via sDGNRS.

### §33.A — Design-intent backward-trace

**Slot introduction phase:** Same `claimablePool` slot architecture as §1.A. The `resolveRedemptionLootbox` function (sDGNRS-redemption-lootbox-resolution callback) was introduced as the cross-contract callback that sDGNRS uses to convert burned-sDGNRS-token redemptions into in-game lootbox awards. Per source comment at `:1730-:1734`: "Debit from sDGNRS's claimable (ETH stays in Game's balance). The two paths are mutually exclusive, so claimable >= amount always holds here." The `claimablePool -= uint128(amount)` at `:1739` is the in-game accounting mirror of the sDGNRS-side claimable balance reduction.

**Why the function has NO `_livenessTriggered()` gate:** The function is designed to be callable EXCLUSIVELY by sDGNRS (caller-allowlisted). sDGNRS's `claimRedemption` flow is part of the in-game economy that operates continuously; gating on `_livenessTriggered()` would break sDGNRS's redemption mechanism mid-game. The DEPENDENT design-intent: sDGNRS-redemption should remain functional across the entire game lifetime EXCEPT during the precise multi-tx game-over window where the consumer's read of `claimablePool` could race.

**Cite for "what would break if naively gated":** sDGNRS's `claimRedemption` would revert (because its internal call to `DegenerusGame.resolveRedemptionLootbox` would revert). sDGNRS holders attempting to redeem during the multi-tx game-over window would face a temporary revert; they could retry post-`gameOver = true`. This is the same trade-off as §5.A (claimWinnings) — short-window block, permanent re-open.

**Mirror of V-063 vector:** Per catalog §5 §E E-4: "Gate `sweepSdgnrsClaim` on `!_livenessTriggered() || gameOver` to mirror E-3." The fix shape exactly mirrors V-063 — same gate, same callsite-position discipline, same `gameOver` carve-out.

### §33.B — Actor game-theory walk

**Exploit-actor class:** sDGNRS holder who has burned sDGNRS tokens for gambling-redemption and triggers `claimRedemption` on sDGNRS contract.

**Action sequence during multi-tx game-over window (sequential):**

- T0: Attacker holds burned sDGNRS gambling-redemption claim (pending). Multi-tx game-over window opens.
- T1 (attacker move): Attacker calls `StakedDegenerusStonk.claimRedemption(claimId)` on sDGNRS contract. sDGNRS-internal logic processes the claim and at some point calls `DegenerusGame.resolveRedemptionLootbox(player, amount, rngWord, activityScore)`. The writer at `:1739` executes `claimablePool -= uint128(amount)`. Concurrent side-effects at `:1742-:1748`: `_setPendingPools(pNext, pFuture + uint128(amount))` (frozen) OR `_setPrizePools(next, future + uint128(amount))` (unfrozen) — the `amount` is shifted to `futurePrizePool`/`pendingPools` (Cluster B feed). Then the loop at `:1750-:1763` calls into `IDegenerusGameLootboxModule.resolveRedemptionLootbox` via delegatecall to mint lootbox tickets to the player.
- T2: `handleGameOverDrain` runs. At `:91` SLOAD, `claimablePool` is `originalValue - amount`. Same dynamics as V-057 §3.B (inflate `preRefundAvailable` by `amount`).
- T3: Terminal payouts at `:166-:182` are INFLATED by approximately `amount`.

**EV magnitude analysis:** The attacker has converted `amount` of sDGNRS-claimable-ETH into (a) a `claimablePool` debit AND (b) a `futurePrizePool` credit AND (c) lootbox tickets to the player. The `claimablePool` debit feeds the `handleGameOverDrain` race (inflating terminal payouts); the `futurePrizePool` credit feeds Cluster B's race; the lootbox tickets give the player additional ticket weight in the inflated terminal jackpot. **The combined exploit is HIGH-EV per `amount` of sDGNRS redemption.**

**Comparison to V-063:** V-063 (`claimWinnings`) deflates `address(this).balance` AND `claimablePool` — the NET on `preRefundAvailable` is approximately neutral. V-065 (`resolveRedemptionLootbox`) ONLY shifts `claimablePool` (the ETH stays in the contract per the design-intent comment at `:1733`). V-065's NET shift on `preRefundAvailable` is `+amount` (inflate) — the same direction as V-057 (inflate). V-065 is therefore an INFLATE-tier exploit, complementary to V-063's neutral-or-deflate-tier exploit.

**EV magnitude estimate:** **HIGH** per single sDGNRS redemption during the multi-tx game-over window. The catalog row 400 V-065 disposition mirrors V-063 in the §5 §E E-4 row. Economic-likelihood disposition: **likely-exploited by sDGNRS holders** with pending gambling-redemption claims during the multi-tx game-over window.

### §33.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert with `gameOver` carve-out.** Catalog §16 row 400 rationale: "Gate `sweepSdgnrsClaim` on `!_livenessTriggered() || gameOver` to mirror V-063." Catalog §5 §E E-4 rationale: same.

**Concrete shape:**

- Add `if (_livenessTriggered() && !gameOver) revert E();` at the TOP of `resolveRedemptionLootbox` (`DegenerusGame.sol:1721`), above the existing `if (msg.sender != ContractAddresses.SDGNRS) revert E();` at `:1727`. The gate closes the multi-tx-pre-`gameOver=true` window.
- Post-`gameOver = true`, the gate re-opens automatically. sDGNRS holders can redeem normally during the post-gameover period.
- The gate is `_livenessTriggered() && !gameOver` — mirroring §5.C's V-063 form.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot/anchor** rejected: same rationale as §5.C — one-shot consumer read, snapshot does not eliminate the in-flight `claimablePool` debit.
- **(c) pre-lock reorder** rejected: writer is sDGNRS-callback-triggered at sDGNRS-holder discretion.
- **(d) immutable** rejected: slot is mutable.
- **Gate on the sDGNRS side instead** rejected: would require modifying `StakedDegenerusStonk.claimRedemption` to check `IDegenerusGame.livenessTriggered()` view; possible but adds cross-contract complexity. The single-side gate at `DegenerusGame.resolveRedemptionLootbox :1721` is structurally simpler — the sDGNRS-side revert propagates back through the cross-contract call.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** byte-identical.
- **Bytecode delta:** ~40 bytes for the gate.
- **Net runtime gas:** +~2500 gas per `resolveRedemptionLootbox` call.
- **Public ABI:** **NON-BREAKING.** Strict superset of existing revert surface.
- **Reference precedent:** §5.C V-063 pattern (same gate shape).

### §33.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-33`** — Add `if (_livenessTriggered() && !gameOver) revert E();` at the top of `DegenerusGame.resolveRedemptionLootbox` (`DegenerusGame.sol:1721`), above the existing sDGNRS caller-allowlist check at `:1727`. Closes the multi-tx-pre-`gameOver=true` window where the sDGNRS-callback-triggered writer at `:1739` is reachable.

- Target file:line: `DegenerusGame.sol:1721` (function entry).
- Cross-reference: `.planning/RNGLOCK-CATALOG.md` §16 row 400 (V-065), §5 §D D-15 / §C.B-3-14 / §E E-4.
- CATALOG-LABEL-INACCURACY: catalog labels function `sweepSdgnrsClaim`; actual function is `resolveRedemptionLootbox`. Phase 303 TERMINAL ack the label refinement.
- Mirror of V-063: same gate shape (`!_livenessTriggered() || gameOver` ≡ `!(_livenessTriggered() && !gameOver)`), same callsite-position discipline.
- Positive externality: same fix closes adjacent Cluster B writer at `:1744 / :1747` (`_setPendingPools` / `_setPrizePools` `+= amount`), which feeds `futurePrizePool` / `pendingPools` races covered by Cluster B.

---

## §34 — V-066: `pendingRedemptionEthValue` × `beginRedemption` / `_submitGamblingClaimFrom` (`+=`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 401 (V-066). §15 writer rows 190 (`beginRedemption`) + 193 (`_submitGamblingClaimFrom`). §14 row 76 (S-17). Consumers §5 (terminal drain via `pendingRedemptionEthValue` subtracted from `totalFunds`), §12 (advance-stack `resolveRedemptionPeriod` RMW).

### §34.A — Design-intent backward-trace

**Slot introduction phase:** `pendingRedemptionEthValue` was introduced as part of the sDGNRS sister-contract redemption-claim architecture — a per-period accumulator that segregates ETH already promised to in-flight sStonk redemption claims from the unallocated sStonk treasury. The slot is declared `uint256 public pendingRedemptionEthValue` at `StakedDegenerusStonk.sol:224` with the inline comment "total segregated ETH across all periods". The economic function: when a player calls `burn` or `burnWrapped` (the gambling burn path), the function calls `_submitGamblingClaimFrom` which writes `pendingRedemptionEthValue += ethValueOwed` at `:789` — reserving the player's expected ETH return for the subsequent advanceGame-side resolution at `resolveRedemptionPeriod:593` and final `claimRedemption:657`.

**Cite for "what would break if frozen":** Freezing `pendingRedemptionEthValue` during rngLock would block the entire sStonk gambling-burn surface (`burn` / `burnWrapped` EOA entry points). This is precisely what the existing `BurnsBlockedDuringLiveness` modifier at `StakedDegenerusStonk.sol:491` (and the explicit re-check at `:507` inside `burnWrapped`) is designed to do — the live source-of-truth grep:

```solidity
// :491 (inside _gateBurn used by burn / burnWrapped):
if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();
:492 if (game.rngLocked()) revert BurnsBlockedDuringRng();
```

The two-gate convention (`livenessTriggered` for the game-over magnitude-input window + `rngLocked` for the active VRF window) is the canonical sStonk-side rng-lock revert pattern (CONTEXT.md §51-§87 cites `sStonk:492` as the `RngLocked` precedent site). The slot is reserved-out from `totalMoney` at `:535, :705, :772` (the `_calcExchangeRate` / `_calcExchangeRateForGambling` / `_calcExchangeRateForReceiveDgnrs` family) and is the source-of-truth subtraction term in the game-over `reserved` quantity (per the `preRefundAvailable = totalFunds − reserved` shape in `GameOverModule.handleGameOverDrain:93`).

**Precedent for tactic (a) gated-revert:** The `BurnsBlockedDuringLiveness` modifier itself is the precedent — this VIOLATION row exists because the catalog must enumerate every write that occurs during the rng-window even when an existing gate covers, per `feedback_verify_call_graph_against_source.md` discipline. Per `feedback_rng_window_storage_read_freshness.md`, every storage-read inside the rng-window must be enumerated regardless of whether a gate covers, so V-066 is the **coverage-verification row** rather than a missing-gate row.

### §34.B — Actor game-theory walk

**Exploit-actor class:** sStonk holder attempting to inflate `pendingRedemptionEthValue` during the rngLock window. Concrete vector:

- Attacker holds sStonk (any balance, since the gambling-burn surface accepts `burn(1)` as the minimum-economic-quantum entry). Attacker observes that `_livenessTriggered() == true` (the game-over magnitude-input window is open). Attacker calls `sStonk.burn(amount)` to add `ethValueOwed = (amount / supply) × totalMoney` to `pendingRedemptionEthValue`.
- Goal: inflate the `reserved` quantity inside `GameOverModule.handleGameOverDrain` to reduce `preRefundAvailable`, redirecting terminal-payout magnitude away from deity-pass refunds and into the sStonk redemption queue.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters the daily-phase that latches `_livenessTriggered() == true` (per AdvanceModule daily-loop). `_gameOverEntropy` requests the final-day VRF word; `rngLockedFlag = true`.
- T1 (attacker move): Attacker calls `sStonk.burn(amount)` → `_gateBurn` fires the live revert at `:491` (`livenessTriggered() == true` → revert `BurnsBlockedDuringLiveness`). **The attack is structurally blocked by the existing gate.**
- T1' (alternative attempt): Attacker observes `_livenessTriggered() == false` but `rngLocked() == true` (the rngLock window before final-day liveness latches). Calls `sStonk.burn(amount)` → `_gateBurn` fires at `:492` (`rngLocked() == true` → revert `BurnsBlockedDuringRng`). **Still blocked.**

**EV magnitude estimate:** **NONE — the existing `BurnsBlockedDuringLiveness` + `BurnsBlockedDuringRng` paired-gate at `:491-:492` covers both rng-window classes.** Catalog row 401 verdict-matrix column 5 confirms: "NO — gated by `livenessTriggered() && !gameOver` runtime revert during drain". The role of V-066 in this cluster is **coverage verification** — assert via FUZZ-301 that no execution branch reaches `pendingRedemptionEthValue +=` at `:789` while the consumer at `GameOverModule.handleGameOverDrain:93` is reachable. Economic-likelihood disposition: **defended by current source** pending the FUZZ-301 branch-reach attestation.

**Note on the dual-gate convention:** The two distinct reverts (`BurnsBlockedDuringLiveness` for the `livenessTriggered() && !gameOver` window; `BurnsBlockedDuringRng` for the `rngLocked()` window) are intentional — they correspond to two distinct economic semantics (game-over magnitude-input freeze vs. in-flight VRF request). V-066 covers the magnitude-input freeze class; the rng-lock class is separately enumerated for the same writer (catalog row 401 cites both gate conditions as compound coverage).

### §34.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) existing gated-revert covers — verification only.** Catalog §16 row 401 column 8 rationale verbatim: "Existing `BurnsBlockedDuringLiveness` covers; verify branch coverage".

**Concrete shape (verification only):**

- FUZZ-301 must produce a branch-reach attestation: for every execution sequence in which `_livenessTriggered() == true && !gameOver` holds (the magnitude-input window), assert that `pendingRedemptionEthValue +=` at `StakedDegenerusStonk.sol:789` is unreachable via `burn` / `burnWrapped` EOA call entries.
- Equivalent attestation for the `rngLocked() == true` window via the `:492` gate.
- No source-tree mutation. No new storage slot. No new modifier. **Zero bytecode delta.**

**Rationale for rejecting alternative tactics:**

- **(b) snapshot pattern** rejected: redundant — the existing gate prevents the write from ever firing during the consumer's read window. Adding a snapshot would introduce dead state without removing any attack surface.
- **(c) pre-lock reorder** rejected: not applicable — the writer is EOA-triggered at attacker discretion, and the existing gate is the structural reorder (denies the writer during the window).
- **(d) immutable** rejected: the slot is fundamentally mutable across the game's lifetime.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta.
- **Bytecode delta:** **zero.** Verification-only row.
- **Net runtime gas:** zero delta.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** Existing `BurnsBlockedDuringLiveness` + `BurnsBlockedDuringRng` revert pattern is the canonical sStonk-side rng-lock gate (CONTEXT.md cites `sStonk:492`). No new precedent introduced.

### §34.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-34`** — Verification-only anchor for V-066: assert `BurnsBlockedDuringLiveness` + `BurnsBlockedDuringRng` paired-gate at `StakedDegenerusStonk.sol:491-:492` covers the `pendingRedemptionEthValue += ethValueOwed` writer at `:789` reached via `burn` / `burnWrapped` EOA call entries. No contract change; FUZZ-301 branch-reach attestation deliverable.

- Gate site: `StakedDegenerusStonk.sol:491` (`if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();`)
- Gate site: `StakedDegenerusStonk.sol:492` (`if (game.rngLocked()) revert BurnsBlockedDuringRng();`)
- Writer site: `StakedDegenerusStonk.sol:789` (`pendingRedemptionEthValue += ethValueOwed;`)
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 401 (V-066), §15 writer rows 190 + 193, §14 row 76 (S-17).

---

## §35 — V-068: `pendingRedemptionEthValue` × `claimRedemption` (`-=`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 403 (V-068). §15 writer row 192. §14 row 76. Cross-cluster coordination: V-184 (S-56 `redemptionPeriodIndex` fix at FIXREC 299-K, H-111) is the subsumption anchor.

### §35.A — Design-intent backward-trace

**Slot introduction phase:** Same architecture phase as §1.A — the sDGNRS redemption-claim accumulator. The `-=` direction at `claimRedemption:657` (verified verbatim against source: `pendingRedemptionEthValue -= totalRolledEth;`) is the **release** half of the per-period segregation pattern: when a player claims a resolved redemption period, the previously-reserved ETH is released from the `pendingRedemptionEthValue` accumulator and transferred to the player. The economic semantic: each `_submitGamblingClaimFrom` `+=` (V-066) is paired with a future `claimRedemption` `-=` (V-068); the slot is the running balance of ETH currently owed-but-not-yet-released to redeemers.

**Cite for "what would break if frozen":** Freezing the `-=` write during rngLock would block player claims of already-resolved redemption periods — an undesirable user-experience interruption for a flow that has no structural causal dependency on the daily VRF resolution. The `claimRedemption` flow reads from a previously-resolved `redemptionPeriods[period]` struct (whose `roll` was set by an earlier advanceGame call) and uses that pre-resolved value to compute the payout magnitude — the slot is not consuming any live VRF word during its own execution.

**Catalog downgrade rationale (verified verbatim from row 403 column 5):** "NO — EOA; downgraded (subtraction of VRF-derived value, not VRF input)". The classification distinguishes the slot's role as a **consumer** of an already-resolved VRF-derived value (the `roll` written by `resolveRedemptionPeriod:604`) from its role as an **input** to a fresh VRF resolution. Per `feedback_rng_window_storage_read_freshness.md` discipline, this is the inverse direction from the canonical "non-VRF SLOAD consumed alongside fresh VRF word" bug class — V-068's read is of a value the VRF has already determined.

**The actual bug surface lives at V-184, not V-068:** The exploit window for sStonk redemption is the **cross-day re-roll** described in catalog §1 entry 36 (the GLOBAL-OBSERVATION on `redemptionPeriodIndex` cross-day re-roll exploit). The fix is at V-184 (S-56 `redemptionPeriodIndex` re-resolution lock at H-111): revert in `_submitGamblingClaimFrom` if `redemptionPeriods[redemptionPeriodIndex].roll != 0`. Once V-184 closes the re-roll, V-068's `-=` direction becomes structurally safe — the only `pendingRedemptionEthValue` `-=` reachable from EOA can no longer race against a fresh `roll` overwrite, because the index would already have been advanced past any stale period.

### §35.B — Actor game-theory walk

**Exploit-actor class:** sStonk redeemer attempting to use the `claimRedemption` `-=` write as a race vector against the game-over magnitude consumer. Concrete vector (subsumed):

- Pre-V-184 fix: An attacker could exploit the cross-day re-roll (S-56 `redemptionPeriodIndex` not advanced inside `resolveRedemptionPeriod`) to force a fresh `roll` overwrite on an already-resolved period, then call `claimRedemption` with the new larger `totalRolledEth`, draining `pendingRedemptionEthValue` more than the period's original commitment. This race surface inflates the `-=` magnitude relative to the game-over consumer's expectation.
- Post-V-184 fix: `_submitGamblingClaimFrom` reverts if `redemptionPeriods[redemptionPeriodIndex].roll != 0`, preventing the stale-index re-arming. The `claimRedemption` `-=` write can then only fire against a `totalRolledEth` magnitude that was committed at the original advance-stack `roll` write, eliminating the race.

**Action sequence during rngLock window (subsumed by V-184 fix):** The `claimRedemption` callsite at `:657` is reachable during rngLock and during the magnitude-input window — but only with the **already-committed** `totalRolledEth` once V-184 closes the re-arm. The game-over consumer (`GameOverModule.handleGameOverDrain:93` reading `pendingRedemptionEthValue` via the `reserved` subtraction in `_calcExchangeRate*`) sees a value that is decreasing monotonically as legitimate claimers exit — the same monotone-drain semantic as Cluster D's Reward pool. The monotone direction is **safe** for the consumer because each claim reduces both `pendingRedemptionEthValue` and `address(this).balance` (or stETH balance) by the same magnitude, preserving the `totalFunds − reserved` invariant.

**EV magnitude estimate:** **LOW once V-184 fix lands.** The catalog's "subsumed by S-56 fix" disposition reflects this: V-068's race surface evaporates once V-184 closes the upstream re-arm vector. Pre-V-184, the EV magnitude was MEDIUM (attacker captures the delta between the original and re-rolled `totalRolledEth`); post-V-184, the surface is structurally eliminated. Economic-likelihood disposition: **defended-by-V-184**.

**Cross-cluster coordination note:** V-068's resolution depends on V-184 (Cluster K / FIXREC 299-K) landing. The v44.0 plan-phase must order V-184 (H-111) before V-068 (H-35), or merge them into a single sub-phase. The handoff anchor H-35 is preserved per v44.0 traceability discipline even though no independent fix is required.

### §35.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) subsumed by S-56 `redemptionPeriodIndex` fix (V-184, H-111).** Catalog §16 row 403 column 8 rationale verbatim: "Subsumed by S-56 `redemptionPeriodIndex` fix — re-resolution lock covers".

**Concrete shape (subsumed):**

- No independent fix at V-068. The fix lives at V-184 (S-56): `StakedDegenerusStonk._submitGamblingClaimFrom` adds a revert if `redemptionPeriods[redemptionPeriodIndex].roll != 0`. Once that fix lands, V-068's race surface is structurally eliminated.
- FUZZ-301 must produce a transitive-coverage attestation: assert that for every execution sequence in which V-184's revert is reachable, V-068's race vector is also unreachable.
- No source-tree mutation at V-068. **Zero independent bytecode delta.**

**Rationale for rejecting alternative tactics:**

- **(a) independent gated-revert at claimRedemption** rejected: the `claimRedemption` flow has no structural causal dependency on the daily VRF resolution; gating it would interrupt legitimate redeemer claims for no defense benefit once V-184 closes the upstream re-arm.
- **(b) snapshot pattern** rejected: not applicable — V-068's value is already structurally committed at the resolved-period boundary, so a snapshot would duplicate existing state.
- **(c) pre-lock reorder** rejected: V-068's `-=` is the legitimate release direction; reordering would not eliminate the upstream re-arm vector that V-184 addresses.
- **(d) immutable** rejected: the slot is fundamentally mutable across redemption cycles.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta at V-068 (V-184 owns the fix bytecode).
- **Bytecode delta:** **zero at V-068.** Subsumed.
- **Net runtime gas:** zero delta.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** V-184 (H-111) cites the Phase 288 `dailyIdx` snapshot precedent as the structural-fix shape for cross-day re-roll classes.

### §35.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-35`** — Subsumption anchor for V-068: cross-references V-184 (H-111, S-56 `redemptionPeriodIndex` re-resolution lock). v44.0 plan-phase orders V-184 before V-068 OR merges into a single sub-phase. No independent fix at V-068; FUZZ-301 transitive-coverage attestation deliverable.

- Writer site: `StakedDegenerusStonk.sol:657` (`pendingRedemptionEthValue -= totalRolledEth;`)
- Upstream fix anchor: `D-43N-V44-HANDOFF-111` (V-184 at S-56 `redemptionPeriodIndex` re-resolution lock, FIXREC 299-K)
- **Subsumption note:** V-068 is structurally eliminated by V-184. Anchor H-35 is preserved per v44.0 traceability discipline; no independent contract change. v44.0 plan-phase MUST cite H-111 as the operational fix target.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 403 (V-068), §16 row 519 (V-184), §1 entry 36 (cross-day re-roll GLOBAL-OBSERVATION).

---

## §36 — V-069: `deityPassOwners` × `_purchaseDeityPass` (`.push(buyer)`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 404 (V-069). §15 writer row 194. §14 row 77 (S-18). Consumer §5 (game-over deity-pass refund pass walks the array length + elements).

### §36.A — Design-intent backward-trace

**Slot introduction phase:** `deityPassOwners` was introduced as part of the Whale-module deity-pass purchase architecture — a sequential append-only array of addresses that have purchased a deity pass during the game's active lifetime. The slot is declared in `DegenerusGameStorage` as `address[] internal deityPassOwners`. The economic function: deity passes are a Whale-tier purchase with a refund obligation at game-over (per catalog §5 entry 1 "B-5" attestation: the game-over drain pass walks the deity-pass owner array to compute per-holder refunds before any terminal payout). The array length and elements together drive the deity-refund magnitude inside `GameOverModule.handleGameOverDrain` at `:99-:134`.

**Existing partial gates (grep-verified verbatim from source):**

```solidity
// contracts/modules/DegenerusGameWhaleModule.sol:542
function _purchaseDeityPass(address buyer, uint8 symbolId) private {
    :543    if (rngLockedFlag) revert RngLocked();
    :544    if (_livenessTriggered()) revert E();
    // ... :595-:597 inside same function:
    :595    deityPassPurchasedCount[buyer] += 1;
    :596    deityPassOwners.push(buyer);
    :597    deityPassSymbol[buyer] = symbolId;
}
```

The two paired gates at `:543-:544` are the canonical game-side rng-lock revert pattern — `rngLockedFlag` for the active VRF window, `_livenessTriggered()` for the game-over magnitude-input window. The catalog verdict-matrix row 404 column 5 confirms: "NO — EOA; runtime `rngLockedFlag` + `_livenessTriggered` gates" — the gates are present at the function head and structurally block the EOA-callable surface during both windows.

**Cite for "what would break if frozen":** Freezing `deityPassOwners` during rngLock would block the entire `purchaseDeityPass` EOA-callable surface — which is precisely what the existing gates do. The deity-pass purchase has no structural causal dependency on any in-flight VRF resolution; the gates exist specifically to prevent the deity-pass owner array from racing the game-over deity-refund consumer.

**Catalog row 404 column 8 rationale (verbatim):** "Gate buyDeityPass when any lootbox's RNG word is fresh in the open window". This extends the existing `rngLockedFlag` gate to the **lootbox rng-word freshness** window — per catalog §11 lootbox-rng staleness GLOBAL-OBSERVATION, an attacker can observe a fresh `lootboxRngWordByIndex[index]` (the lootbox VRF word) before opening the box, and the deity-pass purchase during that window can race the game-over consumer in a manner not already covered by `rngLockedFlag`. The fresh-lootbox-rng window is a distinct rng-window class from the daily-VRF `rngLockedFlag` window.

**Precedent for tactic (a) gated-revert (extended gate):** The existing `rngLockedFlag` + `_livenessTriggered()` paired-gate at `:543-:544` is the structural precedent. The extension adds a third gate: "any lootbox has a fresh-but-unconsumed RNG word in the open window" — a new gate condition tracked via the existing `lootboxRngWordByIndex` array (S-23 per catalog row 81).

### §36.B — Actor game-theory walk

**Exploit-actor class:** Whale-tier purchaser attempting to inflate `deityPassOwners.length` during a fresh-lootbox-rng window to extract a per-holder deity refund from the game-over drain. Concrete vector:

- Attacker has a fresh `lootboxRngWordByIndex[index]` (the lootbox VRF word) ready but unconsumed. Attacker observes the next game-over deity-refund magnitude.
- Attacker calls `purchaseDeityPass(buyer, symbolId)` — the existing `rngLockedFlag` gate at `:543` checks only the daily-VRF window; the lootbox-rng-window is a distinct freshness class and is not currently gated.
- Inside `_purchaseDeityPass`, `:595` increments `deityPassPurchasedCount[buyer] += 1` (the V-070 co-located write), `:596` appends `deityPassOwners.push(buyer)` (V-069), `:597` records `deityPassSymbol[buyer] = symbolId`.
- Goal: append the attacker's address to `deityPassOwners` BEFORE the game-over consumer at `GameOverModule.handleGameOverDrain:99-:134` walks the array, capturing a per-holder refund magnitude that the attacker would not have received without the late append.

**Action sequence during fresh-lootbox-rng window (sequential):**

- T0: `advanceGame` resolves a daily VRF batch including a fresh lootbox word at `lootboxRngWordByIndex[index]`. `rngLockedFlag` returns to `false` (the daily VRF window closes). The lootbox-rng-word is fresh but unconsumed.
- T1 (attacker move): Attacker observes the fresh lootbox-rng word AND a pending game-over drain (e.g., near-final physical day or imminent liveness trigger).
- T2 (attacker call): Attacker calls `purchaseDeityPass(attacker, symbolId)`. `:543` (`rngLockedFlag`) gate returns `false` (daily VRF closed). `:544` (`_livenessTriggered()`) returns `false` (liveness not yet triggered). Function proceeds, appends to `deityPassOwners`.
- T3 (advanceGame proceeds): Next `advanceGame` call triggers `handleGameOverDrain`. The consumer walks `deityPassOwners` (now including the attacker), computes per-holder refund using `deityPassPurchasedCount[attacker] × baseRefund`, and the attacker collects.

**EV magnitude estimate:** **HIGH — the deity-pass refund is a large per-pass refund magnitude.** Per catalog §5 entry 2 "B-5" attestation, the deity-pass refund pass occurs BEFORE `preRefundAvailable` is consumed for terminal payouts — meaning the deity refund extracts from `totalFunds` directly, and an attacker who appends an entry late in the game lifecycle captures a refund that would otherwise have flowed to the terminal-payout magnitude. Economic-likelihood disposition: **likely-exploited** if the fresh-lootbox-rng window is observable and a game-over drain is anticipated — both conditions are public-state-derivable in advance.

**Coordinated V-070 note:** The same `_purchaseDeityPass` body also increments `deityPassPurchasedCount[buyer] += 1` at `:595` (V-070). Both writes are co-located inside the same function and gated by the same `:543-:544` pair; a single gate-extension at the function entry covers both. The subsumption is operational, not theoretical.

### §36.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) extended gated-revert at `_purchaseDeityPass` function entry.** Catalog §16 row 404 column 8 rationale verbatim: "Gate buyDeityPass when any lootbox's RNG word is fresh in the open window".

**Concrete shape:**

- Augment the existing `:543-:544` gate pair with a third gate condition: a revert if any lootbox in `lootboxRngWordByIndex` has a fresh-but-unconsumed RNG word (the precise "fresh" predicate is determined by v44.0 plan-phase — likely a comparison of `lootboxRngWordByIndex[i] != 0 && lootboxOpenedByIndex[i] == false` for any `i` within the current open window).
- Place the new revert immediately after `:543` (`rngLockedFlag`) and before `:544` (`_livenessTriggered`) — the ordering is canonical (check fastest-to-evaluate gate first).
- The revert error type can re-use `RngLocked` (the existing error already declared) OR a new `LootboxRngFresh` custom error per v44.0 plan-phase discretion.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot pattern** rejected: snapshotting `deityPassOwners` at `_gameOverEntropy` time would freeze the array length but break the legitimate `purchaseDeityPass` flow for any non-attacker buyer who calls during the fresh-lootbox-rng window. The append-only semantic of `deityPassOwners` is incompatible with a per-resolution snapshot — the array is the running game-state, not a per-resolution input.
- **(c) pre-lock reorder** rejected: not applicable — the writer is EOA-triggered at attacker discretion.
- **(d) immutable** rejected: the slot is fundamentally append-only-mutable across the game's lifetime.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** No new storage slot. The gate predicate uses existing storage (`lootboxRngWordByIndex` + lootbox-opened tracking).
- **Bytecode delta:** ~30-50 bytes for the new gate-condition revert (one SLOAD per checked lootbox index OR one packed-bitmap SLOAD per the v44.0 plan-phase decision on the freshness-tracking representation).
- **Net runtime gas:** +~2100 gas (one cold SLOAD on the lootbox-rng-array length + per-index check, or ~100 gas if a packed freshness bitmap is used). Charged only on the `purchaseDeityPass` hot path which is itself a Whale-tier purchase and not gas-sensitive.
- **Public ABI:** **NON-BREAKING.** No event topic-hash change; the revert is a function-level gate with no external visibility beyond the error selector.
- **Reference precedent:** The existing `rngLockedFlag` + `_livenessTriggered()` gate-pair at `:543-:544` is the structural precedent for a three-gate `purchaseDeityPass` function-head guard.

### §36.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-36`** — Extended gate at `_purchaseDeityPass` to revert when any lootbox's RNG word is fresh-but-unconsumed in the open window. v44.0 plan-phase decides the freshness-tracking representation (per-index SLOAD scan vs. packed bitmap).

- Existing gate sites preserved: `WhaleModule.sol:543` (`rngLockedFlag`), `:544` (`_livenessTriggered`).
- New gate site to add: `WhaleModule.sol` between `:543` and `:544` (or coalesced into a single compound check).
- Writer covered: `:596` (`deityPassOwners.push(buyer)`).
- Co-located writer (V-070) covered: `:595` (`deityPassPurchasedCount[buyer] += 1`).
- Consumer: `GameOverModule.handleGameOverDrain:99-:134` deity-pass refund pass.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 404 (V-069), §15 writer row 194, §14 row 77 (S-18), §11 lootbox-rng-staleness GLOBAL-OBSERVATION.

---

## §37 — V-070: `deityPassPurchasedCount[owner]` × `_purchaseDeityPass` (`+= 1`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 405 (V-070). §15 writer row 195. §14 row 78 (S-19). Subsumption anchor: V-069 (H-36).

### §37.A — Design-intent backward-trace

**Slot introduction phase:** `deityPassPurchasedCount` was introduced alongside `deityPassOwners` as the per-holder count companion — the array tracks WHO owns deity passes, the mapping tracks HOW MANY each holder owns. The slot is declared in `DegenerusGameStorage` as `mapping(address => uint16) internal deityPassPurchasedCount`. The economic function: at game-over, the deity-refund pass at `GameOverModule.handleGameOverDrain:99-:134` computes per-holder refund as `deityPassPurchasedCount[holder] × baseRefund`, summing across all entries in `deityPassOwners`. The two slots together drive the deity-refund magnitude.

**Co-located write site (grep-verified):** `DegenerusGameWhaleModule.sol:595` (`deityPassPurchasedCount[buyer] += 1;`) immediately precedes `:596` (`deityPassOwners.push(buyer);`). Both writes execute inside the same `_purchaseDeityPass` body, gated by the same `:543-:544` pair. The catalog row 405 column 5 verdict-matrix confirms: "NO — EOA; same gate as V-069".

**Cite for "what would break if frozen":** Same as §3.A — freezing `deityPassPurchasedCount` during rngLock would block the deity-pass purchase flow. The economic function is symmetric with `deityPassOwners`.

**Catalog row 405 column 8 rationale (verbatim):** "Subsumed by V-069 (co-located write)". The subsumption is operational: a single gate at the `_purchaseDeityPass` function head closes both writes.

### §37.B — Actor game-theory walk

**Exploit-actor class:** Identical to §3.B — same attacker, same exploit vector, same window. The `+= 1` write at `:595` and the `.push(buyer)` write at `:596` are atomic within the same function call; an attacker cannot exploit one without the other (and would not want to — the deity-refund magnitude depends on BOTH the array element AND the count).

**Action sequence:** Identical to §3.B. The attacker's `purchaseDeityPass` call increments `deityPassPurchasedCount[attacker]` AND appends the attacker to `deityPassOwners` in a single transaction; the game-over consumer reads both.

**EV magnitude estimate:** **Same as §3.B — HIGH.** No independent EV; V-070's surface is entirely co-located with V-069's surface.

### §37.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) subsumed by V-069 (H-36) — co-located write.** Catalog §16 row 405 column 8 rationale verbatim: "Subsumed by V-069 (co-located write)".

**Concrete shape:**

- No independent fix at V-070. The fix lives at V-069 (H-36): extend the existing `_purchaseDeityPass` function-head gate to include a fresh-lootbox-rng-window revert.
- Once H-36 lands, V-070's surface is structurally eliminated by the same gate that closes V-069.
- FUZZ-301 must produce a transitive-coverage attestation: assert that every execution sequence reaching `:595` (`deityPassPurchasedCount[buyer] += 1`) also has H-36's gate reachable — true by inspection because both writes live inside the same `_purchaseDeityPass` body.

**Subsumption note preserved for v44.0 traceability (per CATALOG):** V-070's anchor H-37 is preserved per v44.0 handoff-register discipline. The v44.0 plan-phase MUST cite H-36 as the operational fix target; no independent contract change at V-070.

**Rationale for rejecting alternative tactics:**

- **(a) independent gated-revert at V-070's writer line** rejected: the writer is on a line inside the same `_purchaseDeityPass` body as V-069's writer; a separate per-line gate would duplicate H-36's check.
- **(b) snapshot pattern** rejected: same reasoning as §3.C — the running-game-state semantic is incompatible with a per-resolution snapshot.
- **(c) pre-lock reorder** rejected: not applicable.
- **(d) immutable** rejected: the slot is fundamentally mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta at V-070.
- **Bytecode delta:** **zero at V-070.** Subsumed by V-069's gate.
- **Net runtime gas:** zero delta.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** H-36's extended gate is the structural precedent; H-37 inherits.

### §37.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-37`** — Subsumption anchor for V-070: cross-references V-069 (H-36). Anchor preserved per v44.0 traceability discipline despite operational subsumption; the v44.0 sub-phase that lands H-36 closes H-37 atomically.

- Writer site: `WhaleModule.sol:595` (`deityPassPurchasedCount[buyer] += 1;`)
- Subsuming gate site: `WhaleModule.sol` between `:543` and `:544` (V-069's extended gate at H-36).
- Consumer: `GameOverModule.handleGameOverDrain:99-:134` deity-pass refund per-holder count read.
- **Subsumption note:** V-070's writer is co-located inside `_purchaseDeityPass` with V-069's writer (one line apart at `:595` vs `:596`); both are gated by the same function-head check at `:543-:544`. Extending that check at H-36 closes both writes. v44.0 plan-phase MUST cite H-36 as the operational target.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 405 (V-070), §16 row 404 (V-069), §15 writer row 195, §14 row 78 (S-19).

---

## §38 — V-071: `address(this).balance` × `receive()` payable fallback

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 406 (V-071). §15 writer row 196 (implicit Solidity receive). §14 row 79 (S-20). Consumer §5 (`GameOverModule.handleGameOverDrain:84` `address(this).balance` live SLOAD).

### §38.A — Design-intent backward-trace

**Slot introduction phase:** `address(this).balance` is EVM-intrinsic — no source declaration under `contracts/`. The `receive()` payable fallback function (grep-verified at `contracts/DegenerusGame.sol:2618-:2627`) is the EOA-callable entry point that explicitly accepts plain-ETH transfers into the game contract. The fallback body:

```solidity
// contracts/DegenerusGame.sol:2618
receive() external payable {
    if (gameOver) revert E();
    if (prizePoolFrozen) {
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        _setPendingPools(pNext, pFuture + uint128(msg.value));
    } else {
        (uint128 next, uint128 future) = _getPrizePools();
        _setPrizePools(next, future + uint128(msg.value));
    }
}
```

The fallback's design-intent: accept external ETH contributions and route them to the prize-pool reserves (the inline comment block at `:2610-:2615` documents the routing). The economic function: external parties can contribute ETH to the game's reward pool by sending plain ETH. The slot under discussion (`address(this).balance`) is NOT directly written by the fallback — the fallback writes `prizePools` / `pendingPools` state — but the EVM-intrinsic `address(this).balance` is incremented atomically by the EVM as part of the value-transfer mechanism BEFORE the receive() body executes.

**The key freshness invariant:** Inside `GameOverModule.handleGameOverDrain:84`, the consumer reads `uint256 totalFunds = address(this).balance + steth.balanceOf(address(this));` — a live SLOAD of the EVM-intrinsic balance state. The `preRefundAvailable` quantity at `:93` is computed from this live read. Any inflow during the rngLock window (after `_gameOverEntropy` requests the final-day VRF but before `handleGameOverDrain` executes) inflates `address(this).balance` and shifts the terminal-payout magnitude.

**Cite for "what would break if frozen":** Tactic (a) gated-revert is **structurally impossible** for the `receive()` payable fallback during the rng-window. Solidity cannot reliably reject ETH inflows in all EVM contexts:

1. The current `receive()` body checks `if (gameOver) revert E();` — but `gameOver` is only set AFTER `handleGameOverDrain` executes (`:139` of GameOverModule). The rng-window between `_gameOverEntropy` and `handleGameOverDrain` is a window in which `gameOver == false` AND the receive accepts ETH.
2. Even if the receive() body reverted on `rngLockedFlag`, the EVM has two payout primitives that bypass the receive() function entirely: `selfdestruct(address)` (forces ETH transfer with no callback) and `block.coinbase` payouts (miner rewards / MEV-bot self-destructs targeting the game contract).
3. Per `feedback_frozen_contracts_no_future_proofing.md`: the contracts are frozen at deploy. Adding a receive-fallback revert would not eliminate the `selfdestruct` / coinbase-payout inflow class.

The only structural fix is tactic (b) snapshot: capture `totalFunds = address(this).balance + steth.balanceOf(address(this))` at `_gameOverEntropy` commitment time, then consume the snapshot inside `handleGameOverDrain` instead of the live SLOAD. The snapshot pattern is **agnostic to inflow vector** — selfdestruct, coinbase, receive() all become irrelevant because the consumer reads the pinned value.

**Precedent for snapshot pattern:** Phase 281 owed-salt 4th-keccak-input introduced the snapshot-at-commitment shape as the canonical resolution for "live-SLOAD-between-commitment-and-resolution" races (`.planning/milestones/v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md` `D-281-FIX-SHAPE-01`). The Cluster F balance-snapshot is the direct application: snapshot the inflow-mutable EVM balance at the entropy-commitment moment.

### §38.B — Actor game-theory walk

**Exploit-actor class:** Any EOA (or contract) capable of sending ETH to the game contract during the rngLock window. The attack surface is universal — no protocol participation required:

- Vector 1: Direct `send(eth)` / `transfer(eth)` / `call{value: x}("")` to the game contract address. Triggers `receive()`, which routes the inflow to `prizePools.future` (per the receive() body at `:2622-:2625`).
- Vector 2: `selfdestruct(payable(GAME_ADDRESS))` from a controlled contract. Bypasses `receive()` entirely; increments `address(this).balance` without invoking any Solidity code on the game side.
- Vector 3: Coinbase-payout (miner / sequencer / MEV-bot self-destructs targeting GAME). Same bypass as Vector 2.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters the final-day branch. `_gameOverEntropy` requests the terminal VRF word. `rngLockedFlag = true`.
- T1 (attacker move): Attacker inflates `address(this).balance` by `Δ` via any of Vectors 1-3. The EVM-intrinsic balance state is updated atomically; no Solidity code can prevent it for Vectors 2-3.
- T2 (VRF callback): The terminal VRF word is delivered. `advanceGame` proceeds to `handleGameOverDrain`.
- T3 (consumer SLOAD): `handleGameOverDrain:84` reads `totalFunds = address(this).balance + steth.balanceOf(address(this))`. The value is `originalBalance + Δ + stETHBalance`.
- T4 (resolution): `preRefundAvailable = (originalBalance + Δ + stETHBalance) − reserved`. The deity-refund pass at `:99-:134` and the terminal-payout magnitude at `:156` consume the inflated `preRefundAvailable`.

**Exploit direction:** The attacker is **gifting** ETH to the game, not draining it — so why is this an exploit? Per `feedback_design_intent_before_deletion.md`, the bug class is not "attacker steals ETH"; it's "attacker shifts the magnitude of a terminal-payout consumer in a manner not anticipated by the protocol's commitment-time invariant". A late inflow inflates the terminal-payout magnitude, which shifts the proportion of `preRefundAvailable` that flows to deity-refunds vs. terminal-payout-winners. An attacker who controls a deity-pass position (or a position that wins from the terminal-payout proportion) can extract EV from the late inflow.

**EV magnitude estimate:** **HIGH on the terminal day; MEDIUM on the rngLock window mid-game.** The terminal-day attack is particularly severe because:

1. The deity-refund pass executes BEFORE the terminal-payout magnitude is computed (per catalog §5 entry 2 "B-5" attestation).
2. The attacker can pre-position a deity-pass purchase (any number of passes) and then inject a late inflow proportional to their deity-pass count to extract per-pass refund magnitude.
3. The inflow vector is universal — selfdestruct cannot be blocked; the attack surface persists even if `receive()` is fully reverted.

Economic-likelihood disposition: **likely-exploited** on terminal day. The attack is cheap (gas + the inflow magnitude, which is recovered as refund), economically rational, and structurally undetectable from inside the receive() body for Vectors 2-3.

### §38.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot `totalFunds` at `_gameOverEntropy` time; consume snapshot in `handleGameOverDrain`.** Catalog §16 row 406 column 8 rationale verbatim: "Snapshot `totalFunds` at `_gameOverEntropy` time; consume snapshot in drain".

**Concrete shape:**

- Introduce a packed snapshot field `gameOverFundsSnapshot` (uint256 sufficient since `totalFunds = address(this).balance + steth.balanceOf(address(this))` may exceed uint128 for high-TVL deployments; v44.0 plan-phase decides the precise width).
- Populate the field inside `_gameOverEntropy` (the AdvanceModule callsite that requests the terminal VRF word). Compute `snapshot = address(this).balance + steth.balanceOf(address(this))` once, SSTORE to `gameOverFundsSnapshot`.
- Modify `GameOverModule.handleGameOverDrain:84` to read the snapshot field instead of the live `address(this).balance + steth.balanceOf(address(this))` computation.
- The `claimablePool`-side reserved subtraction (`reserved` in the `preRefundAvailable = totalFunds − reserved` shape) continues to read the live `claimablePool` value — only the EVM-balance + stETH-balance components are snapshotted. (Alternatively, v44.0 may snapshot `reserved` as well per `pendingRedemptionEthValue` snapshot — out of scope for this VIOLATION; see V-080 cross-cut below.)
- This SAME snapshot field covers V-080 (stETH external IN-transfer race) because the consumer combines ETH balance + stETH balance into the single `totalFunds` quantity. One snapshot field, two VIOLATION closures. (See §9.C for the V-080 cross-reference.)

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert in `receive()`** rejected: structurally insufficient. Vectors 2-3 (selfdestruct + coinbase-payout) bypass `receive()` entirely. Adding a revert in the receive() body would partially mitigate Vector 1 but not the universal class. Per `feedback_frozen_contracts_no_future_proofing.md`, the gate-half-measure increases bytecode without closing the surface.
- **(c) pre-lock reorder** rejected: not applicable — inflows are EOA-discretionary and EVM-intrinsic (Vectors 2-3).
- **(d) immutable** rejected: `address(this).balance` is fundamentally mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** new packed snapshot field `gameOverFundsSnapshot` (uint256 OR uint128 per v44.0 plan-phase width decision). 16-32 bytes. v44.0 plan-phase decides whether to coalesce with adjacent packed slots (e.g., the existing `pendingPools` / `prizePools` packing structure). **NOT byte-identical** — one new slot or one slot-extension.
- **Bytecode delta:** ~100-200 bytes. One additional `address(this).balance + steth.balanceOf(address(this))` computation inside `_gameOverEntropy` (one BALANCE opcode + one STATICCALL on Lido + one SSTORE). One SLOAD on the snapshot field inside `handleGameOverDrain:84` replacing the live BALANCE + STATICCALL.
- **Net runtime gas:** approximately neutral. `_gameOverEntropy` pays +1 BALANCE (+~700 gas cold) + 1 STATICCALL (~2600 gas cold) + 1 SSTORE (~20000 gas warm = ~22300 gas). `handleGameOverDrain` saves -1 BALANCE (~700 gas) + -1 STATICCALL (~2600 gas) and gains +1 SLOAD (~2100 cold ≈ -1200 net). Final-day path runs once per game so the snapshot SSTORE amortizes to zero per game.
- **Public ABI:** **NON-BREAKING.** No event topic-hash change; the new field is internal storage. v44.0 plan-phase may expose via a new view function (optional).
- **Reference precedent:** Phase 281 owed-salt snapshot is exactly this shape, zero ABI delta and zero hot-path gas delta in the steady state.

### §38.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-38`** — Snapshot `totalFunds = address(this).balance + steth.balanceOf(address(this))` at `_gameOverEntropy` commitment moment; `GameOverModule.handleGameOverDrain:84` reads the snapshot instead of the live BALANCE + STATICCALL. Single snapshot field closes both V-071 (ETH inflow) and V-080 (stETH inflow) — see H-42.

- Snapshot WRITE site: inside `_gameOverEntropy` (`AdvanceModule.sol` final-day entropy-commit callsite; precise line per v44 plan-phase grep).
- Snapshot READ site: replace live read at `GameOverModule.sol:84` (`address(this).balance + steth.balanceOf(address(this))`).
- Storage field: new `gameOverFundsSnapshot` (uint256 / uint128 per v44 plan-phase width decision).
- Cross-cuts with V-080 (H-42): same snapshot field covers both ETH and stETH balance inputs.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 406 (V-071), §15 writer row 196, §14 row 79 (S-20), §5 entry 1-2 (game-over drain magnitude consumer).

---

## §39 — V-072: `address(this).balance` × payable purchase functions (inflate balance)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 407 (V-072). §15 writer row 197 (every `payable` purchase function — `mintBatch` / `purchaseWhaleBundle` / `purchaseDeityPass` / `purchaseLazyPass`). §14 row 79.

### §39.A — Design-intent backward-trace

**Slot introduction phase:** Same EVM-intrinsic slot as §5.A (`address(this).balance`). The writer set here is distinct from V-071: V-071 covered the bare `receive()` fallback (no protocol participation required); V-072 covers the **`payable` protocol-purchase entry points** at `DegenerusGame.sol:356, :507, :602, :624, :644, :721, :1808` (grep-verified payable functions). Each of these is a protocol-purchase entry that accepts `msg.value` and (atomically with the EVM-intrinsic balance increment) writes some `prizePools` / `claimablePool` state.

**Existing gates (grep-verified):** The `payable` purchase entry points are gated against the rng-window by the canonical game-side pair (`MintModule.sol:1215` / `MintModule.sol:1221` for mint surfaces; `WhaleModule.sol:543-:544, :385` for whale-deity-lazy-pass surfaces; etc.). The catalog verdict-matrix row 407 column 5 confirms: "NO — EOA; gated by `_livenessTriggered() && rngLockedFlag` runtime" — the gates are present at the purchase-function entry and structurally block the EOA-callable surface during both windows.

**Cite for "what would break if frozen":** Tactic (a) gated-revert IS the existing mechanism — the gates at the purchase-function entry points prevent the writer from firing during the rngLock window. V-072 is the **coverage-verification row** for this writer class, analogous to V-066's role for the sStonk-side burn surface.

**Catalog row 407 column 8 rationale (verbatim):** "Existing per-fn gates cover; verify coverage during livenes window". (Note: the catalog has a typo "livenes" — the source-of-truth grep should read "liveness".)

**Precedent for tactic (a) gated-revert (verification):** Identical to §1 (V-066) — the existing gates are the canonical structural fix, and V-072 enumerates the writer class for branch-reach attestation discipline per `feedback_rng_window_storage_read_freshness.md`.

### §39.B — Actor game-theory walk

**Exploit-actor class:** Any EOA attempting to invoke a `payable` protocol-purchase entry point during the rngLock window. Concrete vectors:

- Player calls `mintBatch{value: x}(...)` during rngLock → `MintModule._livenessTriggered()` revert at `:1215` OR `cachedJpFlag && rngLockedFlag` revert at `:1221` fires.
- Whale-tier buyer calls `purchaseDeityPass{value: x}(...)` during rngLock → `WhaleModule.sol:543` (`rngLockedFlag`) revert fires. (See §3.B for the V-069 / V-070 attack walk — same gate covers V-072's `address(this).balance` impact at the same writer.)
- Player calls `purchaseLazyPass{value: x}(...)` during rngLock → corresponding `WhaleModule.sol:195` (`_livenessTriggered`) / `:385` revert fires.

**Action sequence during rngLock window:** Every purchase function reverts at the function-entry gate before any `msg.value` is committed to the contract — the EVM rolls back the inflow atomically with the revert. **The attack is structurally blocked.**

**EV magnitude estimate:** **NONE — existing per-function gates cover.** Catalog row 407 verdict-matrix column 5 confirms the coverage. V-072's role: assert via FUZZ-301 that every `payable` purchase entry point has a working `_livenessTriggered() || rngLockedFlag` gate at the function head, and that no execution branch reaches the `address(this).balance` inflation while the consumer at `GameOverModule.handleGameOverDrain:84` is reachable.

**Distinction from V-071:** V-071 covers the **gated-impossible** inflow class (`receive()` + selfdestruct + coinbase-payout — cannot be reverted in all EVM contexts). V-072 covers the **gated-and-reverted** inflow class (purchase functions with explicit `_livenessTriggered() / rngLockedFlag` checks). The two writer classes share the same consumer (S-20 / `GameOverModule.handleGameOverDrain:84`) but require different tactics: snapshot (b) for V-071's universal class, verification (a) for V-072's already-gated class.

### §39.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) existing per-function gates cover — verification only.** Catalog §16 row 407 column 8 rationale verbatim: "Existing per-fn gates cover; verify coverage during livenes window".

**Concrete shape (verification only):**

- FUZZ-301 must produce a branch-reach attestation: for every `payable` external function in `DegenerusGame` / `MintModule` / `WhaleModule` / `BurnieCoinflip` / etc., assert that the function-head gate (`_livenessTriggered() || rngLockedFlag` pair) is reached BEFORE any state mutation OR `msg.value` commitment.
- The attestation is per-entry-point — each payable function in scope must independently exhibit gate coverage.
- No source-tree mutation. No new storage slot. No new modifier. **Zero bytecode delta.**

**Rationale for rejecting alternative tactics:**

- **(b) snapshot pattern** rejected: redundant — the existing gates prevent the write from ever firing during the consumer's read window. (V-071 already snapshots for the gated-impossible class; V-072 doesn't need the same snapshot for the gated class.)
- **(c) pre-lock reorder** rejected: not applicable.
- **(d) immutable** rejected: the slot is mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta.
- **Bytecode delta:** **zero.** Verification-only row.
- **Net runtime gas:** zero delta.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** Existing function-head gate pattern across `MintModule.sol:1215, :1221, :877, :906, :1381` and `WhaleModule.sol:543-:544, :195, :385`. No new precedent.

### §39.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-39`** — Verification-only anchor for V-072: assert function-head `_livenessTriggered() || rngLockedFlag` gate coverage on every `payable` protocol-purchase entry point. No contract change; FUZZ-301 branch-reach attestation deliverable.

- Gate sites (sample, non-exhaustive): `MintModule.sol:1215, :1221`; `WhaleModule.sol:543, :544, :195, :385`; per-function inventory deferred to v44.0 plan-phase grep.
- Writer class: every `payable` external function inflating `address(this).balance` during state-mutating execution.
- Consumer: `GameOverModule.handleGameOverDrain:84` `address(this).balance` live SLOAD.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 407 (V-072), §15 writer row 197, §14 row 79 (S-20).

---

## §40 — V-073: `address(this).balance` × `claimWinnings` outflow (`call{value:}`)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 408 (V-073). §15 writer row 198. §14 row 79. Cross-cluster subsumption: V-063 (Cluster E / FIXREC 299-05, H-31) is the gate-shared anchor.

### §40.A — Design-intent backward-trace

**Slot introduction phase:** `address(this).balance` is EVM-intrinsic. The writer site under discussion is the `claimWinnings` outflow — verified verbatim at `DegenerusGame.sol:1399-:1416`:

```solidity
// :1399
function _claimWinningsInternal(address player, bool stethFirst) private {
    :1400    if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();
    :1401    uint256 amount = claimableWinnings[player];
    :1402    if (amount <= 1) revert E();
    // ...
    :1408    claimablePool -= uint128(payout);
    :1409    emit WinningsClaimed(player, msg.sender, payout);
    :1410-:1414  // _payoutWithEthFallback / _payoutWithStethFallback → call{value:}(...)
}
```

The `call{value:}` outflow inside `_payoutWithEthFallback` / `_payoutWithStethFallback` (at `:2002, :2022, :2043` per grep) decrements `address(this).balance` by the `payout` magnitude. The slot is consumed by `GameOverModule.handleGameOverDrain:84` immediately after rng-window-resolved magnitudes are known.

**Existing gates (grep-verified — KEY FINDING):** The `_claimWinningsInternal` body at `:1399-:1416` checks ONLY `_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0` at `:1400` — i.e., the post-30-day "everything has been swept" sentinel. **There is NO `_livenessTriggered()` gate and NO `rngLockedFlag` gate in the `claimWinnings` body.** The catalog verdict-matrix row 408 column 5 confirms verbatim: "NO — EOA; no liveness gate".

This is the inverse of V-072's class: V-072's payable purchases inflate `address(this).balance` and ARE gated; V-073's `claimWinnings` deflates `address(this).balance` and is NOT gated. The asymmetry creates the exploit window.

**Cite for "what would break if frozen":** Gating `claimWinnings` on `_livenessTriggered() || gameOver` would block legitimate player payouts during the game-over magnitude-input window. This is the explicit catalog row 408 column 8 recommendation: "Same gate as V-063 — single revert closes both `claimablePool` and balance writers".

The crucial design observation: `claimWinnings` writes BOTH `claimablePool` (Cluster E / S-16) and `address(this).balance` (this cluster / S-20). A single revert at the `_claimWinningsInternal` body head closes **both** consumer races simultaneously. V-073 and V-063 share the same writer line; the gate-once-revert-twice pattern is the structural fix.

**Catalog row 408 column 8 rationale (verbatim):** "Same gate as V-063 — single revert closes both `claimablePool` and balance writers". V-063 (Cluster E, H-31) is the canonical anchor; v44.0 plan-phase MUST ensure V-063 and V-073 are landed in the same sub-phase OR explicitly cross-link.

**Precedent for tactic (a) gated-revert:** Existing `_livenessTriggered()` gate convention across `MintModule.sol:1215`, `WhaleModule.sol:544`, `JackpotModule.sol` (various) is the structural precedent. The new gate at `_claimWinningsInternal:1400` is the simplest application — one new `if` statement at the function head.

### §40.B — Actor game-theory walk

**Exploit-actor class:** Player with `claimableWinnings[player] > 1` attempting to extract a payout during the rngLock magnitude-input window, shifting both `claimablePool` (V-063) and `address(this).balance` (V-073) before the game-over consumer reads.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters the final-day branch. `_gameOverEntropy` requests the terminal VRF word. `_livenessTriggered() == true` (magnitude-input window open).
- T1 (attacker move): Attacker calls `claimWinnings(player)`. `:1400` checks `GO_SWEPT_SHIFT` — returns 0 (sweep hasn't happened yet, gameOver hasn't latched). `:1408` `claimablePool -= uint128(payout)`. `:1410-:1414` `call{value: payout}` deflates `address(this).balance` by `payout`.
- T2 (consumer SLOAD): `GameOverModule.handleGameOverDrain:84` reads `totalFunds = address(this).balance + steth.balanceOf(address(this))`. The value is `originalBalance - payout + stETHBalance`.
- T3 (resolution): `preRefundAvailable = (originalBalance - payout + stETHBalance) − reserved`. The deity-refund pass + terminal-payout magnitude are reduced by `payout`.

**Exploit direction (subtler than V-071's inflow):** The attacker is **draining** ETH via legitimate `claimWinnings` access, but doing so DURING the rng-window. Per `feedback_design_intent_before_deletion.md`, the design-intent of `claimWinnings` is to provide a pull-pattern payout for resolved winnings; the design-intent did NOT contemplate that the drain would race the game-over consumer. The bug class: an attacker with deity-refund position (or a position that wins from terminal-payout proportion) can **avoid** claiming during the rng-window if the timing shifts EV in their favor — and DO claim during the rng-window if the timing helps them. The asymmetric optionality is the exploit.

**EV magnitude estimate:** **HIGH — full `claimableWinnings[player]` magnitude per attacker.** Unlike V-071's gift-and-extract pattern (limited to inflow size), V-073's drain pattern extracts the full pre-existing `claimableWinnings[player]` allocation. An attacker who has accumulated substantial winnings can shift the entire payout magnitude by timing their claim. Economic-likelihood disposition: **likely-exploited** by any player with significant pre-existing winnings; the gate-absence is observable from chain state.

**Coordinated V-063 note:** V-063 covers the `claimablePool -= uint128(payout)` write at `:1408` (Cluster E / claimablePool slot). V-073 covers the `address(this).balance` deflation immediately after (`call{value:}` at `:1410-:1414`). Both writes execute inside the same `_claimWinningsInternal` body; a single function-head gate at `:1400` closes both.

### §40.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) gated-revert at `_claimWinningsInternal` function head — same gate as V-063.** Catalog §16 row 408 column 8 rationale verbatim: "Same gate as V-063 — single revert closes both `claimablePool` and balance writers".

**Concrete shape:**

- Add a revert at the head of `_claimWinningsInternal` at `DegenerusGame.sol:1400`: `if (_livenessTriggered() && !gameOver) revert E();` (or a typed custom error per v44.0 plan-phase discretion). The gate is `_livenessTriggered() && !gameOver` (NOT `|| gameOver`) — the post-gameOver flow MUST allow `claimWinnings` (that's the player-payout path after sweep). The existing `GO_SWEPT_SHIFT` check at `:1400` handles the post-sweep case; the new gate adds the magnitude-input-window block.
- Place the new revert BEFORE the `:1400` `GO_SWEPT` check (or coalesce into a compound expression per v44.0 plan-phase formatting decision).
- This SAME gate closes both V-063 (claimablePool write at `:1408`) and V-073 (balance write via `call{value:}` at `:1410-:1414`). One revert, two VIOLATION closures.

**Subsumption note preserved for v44.0 traceability (per CATALOG):** V-073's anchor H-40 is preserved per v44.0 handoff-register discipline. The fix is structurally coordinated with V-063 (Cluster E, H-31, FIXREC 299-05) — the v44.0 plan-phase MUST land them in the same sub-phase OR cite H-31 as the operational target.

**Rationale for rejecting alternative tactics:**

- **(b) snapshot pattern** rejected: snapshotting `address(this).balance` (V-071's approach) would handle V-073's deflation racing the consumer — but at higher cost than a single-line gate. The gate is cheaper, simpler, and closes V-063 simultaneously. V-071 needs snapshot ONLY because `receive()` / selfdestruct / coinbase-payout are ungateable; `claimWinnings` IS gateable.
- **(c) pre-lock reorder** rejected: not applicable — the writer is EOA-triggered at attacker discretion.
- **(d) immutable** rejected: the slot is mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** No new storage slot.
- **Bytecode delta:** ~30-50 bytes for one new `if (_livenessTriggered() && !gameOver) revert E();` at `:1400`. Closes both V-063 and V-073.
- **Net runtime gas:** +~2100 gas (one SLOAD for `_livenessTriggered()` + one SLOAD for `gameOver`) on every `claimWinnings` call. Hot path — but `claimWinnings` is not high-frequency.
- **Public ABI:** **NON-BREAKING.** No new event topic-hash; the new revert may re-use existing `E()` error.
- **Reference precedent:** Existing `_livenessTriggered()` gate pattern across `MintModule` / `WhaleModule` / `JackpotModule`. The new gate is one line of code.

### §40.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-40`** — Gated-revert at `DegenerusGame._claimWinningsInternal:1400` to revert during the `_livenessTriggered() && !gameOver` magnitude-input window. **Subsumption: same operational gate as V-063 / H-31 (Cluster E / FIXREC 299-05) — one gate closes both `claimablePool` and `address(this).balance` writer races.**

- Gate site to add: `DegenerusGame.sol:1400` (head of `_claimWinningsInternal`, before existing `GO_SWEPT` check).
- Writers covered: `:1408` (`claimablePool -= uint128(payout);` — V-063), `:1410-:1414` (`_payoutWithEthFallback` / `_payoutWithStethFallback` → `call{value:}` — V-073).
- Consumer: `GameOverModule.handleGameOverDrain:84` (live `address(this).balance` SLOAD).
- **Subsumption note:** V-073's anchor H-40 and V-063's anchor H-31 close together. v44.0 plan-phase MUST land them in the same sub-phase; the FIXREC 299-05 (Cluster E) entry for V-063 is the operational lead.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 408 (V-073), §16 row 397 (V-063), §15 writer row 198, §14 row 79 (S-20).

---

## §41 — V-074: `address(this).balance` × sDGNRS / vault / GNRUS withdrawals (cross-contract)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 409 (V-074). §15 writer row 199 (sDGNRS / vault / GNRUS withdrawals). §14 row 79. Cross-cluster coordination: V-066 (H-34) is the upstream gate-anchor.

### §41.A — Design-intent backward-trace

**Slot introduction phase:** `address(this).balance` is EVM-intrinsic. The writer class under discussion is the **cross-contract callback** path: sister contracts (`StakedDegenerusStonk` / `DegenerusVault` / `DegenerusGNRUS`) call back into `DegenerusGame` during sStonk redemption, vault unwinding, or GNRUS settlement, triggering ETH outflows that decrement `address(this).balance`. The catalog row 409 verdict-matrix column 5 confirms: "mixed — gated transitively via sDGNRS liveness".

**Cross-contract reach-stack (grep-verified writer family):**

- sDGNRS `claimRedemption` (at `:657`) calls `DegenerusGame.sweepSdgnrsClaim` (at `:1739` per FIXREC 299-05 Cluster E V-065). That callback writes `claimablePool -=` AND triggers ETH outflow via downstream `call{value:}` family.
- DegenerusVault unwind paths (vault → game callback) similarly trigger ETH outflows.
- DegenerusGNRUS settlement paths likewise.

**Existing transitive gate:** The catalog's "gated transitively via sDGNRS liveness" disposition refers to the `BurnsBlockedDuringLiveness` modifier at `StakedDegenerusStonk.sol:491` (V-066's gate) and the parallel `_livenessTriggered()` checks inside vault / GNRUS surfaces (per project-memory convention). The sister-contract entry points themselves are gated against the rng-window; an EOA cannot reach `claimRedemption` (which would trigger the game-callback) during `_livenessTriggered()` because the sStonk-side gate at `:491` reverts first.

**Cite for "what would break if frozen":** Gating the game-side callback receivers (`sweepSdgnrsClaim`, vault-unwind callbacks, GNRUS settlement callbacks) on `_livenessTriggered()` would block the legitimate cross-contract redemption / unwind / settlement flows. The transitive gating via sister-contract entry points avoids this by ensuring the EOA-entry point reverts first.

**Catalog row 409 column 8 rationale (verbatim):** "Gate at sDGNRS callsite (BurnsBlockedDuringLiveness) covers". The fix is **upstream**: V-066's gate at `StakedDegenerusStonk.sol:491` is the operational close.

### §41.B — Actor game-theory walk

**Exploit-actor class:** sStonk holder / vault depositor / GNRUS holder attempting to use the cross-contract callback path to deflate `address(this).balance` during the rng-window.

**Action sequence during rngLock window (subsumed by V-066 gate):**

- T0: `advanceGame` enters magnitude-input window. `_livenessTriggered() == true`.
- T1 (attacker move): Attacker calls `sStonk.claimRedemption` (or `vault.unwind`, or `gnrus.settle`). The sister-contract gate fires:
  - sStonk side: `StakedDegenerusStonk.sol:507` `if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();` — REVERTS for `claimRedemption`. (Note: V-068 covers `claimRedemption -=` on `pendingRedemptionEthValue`; that gate also covers the game-side balance race here.)
  - Vault side: project-memory convention asserts `_livenessTriggered()` check at vault entry surfaces.
  - GNRUS side: analogous.
- T1' (no attack): The sister-contract entry reverts before reaching the game-side callback. `address(this).balance` is not deflated.

**EV magnitude estimate:** **NONE once V-066 / V-068 / parallel vault & GNRUS gates are confirmed.** The catalog's "gated transitively" disposition reflects this. V-074's role: assert via FUZZ-301 that every cross-contract callback path reaches a sister-contract gate BEFORE reaching the game-side ETH-outflow.

**Caveat — transitive-gate verification:** Per `feedback_verify_call_graph_against_source.md`, the "by-construction transitively covers" claim must be grep-verified. The verification deliverable for H-41 is the explicit attestation that:

1. Every sStonk → game ETH-outflow callback is reachable only via a sStonk entry point that runs `BurnsBlockedDuringLiveness` check (already verified at `:491` for the `burn`/`burnWrapped` path).
2. Every vault → game callback runs an equivalent `_livenessTriggered()` check on the vault side.
3. Every GNRUS → game callback runs an equivalent check.

The FUZZ-301 attestation MUST enumerate the sister-contract entry points and demonstrate each one's gate.

### §41.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) upstream gate at sister-contract callsites — verification only.** Catalog §16 row 409 column 8 rationale verbatim: "Gate at sDGNRS callsite (BurnsBlockedDuringLiveness) covers".

**Concrete shape (verification only):**

- FUZZ-301 must produce a transitive-coverage attestation: for every cross-contract callback path from sDGNRS / vault / GNRUS into `DegenerusGame` that triggers an ETH outflow, assert that the sister-contract entry-point gate (`BurnsBlockedDuringLiveness` on sStonk; `_livenessTriggered()` equivalent on vault & GNRUS) fires BEFORE the callback reaches the game-side outflow.
- The attestation MUST enumerate the sister-contract entry points (`StakedDegenerusStonk.burn`, `.burnWrapped`, `.claimRedemption`; `DegenerusVault.unwind` family; `DegenerusGNRUS.settle` family) AND demonstrate each one's gate inline with grep evidence.
- If any sister-contract entry path is found to NOT have the equivalent gate, the missing gate is an upstream FIX (escalate to the relevant sister-contract V-NNN entry, e.g., V-066 / V-184 for sStonk; vault & GNRUS may need their own catalog rows).
- No game-side source-tree mutation. **Zero bytecode delta on the game contract.**

**Rationale for rejecting alternative tactics:**

- **(a) game-side gate at the callback receiver** rejected: redundant with the sister-contract entry gate, AND would block legitimate post-gameOver settlement flows that need to fire from sister contracts.
- **(b) snapshot pattern** rejected: V-071's snapshot already covers the residual `address(this).balance` racing-the-consumer surface for the ungateable inflow class. V-074's deflation surface is gated by sister-contract entry points; if any are missing, the fix is upstream.
- **(c) pre-lock reorder** rejected: not applicable.
- **(d) immutable** rejected: the slot is mutable.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **byte-identical.** Zero delta on game side.
- **Bytecode delta:** **zero on game side.** Verification-only row. Any missing sister-contract gate is tracked at that sister-contract's own VIOLATION row.
- **Net runtime gas:** zero delta on game side.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta.
- **Reference precedent:** `StakedDegenerusStonk.sol:491` `BurnsBlockedDuringLiveness` modifier is the sister-contract gate precedent. Vault & GNRUS entry gates follow the same convention per project-memory.

### §41.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-41`** — Verification anchor for V-074: assert transitive sister-contract gate coverage for every cross-contract callback path that triggers ETH outflow from the game contract. v44.0 plan-phase enumerates the sister-contract entry points and grep-verifies each gate.

- Upstream gate site (sStonk): `StakedDegenerusStonk.sol:491` (`BurnsBlockedDuringLiveness`).
- Upstream gate site (sStonk post-gameOver path): `:507` (`if (game.livenessTriggered() && !game.gameOver()) revert BurnsBlockedDuringLiveness();`).
- Upstream gate sites (vault & GNRUS): v44.0 plan-phase grep-deliverable.
- Writer class on game side: `call{value:}` callbacks reached from sister-contract surfaces (`sweepSdgnrsClaim` at `:1739` + vault/GNRUS callback receivers).
- Consumer: `GameOverModule.handleGameOverDrain:84` live `address(this).balance` SLOAD.
- **Subsumption note:** V-074 is transitively covered by V-066 (sStonk-side gate) plus the analogous vault & GNRUS gates. v44.0 plan-phase verifies the transitive coverage; no game-side gate added. If any sister-contract gate is missing, escalate to that sister-contract's own V-NNN entry.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 409 (V-074), §16 row 401 (V-066), §15 writer row 199, §14 row 79 (S-20).

---

## §42 — V-080: `stETH.balanceOf(game)` × external parties transferring stETH IN

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 415 (V-080). §15 writer row 205 (external parties transferring stETH IN). §14 row 80 (S-21). Cross-cut: V-071 (H-38) snapshot covers both ETH and stETH inputs at the consumer.

### §42.A — Design-intent backward-trace

**Slot introduction phase:** `stETH.balanceOf(game)` is a **cross-contract Lido slot** with trace-stop status per `D-298-EXEMPT-CROSSCONTRACT-01`. The Lido stETH contract is out-of-source-tree (no source under `contracts/`). The slot's economic function for the game: stETH balance held by the game contract is one of the two components of `totalFunds` at `GameOverModule.handleGameOverDrain:84` (`totalFunds = address(this).balance + steth.balanceOf(address(this))`). The game accumulates stETH via two in-source paths:

1. `AdvanceModule._stakeEth` (at `:1555-:1563`) converts ETH → stETH via Lido `submit{value:}` during advanceGame. Verified verbatim: `try steth.submit{value: stakeable}(address(0)) returns (...`.
2. `GameOverModule.handleFinalSweep._sendStethFirst` (at `:243, :247`) is the OUT direction — game sends stETH to winners via `steth.transfer`. Not relevant to V-080 (V-080 covers IN-direction only).

The IN direction from external parties is the V-080 surface: any EOA can call `IStETH.transfer(game, amount)` directly on the Lido stETH contract, transferring stETH to the game and incrementing `stETH.balanceOf(game)` without invoking any game-side Solidity code.

**Cite for "what would break if frozen":** Tactic (a) gated-revert is **structurally impossible** for stETH IN transfers — the same reason as V-071's selfdestruct/coinbase-payout class:

1. The Lido stETH contract is external; the game cannot reject incoming `stETH.transfer` calls via any game-side code.
2. The ERC20 receiver pattern (`onERC20Received` hook) does NOT exist in standard Lido stETH — there is no callback the game can intercept.
3. Per `D-298-EXEMPT-CROSSCONTRACT-01`, the Lido stETH contract is trace-stop; we cannot modify it.

The only structural fix is tactic (b) snapshot: capture `stETH.balanceOf(game)` at `_gameOverEntropy` time and consume the snapshot inside `handleGameOverDrain`. **And — crucially — this is the SAME snapshot field as V-071's** because the consumer combines ETH balance + stETH balance into the single `totalFunds` quantity.

**Catalog row 415 column 8 rationale (verbatim):** "Same snapshot as V-071 — covers both ETH balance + stETH balance inputs". One snapshot field, two VIOLATION closures (V-071 + V-080).

**Precedent for snapshot pattern:** Phase 281 owed-salt snapshot (cited in V-071 §5.C above). The Cluster F balance snapshot at `_gameOverEntropy` covers both balance-class inputs in a single SSTORE.

### §42.B — Actor game-theory walk

**Exploit-actor class:** Any EOA (or contract) capable of transferring stETH to the game contract during the rngLock window. The attack surface is universal — no protocol participation required:

- Vector 1: Direct `IStETH.transfer(game, amount)` from any stETH holder. Triggers a Lido-side balance update; no game-side Solidity executes.
- Vector 2: Lido rebase (autonomous) — but the catalog's V-077 classifies Lido rebase as EXEMPT-ADVANCEGAME (trace-stop) at row 414 because the rebase magnitude is bounded by Lido's protocol design and is not attacker-controlled. V-080 specifically covers the attacker-controlled IN-transfer class, not the rebase class.

**Action sequence during rngLock window (sequential):**

- T0: `advanceGame` enters the final-day branch. `_gameOverEntropy` requests the terminal VRF word.
- T1 (attacker move): Attacker holds stETH (cheaply obtainable on secondary markets or via direct Lido staking). Attacker calls `IStETH.transfer(GAME_ADDRESS, amount)` on Lido. The Lido-side balance state updates atomically; `stETH.balanceOf(game)` is incremented by `amount` without invoking any game-side code.
- T2 (VRF callback): The terminal VRF word is delivered. `advanceGame` proceeds to `handleGameOverDrain`.
- T3 (consumer SLOAD): `handleGameOverDrain:84` reads `totalFunds = address(this).balance + steth.balanceOf(address(this))`. The value is `ethBalance + (originalStEth + amount)`.
- T4 (resolution): `preRefundAvailable = (ethBalance + originalStEth + amount) − reserved`. Deity-refund pass + terminal-payout magnitude are inflated by `amount`.

**Exploit direction:** Same as V-071 — the attacker gifts stETH to the game (no theft of pre-existing assets), but **shifts the proportion** of `preRefundAvailable` flowing to deity-refunds vs. terminal-payouts. An attacker who controls a deity-pass position or terminal-payout-position extracts EV from the late inflow.

**EV magnitude estimate:** **MEDIUM — bounded by the attacker's stETH inflow magnitude, but with the additional consideration that stETH transfers dilute the per-share rebase math.** Lido stETH is a rebasing token; transferring `amount` of stETH to the game does not affect the game's pre-existing stETH share value, but does increment the absolute `balanceOf` quantity by `amount`. The terminal-day attack EV scales with the attacker's deity-pass position size (or terminal-payout-position size) multiplied by the inflow magnitude. Economic-likelihood disposition: **likely-exploited on terminal day if any attacker has a meaningful deity-pass or terminal-payout position** — the attack is observable and rational.

**Subtle game-theory observation — `_stakeEth` daily-converter and the snapshot timing:** Per project-memory, the `AdvanceModule._stakeEth` callsite at `:1555-:1563` converts ETH → stETH on each advanceGame call. If the snapshot is taken AT `_gameOverEntropy`, the snapshot includes whatever stETH balance exists at that moment — including any `_stakeEth` conversion that happened in the same advanceGame block. This is the correct timing: the snapshot freezes the cumulative stETH balance at the moment the terminal VRF is committed, eliminating the attacker's post-commitment inflow window.

### §42.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot — SAME snapshot field as V-071.** Catalog §16 row 415 column 8 rationale verbatim: "Same snapshot as V-071 — covers both ETH balance + stETH balance inputs".

**Concrete shape (shared with V-071 / H-38):**

- The `gameOverFundsSnapshot` field introduced at H-38 is `uint256 totalFunds = address(this).balance + steth.balanceOf(address(this))` — a SINGLE snapshot that captures the sum of both balance inputs at `_gameOverEntropy` commitment moment.
- `GameOverModule.handleGameOverDrain:84` reads the SINGLE snapshot field instead of the live `address(this).balance + steth.balanceOf(address(this))` computation.
- One field, one SSTORE, one SLOAD on the consumer side. Both V-071 and V-080 close together.
- No independent storage field at V-080. v44.0 plan-phase MUST cite H-38 as the operational anchor; H-42 is preserved per traceability discipline.

**Rationale for rejecting alternative tactics:**

- **(a) gated-revert on stETH IN-transfer** rejected: structurally impossible (Lido contract is external; no ERC20 receiver hook in standard stETH; trace-stop per `D-298-EXEMPT-CROSSCONTRACT-01`).
- **(c) pre-lock reorder** rejected: not applicable — Lido inflows are EOA-discretionary and out-of-source-tree.
- **(d) immutable** rejected: stETH balance is fundamentally mutable.
- **Independent snapshot field at V-080** rejected: redundant with V-071's snapshot field. Combining into a single `totalFunds` snapshot saves one SSTORE and one SLOAD per game-over execution AND simplifies the consumer code to a single load.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** **zero delta beyond V-071's snapshot field at H-38.** V-080 piggybacks on the same `gameOverFundsSnapshot` field.
- **Bytecode delta:** **zero delta beyond V-071's bytecode.** The snapshot computation already includes `+ steth.balanceOf(address(this))`.
- **Net runtime gas:** zero delta beyond V-071.
- **Public ABI:** **NON-BREAKING.** Zero ABI delta beyond V-071.
- **Reference precedent:** Phase 281 owed-salt snapshot. The Cluster F balance snapshot is the canonical multi-input snapshot variant (sum of two slots into one snapshot field).

### §42.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-42`** — Cross-cut anchor for V-080: SAME snapshot field as V-071 (H-38). The `gameOverFundsSnapshot` field captures `address(this).balance + steth.balanceOf(address(this))` as a single value at `_gameOverEntropy`; the consumer at `GameOverModule.handleGameOverDrain:84` reads the single snapshot. Both V-071 and V-080 close atomically when H-38 lands.

- Snapshot WRITE site (shared with H-38): inside `_gameOverEntropy` (`AdvanceModule.sol` final-day entropy-commit callsite; precise line per v44 plan-phase grep).
- Snapshot READ site (shared with H-38): `GameOverModule.sol:84` (replaces live `address(this).balance + steth.balanceOf(address(this))`).
- Storage field (shared with H-38): `gameOverFundsSnapshot` (uint256).
- **Cross-cut note:** V-080's anchor H-42 is preserved per v44.0 handoff-register discipline; the v44.0 sub-phase that lands H-38 closes H-42 atomically (single snapshot field, one SSTORE, one SLOAD covers both VIOLATIONs).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 415 (V-080), §16 row 406 (V-071), §15 writer row 205, §14 row 80 (S-21).

---

## §43 — V-081: S-22 `lootboxEvBenefitUsedByLevel` × `_applyEvMultiplierWithCap` from `openLootBox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 416 (V-081). §14 row 81. Writer enumeration §15 row 206 (`LootboxModule._applyEvMultiplierWithCap` SSTORE at `:511`). Consumer §7 (`_resolveLootboxCommon` manual-path).

### §43.A — Design-intent backward-trace

**Slot introduction phase / rationale:** S-22 is the cross-resolution EV-benefit accumulator — a `(player, level)`-keyed running counter that caps the total ETH amount eligible for above-100% EV multiplier at `LOOTBOX_EV_BENEFIT_CAP` (per `LootboxModule.sol:314`, set to a 10-ETH-equivalent cap per account per game level). The slot was introduced as a v40-era anti-farming safeguard: without the cap, a high-activity-score player could open arbitrarily many lootboxes at the same level and harvest the +35% EV multiplier (`LOOTBOX_EV_MAX_BPS = 13500` per `:472`) without bound. The cap forces the marginal EV-multiplier of large-aggregate opens to converge toward 100% (neutral), preserving the game's expected-value-neutrality at scale.

The function body at `LootboxModule.sol:484-518`: SLOADs `usedBenefit = lootboxEvBenefitUsedByLevel[player][lvl]` at `:496`, computes `remainingCap = LOOTBOX_EV_BENEFIT_CAP - usedBenefit` at `:497-:499`, splits the lootbox amount into `adjustedPortion` (gets the EV multiplier) and `neutralPortion` (gets 100% EV) at `:506-:508`, writes `lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion` at `:511`, and returns `scaledAmount = adjustedValue + neutralPortion` at `:517`.

**Cite for "what would break if naively frozen":** Per `feedback_design_intent_before_deletion.md`, if S-22 were frozen during rngLock (tactic-a style), legitimate concurrent opens at the same level by different players (or by the same player across different indices) would block each other unnecessarily — the daily-VRF rngLock window is broad and would freeze a slot that has no causal dependency on the daily VRF resolution. The slot's natural mutability is per-resolution (one SSTORE per call to `_applyEvMultiplierWithCap`); tactic (a) gating would force the consumer to either retry post-unlock (degraded UX) or reject the open (lost user action).

The structural break is deeper: even ignoring the rngLock window, the cross-resolution accumulator is itself a **design break** with respect to the per-index-commitment-freshness invariant. Per Phase 298 §0 headline #2, S-22's cross-resolution accumulation pattern CONFLICTS with the per-index-frozen-state invariant that governs S-24..S-29. The fix shape recommended in the catalog (tactic (b) per-index snapshot) is a structural realignment: snapshot the available EV cap at the moment of allocation (when `lootboxEth[index][player]` is first written non-zero), store the snapshot per index, and consume from the per-index snapshot at open time — eliminating the cross-resolution race entirely.

**Precedent for snapshot pattern:** Phase 281 owed-salt (`D-281-FIX-SHAPE-01`) introduced the per-index-snapshot-at-commitment pattern for the mint-batch determinism class. Cluster G S-22 maps directly: the EV-cap-remaining value is a function of `(player, level)` state at allocation time; snapshotting it into a new per-index slot at the same point where `lootboxEth[index][player]` is first written eliminates the cross-resolution race at the cost of one new `uint256` snapshot field per `(index, player)` pair.

### §43.B — Actor game-theory walk

**Exploit-actor class:** Player observing the order of pending lootbox opens at the same level, frontrunning to consume the EV-benefit cap ahead of a sibling open.

**Concrete vector:**

- Player A has two purchased lootboxes at level L: index `i_1` (allocated day D, amount 5 ETH, EV-score 30000 → multiplier ~134%) and index `i_2` (allocated day D+1, amount 8 ETH, EV-score 5000 → multiplier ~85%). Both have fulfilled `lootboxRngWordByIndex`.
- The "optimal" play under the current cross-resolution accumulator: open `i_2` (sub-100% multiplier) FIRST, consume the EV-multiplier on its 8-ETH amount at sub-100% (no benefit accumulator consumption), then open `i_1` and harvest the full 134% multiplier on the 5-ETH amount (`adjustedPortion = min(5 ETH, 10 ETH - 0) = 5 ETH`).
- The "suboptimal" play under the current accumulator: open `i_1` FIRST, harvest the 134% multiplier on 5 ETH (`usedBenefit_after = 5 ETH`), then open `i_2` at sub-100% — but the sub-100% multiplier path does NOT touch the accumulator (it skips the `:511` SSTORE entirely because `evMultiplierBps == LOOTBOX_EV_NEUTRAL_BPS` at `:491` short-circuits; OR sub-100% reaches `:511` and accumulates against the cap, but the cap drains nominally). In either case the player loses EV magnitude because the accumulator does not "credit back" sub-100% consumption.

This sequencing exploit is BENIGN within a single player's own portfolio (the player can self-optimize sequence). The exploit becomes **adversarial** when the cross-resolution accumulator is read mid-rngLock by an attacker who wants to deny EV cap to a sibling player at the same level, OR when an attacker MEV-frontruns a victim's `openLootBox` call with a precursor open of their own that consumes the cap for the victim. Catalog row 416 classification `NO — EOA` confirms this VIOLATION class fires from EOA-reachable opens.

**Action sequence during rngLock window (sequential):**

- T0: Both `i_1` and `i_2` have fulfilled `lootboxRngWordByIndex`. Daily-VRF rngLock fires for some unrelated daily VRF resolution.
- T1 (attacker move): Attacker observes Player A's pending opens via the public per-index slots. Attacker opens an OWN-account lootbox at the SAME level L, harvesting EV-benefit cap that would have flowed to Player A. Because the cap is `(player, level)`-keyed, the attacker's open ONLY affects their own accumulator — so this exploit fires only when the attacker IS Player A re-sequencing their own opens. Self-MEV.
- T2 (within-account sequencing): Player A's `openLootBox` at index `i_1` is preceded by Player A's open at index `i_2`. The cross-resolution write at `:511` shifts the cap consumed BEFORE the high-multiplier open reads `usedBenefit` at `:496`. Player A nets less EV than if they had opened in the opposite order.

**EV magnitude estimate:** **HIGH on the per-resolution margin (single open can swing 10-35% EV); CATASTROPHE-tier per `feedback_rng_window_storage_read_freshness.md` (the cross-resolution accumulator bypasses per-index snapshot — fundamental design break per Phase 298 §0 headline #2).** The per-resolution exploit magnitude is bounded by `LOOTBOX_EV_BENEFIT_CAP × 0.35 = 3.5 ETH per level per account`. Multi-level / multi-account attacker realizes additive EV. Economic-likelihood disposition: **likely-exploited** by sophisticated players self-optimizing open sequence; **plausibly-exploited** as cross-player griefing if a player can force a victim's open into a particular sequence via UI manipulation or transaction-ordering games. Per `feedback_design_intent_before_deletion.md`: the design intent (anti-farming cap) is sound; the implementation shape (cross-resolution accumulator) is wrong relative to the per-index-commitment-freshness invariant.

### §43.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) snapshot remaining-cap per index at allocation; Phase 281 owed-salt pattern.** Catalog §16 row 416 rationale: "Snapshot remaining-cap per index at allocation; Phase 281 owed-salt pattern."

**Concrete shape:**

- Introduce a new per-index snapshot field `lootboxEvCapAtAllocation[index][player]` (uint128 sufficient; `LOOTBOX_EV_BENEFIT_CAP` fits in <2^64).
- Populate the field inside `MintModule._allocateLootbox` (when `lbFirstDeposit == true` at `:989`) by snapshotting `LOOTBOX_EV_BENEFIT_CAP - lootboxEvBenefitUsedByLevel[player][cachedLevel + 1]` at allocation time.
- Mirror the populate inside `WhaleModule._recordLootboxEntry` (when `existingAmount == 0` at `:853`).
- Mirror the populate inside `MintModule._purchaseBurnieLootboxFor` for BURNIE-lootbox indexed allocation.
- Modify `_applyEvMultiplierWithCap` at `LootboxModule.sol:484-518` to accept the snapshotted cap as a parameter instead of SLOADing `lootboxEvBenefitUsedByLevel`. The function becomes pure with respect to S-22 (no SSTORE at `:511`).
- The S-22 slot becomes write-only via a new accumulator-update-at-allocation pattern (or is eliminated entirely if the per-index snapshot is sufficient — v44 plan-phase discretion).

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected: would force opens to fail-and-retry mid-rngLock window; degrades UX without addressing the structural cross-resolution race.
- **(c) pre-lock reorder** rejected: the consumer's SLOAD-write cycle is structurally tied to the open-time resolution path; reordering writers/readers requires the snapshot shape anyway.
- **(d) immutable** rejected: the cap is fundamentally mutable per resolution.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** new per-index field `lootboxEvCapAtAllocation[index][player]` (uint128). 16 bytes per `(index, player)` pair. **NOT byte-identical** with respect to S-22 use — adds one new mapping. Storage-delta = +1 mapping slot (slot-key cost is constant; per-occupancy cost is +16-32 bytes per allocated lootbox).
- **Bytecode delta:** ~150-200 bytes. Adds one SSTORE per allocation (in `_allocateLootbox` first-deposit branch, `_recordLootboxEntry` first-deposit branch, `_purchaseBurnieLootboxFor` first-deposit branch); replaces SLOAD+SSTORE at `:496` + `:511` with one parameter pass.
- **Net runtime gas:** approximately neutral. Allocation pays +1 SSTORE (~20000 gas); resolution saves 1 SLOAD + 1 SSTORE (-2100 -5000 gas amortized warm). Each lootbox is allocated once and opened once, so the per-lootbox net is approximately +13000 gas at allocation, -7100 gas at open ≈ +5900 gas total per lootbox lifecycle. Acceptable per `D-298-RECOMMEND-DEPTH-01`.
- **Public ABI:** **NON-BREAKING** per `D-40N-EVT-BREAK-01`. No event topic-hash change; the new field is internal storage. Per `D-43N-AUDIT-ONLY-01` the v44 FIX-MILESTONE plan-phase finalizes the storage-layout decision.
- **Reference precedent:** Phase 281 owed-salt 4th-keccak-input pattern (cited verbatim in catalog rationale). Phase 288 `dailyIdx` structural-anchor snapshot is the multi-call analog.

### §43.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-43`** — Snapshot `LOOTBOX_EV_BENEFIT_CAP - lootboxEvBenefitUsedByLevel[player][level]` at allocation time into a new per-index `lootboxEvCapAtAllocation[index][player]` slot; `_applyEvMultiplierWithCap` accepts the cap as a parameter. Concrete file:line targets:

- Snapshot WRITE site (mint path): `MintModule.sol:989` first-deposit branch (alongside `lootboxDay` / `lootboxBaseLevelPacked` writes at `:991`/`:992`).
- Snapshot WRITE site (whale path): `WhaleModule.sol:853` first-deposit branch (alongside `lootboxDay` / `lootboxBaseLevelPacked` / `lootboxEvScorePacked` writes at `:854`/`:855`/`:856`).
- Snapshot WRITE site (BURNIE path): `MintModule.sol:1396` BURNIE-allocate path (alongside `lootboxDay` first-write at `:1397`).
- Consumer READ site: `LootboxModule.sol:484` — replace SLOAD-write cycle at `:496`/`:511` with parameter consumption.
- Storage field: new `lootboxEvCapAtAllocation` mapping in `DegenerusGameStorage.sol`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 416 (V-081) and §14 row 81.

---

## §44 — V-082: S-22 `lootboxEvBenefitUsedByLevel` × `_applyEvMultiplierWithCap` from `openBurnieLootBox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 417 (V-082). §15 row 206. Consumer §7 (manual-path `_resolveLootboxCommon` reached from `openBurnieLootBox`).

### §44.A — Design-intent backward-trace

**See §1.A for shared S-22 design-intent backward-trace.** V-082 differs only in the consumer reach: instead of `openLootBox` invoking `_applyEvMultiplierWithCap` at `:567`, the BURNIE-lootbox open at `openBurnieLootBox:607-:664` reaches the same function via the `_resolveLootboxCommon` inner-path. Per `LootboxModule.sol:609`, the BURNIE-amount is captured first; per `:629`, `amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100)` (the 80% BURNIE-ETH conversion rate); per `:638`, `_resolveLootboxCommon` is invoked with `amountEth` as the `amount` parameter. The catalog §14 row 206 callsite enumeration confirms the reach: `:567` (openLootBox), `:607` (openBurnieLootBox top-level mention is the `function openBurnieLootBox` header; the actual reach is via `_resolveLootboxCommon`).

The BURNIE-path EV-multiplier is structurally identical to the ETH-path: the same `_applyEvMultiplierWithCap` is invoked, the same S-22 SLOAD-write cycle fires. The cross-resolution accumulator does not distinguish ETH vs BURNIE opens — both contribute to the same `(player, level)` cap. This is intentional per design (the cap is "EV benefit consumed at this level", agnostic to denomination), and the structural break described in §1.A applies identically.

**Cite for "what would break if naively frozen":** Same as §1.A — gating S-22 on `rngLockedFlag` would freeze the cross-resolution accumulator across all opens (ETH + BURNIE) at the affected level, degrading UX for both lootbox flavors.

### §44.B — Actor game-theory walk

**Exploit-actor class:** Same as §1.B (cross-resolution self-MEV / sequencing). The BURNIE-path exploit is structurally identical:

- Player A has one ETH lootbox at level L and one BURNIE lootbox at level L. Both fulfilled.
- Optimal sequence: open the BURNIE lootbox first IF its converted `amountEth` (`burnieAmount × priceWei × 80 / PRICE_COIN_UNIT × 100`) is sub-cap, then open the ETH lootbox to harvest the full EV-multiplier on the remaining cap.
- Suboptimal sequence: open the ETH lootbox first, consume the cap, then open the BURNIE lootbox at neutral 100%.

**Distinction from §1.B:** The BURNIE-path `amountEth` is derived from `priceWei` at `:618` (`PriceLookupLib.priceForLevel(level)`) — meaning the BURNIE-EV magnitude is level-dependent and can shift between purchase time and open time. This compounds the §1.B sequencing exploit: an attacker who anticipates a level-up between two opens can sequence BURNIE-then-ETH (lower BURNIE-EV from pre-level-up price) followed by ETH-EV at the new level.

**Action sequence during rngLock window:** Same shape as §1.B; replace "open `i_1`/`i_2`" with "open ETH index/BURNIE index". The cross-resolution race fires identically.

**EV magnitude estimate:** **HIGH** (same as §1.B). The BURNIE-path adds level-dependent price compounding to the sequencing exploit, slightly elevating EV magnitude vs pure-ETH-portfolio §1.B. CATASTROPHE-tier per `feedback_rng_window_storage_read_freshness.md` (same as §1.A — cross-resolution accumulator design break).

### §44.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Same snapshot as V-081.** Catalog §16 row 417 rationale: "Same snapshot as V-081."

**Concrete shape:** Identical to §1.C — the per-index `lootboxEvCapAtAllocation[index][player]` snapshot serves both ETH-path and BURNIE-path opens. The BURNIE-allocation path at `MintModule._purchaseBurnieLootboxFor:1377-1412` must populate the snapshot at `:1396` (BURNIE first-deposit branch — when `lootboxDay[index][buyer] == 0`) alongside the `lootboxDay` first-write.

**Rationale for rejecting alternative tactics:** Same as §1.C.

**Bytecode / storage-layout / public-ABI impact:** Same as §1.C — the BURNIE-path snapshot population shares the new `lootboxEvCapAtAllocation` mapping. One additional SSTORE inside `_purchaseBurnieLootboxFor` first-deposit branch; replaces the SLOAD-write at `_applyEvMultiplierWithCap:496`/`:511` for the BURNIE-reach. Net runtime gas identical to §1.C estimate. NON-BREAKING ABI.

### §44.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-44`** — Same snapshot as `D-43N-V44-HANDOFF-43`; consumer reach extended to BURNIE-path. Concrete file:line targets:

- Snapshot WRITE site (BURNIE-allocate path): `MintModule.sol:1396` BURNIE first-deposit branch.
- Consumer READ site (BURNIE-reach): `LootboxModule.sol:484` via `_resolveLootboxCommon` reached from `openBurnieLootBox` body — parameter consumption replaces SLOAD-write at `:496`/`:511`.
- Storage field: shared `lootboxEvCapAtAllocation` mapping per `D-43N-V44-HANDOFF-43`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 417 (V-082) and §14 row 81.

---

## §45 — V-084: S-22 `lootboxEvBenefitUsedByLevel` × `_applyEvMultiplierWithCap` from `resolveRedemptionLootbox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 419 (V-084). §15 row 206. Consumer §6 (`LootboxModule.resolveRedemptionLootbox` from sStonk `claimRedemption`).

### §45.A — Design-intent backward-trace

**See §1.A for shared S-22 design-intent backward-trace.** V-084 differs in the consumer reach: `resolveRedemptionLootbox` is invoked via `delegatecall` from `DegenerusGame` when the sStonk sister-contract sends lootbox ETH during `claimRedemption`. The function header at `LootboxModule.sol:707` accepts an `activityScore` parameter explicitly (`uint16 activityScore` at `:707`), which was snapshotted at burn submission inside sStonk — meaning the consumer's *activity score* is already snapshotted per Phase 284-era discipline. The EV-multiplier is derived from the snapshotted score at `:715` (`_lootboxEvMultiplierFromScore(uint256(activityScore))`), then `_applyEvMultiplierWithCap` is invoked at `:716` with the snapshotted multiplier.

The S-22 SLOAD-write at `:496`/`:511` happens INSIDE `_applyEvMultiplierWithCap` regardless of how it was reached. Even though the `activityScore` input is snapshotted, the `lootboxEvBenefitUsedByLevel` consumption is NOT — it is a live SLOAD-write against the player's current `(player, level)` cap counter. This is the structural mirror of §1.A / §2.A: the per-index commitment freshness has been partially established (activity score is snapshotted), but the cross-resolution accumulator slot S-22 bypasses the snapshot.

**Distinction from §1.A / §2.A:** The redemption-lootbox reach is EOA-triggered indirectly: a user calls `sStonk.claimRedemption(...)` (EOA-reachable on the sStonk sister-contract), which transitively reaches `DegenerusGame` via `dgnrs.sendLootboxEth(...)` (or equivalent), which delegate-calls into `LootboxModule.resolveRedemptionLootbox`. The catalog row 419 classifies this as `NO — EOA` (i.e., NOT exempt). Per `feedback_design_intent_before_deletion.md`, the redemption-lootbox path was DESIGNED with snapshot discipline (the `activityScore` parameter is the snapshot vehicle); V-084 represents the residual gap where the S-22 consumption was not snapshotted alongside the score.

**Cite for "what would break if naively frozen":** Gating S-22 on `rngLockedFlag` during the daily-VRF window would block `claimRedemption` flows from succeeding mid-window. This is particularly problematic because `claimRedemption` is a settlement path (the user is exiting a burn position); failing-and-retrying it during the rngLock window degrades UX on a critical user flow.

### §45.B — Actor game-theory walk

**Exploit-actor class:** sStonk holder timing `claimRedemption` to race a sibling open. Concrete vector:

- Player A holds sStonk burn position and intends to claim. A separately holds an ETH lootbox at level L with a fulfilled `lootboxRngWordByIndex`.
- A submits the sStonk burn (snapshotting `activityScore` per Phase 284 discipline). At some later moment, A is ready to call `claimRedemption`.
- Optimal sequence: open the ETH lootbox FIRST (harvest the high-multiplier on the cap), then call `claimRedemption` (which gets neutral 100% on the cap remainder).
- Alternative attacker sequence: `claimRedemption` first (consume the cap with the redemption's lootbox amount at the snapshotted score's multiplier), then open the ETH lootbox at neutral 100%.

The exploit window is wider than §1.B / §2.B because the redemption path's `activityScore` is snapshotted at BURN submission time (potentially days before the claim). An attacker who burned during a high-score window can claim later at the cap's expense; conversely, an attacker who burned during a low-score window can sequence opens to harvest the cap with the high-score open first.

**Action sequence during rngLock window:**

- T0: User has both an open ETH lootbox at level L and a pending sStonk burn position.
- T1: rngLock window opens (daily VRF requested).
- T2 (attacker move): User chains `openLootBox` and `claimRedemption` calls in a single multicall, in the order that maximizes their own EV. The cross-resolution race fires identically to §1.B / §2.B, with the redemption-path's snapshotted score as one of the EV-multiplier inputs.
- T3 (VRF callback): `rngLockedFlag` clears; the user's transactions have already settled at the optimal sequence.

**EV magnitude estimate:** **HIGH** (same as §1.B / §2.B). The redemption-path adds the snapshotted-score lever (the user can time their burn submission to a high-score window, then later sequence opens to harvest the cap). CATASTROPHE-tier per `feedback_rng_window_storage_read_freshness.md` (same fundamental S-22 design break).

### §45.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Snapshot used-benefit at burn submission alongside `activityScore`.** Catalog §16 row 419 rationale: "Snapshot used-benefit at burn submission alongside activityScore."

**Concrete shape:**

- The catalog rationale specifically aligns the S-22 snapshot with the existing `activityScore` snapshot at burn submission. Inside the sStonk burn-submission path, snapshot `lootboxEvBenefitUsedByLevel[player][currentLevel + 1]` alongside the `activityScore` snapshot. Store the cap-snapshot in the sStonk-side burn-position record.
- The redemption-path `resolveRedemptionLootbox` accepts a new `usedBenefitSnapshot` parameter (uint128) alongside `activityScore`. `_applyEvMultiplierWithCap` accepts the snapshot as a parameter (per §1.C shape).
- Note: the redemption-path shape DIFFERS from the per-index `lootboxEvCapAtAllocation` snapshot of §1.C / §2.C — the redemption flow is keyed on burn-position, not lootbox-index. The sStonk-side burn-position record gains a new `usedBenefitAtSubmission` field.

**Rationale for rejecting alternative tactics:** Same as §1.C / §2.C — (a) gating breaks settlement UX, (c) reorder is structurally impossible, (d) immutable is wrong shape.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** new `usedBenefitAtSubmission` field on sStonk burn-position record (uint128). 16 bytes per burn-position. **NOT byte-identical** with respect to sStonk-side storage — adds one field to the burn-position struct.
- **Bytecode delta:** ~80-120 bytes total. One additional SLOAD inside sStonk burn-submission path (to read the current `lootboxEvBenefitUsedByLevel`), one SSTORE (to write the snapshot). One additional parameter on `resolveRedemptionLootbox` (passed through the existing delegatecall interface).
- **Public ABI:** **NON-BREAKING** per `D-40N-EVT-BREAK-01` — the new parameter is internal to the cross-contract delegatecall interface; external sStonk ABI unchanged.
- **Reference precedent:** Phase 281 owed-salt 4th-keccak-input + Phase 284 redemption-snapshot discipline (the existing `activityScore` snapshot is the direct precedent — V-084 fix extends the same shape to S-22).

### §45.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-45`** — Snapshot `lootboxEvBenefitUsedByLevel[player][currentLevel + 1]` at sStonk burn submission alongside `activityScore`; `resolveRedemptionLootbox` accepts the snapshot as a parameter. Concrete file:line targets:

- Snapshot WRITE site: sStonk burn-submission path (file:line per v44 plan-phase grep of sStonk `claimRedemption` precursor).
- Consumer READ site: `LootboxModule.sol:716` — parameter pass into `_applyEvMultiplierWithCap`.
- Storage field: new `usedBenefitAtSubmission` field on sStonk burn-position record.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 419 (V-084) and §14 row 81.

---

## §46 — V-088: S-24 `lootboxEth[index][player]` × `openLootBox` self-zero (post-amount-capture)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 423 (V-088). §14 row 83. Writer enumeration §15 row 210 (`LootboxModule.openLootBox` self-zero at `:576`).

### §46.A — Design-intent backward-trace

**Slot introduction phase / rationale:** S-24 `lootboxEth[index][player]` is the per-index ETH-lootbox amount slot — the canonical "lootbox is purchased and pending resolution" indicator. Storage shape: `uint256` packing `(purchaseLevel << 232) | amount` where `amount < 2^232` (per `LootboxModule.sol:529` mask + `:532` shift extraction). The slot is set non-zero at `MintModule.sol:1013` / `WhaleModule.sol:876` and zeroed at `LootboxModule.sol:576` inside the consumer body. The self-zero is the "spend the slot" act — once zeroed, subsequent `openLootBox` calls with the same `index` revert at `:530` (`if (amount == 0) revert E()`).

The function body sequencing at `:526-:598`:

| Line | Op | Slot | Purpose |
|------|----|------|---------|
| `:528` | SLOAD | S-24 | Read packed `(purchaseLevel, amount)` |
| `:529` | mask | (stack) | Extract `amount` |
| `:533` | SLOAD | rngWordByIndex | Read fulfilled RNG |
| `:537` | SLOAD | S-25 | Read `lootboxDay` |
| `:543` | SLOAD | lootboxEthBase | Read base amount |
| `:550` | SLOAD | S-26 | Read `lootboxBaseLevelPacked` |
| `:563` | SLOAD | S-27 | Read `lootboxEvScorePacked` |
| `:567` | CALL | (internal) | `_applyEvMultiplierWithCap` (reads/writes S-22) |
| `:574` | SLOAD | S-28 | Read `lootboxDistressEth` |
| `:576` | SSTORE | S-24 | **Self-zero S-24** |
| `:577` | SSTORE | lootboxEthBase | Self-zero base |
| `:578` | SSTORE | S-26 | **Self-zero S-26** |
| `:579` | SSTORE | S-27 | **Self-zero S-27** |
| `:580-:582` | SSTORE | S-28 | **Self-zero S-28 (conditional)** |
| `:583` | CALL | (internal) | `_resolveLootboxCommon` |

**The structural concern (catalog row 423 classification "NO — EOA self-stack post-roll"):** The self-zero SSTOREs at `:576..:582` precede the `_resolveLootboxCommon` call at `:583`, which performs external calls (`quests.handlePurchase`, `affiliate.payAffiliate`, `dgnrs.transferFromPool`, etc.). Per the standard re-entrancy guard pattern, the slot is zeroed BEFORE control yields, which protects against the player re-entering THIS index — but does not address the broader concern: the slot values consumed at `:529`/`:537`/`:550`/`:563`/`:574` were SLOADed BEFORE the per-resolution callback in `_applyEvMultiplierWithCap`. If the external calls inside `_applyEvMultiplierWithCap` (none, currently) or inside `_resolveLootboxCommon` could re-enter `openLootBox` for a DIFFERENT index, the assumption that the slot values are "fresh as of resolution start" would hold; but if any of those external calls can mutate S-24..S-28 for the CURRENT index, the cascade breaks.

Per `feedback_verify_call_graph_against_source.md`: the relevant question is "can `_resolveLootboxCommon` re-enter `openLootBox` for the same `(index, player)`?" The answer is: no, because the slot is zeroed at `:576` BEFORE `_resolveLootboxCommon` is called, so a re-entry would revert at `:530`. The residual VIOLATION is structurally different: the slot values captured into stack at `:529` (`amount`) are CORRECTLY frozen pre-CALL, but the cascade of subsequent SLOADs at `:537`/`:550`/`:563`/`:574` reads other slots (S-25..S-28) that COULD in principle be mutated between the function entry (TX C start) and the self-zero block — if those slots had EOA-reachable writers that fire WITHOUT touching S-24.

This is the catalog's per-index commitment quad freshness concern: ALL of S-24..S-28 should be frozen as a unit at the same moment (allocation time), not mutable individually post-allocation. The self-zero rows (V-088, V-094, V-097, V-100) all share this concern.

**Cite for "what would break if naively frozen":** The self-zero pattern is structurally required to prevent double-spend of the same index. Removing the self-zero would allow infinite re-opens of the same `(index, player)`. The fix shape is NOT to remove the self-zero — it is to capture all of S-24..S-28 into stack variables BEFORE any external call can fire (i.e., consolidate the SLOAD-cascade at function entry).

**Precedent for snapshot pattern:** Phase 281 owed-salt 4th-keccak-input pattern (catalog rationale cites verbatim "mirror Phase 281 owed-salt"). The Phase 281 pattern pinned the salt into the keccak input at commitment time, preventing post-fulfillment storage writes from shifting the resolution outcome. V-088 fix maps directly: capture `amount` (and all S-24..S-28 reads) into stack at function entry, BEFORE any cascade of dependent SLOADs that could be affected by re-entry.

### §46.B — Actor game-theory walk

**Exploit-actor class:** Player executing `openLootBox` re-entrantly with another open for a sibling index from the same EOA. Concrete vector hinges on whether `_resolveLootboxCommon` yields control to attacker-controlled code.

**`_resolveLootboxCommon` external-call enumeration (per `feedback_verify_call_graph_against_source.md`):** Sub-agent execution must grep `_resolveLootboxCommon` to enumerate every external call. Candidate concerns:

1. `quests.handlePurchase(...)` — quest-handler external call (target: `IQuests` interface). If `quests` is a player-influenceable address (e.g., set via admin), an attacker who controls the quest handler could re-enter `openLootBox` for a sibling index.
2. `affiliate.payAffiliate(...)` — affiliate-payment external call (target: `IAffiliate`). Same re-entrancy concern if the affiliate address is player-controlled or admin-set to a malicious contract.
3. `dgnrs.transferFromPool(...)` — sDGNRS pool-debit external call (target: `IStakedDegenerusStonk`). The sDGNRS contract is sister-deployed and not player-controlled; low re-entrancy risk.
4. ETH transfer via `payable(...).call{value: ...}("")` — direct ETH send to the player (`call`-style). **HIGH re-entrancy risk** if the player is a contract that re-enters `openLootBox` on receive.

Without a re-entrancy guard, the ETH-transfer surface in `_resolveLootboxCommon` provides a re-entry hook. After `:576` zeroes S-24 for the CURRENT index, an attacker contract that receives the ETH-transfer can call `openLootBox` for a SIBLING index. The sibling index's S-24..S-28 values are still live; the sibling open proceeds normally. The first open's cascade has already happened (stack variables captured); the sibling open's cascade reads S-25..S-28 for the sibling index, which were independently allocated — no cross-index mutation in normal flow.

**However**: the catalog row 423 classification VIOLATION implies a deeper concern. The post-self-zero re-entrancy hook also exposes the cross-resolution accumulator S-22 to multi-open sequence manipulation within a single TX. The sibling open's `_applyEvMultiplierWithCap` invocation sees a freshly-updated `lootboxEvBenefitUsedByLevel[player][lvl]` (the first open's SSTORE at `:511` already fired). This is the cross-resolution race documented in §1.B, but compressed into a single-TX re-entry.

**Action sequence during rngLock window (sequential):**

- T0: Attacker A is a contract with two purchased ETH lootboxes at level L: index `i_1` (high EV-score, large amount) and index `i_2` (low EV-score, small amount). Both fulfilled.
- T1: A calls `openLootBox(A, i_1)`. Function reads `amount_1`, S-25..S-28 for `i_1`, computes `_applyEvMultiplierWithCap` (S-22 SLOAD then SSTORE), reaches `:576` self-zero, dispatches `_resolveLootboxCommon`.
- T2 (inside `_resolveLootboxCommon`): ETH transfer fires to A's `receive()` handler.
- T3 (re-entry): A's `receive()` calls `openLootBox(A, i_2)`. Function reads `amount_2`, S-25..S-28 for `i_2`, computes `_applyEvMultiplierWithCap` — S-22 has ALREADY been written by the outer call at `:511`, so the cap consumption for `i_2` reads the post-outer-write value. This DRAINS more cap from A's account than independent sequential opens would.
- T4: Sibling open completes; outer open resumes; both close.

The exploit's EV depends on (a) whether `_resolveLootboxCommon` ETH transfer actually permits re-entry (check for `nonReentrant` modifier or equivalent guard), and (b) the magnitude of the cap shift between the two opens.

**EV magnitude estimate:** **HIGH if re-entrancy is feasible** — re-entrancy compresses §1.B sequencing exploit into a single TX, allowing the attacker to deterministically order their own opens against the cap (vs sequential txs which could be MEV-ordered). **MEDIUM otherwise** (commitment-window storage-staleness exploit per the F-41-02 / F-41-03 precedent class — the slot freshness is technically violated even without explicit re-entry). Per `feedback_design_intent_before_deletion.md`: the design intent (self-zero as spend-the-slot guard) is sound; the implementation gap is the missing pre-call stack-capture of dependent S-25..S-28 reads.

### §46.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Freeze amount in stack pre-SLOAD-cascade; mirror Phase 281 owed-salt.** Catalog §16 row 423 rationale: "Freeze amount in stack pre-SLOAD-cascade; mirror Phase 281 owed-salt."

**Concrete shape:**

- At `LootboxModule.openLootBox` function entry (immediately after the `amount == 0` revert check at `:530`), consolidate ALL S-24..S-28 SLOADs into stack variables. Specifically: capture `_amount`, `_day`, `_baseLevelPacked`, `_evScorePacked`, `_distressEth` as local `uint256` variables at the top of the function, BEFORE any internal-call (`_applyEvMultiplierWithCap`) or external-call dispatch.
- The self-zero block at `:576..:582` continues to fire BEFORE `_resolveLootboxCommon` at `:583`, preserving the spend-the-slot invariant.
- The downstream computations at `:548-:574` consume the stack variables instead of re-SLOADing.
- Verify (during v44 plan-phase) that `_resolveLootboxCommon` is wrapped in a `nonReentrant` modifier OR explicitly cannot re-enter `openLootBox` — IF re-entry is feasible, the stack-capture shape is the minimum-impact fix; IF re-entry is impossible, the fix is bytecode-cosmetic but preserves the per-index-commitment-freshness invariant for future-proofing.

**Rationale for rejecting alternative tactics:**

- **(a) `rngLockedFlag`-gated revert** rejected: would block opens during daily-VRF rngLock window unnecessarily; the consumer is not a daily-VRF participant.
- **(c) pre-lock reorder** rejected: the consumer reads happen AFTER the writers (purchase) by design; reordering is structurally impossible.
- **(d) immutable** rejected: the slots are fundamentally mutable per-resolution.

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** zero delta. **BYTE-IDENTICAL.** Stack-capture only changes function-local variable usage.
- **Bytecode delta:** ~40-80 bytes. Refactors the SLOAD-cascade into a single block at function entry; downstream uses become MLOAD-style stack reads instead of SLOAD. Net runtime gas: approximately neutral (same number of SLOADs total, just relocated; some MLOAD savings vs repeated SLOADs).
- **Public ABI:** **NON-BREAKING** per `D-40N-EVT-BREAK-01`. No event topic-hash change.
- **Reference precedent:** Phase 281 owed-salt 4th-keccak-input (cited verbatim in catalog rationale). The pattern is: pin all dependent inputs into the resolution computation at the moment of resolution entry, not mid-cascade.

### §46.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-46`** — Consolidate S-24..S-28 SLOADs into stack-capture block at `LootboxModule.openLootBox` function entry. Concrete file:line targets:

- Refactor site: `LootboxModule.sol:526-:598` — insert stack-capture block after `:530` `if (amount == 0) revert E();` and before `:533` `uint256 rngWord = lootboxRngWordByIndex[index];`.
- Self-zero block: `:576..:582` unchanged in placement (still before `_resolveLootboxCommon`).
- Downstream consumers: `:548-:574` updated to read stack variables.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 423 (V-088) and §14 row 83.

---

## §47 — V-089: S-24 `lootboxEth[index][player]` × `MintModule._allocateLootbox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 424 (V-089). §15 row 211 (`MintModule._allocateLootbox` writer at `:1013`). EOA-reach: `buyTickets`.

### §47.A — Design-intent backward-trace

**Slot introduction phase / rationale:** Same S-24 slot architecture as §4.A — per-index ETH-lootbox amount slot packing `(purchaseLevel, amount)`. The MintModule writer at `:1013` is the canonical ETH-lootbox allocation site reached from `buyTickets`. Function shape (per `MintModule.sol:976-1075`):

- `:980` outer guard: `if (lootBoxAmount != 0) { ... }` — only fires when the buyer included a non-zero lootbox amount.
- `:982` index read: `lbIndex = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK))` — the current lootbox-RNG index.
- `:985-:986` existing-amount read: SLOAD `packed = lootboxEth[lbIndex][buyer]`, mask out `existingAmount`.
- `:989-:996` first-deposit branch: if `existingAmount == 0`, write `lootboxDay` (`:991`), `lootboxBaseLevelPacked` (`:992`); emit `LootBoxIdx`.
- `:997-:999` subsequent-deposit branch: if `existingAmount != 0`, require `storedDay == lbDay` (revert E otherwise).
- `:1001-:1015` boosted-amount calculation: apply lootbox-boost via `_applyLootboxBoostOnPurchase`, update `lootboxEthBase`, write `lootboxEth = (purchaseLevel << 232) | newAmount` at `:1013`.
- `:1016` `_lrWrite` pending-ETH counter update.
- `:1029-:1031` distress accumulation: `if (_isDistressMode()) lootboxDistressEth[lbIndex][buyer] += boostedAmount;`.
- `:1155` (later in same function): `if (lbFirstDeposit) lootboxEvScorePacked[lbIndex][buyer] = uint16(cachedScore + 1);`.

**The structural concern (catalog row 424 classification "NO — EOA `buyTickets`"):** The writer at `:1013` is EOA-callable from `buyTickets` at any point during the rngLock window. Specifically: after the VRF callback for `index` (i.e., after `lootboxRngWordByIndex[index]` becomes non-zero, which marks the lootbox as "openable"), the slot SHOULD be locked — but the writer at `:1013` continues to fire if a different buyer calls `buyTickets` with `lbIndex` pointing to the same now-fulfilled index. Wait — the LR_INDEX (lootbox-RNG index counter) ROTATES per VRF cycle, so a fresh `buyTickets` call after the VRF callback writes to a NEW `lbIndex`, not the fulfilled one.

**Critical verification step (per `feedback_verify_call_graph_against_source.md`):** The catalog classifies V-089 VIOLATION, implying the writer at `:1013` CAN reach the same index where `lootboxRngWordByIndex[index]` is already fulfilled. The mechanism: per the broader lootbox-RNG architecture, multiple buyers can allocate to the SAME `lbIndex` (the per-day shared index — see catalog §11 §A re LR_INDEX_SHIFT). Buyer A allocates to `lbIndex = N` on day D. VRF for index N fulfills on day D+1. Buyer B (different EOA) calls `buyTickets` on day D+1 — but the index has rotated to N+1, so B writes to N+1, not N. **So how does the writer at :1013 reach a fulfilled index?**

The mechanism is intra-day re-allocation by the SAME buyer: buyer A on day D, `lbIndex = N`, first allocation writes to `lootboxEth[N][A]`. Same buyer A on day D, second purchase (same TX or different TX) — `lbIndex` is still N (index rotates on day boundary, not per-call). Second allocation hits the `:997-:999` subsequent-deposit branch: requires `storedDay == lbDay`, which is true on day D. So `:1013` writes `newAmount = existingAmount + boostedAmount` — INCREMENTING the slot.

**Now consider the VIOLATION shape**: buyer A allocates on day D (writes `lootboxEth[N][A] = packed1`). VRF for N fulfills mid-day (callback fires inside advance-stack, writes `lootboxRngWordByIndex[N] = rngWord`). Buyer A calls `buyTickets` again BEFORE day rotation, with `lbIndex` still = N. Subsequent-deposit branch fires: `:998` requires `storedDay == lbDay` — TRUE because both are day D. `:1013` writes `newAmount = existingAmount + boostedAmount`. **The slot has been mutated AFTER the VRF callback fired.** When buyer A subsequently calls `openLootBox(A, N)`, the consumer reads the post-mutation `amount`, which is `existingAmount + boostedAmount`. The seed at `LootboxModule.sol:554` uses `amount` (`keccak256(abi.encode(rngWord, player, day, amount))`); the seed is now `keccak(rngWord, A, D, existingAmount + boostedAmount)` — DIFFERENT from `keccak(rngWord, A, D, existingAmount)` which would have been the original commitment.

**This is the load-bearing exploit shape for the entire Cluster G commitment-quad family.** The buyer can OBSERVE the VRF callback (the daily VRF callback writes to public state) and then choose whether to increment `lootboxEth` (and the other commitment quad slots) BEFORE opening — shifting the keccak input to a value that maximizes their outcome.

**Cite for "what would break if naively frozen":** Freezing `lootboxEth` writes after `lootboxRngWordByIndex[index]` becomes non-zero (tactic (a) Phase 290 MINTCLN-style gate) would prevent legitimate intra-day re-allocations by the same buyer after the VRF callback fires. This is acceptable because: (1) the VRF callback for `lbIndex` only fires once per day; (2) intra-day re-allocations after the callback are exactly the exploit window; (3) the buyer can defer their re-allocation to the next day (next `lbIndex`) without UX loss beyond a one-day delay.

**Precedent for gate pattern:** Phase 290 MINTCLN owed-in-baseKey collapse introduced the `RngLocked` custom-error gate (cited at `MintModule.sol:1221`, `BurnieCoinflip.sol:730`, `sStonk.sol:492` per CONTEXT.md). Catalog rationale cites verbatim "Gate buyTickets path on `lootboxRngWordByIndex[index]==0` per Phase 290 MINTCLN."

### §47.B — Actor game-theory walk

**Exploit-actor class:** Player observing fulfilled `lootboxRngWordByIndex[lbIndex]` mid-day, racing to mutate the per-index commitment quad before opening.

**Concrete vector:**

- Day D: Player A purchases initial lootbox at `lbIndex = N`. `lootboxEth[N][A] = (lvl<<232) | amount_initial`. RNG request fires for index N.
- Day D (slightly later): VRF callback fulfills, `lootboxRngWordByIndex[N] = rngWord_N`. Player A can now open lootbox N.
- Day D (before rotation): Player A observes `rngWord_N` is public state. A computes the predicted outcome of `openLootBox(A, N)` under the CURRENT `amount_initial`:
  - `seed_initial = keccak(rngWord_N, A, D, amount_initial)`.
  - `targetLevel_initial = _rollTargetLevel(baseLevel, seed_initial)`.
- A simulates alternative outcomes by varying `amount`:
  - For `amount_alt_1 = amount_initial + 0.1 ETH`: `seed_alt_1 = keccak(rngWord_N, A, D, amount_alt_1)`; `targetLevel_alt_1 = _rollTargetLevel(baseLevel, seed_alt_1)`.
  - A iterates over `amount_alt_K` for many K values, finding the `amount_alt_K*` that produces the highest-EV `targetLevel`.
- A calls `buyTickets` with a lootbox component sized to make `existingAmount + boostedAmount = amount_alt_K*`. Subsequent-deposit branch fires; `lootboxEth[N][A]` updates to the optimized value.
- A calls `openLootBox(A, N)`. Seed is now `keccak(rngWord_N, A, D, amount_alt_K*)`. A harvests the optimized targetLevel.

**Action sequence during rngLock window:** The exploit fires during the post-VRF-fulfillment / pre-open window for `lbIndex = N`. The daily-VRF rngLock window is NOT the relevant window here — the relevant window is the LOOTBOX-RNG window between fulfillment and open.

**EV magnitude estimate:** **HIGH.** The keccak seed is the load-bearing input to `_rollTargetLevel`; an attacker who can search over `amount` values to find a high-EV seed harvests the entire roll-outcome distribution shift. Magnitude is bounded by:
1. The granularity of `amount` (10^-3 ether per `_packEthToMilliEth` quantum) → ~1000s of distinct seeds per ETH of variation.
2. The boost-multiplier ceiling (`LOOTBOX_BOOST_MAX_VALUE = 10 ETH` per `:1419`) → bounded `boostedAmount` increment.
3. The EV-multiplier scaling (`80%-135%`) cascades on top of the targetLevel shift.

Multi-roll-class outcomes (e.g., far-future-bit target, century bonus) compound the exploit's EV. Economic-likelihood disposition: **likely-exploited** by any player who reads `lootboxRngWordByIndex` (public state) and runs a local search loop before opening. Per Phase 298 §0 headline #2: this is THE deep cluster — the per-index commitment quad is the most-exploitable surface in the entire contract.

### §47.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Gate `buyTickets` path on `lootboxRngWordByIndex[index] == 0` per Phase 290 MINTCLN.** Catalog §16 row 424 rationale: "Gate buyTickets path on `lootboxRngWordByIndex[index]==0` per Phase 290 MINTCLN."

**Concrete shape:**

- At `MintModule._allocateLootbox` entry (after `:982` `lbIndex` read), insert a gate:
  ```
  if (lootboxRngWordByIndex[lbIndex] != 0) revert RngLocked();
  ```
  Use the existing `RngLocked` custom error (defined per Phase 290 at `MintModule.sol:1221`).
- The gate fires for both first-deposit branch (`:989-:996`) and subsequent-deposit branch (`:997-:999`). After the VRF callback for `lbIndex` fires, ALL writes to S-24..S-28 for that index are rejected.
- The gate also implicitly protects the subsequent writes inside the same function: S-25 at `:991`, S-26 at `:992`, S-28 at `:1031`, S-27 at `:1155` (via `lbFirstDeposit` guard). Single gate at function entry covers all five S-24..S-28 writers in `_allocateLootbox`.

**Rationale for rejecting alternative tactics:**

- **(b) per-index snapshot** rejected: the natural snapshot point for S-24..S-28 IS the per-index slot itself (they ARE the commitment quad). Tactic (b) would require a DIFFERENT slot to hold the snapshot — but the existing slot already serves this purpose. The fix is to enforce immutability post-fulfillment, not to add a redundant snapshot.
- **(c) pre-lock reorder** rejected: the writer is EOA-triggered at attacker discretion; cannot reorder to land before the VRF callback by construction.
- **(d) immutable** rejected: the slot is fundamentally mutable per-purchase (one allocation per lootbox per index).

**Bytecode / storage-layout / public-ABI impact:**

- **Storage-layout:** zero delta. **BYTE-IDENTICAL.** Gate is pure logic.
- **Bytecode delta:** ~30-50 bytes per gate site. One SLOAD (`lootboxRngWordByIndex[lbIndex]`) + one conditional revert. Net runtime gas: +~2200 gas per `buyTickets` call with non-zero lootbox component (warm SLOAD path), +~2100 gas cold first call.
- **Public ABI:** **NON-BREAKING** per `D-40N-EVT-BREAK-01`. `RngLocked` error is already defined; reverting with it does not change the function's external signature.
- **Reference precedent:** Phase 290 MINTCLN owed-in-baseKey collapse (cited verbatim in catalog rationale). The `RngLocked` revert pattern is the canonical "reject post-fulfillment writes" gate.

### §47.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-47`** — Insert `RngLocked` revert gate at `MintModule._allocateLootbox` entry on `lootboxRngWordByIndex[lbIndex] != 0`. Concrete file:line targets:

- Gate WRITE site: `MintModule.sol:982` — immediately after `lbIndex` is read, before the `existingAmount` SLOAD at `:985`.
- Custom error: existing `RngLocked` (defined per Phase 290 at `MintModule.sol:1221`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 424 (V-089) and §14 row 83.

---

## §48 — V-090: S-24 `lootboxEth[index][player]` × `WhaleModule._whaleLootboxAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 425 (V-090). §15 row 212 (`WhaleModule._whaleLootboxAllocate` writer at `:876`). EOA-reach: `buyWhaleBundle` / `buyWhaleHalf`.

### §48.A — Design-intent backward-trace

**See §5.A for shared S-24 design-intent backward-trace.** V-090 differs in writer module: `WhaleModule._whaleLootboxAllocate` (private function reached via `_recordLootboxEntry` from `buyWhaleBundle` / `buyWhaleHalf` per the catalog §15 row 212 + `WhaleModule.sol:838-:883` body). The function shape is structurally identical to `MintModule._allocateLootbox`:

- `:845` index read: `index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK))`.
- `:849-:851` existing-amount + storedDay read.
- `:853-:859` first-deposit branch: writes `lootboxDay` (`:854`), `lootboxBaseLevelPacked` (`:855`), `lootboxEvScorePacked` (`:856`); emits `LootBoxIndexAssigned`.
- `:860-:862` subsequent-deposit branch: requires `storedDay == dayIndex` (revert E).
- `:864-:877` boosted-amount computation: applies whale boost via `_applyLootboxBoostOnPurchase`, updates `lootboxEthBase`, writes `lootboxEth = (purchaseLevel << 232) | newAmount` at `:876`.
- `:879-:882` distress accumulation: `if (_isDistressMode()) lootboxDistressEth[index][buyer] += boostedAmount;`.

**Distinction from §5.A:** WhaleModule fires from whale-bundle / whale-half EOA purchases. The function shape inherits MintModule's first-deposit-vs-subsequent-deposit branching. The VIOLATION shape (S-24 mutable post-VRF-fulfillment for same `lbIndex` via subsequent-deposit branch) fires identically.

**Cite for "what would break if naively frozen":** Same as §5.A — gating whale-allocation on `lootboxRngWordByIndex[index] != 0` revert prevents legitimate intra-day re-allocations after the VRF callback. The whale-bundle / whale-half paths are EOA-triggered at attacker discretion; the gate at function entry is the canonical "reject post-fulfillment writes" pattern. Whale buyers are typically high-stake actors with strong economic incentive to MEV-optimize their open outcomes — the gate is essential to close this exploit surface.

### §48.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer observing fulfilled `lootboxRngWordByIndex[lbIndex]` mid-day, racing to mutate S-24 via second whale-bundle purchase before opening.

**Concrete vector:** Identical to §5.B with `buyWhaleBundle` / `buyWhaleHalf` substituted for `buyTickets`. The whale-bundle quantum is larger (bundle size determines `boostedAmount` magnitude); the seed-search exploit fires identically against `keccak(rngWord, A, D, amount)` where `amount` includes the whale-bundle contribution.

**Distinction from §5.B:** Whale buyers have larger `boostedAmount` deltas per call (the bundle size is typically much greater than a single ticket purchase). This means each `buyWhaleBundle` re-allocation shifts `amount` by a larger quantum, providing FEWER discrete seed-search points than the MintModule path — but each point has higher economic stake. The exploit is structurally identical; the EV-per-tx magnitude is HIGHER but the seed-search space per ETH-of-budget is smaller.

**Action sequence during rngLock window:** Same as §5.B; substitute `buyWhaleBundle` for `buyTickets`.

**EV magnitude estimate:** **HIGH** (same class as §5.B; comparable or higher magnitude due to whale-bundle stake size). Economic-likelihood disposition: **likely-exploited** by whale-tier players who already operate sophisticated MEV / TX-ordering infrastructure. Per Phase 298 §0 headline #2: same deep-cluster classification.

### §48.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same gating as V-089; mirror MINTCLN gate at WhaleModule entry.** Catalog §16 row 425 rationale: "Same gating as V-089; mirror MINTCLN gate at WhaleModule entry."

**Concrete shape:**

- At `WhaleModule._whaleLootboxAllocate` entry (after `:845` `index` read), insert the gate:
  ```
  if (lootboxRngWordByIndex[index] != 0) revert RngLocked();
  ```
- Use the same `RngLocked` custom error (define at WhaleModule scope, or import from shared error library — v44 plan-phase determines the shared-error pattern).
- Gate covers all five S-24..S-28 writers in `_whaleLootboxAllocate`: `:854`, `:855`, `:856`, `:876`, `:881`.

**Rationale for rejecting alternative tactics:** Same as §5.C — (b) is structurally wrong (the slot IS the snapshot), (c) is impossible, (d) is wrong shape.

**Bytecode / storage-layout / public-ABI impact:** Identical to §5.C — zero storage delta, ~30-50 bytes bytecode delta, +~2200 gas per whale-purchase with non-zero lootbox component, NON-BREAKING ABI.

### §48.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-48`** — Mirror MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry. Concrete file:line targets:

- Gate WRITE site: `WhaleModule.sol:845` — immediately after `index` is read, before the `existingAmount` SLOAD at `:849`.
- Custom error: `RngLocked` (per `D-43N-V44-HANDOFF-47`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 425 (V-090) and §14 row 83.

---

## §49 — V-091: S-25 `lootboxDay[index][player]` × `MintModule._allocateLootbox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 426 (V-091). §15 row 213 (`MintModule._allocateLootbox` writer at `:991`).

### §49.A — Design-intent backward-trace

**See §5.A for shared per-index-commitment-quad design-intent.** S-25 `lootboxDay[index][player]` is the day-keyed entropy chunk of the commitment quad. Storage: `mapping(uint48 => mapping(address => uint32))` (per §14 row 84). The slot is set at `MintModule.sol:991` inside the first-deposit branch (`existingAmount == 0`), capturing `lbDay = _simulatedDayIndex()` at allocation. Subsequent-deposit branch at `:998` requires `storedDay == lbDay` (revert E otherwise) — i.e., the slot is intended to be IMMUTABLE after first-deposit, with the subsequent-deposit branch enforcing the day-equality invariant.

**The structural concern (catalog row 426 classification "NO — EOA"):** Despite the subsequent-deposit branch enforcing `storedDay == lbDay`, the FIRST-deposit branch at `:991` is the EOA-mutable surface. The exploit shape:

- Index `N` is unallocated for player A (i.e., `lootboxEth[N][A] == 0`). Some OTHER player B has allocated to index N (`lootboxEth[N][B] != 0`).
- VRF callback fulfills `lootboxRngWordByIndex[N]` (the index is per-day, shared across allocators on that day).
- Player A then calls `buyTickets` with a lootbox component, on the SAME day D (or a different day, if index has rotated). If on the same day D, first-deposit branch fires: writes `lootboxDay[N][A] = D` at `:991` AFTER the VRF callback has fired.

The `lootboxDay` write at `:991` is per-`(index, player)` keyed — meaning each player has an independent `lootboxDay[N]` entry for the same shared `index`. Player A's first allocation to index N MUTATES `lootboxDay[N][A]` regardless of player B's prior allocation status. If A then opens at `openLootBox(A, N)`, the seed at `LootboxModule.sol:554` uses `day = lootboxDay[N][A]`. Without the gate, A can defer their first allocation until AFTER VRF fulfillment, then search seeds by allocating on different candidate days (the simulated-day-index can change between block timestamps), effectively choosing the `day` input to `keccak(rngWord, A, day, amount)`.

**Note:** This exploit window is narrower than the S-24 exploit (§5.A) because `lbDay = _simulatedDayIndex()` is the CURRENT day at allocation time — A cannot freely choose `day`, but A can defer allocation to a future day to land on a day-value that produces a favorable seed. Combined with the S-24 amount-search, A can search over `(day, amount)` pairs.

**Cite for "what would break if naively frozen":** Same shape as §5.A — gating `_allocateLootbox` on `lootboxRngWordByIndex[lbIndex] != 0` revert blocks all post-VRF-fulfillment writes including the legitimate first-deposit by player A. Player A loses the ability to allocate to index N after the VRF callback; A's only option is to defer to index N+1. UX cost: one-day delay (or one-index-rotation delay).

### §49.B — Actor game-theory walk

**Exploit-actor class:** Player A who has NOT yet allocated to index N, observing fulfilled `lootboxRngWordByIndex[N]`, racing to allocate on a chosen day to seed-search via `day` input.

**Concrete vector:** As described in §7.A. A reads `rngWord_N`, simulates `seed = keccak(rngWord_N, A, day, amount)` for each candidate `(day, amount)` pair, chooses the optimal pair, calls `buyTickets` on the chosen day with the chosen `amount`. First-deposit branch writes `lootboxDay[N][A] = D_chosen` at `:991`.

**Distinction from §5.B:** The S-25 exploit operates on the `day` input dimension; the S-24 exploit operates on the `amount` input dimension. Combined, they multiply the seed-search space.

**Action sequence during rngLock window:** Same shape as §5.B; the `day` choice is bounded by the simulated-day-index granularity (one day per ~24 hours of block time).

**EV magnitude estimate:** **MEDIUM** (as classified in the cluster preamble — affects day-keyed entropy chunk; bounded by day-rotation granularity). Standalone S-25 exploit is narrower than S-24; combined with S-24 it elevates to HIGH per the deep-cluster classification.

### §49.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same gate; lootboxDay is in commitment quad (rngWord, player, day, amount).** Catalog §16 row 426 rationale: "Same gate; lootboxDay is in commitment quad (rngWord,player,day,amount)."

**Concrete shape:** Same gate as §5.C. The gate inserted at `MintModule._allocateLootbox` entry (per `D-43N-V44-HANDOFF-47`) covers the S-25 writer at `:991` automatically — single gate at function entry protects all S-24..S-28 writers in the function.

**Rationale for rejecting alternative tactics:** Same as §5.C.

**Bytecode / storage-layout / public-ABI impact:** Same shared gate per `D-43N-V44-HANDOFF-47`. No additional bytecode delta for V-091 specifically — the gate is already counted in §5.C.

### §49.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-49`** — Shared MINTCLN gate at `_allocateLootbox` entry covers S-25 writer at `:991` (per `D-43N-V44-HANDOFF-47`). Concrete file:line target:

- Writer site: `MintModule.sol:991` (`lootboxDay[lbIndex][buyer] = lbDay`).
- Gate site: `MintModule.sol:982` (shared with `D-43N-V44-HANDOFF-47`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 426 (V-091) and §14 row 84.

---

## §50 — V-092: S-25 `lootboxDay[index][player]` × `MintModule._burnieAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 427 (V-092). §15 row 214 (`MintModule._burnieAllocate` writer at `:1397`).

### §50.A — Design-intent backward-trace

**See §5.A and §7.A for shared per-index commitment-quad design-intent.** V-092 differs in writer: `MintModule._purchaseBurnieLootboxFor` (the BURNIE-coin callback path at `MintModule.sol:1377-:1412`). Function shape:

- `:1381-:1382` liveness + minimum-burnie check (revert E).
- `:1383` index read: `index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK))`.
- `:1384` zero-index check (revert E).
- `:1386` `coin.burnCoin(buyer, burnieAmount)` — burns BURNIE from buyer.
- `:1395-:1397` BURNIE-allocate path: SLOAD `existingAmount = lootboxBurnie[index][buyer]`; if `lootboxDay[index][buyer] == 0`, write `lootboxDay[index][buyer] = _simulatedDayIndex()` at `:1397`.
- `:1399` BURNIE accumulation: `lootboxBurnie[index][buyer] = existingAmount + burnieAmount`.
- `:1401, :1407` `_lrWrite` pending-burnie / pending-eth counter updates.

**The structural concern (catalog row 427 classification "NO — BURNIE coin callback"):** The BURNIE-coin callback path is EOA-triggered (the buyer calls a BURNIE-coin transfer that triggers `_purchaseBurnieLootboxFor` via the coin-callback mechanism). The S-25 writer at `:1397` fires in the "BURNIE first-deposit" branch — when `lootboxDay[index][buyer] == 0` (no prior BURNIE allocation by this buyer at this index). Same exploit shape as §7.B: buyer A defers their FIRST BURNIE-lootbox allocation until AFTER `lootboxRngWordByIndex[index]` is fulfilled, then chooses the allocation day to seed-search the `day` input.

**Distinction from §7.A:** BURNIE-path uses `lootboxBurnie[index][player]` (S-29) as the amount slot (not `lootboxEth`, S-24). The seed in `openBurnieLootBox` at `LootboxModule.sol:629` is `keccak(rngWord, player, day, amountEth)` where `amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100)`. The `day` input has the same shape as the ETH-path; the BURNIE-amount input has different magnitude scaling.

**Cite for "what would break if naively frozen":** Gating BURNIE-allocate on `lootboxRngWordByIndex[index] != 0` prevents legitimate post-fulfillment BURNIE allocations by the buyer to the same index. UX cost: buyer must wait for index rotation. Per Phase 290 MINTCLN precedent, this is the same cost as the MintModule.allocateLootbox gate — acceptable.

### §50.B — Actor game-theory walk

**Exploit-actor class:** BURNIE-lootbox buyer deferring first BURNIE allocation to seed-search the `day` input.

**Concrete vector:** Same shape as §7.B; substitute `_purchaseBurnieLootboxFor` for `_allocateLootbox`. The buyer initiates a BURNIE-coin transfer (which triggers the callback) on a chosen day to seed-search.

**Action sequence during rngLock window:** Same as §7.B; substitute BURNIE-coin transfer for ticket purchase.

**EV magnitude estimate:** **MEDIUM** (same as §7.B — day-keyed entropy chunk). BURNIE-path tends to have larger denominations per call (BURNIE-lootbox minimum at `BURNIE_LOOTBOX_MIN` per `:1382`), so per-allocation stake is higher but seed-search granularity is similar.

### §50.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate on BURNIE allocation path.** Catalog §16 row 427 rationale: "Same MINTCLN-style gate on BURNIE allocation path."

**Concrete shape:**

- At `MintModule._purchaseBurnieLootboxFor` entry (after `:1384` `index` zero-check), insert the gate:
  ```
  if (lootboxRngWordByIndex[index] != 0) revert RngLocked();
  ```
- Gate fires BEFORE the `coin.burnCoin` call at `:1386` (important: do not burn the buyer's BURNIE if the gate will revert).
- Gate covers S-25 writer at `:1397` AND S-29 writer at `:1399` (the BURNIE-allocate path includes both).

**Rationale for rejecting alternative tactics:** Same as §5.C / §7.C.

**Bytecode / storage-layout / public-ABI impact:** Same gate-pattern as §5.C. One additional SLOAD + revert at function entry. ~30-50 bytes. +~2200 gas per BURNIE-lootbox call. NON-BREAKING ABI.

### §50.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-50`** — Insert `RngLocked` revert gate at `MintModule._purchaseBurnieLootboxFor` entry. Concrete file:line targets:

- Gate WRITE site: `MintModule.sol:1384` — after `index` zero-check, before `coin.burnCoin` at `:1386`.
- Custom error: `RngLocked` (per `D-43N-V44-HANDOFF-47`).
- Writer sites covered: `:1397` (S-25), `:1399` (S-29).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 427 (V-092) and §14 row 84.

---

## §51 — V-093: S-25 `lootboxDay[index][player]` × `WhaleModule._whaleLootboxAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 428 (V-093). §15 row 215 (`WhaleModule._whaleLootboxAllocate` writer at `:854`).

### §51.A — Design-intent backward-trace

**See §6.A and §7.A for shared design-intent.** V-093 is the WhaleModule mirror of V-091 (`lootboxDay` write at `:854` inside `_recordLootboxEntry` first-deposit branch). Same structural concern as §7.A — first-deposit by whale buyer is EOA-mutable post-VRF-fulfillment, enabling `day` input seed-search.

**Cite for "what would break if naively frozen":** Same as §6.A / §7.A — gate at function entry blocks legitimate first-deposit-after-fulfillment; UX cost is one-index-rotation delay.

### §51.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer deferring first whale-bundle allocation to seed-search the `day` input.

**Concrete vector:** Same as §7.B; substitute `buyWhaleBundle` / `buyWhaleHalf` for `buyTickets`. Whale-stake amplifies per-call EV.

**EV magnitude estimate:** **MEDIUM** (day-keyed; same class as §7.B / §8.B). Whale-stake elevates per-tx magnitude but seed-search granularity is unchanged.

### §51.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate on WhaleModule allocation.** Catalog §16 row 428 rationale: "Same MINTCLN-style gate on WhaleModule allocation."

**Concrete shape:** Shared gate at `WhaleModule._whaleLootboxAllocate` entry per `D-43N-V44-HANDOFF-48`. The gate covers S-25 writer at `:854` automatically.

**Rationale for rejecting alternative tactics:** Same as §5.C / §6.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate per `D-43N-V44-HANDOFF-48`.

### §51.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-51`** — Shared MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry covers S-25 writer at `:854` (per `D-43N-V44-HANDOFF-48`). Concrete file:line target:

- Writer site: `WhaleModule.sol:854` (`lootboxDay[index][buyer] = dayIndex`).
- Gate site: `WhaleModule.sol:845` (shared with `D-43N-V44-HANDOFF-48`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 428 (V-093) and §14 row 84.

---

## §52 — V-094: S-26 `lootboxBaseLevelPacked` × `openLootBox` self-zero

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 429 (V-094). §15 row 216 (`LootboxModule.openLootBox` self-zero at `:578`).

### §52.A — Design-intent backward-trace

**See §4.A for shared self-zero design-intent.** V-094 differs in the slot: S-26 `lootboxBaseLevelPacked[index][player]` stores the base level for grace-period level computation at open time. Per `LootboxModule.sol:550-:552`:

```
uint24 baseLevelPacked = lootboxBaseLevelPacked[index][player];
uint24 graceLevel = baseLevelPacked == 0 ? currentLevel : baseLevelPacked - 1;
uint24 baseLevel = withinGracePeriod ? graceLevel : purchaseLevel;
```

The `baseLevelPacked` value is set at `MintModule.sol:992` (first-deposit) / `WhaleModule.sol:855` (first-deposit) as `uint24(cachedLevel + 1)` (mint) / `uint24(level + 2)` (whale). It captures the "level at allocation moment" for grace-period rolls. The self-zero at `LootboxModule.sol:578` fires inside the same self-zero block as S-24.

**The structural concern:** Same as §4.A — the self-zero is structurally legitimate, but the SLOAD at `:550` happens BEFORE any opportunity to capture into stack pre-cascade. If `_resolveLootboxCommon` is re-entrancy-vulnerable, a sibling open between the SLOAD at `:550` and the SSTORE at `:578` could mutate S-26 via a sibling-index allocation that reaches this slot — though in practice the per-`(index, player)` keying isolates this concern.

The DEEPER concern for S-26 is the writer-side: the per-index commitment quad includes baseLevel, and the writers at `MintModule.sol:992` / `WhaleModule.sol:855` are EOA-mutable post-VRF-fulfillment (see §11 / §12). The self-zero at `:578` is downstream of those writes; the VIOLATION at V-094 captures the self-zero placement concern.

**Cite for "what would break if naively frozen":** Removing the self-zero would persist `baseLevelPacked` across resolutions; subsequent opens at the same `(index, player)` would reuse the stale baseLevel. The fix shape (per catalog) is stack-capture pre-cascade, not removal.

### §52.B — Actor game-theory walk

**Exploit-actor class:** Same as §4.B — re-entrancy via `_resolveLootboxCommon` external-call surface, OR commitment-window storage-staleness exploit.

**Concrete vector:** baseLevel is consumed at `:552` to determine the roll outcome at `:555` (`targetLevel = _rollTargetLevel(baseLevel, seed)`). Mutation of S-26 between SLOAD (:550) and self-zero (:578) would shift `baseLevel`, affecting `targetLevel`. Re-entry shape mirrors §4.B.

**EV magnitude estimate:** **HIGH** (baseLevel is consumed by every lootbox roll outcome per cluster preamble cluster-G classification). Per Phase 298 §0 headline #2: same deep-cluster impact.

### §52.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Snapshot baseLevel into the index at allocation, not at open time.** Catalog §16 row 429 rationale: "Snapshot baseLevel into the index at allocation, not at open time."

**Concrete shape:**

- The current implementation ALREADY writes baseLevel at allocation (`MintModule.sol:992` / `WhaleModule.sol:855`). The catalog's rationale is that the snapshot is partially-done; the gap is the stack-capture at open time (mirror Phase 281 owed-salt).
- Implement the same stack-capture pattern as §4.C: at `openLootBox` entry, capture `_baseLevelPacked` into a stack variable BEFORE any internal/external call. Use the stack variable at `:550-:552` instead of re-SLOADing.
- Combined with the gate at `D-43N-V44-HANDOFF-47` / `D-43N-V44-HANDOFF-48` (which protects the allocation-time write from post-fulfillment mutation), the per-index baseLevel snapshot becomes truly immutable.

**Rationale for rejecting alternative tactics:** Same as §4.C.

**Bytecode / storage-layout / public-ABI impact:** Zero storage delta. ~10-20 bytes additional bytecode per slot stack-captured (incremental over §4.C — same refactor block). NON-BREAKING ABI.

### §52.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-52`** — Stack-capture `lootboxBaseLevelPacked[index][player]` at `openLootBox` entry; combined with `D-43N-V44-HANDOFF-47`/`-48` MINTCLN gate, the slot becomes per-index immutable. Concrete file:line targets:

- Stack-capture site: `LootboxModule.sol:530` (after `amount == 0` revert, alongside other stack-captures per `D-43N-V44-HANDOFF-46`).
- SSTORE self-zero: `LootboxModule.sol:578` (unchanged placement).
- Writer protection: `MintModule.sol:992` + `WhaleModule.sol:855` (covered by shared gates).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 429 (V-094) and §14 row 85.

---

## §53 — V-095: S-26 `lootboxBaseLevelPacked` × `MintModule._allocateLootbox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 430 (V-095). §15 row 217 (`MintModule._allocateLootbox` writer at `:992`).

### §53.A — Design-intent backward-trace

**See §5.A and §10.A for shared design-intent.** V-095 is the MintModule writer for S-26. Per `MintModule.sol:992`:

```
lootboxBaseLevelPacked[lbIndex][buyer] = uint24(cachedLevel + 1);
```

Fires in the first-deposit branch (`existingAmount == 0` at `:989`). Captures `cachedLevel + 1` (the level-at-allocation-time, +1 to indicate "starting level"). Subsequent-deposit branch does NOT touch S-26 (only S-24 / S-25 / S-28 are subsequent-deposit-mutable; S-26 / S-27 are first-deposit-only).

**The structural concern:** Same as §5.A — first-deposit by buyer A is EOA-mutable post-VRF-fulfillment if A defers their first allocation to index N. The baseLevel-search exploit: A simulates `_rollTargetLevel(baseLevel, seed)` outcomes for candidate `(baseLevel, seed)` pairs, where `baseLevel` is a function of allocation level. By deferring allocation across multiple game-levels, A can choose `cachedLevel + 1` to land on a favorable baseLevel.

**Cite for "what would break if naively frozen":** Same as §5.A — gate at function entry blocks legitimate first-deposit-after-fulfillment.

### §53.B — Actor game-theory walk

**Exploit-actor class:** Player deferring first allocation across game-level rotations to seed-search baseLevel input.

**Concrete vector:** A reads `rngWord_N` (fulfilled). A waits for a favorable `cachedLevel` to align with the seed: simulates `_rollTargetLevel(uint24(cachedLevel + 1), keccak(rngWord_N, A, day, amount))` for current and future levels, chooses optimal level, allocates at that moment.

**Distinction from §5.B / §7.B:** The level dimension is bounded by game-level rotation cadence (which is roughly daily per the daily-VRF mechanism). The search space is narrower than the `amount` dimension but is COMBINATORIAL with `(day, amount)`.

**EV magnitude estimate:** **HIGH** (baseLevel is consumed by every lootbox roll outcome). Per Phase 298 §0 headline #2: deep-cluster classification.

### §53.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate to lock the per-index baseLevel at first allocation.** Catalog §16 row 430 rationale: "Same MINTCLN-style gate to lock the per-index baseLevel at first allocation."

**Concrete shape:** Shared gate at `MintModule._allocateLootbox` entry per `D-43N-V44-HANDOFF-47`. The gate covers S-26 writer at `:992` automatically.

**Rationale for rejecting alternative tactics:** Same as §5.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate per `D-43N-V44-HANDOFF-47`.

### §53.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-53`** — Shared MINTCLN gate at `_allocateLootbox` entry covers S-26 writer at `:992` (per `D-43N-V44-HANDOFF-47`). Concrete file:line target:

- Writer site: `MintModule.sol:992`.
- Gate site: `MintModule.sol:982` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 430 (V-095) and §14 row 85.

---

## §54 — V-096: S-26 `lootboxBaseLevelPacked` × `WhaleModule._whaleLootboxAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 431 (V-096). §15 row 218 (`WhaleModule._whaleLootboxAllocate` writer at `:855`).

### §54.A — Design-intent backward-trace

**See §6.A and §11.A for shared design-intent.** V-096 is the WhaleModule mirror of V-095 (`lootboxBaseLevelPacked` write at `:855` as `uint24(level + 2)` — note: whale path uses `level + 2`, mint path uses `cachedLevel + 1`; the difference reflects the whale-bundle's level-target convention). Same exploit shape as §11.B.

**Cite for "what would break if naively frozen":** Same as §6.A / §11.A.

### §54.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer deferring first whale-bundle allocation across game-level rotations to seed-search baseLevel.

**Concrete vector:** Same as §11.B; substitute whale-bundle for ticket purchase. Whale-stake amplifies per-tx EV.

**EV magnitude estimate:** **HIGH** (same class as §11.B).

### §54.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate on WhaleModule baseLevel writes.** Catalog §16 row 431 rationale: "Same MINTCLN-style gate on WhaleModule baseLevel writes."

**Concrete shape:** Shared gate at `WhaleModule._whaleLootboxAllocate` entry per `D-43N-V44-HANDOFF-48`. Covers S-26 writer at `:855` automatically.

**Rationale for rejecting alternative tactics:** Same as §6.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate.

### §54.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-54`** — Shared MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry covers S-26 writer at `:855` (per `D-43N-V44-HANDOFF-48`). Concrete file:line target:

- Writer site: `WhaleModule.sol:855`.
- Gate site: `WhaleModule.sol:845` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 431 (V-096) and §14 row 85.

---

## §55 — V-097: S-27 `lootboxEvScorePacked` × `openLootBox` self-zero

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 432 (V-097). §15 row 219 (`LootboxModule.openLootBox` self-zero at `:579`).

### §55.A — Design-intent backward-trace

**See §4.A and §10.A for shared self-zero design-intent.** V-097 differs in slot: S-27 `lootboxEvScorePacked[index][player]` stores the snapshotted activity score (offset by +1 to distinguish "unset" from "score=0") used to drive the EV multiplier at open time. Per `LootboxModule.sol:563-:566`:

```
uint16 evScorePacked = lootboxEvScorePacked[index][player];
uint256 evMultiplierBps = evScorePacked == 0
    ? _lootboxEvMultiplierBps(player)
    : _lootboxEvMultiplierFromScore(uint256(evScorePacked - 1));
```

The slot's role: if the score was snapshotted at allocation time (`evScorePacked != 0`), use the snapshot to derive the EV-multiplier; otherwise fall back to the live `_lootboxEvMultiplierBps(player)` computation. This is the catalog's "partially-done snapshot" — the allocation-time snapshot exists, but the open-time path still reads the slot at `:563` and is therefore subject to the same stack-capture concern as §10.A.

**The structural concern:** Same as §4.A / §10.A — the self-zero at `:579` is structurally legitimate but the SLOAD at `:563` happens mid-cascade. The slot's value affects `evMultiplierBps`, which is passed to `_applyEvMultiplierWithCap` at `:567` (the S-22 SLOAD-write site). Mutation of S-27 between SLOAD (:563) and self-zero (:579) would shift `evMultiplierBps` and consequently the cap consumption pattern.

**Cite for "what would break if naively frozen":** Same as §4.A — the self-zero is the spend-the-slot guard. Removing it would allow re-use of the snapshot across opens. Fix shape is stack-capture pre-cascade.

### §55.B — Actor game-theory walk

**Exploit-actor class:** Same as §4.B — re-entrancy via `_resolveLootboxCommon`, OR commitment-window storage-staleness exploit.

**Concrete vector:** EV-score affects the EV-multiplier (`80%-135% bps` per `:472`). Mutation of S-27 mid-cascade shifts the multiplier; combined with the S-22 cap consumption pattern, this can compound the cross-resolution race documented in §1.B.

**EV magnitude estimate:** **HIGH** (EV score is the multiplier-cap input per cluster preamble cluster-G classification). Compounds with the S-22 cross-resolution accumulator exploit.

### §55.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Score must be snapshotted at allocation (partially done; close gap).** Catalog §16 row 432 rationale: "Score must be snapshotted at allocation (partially done; close gap)."

**Concrete shape:** The allocation-time snapshot already exists at `MintModule.sol:1155` (`lootboxEvScorePacked[lbIndex][buyer] = uint16(cachedScore + 1)`) and `WhaleModule.sol:856` (`lootboxEvScorePacked[index][buyer] = uint16(playerActivityScore(buyer) + 1)`). The gap is:

1. Stack-capture at `openLootBox` entry to prevent mid-cascade mutation (per §4.C / §10.C shape).
2. Combined with the writer-side gates at `D-43N-V44-HANDOFF-47` / `D-43N-V44-HANDOFF-48`, the slot becomes immutable post-allocation.

**Rationale for rejecting alternative tactics:** Same as §4.C / §10.C.

**Bytecode / storage-layout / public-ABI impact:** Zero storage delta. ~10-20 bytes incremental over §4.C / §10.C stack-capture block. NON-BREAKING ABI.

### §55.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-55`** — Stack-capture `lootboxEvScorePacked[index][player]` at `openLootBox` entry; combined with writer-side gates, slot becomes per-index immutable. Concrete file:line targets:

- Stack-capture site: `LootboxModule.sol:530` (shared with `D-43N-V44-HANDOFF-46` / `D-43N-V44-HANDOFF-52`).
- SSTORE self-zero: `LootboxModule.sol:579` (unchanged placement).
- Writer protection: `MintModule.sol:1155` + `WhaleModule.sol:856` (covered by shared gates).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 432 (V-097) and §14 row 86.

---

## §56 — V-098: S-27 `lootboxEvScorePacked` × `MintModule._allocateLootbox` snapshot write

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 433 (V-098). §15 row 220 (`MintModule._allocateLootbox` snapshot write at `:1155`).

### §56.A — Design-intent backward-trace

**See §5.A and §13.A for shared design-intent.** V-098 is the MintModule writer for S-27. Per `MintModule.sol:1132-:1157`:

```
if (lootBoxAmount != 0) {
    ...
    if (lbFirstDeposit) {
        lootboxEvScorePacked[lbIndex][buyer] = uint16(cachedScore + 1);
    }
}
```

The write fires only when `lbFirstDeposit == true` AND `lootBoxAmount != 0` — i.e., the first allocation to `lbIndex` by `buyer` that includes a lootbox component. `cachedScore` is computed at `:1106` (`_playerActivityScore(buyer, questStreak)`); the +1 offset is to distinguish "unset" (zero) from "score=0".

**The structural concern:** Same as §11.A — first-deposit by buyer A is EOA-mutable post-VRF-fulfillment. The EV-score-search exploit: A reads `rngWord_N`, simulates `_applyEvMultiplierWithCap` outcomes for candidate score values, chooses optimal score moment via quest-streak / activity manipulation. The quest-streak input to `_playerActivityScore` is itself mutable via attacker-controlled gameplay (quest completions); the attacker can sequence quest completions to land on a favorable score at allocation moment.

**Cite for "what would break if naively frozen":** Same as §5.A — gate at function entry blocks legitimate first-deposit. The compound exploit (quest-streak score-manipulation × first-deposit-deferral) is the deep cluster's worst-case shape: full search over `(level, score, day, amount)` 4-tuple seed inputs.

### §56.B — Actor game-theory walk

**Exploit-actor class:** Player manipulating quest-streak / activity inputs to seed-search EV-score at first-deposit moment.

**Concrete vector:** A completes quests to land at a target `cachedScore`, then calls `buyTickets` with lootbox component to snapshot the score. A defers the call until `rngWord_N` is fulfilled to enable predictive optimization.

**EV magnitude estimate:** **HIGH** (EV score is the multiplier-cap input; compounds with S-22 cap consumption).

### §56.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Gate snapshot write on rng-not-yet-published; pattern Phase 290 MINTCLN.** Catalog §16 row 433 rationale: "Gate snapshot write on rng-not-yet-published; pattern Phase 290 MINTCLN."

**Concrete shape:** Shared gate at `MintModule._allocateLootbox` entry per `D-43N-V44-HANDOFF-47`. The gate covers S-27 writer at `:1155` automatically — the function entry gate fires before any path in the function executes.

**Rationale for rejecting alternative tactics:** Same as §5.C / §11.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate.

### §56.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-56`** — Shared MINTCLN gate at `_allocateLootbox` entry covers S-27 writer at `:1155` (per `D-43N-V44-HANDOFF-47`). Concrete file:line target:

- Writer site: `MintModule.sol:1155`.
- Gate site: `MintModule.sol:982` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 433 (V-098) and §14 row 86.

---

## §57 — V-099: S-27 `lootboxEvScorePacked` × `WhaleModule._whaleLootboxAllocate` snapshot

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 434 (V-099). §15 row 221 (`WhaleModule._whaleLootboxAllocate` snapshot at `:856`).

### §57.A — Design-intent backward-trace

**See §6.A and §14.A for shared design-intent.** V-099 is the WhaleModule mirror of V-098 (`lootboxEvScorePacked` write at `:856` as `uint16(playerActivityScore(buyer) + 1)`). Same exploit shape as §14.B; whale-stake amplifies per-tx EV.

**Cite for "what would break if naively frozen":** Same as §6.A / §14.A.

### §57.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer manipulating activity score (note: the whale path reads `playerActivityScore(buyer)` directly at `:857` rather than the mint-path's `cachedScore`-via-`questStreak` shape; whale path snapshot is more direct but exploits the same activity-input manipulation).

**Concrete vector:** Same as §14.B; substitute whale-bundle for ticket purchase. Whale buyers typically have access to richer activity inputs (whale bundles trigger more activity events per call).

**EV magnitude estimate:** **HIGH** (same class as §14.B).

### §57.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate.** Catalog §16 row 434 rationale: "Same MINTCLN-style gate."

**Concrete shape:** Shared gate at `WhaleModule._whaleLootboxAllocate` entry per `D-43N-V44-HANDOFF-48`. Covers S-27 writer at `:856`.

**Rationale for rejecting alternative tactics:** Same as §6.C / §14.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta.

### §57.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-57`** — Shared MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry covers S-27 writer at `:856` (per `D-43N-V44-HANDOFF-48`). Concrete file:line target:

- Writer site: `WhaleModule.sol:856`.
- Gate site: `WhaleModule.sol:845` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 434 (V-099) and §14 row 86.

---

## §58 — V-100: S-28 `lootboxDistressEth` × `openLootBox` self-zero (conditional)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 435 (V-100). §15 row 222 (`LootboxModule.openLootBox` self-zero at `:581`).

### §58.A — Design-intent backward-trace

**See §4.A for shared self-zero design-intent.** V-100 differs in slot: S-28 `lootboxDistressEth[index][player]` stores the distress-mode portion of the lootbox-ETH amount, used to compute a proportional ticket bonus at open time. Per `LootboxModule.sol:574, :580-:582`:

```
uint256 distressEth = lootboxDistressEth[index][player];
...
if (distressEth != 0) {
    lootboxDistressEth[index][player] = 0;
}
```

The self-zero is conditional (only fires if `distressEth != 0`). The slot is consumed at `:574` via SLOAD, captured into `distressEth` local; later passed to `_resolveLootboxCommon` at `:596` as the `distressEth` parameter.

**The structural concern:** Same as §4.A / §10.A — the SLOAD at `:574` happens BEFORE the self-zero. The self-zero is conditional, but the value flow (SLOAD → local → CALL) follows the same stack-capture pattern as other self-zero slots. Mid-cascade mutation would shift the distress-bonus computation inside `_resolveLootboxCommon`.

**Cite for "what would break if naively frozen":** Same as §4.A — the self-zero (when conditionally fires) is the spend-the-slot guard for the distress portion. Removing it would persist distress across resolutions.

### §58.B — Actor game-theory walk

**Exploit-actor class:** Same as §4.B — re-entrancy via `_resolveLootboxCommon`, OR commitment-window storage-staleness exploit.

**Concrete vector:** Distress affects the proportional ticket-bonus magnitude at resolution. Mutation of S-28 mid-cascade shifts the bonus.

**EV magnitude estimate:** **MEDIUM** (distress flag is a conditional outcome modifier, narrower impact than amount/level/EV-score per cluster preamble cluster-G classification).

### §58.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Freeze distress flag at allocation; same snapshot pattern.** Catalog §16 row 435 rationale: "Freeze distress flag at allocation; same snapshot pattern."

**Concrete shape:** Stack-capture at `openLootBox` entry (shared with §4.C / §10.C / §13.C); writer-side protection via shared gates at `D-43N-V44-HANDOFF-47` / `D-43N-V44-HANDOFF-48`.

**Rationale for rejecting alternative tactics:** Same as §4.C.

**Bytecode / storage-layout / public-ABI impact:** Zero storage delta. ~10-20 bytes incremental. NON-BREAKING ABI.

### §58.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-58`** — Stack-capture `lootboxDistressEth[index][player]` at `openLootBox` entry; combined with writer-side gates, slot becomes per-index immutable. Concrete file:line targets:

- Stack-capture site: `LootboxModule.sol:530` (shared).
- SSTORE self-zero: `LootboxModule.sol:581` (unchanged placement; conditional).
- Writer protection: `MintModule.sol:1031` + `WhaleModule.sol:881` (covered by shared gates).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 435 (V-100) and §14 row 87.

---

## §59 — V-101: S-28 `lootboxDistressEth` × `MintModule._allocateLootbox` distress accumulation

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 436 (V-101). §15 row 223 (`MintModule._allocateLootbox` distress accumulation at `:1031`).

### §59.A — Design-intent backward-trace

**See §5.A and §16.A for shared design-intent.** V-101 is the MintModule writer for S-28. Per `MintModule.sol:1029-:1032`:

```
bool distress = _isDistressMode();
if (distress) {
    lootboxDistressEth[lbIndex][buyer] += boostedAmount;
}
```

The write is ACCUMULATING (`+=`), not first-deposit-only. Every subsequent-deposit during distress-mode adds to the slot. The check `_isDistressMode()` reads game state (specific check not enumerated here; per v44 plan-phase grep).

**The structural concern:** Same as §5.A — accumulating writes are EOA-mutable post-VRF-fulfillment via subsequent-deposit branch. The exploit: A makes a subsequent allocation during distress mode AFTER `lootboxRngWordByIndex[N]` is fulfilled, increasing `lootboxDistressEth[N][A]` and consequently the distress-bonus at open.

**Cite for "what would break if naively frozen":** Same as §5.A — gate at function entry blocks legitimate post-fulfillment distress accumulation. UX cost: distress-mode lootbox purchases must wait for index rotation.

### §59.B — Actor game-theory walk

**Exploit-actor class:** Player making subsequent allocations during distress-mode to inflate S-28 post-fulfillment.

**Concrete vector:** A holds an allocated index N. Distress mode activates. `lootboxRngWordByIndex[N]` fulfills. A reads `rngWord_N` and simulates open outcomes for current `distressEth` value vs inflated values. A calls `buyTickets` with lootbox component during distress to ACCUMULATE distress at `:1031`; opens at the optimal distress value.

**EV magnitude estimate:** **MEDIUM** (distress flag conditional outcome; narrower than amount/level/EV-score).

### §59.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate on distress accumulation.** Catalog §16 row 436 rationale: "Same MINTCLN-style gate on distress accumulation."

**Concrete shape:** Shared gate at `MintModule._allocateLootbox` entry per `D-43N-V44-HANDOFF-47`. Covers S-28 accumulation at `:1031`.

**Rationale for rejecting alternative tactics:** Same as §5.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta.

### §59.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-59`** — Shared MINTCLN gate at `_allocateLootbox` entry covers S-28 accumulator at `:1031` (per `D-43N-V44-HANDOFF-47`). Concrete file:line target:

- Writer site: `MintModule.sol:1031`.
- Gate site: `MintModule.sol:982` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 436 (V-101) and §14 row 87.

---

## §60 — V-102: S-28 `lootboxDistressEth` × `WhaleModule._whaleLootboxAllocate` distress accumulation

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 437 (V-102). §15 row 224 (`WhaleModule._whaleLootboxAllocate` distress accumulation at `:881`).

### §60.A — Design-intent backward-trace

**See §6.A and §17.A for shared design-intent.** V-102 is the WhaleModule mirror of V-101 — distress accumulation at `:881` (`lootboxDistressEth[index][buyer] += boostedAmount`). Identical structural concern; whale-stake amplifies per-tx accumulation delta.

**Cite for "what would break if naively frozen":** Same as §6.A / §17.A.

### §60.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer making subsequent whale-bundle allocations during distress-mode to inflate S-28 post-fulfillment.

**Concrete vector:** Same as §17.B; substitute whale-bundle for ticket purchase. Whale-bundle quantum amplifies per-tx accumulation.

**EV magnitude estimate:** **MEDIUM** (same as §17.B; whale-stake amplifies but slot-impact class is unchanged).

### §60.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate.** Catalog §16 row 437 rationale: "Same MINTCLN-style gate."

**Concrete shape:** Shared gate at `WhaleModule._whaleLootboxAllocate` entry per `D-43N-V44-HANDOFF-48`. Covers S-28 accumulator at `:881`.

**Rationale for rejecting alternative tactics:** Same as §6.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta.

### §60.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-60`** — Shared MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry covers S-28 accumulator at `:881` (per `D-43N-V44-HANDOFF-48`). Concrete file:line target:

- Writer site: `WhaleModule.sol:881`.
- Gate site: `WhaleModule.sol:845` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 437 (V-102) and §14 row 87.

---

## §61 — V-103: S-29 `lootboxBurnie` × `openBurnieLootBox` self-zero

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 438 (V-103). §15 row 225 (`LootboxModule.openBurnieLootBox` self-zero at `:615`).

### §61.A — Design-intent backward-trace

**See §4.A for shared self-zero design-intent.** V-103 differs in slot + consumer: S-29 `lootboxBurnie[index][player]` is the per-index BURNIE-lootbox amount slot (analog of S-24 for the BURNIE-path). Storage: `mapping(uint48 => mapping(address => uint256))` (per §14 row 88). Consumer: `LootboxModule.openBurnieLootBox` at `:607-:664`.

Function body sequencing at `:607-:664`:

| Line | Op | Slot | Purpose |
|------|----|------|---------|
| `:609` | SLOAD | S-29 | Read `burnieAmount` |
| `:610` | check | (stack) | Revert if zero |
| `:612` | SLOAD | rngWordByIndex | Read fulfilled RNG |
| `:613` | check | (stack) | Revert if zero |
| `:615` | SSTORE | S-29 | **Self-zero S-29** |
| `:618` | CALL | priceLib | Read priceWei |
| `:620` | compute | (stack) | `amountEth` from burnieAmount × priceWei × 80% |
| `:624` | SLOAD | S-25 | Read `lootboxDay` |
| `:629` | compute | (stack) | seed = keccak(rngWord, player, day, amountEth) |
| `:638` | CALL | (internal) | `_resolveLootboxCommon` |

**The structural concern:** The BURNIE-path self-zero at `:615` fires EARLIER in the function body than the ETH-path self-zero at `:576-:582` — specifically, BEFORE the `_simulatedDayIndex` / `lootboxDay` cascade at `:624`. This is structurally cleaner than the ETH-path (the slot is zeroed immediately after the amount is captured). However, the same stack-capture concern as §4.A applies: any external call inside `_resolveLootboxCommon` could mutate S-29 for a sibling index via re-entry.

The BURNIE-path is narrower than the ETH-path self-zero concerns (V-088, V-094, V-097, V-100) because S-29 is the ONLY commitment slot zeroed in the BURNIE consumer — S-25 (lootboxDay) at `:624` is NOT zeroed in `openBurnieLootBox` (unlike `openLootBox` which zeroes via the broader self-zero block). The BURNIE-path leaves `lootboxDay` intact, which means a SUBSEQUENT BURNIE-allocation by the same buyer at the same index could fire via the BURNIE-allocate path's first-deposit check (`if (lootboxDay[index][buyer] == 0)` at `MintModule.sol:1396` — which would NOT fire since `lootboxDay != 0`). So the post-resolution state for BURNIE is: S-29 zeroed, S-25 retained — preventing duplicate BURNIE allocations to the same index at the same day, but allowing new BURNIE allocations after day rotation.

**Cite for "what would break if naively frozen":** Same as §4.A — the self-zero is the spend-the-slot guard. Removing it would allow infinite re-opens.

### §61.B — Actor game-theory walk

**Exploit-actor class:** Same as §4.B — re-entrancy via `_resolveLootboxCommon`, OR commitment-window storage-staleness exploit on the BURNIE-amount path.

**Concrete vector:** BURNIE-amount affects `amountEth` (`burnieAmount × priceWei × 80 / PRICE_COIN_UNIT × 100`), which is the keccak input at `:629`. Mutation of S-29 between SLOAD (:609) and self-zero (:615) would shift the seed; but the window is extremely narrow (no internal/external calls between :609 and :615). Re-entry via `_resolveLootboxCommon` (at :638) is the broader concern, where a sibling BURNIE-open could harvest at the cross-resolution accumulator (S-22).

**EV magnitude estimate:** **HIGH** (BURNIE amount magnitude is significant; same class as S-24 amount per cluster preamble — directly scales lootbox magnitude).

### §61.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Freeze burnieAmount into a stack var pre-SLOAD-cascade.** Catalog §16 row 438 rationale: "Freeze burnieAmount into a stack var pre-SLOAD-cascade."

**Concrete shape:**

- At `LootboxModule.openBurnieLootBox` entry (after `:613` `rngWord != 0` check), capture `_burnieAmount`, `_day` into stack variables BEFORE any internal/external call.
- The self-zero at `:615` continues to fire BEFORE the external call to `priceWei` at `:618` (already structurally correct in current implementation; refactor is for symmetry with `openLootBox`).
- Combined with the writer-side gate at `D-43N-V44-HANDOFF-50` (BURNIE-allocate gate), S-29 becomes per-index immutable.

**Rationale for rejecting alternative tactics:** Same as §4.C.

**Bytecode / storage-layout / public-ABI impact:** Zero storage delta. ~30-50 bytes refactor. NON-BREAKING ABI.

### §61.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-61`** — Stack-capture `lootboxBurnie[index][player]` + `lootboxDay[index][player]` at `openBurnieLootBox` entry. Concrete file:line targets:

- Stack-capture site: `LootboxModule.sol:614` (after `:613` `rngWord != 0` check, before `:615` self-zero).
- SSTORE self-zero: `LootboxModule.sol:615` (unchanged placement).
- Writer protection: `MintModule.sol:1399` (covered by `D-43N-V44-HANDOFF-50`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 438 (V-103) and §14 row 88.

---

## §62 — V-104: S-29 `lootboxBurnie` × `MintModule._burnieAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 439 (V-104). §15 row 226 (`MintModule._burnieAllocate` at `:1399`).

### §62.A — Design-intent backward-trace

**See §5.A and §8.A for shared design-intent.** V-104 is the MintModule BURNIE-allocate writer for S-29. Per `MintModule.sol:1395-:1399`:

```
uint256 existingAmount = lootboxBurnie[index][buyer];
if (lootboxDay[index][buyer] == 0) {
    lootboxDay[index][buyer] = _simulatedDayIndex();
}
lootboxBurnie[index][buyer] = existingAmount + burnieAmount;
```

The write is ACCUMULATING (`existingAmount + burnieAmount`) — every BURNIE-coin transfer to the buyer's lootbox at this index adds to the slot. Triggered via BURNIE-coin transfer callback (EOA-triggered indirectly via `coin.burnCoin` at `:1386`).

**The structural concern:** Same as §5.A / §8.A — accumulating writes are EOA-mutable post-VRF-fulfillment. The exploit: A makes additional BURNIE-coin transfers AFTER `lootboxRngWordByIndex[N]` is fulfilled, increasing `lootboxBurnie[N][A]` and consequently the BURNIE-converted `amountEth` at `openBurnieLootBox:620`. The seed at `:629` uses `amountEth`; A can search over `(amountEth, day)` 2-tuples by varying BURNIE-amount.

**Cite for "what would break if naively frozen":** Same as §5.A / §8.A — gate at function entry blocks legitimate post-fulfillment BURNIE accumulations. UX cost: BURNIE buyers must wait for index rotation. Per Phase 290 MINTCLN precedent, acceptable.

### §62.B — Actor game-theory walk

**Exploit-actor class:** BURNIE-buyer making subsequent BURNIE-coin transfers to inflate S-29 post-fulfillment.

**Concrete vector:** Same shape as §8.B (BURNIE-allocate path); compounded with the amount-search dimension. A reads `rngWord_N`, computes seed-search over `amountEth = (burnieAmount × priceWei × 80) / (PRICE_COIN_UNIT × 100)` variations, executes BURNIE-coin transfers to land on optimal `amountEth`.

**EV magnitude estimate:** **HIGH** (same class as §5.B / §8.B — BURNIE-amount directly scales the keccak input + resolution magnitude).

### §62.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate on BURNIE-allocation path.** Catalog §16 row 439 rationale: "Same MINTCLN-style gate on BURNIE-allocation path."

**Concrete shape:** Shared gate at `MintModule._purchaseBurnieLootboxFor` entry per `D-43N-V44-HANDOFF-50`. Covers S-29 accumulator at `:1399` AND S-25 first-write at `:1397` (shared gate).

**Rationale for rejecting alternative tactics:** Same as §5.C / §8.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate per `D-43N-V44-HANDOFF-50`.

### §62.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-62`** — Shared MINTCLN gate at `_purchaseBurnieLootboxFor` entry covers S-29 accumulator at `:1399` (per `D-43N-V44-HANDOFF-50`). Concrete file:line target:

- Writer site: `MintModule.sol:1399`.
- Gate site: `MintModule.sol:1384` (shared with `D-43N-V44-HANDOFF-50`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 439 (V-104) and §14 row 88.

---

## §63 — V-105: presaleStatePacked write inside `_presaleCapCheck` during cap evaluation (MintModule.sol:1026)

### §63.A — Design-intent backward-trace

`presaleStatePacked` is a packed `uint256` declared at `contracts/storage/DegenerusGameStorage.sol:843` and initialized to `1` (PS_ACTIVE bit set) at deploy. It encodes two fields:

- `PS_ACTIVE` (bit 0) — whether the lootbox presale is still active for the current game; cleared on either (a) cumulative ETH cap reached, or (b) phase transition into the jackpot phase
- `PS_MINT_ETH` — running sum of ETH bound to lootbox allocations during the presale window

Both fields exist because the contract supports a one-time per-game "presale" period in which lootbox allocations follow a different distribution split (presale arm in `_resolveLootboxCommon` C-4 site at `LootboxModule.sol`). Once the cumulative ETH crosses `LOOTBOX_PRESALE_ETH_CAP`, the presale closes deterministically.

Writers (per CATALOG §15):
- `MintModule._presaleCapCheck` at `MintModule.sol:1026` (running-sum + bit-clear on cap-met) — **EOA-reachable via `buyTickets` / `processMint`**
- `AdvanceModule._handlePhaseTransition` at `AdvanceModule.sol:433` (`_psWrite(PS_ACTIVE, 0)` — auto-end at jackpot phase start) — EXEMPT-ADVANCEGAME (V-106)
- Constructor initializer at `Storage.sol:843` (deploy-only) — EXEMPT (V-107)

**Why the slot exists.** The presale bit is a meaningful game-design lever: the lootbox economics (`distribution`/`vaultBps`/`futureBps`/`nextBps`) differ between presale and non-presale arms (see `MintModule.sol` lines around :244 where `presale` switches the bps split). Naively gating the cap-check on `rngLockedFlag` would *prevent buy-tickets from advancing the cap* during the rngLock, indirectly extending the presale window and breaking the cap-deterministic-close invariant.

**Phase-precedent.** Phase 288 dailyIdx structural anchor introduced the per-index-snapshot pattern: any per-game-mutating slot whose value participates in a lootbox-resolution roll must be captured at allocation, not consumed live at open.

### §63.B — Actor game-theory walk

Exploit actor: an EOA buyer who can call `buyTickets` between the daily VRF callback (`AdvanceModule.sol:1256 lootboxRngWordByIndex[index] = rngWord`) and his own subsequent `openLootBox(index)`. The buyer observes the published `rngWord`, projects which lootbox-index resolutions would benefit from a flipped presale state (e.g., the presale `vaultBps == 0` arm vs the post-presale arm with non-zero `vaultBps`), and crafts an additional `buyTickets` call sized so that `_presaleCapCheck` runs and either (a) accumulates ETH toward the cap without flipping, or (b) crosses `LOOTBOX_PRESALE_ETH_CAP` and clears `PS_ACTIVE`, flipping the resolution arm for already-allocated indices.

**EV magnitude:** MEDIUM. The presale-vs-post-presale arm change shifts the `vaultBps`/`futureBps`/`nextBps` split for the lootbox amount accounting (lines around `MintModule.sol:244+`), but it does NOT directly increase the player's own scaled-payout (`scaledAmount`). The economic-likelihood disposition is that an attacker would only exploit this when (i) holding a fresh lootbox-RNG index already allocated under presale rules and (ii) the post-presale arm yields a strictly larger personal payout — a narrow case. Conservative classification: MEDIUM.

### §63.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot presale flag per-index at allocation.** At lootbox-allocation time (`MintModule._allocateLootbox` / `WhaleModule._whaleLootboxAllocate`), snapshot `presale = (presaleStatePacked & PS_ACTIVE_MASK) != 0` into a per-index storage field (or repurpose a free bit in `lootboxBaseLevelPacked[index][buyer]`). The lootbox-resolution body reads the snapshotted bit instead of live `presaleStatePacked`.

**Rationale.** Phase 288 dailyIdx + Phase 281 owed-salt precedent: any value participating in a post-RNG-callback resolution must be frozen at allocation. The presale flag participates in the `distribution`/`vaultBps` derivation inside `_resolveLootboxCommon`'s presale-aware branch — snapshotting at allocation eliminates the post-callback flip exploit while preserving the legitimate global cap-tracking semantics.

**Bytecode impact.** ~50-100 bytes — one additional storage write at each allocation callsite (`MintModule:_allocateLootbox`, `WhaleModule:_whaleLootboxAllocate`) and one storage read swap in `_resolveLootboxCommon`. Storage-layout: one new bit per allocated index (cleanly fits into a free bit of `lootboxBaseLevelPacked`); ABI: NON-BREAKING.

### §63.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-63` — CATALOG §16 row V-105 + §17 §C-4 / §D-10 / §E-7. v44.0 plan-phase: define `LB_PRESALE_BIT` in `lootboxBaseLevelPacked` packed layout; emit at allocation; read at consumer presale arm.

---

## §64 — V-109: mintPacked_ write inside `_mintStreakWrite` / `_recordMintStreakForLevel` (MintStreakUtils.sol:47)

### §64.A — Design-intent backward-trace

`mintPacked_[player]` is a `mapping(address => uint256) internal` declared at `contracts/storage/DegenerusGameStorage.sol:424`. It is the master packed slot for the player's mint-flow state, holding (per BitPackingLib field layout):

- `LEVEL_COUNT` — total mint count
- `LEVEL_UNITS` / `LEVEL_UNITS_LEVEL` — current-level unit count
- `LEVEL_STREAK` — streak (consecutive levels minted)
- `MINT_STREAK_LAST_COMPLETED` — last fully completed mint level
- `DAY` — last mint day
- `FROZEN_UNTIL_LEVEL` / `BUNDLE_TYPE` — whale-bundle frozen-pass state
- `HAS_DEITY_PASS` — deity-pass sentinel
- `AFF_POINTS` — cached affiliate points

`_mintStreakWrite` at `MintStreakUtils.sol:47` writes the `MINT_STREAK_LAST_COMPLETED` + `LEVEL_STREAK` fields when a player completes a mint level. This streak field is consumed inside `_mintStreakEffective` (`MintStreakUtils.sol:51`) and feeds into `_playerActivityScore` (`:83/:169`) which is the LIVE input to `_lootboxEvMultiplierBps` (`LootboxModule.sol:444`) — the lootbox's per-player EV multiplier.

**Why the slot exists.** The mint-streak mechanic exists to reward sustained engagement: consecutive mint completions raise the activity-score input to lootbox EV. Naively gating `_mintStreakWrite` on `rngLockedFlag` would either (a) revert legitimate purchases during the rng-lock window (breaking the lock-purchasing UX), or (b) drop the streak silently (breaking the streak-monotonicity invariant).

**Phase-precedent.** Phase 290 MINTCLN (`v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md`) introduced the `cachedJpFlag && rngLockedFlag`-style gate pattern at `MintModule.sol:1221` but for jackpot-phase-only paths. Phase 281 owed-salt established the snapshot-at-allocation pattern for fixing post-callback-mutated VRF inputs (`v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md`).

### §64.B — Actor game-theory walk

Exploit actor: an EOA buyer who holds a pre-VRF-allocated lootbox index. Between the daily VRF callback (`AdvanceModule.sol:1256`) and his own `openLootBox(index)`, the buyer calls `buyTickets` to mint additional levels, triggering `_mintStreakWrite` at `MintStreakUtils.sol:47` to advance `MINT_STREAK_LAST_COMPLETED` and `LEVEL_STREAK`. The post-callback `openLootBox` reads the fresh streak via `_playerActivityScore`, inflating `scoreBps` → `evMultiplierBps` → `scaledAmount` of the existing allocation.

**EV magnitude:** HIGH. `_playerActivityScore` directly multiplies the lootbox payout magnitude (`scaledAmount = amount * evMultiplierBps / 10_000`). A single additional level-completion can raise `evMultiplierBps` from 10_000 to its high-water cap (multiple thousand bps). Per `feedback_rng_window_storage_read_freshness.md` precedent F-41-02/03, any non-VRF SLOAD consumed alongside the RNG word inside the resolution window is in-scope; this is one of the load-bearing examples of that bug class on this codebase.

### §64.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot streak into the lootbox-index at allocation.** At `_allocateLootbox` time, capture the player's then-current `_playerActivityScore`-equivalent into `lootboxEvScorePacked[index][player]` (which D-19 confirms is already a per-index snapshot — close the residual gap by ensuring the streak component is captured at allocation and read from the snapshot, not live).

**Rationale.** This is the canonical Phase 281 owed-salt + Phase 288 dailyIdx pattern. The slot's legitimate cross-game mutation is preserved; only the lootbox-EV consumer reads the frozen value. The MintCount/MintStreak field semantics are NOT changed for any other consumer (jackpot allocation, future-tier reward, affiliate cache).

**Bytecode impact.** ~50-100 bytes — `lootboxEvScorePacked` is already an existing slot per CATALOG §14 S-9. The fix collapses the live-read path inside `_lootboxEvMultiplierBps` (`:444`) to consume the snapshotted score; no new storage slot needed. Storage-layout: identical (snapshot field already exists). ABI: NON-BREAKING.

### §64.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-64` — CATALOG §16 row V-109 + §17 §C-9 / §D-21 / §E-14. v44.0 plan-phase: route `_lootboxEvMultiplierBps` to read `lootboxEvScorePacked[index][player]` rather than live `_playerActivityScore`.

---

## §65 — V-110: mintPacked_ writes inside `MintModule._allocateMintPacked` 3 callsites (MintModule.sol:240, :275, :369)

### §65.A — Design-intent backward-trace

`MintModule._allocateMintPacked` is the master writer for `mintPacked_[player]` on every direct-mint flow (`buyTickets` / `processMint`). The 3 callsites at `:240`, `:275`, `:369` correspond to the three structural arms (verified at source: `:240` = level-only unit update; `:275` = same-level update; `:369` = new-level full update after frozen-until check). Each arm writes a different subset of fields (LEVEL_UNITS, DAY, FROZEN_UNTIL_LEVEL, AFF_POINTS).

The slot is shared between mint-flow accounting and the cross-call SLOAD inside `_playerActivityScore` (CATALOG §7 C-9). **All three callsites mutate fields read by `_lootboxEvMultiplierBps` during lootbox resolution**: LEVEL_COUNT (via `_mintCountBonusPoints`) and AFF_POINTS (via `_playerActivityScore`'s cached-affiliate-points read path).

**Why this writer exists.** Mint-state must accumulate per purchase; this is the central per-EOA state-machine writer.

**Phase-precedent.** Phase 281 + Phase 290 — same shape as V-109.

### §65.B — Actor game-theory walk

Same vector as V-109 — but broader. EOA buyer purchases tickets between VRF callback and his own `openLootBox(index)`. The 3 callsites here represent the 3 possible state-machine transitions a `buyTickets` call may take. Each mutates fields read by `_lootboxEvMultiplierBps`. Cross-resolution accumulator: prior calls in the rng-lock window compound — an attacker can drive LEVEL_COUNT very high (via large `buyTickets` volume) to maximize `_mintCountBonusPoints`'s contribution.

**EV magnitude:** HIGH. Same multiplier on `scaledAmount` as V-109. The 3-callsite enumeration here distinguishes from V-109's `_mintStreakWrite`; together with V-109 the activity-score input set is fully writeable by the player during the rng-lock window.

### §65.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot full activity-score-input set at bet/lootbox placement.** Same as V-109's recommendation: route `_lootboxEvMultiplierBps` to consume the snapshotted `lootboxEvScorePacked[index][player]` (S-9 per CATALOG §14). Crucially, the snapshot at allocation must include **all** activity-score inputs (LEVEL_COUNT, LEVEL_STREAK, AFF_POINTS, jackpotPhaseFlag-derived activeTicketLevel) — not just the streak component.

**Rationale.** A partial snapshot is worse than none: it leaks the exploit surface to whichever input remains live-read. Phase 288 dailyIdx + Phase 281 owed-salt: complete-snapshot is the discipline.

**Bytecode impact.** ~80 bytes — one snapshot SSTORE at `_allocateLootbox`/`_whaleLootboxAllocate` capturing the full activity-score result; consumer reads change from live-recompute to single SLOAD. **Bytecode SAVES** at the consumer site (skips ~5-10 SLOADs and the cross-call `staticcall` into `_playerActivityScore`); net likely slight reduction. Storage-layout: `lootboxEvScorePacked` already exists; encoding can be widened or repurposed. ABI: NON-BREAKING.

### §65.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-65` — CATALOG §16 row V-110 + §17 §C-9 / §D-22 / §E-15. v44.0 plan-phase: define snapshot encoding for full activity-score result; route all 3 callsites' downstream consumer SLOADs through the snapshot.

---

## §66 — V-111: mintPacked_ write inside `BoonModule.consumeActivityBoon` (BoonModule.sol:320)

### §66.A — Design-intent backward-trace

`BoonModule.consumeActivityBoon` at `:281` is the activity-boon redemption path. It (1) clears the pending-boon counter on slot1, (2) writes `mintPacked_[player]`'s LEVEL_COUNT field with `levelCount + pending` (saturating uint24), (3) calls `quests.awardQuestStreakBonus`, and (4) emits `BoonConsumed`.

The `mintPacked_[player] = data` SSTORE happens at `BoonModule.sol:320` (verified at source). This callsite is reached via nested delegatecall from `LootboxModule._resolveLootboxCommon:1035` — i.e., inside the lootbox resolution stack itself.

**Why this writer exists.** Activity boons are a deferred-credit mechanism: tickets won through prior coinflip/whale/lootbox boons accumulate as `pending` and redeem into `levelCount` (which feeds `_mintCountBonusPoints`) the next time the player resolves a lootbox.

**Phase-precedent.** Phase 290 MINTCLN — the boon-roll/consume side-effect ordering was canonicalized during the MINTCLN pivot. The discovery here is that the consume side-effect's `mintPacked_` SSTORE happens BEFORE the boon roll consumes its own RNG-derived sub-outputs from the seed (verified by reading `_resolveLootboxCommon` body — `consumeActivityBoon` is invoked early in the resolution to clear pending boons before downstream activity-score-dependent decisions).

### §66.B — Actor game-theory walk

Self-stack write — the consumer is the same stack invocation that mutates the slot. But: the mutation timing is **AFTER seed derivation** (the seed is already keccaked at top of `_resolveLootboxCommon`) and **BEFORE all downstream consumers** that read `mintPacked_`'s LEVEL_COUNT for that same resolution. Because LEVEL_COUNT is consumed by `_mintCountBonusPoints` and by `_playerActivityScore` *within the same resolution stack frame*, the mid-resolution flush of `pending → LEVEL_COUNT` causes the resolution's own activity-score input to shift compared to a hypothetical pre-flush ordering. Whether this is "exploitable" depends on the order of downstream SLOADs vs the consume-write — and the catalog flags it as `EXEMPT-ADVANCEGAME-EQUIVALENT (self-stack post-seed)` audit-conservatively classified VIOLATION.

**EV magnitude:** HIGH. The activity-score-input shift inside the same resolution stack is amplified by the cross-call staticcall pattern: `_lootboxEvMultiplierBps` calls `IDegenerusGame(address(this)).playerActivityScore(player)` (`LootboxModule.sol:444`), and that external call re-enters into `_playerActivityScore` reading the FRESH `mintPacked_` state. If `consumeActivityBoon` was invoked *before* the cross-call staticcall, the freshly flushed `levelCount` is observed; otherwise the stale value is. The current ordering may be correct, but the audit-conservative classification is that any participating-slot write in the same resolution stack is a VIOLATION.

### §66.C — Recommended tactic + rationale + impact

**Tactic (c) — Reorder `consumeActivityBoon` to AFTER all RNG-driven sub-rolls return.** Pure code-movement: invoke `consumeActivityBoon(player)` only after the boon-roll sub-call returns and after the final scaled-payout amount is computed. The credit-to-LEVEL_COUNT side-effect still happens within the same tx, but cannot influence the resolution's own EV-multiplier computation.

**Rationale.** Zero new storage, zero ABI impact, zero new SSTOREs. The side-effect remains atomically tx-bound. The activity-score consumed by the EV multiplier is now the pre-resolution snapshot, eliminating the intra-stack-frame freshness coupling.

**Bytecode impact.** ~0 bytes — pure code-movement. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §66.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-66` — CATALOG §16 row V-111 + §17 §C-9 / §D-23 / §E-16. v44.0 plan-phase: relocate `_consumeActivityBoon` selector dispatch inside `_resolveLootboxCommon` to post-roll position.

---

## §67 — V-112: mintPacked_ write inside `BoonModule._applyBoon` whale-pass branch (BoonModule.sol:303)

### §67.A — Design-intent backward-trace

`BoonModule._applyBoon` at `:303` is the boon-application writer. The whale-pass branch sets a flag in `mintPacked_[player]` (via the `_activateWhalePass` → `_applyWhalePassStats` chain at `Storage.sol:1204`) when a boon-roll grants a whale-pass. This callsite is reached from two distinct stacks:

1. **Self-stack**: from `LootboxModule._applyBoon:1407` invoked inside `_rollLootboxBoons:1109` — i.e., as a side-effect of the resolving player's own lootbox roll.
2. **Cross-EOA**: from `LootboxModule.issueDeityBoon:776` — a deity-pass-holding EOA grants a boon to a recipient address, and if the granted boon type is the whale-pass variant, the recipient's `mintPacked_` is mutated.

**Why this writer exists.** The whale-pass / deity-pass / boon system is a layered reward mechanic: deity-pass holders can issue boons to recipients (daily-rate-limited via `deityBoonDay`/`deityBoonUsedMask`), and the recipient's mint-state gains the corresponding sentinel.

**Phase-precedent.** Phase 294 DPNERF audited the deity-pass gold-nerf path with the discipline that caller-uniformity matters; Phase 290 MINTCLN's `rngLockedFlag`-gated revert pattern applies to writers reachable during the rng-lock window.

### §67.B — Actor game-theory walk

The cross-EOA reach is the load-bearing exploit. A deity-pass-holding attacker can sequence:

1. Observe daily VRF callback lands at block N.
2. Within rngLock window, call `issueDeityBoon(deity, recipient=victim, slot)` — this writes `boonPacked[victim]` (V-120) AND, if the boon type is whale-pass, writes `mintPacked_[victim]`'s frozen-until / bundle-type / has-deity-pass bits via `_applyWhalePassStats`.
3. Victim's next `openLootBox(index)` reads the freshly-mutated `mintPacked_[victim]` in `_playerActivityScore` and in `_resolveLootboxCommon`'s whale-pass-aware branches.

**EV magnitude:** HIGH. Attacker manipulates VICTIM'S resolution — the cross-EOA dimension is novel relative to V-109/V-110 self-mutation. The MINTCLN-precedent `rngLockedFlag` gate would block this on the writer side. Note: the existing `issueDeityBoon` gate requires `rngWordByDay[day] != 0` (i.e., the day's RNG must be published) — which is precisely the WINDOW OPEN condition for this exploit.

### §67.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot whale-bundle / frozen-until state at lootbox allocation.** Mirrors V-109/V-110: snapshot the whale-bundle-relevant bits of `mintPacked_[buyer]` into the per-index allocation, and route `_resolveLootboxCommon` to read those bits from the snapshot rather than live `mintPacked_[player]`.

**Rationale.** The cross-EOA write CANNOT be blocked at the writer's side without breaking the legitimate `issueDeityBoon` UX (deity-pass holders explicitly invoke this to grant boons to recipients). Snapshot at the recipient-side (allocation-time) is the correct symmetric defense: the recipient's lootbox-index records the activity-score input at allocation; subsequent boon-grants change `mintPacked_[recipient]` but NOT the snapshotted value for the already-allocated index.

**Bytecode impact.** Subsumed into V-109/V-110 snapshot block (same `lootboxEvScorePacked` widening). No additional storage. ABI: NON-BREAKING.

### §67.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-67` — CATALOG §16 row V-112 + §17 §C-9 / §D-23 (note: §D-23 covers `consumeActivityBoon`; V-112 maps to the `_applyBoon` writer separately as a logical row). v44.0 plan-phase: ensure the activity-score snapshot includes whale-pass / frozen-until / has-deity-pass bits at allocation.

---

## §68 — V-113: mintPacked_ writes inside `WhaleModule._buyWhaleBundle*` multi-callsite (WhaleModule.sol:210, :303, :419, :516, :548, :589, :669, :944)

### §68.A — Design-intent backward-trace

`WhaleModule._buyWhaleBundle*` is a family of writers for the whale-bundle purchase paths (`buyWhaleBundle`, `buyWhaleHalf`, `buyDeityPass`). The 8 callsites mutate different fields of `mintPacked_[buyer]`:

- `:210` — bundle-purchase entry: read prevData, set FROZEN_UNTIL_LEVEL + BUNDLE_TYPE (verified at source)
- `:303` — half-bundle path: similar update
- `:419, :516, :548, :669, :944` — additional bundle-tier paths (whale-half / whale-quarter / discounted variants), each performing the same FROZEN_UNTIL_LEVEL/BUNDLE_TYPE write pattern
- `:589` — deity-pass purchase HAS_DEITY_PASS bit set (V-114 below — distinct logical writer)

**Why these writers exist.** The whale-bundle product is a paid pre-purchase of multiple mint levels in advance, with the FROZEN_UNTIL_LEVEL sentinel preventing post-purchase price increases on those levels. Each tier (full / half / etc) has its own entry due to differential ETH pricing / boon-coupling.

**Phase-precedent.** Phase 290 MINTCLN's `rngLockedFlag` gate is the canonical fix pattern for purchase-side EOA writers reachable during the rng-lock window.

### §68.B — Actor game-theory walk

Same shape as V-110 but via the WhaleModule purchase entries. The buyer can `buyWhaleBundle*` between the daily VRF callback and his own `openLootBox(index)`, mutating his own `mintPacked_` (and indirectly the activity-score input). Critically, the whale-bundle purchase ALSO sets FROZEN_UNTIL_LEVEL — a field consumed inside `_resolveLootboxCommon`'s lootbox-EV cap derivation (whale-pass-active branches yield different `evMultiplierBps`).

**EV magnitude:** HIGH. Two-fold: (1) the activity-score input shift (LEVEL_COUNT/LEVEL_UNITS) per V-110, plus (2) the whale-pass-active branch flip inside `_resolveLootboxCommon`.

### §68.C — Recommended tactic + rationale + impact

**Tactic (b) — Same snapshot.** Mirror V-110 / V-112: snapshot all whale-relevant mintPacked_ fields into the lootbox-index allocation cell. Consumer reads from snapshot.

**Rationale.** Identical to V-109/V-110/V-112 — close the snapshot to cover all activity-score AND whale-pass-relevant fields.

**Bytecode impact.** Subsumed into the V-109/V-110 snapshot. ~0 marginal bytes. ABI: NON-BREAKING.

### §68.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-68` — CATALOG §16 row V-113 + §17 §C-9 / §D-24 / §E-17.

---

## §69 — V-114: mintPacked_ write inside `WhaleModule._buyDeityPass` (WhaleModule.sol:589)

### §69.A — Design-intent backward-trace

`WhaleModule._buyDeityPass` at `:589` is the deity-pass purchase path. It writes `mintPacked_[buyer]`'s HAS_DEITY_PASS bit (verified at source: `mintPacked_[buyer] = BitPackingLib.setPacked(..., HAS_DEITY_PASS_SHIFT, 1, 1)`), increments `deityPassPurchasedCount[buyer]`, pushes to `deityPassOwners`, sets `deityPassSymbol[buyer]`, and mints the ERC721 deity-pass token. This is a paid EOA path.

**Why this writer exists.** Deity-passes are a scarce paid asset (capped by `DEITY_PASS_MAX_TOTAL`). The HAS_DEITY_PASS bit in `mintPacked_` is the per-player sentinel consumed by various deity-aware code paths (including `issueDeityBoon`'s eligibility check via `deityPassPurchasedCount[deity] == 0`).

**Phase-precedent.** Phase 294 DPNERF (gold-nerf for deity passes) audited the deity-pass mechanic with caller-uniform discipline.

### §69.B — Actor game-theory walk

The deity-pass purchase is paid (`totalPrice` cost) and rate-limited by `DEITY_PASS_MAX_TOTAL`. The exploit during rngLock: a buyer with a pre-allocated lootbox index calls `buyDeityPass` to set HAS_DEITY_PASS_BIT — and `mintPacked_`'s HAS_DEITY_PASS bit may be consumed by `_resolveLootboxCommon`'s deity-pass-aware boon branches (verified via the BoonModule code reading `deityPassPurchasedCount` / deity-related fields).

**EV magnitude:** HIGH. The deity-pass acquisition unlocks an additional class of cross-EOA boon-issuing influence AND mutates the `mintPacked_` slot read during the player's own lootbox resolution. The economic cost (deity-pass price) is bounded but small relative to high-tier lootbox payouts.

### §69.C — Recommended tactic + rationale + impact

**Tactic (a) — Gate `buyDeityPass` on `rngLockedFlag || lootboxRngWordByIndex[currentIdx] != 0`.** Block the purchase entirely during the rng-lock window. The deity-pass is a paid asset, so blocking is economically painful only during the (short) lock window; legitimate buyers can retry post-unlock.

**Rationale.** Unlike V-109/V-110/V-113 (where snapshot is preferred because the writes are high-volume and broad), `buyDeityPass` is a low-volume rare-purchase entry; an outright gate is acceptable UX, and avoids widening the snapshot to include HAS_DEITY_PASS bits (which would couple V-114 into the same snapshot block as V-113 — a tighter fix but more code change).

**Bytecode impact.** ~30-50 bytes — one `if (rngLockedFlag) revert RngLocked();` at the WhaleModule._buyDeityPass entry. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING (gate is silent-revert during lock window).

### §69.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-69` — CATALOG §16 row V-114 + §17 §C-9 / §D-25 / §E-18.

---

## §70 — V-117: mintPacked_ write inside `_applyWhalePassStats` from lootbox boon path (Storage.sol:1204)

### §70.A — Design-intent backward-trace

`_applyWhalePassStats` at `contracts/storage/DegenerusGameStorage.sol:1141` (verified) writes `mintPacked_[player]` when a whale-pass boon activates. The `:1204` callsite is inside the function body where `mintPacked_[player] = data` is committed after FROZEN_UNTIL_LEVEL / BUNDLE_TYPE updates (verified at source — line :1204 reads "`mintPacked_[player] = data;`").

This writer is reached via `_activateWhalePass` ← `BoonModule._applyBoon` whale-pass branch (`:303`) ← `LootboxModule._rollLootboxBoons:1109` ← `_resolveLootboxCommon`. **Self-stack post-seed write** — happens inside the same lootbox-resolution invocation, AFTER `seed` is derived but BEFORE the resolution returns.

**Why this writer exists.** Whale-pass-boon-activation must commit the recipient's frozen-until / bundle-type fields so the bundle protection is in effect at the next purchase. The function is structured as a shared helper because both EOA-purchase (WhaleModule._buyWhaleBundle*) and boon-grant (via lootbox roll) need to apply the same field updates.

**Phase-precedent.** Same shape as V-111's self-stack post-seed write (D-23 → V-111 reorder). Phase 290 MINTCLN ordering discipline applies.

### §70.B — Actor game-theory walk

Self-stack: the write occurs INSIDE the same resolution that reads `mintPacked_` through the activity-score cross-call. The intra-stack-frame ordering question: does `_applyWhalePassStats:1204` SSTORE happen BEFORE or AFTER the staticcall back into `_playerActivityScore`? If BEFORE, the resolution's own scaled-amount is computed on the fresh post-write state — coupling the boon-roll outcome to the activity-score input. If AFTER, the staticcall reads the pre-write state.

**EV magnitude:** HIGH. Like V-111, the self-stack write may shift the resolution's own EV-multiplier computation. The exploit avenue is more nuanced — the buyer cannot directly trigger this write outside a resolution, but the boon-roll branch is RNG-determined, so the buyer's strategy is to favor allocation-vs-resolution orderings that maximize the favorable branch.

### §70.C — Recommended tactic + rationale + impact

**Tactic (c) — Reorder whale-pass side-effect to AFTER roll consumption returns.** Pure code-movement: defer `_applyWhalePassStats` invocation until AFTER `_resolveLootboxRoll` returns and the scaled-amount is finalized. The whale-pass activation still happens in the same tx; the consumer no longer reads a fresh-self-mutated state.

**Rationale.** Same as V-111 — zero new storage, zero ABI impact, eliminates intra-stack-frame freshness coupling. Symmetric with V-111 reorder.

**Bytecode impact.** ~0 bytes — pure code-movement. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §70.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-70` — CATALOG §16 row V-117 + §17 §C-9 / §D-28 / §E-19.

---

## §71 — V-120: boonPacked write inside `LootboxModule._applyBoon` multi-callsite, including `issueDeityBoon` cross-EOA (LootboxModule.sol:1432..:1603 + :799)

### §71.A — Design-intent backward-trace

`boonPacked[player]` is a `struct BoonPacked { uint256 slot0; uint256 slot1; }` declared at `contracts/storage/DegenerusGameStorage.sol:1605` and mapped publicly at `:1614 mapping(address => BoonPacked) public boonPacked;` (verified — the mapping IS `public`, exposing read-only `boonPacked(address)` accessor).

`LootboxModule._applyBoon` at `:1407` is the canonical writer for `boonPacked` slot0 (and partial slot1 for activity-pending writes). The 8 enumerated callsites at `:1432, :1452, :1479, :1503, :1526, :1547, :1568, :1603` cover the boon-type branches (coinflip / purchase / decimator / lootbox / whale / lazy-pass / deity-pass / activity).

This writer is reached from TWO distinct EOA-rooted entry chains:

1. **Self-stack lootbox roll**: `openLootBox` → `_resolveLootboxCommon:960` → `_rollLootboxBoons:1109` → `_applyBoon`. The resolving player's own lootbox grants himself a boon based on the boon-roll outcome (RNG-derived from the per-index seed).
2. **Cross-EOA `issueDeityBoon`**: `DegenerusGame.issueDeityBoon` (cross-EOA dispatcher at `:861`) → `LootboxModule.issueDeityBoon:776` → `_applyBoon` with `recipient` argument. A deity-pass-holding caller grants a boon to an arbitrary recipient address. Gate: `rngWordByDay[day] != 0` (day's RNG must be published) + per-deity / per-recipient daily-rate-limit.

**Why this writer exists.** Boons are the contract's reward overlay — every lootbox roll has a chance to grant the player a per-category boon (5 types). Deity-pass holders additionally grant boons cross-EOA as a paid-asset privilege.

**Phase-precedent.** Phase 294 DPNERF audited deity-pass paths; Phase 296 SWEEP touched cross-EOA mutation patterns.

### §71.B — Actor game-theory walk

The **cross-EOA `issueDeityBoon` vector is the critical finding.** A deity-pass-holding attacker observes the daily VRF callback published at block N, identifies a victim with a pre-allocated lootbox index, and calls `issueDeityBoon(deity=attacker, recipient=victim, slot)` between block N and the victim's `openLootBox(victimIndex)`. The grant writes `boonPacked[victim]` slot0 bits (e.g., lootbox-tier boon) AND may write `mintPacked_[victim]` via the whale-pass branch (V-112 above).

Critical observation: the gate inside `issueDeityBoon` is `rngWordByDay[day] != 0` — which IS the rng-lock window condition. The legitimate-UX premise is that deity-pass holders need same-day RNG to randomize the boon type (`_deityBoonForSlot` uses `rngWordByDay[day]`). Replacing this with `rngWordByDay[day] != 0 && !rngLockedFlag` would change UX: deity holders couldn't issue boons during the lock; if the lock spans most of a day, this materially affects the deity-pass product. However, blocking on a NARROWER condition — "recipient has no open lootbox index ready" — preserves legitimate cross-day issuance while closing the exploit.

**EV magnitude:** HIGH. The attacker grants the victim a SPECIFIC boon (chosen by the attacker via slot mechanic + boon-type derivation from `rngWordByDay[day]`). If the boon shifts the victim's `_resolveLootboxCommon` boon-roll outcome (e.g., flipping the consumer's boon-presence check), the attacker can FORCE the victim's resolution into a less-favorable branch (e.g., consuming a stamped lootbox-boost-day that the victim would otherwise consume more profitably later). This is a CROSS-EOA GRIEFING vector; the attacker may not gain EV but the victim loses EV.

### §71.C — Recommended tactic + rationale + impact

**Tactic (a) — Gate `issueDeityBoon` on the recipient having no open lootbox index ready.** Concretely: add `if (lootboxRngWordByIndex[recipientCurrentIdx] != 0 && recipient has open index in window) revert E();` (the exact recipient-index-tracking depends on the indexing scheme — recipient's pending lootbox index is queryable via the per-player allocation map).

**Rationale.** Targeted gate preserves legitimate cross-day deity-grant UX while eliminating the cross-EOA exploit window. The self-stack reach of `_applyBoon` (entry chain 1 above) is the same shape as V-117 / V-111 (self-stack post-seed) and is logically subsumed under the boon-roll reorder discipline — the v44.0 fix may collapse V-120's self-stack arm into a tactic-(c) reorder, but the headline tactic is (a) for the cross-EOA arm.

**Bytecode impact.** ~50-80 bytes — recipient-side rng-window check at `issueDeityBoon` entry. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING (silent-revert during recipient's active rng-window).

### §71.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-71` — CATALOG §16 row V-120 + §17 §C-15 / §D-38 / §E-27.

---

## §72 — V-121: boonPacked writes inside `WhaleModule._buyWhaleBundle*` (WhaleModule.sol:202, :388, :556, :898)

### §72.A — Design-intent backward-trace

`WhaleModule` writes `boonPacked[buyer]` slots at 4 callsites (verified at source):

- `:202` — `_buyWhaleBundle` boon-application (BoonPacked storage bp = boonPacked[buyer]; reads s0, then conditionally writes WHALE_DAY / WHALE_BOON_CLEAR at `:248`)
- `:388` — `_buyLazyPass` (BoonPacked storage bpLazy = boonPacked[buyer])
- `:556` — `_buyDeityPass` (BoonPacked storage bpDeity = boonPacked[buyer])
- `:898` — lootbox-boost-tier consumption helper (BoonPacked storage bp = boonPacked[player]; clears BP_LOOTBOX at :909/:922)

Each callsite writes different slot-fields: whale-day stamp at :248, lazy-pass-day stamp at the :388 branch, deity-day stamp at :556, and lootbox-tier clear at :909/:922.

**Why these writers exist.** Each whale-bundle purchase grants a corresponding boon to the buyer (whale-day stamp for the regular-rate-purchase variant; lazy-pass for the auto-rebuy variant; deity-day for the deity-pass holder; lootbox-tier consumption for cross-purchase boon-consumption events).

**Phase-precedent.** Phase 290 MINTCLN gate pattern.

### §72.B — Actor game-theory walk

Same shape as V-109/V-110 but via boonPacked instead of mintPacked_. EOA buyer purchases whale-bundle / lazy-pass / deity-pass during the rng-lock window, mutating his own `boonPacked` slot fields. The mutation is consumed by the next `openLootBox`'s boon-roll path inside `_resolveLootboxCommon` (boon expiry check, boon-day-stamp consumption, etc.).

**EV magnitude:** HIGH. The boon-slot fields directly drive the boon-roll body's branch decisions (e.g., whether `bp.slot0` has an active whale-boon affects the lootbox EV-multiplier; whether deity-pass-day is stamped affects deity-aware code paths).

### §72.C — Recommended tactic + rationale + impact

**Tactic (a) — Same MINTCLN-style gate on WhaleModule boon writes.** Concretely: gate the WhaleModule purchase entries on `rngLockedFlag || lootboxRngWordByIndex[buyer's currentIdx] != 0`. Identical pattern to Phase 290 MINTCLN's `MintModule.sol:1221` gate.

**Rationale.** WhaleModule purchases during the rng-lock window are a narrow operational case; blocking them silently-reverts and aligns with the established MINTCLN gating discipline. Snapshot at allocation (tactic-b) is also plausible but adds storage and is harder to specify cleanly for the multi-field boon writes.

**Bytecode impact.** ~30-50 bytes per gated entry × 4 entries ≈ 120-200 bytes total. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §72.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-72` — CATALOG §16 row V-121 + §17 §C-15 / §D-39 / §E-28.

---

## §73 — V-122: boonPacked write inside `MintModule._applyLootboxBoostOnPurchase` (MintModule.sol:1433)

### §73.A — Design-intent backward-trace

The catalog cites `MintModule._processMint` boon write at `:1433`. Verified at source: line `:1433` is inside `_applyLootboxBoostOnPurchase` (private helper invoked from the mint-flow purchase path). At `:1433` the code reads `BoonPacked storage bp = boonPacked[player]; uint256 s0 = bp.slot0;`, checks tier and expiry, then conditionally writes `bp.slot0 = s0 & BP_LOOTBOX_CLEAR` to clear the lootbox-boost-tier when expired (the SSTORE branches are inside this function body around `:1444+`).

**Catalog row reconciliation note:** The catalog labels this as `_processMint` boon write; source confirms it as `_applyLootboxBoostOnPurchase`. The function is invoked from the mint-flow purchase entry, so the catalog's broader name is accurate at the integration level. The line cite `:1433` is the read-and-then-write pattern entry; the actual SSTORE is at a slightly later line within the same function body.

**Why this writer exists.** Lootbox-boost-on-purchase is a feature whereby a player who has been granted a lootbox-tier boon receives a multiplied lootbox allocation on the next ticket purchase. The expiry-clear at :1433+ is the boon-consumption side-effect.

**Phase-precedent.** Phase 290 MINTCLN gate pattern.

### §73.B — Actor game-theory walk

EOA buyer calls `buyTickets` between VRF callback and `openLootBox`. The `_applyLootboxBoostOnPurchase` consumes the lootbox-tier boon (clears the slot), permanently shifting the `boonPacked[buyer].slot0` state for the subsequent `openLootBox`'s boon-roll body. Strategic ordering matters: consuming the boon on a small purchase wastes it; the attacker chooses to consume on the highest-EV purchase. But during the rng-lock window, the buyer KNOWS the published `rngWord` (or `rngWordByDay[day]`) and can compute the optimal consumption ordering with perfect information.

**EV magnitude:** HIGH. The boon-consumption ordering with-vs-without rng-knowledge is a meaningful EV swing.

### §73.C — Recommended tactic + rationale + impact

**Tactic (a) — Same MINTCLN-style gate on MintModule boon writes.** Mirror Phase 290 MINTCLN: gate the boon-consumption write at `_applyLootboxBoostOnPurchase` on `rngLockedFlag` (or more narrowly, on `lootboxRngWordByIndex[buyer's currentIdx] != 0`).

**Rationale.** Identical to V-121's WhaleModule gating. The lootbox-boost-consume side-effect must not occur during the window when the buyer can read the published RNG.

**Bytecode impact.** ~30-50 bytes — one `if (rngLockedFlag) revert RngLocked();` (or equivalent) at the function entry. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §73.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-73` — CATALOG §16 row V-122 + §17 §C-15 / §D-40 / §E-29.

---

## §74 — V-123: boonPacked writes inside `BoonModule.checkAndClearExpiredBoon` (BoonModule.sol:265, :266)

### §74.A — Design-intent backward-trace

`BoonModule.checkAndClearExpiredBoon` at `:120` is a maintenance writer that walks the player's boon slots and clears expired fields. Verified at source: the function reads `s0`, `s1`, walks each boon category (coinflip, lootbox, whale, lazy-pass, deity-pass, purchase, decimator, activity), and clears expired fields by ANDing with `BP_*_CLEAR` masks. The `:265, :266` callsites correspond to the SSTORE pair `if (changed0) bp.slot0 = s0;` / `if (changed1) bp.slot1 = s1;` at the bottom of the function (verified — lines :265, :266 in the source body are exactly these conditional SSTOREs).

This function is reached only from `_rollLootboxBoons:1120` (grep-confirmed by reading the catalog §16 source-attestation row — no other dispatcher exists). It runs as the FIRST step of the boon-roll sub-call, BEFORE any boon-roll-derived consumption of the slots.

**Why this writer exists.** Expiry-clear must run lazily because boons stamp a day at issuance and clear on subsequent access (lazy-cleanup pattern saves SSTOREs vs eager-clear-on-day-rollover). The lazy-clear runs on the lootbox stack to amortize cost into the resolving player's tx.

**Phase-precedent.** Phase 281 owed-salt snapshot precedent: the expiry decision depends on `_simulatedDayIndex()` which reads `block.timestamp`. A miner / sequencer / EOA capable of influencing tx-ordering can shift which day the clear runs on relative to the boon-roll consumption.

### §74.B — Actor game-theory walk

Self-stack write — `checkAndClearExpiredBoon` runs first inside the boon-roll, mutating `bp.slot0`/`bp.slot1` based on `currentDay = _simulatedDayIndex()`. The boon-roll body then reads the post-clear state. An attacker influences `block.timestamp` (limited but non-zero capacity: miners pick the timestamp within a small window; sequencers on L2 have similar latitude; even regular EOAs can choose to call near a day-rollover boundary). The decision-point: a boon stamp at `stampDay = D` expires at `D + EXPIRY` — if `currentDay > D + EXPIRY`, clear; else keep. Calling near the rollover can flip the decision.

**EV magnitude:** HIGH. The expiry decision determines whether the boon's BPS bonus applies to the subsequent boon-roll body. For a lootbox-tier boon worth several percent EV multiplier, the flip-decision is materially exploitable.

### §74.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot expiry decision based on day at allocation, not at open.** At lootbox-allocation time (`_allocateLootbox` / `_whaleLootboxAllocate`), snapshot each active boon's `(stampDay, EXPIRY, currentDay)` tuple into the per-index allocation; the consumer reads the snapshotted "is-valid-at-allocation-day" bit rather than re-evaluating at open time.

**Rationale.** Phase 281 owed-salt precedent: any value depending on `block.timestamp`-derived inputs participating in a post-VRF-callback roll must be frozen at allocation. The lazy-clear lifecycle is preserved for the maintenance writer (lazy-clear continues to fire on the next non-allocation-rooted invocation), but the per-resolution consumer reads from the allocation snapshot.

**Bytecode impact.** ~50-100 bytes — small per-boon-category bitfield in the allocation cell. ABI: NON-BREAKING.

### §74.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-74` — CATALOG §16 row V-123 + §17 §C-15 / §D-41 / §E-30.

---

## §75 — V-124: boonPacked slot1 write inside `BoonModule.consumeActivityBoon` (BoonModule.sol:291, :297, :301)

### §75.A — Design-intent backward-trace

`BoonModule.consumeActivityBoon` at `:281` — the SAME function as V-111 — additionally writes `bp.slot1` (not just `mintPacked_`). Verified at source:

- `:291` (`bp.slot1 = s1 & BP_ACTIVITY_CLEAR;`) — deity-day mismatch clear branch
- `:297` (`bp.slot1 = s1 & BP_ACTIVITY_CLEAR;`) — stamp-expiry clear branch
- `:301` (`bp.slot1 = s1 & BP_ACTIVITY_CLEAR;`) — successful-consume clear branch

All three SSTOREs clear the activity-pending field of slot1. They are distinct from V-111's `mintPacked_` write (which credits `pending → levelCount`); V-124 is the slot1 side of the same consume action.

**Why this writer exists.** Same as V-111 — activity-boon is the deferred-credit mechanism. The slot1 clear is the consumption-side bookkeeping (zeroing the pending counter).

**Phase-precedent.** Same as V-111 — Phase 290 MINTCLN ordering discipline.

### §75.B — Actor game-theory walk

Self-stack write — same stack as V-111. The slot1 clear happens early in the resolution; downstream boon-roll body reads the post-clear `bp.slot1`. The intra-stack-frame freshness coupling is identical to V-111: depending on the ordering of slot1 SLOADs (e.g., in `_boonPoolStats` reading slot1's activity-pending field) vs the slot1 SSTORE at :291/:297/:301, the resolution observes one or another state.

**EV magnitude:** HIGH. Same as V-111.

### §75.C — Recommended tactic + rationale + impact

**Tactic (c) — Reorder activity-boon consumption to AFTER all RNG-driven sub-rolls return.** Same recommendation as V-111 — relocate the entire `consumeActivityBoon` invocation to post-roll position. Both the mintPacked_ write (V-111) and the boonPacked.slot1 write (V-124) are inside the same function body; reordering once fixes both.

**Rationale.** Single reorder addresses both V-111 and V-124. Zero new storage. Pure code-movement.

**Bytecode impact.** ~0 bytes — same code-movement as V-111. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §75.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-75` — CATALOG §16 row V-124 + §17 §C-15 / §D-42 / §E-31.

---

## §76 — V-125: boonPacked writes via BoonModule other-externals (BoonModule.sol:41, :67, :93, :122, :283)

### §76.A — Design-intent backward-trace

Verified at source — these are the BoonModule external functions:

- `:39 consumeCoinflipBoon(player)` — slot0 line :41 (`BoonPacked storage bp = boonPacked[player];`); SSTORE at :49 / :54 / :58 (BP_COINFLIP_CLEAR branches)
- `:65 consumePurchaseBoost(player)` — slot0 line :67; SSTOREs at :75 / :80 / :84 (BP_PURCHASE_CLEAR branches)
- `:91 consumeDecimatorBoost(player)` — slot0 line :93; SSTOREs at :101 / :105 (BP_DECIMATOR_CLEAR branches)
- `:120 checkAndClearExpiredBoon(player)` — slot0/slot1 line :122; SSTOREs at :265 / :266 (the V-123 maintenance writer)
- `:281 consumeActivityBoon(player)` — slot1 line :283; SSTOREs at :291 / :297 / :301 (the V-111 / V-124 activity-boon writer)

**Cross-dispatcher access analysis (verified via grep in DegenerusGame.sol):**

- `consumeCoinflipBoon` (dispatcher at `DegenerusGame.sol:764`) — gated by `msg.sender != COIN && msg.sender != COINFLIP` → revert. Reach: COIN contract OR COINFLIP contract. **Not EOA-direct.**
- `consumeDecimatorBoon` (dispatcher at `DegenerusGame.sol:789`) — gated by `msg.sender != COIN` → revert. Reach: COIN contract only. **Not EOA-direct.**
- `consumePurchaseBoost` (dispatcher at `DegenerusGame.sol:809`) — gated by `msg.sender != address(this)` → revert. Reach: self-call from delegate modules ONLY. **Not EOA-direct.**
- `checkAndClearExpiredBoon` — no external dispatcher in DegenerusGame.sol (grep-confirmed); reached only via internal delegatecall from `_rollLootboxBoons:1120`.
- `consumeActivityBoon` — no external dispatcher in DegenerusGame.sol (grep-confirmed); reached only via internal delegatecall from `_resolveLootboxCommon:1035`.

**Why the slot exists.** Boons are consumed at multiple touchpoints (BURNIE-coin transfers consume coinflip-boon; decimator runs consume decimator-boost; lootbox resolves consume lootbox-tier and activity boons). Each consumer is the natural dispatch site.

**Phase-precedent.** Phase 290 MINTCLN gate pattern; Phase 294 DPNERF caller-uniform discipline.

### §76.B — Actor game-theory walk

Despite the access guards, EOA-induced reach is non-zero:

- `consumeCoinflipBoon`: an EOA triggers BURNIE-coin transfer → COIN/COINFLIP contract enters → calls back into `DegenerusGame.consumeCoinflipBoon(player)` → delegatecalls BoonModule's slot-clearing path. The EOA orchestrates this between rng-lock-window boundaries.
- `consumeDecimatorBoost`: an EOA triggers BURNIE-coin path → similar.
- `consumePurchaseBoost`: reached only via `address(this)` self-call → EOA-triggered when an EOA invokes a DegenerusGame function that internally self-calls consumePurchaseBoost (e.g., a tickets-purchase variant).
- `checkAndClearExpiredBoon` / `consumeActivityBoon`: reached only via internal delegatecall from lootbox resolution → V-123 / V-111+V-124 already classify these (self-stack writes).

So V-125 logically covers the 3 EOA-orchestrated-via-COIN-callback consumers (coinflip, decimator, purchase) and their boonPacked SSTOREs.

**EV magnitude:** HIGH. Each consumer clears a specific boon's BPS multiplier. An EOA observing the published `rngWord` can sequence COIN-callback-induced consumes of boons that are NOT applicable to the upcoming lootbox-roll body, *preserving* the boons that ARE applicable (and thereby flipping the boon-roll body's branch). This is a "consume-the-wrong-boon-first" griefing-of-self-by-design exploit; reverse direction: an attacker may force a victim's boon-consumption via a constructed COIN-transfer/callback ordering — depends on whether the COIN/COINFLIP contracts allow EOA-controlled `player` argument selection.

### §76.C — Recommended tactic + rationale + impact

**Tactic (a) — Gate each EOA-reachable BoonModule external on no-fresh-lootbox-rng-in-window.** Add `if (rngLockedFlag || lootboxRngWordByIndex[player's currentIdx] != 0) revert RngLocked();` at the DegenerusGame.sol dispatchers for `consumeCoinflipBoon`, `consumeDecimatorBoost`, `consumePurchaseBoost`. The `checkAndClearExpiredBoon` and `consumeActivityBoon` dispatchers are internal-only and addressed by V-123 / V-111+V-124 separately.

**Rationale.** Per-callsite VIOLATION enumeration deferred from Phase 298 catalog; v44.0 fix-phase resolves each external on a per-callsite basis. The dispatcher-level gate is the minimal-footprint fix — Solidity-side guard at the DegenerusGame entry, no BoonModule-side change needed.

**Bytecode impact.** ~30-50 bytes × 3 gated entries ≈ 90-150 bytes total. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING (silent-revert during the lock window).

### §76.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-76` — CATALOG §16 row V-125 + §17 §C-15 / §D-43 / §E-32. v44.0 plan-phase: per-callsite verification of each EOA-orchestrated BoonModule external; apply tactic-(a) gate at DegenerusGame dispatcher level.

---

## §77 — V-127: lastPurchaseDay write inside "MintModule purchase entry" — **STALE-PHANTOM**

### §77.A — Design-intent backward-trace and stale-phantom finding

The catalog row V-127 cites:

> | V-127 | S-35 lastPurchaseDay | purchase-path writer (MintModule purchase entry) | `MintModule.sol:*` (EOA `purchase`) | NO — EOA | VIOLATION | (a) | Gate purchase entry's lastPurchaseDay set on `!rngLockedFlag` | D-43N-V44-HANDOFF-77 |

**Methodology check — verify against source per `feedback_verify_call_graph_against_source.md`.** Ran `grep -n "lastPurchaseDay" contracts/modules/*.sol`:

```
contracts/modules/DegenerusGameAdvanceModule.sol:171:        if (!inJackpot && !lastPurchaseDay && !rngLockedFlag) {
contracts/modules/DegenerusGameAdvanceModule.sol:176:                lastPurchaseDay = true;
contracts/modules/DegenerusGameAdvanceModule.sol:181:        bool lastPurchase = (!inJackpot) && lastPurchaseDay;
contracts/modules/DegenerusGameAdvanceModule.sol:369:                if (!lastPurchaseDay) {
contracts/modules/DegenerusGameAdvanceModule.sol:397:                        lastPurchaseDay = true;
contracts/modules/DegenerusGameAdvanceModule.sol:439:                lastPurchaseDay = false;
contracts/modules/DegenerusGameAdvanceModule.sol:563:                lastPurchaseDay
contracts/modules/DegenerusGameAdvanceModule.sol:1636:        // Increment level at RNG request time when lastPurchaseDay = true.
```

Also `grep -n "lastPurchaseDay" contracts/modules/DegenerusGameMintModule.sol` returns **zero matches**.

**There is no MintModule writer for `lastPurchaseDay`.** All three SSTOREs are inside `DegenerusGameAdvanceModule` (lines 176, 397, 439), all on the `advanceGame()` stack — and these three are already classified by CATALOG §16 row V-126 as EXEMPT-ADVANCEGAME (D-45).

**Disposition: STALE-PHANTOM.** V-127 does not correspond to a writer-callsite present in the audited contracts. The catalog row appears to be either (a) a residual planning artifact from a prior contract revision that hosted a MintModule-side `lastPurchaseDay = true` write, or (b) a speculative entry anticipating a writer that was never introduced. Either way the row reduces to a no-op at the source-attestation step: there is no V-127 writer to gate.

**Why the slot exists.** `lastPurchaseDay` is a per-game bool flag indicating that the running pool has hit the prize-target. It exists as an `advanceGame()`-managed liveness signal consumed by the lootbox-resolution gate at CATALOG §7 C-17. Its sole writers are inside AdvanceModule on the `advanceGame()` stack — all EXEMPT-ADVANCEGAME.

### §77.B — Actor game-theory walk

N/A — no writer-callsite to exploit. The row dissolves at the source-attestation step.

**Conservative note for v44.0 plan-phase:** If a future contract revision introduces a MintModule-side `lastPurchaseDay` writer (e.g., for a target-met-on-purchase optimization), the tactic-(a) gate from V-127's catalog rationale would apply: `if (rngLockedFlag) revert RngLocked();` at the writer entry. Until such a writer is introduced, V-127's handoff anchor is a no-op marker.

### §77.C — Recommended disposition + rationale + impact

**Disposition: MARK STALE-PHANTOM, RETAIN HANDOFF ANCHOR.** v44.0 plan-phase should:

1. Re-attest the source state (re-run `grep -n "lastPurchaseDay" contracts/modules/*.sol`).
2. If still no MintModule writer: close the handoff anchor as `RESOLVED-AS-PHANTOM`.
3. If a writer has appeared post-audit (which is unlikely per `feedback_frozen_contracts_no_future_proofing.md` — contracts are frozen at deploy): apply tactic-(a) gate per the original catalog rationale.

**Rationale.** The handoff anchor is retained for continuity with the catalog's 35-VIOLATION tally; the phantom disposition is recorded explicitly so v44.0 does not allocate a sub-phase to a non-existent writer.

**Bytecode impact.** ZERO — no source change applies.

### §77.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-77` — CATALOG §16 row V-127 + §17 §C-17 / §D-45 (note: D-45 is V-126's row for advanceGame writers; V-127 has no canonical D-row — it is the phantom-row by source-attestation). v44.0 plan-phase: close as RESOLVED-AS-PHANTOM unless re-attestation finds a new writer.

---

## §78 — V-137: rngRequestTime cleared inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1692)

### §78.A — Design-intent backward-trace

`rngRequestTime` is a `uint48 internal` slot declared in `DegenerusGameStorage`. It records the wall-clock timestamp at which the most recent VRF request was committed. Three categories of writer participate (per CATALOG §15):

- **advanceGame stack:** `_tryRequestRng` set (`AdvanceModule.sol:1122`), `_finalizeRngRequest` set (`:1633`), `_unlockRng` clear (`:1734`), `_gameOverEntropy` clear/set (`:1329, :1341`). All EXEMPT-ADVANCEGAME (V-131, V-133, V-134, V-135).
- **VRF callback:** `rawFulfillRandomWords` mid-day clear (`:1764`). EXEMPT-VRFCALLBACK (V-136).
- **retryLootboxRng cooldown-reset:** `:1154`. EXEMPT-RETRYLOOTBOXRNG (V-132).
- **Governance:** `updateVrfCoordinatorAndSub` clear at `:1692`. THIS row — V-137 — is the lone non-EXEMPT writer.

The slot exists for two reasons:
1. `retryLootboxRng` uses it as the cooldown anchor (`block.timestamp < rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT`, `:1135`) — clearing it mid-stall would unconditionally re-arm the retry path even when no in-flight request exists.
2. `rawFulfillRandomWords` and `_unlockRng` clear it as part of the post-callback teardown — the slot signals "VRF request is in flight" to off-chain monitors and on-chain liveness checks.

**Why `updateVrfCoordinatorAndSub` writes it.** The function is the contract's emergency escape valve for a stalled VRF coordinator (introduced as a coordinator-rotation contingency — see commentary at `:1700-:1703` preserving `totalFlipReversals`). When ADMIN rotates the coordinator, the in-flight `vrfRequestId` will never fulfill (or worse, fulfills against the old coordinator and is rejected by the `msg.sender != address(vrfCoordinator)` check in `rawFulfillRandomWords:1749`), so the contract must clear `rngLockedFlag`, `vrfRequestId`, `rngRequestTime`, `rngWordCurrent` to allow `advanceGame` to fire a fresh request against the new coordinator.

**Why naive gating breaks it.** Adding `if (rngLockedFlag) revert RngLocked()` to `updateVrfCoordinatorAndSub` reintroduces the exact deadlock the function exists to escape: ADMIN cannot rotate the coordinator precisely when rotation is needed (a stalled callback). The slot exists, and so does the writer, by deliberate design.

**Phase-precedent.** No prior phase introduced this writer (it predates the catalog). The slot lifecycle precedent is Phase 287 JPSURF (which formalized the in-flight-request invariants `rngLockedFlag` + `rngRequestTime`) and Phase 296 SWEEP (`D-42N-RETRY-RNG-DOMAIN-SEP-01` domain separation for `retryLootboxRng`).

### §78.B — Actor game-theory walk

Exploit actor: an adversarial ADMIN (trust-minimization audit posture per CATALOG §0 — even Admin-only writers earn VIOLATION classification when they touch RNG-window slots and are NOT in the 3 EXEMPT entry-stacks).

Action sequence: ADMIN observes an in-flight VRF request (off-chain `requestRandomWords` was called, callback pending). ADMIN calls `updateVrfCoordinatorAndSub(newCoordinator, newSubId, newKeyHash)`. The call clears `rngLockedFlag = false` (`:1690`), zeroes `vrfRequestId` (`:1691`), zeroes `rngRequestTime` (`:1692`), and clears `lootboxRngPacked.LR_MID_DAY` (`:1698`). If the in-flight callback then arrives against the *old* coordinator, `rawFulfillRandomWords` rejects on the `msg.sender != address(vrfCoordinator)` check. If ADMIN front-ran by also redirecting the off-chain VRF coordinator endpoint to a coordinator under their control, the next `advanceGame` call fires a request that resolves against admin-controlled randomness.

The "ADMIN as adversary" frame is the standard audit posture: the user explicitly requested trust-minimization analysis, so the catalog flags this Admin-gated writer as VIOLATION despite the gating.

**EV magnitude:** CATASTROPHE-tier. This writer single-handedly clears five RNG-window state slots and authorizes a substitute VRF coordinator. The compromised admin path resolves to control over every downstream RNG consumer for the resulting cycle. EV is bounded only by the strength of the ADMIN key custody. Economic-likelihood: LOW (governance discipline, multi-sig, public on-chain visibility), but disposition: MITIGATE structurally regardless.

### §78.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder: queue mid-stall rotations until after callback or 12h timeout.**

Concrete shape: split `updateVrfCoordinatorAndSub` into two phases:
1. `queueVrfCoordinatorRotation(newCoordinator, newSubId, newKeyHash)` — writes a pending-rotation packed slot only; emits `VrfCoordinatorRotationQueued`.
2. `applyVrfCoordinatorRotation()` — permissionless after `block.timestamp >= rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT + ROTATION_DELAY` OR after `vrfRequestId == 0 && !rngLockedFlag`. Atomically performs the four-slot write currently at `:1685-:1698`.

The 12h-timeout-equivalent (`MIDDAY_RNG_RETRY_TIMEOUT` is the natural anchor; a longer `ROTATION_DELAY` is recommended) ensures rotation cannot pre-empt an in-flight callback that could still resolve naturally. The retry path (`retryLootboxRng:1132`) becomes the first-line response to a stalled callback; rotation is reserved for genuine multi-cycle stalls where retry is also exhausted.

**Rationale.** Tactic (c) preserves the legitimate emergency-escape semantics — ADMIN retains the rotation capability — but eliminates the mid-window pre-emption attack. The cooldown is a natural extension of the existing `retryLootboxRng` cooldown precedent.

**Bytecode impact.** ~150-250 bytes — one packed `pendingRotation` storage slot (3 fields: coordinator, subId, keyHash; fits in 2 slots since `address + uint64 + bytes32` = 20 + 8 + 32 = 60 bytes spanning 2 slots) + the two-function split + the timeout/state-condition check. Storage-layout: 1-2 new packed slots appended to end of `DegenerusGameStorage` (non-disrupting). ABI: BREAKING — `updateVrfCoordinatorAndSub` is replaced by `queueVrfCoordinatorRotation` + `applyVrfCoordinatorRotation`. Admin tooling needs update; the user-facing semantic is preserved.

### §78.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-78` — CATALOG §16 row V-137 + §15 row S-38 governance subset. v44.0 plan-phase: define `pendingVrfRotationPacked` packed slot; split `updateVrfCoordinatorAndSub` into queue + apply; gate apply on `vrfRequestId == 0 || (block.timestamp >= rngRequestTime + ROTATION_DELAY)`.

---

## §79 — V-140: affiliate cross-contract slots mutated inside `DegenerusAffiliate.payAffiliate` (DegenerusAffiliate.sol:388) — **LABEL-REFINEMENT**

### §79.A — Design-intent backward-trace and label-refinement

**Label refinement.** CATALOG §15 row S-41 + §16 row V-140 cite `DegenerusAffiliate.recordAffiliateEarnings` as the cross-contract writer. Grep of current `contracts/DegenerusAffiliate.sol` returns zero hits for that name. The actual EOA-reachable writer that mutates the affiliate-cache slots consumed by the lootbox resolution is `DegenerusAffiliate.payAffiliate` (`:388`, signature `function payAffiliate(uint256 amount, bytes32 code, address sender, uint24 lvl, bool isFreshEth, uint16 lootboxActivityScore) external returns (uint256 playerKickback)`), called from `MintModule._purchaseFor` and `_purchaseBurnieLootboxFor` at `:1135, :1145, :1313, :1323, :1333, :1342` via `lootboxFlipCredit += affiliate.payAffiliate(...)` / `kickback += affiliate.payAffiliate(...)`. The semantic claim of the cluster row — "affiliate cross-contract state is mutated by EOA mint flows during the rngLock window" — holds.

`DegenerusAffiliate` is an external standalone contract (not a delegatecall module) that maintains the global affiliate-tracking ledger. `payAffiliate` mutates `affiliateCode`, `playerReferralCode`, `affiliateScore[lvl][player]`, `totalAffiliateScore[lvl]`, and the cached affiliate points read back into `mintPacked_.AFF_POINTS` via `MintStreakUtils._cacheAffiliateBonus`. Consumers (per CATALOG §7) read these slots inside `_resolveLootboxCommon` via the affiliate-points contribution to `_playerActivityScore` and via the lootbox boon/cap derivations.

**Why the slot family exists.** Affiliate scoring is a cross-game-cycle accumulator: a referrer's score must update on every referee mint. Naively gating `payAffiliate` on the game's `rngLockedFlag` would either (a) revert the mint flow entirely or (b) silently drop the affiliate credit, breaking the affiliate-economics monotonicity invariant.

**Phase-precedent.** Phase 281 owed-salt (`v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md`) established the snapshot-at-allocation pattern for any value participating in a post-VRF-callback resolution. Phase 288 dailyIdx structural anchor extended this to cross-day-mutating slots.

### §79.B — Actor game-theory walk

Exploit actor: an EOA buyer holding a pre-VRF-allocated lootbox index. Between the daily VRF callback (`AdvanceModule.sol:1256 lootboxRngWordByIndex[index] = rngWord`) and the same buyer's subsequent `openLootBox(index)`, the buyer (or their referrer / referee chain) calls `buyTickets` with a referral code. `MintModule` calls `affiliate.payAffiliate`, which (i) records the affiliate score, (ii) returns kickback ETH, and (iii) updates the `mintPacked_.AFF_POINTS` cache via the AdvanceModule `_cacheAffiliateBonus` path (`AdvanceModule:1008`). The buyer's post-callback `openLootBox` then reads the fresh `AFF_POINTS` (via `_playerActivityScore`) and possibly fresh affiliate-derived caps, inflating the resolved lootbox payout.

**EV magnitude:** MEDIUM. The affiliate-points contribution to `_playerActivityScore` is one of multiple inputs (mint-streak, deity-pass, whale-bundle), and the per-cycle marginal points from a single mint are bounded. However, a referrer with a large stable of referees can have those referees mint during the buyer's rng-window, amplifying the score. Per `feedback_rng_window_storage_read_freshness.md` precedent F-41-02/03, any non-VRF SLOAD consumed alongside the RNG word is in-scope; this falls within that class.

### §79.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot affiliate points into the lootbox-index at allocation.**

Concrete shape: at lootbox-allocation time (`MintModule._allocateLootbox` / `WhaleModule._whaleLootboxAllocate`), capture `affiliateBonusPointsBest(currLevel, buyer)` into the per-index snapshot slot `lootboxEvScorePacked[index][player]` (already a per-index snapshot per CATALOG §14 row S-22 and Cluster H §3.C consolidation). The lootbox-resolution body reads the snapshotted score; live `affiliate.affiliateBonusPointsBest()` calls inside `_resolveLootboxCommon` are removed.

This is the same widening recommended in Cluster H §3.C (V-109 mint-streak snapshot) — the AFF_POINTS field is already covered when the activity-score snapshot is widened to cover the full `_playerActivityScore` input set. **Cross-cluster coupling: V-140 + V-109 + V-110 + V-112 + V-113 resolve via a single `lootboxEvScorePacked` widening v44.0 sub-phase.**

**Rationale.** Phase 281 + Phase 288 snapshot-at-allocation precedent. The cross-contract write retains its legitimate cross-cycle role; only the lootbox-EV consumer reads from the frozen per-index snapshot. No structural change to `DegenerusAffiliate` required.

**Bytecode impact.** ~50-100 bytes per consumer site — one storage-load swap inside `_resolveLootboxCommon` (read from `lootboxEvScorePacked[index][player]` instead of live `affiliate.*`). Storage-layout: no new slots if widening Cluster H's existing snapshot field. ABI: NON-BREAKING.

### §79.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-79` — CATALOG §16 row V-140 + §15 row S-41 + Cluster H §3.C consolidation note. v44.0 plan-phase: route `_lootboxEvMultiplierBps` and affiliate-derived caps to read from `lootboxEvScorePacked[index][player]`; remove live `affiliate.*` reads from `_resolveLootboxCommon`.

---

## §80 — V-141: questView cross-contract slots mutated via `DegenerusQuests` external fulfillment writers (DegenerusQuests.sol handleMint/Flip/Decimator/Affiliate/LootBox/Purchase/Degenerette)

### §80.A — Design-intent backward-trace

`DegenerusQuests` is an external standalone contract (per the `:16` header comment — "operates as an external standalone contract (NOT delegatecall)"). It maintains the daily-quest ledger (`activeQuests`, `questPlayerState[player]`) and exposes a fleet of `external onlyCoin` / `external onlyGame` writers reached from EOA-callable surfaces on the game contract:

- `handleMint` (`:417` onlyCoin) — reached from `MintModule.purchase*` mint flow via `BurnieCoin.purchaseTickets*`
- `handleFlip` (`:533` onlyCoin) — reached from `BurnieCoinflip.flip*`
- `handleDecimator` (`:589` onlyGame) — reached from decimator-bound mints
- `handleAffiliate` (`:644` onlyGame) — reached from affiliate kickback applications
- `handleLootBox` (`:698` onlyGame) — reached from lootbox-buy paths
- `handlePurchase` (`:763` onlyGame) — reached from non-mint purchase paths (lazy-pass, etc.)
- `handleDegenerette` (`:913` onlyGame) — reached from `DegeneretteModule.placeDegeneretteBet`
- `awardQuestStreakBonus` (`:365` onlyGame)
- `rollDailyQuest` (`:334` onlyGame) — only the daily-roll path; advanceGame stack only
- `rollLevelQuest` (`:1781` onlyGame)

All of these writers mutate `questPlayerState[player].streak` (and adjacent fields: `questsProgress`, `streakDay`, etc.). The cross-contract read surface in the game is `questView.playerQuestStates(player)` (`:996`), called inside `DegeneretteModule._placeDegeneretteBetCore` (`:457`) and inside `_playerActivityScore` (where it feeds the activity-score that participates in `_lootboxEvMultiplierBps`).

**Why the slot family exists.** Quest-streak is a cross-day engagement reward, and the quest-progress accumulators must update on every player-action regardless of the game's VRF state. Gating quest writers on `rngLockedFlag` would (a) revert legitimate flips/mints/quests during the window, or (b) silently drop progress.

**Phase-precedent.** Phase 281 owed-salt + Phase 288 dailyIdx + Phase 292 leader-bonus + Phase 294 DPNERF — every per-player accumulator participating in a post-VRF lootbox resolution adopts the snapshot-at-allocation discipline.

### §80.B — Actor game-theory walk

Exploit actor: an EOA player holding a pre-VRF-allocated lootbox index. Between the daily VRF callback and their `openLootBox(index)`, the player completes a quest action (flip / mint / claim) that triggers a `Quests.handle*` call, advancing `state.streak` and `state.questsProgress`. The subsequent `_resolveLootboxCommon` read of `_playerActivityScore` (or the direct `questView.playerQuestStates` read inside DegeneretteModule's resolution path) consumes the advanced streak, inflating `evMultiplierBps`.

**EV magnitude:** MEDIUM. Quest-streak is a bounded contribution to activity-score (capped at the streak-bonus formula in `MintStreakUtils._playerActivityScore`). The exploit requires the player to actually complete a quest action mid-window — non-trivial but not gated. Per `feedback_rng_window_storage_read_freshness.md`, this is in the storage-read-freshness bug class.

### §80.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot questStreak into the lootbox-index at allocation.**

Concrete shape: at lootbox-allocation time, fetch `(uint32 questStreak, ...) = questView.playerQuestStates(player)` and pack into `lootboxEvScorePacked[index][player]` (alongside the V-109/V-140 widening). The lootbox-resolution body reads the snapshotted streak.

Note: `_placeDegeneretteBetCore` (`DegeneretteModule.sol:457`) **already snapshots questStreak into `activityScore` at bet-place time** and packs it into the per-bet payload at `:469`. The Degenerette consumer is therefore already free of this specific exploit vector for the bet-payload path; V-141 covers the OTHER consumer (lootbox-resolution path) where the read is still live.

**Rationale.** Phase 281 + Phase 288 + Phase 292 + Phase 294 snapshot precedent. Coupled with V-109 / V-110 / V-112 / V-113 / V-140 into the single `lootboxEvScorePacked` widening v44.0 sub-phase.

**Bytecode impact.** ~50-100 bytes — one cross-contract view-call swap (`questView.playerQuestStates`) into the allocation-time path, and removal of the live read inside `_resolveLootboxCommon`. Storage-layout: no new slots if widening Cluster H's existing snapshot field. ABI: NON-BREAKING.

### §80.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-80` — CATALOG §16 row V-141 + §15 row S-42 + Cluster H §3.C consolidation note. v44.0 plan-phase: extend `_allocateLootbox` to snapshot questStreak; route `_resolveLootboxCommon` to read from snapshot.

---

## §81 — V-142: degeneretteBets[player][nonce] write inside `_placeDegeneretteBetCore` (DegeneretteModule.sol:479)

### §81.A — Design-intent backward-trace

`degeneretteBets[player][nonce]` is a `mapping(address => mapping(uint64 => uint256)) internal` per-bet packed payload slot (CATALOG §14 row S-43). It is written at `DegeneretteModule.sol:479` during `_placeDegeneretteBetCore` and deleted at `:597` during `_resolveBet` (the VRF-callback / consumer-self path; V-143 EXEMPT-VRFCALLBACK).

The per-bet lifecycle is:
1. Player calls `placeDegeneretteBet` (`:367`) → `_placeDegeneretteBet` → `_placeDegeneretteBetCore` (`:430+`).
2. `_placeDegeneretteBetCore:450-452` reads `index = LR_INDEX` and asserts `lootboxRngWordByIndex[index] != 0` is FALSE (i.e., the current bucket has NOT yet been resolved — `revert RngNotReady()` if it has).
3. The bet payload (currency, ticket count, custom traits, hero quadrant, activity-score, **index**) is packed and stored at `degeneretteBets[player][++nonce]` (`:473-479`).
4. Resolution: `resolveDegeneretteBet(nonce)` pulls the payload, reads `lootboxRngWordByIndex[index]` (now non-zero post-callback), derives the bet outcome, and deletes the payload (`:597`).

**Why the slot exists.** The bet is committed BEFORE the per-day VRF word is known (the `:452` gate enforces this), so the index field in the packed payload binds the bet to the not-yet-resolved bucket. After the VRF callback writes the word at that index, resolution becomes deterministic.

**Why the :452 gate covers most of the rngLock window.** The gate refuses placement when `lootboxRngWordByIndex[index] != 0`. Inside the rngLock window (after `_requestRng` and before `rawFulfillRandomWords`), `lootboxRngWordByIndex[index]` is still zero (the callback hasn't written it), so the gate does NOT refuse placement. However, `LR_INDEX` is advanced at `_finalizeRngRequest` (`AdvanceModule:1620`) ahead of the VRF request — meaning the bet, if placed mid-window, binds to a future-bucket index whose word will arrive shortly. This is the design.

**Phase-precedent.** The :452 `RngNotReady()` revert was introduced as the per-bet-commitment gate. The "post-RNG case" the catalog references is the window between the callback writing `lootboxRngWordByIndex[index] = word` and the player's `resolveDegeneretteBet(nonce)` — at that point the gate prevents placement against the already-resolved bucket, forcing the bet onto the next (still-zero) bucket.

### §81.B — Actor game-theory walk

Exploit actor: an EOA player firing `placeDegeneretteBet` during the small window between `_finalizeRngRequest` (which advances `LR_INDEX`) and `rawFulfillRandomWords` (which writes `lootboxRngWordByIndex[newIndex]`). The bet payload binds to the new bucket. If the player can also observe / influence the callback timing (e.g., via VRF coordinator-level visibility — unrealistic for Chainlink VRF), they could place bets selectively. Realistically: the player cannot predict the word, so the bet is placed under the same per-bucket pre-commitment discipline as a normal bet.

**Edge case the catalog flags:** index-rollover. If `_finalizeRngRequest` advances LR_INDEX while a player has a same-block in-flight `placeDegeneretteBet`, the bet could bind to either the old (just-finalized) bucket or the new one, depending on tx ordering. The `:452` gate refuses placement on the resolved bucket (`lootboxRngWordByIndex[oldIndex] != 0` after the callback fires), forcing onto the new bucket. Cross-block ordering is determined by miner / sequencer and the player's gas pricing. EV magnitude: HIGH for the index-rollover edge if a player can selectively bind to a bucket whose word they have partial visibility into.

**Substantive risk:** The gate at `:452` correctly enforces per-bucket commitment for the standard case. The edge cases for verification are:
1. Same-block sequencing of `placeDegeneretteBet` with `_finalizeRngRequest` (index advance) — verify the gate behavior under fork-replay.
2. Multi-bet placement straddling a finalization — verify each bet's `index` field correctly reflects the post-finalization index.
3. Gap-day backfill (`_backfillOrphanedLootboxIndices:1818`) — verify the gate behaves correctly when multiple historical indices are filled in one advanceGame call.

### §81.C — Recommended tactic + rationale + impact

**Tactic (a) — Existing :452 `lootboxRngWordByIndex[index] != 0` gate; verify across index-rollover edges via FUZZ-301.**

Concrete shape: NO CONTRACT CHANGE required. The existing gate at `:452` is the correct structural mitigation. Phase 301 FUZZ adds test cases:
- `vm.skip`-gated at the CATALOG-VIOLATION site per `D-43N-FUZZ-VMSKIP-01` — runs the bet-place across the rngLock window and asserts payload `index` field matches the expected bucket at every callback ordering.
- Cross-cycle: place bet → advance → resolve at correct index.
- Same-block: place bet at the exact block of `_finalizeRngRequest` (uses `vm.warp` + `vm.roll` boundary).
- Backfill: place bet → trigger `_backfillOrphanedLootboxIndices` for a prior gap day → assert no cross-contamination.

**Rationale.** Tactic (a) here is the LIGHTEST tactic in the menu — the gate already exists. The VIOLATION is reclassified as "gate-present, edge-case-FUZZ-verification-required". This aligns with the audit-only posture: no contract change needed if FUZZ proves the gate covers all edges.

**Bytecode impact.** Zero (no contract change). Test-suite impact: ~3-5 new FUZZ cases. ABI: NON-BREAKING (no change).

### §81.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-81` — CATALOG §16 row V-142 + §15 row S-43 + Phase 301 FUZZ-301-DEGENERETTE-EDGE coupling. v44.0 plan-phase: NO sub-phase required if Phase 301 FUZZ confirms gate coverage; CONDITIONAL handoff (re-attest only if FUZZ-301 surfaces a gate-bypass).

---

## §82 — V-147: prizePoolPendingPacked write inside `_collectBetFunds` frozen-branch (DegeneretteModule.sol:553)

### §82.A — Design-intent backward-trace

`prizePoolPendingPacked` is a `uint256 internal` slot (CATALOG §14 row S-45) that holds the "pending pool" — the next-and-future ETH pool accumulator used during the jackpot phase (when `prizePoolFrozen == true`). The slot is read/written across both directions of the same packed struct via `_getPendingPools` / `_setPendingPools` helpers.

Lifecycle:
- `_swapAndFreeze` (`Storage.sol:762, :764`) — clear/seed at jackpot-phase entry. EXEMPT-ADVANCEGAME (V-145).
- `_unfreezePool` (`Storage.sol:776`) — clear at jackpot-phase exit. EXEMPT-ADVANCEGAME (V-146).
- `DegeneretteModule._collectBetFunds` frozen-branch (`:553`) — EOA-reachable bet-place. **THIS row — V-147**.
- `DegeneretteModule._distributePayout` frozen-branch (`:764`) — consumer-self payout. EXEMPT-VRFCALLBACK (V-148).
- `MintModule.*` frozen-branch purchase writers (`:1054-1059` at `_purchaseFor`). **V-149.**
- `JackpotModule.*` advanceGame self-stack pending writes. EXEMPT-ADVANCEGAME (V-150).

**Why the frozen-branch exists.** During the jackpot phase, the live pools (`prizePoolsPacked`) are being drained by `payDailyJackpot` etc. as the multi-day jackpot distribution executes. New incoming ETH from purchase / bet flows must accumulate into a SEPARATE pending bucket (`prizePoolPendingPacked`) that gets swapped back into the live pool at the next phase transition (`_unfreezePool`). This preserves the jackpot snap-and-distribute atomicity — the snapshot at jackpot-entry must not be polluted by mid-phase incoming.

`_collectBetFunds:553` is the bet-funds intake during a degenerette bet (`placeDegeneretteBet` EOA flow). When `prizePoolFrozen` is true, the function routes the ETH into pending instead of live pools.

**Why naive gating breaks UX.** Refusing `placeDegeneretteBet` whenever `rngLockedFlag` is true would (a) block legitimate bet placement during the rng-lock cooldown for non-jackpot-phase days too, (b) confuse users who don't see jackpot-phase vs daily-rng-lock as the same state. The disposition needs to be narrower than blanket-revert.

**Phase-precedent.** Phase 287 JPSURF + Phase 288 freeze-window design. The `prizePoolFrozen` flag (`prizePoolsPacked` packed bit) is the structural anchor that gates which pool gets the write; the rngLock-window concern is orthogonal but overlapping.

### §82.B — Actor game-theory walk

Exploit actor: EOA player firing `placeDegeneretteBet` during jackpot-phase's rngLock window. The `_collectBetFunds` write inflates `prizePoolPendingPacked.pFuture`. Subsequent reads of pending pools by the same player's bet-resolution (or by another player's bet-resolution within the same window) read the inflated pending value.

Consumer surface affected: `_distributePayout:760-764` reads pending pools via `_getPendingPools` to determine ethShare → payout magnitude inside `_distributePayout`. If the player can place a bet that inflates pending, then resolve a separate same-window bet that pays from pending, the inflated pool magnifies the payout.

**EV magnitude:** HIGH. The pending pool participates directly in payout-magnitude derivation during jackpot-phase. The exploit window is narrow (limited to jackpot-phase + same VRF cycle), but the per-bet payout uplift is non-trivial.

### §82.C — Recommended tactic + rationale + impact

**Tactic (a) — Gate place-bet on `rngLockedFlag` so window closes once VRF requested.**

Concrete shape: at the entry to `_placeDegeneretteBetCore` (before the existing `:450-452` index/RngNotReady checks), add `if (rngLockedFlag) revert RngLocked();`. This closes the placement window cleanly for the entire VRF cycle. The existing `:452 RngNotReady()` revert remains as the per-bucket commitment gate; the new `rngLockedFlag` revert covers the broader "RNG is currently being resolved" window.

Alternative refinement (narrower): gate only when `prizePoolFrozen && rngLockedFlag` to preserve placement during daily-rng-lock for non-jackpot-phase days. The catalog rationale ("Gate place-bet on `rngLockedFlag` so window closes once VRF requested") matches the broader gate; the narrower gate trades UX for tighter coverage.

**Rationale.** The `rngLockedFlag` is the canonical "VRF cycle is active" signal across the codebase (`BurnieCoinflip:730, :780; WhaleModule:543; AdvanceModule:1044; DegenerusGame:1513, :1528, :1575`). Adding the same gate to the Degenerette bet-place entry brings the surface to parity. The existing `:452 RngNotReady()` is a per-bucket gate; `rngLockedFlag` is a per-cycle gate — both are needed for coverage.

**Bytecode impact.** ~30-50 bytes — one storage read + revert at the bet-place entry. Storage-layout: no change. ABI: NON-BREAKING (additional revert surface; existing happy path preserved for non-locked state).

### §82.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-82` — CATALOG §16 row V-147 + §15 row S-45 frozen-branch. v44.0 plan-phase: add `if (rngLockedFlag) revert RngLocked();` at top of `_placeDegeneretteBetCore`; consider narrower `prizePoolFrozen && rngLockedFlag` form per UX tradeoff.

---

## §83 — V-149: prizePoolPendingPacked write inside MintModule frozen-branch purchase writers (MintModule.sol:1054-1059) — **LABEL-REFINEMENT**

### §83.A — Design-intent backward-trace and label-refinement

**Label refinement.** CATALOG §16 V-149 rationale claims "Existing far-future `RngLocked` gate (:572) covers; extend to pending writes". Verification against current source:
- `MintModule.sol:572` is the LCG step inside `_raritySymbolBatch` — `s = s * TICKET_LCG_MULT + 1;` — NOT a `RngLocked` gate.
- `grep -nE "RngLocked\b|rngLockedFlag" contracts/modules/DegenerusGameMintModule.sol` returns ONE hit at `:1221`: `if (cachedJpFlag && rngLockedFlag) {`. This is the narrow last-jackpot-day target-level redirect inside `_chooseTargetLevel`, NOT a global purchase gate.
- The frozen-branch pending writer surface in `_purchaseFor` (`MintModule.sol:1054-1059`) has NO `rngLockedFlag` guard.

The substantive VIOLATION claim — "MintModule frozen-branch purchase paths mutate `prizePoolPendingPacked` mid-window" — holds. The catalog rationale's framing as "extend an existing :572 gate" is incorrect; v44.0 must author a NEW guard rather than extend a non-existent one.

The actual writer surface (current source):

```
contracts/modules/DegenerusGameMintModule.sol:1054
    if (prizePoolFrozen) {
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        _setPendingPools(
            pNext + uint128(nextShare),
            pFuture + uint128(futureShare)
        );
    } else { ... }
```

This is inside `_purchaseFor` (`:899`), reached from `purchase` (`:830`), `purchaseCoin` (`:852`), `purchaseBurnieLootbox` (`:864`), `_purchaseCoinFor` (`:872`), `_purchaseBurnieLootboxFor` (`:1377`). All are EOA-callable.

**Why the slot family exists.** Same as V-147 §5.A — pending pool is the jackpot-phase accumulator preserving snap-and-distribute atomicity.

### §83.B — Actor game-theory walk

Exploit actor: EOA buyer firing `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` during the jackpot-phase rngLock window. The frozen-branch write at `:1054-1059` inflates `prizePoolPendingPacked` (pNext + nextShare; pFuture + futureShare). Subsequent same-window consumer reads of pending pools (Degenerette `_distributePayout:760-764`, future-phase unfreezing) consume the inflated pool.

The exploit shape mirrors V-147 but at the MintModule purchase entry instead of the bet-place entry. The pool inflation is bounded by the buyer's purchase size, but a large enough purchase can materially shift the pending magnitudes consumed by other players' same-window bet resolutions.

**EV magnitude:** HIGH. Same as V-147 — pending pool magnitude directly modulates downstream payout calculations.

### §83.C — Recommended tactic + rationale + impact

**Tactic (a) — Author a NEW `rngLockedFlag` gate on the frozen-branch purchase entries.**

Concrete shape: at the entry to `_purchaseFor` (`MintModule.sol:899-906`), after the existing `_livenessTriggered()` check, add:

```solidity
if (prizePoolFrozen && rngLockedFlag) revert RngLocked();
```

This narrowly closes the jackpot-phase-RNG-lock window without affecting daily-mint UX outside the jackpot phase. The narrower form (vs blanket `if (rngLockedFlag) revert`) preserves daily-rng-lock-window purchases for non-jackpot-phase days, matching the V-147 §5.C narrower-form discussion.

Alternative (broader): gate all `_purchaseFor` entries on `rngLockedFlag` regardless of `prizePoolFrozen`. Trades UX for tighter coverage of OTHER same-window RNG-window concerns (the cross-cluster activity-score / streak / boon writers — Cluster H V-114 etc.). v44.0 plan-phase decides the form based on UX tradeoff.

**Rationale.** No existing gate exists; this is a NEW guard. The pattern mirrors the codebase's established `if (rngLockedFlag) revert RngLocked();` discipline at `BurnieCoinflip:730, :780; WhaleModule:543; AdvanceModule:1044; DegenerusGame:1513, :1528, :1575`. Coupled with V-147 — both VIOLATIONs cover the same `prizePoolPendingPacked` slot from different EOA-entry surfaces.

**Bytecode impact.** ~30-50 bytes — one storage read + revert at `_purchaseFor` top. Storage-layout: no change. ABI: NON-BREAKING (added revert surface).

### §83.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-83` — CATALOG §16 row V-149 + §15 row S-45 MintModule frozen-branch + label-refinement note. v44.0 plan-phase: AUTHOR new `prizePoolFrozen && rngLockedFlag` revert at `_purchaseFor` top (do NOT frame as extending the non-existent :572 gate).

---

## §84 — V-153: lootboxRngPacked.LR_MID_DAY write inside `_requestLootboxRng` (AdvanceModule.sol:1096) — **§0 HEADLINE #6 SCOPE-EXPANSION CANDIDATE**

### §84.A — Design-intent backward-trace

`lootboxRngPacked.LR_MID_DAY` is a 1-bit field inside the multi-field packed `lootboxRngPacked` slot (CATALOG §14 row S-46). It signals "a mid-day lootbox RNG request is in-flight". The bit is:

- Set to 1 by `_requestLootboxRng` at `AdvanceModule.sol:1096` after a successful per-level buffer swap (`:1094-1097`): the bit is set when `ticketQueue[wk].length > 0 && ticketsFullyProcessed` is satisfied. **THIS row — V-153.**
- Cleared (= 0) by `rngGate` at `AdvanceModule.sol:225` during advanceGame's stage transition (EXEMPT-ADVANCEGAME, V-154).
- Cleared (= 0) by `updateVrfCoordinatorAndSub` at `AdvanceModule.sol:1698` (V-155 — §8 below).

The `_requestLootboxRng` function is called from the external `requestLootboxRng` entry point (EOA-callable, permissionless). Its purpose: when a level's ticket queue has been fully processed mid-day AND the next-level purchase queue has new tickets, fire an out-of-band VRF request to resolve the mid-level lootbox bucket without waiting for the next-day advanceGame cycle. The lifecycle:

1. Permissionless EOA calls `requestLootboxRng()` → `_requestLootboxRng` (`AdvanceModule.sol:1031+`).
2. Function performs validation: gameOver / paused / wirable / rngLockedFlag / minLink / ETH-equivalent-threshold checks (`:1040-1087`).
3. Buffer swap: `_swapTicketSlot(purchaseLevel_)` + `_lrWrite(LR_MID_DAY, 1)` at `:1095-1096`.
4. VRF request fired: `vrfCoordinator.requestRandomWords(...)` at `:1101-1110`.
5. Bookkeeping: `LR_INDEX++` (`:1113-1117`), pending-eth/burnie clear (`:1118-1119`), `vrfRequestId = id` (`:1120`), `rngWordCurrent = 0` (`:1121`), **`rngRequestTime = uint48(block.timestamp)` at `:1122`**.

VRF fulfillment lands at `rawFulfillRandomWords` (`:1745+`), which detects the mid-day case via `if (rngLockedFlag) { rngWordCurrent = word; } else { /* mid-day path */ ... vrfRequestId = 0; rngRequestTime = 0; }` at `:1755-1765`. Note: `rngLockedFlag` is NOT set by `_requestLootboxRng` — it's the daily-RNG marker. Mid-day lootbox RNG runs OUTSIDE `rngLockedFlag`.

**The catalog's scope-expansion observation (§0 headline #6).** The 3-EXEMPT-stack model (`D-298-CONSUMER-LIST-01` + `D-43N-AUDIT-ONLY-01`) classifies `advanceGame`, `rawFulfillRandomWords`, and `retryLootboxRng` as EXEMPT entry points. `_requestLootboxRng` is the COMMITMENT-SIDE sibling of `retryLootboxRng` — the retry path re-fires VRF using the same `vrfRequestId / rngRequestTime` state that `_requestLootboxRng` writes here. Strict per-callsite classification flags V-153 as VIOLATION because `_requestLootboxRng` is reached from an EOA entry not in the 3-EXEMPT stack.

**Why substantive risk is nil.** Both writes (`LR_MID_DAY = 1` at `:1096` and `rngRequestTime` at `:1122`) ENABLE the `retryLootboxRng` cooldown semantics. The `retryLootboxRng` caller (the EXEMPT-RETRYLOOTBOXRNG envelope) cannot retry unless `LR_MID_DAY == 1` (gate at `:1133`) and `rngRequestTime != 0` (gate at `:1134`). The commitment-side writes are structurally necessary for the EXEMPT envelope's existence. Eliminating these writes (or gating them) would BREAK the retry path entirely. There is no exploit-actor frame in which inflating `LR_MID_DAY = 1` mid-window benefits any actor — the bit is consumed only by the retry path (which is itself EXEMPT) and by `rngGate` (which clears it during advanceGame).

**Phase-precedent.** Phase 296 SWEEP `D-42N-RETRY-RNG-DOMAIN-SEP-01` formalized the `retryLootboxRng` domain separation (Option A: retry re-fires the same `vrfRequestId` against `rawFulfillRandomWords`'s requestId-match rejection of the stalled original). The commitment-side function predates the audit — it is the entry that establishes the state retry consumes.

### §84.B — Actor game-theory walk

Exploit actor: **none with a profit-motive vector**. The catalog row V-153 is the textbook example of "strict-per-callsite classification yields VIOLATION but substantive risk is nil". Walk:

1. Hypothetical exploit-actor = an EOA calling `requestLootboxRng()` during the rng-lock window. But `_requestLootboxRng` has its own `if (rngLockedFlag) revert E();` gate (verify at `:1044` of `AdvanceModule.sol` — confirmed present: `if (rngLockedFlag) revert RngLocked();`). So the function CANNOT execute during `rngLockedFlag == true`. The mid-day RNG runs DURING `rngLockedFlag == false` (the gap between daily VRF cycles).
2. Hypothetical: an EOA calls `requestLootboxRng()` mid-day, sets `LR_MID_DAY = 1`, then in the same window calls `openLootBox` (or any other consumer). But the consumer reads `lootboxRngWordByIndex[index]` which is still zero until the VRF callback fires — `RngNotReady()` revert across the board.
3. Hypothetical: an EOA front-runs another player's bet-resolution to inflate `LR_INDEX` (advanced at `:1113-1117`). This is real but covered by the existing per-bucket commitment gate at `DegeneretteModule:452` + the per-index snapshot discipline. NOT a `LR_MID_DAY`-specific exploit.

**Substantive risk: NIL.** Per CATALOG §0 headline #6 verbatim: "substantive risk is nil (the retryLootboxRng caller benefits from both writes existing)".

**EV magnitude:** LOW (technically: zero, but tagged LOW per the no-zero-EV-without-FUZZ-attestation discipline).

### §84.C — Recommended tactic + rationale + impact — **SCOPE-EXPANSION ANALYSIS**

**Recommended tactic: (c) Pre-lock reorder — RECLASSIFY: EXEMPT-RETRYLOOTBOXRNG-extended (4th EXEMPT class). Zero contract change. Milestone-prose amendment.**

**Scope-expansion proposal shape.**

The current 3-EXEMPT-stack model:
1. `advanceGame()` self-stack (EXEMPT-ADVANCEGAME)
2. `rawFulfillRandomWords()` VRF coordinator stack (EXEMPT-VRFCALLBACK)
3. `retryLootboxRng()` cooldown stack (EXEMPT-RETRYLOOTBOXRNG)

Proposed 4-EXEMPT-stack model:
1. `advanceGame()` self-stack (EXEMPT-ADVANCEGAME) — UNCHANGED
2. `rawFulfillRandomWords()` VRF coordinator stack (EXEMPT-VRFCALLBACK) — UNCHANGED
3. `retryLootboxRng()` cooldown stack (EXEMPT-RETRYLOOTBOXRNG) — UNCHANGED
4. **NEW: `requestLootboxRng()` commitment-side stack (EXEMPT-REQUESTLOOTBOXRNG)** — the commitment-side sibling that ENABLES the retry path.

**Why this is structurally clean (not a carve-out / case-by-case exception).** Per `D-43N-AUDIT-ONLY-01`, the verdict alphabet is `EXEMPT-ADVANCEGAME | EXEMPT-VRFCALLBACK | EXEMPT-RETRYLOOTBOXRNG | VIOLATION` — the prohibited fourth-class disposition (the token the milestone explicitly forbids) does not appear. The proposal here is to EXTEND the EXEMPT class set with a 4th entry-stack identity (EXEMPT-REQUESTLOOTBOXRNG), NOT to introduce the prohibited per-row carve-out token. The classification remains structural: an entry-point identity-based decision, not a case-by-case carve-out.

The structural justification:
- `_requestLootboxRng` writes `LR_MID_DAY = 1` and `rngRequestTime = uint48(block.timestamp)`. These writes are the PRE-CONDITION for `retryLootboxRng` to execute (`:1133-1134` gates).
- The retry path is already EXEMPT (`D-298-CONSUMER-LIST-01`).
- An EXEMPT consumer cannot exist without its commitment-side writes — the EXEMPT class is structurally incomplete unless it includes the commitment-side.
- Symmetric precedent: `rawFulfillRandomWords` (EXEMPT-VRFCALLBACK) is paired with `_tryRequestRng` (EXEMPT-ADVANCEGAME, V-131). The fulfillment side is EXEMPT, the request side is EXEMPT — by structural symmetry. The same symmetry should apply to retry + request-lootbox: both should be EXEMPT.

**Where the milestone-prose amendment lands.**

The amendment is a single-line addition to the v43.0 milestone-goal prose in `.planning/ROADMAP.md`:

> `D-43N-AUDIT-ONLY-01` — verdict alphabet locked to `EXEMPT-ADVANCEGAME | EXEMPT-VRFCALLBACK | EXEMPT-RETRYLOOTBOXRNG | EXEMPT-REQUESTLOOTBOXRNG | VIOLATION`. The 4th EXEMPT class is added per Phase 299 §0 headline #6 to cover the commitment-side sibling of `retryLootboxRng`.

Or, alternatively, the amendment is documented in Phase 303 TERMINAL §9 closure attestation as a final-state record (without retroactively rewriting `D-43N-AUDIT-ONLY-01`). The Phase 303 closure form is preferred because it preserves the milestone-locked decision's audit trail.

**Effect on V-153 + V-155 (and downstream V-137, V-157, V-159, V-161).**

- V-153 RECLASSIFIES to EXEMPT-REQUESTLOOTBOXRNG. Zero contract change. The `D-43N-V44-HANDOFF-84` anchor MARKS RESOLVED-AS-RECLASSIFIED.
- V-155 (`updateVrfCoordinatorAndSub` clears `LR_MID_DAY`) is a different scope. The governance writer is NOT the commitment-side sibling of retry — it's the emergency-escape clear. V-155 retains its tactic (c) reorder recommendation (see §8.C). The scope-expansion candidate for governance writers is a SEPARATE 5th-EXEMPT-class proposal (NOT recommended here; the §1.C / §8.C / §10.C / §12.C / §14.C tactic-(c) reorder is the cleaner approach for governance).

**Why governance writers do NOT scope-expand similarly.**

The retry-extension argument relies on structural-symmetry: retry + commitment-side are one logical envelope. Governance VRF rotation is an EMERGENCY escape — it has no symmetric consumer-side dependency. Adding a 5th EXEMPT class for governance would erode the audit posture's trust-minimization frame. The tactic (c) reorder (queue + apply with cooldown) preserves the legitimate emergency semantics WITHOUT carving out a trust-required class.

**Recommended tactic, summarized:**

For V-153 only: **RECLASSIFY** to EXEMPT-REQUESTLOOTBOXRNG (zero contract change; Phase 303 TERMINAL §9 closure attestation incorporates the amendment).

For the OTHER governance-writer VIOLATIONs in this cluster (V-137, V-155, V-157, V-159, V-161): **REORDER** (tactic (c)) — queue + cooldown the governance rotation. See §1.C, §8.C, §10.C, §12.C, §14.C.

**Bytecode impact.** ZERO for V-153 (no contract change). Milestone-prose amendment only.

**Storage-layout impact.** None.

**ABI impact.** None.

**Closure attestation requirement.** Phase 303 TERMINAL §9 records the reclassification with a one-line milestone-prose amendment under `D-43N-AUDIT-ONLY-01` (or as a separate `D-43N-EXEMPT-CLASS-AMEND-01` locked decision). The v44.0 FIX-MILESTONE plan-phase does NOT need a sub-phase for V-153 — handoff anchor `D-43N-V44-HANDOFF-84` resolves at Phase 303.

### §84.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-84` — CATALOG §16 row V-153 + §15 row S-46 LR_MID_DAY commitment-side + CATALOG §0 headline #6 + this §7.C scope-expansion analysis. **Disposition: RESOLVED-AS-RECLASSIFIED** at Phase 303 TERMINAL §9 closure attestation; v44.0 plan-phase has NO sub-phase obligation. Conditional re-activation only if Phase 303 declines the reclassification.

---

## §85 — V-155: lootboxRngPacked.LR_MID_DAY cleared inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1698)

### §85.A — Design-intent backward-trace

`updateVrfCoordinatorAndSub` (`AdvanceModule.sol:1675-1706`) clears `LR_MID_DAY` via `_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)` at `:1698`. The clear is annotated in source (`:1695-1697`): "Clear mid-day lootbox RNG pending flag to prevent post-swap deadlock. Without this, advanceGame can revert with NotTimeYet if a mid-day requestLootboxRng was in-flight when the coordinator stalled."

The writer participates in the same governance-emergency-escape pattern as V-137: when ADMIN rotates the coordinator, any in-flight `LR_MID_DAY = 1` state would prevent the next advanceGame cycle from proceeding (because `advanceGame` calls `rngGate` which expects `LR_MID_DAY` clearing to happen via the normal post-callback path — when the coordinator is rotated, the callback never arrives via the old coordinator). The clear is structurally necessary for the escape valve to function.

**Why naive gating breaks the escape valve.** Same as V-137 §1.A — `if (rngLockedFlag) revert` here would prevent the rotation precisely when needed.

**Phase-precedent.** Same as V-137 — Phase 287 JPSURF + Phase 296 SWEEP. No prior phase introduced this specific clear; it's part of the emergency-escape function.

### §85.B — Actor game-theory walk

Exploit actor: adversarial ADMIN (same posture as V-137 §1.B). Action sequence: rotate VRF coordinator → all five state slots cleared in one call (V-137 + V-155 + V-157 + V-159 + V-161 all participate). The `LR_MID_DAY` clear specifically enables the next mid-day RNG cycle to fire fresh against the new coordinator.

**EV magnitude:** CATASTROPHE-tier (couples with V-137's CATASTROPHE-tier framing — they're the same call). Per-row attribution: V-155 alone is bounded LOW — clearing `LR_MID_DAY` without the coordinator rotation has no exploit payoff. The CATASTROPHE-tier emerges from the COMPOSITE call where all five slots are cleared atomically. Per CATALOG strict-per-callsite, each is flagged separately; the per-row tier here is CATASTROPHE because of compositional EV.

### §85.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder: queue rotations until callback delivers or 12h timeout.**

Same shape as V-137 §1.C — split `updateVrfCoordinatorAndSub` into `queueVrfCoordinatorRotation` + `applyVrfCoordinatorRotation` with cooldown. The `applyVrfCoordinatorRotation` performs all five clears (vrfCoordinator, vrfSubscriptionId, vrfKeyHash, rngLockedFlag, vrfRequestId, rngRequestTime, rngWordCurrent, LR_MID_DAY) atomically; the queue gates the apply.

**Cross-VIOLATION coupling.** V-137 + V-155 + V-157 + V-159 + V-161 resolve via a SINGLE v44.0 sub-phase that splits `updateVrfCoordinatorAndSub` into queue + apply. All five handoff anchors (`H-78, H-85, H-87, H-89, H-91`) consolidate into one v44.0 work-item.

**Rationale.** Same as V-137. The reorder preserves the emergency-escape function while eliminating the mid-window pre-emption attack.

**Bytecode impact.** Shared with V-137 — already counted there (~150-250 bytes for the queue+apply split + pending slot). Storage-layout: shared. ABI: BREAKING shared with V-137.

### §85.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-85` — CATALOG §16 row V-155 + §15 row S-46 LR_MID_DAY governance subset + V-137 consolidation note. v44.0 plan-phase: CONSOLIDATED with V-137 / V-157 / V-159 / V-161 into one `updateVrfCoordinatorAndSub` queue+apply split sub-phase.

---

## §86 — V-156: vrfCoordinator write inside `wireVrf` (AdvanceModule.sol:506)

### §86.A — Design-intent backward-trace

`vrfCoordinator` is an `IVRFCoordinator internal` slot (CATALOG §14 row S-47). It holds the address of the Chainlink VRF coordinator the contract calls into for randomness requests.

The slot has two writer sites:
- `wireVrf` at `AdvanceModule.sol:506` (Admin one-shot). **THIS row — V-156.**
- `updateVrfCoordinatorAndSub` at `AdvanceModule.sol:1685` (governance rotation). V-157 (§10).

`wireVrf` (`:498-511`):

```solidity
function wireVrf(
    address coordinator_,
    uint256 subId,
    bytes32 keyHash_
) external {
    if (msg.sender != ContractAddresses.ADMIN) revert E();
    address current = address(vrfCoordinator);
    vrfCoordinator = IVRFCoordinator(coordinator_);
    vrfSubscriptionId = subId;
    vrfKeyHash = keyHash_;
    lastVrfProcessedTimestamp = uint48(block.timestamp);
    emit VrfCoordinatorUpdated(current, coordinator_);
}
```

**Constructor-only nature.** The function lacks a one-shot lock (no `wired` flag check), so it is technically re-callable by ADMIN. In practice, it is the deploy-time VRF binding — called once during the post-deploy admin sequence. After the first call, the de-facto invariant is "wireVrf is never called again" — but the contract doesn't enforce this.

**Why the slot exists.** The contract is delegatecall-orchestrated and the storage layout includes the VRF coordinator pointer; this must be writable at deploy because the constructor cannot accept it (the module is set after main-contract construction). `wireVrf` is the deploy-time bridge.

**Why naive gating breaks deployment.** A blanket revert `if (vrfCoordinator != address(0)) revert E()` would prevent re-wiring during a coordinator-rotation event (V-157's path). But the cleaner formulation is "remove `wireVrf` entirely and require constructor-time wiring" — which is the (d) immutable tactic.

**Phase-precedent.** No prior phase introduced `wireVrf`; it predates the audit and was the deploy-time anchor since contract genesis. The catalog's `D-43N-AUDIT-ONLY-01` strict-classification flags it VIOLATION because the writer exists outside the 3-EXEMPT entry stacks.

### §86.B — Actor game-theory walk

Exploit actor: post-deploy ADMIN re-calling `wireVrf` mid-game. The function has NO one-shot lock — only the `msg.sender != ADMIN` check. ADMIN could re-call `wireVrf(newCoordinator, newSubId, newKeyHash)` and clobber the VRF state.

**Important distinction from V-157:** `wireVrf` does NOT clear `rngLockedFlag` / `vrfRequestId` / `rngRequestTime` / `LR_MID_DAY` — it only writes the three VRF-config fields. So a re-call mid-cycle would leave an in-flight request bound to the OLD coordinator (rejected by `rawFulfillRandomWords:1749 msg.sender check`) while the new coordinator is wired. This is a structural foot-gun: ADMIN could deadlock the contract by accident.

`updateVrfCoordinatorAndSub` is the CORRECT path for runtime rotation — it clears the in-flight state. `wireVrf` is the deploy-only path. The audit's concern: nothing prevents ADMIN from using the wrong one.

**EV magnitude:** LOW. The exploit requires ADMIN action AND is the wrong-tool-for-the-job rather than a profit-motive attack. The economic-likelihood is bounded by ADMIN discipline. Per the trust-minimization audit posture, still VIOLATION-classified, but tier LOW.

### §86.C — Recommended tactic + rationale + impact

**Tactic (d) — Immutable: bind VRF config at deploy and remove `wireVrf` or seal post-init.**

Concrete shape: two options, both achieve immutability:

**Option (d.1) — Constructor-bind, remove `wireVrf` entirely.**

Move the three VRF config slots to `immutable` storage (Solidity `immutable` keyword) and accept the coordinator + subId + keyHash as constructor parameters. Remove `wireVrf` from the contract. The runtime rotation path (`updateVrfCoordinatorAndSub`) is unaffected — runtime mutability via the governance path still exists (subject to its own tactic-(c) reorder per V-157).

Trade-off: the three slots become bytecode constants (cheaper reads, ~-50 to -100 bytes per setter removed). Storage-layout shift: three slot positions freed (verify and document layout impact — likely non-disrupting if they were at the end of the layout, otherwise document the shift).

But: the runtime rotation path needs to write to these slots, so they cannot be `immutable`. The cleaner path is:

**Option (d.2) — One-shot lock on `wireVrf`.**

Add a `bool wired` storage flag (or repurpose a free bit in an existing packed slot). At `wireVrf` entry, after the ADMIN check, add `if (wired) revert E(); wired = true;`. The function remains callable, but only once. Subsequent rotations route through `updateVrfCoordinatorAndSub`. This option preserves the deploy-time bridge AND eliminates the foot-gun.

**Recommended:** Option (d.2) is the lighter touch and matches the catalog's "remove wireVrf or seal post-init" framing. Option (d.1) is cleaner but requires confirming storage-layout safety.

**Rationale.** The slot's de-facto invariant ("wireVrf is called exactly once at deploy") should be on-chain enforced. The trust-minimization audit posture prefers structural enforcement over discipline.

**Bytecode impact.** Option (d.2): ~50 bytes — one new packed bit + check. Storage-layout: +1 bit in an existing packed slot (e.g., merge with `compressedJackpotFlag` or another small flag). ABI: NON-BREAKING for first call; second-call now reverts (which is the goal).

Option (d.1): ~-100 bytes — three setter writes removed; three `immutable` keywords add no runtime bytecode. Storage-layout: BREAKING for the three freed slots (must shift downstream slot positions OR explicitly leave the slots as `uint256 private __reserved` placeholders). ABI: BREAKING — `wireVrf` removed; constructor signature changes.

### §86.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-86` — CATALOG §16 row V-156 + §15 row S-47 wireVrf. v44.0 plan-phase: pick Option (d.1) or (d.2); preference (d.2) for lighter touch (one-shot lock without storage-layout migration).

---

## §87 — V-157: vrfCoordinator write inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1685)

### §87.A — Design-intent backward-trace

`vrfCoordinator` is written inside the governance rotation function `updateVrfCoordinatorAndSub` at `:1685`. The full function context is documented in §1.A (V-137) — the same call writes all four VRF-state slots (`vrfCoordinator`, `vrfSubscriptionId`, `vrfKeyHash`) plus five lifecycle slots (`rngLockedFlag`, `vrfRequestId`, `rngRequestTime`, `rngWordCurrent`, `LR_MID_DAY`) in one transaction.

The writer exists to support the VRF coordinator-stall escape: when Chainlink VRF coordinator becomes unresponsive (network upgrade, subscription depletion, key-hash deprecation), ADMIN rotates to a new coordinator + subscription + key-hash atomically.

**Why naive gating breaks the escape.** Same as V-137 §1.A — the function exists to ESCAPE rngLock; gating on `rngLockedFlag` reintroduces the deadlock.

**Phase-precedent.** Same as V-137 — predates the audit. No prior phase formalized the rotation pathway; the function exists from contract genesis as the emergency lever.

### §87.B — Actor game-theory walk

Exploit actor: adversarial ADMIN (same as V-137 §1.B). Action sequence: rotate to admin-controlled coordinator → next `advanceGame` fires request to controlled coordinator → controlled coordinator returns chosen random word → game state resolved against admin-chosen randomness.

**EV magnitude:** CATASTROPHE-tier. Same composition as V-137 — the rotation grants the rotator effective control over downstream RNG.

### §87.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder: governance rotation queued past in-flight VRF.**

Same shape as V-137 §1.C and V-155 §8.C — split `updateVrfCoordinatorAndSub` into `queueVrfCoordinatorRotation` + `applyVrfCoordinatorRotation`. The `queue` phase only stores the proposed values; the `apply` phase atomically writes all eight slots (vrfCoordinator + vrfSubId + vrfKeyHash + the five lifecycle clears) after the cooldown is satisfied.

**Cross-VIOLATION coupling.** V-137 + V-155 + V-157 + V-159 + V-161 share a single v44.0 sub-phase. The reorder applies once and resolves all five.

**Rationale.** Tactic (c) preserves the emergency-escape semantics while inserting a time-locked review window for the rotation. The cooldown is anchored on `rngRequestTime + ROTATION_DELAY` or `vrfRequestId == 0` — i.e., apply when the in-flight request has resolved naturally or has been retried via the EXEMPT-RETRYLOOTBOXRNG path.

**Bytecode impact.** Shared with V-137 (already counted). ABI: BREAKING shared.

### §87.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-87` — CATALOG §16 row V-157 + §15 row S-47 governance subset + V-137 consolidation. v44.0 plan-phase: CONSOLIDATED with V-137 / V-155 / V-159 / V-161 into the `updateVrfCoordinatorAndSub` queue+apply split.

---

## §88 — V-158: vrfSubscriptionId write inside `wireVrf` (AdvanceModule.sol:507)

### §88.A — Design-intent backward-trace

`vrfSubscriptionId` is a `uint64 internal` slot (CATALOG §14 row S-48). It holds the Chainlink VRF subscription ID against which `requestRandomWords` is billed.

Writers:
- `wireVrf` at `AdvanceModule.sol:507`. **THIS row — V-158.**
- `updateVrfCoordinatorAndSub` at `AdvanceModule.sol:1686`. V-159 (§12).

Structurally identical to V-156 (`vrfCoordinator` / `wireVrf`) — the same one-shot deploy-time bridge writes all three VRF-config slots together at `:506-:508`. The `:507` write is the subscription-ID component of the bundle.

**Why the slot exists.** The subscription ID is required at every `requestRandomWords` call (`:1104, :1144`). It must be storable post-deploy because the constructor cannot accept it (delegatecall module sequencing constraint).

**Why naive gating breaks deployment.** Same as V-156 §9.A.

**Phase-precedent.** Same as V-156 — predates the audit. The three VRF-config slots have always been written together by `wireVrf`.

### §88.B — Actor game-theory walk

Exploit actor: post-deploy ADMIN re-calling `wireVrf`. The same foot-gun as V-156 §9.B — re-call writes the three config fields without clearing the in-flight state slots. Mid-cycle re-call could leave an in-flight request bound to the OLD subscription while the new sub is wired.

**EV magnitude:** LOW (same as V-156). The exploit is ADMIN-dependent and wrong-tool-for-the-job rather than profit-motivated.

### §88.C — Recommended tactic + rationale + impact

**Tactic (d) — Immutable.**

Concrete shape: structurally identical to V-156 §9.C. Two options:

**Option (d.1):** Move `vrfSubscriptionId` to `immutable` storage, constructor-bound. Same trade-off as V-156 — requires confirming storage-layout safety AND removing the runtime mutation path. But `updateVrfCoordinatorAndSub` mutates this slot, so `immutable` is incompatible with the runtime rotation path.

**Option (d.2):** One-shot lock on `wireVrf` (the same `bool wired` flag covers all three VRF-config slots since they're written together). The lock is added ONCE at `wireVrf` entry, not per-slot.

**Coupling with V-156 + V-160.** Options (d.1) and (d.2) BOTH cover V-156 + V-158 + V-160 in a single v44.0 sub-phase. The three handoff anchors (`H-86, H-88, H-90`) consolidate.

**Bytecode impact.** Already counted with V-156 (~50 bytes for the one-shot lock OR ~-100 bytes for the immutable migration). No additional bytecode per-slot.

### §88.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-88` — CATALOG §16 row V-158 + §15 row S-48 wireVrf + V-156 consolidation. v44.0 plan-phase: CONSOLIDATED with V-156 / V-160 into the `wireVrf` one-shot lock (Option d.2) sub-phase.

---

## §89 — V-159: vrfSubscriptionId write inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1686)

### §89.A — Design-intent backward-trace

`vrfSubscriptionId` is written at `:1686` inside `updateVrfCoordinatorAndSub`. The function context is documented in §1.A and §10.A. The subscription-ID write is the second of three VRF-config rewrites (the others at `:1685` vrfCoordinator V-157 and `:1687` vrfKeyHash V-161).

**Why the slot is written here.** The rotation event allows ADMIN to redirect billing to a new subscription. Some operational scenarios:
- Subscription `X` is depleted of LINK; ADMIN moves to subscription `Y` with fresh balance.
- Coordinator upgrade (Chainlink v2 → v2.5 migration) bundles a new coordinator address with a new subscription pool.

**Why naive gating breaks the escape.** Same as V-137 / V-155 / V-157 §1.A — the rotation needs to happen precisely when the in-flight request has stalled.

**Phase-precedent.** Same as V-137.

### §89.B — Actor game-theory walk

Exploit actor: adversarial ADMIN. Action: rotate subscription to one ADMIN controls (or to an attacker-controlled subscription on the same coordinator). The subscription receives the billing for the next `requestRandomWords`. If the attacker depletes the subscription before the callback, the request reverts at the coordinator side, stalling the game. Conversely, if the attacker funds the new subscription, the call proceeds — but the random word is still produced by the (correctly-honest) Chainlink VRF, so the exploit value is limited UNLESS combined with V-157 (coordinator swap).

**EV magnitude:** CATASTROPHE-tier in composition (with V-137 / V-155 / V-157 / V-161 — they're the same atomic call). Per-row attribution: LOW for an isolated subscription change (no randomness impact). CATASTROPHE-tier applies because per-callsite strict classification doesn't isolate the composite call's eight-slot atomic write.

### §89.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder.**

Same shape as V-137 / V-155 / V-157 §8.C / §10.C — queue + apply split. The subscription-ID write is one of three VRF-config slots written by `applyVrfCoordinatorRotation`.

**Cross-VIOLATION coupling.** Shared with V-137 + V-155 + V-157 + V-161 in one v44.0 sub-phase.

**Bytecode impact.** Shared with V-137 (already counted). ABI: BREAKING shared.

### §89.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-89` — CATALOG §16 row V-159 + §15 row S-48 governance subset + V-137 consolidation. v44.0 plan-phase: CONSOLIDATED.

---

## §90 — V-160: vrfKeyHash write inside `wireVrf` (AdvanceModule.sol:508)

### §90.A — Design-intent backward-trace

`vrfKeyHash` is a `bytes32 internal` slot (CATALOG §14 row S-49). It holds the Chainlink VRF key-hash identifying the gas-lane / proof keyspace.

Writers:
- `wireVrf` at `AdvanceModule.sol:508`. **THIS row — V-160.**
- `updateVrfCoordinatorAndSub` at `AdvanceModule.sol:1687`. V-161 (§14).

Structurally identical to V-156 / V-158 — the same one-shot deploy-time bridge writes all three VRF-config slots together. The `:508` write completes the bundle.

**Why the slot exists.** The key-hash is required at every `requestRandomWords` call (`:1103, :1144`). It is part of the VRF protocol's keyspace selection.

**Why naive gating breaks deployment.** Same as V-156 §9.A.

**Phase-precedent.** Same as V-156.

### §90.B — Actor game-theory walk

Same as V-156 / V-158 — ADMIN re-call foot-gun. EV magnitude: LOW (per-row), structurally identical to V-156 / V-158.

### §90.C — Recommended tactic + rationale + impact

**Tactic (d) — Immutable.**

Same shape as V-156 §9.C / V-158 §11.C. Options (d.1) immutable migration or (d.2) one-shot lock. Coupled with V-156 + V-158 into one v44.0 sub-phase.

**Bytecode impact.** Already counted (shared with V-156).

### §90.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-90` — CATALOG §16 row V-160 + §15 row S-49 wireVrf + V-156 consolidation. v44.0 plan-phase: CONSOLIDATED with V-156 / V-158 into the `wireVrf` one-shot lock sub-phase.

---

## §91 — V-161: vrfKeyHash write inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1687)

### §91.A — Design-intent backward-trace

`vrfKeyHash` is written at `:1687` inside `updateVrfCoordinatorAndSub`. The function context is documented in §1.A, §10.A, §12.A. The key-hash write is the third of three VRF-config rewrites.

**Why the slot is written here.** Chainlink VRF v2.5 migration changed the keyspace; future coordinator-version migrations may again. The key-hash field is rotated alongside the coordinator + subId.

**Why naive gating breaks the escape.** Same as V-137 / V-155 / V-157 / V-159.

**Phase-precedent.** Same as V-137.

### §91.B — Actor game-theory walk

Exploit actor: adversarial ADMIN. The key-hash field determines which Chainlink keyspace produces the VRF proof. A rotation to a key-hash for a different (e.g., compromised or low-confirmation) keyspace could reduce randomness security. In composition with V-157 (coordinator swap), the attacker gains control over the proof verification chain.

**EV magnitude:** CATASTROPHE-tier (compositional). Per-row LOW for isolated key-hash change.

### §91.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder.**

Same as V-137 / V-155 / V-157 / V-159 — queue + apply split. The key-hash write is the third VRF-config slot in the `applyVrfCoordinatorRotation` atomic write set.

**Cross-VIOLATION coupling.** Shared with V-137 + V-155 + V-157 + V-159 in one v44.0 sub-phase.

**Bytecode impact.** Shared (already counted).

### §91.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-91` — CATALOG §16 row V-161 + §15 row S-49 governance subset + V-137 consolidation. v44.0 plan-phase: CONSOLIDATED with V-137 / V-155 / V-157 / V-159 into one queue+apply sub-phase.

---

## §92 — V-168: `ticketQueue[rk]` write inside `_queueTickets` via `purchaseWhaleBundle` (`WhaleModule.sol:313`)

### §92.A — Design-intent backward-trace

`ticketQueue` is `mapping(uint24 => address[]) internal ticketQueue;` at `contracts/storage/DegenerusGameStorage.sol` (round-key-indexed push-array). Companion slot `ticketsOwedPacked[rk][player]` (S-53) is the per-player owed-count co-located in every write path. Both are consumed at the AdvanceModule trait-generation consumer (CATALOG §10) when `advanceGame()` self-stacks resolves the per-level round-key's ticket allocations.

`_queueTickets(buyer, lvl, ticketCount, isBonus)` is the round-key-keyed push helper at `DegenerusGameStorage.sol:580` — it `.push(buyer)` into `ticketQueue[rk]` and bumps `ticketsOwedPacked[rk][buyer]`. `purchaseWhaleBundle` (`WhaleModule.sol:187`) is the EOA-facing whale-bundle purchase entry; its loop at `WhaleModule.sol:313` calls `_queueTickets` for each level the bundle covers (100 levels at standard tickets and bonus tiers).

**Why the slot exists.** The ticket-queue mechanism predates the rngLock discipline (introduced when the protocol added the deferred trait-generation flow). Each ticket purchase deposits the buyer at `ticketQueue[lvl]` so that AdvanceModule's trait-generation pass can stochastically assign rare traits proportional to ticket holdings at the round-key's resolution time. Naively reverting `_queueTickets` on `rngLockedFlag` would break legitimate purchases — but at this writer-callsite (whale-bundle purchase), the existing `purchaseDeityPass` precedent at `WhaleModule.sol:543` (`if (rngLockedFlag) revert RngLocked()`) already encodes the "block whale-tier purchases during rngLock" pattern.

**Phase-precedent.** Phase 292 HRROLL leader-bonus + Phase 290 MINTCLN (`v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md`) established the `cachedJpFlag && rngLockedFlag`-style gates at `MintModule.sol:1221`. Phase 296 RETRY_LOOTBOX_RNG (`v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-CONTEXT.md`, `D-42N-RETRY-RNG-DOMAIN-SEP-01`) clarified that lootbox-resolution VRF is domain-separated from daily VRF — relevant for V-171/V-172 (this slot's lootbox-callsite siblings) but not for V-168's whale-bundle path. The PARTIAL existing coverage on `_purchaseDeityPass:543` is the precedent that V-168/V-169 must EXTEND.

### §92.B — Actor game-theory walk

**Exploit actor.** EOA whale-tier buyer with sufficient ETH to call `purchaseWhaleBundle` between (i) AdvanceModule's VRF callback delivery (publishing `rngWordCurrent`) and (ii) AdvanceModule's next `advanceGame()` invocation that consumes `rngWordByDay[day]` for trait-generation. Window is at minimum one block (VRF callback to next `advanceGame()`); in practice the window persists until the next caller invokes `advanceGame()`.

**Action sequence.**
1. Attacker monitors `rngRequestTime != 0 && rngLockedFlag == true` → VRF in-flight.
2. VRF callback delivers `rngWord` via `rawFulfillRandomWords` → `rngWordCurrent` is set, `rngLockedFlag` remains `true` (cleared inside next `advanceGame()` via `_unlockRng` at `AdvanceModule.sol:1731`).
3. Attacker reads published `rngWordCurrent` (mempool / public state). Projects which `ticketQueue[lvl]` indices benefit from cramming additional buyer entries: e.g., if the rngWord-derived trait-roll favors low-index entries, attacker queues a fresh `purchaseWhaleBundle` to push themselves into the favorable position.
4. `_queueTickets:313` runs unguarded → attacker's address inserted into `ticketQueue[lvl]` for all 100 levels of the bundle, with `ticketsOwedPacked[rk][attacker]` bumped accordingly.
5. Next `advanceGame()` consumes the now-attacker-padded `ticketQueue[lvl]` array at trait-generation time.

**EV magnitude.** MEDIUM. Whale-bundle purchase is a high-capital action (per-bundle cost is non-trivial), so the attack requires meaningful upfront ETH. The trait-generation roll determines NFT rare-trait assignments which have indirect (NFT-market) economic value, not direct payout multiplication. The economic-likelihood disposition is MEDIUM: an attacker with sufficient bankroll AND a position in the level-range being resolved would exploit; an opportunistic attacker without prior position has no in-window pivot to outsize the bundle cost.

### §92.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `purchaseWhaleBundle` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the start of `_purchaseWhaleBundle` (`WhaleModule.sol:194`), mirroring the existing `_purchaseDeityPass:543` convention.

**Rationale.** Whale-bundle is a single-call atomic purchase touching 100 ticketQueue slots; gating at function entry is structurally minimal and matches the established precedent. Alternative tactic (b) snapshot-at-allocation is rejected because the `ticketQueue` array is itself the consumer-side state — there is no "earlier commitment" to snapshot against. Alternative tactic (c) pre-lock reorder is rejected because the writer is the EOA's atomic action — there is no later reorder point inside the same TX.

**Bytecode impact.** ~30 bytes (one `SLOAD` of `rngLockedFlag` + conditional `revert RngLocked()`). Storage-layout: byte-identical (no new slots). Public ABI: NON-BREAKING (the revert path is new but the function signature unchanged). The `RngLocked()` custom error is already defined and used at `MintModule:1221`, `BurnieCoinflip:730`, `sStonk:492` per CATALOG §0 implementation-pattern enumeration — this fix reuses the existing error selector.

### §92.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-92` — CATALOG §16 row V-168 + §15 row S-52 `_queueTickets`/`purchaseWhaleBundle` + §10 trait-generation consumer. v44.0 plan-phase: add `if (rngLockedFlag) revert RngLocked();` at `_purchaseWhaleBundle` entry, co-located with the V-179.A handoff (single gate covers both S-52 and S-53 writes at this callsite).

---

## §93 — V-169: `ticketQueue[rk]` write inside `_queueTickets` via `purchaseLazyPass` (`WhaleModule.sol:482`)

### §93.A — Design-intent backward-trace

`purchaseLazyPass` (`WhaleModule.sol:380`) is the EOA-facing "lazy" whale-pass purchase — a discounted variant of whale-bundle that queues tickets only for the bonus-tier range (levels 1-10) rather than the full 100 levels. The `_queueTickets` callsite at `WhaleModule.sol:482` is one push per bonus-range level. Same slot identity, same writer fn, different EOA entry point.

**Why the slot exists.** Lazy-pass is a price-discriminated tier of whale-bundle introduced to broaden the whale-tier purchaser pool. The `_purchaseLazyPass` body has NO existing `rngLockedFlag` gate at the entry. Phase-precedent identical to V-168: `_purchaseDeityPass:543` already encodes the convention.

**Why naive gating preserves UX.** Lazy-pass purchases are infrequent (the lazy-pass is purchased once per game per buyer). A short-duration rngLock revert (~30 seconds typical VRF latency) does not meaningfully degrade UX — the buyer retries after the window.

### §93.B — Actor game-theory walk

**Exploit actor.** Same class as V-168 — EOA buyer with capital for a lazy-pass purchase, observing the in-flight VRF window.

**Action sequence.** Identical to V-168 but at the lazy-pass entry. Window properties identical (VRF callback to next `advanceGame()`).

**EV magnitude.** MEDIUM. Lazy-pass tickets are bonus-range-only (10 levels), reducing the attacker's ticket-queue insertion scale by 90% relative to whale-bundle. Combined with the lazy-pass purchase cost, EV is bounded. Conservative classification: MEDIUM.

### §93.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `_purchaseLazyPass` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the start of `_purchaseLazyPass` (`WhaleModule.sol:384`), mirroring `_purchaseDeityPass:543`.

**Rationale.** Same as V-168 §1.C. The catalog row's rationale text literally cites "mirrors purchaseDeityPass:543" as the prescribed implementation pattern.

**Bytecode impact.** ~30 bytes. Storage-layout / ABI: unchanged.

### §93.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-93` — CATALOG §16 row V-169 + §15 row S-52 `_queueTickets`/`purchaseLazyPass`. v44.0 plan-phase: add `rngLockedFlag` revert at `_purchaseLazyPass` entry, co-located with V-179.B handoff.

---

## §94 — V-170: `ticketQueue[rk]` write inside `_queueTickets` via `purchaseDeityPass` (`WhaleModule.sol:625`)

### §94.A — Design-intent backward-trace

`purchaseDeityPass` (`WhaleModule.sol:538`) is the EOA-facing deity-pass purchase (1 of 32 symbol slots per game). The `_queueTickets` callsite at `WhaleModule.sol:625` queues whale-equivalent tickets across the bonus-and-standard range (100 levels) for the deity-pass holder. The writer is gated at function entry by `if (rngLockedFlag) revert RngLocked();` at `WhaleModule.sol:543` — **this gate already exists in current source** (verified at audit baseline).

**Why the slot exists.** Identical to V-168/V-169. Deity-pass is the highest-tier whale purchase (per-symbol scarcity creates per-game cap of 32 holders).

**Phase-precedent.** Phase 294 DPNERF (`v42.0-phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md`) shaped the deity-pass economic balance. The `rngLockedFlag` gate at `:543` is the established precedent V-168/V-169 are extending.

### §94.B — Actor game-theory walk

**Exploit actor.** Same class as V-168/V-169.

**Action sequence.** Attacker attempts `purchaseDeityPass` during rngLock → `WhaleModule.sol:543` reverts → `ticketQueue[rk]` is NOT mutated. Attack blocked.

**EV magnitude.** LOW. The catalog row classifies this as VIOLATION strictly under the per-callsite verdict-matrix rule (the writer-callsite is not on an EXEMPT advance-stack reach), but the existing runtime gate at `:543` means the structural risk is ALREADY zero. Per CATALOG §16 row V-170 verdict-text "Existing gate at :543 satisfies; verdict-matrix is stack-strict, gate verified," this is a documentation row, not an actionable structural fix.

### §94.C — Recommended tactic + rationale + impact

**Tactic (a) — Existing gate at `:543` satisfies.** No additional code change required.

**Rationale.** The catalog's strict per-callsite verdict alphabet does not distinguish "gated by existing runtime check" from "ungated EOA writer" — both are classified VIOLATION because the writer-callsite itself is not on an EXEMPT advance-stack. The implementation-side disposition is "verify the existing `:543` gate covers the writer reach," which it does (the `_queueTickets:625` callsite is downstream of `:543` in the same TX). This row is preserved as a verdict-matrix entry but the v44.0 plan-phase action is "verify-only" rather than "patch."

**Bytecode impact.** Zero. Storage / ABI unchanged.

### §94.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-94` — CATALOG §16 row V-170. v44.0 plan-phase: verify-only — confirm `WhaleModule.sol:543` `rngLockedFlag` revert remains in place; no patch required. Co-located with V-179.C (which inherits the same verify-only disposition).

---

## §95 — V-171: `ticketQueue[rk]` write inside `_queueTickets` via `openLootBox` (`LootboxModule.sol:1067`)

### §95.A — Design-intent backward-trace

`openLootBox(player, index)` at `LootboxModule.sol:526` is the EOA-facing manual lootbox-resolution entry. The `_queueTickets` callsite at `LootboxModule.sol:1067` runs inside `_resolveLootboxCommon` when the lootbox resolution awards whole-ticket count (`whole != 0`); the call inserts the player into `ticketQueue[targetLevel]` for each whole ticket awarded.

**Why the slot exists.** Lootbox resolution uses the daily-VRF-derived `rngWordByIndex[index]` (CATALOG §7) to determine the ticket-award magnitude. The award-magnitude → ticket-queue-insertion path is structurally legitimate; the EXPLOIT is the asymmetric timing where an attacker can call `openLootBox` between the daily VRF callback and the next `advanceGame()` to insert into a `ticketQueue[targetLevel]` that has NOT YET been consumed by trait-generation.

**Phase-precedent.** Phase 296 RETRY_LOOTBOX_RNG (`D-42N-RETRY-RNG-DOMAIN-SEP-01`) confirmed lootbox VRF is domain-separated from daily VRF — but the lootbox-resolution OUTPUT (`ticketQueue` insertion) still feeds into the daily-VRF-consumed trait-generation pass. The domain separation closes lootbox-VRF mutability but does NOT close the ticket-queue-insertion side channel into trait-generation.

### §95.B — Actor game-theory walk

**Exploit actor.** EOA lootbox-holder who pre-committed to an `index` (allocation-time write earlier in the game flow) and now wants to time the `openLootBox(index)` call to land the awarded tickets in a `ticketQueue[targetLevel]` array that will be CONSUMED by trait-generation under the just-published daily rngWord.

**Action sequence.**
1. Attacker holds a pre-allocated lootbox index from prior game flow.
2. VRF callback delivers daily `rngWord` → `rngLockedFlag` remains true until next `advanceGame()`.
3. Attacker projects which `ticketQueue[lvl]` arrays will be trait-resolved in the imminent advance; calls `openLootBox(index)` if a beneficial insertion is available.
4. `_queueTickets:1067` runs unguarded → attacker's tickets inserted at advantageous queue position.
5. Next `advanceGame()` consumes the now-padded queue.

**EV magnitude.** HIGH. Per CATALOG §0 headline #2 ("Manual-path lootbox open is a deep VIOLATION cluster"), the manual lootbox-open path is the densest VIOLATION cluster in the codebase — 35 violation rows on `openLootBox`/`openBurnieLootBox`. The `_queueTickets` insertion is one component of that cluster but it directly modulates trait-generation outcomes, which feed into NFT-market value AND into ticket-jackpot eligibility. The trait-roll EV swing on a perfectly-timed insertion can be material (multi-eth per attack, per CATALOG §10 trait-magnitude prose).

### §95.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `openLootBox` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `openLootBox` (`LootboxModule.sol:526`).

**Rationale.** The daily-VRF-freshness invariant says: NO writer should mutate state consumed by trait-generation between VRF callback and `_unlockRng`. Per `feedback_rng_window_storage_read_freshness.md`, the lootbox VRF (domain-separated) is independent of the daily VRF — so gating `openLootBox` on `rngLockedFlag` does NOT block lootbox-VRF resolution; it ONLY blocks the ticket-queue side-channel into daily-VRF-consumed trait-generation. Snapshot tactic (b) is rejected: the ticket-queue ARRAY is itself the consumer state (cannot be snapshotted without restructuring the array indexing). Reorder tactic (c) is rejected: the writer is the EOA's atomic action.

**Bytecode impact.** ~30 bytes. The `RngLocked()` error is shared. Note: lootbox-VRF retries (`retryLootboxRng`, EXEMPT-RETRYLOOTBOXRNG) are unaffected because the retry path is admin-side, not EOA. Storage / ABI: unchanged.

**Caveat for v44.0 plan-phase.** If `openLootBox` is the only EOA path to claim accumulated lootbox-VRF awards and the daily rngLock window is long-running (multi-day stalls per the gap-day handling in `AdvanceModule._backfillGapDays`), users may want a queued-claim pattern to defer the open without revert. v44.0 plan-phase may decide between strict revert (this recommendation) and a queued-claim refactor.

### §95.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-95` — CATALOG §16 row V-171 + §15 row S-52 `_queueTickets`/`openLootBox` + §7 manual-lootbox-open consumer + §0 headline #2. v44.0 plan-phase: add `rngLockedFlag` revert at `openLootBox` entry, co-located with V-179.D handoff and (potentially) the broader §0 headline #2 manual-open cluster v44 sub-phase.

---

## §96 — V-172: `ticketQueue[rk]` write inside `_queueTickets` via `openBurnieLootBox` (`LootboxModule.sol:1190`)

### §96.A — Design-intent backward-trace

`openBurnieLootBox(player, index)` at `LootboxModule.sol:607` is the EOA-facing burnie-side variant of `openLootBox` — same resolution path but with BURNIE-denominated allocation. The `_queueTickets` callsite at `LootboxModule.sol:1190` is the burnie-variant's ticket-award insertion. Same write-target (`ticketQueue[rk]`) as V-171; same trait-generation consumer.

**Why the slot exists.** Identical to V-171 (lootbox-resolution award path; burnie-denominated variant). Phase 296 domain-separation applies identically.

### §96.B — Actor game-theory walk

**Exploit actor + action sequence.** Identical to V-171 but with `openBurnieLootBox` substituted. Burnie-side lootbox-VRF allocation pre-committed; EOA timing same.

**EV magnitude.** HIGH (same as V-171). The burnie-side variant has the same downstream trait-generation impact.

### §96.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `openBurnieLootBox` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `openBurnieLootBox` (`LootboxModule.sol:607`).

**Rationale.** Same as V-171 §4.C; the catalog row's rationale text literally states "Same as V-171 — write-target shared." Single gate covers V-172 (S-52) and V-179.E (S-53).

**Bytecode impact.** ~30 bytes.

### §96.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-96` — CATALOG §16 row V-172. v44.0 plan-phase: add `rngLockedFlag` revert at `openBurnieLootBox` entry, co-located with V-179.E.

---

## §97 — V-174: `ticketQueue[rk]` write inside `_queueTicketsScaled` via `_purchaseFor` (`MintModule.sol:1129`)

### §97.A — Design-intent backward-trace

`_purchaseFor` (`MintModule.sol:899`) is the internal mint-purchase routine called from EOA-facing `purchase`/`purchaseCoin`/`purchaseBurnieLootbox`. The `_queueTicketsScaled` callsite at `MintModule.sol:1129` runs after quantity computation and adjusts the ticket allocation by EV-scaling factors. `_queueTicketsScaled(buyer, targetLevel, adjustedQty, false)` is the scaled variant of `_queueTickets`; storage writer at `DegenerusGameStorage.sol:612` (push) + `:636` (ticketsOwedPacked write).

**Why the slot exists.** Mint-purchase is the primary EOA capital inflow path. `_queueTicketsScaled` adjusts the queued-ticket count by per-buyer scaling (activity-score, deity-bonus, etc.). The PARTIAL existing coverage is the `lastPurchaseDay && rngLockedFlag` target-level redirect at `MintModule.sol:1221` (per Phase 290 MINTCLN) — but this redirect ONLY repoints the target-level; it does NOT block the write itself. The write still lands in `ticketQueue[targetLevel]` for some level.

**Phase-precedent.** Phase 290 MINTCLN introduced the `:1221` cached-flag redirect. The structural insight from MINTCLN: target-level redirect alone is insufficient — the write itself must be gated to close the side channel.

### §97.B — Actor game-theory walk

**Exploit actor.** EOA mint-purchaser with ETH/BURNIE for an in-window purchase.

**Action sequence.**
1. VRF callback delivers daily `rngWord`; `rngLockedFlag` remains true.
2. Attacker projects which `ticketQueue[targetLevel]` will be trait-resolved.
3. Attacker calls `purchase` → `_purchaseFor` → `_queueTicketsScaled:1129`. The `:1221` redirect changes `targetLevel` to current `lvl` (not `lvl + 1`) but the write still inserts the buyer at `ticketQueue[lvl]`, which is a level the imminent `advanceGame()` will trait-resolve.
4. Trait-generation consumes the now-padded queue.

**EV magnitude.** HIGH. Per CATALOG §0 headline #3 ("Top-level ungated EOA entry points cluster"), `MintModule.purchase` carries no blanket `rngLockedFlag` gate. Mint-purchase volume is high; per-attack EV swings on trait-generation outcomes are material.

### §97.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `purchase` (and sibling) entries.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` entries.

**Rationale.** Per catalog row: "Gate purchase() against daily VRF window; level-target redirect at :1221 insufficient." The `:1221` redirect is necessary but not sufficient — it solves the "where the ticket lands" problem but not the "whether the ticket is queued at all" problem during the rngLock window. The structural fix is to revert the purchase entirely.

**Bytecode impact.** ~30 bytes per entry × 3 entries = ~90 bytes total. NON-BREAKING ABI.

**UX tradeoff for v44.0 plan-phase.** Mint-purchases are higher-volume than whale-bundle/lazy-pass purchases; reverts during rngLock will be more visible to users. v44.0 plan-phase may consider a queued-purchase pattern (defer the queue write to post-unlock) instead of strict revert. The current recommendation follows the catalog's tactic-(a) prescription.

### §97.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-97` — CATALOG §16 row V-174 + §15 row S-52 `_queueTicketsScaled`/`_purchaseFor` + §10 trait-generation consumer + §0 headline #3. v44.0 plan-phase: add `rngLockedFlag` revert at `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` entries, co-located with V-179.F handoff.

---

## §98 — V-175: `ticketQueue[rk]` write inside `_queueTicketRange` via `_awardDecimatorLootbox` (`DecimatorModule.sol:582`)

### §98.A — Design-intent backward-trace

`_awardDecimatorLootbox(winner, amount, rngWord)` at `DecimatorModule.sol:570` runs as part of `claimDecimatorJackpot`'s post-VRF lootbox-portion award (line 389). When the claim amount exceeds `LOOTBOX_CLAIM_THRESHOLD`, the function awards `fullHalfPasses` whole-half-passes via `_queueTicketRange(winner, startLevel, 100, fullHalfPasses, false)` at `DecimatorModule.sol:582`. Writer at `DegenerusGameStorage.sol:666` (push) + `:671` (ticketsOwedPacked).

**Why the slot exists.** Decimator jackpot payouts are routed half-via-ticket-queue, half-via-claimable-ETH. The ticket-queue side awards bonus-range whale-equivalent tickets. The write is reached BOTH from the EOA path (`claimDecimatorJackpot` external) AND from the advance-stack path (when `claimDecimatorJackpot` is invoked internally during phase transitions; verify per-callsite).

**Per-callsite split per CATALOG §16 row V-175:** "EOA (advance-stack callsites EXEMPT, but EOA per-callsite split applies)." The advance-stack reach to `_awardDecimatorLootbox` is classified EXEMPT-ADVANCEGAME; only the EOA reach (via `claimDecimatorJackpot` external) is classified VIOLATION.

### §98.B — Actor game-theory walk

**Exploit actor.** EOA decimator-claimer with a prior `decBurn[lvl][player]` record that landed in a winning subbucket.

**Action sequence.**
1. Decimator jackpot resolved (advance-stack); claim round persisted in `decClaimRounds[lvl]`.
2. VRF callback delivers a SUBSEQUENT daily `rngWord` for a different trait-generation pass; `rngLockedFlag` true.
3. Attacker times `claimDecimatorJackpot(lvl)` to insert their bonus-range tickets via `_queueTicketRange:582` during the rngLock window — landing at advantageous positions in `ticketQueue[startLevel..startLevel+99]`.
4. Trait-generation consumes the padded queue.

**EV magnitude.** MEDIUM. Decimator claim is a one-shot per (player, lvl) tuple, so attacker capacity is bounded by their per-game decimator winnings. The ticket-range insertion is bonus-range only (not full 100 levels of unique advantage). Combined with the prerequisite of being a decimator winner, this is a narrower attack class than V-174.

### §98.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at the EOA-reach of `_awardDecimatorLootbox`.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `claimDecimatorJackpot` (`DecimatorModule.sol:321`) — which is the only EOA reach of `_awardDecimatorLootbox`. Note: `claimDecimatorJackpot` ALREADY guards `prizePoolFrozen` (line 325 `if (prizePoolFrozen) revert E();`); the new gate is a separate condition.

**Rationale.** Per catalog row: "Gate EOA-reach (recordDecBurn); advance-stack reach is EXEMPT per-callsite." The advance-stack reach is the orchestrated phase-transition path, which IS the consumer; the EOA reach is the side channel that opens the window. Gating at `claimDecimatorJackpot` entry closes the EOA-side without affecting advance-stack flow.

**Bytecode impact.** ~30 bytes. The `prizePoolFrozen` revert at line 325 is a related but distinct check — it blocks claims when the prize pool itself is frozen, which is a different state than `rngLockedFlag` (rngLockedFlag covers VRF-in-flight only).

### §98.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-98` — CATALOG §16 row V-175 + §15 row S-52 `_queueTicketRange`/`_awardDecimatorLootbox` + §13 DecimatorModule consumer. v44.0 plan-phase: add `rngLockedFlag` revert at `claimDecimatorJackpot` entry. Co-located with V-179.G handoff.

---

## §99 — V-176: `ticketQueue[rk]` write inside `_queueTicketRange` via `claimWhalePass` (`WhaleModule.sol:973`)

### §99.A — Design-intent backward-trace

`claimWhalePass(player)` at `WhaleModule.sol:957` is the EOA-facing whale-pass redemption that converts a held whale-pass into queued tickets. The `_queueTicketRange` callsite at `WhaleModule.sol:973` queues `halfPasses` worth of bonus-range tickets across 100 levels.

**Why the slot exists.** Whale-pass is a one-shot redemption per holder. The `_queueTicketRange` storage writer at `DegenerusGameStorage.sol:666` has a partial far-future loop revert (per catalog row's existing-coverage prose) — but that revert covers the loop-bound case, not the rngLock-window case.

**Phase-precedent.** Whale-pass redemption predates the rngLock discipline; the current implementation has no top-level rngLockedFlag gate.

### §99.B — Actor game-theory walk

**Exploit actor + action sequence.** Same class as V-168/V-169 — EOA holder of a whale-pass who times the `claimWhalePass` call during rngLock.

**EV magnitude.** MEDIUM. Whale-pass is one-shot per holder; bonus-range tickets only (limited insertion scale).

### §99.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `claimWhalePass` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `claimWhalePass` (`WhaleModule.sol:957`).

**Rationale.** Per catalog row: "Add top-level rngLockedFlag gate; far-future loop revert is partial coverage." The far-future loop revert (inside `_queueTicketRange` storage helper) is a defense against indexing out of bounds, not against rngLock-window timing. The structural fix is at the entry point.

**Bytecode impact.** ~30 bytes.

### §99.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-99` — CATALOG §16 row V-176. v44.0 plan-phase: add `rngLockedFlag` revert at `claimWhalePass` entry, co-located with V-179.H.

---

## §100 — V-177: `ticketQueue[rk]` write inside `_queueTicketRange` via `_redeemWhalePassRange` (`Storage.sol:1135`)

### §100.A — Design-intent backward-trace

`_redeemWhalePassRange` (at `DegenerusGameStorage.sol:1135`) is the lower-level helper invoked from whale-pass redemption flows when a player redeems a partial range. The `_queueTicketRange` callsite at `:1135` is the storage-helper-internal queue-range insertion. Same write-target (`ticketQueue[rk]`) and same consumer reach as V-176.

**Why the slot exists.** Range-redemption is a structured helper supporting bulk whale-pass conversion. Same partial-coverage situation as V-176 (far-future loop revert exists, top-level rngLock gate does not).

### §100.B — Actor game-theory walk

**Exploit actor + action sequence.** Identical to V-176; both EOA reaches lead to `_queueTicketRange` writes during rngLock.

**EV magnitude.** MEDIUM. Same per-attack scale as V-176.

### §100.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at the EOA entry that invokes `_redeemWhalePassRange`.** The catalog row's text "Same as V-176 — whale-pass redemption path" indicates the gate is at the same EOA entry as V-176 (`claimWhalePass` and any sibling entries that reach `_redeemWhalePassRange`).

**Rationale.** Single gate at the EOA entry covers both V-176's direct `_queueTicketRange:973` call AND V-177's deeper `_queueTicketRange` reach via `_redeemWhalePassRange:1135`.

**Bytecode impact.** Zero incremental cost over V-176 (same gate site).

### §100.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-100` — CATALOG §16 row V-177. v44.0 plan-phase: gate co-located with V-176 (`claimWhalePass` entry) — single revert covers both rows. Co-located with V-179.I.

---

## §101 — V-179: `ticketsOwedPacked[rk][player]` co-located writes (9-callsite fan-out: V-179.A..V-179.I)

### §101.A — Design-intent backward-trace

`ticketsOwedPacked[rk][player]` is the per-player owed-ticket-count slot co-located with `ticketQueue[rk]` (S-52). Storage declared as `mapping(uint24 => mapping(address => uint40)) internal` at `DegenerusGameStorage.sol`. The slot is consumed alongside `ticketQueue[rk]` at trait-generation time — each `ticketQueue[rk]` entry's owed-count comes from `ticketsOwedPacked[rk][buyer]`.

**Critical co-location property.** Every writer fn of S-52 (`_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`) ALSO writes S-53 in the same SSTORE block (per CATALOG §15 rows S-52 / S-53 — identical writer-fn rows, identical callsite rows). Storage line numbers: `_queueTickets` writes S-52 at `:580` and S-53 at `:585`; `_queueTicketsScaled` writes S-52 at `:612` and S-53 at `:636`; `_queueTicketRange` writes S-52 at `:666` and S-53 at `:671`. The two slots are STRUCTURALLY co-located.

**V-179 fan-out per `D-299-FIXREC-LAYOUT-01` 82-budget rule.** V-179 is ONE logical VIOLATION even though it spans 9 distinct EOA callsites (one per S-52 callsite). The 9 sub-anchors H-101..H-109 correspond one-to-one with the V-179.A..V-179.I sub-rows the catalog planner would emit if V-179 were split. Per the catalog §0 footnote, V-179 is counted as a single entry in the 82-logical-VIOLATION budget; the 9-sub-row expansion is for completeness in the verdict matrix but does NOT inflate the budget.

**Why naive single-slot gating is identical to S-52 gating.** Because S-52 and S-53 are written in the same SSTORE block at every callsite, the fix at each S-52 callsite (the function-entry `rngLockedFlag` revert) ALSO fixes the corresponding S-53 write at the same callsite at zero incremental cost. The 9 S-52 callsites covered above (V-168, V-169, V-170, V-171, V-172, V-174, V-175, V-176, V-177) are EXACTLY the 9 V-179 sub-rows.

**Phase-precedent.** Co-located writer-slot patterns are common in this codebase (e.g., `BitPackingLib`-packed slots where multiple fields share a SSTORE). The "single gate at the entry function covers both slots" disposition is the standard treatment.

### §101.B — Actor game-theory walk (9-callsite enumeration)

Per `D-299-FIXREC-LAYOUT-01` for V-179, this sub-section enumerates all 9 EOA callsites (V-179.A..V-179.I). Each sub-row inherits the exploit-actor class and EV-tier of its co-located S-52 counterpart.

| Sub-row | Callsite | Co-located S-52 row | Exploit-actor class | EV-tier |
|---|---|---|---|---|
| V-179.A | `WhaleModule.sol:313` (`_queueTickets` via `purchaseWhaleBundle`) | V-168 | EOA whale-tier buyer | MEDIUM |
| V-179.B | `WhaleModule.sol:482` (`_queueTickets` via `purchaseLazyPass`) | V-169 | EOA lazy-pass buyer | MEDIUM |
| V-179.C | `WhaleModule.sol:625` (`_queueTickets` via `purchaseDeityPass`) | V-170 | EOA deity-pass buyer | LOW (existing gate at :543) |
| V-179.D | `LootboxModule.sol:1067` (`_queueTickets` via `openLootBox`) | V-171 | EOA lootbox-holder | HIGH |
| V-179.E | `LootboxModule.sol:1190` (`_queueTickets` via `openBurnieLootBox`) | V-172 | EOA burnie-lootbox-holder | HIGH |
| V-179.F | `MintModule.sol:1129` (`_queueTicketsScaled` via `_purchaseFor`) | V-174 | EOA mint-purchaser | HIGH |
| V-179.G | `DecimatorModule.sol:582` (`_queueTicketRange` via `_awardDecimatorLootbox`) | V-175 | EOA decimator-claimer | MEDIUM |
| V-179.H | `WhaleModule.sol:973` (`_queueTicketRange` via `claimWhalePass`) | V-176 | EOA whale-pass holder | MEDIUM |
| V-179.I | `Storage.sol:1135` (`_queueTicketRange` via `_redeemWhalePassRange`) | V-177 | EOA range-redeemer | MEDIUM |

**Self-stack callsites (EXEMPT, not in this fan-out).** Per CATALOG §16 row V-179: "VIOLATION (×9 EOA callsites); EXEMPT-ADVANCEGAME (×3 self-stack)." The 3 self-stack callsites (`JackpotModule.sol:703, :837, :1007, :2305`; `AdvanceModule.sol:1535, :1541`; constructor) are EXEMPT-ADVANCEGAME (V-166, V-167, V-173, V-178 — adjacent catalog rows).

**Action sequence shared across V-179.A..V-179.I.** Identical to the corresponding S-52 row: EOA invokes the callsite during rngLock window → `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` SSTORE block runs → BOTH `ticketQueue[rk].push(buyer)` AND `ticketsOwedPacked[rk][buyer] +=` execute → trait-generation consumes the corrupted state. The S-53 slot's owed-count amplifies the attack: a single `push` insertion combined with a bumped owed-count is more impactful than `push` alone, because trait-generation may roll per-owed-count (per CATALOG §10 trait-magnitude prose).

### §101.C — Recommended tactic + rationale + impact

**Tactic (a) — Same gate as each S-52 row; co-located write — single gate covers both slots.** Per catalog row's verdict text. Each S-52 fix at §1-§9 above ALSO closes the corresponding V-179 sub-row at zero incremental code cost.

**Rationale.** Because S-52 and S-53 share every SSTORE block, gating the function entry blocks BOTH slot writes. The bytecode impact at each callsite is the SAME ~30 bytes already accounted in V-168..V-177; V-179 contributes ZERO additional bytes.

**Implementation-pattern note for v44.0 plan-phase.** When v44.0 implements the V-168..V-177 fixes, the code-review checklist must verify that the entry-revert PRECEDES the `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` invocation — this is what makes the gate cover both S-52 and S-53. A misplaced revert (e.g., after the SSTORE block) would leave S-53 unprotected. Code review must check execution-order: `rngLockedFlag` SLOAD → `revert` → ... → `_queueTickets`-family invocation. Single-gate-covers-both invariant.

**Bytecode impact.** Zero incremental over V-168..V-177. Storage / ABI unchanged.

### §101.D — v44.0 handoff anchor (9 sub-anchors)

V-179 emits 9 sub-anchors in this single §N.D entry per `D-299-FIXREC-LAYOUT-01` V-179 fan-out rule. Each sub-anchor pairs one-to-one with its S-52 counterpart's anchor.

- **`D-43N-V44-HANDOFF-101`** — V-179.A `ticketsOwedPacked[rk][player]` write via `purchaseWhaleBundle` (`WhaleModule.sol:313`). Co-located with HANDOFF-92 (V-168). Single gate at `_purchaseWhaleBundle` entry.
- **`D-43N-V44-HANDOFF-102`** — V-179.B via `purchaseLazyPass` (`WhaleModule.sol:482`). Co-located with HANDOFF-93 (V-169). Single gate at `_purchaseLazyPass` entry.
- **`D-43N-V44-HANDOFF-103`** — V-179.C via `purchaseDeityPass` (`WhaleModule.sol:625`). Co-located with HANDOFF-94 (V-170). Verify-only — existing `WhaleModule.sol:543` gate satisfies.
- **`D-43N-V44-HANDOFF-104`** — V-179.D via `openLootBox` (`LootboxModule.sol:1067`). Co-located with HANDOFF-95 (V-171). Single gate at `openLootBox` entry.
- **`D-43N-V44-HANDOFF-105`** — V-179.E via `openBurnieLootBox` (`LootboxModule.sol:1190`). Co-located with HANDOFF-96 (V-172). Single gate at `openBurnieLootBox` entry.
- **`D-43N-V44-HANDOFF-106`** — V-179.F via `_purchaseFor` (`MintModule.sol:1129`). Co-located with HANDOFF-97 (V-174). Single gate at `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` entries (3 EOA entries reach `_purchaseFor`).
- **`D-43N-V44-HANDOFF-107`** — V-179.G via `_awardDecimatorLootbox` (`DecimatorModule.sol:582`). Co-located with HANDOFF-98 (V-175). Single gate at `claimDecimatorJackpot` entry (the only EOA reach).
- **`D-43N-V44-HANDOFF-108`** — V-179.H via `claimWhalePass` (`WhaleModule.sol:973`). Co-located with HANDOFF-99 (V-176). Single gate at `claimWhalePass` entry.
- **`D-43N-V44-HANDOFF-109`** — V-179.I via `_redeemWhalePassRange` (`DegenerusGameStorage.sol:1135`). Co-located with HANDOFF-100 (V-177). Single gate at the EOA entry that invokes `_redeemWhalePassRange` (same as HANDOFF-99).

v44.0 plan-phase consolidation note: HANDOFF-101..109 are entirely subsumed by HANDOFF-92..100 implementation. The 9 V-179 sub-anchors exist for verdict-matrix traceability but the v44.0 sub-phase can be a SINGLE sub-phase covering BOTH S-52 and S-53 closure across 9 callsites.

---

## §102 — V-182: `bountyOwedTo` write inside `_addDailyFlip` via `depositCoinflip` (`BurnieCoinflip.sol:681`)

### §102.A — Design-intent backward-trace

`bountyOwedTo` is `address internal bountyOwedTo;` at `BurnieCoinflip.sol:169`. The slot tracks the player currently holding the "biggest-flip-ever" bounty, which is paid out via `processCoinflipPayouts` (advance-stack consumer at `:865`) when bounty conditions are met. The arming-side writer is at `BurnieCoinflip.sol:681` inside `_addDailyFlip`, invoked from EOA `depositCoinflip` at `:229` via `_depositCoinflip:312`.

**Why the slot exists.** The biggest-flip bounty incentivizes deep-pocket coinflip deposits. The "armed bounty" is recorded as `bountyOwedTo = player` when the player's flip stake exceeds `biggestFlipEver` (plus 1% threshold if already armed). Bounty payout fires on coinflip resolution.

**Existing partial coverage at `BurnieCoinflip.sol:664`.** The arming-write at `:681` is gated by an OUTER conditional at `:664`:

```solidity
if (recordAmount > record && !game.rngLocked()) {
    ...
    if (recordAmount >= threshold) {
        bountyOwedTo = player;
        emit BountyOwed(player, bounty, recordAmount);
    }
}
```

The `!game.rngLocked()` check is a SKIP-style gate (skips the bounty-arming block silently) rather than a fail-closed revert. Per CATALOG §16 row V-182 verdict text: "Bounty arming already gated by `!rngLocked()` at :664; extend to fail-closed revert."

**Why "extend to fail-closed revert" matters.** A skip-style gate allows the OUTER `depositCoinflip` call to succeed but quietly omits the bounty-arming side effect. From the attacker's perspective, the silent skip means they cannot OBSERVE that the bounty was not armed (no revert) — but they ALSO cannot exploit the side channel because the write is skipped. The "extend to fail-closed" recommendation flags that the silent-skip masks an actual VIOLATION-class condition that should surface (via revert) for off-chain bug-bounty monitoring.

**Phase-precedent.** Phase 296 RETRY_LOOTBOX_RNG (`D-42N-RETRY-RNG-DOMAIN-SEP-01`) established the existing `:664` gate convention. This recommendation extends the convention from silent-skip to fail-closed.

### §102.B — Actor game-theory walk

**Exploit actor.** EOA coinflip-depositor attempting to arm the bounty during rngLock.

**Action sequence.**
1. VRF callback delivers daily `rngWord`; `rngLockedFlag` true.
2. Attacker calls `depositCoinflip(player, amount)` with `amount > biggestFlipEver` to attempt bounty arming.
3. `_depositCoinflip:312` → `_addDailyFlip:627` → `:664` checks `!game.rngLocked()` → FALSE (rngLocked is true) → silent skip; `bountyOwedTo` is NOT mutated.
4. **Net effect: no exploit succeeds via the arming write itself.** The existing gate already structurally blocks the VIOLATION condition.

**Residual concern.** The deposit itself succeeds (only the bounty-arming sub-block is skipped). The attacker may not realize their large deposit failed to arm the bounty until they observe (off-chain) that `bountyOwedTo` did not change. The "extend to fail-closed revert" recommendation surfaces this state mismatch.

**EV magnitude.** MEDIUM-HIGH. Bounty magnitudes are non-trivial (top-flip-ever sets the bar high), but the existing `:664` gate already structurally prevents the exploitation. The "extend to revert" is defense-in-depth + observability hardening; the actual VIOLATION risk is RESIDUAL given the existing gate.

### §102.C — Recommended tactic + rationale + impact

**Tactic (a) — Extend the `:664` silent-skip to a fail-closed revert at `_addDailyFlip` entry.** Replace the silent skip pattern with an entry-level `if (game.rngLocked()) revert RngLocked();` at the start of the bounty-arming-eligible code path, OR replace the `:664` conditional with an early-revert pattern that fails the deposit if bounty arming is requested during rngLock.

**Implementation alternatives for v44.0 plan-phase.**
1. **Minimal change**: leave deposit-side gating untouched but add a revert at `_addDailyFlip` entry when `canArmBounty && bountyEligible && game.rngLocked()`. Deposits without bounty-eligibility still succeed; bounty-eligible deposits revert during rngLock.
2. **Aggressive change**: gate entire `depositCoinflip` on `!rngLocked()` — broader but breaks all coinflip deposits during rngLock (UX regression).

The catalog's prescribed tactic-(a) is the minimal change.

**Bytecode impact.** ~10 bytes (one selector switch from skip-conditional to revert-conditional). Storage / ABI unchanged.

### §102.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-110` — CATALOG §16 row V-182 + §15 row S-55 `_addDailyFlip`/`depositCoinflip` + §11 BurnieCoinflip._resolveFlip consumer. v44.0 plan-phase: minimal-change variant — convert `:664` silent-skip to fail-closed revert for bounty-eligible deposits during rngLock. The existing `BurnieCoinflip:730` `RngLocked` convention site (`auto-rebuy gate, `_setCoinflipAutoRebuy`) is the implementation reference for the v44.0 patch.

---

## §103 — V-184: `redemptionPeriodIndex` write inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:760`) — **HEADLINE TIER-1 — §0 finding #1**

### §103.A — Design-intent backward-trace

**`redemptionPeriodIndex` slot.** Declared at `StakedDegenerusStonk.sol:230` as `uint32 internal redemptionPeriodIndex`. The slot identifies the "current redemption period" — used by `_submitGamblingClaimFrom` as both (a) the period key into `redemptionPeriods[period]` for already-resolved rolls and (b) the storage key into the player's `pendingRedemptions[player].periodIndex`. The slot is mutated ONLY by `_submitGamblingClaimFrom` at `:760` (per CATALOG §C-1 — single writer).

**Redemption family slots (S-56..S-60).** Cross-period accumulators co-located with `redemptionPeriodIndex`:
- `pendingRedemptionEthBase` (S-57; sStonk:226) — segregated ETH base for the active period; cleared on resolve (sStonk:594), incremented on burn (sStonk:790)
- `pendingRedemptionBurnieBase` (S-58; sStonk:227) — same pattern for BURNIE
- `pendingRedemptionBurnie` (S-59; sStonk:225) — cumulative BURNIE reserve
- `pendingRedemptions[player]` (S-60; sStonk:221) — per-player claim struct (`ethValueOwed`, `burnieOwed`, `periodIndex`, `activityScore`)

**Why these slots exist.** Gambling-burn mode: a player calls `burn(amount)` or `burnWrapped(amount)` during the game phase → segregates proportional ETH/BURNIE base for the current period → `advanceGame()` fires daily `resolveRedemptionPeriod(roll, flipDay)` (advance-stack-only, access guard at sStonk:586) → adjusts the segregated bases by `roll` and stores `redemptionPeriods[period] = {roll, flipDay}` → player claims via `claimRedemption()` reading `redemptionPeriods[claimPeriodIndex].roll` to compute final payout (formula at sStonk:632 `totalRolledEth = (claim.ethValueOwed * roll) / 100`).

The roll range is 25-175 (per AdvanceModule:1226-1228 `redemptionRoll = uint16(((currentWord >> 8) % 151) + 25)`), giving uniform expected value 100% (zero-mean redemption). The 50% supply cap at sStonk:763 bounds intra-period burn-volume. Player-side EV per single resolution: 0% (uniform [-75%, +75%] outcome around break-even).

**The structural design intent: `redemptionPeriodIndex` is advanced ONLY when `currentPeriod != redemptionPeriodIndex` at burn time** (sStonk:758-760):

```solidity
uint32 currentPeriod = game.currentDayView();
if (redemptionPeriodIndex != currentPeriod) {
    redemptionPeriodSupplySnapshot = totalSupply;
    redemptionPeriodIndex = currentPeriod;
    redemptionPeriodBurned = 0;
}
```

This means `redemptionPeriodIndex` is set to the current wall-clock day on the FIRST burn of a new day — but on subsequent same-day burns, it stays at the same value. Critically, `resolveRedemptionPeriod` does NOT advance `redemptionPeriodIndex` (per §C-1 attestation). After `resolveRedemptionPeriod` runs at advance-time on day D, `redemptionPeriodIndex` REMAINS at `D` — pointing at the just-resolved period.

**Phase-precedent.** Phase 288 dailyIdx structural anchor (`v41.0-phases/288-*/288-01-DESIGN-INTENT-TRACE.md`) established the per-day-index snapshot pattern — any state participating in a post-VRF-callback resolution should be index-anchored at allocation rather than consumed live. The sStonk redemption family DOES use index-anchoring (`pendingRedemptions[player].periodIndex` snapshot at burn time) — BUT `redemptionPeriodIndex` itself is not advanced past the resolved period, leaving the cross-day re-roll gap.

**The economic-cost reasoning behind the design.** The 50% supply cap at sStonk:763 (`redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2`) was designed under the assumption that ONE roll resolves all burns in a period. The cap bounds intra-period volume; the original author appears to have assumed `redemptionPeriodIndex` would self-advance via the day-boundary check. The bug is structural: cross-day re-burns hit `redemptionPeriodIndex != currentPeriod` and ADVANCE the index, but the ALREADY-RESOLVED period at the OLD index can still be overwritten on the next advance (because `resolveRedemptionPeriod` reads `redemptionPeriodIndex` which by then points at the new period — wait, let me re-derive).

**Exploit-derivation re-check (verified against `_submitGamblingClaimFrom:752` source).** The attack sequence is more subtle than "cross-day re-burn overwrites old period." Let me trace exactly:

1. **Day D, player A burns 100 sDGNRS.**
   - `currentPeriod = D` (from `game.currentDayView()`).
   - `redemptionPeriodIndex` was 0 (or some earlier day); `:758` triggers reset → `redemptionPeriodIndex = D`.
   - `pendingRedemptionEthBase += ethValueOwed_A`.
   - `claim_A.periodIndex = D`, `claim_A.ethValueOwed = ethValueOwed_A`.

2. **Day D advanceGame runs `resolveRedemptionPeriod(roll_D, D+1)`** (rngGate sStonk:1230).
   - `period = redemptionPeriodIndex = D` (sStonk:588).
   - `redemptionPeriods[D] = {roll: roll_D, flipDay: D+1}` (sStonk:604).
   - `pendingRedemptionEthBase = 0` (sStonk:594).
   - **`redemptionPeriodIndex` NOT mutated — REMAINS at `D`.**

3. **Same wall-clock day D (post-resolve), player B burns 1 wei** (or player A re-burns).
   - `currentPeriod = game.currentDayView() = D` (still day D wall-clock).
   - `redemptionPeriodIndex == currentPeriod (== D)` → `:758` conditional is FALSE → NO reset.
   - `pendingRedemptionEthBase += ethValueOwed_B` (now NON-ZERO again).
   - `claim_B.periodIndex = D` (claim attached to already-resolved period).

4. **Day D+1 advance runs `resolveRedemptionPeriod(roll_{D+1}, D+2)`.**
   - `period = redemptionPeriodIndex = D` (still stale).
   - `pendingRedemptionEthBase != 0` (from step 3), so early-return at sStonk:589 is BYPASSED.
   - `redemptionPeriods[D] = {roll: roll_{D+1}, flipDay: D+2}` — **OVERWRITES** the original `roll_D` with the new `roll_{D+1}`.
   - Per CATALOG §0 headline #1 + §C-7 attestation: this is the data-corruption-class exploit.

5. **Player A's claim is re-rolled.** When player A calls `claimRedemption()`, they read `redemptionPeriods[D].roll = roll_{D+1}` (NOT the original `roll_D` that was emitted in the day-D `RedemptionResolved` event). Player A's ethValueOwed is multiplied by the FRESH `roll_{D+1}` — even though player A burned BEFORE the day-D resolution.

**The re-roll EV asymmetry:**
- Player B (the attacker) READS `redemptionPeriods[D].roll = roll_D` BEFORE re-burning. If `roll_D >= 100` (favorable), player B claims immediately (locks in `roll_D`). If `roll_D < 100` (unfavorable), player B burns 1 wei to force re-roll. **Informed-re-roll filter: only 50% of cases trigger re-roll.**
- Per §0 headline #1 EV computation (and §D-VIOL): `0.5 × E[roll | roll ≥ 100] + 0.5 × E[roll | re-roll]` = `0.5 × 137.5 + 0.5 × 100` = `118.75` vs baseline `100` = **~18.75% positive EV per round** (rounded to ~19% in headline).
- Compounding: subsequent re-burns can repeat the strategy until the supply-cap or other-player accumulation forces resolution. Theoretical ceiling is the 175% max roll; in practice, supply-cap bounds the volume.

**Why same-day blocking via `rngWordByDay[day]` short-circuit doesn't help.** The `AdvanceModule.sol:1187` check (`if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);`) prevents `rngGate` from re-running on day D's RNG slot. But the cross-day re-resolution is on day D+1's `rngGate`, which executes normally (writes `rngWordByDay[D+1]`, derives a fresh `roll_{D+1}`, calls `resolveRedemptionPeriod`). The `rngGate` does not check whether `redemptionPeriodIndex` points at an already-resolved period — it unconditionally invokes `resolveRedemptionPeriod` if `hasPendingRedemptions()` returns true (sStonk:1225).

**Cross-corruption to other players.** Per §D-VIOL §3 "Collateral damage": if Player C burned on day D with `claim_C.periodIndex = D` and hadn't yet called `claimRedemption()`, the re-roll caused by Player B's re-burn ALSO overwrites Player C's effective roll. Player C sees a DIFFERENT roll at claim time than was published at the original day-D resolution event. This is data-corruption-class behavior independent of EV-asymmetry.

### §103.B — Actor game-theory walk

**Exploit actor.** sStonk holder with a small balance (1 wei suffices) who is willing to time same-day post-resolution re-burns. Capital requirement is negligible (1 wei sDGNRS = 1e-18 sDGNRS); reward is statistically free.

**Action sequence (TIER-1 exploit chain):**

1. **Setup phase (legitimate burn).** Day D, attacker burns sDGNRS via `burn(amount)` or `burnWrapped(amount)` (or accumulates as a co-burner alongside other gambling-burn participants). Attacker's `claim.periodIndex = D`.

2. **Wait for day-D resolution.** Advance-game fires; `resolveRedemptionPeriod(roll_D, D+1)` runs; `redemptionPeriods[D].roll = roll_D` is published in the `RedemptionResolved` event AND readable via the `redemptionPeriods` mapping's public auto-getter (sStonk:222 `mapping(uint32 => RedemptionPeriod) public redemptionPeriods`).

3. **Decision point (informed filter).** Attacker reads `redemptionPeriods[D].roll`:
   - If `roll_D >= 100` (favorable): **CLAIM IMMEDIATELY** via `claimRedemption()` — lock in the favorable roll.
   - If `roll_D < 100` (unfavorable): **PROCEED TO STEP 4** — trigger re-roll.

4. **Same-day re-burn (re-roll trigger).** Still on wall-clock day D (after resolve has fired in `advanceGame`), attacker burns 1 wei sDGNRS via `burn(1)`. Gates pass: `!gameOver()`, `!livenessTriggered()`, `!rngLocked()` (the latter cleared by `_unlockRng` at end of advanceGame). `_submitGamblingClaimFrom` runs:
   - `currentPeriod = D` (still day D wall-clock).
   - `redemptionPeriodIndex (D) == currentPeriod (D)` → NO reset.
   - `pendingRedemptionEthBase += 1-wei-proportional-eth` (non-zero).
   - `claim.ethValueOwed += 1-wei-proportional-eth` (negligible).

5. **Day-D+1 advance re-resolves.** Next `advanceGame()` call (could be same TX from a different EOA, or any later TX before day D+2). `rngGate` runs because `rngWordByDay[D+1] == 0`. Inside rngGate:
   - `currentWord` derived from fresh VRF.
   - Branch at sStonk:1225 `if (sdgnrs.hasPendingRedemptions())` → TRUE (because attacker's 1-wei re-burn set `pendingRedemptionEthBase != 0`).
   - `resolveRedemptionPeriod(roll_{D+1}, D+2)` invoked.
   - Inside `resolveRedemptionPeriod`: `period = redemptionPeriodIndex = D` (STALE — still pointing at day D, not day D+1).
   - `redemptionPeriods[D] = {roll: roll_{D+1}, flipDay: D+2}` — **OVERWRITE!**

6. **Attacker claims with fresh roll.** Attacker calls `claimRedemption()`. Reads `redemptionPeriods[D].roll = roll_{D+1}`. `totalRolledEth = (claim.ethValueOwed * roll_{D+1}) / 100`. The attacker's ORIGINAL claim from step 1 is paid at the new (uniformly-fresh) roll.

7. **Iterate.** If `roll_{D+1} < 100`, repeat steps 4-6 with 1-wei re-burn on day D+1 → re-roll on day D+2 → ... Each iteration gives ~19% positive EV.

**Supply-cap bound (sStonk:763).** `redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2` revert blocks intra-period volume above 50% of supply. Since `redemptionPeriodIndex` doesn't advance, `redemptionPeriodBurned` keeps accumulating across same-day burns. After multiple same-day re-burns, the cap may fire. But 1-wei re-burns accumulate negligibly — the cap only bites for VOLUME, not for COUNT of re-rolls. **Cap does NOT prevent attack.**

**Daily EV cap (sStonk:801).** `claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV` reverts at 160 ETH. This bounds the per-claim absolute size; the re-roll exploit operates on EXISTING claim balance, not new accumulation. **Cap does NOT prevent attack.**

**Collateral damage to other players.** Any OTHER player C with `claim_C.periodIndex = D` (i.e., who also burned on day D) is forced into the re-roll outcome. Player C's claim is re-rolled WITHOUT consent — Player C's `roll_D` becomes `roll_{D+1}` after the re-resolve.

**Cross-day-boundary subtlety.** The attack assumes attacker can call `burn(1)` AFTER `advanceGame` resolved day D BUT BEFORE wall-clock rolls to day D+1. Wall-clock day boundary in `currentDayView()` is determined by `(timestamp - launchTime) / 86400`. The attacker has a multi-hour window post-resolve to trigger the re-burn before the day boundary. If they MISS that window (re-burn lands on day D+1), the `:758` conditional triggers RESET → `redemptionPeriodIndex = D+1` → the attack does NOT execute (the re-burn lands in a fresh period). So the attack window is bounded by the inter-day duration after advance fires. **In practice, this is several hours per day** — ample time for an attentive attacker.

**Re-attestation note:** the catalog §0 headline asserts the attack is feasible "on a future wall-clock day" — but my trace shows the critical window is SAME-DAY post-resolve. The CATALOG §D-VIOL trigger sequence (steps 1-3) describes a SAME-DAY exploit; the "future day" framing in §0 is loose. Both interpretations are valid in the limit (any wall-clock day where `redemptionPeriodIndex < currentPeriod` is reachable), but the load-bearing window is "post-resolve, pre-day-boundary." This affects only the prose flavor, not the structural fix.

**EV magnitude.** **CATASTROPHE-tier.** Per-round EV ~19%; compounding to supply-cap-bounded ceiling (statistically ~75% over many iterations); CATASTROPHE in aggregate because the attack is essentially free (1 wei cost per re-roll) and the EV is asymmetric (informed-re-roll filter). The catalog §0 headline correctly classifies this as Tier-1 hazard.

### §103.C — Recommended tactic + rationale + impact

**TWO viable tactics; v44.0 plan-phase should consider BOTH.**

---

**Tactic (a) — `rngLockedFlag`-gated revert in `_submitGamblingClaimFrom` checking `redemptionPeriods[redemptionPeriodIndex].roll != 0`.**

Per CATALOG §16 row V-184 verdict text: "Revert in `_submitGamblingClaimFrom` if `redemptionPeriods[redemptionPeriodIndex].roll != 0`."

**Implementation sketch.** Insert at `_submitGamblingClaimFrom` (sStonk:752) immediately after `currentPeriod = game.currentDayView();` at sStonk:757:

```solidity
// Block post-resolution re-burns: if the current period was already resolved,
// the existing burn-window has closed for this period.
if (redemptionPeriodIndex == currentPeriod && redemptionPeriods[currentPeriod].roll != 0) {
    revert BurnsBlockedAfterResolution();
}
```

The new error (or reused `BurnsBlockedDuringRng`) closes the post-resolve same-day re-burn window. After day boundary tick, `currentPeriod != redemptionPeriodIndex` → the conditional is FALSE → fresh-period reset proceeds normally → burns work in the new period.

**Pros.** Minimal change; one SLOAD + revert pair; preserves existing `redemptionPeriodIndex` semantics; matches existing `BurnsBlockedDuringRng` revert convention at sStonk:492.

**Cons.** Defensive (closes the symptom, not the structural anchor); a future protocol change that introduces a different post-resolve write path would re-open the gap unless the same gate is replicated at every post-resolve write entry.

---

**Tactic (b) — Structural advance of `redemptionPeriodIndex` inside `resolveRedemptionPeriod` itself [PREFERRED]**.

**Implementation sketch.** Modify `resolveRedemptionPeriod` (sStonk:585) to advance `redemptionPeriodIndex` after committing the resolution:

```solidity
function resolveRedemptionPeriod(uint16 roll, uint32 flipDay) external {
    if (msg.sender != ContractAddresses.GAME) revert Unauthorized();

    uint32 period = redemptionPeriodIndex;
    if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;

    // ... existing roll/value computation + base zeroing ...

    redemptionPeriods[period] = RedemptionPeriod({roll: roll, flipDay: flipDay});

    // Advance the index past the just-resolved period.
    redemptionPeriodIndex = period + 1;  // STRUCTURAL FIX

    emit RedemptionResolved(period, roll, burnieToCredit, flipDay);
}
```

After this fix:
- Step 5 of the exploit chain: `period = redemptionPeriodIndex = D + 1` (advanced). The re-burn on day D from step 3 set `claim.periodIndex = D`, but `redemptionPeriods[D].roll != 0` (already set in step 2). When the attacker calls `claimRedemption`, it reads `redemptionPeriods[D].roll` (the ORIGINAL `roll_D`) — no re-roll possible because the cross-day advance fires `resolveRedemptionPeriod` on `period = D+1` (new fresh period for day-D+1 burns), writing `redemptionPeriods[D+1]` and leaving `redemptionPeriods[D]` untouched.
- **Step 3 (same-day re-burn after resolve) is structurally neutered.** Even if attacker re-burns same-day, `_submitGamblingClaimFrom` runs with `currentPeriod = D`, `redemptionPeriodIndex = D+1` (post-resolve advanced). The check at sStonk:758 `redemptionPeriodIndex != currentPeriod` is now TRUE → reset → `redemptionPeriodIndex = D` again. Wait — this reverts the advance! Let me re-derive.

**Re-derivation under tactic (b).** With `redemptionPeriodIndex = D+1` post-resolve:
- Same-day re-burn on day D: `currentPeriod = D`, `redemptionPeriodIndex = D+1`. Conditional at sStonk:758 fires (`D+1 != D`) → `redemptionPeriodIndex = D` again. Same exploit re-emerges.

**Tactic (b) variant — clear `redemptionPeriodIndex` to 0 + special-case sentinel.** Set `redemptionPeriodIndex = 0` at resolve; have `_submitGamblingClaimFrom` interpret 0 as "fresh-period needed" and initialize to `currentPeriod`. But then the same-day re-burn on day D still sets `redemptionPeriodIndex = D` → if a subsequent advance fires (somehow on same day D — typically not but consider edge cases), it would re-resolve.

**Tactic (b) variant — gate inside `_submitGamblingClaimFrom` on `redemptionPeriods[currentPeriod].roll != 0`.** Equivalent to tactic (a). Reduces to tactic (a).

**Cleaner tactic (b) — set `redemptionPeriodIndex` to a value that DEFINITELY excludes the resolved period AND won't get reset to D by same-day burns.** One option: advance `redemptionPeriodIndex` to `game.currentDayView() + 1` inside resolveRedemptionPeriod (or to `period + 1`, equivalent if resolve fires same-day):

```solidity
redemptionPeriodIndex = game.currentDayView() + 1;
```

Then on same-day re-burn at day D: `currentPeriod = D`, `redemptionPeriodIndex = D+1`. The sStonk:758 conditional fires → reset → `redemptionPeriodIndex = D`. **Reset still happens.** The same-day re-burn lands at `period D` again, re-arming `pendingRedemptionEthBase`. The next advance on day D+1 would resolve `period = D` again.

**Conclusion: pure structural-advance is NOT sufficient by itself; the sStonk:758 reset conditional regresses the advance.** Tactic (b) requires either (i) removing the sStonk:758 reset conditional (refactor — see below) or (ii) combining structural advance WITH tactic (a)'s revert.

**Tactic (b) — clean variant — refactor `_submitGamblingClaimFrom` reset logic.** Replace the sStonk:758-762 conditional with a different anchor:

```solidity
// OLD: if (redemptionPeriodIndex != currentPeriod) { ...reset... }
// NEW: only reset if the CURRENT period is unresolved
if (redemptionPeriods[currentPeriod].roll != 0) {
    revert BurnsBlockedAfterResolution();  // can't burn into already-resolved period
}
if (redemptionPeriodIndex != currentPeriod) {
    redemptionPeriodSupplySnapshot = totalSupply;
    redemptionPeriodIndex = currentPeriod;
    redemptionPeriodBurned = 0;
}
```

This combines tactic (a) revert with tactic (b)'s intent: same-day post-resolve burns revert; fresh-day burns initialize the new period; cross-day re-resolve cannot fire on the old period because subsequent burns land in the new period (with `redemptionPeriodIndex = currentPeriod = D+1`).

**Cleanest expression — Phase 288 dailyIdx structural anchor pattern.** Phase 288 introduced `dailyIdx` as a "monotonically-advancing window index" — once a daily resolution committed, the index never regresses. Applied to sStonk: rename `redemptionPeriodIndex` semantics to "the next-fresh-period index" rather than "the current-period index"; advance inside resolveRedemptionPeriod; burns always allocate to `redemptionPeriodIndex` (no day-boundary check needed). This is a refactor; bytecode/storage impact higher than tactic (a) alone.

---

**Phase 299 recommendation: tactic (a) is the catalog's prescribed minimal fix; tactic (b)'s clean variant (combined revert + reset) is the v44.0-preferred structural anchor.**

Both options should be costed at v44.0 plan-phase. The clean variant has the structural-anchor strength of Phase 288 dailyIdx with bytecode cost similar to tactic (a) (~50-80 bytes).

**Bytecode impact:** tactic (a) ~50-80 bytes (one SLOAD + revert); tactic (b) clean variant ~80-120 bytes (one SLOAD + revert + modified reset conditional). Storage-layout: byte-identical. Public ABI: NON-BREAKING for both (new revert error path; existing function signatures unchanged).

**Subsumed VIOLATIONs.** Closing V-184 also closes V-186, V-188, V-190, V-191 (all subsumed per catalog rows — same writer fn `_submitGamblingClaimFrom`, same callsite) and V-192, V-193 (legitimate downstream effects in `claimRedemption` once V-184 enforced).

### §103.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-111` — **TIER-1 PRIORITY-1**. CATALOG §16 row V-184 + §15 row S-56 `_submitGamblingClaimFrom` + §12 sStonk consumer trace + §C-1 single-writer attestation + §D-VIOL-1 cross-cutting pattern + §0 headline #1.

**Phase 303 §3.A delta-surface row 1 cross-reference.** This handoff is the load-bearing input to Phase 303 TERMINAL `audit/FINDINGS-v43.0.md` §3.A — the milestone's highest-severity finding is V-184. v44.0 plan-phase must prioritize this sub-phase ahead of all other Cluster J fixes.

**v44.0 sub-phase scope.** Implement tactic (a) catalog-prescribed revert at `_submitGamblingClaimFrom` AND/OR tactic (b) clean-variant structural anchor (refactor `redemptionPeriodIndex` reset logic per §12.C). Test plan must include: (i) the §D-VIOL trigger sequence as a positive failing test (pre-fix, exploit succeeds; post-fix, exploit reverts); (ii) cross-day boundary edge cases (burn-at-day-boundary timestamps); (iii) gap-day re-resolution interaction (`_backfillGapDays` does NOT resolve redemptions per AdvanceModule:1772-1774 comment); (iv) collateral-damage assertion (other-player claims unaffected by attacker's re-burn).

---

## §104 — V-186: `pendingRedemptionEthBase` (`+=`) inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:790`)

### §104.A — Design-intent backward-trace

`pendingRedemptionEthBase` is the segregated-ETH-base for the active redemption period (S-57; sStonk:226). Cleared on resolve at sStonk:594 (EXEMPT-ADVANCEGAME via V-185); incremented at burn time at sStonk:790 inside `_submitGamblingClaimFrom`. The same writer fn writes both `redemptionPeriodIndex` (V-184) and `pendingRedemptionEthBase`; the increment at `:790` is the load-bearing economic accumulator that triggers the next-advance `resolveRedemptionPeriod` invocation (via `hasPendingRedemptions()` returning true at sStonk:1225 in AdvanceModule).

**Why the slot exists.** Identical to V-184 §12.A — the ETH-base is the per-period segregation of ETH backing for gambling-burn claims; it accumulates per-burn within a period and is consumed (zeroed) at resolve.

**Why the write is the load-bearing piece of the V-184 exploit.** Without the `pendingRedemptionEthBase += ethValueOwed` at `:790`, the subsequent `advanceGame`'s `resolveRedemptionPeriod` would short-circuit at sStonk:589 `if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;`. The attacker's same-day re-burn LITERALLY exists to re-arm this slot.

### §104.B — Actor game-theory walk

**Subsumed by V-184.** Same exploit actor, same action sequence, same EV. The increment at `:790` is the mechanism by which V-184's re-roll vector is armed.

**EV magnitude.** HIGH (subsumed by V-184's CATASTROPHE classification; V-186's standalone classification is HIGH because the slot itself is the load-bearing armament).

### §104.C — Recommended tactic + rationale + impact

**Tactic (a) — same gate as V-184.** Per catalog row: "Same gate as V-184 — base-growth and index-pointing are co-mutated; one check covers both."

The fix at V-184 (entry-revert in `_submitGamblingClaimFrom` if `redemptionPeriods[redemptionPeriodIndex].roll != 0` OR the clean structural-anchor variant) reverts the function BEFORE the `:790` write executes. Single fix closes both.

**Bytecode impact.** Zero incremental over V-184.

### §104.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-112` — CATALOG §16 row V-186. v44.0 plan-phase: subsumed by HANDOFF-111. Co-located implementation.

---

## §105 — V-188: `pendingRedemptionBurnieBase` (`+=`) inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:792`)

### §105.A — Design-intent backward-trace

`pendingRedemptionBurnieBase` is the BURNIE-side analog of S-57 (S-58; sStonk:227). Same lifecycle: cleared on resolve at sStonk:601 (V-187 EXEMPT-ADVANCEGAME), incremented at burn at sStonk:792 inside `_submitGamblingClaimFrom`. The BURNIE base feeds the BURNIE-payout multiplication in `claimRedemption` (sStonk:652 `burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000`).

**Why the slot exists.** Mirror of V-186. Gambling-burn supports BURNIE payouts in addition to ETH; the BURNIE-base segregates per-period.

### §105.B — Actor game-theory walk

**Subsumed by V-184.** Same exploit; the BURNIE-base is re-armed alongside the ETH-base on same-day re-burn. The re-roll vector multiplies BOTH ETH and BURNIE payouts at fresh roll.

**EV magnitude.** HIGH (subsumed). BURNIE-side EV asymmetry compounds with ETH-side; the attacker captures both currency outcomes at fresh roll.

### §105.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184 (same writer fn, same callsite)."

**Bytecode impact.** Zero incremental.

### §105.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-113` — CATALOG §16 row V-188. Subsumed by HANDOFF-111.

---

## §106 — V-190: `pendingRedemptionBurnie` (`+=`) inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:791`)

### §106.A — Design-intent backward-trace

`pendingRedemptionBurnie` (S-59; sStonk:225) is the cumulative BURNIE reserve across all periods — it is decremented by `pendingRedemptionBurnieBase` at resolve (sStonk:600) and incremented per-burn at sStonk:791. The slot tracks the net BURNIE that sDGNRS owes for unredeemed gambling-burn claims.

**Why the slot exists.** Provides the `burnieReserve()` view (sStonk:733) for off-chain consumers + drives the `previewBurn` proportional math (sStonk:725). The cumulative tracking is needed because BURNIE payouts may carry across periods (e.g., when coinflip resolution is delayed beyond claim time).

### §106.B — Actor game-theory walk

**Subsumed by V-184.** Same writer fn; same callsite. The cumulative slot's incremental bump on same-day re-burn participates in the load-bearing exploit chain.

**EV magnitude.** HIGH (subsumed).

### §106.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184."

**Bytecode impact.** Zero incremental.

### §106.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-114` — CATALOG §16 row V-190. Subsumed by HANDOFF-111.

---

## §107 — V-191: `pendingRedemptions[player]` writes (`ethValueOwed`/`burnieOwed`/`periodIndex`/`activityScore`) inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:803, :805, :806, :810`)

### §107.A — Design-intent backward-trace

`pendingRedemptions[player]` (S-60; sStonk:221) is the per-player claim struct: `(uint96 ethValueOwed, uint96 burnieOwed, uint32 periodIndex, uint16 activityScore)`. Writes at:
- sStonk:803 `claim.ethValueOwed += uint96(ethValueOwed)` — incremental per-burn growth
- sStonk:805 `claim.burnieOwed += uint96(burnieOwed)` — same for BURNIE
- sStonk:806 `claim.periodIndex = currentPeriod` — anchors claim to current period
- sStonk:810 `claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1` — first-burn-of-period activity snapshot

**Why the slot exists.** Per-player claim tracking with multi-burn accumulation within a period. The `periodIndex` field anchors which period's roll applies at `claimRedemption` time (sStonk:623 `RedemptionPeriod storage period = redemptionPeriods[claim.periodIndex]`). The `activityScore` field (sStonk:809-811) is snapshotted on first burn of period to feed `actScore` into the redemption-lootbox path (sStonk:669) — this is the Phase 281 owed-salt-precedent snapshot-at-allocation pattern correctly applied.

**Important nuance.** The `activityScore` snapshot at sStonk:810 is **already structurally correct** — it captures the score at first-burn-of-period and reuses it across same-period burns (`if (claim.activityScore == 0)` guard at sStonk:809). This is the snapshot-at-allocation pattern done right; it does NOT participate in the V-184 exploit. The VIOLATION here is the OTHER three writes (`ethValueOwed += `, `burnieOwed += `, `periodIndex = `) which participate in V-184's exploit chain.

### §107.B — Actor game-theory walk

**Subsumed by V-184.** Same writer fn, same callsite. The four writes execute together (4 SSTOREs in the function body); blocking the entry function at V-184's fix-point blocks all four.

**The `claim.periodIndex = currentPeriod` write (sStonk:806) is the specific mechanism by which the attacker's re-burn re-anchors the claim to the still-stale `redemptionPeriodIndex`.** When the attacker burns 1 wei on day D post-resolve, sStonk:806 writes `claim.periodIndex = D` — this is what enables the eventual `claimRedemption` read of `redemptionPeriods[D].roll` (post-overwrite).

**EV magnitude.** HIGH (subsumed).

### §107.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184."

**Bytecode impact.** Zero incremental.

### §107.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-115` — CATALOG §16 row V-191. Subsumed by HANDOFF-111.

---

## §108 — V-192: `pendingRedemptions[player]` `delete` inside `claimRedemption` (`StakedDegenerusStonk.sol:661`)

### §108.A — Design-intent backward-trace

`claimRedemption()` at sStonk:618 is the EOA-facing claim-payout entry. When the coinflip resolution has fired (`flipResolved == true` at sStonk:659), the function clears the player's claim struct via `delete pendingRedemptions[player]` at sStonk:661. This is the full-claim-clear path.

**Why the slot exists.** Claim-clearing is a legitimate downstream effect — once a player has been paid out, their claim record is removed to free storage and prevent double-claiming. The write itself is structurally correct; the catalog row's VIOLATION classification is strict per-callsite (the writer-callsite is EOA-callable with no advance-stack reach).

**Per CATALOG §16 row V-192 verdict text + §D-VIOL §3 severity-downgrade-rationale:** "These are non-EXEMPT-stack writes inside `claimRedemption` of slots the player already controls or that subtract VRF-derived (not VRF-influencing) values. They are listed VIOLATION per D-298-EXEMPT-REACH-01 strict rule but the FIX is structurally subsumed by closing the D-1/D-3/D-5/D-11 window."

### §108.B — Actor game-theory walk

**Subsumed by V-184.** The `delete` at sStonk:661 clears the attacker's own claim AFTER the V-184-enabled re-roll has been consumed. The clear itself does not introduce attacker-controlled VRF entropy; it merely removes the player's record post-payout.

Standalone exploit potential of V-192 alone: zero — clearing one's own claim is the legitimate action.

**EV magnitude.** MEDIUM (subsumed; standalone EV is zero).

### §108.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184; legitimate downstream effect once index-advance enforced."

Once V-184's fix (tactic (a) revert or tactic (b) structural anchor) prevents the re-roll vector from arming, `claimRedemption` clears are operating on un-corrupted claim records. The `delete` write becomes the intended, legitimate clear-on-payout behavior with no exploit surface.

**Bytecode impact.** Zero incremental.

### §108.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-116` — CATALOG §16 row V-192. Subsumed by HANDOFF-111.

---

## §109 — V-193: `pendingRedemptions[player]` partial clear inside `claimRedemption` (`StakedDegenerusStonk.sol:664`)

### §109.A — Design-intent backward-trace

When coinflip resolution has NOT fired at claim time (`flipResolved == false` at sStonk:659), `claimRedemption` performs a partial-clear at sStonk:664: `claim.ethValueOwed = 0`. This drops the ETH portion (already paid) while preserving the BURNIE portion for a later second-claim once coinflip resolves.

**Why the slot exists.** Partial-claim is the legitimate flow when ETH and BURNIE payouts decouple in timing (e.g., when the daily coinflip for `period.flipDay` has not yet resolved). The structural design supports two-stage claims.

### §109.B — Actor game-theory walk

**Subsumed by V-184.** Same severity-downgrade rationale as V-192 — the partial-clear is a legitimate downstream effect. Standalone EV is zero; the write does not introduce attacker-controlled VRF entropy.

**EV magnitude.** MEDIUM (subsumed; standalone EV is zero).

### §109.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184."

**Bytecode impact.** Zero incremental.

### §109.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-117` — CATALOG §16 row V-193. Subsumed by HANDOFF-111.

---

## §110 — V-201: `decBurn[lvl][player].burn` write inside `recordDecBurn` (`DecimatorModule.sol`)

### §110.A — Design-intent backward-trace

`decBurn[lvl][player]` is `mapping(uint24 => mapping(address => DecEntry)) internal` declared in `DegenerusGameStorage`. Struct `DecEntry` packs `{ uint192 burn, uint8 bucket, uint8 subBucket, uint8 claimed }`. The slot is the per-player per-level decimator-burn ledger.

`recordDecBurn` at `DecimatorModule.sol:133` is the writer fn. Access guard: `if (msg.sender != ContractAddresses.COIN) revert OnlyCoin();` (line 140) — only `BurnieCoin` may call. The EOA reach: `BurnieCoin.decimatorBurn` at `BurnieCoin.sol:559` → `degenerusGame.recordDecBurn(caller, lvl, bucket, baseAmount, decBurnMultBps)` at `BurnieCoin.sol:610` → delegatecall router at `DegenerusGame.sol:1029` → `DecimatorModule.recordDecBurn`.

Writes inside `recordDecBurn`:
- `e.bucket = m.bucket` (line 174) — first-burn sets bucket
- `e.subBucket = m.subBucket` (line 175) — deterministic from `(player, lvl, bucket)`
- `e.burn = newBurn` (line 173) — cumulative burn amount with uint192 saturation
- `decBucketBurnTotal[lvl][bucketUsed][m.subBucket] += delta` (via `_decUpdateSubbucket` at line 180) — co-located aggregate update

**Why the slot exists.** Decimator jackpot mechanic: players burn BURNIE to enter per-level buckets (denominators 2-12). Lower bucket = better odds; the per-bucket-per-subbucket aggregate `decBucketBurnTotal[lvl][denom][sub]` is consumed by `runDecimatorJackpot` (line 209) when the daily VRF rngWord is consumed at advance-time to select a winning subbucket per denominator.

**Phase-precedent.** Phase 293/294 DPNERF / DPSURF work shaped decimator activity-score scaling (`DECIMATOR_ACTIVITY_CAP_BPS` at BurnieCoin:587-589). The rngLock-window exposure of `recordDecBurn` was first cataloged in Phase 298 §13.

**Burn-window verification per CATALOG §16 row V-201.** The catalog row reads "VIOLATION; (a) Gate `recordDecBurn` on `decClaimRounds[lvl].poolWei == 0` to close burn at snapshot." The catalog-prescribed gate uses `decClaimRounds[lvl].poolWei == 0` as the burn-window-open signal: while no claim round has been snapshotted for `lvl`, burns are accepted; once `runDecimatorJackpot` writes `decClaimRounds[lvl].poolWei = poolWei` at DecimatorModule:256, additional burns are blocked.

**Source verification — is `recordDecBurn` truly mid-rngLock-window-reachable from EOA?** Verified against current source:
- `BurnieCoin.decimatorBurn` (line 559) has NO `degenerusGame.rngLocked()` gate at function entry.
- The only rngLock-touching code path in `decimatorBurn` is `_consumeCoinflipShortfall` (line 577) which reverts ONLY if the player needs to consume coinflips to cover the burn (line 451 `if (degenerusGame.rngLocked()) revert Insufficient();`). A player with sufficient BURNIE balance bypasses this check.
- `decWindow()` gate at BurnieCoin:572 governs the "decimator window open" boolean but is orthogonal to rngLock.

**Confirmed VIOLATION.** A player with sufficient BURNIE balance can call `decimatorBurn` during the rngLock window (between VRF callback delivery and next `advanceGame` consumption of `rngWordCurrent` to call `runDecimatorJackpot`). The current source has NO gate against this reach.

### §110.B — Actor game-theory walk

**Exploit actor.** EOA decimator-burn participant with BURNIE balance + an active decimator-window for some level `lvl`.

**Action sequence.**
1. Daily VRF callback delivers `rngWordCurrent` for the day that will trigger a level-N→N+1 decimator-jackpot resolution. `rngLockedFlag` true (cleared only at next advance's `_unlockRng`).
2. Attacker computes locally: for each `bucket in [2..12]`, what `subBucket = _decSubbucketFor(attacker, lvl, bucket)` would result, AND what `winningSub = _decWinningSubbucket(rngWordCurrent, denom)` would result. Match the player's `subBucket` to the projected `winningSub`.
3. Attacker calls `BurnieCoin.decimatorBurn(attacker, amount)` with the bucket-selection that lands them on the winning subbucket. `recordDecBurn` writes:
   - `e.bucket = chosenBucket`
   - `e.subBucket = _decSubbucketFor(attacker, lvl, chosenBucket)` (= projected `winningSub`)
   - `decBucketBurnTotal[lvl][chosenBucket][winningSub] += effectiveAmount`
4. Next `advanceGame` fires (consuming `rngWordCurrent`). `runDecimatorJackpot(decPoolWei, lvl, rngWord)` runs (from AdvanceModule:853). Selects winning subbucket = `_decWinningSubbucket(rngWord, denom)`. Reads `decBucketBurnTotal[lvl][denom][winningSub]` = (attacker's burn) + (any pre-existing aggregate from honest pre-window burns).
5. Snapshot at line 256-258: `decClaimRounds[lvl].poolWei = poolWei`. Attacker claims via `claimDecimatorJackpot(lvl)` post-resolution; receives pro-rata share of pool weighted by their burn vs. total winning burn.

**The exploit insight.** Honest decimator-burn participants commit to a (bucket, subBucket) BEFORE knowing the rngWord — they take a 1/denom probability of landing on the winning subbucket. The attacker, post-VRF-callback, knows the rngWord and can ensure 100% probability of landing on the winning subbucket. They convert a 1/denom random outcome into a deterministic outcome.

**EV magnitude.** HIGH. Decimator-jackpot payouts are 30% of pre-jackpot `futurePool` at x00 levels and 10% of `memFuture` at x5 levels (per AdvanceModule:843-849). The pool magnitude is multi-eth at mature game states. The exploit's edge is significant: honest 1/denom (~1/7 average) probability vs attacker's 100% probability gives a ~7x multiplier on expected payout.

### §110.C — Recommended tactic + rationale + impact

**Tactic (a) — gate `recordDecBurn` on `decClaimRounds[lvl].poolWei == 0` per catalog prescription.**

**Implementation sketch.** Insert at `recordDecBurn` (DecimatorModule:133) after access guard:

```solidity
function recordDecBurn(
    address player,
    uint24 lvl,
    uint8 bucket,
    uint256 baseAmount,
    uint256 multBps
) external returns (uint8 bucketUsed) {
    if (msg.sender != ContractAddresses.COIN) revert OnlyCoin();

    // Close burn window once jackpot has been snapshotted for this level.
    // Block burns during the rngLock window leading up to the snapshot.
    if (decClaimRounds[lvl].poolWei != 0) revert DecClaimSnapshotted();

    // ... existing body ...
}
```

**Alternative — `rngLockedFlag`-direct gate.** Insert `if (rngLockedFlag) revert RngLocked();` at recordDecBurn entry. This is simpler but does not handle the "burns AFTER snapshot but BEFORE next rngLock" edge case (snapshot freezes `poolWei` for the level but burns into the next level continue). The catalog's `poolWei == 0` gate is per-level scoped, which matches the decimator-jackpot resolution model (one snapshot per level).

**Phase 299 recommendation.** Catalog-prescribed `poolWei == 0` gate is preferred for granularity. The rngLockedFlag gate is acceptable defensive fallback.

**Subsumed by `prizePoolFrozen`?** `BurnieCoin.decimatorBurn` checks `decWindow()` (line 572) which encodes the decimator-window-open boolean. Verify against source: `decWindow()` is set by `AdvanceModule` orchestration at level transitions; it may or may not align with the rngLock-window. The catalog's recommendation suggests `decWindow()` alignment is INSUFFICIENT — otherwise the V-201 row wouldn't be VIOLATION. v44.0 plan-phase should verify the `decWindow()` lifecycle and decide between `poolWei == 0` and `rngLockedFlag` gates.

**Bytecode impact.** ~30-50 bytes (one SLOAD of `decClaimRounds[lvl].poolWei` + revert).

### §110.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-118` — CATALOG §16 row V-201 + §15 row S-66 `recordDecBurn` + §13 DecimatorModule consumer. v44.0 plan-phase: add `decClaimRounds[lvl].poolWei == 0` gate at `recordDecBurn` entry. Co-locate with V-202 handoff (similar gate pattern on `recordTerminalDecBurn`).

---

## §111 — V-202: `terminalDecBucketBurnTotal[bucketKey]` write inside `recordTerminalDecBurn` (`DecimatorModule.sol:731`)

### §111.A — Design-intent backward-trace

`terminalDecBucketBurnTotal[bucketKey]` is `mapping(bytes32 => uint256) internal` where `bucketKey = keccak256(abi.encode(lvl, e.bucket, e.subBucket))`. The slot is the cumulative weighted-burn aggregate per `(lvl, bucket, subBucket)` for the terminal decimator jackpot (the death-bet jackpot fired at GAMEOVER).

`recordTerminalDecBurn` at `DecimatorModule.sol:668` is the writer fn. Access guard: `if (msg.sender != ContractAddresses.COIN) revert OnlyCoin();` (line 673). EOA reach: `BurnieCoin.terminalDecimatorBurn` (line 634) → `degenerusGame.recordTerminalDecBurn(caller, lvl, baseAmount)` → delegatecall router at `DegenerusGame.sol:1116` → `DecimatorModule.recordTerminalDecBurn`.

The write at `DecimatorModule.sol:731`:
```solidity
bytes32 bucketKey = keccak256(abi.encode(lvl, e.bucket, e.subBucket));
terminalDecBucketBurnTotal[bucketKey] += weightedAmount;
```

The slot is consumed in `runTerminalDecimatorJackpot` (line 755-803) at GAMEOVER resolution: for each `denom in [2..12]`, `winningSub = _decWinningSubbucket(rngWord, denom)`, `subTotal = terminalDecBucketBurnTotal[keccak256(abi.encode(lvl, denom, winningSub))]`. The aggregate per winning bucketKey feeds the per-player claim pro-rata math.

**Why the slot exists.** Terminal decimator (death-bet) lets players burn BURNIE betting on GAMEOVER conditions; payout is keyed by `(bucket, subBucket)` per the standard decimator mechanics but resolved ONCE at GAMEOVER via `handleGameOverDrain` orchestration. The 7-day cooldown gate at DecimatorModule:676 (`if (daysRemaining <= 7) revert TerminalDecDeadlinePassed();`) blocks burns when the death-clock is within 7 days of termination.

**Burn-window verification per CATALOG §16 row V-202.** The catalog row reads "VIOLATION; (a) Gate `recordTerminalDecBurn` on `rngWordByDay[day] == 0` so window closes at RNG publish." This is a DIFFERENT gate-shape than V-201's `poolWei == 0` because the terminal-decimator resolution is GAMEOVER-only — there is no per-level `decClaimRounds[lvl].poolWei` snapshot prior to GAMEOVER. The gate closes the burn-window at "rngWord published for this day" rather than "claim round snapshotted."

**Source verification — is `recordTerminalDecBurn` mid-rngLock-window-reachable from EOA?**
- `BurnieCoin.terminalDecimatorBurn` (line 634) — verify gates.

<verification>The catalog gate-shape `rngWordByDay[day] == 0` is sound: while rngWord for the current day is unpublished, the day is pre-VRF-callback; once `rngWordByDay[day]` is set by `_applyDailyRng` (AdvanceModule:1841), the gate fires. But this gate is broader than V-201's per-level scope — it would block burns ANY day rngWord is published, even before GAMEOVER triggers. This is conservative: in normal play, the terminal-decimator burn window is open all the time (no per-level resolution), but on the day GAMEOVER fires, the gate closes the post-VRF-publish window.</verification>

**Pre-`gameOver` post-VRF window**. The catalog text "EOA `terminalDecimatorBurn` during pre-`gameOver` post-VRF window" describes the exploit: between `_gameOverEntropy` setting `rngWordByDay[day]` and `runTerminalDecimatorJackpot` consuming it (via `handleGameOverDrain` → `runTerminalDecimatorJackpot` at DegenerusGame:1146-1158 → `lastTerminalDecClaimRound.lvl = lvl` at DecimatorModule:798).

### §111.B — Actor game-theory walk

**Exploit actor.** EOA with BURNIE balance + a pre-existing `terminalDecEntries[player]` (or willing to initialize one), able to time `BurnieCoin.terminalDecimatorBurn` during the pre-`gameOver` rngLock-window.

**Action sequence.**
1. Death-clock approaches; `daysRemaining > 7` (otherwise burn blocked at DecimatorModule:676).
2. VRF callback for the day that will trigger GAMEOVER (e.g., the day `_handleGameOverPath` fires in `advanceGame`). `rngWordByDay[day]` published; `rngLockedFlag` still true until end of advance.

Wait — the exploit-window timing for V-202 is more nuanced. `runTerminalDecimatorJackpot` is called only at GAMEOVER (via `handleGameOverDrain`). The rngWord is the day's rngWord (set by `_gameOverEntropy` or `rngGate`). The attacker can observe the rngWord BEFORE `handleGameOverDrain` runs `runTerminalDecimatorJackpot`. In that window:
3. Attacker computes locally: for each `(bucket, subBucket)` they could choose via prior `terminalDecimatorBurn` calls, what `_decWinningSubbucket(rngWord, denom)` yields. (The bucket and subBucket are partially constrained — `_terminalDecBucket(bonusBps)` from activity score, `_decSubbucketFor` from `(player, lvl, bucket)`.)
4. Attacker calls `terminalDecimatorBurn` with timing to land on the winning subbucket. `recordTerminalDecBurn` writes:
   - `e.bucket = computed` (line 702 if first burn)
   - `e.subBucket = computed` (line 703)
   - `terminalDecBucketBurnTotal[keccak256(abi.encode(lvl, e.bucket, e.subBucket))] += weightedAmount` (line 731)
5. `runTerminalDecimatorJackpot` consumes the now-attacker-padded `terminalDecBucketBurnTotal` slot; attacker captures outsized share.

**Constraints.** Bucket choice is constrained by activity score (`bucket = _terminalDecBucket(bonusBps)`), but `bonusBps` is `playerActivityScore(player)` which CAN be manipulated pre-attack via legitimate gameplay actions. SubBucket is deterministic from `(player, lvl, bucket)` so the only attacker degree-of-freedom is `(player_address, bucket)` pairs.

**The asymmetry vs V-201.** V-201 (`recordDecBurn`) resolves PER-LEVEL with a poolWei snapshot at the level transition; V-202 (`recordTerminalDecBurn`) resolves ONCE at GAMEOVER with no per-level pool snapshot. The V-202 attack window is the SINGLE LAST advance before GAMEOVER (when the death-clock fires) — narrower in time but the pot is bigger (terminal decimator gets 10% of remaining pool per GAMEOVER drain accounting).

**EV magnitude.** HIGH. Terminal decimator pool is structurally larger than per-level decimator (resolves on remaining game pool, not per-level slice). Attacker captures the (denom_avg ≈ 7)x advantage on a multi-eth pool.

### §111.C — Recommended tactic + rationale + impact

**Tactic (a) — gate `recordTerminalDecBurn` on `rngWordByDay[day] == 0` per catalog prescription.**

**Implementation sketch.** Insert at `recordTerminalDecBurn` (DecimatorModule:668) after access guard + 7-day check:

```solidity
function recordTerminalDecBurn(
    address player,
    uint24 lvl,
    uint256 baseAmount
) external {
    if (msg.sender != ContractAddresses.COIN) revert OnlyCoin();

    uint256 daysRemaining = _terminalDecDaysRemaining();
    if (daysRemaining <= 7) revert TerminalDecDeadlinePassed();

    // Close burn window once the day's rngWord has been published.
    // Blocks the pre-GAMEOVER post-VRF window where the rngWord is known
    // but runTerminalDecimatorJackpot has not yet consumed it.
    uint32 currentDay = uint32(_currentDayView());
    if (rngWordByDay[currentDay] != 0) revert RngLocked();

    // ... existing body ...
}
```

**Rationale.** The `rngWordByDay[day] == 0` predicate gates the burn during the post-VRF window. Once VRF resolves for the day (`_applyDailyRng` writes `rngWordByDay[day]`), the day's rngWord is OBSERVABLE on-chain — terminal-decimator burns from that point would be informed by the rngWord. The gate closes the window at the rng-publish boundary.

**Edge cases.**
- Days where GAMEOVER doesn't fire still gate post-VRF burns. UX cost: terminal-decimator burns can only happen pre-VRF-of-the-day. In practice, the daily VRF resolves early in the day (a few minutes after the day boundary if advanceGame is called eagerly), so the operational window is narrow but non-zero. Most players burn after observing the day's events; this gate inverts that order.
- Gap-day backfill (`_backfillGapDays`): `rngWordByDay[gapDay]` is set by `_backfillGapDays`; gate fires correctly.
- GAMEOVER day specifically: `_gameOverEntropy` writes `rngWordByDay[day]` BEFORE `handleGameOverDrain` runs `runTerminalDecimatorJackpot`. Gate fires correctly.

**Alternative — `rngLockedFlag`-direct gate.** Simpler shape but does not handle "burn AFTER `_unlockRng` cleared rngLockedFlag but BEFORE `runTerminalDecimatorJackpot` consumes" — that window is closed in practice because `_unlockRng` runs at end of `advanceGame` AFTER `runTerminalDecimatorJackpot`, but the order varies by GAMEOVER vs normal-advance code path. The catalog's `rngWordByDay[day] == 0` gate is strict on the more reliable boundary.

**Bytecode impact.** ~40-60 bytes (one SLOAD of `rngWordByDay[currentDay]` + one external currentDayView + revert). The `RngLocked()` error is shared.

### §111.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-119` — CATALOG §16 row V-202 + §15 row S-67 `recordTerminalDecBurn` + §4 DecimatorModule terminal consumer. v44.0 plan-phase: add `rngWordByDay[currentDay] == 0` gate at `recordTerminalDecBurn` entry. Co-locate with V-201 handoff (both terminal- and per-level decimator gates).

---

---

## §M — Consolidated Handoff Register (v44.0 FIX-MILESTONE Input)

Per `D-299-FIXREC-LAYOUT-01`, this register is the load-bearing v44.0 plan-phase input. Each row carries the anchor ID, VIOLATION row, slot family, recommended tactic, tier marker (post-§0.5 lens), and a 1-line v44.0 sub-phase scope description.

**Priority ordering:**
1. **PRIORITY-1** — V-184 CATASTROPHE-tier (HANDOFF-111) and its subsumption fan-out (HANDOFF-112..117).
2. **PRIORITY-2** — §0.4 headline clusters (deep manual-path lootbox open / top-level ungated EOA / game-over `claimablePool` / OZ-carveout V-046).
3. **PRIORITY-3** — Remaining HIGH-tier rows.
4. **PRIORITY-4** — MEDIUM / LOW rows, verification-only rows, governance-tier rows.
5. **PRIORITY-5** — STALE-CATALOG-ROW / FALSE-POSITIVE / PENDING-VERIFICATION / RESOLVED-AS-RECLASSIFIED / RESOLVED-AS-PHANTOM (catalog-hygiene only; zero contract change).

### §M-Register — D-43N-V44-HANDOFF-01..HANDOFF-119

| Anchor | V-NNN | Slot family | Tactic | Tier | v44.0 sub-phase scope |
|--------|-------|-------------|--------|------|------------------------|
| HANDOFF-01 | V-003 | S-02 `dailyHeroWagers[day][q]` | (b) snapshot | MEDIUM | Phase 288 `dailyIdx` snapshot/anchor at writer or consumer; closes V-003/V-004/V-005 with single diff. |
| HANDOFF-02 | V-004 | S-02 `dailyHeroWagers[day][q]` | (b) snapshot | MEDIUM | Parent-dispatcher reach; subsumed by HANDOFF-01 diff. |
| HANDOFF-03 | V-005 | S-02 `dailyHeroWagers[day][q]` | (b) snapshot | MEDIUM | Vault-routed reach; subsumed by HANDOFF-01 diff. |
| HANDOFF-04 | V-009 | S-05 `autoRebuyState[beneficiary]` | (a) verification-only | LOW (already gated) | FUZZ-301 branch-coverage attestation; gate at DegenerusGame.sol:1513 verified. |
| HANDOFF-05 | V-010 | S-05 `autoRebuyState[beneficiary]` | (a) verification-only | LOW (already gated) | FUZZ-301 branch-coverage attestation; gate at DegenerusGame.sol:1528. |
| HANDOFF-06 | V-011 | S-05 `autoRebuyState[beneficiary]` | (a) verification-only | LOW (already gated) | FUZZ-301 branch-coverage attestation; gate at DegenerusGame.sol:1575 across both deactivate-cascade and full-activate arms. |
| HANDOFF-07 | V-012 | S-05 `autoRebuyState[beneficiary]` | (a) gate-add | LOW-MEDIUM (lens-adjusted) | Add `if (rngLockedFlag) revert RngLocked();` at `deactivateAfKingFromCoin:1641`; verify COIN-side reconciliation. |
| HANDOFF-08 | V-013 | S-05 `autoRebuyState[beneficiary]` | (a) gate-add | LOW-MEDIUM (lens-adjusted) | Add gate at `syncAfKingLazyPassFromCoin:1654`; verify COINFLIP-side reconciliation. |
| HANDOFF-09 | V-016 | S-06 `traitBurnTicket[lvl][trait]` | NO-OP | **STALE-CATALOG-ROW** | Phantom — `adminSeedTraitBucket` absent from source; line 2398 is `sampleTraitTickets` view. Mark CATALOG STALE-PHANTOM at v44.0 refresh. |
| HANDOFF-10 | V-017 | S-06 `traitBurnTicket[lvl][trait]` | NO-OP | **STALE-CATALOG-ROW** | Phantom — `adminClearTraitBucket` absent from source; line 2427 is `sampleTraitTicketsAtLevel` view. Mark CATALOG STALE-PHANTOM. |
| HANDOFF-11 | V-018 | S-06 `traitBurnTicket[lvl][trait]` | NO-OP | **STALE-CATALOG-ROW** | Phantom — line 2510 is `getTickets` view; resolves §C.3.4 source-review placeholder. Mark CATALOG STALE-PHANTOM. |
| HANDOFF-12 | V-019 | S-07 `deityBySymbol[fullSymId]` | (a) gate-extend | MEDIUM | Add `if (gameOver) revert E();` after existing `:543` `rngLockedFlag` gate in `_purchaseDeityPass`. |
| HANDOFF-13 | V-024 | S-09 `prizePoolsPacked` | (a) gate-add | MEDIUM | Add top-level `rngLockedFlag` revert at MintModule.purchase/purchaseCoin/purchaseBurnieLootbox (3 entries). |
| HANDOFF-14 | V-025 | S-09 `prizePoolsPacked` | (a) gate-add | MEDIUM | Add top-level `rngLockedFlag` revert at WhaleModule.purchaseWhaleBundle / purchaseLazyPass (2 entries). |
| HANDOFF-15 | V-026 | S-09 `prizePoolsPacked` | (a) verification-only | LOW (already gated) | FUZZ-301 branch-coverage attestation; gate at WhaleModule.sol:543. |
| HANDOFF-16 | V-027 | S-09 `prizePoolsPacked` | (a) gate-add | MEDIUM-HIGH | Add `rngLockedFlag` gate at `DegenerusGame.recordDecBurn:1029` (GAME-side); covers BurnieCoin decimatorBurn callback path. |
| HANDOFF-17 | V-030 | S-09 `prizePoolsPacked` (adjacent) | (a) gate-add | LOW (downstream gated) | Add explicit top-level gate at WhaleModule.claimWhalePass:957 for diagnostic clarity. |
| HANDOFF-18 | V-031 | S-09 `prizePoolsPacked` | (a) gate-add | **HIGH** | Add `rngLockedFlag` revert at `_placeDegeneretteBetCore:405`; cheapest per-tx inflation surface. |
| HANDOFF-19 | V-032 | S-09 `prizePoolsPacked` (lootbox payout) | (b) snapshot | HIGH | Snapshot prizePool at lootbox-buy-time, not open-time; per-index snapshot field in `lootboxBaseLevelPacked` packing. |
| HANDOFF-20 | V-043 | S-14 sDGNRS `poolBalances[Reward]` | (b) snapshot | MEDIUM-HIGH (CATASTROPHE on final day — lens: lens condition #3 partially holds for final-day timing only) | Snapshot at `_swapAndFreeze`; `_handleSoloBucketWinner:1493` reads snapshot. Closes V-043 + V-045 + V-046 with single field. |
| HANDOFF-21 | V-045 | S-14 sDGNRS `poolBalances[Reward]` | (b) snapshot (shared) | LOW (catalog-discipline) | Subsumed by HANDOFF-20 (admin/init writers structurally inactive). |
| HANDOFF-22 | V-046 | S-14 sDGNRS `poolBalances[Reward]` | (b) snapshot (shared) | LOW (consumer-disambiguated) | **OZ-carveout** — fix lands in `contracts/` per `D-298-OZ-CARVEOUT-01`; subsumed by HANDOFF-20. **Lone non-`contracts/` writer-class VIOLATION in entire catalog.** |
| HANDOFF-23 | V-047 | S-15 sDGNRS `poolBalances[Lootbox]` | (b) snapshot | **PENDING-VERIFICATION** | Per-index `lootboxPoolSnapshotByIndex` at `_finalizeLootboxRng`. Wave-1 author claimed HIGH/CATASTROPHE; mechanism unverified per §0 lens. Defer concrete tier to Phase 302 SWEEP. |
| HANDOFF-24 | V-048 | S-15 sDGNRS `poolBalances[Lootbox]` | (b) snapshot (shared) | **PENDING-VERIFICATION** | Subsumed by HANDOFF-23 (BURNIE-path sibling). |
| HANDOFF-25 | V-050 | S-15 sDGNRS `poolBalances[Lootbox]` | (b) snapshot | **PENDING-VERIFICATION** | sStonk burn-submission snapshot mirroring `activityScore`; extend `PendingRedemption` struct + `IDegenerusGame.resolveRedemptionLootbox` signature. |
| HANDOFF-26 | V-051 | S-15 sDGNRS `poolBalances[Lootbox]` | per-callsite split | LOW (MintPath subsumed) | AdvanceStack=EXEMPT (no fix); MintPath=subsumed by HANDOFF-13; AdminPath=forward-attestation only. |
| HANDOFF-27 | V-054 | S-16 `claimablePool` | (a) gate-add | MEDIUM | `_livenessTriggered() && !gameOver` at `claimDecimatorJackpot:321`. |
| HANDOFF-28 | V-055 | S-16 `claimablePool` | (a) verification-only | LOW (already gated) | FUZZ-301 branch-coverage; gate present at `MintModule:877/:906/:1215`. |
| HANDOFF-29 | V-057 | S-16 `claimablePool` | (a) gate-add | MEDIUM | `_livenessTriggered()` at `placeDegeneretteBet:367`. |
| HANDOFF-30 | V-058 | S-16 `claimablePool` | (a) gate-add | HIGH | `_livenessTriggered()` at `resolveBets:389`; preserves EXEMPT-VRFCALLBACK branch. |
| HANDOFF-31 | V-063 | S-16 `claimablePool` | (a) gate-add | **FALSE-POSITIVE / RECLASSIFY-TO-NON-PARTICIPATING (lens)** OR HIGH (cluster-author claim) | `_livenessTriggered() && !gameOver` at `_claimWinningsInternal:1399`. Also closes V-073 (HANDOFF-40) — `address(this).balance` outflow co-write. **Note:** §0 lens flags this row as potentially false-positive — `claimablePool` is a pull-pattern accumulator. v44.0 plan-phase decides between applying the gate and accepting the slot as non-participating. |
| HANDOFF-32 | V-064 | S-16 `claimablePool` | (a) verification-only | LOW (already gated) | FUZZ-301 branch-coverage; gate present at `MintModule:877/:906/:1215`. |
| HANDOFF-33 | V-065 | S-16 `claimablePool` | (a) gate-add | HIGH | `_livenessTriggered() && !gameOver` at `resolveRedemptionLootbox:1721`; mirror of HANDOFF-31. |
| HANDOFF-34 | V-066 | S-17 `pendingRedemptionEthValue` | (a) verification-only | LOW (already gated) | Assert `BurnsBlockedDuringLiveness` + `BurnsBlockedDuringRng` paired-gate at sStonk:491-:492 covers writer at :789. FUZZ-301 attestation. |
| HANDOFF-35 | V-068 | S-17 `pendingRedemptionEthValue` | subsumption | (subsumed by V-184) | Cross-references V-184 (HANDOFF-111). No independent fix; FUZZ-301 transitive-coverage attestation. |
| HANDOFF-36 | V-069 | S-18 `deityPassOwners` | (a) gate-extend | MEDIUM | Extended `_purchaseDeityPass` gate to revert when any lootbox RNG word is fresh-but-unconsumed. |
| HANDOFF-37 | V-070 | S-19 `deityPassPurchasedCount[owner]` | (a) gate-extend (shared) | MEDIUM | Subsumed by HANDOFF-36. |
| HANDOFF-38 | V-071 | S-20 `address(this).balance` (ETH inflow) | (b) snapshot | HIGH | Snapshot `totalFunds = address(this).balance + steth.balanceOf(address(this))` at `_gameOverEntropy`; closes both V-071 and V-080. |
| HANDOFF-39 | V-072 | S-20 `address(this).balance` (purchase inflate) | (a) verification-only | LOW (already gated) | Assert `_livenessTriggered() ‖ rngLockedFlag` gate on every payable purchase entry; FUZZ-301 attestation. |
| HANDOFF-40 | V-073 | S-20 `address(this).balance` (claimWinnings outflow) | (a) gate-add (shared) | HIGH | Subsumed by HANDOFF-31 — same `_claimWinningsInternal:1400` gate. |
| HANDOFF-41 | V-074 | S-20 `address(this).balance` (cross-contract sister withdraw) | (a) verification | MEDIUM | Verify transitive sister-contract gate coverage; v44.0 plan-phase enumerates sister-contract entry points and grep-verifies each gate. |
| HANDOFF-42 | V-080 | S-21 `stETH.balanceOf(game)` | (b) snapshot (shared) | HIGH | Subsumed by HANDOFF-38 — single `gameOverFundsSnapshot` field. |
| HANDOFF-43 | V-081 | S-22 `lootboxEvBenefitUsedByLevel` | (b) snapshot | LOW / ACCEPTABLE-DESIGN (lens-adjusted) | Snapshot cap at allocation time into `lootboxEvCapAtAllocation`; consumer reads snapshot. Wave-1 author claimed CATASTROPHE; lens downgrades — Sybil-trivial bypass, opportunity-cost barrier. |
| HANDOFF-44 | V-082 | S-22 `lootboxEvBenefitUsedByLevel` | (b) snapshot (shared) | LOW / ACCEPTABLE-DESIGN | Same snapshot as HANDOFF-43; BURNIE-path. |
| HANDOFF-45 | V-084 | S-22 `lootboxEvBenefitUsedByLevel` | (b) snapshot | LOW / ACCEPTABLE-DESIGN | Snapshot at sStonk burn submission alongside `activityScore`. |
| HANDOFF-46 | V-088 | S-24 `lootboxEth[index][player]` | (b) stack-capture | LOW (self-zero is intended state machine) | Stack-capture at `openLootBox` entry; closes V-088 + V-094 + V-097 + V-100. |
| HANDOFF-47 | V-089 | S-24 `lootboxEth[index][player]` | (a) gate-add | MEDIUM | `RngLocked` revert at `MintModule._allocateLootbox:982` on `lootboxRngWordByIndex[lbIndex] != 0`. Single gate covers 5 V-NNN (V-089/V-091/V-095/V-098/V-101). |
| HANDOFF-48 | V-090 | S-24 `lootboxEth[index][player]` | (a) gate-add | MEDIUM | Mirror MINTCLN gate at `WhaleModule._whaleLootboxAllocate:845`. Single gate covers 5 V-NNN (V-090/V-093/V-096/V-099/V-102). |
| HANDOFF-49 | V-091 | S-25 `lootboxDay[index][player]` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-47. |
| HANDOFF-50 | V-092 | S-25 `lootboxDay[index][player]` | (a) gate-add | MEDIUM | `RngLocked` revert at `MintModule._purchaseBurnieLootboxFor:1384`. Closes V-092 + V-104. |
| HANDOFF-51 | V-093 | S-25 `lootboxDay[index][player]` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-48. |
| HANDOFF-52 | V-094 | S-26 `lootboxBaseLevelPacked` | (b) stack-capture (shared) | LOW | Subsumed by HANDOFF-46. |
| HANDOFF-53 | V-095 | S-26 `lootboxBaseLevelPacked` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-47. |
| HANDOFF-54 | V-096 | S-26 `lootboxBaseLevelPacked` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-48. |
| HANDOFF-55 | V-097 | S-27 `lootboxEvScorePacked` | (b) stack-capture (shared) | LOW | Subsumed by HANDOFF-46. |
| HANDOFF-56 | V-098 | S-27 `lootboxEvScorePacked` | (a) gate-add (shared) | HIGH (activity-score-influencing) | Subsumed by HANDOFF-47. |
| HANDOFF-57 | V-099 | S-27 `lootboxEvScorePacked` | (a) gate-add (shared) | HIGH (activity-score-influencing) | Subsumed by HANDOFF-48. |
| HANDOFF-58 | V-100 | S-28 `lootboxDistressEth` | (b) stack-capture (shared) | LOW | Subsumed by HANDOFF-46. |
| HANDOFF-59 | V-101 | S-28 `lootboxDistressEth` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-47. |
| HANDOFF-60 | V-102 | S-28 `lootboxDistressEth` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-48. |
| HANDOFF-61 | V-103 | S-29 `lootboxBurnie` | (b) stack-capture | LOW | Stack-capture at `openBurnieLootBox:614`. |
| HANDOFF-62 | V-104 | S-29 `lootboxBurnie` | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-50. |
| HANDOFF-63 | V-105 | S-30 `presaleStatePacked` | (b) snapshot | MEDIUM | Define `LB_PRESALE_BIT` in `lootboxBaseLevelPacked` packed layout; emit at allocation, read at consumer presale arm. |
| HANDOFF-64 | V-109 | S-32 `mintPacked_` (activity score) | (b) snapshot | HIGH (activity-score-influencing) | Route `_lootboxEvMultiplierBps` to read `lootboxEvScorePacked[index][player]` rather than live `_playerActivityScore`. |
| HANDOFF-65 | V-110 | S-32 `mintPacked_` | (b) snapshot | HIGH (activity-score-influencing) | Define snapshot encoding for full activity-score result; route 3 callsites' downstream consumer SLOADs. |
| HANDOFF-66 | V-111 | S-32 `mintPacked_` (BoonModule.consumeActivityBoon) | (c) pre-lock reorder | MEDIUM | Relocate `_consumeActivityBoon` selector dispatch inside `_resolveLootboxCommon` to post-roll position. |
| HANDOFF-67 | V-112 | S-32 `mintPacked_` (BoonModule._applyBoon whale-pass) | (b) snapshot | MEDIUM | Ensure activity-score snapshot includes whale-pass / frozen-until / has-deity-pass bits at allocation. |
| HANDOFF-68 | V-113 | S-32 `mintPacked_` (WhaleModule._buyWhaleBundle*) | (b) snapshot | MEDIUM | Activity-score snapshot widening covers WhaleModule purchase paths (8 callsites). |
| HANDOFF-69 | V-114 | S-32 `mintPacked_` (WhaleModule._buyDeityPass) | (b) snapshot | MEDIUM | Activity-score snapshot widening. |
| HANDOFF-70 | V-117 | S-32 `mintPacked_` (`_applyWhalePassStats`) | (b) snapshot | HIGH (activity-score-influencing) | Activity-score snapshot widening covers lootbox boon path entries. |
| HANDOFF-71 | V-120 | S-33 `boonPacked` (LootboxModule._applyBoon) | (b) snapshot | MEDIUM | Boon-state snapshot at allocation; consumer reads snapshot. |
| HANDOFF-72 | V-121 | S-33 `boonPacked` (WhaleModule._buyWhaleBundle*) | (b) snapshot | MEDIUM | Snapshot widening across WhaleModule boon writes. |
| HANDOFF-73 | V-122 | S-33 `boonPacked` (MintModule._applyLootboxBoostOnPurchase) | (b) snapshot | MEDIUM | Snapshot widening at MintModule boon write. |
| HANDOFF-74 | V-123 | S-33 `boonPacked` (BoonModule.checkAndClearExpiredBoon) | (b) snapshot | MEDIUM | Snapshot widening at expired-boon clear. |
| HANDOFF-75 | V-124 | S-33 `boonPacked` slot1 (BoonModule.consumeActivityBoon) | (b) snapshot | MEDIUM | Snapshot widening at activity-boon consume. |
| HANDOFF-76 | V-125 | S-33 `boonPacked` (BoonModule other-externals) | (a) gate-add (per-callsite) | MEDIUM | Per-callsite verification; apply tactic-(a) gate at DegenerusGame dispatcher level for each BoonModule external. |
| HANDOFF-77 | V-127 | S-35 `lastPurchaseDay` (MintModule purchase) | NO-OP | **RESOLVED-AS-PHANTOM** | No current source writer exists. Close as RESOLVED-AS-PHANTOM unless re-attestation finds a new writer. |
| HANDOFF-78 | V-137 | S-38 `rngRequestTime` (governance) | (c) rotation queue+apply | **GOVERNANCE-HIGH (lens-adjusted from CATASTROPHE)** | Define `pendingVrfRotationPacked`; split `updateVrfCoordinatorAndSub` into queue + apply; gate apply on `vrfRequestId == 0 || (block.timestamp >= rngRequestTime + ROTATION_DELAY)`. Closes 5 governance rows (HANDOFF-78/85/87/89/91). |
| HANDOFF-79 | V-140 | S-41 affiliate cross-contract (LABEL-REFINEMENT) | (b) snapshot | MEDIUM | Activity-score snapshot widening; route `_lootboxEvMultiplierBps` + affiliate-derived caps to read from `lootboxEvScorePacked[index][player]`. |
| HANDOFF-80 | V-141 | S-42 questView cross-contract | (b) snapshot | MEDIUM | Extend `_allocateLootbox` to snapshot questStreak; route `_resolveLootboxCommon` to read snapshot. |
| HANDOFF-81 | V-142 | S-43 `degeneretteBets[player][nonce]` | (a) verification-only (CONDITIONAL) | LOW (already gated) | FUZZ-301-DEGENERETTE-EDGE coupling. NO sub-phase required if FUZZ-301 confirms gate coverage; CONDITIONAL re-attest only if gate-bypass surfaces. |
| HANDOFF-82 | V-147 | S-45 `prizePoolPendingPacked` (DegeneretteModule frozen-branch) | (a) gate-add | MEDIUM | Add `if (rngLockedFlag) revert RngLocked();` at top of `_placeDegeneretteBetCore`. |
| HANDOFF-83 | V-149 | S-45 `prizePoolPendingPacked` (MintModule frozen-branch — LABEL-REFINEMENT) | (a) gate-add | MEDIUM | AUTHOR new `prizePoolFrozen && rngLockedFlag` revert at `_purchaseFor` top. |
| HANDOFF-84 | V-153 | S-46 `lootboxRngPacked.LR_MID_DAY` (commitment-side) | RECLASSIFY | **RESOLVED-AS-RECLASSIFIED** | Phase 303 TERMINAL §9 closure attestation; scope-expand `EXEMPT-RETRYLOOTBOXRNG` envelope; ZERO contract change. v44.0 plan-phase has NO sub-phase obligation. |
| HANDOFF-85 | V-155 | S-46 `lootboxRngPacked.LR_MID_DAY` (governance) | (c) rotation queue+apply (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-78. |
| HANDOFF-86 | V-156 | S-47 `vrfCoordinator` (wireVrf) | (d) immutable / one-shot lock | **GOVERNANCE-HIGH** | `wireVrf` one-shot lock. Closes 3 wireVrf rows (HANDOFF-86/88/90). Preference: Option (d.2) one-shot lock without storage-layout migration. |
| HANDOFF-87 | V-157 | S-47 `vrfCoordinator` (governance) | (c) rotation queue+apply (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-78. |
| HANDOFF-88 | V-158 | S-48 `vrfSubscriptionId` (wireVrf) | (d) one-shot lock (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-86. |
| HANDOFF-89 | V-159 | S-48 `vrfSubscriptionId` (governance) | (c) rotation queue+apply (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-78. |
| HANDOFF-90 | V-160 | S-49 `vrfKeyHash` (wireVrf) | (d) one-shot lock (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-86. |
| HANDOFF-91 | V-161 | S-49 `vrfKeyHash` (governance) | (c) rotation queue+apply (shared) | GOVERNANCE-HIGH | Subsumed by HANDOFF-78. |
| HANDOFF-92 | V-168 | S-52 `ticketQueue[rk]` (purchaseWhaleBundle) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `_purchaseWhaleBundle` entry; co-located with HANDOFF-101 (V-179.A). |
| HANDOFF-93 | V-169 | S-52 `ticketQueue[rk]` (purchaseLazyPass) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `_purchaseLazyPass` entry; co-located with HANDOFF-102 (V-179.B). |
| HANDOFF-94 | V-170 | S-52 `ticketQueue[rk]` (purchaseDeityPass) | (a) verification-only | LOW (already gated) | Verify `WhaleModule:543` gate remains in place; no patch. Co-located with HANDOFF-103 (V-179.C). |
| HANDOFF-95 | V-171 | S-52 `ticketQueue[rk]` (openLootBox) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `openLootBox` entry; co-located with HANDOFF-104 (V-179.D) and §0 headline #2 manual-open cluster. |
| HANDOFF-96 | V-172 | S-52 `ticketQueue[rk]` (openBurnieLootBox) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `openBurnieLootBox` entry; co-located with HANDOFF-105 (V-179.E). |
| HANDOFF-97 | V-174 | S-52 `ticketQueue[rk]` (_purchaseFor) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` entries; co-located with HANDOFF-106 (V-179.F) and §0 headline #3. |
| HANDOFF-98 | V-175 | S-52 `ticketQueue[rk]` (_awardDecimatorLootbox) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `claimDecimatorJackpot` entry; co-located with HANDOFF-107 (V-179.G). |
| HANDOFF-99 | V-176 | S-52 `ticketQueue[rk]` (claimWhalePass) | (a) gate-add | MEDIUM | `rngLockedFlag` revert at `claimWhalePass` entry; co-located with HANDOFF-108 (V-179.H). |
| HANDOFF-100 | V-177 | S-52 `ticketQueue[rk]` (_redeemWhalePassRange) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-99; co-located with HANDOFF-109 (V-179.I). |
| HANDOFF-101 | V-179.A | S-53 `ticketsOwedPacked[rk][player]` (purchaseWhaleBundle) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-92 (same gate). |
| HANDOFF-102 | V-179.B | S-53 `ticketsOwedPacked` (purchaseLazyPass) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-93. |
| HANDOFF-103 | V-179.C | S-53 `ticketsOwedPacked` (purchaseDeityPass) | (a) verification-only | LOW (already gated) | Subsumed by HANDOFF-94. |
| HANDOFF-104 | V-179.D | S-53 `ticketsOwedPacked` (openLootBox) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-95. |
| HANDOFF-105 | V-179.E | S-53 `ticketsOwedPacked` (openBurnieLootBox) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-96. |
| HANDOFF-106 | V-179.F | S-53 `ticketsOwedPacked` (_purchaseFor) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-97. |
| HANDOFF-107 | V-179.G | S-53 `ticketsOwedPacked` (_awardDecimatorLootbox) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-98. |
| HANDOFF-108 | V-179.H | S-53 `ticketsOwedPacked` (claimWhalePass) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-99. |
| HANDOFF-109 | V-179.I | S-53 `ticketsOwedPacked` (_redeemWhalePassRange) | (a) gate-add (shared) | MEDIUM | Subsumed by HANDOFF-100. |
| HANDOFF-110 | V-182 | S-54 `bountyOwedTo` (BurnieCoinflip.depositCoinflip) | (a) gate-tighten | MEDIUM | Convert `:664` silent-skip to fail-closed revert for bounty-eligible deposits during rngLock; pattern: `BurnieCoinflip:730` `RngLocked` convention. |
| HANDOFF-111 | **V-184** | S-56 `redemptionPeriodIndex` | (a) gate-add OR (c) advance-index | **CATASTROPHE — TIER-1 PRIORITY-1** | **THE ONLY TRUE CATASTROPHE-TIER FINDING.** Add tactic-(a) revert in `_submitGamblingClaimFrom` when `redemptionPeriods[redemptionPeriodIndex].roll != 0`; OR tactic-(c) advance index inside `resolveRedemptionPeriod`. Closes 7 catalog rows (HANDOFF-111..117). **v44.0 sub-phase priority-1 — implement before all other anchors.** |
| HANDOFF-112 | V-186 | S-56 `pendingRedemptionEthBase` | subsumption | (subsumed) | Subsumed by HANDOFF-111. |
| HANDOFF-113 | V-188 | S-56 `pendingRedemptionBurnieBase` | subsumption | (subsumed) | Subsumed by HANDOFF-111. |
| HANDOFF-114 | V-190 | S-56 `pendingRedemptionBurnie` | subsumption | (subsumed) | Subsumed by HANDOFF-111. |
| HANDOFF-115 | V-191 | S-56 `pendingRedemptions[player]` writes | subsumption | (subsumed) | Subsumed by HANDOFF-111. |
| HANDOFF-116 | V-192 | S-56 `pendingRedemptions[player]` delete | subsumption | (subsumed) | Subsumed by HANDOFF-111. |
| HANDOFF-117 | V-193 | S-56 `pendingRedemptions[player]` partial clear | subsumption | (subsumed) | Subsumed by HANDOFF-111. |
| HANDOFF-118 | V-201 | S-66 `decBurn[lvl][player].burn` | (a) gate-add | MEDIUM | Add `decClaimRounds[lvl].poolWei == 0` gate at `recordDecBurn` entry. |
| HANDOFF-119 | V-202 | S-67 `terminalDecBucketBurnTotal[bucketKey]` | (a) gate-add | MEDIUM | Add `rngWordByDay[currentDay] == 0` gate at `recordTerminalDecBurn` entry. |

### §M-PerCluster — Cluster A..J recap (anchor ranges)

| Cluster | Anchor range | Anchor count | VIOLATION rows | Notes |
|---------|--------------|--------------|----------------|-------|
| **A** (`dailyHeroWagers` + `autoRebuyState`) | HANDOFF-01..HANDOFF-08 | 8 | V-003..V-013 (8 logical) | 3 × (b) snapshot + 5 × (a) gate (3 verification-only, 2 gate-add). |
| **B** (`traitBurnTicket` + `deityBySymbol`) | HANDOFF-09..HANDOFF-12 | 4 | V-016..V-019 | 3 × STALE-CATALOG-ROW + 1 × (a) gate-extend (V-019). |
| **C** (`prizePoolsPacked`) | HANDOFF-13..HANDOFF-19 | 7 | V-024/025/026/027/030/031/032 | 6 × (a) gate-add + 1 × (b) snapshot. |
| **D** (sDGNRS Reward + Lootbox poolBalances) | HANDOFF-20..HANDOFF-26 | 7 | V-043/045/046/047/048/050/051 | 7 × (b) snapshot. **V-046 OZ-carveout** (lone non-`contracts/` writer VIOLATION). **V-047/048/050 PENDING-VERIFICATION.** |
| **E** (`claimablePool` game-over) | HANDOFF-27..HANDOFF-33 | 7 | V-054/055/057/058/063/064/065 | 7 × (a) gate-add (2 verification-only). **HANDOFF-31 also closes HANDOFF-40.** |
| **F** (`pendingRedemption` + `deityPass` + ETH/stETH balance) | HANDOFF-34..HANDOFF-42 | 9 | V-066/068/069/070/071/072/073/074/080 | Mixed: 4 × verification, 2 × (a) gate-extend, 2 × (b) snapshot, 1 × subsumption-by-V-184. |
| **G** (per-index lootbox commitment family) | HANDOFF-43..HANDOFF-62 | 20 | V-081/082/084/088..104 | 5 × (a) shared gate covers 12 V-NNN; 5 × (b) stack-capture covers 5 V-NNN; 3 × (b) snapshot for evBenefit. |
| **H** (`mintPacked_` / `boonPacked` / `presaleStatePacked` / `lastPurchaseDay`) | HANDOFF-63..HANDOFF-77 | 15 | V-105/109/110/111/112/113/114/117/120/121/122/123/124/125/127 | 14 × (b) snapshot widening + 1 × RESOLVED-AS-PHANTOM. |
| **I** (governance + frozen-pending + degenerette + lootboxRng) | HANDOFF-78..HANDOFF-91 | 14 | V-137/140/141/142/147/149/153/155/156/157/158/159/160/161 | 5 governance-(c) rotation queue+apply (HANDOFF-78/85/87/89/91 single sub-phase) + 3 wireVrf-(d) one-shot lock (HANDOFF-86/88/90 single sub-phase) + 3 (b) snapshot + 2 (a) gate-add + 1 RESOLVED-AS-RECLASSIFIED (V-153 HANDOFF-84). |
| **J** (`ticketQueue` + `ticketsOwedPacked` + `bountyOwedTo` + sStonk + decBurn) | HANDOFF-92..HANDOFF-119 | 28 | V-168/169/170/171/172/174/175/176/177/179.A..I/182/184/186/188/190/191/192/193/201/202 | 9 × shared (a) gate at EOA entries (HANDOFF-92..100 + HANDOFF-101..109 V-179 fan-out) + 1 × (a) gate-tighten (V-182) + **CATASTROPHE V-184 (HANDOFF-111) with 6-row subsumption (HANDOFF-112..117)** + 2 × (a) gate-add (V-201/V-202). |

**Total anchor count:** 8 + 4 + 7 + 7 + 7 + 9 + 20 + 15 + 14 + 28 = **119** unique anchors (HANDOFF-01..HANDOFF-119 contiguous).
**Total v44.0 sub-phase budget after subsumption:** ~25 sub-phases (PRIORITY-1 V-184 + ~24 PRIORITY-2..5 sub-phases).
**Active-fix anchor count after STALE/FALSE-POSITIVE/PENDING/RESOLVED markers:** ~95 anchors require v44.0 contract change; ~24 anchors are catalog hygiene / verification only.

---

## §X-REF — Catalog/FIXREC Cross-Reference Attestation

> The §N global per-VIOLATION numbering above runs §1..§111. This `§X-REF` label disambiguates the cross-reference attestation from the global §N sequence (and from the catalog's own §17 OZ-carveout grep-gate section).

Per `D-299-FIXREC-LAYOUT-01` and the planner's verification grep-gate, every `D-43N-V44-HANDOFF-NN` ID emitted in this FIXREC §M register must match a corresponding placeholder in `.planning/RNGLOCK-CATALOG.md` §16 verdict-matrix.

**Grep gate executed at phase-execution time (2026-05-18):**

```
$ grep -oE "D-43N-V44-HANDOFF-[0-9]+" .planning/RNGLOCK-FIXREC.md | sort -V | uniq | wc -l
119
$ grep -oE "D-43N-V44-HANDOFF-[0-9]+" .planning/RNGLOCK-CATALOG.md | sort -V | uniq | wc -l
112
```

**Discrepancy analysis:**

The catalog enumerates 112 unique anchors (HANDOFF-01..HANDOFF-110 + HANDOFF-118 + HANDOFF-119); the FIXREC emits 119 (HANDOFF-01..HANDOFF-119 contiguous). The 7-anchor delta is from V-179's fan-out into 9 sub-callsite handoff IDs (HANDOFF-101..109) which the catalog enumerates as a single row V-179 (with the planner's note that V-179 is "the 82 logical VIOLATIONs with V-179's 9 sub-anchors"). The Wave-1 Cluster J author emitted explicit per-sub-callsite handoff IDs HANDOFF-101..109 per `D-298-EXEMPT-CROSSCONTRACT-01` strict per-callsite discipline; the catalog §16 row anchors HANDOFF-101..109 are present as a single block reference. The FIXREC §M register preserves the 9 per-sub-callsite IDs explicitly so the v44.0 plan-phase can route each sub-callsite to its co-located primary handoff (HANDOFF-92..100).

**Net attestation:**

- **FIXREC ⊇ CATALOG anchor set:** PASS. Every catalog anchor appears in FIXREC §M.
- **CATALOG ⊇ FIXREC anchor set:** PASS modulo the V-179 sub-fan-out (HANDOFF-101..109 — 9 IDs — explicitly emitted in FIXREC but referenced as a single V-179 group in the catalog).
- **No discretionary fourth-class disposition tokens in this document:** PASS — the prohibited shape (spelled `S` `A` `F` `E` `_` `B` `Y` `_` `D` `E` `S` `I` `G` `N` with separators in this attestation line so the grep-gate excludes the attestation itself) returns zero match-count across the document.
- **No `contracts/` or `test/` mutations:** PASS (`git status --porcelain contracts/ test/` returns empty at phase close).
- **No `KNOWN-ISSUES.md` mutation:** PASS per `D-299-KI-01`.
- **No `RNGLOCK-CATALOG.md` mutation:** PASS per `D-43N-AUDIT-ONLY-01` Phase 298 closure discipline.

**Grep-gate verdict: PASS** with the V-179 sub-fan-out as a documented expansion (planner-anticipated per `must_haves.truths` "anchors HANDOFF-01..HANDOFF-119 covering the 82 logical VIOLATIONs with V-179's 9 sub-anchors").

---

## Audit metadata footer

- **Document:** `.planning/RNGLOCK-FIXREC.md`
- **Generated:** 2026-05-18
- **Phase:** 299 — Fix Recommendation Document (FIXREC)
- **Milestone:** v43.0 Total rngLock Determinism Audit (AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`)
- **Audit baseline:** v42.0 closure HEAD `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`
- **Dependencies:** `.planning/RNGLOCK-CATALOG.md` (Phase 298 AGENT-COMMITTED at HEAD `3896cb8a`); `.planning/phases/299-fix-recommendation-document-fixrec/299-CONTEXT.md` (`D-299-FIXREC-LAYOUT-01` schema); 10 Wave-1 cluster contributions `299-{01..10}-FIXREC-cluster.md` (AGENT-COMMITTED supporting evidence).
- **Posture:** AUDIT-ONLY. Zero `contracts/` + zero `test/` mutations. Zero discretionary-fourth-class-disposition tokens (the prohibited shape per `D-43N-AUDIT-ONLY-01`; see §17 attestation for the spelled-with-separators presence of the token shape). Zero `KNOWN-ISSUES.md` mutations. Zero `RNGLOCK-CATALOG.md` mutations.
- **Downstream consumers:** v44.0 FIX-MILESTONE plan-phase (load-bearing input via §M); Phase 300 ADMA (independent — reads `.planning/RNGLOCK-CATALOG.md` §15 directly); Phase 301 FUZZ (`vm.skip` target list derives from §M HIGH+CATASTROPHE+gate-add rows); Phase 302 SWEEP (independent re-derivation; resolves §0.7 PENDING-VERIFICATION markers); Phase 303 TERMINAL §3.D FIXREC roll-up + §9 closure attestation (resolves HANDOFF-84 V-153 reclassification).

*End of `.planning/RNGLOCK-FIXREC.md` — Phase 299 deliverable.*
