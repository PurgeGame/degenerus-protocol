# Phase 343 — GAS-01 Gas-Opportunity Inventory (ADVISORY / UNVALIDATED)

**Plan:** 343-03 · **Requirement:** GAS-01 · ROADMAP Phase 343 Success Criterion 5 (gas slice)
**Authored:** 2026-05-30 · **Subject HEAD (`contracts/`):** byte-identical to v53 HEAD **`83a84431`**
**Lens:** produced via the **gas-scavenger** lens (`~/.claude/skills/gas-scavenger/SKILL.md` — "The Scavenger": aggressive, intentionally reckless code-removal/gas-candidate generator whose output feeds The Skeptic). The gas-scavenger persona was applied DIRECTLY over the blast-radius files; no skill/sub-agent was nested.
**Optimizer context (from the gas-scavenger lens):** Solidity 0.8.26/0.8.28, `viaIR: true`, **optimizer runs = 2** (deployment-cost-weighted), immutable deployment, delegatecall module system (storage slots MUST match across `DegenerusGame` + `*Module.sol`). With runs=2, **bytecode size dominates** — every removed line saves deployment gas; runtime savings are secondary.

---

## 0. READ THIS FIRST — the whole list is ADVISORY / UNVALIDATED

> **Every candidate below is ADVISORY and UNVALIDATED.** This is the raw gas-scavenger output — aggressive by design. The gas-scavenger persona is **intentionally reckless**: candidates that trade an invariant, double-count, or simply aren't real are **EXPECTED** and acceptable here. That is the persona's job — find every removal/optimization candidate and let The Skeptic disprove the wrong ones.
>
> **The 345 `/gas-skeptic` is the ONLY validation gate.** NOTHING here is validated, approved, or applied at 343. The 345 GAS phase runs `/gas-skeptic` to approve / reject / escalate each candidate **under the `feedback_security_over_gas` floor** — any candidate that trades a solvency invariant against gas is pre-marked for 345 rejection. Do NOT treat any row below as a decision. Do NOT apply any row at 343.
>
> **Paper-only invariant honored:** this plan only READS/greps `contracts/*.sol` and WRITES this Markdown artifact. `git diff --name-only -- contracts/` is EMPTY — zero contract edits.

---

## 1. Baseline + scope

**Baseline already banked (NOT re-counted here):** the v54 de-custody removes the per-batch boundary value transfer (`AfKing.sol:768` `GAME.batchPurchase{value: totalValue}(buys)` → non-payable). That alone saves **~9k gas/buy** (the per-call value-bearing self-call overhead). **GAS-01 enumerates wins BEYOND that ~9k/buy baseline** — every candidate below is incremental to the already-banked de-custody saving.

**Blast radius (D-03 reach = touched files + the accounting spine the solvency proof walks; codebase-wide CLEANUP-03 sweep stays in 345):**
- `contracts/DegenerusGame.sol` (`batchPurchase` `:1824`, `_claimWinningsInternal` `:1462`, `keeperSnapshot` `:2645`, `adminStakeEthForStEth` `:2109`; the new deposit/withdraw/`keeperFundingOf`)
- `contracts/storage/DegenerusGameStorage.sol` (`claimablePool` `:355`, `claimableWinnings` `:402`; the new `keeperFunding`)
- `contracts/AfKing.sol` (de-custodied `_autoBuy` loop + `_resolveBuy` `:789` + the `:809` snapshot fallback + the `IGame` block)
- `contracts/interfaces/IDegenerusGame*.sol` (signature updates)
- `contracts/modules/DegenerusGameJackpotModule.sol` (`distributeYieldSurplus` `:688`)
- `contracts/modules/DegenerusGameGameOverModule.sol` (drain `:86`, sweep `:202`)
- `contracts/StakedDegenerusStonk.sol` + `contracts/DegenerusVault.sol` (recovery-leg removals)
- (read-only) the sDGNRS valuation `:609-612` / `:769-772` / `:858-861`

> All `file:line` below are the ATTESTED lines from `343-GREP-ATTESTATION.md`, re-confirmed against the live tree (byte-identical to `83a84431`).

---

## 2. Gas-scavenger advisory candidate list

