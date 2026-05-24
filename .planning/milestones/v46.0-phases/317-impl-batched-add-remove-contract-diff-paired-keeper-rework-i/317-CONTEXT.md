# Phase 317: IMPL — Batched ADD+REMOVE Contract Diff + Paired Keeper Rework - Context

**Gathered:** 2026-05-23
**Status:** Ready for planning

<domain>
## Phase Boundary

Apply the locked `316-SPEC.md` design as **one batched, USER-APPROVED `degenerus-audit/contracts/` diff** plus the paired `degenerus-utilities` `AfKing` keeper rework. Protocol side: the 5 PROTO additions (gating on the pinned `AF_KING` constant), the permissionless do-work crank (CRANK-01..04 + REW-01..04), the SUB-09 protocol-sub init wiring, the RM-01..06 legacy removals, and the JGAS-02 daily-ETH split removal. Keeper side: the `AfKing` cursor-sweep / reinvest / two-tier-skip-kill / `batchPurchase`-switch rework.

**The DESIGN is already locked** — signatures, work-type encoding, RM deletion footprint, the compounded −2 storage slot-shift method, the JGAS-02 decision, and the SUB-09 permanent-deity resolution are all fixed by `316-SPEC.md` (verified 5/5). This phase is execution + review, **not** design. No scope creep: anything not in the ROADMAP 317 goal / 316-SPEC belongs to another phase.

**Sensitive-contract boundary:** this is the milestone's contract-mutation phase. Per the project's standing discipline, the protocol diff is presented ONCE at phase end for ONE explicit approval — never pre-approved, never pushed before review.
</domain>

<decisions>
## Implementation Decisions

These four EXECUTION/PROCESS decisions were settled in discussion (the design itself is locked by 316-SPEC.md and is not re-opened here).

### AfKing keeper location & audit scope
- **D-01:** `AfKing.sol` is brought **into `degenerus-audit/contracts/`** as a first-class, canonical contract — audited in-tree alongside the protocol (covered by 318 TST / 320 AUDIT), and part of the ONE approval-gated batched diff. This was chosen over "audit-only frozen copy," so `degenerus-audit/contracts/AfKing.sol` is the **canonical source**, not a snapshot.
- **D-01a (consequence):** With AfKing in `contracts/`, the contract-commit-guard hook now covers it, and it is a large NEW-file addition inside the single approved diff.
- **D-01b (HOW-item for researcher/planner, not a user decision):** The `degenerus-utilities` repo must be reconciled to consume/deploy this canonical AfKing (import or deploy-script update) rather than maintain a divergent `StreakKeeperV2`. Resolve the single-source-of-truth + deploy path during research.

