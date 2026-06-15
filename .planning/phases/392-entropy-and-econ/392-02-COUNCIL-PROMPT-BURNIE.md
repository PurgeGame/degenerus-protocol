# Council Sweep 392-02 — BURNIE / coinflip-seeded-emission rework slice (BURNIE-01..06)

You are an external auditor on a cross-model council reviewing the **Degenerus Protocol** before a
Code4rena engagement. Read the EXACT frozen source at `a8b702a7` via
`git show a8b702a7:contracts/<File>.sol` (ignore the working tree — it has docs-only commits on top of
the frozen subject). Be concrete and reachable: a finding needs a real ordered call sequence (the multi-day
settle/claim sequence, the loss-sequence backing model, or the window-aging skip — where the ordering
matters) and a named state variable with a `file:line` at `a8b702a7`. No speculative gaps.

This slice reviews the **BURNIE / coinflip-seeded-emission rework** of the post-v62 change set: the initial
BURNIE emission moved from a direct 2M mint (+2M virtual VAULT reserve) into seeded flip stakes that must
each survive a coinflip before they mint; the sDGNRS perpetual auto-rebuy latch; the new partial
`claimCoinflipCarry` withdrawal entrypoint; the claim-window widening (90→365, 1095→1460) and `uint8→uint16`
counter widening; the two new packed storage lanes (the 2-days/slot 128-bit wei stake lane and the
32-days/slot 8-bit 3-state day-result lane); the Degenerette per-bet BURNIE survival flip + the box-origin
BURNIE spins ×3 under one survival flip; the afking BURNIE settlement consolidation; and the BurnieCoin
zero-start emission + inline shortfall top-up. We believe these properties hold across the change set —
every BURNIE survives a coinflip before minting, the 200k/day×20d seed conserves the removed 2M+2M, the
auto-rebuy latch is monotone, the sDGNRS redemption backing is complete, the VAULT seed is recoverable, and
the packed lanes round-trip losslessly with BURNIE off the ETH/`claimablePool` spine. **Your job is to find
where one of these beliefs breaks.**

## Threat priority (USER-locked for this slice)

DOMINANT = RNG/freeze (audited in the 391 slice; the RNG-lock half of the carry roll was attested airtight
there — do NOT re-audit the freeze window here). HIGH = gas-DoS only in the `advanceGame` chain
(16,777,216 gas = brick). **SPINE = solvency — and this slice is the solvency-ADJACENT spine of the BURNIE
rework.** LOW/confirmatory = access-control / reentrancy / MEV.

