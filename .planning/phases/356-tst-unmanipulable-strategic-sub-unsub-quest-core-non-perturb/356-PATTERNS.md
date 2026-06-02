# Phase 356: TST — Unmanipulable + Quest-Core Non-Perturbation + Two-Path-Open + Liveness Valve + Gap-Decouple + Gas Marginals + Non-Widening - Pattern Map

**Mapped:** 2026-06-02
**Files analyzed:** 14 (3 NEW fuzz suites + 1 NEW ledger + 2 EXTEND gas harnesses + 10 MIGRATE fuzz files; 2 of the 10 overlap the ADAPT-source list)
**Analogs found:** 14 / 14 (every test-file role has a concrete in-repo analog; zero green-field authoring)

This is a **test-only** phase (ZERO `contracts/*.sol` mutation). The "files to create/modify" are forge `test/` files + one markdown ledger. The shipped contracts listed below are **read-only analogs of the surface under test** — never edited. All file paths are absolute.

---

## File Classification

| New/Modified Test File | Role | Data Flow | Closest Analog | Match Quality |
|------------------------|------|-----------|----------------|---------------|
| `test/fuzz/V56SecUnmanipulable.t.sol` (NEW) | SEC fuzz+repro invariant suite | stateful churn-fuzz + event-driven repro | `test/fuzz/V55RevertFreeEvCap.t.sol` + `test/fuzz/V55SetMutationOpenE.t.sol` | role+flow match (adapt to compute-on-read + pendingBurnie) |
| `test/fuzz/V56FreezeSolvency.t.sol` (NEW) | RNG-freeze + solvency fuzz + byte-diff anchor | freeze-determinism fuzz + solvency invariant | `test/fuzz/V55FreezeDeterminism.t.sol` | exact role; flow adapt (single-roll + STAMP-not-resolve) |
| `test/fuzz/V56QuestNonPerturb.t.sol` (NEW) | quest-core non-perturbation unit+fuzz | cross-contract byte-identity + streak-neutral | `test/fuzz/V55SetMutationOpenE.t.sol` (streak/swap-pop arm) + DegenerusQuests reads | role-match (new boundary; reuse fixture+slot probes) |
| `test/gas/V56AfkingGasMarginal.t.sol` (EXTEND) | gas-ceiling harness + GAS-06 + LIVE-01 + D-06 | per-tx gas marginal + per-advance ceiling | itself (the v56 marginal harness) | exact — EXTEND in place |
| `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` (EXTEND if open-leg cases land here) | open worst-case gas | per-open marginal, uniform O(1) | itself (already uint24-migrated) | exact — already migrated |
| `test/REGRESSION-BASELINE-v56.md` (NEW) | NON-WIDENING ledger (markdown) | doc-only empirical set-diff | `test/REGRESSION-BASELINE-v55.md` | exact — clone structure verbatim |
| `test/fuzz/V55FreezeDeterminism.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | `test/gas/RouterWorstCaseGas.t.sol` @ `08e59a4a` (transform) | exact transform (+ uint96 amount → uint24 + `_setStamp` masks) |
| `test/fuzz/V55RevertFreeEvCap.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | same `08e59a4a` transform | exact transform (+ `_setStamp` masks) |
| `test/fuzz/V55SetMutationOpenE.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | same `08e59a4a` transform | exact transform (+ `OFF_AMOUNT`/`OFF_SCOREPLUS1` re-derive + `_setScorePlus1` mask) |
| `test/fuzz/AfKingConcurrency.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | same `08e59a4a` transform | exact transform |
| `test/fuzz/AfKingFundingWaterfall.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | same `08e59a4a` transform | exact transform |
| `test/fuzz/AfKingSubscription.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | same `08e59a4a` transform | exact transform |
| `test/fuzz/KeeperRouterOneCategory.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | same `08e59a4a` transform | exact transform |
| `test/fuzz/KeeperFaucetResistance.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | same `08e59a4a` transform | exact transform |
| `test/fuzz/KeeperRewardRoutingSameResults.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | same `08e59a4a` transform | exact transform |
| `test/fuzz/KeeperNonBrick.t.sol` (MIGRATE) | fuzz-offset migration | direct-storage Sub-slot probing | same `08e59a4a` transform | exact transform |

**Verified:** `grep -rln 'OFF_LASTBOUGHT *= *21' test/` returns EXACTLY the 10 D-10 files (no other test file carries the stale offset). `V56AfkingGasMarginal` and `KeeperOpenBoxWorstCaseGas` are already at `OFF_LASTBOUGHT=11`/uint24 (`08e59a4a`).

---

## Pattern Assignments

### `test/gas/V56AfkingGasMarginal.t.sol` (EXTEND — gas-ceiling harness, GAS-06 / LIVE-01 / D-06)

**Analog:** itself — the planner EXTENDS this file (D-09 mandates EXTEND, not a new suite). It is the canonical source of the v56 Sub offsets, the marginal idiom, and the driving harness. All excerpts below are verified at `/home/zak/Dev/PurgeGame/degenerus-audit/test/gas/V56AfkingGasMarginal.t.sol`.

**Canonical v56 Sub-slot offset block (lines 68-89) — COPY VERBATIM into every new suite:**
```solidity
uint256 private constant RNG_WORD_BY_DAY_SLOT = 11; // mapping(uint32 => uint256) — afking box DAY-keyed word + readiness gate
uint256 private constant SUBOF_SLOT = 66;           // _subOf mapping root (address => Sub, one packed slot)
uint256 private constant SUBSCRIBERS_SLOT = 68;     // address[] _subscribers (slot holds the length)
uint256 private constant SUBCURSOR_SLOT = 70;       // _subCursor u16@0 + _subOpenCursor u16@2 + _afkingResetDay u32@4
//   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
//   scorePlus1 u16 @6 · amount u24 @8
//   lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20
//   affiliateBase u32 @23 · pendingBurnie u32 @27 · subStreakLatch u8 @31
uint256 private constant OFF_LASTBOUGHT     = 11; // uint24 lastAutoBoughtDay    (bytes 11..13)
uint256 private constant OFF_LASTOPENED     = 14; // uint24 lastOpenedDay        (bytes 14..16)
uint256 private constant OFF_AFKCOVERED     = 17; // uint24 afkCoveredThroughDay (bytes 17..19)
uint256 private constant OFF_AFKINGSTART    = 20; // uint24 afkingStartDay       (bytes 20..22)
uint256 private constant OFF_AFFBASE        = 23; // uint32 affiliateBase        (bytes 23..26)
uint256 private constant OFF_PENDINGBURNIE  = 27; // uint32 pendingBurnie        (bytes 27..30)
uint256 private constant OFF_STREAKLATCH    = 31; // uint8  subStreakLatch       (byte 31; bit7 ever-sub, bits0-6 streak)
uint256 private constant MINTPACKED_SLOT = 10;
uint256 private constant DEITY_SHIFT = 184;
```
NOTE: this harness names the offset block but ALSO carries the v56-canonical accumulator reads `_affiliateBaseOf` (lines 635-637, width 32), `_pendingBurnieOf` (643-645, width 32), `_streakBaseOf` (647-649, byte 31 masked `& 0x7f`), `_afkCoveredOf` (631-633, width 24), `_afkingStartOf` (639-641, width 24) — these are the SEC-01 probe accessors the new fuzz suites need but the v55 analogs lack.

**The MARGINAL idiom (Pattern 1, lines 181-208) — load-bearing, every gas number:**
```solidity
uint256 snap = vm.snapshotState();
uint256 gasN   = _measureStageAdvanceGas(N_HI, "blMhi_", false, false);
vm.revertToState(snap);
uint256 gasNm1 = _measureStageAdvanceGas(N_LO, "blMlo_", false, false);
assertGt(gasN, gasNm1, "...the Nth sub did real work");
uint256 perBuyLootbox = gasN - gasNm1; // loop-N-divide MARGINAL — NEVER a single-item total
```

**The VRF-drain driving harness (lines 579-614) — DON'T hand-roll; fulfill-at-loop-top:**
```solidity
function _settleGame(uint256 vrfWord) internal {
    for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
        if (!game.advanceDue() && !game.rngLocked()) break;
        _fulfillPending(vrfWord);            // fulfill FIRST — a stamping advance leaves rngLocked w/ unfilled word
        if (!game.advanceDue() && !game.rngLocked()) break;
        game.advanceGame();
        _fulfillPending(vrfWord);
    }
}
// _settleClean (594-602): DEMANDS clean before returning — use before a mintBurnie OPEN-leg measure.
// _warpToBoundary (477-487): EXPLICIT accumulating `t` (NOT block.timestamp+1days in a loop — Foundry caching freezes it).
```

**Dual-bound + derived-batch helper (lines 98-103, 164-168) — D-06 ceiling asserts:**
```solidity
uint256 internal constant GAS_TARGET = 10_000_000;            // <10M comfort TARGET
uint256 internal constant EFFECTIVE_GAS_CEILING = 16_700_000; // hard never-exceed (== 16,700,000; D-06 bar is 16,777,216)
function _maxSafeBatch(uint256 fixedOverhead, uint256 perItemMarginal) internal pure returns (uint256) {
    if (perItemMarginal == 0) return 0;
    if (fixedOverhead >= GAS_TARGET) return 0;
    return (GAS_TARGET - 1 - fixedOverhead) / perItemMarginal;
}
```

**REQUIRED FIX before D-06 (Pitfall 1 — HARNESS BUG, not optional):** line 127 declares `SUBSCRIBER_CAP = 500`; the shipped contract is `SUBSCRIBER_CAP = 1000` (`contracts/modules/GameAfkingModule.sol:165`, VERIFIED — note lines 499/505 of the contract carry stale `500` *comments*, but the binding constant on line 165 is 1000). Correct the harness constant to 1000 and re-derive every "at the cap" assertion against 1000 (a 2× under-statement of the worst-case STAGE/open chunk).

**What to ADD (D-06/07/08):**
- A dedicated heavy-state method (its own setup, not a cheap marginal) driving a worst-case multi-day VRF-stall resume; bracket the gap-backfill advance N AND the jackpot advance N+1 SEPARATELY, assert EACH `< 16,777,216` (the per-tx ceiling, not the ~25M total). Budget `block_gas_limit = 30e9` (already `foundry.toml:16`).
- The 4 D-06 residuals (read from `audit/PROOF-V56-16P7M-GAS-CEILING.md` at plan time): (1) level-crossing/gap-rebase iter ≤ its weight allocation; (2) heaviest single `processTicketBatch` entry; (3) mixed-stamp-day OPEN_BATCH spanning 130 DISTINCT stamp days (defeats the `cachedDay`/`cachedWord` short-circuit, `GameAfkingModule:1157-1163`); (4) heaviest reachable per-iter state (max streak hand-back / level crossing) vs the fixture's 5-ETH-sub + deity-pass states.

---

### `test/fuzz/V56SecUnmanipulable.t.sol` (NEW — SEC-01 fuzz + the 4 named repros)

**Analogs:** `/home/zak/Dev/PurgeGame/degenerus-audit/test/fuzz/V55RevertFreeEvCap.t.sol` (fuzz+repro structure, solvency reads) + `/home/zak/Dev/PurgeGame/degenerus-audit/test/fuzz/V55SetMutationOpenE.t.sol` (swap-pop / set-mutation / event-drain). Inherit `DeployProtocol`; copy the v56 offset block from `V56AfkingGasMarginal:68-89` (NOT the stale v55 offsets in these analogs).

**setUp + fixture pattern (from V55SetMutationOpenE.t.sol:69-72):**
```solidity
function setUp() public { _deployProtocol(); vm.warp(block.timestamp + 1 days); }
```

**Funded-sub + deity-pass + new-day STAGE harness (V55SetMutationOpenE.t.sol:386-423; identical in all analogs):**
```solidity
function _runStageNewDay(uint256 vrfWord) internal {   // stamp the funded set + land rngWordByDay[stampDay]
    _settleGame(vrfWord ^ 0xF00D); vm.warp(block.timestamp + 1 days); _settleGame(vrfWord);
}
function _subscribeLootbox(address who, uint8 q) internal { vm.prank(who); game.subscribe(address(0), false, false, q, 0, address(0)); }
function _fundPool(address who, uint256 amount) internal { vm.deal(address(this), amount); game.depositAfkingFunding{value: amount}(who); }
function _grantDeityPass(address who) internal {           // MINTPACKED_SLOT=10, DEITY_SHIFT=184
    bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
    uint256 packed = uint256(vm.load(address(game), slot)); packed |= (uint256(1) << DEITY_SHIFT);
    vm.store(address(game), slot, bytes32(packed));
}
```

**Event-drain helper for finalize/eviction repros (V55SetMutationOpenE.t.sol:491-508) — emitter == address(game):**
```solidity
function _drainLogs() internal {
    Vm.Log[] memory logs = vm.getRecordedLogs();
    for (uint256 i; i < logs.length; i++) {
        if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
        if (logs[i].topics[0] == SUB_EXPIRED_SIG && logs[i].topics.length >= 2) { /* push player+reason */ }
    }
}
```

**The 4 named repros — assert against these VERIFIED shipped anchors:**

1. **Affiliate re-claim churn** — `affiliateBase` PERSISTS across unsub (`GameAfkingModule.sol:315` comment "the accrued `pendingBurnie` (claimable) and `affiliateBase` (upline-pull)"; accrue at `:753-755 sub.affiliateBase = uint32(newBase)`; read-and-zero AFFILIATE-only at `:1303-1304 base = s.affiliateBase; s.affiliateBase = 0`). Repro: sub → accrue → unsub → re-sub repeatedly; assert total drained == honest continuous accrual. Probe `affiliateBase` via `_subField(who, OFF_AFFBASE, 32)`.

2. **Streak decay / gap dodge** — `_afkingStreak` decay-on-read (`GameAfkingModule.sol:778-786`, VERIFIED):
```solidity
uint32 covered = uint32(sub.afkCoveredThroughDay);
if (currentDay == 0 || covered + 1 < currentDay) return 0;   // miss ONE funded day → reads 0
return uint32(_streakBaseOf(sub)) + (covered - uint32(sub.afkingStartDay));
```
   NOTE (Pitfall 3): the read fn is `_afkingStreak` (private) — there is NO `_streakOf`. Assert behavior through the activity-score read / the finalize write + probe the streak latch byte (`_streakBaseOf` = `_subField(who, OFF_STREAKLATCH, 8) & 0x7f`). The decay condition is `covered + 1 < currentDay`.

3. **pendingBurnie double-claim idempotency** — CEI (`GameAfkingModule.sol:1270-1284`, VERIFIED):
```solidity
function claimAfkingBurnie(address[] calldata subs) external {
    for (...) {
        Sub storage s = _subOf[player];
        uint256 owed = uint256(s.pendingBurnie);
        if (owed != 0) { s.pendingBurnie = 0; coinflip.creditFlip(player, owed * 1 ether); } // CEI: zero before credit
    }
}
```
   Repro: double-call in one block / claim→unsub→claim pays EXACTLY once; probe `pendingBurnie` via `_subField(who, OFF_PENDINGBURNIE, 32)`.

4. **4 finalize hooks before slot-delete** — all call `_finalizeAfking` BEFORE the delete/tombstone (VERIFIED `GameAfkingModule.sol`):
   - (A) explicit cancel `subscribe(_,0)`: `:318 _finalizeAfking(subscriber, c, _simulatedDayIndex());` then `:319 c.dailyQuantity = 0;`
   - (B) cancel-reclaim (load-bearing order): `:912 _finalizeAfking(player, sub, processDay);` then `:915 delete _subOf[player]; :916 _removeFromSet(player);`
   - (C) pass-evict: `:952 _finalizeAfking(...)` then `:953 sub.dailyQuantity = 0; :954 _removeFromSet(player);`
   - (D) funding-kill: `:1010 _finalizeAfking(...)` then `:1011 sub.dailyQuantity = 0; :1012 _removeFromSet(player);`
   - `_finalizeAfking` itself (`:799-816`) computes `earned = _streakBaseOf(sub) + (covered - afkingStartDay)`, calls `quests.finalizeAfking(...)`, then zeroes `afkingStartDay` + streak base.

**No-orphan + swap-pop streak-preservation arm** — copy `testStreakNotCorruptedBySwapPop` (V55SetMutationOpenE.t.sol:213-266) and the NO-ORPHAN control/removed pair (`:124-169`). The guard is at `GameAfkingModule.sol:876-881` (a pending-box sub `lastOpenedDay < lastAutoBoughtDay` left entirely untouched).

---

### `test/fuzz/V56FreezeSolvency.t.sol` (NEW — SEC-02 three legs)

**Analog:** `/home/zak/Dev/PurgeGame/degenerus-audit/test/fuzz/V55FreezeDeterminism.t.sol` (the freeze/determinism oracle) + the solvency reads from `V55RevertFreeEvCap.t.sol:46-50` (CLAIMABLE_POOL_SLOT=1 byte 16, AFKING_FUNDING_SLOT=8). Copy the v56 offset block from `V56AfkingGasMarginal:68-89`.

**The materialized-box byte-identity oracle (V55FreezeDeterminism.t.sol:50-72) — the freeze observable:**
```solidity
bytes32 private constant LOOTBOX_OPENED_SIG =
    keccak256("LootBoxOpened(address,uint48,uint32,uint256,uint24,uint32,uint256,bool)");
