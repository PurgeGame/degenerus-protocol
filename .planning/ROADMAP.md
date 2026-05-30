# Roadmap: Degenerus Protocol — Audit Repository

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Milestones

- ✅ **v44.0 sStonk Per-Day Redemption Refactor** — Phases 304-308 (shipped 2026-05-20)
- ✅ **v45.0 VRF-Rotation Liveness Fix** — Phases 309-314 (shipped 2026-05-23, minimal close)
- ✅ **v46.0 Do-Work Crank + AfKing Subscription** — Phases 316-320 (shipped 2026-05-24)
- ✅ **v47.0 Rake-Free Presale + Lootbox-Boon Unification** — Phases 321-324 (shipped 2026-05-25)
- ✅ **v48.0 sDGNRS Salvage Swap + v47 Deferred Fixes + Keeper/Pool/Tombstone/Hero** — Phases 325-328 (shipped 2026-05-26)
- ✅ **v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep** — Phases 329-333 (shipped 2026-05-27)
- ✅ **v50.0 Whale-Pass O(1) Refactor + AfKing Pass-Gated Subs + MintModule Advance-Divergence + External RNG-Audit Protocol** — Phases 334-338 (shipped 2026-05-28, minimal close)
- ✅ **v51.0 claimBingo — Color-Completion Claim** — Phases 339-342 (closed 2026-05-28 at IMPL HEAD `c3e9d907`; 341 TST + 342 TERMINAL folded → v52 audit)
- 🔨 **v54.0 Game-Side Keeper-Funding Ledger + AfKing De-Custody + Dead-Code/Gas Sweep** — Phases 343-347 (started 2026-05-30)

---

## 🔨 v54.0 Game-Side Keeper-Funding Ledger + AfKing De-Custody + Dead-Code/Gas Sweep (Active — started 2026-05-30)

**Milestone:** v54.0 (started 2026-05-30)
**Defined:** 2026-05-30
**Audit baseline → subject:** v53 HEAD `83a84431` (the atomic `BatchBuy[]` batchPurchase; the ad-hoc keeper auto-buy mode + claimable-funding fix that landed after the v51.0 minimal close) → v54.0 closure HEAD (TBD at TERMINAL). Subject = the single batched USER-APPROVED `contracts/*.sol` diff for the ledger + de-custody + cleanup. **Supersedes** v53's cross-contract value-plumbing (`batchPurchase{value}` + `purchaseWith(ethValue)` funded from the AfKing `_poolOf`); v53's atomic `BatchBuy[]` shape is KEPT — only the funding **location** changes (AfKing custody → a game-side `keeperFunding` ledger riding inside `claimablePool`).
**Scope source:** `.planning/REQUIREMENTS.md` (34 v54.0 REQ-IDs across 9 categories: LEDGER 5 · AUTOBUY 5 · DECUSTODY 4 · GAMEOVER 2 · SOLVENCY 3 · CLEANUP 3 · GAS 3 · TST 6 · BATCH 3) + the milestone init (2026-05-30) + the design-locked SPEC source `.planning/PLAN-V54-KEEPER-FUNDING-GAME-LEDGER.md` (Decisions A2 + B locked). **No research** (a fully-specced internal contract refactor — the funding-model exploration is already resolved in the plan doc; no phase needs a research sub-phase).

