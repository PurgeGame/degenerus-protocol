# 350-GAS-SKEPTIC-VERDICTS — `/gas-skeptic` adjudication of SCAV-348-01..07 under the security-over-gas floor

**Phase:** 350 — GAS · **Plan:** 350-02 · **Authored:** 2026-05-31
**Subject HEAD (`contracts/`):** the LIVE committed tree — **`contracts/` last mutated by 349.2 `453f8073`** (working-tree HEAD `c09a9d6c` is the 350-01 docs/bookkeeping commit; `git diff --name-only -- contracts/` is EMPTY, contracts byte-identical to `453f8073`).
**Adjudication input:** `350-RE-PIN-AND-CONFIRM.md` (plan 350-01) — the re-pinned SCAV-348-01..07 candidate table against the live `453f8073` tree.
**Skeptic discipline:** the `/gas-skeptic` skill MD is NOT vendored in this repo (`.claude/skills/` absent) — the discipline is applied INLINE, fully specified by `350-RESEARCH.md` (warm-write re-derivation, off-hot-path affiliate finding, the penny-exact obligations, the floor-check) + the v49 REJECT-with-reasoning precedent. Every "live site" below is a fresh `git grep` of the committed `453f8073` tree (verified, not copied — see §0).
**Paper-only:** this plan READS/greps `contracts/*.sol` and WRITES this Markdown. `git diff --name-only -- contracts/` is EMPTY — zero `contracts/*.sol` edits.

---

## 0. FRESH LIVE-GREP RE-VERIFICATION (verify, don't copy — T-350-01 carry)

The plan + the 350-RESEARCH anchor against 349.1 `77c3d9ef`; 350-01 re-pinned against the live post-349.2 `453f8073` tree. This doc RE-GREPPED the live `453f8073` tree independently before rendering any verdict. The load-bearing anchors, re-confirmed:

| Site | Live `453f8073` anchor | Status vs 350-01 re-pin |
|------|------------------------|--------------------------|
| `claimablePool -= uint128(ethValue)` (GAS-03 candidate, SOLVENCY-01) | `GameAfkingModule.sol:710` | ✓ held |
| `afkingFunding[src] -= ethValue` (per-key debit, floor-protected) | `GameAfkingModule.sol:709` | ✓ held |
| Sub stamp `sub.scorePlus1=` / `sub.amount=` / `sub.lastAutoBoughtDay=` | `:793` / `:794` / `:840` | ✓ held (349.2 drift `:747/:748/:756`→`:793/:794/:840` confirmed) |
| `quests.handlePurchase` (349.2-restored, §4 non-linear) | `:760` | ✓ present (was grep-ABSENT at `77c3d9ef`) |
| `recordMintQuestStreak` (349.2-restored) | `:773` | ✓ present |
| `affiliate.payAffiliate` (349.2-restored, BURNIE) | `:806`, `:816` | ✓ present (BURNIE flip-credit, NOT ETH — code comment `:799-805/:828-830`) |
| `coinflip.creditFlip(player, …)` (349.2-restored lootbox flip-credit) | `:831` | ✓ present (distinct from the `:1015` `msg.sender` open-bounty creditFlip) |
| `prizePoolsPacked` in `GameAfkingModule` | **grep-ABSENT** | ✓ confirmed absent |
| `staticcall` / `.afkingSnapshot` / `.afkingFundingOf` on the hot path | **grep-ABSENT** | ✓ confirmed absent |
| cold box-ledger (`enqueueBoxForAutoOpen`/`lootboxEth[`/`lootboxPurchasePacked[`/`boxPlayers`) in `GameAfkingModule` | **grep-ABSENT** | ✓ confirmed absent |
| `_removeFromSet` swap-pop (set-mutation tombstone, CONSENT-02) | `:391` (def, swap-pop `:399`), called `:588`/`:622`/`:676`; `sub.dailyQuantity=0` `:621`/`:675` | ✓ held |
| no-orphan guard (boxless-skip dominating all 4 orphan paths) | `:570` (`if (sub.lastOpenedDay < sub.lastAutoBoughtDay)`) | ✓ held |
| `claimablePool` storage (`uint128`, warm-packed slot) + SOLVENCY-01 invariant | Storage `:365` (`uint128 internal claimablePool`, slot bits `[16:32]`), invariant `:358` (`claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]`), tandem-move note `:416` | ✓ held |

