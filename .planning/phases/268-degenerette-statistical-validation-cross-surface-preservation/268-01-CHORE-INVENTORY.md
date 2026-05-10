---
phase: 268-degenerette-statistical-validation-cross-surface-preservation
plan: 268-01
task: 1
type: chore
status: complete
authored: 2026-05-10
purpose: Test-file authoring sketches + reusable-helper inventory + worst-case derivation worksheet — authoritative source-of-truth for Task 2 (USER-APPROVED batched test commit).
---

# Phase 268 Task 1 — Test-File Authoring Sketches + Helper Inventory

This working file consolidates everything Task 2 needs to author the 5 test files
(3 NEW stat + 1 EXTENDED surface + 1 NEW gas) + `package.json` `test:stat`
wiring as a single batched diff. Eight sections per the plan:

1. Test-file authoring sketches (per-file NatSpec + describe layout + sample budget).
2. Reusable-helper inventory cross-cite (chi² primitives + Phase 264/266 carry).
3. VRF-override helper construction proof (Hardhat-side mirror of Foundry pattern).
4. Pool-funding entry identification for D-268-THINPOOL-01.
5. advanceGame baseline pin reference.
6. numTickets cap reference.
7. Per-N constant paste-source identification.
8. Worst-case derivation worksheet for SURF-06.

---

## §1 — Test-file authoring sketches

### File 1 — `test/stat/DegenerettePerNEvExactness.test.js` (NEW, ~350 LOC)

**Requirements covered:** STAT-01 + STAT-05 + STAT-07 + D-268-HARNESS-01 spot-check + D-268-THINPOOL-01 thin-pool sub-case.

**Sample budget (locked per ROADMAP floors):**
- STAT-01 = 1_000_000 draws per N (5 × 1M = 5M total).
- STAT-05 histogram derived from STAT-01's per-N pool (no extra draws).
- Cross-pick parity sweep: 32 picks per N × 5 N-classes + 32 random picks at 100K draws each.
- D-268-HARNESS-01 spot-check: 5 on-chain `placeDegeneretteBet` ETH calls (one per N).
- STAT-07 ETH-split distribution = 1_000_000 ETH-currency draws.
- STAT-07 thin-pool sub-case: 1 fresh-fixture `loadFixture(deployFullProtocol)` round-trip.

**Seed family `0xC037_NNNN`:**
- `0xC037_0001..0xC037_0005` — STAT-01 per-N main pool (N=0..4).
- `0xC037_0010` — cross-pick parity sweep stratification.
- `0xC037_0020` — STAT-05 reuses STAT-01 pool.
- `0xC037_0030` — STAT-07 ETH-split distribution.
- `0xC037_0040..0xC037_0044` — D-268-HARNESS-01 on-chain spot-checks (per-N).
- `0xC037_0050` — STAT-07 thin-pool fixture sub-case.

**α=0.05 thresholds:** STAT-01 ±0.50 centi-x absolute; STAT-05 ±0.5% bin tolerance; STAT-07 ±0.5% bin tolerance.

**NatSpec header outline:**
- Phase 268 STAT-01 + STAT-05 + STAT-07 banner.
- Cite `feedback_skip_research_test_phases.md` (mechanical scope).
- Cite `feedback_no_history_in_comments.md` — describes the per-N dispatch as the CURRENT design (NEVER reference any prior design).
- Sample-budget calibration block with per-test seed integers + α=0.05 thresholds.
- D-268-HARNESS-01 hybrid pattern explanation.
- D-268-THINPOOL-01 fresh-fixture pattern explanation.

**Describe-block list:**
1. `describe("STAT-01 — per-N basePayoutEV exactness at N=1M draws")` with per-N `it` blocks asserting `Math.abs(meanCentiX - 100.00) <= 0.50`.
2. `describe("STAT-05 — per-N analytical match-count histogram match within ±0.5% bin")` reusing STAT-01 pool.
3. `describe("STAT-01 — cross-pick parity sweep over 16,384 player-pick configurations (sub-sampled 32 per N + 32 random)")`.
4. `describe("STAT-01 + STAT-03 + STAT-04 D-268-HARNESS-01 on-chain spot-check")` with per-N `placeDegeneretteBet` round-trip.
5. `describe("STAT-07 — ETH payout split rule")` with sub-describes (5a) Distribution sweep + (5b) D-268-THINPOOL-01 thin-pool.

**Approximate LOC budget:** ~350 (matches `min_lines` in PLAN frontmatter).

---

### File 2 — `test/stat/DegeneretteProducerChi2.test.js` (NEW, ~200 LOC)

**Requirements covered:** STAT-02 + STAT-06 + boundary cross-validation.

