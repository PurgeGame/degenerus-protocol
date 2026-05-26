---
phase: 321-spec-design-lock-call-graph-attestation-reconciliation
verification: goal-backward
verdict: PASSED
date: 2026-05-25
deliverable-commit: 779eacc3
note: ledger-reconciliation (deliverable committed pre-outage; this closes the GSD ledger)
---

# Phase 321 — VERIFICATION (SPEC Design-Lock + Call-Graph Attestation + Reconciliation)

**Verdict: PASSED (5/5 success criteria met).**

This phase was delivered by direct design-lock authoring (the v44/v45/v46 audit-milestone
variant), committed as `779eacc3` — `321-SPEC.md` + four `321-ATTEST-*.md` files. A power
outage interrupted the run after that commit but before ledger closure, leaving STATE.md at
"Not started". This VERIFICATION (with `321-01-PLAN.md` + `321-01-SUMMARY.md`) closes the
ledger against the already-committed deliverable; no new design was authored.

**Source mutation check:** `git show --stat 779eacc3` = 5 files, all under
`.planning/phases/321-.../` (1,707 insertions). Zero `contracts/` files touched. The SPEC is
paper-only, as required (SPEC §3 tail: "SOURCE-TREE not yet mutated at SPEC").

---

## Goal-backward verification of the 5 ROADMAP success criteria

### SC1 — FINAL `resolveRedemptionLootbox` signature settled, with apply-order ✅
**Required:** one settled signature carrying BOTH the LOOT-03 boon flip AND the REDEEM-03
changes (`payable` + unchecked `claimableWinnings[SDGNRS] -= amount` debit removed +
`futurePrizePool` credited from `msg.value`), with apply-order recorded.
**Evidence:** SPEC §1 **R1** pins the final signature
`function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external payable`
— SDGNRS-gated, credits `futurePrizePool` from `msg.value`, delegatecalls the now-boon-rolling
common resolver. Apply-order recorded explicitly: (1) REDEEM-03 first (`payable` + DELETE the
`:1802-1806` unchecked debit), (2) LOOT-03 second (boons via R2's `_resolveLootboxCommon`
always-roll, **not** a call-site flag). Anchor `:1788-1838` grep-attested in
`321-ATTEST-REDEEM-CPAY.md` (carried correction **C2**). **MET.**

