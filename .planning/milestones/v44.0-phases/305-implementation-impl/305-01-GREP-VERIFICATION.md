# Phase 305 Plan 01 — Pre-Patch Grep-Verification Manifest

**Phase:** 305-implementation-impl
**Plan:** 01 — sStonk per-day redemption refactor IMPL
**Generated:** 2026-05-19
**Baseline HEAD (Phase 304 Plan 05 attestation):** `MILESTONE_V43_AT_HEAD_8111cfc5189f628b64b500c881f9995c3edf0ed2` (tag `v43.0`)
**Current working-tree HEAD:** `2240c547783f9681d0e14a8d27b93bc80a704fe7` (`docs(305): mark planning complete — Ready to execute`)
**Scope:** Re-verify every cited `file:line` in `304-SPEC.md §5` against the CURRENT working-tree HEAD per D-305-GREP-01 + `feedback_verify_call_graph_against_source.md`. Re-verify the additional test-file compile-break sites enumerated in `305-CONTEXT.md <domain>` and surfaced in `305-01-PLAN.md <interfaces>` (5 in `RedemptionGas.t.sol` + 2 in `CoverageGap222.t.sol` = 7 test-file sites).
**Aggregate result:** **All cited locations VERIFIED-NO-DRIFT.** `git diff --stat 8111cfc5..HEAD -- contracts/StakedDegenerusStonk.sol contracts/modules/DegenerusGameAdvanceModule.sol contracts/interfaces/IStakedDegenerusStonk.sol test/fuzz/RedemptionGas.t.sol test/fuzz/CoverageGap222.t.sol` returns empty — all 5 target files are byte-identical to the v43.0 baseline HEAD. Phase 304 itself produced 5 SPEC-doc commits + zero source-tree mutations between baseline HEAD and Phase 305 start, so this is the structurally-expected outcome; Plan 05's 61 VERIFIED / 0 CORRECTED / 0 ABSENT manifest re-asserts intact.

---

## §A — `contracts/StakedDegenerusStonk.sol` re-verification table (50 rows)

