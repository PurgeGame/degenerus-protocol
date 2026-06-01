# 348-GAS-INVENTORY — Gas-Opportunity Inventory (ADVISORY / UNVALIDATED)

**Phase:** 348 — SPEC · **Plan:** 348-02 · **Authored:** 2026-05-30
**Subject HEAD (`contracts/`):** byte-identical to the v54 de-custody HEAD **`20ca1f79`** (per `348-GREP-ATTESTATION.md` §0: `git diff --numstat 20ca1f79 HEAD -- contracts/` EMPTY)
**Lens:** produced via the **gas-scavenger** lens ("The Scavenger": an aggressive, intentionally-reckless gas-candidate generator whose output feeds The Skeptic). Applied DIRECTLY over the v55 keeper/funding blast radius; no nested skill/sub-agent. **Decision basis: D-348-09** — front-load `/gas-scavenger` at SPEC as an advisory list so 349 IMPL builds the wins in from the start (the Phase-343 D-02 pattern: gas-scavenger-at-SPEC → gas-skeptic-at-GAS).
**Optimizer context:** Solidity `0.8.34`, `via_ir = true`, **`optimizer_runs = 200`**, `evm_version = paris`, delegatecall module system (storage slots MUST match across `DegenerusGame` + `*Module.sol`). At runs=200 both runtime gas and bytecode matter; the v55 wins below are dominated by **runtime SSTORE/STATICCALL** savings on the afking hot path.

---

## 0. READ THIS FIRST — the whole list is ADVISORY / UNVALIDATED

> **Every candidate below is ADVISORY and UNVALIDATED.** This is raw gas-scavenger output — aggressive by design. The gas-scavenger persona is **intentionally reckless**: candidates that trade an invariant, double-count, or simply aren't real are EXPECTED here. That is the persona's job — surface every optimization candidate and let The Skeptic disprove the wrong ones.
>
> **The 350 `/gas-skeptic` is the ONLY validation gate.** NOTHING here is validated, approved, or applied at 348. The 350 GAS phase runs `/gas-skeptic` to approve / reject / escalate each candidate **under the `feedback_security_over_gas` floor**: the freeze / solvency / liveness spine governs — **any win that trades an invariant (a freeze field, a solvency `claimablePool` move, the set-mutation tombstone, the revert-free-by-construction obligation) is REJECTED at 350, not here.** Do NOT treat any row below as a decision. Do NOT apply any row at 348.
>
> **Paper-only invariant honored:** this plan only READS/greps `contracts/*.sol` and WRITES this Markdown artifact. `git diff --name-only -- contracts/` is EMPTY — zero `contracts/*.sol` edits.

---

## 1. Baseline + scope

**Baseline already banked (NOT re-counted here):** the v54 work already landed (a) the non-payable `batchPurchase` (de-custody removed the per-batch boundary value transfer, ~9k/buy) and (b) **per-sender affiliate cap removed → ~22k cold/first-of-level buy** (`6d6aa424`, §6 row 1, ✅ DONE). This inventory enumerates wins **incremental** to those.

**Why most of the v55 win is STRUCTURAL, not a scavenger candidate:** the dominant savings (§6 rows 2–3, the ~120k box-buy + the ~3-5k/sub staticcall→SLOAD) are **inherent to the architecture relocation** — they materialize the moment subscriber state goes game-resident and the box freezes into a per-sub stamp instead of the cold box ledger. They are NOT separable "remove this line" candidates; they ARE the redesign (§3 below). The gas-scavenger candidate list (§2) is the **residual** behavior-identical micro-wins around that relocation.

