# AdvanceModule post-fix re-sweep round 1 — 2026-07-09, tree d5e9f58a (run wf_beb1d108-72d)

20 chunks @ HEAD b5b4f88f (contracts tree d5e9f58a, post C1-C5 fix batch). 19 clean / 1 concern.
Concern: _prepareFutureTickets empty-probe erases in-flight base-level ticket resume cursor
(chunk 1577-1667). Council verification in flight (Codex + 3 Claude lenses).


---
## Chunk 1

(a) Definite inconsistencies
- None. The reviewed range (HEAD lines 1–176) contains only the header, imports, the `IGNRUSResolve.pickCharity(uint24)` interface declaration (line 26), error/event/constant declarations, and the first four statements of `advanceGame` (lines 172–176: `mult = 1`, the `uint48` timestamp cast, and the `_simulatedDayIndexAt` call). No state variable is written, no pool/supply/claimable total is touched, and no arithmetic that can wrap or revert executes within this range. Stage constants (lines 59–86) are distinct sequential values 0–13 with no duplicates or gaps; bps constants are self-consistent (`NEXT_TO_FUTURE_BPS_MIN` 1300 ≤ `FAST` 3000 ≤ `MAX` 8000; `OVERSHOOT_CAP_BPS` 3500 < `OVERSHOOT_THRESHOLD_BPS` 12500; `NEXT_SKIM_VARIANCE_MIN_BPS` 1000 ≤ `NEXT_SKIM_VARIANCE_BPS` 2500).

(b) Observations holding only via out-of-range invariants
- Line 174 `uint48 ts = uint48(block.timestamp)`: the narrowing cast cannot wrap only because `block.timestamp < 2^48` (holds until ~year 8.9M) — a chain-clock invariant, not a code check. All `uint48` time constants in range (`GAMEOVER_RNG_FALLBACK_DELAY` line 126, `MIDDAY_RNG_STALL_TIMEOUT` line 152) rely on the same bound.
- Line 26 `pickCharity(uint24 level)`: the `uint24` level parameter matches `Advance(uint8 stage, uint24 lvl)` (line 51) and `AffiliateDgnrsReward` (line 108); no truncation only because the game's level counter is maintained as `uint24` in `DegenerusGameStorage` (out of range) and never exceeds that width.
- Lines 79–86 (`STAGE_GAP_BACKFILLED` / `STAGE_SUBS_BACKFILL_DEFERRED` doc comments): the claimed accounting soundness — "dailyIdx is not yet advanced, so advanceDue() stays true" and "rngGate is idempotent on re-entry (gapDays == 0 next call)" — is an invariant maintained by the `rngGate`/`advanceDue` bodies outside this range; nothing in-range enforces it. Named invariant: rngGate gap-backfill idempotence + dailyIdx-deferral liveness.
- Line 125 `MIN_LINK_FOR_LOOTBOX_RNG = 40 ether` typed `uint96`: 40e18 < 2^96, safe by literal inspection; its sufficiency as a LINK floor depends on VRF pricing outside the contract.
- Lines 117–121: `charityResolve` and `jackpots` are `constant` handles to `ContractAddresses.GNRUS`/`JACKPOTS`; correctness of every call through them (including `pickCharity`) rests on the compile-time address-wiring invariant of `ContractAddresses`.

(c) Cosmetic / telemetry-only
- Lines 51–56, 87–103, 108–112: `Advance`, `RewardJackpotsSettled`, `DailyRngApplied`, `LootboxRngApplied`, `VrfCoordinatorUpdated`, `StEthStakeFailed`, `AffiliateDgnrsReward` are emission-only declarations; no accounting effect in range.
- Lines 153–166 (`SUB_STAGE_WEIGHT_BUDGET` comment): stated gas arithmetic is internally consistent (budget 2500 × ≈3.4k gas/weight ≈ 8.5M, matching the "<10M target" claim; 2500/8 ≈ 312 evict finalizes as documented). Documentation only.
- Line 45 `NotTimeYet();` and line 46 `RngNotReady();` lack the trailing explanatory comments their sibling errors (lines 36–43) carry — purely cosmetic.
- Lines 168–172: `AFFILIATE_POOL_REWARD_BPS` (100) and `AFFILIATE_DGNRS_LEVEL_BPS` (500) are declarations only; the 1%-of-remaining vs 5%-segregation interaction is consumed outside this range.

REVIEW-STATUS: clean

---
## Chunk 2

(a) definite inconsistencies
- None. All three functions in the range (payDailyJackpot, HEAD lines 1122-1138; payDailyJackpotCoinAndTickets, lines 1144-1156; _payDailyCoinJackpot, lines 1166-1183) are pure delegatecall dispatch wrappers into `ContractAddresses.GAME_JACKPOT_MODULE`. They contain no arithmetic, no narrowing casts, no checked subtractions, and no direct storage writes; parameters (`isJackpotPhase`, `lvl`, `randWord`, `minLevel`, `maxLevel`) are forwarded byte-for-byte via `abi.encodeWithSelector`. There is no input to these wrappers that can independently break an accounting relationship — any pool/supply effect happens inside the jackpot module, which is outside this range.

(b) observations holding only via an external invariant
- Codeless-target success (lines 1128, 1146, 1172): `delegatecall` to an address with no code returns `ok = true` with empty returndata, so all three wrappers would silently no-op — daily jackpot state (e.g. the pending coin/tickets split flag) would never advance while the caller believes it did. This is safe only under the deployment invariant that `ContractAddresses.GAME_JACKPOT_MODULE` is a compile-time constant pointing at a contract deployed before the game module, and delegatecalled code cannot self-destruct the module under post-Cancun semantics.
- Revert propagation (lines 1137, 1155, 1182 via `_revertDelegate`, lines 922-927): correctness of the failure path relies on `_revertDelegate` bubbling the module's revert reason and converting empty-reason failures (OOG in the sub-frame, invalid opcode) into `EmptyRevert()` rather than continuing — that helper is outside the range but verified present at HEAD lines 922-927.
- Selector/ABI agreement: the wrappers assume `IDegenerusGameJackpotModule.payDailyJackpot / payDailyJackpotCoinAndTickets / payDailyFlipJackpot` signatures match the deployed module's implementations (same storage layout under delegatecall). Any pool-total consistency after the call is the module's invariant, not established here.
- `payDailyJackpotCoinAndTickets` (line 1144) carries the documented precondition that it is only invoked when `dailyJackpotCoinTicketsPending` is set; sequencing/idempotence of the split daily jackpot is enforced by the caller and the module, not by this wrapper.

(c) cosmetic / telemetry-only
- Naming asymmetry: `_payDailyCoinJackpot` (line 1166) dispatches the `payDailyFlipJackpot` selector (line 1177). The natspec (lines 1158-1165) makes clear it awards FLIP ("coin"), so this is a readability note only.
- Successful-call returndata (`data`) is discarded in all three wrappers; the module functions return nothing, so nothing is lost.
- `payDailyJackpot` and `payDailyJackpotCoinAndTickets` are `internal` while `_payDailyCoinJackpot` is `private` with an underscore prefix — inconsistent visibility convention, no behavioral effect.

REVIEW-STATUS: clean

---
## Chunk 3

(a) Definite inconsistencies
- None. Both functions in range are `view`/`pure` and write no state; every branch was walked (elapsed ∈ {0,1}, [2,14], [15,28], >28; currentDay ∈ {0,1}, [2,30], >30). No reachable input produces an underflow, a wrapping narrowing cast, or a pool/total divergence within this range. Branch continuity in `_nextToFutureBps` is exact: at elapsed=14 the descent lands precisely on `NEXT_TO_FUTURE_BPS_MIN` (delta*13/13 == delta, line 1541-1545), at elapsed=28 the ascent lands precisely back on FAST+lvlBonus (1300+delta, line 1551), and elapsed=29 continues from there (+14, line 1553-1557). The `uint16` return cast at line 1559 is guarded by the explicit 10_000 clamp and cannot wrap.

(b) Holds only via an outside-range invariant
- Line 1556 `(elapsed - 28) * NEXT_TO_FUTURE_BPS_DAY_STEP`: this sub-expression is evaluated in checked `uint32` (elapsed is uint32, DAY_STEP uint16), so it would revert for elapsed ≥ ~306.8M. Safe only because the sole caller (line 947-948) computes `elapsed = day - (psd + 7)` from a `uint24 day`, bounding elapsed ≤ 16,777,215 (product ≤ ~2.35e8 < 2^32). Invariant: elapsed is derived from a uint24 day counter.
- Lines 1538-1540 and 1548-1550 `delta = FAST + lvlBonus - MIN`: the checked subtraction cannot underflow only because of the constant relationship `NEXT_TO_FUTURE_BPS_FAST (3000) > NEXT_TO_FUTURE_BPS_MIN (1300)` (lines 132-133). Any retuning that inverts that ordering (with lvlBonus < MIN-FAST) makes days 2-28 of every level revert the advance path.
- Docstring claim (lines 1490-1492) that the zero-history prevrandao-only fall-through "can only happen at level 0": holds because `rngWordByDay` is densely populated for every completed day — the gap-day backfill (line 2046, `rngWordByDay[gapDay] = derivedWord`) writes derived non-zero words for skipped days, so for currentDay ≥ 2 with any completed advance at least one word in [1, min(currentDay,30)-1] is non-zero. Invariant: rngWordByDay density via `_backfillGapDays`.

(c) Cosmetic / telemetry-only
- Line 1501 `searchDay < searchLimit` with `searchLimit = min(currentDay, 30)` (line 1500): the scan covers days 1..29 at most — the nominal "30" window is effectively 29 candidates, and the window is anchored at the game's earliest days rather than sliding to the most recent 30. No security delta (all historical VRF words are equally public and the output is salted with `currentDay` + `block.prevrandao`, lines 1515-1516), but the window semantics don't match the "30" constant's apparent intent.
- Header comment at lines 1524-1525 ("Normal levels draw 15%") does not match the constants actually used (FAST = 3000 bps = 30%, MIN = 1300 bps = 13%, lines 132-133). Comment-only.
- The 10_000 clamp at line 1559 is applied before the caller's x9 bonus (line 951 adds 200 bps post-clamp), so the effective pre-adjustment rate can nominally reach 10,200 bps; harmless because the caller's take is hard-capped at `NEXT_TO_FUTURE_BPS_MAX` (80%, line 1005). Cross-range telemetry note only.
- Line 1518 `if (word == 0) word = 1`: keccak256 output of zero is cryptographically unreachable; the guard is pure belt-and-suspenders for a zero-sentinel convention.

REVIEW-STATUS: clean

---
## Chunk 4

(a) Definite inconsistencies
- None. Every reachable input through `_lrAdvanceIndexClearPending` (line 1767), `_swapTicketSlot` (1787), `_freezePool` (1797), `_swapAndFreeze` (1812), and `_unfreezePool` (1818) preserves the packed-slot field boundaries and pool conservation. In `_lrAdvanceIndexClearPending`, the clear mask (lines 1770-1772) zeroes exactly LR_INDEX [0:47], LR_PENDING_ETH [48:111], and LR_PENDING_FLIP [184:223] while preserving LR_THRESHOLD [112:175], the unused byte [176:183], and LR_MID_DAY [224:231] (layout: storage/DegenerusGameStorage.sol:1611-1620). In `_freezePool`, `seed = futureBal / 100` (1801) is subtracted and credited with the same truncated value (1803-1804), so future-pool + pendingFuture is conserved exactly; `uint128(seed)` (1804) cannot truncate because `futureBal` is unpacked from a uint128 half-slot (`_getFuturePrizePool`, storage :893) so `seed < 2^128/100`. In `_unfreezePool`, the sequence read-pending → read-live → sum → zero-pending → clear-flag (1821-1825) has no external calls and no window where pending is double-counted or dropped.