**Sample budget:** 1_000_000 samples × 4 quadrants = 4M-quadrant pool for color + symbol chi².

**Seed family `0xC037_NNNN`:**
- `0xC037_0100` — color chi² main pool.
- `0xC037_0101` — symbol chi² main pool.
- `0xC037_0102..0xC037_0117` — 16 boundary cross-validation seeds (one per scaled boundary value).

**α=0.05 thresholds:** color (df=7) chi² < `CHI2_CRIT_05[7]=14.067` OR Wilson-Hilferty Z<1.645; symbol (df=7) chi² < 14.067.

**NatSpec header outline:**
- Phase 268 STAT-02 + STAT-06 banner.
- Sample-budget calibration: 1M samples × 4 quadrants → 4M-quadrant pool.
- Per-quadrant color spec `[16,16,16,16,16,16,16,8]/120`; per-quadrant symbol spec uniform 1/8.
- D-IMPL-01 boundary cross-validation pattern (`packedTraitsDegenerette` is `internal pure`; route through `placeDegeneretteBet` + `FullTicketResult` event).

**Describe-block list:**
1. `describe("STAT-02 — per-quadrant color chi² uniformity at N=1M samples")`.
2. `describe("STAT-02 — per-quadrant symbol chi² uniformity at N=1M samples")`.
3. `describe("STAT-02 — D-IMPL-01 boundary cross-validation")` — at ≥16 boundary scaled values, route a deterministic VRF word through `placeDegeneretteBet` + capture `FullTicketResult` event, assert `jsPackedTraitsDegenerette(rngWord) == event.firstResultTicket`.

**Approximate LOC budget:** ~200.

---

### File 3 — `test/stat/DegeneretteBonusEv.test.js` (NEW, ~250 LOC)

**Requirements covered:** STAT-03 + STAT-04 + D-268-HARNESS-01 spot-check.

**Sample budget:** 100_000 hero-active draws per N × 5 N-classes × 4 hero quadrants = 2M-draw pool for STAT-03; 100_000 WWXRP-active draws per N × 5 N-classes = 500K-draw pool for STAT-04.

**Seed family `0xC037_NNNN`:**
- `0xC037_0200..0xC037_0204` — STAT-03 per-N hero-EV (one seed per N).
- `0xC037_0210..0xC037_0214` — STAT-04 per-N WWXRP-EV (one seed per N).
- `0xC037_0220..0xC037_0224` — D-268-HARNESS-01 on-chain spot-checks (per-N).

**Tolerance:** ±1% relative for both STAT-03 (hero EV-neutrality `|measured - 1.000| <= 0.01`) and STAT-04 (ETH-bonus EV ±0.05% absolute = ±1% relative against 5.000% target).

**NatSpec header outline:**
- Phase 268 STAT-03 + STAT-04 banner.
- Analytical references: HERO_PENALTY=9500 + HERO_SCALE=10_000 → EV-neutral per-N invariant `P(hero|M, N) × boost(M, N) + (1−P) × HERO_PENALTY = HERO_SCALE`. ETH-bonus EV target = 5.000% per N (Fraction-exact from `derive_5_tables.py` L271-284).
- Sample-budget rationale: 100K per N × 4 quadrants for hero EV → tighter than ±1% at α=0.05.

**Describe-block list:**
1. `describe("STAT-03 — per-N hero-boost EV ±1% at N=100K hero-active draws")`.
2. `describe("STAT-04 — per-N WWXRP factor EV ±1% at N=100K WWXRP-active draws")`.
3. `describe("STAT-03 + STAT-04 D-268-HARNESS-01 on-chain spot-check")` — 5 ETH-currency `placeDegeneretteBet` calls with hero quadrant active + crafted symbol-match.

**Approximate LOC budget:** ~250.

---

### File 4 — `test/stat/SurfaceRegression.test.js` extension (~+130 LOC delta)

**Requirements covered:** SURF-01..04 (SURF-05 covered structurally by `Phase268GasRegression.test.js` advanceGame envelope `it`).

**Append-only after L573.** DO NOT modify existing v33.0/v34.0/v35.0/v36.0 describe blocks (REG-01 carry-forward discipline).

**v37.0 baseline:** `1c0f09132d7439af9881c56fe197f81757f8164a` (v36.0 closure HEAD).

**Constants for new describe block (declared inline with `_V37` suffix to keep the v37.0 block self-contained per L466-473 carry pattern):**
```javascript
const V36_BASELINE = "1c0f09132d7439af9881c56fe197f81757f8164a";
const TRAIT_UTILS_PATH = "contracts/DegenerusTraitUtils.sol";
const JACKPOT_MODULE_PATH_V37 = "contracts/modules/DegenerusGameJackpotModule.sol";
const LOOTBOX_MODULE_PATH = "contracts/modules/DegenerusGameLootboxModule.sol";
const ENTROPY_LIB_PATH_V37 = "contracts/libraries/EntropyLib.sol";
```

