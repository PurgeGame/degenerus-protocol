# 394-04 — NET 2 (the independent Claude adversarial net) — LEGACY-DEBT / the v51 surface slice (LEGACY-03, LEGACY-04)

**Subject (byte-frozen):** `a8b702a7` (contracts tree pin `2934d3d8987a09c5f073549a0cb499f6c5f28620`).
**Net:** NET 2 = the independent Claude adversarial net (the second-discipline net the both-nets-on-record
rule requires; AUDIT-V63-PLAN §2).
**Baseline (green oracle):** `test/REGRESSION-BASELINE-v63.md` = forge **854 / 0 / 110** (expected
forge-failure NAME-set strictly EMPTY). The sDGNRS pool-backing anchor is the BPS-sum + clamp proof below;
the ETH prize-pool conservation anchor is `PoolConservation.inv.t.sol` (FUZZ-05).
**Posture:** AUDIT-ONLY — read-only over the frozen subject. Every source line was read via
`git show a8b702a7:contracts/<File>.sol` (the working tree was ignored). No contract source is touched; any
CONFIRMED finding is DOCUMENTED + ROUTED, never fixed here.
**Threat weighting (§4):** the bingo `traitBurnTicket` freeze read = DOMINANT (RNG/freeze); the sDGNRS
`Pool.Reward` rebalance + the jackpot final-day deletion = SPINE (solvency); access / reentrancy / timing =
confirmatory.
**Discipline:** this net was run INDEPENDENTLY of the council — every attack below was attacked against the
frozen source FIRST; the NET-1 council leads (`394-02-COUNCIL-NET.md` + `council/v51.codex.txt`) are folded
in at §6 at the END, with the convergence/divergence noted per item. No CONFIRMED break was found.

---

## 0. Byte-freeze pre-check (read-only over the frozen subject)

- `git diff a8b702a7 -- contracts/` → **EMPTY** (0 diff lines) at the start of this net.
- `git status --porcelain` shows only the pre-existing untracked `PLAYER-PURCHASE-REWARDS.html` (unrelated;
  left untouched). All source reads used `git show a8b702a7:`. Hardhat was NEVER invoked (the
  ContractAddresses-regeneration landmine avoided).

---

## 1. LEGACY-03a — claimBingo FREEZE-safety (DOMINANT — backward-trace re-verified IN CODE)

**PROPERTY.** The `traitBurnTicket[level]` population that `claimBingo` reads must be a PRE-RESOLVED /
snapshotted set, frozen relative to the level's VRF word — so no player action can steer which bucket
membership the read consumes after that level's word is public.

**Attack tried.** Construct a reachable call sequence where a player, AFTER the level's word is revealed,
appends themselves (or another address) into `traitBurnTicket[level][traitId]` to change the bingo
ownership/eligibility set — i.e. find ANY post-word writer of `traitBurnTicket[level]` reachable by a
player, then race it against the public word.

**Backward-trace — every writer of `traitBurnTicket` enumerated at the frozen source
(`git grep -n traitBurnTicket a8b702a7`):**

| Site | `file:line` | Kind | Reachable post-word by a player? |
|---|---|---|---|
| `claimBingo` ownership read | `BingoModule:135-141` | **READ-ONLY** (`storage levelBuckets`; only `.length` / `[slot]`) | n/a — never writes |
| jackpot draw core `_randTraitTicket` | `JackpotModule:1442/1464/1489/1633/949/635` | **`view` READ** (winner selection over the bucket) | n/a — `view`, no write |
| decimator source read | `JackpotModule:886` | **READ** (passes the storage ref into the `view` selector) | n/a — no write |
| **ticket-resolution append** | **`MintModule:_raritySymbolBatch` @721, body @789-812** (the assembly batch-`sstore`) | **WRITE (the SOLE append path)** | **NO — see the freeze gate below** |

So `traitBurnTicket[level]` has exactly ONE writer: `_raritySymbolBatch` (the assembly batch-write that
`sstore`s the resolved holder address `occurrences` times into `traitBurnTicket[lvl][traitId]`, `:789-812`).

**Freeze gate on the sole writer (the snapshot provenance that settles it).** `_raritySymbolBatch` is called
ONLY from the ticket-resolution drain paths (`MintModule:637`, `:993`), which drain the **read buffer** of the
double-buffered ticket queue. The buffer discipline:
- `_swapTicketSlot` (`Storage:780-784`) flips `ticketWriteSlot` and **reverts if the read slot is not drained**
  (`if (ticketQueue[rk].length != 0) revert E();`), and resets `ticketsFullyProcessed = false`.
