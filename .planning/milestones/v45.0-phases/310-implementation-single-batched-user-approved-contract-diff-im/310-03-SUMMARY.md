---
phase: 310-implementation-single-batched-user-approved-contract-diff-im
plan: 03
subsystem: contracts
tags: [solidity, lootbox, ev-cap, deposit-tally, v45, mint, whale, vrf-freeze]

# Dependency graph
requires:
  - phase: 310-implementation-single-batched-user-approved-contract-diff-im
    provides: "Plan 01 shared base (lootboxPurchasePacked, _packLootboxPurchase / _unpackLootboxPurchase, _lootboxEvMultiplierFromScore, LOOTBOX_EV_NEUTRAL_BPS / LOOTBOX_EV_BENEFIT_CAP, lootboxEvBenefitUsedByLevel) + Plan 02 openLootBox frozen-apply / bonus-only cap"
  - phase: 309-spec-locked-layout-bonus-only-cap-shared-cap-disposition-spe
    provides: "SPEC-03 §3.1-§3.3 deposit tally, §3.5 seed/lootboxEth byte-identity, §0.I DIV-1/DIV-2"
provides:
  - "Purchase-time EV-cap tally at Mint deposit sites (first-deposit gated + subsequent RMW) — IMPL-03"
  - "Purchase-time EV-cap tally at Whale deposit sites (first-deposit inline + subsequent RMW) — IMPL-03"
  - "Raw deposit amount preserved into lootboxEth at both modules (deposit side) — IMPL-05"
affects: [311-tests]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Allocation-time cap draw: each deposit draws add = min(deposit, CAP - used), advances the shared per-(player, level) accumulator, and RMWs adjustedPortion into the packed word"
    - "Frozen multiplier on subsequent deposits: unpack scorePlus1 from the word, derive mult; never recompute from current activity"

key-files:
  created: []
  modified:
    - contracts/modules/DegenerusGameMintModule.sol
    - contracts/modules/DegenerusGameWhaleModule.sol

key-decisions:
  - "BURNIE path (Mint _purchaseBurnieLootboxFor + Lootbox openBurnieLootBox) does NOT participate in the EV-cap snapshot at HEAD — preserved verbatim, no invented EV snapshot (feedback_verify_call_graph_against_source). See finding below."
  - "Cap key inlined as literal subscript (Mint cachedLevel + 1, Whale level + 1) rather than aliased to a local, so the cap-key level is self-evident at every accumulator site in the diff and to satisfy the plan grep gate."
  - "Whale subsequent tally gated on existingAmount != 0 (the snapshot taken before the first-deposit branch writes), mutually exclusive with the first-deposit branch — no double-draw."

requirements-completed: [IMPL-03, IMPL-05]

# Metrics
duration: ~12min
completed: 2026-05-20
---

# Phase 310 Plan 03: Mint + Whale Deposit-Time EV-Cap Tally Summary

**Wired the v45.0 purchase-time EV-cap tally into both purchased-box deposit modules — `DegenerusGameMintModule.sol` (first-deposit gated + subsequent RMW) and `DegenerusGameWhaleModule.sol` (first-deposit inline + subsequent RMW) — each draws `add = min(deposit, CAP - used)` for bonus boxes against the shared `lootboxEvBenefitUsedByLevel[player][level + 1]` accumulator and accumulates `adjustedPortion` into `lootboxPurchasePacked`, with the multiplier frozen from the first-deposit score snapshot; `lootboxEth` writes left byte-identical (IMPL-05). `forge build --force` PASSES over the full 4-file patched tree. UNCOMMITTED — the single batched 4-file USER-APPROVAL gate + commit are PENDING (orchestrator-owned).**

## Performance
- **Duration:** ~12 min
- **Tasks executed:** 3 (Tasks 1-3); Tasks 4-5 are orchestrator-owned (NOT executed)
- **Files modified:** 2 (uncommitted)

## Accomplishments

### Task 1 — Mint deposit tally (IMPL-03; DIV-1 `+1` / DIV-2 gated preserved)
- **First-deposit branch** (`if (existingAmount == 0)`, ~989): removed the standalone
  `lootboxBaseLevelPacked[lbIndex][buyer] = uint24(cachedLevel + 1);` write — `baseLevel + 1`
  now lands in the packed word at the score-write site (DIV-1 `+1` preserved in the packed field).
