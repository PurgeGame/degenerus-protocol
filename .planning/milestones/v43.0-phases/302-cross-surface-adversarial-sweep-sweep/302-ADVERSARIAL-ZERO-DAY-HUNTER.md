---
artifact: ADVERSARIAL-ZERO-DAY-HUNTER
phase: 302-cross-surface-adversarial-sweep-sweep
plan: 01
milestone: v43.0
skill: zero-day-hunter
adversarial_pass_pattern: SEQUENTIAL_MAIN_CONTEXT (Tasks 3+4 originally planned as PARALLEL_SUBAGENT — executor lacks Task tool in current invocation context per v42 P296 precedent fallback; persona-fidelity preserved via sequential main-context run)
audit_subject: rngLock freeze invariant + Phase 298-301 audit artifacts (CATALOG + FIXREC + ADMA + FUZZ)
charge_hypothesis_count: 9 charged + 3 beyond-charge
generated_at: 2026-05-18
---

# Phase 302 Adversarial Pass — /zero-day-hunter

3-skill HYBRID adversarial sweep against the v43.0 audit subject. Persona: Novel attack surface hunter for Degenerus Protocol. Thinks like a C4A warden hunting one weird edge case. Focuses on creative, unconventional, composition-based attack surfaces that the contract-auditor's structural-coverage methodology might miss.

**Skill methodology applied:**
- Look for ERC777/ERC721/ERC677 callback windows missed by per-module audit.
- Look for cross-contract reverse callbacks (sister contracts calling back into the game).
- Look for "by construction" claims that don't hold under composition (Phase 294 BURNIE-gap precedent).
- Look for timing-windows that span multiple blocks or wall-clock boundaries.
- Look for `keccak256(vrfWord, ...)` derivations that might cross-correlate between consumers.
- Always grep-verify against source per `feedback_verify_call_graph_against_source.md`.

---

## Hypothesis (i) — SWP-01: Freeze-invariant storage paths

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE — no novel freeze-invariant violation surfaces.

**Evidence:**

- The catalog §15 writer enumeration was constructed via comprehensive grep over `contracts/`. Walking the §14 row × §15 writer cross-product produced no missing writers. Spot-checked S-09 `prizePoolsPacked` (highest fanout at 4+ writer sites across 6 modules per CATALOG §15); each writer is either EXEMPT-ADVANCEGAME-stack or catalog-flagged as VIOLATION at FIXREC §N.
- The 17 vm.skip blocks in the FUZZ harness map onto the FIXREC §N anchor set 1-to-1 per the v44.0 flip-to-assertion discipline; the writer set is exhaustively re-attested at runtime via the harness.
- Independent grep for `assembly { sstore` patterns (catalog §17 grep-gate Pattern 1) and `function .*external|public` (Pattern 2) re-confirms the writer count.
- **PENDING-VERIFICATION V-047/V-048/V-050 re-derivation (from `/zero-day-hunter` lens):** the "drain-pool-before-resolution" exploit shape — could a HOSTILE THIRD PARTY (not the lootbox-holder) drain `sDGNRS poolBalances[Lootbox]` to grief the holder? Walking the sDGNRS Lootbox-pool writers: `transferFromPool` at sDGNRS:412 is `onlyGame`-gated (reaches sister-contract path via `LootboxModule._creditDgnrsReward:1786`). The third-party drain requires the third party to be ITSELF a lootbox-holder calling their own `openLootBox`. Self-griefing (deflating own potential payout) is irrational. **No novel third-party drain vector surfaces. The `/contract-auditor` disposition (NEGATIVE_RESULT_ONLY for drain-shape; ACCEPTED_DESIGN for cross-player frontrun) is corroborated by independent zero-day re-derivation.**

**Notes:**

- The catalog completeness gate at CAT-06 (CATALOG §17) is strong. The grep-gate patterns cover SSTORE-equivalent + SLOAD-equivalent + external/public surface; the writer enumeration is empirically exhaustive.
- The retry path (S-46 LR_MID_DAY + S-38 rngRequestTime) creates an EXEMPT-RETRYLOOTBOXRNG envelope per `D-42N-RETRY-RNG-DOMAIN-SEP-01`; my hunt for "retry path doing more than its docstring" — see beyond-charge (B1).

