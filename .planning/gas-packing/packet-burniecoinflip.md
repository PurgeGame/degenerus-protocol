# Packet — BurnieCoinflip (RT-PACKING-08 + RT-PACKING-09)

Own-storage contract. Both items change only the **inner key derivation + value encoding** of a
mapping — the mapping roots stay at their declared slots (coinflipBalance@0, coinflipDayResult@1),
so **no declaration-slot shift** for any variable and **no slot-hardcoded harness** touches these
two mappings (grep-clean; the only `FLIP` slot const in the suite is the *Game* `totalFlipReversals`).
Recalibration is behavioral only (day-lane boundary tests).

## REFINEMENT (user-driven, 2026-06-12) — maximal lane widths
User pushed both lanes tighter than the audit's framing, accepting the trade-offs explicitly:
- **Day-result → 8-bit lanes (32/slot), 3-state.** rewardPercent's real max is 156 (`50 / 150 / [78,115]` + bonus 0/2/6 — comment confirms "max 156"), so it fits uint8. reward(8) + win(1) = 9 bits can't share a byte as separate fields, so encode 3 states in one byte: `0`=unresolved, `1`=resolved-loss, `50..156`=resolved-win@reward. `win` is derived (`byte >= 50`); losing days drop the (functionally unused) reward%. **Audited ALL getCoinflipDayResult consumers** (BafCreditRouting, StallResilience, VRFStallEdgeCases, CoinflipCarryClaim, BurnieEmissionSeeds + redemption mocks): every one reads the `win` bool, checks `reward != 0` (resolution detection — a resolved loss reads back as `1`, still nonzero), or reads reward in a win context. NONE assert the exact reward on a losing day → safe. Resolution detection and the claim loop's `rewardPercent == 0 && !win` skip both still hold.
- **Stake → 128-bit wei lanes (2/slot), LOSSLESS.** The whole-BURNIE truncation experiment (uint32, 8/slot) was REVERTED — the full forge suite caught that flip credits are NOT always large player stakes: keeper advance rewards (~1.77e14 wei = 0.000177 BURNIE) and `redeemBurnieShare` settlement amounts are **sub-1-BURNIE**, so whole-token granularity zeroed them — breaking `testRouterAdvanceRewardMatchesLiveUnitRatio`, `testMintBurnieEligibleKeeperEarnsAdvanceBounty` (keeper incentive → 0) and `testRedeemBurnieNetMintZero` (BURNIE conservation). Lesson: "dust" reasoning was wrong for system credits. A stake is provably ≤ uint128 (BurnieCoin supply cap), so 128-bit wei lanes = max LOSSLESS density (2/slot). No clamp, no revert, no truncation. ⚠ `_setFlipStake` is advance-reachable (`creditFlip`→`_addDailyFlip`), so it must never revert — the lossless wei form has no revert path.

Net density: day-result 1→32/slot, stake 2→8/slot. Helper bodies changed; the 11 call sites are unchanged (they pass/receive wei; helpers convert).

## RT-PACKING-08 — coinflipDayResult (APPROVED, hot) — original framing
`mapping(uint24 => CoinflipDayResult{uint16 rewardPercent; bool win})` → `mapping(uint24 => uint256)`.
Today: one full slot per day, fresh zero→nonzero SSTORE each resolution; one cold SLOAD per scanned day.

**Original encoding (superseded by 8-bit above):** key = `day >> 3`; bits `[0:16]` rewardPercent, `[16]` win. 8 results / slot.

**Sentinel safety (stronger than the finding):** the resolution roll always stores `rewardPercent >= 50`
(branches give 50 / 150 / [78,115]+bonus), so every resolved lane is nonzero and an all-zero 32-bit lane
means *unresolved* — exactly the L470 `rewardPercent==0 && !win` skip check. No ambiguity case exists.

**Helpers (decode/encode the lane):**
- `_dayResult(uint24 day) → (uint16 rewardPercent, bool win)`: read `coinflipDayResultPacked[day>>3]`, shift+mask the lane.
- `_storeDayResult(uint24 day, uint16 rewardPercent, bool win)`: **masked RMW** — read slot, clear the 32-bit lane, OR-in `rewardPercent | (win?1:0)<<16`, SSTORE. (Days in a block resolve on different days/txs → masked RMW mandatory to preserve sibling lanes.)

**Sites:** L353 getCoinflipDayResult view → `_dayResult` (ABI unchanged). L465 claim loop → `_dayResult`. L831 resolution write → `_storeDayResult`. L1048 view scan → `_dayResult`.

**Win:** resolution write ~15,000/day avg (zero→nonzero once per 8 days); claim-loop reads naturally warm for days 2-8 of a block within one tx. Worst-case advance gas does NOT rise (first day of block = same 22,100). Bytecode ~0.

## RT-PACKING-09 — coinflipBalance (PARTIAL → safe leg, hot)
`mapping(uint24 => mapping(address => uint256))` re-keyed by `day >> 1`. Today: fresh zero→nonzero SSTORE
per (day,player) for daily flippers.

**Encoding:** key = `day >> 1`; lane = `day & 1`; laneShift = `lane * 128`; `[0:128]` even day, `[128:256]` odd day.
Width: a single (day,player) stake « uint128.max (BURNIE supply hard-capped at uint128 by `_toUint128`).

**Adjudication (skeptic PARTIAL):** mechanics safe; the skeptic only *corrected the savings down* — auto-rebuy
players ride `carry` in playerState and don't write coinflipBalance daily, so the ~8,500/day write saving is
manual-daily-flippers only; the claim-loop read-halving (~1,000/scanned day, via warm-slot) applies to everyone.
Safe leg = the whole change (no unsafe leg to drop).

**Discipline (the landmine):** the claim loop interleaves external calls (payout/creditFlip/jackpots). Every
stake helper does its **own fresh SLOAD/SSTORE at the logical site — never cache the packed word across an
external call.** Consecutive days share a slot, so each masked write preserves the sibling lane.

**Helpers:**
- `_flipStake(uint24 day, address p) → uint256`: read lane from `coinflipBalance[day>>1][p]`.
- `_setFlipStake(uint24 day, address p, uint256 v)`: **masked RMW** — read slot, clear the 128-bit lane, OR-in `v` (v « uint128.max), SSTORE.

**Sites (all 8):** L193-194 constructor seeds → `_setFlipStake` (masked, so day 2&3 sharing key 1 don't clobber).
L475 read → `_flipStake`. L483 zero → `_setFlipStake(…,0)` (masked half-clear). L619 prevStake read → `_flipStake`;
L623 write → `_setFlipStake` (adjacent, no external call between). L989 view → `_flipStake`. L1057 view scan → `_flipStake`.

**Win:** stake write ~8,500/day (manual flippers); claim read ~1,000/scanned day. Zero-write ~neutral
(forgoes some refund — netted). Bytecode ~0.

## Validation
forge 845/0/110 by name; targeted coinflip suites: `test/unit/BurnieCoinflip.test.js`,
`test/fuzz/CoinflipCarryClaim.t.sol`, `test/fuzz/BurnieEmissionSeeds.t.sol` (constructor seeds across the
`>>1` boundary — days 1/2/3 land correctly), `test/validation/PaperParity.test.js`. New boundary tests:
day 0, `>>3`/`>>1` block edges, gaps (unresolved lane), 30/90/1095-day catch-up claims.

## Safety
No RNG-window interaction (coinflipDayResult written post-resolution only; coinflipBalance is the player's
escrowed BURNIE stake, accounting-sensitive → masked RMW must be bit-exact). No solvency-ETH surface. No
access-control change. getCoinflipDayResult ABI preserved via decode.
