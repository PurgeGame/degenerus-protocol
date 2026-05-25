# Phase 325 SPEC — v48.0 Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation

**Milestone:** v48.0 (sDGNRS Far-Future Salvage Swap + v47 deferred-findings fixes + keeper/pool/tombstone/hero bundle).
**Baseline HEAD attested against:** `da5c9d50` (`MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`, the v47.0-closure HEAD; live `contracts/` tree byte-identical to baseline, zero drift).
**Inputs:** the 7 locked plan docs (`PLAN-V48-PRESALE-BOX-DRAIN-FIX.md` [item 1 PFIX], `PLAN-V48-REDEMPTION-ETH-STETH-FALLBACK.md` [item 2 RFALL], `PLAN-V48-KEEPER-RENAME-AND-VAULT-CODE.md` [item 3 KEEP], `PLAN-V48-AFKING-POOL-RECOVERY.md` [item 4 POOL], `PLAN-V48-GAMEOVER-BURNIE-TOMBSTONE.md` [item 5 BTOMB], `PLAN-V48-DEGENERETTE-HERO-2PT-RESCALE.md` [item 6 HERO], `PLAN-SDGNRS-FAR-FUTURE-SALVAGE-SWAP.md` [item 7 SWAP]) + the 4 attestation files in this dir (`325-ATTEST-PFIX-RFALL.md`, `325-ATTEST-KEEP-POOL.md`, `325-ATTEST-BTOMB-HERO.md`, `325-ATTEST-SWAP.md`) + the locked decisions in `325-CONTEXT.md` (D-01..D-06).
**Owns:** BATCH-01 (shared-surface reconciliation) + RFALL-04 + KEEP-04 + KEEP-05 + POOL-06.

> **Items 2/3/4/7 share three files** (`DegenerusGame.sol`, `StakedDegenerusStonk.sol`, `DegenerusVault.sol`) and therefore CANNOT land as independent diffs. Section 1 settles ONE final signature + an apply-order per shared construct so Phase 326 applies a single reconciled diff. Items 1/5/6 are ISOLATED (no cross-plan shared-signature entanglement; item 5 only co-hooks the gameover-drain that item 4 also touches — a coordination point, not a shared signature).

---

## 0. Attestation verdict (BATCH-01, Wave-1 roll-up)

