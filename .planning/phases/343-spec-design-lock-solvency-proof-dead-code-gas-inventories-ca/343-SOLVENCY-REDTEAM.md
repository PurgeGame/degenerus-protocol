# 343-SOLVENCY-REDTEAM — D-07 Focused Adversarial Red-Team on the Solvency Proof

**Phase:** 343 SPEC (v54.0 — Game-Side Keeper-Funding Ledger + AfKing De-Custody)
**Subject:** [`343-SOLVENCY-PROOF.md`](./343-SOLVENCY-PROOF.md) — attacked against `contracts/` byte-identical to v53 HEAD `83a84431`
**Scope (D-07):** FOCUSED red-team **scoped to the solvency proof**, NOT a full re-audit. Two diverse adversarial lenses, each told to REFUTE the proof's safety claims against source.
**Method:** orchestrator-level fan-out (no agent-nesting) → `/contract-auditor` persona (security/solvency lens) + `/economic-analyst` persona (economics/game-theory lens), each scoped to the proof's Section-E charged probes.
**Note on `keeperFunding`:** the v54 ledger (`keeperFunding` / `depositKeeperFunding` / `withdrawKeeperFunding`) is **confirmed ABSENT** from the v53 tree; both lenses therefore attacked the *future* code **as specified** in PLAN-V54 §3–§4 + the proof's D-01 correction, against the real surrounding source.

---

## Verdict

**The solvency proof SURVIVES both lenses. ZERO `FINDING_CANDIDATE`. The SOLVENCY-01/03 spine is sound on paper.**

| Lens | Probes | NEGATIVE-VERIFIED | SAFE_BY_DESIGN | FINDING_CANDIDATE |
|------|--------|-------------------|----------------|-------------------|
| `/contract-auditor` (security/solvency) | 8 | 6 | 2 | **0** |
| `/economic-analyst` (economics/game-theory) | 4 | 2 | 2 | **0** |

**USER adjudication:** the operator selected **fully-autonomous execution (auto-approve the D-07 gate)** for Phase 343. The red-team surfaced **no unresolved solvency hole** (the high-severity block-on item), so the verdict is **AUTO-APPROVED** — the proof + the locked `GO_SWEPT` withdraw-guard carry into 344 IMPL. Two IMPL-discipline carry-forwards (below) are recorded for the 344 edit-order map; both are already flagged by the proof.

---

## Security lens — `/contract-auditor` per-probe disposition

Attacker model: 1000 ETH budget, trying to make the keeper total escape a reservation site, underflow/double-spend the accounting, or mis-account the OPEN-E operator case. Every cited line independently re-grepped against source (zero drift found in the lines the proof cites).

