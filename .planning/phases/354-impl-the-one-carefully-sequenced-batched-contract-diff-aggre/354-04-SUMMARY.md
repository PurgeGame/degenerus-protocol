---
phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre
plan: 04
subsystem: contracts (afking affiliate settle — flat-7% deterministic-split PULL)
tags: [solidity, foundry, affiliate, aff-pull, claim, withdraw, pendingClaim, agg, deterministic-split, cei]

# Dependency graph
requires:
  - phase: 354-01
    provides: "the re-packed single-slot Sub accumulator carrying affiliateBase (uint32 whole-BURNIE, 100M clamp) + the locked pendingClaim cross-contract ownership boundary (declared in DegenerusAffiliate.sol, NOT game storage)"
  - phase: 354-03
    provides: "the AFFILIATE-gated atomic read-and-zero PRODUCER drainAffiliateBase(address sub) returns (uint256) on the Game side (GameAfkingModule via delegatecall) — the read-and-zero happens AT THE STORAGE OWNER (AFF-PULL guardrail 1)"
provides:
  - "DegenerusAffiliate.claim(address[] calldata subs) — the permissionless SAME-AFFILIATE-batch deterministic-split PULL CONSUMER: per-iteration drainAffiliateBase(sub) atomic read-and-zero at the owner → ONE running sumB → fixed 75/20/5 (floor + remainder-to-A, never over-mints) → pendingClaim[A/U1/U2]; noReferrer subs 50/50 VAULT/DGNRS deterministic (remainder→VAULT, NO entropy); claim-time leaderboard write to A; NO roll, NO seed, NO currentDayIndex, NO keccak256"
  - "DegenerusAffiliate.withdraw() — the ONLY cross-contract leg: CEI (zero pendingClaim[msg.sender] BEFORE the single coinflip.creditFlip; whole-BURNIE → base units ×1e18)"
  - "claim/withdraw declared on IDegenerusAffiliate.sol"
affects: [354-05 (parallel — no files_modified overlap), 354-06 (the single USER batched contract commit), 356 TST (SEC-01 churn/idempotent/Σ≤sumB + SEC-02 CEI), 357 TERMINAL]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Deterministic-split PULL settle: accrued running balance drained atomically at the storage owner, split by a FIXED 75/20/5 proportion (floor + remainder-to-A), credited to an off-slot pendingClaim ledger; the only mint is a CEI withdraw — NO roll, NO seed, NO settle-timing surface"
    - "Atomic read-and-zero AT THE OWNER per loop iteration (drainAffiliateBase consumed in the loop, never pre-loaded to a memory array) — the duplicate-sub double-credit guard"
    - "Whole-BURNIE internal ledger (pendingClaim) scaled ×1e18 at the cross-contract boundary (both the leaderboard write and the withdraw mint), keeping the base-unit leaderboard denominator consistent with the live payAffiliate path"

key-files:
  created:
    - .planning/phases/354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre/354-04-SUMMARY.md
  modified:
    - contracts/DegenerusAffiliate.sol
    - contracts/interfaces/IDegenerusAffiliate.sol

key-decisions:
  - "Leaderboard unit-bridge (Rule 2 correctness): sumB is whole-BURNIE but the SHARED leaderboard maps (affiliateCoinEarned[lvl]/_totalAffiliateScore[lvl]) are base-unit (18-decimal) denominated — the live payAffiliate path writes base-unit scaledAmount into the same maps. Writing whole-BURNIE sumB directly would corrupt the score-proportional DGNRS-claim ratio across the two paths, so the claim-time leaderboard scales sumB ×1e18. The SPEC's literal `earned[A] += sumB` is honored in MAGNITUDE-analog form (the `:510` analog wording), with the unit bridge required for cross-path consistency."
  - "withdraw mints owed ×1e18 — pendingClaim is whole-BURNIE (the unit of drainAffiliateBase / the accrued affiliateBase per 354-01's NatSpec), creditFlip expects base units (18 decimals)."
  - "noReferrer detection at subs[0]: A == ContractAddresses.VAULT ⇒ the whole batch routes 50/50 VAULT/DGNRS. The SAME-AFFILIATE require (every sub resolves to A) means a noReferrer batch is homogeneous by construction — no separate grouping pass needed."
  - "claim-time level = afkingDrain.level() + 1 (the live `level + 1` affiliate-routing convention, AFF-02(b) / DegenerusGameAdvanceModule :695-696); the level() accessor rides the same IGameAfkingDrain handle on ContractAddresses.GAME."

