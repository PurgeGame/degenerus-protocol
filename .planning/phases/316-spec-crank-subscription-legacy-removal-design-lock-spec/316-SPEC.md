# Phase 316 SPEC — Crank + Subscription + Legacy-Removal Design Lock

**Milestone:** v46.0 — Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal
**Phase type:** SPEC / design-lock (read-only — zero `contracts/` and zero `test/` mutations; this phase only reads source to grep-verify file:line claims and writes this markdown).
**Audit baseline → subject:** v45.0 closure HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` → v46.0 closure HEAD.
**Load-bearing inputs:** `316-RESEARCH.md` (grep/forge-verified call-graph substrate) + `PLAN-CRANK-DO-WORK-INCENTIVE.md` (ADD half) + `PLAN-V47-REMOVE-AFKING-ETH-AUTOREBUY.md` (REMOVE half) + `REQUIREMENTS.md` (42 v46.0 reqs).

This SPEC is authored across the Phase 316 plans:
- **316-01 (this plan's sections):** the ADD-half design lock — `## ADD Design — Do-Work Crank`, `## ADD Design — Subscription Sweep & Authorization`, `## PROTO Additions`.
- **316-02:** REMOVE footprint + reconciliation + the JGAS jackpot-split-removal decision gate.
- **316-03:** open-item resolution (OPEN-B/OPEN-C/denomination/whale-expiry/skip-kill identity/SUB-09 init configs).
- **316-04:** call-graph attestation (this RESEARCH.md's §1 verification table; zero unverified "by construction" claims).

**Citation discipline (SC#5):** every `file:line` cited in the 316-01 sections below was re-grep-verified against HEAD on 2026-05-23 before authoring. Two short-hand / drift notes carried forward from `316-RESEARCH.md`: (a) the Degenerette module's canonical filename is `contracts/modules/DegenerusGameDegeneretteModule.sol` (research/PLAN short-hand it as `DegeneretteModule.sol`); (b) the `_distributePayout` frozen-pool solvency check is at `~738` inside the body — `PLAN-CRANK §8`'s "742" is an interior offset (decl at `:705`). No design claim below rests on an un-verified anchor.

---

## ADD Design — Do-Work Crank

The do-work crank is a permissionless layer letting any caller settle pending game work on others' behalf and earn a small gas-pegged BURNIE reward as coinflip stake credit (deferred mint). It runs as in-game function(s) on `DegenerusGame` (Deliverable A), because resolution *writes* game storage (`degeneretteBets`, `lootboxEth`, prize pools, `claimableWinnings`, `mintPacked_`) — direct SLOAD/SSTORE, no cross-contract overhead; a separate contract is structurally impossible for the resolve path.

### Do-work entry signatures + work-type encoding (CRANK-01..04)

**Two work-types resolve through two distinct batching models** — caller-list for bets, parameterless cursor for boxes (the OPEN-D resolution; bet-cursor deferred per `REQUIREMENTS.md` Deferred/Future):

- **Degenerette bets = caller-supplied off-chain-discovered `(player, ids)` work lists (CRANK-01/CRANK-02).** The frontend discovers resolvable bets off-chain (no on-chain enumeration → no unbounded-loop DoS) and supplies grouped `(player, betId[])` lists. Calldata is grouped by player (`address player` + a homogeneous `uint64[]`/`uint48[]` id array per work-type) so `level`/`mintPrice` and the per-player gates are read once per group. Resolution reuses `resolveDegeneretteBets` (`DegenerusGame.sol:743`) / `resolveBets` (`DegenerusGameDegeneretteModule.sol:389`) machinery; the `_requireApproved` gate (`DegenerusGame.sol:452`, `DegenerusGameDegeneretteModule.sol:131`) is **relaxed for the resolve path only** — placement stays gated (mirrors `_resolvePlayer` at `DegenerusGame.sol:458` / module `:141`). Owner self-resolve via `resolveBets(player, betIds)` (module `:389`) is the distinct, zero-collision base case winners use; the crank's caller-list is the cross-player tail for the bounty.

- **`BatchAlreadyTaken` collision short-circuit (CRANK-02).** The caller-list path resolves front-to-back. It checks item 0 first: if `list[0]` is already resolved (`degeneretteBets[player₀][betId₀] == 0` — the bet `delete` happens at `DegenerusGameDegeneretteModule.sol:580`) → **revert immediately with `BatchAlreadyTaken`**. This is FREE — it reuses the SLOAD that resolving item 0 needs anyway (an `if (... == 0) revert` branch on the slot read), turning a collision-loser's waste from ~N×skip-scans into ~base+1 SLOAD. Because lists are processed front-to-back, "item 0 taken" reliably signals "a competitor got ahead." Items 1..N are each wrapped in per-item try/catch (below), so a benign partial-overlap (a competitor resolved only a prefix) leaves the live tail to the next crank — acceptable because bets carry NO every-entry-every-day guarantee (winners self-resolve; losers wait harmlessly). The short-circuit is a loser-gas-cap, not a completeness mechanism (completeness is the cursor's job, for boxes/subs); there is no griefing surface (`list[0]` is the caller's own choice).

- **Lootbox boxes = parameterless cursor per OPEN-D (CRANK-03).** `openLootBox` is already permissionless with no caller gate (`DegenerusGameLootboxModule.sol:477`); the crank only routes the reward. The **box resolution model is locked as a parameterless cursor** (collision-free, advanceGame-style self-partition) rather than a caller-list, because box-cranking is the valuable contended "open it for me" case and the box enqueue is cheap. The enqueue is ~1 SSTORE once per `(index, player)` at first deposit, detected via the existing `lootboxEthBase == 0` first-deposit signal (written `DegenerusGameMintModule.sol:1004-1008`, zeroed on open at `DegenerusGameLootboxModule.sol:531`). The box `RngNotReady` resolve guard (`DegenerusGameLootboxModule.sol:485, 567`) and the box-zeroing one-reward-per-item refund (`lootboxEth[index][player] = 0` at `:530`, `lootboxEthBase` at `:531`) are preserved untouched.

- **WWXRP earns zero reward (CRANK-04).** Work with `currency == 3` (WWXRP) is resolvable but earns **zero** crank reward — WWXRP is the most +EV currency (~the engaged-player reward), so it is excluded from the bounty to keep the faucet closed (§ faucet locks).

### Reward / charge model (REW-01..04)

- **Reward formula (REW-01) = `gasUnits(workType) · 0.5 gwei → BURNIE`, via the guarded `_ethToBurnieValue` idiom.** The conversion reuses `_ethToBurnieValue(amountWei, priceWei)` at `contracts/modules/DegenerusGameMintModule.sol:1412` — a private pure helper that guards `if (amountWei == 0 || priceWei == 0) return 0;` then computes `(amountWei * PRICE_COIN_UNIT) / priceWei`. The per-work-type ETH peg is `gasUnits(workType) · 0.5 gwei` — the cranker is reimbursed ~its gas at a fixed 0.5 gwei reference price. This mirrors the proven `advanceGame` bounty idiom `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT * bountyMultiplier) / PriceLookupLib.priceForLevel(lvl)` paid via `coinflip.creditFlip` (`DegenerusGameAdvanceModule.sol` 190-194 / 478-480; `ADVANCE_BOUNTY_ETH = 0.005 ether` at `:150`).

- **RESERVED per-work-type gas-peg constants.** The SPEC RESERVES named per-work-type `gasUnits`/`*_ETH_TARGET` constants here (one per work-type: resolve-bet, open-box, sweep-per-player); their **numeric values are calibrated at Phase 319 GAS from measured worst-case marginal gas** (OPEN-A). Only the names/shape are locked at SPEC; the numbers are deferred. REW-03 fixes that these are **fixed `gasUnits` constants — never `gasleft()` / `tx.gasprice`** (a measured-gas peg is gameable and breaks determinism); the bet reward is pegged to *per-spin* gas, box/sub flat, accepting big-win under-reimbursement (those resolves are owner-motivated anyway).

- **OPEN-B disposition (price-unavailable → reward 0, never revert).** LOCKED: reward computation reuses the `_ethToBurnieValue` zero-guard (`amountWei == 0 || priceWei == 0 → return 0`), so a bad/zero price yields reward 0 and never reverts the settlement. As a structural backstop, pegging to `PriceLookupLib.priceForLevel(uint24)` (`PriceLookupLib:21`, `pure`, never returns 0 — every branch ≥ 0.01 ether) makes div-by-zero impossible regardless. The chosen disposition is the **guarded `_ethToBurnieValue` form** (it additionally defends a future `mintPrice()`-sourced price), with the non-zero `priceForLevel` invariant cited as the secondary guarantee. Either way: reward → 0, never revert. (Final OPEN-B prose is owned by Plan 316-03; this section locks the reward-path consequence.)

- **REW-02 = coinflip-credit deferred mint, ONE `creditFlip` per cranker per tx (never per-item).** The reward is paid as coinflip stake credit (`creditFlip`), never liquid BURNIE — coinflip credit is a deferred mint (BURNIE only mints when the recipient later wins+claims a flip), so it needs no payment pool and must survive coinflip's edge before becoming liquid. The crank **accumulates each chunk's per-item rewards in memory and grants exactly ONE `creditFlip(caller, sumOfRewards)` at the end of the tx** — never one `creditFlip` per item. The credit goes to whoever called (REW-04 = no caller restriction; self-exclusion is Sybil-trivial security theater and only penalizes honest self-resolvers — safety is caller-independent).

### `batchPurchase(players[], amounts[], modes[])` shape (PROTO-04)

`DegenerusGame.batchPurchase(players[], amounts[], modes[])` is the keeper-gated entry the subscription keeper calls once per sweep to recover its purchase gas (does NOT exist yet — PROTO-04 adds it). Locked shape:

- **Keeper-gated** to the pinned `AF_KING` constant (PROTO-04/PROTO-05); does **no** per-player approval check (it trusts the keeper, which structurally only acts on its own `_subscribers`).
- **Per-player purchase wrapped in try/catch + slice-refund:** each player's purchase runs in-context (direct SLOADs); on revert → refund that player's value slice + skip + continue. One reverting player (a level/state-gated lootbox guard, game-over, liveness, or any per-player revert deep in the mint→lootbox→prize-pool→EV-cap→quest path) can NOT brick the batch. Structural isolation > exhaustive revert-enumeration for literal 0% brick.
- **ONE batch value transfer** (one value-hop into the game for the whole batch, not per player).
- **Batch-level conditions pre-checked once at entry:** `rngLocked` and game-over are checked once for a clean whole-batch abort before any per-player work begins.

**OPEN-C disposition (reentrancy) = CEI-proof WITH a guard-fallback note.** LOCKED: the game has **no `nonReentrant` modifier / ReentrancyGuard** anywhere; protection is **CEI throughout** — e.g. `claimablePool -= uint128(payout); // CEI: update state before external call` at `DegenerusGame.sol:1408`; ETH sends via `.call{value: …}` at `:2005 / :2022 / :2043`. The keeper's existing per-player loop already does CEI (pool debit before the external `purchase{value}`, the day-stamp after). The disposition is **CEI-proof**: `batchPurchase`'s per-player try/catch + slice-refund + a once-at-entry batch debit + a post-loop day-stamp should satisfy "no double-buy via reentrant sweep/cancel" without a new guard. **Guard-fallback note (mandatory for IMPL):** the IMPL (Phase 317) MUST trace the full mint→lootbox→prize-pool→EV-cap→quest callback chain for any external call that re-enters before the day-stamp, and **add an explicit reentrancy guard only if a re-entrant path is found.** This CEI-vs-guard proof — the highest-scrutiny ADD surface alongside `burnForKeeper` / `creditFlip` authority — is routed to the **`contract-auditor` skill at IMPL/TST** (Phase 317/318). (Named here only; NOT run in this SPEC phase. Final OPEN-C prose is co-owned with Plan 316-03.)

### Per-item revert isolation (SAFE-02)

The **only Solidity way to isolate an in-context per-item revert** is an `onlySelf` external sub-call wrapped in try/catch: each resolve/open runs via a self-external-call, and a failed item skips-and-continues (the batch rewards only the successes). This covers BOTH the bets/boxes mass-resolve/open AND the subscription `batchPurchase`. A stale / already-resolved / not-ready item, OR a deep per-item revert — for example the `_distributePayout` frozen-pool solvency check (`_distributePayout` decl `DegenerusGameDegeneretteModule.sol:705`, the revert-on-insufficient-solvency check at `~738`) — is a skip-and-continue case, never a batch brick. Iteration is caller-bounded (no contract-bounded loop); cancel is un-brickable; the in-context sub-call rolls back on revert so there is no double-buy. The cost is ~one self-call per item (the GAS phase weighs this against the ~100k+ resolve cost).

### OPEN-D box-cursor ↔ VRF-rotation orphan-index coupling (Pitfall 3 — the milestone's single biggest design landmine)

**LOCKED, stated explicitly:** the box cursor's enqueue/dequeue is keyed on the lootbox `index`, which re-couples it to the VRF-rotation orphan-index keyspace. This is the v45 CATASTROPHE surface (`project_vrf_rotation_midday_orphan_index`): an emergency VRF coordinator rotation can orphan an in-flight mid-day lootbox index. **The box cursor MUST follow the v45 `a303ae18` detect-preserve-re-issue path** — the same emergency-rotation handling that re-issues an in-flight `lootboxRngWordByIndex[N]` request on the new coordinator rather than orphaning it. The AUDIT phase (320) re-verifies the freeze invariant holds under emergency rotation WITH the new box cursor present. This is the single biggest design landmine in the milestone; any box-cursor IMPL that enqueues `boxPlayers[index]` keyed on the raw lootbox index without the `a303ae18` re-issue coupling re-introduces the catastrophe.

---

## ADD Design — Subscription Sweep & Authorization

The AfKing auto-rebuy subscription (Deliverable B) is `StreakKeeperV2` moved in-tree as a **separate contract** named `AfKing` and audited in-tree (the game-brick-immunity rationale is about the contract boundary, not the repo — a separate contract physically cannot corrupt the game's frozen storage). It auto-buys tickets/lootboxes for subscribers, drawing funds via the funding waterfall and recovering its gas via the keeper-gated `batchPurchase` (above). It is owner-less / no-admin / no-upgrade — same frozen posture as the game.

> **Keeper transitional-state caveat (Pitfall 1 — record explicitly).** The keeper's CURRENT live source is a **MIXED transitional state** that does NOT match `PLAN-CRANK §9`'s claimed post-rework state. `316-RESEARCH.md §1.12` re-verified live source against §9 and found: **19× `pullForKeeper`, 5× `mintForKeeper`, only 2× `creditFlip`**, the OLD caller-supplied `sweep(uint256 startIdx, uint256 count)` loop, `subscribe(bool drainGameCreditFirst, uint8 dailyQuantity)` (no `reinvestPct`), and **NO `sweepCursor`, NO `reinvestPct`, NO `windowPaid`** anywhere. Therefore `PLAN-CRANK §9` "done this session (compile-verified)" is **FALSE vs live source** — the cursor / reinvestPct / windowPaid / `batchPurchase` switch / `pull→burn` rename / full `creditFlip` are **genuinely unbuilt**. **This SPEC locks against the INTENDED end-state for Phase 317 IMPL, NOT the current keeper source.** This caveat is cited so the plan-checker does not treat §9 "done this session" as ground truth (cite `316-RESEARCH.md §1.12` drift table). The dependency check itself is clean: the keeper references ZERO RM-deleted symbols (§3) — its only game-side coupling is `hasAnyLazyPass` (the kept-and-exposed PROTO-01 view).

### Cursor sweep (SUB-03)

Mirror **`advanceGame`'s progress-cursor model** (chunk-then-`return`; per-chunk ETH-pegged bounty; escalating `bountyMultiplier` on stall):

- **`sweep(uint256 maxCount)` + internal daily-reset `sweepCursor`.** Each call resumes from the cursor, processes ≤ `maxCount` un-swept active entries, advances the cursor, pays the per-chunk bounty. **No caller-supplied range** (replaces the live OLD `sweep(startIdx, count)`).
- **Concurrent same-block callers self-partition** via the advancing cursor — Tx2 sees Tx1's advanced cursor and takes the next chunk: no overlap, no off-chain range coordination, no wasted-skip reverts (SUB-03 / SAFE-03). Per-entry `lastSweptDay` (already a field on the keeper, `keeper:31`; skip at `keeper:962` via `if (sub.lastSweptDay >= today)`) is the **idempotency backstop** (same-block correctness already holds via sequential execution + the day-stamp — no double-buy).
- **Stall-escalating bounty** mirrors advanceGame's 2/4/6× `bountyMultiplier`: if the cursor lags, the per-chunk bounty rises until someone finishes the day's sweep — this drives daily completeness.
- **Caller-bounded `maxCount`** (no contract-bounded loop) is the anti-gas-DoS property. Liveness ("every entry every day") = contract idempotency + reachability + bounty-incentivized cursor coverage.

### Lapsed / cancelled lifecycle (SUB-07)

- **Tombstone-on-cancel** — external cancel (`setDailyQuantity(0)`) only sets `dailyQuantity = 0` and **moves nothing**, so it can never relocate an unprocessed entry behind the cursor (the one miss case a swap-pop-on-cancel would cause).
- **In-sweep swap-pop reclaim** — on auto-pause OR on reaching a tombstone, the sweep removes the entry, moves the tail into the slot, and processes it there **WITHOUT `++i`** (the mover came from ahead → already processed; nothing skipped or doubled). Reuse the existing `_removeFromSet` swap-pop (`keeper:707 / 1013`). No separate `compact()` pass; no dead-slot buildup.
- **`_subOf` storage reclaim** — `delete` (refund) on lapse AND on cancel, **KEEP only to preserve an unexpired _paid_ window** (`paidThroughDay > today` AND the window was paid, not free). "Paid" is determined via a **1-bit `windowPaid` flag** in the `Sub`'s free bytes — **set on `burnForKeeper`, cleared on the free pass-extend** — which avoids a cancel-path STATICCALL. Pass-holder / expired cancels `delete` (their window was free or gone → nothing to preserve; re-subscribe is fresh). `useTickets` settings-loss on delete is acceptable.
- **Transient skips** (not-approved-funds / insufficient-pool / lootbox-floor) **stay in the set and retry next sweep** (distinct from a kill — see SUB-06, owned by Plan 316-03).
- **Stranded `_poolOf` ETH** on a cancelled sub stays the owner's withdrawable balance — never auto-swept; `withdraw()` reclaims it.

### Authorization (SUB-02)

**Authorization = the subscription itself** — no separate operator-approval re-check in the sweep:

- `subscribe(address player, …)` uses the game's resolve-gate **once at subscribe, third-party path only**: `player == msg.sender` (or `0`) → self-consent, no check; else `require isOperatorApproved(player, msg.sender)` — third-party subscribe is allowed exactly when the player approved the caller as a game operator (mirrors `_resolvePlayer` / `_requireApproved` at `DegenerusGame.sol:458 / :452` and module `:141 / :131`). **Never checked at sweep.**
- The sub is the standing authorization; the player controls it directly (`setDailyQuantity` / `setDrainGameCreditFirst` / cancel all key off `_subOf[player]`). Revoking the operator's game-approval later does NOT auto-cancel (it is a separate, broader grant) — the player cancels directly.
- The game's keeper-purchase entry (`batchPurchase`) is gated to the pinned keeper (`msg.sender == AF_KING`) and does **no per-player approval check** — it trusts the keeper, which structurally only acts on its own `_subscribers`.

### Pass-OR-pay gate (SUB-01 / SUB-08)

- **Pass = any of Deity / Whale / Lazy via `hasAnyLazyPass` (PROTO-01).** All three are packed in the single `mintPacked_[player]` word; `_hasAnyLazyPass` (`DegenerusGame.sol:1610`) already returns `hasDeityPass || frozenUntilLevel > level` = exactly "any of the three" (Deity bit 184 permanent; Whale-bundle + Lazy via `FROZEN_UNTIL_LEVEL` bits 128-151, level-expiring). 1 SLOAD common case, 2 worst, zero external calls.
- **Checked at the monthly renewal branch ONLY** (`paidThroughDay <= today`) — **never per sweep** (already gas-optimal; the optimistic "fire only inside renewal branch" pattern, keeper renewal-gate at `keeper:974`).
- **No pass → `burnForKeeper` charges** the BURNIE cost (or **skip-with-emit** if uncoverable — never revert the whole sweep). **Charge = `burnForKeeper`, all-or-nothing burn** (PROTO-02; if the source can't cover the full amount, burn nothing). **Bounty = `creditFlip`, gas-pegged** (SUB-08, the REW reward model above).

---

## PROTO Additions

The 5 protocol-side additions ship as ONE batched USER-APPROVED contract diff at Phase 317 IMPL. All keeper-authority gates resolve to the **pinned `AF_KING` address constant** (PROTO-05). `ContractAddresses.sol` already pins `VAULT` (`:37`) and `SDGNRS` (`:47`); **no `AF_KING` / `STREAK_KEEPER` constant exists yet** — PROTO-05 must ADD it.

- **PROTO-01 — `hasAnyLazyPass(address) external view`.** Rename the existing private `_hasAnyLazyPass` (`DegenerusGame.sol:1610`) to `external view`, **NO body change**. The reader-set is exactly 3 grep matches total (`316-RESEARCH.md §2`): the decl at `:1610` plus the two readers at `:1580` (`_setAfKingMode`) and `:1660` (`syncAfKingLazyPassFromCoin`) — both inside afKing-**mode** machinery being deleted by RM-01, so after the deletion the body survives precisely because the keeper needs it externally (this is the cross-half RM-04 KEEP+EXPOSE reconciliation; the deletion of the surrounding `:1580`/`:1660` functions does not touch the body). PROTO-01's design lock + verified reader-set is the SPEC-owned acceptance for this phase.

- **PROTO-02 — `BurnieCoin.burnForKeeper(address user, uint256 amount) returns (uint256 burned)`.** Does NOT exist yet — adds it. **ALL-OR-NOTHING** burn of the subscription charge: source from the user's `balanceOf` + pending coinflip; if the available total `< amount`, **burn nothing and return 0** (the charge skip-with-emits at the call site, never a partial burn — you cannot refund a burn). Gated `onlyAfKing` (`msg.sender == AF_KING`, the pinned constant).

- **PROTO-03 — authorize the keeper in `BurnieCoinflip.onlyFlipCreditors`.** The `creditFlip(address player, uint256 amount)` interface decl **ALREADY exists** at `IBurnieCoinflip.sol:115` (with `creditFlipBatch` at `:122`), and the implementation lives at `BurnieCoinflip.sol:898` behind the `onlyFlipCreditors` modifier (`:194`). PROTO-03 therefore only **ADDs the `AF_KING` keeper to `onlyFlipCreditors`** so its gas-pegged `creditFlip` bounty works (coinflip credit = deferred mint; replaces the discarded `mintForKeeper`). No new interface decl needed.

- **PROTO-04 — `DegenerusGame.batchPurchase(players[], amounts[], modes[])`.** Does NOT exist yet — adds it. Keeper-gated (on `AF_KING`); per-player in-context purchase wrapped in try/catch + slice-refund; ONE batch value transfer; batch-level `rngLocked`/game-over pre-checked once at entry; OPEN-C = CEI-proof with the guard-fallback note. **Full shape locked in the `## ADD Design — Do-Work Crank` → `batchPurchase` subsection above** (this entry points to that lock).

- **PROTO-05 — pin `AF_KING` frozen address constant.** ADD `AF_KING` (aligning with any existing afKing address) to `ContractAddresses.sol` (freely modifiable per `feedback_contractaddresses_policy`), and reference it from `BurnieCoin` / `BurnieCoinflip`. `burnForKeeper` / `creditFlip` / `batchPurchase` all gate on **exactly** this constant. `VAULT`/`SDGNRS` (`ContractAddresses.sol:37/:47`) are the precedent pattern; the keeper-rename succession (`STREAK_KEEPER_V2`→`AF_KING`, `onlyStreakKeeper`→`onlyAfKing`) propagates the gate references.

---

## REMOVE Footprint

This is the REMOVE-half design lock authored in Plan **316-02** (appended to the 316-01 ADD-half sections above; those sections are untouched). It locks the PROTO-01/RM-04 KEEP+EXPOSE reconciliation and the RM-01..06 deletion footprint that Phase 317 IMPL deletes verbatim. Every `file:line` below was re-grep-verified against contract HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` on 2026-05-23 (SC#5); where `316-RESEARCH.md §1` recorded a `✗ DRIFT` vs `PLAN-V47`, the RESEARCH live line is locked and the drift is recorded inline. The dedicated call-graph attestation table is owned by Plan 316-04; this section is the design-binding footprint, not the attestation appendix.

### RM-04 / PROTO-01 reconciliation — KEEP+EXPOSE `_hasAnyLazyPass` (locked verbatim)

**LOCKED, overriding the dead-code-deletion instinct:** RM-04 = **KEEP** the existing `_hasAnyLazyPass` body and **EXPOSE** it (rename `private view` → `external view` as `hasAnyLazyPass`, NO body change); **DELETE the rest of afKing** (RM-01/RM-02). This is the single cross-half reconciliation — RM-01 deletes all the afKing-mode machinery *around* `_hasAnyLazyPass`, but the function itself survives because the subscription keeper needs it as its sole pass gate.

**Dependency-safety proof (verified reader-set, 3 grep matches total — `316-RESEARCH.md §2`, re-verified at HEAD):**
- decl `DegenerusGame.sol:1610` (`function _hasAnyLazyPass(address player) private view returns (bool)`),
- reader `DegenerusGame.sol:1580` (inside `_setAfKingMode` — `if (!_hasAnyLazyPass(player)) revert E();`),
- reader `DegenerusGame.sol:1660` (inside `syncAfKingLazyPassFromCoin` — `if (_hasAnyLazyPass(player)) return true;`).

Both readers (`:1580`, `:1660`) sit inside afKing-**mode** functions slated for RM-01 deletion. After RM-01, the private function would be dead code *except* for the keeper's external need — therefore KEEP+EXPOSE is **required, not optional**. The deletion of the surrounding `:1580`/`:1660` functions does not touch the body (the body reads `mintPacked_[player]` Deity bit 184 + `FROZEN_UNTIL_LEVEL` bits 128-151 via `BitPackingLib` — `316-RESEARCH.md §2`).

**The deletion is dependency-safe IFF PROTO-01 ships in the SAME batched Phase-317 diff.** Keeper-dependency finding (`316-RESEARCH.md §3`, re-verified): `StreakKeeperV2` matches ZERO RM-deleted symbols across the full RM-symbol set; its only game-side coupling is `hasAnyLazyPass(player)` at keeper `:671` (subscribe gate) and `:974` (renewal-sweep gate) — the kept-and-exposed PROTO-01 view, NOT a deleted symbol. So the keeper's gate survives RM-* unchanged provided the rename ships alongside the deletion.

### RM-01 — AFKing mode surface (DegenerusGame.sol — `316-RESEARCH.md §1.1`, all ✓ MATCH at HEAD)

**DELETE the 13 afKing-mode functions, KEEPING only `_hasAnyLazyPass`:**

| Symbol | Line | Action |
|--------|------|--------|
| `setAutoRebuy` | 1495 | DELETE (also RM-02) |
| `setAutoRebuyTakeProfit` | 1504 | DELETE (also RM-02) |
| `_setAutoRebuy` | 1512 | DELETE (also RM-02) |
| `_setAutoRebuyTakeProfit` | 1524 | DELETE (also RM-02) |
| `autoRebuyTakeProfitFor` | 1543 | DELETE (also RM-02) |
| `setAfKingMode` | 1559 | DELETE |
| `_setAfKingMode` | 1569 | DELETE (contains the `:1580` `_hasAnyLazyPass` reader) |
| `_hasAnyLazyPass` | 1610 | **KEEP+EXPOSE** (RM-04 — body unchanged) |
| `afKingModeFor` | 1624 | DELETE |
| `afKingActivatedLevelFor` | 1631 | DELETE |
| `deactivateAfKingFromCoin` | 1641 | DELETE |
| `syncAfKingLazyPassFromCoin` | 1654 | DELETE (contains the `:1660` `_hasAnyLazyPass` reader) |
| `_deactivateAfKing` | 1670 | DELETE |

**DELETE 3 events:** `AutoRebuyToggled` (`:1476`), `AutoRebuyTakeProfitSet` (`:1479`), `AfKingModeToggled` (`:1482`). **DELETE error** `AfKingLockActive` (`:92`; used at `:1676` inside `_deactivateAfKing`). **DELETE 3 consts:** `AFKING_KEEP_MIN_ETH` (`:151`; used `:1535`/`:1584`/`:1585`), `AFKING_KEEP_MIN_COIN` (`:154`; used `:1588`/`:1589`), `AFKING_LOCK_LEVELS` (`:157`; used `:1675`). **REMOVE 2 cross-calls:** `coinflip.settleFlipModeChange(player)` at `:1603` (inside `_setAfKingMode`) and `:1678` (inside `_deactivateAfKing`).

### RM-02 — free ETH auto-rebuy (storage + jackpot — `316-RESEARCH.md §1.2/§1.3/§1.4`)

- **storage/DegenerusGameStorage.sol:** DELETE `struct AutoRebuyState` (`:910`, body 910–919) and `mapping(address => AutoRebuyState) internal autoRebuyState` (`:926`). forge-confirmed: `autoRebuyState` = **slot 19** (the RM-06 / storage-slot-shift consequence is locked in `## Storage Slot-Shift Plan` below).
- **modules/DegenerusGameJackpotModule.sol:** `_addClaimableEth` decl `:788` is the 3-arg form `(beneficiary, weiAmount, entropy)` (sig 788–795, returns `(claimableDelta, rebuyLevel, rebuyTickets)` at `:794`). The auto-rebuy block is at **800–808** (the `AutoRebuyState memory state = autoRebuyState[beneficiary];` cold SLOAD verified at `:801`) — **`✗ DRIFT` +2 vs `PLAN-V47`'s claimed 798–806; the locked range is 800–808.** DELETE `_processAutoRebuy` (`:822`). Verify-orphaned: `_budgetToTicketUnits` (`:861`) — confirm no surviving caller post-cut at IMPL. Post-removal, ETH winnings **always credit to claimable** (`_addClaimableEth` falls straight through to `_creditClaimable`). The 3-arg `_addClaimableEth` is consumed at JackpotModule call sites `:755`/`:760`/`:765` (the internal 3-call helper) and `:1430` (`entropyState`), `:1530` (`entropy`), `:1571`, `:1583`, `:2132`, `:2165` — the `entropy`-param drop + the `JackpotEthWin` event signature change (decl `:69`, fields `rebuyLevel`/`rebuyTickets` at `:75`/`:76`, emitted around `:1430`-1438) are locked in `## VRF-Freeze Obligation Retirement` below (ABI break noted there).
- **modules/DegenerusGamePayoutUtils.sol:** DELETE `_calcAutoRebuy` (`:51`; the afKing-mode bonus selector `state.afKingMode ? bonusBpsAfKing : bonusBps` at `:83`; the entropy roll `keccak256(abi.encode(entropy, beneficiary, weiAmount)) & 3` at ~`:70`). Verify-orphaned: `struct AutoRebuyCalc` (`:19`) — confirm no surviving caller post-cut at IMPL.

### RM-03 — BURNIE flip recycle collapse to flat 75bps (BurnieCoinflip.sol — `316-RESEARCH.md §1.5`)

**KEEP the core, drop only the afKing/deity tier.** Surgery interiors (verified at HEAD):
- DELETE `settleFlipModeChange` (`:217`). Collapse the rebet-bonus afKing branch (body 294–308: `afKingModeFor` `:300`, `hasDeityPass` `:302`, `_afKingDeityBonus` `:304`, `_afKingRecyclingBonus` `:305`) to `_recyclingBonus`. In `_claimCoinflipsInternal` (`:416`): drop the `syncAfKingLazyPassFromCoin` sync call (`:422`), the `afKingActive`/`hasDeityPass`/`deityBonusHalfBps` block (434–443), and collapse the recycle branch (540–548) to `_recyclingBonus`. In `_setCoinflipAutoRebuy` (`:722`) / `_setCoinflipAutoRebuyTakeProfit` (`:776`): remove the `deactivateAfKingFromCoin` calls (`:754`/`:766`/`:793`) and the `AFKING_KEEP_MIN_COIN` floor checks (`:753`/`:792`).
- DELETE helpers `_afKingRecyclingBonus` (`:1062`) and `_afKingDeityBonusHalfBpsWithLevel` (`:1078`). DELETE 5 consts: `AFKING_RECYCLE_BONUS_BPS` (`:130`, **=100** — note: this is the deleted afKing tier, NOT the kept 75bps; `PLAN-V47` §1.5 shorthand "75bps" refers to the *kept* `RECYCLE_BONUS_BPS`, recorded here precisely to avoid a wrong-value deletion), `AFKING_DEITY_BONUS_PER_LEVEL_HALF_BPS` (`:131`), `AFKING_DEITY_BONUS_MAX_HALF_BPS` (`:132`), `DEITY_RECYCLE_CAP` (`:133`), `AFKING_KEEP_MIN_COIN` (`:140`).
- **KEEP (byte-unmodified):** `RECYCLE_BONUS_BPS` (`:129`, **=75**) — the flat post-collapse recycle rate; `_recyclingBonus` (`:1051`, `bonus = (amount * uint256(RECYCLE_BONUS_BPS)) / uint256(BPS_DENOMINATOR)` at `:1055`); and the BURNIE win/loss RNG path `processCoinflipPayouts` (`:805`) with `bool win = (rngWord & 1) == 1;` (`:837`) — this path **MUST NOT be modified** (RM-06).

### RM-04 — the kept `_hasAnyLazyPass`

See the RM-04/PROTO-01 reconciliation block above. The single KEEP in an otherwise-all-delete afKing surface; exposed as `hasAnyLazyPass` external view (PROTO-01).

### RM-05 — cross-contract cascade (interfaces + Vault + sStonk — `316-RESEARCH.md §1.6/§1.7/§1.8/§1.9`)

- **interfaces/IDegenerusGame.sol:** REMOVE `afKingModeFor` (`:274`), `afKingActivatedLevelFor` (`:279`), `deactivateAfKingFromCoin` (`:283`), `syncAfKingLazyPassFromCoin` (`:288`). **RESOLVED open (`316-RESEARCH.md §1.6`):** `setAutoRebuy`/`setAutoRebuyTakeProfit`/`setAfKingMode` are **NOT declared in `IDegenerusGame`** (the doc's "verify whether present" resolves to MISSING here) — they ARE in `DegenerusVault`'s **local** interface (see below). **KEEP** `hasDeityPass` (`:376`, read by coinflip — not in removal scope).
- **interfaces/IBurnieCoinflip.sol:** REMOVE `settleFlipModeChange` (`:85`). (`creditFlip` at `:115` + `creditFlipBatch` at `:122` are ADD-side PROTO-03, NOT removed.)
- **DegenerusVault.sol:** REMOVE the local interface decls `setAutoRebuy` (`:47`), `setAutoRebuyTakeProfit` (`:49`), `setAfKingMode` (`:51`); REMOVE the wrappers `gameSetAutoRebuy` (decl `:627`, body call `:628`), `gameSetAutoRebuyTakeProfit` (decl `:634`, body `:635`), `gameSetAfKingMode` (decl `:643`, body `:648`). **KEEP** `coinSetAutoRebuy` (`:685`) / `coinSetAutoRebuyTakeProfit` (`:692`) — the BURNIE-side wrappers stay.
- **StakedDegenerusStonk.sol:** REMOVE the local decl `setAfKingMode` (`:13`) and the init call `game.setAfKingMode(address(0), true, 10 ether, 0)` (`:361`, preceded by `game.claimWhalePass(address(0))` at `:360`). The `setAfKingMode` init is **REPLACED by the keeper self-subscribe (SUB-09)** — that init-config design is locked in Plan 316-03; this section locks only the removal of the `setAfKingMode` call. (The second `game.claimWhalePass(address(0))` re-claim entry at `:404` is not in the removal scope.)

### RM-05 / RM-06 verify-before-IMPL orphan + byte-unmodified hygiene

- **Orphan checks (grep post-edit at IMPL):** confirm `AutoRebuyCalc` (`PayoutUtils:19`), `_budgetToTicketUnits` (`JackpotModule:861`), and any `AutoRebuyState` import have ZERO surviving callers after the RM-01/RM-02 cuts before deleting them.
- **Pitfall 4 — separate overload untouched:** the `DegenerusGameDegeneretteModule._addClaimableEth(address beneficiary, uint256 weiAmount)` **2-arg** overload (`:1117`) is a DISTINCT function from the JackpotModule 3-arg `(beneficiary, weiAmount, entropy)` form. ONLY the JackpotModule 3-arg form carries the auto-rebuy/entropy path; the Degenerette 2-arg overload is **untouched** by RM-02. Do NOT collapse or rename it.
- **Byte-unmodified (RM-06):** `KNOWN_ISSUES` and the BURNIE win/loss RNG path (`processCoinflipPayouts` `:805`, `(rngWord & 1)` `:837`) MUST stay byte-identical across the whole batched diff.

### JGAS cross-reference (footprint owned by Plan 316-05)

The JGAS daily-ETH two-call-split deletion footprint (the `SPLIT_*` / `resumeEthPool` / `_resumeDailyEth` / `splitMode` / `call1Bucket` / `STAGE_JACKPOT_ETH_RESUME` symbols) is **NOT enumerated here** — it is owned by **Plan 316-05's `## JGAS-01 Decision Gate` section**. The only JGAS interaction this plan carries is that `resumeEthPool`'s storage-slot deletion (forge slot 33) **compounds the RM-06 slot shift to −2 for the slot-≥34 region** — locked in `## Storage Slot-Shift Plan` below.

---

## Storage Slot-Shift Plan

RM-06 + JGAS-02 storage-layout re-derivation, locked as a **COMPOUNDED two-deletion shift** (`316-RESEARCH.md §4` + `§J3`, `forge inspect` authoritative). The SAME batched Phase-317 diff deletes **two** storage vars, so the slot re-derivation is a single combined pass — never two sequential −1 patches.

### The two deleted vars (forge-confirmed at HEAD)

- **`autoRebuyState` = slot 19** (RM-02; full-slot mapping). Its deletion → every var at slot ≥ 20 shifts **−1**.
- **`resumeEthPool` = slot 33** (JGAS-02; `uint128` at offset 0 occupying its **OWN** slot — the next declared var `vrfCoordinator` starts fresh at slot 34, NOT packed into 33's free upper 16 bytes). Its deletion → an ADDITIONAL **−1** for every var at slot ≥ 34. (The `resumeEthPool` deletion *footprint* — its reads/writes/the split mechanism — is owned by Plan 316-05; here it is only the second deleted var that compounds the shift.)

### The COMBINED shift (locked)

- vars at slot **< 19** — unchanged.
- vars in **[20, 33)** — shift **−1**.
- vars at slot **≥ 34** — shift **−2**.

**Key combined shifts (current → post-(RM-02+JGAS)):**

| Var | Current slot | Post-(RM-02+JGAS) slot | Net |
|-----|--------------|------------------------|-----|
| `autoRebuyState` | 19 | (deleted) | — |
| `lootboxEthBase` | 20 | 19 | −1 |
| `resumeEthPool` | 33 | (deleted) | — |
| `vrfCoordinator` | 34 | 32 | **−2** |
| `lootboxRngPacked` | 37 | 35 | **−2** |
| `lootboxRngWordByIndex` | 38 | 36 | **−2** |
| `lootboxDay` | 39 | 37 | **−2** |
| `degeneretteBets` | 45 | 43 | **−2** |
| `boonPacked` | 61 | 59 | **−2** |

**⚠ The `vrf*` / `lootboxRng*` family the v45 VRF work depends on lands at −2, NOT −1.** This is the JGAS-deepened shift: `lootboxRngWordByIndex` 38 → **36**, `lootboxRngPacked` 37 → **35**, `vrfCoordinator` 34 → **32**. Anyone treating the shift as a uniform −1 would mis-derive the entire slot-≥34 region (the exact slot family `project_vrf_rotation_midday_orphan_index` + the v45 freeze-invariant work reference) by a full slot. The −2 region is the load-bearing distinction this section locks.

### Where the work lives — entirely test-side

**Contract source contains ZERO numeric slot literals** (re-verified at HEAD: `grep -rnE '\.slot\s*:?=\s*[0-9]+|sload\([0-9]+\)|SLOT_[A-Z_]+\s*=\s*[0-9]+' contracts/` excl test returns only `QUEST_SLOT_COUNT=2` and `TICKET_SLOT_BIT=1<<23` — neither is a storage-slot literal). **NO contract code breaks on either shift** — RM-06 (now including the JGAS `resumeEthPool` deletion) is **entirely a test-side problem**: ~28 test-side `SLOT_*` constants across ~15 files: `BafRebuyReconciliation`, `BafFarFutureTickets`, `RngIndexDrainBinding` (+handler), `DegeneretteFreezeResolution`, `AdvanceGameRewrite`, `AffiliateDgnrsClaim`, `QueueDoubleBuffer`, `VRFCore`, `StorageFoundation`, `LootboxBoonCoexistence`, `LootboxRngLifecycle`, `VrfRotationOrphanIndex`, `StakedStonkRedemption`, `RngLockRotationDeterminism`, `RedemptionEdgeCases`, `VrfRotationLiveness`, `JackpotCombinedPool`, `TicketLifecycle`, `RngLockDeterminism`, `VRFStallEdgeCases`, `RedemptionInvariants.inv`, `RedemptionHandler`.

### Re-derivation MANDATE (locked)

Re-run `forge inspect contracts/DegenerusGame.sol:DegenerusGame storage-layout` **ONCE** on the **POST-(RM-02+JGAS)** contract (both `autoRebuyState` AND `resumeEthPool` deleted in the same diff), and rewrite each test `SLOT_*` constant from that authoritative output, **file-by-file**:
- **NEVER patch-by-arithmetic** (Pitfall 2).
- **NEVER as a blind −1** — the slot-≥34 region is −2; a uniform decrement would be wrong for the entire `vrf*`/`lootboxRng*` family.
- RM-06 and JGAS slot work are re-derived **TOGETHER in one combined pass** (one deletion diff, one `forge inspect`).

### Stale-baseline compounding hazard (locked)

`LootboxBoonCoexistence.t.sol`'s `SLOT_*` constants are **ALREADY +1 stale** vs the current layout (it declares `SLOT_LOOTBOX_RNG_IDX=38` / `SLOT_LOOTBOX_WORD=39` against a live `lootboxRngWordByIndex=38` / `lootboxDay=39`) AND `test_lootboxBoonAppliedDespiteExistingCoinflipBoon` **FAILS at baseline** ("At least one lootbox should have rolled a non-coinflip boon"). With the JGAS −2 compounding, `lootboxRngWordByIndex` lands at slot **36** / `lootboxRngPacked` at **35** — so the re-derivation **cannot be a blind decrement** (some constants are already off in the wrong direction). RM-06 + JGAS therefore MUST: (a) **capture the pre-deletion baseline-failure ledger FIRST** (so the delta is attributable); (b) re-derive from the single combined `forge inspect`; (c) ensure the post-deletion delta is attributable so the re-derivation is NOT blamed for the pre-existing `LootboxBoonCoexistence` failure (the Phase 318 TST phase owns "no NEW failures vs baseline").

The JGAS deletion **FOOTPRINT itself** (the symbols being removed) is enumerated in Plan 316-05; this section locks only the slot-derivation consequence (the −2 compounding + the one-combined-pass mandate). No duplicate footprint enumeration here.

---

## VRF-Freeze Obligation Retirement

SAFE-04 + RM-02 — the concrete VRF-freeze-obligation retirement the ETH-auto-rebuy removal delivers (`316-RESEARCH.md §6` entropy cascade, re-verified at HEAD).

### The entropy cascade being retired

The VRF word (`rngWord` / `randWord`, VRF-derived) is mixed via `EntropyLib.hash2` and threaded as `entropy` / `entropyState` through the jackpot resolution loop into the **3-arg** `_addClaimableEth(beneficiary, weiAmount, entropy)` (`DegenerusGameJackpotModule.sol:788`, consumed at call sites `:755`/`:760`/`:765`/`:1430`/`:1530`/`:1571`/`:1583`/`:2132`/`:2165`) → `_processAutoRebuy` (`:822`) → `_calcAutoRebuy` (`DegenerusGamePayoutUtils.sol:51`), where `keccak256(abi.encode(entropy, beneficiary, weiAmount)) & 3` (~`:70`) picks the rebuy target level.

Removing `_processAutoRebuy` / `_calcAutoRebuy` (RM-02) makes `entropy` **UNCONSUMED on the claimable path** → it is **dropped from the 3-arg `_addClaimableEth` signature** (the function reduces to crediting claimable directly via `_creditClaimable`).

### ABI break — `JackpotEthWin` event signature change (delta note)

The `JackpotEthWin` event (`DegenerusGameJackpotModule.sol:69`) carries `rebuyLevel` (`:75`) / `rebuyTickets` (`:76`) — these become dead on RM-02 removal, so the **event signature CHANGES (breaking topic-hash / field-set delta)**. This is a benign ABI break for the off-chain indexer (a separate frontend track per the out-of-scope list, `316-RESEARCH.md §9 Q3`); recorded here as a delta note, not an in-scope fix.

### The SAFE-04 retirement claim, made concrete

This is the literal "one fewer VRF consumer + three fewer player-mutable in-window inputs" retirement SAFE-04 asserts:
- **−1 VRF consumer:** the daily-ETH claimable path no longer reads the threaded `entropy` (the rebuy-level roll is gone).
- **−3 player-mutable in-window inputs:** `autoRebuyEnabled` / `takeProfit` / `afKingMode` (the `AutoRebuyState` fields, slot 19) are no longer read inside the rng-locked jackpot resolution window. The removal **retires** freeze obligations rather than weakening any — strictly fewer player-controllable SLOADs participate in the VRF-frozen window (consistent with the v45 freeze-invariant north-star).

### IMPL obligation (locked) + AUDIT routing

Before dropping the `entropy` param, the Phase-317 IMPL MUST **verify no OTHER reader of the threaded `entropyState` survives** (grep the full threading chain at IMPL). The 3-arg `_addClaimableEth` is **JackpotModule-only**; the `DegenerusGameDegeneretteModule._addClaimableEth(beneficiary, weiAmount)` **2-arg overload** (`:1117`) is a separate function and is **untouched** — do NOT conflate the two (Pitfall 4). Route the "does dropping `entropy` change any OTHER consumer?" verification to the **`zero-day-hunter` skill at AUDIT** (Phase 320) — named here only; NOT run in this SPEC phase.
