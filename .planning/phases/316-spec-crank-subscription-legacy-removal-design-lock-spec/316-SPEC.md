# Phase 316 SPEC — Crank + Subscription + Legacy-Removal Design Lock

**Milestone:** v46.0 — Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal
**Phase type:** SPEC / design-lock (read-only — zero `contracts/` and zero `test/` mutations; this phase only reads source to grep-verify file:line claims and writes this markdown).
**Audit baseline → subject:** v45.0 closure HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` → v46.0 closure HEAD.
**Load-bearing inputs:** `316-RESEARCH.md` (grep/forge-verified call-graph substrate) + `PLAN-CRANK-DO-WORK-INCENTIVE.md` (ADD half) + `PLAN-V47-REMOVE-AFKING-ETH-AUTOREBUY.md` (REMOVE half) + `REQUIREMENTS.md` (42 v46.0 reqs).

**This SPEC locks the FULL v46.0 add+remove+JGAS design across all 42 requirements** (PROTO-01..05 · CRANK-01..04 · REW-01..04 · SUB-01..09 · RM-01..06 · SAFE-01..04 · GAS-01..06 · JGAS-01..04) and is the **load-bearing input for Phases 317 (IMPL) / 318 (TST) / 319 (GAS) / 320 (TERMINAL)** — every downstream phase consumes these locks. Only **FOUR** requirements have Phase 316 SPEC as their *primary* verification owner: **PROTO-01 · SUB-09 · RM-04 · JGAS-01**; the other 38 have their designs locked here but downstream primary owners (see `## Requirement Design Coverage`). The JGAS-01..04 jackpot-split-removal sub-thread was folded in 2026-05-23 (38→42 reqs).

This SPEC is authored across the Phase 316 plans:
- **316-01:** the ADD-half design lock — `## ADD Design — Do-Work Crank`, `## ADD Design — Subscription Sweep & Authorization`, `## PROTO Additions`.
- **316-02:** REMOVE footprint + reconciliation — `## REMOVE Footprint`, `## Storage Slot-Shift Plan`, `## VRF-Freeze Obligation Retirement`.
- **316-05:** the JGAS-01 jackpot-split-removal decision gate — `## JGAS-01 Decision Gate` (SPEC-owned; design-intent → worst-case-first gas → locked decision → deletion footprint → J5 VRF/freeze verdict).
- **316-03:** open-item resolution — `## Quantity & Funding Model`, `## Protocol-Owned Subs (SUB-09)`, `## SPEC-Open Resolutions` (OPEN-B/OPEN-C/denomination/whale-expiry/skip-kill identity/SUB-09 init configs).
- **316-04 (this plan's sections):** the call-graph attestation + the requirement/success-criteria coverage maps — `## Requirement Design Coverage`, `## Success Criteria Coverage`, `## Call-Graph Attestation` (this RESEARCH.md's §1 + §J1 verification tables; the SPEC carries no unverified "by construction" claim).

