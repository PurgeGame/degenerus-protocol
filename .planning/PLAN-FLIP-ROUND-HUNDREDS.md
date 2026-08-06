# PLAN — Round player-facing awards onto round, displayable figures

**Status:** IMPLEMENTED (2026-08-06), and AMENDED THREE TIMES BY THE OWNER DURING EXECUTION.
Read §0 before anything else — the amendments changed the shape of the result, and several
paragraphs below still argue for the pre-amendment design where that argument is still the
reason the mechanism exists. Where §0 and a later section disagree, §0 wins.
**Subject:** contracts tree `d93ef47a` @ `4a50d58c` (+ the uncommitted solo-quadrant diff in `DegenerusGameJackpotModule.sol`).
**Goal:** every player-facing award lands on a figure a UI can state plainly.

---

## 0. What was actually built (supersedes any contradiction below)

**The governing principle, from the owner, mid-execution: _"the exact coin jackpot EV doesn't
even matter that much, I just want the UI to be easy."_** Round, equal, displayable figures beat
exact budget spend and beat exact EV. Truncation toward the protocol is acceptable everywhere.

Nine sites in three token surfaces:

| # | Site | Mechanism |
|---|------|-----------|
| 1-2 | `_awardDailyCoinToTraitWinners`, `_awardFarFutureCoinJackpot` | **§3a** whole 100-FLIP units, EQUAL per winner, leftover unminted, NO entropy |
| 3 | `_payGoldenTicket` | **§3b** plain truncate to 100 FLIP |
| 4-7 | `_resolvePresaleBox`, `_settleLootboxRoll`, `_resolveBet`, `resolveFlipSpinsFromBox` | **§3c** Bernoulli collapse above 1,000 FLIP, `floorWholeFlip` at or below |
| 8 | `_distributeTicketJackpot` + its two helpers | **§3e** WHOLE TICKETS only (1 ticket = 4 entries), EQUAL per winner, leftover unqueued |
| 9-10 | `_presaleBoxDgnrsReward`, `_lootboxDgnrsReward` | **§3f** DGNRS floored to 3 significant figures, NO entropy |

**AMENDMENT 1 — sub-threshold awards are FLOORED, not exact.** At the four §3c sites, an award
at or below `FLIP_ROUND_THRESHOLD` goes through `FlipRoundLib.floorWholeFlip`, so it is a whole
FLIP and NOT a 100-FLIP multiple. A survived 951.9-FLIP Degenerette payout pays **951 FLIP** and
contributes 951 FLIP to the `acc.flipMint` flush. Any statement below that "every award is a
100-FLIP multiple", that "sub-threshold awards pay exactly", or that the flush sums 100-FLIP
multiples is FALSE as built.

**AMENDMENT 2 — §3a pays EQUAL shares and consumes NO entropy.** The extra-unit window, its
VRF-derived start offset, and `FLIP_EXTRA_UNIT_TAG` were all deleted. `units % winners` goes
unminted. Any statement below about a start-offset roll, a contiguous window, or an exact
budget spend at §3a describes a design that was built and then removed.

**AMENDMENT 3 — the ticket jackpot pays WHOLE TICKETS, equal per winner (§3e).** Budgets are
denominated in entries (1 ticket = 4 entries). `tickets = entries / 4`; a budget under one whole
ticket pays nobody; `cap = min(maxWinners, tickets)`; every winner gets `(tickets / cap) * 4`
entries. The `distParams` remainder window, its cursor, and the `globalIdx` thread were deleted.
Unqueued backing stays in `nextPrizePool` — verified, not stranded.

**Emission bounds as built** (the §2 paragraph below is stale on this):
- §3a leftover is `units % winners` units, up to `winners - 1`. Zero below the winner ceiling.
  Worst relative case ~49% at 99 units over 50 winners (a 9,900-FLIP budget pays 5,000 and
  leaves 4,900 unminted); under 10% by 500 units, under 1% by 5,000.
- §3c is NOT strictly up versus the old whole-FLIP floor. A 1,137.9-FLIP award now resolves to
  1,100 or 1,200 with expectation 1,137 — below the 1,137 the old floor paid only by the
  sub-1-FLIP dust, but the variance is new and the outcome can be 37.9 FLIP down.