patterns-established:
  - "AFF-PULL: the affiliate distribution is a no-roll no-seed deterministic split + an off-slot pendingClaim ledger + a single CEI withdraw — the entire settle-timing/free-option manipulability surface (XMODEL C1/C2) is removed by construction"

requirements-completed: [AGG-01, AGG-04, AGG-05]

# Metrics
duration: 6min
completed: 2026-06-01
---

# Phase 354 Plan 04: Affiliate Flat-7% Deterministic-Split PULL — claim + withdraw + pendingClaim Summary

**Built the afking affiliate SETTLE side in `DegenerusAffiliate.sol`: a permissionless SAME-AFFILIATE-batch `claim(address[] subs)` that drains each sub's accrued `affiliateBase` ATOMICALLY at the storage owner (per-iteration `drainAffiliateBase(sub)` — the 354-03 producer, never pre-loaded to a memory array), accumulates ONE running `sumB`, and splits it by the FIXED deterministic 75/20/5 (floor + remainder-to-A so `Σshares ≤ sumB`, never over-mints — buyer never wins via the rare U1/U2==sub cycle skip) into the off-slot `pendingClaim` ledger, with noReferrer subs split deterministically 50/50 VAULT/DGNRS (remainder→VAULT, NO entropy) and a claim-time leaderboard write to the direct affiliate A; plus a CEI `withdraw()` that zeroes `pendingClaim[msg.sender]` BEFORE the single `coinflip.creditFlip` (the ONLY cross-contract leg). There is NO roll, NO seed, NO `currentDayIndex`, and NO `keccak256` in the claim path — the entire settle-timing / free-option surface is removed; this plan does NOT edit `GameAfkingModule.sol`; `forge build` exits 0.**

## Performance
- **Duration:** ~6 min
- **Started:** 2026-06-01T18:23Z
- **Completed:** 2026-06-01T18:29Z
- **Tasks:** 2
- **Files modified:** 2 (contracts — left UNCOMMITTED for the 354-06 USER batched-commit gate)

## Accomplishments
- **Task 1 (AGG-01/04/05, AFF-01, AFF-PULL guardrails 1+4, AFF-02(b)):** added `claim(address[] calldata subs)` to `DegenerusAffiliate.sol`. It resolves the direct affiliate `A` ONCE from `subs[0]` via `_referrerAddress` (noReferrer ⟺ `A == VAULT`), reads the upline chain `U1 = _referrerAddress(A)` / `U2 = _referrerAddress(U1)` ONCE, and `require`s every other sub resolves to the SAME `A` (mixed arrays revert via `Insufficient()`). It walks `subs[]` accumulating ONE running `sumB`: per sub `B = afkingDrain.drainAffiliateBase(sub)` (the atomic read-and-zero AT THE OWNER — the 354-03 producer, called INSIDE the loop, NEVER pre-loaded to a `uint256[] memory` array, so a duplicate sub drains 0 the second time), skip on `B == 0`, accumulate `skipU1 += B` / `skipU2 += B` only for the rare `U1 == sub` / `U2 == sub` cycle. After the walk: `u1 = (sumB − skipU1) * 20 / 100`, `u2 = (sumB − skipU2) * 5 / 100`, `aShare = sumB − u1 − u2` (A never skips; floor + remainder-to-A → `Σ ≤ sumB`, never over-mints) → `pendingClaim[A/U1/U2] +=`. noReferrer batches split deterministically `pendingClaim[DGNRS] += sumB/2; pendingClaim[VAULT] += sumB − sumB/2` (remainder→VAULT, NO entropy). The leaderboard credits ONCE per batch at the CLAIM-time level (`afkingDrain.level() + 1`) to `A` — `earned[A] += scaled; _totalAffiliateScore[lvl] += scaled; _updateTopAffiliate(A, newTotal, lvl)` where `scaled = sumB * 1 ether` (the whole-BURNIE → base-unit bridge, see Deviations). Declared `claim` on `IDegenerusAffiliate.sol`.
- **Task 2 (AFF-01 withdraw, SEC-02 CEI):** added `withdraw()` — reads `owed = pendingClaim[msg.sender]`; no-op if `owed == 0`; ZEROES `pendingClaim[msg.sender] = 0` FIRST (CEI — textually BEFORE the external call); then `coinflip.creditFlip(msg.sender, owed * 1 ether)` (the only cross-contract leg, batched per recipient, whole-BURNIE → base units). Declared `withdraw` on `IDegenerusAffiliate.sol`.
- `forge build` exits 0 across the working tree (only pre-existing out-of-scope `unsafe-typecast` lint warnings in untouched files).

## Task Commits

