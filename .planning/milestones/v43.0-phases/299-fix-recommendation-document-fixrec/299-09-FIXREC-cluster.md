---
phase: 299-fix-recommendation-document-fixrec
plan: 09
cluster: I
type: fixrec-cluster
scope: "rngRequestTime governance (S-38 governance subset) + cross-contract affiliate (S-41) + cross-contract questView (S-42) + degeneretteBets[player][nonce] (S-43) + prizePoolPendingPacked frozen-branch (S-45) + lootboxRngPacked LR_MID_DAY commitment-side + governance (S-46) + VRF config wireVrf + governance (S-47, S-48, S-49) — governance-window mutation + cross-contract dependency + commitment-side + VRF-config writer family"
violations_covered: [V-137, V-140, V-141, V-142, V-147, V-149, V-153, V-155, V-156, V-157, V-158, V-159, V-160, V-161]
handoff_anchors: [D-43N-V44-HANDOFF-78, D-43N-V44-HANDOFF-79, D-43N-V44-HANDOFF-80, D-43N-V44-HANDOFF-81, D-43N-V44-HANDOFF-82, D-43N-V44-HANDOFF-83, D-43N-V44-HANDOFF-84, D-43N-V44-HANDOFF-85, D-43N-V44-HANDOFF-86, D-43N-V44-HANDOFF-87, D-43N-V44-HANDOFF-88, D-43N-V44-HANDOFF-89, D-43N-V44-HANDOFF-90, D-43N-V44-HANDOFF-91]
tactic_mix:
  rngLock_gate_a: [V-142, V-147, V-149]
  snapshot_b:     [V-140, V-141]
  reorder_c:      [V-137, V-153, V-155, V-157, V-159, V-161]
  immutable_d:    [V-156, V-158, V-160]
  reclassify:     [V-153]   # also tagged reclassify per §0 headline #6 scope-expansion candidate (subset of reorder_c)
ev_tier:
  CATASTROPHE:    [V-137, V-155, V-157, V-159, V-161]
  HIGH:           [V-142, V-147, V-149]
  MEDIUM:         [V-140, V-141]
  LOW:            [V-153, V-156, V-158, V-160]
stale_phantoms:  [V-140, V-149]
label_refinements:
  V-140: "Catalog cites DegenerusAffiliate.recordAffiliateEarnings — actual writer is payAffiliate (DegenerusAffiliate.sol:388, reached from MintModule via affiliate.payAffiliate() at :1135, :1145, :1313, :1323, :1333, :1342). Affiliate cross-contract state is mutated by payAffiliate during EOA mint flows; semantic claim of cluster row holds."
  V-149: "Catalog rationale cites Existing far-future RngLocked gate (:572) covers — :572 in current source is the LCG step inside _raritySymbolBatch trait-batch generator (no RngLocked guard). MintModule has only one rngLockedFlag read (:1221, cachedJpFlag && rngLockedFlag jackpot-phase target-level redirect) and no RngLocked revert. The substantive claim (frozen-branch pending writes during jackpot phase reach EOA-callable purchase paths) holds — the suggested mitigation must be authored from scratch, NOT framed as an extension of an existing gate."
scope_expansion_candidates: [V-153, V-137, V-155, V-157, V-159, V-161]
posture: AUDIT-ONLY (D-43N-AUDIT-ONLY-01)
---

# Phase 299 Plan 09 — FIXREC Cluster I

**Scope:** Governance-window mutation + cross-contract dependency + commitment-side + VRF-config writer family. 14 logical VIOLATIONs spanning seven sub-families:

| Sub-family | Slot | VIOLATIONs |
|---|---|---|
| rngRequestTime governance subset (S-38) | VRF stall liveness anchor | V-137 |
| Affiliate cross-contract (S-41) | affiliate-cache slots in `DegenerusAffiliate` | V-140 |
| Quest cross-contract (S-42) | quest-streak / quest-state slots in `DegenerusQuests` | V-141 |
| degeneretteBets[player][nonce] (S-43) | per-bet packed payload | V-142 |
| prizePoolPendingPacked frozen-branch (S-45) | jackpot-phase pending pool | V-147, V-149 |
| lootboxRngPacked LR_MID_DAY commitment-side + governance (S-46) | mid-day lootbox RNG flag | V-153, V-155 |
| VRF config (S-47, S-48, S-49) | vrfCoordinator / vrfSubscriptionId / vrfKeyHash | V-156..V-161 |

**Consumer reach context.** This cluster covers three categories of writer that all sit on the same `rngLockedFlag` window:

1. **Governance EOA writers** (V-137, V-155, V-157, V-159, V-161). `AdvanceModule.updateVrfCoordinatorAndSub` (`DegenerusGameAdvanceModule.sol:1675-1706`) is `if (msg.sender != ContractAddresses.ADMIN) revert E();`-gated and rewrites four VRF-state slots in one call: `vrfCoordinator` (:1685), `vrfSubscriptionId` (:1686), `vrfKeyHash` (:1687), `rngLockedFlag` (:1690), `vrfRequestId` (:1691), `rngRequestTime` (:1692), `rngWordCurrent` (:1693), and `lootboxRngPacked.LR_MID_DAY` via `_lrWrite` (:1698). The function exists as an emergency escape valve for VRF coordinator stalls. Per `D-43N-AUDIT-ONLY-01` strict 3-EXEMPT-class verdict alphabet, this clears five participating slots mid-window and is flagged VIOLATION per-slot.
2. **Cross-contract dependency writers** (V-140, V-141). `DegenerusAffiliate.payAffiliate` and `DegenerusQuests.handleMint/Flip/Decimator/Affiliate/LootBox/Purchase/Degenerette` are reached from EOA-callable purchase / flip / claim flows on the game contract and mutate state that is later SLOAD'd inside the lootbox-resolution path. Cross-contract state is in-scope per `D-298-EXEMPT-CROSSCONTRACT-01`.
3. **Commitment-side + VRF-config writers** (V-142, V-147, V-149, V-153, V-156, V-158, V-160). EOA-reachable: `placeDegeneretteBet`, `_collectBetFunds` frozen-branch, MintModule frozen-branch purchase paths, `requestLootboxRng` (a.k.a. `_requestLootboxRng`). Constructor-only Admin one-shot: `wireVrf`.

**Verification scope.** Each §N below was cross-checked against current source. Two label-refinements identified:
- **V-140** — catalog cite `DegenerusAffiliate.recordAffiliateEarnings` does not exist in current source. The actual EOA-reachable writer is `DegenerusAffiliate.payAffiliate` at `:388`, called from `MintModule._purchaseFor` / `_purchaseBurnieLootboxFor` chain at `:1135, :1145, :1313, :1323, :1333, :1342`. The cross-contract VIOLATION is real; the function-name cite is stale.
- **V-149** — catalog rationale "Existing far-future `RngLocked` gate (:572) covers" cites a line that contains no gate (`:572` is the LCG step inside `_raritySymbolBatch`). Grep confirms zero `revert RngLocked()` sites in `DegenerusGameMintModule.sol`; the only `rngLockedFlag` read is the narrow `cachedJpFlag && rngLockedFlag` last-jackpot-day redirect at `:1221`. The frozen-branch pending write at `:1054-:1059` (the actual writer surface) has no `rngLockedFlag` guard. The substantive VIOLATION holds; the framing as "extend existing gate" is incorrect — v44.0 must author a NEW guard.

