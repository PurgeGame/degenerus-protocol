# Requirements — v62.0 Cross-Model-Led Blind-Spot Audit (Foundation-First)

**Defined:** 2026-06-07
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

> **THE METHOD — CROSS-MODEL-LED (BINDING; USER 2026-06-07, the defining premise of v62):** v62 is a *cross-model* audit, not another Claude-led one. We have run plenty of Claude-only audits and they glided past real bugs that only the convergent council surfaced in v60 (LIFECYCLE · RNGRETRY · RNGREUSE · gasceil · WHALE-01 were all external-surfaced or external-convergent; v58/v60 Claude passes found ~0 on their own surfaces). Therefore the convergent council (Gemini-3-pro + GPT-5.5, `bash .planning/audit-v52/cross-model/bin/council.sh --out-dir <dir> --label <name> <promptfile>`, ~5 min/area, parallel, **NO Claude-cap cost**) is the **PRIMARY FINDER in every audit-sweep area**. Each pass is pointed at THAT area's cleared/by-design spine with the charge *"here is what we believe is safe — BREAK it."* **Claude's role is to orchestrate the council, ADJUDICATE every convergent + divergent finding against the frozen source `b97a7a2e`, build the test/fuzz foundation, run the skeptic gate, and synthesize — NOT to be the primary bug-finder.** A no-finding verdict for ANY sweep area requires the council pass on record; Claude saturation alone is NOT evidence of "clear." Run the council on Claude-REFUTED findings too (the v60 LIFECYCLE lesson: a Claude-refuted item was externally-confirmed).
> **Baseline & subject:** the *baseline* (diff anchor) is the v61.0 closure HEAD `b97a7a2e` (NOT pushed). The audit *subject* is **locked at `c4d48008`** = `b97a7a2e` + the USER's committed forgiving-funding change (`feat(payments)`: overpay/stray ETH → withdrawable afking via `_creditAfkingValue`; combined-buy `msg.value` split; `receive()` → afking; 4 files incl. `DegenerusGameStorage.sol`). FOUNDATION (phase 380) is subject-agnostic; the subject SHA is re-confirmed at phase 382 SPEC before the council sweeps and frozen through them. Anchors below re-attested against `c4d48008` before each sweep.
> **Design-lock input:** `.planning/AUDIT-V62-PLAN.md` (the full STEP 0–5 plan). This milestone executes that plan; the REQs are its faithful decomposition.
> **Scope (USER-locked 2026-06-07):** the blind-spot-driven audit — attack the recurring bug SHAPES the v60 rotations kept surfacing (**compositions · parallel-path asymmetries · shared RNG-window state · write-only/dead state**), NOT another feature-by-feature rotation. **Ordering = FOUNDATION-FIRST:** the plan's STEP 5 (test-fix + invariant fuzz) runs BEFORE the STEP 0–4 council sweeps — you cannot adjudicate council findings while ~176 forge tests fail (you'd have no green oracle), and repairing the net re-validates v61 as a side effect.
> **Posture:** AUDIT milestone — the audit plans no NEW `contracts/*.sol` change of its own; the subject is locked before the sweeps (above), and small USER pre-audit deltas (parity/normalization tweaks like the combo funding-mix) fold into it. A council-surfaced, Claude-adjudicated, skeptic-passed finding routes to a fix under the standard contract gate (USER hand-review, batched, never pre-approved — `[[only-contract-commits-need-approval]]`); otherwise v62 ships document-only (`audit/FINDINGS-v62.0.md`). Test/fuzz/harness/doc work runs hands-off. Skeptic pass (structural-protection + 3-condition EV lens) before any CATASTROPHE/HIGH (`[[feedback_skeptic_pass_before_catastrophe]]`); git-status-verify any Write-capable subagent didn't mutate contracts (`[[feedback_verify_writecapable_agents]]` — prefer read-only audit agents); bounty-exploitability uses REAL prevailing gas, not the 0.5-gwei peg (`[[feedback_bounty_exploit_uses_real_gas_not_peg_ref]]`).
> **Expected shape:** FOUNDATION → FUZZ → PRIME → ASYM → COMPO → LOOP → PERIPH → TERMINAL. The five middle phases (PRIME/ASYM/COMPO/LOOP/PERIPH) are each council-LED. Phase numbering continues 379 → **380**. No research (audit of existing code; fully specified by the plan).
> **DON'T re-flag (v60 by-design rulings):** presale over-credit · lootbox open/claim TIMING · degenerette/WWXRP RTP>100 + WWXRP worthless · afking pass-eviction inclusive boundary · deity sybil self-grant + single-boon century-gate bypass · ticket dual-scale (100/400) · open-E operator-approval trust boundary · claimBingo no level guard · affiliate single-step claim. (Full list: the "By-design rulings" section of MEMORY.md.) Hand the council THIS list as the spine to break — convergent push-back on a by-design ruling is exactly the signal we're paying for.

