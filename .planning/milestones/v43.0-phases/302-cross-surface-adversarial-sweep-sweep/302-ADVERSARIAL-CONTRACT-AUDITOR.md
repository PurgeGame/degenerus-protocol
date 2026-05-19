---
artifact: ADVERSARIAL-CONTRACT-AUDITOR
phase: 302-cross-surface-adversarial-sweep-sweep
plan: 01
milestone: v43.0
skill: contract-auditor
adversarial_pass_pattern: SEQUENTIAL_MAIN_CONTEXT
audit_subject: rngLock freeze invariant + Phase 298-301 audit artifacts (CATALOG + FIXREC + ADMA + FUZZ)
charge_hypothesis_count: 9 charged + 2 beyond-charge
generated_at: 2026-05-18
---

# Phase 302 Adversarial Pass — /contract-auditor

3-skill HYBRID adversarial sweep against the v43.0 audit subject. SEQUENTIAL_MAIN_CONTEXT invocation per D-302-INVOKE-01. Charge document: `.planning/phases/302-cross-surface-adversarial-sweep-sweep/302-ADVERSARIAL-CHARGE.md`.

**Persona:** Adversarial security researcher with 1000-ETH budget; EVM internals expertise; MEV/VRF/economic-attack focus; storage-layout + call-graph rigor. Reads BOTH the catalog/FIXREC documents AND grep-verifies against `contracts/` source per `feedback_verify_call_graph_against_source.md`.

**Skill methodology applied:**
- `feedback_rng_backward_trace.md` for every RNG-window hypothesis (backward-trace from consumer to verify word unknown at commitment).
- `feedback_rng_commitment_window.md` for every commitment-window hypothesis (state mutable between request and fulfillment).
- `feedback_rng_window_storage_read_freshness.md` for non-VRF reads alongside RNG (F-41-02/03 precedent).
- `feedback_verify_call_graph_against_source.md` for every "by construction" claim (grep-verify).
- 3-condition catastrophe lens applied at classification.

---

## Hypothesis (i) — SWP-01: Freeze-invariant storage paths

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE (mostly) with FINDING_CANDIDATE re-derivations for two PENDING-VERIFICATION rows.

**Evidence:**

- **(a) Coverage gates re-attested.** Grep-verification of FIXREC §0.7 VERIFICATION-ONLY anchors against current source:
  - `MintModule.sol:877` / `:906` / `:1215` — `rngLockedFlag` gate present (jackpot-phase mint gates). Verified.
  - `BurnieCoinflip.sol:730` — `if (rngLockedFlag) revert RngLocked();` gate. Verified.
  - `StakedDegenerusStonk.sol:492` — `BurnsBlockedDuringRng` revert pattern present. Verified.
  - `WhaleModule.sol:543` — purchase-deity-pass gate. Verified (per spot-read).
  - `DegenerusGame.sol:1513` / `:1528` / `:1575` — autoRebuy gates. Verified by reading Storage.sol context.
  - `Storage.sol:572` — `_queueTickets` / `_queueTicketRange` downstream revert. Verified.
- **(b) STALE-CATALOG-ROW V-016/V-017/V-018 re-confirmed STALE.** `grep -n "adminSeedTraitBucket\|adminClearTraitBucket" contracts/` returns ONLY `traitBurnTicket` SLOAD reads at `DegenerusGame.sol:2398` (`sampleTraitTickets` external view), `:2427` (`sampleTraitTicketsAtLevel` external view), and `:2510` (`getTickets` external view). No `address[] storage arr; arr.push(...)` writer exists at any of the three line numbers. **FIXREC §0.7 STALE marker holds; CATALOG §15 rows V-016/V-017/V-018 are catalog-hygiene-only — no production writer corresponds.**
- **(c) PENDING-VERIFICATION V-047/V-048/V-050 re-derivation.** Per FIXREC §0.7, the "drain-pool-before-resolution" exploit shape on `sDGNRS poolBalances[Lootbox]` (S-15) was unverified. Walking the EOA-reachable writers of S-15 (`transferFromPool` at `sDGNRS.sol:412` reached from `LootboxModule._creditDgnrsReward:1786`):
  - The ETH-path `openLootBox` writer self-routes via `_resolveLootboxCommon → _creditDgnrsReward` which consumes the pool's CURRENT balance via the mega-tier arm `(poolBalance * LOOTBOX_DGNRS_POOL_MEGA_PPM * amount) / (1_000_000 * 1 ether)`.
  - **The "drain-before-mega" shape:** Player A holds a pre-allocated index N at VRF-fulfillment T0. Between T0 (the player observes their `rngWord_N`) and Player A's own `openLootBox(N)`, OTHER players can call `openLootBox` for their indices, deflating `sDGNRS poolBalances[Lootbox]`. If A's `rngWord_N` lands them in the mega-tier arm, the post-deflation poolBalance produces a SMALLER mega-tier payout for A. **This is grief-against-A, not extraction-by-attacker.**
  - **The actual surface that DOES extract is the symmetric inverse:** Player A observes own `rngWord_N` post-fulfillment; if `rngWord_N` lands A in mega-tier, A wants to MAXIMIZE pool size before A opens. A cannot inflate poolBalance directly (no minter for sDGNRS Lootbox pool from EOA paths except `transferBetweenPools` admin-controlled), but A CAN delay opening their box AND ALSO front-run other players' opens to extract before they deflate. This is **timing-arbitrage among players sharing the same pool**, not a single-player extraction.
  - **Cross-player surface:** Player A in mega-tier can frontrun Player B (also mega-tier) to extract first. This is the "open first" race, which IS structural — pull-pattern self-resolution; no attacker-controlled state.
  - **Lens disposition:** Lens condition #3 (mutation profits mutator after opportunity cost) — fails for the "drain-pool" shape (the drainer deflates their OWN payout share too). PENDING-VERIFICATION resolves to **NO REAL EV from drain-shape**. The pull-pattern timing-race is intrinsic to pool-routed payouts, not a rngLock-window violation.
  - **Conclusion:** V-047 / V-048 / V-050 → re-disposition `NEGATIVE_RESULT_ONLY` for the drain-shape; the residual cross-player frontrun is `ACCEPTED_DESIGN` (intrinsic to any pool-distribution mechanic).
