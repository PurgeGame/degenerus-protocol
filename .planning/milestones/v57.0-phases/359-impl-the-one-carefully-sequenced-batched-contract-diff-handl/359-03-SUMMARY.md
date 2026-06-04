---
phase: 359-impl-the-one-carefully-sequenced-batched-contract-diff-handl
plan: 03
subsystem: contracts
tags: [solidity, wwxrp-whalepass, terminal-decimator-boost, afking-cancel, bucket-promotion, freeze-safe, forge-build]

# Dependency graph
requires:
  - phase: 358-spec-design-lock
    provides: "WWXRP-02 D-14..D-18 (per-bracket rationing key level/10, recipient = bettor, s==9-first hook), TDEC-02 D-04..D-13 + TDEC-03 (last-day boost + bucket promotion + conserved aggregate re-key under !_livenessTriggered, the future-day-word freeze re-proof), CANCEL-02 D-30..D-33 (manual-cancel auto-claim self+tree before clear; auto-evict explicit-delete forfeit)"
  - phase: 359-01
    provides: "handlePurchase returns burnieMintReward (present in the features-first build)"
  - phase: 359-02
    provides: "BURNIE-01/02 queue-on-return + creditFlip + SALVAGE-01 combo ETH/BURNIE leg + the in-session 5-tuple preview merge (present in the features-first build)"
provides:
  - "WWXRP-01: first WWXRP Degenerette jackpot (s==9, currency 3, >=1 ether) in each level/10 bracket grants whalePassClaims[player] += 1 to the bettor; rationed by wwxrpJackpotWhalePassBracketAwarded[bracket]; zero added cost on non-jackpot spins (s==9 short-circuits first); no ETH/pool touch"
  - "TDEC-01: boostTerminalDecimator() scales an existing entry's weightedBurn by a streak factor (1x..20x), promotes the bucket if the live activity score qualifies a strictly-lower one (re-derive subBucket + conserved aggregate re-key), gated by require(!_livenessTriggered()) on the deadline day (daysRemaining==0), one-time per level via a boosted bit; router stub on DegenerusGame"
  - "CANCEL-01: manual sub-cancel auto-claims self pendingBurnie (CEI zero-first, presale-box parity) + settles the affiliate tree via IDegenerusAffiliate.claim BEFORE _finalizeAfking+tombstone; both auto-evict paths (pass-expiry, funding-out) now delete _subOf[player] (pure forfeit); the FALSE 'claim whenever' comment fixed"
  - "CHECKPOINT 1: features-first forge build GREEN (all 7 v57.0 behavior features, pre-UDVT, no test-file day-signature churn)"
affects: [359-04 (UDVT sweep + final batched diff + HARD STOP), 360 (GAS), 361 (TST SEC-01 freeze/WWXRP-grant/TDEC bucket-promotion determinism, SEC-02 aggregate-weight conservation + no-ETH-touch, CANCEL-03 loss-race + forfeit), 362 (TERMINAL adversarial bucket-promotion probe + delta-audit)]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "RNG-insensitive deferred grant on a jackpot score (whalePassClaims counter + per-bracket flag), gated by the already-committed s==9 — no ETH/pool, reuses the claimWhalePass future-ticket deferral"
    - "Final-day weight+bucket boost under a day-constant freeze gate: scale weightedBurn, promote bucket if strictly lower, re-derive subBucket, re-key the aggregate (remove-old/add-new) so total weight is conserved"
    - "View-only effective-streak read (getPlayerQuestView.baseStreak) — no mutation, no shield consume"
    - "Manual-cancel auto-claim: pay self (CEI zero-first) + settle the upline tree by reusing IDegenerusAffiliate.claim, BEFORE clearing the slot"
    - "Auto-evict pure forfeit via delete _subOf[player] (mirror the tombstone-reclaim path)"

key-files:
  created: []
  modified:
    - contracts/storage/DegenerusGameStorage.sol
    - contracts/modules/DegenerusGameDegeneretteModule.sol
    - contracts/modules/DegenerusGameDecimatorModule.sol
    - contracts/DegenerusGame.sol
    - contracts/modules/GameAfkingModule.sol
    - contracts/interfaces/IDegenerusGameModules.sol
    - contracts/interfaces/IDegenerusQuests.sol

