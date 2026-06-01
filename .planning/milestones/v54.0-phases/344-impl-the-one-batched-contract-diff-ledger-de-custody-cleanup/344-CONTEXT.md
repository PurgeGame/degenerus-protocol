# Phase 344: IMPL — The ONE Batched Contract Diff (ledger + de-custody + CLEANUP-02 orphan removal) - Context

**Gathered:** 2026-05-30
**Status:** Ready for planning

<domain>
## Phase Boundary

Author the v54 Game-side keeper-funding ledger + AfKing de-custody + CLEANUP-02 orphan removal as **ONE
reconciled `contracts/*.sol` diff**, producer-before-consumer, `forge build`-clean, then **HOLD at the
contract-commit boundary** (`autonomous: false`) for explicit user hand-review. This is a **contract-boundary
HARD STOP** — the single USER-APPROVED contract IMPL phase of v54.0.

What the diff lands (all shapes settled by the Phase-343 SPEC, not re-opened here):
- A per-player `mapping(address => uint256) keeperFunding` on `DegenerusGameStorage.sol` whose systemwide total
  rides INSIDE `claimablePool` (NO new aggregate; invariant `claimablePool == Σ claimableWinnings + Σ keeperFunding`).
- `depositKeeperFunding(address) payable` / un-brickable CEI `withdrawKeeperFunding(uint256)` (GO_SWEPT guard
  line 1) / `keeperFundingOf(address) view` / the extended `keeperSnapshot` returning `keeperFunding[player]`.
- Non-payable `batchPurchase(BatchBuy[])` with the per-slice `keeperFunding[b.funder]` + `claimablePool` debit
  then `purchaseWith(b.player, …, ev)` at the fresh affiliate rate; atomic non-brick preserved.
- The post-gameOver `_claimWinningsInternal` keeper-merge (Decision B).
- AfKing de-custody (delete `_poolOf`/`receive`/`deposit`/`depositFor`/`withdraw`/`poolOf`; `subscribe` stays
  payable and forwards `msg.value` → `game.depositKeeperFunding`; OPEN-E consent gate + `src` resolution
  unchanged; local CEI `_poolOf` debit dropped; the batch call becomes the non-value `GAME.batchPurchase(buys)`).
- CLEANUP-02 orphan removal (the v48 stuck-pool recovery legs + every CLEANUP-01 kill-set item).

**Out of scope (downstream phases):** the test-suite repair (346 TST owns it); the broader codebase-wide
dead-code sweep CLEANUP-03 + the GAS-02/03 application + the `claimableWinnings` packing eval (345 GAS+CLEANUP);
the internal 3-skill adversarial sweep + delta-audit + `FINDINGS-v54.0.md` (347 TERMINAL).

> **No SPEC.md lives in this phase dir** — the locked requirements ARE the Phase-343 SPEC document set
> (see Canonical References). The planner/executor MUST read `343-IMPL-EDIT-ORDER-MAP.md` first; it is the
> authoring source-of-truth for the single diff.

</domain>

<decisions>
## Implementation Decisions

These split into (A) **new IMPL-execution decisions from this discussion** and (B) **carried-forward LOCKED
design decisions from the Phase-343 SPEC** — restated here only because they are load-bearing and MUST NOT be
copied wrong. The SPEC docs remain the source of truth for full rationale.

### A. New IMPL-execution decisions (this discussion)

#### Cleanup shape (discussed)
- **D-344-01 — v48 recovery-leg removal = PURE removal + traced equivalence.** Remove all three legs
  (`DegenerusVault.recoverAfKingPool` `:516-517`, the `StakedDegenerusStonk.burnAtGameOver` AfKing-withdraw leg
  `:539`, and the sDGNRS `receive()` AF_KING relaxation `:439-444` → narrowed to GAME-only). **Before deleting,
  the 344 author MUST run the actor-consequence trace** (per [[feedback_design_intent_before_deletion]]) and
  DOCUMENT that the v48 recovery is fully replaced for **both VAULT and sDGNRS** by: (a) ungated
  `game.withdrawKeeperFunding`, (b) the retained sDGNRS `receive()` **GAME**-allowance (step 5c — the Game's
  withdraw `.call` send-back has `msg.sender == GAME`), and (c) the Decision-B `claimWinnings` keeper-merge.
  The trace MUST explicitly confirm **VAULT can receive the Game's withdraw `.call`** and **sDGNRS's GAME-allowance
  permits it**. **If the trace finds a recoverability gap, ESCALATE before deleting** — do not delete the safety
  code on the grep-orphan proof alone. (The 343 inventory proved grep-orphan/no-caller; this decision adds the
  required actor-consequence layer.)