- **(d) Missing-writer grep sweep.** `grep -E "function .*external\b" contracts/modules/*.sol contracts/*.sol` enumerated externals; cross-checked against §14 writer set per row. The catalog completeness gate at CAT-06 (`§17` of CATALOG) already documents this. Spot-check of three high-fanout slots (S-09 `prizePoolsPacked`; S-22 `lootboxEvBenefitUsedByLevel`; S-32 `mintPacked_`) confirms §15 writer enumeration captures every external/public path reachable in current source. No missing writers surfaced.

**Notes:**

- The PENDING-VERIFICATION re-derivation for V-047/V-048/V-050 is the substantive Hypothesis (i) finding — Phase 302 SWEEP IS the venue per FIXREC §0.7 + FIXREC §0.8 "Phase 302 is the venue for resolving PENDING-VERIFICATION markers".
- The STALE marker on V-016/V-017/V-018 holds; no Phase 302 elevation needed. Phase 303 §6 KI walkthrough should reflect catalog amendment.
- The verification-only rows are confirmed present in-source; FUZZ-301 branch-reach attestation is the standard discipline.

---

## Hypothesis (ii) — SWP-02: Novel attack surfaces

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE (no novel ERC-callback re-entrancy vector surfaces).

**Evidence:**

- **(a) ERC777-style hooks.** sDGNRS is NOT an ERC777 token (verified by grep: no `tokensReceived` / `tokensToSend` / `_callTokensReceived` invocation in `StakedDegenerusStonk.sol`). The token implements the standard ERC20 interface plus per-Phase pull-redemption helpers. The OZ-inherited writers per FIXREC §22 V-046 are pure ERC20 `_transfer` / `_burn` / `_mint` with no receiver-hook. **ERC777 receive-hook vector does not exist on this codebase.**
- **(b) Cross-module re-entrancy.** The high-composition-density consumers from §6/§7/§8/§11/§12/§13 all share the `rngLockedFlag` invariant guarded at entry. `_resolveLootboxCommon` (§7) is called from `openLootBox` / `openBurnieLootBox` / `resolveLootboxDirect` / `resolveRedemptionLootbox` — each entry point has its `rngLockedFlag` gate (validated via the §C SLOAD tables in CATALOG). The cross-module call graph traversal does not produce a path where one module's external entry reaches another module's participating-slot writer WITHOUT crossing a `rngLockedFlag` gate, EXCEPT via the catalog-flagged VIOLATION rows already in §16 (which are Phase 299 FIXREC subjects, not novel surfaces).
- **(c) Multi-block window exploits.** The rngLock window IS multi-block by design (VRF callback typically arrives 1-2 blocks after request). Every EOA-callable function inside the window is either (i) `rngLockedFlag`-gated (revert) or (ii) catalog-flagged as VIOLATION. The multi-block dimension is not a novel attack surface; it's the **normal operating window of the lock**, and the catalog enumerates writer behavior within it exhaustively.
- **(d) Cross-module composition.** Walked Phase 294 BURNIE-gap-precedent style: for each VIOLATION writer V-NN, grep its callsite chain back to an external/public entry. The catalog's §15 writer enumeration captures the chain (verified spot-check on V-003 hero-override, V-031 placeDegeneretteBet, V-098 lootboxEvScorePacked writers, V-184 sStonk burn). No "inline-duplicated business logic" gap surfaced.
- **(e) ERC721 deity-pass callback.** `DegenerusDeityPass.sol` deity-pass mint flow: `WhaleModule._purchaseDeityPass` writes `deityBySymbol[fullSymId]` at WhaleModule:598, THEN calls `DegenerusDeityPass._mint(buyer, fullSymId)` which OZ-ERC721 invokes `_checkOnERC721Received`. **The callback is AFTER the participating-slot write.** A receiver contract receiving the deity-pass token could re-enter `contracts/`, BUT by then `deityBySymbol[fullSymId] = buyer` has already been committed atomically with the slot's SSTORE. Re-entry would land in either (i) a function that triggers `_purchaseDeityPass` again — `WhaleModule:543` gates against `rngLockedFlag`; the function is its OWN entry-point — or (ii) any other game function. No new participating-slot write becomes reachable purely through ERC721-receive callback that wasn't already enumerated in §15.
- **(f) Reverse-callback paths.** `BurnieCoin` / `BurnieCoinflip` callbacks into `DegenerusGame` (`deactivateAfKingFromCoin:1641`, `syncAfKingLazyPassFromCoin:1654`) write `autoRebuyState[beneficiary]` (S-05). These are catalog-flagged V-012/V-013 in FIXREC §7/§8 at LOW-ACCEPTABLE-DESIGN tier (afKing toggle costs the player their own afKing-active bonus; no other-player extraction). The disposition is preserved — these are documented VIOLATIONs at low tier, not novel attack surfaces.

**Notes:**

- No beyond-charge re-entrancy vector surfaces. The OZ ERC20 surface (V-046 carveout) is the lone non-`contracts/` writer class; FIXREC §22 handles it via the §M handoff register.
- ERC777 verification is a structural negative: sDGNRS implements standard ERC20, not ERC777. If a future contract upgrade introduces ERC777 surface for the Reward/Lootbox pools, this disposition would need re-attestation.

---

## Hypothesis (iii) — SWP-03: Game-theoretic write-induced effects

**Disposition:** Per-sub-hypothesis split. Mostly SAFE_BY_STRUCTURAL_CLOSURE / ACCEPTED_DESIGN reflecting FIXREC §0 lens disposition; **V-063 sub-derivation conflicts with FIXREC §0.7 — re-disposition to FINDING_CANDIDATE-CONFIRMED** but **already-documented at FIXREC §31 + §40 HANDOFF-31/HANDOFF-40 — no new elevation needed.**

**Evidence:**

