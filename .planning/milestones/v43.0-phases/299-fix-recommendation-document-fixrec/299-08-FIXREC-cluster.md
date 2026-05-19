---
phase: 299-fix-recommendation-document-fixrec
plan: 08
cluster: H
type: fixrec-cluster
scope: "presaleStatePacked (S-30) + mintPacked_[player] (S-32) + boonPacked[player] (S-34) + lastPurchaseDay (S-35) — cross-resolution activity-score / boon / presale / purchase-day slot family"
violations_covered: [V-105, V-109, V-110, V-111, V-112, V-113, V-114, V-117, V-120, V-121, V-122, V-123, V-124, V-125, V-127]
handoff_anchors: [D-43N-V44-HANDOFF-63, D-43N-V44-HANDOFF-64, D-43N-V44-HANDOFF-65, D-43N-V44-HANDOFF-66, D-43N-V44-HANDOFF-67, D-43N-V44-HANDOFF-68, D-43N-V44-HANDOFF-69, D-43N-V44-HANDOFF-70, D-43N-V44-HANDOFF-71, D-43N-V44-HANDOFF-72, D-43N-V44-HANDOFF-73, D-43N-V44-HANDOFF-74, D-43N-V44-HANDOFF-75, D-43N-V44-HANDOFF-76, D-43N-V44-HANDOFF-77]
tactic_mix:
  rngLock_gate_a: [V-114, V-120, V-121, V-122, V-125, V-127]
  snapshot_b:     [V-105, V-109, V-110, V-112, V-113, V-123]
  reorder_c:      [V-111, V-117, V-124]
  immutable_d:    []
ev_tier:
  HIGH:           [V-109, V-110, V-111, V-112, V-113, V-114, V-117, V-120, V-121, V-122, V-123, V-124, V-125]
  MEDIUM:         [V-105, V-127]
  LOW:            []
  CATASTROPHE:    []
stale_phantoms:  [V-127]
posture: AUDIT-ONLY (D-43N-AUDIT-ONLY-01)
---

# Phase 299 Plan 08 — FIXREC Cluster H

**Scope:** `presaleStatePacked` (S-30) + `mintPacked_[player]` (S-32) + `boonPacked[player]` (S-34) + `lastPurchaseDay` (S-35) — the cross-resolution accumulator family. 15 logical VIOLATIONs spanning four sub-families:

| Sub-family | Slot | VIOLATIONs |
|---|---|---|
| presaleStatePacked (S-30) | per-game presale cap counter | V-105 |
| mintPacked_[player] (S-32) | per-EOA activity score / streak / deity sentinel | V-109, V-110, V-111, V-112, V-113, V-114, V-117 |
| boonPacked[player] (S-34) | per-EOA boon state (slot0 + slot1) | V-120, V-121, V-122, V-123, V-124, V-125 |
| lastPurchaseDay (S-35) | per-game purchase-target-met flag | V-127 |

**Consumer reach context.** Every one of these slots is SLOAD'd inside `_resolveLootboxCommon` / `_resolveLootboxRoll` (CATALOG §7, the MANUAL `openLootBox` path) and most also inside `DegeneretteModule._resolveLootboxDirect` (CATALOG §8). `mintPacked_` is the load-bearing input to `_playerActivityScore` (`MintStreakUtils.sol:83 + :169`) which is fetched cross-call via `IDegenerusGame(address(this)).playerActivityScore(player)` at `LootboxModule.sol:444 _lootboxEvMultiplierBps`. `boonPacked` is read in the boon-roll path at `_rollLootboxBoons:1109` and consumed via the BoonModule externals `checkAndClearExpiredBoon:120` + `consumeActivityBoon:281` (both delegatecalled from the lootbox stack). `presaleStatePacked` flips the presale-allocation arm in `_resolveLootboxCommon` at the `presale` branch. `lastPurchaseDay` is read at CATALOG §7 C-17 as a liveness gate.

**Verification scope.** Each §N below was cross-checked against current source: file:line cites in §N.A reproduce the writer present in `contracts/` at the head of this audit; classifications follow CATALOG §16 verdicts. **One stale-phantom row identified** (V-127 — see §15.A). No SAFE_BY_DESIGN tokens used.

**Discipline:** No `contracts/` or `test/` mutations. Backward-trace per `feedback_design_intent_before_deletion.md`. SLOAD-freshness per `feedback_rng_window_storage_read_freshness.md`. Verified-against-source per `feedback_verify_call_graph_against_source.md`. Frozen-contract reality per `feedback_frozen_contracts_no_future_proofing.md` — recommendations remain advisory for v44.0 plan-phase consumption.

---

## §1 — V-105: presaleStatePacked write inside `_presaleCapCheck` during cap evaluation (MintModule.sol:1026)

### §1.A — Design-intent backward-trace

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

### §1.B — Actor game-theory walk

Exploit actor: an EOA buyer who can call `buyTickets` between the daily VRF callback (`AdvanceModule.sol:1256 lootboxRngWordByIndex[index] = rngWord`) and his own subsequent `openLootBox(index)`. The buyer observes the published `rngWord`, projects which lootbox-index resolutions would benefit from a flipped presale state (e.g., the presale `vaultBps == 0` arm vs the post-presale arm with non-zero `vaultBps`), and crafts an additional `buyTickets` call sized so that `_presaleCapCheck` runs and either (a) accumulates ETH toward the cap without flipping, or (b) crosses `LOOTBOX_PRESALE_ETH_CAP` and clears `PS_ACTIVE`, flipping the resolution arm for already-allocated indices.

**EV magnitude:** MEDIUM. The presale-vs-post-presale arm change shifts the `vaultBps`/`futureBps`/`nextBps` split for the lootbox amount accounting (lines around `MintModule.sol:244+`), but it does NOT directly increase the player's own scaled-payout (`scaledAmount`). The economic-likelihood disposition is that an attacker would only exploit this when (i) holding a fresh lootbox-RNG index already allocated under presale rules and (ii) the post-presale arm yields a strictly larger personal payout — a narrow case. Conservative classification: MEDIUM.

### §1.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot presale flag per-index at allocation.** At lootbox-allocation time (`MintModule._allocateLootbox` / `WhaleModule._whaleLootboxAllocate`), snapshot `presale = (presaleStatePacked & PS_ACTIVE_MASK) != 0` into a per-index storage field (or repurpose a free bit in `lootboxBaseLevelPacked[index][buyer]`). The lootbox-resolution body reads the snapshotted bit instead of live `presaleStatePacked`.

**Rationale.** Phase 288 dailyIdx + Phase 281 owed-salt precedent: any value participating in a post-RNG-callback resolution must be frozen at allocation. The presale flag participates in the `distribution`/`vaultBps` derivation inside `_resolveLootboxCommon`'s presale-aware branch — snapshotting at allocation eliminates the post-callback flip exploit while preserving the legitimate global cap-tracking semantics.

