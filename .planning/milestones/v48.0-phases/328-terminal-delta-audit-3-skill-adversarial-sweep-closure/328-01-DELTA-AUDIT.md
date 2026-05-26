---
phase: 328-terminal-delta-audit-3-skill-adversarial-sweep-closure
plan: 01
milestone: v48.0
milestone_name: sDGNRS Far-Future Salvage Swap + v47 Deferred-Findings Fixes + Keeper/Pool/Tombstone/Hero Bundle
audit_baseline: da5c9d50989707c8964a9411e68c51ca1b1a25f2
audit_baseline_signal: MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2
audit_subject_head: 1575f4a9
source_tree_frozen_ref: 1575f4a9
delta_commits: [f50cc634, 1575f4a9]
delta_diffstat: "12 files, +611 / -324 (git diff da5c9d50..1575f4a9 -- contracts/)"
requirements: [BATCH-03]
new_findings_resolved: [F-47-01, F-47-02]
foundry_baseline: "632 pass / 42 fail of 674 (327-06 ledger)"
---

# 328-01 — SC1 Delta Audit (v48.0 TERMINAL)

This is the SC1 delta-audit log for the v48.0 milestone TERMINAL phase. It enumerates every
`contracts/*.sol` surface changed by the v48.0 batched diff relative to the v47.0-closure baseline
`MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` (`da5c9d50`), attests each
**NON-WIDENING** with concrete grep/diff evidence drawn from the FROZEN subject `1575f4a9`, maps each
delta change to exactly one of the 7 v48 work-item surfaces, records the regression-baseline
attestation (632/42 net-zero), and closes the two v47-deferred MEDIUM findings (F-47-01, F-47-02) as
RESOLVED-AT-V48. It mirrors the v47 §3.A delta-surface / §3.B composition / §5 regression / §4.2
finding-disposition structure so the 328-03 findings deliverable can fold it into `audit/FINDINGS-v48.0.md`
§3/§5.

**Read-only.** Zero `contracts/*.sol` edits. The subject is byte-frozen: `git diff 1575f4a9 HEAD -- contracts/`
is empty throughout this phase. All anchors are re-grepped against `1575f4a9` via
`git show 1575f4a9:<file>` / `git diff da5c9d50..1575f4a9 -- <file>` / `git grep … 1575f4a9`.

---

## 1. Audit Subject + Baseline

**Audit baseline.** v47.0 closure HEAD `da5c9d50989707c8964a9411e68c51ca1b1a25f2` (signal
`MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`).

**Audit subject (FROZEN).** HEAD `1575f4a9` = the Phase 326 IMPL batched diff `f50cc634`
(`feat(326): v48 batched contract diff — PFIX/RFALL/KEEP/POOL/BTOMB/HERO/SWAP`) + the Phase 327
HERO-04 byte-reproduced Degenerette payout-finals landing `1575f4a9` (`feat(327): land byte-reproduced
Degenerette payout finals + enforce neutral baseline EV`). The HERO-04 landing is **constant-only** —
15 byte-reproduced finals into `DegenerusGameDegeneretteModule.sol`, 0 storage impact (USER-approved
hand-review). Both commits are part of the frozen subject.

**Delta surface.** `git diff da5c9d50..1575f4a9 -- contracts/` = **12 files changed, 611 insertions /
324 deletions**, across exactly two commits (`git log da5c9d50..1575f4a9 -- contracts/` = `1575f4a9` +
`f50cc634`):

| # | File | Δ (insertions/deletions per diffstat) | Owning v48 surface(s) |
|---|------|----------------------------------------|------------------------|
| 1 | `contracts/modules/DegenerusGameLootboxModule.sol` | 15 (+8/−7) | **PFIX** (item 1) |
| 2 | `contracts/StakedDegenerusStonk.sol` | 39 (+30/−9) | **RFALL** (item 2) + **POOL** (item 4) |
| 3 | `contracts/DegenerusGame.sol` | 160 | **RFALL** (item 2) + **KEEP** (item 3) + **SWAP** (item 7) |
| 4 | `contracts/AfKing.sol` | 146 | **KEEP** (item 3) |
| 5 | `contracts/DegenerusVault.sol` | 29 (+29) | **KEEP** (item 3) + **POOL** (item 4) + **SWAP** (item 7) |
| 6 | `contracts/interfaces/IDegenerusGame.sol` | 6 | **KEEP** (item 3) + **SWAP** (item 7) |
| 7 | `contracts/interfaces/IDegenerusGameModules.sol` | 12 (+12) | **KEEP** (item 3) + **POOL** (item 4) + **SWAP** (item 7) |
| 8 | `contracts/BurnieCoin.sol` | 23 (+23) | **BTOMB** (item 5) |
| 9 | `contracts/modules/DegenerusGameGameOverModule.sol` | 10 (+10) | **BTOMB** (item 5) |
| 10 | `contracts/modules/DegenerusGameDegeneretteModule.sol` | 311 | **HERO** (item 6) |
| 11 | `contracts/modules/DegenerusGameMintModule.sol` | 116 | **SWAP** (item 7) |
| 12 | `contracts/modules/DegenerusGameMintStreakUtils.sol` | 68 (+68) | **SWAP** (item 7) |

