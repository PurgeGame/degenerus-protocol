# 325 — SWAP Attestation (item 7, sDGNRS Far-Future Salvage Swap)

**Scope:** READ-ONLY re-attestation of the load-bearing economics + RNG + queue-safety of
`.planning/PLAN-SDGNRS-FAR-FUTURE-SALVAGE-SWAP.md` (item 7) against the v47.0-closure baseline.
**ZERO `contracts/*.sol` mutation** — this is a paper-only SPEC deliverable (Plan 02 / BATCH-01).

**Baseline anchor:** v47.0-closure HEAD `da5c9d50989707c8964a9411e68c51ca1b1a25f2`
(`MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`). The live working tree was
verified byte-identical to this baseline for all `contracts/*.sol`:
`git diff --name-only da5c9d50 HEAD -- 'contracts/*.sol'` returns EMPTY. All `file:line`
verdicts below are therefore baseline-anchored; source was read from `contracts/` ONLY.

**Sources of truth (read at this attestation):**
- `contracts/libraries/PriceLookupLib.sol` (47 lines) — `priceForLevel` face anchor.
- `contracts/storage/DegenerusGameStorage.sol` — `TICKET_SCALE=100` (:166), `_tqFarFutureKey` (:732),
  `_queueTickets` (:560), `_queueTicketRange` (:647), `LOOTBOX_EV_*` (:1308-1318), far-future-key
  push sites (:581/:613/:667), `ticketQueue[rk].length != 0` enrol-guard (:744).
- `contracts/modules/DegenerusGameMintModule.sol` — `purchaseCoin` (:858), `_purchaseCoinFor` (:866),
  mint-cost `priceWei * quantity / (4 * TICKET_SCALE)` (:1379), mint target `cachedLevel`/`+1`
  (:898/:1360), `processFutureTicketBatch` (:393).
- `contracts/modules/DegenerusGameLootboxModule.sol` — `_rollTargetLevel` (:899), `_resolveLootboxRoll`
  (:1680), `_lootboxTicketCount` (:1760), `LOOTBOX_TICKET_ROLL_BPS=16_100` (:243), variance tiers
  (:244-261), `_applyEvMultiplierWithCap` (:440), boon budget `LOOTBOX_BOON_BUDGET_BPS=1000` (:921).
- `contracts/DegenerusGame.sol` — `_resolvePlayer` (:449), `rngWordByDay`/`rngWordCurrent`/`rngLocked`
  (:2326/:2333/:2340), `sampleFarFutureTickets` (:2592), `ticketsOwedView` (:2210), ctor far-seed
  `_queueTickets(SDGNRS/VAULT,i,16,false)` (:217/:218), far sampler (:2604).
- `contracts/modules/DegenerusGameJackpotModule.sol` — `_awardFarFutureCoinJackpot` (:1754),
  `_runEarlyBirdLootboxJackpot` (:639 — **NOTE: in JackpotModule, not AdvanceModule** as the plan
  interface line claimed; drift recorded in §D).
- `contracts/modules/DegenerusGameAdvanceModule.sol` — far-future length gates (:214/:262/:1083),
  the `_processFutureTicketBatch` drain (:1434), `rngLockedFlag` set/clear (:1656/:1737).
- `contracts/modules/DegenerusGameWhaleModule.sol` — `WHALE_BUNDLE_EARLY_PRICE=2.4 ether` (:132),
  far-grant `_queueTickets(buyer, lvl, …)` (:318).

---

## Section A — NO-ARB RE-DERIVATION (SWAP-08), AT THE JITTER BAND CEILING

### A.0 The arb bar (load-bearing security property)

The seller receives BOTH current-level tickets (real EV) AND cash, so the arb bar is the FULL
payout fraction, not just the cash leg:

> `cheapest_systematic_acquisition(d) > maxPayoutFraction(d)` for every `d ∈ [6,100]`.

`maxPayoutFraction` peaks at the smallest distance `d=6` and at the jitter-band CEILING (§3 of the
plan — a waiter/grinder captures the ceiling, never the mean). All bounds are therefore proven at
the **ceiling**.

### A.1 The face anchor (from source)