**§9 scope-expansion analysis (§7.C below).** Per CATALOG §0 headline #6, `_requestLootboxRng` is the commitment-side sibling of the EXEMPT-RETRYLOOTBOXRNG envelope. The current 3-EXEMPT-stack model (`advanceGame` + `VRFcallback` + `retryLootboxRng`) was locked at `D-298-CONSUMER-LIST-01` + `D-43N-AUDIT-ONLY-01`. Phase 299 surfaces (without resolving) whether the milestone-prose may scope-expand to a 4-EXEMPT-stack model that incorporates `requestLootboxRng` (and a separately-fenced "emergency governance VRF rotation" class). The scope-expansion analysis at §7.C documents the proposal shape, preserves the audit's no-fourth-class-disposition invariant (this is a structural-classification change adding a 4th EXEMPT entry-stack identity, NOT an introduction of any case-by-case carve-out), and leaves the locked decision to Phase 303 TERMINAL §9 closure attestation.

**Discipline:** No `contracts/` or `test/` mutations. Backward-trace per `feedback_design_intent_before_deletion.md`. Verified-against-source per `feedback_verify_call_graph_against_source.md`. Frozen-contract reality per `feedback_frozen_contracts_no_future_proofing.md` — every recommendation remains advisory for v44.0 plan-phase consumption.

---

## §1 — V-137: rngRequestTime cleared inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1692)

### §1.A — Design-intent backward-trace

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

### §1.B — Actor game-theory walk

Exploit actor: an adversarial ADMIN (trust-minimization audit posture per CATALOG §0 — even Admin-only writers earn VIOLATION classification when they touch RNG-window slots and are NOT in the 3 EXEMPT entry-stacks).

Action sequence: ADMIN observes an in-flight VRF request (off-chain `requestRandomWords` was called, callback pending). ADMIN calls `updateVrfCoordinatorAndSub(newCoordinator, newSubId, newKeyHash)`. The call clears `rngLockedFlag = false` (`:1690`), zeroes `vrfRequestId` (`:1691`), zeroes `rngRequestTime` (`:1692`), and clears `lootboxRngPacked.LR_MID_DAY` (`:1698`). If the in-flight callback then arrives against the *old* coordinator, `rawFulfillRandomWords` rejects on the `msg.sender != address(vrfCoordinator)` check. If ADMIN front-ran by also redirecting the off-chain VRF coordinator endpoint to a coordinator under their control, the next `advanceGame` call fires a request that resolves against admin-controlled randomness.

The "ADMIN as adversary" frame is the standard audit posture: the user explicitly requested trust-minimization analysis, so the catalog flags this Admin-gated writer as VIOLATION despite the gating.

**EV magnitude:** CATASTROPHE-tier. This writer single-handedly clears five RNG-window state slots and authorizes a substitute VRF coordinator. The compromised admin path resolves to control over every downstream RNG consumer for the resulting cycle. EV is bounded only by the strength of the ADMIN key custody. Economic-likelihood: LOW (governance discipline, multi-sig, public on-chain visibility), but disposition: MITIGATE structurally regardless.

### §1.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder: queue mid-stall rotations until after callback or 12h timeout.**

Concrete shape: split `updateVrfCoordinatorAndSub` into two phases:
1. `queueVrfCoordinatorRotation(newCoordinator, newSubId, newKeyHash)` — writes a pending-rotation packed slot only; emits `VrfCoordinatorRotationQueued`.
2. `applyVrfCoordinatorRotation()` — permissionless after `block.timestamp >= rngRequestTime + MIDDAY_RNG_RETRY_TIMEOUT + ROTATION_DELAY` OR after `vrfRequestId == 0 && !rngLockedFlag`. Atomically performs the four-slot write currently at `:1685-:1698`.

The 12h-timeout-equivalent (`MIDDAY_RNG_RETRY_TIMEOUT` is the natural anchor; a longer `ROTATION_DELAY` is recommended) ensures rotation cannot pre-empt an in-flight callback that could still resolve naturally. The retry path (`retryLootboxRng:1132`) becomes the first-line response to a stalled callback; rotation is reserved for genuine multi-cycle stalls where retry is also exhausted.

**Rationale.** Tactic (c) preserves the legitimate emergency-escape semantics — ADMIN retains the rotation capability — but eliminates the mid-window pre-emption attack. The cooldown is a natural extension of the existing `retryLootboxRng` cooldown precedent.

**Bytecode impact.** ~150-250 bytes — one packed `pendingRotation` storage slot (3 fields: coordinator, subId, keyHash; fits in 2 slots since `address + uint64 + bytes32` = 20 + 8 + 32 = 60 bytes spanning 2 slots) + the two-function split + the timeout/state-condition check. Storage-layout: 1-2 new packed slots appended to end of `DegenerusGameStorage` (non-disrupting). ABI: BREAKING — `updateVrfCoordinatorAndSub` is replaced by `queueVrfCoordinatorRotation` + `applyVrfCoordinatorRotation`. Admin tooling needs update; the user-facing semantic is preserved.

### §1.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-78` — CATALOG §16 row V-137 + §15 row S-38 governance subset. v44.0 plan-phase: define `pendingVrfRotationPacked` packed slot; split `updateVrfCoordinatorAndSub` into queue + apply; gate apply on `vrfRequestId == 0 || (block.timestamp >= rngRequestTime + ROTATION_DELAY)`.

---

## §2 — V-140: affiliate cross-contract slots mutated inside `DegenerusAffiliate.payAffiliate` (DegenerusAffiliate.sol:388) — **LABEL-REFINEMENT**

### §2.A — Design-intent backward-trace and label-refinement

**Label refinement.** CATALOG §15 row S-41 + §16 row V-140 cite `DegenerusAffiliate.recordAffiliateEarnings` as the cross-contract writer. Grep of current `contracts/DegenerusAffiliate.sol` returns zero hits for that name. The actual EOA-reachable writer that mutates the affiliate-cache slots consumed by the lootbox resolution is `DegenerusAffiliate.payAffiliate` (`:388`, signature `function payAffiliate(uint256 amount, bytes32 code, address sender, uint24 lvl, bool isFreshEth, uint16 lootboxActivityScore) external returns (uint256 playerKickback)`), called from `MintModule._purchaseFor` and `_purchaseBurnieLootboxFor` at `:1135, :1145, :1313, :1323, :1333, :1342` via `lootboxFlipCredit += affiliate.payAffiliate(...)` / `kickback += affiliate.payAffiliate(...)`. The semantic claim of the cluster row — "affiliate cross-contract state is mutated by EOA mint flows during the rngLock window" — holds.

`DegenerusAffiliate` is an external standalone contract (not a delegatecall module) that maintains the global affiliate-tracking ledger. `payAffiliate` mutates `affiliateCode`, `playerReferralCode`, `affiliateScore[lvl][player]`, `totalAffiliateScore[lvl]`, and the cached affiliate points read back into `mintPacked_.AFF_POINTS` via `MintStreakUtils._cacheAffiliateBonus`. Consumers (per CATALOG §7) read these slots inside `_resolveLootboxCommon` via the affiliate-points contribution to `_playerActivityScore` and via the lootbox boon/cap derivations.

