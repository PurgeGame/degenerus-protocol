# Council Sweep 394-02 — LEGACY-DEBT / the v51 surface slice (LEGACY-03, LEGACY-04)

You are an external auditor on a cross-model council reviewing the **Degenerus Protocol** before a
Code4rena engagement. Read the EXACT frozen source at `a8b702a7` via
`git show a8b702a7:contracts/<File>.sol` (ignore the working tree — it has docs-only commits on top of
the frozen subject). Be concrete and reachable: a finding needs a real ordered call sequence (the
multi-claim interleaving, the reentrant-callee re-entry, or the final-day-advance/concurrent-draw ordering —
where the ordering matters) and a named state variable with a `file:line` at `a8b702a7`. No speculative gaps.

This slice reviews the **v51 contract surface** — long-deferred audit debt. v51.0 closed minimally without
the internal adversarial sweep's external second-source, so the v51 changes never received a cross-model
pass: the `claimBingo` color-completion entrypoint / `DegenerusGameBingoModule.sol` (a tiered Pool.Reward
draw on owning one resolved ticket entry in each of the 8 color buckets of a symbol on a level), the sDGNRS
`Pool.Reward` rebalance (AFFILIATE 3500→3000 / REWARD 500→1000 bps), and the jackpot final-day `Pool.Reward`
consolidation/deletion side-effects. We believe these properties hold across the v51 surface — `claimBingo`
is a CEI-correct strict READ-ONLY consumer of a pre-resolved (freeze-safe) trait population with correct
3-tier selection / tier-precedence suppression / per-player `(level, quadrant)` dedup / empty-pool no-op /
`gameOver` cutoff; the sDGNRS `Pool.Reward` rebalance keeps the pool splits summing to the denominator with
no over-draw; the jackpot final-day `Pool.Reward` deletion/draw conserves backing (no strand, no
double-spend). **Your job is to find where one of these beliefs breaks.**

## Threat priority (USER-locked for this slice)

