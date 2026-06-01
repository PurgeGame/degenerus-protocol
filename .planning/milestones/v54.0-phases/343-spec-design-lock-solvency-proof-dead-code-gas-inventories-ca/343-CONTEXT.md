# Phase 343: SPEC — Design-Lock + Solvency Proof + Dead-Code/Gas Inventories + Call-Graph Attestation - Context

**Gathered:** 2026-05-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Paper-only SPEC design-lock for the v54 Game-side keeper-funding ledger + AfKing de-custody. Produces the
artifacts that let IMPL (344) author ONE fully-reconciled `contracts/*.sol` diff with **zero "by construction"
assumptions**:

1. **BATCH-01** — lock the final signatures/storage/wiring (`batchPurchase` / `BatchBuy` / `purchaseWith` /
   extended `keeperSnapshot` / `keeperFunding` storage / deposit-withdraw-claim merge) + the
   producer-before-consumer IMPL edit-order map.
2. **SOLVENCY-01 / SOLVENCY-03** — PROVE (not assume) the spine: every "free ETH = totalBal − reserved" site
   already reserves the keeper total via `claimablePool`; the sDGNRS redemption valuation is unchanged + correct.
3. **CLEANUP-01** — the de-custody dead-code inventory (grep-attested kill-set vs the v53 HEAD).
4. **GAS-01** — the gas-opportunity inventory for the keeper/funding blast radius.
5. **Call-graph attestation** — every cited `file:line` grep-verified vs v53 HEAD `83a84431`, drift corrected.

**ZERO `contracts/*.sol` mutation.** The design itself is already DESIGN-LOCKED in
`PLAN-V54-KEEPER-FUNDING-GAME-LEDGER.md` (Decisions A2 + B); this phase reconciles + proves + inventories it,
it does NOT re-open the mechanism. The CLEANUP-03 codebase-wide sweep, GAS-02 application, and the packing-
candidate evaluation all belong to **345**, not here.

</domain>

<decisions>
## Implementation Decisions

### Locked design (carried forward — do NOT re-ask)
- **D-CF-01:** Decision **A2** — `AfKing.subscribe` stays `payable`, forwards `msg.value` →
  `game.depositKeeperFunding{value}(subscriber)`; AfKing never retains ETH. Standalone `deposit`/`depositFor`/
  `receive` removed (top-ups go direct to `game.depositKeeperFunding`).
- **D-CF-02:** Decision **B** — post-gameOver `claimWinnings` (`_claimWinningsInternal`,
  `DegenerusGame.sol:1471`) also pays the caller's `keeperFunding` (lazy per-player merge); `withdrawKeeperFunding`
  stays available always (both zero the bucket → no double-spend).
- **D-CF-03:** **No new aggregate** — `keeperFunding` is a per-player mapping whose systemwide total rides inside
  the existing `claimablePool` (`claimablePool == Σ claimableWinnings + Σ keeperFunding`). Inherits the solvency
  wiring for free; the prior-omission class ([[project_yield_surplus_omits_pending_pools]]) is structurally
  impossible.
- **D-CF-04:** The `claimableWinnings` `{uint128 normal, uint128 keeper}` **packing candidate is DEFERRED to 345
  GAS** (default expectation: keep the separate mapping). 343 only *documents/flags* it for the gas-skeptic.

### CRITICAL design-lock correction — `BatchBuy.funder` (found during discussion)
- **D-01 (CRITICAL):** **`BatchBuy` gains a `funder` field (= the resolved `src`).** The Game's non-payable
  `batchPurchase` debits **`keeperFunding[b.funder]` + `claimablePool -= uint128(ev)`**, then
  `purchaseWith(b.player, …, ev)` (the beneficiary). AfKing sets `funder: src` per slice (`src = sub.fundingSource
  == 0 ? player : sub.fundingSource`, `AfKing.sol:686`).
  - **Why:** PLAN-V54 §4 and REQUIREMENTS `AUTOBUY-02` literally say `keeperFunding[b.player] -= ev` — but
    `b.player` is the **beneficiary** (`purchaseWith` target, `DegenerusGame.sol:1839`), while the funding identity
    is **`src`**. In v53 the funder/beneficiary split is handled *entirely AfKing-side* (`_poolOf[src]` debit at
    `:719`, aggregate ETH sent, `BatchBuy` carries only the beneficiary). Moving the debit into the Game on
    `b.player` breaks the **OPEN-E operator-funded case** (`fundingSource != subscriber`, gated by
    `isOperatorApproved` at `AfKing.sol:400-409`): `src ≠ player`, so the §4 skip-check guards
    `keeperFunding[src]` (operator) but the debit hits `keeperFunding[player]` (subscriber, empty) → revert /
    mis-account. `DECUSTODY-03` requires the OPEN-E disposition carry over verbatim with "funding-source ETH
    withdrawable by the source," so `src`-keyed funding MUST survive.
  - **The SPEC MUST record this as a correction to REQUIREMENTS `AUTOBUY-02` and PLAN-V54 §4** (both say
    `b.player`). The VAULT/SDGNRS exemption (`AfKing.sol:696`) stays keyed on the un-spoofable `player`, NOT
    `funder`. Both `BatchBuy` structs (AfKing `:20` + Game `:1796`) change together — redeploy-fresh, so the
    "ABI-identical" doc note (`AfKing.sol:16`) just updates.

