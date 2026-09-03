# Known Issues

Pre-disclosure for audit wardens. **If a finding's mechanism + impact is described below, it is
already known and is not eligible.** This is a precise perimeter — each entry names the exact
mechanism and why it is by-design, defended, or out-of-scope. There are no vague blanket disclaimers.

Frozen subject: `contracts/` tree `8b3101b3` @ tag `degenerus-c4a`. Pre-scanned with Slither v0.11.5
+ Aderyn 0.6.8; those findings are triaged in the automated-tools section below.

---

## 1. Design decisions (architectural, not vulnerabilities)

**Daily-advance assumption.** The protocol assumes the daily crank `mineFlip` — which drives
`advanceGame` to completion and pays the keeper bounty — is called each day. An escalating bounty
(≈0.005→0.03 ETH-equiv over ~2h) plus the fact that the advance delivers jackpot payments makes daily
calling economically rational. If skipped for multiple days the next call backfills gap days, **capped
at 120 iterations** for gas safety; gap days beyond 120 are skipped. A coinflip stake placed on a
skipped day never resolves — `_unlockRng` advances `dailyIdx` straight to the current day, so
`processCoinflipPayouts` is never called for that day and the stake stays permanently unclaimable. The
staked FLIP was already burned at deposit (as every coinflip stake is), so the loss is confined to the
affected bettor and never touches stETH solvency. Reaching >120 skipped days requires >120 consecutive
days with nobody calling `mineFlip` at all — a total abandonment under which FLIP is already valueless.

**Non-VRF entropy for the affiliate winner roll.** Deterministic seed (gas optimization). Worst case:
a player times purchases to direct affiliate credit to a different affiliate. No protocol value is
extracted. (Slither `arbitrary-send` family / event-only.)

**VRF-coordinator + price-feed swap governance.** Emergency rotation is sDGNRS-governed behind a
death-clock: a VRF-swap proposal cannot be created until VRF has stalled `ADMIN_STALL_THRESHOLD =
44 hours` (vault-owner path) / `COMMUNITY_STALL_THRESHOLD = 7 days` (0.5%-sDGNRS community path); the vote threshold decays 50%→5%
over a 168h lifetime and requires approve-weight > reject-weight. A proposal is auto-killed the
moment VRF recovers or a word is fulfilled after creation (see SECURITY.md role 1, "kill-on-recovery"). Feed swap
requires the feed unhealthy 2d (admin) / 7d (community); a down feed only suspends LINK→FLIP donation
credit (LINK donations still process). This is the intended trust model (see SECURITY.md).
The daily VRF request itself is a HARD HALT by policy: `_requestVrfWord` (advance module) reverts
the crank when the coordinator refuses the request (subscription unfunded, coordinator
misconfigured), so the game stops at the day boundary until VRF funding/config is fixed or the
rotation above lands — it never proceeds on a missing word. The mid-day lootbox request is the
fail-soft twin (`_tryRequestRng`, try/catch).

**Growth-parimutuel scoring is claim-time-derived, and betting ignores the RNG lock.**
`DegenerusParimutuel` stores no settlement result: every claim re-derives its round's outcome
from three write-once ratchet entries — century levels are served from the append-only
achieved-pool history (`centuryPrizePools`), so the `_endPhase` restart-base overwrite of
`levelPrizePool[x00]` never distorts a settled round — with `ratchet(round+1) == 0` as the
unsettled predicate. Betting stays open through the daily RNG window by design: the market
consumes no randomness and no write a bet performs reaches VRF-consumed state (the quest credit
books to calendar-day+1; the one lock-sensitive path — topping a stake up from unclaimed
coinflip winnings — stays gated inside FLIP, so a mid-window bet must be wallet-funded). An
exact growth tie resolves UNDER (OVER must clear the line strictly). One fixed 1,000-FLIP bet
per address per round; backing both sides is EV-0 in a pooled book, not an exploit. Positions
unclaimed at game over tombstone with FLIP itself — there is no unwind path, by design.

**Lido stETH dependency.** Protocol revenue depends on staking yield, not the prize pool: yield surplus
above all pool obligations is split four ways (vault / sDGNRS / charity / buffer). The prize pool itself
is player buy-ins, and game RTP is player-relative — neither is yield-funded. If yield→0 that revenue
disappears but the protocol stays solvent (the solvency invariant `balance >= claimablePool` does not
depend on yield). Negative rebases are absorbed by an 8% buffer.

---

## 2. Accepted issues & scope boundaries

**Presale over-credit is WONTFIX (bounded).** PRESALE-01 can over-credit, but the amount is bounded,
presale-only, and the presale itself is 50-ETH-capped. Accepted.

