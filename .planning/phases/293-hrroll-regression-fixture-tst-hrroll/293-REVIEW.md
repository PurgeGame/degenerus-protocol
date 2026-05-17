---
phase: 293-hrroll-regression-fixture-tst-hrroll
reviewed: 2026-05-17T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - test/helpers/rollHeroSymbolRef.mjs
  - test/edge/HeroOverrideWeightedRoll.test.js
findings:
  critical: 0
  warning: 4
  info: 6
  total: 10
status: issues_found
---

# Phase 293: Code Review Report

**Reviewed:** 2026-05-17
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Test-only phase shipping (a) a 189-line ES-module JS-replay oracle that
bit-mirrors `_rollHeroSymbol`, and (b) a 1499-line regression fixture
covering TST-HRROLL-01..06 plus a 16-iter cross-attestation. The two
files together drive the v42 HRROLL `_rollHeroSymbol` ALGORITHM_VERIFIED
evidence under D-293-INVOKE-01.

**No Critical (blocker) findings.** The oracle's bit-mirror of
`_rollHeroSymbol` is correctly implemented (uint64 mask on `total` and
`cumulative`, uint32 mask on per-slot amount, `BigInt(maxAmount) >> 1n`
for the leaderBonus integer divide, `abi.encode(uint256, uint32)`
matching the Solidity 64-byte keccak input, strict-`>` first-seen leader
tie-break, leader-bonus add at `idx == leaderIdx`).

**4 Warnings** worth fixing before this fixture is treated as a stable
regression anchor:

- **WR-01 (correctness drift hazard):** `packDailyHeroWagers` comment
  says "saturate at uint32 max" but the code **truncates** via
  `& U32_MASK` while the Solidity contract at
  `DegenerusGameDegeneretteModule.sol:495` does explicit saturation
  (`if (updated > 0xFFFFFFFF) updated = 0xFFFFFFFF`). Latent today (all
  callsites pass values ≤ 10000) but the comment-vs-behavior mismatch
  will mislead the next contributor and cause silent JS-vs-Solidity
  divergence the moment any test seeds a raw value > 4_294_967_295.
- **WR-02 (statistical weakness in cross-attestation):** The
  TST-HRROLL cross-attestation reads the byte at the oracle's
  *predicted* `winQuadrant` and compares only the symbol bits — but
  if the contract chose a DIFFERENT `heroQuadrant`, that byte position
  carries a `getRandomTraits` random symbol with a ~1/8 probability of
  coincidentally matching `oracleOut.winSymbol`, yielding a
  false-positive cross-attestation pass. The describe-block comment
  correctly notes this is NOT the load-bearing distributional
  verification (chi² handles that at N=10000), but the structural
  attestation should still be strengthened to either (a) read the
  contract's actual `heroQuadrant` and compare BOTH quadrant and
  symbol, or (b) assert that ONLY the byte at
  `oracleOut.winQuadrant` carries `oracleOut.winSymbol` (and that no
  other byte position has the same symbol at the same position by
  coincidence). With N_CROSS=16 the joint false-positive rate per
  individual oracle/contract `heroQuadrant` disagreement is ~12.5%,
  which is loud but not airtight.
- **WR-03 (empty catch hides race-condition bugs):** `pinDailyEntropy`
  at lines 378–382 catches and silently swallows any
  `mockVRF.fulfillRandomWords` failure with the comment "Tolerate race
  where advanceGame already fulfilled in-line." This is exactly the
  empty-catch antipattern: a legitimate "request already fulfilled"
  race shares the catch-all branch with any unrelated revert
  (mockVRF misconfiguration, requestId stale, signer auth failure),
  which would silently leave `rngWordByDay[D]` unset and produce
  confusing downstream failures.