- **Score/tally site** (the gated `if (lbFirstDeposit)` block, ~1154): rewired to
  `lootboxPurchasePacked[lbIndex][buyer] = _packLootboxPurchase(uint16(cachedScore + 1), adj, uint24(cachedLevel + 1))`.
  Computes `mult = _lootboxEvMultiplierFromScore(cachedScore)`; if `mult > LOOTBOX_EV_NEUTRAL_BPS`,
  draws `add = min(lootBoxAmount, CAP - used)` against `lootboxEvBenefitUsedByLevel[buyer][cachedLevel + 1]`
  and advances it, `adj = uint64(add)`; else `adj = 0` (no cap draw). DIV-2 gating preserved
  (still inside `if (lbFirstDeposit)`); the score read order at ~1106 is unchanged.
- **Subsequent branch** (new `else if (lootBoxAmount != 0)`): the multiplier is FROZEN — unpacks
  `(scorePlus1, adj, baseLevelPlus1) = _unpackLootboxPurchase(lootboxPurchasePacked[lbIndex][buyer])`,
  derives `mult = _lootboxEvMultiplierFromScore(scorePlus1 - 1)`; if `mult > NEUTRAL`, draws
  `add = min(lootBoxAmount, CAP - used)`, advances the accumulator, and re-packs
  `_packLootboxPurchase(scorePlus1, adj + uint64(add), baseLevelPlus1)` (score+1/baseLevel+1
  preserved). The non-first branch lives where the deposit is finalized (inside the second
  `if (lootBoxAmount != 0)` block), so it runs for every non-first ETH deposit.
- **Cap key:** `cachedLevel + 1` at every accumulator subscript (the lootbox open level == the
  resolver `currentLevel = level + 1`). NOT a `+ 2` sentinel.
- `lootboxEth[lbIndex][buyer] = (uint256(cachedLevel + 1) << 232) | newAmount;` (~1013)
  byte-unchanged; raw `lootBoxAmount` flows into it and the seed unchanged (IMPL-05).

### Task 2 — Whale deposit tally (IMPL-03; DIV-1 `+2` / DIV-2 inline preserved)
- **First-deposit branch** (`if (existingAmount == 0)`, ~853): removed the two separate
  `lootboxBaseLevelPacked[index][buyer] = uint24(level + 2);` and
  `lootboxEvScorePacked[index][buyer] = uint16(playerActivityScore(buyer) + 1);` writes.
  Snapshots `score = IDegenerusGame(address(this)).playerActivityScore(buyer)` once inline
  (DIV-2 inline preserved; read order unchanged); `mult = _lootboxEvMultiplierFromScore(score)`;
  if `mult > NEUTRAL`, draws `add = min(lootboxAmount, CAP - used)` against
  `lootboxEvBenefitUsedByLevel[buyer][level + 1]` and advances it; else `adj = 0`. Writes
  `lootboxPurchasePacked[index][buyer] = _packLootboxPurchase(uint16(score + 1), adj, uint24(level + 2))`
  — the `level + 2` DIV-1 sentinel is preserved EXACTLY in the PACKED FIELD (the helper does not
  normalize it).
- **Subsequent branch** (new `if (existingAmount != 0 && lootboxAmount != 0)` placed after
  `newAmount`/`lootboxEth` finalize, ~895): FROZEN multiplier — unpacks the word, derives
  `mult` from `scorePlus1 - 1`; if `mult > NEUTRAL`, draws `add = min(lootboxAmount, CAP - used)`,
  advances `lootboxEvBenefitUsedByLevel[buyer][level + 1]`, and re-packs preserving
  `scorePlus1`/`baseLevelPlus1`. Mutually exclusive with the first-deposit branch (the gate uses
  the `existingAmount` snapshot taken at ~850 before any first-deposit write) — no double-draw.
- **Cap key:** `level + 1` at every accumulator subscript (the inherited global game-level var
  read directly; == the resolver `currentLevel = level + 1`). EXPLICITLY NOT the `level + 2`
  packed baseLevel sentinel (T-310-05 mitigated).