| # | Cited at §N (304-SPEC) | Cited line | Expected content | Status at Phase 305 start | Drift note |
|---|------------------------|------------|------------------|---------------------------|------------|
| 1 | §3 EDGE preamble + EDGE error refs | `:88-117` | ERRORS block (`Unauthorized..ExceedsDailyRedemptionCap`) | VERIFIED-NO-DRIFT | — |
| 2 | §3 EDGE-11 + EDGE error refs | `:100` | `error BurnsBlockedDuringRng()` | VERIFIED-NO-DRIFT | — |
| 3 | §3 EDGE-12 + EDGE error refs | `:105` | `error BurnsBlockedDuringLiveness()` | VERIFIED-NO-DRIFT | — |
| 4 | §2.7 item 6 + §4 Deletion 6 | `:108` | `error UnresolvedClaim()` | VERIFIED-NO-DRIFT | — |
| 5 | §3 EDGE-09 + EDGE-10 | `:111` | `error NoClaim()` | VERIFIED-NO-DRIFT | — |
| 6 | §3 EDGE-05 + §2 SPEC-02 | `:114` | `error NotResolved()` | VERIFIED-NO-DRIFT | — |
| 7 | §1 INV-11 + §3 EDGE-15 | `:117` | `error ExceedsDailyRedemptionCap()` | VERIFIED-NO-DRIFT | — |
| 8 | §1 storage preamble + §2 SPEC-02 | `:209-214` | `PendingRedemption` struct (4 fields) | VERIFIED-NO-DRIFT | — |
| 9 | §2 SPEC-02 + §4 Deletion 6 | `:212` | `uint32 periodIndex` field in `PendingRedemption` | VERIFIED-NO-DRIFT | — |
| 10 | §1 storage preamble | `:216-219` | `RedemptionPeriod` struct (`roll` + `flipDay`) | VERIFIED-NO-DRIFT | — |
| 11 | §1 INV-NN + §2 SPEC-02 | `:221` | `mapping(address => PendingRedemption) public pendingRedemptions` | VERIFIED-NO-DRIFT | — |
| 12 | §1 INV-NN + §4 Deletion 1 | `:222` | `mapping(uint32 => RedemptionPeriod) public redemptionPeriods` | VERIFIED-NO-DRIFT | — |
| 13 | §1 INV-02 + §2 SPEC-01 | `:224` | `uint256 public pendingRedemptionEthValue` | VERIFIED-NO-DRIFT | — |
| 14 | §1 INV-03 + §2 SPEC-01 | `:225` | `uint256 internal pendingRedemptionBurnie` | VERIFIED-NO-DRIFT | — |
| 15 | §2 SPEC-01 + §2.7 item 4 + §4 Deletion 4 | `:226` | `uint256 internal pendingRedemptionEthBase` | VERIFIED-NO-DRIFT | — |
| 16 | §2 SPEC-01 + §2.7 item 5 + §4 Deletion 5 | `:227` | `uint256 internal pendingRedemptionBurnieBase` | VERIFIED-NO-DRIFT | — |
| 17 | §2 SPEC-01 + §2.7 item 2 + §4 Deletion 2 | `:229` | `uint256 internal redemptionPeriodSupplySnapshot` | VERIFIED-NO-DRIFT | — |
| 18 | §2 SPEC-01 + §2.7 item 1 + §4 Deletion 1 | `:230` | `uint32 internal redemptionPeriodIndex` | VERIFIED-NO-DRIFT | — |
| 19 | §2 SPEC-01 + §2.7 item 3 + §4 Deletion 3 | `:231` | `uint256 internal redemptionPeriodBurned` | VERIFIED-NO-DRIFT | — |
| 20 | §1 INV-11 + §2 SPEC-NN | `:254` | `uint256 private constant MAX_DAILY_REDEMPTION_EV = 160 ether` | VERIFIED-NO-DRIFT | — |
| 21 | §3 EDGE-11 + EDGE-12 | `:486-495` | `burn()` external entry function | VERIFIED-NO-DRIFT | — |
| 22 | §3 EDGE-12 + §2 SPEC-01 (preserves guard) | `:491` | `if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();` | VERIFIED-NO-DRIFT | — |
| 23 | §3 EDGE-11 + §2 SPEC-01 (preserves guard) | `:492` | `if (game.rngLocked()) revert BurnsBlockedDuringRng();` | VERIFIED-NO-DRIFT | — |
| 24 | §4 Deletion 4 | `:578` | `hasPendingRedemptions()` body returns `pendingRedemptionEthBase != 0 \|\| pendingRedemptionBurnieBase != 0` | VERIFIED-NO-DRIFT | — |
| 25 | §1 + §2 SPEC-03 + §3 + §4 Deletion 1 | `:585-610` | `resolveRedemptionPeriod()` function body | VERIFIED-NO-DRIFT | — |
| 26 | §4 Deletion 1 + §4 Deletion 7 | `:588` | `uint32 period = redemptionPeriodIndex;` | VERIFIED-NO-DRIFT | — |
| 27 | §2 SPEC-04 (c) + §4 Deletion 4 | `:589` | `if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;` | VERIFIED-NO-DRIFT | — |
| 28 | §1 INV-02 + §4 Deletion 4 | `:592` | `uint256 rolledEth = (pendingRedemptionEthBase * roll) / 100;` | VERIFIED-NO-DRIFT | — |
| 29 | §4 Deletion 4 | `:593` | `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;` | VERIFIED-NO-DRIFT | — |
| 30 | §4 Deletion 4 | `:594` | `pendingRedemptionEthBase = 0;` | VERIFIED-NO-DRIFT | — |
| 31 | §4 Deletion 5 | `:597` | `uint256 burnieToCredit = (pendingRedemptionBurnieBase * roll) / 100;` | VERIFIED-NO-DRIFT | — |
| 32 | §1 INV-03 + §4 Deletion 5 | `:600` | `pendingRedemptionBurnie -= pendingRedemptionBurnieBase;` | VERIFIED-NO-DRIFT | — |
| 33 | §4 Deletion 5 | `:601` | `pendingRedemptionBurnieBase = 0;` | VERIFIED-NO-DRIFT | — |
| 34 | §1 INV-01 + §4 Deletion 1 | `:604-607` | `redemptionPeriods[period] = RedemptionPeriod({ roll: roll, flipDay: flipDay });` | VERIFIED-NO-DRIFT | — |
| 35 | §4 Deletion 5 | `:609` | `emit RedemptionResolved(period, roll, burnieToCredit, flipDay);` | VERIFIED-NO-DRIFT | — |
| 36 | §2 SPEC-02 + §3 EDGE-05/08/09/10 | `:618-684` | `claimRedemption()` function body | VERIFIED-NO-DRIFT | — |
| 37 | §3 EDGE-05 + §2 SPEC-02 (preserves) | `:624` | `if (period.roll == 0) revert NotResolved();` | VERIFIED-NO-DRIFT | — |
| 38 | §1 INV-02 + §3 EDGE-09 + §4 Deletion 4 (analog) | `:632` | `uint256 totalRolledEth = (claim.ethValueOwed * roll) / 100;` | VERIFIED-NO-DRIFT | — |
| 39 | §2 SPEC-04 (a) + §3 EDGE-08 | `:635` | `bool isGameOver = game.gameOver();` | VERIFIED-NO-DRIFT | — |
| 40 | §2 SPEC-04 (a) + §3 EDGE-08 | `:638-643` | `if (isGameOver) { ethDirect = totalRolledEth; } else { ethDirect = totalRolledEth / 2; lootboxEth = totalRolledEth - ethDirect; }` | VERIFIED-NO-DRIFT | — |
| 41 | §2 SPEC-04 (d) + §3 EDGE-18 | `:649-654` | coinflip oracle read block (`getCoinflipDayResult(period.flipDay)` + `flipResolved` calc) | VERIFIED-NO-DRIFT | — |
| 42 | §1 INV-02 + §3 EDGE-09 + EDGE-10 | `:657` | `pendingRedemptionEthValue -= totalRolledEth;` | VERIFIED-NO-DRIFT | — |
| 43 | §2 SPEC-04 (d) + §3 EDGE-10 + §4 Deletion 6 walk | `:659-665` | partial-claim branch (`delete pendingRedemptions[player]` on full; `claim.ethValueOwed = 0` on partial) | VERIFIED-NO-DRIFT | — |
| 44 | §2 SPEC-04 (d) + §3 EDGE-10 | `:660-661` | `// Full claim: clear entirely / delete pendingRedemptions[player];` | VERIFIED-NO-DRIFT | — |
| 45 | §2 SPEC-04 (d) | `:667-673` | lootbox-eth resolve block (`game.resolveRedemptionLootbox(...)`) | VERIFIED-NO-DRIFT | — |
| 46 | §3 EDGE-10 trace | `:677` | `_payBurnie(player, burniePayout);` | VERIFIED-NO-DRIFT | — |
| 47 | §3 EDGE-10 trace | `:680` | `emit RedemptionClaimed(player, roll, flipResolved, ethDirect, burniePayout, lootboxEth);` | VERIFIED-NO-DRIFT | — |
| 48 | §1 INV-NN + §3 EDGE-10 (CEI tail) | `:683` | `_payEth(player, ethDirect);` (pay-eth-LAST CEI ordering) | VERIFIED-NO-DRIFT | — |
| 49 | §1 + §2 + §3 + §4 refs | `:752-814` | `_submitGamblingClaimFrom()` body | VERIFIED-NO-DRIFT | — |
| 50 | §2 SPEC-04 (b) + §3 EDGE-13 | `:754` | `if (amount == 0 \|\| amount > bal) revert Insufficient();` | VERIFIED-NO-DRIFT | — |
| 51 | §2 SPEC-05 + §2.7 item 7 + §4 Deletion 7 | `:757-762` | `currentPeriod` local read (`:757`) + reset block (`:758-762`) | VERIFIED-NO-DRIFT | — |
| 52 | §1 INV-10 + §3 EDGE-14 | `:763` | `if (redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2) revert Insufficient();` | VERIFIED-NO-DRIFT | — |
| 53 | §4 Deletion 3 + §4 Deletion 7 | `:764` | `redemptionPeriodBurned += amount;` | VERIFIED-NO-DRIFT | — |
| 54 | §2 SPEC-05 | `:766` | `uint256 supplyBefore = totalSupply;` (pre-decrement snapshot) | VERIFIED-NO-DRIFT | — |
| 55 | §4 Deletion 2 | `:784` | `totalSupply -= amount;` (single mutator post-launch) | VERIFIED-NO-DRIFT | — |
| 56 | §4 Deletion 4 | `:790` | `pendingRedemptionEthBase += ethValueOwed;` | VERIFIED-NO-DRIFT | — |
| 57 | §4 Deletion 5 walk | `:791` | `pendingRedemptionBurnie += burnieOwed;` (cumulative) | VERIFIED-NO-DRIFT | — |
| 58 | §4 Deletion 5 | `:792` | `pendingRedemptionBurnieBase += burnieOwed;` | VERIFIED-NO-DRIFT | — |
| 59 | §2 SPEC-02 + §2.7 item 6 + §4 Deletion 6 | `:796-797` | `if (claim.periodIndex != 0 && claim.periodIndex != currentPeriod) { revert UnresolvedClaim(); }` | VERIFIED-NO-DRIFT | — |
| 60 | §1 INV-11 + §3 EDGE-15 | `:801` | `if (claim.ethValueOwed + ethValueOwed > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();` | VERIFIED-NO-DRIFT | — |
| 61 | §3 EDGE-15 + §4 Deletion 6 walk | `:803` | `claim.ethValueOwed += uint96(ethValueOwed);` | VERIFIED-NO-DRIFT | — |
| 62 | §3 EDGE-13 trace | `:818` | `if (amount == 0) return;` (`_payEth` zero-guard) | VERIFIED-NO-DRIFT | — |
| 63 | §3 EDGE-10 (TransferFailed) | `:828-829` | `(bool success, ) = player.call{value: amount}(""); if (!success) revert TransferFailed();` | VERIFIED-NO-DRIFT | — |
| 64 | §3 EDGE-10 (TransferFailed stETH path) | `:834-835` | `(bool success, ) = player.call{value: ethOut}(""); if (!success) revert TransferFailed();` | VERIFIED-NO-DRIFT | — |
| 65 | §1 INV-03 + §3 EDGE-18 + §4 Deletion 5 walk | `:842-852` | `_payBurnie()` fallback chain body | VERIFIED-NO-DRIFT | — |
| 66 | §3 EDGE-18 | `:850` | `coinflip.claimCoinflipsForRedemption(address(this), remaining);` | VERIFIED-NO-DRIFT | — |