> Columns: **ID** | **File:line** | **Type** | **Proposed change** | **Behavior-identical / same-results?** | **Est. saving (runs=2, bytecode-weighted)** | **Confidence** | **Skeptic note (why it might be rejected)**
> Every candidate is tagged **behavior-identical / same-results** per the gas-scavenger contract — the tag is the Scavenger's CLAIM, to be DISPROVEN by the 345 Skeptic, not a guarantee.

| ID | File:line | Type | Proposed change | Behavior-identical? | Est. saving | Confidence | Skeptic note |
|----|-----------|------|-----------------|---------------------|-------------|------------|--------------|
| SCAV-343-01 | `AfKing.sol:768` (de-custody) | redundant_runtime_call | Drop the `{value: totalValue}` value-attachment on the `GAME.batchPurchase` call (non-payable target). | YES — same buys, no value transfer (the ETH already lives in `keeperFunding` game-side). | ~9k/buy (THIS IS THE BANKED BASELINE — listed for completeness, NOT an incremental win) | high | Already banked by de-custody; not double-counted in GAS-01's incremental total. |
| SCAV-343-02 | `AfKing.sol:734-736` / `:768` | redundant_local | `totalValue` accumulator becomes dead once the call is non-payable (no `{value:}` to sum for). Remove the `totalValue += ethValue` accumulation + the local. | YES — `totalValue` only ever fed `{value: totalValue}`; the per-slice `ethValue` already rides in each `BatchBuy`. | ~per-iteration ADD + 1 stack local; small bytecode | high | Skeptic must confirm `totalValue` has NO other reader after de-custody (grep: only `:735` write + `:768` read today). |
| SCAV-343-03 | `DegenerusGame.sol:1831,:1849,:1856` | redundant_check | Post-de-custody `batchPurchase` is non-payable → `spent`/`msg.value` reconciliation (`if (spent != msg.value) revert E();` `:1856`) is dead (no `msg.value`). Replace the `spent` accumulator + the final mismatch check with the per-slice `keeperFunding[b.funder] -= ev` debit; the debit's underflow IS the funding check. | NO (NOT identical) — the check moves from a sum-vs-msg.value equality to per-slice ledger debits; same SAFETY, different mechanism. | removes 1 accumulator + 1 revert-compare; small bytecode | medium | This is a 344 REWRITE, not a removal — flagged so the Skeptic sees the dead `msg.value` reconciliation, NOT to apply at 343. |
| SCAV-343-04 | `DegenerusGame.sol:2648,:2652` (`keeperSnapshot`) | redundant_storage_read | `keeperSnapshot` reads `_goRead(GO_SWEPT...)` once (`:2648`) then branches per-player (`:2652 swept ? 0 : claimableWinnings[...]`). The `swept` SLOAD is already hoisted out of the loop — confirm it is NOT re-read. When extended to also return `keeperFunding[player]`, fold the second per-player SLOAD so the swept-branch covers both in one `swept ? 0 : (...)`. | YES — same returned values; one branch, two reads folded. | ~1 branch/player saved at 344 vs a naive double-branch | medium | A 344-design hint, not a v53 removal. Skeptic: ensure the extended return keeps the `swept` short-circuit for keeperFunding too (post-sweep keeper balance must read 0, mirroring `:2652`). |
| SCAV-343-05 | `AfKing.sol:807-809` (`_resolveBuy`) | redundant_external_call | The per-player `GAME.keeperSnapshot(snap)` single-element staticcall (`:807-809`) is only entered when `reinvestPct > 0 || drainFirst` (`:806`). When the extended snapshot returns `keeperFunding[player]`, the OPEN-E `src == player` common path can read funding from the SAME snapshot instead of a second `keeperFundingOf(src)` staticcall. | YES for the common path (`src == player`) — same value, one staticcall. | ~1 staticcall/player on the OPEN-E common path | medium | D-MR-01 carve-out: the `src != player` operator-funded slice STILL needs the extra `keeperFundingOf(src)` read (snapshot is keyed on `player`). Skeptic must preserve that carve-out — DO NOT collapse it. |
| SCAV-343-06 | `AfKing.sol:298-318` (`receive`/`deposit`/`depositFor`) | unused_function | All three standalone ingress fns are de-custody orphans (CLEANUP-01 #2/#3/#4). Removing them shrinks bytecode (runs=2 win). | YES — no external caller (CLEANUP-01 grep: `.deposit(`/`.depositFor(` → 0 hits; `receive()` ETH ingress moves to `game.depositKeeperFunding`). | ~3 fn bodies of bytecode (largest single removal here) | high | This overlaps CLEANUP-01 removal; the gas win is the bytecode shrink. Skeptic: confirm no raw-ETH-send path relies on AfKing's `receive()` post-de-custody. |
| SCAV-343-07 | `AfKing.sol:117` invariant doc + `:84,:143,:193,:370,:447` comments | vestigial_code | Stale `_poolOf` doc/comments (CLEANUP-01 #12/#13) — zero runtime gas, but with `viaIR` + comments stripped they cost nothing; flag for completeness as the gas-scavenger sweeps vestigial markers. | YES — comments only. | 0 (comments are not bytecode) | low | NOT a gas win (comments cost no gas). Listed because the Scavenger flags vestigial markers; Skeptic will mark "no gas impact — clean up under CLEANUP-01, not GAS." |
| SCAV-343-08 | `DegenerusVault.sol:516-517` + `StakedDegenerusStonk.sol:535,:539` | unused_function / dead_branch | `recoverAfKingPool()` (0 external callers) + the `burnAtGameOver` AfKing-withdraw leg (`:539`) + the sDGNRS `receive()` AF_KING relaxation branch (`:442`) are de-custody dead (CLEANUP-01 #9/#10/#11). Removal shrinks bytecode in TWO non-Game contracts. | YES — proven orphaned after the recovery-leg removal (D-06). | ~1 external fn + 1 statement + 1 branch of bytecode across 2 contracts | high | Overlaps CLEANUP-01; the gas angle is the bytecode shrink in Vault + StakedStonk. Skeptic: honor the D-06 order (remove leg-callers before/with the AfKing views). |
| SCAV-343-09 | `AfKing.sol:719` CEI debit `_poolOf[src] -= ethValue` | dead_storage_write | After de-custody, `_poolOf` (slot 0) is removed; this SSTORE-debit migrates to the Game's `keeperFunding[b.funder] -= ev`. The AfKing-side SSTORE to slot 0 is eliminated from the hot loop. | NO (NOT identical) — the debit MOVES to the Game; net debit count is the same, location changes. | removes 1 hot-loop SSTORE on the AfKing side (offset by the Game-side debit) | medium | NOT a net SSTORE saving — the debit relocates. Skeptic: this is a 344 rewire, not a free removal; net gas is ~neutral (one debit either side of the boundary). |
| SCAV-343-10 | `AfKing.sol:175` `Deposited` event decl + emits `:301,:308,:318,:414` | impossible_trigger / unused_event | If all four `Deposited` emit sites die with the ingress fns (CLEANUP-01 #14), the event decl is removable (bytecode shrink). | YES IF the subscribe-credit rewire (`:413-414`) drops the AfKing-side emit in favor of a Game-side `KeeperFunded`-style event. | event decl + 4 LOG opcodes of bytecode | low | FLAG-for-344: the gas-scavenger lens "What NOT to flag" warns events are part of the API even if unlistened — so this is LOW confidence. Skeptic decides whether off-chain indexers track AfKing `Deposited`. |
| SCAV-343-11 | `DegenerusGame.sol:2116-2120` (`adminStakeEthForStEth` reserve calc) | redundant_storage_read | The reserve calc reads `claimableWinnings[VAULT]` + `claimableWinnings[SDGNRS]` (`:2116-2117`) then `claimablePool` (`:2118`). With keeper funding riding inside `claimablePool` (D-CF-03), this calc is ALREADY correct and needs NO new read — flag that no per-keeper SLOAD is added here. | YES — zero change; the reserve already keys off `claimablePool` which now includes the keeper total. | 0 (a NO-OP confirmation, not a removal) | high | This is a SOLVENCY-01 confirmation surfaced via the gas lens: the Scavenger confirms NO extra read is needed. Skeptic: pure confirmation, no gas action. |

**Incremental-saving framing:** SCAV-343-01 is the BANKED baseline (~9k/buy), explicitly NOT counted in GAS-01's incremental total. The genuine incremental candidates the 345 Skeptic should weigh are SCAV-343-02/-05/-06/-08 (real bytecode/staticcall wins) — SCAV-343-03/-04/-09 are 344-rewrite mechanics surfaced for visibility (net-neutral or design-hints, NOT free removals), and SCAV-343-07/-10/-11 are low/no-gas flags the Skeptic will mostly reject as "no gas impact" or "API surface."

---

## 3. Packing candidate (D-04 — FLAGGED for 345, NOT decided here)

> **This candidate is documented and FLAGGED for the 345 `/gas-skeptic` ONLY. It is NOT evaluated, NOT decided, and NOT applied at 343.** The DEFAULT EXPECTATION is to **keep the separate `keeperFunding` mapping**.

**Candidate:** pack `claimableWinnings` as a struct `{uint128 normal, uint128 keeper}` (one slot per player) instead of carrying `keeperFunding` as a second `mapping(address => uint256)`.

**PLAN-V54 §2 framing (the locked argument the Skeptic inherits):**

- **Width-safe.** `uint128` max ≈ 3.4e20 ETH ≫ total ETH supply; `claimablePool` is already `uint128` (`DegenerusGameStorage.sol:355`), and `claimableWinnings` values are ETH-denominated wei that fit `uint128` with enormous headroom. The two-`uint128`-in-one-slot packing is arithmetically safe.
- **ZERO hot-path benefit.** An auto-buy touches ONE player's funding slot + the `claimablePool` aggregate either way. Whether keeper funding lives in a packed second field of `claimableWinnings[player]` or in a separate `keeperFunding[player]` mapping, the hot path does the SAME number of SSTOREs (one player slot + `claimablePool`). Packing buys nothing on the auto-buy / deposit / withdraw paths.
- **~15+ access-site blast radius on the CENTRAL accounting variable.** `claimableWinnings` is the most-touched ledger in the contract. Packing forces every credit/debit + helper to read/write a struct field instead of a flat `uint256`. The touched sites the Skeptic must weigh include (non-exhaustive, attested):
  - `claimableWinnings[player]` reads/writes in `_claimWinningsInternal` (`DegenerusGame.sol:1464,:1468`),
  - the `keeperSnapshot` per-player read (`:2652`),
  - the `adminStakeEthForStEth` reserve calc reads `claimableWinnings[VAULT]` + `[SDGNRS]` (`:2116-2117`),
  - `claimableWinningsOf` (the external view sDGNRS's `_claimableWinnings()` consumes — `StakedDegenerusStonk.sol:955-956`),
  - the GameOver final-sweep zeroing of `claimableWinnings[VAULT/SDGNRS/GNRUS]` (`DegenerusGameGameOverModule.sol:211-214`),
  - plus every `_processMintPayment` / `_settleClaimableShortfall` / `claimWinnings` credit-debit site and the StakedStonk reads.

  That is the ~9 credit + ~6 debit + helper surface PLAN-V54 §2 cites — **~15+ access sites** on the most central accounting variable.
- **Trades against `feedback_security_over_gas`.** Touching ~15+ sites on the central solvency ledger for ZERO hot-path benefit is exactly the kind of invariant-risk-for-no-gas trade the milestone's `feedback_security_over_gas` floor exists to reject. A packing bug on `claimableWinnings` is a direct solvency-invariant hazard.

**Disposition:** **DEFAULT = keep the separate `keeperFunding` mapping.** This candidate is **FLAGGED for the 345 `/gas-skeptic`** to evaluate against the security-over-gas floor — it is NOT evaluated or decided at 343 (D-04). The structurally-clean separate-mapping design (D-CF-03: keeper total rides inside `claimablePool`) is the SPEC's locked default; the packing is a 345-only optimization question.

---

## 4. Threat-mitigation cross-reference (T-343-08)

| Mitigation requirement (T-343-08) | Where satisfied in this inventory |
|-----------------------------------|-----------------------------------|
| The list is marked ADVISORY / UNVALIDATED with the 345 `/gas-skeptic` named as the only gate | Section 0 + every candidate's "Skeptic note" |
| The packing candidate carries the `feedback_security_over_gas` framing and a default of keeping the separate mapping | Section 3 |
| No win is applied at 343 | Whole doc is paper-only; `git diff --name-only -- contracts/` is EMPTY |

---

## 5. Validity

**Valid until** the next `contracts/` mutation (the 344 IMPL diff — line numbers WILL drift). The 345 `/gas-skeptic` MUST re-confirm each candidate's `file:line` against the then-current tree before validating. **Paper-only assertion:** `git diff --name-only -- contracts/` is EMPTY — zero `contracts/*.sol` edits in this plan. The 345 GAS phase is the sole validation-and-application gate for everything in this inventory.