---

## Hypothesis (ii) — SWP-02: Novel attack surfaces

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for most, FINDING_CANDIDATE for one novel composition (see beyond-charge B1 — retry-vs-daily entropy aliasing; already documented at Phase 296 (xiv) Tier-1 ACCEPT_AS_DOCUMENTED).

**Evidence:**

- **(a) ERC777 / ERC677 hooks.** Grep verification:
  - sDGNRS is NOT ERC777 (no `tokensReceived` hook on the token; standard ERC20).
  - BurnieCoin is NOT ERC777 (standard ERC20 with internal `_handleSpenderCallback` for routed transfers; not a `tokensReceived` recipient hook).
  - **ERC677 `onTokenTransfer` SURFACE: `DegenerusAdmin.sol:977 function onTokenTransfer(...)` — this is the LINK token receiver hook for the LINK→subscription auto-fund path.** Grep verifies: `DegenerusAdmin.sol:31` docstring confirms "LINK funding via onTokenTransfer (ERC-677)". The function is called BY the LINK token's `transferAndCall` mechanism; the caller is the LINK token contract address, gated by `if (msg.sender != address(LINK)) revert`. No re-entrancy into `contracts/` from this path that touches §14 slots (the function only manages LINK subscription accounting on the DegenerusAdmin contract; it does NOT call back into DegenerusGame). **No novel re-entrancy surface.**
- **(b) Cross-contract reverse callbacks.** BurnieCoinflip → DegenerusGame callbacks:
  - `DegenerusGame.deactivateAfKingFromCoin:1641` — called from coinflip (e.g., on flip-mode change). Writes `autoRebuyState[player]` (S-05). Catalog row V-012; FIXREC §7 LOW-ACCEPTABLE-DESIGN tier.
  - `DegenerusGame.syncAfKingLazyPassFromCoin:1654` — called from coinflip. Writes `autoRebuyState[player]` (S-05). Catalog row V-013; FIXREC §8 LOW-ACCEPTABLE-DESIGN tier.
  - Both are already enumerated in FIXREC. The disposition: afKing toggle costs the player their own afKing-active bonus; no cross-player extraction.
  - **Cross-callback composition check:** Could a BurnieCoinflip call into deactivateAfKingFromCoin DURING rngLock window? Re-attestation: `BurnieCoinflip.sol:730` has `if (rngLockedFlag) revert RngLocked();` gate — the gate is at the BurnieCoinflip ENTRY, not at the game-callback receiver. Tracing the callsite chain: `BurnieCoinflip._resolveFlip → BurnieCoinflip.settleFlipModeChange → DegenerusGame.deactivateAfKingFromCoin`. The `_resolveFlip` is called from `processCoinflipPayouts` which is reached from `AdvanceModule._applyDailyRng` (EXEMPT-ADVANCEGAME-stack). **The reverse-callback fires INSIDE the EXEMPT advanceGame stack** — this is exempt-by-construction.
- **(c) Multi-block window exploits.** Walked the rngLock-window state machine:
  - `rngLockedFlag = true` at `_finalizeRngRequest:1634` AFTER VRF request submission.
  - `rngLockedFlag = false` at `_unlockRng` at advanceGame end.
  - Between request and callback (VRF coordinator latency ~1-2 blocks on Arbitrum): the window is open. Any EOA function callable in this window WITHOUT a gate IS catalog-flagged. No novel multi-block surface.
  - **Subtle observation:** `_applyDailyRng:1828` includes `totalFlipReversals` nudge logic (`finalWord += nudges`). The nudges are accumulated across the window via `BurnieCoinflip` activity. **Question:** is `totalFlipReversals` a §14 participating slot? Grep CATALOG §14 — NOT enumerated. **Catalog gap candidate!** Let me re-derive: `totalFlipReversals` is written by `BurnieCoinflip` flip events (likely `addFlipReversal` style); it's READ inside `_applyDailyRng:1832` which is EXEMPT-ADVANCEGAME. The READ is during the resolution itself — i.e., AT VRF-callback-time. If a player can write `totalFlipReversals` AFTER `_finalizeRngRequest:1634` (rngLockedFlag=true) but BEFORE `_applyDailyRng` consumes it, that's a novel surface. See beyond-charge (B2).
