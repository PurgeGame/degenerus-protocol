---
phase: 279-whole-burnie-floor-bur
reviewed: 2026-05-14T00:00:00Z
depth: standard
files_reviewed: 7
files_reviewed_list:
  - contracts/modules/DegenerusGameLootboxModule.sol
  - contracts/modules/DegenerusGameJackpotModule.sol
  - test/unit/LootboxWholeBurnieFloor.test.js
  - test/unit/JackpotNearFutureCoinFloor.test.js
  - test/unit/JackpotFarFutureCoinFloor.test.js
  - test/stat/WholeBurnieFloorInvariant.test.js
  - test/stat/SurfaceRegression.test.js
findings:
  critical: 0
  warning: 3
  info: 3
  total: 6
status: issues_found
---

# Phase 279: Code Review Report

**Reviewed:** 2026-05-14
**Depth:** standard
**Files Reviewed:** 7
**Status:** issues_found

## Summary

Phase 279 applies a whole-BURNIE integer-division floor `(x / 1 ether) * 1 ether`
at 3 RNG-amount-compute sites across the two contract modules and removes the
now-dead `extra`/`cursor` cursor-rotation machinery in
`_awardDailyCoinToTraitWinners`. The actual contract delta (commit `8ef4a010`) is
small and focused — 2 files, +18/-21 lines — and the floor logic is correct at all
3 sites: the lootbox floor at `_resolveLootboxCommon:1023` floors the final
post-bonus accumulator once before the `!= 0` guard, `creditFlip`, the event field,
and the return tuple; `_awardDailyCoinToTraitWinners:1789` and
`_awardFarFutureCoinJackpot:1896` floor before their respective skip/early-bail
guards. The BUR-01 burnie-accumulation reorder (moved above the boon/ticket blocks
to satisfy the stack-depth ceiling) is behavior-safe — no code between the new and
old positions reads `burnieAmount`, `burnieNoMultiplier`, or `burniePresale`. The
out-of-scope ticket-award cursor-rotation at `DegenerusGameJackpotModule.sol:999`
was correctly left untouched. The `SurfaceRegression.test.js` SURF-01 v40.0 re-cut
ranges are an accurate complement of the OLD-side modified-line set (verified
against `git diff 6a7455d1 HEAD`).

The findings below are quality/robustness concerns, not correctness defects in the
floor arithmetic itself.

**Note on review scope:** The supplied `diff_base`
(`090ff6962b024b7a40a70180f1698e52300aada9^`) points at an unrelated audit-doc
commit and spans dozens of prior phases. The review was re-scoped to the actual
Phase 279 commits — `8ef4a010` (contracts) and `37207743` (tests + package.json) —
which is what "Phase 279 changes" denotes.

## Warnings

### WR-01: Whole-budget evaporation when per-winner share falls below 1 BURNIE

**File:** `contracts/modules/DegenerusGameJackpotModule.sol:1789`, `:1896`
**Issue:** At BUR-02, `baseAmount = ((coinBudget / cap) / 1 ether) * 1 ether` with
`cap = DAILY_COIN_MAX_WINNERS = 50`. When `coinBudget < ~50 ether` the floor yields
`baseAmount == 0`, and the existing `if (winner != address(0) && amount != 0)`
guard silently skips every emit and every `creditFlip` — the **entire** near-future
coin budget (75% of `coinBudget`) is destroyed with no event, no consolation, no
redistribution. BUR-03 has the same shape: when `farBudget / found < 1 ether` the
`if (perWinner == 0) return` early-bail destroys the entire 25% far-future
allocation. `_calcDailyCoinBudget` =
`(levelPrizePool[lvl-1] * PRICE_COIN_UNIT) / (priceWei * 200)` can realistically
produce sub-50-ether budgets at low prize pools / early levels, so this is a
reachable state, not a theoretical one. This is a behavioral change from the
pre-279 code, which distributed the full budget down to 1-wei granularity via the
`extra`/`cursor` rotation.
**Fix:** This is documented and accepted per design IDs D-40N-BUR-DUST-01 /
D-40N-BUR-SILENT-01 and is cross-cited in all 4 new test files, so it is in-scope
intent rather than an unreviewed defect — flagged here only so the economic impact
is on the record. If the intent is "sub-1-BURNIE residue evaporates" but **not**
"the whole budget evaporates," consider clamping `cap` so `coinBudget / cap >= 1
ether` (e.g. `if (cap != 0 && coinBudget / cap < 1 ether) cap = uint16(coinBudget / 1 ether)`)
before the floor, so a small budget still pays at least floor-1-BURNIE to a reduced
winner set. No change recommended if total evaporation is the confirmed design.

### WR-02: Phase 279 test evidence is entirely source-structural — no behavioral coverage of the floor