- **D-344-02 — Deletion shape = PURE DELETE, no added comment.** Delete the custody surface cleanly; rely on the
  structural no-receive guarantee (AfKing has no `receive()`/payable path after de-custody, so plain ETH sends
  revert). Do NOT add a NatSpec "AfKing holds no ETH" line and do NOT add a defensive balance==0 assert (a dead
  guard against an unreachable state). The stale `_poolOf`-referencing comments (kill-set #12 `sum(_poolOf) <=
  address(this).balance` invariant doc + #13 `AfKing.sol:84,:117,:143,:193,:370,:447`) are **removed, not
  replaced**.
- **D-344-03 — CLEANUP-02 / CLEANUP-03 boundary = the 343 inventory scope.** 344-CLEANUP-02 removes the
  de-custody orphans ONLY (the 14-item `343-CLEANUP-INVENTORY.md` kill-set + the v48 recovery legs). The
  codebase-wide unrelated dead-code sweep is **CLEANUP-03 → 345**. No widening of removal scope at 344.

#### Planning posture (discussed)
- **D-344-04 — SKIP RESEARCH; plan directly off `343-IMPL-EDIT-ORDER-MAP.md`.** Run
  `/gsd:plan-phase 344 --skip-research`. The phase is fully specified (final signatures, storage shape, edit
  order, corrections, red-team carry-forwards all locked); a research pass adds latency with no new information
  ([[feedback_skip_research_test_phases]]).
- **D-344-05 — The mandatory pre-author re-grep = the EXECUTOR'S FIRST ACTION.** The plan cites the SPEC's
  grep-attested anchors as the starting reference, and instructs the executor to **re-run every grep from
  `343-GREP-ATTESTATION.md` against the live tree and re-pin anchors as its FIRST step, before writing any edit**
  (lines drift the instant the first edit lands). NOTE: at the time of this discussion the `contracts/` tree is
  byte-identical to baseline `83a84431` and clean (`git diff --numstat 83a84431 HEAD -- contracts/` → EMPTY), so
  the SPEC anchors are currently valid — the re-grep is the discipline floor ([[feedback_verify_call_graph_against_source]]),
  not a known-drift fix.
- **D-344-06 — Plan structure = ~5 plans per producer-before-consumer edit-order step** (storage+`BatchBuy.funder`
  → Game fns → interfaces → AfKing de-custody+`funder=src` → v48-recovery removal). All edits authored first, then
  ONE combined diff + ONE approval ([[feedback_batch_contract_approval]]); after approval split into atomic
  per-plan commits for clean SUMMARY mapping (`git add --patch` / sequential staging). Executor subagents NEVER
  commit (hook-enforced — [[feedback_contract_commit_guard_hook]]); the orchestrator owns all commits, deferred
  past the approval gate, with `CONTRACTS_COMMIT_APPROVED=1` on the approved `git add contracts/...`.

#### Verify depth (skipped area — locked to recommended default)
- **D-344-07 — `forge build`-clean ONLY at 344, then HOLD; defer ALL test work to 346 TST.** SC5 requires
  `forge build` clean. The ABI change (non-payable `batchPurchase`, `BatchBuy.funder`, deleted AfKing
  `deposit`/`withdraw`/`poolOf`/`receive`) WILL break existing test-file *compilation* — that breakage is
  EXPECTED and is **346 TST's** charge to repair (`test/` edits are also approval-gated; not touched at 344).
  344 verifies the contracts compile clean and HOLDS; it does not attempt `forge test`.

#### Events (skipped area — locked to recommended default)
- **D-344-08 — Event design.** New Game-side events `KeeperFunded(address indexed player, uint256 amount)` (emitted
  in `depositKeeperFunding`) and `KeeperWithdrew(address indexed player, uint256 amount)` (emitted in
  `withdrawKeeperFunding`, keyed on `msg.sender`). AfKing's `Deposited` event (kill-set #14, decl `AfKing.sol:175`,
  emits `:301,:308,:318,:414`) is **REMOVED** — fully orphaned by de-custody; subscribe-side observability now
  comes from the Game's `KeeperFunded`. AfKing's existing `SubscriptionUpdated` (with indexed `fundingSource`,
  v48) stays UNCHANGED. *(If the author finds a non-orphaned `Deposited` emit during the re-grep, surface it
  rather than deleting blind.)*

### B. Carried-forward LOCKED design decisions (Phase-343 SPEC — DO NOT re-open; restated because load-bearing)

- **⚠ D-01 (LIVE TRAP) — debit `keeperFunding[b.funder]`, NOT `keeperFunding[b.player]`.** ROADMAP Phase-344
  Success Criterion 3 AND `REQUIREMENTS.md` `AUTOBUY-02` AND PLAN-V54 §4 all literally say `b.player` — copying
  that verbatim breaks the OPEN-E operator-funded case (`src != player` debits the empty subscriber bucket). Both
  `BatchBuy` structs gain a `funder` field (= the resolved `src`); AfKing sets `funder: src` per slice
  (`AfKing.sol:726`, `src = sub.fundingSource == 0 ? player : sub.fundingSource` at `:686`); the VAULT/SDGNRS
  exemption stays keyed on the un-spoofable `player` (`AfKing.sol:696`). The non-payable `batchPurchase` `spent ==
  msg.value` guard is GONE; `claimablePool -= uint128(ev)` stays CHECKED math.
- **GO_SWEPT guard = LINE 1 of `withdrawKeeperFunding`**, before any debit (mirror `_claimWinningsInternal:1463`);
  `claimablePool -= amount` stays **checked-math** (no `unchecked`). Un-brickable strict CEI (debit
  `keeperFunding[msg.sender]` + `claimablePool` BEFORE the `.call`).
- **D-06 kill order** — remove the v48 recovery CALLERS (`DegenerusVault.sol:516-517` + `StakedDegenerusStonk.sol:539`)
  BEFORE/atomically-with deleting the `AfKing.poolOf` (`:492`) / `AfKing.withdraw` (`:328`) views they call. ONE
  batched diff satisfies this by authoring order — no intermediate dangling reference / broken build.
- **D-05** — `AfKing.poolOf` is DELETED ENTIRELY (no forwarding view); canonical balance source = `game.keeperFundingOf`.
- **D-MR-01** — the OPEN-E `src != player` slice needs ONE EXTRA `game.keeperFundingOf(src)` staticcall (mirror
  `AfKing.sol:809`); the common path (`src == player`) stays single-staticcall via the extended `keeperSnapshot`
  (GASOPT-03 / AUTOBUY-05 preserved).
- **`payAffiliate` is the canonical symbol** (`DegenerusAffiliate.sol:388`, fresh-rate `:493-505`) for the
  separate-bucket rationale; do NOT mis-rename it to `handleAffiliate` (an unrelated quest fn,
  `DegenerusQuests.sol:644`).
- **Invariant comment updates at `DegenerusGame.sol:18` ONLY** (`:5` is `@title` — the "second copy" does NOT
  exist) + the storage block at `DegenerusGameStorage.sol:345-354`. The master invariant FORM
  (`balance + steth >= claimablePool`) is unchanged; the comment names the keeper component.
- **D-CF-03** — NO `keeperFundingPool` aggregate; every `keeperFunding` mutation moves `claimablePool` in tandem.
- **(awareness)** `pullRedemptionReserve` (`DegenerusGame.sol:1981`) is a 4th `claimablePool`-tandem-debit site —
  keep the keeper bucket disjoint from it (it already is).

### Claude's Discretion
- Exact per-plan split within the 5 edit-order steps (D-344-06) — planner's call, but keep producer-before-consumer.
- The precise wording of the actor-consequence trace doc (D-344-01) — as long as it covers VAULT-can-receive +
  sDGNRS-GAME-allowance + Decision-B merge for both VAULT and sDGNRS, and escalates on any gap.
- Whether the executor records the re-grep results inline in a SUMMARY or a scratch attestation (D-344-05).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Authoring source-of-truth (read FIRST — the locked SPEC set)
- `.planning/phases/343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca/343-IMPL-EDIT-ORDER-MAP.md`
  — **THE primary authoring doc.** Final signatures (Section 1), storage shape (Section 2), the four corrections
  the IMPL author MUST apply (Section 3), the producer-before-consumer edit-order map (Section 4), and the
  red-team IMPL-discipline carry-forwards (Section 5).
- `.planning/phases/343-…-ca/343-GREP-ATTESTATION.md` — the grep-attested anchors + per-file Drift-Correction
  Table; the source the executor re-runs against the live tree (D-344-05).
- `.planning/phases/343-…-ca/343-CLEANUP-INVENTORY.md` — the 14-item CLEANUP-02 kill-set + the D-06 integrity
  gate + the D-05/item-#8/item-#14 dispositions.
- `.planning/phases/343-…-ca/343-SOLVENCY-PROOF.md` — the SOLVENCY-01/03 proof + the GO_SWEPT withdraw-guard LOCK
  (Section B) + the OPEN-E 4-protection carry-over; the design gate the 344 diff inherits (UNCHANGED accounting spine).
- `.planning/phases/343-…-ca/343-SOLVENCY-REDTEAM.md` — the D-07 red-team verdict (SURVIVES, 0 FINDING_CANDIDATE)
  + the IMPL-discipline carry-forwards (GO_SWEPT line-1 / checked-math; `funder` not `player`; `pullRedemptionReserve` awareness).
- `.planning/phases/343-…-ca/343-SPEC-INDEX.md` — the D-08 index + the §6 "344 IMPL hand-off" (the four
  carry-forwards) + the SPEC verdict (PASS).
- `.planning/phases/343-…-ca/343-GAS-INVENTORY.md` — GAS-01 advisory candidates (UNVALIDATED; for 345, not 344).

> Path note: the 343 dir is `.planning/phases/343-spec-design-lock-solvency-proof-dead-code-gas-inventories-ca/`.

### v54 design source-of-truth + requirements
- `.planning/PLAN-V54-KEEPER-FUNDING-GAME-LEDGER.md` — the DESIGN-LOCKED SPEC source (Decisions A2 + B). **NOTE
  §4 `keeperFunding[b.player]` is SUPERSEDED by D-01 (`b.funder`); §5 #1 single-`:18` invariant is correct.**
- `.planning/REQUIREMENTS.md` — the 344 REQ-IDs (LEDGER-01..05, AUTOBUY-01..05, DECUSTODY-01..04, GAMEOVER-01/02,
  CLEANUP-02, BATCH-02). **NOTE `AUTOBUY-02`'s `keeperFunding[b.player]` is corrected to `b.funder` by D-01;
  `AUTOBUY-05`'s "ONE staticcall per player" is refined by D-MR-01.**
- `.planning/ROADMAP.md` §"Phase 344" — goal + 5 success criteria. **NOTE SC3 literally says
  `keeperFunding[b.player]` — this is the D-01 trap; the correct debit is `keeperFunding[b.funder]`.**

### Contract anchors (re-grep ALL vs the live tree at author time — currently == `83a84431`)
- `contracts/DegenerusGame.sol` — `batchPurchase` `:1824`, `BatchBuy` struct `:1796`, `purchaseWith` selector
  call `:1838`, `keeperSnapshot` `:2645`, `_claimWinningsInternal` `:1462` (GO_SWEPT guard `:1463`),
  `adminStakeEthForStEth` `:2109/:2118`, `pullRedemptionReserve` `:1981`, master-invariant comment `:18`,
  bare `receive()` `:2915`.
- `contracts/storage/DegenerusGameStorage.sol` — `claimablePool` `:355`, invariant comment block `:345-354`.
- `contracts/AfKing.sol` — `_poolOf` slot 0 `:214`, `receive/deposit/depositFor/withdraw` `:298-341`, `subscribe`
  OPEN-E gate `:403-408` + `msg.value` credit `:412-414`, `poolOf` view `:492`, `src` resolution `:686`,
  funding-skip `:695` + VAULT/SDGNRS exemption `:696`, CEI debit `:719`, `BatchBuy` build `:726`, batched call
  `:768`, struct `:20`, `IGame` block `:40` (`batchPurchase` decl `:43`, `keeperSnapshot` decl `:56`), snapshot
  fallback `:809`, `Deposited` event decl `:175`.
- `contracts/modules/DegenerusGameJackpotModule.sol` — `distributeYieldSurplus` `:688/:693`.
- `contracts/modules/DegenerusGameGameOverModule.sol` — drain `:98/:163`, final sweep `:202/:215`.
- `contracts/StakedDegenerusStonk.sol` — redemption valuation `:612/:772/:861`, claimableEth read `:955-958`,
  `burnAtGameOver` AfKing leg `:539`, `receive()` `:439-444` (AF_KING relaxation `:442`).
- `contracts/DegenerusVault.sol` — `recoverAfKingPool()` `:516-517`.
- `contracts/DegenerusAffiliate.sol` — `payAffiliate` `:388`, fresh-rate `:493-505`.

### Prior-phase precedent (IMPL of a batched contract diff)
- `.planning/milestones/v50.0-phases/` (335 IMPL) + the v47 322 / v48 326 IMPL phases — the single-batched-diff
  IMPL shape: author all edits, ONE combined approval, atomic per-plan commits after approval, HOLD at boundary.

### Related memory (audit posture / process)
- [[open-e-operator-approval-trust-boundary]] — the 4-protection OPEN-E disposition (carries over verbatim;
  funding-source ETH now `keeperFunding[src]`, withdrawable by the source).
- [[v48-afking-pool-recovery]] — the ORIGINAL intent of the v48 recovery legs (the design-intent trace input for D-344-01).
- [[feedback_batch_contract_approval]] / [[feedback_no_contract_commits]] / [[feedback_contract_commit_guard_hook]]
  / [[feedback_manual_review_before_push]] / [[feedback_never_preapprove_contracts]] — the contract-boundary
  approval + commit discipline.
- [[feedback_design_intent_before_deletion]] — the actor-consequence trace floor (D-344-01).
- [[feedback_no_history_in_comments]] — invariant/comment edits describe current state only (D-344-02).
- [[feedback_skip_research_test_phases]] — plan directly (D-344-04). [[feedback_pause_at_contract_phase_boundaries]]
  — do not auto-advance past the contract gate even with auto_advance on.
- [[worktrees-reenabled-contracts-gate]] — contract plans skip worktrees (the `no_worktree_paths` gate); safety
  rests on the hook's Layer-0 merge guard.
- [[feedback_contractaddresses_policy]] — `ContractAddresses.sol` is freely modifiable (deploy-regenerated, hook-exempt).
- [[threat-model-reentrancy-mev-nonissues]] — audit weighting (solvency = spine; this diff touches it).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`claimableWinnings` / `claimablePool` pattern** (`DegenerusGame.sol`): the exact template for `keeperFunding`
  (per-player mapping + the reserved `uint128 claimablePool` aggregate it rides inside; master invariant
  `balance + steth.balanceOf(this) >= claimablePool` at `:18`).
- **`AfKing.withdraw` un-brickable CEI** (`:328-341`): the template for `withdrawKeeperFunding` (debit before
  send; re-entrant second call reverts on the debit). Carries the USER-LOCKED "cancel-then-withdraw always
  succeeds / never strands ETH" invariant — and is itself one of the symbols being DELETED (its logic moves to the Game).
- **`AfKing.depositFor`** (`:314`): the mirror for `depositKeeperFunding(address) payable` — also being deleted.
- **Per-player snapshot fallback** (`AfKing.sol:809`, `GAME.keeperSnapshot(snap)`): the pattern to reuse for the
  OPEN-E `keeperFunding[src]` extra read (D-MR-01).

### Established Patterns
- **Atomic non-brick** — `batchPurchase` reverts the whole batch on a poisoned slice; benign because `advanceGame()`
  is an independent permissionless entrypoint (the game never freezes; subscribers retry next cycle).
- **Fresh-vs-recycled affiliate labeling** (`DegenerusAffiliate.payAffiliate:493-505`): keeper ETH spent as
  `ethValue` (DirectEth/fresh) earns the fresh 20-25% rate — the reason `keeperFunding` stays a SEPARATE bucket.
- **GO_SWEPT-guard-line-1** (`_claimWinningsInternal:1463`): the precedent `withdrawKeeperFunding` mirrors.
- **Single-batched-diff IMPL**: author all edits across the ~5 plans → ONE combined diff → ONE approval → atomic
  per-plan commits. Executor subagents never commit; orchestrator owns commits past the approval gate.

### Integration Points
- The producer-before-consumer edit order (344's whole shape): storage `keeperFunding` + `BatchBuy.funder` →
  Game deposit/withdraw/`batchPurchase`/`keeperFundingOf`/`_claimWinningsInternal` merge + extended `keeperSnapshot`
  → interfaces (`IGame` non-payable `batchPurchase` + new decls; `IDegenerusGameModules.sol:237` is a comment-only
  refresh) → AfKing de-custody + `funder=src` wiring + non-value call → v48-recovery removal (D-06 gate).
- **Verified at discussion time:** `git diff --numstat 83a84431 HEAD -- contracts/` → EMPTY; working tree clean.
  The live tree IS the SPEC baseline, so the call-graph attestation greps apply directly — but re-grep at author
  time per D-344-05.
- The UNCHANGED accounting spine (`distributeYieldSurplus`, the gameOver drain, `handleFinalSweep`,
  `adminStakeEthForStEth`, the sDGNRS valuation) is NOT touched — it reserves the keeper total automatically via
  `claimablePool` (SOLVENCY-01, proven). Touching it would be a regression.

</code_context>

<specifics>
## Specific Ideas

- The audit-discipline maxim governs the whole diff: "no 'by construction' / 'single fn reaches all paths' claim
  survives un-checked" ([[feedback_verify_call_graph_against_source]]). The D-01 `funder` trap and the D-MR-01
  `keeperSnapshot` src gap are the concrete instances; the executor's first-action re-grep (D-344-05) is the
  enforcement.
- The single biggest copy-paste hazard is **D-01**: three upstream docs (ROADMAP SC3, REQUIREMENTS AUTOBUY-02,
  PLAN-V54 §4) literally say `keeperFunding[b.player]`. The correct debit is `keeperFunding[b.funder]`. This must
  survive into the diff verbatim-corrected.
- `feedback_security_over_gas` governs: the keeper bucket rides inside `claimablePool` precisely to inherit
  correct solvency wiring. The `claimableWinnings` packing candidate is explicitly OUT (345 gas-skeptic, D-04).

</specifics>

<deferred>
## Deferred Ideas

- **CLEANUP-03 codebase-wide unused-code sweep** → 345 (344's CLEANUP-02 is de-custody orphans only; D-344-03).
- **GAS-02/03 validation + application** (gas-scavenger candidates → gas-skeptic) → 345.
- **`claimableWinnings` `{uint128 normal, uint128 keeper}` packing evaluation** → 345 gas-skeptic (D-04).
- **Test-suite repair** (the ABI change breaks test compilation) → 346 TST (D-344-07).
- **Generalized "any operator-approved party may spend my `claimableWinnings`"** → out of v54 (PLAN-V54 §10 /
  REQUIREMENTS "Future Requirements").
- None of the above are scope creep into 344 — all are downstream milestone phases.

</deferred>

---

*Phase: 344-impl-the-one-batched-contract-diff-ledger-de-custody-cleanup*
*Context gathered: 2026-05-30*