**0 IMPL blockers across all 7 items.** Every cited `file:line` across all 7 plan docs is grep-attested against the v47.0-closure HEAD `da5c9d50` (live tree == baseline). **60 anchors attested (items 1-6) + the full SWAP economics/RNG/queue re-derivation (item 7): 58 MATCH / 2 immaterial SHIFTED / 0 ABSENT.** No "by construction" / "single fn reaches all paths" claim survives un-grepped (the `DegenerusGame` mint/jackpot inline-duplication precedent was re-checked: the affiliate-code site is the game's self-call wrapper, not AfKing — see C2). Raw per-anchor tables: the 4 `325-ATTEST-*.md` files. **Re-grep at edit time — the Phase 326 batched diff shifts every line below.**

**Aggregate verdict table (from Plans 01 + 02):**

| Doc | Items | Anchors | MATCH | SHIFTED | ABSENT | Blockers |
|-----|-------|---------|-------|---------|--------|----------|
| 325-ATTEST-PFIX-RFALL | 1, 2 | 13 | 13 | 0 | 0 | 0 |
| 325-ATTEST-KEEP-POOL | 3, 4 | 21 | 21 | 0 | 0 | 0 |
| 325-ATTEST-BTOMB-HERO | 5, 6 | 26 | 24 | 2 | 0 | 0 |
| 325-ATTEST-SWAP | 7 | full economics + RNG + queue re-derivation (5 sections) | n/a | n/a | n/a | 0 |
| **Total** | **1-7** | **60+SWAP** | **58** | **2** | **0** | **0** |

### Carried corrections (override the plan prose at IMPL time)

- **C1. PFIX fix target is EXACT.** The F-47-01 1-line fix lands at `DegenerusGameLootboxModule.sol:720` — `uint256 dgnrsAmount = (poolStart * tierTenths * amount) / (1_000 * 1 ether);` → change the divisor `1_000`→`400` (= `base = poolStart/40`), and rewrite the two derivation comments (`:716` `poolStart / 100` → `poolStart / 40`; `:718-719` `(100 * 10 * 1 ether)` → `(40 * 10 * 1 ether)`). Tier curve `[3.0,2.5,2.0,1.5,1.0]` (`_presaleBoxDgnrsTierTenths` :733-747) is scale-only — UNTOUCHED. The closing-box `transferFromPool` sweep (:686) clamps to live pool balance (`StakedDegenerusStonk.sol:481-483`) → a run of early DGNRS hits cannot over-draw.
- **C2. KEEP-03 wiring-site correction.** The affiliate code `0` is NOT in `AfKing.sol` — `AfKing.batchPurchase` carries no affiliate argument at all (`AfKing.sol:26-30/:821`). The `bytes32(0)` is hard-coded in the game's self-call wrapper: `DegenerusGame.sol:1778` `_purchaseFor(player, 0, msg.value, bytes32(0), payKind);` inside `_batchPurchaseUnit` (:1773-1778, reached from `batchPurchase`'s `try this._batchPurchaseUnit{value:slice}` :1748-1752). **KEEP-03's wiring target is `DegenerusGame.sol:1778`** (`bytes32(0)` → VAULT's registered code) — see §2 KEEP-04 for the literal.
- **C3. RFALL gap CONFIRMED PRESENT.** `pullRedemptionReserve` (`DegenerusGame.sol:1888-1899`) is a single CHECKED `claimableWinnings[SDGNRS]`-only debit (`-= amount` :1893 + `claimablePool -= uint128(amount)` :1894 + `payable(SDGNRS).call{value:amount}` :1897) with NO stETH/ETH fallback — reverts fail-closed via the 0.8 checked subtraction when claimable < amount. This is exactly the F-47-02 mid-game-ETH-depletion + stETH-donation brick. The claim-side `_payEth` (sStonk :918-933) ALREADY has a deterministic ETH→stETH fallback (the two stETH-transfer sites :622/:932 exist); the fix extends that pure-ETH-OR-pure-stETH segregation to the SUBMIT-side reservation (see R1/R4).
- **C4. BTOMB path clarification.** Reuse the clean GAME-gated `vaultEscrow(uint256)` (`BurnieCoin.sol:557-567`: gated `sender != GAME && sender != VAULT) revert OnlyVault()`, `_toUint128(amount)` :563, `_supply.vaultAllowance += amount128` :565 unchecked) for the one-shot flood — NOT the `:370` site (a mint-side RECLASSIFICATION that pairs `+= vaultAllowance` with `-= totalSupply`). 1e36 wei « `uint128` max (~3.4e38, ~340× headroom). The `+= amount128` in `vaultEscrow` is `unchecked` → the BTOMB SPEC must add an explicit checked-add/cap so `existing + 1e36` can't wrap (see §2 BTOMB packing).
- **C5. HERO immaterial SHIFTED (2).** `HERO_BOOST_N4_PACKED` is at `:343` (the plan cited `:339-342` for N0..N3; the full 5-table block to delete is `:339-343`). `HERO_SCALE` declaration is at `:345` (the `:331` anchor the plan cited is its NatSpec derivation comment, not the decl). Both content-present; net-deletion targets are :339-343 + :345. `FT_HERO_SHIFT` decode (:323/:637) + the `heroQuadrant >= 4` revert (:503) are KEPT (hero stays mandatory + stored; no bet-layout change).
- **C6. HERO-06 no-leak CONFIRMED.** `dailyHeroWagers`/`_rollHeroSymbol` (write `DegeneretteModule:541`, read `DegenerusGame.sol:2693`, `JackpotModule:1475/:1489`) consume the WAGERED hero-symbol pool, NOT per-bet `matches`/`S` scores. The `matches` 0-8→0-9 (`S`) widening cannot leak into the daily-hero-symbol jackpot — different state, different code path.
- **C7. SWAP plan-interface drift.** `_runEarlyBirdLootboxJackpot` is at `DegenerusGameJackpotModule.sol:639`, **NOT** `AdvanceModule.sol:639` as the plan's `<interfaces>` line claimed. Behavior matches (draws the activating-level `traitBurnTicket[lvl]` bucket + WRITES `_queueTickets(winner,lvl,…)` :666; does NOT read far-future `ticketQueue` membership). Correct the citation at IMPL.
- **C8. SWAP §12 worked-example recompute.** The plan-doc §12 vectors use the wrong `/4`-per-ticket basis (e.g. `oneTicketWei = priceForLevel(10)/4 = 0.01`). The TRUE basis (attestation §E): `oneTicketWei = priceForLevel(currentLevel)` (NOT `/4`); `owed` is in ENTRIES (4 entries = 1 whole ticket; game-side `TICKET_SCALE=100`); `faceWei = priceForLevel(L) × wholeTickets`. So `oneTicketWei = priceForLevel(10) = 0.04`. This is a documentation recompute, NOT a contract issue — the §A no-arb arithmetic already uses the correct whole-ticket basis.

