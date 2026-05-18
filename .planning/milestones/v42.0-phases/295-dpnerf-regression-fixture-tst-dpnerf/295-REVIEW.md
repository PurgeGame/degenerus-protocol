---
phase: 295-dpnerf-regression-fixture-tst-dpnerf
reviewed: 2026-05-18T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - test/helpers/randTraitTicketRef.mjs
  - test/edge/DeityPassGoldNerfRegression.test.js
findings:
  critical: 0
  warning: 4
  info: 7
  total: 11
status: issues_found
---

# Phase 295: Code Review Report

**Reviewed:** 2026-05-18
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Test-only phase shipping (a) a 311-line ES-module JS-replay oracle that
bit-mirrors `_randTraitTicket` (ETH-path 25-winner draw, L1707-L1763) and
the per-pull body of `_awardDailyCoinToTraitWinners` (BURNIE inline-duplicate
gold-tier block, L1860-L1894); and (b) a 1339-line regression fixture
covering TST-DPNERF-01..05 plus a 16-iter "cross-attestation". The two
files together drive the v42 DPNERF gold-tier flat-1 `virtualCount` nerf
under D-295-INVOKE-01 ALGORITHM_VERIFIED disposition.

**No Critical (blocker) findings.** The bit-mirror is correctly
constructed at the algorithmic level:

- keccak input layout uses `abi.encode` (NOT `abi.encodePacked`) and the
  ABI type list `[uint256, uint8, uint8, uint8]` (ETH) /
  `[uint256, uint8, uint24, uint256]` (BURNIE) is byte-equivalent to the
  Solidity `abi.encode(randomWord, trait, salt, i)` /
  `abi.encode(randomWord, trait_i, lvlPrime, i)` calls at L1750 and L1884.
  Note: the contract's loop counter `i` is `uint256` while the ETH helper
  encodes it as `uint8`; since `abi.encode` left-pads ALL elementary
  values to 32 bytes regardless of declared bit-width, the encoded
  keccak input bytes are bitwise identical for any `i` in `uint8` range
  (which `numWinners <= 255` guarantees). Verified non-bug.
- `goldTierVirtualCount` correctly mirrors the L1726-L1738 (ETH) /
  L1863-L1874 (BURNIE) branch shape: `fullSymId = (trait>>6)*8 + (trait&7)`,
  `if (((trait>>3)&7)==7) virtualCount=1; else virtualCount=max(len/50, 2)`,
  and the deity-`address(0)` outer guard at L1731 / L1867 is honored.
- The `DEITY_SENTINEL_TICKET_IDX = type(uint256).max` marker matches
  L1757 / L1893 verbatim, and the `if (idx < len) ... else { sentinel }`
  branch is correctly reproduced.
- Storage-slot derivation for `traitBurnTicket[lvl][trait]` (slot 8,
  `mapping(uint24 => address[][256])`) and `deityBySymbol[fullSymId]`
  (slot 30, `mapping(uint8 => address)`) is mathematically correct
  Solidity layout.

**4 Warnings** worth fixing before this fixture is treated as a stable
regression anchor:

