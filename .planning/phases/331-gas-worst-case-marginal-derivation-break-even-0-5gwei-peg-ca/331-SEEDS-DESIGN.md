# 331 Seeds Design — Seed 1 (shared-slot DGNRS affiliate aggregation) + Seed 2 (pre-validated keeper batch path)

**Authored:** 2026-05-27 (Phase 331 GAS, plan 331-03 — wave 2)
**Status:** design enumeration complete; the contract code is the GATED 331-05 diff (NOT this plan)
**Covers:** CONTEXT D-06 (Seed 1) + D-07 (Seed 2); rides the GAS-02 contract diff
**Source-verified against:** the committed `63bc16ca` `contracts/` (every `file:line` below was read this session)

> **HARD CONSTRAINT (security floor — `feedback_security_over_gas`, CONTEXT "HARD CONSTRAINT"):**
> A reverting / funding-skipped player must **NEVER** brick the keeper batch. The per-player
> isolation is a SECURITY property, not gas hygiene. Seed 2 may replace the *mechanism*
> (`this._batchPurchaseUnit{value}` try/catch → pre-validation / cheap-skip) but MUST preserve
> the *liveness*. Seed 1 may aggregate only **SUCCESSFUL** (non-reverted / non-skipped) units —
> a poisoned player must contribute ZERO and must not leak another player's credit.

---

## 0. The surface under design (the keeper buy money path, verbatim from `63bc16ca`)

```
AfKing._autoBuy(maxCount)                         AfKing.sol:561
  -> builds [players][amounts][modes] (only fundable/non-skipped subs; CEI-debited pool)
  -> IGame(GAME).batchPurchase{value: totalValue}(players, amounts, modes)   AfKing.sol:774
        DegenerusGame.batchPurchase(players, amounts, modes)     DegenerusGame.sol:1757
          if (msg.sender != AF_KING) revert E();                          :1762  (whole-batch gate)
          if (gameOver) revert E();                                       :1763  (whole-batch gate)
          for i in players:
            try this._batchPurchaseUnit{value: amounts[i]}(players[i], modes[i]) { spent += } catch {}   :1773
          if (msg.value > spent) refund keeper once                       :1787
        DegenerusGame._batchPurchaseUnit(player, payKind) onlySelf        :1798
          _purchaseFor(player, 0, msg.value, bytes32("DGNRS"), payKind)   :1806
        DegenerusGame._purchaseFor(...) delegatecall GAME_MINT_MODULE.purchase  :513-533
        MintModule._purchaseFor(buyer, 0, lootBoxAmount=msg.value, "DGNRS", payKind)  MintModule:997
          ... affiliate.payAffiliate(... "DGNRS" ...)   (lootbox affiliate leg)
```

**KEEP-04 capture (the Seed 1 same-recipient premise — grep-confirmed):**
- `DegenerusAffiliate.sol:247-250` — `affiliateCode["DGNRS"].owner == ContractAddresses.SDGNRS` (NOT VAULT).
- `:252-253` — cross-referral upline `SDGNRS → VAULT` (`_setReferralCode(SDGNRS, "VAULT")`) and `VAULT → DGNRS` (`_setReferralCode(VAULT, "DGNRS")`).
- So a whole `bytes32("DGNRS")` keeper batch resolves to a CONSTANT `affiliateAddr = SDGNRS` and a CONSTANT 75/20/5 winner roll among `{SDGNRS (75%), VAULT (20% upline1), SDGNRS-of-VAULT = DGNRS-code-owner (5% upline2)}`. The recipients are fixed addresses, constant across all players in the batch — the aggregation premise holds.

---

## SEED 2 — replace `batchPurchase` per-player try/catch with pre-validation

### 2.1 Every `_batchPurchaseUnit -> _purchaseFor -> MintModule.purchase` revert source (enumerated)

The keeper buy always calls `_purchaseFor(player, ticketQuantity=0, lootBoxAmount=msg.value, "DGNRS", payKind)`
where `payKind ∈ {DirectEth, Claimable, Combined}` and the slice IS the lootbox amount (tickets=0).
Wait — the keeper buy can ALSO be a TICKET buy: `_resolveBuy` sets `payKind` and `msgValue`, and
`_batchPurchaseUnit` forwards `msg.value` as the `lootBoxAmount` arg of `_purchaseFor`. Re-reading
`_batchPurchaseUnit` (`DegenerusGame.sol:1806`): the call is literally
`_purchaseFor(player, 0, msg.value, bytes32("DGNRS"), payKind)` — **ticketQuantity is hard-zero, the
slice is always the lootBoxAmount.** So the keeper buy path is a **lootbox-only** purchase. That
narrows the reachable revert set materially (the ticket-cost / `_callTicketPurchase` / `ENF-01`
branch at `MintModule:1053-1069` is `ticketCost != 0`-gated and is NOT reached). Enumerated below,
each with a pre-validate-or-cheap-skip disposition.

