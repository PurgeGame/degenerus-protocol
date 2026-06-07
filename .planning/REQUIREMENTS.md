# Requirements — v61.0 AfKing-as-Payment-Source + Cashout-Curse + Deity-Smite

> **Baseline:** the v60.0 closure HEAD `2bee6d6f` (10 commits ahead of origin/main, NOT pushed). Anchors are cited at the plan-doc HEAD (grep-verified 2026-06-06); re-attested at SPEC (375) against `2bee6d6f` before any edit.
> **Design-lock inputs:** `.planning/PLAN-V61-MILESTONE-SCOPE.md` + `.planning/PLAN-V61-AFKING-AS-PAYMENT-SOURCE.md` + `.planning/PLAN-CASHOUT-CURSE.md` + `.planning/PLAN-V61-DEITY-SMITE.md` (`[[v61-milestone-seed]]`).
> **Scope (USER-locked 2026-06-06):** ONE milestone, ONE batched contract diff — (1) the afking-as-payment waterfall `msg.value → claimable → afking` across every non-mintBurnie spend path + the feature-first `claimableWinnings`/`afkingFunding` slot-packing; (2) the cashout-curse counter + cure + permissionless `decurse`; (3) deity-smite on the same curse counter. All 3 work items + the packing sub-concept are IN scope; packing is sequenced **feature-first** (exact feature-first vs accessor-first locked at SPEC).
> **Posture:** Hard floor on EVERY change = RNG-freeze intact + SOLVENCY-01 re-attested. All three items read no `rngWord` (ledger / activity-score / PvP — no RNG). The afking-payment waterfall + the slot-packing keep `claimablePool == Σ(claimableWinnings + afkingFunding)` (afking already rides inside `claimablePool`; each afking debit pairs `claimablePool -=`, pool-neutral, contract balance unchanged). The curse/smite only ever LOWER an activity-score-derived multiplier (payouts down, never up). Pre-launch redeploy-fresh (storage-layout break fine; the PACK repack needs no migration). **ONE contract-boundary HARD STOP at IMPL (376)** — only contract commits need approval; docs/tests run hands-off. **FULL in-milestone close at TERMINAL (379)** — the 3-skill genuine-PARALLEL adversarial sweep + delta-audit + `audit/FINDINGS-v61.0.md`, NOT deferred (#1 reworks the claimable/afking solvency accounting; #2/#3 ride the activity-score path).
> **Expected shape:** SPEC → IMPL → GAS → TST → TERMINAL (phases 375-379). **GAS (377) owns no REQ-ID** — the gas-neutrality gate: CURSE-02 APPLY stays zero-new-SLOAD on the hot activity-score read; PACK adds no cold slot (a winner prepaying afking saves a ~20k cold SSTORE); AFPAY/SMITE add no `advanceGame`-ceiling regression. No research (fully design-locked).

---

## v61.0 Requirements

### AFPAY — AfKing-as-payment waterfall (#1)
> `afkingFunding` becomes a fresh-ETH-equivalent fallback tier (`msg.value → claimable → afking`) across every non-mintBurnie claimable-spend path. The afking-drawn portion is treated identically to `msg.value` (the player's own deposited principal — economically identical to fresh ETH; this just saves a `withdraw → re-pay` round-trip). NO rebuy bonus on the afking portion (the 10% flip-credit bonus recirculates *winnings*; it reads `claimableWinnings` deltas → afking excluded for free). Implicit (no opt-in flag). Builds on `PLAN-UNIVERSAL-CLAIMABLE-PAY.md` (whale/presale already pull claimable; this adds the THIRD tier).

- [ ] **AFPAY-01** (IMPL): Generalize the shared helper → `_settleShortfall(buyer, shortfall, allowClaimable) → (claimableUsed, afkingUsed)` (`DegenerusGameStorage.sol:851`): draw claimable to the 1-wei sentinel (only if `allowClaimable`), then the remainder from `afkingFunding[buyer]` (no sentinel, drains to 0), revert if both short; pair every debit with `claimablePool -=`; drop the stale `basis` param (callers pass the live balance). Covers lootbox + presale + the 3 whale sites at once.
- [ ] **AFPAY-02** (IMPL): `_processMintPayment` (`DegenerusGame.sol:1054`) adds the afking tier to all three pay-kinds — `DirectEth` (`msg.value` → afking, **skip** claimable); `Claimable` (claimable→sentinel → afking); `Combined` (`msg.value` → claimable→sentinel → afking); `prizeContribution = msg.value + claimableUsed + afkingUsed`.
- [ ] **AFPAY-03** (IMPL): Lootbox shortfall (`MintModule:1126-1146`) calls `_settleShortfall(buyer, shortfall, payKind != DirectEth)` — lifts the DirectEth→revert at `:1135` so DirectEth lootboxes use afking; `lootboxFreshEth += afkingUsed` (fresh, score-bearing affiliate at `:1311`), `lootboxClaimableUsed = claimableUsed` (recycled at `:1321`).
- [ ] **AFPAY-04** (IMPL): Presale box (`MintModule:1489`) + whale bundle / lazy pass / deity pass (`WhaleModule:263/490/596`) shortfalls draw the afking tier via the shared `_settleShortfall`.
- [ ] **AFPAY-05** (IMPL): Degenerette ETH bet `_collectBetFunds` (`DegeneretteModule:579-588`) covers the remainder from afking after the claimable-to-sentinel draw; keeps the `InvalidBet()` revert if still short.
- [ ] **AFPAY-06** (IMPL): The afking-drawn portion is treated identically to `msg.value` — fresh-rate affiliate **including the lootbox activity score** (`payAffiliate isFreshEth=true` + score) + presale box credit accrues; **NO rebuy bonus** on the afking portion (the bonus block reads `claimableWinnings` deltas only → afking excluded automatically); the ticket affiliate fresh/recycled split (`MintModule:1620-1692`) sets `freshEth = costWei − claimableUsedTicket` so afking lands in fresh, byte-identical for the existing no-afking DirectEth/Claimable/Combined cases (re-verified at SPEC).
- [ ] **AFPAY-07** (IMPL): `AfkingSpent(address indexed player, uint256 amount)` declared in `DegenerusGameStorage.sol` (visible to game + all modules) and emitted at each afking debit (emission breadth — shared helper vs `_processMintPayment` only — design-locked at SPEC, matching how claimable spends are silent outside `_processMintPayment`).

### PACK — claimable/afking slot-packing (#1 sub-concept, feature-first)
> Fold `claimableWinnings` + `afkingFunding` into one `uint256` (`[afking:high128 | claimable:low128]`) via an accessor layer, after the AFPAY waterfall lands. Width-safe (per-player ETH ≤ supply ~1.2e26 ≪ `2^128` ~3.4e38 — the same justification as `claimablePool` being `uint128`, `DegenerusGameStorage.sol:838-839`). A cross-half carry (bit 127→128) is physically impossible at these magnitudes.

- [ ] **PACK-01** (IMPL): Accessor layer — `_claimableOf/_afkingOf` reads + `_creditClaimable/_debitClaimable/_creditAfking/_debitAfking` (each paired with the `claimablePool` update), routing all `claimableWinnings`/`afkingFunding` refs (4 claimable credits + ~8 debits + ~80 reads; 31 afking refs) through it so the `claimablePool == Σ(claimable+afking)` invariant lives in ONE place. Precedent: `PLAN-PLAYERQUESTSTATE-1SLOT-PACKING.md`.
- [ ] **PACK-02** (IMPL): Pack the two balances into one `uint256` mapping `[afking:high128 | claimable:low128]`; do the math in `uint128` halves and recombine via `(uint256(afking) << 128) | claimable` (NO naive full-word `packed += x` — 0.8's 256-bit check would miss a 127→128 carry; no explicit overflow `require` needed since each half stays a clean `uint128`); preserve the gameOver VAULT/SDGNRS/GNRUS afking half during claimable-zeroing (via the accessor); `src != player` (operator-funded auto-buy) cases stay two addresses (no regression). Folded **feature-first** after AFPAY (exact feature-first vs accessor-first sequencing locked at SPEC-01).

### CURSE — cashout-curse (#2)
> A `uint8` curse counter that grows **+2 points (200 bps) per ghost-cashout** (cashing out ETH winnings while ≥5 days inactive), subtracted from every consumer of the player's activity score (floored 0). Stacks across repeat cash-out-and-ghost; cleared to 0 by any purchase ≥1 ticket worth (funding-agnostic) OR the permissionless paid `decurse`. Active afker is exempt. Deliberately mild — a progressive nudge against cash-out-and-ghost.

- [ ] **CURSE-01** (IMPL): `BitPackingLib` — add `CURSE_COUNT_SHIFT = 215` (uint8, in the documented `[215-222]` free gap; `AFFILIATE_BONUS_POINTS` ends at 214, `LEVEL_UNITS_SHIFT = 228`) + `MASK_8 = 0xFF`; update the layout doc comment; grep-verify no full-slot `mintPacked_` writer clobbers bits 215-222.
- [ ] **CURSE-02** (IMPL): APPLY in `MintStreakUtils._playerActivityScore` (just before `scoreBps = bonusBps` at `:320`, `packed` already loaded at `:248` → **zero new SLOAD**): `penaltyBps = curse * 100; bonusBps = bonusBps > penaltyBps ? bonusBps - penaltyBps : 0;` — propagates to every consumer + the public `playerActivityScore` view + all frozen snapshots.
- [ ] **CURSE-03** (IMPL): SET — new `_maybeCurse(player)` called from the **public `claimWinnings`** after a successful `_claimWinningsInternal` (never via the vault-only `claimWinningsStethFirst`). Cheapest-first bails: infra (VAULT/SDGNRS/GNRUS, constant compares) → gameOver → non-stale (`lastEthDay + 5 > _currentMintDay()`) → deity-pass → whale/lazy pass (`frozenUntilLevel >= level`) → active afker (`_subOf[player].dailyQuantity != 0`) → already at cap; else `curse += 2` (saturating via the cap) and SSTORE only on a stale cashout below the cap.
- [ ] **CURSE-04** (IMPL): CURE — reset `curseCount = 0` when `totalCost >= priceWei` (≥1 ticket worth, funding-agnostic) in `MintModule._purchaseWithFor` (before the score calc at `:1285` so the curing buy gets the un-penalized score), folded into the existing `mintPacked_` RMW with NO write-after-write clobber against the leg stamps (`recordMintData` / `_recordLootboxMintDay`).
- [ ] **CURSE-05** (IMPL): Wire the plain standalone lootbox leg (`MintModule._purchaseWithFor:1170-1254`) through `_recordLootboxMintDay` (relocated from `WhaleModule` private → the shared `MintStreakUtils` base) so manual lootbox buyers stamp `DAY_SHIFT` and gain bounty eligibility; closes the plain-vs-pass-bundled inconsistency.
- [ ] **CURSE-06** (IMPL): `decurse(address target)` — permissionless (no `_resolvePlayer`; clearing another's curse is purely beneficial); revert if the target's curse is already 0 (no wasted burn); `coin.burnCoin(msg.sender, PRICE_COIN_UNIT / 10)` (100 BURNIE from the caller); clear `curseCount = 0`; `emit Decursed(msg.sender, target)`. No `DAY_SHIFT` stamp.
- [ ] **CURSE-07** (IMPL): `curseCountOf(address)` view (or fold the counter into an existing player-state view) so the UI reads the value directly. (Counter cap `CURSE_COUNT_CAP` — rec 20 pts = 10 ghost-cashouts; doubles as the uint8 saturation guard — design-locked at SPEC.)

### SMITE — deity-smite (#3)
> A deity spends BURNIE to **smite** a target, adding a curse stack to the SAME `uint8` counter (the thematic inverse of a deity *blessing*). Reuses the curse APPLY + cure + cap for free. A paid PvP nuisance + BURNIE sink, deliberately mild (cured by one ticket or `decurse`). Depends on the CURSE infra → lands with/after #2.

- [ ] **SMITE-01** (IMPL): `smite(uint256 deityId, address smitee)` — gate `IDegenerusDeityPass(DEITY).ownerOf(deityId) == msg.sender` (single-tier soulbound pass, `tokenId = symbolId` 0-31); validate `smitee` BEFORE the burn (revert on **active afking sub** `_subOf[smitee].dailyQuantity != 0` = the SOLE immunity; revert if the target's `curseCount >= 5 stacks` = the smite ceiling; protocol-addr skip per SPEC); `burnCoin(msg.sender, PRICE_COIN_UNIT / 5)` (200 BURNIE); `curseCount += 2` (1 stack) saturating at the shared cap; write back `mintPacked_[smitee]`; `emit Smited(deityId, smitee)`. 1 smite/tx. Pure ledger/score effect — no ETH, no RNG, no prize-pool touch.

### SPEC — design-lock + anchor re-attestation (375)

- [x] **SPEC-01** (SPEC): Re-attest every cited `file:line` anchor against the frozen baseline `2bee6d6f`; LOCK the open knobs — AFPAY feature-first vs accessor-first packing sequencing + `AfkingSpent` emission breadth + the `purchaseWith`-dead confirmation (`MintModule:858` — only def + `IDegenerusGameModules:242` + stale comments, no call site); CURSE counter cap (rec 20 pts) + the staleness day-basis (`_currentMintDay` vs `_simulatedDayIndex`, ≤1-day skew); SMITE protocol-addr skip (rec keep VAULT/SDGNRS/GNRUS — sDGNRS score feeds its redemption snapshot) + self-smite sanity; and map the producer-before-consumer edit order (CURSE counter/cure/APPLY BEFORE SMITE; the PACK accessor layer BEFORE the repack; the SOLVENCY invariant accessor location). Paper-only, ZERO `contracts/*.sol`.

### SEC — hard security floor (378)

- [ ] **SEC-01** (TST): RNG-freeze intact across all changes — no new player-manipulable VRF-derived read/write: AFPAY/PACK are ledger-only, CURSE/SMITE touch only the activity-score / curse-counter slots, none read `rngWord`. Proven empirically (determinism) + carried to the adversarial close (379).
- [ ] **SEC-02** (TST): SOLVENCY-01 re-attested — `claimablePool == Σ(claimableWinnings + afkingFunding)` holds across the AFPAY waterfall + the PACK repack + curse/smite (off the ETH path); `claimablePool` never exceeds `bal + stETH` after an afking-funded buy, a packed-balance credit/debit, a stale cashout, and a smite. Proven empirically (solvency-invariant) + carried adversarial.

### TST — proving regression tests (378)

- [x] **TST-01** (TST): AFPAY waterfall — DirectEth taps afking but skips claimable; Claimable/Combined draw claimable→sentinel then afking→0; the afking portion gets fresh-rate affiliate + lootbox activity score + presale credit with NO rebuy bonus; `AfkingSpent` emitted; reverts when both claimable + afking are short; NO double-draw with the afking auto-buy path (`_deliverAfkingBuy`/`_queueTicketsScaled` never reach `_processMintPayment`).
- [x] **TST-02** (TST): PACK — packed `[afking|claimable]` round-trips at every credit/debit/read site via the accessors; `claimablePool == Σ` holds; gameOver claimable-zeroing preserves the VAULT/SDGNRS/GNRUS afking halves; no 127→128 cross-half carry; behavior-identical to the two-mapping baseline.
- [x] **TST-03** (TST): CURSE SET — +2 only on a stale (≥5d) cashout, never for infra / gameOver / deity / whale / active-afker; penalty `curse*100` bps floored 0 visible across all consumers + the public view + frozen snapshots; stacking N → `min(2N, cap)`; same-day second claim reverts (sentinel) so no in-day stacking; saturates at the cap, never wraps the uint8.
- [ ] **TST-04** (TST): CURE + bounty + decurse — `curseCount` resets to 0 on a ≥1-ticket buy (direct / batch / affiliate / whale bundle / lootbox ≥ ticket), fresh ETH or claimable; a sub-ticket / small-lootbox buy stamps `DAY_SHIFT` (bounty-eligible, halts growth) but does NOT cure; a manual lootbox buyer is now `_bountyEligible`; `decurse` clears for 100 BURNIE (reverts if already 0, emits `Decursed`).
- [ ] **TST-05** (TST): SMITE — the `ownerOf` gate rejects a non-deity caller (no burn); an active-afker smitee reverts before the burn; a target ≥5 stacks reverts; a successful smite burns 200 BURNIE + adds one stack (+2 pts) saturating at the shared cap + emits `Smited`; cashout-curse and smite share one counter; a single ≥1-ticket buy (or `decurse`) clears both sources.
- [ ] **TST-06** (TST): NON-WIDENING vs the frozen baseline `2bee6d6f` — the forge + Hardhat suite enumerated BY NAME (every pre-existing red), the v61 changes add green, the carried harness layout/RNG artifacts stay characterized (no new contract regression).

### AUDIT — terminal close (379)

- [ ] **AUDIT-01** (TERMINAL): delta-audit (every changed surface across the 17 contract reqs NON-WIDENING vs `2bee6d6f` with grep/diff anchors, zero orphan hunks; RNG-freeze + the SOLVENCY-01 identity re-attested with anchors) + the mandatory 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/economic-analyst` + `/zero-day-hunter`; `/degen-skeptic` = the dual-gate filter per `D-271-ADVERSARIAL-02`) focused on the afking-payment solvency accounting + the PACK repack + the curse/smite activity-score path + `audit/FINDINGS-v61.0.md` (chmod 444) + the atomic closure flip with the `MILESTONE_V61_AT_HEAD_<sha>` signal; re-attest all v61.0 requirements against the frozen closure HEAD; KNOWN-ISSUES.md byte-unmodified unless a genuine new finding is recorded.

---

## Future Requirements (deferred)

- The v52 consolidated cross-model audit (the cumulative v50/v51 surface + `FINDINGS-v50.0.md` / `FINDINGS-v51.0.md` backfill) — a SEPARATE future track.
- The blind-spot-driven **v62 audit** (`.planning/AUDIT-V62-PLAN.md`) — runs AFTER v61.

## Out of Scope (v61.0)

- **afking auto-buy own spend** (`GameAfkingModule:791-799`) — already debits afking inline; not a player "spend to buy."
- **`claimWinnings`/sweep, gameOver distribution zeroing (`GameOverModule:209-214`), sDGNRS redemption reserve (`DegenerusGame.sol:2069`), far-future salvage relabel (`MintModule:1026`), decimator payout accounting (`DecimatorModule:398`)** — not shortfall-spend paths; left untouched.
- **the mintBurnie / `purchaseCoin` chain** — excluded by construction (the coin branch never reaches `_processMintPayment`).
- **curse on `claimWinningsStethFirst`** (vault-only self-claim) — the curse SET fires only on the public `claimWinnings`.
- **migration scaffolding for the PACK storage break** — pre-launch redeploy-fresh, no migration.

---

## Traceability

| REQ-ID | Phase | Type | Status |
|--------|-------|------|--------|
| SPEC-01 | 375 | SPEC | Complete |
| AFPAY-01 | 376 | IMPL | Pending |
| AFPAY-02 | 376 | IMPL | Pending |
| AFPAY-03 | 376 | IMPL | Pending |
| AFPAY-04 | 376 | IMPL | Pending |
| AFPAY-05 | 376 | IMPL | Pending |
| AFPAY-06 | 376 | IMPL | Pending |
| AFPAY-07 | 376 | IMPL | Pending |
| PACK-01 | 376 | IMPL | Pending |
| PACK-02 | 376 | IMPL | Pending |
| CURSE-01 | 376 | IMPL | Pending |
| CURSE-02 | 376 | IMPL | Pending |
| CURSE-03 | 376 | IMPL | Pending |
| CURSE-04 | 376 | IMPL | Pending |
| CURSE-05 | 376 | IMPL | Pending |
| CURSE-06 | 376 | IMPL | Pending |
| CURSE-07 | 376 | IMPL | Pending |
| SMITE-01 | 376 | IMPL | Pending |
| SEC-01 | 378 | TST | Pending |
| SEC-02 | 378 | TST | Pending |
| TST-01 | 378 | TST | Complete |
| TST-02 | 378 | TST | Complete |
| TST-03 | 378 | TST | Complete |
| TST-04 | 378 | TST | Pending |
| TST-05 | 378 | TST | Pending |
| TST-06 | 378 | TST | Pending |
| AUDIT-01 | 379 | TERMINAL | Pending |

**27/27 v61.0 requirements mapped to exactly one phase** — 375 SPEC: 1 · 376 IMPL: 17 · 377 GAS: 0 · 378 TST: 8 · 379 TERMINAL: 1. Per-category: AFPAY 7 · PACK 2 · CURSE 7 · SMITE 1 · SPEC 1 · SEC 2 · TST 6 · AUDIT 1. 0 orphaned, 0 duplicated. Phase 377 GAS owns no REQ-ID (the gas-neutrality measurement gate).