Per the **Phase 354 contract-commit override**: the contract edits (`DegenerusAffiliate.sol`, `IDegenerusAffiliate.sol`) are intentionally left UNCOMMITTED in the working tree — they accumulate with the 354-01 (`DegenerusGameStorage.sol`) + 354-02 (`DegenerusQuests.sol`, `IDegenerusQuests.sol`) + 354-03 (`GameAfkingModule.sol`, `IDegenerusGameModules.sol`) producers for the SINGLE USER-approved batched `contracts/*.sol` commit at the 354-06 hand-review gate. There are intentionally ZERO production-code commits in this plan.

1. **Task 1: claim(address[] subs) deterministic-split PULL + pendingClaim** — working-tree edit, no commit (contract gate)
2. **Task 2: CEI withdraw()** — working-tree edit, no commit (contract gate)

**Plan metadata (docs):** see the `docs(354-04)` commit (this SUMMARY + STATE.md + ROADMAP.md + REQUIREMENTS.md).

## Files Created/Modified
- `contracts/DegenerusAffiliate.sol` — **(UNCOMMITTED, contract gate)** added the `claim(address[] calldata subs)` deterministic-split PULL + the CEI `withdraw()` (between `payAffiliate` and the VIEWS divider). The `IGameAfkingDrain` interface (`drainAffiliateBase` + `level`), the `afkingDrain` constant handle, and the `pendingClaim` mapping were already present in the working tree (added by prior partial 354-04 work) and were CONSUMED, not re-declared.
- `contracts/interfaces/IDegenerusAffiliate.sol` — **(UNCOMMITTED, contract gate)** added the `claim(address[] calldata subs)` and `withdraw()` declarations on `IDegenerusAffiliate`.
- `.planning/phases/354-.../354-04-SUMMARY.md` — this summary (committed).

## Decisions Made
See `key-decisions` in the frontmatter — the load-bearing one: the **leaderboard unit-bridge** (Rule 2). `sumB` is whole-BURNIE; the shared leaderboard maps are base-unit denominated and ALSO written by the live `payAffiliate` path with base-unit `scaledAmount`. Writing whole-BURNIE `sumB` directly into the same maps would corrupt the score-proportional DGNRS-claim ratio across the two paths, so the claim-time write scales `sumB * 1 ether`. The SPEC's literal `earned[A] += sumB` ("`:510` analog") is honored in magnitude-analog form with the cross-path unit consistency restored.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing critical correctness] Scaled the claim-time leaderboard write whole-BURNIE → base units (×1e18)**
- **Found during:** Task 1 (authoring the AFF-02(b) leaderboard write)
- **Issue:** The SPEC writes `earned[A] += sumB` / `_totalAffiliateScore[lvl] += sumB` as a "`:510`/`:511` analog". But `sumB` is **whole-BURNIE** (the unit of `drainAffiliateBase` / the accrued `affiliateBase`), whereas the SHARED leaderboard maps `affiliateCoinEarned[lvl]` / `_totalAffiliateScore[lvl]` are **base-unit (18-decimal)** denominated and are ALSO written by the live `payAffiliate` path (`:540-541`, base-unit `scaledAmount`). Mixing whole-BURNIE afking writes with base-unit live writes in the same map corrupts the `claimAffiliateDgnrs` score-proportional ratio (`reward = allocation × score / totalScore`) across the two paths.
- **Fix:** Scaled the claim-time leaderboard write to base units: `scaled = sumB * 1 ether` before `earned[A] += scaled` / `_totalAffiliateScore[lvl] += scaled` / `_updateTopAffiliate(A, newTotal, lvl)`. This keeps the afking and live writes unit-consistent in the shared maps (numerator and denominator both move in base units). The `pendingClaim` ledger + the split arithmetic stay in whole-BURNIE; only the cross-path leaderboard write (and the `withdraw` mint) bridge to base units.
- **Files modified:** `contracts/DegenerusAffiliate.sol` (UNCOMMITTED, accumulates for the 354-06 batch).
- **Verification:** `forge build` exits 0; the split/Σ≤sumB/buyer-never-wins/CEI invariants are unaffected (this is a leaderboard-denomination fix only, OFF the split + solvency paths).
- **Committed in:** NOT committed — left in the working tree per the Phase 354 contract-commit override.

---

**Total deviations:** 1 auto-fixed (Rule 2 correctness — cross-path unit consistency). **Impact on plan:** none on scope/behavior beyond restoring the leaderboard denominator consistency the SPEC's proportional-claim invariant (AFF-02(d), TST-356) depends on; semantically aligned with the LOCKED `:510`/`:511`-analog intent.