**Why the slot family exists.** Affiliate scoring is a cross-game-cycle accumulator: a referrer's score must update on every referee mint. Naively gating `payAffiliate` on the game's `rngLockedFlag` would either (a) revert the mint flow entirely or (b) silently drop the affiliate credit, breaking the affiliate-economics monotonicity invariant.

**Phase-precedent.** Phase 281 owed-salt (`v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md`) established the snapshot-at-allocation pattern for any value participating in a post-VRF-callback resolution. Phase 288 dailyIdx structural anchor extended this to cross-day-mutating slots.

### §2.B — Actor game-theory walk

Exploit actor: an EOA buyer holding a pre-VRF-allocated lootbox index. Between the daily VRF callback (`AdvanceModule.sol:1256 lootboxRngWordByIndex[index] = rngWord`) and the same buyer's subsequent `openLootBox(index)`, the buyer (or their referrer / referee chain) calls `buyTickets` with a referral code. `MintModule` calls `affiliate.payAffiliate`, which (i) records the affiliate score, (ii) returns kickback ETH, and (iii) updates the `mintPacked_.AFF_POINTS` cache via the AdvanceModule `_cacheAffiliateBonus` path (`AdvanceModule:1008`). The buyer's post-callback `openLootBox` then reads the fresh `AFF_POINTS` (via `_playerActivityScore`) and possibly fresh affiliate-derived caps, inflating the resolved lootbox payout.

**EV magnitude:** MEDIUM. The affiliate-points contribution to `_playerActivityScore` is one of multiple inputs (mint-streak, deity-pass, whale-bundle), and the per-cycle marginal points from a single mint are bounded. However, a referrer with a large stable of referees can have those referees mint during the buyer's rng-window, amplifying the score. Per `feedback_rng_window_storage_read_freshness.md` precedent F-41-02/03, any non-VRF SLOAD consumed alongside the RNG word is in-scope; this falls within that class.

### §2.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot affiliate points into the lootbox-index at allocation.**

Concrete shape: at lootbox-allocation time (`MintModule._allocateLootbox` / `WhaleModule._whaleLootboxAllocate`), capture `affiliateBonusPointsBest(currLevel, buyer)` into the per-index snapshot slot `lootboxEvScorePacked[index][player]` (already a per-index snapshot per CATALOG §14 row S-22 and Cluster H §3.C consolidation). The lootbox-resolution body reads the snapshotted score; live `affiliate.affiliateBonusPointsBest()` calls inside `_resolveLootboxCommon` are removed.

This is the same widening recommended in Cluster H §3.C (V-109 mint-streak snapshot) — the AFF_POINTS field is already covered when the activity-score snapshot is widened to cover the full `_playerActivityScore` input set. **Cross-cluster coupling: V-140 + V-109 + V-110 + V-112 + V-113 resolve via a single `lootboxEvScorePacked` widening v44.0 sub-phase.**

**Rationale.** Phase 281 + Phase 288 snapshot-at-allocation precedent. The cross-contract write retains its legitimate cross-cycle role; only the lootbox-EV consumer reads from the frozen per-index snapshot. No structural change to `DegenerusAffiliate` required.

**Bytecode impact.** ~50-100 bytes per consumer site — one storage-load swap inside `_resolveLootboxCommon` (read from `lootboxEvScorePacked[index][player]` instead of live `affiliate.*`). Storage-layout: no new slots if widening Cluster H's existing snapshot field. ABI: NON-BREAKING.

### §2.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-79` — CATALOG §16 row V-140 + §15 row S-41 + Cluster H §3.C consolidation note. v44.0 plan-phase: route `_lootboxEvMultiplierBps` and affiliate-derived caps to read from `lootboxEvScorePacked[index][player]`; remove live `affiliate.*` reads from `_resolveLootboxCommon`.

---

## §3 — V-141: questView cross-contract slots mutated via `DegenerusQuests` external fulfillment writers (DegenerusQuests.sol handleMint/Flip/Decimator/Affiliate/LootBox/Purchase/Degenerette)

### §3.A — Design-intent backward-trace

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

### §3.B — Actor game-theory walk