struct Box { bool present; uint48 lootboxIndex; uint32 day; uint256 amount; uint24 futureLevel; uint32 futureTickets; uint256 burnie; bool roundedUp; }
// Two opens of the SAME stamp at DIFFERENT blocks (vm.roll/warp/prevrandao/coinbase perturbed) → byte-identical Box.
// Seed = keccak256(abi.encode(rngWordByDay[stampDay], player, stampDay, amount)) — carries NO block.* entropy.
```

**Three legs (D-05):**
1. **ETH/claimablePool debit byte-unchanged vs `453f8073`** — a `git diff 453f8073 HEAD -- contracts/` grep/diff anchor recorded in `REGRESSION-BASELINE-v56.md` (NOT a forge assert). The SOLVENCY-01 site is byte-frozen at `GameAfkingModule.sol:744-745` (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue)`). Affiliate/quest rewards are BURNIE flip-credit OFF the ETH path.
2. **Solvency invariant fuzz** — `balance + steth.balanceOf(this) >= claimablePool` across churn/accrue/claim. Read `claimablePool` per `V55RevertFreeEvCap.t.sol:46-47` (slot 1, offset 16 bytes, uint128). Class-B fail-loud pattern: `testClassB_StageDebitSolvencyFailsLoud` (V55RevertFreeEvCap.t.sol:196).
3. **RNG-freeze determinism fuzz** — the subscribe min-buy STAMPS-for-later-open (never inline-resolves pre-RNG), single-roll open, `pendingBurnie` credit all consume ONLY the frozen `rngWordByDay[stampDay]`. Adapt the two-block determinism test `testStampedDayDeterminismOpenAtTwoBlocks` (V55FreezeDeterminism.t.sol:91+) — the afking open is reached via `mintBurnie()` (the `autoOpen` selector collision means the afking open is NOT re-exposed on the Game).

