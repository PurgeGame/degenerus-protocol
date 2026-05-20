---
phase: 310-implementation-single-batched-user-approved-contract-diff-im
plan: 02
subsystem: contracts
tags: [solidity, lootbox, ev-cap, bonus-only-cap, frozen-apply, vrf-freeze, v45]

# Dependency graph
requires:
  - phase: 310-implementation-single-batched-user-approved-contract-diff-im
    provides: "Plan 01 shared base — lootboxPurchasePacked, _unpackLootboxPurchase, _lootboxEvMultiplierFromScore, LOOTBOX_EV_NEUTRAL_BPS / LOOTBOX_EV_BENEFIT_CAP relocated to Storage"
  - phase: 309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe
    provides: "SPEC-02 bonus-only cap, §3.4 frozen-apply, §1.8 whole-word zero, §3.5/§0.F seed byte-identity"
provides:
  - "Bonus-only cap rule (`<=` NEUTRAL) in _applyEvMultiplierWithCap — IMPL-01 / SPEC-02"
  - "openLootBox frozen-apply: single packed-word SLOAD + unpack, NO cap SLOAD/SSTORE, whole-word zero-at-open — IMPL-04 / SPEC §3.4 / §1.8"
  - "Open-path roll seed preserved byte-identical (raw amount) — IMPL-05 open side / INV-04"
