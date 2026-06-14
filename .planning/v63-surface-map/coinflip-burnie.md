# Change-surface map — BURNIE / Coinflip subsystem

BASELINE `77580320` → SUBJECT `a8b702a7`. READ-ONLY analysis. Foundry build of the
subject is green (`forge build` exit 0; only lint notes, no errors).

Primary files:
- `contracts/BurnieCoinflip.sol`
- `contracts/interfaces/IBurnieCoinflip.sol`
- `contracts/modules/DegenerusGameDegeneretteModule.sol`
- `contracts/modules/GameAfkingModule.sol`

Cross-cutting reads that this dimension depends on:
- `contracts/BurnieCoin.sol` (initial-emission removal, shortfall-claim relocation)
- `contracts/StakedDegenerusStonk.sol` (redemption ↔ coinflip backing, keeper box-bounty)
- `contracts/DegenerusVault.sol` (VAULT seed-stake claim path)
- `contracts/libraries/EntropyLib.sol` (survival-flip / box-seed hash primitive)

---

## 1. What changed (intended behaviour vs incidental)

### 1.1 Initial BURNIE emission moved from a direct mint to seeded flip stakes
- BASELINE: `BurnieCoin` constructor minted **2,000,000 BURNIE directly to sDGNRS**
  as a held wallet balance; `_supply.vaultAllowance` started at 2,000,000 ether
  (virtual VAULT reserve).
- SUBJECT: `BurnieCoin._supply` starts fully zero, no constructor mint
  (`BurnieCoin.sol` constructor removed; `_supply` default-initialised). The
  emission is re-homed into `BurnieCoinflip`'s **new constructor**
  (`BurnieCoinflip.sol:188-198`), which writes seed flip stakes of
  `SEED_FLIP_DAILY = 200_000 ether` for days **1..20** (`SEED_FLIP_DAYS = 20`),
  to **both** `ContractAddresses.VAULT` and `ContractAddresses.SDGNRS`
  (`BurnieCoinflip.sol:140-143, 189-197`). Direct storage writes via
  `_setFlipStake` keep the seeds off the leaderboard / bounty / biggest-flip
  records. **Nothing mints up front** — each seed day only becomes BURNIE if it
  survives that day's coinflip.
- INTENT: "all BURNIE survives a coinflip before minting." This is the defining
  feature of the rework. Total seeded principal = 200k × 20 × 2 = 8M BURNIE of
  *stake*, of which roughly half is expected to win (≈4M expected minted before
  reward%, more with the win bonus), replacing the prior flat 2M direct grant +
  2M vault virtual reserve.

### 1.2 sDGNRS perpetual auto-rebuy latch (`sdgnrsAutoRebuyArmed`)
- New one-shot bool latch `sdgnrsAutoRebuyArmed` (`BurnieCoinflip.sol:174`, packs
  into slot 4 with `bountyOwedTo`+`flipsClaimableDay`, confirmed via
  `forge inspect`).
- In `processCoinflipPayouts` (`BurnieCoinflip.sol:870-893`):
  - While **not** armed: every resolved day auto-claims sDGNRS via
    `_claimCoinflipsAmount(SDGNRS, type(uint256).max, true)` — i.e. wins MINT to
    sDGNRS's wallet balance (redemption backing).
  - When `epoch >= SEED_FLIP_DAYS (20)`: arm the latch, set
    `autoRebuyEnabled = true`, `autoRebuyStartDay = lastClaim`, emit toggle.
  - Once armed: each resolved day calls `_claimCoinflipsInternal(SDGNRS, false)`
    only — wins roll into `autoRebuyCarry` (0 take-profit → nothing mints), and
    "BURNIE leaves sDGNRS's flip position solely through a redemption's
    burn+consume leg."