| # | Revert source (file:line) | Trigger on the keeper lootbox-only path | Disposition | Where pre-gated |
|---|---------------------------|-----------------------------------------|-------------|-----------------|
| R1 | `gameOver` whole-batch | `DegenerusGame.sol:1763` | already a WHOLE-BATCH entry gate (single revert, not per-player) — KEEP | batchPurchase entry |
| R2 | `_livenessTriggered()` → `revert E()` | `MintModule:1004` | **pre-validate ONCE pre-loop** — liveness is a global flag, identical for every player in the batch (mirror the `autoOpen` RD-5 entry-gate: `DegenerusGame.sol:1671` excludes `_livenessTriggered()` pre-loop). If triggered, the whole batch no-ops/returns (no per-player attempt). | batchPurchase entry (NEW) |
| R3 | `lootBoxAmount < LOOTBOX_MIN` (and `!=0`) → `revert E()` | `MintModule:1011` | **cheap-skip per player** — `if (slice < LOOTBOX_MIN) continue;` (the keeper already pre-skips this view-side in `_resolveBuy` `lootboxSkip` at `AfKing.sol:819`, but the GAME side must still skip defensively — a caller-malformed slice must not revert the batch). | per-player skip (NEW) |
| R4 | `totalCost == 0` → `revert E()` | `MintModule:1020` | **subsumed by R3** — with tickets=0, `totalCost == lootBoxAmount`; a zero slice is `< LOOTBOX_MIN` so the R3 cheap-skip catches it first. | per-player skip (R3) |
| R5 | `payKind == DirectEth && remainingEth < lootBoxAmount` → `revert E()` | `MintModule:1036` | **pre-validate per player**: for a `DirectEth` slice the forwarded `msg.value` slice MUST be `>= lootBoxAmount`. The keeper sets `msgValue = cost` for DirectEth (`AfKing.sol:822-823/836-838`) so `remainingEth == lootBoxAmount` by construction; assert/skip if a malformed caller breaks it (`if (payKind == DirectEth && slice < lootBoxAmount) continue;`). For `Combined`/`Claimable` this branch draws claimable shortfall and does NOT revert here. | per-player pre-validate (NEW) |
| R6 | `_settleClaimableShortfall` underflow (Combined/Claimable shortfall > buyer claimable) | `MintModule:1044` (inside `_settleClaimableShortfall`) | **pre-validate per player**: a `Combined`/`Claimable` slice needs `claimableWinnings[player] >= shortfall`. The keeper's `_resolveBuy` waterfall (`AfKing.sol:826-838`) already sizes `msgValue`/`payKind` from a FRESH `keeperSnapshot` claimable read so the shortfall is covered at slice-build time — BUT claimable can move between the keeper's snapshot and the GAME call (a concurrent withdraw / another keeper). The GAME side must read `claimableWinnings[player]` and **cheap-skip** if it cannot cover the shortfall, never revert. | per-player pre-validate (NEW) — read claimable, skip if short |
| R7 | lootbox same-day re-deposit mismatch `storedDay != lbDay` → `revert E()` | `MintModule:1096` | **cannot occur on a fresh keeper buy within one day** — first deposit takes the `existingAmount == 0` branch (`:1084`); a same-day second deposit has `storedDay == lbDay`. Cross-day is impossible inside one tx. **Defensive cheap-skip** anyway (read `lootboxDay[index][player]`; if non-zero and `!= today`, skip) — cheaper than a try/catch and preserves liveness. | per-player pre-validate (NEW) — defensive |
| R8 | `enqueueBoxForAutoOpen` (onlySelf push) | `MintModule:1094` → `DegenerusGame.sol:1567` | **never reverts** for a self-call (the `msg.sender != address(this)` guard passes on the internal delegatecall path); a `push` cannot revert short of OOG. No gate needed. | n/a |
| R9 | presale-box branch reverts (`presaleOver`, `PRESALE_BOX_MIN`, sold-out, etc.) | `MintModule:1371-1438` | **NOT reachable** — that is `purchasePresaleBox`/`buyPresaleBox`, a DIFFERENT entrypoint, not `_purchaseFor`. The keeper buy is `_purchaseFor` (lootbox). Out of scope. | n/a |
| R10 | OOG / stack-depth | any | NOT a logical revert source; the per-player slice is bounded (one box deposit). The existing path already runs this under one sub-call frame's gas. No gate; the keeper bounds `maxCount`. | n/a |

