# Phase 343 — SPEC Index (the D-08 multi-doc set) + Traceability + Verdict + 344 Hand-Off

**Authored:** 2026-05-30
**Plan:** 343-05 (SPEC — Wave-4 integration; lands LAST)
**Milestone:** v54.0 — Game-Side Keeper-Funding Ledger + AfKing De-Custody
**Requirements (this phase):** BATCH-01, SOLVENCY-01, SOLVENCY-03, CLEANUP-01, GAS-01
**Audit baseline (`contracts/`):** byte-identical to the v53 HEAD **`83a84431`** (`git diff --numstat 83a84431 HEAD -- contracts/` → EMPTY; the live working tree's `contracts/` is the v53 baseline, so every grep in the set IS a valid attestation against `83a84431`).
**SPEC verdict:** **PASS — design DESIGN-LOCKED + reconciled; SOLVENCY-01/03 PROVEN; the D-07 focused red-team SURVIVES with ZERO `FINDING_CANDIDATE`; the GO_SWEPT withdraw-guard LOCKED; ZERO `contracts/*.sol` mutation.**

> This is the navigation + closure index for the Phase-343 SPEC. **This index IS the realization of the D-08 multi-doc SPEC pattern** — six discrete, hand-off-able docs + this index, NOT one monolithic `343-SPEC.md`, per the v50 / Phase-334 precedent (`334-DESIGN-LOCK-*.md` + `334-GREP-ATTESTATION.md` + `334-IMPL-EDIT-ORDER-MAP.md` + the verdict/proof docs, indexed by `334-SPEC-INDEX.md`). It maps every 343 requirement and every ROADMAP Phase-343 success criterion to the doc(s) that satisfy it, records the SPEC verdict, and states the single 344 IMPL hand-off.

---

## 1. Phase summary

Phase 343 is a **paper-only SPEC design-lock** for the v54 Game-side `keeperFunding` ledger + AfKing de-custody (PLAN-V54 Decisions **A2** [relocate the AfKing subscriber ETH pool into the Game as a segregated per-player `keeperFunding[player]` mapping riding inside the existing reserved aggregate `claimablePool` — no new aggregate] + **B** [post-gameOver `claimWinnings` lazily merges the caller's keeper bucket]). It writes ZERO `contracts/*.sol` — the entire phase only READS/greps the contracts and WRITES Markdown. Against the v53 HEAD `83a84431`, this phase:

- **Reconciled + DESIGN-LOCKED** the final signatures (non-payable `batchPurchase(BatchBuy[])` with the `funder` debit; `depositKeeperFunding(address) payable`; the un-brickable CEI `withdrawKeeperFunding(uint256)` with the GO_SWEPT guard as line 1; `keeperFundingOf(address) view`; the extended `keeperSnapshot` returning `keeperFunding[player]`; the `_claimWinningsInternal` Decision-B merge) + the `mapping(address => uint256) keeperFunding` storage shape + the producer-before-consumer edit-order map.
- **PROVED** (not assumed) SOLVENCY-01 (all 5 free-ETH reservation sites reserve `claimablePool` inclusive of the keeper total, with ZERO edits, because the keeper total is a sub-component of `claimablePool` — the omittable-pool class is structurally impossible) and SOLVENCY-03 (the sDGNRS redemption valuation is UNCHANGED + CORRECT — keeper ETH lives in the Game's balance, invisible to sDGNRS's own-balance valuation; the same property the external AfKing pool has today).
- **RED-TEAMED** the solvency proof under a focused two-lens D-07 adversarial pass — and the proof **SURVIVED with ZERO `FINDING_CANDIDATE`**.
- **INVENTORIED** the CLEANUP-01 de-custody dead-code kill-set (14 grep-attested items, D-06 ordered) and the GAS-01 advisory gas-opportunity list (11 candidates + the packing candidate, all UNVALIDATED — deferred to the 345 `/gas-skeptic`).
- **ATTESTED** every cited `file:line` by grep against the live tree, **overturning two un-verified `343-RESEARCH.md` claims** (the `payAffiliate`-does-not-exist claim and the double-invariant-comment claim) — the `feedback_verify_call_graph_against_source` floor in action.

---

## 2. Document set (the D-08 multi-doc SPEC — six discrete docs + this index)

The six sibling docs below are the discrete, hand-off-able SPEC deliverables (the D-08 decision: keep the five concerns discrete rather than one monolith, per the v50 / Phase-334 precedent). Each carries its own grep-attested anchors against `83a84431`; this index ties them together.

| # | Doc (filename) | Plan | One-line purpose | Requirement(s) | ROADMAP SC |
|---|----------------|------|------------------|----------------|------------|
| D1 | `343-GREP-ATTESTATION.md` | 343-01 | Call-graph attestation + per-file Drift-Correction Table — re-pins EVERY cited `file:line` to its ACTUAL current line vs `83a84431`; overturns 2 RESEARCH claims (`payAffiliate` EXISTS at `:388`; the master invariant is single-copy at `:18`, NOT `:5 AND :18`); narrows the payable ABI to one interface decl (`AfKing.sol:43`); confirms `keeperFunding` CONFIRMED-NEW (absent from the whole tree). | BATCH-01 (attestation slice) · GAS-01 (anchor re-pin) | SC5 |
| D2 | `343-SOLVENCY-PROOF.md` | 343-02 | SOLVENCY-01 five-reservation-site walk against source (D-CF-03: `claimablePool == Σ claimableWinnings + Σ keeperFunding`) + SOLVENCY-03 sDGNRS-valuation proof + the GO_SWEPT withdraw-guard LOCK (Section B) + the OPEN-E 4-protection carry-over + the D-01 funder-keyed identity + the 10 charged probes handed to the red-team. | SOLVENCY-01 · SOLVENCY-03 | SC2 + SC3 |
| D3 | `343-SOLVENCY-REDTEAM.md` | 343-02 | The D-07 FOCUSED adversarial red-team on the proof (`/contract-auditor` + `/economic-analyst` lenses, scoped to the proof, NOT a full re-audit) — per-probe dispositions + the verdict + the IMPL-discipline carry-forwards. | SOLVENCY-01 · SOLVENCY-03 (hardening) | SC2 (hardening) |
| D4 | `343-CLEANUP-INVENTORY.md` | 343-03 | CLEANUP-01 de-custody dead-code kill-set — 14 items, each with its ACTUAL `file:line` + a repo-wide caller grep (re-run command + hit count) proving orphan-after-removal; the D-06 producer-before-consumer integrity gate; D-05 (`AfKing.poolOf` deleted entirely). | CLEANUP-01 | SC4 |
| D5 | `343-GAS-INVENTORY.md` | 343-03 | GAS-01 `/gas-scavenger` advisory inventory (11 candidates, ADVISORY / UNVALIDATED — the 345 `/gas-skeptic` is the only gate) + the `claimableWinnings` packing candidate framed under `feedback_security_over_gas` (default = keep the separate mapping). | GAS-01 | SC5 (gas slice) |
| D6 | `343-IMPL-EDIT-ORDER-MAP.md` | 343-04 | BATCH-01 design-lock — the FINAL reconciled signatures + storage shape + the producer-before-consumer edit-order map for the SINGLE 344 IMPL diff (no intermediate broken state, D-06 ordered) + the 4 RESEARCH corrections + the red-team carry-forwards. | BATCH-01 | SC1 |
| — | `343-SPEC-INDEX.md` (this doc) | 343-05 | The index for the D-08 set — requirement/success-criterion traceability + the SPEC verdict + the 344 IMPL hand-off. | (cross-cutting) | (all) |

> **D-08 note:** the discrete-doc-set shape (six docs + this index) is the deliberate v50 / Phase-334 multi-doc precedent — each concern is independently hand-off-able to 344/345 and independently re-greppable when the subject HEAD moves. There is no monolithic `343-SPEC.md`.

---

## 3. Requirement → doc traceability

The five Phase-343 requirements (REQUIREMENTS.md / ROADMAP Phase 343), each mapped to the doc(s) that satisfy it:

| Requirement | Description (abbrev.) | Covering doc(s) | Plan(s) | Status |
|-------------|------------------------|-----------------|---------|--------|
| **BATCH-01** | SPEC design-lock — re-attest the design vs `83a84431` (every `file:line`); lock the final `batchPurchase` / `purchaseWith` / extended `keeperSnapshot` signatures + the `keeperFunding` storage shape + the deposit/withdraw/claim-merge wiring; fix the producer-before-consumer edit order (cross-cutting). | `343-IMPL-EDIT-ORDER-MAP.md` (D6, the lock + edit order) + `343-GREP-ATTESTATION.md` (D1, the attestation it consumes) | 343-04, 343-01 | COVERED |
| **SOLVENCY-01** | PROVEN (not assumed) — every "free ETH = totalBal − reserved" site already reserves the keeper total via `claimablePool`, with NO change. | `343-SOLVENCY-PROOF.md` (D2, Section A — the 5-site walk) + `343-SOLVENCY-REDTEAM.md` (D3, the red-team hardening) | 343-02 | COVERED |
| **SOLVENCY-03** | PROVEN — the sDGNRS redemption valuation is UNCHANGED + CORRECT (keeper ETH invisible to sDGNRS's own-balance valuation); OPEN-E carry-over confirmed. | `343-SOLVENCY-PROOF.md` (D2, Section C + Section D) | 343-02 | COVERED |
| **CLEANUP-01** | The de-custody dead-code inventory — a grep-attested kill-set (vs `83a84431`) of everything the de-custody orphans, each with its kill-set grep target. | `343-CLEANUP-INVENTORY.md` (D4) | 343-03 | COVERED |
| **GAS-01** | The gas-opportunity inventory for the keeper/funding blast radius (beyond the banked ~9k/buy), each tagged behavior-identical; every cited anchor grep-attested vs `83a84431`. | `343-GAS-INVENTORY.md` (D5, the inventory) + `343-GREP-ATTESTATION.md` (D1, the anchor attestation) | 343-03, 343-01 | COVERED |

All five requirements are COVERED by a delivered doc.

---

## 4. ROADMAP success-criterion → doc traceability

The five ROADMAP Phase-343 success criteria, each mapped to the doc(s) that satisfy it:

| Success Criterion (ROADMAP) | Covering doc(s) | Status |
|------------------------------|-----------------|--------|
| **SC1** — the full ledger design is settled in writing (BATCH-01): non-payable `batchPurchase(BatchBuy[])`, `depositKeeperFunding`/`withdrawKeeperFunding`/`keeperFundingOf` signatures, the `keeperFunding` storage shape with NO aggregate (rides in `claimablePool`; invariant comment updated), the extended `keeperSnapshot`, the Decision-B `_claimWinningsInternal` merge — reconciled with the producer-before-consumer edit-order map, no downstream file ships an intermediate broken state. | `343-IMPL-EDIT-ORDER-MAP.md` (D6) | COVERED |
| **SC2** — SOLVENCY-01 is PROVEN, not assumed: each of `distributeYieldSurplus`, the gameOver drain (pre/post-refund), `adminStakeEthForStEth`, and the final sweep attested to reserve `claimablePool` (inclusive of the keeper total) unchanged. | `343-SOLVENCY-PROOF.md` (D2, Section A) + `343-SOLVENCY-REDTEAM.md` (D3, probes 1–6 NEGATIVE-VERIFIED / SAFE_BY_DESIGN) | COVERED |
| **SC3** — SOLVENCY-03 is PROVEN: the sDGNRS redemption valuation is UNCHANGED + CORRECT (keeper ETH in the Game's balance is invisible); the OPEN-E 4-protection disposition confirmed to carry over verbatim (consent gate + `src` resolution + VAULT/SDGNRS exemption unchanged; funding-source ETH now `keeperFunding[src]`, withdrawable by the source). | `343-SOLVENCY-PROOF.md` (D2, Section C + Section D) | COVERED |
| **SC4** — the CLEANUP-01 dead-code inventory is produced: a grep-attested kill-set (vs `83a84431`) of everything the de-custody orphans (the AfKing ETH entrypoints / `_poolOf` / `receive`/`deposit`/`depositFor`/`withdraw`, the v48 stuck-pool recovery legs, the `IGame.batchPurchase` payable ABI, the local CEI debit, the stale comments/event), each with its kill-set grep target. | `343-CLEANUP-INVENTORY.md` (D4) | COVERED |
| **SC5** — the GAS-01 gas-opportunity inventory is produced + every cited `file:line` is grep-attested vs `83a84431`: the blast-radius gas inventory (each tagged behavior-identical; the packing candidate flagged for the 345 gas-skeptic) + every milestone-scope anchor re-pinned with drift corrected ("no by-construction survives un-checked"). | `343-GAS-INVENTORY.md` (D5, the gas inventory) + `343-GREP-ATTESTATION.md` (D1, the anchor attestation + drift corrections) | COVERED |

All five success criteria are COVERED by a delivered doc.

---

## 5. SPEC verdict

**PASS — the Phase-343 SPEC is design-gating-complete.** No design amendment is required before 344 IMPL.

### 5.1 — Design DESIGN-LOCKED + reconciled (BATCH-01)

The final signatures + the `keeperFunding` storage shape + the deposit/withdraw/claim-merge wiring are locked in `343-IMPL-EDIT-ORDER-MAP.md` (Sections 1–2): non-payable `batchPurchase(BatchBuy[])` with the per-slice `funder` debit; `depositKeeperFunding(address) payable`; the un-brickable CEI `withdrawKeeperFunding(uint256)` with the GO_SWEPT guard as line 1; `keeperFundingOf(address) view`; the extended `keeperSnapshot` returning `keeperFunding[player]`; the `_claimWinningsInternal` Decision-B keeper-merge. Storage = `mapping(address => uint256) keeperFunding` with **NO separate `keeperFundingPool` aggregate** — the systemwide total rides inside `claimablePool` (D-CF-03). The producer-before-consumer edit-order map fixes the SINGLE 344 diff sequence with no intermediate broken state.

### 5.2 — SOLVENCY-01/03 PROVEN + red-team-survived

- **SOLVENCY-01:** all 5 free-ETH reservation sites (`distributeYieldSurplus` `JackpotModule:688/:693`; drain pre-refund `GameOverModule:98`; drain post-refund `GameOverModule:163`; `adminStakeEthForStEth` `DegenerusGame:2109/:2118`; `handleFinalSweep` `GameOverModule:202/:215`) reserve `claimablePool` inclusive of the keeper total with **ZERO `contracts/*.sol` edits** (D-CF-03 holds against source). The historical-omission site (`distributeYieldSurplus`) is **structurally immune** — the keeper total is the same `claimablePool` variable, not a separate omittable pool.
- **SOLVENCY-03:** the sDGNRS redemption valuation (`StakedDegenerusStonk.sol:612/772/861`, `ethBal + stethBal + claimableEth − pendingRedemptionEthValue`) reads sDGNRS's own balance + only `claimableWinningsOf(sDGNRS)` (`:955-958`); keeper ETH (owed to subscribers, in the Game's balance) is wholly invisible — **UNCHANGED + CORRECT**, the same property the external AfKing pool has today.
- **D-07 red-team verdict — SURVIVES, ZERO `FINDING_CANDIDATE`** (`343-SOLVENCY-REDTEAM.md`): the focused two-lens pass dispositioned every charged probe **NEGATIVE-VERIFIED or SAFE_BY_DESIGN** (security lens: 6 NEGATIVE-VERIFIED + 2 SAFE_BY_DESIGN over 8 probes; economic lens: 2 NEGATIVE-VERIFIED + 2 SAFE_BY_DESIGN over 4 probes; **0 FINDING_CANDIDATE** across both). The red-team surfaced **no unresolved solvency hole** (the high-severity block-on item). Per the operator's selection of **fully-autonomous execution for Phase 343**, the D-07 gate was **AUTO-APPROVED** (no unresolved hole = nothing to block on) — the proof + the locked GO_SWEPT withdraw-guard carry into 344.

### 5.3 — The GO_SWEPT withdraw-guard LOCKED

The single genuine planning risk (Pitfall 1 / Open Q1): `handleFinalSweep:215` zeroes the `claimablePool` aggregate but cannot iterate unbounded `keeperFunding[*]`, so a naive post-sweep `withdrawKeeperFunding` (`claimablePool -= amount`) would checked-revert (clean DoS, no ETH escapes) or — if ever wrapped in `unchecked` — silently corrupt. **LOCKED (T-343-04):** `withdrawKeeperFunding` MUST place the `GO_SWEPT` guard (`if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();`) as **line 1**, before any debit, mirroring the present precedent `_claimWinningsInternal:1463`; the `claimablePool -= amount` debit stays **checked-math** (no `unchecked`). Red-team probe 6 (security) NEGATIVE-VERIFIED conditional on this lock shipping verbatim.

### 5.4 — The 4 RESEARCH corrections + the double-invariant-comment finding

Recorded so no correction is silently lost into 344 (`343-GREP-ATTESTATION.md` Corrections 1–3b + `343-IMPL-EDIT-ORDER-MAP.md` Section 3):

1. **D-01 — `BatchBuy.funder`:** the Game's non-payable `batchPurchase` MUST debit `keeperFunding[b.funder]` (= the resolved `src`), **NOT** `keeperFunding[b.player]`. REQUIREMENTS `AUTOBUY-02` + PLAN-V54 §4 both literally say `b.player` — a **live trap** (OPEN-E `src ≠ player` would debit the empty subscriber bucket). The fix: both `BatchBuy` structs gain a `funder` field; AfKing sets `funder: src` per slice; the VAULT/SDGNRS exemption stays on the un-spoofable `player` (`AfKing.sol:696`).
2. **`payAffiliate` is the canonical symbol** — `DegenerusAffiliate.sol:388` (fresh-rate logic `:493-505`), the function the keeper-bucket separation rationale (AUTOBUY-03 / PLAN-V54 §10) must cite. The `343-RESEARCH.md` claim that `payAffiliate` "does NOT exist; the function is `handleAffiliate:36`" is **OVERTURNED** — `handleAffiliate` is an unrelated `IDegenerusQuestsAffiliate` quest function (impl `DegenerusQuests.sol:644`). Do NOT wire `handleAffiliate` anywhere in the affiliate-rate path.
3. **Single-interface payable narrowing** — `batchPurchase` is declared `payable` in **exactly one interface**, the AfKing-local `IGame` block (`AfKing.sol:43`); it is NOT declared under `contracts/interfaces/` (the only mention there, `IDegenerusGameModules.sol:237`, is a comment). The payable→non-payable flip narrows to three sites: the AfKing ABI `:43`, the Game def `DegenerusGame.sol:1824`, and the AfKing call site `AfKing.sol:768`.
4. **The GO_SWEPT withdraw guard** (§5.3 above) — the locked first-line revert + checked-math debit.

Plus the **double-invariant-comment finding:** the `343-RESEARCH.md` "master invariant comment appears at `DegenerusGame.sol:5` AND `:18` (TWO copies → update both)" claim is **OVERTURNED** — the master invariant `address(this).balance + steth.balanceOf(this) >= claimablePool` appears **EXACTLY ONCE, at `:18`**; `:5` is `* @title DegenerusGame`. The 344 edit updates the invariant comment at **`:18` only** (plus the storage block at `DegenerusGameStorage.sol:345-354`). *(The literal strings `:5` and `:18` are recorded here; the substantive finding is that the `:5` copy does not exist.)*

### 5.5 — ZERO `contracts/*.sol` mutation

Paper-only invariant honored across the entire phase. `git diff --name-only -- contracts/` is **EMPTY** — zero contract edits in 343-05 and in every sibling plan. The CLEANUP-01 kill-set + the GAS-01 inventory ENUMERATE; they do not apply. The first `contracts/` mutation is the 344 IMPL diff.

---

## 6. 344 IMPL hand-off

**344 IMPL is design-gating-complete from this SPEC set.** The single batched diff hand-off:

- **Authoring source:** the 344 author writes ONE fully-reconciled `contracts/*.sol` diff **against `343-IMPL-EDIT-ORDER-MAP.md`** — the FINAL signatures (Section 1), the storage shape (Section 2), and the **producer-before-consumer edit order** (Section 4: storage + `BatchBuy.funder` → Game functions → interfaces → AfKing de-custody → v48-recovery removal), with **zero "by construction" assumptions** and **zero intermediate broken state**.
- **Solvency gate:** the **`343-SOLVENCY-REDTEAM.md` verdict (SURVIVES — ZERO `FINDING_CANDIDATE`)** is the solvency gate the 344 diff inherits — the SOLVENCY-01/03 proof is design-gating-complete; no design amendment is required before IMPL.
- **The four carry-forwards the 344 diff MUST honor:**
  1. **D-01 funder correction** — debit `keeperFunding[b.funder]` (= `src`), NOT `b.player`; add `funder` to BOTH `BatchBuy` structs; keep the VAULT/SDGNRS exemption on `player`. (The PLAN-V54 §4 / AUTOBUY-02 `b.player` snippets are a live trap if copied verbatim.)
  2. **The GO_SWEPT withdraw-guard as line 1** of `withdrawKeeperFunding`, before any debit (mirror `_claimWinningsInternal:1463`); the `claimablePool -= amount` debit stays **checked-math** (no `unchecked`).
  3. **The D-06 kill-set order** — remove the v48 recovery-leg CALLERS (`DegenerusVault.recoverAfKingPool` `:516-517` + the `StakedDegenerusStonk.burnAtGameOver` AfKing leg `:539`) **BEFORE / atomically-with** deleting the `AfKing.poolOf` (`:492`) / `AfKing.withdraw` (`:328`) views they call — satisfied in ONE batched diff by authoring order (no intermediate dangling reference).
  4. **`payAffiliate` is the canonical symbol** for the fresh-rate / separate-bucket rationale (`DegenerusAffiliate.sol:388`, fresh-rate `:493-505`); do NOT mis-rename it to `handleAffiliate` (the unrelated quest fn).
- **(awareness)** `pullRedemptionReserve` (`DegenerusGame.sol:1981`) is a 4th `claimablePool`-tandem-debit site — keep the keeper bucket disjoint from it (it already is).
- **Re-pin before authoring (CRITICAL):** every grep across the D-08 set is a **point-in-time snapshot of `83a84431`**. The line numbers WILL drift the moment a contract is edited. **If the subject HEAD moves before 344, re-run every grep** (or cite a re-pinned successor); the 344 author MUST cite the ACTUAL re-grepped lines from `343-GREP-ATTESTATION.md` (or a successor), never the upstream doc-cited lines.

---

## 7. Validity + paper-only assertion

**Valid until** the next `contracts/` mutation (the 344 IMPL diff). This index, like the six docs it indexes, is a point-in-time snapshot of `83a84431`.

**Paper-only assertion:** `git diff --name-only -- contracts/` is **EMPTY** — zero `contracts/*.sol` edits in this plan (343-05) or anywhere in Phase 343.
