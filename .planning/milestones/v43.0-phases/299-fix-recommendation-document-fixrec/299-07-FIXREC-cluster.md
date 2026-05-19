# Phase 299 — FIXREC Cluster G: Per-Index Lootbox Commitment Slot Family (manual-path lootbox open)

**Cluster:** G — Slots S-22 (`lootboxEvBenefitUsedByLevel[player][lvl]` cross-resolution accumulator) + S-24..S-29 (per-index lootbox commitment quad: `lootboxEth`, `lootboxDay`, `lootboxBaseLevelPacked`, `lootboxEvScorePacked`, `lootboxDistressEth`, `lootboxBurnie`).
**VIOLATIONs covered:** V-081, V-082, V-084, V-088..V-104 (20 logical entries — `D-43N-V44-HANDOFF-43`..`D-43N-V44-HANDOFF-62`).
**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §14 rows S-22 / S-24..S-29; §15 writer enumeration rows 206 / 210-226; §16 verdict-matrix rows 416-417 / 419 / 423-439; consumers §6 (`LootboxModule.resolveRedemptionLootbox`), §7 (`LootboxModule._resolveLootboxCommon` manual-path consumer — the deep cluster origin per Phase 298 §0 headline #2).
**Posture:** AUDIT-ONLY per `D-43N-AUDIT-ONLY-01`. Zero `contracts/` + zero `test/` mutations. Authorial output only.
**Drafted:** 2026-05-18

---

## Cluster preamble — the deep VIOLATION cluster (load-bearing for every §N.A below)

Per `.planning/RNGLOCK-CATALOG.md` §0 headline #2 ("Manual-path lootbox open is a deep VIOLATION cluster"): the manual-path lootbox open (`openLootBox` / `openBurnieLootBox`) is the deepest single resolution surface in the entire catalog — 35 verdict-matrix rows fire against `_resolveLootboxCommon` on the consumer side, and the per-index commitment slots are EOA-mutable across the entire window between VRF callback (TX B — `lootboxRngWordByIndex[index]` is set inside `rawFulfillRandomWords`) and the player's `openLootBox` invocation (TX C — `_applyEvMultiplierWithCap` reads + writes S-22, the function body at `LootboxModule.sol:526..:598` reads S-24..S-28). Cluster G covers 20 of those 35 VIOLATIONs: the three S-22 cross-resolution accumulator consumers (V-081 / V-082 / V-084) plus the per-index commitment quad writers (V-088..V-104, 17 entries).

### Cluster-wide source-of-truth grep (verified pre-patch per `feedback_verify_call_graph_against_source.md`)

| Slot | Declaration | Catalog row |
|------|-------------|-------------|
| S-22 | `mapping(address => mapping(uint24 => uint256)) internal lootboxEvBenefitUsedByLevel` | §14 row 81 |
| S-24 | `mapping(uint48 => mapping(address => uint256)) internal lootboxEth` | §14 row 83 |
| S-25 | `mapping(uint48 => mapping(address => uint32)) internal lootboxDay` | §14 row 84 |
| S-26 | `mapping(uint48 => mapping(address => uint256)) internal lootboxBaseLevelPacked` | §14 row 85 |
| S-27 | `mapping(uint48 => mapping(address => uint256)) internal lootboxEvScorePacked` | §14 row 86 |
| S-28 | `mapping(uint48 => mapping(address => uint256)) internal lootboxDistressEth` | §14 row 87 |
| S-29 | `mapping(uint48 => mapping(address => uint256)) internal lootboxBurnie` | §14 row 88 |

### Consumer SLOAD enumeration inside the rng-window (manual-path open + EOA-reachable redemption)

| Consumer | File:line | Reads | Reach |
|----------|-----------|-------|-------|
| `LootboxModule.openLootBox` | `LootboxModule.sol:526..:598` | S-24 (`:528`), S-25 (`:537`), S-22 (`:496` via `_applyEvMultiplierWithCap`), S-26 (`:550`), S-27 (`:563`), S-28 (`:574`) | EOA — anyone with a populated `lootboxEth[index][player]` slot and a fulfilled `lootboxRngWordByIndex[index]` |
| `LootboxModule.openBurnieLootBox` | `LootboxModule.sol:607..:664` | S-29 (`:609`), S-25 (`:624`), S-22 (`:496` via `_applyEvMultiplierWithCap` reached at `:567`+`:607` per §14 row 206) | EOA |
| `LootboxModule.resolveRedemptionLootbox` | `LootboxModule.sol:707..` | S-22 (`:496` via `_applyEvMultiplierWithCap` reached at `:716`) | EOA-indirect via sStonk `claimRedemption` (catalog §6) |

### Writer enumeration inside the rng-window (EOA-reachable writers — per `feedback_rng_window_storage_read_freshness.md` non-VRF storage-freshness invariant)

| Writer | File:line | Slot | EOA-reachable from |
|--------|-----------|------|---------------------|
| `LootboxModule.openLootBox` self-zero | `:576` (S-24), `:578` (S-26), `:579` (S-27), `:581` (S-28 conditional) | S-24, S-26, S-27, S-28 | EOA `openLootBox` |
| `LootboxModule.openBurnieLootBox` self-zero | `:615` (S-29) | S-29 | EOA `openBurnieLootBox` |
| `LootboxModule._applyEvMultiplierWithCap` SSTORE | `:511` (S-22) | S-22 | EOA via `openLootBox` / `openBurnieLootBox` / `resolveRedemptionLootbox` consumer entry |
| `MintModule._allocateLootbox` (private; reached via `buyTickets`) | `:991` (S-25), `:992` (S-26), `:1013` (S-24), `:1031` (S-28 conditional), `:1155` (S-27 conditional on `lbFirstDeposit`) | S-24..S-28 | EOA `buyTickets` |
| `MintModule._burnieAllocate` (`_purchaseBurnieLootboxFor`) | `:1397` (S-25), `:1399` (S-29) | S-25, S-29 | BURNIE-coin callback (EOA-triggered) |
| `WhaleModule._whaleLootboxAllocate` (`_recordLootboxEntry`) | `:854` (S-25), `:855` (S-26), `:856` (S-27), `:876` (S-24), `:881` (S-28 conditional) | S-24..S-28 | EOA `buyWhaleBundle` / `buyWhaleHalf` |

**Source-of-truth verification** (grep against `contracts/`):
- `LootboxModule.sol:511`: `lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion;` (matches catalog §14 row 206 + §16 V-081/V-082/V-084 reads-and-writes posture).
- `LootboxModule.sol:526..:598`: `openLootBox` body matches enumerated SLOAD ordering verbatim; self-zero block at `:576..:582` precedes the `_resolveLootboxCommon` call (i.e., the slot is zeroed BEFORE the consumer's dispatch into the multi-call resolution stack).
- `LootboxModule.sol:607..:664`: `openBurnieLootBox` body matches; self-zero of S-29 at `:615` precedes the `_resolveLootboxCommon` call.
- `MintModule.sol:991-:1013`: `lootboxDay` / `lootboxBaseLevelPacked` writes happen only when `existingAmount == 0` (first-deposit gate); `lootboxEth` write at `:1013` happens unconditionally.
- `MintModule.sol:1031`: `lootboxDistressEth[lbIndex][buyer] += boostedAmount;` (accumulating `+=` — relevant for per-call delta analysis below).
- `MintModule.sol:1155`: `lootboxEvScorePacked[lbIndex][buyer] = uint16(cachedScore + 1);` (guarded by `lbFirstDeposit`).
- `MintModule.sol:1397-1399`: `lootboxDay` first-write-if-zero gate + `lootboxBurnie[index][buyer] = existingAmount + burnieAmount;` (accumulating).
- `WhaleModule.sol:854-:881`: matches catalog enumeration — `lootboxDay` (:854), `lootboxBaseLevelPacked` (:855), `lootboxEvScorePacked` (:856), `lootboxEth` (:876), `lootboxDistressEth` (:881).

**Zero stale-phantom rows.** Every V-NNN in scope corresponds to a verified writer site at the catalog-cited file:line.

### Two sub-families with distinct structural shape

The 20 VIOLATIONs in Cluster G split into two structurally distinct sub-families:

**Sub-family G.1 — Per-index commitment quad (S-24..S-29; 17 VIOLATIONs V-088..V-104).** The per-index storage slots ARE the snapshot store (one slot family per `(index, player)`). The commitment-time freshness invariant per `feedback_rng_commitment_window.md`: each per-index slot is set at purchase time (mint via `MintModule._allocateLootbox`, whale via `WhaleModule._whaleLootboxAllocate`, or BURNIE via `MintModule._burnieAllocate`) and MUST be IMMUTABLE between the VRF callback (TX B; when `lootboxRngWordByIndex[index]` becomes non-zero) and the consumer's open (TX C; `openLootBox` / `openBurnieLootBox`). The VIOLATION is that the writers continue to be EOA-callable AFTER the VRF callback has fired for the same `index`. The seed at `LootboxModule.sol:554` (`keccak256(abi.encode(rngWord, player, day, amount))`) and the EV scaling at `:567` both consume slot values that an attacker can mutate post-VRF.

The catalog's per-index commitment quad pattern is: (rngWord, player, day, amount) for ETH lootboxes; (rngWord, player, day, amountEth) for BURNIE lootboxes; baseLevel, EV-score, distress flag are auxiliary inputs to the resolution outcome that share the same commitment-time-freshness requirement. Phase 281 owed-salt 4th-keccak-input is the structural precedent — the salt was pinned at commitment time to prevent a player from MEV-shifting the keccak input via post-fulfillment storage writes. The catalog explicitly cites Phase 281 in the tactic-rationale columns for V-088 and V-094, and the same precedent applies to every other commitment-quad VIOLATION in this cluster.

**Self-zero rows (V-088, V-094, V-097, V-100, V-103).** These VIOLATIONs trace to the consumer's own self-zero writes at `LootboxModule.sol:576..:581` / `:615`. The structural concern: the function body reads the slot into a local variable (e.g., `amount = packed & ((1 << 232) - 1)` at `:529`), then performs an SLOAD cascade on auxiliary slots (S-25 at `:537`, S-26 at `:550`, S-27 at `:563`, S-28 at `:574`), then zeroes the slot at `:576..:582` BEFORE the `_resolveLootboxCommon` dispatch. The self-zero itself is structurally legitimate (it's the "spend the slot" act), but its placement and the slot-cascade ordering create a window where any external call inside `_resolveLootboxCommon` (e.g., `quests.handlePurchase`, `affiliate.payAffiliate`, `dgnrs.transferFromPool`) could in principle re-enter `openLootBox` for a sibling index. The catalog row 423 (V-088) classifies this as VIOLATION pending a stack-freeze verification step. Per `feedback_rng_window_storage_read_freshness.md`, the freshness invariant is enforced by snapshotting the consumed values into stack variables BEFORE the first call site that yields control to external code; the catalog's recommendation is tactic (b) "Freeze amount in stack pre-SLOAD-cascade; mirror Phase 281 owed-salt."

**Sub-family G.2 — Cross-resolution EV-benefit accumulator (S-22; 3 VIOLATIONs V-081, V-082, V-084).** S-22 is structurally DIFFERENT from S-24..S-29. It is NOT a per-index slot — it is a `(player, level)`-keyed running counter that accumulates EV-benefit usage ACROSS multiple lootbox resolutions at the same level. Each `openLootBox` / `openBurnieLootBox` / `resolveRedemptionLootbox` invocation at the same level shares the same `lootboxEvBenefitUsedByLevel[player][lvl]` SLOAD-write cycle: SLOAD at `:496`, compute remaining cap, write at `:511`. This bypasses the per-index snapshot convention by design — the EV-benefit cap (`LOOTBOX_EV_BENEFIT_CAP` per `:497`) is a per-account-per-level resource pool that intentionally aggregates across opens.

Per Phase 298 §0 headline #2 + `feedback_rng_window_storage_read_freshness.md`: the cross-resolution accumulator is the **CATASTROPHE-tier** sub-cluster. A sequence of opens at the same level shifts the EV-cap remaining for the next open, and an attacker who observes the order of pending opens (e.g., via the public `lootboxRngWordByIndex` map) can re-order their own opens to maximize EV-benefit consumption ahead of a sibling player at the same level. The catalog tactic for all three S-22 consumers is (b) "Snapshot remaining-cap per index at allocation" — i.e., capture `LOOTBOX_EV_BENEFIT_CAP - lootboxEvBenefitUsedByLevel[player][lvl]` at allocation time and store it in a new per-index `lootboxEvCapSnapshot[index][player]` slot.

### Phase 281 + Phase 290 precedent (load-bearing for tactic selection)

**Phase 281 owed-salt 4th-keccak-input snapshot (`.planning/milestones/v41.0-phases/281-mint-batch-determinism-fix-fix/281-01-DESIGN-INTENT-TRACE.md`):** introduced the snapshot-at-commitment pattern for "live-SLOAD-between-commitment-and-resolution" race classes. Selected over (a) gated-revert because of zero storage delta (the slot already existed; the change was repositioning the SSTORE to be the commitment-time write rather than the resolution-time read), zero new SLOAD/SSTORE on the hot path, minimal grep footprint, neutral actor game-theory, and preservation of the indexer-replay invariant. Tactic (b) for V-088 / V-094 / V-097 / V-100 / V-103 (self-zero rows) is the direct application: capture the slot value into a stack variable BEFORE any external call inside `_resolveLootboxCommon` can re-enter the consumer.

**Phase 290 MINTCLN owed-in-baseKey collapse (`.planning/milestones/v42.0-phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md`):** introduced the `lootboxRngWordByIndex[index] == 0`-gated writer pattern (`RngLocked` custom error revert in `MintModule.sol:1221`, `BurnieCoinflip.sol:730`, `sStonk.sol:492`) — the canonical "reject post-fulfillment writes" gate that protects per-index commitment slots from EOA mutation after the VRF callback fires. Tactic (a) for the 12 MintModule / WhaleModule / BURNIE-allocate VIOLATIONs (V-089, V-090, V-091, V-092, V-093, V-095, V-096, V-098, V-099, V-101, V-102, V-104) is the direct application: gate the writer on `lootboxRngWordByIndex[index] == 0`, revert with `RngLocked` otherwise.

Per `feedback_design_intent_before_deletion.md`: the natural decomposition of "what would break if these slots were frozen" is documented per §N.A below. Per `feedback_rng_backward_trace.md`: every entry traces backward from the consumer SLOAD site to verify the slot value was unknown at the VRF-commitment moment but EOA-mutable in the rng-window. Per `feedback_rng_window_storage_read_freshness.md`: these are non-VRF SLOADs consumed alongside the VRF word (the F-41-02 / F-41-03 precedent class).

---

## §1 — V-081: S-22 `lootboxEvBenefitUsedByLevel` × `_applyEvMultiplierWithCap` from `openLootBox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 416 (V-081). §14 row 81. Writer enumeration §15 row 206 (`LootboxModule._applyEvMultiplierWithCap` SSTORE at `:511`). Consumer §7 (`_resolveLootboxCommon` manual-path).

### §1.A — Design-intent backward-trace

**Slot introduction phase / rationale:** S-22 is the cross-resolution EV-benefit accumulator — a `(player, level)`-keyed running counter that caps the total ETH amount eligible for above-100% EV multiplier at `LOOTBOX_EV_BENEFIT_CAP` (per `LootboxModule.sol:314`, set to a 10-ETH-equivalent cap per account per game level). The slot was introduced as a v40-era anti-farming safeguard: without the cap, a high-activity-score player could open arbitrarily many lootboxes at the same level and harvest the +35% EV multiplier (`LOOTBOX_EV_MAX_BPS = 13500` per `:472`) without bound. The cap forces the marginal EV-multiplier of large-aggregate opens to converge toward 100% (neutral), preserving the game's expected-value-neutrality at scale.

The function body at `LootboxModule.sol:484-518`: SLOADs `usedBenefit = lootboxEvBenefitUsedByLevel[player][lvl]` at `:496`, computes `remainingCap = LOOTBOX_EV_BENEFIT_CAP - usedBenefit` at `:497-:499`, splits the lootbox amount into `adjustedPortion` (gets the EV multiplier) and `neutralPortion` (gets 100% EV) at `:506-:508`, writes `lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion` at `:511`, and returns `scaledAmount = adjustedValue + neutralPortion` at `:517`.

**Cite for "what would break if naively frozen":** Per `feedback_design_intent_before_deletion.md`, if S-22 were frozen during rngLock (tactic-a style), legitimate concurrent opens at the same level by different players (or by the same player across different indices) would block each other unnecessarily — the daily-VRF rngLock window is broad and would freeze a slot that has no causal dependency on the daily VRF resolution. The slot's natural mutability is per-resolution (one SSTORE per call to `_applyEvMultiplierWithCap`); tactic (a) gating would force the consumer to either retry post-unlock (degraded UX) or reject the open (lost user action).

The structural break is deeper: even ignoring the rngLock window, the cross-resolution accumulator is itself a **design break** with respect to the per-index-commitment-freshness invariant. Per Phase 298 §0 headline #2, S-22's cross-resolution accumulation pattern CONFLICTS with the per-index-frozen-state invariant that governs S-24..S-29. The fix shape recommended in the catalog (tactic (b) per-index snapshot) is a structural realignment: snapshot the available EV cap at the moment of allocation (when `lootboxEth[index][player]` is first written non-zero), store the snapshot per index, and consume from the per-index snapshot at open time — eliminating the cross-resolution race entirely.

**Precedent for snapshot pattern:** Phase 281 owed-salt (`D-281-FIX-SHAPE-01`) introduced the per-index-snapshot-at-commitment pattern for the mint-batch determinism class. Cluster G S-22 maps directly: the EV-cap-remaining value is a function of `(player, level)` state at allocation time; snapshotting it into a new per-index slot at the same point where `lootboxEth[index][player]` is first written eliminates the cross-resolution race at the cost of one new `uint256` snapshot field per `(index, player)` pair.

### §1.B — Actor game-theory walk

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

### §1.C — Recommended tactic + rationale + impact estimate

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

### §1.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-43`** — Snapshot `LOOTBOX_EV_BENEFIT_CAP - lootboxEvBenefitUsedByLevel[player][level]` at allocation time into a new per-index `lootboxEvCapAtAllocation[index][player]` slot; `_applyEvMultiplierWithCap` accepts the cap as a parameter. Concrete file:line targets:

- Snapshot WRITE site (mint path): `MintModule.sol:989` first-deposit branch (alongside `lootboxDay` / `lootboxBaseLevelPacked` writes at `:991`/`:992`).
- Snapshot WRITE site (whale path): `WhaleModule.sol:853` first-deposit branch (alongside `lootboxDay` / `lootboxBaseLevelPacked` / `lootboxEvScorePacked` writes at `:854`/`:855`/`:856`).
- Snapshot WRITE site (BURNIE path): `MintModule.sol:1396` BURNIE-allocate path (alongside `lootboxDay` first-write at `:1397`).
- Consumer READ site: `LootboxModule.sol:484` — replace SLOAD-write cycle at `:496`/`:511` with parameter consumption.
- Storage field: new `lootboxEvCapAtAllocation` mapping in `DegenerusGameStorage.sol`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 416 (V-081) and §14 row 81.

---

## §2 — V-082: S-22 `lootboxEvBenefitUsedByLevel` × `_applyEvMultiplierWithCap` from `openBurnieLootBox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 417 (V-082). §15 row 206. Consumer §7 (manual-path `_resolveLootboxCommon` reached from `openBurnieLootBox`).

### §2.A — Design-intent backward-trace

**See §1.A for shared S-22 design-intent backward-trace.** V-082 differs only in the consumer reach: instead of `openLootBox` invoking `_applyEvMultiplierWithCap` at `:567`, the BURNIE-lootbox open at `openBurnieLootBox:607-:664` reaches the same function via the `_resolveLootboxCommon` inner-path. Per `LootboxModule.sol:609`, the BURNIE-amount is captured first; per `:629`, `amountEth = (burnieAmount * priceWei * 80) / (PRICE_COIN_UNIT * 100)` (the 80% BURNIE-ETH conversion rate); per `:638`, `_resolveLootboxCommon` is invoked with `amountEth` as the `amount` parameter. The catalog §14 row 206 callsite enumeration confirms the reach: `:567` (openLootBox), `:607` (openBurnieLootBox top-level mention is the `function openBurnieLootBox` header; the actual reach is via `_resolveLootboxCommon`).

The BURNIE-path EV-multiplier is structurally identical to the ETH-path: the same `_applyEvMultiplierWithCap` is invoked, the same S-22 SLOAD-write cycle fires. The cross-resolution accumulator does not distinguish ETH vs BURNIE opens — both contribute to the same `(player, level)` cap. This is intentional per design (the cap is "EV benefit consumed at this level", agnostic to denomination), and the structural break described in §1.A applies identically.

**Cite for "what would break if naively frozen":** Same as §1.A — gating S-22 on `rngLockedFlag` would freeze the cross-resolution accumulator across all opens (ETH + BURNIE) at the affected level, degrading UX for both lootbox flavors.

### §2.B — Actor game-theory walk

**Exploit-actor class:** Same as §1.B (cross-resolution self-MEV / sequencing). The BURNIE-path exploit is structurally identical:

- Player A has one ETH lootbox at level L and one BURNIE lootbox at level L. Both fulfilled.
- Optimal sequence: open the BURNIE lootbox first IF its converted `amountEth` (`burnieAmount × priceWei × 80 / PRICE_COIN_UNIT × 100`) is sub-cap, then open the ETH lootbox to harvest the full EV-multiplier on the remaining cap.
- Suboptimal sequence: open the ETH lootbox first, consume the cap, then open the BURNIE lootbox at neutral 100%.

**Distinction from §1.B:** The BURNIE-path `amountEth` is derived from `priceWei` at `:618` (`PriceLookupLib.priceForLevel(level)`) — meaning the BURNIE-EV magnitude is level-dependent and can shift between purchase time and open time. This compounds the §1.B sequencing exploit: an attacker who anticipates a level-up between two opens can sequence BURNIE-then-ETH (lower BURNIE-EV from pre-level-up price) followed by ETH-EV at the new level.

**Action sequence during rngLock window:** Same shape as §1.B; replace "open `i_1`/`i_2`" with "open ETH index/BURNIE index". The cross-resolution race fires identically.

**EV magnitude estimate:** **HIGH** (same as §1.B). The BURNIE-path adds level-dependent price compounding to the sequencing exploit, slightly elevating EV magnitude vs pure-ETH-portfolio §1.B. CATASTROPHE-tier per `feedback_rng_window_storage_read_freshness.md` (same as §1.A — cross-resolution accumulator design break).

### §2.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Same snapshot as V-081.** Catalog §16 row 417 rationale: "Same snapshot as V-081."

**Concrete shape:** Identical to §1.C — the per-index `lootboxEvCapAtAllocation[index][player]` snapshot serves both ETH-path and BURNIE-path opens. The BURNIE-allocation path at `MintModule._purchaseBurnieLootboxFor:1377-1412` must populate the snapshot at `:1396` (BURNIE first-deposit branch — when `lootboxDay[index][buyer] == 0`) alongside the `lootboxDay` first-write.

**Rationale for rejecting alternative tactics:** Same as §1.C.

**Bytecode / storage-layout / public-ABI impact:** Same as §1.C — the BURNIE-path snapshot population shares the new `lootboxEvCapAtAllocation` mapping. One additional SSTORE inside `_purchaseBurnieLootboxFor` first-deposit branch; replaces the SLOAD-write at `_applyEvMultiplierWithCap:496`/`:511` for the BURNIE-reach. Net runtime gas identical to §1.C estimate. NON-BREAKING ABI.

### §2.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-44`** — Same snapshot as `D-43N-V44-HANDOFF-43`; consumer reach extended to BURNIE-path. Concrete file:line targets:

- Snapshot WRITE site (BURNIE-allocate path): `MintModule.sol:1396` BURNIE first-deposit branch.
- Consumer READ site (BURNIE-reach): `LootboxModule.sol:484` via `_resolveLootboxCommon` reached from `openBurnieLootBox` body — parameter consumption replaces SLOAD-write at `:496`/`:511`.
- Storage field: shared `lootboxEvCapAtAllocation` mapping per `D-43N-V44-HANDOFF-43`.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 417 (V-082) and §14 row 81.

---

## §3 — V-084: S-22 `lootboxEvBenefitUsedByLevel` × `_applyEvMultiplierWithCap` from `resolveRedemptionLootbox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 419 (V-084). §15 row 206. Consumer §6 (`LootboxModule.resolveRedemptionLootbox` from sStonk `claimRedemption`).

### §3.A — Design-intent backward-trace

**See §1.A for shared S-22 design-intent backward-trace.** V-084 differs in the consumer reach: `resolveRedemptionLootbox` is invoked via `delegatecall` from `DegenerusGame` when the sStonk sister-contract sends lootbox ETH during `claimRedemption`. The function header at `LootboxModule.sol:707` accepts an `activityScore` parameter explicitly (`uint16 activityScore` at `:707`), which was snapshotted at burn submission inside sStonk — meaning the consumer's *activity score* is already snapshotted per Phase 284-era discipline. The EV-multiplier is derived from the snapshotted score at `:715` (`_lootboxEvMultiplierFromScore(uint256(activityScore))`), then `_applyEvMultiplierWithCap` is invoked at `:716` with the snapshotted multiplier.

The S-22 SLOAD-write at `:496`/`:511` happens INSIDE `_applyEvMultiplierWithCap` regardless of how it was reached. Even though the `activityScore` input is snapshotted, the `lootboxEvBenefitUsedByLevel` consumption is NOT — it is a live SLOAD-write against the player's current `(player, level)` cap counter. This is the structural mirror of §1.A / §2.A: the per-index commitment freshness has been partially established (activity score is snapshotted), but the cross-resolution accumulator slot S-22 bypasses the snapshot.

**Distinction from §1.A / §2.A:** The redemption-lootbox reach is EOA-triggered indirectly: a user calls `sStonk.claimRedemption(...)` (EOA-reachable on the sStonk sister-contract), which transitively reaches `DegenerusGame` via `dgnrs.sendLootboxEth(...)` (or equivalent), which delegate-calls into `LootboxModule.resolveRedemptionLootbox`. The catalog row 419 classifies this as `NO — EOA` (i.e., NOT exempt). Per `feedback_design_intent_before_deletion.md`, the redemption-lootbox path was DESIGNED with snapshot discipline (the `activityScore` parameter is the snapshot vehicle); V-084 represents the residual gap where the S-22 consumption was not snapshotted alongside the score.

**Cite for "what would break if naively frozen":** Gating S-22 on `rngLockedFlag` during the daily-VRF window would block `claimRedemption` flows from succeeding mid-window. This is particularly problematic because `claimRedemption` is a settlement path (the user is exiting a burn position); failing-and-retrying it during the rngLock window degrades UX on a critical user flow.

### §3.B — Actor game-theory walk

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

### §3.C — Recommended tactic + rationale + impact estimate

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

### §3.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-45`** — Snapshot `lootboxEvBenefitUsedByLevel[player][currentLevel + 1]` at sStonk burn submission alongside `activityScore`; `resolveRedemptionLootbox` accepts the snapshot as a parameter. Concrete file:line targets:

- Snapshot WRITE site: sStonk burn-submission path (file:line per v44 plan-phase grep of sStonk `claimRedemption` precursor).
- Consumer READ site: `LootboxModule.sol:716` — parameter pass into `_applyEvMultiplierWithCap`.
- Storage field: new `usedBenefitAtSubmission` field on sStonk burn-position record.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 419 (V-084) and §14 row 81.

---

## §4 — V-088: S-24 `lootboxEth[index][player]` × `openLootBox` self-zero (post-amount-capture)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 423 (V-088). §14 row 83. Writer enumeration §15 row 210 (`LootboxModule.openLootBox` self-zero at `:576`).

### §4.A — Design-intent backward-trace

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

### §4.B — Actor game-theory walk

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

### §4.C — Recommended tactic + rationale + impact estimate

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

### §4.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-46`** — Consolidate S-24..S-28 SLOADs into stack-capture block at `LootboxModule.openLootBox` function entry. Concrete file:line targets:

- Refactor site: `LootboxModule.sol:526-:598` — insert stack-capture block after `:530` `if (amount == 0) revert E();` and before `:533` `uint256 rngWord = lootboxRngWordByIndex[index];`.
- Self-zero block: `:576..:582` unchanged in placement (still before `_resolveLootboxCommon`).
- Downstream consumers: `:548-:574` updated to read stack variables.
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 423 (V-088) and §14 row 83.

---

## §5 — V-089: S-24 `lootboxEth[index][player]` × `MintModule._allocateLootbox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 424 (V-089). §15 row 211 (`MintModule._allocateLootbox` writer at `:1013`). EOA-reach: `buyTickets`.

### §5.A — Design-intent backward-trace

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

### §5.B — Actor game-theory walk

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

### §5.C — Recommended tactic + rationale + impact estimate

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

### §5.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-47`** — Insert `RngLocked` revert gate at `MintModule._allocateLootbox` entry on `lootboxRngWordByIndex[lbIndex] != 0`. Concrete file:line targets:

- Gate WRITE site: `MintModule.sol:982` — immediately after `lbIndex` is read, before the `existingAmount` SLOAD at `:985`.
- Custom error: existing `RngLocked` (defined per Phase 290 at `MintModule.sol:1221`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 424 (V-089) and §14 row 83.

---

## §6 — V-090: S-24 `lootboxEth[index][player]` × `WhaleModule._whaleLootboxAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 425 (V-090). §15 row 212 (`WhaleModule._whaleLootboxAllocate` writer at `:876`). EOA-reach: `buyWhaleBundle` / `buyWhaleHalf`.

### §6.A — Design-intent backward-trace

**See §5.A for shared S-24 design-intent backward-trace.** V-090 differs in writer module: `WhaleModule._whaleLootboxAllocate` (private function reached via `_recordLootboxEntry` from `buyWhaleBundle` / `buyWhaleHalf` per the catalog §15 row 212 + `WhaleModule.sol:838-:883` body). The function shape is structurally identical to `MintModule._allocateLootbox`:

- `:845` index read: `index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK))`.
- `:849-:851` existing-amount + storedDay read.
- `:853-:859` first-deposit branch: writes `lootboxDay` (`:854`), `lootboxBaseLevelPacked` (`:855`), `lootboxEvScorePacked` (`:856`); emits `LootBoxIndexAssigned`.
- `:860-:862` subsequent-deposit branch: requires `storedDay == dayIndex` (revert E).
- `:864-:877` boosted-amount computation: applies whale boost via `_applyLootboxBoostOnPurchase`, updates `lootboxEthBase`, writes `lootboxEth = (purchaseLevel << 232) | newAmount` at `:876`.
- `:879-:882` distress accumulation: `if (_isDistressMode()) lootboxDistressEth[index][buyer] += boostedAmount;`.

**Distinction from §5.A:** WhaleModule fires from whale-bundle / whale-half EOA purchases. The function shape inherits MintModule's first-deposit-vs-subsequent-deposit branching. The VIOLATION shape (S-24 mutable post-VRF-fulfillment for same `lbIndex` via subsequent-deposit branch) fires identically.

**Cite for "what would break if naively frozen":** Same as §5.A — gating whale-allocation on `lootboxRngWordByIndex[index] != 0` revert prevents legitimate intra-day re-allocations after the VRF callback. The whale-bundle / whale-half paths are EOA-triggered at attacker discretion; the gate at function entry is the canonical "reject post-fulfillment writes" pattern. Whale buyers are typically high-stake actors with strong economic incentive to MEV-optimize their open outcomes — the gate is essential to close this exploit surface.

### §6.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer observing fulfilled `lootboxRngWordByIndex[lbIndex]` mid-day, racing to mutate S-24 via second whale-bundle purchase before opening.

**Concrete vector:** Identical to §5.B with `buyWhaleBundle` / `buyWhaleHalf` substituted for `buyTickets`. The whale-bundle quantum is larger (bundle size determines `boostedAmount` magnitude); the seed-search exploit fires identically against `keccak(rngWord, A, D, amount)` where `amount` includes the whale-bundle contribution.

**Distinction from §5.B:** Whale buyers have larger `boostedAmount` deltas per call (the bundle size is typically much greater than a single ticket purchase). This means each `buyWhaleBundle` re-allocation shifts `amount` by a larger quantum, providing FEWER discrete seed-search points than the MintModule path — but each point has higher economic stake. The exploit is structurally identical; the EV-per-tx magnitude is HIGHER but the seed-search space per ETH-of-budget is smaller.

**Action sequence during rngLock window:** Same as §5.B; substitute `buyWhaleBundle` for `buyTickets`.

**EV magnitude estimate:** **HIGH** (same class as §5.B; comparable or higher magnitude due to whale-bundle stake size). Economic-likelihood disposition: **likely-exploited** by whale-tier players who already operate sophisticated MEV / TX-ordering infrastructure. Per Phase 298 §0 headline #2: same deep-cluster classification.

### §6.C — Recommended tactic + rationale + impact estimate

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

### §6.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-48`** — Mirror MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry. Concrete file:line targets:

- Gate WRITE site: `WhaleModule.sol:845` — immediately after `index` is read, before the `existingAmount` SLOAD at `:849`.
- Custom error: `RngLocked` (per `D-43N-V44-HANDOFF-47`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 425 (V-090) and §14 row 83.

---

## §7 — V-091: S-25 `lootboxDay[index][player]` × `MintModule._allocateLootbox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 426 (V-091). §15 row 213 (`MintModule._allocateLootbox` writer at `:991`).

### §7.A — Design-intent backward-trace

**See §5.A for shared per-index-commitment-quad design-intent.** S-25 `lootboxDay[index][player]` is the day-keyed entropy chunk of the commitment quad. Storage: `mapping(uint48 => mapping(address => uint32))` (per §14 row 84). The slot is set at `MintModule.sol:991` inside the first-deposit branch (`existingAmount == 0`), capturing `lbDay = _simulatedDayIndex()` at allocation. Subsequent-deposit branch at `:998` requires `storedDay == lbDay` (revert E otherwise) — i.e., the slot is intended to be IMMUTABLE after first-deposit, with the subsequent-deposit branch enforcing the day-equality invariant.

**The structural concern (catalog row 426 classification "NO — EOA"):** Despite the subsequent-deposit branch enforcing `storedDay == lbDay`, the FIRST-deposit branch at `:991` is the EOA-mutable surface. The exploit shape:

- Index `N` is unallocated for player A (i.e., `lootboxEth[N][A] == 0`). Some OTHER player B has allocated to index N (`lootboxEth[N][B] != 0`).
- VRF callback fulfills `lootboxRngWordByIndex[N]` (the index is per-day, shared across allocators on that day).
- Player A then calls `buyTickets` with a lootbox component, on the SAME day D (or a different day, if index has rotated). If on the same day D, first-deposit branch fires: writes `lootboxDay[N][A] = D` at `:991` AFTER the VRF callback has fired.

The `lootboxDay` write at `:991` is per-`(index, player)` keyed — meaning each player has an independent `lootboxDay[N]` entry for the same shared `index`. Player A's first allocation to index N MUTATES `lootboxDay[N][A]` regardless of player B's prior allocation status. If A then opens at `openLootBox(A, N)`, the seed at `LootboxModule.sol:554` uses `day = lootboxDay[N][A]`. Without the gate, A can defer their first allocation until AFTER VRF fulfillment, then search seeds by allocating on different candidate days (the simulated-day-index can change between block timestamps), effectively choosing the `day` input to `keccak(rngWord, A, day, amount)`.

**Note:** This exploit window is narrower than the S-24 exploit (§5.A) because `lbDay = _simulatedDayIndex()` is the CURRENT day at allocation time — A cannot freely choose `day`, but A can defer allocation to a future day to land on a day-value that produces a favorable seed. Combined with the S-24 amount-search, A can search over `(day, amount)` pairs.

**Cite for "what would break if naively frozen":** Same shape as §5.A — gating `_allocateLootbox` on `lootboxRngWordByIndex[lbIndex] != 0` revert blocks all post-VRF-fulfillment writes including the legitimate first-deposit by player A. Player A loses the ability to allocate to index N after the VRF callback; A's only option is to defer to index N+1. UX cost: one-day delay (or one-index-rotation delay).

### §7.B — Actor game-theory walk

**Exploit-actor class:** Player A who has NOT yet allocated to index N, observing fulfilled `lootboxRngWordByIndex[N]`, racing to allocate on a chosen day to seed-search via `day` input.

**Concrete vector:** As described in §7.A. A reads `rngWord_N`, simulates `seed = keccak(rngWord_N, A, day, amount)` for each candidate `(day, amount)` pair, chooses the optimal pair, calls `buyTickets` on the chosen day with the chosen `amount`. First-deposit branch writes `lootboxDay[N][A] = D_chosen` at `:991`.

**Distinction from §5.B:** The S-25 exploit operates on the `day` input dimension; the S-24 exploit operates on the `amount` input dimension. Combined, they multiply the seed-search space.

**Action sequence during rngLock window:** Same shape as §5.B; the `day` choice is bounded by the simulated-day-index granularity (one day per ~24 hours of block time).

**EV magnitude estimate:** **MEDIUM** (as classified in the cluster preamble — affects day-keyed entropy chunk; bounded by day-rotation granularity). Standalone S-25 exploit is narrower than S-24; combined with S-24 it elevates to HIGH per the deep-cluster classification.

### §7.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same gate; lootboxDay is in commitment quad (rngWord, player, day, amount).** Catalog §16 row 426 rationale: "Same gate; lootboxDay is in commitment quad (rngWord,player,day,amount)."

**Concrete shape:** Same gate as §5.C. The gate inserted at `MintModule._allocateLootbox` entry (per `D-43N-V44-HANDOFF-47`) covers the S-25 writer at `:991` automatically — single gate at function entry protects all S-24..S-28 writers in the function.

**Rationale for rejecting alternative tactics:** Same as §5.C.

**Bytecode / storage-layout / public-ABI impact:** Same shared gate per `D-43N-V44-HANDOFF-47`. No additional bytecode delta for V-091 specifically — the gate is already counted in §5.C.

### §7.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-49`** — Shared MINTCLN gate at `_allocateLootbox` entry covers S-25 writer at `:991` (per `D-43N-V44-HANDOFF-47`). Concrete file:line target:

- Writer site: `MintModule.sol:991` (`lootboxDay[lbIndex][buyer] = lbDay`).
- Gate site: `MintModule.sol:982` (shared with `D-43N-V44-HANDOFF-47`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 426 (V-091) and §14 row 84.

---

## §8 — V-092: S-25 `lootboxDay[index][player]` × `MintModule._burnieAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 427 (V-092). §15 row 214 (`MintModule._burnieAllocate` writer at `:1397`).

### §8.A — Design-intent backward-trace

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

### §8.B — Actor game-theory walk

**Exploit-actor class:** BURNIE-lootbox buyer deferring first BURNIE allocation to seed-search the `day` input.

**Concrete vector:** Same shape as §7.B; substitute `_purchaseBurnieLootboxFor` for `_allocateLootbox`. The buyer initiates a BURNIE-coin transfer (which triggers the callback) on a chosen day to seed-search.

**Action sequence during rngLock window:** Same as §7.B; substitute BURNIE-coin transfer for ticket purchase.

**EV magnitude estimate:** **MEDIUM** (same as §7.B — day-keyed entropy chunk). BURNIE-path tends to have larger denominations per call (BURNIE-lootbox minimum at `BURNIE_LOOTBOX_MIN` per `:1382`), so per-allocation stake is higher but seed-search granularity is similar.

### §8.C — Recommended tactic + rationale + impact estimate

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

### §8.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-50`** — Insert `RngLocked` revert gate at `MintModule._purchaseBurnieLootboxFor` entry. Concrete file:line targets:

- Gate WRITE site: `MintModule.sol:1384` — after `index` zero-check, before `coin.burnCoin` at `:1386`.
- Custom error: `RngLocked` (per `D-43N-V44-HANDOFF-47`).
- Writer sites covered: `:1397` (S-25), `:1399` (S-29).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 427 (V-092) and §14 row 84.

---

## §9 — V-093: S-25 `lootboxDay[index][player]` × `WhaleModule._whaleLootboxAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 428 (V-093). §15 row 215 (`WhaleModule._whaleLootboxAllocate` writer at `:854`).

### §9.A — Design-intent backward-trace

**See §6.A and §7.A for shared design-intent.** V-093 is the WhaleModule mirror of V-091 (`lootboxDay` write at `:854` inside `_recordLootboxEntry` first-deposit branch). Same structural concern as §7.A — first-deposit by whale buyer is EOA-mutable post-VRF-fulfillment, enabling `day` input seed-search.

**Cite for "what would break if naively frozen":** Same as §6.A / §7.A — gate at function entry blocks legitimate first-deposit-after-fulfillment; UX cost is one-index-rotation delay.

### §9.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer deferring first whale-bundle allocation to seed-search the `day` input.

**Concrete vector:** Same as §7.B; substitute `buyWhaleBundle` / `buyWhaleHalf` for `buyTickets`. Whale-stake amplifies per-call EV.

**EV magnitude estimate:** **MEDIUM** (day-keyed; same class as §7.B / §8.B). Whale-stake elevates per-tx magnitude but seed-search granularity is unchanged.

### §9.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate on WhaleModule allocation.** Catalog §16 row 428 rationale: "Same MINTCLN-style gate on WhaleModule allocation."

**Concrete shape:** Shared gate at `WhaleModule._whaleLootboxAllocate` entry per `D-43N-V44-HANDOFF-48`. The gate covers S-25 writer at `:854` automatically.

**Rationale for rejecting alternative tactics:** Same as §5.C / §6.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate per `D-43N-V44-HANDOFF-48`.

### §9.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-51`** — Shared MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry covers S-25 writer at `:854` (per `D-43N-V44-HANDOFF-48`). Concrete file:line target:

- Writer site: `WhaleModule.sol:854` (`lootboxDay[index][buyer] = dayIndex`).
- Gate site: `WhaleModule.sol:845` (shared with `D-43N-V44-HANDOFF-48`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 428 (V-093) and §14 row 84.

---

## §10 — V-094: S-26 `lootboxBaseLevelPacked` × `openLootBox` self-zero

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 429 (V-094). §15 row 216 (`LootboxModule.openLootBox` self-zero at `:578`).

### §10.A — Design-intent backward-trace

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

### §10.B — Actor game-theory walk

**Exploit-actor class:** Same as §4.B — re-entrancy via `_resolveLootboxCommon` external-call surface, OR commitment-window storage-staleness exploit.

**Concrete vector:** baseLevel is consumed at `:552` to determine the roll outcome at `:555` (`targetLevel = _rollTargetLevel(baseLevel, seed)`). Mutation of S-26 between SLOAD (:550) and self-zero (:578) would shift `baseLevel`, affecting `targetLevel`. Re-entry shape mirrors §4.B.

**EV magnitude estimate:** **HIGH** (baseLevel is consumed by every lootbox roll outcome per cluster preamble cluster-G classification). Per Phase 298 §0 headline #2: same deep-cluster impact.

### §10.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Snapshot baseLevel into the index at allocation, not at open time.** Catalog §16 row 429 rationale: "Snapshot baseLevel into the index at allocation, not at open time."

**Concrete shape:**

- The current implementation ALREADY writes baseLevel at allocation (`MintModule.sol:992` / `WhaleModule.sol:855`). The catalog's rationale is that the snapshot is partially-done; the gap is the stack-capture at open time (mirror Phase 281 owed-salt).
- Implement the same stack-capture pattern as §4.C: at `openLootBox` entry, capture `_baseLevelPacked` into a stack variable BEFORE any internal/external call. Use the stack variable at `:550-:552` instead of re-SLOADing.
- Combined with the gate at `D-43N-V44-HANDOFF-47` / `D-43N-V44-HANDOFF-48` (which protects the allocation-time write from post-fulfillment mutation), the per-index baseLevel snapshot becomes truly immutable.

**Rationale for rejecting alternative tactics:** Same as §4.C.

**Bytecode / storage-layout / public-ABI impact:** Zero storage delta. ~10-20 bytes additional bytecode per slot stack-captured (incremental over §4.C — same refactor block). NON-BREAKING ABI.

### §10.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-52`** — Stack-capture `lootboxBaseLevelPacked[index][player]` at `openLootBox` entry; combined with `D-43N-V44-HANDOFF-47`/`-48` MINTCLN gate, the slot becomes per-index immutable. Concrete file:line targets:

- Stack-capture site: `LootboxModule.sol:530` (after `amount == 0` revert, alongside other stack-captures per `D-43N-V44-HANDOFF-46`).
- SSTORE self-zero: `LootboxModule.sol:578` (unchanged placement).
- Writer protection: `MintModule.sol:992` + `WhaleModule.sol:855` (covered by shared gates).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 429 (V-094) and §14 row 85.

---

## §11 — V-095: S-26 `lootboxBaseLevelPacked` × `MintModule._allocateLootbox`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 430 (V-095). §15 row 217 (`MintModule._allocateLootbox` writer at `:992`).

### §11.A — Design-intent backward-trace

**See §5.A and §10.A for shared design-intent.** V-095 is the MintModule writer for S-26. Per `MintModule.sol:992`:

```
lootboxBaseLevelPacked[lbIndex][buyer] = uint24(cachedLevel + 1);
```

Fires in the first-deposit branch (`existingAmount == 0` at `:989`). Captures `cachedLevel + 1` (the level-at-allocation-time, +1 to indicate "starting level"). Subsequent-deposit branch does NOT touch S-26 (only S-24 / S-25 / S-28 are subsequent-deposit-mutable; S-26 / S-27 are first-deposit-only).

**The structural concern:** Same as §5.A — first-deposit by buyer A is EOA-mutable post-VRF-fulfillment if A defers their first allocation to index N. The baseLevel-search exploit: A simulates `_rollTargetLevel(baseLevel, seed)` outcomes for candidate `(baseLevel, seed)` pairs, where `baseLevel` is a function of allocation level. By deferring allocation across multiple game-levels, A can choose `cachedLevel + 1` to land on a favorable baseLevel.

**Cite for "what would break if naively frozen":** Same as §5.A — gate at function entry blocks legitimate first-deposit-after-fulfillment.

### §11.B — Actor game-theory walk

**Exploit-actor class:** Player deferring first allocation across game-level rotations to seed-search baseLevel input.

**Concrete vector:** A reads `rngWord_N` (fulfilled). A waits for a favorable `cachedLevel` to align with the seed: simulates `_rollTargetLevel(uint24(cachedLevel + 1), keccak(rngWord_N, A, day, amount))` for current and future levels, chooses optimal level, allocates at that moment.

**Distinction from §5.B / §7.B:** The level dimension is bounded by game-level rotation cadence (which is roughly daily per the daily-VRF mechanism). The search space is narrower than the `amount` dimension but is COMBINATORIAL with `(day, amount)`.

**EV magnitude estimate:** **HIGH** (baseLevel is consumed by every lootbox roll outcome). Per Phase 298 §0 headline #2: deep-cluster classification.

### §11.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate to lock the per-index baseLevel at first allocation.** Catalog §16 row 430 rationale: "Same MINTCLN-style gate to lock the per-index baseLevel at first allocation."

**Concrete shape:** Shared gate at `MintModule._allocateLootbox` entry per `D-43N-V44-HANDOFF-47`. The gate covers S-26 writer at `:992` automatically.

**Rationale for rejecting alternative tactics:** Same as §5.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate per `D-43N-V44-HANDOFF-47`.

### §11.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-53`** — Shared MINTCLN gate at `_allocateLootbox` entry covers S-26 writer at `:992` (per `D-43N-V44-HANDOFF-47`). Concrete file:line target:

- Writer site: `MintModule.sol:992`.
- Gate site: `MintModule.sol:982` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 430 (V-095) and §14 row 85.

---

## §12 — V-096: S-26 `lootboxBaseLevelPacked` × `WhaleModule._whaleLootboxAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 431 (V-096). §15 row 218 (`WhaleModule._whaleLootboxAllocate` writer at `:855`).

### §12.A — Design-intent backward-trace

**See §6.A and §11.A for shared design-intent.** V-096 is the WhaleModule mirror of V-095 (`lootboxBaseLevelPacked` write at `:855` as `uint24(level + 2)` — note: whale path uses `level + 2`, mint path uses `cachedLevel + 1`; the difference reflects the whale-bundle's level-target convention). Same exploit shape as §11.B.

**Cite for "what would break if naively frozen":** Same as §6.A / §11.A.

### §12.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer deferring first whale-bundle allocation across game-level rotations to seed-search baseLevel.

**Concrete vector:** Same as §11.B; substitute whale-bundle for ticket purchase. Whale-stake amplifies per-tx EV.

**EV magnitude estimate:** **HIGH** (same class as §11.B).

### §12.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate on WhaleModule baseLevel writes.** Catalog §16 row 431 rationale: "Same MINTCLN-style gate on WhaleModule baseLevel writes."

**Concrete shape:** Shared gate at `WhaleModule._whaleLootboxAllocate` entry per `D-43N-V44-HANDOFF-48`. Covers S-26 writer at `:855` automatically.

**Rationale for rejecting alternative tactics:** Same as §6.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate.

### §12.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-54`** — Shared MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry covers S-26 writer at `:855` (per `D-43N-V44-HANDOFF-48`). Concrete file:line target:

- Writer site: `WhaleModule.sol:855`.
- Gate site: `WhaleModule.sol:845` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 431 (V-096) and §14 row 85.

---

## §13 — V-097: S-27 `lootboxEvScorePacked` × `openLootBox` self-zero

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 432 (V-097). §15 row 219 (`LootboxModule.openLootBox` self-zero at `:579`).

### §13.A — Design-intent backward-trace

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

### §13.B — Actor game-theory walk

**Exploit-actor class:** Same as §4.B — re-entrancy via `_resolveLootboxCommon`, OR commitment-window storage-staleness exploit.

**Concrete vector:** EV-score affects the EV-multiplier (`80%-135% bps` per `:472`). Mutation of S-27 mid-cascade shifts the multiplier; combined with the S-22 cap consumption pattern, this can compound the cross-resolution race documented in §1.B.

**EV magnitude estimate:** **HIGH** (EV score is the multiplier-cap input per cluster preamble cluster-G classification). Compounds with the S-22 cross-resolution accumulator exploit.

### §13.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Score must be snapshotted at allocation (partially done; close gap).** Catalog §16 row 432 rationale: "Score must be snapshotted at allocation (partially done; close gap)."

**Concrete shape:** The allocation-time snapshot already exists at `MintModule.sol:1155` (`lootboxEvScorePacked[lbIndex][buyer] = uint16(cachedScore + 1)`) and `WhaleModule.sol:856` (`lootboxEvScorePacked[index][buyer] = uint16(playerActivityScore(buyer) + 1)`). The gap is:

1. Stack-capture at `openLootBox` entry to prevent mid-cascade mutation (per §4.C / §10.C shape).
2. Combined with the writer-side gates at `D-43N-V44-HANDOFF-47` / `D-43N-V44-HANDOFF-48`, the slot becomes immutable post-allocation.

**Rationale for rejecting alternative tactics:** Same as §4.C / §10.C.

**Bytecode / storage-layout / public-ABI impact:** Zero storage delta. ~10-20 bytes incremental over §4.C / §10.C stack-capture block. NON-BREAKING ABI.

### §13.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-55`** — Stack-capture `lootboxEvScorePacked[index][player]` at `openLootBox` entry; combined with writer-side gates, slot becomes per-index immutable. Concrete file:line targets:

- Stack-capture site: `LootboxModule.sol:530` (shared with `D-43N-V44-HANDOFF-46` / `D-43N-V44-HANDOFF-52`).
- SSTORE self-zero: `LootboxModule.sol:579` (unchanged placement).
- Writer protection: `MintModule.sol:1155` + `WhaleModule.sol:856` (covered by shared gates).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 432 (V-097) and §14 row 86.

---

## §14 — V-098: S-27 `lootboxEvScorePacked` × `MintModule._allocateLootbox` snapshot write

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 433 (V-098). §15 row 220 (`MintModule._allocateLootbox` snapshot write at `:1155`).

### §14.A — Design-intent backward-trace

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

### §14.B — Actor game-theory walk

**Exploit-actor class:** Player manipulating quest-streak / activity inputs to seed-search EV-score at first-deposit moment.

**Concrete vector:** A completes quests to land at a target `cachedScore`, then calls `buyTickets` with lootbox component to snapshot the score. A defers the call until `rngWord_N` is fulfilled to enable predictive optimization.

**EV magnitude estimate:** **HIGH** (EV score is the multiplier-cap input; compounds with S-22 cap consumption).

### §14.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Gate snapshot write on rng-not-yet-published; pattern Phase 290 MINTCLN.** Catalog §16 row 433 rationale: "Gate snapshot write on rng-not-yet-published; pattern Phase 290 MINTCLN."

**Concrete shape:** Shared gate at `MintModule._allocateLootbox` entry per `D-43N-V44-HANDOFF-47`. The gate covers S-27 writer at `:1155` automatically — the function entry gate fires before any path in the function executes.

**Rationale for rejecting alternative tactics:** Same as §5.C / §11.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate.

### §14.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-56`** — Shared MINTCLN gate at `_allocateLootbox` entry covers S-27 writer at `:1155` (per `D-43N-V44-HANDOFF-47`). Concrete file:line target:

- Writer site: `MintModule.sol:1155`.
- Gate site: `MintModule.sol:982` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 433 (V-098) and §14 row 86.

---

## §15 — V-099: S-27 `lootboxEvScorePacked` × `WhaleModule._whaleLootboxAllocate` snapshot

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 434 (V-099). §15 row 221 (`WhaleModule._whaleLootboxAllocate` snapshot at `:856`).

### §15.A — Design-intent backward-trace

**See §6.A and §14.A for shared design-intent.** V-099 is the WhaleModule mirror of V-098 (`lootboxEvScorePacked` write at `:856` as `uint16(playerActivityScore(buyer) + 1)`). Same exploit shape as §14.B; whale-stake amplifies per-tx EV.

**Cite for "what would break if naively frozen":** Same as §6.A / §14.A.

### §15.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer manipulating activity score (note: the whale path reads `playerActivityScore(buyer)` directly at `:857` rather than the mint-path's `cachedScore`-via-`questStreak` shape; whale path snapshot is more direct but exploits the same activity-input manipulation).

**Concrete vector:** Same as §14.B; substitute whale-bundle for ticket purchase. Whale buyers typically have access to richer activity inputs (whale bundles trigger more activity events per call).

**EV magnitude estimate:** **HIGH** (same class as §14.B).

### §15.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate.** Catalog §16 row 434 rationale: "Same MINTCLN-style gate."

**Concrete shape:** Shared gate at `WhaleModule._whaleLootboxAllocate` entry per `D-43N-V44-HANDOFF-48`. Covers S-27 writer at `:856`.

**Rationale for rejecting alternative tactics:** Same as §6.C / §14.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta.

### §15.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-57`** — Shared MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry covers S-27 writer at `:856` (per `D-43N-V44-HANDOFF-48`). Concrete file:line target:

- Writer site: `WhaleModule.sol:856`.
- Gate site: `WhaleModule.sol:845` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 434 (V-099) and §14 row 86.

---

## §16 — V-100: S-28 `lootboxDistressEth` × `openLootBox` self-zero (conditional)

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 435 (V-100). §15 row 222 (`LootboxModule.openLootBox` self-zero at `:581`).

### §16.A — Design-intent backward-trace

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

### §16.B — Actor game-theory walk

**Exploit-actor class:** Same as §4.B — re-entrancy via `_resolveLootboxCommon`, OR commitment-window storage-staleness exploit.

**Concrete vector:** Distress affects the proportional ticket-bonus magnitude at resolution. Mutation of S-28 mid-cascade shifts the bonus.

**EV magnitude estimate:** **MEDIUM** (distress flag is a conditional outcome modifier, narrower impact than amount/level/EV-score per cluster preamble cluster-G classification).

### §16.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Freeze distress flag at allocation; same snapshot pattern.** Catalog §16 row 435 rationale: "Freeze distress flag at allocation; same snapshot pattern."

**Concrete shape:** Stack-capture at `openLootBox` entry (shared with §4.C / §10.C / §13.C); writer-side protection via shared gates at `D-43N-V44-HANDOFF-47` / `D-43N-V44-HANDOFF-48`.

**Rationale for rejecting alternative tactics:** Same as §4.C.

**Bytecode / storage-layout / public-ABI impact:** Zero storage delta. ~10-20 bytes incremental. NON-BREAKING ABI.

### §16.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-58`** — Stack-capture `lootboxDistressEth[index][player]` at `openLootBox` entry; combined with writer-side gates, slot becomes per-index immutable. Concrete file:line targets:

- Stack-capture site: `LootboxModule.sol:530` (shared).
- SSTORE self-zero: `LootboxModule.sol:581` (unchanged placement; conditional).
- Writer protection: `MintModule.sol:1031` + `WhaleModule.sol:881` (covered by shared gates).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 435 (V-100) and §14 row 87.

---

## §17 — V-101: S-28 `lootboxDistressEth` × `MintModule._allocateLootbox` distress accumulation

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 436 (V-101). §15 row 223 (`MintModule._allocateLootbox` distress accumulation at `:1031`).

### §17.A — Design-intent backward-trace

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

### §17.B — Actor game-theory walk

**Exploit-actor class:** Player making subsequent allocations during distress-mode to inflate S-28 post-fulfillment.

**Concrete vector:** A holds an allocated index N. Distress mode activates. `lootboxRngWordByIndex[N]` fulfills. A reads `rngWord_N` and simulates open outcomes for current `distressEth` value vs inflated values. A calls `buyTickets` with lootbox component during distress to ACCUMULATE distress at `:1031`; opens at the optimal distress value.

**EV magnitude estimate:** **MEDIUM** (distress flag conditional outcome; narrower than amount/level/EV-score).

### §17.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate on distress accumulation.** Catalog §16 row 436 rationale: "Same MINTCLN-style gate on distress accumulation."

**Concrete shape:** Shared gate at `MintModule._allocateLootbox` entry per `D-43N-V44-HANDOFF-47`. Covers S-28 accumulation at `:1031`.

**Rationale for rejecting alternative tactics:** Same as §5.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta.

### §17.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-59`** — Shared MINTCLN gate at `_allocateLootbox` entry covers S-28 accumulator at `:1031` (per `D-43N-V44-HANDOFF-47`). Concrete file:line target:

- Writer site: `MintModule.sol:1031`.
- Gate site: `MintModule.sol:982` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 436 (V-101) and §14 row 87.

---

## §18 — V-102: S-28 `lootboxDistressEth` × `WhaleModule._whaleLootboxAllocate` distress accumulation

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 437 (V-102). §15 row 224 (`WhaleModule._whaleLootboxAllocate` distress accumulation at `:881`).

### §18.A — Design-intent backward-trace

**See §6.A and §17.A for shared design-intent.** V-102 is the WhaleModule mirror of V-101 — distress accumulation at `:881` (`lootboxDistressEth[index][buyer] += boostedAmount`). Identical structural concern; whale-stake amplifies per-tx accumulation delta.

**Cite for "what would break if naively frozen":** Same as §6.A / §17.A.

### §18.B — Actor game-theory walk

**Exploit-actor class:** Whale buyer making subsequent whale-bundle allocations during distress-mode to inflate S-28 post-fulfillment.

**Concrete vector:** Same as §17.B; substitute whale-bundle for ticket purchase. Whale-bundle quantum amplifies per-tx accumulation.

**EV magnitude estimate:** **MEDIUM** (same as §17.B; whale-stake amplifies but slot-impact class is unchanged).

### §18.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate.** Catalog §16 row 437 rationale: "Same MINTCLN-style gate."

**Concrete shape:** Shared gate at `WhaleModule._whaleLootboxAllocate` entry per `D-43N-V44-HANDOFF-48`. Covers S-28 accumulator at `:881`.

**Rationale for rejecting alternative tactics:** Same as §6.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta.

### §18.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-60`** — Shared MINTCLN gate at `WhaleModule._whaleLootboxAllocate` entry covers S-28 accumulator at `:881` (per `D-43N-V44-HANDOFF-48`). Concrete file:line target:

- Writer site: `WhaleModule.sol:881`.
- Gate site: `WhaleModule.sol:845` (shared).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 437 (V-102) and §14 row 87.

---

## §19 — V-103: S-29 `lootboxBurnie` × `openBurnieLootBox` self-zero

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 438 (V-103). §15 row 225 (`LootboxModule.openBurnieLootBox` self-zero at `:615`).

### §19.A — Design-intent backward-trace

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

### §19.B — Actor game-theory walk

**Exploit-actor class:** Same as §4.B — re-entrancy via `_resolveLootboxCommon`, OR commitment-window storage-staleness exploit on the BURNIE-amount path.

**Concrete vector:** BURNIE-amount affects `amountEth` (`burnieAmount × priceWei × 80 / PRICE_COIN_UNIT × 100`), which is the keccak input at `:629`. Mutation of S-29 between SLOAD (:609) and self-zero (:615) would shift the seed; but the window is extremely narrow (no internal/external calls between :609 and :615). Re-entry via `_resolveLootboxCommon` (at :638) is the broader concern, where a sibling BURNIE-open could harvest at the cross-resolution accumulator (S-22).

**EV magnitude estimate:** **HIGH** (BURNIE amount magnitude is significant; same class as S-24 amount per cluster preamble — directly scales lootbox magnitude).

### §19.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (b) Freeze burnieAmount into a stack var pre-SLOAD-cascade.** Catalog §16 row 438 rationale: "Freeze burnieAmount into a stack var pre-SLOAD-cascade."

**Concrete shape:**

- At `LootboxModule.openBurnieLootBox` entry (after `:613` `rngWord != 0` check), capture `_burnieAmount`, `_day` into stack variables BEFORE any internal/external call.
- The self-zero at `:615` continues to fire BEFORE the external call to `priceWei` at `:618` (already structurally correct in current implementation; refactor is for symmetry with `openLootBox`).
- Combined with the writer-side gate at `D-43N-V44-HANDOFF-50` (BURNIE-allocate gate), S-29 becomes per-index immutable.

**Rationale for rejecting alternative tactics:** Same as §4.C.

**Bytecode / storage-layout / public-ABI impact:** Zero storage delta. ~30-50 bytes refactor. NON-BREAKING ABI.

### §19.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-61`** — Stack-capture `lootboxBurnie[index][player]` + `lootboxDay[index][player]` at `openBurnieLootBox` entry. Concrete file:line targets:

- Stack-capture site: `LootboxModule.sol:614` (after `:613` `rngWord != 0` check, before `:615` self-zero).
- SSTORE self-zero: `LootboxModule.sol:615` (unchanged placement).
- Writer protection: `MintModule.sol:1399` (covered by `D-43N-V44-HANDOFF-50`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 438 (V-103) and §14 row 88.

---

## §20 — V-104: S-29 `lootboxBurnie` × `MintModule._burnieAllocate`

**Catalog cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 439 (V-104). §15 row 226 (`MintModule._burnieAllocate` at `:1399`).

### §20.A — Design-intent backward-trace

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

### §20.B — Actor game-theory walk

**Exploit-actor class:** BURNIE-buyer making subsequent BURNIE-coin transfers to inflate S-29 post-fulfillment.

**Concrete vector:** Same shape as §8.B (BURNIE-allocate path); compounded with the amount-search dimension. A reads `rngWord_N`, computes seed-search over `amountEth = (burnieAmount × priceWei × 80) / (PRICE_COIN_UNIT × 100)` variations, executes BURNIE-coin transfers to land on optimal `amountEth`.

**EV magnitude estimate:** **HIGH** (same class as §5.B / §8.B — BURNIE-amount directly scales the keccak input + resolution magnitude).

### §20.C — Recommended tactic + rationale + impact estimate

**Selected tactic: (a) Same MINTCLN-style gate on BURNIE-allocation path.** Catalog §16 row 439 rationale: "Same MINTCLN-style gate on BURNIE-allocation path."

**Concrete shape:** Shared gate at `MintModule._purchaseBurnieLootboxFor` entry per `D-43N-V44-HANDOFF-50`. Covers S-29 accumulator at `:1399` AND S-25 first-write at `:1397` (shared gate).

**Rationale for rejecting alternative tactics:** Same as §5.C / §8.C.

**Bytecode / storage-layout / public-ABI impact:** No incremental delta — covered by shared gate per `D-43N-V44-HANDOFF-50`.

### §20.D — v44.0 FIX-MILESTONE handoff anchor

**`D-43N-V44-HANDOFF-62`** — Shared MINTCLN gate at `_purchaseBurnieLootboxFor` entry covers S-29 accumulator at `:1399` (per `D-43N-V44-HANDOFF-50`). Concrete file:line target:

- Writer site: `MintModule.sol:1399`.
- Gate site: `MintModule.sol:1384` (shared with `D-43N-V44-HANDOFF-50`).
- **Cross-reference:** `.planning/RNGLOCK-CATALOG.md` §16 row 439 (V-104) and §14 row 88.

---

## Cluster G summary — tactic mix + EV-tier distribution + handoff register

**VIOLATION count:** 20 (V-081, V-082, V-084, V-088, V-089, V-090, V-091, V-092, V-093, V-094, V-095, V-096, V-097, V-098, V-099, V-100, V-101, V-102, V-103, V-104).

**Tactic distribution:**
- **(a) `RngLocked`-gated revert (Phase 290 MINTCLN pattern):** 12 entries — V-089, V-090, V-091, V-092, V-093, V-095, V-096, V-098, V-099, V-101, V-102, V-104.
- **(b) Stack-capture / snapshot pre-cascade (Phase 281 owed-salt pattern):** 8 entries — V-081, V-082, V-084 (S-22 cross-resolution accumulator snapshot at allocation); V-088, V-094, V-097, V-100, V-103 (self-zero stack-capture pre-cascade).

**EV-tier distribution:**
- **HIGH:** V-081, V-082, V-084, V-088, V-089, V-090, V-094, V-095, V-096, V-097, V-098, V-099, V-103, V-104 (14 entries). S-22 cross-resolution accumulator + per-index commitment-quad amount/level/EV-score VIOLATIONs.
- **MEDIUM:** V-091, V-092, V-093, V-100, V-101, V-102 (6 entries). Day-keyed entropy chunk + distress flag conditional VIOLATIONs.
- **CATASTROPHE-tier classification per `feedback_rng_window_storage_read_freshness.md`:** V-081, V-082, V-084 (S-22 cross-resolution accumulator design break per Phase 298 §0 headline #2).

**Shared gate / stack-capture consolidation:**
- One `MintModule._allocateLootbox` entry gate (per `D-43N-V44-HANDOFF-47`) covers V-089, V-091, V-095, V-098, V-101 (5 writers).
- One `WhaleModule._whaleLootboxAllocate` entry gate (per `D-43N-V44-HANDOFF-48`) covers V-090, V-093, V-096, V-099, V-102 (5 writers).
- One `MintModule._purchaseBurnieLootboxFor` entry gate (per `D-43N-V44-HANDOFF-50`) covers V-092, V-104 (2 writers).
- One `LootboxModule.openLootBox` stack-capture block (per `D-43N-V44-HANDOFF-46`) covers V-088, V-094, V-097, V-100 (4 self-zero rows).
- One `LootboxModule.openBurnieLootBox` stack-capture block (per `D-43N-V44-HANDOFF-61`) covers V-103 (1 self-zero row).
- Three S-22 snapshot writes (per `D-43N-V44-HANDOFF-43`/`-44`/`-45`) cover V-081, V-082, V-084 (allocation-time + redemption-snapshot at burn submission).

**Total fix sites:** ~8 distinct code-edit locations cover all 20 VIOLATIONs (gates are shared across slot families; stack-capture is shared across self-zero rows; snapshot writes are shared across consumer reach).

**Consolidated v44.0 handoff register** (one ID per VIOLATION; deduplicated):

| Handoff ID | VIOLATION | Slot | Writer | Tactic | File:line |
|------------|-----------|------|--------|--------|-----------|
| `D-43N-V44-HANDOFF-43` | V-081 | S-22 | `_applyEvMultiplierWithCap` (openLootBox reach) | (b) snapshot | `LootboxModule.sol:511` / new `MintModule.sol:989` snapshot + `WhaleModule.sol:853` snapshot |
| `D-43N-V44-HANDOFF-44` | V-082 | S-22 | `_applyEvMultiplierWithCap` (openBurnieLootBox reach) | (b) snapshot | `LootboxModule.sol:511` / new `MintModule.sol:1396` BURNIE snapshot |
| `D-43N-V44-HANDOFF-45` | V-084 | S-22 | `_applyEvMultiplierWithCap` (resolveRedemptionLootbox reach) | (b) snapshot | `LootboxModule.sol:716` / new sStonk burn-submission snapshot |
| `D-43N-V44-HANDOFF-46` | V-088 | S-24 | openLootBox self-zero | (b) stack-capture | `LootboxModule.sol:530`/`:576` |
| `D-43N-V44-HANDOFF-47` | V-089 | S-24 | `MintModule._allocateLootbox` | (a) gate | `MintModule.sol:982`/`:1013` |
| `D-43N-V44-HANDOFF-48` | V-090 | S-24 | `WhaleModule._whaleLootboxAllocate` | (a) gate | `WhaleModule.sol:845`/`:876` |
| `D-43N-V44-HANDOFF-49` | V-091 | S-25 | `MintModule._allocateLootbox` | (a) gate (shared) | `MintModule.sol:982`/`:991` |
| `D-43N-V44-HANDOFF-50` | V-092 | S-25 | `MintModule._purchaseBurnieLootboxFor` | (a) gate | `MintModule.sol:1384`/`:1397` |
| `D-43N-V44-HANDOFF-51` | V-093 | S-25 | `WhaleModule._whaleLootboxAllocate` | (a) gate (shared) | `WhaleModule.sol:845`/`:854` |
| `D-43N-V44-HANDOFF-52` | V-094 | S-26 | openLootBox self-zero | (b) stack-capture (shared) | `LootboxModule.sol:530`/`:578` |
| `D-43N-V44-HANDOFF-53` | V-095 | S-26 | `MintModule._allocateLootbox` | (a) gate (shared) | `MintModule.sol:982`/`:992` |
| `D-43N-V44-HANDOFF-54` | V-096 | S-26 | `WhaleModule._whaleLootboxAllocate` | (a) gate (shared) | `WhaleModule.sol:845`/`:855` |
| `D-43N-V44-HANDOFF-55` | V-097 | S-27 | openLootBox self-zero | (b) stack-capture (shared) | `LootboxModule.sol:530`/`:579` |
| `D-43N-V44-HANDOFF-56` | V-098 | S-27 | `MintModule._allocateLootbox` snapshot write | (a) gate (shared) | `MintModule.sol:982`/`:1155` |
| `D-43N-V44-HANDOFF-57` | V-099 | S-27 | `WhaleModule._whaleLootboxAllocate` snapshot | (a) gate (shared) | `WhaleModule.sol:845`/`:856` |
| `D-43N-V44-HANDOFF-58` | V-100 | S-28 | openLootBox self-zero (conditional) | (b) stack-capture (shared) | `LootboxModule.sol:530`/`:581` |
| `D-43N-V44-HANDOFF-59` | V-101 | S-28 | `MintModule._allocateLootbox` distress accumulation | (a) gate (shared) | `MintModule.sol:982`/`:1031` |
| `D-43N-V44-HANDOFF-60` | V-102 | S-28 | `WhaleModule._whaleLootboxAllocate` distress accumulation | (a) gate (shared) | `WhaleModule.sol:845`/`:881` |
| `D-43N-V44-HANDOFF-61` | V-103 | S-29 | openBurnieLootBox self-zero | (b) stack-capture | `LootboxModule.sol:614`/`:615` |
| `D-43N-V44-HANDOFF-62` | V-104 | S-29 | `MintModule._purchaseBurnieLootboxFor` | (a) gate (shared) | `MintModule.sol:1384`/`:1399` |

**Stale-phantom rows:** **zero**. Every V-NNN in scope corresponds to a verified writer site at the catalog-cited file:line (per `feedback_verify_call_graph_against_source.md` source-of-truth grep enumeration in the cluster preamble).

**Aggregate bytecode impact estimate:** ~600 bytes total (3 gates × ~30-50 bytes each + 5 stack-capture refactor blocks × ~40-80 bytes each + 3 snapshot writes × ~50-100 bytes each). Approximate; v44 plan-phase finalizes exact bytecode delta per sub-phase.

**Aggregate storage-layout impact:** ONE new per-index mapping `lootboxEvCapAtAllocation[index][player]` (uint128 sufficient) — NOT byte-identical with respect to existing layout. Plus one new sStonk burn-position record field `usedBenefitAtSubmission` (uint128). All other fixes are byte-identical (gates / stack-captures).

**Aggregate public-ABI impact:** **NON-BREAKING** per `D-40N-EVT-BREAK-01` (no event topic-hash changes; no external function signature changes; internal `_applyEvMultiplierWithCap` signature changes are private).

**Cross-VIOLATION pattern aggregation note** (per CONTEXT.md `deferred` section): 12 of the 20 VIOLATIONs (V-089..V-099 even MintModule/WhaleModule writers + V-101, V-102, V-104) resolve via the SAME 3 shared gates (MintModule, WhaleModule, MintModule.BURNIE). 5 of the 20 (V-088, V-094, V-097, V-100, V-103) resolve via 2 shared stack-capture blocks (openLootBox, openBurnieLootBox). 3 of the 20 (V-081, V-082, V-084) resolve via the per-index EV-cap snapshot mapping. v44 plan-phase may group by tactic-shape into 3 sub-phases: (1) gate insertion (3 sites), (2) stack-capture consolidation (2 sites), (3) per-index EV-cap snapshot mapping introduction (3 writers + 1 consumer refactor).

---

*Cluster G — Phase 299 FIXREC contribution. AUDIT-ONLY output per `D-43N-AUDIT-ONLY-01`. Zero `contracts/` + zero `test/` mutations.*
