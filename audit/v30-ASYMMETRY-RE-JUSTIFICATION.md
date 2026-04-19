---
audit_baseline: 7ab515fe
plan: 239-03
requirement: RNG-03
subsystem: audit
tags: [v30.0, VRF, RNG-03, asymmetry-re-justification, lootbox-index-advance, phaseTransitionActive, first-principles, HEAD-7ab515fe]
---

# v30.0 Two Asymmetries Re-Justified from First Principles (RNG-03)

**Audit baseline:** HEAD `7ab515fe`
**Plan:** 239-03
**Requirement:** RNG-03

## Executive Summary

- **§ Asymmetry A — Lootbox RNG Index-Advance Isolation Equivalent to Flag-Based Isolation** — proof-by-exhaustion at HEAD `7ab515fe`: enumerates every `lootboxRngIndex` advance SSTORE (2 sites via `_lrWrite(LR_INDEX_SHIFT, ...)`) and every `lootboxRngWordByIndex[k]` SSTORE (3 sites) in `contracts/`, shows each write is monotonic or atomic-per-key and originates from a single-writer trust class (VRF coordinator for delivered words; internal helpers for orphan backfill only reachable after fresh VRF post-gap), and concludes the consumer-side read `lootboxRngWordByIndex[frozenConsumerIndex]` cannot be mutated after the index has advanced past `frozenConsumerIndex`. Freeze-guarantee structurally equivalent to `rngLockedFlag` for the mid-day-lootbox path. **AIRTIGHT**.
- **§ Asymmetry B — `phaseTransitionActive` Exemption Admits Only `advanceGame`-Origin Writes** — proof-by-exhaustion at HEAD `7ab515fe`: enumerates every `phaseTransitionActive = true` SSTORE (1 site: `_endPhase @ :634`) and every `phaseTransitionActive = false` SSTORE (1 site: `advanceGame @ :323`), enumerates every SSTORE reachable while the flag is true (via the in-tx trailing SSTOREs in `_endPhase` + the phase-transition branch in subsequent `advanceGame` calls at `:298-330`), and proves by grep-verified single-caller analysis that `_endPhase`'s sole caller is `advanceGame @ :460`. No external entry point can toggle `phaseTransitionActive = true` without first entering `advanceGame`. **AIRTIGHT**.
- **D-14 proof-by-exhaustion discipline:** every claim enumerates specific storage slots + SSTORE sites + call chains at HEAD `7ab515fe`. Prior-milestone artifacts CROSS-CITED with "we independently re-derived the same result" notes only — never as warrant.
- **D-14 KI-as-SUBJECT discipline:** the KNOWN-ISSUES.md entry "Lootbox RNG uses index advance isolation instead of rngLockedFlag" is the SUBJECT of § Asymmetry A (the design decision being re-justified), NOT its warrant. Both proofs hold independently of KI entry existence.
- **D-29 Phase 238 discharge:** § Asymmetry A discharges Phase 238-03 FWD-03 gating `lootbox-index-advance` audit assumption; § Asymmetry B discharges the `phase-transition-gate` audit-assumption portion. Plan 239-01 separately discharges the `rngLocked` portion. No re-edit of Phase 238 files per D-29 — discharge is evidenced by commit presence; Phase 242 REG-01/02 cross-checks at milestone consolidation.

## § Asymmetry A — Lootbox RNG Index-Advance Isolation Equivalent to Flag-Based Isolation

### Asymmetry Statement

**Claim:** For the mid-day-lootbox VRF path, advancing `lootboxRngIndex` at VRF request time and reading `lootboxRngWordByIndex[consumerIndex]` at fulfillment time provides a freeze-guarantee structurally equivalent to the freeze-guarantee `rngLockedFlag` provides for the daily VRF path. Specifically:

> ∀ lootbox consumer C with `consumerIndex = k` frozen at VRF request time, the read `lootboxRngWordByIndex[k]` at fulfillment returns either
> (a) the uninitialized zero sentinel (guarded by consumer-side zero-check per Phase 237 inventory), OR
> (b) the VRF-delivered word for index `k` written atomically by `rawFulfillRandomWords` (mid-day branch) or by `_finalizeLootboxRng` (daily branch carry-over) or by `_backfillOrphanedLootboxIndices` (post-gap fresh-VRF fallback);
> no player, admin, or validator can write `lootboxRngWordByIndex[k]` after the index has advanced past `k`.

**KI context (SUBJECT not warrant per D-14):** the KNOWN-ISSUES.md entry `"Lootbox RNG uses index advance isolation instead of rngLockedFlag"` (L33 block) documents this design decision. This proof re-derives the equivalence **from first principles** at HEAD `7ab515fe`; the KI entry's existence is NOT relied upon as warrant. The KI entry is the SUBJECT being re-justified — the proof holds independently of whether the KI entry exists.

### Storage Primitives

Enumerated at HEAD `7ab515fe` via fresh grep over `contracts/` (excluding `contracts/mocks/`):

- **`lootboxRngPacked` storage slot** — `contracts/storage/DegenerusGameStorage.sol:1290` (`uint256 internal lootboxRngPacked = ...`). Packed 232-bit layout containing 6 fields; bits `[0:47]` are `lootboxRngIndex` (uint48), declared in layout comment at `contracts/storage/DegenerusGameStorage.sol:1280`.
- **`LR_INDEX_SHIFT` / `LR_INDEX_MASK` constants** — `contracts/storage/DegenerusGameStorage.sol:1296-1297` (`uint256 internal constant LR_INDEX_SHIFT = 0;` + `uint256 internal constant LR_INDEX_MASK = 0xFFFFFFFFFFFF;` — 48 bits).
- **`_lrRead(shift, mask)` / `_lrWrite(shift, mask, value)` helpers** — `contracts/storage/DegenerusGameStorage.sol:1315-1322`. `_lrWrite` is the ONLY way to mutate any field of `lootboxRngPacked`; `_lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, ...)` is the ONLY way to mutate the 48-bit index field.
- **`lootboxRngWordByIndex` mapping declaration** — `contracts/storage/DegenerusGameStorage.sol:1345` (`mapping(uint48 => uint256) internal lootboxRngWordByIndex;`). Solidity 0.8.34 mapping semantics: slot of key `k` is `keccak256(abi.encode(k, 1345))`; each slot is independent (per-key atomicity).

Grep commands preserved for reviewer reproducibility:

```bash
grep -rn 'lootboxRngIndex\|LR_INDEX_SHIFT\|LR_INDEX_MASK' contracts/ --include='*.sol' | grep -v mocks
grep -rn 'lootboxRngWordByIndex' contracts/ --include='*.sol' | grep -v mocks
grep -rn '_lrWrite\s*(' contracts/ --include='*.sol' | grep -v mocks
```

### Write Sites

Enumerated at HEAD `7ab515fe`. Two distinct write surfaces: (i) `lootboxRngIndex` advance (via `_lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, ...)`); (ii) `lootboxRngWordByIndex[k]` per-key SSTOREs.