**Blast radius (the v55 keeper/funding reach — the AfKing process/open path + the box-buy ledger + the affiliate/pool flushes):**
- `contracts/AfKing.sol` — the `_autoBuy` loop (`:495`), `_resolveBuy` (`:727`), the per-player `afkingSnapshot`/`afkingFundingOf` reads (`:636`, `:744`); the whole contract dissolves into `GameAfkingModule` + Game stubs at 349.
- `contracts/DegenerusGame.sol` — `batchPurchase` (`:1897`, the per-slice `claimablePool -= ev` flush `:1912`), `afkingSnapshot` (`:2720`), `afkingFundingOf` (`:1540`).
- `contracts/modules/DegenerusGameMintModule.sol` — the box-ledger writes `enqueueBoxForAutoOpen` (`:1142`, `:1473`) + `lootboxEth[lbIndex][buyer] =` (`:1159`) + `lootboxPurchasePacked[lbIndex][buyer] =` (`:1306`, `:1328`); `purchaseWith` (`:864`) → `quests.handlePurchase` (`:1222`) + `affiliate.payAffiliate` (`:1269/:1279/:1613/:1623/:1633/:1642`).
- `contracts/modules/DegenerusGameLootboxModule.sol` — the open-side ledger reads/zeroes the afking open replaces (`:505/:529/:553/:555/:558/:560`).
- `contracts/storage/DegenerusGameStorage.sol` — `afkingFunding`, `claimablePool` (`:355`), the new subscriber set + per-sub stamp.

> All `file:line` above are live-tree (== `20ca1f79`) greps; cross-referenced with `348-GREP-ATTESTATION.md` where it pins the same anchors. **The 349 IMPL diff WILL drift these lines — the 350 `/gas-skeptic` MUST re-confirm each against the then-current tree.**

---

## 2. Gas-scavenger advisory candidate list