**⚠ The one stale research/plan-text claim, corrected to live reality (the prior_wave_finding charge):** the 350-RESEARCH (against `77c3d9ef`) states "affiliate/quest are NOT on the STAGE hot path — grep-absent from `GameAfkingModule`." That is **STALE for the lootbox branch on the live `453f8073` tree.** 349.2 RESTORED `quests.handlePurchase` (`:760`), `recordMintQuestStreak` (`:773`), `affiliate.payAffiliate` (`:806`/`:816`), and `coinflip.creditFlip` (`:831`) onto the lootbox-mode STAGE path. **This does NOT flip any GAS verdict** — because (proven from the live code, §A.3 + the GAS-03 verdict): the restored calls are **ALL BURNIE flip-credit, NOT ETH/pool writes**. The code's own comment at `:799-805` states *"payAffiliate routes BURNIE flip-credit, never ETH"* and at `:828-830` *"All BURNIE; no ETH moves"*; the comment at `:742-746` states the restore replicates `purchaseWith`'s lootbox leg *"MINUS the cold box-ledger (the warm stamp replaces it — GAS-01)"* and that the `:708-711` ETH/`claimablePool` debit is *"byte-unchanged and NO new ETH/pool write is added."* So the **`:710` `claimablePool` debit remains the SOLE batchable shared additive slot on the STAGE loop** — the GAS-03 candidate set is byte-unchanged by the 349.2 restore, and `quests.*` is the SAME pre-marked-REJECT non-linear surface (§4), never a batchable candidate.

---

## 1. THE FLOOR (governs every verdict — `feedback_security_over_gas`)

`feedback_security_over_gas` is the milestone floor. The v55 spine governs EVERY candidate, and **any win that trades any of these for gas is REJECTED here, not debated:**
- **freeze-completeness** — the stamp captures all outcome-determining state (FREEZE-03).
- **index-binding / stamped-day determinism** — the open seeds the STAMPED `lastAutoBoughtDay`, never open-time.
- **no-double-open** — `lastOpenedDay` monotonic (`_openAfkingBox`).
- **revert-free-by-construction** — D-348-04 DROPPED the try/catch valve; obligation-1 (slice-builder fidelity) is the SOLE no-brick guarantor + fail-loud-on-solvency (class B) + terminal-routing-unblocked (class C).
- **set-mutation tombstone** — the swap-pop (`_removeFromSet`), the H-CANCEL-SWAP-MISS / CONSENT-02 class.
- **SOLVENCY-01 penny-exactness** — `claimablePool == Σ claimableWinnings[*] + Σ afkingFunding[*]` (Storage `:358`); any flush MUST preserve the EXACT net `claimablePool` delta; the `:710` debit FAILS LOUD on underflow (class B — checked `uint128 -=`, NEVER `unchecked`).

**v49 precedent:** REJECT non-real wins WITH reasoning; do not re-litigate. **No GAS-03 win is APPROVED without the penny-exact obligations attached** (net-delta identity + no-mid-loop-read + fail-loud-preserved + byte-identical 351 oracle).

---

## 2. PER-CANDIDATE VERDICT TABLE (SCAV-348-01..07)

