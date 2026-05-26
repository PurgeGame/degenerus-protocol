# Pitfalls Research

**Domain:** Permissionless keeper "do-work" router + gas-pegged bounty for an adversarial real-money on-chain game (Degenerus Protocol v49.0)
**Researched:** 2026-05-26
**Confidence:** HIGH (source-grounded against the v48.0-closure tree — `AfKing.sol`, `DegenerusGameAdvanceModule.sol`, `BurnieCoinflip.creditFlip`, `BurnieCoin.burnForKeeper`, the `PLAN-CRANK-DO-WORK-INCENTIVE.md` faucet-lock analysis, and the v46 CR-01/WR-01 self-crank precedent; attack classes cross-checked against external griefing/MEV references)

> Scope note: these are pitfalls specific to **adding the unified router + re-homed/recalibrated bounty to THIS system**, not generic Solidity. Every pitfall is anchored to the actual mechanism: bounty is paid as illiquid `creditFlip` (coinflip stake), gated by `onlyFlipCreditors`(AF_KING); the daily tick is a two-phase VRF commit (`advanceGame` request → Chainlink callback fills `rngWordCurrent` → second `advanceGame` consumes); `_applyDailyRng` nudges the raw word by player-controllable `totalFlipReversals`; the advance bounty currently lives at `AdvanceModule.sol:189/225/468` with stall multiplier 1/2/4/6 at `:241-255`; the autoBuy bounty + multiplier live at `AfKing.sol:823-848`.

---

## Critical Pitfalls

### Pitfall 1: Bounty faucet drain via self-keeping / wash-keeping loops (low-or-no-real-work farming)

**What goes wrong:**
A caller (often the keeper-operator themselves, or a Sybil swarm) calls the router repeatedly to mint bounty `creditFlip` for work that has near-zero real cost or that they themselves manufactured. Because BURNIE is **uncapped-mintable** and the bounty is minted (`creditFlip` → `_addDailyFlip`), every spurious "success" the router rewards is fresh emission. The classic shape here: subscribe a Sybil to your own keeper-funded subscription, fund its pool, then `autoBuy` it yourself and collect a per-player bounty whose BURNIE value exceeds the round-trip cost. The same applies to `autoOpen` (open your own cheap box) and the router's advance leg (advance the day you would advance anyway, now paid).

**Why it happens:**
Designers reason "the router only rewards *successful* work, so reward ∝ real volume." But "successful work" is not the same as "net-new value to the protocol." If the cost to *manufacture* a rewardable item (a min subscription buy, a min-cost box) is less than the bounty that opening/buying it pays, the loop is +EV regardless of whether anyone benefits. The v46 GAS phase already hit the inverted version of this (CR-01): the box-open peg was set to a single-box *total* instead of the per-box *marginal*, which turned multi-box self-crank into a faucet — caught only during execution.

**How to avoid:**
Re-attest all three caller-independent faucet locks from `PLAN-CRANK-DO-WORK-INCENTIVE.md §7` against the *unified router* surface (they were proven for the separate functions, NOT the router):
1. **Purchase-gate** — every rewardable item exists only because someone prepaid (a real subscription buy / a real box deposit / a real bet). One reward per item via the existing `delete`/zero/day-stamp (`AfKing.sol:784 lastAutoBoughtDay`, box-zeroing, bet `delete`).
2. **Gas-peg at the MARGINAL, never the total** — reward ≈ marginal gas of one item at 0.5 gwei. Anything funded as a per-call total re-opens the CR-01 faucet. Derive the worst-case marginal first (per `feedback_gas_worst_case`).
3. **Coinflip-credit illiquidity** — bounty is `creditFlip` stake that must survive the coinflip house edge before becoming liquid BURNIE. Per-item reward must stay **≪ a min-bet's house edge** so the wash loop is -EV even at gas=0.
Plus **self-exclude is not enough by itself** — the operator can use a fresh address. The real lock is "you cannot manufacture a rewardable item for less than the bounty it pays," which must hold *after* the router stacks advance+open+buy bounties into one tx (see Pitfall 4).

**Warning signs:**
A unit test where address A subscribes/funds a Sybil, then A `autoBuy`s it and the `bountyEarned` BURNIE (post-coinflip-edge expectation) ≥ the subscription cost + gas. Any path where the per-item bounty ≥ the marginal cost to create the item. A faucet-resistance test that asserts self-crank/Sybil round-trip ≤ 0 that was written against the OLD separate functions and not re-run against the router.

**Phase to address:**
GAS (calibrate the marginal peg, derive worst-case first, re-attest the round-trip ≤ 0 against the router) + TST (faucet-resistance regression: self-crank/Sybil round-trip ≤ 0 for every router leg AND the combined tx) + TERMINAL (economic-analyst charges the composed wash loop).

---

### Pitfall 2: Break-even mis-calibration — bounty < gas kills liveness; bounty ≫ gas drains the faucet