---

## v62.0 Requirements

### FOUND — Foundation: test-fix & green baseline (STEP 5a, runs FIRST; Claude-built)
> Stop the manual whack-a-mole and give the council sweeps a green oracle to adjudicate against: repair the regression net so a green full-suite (not a hand-built PoC + baseline-diff) is the audit's safety floor. Claude-built infra (no council). ⚠ LANDMINE: `hardhat compile --force` regenerates `ContractAddresses.sol` → breaks the forge fixture; restore it (`[[gas-measure-worstcase-branch-not-typical-seed]]`). Prefer NOT hard-coding slots — read via named getters / `vm.store` with slots computed from `forge inspect <C> storageLayout`.

- [x] **FOUND-01** (FOUND): Repair the stale-fixture / storage-layout-drift forge failures (garbage-slot reads, signatures `188753807911851` / `171`, `runs:0` setup reverts, 0x11 underflows from shifted slots) — VRFCore/VRFStall/VrfRotation/Keeper/V56Sub + QueueDoubleBuffer / FarFutureIntegration / LootboxRngLifecycle / FarFutureSalvageSwap. Re-derive slots from the authoritative `forge inspect storageLayout` (the v61 PACK shift is region-dependent, NOT uniform −1 — `[[storage-packing-breaks-slot-hardcoded-tests]]`).
- [x] **FOUND-02** (FOUND): Refresh the event-schema-delta tests (LootBoxOpened `day` arg removed → stale topic-hash / arg-list parsing): `test/fuzz/{V55FreezeDeterminism,V55RevertFreeEvCap,V56FreezeSolvency}.t.sol`, `test/edge/LootboxAutoResolveRegression.test.js`, `test/unit/{LootboxWholeBurnieFloor,EventSurfaceUnification,LootboxAutoResolveSilentColdBust,LootboxWholeTicket}.test.js`.
- [x] **FOUND-03** (FOUND): Fix the v60-introduced whale/pass storage-collapse test debt (`2bee6d6f`): `test/edge/GameOver.test.js` + `test/unit/SecurityEconHardening.test.js` reference the REMOVED `deityPassPurchasedCount` / the dropped FIX-05 "refund clears count" → update to `deityPassPricePaid` + `min(pricePaid,20e)` refund semantics; the boon-ownership gate is now the HAS_DEITY_PASS bit.
- [x] **FOUND-04** (FOUND): Re-derive the slot + seed the unseeded `[invariant]` for `DegeneretteBetInvariant::invariant_solvencyUnderDegenerette` (the `SolvencyObligations` test helper reads `prizePoolPendingPacked` via a HARD-CODED slot-11 pinned at v55 → stale after v56–v61 drift). Contract solvency is fine — pure test-infra (don't re-flag as a contract finding).
- [x] **FOUND-05** (FOUND): Commit-or-remove the untracked gas-probe files (`test/fuzz/ActivityScoreStreakGas.t.sol`, `test/gas/AdvanceStageWorstCaseGas.t.sol`); delete obsolete/superseded SKIP-marked test files (KeeperNonBrick supersession cites); consolidate the per-fix PoCs.
- [x] **FOUND-06** (FOUND): Establish a GREEN full-suite baseline (forge + Hardhat, 0 failures) — so council-surfaced findings can be reproduced against a clean suite and future regressions are caught by "0 failures", not a by-name NON-WIDENING diff. Record the green baseline (supersedes `test/REGRESSION-BASELINE-v61.md`'s carried-red ledger).

### FUZZ — Invariant fuzz suite (STEP 5b; Claude-built + council property-review)
> Properties asserted across random reachable action sequences — exactly what catches compositions + asymmetries that point-tests miss, and the durable oracle the council's findings get checked against. Build on the GameSeeder etch pattern (`test/fuzz/PassBoxAutoOpenEnqueue.t.sol`, `test/gas/GameOverCompositionAdvanceGas.t.sol`).

- [x] **FUZZ-01** (FUZZ): SOLVENCY — `claimablePool == Σ claimableWinnings` (post-v61: `Σ(claimableWinnings + afkingFunding)` across the packed balance) AND `balance + stETH ≥ claimablePool`, holds across any action sequence. — DONE 381-01 (V61SolvencyAfpay + SolvencyActionHandler).
- [x] **FUZZ-02** (FUZZ): RNG-FREEZE — every VRF-consumed value is frozen [request → unlock] vs a player acting inside the window (`[[v45-vrf-freeze-invariant]]`; trace BACKWARD from each consumer). — DONE 381-02 (RngWindowFreeze.inv.t.sol + RngWindowFreezeHandler; enumerated in-window SLOAD set incl. non-VRF cursors; 256/128 GREEN, non-vacuous + falsifiable).
- [ ] **FUZZ-03** (FUZZ): GAS-CEILING — no `advanceGame` tx exceeds 16,777,216 gas across any reachable action sequence (TARGETS < 10M — `[[v56-batch-sizing-10m-target-16p7m-ceiling]]`).
- [ ] **FUZZ-04** (FUZZ): ENQUEUE — every persisted box (`lootboxEth`/`presaleBoxEth` with base != 0) is in `boxPlayers[index]` until opened (never held un-enqueued — the WHALE-01 invariant, as a fuzz property).
- [ ] **FUZZ-05** (FUZZ): POOL-CONSERVATION — `futurePrizePool ↔ nextPrizePool ↔ claimablePool` transfers conserve the total; no unbacked credit minted.
- [ ] **FUZZ-06** (XMODEL): Council reviews the invariant-property SET for COMPLETENESS — feed the council FUZZ-01..05 + the action-space and ask "what property is missing? what reachable sequence violates an unstated invariant?"; fold any convergent gap into the suite before the sweep phases consume it as their oracle.

### PRIME — STEP 0: v61's new code (council-LED; audit FIRST, highest bug density)
> New code is unaudited code. **Council-LED:** fire the convergent council at the v61 by-design spine — "afking-as-payment keeps solvency, the pack can't carry, the curse/smite only lower score and can't be griefed — BREAK it." Claude adjudicates each convergent/divergent finding against frozen `b97a7a2e`; a clear verdict needs the council pass on record. The spine the council attacks (also the surfaces Claude back-traces):

- [ ] **PRIME-01** (XMODEL): Fire the council at v61's new code (afking-as-payment + pack · cashout-curse · deity-smite) against ALL threat classes (RNG/freeze, solvency, gas-DoS-in-advance-chain) + COMPOSITION with every mechanic each touches; adjudicate every output vs frozen source; escalate convergent, triage divergent, re-attest or break each by-design claim.
- [ ] **PRIME-02** (SWEEP): afking-as-payment spine — the new `msg.value → claimable → afking` fund-flow vs SOLVENCY (`claimablePool == Σ(claimable + afking)` across every spend path); the msg.value path vs the existing `_settleShortfall` logic; the claimable/afking slot-packing vs truncation / a 127→128 cross-half carry / collision. **Includes the in-flight combo funding-mix parity tweak** (`purchaseWithPresaleBox` now `payable` + msg.value split mint/box via `_purchaseForWith`): does the `mintCost` recompute match the canonical price path (level vs level+1 by `jackpotPhaseFlag`, `TICKET_SCALE`), does the `msg.value − mintFresh` box remainder strand or double-count, and does it match the funding logic of every other ETH-consuming path (the ASYM lens — it removes an asymmetry, verify it adds none)?
- [ ] **PRIME-03** (SWEEP): cashout-curse spine — the state machine (SET on stale cashout, CURE on ≥1-ticket buy, the cap, permissionless `decurse`) + game-theory (economic-analyst / doug-polk lens) for an exploitable nudge, griefing vector, or cure-bypass.
- [ ] **PRIME-04** (SWEEP): deity-smite spine — the immunity check (a PARALLEL-PATH with afking eviction `validThroughLevel` — do they agree on "active afker"?); the curse-stack accounting; interaction with the decimator / jackpot / activity-score consumers.

### ASYM — STEP 1: parallel-path asymmetry sweep (council-LED; highest yield, WHALE-01 proved it)
> **Council-LED:** hand the council the sibling sets and the charge "these N implementations are claimed equivalent — find the one that diverges." Claude adjudicates the diffs against frozen source. The sibling families (the spine):

- [ ] **ASYM-01** (XMODEL): Fire the council at the parallel-path families below — "every box path enqueues; the pass types only differ where intended; the jackpot distributions share math; every RNG read is frozen; every pool mutation is paired — BREAK it"; adjudicate each convergent/divergent diff vs frozen source.
- [ ] **ASYM-02** (SWEEP): box-creation / auto-open — re-verify the INVARIANT *every persisted box is enqueued for auto-open OR resolved inline, never held*: mint (`MintModule:1189`), presale (`:1515`), afking-cover (`GameAfkingModule:985`), pass (`WhaleModule._recordLootboxEntry`, FIXED v60); inline-resolved degenerette/decimator/redemption via `resolveLootboxDirect`. Confirm NO v61 box path skips enqueue.
- [ ] **ASYM-03** (SWEEP): pass types (whale / lazy / deity, all in `WhaleModule`) — diff price calc, freeze delta (`frozenUntilLevel`/`levelCount` via `_applyWhalePassStats` / `_activate10LevelPass`), lootbox 10% (`_recordLootboxEntry`), presale-box credit, DGNRS reward, gate checks.
- [ ] **ASYM-04** (SWEEP): jackpot distribution (`JackpotModule`) — diff purchase-phase `payDailyJackpot(false)` vs jackpot-phase `payDailyJackpot(true)` vs game-over `runTerminalJackpot` (winner caps DAILY_ETH_MAX_WINNERS=305 / DAILY_COIN_MAX_WINNERS=50, the shared `_processDailyEth`/`_processBucket` math, the solo bucket + whale-pass handler) for an off-by-one or a missing cap.
- [ ] **ASYM-05** (SWEEP): RNG-consume sites — grep EVERY read of `rngWordByDay` / `rngWordCurrent` / `lootboxRngWordByIndex` / `_applyDailyRng`; for each, trace BACKWARD that the consumed value was unknown/frozen at input-commitment time. Enumerate ALL SLOADs in the window, not just VRF-derived seeds (`[[feedback_rng_window_storage_read_freshness]]`).
- [ ] **ASYM-06** (SWEEP): pool/credit updates — every `claimableWinnings` / `claimablePool` / `futurePrizePool` / `nextPrizePool` mutation is paired and conserved (the solvency spine).

### COMPO — STEP 2: advanceGame composition sweep (council-LED; direct gasceil follow-on)
> The isolated-stage harness is blind to fall-throughs by construction. **Council-LED:** "every `advanceGame` stage stays < 16.7M and no finished stage falls into another heavy stage in the same tx — BREAK it."

- [ ] **COMPO-01** (XMODEL): Fire the council at the advanceGame stage graph + the end-to-end gas profile — charge it to find a two-stages-in-one-tx composition (the v60 gasceil shape) or a stage-break that re-enters heavy work; adjudicate any candidate by reproducing it on the COMPO-02 / FUZZ-03 harness.
- [ ] **COMPO-02** (SWEEP): build an END-TO-END `advanceGame` gas harness (drive the REAL `advanceGame()`, GameSeeder etch) that fuzzes reachable states and asserts EVERY tx < 16.7M (targets < 10M). (Folds into FUZZ-03 as the durable form.)
- [ ] **COMPO-03** (SWEEP): enumerate EVERY stage-break in `advanceGame` (`DegenerusGameAdvanceModule.sol` STAGE_* returns/breaks); for each "finished" branch, ask what runs NEXT in the SAME tx — re-verify the known-checked fall-throughs post-v61 (game-over ticket-drain→terminal-jackpot FIXED `6d2c8d0c`; entropy→ticket BOUNDED) + the subscriber / jackpot / transition / gap-backfill break points.

### LOOP — STEP 3: VRF-callback / gas-bounded-loop sweep (council-LED; DOMINANT threat class)
> Every uncapped loop reachable in a gas-limited context (VRF `rawFulfillRandomWords`, the advanceGame chain). **Council-LED:** "every loop in a gas-limited context is bounded by a numeric cap, not an unenforced invariant — BREAK it."

- [ ] **LOOP-01** (XMODEL): Fire the council at the loop inventory below + any v61-introduced loop — charge it to find an unbounded iteration or a bound that rests on an UNENFORCED invariant (the shape the orphan-index loop was); adjudicate vs frozen source + the COMPO gas harness.
- [ ] **LOOP-02** (SWEEP): re-verify the CLOSED/bounded loops stay bounded — `_backfillOrphanedLootboxIndices` (max 1, gated on `rngRequestTime==0`), `_backfillGapDays` (cap 120), deity-refund (cap DEITY_PASS_MAX_TOTAL=32), subscriber stage (SUBSCRIBER_CAP=1000, weight-chunked).
- [ ] **LOOP-03** (SWEEP): HUNT any NEW unbounded loop (especially in v61 code) + any loop whose bound is an UNENFORCED invariant rather than a numeric cap.

### PERIPH — STEP 4: peripheral contracts (council-LED; lighter rotation coverage than the core)
> The v60 rotation was game-module-centric. **Council-LED:** point the council at the surrounding contracts + the cross-contract seams — "the peripherals are clear, the delegatecall selectors match, the external token calls aren't reentrant — BREAK it."

- [ ] **PERIPH-01** (XMODEL): Fire the council at the peripheral contracts + cross-contract call seams (delegatecall interface/selector correctness, reentrancy on external token calls); adjudicate each finding vs frozen source.
- [ ] **PERIPH-02** (SWEEP): `DegenerusVault` + `StakedDegenerusStonk` (redemption — re-verify the C-2 stETH-strand fix `0f4e2a54` held; the redemption reserve + per-day accounting).
- [ ] **PERIPH-03** (SWEEP): `DegenerusAffiliate` (claim attribution — the single-step direct-mint claim, `[[affiliate-claim-single-step-direct-mint]]`).
- [ ] **PERIPH-04** (SWEEP): `BurnieCoin` + `BurnieCoinflip` (mint/burn authority, the flip-credit RTP, the curse/decurse/smite burn sinks).
- [ ] **PERIPH-05** (SWEEP): `DegenerusStonk`/`GNRUS` + `DegenerusDeityPass` (soulbound ERC721, the smite `ownerOf` gate) + `DegenerusAdmin` (VRF wiring / coordinator-swap governance).
- [ ] **PERIPH-06** (SWEEP): cross-contract call seams — delegatecall interface/selector correctness (`IDegenerusGame` et al. must match the impls) + reentrancy on the external token calls.

### AUDIT — terminal close
- [ ] **AUDIT-01** (TERMINAL): re-run the council on ALL Claude-REFUTED findings from the sweep phases (the v60 LIFECYCLE lesson); consolidate + dedupe every area's council output; skeptic pass (structural-protection + 3-condition EV lens) before any CATASTROPHE/HIGH; git-status-verify no Write-capable subagent mutated `contracts`.
- [ ] **AUDIT-02** (TERMINAL): `audit/FINDINGS-v62.0.md` authored (chmod 444) recording each area's council pass + verdict + the convergent/divergent/by-design adjudication + the atomic closure flip with the `MILESTONE_V62_AT_HEAD_<sha>` signal; any CONFIRMED finding routed to a gated fix (USER hand-review, batched) else document-only; re-attest all v62.0 requirements; KNOWN-ISSUES.md byte-unmodified unless a genuine new finding is recorded.

---

## Future Requirements (deferred)

- The **v52 consolidated cross-model audit** — the cumulative v50/v51 contract surface + the `FINDINGS-v50.0.md` / `FINDINGS-v51.0.md` backfill — a SEPARATE future track (carried forward; see STATE.md "v50.0 + v51.0 AUDIT DEBT").
- A **finding-driven remediation milestone (v63+)** — only if v62's council surfaces a CRIT/HIGH needing more than a point-fix under the contract gate.

## Out of Scope (v62.0)

| Item | Reason |
|------|--------|
| Audit-initiated `contracts/*.sol` change | The audit plans none of its own; a finding routes to a gated fix. (USER pre-audit deltas — e.g. the combo funding-mix parity tweak — DO fold into the subject; they are not audit-initiated changes.) |
| Claude-only sweep as the primary finder | The whole premise — Claude-only has missed what the council found; every sweep area is council-LED with Claude adjudicating. |
| New features / feature rotation | v62 attacks bug SHAPES, not features — the explicit anti-pattern this plan exists to avoid. |
| Pushing v61/v62 to origin | A separate USER step (manual diff review before push — `[[feedback_manual_review_before_push]]`). |
| Re-flagging the v60 by-design rulings | USER-locked dispositions (listed in the header) — handed to the council AS the spine to break, but not pre-counted as findings. |
| The v52 v50/v51 backfill | Separate future cross-model track (deferred above), not folded into v62. |

## Traceability

Each REQ maps to exactly one phase; 100% coverage. **Every council/XMODEL REQ is the load-bearing deliverable of its phase** — "convergent council fired at the area spine + adjudicated against frozen source" is an explicit success criterion of each of phases 382–386 (and the FUZZ-property review of 381). Roadmapped into `.planning/ROADMAP.md` (v62.0 section).

**Phase structure (foundation-first, council-led sweeps):**

| Phase | Area | REQ-IDs |
|-------|------|---------|
| 380 | FOUNDATION (test-fix & green baseline; Claude-built) | FOUND-01..06 |
| 381 | INVARIANT FUZZ (Claude-built + council property-review) | FUZZ-01..06 |
| 382 | PRIME — v61 new-code (council-LED) | PRIME-01..04 |
| 383 | ASYMMETRY SWEEP (council-LED) | ASYM-01..06 |
| 384 | advanceGame COMPOSITION + e2e gas harness (council-LED) | COMPO-01..03 |
| 385 | VRF / GAS-BOUNDED-LOOP SWEEP (council-LED) | LOOP-01..03 |
| 386 | PERIPHERAL CONTRACTS (council-LED) | PERIPH-01..06 |
| 387 | TERMINAL (council-on-refuted + close + FINDINGS-v62.0) | AUDIT-01..02 |

**Coverage:**
- v62.0 requirements: 38 total (FOUND 6 · FUZZ 6 · PRIME 4 · ASYM 6 · COMPO 3 · LOOP 3 · PERIPH 6 · AUDIT 2)
- Council/XMODEL deliverables: FUZZ-06 + PRIME-01 + ASYM-01 + COMPO-01 + LOOP-01 + PERIPH-01 + AUDIT-01 (council-on-refuted) = the cross-model spine, one per sweep area + fuzz + terminal
- Mapped to phases: 38 (proposed)
- Unmapped: 0 ✓

---
*Requirements defined: 2026-06-07*
*Last updated: 2026-06-07 after initial definition (v62.0 milestone start; cross-model-led per USER)*