key-decisions:
  - "WWXRP bracket key reads the storage `level` directly (uint24 public) only on the jackpot path; the s==9 short-circuit means non-jackpot spins add no SLOAD"
  - "TDEC last-day window = daysRemaining == 0 (the deadline day itself, psd+120 / psd+365-idle); still pre-liveness (liveness fires at currentDay - psd > 120, strictly later), so the deadline day satisfies the freeze gate AND the last-day game-design lever"
  - "TDEC boostFactor curve (SPEC D-08 candidate, accepted verbatim): factorBps = 10000 + streak*3000 for streak<=10; 40000 + (streak-10)*1778 for 10<streak<=100; capped 200000 (20x). Streak pre-clamped to 100. Anchors: streak 0 -> 1x, 10 -> 4x, 100 -> 20x"
  - "TDEC re-key uses two unconditional ops (terminalDecBucketBurnTotal[oldKey] -= oldWeighted; [newKey] += newWeighted). On a same-key boost (no promotion) oldKey==newKey so it nets to +(newWeighted-oldWeighted); on a promotion it moves the whole post-boost contribution. Conserved across both cases"
  - "TDEC reads the effective streak via IDegenerusQuests(QUESTS).getPlayerQuestView(player).baseStreak — getPlayerQuestView added to the IDegenerusQuests interface (it existed only on the contract). View-only"
  - "CANCEL affiliate-tree settle reuses IDegenerusAffiliate.claim([subscriber]) rather than re-implementing the 75/20/5 split inline — same recipients/amounts/leaderboard credit/duplicate-drain guard; the AFFILIATE-only drainAffiliateBase callback resolves cleanly (Game calls Affiliate -> Affiliate calls back Game.drainAffiliateBase with msg.sender==AFFILIATE)"
  - "CANCEL auto-evict delete placed after sub.dailyQuantity=0, before _removeFromSet (which reads only _subscriberIndex/_subscribers, not _subOf) — mirrors the GOOD tombstone-reclaim forfeit at :1167"

requirements-completed: [WWXRP-01, TDEC-01, CANCEL-01]

# Metrics
duration: ~20min
completed: 2026-06-04
---

# Phase 359 Plan 03: WWXRP-01 + TDEC-01 + CANCEL-01 + CHECKPOINT 1 Summary

**Added the three clean RNG-insensitive / BURNIE-emission features on top of plans 01-02 + the three in-session revisions: a per-bracket-rationed WWXRP jackpot whale-halfpass grant to the bettor; a final-day `boostTerminalDecimator()` that scales weight and promotes the bucket under a day-constant freeze gate with a conserved aggregate re-key; and a manual-cancel auto-claim (self + upline tree) plus explicit auto-evict forfeit that closes the loss-on-reclaim race. Features-first `forge build` is GREEN (CHECKPOINT 1, pre-UDVT, no test churn). All contracts UNCOMMITTED — held for the plan-04 batched USER hand-review.**

## Performance

- **Duration:** ~20 min
- **Started:** 2026-06-04T13:37:04Z
- **Completed:** 2026-06-04T13:57Z
- **Tasks:** 4 (3 feature tasks + CHECKPOINT 1)
- **Files modified:** 7 contracts (uncommitted) + docs

## Task 1 — WWXRP-01: jackpot whale-halfpass hook + storage append

**Storage append (`contracts/storage/DegenerusGameStorage.sol`):** appended after `lootboxEthBase` (the `whalePassClaims:973` / `lootboxEthBase:977` slot region) — a clean append, no existing slots reordered:
```solidity
mapping(uint256 => bool) internal wwxrpJackpotWhalePassBracketAwarded;  // keyed by level/10
```