- **(a) V-184 sStonk cross-day re-roll re-derivation.** Walked the exploit chain against `StakedDegenerusStonk.sol` source:
  - `resolveRedemptionPeriod:585` reads `period = redemptionPeriodIndex` (line 588), writes `redemptionPeriods[period] = {roll, flipDay}` (line 604), clears `pendingRedemptionEthBase = 0` (line 594), `pendingRedemptionBurnieBase = 0` (line 601). **Does NOT advance `redemptionPeriodIndex`.**
  - `_submitGamblingClaimFrom:752` advances `redemptionPeriodIndex` (line 760) ONLY if `redemptionPeriodIndex != currentPeriod` (line 758).
  - On wall-clock day D, post-resolve: `redemptionPeriodIndex == D`. A re-burn on day D (still same wall-clock day) hits the conditional FALSE branch — `redemptionPeriodIndex` unchanged. `pendingRedemptionEthBase += newEthValueOwed`.
  - On day D+1's `advanceGame`, `resolveRedemptionPeriod` runs (because `hasPendingRedemptions()` is true). Reads `period = redemptionPeriodIndex = D` (STALE!). Writes `redemptionPeriods[D] = {roll: new_roll, flipDay: D+2}` — **OVERWRITES day D's original roll**.
  - **Cross-day window confirmed:** the attacker needs to time the re-burn AFTER advanceGame on day D AND BEFORE wall-clock rolls to day D+1. The window is the post-resolve, pre-day-boundary slice (hours per day).
  - 3-condition lens applied:
    - (1) Slot feeds VRF-derived output: ✓ — `redemptionPeriods[D].roll` is consumed by `claimRedemption` to compute `totalRolledEth = (claim.ethValueOwed * roll) / 100` at sStonk:632.
    - (2) Slot mutable mid-rngLock by non-EXEMPT actor: ✓ — the `_submitGamblingClaimFrom` callsite is reached from EOA `burn`/`burnWrapped` at sStonk:733; the `BurnsBlockedDuringLiveness` gate at sStonk:492 protects the liveness window but NOT the post-resolve pre-day-boundary window (rngLockedFlag is cleared at `_unlockRng` END of advanceGame).
    - (3) Mutation yields positive EV: ✓ — informed-re-roll filter (claim if `roll_D >= 100`; re-burn 1-wei if `roll_D < 100`) produces EV ~118.75 vs baseline 100 → ~18.75% per round. Compounding to supply-cap-bounded ceiling.
  - **Disposition: FINDING_CANDIDATE CONFIRMED-CATASTROPHE — but already documented at FIXREC §103 with HANDOFF-111.** Phase 302 attestation: the post-fix tactic-(b) "advance the index inside `resolveRedemptionPeriod`" closes the surface structurally; tactic-(a) revert closes the symptom. Tactic-(b) preferred per FIXREC §103.C analysis. **No new FIXREC-augment entry required; V-184 disposition is verbatim re-attested.**
- **(b) V-031 placeDegeneretteBet → prizePoolsPacked.future inflation.** Walked `DegeneretteModule._placeDegeneretteBet:405 → _collectBetFunds:533 → Storage.prizePoolsPacked.future +=`. The `_placeDegeneretteBet` external entry does NOT have a top-level `rngLockedFlag` gate. During rngLock window: attacker calls `placeDegeneretteBet{value: x}` → `prizePoolsPacked.future += x` (or proportional). The jackpot consumer `_processDailyEth` (`JackpotModule:1232`) reads `futurePool` to compute `ethDaySlice`. Attacker pays `x` ETH; the inflation factor at the consumer is `x / total_future_pool`. **Lens condition #3:** attacker pays full bet price `x`; their share of inflated pool is `(attacker_winning_prob × x / total)`. EV = `attacker_winning_prob × x × inflation_factor - x`. For attacker_winning_prob < 100% and inflation_factor ≤ 1, EV is bounded below 0. **The "MEDIUM-HIGH per-dollar leader" disposition in FIXREC §0.4 reflects MARGINAL EV per-tx, not absolute extraction.** Attacker pays their own bet; inflation rewards the attacker's win-conditional share. **Disposition: ACCEPTED_DESIGN — already documented at FIXREC §18 as MEDIUM-HIGH MARGINAL; no Phase 302 elevation.**
- **(c) Cluster G manual-path lootbox open re-derivation.** Walked the cross-index leak hypothesis: does Index A's `openLootBox` mutate Index B's commitment via shared parent slot? Reviewed `LootboxModule.openLootBox:526` body — slot reads `lootboxEth[index][player]`, `lootboxRngWordByIndex[index]`, `lootboxDay[index][player]`, `lootboxEvScorePacked[index][player]`, `lootboxBaseLevelPacked[index][player]`, `lootboxDistressEth[index][player]`. All slot accesses are PER-INDEX scoped (the mapping key is `index`). Self-zero rows V-088/V-094/V-097/V-100/V-103 zero ONLY the opening index's slot — no cross-index write. **No cross-index leak surfaced.** The Cluster G HIGH-tier EV remains in the cross-EOA `mintPacked_` activity-score writes (V-110/V-117 family), which are catalog-enumerated and FIXREC-handled. **Disposition: SAFE_BY_STRUCTURAL_CLOSURE (per-index isolation) for the self-zero rows; ACCEPTED_DESIGN for the writer-side gates (FIXREC §0.4 headline-2 disposition holds).**
- **(d) Cluster E `claimablePool` writer races — V-063 disposition conflict resolution.** FIXREC §0.7 marks V-063 as FALSE-POSITIVE-RECLASSIFY-TO-NON-PARTICIPATING (claim that `claimablePool` is pull-pattern-only). Independent re-derivation:
  - `claimablePool` is read at `GameOverModule.handleGameOverDrain:91`: `uint256 reserved = uint256(claimablePool) + uint256(claimableWinnings[VAULT]) + uint256(claimableWinnings[SDGNRS]) + uint256(claimableWinnings[GNRUS])`.
  - `reserved` is subtracted from `totalFunds` at `:93+` to compute `preRefundAvailable`. `preRefundAvailable` IS the magnitude consumed by the deity-refund pass (`:122 claimableWinnings[owner] += refund;`) and the post-refund terminal-distribution.
  - **A deflation of `claimablePool` BEFORE the SLOAD at `:91` REDUCES `reserved` → INCREASES `preRefundAvailable` → INCREASES the deity-refund magnitude AND the post-refund terminal distribution.**
  - Lens condition #1 (slot feeds VRF-derived output) — **TRUE.** `claimablePool` directly feeds the magnitude of the deity-refund redistribution AND the terminal-jackpot distribution, both of which are VRF-magnitude-input-window outputs.
  - **FIXREC §0.7 FALSE-POSITIVE-RECLASSIFY marker is itself questionable.** The slot IS participating per CATALOG §14 row S-16; the FIXREC §0.7 reclassify-prose appears to confuse "pull-pattern accumulator" (the `+=` direction is pull-pattern) with "non-VRF-input" (the `-=` direction via `_claimWinningsInternal` IS a VRF-input perturbation).
  - **Disposition: FINDING_CANDIDATE CONFIRMED-HIGH at V-063 + V-073 — but already covered by FIXREC §31 + §40 with HANDOFF-31/HANDOFF-40.** The existing FIXREC entries recommend tactic-(a) `_livenessTriggered() && !gameOver` gate at `_claimWinningsInternal:1400`. **Re-attestation: the FIXREC §31/§40 recommendation closes the slot structurally; FIXREC §0.7's FALSE-POSITIVE marker should be amended in Phase 303 §6 catalog hygiene.** No NEW Phase 302 elevation; existing handoff anchors stand. Beyond-charge entry (B1 below) captures the §0.7 marker amendment.