**Bytecode impact.** ~50-100 bytes — one additional storage write at each allocation callsite (`MintModule:_allocateLootbox`, `WhaleModule:_whaleLootboxAllocate`) and one storage read swap in `_resolveLootboxCommon`. Storage-layout: one new bit per allocated index (cleanly fits into a free bit of `lootboxBaseLevelPacked`); ABI: NON-BREAKING.

### §1.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-63` — CATALOG §16 row V-105 + §17 §C-4 / §D-10 / §E-7. v44.0 plan-phase: define `LB_PRESALE_BIT` in `lootboxBaseLevelPacked` packed layout; emit at allocation; read at consumer presale arm.

---

## §2 — V-109: mintPacked_ write inside `_mintStreakWrite` / `_recordMintStreakForLevel` (MintStreakUtils.sol:47)

### §2.A — Design-intent backward-trace

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

### §2.B — Actor game-theory walk

Exploit actor: an EOA buyer who holds a pre-VRF-allocated lootbox index. Between the daily VRF callback (`AdvanceModule.sol:1256`) and his own `openLootBox(index)`, the buyer calls `buyTickets` to mint additional levels, triggering `_mintStreakWrite` at `MintStreakUtils.sol:47` to advance `MINT_STREAK_LAST_COMPLETED` and `LEVEL_STREAK`. The post-callback `openLootBox` reads the fresh streak via `_playerActivityScore`, inflating `scoreBps` → `evMultiplierBps` → `scaledAmount` of the existing allocation.

**EV magnitude:** HIGH. `_playerActivityScore` directly multiplies the lootbox payout magnitude (`scaledAmount = amount * evMultiplierBps / 10_000`). A single additional level-completion can raise `evMultiplierBps` from 10_000 to its high-water cap (multiple thousand bps). Per `feedback_rng_window_storage_read_freshness.md` precedent F-41-02/03, any non-VRF SLOAD consumed alongside the RNG word inside the resolution window is in-scope; this is one of the load-bearing examples of that bug class on this codebase.

### §2.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot streak into the lootbox-index at allocation.** At `_allocateLootbox` time, capture the player's then-current `_playerActivityScore`-equivalent into `lootboxEvScorePacked[index][player]` (which D-19 confirms is already a per-index snapshot — close the residual gap by ensuring the streak component is captured at allocation and read from the snapshot, not live).

**Rationale.** This is the canonical Phase 281 owed-salt + Phase 288 dailyIdx pattern. The slot's legitimate cross-game mutation is preserved; only the lootbox-EV consumer reads the frozen value. The MintCount/MintStreak field semantics are NOT changed for any other consumer (jackpot allocation, future-tier reward, affiliate cache).

**Bytecode impact.** ~50-100 bytes — `lootboxEvScorePacked` is already an existing slot per CATALOG §14 S-9. The fix collapses the live-read path inside `_lootboxEvMultiplierBps` (`:444`) to consume the snapshotted score; no new storage slot needed. Storage-layout: identical (snapshot field already exists). ABI: NON-BREAKING.

### §2.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-64` — CATALOG §16 row V-109 + §17 §C-9 / §D-21 / §E-14. v44.0 plan-phase: route `_lootboxEvMultiplierBps` to read `lootboxEvScorePacked[index][player]` rather than live `_playerActivityScore`.

---

## §3 — V-110: mintPacked_ writes inside `MintModule._allocateMintPacked` 3 callsites (MintModule.sol:240, :275, :369)

### §3.A — Design-intent backward-trace

`MintModule._allocateMintPacked` is the master writer for `mintPacked_[player]` on every direct-mint flow (`buyTickets` / `processMint`). The 3 callsites at `:240`, `:275`, `:369` correspond to the three structural arms (verified at source: `:240` = level-only unit update; `:275` = same-level update; `:369` = new-level full update after frozen-until check). Each arm writes a different subset of fields (LEVEL_UNITS, DAY, FROZEN_UNTIL_LEVEL, AFF_POINTS).