### Keeper-diff approval discipline
- **D-02:** The `degenerus-utilities` `AfKing` rework diff is **also presented for explicit USER review before commit**, in the same review moment as the protocol diff — same discipline, because it is deployed contract code. (Overrides the ROADMAP's "AGENT-COMMITTED keeper" default; the commit-guard hook does NOT watch the other repo, so this gate is enforced manually by the executor pausing for approval.)

### Test/mock scope at IMPL (317) vs TST (318)
- **D-03:** 317 does **compile-fixes only** on `contracts/test` + mocks — patch just enough references to deleted symbols so the tree COMPILES (`forge build` / test-build green = SC#1). It does NOT add coverage or fix behavioral assertions. Behavioral test rework + new subscription/crank/removal coverage is **318 TST**. (The RM grep criterion already excludes `contracts/test`+`mocks`; this resolves the tension that Foundry's `forge build` compiles `test/` too, so leaving them fully untouched could fail SC#1.)

### Batched diff review format
- **D-04:** The protocol diff is presented for approval as: (1) a **requirement-mapped summary** (PROTO-01..05 / RM-01..06 / JGAS-02 → file:hunk), (2) the **full `git diff`**, and (3) the **`forge inspect` storage-layout before/after** so the re-derived −2 slot constants are verifiable — all in one review.

### Claude's Discretion
- Cross-repo authoring sequence (protocol `batchPurchase` signature vs the keeper's call site — which is authored first) is a technical sequencing decision left to the planner/executor; the contract is that the keeper's `batchPurchase` call MUST match the locked PROTO-04 signature.
- The exact mechanism degenerus-utilities uses to consume the canonical AfKing (D-01b) is a research/planning HOW-item.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked design (load-bearing — read FIRST)
- `.planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-SPEC.md` — **THE locked v46.0 add+remove+JGAS design across all 42 requirements.** Signatures, work-type encoding, RM-01..06 footprint, the compounded −2 storage slot-shift plan, the JGAS-01/02 decision, SUB-09 permanent-deity resolution, the `## Call-Graph Attestation` (grep-verified file:line substrate). This is the non-negotiable instruction set for the diff — every deviation is a defect.
- `.planning/phases/316-spec-crank-subscription-legacy-removal-design-lock-spec/316-RESEARCH.md` — §1 (RM re-verified line numbers) + §J1 (JGAS footprint) — the file:line substrate behind the SPEC.

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — the 42 v46.0 requirement IDs + owning-phase traceability (317 primary-owns PROTO-02..05, CRANK-01..04, REW-01..04, SUB-01..08, RM-01..03/05/06, JGAS-02; PROTO-01/SUB-09/RM-04/JGAS-01 design-locked at 316).
- `.planning/ROADMAP.md` §"Phase 317" — the detailed IMPL goal + the 5 success criteria + the wave shape (1 user-approved batched contracts/ commit + agent-committed planning/docs; keeper now reviewed too per D-02).

### Source design plans (background intent)
- `.planning/PLAN-CRANK-DO-WORK-INCENTIVE.md` — the ADD-half (crank + subscription) design rationale.
- `.planning/PLAN-V47-REMOVE-AFKING-ETH-AUTOREBUY.md` — the REMOVE-half (legacy AFKing + free ETH auto-rebuy) design rationale.

### Keeper source (paired rework subject)
- `../degenerus-utilities/contracts/StreakKeeperV2.sol` — the keeper to be reworked into `AfKing` and brought in-tree (D-01). Re-grep-verify every cited keeper file:line pre-patch.
- `../degenerus-utilities/` (foundry repo: `contracts/`, `script/`, `test/`, deploy broadcasts) — the paired repo whose deploy/wiring must be reconciled to the canonical AfKing.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_hasAnyLazyPass` (DegenerusGame) — KEEP + rename private→external view as PROTO-01 (no body change); it is the keeper's pass-OR-pay gate (RM-04 reconciliation). The single cross-half coupling — do NOT delete.
- The Deity bit is ALREADY set on SDGNRS/VAULT in the `DegenerusGame` constructor (`:222`/`:223`) — SUB-09 permanent-deity free-renew needs **no new write**; 317 only PRESERVES that grant byte-unmodified.

### Established Patterns
- RM removal surface spans 9 in-repo contracts: `DegenerusGame.sol`, `DegenerusVault.sol`, `BurnieCoinflip.sol`, `StakedDegenerusStonk.sol`, `modules/DegenerusGamePayoutUtils.sol`, `modules/DegenerusGameJackpotModule.sol`, `interfaces/IBurnieCoinflip.sol`, `interfaces/IDegenerusGame.sol`, `storage/DegenerusGameStorage.sol`. JGAS-02 additionally touches `modules/DegenerusGameAdvanceModule.sol`.
- PROTO target files: `BurnieCoin` (`burnForKeeper` + `AF_KING` constant), `BurnieCoinflip` (`onlyFlipCreditors` + `AF_KING`), `ContractAddresses.sol` (`AF_KING` pin), `DegenerusGame` (`batchPurchase`, `hasAnyLazyPass` view).
- Storage slot constants: compounded −2 shift (`autoRebuyState`@19 + `resumeEthPool`@33) — derive with ONE combined `forge inspect` pass, never blind −1 (per 316-SPEC `## Storage Slot-Shift Plan`). Storage-layout BREAK is acceptable (pre-launch redeploy-fresh).

### Integration Points
- The keeper's per-player purchase switches to the game's PROTO-04 `batchPurchase(players[],amounts[],modes[])` — signatures must match exactly across the two repos.
- `forge build` compiles `test/` too → drives D-03 (compile-fixes-only). SC#1 requires `forge build` PASS on the patched tree AND the paired keeper compiles.

</code_context>

<specifics>
## Specific Ideas

- Wave shape (from ROADMAP, reinforced by D-02/D-04): the final wave is `autonomous: false` — a USER-APPROVAL checkpoint gates the single batched `contracts/` diff (now including AfKing.sol) AND the keeper diff, presented together as the D-04 mapped-summary + full diff + `forge inspect` storage before/after. Planning/docs are agent-committed; the keeper is reviewed-then-committed (D-02).
- RM grep acceptance (SC#4): zero matches for the afKing/AutoRebuy/JGAS symbol set outside `contracts/test`+`mocks`.

</specifics>

<deferred>
## Deferred Ideas

- **Behavioral test rework + new subscription/crank/removal coverage → Phase 318 TST** (consequence of D-03; this is the planned phase boundary, not a dropped idea). The "full test green in 317" option was explicitly declined in favor of keeping the dedicated TST phase.
- None outside the phase scope — discussion stayed within the IMPL boundary.

</deferred>

---

*Phase: 317-impl-batched-add-remove-contract-diff-paired-keeper-rework-i*
*Context gathered: 2026-05-23*