affects: [310-03, 311-tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Frozen-allocation apply: open path reads a pre-frozen adjustedPortion instead of drawing a live cap"
    - "Single packed-word SLOAD replacing two per-(index,player) SLOADs in the VRF-consume window"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameLootboxModule.sol

key-decisions:
  - "openLootBox unpacks the whole word once (scorePlus1, adj, baseLevelPlus1); baseLevelPlus1 feeds the existing grace logic verbatim (value semantics identical to the old lootboxBaseLevelPacked read — 0=unset, else minus-1)."
  - "Frozen-apply inlines the SPEC §3.4 formula directly in openLootBox rather than calling _applyEvMultiplierWithCap, so the open path performs zero lootboxEvBenefitUsedByLevel SLOAD/SSTORE (the V-081 fix). Both resolvers KEEP calling _applyEvMultiplierWithCap (SPEC-04 ACCEPT + Change-1)."
  - "The open-path roll seed line is left textually untouched — no +/- on it in the diff — guaranteeing INV-04 byte-identity. Only reward SCALING consumes adj."

requirements-completed: [IMPL-01, IMPL-04, IMPL-05]

# Metrics
duration: ~7min
completed: 2026-05-20
---

# Phase 310 / Plan 02: LootboxModule Bonus-Only Cap + openLootBox Frozen-Apply Summary

**Rewired `DegenerusGameLootboxModule.sol` to the v45.0 EV-cap design: the bonus-only `<=` cap rule (IMPL-01/SPEC-02), and an `openLootBox` that reads the frozen packed allocation, applies the SPEC §3.4 formula with NO cap SLOAD/SSTORE (V-081 fix), and zeroes the whole word in one SSTORE — while the open-path roll seed stays byte-identical to HEAD (IMPL-05/INV-04). Uncommitted, awaiting the Plan 03 batched USER-APPROVAL gate.**

## Performance
- **Duration:** ~7 min
- **Tasks:** 2 (both grep/awk verify gates PASS)
- **Files modified:** 1 (`DegenerusGameLootboxModule.sol`, uncommitted)

## Accomplishments

### Task 1 — Bonus-only cap (IMPL-01 / SPEC-02)
- In `_applyEvMultiplierWithCap`, replaced the `== NEUTRAL → return amount;` early return with
  `if (evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS) { return (amount * evMultiplierBps) / 10_000; }`.
- Penalty (`< NEUTRAL`) and neutral (`== NEUTRAL`) boxes now apply the multiplier on the FULL
  amount and draw ZERO from the cap; only `> NEUTRAL` falls through to the
  `lootboxEvBenefitUsedByLevel` cap-draw branch.
- The fn stays `private` in LootboxModule (not relocated). `LOOTBOX_EV_NEUTRAL_BPS` /
  `LOOTBOX_EV_BENEFIT_CAP` resolve to the inherited Storage constants (relocated in Plan 01).
- Both resolver call sites (`resolveLootboxDirect`, `resolveRedemptionLootbox`) are unchanged and
  still call `_applyEvMultiplierWithCap` (SPEC-04 ACCEPT with Change-1).

### Task 2 — openLootBox frozen-apply + whole-word zero + seed preservation (IMPL-04 / IMPL-05)
- Replaced the two prior per-(index,player) SLOADs (`lootboxBaseLevelPacked` + `lootboxEvScorePacked`)
  with a SINGLE `lootboxPurchasePacked[index][player]` SLOAD, unpacked via
  `_unpackLootboxPurchase(word)` → `(scorePlus1, adj, baseLevelPlus1)`.
- Fed `baseLevelPlus1` into the existing grace decision verbatim:
  `graceLevel = baseLevelPlus1 == 0 ? currentLevel : baseLevelPlus1 - 1` — identical value
  semantics to the old `baseLevelPacked` read (it was the same encoded `uint24(level+1)/(level+2)`).
- Multiplier source preserved: `_lootboxEvMultiplierFromScore(uint256(scorePlus1 - 1))` (inherited
  Storage fn), keeping the `score+1 - 1` decode and NOT re-ordering relative to the seed build.
- Replaced the `_applyEvMultiplierWithCap(...)` call with the SPEC §3.4 frozen formula, NO cap
  SLOAD/SSTORE:
  `scaledAmount = evMultiplierBps <= LOOTBOX_EV_NEUTRAL_BPS ? (amount * evMultiplierBps) / 10_000 : (uint256(adj) * evMultiplierBps) / 10_000 + (amount - uint256(adj));`
- Merged the two separate clears into a single whole-word zero
  `lootboxPurchasePacked[index][player] = 0;` (SPEC §1.8 — clears score+1, adjustedPortion,
  baseLevel+1 in one SSTORE).

## openLootBox allocation flow (as implemented)
1. SLOAD `lootboxEth` → `amount` (raw); revert `E()` if zero.
2. SLOAD `lootboxRngWordByIndex[index]` → `rngWord` (unlock gate, reverts `RngNotReady`).
3. Compute `currentDay`, `day` (`lootboxDay`, frozen seed input — untouched), `presale`,
   `baseAmount`, `currentLevel`, `withinGracePeriod`.
4. **Single frozen SLOAD:** `purchaseWord = lootboxPurchasePacked[index][player]`;
   `(scorePlus1, adj, baseLevelPlus1) = _unpackLootboxPurchase(purchaseWord)`.
5. `graceLevel = baseLevelPlus1 == 0 ? currentLevel : baseLevelPlus1 - 1`;
   `baseLevel = withinGracePeriod ? graceLevel : purchaseLevel`.
6. **Seed (UNCHANGED):** `seed = keccak256(abi.encode(rngWord, player, day, amount))` → `targetLevel = _rollTargetLevel(baseLevel, seed)`; floor at `currentLevel`.
7. `evMultiplierBps = _lootboxEvMultiplierFromScore(uint256(scorePlus1 - 1))`.
8. **Frozen apply (NO cap SLOAD/SSTORE):**
   `scaledAmount = mult <= NEUTRAL ? (amount * mult)/10_000 : (adj * mult)/10_000 + (amount - adj)`.
9. Clears: `lootboxEth = 0`, `lootboxEthBase = 0`, **`lootboxPurchasePacked = 0` (whole word, one SSTORE)**, conditional `lootboxDistressEth = 0`.
10. `_resolveLootboxCommon(..., scaledAmount, targetLevel, ..., seed, ..., amount)`.

The open path performs ZERO `lootboxEvBenefitUsedByLevel` SLOAD/SSTORE (awk gate + an explicit
`grep`-for-accumulator-in-open both PASS). The cap is drawn at deposit time (Plan 03).

## Seed byte-identity confirmation (INV-04 / IMPL-05)
- **The open-path roll seed `keccak256(abi.encode(rngWord, player, day, amount))` is BYTE-IDENTICAL
  to HEAD.** It binds the RAW `amount` (read from `lootboxEth`), never `adj`. `git diff` shows NO
  `+`/`-` on any `rngWord`-seed line in the file — all four seeds are textually untouched. The line
  number shifted only because Plan 01 deleted ~36 lines above it (HEAD line 545 → working-tree line
  509); the text is unchanged.
- Raw-`amount` seed occurrences = **3** at both HEAD and working tree (openLootBox,
  resolveLootboxDirect, resolveRedemptionLootbox).
- The BURNIE open-path seed `keccak256(abi.encode(rngWord, player, day, amountEth))` is present and
  untouched (uses `amountEth`, not edited).

## Verify gates (all PASS)
- **Task 1:** `<= LOOTBOX_EV_NEUTRAL_BPS` present; `return (amount * evMultiplierBps) / 10_000;`
  present; old `== LOOTBOX_EV_NEUTRAL_BPS` absent. PASS.
- **Task 2:** `_unpackLootboxPurchase(` present; whole-word zero
  `lootboxPurchasePacked[index][player] = 0;` present; `lootboxBaseLevelPacked` /
  `lootboxEvScorePacked` absent from the module; ≥3 raw-`amount` seeds; BURNIE `amountEth` seed
  present; awk gate confirms NO `_applyEvMultiplierWithCap` call inside `openLootBox`. PASS.
- `_applyEvMultiplierWithCap` reference count = 3 (def + 2 resolver call sites); open path no
  longer calls it.

## Deviations from Plan
None — plan executed exactly as written. (The constant declarations + `_lootboxEvMultiplierFromScore`
fn already removed from this module are Plan 01's relocations, not a Plan 02 change; they appear in
the diff because Plan 01 is uncommitted in the shared working tree.)

## Known Stubs
None.

## Threat Flags
None — no new network/auth/file/schema surface introduced. The change strictly REDUCES the
open-path word-adjacent shared-state surface (two SLOADs → one; cap SLOAD/SSTORE removed at open),
consistent with threat-register dispositions T-310-02/03/04/06 (all `mitigate`, satisfied).

## forge build status (informational — NOT gated in this plan)
- `forge build` fails ONLY on the two expected not-yet-wired Mint references the plan defers to
  Plan 03: `lootboxBaseLevelPacked` (Mint:992) and `lootboxEvScorePacked` (Mint:1155) — Errors
  (7576) Undeclared identifier.
- The JackpotModule:457/458/534/535 diagnostics are pre-existing **Warnings (2519) shadowed
  declaration** in an OUT-OF-SCOPE file — not caused by this plan, correctly left untouched
  (scope boundary). LootboxModule itself raises no internal errors.

## Commit Posture
**NO contract commit in this plan** (per the phase CONTRACT-COMMIT POLICY + the active
CONTRACT-COMMIT-GUARD hook that blocks `git commit` while any `contracts/*.sol` is dirty).
`DegenerusGameLootboxModule.sol` is left **UNCOMMITTED** in the working tree. The single batched
4-file contract commit happens at the END of Plan 03 after the explicit USER-APPROVAL gate.
No `git add`/`git commit`/push was run. STATE.md and ROADMAP.md were NOT modified.

## Next Phase Readiness
- The open path (consumer side) is fully wired to the packed word and the frozen-apply formula.
- Plan 03 must: (a) wire the Mint/Whale deposit-time tally to write the packed word
  (`_packLootboxPurchase`) + draw the cap at deposit, resolving the two remaining Mint Errors
  (7576); (b) run the `forge build` gate; (c) present the single batched 4-file diff for USER
  approval and perform the commit.

---
*Phase: 310-implementation-single-batched-user-approved-contract-diff-im*
*Completed: 2026-05-20*