**Degenerette recirc EV-cap allocation is resolve-order-dependent — accepted.** Degenerette ETH-spin
recirculated boxes draw the per-account per-level 10 ETH lootbox EV cap at resolve time
(`resolveLootboxDirect` → `_applyEvMultiplierWithCap`), and `resolveDegeneretteBets` is permissionless
with caller-selected `betIds` order. A player holding multiple unresolved wins whose bet-time-frozen
activity scores differ can therefore choose (by ordering, by deferring resolution across a level
boundary, or by leaving low-multiplier outcomes unresolved) which frozen multiplier (90–145%) consumes
the cap — worst-case ≈ 10 ETH × (145% − 100%) ≈ 4.5 ETH of reward basis. Accepted because the cap's
bound holds under **every** ordering: the bonus subsidy can never exceed 10 ETH × 45% = 4.5 ETH per
account per level, which a single max-score box reaches with no ordering game at all. No cross-player
or pool exposure beyond that budgeted subsidy; a third party choosing a pessimal order for someone
else is unprofitable grief; and selective non-resolution is self-defeating — resolution is
permissionless and keeper transactions settle outstanding bets regardless. Only re-orderings that
break the 4.5 ETH per-account-per-level bonus bound are eligible findings.

**A lone sub-`2^shift` ticket balance on a thanos level rounds to nothing — bounded, accepted.**
The drain divides an accumulated `(player, level)` entry balance by `2^shift` exactly once, over
`owed * 100 + rem` scaled units (`_snapOwedPacked`). A balance below `2^shift` scaled units therefore
truncates to zero, and the probabilistic remainder settle cannot recover it because `rem == 0` always
loses the roll. `_callTicketPurchase` fails such a purchase closed, but only below
`SNAP_CHECK_MAX_UNITS` (16 scaled units = 0.04 tickets): reading the exponent costs a cold SLOAD of a
slot no purchase otherwise touches, so every buy at or above that gate skips the check. A buy of `q`
scaled units with `16 <= q < 2^shift`, which is the buyer's whole balance at that level, is accepted
and pays full price for zero entries.

Reachable only at `shift >= 5` (a smaller exponent cannot zero 16 units) and only where
`TICKET_MIN_BUYIN_WEI` admits such a `q` — it floors a legal buy at `ceil(1e18 / priceWei)` scaled
units, so 100 units at the 0.01 ETH intro price and 5 at the 0.24 ETH century price. The loss is
bounded by the buy itself: at most `2^shift - 1` scaled units, under 0.64 tickets even at the
maximum exponent of 8, so **≈ 0.153 ETH worst case per (player, level)** at the highest ticket price.
Any player already holding entries at that level is unaffected, because the divide is applied to the
accumulated balance, not per purchase.

Accepted rather than fixed: closing it means an exponent read on every ticket purchase, for a case
that needs a shift of 5 or more — itself undeclarable until projected demand reaches 40M entries at
the target level — *and* a lone sub-`2^shift` position. Findings that break the bound above (a loss
larger than the buy, a player with an accumulated balance losing it, or truncation at `shift < 5`)
are eligible; the bounded case described here is not.

**Genesis admin self-break is a NON-finding.** An admin (or anyone) breaking their *own* game at
genesis, when `sDGNRS.votingSupply() == 0` (no engaged community yet), is not a vulnerability — there
is no victim. An admin-power finding must exhibit an **engaged-community victim**: a snapshot with
`votingSupply > 0`. Genesis-only griefs are out of scope.

---

## 3. Accepted out-of-scope risk: the > 120-day VRF-death deadman fallback (do NOT submit)

**Mechanism.** When the game has not sealed a day for more than 120 days
(`_vrfDeadmanFired ≡ _simulatedDayIndex() − dailyIdx > 120`, `DegenerusGameStorage.sol:2088-2089`;
`dailyIdx` is uint24 and always `<= _simulatedDayIndex()` so no underflow), the terminal release no
longer waits for Chainlink. `_getHistoricalRngFallback` (`DegenerusGameAdvanceModule.sol:1988-1999`)
commits a fallback word from sealed historical `rngWordByDay` admixed with `block.prevrandao`; the
`reverseFlip` nudge is cancelled-and-consumed (`unchecked fallbackWord -= totalFlipReversals`,
`:1862`, against the consumption in `_applyDailyRng :2640-2651`).

**Why a block proposer's 1-bit `prevrandao` grind over the terminal distribution is accepted:** this
path is reachable **only** after a catastrophic, unrecovered Chainlink VRF death — VRF itself dead
**and** both the 44h-gated (vault-owner) and the week-gated (community) governance coordinator-swap
paths having failed to land a replacement for **> 120 days**. At that point the only alternatives are (1) brick the contract forever with funds trapped, or
(2) release funds under a slightly-grindable-but-VRF-derived terminal word. The owner ruling is that fund-recovery beats a permanent brick. The deadman only removes a delay that would
otherwise have elapsed anyway; it adds no new advance-chain composition and steers nothing on a live
chain. RNG steering on a *live* Chainlink coordinator remains fully in scope — this exclusion is the
dead-coordinator terminal fallback only.

---

## 4. Out-of-scope & immaterial items

