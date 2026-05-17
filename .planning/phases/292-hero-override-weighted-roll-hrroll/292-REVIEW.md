---
phase: 292-hero-override-weighted-roll-hrroll
reviewed: 2026-05-17T00:00:00Z
depth: standard
files_reviewed: 1
files_reviewed_list:
  - contracts/modules/DegenerusGameJackpotModule.sol
findings:
  critical: 0
  warning: 0
  info: 2
  total: 2
status: issues_found
---

# Phase 292: Code Review Report

**Reviewed:** 2026-05-17
**Depth:** standard
**Files Reviewed:** 1
**Status:** issues_found (Info-tier only — no blockers, no warnings)

## Summary

Reviewed the phase 292 HRROLL change set in `contracts/modules/DegenerusGameJackpotModule.sol`
(commit `a0218952` against base `5bfc26e6`): rewrite of `_applyHeroOverride` to add a third
`heroEntropy` parameter, replacement of `_topHeroSymbol` with the new weighted-random roll
`_rollHeroSymbol`, and the `_rollWinningTraits` callsite update that plumbs raw `randWord`
as the symbol-roll entropy.

The implementation is **correct, safe, and consistent with the locked design decisions**:

- **Weighted-roll math** — Two-pass scan with `uint32[32]` flat cache (D-42N-CACHE-01).
  Cumulative cursor against `pick = uint64(keccak256(abi.encode(entropy, day)) % effectiveTotal)`.
  Strict `>` tie-break selects first-seen leader. Cumulative is provably `≥ effectiveTotal > pick`
  by the last iteration → loop-exit unreachable. Implicit `(false, 0, 0)` fall-through on that
  unreachable path matches the `total == 0` early-bail value (no contract behavior divergence).
- **Integer-overflow safety** — `total` is `uint64`, bounded by 32 × (2^32 − 1) ≈ 2^37; with
  `leaderBonus ≤ maxAmount/2 ≤ 2^31`, `effectiveTotal ≤ 2^37 + 2^31 ≪ 2^64`. Every accumulator
  fits its declared type with substantial margin. The `uint64(...)` cast on the modulo result
  cannot truncate.
- **Storage / packing consistency** — `dailyHeroWagers` is `mapping(uint32 => uint256[4])` per
  `DegenerusGameStorage.sol:1475`. The pass-1 decode (`packed >> (s * 32) & 0xFFFFFFFF` for
  `s ∈ [0,7]`) inverts the writer at `DegenerusGameDegeneretteModule.sol:491-499` exactly,
  including the writer-side `0xFFFFFFFF` saturation cap (so `weights[idx]` cannot exceed
  `2^32 − 1`).
- **Cross-bonus invariance (D-42N-BONUS-ENTROPY-01)** — Callsite at L1988 passes the
  post-bonus-tag `r` as `randomWord` (color extraction) and the raw, pre-tag `randWord` as
  `heroEntropy`. Both bonus and regular rolls within one resolution therefore land on the
  same hero `(quadrant, symbol)` (only colors differ — colors read bit-slices of `r`).
  Confirmed: `_rollHeroSymbol` symbol/quadrant derive from `keccak256(abi.encode(randWord, day))`
  (identical in both calls); color extraction in `_applyHeroOverride` reads `randomWord` (=`r`,
  differs by bonus tag).
- **Entropy commitment window** — `randWord` for day D+1's jackpot is delivered via VRF
  post-wager-commit; it is unknown when day-D bets are placed. Backward trace via
  `_unlockRng` (AdvanceModule) confirms `dailyIdx` is frozen at the prior day's index during
  the entire jackpot window so every `_applyHeroOverride` consumer in one resolution reads
  the same wager pool.
- **Deleted symbol cleanup** — No production code references the removed `_topHeroSymbol`.
  (Stale narrative-comment references survive in `test/edge/HeroOverrideDayIndex.test.js`
  but test files are out of scope per the phase 292 scope note.)
- **NatSpec policy** — Rewritten doc describes what IS; no "previously took" / history-style
  wording. Matches `feedback_no_history_in_comments.md`.

No bugs, no security issues, no quality blockers. Two Info-tier observations on
self-documentation hygiene are recorded below — neither requires action.

## Info

### IN-01: Named returns declared but never assigned by name in `_rollHeroSymbol`

**File:** `contracts/modules/DegenerusGameJackpotModule.sol:1645`
**Issue:** `_rollHeroSymbol` declares `returns (bool hasWinner, uint8 winQuadrant, uint8 winSymbol)`
but every reachable exit uses an explicit tuple return (`return (false, 0, 0)` at L1678 and
`return (true, uint8(idx >> 3), uint8(idx & 7))` at L1694). The named-return identifiers are
never read or written by name anywhere in the body. The only path that depends on the named
zero-defaults is the post-loop fall-through at L1699 — which is provably unreachable
(`cumulative` reaches `effectiveTotal > pick` no later than the last iteration).

This is functionally correct, but mildly inconsistent — a reader scanning for assignments to
`hasWinner` / `winQuadrant` / `winSymbol` finds none. Either anonymous returns (`returns (bool, uint8, uint8)`)
or an explicit terminal `return (false, 0, 0);` (documenting the post-condition rather than
guarding against an impossible state) would make the contract more self-documenting at
zero runtime cost.

Not flagged Warning because: (a) behavior is correct on every reachable path; (b) the
unreachable-tail default coincides with the early-bail value, so even a hypothetical reachable
fall-through would degrade gracefully to "no hero override"; (c) the absence of a terminal
`revert(...)` is the user-directed shape per `feedback_no_dead_guards.md`.

**Fix (optional):** Drop the named-return identifiers, since they are decorative only:
```solidity
function _rollHeroSymbol(uint32 day, uint256 entropy)
    private
    view
    returns (bool, uint8, uint8)
{
    // ... (body unchanged) ...
}
```

### IN-02: NatSpec omits rounding behavior of `leaderBonus = maxAmount / 2`

**File:** `contracts/modules/DegenerusGameJackpotModule.sol:1636`
**Issue:** The NatSpec at L1636 describes "×1.5 leader bonus (`leaderBonus = maxAmount / 2`)".
With Solidity integer division, `maxAmount / 2` truncates toward zero — when `maxAmount` is
odd, the leader's effective multiplier is `(2 * maxAmount + 1) / (2 * maxAmount)`, not exactly
1.5×. For `maxAmount = 5`, leader weight = 7 (1.4×); for `maxAmount = 4`, leader weight = 6
(1.5× exactly).

The arithmetic is intentional and matches the locked spec (D-42N-LEADER-BONUS-01) — the only
gap is documentation. A one-line clarification in the NatSpec would forestall future readers
wondering whether the off-by-half-unit on odd amounts is a bug.

**Fix (optional):** Add a half-sentence to the existing NatSpec:
```solidity
///      effective ×1.5 weight on the leader (integer-truncated for odd maxAmount —
///      e.g., maxAmount=5 → leaderBonus=2, effective leader weight=7), no min-wager
///      floor on any other slot.
```

---

_Reviewed: 2026-05-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