## Issues Encountered
- **Working tree carried prior partial 354-04 work + the 354-01/02/03 producers UNCOMMITTED.** `DegenerusAffiliate.sol` already had the `IGameAfkingDrain` interface, the `afkingDrain` constant, and the `pendingClaim` mapping (a prior partial 354-04 pass) but NOT the `claim`/`withdraw` functions; `IDegenerusAffiliate.sol` had no claim/withdraw decls yet. I built ON TOP of the on-disk state, consumed the existing primitives, authored only the two functions + the two interface decls, and did NOT touch/revert/stash any accumulated edit (354-01 storage, 354-03 GameAfkingModule, etc.).
- **Pre-existing out-of-scope lint warnings** — `forge build` emits `unsafe-typecast` warnings in untouched files (e.g. `DegenerusGameWhaleModule.sol`, `DegenerusGameLootboxModule.sol`). Baseline, not introduced by this plan, `forge build` exits 0. Already tracked. Not fixed (SCOPE BOUNDARY).

## Known Stubs
None. `claim`/`withdraw` are fully wired against the live `drainAffiliateBase` / `level` producers (354-03) and the `pendingClaim` ledger (declared by prior work per 354-01's locked boundary). The ticket buyer-bonus + open-end belong to 354-05 (parallel, no overlap) — not this plan's concern.

## Threat Flags
None. No new network endpoint / auth path / file-access / schema surface beyond the plan's `<threat_model>`: `claim` is permissionless but credits ONLY the resolved upline chain (never the buyer — `A != sub` guaranteed + the rare U1/U2==sub cycle drop) and drains atomically at the owner (no double-credit); `withdraw` mints to `msg.sender` under CEI (no re-entrancy, idempotent). All five STRIDE rows (SEC01-FREEOPT / DUPSUB / OVERMINT / BUYERWIN / SEC02-CEI) are mitigated as designed.

## User Setup Required
None.

## Next Phase Readiness
- **354-05 (Wave 3, parallel):** the ticket minimal-write primitive + `buyerOwedBurnie` 10%/20% accrual + open-end re-verification. No files_modified overlap with this plan (it touches the Mint/Lootbox/Game ticket path, not `DegenerusAffiliate.sol`).
- **354-06 (Wave 4, the contract gate):** `forge build` clean across the accumulated diff + the per-requirement diff-review + the autonomous:false USER hand-review-and-commit gate (the ONE v56 contract boundary). All SIX producers (`DegenerusGameStorage.sol` [354-01] + `DegenerusQuests.sol`/`IDegenerusQuests.sol` [354-02] + `GameAfkingModule.sol`/`IDegenerusGameModules.sol` [354-03] + `DegenerusAffiliate.sol`/`IDegenerusAffiliate.sol` [354-04]) remain UNCOMMITTED, accumulating for the single USER-approved batched commit.
- **356 TST:** SEC-01 (churn ≤ steady, claim idempotent — re-claim sees `B == 0`, `Σ ≤ sumB`) + SEC-02 (CEI: `pendingClaim` zeroed before `creditFlip`) are now buildable against the live `claim`/`withdraw`.

## Self-Check: PASSED

- FOUND: `.planning/phases/354-.../354-04-SUMMARY.md`
- MODIFIED (uncommitted, per Phase 354 override): `contracts/DegenerusAffiliate.sol`, `contracts/interfaces/IDegenerusAffiliate.sol`
- `claim(address[] calldata subs)` present (1) + interface-declared; `withdraw()` present (1) + interface-declared; `pendingClaim` mapping declared; `drainAffiliateBase(sub)` called INSIDE the claim loop (atomic read-and-zero at the owner); ZERO `uint256[] memory` arrays (no pre-load); ZERO `keccak256`/`currentDayIndex` in the claim body (no roll, no seed); split is `* 20 / 100` + `* 5 / 100` + `aShare = sumB - u1Share - u2Share` (floor + remainder-to-A); `withdraw` zeroes `pendingClaim[msg.sender]` BEFORE the `creditFlip` (CEI); this plan's change set is ONLY `contracts/DegenerusAffiliate.sol` + `contracts/interfaces/IDegenerusAffiliate.sol` (GameAfkingModule.sol NOT edited by 354-04).
- `forge build` exit 0.

No commit hashes to verify for contract files — they are intentionally left uncommitted per the Phase 354 contract-commit override (single USER-approved batched commit deferred to 354-06).

---
*Phase: 354-impl-the-one-carefully-sequenced-batched-contract-diff-aggre*
*Completed: 2026-06-01*
