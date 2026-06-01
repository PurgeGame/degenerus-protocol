# Phase 343 — SOLVENCY-01/03 Proof + GO_SWEPT Withdraw-Guard Lock + OPEN-E Carry-Over

**Plan:** 343-02 (Task 1) · **Requirements:** SOLVENCY-01, SOLVENCY-03 · ROADMAP Phase 343 Success Criteria 2 + 3
**Authored:** 2026-05-30 · **Subject HEAD (`contracts/`):** byte-identical to v53 HEAD **`83a84431`**
**Line source-of-truth:** `343-GREP-ATTESTATION.md` (Wave 1, re-pinned vs the live tree). Every `file:line`
below is the ACTUAL re-grepped line — NOT the doc-drifted upstream citation. Where `343-RESEARCH.md`
conflicts with the attestation (the `payAffiliate`/`handleAffiliate` name and the master-invariant `:5`
"second copy"), this proof follows the **attestation**.

> **Paper-only invariant honored:** this plan only READS/greps `contracts/*.sol` and WRITES this Markdown
> artifact. `git diff --name-only -- contracts/` is EMPTY — zero contract edits.

---

## 0. The D-CF-03 framing — there is NO new aggregate

The entire safety claim rests on one structural fact: **`keeperFunding` introduces no new solvency aggregate.**
It is a per-player mapping whose systemwide total rides INSIDE the existing reserved aggregate `claimablePool`:

```
INVARIANT (D-CF-03):   claimablePool  ==  Σ claimableWinnings[*]  +  Σ keeperFunding[*]
MASTER  (unchanged):   address(this).balance + steth.balanceOf(this)  >=  claimablePool
                       — single copy at DegenerusGame.sol:18 (the :5 "second copy" RESEARCH claimed
                         does NOT exist; :5 is `* @title DegenerusGame`).
```

`claimablePool` is the `uint128 internal claimablePool;` at `DegenerusGameStorage.sol:355`, declared under the
invariant comment block at `:345-354` (`INVARIANT: claimablePool >= sum(claimableWinnings[*])`, which v54 widens
to also cover `keeperFunding[*]`). Because the keeper total is folded into the SAME variable every free-ETH
reservation site already reads, **the safety claim is "every reservation site already reserves the keeper total
via `claimablePool`, with zero edits"** — and that must be PROVEN against source, site by site (Section A), with
the one lifecycle gap it leaves explicitly locked (Section B). `keeperFunding` is **CONFIRMED-NEW** — absent from
the entire `contracts/` tree today (`grep -rln "keeperFunding" contracts/` → 0 files), so there is no stale
partial definition to reconcile; the deposit credits `claimablePool` and `keeperFunding[funder]` in tandem (the
mirror of `_addClaimableEth`), and every consumer below already covers it.

This is the load-bearing spine. The 347 TERMINAL 3-skill sweep is far off, so the proof is front-loaded and
adversarially probed (Task 2, D-07) before any code is written.

---

## Section A — SOLVENCY-01: the five free-ETH reservation sites, walked against source

Every site computes `free ETH = totalBal − reserved` where `reserved` is (or includes) `claimablePool`. Since
`claimablePool == Σ claimableWinnings + Σ keeperFunding` (D-CF-03), each site reserves the keeper total
automatically — **no `keeperFunding` term is needed, and no edit is made.** The five sites BY NAME:

### A.1 — `JackpotModule.distributeYieldSurplus` (def `:688`; `claimablePool` in obligations `:693`)

```solidity
// contracts/modules/DegenerusGameJackpotModule.sol
:688  function distributeYieldSurplus(uint256) external {
:689      uint256 stBal = steth.balanceOf(address(this));
:690      uint256 totalBal = address(this).balance + stBal;
:691      uint256 obligations = _getCurrentPrizePool() +
:692          _getNextPrizePool() +
:693          claimablePool +            // ← the keeper total rides inside this term
:694          _getFuturePrizePool() +
:695          yieldAccumulator;
...   :702-703  obligations += pNext + pFuture;   // pending pools (the prior-omission fix)
:705      if (totalBal <= obligations) return;
:707      uint256 yieldPool = totalBal - obligations;   // only the surplus is distributed
```