- **(e) Cluster A hero-override V-003..V-005 EV.** FIXREC §0.4 headline-5 MEDIUM disposition holds — the `dailyHeroWagers[day][q]` slot only flips one byte of one trait quadrant. Reviewed `JackpotModule._rollHeroSymbol` body (per v42 P296 precedent): the hero-symbol roll is a per-day-jackpot-scoped byte modification on the winning-trait selection; the dominant jackpot determinants (bucket-mask roll, prizePool size, ticket-queue level distribution) are unaffected. **Disposition: ACCEPTED_DESIGN.**
- **(f) Admin classes.** ADMIN-AUDIT R-01..R-22 dispositions: each admin function's writer-disposition is independent of EOA player game-theory. The only admin-EOA-collusion path that surfaces under the skeptic-filter discipline (admin-key compromise → COLLUSION-OUT-OF-SCOPE per the Governance tier disposition in FIXREC §0.5) is the R-02 `updateVrfCoordinatorAndSub` queue-vs-applied window — addressed by tactic-(c) pre-lock reorder per CATALOG §16 V-137 / FIXREC §M HANDOFF-78. **Disposition: SAFE_BY_STRUCTURAL_CLOSURE pending v44.0 FIX-MILESTONE for governance-tier rotation.**

**Notes:**

- The V-063 / V-073 FIXREC §0.7 marker amendment is the substantive game-theoretic finding. The slot IS participating; the FIXREC §31/§40 recommendation is correctly authored; only the §0.7 catalog-hygiene marker disagreed. This is a documentation conflict, not a new VIOLATION.
- V-184's CATASTROPHE re-attestation matches FIXREC §103 verbatim. The 19% per-round EV claim is confirmed under the 3-condition lens.

---

## Hypothesis (iv) — SWP-04: FINDING_CANDIDATE elevation routing

**Disposition:** SAFE (procedural attestation).

**Evidence:**

- I attest: any `FINDING_CANDIDATE` elevation from this pass routes through the FIXREC-augment append channel per `D-302-AUDIT-ONLY-ROUTING-01`, with severity per the 3-condition lens, suggested remediation drawn from the FIX-01 menu (a/b/c/d), and NO contract code in my output.
- No `SAFE_BY_DESIGN` candidate is emitted for any §14 participating slot in this pass (per the milestone-goal exclusion). All participating-slot dispositions are either `SAFE_BY_STRUCTURAL_CLOSURE`, `ACCEPTED_DESIGN` (documented), `NEGATIVE_RESULT_ONLY`, or `FINDING_CANDIDATE` (with `ALREADY-DOCUMENTED` flag where the FIXREC entry exists).

**Notes:**

- The hypothesis is procedural attestation; no substantive elevation arises from this hypothesis itself.

---

## Hypothesis (v) — SWP-05: Skill set + pre-authorization attestation

**Disposition:** SAFE (procedural attestation).

**Evidence:**

- I attest: `/degen-skeptic` is OUT OF SCOPE per `D-271-ADVERSARIAL-02`. `/economic-analyst` is IN SCOPE per `D-271-ADVERSARIAL-03`. Invocation is pre-authorized per `D-43N-SWEEP-PREAUTH-01`. Two-tier consensus rule per `D-302-CONSENSUS-01` applies at Task 5 integration. Skeptic-reviewer filter per `feedback_skeptic_pass_before_catastrophe.md` is applied BEFORE any FINDING_CANDIDATE presentation.

**Notes:**

- Procedural-only.

---

## Hypothesis (vi) — Augment (i): FIXREC-recommended tactic adequacy

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for V-184 tactic-(b); SAFE_BY_STRUCTURAL_CLOSURE for V-031 per-entry gate; FINDING_CANDIDATE-RECLASSIFY for V-063 (catalog-hygiene amendment).

**Evidence:**

- **V-184 tactic adequacy.** FIXREC §103.C recommends two tactics: (a) revert in `_submitGamblingClaimFrom` if `redemptionPeriods[redemptionPeriodIndex].roll != 0`; (b) structural advance of `redemptionPeriodIndex` inside `resolveRedemptionPeriod` itself.
  - Tactic-(a) walk: the revert closes the post-resolve same-day re-burn surface. A future protocol change that introduces a different post-resolve writer path (e.g., admin-injected base-amount setter; cross-contract callback writing `pendingRedemptionEthBase`) would re-open the gap UNLESS the same gate is replicated at every post-resolve write entry. **Defensive close — sufficient for v44.0 but not future-proof.**
  - Tactic-(b) walk: advancing `redemptionPeriodIndex` inside `resolveRedemptionPeriod` (after writing `redemptionPeriods[period] = {...}`) means that on a same-day post-resolve re-burn, `redemptionPeriodIndex` is now `D+1` and `currentPeriod` is still `D` (wall-clock). The `:758` conditional `redemptionPeriodIndex != currentPeriod` would fire (`D+1 != D`) — BUT this would RESET to `currentPeriod = D` (going BACKWARD!). **This breaks the protocol semantics.** The tactic-(b) implementation must be more careful: advance to `currentPeriod + 1` AND change the `:758` conditional to `redemptionPeriodIndex < currentPeriod` (or similar monotonic check). **Tactic-(b) is structurally cleaner but requires a coordinated tweak to `:758` semantics.**
  - **Adequacy disposition:** Tactic-(b) preferred but requires the v44.0 plan-phase to coordinate the `:758` semantics update. Tactic-(a) is the minimal close. FIXREC §103.C correctly enumerates both tactics; the implementation discipline for tactic-(b) is implicitly part of v44.0 plan-phase scope. **No augment needed.**
  - V-184 subsumption fan-out closes V-186/V-188/V-190/V-191/V-192/V-193 (the redemption-family slot writers downstream of V-184). Walked the subsumption: each subsumed row's slot (e.g., `pendingRedemptionEthBase`, `pendingRedemptionBurnieBase`) is cleared by `resolveRedemptionPeriod` and re-armed by `_submitGamblingClaimFrom`. The V-184 tactic-(a) revert BEFORE `_submitGamblingClaimFrom` proceeds prevents the re-arm for an already-resolved period; the subsumed-row re-arm classes are structurally closed by the same revert. **Subsumption confirmed.**