- `lootboxEth[index][buyer] = (uint256(purchaseLevel) << 232) | newAmount;` (~876) byte-unchanged;
  raw `lootboxAmount` flows in unchanged (IMPL-05).

### Task 3 — forge build gate (full 4-file patched tree)
- `forge build --force` invoked EXACTLY ONCE; gated on the process exit code (0). Result:
  **"Compiler run successful with warnings"**, 155 files, NO compile errors. Cached re-check
  `forge build` exits 0. Build log preserved at `/tmp/build310.log`.
- No test file created or run (Phase 311 owns tests).

## Cap-key level per module (LOCKED, verified in the applied diff)
| Module | Cap-key subscript | == resolver currentLevel | Packed baseLevel field (DIV-1) |
|--------|-------------------|--------------------------|-------------------------------|
| Mint   | `cachedLevel + 1` | yes (`level + 1`)        | `uint24(cachedLevel + 1)` (`+1`) |
| Whale  | `level + 1`       | yes (`level + 1`)        | `uint24(level + 2)` (`+2` sentinel) |

The Whale cap key (`level + 1`) is distinct from the Whale packed baseLevel sentinel (`level + 2`).
Using `level + 2` as the cap key would draw from a different level's cap (threat T-310-05) — avoided.

## BURNIE-path EV-participation finding (feedback_verify_call_graph_against_source)
**The BURNIE lootbox path does NOT participate in the EV-cap snapshot at HEAD — neither the
deposit side nor the open side — so it carries only its existing writes; no EV snapshot was
invented.** Verified by reading both ends of the path against live source:

- **Deposit side** — `DegenerusGameMintModule._purchaseBurnieLootboxFor` (~1377-1412): writes
  `lootboxBurnie[index][buyer]` (a separate slot from the ETH packed word) and `lootboxDay`
  (§0.H writer W2). It performs ZERO reads/writes of `lootboxPurchasePacked` /
  `lootboxEvBenefitUsedByLevel`, ZERO calls to `_lootboxEvMultiplierFromScore` /
  `playerActivityScore`. No multiplier, no cap, no packed snapshot.
- **Open side** — `DegenerusGameLootboxModule.openBurnieLootBox` (~561-609): reads `lootboxBurnie`,
  converts to `amountEth` at the 80% rate, builds the seed
  `keccak256(abi.encode(rngWord, player, day, amountEth))`, and calls `_resolveLootboxCommon`
  directly with `amountEth`. It does NOT read `lootboxPurchasePacked`, does NOT call
  `_lootboxEvMultiplierFromScore` or `_applyEvMultiplierWithCap`, and does NOT touch the cap
  accumulator. No EV scaling exists on the BURNIE box at HEAD.

Therefore the SPEC §3.1 first-vs-subsequent tally rule is N/A to the BURNIE path: there is no
multiplier to freeze and no cap to draw. Preserving HEAD semantics (per the plan's explicit
instruction and `feedback_verify_call_graph_against_source`) means leaving `_purchaseBurnieLootboxFor`
carrying only its existing `lootboxBurnie` + `lootboxDay` writes — exactly as done (the BURNIE path
was not edited). The Mint grep gate only requires no stale
`lootboxBaseLevelPacked`/`lootboxEvScorePacked` reference survives in Mint — confirmed (repo-wide
grep returns NONE across `contracts/`).

## Verify gates (all PASS)
- **Task 1 (Mint):** `lootboxPurchasePacked[lbIndex][buyer]` present; `_packLootboxPurchase(` present;
  `_lootboxEvMultiplierFromScore(` present; `lootboxEvBenefitUsedByLevel[buyer][cachedLevel + 1]`
  present; `lootboxBaseLevelPacked`/`lootboxEvScorePacked` absent; `lootboxEth[lbIndex][buyer] =`
  present. PASS.
- **Task 2 (Whale):** `lootboxPurchasePacked[index][buyer]` present; `_packLootboxPurchase(` present;
  `_lootboxEvMultiplierFromScore(` present; `lootboxEvBenefitUsedByLevel[buyer][level + 1]` present;
  `uint24(level + 2)` present; `lootboxBaseLevelPacked`/`lootboxEvScorePacked` absent;
  `lootboxEth[index][buyer] =` present. PASS.