**423 VRF rotation-timer governance-malice — out of scope.** A malicious sDGNRS-governance majority
abusing the coordinator-swap path is out of scope per the trust model (governance malice requires the
engaged community to vote against its own interest, and is bounded by the 44h death-clock + decaying
threshold). The rotation backstop is non-resettable on the 120/365-day horizon. See SECURITY.md role 1.

**Affiliate floor-of-sum rounding — immaterial.** The combined `payAffiliateCombined` roll uses a
floor-of-sum instead of a sum-of-floors, but the divergence is at most ~3 FLIP of quest-rounding per
transaction (a coin credit, not ETH-backed value). Immaterial; documented, not eligible.

---

## 5. Automated tool findings (pre-disclosed)

The full machine-readable Slither/Aderyn baseline is maintained internally — Slither 0.11.5 (4,103
results / 101 detectors over 179 contracts at tree `8b3101b3`; 186 High / 526 Medium / 528 Low /
2,809 Informational / 54 Optimization, and the "High" tier is dominated by 142 `uninitialized-state`
false positives from the shared-storage delegatecall architecture — the deployed-module compilation
units plus the `DegenerusGameLens` unit, see below) + Aderyn 0.6.8 (10 High / 22 Low; the one new
High is the same Yul shift-order reading Slither's new class records, below).
Slither totals are sensitive to the scan environment (solc/toolchain resolution), so the absolute
count is not comparable across machines — re-runs should compare category triage, not the total.
These counts were measured directly at tree `8b3101b3`, not carried forward from an earlier scan.
The immediately preceding freeze tree `d5e87795` (the prior `degenerus-c4a`) re-scanned in the same
environment reproduced 3,968 / 177 High / 516 Medium / 515 Low / 2,708 Informational / 52
Optimization exactly, tier for tier — the figure recorded for it at that freeze — so the delta
across this span is a measurement rather than an assumption.

That delta is **+135 results and +9 High** across the fourteen-commit span: the trait-bucket lane
packing (eight 32-bit owner positions per slot over a per-level owner registry), the seated
round drain with its persisted frontier, the unit-priced write budget, the split of the
jackpot-phase daily's carryover ticket leg into its own advance stage, the craps protocol awards
paying half in day passes with the 19:1 normal-to-high conversion, the coin jackpot's comp
quadrant and the vault's lifetime comp allowance, the zero-to-seven chip continuum with the fixed
5x schedule, the window arm binding the live index, the presale closing-box remainder, the whale
bulk bonus with per-pass boxes and the deity seat doubling, the genesis perpetual tickets as one
range call, and the post-council fixes. The contract count moves 177 -> 179.

Eight of the nine new Highs are `uninitialized-state` at 134 -> 142, the standing false-positive
class, keyed by (variable, reader): `lvlTraitEntry` read through the new `_bucketOwnerAt` decoder
and `_computeBucketCounts`, `lvlEntryOwner` at `_registerEntryOwner`, `phaseTransitionActive` at
`payCarryoverTickets`, `dailyTicketBudgetsPacked` and `dailyJackpotCoinTicketsPending` at
`_carryoverLegPending`, and `presaleCloser` at `openHumanBoxes` — every one a storage field the
router writes, read from a module's isolated compilation unit — net of five entries whose readers
were replaced by the lane decoder. The ninth is a **new detector class, `incorrect-shift` (1)**:
`_bucketAppendRun`'s Yul `shl(shl(5, occurrences), 1)`. Yul's `shl` takes the shift count FIRST;
the detector reads the Solidity operand order and reports the arguments swapped. The expression is
`1 << (32 * occurrences)`, the mask for the leading lanes of a fresh word, and
`test/fuzz/BucketLanePacking.t.sol` pins every lane of it. Aderyn's one new High ("Incorrect
Assembly Shift Parameter Order") is the same line. `weak-prng` is unchanged at 20 and every other
High detector class is composition-identical (arbitrary-send-eth 6, delegatecall-loop 4,
encode-packed-collision 2, incorrect-exp 2, reentrancy-balance 6, reentrancy-eth 3).

The Medium (+10), Low (+13), Informational (+101) and Optimization (+2) net movement is fully
attributed, keyed line-insensitively on (check, impact, subject): `unused-state` +85 net, all in
`DegenerusGameStorage` — the unit-pricing constants (`UNIT_GAS_BOUND`, the round / split / join
charges), the lane and owner-position masks and the pass-value figures, declarative constants of
the same kind the earlier freezes recorded; `reentrancy-events` +7 and `reentrancy-no-eth` +3 on
the craps pass-lane credits and the drain's nested delegatecall into the round engine;
`timestamp` +7 on the craps day-lane clock gates; `uninitialized-local` +8, the memory seats of
`_runRound` / `_runQuadrant` / `_drainSeatedSurvivors` and the comp quadrant's pull table, each
written before read; `assembly` +6 (the lane packer, decoder and seed helpers); `cyclomatic-complexity`
+3 and `costly-loop` +3 on the reshaped drain entrypoints; `low-level-calls` +3 (the nested
round-engine delegatecall and the vault comp credit); `constable-states` +2; `unused-return` +1
(the vault comp credit's saturation return, consumed by the jackpot caller only); `too-many-digits`
+1 (the lane replication constant); `calls-loop` −1 and `incorrect-equality` −2 on code the span
replaced. Every new finding names the ticket engine, the craps pass lanes, the whale or presale
code the span actually touched; nothing else moved.

The paragraphs below record the accumulated attribution of the standing false-positive classes
across the earlier freeze chain, and remain accurate as history.

At the preceding freeze, the delta `09413eb0` -> `d5e87795` was **+59 results and +1 High** across
the eleven-commit craps span (the Dice Run high-water redesign, the progressive's window-class
schedule, the craps bankroll-payout boons, the protocol-wallet pass bank, the fifth (dice-run)
record category, the ticket-volume market's excision); the one net High a `weak-prng` three-for-two
swap (three `CrapsBattle` schedule/arithmetic modulos in, the two deleted volume-market clock gates
out), `uninitialized-state` unchanged at 134, no new detector class.

At the preceding freeze, the delta `41f04be2` -> `09413eb0` was **+212 results and +5 High**, effectively the whole of it the addition of the Craps
table — `CrapsBattle` plus its `Craps` / `LootboxCraps` bases, new to the audited scope at that freeze
(deploy set 29 → 30, appended last so no predicted address moved) — net of a refactor of the daily
advance. The contract count moves 163 → 178 for the craps compilation units.

The five new High are **all `weak-prng`**: `uninitialized-state` is unchanged at 134, and every
other High detector class is composition-identical (arbitrary-send-eth 6, delegatecall-loop 4,
encode-packed-collision 2, incorrect-exp 2, reentrancy-balance 6, reentrancy-eth 3). `weak-prng`
moves 14 → 19 — **+7** in `CrapsBattle`, the table's seven keccak draws (board scatter, tie-break,
boost rung, daily high-roller size, progressive cutoff, survival coin, award-rounding roll), each
the same benign class as `requestLootboxRng` where the entropy is the committed VRF word and the
keccak is only an extractor; and **−2** as the advance refactor (−345 nSLOC on
`DegenerusGameAdvanceModule`) retired two of its own. No new detector class entered the High tier.

The Medium (+63), Low (+77) and Informational (+67) additions are the ordinary footprint of three
new contracts, keyed line-insensitively on (check, impact, subject function): `reentrancy-events` /
`-no-eth` / `-benign` on the craps external credit-and-burn calls and the re-keyed `advanceGame`
body, `timestamp` on the table's clock gates, `calls-loop` on `_payout` / `_extsload` /
`_deliverPasses`, `unused-state` on the new `DegenerusGameStorage` craps constants
(`HIGH_ROLLER_DAY_PASS_VALUE`, `MINER_BOUNTY_CRAPS_KEEP`, and the pass-value siblings), and
`divide-before-multiply` / `incorrect-equality` on the craps preset and progressive math. Every
new finding names craps code or the refactored advance/lootbox path; nothing else moved.


Across the wider chain from `33ccd5b9`, the High tier gained no new detector class and one retired
entirely. A single finding was added —
`delegatecall-loop` on the new `_rollSingleBoxBoons` — and eight clear: the two `delegatecall-loop`
entries on the `_resolveLootboxCommon` / `_rollLootboxBoons` pair that one roll replaces, one of the
three `encode-packed-collision` entries on `AFKingSubscriptionToken._renderSvgInternal` (the badge
inversion collapsed one SVG concatenation), the lone `shadowing-state` — the duplicate
`JACKPOT_LEVEL_CAP` constant in the mint module is gone, so that standing triage entry retires with
it — and four `uninitialized-state` shared-storage false positives (`boxPlayers`,
`jackpotPhaseFlag`, `lootboxEth`, `rngLockedFlag`), each of which gained a writer inside the unit
that reads it. The contract count moves 156 -> 163 for the six test-only `tokenURI` renderer probes
(`out_of_scope.txt`) and the new `IFoilWwxrp` interface.

The +285 is dominated by one Informational detector: `unused-state` at **+251** (+360 / −109), the
same shared-storage delegatecall artifact as the High tier and equally not a defect. The packed box
order adds roughly nineteen members to `DegenerusGameStorage` — the thirteen `LB_*` packing
constants, `lootboxOrder`, `MAX_BOXES_PER_ORDER`, the three `MINER_BOUNTY_*` sizes and the
`OPEN_HUMAN_*` weights — and each is reported once per compilation unit that inherits the storage
without touching it, fourteen units in all; the 109 that cleared are the members the same rework
retired. The remaining movement is small and attributable: `reentrancy-events` +20 and `calls-loop`
+6 from the self-describing event surface; `divide-before-multiply` **−17**, because the retired
`_boonPoolStats` carried eighteen of them and the replacement `_rollTier` carries one;
`reentrancy-no-eth` +5 across `beginBoxOrder`, the two pass purchases that now bind an affiliate
code, and the funded-subscribe logging; `uninitialized-local` +4 net as the old `lb*` locals in
`_purchaseForWithCached` gave way to packed-order locals of the same deliberate default-zero kind;
`missing-inheritance` +6, exactly the six renderer probes; and `unused-return` +2 on
`purchaseDeityPass` and on `DegenerusVault.burnCoin`, which now discards the `vaultMintTo` result.

The delta against the tree tagged before this chain began (`4e616db4`, whose retained scan
re-counts to 3,143 results / 156 High) is **+554 results and +15 High**. That span is the
twelve-commit chain enumerated above plus every change below: the `extsload`
observability lens, the module observability
events, the foil daily quest moving to the final-jackpot RNG request, the static boon tables, the
council-review fixes, the seat push-mint, the dead-code removal, the size-scaled lootbox WWXRP
stake, the coinflip claimable-preview fix, the vault share-token ENS reverse names, the solo-quadrant
drop from the main-board ticket draw, the foil-pack spend-waterfall refactor, the award-rounding
granules, the deploy-time level-1 quest seed (which contributes zero findings in every tier), the
purchase-phase insurance skim, the ENS reverse probe, the unified all-time record pool (which
retired the coinflip bounty ladder), the x9 snapshot behind the daily top-bettor board gate, the x0
full-last-purchase-day pacing, the deploy-day daily-quest seed, and the WWXRP Degenerette rig band
(which likewise contributes zero findings in every tier). Keyed line-insensitively on
(check, impact, subject function), every addition is attributable:

- **The unified all-time record pool (+2 Medium, +8 Low, +10 Informational, ZERO High), against
  which the retired bounty ladder gives back 9.** Four records now share one FLIP pot, so three
  purchase-side paths gained an external `armRecord` call and `_endPhase` gained `fundRecordPool`:
  that is the whole reentrancy family here — `reentrancy-no-eth` ×4 and `reentrancy-benign` ×3 plus
  `reentrancy-events` ×5 across `_armBigRecord`, `_placeDegeneretteBet(Core)`,
  `_purchaseForWithCached` and `_endPhase`. Every callee is a protocol contract reached as the
  final statement of its branch, and the claim it may pay is credit-only (`_addDailyFlip`), never a
  transfer. The rest are shape, not behaviour: `costly-loop` ×10 and `calls-loop` ×2 on the record
  helpers (the "loop" is the four-category `if` ladder in `_stampRecordDay` / `_armBigRecord`, not
  an unbounded iteration), `events-maths` on `fundRecordPool`, one `low-level-calls` on the
  `_armBuyRecord` self-call, a `timestamp` taint artifact on `_endPhase`, `unused-state` on a
  `PRICE_COIN_UNIT` whose notional conversion moved to the funding site, and `uninitialized-local`
  on the deliberate default-zero `paid` / `sdgnrsPaid`. Removing the bounty ladder cleared nine in
  the same tiers (`processCoinflipPayouts` reentrancy ×5, its two locals,
  `_coinflipLockedDuringTransition` and `payCoinflipBountyDgnrs` unused-return) plus three on the
  restructured `_addDailyFlip`.
- **The board gate, the x0 pacing and the quest seed (+3 Medium, −1 Medium, ZERO High).** The x9
  snapshot adds `uninitialized-local` on `_depositCoinflip.trackTop` (default false is the answer
  for a non-qualifying deposit) and `unused-return` on `_depositTracksTop` discarding the
  `purchaseInfo` tuple members it does not read. The quest seed adds `uninitialized-local` on the
  constructor's `seeded` array, populated field-by-field through `_seedQuestType`. The x0 pacing
  **removes** one: its mid-day swap guard initialises `lastSwapAhead` at its declaration, clearing
  the `uninitialized-local` the old declare-then-assign form carried.

- **The purchase-phase insurance skim (+2 Medium, ZERO High) and the `EnsReverseProbe` harness
  (+1 Medium, +1 Informational, ZERO High).** The skim routes 2% of the daily 1% `futurePrizePool`
  drip to `yieldAccumulator`, splitting the slice 75 ticket / 23 ETH / 2 insurance. Its two Mediums
  are both standing classes: one `divide-before-multiply` (the function already carried one for the
  same `futureBal / 100` budget carve — the detector now sees a second `× bps / 10_000` chain off
  that quotient) and one `uninitialized-local` on `insuranceCut`, the exact sibling of the
  already-triaged `ticketLegBudget` in the same function, both declared then assigned inside the
  same `if (ethPool != 0)` guard where the zero default is the intended value. The move is
  obligation-neutral — `futurePrizePool` and `yieldAccumulator` are both counted in the yield-surplus
  obligation set, so no surplus is freed. The probe contributes one `low-level-calls` Informational,
  matching the established per-constructor ENS pattern, and one `uninitialized-local` on its `ok`
  flag, deliberately false when no registrar is configured. The probe is listed in `out_of_scope.txt`
  with the other in-tree harnesses and is not deployed.

- **The new `DegenerusGameLens` compilation unit (~160 of the additions).** The lens imports
  `DegenerusGameMintStreakUtils`, which pulls `DegenerusGameStorage` into its compilation unit, so
  the long-triaged shared-storage class fires through a second compilation path: **+13 High**
  `uninitialized-state` (the same false-positive family, 118 → 131 — the fields are written by the
  deployed modules exactly as the standing triage describes), ~130 Informational `unused-state` on
  storage fields the lens unit never touches, Informational `assembly` on its `extsload` word
  decoders, and one `missing-inheritance`. No new code defect is involved. One `unused-return`
  Medium covers the viewer deliberately discarding two data-source flags it no longer needs for
  selection.
- **The award-rounding granules (+4 Medium, −3, ZERO High) and the foil spend waterfall (+1 High,
  +1 Medium, +1 Low).** The award-rounding span adds four `divide-before-multiply` Mediums — on
  `FlipRoundLib.roundFlipToHundreds`, `FlipRoundLib.floorWholeFlip`,
  `DegenerusGameJackpotModule._payGoldenTicket` and `_distributeTicketJackpot`. Each is the
  deliberate `(x / granule) * granule` truncation that produces the round award figure, the same
  benign pattern already triaged on the Coinflip take-profit partition; the floor is the feature.
  Three findings went away in the same span: the two `divide-before-multiply` Mediums on
  `_resolvePresaleBox` / `_settleLootboxRoll` did not disappear but MOVED into `FlipRoundLib` when
  the inline whole-FLIP floor became a library call, and `uninitialized-local` on
  `_distributeTicketsToBuckets.globalIdx` went with the deleted remainder-window cursor. **The
  award-rounding work contributes no High.** The one new High in this span is
  `uninitialized-state` on `DegenerusGameStorage.presaleOver` (131 → 132) from the foil-pack spend
  waterfall — the same shared-storage delegatecall false-positive family described above; the field
  is written by the deployed modules, and it flipped out of the `unused-state` Informational tier
  precisely because the waterfall now reads it.

- **The foil-quest request-side roll (+2 High, plus a few Medium/Low).** The High pair is
  `weak-prng` on the pre-existing `lvl % 10` / `lvl % 100` decimator-window arithmetic (12 → 14),
  newly flagged only because its result now flows into the `rollDailyQuest` external call; these
  are level-index gates, nothing random is drawn from them — the same benign class as
  `requestLootboxRng`'s time-of-day gate. The rest are `incorrect-equality` on the intended
  exact-day gate and mod comparisons, one `uninitialized-local` on the deliberate default-false
  `finalJackpotRequest`, and one `timestamp` taint artifact.
- **The static boon tables REMOVED findings.** Deleting the eligibility locals cleared two
  `uninitialized-local` Mediums (`deityEligible`, `deityPassCount`), and dropping the now-dead
  `_isDecimatorWindow()` helper cleared one High `uninitialized-state` on `decWindowOpen`
  (132 → 131), which downgraded to an Informational `unused-state` in that unit.
- **The seat push-mint (+10, ZERO High, nothing removed).** `_grantSeatCoin` now calls the seat
  token, so the three pass-purchase entrypoints carry an external call: **+4 Medium**
  `reentrancy-no-eth` and **+4 Low** `reentrancy-events` across `purchaseDeityPass` (×2 each, one
  per `_grantSeatCoin` leg), `purchaseLazyPass`, and `purchaseWhalePass`. The callee is
  `AFKING_SUB_TOKEN`, a protocol contract whose mint writes storage and emits `Transfer` with no
  ERC-721 receiver callback, so it cannot re-enter; each call site is also the final statement of
  its function. The remaining two are Informational on the token itself: `costly-loop` on
  `_mintSeat` (reached from the vault tranche's bounded mint loop) and `missing-inheritance`
  (it implements the ERC-721 surface without declaring an interface, as it always has).
- **The dead-code removal (−3, nothing added, ZERO High).** Deleting three unreachable
  `DegenerusGameStorage` helpers cleared exactly their three Informational `dead-code` findings
  (`_setNextPrizePool`, `_unpackWholeFlipToWei`, `_foilSnapShiftFor`). Removing the unreachable
  `DegenerusQuests.handleMint` and the always-zero `DegenerusGameLens.snapExponent` field moved no
  finding, because neither carried one.
- **The size-scaled lootbox WWXRP stake (ZERO, in every tier).** Replacing the two flat WWXRP
  constants with the `_boxWwxrpStake` helper — a `private pure` multiply-and-floor consumed by the
  box spin and the cold-bust consolation — added, removed and re-keyed nothing: the scan totals and
  the full High-tier composition are identical to the prior tree, detector for detector.
- **The coinflip claimable-preview fix (+2, ZERO High, nothing removed).** `_viewClaimableCoin` now
  replays the settle's auto-rebuy accounting instead of scoring each winning day independently, so
  the two preview views cannot disagree with the claim that follows them. Both additions land on
  that one function: **+1 Medium** `divide-before-multiply` on `(payout / takeProfit) * takeProfit`
  and **+1 Informational** `cyclomatic-complexity`. The floor-then-multiply is the take-profit
  semantic itself — bank whole chunks, roll the remainder — copied from the settle path
  (`_claimCoinflipsInternal`), which already carries the identical finding; the partition is exact
  by construction and fuzz-pinned (`reserved + remainder == payout` at every take-profit size).
  The added branching is the point of the change.
- **The vault share-token ENS reverse names (+2, ZERO High, nothing removed).**
  `DegenerusVaultShare`'s constructor now makes the same best-effort `setName` call as every other
  deployed contract (the name arrives as a constructor argument, so one source site covers both the
  DGVF and DGVE instances). Both additions are Informational on that constructor: one
  `low-level-calls` (the sixteenth entry in the standing ENS triage below) and one
  `redundant-statements` on the `ok;` result discard — the exact per-constructor pair every other
  ENS call site already carries. Constructor-only code; no runtime bytecode moved.

The High tier at this tree is 134 `uninitialized-state`, 14 `weak-prng`, 6 `arbitrary-send-eth`,
6 `reentrancy-balance`, 4 `delegatecall-loop`, 3 `reentrancy-eth`, 2 `encode-packed-collision` and
2 `incorrect-exp`. Every check either held or fell against the prior tagged tree; nothing rose, and
the `shadowing-state` entry that stood for many milestones is gone with the duplicate constant that
caused it. The 14 `weak-prng` include the two
`DegenerusParimutuel` entries (`_openVolumeRound()` and `volumeBetCredit()`, each reading
`block.timestamp % 86400` to decide whether the day's betting window is open) — a time-of-day gate,
not a source of randomness: nothing is drawn from it, and the same benign pattern is already
triaged for `requestLootboxRng` and `_bountyEligible`.
CI re-runs both
analyzers on every push (`.github/workflows/ci.yml`); the standing per-category triage — why each is
by-design, defended, or not-applicable — is below.

**Arbitrary-send-eth.** `_payoutWithStethFallback` / `_payoutWithEthFallback` / `_payEth` send ETH via
`.call{value:}` to `msg.sender` or player addresses read from game state — all access-controlled.

**incorrect-exp (High ×2) — both false positives.** One is in `node_modules/@openzeppelin` (out of
scope). The other, `otherSlot = slot ^ 1` in `DegenerusQuests._questCompleteWithPair`, is a deliberate
XOR toggle between the two quest slots (0↔1), not a mistyped `**`.

**locked-ether (Medium ×2).** The flagged contracts are the `DegenerusGameBoonModule` `delegatecall`
module plus a test mock. A module never holds ETH: it executes in `DegenerusGame`'s context, so
`payable` entrypoints there are the *game's* payable surface and the game has the withdrawal paths.

**low-level-calls (Informational ×17) — ENS self-naming.** Seventeen constructor call sites — the
sixteen standalone deployed contracts plus one parameterized site in the vault's share-class token
(compiled once, deployed twice as DGVF/DGVE) — make one best-effort `setName(string)` call to
`ContractAddresses.ENS_REVERSE_REGISTRAR` (`address(0)` in this subject, so unreachable here). The
return value is intentionally discarded so a missing or hostile registrar can never revert a
deployment; each site carries a raw-selector justification comment. Zero authority,
constructor-only — see SECURITY.md role 5. Aderyn additionally reports the discard as a "Redundant
Statement" Low (the `ok;` no-op that silences the unused-variable warning).

**events-maths.** `resolveRedemptionLootbox` decrements `claimablePool` without a dedicated event;
higher-level redemption events capture the context (the variable is a running tally, not a balance).

**Unused import (Aderyn Low ×3) — the one Aderyn category this subject added.** The packed-box-order
rework left three `import` statements with no remaining reference: `IDegenerusQuests` and
`BitPackingLib` in `DegenerusGameLootboxModule.sol`, and `PriceLookupLib` in
`DegenerusGameStorage.sol`. Solidity emits no code for an unused import, so no deployed bytecode is
affected and no behaviour can depend on them; they are catalogued here rather than edited on the
frozen tree.

**encode-packed-collision.** `AFKingSubscriptionToken._renderSvgInternal` concatenates SVG fragments
with `abi.encodePacked(string, ...)`; the bytes render a tokenURI image and are never hashed for
identity, keys, or authorization.

**erc20-interface.** `DegenerusVault`'s local `IAFKingSubscriptionToken.transferFrom` declares the
seat token's ERC-721 transfer (three args, no bool return); the detector pattern-matches the ERC-20
function name. The target is an ERC-721 — there is no ERC-20 interface to mismatch.

**Centralization `[M-2]`.** Critical admin functions (VRF/feed swap) require sDGNRS governance; the
remaining `onlyOwner` functions are operational (staking) or deity-pass metadata. Admin cannot drain
game funds — ETH flows are contract-controlled.

**Chainlink feed `[M-3]`.** LINK/ETH feed values LINK donations only; swap is governance-gated; a
stale/down feed suspends FLIP donation credit but processes the donation.

**No SafeERC20 `[M-5]/[M-6]/[L-19]`.** `.transfer()`/`.transferFrom()` with return-value checks; only
known tokens (stETH, FLIP, LINK, wXRP) that return bool per standard are touched. SafeERC20 adds
~2,600 gas/call for no benefit here.

**abi.encodePacked `[L-4]`.** 35 instances; entropy inputs are fixed-width (uint256/address) — no
collision; SVG string results are not used as keys.

**Division-by-zero `[L-7]`.** 27 instances; all divisors have implicit guards (non-zero BPS, supply
checks revert on zero, level-derived non-zero during active game).

**External-call gas `[L-9]`.** 11 `.call{value:}("")` forward all gas; recipients are player addresses
(self-grief only) or known protocol contracts with minimal `receive()`. CEI followed.

**Burn / zero-address `[L-12]`.** 67 instances; FLIP/sDGNRS/GNRUS burn mechanics are intentional;
internal paths use `msg.sender` / contract-to-contract addresses.

**Unchecked downcasting `[L-18]`.** 50 instances; each preceded by range validation or mathematically
guaranteed to fit (BPS < 10,000 → uint16, timestamps < 2^48 → uint48).

**Missing address(0) `[NC-2]`.** The two renderer setters (DeityPass, AFKing subscription token) are
admin-only, and the VRF coordinator swap is governance-gated with its own liveness checks. None
loses funds if zero.

**Magic numbers / event indexing / old+new values / long functions / setter validation / unchecked
arithmetic** (`[NC-6]`,`[NC-10]`,`[NC-11]`,`[NC-13]`,`[NC-16]`,`[NC-17]`,`[GAS-7]`): documented
conventions — named constants where readability matters, indexes on filter-key fields only, new-value
events for infrequent admin ops, NatSpec-bannered long game functions, governance-checked critical
setters, strategic unchecked blocks within the proven < 16.7M ceiling.

---

## 6. ERC-20 deviations

FLIP and DGNRS are ERC-20 with intentional deviations. **sDGNRS and GNRUS are soulbound (not ERC-20)
— filing ERC-20-compliance issues against them is invalid.**

**DGNRS blocks transfer to its own contract address.** `_transfer` reverts `Unauthorized()` when
`to == address(this)` — DGNRS held by the contract is indistinguishable from the sDGNRS-backed
reserve. Prevents accidental lockup. EIP-20 does not restrict recipients; intentional.

**The game bypasses FLIP `transferFrom` allowance.** `DegenerusGame` (a compile-time immutable
constant) can `transferFrom` without prior approval — the trusted-contract pattern enabling
no-pre-approval gameplay. All other callers require standard allowance.

**FLIP transfer/transferFrom may auto-claim pending coinflip winnings.** Before a transfer with
insufficient balance, the sender's pending coinflip FLIP is auto-claimed from the trusted (immutable)
Coinflip contract, minting before the transfer. Non-standard but intentional UX; the Coinflip contract
is immutable and trusted.

**FLIP sent to VAULT or sDGNRS is burned, not transferred.** `_transfer` special-cases both. `to ==
VAULT` de-circulates the tokens (totalSupply reduced) into the vault's virtual mint allowance
(`balanceOf[VAULT]` stays 0; the reserve lives in `_supply.vaultAllowance`). `to == SDGNRS` de-circulates
them into sDGNRS's redemption backing (`coinflip.creditSdgnrsBacking`). Both reduce totalSupply and emit
`Transfer(from, address(0))`. Intentional virtual-reserve architecture.

**FLIP *minted* to VAULT or sDGNRS never enters `totalSupply` either.** `_mint` mirrors the same two
intercepts: a mint to VAULT lands in `vaultAllowance`, and a mint to SDGNRS (e.g. a box-spin FLIP win on
sDGNRS's own self-subscription) routes straight to `coinflip.creditSdgnrsBacking` with **zero** supply
mutation — nothing was circulating, so nothing is de-circulated, and no `Transfer` event is emitted for
that leg. Consequence: neither address can ever hold a `balanceOf` FLIP balance, by construction on both
the transfer and the mint side. `totalSupply + vaultAllowance = supplyIncUncirculated` still holds.

**sDGNRS's FLIP backing is staked, not held.** `creditSdgnrsBacking` places incoming FLIP on the *next*
day's coinflip stake (day-keyed like every other deposit) rather than crediting `claimableStored`
directly. sDGNRS's redeemable FLIP backing is therefore `claimableStored` (the genesis seed reserve,
which redemption burns drain first) **plus** the rolling auto-rebuy carry, and it moves with coinflip
outcomes. This is by design: FLIP is the game's own coin, its backing role is redemption-side only, and
the 0-take-profit perpetual rebuy makes the position structurally roll rather than pay out. No ETH or
stETH solvency term depends on it.
