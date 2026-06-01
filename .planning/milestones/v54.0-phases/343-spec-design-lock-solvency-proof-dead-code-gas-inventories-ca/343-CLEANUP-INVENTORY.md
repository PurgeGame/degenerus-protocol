# Phase 343 — CLEANUP-01 De-Custody Dead-Code Kill-Set Inventory

**Plan:** 343-03 · **Requirement:** CLEANUP-01 · ROADMAP Phase 343 Success Criterion 4
**Authored:** 2026-05-30 · **Subject HEAD (`contracts/`):** byte-identical to v53 HEAD **`83a84431`**
**Source of truth:** `343-GREP-ATTESTATION.md` (Wave 1). Every kill-set anchor below is the ATTESTED line — where this doc and `343-RESEARCH.md` disagree, the attestation (and a fresh re-grep) wins.
**Verification method:** every caller grep RE-RUN against the live working tree on 2026-05-30; the exact `grep -rn` command + its hit count is recorded per kill-set item. Doc-cited lines were NOT trusted.

> **Paper-only invariant honored:** this plan only READS/greps `contracts/*.sol` and WRITES this Markdown artifact. `git diff --name-only -- contracts/` is EMPTY — zero contract edits.

---

## 0. Baseline identity — the live tree IS `83a84431`

```
$ git diff --numstat 83a84431 HEAD -- contracts/
            ← (empty output)
```

`git diff --numstat 83a84431 HEAD -- contracts/` returns **EMPTY**. The current working tree's `contracts/` directory is **byte-identical** to the v53 HEAD `83a84431`. Therefore every `grep -rn` run below against the live tree IS a valid attestation against `83a84431` — no checkout, no SHA-pinned blob reads.

---

## 1. What this inventory IS (and is NOT)

This is the **de-custody dead-code kill-set**: every symbol the v54 AfKing→Game `keeperFunding` de-custody (Decision A2 + D-CF-01..04, D-05, D-06) orphans, each with (a) its ACTUAL `file:line` and (b) a repo-wide caller grep proving it is truly orphaned **after the batched 344 removal**. It is the CLEANUP-02 removal input for the 344 IMPL diff — and the proof that nothing still-live is removed.

- **Scope:** de-custody orphans ONLY. The codebase-wide unused-code sweep (CLEANUP-03) stays in **345** — it is NOT here.
- **No application:** 343 is paper-only. 344 removes; this doc enumerates.
- **The D-06 integrity gate (Section 3)** is the producer-before-consumer ordering constraint the 344 edit-order map MUST honor — two views (`withdraw`/`poolOf`) are orphaned ONLY after their two recovery-leg callers are removed in the same batched diff.

---

## 2. The 14-item kill-set (grep-attested)

> Columns: **#** | **Kill-set item** | **Location (actual `file:line`)** | **Kill-set grep target** | **Remaining external callers (repo-wide, non-test) — re-run command + hit count** | **Orphaned after batched removal?**
> Every "re-run" cell records the EXACT command run against the live tree on 2026-05-30 and its hit count.

