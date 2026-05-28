# Phase 335: IMPL — The ONE Batched Contract Diff (WHALE + AFSUB + MINTDIV) - Pattern Map

**Mapped:** 2026-05-28
**Audit baseline:** v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` (working tree under `contracts/` is byte-identical to `b0511ca2`).
**Files in diff:** 5 contracts + 8 tests = 13 files.
**Analogs found:** 13/13 (all in-repo). The CONVERGENCE story is load-bearing: every "new" surface this phase introduces has an in-repo writer/reader/caller to mirror verbatim — there is no greenfield code.

---

## 0. The convergence posture (read before everything else)

The Phase-334 SPEC's headline (D-20) is that **`claimWhalePass` / `whalePassClaims` / `_queueTicketRange` / `_applyWhalePassStats` ALL ALREADY EXIST** at `b0511ca2`. WHALE-01's job is to **route the LootboxModule box-open boon onto the existing machinery** — not to author a parallel system. Therefore the per-file "analog" for almost every WHALE surface is **literally another writer of the SAME slot**, not a similar-looking writer elsewhere. The pattern map below cites those exact siblings.

The same posture holds for the AFSUB cluster: the `validThroughLevel` per-iter check has the **same shape** as the existing `paidThroughDay <= today` per-iter check it replaces (`AfKing.sol:630`); the refresh-or-evict crossing reuses the **existing** `setDailyQuantity(0)` tombstone + `_autoBuy:605` swap-pop reclaim — no new eviction infra. And MINTDIV's one-liner is **literally** a copy of the reference advance arithmetic 200 lines above it in the same file.

**Pitfalls to surface up-front** (each is a "wrong pattern would compile but break a locked decision"):

| # | Pitfall | Source | Right pattern |
|---|---------|--------|---------------|
| P1 | Introduce a `pendingWhalePasses[...]` parallel map alongside `whalePassClaims` | D-20 in `334-CONTEXT.md` / `334-DESIGN-LOCK-WHALE-MINTDIV §1`; `D-IMPL-01` posture | **MIRROR** `whalePassClaims[winner] += ...` from `PayoutUtils.sol:52` / `JackpotModule.sol:1410` — the storage IS the existing map. |
| P2 | Add `if (gameOver) revert` to `claimWhalePass:1018` for D-23 (gameOver-forfeit) | D-IMPL-01 (`335-CONTEXT.md`) | **DO NOT TOUCH** `claimWhalePass`. `_livenessTriggered:1213` enforces forfeit by structural transitivity. A redundant `gameOver` guard is wasted gas AND a freeze-floor signal that the structural argument is fragile. |
| P3 | Move `_applyWhalePassStats` calls in `WhaleModule:1032` or `DecimatorModule:588` to claim-time too | D-04 / `334-GREP-ATTESTATION.md §1` drift-correction #3 | **DO NOT TOUCH** those two callers. Only the `LootboxModule:1247` caller (box-open) moves; the other two stay immediate-apply. |
| P4 | Pre-derive an `OPEN_BATCH = ⌊16.7M / 89_000⌋` ceiling value | D-IMPL-04 (`335-CONTEXT.md`) | The value is **picked from the measured `KeeperOpenBoxWorstCaseGas` figure** with ≥1-box headroom. Use the harness as the picker. |
| P5 | Add a proactive `refreshPass()` entrypoint | D-10 / `334-DESIGN-LOCK-AFKING §5.3` | Lazy-only refresh at the crossing (`_autoBuy:630-631` rewrite) is sufficient. |
| P6 | Mid-sweep direct `_removeFromSet` for pass eviction without going through `setDailyQuantity(0)` tombstone + `_autoBuy:605` reclaim | D-12 / `334-DESIGN-LOCK-AFKING §6.3`; memory `afking-cancel-tombstone-streak-finding` | **Route eviction through the existing tombstone path.** A direct removal mid-sweep re-opens H-CANCEL-SWAP-MISS. |
| P7 | Drop the `{value:}` forwarding or the per-player try/catch on `batchPurchase` to "save gas" | `v49-phase331-rescope-keeper-buy-gas` in MEMORY.md (DEAD — `delegatecall` preserves msg.value but the inner mint READS it; R5 day-rollover revert cannot be pre-validated) | This phase is NOT a gas pass. Touching the buy path is OUT of scope. |
| P8 | Re-anchor the new `lazyPassHorizon` view return type to `uint32` because `Sub.paidThroughDay` is `uint32` | D-11 Claude's Discretion / `334-DESIGN-LOCK-AFKING §3.2` | `level` is `uint24`; the deity sentinel is `type(uint24).max`. Width of the stored field is the planner's call but the view returns `uint24`. |

---

## 1. File Classification

| File | Role | Data Flow | Closest Analog | Match Quality | Touch type |
|------|------|-----------|----------------|---------------|------------|
| `contracts/storage/DegenerusGameStorage.sol` | storage / shared utility | — | n/a (CONFIRM-ONLY — no edit) | exact | confirm |
| `contracts/DegenerusGame.sol` | facade (delegatecall router + view) | request-response | `hasAnyLazyPass:1520` (for new `lazyPassHorizon` view); existing autoOpen at `:1687` (for the WHALE-03 retirement) | exact | add view + delete autoOpen weighting |
| `contracts/modules/DegenerusGameLootboxModule.sol` | module-writer | event-driven (box-open → record) | `DegenerusGamePayoutUtils.sol:52` `_queueWhalePassClaimCore` (WHALE-01 mirror); `DegenerusGameJackpotModule.sol:1410` (second `+=` writer) | **exact (same storage slot)** | replace 100-loop with O(1) `+=` |
| `contracts/modules/DegenerusGameMintModule.sol` | module-reader (LCG advance) | batch / transform | `processFutureTicketBatch:393` with `processed += take:502` (same file, 200 lines above) | **exact (same file, same operation)** | one-liner `>>1` → `+= take` |
| `contracts/AfKing.sol` | keeper (subscription/cursor sweep) | event-driven | self (existing `paidThroughDay <= today` per-iter shape at `:630`; existing `setDailyQuantity(0)` reclaim at `:458`/`:605`) | **exact (in-place repurpose)** | delete + rewrite (largest blast radius in the diff) |
| `contracts/BurnieCoin.sol` | token (BURNIE) | CRUD (mint/burn) | `onlyGame`/`onlyVault` modifier siblings at `:535`/`:542` (deletion pattern: drop the `onlyAfKing:549` modifier the same way the others are kept) | role-match (deletion symmetry) | delete `burnForKeeper` + event + modifier |
| `test/fuzz/AfKingSubscription.t.sol` | test (fuzz, AfKing semantics) | request-response | self (the existing pass-OR-pay test bodies at `:79-129` migrate to pass-eviction tests in-place) | exact | rewrite (the heaviest test migration) |
| `test/fuzz/AfKingFundingWaterfall.t.sol` | test (fuzz, OPEN-E + funding) | request-response | self (OPEN-E `fundingSource` 4-protection assertions stay; pass-eviction is the new branch) | exact | rewrite (+ assert pass-eviction-preserves-tombstone) |
| `test/fuzz/AfKingConcurrency.t.sol` | test (fuzz, swap-pop invariant) | event-driven | self (v49 swap-pop `membership ⟺ packed != 0` invariant assertions stay) | exact | rewrite (rebase `paidThroughDay` writes to `validThroughLevel`) |
| `test/fuzz/KeeperNonBrick.t.sol` | test (fuzz, no-brick) | event-driven | self (existing `paidThroughDay` no-brick scenarios) | exact | small rewrite (H-CANCEL-SWAP-MISS class assertion under pass-eviction) |
| `test/fuzz/RngFreezeAndRemovalProofs.t.sol` | test (fuzz, RNG freeze) | event-driven | self (existing freeze-write assertions); cite `334-WHALE04-FREEZE-PROOF.md` write-set map | exact | trivial assertion rewrite (defer freeze fuzz to 336/TST-01) |
| `test/gas/KeeperLeversAndPacking.t.sol` | test (gas, packing oracle) | batch | self (existing `_structFieldBytes(... "uint32 paidThroughDay;" ...)` packing oracle at `:229`) | exact | rename oracle to `validThroughLevel`; drop the `burnForKeeper(` byte-presence assertion at `:297` |
| `test/gas/RouterWorstCaseGas.t.sol` | test (gas, autoOpen budget) | batch | self (existing `OPEN_NORMAL_GAS_UNIT` mirror at `:121`; `weighted` budget assertions across the file) | exact | drop gas-weighted assertions; re-target to flat `OPEN_BATCH` measured per D-IMPL-04 |
| `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` | test (gas, OPEN_BATCH picker) | batch | n/a (HARNESS RE-RUN ONLY — already measures the right thing) | exact | **NO code change**; re-run produces the new uniform-cost figure that picks flat OPEN_BATCH |

---

## 2. Pattern Assignments

### 2.1 Step 1 — `contracts/storage/DegenerusGameStorage.sol` (confirm-only)

**Analog:** the storage decl IS the producer; `_applyWhalePassStats:1111` and `_queueTicketRange:647` stay UNCHANGED.

**Slot to confirm exists** (lines 953-956):

```solidity
// contracts/storage/DegenerusGameStorage.sol:955
mapping(address => uint256) internal whalePassClaims;
```

**Liveness gate (the structural guard for D-IMPL-01 — the gameOver-forfeit attestation)** (lines 1213-1222):

```solidity
function _livenessTriggered() internal view returns (bool) {
    if (lastPurchaseDay || jackpotPhaseFlag) return false;
    uint24 lvl = level;
    uint32 psd = purchaseStartDay;
    uint32 currentDay = _simulatedDayIndex();
    if (lvl == 0 && currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS) return true;
    if (lvl != 0 && currentDay - psd > 120) return true;
    uint48 rngStart = rngRequestTime;
    return rngStart != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD;
}
```

**Reused `_applyWhalePassStats` (UNCHANGED)** (lines 1111-1134, the delta-based no-double-dip head):

```solidity
function _applyWhalePassStats(
    address player,
    uint24 ticketStartLevel
) internal {
    uint256 prevData = mintPacked_[player];
    uint24 frozenUntilLevel = uint24(
        (prevData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24
    );
    // ... delta-based extension ...
    uint24 targetFrozenLevel = ticketStartLevel + 99;
    uint24 newFrozenLevel = frozenUntilLevel > targetFrozenLevel ? frozenUntilLevel : targetFrozenLevel;
    // ...
}
```

**Pattern action:** no edit. Confirm `whalePassClaims` (line 955) is reachable from the LootboxModule write site (Step 3). Confirm `_livenessTriggered` (line 1213) is reachable from `claimWhalePass:1019` (Step 2 — but `claimWhalePass` itself is untouched per D-IMPL-01). Confirm `_applyWhalePassStats` (line 1111) is reachable from BOTH the now-deleted LootboxModule call AND the two preserved immediate-apply callers (`WhaleModule:1032`, `DecimatorModule:588`).

### 2.2 Step 2 — `contracts/DegenerusGame.sol` (facade — add view, retire autoOpen weighting)

**Analog for the new `lazyPassHorizon` view:** `hasAnyLazyPass:1520` — same packed-read shape, just returns the level instead of a bool.

**Imports / shape pattern** (lines 1515-1528, the immediate sibling the new view lives alongside):

```solidity
// contracts/DegenerusGame.sol:1520 — the boolean today; the new view mirrors its packed-read shape
function hasAnyLazyPass(address player) external view returns (bool) {
    uint256 packed = mintPacked_[player];
    if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return true;
    uint24 frozenUntilLevel = uint24(
        (packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24
    );
    return frozenUntilLevel > level;
}
```

**Settled new view shape** (recommended; final name/width is Claude's Discretion per 334-DESIGN-LOCK-AFKING §3.2):

```solidity
// new in DegenerusGame.sol alongside hasAnyLazyPass:1520; exposed via IGame (AfKing.sol:35)
function lazyPassHorizon(address player) external view returns (uint24) {
    uint256 packed = mintPacked_[player];
    if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return type(uint24).max;
    return uint24((packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24);
}
```

- **Pattern action:** add the view AS A SIBLING to `hasAnyLazyPass` (do not delete `hasAnyLazyPass` — other callers may exist; the AfKing migration replaces only AfKing's two reads at `:432`/`:631`). Add it to the `IGame` iface AfKing reads (the iface lives at `AfKing.sol:18-43`).
- **Pitfall guard P8:** the view returns `uint24` even if the IMPL planner picks `uint32` for the stored `validThroughLevel` field. The width of the stored field is independent.

**Analog for the WHALE-03 autoOpen retirement:** the existing `autoOpen:1687` body (the call site of the math being deleted).

**Math to delete** (lines 1561, 1687-1734 — the three load-bearing surfaces):

```solidity
// contracts/DegenerusGame.sol:1561 — DELETE
uint256 private constant OPEN_NORMAL_GAS_UNIT = 90_000;

// :1687 def header (KEEP fn; retire the weighting INSIDE)
function autoOpen(uint256 maxCount) external returns (uint256 opened) {
    if (rngLockedFlag || _livenessTriggered()) return 0;
    // ... cursor walk preamble (KEEP) ...

    // :1711-1730 — the weighted budget loop body (RETIRE the gas-weighting):
    uint256 weighted;
    while (cursor < qlen && weighted < maxCount) {
        // ...
        uint256 g0 = gasleft();                              // DELETE
        _autoOpenBox(index, player);
        uint256 used = g0 - gasleft();                       // DELETE
        unchecked {
            ++opened;
            weighted += used / OPEN_NORMAL_GAS_UNIT;         // DELETE (the :1728 math)
            if (used % OPEN_NORMAL_GAS_UNIT != 0 || used == 0) ++weighted;  // DELETE
        }
    }
    // ...
}
```

**Replacement pattern** (the flat per-count loop guard):

```solidity
// post-WHALE-03: opened-count-only guard (no gas-weighting indirection)
uint256 i;
while (cursor < qlen && i < maxCount) {
    // ... cursor++/skip-already-emptied stays the same ...
    _autoOpenBox(index, player);
    unchecked { ++opened; ++i; }
}
```

- **Pattern action:** delete the `uint256 g0 = gasleft();` measurement and the `weighted += used / OPEN_NORMAL_GAS_UNIT;` math; the loop counter is the count of opens itself. Delete the `OPEN_NORMAL_GAS_UNIT` constant. Update the rejected-but-stale `~5.4M whale-pass box` comment at `:1558`/`:1681-1682` (or delete it — the whale-pass box becomes uniform O(1) per WHALE-01).
- **`claimWhalePass` entrypoint home (Claude's Discretion, D-01):** the function already exists at `WhaleModule:1018`. The planner picks: (a) add a `DegenerusGame.claimWhalePass(address) external` facade fn that delegatecalls `WhaleModule`, or (b) expose `WhaleModule:1018` directly. Both are coherent per `335-CONTEXT.md` Claude's Discretion. **Do not modify the WhaleModule function body itself** — see Pitfall P2.

### 2.3 Step 3 — `contracts/modules/DegenerusGameLootboxModule.sol` (WHALE-01 box-open record)

**Analog (the MIRROR target — IDENTICAL storage slot):** `DegenerusGamePayoutUtils.sol:45-61` `_queueWhalePassClaimCore` — the existing reference O(1) `+=` writer.

**Reference writer pattern** (lines 45-61):

```solidity
// contracts/modules/DegenerusGamePayoutUtils.sol:45-61 — the canonical += writer
function _queueWhalePassClaimCore(address winner, uint256 amount) internal {
    if (winner == address(0) || amount == 0) return;

    uint256 fullHalfPasses = amount / HALF_WHALE_PASS_PRICE;
    uint256 remainder = amount - (fullHalfPasses * HALF_WHALE_PASS_PRICE);

    if (fullHalfPasses != 0) {
        whalePassClaims[winner] += fullHalfPasses;     // :52  ← MIRROR THIS LINE
    }
    if (remainder != 0) {
        unchecked { claimableWinnings[winner] += remainder; }
        claimablePool += uint128(remainder);
        emit PlayerCredited(winner, winner, remainder);
    }
}
```

**Second `+=` writer (also in-repo, confirms the pattern is established):** `JackpotModule.sol:1410`:

```solidity
// contracts/modules/DegenerusGameJackpotModule.sol:1410
whalePassClaims[winner] += whalePassCount;
```

**Existing `_activateWhalePass` to replace** (lines 1240-1261):

```solidity
// contracts/modules/DegenerusGameLootboxModule.sol:1240-1261 — DELETE the body + the helpers
function _activateWhalePass(
    address player
) private returns (uint24 ticketStartLevel) {
    uint24 passLevel = level + 1;
    ticketStartLevel = passLevel;
    _applyWhalePassStats(player, ticketStartLevel);   // :1247 DELETE (D-04 — stats move to claim-time)

    // :1250-1260 — the ~5.4M-gas 100-iter monster DELETE
    for (uint24 i = 0; i < 100; ) {
        uint24 lvl = ticketStartLevel + i;
        bool isBonus = (lvl >= passLevel && lvl <= WHALE_PASS_BONUS_END_LEVEL);
        _queueTickets(
            player,
            lvl,
            isBonus ? WHALE_PASS_BONUS_TICKETS_PER_LEVEL : WHALE_PASS_TICKETS_PER_LEVEL,
            false
        );
        unchecked { ++i; }
    }
}
```

**Bonus-band constants to delete** (lines 205-209 — `:206`/`:208` are doc/blank between the three consts):

```solidity
// :205 KEEP (still used by the existing _queueTicketRange flat shape downstream — verify before deleting)
uint32 private constant WHALE_PASS_TICKETS_PER_LEVEL = 2;
// :207 DELETE — the ≤10 bonus band is DROPPED per D-21
uint32 private constant WHALE_PASS_BONUS_TICKETS_PER_LEVEL = 40;
// :209 DELETE — same band
uint24 private constant WHALE_PASS_BONUS_END_LEVEL = 10;
```

**Replacement pattern (the O(1) record, MIRROR of PayoutUtils:52):**

```solidity
// new _activateWhalePass body — pure O(1) record, no _applyWhalePassStats, no _queueTickets,
// no mintPacked_ write at open. Stats + queue land at claim-time via the existing
// WhaleModule.claimWhalePass:1018.
function _activateWhalePass(address player) private returns (uint24 ticketStartLevel) {
    ticketStartLevel = level + 1;          // KEEP — the caller still emits with this anchor at :1638
    whalePassClaims[player] += grant;      // O(1); the grant is half-pass units
    // grant shape: SETTLED to convergence onto the EXISTING flat per-level shape (D-21):
    //   - drop the bonus band (no 40/lvl ≤10 carve)
    //   - the existing claim materializes via _queueTicketRange(player, startLevel, 100, N, false)
    //     where N is the half-pass count this record contributes (one whale-pass boon = 1 half-pass).
}
```

- **Pattern action:** Replace the entire body of `_activateWhalePass:1240-1261` with the O(1) `+=` and the `ticketStartLevel` assignment (still emitted by the caller's `LootboxWhalePassJackpot` event at `:1638`). Delete the two bonus-band constants at `:207` + `:209`. **Do NOT delete** `WHALE_PASS_TICKETS_PER_LEVEL = 2` at `:205` until you confirm no downstream caller still references it (grep the module + storage).
- **Pitfall guard P1:** do NOT introduce `pendingWhalePasses` — the slot is `whalePassClaims` (Storage:955). The PayoutUtils:52 line is your literal model.
- **The `BOON_WHALE_PASS:378` and the box-open dispatch at `:1635-1639`** are UNTOUCHED — the boon roll still fires; only the activation body changes.

### 2.4 Step 4 — `contracts/modules/DegenerusGameMintModule.sol` (MINTDIV-02 one-liner)

**Analog (the LITERAL copy target — same file, 200 lines above):** `processFutureTicketBatch:393` body's advance at line 502.

**Reference-correct advance pattern** (lines 497-512):

```solidity
// contracts/modules/DegenerusGameMintModule.sol:497-512 — the reference CORRECT advance
uint40 newPacked = (uint40(remainingOwed) << 8) | uint40(rem);
if (newPacked != packed) {
    owedMap[player] = newPacked;
}
unchecked {
    processed += take;                     // :502 ← THIS IS THE ONE-LINER CORRECT SHAPE
    used += writesThis;
}

if (remainingOwed == 0) {
    unchecked { ++idx; }
    processed = 0;
}
```

**Suspect advance to fix** (lines 710-718):

```solidity
// contracts/modules/DegenerusGameMintModule.sol:710-718 — the SUSPECT advance
unchecked {
    used += writesUsed;
    if (advance) {
        ++idx;
        processed = 0;
    } else {
        processed += writesUsed >> 1;      // :716 ← CHANGE TO `processed += take;`
    }
}
```

**Settled one-liner:**

```solidity
// :716 — POST-FIX
processed += take;
```

- **Pattern action:** the one-liner is `processed += writesUsed >> 1` → `processed += take`. NO defensive change anywhere else (D-15 full-dedup REJECTED). **CAREFUL:** the variable name in the `processTicketBatch` loop body must be `take` (or whatever local the budget-slice `take` is named — verify by reading `:700-708` `_processOneTicketEntry` return / the function-scope locals).
- **Verify before edit:** open `:671-718` end-to-end and confirm that `take` is in-scope at `:716` and represents the same per-iter ticket count as `_processOneTicketEntry`'s emit count. If `take` is wrapped/aliased, copy the assignment shape from `:502` verbatim.

### 2.5 Step 5a — `contracts/AfKing.sol` (AFSUB cluster, the caller side)

**Analog for the per-iter check rewrite:** the EXISTING per-iter check at `_autoBuy:630`.

**Existing per-iter shape (preserve)** (lines 619-665, the day-31 branch):

```solidity
// contracts/AfKing.sol:619-665 — the existing per-iter shape (and the crossing branch)
// (1) AlreadyAutoBoughtToday — cheapest SLOAD-only skip.  (KEEP unchanged)
if (sub.lastAutoBoughtDay >= today) {
    emit PlayerSkipped(player, 2);
    unchecked { ++cursor; ++processed; }
    continue;
}

// (2) Day-31 auto-extract branch. The hasAnyLazyPass view fires only here.
if (sub.paidThroughDay <= today) {                           // :630 ← per-iter check (stored-field compare)
    if (IGame(ContractAddresses.GAME).hasAnyLazyPass(player)) {   // :631 ← crossing pass read (ONLY here)
        // FREE active-pass extend — held-harmless reset; clear windowPaid.
        sub.paidThroughDay = today + WINDOW_DAYS;            // :633
        sub.flags &= ~FLAG_WINDOW_PAID;
        emit SubscriptionExtendedFree(player, today);
        didWork = true;
    } else {
        // PAID branch — all-or-nothing burnForKeeper.       // :637-664 ← DELETE the whole PAID branch
        uint256 extractCost = (SUB_COST_ETH_TARGET * PRICE_COIN_UNIT) / mp;
        uint256 burned = IBurnie(ContractAddresses.COIN).burnForKeeper(  // :641 ← DELETE
            sub.fundingSource == address(0) ? player : sub.fundingSource,
            extractCost
        );
        if (burned != extractCost) {
            sub.dailyQuantity = 0;
            sub.flags &= ~FLAG_WINDOW_PAID;
            _removeFromSet(player);
            emit SubscriptionExpired(player, 1);
            // ...
            continue;
        }
        sub.paidThroughDay = today + WINDOW_DAYS;
        sub.flags |= FLAG_WINDOW_PAID;
        emit BurnieAutoExtracted(player, today, extractCost);
        didWork = true;
    }
}
```

**Settled rewrite (per-iter → stored-field level compare; crossing → refresh-or-evict via tombstone):**

```solidity
// contracts/AfKing.sol:630-665 (POST-AFSUB) — preserves the cheap stored-field shape (GASOPT-05)
uint24 currentLevel = IGame(ContractAddresses.GAME).level();  // single SLOAD per autoBuy call (NOT per-iter — hoist out of the loop)
// NOTE: if `level()` is exposed elsewhere on the iface, prefer that. If not, hoist a single read at autoBuy entry.

// non-crossing path: pure stored-field compare, no external pass read
if (currentLevel > sub.validThroughLevel) {
    // CROSSING — re-read horizon EXACTLY ONCE
    uint24 h = IGame(ContractAddresses.GAME).lazyPassHorizon(player);
    if (currentLevel <= h) {
        // REFRESH (the level-denominated analog of the free-extend at :633)
        sub.validThroughLevel = h;
        emit SubscriptionExtendedFree(player, today);  // event name preserved or renamed at planner's discretion
        didWork = true;
    } else {
        // EVICT via the EXISTING tombstone path (mirror the auto-pause shortfall branch at :645-657
        // for the swap-pop semantics, but route through setDailyQuantity(0) tombstone shape):
        sub.dailyQuantity = 0;
        _removeFromSet(player);
        emit SubscriptionExpired(player, 1);   // reason code stays 1 (replaces the burnForKeeper shortfall code 1)
        didWork = true;
        unchecked { ++processed; }
        continue;
    }
}
// otherwise (currentLevel <= sub.validThroughLevel): proceed with the buy unchanged
```

**Subscribe-time encode pattern (replaces the pass-OR-pay block at `:430-443`):**

```solidity
// contracts/AfKing.sol:412-444 — subscribe rewrite

// DELETE :414-416  the anchor math (paidThroughDay-extend-from-endpoint)
// DELETE :424      the s.paidThroughDay = anchor + WINDOW_DAYS; write
// DELETE :430-443  the entire SUB-01 pass-OR-pay gate (interaction-last)
// KEEP   :385-391  SUB-02 self-consent gate (UNTOUCHED)
// KEEP   :393-403  OPENE-04 fundingSource consent gate (UNTOUCHED)

// REPLACE with a single horizon encode:
s.validThroughLevel = IGame(ContractAddresses.GAME).lazyPassHorizon(subscriber);
// no BURNIE charge, no anchor math, no WINDOW_DAYS, no FLAG_WINDOW_PAID write
```

**Existing `setDailyQuantity(0)` reclaim/tombstone (PRESERVED — this IS the eviction mechanism the refresh-or-evict crossing reuses)** (`AfKing.sol:458-468`):

```solidity
// :458-468 — KEEP this setter UNCHANGED; the in-autoBuy reclaim at :605 is what evicts.
function setDailyQuantity(uint8 q) external {
    if (_subscriberIndex[msg.sender] == 0) revert NotSubscribed();
    Sub storage s = _subOf[msg.sender];
    if (q == 0) {
        s.dailyQuantity = 0;     // ← the in-place tombstone (moves no one in the iterable set)
        emit SubscriptionUpdated(msg.sender, 0, ...);
        return;
    }
    s.dailyQuantity = q;
    // ...
}
```

**Existing in-autoBuy reclaim (PRESERVED)** (`AfKing.sol:605-617`):

```solidity
// :605-617 — the in-autoBuy reclaim KEEPER (membership ⟺ packed != 0 invariant load-bearing)
if (sub.dailyQuantity == 0) {
    bool preservePaidWindow = (sub.flags & FLAG_WINDOW_PAID) != 0 && sub.paidThroughDay > today;
    // ↑ NOTE: after AFSUB, FLAG_WINDOW_PAID is freed AND paidThroughDay → validThroughLevel.
    //   Decide AT IMPL: drop the preservePaidWindow branch entirely (every cancel = full delete)
    //   OR repurpose against validThroughLevel (currentLevel <= sub.validThroughLevel == "preserve").
    //   The 334-DESIGN-LOCK-AFKING §6.2 says: reuse THIS PATH unchanged in shape.
    if (!preservePaidWindow) {
        delete _subOf[player];
    }
    _removeFromSet(player);
    emit SubscriptionExpired(player, 2);
    didWork = true;
    unchecked { ++processed; }
    continue;        // ← DOES NOT advance the cursor; the swap-pop occupant gets processed this slot
}
```

**`Sub` struct repurpose** (`AfKing.sol:86-93`):

```solidity
// :86-93 — POST-AFSUB layout (offset 5 reinterpreted in-place)
struct Sub {
    uint8 dailyQuantity;       // offset 0  (UNCHANGED)
    uint32 lastAutoBoughtDay;  // offset 1  (UNCHANGED)
    uint32 validThroughLevel;  // offset 5  ← REPURPOSED (was paidThroughDay; uint32 keeps zero packing churn)
                               //              OR narrow to uint24 if planner picks — see Claude's Discretion
    uint8 reinvestPct;         // offset 9  (UNCHANGED)
    uint8 flags;               // offset 10 (bit 0 FREED — was FLAG_WINDOW_PAID; bits 1+2 UNCHANGED)
    address fundingSource;     // offset 11 (UNCHANGED — OPEN-E preservation)
}
```

**Constants/iface deletions** (the discrete surgical surfaces):

```solidity
// :57       DELETE the IBurnie iface decl (`function burnForKeeper(...);`)
// :220      DELETE `uint32 internal constant WINDOW_DAYS = 30;`
// :239      DELETE `uint8 internal constant FLAG_WINDOW_PAID = 1;` (bit 0 freed; do NOT reserve it)
// :414-416  DELETE the anchor math
// :424      DELETE the paidThroughDay write
// :430-443  DELETE the SUB-01 pass-OR-pay gate (replaced by the single horizon encode)
// :432      (subsumed) — the subscribe-time hasAnyLazyPass read
// :437      (subsumed) — the subscribe-time burnForKeeper call
// :633      KEEP-but-rewrite — the FREE-extend write (now writes validThroughLevel = h)
// :637-664  DELETE the PAID branch in _autoBuy (burnForKeeper + extract events)
// :641      (subsumed) — the day-31 burnForKeeper call
// :631      (subsumed) — the day-31 hasAnyLazyPass read (replaced by the crossing's single lazyPassHorizon read)
```

- **Pattern action:** Apply the rewrites surgically. **Hoist `currentLevel` ONCE at autoBuy entry** (NOT per-iter — the GASOPT-05 win is the no-per-iter-external-read property). Verify the `IGame` iface AfKing reads exposes `level()` (or add it; if not, expose `currentLevel` via a thin wrapper). Add `lazyPassHorizon` to the iface decl at `AfKing.sol:18-43`.
- **Pitfall guard P5:** do NOT add a `refreshPass()` external entrypoint. The crossing IS the refresh.
- **Pitfall guard P6:** the eviction MUST route through `setDailyQuantity(0)`-style tombstone semantics (write `dailyQuantity = 0`, `_removeFromSet`, emit, continue WITHOUT advancing cursor). A direct mid-sweep `_removeFromSet` without the tombstone shape reproduces H-CANCEL-SWAP-MISS.
- **OPEN-E preservation (D-12 / AFSUB-04):** the `fundingSource` field (offset 11), the OPENE-04 gate (`:393-403`), and the self-consent gate (`:385-391`) are ALL UNTOUCHED. The 4-protection set (consent-at-subscribe / default-self byte-identical / no-escalation / trust-the-sub) survives by construction.

### 2.6 Step 5b — `contracts/BurnieCoin.sol` (BurnieCoin cluster, the impl side)

**Analog for the deletion symmetry:** the sibling modifiers `onlyGame:535` + `onlyVault:542` (the two access modifiers that STAY).

**Reference modifier symmetry** (lines 533-552 — the kept modifiers + the one to delete):

```solidity
// contracts/BurnieCoin.sol:533-552 — the access-modifier triad; AFSUB removes the third
modifier onlyGame() {                          // :535 KEEP
    if (msg.sender != ContractAddresses.GAME) revert OnlyGame();
    _;
}
modifier onlyVault() {                         // :542 KEEP
    if (msg.sender != ContractAddresses.VAULT) revert OnlyVault();
    _;
}
modifier onlyAfKing() {                        // :549 DELETE (sole user is burnForKeeper at :475)
    if (msg.sender != ContractAddresses.AF_KING) revert OnlyAfKing();
    _;
}
```

**Implementation to delete** (lines 472-488):

```solidity
// contracts/BurnieCoin.sol:472-488 — DELETE the whole function
function burnForKeeper(
    address user,
    uint256 amount
) external onlyAfKing returns (uint256 burned) {
    if (amount == 0) return 0;
    uint256 available = balanceOf[user];
    unchecked { available += coinflip.previewClaimCoinflips(user); }
    if (available < amount) return 0;
    uint256 consumed = _consumeCoinflipShortfall(user, amount);
    _burn(user, amount - consumed);
    emit KeeperBurn(user, amount);
    return amount;
}
```

**Event to delete** (lines 82-85):

```solidity
// :82-85 DELETE
/// @notice Emitted when the AF_KING keeper burns a player's subscription charge.
event KeeperBurn(address indexed user, uint256 amountBurned);
```

**Error to delete** (search `error OnlyAfKing()` — the bound error of the deleted modifier):

```solidity
// search the errors block (top of contract) for `error OnlyAfKing();` and DELETE.
```

- **Pattern action:** delete the function body (`:472-488`), the event (`:85`), the modifier (`:549-552`), and the `error OnlyAfKing()` declaration. The grep `grep -rn burnForKeeper contracts/` after the diff MUST return zero hits (the 334-DESIGN-LOCK-AFKING §5.2 verification).
- **Within-cluster ordering (D-09 Claude's Discretion):** either order is safe per the atomic-diff property (the diff compiles as a whole). The 334-IMPL-EDIT-ORDER-MAP §1 Step 5 prefers caller-side first (AfKing deletions before BurnieCoin impl deletion) for reviewer clarity. Planner picks.

### 2.7 Tests — `test/fuzz/AfKingSubscription.t.sol` (the heaviest migration)

**Analog:** self — the existing test bodies migrate to the new semantics in-place.

**Existing test body pattern (Task 3a, lines 79-129 — pass-OR-pay renewal gate):**

```solidity
// test/fuzz/AfKingSubscription.t.sol:79-129 — the existing pass-OR-pay test bodies
function testRenewalPassHolderFreeExtendNoCharge() public {
    address pass = makeAddr("pass_holder");
    _grantDeityPass(pass); // hasAnyLazyPass(pass) == true        ← MIGRATE: still grant deity, but assert horizon
    _subscribeTicketMode(pass, 1, false);
    _approveKeeper(pass);
    _fundPool(pass, 1 ether);
    _forceRenewalDue(pass); // paidThroughDay <= today           ← MIGRATE: force currentLevel > validThroughLevel

    vm.recordLogs();
    vm.prank(makeAddr("autoBuyer_pass"));
    afKing.autoBuy(50);

    assertEq(_countEvent(address(afKing), EXTENDED_FREE_SIG), 1, "pass-holder free-extended");
    assertEq(_countEvent(address(afKing), AUTO_EXTRACTED_SIG), 0, "pass-holder NOT charged via burnForKeeper");
                                                                  // ↑ MIGRATE: drop this assert; no more burnForKeeper
    assertEq(coin.balanceOf(pass), burnieBefore, "no BURNIE burned for a pass-holder renewal");
                                                                  // ↑ MIGRATE: no BURNIE involved at all; drop
    assertGt(afKing.subscriptionOf(pass).paidThroughDay, _today(), "renewed window endpoint in the future");
                                                                  // ↑ MIGRATE: assertGt(... .validThroughLevel, currentLevel)
    assertEq(afKing.subscriptionOf(pass).flags & 1, 0, "windowPaid cleared on a free extend");
                                                                  // ↑ MIGRATE: bit 0 freed; drop this assert
}
```

**Storage slot offsets (oracle at lines 38-49) — re-pack for `validThroughLevel`:**

```solidity
// :38-49 — existing offset oracle (the test computes slot writes manually for _forceRenewalDue)
uint256 private constant SUBOF_SLOT = 1;
uint256 private constant OFF_DAILY = 0;
uint256 private constant OFF_LASTSWEPT = 1;
uint256 private constant OFF_PAIDTHROUGH = 5;          // ← RENAME to OFF_VALIDTHROUGHLEVEL (same offset, same width)
uint256 private constant OFF_REINVEST = 9;
uint256 private constant OFF_FLAGS = 10;               // ← bit 0 is FREED; do not assert against it
uint256 private constant OFF_FUNDING_SOURCE = 11;
```

**Settled migration pattern (the new pass-eviction analog of the existing pass-OR-pay):**

```solidity
function testCrossingPassHolderRefreshedNotEvicted() public {
    address pass = makeAddr("pass_holder");
    _grantDeityPass(pass);                                            // horizon = type(uint24).max
    _subscribeTicketMode(pass, 1, /*fundBurnie*/ false);              // no BURNIE needed; pass = free at subscribe
    _approveKeeper(pass);
    _fundPool(pass, 1 ether);
    _forceCrossingDue(pass);                                          // NEW helper: write validThroughLevel s.t. currentLevel > h

    vm.recordLogs();
    vm.prank(makeAddr("autoBuyer_pass"));
    afKing.autoBuy(50);

    // REFRESH taken — the crossing re-read the horizon and stamped a new validThroughLevel:
    assertEq(_countEvent(address(afKing), EXTENDED_FREE_SIG), 1, "deity refreshed at crossing");
    assertGt(afKing.subscriptionOf(pass).validThroughLevel, _currentLevel(), "horizon refreshed past current level");

    // NEGATIVE: no longer asserting absence of a BurnieAutoExtracted — burnForKeeper is GONE.
    // NEGATIVE: no FLAG_WINDOW_PAID bit assertions — bit 0 freed.
}

function testCrossingNoPassEvictedViaTombstone() public {
    address nopass = makeAddr("no_pass");
    _subscribeTicketMode(nopass, 1, /*fundBurnie*/ false);            // no charge at subscribe under AFSUB
    _approveKeeper(nopass);
    _fundPool(nopass, 1 ether);
    _forceCrossingDue(nopass);

    vm.recordLogs();
    vm.prank(makeAddr("autoBuyer_nopass"));
    afKing.autoBuy(50);                                               // MUST NOT revert

    // EVICTION taken via tombstone — assert the exact reclaim shape (SUB-07 invariant + swap-pop)
    assertGe(_countEvent(address(afKing), SUB_EXPIRED_SIG), 1, "no-pass evicted at crossing");
    assertEq(afKing.subscriptionOf(nopass).dailyQuantity, 0, "tombstoned (dailyQuantity zeroed)");
    assertEq(_subscriberIndexOf(nopass), 0, "removed from iterable set (swap-pop)");
}
```

- **Pattern action:** Rename `OFF_PAIDTHROUGH` → `OFF_VALIDTHROUGHLEVEL`; rename `_forceRenewalDue` helper → `_forceCrossingDue` (writes `validThroughLevel < currentLevel` directly via slot poke). Replace the 14 `paidThroughDay` reads, 11 `burnForKeeper` references, and 3 `hasAnyLazyPass` references per the 335-CONTEXT.md count. Delete the `_fundBurnie(... , cost)` calls and the BURNIE-balance assertions — they no longer apply.
- **Pitfall guard:** the SUB-09 deploy-time self-subscribes (VAULT + SDGNRS) still happen at fixture setup. Verify their `validThroughLevel` initializes to whatever `lazyPassHorizon(VAULT)` / `lazyPassHorizon(SDGNRS)` returns (likely zero, since they hold no passes — so they trigger eviction on first crossing). This is the OPENE-04 / two-tier funding-skip invariant the test fixture relies on; re-attest it survives.

### 2.8 Tests — `test/fuzz/AfKingFundingWaterfall.t.sol` (OPEN-E re-attest + pass-eviction-preserves-tombstone)

**Analog:** self — the existing `fundingSource` waterfall tests stay; pass-eviction is the new branch.

**Pattern action:** drop the 11 `burnForKeeper` + 5 `paidThroughDay` + 3 `hasAnyLazyPass` references. Add the new assertion: a `fundingSource`-funded sub whose subscriber's pass expires gets evicted (the tombstone tombstones the SUB, not the funding source). The 4-protection assertions (consent-at-subscribe / default-self / no-escalation / trust-the-sub) survive — they are UNTOUCHED by AFSUB. Pull the OPEN-E pattern guard from `open-e-operator-approval-trust-boundary` (don't model a "tricked into approving" actor).

### 2.9 Tests — `test/fuzz/AfKingConcurrency.t.sol` (swap-pop invariant)

**Analog:** self — the v49 swap-pop `membership ⟺ packed != 0` invariant assertions stay.

**Pattern action:** rebase the 18 `paidThroughDay` writes to `validThroughLevel` writes (same slot, same width if uint32 kept). Re-derive the H-CANCEL-SWAP-MISS regression scenario under pass-eviction: a player evicted mid-sweep MUST NOT relocate a pending tail behind the cursor. The reclaim path (`:605-617` `continue` without advancing cursor) is what protects this; the test asserts the swap-pop occupant is processed this same autoBuy.

### 2.10 Tests — `test/fuzz/KeeperNonBrick.t.sol`

**Analog:** self.

**Pattern action:** small rewrite — drop the 1 `paidThroughDay` + 1 `hasAnyLazyPass` reference. Re-author one assertion: under heavy concurrent pass-expiration, autoBuy MUST NOT revert; H-CANCEL-SWAP-MISS class assertion (missed-day / mint-streak-reset class) does not reproduce.

### 2.11 Tests — `test/fuzz/RngFreezeAndRemovalProofs.t.sol`

**Analog:** self + `334-WHALE04-FREEZE-PROOF.md` write-set map (the load-bearing reference document).

**Pattern action:** trivial assertion-only rewrite. Drop the 7 `hasAnyLazyPass` references. Add two trivial assertions per `335-CONTEXT.md` D-IMPL-02:
1. The box-open `whalePassClaims +=` write occurs at a non-frozen-slot (cite WHALE04-FREEZE-PROOF §1 — `whalePassClaims` is a pending-claim accumulator, not VRF-influenced).
2. The AfKing crossing's `lazyPassHorizon` external view read is not an RNG-window read (cite WHALE04-FREEZE-PROOF §5 — `mintPacked_` freeze-state is the read target; reads do not write).

**Deferred:** the deeper RNG-freeze fuzz of the deferred-claim path lands at 336 TST-01 freeze leg, NOT 335.

### 2.12 Tests — `test/gas/KeeperLeversAndPacking.t.sol`

**Analog:** self — the existing `_structFieldBytes` packing oracle at `:229`.

**Existing oracle pattern** (lines 215-229):

```solidity
// test/gas/KeeperLeversAndPacking.t.sol:215-229 — the packing oracle
///           uint8 dailyQuantity(1) + uint32 lastAutoBoughtDay(4) + uint32 paidThroughDay(4)
///           ...
_structFieldBytes(afking, "uint32 paidThroughDay;", 4) +   // :229 ← MIGRATE
```

**Migrated pattern:**

```solidity
_structFieldBytes(afking, "uint32 validThroughLevel;", 4)   // or "uint24 validThroughLevel;" if planner narrows
```

**Drop the burnForKeeper byte-presence assertion** (line 297):

```solidity
// :296-297 DELETE
// G8 — burnForKeeper all-or-nothing (AfKing:396 — IBurnie.burnForKeeper).
assertGt(_countOccurrences(afking, "burnForKeeper("), 0, "G8: burnForKeeper all-or-nothing charge byte-present");
```

- **Pattern action:** rename the oracle string (2 occurrences per the 335-CONTEXT.md count). Delete the G8 `burnForKeeper(` presence check (after AFSUB, that byte sequence MUST NOT appear in either contract).

### 2.13 Tests — `test/gas/RouterWorstCaseGas.t.sol`

**Analog:** self — the existing `OPEN_NORMAL_GAS_UNIT` mirror at `:121` + the gas-weighted budget assertions across the file.

**Existing mirror pattern** (lines 115-128):

```solidity
// test/gas/RouterWorstCaseGas.t.sol:115-128 — the existing mirror + worst-case constants
uint256 internal constant BUY_BATCH = 50;
uint256 internal constant OPEN_BATCH = 100;
uint256 internal constant OPEN_NORMAL_GAS_UNIT = 90_000;   // :121 DELETE (mirrors a deleted contract const)
uint256 private constant WHALE_CLUSTER_WORD = ...;          // :128 DELETE (the cluster used to fire :1250-1260 heavy box)
```

**Migrated pattern:**

```solidity
// post-WHALE-03 — flat OPEN_BATCH; value picked from KeeperOpenBoxWorstCaseGas (D-IMPL-04)
uint256 internal constant BUY_BATCH = 50;
uint256 internal constant OPEN_BATCH = <measured>;          // ← MEASURE, do not pre-derive
// DELETE OPEN_NORMAL_GAS_UNIT; DELETE WHALE_CLUSTER_WORD; DELETE the cluster-search helper
```

- **Pattern action:** delete the 6 `OPEN_NORMAL_GAS_UNIT` occurrences + the 5 `_activateWhalePass` references + the `weighted += used / OPEN_NORMAL_GAS_UNIT`-related assertions (`testGasWeightedBudgetClusterCapsLeg`, `GAS-02 weighted-budget worst case`). Re-target to a flat `OPEN_BATCH * measured_per_box_gas ≤ 16.7M − headroom` assertion. **The OPEN_BATCH value comes from a re-run of `test/gas/KeeperOpenBoxWorstCaseGas.t.sol`** (D-IMPL-04); do NOT pre-derive (Pitfall P4).

### 2.14 Tests — `test/gas/KeeperOpenBoxWorstCaseGas.t.sol`

**Analog:** n/a — HARNESS RE-RUN ONLY.

**Pattern action:** ZERO code change. After applying the contracts diff (Steps 1-5), re-run this harness; it auto-compiles against the new contracts. Record the new per-box gas figure (expected ~89K — uniform across whale-pass and non-whale-pass openers per D-02/D-04). Use the figure to PICK the flat `OPEN_BATCH` constant in `DegenerusGame.sol` Step 2 and the mirror in `test/gas/RouterWorstCaseGas.t.sol`.

**If the measurement reveals a ceiling overshoot under any reasonable OPEN_BATCH:** STOP and re-spec (D-IMPL-04 hard-stop floor). Do not silently lower OPEN_BATCH below what 331 considered usable.

---

## 3. Shared Patterns

### 3.1 The O(1) `+=` writer pattern (WHALE-01)

**Source:** `contracts/modules/DegenerusGamePayoutUtils.sol:52` and `contracts/modules/DegenerusGameJackpotModule.sol:1410`
**Apply to:** `contracts/modules/DegenerusGameLootboxModule.sol:1240-1261` (the new `_activateWhalePass` body)

```solidity
whalePassClaims[beneficiary] += grant;
```

That is the entire pattern. The materialization is the EXISTING `claimWhalePass:1018` — no new claim function, no new map, no new gate.

### 3.2 The producer-before-consumer edit-order pattern (D-18)

**Source:** `334-IMPL-EDIT-ORDER-MAP.md` §1 (the 5-step order) + §2 (the writer-vs-reader reconciliation for the shared `_queueTickets` surface)
**Apply to:** ALL files in this diff

Order: Storage (confirm) → Game (facade view + autoOpen retirement) → LootboxModule (writer) → MintModule (independent) → AfKing+BurnieCoin (cluster). Within the AfKing+BurnieCoin cluster: caller-side first (AfKing deletions) OR atomic — both safe by the atomic-diff property.

### 3.3 The stored-field-compare per-iter pattern (GASOPT-05 preservation)

**Source:** existing `AfKing.sol:630` (`if (sub.paidThroughDay <= today)`)
**Apply to:** `AfKing.sol:630` (the rewritten check `if (currentLevel > sub.validThroughLevel)`)

The shape is IDENTICAL: one SLOAD (already in the sub struct), one comparison. NO per-iter external read. The single external read is at the crossing only (the `lazyPassHorizon(player)` call inside the `if (crossing)` block).

### 3.4 The tombstone-then-reclaim eviction pattern (SUB-07 + v49 swap-pop preservation)

**Source:** existing `AfKing.sol:458-468` `setDailyQuantity(0)` (in-place tombstone) + `AfKing.sol:605-617` (in-autoBuy reclaim that `continue`s WITHOUT advancing the cursor)
**Apply to:** the AFSUB refresh-or-evict crossing's EVICT branch in `AfKing.sol:_autoBuy:630-665`

The pass-eviction at the crossing MUST route through this existing two-step pattern. A direct mid-sweep `_removeFromSet(player)` without the tombstone-then-reclaim shape re-opens H-CANCEL-SWAP-MISS (memory `afking-cancel-tombstone-streak-finding`).

### 3.5 The structural-guard freeze-floor pattern (D-IMPL-01 / D-23)

**Source:** `contracts/storage/DegenerusGameStorage.sol:1213` `_livenessTriggered` + the existing `claimWhalePass:1019` revert
**Apply to:** nothing — DO NOT add any guard

The pattern is **non-action**: D-23 (unclaimed `whalePassClaims` forfeit at gameOver) is satisfied by structural transitivity through `_livenessTriggered`. Adding a redundant `if (gameOver) revert` would be wasted gas AND a freeze-floor-class signal that the structural argument is fragile (`feedback_security_over_gas`).

The trace (record in any SUMMARY): `gameOver = true` only flips via `GameOverModule.handleGameOverDrain:145` → reachable only via `AdvanceModule._handleGameOverPath:596` → `:522` early-out requires `_livenessTriggered() == true` at the flip moment → post-gameOver, level/`purchaseStartDay`/active-phase flags are all frozen → `_livenessTriggered()` returns `true` forever → `claimWhalePass:1019` reverts forever.

### 3.6 The measurement-first OPEN_BATCH pattern (D-IMPL-04)

**Source:** existing `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` (already measures the right thing)
**Apply to:** the new `OPEN_BATCH` constant in `DegenerusGame.sol` Step 2 + the mirror in `test/gas/RouterWorstCaseGas.t.sol`

Pick OPEN_BATCH = floor((16.7M − headroom) / measured_per_box_gas), with documented headroom ≥ 1 box worth. The attestation is `chosen × measured ≤ 16.7M − headroom`. Do NOT pre-derive.

### 3.7 The test-and-contracts atomic-diff pattern (D-IMPL-02)

**Source:** v49 Phase 330 IMPL `63bc16ca` (5 contracts + 9 tests in ONE USER-approved batch)
**Apply to:** the BATCH-02 HARD STOP at the contract-commit boundary in this phase

The USER hand-review sees a single unified diff (contracts + tests). The `forge build` gate at HARD STOP is the integration oracle — without test migration in the same diff, build fails and "applied + locally compiled" cannot be demonstrated. NEW reds vs the v49 `666/42/17` baseline are reconciled INSIDE 335 via the test migration (D-IMPL-03); a genuine v50 regression (not a fixture-migration artifact) is a STOP-and-re-spec signal.

---

## 4. Files with No Existing Analog

**None.** Every file in the diff has a strong in-repo analog (often self, often a sibling slot writer/reader). The convergence story (§0) is what removes the "novel code" surface entirely.

This is itself a load-bearing finding: a Phase-335 plan that introduces a "new" pattern (e.g. a `pendingWhalePasses` map, a `refreshPass()` entrypoint, a new gameOver guard) is **deviating from the locked decisions**, not "filling a gap." The right question for the planner at every choice point is: *which existing line am I mirroring here?*

---

## 5. Metadata

**Analog search scope:**
- `contracts/storage/DegenerusGameStorage.sol`
- `contracts/DegenerusGame.sol`
- `contracts/modules/DegenerusGameLootboxModule.sol`
- `contracts/modules/DegenerusGameMintModule.sol`
- `contracts/modules/DegenerusGameWhaleModule.sol`
- `contracts/modules/DegenerusGamePayoutUtils.sol`
- `contracts/modules/DegenerusGameJackpotModule.sol`
- `contracts/modules/DegenerusGameDecimatorModule.sol`
- `contracts/AfKing.sol`
- `contracts/BurnieCoin.sol`
- `test/fuzz/AfKing*.t.sol`
- `test/fuzz/KeeperNonBrick.t.sol`
- `test/fuzz/RngFreezeAndRemovalProofs.t.sol`
- `test/gas/{KeeperLeversAndPacking,RouterWorstCaseGas,KeeperOpenBoxWorstCaseGas}.t.sol`

**Files scanned (Read tool):** 14 contract/test files (all anchors hit on first read; no re-reads).

**Pattern extraction date:** 2026-05-28

**Cross-reference attestation:** every `file:line` in this PATTERNS.md was confirmed against the working tree (which is byte-identical to `b0511ca2` per `334-GREP-ATTESTATION.md` §0). The 5 drift corrections recorded in 334-GREP-ATTESTATION.md §4 (`_livenessTriggered` def at `:1213` not `:571`; `Sub` body at `:86-93`; `WhaleModule:1032` is the claim caller not bundle; `processFutureTicketBatch` at `:393`; OPENE-04 region `:393-403`) are honored throughout.

*Phase: 335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re — Pattern map.*