- **WR-04 (empty catch hides advanceGame revert reasons):**
  `measureAdvanceGameGas` (line 1121-1126) and the cross-attestation
  drain loop (line 1351-1354) silently `break` on ANY advanceGame
  throw, not just the expected "NotTimeYet". An unexpected revert
  (state-machine bug, gas exhaustion, AccessControl regression) would
  silently terminate the drain loop and surface as a misleading "drain
  never reached _emitDailyWinningTraits" error.

**6 Info-tier** findings cover unused imports, dead defensive guards
flagged in the helper file's own header comment, hardcoded storage
offsets that bypass the dynamic forge-inspect path, and minor maint
nits.

## Warnings

### WR-01: `packDailyHeroWagers` truncates but comment says "saturate"

**File:** `test/helpers/rollHeroSymbolRef.mjs:175`
**Issue:** The line `const capped = BigInt(raw) & U32_MASK; // saturate at uint32 max` performs **truncation** (modular reduction), not saturation. For `raw = 0x1_0000_0000`, `& U32_MASK` returns `0`, not `0xFFFFFFFF`. The Solidity contract at `DegenerusGameDegeneretteModule.sol:495` does explicit clamping (`if (updated > 0xFFFFFFFF) updated = 0xFFFFFFFF`), so the comment is materially wrong about both this helper and the Solidity behavior it claims to mirror. Today all callsites pass values ≤ 10000 so the bug is latent, but the next contributor seeding a stress-test raw value > uint32 max will get silent JS-vs-Solidity divergence and a confusing oracle mismatch.

**Fix:**
```javascript
// In rollHeroSymbolRef.mjs:175
const rawBn = BigInt(raw);
const capped = rawBn > U32_MASK ? U32_MASK : rawBn; // saturate (matches DegenerusGameDegeneretteModule.sol:495)
```
Or, if truncation is actually the desired semantic (e.g., to keep the helper a pure bit-mirror with the burden of saturation pushed to the caller), then rewrite the comment to say "truncate to uint32 — callers MUST pre-saturate inputs >= 2^32 per the on-chain `placeDegeneretteBet` clamp" and add a runtime check that throws if `raw > 0xFFFFFFFF`.

---

### WR-02: Cross-attestation has ~1/8 false-positive probability per oracle/contract `heroQuadrant` disagreement

**File:** `test/edge/HeroOverrideWeightedRoll.test.js:1459-1486`
**Issue:** The cross-attestation reads `mainTraitsPacked` at the byte position chosen by the **oracle's** predicted `winQuadrant`, then asserts the symbol bits there equal `oracleOut.winSymbol`. If the on-chain `_rollHeroSymbol` actually picked a DIFFERENT `heroQuadrant` (say, the oracle and the contract have drifted), the override byte lands at the contract's `heroQuadrant`, NOT at `oracleOut.winQuadrant`. The byte at `oracleOut.winQuadrant` would then carry the `JackpotBucketLib.getRandomTraits(r)` random symbol — which has a 1/8 probability of coincidentally matching `oracleOut.winSymbol`. Across N_CROSS=16 iterations, if the oracle's bit-mirror were broken in a way that caused systematic `heroQuadrant` drift, the cross-attestation would pass with probability `(1/8)^16 ≈ 5.4e-15` if drift is systematic across ALL iterations, but per-iteration drift events have a 12.5% silent-pass rate. The describe-block comment correctly notes this is NOT load-bearing (chi² at N=10000 handles distributional verification), but the structural attestation can and should be strengthened cheaply.

**Fix:** Read the contract's actual hero output from the trait byte and assert BOTH quadrant and symbol match. The byte at any position `N` always has `quadrant_bits == N` by construction, so the only way to recover the contract's actual `heroQuadrant` is to (a) re-read the rng word and replay the override path on-chain, or (b) check the inverse invariant: ONLY the byte at `oracleOut.winQuadrant` should carry `oracleOut.winSymbol`. Option (b) is the cleaner structural assertion:

```javascript
// After parsing mainTraitsPacked and computing oracleOut
let matchingBytePositions = 0;
for (let q = 0; q < 4; ++q) {
  const decoded = unpackHeroFromTraitsPacked(mainTraitsPacked, q);
  if (decoded.symbol === oracleOut.winSymbol) {
    matchingBytePositions++;
    // Optionally: assert this matching position == oracleOut.winQuadrant
    expect(q, `oracle predicted heroQuadrant=${oracleOut.winQuadrant} but on-chain symbol match landed at q=${q}`).to.equal(oracleOut.winQuadrant);
  }
}
// At minimum one byte matches (the override); rarely more if random getRandomTraits coincidentally produces the same symbol elsewhere.
expect(matchingBytePositions).to.be.gte(1);
```

This bounds the per-iteration false-positive rate from 12.5% down to the probability of `getRandomTraits` producing `oracleOut.winSymbol` at exactly `oracleOut.winQuadrant` (still ~1/8) AND nowhere else (~ (7/8)^3 ≈ 67%) — net ~8.4% — slightly better, but more importantly the assertion now explicitly probes the override's actual landing position rather than implicitly assuming it.

A stronger fix is to extend `_applyHeroOverride` to emit a separate `HeroOverrideRolled(uint8 quadrant, uint8 symbol)` debug event under a test-only compile flag, but that requires contract surgery and is out of scope for this test phase.

---

### WR-03: Empty catch in `pinDailyEntropy` silently swallows non-race errors

**File:** `test/edge/HeroOverrideWeightedRoll.test.js:378-382`
**Issue:**
```javascript
try {
  await mockVRF.fulfillRandomWords(requestId, word);
} catch {
  // Tolerate race where advanceGame already fulfilled in-line.
}
```
Catches any exception. A legitimate "request already fulfilled" race shares the branch with mockVRF auth/state misconfiguration, wrong requestId, signer rejection, or revert from a contract upgrade. The downstream failure mode is silent: `rngWordByDay[D]` stays unset, every subsequent test step proceeds with stale entropy, and the test fails much later with a misleading "advanceGame drain never reached _emitDailyWinningTraits" or "leader pick-rate mismatch" symptom.

**Fix:** Narrow the catch to the specific race condition by inspecting the error message or by pre-checking whether the request is still pending:
```javascript
try {
  await mockVRF.fulfillRandomWords(requestId, word);
} catch (err) {
  const msg = String(err?.message ?? err);
  // Race: advanceGame fulfilled the request in-line during the same block.
  // Any other failure is unexpected and should surface.
  if (!msg.includes("already fulfilled") && !msg.includes("RequestNotFound")) {
    throw new Error(`pinDailyEntropy: unexpected fulfillRandomWords failure: ${msg}`);
  }
}
```
(Adjust the matched substrings to the actual MockVRFCoordinator revert strings — verify against the mock contract or replace with an `instanceof CustomError` check if the mock emits typed errors.)

---

### WR-04: Empty catch in advanceGame drain loops silently terminates on any revert

**File:** `test/edge/HeroOverrideWeightedRoll.test.js:1121-1126, 1351-1354`
**Issue:** Both drain loops use `try { tx = await game.connect(deployer).advanceGame(); } catch { break; }`. A legitimate "NotTimeYet" / "AlreadyAdvanced" terminal state shares the catch with state-machine bugs, access-control regressions, gas-limit exhaustion, and any other revert. The terminal-state revert ends the drain *correctly*; an unexpected revert ends the drain *incorrectly* and produces the misleading "drain never reached _emitDailyWinningTraits" error message at line 1209 / 1386.

**Fix:** Inspect the revert reason and rethrow on unexpected failures:
```javascript
let tx;
try {
  tx = await game.connect(deployer).advanceGame();
} catch (err) {
  const msg = String(err?.message ?? err);
  // Expected terminal-state reverts that end the drain naturally:
  if (msg.includes("NotTimeYet") || msg.includes("AlreadyAdvanced") || msg.includes("StateMachineComplete")) {
    break;
  }
  // Any other revert is a real failure — surface it.
  throw new Error(`advanceGame drain at iter=${iter} reverted unexpectedly: ${msg}`);
}
```
(Verify the actual revert strings emitted by `_unlockRng` / `advanceGame` against the contract source; the example strings above are placeholders.)