Exploit actor: an EOA player holding a pre-VRF-allocated lootbox index. Between the daily VRF callback and their `openLootBox(index)`, the player completes a quest action (flip / mint / claim) that triggers a `Quests.handle*` call, advancing `state.streak` and `state.questsProgress`. The subsequent `_resolveLootboxCommon` read of `_playerActivityScore` (or the direct `questView.playerQuestStates` read inside DegeneretteModule's resolution path) consumes the advanced streak, inflating `evMultiplierBps`.

**EV magnitude:** MEDIUM. Quest-streak is a bounded contribution to activity-score (capped at the streak-bonus formula in `MintStreakUtils._playerActivityScore`). The exploit requires the player to actually complete a quest action mid-window — non-trivial but not gated. Per `feedback_rng_window_storage_read_freshness.md`, this is in the storage-read-freshness bug class.

### §3.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot questStreak into the lootbox-index at allocation.**

Concrete shape: at lootbox-allocation time, fetch `(uint32 questStreak, ...) = questView.playerQuestStates(player)` and pack into `lootboxEvScorePacked[index][player]` (alongside the V-109/V-140 widening). The lootbox-resolution body reads the snapshotted streak.

Note: `_placeDegeneretteBetCore` (`DegeneretteModule.sol:457`) **already snapshots questStreak into `activityScore` at bet-place time** and packs it into the per-bet payload at `:469`. The Degenerette consumer is therefore already free of this specific exploit vector for the bet-payload path; V-141 covers the OTHER consumer (lootbox-resolution path) where the read is still live.

**Rationale.** Phase 281 + Phase 288 + Phase 292 + Phase 294 snapshot precedent. Coupled with V-109 / V-110 / V-112 / V-113 / V-140 into the single `lootboxEvScorePacked` widening v44.0 sub-phase.

**Bytecode impact.** ~50-100 bytes — one cross-contract view-call swap (`questView.playerQuestStates`) into the allocation-time path, and removal of the live read inside `_resolveLootboxCommon`. Storage-layout: no new slots if widening Cluster H's existing snapshot field. ABI: NON-BREAKING.

### §3.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-80` — CATALOG §16 row V-141 + §15 row S-42 + Cluster H §3.C consolidation note. v44.0 plan-phase: extend `_allocateLootbox` to snapshot questStreak; route `_resolveLootboxCommon` to read from snapshot.

---

## §4 — V-142: degeneretteBets[player][nonce] write inside `_placeDegeneretteBetCore` (DegeneretteModule.sol:479)

### §4.A — Design-intent backward-trace

`degeneretteBets[player][nonce]` is a `mapping(address => mapping(uint64 => uint256)) internal` per-bet packed payload slot (CATALOG §14 row S-43). It is written at `DegeneretteModule.sol:479` during `_placeDegeneretteBetCore` and deleted at `:597` during `_resolveBet` (the VRF-callback / consumer-self path; V-143 EXEMPT-VRFCALLBACK).

The per-bet lifecycle is:
1. Player calls `placeDegeneretteBet` (`:367`) → `_placeDegeneretteBet` → `_placeDegeneretteBetCore` (`:430+`).
2. `_placeDegeneretteBetCore:450-452` reads `index = LR_INDEX` and asserts `lootboxRngWordByIndex[index] != 0` is FALSE (i.e., the current bucket has NOT yet been resolved — `revert RngNotReady()` if it has).
3. The bet payload (currency, ticket count, custom traits, hero quadrant, activity-score, **index**) is packed and stored at `degeneretteBets[player][++nonce]` (`:473-479`).
4. Resolution: `resolveDegeneretteBet(nonce)` pulls the payload, reads `lootboxRngWordByIndex[index]` (now non-zero post-callback), derives the bet outcome, and deletes the payload (`:597`).

**Why the slot exists.** The bet is committed BEFORE the per-day VRF word is known (the `:452` gate enforces this), so the index field in the packed payload binds the bet to the not-yet-resolved bucket. After the VRF callback writes the word at that index, resolution becomes deterministic.

**Why the :452 gate covers most of the rngLock window.** The gate refuses placement when `lootboxRngWordByIndex[index] != 0`. Inside the rngLock window (after `_requestRng` and before `rawFulfillRandomWords`), `lootboxRngWordByIndex[index]` is still zero (the callback hasn't written it), so the gate does NOT refuse placement. However, `LR_INDEX` is advanced at `_finalizeRngRequest` (`AdvanceModule:1620`) ahead of the VRF request — meaning the bet, if placed mid-window, binds to a future-bucket index whose word will arrive shortly. This is the design.

**Phase-precedent.** The :452 `RngNotReady()` revert was introduced as the per-bet-commitment gate. The "post-RNG case" the catalog references is the window between the callback writing `lootboxRngWordByIndex[index] = word` and the player's `resolveDegeneretteBet(nonce)` — at that point the gate prevents placement against the already-resolved bucket, forcing the bet onto the next (still-zero) bucket.

### §4.B — Actor game-theory walk

Exploit actor: an EOA player firing `placeDegeneretteBet` during the small window between `_finalizeRngRequest` (which advances `LR_INDEX`) and `rawFulfillRandomWords` (which writes `lootboxRngWordByIndex[newIndex]`). The bet payload binds to the new bucket. If the player can also observe / influence the callback timing (e.g., via VRF coordinator-level visibility — unrealistic for Chainlink VRF), they could place bets selectively. Realistically: the player cannot predict the word, so the bet is placed under the same per-bucket pre-commitment discipline as a normal bet.

**Edge case the catalog flags:** index-rollover. If `_finalizeRngRequest` advances LR_INDEX while a player has a same-block in-flight `placeDegeneretteBet`, the bet could bind to either the old (just-finalized) bucket or the new one, depending on tx ordering. The `:452` gate refuses placement on the resolved bucket (`lootboxRngWordByIndex[oldIndex] != 0` after the callback fires), forcing onto the new bucket. Cross-block ordering is determined by miner / sequencer and the player's gas pricing. EV magnitude: HIGH for the index-rollover edge if a player can selectively bind to a bucket whose word they have partial visibility into.

**Substantive risk:** The gate at `:452` correctly enforces per-bucket commitment for the standard case. The edge cases for verification are:
1. Same-block sequencing of `placeDegeneretteBet` with `_finalizeRngRequest` (index advance) — verify the gate behavior under fork-replay.
2. Multi-bet placement straddling a finalization — verify each bet's `index` field correctly reflects the post-finalization index.
3. Gap-day backfill (`_backfillOrphanedLootboxIndices:1818`) — verify the gate behaves correctly when multiple historical indices are filled in one advanceGame call.

### §4.C — Recommended tactic + rationale + impact

**Tactic (a) — Existing :452 `lootboxRngWordByIndex[index] != 0` gate; verify across index-rollover edges via FUZZ-301.**

Concrete shape: NO CONTRACT CHANGE required. The existing gate at `:452` is the correct structural mitigation. Phase 301 FUZZ adds test cases:
- `vm.skip`-gated at the CATALOG-VIOLATION site per `D-43N-FUZZ-VMSKIP-01` — runs the bet-place across the rngLock window and asserts payload `index` field matches the expected bucket at every callback ordering.
- Cross-cycle: place bet → advance → resolve at correct index.
- Same-block: place bet at the exact block of `_finalizeRngRequest` (uses `vm.warp` + `vm.roll` boundary).
- Backfill: place bet → trigger `_backfillOrphanedLootboxIndices` for a prior gap day → assert no cross-contamination.

**Rationale.** Tactic (a) here is the LIGHTEST tactic in the menu — the gate already exists. The VIOLATION is reclassified as "gate-present, edge-case-FUZZ-verification-required". This aligns with the audit-only posture: no contract change needed if FUZZ proves the gate covers all edges.

**Bytecode impact.** Zero (no contract change). Test-suite impact: ~3-5 new FUZZ cases. ABI: NON-BREAKING (no change).

### §4.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-81` — CATALOG §16 row V-142 + §15 row S-43 + Phase 301 FUZZ-301-DEGENERETTE-EDGE coupling. v44.0 plan-phase: NO sub-phase required if Phase 301 FUZZ confirms gate coverage; CONDITIONAL handoff (re-attest only if FUZZ-301 surfaces a gate-bypass).

---

## §5 — V-147: prizePoolPendingPacked write inside `_collectBetFunds` frozen-branch (DegeneretteModule.sol:553)

### §5.A — Design-intent backward-trace

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

### §5.B — Actor game-theory walk

Exploit actor: EOA player firing `placeDegeneretteBet` during jackpot-phase's rngLock window. The `_collectBetFunds` write inflates `prizePoolPendingPacked.pFuture`. Subsequent reads of pending pools by the same player's bet-resolution (or by another player's bet-resolution within the same window) read the inflated pending value.

Consumer surface affected: `_distributePayout:760-764` reads pending pools via `_getPendingPools` to determine ethShare → payout magnitude inside `_distributePayout`. If the player can place a bet that inflates pending, then resolve a separate same-window bet that pays from pending, the inflated pool magnifies the payout.

**EV magnitude:** HIGH. The pending pool participates directly in payout-magnitude derivation during jackpot-phase. The exploit window is narrow (limited to jackpot-phase + same VRF cycle), but the per-bet payout uplift is non-trivial.

### §5.C — Recommended tactic + rationale + impact

**Tactic (a) — Gate place-bet on `rngLockedFlag` so window closes once VRF requested.**

Concrete shape: at the entry to `_placeDegeneretteBetCore` (before the existing `:450-452` index/RngNotReady checks), add `if (rngLockedFlag) revert RngLocked();`. This closes the placement window cleanly for the entire VRF cycle. The existing `:452 RngNotReady()` revert remains as the per-bucket commitment gate; the new `rngLockedFlag` revert covers the broader "RNG is currently being resolved" window.

Alternative refinement (narrower): gate only when `prizePoolFrozen && rngLockedFlag` to preserve placement during daily-rng-lock for non-jackpot-phase days. The catalog rationale ("Gate place-bet on `rngLockedFlag` so window closes once VRF requested") matches the broader gate; the narrower gate trades UX for tighter coverage.

**Rationale.** The `rngLockedFlag` is the canonical "VRF cycle is active" signal across the codebase (`BurnieCoinflip:730, :780; WhaleModule:543; AdvanceModule:1044; DegenerusGame:1513, :1528, :1575`). Adding the same gate to the Degenerette bet-place entry brings the surface to parity. The existing `:452 RngNotReady()` is a per-bucket gate; `rngLockedFlag` is a per-cycle gate — both are needed for coverage.

**Bytecode impact.** ~30-50 bytes — one storage read + revert at the bet-place entry. Storage-layout: no change. ABI: NON-BREAKING (additional revert surface; existing happy path preserved for non-locked state).

### §5.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-82` — CATALOG §16 row V-147 + §15 row S-45 frozen-branch. v44.0 plan-phase: add `if (rngLockedFlag) revert RngLocked();` at top of `_placeDegeneretteBetCore`; consider narrower `prizePoolFrozen && rngLockedFlag` form per UX tradeoff.

---

## §6 — V-149: prizePoolPendingPacked write inside MintModule frozen-branch purchase writers (MintModule.sol:1054-1059) — **LABEL-REFINEMENT**

### §6.A — Design-intent backward-trace and label-refinement

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

### §6.B — Actor game-theory walk

Exploit actor: EOA buyer firing `purchase` / `purchaseCoin` / `purchaseBurnieLootbox` during the jackpot-phase rngLock window. The frozen-branch write at `:1054-1059` inflates `prizePoolPendingPacked` (pNext + nextShare; pFuture + futureShare). Subsequent same-window consumer reads of pending pools (Degenerette `_distributePayout:760-764`, future-phase unfreezing) consume the inflated pool.

The exploit shape mirrors V-147 but at the MintModule purchase entry instead of the bet-place entry. The pool inflation is bounded by the buyer's purchase size, but a large enough purchase can materially shift the pending magnitudes consumed by other players' same-window bet resolutions.

**EV magnitude:** HIGH. Same as V-147 — pending pool magnitude directly modulates downstream payout calculations.

### §6.C — Recommended tactic + rationale + impact

**Tactic (a) — Author a NEW `rngLockedFlag` gate on the frozen-branch purchase entries.**

Concrete shape: at the entry to `_purchaseFor` (`MintModule.sol:899-906`), after the existing `_livenessTriggered()` check, add:

```solidity
if (prizePoolFrozen && rngLockedFlag) revert RngLocked();
```

This narrowly closes the jackpot-phase-RNG-lock window without affecting daily-mint UX outside the jackpot phase. The narrower form (vs blanket `if (rngLockedFlag) revert`) preserves daily-rng-lock-window purchases for non-jackpot-phase days, matching the V-147 §5.C narrower-form discussion.

Alternative (broader): gate all `_purchaseFor` entries on `rngLockedFlag` regardless of `prizePoolFrozen`. Trades UX for tighter coverage of OTHER same-window RNG-window concerns (the cross-cluster activity-score / streak / boon writers — Cluster H V-114 etc.). v44.0 plan-phase decides the form based on UX tradeoff.

**Rationale.** No existing gate exists; this is a NEW guard. The pattern mirrors the codebase's established `if (rngLockedFlag) revert RngLocked();` discipline at `BurnieCoinflip:730, :780; WhaleModule:543; AdvanceModule:1044; DegenerusGame:1513, :1528, :1575`. Coupled with V-147 — both VIOLATIONs cover the same `prizePoolPendingPacked` slot from different EOA-entry surfaces.

**Bytecode impact.** ~30-50 bytes — one storage read + revert at `_purchaseFor` top. Storage-layout: no change. ABI: NON-BREAKING (added revert surface).

### §6.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-83` — CATALOG §16 row V-149 + §15 row S-45 MintModule frozen-branch + label-refinement note. v44.0 plan-phase: AUTHOR new `prizePoolFrozen && rngLockedFlag` revert at `_purchaseFor` top (do NOT frame as extending the non-existent :572 gate).

---

## §7 — V-153: lootboxRngPacked.LR_MID_DAY write inside `_requestLootboxRng` (AdvanceModule.sol:1096) — **§0 HEADLINE #6 SCOPE-EXPANSION CANDIDATE**

### §7.A — Design-intent backward-trace

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

### §7.B — Actor game-theory walk

Exploit actor: **none with a profit-motive vector**. The catalog row V-153 is the textbook example of "strict-per-callsite classification yields VIOLATION but substantive risk is nil". Walk:

1. Hypothetical exploit-actor = an EOA calling `requestLootboxRng()` during the rng-lock window. But `_requestLootboxRng` has its own `if (rngLockedFlag) revert E();` gate (verify at `:1044` of `AdvanceModule.sol` — confirmed present: `if (rngLockedFlag) revert RngLocked();`). So the function CANNOT execute during `rngLockedFlag == true`. The mid-day RNG runs DURING `rngLockedFlag == false` (the gap between daily VRF cycles).
2. Hypothetical: an EOA calls `requestLootboxRng()` mid-day, sets `LR_MID_DAY = 1`, then in the same window calls `openLootBox` (or any other consumer). But the consumer reads `lootboxRngWordByIndex[index]` which is still zero until the VRF callback fires — `RngNotReady()` revert across the board.
3. Hypothetical: an EOA front-runs another player's bet-resolution to inflate `LR_INDEX` (advanced at `:1113-1117`). This is real but covered by the existing per-bucket commitment gate at `DegeneretteModule:452` + the per-index snapshot discipline. NOT a `LR_MID_DAY`-specific exploit.

**Substantive risk: NIL.** Per CATALOG §0 headline #6 verbatim: "substantive risk is nil (the retryLootboxRng caller benefits from both writes existing)".

**EV magnitude:** LOW (technically: zero, but tagged LOW per the no-zero-EV-without-FUZZ-attestation discipline).

### §7.C — Recommended tactic + rationale + impact — **SCOPE-EXPANSION ANALYSIS**

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

### §7.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-84` — CATALOG §16 row V-153 + §15 row S-46 LR_MID_DAY commitment-side + CATALOG §0 headline #6 + this §7.C scope-expansion analysis. **Disposition: RESOLVED-AS-RECLASSIFIED** at Phase 303 TERMINAL §9 closure attestation; v44.0 plan-phase has NO sub-phase obligation. Conditional re-activation only if Phase 303 declines the reclassification.

---

## §8 — V-155: lootboxRngPacked.LR_MID_DAY cleared inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1698)

### §8.A — Design-intent backward-trace

`updateVrfCoordinatorAndSub` (`AdvanceModule.sol:1675-1706`) clears `LR_MID_DAY` via `_lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0)` at `:1698`. The clear is annotated in source (`:1695-1697`): "Clear mid-day lootbox RNG pending flag to prevent post-swap deadlock. Without this, advanceGame can revert with NotTimeYet if a mid-day requestLootboxRng was in-flight when the coordinator stalled."

The writer participates in the same governance-emergency-escape pattern as V-137: when ADMIN rotates the coordinator, any in-flight `LR_MID_DAY = 1` state would prevent the next advanceGame cycle from proceeding (because `advanceGame` calls `rngGate` which expects `LR_MID_DAY` clearing to happen via the normal post-callback path — when the coordinator is rotated, the callback never arrives via the old coordinator). The clear is structurally necessary for the escape valve to function.

**Why naive gating breaks the escape valve.** Same as V-137 §1.A — `if (rngLockedFlag) revert` here would prevent the rotation precisely when needed.

**Phase-precedent.** Same as V-137 — Phase 287 JPSURF + Phase 296 SWEEP. No prior phase introduced this specific clear; it's part of the emergency-escape function.

### §8.B — Actor game-theory walk

Exploit actor: adversarial ADMIN (same posture as V-137 §1.B). Action sequence: rotate VRF coordinator → all five state slots cleared in one call (V-137 + V-155 + V-157 + V-159 + V-161 all participate). The `LR_MID_DAY` clear specifically enables the next mid-day RNG cycle to fire fresh against the new coordinator.

**EV magnitude:** CATASTROPHE-tier (couples with V-137's CATASTROPHE-tier framing — they're the same call). Per-row attribution: V-155 alone is bounded LOW — clearing `LR_MID_DAY` without the coordinator rotation has no exploit payoff. The CATASTROPHE-tier emerges from the COMPOSITE call where all five slots are cleared atomically. Per CATALOG strict-per-callsite, each is flagged separately; the per-row tier here is CATASTROPHE because of compositional EV.

### §8.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder: queue rotations until callback delivers or 12h timeout.**

Same shape as V-137 §1.C — split `updateVrfCoordinatorAndSub` into `queueVrfCoordinatorRotation` + `applyVrfCoordinatorRotation` with cooldown. The `applyVrfCoordinatorRotation` performs all five clears (vrfCoordinator, vrfSubscriptionId, vrfKeyHash, rngLockedFlag, vrfRequestId, rngRequestTime, rngWordCurrent, LR_MID_DAY) atomically; the queue gates the apply.

**Cross-VIOLATION coupling.** V-137 + V-155 + V-157 + V-159 + V-161 resolve via a SINGLE v44.0 sub-phase that splits `updateVrfCoordinatorAndSub` into queue + apply. All five handoff anchors (`H-78, H-85, H-87, H-89, H-91`) consolidate into one v44.0 work-item.

**Rationale.** Same as V-137. The reorder preserves the emergency-escape function while eliminating the mid-window pre-emption attack.

**Bytecode impact.** Shared with V-137 — already counted there (~150-250 bytes for the queue+apply split + pending slot). Storage-layout: shared. ABI: BREAKING shared with V-137.

### §8.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-85` — CATALOG §16 row V-155 + §15 row S-46 LR_MID_DAY governance subset + V-137 consolidation note. v44.0 plan-phase: CONSOLIDATED with V-137 / V-157 / V-159 / V-161 into one `updateVrfCoordinatorAndSub` queue+apply split sub-phase.

---

## §9 — V-156: vrfCoordinator write inside `wireVrf` (AdvanceModule.sol:506)

### §9.A — Design-intent backward-trace

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

### §9.B — Actor game-theory walk

Exploit actor: post-deploy ADMIN re-calling `wireVrf` mid-game. The function has NO one-shot lock — only the `msg.sender != ADMIN` check. ADMIN could re-call `wireVrf(newCoordinator, newSubId, newKeyHash)` and clobber the VRF state.

**Important distinction from V-157:** `wireVrf` does NOT clear `rngLockedFlag` / `vrfRequestId` / `rngRequestTime` / `LR_MID_DAY` — it only writes the three VRF-config fields. So a re-call mid-cycle would leave an in-flight request bound to the OLD coordinator (rejected by `rawFulfillRandomWords:1749 msg.sender check`) while the new coordinator is wired. This is a structural foot-gun: ADMIN could deadlock the contract by accident.

`updateVrfCoordinatorAndSub` is the CORRECT path for runtime rotation — it clears the in-flight state. `wireVrf` is the deploy-only path. The audit's concern: nothing prevents ADMIN from using the wrong one.

**EV magnitude:** LOW. The exploit requires ADMIN action AND is the wrong-tool-for-the-job rather than a profit-motive attack. The economic-likelihood is bounded by ADMIN discipline. Per the trust-minimization audit posture, still VIOLATION-classified, but tier LOW.

### §9.C — Recommended tactic + rationale + impact

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

### §9.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-86` — CATALOG §16 row V-156 + §15 row S-47 wireVrf. v44.0 plan-phase: pick Option (d.1) or (d.2); preference (d.2) for lighter touch (one-shot lock without storage-layout migration).

---

## §10 — V-157: vrfCoordinator write inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1685)

### §10.A — Design-intent backward-trace

`vrfCoordinator` is written inside the governance rotation function `updateVrfCoordinatorAndSub` at `:1685`. The full function context is documented in §1.A (V-137) — the same call writes all four VRF-state slots (`vrfCoordinator`, `vrfSubscriptionId`, `vrfKeyHash`) plus five lifecycle slots (`rngLockedFlag`, `vrfRequestId`, `rngRequestTime`, `rngWordCurrent`, `LR_MID_DAY`) in one transaction.

The writer exists to support the VRF coordinator-stall escape: when Chainlink VRF coordinator becomes unresponsive (network upgrade, subscription depletion, key-hash deprecation), ADMIN rotates to a new coordinator + subscription + key-hash atomically.

**Why naive gating breaks the escape.** Same as V-137 §1.A — the function exists to ESCAPE rngLock; gating on `rngLockedFlag` reintroduces the deadlock.

**Phase-precedent.** Same as V-137 — predates the audit. No prior phase formalized the rotation pathway; the function exists from contract genesis as the emergency lever.

### §10.B — Actor game-theory walk

Exploit actor: adversarial ADMIN (same as V-137 §1.B). Action sequence: rotate to admin-controlled coordinator → next `advanceGame` fires request to controlled coordinator → controlled coordinator returns chosen random word → game state resolved against admin-chosen randomness.

**EV magnitude:** CATASTROPHE-tier. Same composition as V-137 — the rotation grants the rotator effective control over downstream RNG.

### §10.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder: governance rotation queued past in-flight VRF.**

Same shape as V-137 §1.C and V-155 §8.C — split `updateVrfCoordinatorAndSub` into `queueVrfCoordinatorRotation` + `applyVrfCoordinatorRotation`. The `queue` phase only stores the proposed values; the `apply` phase atomically writes all eight slots (vrfCoordinator + vrfSubId + vrfKeyHash + the five lifecycle clears) after the cooldown is satisfied.

**Cross-VIOLATION coupling.** V-137 + V-155 + V-157 + V-159 + V-161 share a single v44.0 sub-phase. The reorder applies once and resolves all five.

**Rationale.** Tactic (c) preserves the emergency-escape semantics while inserting a time-locked review window for the rotation. The cooldown is anchored on `rngRequestTime + ROTATION_DELAY` or `vrfRequestId == 0` — i.e., apply when the in-flight request has resolved naturally or has been retried via the EXEMPT-RETRYLOOTBOXRNG path.

**Bytecode impact.** Shared with V-137 (already counted). ABI: BREAKING shared.

### §10.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-87` — CATALOG §16 row V-157 + §15 row S-47 governance subset + V-137 consolidation. v44.0 plan-phase: CONSOLIDATED with V-137 / V-155 / V-159 / V-161 into the `updateVrfCoordinatorAndSub` queue+apply split.

---

## §11 — V-158: vrfSubscriptionId write inside `wireVrf` (AdvanceModule.sol:507)

### §11.A — Design-intent backward-trace

`vrfSubscriptionId` is a `uint64 internal` slot (CATALOG §14 row S-48). It holds the Chainlink VRF subscription ID against which `requestRandomWords` is billed.

Writers:
- `wireVrf` at `AdvanceModule.sol:507`. **THIS row — V-158.**
- `updateVrfCoordinatorAndSub` at `AdvanceModule.sol:1686`. V-159 (§12).

Structurally identical to V-156 (`vrfCoordinator` / `wireVrf`) — the same one-shot deploy-time bridge writes all three VRF-config slots together at `:506-:508`. The `:507` write is the subscription-ID component of the bundle.

**Why the slot exists.** The subscription ID is required at every `requestRandomWords` call (`:1104, :1144`). It must be storable post-deploy because the constructor cannot accept it (delegatecall module sequencing constraint).

**Why naive gating breaks deployment.** Same as V-156 §9.A.

**Phase-precedent.** Same as V-156 — predates the audit. The three VRF-config slots have always been written together by `wireVrf`.

### §11.B — Actor game-theory walk

Exploit actor: post-deploy ADMIN re-calling `wireVrf`. The same foot-gun as V-156 §9.B — re-call writes the three config fields without clearing the in-flight state slots. Mid-cycle re-call could leave an in-flight request bound to the OLD subscription while the new sub is wired.

**EV magnitude:** LOW (same as V-156). The exploit is ADMIN-dependent and wrong-tool-for-the-job rather than profit-motivated.

### §11.C — Recommended tactic + rationale + impact

**Tactic (d) — Immutable.**

Concrete shape: structurally identical to V-156 §9.C. Two options:

**Option (d.1):** Move `vrfSubscriptionId` to `immutable` storage, constructor-bound. Same trade-off as V-156 — requires confirming storage-layout safety AND removing the runtime mutation path. But `updateVrfCoordinatorAndSub` mutates this slot, so `immutable` is incompatible with the runtime rotation path.

**Option (d.2):** One-shot lock on `wireVrf` (the same `bool wired` flag covers all three VRF-config slots since they're written together). The lock is added ONCE at `wireVrf` entry, not per-slot.

**Coupling with V-156 + V-160.** Options (d.1) and (d.2) BOTH cover V-156 + V-158 + V-160 in a single v44.0 sub-phase. The three handoff anchors (`H-86, H-88, H-90`) consolidate.

**Bytecode impact.** Already counted with V-156 (~50 bytes for the one-shot lock OR ~-100 bytes for the immutable migration). No additional bytecode per-slot.

### §11.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-88` — CATALOG §16 row V-158 + §15 row S-48 wireVrf + V-156 consolidation. v44.0 plan-phase: CONSOLIDATED with V-156 / V-160 into the `wireVrf` one-shot lock (Option d.2) sub-phase.

---

## §12 — V-159: vrfSubscriptionId write inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1686)

### §12.A — Design-intent backward-trace

`vrfSubscriptionId` is written at `:1686` inside `updateVrfCoordinatorAndSub`. The function context is documented in §1.A and §10.A. The subscription-ID write is the second of three VRF-config rewrites (the others at `:1685` vrfCoordinator V-157 and `:1687` vrfKeyHash V-161).

**Why the slot is written here.** The rotation event allows ADMIN to redirect billing to a new subscription. Some operational scenarios:
- Subscription `X` is depleted of LINK; ADMIN moves to subscription `Y` with fresh balance.
- Coordinator upgrade (Chainlink v2 → v2.5 migration) bundles a new coordinator address with a new subscription pool.

**Why naive gating breaks the escape.** Same as V-137 / V-155 / V-157 §1.A — the rotation needs to happen precisely when the in-flight request has stalled.

**Phase-precedent.** Same as V-137.

### §12.B — Actor game-theory walk

Exploit actor: adversarial ADMIN. Action: rotate subscription to one ADMIN controls (or to an attacker-controlled subscription on the same coordinator). The subscription receives the billing for the next `requestRandomWords`. If the attacker depletes the subscription before the callback, the request reverts at the coordinator side, stalling the game. Conversely, if the attacker funds the new subscription, the call proceeds — but the random word is still produced by the (correctly-honest) Chainlink VRF, so the exploit value is limited UNLESS combined with V-157 (coordinator swap).

**EV magnitude:** CATASTROPHE-tier in composition (with V-137 / V-155 / V-157 / V-161 — they're the same atomic call). Per-row attribution: LOW for an isolated subscription change (no randomness impact). CATASTROPHE-tier applies because per-callsite strict classification doesn't isolate the composite call's eight-slot atomic write.

### §12.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder.**

Same shape as V-137 / V-155 / V-157 §8.C / §10.C — queue + apply split. The subscription-ID write is one of three VRF-config slots written by `applyVrfCoordinatorRotation`.

**Cross-VIOLATION coupling.** Shared with V-137 + V-155 + V-157 + V-161 in one v44.0 sub-phase.

**Bytecode impact.** Shared with V-137 (already counted). ABI: BREAKING shared.

### §12.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-89` — CATALOG §16 row V-159 + §15 row S-48 governance subset + V-137 consolidation. v44.0 plan-phase: CONSOLIDATED.

---

## §13 — V-160: vrfKeyHash write inside `wireVrf` (AdvanceModule.sol:508)

### §13.A — Design-intent backward-trace

`vrfKeyHash` is a `bytes32 internal` slot (CATALOG §14 row S-49). It holds the Chainlink VRF key-hash identifying the gas-lane / proof keyspace.

Writers:
- `wireVrf` at `AdvanceModule.sol:508`. **THIS row — V-160.**
- `updateVrfCoordinatorAndSub` at `AdvanceModule.sol:1687`. V-161 (§14).

Structurally identical to V-156 / V-158 — the same one-shot deploy-time bridge writes all three VRF-config slots together. The `:508` write completes the bundle.

**Why the slot exists.** The key-hash is required at every `requestRandomWords` call (`:1103, :1144`). It is part of the VRF protocol's keyspace selection.

**Why naive gating breaks deployment.** Same as V-156 §9.A.

**Phase-precedent.** Same as V-156.

### §13.B — Actor game-theory walk

Same as V-156 / V-158 — ADMIN re-call foot-gun. EV magnitude: LOW (per-row), structurally identical to V-156 / V-158.

### §13.C — Recommended tactic + rationale + impact

**Tactic (d) — Immutable.**

Same shape as V-156 §9.C / V-158 §11.C. Options (d.1) immutable migration or (d.2) one-shot lock. Coupled with V-156 + V-158 into one v44.0 sub-phase.

**Bytecode impact.** Already counted (shared with V-156).

### §13.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-90` — CATALOG §16 row V-160 + §15 row S-49 wireVrf + V-156 consolidation. v44.0 plan-phase: CONSOLIDATED with V-156 / V-158 into the `wireVrf` one-shot lock sub-phase.

---

## §14 — V-161: vrfKeyHash write inside `updateVrfCoordinatorAndSub` (AdvanceModule.sol:1687)

### §14.A — Design-intent backward-trace

`vrfKeyHash` is written at `:1687` inside `updateVrfCoordinatorAndSub`. The function context is documented in §1.A, §10.A, §12.A. The key-hash write is the third of three VRF-config rewrites.

**Why the slot is written here.** Chainlink VRF v2.5 migration changed the keyspace; future coordinator-version migrations may again. The key-hash field is rotated alongside the coordinator + subId.

**Why naive gating breaks the escape.** Same as V-137 / V-155 / V-157 / V-159.

**Phase-precedent.** Same as V-137.

### §14.B — Actor game-theory walk

Exploit actor: adversarial ADMIN. The key-hash field determines which Chainlink keyspace produces the VRF proof. A rotation to a key-hash for a different (e.g., compromised or low-confirmation) keyspace could reduce randomness security. In composition with V-157 (coordinator swap), the attacker gains control over the proof verification chain.

**EV magnitude:** CATASTROPHE-tier (compositional). Per-row LOW for isolated key-hash change.

### §14.C — Recommended tactic + rationale + impact

**Tactic (c) — Pre-lock reorder.**

Same as V-137 / V-155 / V-157 / V-159 — queue + apply split. The key-hash write is the third VRF-config slot in the `applyVrfCoordinatorRotation` atomic write set.

**Cross-VIOLATION coupling.** Shared with V-137 + V-155 + V-157 + V-159 in one v44.0 sub-phase.

**Bytecode impact.** Shared (already counted).

### §14.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-91` — CATALOG §16 row V-161 + §15 row S-49 governance subset + V-137 consolidation. v44.0 plan-phase: CONSOLIDATED with V-137 / V-155 / V-157 / V-159 into one queue+apply sub-phase.

---

## Cluster Summary

### Tactic Distribution (14 VIOLATIONs)

| Tactic | Count | V-NNN |
|---|---|---|
| (a) rngLock-gate | 3 | V-142, V-147, V-149 |
| (b) snapshot | 2 | V-140, V-141 |
| (c) reorder | 6 | V-137, V-153, V-155, V-157, V-159, V-161 |
| (d) immutable | 3 | V-156, V-158, V-160 |
| RECLASSIFY (subset of c) | 1 | V-153 |

### EV-Tier Distribution (14 VIOLATIONs)

| Tier | Count | V-NNN |
|---|---|---|
| CATASTROPHE-tier | 5 | V-137, V-155, V-157, V-159, V-161 (compositional — same atomic call) |
| HIGH | 3 | V-142, V-147, V-149 |
| MEDIUM | 2 | V-140, V-141 |
| LOW | 4 | V-153, V-156, V-158, V-160 |

### Label-Refinements & Stale-Phantoms

| V-NNN | Type | Refinement |
|---|---|---|
| V-140 | label-refinement | Catalog cites `recordAffiliateEarnings`; actual writer is `payAffiliate` (DegenerusAffiliate.sol:388). Semantic claim holds. |
| V-149 | label-refinement | Catalog cites non-existent `:572 RngLocked gate`; v44.0 must AUTHOR new guard, not extend a phantom. Semantic claim holds. |

### Scope-Expansion Candidates (§0 Headline #6)

| V-NNN | Candidate Class | Disposition |
|---|---|---|
| V-153 | EXEMPT-REQUESTLOOTBOXRNG (4th EXEMPT class) | **RECOMMENDED** — milestone-prose amendment at Phase 303 §9 closure |
| V-137, V-155, V-157, V-159, V-161 | 5th-EXEMPT (governance) | **NOT recommended** — tactic (c) reorder preserves the emergency function without erosing trust-minimization |

### v44.0 FIX-MILESTONE Sub-Phase Consolidation

| v44 sub-phase | Resolves | Handoff anchors |
|---|---|---|
| `updateVrfCoordinatorAndSub` queue+apply split | V-137, V-155, V-157, V-159, V-161 | H-78, H-85, H-87, H-89, H-91 |
| `wireVrf` one-shot lock | V-156, V-158, V-160 | H-86, H-88, H-90 |
| Affiliate cross-contract snapshot (widening of `lootboxEvScorePacked`) | V-140 (+ Cluster H V-109, V-110, V-112, V-113) | H-79 (+ H-64, H-65, H-67, H-68) |
| Quest cross-contract snapshot (widening of `lootboxEvScorePacked`) | V-141 | H-80 |
| Degenerette `:452` gate FUZZ verification | V-142 | H-81 (CONDITIONAL — FUZZ-301 attestation) |
| `_placeDegeneretteBetCore` rngLocked gate | V-147 | H-82 |
| `_purchaseFor` rngLocked gate | V-149 | H-83 |
| Phase 303 TERMINAL §9 closure attestation (EXEMPT-REQUESTLOOTBOXRNG amendment) | V-153 | H-84 (RESOLVED-AS-RECLASSIFIED) |

Total v44 sub-phases consolidated: 8 (vs 14 1:1 mapping). The two governance-cluster consolidations (5+3) recover the most leverage.

### Handoff-Anchor Register (Sequential)

| Anchor | V-NNN | Disposition | v44 sub-phase |
|---|---|---|---|
| D-43N-V44-HANDOFF-78 | V-137 | tactic (c) | rotation queue+apply |
| D-43N-V44-HANDOFF-79 | V-140 | tactic (b) | activity-score snapshot widening |
| D-43N-V44-HANDOFF-80 | V-141 | tactic (b) | activity-score snapshot widening |
| D-43N-V44-HANDOFF-81 | V-142 | tactic (a) gate-present | FUZZ-301 attestation (CONDITIONAL) |
| D-43N-V44-HANDOFF-82 | V-147 | tactic (a) | bet-place rngLocked gate |
| D-43N-V44-HANDOFF-83 | V-149 | tactic (a) | purchase rngLocked gate |
| D-43N-V44-HANDOFF-84 | V-153 | RECLASSIFY | Phase 303 §9 closure (RESOLVED-AS-RECLASSIFIED) |
| D-43N-V44-HANDOFF-85 | V-155 | tactic (c) | rotation queue+apply |
| D-43N-V44-HANDOFF-86 | V-156 | tactic (d) | wireVrf one-shot lock |
| D-43N-V44-HANDOFF-87 | V-157 | tactic (c) | rotation queue+apply |
| D-43N-V44-HANDOFF-88 | V-158 | tactic (d) | wireVrf one-shot lock |
| D-43N-V44-HANDOFF-89 | V-159 | tactic (c) | rotation queue+apply |
| D-43N-V44-HANDOFF-90 | V-160 | tactic (d) | wireVrf one-shot lock |
| D-43N-V44-HANDOFF-91 | V-161 | tactic (c) | rotation queue+apply |

---

*Phase: 299-fix-recommendation-document-fixrec*
*Plan: 09 (Cluster I — governance + cross-contract + commitment-side + VRF-config)*
*Authored: 2026-05-18*
*Posture: AUDIT-ONLY (D-43N-AUDIT-ONLY-01) — zero `contracts/` + `test/` mutations*