**Hook site (`contracts/modules/DegenerusGameDegeneretteModule.sol`):** inserted IMMEDIATELY AFTER the ETH-only `s >= 7` sDGNRS block inside the per-spin loop of `_resolveFullTicketBet` (the block at `:713-715` `if (currency == CURRENCY_ETH && s >= 7) { _awardDegeneretteDgnrs(...); }`). Shape:
```solidity
if (s == 9 && currency == CURRENCY_WWXRP && amountPerTicket >= MIN_BET_WWXRP) {
    uint256 bracket = uint256(level) / 10;
    if (!wwxrpJackpotWhalePassBracketAwarded[bracket]) {
        whalePassClaims[player] += 1;
        wwxrpJackpotWhalePassBracketAwarded[bracket] = true;
        emit WwxrpJackpotWhalePass(player, bracket);
    }
}
```
- The `s == 9` jackpot check short-circuits FIRST (1-in-10M) → non-jackpot spins read no new state and incur zero added cost.
- Full gate: `s == 9 && currency == CURRENCY_WWXRP (3) && amountPerTicket >= MIN_BET_WWXRP (1 ether) && !wwxrpJackpotWhalePassBracketAwarded[level/10]`.
- Credits the BETTOR `player` (the owner from `_resolvePlayer`), NEVER `msg.sender`. Reuses the `claimWhalePass` future-ticket deferral → no ETH / `claimablePool` touch. The bracket key reads the storage `level` (uint24 public) directly, only on the jackpot path.
- A new lean event `WwxrpJackpotWhalePass(address indexed player, uint256 indexed bracket)` was added (declared after `PayoutCapped`). The liveness revert (`:413`) and the router stubs are unchanged.

## Task 2 — TDEC-01: boostTerminalDecimator() + router stub + boosted bit

**Packed struct (`contracts/storage/DegenerusGameStorage.sol`):** added `bool boosted;` to `TerminalDecEntry` (was 232/256 bits, 24 spare → now 240/256, same slot, no new cold slot).

**Entrypoint (`contracts/modules/DegenerusGameDecimatorModule.sol`):** new `boostTerminalDecimator()` authored right after `recordTerminalDecBurn` (the writer analog). Shape:
- **Gate (EXACT):** `if (_livenessTriggered()) revert TerminalDecNotActive();` — the day-constant predicate, NOT `!gameOver`.
- **Last-day window (chosen threshold):** `if (_terminalDecDaysRemaining() != 0) revert TerminalDecNotBoostable();` — admissible only on the deadline day (`daysRemaining == 0`, i.e. `currentDay >= psd + 120` or `psd + 365` idle). This is still pre-liveness (liveness needs `currentDay - psd > 120`, strictly later), so the deadline day satisfies both the freeze gate and the "keep the streak alive to the END" game-design lever.
- **Prerequisites:** an existing entry for the current `level` (`e.burnLevel == uint48(lvl) && e.bucket != 0`, else `TerminalDecNotBoostable`); the `boosted` bit unset (else `TerminalDecAlreadyBoosted`); a live non-zero effective streak; non-zero existing `weightedBurn`. The boost SCALES committed weight — it never buys an entry.
- **Effective streak (VIEW only):** `IDegenerusQuests(ContractAddresses.QUESTS).getPlayerQuestView(player).baseStreak` — the gap/shield-decayed effective streak, no mutation, no shield consume (D-09/D-12). `getPlayerQuestView` was added to the `IDegenerusQuests` interface (it existed only on the contract).
- **Weight scaling:** `newWeighted = (oldWeighted * boostFactorBps) / BPS_DENOMINATOR`, saturated at `type(uint88).max` (mirrors `recordTerminalDecBurn:750-752`). `_terminalDecBoostFactorBps` curve (SPEC D-08 candidate, verbatim): `10000 + streak*3000` for `streak<=10`; `40000 + (streak-10)*1778` for `10<streak<=100`; cap `200000` (20x); streak pre-clamped to 100. Anchors: streak 0 → 1x, 10 → 4x, 100 → 20x.
- **Bucket promotion:** recompute the bucket from the LIVE activity score (`IDegenerusGame(address(this)).playerActivityScore(player)`, capped at `TERMINAL_DEC_ACTIVITY_CAP_BPS`) via `_terminalDecBucket`; PROMOTE only if `liveBucket < oldBucket` (strictly lower = better). On promotion: re-derive `subBucket` via `_decSubbucketFor(player, lvl, liveBucket)` and write the new bucket/subBucket.
- **Aggregate re-key (conserved):** `terminalDecBucketBurnTotal[oldKey] -= oldWeighted; terminalDecBucketBurnTotal[newKey] += newWeighted;` where `oldKey = keccak256(abi.encode(lvl, oldBucket, oldSub))` and `newKey = keccak256(abi.encode(lvl, newBucket, newSub))`. On a same-key boost (no promotion) `oldKey == newKey` so the net is `+(newWeighted - oldWeighted)`; on a promotion the whole post-boost contribution moves. Total weight conserved in both cases.
- **One-time:** `e.boosted = true` set at the end; the promotion + subBucket re-derive + re-key + weight scale are a single atomic in-tx mutation under the gate. A new lean event `TerminalDecBoosted(player, lvl, oldBucket, newBucket, newWeightedBurn)` is emitted. The ETH/BURNIE payout path is byte-untouched (weight-only). Two new errors: `TerminalDecNotBoostable`, `TerminalDecAlreadyBoosted`.

