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

## 4. Regression-Baseline Attestation + F-47-01/F-47-02 dispositions

*Authored in Task 2 (appended to this same artifact) — see the Regression-Baseline Attestation (632/42
NON-WIDENING), the F-47-01 + F-47-02 RESOLVED-AT-V48 dispositions, and the self-check below once Task 2
lands.*