---

### `test/fuzz/V56QuestNonPerturb.t.sol` (NEW — QST-04, D-04)

**Analog:** the swap-pop/streak arm of `V55SetMutationOpenE.t.sol` (fixture + Sub reads) + direct DegenerusQuests state reads. New cross-contract boundary; reuse the funded-sub harness above.

**Shipped DegenerusQuests anchors (VERIFIED `contracts/DegenerusQuests.sol`):**
```solidity
// beginAfking(player, currentDay) :432 — sets state.afkingActive = true (:441), returns snapshot streak; does NOT touch slot-1.
// awardQuestStreakBonus(player, uint16 amount, uint32 currentDay) :378 onlyGame — the shared manual/bingo/degenerette/boon caller.
// afkingActive flag :283 — "While set: slot-0 completions are streak-neutral and pay no immediate reward".
// finalizeAfking(player, uint24 earnedStreak, uint32 afkingCoveredDay, uint32 currentDay) :463 onlyGame (VERIFIED :463-483):
function finalizeAfking(...) external onlyGame {
    if (player == address(0)) return;
    PlayerQuestState storage state = questPlayerState[player];
    if (!state.afkingActive) return;                                 // idempotent (cancel-then-reclaim safe)
    uint32 lastValid = afkingCoveredDay;
    if (uint32(state.lastActiveDay) > lastValid) lastValid = uint32(state.lastActiveDay); // manual-mint keeps alive
    uint24 finalStreak = (currentDay == 0 || lastValid + 1 >= currentDay) ? earnedStreak : 0; // funding-kill guard
    state.streak = finalStreak > type(uint16).max ? type(uint16).max : uint16(finalStreak);
    ...
}
```