- §3f discards under 1% of a DGNRS award (1/mantissa: worst 1/100, best 1/999).

---

## 1. What exists today

FLIP awards are already **floored to whole FLIP** (`(x / 1 ether) * 1 ether`) at two of the sites,
and unrounded at the rest. The floor is a strict downward bias: the sub-1-FLIP residue evaporates
(recorded as `D-40N-BUR-DUST-01` / `D-40N-BUR-SILENT-01`, and pinned by two source-text unit tests).

Stochastic (Bernoulli) rounding is **already the house pattern** for the *ticket* collapse:

- `DegenerusGameJackpotModule.sol:2536-2547` — scaled tickets → whole, round up with p = frac/`QTY_SCALE`
  off `uint32(entropy >> 96)`.
- `DegenerusGameLootboxModule.sol:1482-1487` — same collapse off `uint32(rollSeed >> 224)`.
- Harnesses: `contracts/test/JackpotBernoulliTester.sol`, `contracts/test/LootboxBernoulliTester.sol`;
  statistical EV tests already assert `mean(roundedUp) ≈ frac/scale`.

So this plan is **the existing Bernoulli collapse, re-pointed from ticket counts to FLIP amounts**,
with the granule moved from 1 FLIP to 100 FLIP. Nothing conceptually new is being introduced.

---

## 2. The rounding primitive

```solidity
/// @dev 100 FLIP — the award granule (1 FLIP = 1 ether).
uint256 internal constant FLIP_ROUND_UNIT = 100 ether;

/// @dev Collapse `amount` to a whole-100-FLIP multiple. The 0..99 whole-FLIP remainder
///      rounds up with probability rem/100 off a uint32 entropy window (modulo bias
///      ~2e-8, the same window width the ticket collapse uses). Sub-1-FLIP dust still
///      evaporates, exactly as the current whole-FLIP floor does (D-40N-BUR-DUST-01).
function roundFlipToHundreds(uint256 amount, uint256 entropy)
    internal pure returns (uint256)
{
    uint256 hundreds = amount / FLIP_ROUND_UNIT;
    uint256 remFlip = (amount % FLIP_ROUND_UNIT) / 1 ether;   // 0..99
    if (remFlip != 0 && (uint32(entropy) % 100) < remFlip) {
        unchecked { ++hundreds; }
    }
    return hundreds * FLIP_ROUND_UNIT;
}
```

**Why `% 100` on whole FLIP and not `% 100 ether` on wei.** A `% 100 ether` (1e20) comparison needs a
~67-bit entropy window to keep the modulo bias small; the free windows in the existing seed bit-budgets
are 32- and 72-bit. Reducing the remainder to whole FLIP first collapses the domain to 0..99, which a
32-bit window covers with ~2e-8 bias — identical to the ticket collapse the codebase already ships and
already tests. It also preserves the current sub-1-FLIP evaporation instead of quietly changing it.

**Net emission effect vs today.** SUPERSEDED — see §0 "Emission bounds as built". The
"strictly up at §3c" and "less than 100 FLIP per draw at §3a" bounds below were written for the
pre-amendment design and are both wrong as built: §3c gained variance in both directions, and
the §3a leftover is bounded by `winners - 1` units, not by one unit.

*(Original, retained because it is the reason the primitive discards sub-1-FLIP dust the way it
does: at the §3c sites the collapse pays the 0..99.999… FLIP remainder at its expectation,
losing only sub-1-FLIP dust, where the old floor burned that residue unconditionally.)*

**Helper location.** New `contracts/libraries/FlipRoundLib.sol` (`roundFlipToHundreds` +
`floorWholeFlip`, both `internal pure`); `contracts/libraries/SigFigLib.sol` carries the DGNRS
`floorToThreeSigFigs`.
An `internal` on `DegenerusGameStorage` would also work but is inherited by `DegenerusGame` itself,
which has only ~198 bytes of EIP-170 headroom at the real nonzero `DEPLOY_DAY_BOUNDARY`; the optimizer
should strip an uncalled internal, but a library sidesteps the question entirely. See §6.

---

## 3. Three shapes of site

The seven ORIGINAL FLIP sites split into three kinds, and each gets different treatment. §3d
surveys the rest of the FLIP surface. Two further shapes were added by owner amendment during
execution and are recorded in §0: §3e (whole-ticket jackpot awards) and §3f (DGNRS significant
figures).