**Note on row count:** The §5.1 manifest declares "50 grep-verified citations"; this table contains 66 rows because the SPEC's "50" count appears to count multi-line ranges as single citations while this table breaks them out per-cited-anchor for the executor's convenience. Aggregate disposition is unchanged: every row is VERIFIED-NO-DRIFT.

**Note on `:806`:** The `claim.periodIndex = currentPeriod;` line at `:806` is not in 304-SPEC.md §5.1's enumerated table but IS cited in 305-01-PLAN.md Mutation 10 step 13 as "DELETE `:806 claim.periodIndex = currentPeriod;`". Direct grep verifies: `awk 'NR==806' contracts/StakedDegenerusStonk.sol` returns `        claim.periodIndex = currentPeriod;` — VERIFIED-NO-DRIFT.

---

## §B — `contracts/modules/DegenerusGameAdvanceModule.sol` re-verification table (11 rows + exhaustive call-graph attestation)

| # | Cited at §N (304-SPEC) | Cited line | Expected content | Status at Phase 305 start | Drift note |
|---|------------------------|------------|------------------|---------------------------|------------|
| 1 | §4 Deletion 1 reference (interface boundary) | `:19` | `import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";` | VERIFIED-NO-DRIFT | — |
| 2 | §4 Deletion 1 walk | `:1187` | `if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);` | VERIFIED-NO-DRIFT | — |
| 3 | §2 SPEC-03 + §3 + §4 Deletion 4 walk | `:1222-1230` | FIRST sStonk resolve call block (`IStakedDegenerusStonk sdgnrs = ... ; if (sdgnrs.hasPendingRedemptions()) { ... sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay); }`) | VERIFIED-NO-DRIFT | — |
| 4 | §2 SPEC-03 + §4 Deletion 4 walk | `:1225` | FIRST `if (sdgnrs.hasPendingRedemptions()) {` gate | VERIFIED-NO-DRIFT | — |
| 5 | §2 SPEC-03 first AdvanceModule call site | `:1230` | FIRST `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);` call | VERIFIED-NO-DRIFT | — |
| 6 | §2 SPEC-03 second AdvanceModule call site | `:1285-1293` | SECOND sStonk resolve call block (mirrors rngGate redemption resolution) | VERIFIED-NO-DRIFT | — |
| 7 | §2 SPEC-03 second gate | `:1288` | SECOND `if (sdgnrs.hasPendingRedemptions()) {` gate | VERIFIED-NO-DRIFT | — |
| 8 | §2 SPEC-03 second resolve call | `:1293` | SECOND `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);` call | VERIFIED-NO-DRIFT | — |
| 9 | §2 SPEC-03 third AdvanceModule call site | `:1315-1323` | THIRD sStonk resolve call block (gameover-fallback path; `fallbackWord` not `currentWord`) | VERIFIED-NO-DRIFT | — |
| 10 | §2 SPEC-03 third gate | `:1318` | THIRD `if (sdgnrs.hasPendingRedemptions()) {` gate | VERIFIED-NO-DRIFT | — |
| 11 | §2 SPEC-03 third resolve call | `:1323` | THIRD `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);` call | VERIFIED-NO-DRIFT | — |

