# 357-01 — v56.0 DELTA AUDIT (the SC1 delta-surface + composition + regression half of AUDIT-01)

**Phase:** 357 — TERMINAL (FULL close) · **Plan:** 357-01 · **Authored:** 2026-06-03
**Requirements:** AUDIT-01 (the delta-audit half; the 3-skill adversarial sweep is 357-02, the findings deliverable is 357-03)
**Audit subject HEAD′′ (FROZEN):** `61315ecd0d617e5ece386676aaf452282331ebdf` — the CURRENT re-frozen v56.0 subject (audited == shipped). Phase 357 has **TWO** contract gates on top of the v55 baseline's v56 IMPL/GAS landing:
- **HEAD′ = `ac5f1e03`** (357-00) — F-356-01 `drainAffiliateBase` dispatch stub + D-11 `NoPass` + D-12 `MustPurchaseToBeginAfking` + D-13 VAULT/SDGNRS subscribe-gate exemption.
- **HEAD′′ = `61315ecd`** (357, the CURRENT subject) — the **advance-incentive redesign** (6-file footprint): `advanceGame()` is now PURE LIVENESS (the `_enforceDailyMintGate` + `MustMintToday` revert + the dead `caller`/`vault`/`IDegenerusVaultOwner` args DELETED); the must-mint tier ladder became the non-reverting SOFT pay-gate `_bountyEligible(address)` in `DegenerusGameMintStreakUtils`; `mintBurnie()` soft-gates the advance bounty on it; NEW `bountyEligible(address) external view`; `DegenerusVault.gameAdvance()` + `StakedDegenerusStonk.gameAdvance()` route through `mintBurnie()`.

**Audit baseline:** the v55.0 closure-frozen subject `453f8073` (closure signal `MILESTONE_V55_AT_HEAD_ca3bbd3220de763298ef2e742111f6e6ef90d583`; the 349.2 IMPL fix was the last v55 `contracts/*.sol` mutation).

**Read-only attestation:** `git diff 61315ecd HEAD -- contracts/` is **EMPTY** (re-verified at the start AND end of this plan — zero `contracts/*.sol` was opened or mutated; the entire delta surface was inspected via `git show 61315ecd:…`, `git diff 453f8073 61315ecd -- contracts/`, and `grep`). The working tree IS at HEAD′′ (clean), so reading the live `contracts/` files == reading the frozen subject. This plan edits ONLY this markdown log.

This mirrors the **v55 Phase 352 §2/§3/§4** delta-surface + composition + regression structure (the 5th repetition of the v48/v49/v55 precedent) so the findings deliverable (357-03) folds this log into its §3/§5. The v55→v56 step is the **AfKing-everyday-gas-minimization batching** (per-sub accumulator + mode-agnostic aggregator + ticket minimal-write primitive + open-end re-verification + the affiliate flat-7% PULL) PLUS the two 357 contract gates — **15 contract files differ** — so the composition matrix is load-bearing and the SOLVENCY-01 / RNG-freeze re-attestation is mandatory.

> **⚠ FRAMING SUPERSESSION (LOAD-BEARING — the as-built COMMITTED reality at HEAD′′, re-grepped @ `61315ecd`).** The plan body (written against HEAD′ and earlier framings) cited a **`5cb707f2` advance-gate active-sub `mustMintToday` bypass (D-04)** as a v56 surface to attest "now-sound post-hardening." **At HEAD′′ that framing is OBSOLETE — the gate it bypassed was DELETED ENTIRELY.** The advance-incentive redesign **REMOVED `_enforceDailyMintGate` + the `MustMintToday` revert + the active-sub fall-through bypass + the `IDegenerusVaultOwner vault` constant + the `caller` arg** from `DegenerusGameAdvanceModule.sol` (`grep -rn MustMintToday contracts/` → **0**). There is no longer a gate to bypass: `advanceGame()` is unconditionally crankable. The must-mint logic relocated to the non-reverting `_bountyEligible(address)` SOFT pay-predicate (`DegenerusGameMintStreakUtils.sol:25`), which only decides whether the keeper EARNS the re-homed BURNIE bounty — never whether the advance WORK runs. This log attests the **advance-incentive redesign** (the superseding HEAD′′ change) in place of the obsolete `5cb707f2` bypass framing; the `5cb707f2` commit is subsumed (its `_enforceDailyMintGate` fall-through is among the lines the redesign DELETED).

---

## 1. The frozen subject + the delta-range provenance (re-derived @ execution time)

| Check | Command | Result |
| --- | --- | --- |
| Frozen subject | `git diff --quiet 61315ecd HEAD -- contracts/` | **EMPTY** (zero contract mutation in this phase) |
| Working tree == subject | `git status --short` | clean (HEAD == `cb918d70`, a docs/test commit; `contracts/` byte-identical to `61315ecd`) |
| Delta magnitude (contracts only) | `git diff --stat 453f8073 61315ecd -- contracts/` | **15 files**, **+1565 / −803** |
| `MustMintToday` removed | `git grep -n 'MustMintToday' 61315ecd -- 'contracts/*.sol'` | **ZERO** (the revert + error deleted by the redesign) |
| `_enforceDailyMintGate` removed | `git grep -n '_enforceDailyMintGate' 61315ecd -- 'contracts/*.sol'` | **ZERO** (the whole private fn + the `IDegenerusVaultOwner vault` constant deleted from AdvanceModule) |
| `_bountyEligible` added | `git grep -n 'function _bountyEligible' 61315ecd -- 'contracts/*.sol'` | **1** (`DegenerusGameMintStreakUtils.sol:25`) |
| `bountyEligible` view added | `git grep -n 'function bountyEligible' 61315ecd -- 'contracts/*.sol'` | **1** (`DegenerusGame.sol:1799`) |
| `drainAffiliateBase` Game stub | `git grep -n 'function drainAffiliateBase' 61315ecd -- contracts/DegenerusGame.sol` | **1** (the F-356-01 fix — the stub that makes `DegenerusAffiliate.claim()` reachable) |