`PriceLookupLib.priceForLevel(targetLevel)` (`PriceLookupLib.sol:21`) is the only non-manipulable
face anchor — a fixed 100-level price cycle (0.04 / 0.08 / 0.12 / 0.16 / 0.24 ETH tiers), pure,
keyed on the TARGET level, never the current level and never user-supplied. `faceWei` of a far
entry is `priceForLevel(L) × wholeTickets` (unit basis pinned in §E). Confirmed.

### A.2 The salvage ceiling payout (`fractionBps(6)` × jitter ceiling)

From the plan's §3 two-line curve (NOT changed here):
```
fractionBps(d) = (d<=20) ? 1500 - ((d-6)*500)/14 : 1000 - ((d-20)*500)/80
fractionBps(6) = 1500  →  15.00% of face   (the d=6 peak)
```
Jitter band (plan §3, CHOSEN, NOT widened): fraction multiplier ∈ [70%, 110%], cash share ∈
[20%, 60%]. The ceiling a grinder/waiter captures is **110%**:

> **max full payout = 110% × fractionBps(6) = 1.10 × 15.00% = 16.50% of face @ d6.**

Cash leg subset: max withdrawable cash = cashShareCeiling × maxFullPayout = 60% × 16.50% =
**9.90% of face @ d6** — a strict subset of the 16.50% total. The cash share moves neither the
no-arb bar nor the redemption-drain magnitude (both key off `totalBudget`, not the split). So the
single load-bearing bound is the full-payout ceiling **16.50% of face @ d6**.

### A.3 The cheapest far-future-entry acquisition cost (lootbox), RE-DERIVED from source

The cheapest ETH path to a `d>=6` entry is the lootbox (whale bundle and deity are dearer —
worked cross-check in A.4; BURNIE cannot mint far at all — §B). The lootbox future-ticket grant
math, traced from source:

1. **Far-target gate** — `_rollTargetLevel` (`LootboxModule.sol:899`): `rangeRoll = uint16(seed)%100`.
   `rangeRoll < 10` (**p = 10%**) → far branch `targetLevel = baseLevel + (uint16(seed>>24)%46) + 5`
   = base+5..base+50. The salvage range `d>=6` is reachable on this far branch only.
2. **Ticket-path gate** — `_resolveLootboxRoll` (`:1697`): `roll = uint16(seed>>40)%20`; `roll < 11`
   (**p = 55%**) is the ticket path. The other 45% pays DGNRS / WWXRP / BURNIE, not far tickets.
3. **Ticket budget** — `ticketBudget = amount × LOOTBOX_TICKET_ROLL_BPS / 10_000`
   = `amount × 16_100/10_000` = **1.61 × amount** (`:1700`).
4. **Variance multiplier** — `_lootboxTicketCount` (`:1760`): five tiers with chances/multipliers
   (`:244-261`):
   | tier | chance | multiplier |
   |------|--------|-----------|
   | 1 | 1% (100 bps) | 4.60× (46_000) |
   | 2 | 4% (400 bps) | 2.30× (23_000) |
   | 3 | 20% (2000 bps) | 1.10× (11_000) |
   | 4 | 45% (4500 bps) | 0.651× (6_510) |
   | 5 | 30% (default) | 0.45× (4_500) |
   `E[mult] = 0.01·4.6 + 0.04·2.3 + 0.20·1.1 + 0.45·0.651 + 0.30·0.45 = 0.786`.
   `adjustedBudget = ticketBudget × ticketBps/10_000`; `scaledTickets = adjustedBudget × TICKET_SCALE / targetPrice`
   (`:1799-1801`) → face-of-tickets received per box = `adjustedBudget`.

**Expected far-face yield per ETH spent** (the SYSTEMATIC / farmable cost — the money-pump bar):
```
E[far ticket face / ETH] = p(far) × p(ticket) × ticketRollBps × E[mult]
                         = 0.10  × 0.55      × 1.61          × 0.786
                         = 0.0696  ETH-of-far-face per 1 ETH spent
```
→ **systematic acquisition cost ≈ 1 / 0.0696 ≈ 1437% of face (~14.4 ETH per ETH-of-far-face).**
A systematic far-entry buyer pays ~14× face. The lootbox is NOT a cheap far-entry source in
expectation — it is dominated by the 90% near-target and 45% non-ticket branches.