### SC2 — `claimablePool == Σ claimableWinnings` joint-check documented ✅
**Required:** a documented joint-check spanning PRESALE-06 (80/20 box-ETH move),
CPAY-01/02/03 (msg.value+shortfall), and REDEEM-01/03 (checked `pullRedemptionReserve` +
unchecked-debit removal) proving the three plans stay balanced together.
**Evidence:** SPEC §1 **R3** locks: new `_creditBoxProceeds(boxEth)` (pool += boxEth; credits
VAULT+SDGNRS sum to boxEth); the canonical CPAY shortfall pattern (overpay-reverts, strict
1-wei sentinel, paired `claimableWinnings -= shortfall` / `claimablePool -= shortfall`); new
SDGNRS-gated **checked** `pullRedemptionReserve` (the only surviving `claimable[SDGNRS]` debit,
Defect A's unchecked one deleted in R1). Box-from-claimable proven net-pool-delta-0 for the
claimable portion, pool += msg.value portion. Joint grep gate recorded (every `claimablePool`
mutation matched by an equal `claimableWinnings` move or real ETH; no `unchecked` claimable
subtraction survives the redemption path → REDEEM-08). **MET.**

### SC3 — every cited `file:line` grep-verified vs HEAD; no un-checked "by construction" ✅
**Required:** all 7 plans' anchors grep-verified against `contracts/` HEAD `2a18d622`, drift
corrected, no surviving un-checked "by construction" / "single fn reaches all paths" claim
(Phase 294 inline-duplication precedent re-checked).
**Evidence:** four `321-ATTEST-*.md` files (1,707 lines) — per-anchor MATCH/SHIFTED/ABSENT
tables. **0 ABSENT across all 7 plans** → SPEC §0 verdict "0 IMPL blockers." Counts:
PRESALE 23/5/0 · LOOTBOX-BOON 4/24/0 · DGAS 16/4/0 · DSPIN 11/0/0 · TOMB 6/6-MATCH ·
REDEEM+CPAY table A (R1–R6 etc.). All drift is line-number-only (≤ a few lines; re-grep at
edit time noted). Nine material clarifications captured as carried corrections **C1–C9** that
override plan prose (e.g. `_resolveLootboxCommon` keeps `emitLootboxEvent`+`payColdBustConsolation`;
`CURRENCY_WWXRP=3`; slot-0 has exactly 2 free bytes; 200-ETH auto-end keys on
`LOOTBOX_PRESALE_ETH_CAP`; ETH lootbox hand-off via private `_resolveLootboxDirect` wrapper).
**MET.**

### SC4 — presale-box RNG re-verified freeze-safe ✅
**Required:** box payout reuses the committed index/day RNG word with a domain-separated salt
(`keccak256(rngWord,"PRESALE_BOX")`), entropy unknown at buy-commit + frozen request→unlock,
combined lootbox+box share-one-index / two-domain-separated-draws introduces no new vector.
**Evidence:** SPEC §1 **R4** — box gets its own queue index (mirrors `lootboxEth`/
`lootboxRngWordByIndex`); payout entropy = committed word + salt
`keccak256(abi.encodePacked(rngWord,"PRESALE_BOX"))` (mirrors `AdvanceModule:370-377`
`BONUS_TRAITS` pattern); combined buy → SAME index → one committed word → two domain-separated
draws; freeze-safe by the existing lootbox argument (word committed before player can act,
never re-derived from mutable state). Secure-phase re-verification explicitly flagged for
Phase 322 ("no new mutable SLOAD enters the box roll"). RNG backward-trace +
commitment-window + window-SLOAD-freshness applied per `feedback_rng_*`. **MET.**

### SC5 — earlybird-removal scope grep-confirmed + enum rename pinned + blueprint produced ✅
**Required:** the earlybird-subsystem removal scope grep-confirmed no surviving consumer
before deletion; `Pool.Earlybird`→`Pool.PresaleBox` enum-slot rename targets pinned; plus the
load-bearing per-item IMPL blueprint.
**Evidence:** SPEC §1 **R6** — `Pool.Earlybird → Pool.PresaleBox` rename pinned at
`StakedDegenerusStonk.sol:210-216` + `IStakedDegenerusStonk.sol:10-16` (ordinal 4 preserved,
ABI-safe; `EARLYBIRD_POOL_BPS=1000` allocation unchanged, const renamed). Deletion set pinned:
`_awardEarlybirdDgnrs` (Storage:971-1014) + 4 call sites (MintModule:1210, WhaleModule:263/476/587),
`_finalizeEarlybird` (AdvanceModule:1744-1757) + `EARLYBIRD_END_LEVEL` trigger (:1672-1673) +
state/consts. Candidate-dead `presaleStatePacked` (Storage:843) / level-3 clear
(AdvanceModule:429-431) / 200-ETH auto-end (keyed on `LOOTBOX_PRESALE_ETH_CAP`, Storage:852)
flagged for edit-time grep-confirm-no-consumer before deletion ("if any consumer survives,
keep that flag and note why"). SPEC §2 + the file/edit-order map is the load-bearing input to
Phase 322. **MET.**

---

## Cross-cutting checks

- **No "by construction" survives un-checked** (`feedback_verify_call_graph_against_source`):
  every anchor grepped; 0 ABSENT; inline-duplication re-checked. ✅
- **Single contract IMPL phase preserved:** SPEC §2 enumerates the one batched diff's file set
  and edit order; no `contracts/` mutation at SPEC. ✅
- **Shared-surface reconciliation complete:** the highest-risk overlap (`resolveRedemptionLootbox`
  edited by BOTH LOOT-03 and REDEEM-03) settled to one signature + apply-order (R1); the
  `_resolveLootboxCommon` 5→2 bool reduction settled (R2, C1); single `DegeneretteModule` edit
  (R5). ✅

## Handoff to Phase 322

`321-SPEC.md` §2 (per-item blueprint + file/edit-order map) + §1 R1–R7 + §0 C1–C9 are the
load-bearing inputs. Phase 322 applies the ONE batched `contracts/*.sol` diff — **HELD at the
contract-commit boundary for explicit user hand-review** (no contract commit without it).

**Phase 321: COMPLETE.**