- **How "reserved" is computed:** `obligations` sums every live liability — `claimablePool` at `:693` is one
  term. Distributable yield = `totalBal − obligations`; anything inside `claimablePool` is never distributed.
- **Keeper total reserved?** **YES, automatically.** The keeper total is a sub-component of `claimablePool`, the
  same variable summed at `:693`. No separate `keeperFunding` term is required.
- **Structurally-immune callout ([[project_yield_surplus_omits_pending_pools]]):** This is the EXACT site of the
  historical omission bug — `distributeYieldSurplus` once summed `claimablePool` but FORGOT the pending pools
  (`prizePoolPendingPacked`), over-distributing freeze-window revenue. That class of bug is the omittable-pool
  pattern: a SEPARATE liability variable that a reservation site can forget to add. **Under D-CF-03 the keeper
  total is NOT a separate variable — it is the same `claimablePool` already at `:693` — so the omission class is
  STRUCTURALLY IMPOSSIBLE for keeper funding.** A future edit to this function literally cannot drop the keeper
  reservation without dropping `claimablePool` itself (which would corrupt all claimable winnings too — far too
  loud to slip through). This is the central payoff of the "no new aggregate" decision: the proof for the keeper
  total is the proof `claimablePool` is already reserved here, which it is. The pending-pool fix at `:702-703`
  remains as defense for the genuinely-separate pending buffer; it is unrelated to the keeper bucket.

### A.2 — `GameOverModule.handleGameOverDrain` pre-refund reserve (`:98`)

```solidity
// contracts/modules/DegenerusGameGameOverModule.sol
:86   function handleGameOverDrain(uint32 day) external {
:91       uint256 totalFunds = address(this).balance + steth.balanceOf(address(this));
:98       uint256 reserved = uint256(claimablePool);                       // ← keeper total inside
:99       uint256 preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0;
```

- **How "reserved" is computed:** `reserved = claimablePool`; distributable (deity-refund budget) =
  `totalFunds − reserved`. sDGNRS redemption ETH is already segregated OUT of the game at submit
  (`pullRedemptionReserve`), so it is not in `totalFunds` and is correctly NOT re-subtracted (`:95-97`).
- **Keeper total reserved?** **YES** — `reserved` is `claimablePool`, inclusive of the keeper total. The deity
  refund budget at `:116` (`budget = preRefundAvailable`) and the per-pass refunds (`:128`) draw only from the
  surplus above `claimablePool`; keeper ETH is never refunded away.

### A.3 — `GameOverModule.handleGameOverDrain` post-refund reserve (`:163`)

```solidity
// contracts/modules/DegenerusGameGameOverModule.sol
:140      if (totalRefunded != 0) claimablePool += uint128(totalRefunded);  // refunds grow the pool
...
:163      uint256 postRefundReserved = uint256(claimablePool);              // ← recomputed, keeper still inside
:164      uint256 available = totalFunds > postRefundReserved ? totalFunds - postRefundReserved : 0;
:166      if (available == 0) return;
```

- **How "reserved" is computed:** After deity refunds credit `claimableWinnings[owner]` and grow `claimablePool`
  (`:128`/`:140`), `reserved` is RE-READ as `claimablePool` (`:163`). The terminal-decimator and terminal-jackpot
  distributions (`:176`/`:190`) draw only from `available = totalFunds − postRefundReserved`.
- **Keeper total reserved?** **YES** — the recomputed `claimablePool` still carries the keeper total (refunds add
  to it, nothing subtracted the keeper sub-component). The terminal distributions cannot reach keeper ETH.

### A.4 — `DegenerusGame.adminStakeEthForStEth` reserve (def `:2109`; reserve calc `:2116-2122`)