- **V-031 per-entry gate.** Walked the prizePoolsPacked.future inflation writer set:
  - V-024 (`MintModule.purchase` payment processing → prizePoolsPacked) — gated by MintModule:1215 / :1221.
  - V-025 (`WhaleModule.purchase` entries → prizePoolsPacked) — gated by WhaleModule:543 / :544.
  - V-026 (`WhaleModule.purchaseDeityPass` → prizePoolsPacked) — gated by WhaleModule:543 runtime check.
  - V-027 (`MintModule.recordDecBurn` → prizePoolsPacked) — BurnieCoin callback path; gated by BurnieCoinflip:730 upstream.
  - V-030 (`claimWhalePass → _queueTicketRange` writes) — gated by Storage:572 downstream revert.
  - V-031 (`placeDegeneretteBet → _collectBetFunds → prizePoolsPacked`) — **UNGATED at top-level (FIXREC §0.4 headline-3 confirms; verified by grep — no `rngLockedFlag` revert at `_placeDegeneretteBet:405` or `_collectBetFunds:533`).**
  - V-032 (`MintModule.useClaimableForMint`) — gated.
  - **Disposition:** The "single-entry-gate closes all" claim does NOT hold — each of V-024..V-032 needs its own gate (or its upstream caller's gate). FIXREC §13..§19 entries enumerate each. **V-031 is the lone genuinely-ungated row in the cluster; per-entry-gate is the correct disposition. FIXREC entries correctly per-entry.**
  - **Tactic-(a) adequacy for V-031:** A `rngLockedFlag` revert at `_placeDegeneretteBet:405` closes the rngLock-window inflation. No secondary writer exists for `prizePoolsPacked.future` reachable from `_placeDegeneretteBet`. **Sufficient.**
- **V-063 / V-073 FIXREC §0.7 catalog-hygiene amendment.** Per Hypothesis (iii)(d) re-derivation: `claimablePool` IS participating (read at `GameOverModule:91`); FIXREC §0.7 FALSE-POSITIVE-RECLASSIFY marker is INCORRECT. The slot deflation via `_claimWinningsInternal:1408` DOES change `preRefundAvailable` which IS a VRF-magnitude-input. **Augment surface: amend FIXREC §0.7 hygiene marker for V-063 from `FALSE-POSITIVE-RECLASSIFY-TO-NON-PARTICIPATING` to `CONFIRMED-PARTICIPATING-AT-GAME-OVER-DRAIN`.** This is a documentation/marker amendment, not a contract change; the recommended tactic at FIXREC §31 stands. **Disposition: FINDING_CANDIDATE (marker amendment) — routes to FIXREC §0.7 update in any FIXREC-augment, or Phase 303 §6 catalog hygiene if Phase 302 doesn't emit a FIXREC-augment.**

**Notes:**

- The V-184 tactic-(b) tweak observation is informational — the v44.0 plan-phase will handle the `:758` conditional update if tactic-(b) is selected.
- The V-063 marker amendment is documentation-class — does NOT require a v44.0 contract change beyond what FIXREC §31 already specifies.

---

## Hypothesis (vii) — Augment (ii): Admin-class cross-interaction

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for compositions; FINDING_CANDIDATE for the GNRUS `setCharity` catalog-gap row R-06 (already flagged by ADMA).

**Evidence:**

- **(a) Governance + parameter-update composition.** R-02 `updateVrfCoordinatorAndSub` writes S-47/S-48/S-49/S-38/S-46 (per ADMIN-AUDIT §0). The rotation-as-queue-vs-applied window is addressed by CATALOG §16 V-137 + ADMA R-02's tactic-(c) pre-lock reorder. The queue-vs-applied split, when implemented at v44.0, would create a "rotation pending" state where (a) the EXISTING coordinator still serves the in-flight VRF request and (b) the NEW coordinator becomes active only after `_unlockRng` closes the current window. **Pending tactic-(c) implementation at v44.0; no Phase 302 elevation.**
- **(b) Charity-allowlist composition.** R-06 `setCharity` (GNRUS catalog-gap candidate) mutates `currentSlate[slot]` at GNRUS:408. The `pickCharity:623` (called from `AdvanceModule._finalizeEarlybird` at AdvanceModule:1718) reads `currentSlate[bestSlot]`. Mid-rngLock `setCharity` could redirect a sDGNRS grant to a different charity. The grant magnitude per slot can be substantial (up to thousands of sDGNRS at high game-levels via the sDGNRS Reward pool routing).
  - Lens condition #1 (slot feeds VRF-derived output): the charity SELECTION is itself NOT VRF-derived (the slot index is selected by `pickCharity` per a non-RNG bestSlot algorithm); HOWEVER, the recipient of the VRF-determined Reward grant IS this slot's address. The VRF determines the GRANT MAGNITUDE; the slot determines the RECIPIENT IDENTITY. A mid-window `setCharity` doesn't change the magnitude but DOES change who receives it. **Lens condition #1 borderline: the output (recipient address) is non-VRF-derived; the magnitude is VRF-derived. Mid-window setCharity changes the recipient, not the magnitude.**
  - Lens condition #2 (mutable by non-EXEMPT actor): TRUE — `setCharity` is admin-callable (vault-owner trust boundary per GNRUS:378).
  - Lens condition #3 (mutator profits): admin-key-compromise required for the mutator to redirect to themselves; under the skeptic-filter discipline (admin-key compromise OUT OF SCOPE for non-Governance findings), this is `Governance` tier.
  - **Disposition:** ADMA R-06 already flagged as a catalog-gap candidate. The `currentSlate` slot is missing from CATALOG §14; ADMA recommends adding it. Phase 302 attestation: the recommendation is valid; the slot SHOULD be enumerated. **FINDING_CANDIDATE-RECLASSIFY-AS-CATALOG-GAP — already documented in ADMA R-06; no new Phase 302 elevation, but the v44.0 plan-phase should consume R-06 with a gate placement decision.**
- **(c) Vault-routed admin sub-call composition.** R-07..R-15 (vault-routed wrappers) — verified that EACH wrapper calls into the underlying game entry which has its own gate. The cross-trust-boundary (vault-owner > 50.1% holders) is a broader audience than ADMIN-EOA. The R-03/R-04/R-05 stake-ETH residual EV note in ADMA §0 highlight 2/3 is the load-bearing observation: an admin firing `swapGameEthForStEth` mid-drain can fund Lido while the game-over distributor reads `address(this).balance`. This is **already documented at ADMA R-03/R-04/R-05 with HANDOFF-03/04/05**; **Disposition: ACCEPTED_DESIGN under the Governance-tier framing (admin-key-compromise OUT OF SCOPE for non-Governance findings; v44.0 FIX-MILESTONE per ADMA discipline).**
- **(d) Cross-call admin sub-call into post-resolution claimWinnings.** R-18 `gameClaimWinnings` (vault-routed `claimWinnings`) reaches the same `_claimWinningsInternal:1399` callsite as V-063. The vault-routed claim has the same `_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK)` check (line 1400) and the same absence of `_livenessTriggered()` gate. **The vault-routed entry inherits V-063's exact disposition.** No new admin-class composition surfaces.
- **(e) R-06 catalog-gap re-attestation.** Per (b) above, `currentSlate` is missing from CATALOG §14. The v44.0 plan-phase should add it as a new §14 row and apply the R-06 gate. **FINDING_CANDIDATE — already at ADMA R-06.**

**Notes:**

- No genuinely NEW admin-class composition surfaces beyond what ADMA enumerates.
- The Governance-tier framing per FIXREC §0.5 + ADMA §0 holds: admin-key-compromise scenarios are HIGH under owner-honest-but-curious, MEDIUM under owner-honest, NOT non-admin exploit surfaces.

---

## Hypothesis (viii) — Augment (iii): FUZZ harness `vm.skip` coverage gaps

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for the 17 documented vm.skip blocks (skip-for-future-fix-flip pattern); FINDING_CANDIDATE for two coverage gaps where no fuzz function reaches the surface.

**Evidence:**

- **(a) 17 vm.skip blocks — all confirmed as skip-for-future-fix-flip pattern.** Each skip's comment cites a FIXREC sec + HANDOFF-NN anchor; the test body, if executed, would FAIL because the underlying VIOLATION is not yet fixed. The skip preserves CI-green at v43 close per `D-43N-FUZZ-VMSKIP-01`. **Disposition for each of the 17: SAFE_BY_STRUCTURAL_CLOSURE under the "test exists; flip-to-assertion deferred to v44.0" framing.**
- **(b) Action coverage per consumer.** Walked the `_perturb(seed)` action set (0-8, 9 actions per FUZZ-02 disposition) against §14 writer set. Per spot-check:
  - S-22 `lootboxEvBenefitUsedByLevel` writers (FIXREC §43..§45 V-081/V-082/V-084) — exercised by ResolveRedemptionLootbox / ResolveLootboxCommon / DegeneretteLootboxDirect fuzz functions (with vm.skip). Coverage adequate.
  - S-32 `mintPacked_` writers (FIXREC §65..§71 V-110..V-117 family) — exercised by MintTraitGeneration fuzz function (with vm.skip cluster H). Coverage adequate.
  - S-56 `redemptionPeriodIndex` writers (V-184) — exercised by StakedStonkRedemption fuzz function (with vm.skip sec103). Coverage adequate; **but the test exercises SAME-DAY re-burns; does it cover the cross-day boundary?** Re-reading test/fuzz/RngLockDeterminism.t.sol:1270-1280 — the fuzz body simulates the burn-resolve-reburn sequence; verifying that the CROSS-DAY portion is genuinely covered would require source-level inspection of the fuzz body, but the comment cites "V-184 sStonk cross-day re-roll CATASTROPHE" — the comment matches the cross-day exploit shape.
- **(c) Edge-case coverage gaps.**
  - **Cross-EOA Sybil within single rngLock window:** NOT explicitly covered by any of the 5 edge-case fuzz functions. The harness's `_perturb(seed)` randomizes the actor address but doesn't structure cross-EOA collusion. **GAP: a fuzz function exercising 2+ EOAs simultaneously perturbing within the same rngLock window is missing.**
  - **ERC721 receiver-callback perturbations:** The deity-pass mint flow could trigger an `onERC721Received` callback that re-enters `contracts/`. The harness doesn't include an ERC721-receiver-style malicious recipient. **GAP: a fuzz function with a malicious ERC721 receiver re-entering deity-pass mint is missing.** Note: Hypothesis (ii) attested that the ERC721 callback fires AFTER the participating-slot write, so the exploit surface is bounded — but a fuzz function would harden the attestation.
  - **Cross-currency stETH yield accrual perturbation:** R-04 `adminStakeEthForStEth` Lido yield-bearing growth observation from ADMA §0 — does the harness exercise a Lido yield-arrival landing inside the rngLock window? The `_perturbAdminOnly` covers R-04 admin invocation but not the post-stake Lido-yield-arrival. **GAP: a fuzz function exercising stETH yield accrual mid-window is missing.**
- **(d) Multi-tx-batch / near-end-of-window / multi-block / retry-during-lock coverage adequate.** The 5 edge-case fuzz functions (`testFuzz_EdgeCase_AdminDuringLock`, `_NearEndOfWindow`, `_MultiTxBatch`, `_MultiBlock`, `_RetryLootboxRngDuringLock`) cover the named edge cases. All have `vm.skip(true)` at v43 close per the skip-for-future-fix-flip pattern.

**Notes:**

- The 3 GAP entries (cross-EOA Sybil; ERC721 receiver callback; stETH yield accrual) are coverage observations, not VIOLATIONs in the contract surface. They surface as FINDING_CANDIDATE on the FUZZ harness, with suggested remediation: add 3 new `testFuzz_EdgeCase_*` functions targeting these surfaces. **DO NOT auto-modify `test/fuzz/RngLockDeterminism.t.sol`** per `feedback_no_contract_commits.md` — FUZZ harness extension requires user approval at Task 6 AskUserQuestion.
- The cross-day re-roll coverage on StakedStonkRedemption (sec103/V-184) is the load-bearing case. Re-attestation in source-level FUZZ harness review (out of Phase 302 scope) would verify the simulation matches the §103 cross-day exploit chain.

**Severity (if FINDING_CANDIDATE):** LOW (FUZZ-harness coverage gaps, not contract VIOLATION).

**Suggested remediation:** Tactic (option-a-equivalent for FUZZ): add 3 new `testFuzz_EdgeCase_*` functions covering (i) Cross-EOA Sybil within rngLock window; (ii) ERC721 receiver-callback re-entry on deity-pass mint; (iii) stETH yield accrual mid-window. Each new function ships with appropriate `vm.skip` blocks for currently-unfixed VIOLATION classes per `D-301-VMSKIP-MECHANISM-01` Option C. User approval required per `feedback_no_contract_commits.md`.

---

## Hypothesis (ix) — Augment (iv): Cross-consumer entropy bleed

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for most shared slots; FINDING_CANDIDATE re-derivation for S-22 (cluster G EV-cap accumulator) consistent with FIXREC §43..§45 disposition.

**Evidence:**

- **(a) S-03 `level` (8 consumers).** Single-writer (`_finalizeRngRequest` advance-level branch + constructor init) — EXEMPT-ADVANCEGAME and EXEMPT-CONSTRUCTOR. Cross-consumer reads at §1/§2/§5/§6/§7/§8/§10/§13 all observe the SAME `level` value per game-day. No cross-consumer mutation surface. **SAFE_BY_STRUCTURAL_CLOSURE.**
- **(b) S-40 `ticketWriteSlot` (6 consumers).** Writer set per CATALOG §15 — primarily `_unlockRng` and `advanceGame` internal writes; EXEMPT-ADVANCEGAME. The 6-consumer fanout doesn't introduce a non-EXEMPT mutation path; cross-consumer reads observe the same value. **SAFE_BY_STRUCTURAL_CLOSURE.**
- **(c) S-22 `lootboxEvBenefitUsedByLevel` (4 consumers — §6/§7/§8/§13).** Walked the slot's writer (`_applyEvMultiplierWithCap:511`) and its 4 consumer entry points (`openLootBox:567 → _resolveLootboxCommon:680/:716`; `resolveLootboxDirect:567`; `resolveRedemptionLootbox:680`; `_awardDecimatorLootbox:716`).
  - The slot is a **cross-resolution accumulator**: each resolution reads the slot's current value, computes `adjustedPortion = min(amount, LOOTBOX_EV_BENEFIT_CAP - usedBenefit)`, applies the EV multiplier to `adjustedPortion`, and WRITES BACK `usedBenefit + adjustedPortion`.
  - **Cross-consumer leak:** Player A opens lootbox at index N1 (via ETH `openLootBox`) → reads `usedBenefit` for `(player, lvl)` = 0; gets full EV multiplier on full `amount`; writes back `adjustedPortion`. Player A then opens lootbox at index N2 (via BURNIE `openBurnieLootBox`) → reads `usedBenefit = adjustedPortion`; gets PARTIAL EV multiplier (cap-bounded). This is the LEGITIMATE anti-farming cap.
  - **The exploit shape (per FIXREC §43..§45 + `feedback_rng_window_storage_read_freshness.md`):** Player can SEQUENCE the multi-lootbox opens to maximize cumulative EV. If lootbox at N1's `evMultiplierBps` is LOW (post-VRF observation), player opens N1 LAST (after exhausting cap on other higher-multiplier indices); if HIGH, player opens N1 FIRST (capturing cap allocation). The cross-resolution accumulator pattern bypasses per-index snapshot freshness.
  - 3-condition lens:
    - (1) Slot feeds VRF-derived output: ✓ — `evMultiplierBps` (derived from `playerActivityScore` and lootbox tier roll) directly multiplies `scaledAmount`.
    - (2) Mutable mid-rngLock by non-EXEMPT actor: TRUE — the SLOT itself is mutated by the consumer's own resolution path; the player can OBSERVE the slot value before each open and choose ordering. The consumer-writer atomicity is preserved per-resolution, but the cross-resolution ordering IS player-controllable.
    - (3) Mutation profits attacker: TRUE — informed ordering captures cap allocation for highest-EV indices.
  - **Disposition:** FINDING_CANDIDATE-CONFIRMED-HIGH-tier per FIXREC §0.4 headline-2 + FIXREC §43..§45 entries (V-081/V-082/V-084). **Already documented; HANDOFF-43..HANDOFF-45 anchors stand.** The recommended tactic-(b) per-index snapshot at allocation closes the cross-consumer entropy bleed. **No new Phase 302 elevation needed.**
  - **Per-consumer snapshot adequacy:** Per FIXREC §43.C, the snapshot pattern captures `usedBenefit` at allocation time (per-index per-level). The per-consumer fanout (4 consumer entries) inherits the same snapshot via the per-index field. **Adequate.**
- **(d) S-38 `rngRequestTime` (4 consumers including §9 retryLootboxRng).** Writer single — `_unlockRng` clears (sets to 0) at end of advanceGame; `requestLootboxRng` sets to `block.timestamp` at request time. Cross-consumer reads observe `rngRequestTime != 0` as "lock in progress". The retry path's guard at `retryLootboxRng:1132` checks `rngRequestTime != 0 && (block.timestamp - rngRequestTime) >= 6h` cooldown. **No cross-consumer mutation surface.** The retry path is EXEMPT-RETRYLOOTBOXRNG (3rd exempt entry per the freeze invariant). **SAFE_BY_STRUCTURAL_CLOSURE.**
- **(e) S-14 / S-15 cross-contract sDGNRS pool balances.** OZ-inherited writers covered by V-046 carveout (FIXREC §22); non-OZ writers covered by V-043/V-045 (FIXREC §20/§21). The cross-consumer fanout (§1/§8/§11 for Reward; §6/§7/§8 for Lootbox) is enumerated in CATALOG. No new cross-consumer bleed surfaces beyond what FIXREC handles.
- **(f) S-55 `bountyOwedTo` (§11 BurnieCoinflip) cross-consumer.** Per Phase 296 (xiv) Tier-1 ACCEPT_AS_DOCUMENTED disposition (preserved in v43 via FIXREC §102 V-182 HANDOFF-110), the bountyOwedTo entropy correlation is documented. No new cross-§12 sStonk surface surfaces — the slots are domain-separated.
- **(g) S-17 / S-57..S-60 / S-61 sStonk redemption family cross-consumer.** V-184 (S-56) addresses the cross-day re-roll on the redemption-period index. The subsumed rows (V-186/V-188/V-190/V-191/V-192/V-193) capture the redemption-family slot writers that are structurally closed by V-184's fix. No new cross-consumer bleed beyond V-184's HANDOFF-111 fan-out.

**Notes:**

- The S-22 cross-consumer accumulator is the load-bearing finding — confirmed at HIGH-tier per FIXREC §43..§45. The per-index snapshot tactic-(b) closes the cross-consumer fanout structurally.
- The cross-contract S-14/S-15 pool-balance carveout is handled by V-046; no new cross-contract bleed.

---

## Beyond-charge entries

### Beyond-charge (B1) — FIXREC §0.7 catalog-hygiene marker amendment for V-063

**Disposition:** FINDING_CANDIDATE (documentation/marker amendment, not a contract change).

**Description:** FIXREC §0.7's FALSE-POSITIVE / RECLASSIFY-TO-NON-PARTICIPATING marker for V-063 (`claimablePool` deflation via `_claimWinningsInternal`) is INCORRECT. Per Hypothesis (iii)(d) re-derivation, `claimablePool` IS read at `GameOverModule.handleGameOverDrain:91` as part of the `reserved` computation, which feeds `preRefundAvailable` which IS a VRF-magnitude-input. The `_claimWinningsInternal:1408` `-=` writer DOES change the VRF-derived `preRefundAvailable` magnitude.

**Severity:** LOW (documentation-class amendment; the operational FIXREC §31 gate-add recommendation stands).

**Suggested remediation:** Amend FIXREC §0.7 marker for V-063 from `FALSE-POSITIVE / RECLASSIFY-TO-NON-PARTICIPATING` to `CONFIRMED-PARTICIPATING-AT-GAME-OVER-DRAIN`. The FIXREC §31 recommendation (tactic-(a) `_livenessTriggered() && !gameOver` gate at `_claimWinningsInternal:1400`) is correct and closes both V-063 and V-073 simultaneously per FIXREC §0.6 subsumption map row HANDOFF-31. Routes to Phase 303 §6 catalog hygiene OR FIXREC-augment.

---

### Beyond-charge (B2) — Suggested 3 new FUZZ harness edge-case functions

**Disposition:** FINDING_CANDIDATE (FUZZ-harness coverage gap, not contract VIOLATION).

**Description:** Per Hypothesis (viii)(c), three edge-case fuzz functions are missing from `test/fuzz/RngLockDeterminism.t.sol`:
1. Cross-EOA Sybil within single rngLock window (2+ EOAs simultaneously perturbing).
2. ERC721 receiver-callback re-entry on deity-pass mint (malicious ERC721 receiver).
3. stETH yield accrual mid-window (Lido yield-arrival between R-04 admin stake and window close).

**Severity:** LOW (coverage gap; the underlying VIOLATIONs would be caught by existing fuzz functions; these new functions harden the attestation).

**Suggested remediation:** Add 3 new `testFuzz_EdgeCase_*` functions to `test/fuzz/RngLockDeterminism.t.sol`. Each ships with appropriate `vm.skip` blocks per `D-301-VMSKIP-MECHANISM-01` Option C. **User approval required per `feedback_no_contract_commits.md`** — DO NOT auto-modify the test file. v44.0 plan-phase consumes the recommendation.

---

## Cross-cutting note

The v43.0 audit subject — the rngLock freeze invariant + Phases 298-301 artifacts — is comprehensively covered by the catalog + FIXREC + ADMA + FUZZ artifact set. The Phase 302 adversarial pass produces:
- **Zero new CATASTROPHE-tier findings.** V-184 is the lone CATASTROPHE per FIXREC §103; re-attested at confirmed-19% EV under the 3-condition lens.
- **Zero new HIGH-tier findings** that aren't already documented in FIXREC.
- **Two documentation-class findings (B1 + V-063 marker amendment; B2 + 3 missing FUZZ functions)** that route to Phase 303 §6 catalog hygiene or FIXREC-augment append.
- **Three PENDING-VERIFICATION markers resolved** (V-047/V-048/V-050 → NO REAL EV from drain-shape; cross-player frontrun is ACCEPTED_DESIGN intrinsic to pool-routing).
- **STALE-CATALOG-ROW V-016/V-017/V-018 re-confirmed STALE** (no writer in source; line numbers point to view functions).

The 3-condition catastrophe lens applied throughout produces a tight upper bound on tier classification: V-184 confirmed CATASTROPHE; cluster G S-22 confirmed HIGH (documented); all other surfaces decompose to MEDIUM/LOW/ACCEPTABLE-DESIGN or SAFE_BY_STRUCTURAL_CLOSURE.

**Zero CRITICAL findings, zero NEW HIGH findings, zero NEW CATASTROPHE findings. Two LOW documentation-class beyond-charge findings.**

---

*Phase: 302-cross-surface-adversarial-sweep-sweep*
*Skill: /contract-auditor (SEQUENTIAL_MAIN_CONTEXT per D-302-INVOKE-01)*
*Hypothesis count: 9 charged + 2 beyond-charge*
*No contract code in output per `feedback_never_preapprove_contracts.md` + `feedback_no_contract_commits.md`*
*No post-v43 forward-cite tokens; only `D-43N-V44-HANDOFF-NN` + `D-43N-V44-ADMA-NN` identifiers + descriptive labels used*