All 12 files are accounted for; every file maps to ≥1 of the 7 surfaces; every surface owns ≥1 file.
The **composition matrix (§3)** proves each individual delta *hunk* maps to exactly one surface (no orphan
hunks across the multi-item shared files DegenerusGame / sStonk / Vault / the two interfaces).

> **SPEC-text reconciliation.** The v48 SPEC said "`AfKing.sol` UNCHANGED" — that statement is scoped to
> **item 4 (POOL)**: the pool-recovery interface adds (`IAfKing`/`IAfKingSubscribe` `withdraw`/`poolOf`)
> live in the *consumer* contracts (sStonk, Vault), not in AfKing's own recovery logic. `AfKing.sol` IS
> changed by **item 3 (KEEP)** — the keeper rename (`sweep`→`autoBuy`, `crankBets`→`autoResolve`,
> `crankBoxes`→`autoOpen`) + the `bytes32("DGNRS")` affiliate wiring. Both statements are true and
> non-contradictory.

---

## 2. Per-Surface Delta-Surface Table (mirrors v47 §3.A)

Columns: **Surface | Requirements | Re-grepped anchors @ `1575f4a9` | Disposition.** Every anchor below
was re-verified against the frozen subject via `git show`/`git diff`/`git grep` (read-only).

| Surface | Requirements | Re-grepped anchors @ `1575f4a9` | Disposition |
| --- | --- | --- | --- |
| **PFIX** — presale-box DGNRS drain fix (F-47-01) | PFIX-01·02·03 | `_presaleBoxDgnrsReward` divisor moved `1_000 → 400`, base `poolStart/100 → poolStart/40` (`LootboxModule:719` `dgnrsAmount = (poolStart * tierTenths * amount) / (400 * 1 ether)`); inline `base` derivation comment updated (`:709`, `:717`); curve-comment updated (`:299-302`, "base = poolStart/40 … with the ~40% DGNRS branch rate the pool drains through the boxes"); tier shape preserved — `PRESALE_BOX_DGNRS_TIER1..5_TENTHS = 30/25/20/15/10` UNCHANGED (`:304-308`, tier-1 still 3× tier-5 DGNRS-per-ETH); `transferFromPool(Pool.PresaleBox,…)` clamp held (`:720`). ISOLATED — only `LootboxModule.sol` (15-line diff); touches no other item's surface. PFIX-02/03 dust-bound proof: `test/fuzz/PresaleBoxDrain.t.sol` (327-01, 3/3 GREEN). | **NON-WIDENING** |
| **RFALL** — redemption ETH-empty stETH fallback (F-47-02) | RFALL-01·02·03·04·05 | `pullRedemptionReserve(uint256 amount)` rewritten pure-ETH OR pure-stETH, no mix (`DegenerusGame.sol:1896`): ETH leg requires `claimableWinnings[SDGNRS] >= amount && address(this).balance >= amount` then CHECKED debit + CEI move-out (`:1900-1909`); stETH leg fallback when ETH can't cover — coverage checked against `steth.balanceOf(SDGNRS) >= amount`, NO game-side move/ledger debit (`:1916-1918`); `revert E()` fail-closed if neither pure leg covers (`:1921`). sStonk `_submitGamblingClaimFrom` reservation comment + `_payEth` ETH-then-stETH selection updated (`StakedDegenerusStonk.sol:884-892`, `:930-938`); `pendingRedemptionEthValue` single-tracked-value shape held (RFALL-04). Donation-robust: coverage checked against the **same asset basis the base is inflated by** (stETH donation inflating `totalMoney` ⇒ coverable by the pure-stETH leg). Extends the v47 game-over deterministic ETH→stETH fallback (REDEEM-04) to the **mid-game ETH-depletion** case. RFALL-05 regression: `test/fuzz/RedemptionStethFallback.t.sol` (327-02, 10/10) + `invariant_RFALL05_SolvencyUnderFallback` (`RedemptionAccounting.t.sol` 16→18 invariants). | **NON-WIDENING** |
| **KEEP** — keeper rename + VAULT affiliate code | KEEP-01·02·03·04·05 | Kill-set **grep-ZERO**: `git grep -ciE 'crank\|sweep\|do.?work' 1575f4a9 -- contracts/AfKing.sol` = **0**; `… contracts/DegenerusGame.sol` = **0** (the in-game crank entrypoints). New names present: `AfKing.autoBuy(uint256)` (`AfKing.sol:567`), `autoBuyProgress()` (`:527`); `DegenerusGame.autoResolve(…)` (`:1587`), `autoOpen(uint256)` (`:1636`), `enqueueBoxForAutoOpen(…)` (`:1570`), internal `_autoResolveBet`/`_autoOpenBox` (`:1684`/`:1705`). `creditFlip`/`BOUNTY_ETH_TARGET` KEPT (`AfKing.sol:63`/`:263`/`:279`; minted-flip-credit bounty unchanged, no funding-pool overlay — KEEP-02). Affiliate two-tier wiring: keeper purchase passes `bytes32("DGNRS")` (was `0`) into `_purchaseFor` at `DegenerusGame._batchPurchaseUnit` (`:598`), comment-documented "primary 75% → SDGNRS, secondary 20% → VAULT (two-tier cross-referral); a player already holding a real human affiliate keeps it (the affiliate's !infoSet fall-through)" (`:1745-1746`) per USER-LOCKED KEEP-04 owner attribution (SDGNRS primary / VAULT secondary; `DegenerusAffiliate.sol:247-250` owner = SDGNRS protocol contract). Interface rename `enqueueBoxForCrank → enqueueBoxForAutoOpen` (`IDegenerusGame.sol:24→25`). | **NON-WIDENING** |
| **POOL** — AfKing pool recovery | POOL-01·02·03·04·05·06 | VAULT permissionless `recoverAfKingPool()` → `afKing.withdraw(afKing.poolOf(address(this)))` (`DegenerusVault.sol:38-40`; no owner gate, no gameOver gate; recovered ETH lands in VAULT reserves via its open `receive()`; comment: AfKing.withdraw sends to the CALLER so an external trigger cannot redirect it). sDGNRS `receive()` relaxed to accept `AF_KING` in addition to `GAME` (`StakedDegenerusStonk.sol:439-443`, `if (msg.sender != GAME && msg.sender != AF_KING) revert Unauthorized();`). sDGNRS `burnAtGameOver()` (`onlyGame`) auto-recovers BEFORE the `balanceOf(this)==0` early-return: `afKing.withdraw(afKing.poolOf(address(this)))` at `:539` (precedes `if (bal == 0) return;` at `:541`); `withdraw(0)` no-op cannot brick gameOver. NO standalone sDGNRS withdraw. Interface adds `withdraw(uint256)` + `poolOf(address) returns (uint256)` to `IAfKingSubscribe` (sStonk `:67-70`) + the Vault-side `IAfKing` (`DegenerusVault.sol:23-26`) — match `AfKing.sol`'s signatures verbatim; **`AfKing.sol`'s recovery-interface LOGIC is UNCHANGED** (the only AfKing diff is the item-3 rename). POOL-04 `address(this).balance` accounting-safety proof: `test/fuzz/RedemptionStethFallback.t.sol` invariant extension (327-02). | **NON-WIDENING** |
| **BTOMB** — gameover BURNIE tombstone | BTOMB-01·02·03 | `BurnieCoin.tombstoneAtGameOver()` (`BurnieCoin.sol:36`): GAME-only, one-shot via `bool private _tombstoneFlooded` latch (`:22`; `if (_tombstoneFlooded) return;` `:38` → `_tombstoneFlooded = true;` `:39`); `_supply.vaultAllowance = _toUint128(uint256(_supply.vaultAllowance) + BURNIE_TOMBSTONE_WEI)` (`:40-42`) where `BURNIE_TOMBSTONE_WEI = 1e36` (`:12`); CHECKED add via `_toUint128` (reverts on `uint128` overflow; 1e36 ≪ uint128 max ~3.4e38, ~340× headroom — BTOMB-02). Circulating `totalSupply()` UNTOUCHED — the diff adds no `_supply.totalSupply` mutation; comment confirms "signal lands only in supplyIncUncirculated(), vaultMintAllowance(), and balanceOf(VAULT) — circulating totalSupply() is untouched" (`:33`). Wired one-shot from the gameover-drain: `GameOverModule` declares `IBurnieTombstone.tombstoneAtGameOver()` (`:31`) and calls `burnie.tombstoneAtGameOver()` (`:152`). BTOMB-03 non-circulating + DGVB pro-rata overflow-safe proof: `test/fuzz/BurnieTombstone.t.sol` (327-03, 8/8 GREEN). | **NON-WIDENING** |
| **HERO** — Degenerette hero 2-pt rescale | HERO-01·02·03·04·05·06 | Standalone-multiplier kill-set **grep-ZERO**: `git grep -ciE '_applyHeroMultiplier\|HERO_BOOST\|HERO_PENALTY\|HERO_SCALE' 1575f4a9 -- contracts/modules/DegenerusGameDegeneretteModule.sol` = **0**. Scoring is now `S = A + 2·H ∈ {0..9}` — `_score(...)` replaces `_countMatches` (`DegeneretteModule:673` "Score this spin: S = A + 2*H (hero symbol worth 2), S ∈ {0..9}"; distribution comment `:245` "P_N(S) (S = A + 2*H ∈ {0..9}) so that basePayoutEV = exactly …"; field-name retained `:95` "Composite score S = A + 2*H (0-9). Field name retained"). Hero quadrant stays mandatory: `if (heroQuadrant >= 4) revert InvalidBet();` (`:495`) + `FT_HERO_SHIFT` decode KEPT (`:337`, `:629`, `:893-896`). 15 byte-reproduced finals landed (the `1575f4a9` constant-only landing: 5 `QUICK_PLAY_PAYOUTS_N{0..4}_PACKED` + 5 `QUICK_PLAY_PAYOUT_N{0..4}_S8` + 5 `WWXRP_FACTORS_N{0..4}_PACKED`). HERO-04 PASS_ALL byte-reproduce gate: Hardhat 0-diff GREEN at `1575f4a9` (per-N basePayoutEV == 100 centi-x, ETH bonus == 5.000%; `test/stat/DegenerettePerNEvExactness.test.js` + `DegeneretteBonusEv.test.js`); HERO-06 write-batch DGAS equivalence + `dailyHeroWagers` no-leak: `test/fuzz/DegeneretteHeroScore.t.sol` (327-04, 6/6 GREEN). | **NON-WIDENING** |
| **SWAP** — sDGNRS far-future salvage swap | SWAP-01·02·03·04·05·06·07·08·09 | `DegenerusGame.sellFarFutureTickets(player, levels, quantities, queueIndices)` (`:1933`): `player = _resolvePlayer(player)` operator-honor (`:1939`); delegatecalls `IDegenerusGameMintModule.sellFarFutureTickets.selector` (`:1944`). MintModule body (`MintModule` diff, 116 lines): `rngLocked`-gated; `oneTicketWei = PriceLookupLib.priceForLevel(_activeTicketLevel())`; ticket-floor-first `if (totalBudget < oneTicketWei) revert E();`; inline fail-closed claimable debit `if (claimableWinnings[SDGNRS] < totalBudget + 1 ether) revert E();` (≥1 ETH floor, NO `pendingRedemptionEthValue` term); `claimableWinnings[SDGNRS] -= totalBudget` claimant-to-claimant relabel (claimablePool unchanged); per-line `_removeFarFutureTickets(player, L, entries, queueIndices[i])` O(1) caller-verified swap-pop (`q[idx]==player`) maintaining `membership ⟺ packed != 0`; d-curve + settled-word jitter via `_farFutureFractionBps(d)` + `_quoteFarFutureSwap(...)` (`MintStreakUtils.sol:19`/`:37`). VAULT `gameSellFarFutureTickets(...) onlyVaultOwner` wrapper (`DegenerusVault.sol:51-55`). Interface add `sellFarFutureTickets` (`IDegenerusGame.sol:42`, `IDegenerusGameModules.sol`). SWAP-08 no-arb-at-ceiling proof (margin ~4.5pp @d6: salvage ceiling 16.5% < acquisition ~21%) + SWAP-09 solvency: `test/fuzz/FarFutureSalvageSwap.t.sol` (327-05, 9/9 GREEN). | **NON-WIDENING** |