| # | Charged probe | Disposition | Deciding source |
|---|---------------|-------------|-----------------|
| 1 | Reservation escape — `distributeYieldSurplus` + D-CF-03 invariant | **NEGATIVE-VERIFIED** | `JackpotModule:693` — keeper total is a *sub-component* of `claimablePool`, not a separate omittable pool; deposit/spend move both sides in tandem (`_addClaimableEth`→`claimablePool +=` template `:737`/`:715`). The omittable-pool class that historically bit `prizePoolPendingPacked` is **structurally impossible**. |
| 2 | Reservation escape — gameOver drain pre-refund | **NEGATIVE-VERIFIED** | `GameOverModule:98-99` — `reserved = uint256(claimablePool)`; refunds draw only from surplus above it; refund loop `:118-142` never reads the keeper bucket. |
| 3 | Reservation escape — gameOver drain post-refund | **NEGATIVE-VERIFIED** | `GameOverModule:163` — `postRefundReserved` **re-read** from `claimablePool` after refunds grew it (`:140`); terminal decimator/jackpot draw only from `totalFunds − postRefundReserved`. |
| 4 | Reservation escape — `adminStakeEthForStEth` | **SAFE_BY_DESIGN** | `DegenerusGame:2116-2118` — `stethSettleable = claimableWinnings[VAULT] + claimableWinnings[SDGNRS]` is a **literal two-address whitelist**, not a heuristic. Keeper ETH is in neither named bucket → stays in the ETH `reserve`, never staked-away. Subscribers withdraw plain liquid ETH. |
| 5 | Reservation escape — `handleFinalSweep` aggregate zeroing | **NEGATIVE-VERIFIED** | `GameOverModule:215` — `claimablePool = 0` sweeps the *whole* reserved aggregate (keeper reservation included) to protocol sinks; no keeper ETH escapes a reservation site. (The per-player lifecycle gap this creates is Probe 6.) |
| 6 | **GO_SWEPT withdraw-guard (Pitfall-1, surfaced explicitly)** | **NEGATIVE-VERIFIED** (conditional on the lock shipping verbatim) | Gap confirmed real: `handleFinalSweep:215` zeroes the aggregate but cannot iterate unbounded `keeperFunding[*]`. Naive `withdrawKeeperFunding` (`claimablePool -= amount`) would **checked-revert** post-sweep (clean DoS, no ETH escapes) — or silently corrupt **iff** ever wrapped in `unchecked`. The proof's lock mirrors the **present** precedent `_claimWinningsInternal:1463` (`if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();` as the FIRST statement). With the guard first, post-sweep withdraw reverts cleanly AND the Decision-B claim-merge is naturally blocked too. No pre-sweep window underflows (reservation intact while `claimablePool != 0`). |
| 8 | Un-brickable withdraw CEI / re-entrant double-withdraw | **NEGATIVE-VERIFIED** | Template `AfKing.withdraw:328-341` debits **before** `.call{value:}`; re-entrant call re-reads the debited balance and reverts (`:331`). Spec'd `withdrawKeeperFunding` mirrors this AND debits `claimablePool -= amount` before the call. Cancel (`setDailyQuantity(0)`) never touches `keeperFunding`, so "cancel-then-withdraw always succeeds." |
| 9 | D-01 funder/beneficiary split (`keeperFunding[funder=src]`) | **NEGATIVE-VERIFIED** (proof catches the latent trap) | `AfKing.sol:686` resolves `src`; v53 funding-skip `:695` + CEI debit `:719` are **funder-keyed**; exemption on un-spoofable `player` `:696`. PLAN-V54 §4 / AUTOBUY-02's `keeperFunding[b.player] -= ev` is a **live trap** (OPEN-E `src≠player` would debit the empty subscriber bucket). The proof's D-01 correction (`BatchBuy.funder=src`, debit `[b.funder]`, exemption on `player`) overrides it. Consent gated once at subscribe (`:403-408`). |
| 10 | No-new-aggregate + Decision-B lazy-merge double-spend | **NEGATIVE-VERIFIED** | D-CF-03 holds (tandem credit/debit). Claim vs withdraw: both zero the same per-player bucket → second reads zero, pays nothing. **Spend hand-off proven double-count-free:** `batchPurchase` debits `claimablePool -= ev`, then `recordMint{value: ev}` (`MintModule:1570`) routes `DirectEth` which does **NOT** touch `claimablePool` (`DegenerusGame:1008-1009`); the `ev` becomes a `nextPrizePool`/`futurePrizePool` liability that `distributeYieldSurplus` independently reserves (`JackpotModule:692/694`). Exact hand-off `claimablePool −ev → prizePool +ev`, never double-reserved, never released to "free." |