**File:** `test/unit/LootboxWholeBurnieFloor.test.js`,
`test/unit/JackpotNearFutureCoinFloor.test.js`,
`test/unit/JackpotFarFutureCoinFloor.test.js`,
`test/stat/WholeBurnieFloorInvariant.test.js`
**Issue:** All 4 new test files prove the floor via `extractBody` + regex
string-matching of the contract source plus standalone JS BigInt re-implementations
of `(x / 1 ether) * 1 ether`. None of them deploy the contracts or assert that an
actual on-chain `creditFlip` / `JackpotBurnieWin` / `LootBoxOpened` amount is a
whole-BURNIE multiple. A regex pass proves the *text* `burnieAmount = (burnieAmount
/ 1 ether) * 1 ether` exists; it does not prove that text is on the live code path,
that no later statement re-fractionalizes the value, or that the floored local is
actually the one threaded into `creditFlip`. The index-ordering assertions
partially mitigate this, but a refactor that renamed a variable or moved the
`creditFlip` call would silently pass or silently break the regex without any
behavioral signal.
**Fix:** Accepted per the documented FIXTURE_COVERAGE_GAP_NOTED precedent
(`JackpotTicketRollSilentColdBust.test.js`, Phase 266/275/276/278) — the 3 BUR
sites are `private` with no deterministic full-state harness. Recommend adding a
behavioral assertion to whichever integration/edge fixture *does* exercise
`openLootBox` end-to-end (e.g. `test/edge/LootboxAutoResolveRegression.test.js`):
assert the `LootBoxOpened.burnie` event arg `% 1 ether == 0`. This converts the
load-bearing evidence from "the text exists" to "the deployed contract behaves,"
at near-zero cost since the fixture already runs.

### WR-03: `extractBody` brace-matcher runs before comment-stripping — latent fragility in the shared test infra

**File:** `test/unit/LootboxWholeBurnieFloor.test.js:46-66` (and the three sibling
copies)
**Issue:** Every Phase 279 test file copies `extractBody`, which brace-counts the
raw source to find a function body, and only afterward applies
`stripLineComments`. If any function body in the two modules ever gains a `//` or
`/* */` comment containing an unbalanced `{` or `}` (e.g. a NatSpec example or a
prose `} else {`), `extractBody` will mis-terminate the body and every regex
assertion in that file silently changes meaning — a false pass or a confusing false
fail. The currently-targeted functions happen to be clean, so this does not affect
Phase 279 correctness, but the pattern is now copied into 4 more files and is one
comment edit away from a misleading test result.
**Fix:** Pre-existing pattern, not introduced by this phase — flagging for
awareness. The robust fix is to `stripLineComments` (and block comments) *before*
brace-matching, or to extract `extractBody` into a single shared test helper module
so the fragility is fixed once rather than in N copies. The in-file comments
already acknowledge the copy-paste ("copied from
JackpotTicketRollSilentColdBust.test.js"), which is the right time to de-duplicate.

## Info

### IN-01: Four test files duplicate `extractBody`, `stripLineComments`, `floorWholeBurnie`, and `makeRng` verbatim

**File:** `test/unit/LootboxWholeBurnieFloor.test.js`,
`test/unit/JackpotNearFutureCoinFloor.test.js`,
`test/unit/JackpotFarFutureCoinFloor.test.js`,
`test/stat/WholeBurnieFloorInvariant.test.js`
**Issue:** `extractBody` (~20 lines), `stripLineComments` (~10 lines), and
`floorWholeBurnie` are copy-pasted identically into all 4 new files; `makeRng` is
copied into the stat file. This is ~120 lines of duplicated infra. A bug fix in
the brace-matcher (see WR-03) must now be applied in 4 places, and they can drift.
**Fix:** Factor the shared helpers into `test/helpers/sourceStructural.js` (or
similar) and import. The files themselves document the duplication, so the intent
to share is already implicit.

### IN-02: `JackpotNearFutureCoinFloor.test.js` comment references a stale line anchor

**File:** `test/unit/JackpotNearFutureCoinFloor.test.js:37`
**Issue:** The CROSS-CITES header says "the ticket-award cursor-rotation near :1003
is OUT OF SCOPE." The out-of-scope cursor-rotation is currently at
`DegenerusGameJackpotModule.sol:999-1021`. Line-number anchors in comments rot on
every edit to the file above them; per the project convention "comments describe
what IS," a function-name anchor (`_distributeTicketJackpot` or whichever function
owns L999) is more durable than `:1003`.
**Fix:** Replace the `:1003` anchor with the owning function name. Low priority —
the disambiguation intent is clear from context.

### IN-03: BUR-01 bytecode delta is NET-POSITIVE (+114 bytes), deviating from the plan's NET-NEGATIVE expectation

**File:** `contracts/modules/DegenerusGameLootboxModule.sol`
**Issue:** The Phase 279 commit message records that `DegenerusGameLootboxModule`
grew +140 bytes because `_resolveLootboxCommon` is at the Solidity stack-depth
ceiling and the BUR-01 floor statement forces a less-compact Yul stack schedule.
This is a deviation from the plan's BUR-05 NET-NEGATIVE expectation.
**Fix:** No action required — the commit message states this is "accepted by
explicit user decision" and notes the BUR-01 floor is "non-negotiable." Recorded
here only for completeness of the review trail. The stack-depth pressure is worth
keeping in mind for any future edit to `_resolveLootboxCommon`.

---

_Reviewed: 2026-05-14_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
