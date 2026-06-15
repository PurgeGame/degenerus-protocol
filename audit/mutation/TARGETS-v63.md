# Mutation Campaign — Fix-Site / Spine Target Ledger (v63 subject `a8b702a7`)

**Subject (byte-frozen):** `a8b702a7` — contracts tree-hash
`2934d3d8987a09c5f073549a0cb499f6c5f28620` (`git rev-parse a8b702a7:contracts`).
`git diff a8b702a7 -- contracts/` empty throughout; the harness only ever mutates
source TRANSIENTLY (in-place edit + restore trap), never a persistent edit.

**What this ledger is.** The authoritative target set for the corrected mutation
campaign: the v63-CHANGED + solvency/RNG/packing-SPINE functions (NAMED, not
all-files), each paired with the COMPREHENSIVE green-baseline oracle tests that
genuinely EXERCISE it (the 388-02 ORACLE-HOLES EXERCISED ledger). Line numbers
re-grep-confirmed at the subject.

---

## Why fix-site/spine scope, NOT all-files (MUT-01)

The prior harness (`audit/mutation/run-campaign.sh`) ran an ALL-FILES sweep against
a NARROW per-file oracle (`forge test --match-contract <one regex>`). That produced
mostly FALSE survivors — the documented mutation-oracle mistake: a survivor is FALSE
when the oracle never executes the mutated line.

- `DegenerusVault` DONE `uncaught=418` — the oracle (`V62Redemption|...`) never calls
  most of the file (`PROGRESS.log:20`).
- `BitPackingLib` DONE `uncaught=63` — many survivors are constant-replacement
  mutations on `MASK_16`/`MASK_24` etc. that the narrow `StorageFoundation|V61Pack|
  PrecisionBoundary` set never drives through the masked-RMW path
  (`BitPackingLib.log`, `PROGRESS.log:7`).
- `JackpotBucketLib` DONE `uncaught=275`, multi-hour each.

The all-contracts run is the documented LONG-POLE (14,543s for ONE library), and the
8-agent FOUNDATION surface map proved **0 HIGH on inspection** — so the highest-signal
mutation targets are the CHANGED + SPINE functions, mutated against an oracle that
actually runs them. This ledger scopes exactly those. Survivors under THIS harness are
quantified blind spots in the highest-value surface, not oracle artifacts.

**Spine class (USER-locked threat weighting):** RNG/freeze = DOMINANT · solvency =
SPINE · packing identity = the storage-packing-breaks-slot landmine class. Gas-DoS
in the advanceGame chain (the other HIGH) is a measurement, not a mutation target.

---

## The COMPREHENSIVE oracle (the union — `oracle-comprehensive.sh`)

The oracle is the UNION of the 388-02 EXERCISED green-baseline tests across all four
target groups, run once as a single `forge test` (via `--match-path` per file), so
every mutated target line is executed by at least one oracle test. It is NOT a narrow
per-file `--match-contract` regex. `--no-match-contract VRFPath` keeps the bucket-A
run-variance suite out (per the green baseline). via_ir is inherited from
`foundry.toml [profile.default]` (NOT overridden — the `lite` profile would drop it).

