# Phase 350: GAS — Behavior-Identical No-Cost Wins — Research

**Researched:** 2026-05-31
**Domain:** Solidity gas optimization under a security/freeze/solvency floor — the `/gas-skeptic` validation gate over the SPEC `348-GAS-INVENTORY.md` advisory list, re-pinned against the LIVE post-349.1 tree (HEAD `8f505c0c`, contracts committed `77c3d9ef`).
**Confidence:** HIGH (every anchor below is a live grep against the committed `77c3d9ef` tree; the gas-magnitude verdicts are MEDIUM-HIGH, grounded in the confirmed warm/cold SSTORE profile).

---

## Summary

Phase 350 is a **CONFIRM-and-validate** phase, not an apply phase. The live grep proves what the SPEC inventory predicted: **GAS-01 and GAS-02 are already structurally delivered by the 349/349.1 relocation** (committed `77c3d9ef`) — there is nothing to re-apply, only to confirm and hand 351 a measurement spec. **GAS-03 is the only candidate that could be a net-new code change, and the live evidence points it toward NEGATIVE/marginal** under the security floor: the affiliate/quest/pool calls the inventory worried about are **NOT on the afking process-STAGE hot path at all** (they live inside MintModule's `purchaseWith`, reached only by ticket-mode subs), and the single genuinely-shared aggregate the STAGE does touch per-iteration — `claimablePool` (`GameAfkingModule.sol:710`) — is a **WARM SSTORE after iteration 1** (it packs into slot 1 with `currentPrizePool`, stays dirty across the loop). So collapsing N per-iteration `claimablePool -=` into one batch flush saves ~100 gas × (N−1), not the inventory's naive ~2.9k × (N−1) — exactly the over-count the inventory's own Skeptic note flagged.

The net effect: the planner should structure 350 so the **"no net contract change beyond the IMPL relocation"** branch (Success Criterion 4) is the *expected* outcome, with the small GAS-03 flush diff as a *contingency* that only lands if `/gas-skeptic` finds a real win that survives the penny-exact solvency proof. Both outcomes are first-class.

**Primary recommendation:** Run 350 as three waves — (W1) re-pin + confirm GAS-01/02 structural-present + write the 351 measurement spec; (W2) `/gas-skeptic` each candidate under the floor, with GAS-03 expected REJECT/NEGATIVE on the warm-write evidence; (W3) record the NEGATIVE outcome (most likely) OR, only if a real win survives, author a single penny-exact same-slot-flush diff (`quests.*` untouched, `afkingFunding[src]` per-key untouched) and HOLD at the contract-commit boundary (`autonomous: false`).

---

## User Constraints

> No `CONTEXT.md` exists for Phase 350 (this is integrated research spawned by plan-phase). The binding constraints are the milestone floor + the locked SPEC decisions, transcribed below from REQUIREMENTS.md, ROADMAP.md, the 348 inventory, and project memory.

### Locked Decisions (milestone floor — non-negotiable)
- **`feedback_security_over_gas` is the milestone floor.** The v55 spine — freeze-completeness, index-binding, stamped-day determinism, no-double-open (`lastOpenedDay` monotonic), the discharged REVERT-FREE-CHAIN obligation-1 (revert-free-by-construction), fail-loud-on-solvency, terminal-routing-unblocked, and the set-mutation tombstone (H-CANCEL-SWAP-MISS class) — governs every candidate. **Any gas win that trades any of those is REJECTED, not debated.**
- **GAS-03 SAFE-WITH-CONDITIONS carve-out (carry VERBATIM, `348-GAS-INVENTORY.md` §4):**
  - **SAFE:** bucket affiliate payout by roll-winner + accumulate genuinely-linear additive aggregates (`claimablePool` delta, additive pool pots) → flush once per batch. Order-independent because addition into a slot is associative and per-slice amounts do not depend on the running aggregate.
  - **MUST NOT batch:** `quests.handlePurchase` / `quests.handleAffiliate` — NON-LINEAR completion logic (streak/threshold/completion depends on per-call sequence + prior state). Batching these is a behavior change, not a gas win → **pre-marked for 350 REJECTION.** Each sub's quest calls run per-sub, in order.
- **SOLVENCY-01 penny-exactness:** the same-slot flush MUST preserve the EXACT net `claimablePool` delta the per-slice debits produce. A batching bug there is a direct SOLVENCY-01 hazard. The `claimablePool -=` site FAILS LOUD on underflow (class B — MUST revert, never be masked).
- **Project gas-pegging lesson (v46 Phase 319 CR-01):** flat-per-item rewards peg to the loop-N-divide MARGINAL cost, NEVER a single-item total. (Applies only if 350 touches a reward/peg — the open-bounty `OPEN_KNEE` / advance-bounty `unit·2·mult`. The current scope does NOT propose a peg change; flag if one is introduced.)
- **v49 gas-skeptic precedent:** reject non-real wins WITH reasoning; do not re-litigate.
- **CONTRACT BOUNDARY (`autonomous: false`):** any net `contracts/*.sol` change rides a SECOND batched USER-APPROVED diff, applied + `forge build` clean, HELD at the commit gate for explicit user hand-review. NEVER auto-committed. Per project memory: *the ONLY action needing approval is committing `contracts/*.sol`; all else runs hands-off.*

### Claude's Discretion
- The wave/plan decomposition (recommended below).
- Whether `/gas-skeptic` is invoked as a sub-skill or run inline by the executor persona (the skill MD is not present in this repo — see Environment Availability).

### Deferred Ideas (OUT OF SCOPE)
- `forge build` / `forge test` execution — 351's charge. Stale AfKing.sol-import / `_afkingEpoch` / ABI test reds are EXPECTED now; do NOT fix tests.
- Any contract surface beyond the afking process/open path + the box-buy ledger + the affiliate/pool flushes (the v55 keeper/funding blast radius).
- The empirical gas MEASUREMENT itself (TST-06) — 350 writes the *spec* for it; 351 runs it.

---

## Phase Requirements

| ID | Description (from REQUIREMENTS.md) | Research Support |
|----|-----------------------------------|------------------|
| GAS-01 | The afking box-buy's ~6 cold box-ledger SSTOREs + `boxPlayers.push` + `enqueueBoxForAutoOpen` (~120–130k) collapse to one warm-dirty Sub-stamp write (~5k); behavior-identical, proven same-results in TST. | **ALREADY DELIVERED structurally** (`77c3d9ef`). The lootbox-mode STAGE writes ONLY the warm Sub stamp (`GameAfkingModule.sol:747-748,756`); no `enqueueBoxForAutoOpen`, no `boxPlayers`, no `lootboxEth*` on the afking path (§Re-Pin SCAV-01). 350 CONFIRMS; 351 (TST-06) MEASURES. |
| GAS-02 | The per-subscriber `afkingSnapshot`/`afkingFundingOf` cross-contract staticcalls (~3–5k each) become in-context `SLOAD`s. | **ALREADY DELIVERED structurally** (`77c3d9ef`). The STAGE reads `afkingFunding[player]`/`[src]` directly (`GameAfkingModule.sol:464,662,709`); the `afkingSnapshot`/`afkingFundingOf` symbols survive ONLY as external Game view-helpers for `DegenerusVault.sol` (off the hot path) (§Re-Pin SCAV-02). 350 CONFIRMS. |
| GAS-03 | Same-slot affiliate/pool aggregate flushes across a process batch (`claimablePool`/`prizePoolsPacked` accumulate-and-flush; bucket affiliate by roll-winner) — SAFE-WITH-CONDITIONS (do NOT batch `quests.handleAffiliate`); each gas-only under the security floor. | **The only candidate net-new code change — and likely NEGATIVE/marginal.** The affiliate/quest/pool calls are NOT on the STAGE hot path; the one shared aggregate (`claimablePool`) is a WARM SSTORE after iter 1 (§GAS-03 Linearity Map + §Realistic Outcome). 350 validates via `/gas-skeptic`; expected REJECT-with-reasoning. |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Afking box-buy stamp (the GAS-01 surface) | `GameAfkingModule.processSubscriberStage` (delegatecall, in-context storage) | — | Warm per-sub Sub-slot write; the box record IS the stamp, no cold ledger. |
| In-context funding reads (the GAS-02 surface) | `GameAfkingModule` SLOAD of `afkingFunding`/`claimableWinnings` | `DegenerusGame` view-helpers (`afkingSnapshot`/`afkingFundingOf`) for the EXTERNAL `DegenerusVault` consumer only | Subscriber state is game-resident → the hot path needs no boundary; the Vault still calls the Game view across the real contract boundary. |
| Same-slot solvency aggregate (`claimablePool`) | `GameAfkingModule.processSubscriberStage:710` (per-buy `-=`) | `DegenerusGameAdvanceModule:958` (the once-per-advance jackpot settle `+=`, already batched) | The STAGE's only genuinely-shared per-iteration slot; the candidate GAS-03 batch flush target. |
| Affiliate / quest / pool credit (the inventory's GAS-03 worry) | `DegenerusGameMintModule.purchaseWith` (`:1222` quests, `:1269/:1279` payAffiliate) — reached ONLY by **ticket-mode** subs via the STAGE delegatecall (`GameAfkingModule.sol:718-730`) | — | **NOT on the lootbox-stamp hot path.** This is the key correction to the inventory's GAS-03 framing. |
| Afking box open (post-RNG) | `GameAfkingModule._autoOpen` → `_openAfkingBox` → `LootboxModule.resolveAfkingBox` (`:877`) delegatecall | — | Live-level resolve, frozen-day seed; cursor/marker shell + one EV-cap RMW. No per-iteration shared aggregate. |

---

## Re-Pin Table (research question 1 — THE deliverable)

Every "new live anchor" below is a grep against the committed `77c3d9ef` tree. The inventory's anchors were against `20ca1f79` (pre-349); most drifted or dissolved.

| SCAV-ID | Old anchor (`20ca1f79`) | New live anchor(s) (`77c3d9ef`) | Status |
|---------|-------------------------|---------------------------------|--------|
| **SCAV-348-01** (box-ledger → warm stamp) | `MintModule.sol:1142,:1159,:1306,:1328,:1473` (cold box ledger) | **Afking path:** `GameAfkingModule.sol:747-748` (`sub.scorePlus1=`, `sub.amount=`) + `:756` (`sub.lastAutoBoughtDay=`) — ONE warm-dirty Sub slot, no ledger. **Human path unchanged:** the old anchors `MintModule.sol:1142,1159,1306,1328,1473` STILL EXIST (humans keep `enqueueBoxForAutoOpen`/`lootboxEth`/`lootboxPurchasePacked`). | **ALREADY-DELIVERED-STRUCTURAL** (afking subset). The afking box-buy no longer touches any cold-ledger anchor; humans retain theirs (BOX-05 two-path). Nothing to apply at 350 → CONFIRM + measure (351 TST-06). |
| **SCAV-348-02** (staticcall → SLOAD) | `AfKing.sol:636,:744`; `DegenerusGame.sol:1540,:2720` | **Hot path now SLOAD:** `GameAfkingModule.sol:464` (`playerFunding = afkingFunding[player]`), `:662` (`afkingFunding[src]` skip-gate), `:709` (`afkingFunding[src] -=` debit), `:461-463` (`claimableWinnings[player]` in-context). **Residual stubs (off hot path):** `DegenerusGame.sol:1590` (`afkingFundingOf` view), `:2656/:2665` (`afkingSnapshot` view) — consumed by `DegenerusVault.sol:518` only. | **ALREADY-DELIVERED-STRUCTURAL.** `AfKing.sol` is GONE (file dissolved). The STATICCALLs vanished from the hot path. The Game view-helpers survive for the external Vault consumer — NOT a removal target (they serve a real cross-contract caller). CONFIRM only. |
| **SCAV-348-03** (same-slot aggregate flush = GAS-03) | `DegenerusGame.sol:1912` (`claimablePool -=`) + `MintModule:1269/:1279/:1613/...` (payAffiliate pots) | **Live STAGE aggregate:** `GameAfkingModule.sol:710` (`claimablePool -= uint128(ethValue)`, per funded buy). **Affiliate/pool pots:** `MintModule.sol:1222` (quests), `:1269/:1279` (payAffiliate) — reached ONLY by ticket-mode subs through `GameAfkingModule.sol:718-730`'s `purchaseWith` delegatecall; **NOT on the lootbox-stamp path.** `prizePoolsPacked`: NOT written anywhere in `GameAfkingModule` (grep-empty). | **STILL-APPLICABLE (the only candidate) — but expected NEGATIVE.** The one batchable shared slot is `claimablePool:710`, a WARM write after iter 1 (slot 1, packed w/ `currentPrizePool`). `prizePoolsPacked` is not on the afking path at all. See §GAS-03 Linearity Map + §Realistic Outcome. |
| **SCAV-348-04** (AfKing.sol bytecode retire) | `AfKing.sol` (whole) | `contracts/AfKing.sol` **does not exist** (deleted in the 349/349.1 fold). `AF_KING` constant grep-empty in `contracts/`. | **DISSOLVED / DELIVERED.** Logic relocated to `GameAfkingModule.sol`. Deploy-cost-only win, already banked. N/A to 350 runtime gas. |
| **SCAV-348-05** (snapshot-batching scaffold dead-path) | `AfKing.sol:600-601,:628-636,:716,:744` | No equivalent in `GameAfkingModule` — the pre-loop chunk-batch scaffold was never ported (the STAGE reads inline per-sub: `:464,:662,:709`). | **DISSOLVED.** The boundary workaround the scaffold existed for is gone (SCAV-02). Nothing to remove. N/A. |
| **SCAV-348-06** (Sub-record storage packing) | `AfKing.sol` layout vs Storage | `DegenerusGameStorage.sol:1867-1899` (`struct Sub`): config 56b (`dailyQuantity`8 + `validThroughLevel`32 + `reinvestPct`8 + `flags`8) + stamp 112b (`scorePlus1`16 + `amount`96) + markers 64b (`lastAutoBoughtDay`32 + `lastOpenedDay`32) = **232/256 bits, ONE slot.** | **DELIVERED (layout landed).** 349.1 already collapsed to a single slot (dropped `_afkingEpoch`; `lastOpenedIndex`48→`lastOpenedDay`32). The packed `(scorePlus1, amount)` warm-dirty write IS the GAS-01 saving. CONFIRM the single-slot pack only. |
| **SCAV-348-07** (open-side ledger dead-path, afking subset) | `LootboxModule.sol:505,:529,:553,:555,:558,:560` | **Human `openLootBox` UNCHANGED** at the same lines: `LootboxModule.sol:505` (`lootboxEth[index][player]`), `:529` (`lootboxPurchasePacked`), `:553/:555/:558/:560` (`lootboxDistressEth` read + zeroes). **Afking open** = `LootboxModule.sol:877` `resolveAfkingBox` — NO `boxPlayers` walk, NO ledger reads/zeroes; pure `(stamp + rngWordByDay[day])` resolve via `_resolveLootboxCommon`. | **ALREADY-DELIVERED-STRUCTURAL** (afking subset). The afking open never walks `boxPlayers`/zeroes the cold ledger; humans keep the path verbatim. CONFIRM the two-path no-shared-mutable-state (also a 352-sweep item). |

**Bottom line of the re-pin:** SCAV-01/02/04/05/06/07 are **all already delivered or dissolved by `77c3d9ef`** — 350 confirms, does not apply. **SCAV-03 (GAS-03) is the sole residual candidate**, and the live evidence points it to NEGATIVE/marginal.

---

## Confirming GAS-01 + GAS-02 Are Structurally Present (research question 2)

### GAS-01 — box-buy writes ONE warm Sub-stamp (no cold ledger)

The lootbox-mode branch of `processSubscriberStage` (`GameAfkingModule.sol:735-749`) writes only:
```solidity
// GameAfkingModule.sol:739-748  (lootbox mode — the STAMP)
uint256 activityScore = _playerActivityScore(player, _questStreakOf(player), currentLevel + 1);
uint16 scorePlus1 = activityScore + 1 > type(uint16).max ? type(uint16).max : uint16(activityScore + 1);
sub.scorePlus1 = scorePlus1;   // :747  ─┐ same packed Sub slot (slot is warm/dirty
sub.amount     = uint96(amount); // :748 ─┘  after iter 1 within a chunk if same-slot reused;
                                  //          cold for distinct subs, but ONE slot not six)
// ... then :756  sub.lastAutoBoughtDay = processDay;  (same slot)
```
There is **no** `enqueueBoxForAutoOpen`, **no** `lootboxEth[...]=`, **no** `lootboxPurchasePacked[...]=`, **no** `boxPlayers.push` on this path (grep-confirmed: those symbols appear only in the human MintModule path `:1142/:1159/:1306/:1328/:1473` and `boxPlayers` only in `DegenerusGame.sol`). The box is materialized at open from `(Sub stamp + rngWordByDay[day])` via `resolveAfkingBox` (`LootboxModule.sol:877`). **GAS-01 is the relocation; it is present.**

### GAS-02 — funding reads are in-context SLOADs

`_resolveBuy` reads `afkingFunding[player]` (`:464`) and `claimableWinnings[player]` (`:461-463`) as plain in-context SLOADs (the module inherits `DegenerusGameStorage` and runs via delegatecall). The skip-gate (`:662`) and debit (`:709`) read/write `afkingFunding[src]` in-context. `AfKing.sol` is deleted, so the cross-contract `GAME.afkingSnapshot(...)`/`GAME.afkingFundingOf(...)` STATICCALLs no longer exist on this path. The `afkingSnapshot`/`afkingFundingOf` symbols survive ONLY as Game view-helpers (`DegenerusGame.sol:1590,2656`) for `DegenerusVault.sol:518` — a real external consumer, NOT a removal target. **GAS-02 is present.**

### WHERE 351 must measure (the planner's TST-06 measurement spec)

| Win | Function to instrument | Transaction that exercises it | Marginal unit to report |
|-----|------------------------|-------------------------------|--------------------------|
| GAS-01 (per-buy) | `GameAfkingModule.processSubscriberStage` — invoked inside `advanceGame`'s new-day STAGE block (`DegenerusGameAdvanceModule.sol:310-326`, calling `_runSubscriberStage` `:754`) | A new-day `advanceGame()` (or `mintBurnie()`'s advance leg) with N≥2 funded **lootbox-mode** subs queued. | **Per-sub marginal stamp cost** = (gas for N subs − gas for N−1 subs) / 1. Compare against the v54 cold-ledger box-buy (~120–130k) to confirm the ~5k warm-stamp collapse. |
| GAS-01 (per-open) | `GameAfkingModule._openAfkingBox` (`:814`) → `LootboxModule.resolveAfkingBox` (`:877`) delegatecall | `autoOpen(count)` (`:962`) or `mintBurnie()`'s open leg (`:927`) over N ready stamped boxes after their `rngWordByDay[day]` lands. | **Per-open marginal** = (N opens − (N−1) opens). Compare against the human `openLootBox` (`:503`) which walks the cold ledger + zeroes (`:505/:529/:553/:555/:558/:560`). |
| GAS-02 | Same STAGE call — the in-context `afkingFunding`/`claimableWinnings` SLOADs at `:461-464,:662,:709`. | Same new-day `advanceGame()`. | Confirm NO `STATICCALL` opcode to a different address on the process/open path (a trace assertion, not a marginal number). |

**16.7M HARD per-tx ceiling context (from AdvanceModule):** `SUB_STAGE_BATCH = 50` (`DegenerusGameAdvanceModule.sol:149`) chunks the STAGE; comment `:148` budgets "a landed buy ≈ 262k gas; 50 ≈ 13.1M" — under the ceiling. `OPEN_BATCH` chunks the open leg. 351 measures the per-buy/per-open marginal and confirms a 50-chunk stays under 16.7M.

**This is a CONFIRM-and-measure deliverable — there is NO apply work for GAS-01/GAS-02 in 350.**

---

## GAS-03 Linearity Map (research question 3 — the crux)

**Every per-sub state write inside the live `processSubscriberStage` loop** (`GameAfkingModule.sol:550-762`), classified:

| Write site | Slot / key | Linear additive aggregate to ONE slot? | Batchable? | Why |
|------------|-----------|----------------------------------------|------------|-----|
| `afkingFunding[src] -= ethValue` (`:709`) | `afkingFunding` mapping, **keyed by `src`** | NO — different key per (distinct) funder | **NO** | Distinct storage slots per funder; only collapses if the *same* `src` recurs in a chunk (uncommon; and even then each is a balance `-=`, order matters for the underflow check). Batching across keys is not a same-slot flush. |
| `claimablePool -= uint128(ethValue)` (`:710`) | `claimablePool`, **single uint128, slot 1** (packed w/ `currentPrizePool`, Storage `:365`) | YES — one shared slot, pure additive `-=` | **YES (the only true candidate)** | Genuinely linear: net delta = Σ ethValue is order-independent (associative). BUT — see warm-write magnitude below. |
| `sub.scorePlus1 = …` (`:747`) | per-sub `Sub` slot | NO — per-sub-keyed | **NO** | Per-sub box freeze field; must be written per sub. |
| `sub.amount = uint96(amount)` (`:748`) | same per-sub `Sub` slot | NO — per-sub-keyed | **NO** | Same. |
| `sub.lastAutoBoughtDay = processDay` (`:756`) | same per-sub `Sub` slot | NO — per-sub-keyed; the BOX-03 idempotency + freeze-day marker | **NO** | Order/identity-bound; the open's seed `day`. |
| `sub.lastOpenedDay = processDay` (ticket mode, `:734`) | same per-sub `Sub` slot | NO — per-sub-keyed | **NO** | Ticket-mode no-pending marker. |
| `sub.validThroughLevel = uint32(h)` (refresh, `:616`) | per-sub `Sub` slot | NO | **NO** | Pass-refresh. |
| `sub.dailyQuantity = 0` + `_removeFromSet` (evict/kill, `:621-622,:675-676`) | per-sub `Sub` slot + `_subscribers` array + `_subscriberIndex` | NO — set mutation | **NO** | The CONSENT-02 swap-pop tombstone — order-bound + the H-CANCEL-SWAP-MISS class. **Touching this is a floor violation.** |
| `delete _subOf[player]` + `_removeFromSet` (reclaim, `:587-588`) | per-sub + set | NO | **NO** | Set mutation; same. |
| **`affiliate.payAffiliate`** (`MintModule:1269/:1279`) | pool pots | — | **N/A — NOT on this loop** | Reached ONLY via the **ticket-mode** `purchaseWith` delegatecall (`:718-730`), one call per ticket sub, deep inside MintModule. Not a STAGE-loop write. |
| **`quests.handlePurchase` / `handleAffiliate`** (`MintModule:1222`) | quest state | — | **N/A — NOT on this loop + pre-marked REJECT** | Same — inside `purchaseWith`. Non-linear completion logic; **MUST NOT batch** (carve-out §4). |
| **`prizePoolsPacked`** | slot 2 | — | **N/A — NOT on this loop** | grep-empty in `GameAfkingModule`. Only written by AdvanceModule's jackpot settle (`:954`, already a once-per-advance batch). |

### Two decisive corrections to the inventory's GAS-03 framing

1. **The afking process STAGE does NOT call `affiliate.payAffiliate` or `quests.*` per-sub.** Confirmed grep-empty in `GameAfkingModule.sol`. The lootbox-mode buy STAMPS (no purchase call); the ticket-mode buy delegatecalls `purchaseWith` ONCE per ticket sub (`:718-730`), and the affiliate/quest/pool credits happen *inside* that single call (per the design, the BURNIE bounty is a deferred `creditFlip` mint per PLACE-02, NOT a per-sub `payAffiliate` on the STAGE). So the inventory's "~0.6–1.2M / 50-sub batch for the affiliate/pool flush set" **does not apply to the afking STAGE** — those pots are credited inside per-sub `purchaseWith` calls that cannot be collapsed (each is one sub's own purchase, and batching them would batch `quests.*` → REJECT). **Confirmed: `affiliate.payAffiliate` is NOT on the hot path; the bounty is the deferred `creditFlip` (PLACE-02), credited ONCE in `mintBurnie` CEI-last (`GameAfkingModule.sol:903-911`).**