### 3a. Budget-split sites — floor the winner count instead of rounding (OWNER-RULED)

The two coin-jackpot sites divide a budget among N winners, so the remainder has somewhere to go: a
different winner. **Floor the winner count so every winner clears 100 FLIP**, and the whole thing
becomes integer arithmetic in 100-FLIP units with no probabilistic rounding at all.

```
units    = budget / FLIP_ROUND_UNIT      // whole 100-FLIP units in the budget
winners  = min(units, MAX_WINNERS)       // 50 near-future / `found` far-future
if (winners == 0) return;                // budget under 100 FLIP pays nobody
amount   = (units / winners) * FLIP_ROUND_UNIT   // >= 100 FLIP, IDENTICAL for every winner
```

**OWNER-RULED (2026-08-06): equal shares, and the leftover is simply not minted.** An earlier
revision handed `units % winners` winners one extra unit apiece, placed by a VRF-derived
contiguous window, so the budget was spent to the last unit. That is gone. Two winners in the
same draw must never be able to compare their awards and find one short, and the UI must be able
to state one number per draw. Exact budget spend was traded away deliberately.

Properties this buys, none of which the Bernoulli version had:

- **No winner ever receives zero.** Every paid winner clears 100 FLIP by construction.
- **Every winner receives the same amount.** One figure per draw, for the event feed and the UI.
- **The budget is never overshot.** `winners × amount <= budget` always. Two things go unminted:
  the `units % winners` leftover (up to `winners - 1` units) and the sub-100-FLIP dust in
  `budget % FLIP_ROUND_UNIT` — the latter matching today's sub-1-FLIP evaporation
  (`D-40N-BUR-DUST-01`) one granule up.
- **No randomness whatsoever in the amount.** The VRF word still picks the levels and the holders;
  nothing about the figure they receive is drawn.

**Cost of the equal-share rule.** The unminted leftover is `units % winners`, worst-case
`winners - 1` units. It is zero whenever `units <= MAX_WINNERS` (the common regime — every winner
gets exactly 100 FLIP) and whenever `winners` divides `units`. The relative cost peaks in the band
just above the ceiling: at `units = 99, winners = 50` it is 49 units of 99, i.e. ~49% of a
5,000–10,000 FLIP budget. It falls off fast — under 10% by `units = 500`, under 1% by
`units = 5,000`. Accepted: the near-future budget is small in exactly that band, and exact coin-
jackpot EV is not a design goal (see §8 D3).

Worked example, 100 ETH level pool at the 0.04 ETH standard price:

```
coinBudget = pool × 1000 / (price × 400)   = 6,250 FLIP
nearBudget = 75%                           = 4,687 FLIP  → 46 units
winners    = min(46, 50)                   = 46
perWinner  = 46/46 = 1 unit                = 100 FLIP each, extra = 0
                                             (87 FLIP dust evaporates)
```

versus today's 50 winners × 93.75 FLIP floored to 1 FLIP. Same money, round numbers, no zeroes.

At a larger pool the ceiling binds and the leftover appears — e.g. `units = 75, winners = 50` →
`amount = 1 unit`: all 50 winners get 100 FLIP and 25 units go unminted. At `units = 150,
winners = 50` the division is even again: all 50 get 300 FLIP, nothing is left over.

| # | Site | Change |
|---|------|--------|
| 1 | `JackpotModule.sol` `_awardDailyCoinToTraitWinners` | replace the `cap > coinBudget` clamp and the `/1 ether*1 ether` floor with the unit math above; `MAX_WINNERS` = `DAILY_COIN_MAX_WINNERS` (50) |
| 2 | `JackpotModule.sol` `_awardFarFutureCoinJackpot` | same, with `MAX_WINNERS` = `found`; pay the first `winners` of the VRF-ordered `winners[]` array and drop the tail |

Note site 2's sampling loop discovers `found` ≤ 10 winners *before* the budget is known to be
divisible; truncating to `winners = min(units, found)` simply pays fewer of them. The array order is
already fixed by the per-sample VRF draw, so taking a prefix introduces no new choice.

### 3b. The big jackpot leg — plain truncate, no RNG at all (OWNER-RULED)