```solidity
// contracts/DegenerusGame.sol
:2109 function adminStakeEthForStEth(uint256 amount) external {
:2113     uint256 ethBal = address(this).balance;
:2115     // Vault and DGNRS claimable can be settled in stETH, so exclude from ETH reserve
:2116     uint256 stethSettleable = claimableWinnings[ContractAddresses.VAULT] +
:2117         claimableWinnings[ContractAddresses.SDGNRS];
:2118     uint256 reserve = claimablePool > stethSettleable
:2119         ? claimablePool - stethSettleable
:2120         : 0;
:2121     if (ethBal <= reserve) revert E();
:2122     uint256 stakeable = ethBal - reserve;
```

- **How "reserved" is computed:** `reserve = claimablePool − stethSettleable`, where `stethSettleable` is ONLY the
  VAULT + SDGNRS claimable buckets (those two sinks accept stETH, so their share need not stay liquid ETH). The
  ETH actually stakeable = `ethBal − reserve`.
- **Keeper total reserved?** **YES, and correctly.** The keeper total is part of `claimablePool` but is **NOT**
  stETH-settleable — subscribers withdraw/claim plain ETH, never stETH. Because the subtracted `stethSettleable`
  is exactly and only the two named sink buckets (`:2116-2117`), the keeper sub-component stays inside `reserve`
  and is therefore never staked away into stETH. Keeper ETH remains liquid ETH, exactly as the withdraw path
  needs it. The narrow `stethSettleable` whitelist is what makes this correct: were it computed as "everything
  except players," it would wrongly drain the keeper bucket — but it is not; it is two pinned addresses.

### A.5 — `GameOverModule.handleFinalSweep` (def `:202`; `claimablePool = 0` at `:215`; GO_SWEPT latch `:205-207`)

```solidity
// contracts/modules/DegenerusGameGameOverModule.sol
:202  function handleFinalSweep() external {
:203      if (_goRead(GO_TIME_SHIFT, GO_TIME_MASK) == 0) return;            // game not over
:204      if (block.timestamp < _goRead(GO_TIME_SHIFT, GO_TIME_MASK) + 30 days) return;  // too early
:205      if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return;          // already swept
:207      _goWrite(GO_SWEPT_SHIFT, GO_SWEPT_MASK, 1);                       // latch GO_SWEPT
:209-214  // read+zero claimableWinnings[VAULT/SDGNRS/GNRUS]
:215      claimablePool = 0;                                               // ← zeroes the aggregate
...   :231  remainder = totalFunds - (owedV + owedSD + owedG);              // 30-day three-way split
```

- **How "reserved" is computed:** The 30-day-post-gameover sweep zeroes the reserved aggregate `claimablePool`
  (`:215`) and pays the three protocol sinks what they are owed, splitting the remainder ~1/3 each. All other
  unclaimed player balances are forfeited at this point (the documented terminal-forfeiture lifecycle).
- **Keeper total reserved?** **YES for the aggregate** — `claimablePool = 0` sweeps the keeper reservation along
  with everything else; no keeper ETH "escapes" a reservation site here. **The reservation invariant is intact.**
  The remaining concern is NOT a reservation escape but a per-player lifecycle gap: the sweep zeroes the
  AGGREGATE but cannot (unbounded) iterate per-player `keeperFunding[*]`. That gap is the single genuine planning
  risk and is locked in **Section B**.

### A — Verdict

| # | Site | File:line | `reserved` term | Keeper total reserved | Edit |
|---|------|-----------|-----------------|-----------------------|------|
| 1 | `distributeYieldSurplus` | JackpotModule `:688` / `:693` | `obligations ⊇ claimablePool` | YES (structurally immune) | none |
| 2 | drain pre-refund | GameOverModule `:98` | `reserved = claimablePool` | YES | none |
| 3 | drain post-refund | GameOverModule `:163` | `postRefundReserved = claimablePool` | YES | none |
| 4 | `adminStakeEthForStEth` | DegenerusGame `:2109` / `:2118` | `claimablePool − {VAULT,SDGNRS} claimable` | YES (keeper not stETH-settleable) | none |
| 5 | `handleFinalSweep` | GameOverModule `:202` / `:215` | `claimablePool = 0` | YES (aggregate) | none (but Section B locks the withdraw-side guard) |