**Exhaustive call-graph attestation (per `feedback_verify_call_graph_against_source.md` Phase 294 BURNIE-gap precedent):**

```
$ grep -nc "sdgnrs.resolveRedemptionPeriod" contracts/modules/DegenerusGameAdvanceModule.sol
3
$ grep -nc "sdgnrs.hasPendingRedemptions"   contracts/modules/DegenerusGameAdvanceModule.sol
3
$ grep -n  "sdgnrs.resolveRedemptionPeriod\|sdgnrs.hasPendingRedemptions" contracts/modules/DegenerusGameAdvanceModule.sol
1225:                if (sdgnrs.hasPendingRedemptions()) {
1230:                    sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
1288:                if (sdgnrs.hasPendingRedemptions()) {
1293:                    sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
1318:                    if (sdgnrs.hasPendingRedemptions()) {
1323:                        sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
```

Exactly 6 hits across the two greps: 3 gates at `:1225/:1288/:1318` + 3 resolve calls at `:1230/:1293/:1323`. Each gate is paired one-for-one with a resolve call inside the same `if`-block. Mutation 12 must rewrite **all 6** sites symmetrically — pass `day - 1` to every gate AND every resolve call. Failure to update any one of the six = compile-break or silent partial-fix (Phase 294 BURNIE-gap recurrence per `feedback_verify_call_graph_against_source.md`).