- `_swapAndFreeze` (`Storage:793-805`) calls `_swapTicketSlot` THEN sets `prizePoolFrozen = true`, and it is
  invoked on the daily-RNG path (`AdvanceModule:389`) — i.e. the swap+freeze happens as the level's word is
  requested. The resolution then drains the FROZEN read buffer; far-future ticket sales revert during the RNG
  lock (`MintModule:1214` `if (rngLockedFlag) revert RngLocked();`).

Therefore: by the time a level's word is public, that level's `traitBurnTicket` bucket membership is the
resolved output of draining a buffer that was swapped/frozen BEFORE the word — there is no player-reachable
append into `traitBurnTicket[level]` after the word lands. The `claimBingo` read (`:135-141`) is over a frozen
population. This is the SPEC-339 freeze re-verified IN CODE by the backward-trace, not trusted from the paper
proof.

**Extra hardening observed (tighter than the prompt's model).** `claimBingo` is strictly `msg.sender`-only —
it uses `msg.sender` directly for the ownership check (`:140`), the dedup (`:149-151`), and the payout
(`:191`/`:196`). There is NO `player` argument and NO operator path on `claimBingo`; the `NotApproved` /
`_resolvePlayer` operator-resolution (`:267-275`) belongs to the SEPARATE `claimAffiliateDgnrsReward`
(`:219-264`), not to `claimBingo`. So there is no operator-impersonation surface on the bingo claim at all.

**State var + cite:** `traitBurnTicket` def `Storage:441`; the read `BingoModule:135-141`; the sole writer
`MintModule:789-812`; the freeze gate `Storage:780-805` + `AdvanceModule:389`; the RNG-lock on far-future
sale `MintModule:1214`.

**Provisional verdict — REFUTED (RNG-freeze-safe; the read is over a frozen, pre-resolved population).**

---

## 2. LEGACY-03b — tier-precedence + per-player (level,quadrant) dedup + CEI + empty-pool + gameOver

### (i) TIER-PRECEDENCE — attack a double-collect of the symbol + quadrant tier

**Attack tried.** Find a path where a single player collects BOTH the symbol-first bonus AND the
quadrant-first replacement for the same `(level, quadrant)` — i.e. the precedence is computed so that a
quadrant-first does NOT suppress the symbol bonus, or a later symbol-first re-pays after a quadrant-first.

**Result — REFUTED.** The cascade (`BingoModule:153-176`) reads `bf = bingoFirsts[level]` once, splits it into
`fq = uint8(bf >> 32)` (quadrant mask, bits [32:36)) and `fs = uint32(bf)` (symbol mask, bits [0:32)), then:
- **quadrant-first** (`(fq & qMask) == 0`) is checked FIRST and, in ONE packed write, marks BOTH the symbol
  bit and the quadrant bit: `bingoFirsts[level] = uint64(uint32(fs | sMask)) | (uint64(uint8(fq | qMask)) <<
  32)` (`:166-169`). Because it sets `sMask` too, a subsequent claim on the same symbol finds `isSymbolFirst
  == false` — the symbol bonus is SUPPRESSED. It pays the replacement tier (`FIRST_QUADRANT_*`), not additive.
- **symbol-first** (`(fs & sMask) == 0`, only reached if NOT quadrant-first) marks ONLY the symbol bit while
  preserving the co-resident quadrant mask: `bingoFirsts[level] = (bf & ~uint64(0xFFFFFFFF)) | uint64(fs |
  sMask)` (`:174`). The `& ~uint64(0xFFFFFFFF)` keeps the high 32 bits (the quadrant mask) intact, so a later
  quadrant-first on that quadrant still fires.
- otherwise the **regular** tier pays (`REGULAR_*`).

The ordering (quadrant-first checked before symbol-first) + the both-bits write on the quadrant branch is the
double-pay-trap guard. No path pays symbol+quadrant for the same `(level, quadrant)`. **REFUTED.**

### (ii) per-player (level,quadrant) DEDUP + CEI — attack a reentrant or repeated re-claim

**Attack tried.** (a) Re-call `claimBingo(level, symbol, slots)` twice for the same `(level, quadrant)` to
double-draw the Reward pool. (b) REENTER `claimBingo` from inside the external calls (`transferFromPool` at
`:189-193` or `creditFlip` at `:196`) BEFORE the dedup/tier bits are durable, to re-claim within one tx.

**Result — REFUTED (CEI-tight).** The dedup is an EFFECT set BEFORE any interaction:
- `claimedBits = bingoClaimed[level][msg.sender]` (`:149`); `if (claimedBits & qMask != 0) revert
  AlreadyClaimed();` (`:150`); `bingoClaimed[level][msg.sender] = claimedBits | qMask;` (`:151`) — the dedup
  bit is written at `:151`, and the tier bits at `:166-169`/`:174`, ALL strictly before the external calls at
  `:188-196`.
- So a straight re-call (a) reverts at `:150` (`AlreadyClaimed`). A reentrant re-call (b) — even if
  `transferFromPool`/`creditFlip` could call back (sDGNRS / coinflip are protocol contracts, not attacker
  code; but assume the worst) — would re-enter `claimBingo`, read `bingoClaimed[level][msg.sender]` with
  `qMask` ALREADY set, and revert at `:150`. Effects-before-interactions closes the reentrancy window. The
  module doc states the CEI doctrine explicitly (`:19-22`). **REFUTED.**

### (iii) EMPTY-POOL no-op — attack a strand/revert that burns the dedup bit without paying

**Attack tried.** Drain `Pool.Reward` to 0, then claim — does the draw revert (stranding the now-set dedup
bit so the player can never re-claim even when the pool refills) or mis-credit?

**Result — REFUTED (graceful no-op).** `transferFromPool` returns 0 on an empty pool without reverting (`if
(available == 0) return 0;` `StakedStonk:553`; `if (amount > available) amount = available;` `:556`). The
draw amount `(poolBal * dgnrsBps)/10_000` is 0 when `poolBal == 0`, and `transferFromPool` short-circuits on
`amount == 0` too (`:550`). So an empty Reward pool consumes the bingo bit (the claim is one-shot per the
design — bingo is a first-completion reward, the dedup is permanent by intent) and pays ONLY the BURNIE flip
credit (`creditFlip` is always reached, `:196`; the tier BURNIE is always non-zero). No revert, no strand of
unpaid ETH/stETH, no double-credit. **REFUTED.** (This matches the module doc `:15-17`: an empty pool → the
draw is a no-op, BURNIE still paid.)

### (iv) gameOver cutoff — attack a post-game claim

**Result — REFUTED.** `if (gameOver) revert E();` (`:122`) is the first guard; a post-game claim reverts. The
absence of a level upper-bound guard is BY-DESIGN ([[claimbingo-no-level-guard]]): the 8-color ownership
check (`:137-145`) self-gates — an unresolved/future-level bucket is empty, so `slot >= holders.length`
fails closed with `NotSlotOwner`. Not re-litigated; verified the self-gate holds.

**Provisional verdict (LEGACY-03b) — REFUTED on all four sub-properties (tier-precedence, dedup+CEI,
empty-pool no-op, gameOver). LEGACY-03 overall: REFUTED — `claimBingo` is freeze-safe + CEI-tight +
tier-correct + dedup-sound.**

---

## 3. LEGACY-04a — sDGNRS Pool.Reward rebalance (SPINE — split-conservation, re-summed at source)

**PROPERTY.** The v51 rebalance (AFFILIATE 3500→3000, REWARD 500→1000) must conserve the genesis split — the
named BPS slices must still sum to `BPS_DENOM` so the genesis seeding allocates `INITIAL_SUPPLY` exactly with
no over-/under-allocation — and no Reward draw may over-draw past the (now larger) Reward pool or rely on a
stale BPS.

**Split-conservation — the 8-BPS sum re-summed at the frozen source (`StakedStonk:305-312`):**

| Allocation | BPS | cite |
|---|---|---|
| CREATOR | 2000 | `:305` `CREATOR_BPS` |
| WHALE_POOL | 1000 | `:308` `WHALE_POOL_BPS` |
| AFFILIATE_POOL | **3000** (was 3500) | `:309` `AFFILIATE_POOL_BPS` |
| LOOTBOX_POOL | 2000 | `:310` `LOOTBOX_POOL_BPS` |
| REWARD_POOL | **1000** (was 500) | `:311` `REWARD_POOL_BPS` |
| PRESALE_BOX_POOL | 1000 | `:312` `PRESALE_BOX_POOL_BPS` |
| **SUM** | **10000 == `BPS_DENOM` (`:302`)** | exact |

`2000 + 1000 + 3000 + 2000 + 1000 + 1000 = 10000`. The rebalance is internal to the AFFILIATE/REWARD pair
(−500 / +500); the sum is invariant. The `Pool` enum has exactly 5 members (`Whale, Affiliate, Lootbox,
Reward, PresaleBox`, `:241-247`) — no stray enum member carries a non-zero BPS off the 6 named constants
(CREATOR is the off-pool creator mint, not a `Pool` member).

**Genesis seeding conserves INITIAL_SUPPLY (`:384-408`).** Each amount is `(INITIAL_SUPPLY * BPS)/BPS_DENOM`.
`INITIAL_SUPPLY = 1e30` is divisible by `BPS_DENOM = 10_000` (`1e30 / 1e4 = 1e26`, an exact integer), so each
slice is exact and `totalAllocated == INITIAL_SUPPLY` — the dust branch `if (totalAllocated < INITIAL_SUPPLY)`
(`:391-397`) is a NO-OP at these constants (dust == 0). The five pool balances are seeded to their exact
slices (`:404-408`), `Pool.Reward = rewardAmount` (`:408`). The `uint128` narrowing is safe: every slice ≤
`INITIAL_SUPPLY = 1e30` ≪ `2^128 − 1 ≈ 3.4e38`.

**No-over-draw — attack each Reward consumer for an over-draw past the now-larger pool / a stale-split
hard-code.** Every `Pool.Reward` consumer at the frozen source reads the LIVE `poolBalance(Pool.Reward)` and
routes through the clamping `transferFromPool`, and each guards `poolBalance == 0` first:
- **Bingo** `BingoModule:188-193` — `poolBal = dgnrs.poolBalance(Pool.Reward)`; draw `(poolBal *
  dgnrsBps)/10_000`; `transferFromPool` clamps.
- **Degenerette** `DegeneretteModule:1220-1232` — `poolBalance = sdgnrs.poolBalance(Pool.Reward)`; `if
  (poolBalance == 0) return;`; reward `(poolBalance * bps * cappedBet)/(10_000 * 1 ether)`; `transferFromPool`.
- **coinflip bounty** `DegenerusGame.sol:465-475` — `poolBalance = dgnrs.poolBalance(Pool.Reward)`; `if
  (poolBalance == 0) return;`; payout `(poolBalance * COINFLIP_BOUNTY_DGNRS_BPS)/10_000`; `transferFromPool`.

`transferFromPool` (`:548-570`) clamps: `if (available == 0) return 0;`, `if (amount > available) amount =
available;`, then `unchecked { poolBalances[idx] = uint128(available - amount); }` — the decrement is bounded
by `available`, so NO underflow / over-draw is possible regardless of the requested amount.
`transferBetweenPools` (`:579-593`) clamps identically. NO consumer hard-codes the old 500/3500 split — every
draw is computed against the LIVE pool balance, so the rebalance is automatically respected; there is no stale
BPS consumer to break.

**State var + cite:** `poolBalances` `StakedStonk:253`; BPS `:305-312`; `BPS_DENOM` `:302`; genesis `:384-408`;
clamps `:548-570` / `:579-593`; consumers `BingoModule:188-193`, `DegeneretteModule:1220-1232`,
`DegenerusGame.sol:465-475`.

**Provisional verdict — REFUTED. The rebalance conserves the split (sum = 10000 = BPS_DENOM), the genesis
seeding is exact (no dust), every draw clamps to the live pool, and no consumer carries a stale split.**

---

## 4. LEGACY-04b — jackpot final-day Pool.Reward deletion (SPINE — the PRIORITY: is the premise vacuous?)

**PROPERTY (as charged).** The jackpot final-day reward consolidation must not STRAND backing (a Reward
balance deleted without the value leaving, or vice-versa) or DOUBLE-SPEND (the same Reward backing consumed by
both the final-day consolidation AND a concurrent claimBingo/Degenerette Reward draw).

**The priority — GREP-ENUMERATE every `Pool.Reward` reference across the frozen contract source
(`git grep -n -E 'Pool\.Reward|poolBalances\[' a8b702a7 -- 'contracts/*.sol'`):**

`Pool.Reward` (the sDGNRS reward pool) appears at EXACTLY these sites — and NOWHERE else:

| # | `file:line` | Kind |
|---|---|---|
| 1 | `StakedStonk:408` | genesis seed `poolBalances[uint8(Pool.Reward)] = uint128(rewardAmount)` |
| 2 | `StakedStonk:311` / `:389` | the `REWARD_POOL_BPS` constant + the seed-amount derivation |
| 3 | `BingoModule:15` / `:48` | doc comments (the 0.05% Pool.Reward draw description) |
| 4 | `BingoModule:188` / `:190` | the bingo Reward draw (read + `transferFromPool`) |
| 5 | `DegeneretteModule:1221` / `:1230` | the Degenerette Reward draw (read + `transferFromPool`) |
| 6 | `DegenerusGame.sol:466` / `:472` | the coinflip bounty Reward draw (read + `transferFromPool`) |

**THE PREMISE IS VACUOUS — there is NO final-day `Pool.Reward` deletion/draw path at all.** `Pool.Reward`
appears ONLY in genesis seeding + the three live draws (Bingo, Degenerette, coinflip bounty). It does NOT
appear in `DegenerusGameAdvanceModule.sol` and does NOT appear in `DegenerusGameJackpotModule.sol`:
- `git grep -n -E 'Pool\.Reward|transferFromPool|poolBalance' a8b702a7 -- AdvanceModule.sol` → the ONLY pool
  draw in AdvanceModule is `_rewardTopAffiliate` (`:753-775`), and it targets **`Pool.Affiliate`** (`:754`),
  NOT `Pool.Reward` — `dgnrs.poolBalance(Pool.Affiliate)` (`:753-755`) → `dgnrs.transferFromPool(Pool.Affiliate,
  top, dgnrsReward)` (`:759-763`). Confirmed: the AUDIT-V63-PLAN interface cite that pointed the "final-day
  Reward deletion" at `AdvanceModule:753-775` actually refers to an AFFILIATE-pool draw, not a Reward-pool
  draw.
- `git grep -n -E 'Pool\.Reward|transferFromPool|poolBalance' a8b702a7 -- JackpotModule.sol` → **(none).** The
  jackpot module never touches any sDGNRS pool.

**What the jackpot final-day path actually mutates (the real surface).** The final-day jackpot/consolidation
code mutates the ETH prize-pool state (`currentPrizePool` / `claimablePool` / `prizePoolsPacked` /
`futurePrizePool`, `Storage:354-379`), NOT the sDGNRS token `poolBalances`. The solo-bucket "final day" path
(`JackpotModule:_handleSoloBucketWinner @1183` → `_processSoloBucketWinner`) pays **75% ETH credited to
claimable + 25% converted to whale passes** (moved to `futurePrizePool`) — NO `Pool.Reward` / `transferFromPool`
/ sDGNRS-token mutation anywhere in that path.

**The "DGNRS on final day" comments are STALE (folding the council's stale-comment lead).** Two comments —
`JackpotModule:1047` ("Solo bucket gets whale pass + DGNRS on final day") and `:1160` ("Solo bucket (jackpot
phase): whale pass + DGNRS on final day") — describe a `Pool.Reward`/DGNRS transfer the frozen code path does
NOT implement (the solo bucket pays ETH + whale passes only). These are STALE COMMENTS, NOT a correctness
defect (the code is the authority; no value moves). Per [[feedback_no_history_in_comments]] /
[[lean-code-comments-no-procedural-meta]] this is a doc-hygiene item — INFO/doc-only, deferred (the subject is
byte-frozen during the sweep; any comment fix is a non-contract edit deferred to a post-audit hygiene pass).

**Backing-conservation of the ETH final-day path (the substantive LEGACY-04b verdict).** Since the real
final-day surface is the ETH prize-pool (not sDGNRS Reward), the conservation question reduces to the ETH
final-day accounting, which is the SOLVENCY-spine surface already owned by Phase 390 + `PoolConservation.inv.t.sol`
(FUZZ-05): the four ETH pools (`currentPrizePool + nextPrizePool + futurePrizePool + claimablePool`) are
fully backed by `balance + stETH` and never inflate beyond real inflow. The final-day jackpot decrements
`currentPrizePool` by the budget, credits `claimablePool` for the paid winners, and moves the whale-pass
portion into `futurePrizePool` — a RESHAPE across the four pools, not an unbacked mint. This is the FUZZ-05
property and is GREEN at the subject (854/0/110). The sDGNRS `Pool.Reward` is untouched on the final day, so
there is NO stranded sDGNRS backing and NO double-spend against a concurrent Bingo/Degenerette draw — those
draws read the live Reward balance and clamp, independent of the ETH final-day path.

**No double-spend across concurrent Reward draws (independent attack).** Even setting the final-day path
aside: two concurrent Reward draws (e.g. a Bingo claim and a Degenerette resolve in the same block) each read
the FRESH `poolBalance(Pool.Reward)` and route through the clamping `transferFromPool` — same-block ordering is
EVM-sequenced, so the second draw reads the balance already decremented by the first; the clamp guarantees the
sum of draws never exceeds the seeded Reward pool. No stale-overlap window, no over-draw.

**State var + cite:** the `Pool.Reward` enumeration (the 6 sites above); the AdvanceModule affiliate draw
targets `Pool.Affiliate` `AdvanceModule:753-763`; the jackpot module has zero sDGNRS pool touch (grep empty);
the solo-bucket ETH/whale-pass path `JackpotModule:1183` → `_processSoloBucketWinner`; the ETH prize-pool
state `Storage:354-379`; the FUZZ-05 ETH conservation anchor `PoolConservation.inv.t.sol`.

**Provisional verdict — REFUTED, premise VACUOUS.** There is NO sDGNRS `Pool.Reward` final-day deletion/draw
path in code — the LEGACY-04b break-target premise does not hold. The real final-day surface is the ETH
prize-pool consolidation, whose backing-conservation is attested by FUZZ-05 (green) + the 390 SOLVENCY spine.
Plus an INFO doc-hygiene item: the two STALE "DGNRS on final day" comments (`JackpotModule:1047`/`:1160`).

---

## 5. Skeptic dual-gate (run before any CATASTROPHE/HIGH)

Nothing in this slice reaches a CONFIRMED break, so nothing reaches the HIGH bar — but per the standing
posture ([[feedback_skeptic_pass_before_catastrophe]]) the dual-gate was applied to the three value-bearing
items (the DOMINANT freeze read + the two SPINE conservation surfaces) to confirm none is an under-weighted
HIGH:

- **The bingo `traitBurnTicket` freeze read (DOMINANT).** Structural protection: the sole writer runs in the
  swapped/frozen read buffer before the word; the read is over a frozen population. EV lens: (1) value
  gained/lost from steering the read — NONE (no post-word append exists); (2) direction — n/a (no steering
  surface); (3) player-steerable edge — NONE. Gate FAILS for HIGH → REFUTED (RNG-freeze holds).
- **The sDGNRS Pool.Reward rebalance (SPINE).** Structural protection: BPS sum = 10000 = BPS_DENOM; the clamp
  bounds every draw. EV lens: (1) value — NONE (no over-draw possible; the split is conserved); (2) direction
  — n/a; (3) edge — NONE. Gate FAILS for HIGH → REFUTED.
- **The jackpot final-day deletion (SPINE).** Structural protection: the premise is VACUOUS (no sDGNRS Reward
  final-day path); the real ETH final-day path is FUZZ-05-conserved + green. EV lens: (1) value — NONE (no
  stranded/double-spent sDGNRS backing; the ETH reshape is backed); (2) direction — n/a; (3) edge — NONE.
  Gate FAILS for HIGH → REFUTED (premise vacuous).

**Result: NOTHING reaches HIGH/CATASTROPHE.** All three value-bearing items are structurally protected with no
EV edge. The only non-REFUTED outputs are document-only (the two stale comments).

---

## 6. Council fold-in (NET 1 — `394-02-COUNCIL-NET.md` + `council/v51.codex.txt`, read AFTER the independent pass)

Read AT THE END of the independent pass, per the dual-net discipline. The council had **`codex` on record
with a full traced audit = 0 findings (all three break-targets VERIFIED SOUND)**; **`gemini` is in `skipped[]`**
(non-responsive — no output within an 8-min hard cap ×2; carried to 396 for a post-responsive second-source).

| Item | NET 2 (Claude, this net) | NET 1 (codex) | Convergence |
|---|---|---|---|
| LEGACY-03a freeze | REFUTED (backward-trace: sole writer `MintModule:789-812` runs in the swapped/frozen read buffer; far-future sale rng-locked `:1214`) | VERIFIED SOUND (same writer + `_swapTicketSlot`/`_swapAndFreeze` + the lootbox-index advance before the word) | **CONVERGENT** — codex adds the lootbox-index-advance cites (`AdvanceModule:1136-1151`/`:1689-1699`); NET 2 adds the `claimBingo`-is-msg.sender-only (no operator path) hardening |
| LEGACY-03b tier/dedup/CEI/empty/gameOver | REFUTED (CEI bits @151/166-169/174 before calls @188-196; quadrant-first suppresses symbol; empty-pool clamp no-op; gameOver @122) | VERIFIED SOUND (same bit ordering + clamp + gate) | **CONVERGENT** |
| LEGACY-04a Pool.Reward rebalance | REFUTED (sum 10000 = BPS_DENOM; 1e30 ÷ 1e4 exact, dust no-op; clamp; no stale-split consumer) | VERIFIED SOUND (same sum + `INITIAL_SUPPLY` divisible + clamp + no hard-coded old split) | **CONVERGENT** |
| LEGACY-04b final-day deletion | REFUTED, **premise VACUOUS** (no sDGNRS Reward final-day path; AdvanceModule affiliate draw targets `Pool.Affiliate`; JackpotModule has zero sDGNRS touch; real surface = ETH pools, FUZZ-05-conserved) | VERIFIED SOUND — **codex independently found NO final-day Reward path** (the most material refinement); flagged the stale `JackpotModule:1047` comment | **CONVERGENT** — both nets independently land on "the premise does not hold; there is no final-day sDGNRS Reward deletion." NET 2 additionally pins the AdvanceModule draw to `Pool.Affiliate` and confirms zero sDGNRS touch in JackpotModule |
| stale "DGNRS on final day" comment | INFO/doc-hygiene (`JackpotModule:1047` AND `:1160`) | flagged `:1047` as stale-vs-code | **CONVERGENT** — NET 2 finds the SECOND stale site (`:1160`) too |

**No DIVERGENT council lead.** codex's leads are convergent-with-design SOUND anchors; NET 2 reaches the same
verdicts independently and adds (a) the `claimBingo`-msg.sender-only hardening, (b) the `Pool.Affiliate` pin on
the AdvanceModule draw, (c) the second stale-comment site `:1160`. The `gemini` second-source is owed → 396.

---

## 7. Byte-freeze attestation (after this net)

- `git diff a8b702a7 -- contracts/` → **EMPTY** at the END of this net (subject byte-frozen; NET 2 read all
  source via `git show a8b702a7:`, wrote only this `.planning/` doc).
- `git status --porcelain` → only the pre-existing untracked `PLAYER-PURCHASE-REWARDS.html` (unrelated; not
  produced by this net). T-394-11 (tampering of the byte-frozen subject) mitigation satisfied.
- Hardhat was never invoked (the ContractAddresses-regeneration landmine avoided).

---

## 8. NET-2 provisional verdict roll-up (v51 slice)

| Item | Provisional verdict | Settling cite (`a8b702a7`) |
|---|---|---|
| **LEGACY-03a** claimBingo freeze | **REFUTED** (RNG-freeze-safe) | sole writer `MintModule:789-812` in the swapped/frozen read buffer (`Storage:780-805`, `AdvanceModule:389`); rng-lock `MintModule:1214`; read-only `BingoModule:135-141` |
| **LEGACY-03b** tier/dedup/CEI/empty/gameOver | **REFUTED** (CEI-tight, tier-correct) | dedup `BingoModule:149-151`; tier `:153-176`; calls `:188-196`; clamp `StakedStonk:548-570`; gameOver `:122` |
| **LEGACY-04a** Pool.Reward rebalance | **REFUTED** (split conserved, no over-draw) | BPS sum 10000=`BPS_DENOM` `StakedStonk:302-312`; genesis `:384-408`; clamp `:548-570`; live-balance consumers |
| **LEGACY-04b** jackpot final-day deletion | **REFUTED — premise VACUOUS** + INFO doc-hygiene | no `Pool.Reward` in Advance/Jackpot; affiliate draw = `Pool.Affiliate` `AdvanceModule:753-763`; ETH path FUZZ-05-conserved; stale comments `JackpotModule:1047`/`:1160` |

**NET 2 is on record for the v51 slice, independent of the council, with a per-item attack + provisional
verdict. 0 CONFIRMED contract findings; 1 INFO doc-hygiene item (the two stale comments). Both nets converge
SOUND. The subject stays byte-frozen.**