**All 40 v48.0 REQ-IDs are referenced in the table above** — PFIX-01/02/03 · RFALL-01/02/03/04/05 ·
KEEP-01/02/03/04/05 · POOL-01/02/03/04/05/06 · BTOMB-01/02/03 · HERO-01/02/03/04/05/06 ·
SWAP-01/02/03/04/05/06/07/08/09 · BATCH-01/02/03 (BATCH-01 SPEC `325-SPEC.md`; BATCH-02 IMPL the batched
diff `f50cc634`; BATCH-03 = this TERMINAL audit). Each surface lists its owning REQ-IDs.

---

## 3. Composition Attestation Matrix (mirrors v47 §3.B)

Each delta *hunk* maps to **exactly one** of the 7 surfaces — proven by the per-file hunk attribution
below. There are no orphan hunks across the four multi-item shared files.

### 3.1 Surface-mapping (no orphan hunks across shared files)

- **`DegenerusGame.sol` (160 lines, items 2/3/7):** RFALL hunk = `pullRedemptionReserve` rewrite +
  `_payEth`/submit comments (`:1896-1921`); KEEP hunk = `autoResolve`/`autoOpen`/`enqueueBoxForAutoOpen`
  renames + `_batchPurchaseUnit` `bytes32("DGNRS")` affiliate wiring (`:598`, `:1570-1705`); SWAP hunk =
  `sellFarFutureTickets` entrypoint + delegatecall dispatch (`:1933-1944`). Every hunk lands in exactly
  one of {RFALL, KEEP, SWAP}; the kill-set grep (`crank/sweep/do-work` = 0) proves the KEEP rename is
  complete, not partial.