(b) Holds only via an outside-range invariant
- Line 1769/1775 — index wrap: at LR_INDEX = 2^48-1, `nextIndex & LR_INDEX_MASK` wraps to 0, after which every `uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1` consumer (e.g. lines 242-248, 1378, 2015; MintModule.sol:659) underflows/reverts. Safe under the invariant that the index increments at most a few times per game day (one daily finalize + occasional mid-day request), making 2^48 unreachable in any deployment lifetime.
- Line 1773 — no-double-advance: advancing the index twice for one delivered word would strand lootboxes queued at the skipped index (words are stored at `index - 1` on delivery). Safe only because both call sites guard: the mid-day path (line 1250) requires `rngRequestTime == 0` / no request in flight (1202), and `_finalizeRngRequest` gates on `!isRetry` (lines 1835-1846).
- Lines 1770-1772 — pending ETH/FLIP zeroing loses accrued volume only if a purchase's contribution had not yet been attributed to the request being issued. Safe because these fields are threshold-trigger accumulators (read at 1215-1232 *before* the request/clear), not claimable value; the actual lootbox deposits are tracked per-index elsewhere.
- Line 1823 — `next + pNext` / `future + pFuture` are checked uint128 adds; a revert here would brick the advance heartbeat. Safe under the solvency invariant that both live and pending pools track real deposited ETH, bounded by total ETH supply (~1.2e8 ether ≪ 2^128 wei). Pending inflow during freeze comes only from `_addPrizeContribution` (storage :842), which routes real purchase ETH.
- Lines 1798-1808 — `_freezePool` assumes pending is already zero when entering unfrozen (else the seed branch at 1804 would silently discard a stale pendingNext). The invariant — pending written only while frozen (`_addPrizeContribution`) and zeroed on every unfreeze (1824) — makes both branches full-slot overwrites of an already-zero slot, so it holds unconditionally in practice.
- Line 1788 — a swap while the read slot is undrained defers (never loses) queued entries only because queue keys are level|slot-bit (`_tqReadKey`/`_tqWriteKey`) and entries persist in storage until drained; the normal-cycle call sites (e.g. 1241) additionally check `ticketsFullyProcessed` before swapping, per the terminal-caller carve-out documented at 1784-1786.

(c) Cosmetic / telemetry-only
- Line 1789 — `ticketsFullyProcessed = false` is set unconditionally even when the incoming read slot is empty; the drain loop lazily re-sets it true, costing at most one extra check next cycle.
- Line 1806 — direct `prizePoolPendingPacked = 0` where the sibling branch uses `_setPendingPools`; identical effect, stylistic asymmetry only.
- Line 1801 — the seed==0 branch (futurePrizePool < 100 wei) leaves the Degenerette freeze buffer empty, so ETH wins during that freeze wait for bet inflow; matches the natspec at 1793-1796, no accounting effect.

REVIEW-STATUS: clean

---
## Chunk 5

(a) definite inconsistencies

None. All arithmetic in 932–1030 was walked branch-by-branch:
- L982 `take = (memNext * bps) / 10_000` with worst-case bps = 10_000 (helper cap, L1559) + 200 (X9 bonus, L951) + 400 (ratio bonus, L958) + 3_500 (overshoot cap, L972-973) + 1_000 (additive random, L979) = 15_100, so `take` can exceed `memNext` transiently, but the L1005-1006 cap clamps it to 80% of `memNext` before any subtraction.
- L985-1002 variance: after the two clamps (L989 raise to `minWidth`, then L990 lower to `take`), `halfWidth <= take`, so the L1000 subtraction cannot underflow; `combined = (roll1 + roll2)/2 <= 2*halfWidth`, so the L998 addition adds at most `halfWidth`, and the L1006 cap runs after, bounding the final take.
- L1009 `memNext -= take + insuranceSkim`: take <= floor(0.80*memNext) (L1005-1006, NEXT_TO_FUTURE_BPS_MAX=8000) and insuranceSkim = floor(0.01*memNext) (L1008, INSURANCE_SKIM_BPS=100, computed on the same un-decremented memNext), sum <= 0.81*memNext — no underflow for any memNext including 0 and 1 wei.
- Conservation: L1009-1011 moves value memNext→memFuture (take) and memNext→memYieldAcc (insuranceSkim) exactly; L1015-1018 x00 dump moves floor(memYieldAcc/2) memYieldAcc→memFuture exactly (odd wei stays in the accumulator). memNext+memFuture+memYieldAcc is preserved by both blocks; no pool value is created or destroyed in range.
- L1022-1034: `baseMemFuture` is only snapshotted and `bafPoolWei = (baseMemFuture * bafPct)/100` computed; no state mutation occurs in range for the BAF branch, so nothing to diverge yet. `bafPct` branch L1033: for lvl%100==0 → 20, lvl==50 → 20, else 10; the lvl==50 arm is reachable (prevMod100=50) and consistent with the every-10-levels gate at L1031.
- No overflow anywhere: memNext, memFuture < 2^128 (loaded from packed uint128s, L939), so memFuture*100 (L956), memNext*10_000 (L967, L1005), memNext*15_100-bps products all fit uint256 with >100 bits headroom.

(b) observations holding only via an outside invariant

1. L956 `ratioPct = (memFuture * 100) / memNext` divides by `memNext` unguarded. It cannot be zero only because every path that latches `lastPurchaseDay` requires `_getNextPrizePool() >= levelPrizePool[purchaseLevel-1]` (L218, L566-567, L722), the induction base is `levelPrizePool[0] = BOOTSTRAP_PRIZE_POOL = 50 ether` (DegenerusGame.sol:209, DegenerusGameStorage.sol:165), each completed level's snapshot is written strictly positive at L600 before the sole consolidation call at L602, and no module decrements the next pool between latch and consolidation (all module writers — JackpotModule L392/L653/L720, Whale, Lootbox, Afking, Foil, Degenerette — only add or move future→next; the only zeroing writer is GameOverModule L147, after which consolidation is unreachable). Invariant name: next-pool >= previous-level snapshot at level transition.
2. L953 `levelPrizePool[purchaseLevel - 1]` would revert on checked uint24 underflow if `purchaseLevel == 0`. Safe only because the sole caller (L602) computes `purchaseLevel = (lastPurchase && locked) ? lvl : lvl + 1` (L226) where on the lastPurchase path the level was already incremented at RNG-request time (L1876 comment), so purchaseLevel >= 1 always. Invariant: purchase level is 1-based.
3. L1009's non-underflow depends on the constant relationship NEXT_TO_FUTURE_BPS_MAX (8000, L142) + INSURANCE_SKIM_BPS (100, L138) <= 10_000, declared outside the range; a future constant retune above 9_900+100 would make L1009 revert on real inputs.
4. L947 `uint32 start = psd + 7` performs the addition in uint24 (psd's type) before widening; it cannot overflow only because psd is a days-since-epoch index (~2·10^4 << 2^24-1). Invariant: day indices are calendar-scale.
5. The memory values written back at L1108-1110 (`uint128(memNext)`, `uint128(memFuture)`, part 2) cannot wrap only because total pool obligations are bounded by contract ETH balance << 2^128 (the solvency invariant documented at DegenerusGameStorage `_setCurrentPrizePool`); nothing inside 932-1030 enforces the bound.

(c) cosmetic / telemetry-only

1. Entropy reuse within one word: L979 uses `rngWord % 1001` (low bits), L1032 uses bit 0 of the same word for the BAF flip, and L993-994 use bits 64/192 — the additive-bps draw and the BAF flip share bit 0, giving a fixed parity correlation between the two outcomes. Economically negligible and pre-committed VRF, but the draws are not independent.
2. L1015-1018: the x00 yield dump keeps the odd wei in `memYieldAcc` (floor-half moved), i.e., rounding consistently favors the accumulator — intentional-looking, zero-drift.
3. L1029-1030 comment ("lastBafResolvedDay bump") describes behavior implemented outside this range; accurate per L1031-1034 as far as visible here.

REVIEW-STATUS: clean

---
## Chunk 6

(a) Definite inconsistencies
- None. Every arithmetic operation in the range was checked against reachable inputs:
  - L819 `levelPrizePool[lvl] = _getFuturePrizePool() / 3` — pure uint256 target snapshot, no narrowing, no pool debit; cannot wrap or desynchronize a balance.
  - L856-857 `poolBalance * AFFILIATE_POOL_REWARD_BPS` — poolBalance ≤ 2^128-1 (sDGNRS `uint128[5] poolBalances`, sDGNRS.sol:255), ×100 cannot overflow uint256.
  - L867 `poolBalance -= paid` — cannot underflow (see (b)1).
  - L874 `(poolBalance * AFFILIATE_DGNRS_LEVEL_BPS) / 10_000` — no overflow; downstream uint128 cast cannot truncate (see (b)2).
  - L882-892, L906-917 — fail-loud delegatecall wrappers with no in-range state arithmetic; `_revertDelegate` (L922-927) bubbles callee reverts intact.

(b) Holds only via an invariant maintained outside the range
1. L867 no-underflow of `poolBalance -= paid`: relies on sDGNRS.transferFromPool (sDGNRS.sol:556-580) returning the exact pool decrement clamped to live `available`, and on `available` equaling the L852 snapshot — true because sDGNRS transfers have no hooks/callbacks, so nothing executes between the L852 view and the L858 call. Invariant: transferFromPool return == pool decrement, and hook-free sDGNRS transfer.
2. L872-875 → `_setLevelDgnrsAllocation` (DegenerusGameStorage.sol:1227-1232) truncates `allocation` with `uint128(...)`: safe only because the affiliate pool balance is stored as uint128 in sDGNRS (sDGNRS.sol:255) and supply ~1e30 ≪ 2^128, so allocation ≤ poolBalance/20 < 2^128. Invariant: sDGNRS pool balances bounded by uint128.
3. L872 overwrites the allocation half while preserving the claimed half: sound only because claimed[lvl] == 0 at snapshot time. That holds because (i) claims write only `levelDgnrsPacked[currLevel]` with currLevel = live `level` (BingoModule.claimAffiliateDgnrs:233-256), and (ii) `_rewardTopAffiliate(lvl)` is invoked exactly once per lvl, immediately before the sole `level = lvl` writer (AdvanceModule ~L1883-1884), gated by `isTicketJackpotDay && !isDailyRetry`. If a request-retry ever slipped that gate and re-ran `_rewardTopAffiliate(lvl)` after claims for lvl began, the re-snapshot could set allocation < claimed, and WhaleModule's checked `allocation - claimed` (WhaleModule.sol:750, 819) would revert whale/deity purchases. Invariant: one `_rewardTopAffiliate` per level (retry discrimination + monotone level).
4. Aggregate earmarking: unclaimed allocations from prior levels physically remain in the Affiliate pool and are re-counted in each new 5% snapshot (documented L847-848), so summed historical allocations can exceed the live pool. No claimable/pending total goes inconsistent only because claims are restricted to currLevel (BingoModule:235) and WhaleModule reserves only currLevel's outstanding `allocation - claimed`; stale-level allocations become permanently unclaimable rather than over-committing the pool. Invariant: claim surface = current level only.
5. L850 snapshot freshness of `affiliateTop(lvl)`: scores route to level+1 during gameplay and `level = lvl` executes in the same tx immediately after this call, so no score can land at index lvl between the read and the freeze. Invariant: atomicity of the level-increment request tx.
6. L818-819 century override intentionally supersedes the L600 `levelPrizePool[purchaseLevel] = _getNextPrizePool()` snapshot for the same index; consistency depends on `_endPhase` being reached exactly once per level via the `jackpotCounter >= JACKPOT_LEVEL_CAP` latch at L633-634 (counter is reset at L821 only here).
7. L818 `lvl % 100 == 0` is also true for lvl == 0, but `_endPhase` is reachable only at jackpot end (L634) after the level pre-increment, so lvl ≥ 1 there. Invariant: jackpot phase entered only post-increment.

(c) Cosmetic / telemetry-only
1. L855-863: with 0 < poolBalance < 100, `dgnrsReward` floors to 0; transferFromPool(0) short-circuits and `AffiliateDgnsReward` emits paid = 0 — a zero-value event, no state effect. Same for a non-zero `top` against an empty pool.
2. L874: allocation floors to 0 for poolBalance < 20; claim path already treats allocation == 0 as `ZeroValue()` — consistent, dust-level only.
3. `_distributeYieldSurplus` / `_runSubscriberStage` carry extensive natspec describing callee behavior (JackpotModule / AfkingModule); the accounting they describe (obligations-sum, afkingFunding/claimablePool tandem debit) lives outside this range and was not re-verified here.

REVIEW-STATUS: clean

---
## Chunk 7

(a) Definite inconsistencies

None found in lines 173–300. Every subtraction and cast in range is guarded within the range or by a named external invariant (bucket b):
- Line 216 `uint32 purchaseDays = day - psd;` — guarded by `day >= psd` at line 213; both uint24, widening to uint32 is lossless.
- Line 289 `uint256 elapsed = ts - dayStart;` — cannot underflow: on the new-day path `day <= wallDay` always (either `day == wallDay` or the line-192 clamp sets `day = dIdx + 1 < wallDay`), and by `_simulatedDayIndexAt` (GameTimeLib.sol:31-34) `wallDay == w` implies `ts >= (w - 1 + DEPLOY_DAY_BOUNDARY) * 1 days + 82_620`, so `ts >= dayStart` with the smaller-or-equal clamped `day` a fortiori.
- Line 286 `uint256(day - 1)` — `day >= dIdx + 1 >= deployDay + 1 >= 2` on the new-day path (constructor sets `dailyIdx = currentDay >= 1`, DegenerusGame.sol:206-208), so no uint24 underflow.
- Turbo arm (lines 220-221) writes `lastPurchaseDay = true` / `compressedJackpotFlag = 2` before the mid-day/`NotTimeYet` branch, but every path that could strand the flag without the corresponding `_requestRng` level pre-increment either reverts the whole tx (line 278) or is excluded by `rngWordByDay[day] == 0` + `day == wallDay` + `!locked` (lines 209-212), so the flag never persists on a replay/cached-word day.
- The turbo target check `_getNextPrizePool() >= levelPrizePool[lvl]` (line 218) uses the same index as the normal-path arm (line 567, `levelPrizePool[purchaseLevel - 1]` with `purchaseLevel = lvl + 1`) and the game-over safety check (line 722) — the three arming/blocking comparisons are mutually consistent.

(b) Holds only via an out-of-range invariant

1. Line 226 `purchaseLevel = (lastPurchase && locked) ? lvl : lvl + 1;` — correct only because of the level-promotion invariant: `level` is pre-incremented exactly once, at RNG request time, when `lastPurchaseDay` is set (`_requestRng`, confirmed by the comment at line 1876 "Increment level at RNG request time when lastPurchaseDay = true", and `_finalizeRngRequest` as the sole other writer). If any other writer bumped `level` while `locked == false`, this ternary would double-count.
2. Line 248 `uint48((lrPacked >> LR_INDEX_SHIFT) & LR_INDEX_MASK) - 1` — safe only because `lootboxRngPacked` is initialized with `lootboxRngIndex = 1` (DegenerusGameStorage.sol:1607-1609) and the index only increments (`_lrAdvanceIndexClearPending`, line 1769); and it addresses the *correct* reserved index only because new lootbox requests are blocked while the mid-day flag is set (`revert MidDayActive()`, line 1193), so the index cannot advance past the mid-day request's slot. (48-bit index wrap at line 1775's re-mask is unreachable in any realistic lifetime.)
3. Lines 191-192 clamp and line 240 `day == dIdx` dispatch — sound only under day-monotonicity: `dailyIdx` is written solely by `_unlockRng(day)` (line 1970) with a `day` that never exceeds the wall day at write time, and by the constructor with the deploy day; hence `wallDay >= dIdx` at every entry. The same invariant protects the uint24 subtraction in `_vrfDeadmanFired` (`_simulatedDayIndex() - dailyIdx`, DegenerusGameStorage.sol:1546-1548) reached from line 229.
4. Lines 229-236 — turbo arming before the game-over gate is safe because game-over activation requires the pool target to be *missed* (`_getNextPrizePool() >= levelPrizePool[lvl]` early-returns false at lines 720-725), which is mutually exclusive with the turbo condition at line 218; only the `_vrfDeadmanFired` override pierces that, by design.
5. Line 252 `_tqReadKey(purchaseLevel)` — the read-slot key matches the queue frozen at the mid-day swap only because the swap keys on `level + 1` at request time (line 1238-1243) and `level` cannot change between swap and drain except via `_requestRng` under `lastPurchaseDay`, which flips `locked` and is compensated by the line-226 ternary.
6. GameTimeLib.currentDayIndexAt line 32 `ts - JACKPOT_RESET_TIME` and line 33 `- uint24(DEPLOY_DAY_BOUNDARY)` — no underflow only because block.timestamp >> 82620 on any live chain and DEPLOY_DAY_BOUNDARY is set at deploy to a value ≤ the then-current day boundary.

