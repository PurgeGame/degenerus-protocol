# Phase 322: IMPL — The ONE Batched Contract Diff (all 7 items) — Context

**Gathered:** 2026-05-25
**Status:** Ready for planning
**Source:** Design-lock synthesis from Phase 321 SPEC (no discuss-phase needed — all decisions LOCKED, zero open questions per ROADMAP).

<domain>
## Phase Boundary

Apply ALL seven v47.0 work items as a SINGLE reconciled `contracts/*.sol` diff, exactly as
blueprinted in `321-SPEC.md` §2 (per-item IMPL checklist + file/edit-order map). The diff is
applied to `contracts/`, locally compiled + tested, then **HELD at the contract-commit
boundary** — NEVER committed without explicit user hand-review of the batched diff.

The seven items (manifest `.planning/PLAN-V47-MILESTONE-SCOPE.md`):
1. **PRESALE** (PRESALE-01..13) — rake-free presale: kill the 20% vault skim + 62% BURNIE bonus; credit-gated boon-less presale boxes (25% credit accrual, 50/40/10 BURNIE/DGNRS/WWXRP roll, 80/20 ETH routing, 50-ETH clamp-close + last-buyer DGNRS sweep + `presaleOver` slot-0 latch); `Pool.Earlybird`→`Pool.PresaleBox`.
2. **LOOT** (LOOT-01..06) — remove the BURNIE-lootbox surface entirely (terminal-paradox closure); unify the 3 ETH lootbox callers to full boons+passes; fix the 10% haircut; `_resolveLootboxCommon` 5→2 bool reduction. KEEP BURNIE→tickets.
3. **DGAS** (DGAS-01..04) — Degenerette `resolveBets` write-batching, same-results, cross-bet flush.
4. **CPAY** (CPAY-01..03) — universal claimable-pay (`msg.value` + shortfall) across whale-module purchases + presale box + the full `external payable` entry sweep.
5. **REDEEM** (REDEEM-01..07) — sDGNRS ETH hard-segregation (`pullRedemptionReserve`, fail-closed) + BURNIE flip-credit-at-submit (`redeemBurnieShare`, net new BURNIE = 0) + `resolveRedemptionLootbox` payable / unchecked-debit removed + gameOver double-count drop; delete the BURNIE reserve apparatus.
6. **DSPIN** (DSPIN-01) — per-currency Degenerette spin caps ETH 25 / BURNIE 15 / WWXRP 5 (retire `MAX_SPINS_PER_BET`). Lands in the SAME `DegeneretteModule` edit as DGAS (R5).
7. **TOMB** (TOMB-01..03) — AfKing `setDailyQuantity(0)` true in-place tombstone + in-sweep reclaim branch (resolves H-CANCEL-SWAP-MISS). ISOLATED (no cross-plan entanglement), joins the same diff.

</domain>

<decisions>
## Implementation Decisions (ALL LOCKED — do not re-litigate)

The complete design lock is `321-SPEC.md`. The planner MUST treat these as binding:

- **§0 — Carried corrections C1–C9** override the underlying plan prose where they conflict
  (e.g. `_resolveLootboxCommon` KEEPS `emitLootboxEvent`+`payColdBustConsolation`, removes only
  `presale`/`allowPasses`/`allowBoons`; `CURRENCY_WWXRP=3`; slot-0 has exactly 2 free bytes;
  200-ETH auto-end keys on `LOOTBOX_PRESALE_ETH_CAP`; ETH lootbox hand-off via the private
  `_resolveLootboxDirect` wrapper; `onlyFlipCreditors` + `consumeCoinflipsForBurn` are SEPARATE
  gates and REDEEM-07 must touch both).