| SCAV-ID | Live site(s) (`453f8073`) | DISPOSITION | Reasoning (live-evidence-grounded, under the floor) |
|---------|---------------------------|-------------|------------------------------------------------------|
| **SCAV-348-01** (box-ledger → warm Sub-stamp = **GAS-01**) | Afking stamp: `GameAfkingModule.sol:793/:794/:840`; cold-ledger symbols grep-ABSENT on the afking path; human path keeps `MintModule.sol:1142/:1159/:1306/:1328/:1473` | **CONFIRMED-STRUCTURAL** | Delivered by the 349/349.1 relocation (committed `77c3d9ef`, carried under `453f8073`). The afking box-buy writes ONE warm-dirty Sub slot and touches NO cold box-ledger SSTORE (grep-confirmed absent §A.1); the box materializes at open from `(stamp + rngWordByDay[day])`. **No apply work at 350** — the saving IS the relocation. Measured at 351 TST-06 (per-buy marginal vs the ~120–130k cold-ledger box-buy). The 349.2 BURNIE restore adds no cold SSTORE (code comment `:742-746`). |
| **SCAV-348-02** (staticcall → in-context SLOAD = **GAS-02**) | Hot-path SLOADs: `GameAfkingModule.sol:463/:464/:662/:709`; `staticcall`/`.afkingSnapshot`/`.afkingFundingOf` grep-ABSENT on the hot path; view-helpers survive at `DegenerusGame.sol:1579`/`:2645` for `DegenerusVault.sol:518` ONLY | **CONFIRMED-STRUCTURAL** | Delivered by the relocation. `contracts/AfKing.sol` is GONE (`AF_KING` grep-empty) → the cross-contract `GAME.afkingSnapshot(...)`/`GAME.afkingFundingOf(...)` STATICCALLs vanished from the hot path; the STAGE reads `afkingFunding`/`claimableWinnings` as in-context SLOADs (delegatecall, inherits `DegenerusGameStorage`). The `afkingSnapshot`/`afkingFundingOf` symbols survive ONLY as Game view-helpers for the EXTERNAL `DegenerusVault.sol:518` consumer (`gamePlayer.withdrawAfkingFunding(gamePlayer.afkingFundingOf(address(this)))`) — a real cross-contract caller across the genuine Game↔Vault boundary, **NOT a removal target.** No apply work at 350; the no-STATICCALL trace is a 351 trace assertion. |
| **SCAV-348-03** (same-slot flush = **GAS-03**) | `GameAfkingModule.sol:710` (`claimablePool -= uint128(ethValue)`); 349.2-restored BURNIE calls `:760/:806/:816/:831`; `prizePoolsPacked` grep-ABSENT | **REJECT** (with reasoning — see §3) | The sole residual code-change candidate. The only batchable shared additive slot on the STAGE loop is `claimablePool` (`:710`), a **WARM SSTORE after iter 1** (packed `uint128`, Storage `:365`) → the batch saving is **~100 gas × (N−1), NOT the inventory's ~2.9k × (N−1)** headline. The affiliate/quest/pool calls the inventory worried about are either BURNIE flip-credit (no ETH/pool write — `:806/:816/:831`), grep-absent (`prizePoolsPacked`), or `quests.*` non-linear completion (§4 REJECT). The mixed-chunk hazard (RESEARCH Open Q1) strengthens REJECT. A ~0.04%-of-chunk warm-write saving against net-new audit surface on the SOLVENCY-01 spine at TERMINAL (352) → **REJECT under the floor**, v49 precedent applied. |
| **SCAV-348-04** (AfKing.sol bytecode retire) | `contracts/AfKing.sol` does not exist; `AF_KING` grep-empty; logic in `GameAfkingModule.sol` | **DISSOLVED / DELIVERED** (CONFIRMED-STRUCTURAL) | The entire contract dissolved in the 349/349.1 fold. Deploy-cost-only win, already banked. N/A to 350 runtime gas — nothing to apply. |
| **SCAV-348-05** (snapshot-batching scaffold dead-path) | No equivalent in `GameAfkingModule` — the pre-loop `afkingSnapshot` chunk-batch scaffold was never ported; the STAGE reads inline per-sub (`:464/:662/:709`) | **DISSOLVED** (CONFIRMED-STRUCTURAL) | The cross-contract boundary the scaffold worked around is gone (SCAV-348-02). Nothing to remove. N/A to 350 runtime gas. |
| **SCAV-348-06** (Sub-record storage packing) | `DegenerusGameStorage.sol` `struct Sub`: 232/256 bits, ONE slot (config 56b + stamp 112b + markers 64b) | **DELIVERED-STRUCTURAL** (CONFIRMED-STRUCTURAL) | 349.1 collapsed the Sub record to a single slot (dropped `_afkingEpoch`; day-keyed `uint32` markers). The packed `(scorePlus1, amount)` warm-dirty write IS the GAS-01 saving. Layout landed; confirm-only. N/A to 350 runtime apply. |
| **SCAV-348-07** (open-side ledger dead-path, afking subset) | Afking open `LootboxModule.sol:877 resolveAfkingBox` (no `boxPlayers` walk, no ledger zeroes); human `openLootBox:503` reads/zeroes `:505/:529/:553/:555/:558/:560` unchanged | **DELIVERED-STRUCTURAL** (CONFIRMED-STRUCTURAL) | The afking open resolves from the stamp + `rngWordByDay[day]`; it never walks `boxPlayers` / zeroes the cold ledger. Humans keep the path verbatim (two open routes, no shared mutable state — also a 352-sweep item). N/A to 350 runtime apply. |