### SWAP no-arb margin verdict (the load-bearing item, from Plan 02)

> **VERDICT: NO-ARB FLOOR HOLDS at the band CEILING. STOP rule NOT triggered.**
> Re-derived from live source at `da5c9d50`: max full payout `110% × fractionBps(6) = 1.10 × 15.00% = **16.50% of face @ d6**` (the binding distance, jitter ceiling a grinder/waiter captures). Cheapest realistic far-future-entry acquisition `≈ 21% of face` (lootbox conditional, EV-capped per-level 135%); cross-checks: whale-bundle `~45%`, systematic lootbox `~1437%`, per-level EV-cap floor `~74%`. **Margin = 21% − 16.5% = +4.50 percentage points > 0.** For `d > 6` the salvage fraction only falls (15%→5%) while acquisition cost is distance-independent or rises → the margin only widens; d6 is the binding case. The cash leg (60% share = `9.90% of face @ d6`) is a strict subset of the 16.5% total and moves neither the no-arb bar nor the redemption-drain magnitude. **D-05's accepted ~4.5pp ceiling margin is re-derived from source.** BURNIE — the only token cheap enough to threaten 16.5% — CANNOT mint a far entry (`purchaseCoin` `MintModule.sol:858` has no level arg; every mint targets `cachedLevel`/`+1` :898/:1360; the BURNIE-lootbox→future path is REMOVED, 0 grep hits). The SWAP-03 jitter seed is pinned to the SETTLED `rngWordByDay[currentDay-1]` (immutable-once-written, public; freeze-safe, no new mutable SLOAD in the rng window; swap stays `rngLocked()`-gated). The SWAP-06 swap-pop maintains `membership ⟺ packed != 0` and does NOT reproduce H-CANCEL-SWAP-MISS (11 consumers enumerated; only persistent cursor `processFutureTicketBatch` is rngLock-exclusive with the swap; the two far-future samplers gain no hot-path read).

### Discretion-item resolutions (grep-facts, not user decisions)

