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
- ⊘ **v54.0 Game-Side Keeper-Funding Ledger + AfKing De-Custody + Dead-Code/Gas Sweep** — Phases 343-347 (CLOSED-as-superseded 2026-05-30 — 343 SPEC + 344 IMPL shipped `20ca1f79`; 345/346/347 dropped → folded into v55; no `MILESTONE_V54_AT_HEAD` signal)
- 🔨 **v55.0 AfKing-in-Game Redesign** — Phases 348-352 (started 2026-05-30)

---

## 🔨 v55.0 AfKing-in-Game Redesign (Active — started 2026-05-30)

**Milestone:** v55.0 (started 2026-05-30)
**Defined:** 2026-05-30
**Audit baseline → subject:** v54 de-custody HEAD `20ca1f79` (v54.0 CLOSED-as-superseded — 343 SPEC + 344 IMPL shipped; 345/346/347 dropped; no ship signal) → v55.0 closure HEAD (TBD at TERMINAL). Subject = the single carefully-sequenced batched USER-APPROVED `contracts/*.sol` diff for the AfKing-in-Game fold + the box redesign, plus a second gas-pass diff. **Supersedes much of v54:** once subscriber state is game-resident, the cross-contract value plumbing + most of the de-custody ledger machinery collapse into in-context reads.
**Scope source:** `.planning/REQUIREMENTS.md` (29 v55.0 REQ-IDs across 10 categories: ARCH 4 · BOX 5 · FREEZE 3 · REVERT 2 · EVCAP 1 · CONSENT 2 · PLACE 2 · GAS 3 · TST 6 · AUDIT 1) + the milestone init (2026-05-30) + the design-locked SPEC source `.planning/PLAN-V55-AFKING-IN-GAME-REDESIGN.md` (canonical = §10, which supersedes the §0–§3 stamp framing) + the discharged `.planning/PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` (its §5 = the 4 LOCKED obligations). **No research** — a fully-specced internal contract refactor with a discharged proof; the funding-model + placement explorations are already resolved (the proof made required-path viable).