**SURF-01 protected ranges (TraitUtils existing-functions byte-identical):**
- `weightedColorBucket` body L115-135.
- `traitFromWord` body L143-167.
- `packedTraitsFromSeed` body L169-178.
- (Additions post-L178 — `packedTraitsDegenerette` + `_degTrait` from Phase 267 — are NOT protected.)

**SURF-02..04 — file-level zero-diff** via `expectFileLevelZeroDiff(baseline, path)` mirroring the v36.0 describe pattern at L478-552.

**Describe-block list (5 `it` blocks):**
- `(a)` SURF-01 TraitUtils protected ranges via per-line modified-set walk.
- `(b)` SURF-02 JackpotModule file-level zero-diff.
- `(c)` SURF-03 LootboxModule file-level zero-diff (cite D-268-SURF03-01 inline).
- `(d)` SURF-04 EntropyLib file-level zero-diff.
- `(e)` v37.0 SURF preservation gate self-test (asserts Phase 268 stat files exist on disk).

**Approximate LOC budget:** ~130 delta added after L573 (final file ~700 LOC).

---

### File 5 — `test/gas/Phase268GasRegression.test.js` (NEW, ~350 LOC)

**Requirements covered:** SURF-06 (worst-case quickPlay) + structural carry of SURF-05 advanceGame envelope.

**Sample/measurement budget:** 1 worst-case `placeDegeneretteBet` round-trip with `ticketCount=10` + 1 advanceGame stage-6 5-cycle harness (mirror AdvanceGameGas L1694-1769).

**Seed family `0xC037_NNNN`:**
- `0xC037_C001` — worst-case rngWord engineering nonce prefix (10 distinct rngWords for the 10 spins).
- `0xC037_C100` — advanceGame stage-6 cycle randomization seed.

**NatSpec header per `feedback_gas_worst_case.md` letter:**
- Section "THEORETICAL WORST-CASE DERIVATION (D-268-WORSTGAS-01)" — N=3, M=8, hero match INHERENT at M=8, ETH tier 3, ticketCount=MAX_SPINS_PER_BET=10.
- Per-spin opcode walk yielding ~65K warm gas / ~75K cold gas → ~720K total worst-case → ceiling 800K (10% headroom).
- REF-CAPTURE protocol mirroring `Phase264GasRegression.test.js` L51-110.

**Constants:**
```javascript
const PER_CALL_GAS_CEILING = 800_000;
const ENTRY_POINT_DELTA_TOLERANCE = 2000;
const ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320; // v36.0 HEAD pin per test/gas/AdvanceGameGas.test.js L1668
const STAGE_DELTA_TOLERANCE_GAS_02 = 2000;
const WORST_CASE_QUICKPLAY_GAS_REF = 0; // REF-CAPTURE placeholder; pin after first run
```

**Describe-block list (SINGLE describe, SINGLE worst-case it block per D-268-WORSTGAS-01):**
1. `describe("v37.0 SURF-06 — worst-case quickPlay gas envelope")` containing exactly one `it("constructs N=3 + M=8 + ETH tier 3 + ticketCount=10 deterministically and asserts gas <= analytical ceiling")`.
2. `describe("SURF-06 — v37.0 advanceGame STAGE_PURCHASE_DAILY gas within ±2K of v36.0 baseline")` — re-declares the AdvanceGameGas L1694-1769 harness inline; soft-skip on stage-6 not observed.

NO M=7 fallback. NO ticketCount=1 fallback. NO statistical fallback. Single construction; hero inherent at M=8.

**Approximate LOC budget:** ~350.

---

## §2 — Reusable-helper inventory cross-cite

### Chi² primitives (verbatim re-declaration per STAT-06)

**Origin:** `test/stat/TraitDistribution.test.js`
- `makeRng` — L48-56 (15 LOC including blank lines + comment).
- `CHI2_CRIT_05` — L87-90 (object literal, 8 LOC including comment).
- `wilsonHilfertyZ` — L97-100 (4 LOC).

**Carry pattern:**
- Phase 264 `test/stat/PerPullLevelDistribution.test.js` L78-102 — 3-helper bundle re-declared verbatim (no shared module).
- Phase 266 `test/stat/LootboxEntropyDistribution.test.js` L45-69 — same 3-helper bundle re-declared verbatim.

**Phase 268 application:** Each of the 3 NEW stat test files (`DegenerettePerNEvExactness.test.js`, `DegeneretteProducerChi2.test.js`, `DegeneretteBonusEv.test.js`) re-declares ALL 3 helpers verbatim at top of file. ~27 LOC × 3 files = ~81 LOC of reuse-only chi² infra.