**All 5 reservation sites reserve `claimablePool` inclusive of the keeper total with ZERO `contracts/*.sol`
edits.** No free-ETH-distribution site lets the keeper total escape. D-CF-03 holds against source: the keeper
bucket inherits the entire solvency wiring for free precisely because it is not a separate aggregate.

---

## Section B — The GO_SWEPT withdraw-guard lock (RESEARCH Pitfall 1 / Open Q1)

This is the **single genuine planning risk** the SPEC must close — and it is a CEI/lifecycle detail WITHIN the
locked mechanism, not a re-design.

### B.1 — The gap

`handleFinalSweep:215` sets `claimablePool = 0`, but it does **NOT** (and cannot — the mapping is unbounded)
iterate per-player `keeperFunding[*]`. So after the sweep latches `GO_SWEPT`, a player who never withdrew still
holds `keeperFunding[player] != 0` on disk while `claimablePool == 0`. The PLAN-V54 §3 `withdrawKeeperFunding`
sketch debits the pool unconditionally:

```
withdrawKeeperFunding(amount):
    keeperFunding[msg.sender] -= amount;
    claimablePool            -= uint128(amount);   // ← post-sweep: 0 - amount  ⇒  UNDERFLOW REVERT
    (send amount)
```

Post-sweep `claimablePool == 0`, so `claimablePool -= uint128(amount)` underflows (checked-math revert in 0.8.x,
or — far worse — silent corruption if ever wrapped in `unchecked`). This is a clean DoS-on-the-withdraw, not a
solvency escape (no extra ETH leaves), but it must be handled deliberately, not by accidental underflow.

### B.2 — The precedent guard (`_claimWinningsInternal:1463`) — quoted

The claim path ALREADY solves exactly this, and the keeper withdraw must mirror it verbatim:

```solidity
// contracts/DegenerusGame.sol
:1462 function _claimWinningsInternal(address player, bool stethFirst) private {
:1463     if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();   // ← post-sweep: revert, don't touch pool
:1464     uint256 amount = claimableWinnings[player];
...
:1471     claimablePool -= uint128(payout);                              // only reached pre-sweep
```

Because `_claimWinningsInternal` reverts the moment `GO_SWEPT` is set, the **Decision-B lazy keeper-merge inside
`claimWinnings` is naturally blocked post-sweep too** (the whole function reverts before it can touch
`keeperFunding`) — so the claim path needs no extra work; it is the withdraw path that lacks the guard.

### B.3 — The LOCK

> **LOCKED (T-343-04):** `withdrawKeeperFunding` MUST revert post-sweep via the SAME `GO_SWEPT` latch
> `_claimWinningsInternal` uses at `:1463`:
> ```solidity
> if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();   // FIRST line, before any debit
> ```
> placed as the first statement, before the `keeperFunding[msg.sender] -=` / `claimablePool -=` debits, so a
> post-sweep withdraw reverts cleanly instead of underflowing `claimablePool`.

- **Consistent with the lifecycle (GAMEOVER-02):** "both withdraw/claim paths stay open until that sweep." The
  30-day sweep IS the hard forfeiture cutoff — after it, BOTH the claim path (already, `:1463`) and the keeper
  withdraw path (this lock) revert. Symmetry restored; no path can touch a zeroed `claimablePool`.
- **Within the locked mechanism, not a re-design:** this is a one-line CEI/lifecycle guard that mirrors an
  existing precedent on the sibling path. It changes no economics and opens no new aggregate.
- **344 carry-forward:** the 344 IMPL edit-order map MUST place this `GO_SWEPT` guard as the first line of
  `withdrawKeeperFunding`. It is surfaced to the D-07 red-team (Section E) as an explicit charged probe — "does
  the locked revert fully close the underflow, or is there a residual hole?"

---

## Section C — SOLVENCY-03: the sDGNRS redemption valuation is unchanged + correct

**Claim:** the sDGNRS redemption valuation never sees keeper ETH, so it needs no edit — the same property the
external AfKing pool has TODAY.