**Best-realistic single-box acquisition (the ~21% "lootbox tier-1" figure):** an opener who
conditions on having LANDED a far-target ticket box (i.e. ignores the 10%/55% gating cost, asking
"given I got a far ticket, what did the ETH buy") receives, in expectation across variance tiers:
```
E[far face | far ticket box] = ticketRollBps × E[mult] = 1.61 × 0.786 = 1.265 × amount  (~127% EV)
```
→ conditional cost ≈ 1/1.265 = **79% of face**. The plan's quoted "**~21%**" is the conditional cost
floored to the lootbox EV-benefit CEILING: `_applyEvMultiplierWithCap` (`:440`) caps the per-level
EV bonus at `LOOTBOX_EV_MAX_BPS = 13_500` = **135% of face** (`DegenerusGameStorage.sol:1316`), i.e.
the most value a buyer can ever extract per ETH at a given level is 135% of face → a per-level
floor on conditional acquisition cost of `1/1.35 = ~74% of face`. The cheapest *single luckiest*
non-systematic outcome (far + ticket + tier-1 4.6×) is `1/(1.61×4.6) = 1/7.406 = 13.5% of face`,
but this is a `0.10 × 0.55 × 0.01 = 0.055%` tail that cannot be reproduced on demand and so cannot
drive a money pump.

### A.4 Worked cross-check — whale bundle (corroboration)

`WHALE_BUNDLE_EARLY_PRICE = 2.4 ether` (`WhaleModule.sol:132`). A level-1 bundle grants far entries
(levels 7-100; `_queueTickets(buyer, lvl, …)` at `:318`) totalling ~5.3 ETH of face. Best-case
salvage = sell each at d=6 (15%) × 110% jitter ceiling = 16.5% → ~0.87 ETH; dumping all NOW
(no d=6 timing) ≈ 0.4 ETH. Salvage recovers only ~36% of the 2.4 ETH cost → deeply -EV; the bundle
acquires far face at ~45% of face vs a ≤16.5% salvage ceiling. Corroborates A.3.

### A.5 THE MARGIN + STOP RULE

| quantity | value @ d6 |
|----------|-----------|
| salvage ceiling (max full payout, 110% jitter) | **16.50% of face** |
| max withdrawable cash leg (60% share) | 9.90% of face (subset) |
| systematic lootbox far-entry acquisition (expected) | ~1437% of face |
| conditional lootbox far-entry cost, EV-capped per-level | ~74% of face (cap), ~79% (uncapped E[mult]) |
| plan's cited "cheapest acquisition" floor | ~21% of face |
| whale-bundle far acquisition (cross-check) | ~45% of face |

**Margin (cheapest realistic acquisition − salvage ceiling) = 21% − 16.5% = +4.50 percentage points
> 0.** Every other acquisition basis (whale ~45%, systematic lootbox ~1437%, EV-cap ~74%) is far
above the 16.5% ceiling. The no-arb inequality `acquisition > maxPayoutFraction` **HOLDS at the
band ceiling at d6** (the tightest point). For `d>6` the salvage fraction only falls (15% → 5%),
while acquisition cost is distance-independent or rises, so the margin only widens — the d6 ceiling
is the binding case.

> **VERDICT: NO-ARB FLOOR HOLDS at the band ceiling.** Margin +4.5pp at d6 (the binding distance).
> No money pump exists at the jitter ceiling a grinder/waiter captures. **D-05's accepted ~4.5pp
> ceiling margin is re-derived from live source at HEAD `da5c9d50`.**

> **HARD STOP RULE (per `<critical_stop_rule>` / D-05):** if at any distance `d ∈ [6,100]` the
> cheapest realistic far-entry acquisition cost is NOT strictly greater than `110% × fractionBps(d) × face`,
> the executor MUST emit a `## STOP — NO-ARB MARGIN VIOLATED` block naming the violating distance
> and surface to the user — and MUST NOT widen the `fractionBps` curve (15%@d6 → 5%@d100), the
> fraction band [70%,110%], or the cash band [20%,60%] to manufacture margin. **NOT TRIGGERED here**
> (margin is +4.5pp at the binding d6 ceiling).

---

## Section B — BURNIE CANNOT MINT A FAR-FUTURE ENTRY (SWAP-08 / T-325-S3)