**STAT-06 acceptance:** Structural — the verbatim re-declaration itself satisfies STAT-06. Grep recipe `grep -c "function makeRng"` >= 1 in each of the 3 NEW stat files; `grep -c "CHI2_CRIT_05"` >= 1 each; `grep -c "wilsonHilfertyZ"` >= 1 each.

**No shared helper module per Phase 264/266 precedent.** Tests are self-contained; reduces inter-file coupling.

### Per-N JS-replica functions (verbatim re-declaration per file per Phase 264/266 precedent)

The 7 JS-replica functions live in File 1 (`DegenerettePerNEvExactness.test.js`) and are re-declared in Files 2 + 3 where needed. Functions:

- `jsPackedTraitsDegenerette(rand)` — mirrors `contracts/DegenerusTraitUtils.sol` L201-223 (`packedTraitsDegenerette` + `_degTrait`).
- `jsCountGoldQuadrants(playerTicket)` — mirrors `_countGoldQuadrants` L859-866.
- `jsCountMatches(playerTicket, resultTicket)` — mirrors `_countMatches` L872-902.
- `jsGetBasePayoutBps(N, matches)` — mirrors `_getBasePayoutBps` L1041-1056.
- `jsWwxrpFactor(N, bucket)` — mirrors `_wwxrpFactor` L920-929.
- `jsApplyHeroMultiplier(payout, playerTicket, resultTicket, matches, heroQuadrant, N)` — mirrors `_applyHeroMultiplier` L1007-1032.
- `jsFullTicketPayout(...)` — mirrors `_fullTicketPayout` L944-994 (top-level dispatch with `_countGoldQuadrants` → N → table lookup → ROI scaling → hero adjustment).
- `jsDistributePayoutEth(betAmount, payout, futurePool)` — mirrors `_distributePayout` UNFROZEN-path L725-790 (3-tier ETH split + pool-cap precedence; returns `{ethShare, lootboxShare, capped}`).

**Drift guard:** D-IMPL-01 boundary cross-validation in File 2 (`DegeneretteProducerChi2.test.js`) asserts `jsPackedTraitsDegenerette(rngWord) == on-chain producer output` for ≥16 boundary `scaled` values {0, 1, 13, 14, 27, 28, 29, ...}. JS-replica drift fails the boundary harness FIRST.

---

## §3 — VRF-override helper construction proof (Hardhat-side mirror)

**Foundry-side reference:** `test/fuzz/DegeneretteFreezeResolution.t.sol` L37 + L338-341.
- `LOOTBOX_RNG_WORD_SLOT = 39` — `lootboxRngWordByIndex` mapping root slot.
- `_injectLootboxRngWord(uint48 index, uint256 rngWord)`:
  ```solidity
  bytes32 slot = keccak256(abi.encode(uint256(index), uint256(LOOTBOX_RNG_WORD_SLOT)));
  vm.store(address(game), slot, bytes32(rngWord));
  ```

**Hardhat-side mirror (inline per file per planner discretion D-268-DISCRETION-CHOICES):**
```javascript
// LOOTBOX_RNG_WORD_SLOT = 39 (per Foundry precedent at test/fuzz/DegeneretteFreezeResolution.t.sol L37).
async function injectLootboxRngWord(game, index, rngWord) {
  const slot = hre.ethers.keccak256(
    hre.ethers.AbiCoder.defaultAbiCoder().encode(
      ["uint256", "uint256"],
      [BigInt(index), 39n]
    )
  );
  await hre.network.provider.send("hardhat_setStorageAt", [
    await game.getAddress(),
    slot,
    hre.ethers.zeroPadValue(hre.ethers.toBeHex(rngWord), 32),
  ]);
}
```

**Inlined in 3 places per file (no shared `test/helpers/vrfOverride.js` module):**
- File 1 D-268-HARNESS-01 spot-check describe block (5 calls).
- File 1 STAT-07 thin-pool sub-case describe block (1 call).
- File 5 SURF-06 worst-case describe block (10 calls — one per spin).
- File 2 D-IMPL-01 boundary cross-validation describe block (≥16 calls).
- File 3 D-268-HARNESS-01 spot-check describe block (5 calls).

Re-declare verbatim per file per Phase 264/266 chi²-tooling-reuse precedent.

---

## §4 — Pool-funding entry identification (D-268-THINPOOL-01)

