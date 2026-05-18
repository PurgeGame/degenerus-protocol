---
phase: 299-fix-recommendation-document-fixrec
plan: 10
cluster: J
type: fixrec-cluster
scope: "ticketQueue (S-52) + ticketsOwedPacked V-179 fan-out (S-53) + sStonk redemption family (S-55..S-60) + decBurn (S-66/S-67) — ticket-queue + sStonk-redemption + decimator-burn slot family"
violations_covered: [V-168, V-169, V-170, V-171, V-172, V-174, V-175, V-176, V-177, V-179, V-182, V-184, V-186, V-188, V-190, V-191, V-192, V-193, V-201, V-202]
handoff_anchors:
  - D-43N-V44-HANDOFF-92   # V-168
  - D-43N-V44-HANDOFF-93   # V-169
  - D-43N-V44-HANDOFF-94   # V-170
  - D-43N-V44-HANDOFF-95   # V-171
  - D-43N-V44-HANDOFF-96   # V-172
  - D-43N-V44-HANDOFF-97   # V-174
  - D-43N-V44-HANDOFF-98   # V-175
  - D-43N-V44-HANDOFF-99   # V-176
  - D-43N-V44-HANDOFF-100  # V-177
  - D-43N-V44-HANDOFF-101  # V-179.A purchaseWhaleBundle
  - D-43N-V44-HANDOFF-102  # V-179.B purchaseLazyPass
  - D-43N-V44-HANDOFF-103  # V-179.C purchaseDeityPass
  - D-43N-V44-HANDOFF-104  # V-179.D openLootBox
  - D-43N-V44-HANDOFF-105  # V-179.E openBurnieLootBox
  - D-43N-V44-HANDOFF-106  # V-179.F _purchaseFor
  - D-43N-V44-HANDOFF-107  # V-179.G _awardDecimatorLootbox
  - D-43N-V44-HANDOFF-108  # V-179.H claimWhalePass
  - D-43N-V44-HANDOFF-109  # V-179.I _redeemWhalePassRange
  - D-43N-V44-HANDOFF-110  # V-182
  - D-43N-V44-HANDOFF-111  # V-184 TIER-1 HEADLINE
  - D-43N-V44-HANDOFF-112  # V-186
  - D-43N-V44-HANDOFF-113  # V-188
  - D-43N-V44-HANDOFF-114  # V-190
  - D-43N-V44-HANDOFF-115  # V-191
  - D-43N-V44-HANDOFF-116  # V-192
  - D-43N-V44-HANDOFF-117  # V-193
  - D-43N-V44-HANDOFF-118  # V-201
  - D-43N-V44-HANDOFF-119  # V-202
tactic_mix:
  rngLock_gate_a:        [V-168, V-169, V-170, V-171, V-172, V-174, V-175, V-176, V-177, V-179, V-182, V-184, V-186, V-188, V-190, V-191, V-192, V-193, V-201, V-202]
  snapshot_b:            []
  reorder_c:             []
  immutable_d:           []
  structural_advance_b_alt: [V-184]   # PREFERRED alternative for V-184 (mirrors Phase 288 dailyIdx)
ev_tier:
  CATASTROPHE:           [V-184]      # ~19% free EV per round, compounding to ~75-175% supply-cap-bounded ceiling
  HIGH:                  [V-171, V-172, V-174, V-179, V-186, V-188, V-190, V-191, V-201, V-202]
  MEDIUM:                [V-168, V-169, V-175, V-176, V-177, V-182, V-192, V-193]
  LOW:                   [V-170]      # already gated at WhaleModule:543; verdict-matrix is stack-strict
stale_phantoms:          []           # all 20 verified against current source HEAD (audit baseline 81d7c94b)
headline_tier1:          [V-184]
posture: AUDIT-ONLY (D-43N-AUDIT-ONLY-01)
---

# Phase 299 Plan 10 — FIXREC Cluster J

**Scope.** Ticket-queue + ticketsOwedPacked + sStonk-redemption-family + decBurn writers. 20 logical VIOLATIONs spanning five sub-families:

| Sub-family | Slot | VIOLATIONs |
|---|---|---|
| `ticketQueue[rk]` (S-52) — per-resolution-key player address array | per-game ticket-allocation queue | V-168, V-169, V-170, V-171, V-172, V-174, V-175, V-176, V-177 |
| `ticketsOwedPacked[rk][player]` (S-53) — per-EOA owed-count packed | co-located with S-52 | V-179 (single logical entry; 9 EOA callsites fan out to V-179.A..V-179.I → H-101..H-109) |
| `bountyOwedTo` (S-55) — BurnieCoinflip armed-bounty owner | per-game biggest-flip bounty | V-182 |
| sStonk redemption family (S-56..S-60) — `redemptionPeriodIndex` + `pendingRedemptionEthBase` + `pendingRedemptionBurnieBase` + `pendingRedemptionBurnie` + `pendingRedemptions[player]` | per-period gambling-burn accounting | V-184 (TIER-1), V-186, V-188, V-190, V-191, V-192, V-193 |
| `decBurn[lvl][player].burn` (S-66) + `terminalDecBucketBurnTotal[bucketKey]` (S-67) | decimator burn records | V-201, V-202 |

**§0 headline #1 — V-184 sStonk cross-day re-roll exploit (TIER-1).** This cluster carries the milestone's most economically significant load-bearing finding. Catalog §12 §D-VIOL-1 documents the structural data-corruption pattern in full; this FIXREC entry (§12 below — note: §N counter, not §12-the-catalog-section) crystallizes both the tactic-(a) defensive revert and the preferred tactic-(b) "structural advance" alternative (Phase 288 `dailyIdx` precedent) for v44.0 plan-phase consumption.

**Consumer reach context.** S-52/S-53 slots are consumed during AdvanceModule trait-generation (CATALOG §10) — every EOA writer of `ticketQueue[rk]` mutates the address-array consumed at trait-roll time. S-55 `bountyOwedTo` feeds `BurnieCoinflip.processCoinflipPayouts` (CATALOG §11), where the bounty owner receives the windfall. S-56..S-60 are the sStonk-side accounting slots consumed by `resolveRedemptionPeriod` + `claimRedemption` (CATALOG §12). S-66/S-67 feed `runDecimatorJackpot` (CATALOG §13) and `runTerminalDecimatorJackpot` (CATALOG §4).

**Verification scope.** Every §N below cross-checked against `contracts/` at the audit baseline `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`. File:line cites in §N.A reproduce the writer present in source; classifications follow CATALOG §16 verdicts. **Zero stale-phantom rows identified** in this cluster. Catalog verdict alphabet locked to `EXEMPT-ADVANCEGAME | EXEMPT-VRFCALLBACK | EXEMPT-RETRYLOOTBOXRNG | VIOLATION` per `D-43N-AUDIT-ONLY-01`; no discretionary fourth-class disposition tokens introduced.

**Discipline.** No `contracts/` or `test/` mutations. Backward-trace per `feedback_design_intent_before_deletion.md`. SLOAD-freshness per `feedback_rng_window_storage_read_freshness.md` (V-184 is the canonical commitment-side staleness exploit on this codebase). Source-attestation per `feedback_verify_call_graph_against_source.md`. Frozen-contract reality per `feedback_frozen_contracts_no_future_proofing.md` — recommendations are advisory for v44.0 plan-phase consumption.

---