| # | Kill-set item | Location (actual) | Kill-set grep target | Remaining external callers — re-run command + hits | Orphaned after removal? |
|---|---------------|-------------------|----------------------|----------------------------------------------------|-------------------------|
| 1 | `AfKing._poolOf` mapping (slot 0) | `AfKing.sol:214` | `_poolOf` | `grep -rn '_poolOf' contracts/` → **17 hits, ALL in `AfKing.sol`** (`:84,:117,:143,:193,:214,:300,:307,:317,:330,:334,:370,:413,:447,:493,:695,:715,:719`) — every reference is inside a kill-set fn (#2-#7) or a stale comment (#12/#13). `grep -rln '_poolOf' contracts/` lists ONE non-AfKing file (`DegenerusGame.sol:1819`) — that is a **comment-only** mention ("mis-credited the keeper's own _poolOf"), NOT a symbol reference; DegenerusGame has no `_poolOf` mapping. | **YES** — every live `_poolOf` reference is in the kill-set or rewired |
| 2 | `AfKing.receive()` | `AfKing.sol:298` | — | No external caller (a bare `receive()` is fired by raw ETH sends; standalone top-ups go direct to `game.depositKeeperFunding` post-de-custody). | **YES** |
| 3 | `AfKing.deposit()` | `AfKing.sol:305` | `\.deposit(` | `grep -rn '\.deposit(' contracts/` → **0 hits** (no `.deposit(` call site anywhere; `steth.submit{value:}` is the only stake path). | **YES** |
| 4 | `AfKing.depositFor()` | `AfKing.sol:314` | `\.depositFor(` | `grep -rn '\.depositFor(' contracts/` → **0 hits** | **YES** |
| 5 | `AfKing.withdraw()` | `AfKing.sol:328` (CEI debit `:334`) | `afKing\.withdraw(` | `grep -rn 'afKing\.withdraw(' contracts/` → **2 hits**: `StakedDegenerusStonk.sol:539` + `DegenerusVault.sol:517` — BOTH inside the v48 recovery legs (#9/#10) also being removed. | **YES — but ONLY after #9/#10 are removed (D-06 gate)** |
| 6 | `AfKing.poolOf()` view | `AfKing.sol:492` (return `:493`) | `afKing\.poolOf(` | `grep -rn 'afKing\.poolOf(' contracts/` → **2 hits**: `StakedDegenerusStonk.sol:539` + `DegenerusVault.sol:517` — the SAME two recovery legs only. | **YES — but ONLY after #9/#10 are removed (D-06 gate); DELETED ENTIRELY per D-05 (see Section 4)** |
| 7 | Local CEI debit `_poolOf[src] -= ethValue` | `AfKing.sol:719` | `_poolOf\[src\] -= ethValue` | `grep -rn '_poolOf\[src\] -= ethValue' contracts/` → **1 hit** (`AfKing.sol:719`, its own statement). The whole `src`-debit rewire moves to the Game's non-payable `batchPurchase` (`keeperFunding[b.funder] -= ev`). | **YES** (the statement is removed with the rewire) |
| 8 | `IGame.batchPurchase` **PAYABLE** ABI | `AfKing.sol:43` (the ONLY interface decl) | `function batchPurchase(.*payable` | `grep -rn 'function batchPurchase(.*payable' contracts/` → **2 hits**: `AfKing.sol:43` (interface decl) + `DegenerusGame.sol:1824` (the def). The ONLY `contracts/interfaces/` mention is a **comment** (`IDegenerusGameModules.sol:237` — `grep -rn 'batchPurchase' contracts/interfaces/` → 1 comment hit, NO payable decl). Call site: `AfKing.sol:768` (`{value: totalValue}`). | **n/a — ABI flips payable→non-payable IN PLACE (NOT a deletion); see Section 5** |
| 9 | `DegenerusVault.recoverAfKingPool()` | `DegenerusVault.sol:516` (body `:517`) | `recoverAfKingPool` | `grep -rn 'recoverAfKingPool' contracts/` → **1 hit** (`DegenerusVault.sol:516`, only its own def). **0 external callers.** | **YES — fully orphaned (D-06)** |
| 10 | `StakedDegenerusStonk.burnAtGameOver` AfKing-withdraw leg | `StakedDegenerusStonk.sol:539` (within fn `:535`) | `afKing\.withdraw(afKing\.poolOf` | `grep -rn 'afKing\.withdraw(afKing\.poolOf' contracts/` → **2 hits** (`StakedDegenerusStonk.sol:539` + `DegenerusVault.sol:517`). The leg is ONE statement; `burnAtGameOver()` itself STAYS (it also burns sDGNRS). | **YES (the line only; the fn body remains)** |
| 11 | sDGNRS `receive()` AF_KING relaxation | `StakedDegenerusStonk.sol:442` (within `receive()` `:439`) | `ContractAddresses.AF_KING` (inside `receive()`) | After #10 the AfKing send-back path is gone (`grep -rn 'afKing\.withdraw' contracts/` becomes 0 once #5/#9/#10 removed), so the `msg.sender != AF_KING` allowance branch (`:442`) is dead. | **YES — narrow the guard to GAME-only** |
| 12 | `sum(_poolOf) <= address(this).balance` invariant doc | `AfKing.sol:117` | `sum(_poolOf) <= address(this).balance` | `grep -rn 'sum(_poolOf) <= address(this).balance' contracts/` → **1 hit** (`AfKing.sol:117`, the doc comment). | **YES — stale once `_poolOf` (#1) deleted** |
| 13 | Stale `_poolOf`-referencing comments | `AfKing.sol:84, :117, :143, :193, :370, :447` | `_poolOf` (comment lines only) | The comment subset of the `_poolOf` grep above: `:84` (fundingSource doc), `:117` (invariant — also #12), `:143` (withdraw doc), `:193` (InsufficientPool doc), `:370` (subscribe fundingSource doc), `:447` (stranded-ETH doc). | **YES — update/remove with the rewire** |
| 14 | `Deposited` event | decl `AfKing.sol:175`; emit sites `:301, :308, :318, :414` | `Deposited` | `grep -rn 'Deposited' contracts/AfKing.sol` → **7 hits**: decl `:175`, emit `:301`/`:308`/`:318`/`:414`, doc `:313`/`:361`. All FOUR emit sites are in kill-set fns #2/#3/#4 + the `subscribe` msg.value credit (`:413-414`, rewired to `game.depositKeeperFunding`). | **FLAG for 344 confirmation** — likely fully orphaned after de-custody (the subscribe credit moves to the Game's `KeeperFunded`-style event); NOT asserted final here. |

**Attestation note:** the live tree contains **0** `keeperFunding` references (`grep -rln 'keeperFunding' contracts/` → 0 files). The new Game-side ledger is introduced fresh at 344 — there is no stale/partial definition to reconcile, and no name collision with the kill-set.

---

## 3. D-06 kill-set integrity gate (the producer-before-consumer ordering constraint)

**Items #5 (`AfKing.withdraw`) and #6 (`AfKing.poolOf`) are orphaned ONLY after items #9 and #10 are removed.**

Their entire remaining external caller set is exactly the two v48 recovery legs:

- `DegenerusVault.recoverAfKingPool()` body — `DegenerusVault.sol:517`: `afKing.withdraw(afKing.poolOf(address(this)));`  (item #9)
- `StakedDegenerusStonk.burnAtGameOver()` leg — `StakedDegenerusStonk.sol:539`: `afKing.withdraw(afKing.poolOf(address(this)));`  (item #10)

Both call `afKing.withdraw(afKing.poolOf(...))` — i.e. each recovery leg is the SOLE consumer of BOTH views in one statement. Therefore:

> **344 edit-order constraint (carry to `343-IMPL-EDIT-ORDER-MAP.md`):** the Vault/sDGNRS recovery legs (#9, #10) MUST be removed BEFORE (or atomically with) deleting `AfKing.poolOf` (#6) and `AfKing.withdraw` (#5). Any intermediate file state that deletes the views while a recovery leg still calls them holds a **dangling reference → broken build**. In ONE batched diff this is satisfied trivially; the ordering note exists so a future split-diff cannot accidentally violate it.

This gate is the T-343-07 mitigation (broken-build / dangling-ref DoS): the views are NOT independently dead — their death is gated on the recovery-leg removal.

---

## 4. D-05 — `AfKing.poolOf` is DELETED ENTIRELY (no replacement view on AfKing)

Per **D-05**, `AfKing.poolOf(player)` (`AfKing.sol:492`, return `:493`) is **deleted entirely** — NOT re-pointed at the Game, NOT replaced with a thin forwarding view. The canonical keeper-balance source after de-custody becomes:

```
game.keeperFundingOf(player)
```

Rationale (from CONTEXT D-05): v54 is pre-launch redeploy-fresh with no live integrators; the off-chain keeper bot / frontend read the Game directly. The PLAN-V54 §6 "→ `game.keeperFundingOf` … (or remove)" choice is resolved toward **remove**. No AfKing-side balance view survives the de-custody.

---

## 5. The payable-ABI kill target is NARROWED (item #8) — payable→non-payable IN PLACE

The "`IGame.batchPurchase` payable ABI" kill target is **narrowed to exactly the single interface declaration + the one comment**:

- **`AfKing.sol:43`** — `function batchPurchase(BatchBuy[] calldata buys) external payable;` — the **ONLY** interface declaration of `batchPurchase` in the entire repo (the AfKing-local `IGame` block, `interface IGame {` at `:40`). This flips `payable` → non-payable.
- **`contracts/interfaces/IDegenerusGameModules.sol:237`** — a **comment** (`/// … (not msg.value), so batchPurchase can run many subscriber buys inline in one frame.`), NOT a payable declaration. Refresh the comment to match; it carries no ABI weight.

> `batchPurchase` is **NOT** declared anywhere under `contracts/interfaces/` — the only `contracts/interfaces/` mention is the comment above. The kill target does NOT touch `contracts/interfaces/` ABI.

This is a **payable→non-payable flip IN PLACE**, NOT a deletion. The co-requisite edit sites at 344 (recorded here for the edit-order map, not part of the deletion kill-set) are: the Game def `DegenerusGame.sol:1824` (payable→non-payable + `keeperFunding[b.funder]`/`claimablePool` debit body) and the AfKing call site `AfKing.sol:768` (`GAME.batchPurchase{value: totalValue}(buys)` → no value).

---

## 6. New AfKing IGame ABI to ADD (consumer additions — NOT a kill)

The AfKing-local `IGame` interface block (`AfKing.sol:40-57`) is the consumer of the new Game-side ledger fns. The 344 diff ADDS these rows to the SAME `IGame` block (this is an ADD, recorded here so the kill-set and the additions live in one map):

- `depositKeeperFunding(address) payable` — the deposit entrypoint `AfKing.subscribe` forwards `msg.value` into (mirror of the removed `AfKing.depositFor` shape).
- `withdrawKeeperFunding(uint256)` — the un-brickable CEI withdraw (mirror of the removed `AfKing.withdraw` CEI shape).
- `keeperFundingOf(address) view returns (uint256)` — the canonical balance view replacing the deleted `AfKing.poolOf` (D-05), plus the OPEN-E `src != player` extra-read source (D-MR-01, mirror of `AfKing.sol:809`).
- **extended `keeperSnapshot`** — the existing decl at `AfKing.sol:56` gains a per-player `keeperFunding[player]` return alongside the current `(mintPriceWei, rngLocked_, claimables)`.
- **`batchPurchase` at `AfKing.sol:43` goes non-payable** (item #8 flip) within this same block.

---

## 7. Threat-mitigation cross-reference (T-343-07)

| Mitigation requirement (T-343-07) | Where satisfied in this inventory |
|-----------------------------------|-----------------------------------|
| Every kill-set item carries a repo-wide caller grep proving orphan-after-removal | Section 2 (re-run command + hit count per item) |
| The D-06 integrity gate sequences the v48-recovery-leg removal before `poolOf`/`withdraw` deletion | Section 3 |
| The `Deposited` event + the `IGame` ABI items are FLAGGED for 344 confirmation rather than asserted final | Section 2 #14 (FLAG) + Section 6 (ABI additions are an ADD, not a kill) |

---

## 8. Validity

**Valid until** the next `contracts/` mutation (the 344 IMPL diff). Line numbers WILL drift the moment a contract is edited; the 344 author MUST re-run every grep in this document (or cite a re-pinned successor) and NEVER trust upstream doc-cited lines. **Paper-only assertion:** `git diff --name-only -- contracts/` is EMPTY — zero `contracts/*.sol` edits in this plan.