**Foundry-side reference:** `test/fuzz/DegeneretteFreezeResolution.t.sol` L307-312 + L31 + L40.
- `PRIZE_POOLS_PACKED_SLOT = 2` — `prizePoolsPacked: [upper 128: futurePrizePool] [lower 128: nextPrizePool]`.
- `_seedFuturePrizePool(uint256 targetFuture)`:
  ```solidity
  uint256 currentPacked = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
  uint128 currentNext = uint128(currentPacked);
  uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
  vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
  ```

**Also required:** Seed `lootboxRngIndex = 1` so `placeDegeneretteBet` doesn't revert with `RngNotReady` at index 0:
- `LOOTBOX_RNG_PACKED_SLOT = 38`; `lootboxRngIndex` = low 48 bits.
- Foundry pattern at L57-67:
  ```solidity
  uint256 lrPacked = uint256(vm.load(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT))));
  lrPacked = (lrPacked & ~uint256(0xFFFFFFFFFFFF)) | uint256(1);
  vm.store(address(game), bytes32(uint256(LOOTBOX_RNG_PACKED_SLOT)), bytes32(lrPacked));
  ```

**Hardhat-side mirror (inline in File 1 STAT-07 thin-pool sub-case + File 5 SURF-06):**
```javascript
async function seedFuturePrizePool(game, targetFuture) {
  const packedSlot = "0x2";
  const currentRaw = await hre.network.provider.send("eth_getStorageAt", [
    await game.getAddress(),
    packedSlot,
    "latest",
  ]);
  const currentPacked = BigInt(currentRaw);
  const currentNext = currentPacked & ((1n << 128n) - 1n);
  const newPacked = (targetFuture << 128n) | currentNext;
  await hre.network.provider.send("hardhat_setStorageAt", [
    await game.getAddress(),
    packedSlot,
    hre.ethers.zeroPadValue(hre.ethers.toBeHex(newPacked), 32),
  ]);
}

async function seedLootboxRngIndex(game, targetIndex) {
  const packedSlot = "0x26"; // 38 decimal = 0x26 hex
  const currentRaw = await hre.network.provider.send("eth_getStorageAt", [
    await game.getAddress(),
    packedSlot,
    "latest",
  ]);
  const currentPacked = BigInt(currentRaw);
  const mask48 = (1n << 48n) - 1n;
  const newPacked = (currentPacked & ~mask48) | (BigInt(targetIndex) & mask48);
  await hre.network.provider.send("hardhat_setStorageAt", [
    await game.getAddress(),
    packedSlot,
    hre.ethers.zeroPadValue(hre.ethers.toBeHex(newPacked), 32),
  ]);
}
```

**STAT-07 thin-pool fixture parameter sketch:**
- Pool: `targetFuture = eth(0.1)` (small) — `loadFixture(deployFullProtocol)` then `seedFuturePrizePool(game, eth(0.1))`.
- Bet: `betAmount = eth(0.01)`.
- Engineered payout target: `eth(0.02)` (tier-1 ≤3× bet path).
- 10% pool cap: `0.1 × 0.1 = eth(0.01)`. Tier-1 says `ethShare = payout = eth(0.02)`. Cap binds because `0.02 > 0.01` → `ethShare = eth(0.01)`, `lootboxShare = eth(0.01)`. `PayoutCapped` event fires + cap precedence holds even on tier-1 ≤3× bet path.

**Choice of mechanism — `hardhat_setStorageAt` rather than admin entry:** No public pool-funding admin entry exists in `DegenerusGameDegeneretteModule.sol` that would let a test seed `futurePrizePool` to an arbitrary small value at fixture time without first running through a full purchase / advanceGame loop. Storage-slot injection via `hardhat_setStorageAt` mirrors the Foundry-side precedent and avoids `setStorageAt`-brittleness concerns flagged in CONTEXT.md by anchoring on the same `PRIZE_POOLS_PACKED_SLOT = 2` confirmed via `forge inspect DegenerusGameStorage storage` at the Foundry test's L24 comment.

---

## §5 — advanceGame baseline pin reference (SURF-06 advance-gas envelope `it`)

**Source:** `test/gas/AdvanceGameGas.test.js`
- L1667: `const STAGE_DELTA_TOLERANCE_GAS_02 = 2000;` (GAS-02 ±2K per-stage tolerance).
- L1668: `const ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320;` (pinned at v36.0 HEAD post Wave 1 contract refactor).
- L1694-1769: STAGE_PURCHASE_DAILY (6) 5-cycle harness with REF-CAPTURE protocol.

**Phase 268 application:** Re-declare both literals at the top of `test/gas/Phase268GasRegression.test.js` (do NOT import from `AdvanceGameGas.test.js` — keeps the gas file self-contained per Phase 264 precedent). Re-declare the L1694-1769 stage-6 harness inline (5 cycles × 50 advance attempts; soft-skip on stage-6 not observed).