(c) Cosmetic / telemetry-only

1. Lines 283-297: on an RNGREUSE-clamped replay day (`day = dIdx + 1 < wallDay`), `elapsed` is measured from the *processed* day's start, so `mult` is always 6 regardless of how promptly the caller acts. This inflates the router bounty on replay days but is consistent with the stated intent (the day genuinely is >2h stale); it never touches pool accounting.
2. Lines 263-276: if `_runProcessTicketBatch` ever returned `(worked=false, finished=true)` on the mid-day path, the completed drain would fall through to `revert NotTimeYet()` (line 278), discarding the batch's work. Because the whole tx reverts, no state diverges — the only cost is wasted gas and the drain completing one call later on the new-day path; and the guard at lines 258-261 (non-empty queue or pending foil) makes the combination hard to reach at all.
3. Line 226 `lvl + 1` and line 192 `dIdx + 1`: uint24 overflow requires ~16.7M levels/days — unreachable given at most one increment per real day.

REVIEW-STATUS: clean

---
## Chunk 8

(a) Definite inconsistencies

None. Every branch of rngGate (lines 1278-1375) was walked: recorded-word early return (1286-1287), fresh-word gap-backfill (1300-1313), normal daily processing (1316-1354), timeout retry (1362-1369), and fresh request (1372-1374). No reachable input makes a running total diverge, a narrowing cast wrap, or a checked subtraction revert on a valid value:
- Line 1302 `day - idx - 1` cannot underflow (guarded by `day > idx + 1` at 1301).
- Line 1311 `purchaseStartDay += gapCount` cannot overflow uint24: purchaseStartDay <= idx and gapCount = day - idx - 1, so the sum is <= day - 1 < 2^24.
- Line 1346-1348 `((currentWord >> 8) % 151) + 25` is 25..175, fits uint16 with no truncation.
- gapDays (uint32 return) assigned from uint24 gapCount at 1312 — widening, safe.

(b) Observations that hold only via an invariant maintained outside the range

1. Line 1363 `uint48 elapsed = ts - rngRequestTime` is a checked subtraction. Safe only because rngRequestTime is always `uint48(block.timestamp)` of a prior or current block (writers at lines 1253, 1852, 1945, 1951) and `ts` is the current block timestamp — chain timestamp monotonicity is the invariant. uint48 wrap is out of horizon.

2. Line 1353 `_finalizeLootboxRng` computes `uint48(_lrRead(LR_INDEX...)) - 1` (line 1378), which would underflow if LR_INDEX were 0. Safe because a nonzero `rngWordCurrent` (branch guard at 1292) can only exist after a request, and every fresh request advances LR_INDEX via `_lrAdvanceIndexClearPending` (_finalizeRngRequest line 1845; midday path line 1250) while retries keep the reservation. Invariant: LR_INDEX >= 1 whenever rngWordCurrent != 0.

3. Line 1311 adds the FULL uncapped gapCount to purchaseStartDay while `_backfillGapDays` (line 2040) processes at most 120 gap days; for a gap > 121 days, days startDay+120..day-2 would keep rngWordByDay == 0 forever, and the once-per-window guard at 1301 (now false — startDay was filled at line 2046) would never resume the fill. This never manifests because `_vrfDeadmanFired()` (120-day VRF-death timeout, checked at caller line 229) diverts advance into the game-over path before a gap that exceeds the backfill cap can reach rngGate — the 120-day cap is matched to the 120-day deadman window.

4. Fresh-word branch (1316) applies the current word to whatever `day` the caller passes; if the wall-day advanced while a processed-but-unsealed word is still resident (rngWordCurrent != 0 until _unlockRng), rngGate itself would reuse the old entropy for a new day. Prevented only by the caller's RNGREUSE clamp (lines 191-193), which pins `day` to dailyIdx+1 until the seal — on such re-entry line 1287 returns the cached word instead. rngGate has no internal `day == dailyIdx + 1` check.

5. The double-accounting protection promised by the comment at 1294-1299 (no doubled purchaseStartDay, no re-run coinflip payouts) relies on `_backfillGapDays` writing rngWordByDay[startDay] first (line 2046) — the 120 cap trims endDay, never startDay, so `rngWordByDay[idx + 1] == 0` at 1301 is guaranteed to flip false after one backfill.

6. Sentinel aliasing: the "request sent" returns at 1367/1374 use word = 1, and the caller (line 449) treats `rngWord == 1` as request-pending. A genuinely processed day whose final word equals 1 (rawFulfillRandomWords remaps 0 to 1 at line 2008; the unchecked nudge add in _applyDailyRng line 2091 can also land on 1) would store rngWordByDay[day] = 1, after which every advance takes the 1287 path returning (1, 0), never sealing the day and never re-requesting, until the 120-day deadman fires. Holds as safe only via the statistical invariant that a VRF word is uniform and non-inducible (~2^-255; nudges are committed before the word is known).

(c) Cosmetic / telemetry-only notes

1. Backfilled gap days are processed with coinflipBonus 0 and consume no nudges (documented at 2026, 2047-2049) — deliberate, since no gap day can be a level-0/first-jackpot bonus day.
2. Line 1333: with gapDays != 0 the foil-quest force is suppressed, and because rollDailyQuest runs exactly once per day (re-entry short-circuits at 1287) a stall spanning a level transition skips the forced foil daily for that level entirely — documented trade-off affecting only quest selection, not accounting.
3. Line 1287 returns gapDays = 0 on re-entry after a backfill tx; the caller's local `psd += gapDays` (line 448) is unaffected because storage purchaseStartDay was already updated atomically in the backfill tx.
4. Line 1301 `idx + 1` would revert (checked uint24) at idx = 2^24-1 — ~45,000 game-years out, unreachable.

REVIEW-STATUS: clean

---
## Chunk 9

(a) Definite inconsistencies

None. Within lines 1031–1121 every branch preserves the pool identity: each wei removed from `memFuture` (line 1041 `claimed`, line 1061 `spend`) is added to `claimableDelta` and credited to `claimablePool` exactly once (line 1112); the x00 keep-roll (1080–1082) and merge (1087–1088) are pure transfers between `memFuture`/`memCurrent`/`memNext`; the 15% drawdown (1102–1104) is a pure `memFuture`→`memNext` transfer. Worst-case combined x00 draw is bounded: BAF ≤ 20% of `baseMemFuture` (line 1034) plus Decimator ≤ 30% of `baseMemFuture` (line 1052), leaving `memFuture` ≥ 50% of base before the keep roll, so no in-range subtraction can underflow given the callee bounds in (b).

(b) Holds only via an outside-range invariant