2. **`claimablePool -=` is a WARM SSTORE after iteration 1.** It packs into slot 1 with `currentPrizePool` (Storage `:365` comment: *"Packed into slot 1 alongside currentPrizePool"*). The first `-=` in a chunk pays the cold→warm SSTORE; every subsequent `-=` in the same `processSubscriberStage` call is a warm SSTORE (~100 gas, post-Berlin). Collapsing N warm `-=` into one batch flush saves **~100 gas × (N−1)** — NOT the ~2.9k × (N−1) the inventory's headline implied. This is precisely the over-count the inventory's own Skeptic note warned about ("a naive 2.9k × N−1 over-counts warm writes").

### Where a once-per-batch flush WOULD go (if pursued)

A memory local `uint256 poolDebitAcc` accumulates `ethValue` per funded buy inside the loop; flush `claimablePool -= uint128(poolDebitAcc)` ONCE after the `while` (before `_subCursor = uint16(cursor)` at `:765`). The `afkingFunding[src] -=` at `:709` **stays per-iteration** (per-key, and the underflow check is the SOLVENCY-01 fail-loud guard). This is the entire candidate diff — small, local to `processSubscriberStage`, `quests.*`/`purchaseWith`/set-mutations all untouched.

---

## Penny-Exact Solvency Check For The Flush (research question 4)