- **(d) Cross-module composition.** Walked the cross-module call graph (12-module surface). The composition pattern `Module A entry → Module B writer` is enumerated in §15 callsite columns. Spot-check on `JackpotModule._processDailyEth → DegeneretteModule._addClaimableEth` (V-058 cluster) — gated by `rngLockedFlag` at JackpotModule level. No genuinely-novel composition surfaces.
- **(e) ERC721 deity-pass mint callback.** Walked `WhaleModule._purchaseDeityPass:542`:
  - Line 598: `deityBySymbol[fullSymId] = buyer` (the catalog-flagged write).
  - Subsequent: `IDegenerusDeityPass(deityPass).mint(buyer, fullSymId)` (cross-contract mint call).
  - **Key ordering:** the §14 slot write at `:598` happens BEFORE the ERC721 mint. The OZ ERC721 `_safeMint` invokes `_checkOnERC721Received` AFTER the receiver gets the token. **Even if the receiver re-enters `contracts/`, the deity slot is already committed.** A re-entry could attempt another `purchaseDeityPass` — but the function-head gate at `WhaleModule:543` reverts on `rngLockedFlag`. **No novel ERC721 callback surface.**
- **(f) Reverse-callback into `_claimWinningsInternal`.** Walked the cross-contract callers of `claimWinnings`:
  - `claimWinnings(address)` — external; callable by anyone.
  - `claimWinningsStethFirst()` — external; gated to VAULT.
  - `_claimWinningsInternal` body has only `_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK)` gate. **No `rngLockedFlag` or `_livenessTriggered()` gate.** This is V-063 / V-073 territory — already documented; my `/zero-day-hunter` re-derivation confirms the `/contract-auditor` finding on V-063 lens-condition #1 (`claimablePool` IS read by `GameOverModule.handleGameOverDrain:91` as part of `reserved`; lens-condition #1 holds). The FIXREC §0.7 FALSE-POSITIVE marker is incorrect; the operational FIXREC §31 gate-add is correct.

**Notes:**

- The DegenerusAdmin.onTokenTransfer surface is the lone novel callback discovered; it's gated by msg.sender check and does NOT reach §14 slots. Negative result.
- The `totalFlipReversals` observation (beyond-charge B2) is the substantive zero-day hunt finding — catalog gap candidate.

---

## Hypothesis (iii) — SWP-03: Game-theoretic write-induced effects

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for novel game-theoretic compositions (no zero-day extraction surface beyond the documented V-184 CATASTROPHE).

**Evidence:**