**Assertion:** `|stage6Gas - 908_320| <= 2000`. v36.0 baseline is REUSED (no v37.0 re-pin) since Phase 267 Degenerette path is OFF the advanceGame hot path per ROADMAP Phase 268 success criterion 5.

---

## §6 — numTickets cap reference (SURF-06 worst-case ticketCount)

**Source:** `contracts/modules/DegenerusGameDegeneretteModule.sol` L226:
```solidity
/// @dev Maximum spins per bet (encoded as ticketCount in packed bet).
uint8 private constant MAX_SPINS_PER_BET = 10;
```

**Validation site:** L446-447 in `_placeDegeneretteBetCore`:
```solidity
if (ticketCount == 0 || ticketCount > MAX_SPINS_PER_BET)
    revert InvalidBet();
```

**Phase 268 application:** SURF-06 worst-case constructs `ticketCount = MAX_SPINS_PER_BET = 10`. Per-spin gas multiplies; 10 spins × ~65K warm gas ≈ 650K + ~70K overhead → ~720K total worst-case → ceiling 800K (10% headroom).

---

## §7 — Per-N constant paste-source identification (JS-replay tables)

For the JS-replay path, paste byte-identical hex constants from `contracts/modules/DegenerusGameDegeneretteModule.sol`:

**Per-N base payout tables (L254-258 — uint256 packed, M=0..7 in 32-bit slots):**
- L254: `QUICK_PLAY_PAYOUTS_N0_PACKED = 0x0001a42c000051f1000011da00000654000001ff000000cc0000000000000000;`
- L255: `QUICK_PLAY_PAYOUTS_N1_PACKED = 0x0001eb8600005fd7000014e70000075f00000256000000ef0000000000000000;`
- L256: `QUICK_PLAY_PAYOUTS_N2_PACKED = 0x000241d9000070ac00001894000008aa000002bf000001190000000000000000;`
- L257: `QUICK_PLAY_PAYOUTS_N3_PACKED = 0x0002ac130000856900001d1700000a39000003400000014d0000000000000000;`
- L258: `QUICK_PLAY_PAYOUTS_N4_PACKED = 0x0003310c00009f5a000022be00000c4d000003e20000018d0000000000000000;`

**Per-N M=8 jackpot tier (L262-266 — separate uint256s):**
- L262: `QUICK_PLAY_PAYOUT_N0_M8 = 10_756_411;` // 107,564.11x bet
- L263: `QUICK_PLAY_PAYOUT_N1_M8 = 12_583_037;` // 125,830.37x bet
- L264: `QUICK_PLAY_PAYOUT_N2_M8 = 14_792_939;` // 147,929.39x bet
- L265: `QUICK_PLAY_PAYOUT_N3_M8 = 17_512_324;` // 175,123.24x bet
- L266: `QUICK_PLAY_PAYOUT_N4_M8 = 20_916_435;` // 209,164.35x bet

**Per-N WWXRP factors (L281-285 — uint256 packed, B=5..8 in 64-bit slots):**
- L281: `WWXRP_FACTORS_N0_PACKED = 0x0000000002278add0000000003fd603d0000000000ddba9f00000000001923d6;`
- L282: `WWXRP_FACTORS_N1_PACKED = 0x0000000003aef46a0000000005fd43a60000000001285f2400000000001e36c9;`
- L283: `WWXRP_FACTORS_N2_PACKED = 0x0000000006442ce7000000000914e5e4000000000192745c000000000024f43d;`
- L284: `WWXRP_FACTORS_N3_PACKED = 0x000000000a96251f000000000dd6ad96000000000228fcb000000000002de0ce;`
- L285: `WWXRP_FACTORS_N4_PACKED = 0x0000000011ba25db00000000151a90e70000000002fdeaff0000000000399efe;`

**WWXRP scale (L280):** `WWXRP_BONUS_FACTOR_SCALE = 1_000_000;`

**Per-N hero boost (L337-341 — uint256 packed, M=2..7 in 16-bit slots):**
- L337: `HERO_BOOST_N0_PACKED = 0x275a27be2849291a2a762d2e;`
- L338: `HERO_BOOST_N1_PACKED = 0x275027a9282728e52a262ca9;`
- L339: `HERO_BOOST_N2_PACKED = 0x27482797280828b529d92c26;`
- L340: `HERO_BOOST_N3_PACKED = 0x2742278827ed288829902ba6;`
- L341: `HERO_BOOST_N4_PACKED = 0x273d277c27d62860294b2b2a;`

**Hero scale (L342-343):** `HERO_PENALTY = 9500;` `HERO_SCALE = 10_000;`

**ETH bonus + win cap (L185 + L196):**
- `ETH_ROI_BONUS_BPS = 500;` // ETH bonus EV target = 5.000% per N
- `ETH_WIN_CAP_BPS = 1_000;` // 10% of futurePool — pool cap precedence