The slot is shared between mint-flow accounting and the cross-call SLOAD inside `_playerActivityScore` (CATALOG §7 C-9). **All three callsites mutate fields read by `_lootboxEvMultiplierBps` during lootbox resolution**: LEVEL_COUNT (via `_mintCountBonusPoints`) and AFF_POINTS (via `_playerActivityScore`'s cached-affiliate-points read path).

**Why this writer exists.** Mint-state must accumulate per purchase; this is the central per-EOA state-machine writer.

**Phase-precedent.** Phase 281 + Phase 290 — same shape as V-109.

### §3.B — Actor game-theory walk

Same vector as V-109 — but broader. EOA buyer purchases tickets between VRF callback and his own `openLootBox(index)`. The 3 callsites here represent the 3 possible state-machine transitions a `buyTickets` call may take. Each mutates fields read by `_lootboxEvMultiplierBps`. Cross-resolution accumulator: prior calls in the rng-lock window compound — an attacker can drive LEVEL_COUNT very high (via large `buyTickets` volume) to maximize `_mintCountBonusPoints`'s contribution.

**EV magnitude:** HIGH. Same multiplier on `scaledAmount` as V-109. The 3-callsite enumeration here distinguishes from V-109's `_mintStreakWrite`; together with V-109 the activity-score input set is fully writeable by the player during the rng-lock window.

### §3.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot full activity-score-input set at bet/lootbox placement.** Same as V-109's recommendation: route `_lootboxEvMultiplierBps` to consume the snapshotted `lootboxEvScorePacked[index][player]` (S-9 per CATALOG §14). Crucially, the snapshot at allocation must include **all** activity-score inputs (LEVEL_COUNT, LEVEL_STREAK, AFF_POINTS, jackpotPhaseFlag-derived activeTicketLevel) — not just the streak component.

**Rationale.** A partial snapshot is worse than none: it leaks the exploit surface to whichever input remains live-read. Phase 288 dailyIdx + Phase 281 owed-salt: complete-snapshot is the discipline.

**Bytecode impact.** ~80 bytes — one snapshot SSTORE at `_allocateLootbox`/`_whaleLootboxAllocate` capturing the full activity-score result; consumer reads change from live-recompute to single SLOAD. **Bytecode SAVES** at the consumer site (skips ~5-10 SLOADs and the cross-call `staticcall` into `_playerActivityScore`); net likely slight reduction. Storage-layout: `lootboxEvScorePacked` already exists; encoding can be widened or repurposed. ABI: NON-BREAKING.

### §3.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-65` — CATALOG §16 row V-110 + §17 §C-9 / §D-22 / §E-15. v44.0 plan-phase: define snapshot encoding for full activity-score result; route all 3 callsites' downstream consumer SLOADs through the snapshot.

---

## §4 — V-111: mintPacked_ write inside `BoonModule.consumeActivityBoon` (BoonModule.sol:320)

### §4.A — Design-intent backward-trace

`BoonModule.consumeActivityBoon` at `:281` is the activity-boon redemption path. It (1) clears the pending-boon counter on slot1, (2) writes `mintPacked_[player]`'s LEVEL_COUNT field with `levelCount + pending` (saturating uint24), (3) calls `quests.awardQuestStreakBonus`, and (4) emits `BoonConsumed`.

The `mintPacked_[player] = data` SSTORE happens at `BoonModule.sol:320` (verified at source). This callsite is reached via nested delegatecall from `LootboxModule._resolveLootboxCommon:1035` — i.e., inside the lootbox resolution stack itself.

**Why this writer exists.** Activity boons are a deferred-credit mechanism: tickets won through prior coinflip/whale/lootbox boons accumulate as `pending` and redeem into `levelCount` (which feeds `_mintCountBonusPoints`) the next time the player resolves a lootbox.

**Phase-precedent.** Phase 290 MINTCLN — the boon-roll/consume side-effect ordering was canonicalized during the MINTCLN pivot. The discovery here is that the consume side-effect's `mintPacked_` SSTORE happens BEFORE the boon roll consumes its own RNG-derived sub-outputs from the seed (verified by reading `_resolveLootboxCommon` body — `consumeActivityBoon` is invoked early in the resolution to clear pending boons before downstream activity-score-dependent decisions).

### §4.B — Actor game-theory walk

Self-stack write — the consumer is the same stack invocation that mutates the slot. But: the mutation timing is **AFTER seed derivation** (the seed is already keccaked at top of `_resolveLootboxCommon`) and **BEFORE all downstream consumers** that read `mintPacked_`'s LEVEL_COUNT for that same resolution. Because LEVEL_COUNT is consumed by `_mintCountBonusPoints` and by `_playerActivityScore` *within the same resolution stack frame*, the mid-resolution flush of `pending → LEVEL_COUNT` causes the resolution's own activity-score input to shift compared to a hypothetical pre-flush ordering. Whether this is "exploitable" depends on the order of downstream SLOADs vs the consume-write — and the catalog flags it as `EXEMPT-ADVANCEGAME-EQUIVALENT (self-stack post-seed)` audit-conservatively classified VIOLATION.

**EV magnitude:** HIGH. The activity-score-input shift inside the same resolution stack is amplified by the cross-call staticcall pattern: `_lootboxEvMultiplierBps` calls `IDegenerusGame(address(this)).playerActivityScore(player)` (`LootboxModule.sol:444`), and that external call re-enters into `_playerActivityScore` reading the FRESH `mintPacked_` state. If `consumeActivityBoon` was invoked *before* the cross-call staticcall, the freshly flushed `levelCount` is observed; otherwise the stale value is. The current ordering may be correct, but the audit-conservative classification is that any participating-slot write in the same resolution stack is a VIOLATION.

### §4.C — Recommended tactic + rationale + impact

**Tactic (c) — Reorder `consumeActivityBoon` to AFTER all RNG-driven sub-rolls return.** Pure code-movement: invoke `consumeActivityBoon(player)` only after the boon-roll sub-call returns and after the final scaled-payout amount is computed. The credit-to-LEVEL_COUNT side-effect still happens within the same tx, but cannot influence the resolution's own EV-multiplier computation.

**Rationale.** Zero new storage, zero ABI impact, zero new SSTOREs. The side-effect remains atomically tx-bound. The activity-score consumed by the EV multiplier is now the pre-resolution snapshot, eliminating the intra-stack-frame freshness coupling.

**Bytecode impact.** ~0 bytes — pure code-movement. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §4.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-66` — CATALOG §16 row V-111 + §17 §C-9 / §D-23 / §E-16. v44.0 plan-phase: relocate `_consumeActivityBoon` selector dispatch inside `_resolveLootboxCommon` to post-roll position.

---

## §5 — V-112: mintPacked_ write inside `BoonModule._applyBoon` whale-pass branch (BoonModule.sol:303)

### §5.A — Design-intent backward-trace

`BoonModule._applyBoon` at `:303` is the boon-application writer. The whale-pass branch sets a flag in `mintPacked_[player]` (via the `_activateWhalePass` → `_applyWhalePassStats` chain at `Storage.sol:1204`) when a boon-roll grants a whale-pass. This callsite is reached from two distinct stacks:

1. **Self-stack**: from `LootboxModule._applyBoon:1407` invoked inside `_rollLootboxBoons:1109` — i.e., as a side-effect of the resolving player's own lootbox roll.
2. **Cross-EOA**: from `LootboxModule.issueDeityBoon:776` — a deity-pass-holding EOA grants a boon to a recipient address, and if the granted boon type is the whale-pass variant, the recipient's `mintPacked_` is mutated.

**Why this writer exists.** The whale-pass / deity-pass / boon system is a layered reward mechanic: deity-pass holders can issue boons to recipients (daily-rate-limited via `deityBoonDay`/`deityBoonUsedMask`), and the recipient's mint-state gains the corresponding sentinel.

**Phase-precedent.** Phase 294 DPNERF audited the deity-pass gold-nerf path with the discipline that caller-uniformity matters; Phase 290 MINTCLN's `rngLockedFlag`-gated revert pattern applies to writers reachable during the rng-lock window.

### §5.B — Actor game-theory walk

The cross-EOA reach is the load-bearing exploit. A deity-pass-holding attacker can sequence:

1. Observe daily VRF callback lands at block N.
2. Within rngLock window, call `issueDeityBoon(deity, recipient=victim, slot)` — this writes `boonPacked[victim]` (V-120) AND, if the boon type is whale-pass, writes `mintPacked_[victim]`'s frozen-until / bundle-type / has-deity-pass bits via `_applyWhalePassStats`.
3. Victim's next `openLootBox(index)` reads the freshly-mutated `mintPacked_[victim]` in `_playerActivityScore` and in `_resolveLootboxCommon`'s whale-pass-aware branches.

**EV magnitude:** HIGH. Attacker manipulates VICTIM'S resolution — the cross-EOA dimension is novel relative to V-109/V-110 self-mutation. The MINTCLN-precedent `rngLockedFlag` gate would block this on the writer side. Note: the existing `issueDeityBoon` gate requires `rngWordByDay[day] != 0` (i.e., the day's RNG must be published) — which is precisely the WINDOW OPEN condition for this exploit.

### §5.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot whale-bundle / frozen-until state at lootbox allocation.** Mirrors V-109/V-110: snapshot the whale-bundle-relevant bits of `mintPacked_[buyer]` into the per-index allocation, and route `_resolveLootboxCommon` to read those bits from the snapshot rather than live `mintPacked_[player]`.

**Rationale.** The cross-EOA write CANNOT be blocked at the writer's side without breaking the legitimate `issueDeityBoon` UX (deity-pass holders explicitly invoke this to grant boons to recipients). Snapshot at the recipient-side (allocation-time) is the correct symmetric defense: the recipient's lootbox-index records the activity-score input at allocation; subsequent boon-grants change `mintPacked_[recipient]` but NOT the snapshotted value for the already-allocated index.

**Bytecode impact.** Subsumed into V-109/V-110 snapshot block (same `lootboxEvScorePacked` widening). No additional storage. ABI: NON-BREAKING.

### §5.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-67` — CATALOG §16 row V-112 + §17 §C-9 / §D-23 (note: §D-23 covers `consumeActivityBoon`; V-112 maps to the `_applyBoon` writer separately as a logical row). v44.0 plan-phase: ensure the activity-score snapshot includes whale-pass / frozen-until / has-deity-pass bits at allocation.

---

## §6 — V-113: mintPacked_ writes inside `WhaleModule._buyWhaleBundle*` multi-callsite (WhaleModule.sol:210, :303, :419, :516, :548, :589, :669, :944)

### §6.A — Design-intent backward-trace

`WhaleModule._buyWhaleBundle*` is a family of writers for the whale-bundle purchase paths (`buyWhaleBundle`, `buyWhaleHalf`, `buyDeityPass`). The 8 callsites mutate different fields of `mintPacked_[buyer]`:

- `:210` — bundle-purchase entry: read prevData, set FROZEN_UNTIL_LEVEL + BUNDLE_TYPE (verified at source)
- `:303` — half-bundle path: similar update
- `:419, :516, :548, :669, :944` — additional bundle-tier paths (whale-half / whale-quarter / discounted variants), each performing the same FROZEN_UNTIL_LEVEL/BUNDLE_TYPE write pattern
- `:589` — deity-pass purchase HAS_DEITY_PASS bit set (V-114 below — distinct logical writer)

**Why these writers exist.** The whale-bundle product is a paid pre-purchase of multiple mint levels in advance, with the FROZEN_UNTIL_LEVEL sentinel preventing post-purchase price increases on those levels. Each tier (full / half / etc) has its own entry due to differential ETH pricing / boon-coupling.

**Phase-precedent.** Phase 290 MINTCLN's `rngLockedFlag` gate is the canonical fix pattern for purchase-side EOA writers reachable during the rng-lock window.

### §6.B — Actor game-theory walk

Same shape as V-110 but via the WhaleModule purchase entries. The buyer can `buyWhaleBundle*` between the daily VRF callback and his own `openLootBox(index)`, mutating his own `mintPacked_` (and indirectly the activity-score input). Critically, the whale-bundle purchase ALSO sets FROZEN_UNTIL_LEVEL — a field consumed inside `_resolveLootboxCommon`'s lootbox-EV cap derivation (whale-pass-active branches yield different `evMultiplierBps`).

**EV magnitude:** HIGH. Two-fold: (1) the activity-score input shift (LEVEL_COUNT/LEVEL_UNITS) per V-110, plus (2) the whale-pass-active branch flip inside `_resolveLootboxCommon`.

### §6.C — Recommended tactic + rationale + impact

**Tactic (b) — Same snapshot.** Mirror V-110 / V-112: snapshot all whale-relevant mintPacked_ fields into the lootbox-index allocation cell. Consumer reads from snapshot.

**Rationale.** Identical to V-109/V-110/V-112 — close the snapshot to cover all activity-score AND whale-pass-relevant fields.

**Bytecode impact.** Subsumed into the V-109/V-110 snapshot. ~0 marginal bytes. ABI: NON-BREAKING.

### §6.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-68` — CATALOG §16 row V-113 + §17 §C-9 / §D-24 / §E-17.

---

## §7 — V-114: mintPacked_ write inside `WhaleModule._buyDeityPass` (WhaleModule.sol:589)

### §7.A — Design-intent backward-trace

`WhaleModule._buyDeityPass` at `:589` is the deity-pass purchase path. It writes `mintPacked_[buyer]`'s HAS_DEITY_PASS bit (verified at source: `mintPacked_[buyer] = BitPackingLib.setPacked(..., HAS_DEITY_PASS_SHIFT, 1, 1)`), increments `deityPassPurchasedCount[buyer]`, pushes to `deityPassOwners`, sets `deityPassSymbol[buyer]`, and mints the ERC721 deity-pass token. This is a paid EOA path.

**Why this writer exists.** Deity-passes are a scarce paid asset (capped by `DEITY_PASS_MAX_TOTAL`). The HAS_DEITY_PASS bit in `mintPacked_` is the per-player sentinel consumed by various deity-aware code paths (including `issueDeityBoon`'s eligibility check via `deityPassPurchasedCount[deity] == 0`).

**Phase-precedent.** Phase 294 DPNERF (gold-nerf for deity passes) audited the deity-pass mechanic with caller-uniform discipline.

### §7.B — Actor game-theory walk

The deity-pass purchase is paid (`totalPrice` cost) and rate-limited by `DEITY_PASS_MAX_TOTAL`. The exploit during rngLock: a buyer with a pre-allocated lootbox index calls `buyDeityPass` to set HAS_DEITY_PASS_BIT — and `mintPacked_`'s HAS_DEITY_PASS bit may be consumed by `_resolveLootboxCommon`'s deity-pass-aware boon branches (verified via the BoonModule code reading `deityPassPurchasedCount` / deity-related fields).

**EV magnitude:** HIGH. The deity-pass acquisition unlocks an additional class of cross-EOA boon-issuing influence AND mutates the `mintPacked_` slot read during the player's own lootbox resolution. The economic cost (deity-pass price) is bounded but small relative to high-tier lootbox payouts.

### §7.C — Recommended tactic + rationale + impact

**Tactic (a) — Gate `buyDeityPass` on `rngLockedFlag || lootboxRngWordByIndex[currentIdx] != 0`.** Block the purchase entirely during the rng-lock window. The deity-pass is a paid asset, so blocking is economically painful only during the (short) lock window; legitimate buyers can retry post-unlock.

**Rationale.** Unlike V-109/V-110/V-113 (where snapshot is preferred because the writes are high-volume and broad), `buyDeityPass` is a low-volume rare-purchase entry; an outright gate is acceptable UX, and avoids widening the snapshot to include HAS_DEITY_PASS bits (which would couple V-114 into the same snapshot block as V-113 — a tighter fix but more code change).

**Bytecode impact.** ~30-50 bytes — one `if (rngLockedFlag) revert RngLocked();` at the WhaleModule._buyDeityPass entry. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING (gate is silent-revert during lock window).

### §7.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-69` — CATALOG §16 row V-114 + §17 §C-9 / §D-25 / §E-18.

---

## §8 — V-117: mintPacked_ write inside `_applyWhalePassStats` from lootbox boon path (Storage.sol:1204)

### §8.A — Design-intent backward-trace

`_applyWhalePassStats` at `contracts/storage/DegenerusGameStorage.sol:1141` (verified) writes `mintPacked_[player]` when a whale-pass boon activates. The `:1204` callsite is inside the function body where `mintPacked_[player] = data` is committed after FROZEN_UNTIL_LEVEL / BUNDLE_TYPE updates (verified at source — line :1204 reads "`mintPacked_[player] = data;`").

This writer is reached via `_activateWhalePass` ← `BoonModule._applyBoon` whale-pass branch (`:303`) ← `LootboxModule._rollLootboxBoons:1109` ← `_resolveLootboxCommon`. **Self-stack post-seed write** — happens inside the same lootbox-resolution invocation, AFTER `seed` is derived but BEFORE the resolution returns.

**Why this writer exists.** Whale-pass-boon-activation must commit the recipient's frozen-until / bundle-type fields so the bundle protection is in effect at the next purchase. The function is structured as a shared helper because both EOA-purchase (WhaleModule._buyWhaleBundle*) and boon-grant (via lootbox roll) need to apply the same field updates.

**Phase-precedent.** Same shape as V-111's self-stack post-seed write (D-23 → V-111 reorder). Phase 290 MINTCLN ordering discipline applies.

### §8.B — Actor game-theory walk

Self-stack: the write occurs INSIDE the same resolution that reads `mintPacked_` through the activity-score cross-call. The intra-stack-frame ordering question: does `_applyWhalePassStats:1204` SSTORE happen BEFORE or AFTER the staticcall back into `_playerActivityScore`? If BEFORE, the resolution's own scaled-amount is computed on the fresh post-write state — coupling the boon-roll outcome to the activity-score input. If AFTER, the staticcall reads the pre-write state.

**EV magnitude:** HIGH. Like V-111, the self-stack write may shift the resolution's own EV-multiplier computation. The exploit avenue is more nuanced — the buyer cannot directly trigger this write outside a resolution, but the boon-roll branch is RNG-determined, so the buyer's strategy is to favor allocation-vs-resolution orderings that maximize the favorable branch.

### §8.C — Recommended tactic + rationale + impact

**Tactic (c) — Reorder whale-pass side-effect to AFTER roll consumption returns.** Pure code-movement: defer `_applyWhalePassStats` invocation until AFTER `_resolveLootboxRoll` returns and the scaled-amount is finalized. The whale-pass activation still happens in the same tx; the consumer no longer reads a fresh-self-mutated state.

**Rationale.** Same as V-111 — zero new storage, zero ABI impact, eliminates intra-stack-frame freshness coupling. Symmetric with V-111 reorder.

**Bytecode impact.** ~0 bytes — pure code-movement. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §8.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-70` — CATALOG §16 row V-117 + §17 §C-9 / §D-28 / §E-19.

---

## §9 — V-120: boonPacked write inside `LootboxModule._applyBoon` multi-callsite, including `issueDeityBoon` cross-EOA (LootboxModule.sol:1432..:1603 + :799)

### §9.A — Design-intent backward-trace

`boonPacked[player]` is a `struct BoonPacked { uint256 slot0; uint256 slot1; }` declared at `contracts/storage/DegenerusGameStorage.sol:1605` and mapped publicly at `:1614 mapping(address => BoonPacked) public boonPacked;` (verified — the mapping IS `public`, exposing read-only `boonPacked(address)` accessor).

`LootboxModule._applyBoon` at `:1407` is the canonical writer for `boonPacked` slot0 (and partial slot1 for activity-pending writes). The 8 enumerated callsites at `:1432, :1452, :1479, :1503, :1526, :1547, :1568, :1603` cover the boon-type branches (coinflip / purchase / decimator / lootbox / whale / lazy-pass / deity-pass / activity).

This writer is reached from TWO distinct EOA-rooted entry chains:

1. **Self-stack lootbox roll**: `openLootBox` → `_resolveLootboxCommon:960` → `_rollLootboxBoons:1109` → `_applyBoon`. The resolving player's own lootbox grants himself a boon based on the boon-roll outcome (RNG-derived from the per-index seed).
2. **Cross-EOA `issueDeityBoon`**: `DegenerusGame.issueDeityBoon` (cross-EOA dispatcher at `:861`) → `LootboxModule.issueDeityBoon:776` → `_applyBoon` with `recipient` argument. A deity-pass-holding caller grants a boon to an arbitrary recipient address. Gate: `rngWordByDay[day] != 0` (day's RNG must be published) + per-deity / per-recipient daily-rate-limit.

**Why this writer exists.** Boons are the contract's reward overlay — every lootbox roll has a chance to grant the player a per-category boon (5 types). Deity-pass holders additionally grant boons cross-EOA as a paid-asset privilege.

**Phase-precedent.** Phase 294 DPNERF audited deity-pass paths; Phase 296 SWEEP touched cross-EOA mutation patterns.

### §9.B — Actor game-theory walk

The **cross-EOA `issueDeityBoon` vector is the critical finding.** A deity-pass-holding attacker observes the daily VRF callback published at block N, identifies a victim with a pre-allocated lootbox index, and calls `issueDeityBoon(deity=attacker, recipient=victim, slot)` between block N and the victim's `openLootBox(victimIndex)`. The grant writes `boonPacked[victim]` slot0 bits (e.g., lootbox-tier boon) AND may write `mintPacked_[victim]` via the whale-pass branch (V-112 above).

Critical observation: the gate inside `issueDeityBoon` is `rngWordByDay[day] != 0` — which IS the rng-lock window condition. The legitimate-UX premise is that deity-pass holders need same-day RNG to randomize the boon type (`_deityBoonForSlot` uses `rngWordByDay[day]`). Replacing this with `rngWordByDay[day] != 0 && !rngLockedFlag` would change UX: deity holders couldn't issue boons during the lock; if the lock spans most of a day, this materially affects the deity-pass product. However, blocking on a NARROWER condition — "recipient has no open lootbox index ready" — preserves legitimate cross-day issuance while closing the exploit.

**EV magnitude:** HIGH. The attacker grants the victim a SPECIFIC boon (chosen by the attacker via slot mechanic + boon-type derivation from `rngWordByDay[day]`). If the boon shifts the victim's `_resolveLootboxCommon` boon-roll outcome (e.g., flipping the consumer's boon-presence check), the attacker can FORCE the victim's resolution into a less-favorable branch (e.g., consuming a stamped lootbox-boost-day that the victim would otherwise consume more profitably later). This is a CROSS-EOA GRIEFING vector; the attacker may not gain EV but the victim loses EV.

### §9.C — Recommended tactic + rationale + impact

**Tactic (a) — Gate `issueDeityBoon` on the recipient having no open lootbox index ready.** Concretely: add `if (lootboxRngWordByIndex[recipientCurrentIdx] != 0 && recipient has open index in window) revert E();` (the exact recipient-index-tracking depends on the indexing scheme — recipient's pending lootbox index is queryable via the per-player allocation map).

**Rationale.** Targeted gate preserves legitimate cross-day deity-grant UX while eliminating the cross-EOA exploit window. The self-stack reach of `_applyBoon` (entry chain 1 above) is the same shape as V-117 / V-111 (self-stack post-seed) and is logically subsumed under the boon-roll reorder discipline — the v44.0 fix may collapse V-120's self-stack arm into a tactic-(c) reorder, but the headline tactic is (a) for the cross-EOA arm.

**Bytecode impact.** ~50-80 bytes — recipient-side rng-window check at `issueDeityBoon` entry. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING (silent-revert during recipient's active rng-window).

### §9.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-71` — CATALOG §16 row V-120 + §17 §C-15 / §D-38 / §E-27.

---

## §10 — V-121: boonPacked writes inside `WhaleModule._buyWhaleBundle*` (WhaleModule.sol:202, :388, :556, :898)

### §10.A — Design-intent backward-trace

`WhaleModule` writes `boonPacked[buyer]` slots at 4 callsites (verified at source):

- `:202` — `_buyWhaleBundle` boon-application (BoonPacked storage bp = boonPacked[buyer]; reads s0, then conditionally writes WHALE_DAY / WHALE_BOON_CLEAR at `:248`)
- `:388` — `_buyLazyPass` (BoonPacked storage bpLazy = boonPacked[buyer])
- `:556` — `_buyDeityPass` (BoonPacked storage bpDeity = boonPacked[buyer])
- `:898` — lootbox-boost-tier consumption helper (BoonPacked storage bp = boonPacked[player]; clears BP_LOOTBOX at :909/:922)

Each callsite writes different slot-fields: whale-day stamp at :248, lazy-pass-day stamp at the :388 branch, deity-day stamp at :556, and lootbox-tier clear at :909/:922.

**Why these writers exist.** Each whale-bundle purchase grants a corresponding boon to the buyer (whale-day stamp for the regular-rate-purchase variant; lazy-pass for the auto-rebuy variant; deity-day for the deity-pass holder; lootbox-tier consumption for cross-purchase boon-consumption events).

**Phase-precedent.** Phase 290 MINTCLN gate pattern.

### §10.B — Actor game-theory walk

Same shape as V-109/V-110 but via boonPacked instead of mintPacked_. EOA buyer purchases whale-bundle / lazy-pass / deity-pass during the rng-lock window, mutating his own `boonPacked` slot fields. The mutation is consumed by the next `openLootBox`'s boon-roll path inside `_resolveLootboxCommon` (boon expiry check, boon-day-stamp consumption, etc.).

**EV magnitude:** HIGH. The boon-slot fields directly drive the boon-roll body's branch decisions (e.g., whether `bp.slot0` has an active whale-boon affects the lootbox EV-multiplier; whether deity-pass-day is stamped affects deity-aware code paths).

### §10.C — Recommended tactic + rationale + impact

**Tactic (a) — Same MINTCLN-style gate on WhaleModule boon writes.** Concretely: gate the WhaleModule purchase entries on `rngLockedFlag || lootboxRngWordByIndex[buyer's currentIdx] != 0`. Identical pattern to Phase 290 MINTCLN's `MintModule.sol:1221` gate.

**Rationale.** WhaleModule purchases during the rng-lock window are a narrow operational case; blocking them silently-reverts and aligns with the established MINTCLN gating discipline. Snapshot at allocation (tactic-b) is also plausible but adds storage and is harder to specify cleanly for the multi-field boon writes.

**Bytecode impact.** ~30-50 bytes per gated entry × 4 entries ≈ 120-200 bytes total. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §10.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-72` — CATALOG §16 row V-121 + §17 §C-15 / §D-39 / §E-28.

---

## §11 — V-122: boonPacked write inside `MintModule._applyLootboxBoostOnPurchase` (MintModule.sol:1433)

### §11.A — Design-intent backward-trace

The catalog cites `MintModule._processMint` boon write at `:1433`. Verified at source: line `:1433` is inside `_applyLootboxBoostOnPurchase` (private helper invoked from the mint-flow purchase path). At `:1433` the code reads `BoonPacked storage bp = boonPacked[player]; uint256 s0 = bp.slot0;`, checks tier and expiry, then conditionally writes `bp.slot0 = s0 & BP_LOOTBOX_CLEAR` to clear the lootbox-boost-tier when expired (the SSTORE branches are inside this function body around `:1444+`).

**Catalog row reconciliation note:** The catalog labels this as `_processMint` boon write; source confirms it as `_applyLootboxBoostOnPurchase`. The function is invoked from the mint-flow purchase entry, so the catalog's broader name is accurate at the integration level. The line cite `:1433` is the read-and-then-write pattern entry; the actual SSTORE is at a slightly later line within the same function body.

**Why this writer exists.** Lootbox-boost-on-purchase is a feature whereby a player who has been granted a lootbox-tier boon receives a multiplied lootbox allocation on the next ticket purchase. The expiry-clear at :1433+ is the boon-consumption side-effect.

**Phase-precedent.** Phase 290 MINTCLN gate pattern.

### §11.B — Actor game-theory walk

EOA buyer calls `buyTickets` between VRF callback and `openLootBox`. The `_applyLootboxBoostOnPurchase` consumes the lootbox-tier boon (clears the slot), permanently shifting the `boonPacked[buyer].slot0` state for the subsequent `openLootBox`'s boon-roll body. Strategic ordering matters: consuming the boon on a small purchase wastes it; the attacker chooses to consume on the highest-EV purchase. But during the rng-lock window, the buyer KNOWS the published `rngWord` (or `rngWordByDay[day]`) and can compute the optimal consumption ordering with perfect information.

**EV magnitude:** HIGH. The boon-consumption ordering with-vs-without rng-knowledge is a meaningful EV swing.

### §11.C — Recommended tactic + rationale + impact

**Tactic (a) — Same MINTCLN-style gate on MintModule boon writes.** Mirror Phase 290 MINTCLN: gate the boon-consumption write at `_applyLootboxBoostOnPurchase` on `rngLockedFlag` (or more narrowly, on `lootboxRngWordByIndex[buyer's currentIdx] != 0`).

**Rationale.** Identical to V-121's WhaleModule gating. The lootbox-boost-consume side-effect must not occur during the window when the buyer can read the published RNG.

**Bytecode impact.** ~30-50 bytes — one `if (rngLockedFlag) revert RngLocked();` (or equivalent) at the function entry. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §11.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-73` — CATALOG §16 row V-122 + §17 §C-15 / §D-40 / §E-29.

---

## §12 — V-123: boonPacked writes inside `BoonModule.checkAndClearExpiredBoon` (BoonModule.sol:265, :266)

### §12.A — Design-intent backward-trace

`BoonModule.checkAndClearExpiredBoon` at `:120` is a maintenance writer that walks the player's boon slots and clears expired fields. Verified at source: the function reads `s0`, `s1`, walks each boon category (coinflip, lootbox, whale, lazy-pass, deity-pass, purchase, decimator, activity), and clears expired fields by ANDing with `BP_*_CLEAR` masks. The `:265, :266` callsites correspond to the SSTORE pair `if (changed0) bp.slot0 = s0;` / `if (changed1) bp.slot1 = s1;` at the bottom of the function (verified — lines :265, :266 in the source body are exactly these conditional SSTOREs).

This function is reached only from `_rollLootboxBoons:1120` (grep-confirmed by reading the catalog §16 source-attestation row — no other dispatcher exists). It runs as the FIRST step of the boon-roll sub-call, BEFORE any boon-roll-derived consumption of the slots.

**Why this writer exists.** Expiry-clear must run lazily because boons stamp a day at issuance and clear on subsequent access (lazy-cleanup pattern saves SSTOREs vs eager-clear-on-day-rollover). The lazy-clear runs on the lootbox stack to amortize cost into the resolving player's tx.

**Phase-precedent.** Phase 281 owed-salt snapshot precedent: the expiry decision depends on `_simulatedDayIndex()` which reads `block.timestamp`. A miner / sequencer / EOA capable of influencing tx-ordering can shift which day the clear runs on relative to the boon-roll consumption.

### §12.B — Actor game-theory walk

Self-stack write — `checkAndClearExpiredBoon` runs first inside the boon-roll, mutating `bp.slot0`/`bp.slot1` based on `currentDay = _simulatedDayIndex()`. The boon-roll body then reads the post-clear state. An attacker influences `block.timestamp` (limited but non-zero capacity: miners pick the timestamp within a small window; sequencers on L2 have similar latitude; even regular EOAs can choose to call near a day-rollover boundary). The decision-point: a boon stamp at `stampDay = D` expires at `D + EXPIRY` — if `currentDay > D + EXPIRY`, clear; else keep. Calling near the rollover can flip the decision.

**EV magnitude:** HIGH. The expiry decision determines whether the boon's BPS bonus applies to the subsequent boon-roll body. For a lootbox-tier boon worth several percent EV multiplier, the flip-decision is materially exploitable.

### §12.C — Recommended tactic + rationale + impact

**Tactic (b) — Snapshot expiry decision based on day at allocation, not at open.** At lootbox-allocation time (`_allocateLootbox` / `_whaleLootboxAllocate`), snapshot each active boon's `(stampDay, EXPIRY, currentDay)` tuple into the per-index allocation; the consumer reads the snapshotted "is-valid-at-allocation-day" bit rather than re-evaluating at open time.

**Rationale.** Phase 281 owed-salt precedent: any value depending on `block.timestamp`-derived inputs participating in a post-VRF-callback roll must be frozen at allocation. The lazy-clear lifecycle is preserved for the maintenance writer (lazy-clear continues to fire on the next non-allocation-rooted invocation), but the per-resolution consumer reads from the allocation snapshot.

**Bytecode impact.** ~50-100 bytes — small per-boon-category bitfield in the allocation cell. ABI: NON-BREAKING.

### §12.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-74` — CATALOG §16 row V-123 + §17 §C-15 / §D-41 / §E-30.

---

## §13 — V-124: boonPacked slot1 write inside `BoonModule.consumeActivityBoon` (BoonModule.sol:291, :297, :301)

### §13.A — Design-intent backward-trace

`BoonModule.consumeActivityBoon` at `:281` — the SAME function as V-111 — additionally writes `bp.slot1` (not just `mintPacked_`). Verified at source:

- `:291` (`bp.slot1 = s1 & BP_ACTIVITY_CLEAR;`) — deity-day mismatch clear branch
- `:297` (`bp.slot1 = s1 & BP_ACTIVITY_CLEAR;`) — stamp-expiry clear branch
- `:301` (`bp.slot1 = s1 & BP_ACTIVITY_CLEAR;`) — successful-consume clear branch

All three SSTOREs clear the activity-pending field of slot1. They are distinct from V-111's `mintPacked_` write (which credits `pending → levelCount`); V-124 is the slot1 side of the same consume action.

**Why this writer exists.** Same as V-111 — activity-boon is the deferred-credit mechanism. The slot1 clear is the consumption-side bookkeeping (zeroing the pending counter).

**Phase-precedent.** Same as V-111 — Phase 290 MINTCLN ordering discipline.

### §13.B — Actor game-theory walk

Self-stack write — same stack as V-111. The slot1 clear happens early in the resolution; downstream boon-roll body reads the post-clear `bp.slot1`. The intra-stack-frame freshness coupling is identical to V-111: depending on the ordering of slot1 SLOADs (e.g., in `_boonPoolStats` reading slot1's activity-pending field) vs the slot1 SSTORE at :291/:297/:301, the resolution observes one or another state.

**EV magnitude:** HIGH. Same as V-111.

### §13.C — Recommended tactic + rationale + impact

**Tactic (c) — Reorder activity-boon consumption to AFTER all RNG-driven sub-rolls return.** Same recommendation as V-111 — relocate the entire `consumeActivityBoon` invocation to post-roll position. Both the mintPacked_ write (V-111) and the boonPacked.slot1 write (V-124) are inside the same function body; reordering once fixes both.

**Rationale.** Single reorder addresses both V-111 and V-124. Zero new storage. Pure code-movement.

**Bytecode impact.** ~0 bytes — same code-movement as V-111. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING.

### §13.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-75` — CATALOG §16 row V-124 + §17 §C-15 / §D-42 / §E-31.

---

## §14 — V-125: boonPacked writes via BoonModule other-externals (BoonModule.sol:41, :67, :93, :122, :283)

### §14.A — Design-intent backward-trace

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

### §14.B — Actor game-theory walk

Despite the access guards, EOA-induced reach is non-zero:

- `consumeCoinflipBoon`: an EOA triggers BURNIE-coin transfer → COIN/COINFLIP contract enters → calls back into `DegenerusGame.consumeCoinflipBoon(player)` → delegatecalls BoonModule's slot-clearing path. The EOA orchestrates this between rng-lock-window boundaries.
- `consumeDecimatorBoost`: an EOA triggers BURNIE-coin path → similar.
- `consumePurchaseBoost`: reached only via `address(this)` self-call → EOA-triggered when an EOA invokes a DegenerusGame function that internally self-calls consumePurchaseBoost (e.g., a tickets-purchase variant).
- `checkAndClearExpiredBoon` / `consumeActivityBoon`: reached only via internal delegatecall from lootbox resolution → V-123 / V-111+V-124 already classify these (self-stack writes).

So V-125 logically covers the 3 EOA-orchestrated-via-COIN-callback consumers (coinflip, decimator, purchase) and their boonPacked SSTOREs.

**EV magnitude:** HIGH. Each consumer clears a specific boon's BPS multiplier. An EOA observing the published `rngWord` can sequence COIN-callback-induced consumes of boons that are NOT applicable to the upcoming lootbox-roll body, *preserving* the boons that ARE applicable (and thereby flipping the boon-roll body's branch). This is a "consume-the-wrong-boon-first" griefing-of-self-by-design exploit; reverse direction: an attacker may force a victim's boon-consumption via a constructed COIN-transfer/callback ordering — depends on whether the COIN/COINFLIP contracts allow EOA-controlled `player` argument selection.

### §14.C — Recommended tactic + rationale + impact

**Tactic (a) — Gate each EOA-reachable BoonModule external on no-fresh-lootbox-rng-in-window.** Add `if (rngLockedFlag || lootboxRngWordByIndex[player's currentIdx] != 0) revert RngLocked();` at the DegenerusGame.sol dispatchers for `consumeCoinflipBoon`, `consumeDecimatorBoost`, `consumePurchaseBoost`. The `checkAndClearExpiredBoon` and `consumeActivityBoon` dispatchers are internal-only and addressed by V-123 / V-111+V-124 separately.

**Rationale.** Per-callsite VIOLATION enumeration deferred from Phase 298 catalog; v44.0 fix-phase resolves each external on a per-callsite basis. The dispatcher-level gate is the minimal-footprint fix — Solidity-side guard at the DegenerusGame entry, no BoonModule-side change needed.

**Bytecode impact.** ~30-50 bytes × 3 gated entries ≈ 90-150 bytes total. Storage-layout: BYTE-IDENTICAL. ABI: NON-BREAKING (silent-revert during the lock window).

### §14.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-76` — CATALOG §16 row V-125 + §17 §C-15 / §D-43 / §E-32. v44.0 plan-phase: per-callsite verification of each EOA-orchestrated BoonModule external; apply tactic-(a) gate at DegenerusGame dispatcher level.

---

## §15 — V-127: lastPurchaseDay write inside "MintModule purchase entry" — **STALE-PHANTOM**

### §15.A — Design-intent backward-trace and stale-phantom finding

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

### §15.B — Actor game-theory walk

N/A — no writer-callsite to exploit. The row dissolves at the source-attestation step.

**Conservative note for v44.0 plan-phase:** If a future contract revision introduces a MintModule-side `lastPurchaseDay` writer (e.g., for a target-met-on-purchase optimization), the tactic-(a) gate from V-127's catalog rationale would apply: `if (rngLockedFlag) revert RngLocked();` at the writer entry. Until such a writer is introduced, V-127's handoff anchor is a no-op marker.

### §15.C — Recommended disposition + rationale + impact

**Disposition: MARK STALE-PHANTOM, RETAIN HANDOFF ANCHOR.** v44.0 plan-phase should:

1. Re-attest the source state (re-run `grep -n "lastPurchaseDay" contracts/modules/*.sol`).
2. If still no MintModule writer: close the handoff anchor as `RESOLVED-AS-PHANTOM`.
3. If a writer has appeared post-audit (which is unlikely per `feedback_frozen_contracts_no_future_proofing.md` — contracts are frozen at deploy): apply tactic-(a) gate per the original catalog rationale.

**Rationale.** The handoff anchor is retained for continuity with the catalog's 35-VIOLATION tally; the phantom disposition is recorded explicitly so v44.0 does not allocate a sub-phase to a non-existent writer.

**Bytecode impact.** ZERO — no source change applies.

### §15.D — v44.0 handoff anchor

`D-43N-V44-HANDOFF-77` — CATALOG §16 row V-127 + §17 §C-17 / §D-45 (note: D-45 is V-126's row for advanceGame writers; V-127 has no canonical D-row — it is the phantom-row by source-attestation). v44.0 plan-phase: close as RESOLVED-AS-PHANTOM unless re-attestation finds a new writer.

---

## Cluster H Summary

**15 logical VIOLATIONs** enumerated across four sub-families:

| Sub-family | Slot | VIOLATIONs | Tactic mix |
|---|---|---|---|
| presaleStatePacked (S-30) | 1 | V-105 | (b) ×1 |
| mintPacked_ (S-32) | 7 | V-109, V-110, V-111, V-112, V-113, V-114, V-117 | (b) ×4, (c) ×2, (a) ×1 |
| boonPacked (S-34) | 6 | V-120, V-121, V-122, V-123, V-124, V-125 | (a) ×4, (b) ×1, (c) ×1 |
| lastPurchaseDay (S-35) | 1 | V-127 (stale-phantom) | (N/A) |

**Tactic distribution (14 actionable + 1 phantom):**
- **Tactic (a) — rngLock-gated revert:** 6 VIOLATIONs (V-114, V-120, V-121, V-122, V-125, V-127 — phantom)
- **Tactic (b) — snapshot at allocation:** 6 VIOLATIONs (V-105, V-109, V-110, V-112, V-113, V-123)
- **Tactic (c) — pre-lock reorder:** 3 VIOLATIONs (V-111, V-117, V-124)
- **Tactic (d) — immutable:** 0 VIOLATIONs

**EV-tier distribution:**
- **HIGH:** 13 VIOLATIONs (V-109..V-114, V-117, V-120..V-125)
- **MEDIUM:** 2 VIOLATIONs (V-105, V-127-phantom)

**Cross-VIOLATION coupling observations:**

1. **V-109 + V-110 + V-112 + V-113 share a single snapshot block.** Snapshotting the full activity-score input set + whale-bundle/frozen-until/has-deity-pass bits at `_allocateLootbox`/`_whaleLootboxAllocate` resolves all four at once. The snapshot field is `lootboxEvScorePacked[index][player]` (S-9) — widening its bitfield encoding subsumes the four logical VIOLATIONs into a single v44.0 sub-phase.

2. **V-111 + V-124 share a single reorder.** Both are the `consumeActivityBoon` function — V-111 covers the mintPacked_ side, V-124 covers the boonPacked.slot1 side. A single relocation of the `consumeActivityBoon` invocation to post-roll position fixes both.

3. **V-117 is a separate reorder from V-111/V-124.** `_applyWhalePassStats` (reached from the whale-pass boon branch of `_applyBoon`) is a distinct callsite from `consumeActivityBoon`; both need independent reorders.

4. **V-120 is the only cross-EOA-write in the cluster** (`issueDeityBoon` recipient-write). Tactic (a) requires a recipient-side rng-window check, not just a self-gate.

5. **V-125 is a per-callsite-deferred VIOLATION class.** Three EOA-orchestrated COIN-callback dispatchers (consumeCoinflipBoon, consumeDecimatorBoost, consumePurchaseBoost) each need an independent gate; the other two BoonModule externals (checkAndClearExpiredBoon, consumeActivityBoon) are subsumed under V-123 / V-111+V-124.

6. **V-127 is a stale-phantom.** No MintModule lastPurchaseDay writer exists; v44.0 should close the handoff anchor as RESOLVED-AS-PHANTOM after re-attestation.

**Phase 290 MINTCLN + Phase 281 owed-salt + Phase 288 dailyIdx precedents** are cited per-VIOLATION above; no novel methodology required for v44.0 fix-phase planning.

**Handoff register (H-63..H-77):** All 15 anchors locked: D-43N-V44-HANDOFF-63, D-43N-V44-HANDOFF-64, D-43N-V44-HANDOFF-65, D-43N-V44-HANDOFF-66, D-43N-V44-HANDOFF-67, D-43N-V44-HANDOFF-68, D-43N-V44-HANDOFF-69, D-43N-V44-HANDOFF-70, D-43N-V44-HANDOFF-71, D-43N-V44-HANDOFF-72, D-43N-V44-HANDOFF-73, D-43N-V44-HANDOFF-74, D-43N-V44-HANDOFF-75, D-43N-V44-HANDOFF-76, D-43N-V44-HANDOFF-77.

---

*Cluster H FIXREC contribution — Phase 299 Plan 08.*