| Oracle test (`--match-path`) | 388-02 verdict | Exercises (which target group) |
|---|---|---|
| `test/invariant/RedemptionAccounting.t.sol` | EXERCISED (#3) | G1 sStonk redemption per-(player,day) accounting |
| `test/fuzz/RedemptionStethFallback.t.sol` | EXERCISED (#4, 10/10 branch-proofs) | G1 claim-split + dust-forfeit + segregation-release legs + CEI |
| `test/fuzz/StakedStonkRedemption.t.sol` | EXERCISED (#9) | G1 per-function redemption post-conditions + narrowing casts |
| `test/fuzz/invariant/EthSolvency.inv.t.sol` | EXERCISED game-side (#5) | G1/G3 `balance >= obligations` master invariant |
| `test/fuzz/invariant/PoolConservation.inv.t.sol` | EXERCISED falsifiable (#6) | G3 4-pool conservation under the delta-fold |
| `test/fuzz/StorageFoundation.t.sol` | EXERCISED (#tail-pack 25/25) | G4 BitPackingLib / packing-helper tail-pack canary |
| `test/fuzz/V61Pack.t.sol` | EXERCISED | G4 packed-field round-trip pokes |
| `test/fuzz/PrecisionBoundary.t.sol` | EXERCISED | G4 narrowing-cast boundary |
| `test/fuzz/BurnieEmissionSeeds.t.sol` | EXERCISED (#7, 5/5) | G2 seed schedule + latch + VAULT claim + `processCoinflipPayouts` |
| `test/fuzz/CoinflipCarryClaim.t.sol` | EXERCISED | G2 `claimCoinflipCarry` partial/cap/loss-zero/compounding |
| `test/repro/DecimatorOffsetIsolation.t.sol` | EXERCISED (#8, 1/1) | G3 terminal-offset `[lvl+1]` + uint32 claim-seed path |
| `test/fuzz/invariant/RngWindowFreeze.inv.t.sol` | EXERCISED falsifiable (#1) | G3 in-window freeze over the repacked RNG slots |

---

## Target group 1 — StakedDegenerusStonk (standalone CALL)

Slither contract name: `StakedDegenerusStonk` (`contracts/StakedDegenerusStonk.sol:97`).
Class: SOLVENCY SPINE + v63-CHANGED (the redemption claim-split rework + slot-0 packing).

| Target function | Line (subject) | Rationale | Exercising oracle test(s) |
|---|---|---|---|
| `_claimRedemptionFor(address,uint24,uint16,bool)` | 821 | The claim-split heart: direct/lootbox/dust-forfeit legs + `_pendingRedemptionEthValue -= totalRolledEth` release (B1/B2/B5) | RedemptionStethFallback · RedemptionAccounting · StakedStonkRedemption |
| `claimRedemption(address,uint24)` | 771 | Permissionless live claim; `gameOver()` read-once snapshot (CF-1) | RedemptionAccounting · StakedStonkRedemption |
| `claimRedemptionMany(address[],uint24)` | 787 | Batch skip-empty + keeper BURNIE bounty (B3) | RedemptionAccounting · StakedStonkRedemption |
| `previewClaimCoinflips` / `redeemBurnieShare` | 69 / 71 | sDGNRS BURNIE backing waterfall (carry-strand surface FA-1) | StakedStonkRedemption · BurnieEmissionSeeds |
| dust-forfeit + segregation-release legs inside `_claimRedemptionFor` | 845-903 | `creditRedemptionDirect{value}(address(this), forfeitEth)` self-credit reconciliation (CF-2) | RedemptionStethFallback |
| `uint96`/`uint128` narrowing-cast writes on `_pendingRedemptionEthValue` / `_totalSupply` | 854 / supply burns | silent-truncate cast on a checked result (FA-2) | PrecisionBoundary · StakedStonkRedemption |

## Target group 2 — BurnieCoinflip (standalone CALL)

Slither contract name: `BurnieCoinflip` (`contracts/BurnieCoinflip.sol:46`).
Class: v63-CHANGED (the seed-stake emission rework) + RNG-adjacent (carry RNG-lock).

| Target function | Line (subject) | Rationale | Exercising oracle test(s) |
|---|---|---|---|
| `processCoinflipPayouts` | 789 | seed→arm handoff, sDGNRS auto-claim vs carry latch (§1.2) | BurnieEmissionSeeds |
| `claimCoinflipCarry` | 754 | settle-then-pay carry withdrawal, RNG-lock gated (§1.3) | CoinflipCarryClaim |
| `_claimCoinflipsInternal` | 394 | the 365/1460 resolution-walk + day-window skip math | CoinflipCarryClaim · BurnieEmissionSeeds |
| `redeemBurnieShare` | 940 | consume waterfall (held balance + claimableStored) | StakedStonkRedemption · BurnieEmissionSeeds |
| `_setFlipStake` / `_flipStake` | 1079 / 1072 | 2-days/slot 128-bit lossless wei lane masked RMW (§1.6) | BurnieEmissionSeeds |
| `_storeDayResult` / `_dayResult` | 1099 / 1092 | 8-bit 3-state day-result lane (win∈[50,156], `b>=50`) (§1.5) | BurnieEmissionSeeds · CoinflipCarryClaim |

## Target group 3 — delegatecall-shared modules (Decimator + Lootbox redemption legs)

Slither contract names: `DegenerusGameDecimatorModule`
(`contracts/modules/DegenerusGameDecimatorModule.sol:20`) and
`DegenerusGameLootboxModule` (`contracts/modules/DegenerusGameLootboxModule.sol:39`).
Both inherit `DegenerusGameStorage`. Class: RNG DOMINANT (uint32 claim seed, lootbox
seed domain-separation) + SOLVENCY SPINE (redemption credit legs) + v63-CHANGED.

| Target function | Contract / line | Rationale | Exercising oracle test(s) |
|---|---|---|---|
| `claimDecimatorJackpot(address,uint24)` | Decimator / 293 | permissionless claim, value→winner only (E1) | DecimatorOffsetIsolation |
| `claimDecimatorJackpotMany` | Decimator / 325 | batch skip-non-winner + keeper bounty (E2) | DecimatorOffsetIsolation |
| `_creditDecJackpotClaimCore` | Decimator / 449 | claim-time lootbox draw seeded by uint32 `rngWord` (E3/E5) | DecimatorOffsetIsolation · RngWindowFreeze |
| terminal-offset `[lvl+1]` keying | Decimator / ~1014-1108 | DEC-ALIAS fix — never alias a live regular round `[lvl]` (E4) | DecimatorOffsetIsolation |
| `creditRedemptionDirect(address,uint256)` body | Lootbox / 1004-1015 | new game-side redemption credit leg (msg.value + stETH pull + claimablePool) (C1) | RedemptionStethFallback · EthSolvency |
| `resolveLootboxDirect` seed | Lootbox / 874 | seed dropped `amount` → `hash2(rngWord, uint160(player))`; caller domain-separation now load-bearing (FC-391-01) | RngWindowFreeze |
| `_applyEvMultiplierWithCap` (the `lootboxEvCapPacked` two-window eviction) | Lootbox / 474 | per-level 10 ETH EV-benefit cap; eviction must not zero a live window (FA-1) | PoolConservation · RedemptionStethFallback |

## Target group 4 — packing helpers (BitPackingLib + DegenerusGameStorage)

Slither contract names: `BitPackingLib` (`contracts/libraries/BitPackingLib.sol:27`,
a library) and `DegenerusGameStorage` (`contracts/storage/DegenerusGameStorage.sol:120`,
abstract). Class: PACKING IDENTITY (the storage-packing-breaks-slot landmine class);
a masked-RMW defect here corrupts a co-resident field silently (compile stays green).

| Target function | Contract / line | Rationale | Exercising oracle test(s) |
|---|---|---|---|
| `setPacked(data,shift,mask,value)` | BitPackingLib / 104 | the masked-RMW primitive `(data & ~(mask<<shift)) \| ((value&mask)<<shift)` + the `MASK_*` constants | StorageFoundation · V61Pack · PrecisionBoundary |
| `_debitClaimableAndAfking` | Storage / 951 | per-half claimable/afking borrow guards (low-half borrow + oversized-afking `<<128` truncation closed) (#14) | EthSolvency · PoolConservation · RedemptionAccounting |
| `_addLevelDgnrsClaimed` | Storage / 1160 | high-half `<<128` accumulator, no uint128 clamp (relies on caller `claimed<=allocation`) (FC-389-07) | StorageFoundation · V61Pack |
| `_setLevelDgnrsAllocation` | Storage / 1151 | preserves the claimed half via mask while writing allocation | StorageFoundation · V61Pack |
| `_lootboxEvUsedFor` / `_setLootboxEvUsedFor` (the `lootboxEvCapPacked` set/get/evict) | Storage / 1698 / 1712 | the two-window read + eviction-discards-smaller-level logic (FA-1 / FC-389-01) | PoolConservation · RedemptionStethFallback |

---

## Fix-site order (smallest / highest-signal first — pacing)

`run-campaign-v63.sh` drives `run_target` in this order so results land early and a
5h cap never strands the whole campaign:

1. `BitPackingLib` + `DegenerusGameStorage` (the packing helpers — smallest, highest identity-signal)
2. `StakedDegenerusStonk` (the redemption solvency spine)
3. `BurnieCoinflip` (the emission rework)
4. `DegenerusGameLootboxModule` + `DegenerusGameDecimatorModule` (the delegatecall-shared long tail)

---

## Exclusion rationale (recorded for the sweep)

This is the fix-site/spine scope, NOT all-files. Excluded by design: unchanged
non-spine surface (the 0-HIGH-on-inspection FOUNDATION verdict), the gas-DoS
advanceGame chain (a measurement target, not a mutation target), and the pure
view/ABI getters (mutating a getter the oracle never reads is itself a false-survivor
generator). The prior all-files survivors (`DegenerusVault` 418, `JackpotBucketLib`
275) are NOT re-run here — they were narrow-oracle artifacts, and `DegenerusVault`'s
solvency-relevant legs are covered through the redemption oracle on the sStonk side.