**D-268-CONSTVERIFY-CARRY-01:** Phase 267 Task 2 grep-asserted all 25 packed constants byte-identical to `derive_5_tables.py` Fraction-exact stdout via `267-01-CONSTANTS-VERIFY.md` PASS_ALL_25. Phase 268 trusts this baseline; STAT-01..05 verifies the *dispatch applies the constants correctly* (catches mis-routed table assignments in `_getBasePayoutBps` / `_applyHeroMultiplier` / `_wwxrpFactor` per-N if/else legs that the constant-grep AND the JS replica both miss because the JS replica copies the same dispatch).

---

## §8 — Worst-case derivation worksheet for SURF-06

### Player-pick design

**Goal:** `_countGoldQuadrants(playerTicket) == 3` so the dispatch hits the longest if/else chain in `_getBasePayoutBps` / `_applyHeroMultiplier` / `_wwxrpFactor`.

**Construction:** 3 quadrants with `color == 7` (gold) + 1 quadrant with `color != 7` (any common, choose `color = 0` for simplicity). Symbols may be any value but must be deterministic so the rngWord engineering can target them.

**Encoded `playerTicket` (uint32) for {Q0=gold/sym0, Q1=gold/sym0, Q2=gold/sym0, Q3=common0/sym0}:**
- Q0: `(0 << 6) | (7 << 3) | 0 = 0x38` (color=7, symbol=0, quadrant=0).
- Q1: `(1 << 6) | (7 << 3) | 0 = 0x78` (color=7, symbol=0, quadrant=1).
- Q2: `(2 << 6) | (7 << 3) | 0 = 0xB8` (color=7, symbol=0, quadrant=2).
- Q3: `(3 << 6) | (0 << 3) | 0 = 0xC0` (color=0, symbol=0, quadrant=3).
- Packed uint32: `0xC0_B8_78_38` = `(0xC0 << 24) | (0xB8 << 16) | (0x78 << 8) | 0x38 = 0xC0B87838`.

Note: `_countGoldQuadrants` extracts color via `(ticket >> (q * 8 + 3)) & 7`. For Q0..Q2 with color=7 → count++. For Q3 with color=0 → no count. Total N = 3. Confirmed.

### Result-ticket design (engineered via VRF-word injection)

**Goal:** `_countMatches(playerTicket, resultTicket) == 8` (full color+symbol match across all 4 quadrants).

**Constraint per quadrant q:** result-ticket's quadrant byte must satisfy:
- Color (bits 5-3 of `resultTicket >> (q*8)`) == player's color in quadrant q.
- Symbol (bits 2-0 of `resultTicket >> (q*8)`) == player's symbol in quadrant q.

For player = `0xC0B87838` with all symbols=0:
- Q0: color=7, symbol=0 → result Q0 byte's color slice = 7, symbol slice = 0. Quadrant bits 7-6 are added by `packedTraitsDegenerette` deterministically (Q0=00, Q1=01, Q2=10, Q3=11), so the engineered constraint is on the 6 low bits of `_degTrait(rnd_q)` output.
- Q1: color=7, symbol=0 → ditto.
- Q2: color=7, symbol=0 → ditto.
- Q3: color=0, symbol=0 → result Q3's `_degTrait` must produce color=0 (`scaled >> 1 == 0` → `scaled ∈ {0, 1}`) and symbol=0.

### `_degTrait` constraint inversion (per 64-bit lane)

Per `contracts/DegenerusTraitUtils.sol` L218-223:
```solidity
function _degTrait(uint64 rnd) private pure returns (uint8) {
    uint32 scaled = uint32((uint64(uint32(rnd)) * 15) >> 32);
    uint8 color = scaled == 14 ? 7 : uint8(scaled >> 1);
    uint8 symbol = uint8(rnd >> 32) & 7;
    return (color << 3) | symbol;
}
```

**Per-quadrant 64-bit lane bit-field constraints:**
- Low 32 bits (`rnd_low`) feed `scaled = (rnd_low * 15) >> 32`. To target color=7 (gold) → `scaled = 14` → `rnd_low ∈ [ceil(14 * 2^32 / 15), ceil(15 * 2^32 / 15) - 1] = [4_008_636_142, 4_294_967_295]` (any value in this range). For color=0 → `scaled ∈ {0, 1}` → `rnd_low ∈ [0, ceil(2 * 2^32 / 15) - 1] = [0, 572_662_305]`.
- Bits 32-34 (`(rnd >> 32) & 7`) feed `symbol`. For symbol=0 → bits 32-34 = `000`.
- Bits 35-63 are unconstrained (free).