- **§1 — Reconciliation decisions R1–R7** are the cross-plan joint edits. Highest-risk:
  - **R1** — `resolveRedemptionLootbox` FINAL signature: `external payable`, SDGNRS-gated,
    credits `futurePrizePool` from `msg.value`, delegatecalls the now-boon-rolling common
    resolver. Apply-order: REDEEM-03 first (payable + DELETE the unchecked
    `claimableWinnings[SDGNRS] -= amount` debit at `:1802-1806`), THEN LOOT-03 (boons via R2's
    always-roll, NOT a call-site flag).
  - **R2** — `_resolveLootboxCommon` 5→2 bool reduction (fixes the 10% haircut).
  - **R3** — claimable invariant: new `_creditBoxProceeds(boxEth)` (PayoutUtils) + new
    SDGNRS-gated **checked** `pullRedemptionReserve` + canonical CPAY shortfall pattern;
    `claimablePool == Σ claimableWinnings` must stay balanced; NO `unchecked` claimable
    subtraction survives the redemption path.
  - **R4** — presale-box RNG freeze: own queue index, payout entropy = committed word +
    `keccak256(abi.encodePacked(rngWord,"PRESALE_BOX"))`; combined lootbox+box share one index /
    two domain-separated draws. Re-verify freeze-safe at secure-phase (no new mutable SLOAD).
  - **R5** — ONE `DegeneretteModule` edit covers DGAS write-batching + DSPIN per-currency caps.
  - **R6** — earlybird→presale-box subsystem swap; grep-confirm no surviving consumer before
    deleting `presaleStatePacked` / level-3 clear / 200-ETH auto-end; if any consumer survives,
    KEEP that flag and note why.
  - **R7** — AfKing cancel-tombstone (Edits 1+2), ISOLATED.
- **§2 — Per-item IMPL blueprint + file/edit-order map** is the executable checklist. Edit
  order: storage/enums first → helpers → callers → entrypoints → interfaces.
- All economic numbers + design decisions D1–D5 (manifest §4) are LOCKED. No research, no open
  decisions.

### Claude's Discretion
- Plan/wave decomposition and per-task granularity (subject to the constraints below).
- Exact local variable names / helper placement WITHIN the locked signatures and routing.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner + executor) MUST read these before planning or implementing.**

### The design lock (binding)
- `.planning/phases/321-spec-design-lock-call-graph-attestation-reconciliation/321-SPEC.md` — §0 C1–C9, §1 R1–R7, §2 blueprint + edit-order map, §3 success criteria. **THE load-bearing input.**
- `.planning/phases/321-.../321-ATTEST-PRESALE.md` — per-anchor grep tables (PRESALE).
- `.planning/phases/321-.../321-ATTEST-LOOT-DGAS-DSPIN.md` — LOOT + DGAS + DSPIN anchors.
- `.planning/phases/321-.../321-ATTEST-REDEEM-CPAY.md` — REDEEM + CPAY anchors (incl. full bodies).
- `.planning/phases/321-.../321-ATTEST-TOMB.md` — AfKing cancel-tombstone anchors.

### The underlying per-item plans (detail behind the blueprint)
- `.planning/PLAN-V47-MILESTONE-SCOPE.md` — the 7-item manifest (§2 shared surfaces, §4 D1–D5).
- `.planning/PLAN-PRESALE-COIN-BOXES-RAKE-FREE.md` (PRESALE)
- `.planning/PLAN-LOOTBOX-BOON-UNIFICATION.md` (LOOT)
- `.planning/PLAN-DEGENERETTE-RESOLUTION-GAS.md` (DGAS)
- `.planning/PLAN-DEGENERETTE-SPINS-PER-CURRENCY.md` (DSPIN)
- `.planning/PLAN-UNIVERSAL-CLAIMABLE-PAY.md` (CPAY)
- `.planning/PLAN-SDGNRS-REDEMPTION-ACCOUNTING.md` (REDEEM)
- `.planning/PLAN-V47-AFKING-CANCEL-TOMBSTONE.md` (TOMB)

### Scope + requirements
- `.planning/REQUIREMENTS.md` — the 37 IMPL REQ-IDs (acceptance per requirement).
- `.planning/ROADMAP.md` — Phase 322 goal + 6 success criteria.