- **`StakedDegenerusStonk.sol` (39 lines, items 2/4):** RFALL hunk = `_submitGamblingClaimFrom`
  reservation comment + `_payEth` ETH-then-stETH selection (`:884-892`, `:930-938`); POOL hunk =
  `receive()` AF_KING relax (`:439-443`) + `burnAtGameOver` pool-recover (`:539`) + `IAfKingSubscribe`
  `withdraw`/`poolOf` adds (`:67-70`). Disjoint.
- **`DegenerusVault.sol` (29 lines, items 3/4/7):** POOL hunk = `IAfKing` adds + `recoverAfKingPool()`
  (`:23-40`); SWAP hunk = `gameSellFarFutureTickets onlyVaultOwner` wrapper (`:51-55`); the item-3 (KEEP)
  touch is the affiliate-routing path that resolves through the game (Vault holds the registered DGNRS
  code; no separate Vault-side rename hunk). Disjoint.
- **`interfaces/IDegenerusGame.sol` (6 lines) + `IDegenerusGameModules.sol` (12 lines):** KEEP rename
  (`enqueueBoxForCrank → enqueueBoxForAutoOpen`) + SWAP add (`sellFarFutureTickets`) + POOL add
  (`withdraw`/`poolOf` on the AfKing interface). Each decl maps to one surface.