---

## Info

### IN-01: Unused imports `eth` and `ZERO_ADDRESS`

**File:** `test/edge/HeroOverrideWeightedRoll.test.js:120, 124`
**Issue:** `eth` (line 120) and `ZERO_ADDRESS` (line 124) are imported from `../helpers/testUtils.js` but never referenced in the rest of the file. `placeEthBet` uses `hre.ethers.ZeroAddress` directly (line 361), and the cross-attestation also uses `hre.ethers.ZeroAddress` (lines 1055, 1283, 1086, 1318), bypassing the imported `ZERO_ADDRESS` constant. `eth` is unreferenced anywhere in the file.
**Fix:** Drop both from the import list:
```javascript
import {
  advanceToNextDay,
  getLastVRFRequestId,
  fulfillVRF,
  ZERO_BYTES32,
} from "../helpers/testUtils.js";
```

Also `fulfillVRF` is imported but not directly invoked (`mockVRF.fulfillRandomWords` is called directly via the mock contract). Verify whether `fulfillVRF` is intentionally imported for parity with sister fixtures or if it can also be dropped.

---

### IN-02: Dead defensive guard in TST-HRROLL-06 contradicts the helper file's own `feedback_no_dead_guards.md` carry-forward

**File:** `test/edge/HeroOverrideWeightedRoll.test.js:1189-1195`
**Issue:** The branch `if (worstResult.gasUsed === null || baselineResult.gasUsed === null) { ++invalidSamples; continue; }` is unreachable: `measureAdvanceGameGas` returns `gasUsed: null` **only** when `dailyWinningTraitsFired: false` (lines 1148-1149), and the immediately-preceding `expect(...dailyWinningTraitsFired).to.equal(true)` assertions (lines 1180-1187) would throw before this branch is reached. The inline comment ("Defensive guard — should be unreachable") explicitly acknowledges this. The `rollHeroSymbolRef.mjs` header itself cites `feedback_no_dead_guards.md` at line 68 as the project's stance against dead branches. This is test code, not a frozen contract, so the cost is style only — but consistency with the helper's stated stance argues for deletion.

**Fix:** Drop the `invalidSamples` counter and the dead branch entirely; the assertion already guarantees both `gasUsed` values are non-null:
```javascript
const delta = worstResult.gasUsed - baselineResult.gasUsed;
samples.push({
  gasWorst: worstResult.gasUsed,
  gasBaseline: baselineResult.gasUsed,
  delta,
});
```
And drop the corresponding `invalidSamples` mention from the throw at line 1209.

---

### IN-03: Hardcoded slot-0 offset for `dailyIdx` bypasses the dynamic forge-inspect pattern

**File:** `test/edge/HeroOverrideWeightedRoll.test.js:198-200, 325-330`
**Issue:** `deriveDailyHeroWagersBaseSlot` dynamically discovers the storage slot for `dailyHeroWagers` via `forge inspect`, defending against storage-layout drift. But `readDailyIdx` hardcodes slot 0 and a 32-bit offset for `dailyIdx` (`SLOT0_TIMING_FSM = "0x...0"`, `DAILY_IDX_BIT_SHIFT = 32n`). If `DegenerusGameStorage.sol` ever introduces a new packed field before `dailyIdx`, the hardcoded offset breaks silently with arbitrary day values. This is asymmetric defense.

**Fix:** Either derive the `dailyIdx` offset from `forge inspect` similarly, or document the rationale for the asymmetry (e.g., "slot-0 packing is locked under D-288-FIX-SHAPE-01 single-writer invariant; layout drift here would be caught by Phase 288 fixtures") with an explicit cite.

---

