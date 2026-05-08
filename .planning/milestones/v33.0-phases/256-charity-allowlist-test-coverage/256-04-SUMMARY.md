---
phase: 256-charity-allowlist-test-coverage
plan: 04
subsystem: testing
tags: [hardhat, integration, charity-allowlist, gnrus, sdgnrs, dgnrs, conservation, soulbound, v33, tst-05]

# Dependency graph
requires:
  - phase: 254-gnrus-allowlist-storage-admin-op-storage-repack
    provides: v33 GNRUS storage skeleton + setCharity (instant-apply branch on empty slot 5)
  - phase: 255-vote-rewrite-resolve-flush-event-error-cleanup
    provides: v33 vote(uint8 slot) + pickCharity(uint24 level) + LevelResolved event (slot/recipient/gnrusDistributed args)
  - phase: 256
    plan: 01
    provides: POOL_REWARD constant (used inline in conservation it-block per executor discretion — opted to keep impersonation inline rather than import to keep this file's import block minimal)
provides:
  - Integration-level v33 conservation evidence (TST-05) driven via REAL game flow at DegenerusGameAdvanceModule.sol:1634 — Phase 257 AUDIT-03 grep-citation target
  - v33 slate-empty rewrite of the stale "no proposals exist" skip-path-A it-block
  - LevelResolved event-arg verification (slot=5, recipient=dan.address) from real game flow (not impersonate-and-call) — proves the IGNRUSResolve wire (DegenerusGameAdvanceModule.sol:31-34) is alive at HEAD
affects:
  - Phase 257 AUDIT-03 (conservation re-proof) — cites this it-block as integration-side evidence
  - Phase 257 AUDIT-02 (adversarial sweep) — cross-references soulbound smoke (transfer / transferFrom / approve all revert TransferDisabled post-transition)

# Tech tracking
tech-stack:
  added: []
  patterns:
    - blockTag-pinned supply snapshots ({ blockTag: resolvedBlock - 1 } / { blockTag: resolvedBlock }) — isolates the pickCharity tx from sibling ticket-processing txs that may mint sDGNRS rewards
    - tx-receipt-collecting VRF driver variant (driveVRFCycleCapturing) — extends the existing driveVRFCycle helper to return all advanceGame tx receipts so callers can extract LevelResolved and pin block boundaries

key-files:
  created: []
  modified:
    - test/integration/CharityGameHooks.test.js

key-decisions:
  - "Snapshot supplies via blockTag pinning at resolvedBlock - 1 / resolvedBlock — NOT pre-fill snapshots. Pre-fill snapshots fail because (a) the level transition actually fires during day 1's VRF cycle (not day 2), AND (b) ticket processing during day 1 mints sDGNRS rewards to buyers, so a pre-fill sdgnrs.totalSupply snapshot would not equal the post-transition value even with a supply-preserving pickCharity."
  - "Add a tx-capturing variant of driveVRFCycle (driveVRFCycleCapturing) rather than rewrite the existing helper. The existing helper is consumed by the other 5 it-blocks and changing its return shape would cascade. The variant duplicates 11 lines for additive event-extraction capability — accepted per Rule 2 (correctness requirement: TST-05 needs the LevelResolved event tx to derive blockTag boundaries)."
  - "Inline the impersonate-and-fund-alice block rather than import from charityFixture.js. The integration file uses deployFullProtocol directly (not deployGNRUSFixture), so it owns its own setup. Importing four helpers (impersonate / stopImpersonating / giveSDGNRS / POOL_REWARD) for a single one-shot block adds an import edge for marginal gain. Per the plan's executor-discretion clause."
  - "Keep the existing skip-path-A test's polling loop (L191) — only the describe wording is rewritten to v33 slate-empty shape. The polling loop is part of the existing test's event-capture mechanism for LevelSkipped; rewriting it to a deterministic shape is out of scope for this plan (Plan 04 only adds the conservation it-block + rewrites describe wording)."

patterns-established:
  - "blockTag-pinned conservation assertions for multi-tx VRF drivers — captures the exact block boundaries around pickCharity, isolating its supply effects from sibling ticket-processing txs."
  - "Driver-variant pattern (driveVRFCycle vs driveVRFCycleCapturing) — additive helper rather than mutating the existing one, avoids cascade-rewriting consumers."
  - "Per feedback_no_history_in_comments.md, the rewritten skip-path-A describe wording carries no v32 migration prose (no `// was:` annotation, no `// migrated from v32 propose flow` note)."

requirements-completed:
  - TST-05  # Conservation across level transition — see traceability table in REQUIREMENTS.md

# Metrics
duration: ~25 min
completed: 2026-05-06
---

# Phase 256 Plan 04: CharityGameHooks Integration Conservation + Slate-Empty Rewrite Summary

**Extended `test/integration/CharityGameHooks.test.js` with the TST-05 conservation it-block driven via the REAL game flow at DegenerusGameAdvanceModule.sol:1634 (NOT impersonate-and-call), and rewrote the stale `LevelSkipped(0) when no proposals exist for level 0` it-block to v33 slate-empty wording.**

## What Changed

### Edit A — Stale skip-path-A rewrite

- **Before:** `it("emits LevelSkipped(0) when no proposals exist for level 0", ...)` (L149 in pre-edit file)
- **After:** `it("emits LevelSkipped(0) when no active slots in slate (skip-path A)", ...)` (L169 in post-edit file)
- Body assertions unchanged (`expect(events[0].args.level).to.equal(0)` still holds for `LevelSkipped(0)`)
- Inline comment added: `// No setCharity() calls before transition -> currentActiveBitmap == 0 -> skip-path A.`
- Per `feedback_no_history_in_comments.md`: NO `// was:` annotation, NO `// migrated from v32 propose flow` trace.

### Edit B — TST-05 conservation it-block (added inside `pickCharity fires at level transition` describe)

- **Setup:** vault owner (deployer) calls `setCharity(5, dan.address)` (instant-apply branch since slot 5 is empty); alice is funded with 100 sDGNRS via game-impersonated `transferFromPool(POOL_REWARD=3, ...)`; alice votes for slot 5 (vote weight = 100, ensures winner-loop selects slot 5 instead of falling through skip-path B).
- **Driver:** the deterministic shape from `charity.currentLevel increments from 0 to 1` it-block at L116-147 (Warning #6 resolution: NO 200-iteration polling loop in the conservation it-block itself):
  - `fillPrizePoolForLevelTransition(game, buyers)` — 10 buyers × ~7.5 ETH = ~75 ETH purchases
  - `advanceToNextDay()` then `driveVRFCycleCapturing(game, deployer, mockVRF)` — returns every advanceGame tx receipt
  - Iterate captured txs to find the one that emitted `LevelResolved` (the pickCharity tx)
- **Event assertions** (proves the IGNRUSResolve wire is alive at HEAD):
  - `resolvedEvent.args.level === 0`
  - `resolvedEvent.args.slot === 5` (matches the pre-populated slot)
  - `resolvedEvent.args.recipient === dan.address` (matches the setCharity recipient)
  - `expectedDist === resolvedEvent.args.gnrusDistributed`
- **Balance-delta assertions** via blockTag pinning (`{ blockTag: resolvedBlock - 1 }` / `{ blockTag: resolvedBlock }`):
  - `dan.balance += expectedDist` (= 2% of unallocated)
  - `gnrus.balance -= expectedDist`
- **Supply-invariant assertions** (pickCharity touches only GNRUS balances, never sDGNRS / DGNRS supplies):
  - `gnrus.totalSupply()` unchanged
  - `sdgnrs.totalSupply()` unchanged
  - `sdgnrs.votingSupply()` unchanged
  - `dgnrs.totalSupply()` unchanged
- **Day 2 sanity drive:** `advanceToNextDay() + driveVRFCycle()` to mirror the existing test's deterministic shape; confirms `charity.currentLevel == 1` and `charity.levelResolved(0) == true` after the full cycle (proves no second pickCharity fired).
- **Soulbound smoke** (3 asserts post-transition):
  - `charity.connect(dan).transfer(eve, 1 ether)` reverts `TransferDisabled`
  - `charity.connect(dan).transferFrom(eve, alice, 1 ether)` reverts `TransferDisabled`
  - `charity.connect(dan).approve(eve, 1 ether)` reverts `TransferDisabled`

### New helper

- `driveVRFCycleCapturing(game, deployer, mockVRF)` — returns every `advanceGame` tx receipt. Structurally identical to the existing `driveVRFCycle` (same polling-loop shape) but accumulates `txs.push(...)` so callers can extract events and pin block boundaries. Used only by the conservation it-block. The existing `driveVRFCycle` is unchanged so the other 5 it-blocks remain untouched.

## File Metrics

| Metric | Before | After | Delta |
|--------|--------|-------|-------|
| Total lines | 252 | 400 | +148 |
| `describe` blocks | 3 | 3 | 0 (top-level + pickCharity-fires + burnAtGameOver-fires) |
| `it` blocks | 5 | 6 | +1 (conservation) |
| `it` blocks in `pickCharity fires at level transition` describe | 2 | 3 | +1 |
| `it` blocks in `burnAtGameOver fires during gameover drain` describe | 3 | 3 | 0 |
| `for (let i = 0; i < 200` polling loops | 2 (driveVRFCycle helper + skip-path-A inline) | 3 (added driveVRFCycleCapturing helper variant) | +1 (helper, NOT in conservation it-block — see Warning #6 note below) |

## Test Run Output

```
CharityGameHooks
  pickCharity fires at level transition
    ✔ charity.currentLevel increments from 0 to 1 after first level transition (18414ms)
    ✔ emits LevelSkipped(0) when no active slots in slate (skip-path A) (1672ms)
    ✔ conservation: 2% distribution preserves totalSupplies and soulbound enforcement (TST-05) (1855ms)
  burnAtGameOver fires during gameover drain
    ✔ charity.finalized becomes true after game over
    ✔ unallocated GNRUS is burned at gameover
    ✔ emits GameOverFinalized event

6 passing (22s)
```

Full suite: 1213 passing, 9 pending, 64 failing (all 64 failures are pre-existing — verified by stash-and-run with no work-in-progress; failures are concentrated in `test/integration/VRFIntegration*.test.js` and other suites not touched by Plan 04). Integration sub-suite: 54 passing, 2 failing — the 2 are in `VRFIntegration` (pre-existing, unrelated to charity).

## Key Verification Values

- **Initial GNRUS supply (constructor):** `1e30` wei = 1,000,000,000,000 GNRUS (1T tokens × 1e18 decimals)
- **`gnrusUnallocBefore` at blockTag(resolvedBlock - 1):** `1e30` wei (pre-transition state — full unallocated pool intact)
- **`expectedDist = (gnrusUnallocBefore * 200n) / 10_000n`:** `2e28` wei = 20,000,000,000 GNRUS (2% of 1T)
- **`resolvedEvent.args.gnrusDistributed`:** `2e28` wei (matches `expectedDist` — assertion passes)
- **`dan.balanceOf` post-transition:** `2e28` wei (= `0 + expectedDist`, since dan's pre-transition GNRUS balance was 0)
- **`gnrus.balanceOf(charityAddr)` post-transition:** `9.8e29` wei (= `1e30 - 2e28`)

## Wire Verification (DegenerusGameAdvanceModule.sol:1634)

The `LevelResolved` event was captured from a tx returned by `driveVRFCycleCapturing` — the tx came from `game.connect(deployer).advanceGame()`, NOT from a direct `charity.connect(gameSigner).pickCharity(level)` call. This proves the `IGNRUSResolve` wire defined at `contracts/modules/DegenerusGameAdvanceModule.sol:31-34` and exercised at `contracts/modules/DegenerusGameAdvanceModule.sol:1634` (`charityResolve.pickCharity(lvl - 1);`) is alive at v33 HEAD. Phase 257 AUDIT-03 conservation re-proof can grep-cite this test for integration-side evidence without re-deriving wire correctness.

## Warning #6 Resolution (Deterministic Driver, Not Polling Loop)

The conservation it-block itself contains **zero** `for (let i = 0; i < 200; i++)` polling loops. The driver pattern mirrors the existing `charity.currentLevel increments from 0 to 1` it-block at L116-147 verbatim:

```js
const buyers = [alice, bob, carol, dan, eve, ...others.slice(0, 5)];
await fillPrizePoolForLevelTransition(game, buyers);
await advanceToNextDay();
const day1Txs = await driveVRFCycleCapturing(game, deployer, mockVRF);
// ... extract LevelResolved from day1Txs ...
await advanceToNextDay();
await driveVRFCycle(game, deployer, mockVRF);
```

The total polling-loop count in the file rose from 2 to 3 because the new `driveVRFCycleCapturing` HELPER contains a polling loop (same shape as the existing `driveVRFCycle` HELPER). The plan's prose explicitly endorses adding a tx-capturing variant when event-extraction is needed:

> "If the existing `driveVRFCycle` helper does not return a tx receipt suitable for event extraction, capture the events by re-executing the same level-transition path with `await game.connect(deployer).advanceGame()` calls and tx-by-tx event collection — but reuse the deterministic shape (no polling loop). Fall back to the existing test's idiom verbatim if event capture is awkward."

The "no polling loop" stricture applies to the conservation it-block, which has none. The helper variant is a re-use of the existing helper's polling shape with additive tx collection.

## Why blockTag Pinning (Not Pre-Fill Snapshots)

The plan's source pattern (PATTERNS.md L356-378) used pre-fill snapshots:

```js
// Suggested in PATTERNS.md:
const gnrusUnallocBefore = await charity.balanceOf(charityAddr);  // BEFORE setCharity
// ... drive level transition ...
expect(await charity.balanceOf(dan.address)).to.equal(expectedDist);
```

This pattern would have failed for two reasons:

1. **The level transition fires during DAY 1, not DAY 2.** Empirically verified by debug instrumentation: `charity.currentLevel == 1` and `charity.levelResolved(0) == true` AFTER the first `driveVRFCycle`, before the second. The plan's prose ("Day 2 second VRF cycle triggers the level transition") was inaccurate; the existing `currentLevel increments from 0 to 1` test only asserts post-cycle state, not which cycle fires the transition.
2. **Purchases mint sDGNRS rewards.** A pre-fill `sdgnrs.totalSupply` snapshot would not equal the post-transition value, even with a supply-preserving `pickCharity`.

blockTag pinning isolates the pickCharity tx from all sibling ticket-processing txs. Both `before` and `after` snapshots are read at the chain's actual block boundaries around the pickCharity call — providing rigorous deterministic conservation evidence.

## Confirmation: BURNIE Per-Pool Accounting Intentionally NOT Asserted

Per CONTEXT.md `<specifics>` "Conservation across level transition (integration)" → "BURNIE per-pool accounting unchanged" — covered by Phase 257 AUDIT-03 grep-cited proof, not by Phase 256 test. The Phase 256 conservation it-block scope is GNRUS + sDGNRS (totalSupply + votingSupply) + DGNRS supplies + soulbound smoke. BURNIE / coinflip per-pool accounting is out of scope for this it-block.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Pre-fill snapshot pattern produces incorrect baselines**
- **Found during:** Task 1 (initial implementation, debug-print iteration)
- **Issue:** The plan's suggested pre-fill snapshot of `gnrusUnallocBefore = await charity.balanceOf(charityAddr)` at the top of the it-block — followed by `expect(await charity.balanceOf(dan.address)).to.equal(danBalanceBefore + expectedDist)` post-transition — failed: actual `2e28` vs. expected `3.96e28`. Root cause: the level transition fires during day 1's VRF cycle (not day 2), so by the time the second `driveVRFCycle` returns, pickCharity has already run, dan already holds 2e28, and the GNRUS contract balance is 9.8e29 (not 1e30). A pre-fill snapshot of 1e30 → expectedDist = 2e28 would have worked for dan's balance assertion, BUT the snapshot was taken AFTER `setCharity(slot, dan.address)` in the source pattern — and setCharity does not move GNRUS balances, so 1e30 was preserved. Actually the snapshot was taken AFTER day 1 cycle in the initial implementation (because supply invariants needed a post-day-1-mint snapshot to isolate purchase-induced sDGNRS minting from pickCharity), at which point `gnrusUnallocBefore = 9.8e29` and `expectedDist = 1.96e28` — but `dan.balanceOf` is also already `2e28`, so `expect(2e28).to.equal(0 + 1.96e28)` fails.
- **Fix:** Replaced the pre-fill snapshot pattern with **blockTag pinning** around the LevelResolved tx (`{ blockTag: resolvedBlock - 1 }` / `{ blockTag: resolvedBlock }`). Captured the LevelResolved tx via a new tx-receipt-collecting variant of `driveVRFCycle` (`driveVRFCycleCapturing`). This isolates the pickCharity tx from sibling ticket-processing txs deterministically.
- **Files modified:** `test/integration/CharityGameHooks.test.js` (added `driveVRFCycleCapturing` helper + replaced snapshot block with blockTag-pinned reads).
- **Commit:** Not yet committed — awaits user approval per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`.

**2. [Rule 2 - Auto-add missing critical functionality] LevelResolved event-arg verification (slot/recipient)**
- **Found during:** Task 1 (verification design)
- **Issue:** Plan's verification list mentions "LevelResolved event capture asserts args.slot == 5 and args.recipient matches the address pre-populated via setCharity" but the plan's source it-block (PATTERNS.md L346-385) only asserts balance deltas, not LevelResolved args. The wire-verification narrative requires asserting that the LevelResolved event came from the real game flow with the correct args.
- **Fix:** Added explicit `expect(resolvedEvent.args.slot).to.equal(slot)` + `expect(resolvedEvent.args.recipient).to.equal(dan.address)` + `expect(resolvedEvent.args.level).to.equal(0)` + `expect(expectedDist).to.equal(resolvedEvent.args.gnrusDistributed)` assertions. This locks the wire-verification narrative explicitly and makes the test fail loudly if the IGNRUSResolve wire is rerouted or the event signature changes.
- **Files modified:** `test/integration/CharityGameHooks.test.js`.
- **Commit:** Not yet committed — same approval gate.

**No architectural changes (Rule 4).** No contract changes. No new dependencies. No deferred items.

## Self-Check: PASSED

- ✓ `test/integration/CharityGameHooks.test.js` exists at the expected path (`/home/zak/Dev/PurgeGame/degenerus-audit/test/integration/CharityGameHooks.test.js`)
- ✓ All 6 it-blocks pass (`npx hardhat test test/integration/CharityGameHooks.test.js` exits 0)
- ✓ No `git add` / `git commit` performed (per CRITICAL OVERRIDE in executor prompt + `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md`)
- ✓ SUMMARY.md not committed (per `.planning/` gitignore at `.gitignore:15` per executor prompt)
- ✓ All acceptance criteria verified by grep (describe count = 3, it count = 6, no `no proposals exist` matches, conservation label present, all 4 supply invariants asserted, 3 TransferDisabled asserts, setCharity slot=dan present, no history-in-comments)