### GAS-01 inventory depth
- **D-02:** Build the candidate inventory by **running `/gas-scavenger` now** at SPEC — **advisory candidate list
  ONLY** (NO validation, NO application here; 345 runs `/gas-skeptic` to validate + apply under the
  security-over-gas floor). Aggressive-by-design candidates are expected; 345 rejects the non-real ones with
  reasoning.
- **D-03:** Reach = **touched files + the accounting spine the solvency proof already walks** —
  `DegenerusGame` (batchPurchase/deposit/withdraw/claim/`keeperSnapshot`), `AfKing`, the interfaces,
  Vault/StakedStonk recovery legs, PLUS `distributeYieldSurplus` / gameOver drain / final sweep / `adminStakeEthForStEth`
  / sDGNRS valuation (read anyway for SOLVENCY-01/03). The **codebase-wide CLEANUP-03 sweep stays in 345.**
- **D-04:** The `claimableWinnings` packing candidate is **documented in GAS-01 with the PLAN-V54 §2 framing**
  (zero hot-path benefit; ~15+ access-site blast radius on the central accounting variable; trades against
  `feedback_security_over_gas`) and flagged for the 345 gas-skeptic — NOT evaluated/decided here.

### De-custody finalization
- **D-05:** `AfKing.poolOf(player)` view (`:493`) → **deleted entirely**. Canonical balance source becomes
  `game.keeperFundingOf(player)`. Pre-launch redeploy-fresh, no live integrators; off-chain keeper bot /
  frontend read the Game directly. (Resolves the PLAN-V54 §6 "→ game.keeperFundingOf … (or remove)" choice
  toward remove.)
- **D-06:** The v48 stuck-pool recovery → **hard-removed**, but ONLY after CLEANUP-01 grep-attests each leg is
  truly orphaned (no remaining caller): `DegenerusVault.recoverAfKingPool()` (`Vault:512`), the
  `StakedDegenerusStonk.burnAtGameOver()` AfKing-withdraw leg (`StakedStonk:533`), and the AfKing `receive()`
  AF_KING relaxation. Matches `DECUSTODY-04`'s "removed"; rejects PLAN-V54 §6's "leave as no-ops" alternative.

### Solvency proof rigor (skipped area — resolved by recommendation)
- **D-07:** SOLVENCY-01/03 are **paper-proven AND front-load a focused adversarial red-team** on the proof at
  SPEC (`/economic-analyst` and/or `/contract-auditor`), not self-attest only. The spine (`claimablePool`) is
  the load-bearing concern and the 347 TERMINAL 3-skill sweep is far off — surface any "the keeper total escapes
  a reservation site" hole on paper, before any code. (Scoped to the proof, not a full re-audit.)

### SPEC deliverable shape (skipped area — resolved by recommendation)
- **D-08:** Use the **v50 / Phase-334 multi-doc pattern** rather than one monolithic `343-SPEC.md`: separate
  `343-SOLVENCY-PROOF.md`, `343-GREP-ATTESTATION.md`, `343-CLEANUP-INVENTORY.md`, `343-GAS-INVENTORY.md`,
  `343-IMPL-EDIT-ORDER-MAP.md`, indexed by a `343-SPEC-INDEX.md`. (Phase 334 precedent:
  `334-DESIGN-LOCK-*.md` + `334-GREP-ATTESTATION.md` + `334-IMPL-EDIT-ORDER-MAP.md` + verdict/proof docs.)
  Planner may split/merge filenames, but keep the five concerns as discrete, hand-off-able docs.

