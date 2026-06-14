# 388-02 — Consolidated Finding-Candidate Intake Ledger (FND-04, part 2)

**Subject (byte-frozen):** `a8b702a7` (`git diff a8b702a7 -- contracts/` empty throughout).
**Source:** the seven read-only `.planning/v63-surface-map/*.md` dimension maps (8-agent FOUNDATION
sweep, 0 HIGH on inspection) + the `AUDIT-V63-PLAN.md` §6 9-row cross-map summary.
**Purpose:** every lead from every map becomes ONE tracked row routed to its OWNING sweep phase
(389-394) so no lead is lost between FOUNDATION and the sweeps. INTAKE ONLY — no lead is adjudicated,
refuted, or fixed here. Severity hints carry the map's own hint; MED leads are the prime sweep targets.

**Routing key (REQUIREMENTS.md Traceability):**
`389 PACKING-IDENTITY` = STORAGE + GASID · `390 SOLVENCY-SPINE` = SOLV · `391 RNG-SPINE` = RNG ·
`392 ENTROPY-AND-ECON` = ECON + BURNIE · `393 PERMISSIONLESS-COMPOSITION` = ACCESS ·
`394 LEGACY-DEBT` = v50/v51/v52.

**Design-intent anchor (§5 / PAPER-REWARD-CHANGES-BRIEF):** leads about *documented* EV changes
(EV-multiplier lift floor 90% / ceiling 145% / score-to-ceiling 40,000; recycle-bonus ≥3-ticket gate;
EV-neutral redistributions) are tagged **VERIFY-claim** — the sweep VERIFIES the stated invariant in
code, it does NOT re-litigate the documented intent. Standing by-design rulings
([[intended-game-mechanics-not-findings]], [[degenerette-wwxrp-rtp-by-design]],
[[lootbox-resolution-timing-by-design]]) apply.

---

## A. Storage-packing map → 389 PACKING-IDENTITY (FA-1..FA-4)

| ID | Src (map / id) | Restatement | Sev | Source location | Phase |
|----|----------------|-------------|-----|-----------------|-------|
| FC-389-01 | storage-packing FA-1 | `lootboxEvCapPacked` two-window eviction: if a resolve cursor lags >1 level behind a deposit (deferred/queued resolve, far-future ticket path), a third distinct level key could be live and eviction silently zeroes a live window → the 10 ETH per-level EV cap could be re-earned. Confirm the resolve cursor cannot lag >1 level. **(§6 lead: EV-cap two-window eviction)** | LOW (MED-attention per §6) | storage-packing.md FA-1; DegenerusGameStorage.sol:1698-1707 | 389 |
| FC-389-02 | storage-packing FA-2 | `_pendingRedemptionEthValue=uint96(...)` / `poolBalances[toIdx]=uint128(...)` narrowing casts do NOT revert on overflow — silently truncate. Safety rests on the economic bound (real-ETH<uint96; pool conservation<uint128). Confirm no path inflates segregated ETH / a pool beyond width (truncation would understate segregated ETH → solvency-accounting drift). | INFO | storage-packing.md FA-2; StakedDegenerusStonk.sol | 389 (cross-ref 390) |
| FC-389-03 | storage-packing FA-3 | `DecClaimRound.totalBurn` storage comment says "sum of effective amounts (≤2.35x)" but the accumulator stores RAW burns (`delta=e.burn`). Bound still holds; comment-only mismatch — flag so the sweep doesn't re-derive a non-existent overflow and so a future reader doesn't trust the wrong framing. | INFO | storage-packing.md FA-3; DecimatorModule | 389 |
| FC-389-04 | storage-packing FA-4 | Test-harness slot recalibration: Game tail shifted ~4 slots, sDGNRS −3, Coinflip/Admin shifted; any `vm.store`/`vm.load` hardcoding pre-shift slots silently reads/writes the WRONG field at runtime (compile green) — regression-oracle integrity risk. Confirm the regression baseline was recalibrated vs `forge inspect`. **(388-01 FND-02 + 388-02 ORACLE-HOLES found 1 such HOLE: legacy RedemptionInvariants slots 10/13/15.)** | LOW | storage-packing.md FA-4; (test harnesses) | 389 |