**Citation discipline (SC#5):** every `file:line` cited in the design sections below was re-grep-verified against HEAD on 2026-05-23 before authoring (the full attestation is the `## Call-Graph Attestation` section at the end of this document). Two short-hand / drift notes carried forward from `316-RESEARCH.md`: (a) the Degenerette module's canonical filename is `contracts/modules/DegenerusGameDegeneretteModule.sol` (research/PLAN short-hand it as `DegeneretteModule.sol`); (b) the `_distributePayout` frozen-pool solvency check is at `~738` inside the body — `PLAN-CRANK §8`'s "742" is an interior offset (decl at `:705`). No design claim below rests on an un-verified anchor.

---

## Requirement Design Coverage

This section (Plan **316-04**) maps **all 42 v46.0 requirement IDs** to the SPEC section that LOCKS each design + its **primary verification owner phase**. Coverage is **42/42, zero unmapped**. The **FOUR** reqs with Phase 316 SPEC as primary owner are **PROTO-01 · SUB-09 · RM-04 · JGAS-01**; the other 38 have downstream primary owners (317 IMPL · 318 TST · 319 GAS) but their **designs are all locked at this SPEC**. Phase 320 TERMINAL re-attests all 42 and owns 0 primarily. (Source: `REQUIREMENTS.md` Traceability + `316-RESEARCH.md §10`/`§J6`.)

| Req | Design locked in SPEC section | Primary owner |
|-----|-------------------------------|---------------|
| **PROTO-01** | `## PROTO Additions` + `## REMOVE Footprint` (RM-04/PROTO-01 reconciliation) + `## Call-Graph Attestation` (4) | **Phase 316 (SPEC-owned)** |
| PROTO-02 | `## PROTO Additions` (`burnForKeeper`) | Phase 317 |
| PROTO-03 | `## PROTO Additions` (`onlyFlipCreditors` keeper authz) | Phase 317 |
| PROTO-04 | `## PROTO Additions` + `## ADD Design — Do-Work Crank` (`batchPurchase` shape) | Phase 317 |
| PROTO-05 | `## PROTO Additions` (pinned `AF_KING` constant) | Phase 317 |
| CRANK-01 | `## ADD Design — Do-Work Crank` (do-work entry signatures + work-type encoding) | Phase 317 |
| CRANK-02 | `## ADD Design — Do-Work Crank` (`BatchAlreadyTaken` short-circuit) | Phase 317 |
| CRANK-03 | `## ADD Design — Do-Work Crank` (parameterless box cursor, OPEN-D) | Phase 317 |
| CRANK-04 | `## ADD Design — Do-Work Crank` (WWXRP zero reward) | Phase 317 |
| REW-01 | `## ADD Design — Do-Work Crank` (reward formula) + `## SPEC-Open Resolutions` (OPEN-B) | Phase 317 |
| REW-02 | `## ADD Design — Do-Work Crank` (one `creditFlip`/tx deferred mint) | Phase 317 |
| REW-03 | `## ADD Design — Do-Work Crank` (fixed `gasUnits`, never `gasleft()`) | Phase 317 |
| REW-04 | `## ADD Design — Do-Work Crank` (no caller restriction) | Phase 317 |
| SUB-01 | `## ADD Design — Subscription Sweep & Authorization` (pass-OR-pay gate) | Phase 317 |
| SUB-02 | `## ADD Design — Subscription Sweep & Authorization` (authorization) | Phase 317 |
| SUB-03 | `## ADD Design — Subscription Sweep & Authorization` (cursor sweep) | Phase 317 |
| SUB-04 | `## Quantity & Funding Model` (flat + reinvest% max-semantics) | Phase 317 |
| SUB-05 | `## Quantity & Funding Model` (funding waterfall) | Phase 317 |
| SUB-06 | `## Quantity & Funding Model` (two-tier skip-kill by pinned identity) | Phase 317 |
| SUB-07 | `## ADD Design — Subscription Sweep & Authorization` (lapsed/cancelled lifecycle) | Phase 317 |
| SUB-08 | `## ADD Design — Subscription Sweep & Authorization` (bounty = creditFlip, charge = burnForKeeper) | Phase 317 |
| **SUB-09** | `## Protocol-Owned Subs (SUB-09)` (init configs + permanent-deity free-renew) | **Phase 316 (SPEC-owned)** |
| RM-01 | `## REMOVE Footprint` (RM-01 afKing mode surface) | Phase 317 |
| RM-02 | `## REMOVE Footprint` (RM-02 free ETH auto-rebuy) + `## VRF-Freeze Obligation Retirement` | Phase 317 |
| RM-03 | `## REMOVE Footprint` (RM-03 BURNIE flip → flat 75bps) | Phase 317 |
| **RM-04** | `## REMOVE Footprint` (RM-04/PROTO-01 KEEP+EXPOSE) + `## Call-Graph Attestation` (4) | **Phase 316 (SPEC-owned)** |
| RM-05 | `## REMOVE Footprint` (RM-05 cross-contract cascade) | Phase 317 |
| RM-06 | `## Storage Slot-Shift Plan` (combined re-derivation) | Phase 317 |
| SAFE-01 | `## ADD Design — Do-Work Crank` (faucet locks: purchase-gate + gas-peg + coinflip-credit illiquidity; WWXRP 0) | Phase 318 |
| SAFE-02 | `## ADD Design — Do-Work Crank` (per-item `onlySelf`+try/catch non-brick) | Phase 318 |
| SAFE-03 | `## ADD Design — Subscription Sweep & Authorization` (cursor self-partition + `lastSweptDay`) | Phase 318 |
| SAFE-04 | `## VRF-Freeze Obligation Retirement` + `## JGAS-01 Decision Gate` (5) J5 freeze verdict | Phase 318 |
| GAS-01 | `## ADD Design — Do-Work Crank` (reserved gas-peg constants, worst-case-first) + `## JGAS-01 Decision Gate` (2) | Phase 319 |
| GAS-02 | `## ADD Design — Do-Work Crank` (one `creditFlip`/tx; one batch value transfer; read-once/batch) | Phase 319 |
| GAS-03 | `## ADD Design — Do-Work Crank` (calldata grouped by player; homogeneous fns) | Phase 319 |
| GAS-04 | `## ADD Design — Do-Work Crank` (no new hot-path storage) + `## Storage Slot-Shift Plan` | Phase 319 |
| GAS-05 | `## ADD Design — Do-Work Crank` (scavenger/skeptic against the security floor) | Phase 319 |
| GAS-06 | `## ADD Design — Do-Work Crank` (regression bounds; 0.5 gwei peg calibration deferred to Phase 319/OPEN-A) | Phase 319 |
| **JGAS-01** | `## JGAS-01 Decision Gate` (decision gate + design-intent + worst-case-first + footprint + J5 verdict) | **Phase 316 (SPEC-owned)** |
| JGAS-02 | `## JGAS-01 Decision Gate` (4) deletion footprint + `## Storage Slot-Shift Plan` (the −2 slot consequence) | Phase 317 |
| JGAS-03 | `## JGAS-01 Decision Gate` (3) correctness criteria @305-winner single-call | Phase 318 |
| JGAS-04 | `## JGAS-01 Decision Gate` (2) worst-case derivation (empirical measurement gate) | Phase 319 |

**Coverage:** 42/42 mapped (SPEC-owned: 4 · 317: 26 · 318: 5 · 319: 7 · 320 TERMINAL: re-attests all 42, owns 0). 0 unmapped; 0 duplicated. The **SAFE-* / GAS-*** designs are locked here as the safety/gas *properties* the ADD/REMOVE/JGAS sections must hold (e.g. SAFE-04 freeze maps to BOTH `## VRF-Freeze Obligation Retirement` AND the JGAS J5 verdict; GAS-* numeric calibration of the 0.5 gwei peg is deferred to Phase 319/OPEN-A); their primary verification owners are Phases 318/319.

## Success Criteria Coverage

The 5 ROADMAP Phase-316 success criteria, each mapped to the satisfying SPEC section(s) and marked **COVERED**:

| SC# | ROADMAP success criterion (abridged) | SPEC section(s) satisfying it | Status |
|-----|--------------------------------------|-------------------------------|--------|
| SC#1 | ADD design fully locked (do-work entries + work-type encoding, reward + reserved gas-peg + OPEN-B, `batchPurchase` shape + reentrancy, cursor sweep, authorization + pass gate, 5 PROTO sigs on pinned `AF_KING`) | `## ADD Design — Do-Work Crank` + `## ADD Design — Subscription Sweep & Authorization` + `## PROTO Additions` | **COVERED** |
| SC#2 | Quantity + funding model locked (flat min-1 COEXIST reinvest% via `max(...)`, claimable→pool→`InsufficientPool`-skip waterfall, two-tier skip-kill by un-spoofable pinned identity) | `## Quantity & Funding Model` | **COVERED** |
| SC#3 | Protocol-owned subs at init specified (SUB-09 sDGNRS + Vault configs; whale-pass-expiry renewal funding confirmed; "1 price lootbox" denomination resolved) | `## Protocol-Owned Subs (SUB-09)` + `## SPEC-Open Resolutions` | **COVERED** |
| SC#4 | REMOVE design + reconciliation locked (PROTO-01/RM-04 KEEP+EXPOSE, RM-01..06 footprint, slot re-derivation, VRF-freeze retirement) **AND the JGAS-01 jackpot-split-removal decision locked** (worst-case-first gas, gate resolved, footprint grep-verified across both modules, 305 ceiling preserved) | `## REMOVE Footprint` + `## Storage Slot-Shift Plan` + `## VRF-Freeze Obligation Retirement` **+ `## JGAS-01 Decision Gate`** | **COVERED** |
| SC#5 | Every cited file:line grep-verified against HEAD; zero "by construction" claims; keeper does NOT depend on anything RM-* deletes; zero `contracts/`/`test/` mutations | `## Call-Graph Attestation` | **COVERED** |

All 5 success criteria are COVERED by the assembled SPEC.

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

---

## JGAS-01 Decision Gate

JGAS-01 is the SPEC decision gate (owned by Plan 316-05) that authorizes — or withholds — the JGAS-02 IMPL deletion of the daily-ETH two-call jackpot split at Phase 317. The split removal is **enabled by RM-02** (the `## VRF-Freeze Obligation Retirement` section above): dropping the per-winner `autoRebuyState` SLOAD + `_processAutoRebuy` branch frees gas on the daily-ETH credit path, which is the headroom JGAS spends to fit all 305 winners in one call. JGAS ships in the SAME batched USER-APPROVED diff at Phase 317. This section is ordered deliberately per `feedback_design_intent_before_deletion` + `feedback_gas_worst_case`: **design intent → theoretical worst-case-first gas → locked decision → deletion footprint → VRF/freeze-SAFE verdict.** Every cited `file:line` across `DegenerusGameJackpotModule.sol`, `DegenerusGameAdvanceModule.sol`, and `DegenerusGameStorage.sol` was re-grep-verified against HEAD `MILESTONE_V45_AT_HEAD_62fb514b` on 2026-05-23 (`316-RESEARCH.md §J1`); the two cosmetic `+1` resume-check drifts are recorded below.

### (1) Design intent of the two-call split — traced BEFORE locking the deletion

Per `feedback_design_intent_before_deletion`, the original design intent + actor game-theory is traced first; only then is the deletion shape locked. The two-call ETH split is a **pure block-gas-ceiling workaround — NOT a correctness, fairness, EV, or determinism mechanism.**

- **The ceiling that forced it.** The daily ETH jackpot at max scale (`DAILY_JACKPOT_SCALE_MAX_BPS = 63_600` = 6.36×, JackpotModule `:248`) caps at `DAILY_ETH_MAX_WINNERS = 305` winners (`:227`) distributed across 4 trait buckets sized **159 / 95 / 50 / 1** (sum = 305; doc-comment `:226`). Crediting 305 cold winners in a single transaction was judged to risk the block gas limit at the time the split was authored — hence the chunking.
- **The split threshold.** `JACKPOT_MAX_WINNERS = 160` (`:219`) is the split-routing threshold: at the derivation site (`splitMode = (totalWinners <= JACKPOT_MAX_WINNERS) ? SPLIT_NONE : SPLIT_CALL1;`, `:480`) — `totalWinners ≤ 160 → SPLIT_NONE` (one call), else `SPLIT_CALL1` (two calls). Since the max-scale ceiling is 305 > 160, the busiest jackpot day always splits. `JACKPOT_MAX_WINNERS` is a *split-routing* threshold, NOT a winner-count cap (the cap is `DAILY_ETH_MAX_WINNERS = 305`).
- **How the split partitions.** The `call1Bucket` mask (decl `:1270`, build `:1272`/`:1274`/`:1276`, skip-routing `:1287-1288`) assigns **call 1 = largest bucket + solo bucket = 159 + 1 = 160 winners**, **call 2 = the two mid buckets = 95 + 50 = 145 winners** (arithmetic confirmed against `:246-247`). Call 1 writes `resumeEthPool = uint128(ethPool)` (`:1348`, gated by `splitMode == SPLIT_CALL1` at `:1347`); call 2 reads it back and zeroes it (`ethPool = uint256(resumeEthPool); resumeEthPool = 0;`, `:1252-1253`) before paying the skipped buckets.
- **What `resumeEthPool` carries.** **ONLY the total ETH pool amount — a single `uint128`.** The winner set, trait IDs, per-winner shares, and entropy are all **re-derived deterministically in call 2** by `_resumeDailyEth` (`:1186`, called at `:350`), which re-rolls the winning traits from the SAME held `randWord`. So `resumeEthPool` is the *only* cross-call storage carry; everything else is recomputed from the held VRF word — no semantic state crosses the call boundary except the pool remainder.
- **How advanceGame pauses and resumes.** Call 1 runs inside the fresh-daily-jackpot path; the NEXT `advanceGame` invocation sees the resume-check `if (resumeEthPool != 0)` (AdvanceModule `:453`) and runs call 2 (assigning `stage = STAGE_JACKPOT_ETH_RESUME`, `:455`). Thus **two separate bountied `advanceGame` transactions** complete one daily ETH jackpot whenever winners > 160.
- **Actor game-theory.** `advanceGame` is permissionless, gas-rebated via the escalating `bountyMultiplier` (1/2/4/6× of `ADVANCE_BOUNTY_ETH`, AdvanceModule `:244-256`) credited as coinflip-stake bounty. The split means the daily-jackpot completion is two bountied advance calls; collapsing to a single call merges those two bounties into one (a minor economic delta — slightly cheaper to fully advance — never a safety regression).
- **The clean precondition (locked).** Because call 2 re-derives the SAME winner set from the SAME held `randWord`, single-call and two-call produce **IDENTICAL payouts** — same winners, same per-winner amounts, same solo-bucket whale-pass treatment. **NO correctness / fairness / EV / determinism property is carried by the split; it is observationally equivalent to a single call modulo gas.** This is exactly the precondition `feedback_design_intent_before_deletion` requires before a deletion may be locked: the mechanism carries no semantic load beyond gas-fits.

### (2) Theoretical worst-case single-call gas — derived FIRST, before any reliance

Per `feedback_gas_worst_case`, the theoretical worst case is derived from source FIRST (max scale → max winners → all buckets in one call), not read off an existing benchmark. **This is a structural estimate (±30%), NOT a measurement** — which is precisely why the lock's *finality* is gated on the JGAS-04 empirical measurement (Phase 319).

- **The worst case enumerated.** Max scale `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600` → `DAILY_ETH_MAX_WINNERS = 305` winners across the 4 buckets (159 / 95 / 50 / 1), ALL credited in ONE call.
- **Per-cold-winner cost structure (post-RM-02).** For each new winner the single-call path costs: one cold SSTORE to `claimableWinnings[w]` (~22k gas: ~20k cold-zero-init + ~2.1k cold-account access) + one `PlayerCredited` event (~1.5k) + one `JackpotEthWin` event (~2-3k) ≈ **25-30k gas per cold-new winner**. Across 305 winners ≈ **7.6M-9.2M gas** for the winner-credit loop.
- **Fixed overhead.** 4× `_randTraitTicket` ticket-pool reads, bucket-share math, `bucketCountsForPoolCap`, the solo-bucket whale-pass path, and the prize-pool accounting SSTOREs (batched once per bucket, not per winner) ≈ **1-3M gas**.
- **Theoretical worst-case single-call ≈ 9-12M gas** vs a ~30M block gas limit → a **~2.5-3.3× margin**.
- **The enabling headroom (RM-02 frees ~1.3M).** RM-02 removes, per daily-ETH winner, the **unconditional cold `autoRebuyState[beneficiary]` SLOAD** (~4.2k gas — paid for every winner even when auto-rebuy is disabled, because the SLOAD precedes the enabled-branch test) plus the conditional `_processAutoRebuy` branch, from `_addClaimableEth`. Freed ≈ 4.2k × 305 ≈ **~1.3M gas** off the worst-case single-call total — the localized daily-ETH-path headroom JGAS spends to fit 305 winners in one call.
- **The observational-equivalence strengthener.** Single-call total ≈ call1(160-winner) work + call2(145-winner) work − (305 × the RM-02-freed SLOAD). **Today call 1 demonstrably pays 160 winners in ONE transaction under the block limit; single-call simply sums the SAME total work — call1 + call2 — into one transaction.** Since RM-02 *lowers* per-winner cost, the single-call total is strictly less than the current two-call total work. The open question is purely whether `call1_gas + call2_gas < block_limit`, which the ~2.5-3.3× structural margin says fits with comfort — but the absolute 9-12M figure is a ±30% structural estimate, not a measurement, so finality defers to JGAS-04.

### (3) The decision gate — resolved and LOCKED

**LOCKED DECISION (verbatim): "REMOVE pending JGAS-04 empirical confirmation, RETAIN-fallback documented".**

- **The 305-winner ceiling is PRESERVED.** This is a **mechanism-only removal at the SAME 305-winner ceiling** — **NO winner-count, NO bucket-scaling, NO payout-EV change.** `DAILY_ETH_MAX_WINNERS = 305` (`:227`), `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600` (`:248`), and the 159 / 95 / 50 / 1 bucket derivation (`bucketCountsForPoolCap` / `capBucketCounts`) are **NOT in the deletion set**. Only the split MECHANISM that chunks those same 305 winners across two calls is removed.
- **REMOVE is makeable AT SPEC.** The structural derivation (Section 2 — ~9-12M vs ~30M, ~2.5-3.3× margin) plus the observational-equivalence argument (the split already pays 160 + 145 winners in two txs that each fit) make REMOVE the locked design direction. JGAS-02 (Phase 317 IMPL) deletes the split in the same batched USER-APPROVED diff.
- **Finality is gated on JGAS-04.** Per `feedback_gas_worst_case`, the derived worst case must be measured before being relied upon. The lock's *finality* is therefore gated on **JGAS-04's Phase-319 empirical 305-winner single-call measurement** confirming `< block limit with margin`. This is a decision MAKEABLE at SPEC (REMOVE) with an empirical confirmation gate — **NOT blocked-until-measurement**.
- **RETAIN-fallback documented.** If JGAS-04 measures the single-call over (or uncomfortably near) the block limit, the IMPL reverts to KEEPING the split. This outcome is judged unlikely given the structural margin + the observational-equivalence argument, but the fallback is documented so the gate is honest.

### (4) Deletion footprint — enumerated and grep-verified across BOTH modules

The full footprint, with the `316-RESEARCH.md §J1` re-verified line numbers (re-grep-confirmed against HEAD on 2026-05-23). Inline-duplicated logic across modules is a recurring `DegenerusGameJackpotModule` hazard (`feedback_verify_call_graph_against_source`), so both modules are enumerated explicitly.

**`DegenerusGameJackpotModule.sol`:**
- `SPLIT_NONE` (`:197`), `SPLIT_CALL1` (`:199`), `SPLIT_CALL2` (`:201`) — the three `uint8 private constant` split-mode tags. DELETE all three.
- `JACKPOT_MAX_WINNERS = 160` (`:219`) — the split-threshold constant; its sole functional use is the threshold at `:480`. **DEAD on removal → DELETE.** (NOT a winner-count cap.)
- `resumeEthPool` reads/writes: the jackpot resume-check `if (resumeEthPool != 0)` (`:349`); the read at `:1201` (inside `_resumeDailyEth`); the read+zero `ethPool = uint256(resumeEthPool); resumeEthPool = 0;` (`:1252-1253`, call 2); the write `resumeEthPool = uint128(ethPool)` (`:1348`, call 1, gated by `:1347`). DELETE all.
- `_resumeDailyEth` function decl (`:1186`, called at `:350`) — DELETE.
- `splitMode` param (in `_processDailyEth`, `:1248`) + its routing (`:1251` `if (splitMode == SPLIT_CALL2)`, derivation locals `:476`/`:480`/`:501`) — DELETE the param + routing; collapse to the unconditional single-call path.
- `call1Bucket` mask: decl (`:1270`), build (`:1272`/`:1274`/`:1276`), skip-routing (`:1287-1288`) — DELETE.
- The split-threshold branch (`:476-483`) and the `_processDailyEth(... splitMode ...)` call that consumes it (`:493-503`) — collapse to the unconditional single-call.

**`DegenerusGameAdvanceModule.sol`:**
- `STAGE_JACKPOT_ETH_RESUME = 8` (`:70`) — DELETE the constant.
- Its single assignment (`stage = STAGE_JACKPOT_ETH_RESUME;`, `:455`) + the whole resume-check block `if (resumeEthPool != 0) { payDailyJackpot(true, lvl, rngWord); stage = STAGE_JACKPOT_ETH_RESUME; break; }` (`:453-456`) — DELETE the entire block.

**`DegenerusGameStorage.sol`:**
- `uint128 internal resumeEthPool;` (`:994`) — DELETE (enumerated here as a footprint item; the slot-shift CONSEQUENCE is cross-referenced below, not re-derived here).

**Two cosmetic `+1` resume-check drifts recorded** (the requirement text cites the leading comment line; the live `if` guard is +1): the jackpot resume-check cited at `:348` is the `if` at **`:349`** (comment at 348); the advance resume-check cited at `:452-455` is the block at **`:453-456`** (comment at 452). Both are cosmetic doc-vs-`if` offsets, not symbol drifts; all constants exact-match by value; no MISSING symbols (`316-RESEARCH.md §J1.2`).

**Stage numbers are NOT load-bearing** (`316-RESEARCH.md §J2`, verified three ways): `stage` is a function-local `uint8` (declared inside `advanceGame`, never written to a storage slot); `STAGE_JACKPOT_ETH_RESUME` is **only assigned (`:455`) and emitted** via the `Advance` event — ZERO `==` comparisons anywhere; and the `Advance` event is NOT consumed on-chain (the `gameAdvance()` wrappers in `DegenerusVault.sol` / `StakedDegenerusStonk.sol` only call advance, never read the stage). Consequently **renumbering 9 / 10 / 11 → 8 / 9 / 10 is OPTIONAL and cosmetic** — deleting constant 8 + its single assignment + the resume-check block is sufficient and behaviorally complete; the resume *mechanism* is driven by the `resumeEthPool != 0` storage read (`:453`), NOT by any stored stage number. Benign off-chain note: stage 8 will never be emitted post-removal (an observability-only `Advance`-event delta).

**Scope fence (confirmed).** No footprint item forces a winner-count / bucket-scaling / payout-EV touch — the deletion set is exactly the split MECHANISM (the `splitMode` / `resumeEthPool` / `STAGE_JACKPOT_ETH_RESUME` plumbing + the dead `JACKPOT_MAX_WINNERS` threshold), at the preserved 305-winner ceiling.

**Cross-reference — do NOT re-derive slots here.** Deleting `resumeEthPool` (slot 33, its OWN slot) compounds the RM-02 `autoRebuyState` (slot 19) deletion into a **combined −2 shift for the slot-≥34 region** (the `vrf*` / `lootboxRng*` family the v45 VRF work depends on — e.g. `lootboxRngWordByIndex` 38 → 36, `lootboxRngPacked` 37 → 35). That re-derivation is owned by the **`## Storage Slot-Shift Plan`** section above (316-02): one combined `forge inspect` pass on the post-(RM-02+JGAS) contract, file-by-file test `SLOT_*` rewrite, never a blind decrement. This section enumerates the `resumeEthPool` decl as a footprint item only and does NOT re-derive any slot.

### (5) VRF / freeze-invariant SAFE verdict — STATED, not assumed

`DegenerusGameAdvanceModule` is the VRF-rotation-sensitive module (the Phase 312 `a303ae18` detect-preserve-re-issue work lived here), so a stage-machine edit here is exactly the change class that can perturb the freeze invariant. Per `feedback_security_over_gas` + the v45 VRF-freeze north-star, the SAFE verdict is **STATED with its source trace**, not assumed (`316-RESEARCH.md §J5`).

**The setup, traced.** The daily ETH jackpot consumes the VRF-derived `randWord`. BOTH call 1 (`payDailyJackpot(true, lvl, rngWord)`, advance `:473`) and call 2 (`payDailyJackpot(...)` → `_resumeDailyEth(lvl, randWord)`, advance `:454` / jackpot `:350`) consume the **SAME `randWord`** — call 2 re-rolls the winning traits from the identical held word inside `_resumeDailyEth` (`:1186`). **The rng lock is HELD across the entire split:** the ETH-resume branch (`:453-456`) does **NOT** call `_unlockRng` — `rngLockedFlag` stays SET, `rngWordCurrent` stays non-zero, and the pool stays frozen across call 1 → next advanceGame → call 2. `_unlockRng` is called only at the coin-tickets stage (`:467`) and the phase-ended / non-jackpot transition paths (`:331` / `:402` / `:629`) — verified: the resume branch contains no `_unlockRng`.

**The four sub-points (locked):**
- **(a) Single-call collapses two same-word consumptions into one.** Today the held word is consumed twice (call 1 + call 2); single-call consumes it once. Fewer consumption points = a strictly simpler freeze surface, never weaker — and the word is still consumed *inside* the locked window (the daily jackpot still runs before `_unlockRng` at the coin-tickets stage).
- **(b) `_unlockRng` placement is UNCHANGED.** JGAS deletes the `resumeEthPool != 0` early-return branch (`:453-456`); the unlock still happens at the coin-tickets stage (`:467`). The unlock timing relative to VRF consumption does not move — removing the resume branch just means the daily-jackpot-then-coin-tickets sequence is one fewer advanceGame hop, with the lock still held continuously from request to the coin-tickets `_unlockRng`.
- **(c) No new player-mutable in-window input.** Single-call reads the same `traitBurnTicket[lvl]` pools and the same held `randWord` the split already read; no additional SLOAD of player-controllable state is introduced. RM-02 *removes* the `autoRebuyState` read (opposite direction). The `dailyHeroWagers[dailyIdx]` read is keyed on the frozen `dailyIdx` (written only at `_unlockRng`), unchanged by JGAS.
- **(d) No coupling between stage NUMBER and VRF unlock.** Resume is driven by the `resumeEthPool != 0` storage read, NOT by the emitted stage value (Section 4 / §J2). The VRF unlock is sequenced by the code path (the `_unlockRng` call site), not by any stored stage number. So deleting stage-constant 8 cannot perturb VRF sequencing — there is no stored-stage→unlock dependency to break.

**LOCKED VERDICT: JGAS is freeze-invariant-SAFE.** It removes a VRF-word RE-consumption point (two same-word reads → one) and a cross-tx `resumeEthPool` carry, does NOT move `_unlockRng`, introduces NO new in-window player-mutable input, and the stage-number deletion cannot perturb VRF sequencing. **The only residual risk is the gas-fits (liveness) question gated on JGAS-04 — NOT a freeze-invariant or RNG-manipulability concern.** Removing the cross-tx `resumeEthPool` carry is a **VRF-rotation-robustness IMPROVEMENT**: single-call completes the daily ETH jackpot in one atomic transaction with no cross-tx state carry to orphan, so it is **strictly less rotation-exposed** than the two-call split (which carries `resumeEthPool` across a tx boundary where an emergency rotation could intervene) — consistent with the Phase 312 `a303ae18` detect-preserve-re-issue work.

**AUDIT-320 re-attestation charge.** Phase 320 TERMINAL must re-attest that the freeze invariant holds **under the post-removal single-call path AND under emergency VRF rotation** (the `project_vrf_rotation_midday_orphan_index` surface — single-call must not orphan a mid-jackpot index, which it structurally cannot since there is no cross-tx carry). The final "does the stage-machine edit perturb the freeze invariant under rotation" check is routed to the **`zero-day-hunter` skill at AUDIT** (named here only; NOT run in this SPEC phase).

---

## Quantity & Funding Model

This section (Plan **316-03**, appended after the 316-01/02/05 sections above; those are untouched) locks the three open-item decisions whose wrong lock produces free-money or a trivially-dodgeable cancellation downstream: the subscription quantity model, the funding waterfall, and the two-tier skip-kill keyed on un-spoofable pinned-address identity. The crank/subscription end-state is on the in-tree `AfKing` keeper (the keeper's CURRENT live source is the MIXED transitional state recorded in the `## ADD Design — Subscription Sweep & Authorization` Keeper transitional-state caveat above — `subscribe(bool drainGameCreditFirst, uint8 dailyQuantity)` at keeper `:632` has **no `reinvestPct` yet**; this section locks the INTENDED end-state, NOT the current source). Every `file:line` was re-grep-verified against HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` on 2026-05-23 (SC#5).

### Quantity model — flat + reinvest% COEXIST max-semantics (SUB-04 / OPEN-F)

**LOCKED (overriding the replace instinct): COEXIST with max-semantics, NOT replace** (`PLAN-CRANK §12.6` OPEN-F RESOLVED, user 2026-05-23):

- **`effective = max(dailyQuantity, floor(claimable × reinvestPct / price))`** — the flat schedule is a floor; the reinvest% only *raises* the daily buy when its computed amount exceeds the flat schedule. Both inputs pack into **one flags byte + a `reinvestPct uint8`** in the `Sub`'s free bytes — **NO new storage slot** (the keeper rework at Phase 317 adds the `reinvestPct` field; the live `subscribe` sig at keeper `:632` is the pre-rework drift that lacks it).
- **`dailyQuantity` is `uint8`, MINIMUM 1 — flat = 0 is DISALLOWED** (cancel is the tombstone `setDailyQuantity(0)` path, SUB-07, NOT a zero-flat subscribe). Because the flat floor is always ≥ 1, there is **ALWAYS a ≥ 1-lootbox target every sweep**, so a "skip" is unambiguously "can't afford the scheduled buy." **There is no reinvest-rounds-to-0 no-op case** — the `floor(claimable × reinvestPct / price)` term can round to 0 on a dry/low-claimable day, but `max(…, dailyQuantity ≥ 1)` floors it back to the flat schedule, so the effective buy is never 0.

**Price-unit denomination (LOCKED).** `dailyQuantity` is **price-denominated: 1 unit = 1 `mintPrice` worth = one "1-price lootbox."** Source-grounded (keeper, re-verified at HEAD):
- `TICKET_SCALE = 400` (keeper `:387`); ticket mode computes `ticketQty = TICKET_SCALE * sub.dailyQuantity` (keeper `:1049`); lootbox mode computes `lootBoxAmt = cost` (keeper `:1063`) where `cost = (SUB_COST_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice()` (keeper `:678` / `:996`, `SUB_COST_ETH_TARGET` immutable at `:419`).
- The `TICKET_SCALE = 400` calibration makes `400 · qty · price / 400 == price · qty` — i.e. one unit of `dailyQuantity` resolves to exactly one `mintPrice` worth of spend in **both** ticket and lootbox mode. Therefore the **`max(dailyQuantity, floor(claimable × reinvestPct / price))` comparison is unit-consistent** — both sides are in price-units (the left side a flat count of 1-price lootboxes, the right side `claimable ÷ price` scaled by the reinvest fraction). `OPEN-F` denomination RESOLVED (also locked in the `## SPEC-Open Resolutions` "1 price lootbox" entry below, which points back here).

### Funding waterfall — the EXISTING `drainGameCreditFirst=true` model (SUB-05)

**LOCKED: reuse the EXISTING `drainGameCreditFirst` 3-case waterfall + InsufficientPool skip** — NO new funding mechanism, NO new flag (`PLAN-CRANK §12.6` RESOLVED). Per sweep, for a player with claimable credit `cred = claimableWinningsOf(player)` (keeper `:1077`) and scheduled spend `cost`:

- **Claimable** (`cred > cost`, keeper `:1078`) → fully covered by game credit, `msgValue = 0`.
- **Combined** (`1 < cred ≤ cost`) → spend `cred - 1` of credit + top up the remainder from the pool (`msgValue = cost - (cred - 1)`).
- **DirectEth** (`cred ≤ 1`) → pay the whole `cost` from the pool (`msgValue = cost`).
- **InsufficientPool skip** (`if (_poolOf[player] < msgValue)`, keeper `:288` reason 3) → the pool can't cover the pool-portion → **skip the player this sweep, emit `PlayerSkipped(player, 3)`, do NOT advance `lastSweptDay`** (retry next sweep). The 3-case branch interior is at keeper `:1068-1110` (verbatim comment block `:1068-1070`; the `if (!sub.drainGameCreditFirst)` gate at `:1073`; the `cred` read at `:1077`). CEI holds: `_poolOf[player] -= msgValue` (keeper `:1106`) → `purchase{value: msgValue}` (keeper `:1110`) → `sub.lastSweptDay = today` (keeper `:1115`) — debit-before-call, day-stamp-after. (`316-RESEARCH.md §1.12` cited the region as `1076-1108` with the debit at `:1104`; the live debit is at `:1106` — a benign ≤+2 cosmetic line drift, no symbol drift; the locked CEI ordering is exact.)

**Claimable-only = empty `_poolOf`, NO new flag (LOCKED).** A claimable-only sub (the protocol subs, SUB-09) is **not a new funding mode** — it is the SAME waterfall with an **empty `_poolOf` balance** (sDGNRS / Vault never deposit to the pool). With an empty pool, the waterfall degrades to **claimable-or-skip**: covered when `cred > cost` (Claimable case), else InsufficientPool-skips (the pool-portion is unfundable). No `claimableOnly` flag is added — "claimable-only" is an emergent property of a zero pool balance, which is exactly why it composes with the EXISTING waterfall for free.

**Transient lootbox-floor skip ≠ funding skip (distinguished, LOCKED).** A DISTINCT transient skip exists: `if (!sub.useTickets && cost < LOOTBOX_MIN)` → `PlayerSkipped(player, 4)` (keeper `:289` reason 4; the floor `LOOTBOX_MIN` immutable at `:451`; skip path at `:449`). This is a **lootbox-minimum-not-met** skip (the per-lootbox cost fell below the protocol's lootbox floor), NOT an InsufficientPool funding skip. The SPEC's skip-vs-kill logic (below) keys the **kill** on the FUNDING skip (`claimable + pool < cost`), NOT on the lootbox-floor transient — a lootbox-floor skip stays in the set and retries (it is a price-window condition, not a player-funding failure).

### Two-tier skip-kill — by un-spoofable pinned identity (SUB-06)

**LOCKED: NORMAL subs cancel on a funding skip; `Vault` + `sDGNRS` are EXEMPT keyed on the un-spoofable pinned `ContractAddresses.VAULT` / `SDGNRS` address identity — NEVER a player-settable flag** (`PLAN-CRANK §12.6` + `REQUIREMENTS.md SUB-06`):

- **NORMAL sub on a funding skip → CANCEL.** When a normal subscriber cannot fund the scheduled buy (`claimable + pool < cost` — the InsufficientPool funding skip, reason 3), the sweep **cancels the sub in-sweep via the existing swap-pop / auto-pause removal** (`_removeFromSet`, keeper `:707` / `:1013`; the auto-pause sets `dailyQuantity = 0` + removes the entry **WITHOUT `++i`** — the mover came from ahead of the cursor so it is already processed; nothing skipped or doubled). The owner's pool **dust stays withdrawable** (`withdraw()` reclaims any stranded `_poolOf` balance — the cancel moves the set membership, never the pool ETH); **re-subscribe resumes**.
- **`Vault` + `sDGNRS` are EXEMPT — a funding skip is TRANSIENT for them** (buy nothing this sweep, retry next sweep, persist in the set). Their claimable-only / empty-pool design (SUB-09) makes dry days NORMAL, not a cancellation signal — so a funding skip must NOT kill them.
- **The exemption MUST key on the un-spoofable pinned `ContractAddresses.VAULT` (`:37`) + `SDGNRS` (`:47`) address constants — a keeper-side branch comparing the swept `player` to those two pinned constants — and NEVER a player-settable flag.** A settable exemption flag is a **trivial cancellation dodge**: any normal sub could set the flag to dodge the funding-skip kill and persist as a free-retry sub forever (defeating the two-tier design's whole point). Pinned-address identity is un-spoofable (only the actual Vault / sDGNRS contract addresses match the constants); a settable flag is spoofable by construction. (`316-RESEARCH.md §5` "Two-tier skip-kill identity": the `VAULT` / `SDGNRS` constants ALREADY exist in `ContractAddresses.sol` at `:37` / `:47`; the keeper-side exemption branch is the new logic — note PROTO-05 separately adds the `AF_KING` keeper constant, a distinct anchor not used by this exemption.)
- **Renewal-lapse cancels BOTH tiers.** The monthly pass-OR-pay renewal-lapse path (the `paidThroughDay <= today` renewal branch failing to extend) still cancels the exempt protocol subs too — the exemption is ONLY from the FUNDING-skip kill, NOT from a genuine renewal lapse. (How the protocol subs free-renew through the renewal branch is the Task-2 user-decision, recorded in the `## Protocol-Owned Subs (SUB-09)` + `## SPEC-Open Resolutions` sections below.)

**Audit notes recorded (LOCKED):**
- **(a) Griefable ONLY at the funding margin.** A pool-funded NORMAL sub whose pool balance ≥ the scheduled `cost` is **never skipped regardless of sweep timing** — concurrent same-block callers self-partition via the cursor (SUB-03) and the per-entry `lastSweptDay` day-stamp is the idempotency backstop, so no sweep ordering can manufacture a spurious funding skip on a solvent sub. The kill only fires when funding genuinely cannot cover the buy.
- **(b) A claimable-only NORMAL sub (no pool) is FRAGILE BY DESIGN** — one dry day (no claimable winnings, empty pool) is a funding skip → cancels it. This is correct behavior (a normal sub with no funding source has nothing to buy with) but a UX trap. **Surface to players; consider a minimum-pool-at-subscribe** so a normal sub cannot accidentally configure a one-dry-day-cancels-it posture. (The protocol subs are EXEMPT from exactly this kill, which is why claimable-only is safe for THEM and fragile for a normal sub.)
- **(c) The kill REUSES the swap-pop path** (`_removeFromSet`, keeper `:707` / `:1013`) — it is the SAME removal machinery as the SUB-07 lapse/cancel reclaim, **distinct from the protocol-exempt transient skip** (which moves nothing and stays in the set). The kill is a set-membership removal; the exempt transient skip is a no-op-and-retry. They are different code paths on the same funding-skip trigger, branched on the pinned-identity exemption check.

---

## Protocol-Owned Subs (SUB-09)

This section (Plan **316-03**, appended after the 316-01/02/05 + Task-1 sections above; those are untouched) locks the SUB-09 protocol-owned-sub init configs — sDGNRS + Vault self-subscribe at init, replacing the `setAfKingMode` init that RM-05 deletes — and records the **Task-2 user-ratified whale-pass-expiry free-renew decision** that closes the SUB-09 funding loop. Every `file:line` was re-grep-verified against HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` on 2026-05-23 (SC#5).

### sDGNRS (`StakedDegenerusStonk`) protocol-sub init config (LOCKED)

The current init runs `game.claimWhalePass(address(0))` (`StakedDegenerusStonk.sol:360`) then `game.setAfKingMode(address(0), true, 10 ether, 0)` (`:361`, a multi-line call spanning `:361`+). **RM-05 deletes the `setAfKingMode` call** (and its local interface decl at `:13`); SUB-09 **REPLACES it with a keeper self-subscribe**:

- **Claimable-only funding** (no pool deposit → empty `_poolOf` → the SUB-05 waterfall degrades to claimable-or-skip; sDGNRS is EXEMPT from the SUB-06 funding-skip kill by pinned `ContractAddresses.SDGNRS` (`:47`) identity).
- **Lootbox mode** (`useTickets = false` — the default), **`dailyQuantity = 1`** (flat floor of one 1-price lootbox per sweep, the minimum-1 invariant from the `## Quantity & Funding Model` SUB-04 lock), **`reinvestPct = 2%`** (the COEXIST max-semantics term — on a high-claimable day the reinvest term `floor(claimable × 2% / price)` can raise the daily buy above the flat-1 floor; on a dry day `max(…, 1)` floors back to the flat-1 schedule).
- **PLUS `setCoinflipAutoRebuy(self, true, 0)`** — the BURNIE-flip auto-rebuy with `takeProfit = 0` (full recycle, the v47-KEPT path at the flat `RECYCLE_BONUS_BPS = 75` post-RM-03-collapse rate). The `setCoinflipAutoRebuy` interface is the same shape sStonk/Vault already wrap (`DegenerusVault.sol:78` `setCoinflipAutoRebuy(address player, bool enabled, uint256 takeProfit)`; Vault's `coinSetAutoRebuy` wrapper at `:685` → `:686` is the precedent call shape). `takeProfit = 0` = recycle every BURNIE flip win back into stake (no profit skim), maximizing the protocol-sub's BURNIE flip recycling.
- **Re-claim site preserved.** The public `gameClaimWhalePass()` re-claim at `StakedDegenerusStonk.sol:404` (`game.claimWhalePass(address(0))`) is **NOT in the removal scope** — it stays, and is the on-chain re-claim entry distinct from the `:360` init claim.

### Vault (`DegenerusVault`) protocol-sub init config (LOCKED)

The Vault has a `gameClaimWhalePass()` (`DegenerusVault.sol:581`, `onlyVaultOwner`) → `gamePlayer.claimWhalePass(address(this))` (`:582`). SUB-09 adds a **self-subscribe at init**:

- **Claimable-only funding** (same empty-`_poolOf` degrade-to-claimable-or-skip; Vault is EXEMPT from the SUB-06 funding-skip kill by pinned `ContractAddresses.VAULT` (`:37`) identity).
- **`dailyQuantity = 1`** (flat-1, same minimum-1 invariant), **`reinvestPct = 0`** (NO reinvest — the Vault buys a flat one 1-price lootbox per sweep, never scaling with claimable), **NO BURNIE rebuy** (no `setCoinflipAutoRebuy` call — distinct from sDGNRS which DOES wire the flip auto-rebuy).

### Both self-subscribe via the SUB-02 self-consent path (LOCKED)

Both protocol subs self-subscribe with **`player == msg.sender`** (the SUB-02 authorization self-consent base case — no operator-approval check, since the subscribing contract IS the player). This is the same `_resolvePlayer`-mirror self-consent path the `## ADD Design — Subscription Sweep & Authorization` SUB-02 section locks; the protocol contracts call `subscribe` on their own behalf at init.

### Whale-pass-expiry free-renew — Task-2 USER-RATIFIED DECISION (recorded VERBATIM)

The SUB-09 design says the protocol subs "free-renew via their Whale pass," but `claimWhalePass(player)` (`DegenerusGameWhaleModule.sol:1004`) early-returns a NO-OP when `whalePassClaims[player] == 0` (`:1007` `if (halfPasses == 0) return;`) — it only EXTENDS the freeze when there are queued half-passes, and does NOT self-renew indefinitely. The renewal-funding mechanism is therefore a genuine user-OPEN (RESEARCH §5/§9-Q1). **Task 2 was a `checkpoint:decision` gate; the user RATIFIED the decision on 2026-05-23.**

**USER-SELECTED OPTION: `permanent-deity` (Permanent Deity bit), with NO additional caveats.**

**Verbatim meaning (recorded as the SUB-09 free-renew mechanism):** the protocol-owned subs (sDGNRS + Vault) free-renew by relying on the **permanent Deity bit (`HAS_DEITY_PASS_SHIFT = 184`, `libraries/BitPackingLib.sol:71`, never expires)** being set on the pinned VAULT / SDGNRS addresses. Because `_hasAnyLazyPass` (`DegenerusGame.sol:1610`) returns `true` as soon as the Deity bit is set (`:1612` `if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return true;`), the PROTO-01-exposed `hasAnyLazyPass(address)` view returns **true permanently** for those two addresses → the keeper's monthly pass-OR-pay renewal branch (the `paidThroughDay <= today` gate) takes the **free pass-extend** path forever, at **zero per-renewal cost** and with **no BURNIE funding stream**. This is the simplest invariant and is the closure of the SUB-09 free-renew loop.

**MATERIAL SOURCE FINDING (grep-verified at HEAD, strengthens the decision): the permanent Deity bit is ALREADY SET on both pinned addresses in the live `DegenerusGame` constructor — no NEW bit-setting contract change is required.** The constructor (`DegenerusGame.sol:216`) already runs, with the comment "Vault addresses get deity-equivalent score boost (no symbol, not in deityPassOwners)":
- `mintPacked_[ContractAddresses.SDGNRS] = BitPackingLib.setPacked(..., HAS_DEITY_PASS_SHIFT, 1, 1);` (`DegenerusGame.sol:222`)
- `mintPacked_[ContractAddresses.VAULT] = BitPackingLib.setPacked(..., HAS_DEITY_PASS_SHIFT, 1, 1);` (`DegenerusGame.sol:223`)

So the Phase 317 IMPL obligation is **NOT "add a Deity-bit setter"** (the planner's Task-2 option-cons assumed a new write); it is the WEAKER obligation **"rely on the existing `:222`/`:223` constructor grant + verify that grant survives byte-unmodified through the batched ADD+REMOVE diff"** (the grant sits in the same constructor RM-05/RM-02 edit nearby — it MUST NOT be perturbed). PROTO-01's `hasAnyLazyPass` exposure is what makes the existing bit reachable to the keeper's renewal gate. This is recorded so the IMPL does not author a redundant Deity-bit write and so the AUDIT re-verifies the existing grant's survival.

**Ratified side-effect (T-316-12 Elevation, accept-with-condition):** the user RATIFIES — with eyes open — that the Deity bit also grants the pinned protocol addresses the full **Deity pass utility (trait/gold score boost)** as a side effect. This is already the live behavior (the `:221` comment "deity-equivalent score boost" + the `:1435` / `:2270` Deity-holder branches that read the same bit), so `permanent-deity` introduces NO NEW side-effect beyond what the constructor already grants; the decision is to RETAIN it, not to add it. Accepted per threat-register **T-316-12** (Elevation → accept-with-condition).

**AUDIT routing (named here only; NOT run in this SPEC phase):** because `permanent-deity` has **zero per-renewal cost**, there is **no BURNIE funding stream to close** — so the planner's "funding-model-closure check routed to `economic-analyst` at AUDIT" is re-framed as: route to the **`economic-analyst` skill at AUDIT (Phase 320)** the validation that granting a permanent Deity bit to the pinned protocol addresses introduces **NO economic distortion** — specifically (a) that the trait/gold side-effect utility accruing to non-player contract addresses (SDGNRS / VAULT) does not skew the protocol's score/gold economy, and (b) that two permanently-`hasAnyLazyPass = true` protocol addresses do not skew any pass-gated EV or gating. The skill is **named, not run** in this SPEC phase.

---

## SPEC-Open Resolutions

This section (Plan **316-03**, appended after the SUB-09 section above; those are untouched) resolves the remaining SPEC-open items with HEAD-verified source citations: OPEN-B (price-unavailable → reward 0), OPEN-C (CEI/reentrancy lean), the "1 price lootbox" denomination, the claimable-only confirmation, and the `JackpotEthWin` ABI-break note. Every `file:line` was re-grep-verified against HEAD on 2026-05-23 (SC#5). (The whale-pass-expiry renewal funding — the largest SPEC-open — is resolved in the `## Protocol-Owned Subs (SUB-09)` section above as the Task-2 user-ratified `permanent-deity` decision; this section cross-references it rather than re-stating it.)

### OPEN-B — price-unavailable → reward 0, NEVER revert (LOCKED)

**LOCKED disposition: reward → 0, never revert the settlement, via the guarded `_ethToBurnieValue` idiom.** The crank reward conversion reuses `_ethToBurnieValue(amountWei, priceWei)` (`contracts/modules/DegenerusGameMintModule.sol:1412`), whose first statement guards `if (amountWei == 0 || priceWei == 0) return 0;` (`:1416`) before computing `(amountWei * PRICE_COIN_UNIT) / priceWei`. A bad / zero price therefore yields **reward 0 and never reverts** the crank/sweep settlement (a reverting reward path would let a transient bad price brick the whole crank — the OPEN-B failure mode this lock forecloses).

**Secondary structural guarantee:** if the reward instead pegs to `PriceLookupLib.priceForLevel(uint24)` (`contracts/libraries/PriceLookupLib.sol:21`, `pure`), that function **never returns 0** (every branch returns ≥ 0.01 ether), so div-by-zero is structurally impossible regardless of the guard. **The chosen disposition is the guarded `_ethToBurnieValue` form** (it additionally defends a future `mintPrice()`-sourced price, which `priceForLevel` does not), with the non-zero `priceForLevel` invariant cited as the secondary backstop. (This is the same OPEN-B disposition the `## ADD Design — Do-Work Crank` REW-01 section locks at the reward-path level; this entry is the SPEC-open-owned final prose, consistent with it.) Relevant skill: **none external — pure arithmetic.**

### OPEN-C — reentrancy = CEI-proof lean, with the IMPL/AUDIT trace requirement (LOCKED)

**LOCKED lean: CEI-proof, no new `nonReentrant` guard, WITH a mandatory IMPL trace + guard-fallback.** `DegenerusGame` has **no `ReentrancyGuard` / `nonReentrant` modifier anywhere**; protection is **CEI throughout** — e.g. `claimablePool -= uint128(payout); // CEI: update state before external call` (`DegenerusGame.sol:1408`), ETH sends via `.call{value: …}` at `:2005` / `:2022` / `:2043`. The keeper's existing per-player loop already does CEI (pool debit `_poolOf[player] -= msgValue` at keeper `:1106` BEFORE the external `purchase{value}` at `:1110`; the `lastSweptDay = today` day-stamp at `:1115` AFTER). `batchPurchase`'s per-player try/catch + slice-refund + a once-at-entry batch debit + a post-loop day-stamp should satisfy "no double-buy via a reentrant sweep/cancel" without a new guard.

**Mandatory IMPL/AUDIT obligation (NOT optional):** the Phase 317 IMPL MUST trace the full **mint → lootbox → prize-pool → EV-cap → quest** callback chain for any external call that re-enters before the day-stamp, and **add an explicit reentrancy guard ONLY IF a re-entrant path is found.** This CEI-vs-guard proof — alongside `burnForKeeper` / `creditFlip` authority, the highest-scrutiny ADD surface — is routed to the **`contract-auditor` skill at IMPL/TST (Phase 317/318)**. (Named here only; NOT run in this SPEC phase. This entry is co-owned with the `## ADD Design — Do-Work Crank` OPEN-C disposition above and is consistent with it.)

### "1 price lootbox" denomination (LOCKED — points to the Task-1 quantity lock)

**LOCKED: `dailyQuantity` is price-denominated — 1 unit = 1 `mintPrice` worth = one "1-price lootbox."** Source-grounded by `TICKET_SCALE = 400` (keeper `:387`): ticket mode computes `ticketQty = TICKET_SCALE × dailyQuantity` (keeper `:1049`), lootbox mode computes `lootBoxAmt = cost` where `cost = (SUB_COST_ETH_TARGET × PRICE_COIN_UNIT) / mintPrice()` — the `400` calibration makes `400 · qty · price / 400 == price · qty`, so one unit of `dailyQuantity` resolves to exactly one `mintPrice` worth of spend in BOTH modes, and the SUB-04 `max(dailyQuantity, floor(claimable × reinvestPct / price))` comparison is unit-consistent (both sides price-units). **The full denomination derivation is locked in the `## Quantity & Funding Model` → "Price-unit denomination (LOCKED)" subsection above (Task 1);** this entry records that the OPEN denomination item is RESOLVED and points back to that lock (no duplicate derivation here).

### Claimable-only confirmation (LOCKED — no new flag)

**CONFIRMED: claimable-only is an EMERGENT property of an empty `_poolOf` balance, NOT a new funding flag.** A claimable-only sub (the SUB-09 protocol subs) never deposits to `_poolOf`, so the SUB-05 `drainGameCreditFirst` waterfall degrades to claimable-or-skip with **no `claimableOnly` flag added** — this is why it composes with the EXISTING waterfall for free. The full claimable-only lock is in the `## Quantity & Funding Model` → "Claimable-only = empty `_poolOf`, NO new flag (LOCKED)" subsection above (Task 1); this entry confirms the SUB-09 protocol subs (sDGNRS = claimable-only flat-1 + 2% reinvest + `setCoinflipAutoRebuy(self,true,0)`; Vault = claimable-only flat-1 no-reinvest) ride exactly that emergent claimable-only path, consistent with it.

### `JackpotEthWin` event ABI-break note (delta only — OUT OF SCOPE for this milestone)

**RECORDED as a delta note, NOT an in-scope fix.** RM-02's removal of `_processAutoRebuy` / `_calcAutoRebuy` makes the `JackpotEthWin` event's (decl `DegenerusGameJackpotModule.sol:69`) `rebuyLevel` (`:75`) / `rebuyTickets` (`:76`) fields dead, so the event signature CHANGES (a breaking topic-hash / field-set delta). This is a **benign ABI break for the off-chain indexer**, which is a separate frontend track explicitly OUT OF SCOPE for this milestone (RESEARCH §9-Q3). The full ABI-break delta is locked in the `## VRF-Freeze Obligation Retirement` → "ABI break — `JackpotEthWin` event signature change" subsection above (316-02); this entry records that the SPEC-open "what about the event consumers?" item is RESOLVED as out-of-scope (frontend indexer track), pointing back to that delta note.

---

## Call-Graph Attestation

This section (Plan **316-04**, the LAST plan; appended after all the 316-01/02/03/05 design sections above, which are untouched) is the **SC#5 deliverable**: every `file:line` the SPEC's design sections actually cite — across `DegenerusGame` + modules + `BurnieCoin`/`BurnieCoinflip`/`DegenerusVault`/`StakedDegenerusStonk`/`ContractAddresses` + the in-tree `StreakKeeperV2`→`AfKing` keeper, **now including the JGAS two-module footprint** the `## JGAS-01 Decision Gate` section cites — was re-grep-verified against contract HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801` on 2026-05-23, with a **MATCH / DRIFT / MISSING** verdict per row. The verification substrate is `316-RESEARCH.md §1` (the full RM verification table) + `§J1` (the JGAS two-module footprint table) — embedded/referenced here rather than re-tabulated verbatim row-by-row; this section's job is to (a) record the every-row-covered verdict, (b) enumerate the DRIFT/MISSING items explicitly so the SPEC carries no unverified call-graph claim, and (c) re-state the load-bearing keeper-dependency clean result + the J5 VRF/freeze verdict.

> **Attestation statement (SC#5):** Every `file:line` cited by the SPEC's design sections was grep-verified against HEAD; the SPEC asserts no unverified "by construction" / "single fn reaches all paths" claim — the only such phrasing in this document is inside this explicit negation sentence and the quoted `feedback_verify_call_graph_against_source` reference. All citations are either MATCH, or a recorded DRIFT (live line locked, doc offset noted), or a recorded MISSING (resolves an open). This table is what the plan-checker and Phases 317/318/319/320 trust.

### Verdict roll-up — coverage by source file

| Source surface | RESEARCH substrate | Verdict roll-up |
|----------------|--------------------|-----------------|
| `DegenerusGame.sol` (RM-01 afKing surface + `_hasAnyLazyPass` reader-set) | §1.1, §2 | all 23 rows ✓ MATCH (13 fn decls + 3 events + 1 error + 3 consts + 2 cross-calls + 2 readers — re-grepped at HEAD: `setAutoRebuy :1495`, `setAfKingMode :1559`, `_setAfKingMode :1569`, `_hasAnyLazyPass :1610`, `afKingModeFor :1624`, `syncAfKingLazyPassFromCoin :1654`, `_deactivateAfKing :1670`, readers `:1580`/`:1660`, ctor Deity grant `:222`/`:223`) |
| `storage/DegenerusGameStorage.sol` | §1.2, §4, §J3 | ✓ MATCH (`struct AutoRebuyState :910`, `autoRebuyState :926` forge slot 19; `resumeEthPool :994` forge slot 33) |
| `modules/DegenerusGameJackpotModule.sol` (RM-02 + JGAS) | §1.3, §J1.1 | mostly ✓ MATCH; **2 cosmetic DRIFTs** (auto-rebuy block +2, jackpot resume-check +1 — below) |
| `modules/DegenerusGamePayoutUtils.sol` (RM-02) | §1.4 | ✓ MATCH (`_calcAutoRebuy :51`, `struct AutoRebuyCalc :19`, selector `:83`, entropy roll `~70`) |
| `modules/DegenerusGameAdvanceModule.sol` (JGAS + bounty idiom) | §1.10, §J1.2, §J2 | ✓ MATCH on all constants; **1 cosmetic DRIFT** (advance resume-check +1 — below) |
| `BurnieCoinflip.sol` (RM-03) | §1.5 | ✓ MATCH (incl. the `RECYCLE_BONUS_BPS=75 :129` KEEP vs `AFKING_RECYCLE_BONUS_BPS=100 :130` DELETE value distinction, re-confirmed at HEAD) |
| `interfaces/IDegenerusGame.sol` (RM-05) | §1.6 | ✓ MATCH on the 4 removed decls; **1 MISSING** (setAutoRebuy/TakeProfit/AfKingMode NOT here — resolves an open, below) |
| `interfaces/IBurnieCoinflip.sol` (RM-05 + PROTO-03) | §1.7 | ✓ MATCH (`settleFlipModeChange :85` REMOVE; `creditFlip :115` + `creditFlipBatch :122` ALREADY present — PROTO-03 needs no new decl) |
| `DegenerusVault.sol` (RM-05) | §1.8 | ✓ MATCH (`gameSet* :627/:634/:643` REMOVE; `coinSet* :685/:692` KEEP; self-subscribe site) |
| `StakedDegenerusStonk.sol` (RM-05 + SUB-09) | §1.9 | ✓ MATCH (`setAfKingMode` decl `:13` + init `:361` REMOVE; re-claim `:404` KEEP) |
| `ContractAddresses.sol` (PROTO-05 + SUB-06 identity) | §5 | ✓ MATCH (`VAULT :37`, `SDGNRS :47` already pinned; `AF_KING` ADD by PROTO-05) |
| `libraries/PriceLookupLib.sol` / `BitPackingLib.sol` (OPEN-B + pass-bits + Deity free-renew) | §2, §5 | ✓ MATCH (`priceForLevel :21` pure non-zero; `HAS_DEITY_PASS_SHIFT=184 :71`, `FROZEN_UNTIL_LEVEL_SHIFT=128 :63`) |
| `modules/DegenerusGameMintModule.sol` (REW-01 OPEN-B) | §1.10 | ✓ MATCH (`_ethToBurnieValue :1412` guarded zero-return) |
| `StreakKeeperV2.sol`→`AfKing` keeper | §1.12, §2, §3 | dependency CLEAN (below); transitional-state DRIFTs recorded (below); only game coupling = `hasAnyLazyPass :671/:974` |

**Re-verification freshness:** the milestone has not mutated source yet (`git diff --name-only -- contracts/ test/` is empty at HEAD), so the §1 + §J1 tables hold. A representative spread was re-grepped at attestation time: the JGAS anchors (`SPLIT_NONE :197`, `STAGE_JACKPOT_ETH_RESUME=8 :70`, `resumeEthPool` storage `:994`, jackpot resume-check `:349`, advance resume-check `:453-456`), the RM anchors (`_hasAnyLazyPass :1610` + readers `:1580/:1660`, `AutoRebuyState :910`/`autoRebuyState :926`, `_processAutoRebuy :822`, `RECYCLE_BONUS_BPS=75 :129`), and the keeper-dependency grep — all consistent with the embedded tables.

### (1) RM drift items recorded (cosmetic line offsets — live line locked)

- **DRIFT (+2, cosmetic):** JackpotModule `_addClaimableEth` auto-rebuy block — `PLAN-V47` claimed `798–806`; **live = `800–808`** (the `AutoRebuyState memory state = autoRebuyState[beneficiary];` cold SLOAD at `:801`). The locked range is `800–808`. (`316-RESEARCH.md §1.3`.)
- **DRIFT (interior offset, cosmetic):** DegeneretteModule `_distributePayout` frozen-pool solvency check — decl at `:705`, the revert-on-insufficient-solvency check at **`~738`** (inside the body); `PLAN-CRANK §8`'s "742" is a slightly-off interior offset. The locked anchors are decl `:705` / check `~738`. (`316-RESEARCH.md §1.11`.)
- **MISSING (resolves an open):** `setAutoRebuy` / `setAutoRebuyTakeProfit` / `setAfKingMode` are **NOT declared in `IDegenerusGame.sol`** — the doc's "verify whether present" resolves to MISSING here. They ARE declared in `DegenerusVault.sol`'s **local** interface (`:47`/`:49`/`:51`), which RM-05 removes. This is the resolution to `PLAN-V47 §5.6`'s open verify. (`316-RESEARCH.md §1.6`.)

### (2) JGAS footprint attestation (embedding `316-RESEARCH.md §J1`)

The JGAS two-call-split deletion surface (cited by the `## JGAS-01 Decision Gate` section) — every constant **exact-match by value** at HEAD:

| Symbol | Live anchor | Verdict | Removal note |
|--------|-------------|---------|--------------|
| `SPLIT_NONE` / `SPLIT_CALL1` / `SPLIT_CALL2` | JackpotModule `:197` / `:199` / `:201` | ✓ MATCH | DELETE all three split-mode tags |
| `JACKPOT_MAX_WINNERS = 160` | JackpotModule `:219` (sole functional use = threshold `:480`) | ✓ MATCH | **DEAD on removal → DELETE** (split-routing threshold, NOT a winner-count cap) |
| `resumeEthPool` storage | `storage/DegenerusGameStorage.sol:994`, forge **slot 33** (own slot) | ✓ MATCH | DELETE (the −2 slot-shift consequence is owned by `## Storage Slot-Shift Plan`) |
| `resumeEthPool` reads/writes | jackpot resume-check `:349`, read `:1201`, read+zero `:1252-1253`, write `:1348` (gated `:1347`) | ✓ MATCH (resume-check +1 drift below) | DELETE all |
| `_resumeDailyEth` | JackpotModule `:1186` (called `:350`) | ✓ MATCH | DELETE |
| `splitMode` param + routing | JackpotModule `:1248`; derivation locals `:476`/`:480`/`:501`; `:1251` | ✓ MATCH | DELETE param + routing; collapse to single-call |
| `call1Bucket` mask | JackpotModule decl `:1270`, build `:1272/:1274/:1276`, skip-routing `:1287-1288` | ✓ MATCH | DELETE |
| split-threshold branch | JackpotModule `:476-483` + `_processDailyEth(...)` call `:493-503` | ✓ MATCH | collapse to unconditional single-call |
| `STAGE_JACKPOT_ETH_RESUME = 8` | AdvanceModule `:70` | ✓ MATCH (value=8 exact) | DELETE constant |
| stage assignment + resume-check block | AdvanceModule `:455` (assign) + `:453-456` (whole block) | ✓ MATCH (block +1 drift below) | DELETE the entire block |

- **Two cosmetic `+1` JGAS resume-check DRIFTs recorded:** the jackpot resume-check the requirement cites at `:348` is the `if` guard at **`:349`** (comment at 348); the advance resume-check cited at `:452-455` is the block at **`:453-456`** (comment at 452). Both are the requirement citing the leading comment line, not the `if`/block — cosmetic doc-vs-`if` offsets, **no symbol drift, no MISSING symbol** (`316-RESEARCH.md §J1.2`).
- **PRESERVED (NOT in the deletion set):** `DAILY_ETH_MAX_WINNERS = 305` (`:227`), `DAILY_JACKPOT_SCALE_MAX_BPS = 63_600` (`:248`), and the 159/95/50/1 bucket derivation. JGAS removes only the split MECHANISM at the same 305-winner ceiling — zero winner-count / bucket-scaling / payout-EV change.
- **Stage numbers are NOT load-bearing** (`316-RESEARCH.md §J2`): `stage` is a function-local `uint8` (never stored); `STAGE_JACKPOT_ETH_RESUME` is only ASSIGNED (`:455`) and EMITTED via the `Advance` event — zero `==` comparisons; the `Advance` event is not consumed on-chain. Renumbering 9/10/11 → 8/9/10 is OPTIONAL/cosmetic.

### (3) JGAS J5 VRF / freeze-SAFE verdict (HEADLINE — re-stated as attestation)

Re-stated here (full trace in `## JGAS-01 Decision Gate` section (5), substrate `316-RESEARCH.md §J5`) so the attestation carries the security verdict:

- The ETH-resume branch (`:453-456`) **never calls `_unlockRng`** — the rng lock is HELD across the entire split (call 1 → next advanceGame → call 2), and the **same `randWord` is re-consumed in call 2** (`_resumeDailyEth` re-rolls the winning traits from the identical held word).
- Single-call **collapses two same-word consumptions into one**; `_unlockRng` placement is **UNCHANGED** (still the coin-tickets stage `:467`); **no new in-window player-mutable input** is introduced (RM-02 *removes* the `autoRebuyState` read — opposite direction); the stage-number deletion **cannot perturb VRF sequencing** (resume is driven by the `resumeEthPool != 0` storage read, not by any stored stage value).
- **VERDICT: JGAS is freeze-invariant-SAFE.** It removes a VRF-word re-consumption point AND a cross-tx `resumeEthPool` carry → a **VRF-rotation-robustness IMPROVEMENT** (single-call completes the daily ETH jackpot in one atomic tx with no cross-tx state to orphan, strictly less rotation-exposed than the two-call split, consistent with the Phase 312 `a303ae18` detect-preserve-re-issue work). **The only residual risk is the gas-fits (liveness) question, gated on JGAS-04** (Phase 319) — NOT a freeze-invariant or RNG-manipulability concern. **AUDIT-320 re-attests** the freeze invariant under the single-call path AND under emergency VRF rotation.

### (4) Keeper-dependency CLEAN result (the load-bearing RM/JGAS deletion-safety attestation)

**Zero-match grep over the full RM-symbol set, re-run at HEAD.** `StreakKeeperV2.sol` matches **ZERO** of the RM-deletion symbols (`syncAfKingLazyPassFromCoin` / `afKingModeFor` / `afKingActivatedLevelFor` / `setAfKingMode` / `deactivateAfKingFromCoin` / `setAutoRebuy` / `setAutoRebuyTakeProfit` / `autoRebuyState` / `AutoRebuyState` / `_processAutoRebuy` / `_calcAutoRebuy` / `settleFlipModeChange` / `_afKingRecyclingBonus` / `_afKingDeityBonus` / `gameSetAutoRebuy` / `gameSetAfKingMode`). The keeper **also matches ZERO** of the JGAS symbols (`SPLIT_*` / `resumeEthPool` / `STAGE_JACKPOT_ETH_RESUME` / `_resumeDailyEth` / `call1Bucket` / `splitMode`) — those are jackpot/advance-module-internal and the keeper never references them.

- **The keeper's ONLY game-side coupling is `hasAnyLazyPass(player)`** — the kept-and-exposed PROTO-01 view — at keeper `:671` (subscribe gate) and `:974` (monthly-renewal sweep gate). The lazy-pass *sync* (`syncAfKingLazyPassFromCoin`) the input doc worried about is a coinflip↔game internal and is NOT used by the keeper.
- **The deletion is dependency-safe IFF PROTO-01 ships in the SAME batched Phase-317 diff.** With the rename shipping alongside the deletion, the keeper's pass gate survives RM-* unchanged.
- **PROTO-side keeper interface obligation (recorded):** the keeper still calls `IBurnie.pullForKeeper` / `mintForKeeper` against `BurnieCoin`, which has NEITHER yet (deferred-selector by design); **PROTO-02 adds `burnForKeeper`** and the keeper IMPL (Phase 317, utilities side) switches its calls. This is a PROTO-side interface obligation, NOT an afKing-deletion dependency.

### (5) Keeper transitional-state caveat (Pitfall 1 — record explicitly)

The keeper's CURRENT live source is a **MIXED transitional state** that does NOT match `PLAN-CRANK §9`'s claimed post-rework state. `316-RESEARCH.md §1.12` re-verified live source vs §9: **19× `pullForKeeper`, 5× `mintForKeeper`, only 2× `creditFlip`**, the OLD caller-supplied `sweep(uint256 startIdx, uint256 count)` loop, `subscribe(bool drainGameCreditFirst, uint8 dailyQuantity)` (no `reinvestPct`), and **NO `sweepCursor` / `reinvestPct` / `windowPaid`** anywhere. Therefore `PLAN-CRANK §9` "done this session (compile-verified)" is **FALSE vs live source** — the cursor / reinvestPct / windowPaid / `batchPurchase` switch / `pull→burn` rename / full `creditFlip` are genuinely unbuilt. **This SPEC locks against the INTENDED end-state for Phase 317 IMPL, NOT the current keeper source.** Recorded so the plan-checker does NOT treat §9 "done this session" as ground truth.

### (6) Box-cursor VRF-rotation-orphan-index landmine (Pitfall 3 — the single biggest ADD-side design risk)

The OPEN-D box cursor's enqueue/dequeue is keyed on the lootbox `index`, which re-couples it to the **v45 VRF-rotation orphan-index keyspace** (`project_vrf_rotation_midday_orphan_index`): an emergency VRF coordinator rotation can orphan an in-flight mid-day lootbox index. **The box cursor MUST follow the v45 `a303ae18` detect-preserve-re-issue path** (re-issue an in-flight `lootboxRngWordByIndex[N]` request on the new coordinator rather than orphaning it). This is the milestone's single biggest design landmine; the AUDIT phase (320) re-verifies the freeze invariant holds under emergency rotation WITH the new box cursor present. (Full lock in the `## ADD Design — Do-Work Crank` → OPEN-D subsection above; recorded here so the attestation surfaces it alongside the JGAS rotation note.)

**SC#5 satisfied:** every cited `file:line` is grep-verified against HEAD (incl. the JGAS footprint); the RM + JGAS DRIFT items, the IDegenerusGame MISSING resolution, the keeper-dependency clean result, the J5 VRF verdict, the keeper transitional-state caveat, and the box-cursor rotation landmine are all recorded — the SPEC carries no unverified call-graph claim.