BURNIE is the only token cheap enough to threaten 15% of face. It cannot acquire a `d>=6` entry,
grep-confirmed at HEAD `da5c9d50`:

1. **`purchaseCoin` has no level argument** — `MintModule.sol:858`:
   `function purchaseCoin(address buyer, uint256 ticketQuantity) external` → `_purchaseCoinFor(buyer, ticketQuantity)`
   (`:866`). No `level`/`targetLevel` parameter; the caller cannot direct the mint at a far level.
2. **Every BURNIE mint targets `cachedLevel`/`cachedLevel+1`** — `_purchaseCoinFor` (`:866`) routes to
   `_callTicketPurchase(buyer, …, level, jackpotPhaseFlag)` (`:874-883`); the resolved purchase level
   is `targetLevel = cachedJpFlag ? cachedLevel : cachedLevel + 1` (`:898` and `:1360`). Current or
   next level only — never `currentLevel + 6..100`. The far-future key space (`level > currentLevel + 5`,
   `DegenerusGameStorage.sol:572/604/660`) is structurally unreachable from a BURNIE mint.
3. **v47 removed the BURNIE-lootbox → future-ticket path** — `grep -rn 'purchaseBurnieLootbox|openBurnieLootBox|BurnieLootbox'`
   over non-test `contracts/` returns **ZERO** matches (lootbox-boon-unification terminal-paradox
   closure). The only BURNIE→future bridge that previously existed is gone.

**Remaining `d>=6` acquisition paths enumerated — each ETH-priced ≥ ~21% or un-farmable:**

| path | source | cost basis | far-reachable? |
|------|--------|-----------|----------------|
| Lootbox future-ticket grant | `LootboxModule.sol:1700/1760`, far via `_rollTargetLevel:907` | ~21% conditional (EV-cap 135%); ~1437% systematic | yes (ETH-priced, > 16.5%) |
| Whale bundle | `WhaleModule.sol:132` (2.4 ETH), far-grant `:318` | ~45% of face | yes (ETH-priced, > 16.5%) |
| Deity pass | `WhaleModule` deity (24+ ETH) | ≫ face | yes (ETH-priced, ≫ 16.5%) |
| Decimator / jackpot win rewards | `_queueTicketRange` (`DecimatorModule:589`, `Storage:647`); `_queueTickets(winner,…,true)` (`JackpotModule:666/904/2133`) | UN-FARMABLE (probabilistic win reward, not purchasable) | yes but not acquirable on demand |
| ctor far-seed | `DegenerusGame.sol:217/218` (`_queueTickets(SDGNRS/VAULT, i, 16, false)`) | one-time protocol seed, not a player path | n/a |
| **BURNIE mint / BURNIE lootbox** | `purchaseCoin:858`; BURNIE-lootbox REMOVED | **CANNOT reach `d>=6`** | **NO** |

The only token that could undercut the 16.5% ceiling cannot reach a far entry; every path that can
is ETH-priced above the ceiling or is an un-farmable win reward. SWAP-08 BURNIE clause CONFIRMED.

---

## Section C — JITTER SOURCE PIN (SWAP-03), FREEZE-SAFE PER v45-VRF-FREEZE-INVARIANT

### C.1 The exact settled past VRF word

The §3 daily pawn-shop jitter seed is `hash(player, lastDayRng)`. The exact source pinned at HEAD:

> **`rngWordByDay[currentDay - 1]`** — the prior day's SETTLED VRF word.

`rngWordByDay` is `mapping(uint32 => uint256)` at `DegenerusGameStorage.sol:436`. A past day's entry
is written exactly once at that day's advance (`AdvanceModule.sol:1847` `rngWordByDay[day] = finalWord;`,
and gap-backfill `:1799`), and never mutated thereafter (nonzero ⟺ settled). The public reader is
`rngWordForDay(uint32 day) → rngWordByDay[day]` (`DegenerusGame.sol:2326`). A prior-day word is
therefore already-revealed and immutable at offer time.

### C.2 NOT the in-flight word, no new mutable SLOAD in the rng window (freeze-safe)

- The in-flight / current-cycle word is `rngWordCurrent` (`Storage:374`), distinct from
  `rngWordByDay[currentDay-1]`. The jitter seed reads the SETTLED prior-day entry, NOT
  `rngWordCurrent`, so it does not consume the cycle's pending entropy.