**Bottom line:** SCAV-01/02/04/05/06/07 are all CONFIRMED-STRUCTURAL / DISSOLVED on the live `453f8073` tree — 350 confirms, does not apply (GAS-01/GAS-02 measured at 351 TST-06). **SCAV-348-03 (GAS-03) is REJECTED-with-reasoning** (§3). No candidate is APPROVED.

---

## 3. GAS-03 — THE LOAD-BEARING ADJUDICATION (REJECT, executor-rendered)

The GAS-03 candidate (SCAV-348-03): collapse the per-iteration `claimablePool -= uint128(ethValue)` at `GameAfkingModule.sol:710` into a once-per-batch accumulate-and-flush across the `processSubscriberStage` chunk. **Verdict: REJECT.** All five evidence prongs recorded:

### (a) The warm-SSTORE magnitude — ~100 gas × (N−1), NOT ~2.9k × (N−1)
The only batchable shared slot on the STAGE loop is `claimablePool` (`:710`), a `uint128` (Storage `:365`, slot bits `[16:32]`). The first `-=` in a chunk pays the cold→warm SSTORE; every subsequent `-=` in the SAME `processSubscriberStage` call is a **WARM SSTORE (~100 gas, post-Berlin/evm_version=paris)**. Collapsing N warm `-=` into one batch flush saves **~100 gas × (N−1)** — for `SUB_STAGE_BATCH = 50`, ~4,900 gas best-case against a ~262k-per-buy STAGE = **< 0.04% of the chunk.** This is exactly the over-count the 348-inventory's own Skeptic note flagged (*"a naive 2.9k × N−1 over-counts warm writes"*). The headline ~2.9k applies only to a cold-or-recomputed write; `claimablePool` is neither after iter 1.

### (b) The affiliate/quest/pool calls are OFF the ETH+pool path (live-confirmed, NOT grep-absent — the 349.2 correction)
The 349.2-restored calls ARE present on the lootbox STAGE (`:760` quests, `:806/:816` payAffiliate, `:831` creditFlip — §0 correction), but they are **ALL BURNIE flip-credit, NOT ETH/pool writes** (code comments `:799-805` *"payAffiliate routes BURNIE flip-credit, never ETH"* + `:828-830` *"All BURNIE; no ETH moves"*). They do NOT mutate `claimablePool` or `prizePoolsPacked` → they add NO batchable shared additive slot. The `:710` `claimablePool` debit is byte-unchanged by 349.2 (comment `:742-746`). So the inventory's large "~0.6–1.2M / 50-sub" affiliate/pool flush figure **does not apply to the afking STAGE** — there is no per-sub `payAffiliate` ETH/pool cut to batch; the only ETH/pool slot is `claimablePool:710` (warm). The `quests.*` is the §4 pre-marked-REJECT non-linear surface and was never a batchable candidate. The per-sub `creditFlip(player, …)` at `:831` is keyed on `player` (distinct from the `:1015` `msg.sender` open-bounty creditFlip) and is BURNIE, not a shared-slot ETH aggregate.

### (c) `prizePoolsPacked` is NOT on the afking path
`prizePoolsPacked` is **grep-ABSENT in `GameAfkingModule`** (§0). It is written ONLY by the AdvanceModule jackpot-settle, already once-per-advance. There is no per-sub `prizePoolsPacked` write on the STAGE to batch.

### (d) The mixed-chunk `purchaseWith` interleave hazard (RESEARCH Open Question 1) — STRENGTHENS REJECT, decisive for any Outcome-B flush
A `processSubscriberStage` chunk can mix ticket-mode and lootbox-mode subs. Ticket-mode subs delegatecall `purchaseWith` (`GameAfkingModule.sol:713-731`), and `purchaseWith` itself touches `claimablePool` internally (the 80/20 routing `+=` / the relabel). Under a batch flush of the lootbox `:710` debits, a `purchaseWith`-internal `claimablePool` write from a ticket sub would be **interleaved with (and read/observe a stale)** the accumulated-but-not-yet-flushed lootbox debits — exactly the "mid-loop read/write of the batched slot" that breaks the accumulate-and-flush net-delta identity (a behavior change, not a gas win). To make a flush safe one would have to PROVE the flush only accumulates the `:710` lootbox debits AND that every `purchaseWith`-internal `claimablePool` write is applied immediately (not batched) — or, cleaner, REJECT GAS-03 outright because mixed chunks make the batch unsafe. **This is decisive: REJECT.**