**What goes wrong:**
The bounty is ETH-pegged and BURNIE-denominated: `(BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice()` (`AfKing.sol:845`; advance peg `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / priceForLevel(lvl)` `AdvanceModule.sol:468-471`). Two failure modes bracket the target:
- **Too low** (bounty < real gas): no rational keeper calls the router → no one autoOpens/autoBuys, and after re-homing, **no one advances the daily tick** → the game stalls until the stall multiplier escalates or the unrewarded fallback is called by a charitable/self-interested party.
- **Too high** (bounty ≫ gas): every successful call is +EV by the margin, which is precisely the faucet drain of Pitfall 1, and it makes wash-keeping profitable.
The peg is denominated in BURNIE via `mintPrice()` / `priceForLevel(lvl)`, so it **drifts with the game level** — a peg that breaks even at level 1 may be far off at level 50 if the conversion math isn't level-invariant in ETH terms.

**Why it happens:**
"Break-even at 0.5 gwei" is a single-point calibration. Real mainnet gas is rarely 0.5 gwei, so the design *intends* under-reimbursement at normal gas (only the gas-blind cohort participates — that's the anti-farm property). But that same under-reimbursement is the liveness risk: at high gas the bounty doesn't cover cost and the daily tick may not fire. The two requirements (anti-farm needs bounty ≤ gas; liveness needs bounty ≥ gas) are in direct tension and are reconciled ONLY by the stall multiplier (1/2/4/6) raising the reward until *someone* finds it worth it.

**How to avoid:**
Treat the stall multiplier as the load-bearing liveness mechanism, not a nice-to-have. Verify the **escalated** bounty (×6, and the proposed extended ceiling for extreme stalls) covers gas at a plausible *stressed* gas price, not just 0.5 gwei. Confirm the ETH-peg conversion is level-invariant: a fixed ETH target should buy the same ETH-equivalent BURNIE at every level (the `/ mintPrice` and `/ priceForLevel` divisors are what hold this — re-derive at GAS). Keep the base peg at break-even-or-just-under @0.5 gwei (anti-farm) and let the multiplier carry liveness. Document the explicit gas-price band over which liveness holds.

**Warning signs:**
A peg derived from a single gas price with no stress band. A ×6 ceiling whose escalated reward still doesn't cover gas at 20–50 gwei. A bounty whose ETH-equivalent value changes with level (peg not level-invariant). No worst-case-first gas derivation (per `feedback_gas_worst_case`).

**Phase to address:**
GAS (worst-case-first per leg; derive the gas-price band where base+multiplier keeps liveness; confirm level-invariance) + SPEC (lock whether the ×6 ceiling is extended for extreme stalls and to what value) + TERMINAL (economic-analyst sanity-checks the band).

---

### Pitfall 3: Advance-timing / MEV — paying a bounty to fire the daily tick incentivizes advancing at a self-favorable moment

**What goes wrong:**
Re-homing the advance bounty into the router means whoever calls the router *and triggers the advance leg* is paid. The daily tick is a **two-phase VRF commit**: tx-1 `advanceGame` requests the word (`_requestRng`, returns word==1, sets `rngLockedFlag`); the Chainlink callback fills `rngWordCurrent`; tx-2 `advanceGame` *consumes* it to pay jackpots / select winners / resolve redemptions. The concern is twofold:
- **(a) Does the caller's choice of *when* to fire request-tx or consume-tx let them benefit their own positions (jackpot/RNG/price)?** The VRF word itself is Chainlink-derived (10 confirmations daily, 4 mid-day at `:119-120`) and the jackpot winners are selected purely from that word — the *advancer cannot bias the entropy*. BUT `_applyDailyRng` adds `totalFlipReversals` to the raw word (`:1838-1844`) — a **player-controllable nudge**. This is exactly the v43/v45 freeze-invariant variable class: a variable interacting with a VRF word that must be frozen between rng-request and unlock. If a bounty now makes the caller *choose the consume moment*, they can choose to be the actor who sets `totalFlipReversals` (via coinflip activity) immediately before the consume tx lands — i.e., the bounty creates a *new incentive to exercise the nudge*.
- **(b) Does paying for the request-tx incentivize firing it on a wall-day boundary that's favorable?** The request commits the level pre-increment and which day's word is requested; the consume distributes that day's jackpot. A paid caller is now motivated to be the one who picks the boundary.

**Why it happens:**
The pre-v49 design paid the advance bounty too (`AdvanceModule.sol`), so this surface *already exists* — but re-homing it into a unified router that *also* does autoOpen/autoBuy bundles the advance trigger with the caller's other positions in **one atomic tx**, which is the textbook MEV "do my advantageous thing in the same tx as the tick" setup. The freeze invariant says `advanceGame` is "exempt-but-sensitive"; bundling raises the sensitivity.

**How to avoid:**
- Hold the v45 VRF-freeze invariant as a HARD floor: **every variable interacting with the consumed word must be frozen between rng-request and unlock vs players.** Re-verify `totalFlipReversals` (and any other SLOAD read alongside the word — per `feedback_rng_window_storage_read_freshness`) is frozen across the request→consume window, *even when the consume is triggered from inside the router in the same tx as the caller's autoBuy/autoOpen*. Trace BACKWARD from each consumer (per `feedback_rng_backward_trace`).
- Confirm the two-phase commit means the caller **cannot see the word before committing the request** (10/4 confirmations + separate-tx callback enforce this — the word is unknown at request time).
- Confirm the consume tx's outputs (winner selection, redemption roll `((word>>8)%151)+25` at `:1219-1221`) depend ONLY on the frozen word, not on any state the same-tx router legs could mutate first. Order matters: if the router does autoBuy/autoOpen *before* the advance-consume in the same tx, prove those legs cannot change a variable the consume reads.
- Keep `requestConfirmations` unchanged (10 daily / 4 mid-day) — do not let a gas-optimization lower them.

**Warning signs:**
A router that calls the advance-consume in the same tx *after* it has run autoBuy/autoOpen (mutating coinflip/claimable state). Any new read inside the consume path that touches state mutable by the same caller in the same tx. A test that perturbs `totalFlipReversals` between request and consume and gets a different jackpot outcome. Lowered VRF confirmations "for gas."

**Phase to address:**
SPEC (lock the router's internal ordering: advance-if-due must read only frozen state; decide whether the advance leg runs before or after the buy/open legs and prove freeze-safety either way) + TST (freeze-invariant fuzz: perturb `totalFlipReversals` and every in-window SLOAD between request and unlock, assert byte-identical consumed output — extend the v43 RngLockDeterminism harness) + TERMINAL (zero-day-hunter charges advance-timing/same-tx-bundling explicitly).

---

### Pitfall 4: Bounty-stacking in the unified router — combined advance+open+buy reward exceeds combined marginal cost

**What goes wrong:**
The router fires ONE category per call by priority (advance-if-due → autoOpen → autoBuy). But "one category per call" can still **stack across the work it does within that category** (the autoBuy leg already pays `batchLen × per-player bounty × multiplier` at `AfKing.sol:845`). And if "advance-if-due" pays the advance bounty *and then* falls through to autoOpen/autoBuy in the same call (or if the router doesn't strictly stop after the first category), a single tx collects the advance bounty + the open bounty + the buy bounty. Even with strict one-category routing, the per-category internal accumulation must individually clear the marginal-cost bar (Pitfall 1) — and the *priority order itself* is now a farming vector: a caller can arrange state so the highest-paying category is selected.

**Why it happens:**
The faucet locks were each proven for a *standalone* function. The router is a new composition surface. "Routes to one category per call" is a liveness/UX decision (do the most-urgent thing), but it was not necessarily analyzed as a *reward-composition* decision. The advance bounty (re-homed) + the existing autoBuy bounty were calibrated independently; nobody has yet proven `advance_bounty + open_bounty + buy_bounty ≤ combined marginal gas` for the path where they co-occur.

**How to avoid:**
- Define and enforce **strictly one rewarded category per call** in code (return immediately after the chosen category pays; do not fall through). The locked design says one category — make it a structural invariant, not a comment.
- If advance-if-due is the chosen category, it pays ONLY the advance bounty that tx; autoOpen/autoBuy are not also run+rewarded in the same tx.
- Re-attest the marginal-cost bound for EACH category independently AND assert the router cannot pay two categories in one tx.
- Keep the caller-bounded `maxCount` / gas budget so the within-category accumulation is caller-paid iteration, not contract-bounded (the anti-gas-DoS property, see Pitfall 5).

**Warning signs:**
A router that does not `return` after the first category's bounty payout. A test that lands a single tx earning more than one category's bounty. The combined-tx round-trip in the Pitfall-1 test passing for each leg alone but failing when composed.

**Phase to address:**
SPEC (lock "one rewarded category per call" as a structural invariant + the priority rule) + IMPL (enforce the early-return) + TST (assert single-category reward per tx; combined round-trip ≤ 0) + TERMINAL (economic-analyst composition charge).

---

### Pitfall 5: Gas-griefing / unbounded-loop DoS in work-discovery + dispatch

**What goes wrong:**
If the router enumerates work on-chain (e.g., scans the subscriber set, a bet/box queue, or "is the day due") in an unbounded loop, an attacker can inflate the set (cheap subscriptions, many small boxes) until the router's discovery loop exceeds the block gas limit and **no one can call it** — a permanent liveness DoS on the keeper subsystem. The existing autoBuy avoids this with a caller-bounded `maxCount` + a resuming cursor (`AfKing.sol:584/597/794`), and the crank plan explicitly rejected on-chain bet enumeration for this reason (`§9 OPEN-D`). A unified router that adds an advance-due check + an autoOpen discovery step must preserve the bound on *every* leg.

**Why it happens:**
"Do the highest-priority pending action" tempts the designer to scan for the highest-priority item on-chain. Scanning is O(set size); the set is permissionlessly growable (`depositFor` is permissionless `AfKing.sol:304`; subscriptions are open). A per-item try/catch isolation (the `onlySelf` external-call pattern from `§7`) *adds* a sub-call per item — at scale that compounds the gas. A single reverting/expensive item inside the dispatch loop can also revert the whole batch if isolation is missing.

**How to avoid:**
- Every router leg must be **caller-bounded** (a `maxCount` / explicit gas budget the caller pays for), never contract-bounded over a growable set. Reuse the cursor model for the buy leg; for the open leg use caller-supplied off-chain-discovered `(player, ids)` lists (the crank plan's chosen model — no on-chain enumeration → no DoS) OR a bounded resuming cursor.
- Per-item isolation via the `onlySelf` external sub-call + try/catch so one stale/already-resolved/not-ready/deep-reverting item (e.g. the `_distributePayout` solvency check) skips-and-continues and rewards only successes — never bricks the batch.
- Keep the advance-due check O(1) (read the day index / flags), never a scan.
- Verify the swap-pop cursor pattern (`_removeFromSet` `:869`, "no cursor-advance after swap-pop") survives the router wrapper — the H-CANCEL-SWAP-MISS class (a relocated tail behind the cursor missing a day) must not reappear (enumerate every `ticketQueue`/subscriber-set consumer the router introduces).

**Warning signs:**
Any on-chain loop in the router whose iteration count is set by a permissionlessly-growable structure. A discovery step without a caller-supplied bound. A dispatch loop without per-item try/catch isolation. A reverting single item that fails the whole router call in a test.

**Phase to address:**
SPEC (lock the discovery model per leg: caller-bounded cursor or caller-supplied list, O(1) advance-due check) + IMPL (per-item `onlySelf`+try/catch isolation; caller-bounded iteration) + TST (non-brick: one reverting item skipped, batch completes; growable-set DoS resistance; swap-pop no-miss) + TERMINAL (zero-day-hunter charges set-inflation DoS).

---

### Pitfall 6: Re-entrancy across router → game.advanceGame / autoOpen → creditFlip / batchPurchase

**What goes wrong:**
The router crosses contract boundaries: AfKing → `game.batchPurchase{value}` (`AfKing.sol:821`) which fires the mint module; → `game.advanceGame` (delegatecalls modules, runs jackpot payouts that `creditFlip` and send ETH); → `coinflip.creditFlip` (`AfKing.sol:846`). A reentrant call back into the router (or into `withdraw`/`subscribe`/`autoBuy`) mid-dispatch could double-pay a bounty, double-buy for a player, double-advance, or re-enter while the cursor/`_poolOf` is in an intermediate state. The autoBuy path already relies on CEI (pool debit BEFORE the batched external call `:766-768`; day-stamp after) — the router must preserve this across all legs, and the advance-consume path sends ETH to jackpot winners (an external-call reentrancy surface).

**Why it happens:**
Composing three external-boundary-crossing operations into one entrypoint multiplies the reentrancy surface. Each leg may have been CEI-safe alone, but the router's sequencing (debit/credit/cursor writes interleaved with external calls and ETH sends) can open a window where a reentrant call sees inconsistent state. The crank plan flagged this as `OPEN-C` (reentrancy disposition on the batchPurchase callback — CEI proof vs explicit guard) and it was never fully closed for a *router*.

**How to avoid:**
- Prove CEI for every router leg: all state effects (pool debits, cursor advance, day-stamps, bounty accounting) committed BEFORE the external call that could reenter; the bounty `creditFlip` fires LAST (`AfKing.sol:846` does this for autoBuy — preserve it).
- Decide OPEN-C explicitly for the router: either a strict CEI proof across the *composed* legs OR a `nonReentrant`-style guard on the router entrypoint (and on `withdraw`/`subscribe` if they can be reentered mid-router). Given the security floor (`feedback_security_over_gas`), a reentrancy guard is cheap insurance vs a subtle composed-CEI proof.
- Verify the advance-consume's ETH sends to jackpot winners (and the redemption resolve) cannot reenter the router to collect a second bounty or re-trigger the same category.
- Confirm a reentrant `autoBuy`/`withdraw` during the batched purchase cannot double-spend `_poolOf` (the debit-before-call is the guard — test it).

**Warning signs:**
Any router leg where an external call (mint, advance, ETH send, creditFlip) precedes a state write. No reentrancy guard AND no explicit composed-CEI proof. A test where a malicious player contract reenters the router from a mint/payout callback and earns a second bounty or double-buys.

**Phase to address:**
SPEC/IMPL (close OPEN-C for the router: CEI proof or explicit guard; bounty `creditFlip` last) + TST (reentrancy regression: reentrant call from mint/payout callback cannot double-pay/double-buy/double-advance) + TERMINAL (zero-day-hunter charges the composed reentrancy surface).

---

### Pitfall 7: Stall-multiplier abuse — forcing or faking a stall to inflate the escalated bounty (1/2/4/6, possibly extended)

**What goes wrong:**
The multiplier escalates by elapsed time since day-start (autoBuy: 2× @20m / 4× @1h / 6× @2h `AfKing.sol:831-837`; advance: same bands `AdvanceModule.sol:248-254`). A caller who can *cause* or *wait out* a stall collects a richer bounty for the same work:
- **Wait-and-grab:** a keeper deliberately does NOT call the router early, lets the multiplier climb to 6×, then sweeps everything at the inflated rate — the protocol pays 6× for work that was always available at 1×. This is rational if the 6× reward exceeds gas while 1× didn't (which is *intended* — that's how the multiplier buys liveness) but becomes abusive if 6× far exceeds gas, turning routine keeping into a daily 6× payout.
- **Force-the-stall:** if extending the ceiling for "extreme stalls" introduces a higher band (e.g., 12×/24× after days), an attacker who can briefly brick the cheap path (e.g., make every early item revert/skip so no one profits at 1–6×) can push the multiplier into the extended band, then collect.
- **Mid-day vs new-day band confusion:** the autoBuy day-start uses `today*1 days + 82_620` (`:829`); the advance uses `(day-1 + DEPLOY_DAY_BOUNDARY)*1 days + 82_620` (`:243-246`). Re-homing the advance bounty into the router must use a single, consistent day-start so the multiplier can't be double-counted or computed against the wrong epoch.

**Why it happens:**
The multiplier is a liveness incentive (richer reward for lagging work), but every "richer reward for a condition the caller can influence" is a manipulation vector. Extending the ceiling for extreme stalls (a v49 option) widens the band an attacker can aim for. The two different day-start formulas are an integration hazard when unifying.

**How to avoid:**
- Keep the multiplier capped such that **even the maximum band stays bounded relative to real worst-case gas** — the ×6 (or extended) reward should cover *stressed* gas, not be a windfall (ties to Pitfall 2).
- Prove the multiplier is a function only of `block.timestamp` and the on-chain day boundary — NOT of any caller-suppliable input — so it can't be spoofed (the current code reads only `block.timestamp` and `today`/`day`; preserve this).
- Unify the day-start computation: the router's advance leg and autoBuy leg must use ONE day-start epoch so the multiplier is computed identically and once.
- Accept "wait-and-grab" as the intended cost of liveness, but bound the windfall: document that 6× (or extended) is the ceiling and that it covers gas at the design's worst-case price — not an arbitrarily large multiple.
- If extending the ceiling, verify no actor can *cause* the stall cheaply (Pitfall 5's brick-the-cheap-path vector); the extended band must require a *genuine* multi-day VRF/liveness stall, not an attacker-induced one.

**Warning signs:**
A multiplier band whose max reward ≫ stressed gas. Two day-start formulas in the unified router. Any multiplier input the caller can supply. An extended ceiling reachable by attacker-induced (not genuine) stall. A test that brick-skips early items to push the multiplier up.

**Phase to address:**
SPEC (lock the extended-ceiling value and the single day-start epoch; prove multiplier inputs are timestamp-only) + GAS (cap the max-band reward to stressed-gas, not windfall) + TST (multiplier-vs-wallclock determinism; cannot-induce-stall) + TERMINAL (economic-analyst charges wait-and-grab + force-stall).

---

### Pitfall 8: "advanceGame is now unrewarded" — second-order liveness failure (no one ticks the game)

**What goes wrong:**
After re-homing, standalone `advanceGame()` pays nothing; the advance bounty flows ONLY through the router. The intended fallback ("direct advanceGame stays an unrewarded fallback for when the router path is broken") only works if **someone actually calls the unrewarded fallback**. If the router path breaks (a bug, a revert in the open/buy legs that the advance leg is coupled to, a paused dependency, or the router simply being un-deployed/mis-wired), and the unrewarded `advanceGame` is the only remaining tick path, the rational-actor incentive to call it is **zero**. The daily tick drives the entire game (RNG request/consume, jackpot payouts, redemption resolution, level transitions, the liveness death-clock). If nobody ticks, the game stalls toward the ~120-day liveness-triggered premature game-over (the v45 failure mode).

**Why it happens:**
"Unrewarded fallback" assumes some party (the protocol operator, the VAULT, a player who *wants* their jackpot/level to advance) will call it for free. That's a soft assumption, not a guarantee. Re-homing concentrates the liveness incentive into the router; if the router is the single point of failure for *paid* advancement, a router bug becomes a liveness bug. The coupling in the router (advance-if-due → open → buy) also means a revert in a later leg could prevent the advance leg from being reached/rewarded, silently degrading advance liveness even while the router "works."

**How to avoid:**
- Verify the **standalone `advanceGame()` remains fully functional and callable** (unrewarded ≠ disabled) — it must still drive the full tick so the fallback is real, not nominal.
- Identify the structural fallback callers who advance for free even without a bounty: protocol-owned subs (VAULT, sDGNRS), and any player whose own pending jackpot/level/redemption *requires* the tick (they're motivated to advance to unlock their winnings). Confirm at least one such party always exists and can reach the unrewarded path.
- Ensure the advance leg in the router is **reachable and rewarded independent of the open/buy legs** — advance-if-due must run (and pay) even if there's no open/buy work, and must not be gated behind a leg that can revert (ties to Pitfall 4's early-return: advance is the highest priority, so it runs first).
- Keep the stall multiplier on the *router's* advance leg so that even if normal keeping lapses, the escalating reward eventually makes *someone* route-advance (the primary liveness backstop); the unrewarded standalone is the secondary backstop; the ~120-day liveness game-over is the tertiary.
- Treat the router as a liveness-critical contract: a mis-wire (wrong `AF_KING`/`COINFLIP`/`GAME` address) must fail loudly at deploy, not silently disable paid advancement.

**Warning signs:**
A standalone `advanceGame()` that reverts or no-ops after the rework (fallback is nominal, not real). An advance leg gated behind open/buy work (won't run on a no-other-work day). No identified always-present free-fallback caller. A router whose advance leg can be starved by a revert in another leg. No deploy-time wiring check.

**Phase to address:**
SPEC (prove standalone advanceGame stays functional+callable; identify guaranteed free-fallback callers; advance leg runs first + independent of other legs) + IMPL (advance-if-due highest priority, reachable without other work) + TST (liveness: standalone advanceGame still drives the full tick; router advance leg runs on a no-open/no-buy day; stall multiplier still escalates) + TERMINAL (zero-day-hunter charges router-as-single-point-of-failure for liveness; regression confirms the ~120-day death-clock still latches as the tertiary backstop).

---

## Technical Debt Patterns

Shortcuts that seem reasonable but create long-term problems.

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Calibrate the bounty peg at a single gas price (0.5 gwei) only | Simple, one number | Liveness band undocumented; ×6 ceiling may not cover stressed gas | Only if the stress-band analysis is done separately and the ceiling verified |
| Reward fall-through (router pays >1 category per tx) | "Caller did more work, pay more" UX | Re-opens the faucet via bounty-stacking (Pitfall 4) | Never |
| On-chain work discovery loop in the router | "Click-a-button" UX, no off-chain indexer | Unbounded-loop DoS over a growable set | Only with a strict caller-bounded cursor/`maxCount`, never unbounded |
| Composed-CEI proof instead of a reentrancy guard on the router | Saves ~2.1k gas/call | Subtle, easy to break on a later edit; one missed ordering = double-pay | Acceptable only with an airtight, test-backed CEI proof; given the security floor, prefer the guard |
| "Unrewarded fallback will get called by someone" | No need to fund the fallback | Soft liveness assumption; router bug → game stall | Acceptable only with an *identified, structurally-guaranteed* free caller + the stall multiplier on the router's advance leg |
| Lower VRF `requestConfirmations` for gas | Cheaper advance tx | Shortens the window/weakens unpredictability — violates the freeze floor | Never (security floor) |

## Integration Gotchas

Common mistakes when connecting cross-contract / to external services.

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| `coinflip.creditFlip` (bounty mint) | Treating credited BURNIE as if it were paid liquid value | It's illiquid stake that must survive the coinflip edge — the third faucet lock; keep it last in the tx (CEI) |
| `game.batchPurchase` (AF_KING-gated) | Forgetting per-slice try/catch → one bad player bricks the batch | Per-player isolation; one value transfer; refund unspent once to the keeper (`AfKing.sol:821` model) |
| `game.advanceGame` (two-phase VRF commit) | Assuming the word is available in the same tx as the request | Request returns word==1 + sets `rngLockedFlag`; consume is a SEPARATE tx after the Chainlink callback (10/4 confirmations) |
| Chainlink VRF coordinator | Lowering confirmations or assuming the advancer can bias entropy | Keep 10 daily / 4 mid-day; entropy is coordinator-derived; only the freeze invariant on in-window state is the caller's surface |
| `DegenerusAffiliate` (VAULT code on autoBuy) | Passing a spoofable/owner-mismatched code; foreclosing a real human affiliate | Use VAULT's *registered* immutable code (`:436/449`); real human affiliates keep theirs (`:463-476`) — confirm VAULT holds a registered code at SPEC |
| Pinned address constants (`AF_KING`, `COINFLIP`, `GAME`) | Mis-wiring the router so paid advancement silently breaks | Fail-loud deploy-time wiring check; the gates (`onlyFlipCreditors`/`onlyAfKing`) must pin exactly the deployed router/keeper |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| On-chain enumeration of a growable subscriber/box/bet set in the router | Router tx gas climbs with set size; eventually OOG | Caller-bounded cursor / caller-supplied lists; O(1) advance-due check | When the set exceeds ~block-gas / per-item cost (attacker can force this cheaply via permissionless `depositFor`/subscribe) |
| Per-item `onlySelf` try/catch sub-call overhead | High gas per item dominates the bounty | Weigh the self-call (~one CALL) vs the ~100k+ resolve at GAS; keep `maxCount` caller-bounded so the caller pays for iteration | When per-item overhead pushes the marginal cost above the bounty (kills the gas-blind cohort's participation) |
| Stacked bounty accumulation across many players in one autoBuy chunk | One `creditFlip` of `batchLen × per-player × multiplier` — large emission per tx | Per-player marginal peg (CR-01 lesson); cap `maxCount`; the coinflip illiquidity caps realized value | When the per-player peg is set to a total instead of a marginal (the v46 CR-01 faucet) |

## Security Mistakes

Domain-specific (beyond generic Solidity).

| Mistake | Risk | Prevention |
|---------|------|------------|
| Per-item bounty ≥ marginal cost to manufacture the item | Self-crank/wash faucet drain of uncapped BURNIE | Three faucet locks (purchase-gate + marginal gas-peg + coinflip illiquidity); round-trip ≤ 0 test |
| Router pays >1 category per tx (no early-return) | Bounty-stacking faucet | Structural "one rewarded category per call" invariant + early-return |
| Reading a player-mutable variable (`totalFlipReversals`, in-window SLOADs) into the consumed VRF word without freeze | Advance-timing manipulation of jackpot/redemption outcomes | Hold the v45 freeze invariant; backward-trace every consumer; freeze across request→unlock even when the consume is router-triggered |
| External call before state write in any router leg | Reentrancy → double-pay / double-buy / double-advance | CEI on every leg; bounty `creditFlip` last; close OPEN-C (guard or proof) |
| Stall multiplier reachable by attacker-induced stall | Inflated bounty for self-created scarcity | Multiplier = timestamp-only; extended ceiling requires genuine VRF/liveness stall; cap max-band to stressed-gas |
| Disabling (not just un-rewarding) standalone `advanceGame` | Router becomes single point of failure for liveness | Keep standalone advanceGame fully functional; identify guaranteed free fallback caller; ~120-day death-clock as tertiary backstop |
| Mis-wired pinned router/keeper address | Silent loss of paid advancement | Fail-loud deploy wiring check; gates pin the exact deployed address |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| "Bounty earned" shown as liquid BURNIE | Caller expects spendable tokens, gets illiquid coinflip stake | Surface the bounty as coinflip stake (must be flipped/claimed) in events/UI; `AutoBuyCompleted.bountyEarned` is stake, not balance |
| Router silently no-ops when nothing is due | Caller pays gas for a do-nothing tx | The no-buy revert (`NoSubscribersAutoBought` `:806`) is intentional anti-spam — keep it, but make the router clearly signal "nothing to do" vs "did work" |
| Caller can't tell which category the router will pick | Confusion about reward/cost before sending | View helper that previews the next due category + estimated bounty (off-chain or a `view`) |

## "Looks Done But Isn't" Checklist

- [ ] **Faucet locks:** Re-attested against the *unified router* (not just the old standalone functions) — verify self-crank/Sybil round-trip ≤ 0 for each leg AND the combined tx
- [ ] **Bounty peg:** Verify the ETH-peg is level-invariant AND the ×6/extended ceiling covers *stressed* gas (not just 0.5 gwei) — document the liveness gas band
- [ ] **Advance-timing freeze:** Verify `totalFlipReversals` + every in-window SLOAD is frozen request→unlock *even when the consume is router-triggered in the same tx as buy/open*
- [ ] **One-category-per-call:** Verify the router structurally returns after the first rewarded category (no fall-through; advance runs first)
- [ ] **Reentrancy:** OPEN-C closed for the router (guard or test-backed composed-CEI proof); bounty `creditFlip` fires last
- [ ] **Stall multiplier:** Single day-start epoch across the unified legs; timestamp-only inputs; extended ceiling requires genuine stall
- [ ] **Unrewarded fallback:** Standalone `advanceGame()` still fully drives the tick; an identified free-fallback caller exists; the ~120-day death-clock still latches
- [ ] **VRF confirmations:** Unchanged (10 daily / 4 mid-day) — no gas-driven reduction
- [ ] **Swap-pop no-miss:** The H-CANCEL-SWAP-MISS class (relocated tail behind cursor missing a day) does not reappear in any router-introduced set consumer
- [ ] **Wiring:** Pinned `AF_KING`/`COINFLIP`/`GAME` addresses fail loud on mis-wire

## Recovery Strategies

When pitfalls occur despite prevention, how to recover. (Pre-launch redeploy-fresh per `feedback_frozen_contracts_no_future_proofing` — storage breaks are fine, so most recoveries are "fix + redeploy before mainnet.")

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| Faucet drain (peg too high / stacking) | LOW (pre-launch) | Re-derive marginal peg; enforce one-category early-return; re-run round-trip test; redeploy |
| Liveness stall (no one ticks) | MEDIUM | Confirm standalone advanceGame works; have a protocol-owned sub / VAULT call the unrewarded fallback; the stall multiplier + death-clock are the on-chain backstops |
| Advance-timing freeze violation | HIGH (security-critical) | Treat as a v45-class freeze finding; re-trace every consumer; re-freeze the in-window variable; extend the RngLockDeterminism fuzz; redeploy |
| Reentrancy double-pay/double-buy | HIGH | Add the router reentrancy guard; re-attest CEI on every leg; redeploy |
| Unbounded-loop DoS | LOW (pre-launch) | Convert discovery to caller-bounded cursor/list; redeploy |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| 1. Faucet drain / self-crank | GAS (marginal peg) + IMPL (locks) | Round-trip ≤ 0 test per leg + combined (TST); economic-analyst (TERMINAL) |
| 2. Break-even mis-calibration | GAS (worst-case-first, stress band, level-invariance) | Stressed-gas band documented; ×6/extended covers it (GAS); economic-analyst (TERMINAL) |
| 3. Advance-timing / MEV | SPEC (router ordering + freeze) | Freeze-invariant fuzz on `totalFlipReversals` + in-window SLOADs (TST); zero-day-hunter (TERMINAL) |
| 4. Bounty-stacking in router | SPEC (one-category invariant) + IMPL (early-return) | Single-category-reward-per-tx test (TST); economic-analyst (TERMINAL) |
| 5. Gas-griefing / unbounded-loop DoS | SPEC (discovery model) + IMPL (cursor/list + isolation) | Non-brick + set-inflation DoS resistance (TST); zero-day-hunter (TERMINAL) |
| 6. Reentrancy across router legs | SPEC/IMPL (close OPEN-C) | Reentrancy regression from mint/payout callback (TST); zero-day-hunter (TERMINAL) |
| 7. Stall-multiplier abuse | SPEC (ceiling + epoch) + GAS (cap to stressed-gas) | Multiplier-vs-wallclock determinism + cannot-induce-stall (TST); economic-analyst (TERMINAL) |
| 8. Unrewarded-advance liveness | SPEC (fallback real + free caller) + IMPL (advance first/independent) | Standalone advanceGame drives full tick; router advance on no-other-work day; death-clock latches (TST); zero-day-hunter (TERMINAL) |

## Sources

- `contracts/AfKing.sol` (v48.0-closure tree) — autoBuy bounty math `:845`, stall multiplier `:823-838`, cursor/self-partition `:577/597/794`, swap-pop `:869`, CEI debit-before-call `:766-768`, no-buy revert `:806`, permissionless `depositFor` `:304`, `creditFlip` bounty `:846` — HIGH
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `ADVANCE_BOUNTY_ETH` `:147`, advance bounty creditFlip `:189/225/468-471`, stall multiplier `:241-255`, two-phase VRF commit (`rngGate` `:1168`, `_requestRng` confirmations `:119-120/1094`), `_applyDailyRng` totalFlipReversals nudge `:1838-1844`, redemption roll from word `:1219-1221`, liveness/game-over path `:510-573` — HIGH
- `contracts/BurnieCoinflip.sol` — `creditFlip`/`onlyFlipCreditors` (AF_KING authorized) `:197-201/859-865`, illiquid stake model — HIGH
- `contracts/BurnieCoin.sol` — `burnForKeeper` all-or-nothing `onlyAfKing` `:472-549`, uncapped vaultAllowance mint surface — HIGH
- `.planning/PLAN-CRANK-DO-WORK-INCENTIVE.md` — §7 three faucet locks, §5 cursor/CEI/non-brick, §9 OPEN-C reentrancy / OPEN-D enumeration-DoS, CR-01 marginal-peg lesson — HIGH
- `.planning/PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md` — autoBuy/autoOpen/autoResolve naming, VAULT registered affiliate code `DegenerusAffiliate.sol:436/449/463-476` — HIGH
- Project memory: `v45-vrf-freeze-invariant`, `feedback_rng_backward_trace`, `feedback_rng_window_storage_read_freshness`, `feedback_gas_worst_case`, `feedback_security_over_gas`, `project_free_burnie_crank_button` — HIGH
- [Cyfrin — Solodit Checklist: Griefing Attacks](https://www.cyfrin.io/blog/solodit-checklist-explained-5-griefing-attacks) — gas-griefing recurring-tax / liveness-DoS pattern — MEDIUM
- [Bitquery — Different MEV Attacks](https://bitquery.io/blog/different-mev-attacks) + [LBank Labs — MEV 101: Manipulating Time](https://lbanklabs.medium.com/mev-101-a-glimpse-into-mev-the-magic-of-manipulating-time-4ded801647f8) — advance/transaction-timing MEV classes — MEDIUM

---
*Pitfalls research for: permissionless keeper "do-work" router + gas-pegged bounty (Degenerus Protocol v49.0)*
*Researched: 2026-05-26*