1. Line 1041 (`memFuture -= claimed`): no underflow only because JackpotModule.runBafJackpot returns `claimableDelta ≤ poolWei`. Verified in HEAD: DegenerusJackpots.runBafJackpot's slices sum to exactly 100% of P (10+5+5+2×(3+2)+45+25), unawarded slices go to `returnAmountWei` (discarded — stays in futurePool), and the module folds only credited legs (`ethPortion ≤ amount`, whale-pass remainder ≤ `lootboxPortion`, ticket legs return 0). Invariant: BAF callee never credits more than the pool it was handed.
2. Lines 1060–1061 (`spend = decPoolWei - returnWei; memFuture -= spend`): both subtractions rely on DecimatorModule.runDecimatorJackpot returning exactly `poolWei` (already-snapshotted / zero qualifying burns, lines 235–237, 266–268 of the module) or 0 (line 281). Any intermediate return value > `decPoolWei` would underflow line 1060; the callee cannot produce one.
3. Lines 1036 and 1058 are self-CALLs executed while the pool slots in storage are stale relative to `memFuture`/`memCurrent`/`memNext`; lines 1108–1110 then overwrite `nextPool`/`futurePool`/`currentPrizePool`/`yieldAccumulator` wholesale. Safe only because the BAF/Decimator delegatecall paths write no pool slot: `_creditClaimable` → `balancesPacked` only (DegenerusGameStorage.sol:994), `_queueWhalePassClaimCore` → `whalePassClaims` + `balancesPacked` (DegenerusGamePayoutUtils.sol:33), `_jackpotTicketRoll` → `entriesOwedPacked`/`ticketQueue`, DecimatorModule → `decClaimRounds`/`decBucketOffsetPacked`. Invariant: reward-jackpot callees never touch the four consolidated pool slots or `claimablePool`; a future edit adding e.g. `_addFuturePrizePool` inside that path would be silently clobbered by line 1108.
4. Line 1112 bumps `claimablePool` for the Decimator `spend` even though no `balancesPacked` credit exists yet (winners claim later via claimDecimatorJackpot). Consistent only under the documented solvency invariant `claimablePool ≥ Σ (claimable + afking halves of balancesPacked)` with transient over-reservation (DegenerusGameStorage.sol:389–393).
5. Narrowing casts at 1108, 1109, 1112: `memFuture`/`memCurrent`/`claimableDelta` are sums of a handful of uint128-backed quantities; the uint128 casts cannot wrap only under the physical invariant total protocol-held wei << 2^128 (ETH supply ≈ 1.2e26 wei). The `+=` at 1112 is checked, so a violation reverts rather than corrupts.
6. Lines 1096–1097 division: safe only because PriceLookupLib.priceForLevel never returns 0 (minimum 0.01 ether across all tiers, PriceLookupLib.sol:21–41).
7. Line 1108 writes `nextPool = 0` on x00 levels (drawdown skipped at 1101). The next invocation's ratio computation (`(memFuture * 100) / memNext`, line 956 — outside this range, same function) divides by `memNext` unguarded, so this write is safe only under the invariant that nextPool receives ≥ 1 wei of purchase-revenue routing (JackpotModule `_addNextPrizePool`) before the next consolidation — i.e. a level cannot complete with zero next-pool inflow. Worth confirming that invariant is actually enforced by the purchase/goal path.
8. Line 1094 comment invariant (`purchaseLevel == storage level`, consolidation only on the lastPurchase leg under `rngLockedFlag`): the coinflip credit denominator uses `purchaseLevel` pricing; correctness of the 5% sizing depends on that caller-ordering invariant, not on anything in-range.

(c) Cosmetic / telemetry

1. Line 1079: `keepBps < 10_000` is always true — `total` ≤ 15 (five `%4` terms), so `keepBps` ∈ [3000, 6500]. Dead guard; the branch body is unconditional in practice.
2. Line 1054: the "draws 10% from current" distinction vs `baseMemFuture` is vacuous on the x5 path — `memFuture == baseMemFuture` there, since the BAF debit requires `prevMod10 == 0` and the yield dump requires `prevMod100 == 0`. The base/current split only matters at x00.
3. Line 1114: `RewardJackpotsSettled` emits the post-drawdown `memFuture` (after the 15% reservation on non-x00 levels), not the post-jackpot value; consumers reconstructing jackpot draws from this event must account for the drawdown. Telemetry only.
4. Line 1032: bit 0 of the same `rngWord` also feeds the additive-bps roll earlier in the function (line 979) and the module's slice entropy (which re-hashes); the BAF win/skip bit is raw bit 0. No exploitable correlation (all consumers are same-transaction, VRF-sealed), stylistic only.

REVIEW-STATUS: clean

---
## Chunk 10

(a) Definite inconsistencies
- None. Every reachable input to `updateVrfCoordinatorAndSub` (1912-1964) lands in exactly one of the three arms — genuine mid-day in flight (1927-1945), daily lock held (1946-1956), nothing in flight (fall-through) — and each arm either re-issues without touching accounting state or preserves state verbatim. `_unlockRng` (1969-1990) clears exactly the four RNG variables that are set as a group (`_finalizeRngRequest` :1850-1853 / mid-day request :1251-1253), so no variable is left half-cleared. No narrowing cast in range can wrap: `uint48(block.timestamp)` (1945, 1951) and `uint24 day` (1970) are far from their bounds; no subtraction exists in range.

(b) Holds only via an invariant outside the range
- 1944 (mid-day re-issue) vs the composite state {LR_MID_DAY=1, vrfRequestId!=0, rngLockedFlag=false, rngWordCurrent!=0}, reachable when the game-over terminal fallback (`_gameOverEntropy` :1436-1471) fires while a mid-day request is still outstanding (the fallback fills the reserved lootbox index via `_finalizeLootboxRng` :1465 but never clears `vrfRequestId`/LR_MID_DAY). A rotation then re-issues a spurious mid-day request. The already-finalized write-once lootbox word survives only because of the `rngWordCurrent != 0` early-return in `rawFulfillRandomWords` (:2005) — the mid-day fulfillment write `lootboxRngWordByIndex[index] = word` (:2015-2017) has no write-once check of its own, unlike `_finalizeLootboxRng` (:1379). Cost is one wasted LINK request. The same rotation also overwrites `rngRequestTime` (1945), the game-over "terminal-intent latch" (:1466-1471); harmless only because it stays nonzero and `rngWordByDay[day] != 0` short-circuits re-entry (:1396).
- 1949-1951 (daily re-issue): bypassing `_finalizeRngRequest` is correct only under the invariant that the original daily request already advanced LR_INDEX and performed the one-shot side effects (level increment, `_rewardTopAffiliate`, `ticketRedemptionOpen` close, `pickCharity` — :1832-1903); LR_INDEX-1 still names the reserved lootbox slot for the retry.
- 1954-1955 (preserve delivered daily word, no re-issue): safe against a late callback from the old coordinator only via `msg.sender != address(vrfCoordinator)` (:2004) after the repoint, plus the requestId-match / `rngWordCurrent != 0` guard (:2005).
- 1929-1930 (`vrfRequestId != 0 && !rngLockedFlag` keying): correctly excludes the `_gameOverEntropy` failed-request window (:1478-1480 sets `rngRequestTime` with `vrfRequestId == 0`) only under the invariant that `vrfRequestId` and `rngRequestTime` are always set together (:1251-1253, :1850-1852) and cleared together (`_unlockRng` :1972-1973, mid-day fulfillment :2018-2019).
- 1973-1975 (`_unfreezePool` at unlock): the checked uint128 adds `next + pNext` / `future + pFuture` (:1824) cannot revert only because pool totals are bounded by the contract's ETH+stETH balance, orders of magnitude below 2^128.
- `_unlockRng` intentionally does not clear LR_MID_DAY (drained by the advance flow :269, :366-367) or `totalFlipReversals` (consumed by `_applyDailyRng` :2087-2093; carry-over documented at 1958-1962). Consistency depends on those external paths running.
- 1917/1920: no zero-address or code-existence check on `newCoordinator`. With something in flight, a bad repoint reverts the whole rotation inside `_requestVrfWord` (fail-safe); with nothing in flight it repoints to a dead coordinator and halts future requests until a corrective rotation — bounded by the ADMIN + sDGNRS-governance trust boundary.

(c) Cosmetic / telemetry
- Stale line anchors in comments: "(-> :1768)" at 1949 and "the :1761 rngWordCurrent!=0 guard" at 1952-1953 point into `_setVrfConfig`/`_lrAdvanceIndexClearPending` (:1758-1771); the referenced guard and daily fulfillment branch actually live at :2005 and :2010-2012.
- 1982-1989: `PrizePoolDailySnapshot` is indexer-facing telemetry only; the `address(this).balance + steth.balanceOf(...)` solvency figure is a snapshot, not accounting state.
- 1963: `VrfCoordinatorUpdated` emits only old/new coordinator; subId and keyHash changes are not observable from the event.

REVIEW-STATUS: clean

---
## Chunk 11

(a) definite inconsistencies

None. Every reachable input path through `requestLootboxRng` (HEAD `contracts/modules/DegenerusGameAdvanceModule.sol:1189-1254`) either reverts before any state write or performs the full, atomic effect set {optional slot-swap + LR_MID_DAY=1 (:1241-1242), VRF request (:1247), index advance + pending clear (:1250), vrfRequestId/rngWordCurrent/rngRequestTime writes (:1251-1253)}. Unit math checks out: pendingEth and threshold are both milli-ETH unpacked via `_unpackMilliEthToWei` (×1e15, storage :1672), so the comparison at :1233 is like-for-like in wei; the FLIP conversion `(pendingFlip * priceWei) / PRICE_COIN_UNIT` at :1225-1227 is (FLIP-wei × wei-per-mint) / (1000e18 FLIP-wei-per-mint) = wei, the exact inverse of the conversion at :1096; overflow needs priceWei > ~1e47, unreachable. Index math is self-consistent: purchases before the call accumulate under index N, `_lrAdvanceIndexClearPending` (:1767) moves the write target to N+1, and the mid-day fulfill branch stores the word at N (index−1, :2011), so no box purchased after the request can ever be resolved by this word (freeze invariant preserved). The word at N is write-once (a repeat call stores at N+1), so no re-roll of a delivered lootbox word is reachable.

(b) observations that hold only via an invariant maintained outside this range

1. `:1252 rngWordCurrent = 0` is safe only because of the paired-state invariant "a delivered-but-unconsumed word always coexists with `rngRequestTime != 0` or `rngLockedFlag`": the daily fulfill branch sets `rngWordCurrent` only under `rngLockedFlag` (:2010-2012, blocked here by :1190), `_applyDailyRng` (:2095) runs inside the locked window, and the two are cleared only together in `_unlockRng` (:1971-1974). If any path ever cleared `rngRequestTime` while leaving a live daily word, :1252 would silently erase it.
2. `:1198 (nowTs - 82620)` checked subtraction cannot underflow only because `block.timestamp > 82620` on any real chain; the modulus is aligned with the day boundary because `GameTimeLib.JACKPOT_RESET_TIME == 82620` (GameTimeLib.sol:14), the same constant used by `_simulatedDayIndexAt` (:1195) — the two checks stay coherent only while that constant is shared.
3. `:1240-1241` — flipping the global `ticketWriteSlot` via `_swapTicketSlot` is safe only because (i) `rngLockedFlag` is held for the entire multi-tx daily/jackpot batch window, so no partially-drained read cohort can coexist with the :1190 guard passing, and (ii) `ticketsFullyProcessed == true` implies the purchase-level read slot is drained; residual read-slot entries at unrelated levels are deferred one cycle, never lost (documented tolerance in `_swapTicketSlot`, :1787), and far-future queues use the slot-independent bit-22 key (`_tqFarFutureKey`, storage :872).
4. `:1250` clears the pending accumulators before the word is delivered; on a permanent mid-day VRF stall the boxes at index N would orphan, but the stall is recovered outside this range by the `MIDDAY_RNG_STALL_TIMEOUT` promotion in rngGate (:317-351), `updateVrfCoordinatorAndSub`'s mid-day re-issue branch (:1935-1945, keyed on LR_MID_DAY + vrfRequestId), and `_backfillOrphanedLootboxIndices` (:2060).
5. `:1238 level + 1` (uint24) cannot wrap only because `level` is bounded far below 2^24 by the game's level-cap economics.
6. The mid-day fulfill branch computes `LR_INDEX - 1` in uint48 (:2011); no underflow only because the index initializes to 1 (storage :1606) and this function has already advanced it to ≥2 before any mid-day fulfillment can occur.
7. No `gameOver` guard in range: a post-gameover call is blocked in practice because purchases stop at gameover and the terminal entropy path finalizes lootbox RNG / clears pendings (`_finalizeLootboxRng`, :1465), leaving `NoPendingLootbox` (:1221) to reject the call; the gameover drain's `entropyCommitted` check (:740-746) additionally treats a set LR_MID_DAY flag as an entropy boundary.

(c) cosmetic / telemetry-only notes