**Quadrant entropy cost:** color constraint cuts ~3 bits (effective; `scaled == 14` is 1 of 15 values + a bit of slack) + symbol constraint cuts 3 bits = ~6 bits per quadrant. 4 quadrants × ~6 bits = ~24 bits of entropy out of 256.

### rngWord → resultSeed → 4-quadrant constraint

Per `_resolveFullTicketBet` per-spin dispatch (executor: re-grep exact line range — preimage shape may have shifted; mirror live contract):
```
resultSeed_i = uint256(keccak256(abi.encodePacked(rngWord_i, indexBase + spinIdx_i, QUICK_PLAY_SALT)))
```
where `QUICK_PLAY_SALT = 0x51` per L233.

Then `resultTicket_i = packedTraitsDegenerette(resultSeed_i)`.

**Engineering rngWord:** Brute-force search rngWord candidates such that `keccak256(abi.encodePacked(rngWord, ...))` yields a `resultSeed` whose 4 64-bit lanes each satisfy the per-quadrant (color, symbol) constraint. Expected search depth per spin ≈ `2^24` = ~16M candidates × 10 spins = ~160M total. At ~1µs per candidate (JS keccak + bit-field check), ~160 seconds.

**Time budget:** If the construction time exceeds 60s typical, pin pre-computed rngWords as test constants via REF-CAPTURE protocol — print `[REF-CAPTURE] WORST_CASE_RNG_WORDS = [...]` on first run; inline the literals on subsequent runs. Document the strategy in NatSpec.

**NO statistical fallback. NO ticketCount=1 fallback** per `feedback_gas_worst_case.md` and D-268-WORSTGAS-01: the test MUST construct the EXACT worst-case state.

### Hero quadrant choice

At M=8, every quadrant matches both color AND symbol. The hero quadrant — whichever of {0..3} it is — necessarily symbol-matches. The per-N M=8 SLOAD jackpot constant `QUICK_PLAY_PAYOUT_N3_M8 = 17_512_324` already encodes the hero-match contribution. The L984 gate `matches >= 2 && matches < 8` is a code-path SKIP optimization (cheaper to short-circuit than to fall through with a no-op multiplier), NOT a semantic carve-out.

**Therefore:** `heroQuadrant = 0` (or any of 0..3) is a valid worst-case choice. Per the D-268-WORSTGAS-01 single-construction discipline, NO separate M=7 sub-case is required.

### ETH tier 3 sizing math

At N=3 M=8, `basePayoutBps = QUICK_PLAY_PAYOUT_N3_M8 = 17_512_324` (centi-x scaled). Payout = `betAmount × 17_512_324 × roiBps / 1_000_000`. With `roiBps = 9_000` (default min ROI at activity score 0): `payout = betAmount × 17_512_324 × 9_000 / 1_000_000 = betAmount × 157_610_916 / 1_000`.

For `betAmount = MIN_BET_ETH = 0.005 ETH = 5e15 wei`: `payout = 5e15 × 157_610_916 / 1_000 = 7.88e20 wei ≈ 788 ETH`. `payout / betAmount ≈ 157,611 >>> 10` → ETH tier 3 triggers trivially.

**Choice for the test:** `betAmount = MIN_BET_ETH = eth(0.005)`. Pool needs to be sized so the cap doesn't bind on the tier-3 case (we want the headline worst-case to exercise the tier-3 lootbox-conversion path, not pool-cap excess flip). Pool ≥ `payout × 10 / ETH_WIN_CAP_BPS = payout × 10 / 1_000 = payout / 100 ≈ 7.88 ETH`. Default `loadFixture` pool funding is far larger (purchase-driven funding lands in the kETH range); cap won't bind.

### Worst-case construction summary

| Dimension | Worst-case value | Source |
|-----------|-----------------|--------|
| N | 3 | `_countGoldQuadrants(0xC0B87838) == 3`; longest dispatch chain |
| M | 8 | result-ticket matches player at all 4 (color, symbol) axes |
| hero | INHERENT at M=8 | per D-268-WORSTGAS-01 + user clarification |
| currency | CURRENCY_ETH (0) | tier 3 path needs ETH currency |
| betAmount | MIN_BET_ETH = 0.005 ETH | sized so payout > 10× bet trivially |
| ticketCount | 10 | MAX_SPINS_PER_BET cap |
| pool size | default (large, kETH range) | cap doesn't bind on the headline test |

**rngWord engineering:** brute-force search per spin × 10 spins; if total exceeds 60s budget, REF-CAPTURE pin discovered rngWords as test constants. NO statistical fallback.

---

*Phase 268 Task 1 — chore inventory complete. Task 2 reads this file as authoritative source-of-truth for the 5-file batched test diff.*