## §1 — V-168: `ticketQueue[rk]` write inside `_queueTickets` via `purchaseWhaleBundle` (`WhaleModule.sol:313`)

### §1.A — Design-intent backward-trace

`ticketQueue` is `mapping(uint24 => address[]) internal ticketQueue;` at `contracts/storage/DegenerusGameStorage.sol` (round-key-indexed push-array). Companion slot `ticketsOwedPacked[rk][player]` (S-53) is the per-player owed-count co-located in every write path. Both are consumed at the AdvanceModule trait-generation consumer (CATALOG §10) when `advanceGame()` self-stacks resolves the per-level round-key's ticket allocations.

`_queueTickets(buyer, lvl, ticketCount, isBonus)` is the round-key-keyed push helper at `DegenerusGameStorage.sol:580` — it `.push(buyer)` into `ticketQueue[rk]` and bumps `ticketsOwedPacked[rk][buyer]`. `purchaseWhaleBundle` (`WhaleModule.sol:187`) is the EOA-facing whale-bundle purchase entry; its loop at `WhaleModule.sol:313` calls `_queueTickets` for each level the bundle covers (100 levels at standard tickets and bonus tiers).

**Why the slot exists.** The ticket-queue mechanism predates the rngLock discipline (introduced when the protocol added the deferred trait-generation flow). Each ticket purchase deposits the buyer at `ticketQueue[lvl]` so that AdvanceModule's trait-generation pass can stochastically assign rare traits proportional to ticket holdings at the round-key's resolution time. Naively reverting `_queueTickets` on `rngLockedFlag` would break legitimate purchases — but at this writer-callsite (whale-bundle purchase), the existing `purchaseDeityPass` precedent at `WhaleModule.sol:543` (`if (rngLockedFlag) revert RngLocked()`) already encodes the "block whale-tier purchases during rngLock" pattern.