1. `:1233` — a zero threshold disables the gate entirely (intended owner-tunable semantics); request frequency is still self-limited because :1250 zeroes the accumulators, so each request needs fresh nonzero pending plus the :1202 in-flight and :1198 window guards.
2. `:1224-1228` — if `PriceLookupLib.priceForLevel(level)` returns 0, pure-FLIP pending values as 0 ETH-equivalent and the call reverts `BelowThreshold` when a threshold is set; liveness-only, and the comment at :1211-1213 already documents the one-cycle fallback via the daily advance.
3. Pending accumulators quantize at 0.001 ETH / 1 FLIP (LR_ETH_SCALE/LR_FLIP_SCALE, storage :1623-1625); sub-resolution dust never counts toward the threshold — a property of the packing scale, not this function.
4. `:1194 uint48(block.timestamp)` truncation is a non-issue until year ~8.9M.

REVIEW-STATUS: clean

---
## Chunk 12

(a) Definite inconsistencies
- None. Walked every branch of `_processPhaseTransition` (1668–1687), `_autoStakeExcessEth` (1692–1702), `_requestRng` (1708–1715), `_tryRequestRng` (1717–1736), `_requestVrfWord` (1741–1752), `_setVrfConfig` (1758–1762) in `HEAD:contracts/modules/DegenerusGameAdvanceModule.sol`. No reachable input makes a narrowing cast wrap, a checked subtraction revert on a valid value, or a pool/supply/claimable total inconsistent. Specifics: line 1670 `purchaseLevel + 99` is checked uint24 math (see (b)1); line 1695 `ethBal <= reserve` early-return guarantees line 1696 `ethBal - reserve` never underflows; line 1697 stakes only the surplus so post-call `address(this).balance == claimablePool` exactly when staking fires — the documented solvency invariant `balance + steth.balanceOf(this) >= claimablePool` (DegenerusGame.sol:18) holds even under Lido's 1–2 wei share-rounding shortfall, since that shortfall lands entirely on the non-reserved staked portion; lines 1697–1701 catch path emits telemetry only, no state written, so a Lido failure leaves all accounting untouched; `_tryRequestRng` writes no state on the catch path (1735); `_setVrfConfig` is three plain slot writes with no derived accounting. Per-level continuity of the perpetual-entry accounting also checks out: `level` is written only at line 1884 (`level = lvl`, +1 per transition), every level end sets `phaseTransitionActive` (line 817, `_endPhase`), and the seed path (DegenerusGame.sol `initPerpetualTickets`, levels 1–100 at 16 entries) meets the advance path's `targetLevel = newLevel + 100` (first transition → newLevel 1 → target 101) with no gap and no overlap.

(b) Holds only via an invariant maintained outside the range
1. Line 1670 (`purchaseLevel + 99`, checked uint24): cannot overflow only because `level` is lifecycle-bounded — it increments by exactly 1 per level transition (sole write at line 1884), at most one per day even in turbo, so reaching 2^24−100 is unreachable within any game lifetime. Invariant: level monotone +1 per multi-day cycle.
2. Lines 1671–1682 (the two 16-entry `_queueEntries` credits): exactly-once-per-level crediting is enforced entirely by the caller's resume marker, not locally. Lines 476–497: `resumingFF` (`ticketLevel == ffLevel | TICKET_FAR_FUTURE_BIT`) gates the call, and the marker is deliberately re-asserted at line 496 when a batch both works and finishes, so the next advance skips `_processPhaseTransition`. Invariant: the FF-drain `ticketLevel` marker persists across advances until the FF queue drains with no work; if any other code path cleared `ticketLevel` mid-transition, SDGNRS/VAULT would be double-credited 16 entries.
3. Lines 1675/1681 `rngBypass = true` (skips the far-future `RngLocked` guard in `_queueEntries`, DegenerusGameStorage.sol:682): safe only because `targetLevel = purchaseLevel + 99` routes to a far-future key ~99 levels from resolution (its resolving word is not the frozen current word) and never collides with the FF level being drained this transition (`purchaseLevel + 4`). Invariant: far-future key routing (`targetLevel > level + 5`) plus the 95-level separation between the perpetual target and the FF drain level.
4. Lines 1671–1682 with `_queueEntries`' `unchecked { owed += entries; }` (DegenerusGameStorage.sol:692): no uint32 wrap only because each (vault, targetLevel) bucket receives exactly 16 protocol entries once (invariant (b)2) and any additional player-gifted entries toward wrap would need ~4.29e9 entries of paid volume at one level. Invariant: economic bound + exactly-once protocol credit.
5. Lines 1692–1702: reserving only `claimablePool` in raw ETH is sufficient for the other liability pools (nextPrizePool/futurePrizePool/pending/lootbox pending) only because those pools pay out by *crediting* `claimablePool` rather than sending ETH, and player claim paths carry stETH fallbacks (`_payoutWithEthFallback` / `_payoutWithStethFallback`, DegenerusGame.sol:1391–1395). Note `withdrawAfkingFunding` (DegenerusGame.sol:1417–1428) is raw-ETH-only with no stETH fallback; it stays funded because afkingFunding rides *inside* claimablePool ("tandem" credit/debit), so post-stake `balance == claimablePool >= total afking`. Invariant: every raw-ETH outflow debits claimablePool in tandem (or spends only pre-stake excess).
6. Lines 1733 and 1708–1714: on `_tryRequestRng`'s catch path the RNG lock/fallback state is installed by the *caller* (gameover path, lines 1478–1481: `rngWordCurrent = 0; rngRequestTime = ts`), not locally — `_tryRequestRng` returning false with no state change is only consistent because its sole caller installs the fallback timer. Similarly, retry/fresh classification and the level pre-increment guard live in `_finalizeRngRequest` (lines 1828–1904: `isRetry`/`isDailyRetry` off `vrfRequestId`/`rngRequestTime`/`rngWordCurrent`/`rngLockedFlag`), so lootbox-index single-advance and single level increment per jackpot day are invariants of that function, outside this range.

(c) Cosmetic / telemetry-only
1. Line 1669 comment "16 generic tickets per level" is a unit slip: `VAULT_PERPETUAL_ENTRIES = 16` is in *entry* units (4 entries = 1 ticket, per `_queueEntries` natspec and the seed path's own comment "16 entries (= 4 whole tickets)" at DegenerusGame.sol:226). Code is self-consistent with the seed path (16 entries both sides); only the comment misstates the unit.
2. Lines 1721–1731 duplicate `_requestVrfWord`'s request struct inline (a `try` requires a direct external-call expression, so the internal helper can't be reused). Grep-verified the parameters are identical (same key/sub/`VRF_REQUEST_CONFIRMATIONS`/gas limit/1 word/empty extraArgs) — no behavioral drift, duplication only.
3. Line 1700 `StEthStakeFailed(stakeable)` is telemetry only; no accounting depends on it.
4. Lines 1758–1762 `_setVrfConfig` performs no zero-address/zero-key validation; sole external caller is governance-gated `updateVrfCoordinatorAndSub` (admin + sDGNRS-holder vote), consistent with the project's admin-trust posture.

REVIEW-STATUS: clean

---
## Chunk 13

(a) Definite inconsistencies

None. Branch walk of the range (all under `!inJackpot` / jackpot-phase tail):