**Pitfall 4 (funding-kill guard exact boundary):** the guard is `lastValid + 1 >= currentDay` (NOT `<= currentDay-2`). Test BOTH boundary cases explicitly: `lastValid == currentDay-1` → KEPT; `lastValid <= currentDay-2` → ZEROED. `lastValid = max(afkingCoveredDay, state.lastActiveDay)` — a sub that lapsed afking but kept minting MANUALLY (bumping `lastActiveDay`) is NOT wrongly zeroed (D-02.4).

**The two D-04 properties:** (a) slot-1 (player's own random/manual quest) stays fully accessible every day during afking AND is streak-neutral (`afkingActive` gates the bump — a slot-1 completion during afking must NOT advance the compute-on-read streak; for a NON-afking player slot-1 advances normally); (b) `awardQuestStreakBonus` & the manual/bingo/degenerette/boon callers produce byte-identical results with afking subs present vs absent.

---

### `test/REGRESSION-BASELINE-v56.md` (NEW — NON-WIDENING ledger)

**Analog:** `/home/zak/Dev/PurgeGame/degenerus-audit/test/REGRESSION-BASELINE-v55.md` — clone the structure VERBATIM. Sections to reproduce: §1 TST-HEAD arithmetic table; §2 empirical baseline-red union BY NAME (Buckets A/B/F); §3 NEW-vs-baseline deltas (rewrite map / drops / NARROWING — here the §3 delta is the D-10 offset-migration red→green NARROWING); §4 unseeded-`[invariant]` ⊆-gate rationale; §5 new green-proof files; §6 net-zero ⊆-gate PROOF + FC1-FC6 false-confidence guards; §7 scope attestation + Hardhat compile-sanity arm.

**The binding headline (clone the v55 wording, swap the baseline):**
> at the v56 TST HEAD, every `forge test` failing test ∈ the empirically-established `453f8073` baseline red union BY NAME — `live failing set − union == ∅` — net-zero new regression.

**The empirical-checkout method (Pattern 3 — the v56 contract tree DIFFERS from `453f8073`, so re-derive the union, do NOT carry the v55 union):**
```bash
node scripts/lib/patchForFoundry.js              # predict CREATE addrs (no pretest hook)
forge test --json                                # WHOLE tree, NOT --match-path
git checkout -- contracts/ContractAddresses.sol  # restore frozen (sha256 80fe0dac…)
# then: git worktree/stash to 453f8073, patch, forge test --json, parse the failing (suite,test) union BY NAME, restore, return to HEAD
```

**Carry the ⊆ relaxation (Pitfall 5):** `foundry.toml` seeds `[fuzz]` (`seed=0xdeadbeef`) but the `[invariant]` block is UNSEEDED → `DegeneretteBet.inv::invariant_solvencyUnderDegenerette` is flaky → use the SUBSET gate (`live − union == ∅`), NOT strict equality. Enumerate BOTH the forge AND Hardhat suites (v55 was 603/134/16 spanning both). Record the D-10 offset migration's red→green deltas as NARROWING (the `6555125 != 3774873600` garbage-read reds flipping green).

---

## Shared Patterns

### The `08e59a4a` offset-migration transform (D-10 — apply to all 10 stale-offset files)

**Source:** `git show 08e59a4a -- test/gas/RouterWorstCaseGas.t.sol test/gas/SweepPerPlayerWorstCaseGas.t.sol` (the EXACT mechanical fix already validated on the gas suites).
**Apply to:** the 10 D-10 fuzz files (all VERIFIED at stale `OFF_LASTBOUGHT=21`/uint32). The mechanical core:
```
-    uint256 private constant OFF_LASTBOUGHT = 21; // uint32 lastAutoBoughtDay (bytes 21..24)
-    uint256 private constant OFF_LASTOPENED = 25; // uint32 lastOpenedDay     (bytes 25..28)
+    uint256 private constant OFF_LASTBOUGHT = 11; // uint24 lastAutoBoughtDay (bytes 11..13)
+    uint256 private constant OFF_LASTOPENED = 14; // uint24 lastOpenedDay     (bytes 14..16)
...
-        return uint32(_subField(who, OFF_LASTBOUGHT, 32));   // every day-marker read
+        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
-        return uint32(_subField(who, OFF_LASTOPENED, 32));
+        return uint32(_subField(who, OFF_LASTOPENED, 24));
-        return uint32(p & 0xFFFFFFFF);                       // any inline 32-bit mask on a day marker
+        return uint32(p & 0xFFFFFF); // uint24
```
Per-file the full re-pack: day markers (`OFF_LASTBOUGHT`=11, `OFF_LASTOPENED`=14, `OFF_AFKCOVERED`=17, `OFF_AFKINGSTART`=20) all uint24/width-24; accumulators (`OFF_AFFBASE`=23, `OFF_PENDINGBURNIE`=27) uint32/width-32; latch (`OFF_STREAKLATCH`=31) uint8 byte-31; `scorePlus1`=6/uint16; `amount`=8/uint24 (was 9/uint96 in the v55 4-field files). Copy the canonical block from `V56AfkingGasMarginal:68-89`; confirm via `forge inspect DegenerusGame storageLayout` against HEAD.

**EXTRA care for 3 of the 10 (they are 4-field v55 proofs, NOT bare gas suites):** `V55FreezeDeterminism`, `V55RevertFreeEvCap`, `V55SetMutationOpenE` ALSO have **write helpers** that mask the OLD layout and MUST be migrated in lockstep:
- `V55FreezeDeterminism._setStamp` (lines 422-429) masks `OFF_SCOREPLUS1` u16 + `OFF_AMOUNT` u96 + `OFF_LASTBOUGHT`/`OFF_LASTOPENED` u32 → re-mask to `amount` uint24@8 + markers uint24.
- `V55RevertFreeEvCap` stamp-write (lines 561-566) same.
- `V55SetMutationOpenE` has `OFF_AMOUNT=9 (uint96)` / `OFF_SCOREPLUS1=7 (uint16)` (lines 54-55) + `_setScorePlus1` (473-479) masking byte 7 → re-derive to `scorePlus1`@6, `amount`@8/uint24. (Its `OFF_DAILY=0`/`OFF_VALIDTHROUGH=1` are unchanged.)
A pure offset constant swap is sufficient for the 7 keeper/afking files (read-only probes); the 3 v55 proofs need the write-mask shift too.

### CEI-before-credit (the idempotency/reentrancy anchor)

**Source:** `contracts/modules/GameAfkingModule.sol:1277` (`s.pendingBurnie = 0;` precedes `coinflip.creditFlip(...)`).
**Apply to:** SEC-01 repro 3 (`V56SecUnmanipulable`). `creditFlip` recordAmount makes reentrancy a non-issue; the property is "pays exactly once".

### Sub-slot direct-storage probing (`_subField`)

**Source:** `V56AfkingGasMarginal.t.sol:618-621` (the v56-correct width usage).
**Apply to:** every new fuzz suite + every migrated file.
```solidity
function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
    uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
    return p & ((uint256(1) << widthBits) - 1);
}
```

### Two-path open coexistence (LIVE-01 — no shared-mutable-state hazard)

**Source:** `V55SetMutationOpenE.t.sol:82-116` (`testTwoPathOpenCoexistenceNoCrossCorruption`) + the shipped valve `DegenerusGame.sol:1800-1819` (afking-first `drainAfkingBoxes(maxCount)` via delegatecall, then `_openHumanBoxes(maxCount - openedAfking)`).
**Apply to:** `V56AfkingGasMarginal` (LIVE-01 cases) and/or a coexistence test. Assert (Pitfall 7): (a) afking-first ordering (exhaust afking backlog, human leg consumes only the remainder); (b) repeated bounded `openBoxes(maxCount)` advance BOTH `_subOpenCursor` (slot 70 byte 2) AND `boxCursor` until both drain; (c) `lastOpenedDay` monotone no-double-open (the skip is `GameAfkingModule.sol:1154 if (sub.lastOpenedDay >= stampDay) continue;`); (d) `drainAfkingBoxes` called directly on the module address hits empty storage (selector isolation — reached ONLY via the Game delegatecall; the dead `autoOpen` was dropped in `86a2d6c8`).

### GAS-06 gap/jackpot decouple (idempotent resume)

**Source:** `contracts/modules/DegenerusGameAdvanceModule.sol:369-372` (`if (gapDays != 0) { stage = STAGE_GAP_BACKFILLED; break; }`, `STAGE_GAP_BACKFILLED = 12` @:81) + `rngGate:1262` idempotency (`:1271 if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);`; `:1284 if (day > idx + 1 && rngWordByDay[idx + 1] == 0) { ... purchaseStartDay += gapCount; gapDays = gapCount; }`).
**Apply to:** `V56AfkingGasMarginal` (GAS-06). Assert (D-07): advance N sets `STAGE_GAP_BACKFILLED` + pays NO jackpot; advance N+1 pays the day's jackpot with the SAME frozen word; `rngGate` returns `gapDays == 0` on re-entry; `dailyIdx` NOT advanced so `advanceDue()` stays true; `purchaseStartDay` bumped EXACTLY ONCE; no double jackpot / no skipped day.

---

## No Analog Found

None. Every file role has a concrete in-repo analog (the phase is EXTEND + ADAPT + MIGRATE, not green-field). The only "net-new" property surfaces (QST-04 quest-core non-perturbation; the per-tx gap-resume per-advance ceiling) reuse existing fixture + harness + slot-probe patterns and assert against verified shipped anchors — no RESEARCH.md fallback pattern is needed.

---

## Metadata

**Analog search scope:** `test/fuzz/`, `test/gas/`, `test/*.md`, `contracts/modules/GameAfkingModule.sol`, `contracts/modules/DegenerusGameAdvanceModule.sol`, `contracts/DegenerusGame.sol`, `contracts/DegenerusQuests.sol`, `git show 08e59a4a`.
**Files scanned:** ~30 (the full `test/fuzz` + `test/gas` listing, 6 read in full/region, 4 shipped contracts at line anchors, the `08e59a4a` migration diff).
**Key facts verified this session:** `SUBSCRIBER_CAP = 1000` (`:165`, harness has stale 500); the 4 finalize hooks at `:318/:912/:952/:1010` all precede delete; CEI at `:1277`; decouple at `:369-372`; valve at `:1800-1819`; `finalizeAfking` funding-kill guard `lastValid + 1 >= currentDay` (`:474`); the 10 D-10 files all at stale `OFF_LASTBOUGHT=21` (and no other test file is).
**Pattern extraction date:** 2026-06-02