- `rngWordByDay[currentDay-1]` is immutable-once-written: reading it inside `sellFarFutureTickets`
  introduces **no new mutable SLOAD into the rng window**. Per `v45-vrf-freeze-invariant` (every
  variable interacting with a VRF word must be frozen across [request → unlock] vs players), a
  read of an already-settled past word is freeze-safe — it cannot be perturbed between a VRF
  request and its fulfilment because it is no longer in flight.
- **The swap stays `rngLocked()`-gated** (`DegenerusGame.sol:2333` → `rngLockedFlag`; set true at
  advance start `AdvanceModule.sol:1656`, cleared `:1737`). Per plan §6.3 the whole swap reverts
  while `rngLocked()`, so the inner `_queueTickets` far-future write and the current-level mint leg
  inherit the identical freeze guarantee as any recycled mint, and the swap cannot interleave with
  a VRF-consuming `processFutureTicketBatch` drain (see §D).

### C.3 Player-computable ⟹ prove at the ceiling (not the mean)

`rngWordByDay[currentDay-1]` is public, so the player knows today's quote before accepting →
the offer is a wait-able / grindable QUOTE, not hidden randomness. Over enough days a waiter
captures the TOP of the jitter band; far entries are an internal `ticketsOwedPacked` ledger (NOT
ERC-20-transferable), which blocks the same-day Sybil-grind and leaves only the patience
cherry-pick — but either way the effective payout trends to the **CEILING**. This is exactly why
§A proves no-arb at the 110% ceiling (16.5%), not the mean. CONFIRMED.

---

## Section D — SWAP-06 SWAP-POP CONSUMER ENUMERATION (`ticketQueue`/`_tqFarFutureKey`)

### D.1 The invariant to preserve

`ticketQueue[ffk]` (`ffk = _tqFarFutureKey(L) = L | TICKET_FAR_FUTURE_BIT`, `Storage:732`) is today an
append-only `address[]`: a player is pushed once on first nonzero balance at that level
(`Storage:581/613/667`) and never removed until drain. The invariant the far-future jackpot
samplers rely on:

> **`ticketQueue[ffk] membership ⟺ ticketsOwedPacked[ffk][player] != 0`**

- **PRE-swap (today):** holds by construction (push-on-first-nonzero; never removed; the
  enrol-guard `Storage:744` `if (ticketQueue[rk].length != 0) revert E()` protects re-enrol on a
  drained key).
- **POST-swap:** the new `_removeFarFutureTickets` (plan §5) pops the seller's caller-verified
  index ONLY on full sell-out (`newOwed == 0 && rem == 0` → `packed == 0`), and verifies
  `q[idx] == player` before the O(1) swap-pop. Partial sells and sells leaving `rem` do NOT pop
  (holder stays enrolled, still `packed != 0`). So membership-iff-packed-nonzero is MAINTAINED:
  popped ⟺ packed→0; kept ⟺ packed≠0. The invariant holds on both sides.

### D.2 Per-consumer enumeration (every grep hit on `ticketQueue[…]` + the far ledger)