---

## §C — Test-file compile-break site verification

| # | File | Cited line | Expected content (pre-refactor) | Status at Phase 305 start | Drift note |
|---|------|------------|---------------------------------|---------------------------|------------|
| 1 | `test/fuzz/RedemptionGas.t.sol` | `:78` | `sdgnrs.resolveRedemptionPeriod(100, currentDay);` | VERIFIED-NO-DRIFT | — |
| 2 | `test/fuzz/RedemptionGas.t.sol` | `:94` | `sdgnrs.resolveRedemptionPeriod(100, currentDay);` | VERIFIED-NO-DRIFT | — |
| 3 | `test/fuzz/RedemptionGas.t.sol` | `:113` | `sdgnrs.claimRedemption();` | VERIFIED-NO-DRIFT | Not enumerated in 305-CONTEXT.md `<domain>`; surfaced by 305-01-PLAN.md `<interfaces>` block. Compile-break site #5 on this file. |
| 4 | `test/fuzz/RedemptionGas.t.sol` | `:127` | `bool pending = sdgnrs.hasPendingRedemptions();` | VERIFIED-NO-DRIFT | — |
| 5 | `test/fuzz/RedemptionGas.t.sol` | `:134` | `bool pending = sdgnrs.hasPendingRedemptions();` | VERIFIED-NO-DRIFT | — |
| 6 | `test/fuzz/CoverageGap222.t.sol` | `:948` | `"resolveRedemptionPeriod(uint16,uint32)",` (selector string) | VERIFIED-NO-DRIFT | — |
| 7 | `test/fuzz/CoverageGap222.t.sol` | `:955` | `abi.encodeWithSignature("claimRedemption()")` | VERIFIED-NO-DRIFT | Plan flags this as the 7th compile-break site beyond CONTEXT.md's enumeration — Mutation 14 must update both `:948` (resolve selector) AND `:955` (claim selector) to keep the ACL-rejection test compiling. |
| 8 | `test/fuzz/CoverageGap222.t.sol` | `:973` | `assertFalse(o1, "sdgnrs.resolveRedemptionPeriod rejected non-authorized caller");` (BYTE-IDENTICAL — preserved) | VERIFIED-NO-DRIFT | Assertion text unchanged by refactor. |
| 9 | `test/fuzz/CoverageGap222.t.sol` | `:974` | `assertFalse(o2, "sdgnrs.claimRedemption rejected caller with no pending redemption");` (BYTE-IDENTICAL — preserved) | VERIFIED-NO-DRIFT | Assertion text unchanged by refactor; `claimRedemption(day)` with `day=0` still trips the no-claim revert post-refactor. |

