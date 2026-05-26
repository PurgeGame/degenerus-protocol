# Architecture Research

**Domain:** Solidity on-chain game — unified keeper "do-work" router + advance-bounty re-home (v49.0)
**Researched:** 2026-05-26
**Confidence:** HIGH (all findings are direct source reads of the v48.0-closure tree; cross-contract call sites grep-verified per `feedback_verify_call_graph_against_source`)

> Scope note: this is SUBSEQUENT-milestone integration research, NOT greenfield ecosystem
> research. There is no "stack" to pick — the question is *where a new router sits inside an
> existing, frozen-at-deploy contract topology* and *how to re-home one reward path*. The
> sections below answer the five integration questions in the milestone brief. Every cited
> `file:line` is against the v48.0-closure HEAD `0cc5d10f` working tree and MUST be re-attested
> at SPEC before any patch.

---

## Standard Architecture

### The existing keeper topology (as-built, v48.0)

The "do-work" surface is **already split across two contracts**, with the BURNIE bounty rail
(`BurnieCoinflip.creditFlip`) shared by both. This is the single most important fact for the
router design, and it differs from the milestone brief's framing (which implies AfKing holds
autoOpen/autoResolve — it does not; those live on the game).

```
┌──────────────────────────────────────────────────────────────────────────┐
│                          CALLER (any EOA — keeper bot)                     │
└───────────────┬───────────────────────────────┬───────────────┬───────────┘
                │ advanceGame()                  │ autoOpen()    │ autoBuy(n)
                │ autoOpen() autoResolve()       │ autoResolve() │
                ▼ (IN-GAME entrypoints)          ▼               ▼ (SATELLITE)
┌──────────────────────────────────────────────┐  ┌──────────────────────────┐
│              DegenerusGame.sol                 │  │       AfKing.sol          │
│  ────────────────────────────────────────     │  │  ───────────────────────  │
│  advanceGame()  :275  ──delegatecall──┐        │  │  autoBuy(maxCount)  :567  │
│  autoOpen(n)    :1636 (gas-peg reward) │        │  │   - daily cursor sweep    │
│  autoResolve()  :1587 (gas-peg reward) │        │  │   - stall mult 1/2/4/6    │
│  batchPurchase()    :1731 (AF_KING-gated)◄──────┼──┼── calls game.batchPurchase│
│  currentDayView()   :462  (advance-due signal) │  │   - bounty = creditFlip   │
│  rngLocked()        :2413 (global gate)        │  │     :846                  │
│  boxPlayers/boxCursor :1551-1562 (box queue)   │  └──────────┬────────────────┘
│         │                                      │             │
│         ▼ delegatecall                         │             │
│  ┌─────────────────────────────────────────┐  │             │
│  │  DegenerusGameAdvanceModule.sol  :155     │  │             │
│  │   advanceGame body                        │  │             │
│  │   ADVANCE_BOUNTY_ETH = 0.005e  :147       │  │             │
│  │   stall mult 1/2/4/6  :241-255            │  │             │
│  │   creditFlip(caller,…) @ :189 :225 :468 ──┼──┼─────────────┤
│  └─────────────────────────────────────────┘  │             │
└────────────────────────────────────────────────┘             │
                │ creditFlip(msg.sender, reward)                │ creditFlip(msg.sender, bounty)
                ▼                                               ▼
        ┌───────────────────────────────────────────────────────────┐
        │                   BurnieCoinflip.sol                        │
        │   creditFlip(player, amount)  — onlyFlipCreditors           │
        │   authorized: GAME (delegate-callers) + AF_KING             │
        │   → deferred BURNIE mint (flip-credit, illiquid until claim) │
        └───────────────────────────────────────────────────────────┘
```

### Component responsibilities (current)

| Component | What it owns today | Bounty mechanism |
|-----------|--------------------|------------------|
| `DegenerusGame.advanceGame` (`:275`→AdvanceModule `:155`) | Day rollover, VRF gate, jackpot/ticket batch processing | `creditFlip(caller, ADVANCE_BOUNTY_ETH·mult / price)` at 3 internal sites |
| `DegenerusGame.autoOpen(maxCount)` (`:1636`) | Walk `boxPlayers[index]` from `boxCursor`, open ready boxes | `creditFlip(msg.sender, Σ AUTO_OPEN_BOX_GAS_UNITS·0.5gwei)` once at end |
| `DegenerusGame.autoResolve(players,betIds)` (`:1587`) | Caller-supplied Degenerette bet list, per-item isolated | `creditFlip(msg.sender, Σ AUTO_RESOLVE_BET_GAS_UNITS·0.5gwei)` once at end |
| `AfKing.autoBuy(maxCount)` (`:567`) | Daily subscription sweep (mint/lootbox-buy on behalf of subs) | `creditFlip(msg.sender, batchLen·BOUNTY_ETH_TARGET·mult / mp)` once at end |
| `BurnieCoinflip.creditFlip` | Deferred-mint bounty rail | authorized callers = GAME + AF_KING |