- The 3-condition catastrophe lens is satisfied only by V-184 (FIXREC §103). All other documented VIOLATIONs decompose to HIGH/MEDIUM/LOW under the lens.
- **Game-theoretic surfaces my zero-day hunt examined:**
  - **(α) Sybil cross-EOA collusion within single rngLock window.** Two attacker EOAs A and B coordinate: A places a degenerette bet on quadrant Q1 inflating `dailyHeroWagers[day][Q1]`; B places a wager on quadrant Q2. The hero-symbol roll consumes both. **No coordination produces a strictly-better EV than the per-EOA strategy** because the hero-override magnitude is bounded by per-quadrant wager-volume share (per FIXREC §0.4 headline-5 MEDIUM dispo).
  - **(β) Cross-contract callback chained inside resolution.** `BurnieCoinflip._resolveFlip` (§11 consumer) chains into `DegenerusGame.deactivateAfKingFromCoin` (writes S-05 V-012). The chain fires inside the advance-stack — EXEMPT.
  - **(γ) Time-of-VRF-vs-time-of-claim asymmetry.** Player A burns sDGNRS at hour 0 of day D; `resolveRedemptionPeriod` runs at hour 23:59 of day D. Player A has 23+ hours to observe other players' burn activity and decide whether to burn additional sDGNRS to inflate `pendingRedemptionEthBase` (which doesn't matter individually since rolls apply proportionally) — but the cross-day re-roll surface IS V-184. Time-of-VRF observation doesn't produce a NEW surface.
  - **(δ) MEV bot bet reordering within block.** Walked the bet-placement path: `placeDegeneretteBet` writes `dailyHeroWagers` atomically with `_collectBetFunds`. Block ordering doesn't change the aggregate wager state for the hero-symbol roll (rolls happen at VRF callback, not at bet time). MEV bots cannot gain information about the future VRF word from observing other bets. **No novel MEV surface.**
  - **(ε) Cross-EOA wagering on contradictory quadrants.** A single attacker could spread bets across all 4 quadrants to inflate `effectiveTotal` and dilute the leader-bonus mechanic — but per FIXREC §0.4 headline-5, the leader-bonus only affects the WINNING symbol selection (rare), and attacker pays full bet price across all 4 quadrants. EV is bounded below 0.
- **The lens defeats every game-theoretic surface I considered except V-184.** V-184 is documented; no new elevation.

**Notes:**

- The zero-day hunt for "irrational-attacker griefing" produces no surface because Degenerus' fee-burn mechanic + bet-cost requirement structurally taxes irrational strategies.
- The cross-day re-roll on V-184 is exceptional because the cost (1 wei) is negligible AND the EV is asymmetric (informed re-roll filter).

---

## Hypothesis (iv) — SWP-04: FINDING_CANDIDATE elevation routing

**Disposition:** SAFE (procedural attestation).

**Evidence:**

- Attestation: any `FINDING_CANDIDATE` from this pass routes through FIXREC-augment append per `D-302-AUDIT-ONLY-ROUTING-01`. Severity per 3-condition lens. Suggested remediation from FIX-01 menu (a/b/c/d). NO contract code in output.

---

## Hypothesis (v) — SWP-05: Skill set + pre-authorization attestation

**Disposition:** SAFE (procedural attestation).

**Evidence:**

- `/degen-skeptic` OUT OF SCOPE per `D-271-ADVERSARIAL-02`. `/economic-analyst` IN SCOPE per `D-271-ADVERSARIAL-03`. Pre-authorization per `D-43N-SWEEP-PREAUTH-01`. Two-tier consensus per `D-302-CONSENSUS-01`. Skeptic-filter per `feedback_skeptic_pass_before_catastrophe.md` applied pre-presentation.

---

## Hypothesis (vi) — Augment (i): FIXREC-recommended tactic adequacy

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for V-184, V-031, V-063 tactics — corroborates `/contract-auditor` re-derivation.

**Evidence:**

- **V-184 tactic adequacy from zero-day lens.** Walked the post-fix state for both tactic-(a) and tactic-(b):
  - **Tactic-(a) walk for novel evasion:** the revert checks `redemptionPeriods[redemptionPeriodIndex].roll != 0`. Could an attacker bypass by triggering a state where `redemptionPeriods[index].roll == 0` after resolution? Only if `roll` was originally 0 — but `resolveRedemptionPeriod` is called with `roll` in range 25-175 per AdvanceModule:1226 derivation, never 0 (`((currentWord >> 8) % 151) + 25` is in [25, 175]). So `roll == 0` only at unresolved-period state. The revert correctly fires.
  - **Tactic-(b) walk for novel evasion:** advancing `redemptionPeriodIndex` to `currentPeriod + 1` inside `resolveRedemptionPeriod` AND updating `:758` conditional to `redemptionPeriodIndex < currentPeriod`. Could an attacker manipulate `currentPeriod` (via game.currentDayView())? `currentDayView` is `(timestamp - launchTime) / 86400`, where `launchTime` is immutable post-deploy. Timestamp is miner-controllable to ~12-second skew on Arbitrum; not enough to slip a fake day boundary. **Tactic-(b) implementation is robust under realistic attacker capabilities.**
  - **Could `pendingRedemptionEthBase` be re-armed via a path OTHER than `_submitGamblingClaimFrom`?** Grep `pendingRedemptionEthBase` writes in `StakedDegenerusStonk.sol`: at `:594` (cleared in resolve), `:790` (incremented in `_submitGamblingClaimFrom`). **No other writer.** The tactic-(a) gate at `_submitGamblingClaimFrom` is the COMPLETE close for re-arm.