If GAS-03's `claimablePool` flush is pursued, the planner MUST require the following proof obligations (these are the SOLVENCY-01 hazard controls):

1. **Net-delta identity.** Prove `claimablePool_after_batch == claimablePool_before − Σ(ethValue_i)` over the chunk, identical to the per-slice path's running `claimablePool -= ethValue_i`. Because the accumulator is `Σ ethValue_i` and `-=` is associative, this holds **iff** no intermediate code path reads `claimablePool` *between* the first per-slice debit and the batch flush. **Verification step:** grep the loop body for any `claimablePool` READ after `:710` and before the flush — there must be NONE (a mid-loop read would observe a stale value under batching → behavior change). Currently the only other `claimablePool` touch in the module is `subscribe:282` (`+=`, a different external function) and the AdvanceModule `:958` (`+=`, a different tx phase) — neither is inside the STAGE loop, so the identity holds, but the planner must re-grep after any diff.
2. **Fail-loud preserved (class B).** The batch flush `claimablePool -= uint128(poolDebitAcc)` MUST still revert on underflow (Solidity 0.8 checked arithmetic on the `uint128` subtraction). Do NOT wrap in `unchecked`. A single batched underflow revert is *equivalent* to the first per-slice underflow that would have reverted (the sum can only underflow if the running balance would have), so fail-loud semantics are preserved — but the planner must assert no `unchecked` block wraps the flush, and 351 (TST-02) must include a forced-underflow test that confirms the revert still fires.
3. **`afkingFunding[src]` stays per-iteration.** The per-funder debit at `:709` is NOT batched (different keys; and it is the per-account guard that bounds each debit ≤ the account's balance, the precondition that makes the `claimablePool` aggregate never underflow). Batching it would lose the per-account underflow check → SOLVENCY-01 hazard. **Pre-marked: do NOT batch `afkingFunding[src] -=`.**
4. **Penny-exact, not approximately-equal.** No rounding, no truncation: `uint96(amount)`/`uint128(ethValue)` casts are unchanged; the accumulator is full-width `uint256` and the single cast to `uint128` at flush is identical to the per-slice cast (each `ethValue ≤ afkingFunding[src] ≤ claimablePool` fits `uint128`, and the sum fits `uint128` because it cannot exceed `claimablePool`). 351 (TST-06) must assert byte-identical `claimablePool` before/after vs the per-slice oracle on a multi-sub batch.

---

## Realistic Outcome + The "No Net Change" Branch (research question 5)

**Verdict-direction: GAS-03 is most likely NEGATIVE / not-worth-it on this surface.** The evidence:

- The only batchable shared slot is `claimablePool` (`:710`), and it is a **warm ~100-gas SSTORE** after iteration 1 (packed slot 1). The batch saving is ~100 × (N−1) — for the `SUB_STAGE_BATCH = 50` max chunk, ~4,900 gas best-case, against a ~262k-per-buy STAGE — i.e. **< 0.04% of the chunk**, at the cost of: a memory accumulator, a new flush site, a re-grep'd "no mid-loop `claimablePool` read" invariant, a forced-underflow test, and net-new audit surface on the SOLVENCY-01 spine at TERMINAL (352).
- The inventory's large "~0.6–1.2M / 50-sub" affiliate/pool figure **does not apply** — those pots are not on the afking STAGE (they're inside per-sub `purchaseWith`, un-collapsible without batching `quests.*` = REJECT).
- This is a textbook v49 gas-skeptic REJECT: a marginal warm-write saving that adds correctness surface on the solvency spine, under a `feedback_security_over_gas` floor. **Reject WITH reasoning (the warm-write count + the off-hot-path affiliate/pool finding), do not re-litigate.**