**Informational (outside the charged probes, NOT a finding):** a 4th tandem-debit site exists — `pullRedemptionReserve` (`DegenerusGame.sol:1981`) debits `claimableWinnings[SDGNRS]` + `claimablePool` in tandem when segregating sDGNRS redemption ETH. It never reads `keeperFunding` (different bucket), preserves the invariant, and is irrelevant to the keeper reservation. 344 should be aware it is another tandem-debit site the keeper bucket must never collide with (it can't).

---

## Economic lens — `/economic-analyst` per-probe disposition

Rational-actor / EV model: can anyone profit at the system's expense from the keeper bucket, the fresh-rate labeling, the OPEN-E channel, or the gameOver boundary?

| Probe | Disposition | Deciding source |
|-------|-------------|-----------------|
| **7 (primary) — deposit-then-spend / fresh-rate-labeling** | **NEGATIVE-VERIFIED** | The fresh-rate FLIP reward **never reaches the funder**: keeper path passes `affiliateCode = bytes32("DGNRS")` (`DegenerusGame:1842`); `:606 if (winner != sender)` suppresses buyer payout; DGNRS kickback `=0` (`:442`); `payAffiliate` GAME-gated (`:400-403`). No wash loop — a keeper buy **irreversibly** spends `ethValue` (`MintModule:1191-1206`); withdraw returns only UNSPENT funds. The "fresh" label is **correct** (keeper ETH is deposited external capital, never won) — same rate a normal fresh-`msg.value` buy earns today. Keeping `keeperFunding` a SEPARATE bucket is the **attack-mitigating** choice; merging into `claimableWinnings` is what would open deposit-then-spend farming (PLAN §10). |
| OPEN-E operator-funded incentive (D-01 / Section D) | **SAFE_BY_DESIGN** | Consent gated at subscribe (`isOperatorApproved`, `AfKing:403-408`); buy debits `keeperFunding[funder=src]` (operator), proceeds buy tickets *for the subscriber* — exactly the funded service; subscriber cannot redirect the operator's ETH to their own bucket (only sink is the buy; FLIP goes to protocol/affiliate, not subscriber). "Operator withdraws mid-batch" is benign — separate txs; mid-batch the funding-skip gate (`keeperFunding[src] < ethValue`) just skips that subscriber (`AfKing:376-380`), the intended "defund to halt" behavior. No griefing profit (operator reclaims their own ETH; denying a -EV buy isn't value-extractive). |
| Decision-B merge + withdraw (double-claim / gameOver timing) | **NEGATIVE-VERIFIED** | Both paths zero the bucket + debit `claimablePool` in tandem, CEI (PLAN §3 `:119-120`). No read-stale-then-debit-twice. Economics identical pre/post-gameOver — `keeperFunding` is the depositor's own 1:1 ETH; merge is a UX convenience, no rate/bonus/yield straddles the boundary. |
| GO_SWEPT withdraw-guard economics (bank-run dynamics) | **SAFE_BY_DESIGN** | Withdraw + claim BOTH open until sweep = **gameOver + 30 days** (`GameOverModule:204`) — the same symmetric forfeiture cutoff `_claimWinningsInternal:1463` already enforces on winnings (GAMEOVER-02). No first-mover advantage (per-player segregated balance, un-brickable 1:1 withdraw, no shrinking shared pool) → **no bank run**. The underflow (probe 6) is a DoS-on-self, not an economic exploit; the `GO_SWEPT` revert removes the foot-gun and changes no incentive. |

**Out-of-scope (noted, NOT a v54 regression):** registering one's own contract as a custom affiliate code to route keeper-buy FLIP to a controlled wallet is the **pre-existing, universal** affiliate self-referral-via-proxy economics that applies to *every* purchase path; `keeperFunding` changes nothing about it (keeper ETH earns the same fresh rate a normal fresh buy earns today, the "reward" is a 50/50 minted BURNIE flip stake, and the buyer still paid full -EV ticket price). Not a solvency-proof finding.

---

## IMPL-discipline carry-forwards to 344 (recorded; both already flagged by the proof)

These are NOT findings against the design — they are precise instructions the 344 IMPL diff must honor, surfaced by the red-team for the edit-order map:

1. **`withdrawKeeperFunding` GO_SWEPT guard MUST be line 1** — placed BEFORE the `claimablePool -= amount` debit (mirror `_claimWinningsInternal:1463`), and the debit MUST stay **checked-math** (no `unchecked`). Per Proof Section B.3 / `T-343-04`.
2. **`batchPurchase` MUST debit `keeperFunding[b.funder]`, not `keeperFunding[b.player]`** — add the `funder` field to BOTH `BatchBuy` structs (AfKing + Game); keep the VAULT/SDGNRS exemption on `player`. The PLAN-V54 §4 / AUTOBUY-02 `b.player` snippets are a live trap if copied verbatim. Per Proof Section D / D-01.
3. **(awareness)** `pullRedemptionReserve` (`DegenerusGame:1981`) is a 4th `claimablePool`-tandem-debit site — keep the keeper bucket disjoint from it (it already is).

---

## Disposition summary

- **Reservation escape (5 sites):** NEGATIVE-VERIFIED ×4 + SAFE_BY_DESIGN ×1 — the keeper total cannot escape any free-ETH reservation site.
- **GO_SWEPT withdraw-guard:** NEGATIVE-VERIFIED (security) + SAFE_BY_DESIGN (economic) — the locked revert-post-sweep fully closes the underflow; carry the line-1 + checked-math discipline to 344.
- **D-01 funder/beneficiary split:** NEGATIVE-VERIFIED — the proof's correction preserves the OPEN-E operator-funded case; carry `funder` to 344.
- **Economics (fresh-rate, OPEN-E, Decision-B, bank-run):** all NEGATIVE-VERIFIED / SAFE_BY_DESIGN — the separate bucket is the attack-mitigating choice.

**No design amendment required before 344 IMPL.** The proof is design-gating-complete.