| # | Site | Award | Change |
|---|------|-------|--------|
| 3 | `JackpotModule.sol:1602-1607` `flipCredit` | golden-ticket / grand flip leg | `flipCredit = (flipCredit / FLIP_ROUND_UNIT) * FLIP_ROUND_UNIT` |

The flip leg is 5% of `futurePrizePool` on the 4-gold rung and ~19% of the whole headline on the
grand, so a 100-FLIP truncation is noise:

| future prize pool | flip leg @ 0.04 ETH price | truncation cost |
|---|---|---|
| 1 ETH | 1,250 FLIP | ≤ 8% |
| 10 ETH | 12,500 FLIP | ≤ 0.8% |
| 100 ETH | 125,000 FLIP | ≤ 0.08% |

It only falls below 100 FLIP when the future pool is under ~0.08 ETH (standard price) or ~0.48 ETH
(milestone price) — a game that has barely started — and the loss is capped at 100 FLIP ≈ 0.004 ETH
of face value either way.

**This is the single biggest simplification in the plan.** Truncating deletes the entire D5 workstream:
no seed threaded through `_resolveGoldenTicket` / `_payGoldenTicket`, no `uint256 seed` param on
`payGoldenTicketGrand`, no `IDegenerusGameModules.sol:71` interface change, no
`FoilPackModule.sol:1172` call-site change, and no `check-delegatecall` / `check-raw-selectors`
re-run. Site 3 becomes a one-line edit inside an existing private function.

### 3c. Small-award sites — Bernoulli round to 100, but only above 1,000 FLIP (OWNER-RULED)

| # | Site | Award | Today | VRF word already in scope |
|---|------|-------|-------|---------------------------|
| 4 | `LootboxModule.sol:818-820` `flipOut` | presale box FLIP branch | floored to 1 FLIP | the index's committed daily word, via the box `seed` |
| 5 | `LootboxModule.sol:1465` `flipAmount` | every lootbox roll's FLIP leg | floored to 1 FLIP | `rollSeed` |
| 6 | `DegeneretteModule.sol:887-895` per-bet `totalPayout` | FLIP bet payout, post survival-flip | unrounded | `rngWord` + the immutable `betId` |
| 7 | `DegeneretteModule.sol:1727-1730` `total` | box FLIP spins, post survival-flip | unrounded | the box `seed` |

These four bottom out small, because every one of them is driven by a 0.01 ETH box minimum
(`MintModule.sol:104/108`) or the 100 FLIP `MIN_BET_FLIP`. Smallest possible award:

| site | @ 0.01 price | @ 0.04 price | @ 0.24 price |
|---|---|---|---|
| presale box (min box, lowest 140.98% band) | 1,410 FLIP | 352 FLIP | 59 FLIP |
| lootbox FLIP leg (min box, lowest 43.88% band) | 439 FLIP | 110 FLIP | 18 FLIP |
| box FLIP spin stake (70.6% of the above) | 310 FLIP | 77 FLIP | 13 FLIP |
| degenerette bet | payouts scale off a 100 FLIP minimum bet | | |

A flat 100-FLIP granule on an 18-FLIP award is a 100% haircut, so:

```solidity
uint256 constant FLIP_ROUND_THRESHOLD = 1_000 ether;

if (amount > FLIP_ROUND_THRESHOLD) {
    amount = FlipRoundLib.roundFlipToHundreds(amount, entropy);
}
// at or below the threshold, pay the exact amount — ragged but honest
```

Above 1,000 FLIP the granule is ≤10% and falling; below it, small wins stay exact. The threshold is
not gameable: the rounding is EV-neutral either side of it, so there is nothing to gain by steering a
payout across the line, and payouts are not finely steerable to begin with.

**Applied to all four (OWNER-RULED).** The threshold covers sites 4–7, not just degenerette: sites 4
and 5 have the identical cliff (110 FLIP at standard price, 18 at milestone) and take the identical
fix. One rule, one constant, one thing to test.

**Ordering against the survival flip.** Sites 6 and 7 round the *final* amount — after the survival
flip has doubled or zeroed it. A 600 FLIP payout that survives becomes 1,200 and rounds; the same
payout losing its flip is 0 and never reaches the threshold. So the threshold is always read against
the number the player actually receives.