**Therefore Success Criterion 4's "no net contract change" branch is the EXPECTED outcome, and the planner must make BOTH outcomes first-class:**

- **Outcome A (expected): all-rejected / NEGATIVE.** 350 produces a `350-GAS-SKEPTIC-VERDICTS.md` (or similar) recording: GAS-01 CONFIRMED-STRUCTURAL (delivered `77c3d9ef`, measured at 351), GAS-02 CONFIRMED-STRUCTURAL, GAS-03 REJECTED (warm-write marginal + off-hot-path affiliate/pool + solvency-surface cost). NO `contracts/*.sol` diff. The phase closes on the documented verdict. This satisfies SC4's explicit "no diff is gated" branch and is a clean, valid phase completion.
- **Outcome B (contingency): a real win survives.** If `/gas-skeptic` finds a win that (a) is genuinely linear-additive to a shared slot, (b) survives the §Penny-Exact proof obligations, AND (c) clears a cost/benefit bar worth the audit surface, then author the single penny-exact `claimablePool` flush diff (W3), `forge build` clean, HOLD at the contract-commit boundary (`autonomous: false`).

**Do NOT structure the phase to assume a diff is produced.** The plan's terminal wave must branch on the W2 verdict.

---

## Recommended Plan Shape (research question 6)

A **3-wave** decomposition (CONTRACT BOUNDARY, `autonomous: false` only at the W3 commit gate IF a diff is produced):