## B. Gas-identity map → 389 PACKING-IDENTITY (F-1..F-5)

| ID | Src (map / id) | Restatement | Sev | Source location | Phase |
|----|----------------|-------------|-----|-----------------|-------|
| FC-389-05 | gas-identity F-1 | `DecClaimRound.rngWord` uint32 narrowing — 32 bits of post-fulfillment entropy seed the claim-time lootbox draw via `hash2(rngWord, uint160(player))`. Predictability without control (player+word frozen, permissionless deterministic claim). Defensible by-design but worth a grinding/retry-timing check. **(Distribution-bias half routed to 391 as FC-391-04; this row = the gas-identity narrowing-equivalence half.)** | INFO/LOW | gas-identity.md F-1; DegenerusGameStorage.sol:1772 + DecimatorModule:277/410 | 389 |
| FC-389-06 | gas-identity F-2 | `lootboxEvCapPacked` level-0 stamp collision — a window whose level stamp is its initial 0 reads as level-0 `used`, diverging from the baseline nested map (returned 0 for unwritten [player][0]). Reachable only if `level==0` is passed (callers pass gameLevel+1≥1, or a uint24 `level+1` wrap). Verify no caller path reaches level 0. | LOW | gas-identity.md F-2; DegenerusGameStorage.sol:1698-1707 | 389 |
| FC-389-07 | gas-identity F-3 | `_addLevelDgnrsClaimed` unclamped high-half — `newClaimed<<128` has no uint128 clamp; relies on caller invariant `claimed≤allocation≤2^128`. Confirm every claim path enforces `claimed+add≤allocation`. | LOW | gas-identity.md F-3; DegenerusGameStorage.sol:1160 | 389 |
| FC-389-08 | gas-identity F-4 | StakedStonk `pendingRedemptionEthValue` uint96 + `totalSupply` uint128 narrowings — bounds make overflow unreachable but worth a solvency-sweep confirmation that no path exceeds 2^96 wei segregated. **(Same surface as FC-389-02; cross-ref 390.)** | LOW/INFO | gas-identity.md F-4; StakedDegenerusStonk.sol | 389 (cross-ref 390) |
| FC-389-09 | gas-identity F-5 | Dynamic-array `msg.data` wrappers (`previewSellFarFutureTickets`, `claimAfkingBurnie`, `rawFulfillRandomWords`) forward raw calldata with non-canonical ABI offsets; benign (module shares the wrapper's decoder + wrapper validates on entry) but a fuzz of malformed/oversized calldata confirms no decoder-divergence corner. | INFO | gas-identity.md F-5; DegenerusGame.sol | 389 |

> Gas-identity §1-§9 VERIFIED-IDENTICAL claims (PriceLookup nibble table, JackpotBucketLib `unchecked`,
> BitPackingLib dead-const removal, the 30 `delegatecall(msg.data)` selectors, hash1/hash2 preimages,
> trait-roll consolidation, `_farFutureSeed` extraction, Stage-B packs) are the GASID-01..05 re-verify
> targets at 389 — they are positive claims to re-confirm, not finding-candidates, so they are NOT
> ledgered as rows here (they map to GASID-01..05 directly in REQUIREMENTS).

## C. Solvency map → 390 SOLVENCY-SPINE (CF-1..CF-7)

| ID | Src (map / id) | Restatement | Sev | Source location | Phase |
|----|----------------|-------------|-----|-----------------|-------|
| FC-390-01 | solvency CF-1 | `claimRedemption`/`Many` live-claim has NO explicit liveness-window gate; `gameOver()` read once as a snapshot. Between `livenessTriggered()` firing and `gameOver()` latching, a resolved redemption can settle via the live path while `handleGameOverDrain` snapshots `totalFunds`/reserves `claimablePool` — concrete multi-tx ordering check for strand/double-credit. **(§6 lead: redemption CLAIM path has no liveness gate)** | MED | solvency.md CF-1; StakedDegenerusStonk.sol:771-801, DegenerusGameGameOverModule.sol:73-182 | 390 |
| FC-390-02 | solvency CF-2 | Dust-forfeit credits sDGNRS's OWN game claimable via `creditRedemptionDirect{value}(address(this), forfeitEth)`. In the stETH-leg submit case no claimable was debited at submit — confirm the forfeit credit is always backed by value actually leaving sDGNRS (msg.value + stETH-pull), never a phantom claimable bump; verify the stETH `transferFrom` always covers the remainder. **(§6 lead: dust-forfeit self-credit)** | MED | solvency.md CF-2; StakedDegenerusStonk.sol:893-901, DegenerusGameLootboxModule.sol:1004-1015 | 390 |
| FC-390-03 | solvency CF-3 | Permissionless decimator/redemption claim + post-gameOver/freeze edge: a third party can trigger a victim's claim during a live game. Verify `gameOver`/`prizePoolFrozen` can't flip mid-batch and split a batch across the boundary inconsistently (batch caches `over`/`frozen` once); no path resolves a claim into claimable that is then forfeited. | MED | solvency.md CF-3; DegenerusGameDecimatorModule.sol:283-380 | 390 (cross-ref 393) |
| FC-390-04 | solvency CF-4 | `burnEth` claim-trigger simplification (`claimValue > combined`, dropped `&& claimable != 0`). Verify the edge `amount==supplyBefore` (last DGVE burn → REFILL_SUPPLY mint) can't let `claimValue` slightly exceed `combined` with `claimable==0` (sentinel-only) → a wasted `claimWinnings(vault)` for a 0-net amount. | LOW | solvency.md CF-4; DegenerusVault.sol:751-770 | 390 |
| FC-390-05 | solvency CF-5 | `gameDegeneretteBet` overpay guard relocated game-side — map VERIFIED equivalent (`_collectBetFunds:596 if (ethPaid>totalBet) revert`, identical formula). Recorded for completeness; re-confirm the guard at sweep. | INFO (verified) | solvency.md CF-5; DegenerusVault.sol:577-589, DegenerusGameDegeneretteModule.sol:587-618 | 390 |
| FC-390-06 | solvency CF-6 | Keeper-bounty `creditFlip` issuance (redemption + decimator batches) — BURNIE off the ETH/stETH spine, but BURNIE is redeemable against sDGNRS/vault backing downstream; confirm issuance is bounded (one box/wallet/day redemption; one decimator entry per real burn) so a keeper can't mint unbounded BURNIE claim-value that dilutes ETH backing. **(coupled to ACCESS-02; cross-ref 393.)** | LOW/INFO | solvency.md CF-6; StakedDegenerusStonk.sol:803-814, DegenerusGameDecimatorModule.sol:357-380 | 390 (cross-ref 393) |
| FC-390-07 | solvency CF-7 | Vault `deposit()` removal completeness — confirm no remaining game-side code attempts `vault.deposit(...)` (dead/reverting call) and that BURNIE mint-allowance accounting (now live via `vaultMintAllowance()`, not the dropped `coinTracked`) cannot over-mint (`burnCoin`'s over-mint claimed to revert inside `vaultMintTo` against the live allowance). | INFO | solvency.md CF-7; DegenerusVault.sol:680-760 | 390 |

## D. RNG-freeze map → 391 RNG-SPINE (top leads §2/§3/§4/§6/§7b)

| ID | Src (map / lead) | Restatement | Sev | Source location | Phase |
|----|------------------|-------------|-----|-----------------|-------|
| FC-391-01 | rng-freeze §2 (Top-lead 2) | `resolveLootboxDirect` seed dropped `amount` (now `hash2(rngWord, uint160(player))`; manual open still includes `amount`). Caller-side domain separation now load-bearing. Confirm no caller path feeds two same-word/same-player resolutions that would collide (the `amount` term used to disambiguate). | LOW-MED | rng-freeze.md §2; DegenerusGameLootboxModule.sol:872 | 391 |
| FC-391-02 | rng-freeze §3 (Top-lead 3) | Box-spin replay/one-shot: box-spins (WWXRP 15% / BURNIE 10% / ETH 5%) are a NEW consumer off the permissionless lootbox-open / bet-resolution surface. Confirm the record-clear (lootbox record zeroed / bet `delete`d) + the `address(this)!=GAME` module guard fully prevent observing a spin outcome and re-triggering with a now-known word. | INFO-LOW | rng-freeze.md §3; DegenerusGameDegeneretteModule.sol ~1290-1430 | 391 |
| FC-391-03 | rng-freeze §4 (Top-lead 4) | Survival-flip cross-bet accumulator: every BURNIE bet payout double-or-nothings on `hash2(rngWord, betId)&1`; `acc.burnieMint -=` nets to zero per bet but `acc` is shared across the batch — confirm cross-bet accumulator ordering can't transiently underflow the unsigned running total. | LOW | rng-freeze.md §4; DegenerusGameDegeneretteModule.sol:772-780 | 391 |
| FC-391-04 | rng-freeze §7b (Top-lead 1) | **Decimator 32-bit claim-word narrowing** — `DecClaimRound.rngWord` uint256→uint32; freeze-safe (fixed at resolution, address-mixed) but a genuine entropy reduction. Confirm the reduced VRF entropy can't BIAS the per-bucket lootbox reward distribution across many winners of one level (the missing-distribution-property the ORACLE-HOLES audit flagged; RNG-02). **(§6 lead: DecClaimRound.rngWord uint32 narrowing)** | MED | rng-freeze.md §7b; DegenerusGameDecimatorModule.sol:277/410 | 391 |
| FC-391-05 | rng-freeze §6 (Top-lead 5) | Redemption day-boundary: confirm `GameTimeLib.currentDayIndex()` can't diverge from the game's `dailyIdx` at a day boundary so a burn stamps a day whose `day+1` word is already on-chain (the `BurnsBlockedBeforeDailyRng` gate pins a drawn day by construction; concrete boundary test). | LOW | rng-freeze.md §6; StakedDegenerusStonk.sol:991 + GameTimeLib | 391 |

## E. Reward-economics map → 392 ENTROPY-AND-ECON (FA-1..FA-15)

| ID | Src (map / id) | Restatement | Sev | Source location | Phase |
|----|----------------|-------------|-----|-----------------|-------|
| FC-392-01 | reward-econ FA-1 | Level-quest +1 streak is NOT gated by the daily primary off-run — a player can bump streak via a level quest on a no-primary day; decay anchor (primary) not updated, so at decay risk next day but locked into `state.streak` immediately. Confirm decay zeroes it when the primary is then skipped. | LOW | reward-economics.md FA-1; DegenerusQuests.sol:2063-2068 | 392 |
| FC-392-02 | reward-econ FA-2 | Afking-secondary double-channel: while afking both `recordAfkingSecondary` and the funded delivered day count toward streak. Confirm toggling afking on/off across a day boundary can't harvest both the funded-day streak AND a manual +1 for the same primary. | LOW/INFO | reward-economics.md FA-2; _questCompleteWithPair | 392 |
| FC-392-03 | reward-econ FA-3 | Faster decimator-max ramp (20x boost in ~33 active days vs ~100) — intended rebalance of terminal-jackpot weight toward fast-ramping players. **VERIFY-claim** the documented intent matches. | INFO | reward-economics.md FA-3 | 392 |
| FC-392-04 | reward-econ FA-4 | Stale EV-band comments (`8000-13500`) after the band moved to 9000-14500. Comment-only stale economic spec. | LOW | reward-economics.md FA-4; LootboxModule.sol:472-473 | 392 |
| FC-392-05 | reward-econ FA-5 | EV-multiplier benefit-cap interaction with the wider band (max EV 145%): the per-level 10 ETH benefit cap is reached on a smaller staked notional. Confirm the `usedBenefit` per (player,level) cap can't be reset within a level to re-earn the uplift across redemption + direct-open + Degenerette-recirc paths that all funnel into `_applyEvMultiplierWithCap`. **VERIFY-claim** (EV-multiplier lift is documented). | INFO | reward-economics.md FA-5; _applyEvMultiplierWithCap | 392 |
| FC-392-06 | reward-econ FA-6 | Repeatable recycle kicker on partial spends (all-claimable gate removed): a whale can earn the 10% kicker on EVERY ≥3-ticket recycle while retaining balance. Confirm BURNIE flip-credit illiquidity + flip-survival keeps it EV-neutral-or-negative; confirm no positive loop when it stacks with the presale 25% box-credit on the same recycled spend. **VERIFY-claim** (recycle-bonus relaxation is documented). | LOW | reward-economics.md FA-6; MintModule.sol:1740-1744, 1726 | 392 |
| FC-392-07 | reward-econ FA-7 | **Box WWXRP-spin (15% of opens, S==9) lowers the cost to farm a whale halfpass** — a NEW acquisition channel vs only deliberate WWXRP bets. Supply still capped per-bracket. Quantify P(S==9) × boxes-per-pass and confirm the cost still exceeds the by-design "near-unfarmable" bar (re-confirm, not auto-dismiss — the acquisition channel changed; ECON-05). **(§6 lead: box WWXRP-spin = new whale-half-pass channel)** | MED | reward-economics.md FA-7; DegeneretteModule.sol:1323-1330 | 392 |
| FC-392-08 | reward-econ FA-8 | **Redemption ETH-spin pool RMW + recirc vs solvency CEI** — the redemption path (`allowEthSpin=true`) reaches the ETH-spin whose `_distributePayout` does a live ETH-pool RMW + recirc box INSIDE the redemption claim (the V62-03/council CEI surface). Trace whether the ETH-spin pool writes + dust-forfeit + `pendingRedemptionEthValue` release reconcile exactly and whether the recirc box's `_applyEvMultiplierWithCap` cap RMW can be raced across chunks. **(§6 lead: box ETH-spin reaches a live ETH-pool RMW + recirc in the claim path → SOLV/ACCESS; cross-ref 390/393.)** | MED | reward-economics.md FA-8; DegeneretteModule.sol ~1400, _resolveRedemptionChunk | 392 (cross-ref 390/393) |
| FC-392-09 | reward-econ FA-9 | ETH-spin stake = ticket budget "EV-equal" claim, but the ETH-spin runs through the >100%-RTP Degenerette payout + recirc → realized EV of the 5% slice plausibly > the tickets it replaced. Confirm the aggregate box EV uplift (this + §2 band widening + WWXRP/BURNIE conversions) is intended and the 10 ETH benefit cap still bounds it. **VERIFY-claim** (EV-neutral redistribution + documented band lift). | LOW | reward-economics.md FA-9; resolveEthSpinFromBox | 392 |
| FC-392-10 | reward-econ FA-10 | `BoxSpin` betId sentinel collision: `BOX_BETID_SENTINEL=1<<63`; confirm a real bet nonce can never reach bit 63 over the game lifetime (event-decode correctness depends on it). | INFO | reward-economics.md FA-10 | 392 |
| FC-392-11 | reward-econ FA-11 | **sDGNRS perpetual 0-take-profit auto-rebuy backing dynamics** — backing rolls win-after-win until a loss zeroes the pending stake. Model whether a loss sequence (or one large-carry loss) drops sDGNRS backing below outstanding redemption obligations, and whether `claimCoinflipCarry` interacts with the sDGNRS settle to let a redeemer extract mid-roll. Carry is RNG-lock-gated — verify the lock fully covers the roll application. **(§6 lead: stochastic sDGNRS auto-rebuy backing → ECON/RNG; cross-ref 391.)** | MED | reward-economics.md FA-11; BurnieCoinflip.sol | 392 (cross-ref 391) |
| FC-392-12 | reward-econ FA-12 | Seed-stake leaderboard/bounty exclusion — seeds are direct `coinflipBalance` writes to stay off the leaderboard/bounty/biggest-flip. Confirm no path reads `coinflipBalance[d][VAULT\|SDGNRS]` for days 1-20 into a leaderboard/bounty/BAF/biggestFlipEver computation that mis-credits the protocol addresses. | LOW | reward-economics.md FA-12 | 392 |
| FC-392-13 | reward-econ FA-13 | `claimCoinflipCarry` settle ordering — settles resolved days (wins→carry, pending loss→zero) BEFORE withdrawing from the carry. Confirm the take-profit chunks the settle banks into `claimableStored` + the carry withdrawal can't double-count a single win across the two channels. | INFO | reward-economics.md FA-13; BurnieCoinflip.sol:782 | 392 |
| FC-392-14 | reward-econ FA-14 | VAULT-terminating referral chains + winner-takes-all — confirm a self-referral / circular-code attempt can't route the upline1/upline2 (20/5%) slices back to the sender, and that the no-referrer 50/50 VAULT/DGNRS path can't be steered by choosing a code that flips `noReferrer` to capture the affiliate 75% slice for an attacker-controlled address. | LOW | reward-economics.md FA-14; DegenerusAffiliate.sol | 392 |
| FC-392-15 | reward-econ FA-15 | Carried affiliate-score asymmetry (the v62 finding-candidate routed forward) — re-examine against the now-GAME-only `payAffiliate` access + the `affiliateBonusPointsBest` 25-ether early-break to confirm the asymmetry didn't change. | INFO | reward-economics.md FA-15; DegenerusAffiliate.sol:725-726 | 392 |

## F. Coinflip-BURNIE map → 392 ENTROPY-AND-ECON (FA-1..FA-5)

| ID | Src (map / id) | Restatement | Sev | Source location | Phase |
|----|----------------|-------------|-----|-----------------|-------|
| FC-392-16 | coinflip-burnie FA-1 | **sDGNRS post-seed carry is stranded from redemption backing** — `previewClaimCoinflips`/`redeemBurnieShare` consume waterfall never read `autoRebuyCarry`, yet post-day-20 ALL sDGNRS BURNIE accrual lands in the carry → redeemers progressively under-credited and the carry has no liquidation path (nothing calls `claimCoinflipCarry(sDGNRS,…)`). Confirm vs design intent (under-credit/strand, NOT insolvency; BURNIE rated "worthless except the whale pass"). **(§6 lead #1: auto-rebuy carry excluded from sDGNRS redemption backing → BURNIE-04.)** | MED | coinflip-burnie.md FA-1; StakedDegenerusStonk.sol:1029-1031, BurnieCoinflip.sol:940-975 | 392 |
| FC-392-17 | coinflip-burnie FA-2 | **VAULT seed stakes (days 1-20) can age out of the 30-day claim window** — only sDGNRS is auto-claimed; the VAULT must claim via `coinClaimCoinflips`. If the VAULT doesn't claim until `flipsClaimableDay≥51`, `minClaimableDay=21>20` and every VAULT seed day is silently skipped → the VAULT's ~half-of-4M expected seed emission never mints. Confirm the VAULT is expected to claim within 30 days or be on auto-rebuy at deploy. **(§6 lead #2: VAULT seed window-aging → BURNIE-05; "most likely to need a contract change".)** | MED | coinflip-burnie.md FA-2; DegenerusVault.sol:630-647, BurnieCoinflip.sol:420-457 | 392 |
| FC-392-18 | coinflip-burnie FA-3 | `setCoinflipAutoRebuy` fromGame branch skips operator-approval for a non-zero player (GAME caller uses the player verbatim). No in-protocol GAME module calls it (grep clean) → presently unreachable + matches baseline (not a regression). Latent permissive branch in case a future delegatecall path reaches it. | LOW | coinflip-burnie.md FA-3; BurnieCoinflip.sol:662-668 | 392 |
| FC-392-19 | coinflip-burnie FA-4 | Survival-flip seed reuses the box seed hash on the bet path (both `hash2(rngWord, betId)`). For BURNIE bets `betLootboxShare==0` so no box opens (no observable correlation); shared derivation worth a glance that no path mixes a BURNIE survival outcome with a box draw a player could bias via their own sequential `betId`s. Defence-in-depth. | LOW | coinflip-burnie.md FA-4; DegeneretteModule.sol:773/791 | 392 |
| FC-392-20 | coinflip-burnie FA-5 | Claim-window widening to 365 (+ 1460 auto-rebuy-off) raises the per-claim resolution-walk iteration ceiling; deep path `uint32` (safe), shallow `uint16` (safe for 365); per-call + caller-paid, not in the advanceGame chain. Confirm no realistic actor can force a many-hundred-day cold-SLOAD walk into a gas-sensitive caller (fresh gas check under the new packed storage). **(echoes permissionless-access §4 gas lead — see FC-393-04.)** | INFO | coinflip-burnie.md FA-5; BurnieCoinflip.sol:420-457 | 392 (cross-ref 393) |

## G. Permissionless-access map → 393 PERMISSIONLESS-COMPOSITION (forced-timing + residuals + claim-loop gas)

| ID | Src (map / lead) | Restatement | Sev | Source location | Phase |
|----|------------------|-------------|-----|-----------------|-------|
| FC-393-01 | permissionless-access §1 (Residual lead: timing forced on the winner) | A third party can now FORCE a winner's live-game decimator claim to resolve at a `level` the winner didn't choose — `_rollTargetLevel(level+1, frozenSeed)` and the whale-pass `_queueTicketRange(winner, level+1,…)` read the LIVE `level` at claim time. Frozen seed prevents win/loss steering, but the LEVEL the reward lands at is externally forceable. Memory rules this by-design; **VERIFY the magnitude** — does any reward magnitude / target-level distribution diverge enough between adjacent levels to make forced resolution materially harmful (ACCESS-03). | LOW | permissionless-access.md §1; DegenerusGameDecimatorModule.sol:283-322 | 393 |
| FC-393-02 | permissionless-access §2 residual (a) | Forfeit-to-self leg: dust lootbox forfeits to sDGNRS's own claimable. A keeper choosing WHICH redemptions to settle could bias when forfeits land vs full lootboxes resolve, but the per-claim split is deterministic from the fixed roll + the player's owed value → no per-victim value extraction, only benign timing of backing accrual. Confirm. | INFO | permissionless-access.md §2(a); StakedDegenerusStonk.sol:839-848,897-901 | 393 (cross-ref 390 FC-390-02) |
| FC-393-03 | permissionless-access §2 residual (b) | **Partial-balance redemption-leg solvency** — each leg sends `min(address(this).balance, legAmount)` ETH and pulls the rest as stETH; the MAX (175%) reservation is claimed to guarantee ETH+stETH≥rolled. Confirm under an adversarial sequence of many partial-balance live claims in ONE block that segregation accounting (`_pendingRedemptionEthValue` release == total leg movement) never strands ETH or under-pulls stETH (ACCESS-04). | LOW | permissionless-access.md §2(b); StakedDegenerusStonk.sol redemption legs | 393 (cross-ref 390) |
| FC-393-04 | permissionless-access §4 (claim-loop gas) | Widened coinflip claim loops (365/1460) over the new packed storage — claims user-paid + out of the advanceGame chain; the advanceGame-chain sDGNRS auto-settle walks ~1 day/advance (bounded). Fresh gas pass on the 365/1460 worst-case loops under the new masked sub-word reads. **(same surface as FC-392-20.)** | INFO | permissionless-access.md §4; BurnieCoinflip.sol | 393 (cross-ref 392) |

---

## §6 cross-map summary — all 9 rows present + same-phase routed

| AUDIT-V63-PLAN §6 lead | §6 phase | Ledger row(s) | Same phase? |
|------------------------|----------|---------------|-------------|
| Auto-rebuy carry excluded from sDGNRS redemption backing | 392 | FC-392-16 | ✓ 392 |
| VAULT seed-stakes age out of 30-day window | 392 | FC-392-17 | ✓ 392 |
| Redemption CLAIM path has no liveness-window gate | 390 | FC-390-01 | ✓ 390 |
| Dust-forfeit self-credit via `creditRedemptionDirect` | 390 | FC-390-02 | ✓ 390 |
| Stochastic sDGNRS auto-rebuy backing (loss zeroes pending) | 392/391 | FC-392-11 (cross-ref 391) | ✓ 392/391 |
| Two-window `lootboxEvCapPacked` eviction under cursor lag | 389 | FC-389-01 | ✓ 389 |
| `DecClaimRound.rngWord` uint32 narrowing | 391 | FC-391-04 (+ FC-389-05 gas-half) | ✓ 391 |
| Box WWXRP-spin = new whale-half-pass channel | 392 | FC-392-07 | ✓ 392 |
| Box ETH-spin → live ETH-pool RMW + recirc in claim path | 390/393 | FC-392-08 (cross-ref 390/393) | ✓ 390/393 |

All nine §6 leads are present and routed to the phase §6 assigns. Named-by-name as required: the two
top BURNIE leads (auto-rebuy carry backing **FC-392-16 → 392**; VAULT seed window-aging
**FC-392-17 → 392**); the EV-cap two-window eviction (**FC-389-01 → 389**); the decimator-uint32
distribution lead (**FC-391-04 → 391**).

---

## Per-phase rollup (intake size each sweep planner inherits)

| Phase | Sweep | Owned candidate rows | Count | MED prime targets |
|-------|-------|----------------------|-------|-------------------|
| 389 PACKING-IDENTITY | STORAGE + GASID | FC-389-01..09 | **9** | FC-389-01 (EV-cap eviction) |
| 390 SOLVENCY-SPINE | SOLV | FC-390-01..07 | **7** | FC-390-01, -02, -03 |
| 391 RNG-SPINE | RNG | FC-391-01..05 | **5** | FC-391-04 (decimator uint32 distribution) |
| 392 ENTROPY-AND-ECON | ECON + BURNIE | FC-392-01..20 | **20** | FC-392-07, -08, -11, -16, -17 |
| 393 PERMISSIONLESS-COMPOSITION | ACCESS | FC-393-01..04 | **4** | FC-393-03 (partial-balance same-block) |
| 394 LEGACY-DEBT | v50/v51/v52 | — (no surface-map leads; charge = LEGACY-01..06 per REQUIREMENTS) | **0** | — |
| **Total intaken** | | | **45** | 11 MED |

> 394 LEGACY-DEBT receives no rows from the seven post-v62 surface-maps (it sweeps the cumulative
> v50/v51 surface + authors `FINDINGS-v50.0.md`/`FINDINGS-v51.0.md` per its own charge spec in
> STATE.md / REQUIREMENTS LEGACY-01..06) — recorded here so its planner knows its surface-map intake
> is zero by design, not by omission.

## Exhaustiveness cross-check (no lead dropped)

| Map | Candidate-focus rows in map | Intaken | Status |
|-----|-----------------------------|---------|--------|
| storage-packing.md | FA-1, FA-2, FA-3, FA-4 | FC-389-01..04 | ✓ 4/4 |
| gas-identity.md | F-1, F-2, F-3, F-4, F-5 | FC-389-05..09 | ✓ 5/5 |
| solvency.md | CF-1, CF-2, CF-3, CF-4, CF-5, CF-6, CF-7 | FC-390-01..07 | ✓ 7/7 |
| rng-freeze.md | Top leads §2, §3, §4, §6, §7b (5) | FC-391-01..05 | ✓ 5/5 |
| reward-economics.md | FA-1..FA-15 | FC-392-01..15 | ✓ 15/15 |
| coinflip-burnie.md | FA-1..FA-5 | FC-392-16..20 | ✓ 5/5 |
| permissionless-access.md | §1 forced-timing, §2(a), §2(b), §4 claim-loop gas (4) | FC-393-01..04 | ✓ 4/4 |
| **Total** | **45** | **45** | **✓ exhaustive** |

`git status --porcelain contracts/` empty; `git diff a8b702a7 -- contracts/` empty — intake is
read-only over the subject. No lead adjudicated, refuted, or fixed in this plan.