### IN-04: `forge inspect` parser brittle to foundry version drift

**File:** `test/edge/HeroOverrideWeightedRoll.test.js:245-288`
**Issue:** `deriveDailyHeroWagersBaseSlot` parses `forge inspect storageLayout` output by splitting on `|` and matching `dailyHeroWagers` against the first cell. Future foundry versions may emit JSON output by default, change the column ordering, or drop the human-readable table format — silently producing `null` slot and triggering the "failed to parse" throw. Consider using `forge inspect --json` and parsing the structured `storage[]` array instead, which is far more stable across foundry versions.

**Fix:**
```javascript
const forgeOut = execSync(
  "FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge inspect contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage storageLayout --json 2>/dev/null"
).toString();
const layout = JSON.parse(forgeOut);
const entry = layout.storage.find((s) => s.label === "dailyHeroWagers");
if (!entry) throw new Error("dailyHeroWagers not found in storageLayout");
return BigInt(entry.slot);
```
Verify `forge inspect storageLayout --json` is stable across the project's pinned foundry version.

---

### IN-05: Redundant defensive type-check on `baseSlot >= 0n`

**File:** `test/edge/HeroOverrideWeightedRoll.test.js:440`
**Issue:** `deriveDailyHeroWagersBaseSlot` already throws if the parsed slot is negative (lines 282-286). The setup test then re-asserts `expect(baseSlot >= 0n).to.equal(true)`, which is unreachable: the helper would have thrown first. Style-only — adds noise without test value.

**Fix:** Drop the redundant assertion; keep the `typeof baseSlot === "bigint"` check (which IS load-bearing — confirms the helper's return type contract).

---

### IN-06: `MAX_DRAIN_ITERS = 30` magic number duplicated across two functions

**File:** `test/edge/HeroOverrideWeightedRoll.test.js:1102, 1337`
**Issue:** Both `measureAdvanceGameGas` and the cross-attestation drain loop define `const MAX_DRAIN_ITERS = 30;` inline. If one is tuned (e.g., raised to 50 to accommodate slower fixtures), the other drifts. Promote to a module-level constant alongside `N_CHI2`, `N_EDGE`, `N_GAS_SAMPLES`, `N_CROSS`.

**Fix:**
```javascript
// Module-level
const MAX_DRAIN_ITERS = 30; // advanceGame drain budget per measurement / cross-attestation sample
```
Remove the inline declarations at lines 1102 and 1337.

---

## Notes Outside Findings

**Sound design choices observed:**

- The JS oracle's keccak input layout (`abi.encode(uint256 entropy, uint32 day)` packed to two 32-byte words = 64 bytes) correctly matches the Solidity `abi.encode` byte layout. Verified against the documented anchor at Phase 282 W2.
- `BigInt(maxAmount) >> 1n` for `leaderBonus` is exactly the Solidity `uint64(maxAmount) / 2` semantic (non-negative integer right-shift, no floating-point coercion).
- The U64_MASK / U32_MASK / U256_MASK pattern correctly mirrors all Solidity overflow boundaries the algorithm crosses; no observable drift on any in-spec test input.
- The TST-HRROLL-02 LOCKED seed `[500, 200, 200, 100]` algebra is correct: `(L + L/2) / (T + L/2) = 0.60` requires `L = T/2`, satisfied uniquely up to permutation. The seed comment correctly documents why the ROADMAP example `[500, 100, 100, 100]` is algebraically inconsistent with the 0.60 target.
- N=10000 sample size for chi² df=3 yields minimum expected bucket count 833, well above the chi²-approximation validity threshold (E ≥ 5).
- Deterministic entropy construction (function of iteration counter `i` only) yields reproducible test runs.
- The `feedback_no_history_in_comments.md` carry-forward is respected throughout: comments describe what the code IS, not what it used to be. The "v42 mechanic" framing instead of "what changed from v41" is the project pattern.

---

_Reviewed: 2026-05-17_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