**Router stub (`contracts/DegenerusGame.sol`):** added a `boostTerminalDecimator()` external stub mirroring `recordTerminalDecBurn:1275` — `delegatecall ContractAddresses.GAME_DECIMATOR_MODULE` + `abi.encodeWithSelector(IDegenerusGameDecimatorModule.boostTerminalDecimator.selector)` + `_revertDelegate`. Permissionless; the module reads `msg.sender` as the caller (which is the player, since the Game stub forwards via delegatecall so `address(this)` is the Game and the original `msg.sender` is preserved). The selector was added to `IDegenerusGameDecimatorModule`.

## Task 3 — CANCEL-01: manual-cancel auto-claim (self + tree) + auto-evict forfeit

**File: `contracts/modules/GameAfkingModule.sol`** (+ import `IDegenerusAffiliate`).

**Manual cancel (`if (dailyQuantity == 0)` branch):** the FALSE "claim whenever" comment was replaced with a correct lean comment (the auto-claim closes the advance-driven reclaim race). The auto-claim runs BEFORE `_finalizeAfking` + tombstone, in this order:
1. **Pay self `pendingBurnie` (CEI zero-first, presale-box parity)** — mirrors `claimAfkingBurnie:1568-1583`: `owed = c.pendingBurnie; c.pendingBurnie = 0;` THEN (while `!presaleOver`) `presaleBoxCredit[subscriber] += (owed * 0.0025 ether) / 100` (halved for ticket subs `FLAG_USE_TICKETS`) THEN `coinflip.creditFlip(subscriber, owed * 1 ether)`.
2. **Drain affiliateBase → 75/20/5 tree** — `IDegenerusAffiliate(ContractAddresses.AFFILIATE).claim([subscriber])`. This reuses the exact settle logic: A = the canceller's referrer-upline (the base is owed UPLINE, NOT to the canceller), `u1Share=(sumB-skipU1)*20/100`, `u2Share=(sumB-skipU2)*5/100`, remainder → A; no-referrer ⇒ 50/50 VAULT/DGNRS; the duplicate-drain guard and leaderboard credit come for free. The AFFILIATE-only `drainAffiliateBase` callback resolves cleanly (the Game calls the Affiliate contract → it calls back `Game.drainAffiliateBase` with `msg.sender == AFFILIATE`).
3. **THEN `_finalizeAfking` + `c.dailyQuantity = 0`** (the existing clear/tombstone). Order: claim self + drain-to-tree, THEN finalize + clear.

**Auto-evict pure forfeit:** both auto-evict paths now `delete _subOf[player]` (mirroring the GOOD tombstone-reclaim path at `:1167`), wiping BOTH accumulators so no `pendingBurnie`/`affiliateBase` survives out-of-set:
- **pass-expiry evict** (`_finalizeAfking` / `sub.dailyQuantity = 0` / `_removeFromSet`) — `delete _subOf[player]` added between the tombstone and `_removeFromSet`.
- **funding-out evict** — same shape, same insertion.