**Residual after pre-gating:** R2 (liveness, whole-batch) + R1 (gameOver, whole-batch) move pre-loop;
R3/R5/R6/R7 become **cheap per-player view checks that `continue` (skip) instead of reverting**. After
those gates the internal `_purchaseFor` call is **guaranteed-non-reverting for the lootbox-only keeper
slice** — exactly the property `autoOpen` achieved (RD-5, `DegenerusGame.sol:1667-1701`). No revert
source is left un-dispositioned.

> **Note on `_settleClaimableShortfall` (R6) — the one source that is NOT a pure global flag.**
> It is per-player state that can change between the keeper's `keeperSnapshot` and the GAME call.
> This is why a NAIVE "pre-validate once and call without any per-player guard" is unsafe — Seed 2
> MUST keep a per-player **cheap-skip** (a single `claimableWinnings[player]` SLOAD + compare +
> `continue`), NOT a blanket "all slices are safe now." The try/catch is removed; the per-player
> ISOLATION (skip + slice not consumed) is preserved by the cheap-skip.

### 2.2 Chosen path shape (CONTEXT "Claude's Discretion": new function vs internal helper)

**DECISION: a NEW keeper-specialized batch path `batchPurchaseForKeeper` (a separate external,
AF_KING-gated function), NOT a parameterized branch inside the existing `batchPurchase`.**