**OWNER-RULED OUT:** `DegeneretteModule.sol:913-917` `refFlip` (the affiliate 7% on high-match ETH
spins) is an affiliate credit and stays untouched, along with every other affiliate FLIP path —
`DegenerusAffiliate.sol:576/594/846/870` and the affiliate-deity FLIP bonus inside
`BingoModule.claimAffiliateDgnrs` (`:266`). Seven sites, not eight.

**Entropy rule (owner-ruled).** Every roll that remains — the §3a start offset and the §3c round-up —
is a **domain-separated keccak of the committed VRF word plus immutable per-award data**
(`EntropyLib.hash2(vrfWord, TAG ^ awardKey)`), not a spare bit-slice of a word already doing another
job. That costs one keccak (~36 gas) per award and buys an argument that needs no bit-budget
bookkeeping to verify. `awardKey` is the pull index, the `betId`, the box index — never a value the
caller picked. No mutable storage is read, so `v45-vrf-freeze-invariant` holds unchanged, and the
existing bit-budget comment blocks (`LootboxModule.sol:1338-1347`) stay accurate because no new
window is consumed.

**Site 6 mechanics.** `totalPayout` and this bet's contribution to `acc.flipMint` are the same number
(both sum the raw per-spin payouts; the survival flip doubles or zeroes both). So round *after* the
survival block and carry the delta into the accumulator:

```solidity
uint256 rounded = FlipRoundLib.roundFlipToHundreds(
    totalPayout,
    EntropyLib.hash2(rngWord, betId ^ FLIP_ROUND_TAG)
);
if (rounded > totalPayout)      acc.flipMint += rounded - totalPayout;
else if (rounded < totalPayout) acc.flipMint -= totalPayout - rounded;
totalPayout = rounded;
```

The subtraction cannot underflow: `acc.flipMint` already holds at least this bet's raw `totalPayout`.
The single flush at `:513` then mints a sum of 100-multiples — no rounding is needed at the flush, and
adding one there would make the result depend on the caller's chosen batch (see §4).

### 3d. The adjacent FLIP surface — surveyed, D7 resolved

Every other FLIP payout in the tree, checked for whether a VRF word is already in scope and what it
would cost to get one.

**Already exact multiples of 100 — no work at all.** These pay fixed constants:

| Site | Amount |
|------|--------|
| `BingoModule.sol:202` (`creditFlip(player, flip)`) | `REGULAR_FLIP` 1,000 · `+FIRST_SYMBOL_BONUS_FLIP` 2,000 · `FIRST_QUADRANT_FLIP` 5,000 FLIP |
| `WWXRP.sol:725` (daily draw prize) | `BIG_PRIZE` 100,000 · `SMALL_PRIZE` 10,000 FLIP |

**Parimutuel — OWNER-RULED OUT, left exactly as it is.** Recorded here so the survey stays complete
and the question is not reopened.

`DegenerusParimutuel` is a standalone contract, not a Game module, and **it has no VRF word in scope**.
`claim` (`:317`) and `claimVolume` (`:513`) make **zero** external Game calls today, so a word costs a
fresh cold call (~2,600 gas) on a path that currently has none; `claimRound` (`:411`/`:597`) makes one
`game.growthState(0)` call, but piggybacking a word onto its return means touching `DegenerusGame`
itself, which has ~198 bytes of EIP-170 headroom. A deterministic floor-to-100 was offered as the
no-RNG alternative (every payout is ≥ `STAKE` = 1,000 FLIP, so the haircut is ~1–3% in practice) and
**declined**. The four parimutuel payout sites keep their exact `_payoutFrom` share:

```
payout = STAKE × (overCount + underCount) / winCount        // :718-726
```

**Constant ladders — rounding is the wrong tool.** `volumeBetCredit()` (`:485-491`) steps
25/20/15/10/5 FLIP and `_questReward` (`:738-741`) steps 150/75/37/18 FLIP. Both are sub-100 by
design and already deliberately floored to whole FLIP "so the ladder reads as round numbers". Making
these multiples of 100 is a **re-tune of the constants**, not a rounding mechanism — and it would
change the incentives by up to 4×. Leave them, or re-tune deliberately as a separate decision.