### (e) Cost/benefit under the floor
A ~0.04%-of-chunk warm-write saving (~4,900 gas / 50-sub max chunk) against: a memory accumulator, a new flush site, a re-grep'd "no mid-loop `claimablePool` read" invariant, the mixed-chunk safety proof, a forced-underflow test, AND net-new audit surface on the **SOLVENCY-01 spine** at TERMINAL (352) — under a `feedback_security_over_gas` floor. This is a textbook v49 gas-skeptic REJECT: a marginal warm-write saving that adds correctness surface on the solvency spine. **REJECT WITH reasoning (the warm-write count + the off-hot-path BURNIE-only affiliate finding + the mixed-chunk hazard + the solvency surface); do not re-litigate.**

### GAS-03 final disposition
**REJECT.** GAS-03 is SAFE-WITH-CONDITIONS in principle (the `claimablePool` delta is genuinely linear-additive), but on the live `453f8073` surface the conditions do not clear the floor: the saving is warm-write marginal (~100×(N−1)), the affiliate/quest/pool worry is off the ETH+pool path (BURNIE-only / grep-absent / §4-REJECT), the mixed-chunk interleave makes the batch unsafe without further proof, and the cost is net audit surface on the SOLVENCY-01 spine. **Not APPROVED; no penny-exact-obligated win survives.** No `claimablePool` flush diff is authored.

---

## 4. §4 SAFE-WITH-CONDITIONS CARVE-OUT (carried VERBATIM from 348-GAS-INVENTORY §4)

> **SAFE:** **bucket affiliate payout by roll-winner.** Across a process batch, the affiliate/pool aggregates that are **pure additive sums** (the `claimablePool` delta, the additive pool pots) may be accumulated in a memory local and flushed once per batch — bucketing the payout by roll-winner is order-independent and same-results, because addition into a slot is associative and the per-slice amounts do not depend on the running aggregate.
>
> **MUST NOT batch:** **`quests.handlePurchase` / `quests.handleAffiliate`** (`GameAfkingModule.sol:760`, the live restored site; orig `MintModule.sol:1222`) — **non-linear completion logic.** Quest completion is NOT a linear accumulation: a quest's state transition (streak/threshold/completion) depends on the per-call sequence and prior state, so collapsing N per-sub `handlePurchase`/`handleAffiliate` calls into one batched call would change quest outcomes (different completions, different streak credit). **Batching this is a behavior change, not a gas win — REJECT at 350.** Each sub's `handlePurchase`/`handleAffiliate` MUST run per-sub, in order.

**Live-tree note:** on `453f8073` the quest call runs per-sub at `:760` inside the lootbox STAGE branch (handlers-before-score), exactly as required. **Any candidate that batches `quests.handlePurchase` / `quests.handleAffiliate` is pre-marked REJECT** under the security-over-gas floor. No candidate in this adjudication proposes to batch them; GAS-03's REJECT does not depend on the carve-out (it rejects on the warm-write + mixed-chunk grounds even for the linear `claimablePool` slot), but the carve-out independently forecloses any future "batch the quest credit too" variant.

---

## 5. FLOOR-PROTECTED REJECT LIST (stated explicitly — any candidate touching these for gas is REJECT)

Any gas candidate that touches any of the following is REJECTED, not debated (the `feedback_security_over_gas` floor):