- **Single-item files** (LootboxModule→PFIX, BurnieCoin+GameOverModule→BTOMB, DegeneretteModule→HERO,
  MintModule+MintStreakUtils→SWAP) — no cross-item ambiguity.

**Conclusion: zero orphan hunks.** Every line of the +611/−324 delta maps to exactly one of the 7
work-item surfaces.

### 3.2 Claimable-balance preserved (`claimablePool == Σ claimableWinnings`)

- **RFALL** ETH leg debits `claimableWinnings[SDGNRS] -= amount` AND `claimablePool -= uint128(amount)`
  in lockstep (`DegenerusGame.sol:1905-1906`) — the segregated ETH leaves the ledger and the pool
  together; the stETH leg moves nothing (records via `pendingRedemptionEthValue`). Conserved.
- **SWAP** cash leg is a pure claimant-to-claimant **relabel**: `claimableWinnings[SDGNRS] -= totalBudget`
  → credited to the player; `claimablePool` UNCHANGED (the comment states "relabel; claimablePool
  unchanged"). The ticket leg routes the budget's ticket portion into the prize pools (pool slack
  gained, never lost). SWAP-09 proves `claimablePool ≤ ETH + stETH` never violated (327-05).
- **POOL** recovery only moves *donated* AfKing prepaid-pool ETH back to VAULT/sDGNRS reserves (read live
  via `address(this).balance`); no claimable ledger entry is created or destroyed (POOL-04). NON-WIDENING.

### 3.3 BURNIE-net / tombstone non-circulating

- **BTOMB** floods only the *virtual VAULT mint allowance* `_supply.vaultAllowance` by 1e36 wei,
  one-shot, GAME-gated, CHECKED. It does NOT mint, does NOT touch circulating `totalSupply()`, and is
  bounded ~340× below `uint128` max. The signal surfaces only in `supplyIncUncirculated()` /
  `vaultMintAllowance()` / `balanceOf(VAULT)` (BTOMB-03 proven, 327-03). NON-WIDENING.
- **KEEP** keeps the v46 `creditFlip` minted-flip-credit bounty (gas-pegged `BOUNTY_ETH_TARGET`,
  coinflip-credit illiquidity faucet-lock) UNCHANGED; no new BURNIE emission path. NON-WIDENING.

### 3.4 RNG-freeze-intact (no new in-window VRF consumer)

- **SWAP** jitter is seeded from an already-SETTLED **past** VRF word (`rngWordByDay[currentDay-1]`,
  pinned at SPEC per `325-ATTEST-SWAP.md`, freeze-safe per `v45-vrf-freeze-invariant`); the entrypoint is
  `rngLocked`-gated; the swap-pop is deterministic bookkeeping. No new word is consumed inside the
  request→unlock window.