**Direct grep evidence:**
```
$ grep -n "resolveRedemptionPeriod\|hasPendingRedemptions\|claimRedemption" test/fuzz/RedemptionGas.t.sol test/fuzz/CoverageGap222.t.sol
test/fuzz/RedemptionGas.t.sol:9:/// @notice Exercises burn, burnWrapped, resolveRedemptionPeriod, claimRedemption,
test/fuzz/RedemptionGas.t.sol:10:///         hasPendingRedemptions, and previewBurn in isolation for clean gas measurement.
test/fuzz/RedemptionGas.t.sol:69:    /// @notice Gas benchmark: resolveRedemptionPeriod() called by game contract
test/fuzz/RedemptionGas.t.sol:70:    function test_gas_resolveRedemptionPeriod() external {
test/fuzz/RedemptionGas.t.sol:78:        sdgnrs.resolveRedemptionPeriod(100, currentDay);
test/fuzz/RedemptionGas.t.sol:85:    /// @notice Gas benchmark: claimRedemption() after full resolve lifecycle
test/fuzz/RedemptionGas.t.sol:86:    function test_gas_claimRedemption() external {
test/fuzz/RedemptionGas.t.sol:94:        sdgnrs.resolveRedemptionPeriod(100, currentDay);
test/fuzz/RedemptionGas.t.sol:96:        // Step 3: Mock the coinflip day result so claimRedemption doesn't revert
test/fuzz/RedemptionGas.t.sol:113:        sdgnrs.claimRedemption();
test/fuzz/RedemptionGas.t.sol:120:    /// @notice Gas benchmark: hasPendingRedemptions() when redemptions exist
test/fuzz/RedemptionGas.t.sol:121:    function test_gas_hasPendingRedemptions_true() external {
test/fuzz/RedemptionGas.t.sol:127:        bool pending = sdgnrs.hasPendingRedemptions();
test/fuzz/RedemptionGas.t.sol:131:    /// @notice Gas benchmark: hasPendingRedemptions() when no redemptions exist
test/fuzz/RedemptionGas.t.sol:132:    function test_gas_hasPendingRedemptions_false() external view {
test/fuzz/RedemptionGas.t.sol:134:        bool pending = sdgnrs.hasPendingRedemptions();
test/fuzz/CoverageGap222.t.sol:948:                "resolveRedemptionPeriod(uint16,uint32)",
test/fuzz/CoverageGap222.t.sol:955:            abi.encodeWithSignature("claimRedemption()")
test/fuzz/CoverageGap222.t.sol:973:        assertFalse(o1, "sdgnrs.resolveRedemptionPeriod rejected non-authorized caller");
test/fuzz/CoverageGap222.t.sol:974:        assertFalse(o2, "sdgnrs.claimRedemption rejected caller with no pending redemption");
```

The `/// @notice` doc-comments at `RedemptionGas.t.sol:9-10`, `:69`, `:85`, `:120`, `:131` reference function names that survive the refactor (only signatures change), so no doc-comment changes are required. The `RedemptionGas.t.sol:96` comment ("Step 3: Mock the coinflip day result so claimRedemption doesn't revert") is also unaffected.

---

## §D — Aggregate status attestation

**Total citations re-verified:** 66 sStonk rows (§A) + 11 AdvanceModule rows (§B) + 9 test-file rows (§C) = **86 total cited file:line locations**.

**Status distribution:**
- VERIFIED-NO-DRIFT: **86**
- DRIFTED-WITH-CORRECTION: 0
- ABSENT: 0

**Verdict:** **Working-tree HEAD is byte-identical to v43.0 baseline HEAD `8111cfc5189f628b64b500c881f9995c3edf0ed2` for all cited file:line locations in `304-SPEC.md §5` plus the test-file compile-break sites surfaced by `305-CONTEXT.md <domain>` and `305-01-PLAN.md <interfaces>`. Task 2 proceeds with line numbers verbatim from 304-SPEC.md §5 + 305-CONTEXT.md `<domain>` + 305-01-PLAN.md `<interfaces>`. No corrected line numbers required.**

Structural rationale for the zero-drift outcome: the only commits between baseline HEAD `8111cfc5` and Phase 305 start HEAD `2240c547` are 5 documentation commits (Phase 304's 5 SPEC-doc plans + Phase 305's context/plan-creation commits) — `git diff --stat 8111cfc5..HEAD -- contracts/ test/fuzz/RedemptionGas.t.sol test/fuzz/CoverageGap222.t.sol` returns empty. Zero source-tree mutations have landed between manifest write-time and pre-patch verification time. This is the expected outcome under the SPEC-doc-only Phase 304 deliverable.