- **WR-01 (oversold attestation):** TST-DPNERF-04 cross-attestation
  docstring + `console.log` ("ALGORITHM_VERIFIED established", "JS↔EVM
  bit-identity", "production cross-attestation iterations") claim a
  JS-vs-EVM equivalence test, but the actual code only calls
  `randTraitTicketRef(...)` twice with identical inputs and asserts
  determinism against itself. No EVM execution of `_randTraitTicket`
  ever occurs (it remains `private view` per D-295-INVOKE-01 — visibility
  flip not invoked). The only EVM touch is `seedTraitBucket` +
  `readTraitBucket` round-trip, which proves storage seeding works, not
  algorithmic equivalence. Downstream consumers reading the PASS log may
  conclude D-295-INVOKE-01 ALGORITHM_VERIFIED is empirically verified
  against EVM execution; it is not.
- **WR-02 (`isDeityPresent` shape-fragility):** The helper at
  `randTraitTicketRef.mjs:74-78` sentinels `address(0)` by comparing the
  lowercased deity string against two literal forms (`ZERO_ADDRESS`
  full-length and `"0x0"`) and treats EVERYTHING ELSE as "deity present".
  Any non-canonical zero-shape input — `""`, `"0x"`, `"0x00"`,
  `"0x000000"`, the canonical-but-uppercase `"0X0000...0"` (covered),
  `"0"` (no `0x` prefix), or a 19-byte address that happens to be all
  zeros padded to 20 — would be treated as non-zero by the helper but as
  `address(0)` by Solidity, inverting `virtualCount` semantics. Today
  all callsites pass either `hre.ethers.getAddress(...)` (canonical
  checksummed mixed-case, length 42) or `ZERO_ADDRESS` (canonical
  all-zero lowercase, length 42) so the bug is latent — but it is a
  one-line trip-hazard for any future caller that constructs a deity
  string through an unconventional path.
- **WR-03 (chi² approximation validity weak on BURNIE EV test):** The
  BURNIE-half EV test (TST-DPNERF-04, line 1023-1042) uses
  `expectedSentinel = 250 / 51 ≈ 4.9` for the chi² goodness-of-fit
  computation. The standard chi²-approximation validity rule of thumb
  requires expected counts in EVERY cell to be ≥ 5; the BURNIE-half
  narrowly fails this threshold. With observed counts typically very
  close to expected at the 1/51 rate, the chi² statistic stays well
  below 3.841 in practice — but the p-value derived from the
  approximation is unreliable in this regime, weakening the inferential
  claim. The ETH-half (`750 × 25 / 51 ≈ 367.6`) and cross-attest aggregate
  (`16 × 25 / 51 ≈ 7.84`) both clear the threshold.
- **WR-04 (BURNIE common-tier branch not exercised by `awardDailyCoinPullRef`):**
  `awardDailyCoinPullRef` is the BURNIE-path helper and is the
  load-bearing oracle for the inline-duplicate at contract L1867-L1874.
  Every call to `awardDailyCoinPullRef` in the fixture passes
  `trait_i: GOLD_TRAIT` (lines 504, 836, 1006, 1079). The BURNIE common-tier
  branch (L1870-L1873 of the contract, the inline-duplicate of L1735-L1736)
  is therefore never exercised through the BURNIE-specific helper. The
  shared primitive `goldTierVirtualCount` IS tested at COMMON_TRAIT
  (line 454), and that primitive is what both helpers ultimately call —
  so the algorithmic surface is covered indirectly. But a future
  contributor mutating the inline BURNIE branch in a way that drifts
  from the shared primitive (e.g., copy-paste error reverting just the
  BURNIE site to v41 `len/50` behavior) would not be caught by this
  fixture as a BURNIE-path-specific regression because no test pulls
  `awardDailyCoinPullRef` through the common-tier path. TST-DPNERF-02
  covers the ETH common-tier; there is no symmetric BURNIE common-tier
  fixture.

**7 Info-tier findings** cover dead guards, unused exports, misleading
test descriptions, redundant `forge inspect` calls, decorative chain-state
seeding, inconsistent Wilson-Hilferty Z logging, and the carry-forward
of Phase 293 IN-04 (forge inspect parser brittleness).

## Warnings

### WR-01: TST-DPNERF-04 cross-attestation is JS-vs-JS, not JS-vs-EVM

**File:** `test/edge/DeityPassGoldNerfRegression.test.js:1099-1215`
**Issue:** The describe-block docstring (lines 895-901), the test description string (line 1100-1101), the file header (line 102-108), and the inline trace log (line 1206) all frame this 16-iteration block as a "cross-attestation" that establishes "JS↔EVM bit-identity" and "D-295-INVOKE-01 ALGORITHM_VERIFIED established". But the test body (lines 1148-1173) executes `randTraitTicketRef(...)` twice with **identical** inputs (`readBack`, `randomWord`, `GOLD_TRAIT`, `numWinners`, `salt`, `deity` — all same between `out1` and `out2`) and asserts `out1[k] === out2[k]` for every output element. This proves the JS oracle is **deterministic against itself** — a tautology that holds for any pure function over the same arguments. The only EVM touch is `seedTraitBucket(...)` + `readTraitBucket(...)` round-trip at lines 1126-1146, which verifies storage-layout encoding/decoding parity (load-bearing) but does not exercise `_randTraitTicket` on-chain (the function is `private view` and would require a visibility flip per D-295-INVOKE-01 escalation, which was explicitly NOT invoked). The "ALGORITHM_VERIFIED" claim cannot rest on this test.

**Fix:** Either (a) honestly describe what the test does and what it does not — drop the "cross-attestation / JS↔EVM bit-identity / ALGORITHM_VERIFIED" framing and replace with "JS-oracle determinism + storage round-trip integrity"; OR (b) actually exercise an EVM execution path. Option (b) variants in increasing order of intrusiveness:

```javascript
// (b1) Cheapest: invoke an existing CALLER of _randTraitTicket on-chain
//      (e.g., a fixture that completes a day boundary so _processDailyEth
//      runs naturally) and assert the contract-emitted JackpotEthWin
//      events at the seeded (lvl, GOLD_TRAIT) bucket match the oracle's
//      predicted (winner, ticketIndex) pairs byte-equal.

// (b2) Invoke the BURNIE callsite via the public `payDailyCoinJackpot`
//      entry — but only after wiring the `_calcDailyCoinBudget(lvl) > 0`
//      precondition (prize pool funded, level state set, jackpot phase
//      active). D-295-INVOKE-01 prices this in as "non-trivial game-state
//      scaffolding" — feasible but expensive.

// (b3) Heaviest: invoke the visibility-flip escalation path per
//      D-295-INVOKE-01 (expose _randTraitTicket via a test-only harness
//      contract). Out of scope per the plan.
```

For (a), update the docstring at lines 887-901, the test description at line 1099-1101, and the trace log at line 1200-1207 to read:

```javascript
it(
  N_CROSS +
    "-iteration JS-oracle determinism + storage round-trip: per-iteration storage seed + read-back byte-equality + JS-oracle output is invariant under identical inputs; per-iteration chi² goodness-of-fit < 3.841 (p > 0.05)",
  async function () { /* ... */
    console.log(
      `      [TST-DPNERF-04 storage round-trip + JS determinism] ${matchCount}/${N_CROSS} ` +
        `iterations passed determinism replay; ` +
        `totalSentinels=${totalSentinels} / ${totalDraws} ` +
        `(target=${expectedRate.toFixed(5)}); chi²=${chi2.toFixed(3)} < ${crit} (df=1); ` +
        `D-295-INVOKE-01 ALGORITHM_VERIFIED evidence rests on the JS-oracle bit-mirror ` +
        `at randTraitTicketRef.mjs against the contract source per Task 3 grep-verification — ` +
        `NOT on JS-vs-EVM execution equivalence (visibility-flip escalation not invoked)`
    );
  }
);
```

---

### WR-02: `isDeityPresent` mis-classifies non-canonical zero-shape inputs as deity-present

**File:** `test/helpers/randTraitTicketRef.mjs:74-78`
**Issue:**
```javascript
function isDeityPresent(deity) {
  if (deity === undefined || deity === null) return false;
  const lower = String(deity).toLowerCase();
  return lower !== ZERO_ADDRESS && lower !== "0x0";
}
```
Sentinels only two literal zero-shape strings: the canonical 42-character `"0x" + "0".repeat(40)` and the short form `"0x0"`. Any other shape that Solidity would treat as `address(0)` is treated as non-zero by the helper:
- `""` (empty string) — passes
- `"0x"` — passes (no zero digits at all)
- `"0x00"` — passes
- `"0x000000"` — passes
- `"0"` (missing `0x` prefix) — passes
- `"0x0000000000000000000000000000000000000000000"` (extra zeros) — passes
- A `BigInt(0)` accidentally interpolated — passes after `String()` produces `"0"`

Today every test callsite uses `hre.ethers.getAddress(...)` (canonical mixed-case 42-char checksummed) or the module-level `ZERO_ADDRESS` import (canonical 42-char lowercase). So the bug is latent. But the failure mode is silent and counter-intuitive: passing `deity: "0x00"` returns `virtualCount > 0` (gold-tier branch fires) where Solidity would set `virtualCount = 0` and effectively skip the deity slot. A future contributor writing a stress-test with a hand-constructed zero would get a confusing JS-vs-Solidity mismatch.

**Fix:** Replace the string-shape sentinel with a numeric-zero check:
```javascript
function isDeityPresent(deity) {
  if (deity === undefined || deity === null) return false;
  // Solidity: deity != address(0). Mirror via BigInt numeric value.
  try {
    return BigInt(deity) !== 0n;
  } catch {
    // Malformed input (not hex / not numeric) — fail closed.
    return false;
  }
}
```
This correctly mirrors Solidity's `address(0)` semantic for ANY string/numeric input shape that ethers/Node coerces to a hex address.

---

### WR-03: BURNIE-half chi² expected count (~4.9) below the χ²-approximation validity threshold of 5

**File:** `test/edge/DeityPassGoldNerfRegression.test.js:1023-1042`
**Issue:**
```javascript
const expectedRate = 1 / (BUCKET_SIZE + 1); // 1/51 ≈ 0.01961
const expectedSentinel = N_EV_BURNIE * expectedRate; // 250 × 1/51 ≈ 4.9
const expectedRegular = N_EV_BURNIE * (1 - expectedRate); // ≈ 245.1
const chi2 = computeChi2Multinomial(
  [totalBurnieDeitySentinels, N_EV_BURNIE - totalBurnieDeitySentinels],
  [expectedSentinel, expectedRegular]
);
```
The chi²-approximation to the multinomial requires expected counts ≥ 5 in EVERY cell (Cochran's rule; more conservative variants require ≥ 10). With `N_EV_BURNIE = 250` and `expectedRate = 1/51`, the rare-event cell sits at 4.9 — narrowly below threshold. The chi² test will pass with high probability under H₀ (true rate = 1/51), so observed false-negative rate is low, but the p-value claimed in the failure message ("p > 0.05 against analytical 1/(50+1) per-draw expectation") is suspect in this expected-count regime. By contrast, the ETH-half (line 956-983) sits at `750 × 25 × 1/51 ≈ 367.6` and the cross-attest aggregate at `16 × 25 / 51 ≈ 7.84` (also above 5).

**Fix:** Either (a) raise `N_EV_BURNIE` from 250 to at least 256 to clear the threshold (`256/51 ≈ 5.02`); or, more comfortably (b) use Fisher's exact test for the rare-event cell, or (c) use a binomial / Wilson-score CI for the sentinel rate directly:

```javascript
// (a) Minimal fix — bump N_EV_BURNIE to the lowest value clearing E ≥ 5.
const N_EV_BURNIE = 260; // 260 / 51 = 5.10 > 5
const N_EV = N_EV_ETH + N_EV_BURNIE; // re-derived combined total
```

If the EV-split ratio (750/250) is itself a load-bearing decision per D-295-EV-METHODOLOGY-01 (production call-frequency proportion), document the chi²-validity weakness explicitly and substitute a binomial test for the BURNIE-half rare-event cell.

---

### WR-04: BURNIE common-tier branch (`awardDailyCoinPullRef` with `COMMON_TRAIT`) has zero direct coverage

**File:** `test/edge/DeityPassGoldNerfRegression.test.js` (BURNIE-side coverage gap)
**Issue:** `awardDailyCoinPullRef` is the BURNIE-path oracle. It is invoked at 4 callsites in the fixture:
- Line 501 (setup-and-sanity) — `trait_i: GOLD_TRAIT`
- Line 833 (TST-DPNERF-03) — `trait_i: GOLD_TRAIT`
- Line 1003 (TST-DPNERF-04 BURNIE half) — `trait_i: GOLD_TRAIT`
- Line 1076 (TST-DPNERF-04 combined) — `trait_i: GOLD_TRAIT`

All four pass GOLD_TRAIT. The BURNIE common-tier branch at contract L1870-L1873 (`virtualCount = len/50; if (virtualCount < 2) virtualCount = 2`) — the inline-duplicate of the ETH common-tier formula — is therefore not exercised through the BURNIE-specific helper. The shared primitive `goldTierVirtualCount(COMMON_TRAIT, 50n, true) === 2n` IS asserted (setup-and-sanity, line 454), and both helpers call that primitive, so the algorithmic correctness of the common-tier branch is verified indirectly. But the BURNIE-PATH-LEVEL byte mapping (winner assignment, ticketIdx semantics, effectiveLen computation under `virtualCount=2`) is not. A regression specifically in the BURNIE inline-duplicate (a copy-paste drift where the BURNIE site reverts to v41 `len/50` no-floor behavior) would only be caught by the shared-primitive assertion, not by a BURNIE-callsite-equivalent test.

**Fix:** Add a symmetric BURNIE common-tier test mirroring TST-DPNERF-02's structure but driven through `awardDailyCoinPullRef`:

```javascript
// TST-DPNERF-02b (or a sub-describe inside TST-DPNERF-02): BURNIE common-tier
// inline-duplicate L1870-L1873 — virtualCount == max(len/50, 2) at the
// per-pull granularity.
it("BURNIE common-tier inline-duplicate L1870-L1873: awardDailyCoinPullRef yields virtualCount=2n at bucket=50, virtualCount=4n at bucket=200", function () {
  const deity = hre.ethers.getAddress("0x000000000000000000000000000000000000C00B");
  const holders50 = generateHolderAddresses(50);
  const out50 = awardDailyCoinPullRef({
    holders: holders50,
    randomWord: DAILY_ENTROPY,
    trait_i: COMMON_TRAIT,
    lvlPrime: 1,
    pullIdx: 0n,
    deity,
  });
  expect(out50.virtualCount).to.equal(2n);
  expect(out50.effectiveLen).to.equal(52n);

  const holders200 = generateHolderAddresses(200, "0xC0E5C0E5");
  const out200 = awardDailyCoinPullRef({
    holders: holders200,
    randomWord: DAILY_ENTROPY,
    trait_i: COMMON_TRAIT,
    lvlPrime: 1,
    pullIdx: 0n,
    deity,
  });
  expect(out200.virtualCount).to.equal(4n);
});
```

This locks the BURNIE-callsite common-tier mapping symmetrically with TST-DPNERF-02's ETH coverage.

---

## Info

### IN-01: Setup test description claims `fullSymId >= 32` exercise but actually exercises `fullSymId == 31`

**File:** `test/edge/DeityPassGoldNerfRegression.test.js:460-465`
**Issue:**
```javascript
// fullSymId >= 32: branch skipped entirely (no deity slot exists).
const traitWithHighSymId = (3 << 6) | (7 << 3) | 7; // quadrant 3, gold, symIdx 7 → fullSymId 31 (still < 32)
expect(
  goldTierVirtualCount(traitWithHighSymId, 50n, true)
).to.equal(1n);
```
The top comment promises a `fullSymId >= 32` skip-branch exercise; the inline comment on the same line then admits `fullSymId 31 (still < 32)`. The assertion verifies `virtualCount === 1n`, which is the GOLD-TIER BRANCH FIRING result — the opposite of "branch skipped entirely". For a uint8 trait, `fullSymId = (trait >> 6) * 8 + (trait & 0x07)` is bounded by `3*8 + 7 = 31`, so it is structurally IMPOSSIBLE to construct an input that triggers the `fullSymId >= 32` skip. The helper's `if (fullSymId >= 32) return 0n` guard at line 110 is unreachable by construction (see IN-02 carry-forward of `feedback_no_dead_guards.md`).

**Fix:** Drop the misleading comment and the contradictory inline note; rephrase to match what the test actually verifies:
```javascript
// Edge of the deity-slot range: trait byte maxing the (quadrant, symIdx)
// fields → fullSymId = 3*8 + 7 = 31 (still < 32, deity slot exists).
// The gold-tier branch fires; virtualCount=1.
const traitMaxSymId = (3 << 6) | (7 << 3) | 7; // fullSymId = 31
expect(goldTierVirtualCount(traitMaxSymId, 50n, true)).to.equal(1n);
```

---

### IN-02: Dead guard `if (fullSymId >= 32) return 0n` in helper contradicts the helper file's own `feedback_no_dead_guards.md` carry-forward stance

**File:** `test/helpers/randTraitTicketRef.mjs:110`
**Issue:** Line 110 reads `if (fullSymId >= 32) return 0n;`. Given `traitNum = Number(trait) & 0xff` (line 108), `fullSymId = ((traitNum >> 6) & 0x03) * 8 + (traitNum & 0x07)` (line 109) is structurally bounded above by `3*8 + 7 = 31`. The branch is unreachable. The Phase 293 review (IN-02) and the project memory at `feedback_no_dead_guards.md` argue against dead branches even in test code, and the sister helper `rollHeroSymbolRef.mjs` is cited as enforcing that stance. This helper inherits the same stance verbally (header line 13 in 293-REVIEW.md context) but introduces a new dead branch.

**Fix:** Drop the dead guard. The contract has a parallel dead guard at L1729 + L1843 (`if (fullSymId < 32)`), but that is contract code — out of scope for this test-only review. The helper version IS in scope:
```javascript
export function goldTierVirtualCount(trait, len, deityPresent) {
  const traitNum = Number(trait) & 0xff;
  const fullSymId = ((traitNum >> 6) & 0x03) * 8 + (traitNum & 0x07);
  // fullSymId is bounded by 3*8 + 7 = 31; the `fullSymId >= 32` branch
  // is unreachable for any uint8 trait input. Mirror the contract's
  // `if (fullSymId < 32)` guard implicitly by accepting the bound.
  if (!deityPresent) return 0n;
  if (((traitNum >> 3) & 7) === 7) return 1n;
  const lenBn = typeof len === "bigint" ? len : BigInt(len);
  const vc = lenBn / 50n;
  return vc < 2n ? 2n : vc;
}
```
Alternatively, if the dead guard is intentional defense-in-depth against a Number-coercion bug that produces `traitNum > 255` (which `& 0xff` already prevents), document the rationale inline. Today the line is just noise.

---

### IN-03: Unused `U64_MASK` / `U32_MASK` exports in `RAND_TRAIT_TICKET_CONSTANTS`

**File:** `test/helpers/randTraitTicketRef.mjs:63-64, 307-308`
**Issue:**
```javascript
const U64_MASK = (1n << 64n) - 1n;
const U32_MASK = (1n << 32n) - 1n;
// ...
export const RAND_TRAIT_TICKET_CONSTANTS = Object.freeze({
  U256_MASK,
  U64_MASK,
  U32_MASK,
  DEITY_SENTINEL_TICKET_IDX,
  ZERO_ADDRESS,
});
```
`U64_MASK` and `U32_MASK` are defined and exported but never used in the helper's own logic. The DPNERF algorithm has no uint64 or uint32 boundary (the only boundaries are `uint256` for keccak inputs/ticket indexes and `uint8` for trait/numWinners/salt). The sister helper `rollHeroSymbolRef.mjs` legitimately uses U64_MASK and U32_MASK because `_rollHeroSymbol` operates on packed uint64 totals + uint32 per-slot amounts. Copy-pasting the mask declarations across helpers without pruning is a clean-up nit.

**Fix:** Drop the unused mask declarations and the corresponding `RAND_TRAIT_TICKET_CONSTANTS` keys:
```javascript
const U256_MASK = (1n << 256n) - 1n;
const DEITY_SENTINEL_TICKET_IDX = U256_MASK;
const ZERO_ADDRESS = "0x" + "0".repeat(40);

// ...
export const RAND_TRAIT_TICKET_CONSTANTS = Object.freeze({
  U256_MASK,
  DEITY_SENTINEL_TICKET_IDX,
  ZERO_ADDRESS,
});
```
Verify no external consumer imports `RAND_TRAIT_TICKET_CONSTANTS.U64_MASK` (grep the test/ tree).

---

### IN-04: `deriveStorageSlot` called repeatedly per `it` block instead of cached at module level

**File:** `test/edge/DeityPassGoldNerfRegression.test.js:430-448, 551-552, 665-666, 789-790, 1108-1109, 1244-1245`
**Issue:** Every `it` block that touches chain storage re-derives the `deityBySymbol` and `traitBurnTicket` base slots via `deriveStorageSlot(...)`, which shells out to `forge inspect` (an expensive child-process invocation, ~hundreds of ms). The slots are immutable for the duration of the test run (and across runs unless the storage layout drifts, in which case the `FALLBACK_DEITY_BY_SYMBOL_SLOT` / `FALLBACK_TRAIT_BURN_TICKET_SLOT` cross-check at lines 434 / 444 would catch it). Counted: at least 6 `it` blocks × 2 vars = 12 `forge inspect` invocations per test run. Cumulative wall-clock cost is meaningful in CI.

**Fix:** Hoist into module-level constants gated by a `before()` hook:
```javascript
// Module-level
let DEITY_BY_SYMBOL_SLOT;
let TRAIT_BURN_TICKET_SLOT;

before(() => {
  DEITY_BY_SYMBOL_SLOT = deriveStorageSlot("deityBySymbol");
  TRAIT_BURN_TICKET_SLOT = deriveStorageSlot("traitBurnTicket");
  // Cross-check the EMPTY-diff attestation from Phase 294 §2.
  if (DEITY_BY_SYMBOL_SLOT !== FALLBACK_DEITY_BY_SYMBOL_SLOT) {
    throw new Error(`deityBySymbol slot drift: ${DEITY_BY_SYMBOL_SLOT} != ${FALLBACK_DEITY_BY_SYMBOL_SLOT}`);
  }
  if (TRAIT_BURN_TICKET_SLOT !== FALLBACK_TRAIT_BURN_TICKET_SLOT) {
    throw new Error(`traitBurnTicket slot drift: ${TRAIT_BURN_TICKET_SLOT} != ${FALLBACK_TRAIT_BURN_TICKET_SLOT}`);
  }
});
```
Then reference the module-level `DEITY_BY_SYMBOL_SLOT` / `TRAIT_BURN_TICKET_SLOT` from every `it` block instead of re-deriving.

---

### IN-05: TST-DPNERF-03 chain-state seeding is decorative (contract never executes against it)

**File:** `test/edge/DeityPassGoldNerfRegression.test.js:786-873`
**Issue:** TST-DPNERF-03 wires `await loadFixture(deployFullProtocol)`, derives storage base slots, seeds `deityBySymbol[0]` and `traitBurnTicket[lvlPrime][GOLD_TRAIT]` for lvlPrime in [1..10], then for each of 50 pulls calls `readTraitBucket(...)` (read-back from chain) and passes the result to `awardDailyCoinPullRef`. The contract is NEVER invoked between the seeding and the read-back — the chain state is purely a round-trip channel: `holders[]` → on-chain storage → `readBack[]` → JS oracle. Since the `seedTraitBucket` / `readTraitBucket` round-trip is verified byte-equal by the setup-and-sanity test (TST-DPNERF-01 at line 581-584), the chain-state intermediation in TST-DPNERF-03 is redundant: feeding `holders[]` directly to the JS oracle would produce identical assertions. The describe-block docstring at lines 768-775 frames this as "drives `awardDailyCoinPullRef` against the seeded BURNIE bucket state" — but the seeded BURNIE bucket state is only ever observed by the JS oracle, never by the contract.

**Fix:** Either (a) drop the chain seeding entirely and run TST-DPNERF-03 as a pure JS-oracle test (cheaper, faster, less brittle); OR (b) document the chain-state seeding as deliberate scaffolding for a future contract-side cross-check (currently deferred to D-295-INVOKE-01 escalation):

```javascript
// (a) Drop chain seeding — pure JS-oracle 50-pull cap exercise:
describe("TST-DPNERF-03 — BURNIE coin jackpot path gold-tier virtualCount == 1 ...", function () {
  it("drives awardDailyCoinPullRef across DAILY_COIN_MAX_WINNERS=50 pulls + asserts virtualCount=1n per pull + deity-sentinel pair invariant L1888-L1893 holds", function () {
    const deity = hre.ethers.getAddress("0x00000000000000000000000000000000000B0E11");
    const holderBuckets = {};
    for (let lvlPrime = 1; lvlPrime <= 10; ++lvlPrime) {
      holderBuckets[lvlPrime] = generateHolderAddresses(BUCKET_SIZE, "0xB011" + lvlPrime.toString(16).padStart(4, "0"));
    }
    const CAP = 50;
    /* ... same assertions, no `await loadFixture` ... */
  });
});
```

---

### IN-06: Wilson-Hilferty `z` logged on 2 of 3 chi² tests; inconsistent traceability

**File:** `test/edge/DeityPassGoldNerfRegression.test.js:965, 1031, 1200-1207`
**Issue:** The Wilson-Hilferty normal approximation `wilsonHilfertyZ(chi2, 1)` is computed and logged for the ETH-half EV chi² (line 965) and the BURNIE-half EV chi² (line 1031), but is OMITTED from the cross-attestation chi² log (line 1200-1207). All three chi² values carry the same df=1 critical 3.841; logging Z on two and omitting on the third is inconsistent — a reader scanning the three trace logs side-by-side gets asymmetric information density.

**Fix:** Add the Z computation + log for symmetry:
```javascript
const crit = CHI2_CRIT_05[1];
const z = wilsonHilfertyZ(chi2, 1);

console.log(
  `      [TST-DPNERF-04 cross-attest] ${matchCount}/${N_CROSS} ... ; ` +
    `chi²=${chi2.toFixed(3)} < ${crit} (df=1); Wilson-Hilferty Z=${z.toFixed(3)}; ` +
    `D-295-INVOKE-01 ALGORITHM_VERIFIED established`
);
```
(See also WR-01 re: rewording the trailing `ALGORITHM_VERIFIED` claim.)

---

### IN-07: `forge inspect` parser brittle to foundry-version drift (carry-forward from Phase 293 IN-04)

**File:** `test/edge/DeityPassGoldNerfRegression.test.js:192-225`
**Issue:** `deriveStorageSlot` parses `forge inspect storageLayout` human-readable table output by splitting on `|` and checking `cells[k] === varName`. Future foundry versions may default to JSON output, change column ordering, or drop the human-readable table format — silently producing the "failed to parse" throw at line 221-224. The Phase 293 review (IN-04) flagged the same issue against `HeroOverrideWeightedRoll.test.js` and proposed switching to `forge inspect ... --json`. The same fix applies here (and would unify the parsing layer across two test files for free).

**Fix:**
```javascript
function deriveStorageSlot(varName) {
  let forgeOut;
  try {
    forgeOut = execSync(
      "FOUNDRY_DISABLE_NIGHTLY_WARNING=1 forge inspect " +
        "contracts/storage/DegenerusGameStorage.sol:DegenerusGameStorage " +
        "storageLayout --json 2>/dev/null"
    ).toString();
  } catch (err) {
    throw new Error(`deriveStorageSlot(${varName}): forge inspect failed — ${err.message}`);
  }
  const layout = JSON.parse(forgeOut);
  const entry = layout.storage.find((s) => s.label === varName);
  if (!entry) {
    throw new Error(`deriveStorageSlot(${varName}): not found in storageLayout`);
  }
  return BigInt(entry.slot);
}
```
Verify `forge inspect storageLayout --json` is stable across the project's pinned foundry version (and matches the Phase 293 fix once applied there).

---

## Notes Outside Findings

**Sound design choices observed:**

- The JS oracle's keccak input encoding (`abi.encode` with the documented type list) correctly mirrors the Solidity `abi.encode` 32-byte left-padded layout. The apparent type-width mismatch on the ETH `i` parameter (helper: uint8, contract: uint256) is byte-equivalent under `abi.encode` since both produce a 32-byte left-padded word for any `i` in `uint8` range — verified non-bug. The header comment at lines 46-48 documents the equivalence correctly.
- The `DEITY_SENTINEL_TICKET_IDX = type(uint256).max` marker is plumbed consistently across helper + tests (line 65, 176, 487, 513, 615, 714, 857).
- Storage-slot math for `mapping(uint24 => address[][256])` (outer: `keccak256(abi.encode(lvl, baseSlot))`; inner: `outerSlot + trait`; data: `keccak256(lengthSlot) + i`) is correct Solidity layout.
- The seed-and-read-back round-trip (`seedTraitBucket` + `readTraitBucket`) at TST-DPNERF-01 (lines 567-584) provides genuine cross-validation of the storage-layout encoding — load-bearing for the slot-derivation correctness.
- Address generation via `generateHolderAddresses` produces collision-free addresses across all seedPrefix values used in the fixture (verified by inspection: seedPrefixes use disjoint hex byte ranges from deity addresses).
- Deterministic per-iteration entropy (`deriveIterationEntropy(label, i)`) with label-namespaced keccak chains correctly prevents cross-iteration entropy collision while remaining reproducible across test runs.
- The setup-and-sanity describe block (lines 427-520) provides genuine forge-inspect EMPTY-diff cross-check against the v41 close pin (lines 434, 444) before any TST-DPNERF-NN assertion fires — defense against silent storage-layout drift.
- The shared primitive `goldTierVirtualCount` factoring is correct: both `randTraitTicketRef` (line 171) and `awardDailyCoinPullRef` (line 256) delegate to the same function, so any algorithmic regression in the gold-tier formula is caught at both surfaces by one fix. This is the structural argument that mitigates WR-04's concrete coverage gap.

**Acceptable deferrals per phase-plan scope:**

- ETH callsites 1 + 2 (`_runEarlyBirdLootboxJackpot` L698, `_distributeTicketsToBucket` L988) deferred to Phase 296 SWEEP per D-294-CALLER-UNIFORM-01 — flagged at file header lines 84-85, consistent with the SWEEP scope.
- D-295-GAS-01 SKIP-GAS posture (no empirical gas measurement at this phase) — Phase 294 §5 attestation is load-bearing per file header lines 54-59. Consistent with Phase 291 D-291-GAS-01 precedent.
- D-295-INVOKE-01 visibility-flip escalation NOT invoked — contracts/ untouched, per phase-plan disposition. WR-01 above is about how the test FRAMES this disposition, not about the disposition itself.

---

_Reviewed: 2026-05-18_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