- **V-031 per-entry-gate adequacy from zero-day lens.** Walked `_placeDegeneretteBet` for novel paths around the gate:
  - The function is reached from EOA `placeDegeneretteBet`, `DegenerusGame.placeDegeneretteBet` (parent dispatch), `DegenerusVault.gameDegeneretteBet` (vault-routed). Each entry routes through `_placeDegeneretteBetCore` which writes `prizePoolsPacked.future +=`. Gating at `_placeDegeneretteBetCore` (the shared writer) closes all 3 entries. **Tactic-(a) at the shared writer is the optimal gate placement.**
- **V-063 tactic adequacy.** Walked the post-fix state for `_livenessTriggered() && !gameOver` gate at `:1400`. The gate's complement (`!_livenessTriggered() || gameOver`) preserves legitimate access:
  - Pre-liveness window: any player can claim normally.
  - Liveness window (final-day drain in progress): blocked.
  - Post-gameOver (after final drain): unblocked again for player payouts.
  - The transition `_livenessTriggered() → gameOver=true` happens atomically at `_finalizeRngRequest:1643` `level` advance branch. **No window where both `_livenessTriggered()` and `!gameOver` are simultaneously true for legitimate player access.** The gate correctly closes the magnitude-input window without breaking the post-drain payout path.

**Notes:**

- The FIX-01 menu tactics are robust under zero-day re-derivation. No augment needed.

---

## Hypothesis (vii) — Augment (ii): Admin-class cross-interaction

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for compositions; FINDING_CANDIDATE-RECLASSIFY for R-06 catalog-gap (already at ADMA).

**Evidence:**

- **R-02 + R-01 governance composition (VRF rotation queue + immutable wire).** R-01 `wireVrf` is one-shot post-deploy per the AdvanceModule:493 docstring; calls during normal operation revert. R-02 `updateVrfCoordinatorAndSub` is the operational rotation entry. The "between R-02 queue and R-02 applied" window exists only after the v44.0 tactic-(c) implementation lands the queue-vs-applied split — at v43 close, R-02 writes the slots DIRECTLY (per CATALOG §16 V-137 verdict). **Novel zero-day surface check:** could a non-admin EOA observe an in-flight VRF request and predict the VRF coordinator's response before R-02 changes coordinator addresses? Verifiable: VRF coordinator's `randomWords` are submitted via the verified-random-source protocol; predicting them requires breaking VRF. **No novel non-admin surface.**
- **R-06 setCharity composition.** Independently corroborated: `currentSlate` is missing from CATALOG §14. The slot SHOULD be participating per the pickCharity:623 → `_finalizeEarlybird:1718` reach into advance stack. ADMA R-06 correctly identifies this. **No new Phase 302 elevation; ADMA disposition stands.**
- **Vault-routed admin sub-call cross-trust-boundary.** The trust expansion from ADMIN-EOA to vault-owner (>50.1% DGVE holders) is documented at ADMA §3.05. From the zero-day lens: could a vault-owner-coalition (multi-EOA collusion at >50.1%) game the cross-routed entry points to extract beyond what individual admins can? Walking R-07..R-15 — each underlying game-entry has its own gate; the vault-routed wrapper inherits the gate. No novel coalition surface.
- **R-06 catalog-gap re-emphasized:** the `currentSlate` slot's omission from §14 is a documentation gap. The slot's mid-window mutation could redirect grants. **Already at ADMA R-06 HANDOFF — no Phase 302 elevation.**