### C.1 — The valuation (three identical sites)

```solidity
// contracts/StakedDegenerusStonk.sol  — :609-612, :769-772, :858-861 (byte-identical formula)
:609  uint256 ethBal = address(this).balance;                       // sDGNRS's OWN ETH
:610  uint256 stethBal = steth.balanceOf(address(this));            // sDGNRS's OWN stETH
:611  uint256 claimableEth = _claimableWinnings();                  // only what the GAME owes sDGNRS
:612  uint256 totalMoney = ethBal + stethBal + claimableEth - pendingRedemptionEthValue;
```

### C.2 — `_claimableWinnings` reads ONLY `claimableWinningsOf(sDGNRS)` — quoted

```solidity
// contracts/StakedDegenerusStonk.sol
:955  function _claimableWinnings() private view returns (uint256 claimable) {
:956      uint256 stored = game.claimableWinningsOf(address(this));   // ← Game's debt to sDGNRS ONLY
:957      if (stored <= 1) return 0;
:958      return stored - 1;
```

### C.3 — Why keeper ETH is invisible

- `ethBal` (`:609`) is `address(this).balance` of **the sDGNRS contract** — keeper ETH lives in **the Game's**
  balance, a different contract. Not counted.
- `claimableEth` (`:611` → `:956`) is `game.claimableWinningsOf(address(this))` — strictly **what the Game owes
  sDGNRS**. Keeper ETH is owed to SUBSCRIBERS (tracked in `keeperFunding[*]`), never to sDGNRS, so it is **not**
  in `claimableWinningsOf(sDGNRS)`. Not counted.
- There is **no term** in the valuation that reads the Game's total balance, `claimablePool`, or any keeper
  variable. Keeper ETH is therefore wholly invisible to the redemption price.