- **Task 3 (build):** `forge build --force` exits 0; no compile errors. PASS.
- **Repo-wide:** `grep -rn "lootboxBaseLevelPacked\|lootboxEvScorePacked\|lootboxEvPacked" contracts/`
  returns NONE — clean.

## Threat mitigations satisfied (this plan's surface)
- **T-310-05** (wrong cap level key): cap key inlined as `cachedLevel + 1` (Mint) / `level + 1`
  (Whale) at every accumulator site, matching resolver `currentLevel`; Whale `level + 2` used only
  as the packed baseLevel sentinel, never as a cap key.
- **T-310-01** (packed-field overflow/aliasing): `adj` accumulates `min(deposit, CAP - used)`,
  bounded by `CAP = 10 ETH < 2^64`; `uint64(add)` and `adj + uint64(add)` never overflow uint64.
  `_packLootboxPurchase` masks each field (Plan 01).
- **T-310-02** (deposit-order griefing / cap drift): each deposit draws against the SAME shared
  accumulator monotonically (`used + add`), bounded by CAP; multiplier frozen from the first-deposit
  snapshot, so subsequent deposits cannot re-roll the classification.
- **T-310-03** (seed perturbation): both `lootboxEth[...] =` writes byte-unchanged; raw deposit
  amount flows into `lootboxEth`/seed unchanged; only `adjustedPortion` (reward scaling) is derived.

## Deviations from Plan
None of consequence. Two mechanical notes:
1. The Mint cap-key was initially aliased to a local `lbCapLevel`; the plan's grep gate requires the
   literal `lootboxEvBenefitUsedByLevel[buyer][cachedLevel + 1]` subscript, so it was inlined
   (semantically identical; also makes the cap-key level self-evident at each site for the diff
   review). Not a behavior change.
2. The BURNIE-path finding (above) is documented per the plan's explicit instruction to confirm and
   record EV participation — not a deviation, a required verification outcome.

## Known Stubs
None.

## Threat Flags
None — no new network/auth/file/schema surface. The change moves the cap draw from open → deposit
time (pre-VRF-word) and writes only the pre-existing packed `(index, player)` slot + the pre-existing
shared `(player, level)` accumulator. No new player-discretionary writer in the `[rng request → unlock]`
window (INV-06 holds; the open path's cap SLOAD/SSTORE was already removed in Plan 02).

## Commit Posture — PENDING (orchestrator-owned)
**NO contract commit in this plan run.** Per the phase CONTRACT-COMMIT POLICY + the active
PreToolUse guard hook (blocks commits while any `contracts/*.sol` is dirty), all 4 contract files
(`DegenerusGameStorage.sol`, `DegenerusGameLootboxModule.sol`, `DegenerusGameMintModule.sol`,
`DegenerusGameWhaleModule.sol`) are left **UNCOMMITTED** in the working tree. This executor STOPPED
after the Task 3 build gate. The orchestrator owns:
- **Task 4** — the blocking-human USER-APPROVAL gate (present the single batched 4-file diff,
  walk the (a)-(g) evidence points, await explicit approval).
- **Task 5** — the single batched 4-file commit (ONLY after explicit user approval).
No `git add`/`git commit`/push was run. STATE.md and ROADMAP.md were NOT modified.

## Next Steps (orchestrator)
- Present `git --no-pager diff -- contracts/storage/DegenerusGameStorage.sol contracts/modules/DegenerusGameLootboxModule.sol contracts/modules/DegenerusGameMintModule.sol contracts/modules/DegenerusGameWhaleModule.sol` for USER review.
- On approval: stage exactly the 4 files by name and create ONE commit (no push, no amend).
- Phase 311 (TST) proves INV-01..06 against the post-IMPL tree.

## Self-Check: PASSED
- `310-03-SUMMARY.md` present on disk.
- All 4 contract files MODIFIED + UNCOMMITTED in the working tree (Mint + Whale by this plan;
  Storage + Lootbox from Plans 01/02).
- Index empty for `contracts/*.sol` — nothing staged by the executor.
- HEAD unchanged — no commit created (Task 4/5 deferred to orchestrator).
- STATE.md / ROADMAP.md NOT modified by this run.

---
*Phase: 310-implementation-single-batched-user-approved-contract-diff-im*
*Completed: 2026-05-20*