**Notes:**

- The Governance-tier framing (FIXREC §0.5 + ADMA §0) holds: admin-key-compromise scenarios at HIGH-under-curious / MEDIUM-under-honest are NOT non-admin exploit surfaces from zero-day lens.
- No genuinely-novel cross-admin composition found.

---

## Hypothesis (viii) — Augment (iii): FUZZ harness `vm.skip` coverage gaps

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for the 17 documented skips. FINDING_CANDIDATE for 2 novel coverage gaps (cross-currency stETH yield + retry-vs-daily collision composition).

**Evidence:**

- The 17 documented vm.skip blocks correctly cite FIXREC sec + HANDOFF-NN anchors. Each is a "flip-to-assertion at v44.0" skip per `D-43N-FUZZ-VMSKIP-01`.
- **Novel coverage gap 1: stETH yield accrual mid-window.** Per ADMA §0 highlight 2/3: an admin firing `swapGameEthForStEth` mid-drain can fund Lido while the game-over distributor reads `address(this).balance`. The Lido stETH balance grows continuously via rebase. **The harness does not simulate Lido yield accrual** — the rebase happens off-protocol (Lido oracle pushes balance updates). A harness vm.warp + Lido rebase mock could exercise the surface. **GAP confirmed by `/contract-auditor` Hypothesis (viii) — corroborated.**
- **Novel coverage gap 2: retry-vs-daily collision composition (B1 below).** The Phase 296 (xiv) Tier-1 ACCEPT_AS_DOCUMENTED finding is preserved in FIXREC §102 V-182 (HANDOFF-110). The `testFuzz_RngLockDeterminism_BurnieCoinflipResolve` vm.skip at line 1209 references sec102 V-182 + Phase 296 (xiv) entropy-correlation. The harness's coverage of the retry-vs-daily collision is via the `_RetryLootboxRngDuringLock` edge-case fuzz function (line 1730). **Coverage adequate but the (xiv)-specific collision shape (where `_finalizeRngRequest:1615 isRetry shortcut` lands the daily VRF word in the lootbox slot) would benefit from an explicit fuzz function.** GAP candidate.

**Notes:**

- The 17 documented vm.skip blocks are the v44.0 flip-to-assertion register. The 2 novel coverage gaps are FUZZ-harness enhancements, not contract VIOLATIONs.
- The 2 gaps share severity LOW (FUZZ-harness coverage), tactic option-a-equivalent (add new edge-case fuzz functions).

---

## Hypothesis (ix) — Augment (iv): Cross-consumer entropy bleed

**Disposition:** SAFE_BY_STRUCTURAL_CLOSURE for most. FINDING_CANDIDATE-CONFIRMED for S-22 (cluster G EV-cap; already documented). One novel beyond-charge entry on `totalFlipReversals` (B2 below).

**Evidence:**

- S-22 cluster G — corroborates `/contract-auditor` finding. The per-index snapshot tactic-(b) closes the cross-consumer fanout. Already documented at FIXREC §43..§45.
- **Novel cross-consumer surface check: `_backfillOrphanedLootboxIndices`.** Per AdvanceModule:1806, this function fires post-VRF-callback to fill orphaned indices with `keccak256(vrfWord, i)`. The vrfWord is the FRESH post-gap VRF callback word; the orphaned-index derivation is one keccak step away. **Cross-consumer entropy correlation surface:** the orphan-index's derived word is consumed by the SAME lootbox-resolution path (`openLootBox` → reads `lootboxRngWordByIndex[orphan_idx]` = `keccak(vrfWord, orphan_idx)`). Different orphan indices get DIFFERENT derived words (per-index keccak salt). **Per-index domain separation holds. No cross-consumer collision.**
- **Novel cross-consumer surface check: `_backfillGapDays`.** Per AdvanceModule:1779, fills `rngWordByDay[gapDay]` for gap days during VRF stall. Each gap day's derived word is `keccak(vrfWord, gapDay)`. Cross-day consumers (sStonk redemption period, coinflip processCoinflipPayouts) read these derived words. **Per-day domain separation holds.** No cross-consumer collision.
- **Novel cross-consumer surface check: `totalFlipReversals` nudge integration.** Per AdvanceModule:1832, `finalWord = rawWord + nudges; totalFlipReversals = 0`. The nudge values are accumulated via player `reverseFlip` calls. Cross-consumer impact: the slot is read AT VRF callback time AND inside the advance-stack pre-lootbox branch (AdvanceModule:273 `cw += totalFlipReversals`). The slot is NOT enumerated in CATALOG §14 — this IS a catalog-hygiene gap. Writer gate verification: `reverseFlip:1929 if (rngLockedFlag) revert RngLocked();` — **structurally closed in source**. See beyond-charge (B2) — disposition is FINDING_CANDIDATE-RECLASSIFY-AS-CATALOG-GAP (documentation-class).