**Out of scope by category — principal, not prize.** These return a player's own staked FLIP; a
±100 FLIP round on someone's principal is a haircut on their money, not a prize that reads nicer:

| Site | What it is |
|------|-----------|
| `Coinflip.sol:533/869/889/928` | the player's own coinflip stake settling out |
| `sDGNRS.sol:906` | escrowed redemption principal + the day's flip multiplier |

Worth noting for the record that `sDGNRS.sol:906` is the one place outside the Game modules with a
**genuinely free VRF word**: `rngWordNext` is already fetched once at `:809` and threaded in as a
parameter of `_claimRedemptionFor` (`:836`), and the single-claim path at `:788` already fetches it
lazily for the lootbox leg. So the gas answer there is "free" — it is excluded on category grounds,
not cost grounds, and can be revisited if the principal-vs-prize call goes the other way.

**Keeper bounties — leave alone.** `Parimutuel.sol:405-409` and `sDGNRS.sol:825-828` price a FLIP
credit against an ETH gas target so the rebate tracks settle cost across the price curve. Rounding a
gas reimbursement to 100 FLIP adds noise to a figure whose whole job is to track a real cost.

---

## 4. Why the entropy source matters (the one real attack surface)

**OWNER-RULED: nothing remotely manipulable — VRF only, and every one of these sites already has a
VRF word in scope.** Verified: `randWord` at `JackpotModule.sol:381` and `:1876`, `rngWordCurrent` in
`FoilPackModule._resolveFoilBuyer`, the committed daily word behind every lootbox/presale box seed,
and `rngWord` in `DegeneretteModule._resolveBet`. No site needs a new entropy source, and none needs
block data, `msg.sender`, timestamps, or any other ambient value.

Stochastic rounding is EV-neutral *only if the player cannot choose which roll applies to which
amount*. Two rules keep that true:

1. **Never round a caller-composed aggregate.** `resolveDegeneretteBets` takes a caller-chosen
   `betIds[]` array, and it is permissionless — anyone may settle anyone's bets. If the rounding ran on
   `acc.flipMint` at the flush (`:513`), a player could enumerate batch partitions off-chain against the
   already-committed VRF word and pick the split that maximises round-ups: a free, repeatable grind
   worth up to ~100 FLIP per bet. Rounding per-bet on a `betId`-keyed word removes the degree of
   freedom entirely — the outcome is fixed at VRF fulfillment regardless of how the bets are batched.
2. **Never round on a word the player can re-roll.** All seven sources are keccak-derived from a
   committed VRF word plus immutable award data (betId, box index, pull index, level). Nothing reads
   mutable storage inside a freeze window, so `v45-vrf-freeze-invariant` holds unchanged.

Both rules are worth writing into the site docstrings, because the natural "simplify it later" refactor
(round once at the flush) silently reintroduces the grind.

---

## 5. Supersedes a recorded decision

`D-279-INLINE-01` explicitly locked the whole-FLIP floor as an **inline** `(x / 1 ether) * 1 ether` at
each site, *no shared helper*. Two unit tests enforce it by **source-text structural proof**, not by
behaviour:

- `test/unit/JackpotNearFutureCoinFloor.test.js`
- `test/unit/LootboxWholeFlipFloor.test.js`

Both extract the function body and regex-match the literal floor expression. They will fail the moment
the expression changes, whichever helper strategy is chosen. Both must be rewritten as part of this
work, and `D-279-INLINE-01` explicitly marked superseded in the freeze notes (otherwise the next audit
pass reads the drift as a regression). If the owner prefers not to supersede it, the fallback is to
inline the primitive at the §3c sites (§8 D2 fallback) — same behaviour, four copies, tests still
need rewriting because the matched text changes either way.

---

## 6. Gates, size, gas

- **`make check-rng-window`** — the manifest is keyed `identifier|function|file|mode`. No new
  VRF-word *storage* access is added, so no manifest row changes **provided no enclosing function is
  renamed or extracted**. Do not refactor `_awardDailyCoinToTraitWinners` / `_settleLootboxRoll` /
  `_resolveBet` boundaries while doing this.
- **`make check-pool-writes`** — FLIP credits/mints are not counted ETH-obligation terms; confirm no
  new row is needed (site 3 touches `_creditClaimable`, which is already classified, and its ETH leg
  is untouched by this change).
