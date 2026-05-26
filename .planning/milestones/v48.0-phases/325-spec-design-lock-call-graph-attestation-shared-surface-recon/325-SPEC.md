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
- **C2. KEEP-03 wiring-site correction.** The affiliate code `0` is NOT in `AfKing.sol` — `AfKing.batchPurchase` carries no affiliate argument at all (`AfKing.sol:26-30/:821`). The `bytes32(0)` is hard-coded in the game's self-call wrapper: `DegenerusGame.sol:1778` `_purchaseFor(player, 0, msg.value, bytes32(0), payKind);` inside `_batchPurchaseUnit` (:1773-1778, reached from `batchPurchase`'s `try this._batchPurchaseUnit{value:slice}` :1748-1752). **KEEP-03's wiring target is `DegenerusGame.sol:1778`** (`bytes32(0)` → the protocol-owned registered code `bytes32("DGNRS")`, primary SDGNRS / secondary VAULT) — see §2 KEEP-04 for the literal + routing.
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

- **KEEP-04 = YES (USER-LOCKED)** — wire the protocol-owned registered code `bytes32("DGNRS")` (= `AFFILIATE_CODE_DGNRS`, seeded `DegenerusAffiliate.sol:247-250`). **Owner attribution (corrected vs source):** `"DGNRS"`→owner **SDGNRS** (:247-250); `"VAULT"`→owner **VAULT** (:243-246). Via the ctor cross-referral (:254-255) + the 75/20/5 roll (:583-603), an AfKing-captured player routes **primary (75%) → SDGNRS (protocol), secondary (20%) → VAULT** (5% → SDGNRS) — the user-confirmed intent; permanent from purchase #1. **No register-one setup step required.** Do NOT wire `bytes32("VAULT")` (owner VAULT, presale-mutable). See §2 KEEP-04.
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
- **Affiliate wiring (KEEP-03/04, at C2's corrected site):** `DegenerusGame.sol:1778` `_purchaseFor(player, 0, msg.value, bytes32(0), payKind);` → replace `bytes32(0)` with the protocol-owned (SDGNRS) registered code `bytes32("DGNRS")` (= `AFFILIATE_CODE_DGNRS`, KEEP-04 = YES). Unreferred AfKing-joiners are then permanently captured into the two-tier code — **primary (75%) → SDGNRS (protocol), secondary (20%) → VAULT** via the ctor cross-referral (foreclosure intended; a player already holding a real human code keeps it via the `_setReferralCode` `!infoSet` fall-through at `DegenerusAffiliate.sol:463-476`).
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

- **Item 3 — affiliate pass-through:** the AfKing affiliate-code attribution for item 3 is wired at `DegenerusGame.sol:1778` (R2/C2), NOT in VAULT — VAULT's only KEEP-related touch is that it receives the **secondary (20%) upline** share of captured revenue routed via the protocol-owned `bytes32("DGNRS")` code (primary 75% → SDGNRS). No VAULT signature change for item 3.
- **Item 4 — NEW permissionless `recoverAfKingPool()`:** `function recoverAfKingPool() external { afKing.withdraw(afKing.poolOf(address(this))); }` — recovered ETH lands in VAULT reserves via its open `receive()` (`DegenerusVault.sol:497`); NO gameOver gate (anytime recovery). Follows the existing `gameXxx` pattern shape (e.g. `gameOpenLootBox` :550).
- **Item 4 — inline `IAfKing`/`IAfKingSubscribe` adds (:76-86, POOL-05 verbatim):** add `withdraw(uint256)` + `poolOf(address) returns (uint256)` to the single-member interface.
- **Item 7 — `gameSellFarFutureTickets onlyVaultOwner` wrapper + interface entry:** add `sellFarFutureTickets(address,uint32[],uint256[],uint256[])` to the `IDegenerusGamePlayerActions` interface (:10/:395) + `function gameSellFarFutureTickets(uint32[] calldata levels, uint256[] calldata quantities, uint256[] calldata queueIndices) external onlyVaultOwner { gamePlayer.sellFarFutureTickets(address(this), levels, quantities, queueIndices); }` (the >50.1% DGVE holder can salvage VAULT's far inventory; VAULT self-calls, no operator). No reentrancy (output is internal ledger only; cash pulled later via `gameClaimWinnings`).
- **Apply-order within the file:** interface adds (:76 + the `IDegenerusGamePlayerActions` entry) FIRST → `recoverAfKingPool()` + `gameSellFarFutureTickets` wrappers (with the other `gameXxx onlyVaultOwner` wrappers). Consumes R3's settled signature.

### R6 — cross-repo `DroneManager` flag + OPEN-E disposition confirmation

**Not a `degenerus-audit` shared signature** — flagged for coordination before freeze.

- **`DroneManager` (degenerus-utilities, immutable, locked 32→33 surface):** +1 typed `onlyChainOwner` pass-through `sellFarFutureTickets(uint8 idx, uint32[] levels, uint256[] quantities, uint256[] queueIndices) onlyChainOwner → IGame(GAME).sellFarFutureTickets(_droneOf(idx), …)` matching its existing `purchase*` pattern. **Lands before the manager is deployed/frozen** — fold into its pending v47-interface re-sync (it still references the v47-deleted `purchaseBurnieLootbox`/`openBurnieLootBox`). Cross-repo; not in this milestone's `degenerus-audit` diff, but the SWAP entrypoint signature (R3) is the contract it must match.
- **OPEN-E operator-trust disposition CONFIRMED to cover the first value-destructive operator action.** `sellFarFutureTickets` can torch 85-95% of the resolved player's far-inventory value — a DIFFERENT risk shape than other operator actions (mint/purchase/bet spend funds on something the player wanted). Under the LOCKED OPEN-E disposition (operator = the same person or a fixed contract the player chose; do NOT model a tricked-into-approving actor; for a drone it's the chain owner's own `onlyChainOwner` manager acting on the owner's own position), this is ACCEPTABLE. The SPEC confirms the disposition EXPLICITLY covers a value-destructive operator call rather than assuming it (T-325-S* mitigated).

---

## 2. Open-item resolutions (every SPEC-time open item, resolved on paper)

Each subsection records the **decision + source (D-NN or grep verdict) + the IMPL instruction it produces.**

### RFALL-04 — `pendingRedemptionEthValue` accounting shape

- **Decision (D-06, LOCKED):** SINGLE tracked `pendingRedemptionEthValue` — pure-ETH OR pure-stETH reservation, NO mix. Do NOT introduce a separate stETH-denominated reservation slot.
- **Source:** `325-CONTEXT.md` D-06 + the RFALL plan §"Fix LOCKED shape"; attestation R6 (`325-ATTEST-PFIX-RFALL`) confirms the single value at `StakedDegenerusStonk.sol:263`, subtracted in all three bases (submit :847 / preview :598 / resolve :758), decremented at roll-resolve :668/:719.
- **IMPL instruction:** apply the pure-ETH-OR-pure-stETH selection consistently across submit (R4 `_submitGamblingClaimFrom` :880-887) / claim (asset-matched payout via the existing :622/:932 stETH-transfer sites) / gameOver (`burnAtGameOver` payout). Coverage is checked against the SAME asset basis the base is inflated by (donation-robust — a stETH `selfdestruct`/transfer force-feed inflates `stethBal` at :847 and MUST be coverable by the pure-stETH leg; do NOT reintroduce a claimable-ETH-only chokepoint). The single value records the segregated ETH amount; the stETH path is recorded by which asset is physically reserved/paid, not a second counter. Reverts fail-closed if neither pure leg covers (R1 step 3).

### KEEP-04 — protocol/VAULT two-tier affiliate code (USER-LOCKED 2026-05-25)

- **Verdict (grep-fact, USER-LOCKED):** YES — wire the **protocol-owned** registered code `bytes32("DGNRS")`. **Owner attribution (corrected vs source :243-250):** `affiliateCode[AFFILIATE_CODE_VAULT] = { owner: VAULT }` (:243-246) and `affiliateCode[AFFILIATE_CODE_DGNRS] = { owner: SDGNRS }` (:247-250) — i.e. code `"DGNRS"` (`= bytes32("DGNRS")`, :181) is owned by **SDGNRS** (the protocol/"house" contract; distinct from `ContractAddresses.DGNRS`), code `"VAULT"` by **VAULT**. (An earlier draft of this section claimed `"DGNRS"`→owner VAULT — wrong; corrected.) **No register-one setup step required.**
- **Source:** `325-ATTEST-KEEP-POOL` K5.
- **Routing (two-tier, user-confirmed intent — primary to protocol, secondary to VAULT):** the ctor cross-refers the owner addresses — VAULT's own referrer = `"DGNRS"` (:254 → upline SDGNRS); SDGNRS's = `"VAULT"` (:255 → upline VAULT). Under the 75/20/5 winner-takes-all roll (`DegenerusAffiliate.sol:583-603`), an AfKing-captured player carrying `"DGNRS"` routes **75% → SDGNRS (primary), 20% → upline1 VAULT (secondary), 5% → upline2 SDGNRS.** Capture is **permanent from purchase #1** (`_vaultReferralMutable("DGNRS")==false` always, :692-695 — not reclaimable even during presale); a player already holding a real human code keeps it (`!infoSet` fall-through :463-476).
- **IMPL instruction:** at `DegenerusGame.sol:1778` (C2) replace `bytes32(0)` with `bytes32("DGNRS")` (or the named `AFFILIATE_CODE_DGNRS` constant if reachable from that file) — captured revenue routes **primary → SDGNRS (protocol), secondary → VAULT** via the two-tier cross-referral. Do NOT wire `bytes32("VAULT")` (owner VAULT, presale-mutable — would send primary to VAULT and be reclaimable during presale).

### KEEP-05 — `autoOpen` existing-vs-new scope

- **Verdict (grep-fact):** EXISTING — opening queued lootboxes is already a live permissionless keeper capability (`DegenerusGame.sol:1636` `crankBoxes(uint256 maxCount)`, CRANK-03; self-call helper `_crankOpenBox` :1705). `autoOpen` is a RENAME, not a new function.
- **Source:** `325-ATTEST-KEEP-POOL` KEEP-05 resolution.
- **IMPL instruction (scope the rename, R2):** `crankBoxes`→`autoOpen` (:1636), `_crankOpenBox`→`_autoOpenBox` (:1705). Box-opening lives in `DegenerusGame`/modules (NOT `AfKing.sol`, which does auto-BUY via `sweep`→`autoBuy`); the rename spans both contracts. No new capability to author.

### POOL-06 — post-gameOver `depositFor(SDGNRS)` re-stranding

- **Decision (D-04, LOCKED):** ACCEPT-AS-MINOR — NO second sweep in `handleFinalSweep` (+30d).
- **Source:** `325-CONTEXT.md` D-04; attestation L11/L14 confirms `burnAtGameOver` (:525-533) already auto-recovers all pool ETH deposited BEFORE gameOver (R4 placement); the gameover-drain one-shot hook is `DegenerusGameGameOverModule.sol:142`.
- **IMPL instruction:** do NOT add a second sweep. **Record the documented known-minor:** a `depositFor(SDGNRS)` landing AFTER `burnAtGameOver` re-strands (sDGNRS has no later trigger and — per the locked design — gets NO standalone withdraw), but that is an adversarial/pointless self-donation that harms only the donor. VAULT is UNAFFECTED (anytime permissionless `recoverAfKingPool()`, R5). The residual is donor-only, no protocol loss.

### BTOMB packing — `vaultAllowance` checked-add/cap, one-shot

- **Decision (Claude's discretion, grep-derived):** the BTOMB flood reuses the GAME-gated `vaultEscrow(uint256)` (`BurnieCoin.sol:557-567`, C4) — NOT the `:370` reclassification site. Because `vaultEscrow`'s add is `unchecked` (:564-565), the one-shot flood MUST be guarded.
- **Source:** `325-CONTEXT.md` "BTOMB packing" discretion item; `325-ATTEST-BTOMB-HERO` B5/B7.
- **IMPL instruction:** add an explicit checked-add / cap so `existing vaultAllowance + 1e36 wei` cannot overflow `uint128` (1e36 « `uint128` max ~3.4e38, ~340× headroom; keep the constant well below 1e38 wei). Strictly **one-shot** from the gameover-drain (`burnAtGameOver` :142 / GameOverModule), gated on `gameOver()`, cannot be re-triggered. The flood (`1e36 wei` = 1 quintillion BURNIE) bumps `vaultAllowance` only → `totalSupply()` (:256) UNTOUCHED; the signal lands in `supplyIncUncirculated()` (:263-265) / `vaultMintAllowance()` (:270-272) / `balanceOf(VAULT)`. (BTOMB is ISOLATED from the items-2/3/4/7 shared surface, but co-hooks the gameover-drain — edit-order coordination with item-4 POOL recovery is in §3.)

### HERO-04 — payout SHAPE over `S ∈ {0..9}` (D-01/02/03, shape-lock only)

- **Decision (D-01/02/03, LOCKED):**
  - **D-01 (curve shape) = Continuity.** Across `S ∈ {0..9}` (fixed EV budget = 100 centi-x per pick, RTP unchanged), the real-match tiers `S=3..9` track today's `M=2..8` curve (shift-by-one — forced at the top by the locked `S=9 ≡ old M=8` jackpot relabel, identical odds). NOT the flatter "frequent-reward" nor the steeper "lottery" shapes.
  - **D-02 (`S=2` magnitude) = Partial refund (~40–60% of wager).** The new frequent hero-alone `S=2` tier (hero symbol alone ⇒ `S=A+2·H`=2 ⇒ guaranteed win) is a *felt* consolation. `S=2` hits ~16–20% of picks (15.9%@N=4 → 20.2%@N=0), consuming ~9% of the EV budget → `S=3..9` drift *modestly* below today's values to hold EV=100. (NOT a ~10–20% token, NOT ~0.8–1× break-even.)
  - **D-03 (bonus-currency thresholds) = Preserve rarity → S≥7.** Re-map today's `matches M≥6` thresholds (`_awardDegeneretteDgnrs` `DEGEN_DGNRS_6/7/8_BPS`; WWXRP bonus buckets) onto the new scale at `S≥7` (shift-by-one, consistent with `S=9≡M=8`). Recompute factors so ETH +5% / WWXRP high-roi bonus EV stays exact per `N`.
- **Source:** `325-CONTEXT.md` D-01/02/03 + the HERO plan §Decisions 1-3; attestation H1-H18 (`325-ATTEST-BTOMB-HERO`).
- **IMPL instruction (shape design-lock):** `_countMatches` (:932-962, counts 8 axes → {0..8}) → `_score(playerTicket, resultTicket, heroQuadrant) ∈ {0..9}` = 7 ordinary axes (4 color + 3 non-hero symbol) + `2 if hero symbol matches` (heroQuadrant's color stays an ordinary axis; pay floor `S≥2`). Net-DELETE `_applyHeroMultiplier` (:1070-1095), the 5 `HERO_BOOST_N*_PACKED` tables (:339-343, C5), `HERO_PENALTY` (:344), `HERO_SCALE` (:345, C5), and the `matches >= 2 && matches < 8` carve-out in `_fullTicketPayout` (:1047-1059). KEEP `FT_HERO_SHIFT` decode (:323/:637) + `heroQuadrant >= 4` revert (:503). `_getBasePayoutBps(N, matches)` → `_getBasePayoutBps(N, S)`; `_fullTicketPayout` dispatches on `S` (drop the multiplier branch). `_awardDegeneretteDgnrs` thresholds re-map to `S≥7`; `_wwxrpBonusBucket`/`_wwxrpFactor` re-map buckets to the 10-pt scale. **The byte-exact constants are SOLVED by `derive_5_tables.py` at TST (Phase 327) under the Phase-267-style byte-reproduce PASS_ALL gate — NEVER hand-typed here.** This SPEC locks only the SHAPE (continuity + S=2 ~40-60% partial refund + thresholds S≥7) + the byte-reproduce-gate handoff. The recalibration is payout-SHAPE only and MUST stay write-batch byte-identical to v47's `resolveBets` (DGAS, attestation H16). HERO-06 daily-hero jackpot is UNAFFECTED (C6).

### S=8 / S=9 packing scheme (>32-bit re-pack)

- **Decision (Claude's discretion, grep-derived):** the current layout is 9 buckets — `QUICK_PLAY_PAYOUTS_N0..N4_PACKED` hold M=0..7 (8 buckets × 32 bits = 256 bits per `uint256`, dispatch `(packed >> (matches*32)) & 0xFFFFFFFF` :1118) + a SEPARATE M=8 jackpot constant per N (`QUICK_PLAY_PAYOUT_N{N}_M8` :264-268, dispatched `if (matches >= 8) return ...` :1105-1110). Widening to S=0..9 adds TWO buckets (S=8 + S=9) beyond the 8 that fill a `uint256`.
- **Source:** `325-CONTEXT.md` "S=8/S=9 packing" discretion item; the HERO plan §"On-chain shape"; attestation H11.
- **IMPL instruction (settled layout):** keep the `QUICK_PLAY_PAYOUTS_N{N}_PACKED` `uint256` for S=0..7 (8 × 32-bit, unchanged dispatch `(packed >> (S*32)) & 0xFFFFFFFF` for S<8); hold **S=8 AND S=9 as SEPARATE per-N constants** (mirror the existing separate-M=8 pattern: `QUICK_PLAY_PAYOUT_N{N}_S8` + `QUICK_PLAY_PAYOUT_N{N}_S9`), dispatched `if (S >= 9) return ..._S9; if (S == 8) return ..._S8;` ahead of the packed `<8` path. `S=9 ≡ old M=8` reuses the existing jackpot constants' physical event (identical odds — a relabel). Both S=8 and S=9 may exceed 32 bits → separate `uint256` per N is required (cannot pack into the 256-bit word). The byte-exact S=8/S=9 values are likewise emitted by `derive_5_tables.py` at TST.

---

## 3. Per-item IMPL blueprint + edit-order map (the load-bearing input to Phase 326)

> **Files in the diff** (degenerus-audit `contracts/`): `modules/DegenerusGameLootboxModule.sol` (item 1), `modules/DegenerusGameDegeneretteModule.sol` (item 6), `BurnieCoin.sol` + `modules/DegenerusGameGameOverModule.sol` (item 5), `AfKing.sol` (item 3 `sweep`→`autoBuy` rename ONLY; item 4 leaves it UNCHANGED), `DegenerusGame.sol` (items 2/3/7 — R1→R2→R3), `StakedDegenerusStonk.sol` (items 2/4 — R4), `DegenerusVault.sol` (items 3/4/7 — R5), `interfaces/IDegenerusGame.sol` / `interfaces/IStakedDegenerusStonk.sol` (selector adds if needed), `ContractAddresses.sol` (if a new pinned address is needed — none expected).
> **Edit-order (mirror v47):** storage/enums + constants first → interface decls → helpers → callers → entrypoints → wrappers. Within `DegenerusGame.sol`: R1 (`pullRedemptionReserve` :1888) → R2 (rename :1570-1778 + affiliate :1778) → R3 (new `sellFarFutureTickets` + `_removeFarFutureTickets`, appended). Within `StakedDegenerusStonk.sol`: interface (:57) → `receive()` (:433) → `_submitGamblingClaimFrom` (:880) → `burnAtGameOver` (:525). Within `DegenerusVault.sol`: interfaces (:76 + `IDegenerusGamePlayerActions`) → `recoverAfKingPool()` + `gameSellFarFutureTickets` wrappers. **GameOverModule coordination:** item 4 (POOL — sStonk `burnAtGameOver` pool-recover, invoked via the existing :142 hook) and item 5 (BTOMB — the one-shot `vaultEscrow` flood, also hooked at the gameover-drain) both touch the gameover path — apply item-4's sStonk change (R4) and item-5's BurnieCoin/GameOverModule change as adjacent, non-conflicting edits (different contracts; the shared coupling is only the gameover-drain ordering, not a shared signature).

**Item 1 (PFIX) — ISOLATED, 1-line.** `DegenerusGameLootboxModule.sol:720` divisor `1_000`→`400` (`base = poolStart/40`) + the two derivation comments (:716, :718-719) per C1. Tier function (:733-747) UNTOUCHED; `transferFromPool` clamp held. No R-row (no shared surface). [PFIX-01]

**Item 2 (RFALL) — via R1 + R4.** `DegenerusGame.pullRedemptionReserve` coverage branch (R1) + `StakedDegenerusStonk._submitGamblingClaimFrom` maxIncrement segregation + claim-asset selection (R4). Single `pendingRedemptionEthValue` (D-06/RFALL-04, §2). Fail-closed, donation-robust. [RFALL-01/02/03]

**Item 3 (KEEP) — via R2 + R5.** `AfKing.sweep`→`autoBuy` (the only AfKing edit for item 3) + `DegenerusGame.{crankBets→autoResolve, crankBoxes→autoOpen, _crankResolveBet→_autoResolveBet, _crankOpenBox→_autoOpenBox, enqueueBoxForCrank→enqueueBoxForAutoOpen}` (R2; KEEP-05 EXISTING) + the `bytes32(0)`→`bytes32("DGNRS")` affiliate wiring at `DegenerusGame.sol:1778` (R2/C2; KEEP-04 §2). `creditFlip`/`BOUNTY_ETH_TARGET` KEPT. Purge "crank"/"sweep" from code + comments. [KEEP-01/02/03]

**Item 4 (POOL) — via R4 + R5.** sStonk `receive()` AF_KING relax + `burnAtGameOver` pool-recover before the `balanceOf(this)==0` early-return + the `IAfKingSubscribe` `withdraw`/`poolOf` adds (R4). VAULT `recoverAfKingPool()` permissionless + interface adds (R5). `AfKing.sol` UNCHANGED for item 4 (POOL-05 verbatim). POOL-06 = accept-as-minor, no second sweep (§2). [POOL-01/02/03/05]

**Item 5 (BTOMB) — ISOLATED, co-hooks gameover-drain.** `BurnieCoin` one-shot `vaultEscrow`-path flood (1e36 wei) with the checked-add/cap (§2 BTOMB packing; C4) + the `DegenerusGameGameOverModule` one-shot call at gameover (the :142-region drain). `totalSupply()` untouched; signal in uncirculated views. Edit-order coordination with item-4 at the gameover-drain (§3 header). [BTOMB-01/02]

**Item 6 (HERO) — ISOLATED + byte-reproduce-gate TST handoff.** `DegeneretteModule` `_countMatches`→`_score ∈ {0..9}`, net-delete the standalone hero multiplier apparatus (§2 HERO-04), `S=8/S=9` separate-`uint256` packing (§2), thresholds re-mapped to `S≥7` (D-03). Write-batch byte-identical to v47 `resolveBets` (DGAS). **The byte-exact 10-bucket per-N constants are emitted by `derive_5_tables.py` at TST (Phase 327) under the PASS_ALL byte-reproduce gate — this SPEC locks SHAPE only.** HERO-06 jackpot unaffected (C6). [HERO-01/02/03/05]

**Item 7 (SWAP) — via R3 + R5 + R6.** `DegenerusGame.sellFarFutureTickets` + the inline `claimableWinnings[SDGNRS]` debit (≥1 ETH floor, NO `pendingRedemptionEthValue` term, NO daily cap) + `_removeFarFutureTickets` swap-pop primitive (R3). Units: `oneTicketWei = priceForLevel(currentLevel)` (C8). VAULT `gameSellFarFutureTickets onlyVaultOwner` wrapper + interface entry (R5). Cross-repo `DroneManager` +1 typed pass-through + OPEN-E disposition confirmed (R6). `rngLocked()`-gated; jitter from `rngWordByDay[currentDay-1]` (freeze-safe); swap-pop maintains `membership ⟺ packed != 0` (no H-CANCEL-SWAP-MISS). [SWAP-01/02/03/04/05/06/07]

### Out-of-scope flag (flag, NOT fix)

> **The `matches` 0-8 → 0-9 (`S`) event-range widening is a FRONTEND / INDEXER concern.** `FullTicketResult.matches` (`DegeneretteModule:97-102`, NatSpec `(0-8)`) widens to `(0-9)`. The off-chain indexer / webpage that reads this event range (and any salvage-swap -EV labeling UI) is a SEPARATE frontend track, **OUT OF SCOPE** for v48.0 (PROJECT.md / `325-CONTEXT.md` `<specifics>`). FLAGGED here; not fixed in this milestone's contract diff.

### Success-criteria checklist (mapped 1:1 to ROADMAP Phase 325 SC1..SC5)

1. ✅ **SC1 — shared signatures settled.** §1 R1-R5 settle ONE final signature + apply-order per multi-item construct: `DegenerusGame.sol` (R1 `pullRedemptionReserve` coverage branch + R2 renamed crank entrypoints + affiliate code + R3 `sellFarFutureTickets` + inline `claimableWinnings[SDGNRS]` debit), `StakedDegenerusStonk.sol` (R4 `_submitGamblingClaimFrom` + `receive()` + `burnAtGameOver` + interface adds), `DegenerusVault.sol` (R5 affiliate route + `recoverAfKingPool()` + `gameSellFarFutureTickets`). None of items 2/3/4/7 can land as a conflicting independent diff.
2. ✅ **SC2 — every anchor grep-attested; no un-grepped "by construction".** §0: 60 anchors + SWAP economics attested vs `da5c9d50`, 0 blockers; corrections C1-C8 captured; the `DegenerusGame` mint/jackpot inline-duplication precedent re-checked (C2 affiliate site = the game self-call wrapper, not AfKing); POOL-05 confirms the `IAfKing`/`IAfKingSubscribe` `withdraw(uint256)`/`poolOf(address)` adds match `AfKing.sol` verbatim and `AfKing.sol` stays UNCHANGED for item 4.
3. ✅ **SC3 — salvage-swap no-arb floor RE-CONFIRMED at the band ceiling.** §0 SWAP verdict: 16.5% of face @d6 (110% ceiling) < ~21% cheapest acquisition, margin +4.5pp; BURNIE-can't-mint-far confirmed; SWAP-03 jitter pinned to the SETTLED `rngWordByDay[currentDay-1]` (freeze-safe). STOP rule NOT triggered.
4. ✅ **SC4 — every SPEC-time open item resolved.** §2: RFALL-04 (D-06 single value), KEEP-04 (registered `bytes32("DGNRS")`), KEEP-05 (autoOpen EXISTING rename), POOL-06 (D-04 accept-as-minor, no second sweep), BTOMB packing (checked-add/cap, one-shot via `vaultEscrow`), HERO-04 shape (D-01/02/03 + byte-reproduce-gate handoff), S=8/S=9 packing (separate per-N `uint256`).
5. ✅ **SC5 — swap-pop proven NOT H-CANCEL-SWAP-MISS + OPEN-E covers the value-destructive operator action.** §0 + §1 R3/R6 + §2: 11 `ticketQueue` consumers enumerated (`325-ATTEST-SWAP` §D), the O(1) caller-verified swap-pop maintains `membership ⟺ packed != 0` so the far-future samplers gain no hot-path read, and the LOCKED OPEN-E disposition is confirmed to cover the first value-destructive operator-gated action.

**SOURCE-TREE not mutated at SPEC.** Phase 326 applies the single batched diff (HELD at the contract-commit boundary for explicit user hand-review). `git diff --name-only da5c9d50 HEAD -- 'contracts/*.sol'` is EMPTY.