> Columns: **ID** | **File:line** | **Type** | **Proposed change** | **Behavior-identical / same-results? (the Scavenger's CLAIM, to be DISPROVEN by 350)** | **Est. saving** | **Confidence** | **Skeptic note (why 350 might reject)**
> Status of EVERY row = **ADVISORY / UNVALIDATED**.

| ID | File:line | Type | Proposed change | Behavior-identical? | Est. saving | Confidence | Skeptic note |
|----|-----------|------|-----------------|---------------------|-------------|------------|--------------|
| SCAV-348-01 | `MintModule.sol:1142,:1159,:1306,:1328,:1473` | redundant_storage_write (STRUCTURAL) | Afking box-buy STOPS writing the cold box ledger (`lootboxEth`/`lootboxPurchasePacked` + `enqueueBoxForAutoOpen` + `boxPlayers.push`); the process-pass writes ONE warm-dirty Sub-stamp `(index, amount, day)` instead. | YES — the open re-derives the box from the stamp + `lootboxRngWordByIndex[index]`, identical math to `openLootBox`. | **~120k / afking box-buy** (≈6 cold SSTOREs + push + enqueue ~130k → ~5k warm stamp) | high (structural) | **= §6 row 2; STRUCTURAL to the IMPL relocation — NOT a standalone removal.** The saving IS the redesign. 350/351 confirm-measure the warm-dirty 5k vs cold ~130k and that the two-path open (afking stamp vs human `boxPlayers`) has no shared-state hazard (§8 open item). Freeze-completeness (the stamp carries every outcome-determining field; §10 collapses to `(index,amount,day)` with score/baseLevel/EV-cap read LIVE at open) is the load-bearing invariant — a 351, not a 350, gate. |
| SCAV-348-02 | `AfKing.sol:636,:744`; `DegenerusGame.sol:1540,:2720` | redundant_external_call (STRUCTURAL) | The cross-contract `GAME.afkingSnapshot(...)` / `GAME.afkingFundingOf(src)` STATICCALLs vanish — once subscriber state is game-resident, the process/open passes read `afkingFunding[player]` + the subscriber set via in-context `SLOAD`. | YES — same values, in-context SLOAD instead of a STATICCALL across the AF_KING→Game boundary. | **~3–5k / sub** | high (structural) | **= §6 row 3; STRUCTURAL to the relocation.** The STATICCALL overhead (~2.6k base + calldata/returndata) collapses to a warm SLOAD (~100). 350 confirms; note the D-MR-01 carve-out (the rare OPEN-E `src != player` operator-funded slice read `:636`) becomes a plain in-context `afkingFunding[src]` SLOAD — same value, no boundary. |
| SCAV-348-03 | `DegenerusGame.sol:1912` (per-slice `claimablePool -= uint128(ev)`) + the per-slice `affiliate.payAffiliate` pool credits (`MintModule:1269/:1279/...`) | redundant_storage_write (same-slot aggregate flush) | Across a process batch of N subs, accumulate the same-slot aggregates (`claimablePool` delta, the affiliate/pool pots that are pure additive sums) in a memory local and **flush once** at batch end instead of N times. | CLAIM yes for the genuinely-linear aggregates (`claimablePool`, additive pool pots) — see the **GAS-03 SAFE-WITH-CONDITIONS** carve-out in §4. | **~2.9k × (N−1)** per batched same-slot aggregate; **~0.6–1.2M / 50-sub batch** for the affiliate/pool flush set | medium | **= §6 rows 4–5; this is GAS-03 — a RESIDUAL same-slot batching change, NOT structural** (it is a real code change 350 validates + 351 proves same-results, distinct from the inherent SCAV-348-01/02 wins). **HARD CONDITION (§4): bucket affiliate payout by roll-winner is SAFE; `quests.handlePurchase`/`handleAffiliate` (`MintModule:1222`) MUST NOT be batched — non-linear completion logic.** A warm SSTORE is already only ~100 gas, so the per-iteration → once-per-batch saving is the warm-write count × ~2.9k only where a COLD-or-recomputed write is collapsed; the Skeptic re-derives the real per-slot delta (a naive "2.9k × N−1" over-counts warm writes). |
| SCAV-348-04 | `AfKing.sol` (whole) — `_autoBuy` `:495`, `_resolveBuy` `:727`, the `IDegenerusGame` block `:45-77`, setters, the snapshot fallbacks | unused_function / bytecode_shrink | The entire `AfKing.sol` contract dissolves; its logic moves to `GameAfkingModule`, the Game keeps thin dispatch stubs (see `348-CODE-SIZE-PLAN.md` §3). The standalone AfKing deployed bytecode (9,780 B measured) is retired. | YES — same behavior, relocated; AF_KING address dissolves (a thin shim is an open §8 question). | full AfKing deploy (9,780 B) retired; deploy-gas only | high | Deploy-cost only (not a runtime per-tx win). Cross-refs `348-CODE-SIZE-PLAN.md` (the Game stubs + `GameAfkingModule`'s own ~10-24KB budget). 350 notes the AF_KING-address-dissolution + integrator-shim open item (§8). |
| SCAV-348-05 | `AfKing.sol:600-601,:628-636,:716,:744` (the swap-pop pre-loop chunk batch + the per-player snapshot fallback comments/logic) | redundant_local / dead_path | The pre-loop `afkingSnapshot` chunk batch + the per-player fallback exist ONLY to work around the cross-contract boundary (batch the staticcalls). Once reads are in-context SLOADs (SCAV-348-02), the whole batching scaffold is dead — read `afkingFunding`/claimable per-sub inline. | YES — the batched-snapshot scaffold was a boundary workaround; in-context reads need no pre-batch. | the snapshot-array alloc + the pre-loop chunk pass (memory + a loop) | medium | Folds into SCAV-348-02's relocation. Skeptic: confirm no reinvest/claimable read still needs the batched shape once in-context (the `reinvestPct > 0 || drainFirst` path `:636` reads claimable too — both become inline SLOADs). |
| SCAV-348-06 | `AfKing.sol` Sub-record layout vs `DegenerusGameStorage` | storage_packing | The migrated Sub record + the box-stamp `(index, amount, day)` should pack to minimize slots (§8: the stamp "likely needs the Sub to grow to 2 slots"; §10 collapsed the stamp by reading score/baseLevel/EV-cap LIVE → fewer fields than the §0–§3 framing). Confirm the packed layout so the 2nd slot's warm-dirty cost still beats the cold box ledger (it does: ~5k vs ~130k). | N/A (layout) — same values, fewer/denser slots. | per-stamp slot warm-dirty vs cold; bounded by SCAV-348-01's ~120k | medium | A LAYOUT-design hint for 349, surfaced via the gas lens. Skeptic/IMPL: prove the packed `(index, amount, day)` fits the slot budget; `amount` is full wei (no boon → `amount = spend`, §10), `index`/`day` are narrow. Pre-launch redeploy-fresh → storage break is free. |
| SCAV-348-07 | `LootboxModule.sol:505,:529,:553,:555,:558,:560` (the open-side ledger reads + zeroes) | dead_path (afking subset only) | For the afking open route, the `boxPlayers`-walk + the `lootboxEth`/`lootboxPurchasePacked`/`lootboxDistressEth` read-then-zero (`:555/:558/:560`) is replaced by a stamp-derived open + a `lastOpenedIndex` bump. Humans keep this path unchanged. | YES for the afking subset — the human path (`boxPlayers`) is untouched (two open routes). | a cheap SLOAD-skip on ticket-buying subs (vs walking `boxPlayers`) | low | NOT a removal — the human path KEEPS these reads/zeroes. The afking win is "don't walk `boxPlayers` for subs." Skeptic: ensure the two-path open shares NO mutable state (§8 open item) and `lastOpenedIndex` monotonicity (freeze invariant #4) holds. |

**Incremental-saving framing:** SCAV-348-01/-02 are the BIG STRUCTURAL wins (= §6 rows 2-3) — they are the redesign, confirmed-measured at 350/351, NOT standalone removals. SCAV-348-03 is the genuine RESIDUAL same-slot batching candidate (GAS-03, the real 350-validated code change) — gated by the §4 carve-out. SCAV-348-04/-05/-06/-07 are relocation by-products (bytecode-retire / dead-scaffold / layout-hint / two-path) that fall out of the fold; the Skeptic will treat several as "structural, not a separable candidate" or "deploy-cost only."

---

## 3. §6 scorecard levers (transcribed from PLAN-V55 §6, vs the v54 baseline)

> **GAS-01 + GAS-02 are flagged STRUCTURAL to the IMPL relocation** — the warm Sub-stamp write + the in-context subscriber-set/`afkingFunding` SLOADs ARE the saving (they exist the moment the relocation lands), confirmed-measured at 350/351. **GAS-03 is distinct: a residual same-slot batching change** that lands on top of the relocation (the real 350-validated diff). The first row is the already-banked v54 baseline (not a v55 win).

| Lever | Saving | Status | v55 ID / flag |
|---|---|---|---|
| Per-sender affiliate cap removed | ~22k cold / first-of-level buy | ✅ DONE (`6d6aa424`) — v54 baseline, NOT a v55 win | — (banked) |
| **Box-ledger → warm Sub-stamp + no `boxPlayers.push`** | **~120k / afking box-buy** | v55 | **GAS-01 — STRUCTURAL to the IMPL relocation** (SCAV-348-01) |
| **Cross-contract `afkingSnapshot`/`afkingFundingOf` staticcalls → SLOAD** | **~3–5k / sub** | v55 (module) | **GAS-02 — STRUCTURAL to the IMPL relocation** (SCAV-348-02) |
| Batch same-slot affiliate/pool aggregate flushes across a process batch | ~0.6–1.2M / 50-sub batch | v55 | **GAS-03 — residual batching change, SAFE-WITH-CONDITIONS** (SCAV-348-03; §4) |
| `claimablePool`/`prizePoolsPacked` accumulate-and-flush per batch | ~2.9k × (N−1) | v55 | **GAS-03** (SCAV-348-03; §4) |

**Mechanism notes (PLAN-V55 §2, for 349/350):**
- **GAS-01 (~120k):** the ~6 cold box-ledger SSTOREs + `boxPlayers.push` + `enqueueBoxForAutoOpen` (~130k) → ONE warm-dirty Sub-stamp write (~5k) + the cumulative EV-cap write only at level-crossing. The open-walk costs a cheap SLOAD-skip on ticket-buying subs.
- **GAS-02 (~3–5k/sub):** the current per-subscriber `afkingSnapshot`/`afkingFundingOf` STATICCALLs vanish — the process/open passes read the subscriber set + `afkingFunding` via in-context `SLOAD`, and the open delegatecalls the lootbox materializer in-context.

---

## 4. ⚠ GAS-03 — SAFE-WITH-CONDITIONS (carry VERBATIM into the 350 gas phase)

> This carve-out is **load-bearing** and must be carried verbatim into 350. It is the boundary between a safe batching win and a correctness break, and it sits under the `feedback_security_over_gas` floor.

**SAFE:** **bucket affiliate payout by roll-winner.** Across a process batch, the affiliate/pool aggregates that are **pure additive sums** (the `claimablePool` delta, the additive pool pots credited via `affiliate.payAffiliate` `MintModule:1269/:1279/:1613/...`) may be accumulated in a memory local and flushed once per batch — bucketing the payout by roll-winner is order-independent and same-results, because addition into a slot is associative and the per-slice amounts do not depend on the running aggregate.

**MUST NOT batch:** **`quests.handlePurchase` / `quests.handleAffiliate`** (`MintModule.sol:1222`) — **non-linear completion logic.** Quest completion is NOT a linear accumulation: a quest's state transition (streak/threshold/completion) depends on the per-call sequence and prior state, so collapsing N per-sub `handlePurchase`/`handleAffiliate` calls into one batched call would change quest outcomes (different completions, different streak credit). **Batching this is a behavior change, not a gas win — REJECT at 350.** Each sub's `handlePurchase`/`handleAffiliate` MUST run per-sub, in order.

**Rule for 350:** validate the same-slot aggregate flush ONLY for the linear additive aggregates; leave every `quests.*` completion call per-sub. Any candidate that batches `quests.handleAffiliate`/`handlePurchase` is pre-marked for 350 REJECTION under the security-over-gas floor.

---

## 5. Security-over-gas floor (governs every candidate)

`feedback_security_over_gas` is the milestone floor. The v55 spine — freeze-completeness (the stamp captures all outcome-determining state), index-binding (pre-RNG `LR_INDEX` read once, no straddle), stamped-day determinism (seed the stamped buy-day, never open-time `_simulatedDayIndex()`), no-double-open (`lastOpenedIndex` monotonic), the discharged REVERT-FREE-CHAIN obligation-1 (slice-builder fidelity, the sole no-brick guarantor under the no-try/catch decision D-348-04), and the set-mutation tombstone (the H-CANCEL-SWAP-MISS class) — is NON-NEGOTIABLE. **Any gas candidate that trades any of those for gas is REJECTED at 350, not debated here.** Solvency (`claimablePool` tandem moves) in particular: the same-slot flush (SCAV-348-03) must preserve the exact net `claimablePool` delta the per-slice debits produce — a batching bug there is a direct SOLVENCY-01 hazard, so 350 + 351 prove the aggregate flush is penny-exact vs the per-slice path.

---

## 6. Threat-mitigation cross-reference (T-348-04)

| Mitigation requirement (T-348-04) | Where satisfied in this inventory |
|---|---|
| Every gas candidate tagged ADVISORY / UNVALIDATED with the 350 `/gas-skeptic` named as the only gate | §0 + every candidate's Status + Skeptic note |
| GAS-03 SAFE-WITH-CONDITIONS recorded verbatim (no `quests.handleAffiliate` batching) | §4 |
| The `feedback_security_over_gas` floor governs; an invariant-trading win is rejected | §0 + §5 |
| No win applied at 348 | Whole doc is paper-only; `git diff --name-only -- contracts/` is EMPTY |

---

## 7. Validity

**Valid until** the next `contracts/` mutation (the 349 IMPL diff — line numbers WILL drift). The **350 `/gas-skeptic` MUST re-confirm each candidate's `file:line`** against the then-current tree before validating, and is the sole validation-and-application gate for everything in this inventory. GAS-01/02 are confirmed-measured at 350/351 as structural outcomes of the relocation; GAS-03 is the residual change 350 validates + 351 proves same-results. **Paper-only assertion:** `git diff --name-only -- contracts/` is EMPTY — zero `contracts/*.sol` edits in this plan; the pre-existing `scope.txt` working-tree change is unrelated and untouched.

---

*Phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p · Plan: 348-02. The only CLI used was `grep`/read (read-only, no ffi, no package install).*