- **`check-delegatecall` / `check-raw-selectors`** — **not triggered.** D5 ruled to truncate site 3
  rather than thread a seed, so no signature anywhere changes and neither gate is touched.
- **Storage layout oracle** — no storage change, but per standing note run
  `bash scripts/layout/storage_layout_oracle.sh` at the freeze regardless; it has been red across four
  freezes and is not in `make test-foundry` or any `make check-*`.
- **EIP-170** — none of the three touched modules is `DegenerusGame` (all are delegatecall targets with
  their own budgets), so Game's ~198-byte headroom is untouched *if* the helper lives in a library.
  Measure the three modules with `forge build --sizes` at the **nonzero** `DEPLOY_DAY_BOUNDARY` variant
  before and after — that variant is the binding one.
- **Gas** — sites 1, 4, 5, 6, 7, 8 reuse an existing keccak word: a shift, a mod, a compare, ~15 gas.
  Site 2 adds ≤10 keccaks (~400 gas). Site 3 adds one. Nothing lands on the advance path's hot loop.
- **Untracked `.sol` under `contracts/`** silently joins the Slither run — `git ls-files --others
  --exclude-standard contracts/` before baselining (there is currently an untracked
  `contracts/test/EnsReverseProbe.sol`).

---

## 7. Test and port work

**Rewrite (mandatory, they pin the old text):**
- `test/unit/JackpotNearFutureCoinFloor.test.js`
- `test/unit/LootboxWholeFlipFloor.test.js`

**New:**
- `contracts/test/FlipRoundBernoulliTester.sol` — mirrors the two existing Bernoulli testers; exposes
  `roundFlipToHundreds` so the statistical layer can drive it directly.
- `test/stat/FlipRoundHundredsEv.test.js` — `mean(rounded) ≈ amount` within tolerance across a sweep of
  remainders (0, 1, 37, 50, 99 FLIP) at N=10,000, matching the existing `mean(roundedUp) ≈ frac/100`
  suites.
- Invariant/fuzz, stated against the threshold policy rather than over it. The §3a and §3b sites
  are unconditional: every amount they emit is `≡ 0 (mod 100 ether)`. The four §3c sites are
  conditional, because the threshold is the whole point of §3c:
    - above `FLIP_ROUND_THRESHOLD`: `≡ 0 (mod 100 ether)`;
    - at or below it: `≡ 0 (mod 1 ether)` and **exactly** `floorWholeFlip(raw)` — a raw 950-FLIP
      award pays 950 FLIP, which is deliberately NOT a 100-FLIP multiple.
  A flat "every award is a 100-FLIP multiple" assertion is FALSE and must not be written.
  Cheapest form is an assertion in the existing fuzz handlers on the `creditFlip` /
  `mintForGame` arguments, branched on the threshold.
- **Budget-split exactness (§3a), the new load-bearing property.** Over a fuzzed budget:
  (a) every paid winner receives `>= 100 FLIP` — never zero;
  (b) `sum(paid) == winners * amount <= budget` — the total never overshoots; what goes unminted
      is the `units % winners` leftover plus the sub-100-FLIP dust. NOTE: `sum(paid)` is also
      reduced by every empty `(lvl', trait)` bucket the near-future loop skips, so the
      "exact spend" property holds only when every pull finds a winner;
  (c) `winners == min(budget / 100 ether, MAX_WINNERS)`;
  (d) every paid winner receives the IDENTICAL amount, and the `units % winners` leftover is
      not minted.
  This is a stronger, cheaper-to-test contract than the Bernoulli EV bound it replaces — it is exact
  arithmetic, so it wants unit tests, not an N=10,000 statistical suite.
- Degenerette regression: multi-bet batches where some bets round up and some down, plus a losing
  survival flip, must leave `acc.flipMint` exact and never underflow.
- Anti-grind regression: the same bet resolved alone vs inside a batch yields the identical FLIP
  amount (this is the §4 property, and it is the one that silently breaks under refactor).

**Re-grep before touching tests:** several suites pin call sites by literal source text (the WWXRP
work hit six such files). `grep -rn "1 ether) \* 1 ether" test/` and the event-name greps in §7's
23 matching files.