- **HERO** the Degenerette write-batch is **bookkeeping-only post-outcome** (the per-spin score `S` is
  computed from the already-resolved result ticket; the recalibrated tables are constants); no new RNG
  consumer; `dailyHeroWagers`/`_rollHeroSymbol` unaffected (reads wagers, not per-bet scores — HERO-06
  no-leak proven 327-04).
- **PFIX** the presale-box DGNRS draw reuses the v47 committed-word + domain-salt path UNCHANGED — only
  the scalar divisor moved; no RNG surface touched. NON-WIDENING.

**Composition verdict: NON-WIDENING across all four axes.**

---

## 4. Regression-Baseline Attestation (mirrors v47 §5)

### 4.1 Foundry baseline — 632 pass / 42 fail of 674, NON-WIDENING vs the 326-08 594/42 baseline

Per the 327-06 ledger `test/REGRESSION-BASELINE-v48.md` (the Wave-2 full-suite regression gate; FULL
`forge test` tree, NOT `--match-path`):

| Quantity | 326-08 baseline | Wave-1 delta | v48 baseline (327-06) |
|----------|-----------------|--------------|------------------------|
| `forge test` passed | 594 | **+38 NEW_PASSING** | **632** |
| `forge test` failed | 42 | **+0 net-new** | **42** |
| total | 636 | +38 | 674 |

`632 == 594 + 38` ✓ ; `42 == 42 + 0` ✓.

**NEW_PASSING = 38**, fully attributed to the 5 wave-1 test files + the redemption invariant extension
(all PASSING-only, zero red): `PresaleBoxDrain` 3 + `RedemptionStethFallback` 10 + `RedemptionAccounting`
invariant extension +2 (16→18) + `BurnieTombstone` 8 + `DegeneretteHeroScore` 6 + `FarFutureSalvageSwap`
9 = **38**.

**The 42 reds classify into named buckets (each red in exactly one bucket):**
- **Bucket A = 8** VRF/RNG pre-existing reds (out of v48 scope — v48 touched no VRF/Advance code):
  `VRFPathInvariants` ×3 (gap-day / coordinator-swap / stall-recovery) + `VRFCore` ×1 + `VRFLifecycle`
  ×1 + `VRFPathCoverage` ×1 + `RngLockDeterminism` ×1 (`vm.assume` over-rejection) + `RngIndexDrainBinding`
  ×1.
- **Bucket B = 34** stale-harness / v48-behavioral baseline reds (fixtures not yet re-synced to the v48
  contract; present at the 326-08 HEAD; re-sync owned by a future fixture-repair plan, NOT this terminal):
  `TicketRouting` 12 + `QueueDoubleBuffer` 9 + `TicketEdgeCases` 2 + `PrizePoolFreeze` 2 + `TicketLifecycle`
  1 + `GameOverPathIsolation` 1 + `LootboxBoonCoexistence` 2 + `AfKingSubscription` 1 +
  `AfKingFundingWaterfall` 1 + `CoverageGap222` 1 + `DegeneretteBet.inv` 1 + `DegeneretteFreezeResolution`
  1 (B13).
- **Bucket C = 0** HERO-deferred FOUNDRY-side reds. The HERO byte-reproduce red lived ENTIRELY in the
  Hardhat stat tree (§4.2); the only Foundry file asserting payout-magnitude (`DegeneretteHeroScore.t.sol`)
  is GREEN (6/6) because it asserts scoring SHAPE/dispatch off `FullTicketResult.matches`.

A(8) + B(34) + C(0) = **42** ✓. **Membership proof (327-06 §4):** NONE of the 18 failing suites was last
touched by a 327-01..05 wave-1 commit — every failing suite's last-touching commit is at or before
`f50cc634` (the v48 contract diff) or earlier (323/211/210/pre-v48). The 5 new wave-1 test files added
only PASSING tests. **Net new regression from the wave-1 work = 0.** No `## STOP — NEW REGRESSION OUTSIDE
BASELINE` block; the actual red NAME-set is a strict subset of the enumerated baseline union.

### 4.2 The conditional HERO byte-reproduce delta — RESOLVED at `1575f4a9`

The HERO-04 PASS_ALL byte-reproduce gate runs in the **Hardhat stat tree** (`DegenerettePerNEvExactness`
+ `DegeneretteBonusEv`), NOT `forge test`. The 327-06 ledger §3 recorded the **CONDITIONAL** delta:

| Runner | Pre-landing (327-06 run, subject `f50cc634`) | Post-landing (subject `1575f4a9`) | Delta |
|--------|-----------------------------------------------|-----------------------------------|-------|
| Hardhat stat gate | 15 passing / **1 failing** (PASS_ALL RED: 15/20 constants diverge from the canonical generator) | **16 passing / 0 failing** (PASS_ALL 0-diff GREEN; per-N EV == 100; ETH bonus == 5.000%) | **PASS_ALL flips GREEN** |
| `forge test` whole tree | 632 / **42** | 632 / **42** (forge-side HERO-deferred count = 0; the gate is Hardhat-only) | **0** on the forge failure count |