| Protected surface | Live site(s) (`453f8073`) | Why it is floor-protected |
|-------------------|---------------------------|----------------------------|
| **`afkingFunding[src]` per-key debit** | `GameAfkingModule.sol:709` | Per-funder key (NOT a same-slot aggregate); it IS the per-account underflow guard / SOLVENCY-01 precondition that bounds each debit ≤ the account's balance, making the `claimablePool` aggregate never underflow. Do NOT batch into an accumulator. |
| **Swap-pop set-mutation tombstone (CONSENT-02 / H-CANCEL-SWAP-MISS)** | `_removeFromSet` def `:391` (swap-pop `:399`), called `:588` (reclaim) / `:622` (pass-evict) / `:676` (funding-kill); `sub.dailyQuantity = 0` `:621`/`:675` | Order-bound set mutation; the H-CANCEL-SWAP-MISS class. Touching `_removeFromSet` / cursor / the tombstone for gas regresses CONSENT-02. |
| **No-orphan guard** | `GameAfkingModule.sol:570` (`if (sub.lastOpenedDay < sub.lastAutoBoughtDay)` boxless-skip) | Dominates all four orphan paths (re-stamp / cancel-reclaim / pass-evict / funding-kill); the SKIP-not-force-open liveness guard. Do NOT remove/reorder for gas. |
| **Freeze fields (the stamp)** | `sub.scorePlus1` `:793`, `sub.amount` `:794`, `sub.lastAutoBoughtDay` `:840` | FREEZE-03 — the stamped, frozen activity-score EV-multiplier input + spend + the open's seed `day`. Per-sub-keyed, NOT batchable; each must be written per sub. |
| **Fail-loud-on-solvency (class B)** | `GameAfkingModule.sol:710` (the checked `claimablePool -= uint128(ethValue)`) | MUST revert on underflow (checked arithmetic, NEVER `unchecked`). A batched flush that masked the underflow is a direct SOLVENCY-01 hazard. |

---

## 6. NO-INVARIANT-TRADED ATTESTATION

No invariant-trading candidate is APPROVED:
- The `afkingFunding[src]` per-key debit (`:709`) — **untouched** (floor-protected REJECT).
- The swap-pop tombstone (CONSENT-02 / H-CANCEL-SWAP-MISS, `:588`/`:622`/`:676`) — **untouched** (floor-protected REJECT).
- The no-orphan guard (`:570`) — **untouched** (floor-protected REJECT).
- The freeze fields (`scorePlus1`/`amount`/`lastAutoBoughtDay` stamp) — **untouched** (floor-protected REJECT).
- Fail-loud-on-solvency (the checked `claimablePool -=` at `:710`) — **untouched** (floor-protected REJECT).
- `quests.handlePurchase`/`handleAffiliate` (`:760`) — **NOT batched** (§4 carve-out; stays per-sub, in order).

The ONLY candidate that proposed a contract change (GAS-03, the `claimablePool` same-slot flush) is REJECTED on warm-write-marginal + off-ETH-path + mixed-chunk + solvency-surface grounds. GAS-01/GAS-02 (+ SCAV-04/05/06/07) are CONFIRMED-STRUCTURAL — already delivered by the relocation, no apply. **Net: zero contract change beyond the IMPL relocation.**

---

## 7. ⮕ W3 BRANCH DIRECTIVE FOR PLAN 350-03

**Plan 350-03 MUST execute Outcome A.**

- **Outcome A (DIRECTED — the expected path):** NO net contract change. GAS-03 is REJECTED and all other candidates (SCAV-348-01/02/04/05/06/07) are CONFIRMED-STRUCTURAL / DISSOLVED. Plan 350-03 records the verdict (this doc is its input), keeps `git diff --name-only -- contracts/` EMPTY, and the phase closes on the documented verdict per ROADMAP Success Criterion 4's explicit "no diff is gated" branch. Runs hands-off (docs-only; `autonomous: true`).
- **Outcome B (NOT taken):** author the held `claimablePool` same-slot-flush diff. **This branch is NOT directed** — no GAS-03 win was APPROVED with the penny-exact obligations (net-delta identity + no-mid-loop-read + fail-loud-preserved + byte-identical 351 oracle), and the mixed-chunk interleave hazard (§3d) makes the flush unsafe on the live surface. No `contracts/*.sol` diff is authored at 350.

**Directive: plan 350-03 = Outcome A (no net contract change; record the verdict). Do NOT author the GAS-03 flush diff.**

---

## 8. VALIDITY

**Valid until** the next `contracts/` mutation. The surface is committed at `453f8073`; this adjudication is stable while contracts stay byte-identical to it. `git diff --name-only -- contracts/` is EMPTY in this plan. The empirical GAS-01/GAS-02 marginals (and the warm-SSTORE A1 backstop for GAS-03's REJECT magnitude) are measured at 351 TST-06 per `350-TST06-MEASUREMENT-SPEC.md`.

*Phase: 350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam · Plan: 350-02 · Task 1. Only CLI used: `git grep`/read (read-only, no ffi, no package install).*