> **Audit posture — FULL CLOSE WITH ITS OWN INTERNAL SWEEP (NOT deferred).** Like v54.0 (and unlike v50.0 + v51.0, which deferred their internal sweep → the v52 consolidated audit), **v55.0 runs its own internal 3-skill genuine-PARALLEL adversarial sweep + delta-audit + `audit/FINDINGS-v55.0.md` at TERMINAL (352, AUDIT-01)** — the 3-skill pass (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) + the delta-audit + `audit/FINDINGS-v55.0.md` (chmod 444) + the atomic 5-doc closure flip all execute in-milestone, focused on the **box-stamp freeze + the liveness isolation + the two-path open**. Rationale: this redesign touches the **RNG-freeze + solvency spine** — the freeze invariants (§3) + the discharged REVERT-FREE-CHAIN proof + the Phase-343 SOLVENCY-01 are the load-bearing concerns and must be adversarially probed in-milestone, not deferred. (The separate v52 consolidated cross-model audit still folds the v55 surface into its cumulative sweep — an additional track, not a substitute for v55's own close.)

> **Cross-cutting rule (every requirement):** every cited `file:line` MUST be re-attested against the **v54 de-custody HEAD `20ca1f79`** before any patch (no "by construction" / "single fn reaches all paths" claim survives un-checked — the `DegenerusGame` mint/jackpot inline-duplication precedent; `feedback_verify_call_graph_against_source`). The cited anchors (the box-freeze snapshot `DegenerusGameLootboxModule.sol:530-551`/`:534`; the EV-cap helper `_applyEvMultiplierWithCap` `LB:459-495` + the `lootboxEvBenefitUsedByLevel` map `Storage:1468-1469`/cap `:1326`; the slice builder `_resolveBuy` `AfKing.sol:727-795` + its named-revert comments `:766-767`/`:781-782`; the mid-day index advance `AdvanceModule.sol:1016` + the RNG-request index advance `:1086-1090`/`:1626-1630`; the non-reverting ticket-drain budget loop `MintModule.sol:699`; the `_enforceDailyMintGate` `AdvanceModule.sol:973`; the OPEN-E consent gate `AfKing.sol:400-409` + `src` resolution `:682`; the code-size reclaim targets `claimAffiliateDgnrs`→BingoModule [1,283B], `playerActivityScore` [953B], `previewSellFarFutureTickets` [383B]) are confirmed at SPEC. **Security / freeze / solvency floor over gas** (`feedback_security_over_gas`): the freeze spine (§3) is load-bearing; the REVERT-FREE-CHAIN proof + SOLVENCY-01 (Phase 343) are the discharged foundations carried in. Pre-launch redeploy-fresh (storage-layout break fine, no migration; `feedback_frozen_contracts_no_future_proofing`).

> **Posture:** the contract changes ship across **TWO carefully-sequenced batched USER-APPROVED `contracts/*.sol` diffs** with **HARD STOPs at the contract-commit boundary** (applied + locally compiled/tested, NEVER committed without explicit user hand-review — `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`; `ContractAddresses.sol` freely modifiable per `feedback_contractaddresses_policy`). The 349 IMPL diff lands the AfKing-in-Game fold + the box redesign (the code-size reclaim FIRST so the Game never breaches the 24,576-byte ceiling mid-flight, then the GameAfkingModule + storage append + the box stamp/process-pass/open-pass + the AfKing stubs + the preserved slice-builder invariants + the EV-cap-at-open + the skip valve). The 350 GAS diff lands the further behavior-identical no-cost wins (GAS-01/02/03) under the security floor. Both are HARD STOPs; both prove same-results in TST (351). The diff is authored producer-before-consumer (storage append → GameAfkingModule process/open/router → interfaces → AfKing thin stubs). Tests + planning + docs AGENT-committable.

> **Why two contract gates (349 IMPL + 350 GAS) mirror v49.0 + v54.0:** v49.0 / v54.0 each carried a dedicated GAS phase because a load-bearing gas change needs its own measurement + USER gate; v55.0 mirrors that — 349 lands the functional refactor (the fold + box redesign) under the first gate; 350 lands the FURTHER behavior-identical gas wins (gas-scavenger → gas-skeptic) under the second gate. Both are HARD STOPs; both prove same-results in TST (351).

> **Phase numbering** continues from the previous milestone — v54.0 ran 343–347, so **v55.0 starts at Phase 348.** Not reset to 1. (Prior milestones' phase dirs are archived under `.planning/milestones/vXX.0-phases/`.)

> **Milestone shape** is the established v49.0 + v54.0 audit pattern (with a dedicated GAS phase): **348 SPEC design-lock (re-attest the §10 design + PROVE the FREEZE spine + carry the discharged REVERT-FREE-CHAIN + EV-cap invariants + DECIDE §4 placement + produce the code-size reclaim plan + GAS inventory + call-graph attestation) → 349 IMPL single carefully-sequenced batched contract diff (code-size reclaim → GameAfkingModule + storage append + box stamp/process-pass/open-pass + AfKing stubs + preserved slice-builder invariants + EV-cap-at-open + skip valve) → 350 GAS (further behavior-identical no-cost wins, proven same-results) → 351 TST (the empirical proofs TST-01..06: freeze/determinism, revert-free, EV-cap, two-path + set-mutation, NON-WIDENING vs the v54 baseline, gas) → 352 TERMINAL FULL close (delta-audit + 3-skill genuine-PARALLEL adversarial sweep + `audit/FINDINGS-v55.0.md` + atomic 5-doc closure flip).** The contract-boundary HARD STOP lives at TWO phases (349 IMPL + 350 GAS).

### Phases

- [ ] **Phase 348: SPEC — Design-Lock + Freeze Proof + Discharged-Invariant Carry + §4 Placement Decision + Code-Size/GAS Inventories + Call-Graph Attestation** - Re-attest the §10 design vs the v54 baseline `20ca1f79`; lock the GameAfkingModule split + the `DegenerusGameStorage` append layout + the per-sub stamp `(index, amount, day)` shape + the two-open-route wiring; PROVE the FREEZE spine (freeze-completeness / pre-RNG index-binding / stamped-day determinism); carry the discharged REVERT-FREE-CHAIN invariant (preserve `_resolveBuy`'s slice-builder invariants verbatim) + the EV-cap-at-open equivalence as locked SPEC invariants; DECIDE §4 placement (required-path vs separate-legs, on non-revert grounds); produce the code-size reclaim plan (ARCH-04, sequenced so the Game never breaches 24,576 mid-flight) + the GAS-opportunity inventory; confirm the OPEN-E/AFSUB/set-mutation carry-over; grep-attest every `file:line` vs `20ca1f79` — paper-only, ZERO `contracts/*.sol`.
- [ ] **Phase 349: IMPL — The ONE Carefully-Sequenced Batched Contract Diff (code-size reclaim → fold + box redesign)** - Land the single reconciled `contracts/*.sol` diff in code-size-safe order: the code-size reclaim FIRST (`claimAffiliateDgnrs`→`BingoModule` ≈1.3KB + read-aggregators drop-`view`/→lens) so the Game stays < 24,576 at every intermediate step, then the `GameAfkingModule` (delegatecall) + the `DegenerusGameStorage` append (subscriber set + cursors + per-sub box-stamp + `afkingFunding` ledger) + the box redesign (boons OFF → amount = spend; the process-pass stamps `(index = LR_INDEX, amount, day)` + debits `afkingFunding` + sets the `lastAutoBoughtDay == today` success-marker only after a successful debit; the open-pass materializes from the stamp + `lootboxRngWordByIndex[index]` byte-identical to `openLootBox`, `lastOpenedIndex` monotonic) + the AfKing thin dispatch stubs + the preserved slice-builder invariants verbatim (REVERT-01) + the EV-cap-at-open via `_applyEvMultiplierWithCap[player][level+1]` with the buy-time write bypassed (EVCAP-01) + the thin per-sub try/catch skip valve on both legs (REVERT-02) + the OPEN-E/pass-gating/exemption/set-mutation carry-over (CONSENT-01/02) + the bounty reconciliation (PLACE-02); authored producer-before-consumer, applied to `contracts/` and locally compiling (`forge build` clean), then HELD at the contract-commit boundary for explicit user hand-review.
- [ ] **Phase 350: GAS — Behavior-Identical No-Cost Wins (box-ledger → warm Sub-stamp + staticcall → SLOAD + same-slot aggregate flushes)** - Apply the validated behavior-identical, no-cost gas wins from the SPEC GAS inventory under the security-over-gas floor (gas-scavenger → gas-skeptic, each gas-only, proven same-results in TST): the ~120–130k/afking box-buy collapse (the ~6 cold box-ledger SSTOREs + `boxPlayers.push` + `enqueueBoxForAutoOpen` → one warm-dirty Sub-stamp write, GAS-01); the per-subscriber `afkingSnapshot`/`afkingFundingOf` cross-contract staticcalls → in-context `SLOAD`s (GAS-02); and the same-slot affiliate/pool aggregate flushes across a process batch (`claimablePool`/`prizePoolsPacked` accumulate-and-flush; bucket affiliate by roll-winner — SAFE-WITH-CONDITIONS, NOT batching `quests.handleAffiliate`'s non-linear completion logic, GAS-03). Any net contract change rides a SECOND batched USER-APPROVED diff held at the contract-commit boundary; wins that trade an invariant or aren't real are REJECTED with reasoning. (Note: most of GAS-01/02 is structural to the IMPL relocation — this phase confirms the savings + lands any residual same-slot batching + extra gas-scavenger wins under the gate.)
- [ ] **Phase 351: TST — Freeze/Determinism + Revert-Free + EV-Cap + Two-Path + Set-Mutation + Non-Widening + Gas** - Prove the redesign behaviorally correct empirically against the game-resident model (not v54's soon-replaced de-custody machinery, so no throwaway test work): the stamp+open produces an identical box outcome independent of open timing/block (seed uses the STAMPED day) + index-binding holds across a mid-day index advance (TST-01); a funded process/open never reverts on well-formed slices (the preserved `_resolveBuy` invariants) + the skip valve isolates the solvency/liveness residuals without bricking the batch/day (TST-02); the per-`(player, level)` 10-ETH EV-benefit budget is enforced exactly once per open with no double-draw vs the buy-time path, equivalent to v54 (TST-03); two-path open coexistence + set-mutation (eviction/tombstone/swap-pop, streak preserved) + the OPEN-E 4-protection regression (TST-04); the suite is NON-WIDENING vs the v54 baseline `20ca1f79` (every pre-existing red enumerated BY NAME, `REGRESSION-BASELINE-v55.md`, TST-05); and the per-buy + per-open marginal gas is measured under the 16.7M HARD per-tx ceiling with the GAS-01/02/03 wins proven same-results (TST-06).
- [ ] **Phase 352: TERMINAL — Delta Audit + 3-Skill Genuine-PARALLEL Adversarial Sweep + FINDINGS-v55.0 + Closure Flip** - Close the v55.0 audit subject (the carefully-sequenced batched diff — the AfKing-in-Game fold + the box redesign + the gas pass, FROZEN at the IMPL+GAS HEAD) via a FULL close that runs its own internal sweep IN-MILESTONE (NOT deferred to v52): a delta-audit (every v55 surface NON-WIDENING vs the v54 HEAD `20ca1f79`; the freeze spine + the discharged REVERT-FREE-CHAIN + SOLVENCY-01 + the OPEN-E 4-protection re-attested intact) + the 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) focused on the box-stamp freeze + the liveness isolation + the two-path open + `audit/FINDINGS-v55.0.md` (chmod 444) + the atomic 5-doc closure flip with the `MILESTONE_V55_AT_HEAD_<sha>` signal — the internal sweep runs IN-MILESTONE (NOT deferred to v52).

---

## Phase Details

### Phase 348: SPEC — Design-Lock + Freeze Proof + Discharged-Invariant Carry + §4 Placement Decision + Code-Size/GAS Inventories + Call-Graph Attestation

**Goal**: The AfKing-in-Game redesign's shapes are settled in writing so the IMPL phase authors a fully reconciled, code-size-safe diff with zero "by construction" assumptions, and the load-bearing FREEZE spine is PROVEN before any code is written: the GameAfkingModule split + the `DegenerusGameStorage` append layout + the per-sub stamp `(index, amount, day)` shape + the two-open-route wiring are locked; the freeze invariants (freeze-completeness / pre-RNG index-binding / stamped-day determinism) are PROVEN on paper; the discharged REVERT-FREE-CHAIN invariant (preserve `_resolveBuy`'s slice-builder validation verbatim) + the EV-cap-at-open equivalence are carried as locked SPEC invariants; the §4 placement (required-path vs separate permissionless legs) is DECIDED on non-revert grounds; the code-size reclaim plan (ARCH-04, sequenced) + the GAS-opportunity inventory are produced; the OPEN-E/AFSUB/set-mutation carry-over is confirmed; and every cited `file:line` is grep-verified against the v54 HEAD `20ca1f79` — paper-only, zero `contracts/*.sol`.
**Type**: SPEC
**Depends on**: Nothing (first v55.0 phase; consumes the v54 de-custody HEAD `20ca1f79` as the frozen audit baseline, plus the discharged `.planning/PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` + the design-lock `.planning/PLAN-V55-AFKING-IN-GAME-REDESIGN.md` §10)
**Requirements**: FREEZE-01, FREEZE-02, FREEZE-03, PLACE-01, ARCH-04
**Success Criteria** (what must be TRUE):

  1. The FREEZE spine is PROVEN, not assumed (FREEZE-01 / FREEZE-02 / FREEZE-03) — **freeze-completeness** (FREEZE-01): the stamp captures ALL outcome-determining state at process; the open re-derives nothing manipulable from mutable per-player state — and the §10 live score/base-level/EV-cap reads are admitted ONLY because in-window manipulation is −EV (the 80→135% multiplier is streak-built over many levels; one mint in the reveal→open window moves it a few % and costs ~a full box), documented + attested; **index-binding** (FREEZE-02): the stamp binds to the pre-RNG `LR_INDEX` read once at pass start, and the process-pass MUST NOT straddle a mid-day `requestLootboxRng` index advance (`AdvanceModule.sol:1016`; the index only advances at RNG-request `:1086-1090`/`:1626-1630`) — proven the process reads `LR_INDEX` once; **determinism** (FREEZE-03): the box seed `keccak256(rngWord, player, day, amount)` uses the STAMPED buy-day (never open-time `_simulatedDayIndex()`) and carries no `block.timestamp/number/prevrandao/coinbase/blockhash` in the draw (confirmed none in the lootbox module today).

  2. The discharged REVERT-FREE-CHAIN + EV-cap invariants are carried as locked SPEC invariants (PLACE-01 input) — the proof's 4 LOCKED obligations (`.planning/PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` §5) are restated as the v55 invariant set: (1) preserve `_resolveBuy`'s validation invariants VERBATIM when it folds into the process-pass — `ev = cost − claimableUse` + enum payKind, the 1-wei claimable sentinel, the `LOOTBOX_MIN` transient skip, `quantity ≥ 1` (migration fidelity, the load-bearing obligation); (2) EV-cap at open via `_applyEvMultiplierWithCap(player, level+1, amount, mult)` keyed on the SAME `lootboxEvBenefitUsedByLevel[player][level+1]` map, exactly once per open, hard-clamped ≤10 ETH (no revert), with the buy-time EV write BYPASSED for afking boxes (no double-draw — proven equivalent to the v54 per-`(sub,level)` accumulator); (3) stamp `(index, amount, day)` + seed the open with the stamped day; (4) a thin per-sub try/catch skip valve on BOTH legs absorbs the two residual revert classes (solvency-violation [safe under SOLVENCY-01] + liveness-timeout [game-dead]). The 3 §7 SPEC follow-ups from the proof doc (cost-unit reconciliation `mp·effectiveQty` vs `priceForLevel·ticketQuantity/(4·TICKET_SCALE)`, the `(index, amount, day)` stamp field widths, the double-draw guard) are discharged.

  3. The §4 placement is DECIDED on non-revert grounds (PLACE-01) — the placement (required-path `advanceGame` phase vs separate permissionless legs) is decided in writing: required-path is now VIABLE/clean (the proof showed a funded well-formed sub can't revert in a healthy game → won't freeze the day), so the choice rests on guaranteed-every-day vs minimal-surface, the `_enforceDailyMintGate` standing interaction (`AdvanceModule.sol:973` — required-path needs minting standing or the 15–30min time-laddered bypass), and bounty farm-by-splitting; the process-leg runs pre-RNG cursor-chunked (`BUY_BATCH`-style), the open-leg post-`_unlockRng` cursor-chunked (`OPEN_BATCH`-style); recommendation leans separate-legs for minimal surface, with the decision (and its rationale) recorded for IMPL.

  4. The code-size reclaim plan is produced + sequenced (ARCH-04) — a measured, agent-verified reclaim plan that keeps the Game runtime code-size < 24,576 bytes at EVERY intermediate step: `claimAffiliateDgnrs`→`BingoModule` (1,283B, zero-risk void) FIRST before adding any afking stubs; `playerActivityScore` (953B) + `previewSellFarFutureTickets` (383B) → a lens / drop-`view` (a delegatecall stub can't be `view`; precedent `DeityBoonViewer.sol`); the ~650B reserve (`decClaimable`/`getTickets`/`getDailyHeroWinner`) — realistic clean reclaim ≈ 2.8KB vs the ~1.5KB the stubs need + the 218B current headroom — with the edit-order sequenced so the ceiling is never breached mid-flight.

  5. The OPEN-E/set-mutation carry-over is confirmed + every cited `file:line` is grep-attested vs `20ca1f79` (CONSENT inputs / FREEZE / ARCH) — the subscribe-time `isOperatorApproved` (OPEN-E) gate (`AfKing.sol:400-409`), the pass-gating (`validThroughLevel`), the VAULT/SDGNRS exemption-on-`player`, the funder=src accounting (`:682`), and the set-mutation invariant ("no cursor advance after swap-pop", the H-CANCEL-SWAP-MISS / cancel-tombstone-streak class) are confirmed to carry over verbatim with the OPEN-E 4-protection structure re-attested; the GameAfkingModule + storage-append + two-path-open shapes are reconciled producer-before-consumer for the IMPL edit-order map; and every cited anchor across the milestone scope (the box-freeze snapshot, the EV-cap helper + map, the slice builder + its named-revert comments, the index-advance sites, the non-reverting drain loop, the mint-gate, the OPEN-E surface, the code-size reclaim targets) is grep-verified against `20ca1f79` with any drift corrected in the SPEC (no "by construction" survives un-checked).

**Plans**: 6 plans (4 waves) — the D-08 multi-doc SPEC set (343 precedent)
- [x] 348-01-PLAN.md — `348-GREP-ATTESTATION.md`: re-pin every cited `file:line` vs `20ca1f79` (resolve the box-seed `abi.encode`-vs-`abi.encodePacked` drift); upstream producer [wave 1; FREEZE-02/03, ARCH-04]
- [x] 348-02-PLAN.md — `348-CODE-SIZE-PLAN.md` (`forge build --sizes` measured reclaim, running-total < 24,576) + `348-GAS-INVENTORY.md` (`/gas-scavenger` advisory + GAS-03 SAFE-WITH-CONDITIONS) [wave 1; ARCH-04]
- [ ] 348-03-PLAN.md — `348-FREEZE-PROOF.md` (FREEZE-01/02/03 proven; live-read = accepted-by-design known issue) + `348-INVARIANT-CARRY.md` (the discharged invariants + the D-348-04 try/catch DROP + the light `/contract-auditor` obligation-1 pass); `autonomous: false` [wave 2; FREEZE-01/02/03]
- [ ] 348-04-PLAN.md — `348-PLACEMENT-DECISION.md`: §4 DECIDED = required-path (D-348-01 USER override; PLAN-V55 §4/§9 superseded; two proof obligations carried) [wave 2; PLACE-01]
- [ ] 348-05-PLAN.md — `348-IMPL-EDIT-ORDER-MAP.md`: the producer-before-consumer edit-order for the 349 diff (reclaim FIRST → storage append → GameAfkingModule → AdvanceModule STAGE → interfaces → AfKing stubs) [wave 3; ARCH-04]
- [ ] 348-06-PLAN.md — `348-SPEC-INDEX.md`: the D-08 index + requirement/SC traceability + the OPEN-E/set-mutation carry-over confirmation + the SPEC verdict + the 349 hand-off [wave 4; FREEZE-01/02/03, PLACE-01, ARCH-04]
**UI hint**: no

### Phase 349: IMPL — The ONE Carefully-Sequenced Batched Contract Diff (code-size reclaim → fold + box redesign)

**Goal**: The AfKing-in-Game redesign lands as a single reconciled `contracts/*.sol` diff under the SPEC's settled shapes, authored in code-size-safe order so the Game runtime never breaches 24,576 bytes mid-flight: the code-size reclaim FIRST (`claimAffiliateDgnrs`→`BingoModule` ≈1.3KB + the read-aggregators drop-`view`/→lens), then the new `GameAfkingModule` (delegatecall, inherits `DegenerusGameStorage`) owning `subscribe`/setters + the process-pass + the open-pass + the router + the `DegenerusGameStorage` append (the subscriber set `_subOf`/`_subscribers`/`_subscriberIndex` + the process/open cursors + the per-sub box-stamp + the `afkingFunding` ledger) + the box redesign (boons OFF → box `amount` = spend; the process-pass [pre-RNG] writes the stamp `(index = current `LR_INDEX`, amount, day)` + debits `afkingFunding` + sets the `lastAutoBoughtDay == today` success-marker ONLY after a successful debit; the open-pass [post-RNG] materializes from the stamp + `lootboxRngWordByIndex[stamp.index]` byte-identical to `openLootBox`, `lastOpenedIndex` monotonic; humans keep the existing `lootboxEth`/`boxPlayers` route → two open routes) + `AfKing.sol` collapsed to thin dispatch stubs + the preserved slice-builder invariants VERBATIM (REVERT-01) + the EV-cap-at-open via `_applyEvMultiplierWithCap[player][level+1]` with the buy-time write bypassed (EVCAP-01) + the thin per-sub try/catch skip valve on both legs (REVERT-02) + the OPEN-E/pass-gating/exemption/set-mutation carry-over (CONSENT-01/02) + the bounty reconciliation (PLACE-02) — authored producer-before-consumer, applied to `contracts/` and locally compiling (`forge build` clean), then HELD at the contract-commit boundary for explicit user hand-review.
**Type**: IMPL (CONTRACT BOUNDARY — the ONE carefully-sequenced batched USER-APPROVED `contracts/*.sol` diff; `autonomous: false` at the commit gate; never auto-commit contracts)
**Depends on**: Phase 348 (the SPEC must lock the module split + storage append + stamp shape + two-path wiring, PROVE the FREEZE spine, carry the discharged REVERT-FREE-CHAIN + EV-cap invariants, DECIDE §4 placement, produce the sequenced code-size reclaim plan, confirm the OPEN-E/set-mutation carry-over, and grep-attest the edit-order map first)
**Requirements**: ARCH-01, ARCH-02, ARCH-03, BOX-01, BOX-02, BOX-03, BOX-04, BOX-05, REVERT-01, REVERT-02, EVCAP-01, CONSENT-01, CONSENT-02, PLACE-02
**Success Criteria** (what must be TRUE):

  1. The state is game-resident + the GameAfkingModule owns the logic + the Game stays under the ceiling (ARCH-01 / ARCH-02 / ARCH-03 / ARCH-04-delivered) — the subscriber set (`_subOf`/`_subscribers`/`_subscriberIndex`), the process/open cursors, the per-sub box-stamp, and the v54 `afkingFunding` ledger are appended to `DegenerusGameStorage` (layout-safe append; every module shares the base); a new `GameAfkingModule` (delegatecall, inherits `DegenerusGameStorage`) owns `subscribe`/setters + the process-pass + the open-pass + the router (its bytecode is its own budget, not the Game's); `AfKing.sol` collapses to thin dispatch stubs (`subscribe`/`setDailyQuantity`/`doWork`/…) ≈1–1.5KB with the `AF_KING`-address dissolution-vs-thin-shim question resolved (incl. the mandatory-mint-gate interaction if any entry routes through `advanceGame`); and the reclaim lands FIRST (`claimAffiliateDgnrs`→`BingoModule` + read-aggregators drop-`view`/→lens) so the Game runtime code-size stays < 24,576 bytes at every intermediate step (sequenced per the SPEC map; verified by the build).

  2. The box freeze is RELOCATED into the per-sub stamp, not derived (BOX-01 / BOX-02 / BOX-03) — boons are OFF for afking boxes → box `amount` = spend (the boosted-amount freeze field deleted, BOX-01); the process-pass (pre-RNG) writes the per-sub stamp `(index = current `LR_INDEX`, amount, day)` as one warm-dirty write per process-day, overwritten each cycle, with NO cold `lootboxEth*`/`lootboxPurchasePacked`/`boxPlayers.push` (BOX-02); and the process-pass debits `afkingFunding` and sets the `lastAutoBoughtDay == today` success-marker ONLY after a successful debit — a failed buy writes no marker (no free box), and a wallet subscribing between the process pass and the open has no this-cycle marker (no free box) (BOX-03).

  3. The open-pass materializes byte-identically with no double-open + the two routes are hazard-free (BOX-04 / BOX-05) — the open-pass (post-RNG) materializes the box from the stamp + the committed `lootboxRngWordByIndex[stamp.index]` with math byte-identical to `openLootBox` (including the benign open-time `level`/`currentDay` dependence of `targetLevel` kept identical so ticket placement/value doesn't drift), and `lastOpenedIndex` is monotonic per sub (open only if `stamp.index > lastOpenedIndex` → no double-open) (BOX-04); humans (not in the sub set) keep the existing `lootboxEth`/`boxPlayers` open route unchanged, and the two open routes share no mutable-state hazard (BOX-05).

  4. The discharged invariants are preserved + the EV-cap + skip valve land (REVERT-01 / REVERT-02 / EVCAP-01) — the process-pass slice construction preserves `_resolveBuy`'s validation invariants VERBATIM (`ev = cost − claimableUse` + enum payKind, the 1-wei claimable sentinel, the `LOOTBOX_MIN` transient skip, `quantity ≥ 1`) so the funded buy is revert-free by construction (migration fidelity, REVERT-01); a thin per-sub try/catch skip valve isolates the process AND open legs, absorbing the two residual revert classes (solvency-violation [safe under SOLVENCY-01], liveness-timeout [game-dead]) so no single sub can brick a batch/the day (REVERT-02); and the afking open increments `lootboxEvBenefitUsedByLevel[player][level+1]` via `_applyEvMultiplierWithCap` (read+write-at-open, exactly once per open, same map/key as MintModule's buy-time write, hard-clamped ≤10 ETH → no revert) with the buy-time EV write BYPASSED for afking boxes (no double-draw) (EVCAP-01).

  5. The consent/set-mutation carry over + the bounty is reconciled + `forge build` is clean + the diff is HELD at the boundary (CONSENT-01 / CONSENT-02 / PLACE-02) — the subscribe-time `isOperatorApproved` (OPEN-E) gate, the pass-gating (`validThroughLevel`), the VAULT/SDGNRS exemption-on-`player`, and the funder=src accounting carry over verbatim with the OPEN-E 4-protection structure re-attested (CONSENT-01); evictions preserve "no cursor advance after swap-pop" (the H-CANCEL-SWAP-MISS / cancel-tombstone-streak class) and the tombstone-then-reclaim shape carries over (CONSENT-02); the open stays a post-RNG router category (`OPEN_BATCH`/`OPEN_KNEE` pro-rate) and the buy/process bounty is work-scaled (not once-per-advance) to close the middle-chunk-unpaid gap and resist farm-by-splitting, with payment the deferred BURNIE flip-credit mint (`creditFlip`) (PLACE-02); and the whole diff is authored producer-before-consumer per the SPEC edit-order map, applied to `contracts/` and locally compiling (`forge build` clean; `ContractAddresses.sol` freely modifiable), but NOT committed without explicit user hand-review of the single batched diff.

**Plans**: TBD
**UI hint**: no

### Phase 350: GAS — Behavior-Identical No-Cost Wins (box-ledger → warm Sub-stamp + staticcall → SLOAD + same-slot aggregate flushes)

**Goal**: Beyond the freeze-correct relocation the IMPL diff already delivers, the keeper/funding blast radius gets confirmed + completed under the security-over-gas floor: the validated behavior-identical, no-cost gas wins from the SPEC GAS inventory are applied (gas-scavenger surfaces, gas-skeptic validates — each gas-only, proven same-results in TST; invariant-trading or not-real wins REJECTED with reasoning, not re-litigated): the afking box-buy's ~6 cold box-ledger SSTOREs + `boxPlayers.push` + `enqueueBoxForAutoOpen` (~120–130k) collapse to one warm-dirty Sub-stamp write (~5k) is confirmed (GAS-01); the per-subscriber `afkingSnapshot`/`afkingFundingOf` cross-contract staticcalls (~3–5k each) become in-context `SLOAD`s (GAS-02); and the same-slot affiliate/pool aggregate flushes across a process batch (`claimablePool`/`prizePoolsPacked` accumulate-and-flush; bucket affiliate by roll-winner — SAFE-WITH-CONDITIONS, do NOT batch `quests.handleAffiliate`'s non-linear completion logic) land (GAS-03). Any net contract change rides a SECOND batched USER-APPROVED diff held at the contract-commit boundary.
**Type**: GAS (CONTRACT BOUNDARY — the SECOND batched USER-APPROVED `contracts/*.sol` diff; `autonomous: false` at the commit gate)
**Depends on**: Phase 349 (the gas pass operates on the post-fold game-resident surface — the warm Sub-stamp write + the in-context subscriber set + the process-batch loop the IMPL established must exist before the same-slot aggregate flushes can be applied and the relocation savings confirmed)
**Requirements**: GAS-01, GAS-02, GAS-03
**Success Criteria** (what must be TRUE):

  1. The box-ledger → warm Sub-stamp collapse is confirmed same-results (GAS-01) — the afking box-buy's ~6 cold box-ledger SSTOREs + `boxPlayers.push` + `enqueueBoxForAutoOpen` (~120–130k) are confirmed collapsed to one warm-dirty Sub-stamp write (~5k), measured and proven behavior-identical (same materialized box outcome) in TST (351); this is the headline ~120k/afking box-buy saving from the relocation, validated under the security floor.

  2. The cross-contract staticcalls become in-context SLOADs (GAS-02) — the per-subscriber `afkingSnapshot`/`afkingFundingOf` cross-contract staticcalls (~3–5k each) are replaced by in-context `SLOAD`s now that the subscriber set + `afkingFunding` are game-resident, proven same-results in TST (351); no value-plumbing or cross-contract read remains on the hot process/open path.

  3. The same-slot aggregate flushes land SAFE-WITH-CONDITIONS (GAS-03) — the same-slot affiliate/pool aggregate flushes across a process batch (`claimablePool`/`prizePoolsPacked` accumulate-and-flush, bucket affiliate by roll-winner) are applied as a gas-only change proven same-results in TST (351), explicitly NOT batching `quests.handleAffiliate` (non-linear completion logic — the SAFE-WITH-CONDITIONS carve-out); each win that trades an invariant or isn't real is REJECTED with reasoning (the v49 gas-skeptic precedent), not re-litigated.

  4. The second contract diff is held at the boundary (GAS-01 / GAS-02 / GAS-03) — any `contracts/*.sol` change from this phase (the residual same-slot batching + any extra gas-scavenger wins beyond the structural IMPL relocation) rides a SECOND batched USER-APPROVED diff, applied + locally compiling (`forge build` clean), HELD at the contract-commit boundary for explicit user hand-review (never auto-committed); if the phase produces no net contract change beyond what the IMPL relocation already delivered (all residual wins rejected / NEGATIVE), that is recorded as the outcome and no diff is gated.

**Plans**: TBD
**UI hint**: no

### Phase 351: TST — Freeze/Determinism + Revert-Free + EV-Cap + Two-Path + Set-Mutation + Non-Widening + Gas

**Goal**: The redesign is proven behaviorally correct empirically against the game-resident model (not v54's soon-replaced de-custody machinery, so no throwaway test work): the stamp+open produces an identical box outcome independent of open timing/block (the seed uses the STAMPED day) and index-binding holds across a mid-day index advance; a funded process/open never reverts on well-formed slices (the preserved `_resolveBuy` invariants) and the thin per-sub skip valve isolates the solvency/liveness residuals without bricking the batch/day; the per-`(player, level)` 10-ETH EV-benefit budget is enforced exactly once per open with no double-draw vs the buy-time path (equivalent to v54); two-path open coexistence + set-mutation (eviction/tombstone/swap-pop, streak preserved) + the OPEN-E 4-protection hold; the suite is NON-WIDENING vs the v54 baseline `20ca1f79` (every pre-existing red enumerated BY NAME); and the per-buy + per-open marginal gas is measured under the 16.7M HARD per-tx ceiling with the GAS-01/02/03 wins proven same-results — restoring a clean v55.0 regression baseline.
**Type**: TST
**Depends on**: Phase 350 (tests exercise the FINAL applied surface — the live fold + box redesign from 349 plus whatever same-slot batching / gas-scavenger wins 350 landed — not SPEC placeholders or an intermediate pre-gas state)
**Requirements**: TST-01, TST-02, TST-03, TST-04, TST-05, TST-06
**Success Criteria** (what must be TRUE):

  1. Freeze/determinism is proven (TST-01) — the stamp+open produces an identical box outcome independent of open timing/block (the seed uses the STAMPED day, never open-time `_simulatedDayIndex()`): two opens of the same stamp at different blocks/days yield byte-identical materialized boxes, and index-binding holds across a mid-day `requestLootboxRng` index advance (a process-pass that reads `LR_INDEX` once never attaches to an index whose word already exists).

  2. Revert-free + the skip valve are proven (TST-02) — a funded process/open never reverts on well-formed slices (exercising the preserved `_resolveBuy` invariants — `ev = cost − claimableUse`, the 1-wei sentinel, the `LOOTBOX_MIN` skip, `quantity ≥ 1`), and the thin per-sub try/catch skip valve isolates the two residual revert classes (solvency-violation, liveness-timeout) without bricking the batch/the day (a single poisoned sub is skipped; the rest of the batch + the day proceed).

  3. EV-cap is proven exactly-once with no double-draw (TST-03) — the per-`(player, level)` 10-ETH EV-benefit budget (`lootboxEvBenefitUsedByLevel[player][level+1]`) is enforced exactly once per open via `_applyEvMultiplierWithCap`, with NO double-draw vs the buy-time path (the buy-time EV write is bypassed for afking boxes), and the accounting is proven equivalent to the v54 per-`(sub,level)` accumulator (same map + same `level+1` key + one shared per-level budget across afking and any residual human boxes).

  4. Two-path coexistence + set-mutation + OPEN-E hold (TST-04) — the two open routes (afking-stamp vs human `lootboxEth`/`boxPlayers`) coexist with no shared-state hazard; set-mutation (eviction / tombstone / swap-pop) preserves the mint-streak ("no cursor advance after swap-pop" — the H-CANCEL-SWAP-MISS regression NEGATIVE-VERIFIED); and the OPEN-E 4-protection structure regression-holds (consent-gate-at-subscribe / default-self / no-escalation / trust-the-sub temporal bound).

  5. The NON-WIDENING regression + the gas measurement are proven (TST-05 / TST-06) — the reconceived afking/keeper suite compiles + passes against the game-resident model with net-zero new regression vs the v54 baseline `20ca1f79` (every pre-existing red enumerated BY NAME, `REGRESSION-BASELINE-v55.md`), absorbing any test renames / oracle migrations from the fold (incl. whatever 350 landed); and the per-buy + per-open marginal gas is measured under the 16.7M HARD per-tx ceiling with the GAS-01/02/03 wins proven same-results (the ~120k box-buy collapse + the staticcall→SLOAD + the same-slot flushes confirmed behavior-identical).

**Plans**: TBD
**UI hint**: no

### Phase 352: TERMINAL — Delta Audit + 3-Skill Genuine-PARALLEL Adversarial Sweep + FINDINGS-v55.0 + Closure Flip

**Goal**: The v55.0 audit subject (the carefully-sequenced batched diff — the AfKing-in-Game fold + the box redesign + the gas pass, FROZEN at the IMPL+GAS HEAD) is closed via a FULL close that runs its own internal sweep IN-MILESTONE (NOT deferred to v52, like v54.0 and unlike v50.0/v51.0): a delta-audit confirms every v55 surface is NON-WIDENING vs the v54 HEAD `20ca1f79` with the freeze spine (§3) + the discharged REVERT-FREE-CHAIN + the Phase-343 SOLVENCY-01 + the OPEN-E 4-protection re-attested intact; the 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT) probes the box-stamp freeze + the liveness isolation + the two-path open; `audit/FINDINGS-v55.0.md` (chmod 444) is authored; and the atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) is applied with the `MILESTONE_V55_AT_HEAD_<sha>` closure signal.
**Type**: TERMINAL (FULL close — delta-audit + internal 3-skill adversarial sweep + FINDINGS + closure flip; NOT deferred)
**Depends on**: Phase 351 (the subject must be implemented + gas-swept + test-proven — incl. the freeze/determinism + revert-free + EV-cap + NON-WIDENING proofs — before the requirements are re-attested at closure and the adversarial sweep runs on the proven surface)
**Requirements**: AUDIT-01
**Success Criteria** (what must be TRUE):

  1. The delta-audit + the internal 3-skill adversarial sweep are run IN-MILESTONE (AUDIT-01) — the delta-audit confirms every v55 surface (the code-size reclaim + the `GameAfkingModule` + the storage append + the box stamp/process-pass/open-pass + the AfKing stubs + the gas-pass edits) is NON-WIDENING vs the v54 HEAD `20ca1f79` with zero orphan hunks, the freeze spine (freeze-completeness / index-binding / stamped-day determinism) + the discharged REVERT-FREE-CHAIN + the Phase-343 SOLVENCY-01 + the OPEN-E 4-protection re-attested intact; and the 3-skill genuine-PARALLEL adversarial sweep (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` run as concurrent background Task spawns from the orchestrator; `/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) probes the box-stamp freeze (manipulate score/boon/EV-cap in the reveal→open window; straddle a mid-day index advance), the liveness isolation (a poisoned sub bricking the day / the batch), and the two-path open (afking-vs-human shared-state hazard, double-open) with each charged probe dispositioned NEGATIVE-VERIFIED / SAFE_BY_DESIGN / FINDING_CANDIDATE.

  2. The findings deliverable is authored + all 29 v55.0 requirements re-attested (AUDIT-01) — `audit/FINDINGS-v55.0.md` (the full multi-section report, chmod 444) is authored capturing the delta-audit + the adversarial disposition + any findings, and all 29 v55.0 requirements (ARCH-01..04 · BOX-01..05 · FREEZE-01/02/03 · REVERT-01/02 · EVCAP-01 · CONSENT-01/02 · PLACE-01/02 · GAS-01/02/03 · TST-01..06 · AUDIT-01) are confirmed satisfied against the frozen v55.0 closure HEAD.

  3. The closure flip is applied (AUDIT-01) — the `MILESTONE_V55_AT_HEAD_<sha>` closure signal is emitted and propagated verbatim, and the atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) is applied; the closure plan is a single blocking USER closure-verdict + signal-format approval gate (`autonomous: false`) — the auto-advance is HELD at the closure boundary per `feedback_pause_at_contract_phase_boundaries`. (The separate v52 consolidated cross-model audit still folds the v55 surface into its cumulative sweep — an additional track, recorded in the v52 charge, NOT a substitute for this in-milestone close.)

**Plans**: TBD
**UI hint**: no

---

## Progress

**Execution Order:** Phases execute in numeric order: 348 → 349 → 350 → 351 → 352

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 348. SPEC — Design-Lock + Freeze Proof + Discharged-Invariant Carry + §4 Placement + Code-Size/GAS Inventories + Attestation | v55.0 | 2/7 | In Progress|  |
| 349. IMPL — The ONE Carefully-Sequenced Batched Contract Diff (code-size reclaim → fold + box redesign) | v55.0 | 0/? | Not started | - |
| 350. GAS — Behavior-Identical No-Cost Wins (box-ledger → warm Sub-stamp + staticcall → SLOAD + same-slot flushes) | v55.0 | 0/? | Not started | - |
| 351. TST — Freeze/Determinism + Revert-Free + EV-Cap + Two-Path + Set-Mutation + Non-Widening + Gas | v55.0 | 0/? | Not started | - |
| 352. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + FINDINGS-v55.0 + Closure | v55.0 | 0/? | Not started | - |

> **🔒 v55.0 CONTRACT-BOUNDARY HARD STOPS (TWO gates).** Phase 349 IMPL is the FIRST contract phase — the carefully-sequenced batched fold + box-redesign diff (code-size reclaim FIRST so the Game stays < 24,576 mid-flight, then the GameAfkingModule + storage append + box stamp/process-pass/open-pass + AfKing stubs + preserved slice-builder invariants + EV-cap-at-open + skip valve) is applied to `contracts/` and locally compiled (`forge build` clean) but HELD at the contract-commit boundary, NEVER committed without explicit user hand-review (`feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`). Phase 350 GAS is the SECOND contract phase — any further behavior-identical gas change (residual same-slot batching + extra gas-scavenger wins) rides its own batched USER-APPROVED diff at the same boundary. `ContractAddresses.sol` freely modifiable per `feedback_contractaddresses_policy`; tests + planning + docs AGENT-committable.

> **🔓 v55.0 AUDIT POSTURE — FULL CLOSE (internal sweep NOT deferred).** Like v54.0 (and unlike v50.0 + v51.0, whose internal sweeps were deferred → the v52 consolidated audit), **v55.0 runs its own internal 3-skill genuine-PARALLEL adversarial sweep + delta-audit + `audit/FINDINGS-v55.0.md` at TERMINAL (352, AUDIT-01)** — because the redesign touches the RNG-freeze + solvency spine and the freeze invariants must be adversarially probed in-milestone (the box-stamp freeze + the liveness isolation + the two-path open). The separate v52 consolidated cross-model audit folds the v55 surface into its cumulative sweep as an additional track (recorded in the v52 charge), not a substitute.

---

## Coverage (v55.0)

**29/29 v55.0 requirements mapped to exactly one phase — 0 orphaned, 0 duplicated.**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 348 SPEC | FREEZE-01, FREEZE-02, FREEZE-03, PLACE-01, ARCH-04 | 5 |
| 349 IMPL | ARCH-01, ARCH-02, ARCH-03, BOX-01, BOX-02, BOX-03, BOX-04, BOX-05, REVERT-01, REVERT-02, EVCAP-01, CONSENT-01, CONSENT-02, PLACE-02 | 14 |
| 350 GAS | GAS-01, GAS-02, GAS-03 | 3 |
| 351 TST | TST-01, TST-02, TST-03, TST-04, TST-05, TST-06 | 6 |
| 352 TERMINAL | AUDIT-01 | 1 |
| **Total** | | **29** |

**Per-category split (verification):**

| Category | Total | SPEC (348) | IMPL (349) | GAS (350) | TST (351) | TERMINAL (352) |
|----------|-------|------------|------------|-----------|-----------|----------------|
| ARCH | 4 | 1 (04) | 3 (01,02,03) | — | — | — |
| BOX | 5 | — | 5 (01-05) | — | — | — |
| FREEZE | 3 | 3 (01,02,03) | — | — | — | — |
| REVERT | 2 | — | 2 (01,02) | — | — | — |
| EVCAP | 1 | — | 1 (01) | — | — | — |
| CONSENT | 2 | — | 2 (01,02) | — | — | — |
| PLACE | 2 | 1 (01) | 1 (02) | — | — | — |
| GAS | 3 | — | — | 3 (01-03) | — | — |
| TST | 6 | — | — | — | 6 (01-06) | — |
| AUDIT | 1 | — | — | — | — | 1 (01) |
| **Total** | **29** | **5** | **14** | **3** | **6** | **1** |

**Center-of-gravity rationale (where a requirement spans design + impl + test):**

- **FREEZE-01 / FREEZE-02 / FREEZE-03** (the RNG/determinism security spine) → SPEC (348), where they are PROVEN on paper (freeze-completeness / pre-RNG index-binding / stamped-day determinism) as the design-gating attestations BEFORE the code is written. They are re-proven empirically at TST (351) by TST-01 — TST-01 does NOT re-count the FREEZE reqs, it is the test that re-proves the SPEC proofs.
- **PLACE-01** (the §4 placement DECISION — required-path vs separate-legs, on non-revert grounds) → SPEC (348). **PLACE-02** (the bounty reconciliation — work-scaled buy/process bounty + the post-RNG `OPEN_BATCH`/`OPEN_KNEE` open category + the `creditFlip` deferred payment) → IMPL (349), where it is BUILT.
- **ARCH-04** (the code-size reclaim PLAN, sequenced so the Game never breaches 24,576 mid-flight) → SPEC (348), where the measured reclaim plan + edit-order are produced; **ARCH-01 / ARCH-02 / ARCH-03** (the delivered state-game-resident append + the GameAfkingModule + the AfKing thin stubs) → IMPL (349), where they are BUILT (and the reclaim is delivered as part of the code-size-safe edit-order). Two distinct deliverables (the plan vs the build), one phase each — no double-counting.
- **The discharged REVERT-FREE-CHAIN + EV-cap invariants** are CARRIED at SPEC (348) as the locked invariant set (the proof's §5 obligations 1–4), but **REVERT-01 / REVERT-02 / EVCAP-01** are owned at IMPL (349) — they are migration-fidelity / build requirements (preserve `_resolveBuy` verbatim · the thin per-sub skip valve · the EV-cap-at-open RMW with the buy-time write bypassed), where the invariants become code. The SPEC carries them as design context; IMPL delivers them — no double-counting.
- **BOX-01..05 + CONSENT-01/02** (the box redesign + the OPEN-E/set-mutation carry-over) → IMPL (349) as part of the single batched diff. The SPEC concerns those decisions feed (the stamp shape, the two-path wiring, the OPEN-E confirmation) are folded into the SPEC's FREEZE/PLACE/attestation success criteria — they are not double-counted at SPEC; only the requirement's HOME (where it must be BUILT) is counted.
- **GAS-01 / GAS-02 / GAS-03** (the behavior-identical no-cost wins — box-ledger → warm Sub-stamp · staticcall → SLOAD · same-slot aggregate flushes) → GAS (350). Note: much of GAS-01/02 is structural to the IMPL relocation (the warm Sub-stamp write + the in-context subscriber set ARE the saving); the GAS phase confirms the savings (proven same-results in TST), lands the residual same-slot batching (GAS-03 SAFE-WITH-CONDITIONS), and gates any net contract change under the second USER-approved diff. The SPEC produces the GAS-opportunity inventory (folded into the SPEC attestation success criterion), but the wins LAND at the GAS phase.
- **TST-01..06** (the proofs) → TST (351). They do not "uncover" the IMPL/GAS reqs — they re-prove them empirically against the game-resident model (freeze/determinism, revert-free, EV-cap, two-path + set-mutation, NON-WIDENING regression, gas).
- **AUDIT-01** (the TERMINAL FULL close) → TERMINAL (352); it re-attests all 29 v55.0 requirements + runs the in-milestone delta-audit + 3-skill adversarial sweep + `audit/FINDINGS-v55.0.md` + the atomic 5-doc closure flip with the `MILESTONE_V55_AT_HEAD_<sha>` signal.

✓ All 29 v55.0 requirements mapped
✓ No orphaned requirements
✓ No duplicated requirements

**Note on §13e-style "uncovered" warnings:** as in the v44–v54 roadmaps, milestone-wide "uncovered" warnings are EXPECTED false alarms — each phase owns only its slice; AUDIT-01 re-attests the full 29-requirement set at the TERMINAL full close (352). The TST / TERMINAL phases do not "uncover" the IMPL/GAS reqs — they re-prove and re-attest them.

**Note on the internal sweep (NOT deferred):** like v54.0 (and unlike v50.0 + v51.0), v55.0 runs its own internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v55.0.md` at TERMINAL (352, AUDIT-01) — the RNG-freeze + solvency-spine touch makes deferral unacceptable. v55's regression bar is TST-05 (NON-WIDENING vs the v54 baseline `20ca1f79`); its security proof is the FREEZE-01/02/03 SPEC proofs (348) + the carried REVERT-FREE-CHAIN / SOLVENCY-01 foundations + TST-01..04/06 (351) + the TERMINAL adversarial sweep (352). The v52 consolidated cross-model audit still folds the v55 surface into its cumulative sweep as a separate, additional track.

---

<details>
<summary>⊘ v54.0 Game-Side Keeper-Funding Ledger + AfKing De-Custody + Dead-Code/Gas Sweep (Phases 343-347) — CLOSED-as-superseded 2026-05-30 (343 SPEC + 344 IMPL shipped `20ca1f79`; 345/346/347 dropped → folded into v55)</summary>

**Closure:** CLOSED-as-superseded 2026-05-30 — 343 SPEC + 344 IMPL shipped (HEAD `20ca1f79`, not pushed); **345 GAS / 346 TST / 347 TERMINAL DROPPED → folded into v55** (the AfKing-in-Game redesign relocates subscriber state into Game storage and rips out most of v54's cross-contract de-custody ledger machinery, so gas-sweeping / testing / auditing that soon-to-be-replaced surface is wasted). **No `MILESTONE_V54_AT_HEAD` ship signal** (the diff was never audited via 347). `20ca1f79` = the v55 baseline. Audit baseline → subject: v53 HEAD `83a84431` (the atomic `BatchBuy[]` batchPurchase) → v54 de-custody HEAD `20ca1f79`. Shape: SPEC → IMPL → (GAS+CLEANUP → TST → TERMINAL dropped → v55). The contract-boundary HARD STOP lived at the IMPL phase (344, the ONE batched ledger + de-custody + CLEANUP-02 diff, USER-approved, committed `d728263e`/`6d6aa424`/`20ca1f79`).

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 343. SPEC — Design-Lock + Solvency Proof + Dead-Code/Gas Inventories + Attestation | 5/5 | ✅ Complete (verdict PASS) | 2026-05-30 |
| 344. IMPL — The ONE Batched Contract Diff (ledger + de-custody + CLEANUP-02) | 5/5 | ✅ Complete (`d728263e`/`6d6aa424`/`20ca1f79`; `forge build` clean; not pushed) | 2026-05-30 |
| 345. GAS+CLEANUP — Further Behavior-Identical Gas Wins + Packing Eval + Broader Sweep | — | ⊘ DROPPED → v55 (gas levers re-target the game-resident surface) | 2026-05-30 |
| 346. TST — Deposit/Withdraw + Zero-Value Auto-Buy + Fresh-Rate + Solvency + Terminal-Merge + Non-Widening | — | ⊘ DROPPED → v55 (v55 TST covers the net surface) | 2026-05-30 |
| 347. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + FINDINGS-v54.0 + Closure | — | ⊘ DROPPED → v55 (v55 TERMINAL audits the net surface; no v54 ship signal) | 2026-05-30 |

**Coverage:** 34/34 v54.0 requirements mapped (343: 5 · 344: 18 · 345: 3 · 346: 7 · 347: 1); 0 orphaned, 0 duplicated. Per-category: LEDGER 5 · AUTOBUY 5 · DECUSTODY 4 · GAMEOVER 2 · SOLVENCY 3 · CLEANUP 3 · GAS 3 · TST 6 · BATCH 3. 343 SPEC PROVEN SOLVENCY-01/03 (the master invariant `balance + steth.balanceOf(this) >= claimablePool` inclusive of the keeper total); 344 IMPL shipped the game-side `keeperFunding` ledger (riding inside `claimablePool`, no new aggregate) + the non-payable `batchPurchase` (funder debit) + the AfKing de-custody + the repo-wide keeper→afking rename + the per-sender affiliate-cap removal. The 18 IMPL reqs (LEDGER/AUTOBUY/DECUSTODY/GAMEOVER + CLEANUP-02 + BATCH-02) shipped at `20ca1f79`; the 11 dropped-phase reqs (345 GAS-02/03 + CLEANUP-03 · 346 TST-01..06 + SOLVENCY-02 · 347 BATCH-03) fold into v55's net surface (the v55 GAS phase re-targets the game-resident levers; v55 TST/TERMINAL cover the net surface). Phase numbering continued 342 → 343. Full detail in `.planning/MILESTONES.md`. **v55 baseline = v54 de-custody HEAD `20ca1f79`.**

</details>

<details>
<summary>✅ v51.0 claimBingo — Color-Completion Claim (Phases 339-342) — CLOSED 2026-05-28 (minimal close at IMPL HEAD `c3e9d907`; 341 TST + 342 TERMINAL folded → v52)</summary>

**Closure:** MINIMAL CLOSE (USER decision 2026-05-28 at milestone start) — v51.0 closes at the 340 IMPL HEAD `c3e9d907` (USER-APPROVED). Phases 339 SPEC + 340 IMPL Complete; **Phase 341 TST + Phase 342 TERMINAL FOLDED → the v52 consolidated audit** (USER 2026-05-28: "move this along and fold tests and shit into v52"). The internal 3-skill genuine-PARALLEL adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` (and the full TST-01..06 suite) consolidate into the v52 audit (cumulative v50 + v51 surface). Audit baseline → subject: v50.0 closure HEAD `812abeee2719c32d6973771ad2a66187fae75b80` (minimal-close commit, no formal signal) → v51.0 closure HEAD `c3e9d907`. Shape: SPEC → IMPL → (TST → TERMINAL folded → v52). The contract-boundary HARD STOP lived at the single IMPL phase (340). **Note:** v53 — the AfKing keeper auto-buy mode/claimable fix `83a84431` — landed ad-hoc afterward and was the v54.0 baseline (superseded by v54.0, itself now superseded by v55.0).

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 339. SPEC — Design-Lock + Freeze Proof + Tier-Precedence + Attestation | 4/4 | Complete | 2026-05-28 |
| 340. IMPL — The ONE Batched Contract Diff (BINGO + REBAL + JACK) | 4/4 | Complete | 2026-05-29 |
| 341. TST — Per-Tier + Precedence + Revert/Dedup + Empty-Pool + Jackpot + Non-Widening | — | ⤴ Folded → v52 | 2026-05-28 |
| 342. TERMINAL — Minimal Close: Re-Attest + Closure Flip | — | ⤴ Folded → v52 | 2026-05-28 |

**Coverage:** 18/18 requirements mapped (339: 2 · 340: 9 · 341: 6 · 342: 1); 0 orphaned, 0 duplicated. Per-category: BINGO 6 · REBAL 1 · JACK 2 · TST 6 · BATCH 3. Phase numbering continued 338 → 339. BINGO-06 freeze-safety PROVEN at SPEC (the read-only `traitBurnTicket` consumer); tier-precedence (quadrant-first-before-symbol-first) locked at SPEC. Full detail in `.planning/MILESTONES.md`.

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

**Closure signal:** `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9` (subject FROZEN `4c9f9d9b`; 0 NEW findings [21 probes: 15 NEGATIVE-VERIFIED + 6 SAFE_BY_DESIGN]; OPEN-E 4-protection HOLD without `:676`; RNG-freeze intact; 666/42/17 by NAME). Audit baseline → subject: v48.0 closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` → v49.0 closure HEAD. ONE batched USER-APPROVED diff `63bc16ca` + the 331 GAS re-peg `4c9f9d9b`. Shape: SPEC → IMPL → GAS → TST → TERMINAL (the dedicated GAS phase because the break-even bounty re-peg was load-bearing — **the shape v54.0 + v55.0 mirror**). **PUSHED to origin/main 2026-05-27** (`0d9d321f`→`5803da95`, 274 commits — published the prior-unpushed v46/v47/v48/v49 contract history).

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
- **v46.0** Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal (316-320, shipped 2026-05-24; signal `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`). 6-phase FEATURE milestone with the dedicated GAS phase 319 (the break-even peg precedent v49.0 + v54.0 + v55.0 mirror); the in-tree `AfKing` keeper + the OPEN-E shared `fundingSource` shipped here. 1 MEDIUM finding H-CANCEL-SWAP-MISS DEFERRED→v47.0 (RESOLVED_AT_V47).
- **v45.0** VRF-Rotation Liveness Fix + Consolidate-Forward Delta Audit (309-314, shipped 2026-05-23, minimal close; signal `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`). The CATASTROPHE-class VRF-rotation orphan-index liveness fix; the `v45-vrf-freeze-invariant` north-star established here. **The minimal-close precedent v50.0 + v51.0 mirror (v54.0 + v55.0 do NOT — they run their own internal sweep).**
- **v44.0** sStonk Per-Day Redemption Refactor + Accounting Invariant Proof (304-308, shipped 2026-05-20; signal `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`). V-184 CATASTROPHE structurally closed; 13/13 invariants proven.

</details>

---
*Roadmap created: 2026-05-25 (v48.0)*
*v49.0 milestone added: 2026-05-26 (5 phases 329-333, SPEC→IMPL→GAS→TST→TERMINAL; 36 reqs / 7 categories) — SHIPPED 2026-05-27, archived to the collapsed block above.*
*v50.0 milestone added: 2026-05-27 (5 phases 334-338, SPEC→IMPL→TST→AUDIT-PROTOCOL→TERMINAL; 25 reqs / 7 categories) — CLOSED 2026-05-28 via minimal close (Phase 338 sweep + FINDINGS DEFERRED → v52); archived to the collapsed block above.*
*v51.0 milestone added: 2026-05-28 (4 phases 339-342, SPEC→IMPL→TST→TERMINAL; 18 reqs / 5 categories) — CLOSED 2026-05-28 via minimal close (341 TST + 342 TERMINAL folded → v52) at IMPL HEAD `c3e9d907`; archived to the collapsed block above.*
*v54.0 milestone added: 2026-05-30 (5 phases 343-347, SPEC→IMPL→GAS+CLEANUP→TST→TERMINAL; 34 reqs / 9 categories) — CLOSED-as-superseded 2026-05-30 (343 SPEC + 344 IMPL shipped `20ca1f79`; 345/346/347 dropped → folded into v55; no `MILESTONE_V54_AT_HEAD` signal); archived to the collapsed block above. `20ca1f79` = the v55 baseline.*
*v55.0 milestone added: 2026-05-30 (5 phases 348-352, SPEC→IMPL→GAS→TST→TERMINAL; 29 reqs / 10 categories: ARCH 4 · BOX 5 · FREEZE 3 · REVERT 2 · EVCAP 1 · CONSENT 2 · PLACE 2 · GAS 3 · TST 6 · AUDIT 1). Phase numbering continues from 347 (v54.0 ran 343-347) → 348. Established v49.0 + v54.0 audit-milestone shape WITH a dedicated GAS phase. **FULL close — the internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v55.0.md` run IN-MILESTONE at TERMINAL (352), NOT deferred** (the RNG-freeze + solvency-spine touch makes deferral unacceptable, like v54.0 and unlike v50.0/v51.0). TWO contract-boundary HARD STOPs (349 IMPL + 350 GAS). Baseline = v54 de-custody HEAD `20ca1f79`. Design-locked in `.planning/PLAN-V55-AFKING-IN-GAME-REDESIGN.md` (canonical = §10) + the discharged `.planning/PLAN-V55-REVERT-FREE-CHAIN-PROOF.md` (its §5 = the 4 LOCKED obligations).*