> **Audit posture — FULL CLOSE WITH ITS OWN INTERNAL SWEEP (NOT deferred).** Unlike v50.0 + v51.0 (which deferred their internal 3-skill adversarial sweep + delta-audit + FINDINGS → the v52 consolidated audit), **v54.0 runs its own internal sweep at TERMINAL (347)**: the 3-skill genuine-PARALLEL adversarial pass (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) + the delta-audit + `audit/FINDINGS-v54.0.md` (chmod 444) + the atomic 5-doc closure flip all execute in-milestone. Rationale: this change touches the **solvency spine** (`claimablePool`) — the master invariant `balance + steth.balanceOf(this) >= claimablePool` is the load-bearing concern and must be adversarially probed, not deferred. (The separate v52 consolidated cross-model audit still folds the v54 surface into its cumulative sweep — that is an additional track, not a substitute for v54's own close.)

> **Cross-cutting rule (every requirement):** every cited `file:line` MUST be re-attested against the **v53 HEAD `83a84431`** before any patch (no "by construction" / "single fn reaches all paths" claim survives un-checked — the `DegenerusGame` mint/jackpot inline-duplication precedent; `feedback_verify_call_graph_against_source`). The cited anchors (the master invariant comment `DegenerusGameStorage.sol:344-352` + `DegenerusGame.sol:18`; `batchPurchase` `DegenerusGame.sol:1809`; `_claimWinningsInternal` `:1471`; `distributeYieldSurplus` `JackpotModule:691-707`; the gameOver drain `GameOverModule:98-99/:164`; the final sweep `:215`; `adminStakeEthForStEth` `:2113-2123`; the sDGNRS redemption valuation `StakedStonk:612/772/861`; the AfKing custody surface `AfKing.sol:214,298-341,400-409,682,695,719`; the v48 recovery `Vault:512` + `StakedStonk:533`) are confirmed at SPEC. **Security / solvency floor over gas** (`feedback_security_over_gas`): the keeper bucket rides inside `claimablePool` (no new reserved aggregate) → it inherits the already-correct solvency wiring; the prior-omission class ([[project_yield_surplus_omits_pending_pools]]) is structurally impossible. Pre-launch redeploy-fresh (storage break fine, no migration; no live AfKing pools — `feedback_frozen_contracts_no_future_proofing`).

> **Posture:** the contract changes (the ledger + the non-payable auto-buy + the de-custody + the CLEANUP-02 orphan removal) ship as **ONE batched USER-APPROVED `contracts/*.sol` diff** at IMPL (344) with a **HARD STOP at the contract-commit boundary** (applied + locally compiled/tested, NEVER committed without explicit user hand-review of the single batched diff — `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`; `ContractAddresses.sol` freely modifiable per `feedback_contractaddresses_policy`). The further behavior-identical gas wins (345 GAS+CLEANUP) ride a SECOND batched contract-boundary gate. The diff is authored producer-before-consumer (storage `keeperFunding` → Game deposit/withdraw/`batchPurchase`/`keeperFundingOf`/`_claimWinningsInternal` merge/extended `keeperSnapshot` → interfaces → AfKing de-custody + the v48 recovery removal). Tests + planning + docs AGENT-committable.

> **Why two contract gates (344 IMPL + 345 GAS+CLEANUP) mirror v49.0:** v49.0 (and v46.0 before it) carried a dedicated GAS phase because a load-bearing gas/peg change needed its own measurement + USER gate; v54.0 mirrors that — 344 lands the functional refactor (ledger + de-custody) under the first gate; 345 lands the FURTHER behavior-identical gas wins (gas-scavenger → gas-skeptic) + the packing-candidate evaluation + the broader dead-code sweep under the second gate. Both are HARD STOPs; both prove same-results in TST (346).

> **Phase numbering** continues from the previous milestone — v51.0 ended at Phase 342 (340 was the last phase with a directory; 341/342 were folded into the v52 audit track), so **v54.0 starts at Phase 343.** Not reset to 1. (Prior milestones' phase dirs are archived under `.planning/milestones/vXX.0-phases/`.)

> **Milestone shape** is the established v49.0 audit pattern (which had a dedicated GAS phase): **SPEC design-lock (+ the SOLVENCY-01/03 proofs + the CLEANUP-01 + GAS-01 inventories + call-graph attestation) → single batched IMPL contract diff (ledger + de-custody + CLEANUP-02) → GAS+CLEANUP (further behavior-identical gas wins + packing-candidate eval + broader dead-code sweep) → TST proof (keeper suite reconceived + SOLVENCY-02 invariant + NON-WIDENING regression) → TERMINAL FULL close (delta-audit + 3-skill genuine-PARALLEL adversarial sweep + `audit/FINDINGS-v54.0.md` + atomic 5-doc closure flip).** The contract-boundary HARD STOP lives at TWO phases (344 IMPL + 345 GAS+CLEANUP).

### Phases

- [x] **Phase 343: SPEC — Design-Lock + Solvency Proof + Dead-Code/Gas Inventories + Call-Graph Attestation** ✅ Complete (5/5; SPEC verdict PASS — design DESIGN-LOCKED, SOLVENCY-01/03 PROVEN, D-07 red-team SURVIVES 0 FINDING_CANDIDATE, GO_SWEPT locked, zero contracts/ mutation; index `519f0f16`) - Re-attest the PLAN-V54 design vs the v53 HEAD `83a84431`; lock the final `batchPurchase` / `purchaseWith` / extended `keeperSnapshot` signatures + the `keeperFunding` storage shape + the deposit/withdraw/claim-merge wiring; PROVE (not assume) SOLVENCY-01 (every "free ETH = totalBal − reserved" site already reserves the keeper total via `claimablePool`) + SOLVENCY-03 (sDGNRS redemption valuation unchanged + correct); produce the CLEANUP-01 dead-code inventory + the GAS-01 gas-opportunity inventory; confirm the OPEN-E 4-protection carry-over — paper-only, ZERO `contracts/*.sol`.
- [x] **Phase 344: IMPL — The ONE Batched Contract Diff (ledger + de-custody + CLEANUP-02 orphan removal)** ✅ Complete (executed + committed `d728263e`/`6d6aa424`/`20ca1f79`; `forge build` clean; consolidated `344-EXECUTION-SUMMARY.md`; not pushed) - Land the single reconciled `contracts/*.sol` diff in producer-before-consumer order: the per-player `keeperFunding` mapping (riding inside `claimablePool`, no new aggregate) + `depositKeeperFunding` / un-brickable CEI `withdrawKeeperFunding` / `keeperFundingOf` + the non-payable `batchPurchase` (per-slice `keeperFunding`+`claimablePool` debit then `purchaseWith(ethValue)`, fresh affiliate rate, atomic non-brick) + the extended `keeperSnapshot` + the post-gameOver `_claimWinningsInternal` keeperFunding merge + the AfKing de-custody (delete `_poolOf`/`receive`/`deposit`/`depositFor`/`withdraw`, `subscribe` forwards `msg.value`→`depositKeeperFunding`, OPEN-E gate unchanged) + the CLEANUP-02 orphan removal (the v48 stuck-pool recovery + every CLEANUP-01 kill-set item); applied + locally compiled (`forge build` clean), then HELD at the contract-commit boundary for explicit user hand-review.
- [⊘] **Phase 345: GAS+CLEANUP — Further Behavior-Identical Gas Wins + Packing-Candidate Eval + Broader Dead-Code Sweep** ⊘ DROPPED 2026-05-30 — superseded by v55 (the gas levers re-target the game-resident surface; folded into v55's GAS phase). - Apply the validated behavior-identical, no-cost gas wins from the GAS-01 inventory (gas-scavenger → gas-skeptic, under the security-over-gas floor) — each gas-only, proven same-results in TST, with invariant-trading / not-real wins REJECTED with reasoning; EVALUATE the `claimableWinnings` `{uint128 normal, uint128 keeper}` packing candidate (lands ISOLATED only if the slot/gas saving survives the ~15+ access-site blast radius on the central accounting variable, else documented NEGATIVE — default: keep the separate mapping); and run a broader unused-code audit across the keeper/funding blast radius + adjacent surface (anything found removed gas-skeptic-validated or documented NEGATIVE). Contract changes ride a SECOND batched USER-APPROVED diff held at the contract-commit boundary.
- [⊘] **Phase 346: TST — Deposit/Withdraw + Zero-Value Auto-Buy + Fresh-Rate + Solvency Invariant + Terminal-Claim Merge + Non-Widening Regression** ⊘ DROPPED 2026-05-30 — superseded by v55 (v55 TST proves the net game-resident surface; testing soon-replaced de-custody machinery is wasted). - Prove the bundle behaviorally correct empirically against the ledger model: deposit/withdraw un-brickable (game-side, drains-to-zero, never-strands, mid-game + post-cancel + post-gameOver); the non-payable `batchPurchase` debits each slice's `keeperFunding`+`claimablePool` with ZERO value transferred + lands ticket/lootbox + draws claimable for the remainder + reverts the WHOLE batch atomically on a poisoned slice (the v52 Finding A/B regressions) with the game stayed un-bricked via `advanceGame()`; keeper buys earn the FRESH 20-25% affiliate rate; the master invariant `balance + steth ≥ claimablePool` (now inclusive of the keeper total) holds across deposit → autobuy → withdraw → yield-surplus → gameOver-drain → claim → final-sweep (SOLVENCY-02) + the reservation sites never spend reserved keeper ETH; the post-gameOver `claimWinnings` pays `claimableWinnings + keeperFunding` in one call (no double-spend vs withdraw); and the reconceived keeper suite is NON-WIDENING vs the v53 baseline (every pre-existing red enumerated BY NAME, `REGRESSION-BASELINE-v54.md`).
- [⊘] **Phase 347: TERMINAL — Delta Audit + 3-Skill Genuine-PARALLEL Adversarial Sweep + FINDINGS-v54.0 + Closure Flip** ⊘ DROPPED 2026-05-30 — superseded by v55 (v55 TERMINAL audits the net surface; v54 ships NO `MILESTONE_V54_AT_HEAD` signal — the diff was never audited here, and `20ca1f79` is the v55 baseline). - Close the v54.0 audit subject (the single batched diff — the game-side `keeperFunding` ledger + the non-payable auto-buy + the AfKing de-custody + the gas/cleanup sweep, FROZEN at the IMPL+GAS HEAD) via a FULL close: a delta-audit (every v54 surface NON-WIDENING vs the v53 HEAD; the master solvency invariant + the OPEN-E 4-protection re-attested) + the 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) focused on the funding-ledger + de-custody surface + `audit/FINDINGS-v54.0.md` (chmod 444) + the atomic 5-doc closure flip with the `MILESTONE_V54_AT_HEAD_<sha>` signal — the internal sweep runs IN-MILESTONE (NOT deferred to v52).

---

## Phase Details

### Phase 343: SPEC — Design-Lock + Solvency Proof + Dead-Code/Gas Inventories + Call-Graph Attestation

**Goal**: The funding-ledger bundle's shapes are settled in writing so the IMPL phase authors a fully reconciled diff with zero "by construction" assumptions, and the load-bearing solvency concern is PROVEN before any code is written: the final `batchPurchase` / `purchaseWith` / extended `keeperSnapshot` signatures + the `keeperFunding` storage shape (riding inside `claimablePool`, no new aggregate) + the deposit/withdraw/claim-merge wiring are locked; SOLVENCY-01 (every "free ETH = totalBal − reserved" site already reserves the keeper total) + SOLVENCY-03 (the sDGNRS redemption valuation is unchanged + correct) are PROVEN on paper; the CLEANUP-01 dead-code inventory + the GAS-01 gas-opportunity inventory are produced with grep-attested kill-sets / behavior-identical tags; the OPEN-E 4-protection carry-over is confirmed; and every cited `file:line` is grep-verified against the v53 HEAD `83a84431` — paper-only, zero `contracts/*.sol`.
**Type**: SPEC
**Depends on**: Nothing (first v54.0 phase; consumes the v53 HEAD `83a84431` as the frozen audit baseline)
**Requirements**: BATCH-01, SOLVENCY-01, SOLVENCY-03, CLEANUP-01, GAS-01
**Success Criteria** (what must be TRUE):

  1. The full ledger design is settled in writing (BATCH-01) — the non-payable `batchPurchase(BatchBuy[])` signature (the `payable` + `spent == msg.value` guard removed, per-slice `keeperFunding[b.player] -= ev` & `claimablePool -= uint128(ev)` then `purchaseWith(b.player, …, ev)`), the `depositKeeperFunding(address) payable` + un-brickable CEI `withdrawKeeperFunding(uint256)` + `keeperFundingOf(address)` signatures, the `mapping(address => uint256) keeperFunding` storage shape on `DegenerusGameStorage.sol` with NO separate aggregate (the systemwide total rides inside `claimablePool`; the invariant comment updated to `claimablePool == Σ claimableWinnings + Σ keeperFunding`), the extended `keeperSnapshot` (one staticcall/player, GASOPT-03 preserved) returning the subject's `keeperFunding`, and the post-gameOver `_claimWinningsInternal` keeper-merge wiring (Decision B) are reconciled so no downstream file ships an intermediate broken state, and the producer-before-consumer edit-order map for the IMPL diff is fixed.
  2. SOLVENCY-01 is PROVEN, not assumed (SOLVENCY-01) — because the keeper total rides inside `claimablePool`, every "free ETH = totalBal − reserved" site is shown to reserve it with NO change: `distributeYieldSurplus` (`JackpotModule:691-707`, the prior-omission site [[project_yield_surplus_omits_pending_pools]], now structurally immune — it sums the same `claimablePool`), the gameOver drain (`GameOverModule:98-99/:164`), `adminStakeEthForStEth` (`DegenerusGame.sol:2113-2123`, keeper ETH never staked-away), and the final sweep (`GameOverModule:215`, the keeper reservation swept with `claimablePool`) — each attested to reserve `claimablePool` (inclusive of the keeper total) unchanged.
  3. SOLVENCY-03 is PROVEN (SOLVENCY-03) — the sDGNRS redemption valuation (`StakedStonk:612/772/861`, `ethBal + stethBal + claimableEth − pendingRedemptionEthValue`) is shown to be UNCHANGED and CORRECT: keeper ETH lives in the Game's balance (not sDGNRS's), invisible to sDGNRS's own-balance valuation — the same property as the external AfKing pool today — so no redemption-valuation edit is needed; and the OPEN-E disposition (`open-e-operator-approval-trust-boundary`) is confirmed to carry over verbatim (the `fundingSource` storage + the subscribe-time consent gate `AfKing.sol:400-409` + the `src` resolution `:682` are unchanged; funding-source ETH is now `keeperFunding[src]`, withdrawable by the source).
  4. The CLEANUP-01 dead-code inventory is produced (CLEANUP-01) — a grep-attested kill-set (vs the v53 HEAD) of everything the de-custody orphans: the AfKing ETH entrypoints / `_poolOf` (slot 0) / `receive`/`deposit`/`depositFor`/`withdraw` (`AfKing.sol:214,298-341`), the now-moot v48 stuck-pool recovery (`Vault.recoverAfKingPool()` `:512`, the `StakedStonk.burnAtGameOver()` AfKing-withdraw leg `:533`, the AfKing `receive()` AF_KING relaxation), the `IGame.batchPurchase` payable ABI, the local CEI debit `_poolOf[src] -= ethValue` (`AfKing.sol:719`), the `sum(_poolOf) <= address(this).balance` invariant doc, and any now-unused helpers / events / errors / constants / stale `_poolOf`-referencing comments — each item with its kill-set grep target.
  5. The GAS-01 gas-opportunity inventory is produced + every cited `file:line` is grep-attested vs `83a84431` (GAS-01 / BATCH-01) — a gas-opportunity inventory for the keeper/funding blast radius (beyond the ~9k/buy already saved by removing the per-batch value call), each tagged behavior-identical / same-results (and the `claimableWinnings` packing candidate flagged for the GAS phase's gas-skeptic evaluation per PLAN-V54 §2); and every cited anchor across the milestone scope (the master invariant comment, `batchPurchase`, `_claimWinningsInternal`, the yield-surplus / drain / final-sweep / stETH-stake reservation sites, the sDGNRS valuation, the AfKing custody + OPEN-E surface, the v48 recovery) is grep-verified against the v53 HEAD `83a84431` with any drift corrected in the SPEC (no "by construction" survives un-checked).

**Plans**: 5 plans (4 waves)
- [x] 343-01-PLAN.md — Call-graph attestation + Drift-Correction Table vs 83a84431 (re-pins every anchor; payAffiliate-EXISTS + single-interface-payable + single-copy-invariant corrections; 2 RESEARCH claims overturned) [wave 1] ✅ 6deda035
- [x] 343-02-PLAN.md — SOLVENCY-01 reservation-site walk + SOLVENCY-03 valuation proof + GO_SWEPT withdraw-guard lock + OPEN-E carry-over + D-07 focused red-team (autonomous:false — USER adjudicates the solvency verdict) [wave 2]
- [x] 343-03-PLAN.md — CLEANUP-01 grep-attested de-custody kill-set + GAS-01 /gas-scavenger advisory inventory + packing-candidate framing [wave 2] ✅ c35aadb2 + 428f7581
- [x] 343-04-PLAN.md — BATCH-01 design-lock + producer-before-consumer IMPL edit-order map (final signatures/storage/wiring; D-01 funder correction; D-MR-01 src carve-out; payAffiliate-canonical; single-copy :18 invariant; D-06 kill order) [wave 3] ✅ 725c23ee
- [x] 343-05-PLAN.md — 343-SPEC-INDEX.md indexing the doc set + requirement/success-criterion traceability + SPEC verdict (PASS — D-07 red-team SURVIVES, 0 FINDING_CANDIDATE) + 344 hand-off [wave 4] ✅ 519f0f16
**UI hint**: no

### Phase 344: IMPL — The ONE Batched Contract Diff (ledger + de-custody + CLEANUP-02 orphan removal)

**Goal**: The funding-ledger refactor lands as a single reconciled `contracts/*.sol` diff under the SPEC's settled shapes — the per-player `keeperFunding` mapping (riding inside `claimablePool`, no new aggregate) with `depositKeeperFunding` / the un-brickable CEI `withdrawKeeperFunding` / `keeperFundingOf` + the non-payable `batchPurchase` (per-slice `keeperFunding`+`claimablePool` debit then `purchaseWith(ethValue)` at the fresh affiliate rate, atomic non-brick preserved) + the extended `keeperSnapshot` + the post-gameOver `_claimWinningsInternal` keeper merge (Decision B) + the AfKing de-custody (delete `_poolOf`/`receive`/`deposit`/`depositFor`/`withdraw`; `subscribe` stays payable and forwards `msg.value`→`game.depositKeeperFunding`; the OPEN-E consent gate + `src` resolution unchanged; the local CEI `_poolOf` debit dropped; the batch call becomes the non-value `GAME.batchPurchase(buys)`) + the CLEANUP-02 orphan removal (the now-moot v48 stuck-pool recovery + every CLEANUP-01 kill-set item, grep-confirmed empty) — authored producer-before-consumer, applied to `contracts/` and locally compiling (`forge build` clean), then HELD at the contract-commit boundary for explicit user hand-review.
**Type**: IMPL (CONTRACT BOUNDARY — the ONE batched USER-APPROVED `contracts/*.sol` diff; `autonomous: false` at the commit gate; never auto-commit contracts)
**Depends on**: Phase 343 (the SPEC must settle the signatures/storage/wiring + PROVE SOLVENCY-01/03 + produce the CLEANUP-01 kill-set + confirm the OPEN-E carry-over + grep-attest the edit-order map first)
**Requirements**: LEDGER-01, LEDGER-02, LEDGER-03, LEDGER-04, LEDGER-05, AUTOBUY-01, AUTOBUY-02, AUTOBUY-03, AUTOBUY-04, AUTOBUY-05, DECUSTODY-01, DECUSTODY-02, DECUSTODY-03, DECUSTODY-04, GAMEOVER-01, GAMEOVER-02, CLEANUP-02, BATCH-02
**Success Criteria** (what must be TRUE):

  1. The game-side `keeperFunding` ledger exists, segregated, with its total riding inside `claimablePool` (LEDGER-01 / LEDGER-02 / LEDGER-05) — a new per-player `mapping(address => uint256) keeperFunding` on `DegenerusGameStorage.sol` (no human-purchase path, no `_settleClaimableShortfall`, no claim path reads it except the GAMEOVER-01 merge; only the AF_KING-gated `batchPurchase` spends it) has NO separate aggregate — every mutation moves `claimablePool` in tandem so `claimablePool == Σ claimableWinnings[*] + Σ keeperFunding[*]`, the invariant comment (`DegenerusGameStorage.sol:344-352` + `DegenerusGame.sol:18`) names the keeper component, and `keeperFundingOf(address) external view returns (uint256)` exposes the per-player balance.
  2. The deposit + un-brickable withdraw entrypoints exist (LEDGER-03 / LEDGER-04) — `depositKeeperFunding(address player) external payable` credits `keeperFunding[player] += msg.value` AND `claimablePool += msg.value` (reverts on `player == address(0)`, zero-value no-op, emits `KeeperFunded`; the Game's bare `receive()` is NOT used), and `withdrawKeeperFunding(uint256 amount) external` is un-brickable (strict CEI — debit `keeperFunding[msg.sender]` + `claimablePool` BEFORE the `.call`, so a re-entrant second call reverts on the debit), available ALWAYS (mid-game / post-cancel / post-gameOver), reverts on `amount > balance`, zero-value no-op, emits `KeeperWithdrew`, inheriting the USER-locked "cancel-then-withdraw always succeeds / never strands ETH" invariant.
  3. The non-payable batched auto-buy lands with the fresh rate + atomic non-brick (AUTOBUY-01..05) — `batchPurchase(BatchBuy[] calldata buys)` is NON-payable (the `payable` modifier + the `spent == msg.value` guard removed), stays AF_KING-gated / `!gameOver`-pre-checked / `len != 0`, and per slice debits `keeperFunding[b.player] -= b.ethValue` AND `claimablePool -= b.ethValue` (revert if `keeperFunding[b.player] < ethValue`) then delegatecalls `purchaseWith(b.player, …, b.ethValue)` (`_purchaseForWith`/`purchaseWith`/`_settleClaimableShortfall` UNCHANGED) so the keeper ETH becomes prize-pool/vault-share ETH earning the FRESH affiliate rate (20-25%, `isFreshEth=true`, NOT recycled 5% — no affiliate-bonus rework); a reverting slice rolls back the WHOLE batch (no per-slice try/catch — benign because `advanceGame()` is independent permissionless); and AfKing's funding-skip gate reads `keeperFunding[src]` via the extended `keeperSnapshot` (one staticcall/player) with byte-identical two-tier branching, the local CEI `_poolOf[src] -= ethValue` (`AfKing.sol:719`) removed, and `GAME.batchPurchase{value: totalValue}(buys)` → the non-value `GAME.batchPurchase(buys)`.
  4. AfKing is de-custodied + the v48 recovery is removed + the OPEN-E gate carries over (DECUSTODY-01..04 / CLEANUP-02) — AfKing holds NO ETH (`_poolOf` slot 0 + `receive()`/`deposit()`/`depositFor()`/`withdraw()` `AfKing.sol:214,298-341` deleted, the `sum(_poolOf) <= address(this).balance` invariant retired, `poolOf(player)` delegates to `game.keeperFundingOf(player)` or is removed); `subscribe` stays `payable` and FORWARDS `msg.value` → `game.depositKeeperFunding{value}(subscriber)` (Decision A2; standalone top-ups go direct); the OPEN-E `fundingSource` storage + the subscribe-time operator-approval consent gate (`:400-409`) + the `src` resolution (`:682`) are UNCHANGED so the 4-protection disposition carries over verbatim (funding-source ETH is now withdrawable `keeperFunding[src]`); and the now-moot v48 stuck-pool recovery (`Vault.recoverAfKingPool()` `:512`, the `StakedStonk.burnAtGameOver()` AfKing-withdraw leg `:533`, the AfKing `receive()` AF_KING relaxation) plus every other CLEANUP-01 kill-set item are removed with the kill-set grep-confirmed empty (no orphaned references).
  5. The unified terminal claim lands + `forge build` is clean + the diff is HELD at the contract boundary (GAMEOVER-01 / GAMEOVER-02 / BATCH-02) — post-gameOver `claimWinnings` (`_claimWinningsInternal`, `DegenerusGame.sol:1471`) ALSO pays the caller's `keeperFunding` (lazy per-player merge, no unbounded loop): payout = `claimableWinnings[caller] + keeperFunding[caller]`, zeroing both and debiting `claimablePool` for the sum (`withdrawKeeperFunding` remains available too; both zero the bucket → no double-spend), and the final sweep (`GameOverModule:215`, 30 days post-end) sweeps the keeper reservation with `claimablePool` (same forfeiture lifecycle, both paths open until that sweep); the whole diff is authored producer-before-consumer per the SPEC edit-order map, applied to `contracts/` and locally compiling (`forge build` clean; `ContractAddresses.sol` freely modifiable), but NOT committed without explicit user hand-review of the single batched diff.

**Plans**: 5 plans (5 waves)
- [ ] 344-01-PLAN.md — Storage producers: `keeperFunding` mapping (no aggregate, D-CF-03) + `funder` field on both `BatchBuy` structs + invariant comment; executor's first-action re-grep (D-344-05) [wave 1]
- [ ] 344-02-PLAN.md — Game fns: `depositKeeperFunding` / un-brickable `withdrawKeeperFunding` (GO_SWEPT line-1) / `keeperFundingOf` + non-payable `batchPurchase` (D-01 `b.funder` debit) + Decision-B claim-merge + extended `keeperSnapshot` + `:18` invariant [wave 2]
- [ ] 344-03-PLAN.md — Interfaces: AfKing `IGame` block — flip `batchPurchase` non-payable + extend `keeperSnapshot` + add the 3 ledger decls; `IDegenerusGameModules.sol:237` comment refresh [wave 3]
- [ ] 344-04-PLAN.md — AfKing de-custody: forward `subscribe` msg.value → `depositKeeperFunding` (A2) + `funder: src` (D-01) + funding-skip reads `keeperFunding[src]` (D-MR-01) + non-value call + PURE-DELETE custody surface + remove `Deposited` event [wave 4]
- [ ] 344-05-PLAN.md — v48-recovery removal (D-06 kill order) with the [BLOCKING] D-344-01 actor-consequence trace + sDGNRS `receive()` GAME-only narrow + CLEANUP-02 grep-empty + `forge build` gate + HOLD (autonomous:false) [wave 5]
**UI hint**: no

### Phase 345: GAS+CLEANUP — Further Behavior-Identical Gas Wins + Packing-Candidate Eval + Broader Dead-Code Sweep

**Goal**: Beyond the ~9k/buy already saved by removing the per-batch value call, the keeper/funding blast radius gets a further gas pass + a broader dead-code sweep, both under the security-over-gas floor: the validated behavior-identical, no-cost gas wins from the GAS-01 inventory are applied (gas-scavenger surfaces, gas-skeptic validates — each gas-only, proven same-results in TST; invariant-trading or not-real wins REJECTED with reasoning, not re-litigated); the `claimableWinnings` `{uint128 normal, uint128 keeper}` packing candidate is EVALUATED by gas-skeptic against the security floor (landing ISOLATED only if the slot/gas saving survives the ~15+ access-site blast radius on the central accounting variable, else documented NEGATIVE — default expectation: keep the separate mapping); and a broader unused-code audit across the keeper/funding blast radius + adjacent surface removes anything found (gas-skeptic-validated) or documents it NEGATIVE with reasoning. Any contract change rides a SECOND batched USER-APPROVED diff held at the contract-commit boundary.
**Type**: GAS+CLEANUP (CONTRACT BOUNDARY — the SECOND batched USER-APPROVED `contracts/*.sol` diff; `autonomous: false` at the commit gate)
**Depends on**: Phase 344 (the gas pass + broader sweep operate on the post-de-custody surface — the dead code the de-custody created + the keeper/funding hot path the ledger established must exist before they can be optimized/swept; the packing candidate is evaluated against the landed `keeperFunding` mapping)
**Requirements**: GAS-02, GAS-03, CLEANUP-03
**Success Criteria** (what must be TRUE):

  1. The behavior-identical gas wins are applied or rejected with reasoning (GAS-02) — every validated no-cost, same-results gas win from the GAS-01 inventory (gas-scavenger → gas-skeptic, under the security-over-gas floor) is applied as a gas-only change proven same-results in TST (346); each win that trades an invariant or isn't real is explicitly REJECTED with reasoning (the v49 gas-skeptic precedent — e.g. a `Sub` memory-snapshot opt that breaks a core invariant's access pattern stays rejected and is not re-litigated).
  2. The `claimableWinnings` packing candidate is decided by gas-skeptic against the security floor (GAS-03) — the `{uint128 normal, uint128 keeper}` packing alternative (instead of the separate `keeperFunding` mapping) is EVALUATED: it lands as an ISOLATED change only if the slot/gas saving survives the blast-radius cost on the central accounting variable (~15+ access sites — every `claimableWinnings` credit/debit + `_processMintPayment` / `_settleClaimableShortfall` / `claimWinnings` / `claimableWinningsOf` / StakedStonk reads); otherwise it is documented NEGATIVE (PLAN-V54 §2 deferral) with the default expectation (keep the separate mapping — hot-path-neutral, large spine refactor) recorded.
  3. The broader dead-code sweep is complete (CLEANUP-03) — a gas-scavenger dead-code pass across the keeper/funding blast radius + adjacent surface (beyond the CLEANUP-02 de-custody orphans already removed in 344) finds and removes anything unused (gas-skeptic-validated, no behavior change) or documents it NEGATIVE with reasoning; nothing dead is left behind and nothing live is removed.
  4. The second contract diff is held at the boundary (GAS-02 / GAS-03 / CLEANUP-03) — any `contracts/*.sol` change from this phase (the applied gas wins + the packing candidate if it lands + the broader-sweep removals) rides a SECOND batched USER-APPROVED diff, applied + locally compiling (`forge build` clean), HELD at the contract-commit boundary for explicit user hand-review (never auto-committed); if the phase produces no net contract change (all wins rejected / NEGATIVE), that is recorded as the outcome and no diff is gated.

**Plans**: TBD
**UI hint**: no

### Phase 346: TST — Deposit/Withdraw + Zero-Value Auto-Buy + Fresh-Rate + Solvency Invariant + Terminal-Claim Merge + Non-Widening Regression

**Goal**: The funding-ledger bundle is proven behaviorally correct empirically against the ledger model (not v53's value-plumbing, so no throwaway v53 test work): deposit/withdraw is un-brickable game-side (re-entrant double-withdraw reverts on the debit, drains-to-zero, never-strands, mid-game + post-cancel + post-gameOver); the non-payable `batchPurchase` debits each slice's `keeperFunding`+`claimablePool` by `ethValue` with ZERO value transferred + lands the buy (ticket or lootbox) + draws claimable for the Combined/Claimable remainder (the v52 Finding A/B regressions) + reverts the WHOLE batch atomically on a poisoned slice with the game stayed un-bricked via `advanceGame()`; keeper buys earn the FRESH 20-25% affiliate rate; the master invariant `balance + steth.balanceOf(this) >= claimablePool` (now inclusive of the keeper total) holds across the FULL lifecycle and the reservation sites never spend reserved keeper ETH (SOLVENCY-02); the post-gameOver `claimWinnings` pays `claimableWinnings + keeperFunding` in one call (no double-spend vs `withdrawKeeperFunding`); and the reconceived keeper suite is NON-WIDENING vs the v53 baseline — restoring a clean v54.0 regression baseline.
**Type**: TST
**Depends on**: Phase 345 (tests exercise the FINAL applied surface — the live ledger + de-custody from 344 plus whatever gas wins / packing decision / broader-sweep removals 345 landed — not SPEC placeholders or an intermediate pre-gas state)
**Requirements**: TST-01, TST-02, TST-03, TST-04, TST-05, TST-06, SOLVENCY-02
**Success Criteria** (what must be TRUE):

  1. Deposit/withdraw is proven un-brickable + never-strands (TST-01) — `depositKeeperFunding` credits `keeperFunding` + `claimablePool`; `withdrawKeeperFunding` is un-brickable (a re-entrant double-withdraw reverts on the debit, the pool fully restored), drains to zero, never strands ETH (fuzz any pool / partial-withdraw), and works mid-game + post-cancel + post-gameOver.
  2. The zero-value auto-buy is proven + atomic non-brick holds (TST-02) — `batchPurchase(buys)` (no value) debits each slice's `keeperFunding` + `claimablePool` by `ethValue`, lands the buy (ticket or lootbox per `isTicket`), draws claimable for the Combined/Claimable remainder (the v52 Finding A/B regressions — ticket-mode buys tickets, claimable funding is actually drawn), and reverts the WHOLE batch atomically on a poisoned slice (no partial landing); the game stays un-bricked via `advanceGame()`.
  3. The fresh affiliate rate + the terminal-claim merge are proven (TST-03 / TST-05) — a keeper buy credits the affiliate at the FRESH rate (20-25%, `isFreshEth=true`), not the recycled 5% (proving keeper-funded ETH is labeled fresh); and post-gameOver `claimWinnings` pays `claimableWinnings + keeperFunding` in one call (both zeroed, `claimablePool` debited by the sum), the final sweep zeroes the keeper reservation, and there is no double-spend vs `withdrawKeeperFunding`.
  4. The master solvency invariant holds across the full lifecycle (TST-04 / SOLVENCY-02) — `balance + steth.balanceOf(this) >= claimablePool` (with `claimablePool` now including the keeper total) holds across deposit → autobuy → withdraw → `distributeYieldSurplus` → gameOver-drain → claim → final-sweep, and the reservation sites never spend reserved keeper ETH (a yield-surplus run with outstanding `keeperFunding` distributes 0 of it; an `adminStakeEthForStEth` call cannot stake below the keeper reserve; the gameOver-drain leaves the keeper reservation intact); no test asserts strict `claimablePool == Σ claimableWinnings` across a keeper op.
  5. The NON-WIDENING regression is proven (TST-06) — the reconceived keeper suite (`KeeperNonBrick`, `KeeperBatchAffiliateDeltaAudit`, the 3 `test/gas/*`) compiles + passes against the ledger model with net-zero new regression vs the v53 baseline (every pre-existing red enumerated BY NAME), absorbing any test renames / oracle migrations from the bundle (incl. whatever 345 landed), with no test asserting strict `claimablePool == Σ claimableWinnings` across a keeper op, and a clean v54.0 regression baseline recorded → `REGRESSION-BASELINE-v54.md`.

**Plans**: TBD
**UI hint**: no

### Phase 347: TERMINAL — Delta Audit + 3-Skill Genuine-PARALLEL Adversarial Sweep + FINDINGS-v54.0 + Closure Flip

**Goal**: The v54.0 audit subject (the single batched diff — the game-side `keeperFunding` ledger + the non-payable auto-buy + the AfKing de-custody + the gas/cleanup sweep, FROZEN at the IMPL+GAS HEAD) is closed via a FULL close that runs its own internal sweep IN-MILESTONE (NOT deferred to v52, unlike v50.0/v51.0): a delta-audit confirms every v54 surface is NON-WIDENING vs the v53 HEAD `83a84431` with the master solvency invariant + the OPEN-E 4-protection re-attested; the 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT) probes the funding-ledger + de-custody surface; `audit/FINDINGS-v54.0.md` (chmod 444) is authored; and the atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) is applied with the `MILESTONE_V54_AT_HEAD_<sha>` closure signal.
**Type**: TERMINAL (FULL close — delta-audit + internal 3-skill adversarial sweep + FINDINGS + closure flip; NOT deferred)
**Depends on**: Phase 346 (the subject must be implemented + gas-swept + test-proven — incl. SOLVENCY-02 + the NON-WIDENING regression — before the requirements are re-attested at closure and the adversarial sweep runs on the proven surface)
**Requirements**: BATCH-03
**Success Criteria** (what must be TRUE):

  1. The delta-audit + the internal 3-skill adversarial sweep are run IN-MILESTONE (BATCH-03) — the delta-audit confirms every v54 surface (the `keeperFunding` ledger + the non-payable `batchPurchase` + the AfKing de-custody + the v48-recovery removal + the gas/cleanup edits) is NON-WIDENING vs the v53 HEAD `83a84431` with zero orphan hunks, the master invariant `balance + steth.balanceOf(this) >= claimablePool` (inclusive of the keeper total) + the OPEN-E 4-protection re-attested intact; and the 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` run as concurrent background Task spawns from the orchestrator; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) probes the funding-ledger + de-custody surface (the solvency reservation, the un-brickable withdraw, the deposit-then-spend / fresh-rate-labeling economics, the atomic non-brick, the OPEN-E trust boundary) with each charged probe dispositioned NEGATIVE-VERIFIED / SAFE_BY_DESIGN / FINDING_CANDIDATE.
  2. The findings deliverable is authored + all 34 v54.0 requirements re-attested (BATCH-03) — `audit/FINDINGS-v54.0.md` (the full multi-section report, chmod 444) is authored capturing the delta-audit + the adversarial disposition + any findings, and all 34 v54.0 requirements (LEDGER-01..05 · AUTOBUY-01..05 · DECUSTODY-01..04 · GAMEOVER-01/02 · SOLVENCY-01/02/03 · CLEANUP-01/02/03 · GAS-01/02/03 · TST-01..06 · BATCH-01/02/03) are confirmed satisfied against the frozen v54.0 closure HEAD.
  3. The closure flip is applied (BATCH-03) — the `MILESTONE_V54_AT_HEAD_<sha>` closure signal is emitted and propagated verbatim, and the atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) is applied; the closure plan is a single blocking USER closure-verdict + signal-format approval gate (`autonomous: false`) — the auto-advance is HELD at the closure boundary per `feedback_pause_at_contract_phase_boundaries`. (The separate v52 consolidated cross-model audit still folds the v54 surface into its cumulative sweep — that is an additional track, recorded in the v52 charge, NOT a substitute for this in-milestone close.)

**Plans**: TBD
**UI hint**: no

---

## Progress

**Execution Order:** Phases execute in numeric order: 343 → 344 → 345 → 346 → 347

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 343. SPEC — Design-Lock + Solvency Proof + Dead-Code/Gas Inventories + Attestation | v54.0 | 5/5 | Complete    | 2026-05-30 |
| 344. IMPL — The ONE Batched Contract Diff (ledger + de-custody + CLEANUP-02) | v54.0 | 0/5 | Not started | - |
| 345. GAS+CLEANUP — Further Behavior-Identical Gas Wins + Packing Eval + Broader Sweep | v54.0 | 0/? | Not started | - |
| 346. TST — Deposit/Withdraw + Zero-Value Auto-Buy + Fresh-Rate + Solvency + Terminal-Merge + Non-Widening | v54.0 | 0/? | Not started | - |
| 347. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + FINDINGS + Closure | v54.0 | 0/? | Not started | - |

> **🔒 v54.0 CONTRACT-BOUNDARY HARD STOPS (TWO gates).** Phase 344 IMPL is the FIRST contract phase — the batched ledger + de-custody + CLEANUP-02 diff is applied to `contracts/` and locally compiled (`forge build` clean) but HELD at the contract-commit boundary, NEVER committed without explicit user hand-review (`feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`). Phase 345 GAS+CLEANUP is the SECOND contract phase — any further gas/packing/dead-code contract change rides its own batched USER-APPROVED diff at the same boundary. `ContractAddresses.sol` freely modifiable per `feedback_contractaddresses_policy`; tests + planning + docs AGENT-committable.

> **🔓 v54.0 AUDIT POSTURE — FULL CLOSE (internal sweep NOT deferred).** Unlike v50.0 + v51.0 (whose internal sweeps were deferred → the v52 consolidated audit), **v54.0 runs its own internal 3-skill genuine-PARALLEL adversarial sweep + delta-audit + `audit/FINDINGS-v54.0.md` at TERMINAL (347)** — because the change touches the solvency spine (`claimablePool`) and the master invariant must be adversarially probed in-milestone. The separate v52 consolidated cross-model audit folds the v54 surface into its cumulative sweep as an additional track (recorded in the v52 charge), not a substitute.

---

## Coverage (v54.0)

**34/34 v54.0 requirements mapped to exactly one phase — 0 orphaned, 0 duplicated.**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 343 SPEC | BATCH-01, SOLVENCY-01, SOLVENCY-03, CLEANUP-01, GAS-01 | 5 |
| 344 IMPL | LEDGER-01, LEDGER-02, LEDGER-03, LEDGER-04, LEDGER-05, AUTOBUY-01, AUTOBUY-02, AUTOBUY-03, AUTOBUY-04, AUTOBUY-05, DECUSTODY-01, DECUSTODY-02, DECUSTODY-03, DECUSTODY-04, GAMEOVER-01, GAMEOVER-02, CLEANUP-02, BATCH-02 | 18 |
| 345 GAS+CLEANUP | GAS-02, GAS-03, CLEANUP-03 | 3 |
| 346 TST | TST-01, TST-02, TST-03, TST-04, TST-05, TST-06, SOLVENCY-02 | 7 |
| 347 TERMINAL | BATCH-03 | 1 |
| **Total** | | **34** |

**Per-category split (verification):**

| Category | Total | SPEC (343) | IMPL (344) | GAS+CLEANUP (345) | TST (346) | TERMINAL (347) |
|----------|-------|------------|------------|-------------------|-----------|----------------|
| LEDGER | 5 | — | 5 (01-05) | — | — | — |
| AUTOBUY | 5 | — | 5 (01-05) | — | — | — |
| DECUSTODY | 4 | — | 4 (01-04) | — | — | — |
| GAMEOVER | 2 | — | 2 (01,02) | — | — | — |
| SOLVENCY | 3 | 2 (01,03) | — | — | 1 (02) | — |
| CLEANUP | 3 | 1 (01) | 1 (02) | 1 (03) | — | — |
| GAS | 3 | 1 (01) | — | 2 (02,03) | — | — |
| TST | 6 | — | — | — | 6 (01-06) | — |
| BATCH | 3 | 1 (01) | 1 (02) | — | — | 1 (03) |
| **Total** | **34** | **5** | **18** | **3** | **7** | **1** |

**Center-of-gravity rationale (where a requirement spans design + impl + test):**

- **SOLVENCY-01 / SOLVENCY-03** (the load-bearing solvency PROOFS — every reservation site already covers the keeper total via `claimablePool`; the sDGNRS valuation unchanged + correct) → SPEC (343), where they are PROVEN on paper as the design-gating attestations BEFORE the ledger is authored. **SOLVENCY-02** (the empirical master-invariant proof across the full lifecycle) → TST (346) — it is the test that re-proves the SPEC paper-proofs empirically; it is NOT re-counted at SPEC.
- **CLEANUP-01** (the SPEC dead-code inventory + grep-attested kill-set) → SPEC (343); **CLEANUP-02** (the kill-set removed in the batched diff, grep-confirmed empty) → IMPL (344); **CLEANUP-03** (the broader gas-scavenger dead-code sweep beyond the de-custody orphans) → GAS+CLEANUP (345). Three distinct deliverables, three distinct phases — no double-counting.
- **GAS-01** (the SPEC gas-opportunity inventory) → SPEC (343); **GAS-02** (the validated wins applied) + **GAS-03** (the packing-candidate evaluation) → GAS+CLEANUP (345). The inventory is produced at SPEC; the wins land + the candidate is decided at the GAS phase.
- **LEDGER-01..05 + AUTOBUY-01..05 + DECUSTODY-01..04 + GAMEOVER-01/02** (the build) → IMPL (344) as the single batched diff. The design-lock concerns those decisions feed are SPEC concerns folded into BATCH-01 — they are not double-counted at SPEC; only the requirement's HOME (where it must be BUILT) is counted.
- **TST-01..06** (the proofs) → TST (346). They do not "uncover" the IMPL reqs — they re-prove them empirically against the ledger model (deposit/withdraw, zero-value auto-buy, fresh rate, terminal merge, NON-WIDENING regression).
- **BATCH-01** (the single SPEC design-lock) absorbs the signature/storage/wiring reconciliation + the SOLVENCY-01/03 proofs + the CLEANUP-01/GAS-01 inventories + the OPEN-E confirmation + the grep-attestation; it does not duplicate the LEDGER/AUTOBUY/DECUSTODY/GAMEOVER/SOLVENCY/CLEANUP/GAS requirements those decisions feed.
- **BATCH-02** (the single batched contract diff + the contract-commit HARD STOP) → IMPL (344); the diff is authored producer-before-consumer per the SPEC edit-order map. **BATCH-03** (the TERMINAL FULL close) re-attests all 34 v54.0 requirements + runs the in-milestone delta-audit + 3-skill adversarial sweep + `audit/FINDINGS-v54.0.md` + the atomic 5-doc closure flip with the `MILESTONE_V54_AT_HEAD_<sha>` signal.

✓ All 34 v54.0 requirements mapped
✓ No orphaned requirements
✓ No duplicated requirements

**Note on §13e-style "uncovered" warnings:** as in the v44–v51 roadmaps, milestone-wide "uncovered" warnings are EXPECTED false alarms — each phase owns only its slice; BATCH-03 re-attests the full 34-requirement set at the TERMINAL full close (347). The TST / TERMINAL phases do not "uncover" the IMPL reqs — they re-prove and re-attest them.

**Note on the internal sweep (NOT deferred):** unlike v50.0 + v51.0, v54.0 runs its own internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v54.0.md` at TERMINAL (347, BATCH-03) — the solvency-spine touch makes deferral unacceptable. v54's regression bar is TST-06 (NON-WIDENING vs the v53 baseline); its security proof is the SOLVENCY-01/03 SPEC proofs (343) + SOLVENCY-02 + TST-01..05 (346) + the TERMINAL adversarial sweep (347). The v52 consolidated cross-model audit still folds the v54 surface into its cumulative sweep as a separate, additional track.

---

<details>
<summary>✅ v51.0 claimBingo — Color-Completion Claim (Phases 339-342) — CLOSED 2026-05-28 (minimal close at IMPL HEAD `c3e9d907`; 341 TST + 342 TERMINAL folded → v52)</summary>

**Closure:** MINIMAL CLOSE (USER decision 2026-05-28 at milestone start) — v51.0 closes at the 340 IMPL HEAD `c3e9d907` (USER-APPROVED). Phases 339 SPEC + 340 IMPL Complete; **Phase 341 TST + Phase 342 TERMINAL FOLDED → the v52 consolidated audit** (USER 2026-05-28: "move this along and fold tests and shit into v52"). The internal 3-skill genuine-PARALLEL adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` (and the full TST-01..06 suite) consolidate into the v52 audit (cumulative v50 + v51 surface). Audit baseline → subject: v50.0 closure HEAD `812abeee2719c32d6973771ad2a66187fae75b80` (minimal-close commit, no formal signal) → v51.0 closure HEAD `c3e9d907`. Shape: SPEC → IMPL → (TST → TERMINAL folded → v52). The contract-boundary HARD STOP lived at the single IMPL phase (340). **Note:** v53 — the AfKing keeper auto-buy mode/claimable fix `83a84431` — landed ad-hoc afterward and is the v54.0 baseline (superseded by v54.0).

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 339. SPEC — Design-Lock + Freeze Proof + Tier-Precedence + Attestation | 4/4 | Complete | 2026-05-28 |
| 340. IMPL — The ONE Batched Contract Diff (BINGO + REBAL + JACK) | 4/4 | Complete | 2026-05-29 |
| 341. TST — Per-Tier + Precedence + Revert/Dedup + Empty-Pool + Jackpot + Non-Widening | — | ⤴ Folded → v52 | 2026-05-28 |
| 342. TERMINAL — Minimal Close: Re-Attest + Closure Flip | — | ⤴ Folded → v52 | 2026-05-28 |

**Coverage:** 18/18 requirements mapped (339: 2 · 340: 9 · 341: 6 · 342: 1); 0 orphaned, 0 duplicated. Per-category: BINGO 6 · REBAL 1 · JACK 2 · TST 6 · BATCH 3. Phase numbering continued 338 → 339. BINGO-06 freeze-safety PROVEN at SPEC (the read-only `traitBurnTicket` consumer); tier-precedence (quadrant-first-before-symbol-first) locked at SPEC. **v52 test note:** the locked revert table referenced `level > currentLevel`, REMOVED in 340 IMPL (no level guard; signature `uint24 level`) → the v52 suite drops that case + adds no-level-guard / uint24 / claimable-near-future-level coverage. Full detail in `.planning/MILESTONES.md`. v54 baseline = v53 HEAD `83a84431`.

</details>

<details>
<summary>✅ v50.0 Whale-Pass O(1) Refactor + AfKing Pass-Gated Subs + MintModule Advance-Divergence + External RNG-Audit Protocol (Phases 334-338) — CLOSED 2026-05-28 (minimal close)</summary>

**Closure:** MINIMAL CLOSE (USER-approved 2026-05-28) — closure HEAD `812abeee2719c32d6973771ad2a66187fae75b80`; NO formal `MILESTONE_V50_AT_HEAD` signal emitted. Phases 334 SPEC + 335 IMPL + 336 TST + 337 AUDIT-PROTOCOL all Complete (21/25 reqs). **Phase 338's internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v50.0.md` are DEFERRED → the v52 consolidated audit** (SWEEP-01/02/03 + the findings/flip portion of BATCH-03), which MUST cover the cumulative v50 + v51 contract surface. Audit baseline → subject: v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` → v50.0 closure HEAD. Shape: SPEC → IMPL → TST → AUDIT-PROTOCOL → TERMINAL. Rationale: pre-launch (no live funds); WHALE-04 freeze-safety PROVEN at SPEC + tested at TST. Mirrors the v45.0 minimal-close precedent. v50 contract history UNPUSHED.

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 334. SPEC — Design-Lock + MINTDIV Reachability + RNGAUDIT Structure | 4/4 | Complete | 2026-05-27 |
| 335. IMPL — The ONE Batched Contract Diff (WHALE + AFSUB + MINTDIV-if-real) | 7/7 | Complete | 2026-05-28 |
| 336. TST — Equivalence + Freeze + Divergence + Regression | 6/6 | Complete | 2026-05-28 |
| 337. AUDIT-PROTOCOL — External-LLM RNG-Audit Kit (Package-Only) | 4/4 | Complete | 2026-05-28 |
| 338. TERMINAL — Internal Delta Audit + Sweep + Closure | 0/4 | 🔒 DEFERRED → v52 (minimal close) | 2026-05-28 |

**Coverage:** 25/25 requirements mapped (334: 3 · 335: 10 · 336: 4 · 337: 4 · 338: 4); 0 orphaned, 0 duplicated. Per-category: WHALE 4 · AFSUB 5 · MINTDIV 2 · RNGAUDIT 4 · TST 4 · SWEEP 3 · BATCH 3. Closed verdict: WHALE_O1_CLAIM + AFKING_PASS_GATED_SUBS + MINTDIV_ALIGNED + EXTERNAL_RNG_AUDIT_KIT shipped; KNOWN_ISSUES_UNMODIFIED. SWEEP-01/02/03 + the BATCH-03 findings/flip portion = the v52 charge. Full detail in `.planning/MILESTONES.md`.

</details>

<details>
<summary>✅ v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep (Phases 329-333) — SHIPPED 2026-05-27</summary>

**Closure signal:** `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` (subject FROZEN `4c9f9d9b`; 0 NEW findings [21 probes: 15 NEGATIVE-VERIFIED + 6 SAFE_BY_DESIGN]; OPEN-E 4-protection HOLD without `:676`; RNG-freeze intact; 666/42/17 by NAME). Audit baseline → subject: v48.0 closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` → v49.0 closure HEAD. ONE batched USER-APPROVED diff `63bc16ca` + the 331 GAS re-peg `4c9f9d9b`. Shape: SPEC → IMPL → GAS → TST → TERMINAL (the dedicated GAS phase because the break-even bounty re-peg was load-bearing — **the shape v54.0 mirrors**). **PUSHED to origin/main 2026-05-27** (`0d9d321f`→`5803da95`, 274 commits — published the prior-unpushed v46/v47/v48/v49 contract history).

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 329. SPEC — Design-Lock + 4 Structural Invariants | 3/3 | Complete | 2026-05-26 |
| 330. IMPL — The ONE Batched Contract Diff (router + advance-rework + micro-opts) | 9/9 | Complete | 2026-05-27 |
| 331. GAS — Worst-Case Marginal + Break-Even @0.5gwei Peg | 6/5 | Complete | 2026-05-27 |
| 332. TST — Freeze Fuzz + One-Category + Regression | 6/6 | Complete | 2026-05-27 |
| 333. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure | 4/4 | Complete | 2026-05-27 |

**Coverage:** 36/36 requirements mapped (329 SPEC: 4 · 330 IMPL: 18 · 331 GAS: 5 · 332 TST: 5 · 333 TERMINAL: 4, re-attests all 36); 0 orphaned, 0 duplicated. Per-category: ROUTER 10 · ADV 5 · GAS 6 · GASOPT 4 · TST 5 · SWEEP 3 · BATCH 3. Closure verdict: UNIFIED_KEEPER_ROUTER + ADVANCE_BOUNTY_RE-HOMED + BOUNTY_RE-PEGGED @0.5gwei + DEGENERETTE_RESOLVE RENAMED + GASOPT-01/03/04/05; 5 surfaces NON-WIDENING; OPEN-E 4-protection HOLD without `:676`; RNG_FREEZE_INTACT; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED. Full detail in `.planning/MILESTONES.md` + `audit/FINDINGS-v49.0.md` (chmod 444).

</details>

<details>
<summary>✅ v48.0 sDGNRS Far-Future Salvage Swap + v47 Deferred-Findings Fixes + Keeper/Pool/Tombstone/Hero Bundle (Phases 325-328) — SHIPPED 2026-05-26</summary>

**Closure signal:** `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (subject frozen `1575f4a9`; 0 NEW findings; F-47-01 + F-47-02 RESOLVED_AT_V48). Audit baseline → subject: v47.0 closure HEAD `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` → v48.0 closure HEAD. ONE batched USER-APPROVED diff `f50cc634` + the 327 HERO-04 constant-only finals landing `1575f4a9`. Shape: SPEC → IMPL → TST → TERMINAL.

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 325. SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation | 3/3 | Complete | 2026-05-25 |
| 326. IMPL — The ONE Batched Contract Diff (all 7 items) | 8/8 | Complete | 2026-05-25 |
| 327. TST — Repro/Same-Results + No-Arb + EV + Regression Proofs | 6/6 | Complete | 2026-05-26 |
| 328. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure | 4/4 | Complete | 2026-05-26 |

**Coverage:** 40/40 requirements mapped; 0 orphaned, 0 duplicated. Per-category: PFIX 3 · RFALL 5 · KEEP 5 · POOL 6 · BTOMB 3 · HERO 6 · SWAP 9 · BATCH 3. The v48 stuck-pool recovery (`Vault.recoverAfKingPool()` + the sDGNRS auto-recover leg) shipped here — **now removed by v54.0's de-custody** (made moot by game-side `keeperFunding`). Full detail in `.planning/MILESTONES.md` + `audit/FINDINGS-v48.0.md` (chmod 444).

</details>

<details>
<summary>✅ v44.0–v47.0 (Phases 304-324) — SHIPPED</summary>

Full per-phase detail for v44.0 (304-308), v45.0 (309-314), v46.0 (316-320), and v47.0 (321-324) lives in `.planning/MILESTONES.md`. Summary:

- **v47.0** Rake-Free Presale + Lootbox-Boon Unification + Redemption/Degenerette/Cancel-Tombstone Bundle (321-324, shipped 2026-05-25; signal `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`). 4-phase SPEC→IMPL→TST→TERMINAL; 45/45 reqs. 2 MEDIUM findings (F-47-01 + F-47-02) DEFERRED→v48.0 (both RESOLVED_AT_V48). H-CANCEL-SWAP-MISS RESOLVED_AT_V47.
- **v46.0** Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal (316-320, shipped 2026-05-24; signal `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`). 6-phase FEATURE milestone with the dedicated GAS phase 319 (the break-even peg precedent v49.0 + v54.0 mirror); the in-tree `AfKing` keeper + the OPEN-E shared `fundingSource` shipped here. 1 MEDIUM finding H-CANCEL-SWAP-MISS DEFERRED→v47.0 (RESOLVED_AT_V47).
- **v45.0** VRF-Rotation Liveness Fix + Consolidate-Forward Delta Audit (309-314, shipped 2026-05-23, minimal close; signal `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`). The CATASTROPHE-class VRF-rotation orphan-index liveness fix; the `v45-vrf-freeze-invariant` north-star established here. **The minimal-close precedent v50.0 + v51.0 mirror (v54.0 does NOT — it runs its own internal sweep).**
- **v44.0** sStonk Per-Day Redemption Refactor + Accounting Invariant Proof (304-308, shipped 2026-05-20; signal `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`). V-184 CATASTROPHE structurally closed; 13/13 invariants proven.

</details>

---
*Roadmap created: 2026-05-25 (v48.0)*
*v49.0 milestone added: 2026-05-26 (5 phases 329-333, SPEC→IMPL→GAS→TST→TERMINAL; 36 reqs / 7 categories) — SHIPPED 2026-05-27, archived to the collapsed block above.*
*v50.0 milestone added: 2026-05-27 (5 phases 334-338, SPEC→IMPL→TST→AUDIT-PROTOCOL→TERMINAL; 25 reqs / 7 categories) — CLOSED 2026-05-28 via minimal close (Phase 338 sweep + FINDINGS DEFERRED → v52); archived to the collapsed block above.*
*v51.0 milestone added: 2026-05-28 (4 phases 339-342, SPEC→IMPL→TST→TERMINAL; 18 reqs / 5 categories) — CLOSED 2026-05-28 via minimal close (341 TST + 342 TERMINAL folded → v52) at IMPL HEAD `c3e9d907`; archived to the collapsed block above.*
*v54.0 milestone added: 2026-05-30 (5 phases 343-347, SPEC→IMPL→GAS+CLEANUP→TST→TERMINAL; 34 reqs / 9 categories: LEDGER 5 · AUTOBUY 5 · DECUSTODY 4 · GAMEOVER 2 · SOLVENCY 3 · CLEANUP 3 · GAS 3 · TST 6 · BATCH 3). Phase numbering continues from 342 (v51.0 ended there; 341/342 folded → v52) → 343. Established v49.0 audit-milestone shape WITH a dedicated GAS phase. **FULL close — the internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v54.0.md` run IN-MILESTONE at TERMINAL (347), NOT deferred** (the solvency-spine touch makes deferral unacceptable, unlike v50.0/v51.0). TWO contract-boundary HARD STOPs (344 IMPL + 345 GAS+CLEANUP). Baseline = v53 HEAD `83a84431` (the atomic `BatchBuy[]` batchPurchase; supersedes v53's cross-contract value-plumbing). Design-locked in `.planning/PLAN-V54-KEEPER-FUNDING-GAME-LEDGER.md` (Decisions A2 + B).*