**Notes:**

- The `totalFlipReversals` catalog-gap is the substantive novel zero-day hunt finding. The slot is structurally protected in source; only its CATALOG enumeration is missing.

---

## Beyond-charge entries

### Beyond-charge (B1) — Phase 296 (xiv) carry-forward attestation

**Disposition:** ACCEPT_AS_DOCUMENTED (preserved from v42 P296 disposition).

**Description:** The v42 Phase 296 user-added beyond-charge hypothesis (xiv) found that `retryLootboxRng` composition can land daily-VRF-derived entropy in the mid-day lootbox slot via the `_finalizeRngRequest:1615 isRetry shortcut` branch. The disposition was Tier-1 → user-resolved as ACCEPT_AS_DOCUMENTED. At v43.0 close, this is preserved per FIXREC §102 V-182 (HANDOFF-110); the FUZZ harness includes a vm.skip-gated test for it (line 1209-1210).

**Severity:** LOW (correctness observation; bettors still receive a valid entropy word).

**Suggested remediation:** None new. The v44.0 plan-phase consumes HANDOFF-110 with the documented options: (1) documentation-only — extend the bit-allocation map comment; (2) behavioral — clear `LR_MID_DAY` at the start of `_finalizeRngRequest`'s isRetry branch. User-decision per `feedback_never_preapprove_contracts.md`.

---

### Beyond-charge (B2) — `totalFlipReversals` CATALOG GAP (slot not enumerated in §14)

**Disposition:** FINDING_CANDIDATE-RECLASSIFY-AS-CATALOG-GAP (documentation-class; writer is structurally gated in source).

**Description:** `totalFlipReversals` (declared at `DegenerusGameStorage.sol:383 uint256 internal totalFlipReversals`) is consumed inside `_applyDailyRng:1832-1838` as a deterministic nudge to the raw VRF word:
```
nudges = totalFlipReversals;
finalWord = rawWord + nudges;
totalFlipReversals = 0;
rngWordByDay[day] = finalWord;
```
The slot is ALSO read inside the lootbox-RNG path at AdvanceModule:273 (`cw += totalFlipReversals`) inside the `advanceGame` pre-lootbox branch. Both reads happen at VRF CALLBACK TIME inside the advance-stack — it's a non-VRF SLOAD consumed alongside the RNG per `feedback_rng_window_storage_read_freshness.md` (F-41-02/03 precedent class).

**Grep verification of CATALOG §14 enumeration:** `grep -n "totalFlipReversals" .planning/RNGLOCK-CATALOG.md` returns ZERO hits. **`totalFlipReversals` is NOT in CATALOG §14.** This is a CATALOG GAP.

**Writer enumeration:** The slot's sole EOA-reachable writer is `DegenerusGame.reverseFlip` at `DegenerusGame.sol:1928`. The writer body at `:1929` has `if (rngLockedFlag) revert RngLocked();` — **structurally gated against the rngLock window.** No other non-advance-stack writer exists (verified via grep of `totalFlipReversals\s*=` and `totalFlipReversals\s*\+=` across `contracts/`).