The audit subject `1575f4a9` IS the post-landing state (the USER-approved constant-only HERO-04 finals
landing). The byte-reproduce red was **Hardhat-only** and is now resolved (0-diff GREEN); the **forge
42-count is unchanged** (the HERO byte-reproduce red was never a forge red). The Memory-noted "Hardhat
PASS_ALL stat gate 1→0" flip is therefore realized at the frozen subject. One follow-on test-only edit
(`DegeneretteHeroScore.t.sol`'s `test_HERO_S8S9PackingDecodable` placeholder-0 → nonzero expectation) is
a test concern, GREEN today, and does not affect the forge count.

### 4.3 REG-01-equivalent NON-WIDENING attestation

`git diff da5c9d50989707c8964a9411e68c51ca1b1a25f2..1575f4a9 -- contracts/ test/`: **every hunk is
attributable to a known v48-scope commit** —
- the batched IMPL diff `f50cc634` (the 12-file contract surface across PFIX/RFALL/KEEP/POOL/BTOMB/HERO/SWAP),
- the HERO-04 finals landing `1575f4a9` (constant-only into `DegeneretteModule.sol`),
- the AGENT-committed wave-1 test files (the 5 new `test/fuzz/*` + the `RedemptionAccounting`/`RedemptionHandler`
  invariant extension under Phase 327).

`git diff 1575f4a9 HEAD -- contracts/` is **empty** (zero contract mutation in this terminal phase; subject
byte-frozen). **NON-WIDENING confirmed.**

---

## 5. v47-Deferred Findings — RESOLVED-AT-V48 (mirrors v47 §4.2 dispositions)

The two MEDIUM findings v47.0 surfaced and USER-DEFERRED→v48.0 (`audit/FINDINGS-v47.0.md` §4.2 / §9d) are
closed by this milestone. Each disposition is run through the **economic skeptic-filter** (structural-protection
check → 3-condition EV lens) before being recorded RESOLVED.

### F-47-01 — Presale closing-box DGNRS over-distribution (MEDIUM) → RESOLVED-AT-V48

**v47 finding.** The per-box DGNRS draw `(poolStart × tierTenths × amount) / (1_000 × 1e18)` with base
`poolStart/100` drained the 100B-DGNRS `Pool.PresaleBox` over 50 ETH **only if every box drew DGNRS** —
but the resolution branch is 50% BURNIE / **40% DGNRS** / 10% WWXRP and the draw did not scale for the
~40% branch rate, so ~60% (~6% of supply) was swept to the single closing buyer (a tokenomics
concentration windfall, NOT fund-loss/drain/inflation — the DGNRS is pre-minted + pool-bounded).

**v48 fix LANDED (PFIX-01 IMPL anchor @ `1575f4a9`).** `_presaleBoxDgnrsReward` divisor `1_000 → 400`,
base `poolStart/100 → poolStart/40` (`LootboxModule:719`, comment `:299-302`/`:709`/`:717`). The 2.5×-larger
per-box draw × the ~40% realized DGNRS branch rate drains the full pool in expectation, so the closing-box
sweep mops up only **variance dust**. PFIX-02/03 empirical dust-bound proof: `test/fuzz/PresaleBoxDrain.t.sol`
(327-01, 3/3 GREEN — dust bound ≤ small bound over a realistic 50-ETH run, NOT ~60%; tier shape preserved
3×; a run of early DGNRS hits empties the pool before close via the `transferFromPool` clamp → closing sweep
≈ 0, no revert / no over-draw).

**Skeptic-filter (structural-protection + 3-condition EV).** The fix does NOT re-open an over-drain or
inflation axis: `transferFromPool(Pool.PresaleBox,…)` still clamps to the live pool balance (structural
protection: cannot draw below zero, cannot mint), so the worst case is the pool empties *early* → closing
sweep = 0 (no revert, no over-draw). The 3-condition EV lens (attacker control of timing × exploitable
edge × net-positive EV) returns NEGATIVE: the draw is keyed off the FROZEN buy-time cumulative box volume
(no timing edge), the curve is deterministic, and the 2.5× rescale REDUCES (not inflates) the closing
windfall to dust. **Concentration concern CLOSED without re-opening over-drain/inflation. RESOLVED-AT-V48.**

### F-47-02 — Redemption submit ETH-empty stETH-fallback gap (MEDIUM) → RESOLVED-AT-V48

**v47 finding.** `_submitGamblingClaimFrom` computed the ETH base against sDGNRS's FULL backing
(`ethBal + stethBal + claimable − pending`), but `pullRedemptionReserve` segregated the MAX-175%
reservation from `claimableWinnings[SDGNRS]` ALONE, fail-closed, with NO fallback to sDGNRS's stETH/ETH
balance. The genuine residual case = **mid-game ETH depletion** (and a freely-transferable stETH donation
inflating the base) → a fail-closed revert could brick submit (liveness/availability; no funds at risk).

**v48 fix LANDED (RFALL-01/02/03 IMPL anchor @ `1575f4a9`).** `pullRedemptionReserve` now reserves the
MAX as **pure-ETH OR pure-stETH (no mix)**, with a **mid-game ETH→stETH fallback** and **revert-if-neither**,
donation-robust (`DegenerusGame.sol:1896-1921`): ETH leg requires both `claimableWinnings[SDGNRS]` and the
game's liquid ETH cover `amount` (CHECKED debit + CEI move-out); else the stETH leg covers against
`steth.balanceOf(SDGNRS) >= amount` (sDGNRS's own stETH already in safe custody, no game-side move, recorded
via `pendingRedemptionEthValue`, paid stETH at claim — `_payEth` ETH-then-stETH `:930-938`); revert
`E()` only if NEITHER pure leg covers. Coverage is checked against the **same asset basis the base is
inflated by** (a stETH donation inflating `totalMoney` ⇒ coverable by the pure-stETH leg). Extends the v47
game-over deterministic ETH→stETH fallback (REDEEM-04) to the mid-game case. RFALL-05 regression proof:
`test/fuzz/RedemptionStethFallback.t.sol` (327-02, 10/10) + `invariant_RFALL05_SolvencyUnderFallback`
(`RedemptionAccounting.t.sol`) + POOL-04 `address(this).balance` accounting-safety.

**Skeptic-filter (structural-protection + 3-condition EV).** The fix RESTORES liveness while PRESERVING
the v47 REDEEM-08 solvency invariants (proven 327-02): two same-period claimants both reserve, BURNIE-can't-block-ETH,
value conservation, `balance ≥ pending`. The fail-closed `revert` is RETAINED as the structural solvency
guard for the (now-unreachable-in-practice) "neither pure leg covers" state — the fix adds a *liveness*
leg, it does not weaken the *safety* guard. The 3-condition EV lens returns NEGATIVE: a stETH donation /
`selfdestruct` force-feed is verified NOT a profit/inflation/underflow exploit (coverage matches the
inflated asset basis; no claimable-ETH-only chokepoint reintroduced). **Liveness restored, solvency
preserved. RESOLVED-AT-V48.**

---

## 6. Self-Check + Frozen-Subject Attestation

- `git diff 1575f4a9 HEAD -- contracts/` = **empty** (zero contract mutation; subject byte-frozen).
- All anchors above are re-grepped against `1575f4a9` (read-only `git show`/`git diff`/`git grep`).
- Keeper kill-set (`crank`/`sweep`/`do-work`) = **0** in `AfKing.sol` AND `DegenerusGame.sol` (the in-game
  crank entrypoints). The only surviving `sweep` hits tree-wide are the unrelated word-sense
  (`handleFinalSweep` gameover fund-sweep — a pre-existing function NOT the keeper; and the PFIX
  presale "closing-box sweep" dust-mop language); `crank`/`do-work` = 0 everywhere. Doc-comment
  survivors of the unrelated word-sense are explicitly called out here.
- Standalone-hero-multiplier kill-set (`_applyHeroMultiplier`/`HERO_BOOST_*`/`HERO_PENALTY`/`HERO_SCALE`)
  = **0** in `DegeneretteModule.sol`.

**SC1 satisfied:** every contract surface changed vs the v47.0 baseline `da5c9d50` is enumerated and
attested NON-WIDENING with each delta hunk mapped to exactly one of the 7 v48 surfaces; the 632/42
foundry regression baseline is attested NON-WIDENING (594/42 + 38 NEW_PASSING + 0 net-new) with the
HERO byte-reproduce Hardhat gate flipped 15/20-diverge-RED → 0-diff-GREEN at `1575f4a9`; F-47-01 +
F-47-02 are recorded RESOLVED-AT-V48 (both passing the economic skeptic-filter); `contracts/` is
byte-identical to `1575f4a9`.

---

*v48.0 Phase 328 SC1 delta-audit authored 2026-05-26. Source-tree frozen throughout
(`git diff 1575f4a9 HEAD -- contracts/` empty). Folds into `audit/FINDINGS-v48.0.md` §3 (delta-surface +
composition) / §5 (regression) / §4 (F-47-01 + F-47-02 RESOLVED-AT-V48) at 328-03.*