**DOMINANT = RNG/freeze** — the `claimBingo` ownership read over `traitBurnTicket` is RNG/freeze-adjacent:
the read happens POST-resolution (after the level's word is public). A confirmed FREEZE break — the trait
population the read consumes became player-STEERABLE after the level's word was on-chain so a player can
choose which color-completion they hold against a known word, or a bingo draw entropy that is grindable — is
the HIGHEST-severity class here. **SPINE = solvency** — a `Pool.Reward` rebalance conservation break (the
splits no longer sum to the denominator so genesis over-/under-seeds, or `transferFromPool` over-draws past
the pool balance) or a jackpot final-day deletion break (Reward backing stranded or double-spent on the
final-day consolidation) is SPINE-level. **LOW/confirmatory = access-control / reentrancy / MEV** — a broken
CEI ordering that lets a reentrant `creditFlip` / `transferFromPool` re-enter the dedup is confirmatory.
A desirability complaint about the no-level-guard or the RTP is **NOT** a finding.

## Trust-boundary framing (so you do not waste passes)

- `claimBingo` is **permissionless-for-beneficiary**: the reward credits `msg.sender` (or the player on
  whose behalf an approved operator claims), gated by the 8-color ownership read over `traitBurnTicket` + the
  per-player `(level, quadrant)` dedup bit + the `gameOver` cutoff. The caller can only claim a completion
  it actually owns; the value flows to the beneficiary, never to an arbitrary `msg.sender`.
- `transferFromPool` / `transferBetweenPools` are `onlyGame` callees; `creditFlip` is an `onlyFlipCreditors`
  callee. The Pool.Reward genesis split and the final-day consolidation run INSIDE the contracts' own
  accounting (the Game/sDGNRS modules share the inherited `DegenerusGameStorage` and reach sDGNRS via the
  `IStakedDegenerusStonk` interface). The residual risk is therefore **freeze-safety / accounting-correctness
  / dedup-integrity / tier-precedence / pool-conservation**, NOT a cross-module access bypass.

## KNOWN BY-DESIGN (do NOT flag — out of scope for this slice)

- **`claimBingo` has NO level guard — BY-DESIGN.** The traits pre-resolve to `currentLevel + 5` and the
  8-color ownership read self-gates (a player can only claim a completion it actually holds in the resolved
  buckets); the signature is `claimBingo(uint24 level, …)`. **Do NOT flag the absence of a level guard.** The
  question is whether the ownership read + the dedup + the `gameOver` cutoff are CORRECT, not whether a level
  guard is missing.
- **EV > 100% RTP / positive-EV reward draws / the deliberately-near-worthless WWXRP token / the
  near-unfarmable whale pass / refund floors / charity governance are by-design economics.** Verify
  pool-conservation + freeze + dedup + tier-precedence, NOT whether an EV is desirable. Do not flag "the
  bingo reward is too generous" or "RTP too high".
- **Lootbox / redemption / claim TIMING is not a player edge** — the open is permissionless and
  economically-incentivized; the seed is frozen before the open, so WHEN a player claims cannot re-roll an
  outcome. (A path where the population the read consumes is NOT yet frozen at the player's commitment, or can
  be re-steered against a now-public word, IS in scope — that is a freeze break, not a timing edge.)
- **An admin / protocol-address breaking its OWN game at genesis with no engaged community is a non-finding.**

## The thesis to BREAK (mapped to LEGACY-03..04)

We believe ALL of the following hold. Find a concrete counterexample to any one — or VERIFY SOUND with the
specific reason it holds.

1. **(LEGACY-03) `claimBingo` is a CEI-correct, freeze-safe, tier-precedence-correct, dedup-tight,
   empty-pool-safe, `gameOver`-gated read-only consumer of a pre-resolved trait population.**
2. **(LEGACY-04a) The sDGNRS `Pool.Reward` rebalance (AFFILIATE 3000 / REWARD 1000 bps) conserves total
   supply** (the pool BPS sum to `BPS_DENOM` so genesis neither over- nor under-allocates) **and admits no
   over-draw** (`transferFromPool` clamps to the available balance; no consumer hard-codes the old split).
3. **(LEGACY-04b) The jackpot final-day `Pool.Reward` consolidation/deletion conserves backing** — no Reward
   draw on the final-day path strands a decremented-but-not-transferred (or transferred-but-not-decremented)
   balance, and no Reward backing is double-spent across the final-day consolidation and a concurrent
   `claimBingo` / Degenerette Reward draw in the same advance window.

## Authoritative frozen line-cites (read the code via `git show a8b702a7:...`, do not trust the cite blindly)

Cites verified at `a8b702a7`; re-read each — several drift by a few lines from prior planning notes, and the
prompt flags the known drifts so you pin the right code.

- `contracts/modules/DegenerusGameBingoModule.sol`:
  - the 3-tier doc-table + CEI doctrine in the contract NatSpec @14-22 (regular `0.05% Pool.Reward +
    1_000e18 BURNIE` / symbol-first additive `+0.05% + 1_000e18` / quadrant-first replacement `0.5% +
    5_000e18`, suppresses the symbol bonus; "`claimBingo` is a strict READ-ONLY consumer of `traitBurnTicket`
    … CEI: effects [the bit sets] precede interactions [`transferFromPool` / `creditFlip`]");
  - the reward constants `REGULAR_DGNRS_BPS = 5` @49, `FIRST_SYMBOL_BONUS_DGNRS_BPS = 5`,
    `FIRST_QUADRANT_DGNRS_BPS = 50`, `REGULAR_BURNIE = 1_000e18`, `FIRST_SYMBOL_BONUS_BURNIE`,
    `FIRST_QUADRANT_BURNIE = 5_000e18` @49-65;
  - the `AlreadyClaimed` error @39;
  - `function claimBingo(uint24 level, uint8 symbol, uint32[8] calldata slots)` @114; the comment that
    `claimBingo` only READS `traitBurnTicket` @118; the `gameOver` cutoff `if (gameOver) revert E()` @122;
    `quadrant = symbol >> 3` @125, `qMask = uint8(1 << quadrant)` @127;
  - the READ-ONLY ownership read over `traitBurnTicket[level]` @130-136 (`levelBuckets = traitBurnTicket[level]`
    @135; `traitBase = (uint256(quadrant) << 6) | uint256(symInQ)` @136; the per-color `traitId =
    (quadrant << 6) | (c << 3) | symInQ`, index-guarded, fails closed);
  - the per-player `(level, quadrant)` dedup EFFECT @148-151 (`claimedBits = bingoClaimed[level][msg.sender]`
    @149; `if (claimedBits & qMask != 0) revert AlreadyClaimed()` @150; `bingoClaimed[level][msg.sender] =
    claimedBits | qMask` @151);
  - the tier cascade EFFECTS / bit-sets @155-180 (`bf = bingoFirsts[level]` @157; `fq = uint8(bf >> 32)` the
    quadrant mask in bits [32:36) @158; `isQuadrantFirst = (fq & qMask) == 0` @160; a quadrant-first marks
    BOTH bits @167-169 and pays `FIRST_QUADRANT_DGNRS_BPS` / `FIRST_QUADRANT_BURNIE`; a symbol-first marks
    only the symbol bit, preserving the co-resident quadrant mask @174-176 and pays `REGULAR +
    FIRST_SYMBOL_BONUS`; the regular tier pays `REGULAR_DGNRS_BPS` @180);
  - the sDGNRS draw `poolBal = dgnrs.poolBalance(Pool.Reward)` @188 + `dgnrsPaid = dgnrs.transferFromPool(
    Pool.Reward, …)` @189 (clamps to available); the BURNIE flip credit `coinflip.creditFlip(msg.sender,
    burnie)` @196;
  - the second draw helper (operator-path) `transferFromPool` @240 + `creditFlip` @259.
- `contracts/StakedDegenerusStonk.sol`:
  - the pool BPS constants `BPS_DENOM = 10_000` @302; `CREATOR_BPS = 2000` @305; `WHALE_POOL_BPS = 1000`
    @308; `AFFILIATE_POOL_BPS = 3000` @309 (was 3500); `LOOTBOX_POOL_BPS = 2000` @310; `REWARD_POOL_BPS =
    1000` @311 (was 500); `PRESALE_BOX_POOL_BPS = 1000` @312;
  - `INITIAL_SUPPLY = 1_000_000_000_000 * 1e18` @299; the genesis seeding @384-408 (`creatorAmount` @384 …
    `rewardAmount = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM` @389; `totalAllocated = creator + whale +
    presaleBox + affiliate + lootbox + reward` @390; the `if (totalAllocated < INITIAL_SUPPLY)` dust handling
    @391-399; `poolBalances[uint8(Pool.Reward)] = uint128(rewardAmount)` @408 — NOTE only these 6 pools carry
    a non-zero BPS; verify what the OTHER `Pool` enum members are and whether the 6 sum to `BPS_DENOM`);
  - `function poolBalance(Pool pool)` @509; `function transferFromPool(Pool, address, uint256) onlyGame` @548
    (clamps to available); `function transferBetweenPools(Pool, Pool, uint256) onlyGame` @579.
- `Pool.Reward` consumers (the conservation surface to verify all draws clamp + no consumer hard-codes the old split):
  - `BingoModule` @188-189 (the bingo draw); `DegeneretteModule` @1220-1230 (a Degenerette Reward draw —
    `poolBalance(Pool.Reward)` @1220, empty-pool early-return `if (poolBalance == 0) return` @1223,
    `transferFromPool(Pool.Reward, …)` @1229); `DegenerusGame.sol` @466-472 (a Game-level Reward consume).
- jackpot final-day `Pool.Reward` consolidation/deletion side-effects:
  - `DegenerusGameAdvanceModule.sol`: `_consolidatePoolsAndRewardJackpots(...)` definition @833, called @530;
    the `RewardJackpotsSettled` event @45 / emit @1015; the affiliate-top DGNRS reward `poolBalance =
    dgnrs.poolBalance(...)` @753, `dgnrsReward = (poolBalance * AFFILIATE_POOL_REWARD_BPS) / 10_000` @757
    (`AFFILIATE_POOL_REWARD_BPS = 100` @164), `poolBalance -= paid` @768, the per-level `AFFILIATE_DGNRS_LEVEL_BPS`
    draw @775; the BAF fire gate `if ((rngWord & 1) == 1)` @933 + the dispatch-table comment @1188-1189;
  - `DegenerusGameJackpotModule.sol`: the final-day / day-5-style terminal-jackpot bucket distribution
    `FINAL_DAY_SHARES_PACKED` (60/13/13/13) @224-265; the daily-jackpot solo-bucket whale-pass leg `true //
    jackpot phase (solo bucket gets whale pass)` @440; the fixed `[20,12,6,1]` purchase-phase distribution
    @493-521 (`purchase-phase distribution never reaches the solo whale-pass leg` @528); the quarter-share
    claimable credits @681-709.
  (NOTE the prior planning cites `@757-762` for the affiliate DGNRS reward and `@1047/1160` for the
  JackpotModule final-day whale-pass + DGNRS drift from the verified `@753-768` / `@224-265`/`@440`/`@493-528`
  — re-read at the frozen source.)
- Green oracle (for reference — NOT a substitute for tracing): `test/REGRESSION-BASELINE-v63.md` = forge
  854/0/110 (v51 empirical coverage carried from Phase 341: per-tier rewards / dedup / empty-pool /
  jackpot-final-day regression; freeze-safety + tier-precedence proven at SPEC 339). The POOL-CONSERVATION
  invariant net (FUZZ-05, carried from the v62 foundation) attests the multi-pool total is fully backed and
  transfers conserve.

## Concrete break-targets (the three v51 charge items — charge them HARD)

### 1. (LEGACY-03, PRIME — `claimBingo` / BingoModule freeze + tier-precedence + dedup + empty-pool + gameOver)

`claimBingo` (`BingoModule:114`) is documented as a strict READ-ONLY consumer of `traitBurnTicket` with
effects (the dedup bit @151 + the tier cascade bit-sets @167-176) BEFORE the interactions (`transferFromPool`
@189 + `creditFlip` @196). Find:

- **(i) any FREEZE break.** The `traitBurnTicket` ownership read (@130-136) consumes a trait population on
  the given level. Trace BACKWARD: is that population SNAPSHOTTED / pre-resolved (the traits resolve to
  `currentLevel + 5`) BEFORE the player can commit to which color-completion it holds, relative to the
  level's RNG word becoming public? Or can a player, AFTER the word is on-chain, still acquire/transfer the
  resolved ticket entries to assemble a now-known-favourable completion (re-verify the SPEC-339 freeze-safety
  claim IN CODE — do NOT trust the prior paper proof; enumerate what writes `traitBurnTicket[level]` and
  whether any is reachable after the level's word is revealed). Is there any bingo-draw ENTROPY in the reward
  selection that a player can grind (the tier is deterministic from `bingoFirsts` ordering — confirm there is
  no RNG in the draw that a player can re-roll)?
- **(ii) any TIER-PRECEDENCE error.** A quadrant-first claim must SUPPRESS the symbol bonus (quadrant-first =
  replacement `0.5% + 5_000e18`, not additive). Verify the `fq` quadrant mask @158 / `isQuadrantFirst =
  (fq & qMask) == 0` @160 / the both-bits-vs-symbol-bit-only logic @167-176 is computed correctly so a player
  cannot double-collect the symbol tier AND the quadrant tier (e.g. by ordering two claims so each observes a
  stale `bingoFirsts` and both bank a "first" bonus), and a symbol-first claim @174-176 preserves the
  co-resident quadrant mask (the `(bf & ~uint64(0xFFFFFFFF)) | …` masking @175 does not clobber the
  bits-[32:36) quadrant mask).
- **(iii) any DEDUP bypass.** The per-player `(level, quadrant)` dedup (@149-151) must reject a second
  `claimBingo` for the same `(level, quadrant)` at the `AlreadyClaimed` guard @150. Confirm the CEI ordering
  sets the bit @151 (and the tier bits @167-176) BEFORE the external `transferFromPool` @189 / `creditFlip`
  @196 — find ANY path where a reentrant `creditFlip` / `transferFromPool` callee re-enters `claimBingo` for
  the same `(level, quadrant)` before the bit is observed, or where two claims for different symbols in the
  same quadrant each pass the guard and both draw (the dedup is keyed on `quadrant`, not `symbol` — confirm
  that is the intended granularity and a player cannot multi-draw the regular tier per-symbol within one
  quadrant).
- **(iv) any EMPTY-POOL / gameOver edge.** Confirm the empty-Reward-pool path is a clean no-op (the
  `transferFromPool` clamp @189/`:548` returns 0, `creditFlip` @196 still safe / does not strand) and the
  `gameOver` cutoff @122 blocks a post-game claim. Confirm a claim that draws 0 from an empty pool still
  consumes the dedup bit (so it cannot be re-tried for a refund once the pool refills) OR — if the bit is set
  before a zero-draw — that this is intended (a claim against an empty pool forfeits the draw); state which.

VERIFIED SOUND requires the freeze snapshot (what writes `traitBurnTicket[level]` and that none is reachable
after the word is public) + the tier-precedence logic + the dedup bit + the CEI ordering cited.

### 2. (LEGACY-04a) sDGNRS `Pool.Reward` rebalance — split conservation + no over-draw

The v51 rebalance moved `AFFILIATE_POOL_BPS` 3500→3000 (`StakedStonk:309`) and `REWARD_POOL_BPS` 500→1000
(@311). Find:

- **(i) any conservation break.** Sum the pool BPS at the frozen source (`CREATOR 2000` @305, `WHALE 1000`
  @308, `AFFILIATE 3000` @309, `LOOTBOX 2000` @310, `REWARD 1000` @311, `PRESALE_BOX 1000` @312, plus
  ENUMERATE any other `Pool` enum member and confirm its BPS is 0 / accounted) and confirm the seeded pools
  sum to `BPS_DENOM = 10_000` so the genesis seeding (@384-408) neither over- nor under-allocates
  `INITIAL_SUPPLY`. Trace the `totalAllocated` dust handling @390-399: does the `if (totalAllocated <
  INITIAL_SUPPLY)` branch correctly absorb the residual (if the 6 sum to exactly 10_000 the dust is 0;
  confirm), and does ANY rounding in `(INITIAL_SUPPLY * BPS) / BPS_DENOM` per pool drop wei that strands
  unallocated supply or double-credits a pool?
- **(ii) any over-draw.** `transferFromPool` (@548) on the now-LARGER Reward pool (or the now-SMALLER
  Affiliate pool) must clamp to the pool balance and never over-spend; `transferBetweenPools` (@579) must not
  underflow the source pool. Confirm the `uint128` pool-balance narrowing @408 is safe for the rebalanced
  sizes (each ≤ `INITIAL_SUPPLY` 1e30 ≪ uint128 max).
- **(iii) any downstream assumption hard-coding the OLD 500/3500 split.** Grep for any consumer that computes
  a Reward (or Affiliate) draw against a stale BPS literal `500` / `3500` instead of reading the constant /
  the live `poolBalance` (e.g. an off-spine reward sizing that mis-scales because the pool grew/shrank).
  Confirm every Reward-pool consumer (`BingoModule:188-189`, `DegeneretteModule:1220-1229`,
  `DegenerusGame:466-472`, `AdvanceModule:753-775`) reads the live `poolBalance` rather than a hard-coded old
  split.

Confirm the new split conserves supply and every pool draw clamps, or surface a finding.

### 3. (LEGACY-04b) the jackpot final-day `Pool.Reward` deletion / draw side-effects

The final-day reward consolidation (`_consolidatePoolsAndRewardJackpots` @AdvanceModule:833, called @530) and
the affiliate-top DGNRS reward (`poolBalance * AFFILIATE_POOL_REWARD_BPS` @757, `poolBalance -= paid` @768,
the per-level `AFFILIATE_DGNRS_LEVEL_BPS` draw @775) + the JackpotModule terminal/final-day bucket
distribution (`FINAL_DAY_SHARES_PACKED` @224-265) + the daily-jackpot solo-bucket whale-pass leg @440 touch
`Pool.Reward` on the final day. Find:

- **(i) any STRANDED backing.** A Reward draw on the final-day path that DECREMENTS / zeroes the pool balance
  WITHOUT the corresponding value leaving (a `poolBalance -= paid` @768 where `paid` was clamped LOWER than
  the decrement, or a balance debited but the `transferFromPool` reverted/clamped to less), or vice versa (a
  transfer made but the balance not decremented). Trace the `paid` return of each `transferFromPool` vs the
  local `poolBalance -= paid` arithmetic @757-775 and confirm the local mirror tracks the actual transferred
  amount.
- **(ii) any DOUBLE-SPEND.** The same Reward backing consumed by BOTH the final-day consolidation AND a
  concurrent `claimBingo` / Degenerette Reward draw in the same advance window. Since `claimBingo` and the
  Degenerette draw both read a FRESH `poolBalance` and `transferFromPool` clamps, confirm the final-day
  consolidation cannot read a stale (pre-other-draw) balance and over-allocate; enumerate the ordering within
  the advance: does the consolidation run BEFORE or AFTER any same-block permissionless `claimBingo` /
  Degenerette draw, and can the interleaving let two draws each succeed against an overlapping balance?
- **(iii) any ORDERING hazard** where the final-day deletion runs before/after the per-level affiliate DGNRS
  reward @775 in a way that mis-sizes the draw (e.g. the per-level draw reads `poolBalance` after the
  consolidation already zeroed it, or before, producing a different amount than intended).

Anchor on the POOL-CONSERVATION invariant (FUZZ-05) but attack INDEPENDENTLY for any final-day path its
action set does not cover. Confirm the final-day Reward deletion conserves backing (Σ decrements == Σ
transferred, no overlap with concurrent draws), or surface a finding.

## Output (per item)

For each break-target AND each thesis point (LEGACY-03, LEGACY-04a, LEGACY-04b), state ONE of:

- **FINDING:** PROPERTY broken · reachable ordered CALL SEQUENCE (the multi-claim interleaving, the
  reentrant-callee re-entry, or the final-day-advance/concurrent-draw ordering — where the ordering matters) ·
  STATE VAR + `file:line` at `a8b702a7` · SEVERITY (per the threat priority above — a `claimBingo`
  freeze/steer break is DOMINANT; a `Pool.Reward` conservation / final-day strand-or-double-spend is SPINE; a
  CEI/reentrancy issue is confirmatory) · WHY the existing dedup-bit / clamp-to-available / CEI ordering /
  freeze-snapshot / BPS-sum-to-denominator does NOT stop it.
- **VERIFIED SOUND:** the property and the SPECIFIC reason it holds — cite the dedup bit, the
  clamp-to-available, the BPS-sum-to-denominator, the freeze snapshot (what writes `traitBurnTicket[level]`
  and that none is reachable after the word is public), the tier-precedence masking, or the CEI ordering — so
  the adjudicator can confirm your reasoning.

Do NOT pre-state a verdict you have not traced to source. Read the frozen tree at `a8b702a7` via
`git show`. The council finds; the adjudicator (Claude) reconciles at 394-04.
