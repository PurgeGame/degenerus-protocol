# 381-06 — Council Completeness Adjudication (FUZZ-06)

**Subject:** frozen `c4d48008` · **Council:** gemini-3-pro-preview + codex (gpt-5.x), both returned, 0 skipped.
**Dispatch:** `.planning/audit-v52/cross-model/381-fuzz-completeness/` (council.sh, label `fuzz-completeness`).
**Question put to the council:** what protocol property SHOULD always hold but FUZZ-01..05 do not assert?

## Convergent theme

Both models, by different routes, flagged the SAME blind-spot class: the net asserts **enqueue** (FUZZ-04)
and **gas ceiling** (FUZZ-03) but NOT **post-resolution liveness/openability** — i.e. that a finalized box
actually opens, and that `advanceGame()` actually succeeds (not just stays under a gas cap). That theme
turned out to contain a real, reproduced defect.

## Per-candidate verdicts

### C1 (codex) — Box auto-open completeness — **CONFIRMED (real finding) → routed to USER-gated fix**
- **Claim:** the permissionless `openBoxes()`/`boxesPending()` read the **active** `LR_INDEX`, but VRF
  words land at `LR_INDEX − 1` (the request pre-increments the index before the word lands). So human +
  presale lootboxes are **never auto-opened** by the permissionless valve; they degrade to manual-only
  `openLootBox(owner, N)`, returning open-timing control to the box owner.
- **Adjudication (vs `c4d48008`):** confirmed by source — enqueue at `boxPlayers[LR_INDEX]`
  (MintModule ~:1251, Whale ~:896, presale ~:1602); both word-landing paths write `LR_INDEX − 1`
  (`rawFulfillRandomWords` AdvanceModule:1815-1816; `_finalizeLootboxRng` :1281-1283); the only two
  increment sites pre-advance the index (:1136, :1693); `_openHumanBoxes` reads `index = LR_INDEX`
  (DegenerusGame.sol:1889) and bails on `lootboxRngWordByIndex[index]==0` (:1899). Presale-only boxes are
  additionally skipped by the `lootboxEthBase==0 → continue` guard (:1912). The afking-cover leg is
  immune (keys off `rngWordByDay[stampDay]`, GameAfkingModule ~:1488) — the differential tell.
- **Empirically reproduced** (test-only, real contracts, zero contract mutation —
  `test/repro/C1BoxAutoOpen.t.sol`, 2/2 pass): human box at N=2 (base 1.2 ETH); after the word lands at
  N=2 with LR_INDEX=3, `openBoxes(50)` opens **0** and the base is **unchanged**; a second `openBoxes`
  after LR_INDEX→4 still opens nothing (box structurally abandoned, not merely not-yet-ready); manual
  `openLootBox(actor, 2)` zeroes the base (box was ready + owed). Identical on the daily-finalize path.
- **Severity: MEDIUM–HIGH.** No fund loss / no solvency or RNG-freeze break (the seed is frozen at
  `keccak256(rngWord, player, amount)`; only `currentLevel` shifts at open). BUT it re-opens the **WHALE-01
  anti-timing vector** (v60) for the mainline human/presale box classes: with the permissionless valve
  dead, the owner has sole control of open timing. The lootbox-resolution-timing by-design ruling
  *presumes a working permissionless backstop* — which is violated here. USER adjudicates final severity.
- **Disposition:** v62 is document-only → **NOT fixed autonomously**. Recorded as Finding **V62-01**;
  candidate fix = point the `openBoxes`/`boxesPending` reads at `LR_INDEX − 1` (where words land) +
  include the presale-box leg. Re-examined under 383 ASYM-02 + 384 COMPO. The proper after-fix regression
  (assert `openBoxes` DOES drain a ready box) ships with the gated fix.

### G2 (gemini) — advanceGame liveness / unbounded backfill revert — **REFUTED (+ net-gap noted)**
- **Claim:** `retryLootboxRng`/VRF-stall piles up orphaned indices; `_backfillOrphanedLootboxIndices` does
  an unbounded backward scan that reverts and bricks `advanceGame` (passing FUZZ-03 because a revert is
  cheap).
- **Adjudication:** REFUTED. `_backfillOrphanedLootboxIndices` (AdvanceModule:1861-1880) **breaks on the
  first filled index**; orphans cannot accumulate — `LR_INDEX` is structurally ≤1 ahead of the last
  filled index (mid-day `requestLootboxRng` gated on `rngRequestTime==0` :1077; `retryLootboxRng` writes
  no index :1152-1170; coordinator rotation preserves the index). Already net-asserted by
  `VRFPathInvariants.inv.t.sol` (`invariant_everyIndexHasWord`, `invariant_indexNeverSkips`).
- **Net-gap (real, orthogonal):** no invariant forbids `advanceGame()` from **reverting** in a due/unlocked
  state; existing tests only `try/catch` it. → folded as a candidate (see below).

### G1 (gemini) — ticket / hero-wager conservation — **REFUTED**
- **Claim:** free-mint `dailyHeroWagers` via zero-cost afking entries → jackpot capture with pools green.
- **Adjudication:** REFUTED. `dailyHeroWagers` is credited **only for `CURRENCY_ETH`** (DegeneretteModule
  :540) from `totalBet` that `_collectBetFunds` (:572-616) requires fully funded by `msg.value`/`claimable`
  /`afking` (each debiting `claimablePool`, else `revert InvalidBet()`). No free balance exists to inflate
  with; afking funding moves `claimablePool` in tandem (SOLVENCY-01). Generous RTP / worthless WWXRP are
  the existing by-design rulings, not an accounting bug.

## Fold-in decision (per plan: fold ONLY convergent, reproducible gaps; never block on speculative)

1. **Auto-open completeness** — this is the C1 finding's regression property (RED at `c4d48008`, GREEN
   after the gated fix). NOT folded into the green net now (would be a permanently-red invariant pre-fix);
   it travels with the V62-01 fix. The reproduction `test/repro/C1BoxAutoOpen.t.sol` stands as the proof.
2. **advanceGame liveness (non-revert)** — a real green-foldable net-gap. Deferred to 384 COMPO/385 LOOP
   where the advanceGame harness already lives (FUZZ-03 component), rather than a thin add here — recorded
   as candidate **NETGAP-02** so the sweep owns it with the right harness.

**Outcome:** the council found a real defect the net missed (C1 → V62-01) — exactly the FUZZ-06 purpose:
surface a missing property NOW, not as an un-caught finding later. The net is otherwise complete for the
solvency and RNG-freeze threat classes per the refutations above. Pipeline validated end-to-end (both
models headless, adjudicated vs frozen source, convergent finding reproduced on the harness).