| Site ID | File:Line | Function | Writer Context | Write Semantics |
|---------|-----------|----------|----------------|-----------------|
| ASYM-239-A-W-01 | `contracts/modules/DegenerusGameAdvanceModule.sol:1100-1104` | `requestLootboxRng` (external, permissionless) | Mid-day lootbox VRF request: advances `lootboxRngIndex` by 1 after `vrfCoordinator.requestRandomWords` returns an id (index is advanced AFTER the request so `index - 1` identifies the pending word). Gated upstream by `if (rngLockedFlag) revert RngLocked();` @ `:1031` (daily-RNG lockout subsumes the need for a mid-day lock during daily-RNG windows). | Monotonic +1 on the 48-bit field; no decrement path. 281T-index capacity. |
| ASYM-239-A-W-02 | `contracts/modules/DegenerusGameAdvanceModule.sol:1565-1569` | `_finalizeRngRequest` (private; called from `_requestRng @ :1531` and `_tryRequestRng @ :1550`, both reached only from daily-advanceGame) | Daily VRF request (fresh, non-retry): advances `lootboxRngIndex` by 1 so new purchases target the NEXT RNG index (the current index becomes the key for today's daily RNG word carry-over). Retry path explicitly skips the advance (L1563 `if (!isRetry)` guard) because the index was already advanced on the fresh request. | Monotonic +1 on 48-bit field, conditional on `!isRetry`. Only SSTORE path in the daily-lifetime fresh-request branch. |
| ASYM-239-A-W-03 | `contracts/modules/DegenerusGameAdvanceModule.sol:1204` | `_finalizeLootboxRng` (private; called from `rngGate @ :1182` inside daily `advanceGame`; also from the mid-day reroll-block early finalization at `:267`) | Daily RNG word carry-over: `lootboxRngWordByIndex[index] = rngWord` where `index = lootboxRngIndex - 1`. Guarded by `if (lootboxRngWordByIndex[index] != 0) return;` @ `:1203` (idempotent no-op if already set). | Per-key SSTORE, idempotent (guards against double-set). Only writes to the single index `lootboxRngIndex - 1` (the pending index). |
| ASYM-239-A-W-04 | `contracts/modules/DegenerusGameAdvanceModule.sol:1706` | `rawFulfillRandomWords` (external — callable ONLY by `vrfCoordinator` per `:1694` access check) — mid-day branch (`rngLockedFlag == false` branch @ `:1703`) | Mid-day lootbox VRF fulfillment: `lootboxRngWordByIndex[index] = word` where `index = lootboxRngIndex - 1`. Clears `vrfRequestId = 0` + `rngRequestTime = 0` atomically in the same branch (`:1708-1709`). Reaches this branch only when `rngLockedFlag == false` (daily RNG not locked) AND `requestId == vrfRequestId` AND `rngWordCurrent == 0` (guards at `:1694-1695`). | Per-key SSTORE, atomic with companion VRF-state clears. Single-writer-per-slot (VRF coordinator only). |
| ASYM-239-A-W-05 | `contracts/modules/DegenerusGameAdvanceModule.sol:1763` | `_backfillOrphanedLootboxIndices` (private; called from `rngGate @ :1155` under the post-gap `currentWord != 0 && day > idx + 1` branch) | Post-gap backfill of orphaned indices (indices reserved but never fulfilled because the VRF coordinator stalled for ≥ 2 days). Scans backwards from `lootboxRngIndex - 1`, filling any zero slot with `keccak256(freshVrfWord, i)`. Breaks at the first filled slot encountered (`:1757`). Reachable only after a fresh daily VRF word arrives post-gap (i.e., `rawFulfillRandomWords` daily branch delivered, unlocking `_applyDailyRng` and thus `rngGate` consumption). | Per-key SSTORE, backward scan with break-at-first-filled. Write value is deterministic on a fresh VRF-delivered word; not a player-controlled value. |

**Row count reconciliation:** `grep -rnE 'lootboxRng(Index|WordByIndex)\[' contracts/ --include='*.sol' | grep -v mocks | grep -E '=\s*'` at HEAD returns the 3 `lootboxRngWordByIndex[x] = ...` SSTOREs (L1204, L1706, L1763). `grep -rn '_lrWrite(LR_INDEX_SHIFT' contracts/ --include='*.sol'` returns the 2 index-advance sites (L1100, L1565). Write Sites row count = 5 ≥ mechanical grep count = 5. Exhaustiveness preserved.

### Read Sites

Consumer-side reads of `lootboxRngWordByIndex[consumerIndex]`. Phase 237 Consumer Inventory §"Consumer Index" maps the RNG-03 mid-day-lootbox family to 19 PREFIX-MIDDAY rows (INV-237-107..125 per 237-03 Decision 4; the 8-row EntropyLib EXC-04 subset at INV-237-131/132/134..138 routes via `lootboxRngWordByIndex` indirectly via `EntropyLib.entropyStep(seed, ...)` — Phase 238-03 SUMMARY Named-Gate distribution assigns these to `lootbox-index-advance`).

| Site ID | File:Line | Function | Read Context | consumerIndex Freeze Citation |
|---------|-----------|----------|--------------|-------------------------------|
| ASYM-239-A-R-01 | `contracts/modules/DegenerusGameAdvanceModule.sol:204-206` | `advanceGame` mid-day wait-gate (`day == dailyIdx` path @ `:199-233`) | Reads `lootboxRngWordByIndex[lootboxRngIndex - 1]` — checks whether the pending mid-day VRF word has been delivered before processing tickets. Reverts `RngNotReady` if word is zero (`:207`). | `lootboxRngIndex - 1` pinned at read time from current packed slot. No `consumerIndex` freeze required here — this is a liveness gate, not a per-consumer derivation. |
| ASYM-239-A-R-02 | `contracts/modules/DegenerusGameAdvanceModule.sol:261` | `advanceGame` daily-drain-gate (`:255-279` pre-RNG) | Reads `lootboxRngWordByIndex[preIdx]` where `preIdx = lootboxRngIndex - 1`. If zero, falls back to `rngWordCurrent + totalFlipReversals` and synthesizes a daily-RNG-derived word via `_finalizeLootboxRng(cw)` @ `:267`. | `preIdx` pinned at read time. This is the drain-path reconciliation (daily RNG word carry-over), not a player-controlled consumer. |
| ASYM-239-A-R-03 | `contracts/modules/DegenerusGameDegeneretteModule.sol:430` | `reverseFlip` (permissionless; rngLockedFlag-gated per Plan 239-02 PERM-239-062) | Reads `lootboxRngWordByIndex[index]` where `index = lootboxRngIndex` (note: **NOT** `- 1`; reverts with `RngNotReady()` if nonzero — inverts the usual semantics as a safety check). | `index` pinned at read time. Gate: `rngLockedFlag` + mid-day-sentinel checks elsewhere. |
| ASYM-239-A-R-04 | `contracts/modules/DegenerusGameDegeneretteModule.sol:574` | `creditDegeneretteRewards` (Coinflip-internal via delegatecall; carries `onlyCoinflip` / module-internal gate) | Reads `lootboxRngWordByIndex[index]` — consumer-side read for the rewards derivation using the lootbox word. `index` frozen at the caller's commit time (DegeneretteModule uses per-player `index` frozen in the `boonStake` storage); the frozen consumerIndex is what the freeze-guarantee protects. | Per-player freeze at boon-stake commit time; consumer-index recorded as a per-player storage slot that cannot be mutated between commit and fulfillment (see Phase 237 INV-237-107..125 PREFIX-MIDDAY chain freezing analysis). |
| ASYM-239-A-R-05 | `contracts/modules/DegenerusGameLootboxModule.sol:533` | `openLootBox` / `openBurnieLootBox` path (permissionless opens; rngLockedFlag-gated per Plan 239-02 PERM-239-046 / PERM-239-047) | Reads `lootboxRngWordByIndex[index]` for the lootbox-open reward derivation. `index` is pinned from per-player storage (`lootboxDay[idx][player]`-paired ownership) — frozen at purchase/queue time. | `index` frozen at lootbox purchase commitment; cannot be mutated by the player after commit. See Phase 237 INV-237-107..125. |
| ASYM-239-A-R-06 | `contracts/modules/DegenerusGameLootboxModule.sol:611` | `openLootBox` / `openBurnieLootBox` alternate-path read — second lootbox word read inside same family chain. | As R-05. | As R-05. |
| ASYM-239-A-R-07 | `contracts/modules/DegenerusGameMintModule.sol:690` | Mint-phase entropy read (`entropy = lootboxRngWordByIndex[lootboxRngIndex - 1]`) | Reads the word at the pending index (index - 1) as entropy for a mint-phase randomization. `lootboxRngIndex - 1` pinned at read time. | Same-tx atomic-read; no freeze semantics required (the read value affects the same transaction's trait assignment). |

**Cross-reference to Phase 237 Consumer Inventory:** 19 PREFIX-MIDDAY rows (INV-237-107..125) trace the per-consumer `consumerIndex` freeze and the read site through the shared MIDDAY prefix. 20-row total for Phase 238-03 `lootbox-index-advance` Named-Gate distribution (19 PREFIX-MIDDAY + 1 INV-237-124 daily-subset EXC-04 routed via index-advance per 238-03 SUMMARY D-06 EntropyLib routing). Additional 7 EntropyLib EXC-04 rows (INV-237-131/132/134..138) derive entropy via `EntropyLib.entropyStep(lootboxRngWordByIndex[k], ...)` — the load-bearing freeze of the seed word is exactly what this asymmetry proves.

### Equivalence Proof

**Invariant (Asymmetry A):** ∀ lootbox consumer C with `consumerIndex = k` frozen at VRF request time,

    Read lootboxRngWordByIndex[k] at fulfillment returns exactly one of:
        (a) 0  (uninitialized sentinel — guarded by consumer-side zero-check per Phase 237 inventory; consumer reverts RngNotReady or defers)
        (b) w  where w is the VRF-delivered word for index k, written atomically by one of:
              - Write Site ASYM-239-A-W-04 (rawFulfillRandomWords mid-day branch @ :1706)
              - Write Site ASYM-239-A-W-03 (_finalizeLootboxRng @ :1204 — daily RNG word carry-over to lootboxRngWordByIndex[lootboxRngIndex - 1])
              - Write Site ASYM-239-A-W-05 (_backfillOrphanedLootboxIndices @ :1763 — post-gap fresh-VRF-derived fallback)

**Freeze-Guarantee:** No player, admin, or validator can write `lootboxRngWordByIndex[k]` after the index has advanced past `k`, because:

1. **Single writer set to the mapping.** The ONLY SSTORE sites to `lootboxRngWordByIndex[...]` in `contracts/` at HEAD `7ab515fe` are ASYM-239-A-W-03/04/05 (L1204, L1706, L1763). Verified by `grep -rnE 'lootboxRngWordByIndex\[[^\]]+\]\s*=' contracts/ --include='*.sol' | grep -v mocks` returning exactly those three lines. No other contract in the inventory (Phase 237) writes to this mapping.

2. **ASYM-239-A-W-04 caller-gate.** `rawFulfillRandomWords` is guarded by `if (msg.sender != address(vrfCoordinator)) revert E();` @ `:1694`. `vrfCoordinator` is mutated only via `wireVrf` (admin-gated @ `:500`) and `updateVrfCoordinatorAndSub` (admin-gated @ `:1627`). Therefore the mid-day branch SSTORE is callable only by the Chainlink VRF coordinator EOA/contract. A player cannot impersonate the coordinator; an admin can only rotate the coordinator (re-pointing subsequent fulfillments, not retroactively overwriting prior indices).

3. **ASYM-239-A-W-03 caller-chain.** `_finalizeLootboxRng` is `private` and reached only from (a) `rngGate @ :1182` (inside `advanceGame`'s daily body after `_applyDailyRng` delivered the daily word), and (b) the daily-drain-gate at `:267` inside `advanceGame` when the pending index still reads zero. Both chains root at `advanceGame` and can only write to the single index `lootboxRngIndex - 1` (the pending index). After index advance past that value, `_finalizeLootboxRng` targets a different key on subsequent advanceGame calls — it cannot retroactively overwrite an earlier index's slot.

4. **ASYM-239-A-W-05 caller-chain.** `_backfillOrphanedLootboxIndices` is `private` and reached only from `rngGate @ :1155` under the post-gap branch (`currentWord != 0 && day > idx + 1`). Called exactly once per post-gap fresh-VRF delivery, with `vrfWord` being the just-delivered fresh VRF word. The backfill scans backwards from `lootboxRngIndex - 1` and BREAKS at the first filled slot (`:1757 if (lootboxRngWordByIndex[i] != 0) break;`). Therefore: once an index `k` has received a word (from W-03 or W-04 or a prior W-05 pass), W-05 cannot overwrite it. Furthermore, the value written by W-05 is deterministic on a VRF-derived seed, not on any player-controlled state.

5. **Per-key atomicity (Solidity 0.8.34 mapping semantics).** Each `lootboxRngWordByIndex[k]` slot is `keccak256(abi.encode(k, 1345))` — a distinct 256-bit storage slot per key. Writing to index `k+1` has no effect on the slot for index `k`. Combined with single-writer-per-write-site (W-03/04/05 target `lootboxRngIndex - 1` at call time), the only way slot `k` can receive a value is when `lootboxRngIndex - 1 == k` at call time.

6. **Monotonic index advance.** `lootboxRngIndex` is advanced only by W-01 (`requestLootboxRng :1100`) and W-02 (`_finalizeRngRequest :1565`). Both are monotonic `+1` on the 48-bit field (`_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK) + 1`). There is no decrement path, no reset, no admin reconfiguration. Therefore once `lootboxRngIndex` has advanced past `k` (i.e., `lootboxRngIndex > k + 1`), no future write site can target slot `k`: W-03/W-04 write to `lootboxRngIndex - 1 != k`; W-05 breaks at the first filled slot when scanning backwards.

**Equivalence to rngLockedFlag:** The freeze-guarantee above is structurally equivalent to the `rngLockedFlag` guarantee for the daily VRF path, in the following sense:

- **`rngLockedFlag` (daily path):** ALL player-reachable mutations that affect daily-RNG consumer state are gated behind `if (rngLockedFlag) revert RngLocked();` @ `DegenerusGameAdvanceModule.sol:1031` (and the `rngLocked()` view-exposed gate points throughout the codebase — re-verified at HEAD `7ab515fe` per Plan 239-01 RNG-01 output `audit/v30-RNGLOCK-STATE-MACHINE.md`). Any attempted player mutation between daily VRF request and consumption reverts; therefore the consumed slot is frozen from request to fulfillment.

- **`lootbox-index-advance` (mid-day-lootbox path):** the `consumerIndex` freeze (at VRF request time) combined with mapping-slot atomicity (Solidity per-key independence) combined with monotonic index advance (strictly `+1` at W-01/W-02) combined with single-writer-per-slot (only W-03/W-04/W-05 write the mapping, and each targets only the current `lootboxRngIndex - 1` or the backward-scan fill-zero slot) composes to the same "no mutable-after-request" property for the specific storage slot `lootboxRngWordByIndex[k]` read by consumer C with `consumerIndex = k`.

Both mechanisms guarantee: **between the moment a consumer commits its input (daily-RNG-dependent read OR mid-day-lootbox index-pinned read) and the moment the consumer reads the RNG word, no adversarial mutation of the underlying storage slot is reachable.** The mechanisms differ in the specific storage locations gated (a global boolean for daily vs. a per-key mapping for lootbox) but the freeze-proof property is preserved by construction in both.

**Conclusion:** Asymmetry A is re-justified from first principles at HEAD `7ab515fe`. The lootbox-index-advance mechanism provides freeze-guarantee equivalent to flag-based isolation for the mid-day-lootbox VRF path. **AIRTIGHT**. ∎

### Discharge of Phase 238-03 FWD-03 gating `lootbox-index-advance` audit assumption (D-29)

Phase 238-03 FWD-03 gating cited `lootbox-index-advance` gate correctness as an audit assumption pending Phase 239 RNG-03(a) first-principles re-proof (Scope-Guard Deferral #1 in `audit/v30-FREEZE-PROOF.md`, paired with the `rngLocked` portion discharged by Plan 239-01). This § Asymmetry A proof **DISCHARGES** the `lootbox-index-advance` portion of Scope-Guard Deferral #1. Evidence: the freeze-guarantee enumerated in §"Equivalence Proof" derives from Storage Primitives + Write Sites + single-writer analysis at HEAD `7ab515fe` — none of Phase 238's output files are relied upon as warrant. Per D-29, no re-edit of Phase 238 files. Discharge is evidenced by commit presence; Phase 242 REG-01/02 cross-checks at milestone consolidation.

## § Asymmetry B — phaseTransitionActive Exemption Admits Only advanceGame-Origin Writes

### Asymmetry Statement

**Claim:** The `phaseTransitionActive` storage flag, when `true`, exempts writes from the `rngLocked` guard that would otherwise block mutation during the VRF commitment window. This proof demonstrates that (a) every SSTORE reachable while `phaseTransitionActive = true` originates inside `advanceGame`'s execution context, and (b) no external entry point can toggle `phaseTransitionActive` to `true` without first entering `advanceGame` — therefore the exemption creates no player-reachable mutation path to RNG-consumer state.

**Context:** Phase 238-03's `phase-transition-gate` Named-Gate classification appears as a COMPANION gate (not PRIMARY) in the 238-03 Gating Verification Table per Phase 238-03 SUMMARY (0 rows as PRIMARY gate; appears as secondary cover on PREFIX-DAILY / PREFIX-MIDDAY / PREFIX-GAMEOVER chains whose Forward Mutation Paths touch the `phaseTransitionActive` slot). The PRIMARY gate on those rows is `rngLocked` (daily/gameover) or `lootbox-index-advance` (mid-day) — `phaseTransitionActive` is secondary. This proof re-justifies the companion-gate semantics **from first principles** at HEAD `7ab515fe`.

### Storage Primitives

Enumerated at HEAD `7ab515fe` via fresh grep over `contracts/` (excluding `contracts/mocks/`):

- **`phaseTransitionActive` storage slot declaration** — `contracts/storage/DegenerusGameStorage.sol:282` (`bool internal phaseTransitionActive;`). Layout comment at `contracts/storage/DegenerusGameStorage.sol:56` (`| [22:23] phaseTransitionActive    bool     Level transition in progress       |`). Single boolean slot; no packed sibling mutation path.
- **Set site (`phaseTransitionActive = true`)** — `contracts/modules/DegenerusGameAdvanceModule.sol:634` inside `_endPhase()` (private, defined at `:632-640`). **Exactly one `= true` site in the entire `contracts/` tree** (verified by grep below).
- **Clear site (`phaseTransitionActive = false`)** — `contracts/modules/DegenerusGameAdvanceModule.sol:323` inside `advanceGame`'s phase-transition-done branch (`:298-330`). **Exactly one `= false` site in the entire `contracts/` tree**.
- **Gate branch (`if (phaseTransitionActive)`)** — `contracts/modules/DegenerusGameAdvanceModule.sol:298` inside `advanceGame`'s do-while body (after `rngGate` returns a fulfilled VRF word).

Grep commands preserved for reviewer reproducibility:

```bash
grep -rn 'phaseTransitionActive' contracts/ --include='*.sol' | grep -v mocks
grep -rnE 'phaseTransitionActive\s*=' contracts/ --include='*.sol' | grep -v mocks
grep -rnE '_endPhase\s*\(' contracts/ --include='*.sol' | grep -v mocks
```

Raw counts at HEAD `7ab515fe`:
- Total `phaseTransitionActive` references (all): 5 (1 layout comment + 1 declaration + 1 set site + 1 clear site + 1 gate branch)
- SSTORE sites to `phaseTransitionActive`: 2 (set @ `:634`, clear @ `:323`)
- `_endPhase(...)` definitions: 1 (`:632`)
- `_endPhase(...)` call sites: 1 (`:460` inside `advanceGame` jackpot-phase terminal branch — `jackpotCounter >= JACKPOT_LEVEL_CAP`)

### Enumerated SSTORE Sites Under phaseTransitionActive = true

The `phaseTransitionActive = true` window spans from the SSTORE at `:634` (inside `_endPhase`, which is itself inside `advanceGame`'s jackpot-phase terminal branch at `:460`) until the SSTORE at `:323` (inside `advanceGame`'s phase-transition-done branch). Because `advanceGame` breaks out of its do-while after `_endPhase` (via `stage = STAGE_JACKPOT_PHASE_ENDED; break;` at `:461-462`) and the `phase-transition-done` branch is inside a SUBSEQUENT `advanceGame` invocation (gated by `if (phaseTransitionActive)` at `:298`), the window spans **at least one transaction boundary and possibly many** (if `_processFutureTicketBatch` returns `!ffFinished` at `:319` the flag is NOT cleared, stage = `STAGE_TRANSITION_WORKING`, break at `:321`, and the next `advanceGame` caller re-enters the `if (phaseTransitionActive)` branch).

Two classes of SSTOREs are reachable under `phaseTransitionActive = true`:

**Class 1: Same-tx SSTOREs inside `_endPhase` after the set site.**
These execute in the same transaction as the `= true` SSTORE at `:634`.

**Class 2: Subsequent-tx SSTOREs in the `if (phaseTransitionActive)` branch of `advanceGame` @ `:298-330`** — reachable in any `advanceGame` invocation after the flag is set and before it is cleared at `:323`.

Enumerated below (`Site ID | File:Line | Function | SSTORE Target | Call-Chain Root`):

| Site ID | File:Line | Function | SSTORE Target (storage slot / mapping key) | Call-Chain Root |
|---------|-----------|----------|--------------------------------------------|-----------------|
| ASYM-239-B-S-01 | `contracts/modules/DegenerusGameAdvanceModule.sol:634` | `_endPhase` (private) | `phaseTransitionActive = true` (the set site itself — terminus of the in-tx path BEFORE the flag is true; included here as the atomic pair to the trailing SSTOREs for exhaustiveness) | `advanceGame` → `_endPhase` (only caller @ `:460`) |
| ASYM-239-B-S-02 | `contracts/modules/DegenerusGameAdvanceModule.sol:636` | `_endPhase` (private) — conditional (`lvl % 100 == 0`) | `levelPrizePool[lvl] = _getFuturePrizePool() / 3` (ONLY at multiples of 100 — century boundaries) | `advanceGame` → `_endPhase` |
| ASYM-239-B-S-03 | `contracts/modules/DegenerusGameAdvanceModule.sol:638` | `_endPhase` (private) | `jackpotCounter = 0` | `advanceGame` → `_endPhase` |
| ASYM-239-B-S-04 | `contracts/modules/DegenerusGameAdvanceModule.sol:639` | `_endPhase` (private) | `compressedJackpotFlag = 0` | `advanceGame` → `_endPhase` |
| ASYM-239-B-S-05 | `contracts/modules/DegenerusGameAdvanceModule.sol:312` | `advanceGame` phase-transition branch (entered under `if (phaseTransitionActive)` @ `:298`) | `ticketLevel = ffLevel \| TICKET_FAR_FUTURE_BIT` (FF-drain setup) | `advanceGame` (own-body SSTORE under `phaseTransitionActive = true` branch) |
| ASYM-239-B-S-06 | `contracts/modules/DegenerusGameAdvanceModule.sol:313` | `advanceGame` phase-transition branch | `ticketCursor = 0` | `advanceGame` (own-body SSTORE) |
| ASYM-239-B-S-07 | `contracts/modules/DegenerusGameAdvanceModule.sol:307` (delegatecall boundary) | `_processPhaseTransition` (private) → via AdvanceModule body `:1475-1498`: calls `_queueTickets(SDGNRS, ...)` @ `:1480-1485` + `_queueTickets(VAULT, ...)` @ `:1486-1491` + `_autoStakeExcessEth()` @ `:1495` | `ticketQueue[targetLevel]` appends (via `_queueTickets`, `DegenerusGameStorage.sol:557-590`); no SSTORE in `_autoStakeExcessEth` beyond the balance-effect of the external `steth.submit` call (no in-contract storage mutation) | `advanceGame` → `_processPhaseTransition` (private, only caller @ `:307`) |
| ASYM-239-B-S-08 | `contracts/modules/DegenerusGameAdvanceModule.sol:315` (delegatecall boundary) | `_processFutureTicketBatch` → delegatecall to `ContractAddresses.GAME_MINT_MODULE.processFutureTicketBatch` @ `:1387-1395` | FF-ticket-queue mutations inside MintModule's `processFutureTicketBatch` — all scoped to ticket-queue slots keyed on far-future level (`TICKET_FAR_FUTURE_BIT | ffLevel`). Delegatecall preserves `msg.sender` and storage context — `advanceGame`'s ticket-queue slots are the only storage mutated. | `advanceGame` → `_processFutureTicketBatch` → delegatecall MintModule |
| ASYM-239-B-S-09 | `contracts/modules/DegenerusGameAdvanceModule.sol:323` | `advanceGame` phase-transition-done branch | `phaseTransitionActive = false` (the clear site — terminus of the window) | `advanceGame` (own-body SSTORE; clear site is the exit) |
| ASYM-239-B-S-10 | `contracts/modules/DegenerusGameAdvanceModule.sol:324` | `advanceGame` phase-transition-done branch → calls `_unlockRng(day)` @ `:1674-1681` | `dailyIdx = day` (`:1675`), `rngLockedFlag = false` (`:1676`), `rngWordCurrent = 0` (`:1677`), `vrfRequestId = 0` (`:1678`), `rngRequestTime = 0` (`:1679`) + `_unfreezePool()` call (`:1680`) — ALL 5 SSTOREs atomic with clear | `advanceGame` → `_unlockRng` (private) |
| ASYM-239-B-S-11 | `contracts/modules/DegenerusGameAdvanceModule.sol:325` | `advanceGame` phase-transition-done branch | `purchaseStartDay = day` | `advanceGame` (own-body SSTORE) |
| ASYM-239-B-S-12 | `contracts/modules/DegenerusGameAdvanceModule.sol:326` | `advanceGame` phase-transition-done branch | `jackpotPhaseFlag = false` | `advanceGame` (own-body SSTORE) |
| ASYM-239-B-S-13 | `contracts/modules/DegenerusGameAdvanceModule.sol:328` | `advanceGame` phase-transition-done branch → `_evaluateGameOverAndTarget(lvl, day, day)` | Potential `gameOverPossible = true/false` flip + other game-over-evaluation SSTOREs inside `_evaluateGameOverAndTarget` (`:1824-...`) — all scoped to game-state flags, not RNG-consumer input state | `advanceGame` → `_evaluateGameOverAndTarget` (private) |
| ASYM-239-B-S-14 | Also via `rngGate` @ `:283` before reaching `:298` — the `rngGate` call itself may produce SSTOREs (daily-RNG processing, `_applyDailyRng`, `_backfillGapDays`, `_backfillOrphanedLootboxIndices`, `_finalizeLootboxRng`, VRF request path via `_requestRng` / `_finalizeRngRequest`) — **BUT** on the phase-transition-entry call, `rngWord` is non-sentinel (otherwise the `if (rngWord == 1)` branch at `:291` would have broken out before reaching `:298`). The `rngGate`-produced SSTOREs are UPSTREAM of the `if (phaseTransitionActive)` branch and are covered by Plan 239-01's RNG-01 state-machine proof (not re-enumerated here — they are `rngLocked`-gated per RNG-01). | Listed for exhaustiveness only; not counted as "new" SSTOREs under `phaseTransitionActive = true` distinct from the broader RNG-01 surface. | `advanceGame` → `rngGate` |

**Row count reconciliation:** 13 enumerated SSTORE sites (ASYM-239-B-S-01..13) directly under the `phaseTransitionActive = true` window. The control-flow walk from set (`:634`) to clear (`:323`) covers: (i) the trailing in-tx SSTOREs in `_endPhase` (B-S-01..04), (ii) the phase-transition branch SSTOREs in subsequent `advanceGame` calls (B-S-05..13). Row B-S-14 is a reachability note for `rngGate` upstream SSTOREs (covered by RNG-01). Write Sites row count = 13 ≥ mechanical enumeration count = 13.

### Call-Chain Rooting Proof

**Invariant (Asymmetry B, part 1):** ∀ Site ID S ∈ Enumerated SSTORE Sites (sub-section above), S's call chain roots at `advanceGame`. Specifically:

1. **`advanceGame` is the only external entry point that (transitively) calls `_endPhase`.** Verified by grep:
   ```
   grep -rnE '_endPhase\s*\(' contracts/ --include='*.sol' | grep -v mocks
   → contracts/modules/DegenerusGameAdvanceModule.sol:460:                    _endPhase();
   → contracts/modules/DegenerusGameAdvanceModule.sol:632:    function _endPhase() private {
   ```
   Exactly one caller at `:460` (inside `advanceGame`'s do-while jackpot-phase branch, gated by `if (jackpotCounter >= JACKPOT_LEVEL_CAP)` at `:459`). The function definition at `:632` is `private` (no selector, no external call surface).

2. **`_endPhase` is the only function that sets `phaseTransitionActive = true`.** Verified by grep:
   ```
   grep -rnE 'phaseTransitionActive\s*=\s*true' contracts/ --include='*.sol' | grep -v mocks
   → contracts/modules/DegenerusGameAdvanceModule.sol:634:        phaseTransitionActive = true;
   ```
   Exactly one site at `:634` (inside `_endPhase`).

3. **Combining (1) and (2):** the only way `phaseTransitionActive` becomes `true` is via the call chain `EOA → advanceGame (external :156) → do-while jackpot-phase (:446-472) → _endPhase (:460) → :634 SSTORE`. Therefore every SSTORE executed while `phaseTransitionActive = true` has a call chain that passes through `advanceGame`.

4. **The phase-transition branch SSTOREs (B-S-05..13) are themselves inside `advanceGame`'s do-while body** (`:298-330`). Entry to this branch requires `phaseTransitionActive == true` AND having reached the top of the do-while AND `rngWord != 1` (fresh VRF fulfilled). Therefore these SSTOREs execute in a subsequent `advanceGame` call after `_endPhase` landed — but still rooted at `advanceGame`.

5. **Delegatecall boundaries preserve storage context.** `_processFutureTicketBatch` (B-S-08) delegatecalls `GAME_MINT_MODULE.processFutureTicketBatch` (`:1387-1395`). Solidity `delegatecall` executes the callee's bytecode in the caller's storage context — the MintModule module code does NOT have its own storage slots; it reads/writes the `DegenerusGame.sol` contract's slots via the shared `DegenerusGameStorage` base contract (per CONTEXT.md `<code_context>` and 238 `<domain>`). Therefore even delegatecall-reached SSTOREs under `phaseTransitionActive = true` root at `advanceGame`.

**Proof-by-exhaustion summary:** every SSTORE in the B.3 table has call-chain root = `advanceGame`. The EVM's single-threaded transaction execution model guarantees these SSTOREs cannot be interleaved with unrelated transactions (a mutation in transaction T cannot observe `phaseTransitionActive = true` unless T itself executes a path rooted at `advanceGame` that has already set the flag, OR a prior transaction's `_endPhase` committed the flag to storage without clearing it — in which case the next `advanceGame` invocation reaches the `if (phaseTransitionActive)` branch and clears it). ∎

### No Player-Reachable Mutation-Path Proof

**Invariant (Asymmetry B, part 2):** No player-callable function can reach any SSTORE in the Enumerated SSTORE Sites table under the condition `phaseTransitionActive = true` other than via the `advanceGame`-rooted chain above.

**Proof by exhaustion over external entry points:**

Forward-cite Plan 239-02 RNG-02 Pass 1 candidate universe — `audit/v30-PERMISSIONLESS-SWEEP.md ## Pass 1 — Mechanical Grep Discovery` (62 permissionless-function candidates after two-pass filtering at HEAD `7ab515fe`; D-09 taxonomy). For each external entry E in that universe:

1. **If E is admin-gated** (`onlyAdmin`, `onlyOwner`, `onlyGovernance`, `onlyVaultOwner`, `onlyBurnieCoin`, `onlyCoin`, `onlyDegenerusGameContract`, `onlyFlipCreditors`, `onlyGame`, `onlyVault`): E is excluded from player-actor-class reachability. Phase 238 BWD-03 / FWD-02 adversarial-closure `admin` class owns admin paths — not player. Out of scope for "player-reachable".

2. **If E is game-internal** (`onlyGame`, `onlyCoinflip`, self-call, delegatecall-only-invoked): E is not a player-EOA entry point. Routed to internal call-graph; covered by the B.4 call-chain rooting proof above.

3. **If E is `view` / `pure`**: no storage mutation. Trivially no player-reachable mutation.

4. **If E is permissionless AND mutating** (`respects-rngLocked`, `respects-equivalent-isolation`, or `proven-orthogonal` per RNG-02 D-08):
   - **`respects-rngLocked` (24 rows in RNG-02)**: guarded by `if (rngLockedFlag) revert RngLocked();` (or inherited equivalent). On the phase-transition window entry point, `rngLockedFlag` is `true` at set time of `phaseTransitionActive` (because `_endPhase` is reached via `payDailyJackpotCoinAndTickets` inside `advanceGame`'s daily fulfillment flow, after `rngLockedFlag` was set in a prior `_finalizeRngRequest` on a different tx). Therefore player-reachable writes via these 24 entries are BLOCKED by `rngLockedFlag` while `phaseTransitionActive` is concurrently `true`. Even if a player calls one of these 24 entries during the window, the `rngLockedFlag` revert fires FIRST. **No player-reachable mutation path.**
   - **`proven-orthogonal` (38 rows in RNG-02)**: writes to state no RNG consumer reads (disjointness with RNG-consumer read set per Phase 237 inventory). Even if a player calls one of these 38 entries during the window, the resulting SSTORE does NOT affect any RNG-consumer read surface. **No mutation path to RNG-consumer state.**
   - **`respects-equivalent-isolation` (0 rows in RNG-02 per Plan 239-02 SUMMARY)**: empty set at HEAD `7ab515fe`; no rows to analyze.

5. **The `advanceGame` external entry itself** is permissionless (external; anyone can trigger). It DOES eventually call `_endPhase` under the terminal-jackpot condition (`jackpotCounter >= JACKPOT_LEVEL_CAP`), and subsequent invocations reach the phase-transition branch at `:298-330`. However:
   - The SSTOREs in the B.3 table that execute while `phaseTransitionActive = true` execute INSIDE `advanceGame`'s own transaction — they cannot be interleaved with mutations from OTHER transactions because EVM transactions are serialized and atomic.
   - An attacker cannot send a DIFFERENT transaction that mutates RNG-consumer state while `advanceGame` is running under `phaseTransitionActive = true`, because the EVM does not interleave transactions.
   - The exemption from `rngLocked` is therefore safe: any mutation executed under `phaseTransitionActive = true` is by construction inside an `advanceGame` invocation, and `advanceGame`'s call chain is the ONLY chain that could have originated the mid-VRF-request window in the first place. The companion-gate semantics cited by Phase 238-03 (where `phaseTransitionActive` appears as a secondary cover on `rngLocked`-PRIMARY rows) are preserved: the PRIMARY `rngLocked` gate blocks player-reachable mutations; the `phaseTransitionActive` exemption admits only `advanceGame`-origin writes, which are by-construction non-adversarial.

**Conclusion:** Asymmetry B is re-justified from first principles at HEAD `7ab515fe`. The `phaseTransitionActive` exemption admits only `advanceGame`-origin writes and creates no player-reachable mutation path to RNG-consumer state. **AIRTIGHT**. ∎

### Discharge of Phase 238-03 FWD-03 gating `phase-transition-gate` audit assumption (D-29)

Phase 238-03 FWD-03 gating's Named-Gate taxonomy includes `phase-transition-gate` as a COMPANION-only gate (0 PRIMARY rows, appearing as secondary cover on PREFIX-DAILY / PREFIX-MIDDAY / PREFIX-GAMEOVER chains per 238-03 SUMMARY). The companion-gate correctness was stated as an audit assumption pending Phase 239 RNG-03(b) first-principles re-proof (Scope-Guard Deferral #1 in `audit/v30-FREEZE-PROOF.md`, the third portion paired with `rngLocked` discharged by Plan 239-01 and `lootbox-index-advance` discharged by this plan's § Asymmetry A). This § Asymmetry B proof **DISCHARGES** the `phase-transition-gate` portion of Scope-Guard Deferral #1. Evidence: the companion-gate-admits-only-advanceGame-origin-writes proof derives from Storage Primitives (1 set site, 1 clear site, 1 `_endPhase` caller) + call-chain-rooting analysis at HEAD `7ab515fe` — none of Phase 238's output files are relied upon as warrant. Per D-29, no re-edit of Phase 238 files. Discharge is evidenced by commit presence; Phase 242 REG-01/02 cross-checks at milestone consolidation.

## Prior-Artifact Cross-Cites

Each cite carries a `re-verified at HEAD 7ab515fe` note with a `we independently re-derived the same result` statement per D-14 format. Prior-milestone artifacts corroborate the result; they are **not relied upon** as the warrant — the warrants are the proof-by-exhaustion arguments in §§ Asymmetry A / B above.

1. **v29.0 Phase 235 Plan 05** — `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/235-05-TRNX-01.md` — rngLocked 4-path walk incl. Path 4 (read/write buffer invariants around phase transition). `re-verified at HEAD 7ab515fe` — we independently re-derived the same result for § Asymmetry B via fresh grep of `phaseTransitionActive` set/clear sites + `_endPhase` caller enumeration. The v29.0 artifact's Path 4 argument is structurally equivalent to the Asymmetry B Call-Chain Rooting Proof; neither cite load-bears the other. Contract tree identical to v29.0 `1646d5af` per PROJECT.md — `_endPhase` structure unchanged since v29.0 baseline.

2. **v29.0 Phase 232.1-03** — `.planning/milestones/v29.0-phases/232.1-rng-index-ticket-drain-ordering-enforcement/232.1-03-PFTB-AUDIT.md` — non-zero-entropy guarantees + semantic-path-gate archetypes around phase transition. `re-verified at HEAD 7ab515fe` — we independently re-derived the same result: the semantic-path-gate archetype around FF-drain + phase-transition is reflected in Asymmetry B's `_processFutureTicketBatch` delegatecall (B-S-08) which drains only FF tickets under the `phaseTransitionActive = true` window. Corroborates § Asymmetry B but does not serve as its warrant.

3. **KNOWN-ISSUES.md §"Lootbox RNG uses index advance isolation instead of rngLockedFlag"** — L33 entry: "the rngLockedFlag is set for daily VRF requests but NOT for mid-day lootbox RNG requests. Lootbox RNG isolation relies on a separate mechanism: the lootbox VRF request index advances past the current fulfillment index, preventing any overlap between daily and lootbox VRF words." **SUBJECT of § Asymmetry A — the design decision being re-justified from first principles per D-14. NOT warrant** — the proof holds independently of the KI entry's existence. `re-verified at HEAD 7ab515fe` — KI entry header text exact match; design decision structurally reflected in Write Sites ASYM-239-A-W-01/02 (monotonic index advance) + ASYM-239-A-W-04 (per-index atomic fulfillment write under VRF-coordinator-only gate).

4. **v25.0 Phase 215 RNG fresh-eyes sweep** — `.planning/milestones/v25.0-phases/215-rng-fresh-eyes/` — last milestone-level RNG-invariant baseline with SOUND verdict. `re-verified at HEAD 7ab515fe` — we independently re-derived the same result: the RNG fresh-eyes structural baseline (single SSTORE-site gating for each freeze window) holds in both § Asymmetry A (per-key mapping-slot single-writer) and § Asymmetry B (single set-site + single clear-site + single caller of `_endPhase`). Corroborating structural baseline.

5. **v3.7 Phase 63 — rawFulfillRandomWords revert-safety + Phase 68-72 VRF commitment window** — older v3.7/v3.8 VRF path test coverage including Foundry invariants + Halmos proofs. `re-verified at HEAD 7ab515fe` — we independently re-derived the same result: the `rawFulfillRandomWords` mid-day branch (ASYM-239-A-W-04 @ `:1706`) carries the same single-writer-via-coordinator invariant surfaced by v3.7 invariant tests; `rawFulfillRandomWords` body at `:1690-1711` structurally unchanged from v3.7 baseline. Corroborating; not relied upon.

6. **Phase 237 Consumer Index RNG-03 scope** — `audit/v30-CONSUMER-INVENTORY.md` §"Consumer Index" maps 19 PREFIX-MIDDAY rows (INV-237-107..125) to RNG-03 mid-day-lootbox scope per 237-03 Decision 4. Phase 238-03 SUMMARY's Named-Gate distribution adds INV-237-124 daily-subset EXC-04 (routed via `lootbox-index-advance`) for a 20-row total. `re-verified at HEAD 7ab515fe` — § Asymmetry A Read Sites enumeration cross-references these Row IDs. Scope anchor; not relied upon as proof warrant.

7. **Phase 238-03 Scope-Guard Deferral #1** — `audit/v30-FREEZE-PROOF.md` §"Scope-Guard Deferrals" entry #1: "Phase 239 RNG-01 / RNG-03 audit assumption (APPLICABLE)". **Discharge target per D-29** (see discharge sub-sections under §§ Asymmetry A/B). Not relied upon as warrant — this plan's commit presence discharges the entry.

## Finding Candidates

**None surfaced.** Both asymmetries re-justified AIRTIGHT from first principles at HEAD `7ab515fe`. The Asymmetry A 5-site Write-Set enumeration + 7-site Read-Set enumeration + 6-step freeze-guarantee composition + equivalence-to-rngLockedFlag argument all resolve to the conclusion without ambiguous paths. The Asymmetry B 13-site SSTORE enumeration under `phaseTransitionActive = true` + single-caller-of-_endPhase call-chain rooting + no-player-reachable-mutation-path exhaustion over the 62-row RNG-02 permissionless universe all resolve to the conclusion without ambiguous entries.

No routing to Phase 242 FIND-01 intake from this plan.

## Scope-Guard Deferrals

**None surfaced.** § Asymmetry A consumer set (20 rows: 19 PREFIX-MIDDAY INV-237-107..125 + 1 INV-237-124 daily-subset EXC-04 per Phase 238-03 Named-Gate distribution) maps entirely to existing `INV-237-NNN` Universe List rows in `audit/v30-CONSUMER-INVENTORY.md`. § Asymmetry B SSTORE set (13 enumerated sites in `contracts/modules/DegenerusGameAdvanceModule.sol`) — every mutated slot (`phaseTransitionActive`, `levelPrizePool`, `jackpotCounter`, `compressedJackpotFlag`, `ticketLevel`, `ticketCursor`, `ticketQueue[k]`, `dailyIdx`, `rngLockedFlag`, `rngWordCurrent`, `vrfRequestId`, `rngRequestTime`, `purchaseStartDay`, `jackpotPhaseFlag`, `gameOverPossible`) appears in the Phase 237 Consumer Inventory Write-Paths sets for at least one INV-237-NNN row.

Phase 237 inventory READ-only per D-28; no inventory delta proposed.

## Attestation

**HEAD anchor:** `7ab515fe` (contract tree identical to v29.0 `1646d5af`; all post-v29 commits are docs-only per PROJECT.md; verified by `git diff --stat 7ab515fe..HEAD -- contracts/` returning empty at plan execution time).

**Scope:** RNG-03 two asymmetries re-justified from first principles — § Asymmetry A (lootbox RNG index-advance isolation equivalent to flag-based isolation) + § Asymmetry B (`phaseTransitionActive` exemption admits only `advanceGame`-origin writes).

**D-14 proof-by-exhaustion:** every claim enumerates specific storage slots + SSTORE sites + call chains at HEAD `7ab515fe`. Asymmetry A Storage Primitives + 5 Write Sites + 7 Read Sites + 6-step Equivalence Proof; Asymmetry B Storage Primitives + 13 SSTORE sites + Call-Chain Rooting via single-caller-of-`_endPhase` + No-Player-Reachable-Mutation-Path via exhaustion over Plan 239-02's 62-row RNG-02 permissionless universe. Prior-milestone cites carry `we independently re-derived the same result` notes (D-14 format) — NOT load-bearing-reliance notes.

**D-14 KI-as-SUBJECT:** KNOWN-ISSUES.md entry `"Lootbox RNG uses index advance isolation instead of rngLockedFlag"` is SUBJECT of Asymmetry A (the design decision being re-justified from first principles), NOT warrant. Proof is independent of KI entry existence.

**D-15 forward-cite target:** Plan 239-02 RNG-02 `respects-equivalent-isolation` rows (zero rows in final distribution per 239-02 SUMMARY structural observation) and three corroborating forward-cite rows (PERM-239-046 `openLootBox` / PERM-239-047 `openBurnieLootBox` / PERM-239-061 `requestLootboxRng`) reference `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md § Asymmetry A` by file+section path. Per 239-02 SUMMARY §"D-15 Forward-Cite Reconciliation", these forward-cites are FORWARD-ONLY corroboration — the primary warrant for those three permissionless rows is the direct `rngLockedFlag` revert at `DegenerusGameAdvanceModule.sol:1031`, not the index-advance asymmetry. Consequently no 239-02 row classification depends on this plan's § Asymmetry A structure — reconciliation is cosmetic-only. Section heading format (`## § Asymmetry A — Lootbox RNG Index-Advance Isolation Equivalent to Flag-Based Isolation`) matches the file+section path used in 239-02 forward-cites per D-15; no erratum needed.

**D-22 finding-ID emission:** Zero `F-30-NN`. Finding Candidates section states `None surfaced.` — no routing to Phase 242 FIND-01 intake from this plan.

**D-25 tabular / no diagram fences:** All enumeration in markdown tables with grep-stable Row IDs (`ASYM-239-A-W-NN`, `ASYM-239-A-R-NN`, `ASYM-239-B-S-NN`). Zero diagram-renderer fences of any kind. Diagrams in prose only.

**D-26 HEAD anchor:** `7ab515fe` locked in frontmatter + Audit-baseline header line + echoed throughout body + in this Attestation section.

**D-27 READ-only:** zero `contracts/` or `test/` writes. `KNOWN-ISSUES.md` not touched. Phase 237 / Phase 238 / Plan 239-01 / Plan 239-02 outputs all READ-only (verified by `git status --porcelain audit/v30-CONSUMER-INVENTORY.md audit/v30-238-*.md audit/v30-FREEZE-PROOF.md audit/v30-RNGLOCK-STATE-MACHINE.md audit/v30-PERMISSIONLESS-SWEEP.md KNOWN-ISSUES.md` returning empty).

**D-28 Scope-Guard Deferral:** `None surfaced.` Every consumer / SSTORE site involved in both asymmetries maps to an existing `INV-237-NNN` Universe List row in `audit/v30-CONSUMER-INVENTORY.md`.

**D-29 Phase 238 dual-portion discharge:** Phase 238-03 FWD-03 gating Scope-Guard Deferral #1 discharged by this plan commit for (a) `lootbox-index-advance` portion via § Asymmetry A Equivalence Proof; (b) `phase-transition-gate` portion via § Asymmetry B Call-Chain Rooting Proof. Plan 239-01 separately discharged the `rngLocked` portion (commit `5764c8a4`, per 239-01 SUMMARY). Combined, all three portions of Phase 238-03 Scope-Guard Deferral #1 are now discharged. No re-edit of Phase 238 files per D-29 (verified above). Phase 242 REG-01/02 cross-checks at milestone consolidation.

**Row-set integrity:** Asymmetry A Write Sites row count (5) + Read Sites row count (7) cited in §§ Asymmetry Statement / Write Sites / Read Sites sub-sections. Asymmetry B Enumerated SSTORE Sites row count (13) cited in § B.3. All grep-reproducible at HEAD `7ab515fe`.