`delete _subOf[player]` count went from 1 (the original tombstone-reclaim) to 3 (+ the two evict paths). The auto-evict pays nothing to self or uplines (pure forfeit). The branch reads no `rngWord`; touches no ETH / `claimablePool`. `_removeFromSet` reads only `_subscriberIndex`/`_subscribers` (not `_subOf`), so deleting `_subOf` first is safe.

## Task 4 — CHECKPOINT 1: post-features forge build GREEN

`forge build` (and a clean `forge build --force`) exits **0**: `Compiler run successful with warnings`. The only output is pre-existing lint advisories — 617 `unsafe-typecast`, 13 `divide-before-multiply`, 7 `incorrect-shift` (all pre-existing, out of scope per the scope boundary). **Zero errors.** All artifacts compiled in `forge-out/` (DegenerusGame, DegenerusGameDecimatorModule, DegenerusGameDegeneretteModule, GameAfkingModule, and the test `FarFutureSalvageSwapTest`). No test-file day-signature churn was needed (pre-UDVT). `ContractAddresses.sol` was NOT regenerated (verified clean — forge does not touch it).

**Contract delta vs the frozen subject `1e7a646d`** (`git diff --stat 1e7a646d -- contracts/`) — the full plans-01-03 + in-session-revisions block, NO UDVT/day-type churn yet:
```
 contracts/DegenerusGame.sol                        |  41 +++++--
 contracts/DegenerusQuests.sol                      |  15 +--
 contracts/interfaces/IDegenerusCoin.sol            |  19 ++++
 contracts/interfaces/IDegenerusGameModules.sol     |   3 +
 contracts/interfaces/IDegenerusQuests.sol          |   9 ++
 contracts/modules/DegenerusGameDecimatorModule.sol | 118 +++++++++++++++++++++
 contracts/modules/DegenerusGameDegeneretteModule.sol |  22 ++++
 contracts/modules/DegenerusGameMintModule.sol      |  96 +++++++++++++----
 contracts/modules/DegenerusGameMintStreakUtils.sol |  42 ++++++++
 contracts/modules/DegenerusGameWhaleModule.sol     |   8 +-
 contracts/modules/GameAfkingModule.sol             |  35 +++++-
 contracts/storage/DegenerusGameStorage.sol         |   9 +-
 12 files changed, 370 insertions(+), 47 deletions(-)
```
The two interface files (`IDegenerusGameModules`, `IDegenerusQuests`) are this plan's additions (the `boostTerminalDecimator` selector + the `getPlayerQuestView` declaration). `DegenerusGameMintModule`/`DegenerusGameMintStreakUtils`/`IDegenerusCoin`/`DegenerusGameWhaleModule`/`DegenerusQuests` are the plan-01/02 + in-session hunks, unchanged by this plan.

## In-session revisions confirmed intact (untouched by this plan)