**Same property as today:** in v53 the AfKing pool ETH sits in the external AfKing contract — equally invisible to
this sDGNRS valuation. v54 relocates that ETH into the Game's balance + `keeperFunding[*]`, but it remains owed to
subscribers and outside `claimableWinningsOf(sDGNRS)`, so the valuation reads identically. **No redemption-valuation
edit is needed; the formula is UNCHANGED and CORRECT.** (Folding keeper ETH into the redemption price would be the
bug — it would let redeemers cash out other subscribers' deposits; the structure correctly prevents that.)

---

## Section D — OPEN-E 4-protection carry-over (verbatim) + the D-01 funder-keyed identity

The USER-LOCKED OPEN-E disposition (`open-e-operator-approval-trust-boundary`: operator-approval IS the trust
boundary; default-self byte-identical; no-escalation; trust-the-sub temporal bound) carries over **verbatim** —
all of its source anchors are UNCHANGED:

| Protection | Source (UNCHANGED) | Confirmation |
|------------|--------------------|--------------|
| Consent gate at subscribe | `AfKing.sol:403-407` (`if` at `:403`; revert `NotApproved()` at `:408`) | A non-zero, non-self `fundingSource` must have `GAME.isOperatorApproved(fundingSource, subscriber)` — else revert. Checked HERE only (renewal/per-draw never re-check) — the temporal "trust the sub" bound. |
| Default-self short-circuit | `AfKing.sol:404` (`fundingSource != address(0)`) | `address(0)` (self) short-circuits the read — default-self path byte-identical. |
| `src` resolution | `AfKing.sol:686` | `address src = sub.fundingSource == address(0) ? player : sub.fundingSource;` — UNCHANGED. |
| VAULT/SDGNRS exemption on un-spoofable `player` | `AfKing.sol:696` | `if (player == ContractAddresses.VAULT || player == ContractAddresses.SDGNRS)` — keyed on `player`, NOT `funder`; UNCHANGED. |

- **What changes (and why the disposition still holds):** funding-source ETH is no longer `_poolOf[src]` in
  AfKing; it is now `keeperFunding[src]` in the Game, **withdrawable by the source** — preserving "funding-source
  ETH withdrawable by the source" (DECUSTODY-03). The four protections are all subscribe-time / resolution-time
  logic that is untouched by relocating the ETH.

- **The D-01 interaction (the reservation identity tracks the FUNDER, not the beneficiary):** v54's non-payable
  `batchPurchase` debits **`keeperFunding[b.funder]`** (= the resolved `src`), NOT `keeperFunding[b.player]`
  (the beneficiary / `purchaseWith` target). AfKing sets `funder: src` per slice. This is CRITICAL for the
  OPEN-E operator-funded case: when `fundingSource != subscriber`, `src ≠ player`, so the funding identity is the
  OPERATOR (`src`). v53 handles this entirely AfKing-side — the CEI debit at `AfKing.sol:719`
  (`_poolOf[src] -= ethValue`) keys on `src`. The naive PLAN-V54 §4 / REQUIREMENTS AUTOBUY-02 snippet
  (`keeperFunding[b.player] -= ev`) would debit the SUBSCRIBER's (empty) bucket while the funding-skip check
  guards the OPERATOR's bucket → revert / mis-account, breaking the OPEN-E disposition. **D-01 corrects this:**
  the Game debit keys on `keeperFunding[funder=src]`, so the reservation identity tracks the source — the
  operator-funded slice stays correctly accounted and the operator (source) retains withdraw rights. The
  VAULT/SDGNRS exemption stays on the un-spoofable `player` (`:696`); only the debit moves to `funder`. **This is
  a recorded correction to REQUIREMENTS AUTOBUY-02 and PLAN-V54 §4, both of which say `b.player`.**

  *(Note on the snapshot read — D-MR-01: the extended `keeperSnapshot` returns `keeperFunding[player]`, which
  equals `keeperFunding[src]` only when `src == player` [normal subs + VAULT + SDGNRS]. The OPEN-E `src ≠ player`
  slice needs `keeperFunding[src]`, supplied by one extra `keeperFundingOf(src)` fallback staticcall mirroring
  the existing per-player fallback at `AfKing.sol:809`. This is BATCH-01/AUTOBUY-05 plumbing, noted here only so
  the D-01 funder identity is consistent end-to-end; the reservation/solvency proof is unaffected.)*

**OPEN-E 4-protection disposition CONFIRMED to carry over verbatim;** the only delta (funding-source ETH now
`keeperFunding[src]`, debit keyed on `funder=src`) preserves it.

---

## Section E — Charged probes for the D-07 red-team (Task 2)

The following attack surfaces are handed to the D-07 focused adversarial red-team (`/economic-analyst` AND
`/contract-auditor`, **scoped to this solvency proof — NOT a full re-audit**). Each must be dispositioned
(NEGATIVE-VERIFIED / SAFE_BY_DESIGN / FINDING_CANDIDATE) with source-cited reasoning in `343-SOLVENCY-REDTEAM.md`.

1. **Reservation escape — site 1 `distributeYieldSurplus`** (JackpotModule `:693`): can the keeper total be
   distributed as yield surplus? Probe the structural-immunity claim — is there any path where `claimablePool`
   under-counts the keeper total (e.g., a deposit that credits `keeperFunding` but not `claimablePool`, breaking
   D-CF-03)? The omittable-pool class should be impossible since it is the same variable.

2. **Reservation escape — site 2 drain pre-refund** (GameOverModule `:98`): can deity refunds spend keeper ETH?
   Probe `preRefundAvailable = totalFunds − claimablePool`.

3. **Reservation escape — site 3 drain post-refund** (GameOverModule `:163`): can terminal-decimator /
   terminal-jackpot reach keeper ETH after refunds grow the pool? Probe the recomputed `postRefundReserved`.

4. **Reservation escape — site 4 `adminStakeEthForStEth`** (DegenerusGame `:2118`): can keeper ETH be staked into
   stETH (making it illiquid for withdraw)? Probe that `stethSettleable` is strictly the two pinned sink buckets
   and never includes keeper funding.

5. **Reservation escape — site 5 `handleFinalSweep`** (GameOverModule `:215`): does `claimablePool = 0` correctly
   sweep the keeper reservation with the aggregate? (Distinct from probe 6.)

6. **The GO_SWEPT withdraw-guard** (Section B; precedent `_claimWinningsInternal:1463`): does the LOCKED
   revert-post-sweep on `withdrawKeeperFunding` fully close the `claimablePool -= amount` underflow, or is there a
   residual hole (e.g., a path that debits before the guard, or a non-swept-but-gameover window)? The Pitfall-1
   gap MUST be surfaced explicitly to the red-team.

7. **Deposit-then-spend / fresh-rate-labeling economics** (`payAffiliate` at `DegenerusAffiliate.sol:388`,
   fresh-rate logic `:493-505`, fresh tiers 25%/20% at `:499-500`, recycled 5% at `:503`): can an actor mislabel
   keeper ETH (spent as `ethValue` / DirectEth / fresh) to drain the fresh affiliate rate, or otherwise game the
   fresh-vs-recycled labeling? Keeper funding is a SEPARATE bucket precisely to keep this honest — probe whether
   the separation can be defeated. *(Cite `payAffiliate`, NOT the non-applicable `handleAffiliate` quest fn — per
   343-GREP-ATTESTATION Correction 2.)*

8. **The un-brickable withdraw CEI** (template `AfKing.withdraw:328`, debit-before-send at `:334`): does
   `withdrawKeeperFunding`, mirroring the debit-before-send CEI while also moving `claimablePool` in tandem,
   resist re-entrant double-withdraw (the second re-entrant call reverts on the already-debited bucket)? Probe the
   "cancel-then-withdraw always succeeds / never strands ETH" invariant under the new dual-debit.

9. **The D-01 funder/beneficiary split** (debit on `keeperFunding[funder=src]`, AfKing `src` at `:686`, CEI debit
   precedent `:719`): probe the OPEN-E operator-funded mis-account — if the Game debit EVER keyed on `player`
   instead of `funder`, the operator-funded slice (`src ≠ player`) breaks (subscriber's empty bucket debited,
   operator's bucket skip-checked). Confirm the funder-keyed debit preserves the OPEN-E disposition and the
   VAULT/SDGNRS exemption stays on `player` (`:696`).

10. **The no-new-aggregate invariant** (D-CF-03: `claimablePool == Σ claimableWinnings + Σ keeperFunding`): probe
    any path that could break the invariant — a deposit/withdraw/merge that moves one side without the other, or a
    double-credit (e.g., the Decision-B lazy merge in `claimWinnings` double-spending against
    `withdrawKeeperFunding`). Both must zero the bucket; confirm no double-spend window.

---

## Verdict (SOLVENCY-01 / SOLVENCY-03 paper-proof)

- **SOLVENCY-01:** all 5 free-ETH reservation sites reserve `claimablePool` inclusive of the keeper total with
  ZERO contract edits (D-CF-03 holds against source); the prior-omission site (`distributeYieldSurplus`) is
  structurally immune; no reservation site lets the keeper total escape.
- **SOLVENCY-03:** the sDGNRS redemption valuation reads sDGNRS's own balance + only `claimableWinningsOf(sDGNRS)`;
  keeper ETH in the Game's balance is invisible — UNCHANGED and CORRECT, same property as today's external pool.
- **Single genuine planning risk (Pitfall 1 / Open Q1):** the GO_SWEPT withdraw-guard, LOCKED in Section B —
  `withdrawKeeperFunding` reverts post-sweep via the same `GO_SWEPT` latch `_claimWinningsInternal:1463` uses;
  carried into the 344 edit-order map; surfaced to the D-07 red-team.
- **OPEN-E:** the 4-protection disposition carries over verbatim; funding-source ETH = `keeperFunding[src]`,
  withdrawable by the source; the D-01 funder-keyed debit preserves the operator-funded case.

**Paper-only assertion:** `git diff --name-only -- contracts/` is EMPTY — zero `contracts/*.sol` edits in this
plan. The proof is now ready for the D-07 adversarial red-team (Task 2, orchestrator-run).