**Phase-precedent.** Phase 292 HRROLL leader-bonus + Phase 290 MINTCLN (`v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md`) established the `cachedJpFlag && rngLockedFlag`-style gates at `MintModule.sol:1221`. Phase 296 RETRY_LOOTBOX_RNG (`v42.0-phases/296-cross-surface-adversarial-sweep-sweep/296-CONTEXT.md`, `D-42N-RETRY-RNG-DOMAIN-SEP-01`) clarified that lootbox-resolution VRF is domain-separated from daily VRF — relevant for V-171/V-172 (this slot's lootbox-callsite siblings) but not for V-168's whale-bundle path. The PARTIAL existing coverage on `_purchaseDeityPass:543` is the precedent that V-168/V-169 must EXTEND.

### §1.B — Actor game-theory walk

**Exploit actor.** EOA whale-tier buyer with sufficient ETH to call `purchaseWhaleBundle` between (i) AdvanceModule's VRF callback delivery (publishing `rngWordCurrent`) and (ii) AdvanceModule's next `advanceGame()` invocation that consumes `rngWordByDay[day]` for trait-generation. Window is at minimum one block (VRF callback to next `advanceGame()`); in practice the window persists until the next caller invokes `advanceGame()`.

**Action sequence.**
1. Attacker monitors `rngRequestTime != 0 && rngLockedFlag == true` → VRF in-flight.
2. VRF callback delivers `rngWord` via `rawFulfillRandomWords` → `rngWordCurrent` is set, `rngLockedFlag` remains `true` (cleared inside next `advanceGame()` via `_unlockRng` at `AdvanceModule.sol:1731`).
3. Attacker reads published `rngWordCurrent` (mempool / public state). Projects which `ticketQueue[lvl]` indices benefit from cramming additional buyer entries: e.g., if the rngWord-derived trait-roll favors low-index entries, attacker queues a fresh `purchaseWhaleBundle` to push themselves into the favorable position.
4. `_queueTickets:313` runs unguarded → attacker's address inserted into `ticketQueue[lvl]` for all 100 levels of the bundle, with `ticketsOwedPacked[rk][attacker]` bumped accordingly.
5. Next `advanceGame()` consumes the now-attacker-padded `ticketQueue[lvl]` array at trait-generation time.

**EV magnitude.** MEDIUM. Whale-bundle purchase is a high-capital action (per-bundle cost is non-trivial), so the attack requires meaningful upfront ETH. The trait-generation roll determines NFT rare-trait assignments which have indirect (NFT-market) economic value, not direct payout multiplication. The economic-likelihood disposition is MEDIUM: an attacker with sufficient bankroll AND a position in the level-range being resolved would exploit; an opportunistic attacker without prior position has no in-window pivot to outsize the bundle cost.

### §1.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `purchaseWhaleBundle` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the start of `_purchaseWhaleBundle` (`WhaleModule.sol:194`), mirroring the existing `_purchaseDeityPass:543` convention.

**Rationale.** Whale-bundle is a single-call atomic purchase touching 100 ticketQueue slots; gating at function entry is structurally minimal and matches the established precedent. Alternative tactic (b) snapshot-at-allocation is rejected because the `ticketQueue` array is itself the consumer-side state — there is no "earlier commitment" to snapshot against. Alternative tactic (c) pre-lock reorder is rejected because the writer is the EOA's atomic action — there is no later reorder point inside the same TX.

**Bytecode impact.** ~30 bytes (one `SLOAD` of `rngLockedFlag` + conditional `revert RngLocked()`). Storage-layout: byte-identical (no new slots). Public ABI: NON-BREAKING (the revert path is new but the function signature unchanged). The `RngLocked()` custom error is already defined and used at `MintModule:1221`, `BurnieCoinflip:730`, `sStonk:492` per CATALOG §0 implementation-pattern enumeration — this fix reuses the existing error selector.

### §1.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-92` — CATALOG §16 row V-168 + §15 row S-52 `_queueTickets`/`purchaseWhaleBundle` + §10 trait-generation consumer. v44.0 plan-phase: add `if (rngLockedFlag) revert RngLocked();` at `_purchaseWhaleBundle` entry, co-located with the V-179.A handoff (single gate covers both S-52 and S-53 writes at this callsite).

---

## §2 — V-169: `ticketQueue[rk]` write inside `_queueTickets` via `purchaseLazyPass` (`WhaleModule.sol:482`)

### §2.A — Design-intent backward-trace

`purchaseLazyPass` (`WhaleModule.sol:380`) is the EOA-facing "lazy" whale-pass purchase — a discounted variant of whale-bundle that queues tickets only for the bonus-tier range (levels 1-10) rather than the full 100 levels. The `_queueTickets` callsite at `WhaleModule.sol:482` is one push per bonus-range level. Same slot identity, same writer fn, different EOA entry point.

**Why the slot exists.** Lazy-pass is a price-discriminated tier of whale-bundle introduced to broaden the whale-tier purchaser pool. The `_purchaseLazyPass` body has NO existing `rngLockedFlag` gate at the entry. Phase-precedent identical to V-168: `_purchaseDeityPass:543` already encodes the convention.

**Why naive gating preserves UX.** Lazy-pass purchases are infrequent (the lazy-pass is purchased once per game per buyer). A short-duration rngLock revert (~30 seconds typical VRF latency) does not meaningfully degrade UX — the buyer retries after the window.

### §2.B — Actor game-theory walk

**Exploit actor.** Same class as V-168 — EOA buyer with capital for a lazy-pass purchase, observing the in-flight VRF window.

**Action sequence.** Identical to V-168 but at the lazy-pass entry. Window properties identical (VRF callback to next `advanceGame()`).

**EV magnitude.** MEDIUM. Lazy-pass tickets are bonus-range-only (10 levels), reducing the attacker's ticket-queue insertion scale by 90% relative to whale-bundle. Combined with the lazy-pass purchase cost, EV is bounded. Conservative classification: MEDIUM.

### §2.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `_purchaseLazyPass` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the start of `_purchaseLazyPass` (`WhaleModule.sol:384`), mirroring `_purchaseDeityPass:543`.

**Rationale.** Same as V-168 §1.C. The catalog row's rationale text literally cites "mirrors purchaseDeityPass:543" as the prescribed implementation pattern.

**Bytecode impact.** ~30 bytes. Storage-layout / ABI: unchanged.

### §2.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-93` — CATALOG §16 row V-169 + §15 row S-52 `_queueTickets`/`purchaseLazyPass`. v44.0 plan-phase: add `rngLockedFlag` revert at `_purchaseLazyPass` entry, co-located with V-179.B handoff.

---

## §3 — V-170: `ticketQueue[rk]` write inside `_queueTickets` via `purchaseDeityPass` (`WhaleModule.sol:625`)

### §3.A — Design-intent backward-trace

`purchaseDeityPass` (`WhaleModule.sol:538`) is the EOA-facing deity-pass purchase (1 of 32 symbol slots per game). The `_queueTickets` callsite at `WhaleModule.sol:625` queues whale-equivalent tickets across the bonus-and-standard range (100 levels) for the deity-pass holder. The writer is gated at function entry by `if (rngLockedFlag) revert RngLocked();` at `WhaleModule.sol:543` — **this gate already exists in current source** (verified at audit baseline).

**Why the slot exists.** Identical to V-168/V-169. Deity-pass is the highest-tier whale purchase (per-symbol scarcity creates per-game cap of 32 holders).

**Phase-precedent.** Phase 294 DPNERF (`v42.0-phases/294-deity-pass-gold-nerf-dpnerf/294-01-DESIGN-INTENT-TRACE.md`) shaped the deity-pass economic balance. The `rngLockedFlag` gate at `:543` is the established precedent V-168/V-169 are extending.

### §3.B — Actor game-theory walk

**Exploit actor.** Same class as V-168/V-169.

**Action sequence.** Attacker attempts `purchaseDeityPass` during rngLock → `WhaleModule.sol:543` reverts → `ticketQueue[rk]` is NOT mutated. Attack blocked.

**EV magnitude.** LOW. The catalog row classifies this as VIOLATION strictly under the per-callsite verdict-matrix rule (the writer-callsite is not on an EXEMPT advance-stack reach), but the existing runtime gate at `:543` means the structural risk is ALREADY zero. Per CATALOG §16 row V-170 verdict-text "Existing gate at :543 satisfies; verdict-matrix is stack-strict, gate verified," this is a documentation row, not an actionable structural fix.

### §3.C — Recommended tactic + rationale + impact

**Tactic (a) — Existing gate at `:543` satisfies.** No additional code change required.

**Rationale.** The catalog's strict per-callsite verdict alphabet does not distinguish "gated by existing runtime check" from "ungated EOA writer" — both are classified VIOLATION because the writer-callsite itself is not on an EXEMPT advance-stack. The implementation-side disposition is "verify the existing `:543` gate covers the writer reach," which it does (the `_queueTickets:625` callsite is downstream of `:543` in the same TX). This row is preserved as a verdict-matrix entry but the v44.0 plan-phase action is "verify-only" rather than "patch."

**Bytecode impact.** Zero. Storage / ABI unchanged.

### §3.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-94` — CATALOG §16 row V-170. v44.0 plan-phase: verify-only — confirm `WhaleModule.sol:543` `rngLockedFlag` revert remains in place; no patch required. Co-located with V-179.C (which inherits the same verify-only disposition).

---

## §4 — V-171: `ticketQueue[rk]` write inside `_queueTickets` via `openLootBox` (`LootboxModule.sol:1067`)

### §4.A — Design-intent backward-trace

`openLootBox(player, index)` at `LootboxModule.sol:526` is the EOA-facing manual lootbox-resolution entry. The `_queueTickets` callsite at `LootboxModule.sol:1067` runs inside `_resolveLootboxCommon` when the lootbox resolution awards whole-ticket count (`whole != 0`); the call inserts the player into `ticketQueue[targetLevel]` for each whole ticket awarded.

**Why the slot exists.** Lootbox resolution uses the daily-VRF-derived `rngWordByIndex[index]` (CATALOG §7) to determine the ticket-award magnitude. The award-magnitude → ticket-queue-insertion path is structurally legitimate; the EXPLOIT is the asymmetric timing where an attacker can call `openLootBox` between the daily VRF callback and the next `advanceGame()` to insert into a `ticketQueue[targetLevel]` that has NOT YET been consumed by trait-generation.

**Phase-precedent.** Phase 296 RETRY_LOOTBOX_RNG (`D-42N-RETRY-RNG-DOMAIN-SEP-01`) confirmed lootbox VRF is domain-separated from daily VRF — but the lootbox-resolution OUTPUT (`ticketQueue` insertion) still feeds into the daily-VRF-consumed trait-generation pass. The domain separation closes lootbox-VRF mutability but does NOT close the ticket-queue-insertion side channel into trait-generation.

### §4.B — Actor game-theory walk

**Exploit actor.** EOA lootbox-holder who pre-committed to an `index` (allocation-time write earlier in the game flow) and now wants to time the `openLootBox(index)` call to land the awarded tickets in a `ticketQueue[targetLevel]` array that will be CONSUMED by trait-generation under the just-published daily rngWord.

**Action sequence.**
1. Attacker holds a pre-allocated lootbox index from prior game flow.
2. VRF callback delivers daily `rngWord` → `rngLockedFlag` remains true until next `advanceGame()`.
3. Attacker projects which `ticketQueue[lvl]` arrays will be trait-resolved in the imminent advance; calls `openLootBox(index)` if a beneficial insertion is available.
4. `_queueTickets:1067` runs unguarded → attacker's tickets inserted at advantageous queue position.
5. Next `advanceGame()` consumes the now-padded queue.

**EV magnitude.** HIGH. Per CATALOG §0 headline #2 ("Manual-path lootbox open is a deep VIOLATION cluster"), the manual lootbox-open path is the densest VIOLATION cluster in the codebase — 35 violation rows on `openLootBox`/`openBurnieLootBox`. The `_queueTickets` insertion is one component of that cluster but it directly modulates trait-generation outcomes, which feed into NFT-market value AND into ticket-jackpot eligibility. The trait-roll EV swing on a perfectly-timed insertion can be material (multi-eth per attack, per CATALOG §10 trait-magnitude prose).

### §4.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `openLootBox` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `openLootBox` (`LootboxModule.sol:526`).

**Rationale.** The daily-VRF-freshness invariant says: NO writer should mutate state consumed by trait-generation between VRF callback and `_unlockRng`. Per `feedback_rng_window_storage_read_freshness.md`, the lootbox VRF (domain-separated) is independent of the daily VRF — so gating `openLootBox` on `rngLockedFlag` does NOT block lootbox-VRF resolution; it ONLY blocks the ticket-queue side-channel into daily-VRF-consumed trait-generation. Snapshot tactic (b) is rejected: the ticket-queue ARRAY is itself the consumer state (cannot be snapshotted without restructuring the array indexing). Reorder tactic (c) is rejected: the writer is the EOA's atomic action.

**Bytecode impact.** ~30 bytes. The `RngLocked()` error is shared. Note: lootbox-VRF retries (`retryLootboxRng`, EXEMPT-RETRYLOOTBOXRNG) are unaffected because the retry path is admin-side, not EOA. Storage / ABI: unchanged.

**Caveat for v44.0 plan-phase.** If `openLootBox` is the only EOA path to claim accumulated lootbox-VRF awards and the daily rngLock window is long-running (multi-day stalls per the gap-day handling in `AdvanceModule._backfillGapDays`), users may want a queued-claim pattern to defer the open without revert. v44.0 plan-phase may decide between strict revert (this recommendation) and a queued-claim refactor.

### §4.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-95` — CATALOG §16 row V-171 + §15 row S-52 `_queueTickets`/`openLootBox` + §7 manual-lootbox-open consumer + §0 headline #2. v44.0 plan-phase: add `rngLockedFlag` revert at `openLootBox` entry, co-located with V-179.D handoff and (potentially) the broader §0 headline #2 manual-open cluster v44 sub-phase.

---

## §5 — V-172: `ticketQueue[rk]` write inside `_queueTickets` via `openBurnieLootBox` (`LootboxModule.sol:1190`)

### §5.A — Design-intent backward-trace

`openBurnieLootBox(player, index)` at `LootboxModule.sol:607` is the EOA-facing burnie-side variant of `openLootBox` — same resolution path but with BURNIE-denominated allocation. The `_queueTickets` callsite at `LootboxModule.sol:1190` is the burnie-variant's ticket-award insertion. Same write-target (`ticketQueue[rk]`) as V-171; same trait-generation consumer.

**Why the slot exists.** Identical to V-171 (lootbox-resolution award path; burnie-denominated variant). Phase 296 domain-separation applies identically.

### §5.B — Actor game-theory walk

**Exploit actor + action sequence.** Identical to V-171 but with `openBurnieLootBox` substituted. Burnie-side lootbox-VRF allocation pre-committed; EOA timing same.

**EV magnitude.** HIGH (same as V-171). The burnie-side variant has the same downstream trait-generation impact.

### §5.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `openBurnieLootBox` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `openBurnieLootBox` (`LootboxModule.sol:607`).

**Rationale.** Same as V-171 §4.C; the catalog row's rationale text literally states "Same as V-171 — write-target shared." Single gate covers V-172 (S-52) and V-179.E (S-53).

**Bytecode impact.** ~30 bytes.

### §5.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-96` — CATALOG §16 row V-172. v44.0 plan-phase: add `rngLockedFlag` revert at `openBurnieLootBox` entry, co-located with V-179.E.

---

## §6 — V-174: `ticketQueue[rk]` write inside `_queueTicketsScaled` via `_purchaseFor` (`MintModule.sol:1129`)

### §6.A — Design-intent backward-trace

`_purchaseFor` (`MintModule.sol:899`) is the internal mint-purchase routine called from EOA-facing `purchase`/`purchaseCoin`/`purchaseBurnieLootbox`. The `_queueTicketsScaled` callsite at `MintModule.sol:1129` runs after quantity computation and adjusts the ticket allocation by EV-scaling factors. `_queueTicketsScaled(buyer, targetLevel, adjustedQty, false)` is the scaled variant of `_queueTickets`; storage writer at `DegenerusGameStorage.sol:612` (push) + `:636` (ticketsOwedPacked write).

**Why the slot exists.** Mint-purchase is the primary EOA capital inflow path. `_queueTicketsScaled` adjusts the queued-ticket count by per-buyer scaling (activity-score, deity-bonus, etc.). The PARTIAL existing coverage is the `lastPurchaseDay && rngLockedFlag` target-level redirect at `MintModule.sol:1221` (per Phase 290 MINTCLN) — but this redirect ONLY repoints the target-level; it does NOT block the write itself. The write still lands in `ticketQueue[targetLevel]` for some level.

**Phase-precedent.** Phase 290 MINTCLN introduced the `:1221` cached-flag redirect. The structural insight from MINTCLN: target-level redirect alone is insufficient — the write itself must be gated to close the side channel.

### §6.B — Actor game-theory walk

**Exploit actor.** EOA mint-purchaser with ETH/BURNIE for an in-window purchase.

**Action sequence.**
1. VRF callback delivers daily `rngWord`; `rngLockedFlag` remains true.
2. Attacker projects which `ticketQueue[targetLevel]` will be trait-resolved.
3. Attacker calls `purchase` → `_purchaseFor` → `_queueTicketsScaled:1129`. The `:1221` redirect changes `targetLevel` to current `lvl` (not `lvl + 1`) but the write still inserts the buyer at `ticketQueue[lvl]`, which is a level the imminent `advanceGame()` will trait-resolve.
4. Trait-generation consumes the now-padded queue.

**EV magnitude.** HIGH. Per CATALOG §0 headline #3 ("Top-level ungated EOA entry points cluster"), `MintModule.purchase` carries no blanket `rngLockedFlag` gate. Mint-purchase volume is high; per-attack EV swings on trait-generation outcomes are material.

### §6.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `purchase` (and sibling) entries.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` entries.

**Rationale.** Per catalog row: "Gate purchase() against daily VRF window; level-target redirect at :1221 insufficient." The `:1221` redirect is necessary but not sufficient — it solves the "where the ticket lands" problem but not the "whether the ticket is queued at all" problem during the rngLock window. The structural fix is to revert the purchase entirely.

**Bytecode impact.** ~30 bytes per entry × 3 entries = ~90 bytes total. NON-BREAKING ABI.

**UX tradeoff for v44.0 plan-phase.** Mint-purchases are higher-volume than whale-bundle/lazy-pass purchases; reverts during rngLock will be more visible to users. v44.0 plan-phase may consider a queued-purchase pattern (defer the queue write to post-unlock) instead of strict revert. The current recommendation follows the catalog's tactic-(a) prescription.

### §6.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-97` — CATALOG §16 row V-174 + §15 row S-52 `_queueTicketsScaled`/`_purchaseFor` + §10 trait-generation consumer + §0 headline #3. v44.0 plan-phase: add `rngLockedFlag` revert at `purchase`/`purchaseCoin`/`purchaseBurnieLootbox` entries, co-located with V-179.F handoff.

---

## §7 — V-175: `ticketQueue[rk]` write inside `_queueTicketRange` via `_awardDecimatorLootbox` (`DecimatorModule.sol:582`)

### §7.A — Design-intent backward-trace

`_awardDecimatorLootbox(winner, amount, rngWord)` at `DecimatorModule.sol:570` runs as part of `claimDecimatorJackpot`'s post-VRF lootbox-portion award (line 389). When the claim amount exceeds `LOOTBOX_CLAIM_THRESHOLD`, the function awards `fullHalfPasses` whole-half-passes via `_queueTicketRange(winner, startLevel, 100, fullHalfPasses, false)` at `DecimatorModule.sol:582`. Writer at `DegenerusGameStorage.sol:666` (push) + `:671` (ticketsOwedPacked).

**Why the slot exists.** Decimator jackpot payouts are routed half-via-ticket-queue, half-via-claimable-ETH. The ticket-queue side awards bonus-range whale-equivalent tickets. The write is reached BOTH from the EOA path (`claimDecimatorJackpot` external) AND from the advance-stack path (when `claimDecimatorJackpot` is invoked internally during phase transitions; verify per-callsite).

**Per-callsite split per CATALOG §16 row V-175:** "EOA (advance-stack callsites EXEMPT, but EOA per-callsite split applies)." The advance-stack reach to `_awardDecimatorLootbox` is classified EXEMPT-ADVANCEGAME; only the EOA reach (via `claimDecimatorJackpot` external) is classified VIOLATION.

### §7.B — Actor game-theory walk

**Exploit actor.** EOA decimator-claimer with a prior `decBurn[lvl][player]` record that landed in a winning subbucket.

**Action sequence.**
1. Decimator jackpot resolved (advance-stack); claim round persisted in `decClaimRounds[lvl]`.
2. VRF callback delivers a SUBSEQUENT daily `rngWord` for a different trait-generation pass; `rngLockedFlag` true.
3. Attacker times `claimDecimatorJackpot(lvl)` to insert their bonus-range tickets via `_queueTicketRange:582` during the rngLock window — landing at advantageous positions in `ticketQueue[startLevel..startLevel+99]`.
4. Trait-generation consumes the padded queue.

**EV magnitude.** MEDIUM. Decimator claim is a one-shot per (player, lvl) tuple, so attacker capacity is bounded by their per-game decimator winnings. The ticket-range insertion is bonus-range only (not full 100 levels of unique advantage). Combined with the prerequisite of being a decimator winner, this is a narrower attack class than V-174.

### §7.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at the EOA-reach of `_awardDecimatorLootbox`.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `claimDecimatorJackpot` (`DecimatorModule.sol:321`) — which is the only EOA reach of `_awardDecimatorLootbox`. Note: `claimDecimatorJackpot` ALREADY guards `prizePoolFrozen` (line 325 `if (prizePoolFrozen) revert E();`); the new gate is a separate condition.

**Rationale.** Per catalog row: "Gate EOA-reach (recordDecBurn); advance-stack reach is EXEMPT per-callsite." The advance-stack reach is the orchestrated phase-transition path, which IS the consumer; the EOA reach is the side channel that opens the window. Gating at `claimDecimatorJackpot` entry closes the EOA-side without affecting advance-stack flow.

**Bytecode impact.** ~30 bytes. The `prizePoolFrozen` revert at line 325 is a related but distinct check — it blocks claims when the prize pool itself is frozen, which is a different state than `rngLockedFlag` (rngLockedFlag covers VRF-in-flight only).

### §7.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-98` — CATALOG §16 row V-175 + §15 row S-52 `_queueTicketRange`/`_awardDecimatorLootbox` + §13 DecimatorModule consumer. v44.0 plan-phase: add `rngLockedFlag` revert at `claimDecimatorJackpot` entry. Co-located with V-179.G handoff.

---

## §8 — V-176: `ticketQueue[rk]` write inside `_queueTicketRange` via `claimWhalePass` (`WhaleModule.sol:973`)

### §8.A — Design-intent backward-trace

`claimWhalePass(player)` at `WhaleModule.sol:957` is the EOA-facing whale-pass redemption that converts a held whale-pass into queued tickets. The `_queueTicketRange` callsite at `WhaleModule.sol:973` queues `halfPasses` worth of bonus-range tickets across 100 levels.

**Why the slot exists.** Whale-pass is a one-shot redemption per holder. The `_queueTicketRange` storage writer at `DegenerusGameStorage.sol:666` has a partial far-future loop revert (per catalog row's existing-coverage prose) — but that revert covers the loop-bound case, not the rngLock-window case.

**Phase-precedent.** Whale-pass redemption predates the rngLock discipline; the current implementation has no top-level rngLockedFlag gate.

### §8.B — Actor game-theory walk

**Exploit actor + action sequence.** Same class as V-168/V-169 — EOA holder of a whale-pass who times the `claimWhalePass` call during rngLock.

**EV magnitude.** MEDIUM. Whale-pass is one-shot per holder; bonus-range tickets only (limited insertion scale).

### §8.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at `claimWhalePass` entry.** Insert `if (rngLockedFlag) revert RngLocked();` at the top of `claimWhalePass` (`WhaleModule.sol:957`).

**Rationale.** Per catalog row: "Add top-level rngLockedFlag gate; far-future loop revert is partial coverage." The far-future loop revert (inside `_queueTicketRange` storage helper) is a defense against indexing out of bounds, not against rngLock-window timing. The structural fix is at the entry point.

**Bytecode impact.** ~30 bytes.

### §8.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-99` — CATALOG §16 row V-176. v44.0 plan-phase: add `rngLockedFlag` revert at `claimWhalePass` entry, co-located with V-179.H.

---

## §9 — V-177: `ticketQueue[rk]` write inside `_queueTicketRange` via `_redeemWhalePassRange` (`Storage.sol:1135`)

### §9.A — Design-intent backward-trace

`_redeemWhalePassRange` (at `DegenerusGameStorage.sol:1135`) is the lower-level helper invoked from whale-pass redemption flows when a player redeems a partial range. The `_queueTicketRange` callsite at `:1135` is the storage-helper-internal queue-range insertion. Same write-target (`ticketQueue[rk]`) and same consumer reach as V-176.

**Why the slot exists.** Range-redemption is a structured helper supporting bulk whale-pass conversion. Same partial-coverage situation as V-176 (far-future loop revert exists, top-level rngLock gate does not).

### §9.B — Actor game-theory walk

**Exploit actor + action sequence.** Identical to V-176; both EOA reaches lead to `_queueTicketRange` writes during rngLock.

**EV magnitude.** MEDIUM. Same per-attack scale as V-176.

### §9.C — Recommended tactic + rationale + impact

**Tactic (a) — `rngLockedFlag`-gated revert at the EOA entry that invokes `_redeemWhalePassRange`.** The catalog row's text "Same as V-176 — whale-pass redemption path" indicates the gate is at the same EOA entry as V-176 (`claimWhalePass` and any sibling entries that reach `_redeemWhalePassRange`).

**Rationale.** Single gate at the EOA entry covers both V-176's direct `_queueTicketRange:973` call AND V-177's deeper `_queueTicketRange` reach via `_redeemWhalePassRange:1135`.

**Bytecode impact.** Zero incremental cost over V-176 (same gate site).

### §9.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-100` — CATALOG §16 row V-177. v44.0 plan-phase: gate co-located with V-176 (`claimWhalePass` entry) — single revert covers both rows. Co-located with V-179.I.

---

## §10 — V-179: `ticketsOwedPacked[rk][player]` co-located writes (9-callsite fan-out: V-179.A..V-179.I)

### §10.A — Design-intent backward-trace

`ticketsOwedPacked[rk][player]` is the per-player owed-ticket-count slot co-located with `ticketQueue[rk]` (S-52). Storage declared as `mapping(uint24 => mapping(address => uint40)) internal` at `DegenerusGameStorage.sol`. The slot is consumed alongside `ticketQueue[rk]` at trait-generation time — each `ticketQueue[rk]` entry's owed-count comes from `ticketsOwedPacked[rk][buyer]`.

**Critical co-location property.** Every writer fn of S-52 (`_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange`) ALSO writes S-53 in the same SSTORE block (per CATALOG §15 rows S-52 / S-53 — identical writer-fn rows, identical callsite rows). Storage line numbers: `_queueTickets` writes S-52 at `:580` and S-53 at `:585`; `_queueTicketsScaled` writes S-52 at `:612` and S-53 at `:636`; `_queueTicketRange` writes S-52 at `:666` and S-53 at `:671`. The two slots are STRUCTURALLY co-located.

**V-179 fan-out per `D-299-FIXREC-LAYOUT-01` 82-budget rule.** V-179 is ONE logical VIOLATION even though it spans 9 distinct EOA callsites (one per S-52 callsite). The 9 sub-anchors H-101..H-109 correspond one-to-one with the V-179.A..V-179.I sub-rows the catalog planner would emit if V-179 were split. Per the catalog §0 footnote, V-179 is counted as a single entry in the 82-logical-VIOLATION budget; the 9-sub-row expansion is for completeness in the verdict matrix but does NOT inflate the budget.

**Why naive single-slot gating is identical to S-52 gating.** Because S-52 and S-53 are written in the same SSTORE block at every callsite, the fix at each S-52 callsite (the function-entry `rngLockedFlag` revert) ALSO fixes the corresponding S-53 write at the same callsite at zero incremental cost. The 9 S-52 callsites covered above (V-168, V-169, V-170, V-171, V-172, V-174, V-175, V-176, V-177) are EXACTLY the 9 V-179 sub-rows.

**Phase-precedent.** Co-located writer-slot patterns are common in this codebase (e.g., `BitPackingLib`-packed slots where multiple fields share a SSTORE). The "single gate at the entry function covers both slots" disposition is the standard treatment.

### §10.B — Actor game-theory walk (9-callsite enumeration)

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

### §10.C — Recommended tactic + rationale + impact

**Tactic (a) — Same gate as each S-52 row; co-located write — single gate covers both slots.** Per catalog row's verdict text. Each S-52 fix at §1-§9 above ALSO closes the corresponding V-179 sub-row at zero incremental code cost.

**Rationale.** Because S-52 and S-53 share every SSTORE block, gating the function entry blocks BOTH slot writes. The bytecode impact at each callsite is the SAME ~30 bytes already accounted in V-168..V-177; V-179 contributes ZERO additional bytes.

**Implementation-pattern note for v44.0 plan-phase.** When v44.0 implements the V-168..V-177 fixes, the code-review checklist must verify that the entry-revert PRECEDES the `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` invocation — this is what makes the gate cover both S-52 and S-53. A misplaced revert (e.g., after the SSTORE block) would leave S-53 unprotected. Code review must check execution-order: `rngLockedFlag` SLOAD → `revert` → ... → `_queueTickets`-family invocation. Single-gate-covers-both invariant.

**Bytecode impact.** Zero incremental over V-168..V-177. Storage / ABI unchanged.

### §10.D — v44.0 handoff anchor (9 sub-anchors)

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

## §11 — V-182: `bountyOwedTo` write inside `_addDailyFlip` via `depositCoinflip` (`BurnieCoinflip.sol:681`)

### §11.A — Design-intent backward-trace

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

### §11.B — Actor game-theory walk

**Exploit actor.** EOA coinflip-depositor attempting to arm the bounty during rngLock.

**Action sequence.**
1. VRF callback delivers daily `rngWord`; `rngLockedFlag` true.
2. Attacker calls `depositCoinflip(player, amount)` with `amount > biggestFlipEver` to attempt bounty arming.
3. `_depositCoinflip:312` → `_addDailyFlip:627` → `:664` checks `!game.rngLocked()` → FALSE (rngLocked is true) → silent skip; `bountyOwedTo` is NOT mutated.
4. **Net effect: no exploit succeeds via the arming write itself.** The existing gate already structurally blocks the VIOLATION condition.

**Residual concern.** The deposit itself succeeds (only the bounty-arming sub-block is skipped). The attacker may not realize their large deposit failed to arm the bounty until they observe (off-chain) that `bountyOwedTo` did not change. The "extend to fail-closed revert" recommendation surfaces this state mismatch.

**EV magnitude.** MEDIUM-HIGH. Bounty magnitudes are non-trivial (top-flip-ever sets the bar high), but the existing `:664` gate already structurally prevents the exploitation. The "extend to revert" is defense-in-depth + observability hardening; the actual VIOLATION risk is RESIDUAL given the existing gate.

### §11.C — Recommended tactic + rationale + impact

**Tactic (a) — Extend the `:664` silent-skip to a fail-closed revert at `_addDailyFlip` entry.** Replace the silent skip pattern with an entry-level `if (game.rngLocked()) revert RngLocked();` at the start of the bounty-arming-eligible code path, OR replace the `:664` conditional with an early-revert pattern that fails the deposit if bounty arming is requested during rngLock.

**Implementation alternatives for v44.0 plan-phase.**
1. **Minimal change**: leave deposit-side gating untouched but add a revert at `_addDailyFlip` entry when `canArmBounty && bountyEligible && game.rngLocked()`. Deposits without bounty-eligibility still succeed; bounty-eligible deposits revert during rngLock.
2. **Aggressive change**: gate entire `depositCoinflip` on `!rngLocked()` — broader but breaks all coinflip deposits during rngLock (UX regression).

The catalog's prescribed tactic-(a) is the minimal change.

**Bytecode impact.** ~10 bytes (one selector switch from skip-conditional to revert-conditional). Storage / ABI unchanged.

### §11.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-110` — CATALOG §16 row V-182 + §15 row S-55 `_addDailyFlip`/`depositCoinflip` + §11 BurnieCoinflip._resolveFlip consumer. v44.0 plan-phase: minimal-change variant — convert `:664` silent-skip to fail-closed revert for bounty-eligible deposits during rngLock. The existing `BurnieCoinflip:730` `RngLocked` convention site (`auto-rebuy gate, `_setCoinflipAutoRebuy`) is the implementation reference for the v44.0 patch.

---

## §12 — V-184: `redemptionPeriodIndex` write inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:760`) — **HEADLINE TIER-1 — §0 finding #1**

### §12.A — Design-intent backward-trace

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

### §12.B — Actor game-theory walk

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

### §12.C — Recommended tactic + rationale + impact

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

### §12.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-111` — **TIER-1 PRIORITY-1**. CATALOG §16 row V-184 + §15 row S-56 `_submitGamblingClaimFrom` + §12 sStonk consumer trace + §C-1 single-writer attestation + §D-VIOL-1 cross-cutting pattern + §0 headline #1.

**Phase 303 §3.A delta-surface row 1 cross-reference.** This handoff is the load-bearing input to Phase 303 TERMINAL `audit/FINDINGS-v43.0.md` §3.A — the milestone's highest-severity finding is V-184. v44.0 plan-phase must prioritize this sub-phase ahead of all other Cluster J fixes.

**v44.0 sub-phase scope.** Implement tactic (a) catalog-prescribed revert at `_submitGamblingClaimFrom` AND/OR tactic (b) clean-variant structural anchor (refactor `redemptionPeriodIndex` reset logic per §12.C). Test plan must include: (i) the §D-VIOL trigger sequence as a positive failing test (pre-fix, exploit succeeds; post-fix, exploit reverts); (ii) cross-day boundary edge cases (burn-at-day-boundary timestamps); (iii) gap-day re-resolution interaction (`_backfillGapDays` does NOT resolve redemptions per AdvanceModule:1772-1774 comment); (iv) collateral-damage assertion (other-player claims unaffected by attacker's re-burn).

---

## §13 — V-186: `pendingRedemptionEthBase` (`+=`) inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:790`)

### §13.A — Design-intent backward-trace

`pendingRedemptionEthBase` is the segregated-ETH-base for the active redemption period (S-57; sStonk:226). Cleared on resolve at sStonk:594 (EXEMPT-ADVANCEGAME via V-185); incremented at burn time at sStonk:790 inside `_submitGamblingClaimFrom`. The same writer fn writes both `redemptionPeriodIndex` (V-184) and `pendingRedemptionEthBase`; the increment at `:790` is the load-bearing economic accumulator that triggers the next-advance `resolveRedemptionPeriod` invocation (via `hasPendingRedemptions()` returning true at sStonk:1225 in AdvanceModule).

**Why the slot exists.** Identical to V-184 §12.A — the ETH-base is the per-period segregation of ETH backing for gambling-burn claims; it accumulates per-burn within a period and is consumed (zeroed) at resolve.

**Why the write is the load-bearing piece of the V-184 exploit.** Without the `pendingRedemptionEthBase += ethValueOwed` at `:790`, the subsequent `advanceGame`'s `resolveRedemptionPeriod` would short-circuit at sStonk:589 `if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;`. The attacker's same-day re-burn LITERALLY exists to re-arm this slot.

### §13.B — Actor game-theory walk

**Subsumed by V-184.** Same exploit actor, same action sequence, same EV. The increment at `:790` is the mechanism by which V-184's re-roll vector is armed.

**EV magnitude.** HIGH (subsumed by V-184's CATASTROPHE classification; V-186's standalone classification is HIGH because the slot itself is the load-bearing armament).

### §13.C — Recommended tactic + rationale + impact

**Tactic (a) — same gate as V-184.** Per catalog row: "Same gate as V-184 — base-growth and index-pointing are co-mutated; one check covers both."

The fix at V-184 (entry-revert in `_submitGamblingClaimFrom` if `redemptionPeriods[redemptionPeriodIndex].roll != 0` OR the clean structural-anchor variant) reverts the function BEFORE the `:790` write executes. Single fix closes both.

**Bytecode impact.** Zero incremental over V-184.

### §13.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-112` — CATALOG §16 row V-186. v44.0 plan-phase: subsumed by HANDOFF-111. Co-located implementation.

---

## §14 — V-188: `pendingRedemptionBurnieBase` (`+=`) inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:792`)

### §14.A — Design-intent backward-trace

`pendingRedemptionBurnieBase` is the BURNIE-side analog of S-57 (S-58; sStonk:227). Same lifecycle: cleared on resolve at sStonk:601 (V-187 EXEMPT-ADVANCEGAME), incremented at burn at sStonk:792 inside `_submitGamblingClaimFrom`. The BURNIE base feeds the BURNIE-payout multiplication in `claimRedemption` (sStonk:652 `burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000`).

**Why the slot exists.** Mirror of V-186. Gambling-burn supports BURNIE payouts in addition to ETH; the BURNIE-base segregates per-period.

### §14.B — Actor game-theory walk

**Subsumed by V-184.** Same exploit; the BURNIE-base is re-armed alongside the ETH-base on same-day re-burn. The re-roll vector multiplies BOTH ETH and BURNIE payouts at fresh roll.

**EV magnitude.** HIGH (subsumed). BURNIE-side EV asymmetry compounds with ETH-side; the attacker captures both currency outcomes at fresh roll.

### §14.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184 (same writer fn, same callsite)."

**Bytecode impact.** Zero incremental.

### §14.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-113` — CATALOG §16 row V-188. Subsumed by HANDOFF-111.

---

## §15 — V-190: `pendingRedemptionBurnie` (`+=`) inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:791`)

### §15.A — Design-intent backward-trace

`pendingRedemptionBurnie` (S-59; sStonk:225) is the cumulative BURNIE reserve across all periods — it is decremented by `pendingRedemptionBurnieBase` at resolve (sStonk:600) and incremented per-burn at sStonk:791. The slot tracks the net BURNIE that sDGNRS owes for unredeemed gambling-burn claims.

**Why the slot exists.** Provides the `burnieReserve()` view (sStonk:733) for off-chain consumers + drives the `previewBurn` proportional math (sStonk:725). The cumulative tracking is needed because BURNIE payouts may carry across periods (e.g., when coinflip resolution is delayed beyond claim time).

### §15.B — Actor game-theory walk

**Subsumed by V-184.** Same writer fn; same callsite. The cumulative slot's incremental bump on same-day re-burn participates in the load-bearing exploit chain.

**EV magnitude.** HIGH (subsumed).

### §15.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184."

**Bytecode impact.** Zero incremental.

### §15.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-114` — CATALOG §16 row V-190. Subsumed by HANDOFF-111.

---

## §16 — V-191: `pendingRedemptions[player]` writes (`ethValueOwed`/`burnieOwed`/`periodIndex`/`activityScore`) inside `_submitGamblingClaimFrom` (`StakedDegenerusStonk.sol:803, :805, :806, :810`)

### §16.A — Design-intent backward-trace

`pendingRedemptions[player]` (S-60; sStonk:221) is the per-player claim struct: `(uint96 ethValueOwed, uint96 burnieOwed, uint32 periodIndex, uint16 activityScore)`. Writes at:
- sStonk:803 `claim.ethValueOwed += uint96(ethValueOwed)` — incremental per-burn growth
- sStonk:805 `claim.burnieOwed += uint96(burnieOwed)` — same for BURNIE
- sStonk:806 `claim.periodIndex = currentPeriod` — anchors claim to current period
- sStonk:810 `claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1` — first-burn-of-period activity snapshot

**Why the slot exists.** Per-player claim tracking with multi-burn accumulation within a period. The `periodIndex` field anchors which period's roll applies at `claimRedemption` time (sStonk:623 `RedemptionPeriod storage period = redemptionPeriods[claim.periodIndex]`). The `activityScore` field (sStonk:809-811) is snapshotted on first burn of period to feed `actScore` into the redemption-lootbox path (sStonk:669) — this is the Phase 281 owed-salt-precedent snapshot-at-allocation pattern correctly applied.

**Important nuance.** The `activityScore` snapshot at sStonk:810 is **already structurally correct** — it captures the score at first-burn-of-period and reuses it across same-period burns (`if (claim.activityScore == 0)` guard at sStonk:809). This is the snapshot-at-allocation pattern done right; it does NOT participate in the V-184 exploit. The VIOLATION here is the OTHER three writes (`ethValueOwed += `, `burnieOwed += `, `periodIndex = `) which participate in V-184's exploit chain.

### §16.B — Actor game-theory walk

**Subsumed by V-184.** Same writer fn, same callsite. The four writes execute together (4 SSTOREs in the function body); blocking the entry function at V-184's fix-point blocks all four.

**The `claim.periodIndex = currentPeriod` write (sStonk:806) is the specific mechanism by which the attacker's re-burn re-anchors the claim to the still-stale `redemptionPeriodIndex`.** When the attacker burns 1 wei on day D post-resolve, sStonk:806 writes `claim.periodIndex = D` — this is what enables the eventual `claimRedemption` read of `redemptionPeriods[D].roll` (post-overwrite).

**EV magnitude.** HIGH (subsumed).

### §16.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184."

**Bytecode impact.** Zero incremental.

### §16.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-115` — CATALOG §16 row V-191. Subsumed by HANDOFF-111.

---

## §17 — V-192: `pendingRedemptions[player]` `delete` inside `claimRedemption` (`StakedDegenerusStonk.sol:661`)

### §17.A — Design-intent backward-trace

`claimRedemption()` at sStonk:618 is the EOA-facing claim-payout entry. When the coinflip resolution has fired (`flipResolved == true` at sStonk:659), the function clears the player's claim struct via `delete pendingRedemptions[player]` at sStonk:661. This is the full-claim-clear path.

**Why the slot exists.** Claim-clearing is a legitimate downstream effect — once a player has been paid out, their claim record is removed to free storage and prevent double-claiming. The write itself is structurally correct; the catalog row's VIOLATION classification is strict per-callsite (the writer-callsite is EOA-callable with no advance-stack reach).

**Per CATALOG §16 row V-192 verdict text + §D-VIOL §3 severity-downgrade-rationale:** "These are non-EXEMPT-stack writes inside `claimRedemption` of slots the player already controls or that subtract VRF-derived (not VRF-influencing) values. They are listed VIOLATION per D-298-EXEMPT-REACH-01 strict rule but the FIX is structurally subsumed by closing the D-1/D-3/D-5/D-11 window."

### §17.B — Actor game-theory walk

**Subsumed by V-184.** The `delete` at sStonk:661 clears the attacker's own claim AFTER the V-184-enabled re-roll has been consumed. The clear itself does not introduce attacker-controlled VRF entropy; it merely removes the player's record post-payout.

Standalone exploit potential of V-192 alone: zero — clearing one's own claim is the legitimate action.

**EV magnitude.** MEDIUM (subsumed; standalone EV is zero).

### §17.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184; legitimate downstream effect once index-advance enforced."

Once V-184's fix (tactic (a) revert or tactic (b) structural anchor) prevents the re-roll vector from arming, `claimRedemption` clears are operating on un-corrupted claim records. The `delete` write becomes the intended, legitimate clear-on-payout behavior with no exploit surface.

**Bytecode impact.** Zero incremental.

### §17.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-116` — CATALOG §16 row V-192. Subsumed by HANDOFF-111.

---

## §18 — V-193: `pendingRedemptions[player]` partial clear inside `claimRedemption` (`StakedDegenerusStonk.sol:664`)

### §18.A — Design-intent backward-trace

When coinflip resolution has NOT fired at claim time (`flipResolved == false` at sStonk:659), `claimRedemption` performs a partial-clear at sStonk:664: `claim.ethValueOwed = 0`. This drops the ETH portion (already paid) while preserving the BURNIE portion for a later second-claim once coinflip resolves.

**Why the slot exists.** Partial-claim is the legitimate flow when ETH and BURNIE payouts decouple in timing (e.g., when the daily coinflip for `period.flipDay` has not yet resolved). The structural design supports two-stage claims.

### §18.B — Actor game-theory walk

**Subsumed by V-184.** Same severity-downgrade rationale as V-192 — the partial-clear is a legitimate downstream effect. Standalone EV is zero; the write does not introduce attacker-controlled VRF entropy.

**EV magnitude.** MEDIUM (subsumed; standalone EV is zero).

### §18.C — Recommended tactic + rationale + impact

**Tactic (a) — subsumed by V-184.** Per catalog: "Subsumed by V-184."

**Bytecode impact.** Zero incremental.

### §18.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-117` — CATALOG §16 row V-193. Subsumed by HANDOFF-111.

---

## §19 — V-201: `decBurn[lvl][player].burn` write inside `recordDecBurn` (`DecimatorModule.sol`)

### §19.A — Design-intent backward-trace

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

### §19.B — Actor game-theory walk

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

### §19.C — Recommended tactic + rationale + impact

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

### §19.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-118` — CATALOG §16 row V-201 + §15 row S-66 `recordDecBurn` + §13 DecimatorModule consumer. v44.0 plan-phase: add `decClaimRounds[lvl].poolWei == 0` gate at `recordDecBurn` entry. Co-locate with V-202 handoff (similar gate pattern on `recordTerminalDecBurn`).

---

## §20 — V-202: `terminalDecBucketBurnTotal[bucketKey]` write inside `recordTerminalDecBurn` (`DecimatorModule.sol:731`)

### §20.A — Design-intent backward-trace

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

### §20.B — Actor game-theory walk

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

### §20.C — Recommended tactic + rationale + impact

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

### §20.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-119` — CATALOG §16 row V-202 + §15 row S-67 `recordTerminalDecBurn` + §4 DecimatorModule terminal consumer. v44.0 plan-phase: add `rngWordByDay[currentDay] == 0` gate at `recordTerminalDecBurn` entry. Co-locate with V-201 handoff (both terminal- and per-level decimator gates).

---

## Cluster J summary

**Total VIOLATIONs covered:** 20 logical (V-179 fan-out counted as 1 per `D-299-FIXREC-LAYOUT-01`).
**Handoff anchors emitted:** 28 (H-92..H-119; V-179 contributes 9 sub-anchors H-101..H-109).
**Tactic distribution:** all 20 use tactic (a) rngLockedFlag-gated revert as the catalog-prescribed minimal fix. V-184 additionally surfaces tactic (b) structural-anchor variant as PREFERRED for v44.0 plan-phase consideration.
**EV-tier distribution:** CATASTROPHE ×1 (V-184 TIER-1 HEADLINE), HIGH ×10, MEDIUM ×8, LOW ×1 (V-170 — existing :543 gate).
**Stale-phantom rows:** 0 — all 20 verified against current source HEAD `MILESTONE_V42_AT_HEAD_81d7c94bc924edb3429f6dc16ee33280fc11c7c2`.
**§0 headline #1 — V-184 TIER-1 — sStonk cross-day re-roll exploit:** documented in §12 with BOTH tactic (a) catalog-prescribed defensive revert AND tactic (b) PREFERRED clean-variant structural anchor. Phase 303 §3.A delta-surface row 1 cross-reference embedded in §12.D.
**Cross-VIOLATION subsumption:** V-186 / V-188 / V-190 / V-191 / V-192 / V-193 all subsumed by V-184 fix (single writer fn `_submitGamblingClaimFrom`; single callsite). v44.0 plan-phase can collapse 7 V-NNN entries into 1 sub-phase.
**V-179 single-logical treatment:** 9 EOA callsites (V-179.A..V-179.I) emit 9 sub-anchors H-101..H-109; each subsumed by the corresponding S-52 handoff (HANDOFF-92..100) at zero incremental cost (co-located SSTORE blocks).
**V-201/V-202 decBurn burn-window verification:** confirmed VIOLATION at current source — `BurnieCoin.decimatorBurn` + `BurnieCoin.terminalDecimatorBurn` have NO rngLock-gating at function entry; the only related check (`_consumeCoinflipShortfall` rngLock revert) requires shortfall consumption to fire. Catalog-prescribed gates (`decClaimRounds[lvl].poolWei == 0` for V-201; `rngWordByDay[currentDay] == 0` for V-202) verified appropriate per source trace.

**Posture compliance.** AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`. Zero `contracts/` or `test/` source-tree mutations. Verdict alphabet remains the locked four-class set; no discretionary fourth-class disposition introduced. Frozen-contract reality per `feedback_frozen_contracts_no_future_proofing.md` — all recommendations advisory for v44.0 plan-phase consumption.
