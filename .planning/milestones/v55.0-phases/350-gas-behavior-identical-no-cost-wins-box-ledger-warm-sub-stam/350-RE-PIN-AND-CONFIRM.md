# 350-RE-PIN-AND-CONFIRM — SCAV-348-01..07 re-pin + GAS-01/02 confirm-structural

**Phase:** 350 — GAS · **Plan:** 350-01 · **Authored:** 2026-05-31
**Subject HEAD (`contracts/`):** the LIVE committed tree at **HEAD `902f3fbf`** (contracts last mutated by **349.2 `453f8073`**, which landed ON TOP of 349.1 `77c3d9ef`).
**Re-pin basis:** every "live anchor" below is a `git grep` against the current committed tree (read-only). The 348 inventory's anchors were against `20ca1f79` (pre-349); the 350-RESEARCH re-pinned against `77c3d9ef` (349.1). **This doc re-pins against the CURRENT post-349.2 tree** and records every drift from the research's `77c3d9ef` anchors explicitly (T-350-01 — no silent override).
**Paper-only:** this plan READS/greps `contracts/*.sol` and WRITES this Markdown. `git diff --name-only -- contracts/` is EMPTY — zero `contracts/*.sol` edits.

---

## 0. ⚠ LOAD-BEARING DISCREPANCY — re-pinned against post-349.2, not 77c3d9ef

The plan + the 350-RESEARCH anchor against **349.1 `77c3d9ef`**. But **349.2 `453f8073`** (the lootbox quest-credit + affiliate regression fix) landed AFTER and mutated `GameAfkingModule.sol` by +104/−29 lines:

```
git diff --numstat 77c3d9ef HEAD -- contracts/modules/GameAfkingModule.sol  →  104  29
git diff --stat   77c3d9ef HEAD -- contracts/                               →  DegenerusGame.sol 13 / IDegenerusGameModules.sol 4 / GameAfkingModule.sol 133
```

STATE.md is explicit that 350 "re-confirms GAS-01 net of the restored side-effects **on the post-349.2 surface**". So the correct subject is the CURRENT committed tree (`902f3fbf`, contracts == `453f8073`), NOT `77c3d9ef`. Two consequences, both recorded here, neither silently overridden:

1. **The stamp-write anchors DRIFTED** (349.2 inserted the quest + affiliate block between the funding debit `:708-711` and the stamp). Research/plan `77c3d9ef` → live `453f8073`:
   - `sub.scorePlus1` `:747` → **`:793`**
   - `sub.amount` `:748` → **`:794`**
   - `sub.lastAutoBoughtDay` `:756` → **`:840`**
   - The funding anchors **held** (the 349.2 insert was below them): `afkingFunding[player]` read `:464` ✓, funding-skip `:662` ✓, `afkingFunding[src] -=` `:709` ✓, `claimablePool -=` `:710` ✓.
   - The GAS-02 view-helpers DRIFTED (349.2's −13 DegenerusGame lines): `afkingFundingOf` `:1590` → **`:1579`**, `afkingSnapshot` `:2656` → **`:2645`**.

2. **The research's "affiliate/quest are NOT on the STAGE hot path" claim is now PARTIALLY STALE for the lootbox branch.** 349.2 RESTORED `quests.handlePurchase` (`:760`), `recordMintQuestStreak` (`:773`), `affiliate.payAffiliate` (`:806`, `:816`), and `coinflip.creditFlip` (`:831`) onto the lootbox-mode STAGE path (they were absent at `77c3d9ef`). **This does NOT change the GAS-01/02 structural verdicts and does NOT change the GAS-03 same-slot-flush candidate** — see §B.3 — because the restored calls are **ALL BURNIE flip-credit, NOT ETH/pool writes**: the `:710` `claimablePool` debit is byte-unchanged, no new solvency-slot mutation is added (code comment `:742-744`), and `quests.*` is the SAME pre-marked-REJECT non-linear surface (§4 carve-out) — it was never a batchable candidate. The net effect on this doc: SCAV-348-03's "only batchable shared slot is `claimablePool:710`" verdict **survives** the 349.2 change; the restored BURNIE calls are per-sub non-batchable and were already excluded.

This discrepancy is the T-350-01 mitigation: every anchor below is the LIVE `453f8073` grep, flagged where it diverges from the research's `77c3d9ef` expectation.

---

## A. RE-PIN TABLE — SCAV-348-01..07 against the live `453f8073` tree

| SCAV-ID | OLD anchor (`20ca1f79`, the inventory) | NEW live anchor(s) (`453f8073`) | STATUS |
|---------|----------------------------------------|---------------------------------|--------|
| **SCAV-348-01** (box-ledger → warm Sub-stamp) | `MintModule.sol:1142,:1159,:1306,:1328,:1473` (cold box ledger) | **Afking path = ONE warm Sub slot, no ledger:** `GameAfkingModule.sol:793` (`sub.scorePlus1=`), `:794` (`sub.amount=`), `:840` (`sub.lastAutoBoughtDay=`). **Cold-ledger symbols grep-ABSENT in `GameAfkingModule.sol`** (`enqueueBoxForAutoOpen`/`lootboxEth[`/`lootboxPurchasePacked[`/`boxPlayers.push` — see §B.1). **Human path UNCHANGED:** `MintModule.sol:1142,:1159,:1306,:1328,:1473` + `WhaleModule.sol:863,:887,:909` still write the cold ledger. | **ALREADY-DELIVERED-STRUCTURAL** (afking subset). The afking box-buy touches no cold-ledger anchor; humans retain theirs (BOX-05 two-path). Nothing to apply at 350 → CONFIRM + measure (351 TST-06). ⚠ stamp anchors drifted `:747/:748/:756` → `:793/:794/:840` (349.2). |
| **SCAV-348-02** (staticcall → in-context SLOAD) | `AfKing.sol:636,:744`; `DegenerusGame.sol:1540,:2720` | **Hot path = in-context SLOAD:** `GameAfkingModule.sol:464` (`playerFunding = afkingFunding[player]`), `:662` (`afkingFunding[src]` funding-skip), `:709` (`afkingFunding[src] -=` debit), `:463` (`claimableWinnings[player]`). **No STATICCALL to a different address on the hot path** (`staticcall`/`.afkingSnapshot`/`.afkingFundingOf` grep-ABSENT in `GameAfkingModule.sol` — §B.2). **Residual view-helpers (OFF hot path):** `DegenerusGame.sol:1579` (`afkingFundingOf`), `:2645` (`afkingSnapshot`) — consumed by `DegenerusVault.sol:518` ONLY. | **ALREADY-DELIVERED-STRUCTURAL.** `contracts/AfKing.sol` is GONE; `AF_KING` grep-empty. The STATICCALLs vanished from the hot path. The Game view-helpers survive for the EXTERNAL Vault consumer — **NOT a removal target** (real cross-contract caller). CONFIRM only. ⚠ view-helper anchors drifted `:1590/:2656` → `:1579/:2645` (349.2). |
| **SCAV-348-03** (same-slot aggregate flush = GAS-03) | `DegenerusGame.sol:1912` (`claimablePool -=`) + `MintModule:1269/:1279/...` (payAffiliate pots) | **Live STAGE shared-slot aggregate:** `GameAfkingModule.sol:710` (`claimablePool -= uint128(ethValue)`, per funded buy — single slot 1, packed w/ `currentPrizePool`). **Affiliate/quest on the lootbox STAGE (349.2-restored) are ALL BURNIE flip-credit, NOT ETH/pool writes:** `:760` (`quests.handlePurchase`), `:806`/`:816` (`affiliate.payAffiliate`), `:831` (`coinflip.creditFlip`) → none mutate `claimablePool`/`prizePoolsPacked`. `prizePoolsPacked`: grep-ABSENT in `GameAfkingModule`. | **STILL-APPLICABLE (the sole candidate) — verdict DEFERRED to plan 350-02.** The one batchable shared slot remains `claimablePool:710`. The 349.2-restored BURNIE calls do NOT add a batchable shared slot (BURNIE, not ETH; `quests.*` non-linear = §4 REJECT). **Not adjudicated here** — 350-02 (`/gas-skeptic`) APPROVE/REJECT/ESCALATE under the security floor (research direction: NEGATIVE/marginal, warm-write ~100 gas × (N−1)). |
| **SCAV-348-04** (AfKing.sol bytecode retire) | `AfKing.sol` (whole) | `contracts/AfKing.sol` **does not exist** (deleted in the 349/349.1 fold; `ls` → No such file). `AF_KING` constant **grep-empty** in `contracts/*.sol`. Logic relocated to `GameAfkingModule.sol` (61,221 B source). | **DISSOLVED / DELIVERED.** Deploy-cost-only win, already banked. N/A to 350 runtime gas. |
| **SCAV-348-05** (snapshot-batching scaffold dead-path) | `AfKing.sol:600-601,:628-636,:716,:744` | **No equivalent in `GameAfkingModule`** — the pre-loop `afkingSnapshot` chunk-batch scaffold was never ported; the STAGE reads inline per-sub (`:464,:662,:709`). | **DISSOLVED.** The cross-contract boundary the scaffold worked around is gone (SCAV-02). Nothing to remove. N/A. |
| **SCAV-348-06** (Sub-record storage packing) | `AfKing.sol` layout vs Storage | `DegenerusGameStorage.sol:1867` (`struct Sub`): config 56b (`dailyQuantity`8 + `validThroughLevel`32 + `reinvestPct`8 + `flags`8) + stamp 112b (`scorePlus1`16 + `amount`96) + markers 64b (`lastAutoBoughtDay`32 + `lastOpenedDay`32) = **232/256 bits, ONE slot.** | **ALREADY-DELIVERED-STRUCTURAL (layout landed).** 349.1 collapsed to a single slot (dropped `_afkingEpoch`; markers are day-keyed `uint32` not `lastOpenedIndex`48). The packed `(scorePlus1, amount)` warm-dirty write IS the GAS-01 saving. CONFIRM the single-slot pack. |
| **SCAV-348-07** (open-side ledger dead-path, afking subset) | `LootboxModule.sol:505,:529,:553,:555,:558,:560` | **Human `openLootBox` UNCHANGED:** `LootboxModule.sol:503` (fn), reads `:505`/`:529`/`:553`, zeroes `:555`/`:558`/`:560` (`lootboxEth`/`lootboxPurchasePacked`/`lootboxDistressEth`). **Afking open = `LootboxModule.sol:877` `resolveAfkingBox`** (called from `GameAfkingModule.sol:888 _openAfkingBox` → `:901`): NO `boxPlayers` walk, NO ledger reads/zeroes; resolves from `(uint256(sub.amount), day, rngWordByDay[day], scorePlus1-1)`, EV-cap read LIVE in the callee. `boxPlayers` lives ONLY in `DegenerusGame.sol:1672/:1682/:1806` (human path). | **ALREADY-DELIVERED-STRUCTURAL** (afking subset). The afking open never walks `boxPlayers`/zeroes the cold ledger; humans keep the path verbatim. CONFIRM the two-path no-shared-mutable-state (also a 352-sweep item). |

**Bottom line of the re-pin:** SCAV-01/02/04/05/06/07 are **all already delivered or dissolved** on the live `453f8073` tree — 350 confirms, does not apply. **SCAV-348-03 (GAS-03) is the sole residual candidate; its APPROVE/REJECT verdict is carried to plan 350-02** (named STILL-APPLICABLE here, not adjudicated). No live grep CONTRADICTS the research's expected status; the two recorded divergences (§0) are anchor-line drift + the 349.2-restored-but-BURNIE-only affiliate/quest, neither of which flips a verdict.

---

## B. GAS-01 + GAS-02 CONFIRM-STRUCTURAL evidence

**GAS-01 and GAS-02 require NO apply work at 350 — they are confirmed structurally present in the live committed tree (`453f8073`); the empirical measurement is 351 TST-06.**

### B.1 GAS-01 — the afking box-buy writes ONE warm Sub-stamp + NO cold ledger

The lootbox-mode branch of `processSubscriberStage` (`GameAfkingModule.sol:735-833`) writes the box record as the **single warm-dirty Sub slot** (SCAV-348-06's 232-bit slot):
- `sub.scorePlus1` at **`:793`** (the frozen activity-score EV-multiplier input, D-348-07).
- `sub.amount` at **`:794`** (the stamped spend; boons OFF ⇒ `amount == spend`, `uint96`).
- `sub.lastAutoBoughtDay` at **`:840`** (the success-marker AND the open's frozen seed `day`).

**Grep-confirmed ABSENCE on the afking path** — the cold box-ledger symbols do NOT appear in `GameAfkingModule.sol`:
- `enqueueBoxForAutoOpen` → lives only in `MintModule.sol:1142,:1473` + `DegenerusGame.sol:1680` (decl) + `IDegenerusGame.sol:339`.
- `lootboxEth[` → `MintModule.sol:1128,:1159`, `LootboxModule.sol:505,:555,:602`, `WhaleModule.sol:863,:909`, `DegenerusGame.sol:2381` — **none in GameAfkingModule.**
- `lootboxPurchasePacked[` → `MintModule.sol:1306,:1316,:1328`, `LootboxModule.sol:529,:558`, `WhaleModule.sol:887,:921,:931` — **none in GameAfkingModule.**
- `boxPlayers.push` → `DegenerusGame.sol:1682` only; `boxPlayers` mapping `:1672`, walked `:1806` (human path) — **none in GameAfkingModule.**

The box is materialized LATER, at open, from `(Sub stamp + rngWordByDay[lastAutoBoughtDay])` via `resolveAfkingBox` (`LootboxModule.sol:877`), called by `_openAfkingBox` (`GameAfkingModule.sol:888 → :901`) — identical resolve math to the human `openLootBox`, but seeded from the frozen stamp instead of the cold ledger. **GAS-01 is the relocation; it is present.** (The 349.2-restored quest/affiliate calls at `:760/:806/:816/:831` are BURNIE flip-credit, NOT box-ledger writes — they do not reintroduce any cold SSTORE; the comment `:740-741` states they replicate `purchaseWith`'s lootbox leg "MINUS the cold box-ledger (the warm stamp replaces it — GAS-01)".)

### B.2 GAS-02 — funding reads are in-context SLOADs, no STATICCALL on the hot path

`_resolveBuy` reads `afkingFunding[player]` (`GameAfkingModule.sol:464`) and `claimableWinnings[player]` (`:463`) as plain in-context SLOADs (the module inherits `DegenerusGameStorage`, runs via delegatecall). The funding-skip gate (`:662`) and the debit (`:709`) read/write `afkingFunding[src]` in-context.

**Grep-confirmed: NO STATICCALL to a different address on the process/open hot path** — `staticcall`, `.afkingSnapshot`, `.afkingFundingOf` are ALL grep-empty in `GameAfkingModule.sol`. `AfKing.sol` is deleted, so the cross-contract `GAME.afkingSnapshot(...)`/`GAME.afkingFundingOf(...)` STATICCALLs that the old `AfKing._autoBuy`/`_resolveBuy` issued no longer exist.

The `afkingSnapshot`/`afkingFundingOf` symbols **survive ONLY as Game view-helpers** (`DegenerusGame.sol:1579 afkingFundingOf`, `:2645 afkingSnapshot`) for the EXTERNAL `DegenerusVault.sol:518` consumer (`gamePlayer.withdrawAfkingFunding(gamePlayer.afkingFundingOf(address(this)))`) — a real cross-contract caller across the genuine Game↔Vault boundary, **NOT a removal target**. **GAS-02 is present.**

### B.3 Net of the 349.2 restore (the STATE.md "GAS-01 net of restored side-effects" charge)

349.2 restored, onto the lootbox STAGE branch, the quest-credit + affiliate that a manual lootbox buy (and an afking TICKET sub via `purchaseWith`) already gets — `quests.handlePurchase` `:760`, `recordMintQuestStreak` `:773`, `affiliate.payAffiliate` `:806`/`:816`, one `coinflip.creditFlip` `:831`. Confirmed against the live code (comment `:742-744` + the `:708-711` debit):
- The `:710` `claimablePool -= uint128(ethValue)` debit is **byte-unchanged**; **no new ETH/pool write** is added (affiliate/quest are routed as BURNIE flip-credit, never an ETH cut → no solvency surface).
- GAS-01's structural verdict holds: still ONE warm Sub-stamp, still no cold box ledger (the restore is BURNIE side-effects, not ledger SSTOREs).
- GAS-02's structural verdict holds: the restored calls are in-context delegatecalls to `quests`/`affiliate`/`coinflip` module addresses on the SAME-contract storage (delegatecall, not a cross-address STATICCALL of afking funding state); the funding-state reads stay the in-context SLOADs at `:463/:464/:662/:709`.
- GAS-03's candidate set is **unchanged**: the only batchable shared additive slot on the loop is still `claimablePool:710`; the restored `quests.*` is the pre-marked-REJECT non-linear surface (§4), and `affiliate.payAffiliate` here credits BURNIE (no shared ETH/pool slot to batch on this path). The per-sub `creditFlip` is keyed on `player` (distinct from the `:1015` `msg.sender` open-bounty creditFlip) and is not a shared-slot aggregate.

---

## C. Carried floor + carve-outs (verbatim, for 350-02)

- **`feedback_security_over_gas` is the floor.** Freeze-completeness / index-binding / stamped-day determinism / no-double-open (`lastOpenedDay` monotonic, `_openAfkingBox:892`) / revert-free-by-construction (no try/catch, D-348-04) / fail-loud-on-solvency / the set-mutation swap-pop tombstone (CONSENT-02, `:621/:675`) govern every candidate. Any win trading any of those is REJECTED at 350-02, not debated.
- **GAS-03 SAFE-WITH-CONDITIONS (348-GAS-INVENTORY §4, verbatim):** SAFE = bucket affiliate payout by roll-winner + accumulate genuinely-linear additive aggregates (`claimablePool` delta) → flush once per batch (associative). **MUST NOT batch** `quests.handlePurchase`/`quests.handleAffiliate` — non-linear completion logic; batching is a behavior change, pre-marked 350-02 REJECT. Each sub's quest calls run per-sub, in order (live: `:760`).
- **SOLVENCY-01 penny-exactness:** `claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]` (`DegenerusGameStorage.sol:358`). A same-slot flush MUST preserve the EXACT net `claimablePool` delta the per-slice debits produce; the `:710` site FAILS LOUD on underflow (class B — checked `uint128 -=`, NEVER `unchecked`).
- **v46 Phase 319 CR-01:** flat-per-item rewards peg to the loop-N-divide MARGINAL, never a single-item total (applies only if 350 touches a peg — current scope does not).
- **Do NOT batch `afkingFunding[src] -=`** (`:709`) — per-key, and it is the per-account underflow guard that makes the `claimablePool` aggregate never underflow.

---

## D. Validity

**Valid until** the next `contracts/` mutation (a 350 Outcome-B `claimablePool`-flush diff, if 350-02/350-03 produce one — at which point `:709/:710` shift by the diff's line delta and the re-grep must re-run). Stable otherwise (the surface is committed at `453f8073`). `git diff --name-only -- contracts/` is EMPTY in this plan.

*Phase: 350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam · Plan: 350-01 · Task 1. Only CLI used: `git grep`/read (read-only, no ffi, no package install).*