- **KEEP-04 = YES** — a registered `owner == VAULT` affiliate code EXISTS (`bytes32("DGNRS")` = `AFFILIATE_CODE_DGNRS`, seeded `DegenerusAffiliate.sol:247-254`). **No register-one setup step required.** Caveat: the two custom codes are cross-named (`AFFILIATE_CODE_DGNRS`=`"DGNRS"`→owner VAULT; `AFFILIATE_CODE_VAULT`=`"VAULT"`→owner SDGNRS). Wire the VAULT-owned literal `bytes32("DGNRS")` (see §2 KEEP-04 for the disambiguation).
- **KEEP-05 = EXISTING** — `autoOpen` is a RENAME of the live permissionless `crankBoxes` (`DegenerusGame.sol:1636`) / `_crankOpenBox` (:1705), not a new capability.
- **POOL-05 = VERBATIM MATCH** — `withdraw(uint256)` (`AfKing.sol:318`) + `poolOf(address) returns (uint256)` (`AfKing.sol:503`) match the planned interface adds exactly; `AfKing.sol` needs NO other change for item 4 (item 3's `sweep`→`autoBuy` rename is a separate work item).
- **BTOMB feasibility = CONFIRMED** — `uint128 vaultAllowance` field (:174), `totalSupply()` excludes (:256), `supplyIncUncirculated()`/`vaultMintAllowance()` include (:263-272), GAME-gated `vaultEscrow` increase path (:557-567), gameover-drain one-shot hook (`burnAtGameOver` :142 / GameOverModule) all exist; 1e36 « `uint128` max.
- **HERO-06 no-leak = CONFIRMED** (C6).

---

## 1. Shared Signatures (BATCH-01 reconciliation)

> The cross-plan joint edits. One settled signature + an explicit **apply-order** per shared construct so items 2/3/4/7 cannot land as conflicting independent diffs. R1/R2/R3 jointly cover the `DegenerusGame.sol` items-2/3/7 overlap; R4 covers the `StakedDegenerusStonk.sol` items-2/4 overlap; R5 covers the `DegenerusVault.sol` items-3/4/7 overlap; R6 covers the cross-repo `DroneManager` flag + the OPEN-E disposition confirmation.

### R1 — `DegenerusGame.pullRedemptionReserve` coverage branch (item 2 RFALL, D-06)

**Co-edits this construct:** item 2 only (but on the same FILE as items 3 + 7 → see apply-order). Composes on TOP of the v47-form (already `external`, SDGNRS-gated, CHECKED claimable-only debit per C3).

- **Final signature (unchanged selector):** `function pullRedemptionReserve(uint256 amount) external` — `msg.sender != ContractAddresses.SDGNRS) revert E();` and `if (amount == 0) return;` KEPT.
- **The coverage branch (D-06, pure-ETH OR pure-stETH, fail-closed, donation-robust):** before the CHECKED claimable debit, select the reservation asset against the SAME basis the submit base was inflated by:
  1. **ETH leg (as today):** if `claimableWinnings[SDGNRS]` / the game ETH side covers `amount`, do the existing CHECKED `claimableWinnings[SDGNRS] -= amount; claimablePool -= uint128(amount);` + `payable(SDGNRS).call{value:amount}`.
  2. **stETH leg (NEW fallback):** if the ETH side cannot cover, segregate the reservation in PURE stETH (sDGNRS already holds stETH; the claim then pays stETH via the existing :622/:932 transfer sites — no new external-call selector). The coverage check is against the stETH basis.
  3. **Neither covers → revert** (fail-closed; the locked "neither covers" case is not realistic).
- **Single `pendingRedemptionEthValue` tracker (D-06):** reuse the existing single value (`StakedDegenerusStonk.sol:263`, subtracted at submit :847 / preview :598 / resolve :758, decremented at roll-resolve :668/:719). Do NOT add a separate stETH-denominated reservation slot. The pure-ETH-OR-pure-stETH selection is recorded by which asset is physically moved, not a second counter.
- **Apply-order within the file:** R1 is the FIRST `DegenerusGame.sol` edit (lowest line range, :1888-1899). Apply R1 → R2 (rename, :1570-1778 region) → R3 (new `sellFarFutureTickets` entrypoint, appended) so the line shifts cascade downward predictably.

### R2 — `DegenerusGame` crank-entrypoint RENAME + VAULT affiliate code (item 3 KEEP, KEEP-05 + KEEP-03/04)

**Co-edits this file:** item 2 (R1) + item 7 (R3). The rename is a wide mechanical diff; the affiliate-wiring is a 1-token change at :1778.

- **Rename (KEEP-05 = EXISTING; renames live entrypoints, no new capability):**
  - `AfKing.sol:567` `sweep(uint256 maxCount)` → **`autoBuy(uint256 maxCount)`** (the keeper auto-BUY work entrypoint; this is the ONLY `AfKing.sol` edit for item 3, separate from item 4 which leaves AfKing untouched).
  - `DegenerusGame.sol:1587` `crankBets(...)` → **`autoResolve(...)`** ("permissionlessly resolve a caller-supplied list of Degenerette bets").
  - `DegenerusGame.sol:1636` `crankBoxes(uint256 maxCount)` → **`autoOpen(uint256 maxCount)`** ("permissionlessly open queued lootboxes").
  - Self-call helpers + enqueue: `_crankResolveBet` (:1684) → `_autoResolveBet`; `_crankOpenBox` (:1705) → `_autoOpenBox`; `enqueueBoxForCrank` (:1570) → `enqueueBoxForAutoOpen`.
  - Purge "crank"/"do-work"/"sweep" from CODE AND COMMENTS across both contracts (KEEP-01).
  - KEEP-02 KEPT UNCHANGED: the minted `creditFlip` bounty (`AfKing.sol:846`) + the ETH-pegged `BOUNTY_ETH_TARGET` (:263/:279).
- **Affiliate wiring (KEEP-03/04, at C2's corrected site):** `DegenerusGame.sol:1778` `_purchaseFor(player, 0, msg.value, bytes32(0), payKind);` → replace `bytes32(0)` with the VAULT-owned registered code `bytes32("DGNRS")` (= `AFFILIATE_CODE_DGNRS`, KEEP-04 = YES). Unreferred AfKing-joiners are then permanently captured by VAULT (foreclosure intended; a player already holding a real human code keeps it via the `_setReferralCode` `!infoSet` fall-through at `DegenerusAffiliate.sol:463-476`).
- **Apply-order:** apply R2 SECOND on `DegenerusGame.sol` (after R1, before R3). The `AfKing.sol` `sweep`→`autoBuy` rename is independent (apply with the rest of item 3).

### R3 — `DegenerusGame.sellFarFutureTickets` + inline `claimableWinnings[SDGNRS]` debit (item 7 SWAP)

**Co-edits this file:** item 2 (R1) + item 3 (R2). NEW entrypoint + NEW storage primitive `_removeFarFutureTickets`; appended after the existing functions → minimal interaction with R1/R2 beyond line-shift.

- **Final entrypoint signature (plan §5; types match the contract's level/quantity types):**
  ```solidity
  function sellFarFutureTickets(
      address player,            // resolved via _resolvePlayer (operator-honor), NOT bare msg.sender
      uint32[] calldata levels,
      uint256[] calldata quantities,
      uint256[] calldata queueIndices
  ) external;
  ```
  `rngLocked()`-gated (reverts while `rngLockedFlag`); mass-sell across many far levels (each `6 ≤ d=L-currentLevel ≤ 100`) → ONE aggregated current-level ticket mint + ONE cash credit. Units pinned (§E): `oneTicketWei = priceForLevel(currentLevel)` (NOT `/4`); `require totalBudget ≥ oneTicketWei`; ticket leg floored at ≥1 whole current ticket; cash share jittered ∈[20%,60%], fraction ×∈[70%,110%], seeded from `rngWordByDay[currentDay-1]`.
- **Inline `claimableWinnings[SDGNRS]` debit (mirrors R1's CHECKED pattern):** debit `claimableWinnings[SDGNRS]` INLINE inside `sellFarFutureTickets` (the ledger lives on the game contract — NO cross-contract `pullRedemptionReserve`-style call needed). Fail-closed CHECKED debit down to a ≥1 ETH `claimableWinnings[SDGNRS]` floor; **NO `pendingRedemptionEthValue` term** (the redemption desk is protected STRUCTURALLY post-v47); **NO daily cap**. Standing/by-construction authorization (`_resolvePlayer` operator-honor).
- **The swap-pop primitive `_removeFarFutureTickets(address player, uint24 L, uint32 n, uint256 idx) internal`** (plan §5): decrements `owed` (keeps `rem` dust with seller); on full sell-out (`newOwed == 0 && rem == 0` → `packed == 0`) verifies `q[idx] == player` then O(1) swap-pops the seller out of `ticketQueue[_tqFarFutureKey(L)]`; partial sells / sells leaving `rem` do NOT pop. Maintains `membership ⟺ packed != 0` (SWAP-06; the two far-future samplers `sampleFarFutureTickets` :2592 + `_awardFarFutureCoinJackpot` `JackpotModule:1754` gain NO hot-path read). Duplicate input lines per level MUST be aggregated so a level pops at most once with a valid index.
- **Apply-order:** apply R3 LAST on `DegenerusGame.sol` (after R1 + R2). The VAULT wrapper (R5) + the interface entry consume this signature.

### R4 — `StakedDegenerusStonk` joint edit (item 2 RFALL + item 4 POOL)

**Co-edits this file:** item 2 (`_submitGamblingClaimFrom` maxIncrement segregation) + item 4 (`receive()` relax + `burnAtGameOver` pool-recovery + interface adds). Settled together with apply-order.

- **Item 2 — `_submitGamblingClaimFrom` maxIncrement segregation (:880-887):** the 175% `maxIncrement` reservation pull (`game.pullRedemptionReserve(maxIncrement)` :885) gains the pure-ETH-OR-pure-stETH segregation mirroring R1's coverage branch (try ETH; fall back to pure stETH; revert if neither). The 4-term submit base (:847 `ethBal + stethBal + claimableEth - pendingRedemptionEthValue`) and the single `pendingRedemptionEthValue` (:263) are KEPT (D-06). Claim-time payout-asset selection matches the reserved asset (stETH-reserved → stETH-paid via :622/:932).
- **Item 4 — `receive()` relaxation (:433):** `receive() external payable onlyGame` → relax to ALSO accept `AF_KING` (so AfKing's `withdraw` send-back lands). Accounting-safe: reserves are read live via `address(this).balance` (no running counter SSTORE in `receive()`), so an `AF_KING`-sourced credit is not mis-attributed/double-counted (POOL-04).
- **Item 4 — `burnAtGameOver()` pool-recovery placement (:525-533):** fold `afKing.withdraw(afKing.poolOf(address(this)))` BEFORE the `balanceOf(this) == 0` early-return (:527) so a zero-pool-TOKEN sDGNRS still recovers its ETH pool. No standalone sDGNRS withdraw (D-04 locked).
- **Item 4 — inline `IAfKingSubscribe` adds (:57-67, POOL-05 verbatim):** add `function withdraw(uint256) external;` + `function poolOf(address) external view returns (uint256);` to the single-member interface (matches `AfKing.sol:318/:503` verbatim).
- **Apply-order within the file:** interface adds (:57) FIRST → `receive()` relax (:433) → `_submitGamblingClaimFrom` segregation (:880-887) → `burnAtGameOver` pool-recover (:525-533). (Order by ascending declaration; the interface decl must precede its first use.)

### R5 — `DegenerusVault` joint edit (item 3 KEEP + item 4 POOL + item 7 SWAP)

**Co-edits this file:** item 3 (affiliate pass-through — see note), item 4 (`recoverAfKingPool()` + interface adds), item 7 (`gameSellFarFutureTickets` wrapper + interface entry). Settled together.

- **Item 3 — affiliate pass-through:** the AfKing affiliate-code attribution for item 3 is wired at `DegenerusGame.sol:1778` (R2/C2), NOT in VAULT — VAULT's only KEEP-related touch is that the captured revenue routes to its registered code `bytes32("DGNRS")`. No VAULT signature change for item 3.
- **Item 4 — NEW permissionless `recoverAfKingPool()`:** `function recoverAfKingPool() external { afKing.withdraw(afKing.poolOf(address(this))); }` — recovered ETH lands in VAULT reserves via its open `receive()` (`DegenerusVault.sol:497`); NO gameOver gate (anytime recovery). Follows the existing `gameXxx` pattern shape (e.g. `gameOpenLootBox` :550).
- **Item 4 — inline `IAfKing`/`IAfKingSubscribe` adds (:76-86, POOL-05 verbatim):** add `withdraw(uint256)` + `poolOf(address) returns (uint256)` to the single-member interface.
- **Item 7 — `gameSellFarFutureTickets onlyVaultOwner` wrapper + interface entry:** add `sellFarFutureTickets(address,uint32[],uint256[],uint256[])` to the `IDegenerusGamePlayerActions` interface (:10/:395) + `function gameSellFarFutureTickets(uint32[] calldata levels, uint256[] calldata quantities, uint256[] calldata queueIndices) external onlyVaultOwner { gamePlayer.sellFarFutureTickets(address(this), levels, quantities, queueIndices); }` (the >50.1% DGVE holder can salvage VAULT's far inventory; VAULT self-calls, no operator). No reentrancy (output is internal ledger only; cash pulled later via `gameClaimWinnings`).
- **Apply-order within the file:** interface adds (:76 + the `IDegenerusGamePlayerActions` entry) FIRST → `recoverAfKingPool()` + `gameSellFarFutureTickets` wrappers (with the other `gameXxx onlyVaultOwner` wrappers). Consumes R3's settled signature.

### R6 — cross-repo `DroneManager` flag + OPEN-E disposition confirmation

**Not a `degenerus-audit` shared signature** — flagged for coordination before freeze.

- **`DroneManager` (degenerus-utilities, immutable, locked 32→33 surface):** +1 typed `onlyChainOwner` pass-through `sellFarFutureTickets(uint8 idx, uint32[] levels, uint256[] quantities, uint256[] queueIndices) onlyChainOwner → IGame(GAME).sellFarFutureTickets(_droneOf(idx), …)` matching its existing `purchase*` pattern. **Lands before the manager is deployed/frozen** — fold into its pending v47-interface re-sync (it still references the v47-deleted `purchaseBurnieLootbox`/`openBurnieLootBox`). Cross-repo; not in this milestone's `degenerus-audit` diff, but the SWAP entrypoint signature (R3) is the contract it must match.
- **OPEN-E operator-trust disposition CONFIRMED to cover the first value-destructive operator action.** `sellFarFutureTickets` can torch 85-95% of the resolved player's far-inventory value — a DIFFERENT risk shape than other operator actions (mint/purchase/bet spend funds on something the player wanted). Under the LOCKED OPEN-E disposition (operator = the same person or a fixed contract the player chose; do NOT model a tricked-into-approving actor; for a drone it's the chain owner's own `onlyChainOwner` manager acting on the owner's own position), this is ACCEPTABLE. The SPEC confirms the disposition EXPLICITLY covers a value-destructive operator call rather than assuming it (T-325-S* mitigated).
