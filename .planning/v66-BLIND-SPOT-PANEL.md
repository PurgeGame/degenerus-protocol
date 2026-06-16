# v66.0 Blind-Spot Panel — "How might we be missing something?"

> Claude-internal foundation step (six diverse lenses attacking our OWN RNG/cross-contract audit).
> The actual cross-model council (Gemini + Codex) is the PRIMARY finder in the execute phases — this
> panel produces the SEED hypotheses the council verifies / refutes / extends. Run `wf_fd1bfbb7-e99`,
> 2026-06-16, against post-rename HEAD (`origin/main bb0912a6`).

## The convergent meta-finding (5 of 6 lenses, independently)

**Our trusted RNG corpus is a stale snapshot, and the audit net was drawn against it — never re-derived
from current code.** This is the structural reason a real defect could survive 10+ passes: every pass
re-confirms the *cataloged* consumers and never notices newer ones, or re-cites proofs whose anchor code
no longer exists.

Stale anchors found:
- **`RNGLOCK-CATALOG.md`** (v42/v43, 2026-05-18) — entire slot×writer×callsite matrix keyed to deleted
  `BurnieCoinflip` / `StakedDegenerusStonk` names + old line numbers; lists **13 VRF consumers** and at
  least **5 current consumers are absent** from it (see below).
- **`audit/v30-RNGLOCK-STATE-MACHINE.md` / `v30-FREEZE-PROOF.md`** — describe `updateVrfCoordinatorAndSub`
  as Clear-Site C-02 (an "AIRTIGHT" rngLockedFlag=false reset). **Current code does the opposite**: it
  KEEPS the lock true and re-requests on the new coordinator. The proof analyzes a threat model that no
  longer applies; every cited line is off by ~60–120 lines.
- **Redemption `§12`** — models a stored `flipDay` struct field. Current code has **no stored flipDay**;
  it recomputes `day+1` from a **caller-supplied argument** at claim time.
- **`§11` coinflip/bounty proof** — anchored on `_targetFlipDay → currentDayView()` cross-call. Current
  code uses a **local `GameTimeLib` wall-clock calc**; the v65 rename framed this as "name-only" and
  buried a real call-graph change.

## Newly-found VRF consumers NOT enrolled in the trusted net

| Consumer | Where | Reads (player-mutable?) | Sev-if-real |
|---|---|---|---|
| `runBafJackpot` winner-select | `DegenerusJackpots.sol:262/318/389` → re-entrant `sampleFarFutureTickets`/`sampleTraitTicketsAtLevel` | `ticketQueue` / `traitBurnTicket` queues | **HIGH** |
| `_farFutureSeed` salvage | `MintStreakUtils.sol:244-250` | `keccak(player, rngWordByDay[day-1])` — **address-selectable** | MED (likely) |
| `coinflipTopByDay` BAF slice | `Jackpots.sol:284` ↔ `Coinflip.sol:1103` | leaderboard, lock only on `lvl%10==0` | MED |
| Degenerette FLIP survival flip | `DegeneretteModule.sol:773/791` | `hash2(rngWord, betId)` | — |
| Redemption FLIP-escrow leg | `sDGNRS.sol:888` `getCoinflipDayResult(day+1)` | cross-contract win/loss | MED (likely) |

## Ranked blind spots

### Tier 1 — verify first (concrete, plausibly real, or live net-gap)

1. **Gameover prevrandao fallback never sets `rngLockedFlag`** (Lens 1, HIGH). During the 14-day fallback
   window (`AdvanceModule.sol:1327-1364`), the fallback word mixes `block.prevrandao` (proposer-influenceable)
   and feeds **four** consumers (coinflip resolve, bounty, redemption roll, lootbox draw) while every
   consumer gate that relies on `rngLocked()` is OPEN: Coinflip bounty-arm `!rngLocked()` (`:686`), carry
   (`:752/:791/:822`), sDGNRS `BurnsBlockedDuringRng`. The code only patches the **reverseFlip** input; the
   FLIP-emission + salvage-carry reworks added player-controllable inputs to those same consumers *after*
   the KI exception was signed. Re-derive freshness of every fallback consumer.

2. **Redemption claim argument-selection** (Lens 3, HIGH). `claimRedemption(player, day)` recomputes
   `rngWordForDay(day+1)` (`sDGNRS:916`) and `getCoinflipDayResult(day+1)` (`:888`) from a **caller-supplied
   `day`**, gated only by two existence checks. If any path leaves a non-empty `pendingRedemptions[player][D]`
   for a `D` whose `D+1` word is already on-chain, the caller foreknows both the lootbox seed AND the FLIP
   win/loss. Prove `pendingRedemptions[*][d]` can only exist for `d == currentDayIndex()` with `d+1` undrawn.