The framing that bounds severity here: **BURNIE is OFF the ETH / `claimablePool` solvency path by design
(BURNIE-06).** BURNIE is minted (`mintForGame`) / burned (`burnForCoinflip` / `burnCoin`) only — no BURNIE
flow credits `claimableWinnings` or the prize pools, and the sDGNRS redemption BURNIE leg is conserved
(the burn+consume nets new BURNIE = 0). So the concern here is **NOT an ETH solvency break.** The concern is
the **sDGNRS REDEMPTION-BACKING completeness / conservation**: a carry/seed accounting gap that
progressively **under-credits** redeemers, or **silently forfeits** seeded emission, is the value-bearing
defect this slice hunts. Concretely, in descending severity:
- a confirmed **redemption-backing under-credit** (the auto-rebuy carry invisible to the only consumer of
  sDGNRS's BURNIE backing) or a **lost-emission window** (a VAULT seed that ages out unrecoverably) — the
  spine concern of this phase, the prize targets here;
- an **emission over-mint / under-mint** vs the conservation identity (BURNIE-02) — value-bearing;
- a **latch double-claim or strand** (BURNIE-03) — value-bearing;
- a **survive-before-mint violation** (BURNIE-01) — breaks the defining invariant of the rework;
- a **lossy packed lane / sibling-day corruption** (BURNIE-06) — a value-bearing storage defect.

## Design-intent anchor (so you do not waste passes)

**"All BURNIE survives a coinflip before minting" is the DEFINING intent of this rework.** Every BURNIE
source — the seed stakes (mint only if the day's flip survives), the per-bet survival double-or-nothing, the
box BURNIE spins ×3 under one survival flip, the normal mint — gates on a survived coinflip by design.

**The stochastic backing trade is an INTENDED VARIANCE TRADE.** The old design held a flat 2M BURNIE direct
grant + a 2M virtual VAULT reserve as fixed backing. The new design seeds 200k/day×20d of *stake* (8M total
principal across both addresses) of which ~half is expected to win through flip survival, and after day 20
sDGNRS rolls its ongoing accrual perpetually on auto-rebuy. A bad-luck seed window therefore leaves sDGNRS
with **less** BURNIE backing than the old fixed reserve, and the perpetual auto-rebuy compounds the
position. **This variance is intended — the council VERIFIES conservation + completeness + monotonicity +
round-trip-losslessness, NOT whether the variance trade is desirable.** Do not flag "the seed could lose"
or "auto-rebuy is risky" as findings — those are the design. DO flag if the accounting that backs real
redeemers UNDER-CREDITS them relative to the BURNIE that actually exists in the position, or if seeded
emission is FORFEITED unrecoverably.

**BURNIE is rated "worthless except the near-unfarmable whale pass"** ([[degenerette-wwxrp-rtp-by-design]];
the lootbox BURNIE:tickets ETH-value ratio is ≈ 0.59:1 and the BURNIE-credit is illiquid flip-credit). This
**BOUNDS the real impact** of a backing under-credit: it is an under-credit / strand class, NOT an ETH
insolvency. **But a confirmed under-credit or a lost-emission window is still a value-bearing finding to
surface** — the bound governs severity, not whether it is a finding.

## KNOWN BY-DESIGN (do NOT flag — out of scope for this slice)

- **EV>100% RTP / positive-EV coinflip / positive-EV lootbox / refund floors are NOT findings**
  ([[intended-game-mechanics-not-findings]]) — they are documented, intended game economics. Do not flag
  "RTP too high" or "the coinflip pays out more than 100%".
- **Lootbox / redemption claim/open TIMING is not a player edge** ([[lootbox-resolution-timing-by-design]])
  — the open is permissionless and economically-incentivized; do not flag day/level/wait-to-open steering.
- **Operator-approval IS the trust boundary** ([[open-e-operator-approval-trust-boundary]]) — do NOT model
  a "tricked into approving" actor; the BURNIE-funding operator overload is accepted by design.
- **An admin/protocol-address breaking its OWN position at genesis with no engaged community is a
  non-finding** ([[genesis-admin-self-break-nonfinding]]). **CAVEAT — the VAULT/SDGNRS seed window-aging
  is NOT a genesis self-break:** it is a PROTOCOL-ADDRESS losing seeded EMISSION that backs REAL redeemers
  (the seed is the substance of the sDGNRS/VAULT BURNIE backing real users redeem against), which is
  distinct from an admin self-harm at votingSupply()==0. **DO charge the VAULT-window lead** (break-target
  2) — it is not excluded by the genesis-self-break ruling.
- **The RNG-freeze / RNG-lock window over the carry roll is OUT of scope here** — it was audited and
  attested airtight in the 391 RNG slice (FC-392-11's RNG-lock half: the daily request sets the lock, the
  callback stores the word while the lock holds, `claimCoinflipCarry` checks `rngLocked()` @759 before
  reading `autoRebuyCarry`). Here you own the **backing/EV-dynamics half** of FC-392-11 (the path-dependent
  backing vs outstanding obligations), NOT the freeze window. Do not re-litigate the freeze coverage.

## The thesis to BREAK (mapped to BURNIE-01..06)

We believe ALL of the following hold. Find a concrete counterexample to any one — or VERIFY SOUND with the
specific reason it holds.

1. **(BURNIE-01) Every BURNIE source mints only AFTER surviving a coinflip.** The seed stakes (only mint if
   that day's flip survives), the per-bet survival double-or-nothing, the box BURNIE spins ×3 under one
   survival flip, and the normal mint — find ANY BURNIE that mints without a survived flip.
2. **(BURNIE-02) Total seeded emission conserves the removed 2M direct + 2M virtual lumps.** 200k × 20 × 2
   = 8M of STAKE, ~half expected to win through flip survival, replacing the prior flat grant — find any
   over- or under-emission vs the conservation identity (BurnieCoin's `supplyIncludingUncirculated` =
   `totalSupply + vaultAllowance`; nothing mints up front; each seed day mints only on its survived flip).
3. **(BURNIE-03) The `sdgnrsAutoRebuyArmed` latch is monotone** (set once at `epoch >= SEED_FLIP_DAYS (20)`,
   never cleared) and cannot be entered/exited to double-claim (the seed-window branch mints via
   `_claimCoinflipsAmount(...,true)`; the armed branch never mints) or strand funds.
4. **(BURNIE-04) The auto-rebuy CARRY is reflected in the sDGNRS redemption backing.**
   `claimCoinflipCarry` accounting is correct AND `previewClaimCoinflips` / `redeemBurnieShare` account for
   carry-resident BURNIE in the sDGNRS backing.
5. **(BURNIE-05) The VAULT seed-stakes (days 1-20) are recoverable within the claim window** — they do not
   silently age out and forfeit ~half the seeded initial emission.
6. **(BURNIE-06) The packed stake lanes (2 days/slot, 128-bit wei) + the 8-bit 3-state day-result lane
   (0=unresolved / 1=loss / 50..156=win) round-trip losslessly, and BURNIE stays off the
   ETH/`claimablePool` solvency path.**

## Authoritative frozen line-cites (read the code via `git show a8b702a7:...`, do not trust the cite blindly)

- `contracts/BurnieCoinflip.sol`: constructor seed stakes `SEED_FLIP_DAILY = 200_000 ether` for days 1-20
  to VAULT + SDGNRS via direct `_setFlipStake` writes (constructor @188-200; `SEED_FLIP_DAYS = 20` @143;
  `SEED_FLIP_DAILY` @142); `sdgnrsAutoRebuyArmed` latch @174 (packs slot 4 with `bountyOwedTo` +
  `flipsClaimableDay`); `PlayerCoinflipState` with `autoRebuyCarry` uint128, `autoRebuyEnabled`,
  `autoRebuyStartDay`, `claimableStored` @150-161; `processCoinflipPayouts` @789 — the arming/claim block
  @877-887 (`if (sdgnrsAutoRebuyArmed)` → `_claimCoinflipsInternal(SDGNRS, false)` @878 [carry roll, mints
  nothing]; `else` → `_claimCoinflipsAmount(SDGNRS, type(uint256).max, true)` @880 [mints to wallet]; then
  `if (epoch >= SEED_FLIP_DAYS) { sdgnrsAutoRebuyArmed = true; ... }` @884-885); `claimCoinflipCarry` @754
  (`rngLocked` guard @759, settle-then-mint-from-settled-carry); `_claimCoinflipsInternal` @394 with the
  claim-window `minClaimableDay` skip @423-436 (`windowDays = start == 0 ? COIN_CLAIM_FIRST_DAYS :
  COIN_CLAIM_DAYS` @423; `if (start < minClaimableDay) start = minClaimableDay` @435-436 — silently skips
  below-window days); `COIN_CLAIM_DAYS = 365` / `COIN_CLAIM_FIRST_DAYS = 30` / `AUTO_REBUY_OFF_CLAIM_DAYS_MAX
  = 1460` @136-138; `redeemBurnieShare` consume waterfall @940-967 (covers `base` from sDGNRS held balance +
  `claimableStored` + a bounded `_claimCoinflipsAmount(SDGNRS, remainder, false)` @956 — never reads
  `autoRebuyCarry`); `previewClaimCoinflips` @971 (= `_viewClaimableCoin` + `claimableStored`);
  `_viewClaimableCoin` @1014 with its own `minClaimableDay` skip @1022-1030; `setCoinflipAutoRebuy` fromGame
  branch @662-668; the packed lanes `coinflipStakePacked` (2 days/slot, 128-bit wei lanes) @162 + the
  helpers `_flipStake` / `_setFlipStake`, and `coinflipDayResultPacked` (32 days/slot, 8-bit 3-state) @163 +
  `_dayResult` / `_storeDayResult`.
- `contracts/StakedDegenerusStonk.sol`: `burnieOwed = ((burnieBal + claimableBurnie) * amount) /
  supplyBefore` @1029-1031 where `claimableBurnie = coinflip.previewClaimCoinflips(address(this))` @1030;
  the redemption BURNIE leg `coinflip.redeemBurnieShare(beneficiary, burnieOwed)` @1072-1073; sDGNRS holds
  NO `claimCoinflipCarry` call (no carry liquidation path; grep clean); auto-rebuy NOT enabled in the
  sDGNRS constructor (it arms once the final seeded day settles, via `processCoinflipPayouts`).
- `contracts/DegenerusVault.sol`: VAULT seed claim path `coinClaimCoinflips(amount)` @630-631 →
  `coinflipPlayer.claimCoinflips(address(this), amount)`; VAULT not auto-rebuy-armed, not auto-claimed.
- `contracts/modules/DegenerusGameDegeneretteModule.sol`: per-bet BURNIE survival flip
  `EntropyLib.hash2(rngWord, betId) & 1 == 1` @773 (`acc.burnieMint += totalPayout` @774 [double] /
  `acc.burnieMint -= totalPayout` @777 [zero]); each spin's payout added to `acc.burnieMint` in
  `_distributePayout` @907; flushed once `coin.mintForGame(player, acc.burnieMint)` @447;
  `resolveBurnieSpinsFromBox` @1347 (3 spins under one survival flip
  `EntropyLib.hash2(seed, BOX_SURVIVAL_TAG) & 1 == 1` @1385, mint-only `coin.mintForGame(player, total)`
  @1387, no pool/ETH/recirc; `BOX_SURVIVAL_TAG` @1250).
- `contracts/modules/GameAfkingModule.sol`: `_settlePendingBurnie(player, Sub storage s)` @1085
  (zero-then-`coinflip.creditFlip(player, owed * 1 ether)` @1095, CEI; a BURNIE flip credit, never a
  transfer / `mintForGame`).
- `contracts/BurnieCoin.sol`: `_supply` starts fully zero (no constructor mint) @178;
  `supplyIncludingUncirculated` = `totalSupply + vaultAllowance` @256; `_transfer` inline shortfall top-up
  (skipped while `rngLocked`); `onlyBurnieCoin` narrowed to COIN only.

## Concrete break-targets

The two prime backing leads are charged HARD as the lead dedicated numbered items — they demand a
**CONFIRM / REFUTE / BY-DESIGN with the backing accounting traced exhaustively, NOT a hand-wave.**

### 1. (PRIME — BURNIE-04 / FC-392-16, MED) Auto-rebuy carry excluded from the sDGNRS redemption backing

`burnieOwed = ((burnieBal + claimableBurnie) * amount) / supplyBefore` (`StakedDegenerusStonk:1029-1031`),
where `claimableBurnie = coinflip.previewClaimCoinflips(address(this))` (@1030). `previewClaimCoinflips`
(`BurnieCoinflip:971`) = `_viewClaimableCoin` + `claimableStored`. `redeemBurnieShare`'s consume waterfall
(`BurnieCoinflip:940-967`) covers `base` from sDGNRS's held balance + `claimableStored` + a bounded
`_claimCoinflipsAmount(SDGNRS, remainder, false)` (@956) — and **never reads `autoRebuyCarry`.**

After day 20, sDGNRS is on PERPETUAL auto-rebuy (`processCoinflipPayouts` armed branch @877-878 calls
`_claimCoinflipsInternal(SDGNRS, false)` — 0 take-profit, mints nothing), so its ENTIRE ongoing BURNIE
accrual rolls into `autoRebuyCarry` — which NEITHER `previewClaimCoinflips` NOR the consume waterfall ever
reads, AND there is NO liquidation path (nothing calls `claimCoinflipCarry(SDGNRS, …)`; sDGNRS holds no
such code).

**TRACE EXHAUSTIVELY and CONFIRM or REFUTE:**
- **(i)** Is the carry-resident BURNIE invisible to the only consumer of sDGNRS's BURNIE backing
  (`burnieOwed` via `previewClaimCoinflips` + the consume waterfall), so redeemers are progressively
  UNDER-CREDITED for the carry-resident BURNIE?
- **(ii)** Is this a CONSERVATIVE under-credit / strand (`base <= burnieBal + claimableBurnie` so the
  waterfall never reverts → no over-credit, no insolvency), or can it ever OVER-credit / strand value
  irrecoverably?
- **(iii)** In steady state, does `_viewClaimableCoin(SDGNRS)` return 0 between resolutions (the cursor
  `lastClaim` == latest after each daily auto-claim), so `burnieOwed` reflects ONLY the HELD balance and
  the ongoing BURNIE share to redeemers post-seed is essentially zero?

Settle whether this MATCHES design intent (an intended loss of the BURNIE-share economics the old fixed 2M
reserve provided — BURNIE being "worthless except the whale pass") or is an ACCIDENTAL backing gap. A
hand-wave ("BURNIE is worthless so it doesn't matter") is NOT acceptable — require the backing accounting
TRACED to the carry: show whether the carry is or is not part of `burnieOwed`, and quantify the realized
under-credit.

### 2. (PRIME — BURNIE-05 / FC-392-17, MED — "most likely to need a contract change") VAULT seed window-aging

The constructor seeds the VAULT IDENTICALLY (days 1-20, 200k each), but ONLY sDGNRS is auto-claimed by
`processCoinflipPayouts`. The VAULT must claim via `DegenerusVault.coinClaimCoinflips` (@630-631) →
`claimCoinflips(VAULT, …)`. For a player with `lastClaim == 0` the window is `COIN_CLAIM_FIRST_DAYS = 30`
(`BurnieCoinflip:423`), and `_claimCoinflipsInternal` sets `start = minClaimableDay = latest - windowDays`
when `start < minClaimableDay`, **SILENTLY SKIPPING** all days below it (@435-436; the read-path twin in
`_viewClaimableCoin` @1029-1030). If the VAULT does not claim until `flipsClaimableDay >= 51`, then
`minClaimableDay = 51 - 30 = 21 > 20` and EVERY VAULT seed day (1-20) is skipped — the VAULT's entire
~half-of-4M expected seed emission never mints.

**DETERMINE:**
- **(i)** Is the VAULT EXPECTED / GUARANTEED to claim within 30 days, or to be on auto-rebuy at deploy?
- **(ii)** Is there ANY auto-claim or auto-rebuy safety net for the VAULT seed (there is for sDGNRS via the
  armed branch; is there ANY for the VAULT — a constructor `setCoinflipAutoRebuy`, an `advanceGame`-driven
  claim, an operational keeper)?
- **(iii)** Under the realistic deploy/operations timeline, is the VAULT seed at risk of SILENT forfeiture?

Settle: **INTENDED forfeiture (BY-DESIGN** — e.g. the VAULT is operationally claimed within 30 days, or the
seed is deliberately a use-it-or-lose-it incentive) **or a real DEFECT (CONFIRMED → routed fix).** This is
the one the surface map flagged as the MOST LIKELY real contract change — give it rigorous dedicated
treatment, not a "the operator will claim it" hand-wave; require the recoverability traced through the
window math.

### 3. (BURNIE-02, the conservation target) Seed emission conservation vs the removed 2M+2M

Confirm the constructor seeds days 1-20 INCLUSIVE to BOTH addresses (200k × 20 × 2 = 8M of stake), that
`processCoinflipPayouts` resolves exactly one epoch per `advanceGame` call with sDGNRS auto-claimed every
resolved day (the cursor `lastClaim` tracks `flipsClaimableDay` 1:1 through the seed window), and that the
seed→arm handoff at `epoch >= SEED_FLIP_DAYS` has NO off-by-one (arming fires AFTER day-20's win mints;
`autoRebuyStartDay = lastClaim = 20`; days 21+ roll to carry). Anchor on the green `BurnieEmissionSeeds`
invariant (5/5 in `test/REGRESSION-BASELINE-v63.md`). Find any OVER- or UNDER-emission vs the conservation
identity (`supplyIncludingUncirculated`; nothing mints up front), or confirm SOUND with the conservation
identity cited.

### 4. (BURNIE-03, the latch target) Auto-rebuy latch monotonicity

Confirm `sdgnrsAutoRebuyArmed` is set EXACTLY ONCE (`epoch >= SEED_FLIP_DAYS`, @884-885), never cleared,
gated behind the `else` of `if (sdgnrsAutoRebuyArmed)`, with NO disarm / re-run path; the seed-window
branch mints via `_claimCoinflipsAmount(...,true)` (@880) and the armed branch never mints
(`_claimCoinflipsInternal(SDGNRS, false)` @878 → no double-mint); `setCoinflipAutoRebuy` is NEVER called for
sDGNRS post-genesis so the `autoRebuyEnabled` flag can't be toggled off to extract carry. **FC-392-18 folds
in:** the `setCoinflipAutoRebuy` fromGame branch (@662-668) skips operator-approval for a non-zero player,
but no in-protocol GAME module calls it (grep clean) → presently unreachable + matches baseline; confirm it
STAYS unreachable (a latent permissive branch, NOT a regression). Find any latch re-entry / double-claim /
strand, or confirm SOUND.

### 5. (BURNIE-01, the survive-before-mint completeness target) Every BURNIE source gates on a survived flip

Enumerate EVERY BURNIE mint source and confirm each gates on a survived coinflip:
- the seed stakes (mint only if the day's flip survives — resolved via `processCoinflipPayouts` /
  `_claimCoinflipsInternal`);
- the per-bet survival double-or-nothing (`DegeneretteModule:773-777`: `acc.burnieMint +=` doubles /
  `-=` zeroes; nets to the bet's own contribution per losing bet, flushed once `mintForGame` @447);
- the box BURNIE spins ×3 under one survival flip (`resolveBurnieSpinsFromBox:1347-1387`, mint-only);
- the normal mint;
- the afking BURNIE settlement (`_settlePendingBurnie:1085-1095`, a `creditFlip` flip credit not a direct
  mint — it stakes a flip, consistent with the survive-first rule).

**FC-392-19 folds in:** the survival flip seed reuses the box seed hash `hash2(rngWord, betId)` on the bet
path — for BURNIE bets `betLootboxShare == 0` so no box opens (no observable correlation); confirm no path
mixes a BURNIE survival outcome with a box draw a player could bias via their own sequential `betId`s
(`betId` is `++nonce`, not free; `rngWord` is VRF-committed after placement). Find any BURNIE that mints
without a survived flip, or confirm SOUND.

### 6. (BURNIE-06, the packed-lane round-trip + off-spine target)

Confirm the stake lane (`coinflipStakePacked`, key `day>>1`, two 128-bit wei lanes; wei because flip
credits can be sub-1-BURNIE; masked read/write preserves the SIBLING day; stake width bounded by
BurnieCoin's uint128 supply cap) and the 8-bit 3-state day-result lane (`coinflipDayResultPacked`, key
`day>>5`, 32 lanes; 0=unresolved, 1=loss, 50..156=win; `win` derived `b >= 50`; verify NO win can land in
`[2,49]` to mis-read as a loss — the only sub-50 fixed branch is unlucky=50) round-trip LOSSLESSLY; and that
BURNIE never credits `claimableWinnings` or the prize pools (`mintForGame` / `burnForCoinflip` / `burnCoin`
only; the sDGNRS redemption BURNIE leg burn+consume nets new BURNIE = 0). Find any lossy lane /
sibling-corruption / BURNIE→ETH path, or confirm SOUND.

### 7. (FC-392-11, MED — the backing/EV-dynamics half cross-referenced from 391) Loss-sequence backing model

The stochastic sDGNRS auto-rebuy backing rolls win-after-win until a loss zeroes the pending stake. **MODEL**
whether a sequence of losses (or a single large-carry loss) can drop sDGNRS BURNIE backing below outstanding
redemption obligations, and whether `claimCoinflipCarry` (a player-pull from the carry — though note sDGNRS
holds no such call) interacts with the sDGNRS settle to let a redeemer extract during a window where backing
is mid-roll. **NOTE the RNG-lock window over the carry roll was attested airtight at 391 (cross-ref) — do
NOT re-audit the freeze window; here the concern is the BACKING DYNAMICS (the path-dependent backing vs
obligations).** **FC-392-13 folds in:** `claimCoinflipCarry` settles resolved days (wins→carry, pending
loss→zero) BEFORE withdrawing — confirm the take-profit chunks the settle banks into `claimableStored` and
that the carry withdrawal cannot DOUBLE-COUNT a single win across the two channels (the `claimableStored`
take-profit channel and the `autoRebuyCarry` withdrawal channel). Model the loss-sequence backing, or
confirm SOUND.

### 8. (FC-392-12 / FC-392-20, LOW-INFO) Seed leaderboard/bounty exclusion + claim-loop gas ceiling

- **FC-392-12:** the seed stakes are direct `_setFlipStake` writes SPECIFICALLY to stay off the top-bettor
  leaderboard, the bounty, and the biggest-flip records. Confirm no path reads the seed
  `coinflipStakePacked[d>>1][VAULT|SDGNRS]` for days 1-20 into a leaderboard / bounty / BAF /
  `biggestFlipEver` computation that mis-credits the protocol addresses.
- **FC-392-20:** the claim-window widening to 365 (+1460 auto-rebuy-off) raises the per-claim
  resolution-walk iteration ceiling (the deep `uint32 remaining` path is safe; the shallow `uint16` path is
  safe for 365; per-call + caller-paid, NOT in the `advanceGame` chain — sDGNRS auto-claim walks at most 1
  new day per resolution). Confirm no realistic actor can force a many-hundred-day cold-SLOAD walk under the
  new packed masked sub-word reads into a gas-sensitive caller (this echoes the permissionless-access gas
  lead FC-393-04, cross-ref 393).

## Output (per item)

For each break-target AND each thesis point (BURNIE-01..06), state ONE of:
- **FINDING:** PROPERTY broken · reachable ordered CALL SEQUENCE (the multi-day settle/claim sequence; the
  loss-sequence backing model; the window-aging skip — where the ordering matters) · STATE VAR + `file:line`
  at `a8b702a7` · SEVERITY (per the threat priority above — a redemption-backing under-credit or a
  lost-emission window is the spine concern here) · WHY the existing conservation / latch / CEI / consume
  waterfall does NOT stop it.
- **VERIFIED SOUND / INTENDED:** the property and the SPECIFIC reason it holds — cite the conservation
  identity, the monotone latch, the round-trip bound, the consume-waterfall coverage, or the design intent
  (the intended variance trade / the BURNIE-worthless bound) — so the adjudicator can confirm your reasoning.

Do NOT pre-state a verdict you have not traced to source. Read the frozen tree at `a8b702a7` via
`git show`. The council finds; the adjudicator (Claude) reconciles at 392-04.