**Off-chain ports owed** (amounts change, so any golden-value fixture breaks):
- the `../simulator` twin,
- `degenerus-sim/scripts/testnet.ts`,
- the indexer / DB schema (already carrying two known live ABI mismatches from the foil work).

No event signature changes if D6 lands as recommended, so the ports are value-only, not schema.

---

## 8. Owner decisions

| # | Question | Recommendation |
|---|----------|----------------|
| **D1** | "Even 100s" = multiples of **100** FLIP, not 200? | 100 — assumed throughout; say so if you meant 200. |
| **D2** | Stochastic (EV-exact) or plain floor-to-100? | **Stochastic.** Plain floor would burn up to 100 FLIP per award — at the near-future jackpot's ~94 FLIP per winner that is the entire prize. Fallback if a helper is unwanted: same primitive inlined at all 8 sites. |
| ~~**D3**~~ | ~~Coin jackpot: round per-winner or once per draw?~~ | **RULED — neither.** Floor the winner count to `budget / 100 FLIP` so every winner clears 100 FLIP. **Amended 2026-08-06: every winner receives the SAME share and the `units % winners` leftover is not minted** — no extra-unit window, no randomness in the amount. Owner: exact coin-jackpot EV is not a goal; a UI that states one number per draw is. |
| ~~**D4**~~ | ~~A 100 granule is chunky at the small end. Accept, or exempt under a threshold?~~ | **RULED — round only above 1,000 FLIP** (§3c), applied to all four small-award sites (4–7). At or below the threshold, pay the exact amount. |
| ~~**D5**~~ | ~~Golden-ticket flip leg: thread a VRF seed, or plain floor?~~ | **RULED — plain truncate, no RNG** (§3b). The leg is 5–19% of a prize pool, so 100 FLIP is ≤0.8% at any real pool size. Deletes the seed threading, the `payGoldenTicketGrand` param, the `IDegenerusGameModules.sol:71` interface change, the `FoilPackModule.sol:1172` call site, and the `check-delegatecall` / `check-raw-selectors` re-run. |
| **D6** | Add a `roundedUp` flag to the affected events (as `LootBoxOpened` has for tickets)? | **No** — keeps the ABI stable and the indexer/sim ports value-only. Expose the raw pre-round value through the tester contract for EV tests instead. |
| ~~**D7**~~ | ~~Scope: the adjacent FLIP surface — in or out?~~ | **RULED — surveyed in §3d.** Affiliate is **out** entirely (owner), which also removes the degenerette `refFlip` site from the main seven. Bingo and WWXRP prizes are **already** exact multiples of 100 — no work. Parimutuel is **untouched** (see D8). Coinflip claims, the sDGNRS escrow, the constant bet-credit ladders and the keeper bounties are **out** on category grounds. |
| ~~**D8**~~ | ~~Parimutuel: floor `_payoutFrom` to 100, or leave it ragged?~~ | **RULED — leave it as it is.** No parimutuel change of any kind. |

---

## 9. Execution order once D1–D7 are ruled

1. Baseline: `forge build --sizes` (nonzero `DEPLOY_DAY_BOUNDARY`), Slither/Aderyn counts, nSLOC,
   `git ls-files --others --exclude-standard contracts/`.
2. **Sites 1–2 first, and they are independent of everything else** — the §3a unit math needs no
   `FlipRoundLib`, no Bernoulli, and no new entropy beyond the one start-offset draw. Smallest,
   highest-value slice; ships and tests on its own.
3. `FlipRoundLib.sol` + its tester + the EV stat suite — green before any §3b site is touched.
4. Sites 4–5 (lootbox), then 6–8 (degenerette). One commit per module, all batched into a single
   contracts-diff approval per the standing rule.
5. Site 3 — now a one-line truncate inside `_payGoldenTicket`, no interface touch. Any time.
6. Rewrite the two pinned unit tests; add the budget-split exactness, invariant, and anti-grind
   regressions.
7. Full `make test-foundry` + `make test-hardhat` + the six `make check-*` + the layout oracle.
8. Freeze: re-measure sizes, re-baseline Slither/Aderyn, update `STATE.md`, mark `D-279-INLINE-01`
   superseded, note the FLIP emission delta from §2.
9. Port the simulator, `testnet.ts`, and the indexer fixtures.