**Lens check (re-derived after gate-verification):**
- (1) Slot feeds VRF-derived output: ✓ — `totalFlipReversals` directly perturbs `finalWord` which is the day's RNG written to `rngWordByDay`.
- (2) Mutable mid-rngLock by non-EXEMPT actor: ✗ — `reverseFlip:1929` reverts on `rngLockedFlag`. **Structural close.**
- (3) Mutation profits attacker: N/A (lens condition #2 fails).

**Severity:** LOW (CATALOG-hygiene gap; slot SHOULD be enumerated as participating in §14 with VERIFICATION-ONLY status; the writer is already gated in source so no v44.0 contract change required).

**Suggested remediation:** Phase 303 §6 catalog hygiene amendment OR FIXREC-augment append: add `totalFlipReversals` as a new §14 row (e.g., S-68) with `Module: DegenerusGameStorage`; writer enumeration includes `reverseFlip` at `DegenerusGame.sol:1929` with VERIFICATION-ONLY status (gate present in-source); consumers `§5` (AdvanceModule._applyDailyRng), and the advance-stack pre-lootbox branch. The corresponding HANDOFF anchor would be VERIFICATION-ONLY class (no v44.0 contract change). Per `D-302-AUDIT-ONLY-ROUTING-01`, this routes to FIXREC-augment §N+1 entry; per the audit-only posture, no contract change at v43.

**This is the substantive zero-day hunt finding — a documentation/catalog-hygiene gap. Recommends Tier-1 user-review checkpoint to confirm routing.**

---

### Beyond-charge (B3) — DegenerusAdmin.onTokenTransfer ERC-677 surface

**Disposition:** NEGATIVE_RESULT_ONLY.

**Description:** Investigated the lone ERC-677 callback surface (`DegenerusAdmin.sol:977 onTokenTransfer`). Verified gated by `if (msg.sender != address(LINK)) revert;` — only the LINK token contract can invoke. Function manages LINK subscription auto-fund accounting on DegenerusAdmin (NOT on DegenerusGame). Does not touch §14 slots. **Negative result; no exploit surface.**

---

## Cross-cutting note

From the `/zero-day-hunter` lens, the v43.0 audit subject is comprehensively covered. The novel surfaces hunt produced:
- **Zero new CATASTROPHE / HIGH findings** beyond V-184.
- **One CATALOG-HYGIENE GAP** — `totalFlipReversals` consumed by `_applyDailyRng` is NOT enumerated in CATALOG §14, despite being a non-VRF SLOAD consumed alongside RNG at VRF-callback time. **Writer (`reverseFlip:1929`) IS structurally gated by `rngLockedFlag` in source**, so no contract change needed — only a §14 amendment. Routes to documentation-class FIXREC-augment OR Phase 303 §6 catalog hygiene.
- **One ACCEPT_AS_DOCUMENTED carry** from v42 P296 (xiv) — preserved per FIXREC §102.
- **One NEGATIVE_RESULT** on DegenerusAdmin.onTokenTransfer (LINK ERC-677 callback gated).
- **Corroboration of V-063 lens-condition #1** (the `/contract-auditor` finding that FIXREC §0.7's FALSE-POSITIVE marker is incorrect).

The novel-attack-surface hunt confirms: the protocol's defense-in-depth (rngLockedFlag + _livenessTriggered + per-module gates + per-index snapshot pattern) closes the major composition surfaces. The `totalFlipReversals` writer is the lone catalog-hygiene gap and is structurally closed in source.

---

*Phase: 302-cross-surface-adversarial-sweep-sweep*
*Skill: /zero-day-hunter (SEQUENTIAL_MAIN_CONTEXT fallback per executor invocation context; v42 P296 precedent for sequential main-context dispatch when subagent dispatch unavailable)*
*Hypothesis count: 9 charged + 3 beyond-charge*
*No contract code in output*
*No post-v43 forward-cite tokens; only D-43N-V44-HANDOFF-NN + D-43N-V44-ADMA-NN + descriptive labels*