### Must-reconcile (planner/researcher — not user-facing, but DO NOT ship un-checked)
- **D-MR-01:** **Extended `keeperSnapshot` returns `keeperFunding[player]`** (`keeperSnapshot` at
  `DegenerusGame.sol:2645`, keyed on the subscriber array) — which equals `keeperFunding[src]` ONLY when
  `src == player` (normal subs + VAULT + SDGNRS, the common path → AUTOBUY-05's "ONE staticcall per player"
  GASOPT-03 holds). The **OPEN-E `src ≠ player` slice needs `keeperFunding[src]`**, which the per-player snapshot
  does NOT carry (`src` resolves at `AfKing.sol:686`, AFTER `_resolveBuy`'s snapshot read). **Recommended
  default:** one extra `game.keeperFundingOf(src)` fallback staticcall for that rare operator-funded slice (mirror
  the existing per-player fallback at `AfKing.sol:809`); common path unchanged. The SPEC must REFINE AUTOBUY-05's
  "ONE staticcall per player" claim to name this OPEN-E carve-out. (Alt the planner/345 may weigh: resolve `src`
  before the snapshot and batch all `src` addresses into the snapshot list — preserves single-staticcall but
  restructures the stack-tight loop; gas-vs-simplicity, defer to 345 if material.)
- **D-MR-02:** **Line-number drift is real** — `batchPurchase` is at `DegenerusGame.sol:1824`, but the docs
  (ROADMAP/REQUIREMENTS/PLAN-V54) cite `:1809`. The `343-GREP-ATTESTATION` pass MUST re-pin EVERY cited anchor
  to its actual line and correct drift in the SPEC; do not trust the doc-cited lines.

### Claude's Discretion
- The exact filenames/split of the multi-doc set (D-08) — keep the five concerns discrete.
- Whether the adversarial red-team (D-07) uses `/economic-analyst`, `/contract-auditor`, or both — planner's call
  based on proof shape; scope it to the solvency proof, not a full sweep.
- How aggressively `/gas-scavenger` is prompted (D-02) — it is advisory; 345 is the validation gate.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### v54 design source-of-truth (read FIRST)
- `.planning/PLAN-V54-KEEPER-FUNDING-GAME-LEDGER.md` — the DESIGN-LOCKED SPEC source (Decisions A2 + B; §2 ledger
  shape; §3 deposit/withdraw; §4 hot path; §5 solvency-wiring table; §6 de-custody; §8 edit map; §10 why a
  separate mapping). **NOTE the §4 `keeperFunding[b.player]` snippet is SUPERSEDED by D-01 (`b.funder`).**
- `.planning/REQUIREMENTS.md` — the 34 v54.0 REQ-IDs (343 owns BATCH-01, SOLVENCY-01, SOLVENCY-03, CLEANUP-01,
  GAS-01). **NOTE `AUTOBUY-02`'s `keeperFunding[b.player]` is corrected to `b.funder` by D-01.**
- `.planning/ROADMAP.md` §"Phase 343" — goal + 5 success criteria + the cross-cutting attestation rule.

### Prior-phase precedent (SPEC deliverable shape — D-08)
- `.planning/milestones/v50.0-phases/334-.../` — `334-SPEC-INDEX.md`, `334-GREP-ATTESTATION.md`,
  `334-IMPL-EDIT-ORDER-MAP.md`, `334-DESIGN-LOCK-*.md`, `334-*-FREEZE-PROOF.md` (the multi-doc SPEC pattern).
- `.planning/milestones/v49.0-phases/329-.../329-SPEC.md` + `329-ATTEST-*.md` (call-graph attestation precedent).

### Contract anchors (grep-verify ALL vs v53 HEAD `83a84431`; tree is byte-identical to it)
- `contracts/DegenerusGame.sol` — `batchPurchase` **`:1824`** (doc says :1809 — DRIFT), `BatchBuy` struct `:1796`,
  `purchaseWith` selector call `:1839`, `keeperSnapshot` `:2645`, `_claimWinningsInternal` `:1471`,
  `adminStakeEthForStEth` `:2113-2123`, master-invariant comment `:18`.
- `contracts/storage/DegenerusGameStorage.sol` — invariant comment `:344-352`.
- `contracts/AfKing.sol` — `_poolOf` slot 0 `:214`, `deposit/depositFor/receive/withdraw` `:298-341`,
  `subscribe` OPEN-E gate `:400-409`, `poolOf` view `:493`, `src` resolution `:686`, funding-skip `:695`,
  CEI debit `:719`, `BatchBuy` build `:726`, batched call `:768`, struct `:20`, `IGame`/`keeperSnapshot` ABI
  `:43/:56`.
- `contracts/modules/DegenerusGameJackpotModule.sol` — `distributeYieldSurplus` `:691-707`.
- `contracts/modules/DegenerusGameGameOverModule.sol` — drain `:98-99/:164`, final sweep `:215`.
- `contracts/StakedDegenerusStonk.sol` — redemption valuation `:612/:772/:861`, `burnAtGameOver` AfKing leg `:533`.
- `contracts/DegenerusVault.sol` — `recoverAfKingPool()` `:512`.

### Related memory (audit posture / dispositions)
- `open-e-operator-approval-trust-boundary` — the 4-protection OPEN-E disposition (carries over verbatim;
  funding-source ETH now `keeperFunding[src]`, withdrawable by the source).
- `project_yield_surplus_omits_pending_pools` — the prior-omission site, now structurally immune (D-CF-03).
- `threat-model-reentrancy-mev-nonissues` — audit weighting (solvency = spine).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`claimableWinnings` / `claimablePool` pattern** (`DegenerusGame.sol`): the exact template for `keeperFunding`
  (per-player mapping + uint128 reserved aggregate, master invariant `balance + steth.balanceOf(this) >=
  claimablePool` at `:18`). `keeperFunding` rides inside `claimablePool` — no new aggregate (D-CF-03).
- **`AfKing.withdraw` un-brickable CEI** (`:330-341`): the template for `withdrawKeeperFunding` (debit before
  send; re-entrant second call reverts on the debit). Carries the USER-LOCKED "cancel-then-withdraw always
  succeeds / never strands ETH" invariant.
- **`AfKing.depositFor`** (`:317`): the mirror for `depositKeeperFunding(address) payable`.
- **Per-player snapshot fallback** (`AfKing.sol:809`, `GAME.keeperSnapshot(snap)`): the pattern to reuse for the
  OPEN-E `keeperFunding[src]` extra read (D-MR-01).

### Established Patterns
- **Atomic non-brick** (`batchPurchase` reverts the whole batch on a poisoned slice) is preserved and *more*
  obviously correct in v54 (a slice revert rolls back; `advanceGame()` is an independent permissionless
  entrypoint → the game never freezes; subscribers retry next cycle).
- **Fresh-vs-recycled affiliate labeling** (`DegenerusAffiliate.payAffiliate:493-505`): keeper ETH spent as
  `ethValue` (DirectEth/fresh) earns the fresh 20-25% rate — the reason `keeperFunding` stays a SEPARATE bucket
  (not merged into `claimableWinnings`, which would relabel it recycled-5%). PLAN-V54 §10.

### Integration Points
- The producer-before-consumer IMPL edit order (BATCH-01 deliverable, for 344): storage `keeperFunding` +
  `BatchBuy.funder` → Game deposit/withdraw/`batchPurchase`/`keeperFundingOf`/`_claimWinningsInternal` merge +
  extended `keeperSnapshot` → interfaces (`IDegenerusGame*`, non-payable `batchPurchase`) → AfKing de-custody +
  `funder=src` wiring + v48-recovery removal. No file ships an intermediate broken state.
- **Verified:** the working tree (`6833cf59`) is byte-identical to v53 HEAD `83a84431` in `contracts/` (only docs
  commits since) → the call-graph attestation greps the LIVE tree directly; no SHA checkout needed.

</code_context>

<specifics>
## Specific Ideas

- The SPEC's job is the audit-discipline maxim "no 'by construction' / 'single fn reaches all paths' claim
  survives un-checked" (`feedback_verify_call_graph_against_source`). The `BatchBuy.funder` finding (D-01) and the
  `keeperSnapshot` src gap (D-MR-01) are concrete instances — the SOLVENCY-01 proof must walk EACH reservation
  site against source, not assume.
- `feedback_security_over_gas` governs the whole milestone: the keeper bucket rides inside `claimablePool`
  precisely to inherit correct solvency wiring; GAS-01 candidates that trade an invariant are pre-marked for 345
  rejection.

</specifics>

<deferred>
## Deferred Ideas

- **CLEANUP-03 codebase-wide unused-code sweep** → 345 (343's CLEANUP-01 is de-custody orphans only).
- **GAS-02 validation + application** (gas-scavenger → gas-skeptic) → 345 (343 only enumerates).
- **`claimableWinnings` `{uint128 normal, uint128 keeper}` packing evaluation** → 345 gas-skeptic (D-04).
- **Generalized "any operator-approved party may spend my `claimableWinnings`"** → out of v54 (larger blast
  radius; PLAN-V54 §10 / REQUIREMENTS "Future Requirements").
- None of the above are scope creep into 343 — all are downstream milestone phases.

</deferred>

---

*Phase: 343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca*
*Context gathered: 2026-05-30*