- BASELINE: sDGNRS enabled auto-rebuy in its OWN constructor at genesis
  (`coinflip.setCoinflipAutoRebuy(self, true, 0)`), so it was on rebuy from day 1;
  the 2M lived as held balance, not as a flip. The SUBJECT removes that
  constructor call (sDGNRS comment: "auto-rebuy is NOT enabled here … arms once
  the final seeded day settles") and centralises arming in the coinflip
  contract.

### 1.3 `claimCoinflipCarry` — new partial carry withdrawal entrypoint
- New external `claimCoinflipCarry(player, amount)` (`BurnieCoinflip.sol:754-778`,
  interface `IBurnieCoinflip.sol:46`). Settles resolved days first (wins roll into
  carry, a pending loss zeroes it), then mints up to `amount` from the *settled*
  carry while staying on auto-rebuy. RNG-lock gated; reverts `AutoRebuyNotEnabled`
  if not on rebuy. Take-profit chunks surfaced by the settle bank into
  `claimableStored` (claimed via the normal `claimCoinflips`).
- Test coverage exists: `test/fuzz/CoinflipCarryClaim.t.sol` (partial / cap /
  loss-zeroing / compounding).

### 1.4 Claim-window widening + perma-brick relaxation
- `COIN_CLAIM_DAYS 90 → 365`, `AUTO_REBUY_OFF_CLAIM_DAYS_MAX 1095 → 1460`, and the
  type of the day counters widened from `uint8` → `uint16`
  (`BurnieCoinflip.sol:136-138`; loop locals at 423, 448-457, 1022, 1033). The
  `uint8` window was capped at 255 and the loops used `uint8 remaining`; widening
  to `uint16` is what makes 365/1460 expressible without truncation. The deep
  auto-rebuy walk uses a `uint32 remaining` (line 448) for the 1460 path.
- `COIN_CLAIM_FIRST_DAYS` stays 30.

### 1.5 8-bit 3-state day-result packing (lossless lane)
- BASELINE: `mapping(uint24 => CoinflipDayResult{uint16 rewardPercent; bool win})`.
- SUBJECT: `mapping(uint24 => uint256) coinflipDayResultPacked` (32 days/slot,
  8-bit lanes) + helpers `_dayResult` / `_storeDayResult`
  (`BurnieCoinflip.sol:1092-1106`). 3-state byte: `0` = unresolved, `1` = resolved
  loss, `50..156` = resolved win at that reward%. `win` is derived (`b >= 50`).
  - Round-trip is lossless: every WIN stores `rewardPercent` in `[50,156]`
    (unlucky=50, lucky=150, normal 78+[0..37], +bonus up to +6 → max 156 ≤ 255),
    so `b >= 50` cleanly separates wins; a resolved LOSS stores `1`; an
    unresolved day reads `0`. Resolution-detection in the claim loops stays
    `rewardPercent == 0 && !win` → only the unresolved (`b==0`) state is skipped.
    Verified there is NO win whose `rewardPercent` can land in `[2,49]` (would
    mis-read as a loss): the only sub-50 fixed branch is unlucky=50.

### 1.6 Daily stake packing (2 days/slot, 128-bit wei lanes — lossless)
- BASELINE: `mapping(uint24 => mapping(address => uint256)) coinflipBalance`.
- SUBJECT: `coinflipStakePacked` (key = `day>>1`, two 128-bit wei lanes) +
  `_flipStake` / `_setFlipStake` (`BurnieCoinflip.sol:1072-1085`). Stored in **wei**
  (not whole tokens) because flip credits (keeper rewards, redemption shares) can
  be sub-1-BURNIE. Masked read/write preserves the sibling day. Stake width
  bounded by BurnieCoin's uint128 supply cap.

### 1.7 Degenerette BURNIE survival flip (double-or-nothing)
- New per-bet BURNIE survival flip in `_resolveFullTicketBet`
  (`DegenerusGameDegeneretteModule.sol:763-780`): if `currency == BURNIE` and the
  bet's `totalPayout != 0`, a single bet-keyed fair flip
  (`EntropyLib.hash2(rngWord, betId) & 1`) either doubles the payout
  (`acc.burnieMint += totalPayout; totalPayout *= 2`) or zeroes it
  (`acc.burnieMint -= totalPayout; totalPayout = 0`). EV-neutral. Each spin's
  payout was already added to `acc.burnieMint` in `_distributePayout` (line 906),
  so the `-=` removes exactly what this bet added → no underflow within the bet.
  Flushed once in `resolveBets` (`coin.mintForGame(player, acc.burnieMint)`,
  line 447).
- New box-origin BURNIE spins `resolveBurnieSpinsFromBox`
  (`DegenerusGameDegeneretteModule.sol:1347-1394`): 3 spins under ONE survival
  flip (`hash2(seed, BOX_SURVIVAL_TAG)`), mint-only, no pool/ETH/recirc — solvency
  safe on any box path. Emits a packed `BoxSpin` (3×72-bit reels + count@216 +
  survived@224 — no lane collision; lossless round-trip).
- INTENT: "all BURNIE entering existence survives at least one coinflip" extends
  to Degenerette BURNIE wins.

### 1.8 Afking BURNIE settlement consolidation
- `_settlePendingBurnie(player, Sub storage s)` helper
  (`GameAfkingModule.sol:1085-1096`) replaces three inline copies of the
  zero-then-`creditFlip(player, owed*1e18)` pattern (mintBurnie advance leg,
  re-subscribe settle, `claimAfkingBurnie`). CEI preserved (zero before external
  credit). Off the ETH/solvency path — pays a BURNIE flip credit. The presale-box
  credit derivation is unchanged. Largely a refactor + the BURNIE→flip-credit
  routing (consistent with §1.1's "survive a flip first" rule).

### 1.9 BurnieCoin shortfall-claim relocation (incidental, in-scope cross-read)
- `transfer`/`transferFrom` no longer call `_claimCoinflipShortfall`; instead
  `_transfer` itself tops up a short balance from coinflip winnings inline
  (`BurnieCoin.sol` `_transfer`), skipped while `rngLocked`. `onlyBurnieCoin` on
  the coinflip side narrowed to **COIN only** (sDGNRS dropped, since
  `claimCoinflipsForRedemption` is gone). Net behaviour for player transfers
  unchanged; the removed sDGNRS branch is replaced by `redeemBurnieShare`'s
  own consume.

### 1.10 Removed surface
- `BurnieCoinflip.claimCoinflipsForRedemption` (sDGNRS-only RNG-skip claim) DELETED
  (interface entry removed). No remaining caller in `contracts/` (grep clean).
- `BurnieCoin.IBurnieCoinflip.creditFlip` declaration removed (BurnieCoin no
  longer credits flips directly).
- `CoinflipDayResult` struct, `JACKPOT_RESET_TIME` constant, `_requireApproved`
  helper removed.

---

## 2. Correctness review of the focus items

### 2.1 Day-indexed accrual — OK
Seed stakes are written for days 1..20 inclusive in the constructor.
`processCoinflipPayouts` resolves exactly one `epoch` per call and is driven by
`advanceGame`. sDGNRS is auto-claimed every resolved day (no missed day), so its
cursor (`lastClaim`) tracks `flipsClaimableDay` 1:1 through the seed window. The
arming check `epoch >= SEED_FLIP_DAYS` fires when day 20 settles, AFTER that day's
claim has minted day-20's win to wallet; `autoRebuyStartDay` is then `lastClaim`
(= 20). Future days (21+) roll into carry. No off-by-one in the seed→arm
handoff was found.

### 2.2 Rebuy latch state machine — single-direction, cannot double-claim
`sdgnrsAutoRebuyArmed` is set exactly once (`epoch >= 20`) and never cleared. There
is no code path that disarms it or re-runs the arming block (it is gated behind
the `else` of `if (sdgnrsAutoRebuyArmed)`). Once armed, only
`_claimCoinflipsInternal` runs for sDGNRS (carry roll, 0 take-profit → mints
nothing). There is no double-mint: the seed-window branch mints via
`_claimCoinflipsAmount(...,true)` and the armed branch never mints. The latch can't
be entered twice (advanceGame is monotone in `epoch`), and `setCoinflipAutoRebuy`
is NEVER called for sDGNRS post-genesis, so the enabled flag can't be toggled off
to extract carry. No double-claim / re-entry of the latch found.

### 2.3 Survival-flip resolution — EV-neutral, no underflow, freeze-safe
- Per-bet flip (`_resolveFullTicketBet`) and box flip
  (`resolveBurnieSpinsFromBox`) both key off VRF-committed `rngWord`/`seed` plus
  the immutable `betId`/box seed, fixed at fulfilment; a losing bet pays 0 whether
  resolved or abandoned (selective-resolution earns nothing). Parity bit of a full
  keccak (`EntropyLib.hash2`, unchanged) is uniform → fair 50/50.
- `acc.burnieMint -= totalPayout` cannot underflow: the same `totalPayout` was
  added to `acc.burnieMint` across this bet's spins immediately before, in the
  same `_resolveFullTicketBet` frame; the conditional subtract removes exactly that
  contribution.

### 2.4 Carry-claim accounting — OK in isolation
`claimCoinflipCarry` settles first, then pays from the *settled* carry, RNG-locked.
Take-profit reserved chunks bank into `claimableStored` (separate claim domain),
the function only touches `autoRebuyCarry`. Matches the documented invariant and
the carry-claim test.

### 2.5 BURNIE stays off the ETH / claimablePool solvency path — confirmed
BURNIE is minted (`mintForGame`) / burned (`burnForCoinflip`/`burnCoin`) only; no
BURNIE flow credits `claimableWinnings` or the prize pools. Degenerette BURNIE
payouts mint directly; box BURNIE spins are mint-only. The afking BURNIE
settlement is a flip credit, never an ETH cut. The sDGNRS redemption BURNIE leg is
explicitly conserved (burn+consume offsets the deferred `creditFlip` mint, net new
BURNIE = 0). No new BURNIE→ETH path introduced.

### 2.6 Packed lanes round-trip losslessly — confirmed (see §1.5, §1.6)
Stake lane = wei in 128-bit halves (bounded by uint128 supply). Day-result lane =
8-bit 3-state, win∈[50,156]⊂[0,255]. `forge inspect BurnieCoinflip storageLayout`
confirms the new mappings occupy slots 0/1 and the slot-4 packing
(`bountyOwedTo`@0, `flipsClaimableDay`@20, `sdgnrsAutoRebuyArmed`@23).

---

## 3. Candidate focus areas for the adversarial sweep

### FA-1 (MED) — sDGNRS post-seed carry is stranded from redemption backing
`StakedDegenerusStonk.sol:1029-1031` computes `burnieOwed = (burnieBal +
previewClaimCoinflips(sDGNRS)) * amount / supply`, and
`redeemBurnieShare`'s consume waterfall (`BurnieCoinflip.sol:940-964`) covers
`base` only from sDGNRS's **held balance** + **claimableStored**.
`previewClaimCoinflips` (`:971-975`) = `_viewClaimableCoin` + `claimableStored`;
`_viewClaimableCoin` sums per-day WIN payouts as if claimable, but for an
auto-rebuy player those payouts roll into `autoRebuyCarry`, which **neither
`previewClaimCoinflips` nor the consume waterfall ever touches**. After day 20
sDGNRS is on perpetual rebuy, so its entire ongoing BURNIE accrual lands in the
carry. Net effect: redeemers are progressively **under-credited** for
carry-resident BURNIE, and that carry has no liquidation path (nothing calls
`claimCoinflipCarry(sDGNRS, …)`; sDGNRS holds no such code). Plausible because the
carry is the PRIMARY post-seed accrual sink yet is invisible to the only consumer
of sDGNRS's BURNIE backing. NOTE: this is conservative (under-credit / strand, not
over-credit or insolvency — `base <= burnieBal + claimableBurnie` so the waterfall
never reverts), and the pre-existing memory note rates BURNIE as
"worthless except the near-unfarmable whale pass," which bounds real impact. But
between resolutions `_viewClaimableCoin(sDGNRS)` returns 0 anyway (cursor==latest
after each daily auto-claim), so in steady state `burnieOwed` reflects only
sDGNRS's HELD balance — i.e. essentially zero ongoing BURNIE share to redeemers
post-seed. Worth confirming this matches design intent vs. an accidental loss of
the BURNIE-share economics the baseline 2M reserve provided. Severity_hint MED.

### FA-2 (MED) — VAULT seed stakes can age out of the 30-day claim window
The constructor seeds the VAULT identically (days 1..20), but ONLY sDGNRS is
auto-claimed by `processCoinflipPayouts`. The VAULT must claim via
`DegenerusVault.coinClaimCoinflips` → `claimCoinflips(VAULT, …)`. For a player with
`lastClaim == 0`, the window is `COIN_CLAIM_FIRST_DAYS = 30`
(`BurnieCoinflip.sol:423`), and `_claimCoinflipsInternal` sets
`start = minClaimableDay = latest - 30` when `start < minClaimableDay`, **silently
skipping** all days below it (lines 431-440). If the VAULT does not claim until
`flipsClaimableDay >= 51`, then `minClaimableDay = 21 > 20` and **every VAULT seed
day (1..20) is skipped — the VAULT's entire ~half-of-4M expected seed emission
never mints.** Plausible because the VAULT's seed is half the total initial
emission and has no auto-claim safety net (unlike sDGNRS) and no auto-rebuy
(removed for sDGNRS but the VAULT was never armed here either). Confirm whether
the VAULT is expected to claim within 30 days or be put on auto-rebuy at deploy;
if neither is guaranteed, the seed is at risk. Severity_hint MED.
Location: `contracts/DegenerusVault.sol:630-647` + `contracts/BurnieCoinflip.sol:420-457`.

### FA-3 (LOW) — `setCoinflipAutoRebuy` fromGame branch skips approval for non-zero player
`BurnieCoinflip.sol:662-668`: when `msg.sender == GAME` and `player != address(0)`,
the player is used verbatim with NO operator-approval check (the `else` /
`_resolvePlayer` arm is skipped). No in-protocol GAME module currently calls
`setCoinflipAutoRebuy` (grep clean), so this is presently unreachable, and it
matches baseline behaviour (not a regression). Flagged as a latent permissive
branch in case a future delegatecall path reaches it. Severity_hint LOW.

### FA-4 (LOW) — survival-flip seed reuses the box seed hash on the bet path
On a Degenerette bet, the survival flip uses `EntropyLib.hash2(rngWord, betId)`
(`:773`) and the per-bet lootbox box is opened with the SAME
`EntropyLib.hash2(rngWord, betId)` as its seed (`:791`). For BURNIE bets
`betLootboxShare == 0` so no box opens (no observable correlation), but the
shared derivation is worth a glance to confirm no path mixes a BURNIE survival
outcome with a box draw that a player could bias by choosing among their own
sequential `betId`s (betId is `++nonce`, not free; rngWord is VRF-committed after
placement). Plausible only as a defence-in-depth check. Severity_hint LOW.

### FA-5 (INFO) — claim-window widening to 365 increases the resolution-walk bound
`COIN_CLAIM_DAYS 90→365` and `AUTO_REBUY_OFF_CLAIM_DAYS_MAX 1095→1460` raise the
per-claim loop iteration ceiling. The deep auto-rebuy path uses `uint32 remaining`
(safe), the shallow path `uint16` (safe for 365). A claim that has accrued the
full 365-day window does a 365-iteration SLOAD walk; bound is per-call and
caller-paid, not in the advanceGame chain (sDGNRS auto-claim walks at most 1 new
day per resolution). Note only — confirm no realistic actor can force a
many-hundred-day cold-SLOAD walk into a gas-sensitive caller. Severity_hint INFO.

---

## 4. Files reviewed
- contracts/BurnieCoinflip.sol (full)
- contracts/interfaces/IBurnieCoinflip.sol (full diff)
- contracts/modules/DegenerusGameDegeneretteModule.sol (survival flip + box spins)
- contracts/modules/GameAfkingModule.sol (BURNIE settlement)
- contracts/BurnieCoin.sol (emission removal, shortfall relocation)
- contracts/StakedDegenerusStonk.sol (redemption BURNIE backing, keeper bounty)
- contracts/DegenerusVault.sol (VAULT seed claim path)
- contracts/libraries/EntropyLib.sol (hash primitive)
- forge inspect BurnieCoinflip storageLayout (slot/packing verification)