Justification from the revert-source enumeration:
1. **R6 forces a per-player view check that the player-facing path never needs.** The existing
   `batchPurchase` relies on the try/catch to absorb R3/R5/R6/R7; converting it in place would
   entangle the keeper-only pre-validation logic with the (kept-for-safety) player path. A separate
   function keeps the player-facing `_purchaseFor` / normal `purchase` semantics untouched
   (scope fence: "Seed 2 = a keeper-specialized batch path; do NOT alter the normal player-facing
   `batchPurchase`/`_purchaseFor` semantics").
2. **Seed 1 (return-the-affiliate-contribution + aggregate-at-tail) requires the unit to RETURN a
   value** — `_batchPurchaseUnit` is `external onlySelf` returning `void` today. The keeper path
   needs an INTERNAL helper that returns the per-unit coalescible affiliate contribution. A new
   internal `_keeperBuyUnit(player, payKind) returns (KeeperAffAcc memory)` called directly (no
   external self-call, no try/catch) is the clean shape; the external `batchPurchaseForKeeper`
   wraps the loop + tail flush.
3. **The cheap-skips make the external self-call (`this._batchPurchaseUnit{value}`) pointless** —
   its only purpose was the try/catch revert-isolation. Once every reachable revert is pre-gated,
   the call becomes a plain internal call, saving the CALL overhead per player on top of the SSTORE
   savings (Seed 1).

**The new path (pseudocode, the 331-05 blueprint):**
```solidity
function batchPurchaseForKeeper(address[] players, uint256[] amounts, uint8[] modes) external payable {
    if (msg.sender != AF_KING) revert E();
    if (gameOver) revert E();                       // R1 whole-batch
    if (_livenessTriggered()) { _refundAll(); return; }  // R2 whole-batch (NEW pre-loop gate)
    uint256 len = players.length;
    if (len == 0 || amounts.length != len || modes.length != len) revert E();

    KeeperAffAcc memory acc;                         // Seed 1 accumulator (sum across SUCCESSFUL units)
    uint256 spent;
    uint24 lvl = ...;                                // purchaseLevel, constant across the batch
    for (uint256 i; i < len; ) {
        uint256 slice = amounts[i];
        MintPaymentKind pk = MintPaymentKind(modes[i]);
        // ---- cheap per-player pre-validation (R3/R5/R6/R7) — skip, never revert ----
        if (slice < LOOTBOX_MIN) { _skip(); continue; }                       // R3/R4
        if (pk == DirectEth && slice < /*lootBoxAmount==slice*/ slice) {}      // R5 (DirectEth: slice == lootBoxAmount by construction; defensive)
        if ((pk == Combined || pk == Claimable) && claimableWinnings[players[i]] < _shortfall(slice, msg.value-spent...)) { _skip(); continue; } // R6
        if (lootboxDay[idx][players[i]] != 0 && lootboxDay[idx][players[i]] != today) { _skip(); continue; } // R7 defensive
        // ---- guaranteed-non-reverting internal unit; RETURNS its affiliate contribution ----
        AffContribution memory c = _keeperBuyUnit{??}(players[i], pk);   // see Seed 1 for value flow
        acc.coinEarned += c.coinEarned;          // coalescible (SDGNRS slot)
        acc.totalScore += c.totalScore;          // coalescible (_totalAffiliateScore[lvl])
        acc.flipCredit += c.flipCredit;          // coalescible (creditFlip to the winner)
        // (per-player affiliateCommissionFromSender is written INSIDE the unit — NOT coalesced)
        spent += slice;
        unchecked { ++i; }
    }
    _flushKeeperAff(acc, lvl);                   // Seed 1: ONE SSTORE per coalescible slot at the tail
    if (msg.value > spent) { refund keeper once; }
}
```

> **Liveness proof obligation for 331-05:** every `continue` above is a SKIP that (a) does not consume
> the slice (it stays in the contract, refunded at the tail) and (b) does not revert. The
> `CrankNonBrick` extension (this plan, Task 3) proves a poisoned middle player is skipped + refunded
> and the batch does not revert under this path.

---

## SEED 1 — aggregate shared-slot DGNRS affiliate writes across the keeper batch

### 1.1 The per-buy affiliate SSTORE table (confirmed against `DegenerusAffiliate.payAffiliate` `:388-615`)

For a `bytes32("DGNRS")` keeper batch the `affiliateAddr` (= SDGNRS), `storedCode` (= "DGNRS"),
`lvl` (= purchaseLevel), and the winner roll are CONSTANT across players (the roll keys on
`(AFFILIATE_ROLL_TAG, currentDayIndex, sender, storedCode)` `:585-594` — `sender` varies, but the
winner SET `{SDGNRS, VAULT, DGNRS-code-owner}` is fixed and the 75/20/5 distribution recipient is
one of three FIXED addresses). So each per-buy write either lands on the SAME slot N times
(coalescible) or a per-`sender` slot (not coalescible):

| Write | Line | Slot key | Coalescible across the DGNRS batch? |
|-------|------|----------|--------------------------------------|
| `affiliateCommissionFromSender[lvl][affiliateAddr][sender] = ...` | `:527` | `lvl + affiliateAddr + sender` | **NO — keyed on `sender` (the player). The ONLY non-coalescible write.** |
| `earned[affiliateAddr] = newTotal` (== `affiliateCoinEarned[lvl][SDGNRS]`) | `:537` | `lvl + affiliateAddr` | **YES — same slot every player → coalescible** |
| `_totalAffiliateScore[lvl] += scaledAmount` | `:538` | `lvl` | **YES — same slot → coalescible** |
| `_updateTopAffiliate(affiliateAddr, newTotal, lvl)` (leaderboard `affiliateTopByLevel[lvl]`) | `:548` | `lvl` (per-lvl PlayerScore) | **YES — same `lvl`/`affiliateAddr` → coalescible (write the final `newTotal` once)** |
| `_routeAffiliateReward(winner, affiliateShareBase + questReward)` → `coinflip.creditFlip(winner, ...)` | `:581 / :608` | the winner's coinflip stake slot (winner ∈ fixed set) | **YES — same recipient → coalescible (sum, one creditFlip per distinct winner)** |
| `quests.handleAffiliate(winner, affiliateShareBase)` | `:607` | per-winner quest accumulators | **YES if same winner → coalescible** |

**Confirmed: `affiliateCommissionFromSender` (`:527`) is the SOLE non-coalescible write.** Everything
else accumulates to a `lvl + affiliateAddr` / `lvl` / fixed-winner slot that recurs N times in a
keeper batch. CONTEXT D-06: "ONLY shared-slot rewards aggregate; player-specific credits cannot."

> **Per-referrer commission CAP interaction (`:516-528`, load-bearing for correctness):** the cap
> `MAX_COMMISSION_PER_REFERRER_PER_LEVEL` is read+written PER `(lvl, affiliateAddr, sender)`. Because
> the cap is keyed on `sender`, each player's `scaledAmount` is computed against THAT player's own
> running `affiliateCommissionFromSender` — so the aggregation MUST compute each unit's post-cap
> `scaledAmount` INSIDE the unit (reading/writing the per-`sender` cap slot) and only SUM the
> post-cap `scaledAmount` into the coalescible accumulators. Aggregating BEFORE the cap would change
> the money outcome. The delta-audit (Task 2) asserts the aggregate equals the sum of per-unit
> POST-cap contributions of the successful units.

### 1.2 The win sizing

For a keeper batch of N successful DGNRS buys, the coalescible writes recur N times to the same slots.
Coalescing them = sum in memory, ONE SSTORE per coalescible slot at the tail:
- `affiliateCoinEarned[lvl][SDGNRS]`: N writes → 1 (saves N−1)
- `_totalAffiliateScore[lvl]`: N writes → 1 (saves N−1)
- `affiliateTopByLevel[lvl]` leaderboard: N updates → 1 (saves N−1; write the final `newTotal`)
- `creditFlip(winner)` deferred-mint stake: N credits → up to 1 per distinct winner (≤3 winners)

Aggregate saving ≈ **(N−1) × (number of coalescible slots ≈ 3–4)** SSTOREs per keeper batch, on top
of the Seed 2 per-player CALL-overhead saving. `affiliateCommissionFromSender` stays N writes
(non-coalescible). Extra coalesce is possible if the SDGNRS/VAULT standing subs are processed in the
same tx (the buy-credit AND the affiliate-payee-credit then share a recipient slot) — opportunistic,
not required.

### 1.3 The acc-flush shape (mirror the degenerette `resolveBets` precedent)

Precedent: `DegenerusGameDegeneretteModule.sol:407-426` — `acc.burnieMint` / `acc.claimable` summed
across bets, then ONE `coin.mintForGame(player, acc.burnieMint)` + ONE claimable write at the tail
(`:426`). Copy that "sum-into-acc-struct, one flush at the tail" shape:

```solidity
struct KeeperAffAcc {        // memory accumulator, summed across SUCCESSFUL units only
    uint256 coinEarned;      // -> affiliateCoinEarned[lvl][SDGNRS] (final newTotal, ONE SSTORE)
    uint256 totalScore;      // -> _totalAffiliateScore[lvl] += (ONE SSTORE)
    // creditFlip totals per distinct winner -> ONE creditFlip per winner at the tail
    // leaderboard: write the final newTotal once
}
```

**Only SUCCESSFUL units sum (HARD CONSTRAINT).** A pre-validation-skipped (poisoned) player never
reaches `_keeperBuyUnit`, so it contributes nothing to `acc` and its slice is refunded — exactly as
the try/catch path skips today. The delta-audit (Task 2) asserts `aggregate == Σ post-cap
contributions of the successful units` and that a skipped player contributes ZERO and is refunded.

### 1.4 Implementation note for 331-05 (where the affiliate writes move)

`payAffiliate` (`DegenerusAffiliate.sol`) is a SEPARATE contract reached via the MintModule lootbox
leg. Two shapes are open for 331-05 (decide at implementation, both satisfy the equivalence the
delta-audit proves):
- **(a)** add a keeper-batch entry on `DegenerusAffiliate` that takes the per-player list and does
  the per-`sender` cap writes inline but the coalescible accumulators once at the tail; OR
- **(b)** have `_keeperBuyUnit` capture each unit's post-cap coalescible contribution (returned from
  a view-shaped `payAffiliate` variant) and flush from the GAME side.