- L541: `purchaseLevel == 1` is only reachable with `purchaseLevel = lvl + 1` (this branch requires `!lastPurchase`, so the ternary's `lvl` arm is excluded) — no aliasing with the locked-transition case, and L567's `levelPrizePool[purchaseLevel - 1]` index is exactly `lvl`, no underflow (`purchaseLevel >= 1` always).
- L574-578: `day - psd` at L576 is guarded by `day >= psd` in the same conjunction at L574 — no checked-subtraction revert, including after the gap-backfill `psd += gapDays` adjustment (the `gapDays != 0` path already broke out at STAGE_GAP_BACKFILLED before reaching here). `compressedJackpotFlag = 1` (L577) cannot clobber the turbo value 2: the turbo latch sets `lastPurchaseDay`, which excludes this branch on every later advance.
- L587: `purchaseLevel + 1` / L562-563 `purchaseLevel + 4` uint24 arithmetic — overflow needs level near 2^24, unreachable at one transition per multi-day cycle.
- L600: executes exactly once per transition — the future-batch gate (L588-596) breaks before it on every partial pass, and `prizePoolFrozen` (held from the request until `_unlockRng`) routes intervening revenue to `prizePoolPendingPacked`, so the snapshot value is stable across resumed advances; no double-write, no drift between the L600 snapshot and the `memNext` the consolidation at L602 then consumes.
- L615-617: `jackpotPhaseFlag = true` and `lastPurchaseDay = false` flip together, matching the phase-pair invariant the storage natspec documents.
- L631-641: `jackpotCounter` is read at L633 after the delegatecall at L632, so it sees the module's increment; the `_endPhase` path (L634) deliberately skips `_unlockRng`, leaving `dailyIdx` unadvanced so the same day/word carries into the phase-transition leg which seals at its own `_unlockRng(day)` (L502).
- L644: no unlock/no break — `dailyJackpotCoinTicketsPending` is set inside the module, `advanceDue` stays true, and the next advance completes the split half with the same pinned day word. No state left half-applied.

(b) Holds only via an invariant maintained outside this range

1. L574 latch guard / L600-608 level identity: correctness of `purchaseLevel == storage level` on the transition leg (asserted by `_consolidatePoolsAndRewardJackpots`'s coinflip-credit comment and the L600 index) rests on two external invariants: (i) `rngWordByDay[dIdx+1] != 0 ⟹ rngLockedFlag` still held (the word is written only in `_finalizeRngRequest` under lock, and the lock clears only in `_unlockRng`, which simultaneously advances `dailyIdx`), and (ii) the request-time level pre-increment in `_requestRng` (module L1876-1884, `level = lvl` when `isTicketJackpotDay && !isDailyRetry`). The `day == wallDay` term at L574 exists precisely to keep RNGREUSE replay days from latching and bypassing (ii).
2. L566 `targetMet` manipulation-resistance: the compared `_getNextPrizePool()` is a frozen snapshot — `prizePoolFrozen` (set at request, cleared in `_unlockRng`) diverts post-request purchases to the pending buffer, so the pool cannot be topped up after the VRF word is known. Invariant: freeze window covers [request → unlock].
3. Division-by-zero reachable through L602: `_consolidatePoolsAndRewardJackpots` computes `ratioPct = (memFuture * 100) / memNext` with no zero guard. Safe only because every latch requires live `nextPool >= levelPrizePool[lvl]`, all realized targets are positive (constructor bootstrap `levelPrizePool[0] = 50 ether`, DegenerusGame.sol:209; x00 targets `futurePrizePool / 3` from `_endPhase`, positive in any funded game), and the frozen pool cannot decrease between latch and consolidation. A zero-value-game degenerate case is admin-self-break class.
4. L633 phase termination relies on the jackpot module incrementing `jackpotCounter` inside `payDailyJackpotCoinAndTickets` (JackpotModule L596-616, including the compressed `counterStep`); a module path that returned without incrementing would loop the jackpot phase past JACKPOT_LEVEL_CAP indefinitely.
5. L634/L644 deferred day-seal: relies on the RNGREUSE clamp in the advance preamble (`day = dIdx + 1` when `rngWordByDay[dIdx+1] != 0`) to pin subsequent advances to the unsealed day so the deferred jackpot half / phase-transition housekeeping resolve against the same word — `dailyIdx` never skips a paid day.
6. uint128 narrowings behind L602 (`_setPrizePools`, `currentPrizePool = uint128(memCurrent)`, `claimablePool += uint128(claimableDelta)`) are unchecked casts, safe only under the total-ETH-supply ≪ 2^128 bound.
7. L600's snapshot is also the sizing input for `payDailyJackpot` (JackpotModule L1849 reads `levelPrizePool[lvl - 1]`) and the MintModule gate (L957); both readers evaluate at frozen-time like the writer, so the pending-revenue exclusion is applied consistently.

(c) Cosmetic / telemetry-only

1. Storage natspec for `levelPrizePool` (DegenerusGameStorage.sol:1201, "used for affiliate DGNRS weighting") is stale relative to actual readers (target/threshold checks and jackpot sizing; affiliate weighting uses `levelDgnrsPacked`).
2. L650 `emit Advance(stage, lvl)`: `lvl` is the old level on stages ≤ STAGE_PURCHASE_DAILY but the pre-incremented new level on STAGE_ENTERED_JACKPOT — indexer-facing semantics only, no state impact.
3. L541-557 genesis asymmetry: level-0 purchase days pay coin jackpots over levels [1,1] (main word) plus [2,5] (salted word) — 5 target levels vs 4 (`[pL+1, pL+4]`) on the else branch, and no ETH `payDailyJackpot(false, ...)` call; intentional bootstrap (no prize pool exists yet), FLIP-mint only, no pool accounting touched.

REVIEW-STATUS: clean

---
## Chunk 14

(a) Definite inconsistencies

None found. Every branch in lines 421-540 was walked (subscriber-drain backfill deferral 421-429, rngGate call + gap-backfill decouple 441-466, phase-transition/FF-promotion resume 469-507, near-future prep gate 511-521, current-level batch 526-533, purchase-phase entry 536-540). No reachable input makes a running total diverge, a narrowing cast wrap (only cast in range is line 448 `uint24(gapDays)`, bounded ≤119, see b-2), or a checked subtraction revert on a valid value; no pool/supply/pending total is left inconsistent at any break point.

(b) Observations holding only via an out-of-range invariant

1. Lines 416-424 (STAGE_SUBS_BACKFILL_DEFERRED): the deferral predicate mirrors rngGate's backfill entry (rngGate:1292,1301) but omits rngGate's `rngWordByDay[day] != 0` early return (rngGate:1287). It correctly predicts "next advance will backfill" only under the contiguous day-word-recording invariant: words are written solely by `_backfillGapDays` (fills dailyIdx+1 upward, before `_applyDailyRng` in the same rngGate call) plus the line-191 RNGREUSE clamp, so `rngWordByDay[dIdx+1] == 0` implies `rngWordByDay[day] == 0`. `_gameOverEntropy` (1396-1400) can break contiguity but only on paths that return at line 229-236 before reaching this range.

2. Line 448 `psd += uint24(gapDays)` mirrors rngGate:1311 `purchaseStartDay += gapCount`, which credits the UNCAPPED gap (`day - idx - 1`) while `_backfillGapDays` caps actual backfill at 120 days (2040). purchaseStartDay/day-word accounting stays consistent only because `_vrfDeadmanFired()` (`_simulatedDayIndex() - dailyIdx > 120`, storage:1546) is checked at line 229 on every phase (`(!inJackpot && !lastPurchase) || _vrfDeadmanFired()`) and routes to the game-over path first, so the maximum reachable gapCount here is 119 — the cap never binds and no day-word hole (with its stranded per-day coinflip resolutions) can form. Invariant: VRF-deadman threshold (120) ≤ backfill cap + 1.

3. Lines 477-482: skipping `_processPhaseTransition` on resume (preventing double-queueing of 2×16 VAULT_PERPETUAL_ENTRIES to SDGNRS/VAULT, 1668-1682) hinges on the `ticketLevel == ffLevel | TICKET_FAR_FUTURE_BIT` marker surviving between transition advances. Holds because no other writer touches ticketLevel while phaseTransitionActive: the mid-day path returns at 278 before this block, `_prepareFutureTickets` (the other ticketLevel writer via the mint module) is unreachable while the block breaks at 499/506, and player purchases route to write keys only.

4. Lines 495-497 (marker re-assert after a worked-and-finished FF batch): correctness of the follow-up advance relies on mint-module semantics — an empty-queue `processFutureTicketBatch` call clears `ticketLevel`/`ticketCursor` and returns (worked=false, finished=true) (MintModule:325-328) — and on the routing invariant stated in the comment at 472 that no new entries can land in the ffLevel far-future queue after the boundary moved. Both verified in MintModule for the HEAD tree.

5. Line 503 `purchaseStartDay = day` can store an RNGREUSE-clamped past day (a multi-advance transition drain that crosses wall-day boundaries keeps `day` pinned at the sealed jackpot day via line 191). The purchase-day counters (turbo at 216-218, compressed flag at 576, skim day-steps) are not distorted only because the next fresh-word rngGate backfills the elapsed days and credits `purchaseStartDay += gapCount` (1311), netting psd = wallDay − 1. Invariant: stall days are always either clamped-replayed or gap-credited.

6. Lines 501-506: breaking at STAGE_TRANSITION_DONE without paying a jackpot is correct only because a transition always begins on a fully-paid jackpot day — `_endPhase` (817-822) is reached solely at line 634, after `payDailyJackpotCoinAndTickets` (632) completed the day's split, and `_unlockRng` is deferred so every subsequent transition advance replays that same sealed day.

(c) Cosmetic / telemetry-only

1. Line 448: the local `psd` update is inert on every live path — `gapDays != 0` always breaks at 464, and the only later readers of `psd` (574, 576, 607) execute exclusively with `gapDays == 0`. Local/storage-mirror hygiene only.

2. Line 449 `rngWord == 1` sentinel: a genuine daily word equal to 1 (raw 0→1 remap at rawFulfillRandomWords:2008, a natural 1, or an unchecked nudge wrap in `_applyDailyRng`:2091 landing on 1) would be misread as "request sent", causing repeated `_swapAndFreeze` and a never-sealing day until the deadman. Probability ≈2⁻²⁵⁵; standard accepted sentinel-collision design.

3. Lines 416-424: the deferral fires even when the completing subscriber chunk was trivially small (e.g., one stamp), costing one extra advance transaction before the backfill. Gas-scheduling conservatism; no accounting effect.

4. Lines 437-440: `bonusDay`/`coinflipBonus` are recomputed on advances that take rngGate's cached-word early return (1287), where the bonus is discarded — coinflip payouts run exactly once per day on the fresh-word path, so no double-bonus is possible; the computation is merely wasted work on replay advances.

5. Line 474 `purchaseLevel + 4` (checked uint24 add) and line 476/480 `ffLevel | TICKET_FAR_FUTURE_BIT` (bit = 1<<22, storage:182) would only overflow/alias at level ≥ 4,194,299 — unreachable at protocol cadence.

REVIEW-STATUS: clean

---
## Chunk 15

(a) Definite inconsistencies

None. Every branch of `_finalizeRngRequest` (HEAD lines 1828-1904) was walked against all four reachable entry states — fresh request, 12h daily retry, promoted mid-day→daily request, and gameover-fallback-timer state — and no reachable input makes a counter diverge, a cast wrap, or a checked subtraction revert on a valid value:

- Fresh (`vrfRequestId==0`): 1843-1845 advances the lootbox index exactly once; pending ETH/FLIP accumulators zeroed in the same packed write (`_lrAdvanceIndexClearPending`, 1767-1776), matching a bucket that was never reserved.
- Daily retry (`isRetry && rngLockedFlag`, 1842): no second index advance (1843), no second `level` increment or affiliate reward (guard at 1880), and the window-close block 1860-1874 re-runs idempotently (`ticketRedemptionOpen` already false, or same predicate/same `jackpotCounter` since no jackpot can pay without the word).
- Promoted mid-day→daily (`isRetry && !rngLockedFlag`): index correctly NOT re-advanced (mid-day path 1247-1250 already advanced it), while the level increment at 1880-1884 correctly still fires; the overwritten `vrfRequestId` (1850) orphans the stale mid-day request, which `rawFulfillRandomWords` rejects at 2005.
- `uint48(block.timestamp)` (1852) cannot truncate on any realistic timestamp; `jackpotCounter + jpStep` (1871) is uint8 arithmetic bounded at 5+5=10; `lvl - 1` (1902) cannot underflow because every `isTicketJackpotDay=true` caller passes `purchaseLevel >= 1` (see (b)-4).
- Compressed/turbo close schedule 1861-1873 (steps 1 / 1,2,2 / 5) closes `ticketRedemptionOpen` exactly at the request preceding the final jackpot payout in all three `compressedJackpotFlag` modes, matching the payer's `isFinalPhysicalDay`.

(b) Observations holding only via out-of-range invariants

1. Lines 1835-1837 — `isRetry` classification depends on the invariant "`vrfRequestId != 0` ⇔ an unfulfilled VRF request is in flight." Maintained outside the range by `rawFulfillRandomWords` clearing it on mid-day fulfillment (2018), `_unlockRng` clearing it after daily processing (1973), and the gameover failed-request fallback deliberately leaving it 0 while re-arming only `rngRequestTime` (1478-1480; rotation comment 1938-1941 documents the same invariant). If `vrfRequestId` could ever be stale-nonzero with nothing in flight, a fresh request would skip the index advance and two RNG buckets would collide.
2. Line 1851 — `rngWordCurrent = 0` would discard a delivered-but-unprocessed daily word, but is safe because every path into `_requestRng`/`_tryRequestRng` first requires `rngWordCurrent == 0` (rngGate 1289-1292/1362/1372, mid-day stall promotion guard at 315-316, `_gameOverEntropy` 1398-1399 plus the "word set ⇒ rngRequestTime set" pairing in `rawFulfillRandomWords`/`_unlockRng`).
3. Lines 1880-1903 — the block can never execute with `lvl = level` (raw, un-promoted) from the gameover path: `_tryRequestRng(…, lastPurchaseDay)` at 1474 is reachable only when `rngRequestTime == 0` and `deadman == false` (1432-1433), and `_livenessTriggered` (storage 1524-1529) admits the gameover path in a `lastPurchaseDay`/jackpot phase only when the deadman HAS fired — so `isTicketJackpotDay` is false whenever 1474 executes. Otherwise `_rewardTopAffiliate(level)` would double-pay the previous level's top affiliate and `_setLevelDgnrsAllocation(level, …)` would overwrite an allocation players may already be claiming against. Structural protection, not local.
4. Line 1902 — `lvl - 1` no-underflow relies on all `isTicketJackpotDay=true` call sites passing `purchaseLevel` (= `level + 1` before the lock, = already-incremented `level >= 1` on a retry): advance path line 226/334, rngGate call site 441-445. The retry case additionally never reaches 1902 (isDailyRetry guard).
5. Lines 1861-1870 — `jpStep` is a byte-for-byte mirror of JackpotModule's `counterStep` (JackpotModule 312-328); verified identical at HEAD. The window-close boundary is correct only while the two copies stay in lockstep; divergence would close the FLIP ticket window a day early or late relative to the final payout.
6. Line 1871 — no uint8 wrap relies on `jackpotCounter <= JACKPOT_LEVEL_CAP` (5), maintained by JackpotModule's bounded `counterCached + counterStep` write (616) and the reset to 0 at `_endPhase` (821).
7. Idempotency of 1860-1874 across a daily retry relies on `jackpotCounter` being frozen while a daily request is outstanding (jackpot payouts require the delivered word, which the retry precondition `rngWordCurrent == 0` excludes).

(c) Cosmetic / telemetry-only

1. Lines 1861-1870 duplicate JackpotModule's step derivation rather than sharing a helper — pure maintenance-surface note given the lockstep requirement in (b)-5; no behavioral effect at HEAD.
2. Lines 1886-1895 decimator latch is a pure boolean telemetry/window flag driven off the strictly-sequential `level = lvl` writer (sole writer, +1 steps), so the open-at-x4/x99, close-at-x5/x00 latch can never skip a boundary; no accounting impact.
3. Comment at 1847-1848 ("lootboxRngIndex - 1 still points to the pending index regardless of request ID") is accurate for both retry flavors, including the promoted mid-day case — no code effect.

REVIEW-STATUS: clean

---
## Chunk 16

(a) Definite inconsistencies
  none.

(b) Sound only because of an invariant maintained outside lines 666-815

- wireVrf (665-676) unconditionally re-runs `_setVrfConfig` and overwrites `lastVrfProcessedTimestamp` (675) on every ADMIN call, with no once-only latch. A second call mid-game would reset the governance stall-timer baseline. Safe ONLY because the sole ADMIN caller, DegenerusAdmin, invokes `gameAdmin.wireVrf(...)` exclusively from its constructor (DegenerusAdmin.sol:482, inside the constructor at :469); the post-deploy rotation path is `updateVrfCoordinatorAndSub`. Invariant: "DegenerusAdmin exposes no post-deploy path to wireVrf." Nothing in range enforces it.

- drainLevel narrowing (731): `_gameOverTicketLevel(lvl)` can return `lvl + 1` (storage :641), a uint24 add that wraps to 0 at `lvl == type(uint24).max`, and `_tqReadKey/_tqWriteKey` OR that into TICKET_SLOT_BIT (bit 23). Safe only under the invariant that `level` stays far below 2^24 (and below bit 22/23), maintained by the level state machine outside this range.

- Cross-tx stability of drainLevel (731, 746-747, 803-808): the terminal drain runs over multiple transactions, and `_gameOverTicketLevel` must return the same value on each so DRAIN (here) and the terminal-jackpot READ (GameOverModule) hit the same trait bucket. This holds only because `jackpotPhaseFlag`, `lastPurchaseDay`, and `rngLockedFlag` do not change across the drain window: `_gameOverEntropy` leaves phase flags intact, and its VRF-death fallback branch deliberately does not set `rngLockedFlag` (so the ternary at storage :641 is stable). Invariant: liveness gating blocks new buys and the fallback path never flips rngLockedFlag. Verified consistent, but enforced outside range.

- The transient state (lastPurchaseDay=true ∧ rngLockedFlag=false) that would make the `_gameOverEntropy(...,lastPurchaseDay)` call (761) issue a *fresh* `_tryRequestRng` with the raw `lvl` — which would run `_finalizeRngRequest`'s `level = lvl` as a no-op and mis-promote, desyncing cohort routing from drainLevel — is never reached: whenever the deadman routes here with lastPurchaseDay set, `_gameOverEntropy` takes the deadman historical-fallback branch (returns a real word), not the fresh-request branch. In the turbo+deadman entry (advanceGame :213 sets lastPurchaseDay without a request, then :229 routes to game-over via `_vrfDeadmanFired()`), `deadman` is true so the fallback branch is taken and level is intentionally NOT promoted, so drainLevel=`lvl+1` correctly matches the un-promoted purchase cohort. Correctness depends on `_gameOverEntropy`'s branch ordering, outside range.

- Terminal `_unlockRng(day)` (809) → `_unfreezePool()` does not double-credit or resurrect pending pools even though the game-over path froze nothing itself: `handleGameOverDrain` (delegatecalled at 803) zeroes all three pools and sets `prizePoolFrozen = false` / `prizePoolPendingPacked = 0` before returning, so the subsequent `_unfreezePool` is a no-op. Invariant maintained in GameOverModule (`handleGameOverDrain` clears freeze), not here.

- FUND-RELEASE swallow (798, `dOk=false` falls through to handleGameOverDrain): a reverting `processTicketBatch` leaves the read cohort undrained (forfeits trait eligibility) but does not corrupt any pool/supply total, because the terminal drain works off physical balance (`address(this).balance + steth.balanceOf`) minus `claimablePool`, not off ticket-materialization state. Consistency of the drain therefore does not depend on the swallowed batch succeeding — a property of GameOverModule's balance-based accounting, outside range.

(c) Cosmetic / telemetry-only

- `lastVrfProcessedTimestamp = uint48(block.timestamp)` (675) feeds only governance stall detection (read at DegenerusGame.sol:2241 and in DegenerusAdmin); it is not part of value accounting. The `uint48` cast cannot overflow for any realistic timestamp. The var shares its slot with `totalFlipReversals` (uint64); the partial-slot write is a normal read-modify-write and preserves the neighbor (0 at deploy regardless).

- `emit VrfCoordinatorUpdated(current, coordinator_)` (676) reports the pre-write coordinator as `current`; purely informational.

- Both game-over exits return `STAGE_TICKETS_WORKING` (789, 796) even on the "read snapshot complete" branch (796), where `ticketsFullyProcessed` is set true and the caller is asked to retry; the finished-vs-more distinction is intentionally collapsed for the caller's retry loop (telemetry stage only, no state effect).

REVIEW-STATUS: clean

---
## Chunk 17

I have the authoritative HEAD source and all referenced declarations (LR packing/`_lrRead` in storage, `_applyDailyRng`, `_vrfDeadmanFired`, `_finalizeRngRequest`/`_lrAdvanceIndexClearPending`, the caller at 759-767, `resolveRedemptionPeriod`, `processCoinflipPayouts`). Findings for the two in-range functions (`_finalizeLootboxRng` 1377-1382, `_gameOverEntropy` 1390-1481):

(a) DEFINITE INCONSISTENCIES
None.

(b) HOLDS ONLY BY AN INVARIANT MAINTAINED OUTSIDE THIS RANGE
- Line 1378 (`uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;`): the checked `- 1` underflow-reverts iff the packed lootbox index is 0. Safe only by the storage invariant that `lootboxRngPacked` is initialized with `lootboxRngIndex = 1` (DegenerusGameStorage) and is exclusively incremented by `_lrAdvanceIndexClearPending` (never decremented). Invariant: **lootbox index init=1 + monotonic increment**.
- Lines 1380 / 1420 / 1465 (`_finalizeLootboxRng` writes to `index-1`): writes the terminal word into the *most-recently-reserved* bucket. Correct only because the index is advanced at request time (`_finalizeRngRequest`:1845 / `requestLootboxRng`:1250), so `index-1` names the pending reservation. Invariant: **index advanced-at-request, so `index-1` == the in-flight/last-reserved bucket**.
- Line 1379 (`if (lootboxRngWordByIndex[index] != 0) return;`): the deadman branch (1432) can enter with `rngRequestTime == 0` (deadman is purely day-based via `_vrfDeadmanFired`), i.e. no request advanced the index this cycle, so `index-1` may already be finalized. No overwrite occurs — but only because this write-once guard is present and every real word reaching finalize is non-zero. Invariant: **finalize words are always non-zero** (VRF `word==0→1` in `rawFulfillRandomWords`; `_getHistoricalRngFallback` forces `!=0`; the fallback `-= totalFlipReversals` at 1444 is exactly re-added inside `_applyDailyRng`:2088, so the net word equals the non-zero historical value).
- Line 1434 (`ts - rngRequestTime < GAMEOVER_RNG_FALLBACK_DELAY`): checked subtraction. Non-underflowing because the enclosing `if (rngRequestTime != 0 || deadman)` plus the `!deadman &&` short-circuit guarantee `rngRequestTime != 0` whenever this is evaluated, and `rngRequestTime` is always a past `block.timestamp` (≤ `ts`). Invariant: **`rngRequestTime` only ever set to `block.timestamp`**.
- Lines 1400 / 1445 (`_applyDailyRng(day, …)` sets `rngWordByDay[day]`): single-application per `day` relies on the top guard `if (rngWordByDay[day] != 0) return` (1396) plus advance control-flow, which also stops `rngGate`'s `_applyDailyRng` (1316) from double-applying for the same day.

(c) COSMETIC / TELEMETRY / NEGLIGIBLE
- Lines 1381 / 1421 / 1466 emit `LootboxRngApplied(index, word, vrfRequestId)` with `vrfRequestId` still holding the pre-`_unlockRng` request id (not cleared until 1974). Telemetry only.
- Return-value sentinel collision: if an applied word (branch-2 `currentWord` at 1400 or fallback at 1445) equals exactly `1`, the caller (767) misreads it as "request sent" and skips the drain for that tx. Self-heals on the next advance because `dayWord = rngWordByDay[day]` (752) is then non-zero and the `if (dayWord == 0)` gate (759) bypasses `_gameOverEntropy`; the stored `rngWordByDay[day]==1` is used consistently by drain/coinflip. Probability ~2⁻²⁵⁶; at most a one-tx delay, no accounting divergence.
- Theoretical `rawWord + nudges` wrap to 0 in `_applyDailyRng` (2088, unchecked) would zero `rngWordCurrent`/`rngWordByDay[day]`; requires `rawWord ∈ [2²⁵⁶−2⁶⁴, 2²⁵⁶−1]` (nudges bounded by uint64). Not a practically reachable input.
- Genesis edge: at `index==1` with no prior reservation, `_finalizeLootboxRng` targets bucket 0; harmless dead write (no consumer reads an unreserved bucket 0, and the write-once guard blocks any later collision). Same index-0 convention is used uniformly by `rngGate`:314 and `rawFulfillRandomWords`:2015.

REVIEW-STATUS: clean

---
## Chunk 18

(a) definite inconsistencies

1. `_prepareFutureTickets` destroys the resume cursor of an in-flight current-level ticket batch, breaking monotonic drain progress (quadratic re-scan; hard advance stall past a threshold).
   - Anchor: contracts/modules/DegenerusGameAdvanceModule.sol:1608-1626 (HEAD), with the resume window at 1611 covering only `[lvl+1, lvl+4]`.
   - Mechanism: the level drained by `_runProcessTicketBatch` at AdvanceModule:526 is the window base itself (`lvl` in jackpot phase, `purchaseLevel` in purchase phase), which is strictly below `startLevel` (1606). So when that batch stops mid-queue (`ticketLevel = base, ticketCursor > 0`) and the advance breaks at STAGE_TICKETS_WORKING, the next advance reaches `_prepareFutureTickets` (AdvanceModule:513) first — `ticketsFullyProcessed` is already latched true, the RNG word is cached, and `dailyJackpotCoinTicketsPending` is still false because the daily jackpot runs only after line 526 finishes. The 1611 resume guard does not match (`resumeLevel = base < startLevel`), so the loop at 1620-1631 probes `lvl+1`: `processFutureTicketBatch` unconditionally executes `ticketCursor = 0; ticketLevel = 0` on the empty-queue path (DegenerusGameMintModule.sol:325-328) or `ticketLevel = lvl; ticketCursor = 0` on the nonempty path (MintModule:331-333). Either way the current-level cursor is erased, and the next `processTicketBatch(base)` call re-enters via `ticketLevel != lvl → ticketCursor = 0` (MintModule:630-632), rescanning from index 0.
   - Inducing input: any jackpot-phase day whose swapped read queue at the current level holds more distinct queued addresses than one write-budget call can materialize. This queue is fed by the carryover ticket distribution, which queues winners at the current level on non-final jackpot days (`isFinalDay ? lvl + 1 : lvl`, DegenerusGameJackpotModule.sol:603-612, up to LOOTBOX_MAX_WINNERS = 100/day) — at ~11 budget units per one-ticket winner against the 358-unit cold budget (550 − 35%, MintModule:93,636-639), any day with more than ~32 such winners spans ≥2 advance calls at line 526 and hits the reset on every subsequent call.
   - Divergence: already-processed entries are re-skipped at 1 budget unit each (`_processOneTicketEntry` returns `(1, 0, true)`, MintModule:825), so per-call net progress shrinks as the processed prefix grows — extra advance transactions in the common case. If a single read-slot queue ever accumulates ≥ ~354 distinct addresses, every call spends its entire budget re-skipping the prefix and returns `worked = true` with zero net progress: `advanceGame` loops STAGE_TICKETS_WORKING forever, `_unlockRng` is never reached, and the day never completes (terminating only via the 120-day liveness game-over). Current per-day feeders cap near 100 entries for that key, so the hard-stall tier rests on calibration (winner caps), not structure. No double-mint in either tier: `owedMap` zeroing (MintModule:865-870) keeps the re-scan value-idempotent, including persisted partial progress on large `owed` entries.

(b) holds only via an outside invariant

1. AdvanceModule:1606-1607 (`lvl + 1`, `lvl + 4`) and the window comparison at 1611 are collision-free against the far-future marker only because game levels stay far below 2^22: `TICKET_FAR_FUTURE_BIT = 1 << 22` (DegenerusGameStorage.sol:182) shares the uint24 space with plain levels, so a `ticketLevel` of `X | FF` reads at 1608 as a large plain level and correctly falls outside the window — but only while `endLevel < 2^22`. Invariant: level progression bound (one level per multi-day jackpot cycle) keeps `level` orders of magnitude below 2^22.
2. The window-shift safety of the resume logic (1611) — an in-flight future level can never be stranded below a new window — holds because every phase/level transition path (STAGE_TRANSITION_DONE, jackpot entry) is reached only after all batch processors returned finished, at which point the mint module has terminally reset `ticketLevel = 0` (MintModule:325-328, 336-340, 462-467). Invariant: base `lvl` passed at AdvanceModule:513 is constant while any future-level batch is in flight.
3. `_prepareFutureTickets` never observes a far-future resume marker (`ticketLevel = ffLevel | FF`): while that marker is set, `phaseTransitionActive` is still true and the advance loop breaks in the transition branch (AdvanceModule:469-506) before reaching line 513. Were prepare reachable in that state, its first empty probe (MintModule:325-328) would clear the marker and orphan the FF queue mid-drain. Invariant: FF marker is set only under `phaseTransitionActive`, and that flag clears only after the FF batch reports finished-without-work.
4. Skipping `target == resumeLevel` in the loop (1621) after the resume call at 1612 returned finished-without-work is sound only because read queues cannot grow mid-day: all queue writers push to the write key (`_queueEntries`/`_queueEntriesScaled` → `_tqWriteKey`, DegenerusGameStorage.sol:682-685, 726-729), and the read/write slots swap only at the daily RNG request. A same-day append to a read queue would make the skip drop queued entries for that day.
5. Decode shapes at 1592 and 1661-1662 are correct only by convention with the mint module: 1592 decodes `(bool, bool, uint32)` matching `returns (bool worked, bool finished, uint32 writesUsed)` (IDegenerusGameModules.sol:302-305), and 1662 deliberately swaps to `(finished, worked)` matching `returns (bool finished, bool didWork)` (IDegenerusGameModules.sol:311-313). Verified consistent at HEAD; the asymmetric return orders between the two sibling functions are the invariant to preserve on any future edit.

(c) cosmetic / telemetry-only

1. AdvanceModule:1591 guards `data.length == 0` before a decode that requires 96 bytes, while the sibling at 1661 guards `data.length < 64` for a 64-byte decode. A 32- or 64-byte return at 1592 would revert inside `abi.decode` with a generic error instead of `EmptyReturn()` — unreachable with the fixed trusted module, and outcome-identical (revert) either way; only the error selector differs.
2. AdvanceModule:1616/1626 — a probed level that both works and finishes in one call still returns false, costing one extra advance call that re-probes the (now empty) window before proceeding. Matches the documented one-batch-per-tx gas discipline (cf. 1644-1647); no state effect.
3. The `writesUsed` return of `_processFutureTicketBatch` is discarded at both in-range call sites (1612, 1622); it is consumed only as telemetry elsewhere.

REVIEW-STATUS: concerns:1

---
## Chunk 19

Based on my review of the HEAD version (lines 301-420 of `contracts/modules/DegenerusGameAdvanceModule.sol`), covering the new-day daily-drain gate, the mid-day-stall promotion, and the afking subscriber STAGE. I traced referenced state through `DegenerusGameStorage.sol`, `GameAfkingModule.sol`, and the `reverseFlip`/`_applyDailyRng` nudge writers.

(a) Definite inconsistencies
- None found in range.

(b) Observations that hold only via an invariant maintained outside this range
- Line 311 `uint48 preIdx = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;` — this is a bare (checked) `- 1` on the lootbox index. It cannot underflow ONLY because of the storage-init invariant: `lootboxRngPacked` is initialized with `lootboxRngIndex = 1` (Storage.sol:1606) and the field is only ever incremented (`_lrAdvanceIndexClearPending`), never decremented, so `_lrRead(LR_INDEX) >= 1` always. If the index were ever 0 this line reverts / wraps. Same reliance applies to the mid-day read at line 248 (just outside range).
- Lines 345-347 `unchecked { cw += totalFlipReversals; }` then line 350 `lootboxRngWordByIndex[preIdx] = cw;` — this pre-stores the daily word into the lootbox bucket WITHOUT zeroing `totalFlipReversals` (unlike `_applyDailyRng`, which applies the same nudge and then sets `totalFlipReversals = 0` at AdvanceModule:2093). Correctness — that the bucket word equals the day's sealed `rngWordByDay[day]` word computed later in `rngGate`/`_applyDailyRng` — holds ONLY because of the VRF-freeze invariant: this branch runs with `cw = rngWordCurrent != 0`, which implies `rngLockedFlag == true`, and `reverseFlip` reverts while `rngLockedFlag` is set (DegenerusGame.sol:1955). Thus `totalFlipReversals` is frozen between the pre-store here and the later `_applyDailyRng`, so both words carry identical nudges and `_finalizeLootboxRng`'s `if (lootboxRngWordByIndex[index] != 0) return;` (line 1379) correctly no-ops. If reversals could accrue while locked, the bucket word and the daily word would diverge.
- Lines 345-347 `unchecked` add: `cw` is a full 256-bit VRF word and `totalFlipReversals` is uint64; the add is deliberately unchecked and can wrap only if `cw` is within 2^64 of 2^256, which does not occur for a real VRF word. Mirrors the intended `_applyDailyRng` behavior; relies on VRF word magnitude, not on in-range logic.
- Lines 330-343 mid-day-stall promotion: `_requestRng(lastPurchase, purchaseLevel)` re-uses the reserved lootbox index without double-incrementing because `_finalizeRngRequest` computes `isRetry` from `vrfRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0` (all true on this `cw == 0`, `rngRequestTime != 0` branch), so `_lrAdvanceIndexClearPending` is skipped and `LR_PENDING_*` accumulators stay attached to the still-pending index. Correct, but depends on `_finalizeRngRequest`'s retry detection outside this range.
- Line 336-338 `_swapAndFreeze()` vs `_freezePool()` selection keys on `ticketQueue[preRk].length == 0`; the resulting read/write-slot consistency depends on `_swapTicketSlot`/`ticketsFullyProcessed` discipline defined outside range.
- Lines 415-422 subscriber-stage completion + backfill-defer: after `subsFullyProcessed = true` and a `STAGE_SUBS_BACKFILL_DEFERRED` break, the set is not re-walked on the next same-day advance because the `_afkingResetDay != day` guard (391) already stamped `_afkingResetDay = day` and only a genuine day change reopens the drain. No double-processing, but this relies on `day` being stable across retries (the RNGREUSE clamp at line 191 and `dailyIdx` only advancing in `_unlockRng`).
- Line 399 `_subCursor < _subscribers.length`: no cast/overflow risk because `_subscribers` is capped at `SUBSCRIBER_CAP = 1000` (GameAfkingModule.sol:199/619) and `_subCursor` is uint16 (max 65535). Bound holds only because of the cap enforced in `_addToSet`, outside this range.

(c) Cosmetic / telemetry-only
- Line 351 `emit LootboxRngApplied(preIdx, cw, vrfRequestId)` — telemetry; uses the current daily `vrfRequestId` (vs `requestId` in `rawFulfillRandomWords`), purely indexer-facing.
- Lines 320-329 and 411-414 are long explanatory comments describing the stall-promotion and backfill-decouple rationale; no state effect.
- Line 332 `ts - rngRequestTime` and the analogous elapsed computations are safe (uint48 monotonic timestamps, `ts >= rngRequestTime`), noted only for completeness.

REVIEW-STATUS: clean

---
## Chunk 20

(a) Definite inconsistencies

None found. Every branch in the four target functions was walked against the reachable state space; each candidate hazard resolved to an invariant maintained elsewhere (bucket b) or a telemetry/design note (bucket c).

(b) Observations that hold only via an outside-range invariant

1. Line 2015 (`rawFulfillRandomWords`, mid-day branch): `uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1` is a checked subtraction that would revert (bricking the callback) if the index counter were 0, and would misattribute the word if the counter moved between request and fulfillment. Holds because (i) `lootboxRngPacked` is initialized with `lootboxRngIndex = 1` (DegenerusGameStorage.sol:1606) and the counter is only ever incremented, and (ii) `LR_INDEX` is advanced solely by `_lrAdvanceIndexClearPending` on a fresh `_finalizeRngRequest` (line 1843), which cannot run while a request is in flight (`rngRequestTime != 0` gates at line 1202 / isRetry at lines 1835-1846; Mint/Whale/Afking modules only read the index and add pending amounts). So counter-1 at fulfillment time is exactly the index the in-flight request reserved.

2. Line 2016 (mid-day branch writes `lootboxRngWordByIndex[index]` unconditionally): write-once on this mapping holds because every competing writer is fenced — the timeout-promotion fill (line 350) and `_finalizeLootboxRng` (line 1379) both check-for-zero first, and any abandoned/rotated mid-day request has its `vrfRequestId` replaced (lines 334, 1366, 1944) so a late duplicate callback fails the line-2004 `requestId != vrfRequestId` guard. A duplicate fulfillment of the same live requestId is excluded only by the coordinator's own once-per-request guarantee (and by `requestId != 0` for real Chainlink IDs).

3. Line 2040 (`_backfillGapDays`): `endDay - startDay` is a checked uint24 subtraction; underflow is excluded because the sole caller (rngGate line 1301-1303) passes `startDay = dailyIdx + 1`, `endDay = day` under the guard `day > dailyIdx + 1`.

4. Lines 2040/2041 (120-day cap): calendar days in `[startDay+120, endDay)` never receive an `rngWordByDay` entry and never get `processCoinflipPayouts`; after this recovery the line-1301 gate (`rngWordByDay[idx+1] == 0`) is permanently false so they are never revisited. This is loss-free only under two outside invariants: coinflip placement is closed while `rngLockedFlag` holds the daily lock (a >1-day stall keeps it set, so no new flips land on deep gap days), and a >120-day stall is the governance-rotation / VRF-deadman regime (`_vrfDeadmanFired`, `updateVrfCoordinatorAndSub`) rather than this path's responsibility.

5. Line 2046 (`rngWordByDay[gapDay] = derivedWord` written unconditionally, payouts re-fired per day): non-double-processing holds only because the caller's `rngWordByDay[idx + 1] == 0` gate (line 1301) runs the backfill at most once per lock window and `dailyIdx` is unchanged until `_unlockRng`.

6. Line 2074 (`_backfillOrphanedLootboxIndices` break-on-first-filled): correctness requires trailing-contiguous orphans — no empty index below a filled one. Holds because only one VRF request is ever in flight (single `vrfRequestId`/`rngRequestTime` slot), the index advances only on fresh requests, and every retry/promotion path (`isRetry`, line 1835; mid-day promotion, lines 329-342; coordinator rotation, lines 1927-1955) preserves the reserved index so each reserved slot is filled before the counter can advance past it. The same invariant bounds the backwards-scan gas (at most a few orphans before a filled index).

7. Line 2101 (`_applyDailyRng` writes `rngWordCurrent = finalWord` as a non-zero "delivered" sentinel): relies on `finalWord != 0`, which is guaranteed by the word==0→1 clamp at line 2007 plus the negligible-probability wrap noted in (c)(3).

(c) Cosmetic / telemetry-only notes

1. Lines 2049/2051: gap days always get `coinflipBonus = 0` and never consume `totalFlipReversals` nudges — both explicitly documented (lines 2024-2026, 2048-2049) as intended: reversal purchases made during a stall carry into the current day's word via `_applyDailyRng` instead.

2. Line 2072 vs line 1353: on a gap-recovery day the daily request's own reserved lootbox index is filled by the orphan backfill with `keccak256(vrfWord, i)` before `_finalizeLootboxRng` would have filled it with the nudged daily word. Both words are VRF-derived and unpredictable pre-request; lootbox EV and accounting are unaffected — only which unpredictable word a bucket binds to differs.

3. Lines 2096-2098: `unchecked { finalWord += nudges; }` can in principle wrap; wrapping to exactly 0 would corrupt the zero-sentinel on `rngWordCurrent`/`rngWordByDay[day]`. Not targetable: `rawWord` is a fresh VRF word unknown when nudges are committed, so hitting `2^256 - rawWord` has probability ~2^-256; `totalFlipReversals` is additionally far below that magnitude in practice.

4. Line 2016/2074-2077: `LootboxRngApplied` is emitted with `requestId` for genuine fulfillments (line 2017) but with `0` for orphan backfills (line 2078) — an intentional telemetry distinction, no state effect.

REVIEW-STATUS: clean