### Wave 1 — Re-pin + Confirm-Structural + Measurement Spec (READ-ONLY, autonomous)
- **W1 plan 350-01:** Re-pin all SCAV-348-01..07 anchors against the LIVE `77c3d9ef` tree (this RESEARCH's Re-Pin Table is the seed; the plan re-verifies each grep). Confirm GAS-01 (one warm Sub stamp, no cold ledger on the afking path) and GAS-02 (in-context SLOADs, no STATICCALL on the hot path) are structurally present. Write the **351 TST-06 measurement spec** (the §"WHERE 351 must measure" table: which function, which tx, which marginal). Output: `350-RE-PIN-AND-CONFIRM.md`. No contract edits.

### Wave 2 — `/gas-skeptic` Validation Gate (READ-ONLY, autonomous)
- **W2 plan 350-02:** Run `/gas-skeptic` (or the equivalent skeptic discipline inline — the skill MD is not vendored in this repo, see Environment Availability) over each candidate **under the `feedback_security_over_gas` floor**. For each: APPROVE (real, safe, worth it) / REJECT (not real, marginal, or trades an invariant — with reasoning) / ESCALATE (needs USER judgment). Expected: GAS-01/02 = CONFIRMED-STRUCTURAL (no apply); GAS-03 = REJECT (warm-write marginal + off-hot-path affiliate/pool + solvency surface). Carry the §4 carve-out VERBATIM (no `quests.*` batching). Output: `350-GAS-SKEPTIC-VERDICTS.md`. No contract edits.

### Wave 3 — BRANCH on the W2 verdict
- **W3-A (expected) plan 350-03:** Record the NEGATIVE/all-confirmed outcome. No `contracts/*.sol` diff. The phase closes on the documented verdict per SC4's "no diff is gated" branch. `autonomous: true` (docs-only).
- **W3-B (contingency) plan 350-03 (alt):** IF a real win survived W2 — author the single penny-exact `claimablePool` same-slot-flush diff (memory accumulator in `processSubscriberStage`, flush once before `:765`; `quests.*`/`purchaseWith`/`afkingFunding[src]`/set-mutations UNTOUCHED). `forge build` clean (DegenerusGame must stay < 24,576 B; current 22,927 B / 1,649 margin). **HOLD at the contract-commit boundary — `autonomous: false`** (the ONLY action needing approval is committing `contracts/*.sol`). Per project memory, all docs/planning around it run hands-off; only the contract commit gates.

**The plan MUST be written so W3 is conditional on W2's output**, not pre-committed to producing a diff. Flag the W3-B contract gate as `autonomous: false`; W1/W2/W3-A are autonomous.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Validating whether a gas candidate is real + safe | An ad-hoc "looks fine" judgment | The `/gas-skeptic` discipline under the security floor (REJECT-with-reasoning, v49 precedent) | The skeptic's entire job is to disprove the scavenger's aggressive claims; ad-hoc judgment re-introduces the over-count (the warm-write trap) the discipline exists to catch. |
| Proving the batch flush is same-results | Eyeballing the accumulator | The §Penny-Exact proof obligations (net-delta identity + no-mid-loop-read grep + fail-loud-preserved + byte-identical 351 oracle) | A batching bug on `claimablePool` is a direct SOLVENCY-01 hazard; the proof must be mechanical, not visual. |
| Measuring the per-buy/per-open marginal | A single-tx total | The loop-N-divide MARGINAL (v46 CR-01 rule) | A single-box total over-states the saving and (if a reward were pegged to it) re-introduces the Phase-319 faucet. |

**Key insight:** in this phase the highest-value work is *disproving* candidates, not applying them. The relocation already banked the structural wins; 350's job is to confirm them and to keep a marginal warm-write optimization from adding solvency-spine surface for ~0.04% gas.

---

## Common Pitfalls

### Pitfall 1: Treating GAS-01/GAS-02 as apply-work
**What goes wrong:** The planner writes tasks to "implement" the box-ledger collapse or the staticcall→SLOAD swap.
**Why it happens:** The REQUIREMENTS phrasing ("collapse to one warm-dirty Sub-stamp write") reads like an action.
**How to avoid:** GAS-01/02 are ALREADY in `77c3d9ef` (the 349/349.1 relocation). 350 CONFIRMS + writes the 351 measurement spec. The Re-Pin Table marks them ALREADY-DELIVERED-STRUCTURAL.
**Warning signs:** A 350 task that edits `processSubscriberStage`'s stamp writes or re-routes funding reads.

### Pitfall 2: Inheriting the inventory's stale GAS-03 magnitude
**What goes wrong:** Planning a flush for the "~0.6–1.2M / 50-sub" affiliate/pool saving.
**Why it happens:** The inventory (against `20ca1f79`, pre-fold) assumed per-sub `payAffiliate` on the STAGE.
**How to avoid:** Grep confirms `affiliate.payAffiliate`/`quests.*` are NOT in `GameAfkingModule` — they're inside per-sub `purchaseWith` (ticket mode only), un-collapsible without batching `quests.*` (REJECT). The only batchable slot is `claimablePool` (warm, ~100 gas/iter).
**Warning signs:** A GAS-03 task that touches affiliate pots or `purchaseWith`.

### Pitfall 3: Batching `afkingFunding[src]` or touching set-mutation
**What goes wrong:** Folding the per-funder debit into the aggregate, or "optimizing" the swap-pop tombstone.
**Why it happens:** Both appear in the loop and look batchable.
**How to avoid:** `afkingFunding[src] -=` is per-key AND is the per-account underflow guard (SOLVENCY-01 precondition). The swap-pop tombstone is the H-CANCEL-SWAP-MISS class (CONSENT-02). Both are floor-protected — REJECT any candidate that touches them.
**Warning signs:** A diff that changes `:709` to an accumulator, or alters `_removeFromSet`/cursor logic.

### Pitfall 4: Running forge / fixing tests
**What goes wrong:** Treating stale test reds as a 350 problem.
**Why it happens:** `forge test` shows reds (stale AfKing.sol imports, `_afkingEpoch` refs).
**How to avoid:** Stale reds are EXPECTED post-`77c3d9ef`; the test sweep is 351 (TST-05). 350 is READ-only except (optionally) `forge build` to confirm a contingency diff compiles.
**Warning signs:** A 350 task editing `test/`.

---

## Runtime State Inventory

> This is a contract gas-validation phase, not a rename/migration. No stored-data/service-config/OS-state migration applies. The one storage-adjacent fact:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `Sub` record single-slot layout already landed in `77c3d9ef` (`DegenerusGameStorage.sol:1867-1899`); `_afkingEpoch` already deleted. | None — delivered at 349.1. Pre-launch redeploy-fresh (storage break free). |
| Live service config | None — no external service holds afking gas state. | None — verified (afking state is fully game-resident). |
| OS-registered state | None. | None. |
| Secrets/env vars | None. | None. |
| Build artifacts | `forge` build cache reflects `77c3d9ef` (DegenerusGame 22,927 B). A contingency GAS-03 diff would dirty the cache → `forge build` re-run (NOT `forge test`). | Only if Outcome B (diff produced). |

---

## Code Examples

### The live GAS-01 stamp (lootbox mode) — the warm single-slot write
```solidity
// Source: contracts/modules/GameAfkingModule.sol:735-756 (committed 77c3d9ef)
} else {
    // STAMP the lootbox box — ONE warm-dirty SSTORE (the single Sub slot)
    uint256 activityScore = _playerActivityScore(player, _questStreakOf(player), currentLevel + 1);
    uint16 scorePlus1 = activityScore + 1 > type(uint16).max ? type(uint16).max : uint16(activityScore + 1);
    sub.scorePlus1 = scorePlus1;   // :747
    sub.amount     = uint96(amount); // :748
}
// ...
sub.lastAutoBoughtDay = processDay; // :756  — same packed Sub slot
```

### The live GAS-03 candidate site — the warm `claimablePool` debit
```solidity
// Source: contracts/modules/GameAfkingModule.sol:704-711 (committed 77c3d9ef)
// ⚠ SOLVENCY-01: the `claimablePool -= uint128(ethValue)` site FAILS LOUD on an
//    underflow ... class B, MUST propagate, NEVER caught.
if (ethValue != 0) {
    afkingFunding[src] -= ethValue;       // :709  per-funder key — NOT batchable (per-account guard)
    claimablePool      -= uint128(ethValue); // :710  single slot 1 — warm after iter 1 (~100 gas)
}
```

### The penny-exact flush shape (contingency only — if W2 approves)
```solidity
// CONTINGENCY (Outcome B): accumulate in memory, flush once before _subCursor persist.
// quests.* / purchaseWith / afkingFunding[src] / set-mutations UNTOUCHED.
uint256 poolDebitAcc; // memory local, full-width
// ... inside the loop, replace :710 with:
//     if (ethValue != 0) { afkingFunding[src] -= ethValue; poolDebitAcc += ethValue; }
// ... after the while loop, BEFORE `_subCursor = uint16(cursor)` at :765:
if (poolDebitAcc != 0) {
    claimablePool -= uint128(poolDebitAcc); // checked (NO unchecked) — fail-loud preserved (class B)
}
// INVARIANT to grep-prove: no `claimablePool` READ exists between the first debit and this flush.
```

---

## State of the Art

| Old framing (348 inventory, vs `20ca1f79`) | Current reality (`77c3d9ef`) | When changed | Impact |
|--------------------------------------------|------------------------------|--------------|--------|
| GAS-01/02 = "wins to apply" | Already structurally delivered by the relocation | 349 + 349.1 (`77c3d9ef`) | 350 confirms + measures, does not apply. |
| GAS-03 affiliate/pool = ~0.6–1.2M/50-sub on the STAGE | Affiliate/pool NOT on the STAGE (inside per-sub `purchaseWith`, ticket mode only); only `claimablePool` is on-loop, WARM | 349.1 fold (PLACE-02 deferred-`creditFlip` bounty) | GAS-03 magnitude collapses to ~100×(N−1); expected REJECT. |
| `AfKing.sol` standalone contract | Deleted; logic in `GameAfkingModule.sol` | 349 | SCAV-04/05 dissolved. |
| 5-field stamp `(index, amount, day, scorePlus1, baseLevelPlus1)` | `_afkingEpoch` dropped; live-level resolve → stamp is `(scorePlus1, amount)` + `(lastAutoBoughtDay, lastOpenedDay)` markers; index/baseLevel GONE | 349.1 (live-level redesign) | The open rolls from LIVE `level` + `rngWordByDay[day]`; fewer frozen fields. |

**Deprecated/outdated in the 348 inventory:** every `file:line` anchor (all against `20ca1f79`); the GAS-03 affiliate/pool magnitude; the implication that GAS-01/02 are apply-work; the 5-field stamp framing (superseded by 349.1's live-level model).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `claimablePool` (packed slot 1) is a WARM SSTORE (~100 gas) after the first per-chunk write, post-Berlin/London gas schedule (evm_version=paris). | GAS-03 Linearity / Realistic Outcome | If somehow cold per-iteration, the GAS-03 saving would be larger (~2.9k×(N−1)) and the REJECT-direction would weaken. **Mitigation:** verifiable empirically at 351 (TST-06) — the planner's measurement spec already instruments the per-iter marginal. The storage comment (`:365` "Packed into slot 1") + EVM semantics make warm HIGH-confidence, but 351 is the empirical backstop. |
| A2 | No code path reads `claimablePool` between the first per-slice debit (`:710`) and the (contingency) batch flush, so the accumulate-and-flush identity holds. | Penny-Exact Solvency Check | If a hidden read exists, batching would change behavior. **Mitigation:** the proof obligation IS a mandatory re-grep; currently grep-confirmed (only `subscribe:282` + `Advance:958` touch `claimablePool`, both outside the loop). |
| A3 | The `/gas-skeptic` skill is available to the executor (or its discipline can be applied inline). | Recommended Plan Shape | If unavailable and not vendored, W2 must run the skeptic discipline inline against this RESEARCH's evidence. **Mitigation:** see Environment Availability — the discipline (REJECT-with-reasoning, warm-write re-derivation, floor-check) is fully specified here. |

---

## Open Questions

1. **Does any ticket-mode sub's `purchaseWith` produce a *second* `claimablePool` touch that could interact with a GAS-03 flush?**
   - What we know: ticket mode delegatecalls `purchaseWith` (`GameAfkingModule.sol:718-730`); `purchaseWith` touches `claimablePool` at `MintModule.sol:981` (relabel comment "claimablePool unchanged") + `:1449` (80/20 routing `+=`).
   - What's unclear: whether a chunk mixing ticket + lootbox subs would have a `purchaseWith`-driven `claimablePool` write *interleaved* with the lootbox `:710` debits — which (under a batch flush of the lootbox debits) is exactly the "mid-loop read/write of the batched slot" that breaks the identity.
   - Recommendation: this is decisive for Outcome B. If GAS-03 is pursued, the planner MUST prove the flush only accumulates the `:710` lootbox debits and that any `purchaseWith`-internal `claimablePool` write is applied immediately (not batched) — OR (cleaner) reject GAS-03 outright because mixed chunks make the batch unsafe. This strengthens the REJECT-direction. Re-attest at 352.

2. **Is the `claimableWinnings[player]` read at `_resolveBuy:461-463` (the reinvest/drainFirst split) the same swept-gated value the buy-time path uses?**
   - What we know: comment `:431-434` asserts it mirrors `afkingSnapshot`/`claimableWinningsOf` incl. the 1-wei sentinel.
   - What's unclear: only relevant to GAS-02's same-results confirmation (it's a read, not a write).
   - Recommendation: 351 (TST-03/TST-06) confirms the read equivalence; not a 350 blocker.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Live contract tree at `77c3d9ef` | Re-pin + confirm | ✓ | committed on `main` (HEAD `8f505c0c`) | — |
| `grep` / read | All read-only analysis | ✓ | — | — |
| `forge build` | Contingency diff compile only (Outcome B) | ✓ (assumed — used throughout v55) | — | If unavailable, the diff is held un-compiled and 351 compiles it. |
| `/gas-skeptic` skill MD | W2 validation gate | ✗ | — | **Not vendored in this repo** (`.claude/skills/` absent; only `.claude/settings.local.json` + `worktrees/`). The skill lives in the global/user skill set, not the project. **Fallback: apply the skeptic discipline inline** — this RESEARCH supplies the full evidence (warm-write re-derivation, off-hot-path affiliate finding, floor-check, penny-exact obligations). The v49/v54 GAS phases established the REJECT-with-reasoning pattern. |
| `/gas-scavenger` skill MD | (already ran at 348) | ✗ | — | N/A — its output IS `348-GAS-INVENTORY.md`; 350 does not re-run it. |

**Missing dependencies with no fallback:** none — 350 is read-only analysis + a documented verdict; `forge build` is only needed for the contingency diff.
**Missing dependencies with fallback:** the `/gas-skeptic` skill MD (apply the discipline inline against this RESEARCH's evidence — fully specified here).

---

## Validation Architecture

> `workflow.nyquist_validation` not found in `.planning/config.json` for this phase context; this phase is gas-validation (no new behavior). The validation that matters is the SAME-RESULTS proof, which is **owned by 351 (TST-06)**, not 350. 350 writes the *measurement spec* 351 consumes.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (`forge`) — Solidity 0.8.34, via_ir=true, optimizer_runs=200, evm_version=paris |
| Config file | `foundry.toml` (repo root) |
| Quick run command | `forge build --sizes` (350 contingency-diff compile check ONLY — confirms DegenerusGame < 24,576 B) |
| Full suite command | `forge test` — **351's charge, NOT 350's** (stale reds expected now) |

### Phase Requirements → Test Map (the 351 spec 350 produces)
| Req ID | Behavior | Test Type | Automated Command (351 owns) | File Exists? |
|--------|----------|-----------|------------------------------|-------------|
| GAS-01 | per-buy stamp marginal ≈5k (vs ~120-130k cold); same materialized box | gas + behavior | `forge test --mp test/.../AfkingGas.t.sol --gas-report` (351 authors) | ❌ 351 Wave 0 |
| GAS-02 | no STATICCALL on the process/open path; same funding values | trace | 351 authors a trace assertion | ❌ 351 Wave 0 |
| GAS-03 | IF a flush lands: byte-identical `claimablePool` before/after vs per-slice oracle + forced-underflow still reverts | behavior + solvency | 351 authors | ❌ 351 Wave 0 (only if Outcome B) |

### Sampling Rate
- **350 per task:** `forge build --sizes` only on a contingency diff (Outcome B); no test runs.
- **350 phase gate:** the `350-GAS-SKEPTIC-VERDICTS.md` documented + (if Outcome B) `forge build` clean + held at the contract boundary.
- **Same-results proof:** deferred to 351 (TST-06) by design (ROADMAP Phase 351 Depends-on 350).

### Wave 0 Gaps (for 351, surfaced here)
- [ ] An afking gas-measurement test harness (per-buy + per-open marginal under 16.7M) — 351 Wave 0.
- [ ] A `claimablePool` per-slice-vs-batch oracle — only if Outcome B.

*350 itself needs no new test infrastructure — its output is a verdict doc + (conditionally) a held diff.*

---

## Security Domain

> `security_enforcement` treated as enabled (absent = enabled). This phase sits directly on the SOLVENCY-01 spine; the floor IS the governing constraint.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V5 Input Validation | no | No new external inputs; 350 is internal gas refactor at most. |
| V6 Cryptography | no | No crypto change (the box seed/RNG freeze is untouched by a gas flush; FREEZE spine is 348/349 territory, re-attested 352). |
| V11 Business Logic (solvency) | **YES** | `claimablePool == Σ claimableWinnings + Σ afkingFunding` (Storage `:358`) — a GAS-03 flush MUST preserve this penny-exactly; fail-loud on underflow (checked arithmetic, no `unchecked`). |
| V7 Error Handling | **YES** | Class-B fail-loud: a `claimablePool` underflow MUST revert (never masked) — preserved by checked subtraction on the batched flush. |

### Known Threat Patterns for the afking gas surface

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Batching debits drifts the net `claimablePool` (penny mismatch) | Tampering / Repudiation | Net-delta identity proof (Σ = associative) + no-mid-loop-read grep + 351 byte-identical oracle. |
| Masking a solvency underflow under a batched flush | Tampering | Checked `uint128 -=` (no `unchecked`); 351 forced-underflow test (TST-02). |
| Touching the swap-pop tombstone for gas (H-CANCEL-SWAP-MISS regression) | Tampering | Floor REJECT — set-mutation is CONSENT-02 protected; do not optimize `_removeFromSet`/cursor. |
| Batching `quests.*` completion (non-linear) | Tampering | Floor REJECT — carve-out §4 verbatim; quest calls stay per-sub, in order. |
| Pegging a bounty to a single-box total (faucet, v46 CR-01) | Elevation (economic) | Only if 350 touches a peg (current scope does NOT) — peg to loop-N-divide MARGINAL. |

---

## Sources

### Primary (HIGH confidence — live greps of the committed `77c3d9ef` tree)
- `contracts/modules/GameAfkingModule.sol` — `processSubscriberStage:539-767` (the STAGE loop), `_resolveBuy:440-496`, `_autoOpen:864-892`, `_openAfkingBox:814-`, `mintBurnie:911`, `subscribe:234`, `_addToSet:373`/`_removeFromSet:391`, the `claimablePool`/`afkingFunding` sites (`:282,:464,:662,:709,:710`).
- `contracts/modules/DegenerusGameAdvanceModule.sol` — the STAGE insertion (`:288-326`), `_runSubscriberStage:754`, `SUB_STAGE_BATCH:149`, the jackpot-settle `claimablePool +=:958`, `rngWordByDay` sites.
- `contracts/modules/DegenerusGameLootboxModule.sol` — `resolveAfkingBox:877` (afking open, no ledger), `openLootBox:503`/`:505/:529/:553/:555/:558/:560` (human path, unchanged), `resolveLootboxDirect:763`, `_applyEvMultiplierWithCap:459`.
- `contracts/modules/DegenerusGameMintModule.sol` — the human box-ledger (`:1142,:1159,:1306,:1328,:1473`), `purchaseWith:864`, the affiliate/quest/pool calls (`:1222,:1269,:1279,:981,:1449`) confirmed OFF the afking STAGE.
- `contracts/storage/DegenerusGameStorage.sol` — `struct Sub:1867-1899` (single slot), `claimablePool:365` (packed slot 1), `afkingFunding:420`, `prizePoolsPacked:378`, the SOLVENCY invariant `:358`, cursors `:1925-1936`.
- `contracts/DegenerusGame.sol` — residual view-helpers `afkingFundingOf:1590`, `afkingSnapshot:2656`, `enqueueBoxForAutoOpen:1691`, `boxPlayers` (human-path only).
- `contracts/DegenerusVault.sol:518` — the external consumer of `afkingFundingOf`.
- `.planning/REQUIREMENTS.md` (GAS-01/02/03, TST-06, traceability) · `.planning/ROADMAP.md` (Phase 350 §120-137, Success Criteria 1-4) · `.planning/STATE.md` (Current Position — the committed 349.1 state + 5 refinements) · `.planning/phases/349.1-*/349.1-DESIGN.md` (the final applied design).

### Secondary (the advisory input, now superseded for anchors)
- `.planning/phases/348-*/348-GAS-INVENTORY.md` — the SCAV-348-01..07 list + the §4 SAFE-WITH-CONDITIONS carve-out (carried verbatim) + the §5 security floor. Its `file:line` anchors are STALE (against `20ca1f79`); the §4/§5 prose is binding.
- Project memory: `only-contract-commits-need-approval`, `threat-model-reentrancy-mev-nonissues`, `v55-afking-revert-free-proof`, the v46 Phase 319 CR-01 faucet lesson, the v49 gas-skeptic REJECT-with-reasoning precedent.

### Tertiary (LOW confidence — none load-bearing)
- Post-Berlin warm-SSTORE ~100-gas figure (A1) — standard EVM gas schedule (evm_version=paris); empirically backstopped at 351.

---

## Metadata

**Confidence breakdown:**
- Re-pin table: HIGH — every anchor is a live grep against the committed `77c3d9ef` tree.
- GAS-01/02 structurally-present: HIGH — the code is committed; the absence of cold-ledger/STATICCALL on the afking path is grep-verified.
- GAS-03 NEGATIVE-direction: MEDIUM-HIGH — the off-hot-path affiliate/pool finding is grep-certain; the warm-write magnitude (A1) is HIGH on EVM semantics + the storage-pack comment, empirically backstopped at 351.
- Plan shape + the conditional-W3 structure: HIGH — directly grounded in SC4's explicit "no diff is gated" branch + the contract-boundary rule.

**Research date:** 2026-05-31
**Valid until:** the next `contracts/` mutation (i.e., a 350 Outcome-B diff, if produced — at which point the `:710`/`:765` anchors shift by the diff's line delta and the re-grep must re-run). Stable otherwise (the surface is committed).