### Source (read from `contracts/` ONLY — stale copies exist elsewhere and must be ignored)
- The diff spans: `storage/DegenerusGameStorage.sol`, `modules/DegenerusGameMintModule.sol`,
  `modules/DegenerusGameLootboxModule.sol`, `modules/DegenerusGameAdvanceModule.sol`,
  `modules/DegenerusGameDegeneretteModule.sol`, `modules/DegenerusGameWhaleModule.sol`,
  `modules/DegenerusGameGameOverModule.sol`, `modules/DegenerusGamePayoutUtils.sol`,
  `DegenerusGame.sol`, `StakedDegenerusStonk.sol`, `BurnieCoin.sol`, `BurnieCoinflip.sol`,
  `AfKing.sol`, `interfaces/IDegenerusGame.sol`, `interfaces/IStakedDegenerusStonk.sol`,
  `DegenerusVault.sol`, `ContractAddresses.sol` (freely modifiable; none expected).

</canonical_refs>

<scope_fence>
## Hard Constraints (project-specific — NON-NEGOTIABLE)

1. **ONE batched diff, ONE approval.** All seven items' `contracts/*.sol` edits land as a single
   batched diff. The plan presents ONE diff for ONE explicit user hand-review at the END. Do NOT
   split contract approval per item.
2. **NEVER pre-approve contracts.** No plan/task may state or imply that any `contracts/*.sol`
   change is "pre-approved." The contract-commit step is `autonomous: false` and gated on explicit
   user review of the diff.
3. **No contract COMMIT without hand-review.** Applying/editing `.sol` autonomously is fine;
   COMMITTING `contracts/*.sol` is not, until the user reviews the diff. A PreToolUse hook blocks
   ALL commits while `contracts/*.sol` is dirty (bypass only after approval). Therefore: commit
   ALL planning/test/docs BEFORE touching `.sol`.
4. **Security over gas (hard floor).** Real-money, adversarial actors assumed. Reject any gas
   optimization that weakens an invariant — especially RNG non-manipulability / the freeze
   invariant (R4) and the claimable-balance invariant (R3). DGAS is gas-only with a HARD
   "same-results" constraint.
5. **Read/edit `contracts/` ONLY.** Stale copies exist elsewhere; ignore them.
6. **Storage packing maximal; redeploy-fresh.** Pre-launch — storage-layout breaks are fine (no
   migration). Pack to the tightest cap-bounded widths; reuse freed slots (C7: slot-0 has 2 free
   bytes for `presaleOver`).
7. **Comments describe what IS, never what changed / used to be.** No history/changelog in code
   comments.
8. **Grep-verify at edit time.** Anchors drift as the batched diff shifts lines — re-grep every
   cited construct before editing (the SPEC attests against pre-patch HEAD `2a18d622`).
9. **`ContractAddresses.sol`** is freely modifiable (the lone exception to the approval rule).

</scope_fence>

<specifics>
## Specific Ideas

- The single highest-risk reconciliation is `resolveRedemptionLootbox` (edited by BOTH LOOT-03
  and REDEEM-03) — its final signature + apply-order is settled in R1; do not deviate.
- `DegeneretteModule` gets exactly ONE edit covering both DGAS (write-batching) and DSPIN
  (per-currency caps) — R5.
- Because plans 1–6 overlap heavily on shared files, contract edits to the SAME `.sol` file
  CANNOT be parallelized across executor agents (write conflicts). Wave/decomposition must keep
  per-file edits serialized; the v46 precedent landed the contract edits behind a single final
  `autonomous: false` USER-APPROVAL gate.
- TOMB (item 7) is isolated and could be authored independently, but still joins the same diff
  and the same single approval gate.

</specifics>

<deferred>
## Deferred Ideas

- TST proofs (REDEEM-08 repro, DGAS-05 / DSPIN-02 same-results gas, TOMB-04/05) → Phase 323.
- Delta-audit + 3-skill adversarial sweep + closure → Phase 324.
- Secure-phase re-verification of the presale-box RNG freeze (R4) is FLAGGED for execution
  during this phase's verification, but the formal sweep is Phase 324.

</deferred>

---

*Phase: 322-impl-the-one-batched-contract-diff-all-7-items*
*Context synthesized: 2026-05-25 from the Phase 321 design lock (no discuss-phase — zero open decisions)*