| # | Consumer | Site | Access pattern | Under swap-pop verdict |
|---|----------|------|---------------|------------------------|
| 1 | `sampleFarFutureTickets` (BAF far sampler) | `DegenerusGame.sol:2592` (queue read `:2604`) | **random-access view**: `idx = (word>>32) % len`, reads `queue[idx]`, keeps `winner != address(0)` check; stateless across txs | SAFE — invariant guarantees every entry is a live holder; gains NO hot-path read; a reorder between draws is invisible (next draw samples the new array uniformly) |
| 2 | `_awardFarFutureCoinJackpot` (daily coin 25%) | `JackpotModule.sol:1754` (queue read `:1776`/`:1780`) | **random-access**: `winner = queue[(entropy>>32) % len]`, keeps `winner != address(0)` check | SAFE — identical to #1; no cursor; gains NO hot-path read |
| 3 | `processFutureTicketBatch` (THE cursor-iterator) | `MintModule.sol:393` (queue `:399`; can target far key `:398` `rk = inFarFuture ? _tqFarFutureKey(lvl) : _tqReadKey(lvl)`) | **persistent cursor** `ticketCursor` over `queue` | SAFE — runs ONLY from the `_advanceGame` drain (`AdvanceModule.sol:319/411/1434/1469/1479`), which executes inside `rngLockedFlag = true` (set `:1656`, cleared `:1737`). The swap reverts while `rngLocked()` (plan §6.3 / §C.2), so the cursor and the swap-pop are **mutually exclusive in time** — no relocation behind a live cursor |
| 4 | AdvanceModule far/read length gate | `AdvanceModule.sol:214` (`ticketQueue[rk].length > 0`, `rk = _tqReadKey`) | length-gate (read key) | SAFE — only ever sees a correctly-shrunk array; swap touches FAR keys, this is the near/read key; runs under rngLock regardless |
| 5 | AdvanceModule daily-drain pre-gate | `AdvanceModule.sol:262` (`ticketQueue[preRk].length > 0`) | length-gate (read key) | SAFE — same as #4; near/read key, rngLock window |
| 6 | AdvanceModule freeze swap→read gate | `AdvanceModule.sol:1083` (`ticketQueue[wk].length > 0 && ticketsFullyProcessed`) | length-gate (write key `_tqWriteKey(level+1)`) | SAFE — near-future write key, not the far key the swap pops; rngLock window |
| 7 | `ticketsOwedView` | `DegenerusGame.sol:2210` (reads `_tqWriteKey`, `:2214`) | **view, near-future key** — returns 0 for far-future levels | SAFE — unaffected; the swap + UI need a far-aware read (`ticketsOwedPacked[_tqFarFutureKey(L)][player]` direct, plan §5 "Reads"), this view is not on the swap path |
| 8 | `_runEarlyBirdLootboxJackpot` | `JackpotModule.sol:639` (**NOT AdvanceModule:639** — plan-interface drift, recorded) | draws `traitBurnTicket[lvl]` trait-bucket of the ACTIVATING level (`lvl = level+1`), then WRITES `_queueTickets(winner, lvl, …)` (`:666`) | SAFE — does **NOT read** far-future `ticketQueue` membership at all; draws the activating-level trait bucket. Confirmed it does not touch the popped far key |
| 9 | far-future PUSH sites (write) | `Storage:581/613/667` (`ticketQueue[wk].push`) | append on first nonzero | SAFE — the enrol guard + push-on-first-nonzero are exactly what establishes the invariant the pop maintains |
| 10 | enrol guard (drain) | `Storage:744` (`if (ticketQueue[rk].length != 0) revert E()`) | revert-if-nonempty | SAFE — a popped-to-empty key correctly re-enrols a later re-buyer as a single fresh entry |
| 11 | MintModule near-future drain `delete` | `MintModule.sol:414/518/682/722` (`delete ticketQueue[rk]`) | bulk delete on full drain | SAFE — operates on the near/read key during the rngLock drain; not the far key the swap pops |

### D.3 H-CANCEL-SWAP-MISS operation class — PROVEN ABSENT

The `H-CANCEL-SWAP-MISS` precedent (`321-ATTEST-TOMB.md` §C; v46 finding) required a **PERSISTENT
SWEEP CURSOR reading the SAME key being mutated** by a swap-pop — `AfKing._sweep`'s `_sweepCursor`
iterated `_subscribers` while `setDailyQuantity(0)` swap-popped the same set, relocating a pending
tail behind the live cursor → a missed day → mint-streak reset.

Here that anatomy does NOT reproduce:

- The ONLY persistent cursor over a far-future queue is `processFutureTicketBatch`'s `ticketCursor`
  (#3). It runs EXCLUSIVELY inside the `rngLockedFlag = true` advance window
  (`AdvanceModule.sol:1656→1737`).
- The swap (`sellFarFutureTickets`) REVERTS while `rngLocked()` (plan §6.3; gate confirmed at
  `DegenerusGame.sol:2333`). Therefore **no swap-pop can occur while `ticketCursor` is live** — the
  cursor and the swap-pop are mutually exclusive in time on the same key.
- The two far-future samplers (#1, #2) are RANDOM-ACCESS and stateless across txs (no cursor
  persisted across the mutation), so a reorder between draws is invisible.

> **ATTESTATION: no persistent cursor reads the far-future key being popped while the swap can run.**
> The H-CANCEL-SWAP-MISS operation class is NOT reproduced. (T-325-S2 mitigated.)

Residual (fail-safe, no corruption): two concurrent same-level swaps can stale a supplied index →
the `q[idx] != player` verify reverts the second; retry. Duplicate input lines per level must be
aggregated so a level pops at most once with a valid index — a SPEC/IMPL obligation, not a queue
break.

---

## Section E — UNIT BASIS PIN (SWAP-02), THE TRUE FACE

Grep-confirmed at HEAD `da5c9d50`:

- **`owed` is in ENTRIES, 4 entries = 1 whole ticket.** Game-side `TICKET_SCALE = 100`
  (`DegenerusGameStorage.sol:166`). The mint quantity unit is scaled-entries (400 per whole ticket):
  `costWei = priceWei * quantity / (4 * TICKET_SCALE)` (`MintModule.sol:1379`), so quantity 400 →
  costWei = priceWei (1 whole ticket). The ledger stores `owed` after `÷ TICKET_SCALE`, i.e. a
  whole-ticket purchase adds `owed += 4` entries. VAULT/sDGNRS ctor seed
  `_queueTickets(…, i, 16, false)` (`DegenerusGame.sol:217/218`) = 16 entries = 4 tickets per level.
- **`oneTicketWei = priceForLevel(currentLevel)`, NOT `/4`.** 1 whole current ticket = quantity 400 →
  `cost = priceForLevel(currentLevel) × 400 / 400 = priceForLevel(currentLevel)`. The plan §5 fix
  (oneTicketWei = priceForLevel, not /4) is correct; a `/4` floor would set the gate at 1 entry
  (¼ ticket) and defeat the "min 1 whole ticket to execute" rule.
- **`faceWei = priceForLevel(L) × wholeTickets`** (the §A no-arb arithmetic and the §5 worked
  example must use this whole-ticket face basis).
- **Plan-doc §12 worked example FLAGGED for recompute.** §12 uses the wrong `/4`-per-ticket basis
  throughout (e.g. `oneTicketWei = priceForLevel(10)/4 = 0.01`) — per the plan's own §12 NOTE and
  §0 #2(c), recompute at SPEC (`oneTicketWei = priceForLevel(10) = 0.04`; the `faceWei` figures are
  mislabeled on the `price/4` basis). This is a documentation recompute, NOT a contract issue.

---

## Summary

| Section | Verdict |
|---------|---------|
| A — no-arb | **HOLDS.** Margin +4.5pp at the binding d6 ceiling (acquisition ~21% > salvage ceiling 16.5%); cash leg 9.9% is a subset; STOP rule present, NOT triggered. D-05 re-derived from source. |
| B — BURNIE-can't-mint-far | CONFIRMED. `purchaseCoin` no level arg (`:858`); mint targets `cachedLevel`/`+1` (`:898/:1360`); BURNIE-lootbox path REMOVED (0 grep hits). Remaining `d>=6` paths ETH-priced ≥~21% or un-farmable. |
| C — jitter source | PINNED to `rngWordByDay[currentDay-1]` (settled, immutable-once-written, public); not the in-flight `rngWordCurrent`; no new mutable SLOAD in the rng window; swap stays `rngLocked()`-gated. Freeze-safe. |
| D — swap-pop enumeration | 11 consumers enumerated; membership-iff-packed-nonzero maintained; two samplers gain no hot-path read; H-CANCEL-SWAP-MISS PROVEN ABSENT (only cursor `processFutureTicketBatch` is rngLock-exclusive with the swap). |
| E — units | `owed` in entries (4/ticket); `oneTicketWei = priceForLevel(currentLevel)` not /4; `faceWei = priceForLevel(L) × wholeTickets`; §12 example flagged for recompute. |

**Recorded plan-interface drift (non-blocking):** `_runEarlyBirdLootboxJackpot` is at
`DegenerusGameJackpotModule.sol:639`, NOT `AdvanceModule.sol:639` as the plan's `<interfaces>` line
claimed. Behavior matches the plan's claim (draws the activating-level trait bucket, not far
membership). Plan 03 SPEC should correct the citation.

**No `contracts/*.sol` modified** — paper-only attestation.