3. **Redemption claim-side seed is mocked away in EVERY test** (Lens 6, HIGH). Both redemption test files
   mock the word source; a one-line `rngWordForDay(day+1) → rngWordForDay(day)` mutant — the exact **v62
   REDEMPTION-ZERO-SEED class** — would pass the whole redemption suite green. The burn-side gate is netted;
   the **claim-side `day+1` binding has no behavioral net.** Write a real submit→resolve→claim test; the
   mutant must fail.

4. **Mid-day cross-day lootbox binding test is `vm.skip(true)`'d + vacuous** (Lens 6, HIGH). The only
   mechanical net for the `rngLockedFlag==FALSE` mid-day freeze window (`RngIndexDrainBinding.t.sol:214-266`)
   is disabled (decodes a slimmed-away event field). A regression letting a post-request box/ticket bind to
   the in-flight word would be green. Rewrite to read `lootboxRngWordByIndex[LR_INDEX-1]` from storage.

5. **BAF winner-set freeze** (Lens 2, HIGH). `runBafJackpot` samples mutable `ticketQueue` far-future keys
   and `traitBurnTicket`; classified EXEMPT-ADVANCEGAME by *assumption*, never *proof*. Enumerate every
   writer to the sampled queues and prove none is reachable after the daily word is observable but before
   the advance that runs the BAF.

### Tier 2 — consumer-net + seams

6. **Salvage address-selection grind** (Lens 5, MED/likely). `_farFutureSeed = keccak(player, knownWord)`;
   the only player-variable preimage is the address. Pick the EOA whose seed lands `jitterMult ≈ 110%` →
   ~1.57× over the discount floor, every sale. Freeze proof satisfied; **selection-grind wide open** — and
   the trusted doc (`v63 rng-freeze.md §10`) explicitly dismisses it on *timing* grounds only.
7. **`coinflipTopByDay` BAF leaderboard freeze across Game↔Jackpots↔Coinflip** (Lens 2, MED) — lock predicate
   lives in Coinflip and fires only on `lvl%10==0`; prove "which day is locked" == "which day the BAF reads".
8. **Redemption FLIP-escrow leg freeze** (Lens 3, likely) — `getCoinflipDayResult(day+1)` was only ever
   reviewed for *solvency*, never for *freshness*; prove `day+1`'s result is unwritten at submit.
9. **Degenerette index-keyed score freeze** (Lens 5, HIGH-if-real) — the score-deciding `resultSeed =
   keccak(rngWord, index, spinIdx)` omits both betId and player; the entire freeze rests on the single
   placement guard `lootboxRngWordByIndex[index]!=0 ⇒ revert` (`:533`). Exhaustively prove no word-set path
   coincides with an accepting placement index (esp. gap-backfill `:1899-1901`, mid-day retry).
10. **Coordinator-rotation-while-locked** (Lens 1/4/6, MED) — behavior IS netted by
    `RngLockRotationDeterminism.t.sol`; the **docs are stale**. Re-derive the set/clear state machine at HEAD
    (2 set + 1 clear, not the doc's 1 set + 2 clear) and confirm no rotation path strands or under-freezes.

### Tier 3 — verify-and-close

11. **Coinflip `win = b >= 50` floor** (Lens 4, MED) — confirm `COINFLIP_EXTRA_MIN_PERCENT >= 50` at HEAD
    post-rename/optimizer-bump so no win stores `b ∈ [2,49]` misreading as a loss. Resolvable by reading two
    constants.
12. **Coinflip win-path netted only by a source-string match** (Lens 6, MED) —
    `testWinLossRngPathByteUnmodified` counts a literal string; blind to callsite arg-swaps, the `seedWord`
    reward path, and the packing threshold. Run a mutation pass on `processCoinflipPayouts/_storeDayResult/_dayResult`.
13. **Stall gap-backfill entropy collapse** (Lens 3, MED) — roll / flip-win / lootbox seed all derive from
    one post-gap `currentWord`; design assumes three independent draws. Quantify any EV deviation.
14. **Redemption first-mover / elective resolution** (Lens 4, MED) — outcome publicly precomputable, no claim
    deadline; "permissionless ⇒ no timing control" answers "can others claim?" not "can the player capture
    asymmetric outcomes by self-claiming first?" (whale-pass jackpot order-dependence).

## How this reshapes the milestone

The v66 net must be **re-derived from current HEAD**, not inherited from the catalog. The panel's blind
spots become the council's seed prompts. The mechanical-net gaps (3, 4, 12) are committable test work
(no contract changes); the rest are verify-or-refute hunts that only touch `.sol` if a real defect surfaces.
