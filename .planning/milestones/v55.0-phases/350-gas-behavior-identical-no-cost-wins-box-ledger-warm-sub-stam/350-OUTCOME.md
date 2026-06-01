# 350-OUTCOME — the verdict-driven phase outcome (executes the 350-02 W3 branch directive)

**Phase:** 350 — GAS · **Plan:** 350-03 · **Task 1** · **Authored:** 2026-05-31
**Subject HEAD (`contracts/`):** the LIVE committed tree — `contracts/` last mutated by **349.2 `453f8073`**; `git diff --name-only -- contracts/` is **EMPTY** at this plan (byte-identical to `453f8073`; the working-tree `scope.txt` edit is a held audit-scope change, NOT a contract change).
**Input (the W3 branch directive):** `350-GAS-SKEPTIC-VERDICTS.md` (plan 350-02, commit `2cada6d4`) §7.
**Confirm-structural evidence:** `350-RE-PIN-AND-CONFIRM.md` (plan 350-01) §A + §B.
**ROADMAP gate:** Phase 350 Success Criterion 4 — the explicit no-diff branch (`.planning/ROADMAP.md:144`).

---

## ⮕ EXECUTED BRANCH: **OUTCOME A** (no net contract change — record the verdict)

This plan READS the 350-02 W3 branch directive and records the phase outcome it dictates. I re-read §7 of `350-GAS-SKEPTIC-VERDICTS.md` directly (verify-don't-assume) before rendering this: it states, verbatim —

> **"Plan 350-03 MUST execute Outcome A."** … *"Directive: plan 350-03 = Outcome A (no net contract change; record the verdict). Do NOT author the GAS-03 flush diff."*

**Outcome A is the executed branch.** GAS-03 was REJECTED-with-reasoning at 350-02; GAS-01 and GAS-02 are CONFIRMED-STRUCTURAL; all other SCAV-348 candidates are DISSOLVED / DELIVERED-STRUCTURAL. There is **NO `contracts/*.sol` diff this phase, and NO contract-commit gate** — the phase closes on the documented verdict per ROADMAP Phase 350 SC4's explicit "if the phase produces no net contract change … that is recorded as the outcome and no diff is gated" branch.

Under Outcome A, **Task 2 of this plan does NOT run** (it is the contingency-branch flush-diff author, which would run only had 350-02 cleared a GAS-03 win — it did not). Task 2 is recorded "skipped — Outcome A" in `350-03-SUMMARY.md`. No contract is touched in either task.

> Note on the contingency branch: the alternate (NOT-taken) branch is referenced by name throughout this doc only to record that it was excluded. The decisive `## ⮕ EXECUTED BRANCH` heading above (Outcome A) is the single source of truth for which branch ran; this doc never asserts the contingency branch is the active one.

---

## 1. THE GAS CANDIDATE DISPOSITIONS (recorded, from the 350-02 adjudication)

| ID | Candidate (SCAV) | Live site(s) (`453f8073`) | DISPOSITION | Apply at 350? |
|----|------------------|---------------------------|-------------|---------------|
| **GAS-01** | box-ledger cold SSTOREs → ONE warm Sub-stamp (SCAV-348-01) | Afking stamp `GameAfkingModule.sol:793/:794/:840`; cold-ledger symbols grep-ABSENT on the afking path | **CONFIRMED-STRUCTURAL** | **No** — delivered by the 349/349.1 relocation; measured at 351 TST-06 |
| **GAS-02** | `afkingSnapshot`/`afkingFundingOf` cross-contract staticcall → in-context SLOAD (SCAV-348-02) | Hot-path SLOADs `GameAfkingModule.sol:463/:464/:662/:709`; staticcall grep-ABSENT on the hot path | **CONFIRMED-STRUCTURAL** | **No** — delivered by the relocation (`AfKing.sol` deleted); 351 trace assertion |
| **GAS-03** | same-slot `claimablePool` accumulate-and-flush across a process batch (SCAV-348-03) | `GameAfkingModule.sol:710` (`claimablePool -= uint128(ethValue)`) | **REJECT** (with reasoning — §2) | **No** — no diff authored |
| (SCAV-348-04) | `AfKing.sol` bytecode retire | `contracts/AfKing.sol` does not exist; `AF_KING` grep-empty | **DISSOLVED / DELIVERED** | No — deploy-cost-only, already banked |
| (SCAV-348-05) | snapshot-batching scaffold dead-path | no equivalent in `GameAfkingModule` | **DISSOLVED** | No — the cross-contract boundary it worked around is gone |
| (SCAV-348-06) | Sub-record storage packing | `struct Sub` 232/256 bits, ONE slot | **DELIVERED-STRUCTURAL** | No — 349.1 single-slot pack landed |
| (SCAV-348-07) | open-side ledger dead-path (afking subset) | afking open `resolveAfkingBox` `LootboxModule.sol:877` (no `boxPlayers` walk / no ledger zeroes) | **DELIVERED-STRUCTURAL** | No — afking open resolves from the stamp + `rngWordByDay[day]` |

**Net:** GAS-01/GAS-02 and SCAV-04/05/06/07 are already delivered by the IMPL relocation (349/349.1, carried under 349.2 `453f8073`); 350 CONFIRMS them, it does not apply. The empirical GAS-01/GAS-02 marginals are measured at 351 TST-06 per `350-TST06-MEASUREMENT-SPEC.md`. The sole code-change candidate (GAS-03) is REJECTED. **Zero contract change beyond the IMPL relocation.**

---

## 2. GAS-03 — WHY REJECTED (the load-bearing disposition, carried from 350-02 §3)

GAS-03 proposed collapsing the per-iteration `claimablePool -= uint128(ethValue)` at `GameAfkingModule.sol:710` into a once-per-batch accumulate-and-flush across the `processSubscriberStage` chunk. **Verdict: REJECT**, on five evidence prongs (all grounded in the live `453f8073` tree, under the `feedback_security_over_gas` floor; v49 REJECT-with-reasoning precedent applied):

- **(a) Warm-write magnitude — ~100 gas × (N−1), NOT ~2.9k × (N−1).** The only batchable shared additive slot on the STAGE loop is `claimablePool` (`:710`), a packed `uint128` (Storage `:365`, slot bits `[16:32]`). After iteration 1 in a chunk the slot is **WARM**, so every subsequent `-=` is a ~100-gas warm SSTORE (post-Berlin/`evm_version=paris`). Collapsing N warm writes saves ~100 × (N−1) — for `SUB_STAGE_BATCH = 50`, ~4,900 gas best-case against a ~262k-per-buy STAGE = **< 0.04% of the chunk.** This is the over-count the 348-inventory's own Skeptic note flagged; the headline ~2.9k applies only to a cold-or-recomputed write, which `claimablePool` is not after iter 1.

- **(b) The off-ETH/pool BURNIE-restore finding (the 349.2 correction).** 349.2 restored `quests.handlePurchase` (`:760`), `recordMintQuestStreak` (`:773`), `affiliate.payAffiliate` (`:806`/`:816`), and `coinflip.creditFlip` (`:831`) onto the lootbox-mode STAGE path — but they are **ALL BURNIE flip-credit, NOT ETH/pool writes** (the code's own comments `:799-805` *"payAffiliate routes BURNIE flip-credit, never ETH"* + `:828-830` *"All BURNIE; no ETH moves"*; the `:710` `claimablePool` debit is byte-unchanged per comment `:742-746`). They mutate neither `claimablePool` nor `prizePoolsPacked` → they add **NO new batchable shared additive slot.** The inventory's large "~0.6–1.2M / 50-sub affiliate/pool flush" figure does not apply to the afking STAGE — there is no per-sub `payAffiliate` ETH/pool cut to batch.

- **(c) `prizePoolsPacked` is NOT on the afking path** — grep-ABSENT in `GameAfkingModule`; written only by the AdvanceModule jackpot-settle, already once-per-advance. No per-sub `prizePoolsPacked` write to batch.

- **(d) The mixed-chunk `purchaseWith` interleave hazard (RESEARCH Open Q1) — decisive.** A `processSubscriberStage` chunk can mix ticket-mode and lootbox-mode subs. Ticket-mode subs delegatecall `purchaseWith` (`GameAfkingModule.sol:713-731`), which itself touches `claimablePool` internally (the 80/20 routing). Under a batch flush of the lootbox `:710` debits, a `purchaseWith`-internal `claimablePool` write from a ticket sub would interleave with (and observe a stale) accumulated-but-not-yet-flushed value — breaking the accumulate-and-flush net-delta identity (a behavior change, not a gas win). Making a flush safe would require proving the accumulator collects ONLY the `:710` lootbox debits AND that every `purchaseWith`-internal `claimablePool` write stays immediate — additional correctness surface the marginal saving does not justify.

- **(e) Cost/benefit under the floor (SOLVENCY-01 surface).** A ~0.04%-of-chunk warm-write saving against: a memory accumulator, a new flush site, a re-grep'd "no mid-loop `claimablePool` read" invariant, the mixed-chunk safety proof, a forced-underflow test, AND net-new audit surface on the **SOLVENCY-01 spine** at TERMINAL (352) — under `feedback_security_over_gas`. Textbook v49 gas-skeptic REJECT: a marginal warm-write saving that adds correctness surface on the solvency spine. **REJECT WITH reasoning; do not re-litigate.** No penny-exact-obligated win survives → no `claimablePool` flush diff is authored.

---

## 3. NO-INVARIANT-TRADED ATTESTATION

No invariant-trading candidate was accepted. The floor-protected sites stay byte-untouched (no diff exists this phase):
- `afkingFunding[src]` per-key debit (`:709`) — the per-account underflow guard / SOLVENCY-01 precondition.
- The swap-pop set-mutation tombstone (CONSENT-02 / H-CANCEL-SWAP-MISS) — `_removeFromSet` `:391`, called `:588`/`:622`/`:676`; `sub.dailyQuantity = 0` `:621`/`:675`.
- The no-orphan guard (`:570`).
- The freeze fields — `sub.scorePlus1` `:793`, `sub.amount` `:794`, `sub.lastAutoBoughtDay` `:840` (FREEZE-03 stamp).
- Fail-loud-on-solvency — the checked `claimablePool -= uint128(ethValue)` at `:710` (class B; never `unchecked`).
- `quests.handlePurchase`/`handleAffiliate` (`:760`) — non-linear completion; NOT batched (§4 carve-out).

---

## 4. CONTRACT-DIFF ASSERTION (Outcome A — no diff, no gate)

- **`git diff --name-only -- contracts/` is EMPTY.** No `contracts/*.sol` file is created, edited, or staged in this phase. `contracts/` is byte-identical to `453f8073`.
- **NO contract-commit gate.** This plan is `autonomous: false` ONLY because Outcome B *could* have touched `contracts/*.sol`. Under the directed Outcome A there is nothing to apply and nothing to commit — per the project rule the ONLY action needing USER approval is committing `contracts/*.sol`, and there is none here, so the close runs hands-off (docs-only).
- **ROADMAP Phase 350 SC4 satisfied via its no-diff branch** (`.planning/ROADMAP.md:144`): *"if the phase produces no net contract change beyond what the IMPL relocation already delivered (all residual wins rejected / NEGATIVE), that is recorded as the outcome and no diff is gated."* That is exactly this outcome.

**Phase 350 outcome: NO net contract change. GAS-01 = CONFIRMED-STRUCTURAL, GAS-02 = CONFIRMED-STRUCTURAL, GAS-03 = REJECTED. Recorded. No diff gated.**

---

## 5. DOWNSTREAM HANDOFF

- **351 TST:** measures the GAS-01/GAS-02 empirical marginals at TST-06 (per `350-TST06-MEASUREMENT-SPEC.md`). **No Outcome-B `claimablePool` byte-identical-vs-per-slice oracle is required** — GAS-03 was REJECTED, so no flush diff exists to prove byte-identical (the conditional TST-06 row is inert). `forge test` stays 351's charge (stale `AfKing.sol`-import reds expected until 351 clears them).
- **352 TERMINAL:** **no net-new GAS contract surface** to delta-audit or sweep from this phase — the FINAL applied surface is the 349/349.1/349.2 fold + box redesign, unchanged by 350.

---

## 6. VALIDITY

**Valid until** the next `contracts/` mutation. The surface is committed at `453f8073`; this outcome is stable while `contracts/` stays byte-identical to it. `git diff --name-only -- contracts/` is EMPTY in this plan.

*Phase: 350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam · Plan: 350-03 · Task 1. Only CLI used: `git grep`/read + the empty-diff assertion (read-only; no `forge`, no ffi, no package install). Task 2 (Outcome-B flush author) SKIPPED — Outcome A.*