Either way the per-`sender` `affiliateCommissionFromSender` cap write stays per-player and the
coalescible slots flush once. The delta-audit is shape-agnostic: it asserts the RESULTING
accumulators are byte-identical to today's per-buy path.

---

## No-brick / money-path invariants the gated 331-05 diff MUST satisfy

1. **No-brick (T-331-06):** a single reverting / funding-skipped / poisoned player NEVER bricks
   `batchPurchaseForKeeper`; it is cheap-skipped (no revert), its slice not consumed, refunded at
   the tail. (Proven by `CrankNonBrick.testKeeperBatchSkipsPoisonedMiddlePlayer` + the fuzz variant.)
2. **No double-credit (T-331-07):** the tail-flushed coalescible total == Σ post-cap contributions
   of the SUCCESSFUL units only. (Proven by `KeeperBatchAffiliateDeltaAudit`.)
3. **No skipped-player drain (T-331-08):** a skipped player contributes ZERO to every accumulator
   AND its slice is refunded — unchanged from today. (Proven by `KeeperBatchAffiliateDeltaAudit`.)
4. **Per-player commission stays per-player:** `affiliateCommissionFromSender[lvl][SDGNRS][sender]`
   is NOT coalesced (the per-`sender` cap is honored exactly as today).
5. **Byte-identical money outcomes:** `affiliateCoinEarned[lvl][SDGNRS]`, `_totalAffiliateScore[lvl]`,
   the SDGNRS/VAULT flip-credit balances, each player's `affiliateCommissionFromSender`, and each
   player's claimable delta are byte-identical between the current try/catch path and the proposed
   aggregated keeper-batch path. (The `_drive(useKeeperPath)` toggle in the delta-audit asserts this
   once 331-05 lands `batchPurchaseForKeeper`.)

---

*Phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca · plan 331-03 · 2026-05-27*