- SALVAGE preview = the merged 5-tuple `previewSellFarFutureTickets` (grep count 2); `previewSellFarFutureSplit` deleted (grep count 0).
- BURNIE-02 awards the MINT_BURNIE quest reward via `coinflip.creditFlip` (`questCompleted && questReward != 0`, grep count 1).
- `DegenerusGameWhaleModule.sol` lazy-pass window (the additive 0-2 / x9 / x0 change) unchanged (6/2 vs `1e7a646d`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added `getPlayerQuestView` to the `IDegenerusQuests` interface**
- **Found during:** Task 2 (TDEC effective-streak read).
- **Issue:** `getPlayerQuestView(address) returns (PlayerQuestView memory)` was declared only on the `DegenerusQuests` contract, not in `IDegenerusQuests`. The DecimatorModule must call it cross-contract via `IDegenerusQuests(ContractAddresses.QUESTS)` — without the interface declaration the call would not compile.
- **Fix:** Added the `getPlayerQuestView` external-view declaration to `contracts/interfaces/IDegenerusQuests.sol` (matching the contract's signature exactly; the `PlayerQuestView` struct already lives in that interface file) and imported `IDegenerusQuests` + `PlayerQuestView` into the DecimatorModule.
- **Files modified:** `contracts/interfaces/IDegenerusQuests.sol`, `contracts/modules/DegenerusGameDecimatorModule.sol`.
- **Verification:** features-first `forge build` GREEN.

**2. [Rule 3 - Blocking] Added the `boostTerminalDecimator` selector to `IDegenerusGameModules.sol`**
- **Found during:** Task 2 (router stub).
- **Issue:** the DegenerusGame router stub uses `IDegenerusGameDecimatorModule.boostTerminalDecimator.selector`, which requires the function to be declared in the interface.
- **Fix:** added `function boostTerminalDecimator() external;` to `interface IDegenerusGameDecimatorModule`.
- **Files modified:** `contracts/interfaces/IDegenerusGameModules.sol`.
- **Verification:** features-first `forge build` GREEN.

Both interface additions are the minimal supporting declarations needed to realize the planned module + stub edits (the plan's `files_modified` listed the 5 implementation files; these two interface files are the wiring). No scope creep beyond the three requirements.

Otherwise: plan executed exactly as written. The `daysRemaining == 0` last-day threshold and the D-08 boostFactor constants were chosen within the explicitly-delegated discretion (SPEC D-04 / D-08).

## Issues Encountered

None.

## NO CONTRACT COMMIT MADE

Per the contract-commit boundary (this plan is `autonomous: false`; project rule: only `contracts/*.sol` commits need USER approval), all 7 contract edits — `DegenerusGameStorage.sol`, `DegenerusGameDegeneretteModule.sol`, `DegenerusGameDecimatorModule.sol`, `DegenerusGame.sol`, `GameAfkingModule.sol`, `IDegenerusGameModules.sol`, `IDegenerusQuests.sol` — are left **UNCOMMITTED** in the working tree, alongside the still-uncommitted plan-01/02 + in-session contract files. They accumulate across plans 01-04 and are committed as ONE batched diff ONLY after explicit USER hand-review at the plan-04 HARD STOP. No `git add -A`/`git add .`/`git add contracts` was run; no `contracts/*.sol` was staged. `git status` confirmed no contract file is staged. The ONLY commit this plan makes is docs-only (this SUMMARY + STATE.md + ROADMAP.md), staged by explicit path.

## Next Phase Readiness

- All 7 v57.0 behavior features are authored against the frozen subject and the features-first build is GREEN. Plan 04 lands the wide `type Day is uint24` UDVT sweep (incl. the WhaleModule day-bearing boon-day code from the in-session revision), the forge `.t.sol` day-signature churn, the post-UDVT `forge build` (CHECKPOINT 2), and the single batched USER hand-review HARD STOP.
- TST 361 deferred proofs: SEC-01 (WWXRP grant determinism / award reads no VRF-state beyond the committed `s==9` / unreachable post-liveness; TDEC bucket-promotion determinism + the future-day-word freeze), SEC-02 (TDEC aggregate-weight conservation + no-ETH-touch), CANCEL-03 (loss-race closed + auto-evict forfeit). TERMINAL 362: the adversarial bucket-promotion probe.

## Self-Check: PASSED

- `contracts/storage/DegenerusGameStorage.sol` — `wwxrpJackpotWhalePassBracketAwarded` mapping appended (grep 1); `boosted` in `TerminalDecEntry` (grep 3).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — `wwxrpJackpotWhalePassBracketAwarded` (grep 2), `whalePassClaims[player] += 1` (grep 1).
- `contracts/modules/DegenerusGameDecimatorModule.sol` — `boostTerminalDecimator` (grep 1), `_livenessTriggered()` gate (grep 2).
- `contracts/DegenerusGame.sol` — `boostTerminalDecimator` router stub (grep 2).
- `contracts/modules/GameAfkingModule.sol` — `delete _subOf[player]` count = 3 (tombstone-reclaim + 2 evict paths); `IDegenerusAffiliate(ContractAddresses.AFFILIATE).claim` present.
- `forge build` exits 0 (GREEN), zero errors, all artifacts in `forge-out/`; `ContractAddresses.sol` untouched.
- `git status` shows the 12 contract files modified + 1 forge fixture, all UNCOMMITTED; no `contracts/*.sol` staged.

---
*Phase: 359-impl-the-one-carefully-sequenced-batched-contract-diff-handl*
*Completed: 2026-06-04*