The 15-file delta set is enumerated below exactly as `git diff --numstat 453f8073 61315ecd -- contracts/` reports it (re-derived, NOT trusted from the plan list — the plan's "14-file" count predates the redesign which added `DegenerusGameMintStreakUtils.sol` to the delta and reshaped `DegenerusGameAdvanceModule.sol` / `DegenerusGame.sol`):

| File | +ins | −del | Owning work item(s) |
| --- | --- | --- | --- |
| `storage/DegenerusGameStorage.sol` | 129 | 41 | AGG-05 / GAS-02 (per-sub accumulator re-pack) |
| `modules/GameAfkingModule.sol` | 558 | 268 | AGG-01..05 / QST-01/02/03 / GAS-05 / **mintBurnie soft pay-gate (redesign)** / **D-11/D-12/D-13 (357-00)** |
| `DegenerusQuests.sol` | 320 | 157 | QST-01..05 (batched-settle entrypoint + O1/QST-05 single-credit) |
| `interfaces/IDegenerusQuests.sol` | 29 | 15 | QST (interface wiring) |
| `DegenerusAffiliate.sol` | 108 | 0 | AFF-01/02 (flat-7% deterministic-split PULL `claim`) |
| `interfaces/IDegenerusAffiliate.sol` | 8 | 0 | AFF (interface wiring) |
| `modules/DegenerusGameLootboxModule.sol` | 163 | 188 | TKT-01/02 / OPEN-01/02 / LIVE-01 (ticket minimal-write + open-end + valve) |
| `modules/DegenerusGameAdvanceModule.sol` | 45 | 74 | GAS-05 / LIVE-01 / GAS-06 / **advance-gate REMOVAL (redesign)** |
| `modules/DegenerusGameMintStreakUtils.sol` | 48 | 0 | **`_bountyEligible` SOFT pay-predicate (redesign)** |
| `DegenerusGame.sol` | 90 | 25 | **`bountyEligible` view (redesign)** / **drainAffiliateBase stub (357-00 F-356-01)** / `initPerpetualTickets` (deploy-cap) / wiring |
| `DegenerusVault.sol` | 12 | 3 | **`gameAdvance()`→`mintBurnie()` (redesign)** / `initPerpetualTickets` caller (deploy-cap) |
| `StakedDegenerusStonk.sol` | 12 | 2 | **`gameAdvance()`→`mintBurnie()` (redesign)** / `initPerpetualTickets` caller (deploy-cap) |
| `interfaces/IDegenerusGameModules.sol` | 25 | 12 | interface wiring (the new module ABI) |
| `modules/DegenerusGameWhaleModule.sol` | 3 | 3 | quest-pack discount rebalance (25/50→20/35) |
| `ContractAddresses.sol` | 15 | 15 | deploy-cap address reshuffle (freely-modifiable) |

**15 files, +1565 / −803** — exactly the `git diff --stat 453f8073 61315ecd -- contracts/` set. Every file carries a NON-WIDENING verdict in §2.

---

## 2. §3.A Delta-Surface Table — every changed contract surface attested NON-WIDENING @ `61315ecd`

Grouped by the v56 work-item family. Columns mirror FINDINGS-v49/v55 §3.A: **Surface (file, Δ)** | **Requirements** | **Re-grepped anchors @ `61315ecd`** | **Disposition**.

### Family 1 — Per-sub accumulator re-pack (AGG-05 / GAS-02)

| Surface (file, Δ) | Requirements | Re-grepped anchors @ `61315ecd` | Disposition |
| --- | --- | --- | --- |
| **`contracts/storage/DegenerusGameStorage.sol`** (+129 / −41) | AGG-05 · GAS-02 | The `Sub` slot is re-packed to the batching accumulator shape: `affiliateBase` (the per-sub affiliate accrual drained by `DegenerusAffiliate.claim`), the inline quest-progress fields, `pendingBurnie` (the deferred-payout accumulator), `hasEverSubscribed`, `validThroughLevel`; `amount` migrated to **milli-ETH** units; the v55 per-day window/settled markers DROPPED (the streak now computes on-read from the Sub slot — no per-day settle marker). The `afkingFunding` ledger STILL rides inside `claimablePool` (the SOLVENCY-01 invariant `claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]`, `:247` comment). | **NON-WIDENING** — a layout re-pack on a PRE-LAUNCH (redeploy-fresh) storage base; the `afkingFunding` aggregate is unchanged (rides inside `claimablePool` → inherits the v54/v55-correct solvency wiring); no new reserved aggregate. |

### Family 2 — Mode-agnostic aggregator + GameAfkingModule fold + the redesign soft pay-gate + the 357-00 gates (AGG / QST / GAS-05 + redesign + SEC-01 spine)

| Surface (file, Δ) | Requirements | Re-grepped anchors @ `61315ecd` | Disposition |
| --- | --- | --- | --- |
| **`contracts/modules/GameAfkingModule.sol`** (+558 / −268) | AGG-01..05 · QST-01/02/03 · GAS-05 · (redesign mintBurnie soft-gate) · (357-00 D-11/D-12/D-13) | The mode-agnostic accrue + inline `_settleQuest` (rides the STAGE) + `claimQuest` fallback + unsub-settle + first-sub head-start + the `pendingBurnie` GAS-05 deferred payout. **The SOLVENCY-01 ETH/`claimablePool` debit two-liner is BYTE-IDENTICAL to `453f8073`** (`afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue);` — re-added verbatim at the new helper location `:690-691`, only the surrounding code/comments relocated; the baseline anchor was `:709-710`). **The redesign mintBurnie soft pay-gate** `:982` `bool eligible = _bountyEligible(msg.sender);` read BEFORE the `advanceGame()` self-call (correct pre-advance `dailyIdx`), `:985` `if (mult > 0 && eligible) bountyEarned = unit * ADVANCE_RATIO_NUM * mult;` — the advance WORK runs regardless; the bounty is the only thing gated, and it is BURNIE off the ETH path. **The 357-00 gates** (in audit scope, D-01): the D-11 `NoPass` pass-required + D-12 `MustPurchaseToBeginAfking` purchase-grounded reverts on the subscribe UPSERT branch, both wrapped by the D-13 `subscriber == VAULT \|\| subscriber == SDGNRS` exemption (the un-spoofable resolved identity) — **RESOLVED-AT-357 / SEC-01 spine, NOT orphan hunks**. | **NON-WIDENING** — every entrypoint maps to a v56 work item; the SOLVENCY-01 debit is byte-frozen (BURNIE/quest/affiliate rewards stay OFF the ETH/`claimablePool` path); the redesign soft-gate is MONOTONE (advance always runs, only the BURNIE bounty is gated → strictly removes a free-rider's EARN, never adds a revert); the 357-00 gates are STRICTLY TIGHTER (passless/unfunded subscribes now revert — narrowing the eligible-subscriber set). |
| **`contracts/interfaces/IDegenerusGameModules.sol`** (+25 / −12) | (interface wiring) | The `IGameAfkingModule` signatures track the contract verbatim — `processSubscriberStage(processDay, SUB_STAGE_WEIGHT_BUDGET)`, `drainAffiliateBase`, `mintBurnie`, the accumulator accessors. The interface adds the new module ABI; no surface beyond the fold. | **NON-WIDENING** — interface tracks the new module's external ABI; behavior-attributed to the owning item. |

### Family 3 — DegenerusQuests batched-settle entrypoint + the single-credit fix (QST-01..05)

| Surface (file, Δ) | Requirements | Re-grepped anchors @ `61315ecd` | Disposition |
| --- | --- | --- | --- |
| **`contracts/DegenerusQuests.sol`** (+320 / −157) | QST-01..05 | The batched-settle entrypoint (the afking STAGE settles N subs' quests in one call) + the O1/QST-05 single-credit fix (the LOOTBOX-quest BURNIE reward credited exactly once, no double-credit). `afkingActive` gates the streak bump so the manual/bingo/degenerette/boon callers are byte-identical with afking siblings present vs absent (the QST-04 non-perturbation, proven §3.6). | **NON-WIDENING** — the batched-settle entrypoint is non-perturbing to the shared quest-core callers (proven NON-PERTURB by `V56QuestNonPerturb` 7/7, 356-05); the single-credit fix strictly removes a double-credit (a tightening, not a widening). |
| **`contracts/interfaces/IDegenerusQuests.sol`** (+29 / −15) | QST (interface wiring) | Tracks the `DegenerusQuests` external ABI (the batched-settle entry + the credit-path signatures). | **NON-WIDENING** — interface wiring, behavior-attributed to QST. |

### Family 4 — DegenerusAffiliate flat-7% deterministic-split PULL (AFF-01/02)

| Surface (file, Δ) | Requirements | Re-grepped anchors @ `61315ecd` | Disposition |
| --- | --- | --- | --- |
| **`contracts/DegenerusAffiliate.sol`** (+108 / −0) | AFF-01/02 · AGG-01/04/05 | The flat-7% deterministic-split PULL: `claim(address[] calldata subs)` @ **`:629`** resolves the upline chain ONCE from `subs[0]`; the **buyer-never-wins** comment @ **`:633-634`** ("`A != sub` is guaranteed by the referral layer (self-referral resolves to VAULT), so the 75% leg never skips to a buyer"); the per-sub drain loop @ **`:654`** `uint256 b = afkingDrain.drainAffiliateBase(sub)` (the GAME-routed drain that the 357-00 stub makes reachable); the **75/20/5 split** arithmetic @ **`:678-695`** (`u1Share = ((sumB - skipU1) * 20)/100`, `u2Share = ((sumB - skipU2) * 5)/100`, `aShare = sumB - u1Share - u2Share` — floored with the remainder to A so the parts never exceed `sumB`; the rare U1/U2==sub cycle skip). **NO roll, NO seed, NO scheduled/mutation flush** — exactly ONE deterministic distribution path. CEI: the `affiliateCoinEarned[lvl]` accrual + the pending-claim accumulation, no value transfer in the loop. | **NON-WIDENING** — a PULL `claim` with exactly one deterministic distribution path (no favorable-seed selection AND no two-distribution free option); the buyer never receives the base; the drain is atomic at the storage owner (a duplicate sub drains 0). Proven NON-GAMEABLE by `V56SecUnmanipulable` 11/11 churn-fuzz (356-03). The 357-00 stub makes `claim()` REACHABLE; the CEI is unchanged. |
| **`contracts/interfaces/IDegenerusAffiliate.sol`** (+8 / −0) | AFF (interface wiring) | Tracks the `claim`/`payAffiliate` external ABI. | **NON-WIDENING** — interface wiring. |

### Family 5 — Ticket minimal-write primitive + open-end + LIVE-01 valve (TKT / OPEN / LIVE-01)

| Surface (file, Δ) | Requirements | Re-grepped anchors @ `61315ecd` | Disposition |
| --- | --- | --- | --- |
| **`contracts/modules/DegenerusGameLootboxModule.sol`** (+163 / −188) | TKT-01/02 · OPEN-01/02 · LIVE-01 | The ticket minimal-write primitive (queue resolution-equivalent ticket entries with one warm Sub-stamp write, the `buyerOwedBurnie` 10%/20% accrual folded into `pendingBurnie`) + the century-day (x00-level) quantity-bonus parity + the open-end re-verification (afking open ≡ human `openLootBox` at the same LIVE level, `lastOpenedDay` monotone no-double-open) + the LIVE-01 `openBoxes` unified valve leg (`86a2d6c8`: afking-first then human, both cursors drain). The afking open materializes from the Sub stamp + `rngWordByDay[lastAutoBoughtDay]`, math byte-identical to `openLootBox`. | **NON-WIDENING** — the afking open re-uses the existing draw math (the differential oracle proves byte-identical traits at the same live level); the minimal-write primitive only changes the WRITE shape (cold ledger → warm Sub stamp), not the economic outcome; the valve is afking-then-human with isolated cursors (no double-draw on the shared `(player,level)` budget). Proven by `V56AfkingGasMarginal` LIVE-01 cases (356-06). |

### Family 6 — GAS-05 weighted budget + advance-gate REMOVAL + LIVE-01 valve + GAS-06 decouple (GAS-05 / LIVE-01 / GAS-06 + redesign)

| Surface (file, Δ) | Requirements | Re-grepped anchors @ `61315ecd` | Disposition |
| --- | --- | --- | --- |
| **`contracts/modules/DegenerusGameAdvanceModule.sol`** (+45 / −74) | GAS-05 · LIVE-01 · GAS-06 · (redesign advance-gate removal) | **The advance-gate REMOVAL (the redesign — supersedes the obsolete `5cb707f2` bypass framing):** the `IDegenerusVaultOwner` interface, the `MustMintToday` error, the `IDegenerusVaultOwner vault` constant, the `_enforceDailyMintGate(caller, purchaseLevel, dailyIdx)` call site, the entire `_enforceDailyMintGate` private fn (~45 lines), and the `address caller = msg.sender;` capture are ALL DELETED (`-74` lines dominate this file's delta). `advanceGame()` is now unconditionally crankable (reverts only `NotTimeYet()` for ordinary game-state reasons, NEVER a mint gate). **GAS-05:** the per-call STAGE budget is the gas-WEIGHT `SUB_STAGE_WEIGHT_BUDGET` (1000) replacing the v55 count-based `SUB_STAGE_BATCH` (50) — buys weighted by true cost (lootbox≈1, ticket≈8, evict≈2), ending the chunk on accumulated weight so the worst-case chunk stays under 16.7M while a normal chunk targets <10M. **GAS-06:** the `STAGE_GAP_BACKFILLED` (12) decouple — a multi-day VRF-stall gap backfill defers the day's jackpot to the next advance (`if (gapDays != 0) { stage = STAGE_GAP_BACKFILLED; break; }`, `:351`) so the backfill + jackpot never share one tx; `rngGate` is idempotent on re-entry. | **NON-WIDENING** — the advance-gate REMOVAL is a LIVENESS change that DELETES a view-only revert (strictly removes a way `advanceGame()` could fail; adds no new state, no new entropy, no new external call on the advance path); the RNG-request path is unchanged apart from dropping the entry gate (§3.7). GAS-05 weight-budget and GAS-06 decouple are per-tx gas-ceiling-honoring tunes (proven by `V56AfkingGasMarginal` gap-resume + per-tx, 356-06). |

### Family 7 — The advance-incentive soft pay-predicate (redesign — the must-mint relocation)

| Surface (file, Δ) | Requirements | Re-grepped anchors @ `61315ecd` | Disposition |
| --- | --- | --- | --- |
| **`contracts/modules/DegenerusGameMintStreakUtils.sol`** (+48 / −0) | (redesign — the `_bountyEligible` soft pay-predicate) | NEW `interface IDegenerusVaultOwner` (the cold-path DGVE tier) + NEW `function _bountyEligible(address who) internal view returns (bool)` @ **`:25`** — the SOFT pay-gate the must-mint ladder relocated into. Tiers, cheapest-first short-circuit: `gateIdx == 0` first-day → `true`; minted today/yesterday (`lastEthDay + 1 >= gateIdx`) → `true`; deity pass → `true`; anyone 30+ min into the day (`elapsed >= 30 minutes`) → `true`; any pass holder 15+ min in (`frozenUntilLevel > level`) → `true`; active afking sub (`_subOf[who].dailyQuantity != 0`) → `true`; finally `IDegenerusVaultOwner(VAULT).isVaultOwner(who)` (the ONLY external call, cold path). It NEVER reverts — it returns a bool that gates only the BURNIE bounty in `mintBurnie`. | **NON-WIDENING** — a pure-add NON-REVERTING view predicate; it gates BURNIE-bounty EARN only (off the ETH/solvency path), so it cannot widen any value-bearing surface; the tier ladder is the same logic the deleted `_enforceDailyMintGate` enforced, minus the revert (the active-afking-sub tier is NEW — it correctly recognizes daily auto-buy participation that never stamps `DAY_SHIFT`). |

### Family 8 — DegenerusGame: the redesign view + the F-356-01 stub + deploy-cap + wiring

| Surface (file, Δ) | Requirements | Re-grepped anchors @ `61315ecd` | Disposition |
| --- | --- | --- | --- |
| **`contracts/DegenerusGame.sol`** (+90 / −25) | (redesign `bountyEligible` view) · (357-00 **F-356-01** drainAffiliateBase stub) · (deploy-cap `initPerpetualTickets`) · wiring | **The redesign `bountyEligible(address who) external view returns (bool)` @ `:1799`** (`return _bountyEligible(who);`) — the off-chain pre-check + test oracle. **The 357-00 F-356-01 fix @ `:222`-region** `function drainAffiliateBase(address sub) external returns (uint256)` — the guard-less delegatecall to `GAME_AFKING_MODULE` (mirrors `claimAfkingBurnie`), `_revertDelegate` on fail, `data.length == 0` guard, `abi.decode(data, (uint256))` return tail (mirrors `runDecimatorJackpot`); the module impl owns the AFFILIATE-only access gate. **`initPerpetualTickets() external` @ `:222`** — the perpetual-ticket queue moved OUT of the GAME constructor (so GAME's deploy stays under the EIP-7825 per-tx gas cap), called once each by VAULT/SDGNRS. Plus thin wiring churn. | **NON-WIDENING** — `bountyEligible` is a read-only view (no state); the F-356-01 stub is a STRICTLY-ENABLING dispatch fix (`DegenerusAffiliate.claim()` was reverting on the live contract; the stub makes the already-designed affiliate-base settlement reachable — the access gate is in the module impl, the dispatch is guard-less like `claimAfkingBurnie`) → **RESOLVED-AT-357**, NOT orphan; `initPerpetualTickets` is a constructor-to-init relocation (deploy-cap, behavior-identical). |
| **`contracts/DegenerusVault.sol`** (+12 / −3) | (redesign `gameAdvance`→`mintBurnie`) · (deploy-cap `initPerpetualTickets` caller) | `gameAdvance() external onlyVaultOwner` now calls `gamePlayer.mintBurnie()` (was `advanceGame()`) — the vault earns the keeper bounty for the work, reverts `NoWork()` when idle; `onlyVaultOwner` (DGVE-majority) gate UNCHANGED. The constructor self-subscribe now also calls `gamePlayer.initPerpetualTickets()` (deploy-cap relocation). | **NON-WIDENING** — same caller authority (`onlyVaultOwner`); routing `advanceGame`→`mintBurnie` only changes WHICH crank entrypoint the owner hits (both advance the game; `mintBurnie` additionally pays the earned bounty + opens boxes); the vault holds a deity pass + afking sub so it is always bounty-eligible. STRICTLY TIGHTER on the no-op path (`NoWork()` revert when idle). |
| **`contracts/StakedDegenerusStonk.sol`** (+12 / −2) | (redesign `gameAdvance`→`mintBurnie`) · (deploy-cap `initPerpetualTickets` caller) | `gameAdvance() external` (permissionless) now calls `game.mintBurnie()` (was `advanceGame()`); reverts `NoWork()` when idle. The constructor self-subscribe now also calls `game.initPerpetualTickets()`. | **NON-WIDENING** — permissionless either way; `advanceGame`→`mintBurnie` routes through the unified keeper router (earns the bounty); sDGNRS holds a deity pass + afking sub → always bounty-eligible. STRICTLY TIGHTER on idle (`NoWork()`). |

### Family 9 — Quest-pack discount rebalance + deploy-cap address reshuffle (wiring)

| Surface (file, Δ) | Requirements | Re-grepped anchors @ `61315ecd` | Disposition |
| --- | --- | --- | --- |
| **`contracts/modules/DegenerusGameWhaleModule.sol`** (+3 / −3) | (quest-pack discount rebalance) | The whale/deity discount-boon tiers rebalanced **25/50 → 20/35** (`boonTier == 2 ? 2000 : (tier 3 → 3500)`; was `2500`/`5000` bps) — the `e2590c1c` quest-pack/deploy-cap follow-up folded into the v56 contract tree. A parameter-value change on the existing discount path. | **NON-WIDENING** — a discount-tier parameter rebalance (the boon mechanism is unchanged; the bps values shifted); no new surface, no new emission. |
| **`contracts/ContractAddresses.sol`** (+15 / −15) | (deploy-cap address reshuffle) | The deployed-address constants reshuffled (the deploy-cap re-ordering); freely-modifiable per project policy. No symbol added/removed beyond the address rebind. | **NON-WIDENING** — an address-constant reshuffle (deploy-time wiring; no behavioral surface). |

**Per-file delta accounted: 1 (F1) + 2 (F2) + 2 (F3) + 2 (F4) + 1 (F5) + 1 (F6) + 1 (F7) + 3 (F8) + 2 (F9) = 15 files** — exactly the `git diff --numstat 453f8073 61315ecd -- contracts/` set (+1565 / −803). **Every file carries a NON-WIDENING verdict backed by a concrete grep/diff anchor @ `61315ecd`, mapped to its owning v56 work item.**

---

## 3. §3.B Composition Attestation Matrix

### 3.1 No orphan hunks — every `contracts/` delta hunk maps to exactly ONE v56 work item

The +1565 / −803 delta decomposes into nine v56 work-item families with **ZERO orphan hunks**:

| Work item (family) | Surfaces | Net intent |
| --- | --- | --- |
| **per-sub accumulator re-pack** (AGG-05/GAS-02) | `DegenerusGameStorage.sol` | `affiliateBase`/quest-progress/`pendingBurnie`/`hasEverSubscribed`/`validThroughLevel`; `amount`→milli-ETH; window/settled markers dropped |
| **mode-agnostic aggregator + GameAfkingModule fold** (AGG-01..05/QST-01/02/03/GAS-05) | `GameAfkingModule.sol`, `IDegenerusGameModules.sol` | accrue + inline `_settleQuest` + `claimQuest` fallback + unsub-settle + first-sub head-start + the `pendingBurnie` deferred payout |
| **DegenerusQuests batched-settle** (QST-01..05) | `DegenerusQuests.sol`, `IDegenerusQuests.sol` | the batched-settle entrypoint (non-perturbing) + the O1/QST-05 single-credit fix |
| **affiliate flat-7% PULL** (AFF-01/02) | `DegenerusAffiliate.sol`, `IDegenerusAffiliate.sol` | `claim(subs[])` 75/20/5 deterministic split + CEI + pending-claim; no roll/seed |
| **ticket minimal-write + open-end + valve** (TKT-01/02/OPEN-01/02/LIVE-01) | `DegenerusGameLootboxModule.sol` | minimal-write primitive + `buyerOwedBurnie`→`pendingBurnie` + century parity + open re-verify + the `openBoxes` valve leg |
| **GAS-05 weighted budget + advance-gate REMOVAL + GAS-06 decouple** (GAS-05/LIVE-01/GAS-06 + redesign) | `DegenerusGameAdvanceModule.sol` | the weight-budget STAGE + the `MustMintToday`/`_enforceDailyMintGate` REMOVAL + the gap/jackpot decouple |
| **advance-incentive soft pay-predicate** (redesign) | `DegenerusGameMintStreakUtils.sol` | NEW `_bountyEligible(address)` — the non-reverting must-mint relocation |
| **DegenerusGame redesign view + F-356-01 stub + deploy-cap + redesign routing** (redesign / F-356-01 / deploy-cap) | `DegenerusGame.sol`, `DegenerusVault.sol`, `StakedDegenerusStonk.sol` | `bountyEligible` view + the `drainAffiliateBase` stub + `initPerpetualTickets` + `gameAdvance`→`mintBurnie` |
| **quest-pack rebalance + address reshuffle** (wiring) | `DegenerusGameWhaleModule.sol`, `ContractAddresses.sol` | 25/50→20/35 discount tiers + the deploy-cap address reshuffle |

**The advance-incentive redesign is the dominant HEAD′′ work item** and supersedes the plan's obsolete `5cb707f2` bypass framing (§ FRAMING SUPERSESSION banner). Its hunks span FOUR files and ALL map cleanly:
- `DegenerusGameAdvanceModule.sol` — the gate DELETION (`-74` lines: the error, the interface, the `vault` constant, the call site, the whole `_enforceDailyMintGate` fn, the `caller` capture).
- `DegenerusGameMintStreakUtils.sol` — the `_bountyEligible` non-reverting soft pay-predicate (`+48`).
- `GameAfkingModule.sol` — the `mintBurnie` soft-gate (read `_bountyEligible` pre-advance, pay `if (mult > 0 && eligible)`).
- `DegenerusGame.sol` / `DegenerusVault.sol` / `StakedDegenerusStonk.sol` — the `bountyEligible` view + the `gameAdvance`→`mintBurnie` routing.

**The 357-00 F-356-01 stub + D-11/D-12/D-13 gates** (the FIRST 357 gate, HEAD′) are attributed RESOLVED-AT-357 / SEC-01 spine (Families 2 + 8), NOT orphan hunks. **ZERO orphan hunks** — the v56 surface widens NOTHING beyond the nine work-item families.

### 3.2 SOLVENCY-01 byte-unchanged (SEC-02) — re-attested at HEAD′′

The master inequality `balance + steth.balanceOf(this) >= claimablePool` (inclusive of the afking total) is carried from Phase 343 as a discharged foundation. **The SOLVENCY-01 leg-1 ETH/`claimablePool` debit two-liner is BYTE-IDENTICAL between `453f8073` and HEAD′′:**

```solidity
afkingFunding[src] -= ethValue;
claimablePool -= uint128(ethValue);
```

at `453f8073:709-710` ↔ HEAD′′ `GameAfkingModule.sol:690-691` (re-verified by `git show` on both HEADs — the two statements are byte-identical modulo indentation; the v56 refactor hoisted them into a helper, less-indented, but the economic statements are unchanged). The `afkingFunding` mutation moves `claimablePool` in tandem (the `:247` INVARIANT comment), so the master inequality is structurally unchanged.

**The two 357 gates do NOT touch the debit:**
- **The 357-00 changes are BURNIE-only + revert-only:** the `drainAffiliateBase` stub drains a BURNIE-flip-credit accumulator (`affiliateBase`), and the D-11/D-12 gates are pre-UPSERT REVERTS — neither writes the ETH/`claimablePool` debit.
- **The advance-incentive redesign is liveness-only + BURNIE-bounty-only:** `advanceGame()` drops a VIEW-ONLY revert (`_enforceDailyMintGate` was `private view`, no state write); `mintBurnie`'s soft-gate pays a BURNIE bounty (`coinflip.creditFlip`), off the ETH/`claimablePool` path. No ETH/`claimablePool` debit change.

Cross-ref `V56FreezeSolvency` 7/7 (356-04, the solvency-invariant fuzz `balance + steth.balanceOf(this) >= claimablePool` + the leg-1 debit-equals-delivered-value forge arm). **SOLVENCY-01 HELD NET — byte-unchanged at HEAD′′.**

### 3.3 RNG-freeze intact (SEC-02) — the v45 north-star re-attested at HEAD′′

Per `[[v45-vrf-freeze-invariant]]`: re-attested INTACT — **no in-window SLOAD a player can manipulate between rng-request and unlock**. The v56 accrue/settle + the open-end materialization touch no frozen RNG-window slot (the open consumes only the stamped seed + the LIVE level, the same posture v55 proved); the per-sub accumulator re-pack is in-context SLOADs of appended/repacked storage, not new entropy-window levers.

**The advance-incentive redesign "premature-advance" liveness change touches NO frozen RNG-window slot:** removing `_enforceDailyMintGate` does NOT change `advanceGame()`'s RNG-request path — the `rngGate`/`requestLootboxRng`/`_unlockRng` sequence, the `rngWordByDay[day]` write, and the `STAGE_GAP_BACKFILLED` idempotent re-entry are all unchanged apart from dropping the (view-only) entry gate. An attacker who can now crank `advanceGame()` earlier (no mint requirement) gains NO control over the VRF input (the player cannot manipulate the VRF word after the request; the daily-advance path is the normal path the v45 invariant exempts). The GAS-06 decouple even STRENGTHENS the window discipline (the backfill and jackpot never share a tx). Cross-ref `V56FreezeSolvency` RNG-freeze determinism fuzz (356-04). **Composition verdict: RNG-freeze NON-WIDENING.**

### 3.4 The affiliate flat-7% deterministic-split-PULL non-gameability (AFF-01/02) — re-attested on the CORRECTED anchors

Re-anchored on the CORRECTED `DegenerusAffiliate.sol` lines @ HEAD′′ (the 357-PATTERNS DRIFT NOTE — CONTEXT's stale `:579` is superseded):
- **`claim(address[] calldata subs)` entry @ `:629`** — resolves the upline chain ONCE from `subs[0]`.
- **buyer-never-wins @ `:633-634`** — "`A != sub` is guaranteed by the referral layer (self-referral resolves to VAULT), so the 75% leg never skips to a buyer."
- **the per-sub drain loop @ `:654`** — `uint256 b = afkingDrain.drainAffiliateBase(sub)` (the GAME-routed atomic drain; a duplicate sub drains 0).
- **the 75/20/5 split @ `:678-695`** — floored with the remainder to A so the parts never exceed `sumB`; the rare U1/U2==sub cycle skip.

**NO roll, NO seed, NO scheduled/mutation flush** — exactly ONE deterministic distribution path → no favorable-seed selection AND no two-distribution free option. The buyer never receives the base (`A != sub` guaranteed + the U1/U2==sub cycle skip), so no settle-timing profit. The F-356-01 stub now makes `claim()` REACHABLE (the GAME-layer `drainAffiliateBase` dispatch that was missing); the CEI is unchanged. Cross-ref `V56SecUnmanipulable` 11/11 churn-fuzz (356-03, the storage-level `affiliateBase` byte-identity across unsub AND re-sub + the AFFILIATE-only access gate + the bounded realizable BURNIE pull). **Affiliate PULL non-gameability: NON-WIDENING.**

### 3.5 The open-end two-path / no-double-open + LIVE-01 valve + GAS-06 decouple — re-attested

- **OPEN-02 two-path / no-double-open — HOLD.** The afking open vs human `openLootBox` coexist; `lastOpenedDay` monotone (no-double-open); no EV-cap double-draw on the shared `(player,level)` budget (the EV RMW happens once, at open). Proven by `V56AfkingGasMarginal` LIVE-01 cases (356-06).
- **LIVE-01 `openBoxes` valve — HOLD.** `86a2d6c8`: the unified valve opens afking-first then human, both cursors drain, with `drainAfkingBoxes` selector isolation; the individual/`mintBurnie` open is byte-unchanged. Proven by `V56AfkingGasMarginal` LIVE-01 (356-06).
- **GAS-06 gap/jackpot decouple — HOLD.** `3d969621`: each `advanceGame` tx < 16,777,216 under a multi-day VRF-stall resume (gap-backfill advance N ≈ 6.85M + deferred-jackpot N+1 SEPARATE tx); the idempotent-resume invariants (D-07). The `STAGE_GAP_BACKFILLED` (12) break path (`AdvanceModule.sol:351`) is the structural closure. Proven by `V56AfkingGasMarginal` gap-resume (356-06).

### 3.6 The shared-DegenerusQuests-core non-perturbation (QST-04) — re-attested

The batched-settle entrypoint is non-perturbing to the manual/bingo/degenerette/boon callers: `afkingActive` gates the streak bump; byte-identity with afking siblings present vs absent; the O1/QST-05 single-credit fix removes the LOOTBOX-quest double-credit. Proven by `V56QuestNonPerturb` 7/7 (356-05). **Non-perturbation: HOLD.**

### 3.7 The advance-incentive redesign soft-gate — MONOTONE, off the ETH path (replacing the obsolete `5cb707f2` bypass attestation)

The plan asked to attest the `5cb707f2` advance-gate active-sub bypass "now-sound post-hardening." **At HEAD′′ there is no gate to bypass** — the redesign DELETED `_enforceDailyMintGate` + `MustMintToday` entirely (§2 Family 6). The correct HEAD′′ attestation is the redesign itself:

- **The soft-gate is MONOTONE.** `advanceGame()` ALWAYS runs the advance work — `_bountyEligible` returns a bool that gates ONLY the BURNIE bounty in `mintBurnie` (`if (mult > 0 && eligible)`). There is no path where eligibility blocks the advance. Removing the old hard revert strictly REMOVES a way the crank could fail; it adds no new revert, no new state, no new entropy.
- **The bounty is off the ETH/solvency path.** The bounty is `unit * ADVANCE_RATIO_NUM * mult` paid via `creditFlip` (BURNIE), never an ETH/`claimablePool` debit (§3.2). So even if an "unfunded free-rider" earned the bounty, it could not breach SOLVENCY-01.
- **The free-rider concern the `5cb707f2` framing raised is moot at HEAD′′ AND further mitigated by the 357-00 gates.** Pre-redesign, the concern was an active-sub fall-through claiming an advance-TIMING edge. At HEAD′′: (a) there is no timing GATE — anyone advances any time, so no edge exists to claim; (b) the bounty's active-afking-sub tier (`_subOf[who].dailyQuantity != 0`) correctly recognizes genuine daily-auto-buy participation, and the D-11/D-12 gates (357-00) guarantee every active sub is a pass-holding, purchase-grounded participant — so even the bounty tier is not claimable by an unfunded free-rider; (c) the D-13 VAULT/sDGNRS exemption does not reopen one (they advance via their own `gameAdvance`→`mintBurnie` paths and hold deity passes → legitimately eligible). **The redesign is NON-WIDENING:** it converts a hard liveness-revert into a soft BURNIE-bounty gate, strictly improving liveness while keeping the participation-priority intent on a value-neutral (BURNIE) lever.

---

## 4. Regression-Baseline Attestation (the §5 LEAN Regression Appendix, mirroring FINDINGS-v55 §5)

**AUTHORITATIVE SOURCE — cite, do NOT re-run forge or re-derive:** `test/REGRESSION-BASELINE-v56.md` §9 (the 357-00b reconciliation at HEAD′′). The whole-tree `forge test` run at HEAD′′ `61315ecd` was **567 passed / 133 failed / 99 skipped** (799 total, default profile, WHOLE tree). This section folds that ledger; the binding gate, the empirical baseline derivation, the rewrite/drop attribution, and the HEAD′′ narrowing are recorded below exactly as the ledger §9 established them.

### §4a Suite Baseline — 567 / 133 / 99, NON-WIDENING BY NAME vs the `453f8073` baseline

| Quantity | `453f8073` baseline (§2, empirical via `83a6a9ca`) | v56 corpus delta (356-01..07 + 357-00/00b) | HEAD′′ `61315ecd` |
| --- | --- | --- | --- |
| `forge test` passed | 603 | +the adapted-green corpus + the v56 proof files | **567** |
| `forge test` failed | 134 | −1 (the HEAD′′ narrowing — run-variance) | **133** |
| `forge test` skipped | 16 | +the 356-07/357-00b drops + carried `RngLockDeterminism` | **99** |

### §4b The BINDING gate — a failing-NAME-set strict SUBSET (`live − union == ∅`), NOT a count delta

**NON-WIDENING = a strict failing-NAME-set SUBSET**, NOT a count match. The binding, load-bearing gate is stated as a **SUBSET relation** (`live ⊆ union`, BY NAME):

> **`HEAD′′ live failing set (133 names) − the empirical 453f8073 §2 134-name union == ∅`** (0 names outside the baseline) → **net-zero NEW regression.**

The ledger §9b verified this empirically at HEAD′′: the 133 failing forge NAMEs are a STRICT SUBSET of the §2 134-name `453f8073` union (the set-diff `live − union` is EMPTY — `forge` log at `/tmp/ft357.log`). **ZERO new forge red was introduced by the advance-incentive redesign.** The gate is the NAME-set membership test, not "133 down from 134."

### §4c The `453f8073` baseline was established EMPIRICALLY (the strongest non-widening position)

The `453f8073` baseline red union was established EMPIRICALLY (the raw `453f8073` corpus is UNCOMPILABLE — `AfKing.sol` was deleted at v55 but `DeployProtocol` + 5 files still reference its deploy API). The ledger §2 used the **byte-identical-contracts commit `83a6a9ca`** (the commit that authored `REGRESSION-BASELINE-v55.md`, whose contract tree is byte-identical to `453f8073` — `git diff 453f8073 83a6a9ca -- contracts/` EMPTY, verified), `node scripts/lib/patchForFoundry.js` + the WHOLE-tree `forge test --json`, parsing the `--json` failing set → **603 passed / 134 failed / 16 skipped**, the 134-name union. This is the STRONGEST possible non-widening position (the empirically-derived ceiling).

### §4d The test-surface churn is ATTRIBUTED via the ledger, NOT counted as regression

- **The 14 migration-unmasked v56-behavior reds** (`vm.skip`-dropped at 356-07 `f23b010e`, BY NAME + reason, each re-proven GREEN by `V56Sec*`/`V56FreezeSolvency`/`V56QuestNonPerturb`/`V56AfkingGasMarginal`) — adapted-out, NOT new reds.
- **The D-10 offset-migration red→green NARROWING** (the v55 Sub-layout garbage-read reds, fixed by re-pointing the harness slot offsets to the v56 Sub slot) — a narrowing, the opposite of a regression.
- **The NEW 357-00b reconciliation drops** (the D-11/D-12 supersession reds `vm.skip`-dropped, naming `NoPass`/`MustPurchaseToBeginAfking`, each re-proven GREEN by `V56SubHardening`; the F-356-01 narrowing — the `drainAffiliateBase` drain is now a GREEN reachability proof) — behavior-supersession, NOT new reds.
- **The HEAD′′ 1-red NARROWING (133 vs the HEAD′ 134) is run-variance, NOT a deterministic gate-freed forge fixture.** The removed `MustMintToday` hard-revert had a SINGLE consumer — the Hardhat `GovernanceGating` GATE-01..04 block (a unit test, NOT in the forge tree / NOT in the §2 forge union), which 357-00b rewrote to the soft pay-gate model (§9e). No forge `.t.sol` ever asserted the revert (`grep -rln MustMintToday test/ --include='*.t.sol'` → only the NEW `V56SubHardening`, which asserts it does NOT revert). The `union − live` slack is entirely Bucket A (VRF/RNG-window) + Bucket F (`invariant_solvencyUnderDegenerette`, flaky) + the `vm.assume`-exhaustion fuzzer + the `testFuzz_MintDiv_*` differential — all members the §4 ⊆-gate rationale accounts for as fuzz/invariant-campaign variance. The redesign touches no VRF/RNG-window code, so it cannot have deterministically narrowed any Bucket-A red.

### §4e SWEEP NON-WIDENING attestation

Every `git diff 453f8073 61315ecd -- contracts/ test/` hunk is attributable to a known v56-scope commit:
- the **354 IMPL `e18af451`** (the batching contract diff) + the **355 GAS net tune** + the **liveness adds `86a2d6c8` (LIVE-01 valve) / `3d969621` (GAS-06 decouple)** + the **quest-pack/deploy-cap `e2590c1c`** (the whale-module discount rebalance + the address reshuffle + `initPerpetualTickets`) + the **AGENT-committed 356 TST work** (the rewrite map, the 4 v56 proof files, the D-10 migration, `test/REGRESSION-BASELINE-v56.md` itself) + the **357-00 hardening `ac5f1e03`** (F-356-01 stub + D-11/D-12/D-13) + the **advance-incentive redesign `61315ecd`** (the gate removal + `_bountyEligible` + the mintBurnie soft-gate + the `bountyEligible` view + the Vault/sDGNRS routing) + the **357-00b reconciliation** (`056e78c8`/`1d5fd872`/`48fab561` — the GovernanceGating rewrite + the `V56SubHardening` soft-gate proofs + the §9 ledger reconcile).

`git diff 61315ecd HEAD -- contracts/` is **EMPTY** (zero contract mutation in this terminal phase; subject byte-frozen at HEAD′′). **The SOLVENCY-01 leg-1 byte anchor (`453f8073:709-710` ↔ HEAD′′ `:690-691`, byte-identical) holds at HEAD′′** (§3.2, ledger §7a re-confirmed at §9). **NON-WIDENING confirmed.**

### §4f Hardhat sanity arm (Foundry is the primary BY-NAME ledger; Hardhat is the sanity check)

The Hardhat `GovernanceGating` GATE-01..04 block — the ONLY `MustMintToday` consumer — was rewritten to the soft pay-gate model in 357-00b (`056e78c8`): GATE-01 a same-day minter is `bountyEligible` AND advances; GATE-02 the 30-min window flips a non-minter eligible while the advance always works; GATE-03 the DGVE majority holder is always eligible; GATE-04 an ineligible keeper earns no bounty but the advance still runs. 6/6 GATE tests GREEN. (One unrelated pre-existing `ADMIN-02` red — a stale `gameSetAutoRebuy` fixture — is a Hardhat-only scope-boundary item, NOT part of the forge NON-WIDENING ledger.) The Foundry whole-tree run (§4a–§4e) is the authoritative regression ledger.

---

## 5. Self-Check — PASSED

- **Deliverable present:** `.planning/phases/357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw/357-01-DELTA-AUDIT.md` — FOUND.
- **Cited authoritative source present:** `test/REGRESSION-BASELINE-v56.md` (§9 reconciled at HEAD′′) — FOUND (not re-derived; folded into §4).
- **Frozen-subject invariant:** `git diff --quiet 61315ecd HEAD -- contracts/` — **EMPTY** (zero contract mutation; re-asserted after each task).
- **Framing-supersession scan:** the obsolete `5cb707f2` "now-sound bypass" attestation is REPLACED by the advance-incentive redesign attestation (§ FRAMING SUPERSESSION banner + §2 Family 6 + §3.7); `MustMintToday`/`_enforceDailyMintGate` confirmed grep-ZERO at HEAD′′.
- **Affiliate anchors:** the CORRECTED `:629`/`:633-634`/`:654`/`:678-695` lines used (no stale `:579`/`:558` citation), re-grepped at HEAD′′.
- **Delta enumeration:** the 15-file set re-derived from `git diff --numstat 453f8073 61315ecd -- contracts/`; every file carries a NON-WIDENING verdict + a concrete grep/diff anchor @ `61315ecd`, mapped to its owning v56 work item; ZERO orphan hunks.
- **Read-only:** the entire delta surface was inspected via `git show 61315ecd:…` / `git diff 453f8073 61315ecd` / `grep` — no `contracts/*.sol` was opened or mutated; this plan edits ONLY this markdown log.

**SC1 delta-audit half of AUDIT-01: SATISFIED.** (The 3-skill genuine-PARALLEL adversarial sweep is 357-02; the `audit/FINDINGS-v56.0.md` deliverable that folds this log into its §3/§5 is 357-03; the closure flip + the OPEN-E blocking adjudication are 357-04.)