---

## §E — Per-mutation work-item enumeration (pre-patch, in execution order)

The 14 mutations Task 2 executes against the verified line numbers above. SPEC-NN anchors per `304-SPEC.md §2`. Each mutation is locked by SPEC; no executor discretion on semantics (only on comment verbosity, local variable names, and the optional `DayPending storage pool` alias per `305-CONTEXT.md <decisions>` Claude's Discretion block).

1. **Mutation 1 — DELETE `error UnresolvedClaim();` at `StakedDegenerusStonk.sol:108`** — SPEC-02 + SPEC §2.7 deletion 6. The `///` natspec block at `:107` is deleted along with the error.
2. **Mutation 2 — REMOVE `uint32 periodIndex` field from `PendingRedemption` struct at `:212`** — SPEC-02. POST-state: `struct PendingRedemption { uint96 ethValueOwed; uint96 burnieOwed; uint16 activityScore; }` (208 bits, still 1 slot).
3. **Mutation 3 — ADD `struct DayPending` declaration near `:216-218` region (alongside `RedemptionPeriod`)** — SPEC-01. Shape: `{ uint256 ethBase; uint256 burnieBase; uint128 supplySnapshot; uint128 burned; }` — 3 slots/day.
4. **Mutation 4 — CHANGE `mapping(address => PendingRedemption) public pendingRedemptions` at `:221` to `mapping(address => mapping(uint32 => PendingRedemption)) public pendingRedemptions`** — SPEC-02 composite key.
5. **Mutation 5 — DELETE 5 storage slots at `:226-231`** — SPEC §2.7 deletions 1-5: `pendingRedemptionEthBase`, `pendingRedemptionBurnieBase`, `redemptionPeriodSupplySnapshot`, `redemptionPeriodIndex`, `redemptionPeriodBurned`. PRESERVE `pendingRedemptionEthValue` (`:224`) + `pendingRedemptionBurnie` (`:225`).
6. **Mutation 6 — ADD `mapping(uint32 => DayPending) internal pendingByDay;` declaration immediately after `pendingRedemptionBurnie` at `:225`** — SPEC-01 + D-305-STORAGE-01.
7. **Mutation 7 — REWRITE `hasPendingRedemptions()` at `:577-579` to 1-arg form** — SPEC-03 secondary lock. POST-state body: `return pendingByDay[day].ethBase != 0 || pendingByDay[day].burnieBase != 0;`.
8. **Mutation 8 — REWRITE `resolveRedemptionPeriod` at `:585-610` to 3-arg form** — SPEC-03 + SPEC-04 (a) + SPEC-04 (c). Reads/writes re-keyed to `pendingByDay[dayToResolve]`; writes `redemptionPeriods[dayToResolve]`; emits `RedemptionResolved(dayToResolve, roll, burnieToCredit, flipDay)`; then `delete pendingByDay[dayToResolve]` per SPEC-04 (c) ordering (AFTER write + emit). ACL check at `:586` (`if (msg.sender != ContractAddresses.GAME) revert Unauthorized();`) PRESERVED VERBATIM.
9. **Mutation 9 — REWRITE `claimRedemption()` at `:618-684` to 1-arg form** — SPEC-02 + SPEC-04 (d). Composite-key read `pendingRedemptions[msg.sender][day]` + `redemptionPeriods[day]`. `period.roll == 0` `NotResolved` revert at `:624` PRESERVED VERBATIM. Partial-claim branch at `:659-665` PRESERVED VERBATIM (only `claim.ethValueOwed = 0;` on `!flipResolved`). Full-claim path: `delete pendingRedemptions[msg.sender][day]` AFTER `_payBurnie` + `emit RedemptionClaimed`. Rename `claim.periodIndex == 0` NoClaim sentinel to `claim.ethValueOwed == 0 && claim.burnieOwed == 0` (or equivalent — executor discretion).
10. **Mutation 10 — REWRITE `_submitGamblingClaimFrom` at `:752-814`** — SPEC-01 + SPEC-02 + SPEC-04 (b) + SPEC-05. Replace `:758-762` reset block with SPEC-05 lazy-init `if (pendingByDay[currentPeriod].supplySnapshot == 0 && pendingByDay[currentPeriod].burned == 0) { pendingByDay[currentPeriod].supplySnapshot = uint128(totalSupply); }`. Re-key cap check at `:763` + cap accumulator at `:764` to `pendingByDay[currentPeriod].burned`. Re-key segregate writes at `:790-792` to `pendingByDay[currentPeriod].ethBase` + `pendingByDay[currentPeriod].burnieBase` (cumulative `pendingRedemptionEthValue` + `pendingRedemptionBurnie` PRESERVED). Re-key per-claim pointer at `:795` to `pendingRedemptions[beneficiary][currentPeriod]`. DELETE `:796-797` `UnresolvedClaim` revert block. DELETE `:806` `claim.periodIndex = currentPeriod;`. `:757` `currentPeriod` local declaration PRESERVED (consumed downstream). `:754` zero-amount revert PRESERVED per SPEC-04 (b).
11. **Mutation 11 — UPDATE `IStakedDegenerusStonk.sol` at `:86` + `:96`** — SPEC-03. `:86` 0-arg → 1-arg `hasPendingRedemptions(uint32 day)`; `:96` 2-arg → 3-arg `resolveRedemptionPeriod(uint16, uint32, uint32)`. `claimRedemption(uint32 day)` NOT added (not in pre-refactor interface; out of scope per CONTEXT.md `<canonical_refs>`).
12. **Mutation 12 — UPDATE `DegenerusGameAdvanceModule.sol` 3 call-site blocks** — D-305-DAYTORESOLVE-01 + Phase 294 BURNIE-gap precedent prevention. Each site updates BOTH gate AND call:
    - Site 1 (`:1225` + `:1230`): `hasPendingRedemptions()` → `hasPendingRedemptions(day - 1)`; `resolveRedemptionPeriod(redemptionRoll, flipDay)` → `resolveRedemptionPeriod(redemptionRoll, flipDay, day - 1)`.
    - Site 2 (`:1288` + `:1293`): same dual update.
    - Site 3 (`:1318` + `:1323`): same dual update.
    All 3 sites pass IDENTICAL `day - 1` expression for future-grep enumeration cleanness. RNG-derivation lines (`:1226-1228`, `:1289-1291`, `:1319-1321`) and `flipDay` computations (`:1229`, `:1292`, `:1322`) BYTE-IDENTICAL per `feedback_rng_backward_trace.md`.
13. **Mutation 13 — FIX `test/fuzz/RedemptionGas.t.sol` 5 compile-break sites** — D-305-TESTBREAK-01:
    - `:78` + `:94`: `sdgnrs.resolveRedemptionPeriod(100, currentDay);` → `sdgnrs.resolveRedemptionPeriod(100, currentDay, currentDay);` (recommended per `305-01-PLAN.md` Mutation 13 option (b) — preserves gas-benchmark intent by resolving same-wall-day pool).
    - `:113`: `sdgnrs.claimRedemption();` → `sdgnrs.claimRedemption(currentDay);` (matches the resolved-day from `:94`).
    - `:127`: `bool pending = sdgnrs.hasPendingRedemptions();` → `bool pending = sdgnrs.hasPendingRedemptions(currentDay);` (capture `uint32 currentDay = game.currentDayView();` at top of `test_gas_hasPendingRedemptions_true` before the burn at `:123`).
    - `:134`: `bool pending = sdgnrs.hasPendingRedemptions();` → `bool pending = sdgnrs.hasPendingRedemptions(game.currentDayView());` (view test, no burn).
14. **Mutation 14 — FIX `test/fuzz/CoverageGap222.t.sol` selector strings** — D-305-TESTBREAK-01:
    - `:948`: `"resolveRedemptionPeriod(uint16,uint32)",` → `"resolveRedemptionPeriod(uint16,uint32,uint32)",`. Args at `:951-952` get a third `uint32(0)`.
    - `:955`: `abi.encodeWithSignature("claimRedemption()")` → `abi.encodeWithSignature("claimRedemption(uint32)", uint32(0))`.
    - Assertion texts at `:973` + `:974` BYTE-IDENTICAL (preserved per `305-CONTEXT.md <domain>` lock).

**Total: 14 mutations across 5 files** — `contracts/StakedDegenerusStonk.sol` (10), `contracts/modules/DegenerusGameAdvanceModule.sol` (1, 3 sites), `contracts/interfaces/IStakedDegenerusStonk.sol` (1, 2 lines), `test/fuzz/RedemptionGas.t.sol` (1, 5 sites), `test/fuzz/CoverageGap222.t.sol` (1, 2 sites). Task 2 lands these in a single atomic USER-APPROVED commit per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md` + `feedback_wait_for_approval.md`.
