# FINDINGS — v51.0 (claimBingo Color-Completion + BingoModule + sDGNRS Pool.Reward Rebalance + Jackpot Final-Day Deletion — deferred deliverable, swept under v63.0 Phase 394 LEGACY-DEBT, CROSS-MODEL-LED)

- **Frozen audit subject (SHA):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`). The v51 contract surface is audited AS IT STANDS in the byte-frozen v63 subject. **NOTE — the v51 surface was NOT separately re-frozen:** v51.0 closed 2026-05-28 via a USER-approved MINIMAL CLOSE, with the internal 3-skill adversarial sweep + delta-audit + this `FINDINGS-v51.0.md` all DEFERRED. The deferred debt was folded into v63.0 Phase 394 (LEGACY-DEBT, reqs LEGACY-03/-04/-06) by the USER on 2026-06-14, so the v51 surface is swept as the form it carries at the cumulative byte-frozen v63 subject `a8b702a7` (the v51 items are byte-stable from the v51 close through this subject; `git diff a8b702a7 -- contracts/` is empty at every checkpoint — this is a document-only audit, zero `contracts/*.sol` mutation).
- **Baseline (frozen, green oracle):** `test/REGRESSION-BASELINE-v63.md` = forge **854 / 0 / 110** (carries the Phase-341 v51 coverage: per-tier bingo rewards / per-player dedup / empty-pool no-op / jackpot-final-day regression; the SPEC-339 freeze + tier-precedence proof). The ETH prize-pool conservation anchor is `PoolConservation.inv.t.sol` (FUZZ-05); the sDGNRS Reward-pool backing anchor is the BPS-sum + clamp proof (below).
- **Date:** 2026-06-15.
- **Method — CROSS-MODEL-LED, dual-net (the defining v63 premise, AUDIT-V63-PLAN §2):** the external council (`gemini` + `codex`) is the PRIMARY finder; Claude orchestrates the dispatch, runs an INDEPENDENT second-discipline net, **adjudicates every candidate vs the frozen source** with the skeptic dual-gate, applies the locked threat model + by-design rulings, and anchors verdicts to the green oracle. A no-finding verdict for any sub-item requires BOTH nets on record (NET 1 = council `394-02`; NET 2 = Claude `394-04`).
- **Council pipeline:** `.planning/audit-v52/cross-model/bin/council.sh` -> `ask-gemini.sh` (read-only `--approval-mode plan`) + `ask-codex.sh` (`exec --sandbox read-only`). For the v51 slice (`--label v51`) **`codex` returned a substantive 19-line fully-traced per-item audit (0 findings, all 3 break-targets VERIFIED SOUND); `gemini` is in `skipped[]`** (`v51.council.json` `skipped: ["gemini"]`) — non-responsive (no output within an 8-min hard cap ×2; rc=124), NOT a refusal/classifier trip. The single-available-model-with-real-content rule satisfies "council on record" with the skip documented; a post-responsive `gemini` second-source re-run is carried to **396** (the roles are INVERTED vs the 392/393 slices, where codex was capped and gemini available — so the 396 second-source carry now spans both directions). Raw outputs: `.planning/phases/394-legacy-debt/council/v51.codex.txt` (19 lines) + `v51.gemini.err` (the non-response reason).

---

## Executive summary

**The v51 surface (the `claimBingo` color-completion entrypoint / `DegenerusGameBingoModule.sol`, the sDGNRS `Pool.Reward` rebalance, and the jackpot final-day `Pool.Reward` deletion side-effects) clears the dual-net sweep with 0 actionable findings.** Both nets converged SOUND on all three break-targets. The most material outcome is on the third: a grep-enumeration of every `Pool.Reward` reference across the frozen contracts (run independently by both nets) shows the jackpot final-day `Pool.Reward` deletion premise is **VACUOUS** — there is NO sDGNRS Reward-pool deletion/draw on any final-day path. This is the expected residue of the v51 BINGO bundle, which CLEANLY ORPHANED the old `FINAL_DAY_DGNRS_BPS` / `JackpotDgnrsWin` final-day Reward-deletion branch (Phase 339 Plan 03, decision D-12); the surviving solo-bucket "final day" path pays ETH + whale passes only. Two STALE comments ("DGNRS on final day" at `JackpotModule:1047` and `:1160`) are the only residue and are an INFO doc-hygiene item. The `claimBingo` freeze (the DOMINANT item) is re-verified IN CODE by a backward-trace of every `traitBurnTicket[level]` writer; the tier-precedence + per-player dedup + CEI are confirmed bit-for-bit; the sDGNRS rebalance is proven to conserve the genesis split (the 8 BPS sum to `BPS_DENOM`) with every draw clamped to the live pool. Every result is anchored to the green oracle (854/0/110) and re-verified at the frozen source, not trusted from the v51 paper proofs.

| Disposition | Count |
|---|---|
| **HIGH / CATASTROPHE (contract fix required)** | **0** |
| MEDIUM (contract fix required) | 0 |
| LOW (bounded; fix recommended) | 0 |
| BY-DESIGN (documented intent, recorded so not re-flagged) | 2 — the claimBingo no-level-guard (self-gated ownership check); the bingo one-shot per-`(level,quadrant)` dedup economics |
| REFUTED at the frozen source (the three break-targets + sub-items) | 4 — LEGACY-03a freeze, LEGACY-03b tier/dedup/CEI/empty/gameOver, LEGACY-04a Pool.Reward rebalance, LEGACY-04b final-day deletion (premise vacuous) |
| INFO / doc-only (ROUTED, not a contract change) | 1 — the two stale "DGNRS on final day" comments (`JackpotModule:1047`/`:1160`) |

> **Milestone outcome:** this is the deferred v51 AUDIT deliverable, discharged in-milestone under v63.0 Phase 394. Its deliverable is THIS findings document. **0 actionable findings -> no remediation gate from the v51 surface.** The subject stays byte-frozen; no fix is applied or committed.

---

## The v51 surface coverage (each item with its adjudicated verdict + settling cite at `a8b702a7`)

### LEGACY-03 — claimBingo color-completion / DegenerusGameBingoModule (3-tier reward + tier-precedence + dedup + freeze)

`claimBingo(uint24 level, uint8 symbol, uint32[8] slots)` (`BingoModule:114`) is the v51 color-completion
entrypoint: a player who occupies all 8 color buckets of a single symbol on a level claims a tiered reward
(regular 0.05% Pool.Reward + 1,000e18 BURNIE; symbol-first additive 0.1% + 2,000e18; quadrant-first
replacement 0.5% + 5,000e18, suppressing the symbol bonus — `:14-17`). It is a strict READ-ONLY consumer of
`traitBurnTicket`; the only state it writes is its own `bingoClaimed` / `bingoFirsts` bitfields.

- **LEGACY-03a — freeze-safety of the post-resolution `traitBurnTicket` read — VERIFIED SOUND (REFUTED as a
  finding; DOMINANT, re-verified in code).** Backward-trace of every `traitBurnTicket[level]` writer at the
  frozen source: the SOLE append-writer is `_raritySymbolBatch` (`MintModule:789-812`, the assembly
  batch-`sstore` of the resolved holder address); every other touch is a READ (`claimBingo` `:135-141`
  read-only; `JackpotModule._randTraitTicket` `view`). The sole writer drains the double-buffered ticket
  queue's READ buffer, which is swap+frozen BEFORE the level's word: `_swapTicketSlot` reverts if the read
  slot isn't drained (`Storage:780-784`), `_swapAndFreeze` sets `prizePoolFrozen` (`:793-805`) on the
  daily-RNG path (`AdvanceModule:389`); far-future ticket sales revert during the RNG lock
  (`MintModule:1214`). So once a level's word is public, its `traitBurnTicket` bucket membership is the
  resolved output of draining a buffer swapped/frozen before the word — no player-reachable post-word append
  exists, and the `claimBingo` read is over a frozen population. SPEC-339 freeze re-verified by the
  backward-trace, not trusted from the paper proof. Additional hardening: `claimBingo` is strictly
  `msg.sender`-only — no `player` argument, no operator path (the `NotApproved`/`_resolvePlayer` operator
  resolution `:267-275` belongs to the SEPARATE `claimAffiliateDgnrsReward`, not to `claimBingo`). Green
  anchor: `RngWindowFreeze.inv.t.sol` (exercised, non-vacuous, per the v63 baseline §2).
- **LEGACY-03b — 3-tier reward selection + tier-precedence + per-player `(level,quadrant)` dedup + CEI +
  empty-pool + gameOver — VERIFIED SOUND (REFUTED).** Tier-precedence: `bf = bingoFirsts[level]` is read once,
  split into `fq = uint8(bf >> 32)` (quadrant mask) + `fs = uint32(bf)` (symbol mask); quadrant-first
  (`(fq & qMask) == 0`) is checked FIRST and marks BOTH bits in one packed write (`:166-169`), SUPPRESSING the
  symbol bonus (a later same-symbol claim finds `isSymbolFirst == false`); symbol-first (`:174`) marks only
  the symbol bit while preserving the co-resident quadrant mask via `(bf & ~uint64(0xFFFFFFFF))`. No path pays
  symbol+quadrant for the same `(level, quadrant)`. CEI dedup: the per-player bit
  `bingoClaimed[level][msg.sender] |= qMask` (`:151`) and the tier bits (`:166-169`/`:174`) are ALL set BEFORE
  the interactions `transferFromPool` / `creditFlip` (`:188-196`), so a reentrant or repeat claim hits the set
  `qMask` and reverts `AlreadyClaimed` (`:150`) — the reentrancy window is closed by
  effects-before-interactions (the module CEI doctrine, `:19-22`). Empty-pool: `transferFromPool` clamps to 0
  on an empty pool (`StakedStonk:553-556`) without reverting, so the bingo bit is consumed and only the BURNIE
  flip credit is paid (`:196`, always reached, tier BURNIE always non-zero) — a graceful no-op, not a strand.
  gameOver: `if (gameOver) revert E();` (`:122`) blocks a post-game claim. The absence of a level upper-bound
  guard is BY-DESIGN (the 8-color ownership check `:137-145` self-gates an unresolved/future bucket to
  `NotSlotOwner`, [[claimbingo-no-level-guard]]).

### LEGACY-04 — sDGNRS Pool.Reward rebalance + jackpot final-day Pool.Reward deletion side-effects

- **LEGACY-04a — the sDGNRS Pool.Reward rebalance (AFFILIATE 3500->3000 / REWARD 500->1000) — VERIFIED SOUND
  (REFUTED).** Split-conservation, re-summed at the frozen source (`StakedStonk:305-312`): CREATOR 2000 +
  WHALE 1000 + AFFILIATE 3000 + LOOTBOX 2000 + REWARD 1000 + PRESALE_BOX 1000 = **10000 == `BPS_DENOM`**
  (`:302`). The rebalance is internal to the AFFILIATE/REWARD pair (-500 / +500); the sum is invariant. The
  `Pool` enum has exactly 5 members (`:241-247`); no stray member carries a non-zero BPS off the 6 named
  constants. Genesis seeding (`:384-408`) is exact: `INITIAL_SUPPLY = 1e30` is divisible by `BPS_DENOM`
  (`1e30 / 1e4 = 1e26`, integer), so each slice is exact, `totalAllocated == INITIAL_SUPPLY`, and the dust
  branch (`:391-397`) is a no-op; the `uint128` narrowing is safe (each slice <= 1e30 << 2^128). No over-draw:
  `transferFromPool` clamps (`:548-570`: `available==0->0`; `amount>available->available`; the decrement is
  bounded by `available`) and `transferBetweenPools` clamps identically (`:579-593`). Every `Pool.Reward`
  consumer reads the LIVE balance and clamps — Bingo (`:188-193`), Degenerette (`:1220-1232`), the coinflip
  bounty (`Game:465-475`) — so NO consumer hard-codes the old 500/3500 split; the rebalance is automatically
  respected. Green anchor: the sDGNRS pool backing is the BPS-sum + clamp proof; the ETH-pool conservation is
  `PoolConservation.inv.t.sol` (FUZZ-05).
- **LEGACY-04b — the jackpot final-day Pool.Reward deletion side-effects — VERIFIED SOUND (REFUTED; PREMISE
  VACUOUS).** A grep-enumeration of every `Pool.Reward` reference across the frozen contracts
  (`git grep -n -E 'Pool\.Reward|poolBalances\[' a8b702a7`) shows `Pool.Reward` appears at EXACTLY 6 sites —
  genesis seeding (`StakedStonk:408`/`:311`/`:389`), the 3 live draws (Bingo `:188/190`, Degenerette
  `:1221/1230`, coinflip bounty `Game:466/472`), and doc comments — and NOWHERE in `DegenerusGameAdvanceModule`
  or `DegenerusGameJackpotModule`. The AdvanceModule final-day pool draw (`_rewardTopAffiliate` `:753-763`)
  targets **`Pool.Affiliate`**, not `Pool.Reward`; `JackpotModule` has ZERO sDGNRS pool touch (the grep is
  empty). **There is no sDGNRS Reward-pool deletion/draw on any final-day path — the break-target premise does
  not hold.** This is the expected residue of the v51 BINGO bundle: Phase 339 Plan 03 (decision D-12) CLEANLY
  ORPHANED the old final-day Reward-deletion branch (the `FINAL_DAY_DGNRS_BPS` / `JackpotDgnrsWin` path), so
  the surviving solo-bucket "final day" path (`_handleSoloBucketWinner` -> `_processSoloBucketWinner`) pays 75%
  ETH (credited to claimable) + 25% as whale passes (moved to `futurePrizePool`) — no `Pool.Reward` /
  `transferFromPool` / sDGNRS-token mutation. The real final-day surface is the ETH prize-pool consolidation
  (`currentPrizePool` / `claimablePool` / `futurePrizePool`, `Storage:354-379`), whose backing-conservation is
  the SOLVENCY-spine surface owned by Phase 390 + attested green by FUZZ-05 (`PoolConservation.inv.t.sol`: the
  four ETH pools are fully backed by balance+stETH and never inflate beyond real inflow). With `Pool.Reward`
  untouched on the final day, there is NO stranded sDGNRS backing and NO double-spend against a concurrent
  Bingo/Degenerette draw (those read the live Reward balance and clamp; same-block draws are EVM-sequenced, so
  the second reads the already-decremented balance — the clamp bounds the sum to the seeded pool).

---

## Lower-severity / INFO

- **INFO — stale "DGNRS on final day" comments (doc-only, comment-only, ROUTED).** Two comments —
  `JackpotModule:1047` ("Solo bucket gets whale pass + DGNRS on final day") and `:1160` ("Solo bucket (jackpot
  phase): whale pass + DGNRS on final day") — describe a `Pool.Reward`/DGNRS transfer the frozen solo-bucket
  path does NOT implement (it pays ETH + whale passes only). They are the residue of the v51 D-12 orphaning of
  the final-day Reward-deletion branch. The code is the authority; no value moves — this is a doc-hygiene item
  ([[feedback_no_history_in_comments]] / [[lean-code-comments-no-procedural-meta]]). Route a comment trim to a
  post-audit hygiene pass (a non-contract edit, deferred while the subject is byte-frozen). codex independently
  flagged `:1047`; the Claude net found the second site `:1160`.

## Refuted / by-design (recorded so they are not re-flagged)

- **Jackpot final-day Pool.Reward deletion (the charged break-target) — REFUTED, PREMISE VACUOUS.** No sDGNRS
  Reward-pool deletion/draw exists on any final-day path; the old branch was orphaned at v51 (D-12). The
  surviving final-day surface is the ETH prize-pool, FUZZ-05-conserved.
- **claimBingo no-level-guard — BY-DESIGN.** No level upper-bound guard; the 8-color ownership check self-gates
  an unresolved/future bucket to `NotSlotOwner` ([[claimbingo-no-level-guard]]). The intended self-gating, not
  a defect.
- **Bingo one-shot per-`(level,quadrant)` dedup — BY-DESIGN.** The dedup bit (`bingoClaimed`, `:151`) is
  permanent by intent — bingo is a first-completion reward; an empty Reward pool at claim-time consumes the
  bit and pays only BURNIE (the sDGNRS draw is a graceful no-op). The intended one-shot economics
  ([[intended-game-mechanics-not-findings]]), not a defect.
- **Degenerette RTP / whale-pass / WWXRP economics — BY-DESIGN.** Not re-litigated; the sweep verifies the
  `Pool.Reward` draw conservation, not the RTP ([[degenerette-wwxrp-rtp-by-design]]).

## Prior mitigations carried (the v51-close coverage, re-attested at this subject)

- **SPEC (Phase 339):** `339-BINGO06-FREEZE-PROOF.md` (BINGO-06 freeze-safe via the D-04 per-slot
  enumeration) + the traitBurnTicket soundness attestation (D-02) + the tier-precedence design-lock (D-06,
  quadrant-first-before-symbol-first + both-bits-marking + suppression). Re-verified in code by NET 2's
  backward-trace.
- **TST (Phase 341):** the per-tier bingo rewards / per-player dedup / empty-pool no-op / jackpot-final-day
  regression coverage, folded into the v63 green oracle (854/0/110).
- **POOL-CONSERVATION (FUZZ-05):** `PoolConservation.inv.t.sol` — the four ETH prize-pools fully backed +
  transfers conserve (the LEGACY-04b ETH final-day anchor).

## Both-nets-on-record attestation

| Break-target | NET 1 (codex) | NET 2 (Claude `394-04`) | Both on record? |
|---|---|---|---|
| LEGACY-03 claimBingo freeze + tier/dedup/CEI/empty/gameOver | VERIFIED SOUND | REFUTED (freeze backward-trace + CEI bit-ordering) | yes (codex + Claude); gemini skip -> 396 |
| LEGACY-04a Pool.Reward rebalance | VERIFIED SOUND | REFUTED (8-BPS sum = BPS_DENOM + clamp) | yes |
| LEGACY-04b final-day deletion | VERIFIED SOUND — codex found NO final-day Reward path | REFUTED, premise VACUOUS (grep-enumeration + D-12 orphaning) | yes |

Both nets CONVERGE SOUND on all three break-targets. The `gemini` skip (non-responsive) is documented; a
post-responsive second-source re-run is carried to 396. No DIVERGENT lead.

---

## Byte-freeze attestation

`git diff a8b702a7 -- contracts/` is EMPTY before and after the v51 adjudication (NET 2 read all source via
`git show a8b702a7:`; the council ran read-only). `git status --porcelain contracts/` EMPTY; the contracts
tree held at `2934d3d8987a09c5f073549a0cb499f6c5f28620` throughout. Hardhat was never invoked (the
ContractAddresses-regeneration landmine avoided). No CONFIRMED finding was fixed in-phase (0 CONFIRMED). The
only untracked working-tree file is the pre-existing `PLAYER-PURCHASE-REWARDS.html` (unrelated; left
untouched). This deliverable is factual + neutral; it is NOT chmod-444-sealed here (the terminal v63 close,
Phase 396, handles sealing).

**v51 verdict:** the v51 surface (LEGACY-03 claimBingo / BingoModule; LEGACY-04 the sDGNRS `Pool.Reward`
rebalance + the jackpot final-day deletion) is adjudicated against the byte-frozen subject `a8b702a7` with
BOTH nets on record (codex + Claude, CONVERGENT SOUND; gemini skip -> 396), the skeptic dual-gate applied, and
every break-target carrying an explicit verdict. **0 actionable findings**; 1 INFO doc-hygiene item (the stale
`JackpotModule:1047`/`:1160` comments). The byte-frozen subject is attested throughout.