**Wiring already in place that the router reuses unchanged:**
- AfKing is **already** an authorized `creditFlip` caller (PROTO-03, v46). No new authorization needed if the router lives on AfKing.
- The game is **already** an authorized `creditFlip` caller (it delegate-calls the AdvanceModule whose `coinflip` constant is the game's own credit authority).
- `AF_KING` is **already** the sole authorized caller of `game.batchPurchase` (`:1736`).
- Both bounty paths already use the identical ETH-pegged → BURNIE conversion idiom
  (`ethTarget · PRICE_COIN_UNIT / mintPrice`), so a unified break-even peg is a constant swap, not new math.

---

## Recommended Project Structure (where the router lives)

### Decision: the router lives on `AfKing.sol`. HIGH confidence.

This is the load-bearing architectural call. Reasoning with explicit tradeoffs:

| Criterion | Router on **AfKing** (RECOMMENDED) | Router on **the game** |
|-----------|-------------------------------------|------------------------|
| Calls `autoBuy` | **Internal** — refactor autoBuy → internal `_autoBuy`, call directly (no external hop, no new re-entrancy surface) | External `IAfKing(AF_KING).autoBuy(n)` — adds a call frame + a trust edge the game does not currently have |
| Calls `autoOpen` / `autoResolve` | External `IGame(GAME).autoOpen(n)` — but these are **already** external/permissionless, so the hop is benign and bounty still routes through the game's own creditFlip | Internal (same contract) |
| Calls `advanceGame` | External `IGame(GAME).advanceGame()` — already permissionless | Internal delegatecall (already how the game reaches it) |
| `creditFlip` authority | AfKing is **already** a flip creditor → router bounty needs **no new authorization** | Game is also a creditor → also fine |
| Bounty-peg ownership | AfKing already owns `BOUNTY_ETH_TARGET` + the 1/2/4/6 stall logic (`:823-846`) — natural home for the unified peg | Would need to import/duplicate the peg constants AfKing owns |
| Storage-layout risk | AfKing is **standalone** (4-slot-pinned + cursor); a router fn touches **no game storage** and cannot perturb the game's fragile packed layout | The game's storage is the protocol's most fragile surface (bit-packed, module-delegatecall slot-sharing) — higher blast radius |
| Owner-less posture | AfKing is explicitly owner-less / no-fallback / no-multicall — a permissionless router fn fits its character | Game already huge; concentrates more keeper surface in the audit-heaviest contract |

**Why AfKing wins:** the router's *most security-sensitive* edge is the one to `autoBuy` — it
moves ETH out of subscriber pools and calls `batchPurchase`. Keeping that edge **internal to
AfKing** (refactor `autoBuy` → internal `_autoBuy(maxCount)` + retain a thin external `autoBuy`
wrapper) means the router introduces **zero new cross-contract trust edges on the money-moving
path**. The two remaining edges (`advanceGame`, `autoOpen`) are to **already-permissionless** game
entrypoints whose bounties **already route through the game's own creditFlip** — the router does
not need to (and must not) pay those itself; it just *triggers* them and lets the game pay the
existing in-game reward. The only bounty the router *itself* pays is the **re-homed advance
bounty** (see below).

> Anti-pattern rejected: router on the game calling `AfKing.autoBuy`. That inverts the current
> trust direction (today AfKing calls the game, never the reverse) and forces the game to become an
> authorized caller of AfKing's internal money-moving sweep — a broad new trust edge. Do not.

### Files touched (new-vs-modified)

```
contracts/
├── AfKing.sol                 # MODIFIED — add doWork(maxCount) router;
│                              #   refactor autoBuy → internal _autoBuy + external wrapper;
│                              #   re-peg BOUNTY_ETH_TARGET to break-even @0.5 gwei;
│                              #   pay the re-homed advance bounty here.
├── DegenerusGame.sol          # MODIFIED — autoOpen/autoResolve UNCHANGED in behavior;
│                              #   advanceGame() stays (unrewarded fallback);
│                              #   forward the AdvanceModule return through the :275 wrapper;
│                              #   NEW O(1) work-discovery view(s) (advance-due + box-pending).
├── modules/
│   └── DegenerusGameAdvanceModule.sol   # MODIFIED — REMOVE the 3 creditFlip(caller,…)
│                              #   bounty sites (:189,:225,:468); advanceGame becomes
│                              #   unrewarded AND returns the stall multiplier (+rewardable
│                              #   flag) so the router can pay the re-homed, stall-scaled bounty.
├── interfaces/
│   ├── IDegenerusGame.sol     # MODIFIED — add the new work-discovery view(s);
│   └── IDegenerusGameModules.sol  # MODIFIED — advanceGame() return signature.
└── ContractAddresses.sol      # likely UNCHANGED (freely modifiable if a redeploy reshuffles).
```

### Structure rationale

- **Router on AfKing:** keeps the money-moving `autoBuy` edge internal; reuses AfKing's existing
  creditFlip authorization, stall-multiplier logic, and ETH-peg immutable.
- **autoOpen/autoResolve stay in-game, unchanged:** they write game storage directly ("lives
  in-game by construction", `DegenerusGame.sol:1533`) and already pay their own gas-peg reward via
  the game's creditFlip. The router merely *invokes* `autoOpen`; it does not absorb that reward
  logic. `autoResolve` is excluded from the router entirely (brief decision) and is untouched.
- **Advance bounty moves to AfKing:** the bounty becomes a router concern, paid by AfKing (an
  authorized creditor) only when the router took the advance branch. The AdvanceModule stops
  paying; it only needs to *surface* the stall signal.

---

## Architectural Patterns

### Pattern 1: One-category-per-call priority router with early-return

**What:** `doWork(uint256 maxCount)` evaluates cheap work-discovery predicates in fixed priority
order (advance-due → boxes-pending → buys-pending) and dispatches to **exactly one** category,
then returns. Mirrors the existing `advanceGame` single-stage-per-call discipline and the
`autoBuy` chunked-cursor discipline.

**When to use:** here — the brief mandates one category per call; it bounds gas (a single
category's worst case) and makes the faucet analysis tractable (max bounty per call = one
category's max).

**Trade-offs:** a caller wanting to do everything calls `doWork` repeatedly — intended (keeper bots
loop). Priority ordering means buys can starve while advance is perpetually due — but "advance due"
self-clears per day, so starvation is bounded to the within-day window.

**Sketch (router on AfKing):**
```solidity
// AfKing.sol
function doWork(uint256 maxCount) external returns (uint8 category, uint256 bounty) {
    if (IGame(GAME).rngLocked()) revert AutoBuyAborted(msg.sender, 1);  // global gate, mirrors autoBuy:568
    if (maxCount == 0) revert EmptyAutoBuy();

    // (1) ADVANCE — highest priority. Cheap predicate: day rolled past last-advanced.
    if (IGame(GAME).advanceDue()) {
        (uint8 mult, bool rewardable) = IGame(GAME).advanceGame();   // unrewarded in-callee; returns the stall signal
        if (rewardable) {
            bounty = (ADVANCE_BREAKEVEN_ETH * PRICE_COIN_UNIT * mult) / IGame(GAME).mintPrice();
            ICoinflip(COINFLIP).creditFlip(msg.sender, bounty);      // AfKing IS an authorized creditor
        }
        return (1, bounty);
    }
    // (2) OPEN — boxes pending for the active index with a VRF word.
    if (IGame(GAME).boxesPending()) {
        IGame(GAME).autoOpen(maxCount);   // game pays its OWN gas-peg reward; router pays nothing
        return (2, 0);
    }
    // (3) BUY — subscription sweep. Internal, money-moving; pays its own bounty in the tail.
    return (3, _autoBuy(maxCount));
}
```
> Bounty asymmetry by design: ADVANCE's bounty is paid **by the router** (re-homed); OPEN's is paid
> **by the game** (existing path, untouched); BUY's is paid **by AfKing's existing autoBuy tail**
> (untouched). The router never double-pays.

### Pattern 2: Cheap work-discovery via pre-existing scalar reads (no scan)

**What:** every "is there work?" predicate is an **O(1) storage read or comparison** — never a loop
over a queue. The protocol already exposes (or trivially can) the three scalars needed:

| Predicate | Cheap signal (from source) | Cost |
|-----------|----------------------------|------|
| **Advance due?** | `currentDayView() != dailyIdx` — the day rolled past the last-advanced day (`dailyIdx` is set to `day` at the tail of advance, `AdvanceModule:1736`; `day == dailyIdx` is exactly the mid-day "nothing new" case ending in `revert NotTimeYet`, `:202/:235`). | 1 SLOAD + 1 view |
| **Boxes pending?** | `boxPlayers[activeIndex].length > boxCursor` **AND** `lootboxRngWordByIndex[activeIndex] != 0` — the same two reads `autoOpen` does at `:1647-1651`. The VRF-word gate is MANDATORY (the v45 orphan-index landmine). | 2-3 SLOADs |
| **Buys pending?** | `_autoBuyCursor < _subscribers.length` for today, OR `_autoBuyDay != currentDay` (new day un-resets the cursor) — AfKing-local reads, already in `autoBuy:577`. | 1-2 SLOADs (local) |

**When to use:** always. The anti-pattern (below) of scanning queues to "find work" is a gas-DoS
faucet.

**Trade-offs:** the predicates are *necessary but not sufficient* — e.g. `boxesPending()` can be
true while every queued box is already-emptied (skipped at `:1662`), so `autoOpen` does real work
but earns nothing. That is acceptable: each underlying entrypoint is **already** self-guarding
(autoOpen returns early / earns zero; advance reverts `NotTimeYet`; autoBuy reverts
`NoSubscribersAutoBought` on a do-nothing chunk). The router should NOT try to perfectly predict
work — pick the highest-priority *plausible* category and let the entrypoint's own guards handle
the empty case. Refinement: **fall through** a cheaply-known-false predicate so a no-op advance
does not block a real open; **commit** once a predicate is true (don't re-evaluate post-dispatch).

### Pattern 3: Re-home a reward without moving the worker (advance-bounty rework)

**What:** the *work* (advanceGame's day processing) stays exactly where it is — in the
AdvanceModule, reached via the game's delegatecall. Only the *reward* moves: the three
`creditFlip(caller, …)` sites (`:189`, `:225`, `:468`) are **deleted**, making `advanceGame`
unrewarded. The router, when it takes the advance branch, pays the re-homed bounty itself.

**When to use:** when a function must remain a permissionless **liveness fallback** (anyone can
still call `advanceGame()` directly to un-stick the game even if the router is broken) while
concentrating the **incentive** on the preferred path (the router).

**Trade-offs:** standalone `advanceGame()` becomes unrewarded — a rational keeper always goes
through `doWork`. That is the intent ("direct advanceGame = unrewarded fallback"). If the router
were ever bricked, advance is still callable (liveness preserved) but unrewarded; the game's
existing `_livenessTriggered` game-over backstop still applies. Acceptable, deliberate degradation.

**The stall-multiplier exposure problem (the crux of question 3):**

The stall multiplier (1/2/4/6) is currently computed **inside** the AdvanceModule (`:241-255`)
from `block.timestamp` vs a reconstructed day-start, and is **only applied at the `:468` payout
site** (the mid-day partial-drain sites `:189`/`:225` pay the flat base). The router cannot pay a
stall-scaled advance bounty unless that multiplier (or its inputs) is surfaced. Three viable
designs, in order of preference:

1. **RECOMMENDED — `advanceGame` returns the multiplier (+ a "rewardable / which payout site"
   flag).** Change `advanceGame()` to `returns (uint8 mult, bool rewardable)` (or a small packed
   value). The AdvanceModule already *has* the multiplier in scope at the payout sites; instead of
   `creditFlip`-ing, it returns it. The game's `advanceGame()` wrapper (`:275`) decodes and
   forwards the delegatecall return. The router reads it and pays `base · mult`. **Pros:** single
   source of truth for the multiplier stays in the AdvanceModule (which owns the day-start math +
   `DEPLOY_DAY_BOUNDARY` offset, `:243-246`); no duplicated timing logic; the router cannot disagree
   with the module about "is it stalled." **Cons:** the game's `advanceGame()` external signature
   gains a return value — a minor interface change (`IDegenerusGameModules` + `IDegenerusGame`);
   existing direct callers (tests, liveness bots) just ignore the return.

2. **Acceptable — a pure/view `advanceStallMultiplier()` on the game** that recomputes 1/2/4/6 (+
   any extended tier), with the router calling `advanceGame()` (now unrewarded) then reading the
   view in the same tx. **Pros:** no change to `advanceGame`'s signature. **Cons:** **duplicates
   the timing math** in a view — two places must agree on the day-start offset
   (`DEPLOY_DAY_BOUNDARY`, the 82_620-second alignment); a drift bug becomes possible. Subtle
   TOCTOU: the view is read *after* advance ran, so `dailyIdx` has moved — the view must compute the
   multiplier against the *pre-advance* day, not "today." Fiddlier than it looks.

3. **Discouraged — recompute the multiplier entirely inside the router.** Worst option: the router
   re-owns the timing constants, maximizing drift risk, and **AfKing's own `_currentDay()` uses a
   DIFFERENT offset convention** (raw `(ts - 82620)/1 days`, `:887`) than the AdvanceModule's
   `(day-1 + DEPLOY_DAY_BOUNDARY)·1days + 82620` (`:243`). Reconciling two day conventions in a
   money path is exactly the off-by-one that produces a wrong (possibly inflated) bounty. Avoid.

> **Recommendation: design 1 (return the multiplier from advanceGame).** It keeps the stall math in
> its single existing home, avoids the two-day-convention reconciliation hazard, and the interface
> churn is small and backward-compatible for direct callers. The brief also wants the *option to
> extend the ceiling* for extreme stalls (e.g. add an 8x/12x tier beyond 2h) — design 1 makes that
> a one-line change in the module's existing `if/else` ladder, with the router automatically
> honoring the new tier.

### Pattern 4: Break-even peg as a constant swap (bounty recalibration)

**What:** both bounty rails already convert an **ETH-equivalent target** to BURNIE via
`ethTarget · PRICE_COIN_UNIT / mintPrice`. Re-pegging to break-even @0.5 gwei means setting the ETH
target to `gasUnits · 0.5 gwei` — the same idiom the in-game `_ethToBurnieValue` already uses with
`AUTO_GAS_PRICE_REF = 0.5 gwei` (`:1539`). So the advance bounty's `ADVANCE_BOUNTY_ETH = 0.005
ether` literal becomes `ADVANCE_GAS_UNITS · 0.5 gwei`, and AfKing's `BOUNTY_ETH_TARGET` immutable is
re-derived from the measured worst-case autoBuy marginal gas.

**When to use:** here. The GAS phase measures worst-case marginal gas per category; the peg
constants are then the deploy-time inputs.

**Trade-offs:** break-even reimburses gas at a 0.5 gwei reference with no profit margin — at >0.5
gwei real gas the keeper runs at a loss, at <0.5 gwei a small profit. The stall multiplier restores
the incentive when work is overdue. This is the **established protocol pattern** (v46 `CRANK_*_GAS_UNITS`,
v46 advance peg); v49.0 is a recalibration + multiplier extension, not a new mechanism.

---

## Data Flow

### `doWork` call flow (router on AfKing) — trust boundaries (question 4)

```
keeper EOA
  │  doWork(maxCount)
  ▼
AfKing.doWork  ── reads IGame(GAME).rngLocked()             [view, global gate]
  │
  ├── advance branch  ── IGame(GAME).advanceGame() ─────┐   [permissionless; UNREWARDED now]
  │        │                                            │
  │        │   game.advanceGame() :275  delegatecall ──▶│   AdvanceModule.advanceGame :155
  │        │        returns (mult, rewardable) ◀────────┘     (does day work; NO creditFlip)
  │        ▼
  │   AfKing pays re-homed bounty:
  │   ICoinflip(COINFLIP).creditFlip(msg.sender, base·mult)    [AfKing IS an authorized creditor]
  │
  ├── open branch  ──── IGame(GAME).autoOpen(maxCount) ──▶   game opens boxes,
  │                                                           game.creditFlip(msg.sender, gasPeg)
  │                                                           [bounty paid IN-GAME, not by router]
  │
  └── buy branch  ───── _autoBuy(maxCount)  [INTERNAL — money-moving]
           │  CEI-debit subscriber pools, accumulate slices
           ├── IGame(GAME).batchPurchase{value}(…)    [AF_KING-gated, :1736]
           └── ICoinflip(COINFLIP).creditFlip(msg.sender, batchLen·peg·mult)   [AfKing creditor]
```

**Enumerated trust boundaries:**

| Edge | Caller → Callee | Auth gate | New for v49? | Notes |
|------|------------------|-----------|--------------|-------|
| router → `game.advanceGame()` | AfKing → GAME | permissionless | NO (already public) | bounty NO LONGER paid by callee; router pays |
| router → `game.autoOpen()` | AfKing → GAME | permissionless | NO | callee still pays its own gas-peg reward |
| router → `_autoBuy` | internal | n/a | refactor only | money-moving; stays internal to AfKing |
| `_autoBuy` → `game.batchPurchase` | AF_KING → GAME | `msg.sender == AF_KING` (`:1736`) | NO | unchanged |
| router/`_autoBuy` → `coinflip.creditFlip` | AF_KING → COINFLIP | `onlyFlipCreditors` incl. AF_KING | NO | re-homed advance bounty rides the SAME existing authorization |
| AdvanceModule → `coinflip.creditFlip` | (delegate of GAME) → COINFLIP | GAME is a creditor | **REMOVED** | the 3 sites `:189/:225/:468` deleted |

**Critical security invariants to preserve (re-attest at the adversarial sweep):**
- **No new authorization is minted.** The re-homed advance bounty must ride AfKing's *existing*
  `creditFlip` authority. Do NOT add the game-as-payer for an AfKing-triggered advance — that would
  be a redundant credit path and a double-pay vector.
- **No double-pay.** Exactly one creditFlip per `doWork` call: advance branch pays once (router),
  open branch pays once (game), buy branch pays once (AfKing tail). The router must NOT pay the open
  bounty (the game already does).
- **rngLocked is the universal pre-gate.** Every branch respects `rngLocked()` (advance and autoBuy
  already do; autoOpen's per-box `lootboxRngWordByIndex != 0` gate is its own VRF-freeze guard). The
  VRF-freeze invariant (`v45-vrf-freeze-invariant`) MUST stay intact — the router adds no new
  VRF-window state read.
- **CEI preserved.** AfKing has no reentrancy guard by design (strict CEI, "never a payee in any
  contract it calls", `:101`). The router must not introduce a payee position: it calls into the
  game (which never calls back into AfKing except the AF_KING-gated `batchPurchase` it initiates),
  and pays creditFlip (deferred mint, no ETH out). Cursor/day-stamp writes stay in the order the
  existing autoBuy already enforces.

### Build-order dependency (question 5)

The advance-bounty removal and the router are **coupled** — removing the bounty before the router
exists would leave a window where advancing is entirely unrewarded (a liveness/incentive
regression). But the whole milestone ships as **ONE batched USER-APPROVED contract diff** (per
`feedback_batch_contract_approval`), so there is no on-chain intermediate state — ordering is about
*authoring/review* sequencing, not deployment. Recommended order:

```
1. SPEC (Phase 329)
   - Confirm: router lives on AfKing.
   - Settle: stall-multiplier exposure = advanceGame returns (mult, rewardable) [design 1].
   - Settle: work-discovery view signatures (advanceDue / boxesPending; buys via AfKing-local).
   - Settle: break-even peg targets (placeholders; numbers come from GAS).
   - Re-attest every cited file:line vs v48.0 HEAD 0cc5d10f.

2. IMPL (Phase 330) — single batched diff, authored in this internal order:
   2a. AdvanceModule: DELETE the 3 creditFlip(caller,…) sites (:189,:225,:468);
       change advanceGame to return the stall multiplier + rewardable flag (now unrewarded).
   2b. Game: forward the advanceGame return through the :275 wrapper;
       add advanceDue() + boxesPending() O(1) views; autoOpen/autoResolve UNCHANGED.
   2c. Interfaces: add the new views + advanceGame return signature.
   2d. AfKing: refactor external autoBuy → internal _autoBuy + thin external wrapper;
       add doWork(maxCount) router; re-peg BOUNTY_ETH_TARGET; pay the re-homed advance bounty.
   → author the PRODUCER (2a/2b module+game) before the CONSUMER (2d router) — the router reads
     what 2a/2b expose. All within the one diff.

3. GAS (Phase 331)
   - Worst-case-first marginal gas per category (advance, open, buy) + router overhead.
   - Calibrate break-even peg constants; size any extended multiplier ceiling.
   - Faucet check: max bounty per doWork = one category's max; no self-crank loop
     (re-run the WR-01-style round-trip guard from v46/Phase 319).

4. TST (Phase 332)
   - Router priority ordering (advance > open > buy); fall-through correctness.
   - Advance UNREWARDED via direct game.advanceGame(); REWARDED via router; multiplier honored.
   - No-double-pay across all three branches; rngLocked gate on each branch.
   - Regression: autoBuy/autoOpen/autoResolve behavior byte-faithful (autoBuy refactor to internal
     must be behavior-identical via the external wrapper).

5. TERMINAL (Phase 333)
   - 3-skill adversarial sweep on the router + advance-rework + AfKing subs/funding/auto-resolve.
   - Delta-audit; FINDINGS-v49.0; closure flip.
```

> The "remove the advance bounty before/with the router" requirement is satisfied by authoring 2a
> before 2d **inside the single diff** — no separate on-chain step, so no unrewarded-window ever
> ships. This is the safe reading of the brief's "sequence the removal before/with the router."

---

## Scaling Considerations

This is a fixed-population, pre-launch, frozen-at-deploy game, so "scaling" is **gas-per-call worst
case under adversarial input**, not user growth.

| Concern | Bound |
|---------|-------|
| Subscriber set growth (`_autoBuy`) | Already caller-bounded by `maxCount` (anti-gas-DoS, `:563-565`). Router inherits this. |
| Box queue growth (autoOpen) | Already caller-bounded by `maxCount` + self-partitioning `boxCursor`. Unchanged. |
| Advance work per call | Already single-stage-per-call (one stage then return/revert). Unchanged. |
| Router fixed overhead | 1-3 SLOAD discovery predicates + one external hop. Negligible vs dispatched work, but MUST be folded into the GAS-phase break-even peg so the hop is reimbursed. |

### Scaling priorities

1. **First bottleneck:** the break-even peg must cover **router overhead + the dispatched
   category's worst-case marginal gas**. If the peg only covers bare category cost, the router hop
   runs the keeper at a small loss even at 0.5 gwei.
2. **Second:** the multiplier-ceiling extension — at a 12h+ stall, even 6x may under-incentivize
   working through a large backlog; the GAS phase should size any new tier against the worst-case
   multi-stage advance backlog.

---

## Anti-Patterns

### Anti-Pattern 1: Scanning a queue to "discover" work

**What people do:** loop `boxPlayers[index]` / `_subscribers` in the router to count pending items
before dispatching.
**Why it's wrong:** turns an O(1) predicate into an O(n) gas-DoS faucet; loop cost is unbounded and
unpegged.
**Do this instead:** O(1) scalar comparisons (`currentDayView() != dailyIdx`,
`boxPlayers[idx].length > boxCursor` + `lootboxRngWordByIndex[idx] != 0`,
`_autoBuyCursor < _subscribers.length`). Let each entrypoint's own guards handle "predicate true but
no actual work."

### Anti-Pattern 2: Recomputing the stall multiplier in two places

**What people do:** copy the 1/2/4/6 timing ladder into the router (or a view) instead of returning
it from where it is computed.
**Why it's wrong:** AfKing's `_currentDay()` (`(ts-82620)/1days`, `:887`) and the AdvanceModule's
day-start (`(day-1 + DEPLOY_DAY_BOUNDARY)·1days + 82620`, `:243`) use **different conventions**;
duplicating the ladder invites an off-by-one in a money path (wrong/inflated bounty).
**Do this instead:** return the multiplier from `advanceGame` (design 1) — single source of truth in
the module that already owns the day-start math.

### Anti-Pattern 3: The router paying bounties the callee already pays

**What people do:** have `doWork` pay the open/resolve bounty after calling `game.autoOpen`.
**Why it's wrong:** `autoOpen`/`autoResolve` **already** pay their gas-peg reward via the game's own
`creditFlip` (`:1676`, `:1622`). A second payment from the router is a double-pay faucet.
**Do this instead:** the router pays ONLY the re-homed advance bounty (the one path whose in-callee
payment was deleted). Open/buy bounties stay where they are.

### Anti-Pattern 4: Inverting the trust direction (game calls AfKing)

**What people do:** put the router on the game and have it call `AfKing.autoBuy`.
**Why it's wrong:** today AfKing → game is the only direction; the reverse requires the game to be an
authorized caller of AfKing's money-moving sweep — a broad new trust edge.
**Do this instead:** router on AfKing; the money-moving `_autoBuy` stays internal.

---

## Integration Points

### Internal boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| AfKing.doWork ↔ game.advanceGame | external call; reads returned (mult, rewardable) | advanceGame now unrewarded; router pays bounty |
| AfKing.doWork ↔ game.autoOpen | external call | game pays its own in-callee gas-peg reward |
| AfKing.doWork ↔ AfKing._autoBuy | internal call | refactored from external autoBuy; money-moving |
| AfKing ↔ game.batchPurchase | external, AF_KING-gated | unchanged from v46/v48 |
| AfKing ↔ BurnieCoinflip.creditFlip | external, AfKing authorized creditor | re-homed advance bounty rides this existing authorization |
| AdvanceModule ↔ BurnieCoinflip.creditFlip | REMOVED | the 3 bounty sites deleted |
| router/game ↔ game.rngLocked / currentDayView / new views | external views | cheap work-discovery; no VRF-window state added |

### External services

| Service | Integration | Notes |
|---------|-------------|-------|
| Chainlink VRF | unchanged | router adds no VRF-window read; `rngLocked` + per-box `lootboxRngWordByIndex` gates preserved (v45 freeze invariant intact) |

---

## Open Questions for SPEC

1. **`advanceGame` return shape** — packed `(uint8 mult, bool rewardable)` vs a struct vs a separate
   `advanceGameRewarded()` selector. Recommendation: small return on the existing selector; direct
   callers ignore it. (Decides interface churn.)
2. **Discovery-view precision** — should `advanceDue()` be exactly `currentDayView() != dailyIdx`, or
   also account for the mid-day partial-drain case (`day == dailyIdx` but `!ticketsFullyProcessed`,
   which still does rewarded work at `:225`)? The brief says "advance-if-due" — **clarify whether
   mid-day drains count as due** and should be router-rewarded. If yes, the predicate (and the
   `rewardable` flag returned by advanceGame) must cover that case.
3. **Fall-through vs commit** — confirm `doWork` falls through cheap-false predicates but commits
   once a predicate is true, and how it surfaces "did nothing" (revert vs sentinel category).
4. **Multiplier ceiling extension** — confirm whether to add tier(s) beyond 6x for extreme stalls,
   and the thresholds (GAS phase sizes them).
5. **autoResolve exclusion** — confirm the router exposes no resolve branch and `autoResolve` keeps
   its own in-game bounty untouched (per brief).

---

## Sources

- `contracts/AfKing.sol` (full read) — keeper, autoBuy `:567`, stall multiplier `:823-846`, creditFlip wiring `:62-64/:846`, cursor `:215-216/:577`, day convention `:887`, CEI/no-reentrancy invariant `:99-106` — HIGH (source)
- `contracts/DegenerusGame.sol` — advanceGame wrapper `:275`, autoResolve `:1587`, autoOpen `:1636`, _autoResolveBet/_autoOpenBox `:1684/:1705`, batchPurchase AF_KING gate `:1731-1736`, gas-peg constants `:1539-1546`, `_ethToBurnieValue` `:1790`, currentDayView `:462`, rngLocked `:2413`, mintPrice `:2398`, boxCursor/boxPlayers `:1551-1562` — HIGH (source)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — advanceGame `:155`, ADVANCE_BOUNTY_ETH `:147`, creditFlip sites `:189/:225/:468`, stall multiplier `:238-255`, day-start offset `:243-246`, NotTimeYet `:202/:235`, dailyIdx write `:1736` — HIGH (source)
- `contracts/interfaces/IDegenerusGame.sol` — currentDayView `:266`, rngLocked `:263`, isOperatorApproved `:71`, hasAnyLazyPass `:416`, mintPrice `:37` — HIGH (source)
- `contracts/interfaces/IDegenerusGameModules.sol` — advanceGame `:10` — HIGH (source)
- `contracts/storage/DegenerusGameStorage.sol` — dailyIdx slot `:231`, `_simulatedDayIndexAt` `:1225` — HIGH (source)
- `contracts/ContractAddresses.sol` — AF_KING/GAME/COIN/COINFLIP/VAULT/SDGNRS/GAME_ADVANCE_MODULE pins, DEPLOY_DAY_BOUNDARY `:7` — HIGH (source)
- `.planning/PROJECT.md` — v49.0 milestone scope, locked design decisions — HIGH (project context)

---
*Architecture research for: Degenerus Protocol v49.0 unified keeper do-work router*
*Researched: 2026-05-26*
