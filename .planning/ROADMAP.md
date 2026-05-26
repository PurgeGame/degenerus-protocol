# Roadmap: Degenerus Protocol — Audit Repository

**Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.

## Milestones

- ✅ **v44.0 sStonk Per-Day Redemption Refactor** — Phases 304-308 (shipped 2026-05-20)
- ✅ **v45.0 VRF-Rotation Liveness Fix** — Phases 309-314 (shipped 2026-05-23, minimal close)
- ✅ **v46.0 Do-Work Crank + AfKing Subscription** — Phases 316-320 (shipped 2026-05-24)
- ✅ **v47.0 Rake-Free Presale + Lootbox-Boon Unification** — Phases 321-324 (shipped 2026-05-25)
- ✅ **v48.0 sDGNRS Salvage Swap + v47 Deferred Fixes + Keeper/Pool/Tombstone/Hero** — Phases 325-328 (shipped 2026-05-26)
- 🚧 **v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep** — Phases 329-333 (in progress)

---

## 🚧 v49.0 Unified Keeper Router + Bounty Recalibration + AfKing Keeper Sweep (In Progress)

**Milestone:** v49.0 (started 2026-05-26)
**Defined:** 2026-05-26
**Audit baseline → subject:** v48.0 closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` → v49.0 closure HEAD. Subject = the single batched USER-APPROVED `contracts/*.sol` diff (the `doWork` router + the `advanceGame`-bounty rework + the break-even bounty re-peg + the folded no-cost micro-opts).
**Scope source:** `.planning/REQUIREMENTS.md` (31 v49.0 REQ-IDs across 7 categories: ROUTER 7 · ADV 5 · GAS 6 · GASOPT 2 · TST 5 · SWEEP 3 · BATCH 3; GAS-06 + TST-05 added at the Phase 329 discussion for the `autoResolve`→`degeneretteResolve` rename + flat ~1-BURNIE re-peg) + `.planning/research/SUMMARY.md` (HIGH confidence; phase shape + the 4 structural invariants validated) + the milestone discussion (2026-05-26). All decisions LOCKED; **no phase needs a research sub-phase** (attestation + design-finalization + established-methodology only).

> **Cross-cutting rule (every requirement):** every cited `file:line` + the bounty/gas math MUST be re-attested against the **v48.0-closure HEAD `0cc5d10f`** before any patch (no "by construction" / "single fn reaches all paths" claim survives un-checked — the `DegenerusGame` mint/jackpot inline-duplication precedent; `feedback_verify_call_graph_against_source`). Security / RNG-freeze floor over gas (`feedback_security_over_gas` + `v45-vrf-freeze-invariant`). Pre-launch redeploy-fresh (storage-layout break fine, no migration; `feedback_frozen_contracts_no_future_proofing`).

> **Posture:** **ONE batched USER-APPROVED `contracts/*.sol` diff** for the whole milestone's contract surface — the router (`AfKing.sol`), the advance-bounty rework (`DegenerusGameAdvanceModule.sol`), the Game wrapper + discovery views (`DegenerusGame.sol`), the interface updates (`IDegenerusGame.sol` + `IDegenerusGameModules.sol`), the break-even re-peg, and the two folded no-cost micro-opts all land in a single reconciled diff at IMPL with a **HARD STOP at the contract-commit boundary** (applied + locally compiled/tested, never committed without explicit user hand-review — `feedback_batch_contract_approval` + `feedback_never_preapprove_contracts` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`; `ContractAddresses.sol` freely modifiable per `feedback_contractaddresses_policy`). The break-even peg constants land under a SECOND USER-approved gate at the GAS phase (the v46 Phase 319 CR-01 precedent — peg derived from worst-case MARGINAL gas, never a single-item total). Tests + planning + docs AGENT-committable.

> **Phase numbering** continues from the previous milestone — v48.0 ended at Phase 328, so **v49.0 starts at Phase 329.** Not reset to 1.

> **Milestone shape** matches the established v46.0 FEATURE-with-GAS pattern (the dedicated GAS phase between IMPL and TST exists because the break-even bounty re-peg is load-bearing — peg constants are a function of measured worst-case marginal gas and cannot be a guess): **SPEC design-lock → single batched IMPL contract diff → GAS calibration → TST proof → TERMINAL delta-audit + 3-skill adversarial sweep + closure flip.**

> **Bounty stays minted FLIP CREDIT** from the finite-pool / self-exclude / ETH-work-gate pattern (LOCKED; the liquid-BURNIE / affiliate-revenue funding overlay is OUT, dropped at v48). The stall multiplier (1/2/4/6) is kept as the sole liveness lever; the base bounty is calibrated below gas at normal prices so only the stall-escalated reward pulls in keepers for lagging work.

### Phases

- [x] **Phase 329: SPEC — Design-Lock + Call-Graph Attestation + 4 Structural Invariants** - Lock the 4 structural invariants, settle the shared signatures (`advanceGame` return shape, `doWork` signature, the O(1) discovery views), decide ROUTER-07 reentrancy disposition + GAS-03 single day-start epoch, and grep-attest every cited `file:line` vs the v48.0 HEAD `0cc5d10f` — paper-only, zero `contracts/*.sol`.
- [ ] **Phase 330: IMPL — The ONE Batched Contract Diff (router + advance-rework + micro-opts)** - Apply the single reconciled diff in producer-before-consumer order (AdvanceModule bounty-removal + return → Game wrapper/views → interfaces → AfKing router/`_autoBuy`/micro-opts); HARD STOP at the contract-commit boundary for explicit user hand-review.
- [ ] **Phase 331: GAS — Worst-Case Marginal Derivation + Break-Even @0.5gwei Peg Calibration** - Derive the worst-case-first per-category marginal gas + router overhead, calibrate the break-even peg constants (per-item marginal, never a per-call total — the CR-01 rule), size the stall ceiling, prove the WR-01-style no-self-crank round-trip, and rename `autoResolve`→`degeneretteResolve` + re-peg it to a flat ~1-BURNIE "lose" (GAS-06, ≥3-resolution pay-gate; a lose vs real tx gas) — peg constants land under a USER-approved gate.
- [ ] **Phase 332: TST — Freeze Fuzz + One-Category + Reward-Routing + Non-Widening Regression** - Prove the router advance-consume reads only frozen state mid-tx, the one-rewarded-category-per-tx invariant (no bounty-stacking) + reentrancy double-pay regression, the advance unrewarded-standalone/rewarded-via-router behavior + GASOPT same-results, the `degeneretteResolve` rename + re-peg (flat ~1-BURNIE/≥3-pay-gate/revert-on-no-work/WWXRP-excluded/same-results, TST-05), and a NON-WIDENING full-suite regression vs the v48.0 baseline.
- [ ] **Phase 333: TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure** - NON-WIDENING delta-audit vs the v48.0 baseline `0cc5d10f`, run the 3-skill genuine-PARALLEL adversarial sweep on the unified keeper surface, author `audit/FINDINGS-v49.0.md`, and flip the closure signal `MILESTONE_V49_AT_HEAD_<sha>`.

---

## Phase Details

### Phase 329: SPEC — Design-Lock + Call-Graph Attestation + 4 Structural Invariants
**Goal**: The 4 load-bearing structural invariants are locked in writing, every shared signature (the `advanceGame` return shape, the `doWork(maxCount)` signature, the O(1) discovery views) is settled, the ROUTER-07 reentrancy disposition (GAS-03 single day-start epoch + the OPEN-C guard-vs-CEI decision) is resolved, and every cited `file:line` + the bounty/gas math is grep-verified against the v48.0-closure HEAD `0cc5d10f` — so the IMPL phase authors a fully reconciled diff with zero "by construction" assumptions and the VRF-freeze invariant is proven to survive the new router composition on paper before any code is written.
**Depends on**: Nothing (first v49.0 phase; consumes the v48.0 closure HEAD `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` as the frozen audit baseline)
**Requirements**: BATCH-01, ROUTER-07, ADV-04, GAS-03
**Success Criteria** (what must be TRUE):
  1. The 4 structural invariants are locked in writing (BATCH-01): (a) **one-category structural early-return** — `doWork` early-returns after the first rewarded category so advance/open/buy bounties can never stack in one tx (a code invariant, not a comment); (b) **frozen advance-consume** — the router's advance-consume reads only FROZEN VRF-window state even when fired in the same tx as `autoOpen`/`autoBuy`, with the player-controllable `totalFlipReversals` nudge (`AdvanceModule.sol` ~`:1838-1844`) proven frozen between rng-request and unlock (ADV-04; `v45-vrf-freeze-invariant` re-attested); (c) **guaranteed free-fallback caller** — at least one structurally-guaranteed unrewarded `advanceGame()` caller path is identified (protocol-owned VAULT/sDGNRS subs, any player with a pending jackpot) so re-homing the bounty does not create a single-point liveness risk; (d) **single day-start epoch** (GAS-03) — the differing `AfKing` `_currentDay()` `(ts-82620)/1days` vs `AdvanceModule` `(day-1+DEPLOY_DAY_BOUNDARY)*1days+82620` conventions are collapsed to one unified day-start epoch so the stall multiplier is never recomputed in a money path.
  2. The shared signatures are settled in writing so no downstream file ships an intermediate broken state: the `advanceGame` return shape (design 1 — `advanceGame` returns `(uint8 mult, bool rewardable)` so the stall math stays single-source-of-truth in `AdvanceModule` and the router never recomputes it, covering BOTH the new-day advance AND the mid-day partial-drain site `AdvanceModule.sol:225` per ADV-05), the `doWork(maxCount)` signature + its no-work signal (ROUTER-06, consistent with the existing no-buy anti-spam revert; exact form decided here), and the O(1) discovery views (`advanceDue()` covering both new-day `currentDayView() != dailyIdx` AND partial-drain `day == dailyIdx but tickets-not-fully-processed`, `boxesPending()`, buys-pending via AfKing-local cursor reads — no unbounded scans, ROUTER-04).
  3. The ROUTER-07 reentrancy disposition is decided and recorded (OPEN-C): a `nonReentrant` guard on `doWork` (the default per the security floor — cheap insurance against the new multi-boundary router→game→`creditFlip` composition surface) OR a proven composed-CEI argument; the v48 KEEP-04 VAULT registered-affiliate-code wiring is confirmed valid at v49 HEAD so the `autoBuy` affiliate-code passthrough survives the `_autoBuy` internal refactor (ROUTER-05).
  4. Every cited `file:line` across the SUMMARY + the milestone scope is grep-verified against the v48.0-closure HEAD `0cc5d10f` and any drift is corrected in the SPEC (no "by construction" survives un-checked) — including the 3 advance-bounty `creditFlip` sites `AdvanceModule.sol:189/225/468` to be deleted (ADV-01), `ADVANCE_BOUNTY_ETH = 0.005 ether` `:147`, the stall ladder `:238-255`, `AfKing.sol` `BOUNTY_ETH_TARGET` + `creditFlip` `:846` + cursor + the CEI invariant `:99-106`, and the `DegenerusGame.sol` `advanceGame` wrapper `:275` + the gas-peg constants `:1539-1546` — confirming the producer-before-consumer edit-order map for IMPL.
**Plans**: 3 plans (2 waves)
- [x] 329-01-PLAN.md — ATTEST the router + advance surface (AfKing CEI/cursor/bounty/epoch + AdvanceModule 3 creditFlip sites/stall/totalFlipReversals/30-min-bypass/death-clock + DegenerusGame wrapper/views + GASOPT-01/02) incl. the per-leg no-untrusted-ETH-send (D-01a/ROUTER-07), the dual-epoch (D-03/GAS-03), the totalFlipReversals freeze (ADV-04), and the invariant-(c) fallback callers (D-04) → `329-ATTEST-ROUTER-ADVANCE.md` [Wave 1]
- [x] 329-02-PLAN.md — ATTEST the D-05 `autoResolve`→`degeneretteResolve` rename + flat ~1-BURNIE re-peg: rename surface (D-05a), the D-05f losing-bet-liveness grep-verification (load-bearing), the D-05c real-gas exploitability basis, the D-05b flat-shape/≥3-gate feasibility, and the architectural router-non-foldability → `329-ATTEST-DEGENERETTE-RESOLVE.md` [Wave 1]
- [x] 329-03-PLAN.md — Reconcile into `329-SPEC.md`: §0 attestation roll-up / §1 settled shared signatures (advanceGame return / doWork+NoWork / O(1) discovery views) / §2 the 4 structural invariants + the ROUTER-07/GAS-03 dispositions + the D-05 design-lock / §3 per-item IMPL blueprint + producer-before-consumer edit-order map [Wave 2, depends on 329-01 + 329-02]
**UI hint**: no

### Phase 330: IMPL — The ONE Batched Contract Diff (router + advance-rework + micro-opts)
**Goal**: The unified keeper router lands as a single reconciled `contracts/*.sol` diff — `AfKing.doWork(maxCount)` routes to exactly ONE category per call (advance-leg → `autoOpen` → `autoBuy`) with a structural early-return, `autoBuy` is refactored to internal `_autoBuy`, the 3 `advanceGame` bounty `creditFlip` sites are deleted and `advanceGame` returns `(uint8 mult, bool rewardable)`, standalone `advanceGame()` stays an unrewarded liveness fallback, the break-even peg targets are wired as SPEC placeholders (calibrated at GAS), and the two no-cost micro-opts (MintModule nested-mapping pointer + AfKing claimable-hoist) ride in the same diff — applied + locally compiled/tested, then HELD at the contract-commit boundary for explicit user hand-review.
**Depends on**: Phase 329 (the SPEC must lock the 4 invariants + settle the shared signatures + decide the reentrancy + single-epoch disposition first)
**Requirements**: ROUTER-01, ROUTER-02, ROUTER-03, ROUTER-04, ROUTER-05, ROUTER-06, ADV-01, ADV-02, ADV-03, ADV-05, GASOPT-01, GASOPT-02, BATCH-02
**Success Criteria** (what must be TRUE):
  1. The unified `doWork(maxCount)` router ships on `AfKing.sol` (ROUTER-01/02/03/04/06) — a single entrypoint performing exactly ONE keeper category per call, routing by priority advance-leg (new-day advance OR mid-day partial-drain ticket processing) → `autoOpen` → `autoBuy`, with the one-rewarded-category rule enforced as a STRUCTURAL early-return (advance/open/buy bounties can never stack in one tx), O(1) on-chain work-discovery predicates (advance-due incl. mid-day partial-drain / boxes-pending / buys-pending — no unbounded scans), and a clean "no work done" signal consistent with the existing no-buy anti-spam revert (never pays a bounty for no work).
  2. `autoBuy` is refactored to internal `_autoBuy` + `autoResolve` is excluded (ROUTER-05) — `autoBuy` becomes an internal `_autoBuy(maxCount)` call with a thin behavior-identical external wrapper so the money-moving path stays internal (no new cross-contract money edge); `autoResolve` is excluded from the router and stays a separate call (RENAMED to `degeneretteResolve` + its bounty re-pegged per GAS-06, calibrated at Phase 331; the router-fold is architecturally blocked by the caller-supplied `(players[], betIds[])` requirement); the v48 KEEP-04 VAULT registered-affiliate-code passthrough survives the refactor.
  3. The advanceGame bounty is re-homed (ADV-01/02/03/05) — the 3 advance-bounty `creditFlip(caller,…)` sites in `DegenerusGameAdvanceModule.sol` (`:189`/`:225`/`:468`) are removed so standalone `advanceGame()` pays no bounty; `advanceGame` returns the stall multiplier + a rewardable flag (design 1) so the router pays the re-homed bounty from the multiplier's canonical day-epoch home (no recompute in a money path); standalone `advanceGame()` stays fully functional as an unrewarded liveness fallback with the SPEC-identified guaranteed free-fallback caller path intact; and mid-day partial-drain ticket processing (`day == dailyIdx` but tickets not fully processed) is router-rewardable advance-leg work covered by the rewardable flag.
  4. The two no-cost gas micro-opts ride in the same diff (GASOPT-01/02) — `DegenerusGameMintModule.sol` hoists `mapping(address=>uint40) storage owedMap = ticketsOwedPacked[rk]` in both `processTicketBatch` (`:671`) and the resolve/future loop (`:398`) (`rk` loop-invariant, behavior-identical), and `AfKing.autoBuy` hoists `IGame.claimableWinningsOf(player)` to one call per iteration (today `:691` + `:722`), preserving the existing laziness (only when `reinvestPct>0 || FLAG_DRAIN_FIRST`, behavior-identical) — both gas-only, same-results (proven at TST).
  5. The diff is reconciled per the SPEC's settled shared signatures and is HELD at the contract-commit boundary (BATCH-02) — authored in producer-before-consumer order (AdvanceModule bounty-removal + return → Game wrapper/views → interfaces → AfKing router/`_autoBuy`/re-peg-placeholders/micro-opts) so no intermediate state ever ships where advancing is unrewarded, applied to `contracts/` and locally compiling/tested (`ContractAddresses.sol` freely modifiable), but NOT committed without explicit user hand-review of the single batched diff; CEI on every leg (`creditFlip` last) and no multiplier duplication.
**Plans**: TBD
**UI hint**: no

### Phase 331: GAS — Worst-Case Marginal Derivation + Break-Even @0.5gwei Peg Calibration
**Goal**: The break-even bounty peg is calibrated from measured worst-case marginal gas (not a guess) — the worst-case-first per-category marginal gas (`autoBuy`/`autoOpen`/`autoResolve`) + the router overhead is derived theoretically then measured, the keeper bounties are re-pegged to break-even at 0.5 gwei in BURNIE using the per-item MARGINAL (never a per-call total — the CR-01 self-crank-faucet rule), the stall multiplier (1/2/4/6) is kept with any ceiling extension added ABOVE the 2h tier and capped against the finite faucet pool, and a WR-01-style round-trip guard proves no positive-EV self-crank loop under the unified router — the landed peg constants under a USER-approved gate (the v46 Phase 319 precedent).
**Depends on**: Phase 330 (the peg cannot be set before worst-case marginal gas is measured against the applied diff; tests must exercise calibrated constants, not placeholders)
**Requirements**: GAS-01, GAS-02, GAS-04, GAS-05, GAS-06
**Success Criteria** (what must be TRUE):
  1. The worst-case-first marginal gas is derived per keeper category + router overhead (GAS-01) — the theoretical worst case is derived FIRST (per `feedback_gas_worst_case`), then measured via the established `test/gas/*WorstCaseGas.t.sol` harness idiom (a new `RouterWorstCaseGas.t.sol`, Foundry `--isolate` for `vm.snapshotGas` section snapshots), amortized per-item over N≥32 items (NOT a single-item total, NOT `forge test --gas-report` numbers as the peg).
  2. All keeper bounties are re-pegged to break-even at 0.5 gwei BURNIE-denominated using the per-item MARGINAL (GAS-02) — the CR-01 self-crank-faucet rule holds (the box peg is the per-box marginal, never a single-box/single-call total), conversion math is confirmed level-invariant, and the constants land under a USER-approved gate (the v46 Phase 319 `e4014f91`/`795e679d` precedent).
  3. The stall multiplier (1/2/4/6) is kept + any ceiling extension is faucet-bounded (GAS-04) — the existing thresholds are never lowered, any extreme-stall ceiling extension is added ABOVE the 2h tier, the extension value (if any) is decided from the GAS data (whether 6× covers stressed mainnet gas at a plausible deep stall) and is capped against the finite faucet pool.
  4. A WR-01-style round-trip guard proves no positive-EV self-crank loop under the unified router (GAS-05) — the faucet bound holds, the self-exclude + ETH-work-gate are intact, and a Sybil/self-crank round-trip is proven ≤ 0 EV under the new router composition (the box-peg multi-box round-trip regression-guard precedent extended to the router).
  5. `autoResolve` is renamed to `degeneretteResolve` and its bounty re-pegged to a flat ~1-BURNIE "lose" (GAS-06) — restructured from per-item break-even to ONE flat literal ~1 BURNIE `creditFlip` per tx (count-independent) gated at ≥3 successfully-resolved NON-WWXRP bets (revert on zero work; 1–2 resolved → unpaid, lean = do-not-revert so a trailing tail isn't stranded). Anti-exploit basis (corrected — NOT the 0.5-gwei peg ref): the keeper pays REAL tx gas every call while ~1 BURNIE illiquid flip-credit is ≤ `mintPrice/1000` ETH (≤0.00024 ETH) → every qualifying tx is a net loss at any realistic gas price; the ≥3 gate widens the margin. WWXRP stays excluded (AUTO-04, the ≥3 count is non-WWXRP only), and AUTO-02 probe + per-item isolation + self-resolve-allowed (REW-04) are preserved; stays a SEPARATE call (the rename + bounty code rides the BATCH-02 diff, the exact constant confirmed sub-real-gas here — NOT a blocker). The SPEC (D-05f) verifies no invariant requires losing-bet resolution before the break-even incentive is dropped.
**Plans**: TBD
**UI hint**: no

### Phase 332: TST — Freeze Fuzz + One-Category + Reward-Routing + Non-Widening Regression
**Goal**: The new router composition is proven behaviorally correct empirically — the router advance-consume reads only frozen state mid-tx (the `totalFlipReversals` class), no single tx earns more than one category's bounty + the router→game→`creditFlip` path cannot double-pay via reentrancy, `advanceGame` is unrewarded standalone but rewarded via `doWork` with the multiplier honored + the GASOPT micro-opts produce byte-identical results, and the full suite is NON-WIDENING vs the v48.0 baseline — restoring a clean v49.0 regression baseline against the GAS-calibrated constants.
**Depends on**: Phase 331 (tests exercise the GAS-calibrated peg constants, not the IMPL placeholders)
**Requirements**: TST-01, TST-02, TST-03, TST-04, TST-05
**Success Criteria** (what must be TRUE):
  1. The freeze-invariant fuzz holds (TST-01) — extending the v43 `RngLockDeterminism` harness, the router advance-consume is proven to read only frozen state mid-tx (perturb `totalFlipReversals` + every in-window SLOAD between rng-request and unlock, assert byte-identical consumed VRF-derived output) even when fired in the same tx as `autoBuy`/`autoOpen` — the `v45-vrf-freeze-invariant` is preserved under the new router composition.
  2. The one-category invariant + reentrancy regression hold (TST-02) — a one-rewarded-category-per-tx assertion proves no single tx earns more than one category's bounty (no advance+open+buy bounty-stacking), and a router→game→`creditFlip` reentrancy double-pay regression confirms the disposition decided at SPEC (guard or composed-CEI) blocks any double-pay.
  3. The reward-routing + GASOPT same-results hold (TST-03) — `advanceGame` is proven UNREWARDED when called standalone via `game.advanceGame()` and REWARDED when driven via `doWork` (the multiplier honored, the mid-day partial-drain leg rewarded), and the two GASOPT micro-opts (MintModule pointer + AfKing claimable-hoist) are proven same-results (gas-only, byte-identical behavior).
  4. The full-suite regression is NON-WIDENING vs the v48.0 baseline (TST-04) — net-zero new regression (every red named in the VRF/baseline + any enumerated-deferred set), the standalone `advanceGame` still drives the full daily tick (death-clock latches as the tertiary backstop), and a clean v49.0 regression baseline ledger is recorded.
  5. The `degeneretteResolve` rename + re-peg is proven (TST-05) — the bounty is flat literal ~1 BURNIE per tx (NOT per-item), the ≥3-resolution pay-gate holds, revert-on-no-work (zero resolved), WWXRP stays excluded from both the gate count and the reward, and the resolution RESULTS are byte-identical vs the per-item path (rename + bounty-shape change only, no payout/RNG change).
**Plans**: TBD
**UI hint**: no

### Phase 333: TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure
**Goal**: The v49.0 audit subject (the single batched diff — the router + advance-rework + the GAS-calibrated peg + the micro-opts, FROZEN at the IMPL/GAS HEAD) is delta-audited NON-WIDENING against the v48.0 baseline `0cc5d10f`, swept by the 3-skill genuine-PARALLEL adversarial pass charged against the highest-risk advance-timing MEV + composed-reentrancy + faucet-drain surfaces, consolidated into `audit/FINDINGS-v49.0.md`, and the milestone is closed with the `MILESTONE_V49_AT_HEAD_<sha>` signal and the atomic ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS flip — re-attesting all 31 v49.0 requirements.
**Depends on**: Phase 332 (the audit subject must be implemented + GAS-calibrated + test-proven before the terminal delta-audit + sweep)
**Requirements**: SWEEP-01, SWEEP-02, SWEEP-03, BATCH-03
**Success Criteria** (what must be TRUE):
  1. The 3-skill genuine-PARALLEL adversarial sweep runs (SWEEP-01) — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` (`/degen-skeptic` OUT per `D-271-ADVERSARIAL-02`) against the frozen v49 subject, charged with: advance-timing MEV / same-tx bundling of advance-consume + buy/open, composed reentrancy (router→game→`creditFlip`), faucet-drain re-attestation on the unified surface, bounty-stacking, stall-multiplier abuse, and the unrewarded-advance liveness backstop — with `/zero-day-hunter` explicitly charged against same-tx-bundling of advance-consume + buy/open (Pitfall 3) and composed reentrancy (Pitfall 6), and every elevation passed through the skeptic dual-gate (structural-protection + 3-condition EV lens) before being recorded.
  2. The delta-audit attests NON-WIDENING vs the v48.0 baseline `0cc5d10f` (SWEEP-02) — every `contracts/`+`test/` diff is attributable to a v49 work item across the blast radius (AfKing router/`_autoBuy`/re-peg/micro-opt, AdvanceModule bounty-removal + return, Game wrapper + discovery views + MintModule pointer, the interface updates), each surface attested non-widening relative to the baseline, and the v48 SWAP cash-share advisory recorded carried-forward-unmodified.
  3. `audit/FINDINGS-v49.0.md` is authored at the v49.0 closure HEAD (SWEEP-03) — 9-section, mirroring the v44/v46/v47/v48 pattern, chmod 444, folding in the delta-audit (§3/§5) + the sweep disposition (§4), with any findings adjudicated or deferred per USER direction.
  4. The closure flip is applied (BATCH-03) — all v49.0 requirements re-attested at closure, the `MILESTONE_V49_AT_HEAD_<sha>` closure signal emitted and propagated verbatim, and the atomic 5-doc closure flip (ROADMAP + STATE + MILESTONES + PROJECT + REQUIREMENTS) applied; the closure plan is a single blocking USER closure-verdict + signal-format approval gate (autonomous:false) — the auto-advance is HELD at the closure boundary per `feedback_pause_at_contract_phase_boundaries`.
**Plans**: TBD
**UI hint**: no

---

## Progress

**Execution Order:** Phases execute in numeric order: 329 → 330 → 331 → 332 → 333

| Phase | Milestone | Plans Complete | Status | Completed |
|-------|-----------|----------------|--------|-----------|
| 329. SPEC — Design-Lock + 4 Structural Invariants | v49.0 | 3/3 | Complete    | 2026-05-26 |
| 330. IMPL — The ONE Batched Contract Diff | v49.0 | 0/TBD | Not started | - |
| 331. GAS — Worst-Case Marginal + Break-Even Peg | v49.0 | 0/TBD | Not started | - |
| 332. TST — Freeze Fuzz + One-Category + Regression | v49.0 | 0/TBD | Not started | - |
| 333. TERMINAL — Delta Audit + Sweep + Closure | v49.0 | 0/TBD | Not started | - |

---

## Coverage (v49.0)

**31/31 v49.0 requirements mapped to exactly one phase — 0 orphaned, 0 duplicated.**

| Phase | Requirements | Count |
|-------|--------------|-------|
| 329 SPEC | BATCH-01, ROUTER-07, ADV-04, GAS-03 | 4 |
| 330 IMPL | ROUTER-01, ROUTER-02, ROUTER-03, ROUTER-04, ROUTER-05, ROUTER-06, ADV-01, ADV-02, ADV-03, ADV-05, GASOPT-01, GASOPT-02, BATCH-02 | 13 |
| 331 GAS | GAS-01, GAS-02, GAS-04, GAS-05, GAS-06 | 5 |
| 332 TST | TST-01, TST-02, TST-03, TST-04, TST-05 | 5 |
| 333 TERMINAL | SWEEP-01, SWEEP-02, SWEEP-03, BATCH-03 | 4 |
| **Total** | | **31** |

**Per-category split (verification):**

| Category | Total | SPEC | IMPL | GAS | TST | TERMINAL |
|----------|-------|------|------|-----|-----|----------|
| ROUTER | 7 | 1 (07) | 6 (01–06) | — | — | — |
| ADV | 5 | 1 (04) | 4 (01,02,03,05) | — | — | — |
| GAS | 6 | 1 (03) | — | 5 (01,02,04,05,06) | — | — |
| GASOPT | 2 | — | 2 (01–02) | — | — | — |
| TST | 5 | — | — | — | 5 (01–05) | — |
| SWEEP | 3 | — | — | — | — | 3 (01–03) |
| BATCH | 3 | 1 (01) | 1 (02) | — | — | 1 (03) |
| **Total** | **31** | **4** | **13** | **5** | **5** | **4** |

**Center-of-gravity rationale (where a requirement spans design + impl + test):**
- **ROUTER-07** (reentrancy disposition decision: guard vs composed-CEI) → SPEC; the guard/CEI code lands under ROUTER-01..06 (IMPL).
- **ADV-04** (the frozen-advance-consume VRF-freeze invariant decision) → SPEC, where it is locked as structural invariant (b); the freeze-invariant fuzz that PROVES it empirically is TST-01 (TST); the ordering that preserves it lands under ADV-01..05 (IMPL).
- **GAS-03** (the single unified day-start epoch decision — collapsing the AfKing vs AdvanceModule conventions) → SPEC (it is a design-lock that feeds the `advanceGame` return-shape signature); the calibration GAS reqs (GAS-01/02/04/05) are the GAS phase's empirical work.
- **BATCH-01** (the single SPEC design-lock) absorbs the 4 structural invariants + the shared-signature reconciliation + the grep-attestation; it does not duplicate the ROUTER/ADV requirements those decisions feed.
- **BATCH-02** (the single batched contract diff + the contract-commit HARD STOP) → IMPL; the diff is authored producer-before-consumer with the GAS peg as a placeholder calibrated at Phase 331.
- **BATCH-03** (the TERMINAL closure flip) re-attests all 31 v49.0 requirements at closure — alongside SWEEP-01/02/03 in Phase 333.
- **GAS-06 / TST-05** (the `autoResolve`→`degeneretteResolve` rename + flat ~1-BURNIE "lose" re-peg with the ≥3-resolution pay-gate, added at the Phase 329 discussion 2026-05-26) → calibrate-at-GAS (331) / prove-at-TST (332); the rename + bounty-logic code change rides the BATCH-02 diff (330). The router-fold is OUT (architecturally blocked); only the rename + bounty re-peg are in scope.

✓ All 31 v49.0 requirements mapped
✓ No orphaned requirements
✓ No duplicated requirements

**Note on §13e-style "uncovered" warnings:** as in the v47/v48 roadmaps, milestone-wide "uncovered" warnings are EXPECTED false alarms — each phase owns only its slice; SWEEP-01/02/03 + BATCH-03 re-attest the full 29-requirement set at TERMINAL. The TST/TERMINAL phases do not "uncover" the IMPL reqs — they re-prove and re-attest them.

---

<details>
<summary>✅ v48.0 sDGNRS Far-Future Salvage Swap + v47 Deferred-Findings Fixes + Keeper/Pool/Tombstone/Hero Bundle (Phases 325-328) — SHIPPED 2026-05-26</summary>

**Closure signal:** `MILESTONE_V48_AT_HEAD_0cc5d10fbc1232a6d2e7b0464fe21541b9812029` (subject frozen `1575f4a9`; 0 NEW findings; F-47-01 + F-47-02 RESOLVED_AT_V48). Audit baseline → subject: v47.0 closure HEAD `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2` → v48.0 closure HEAD. ONE batched USER-APPROVED diff `f50cc634` + the 327 HERO-04 constant-only finals landing `1575f4a9`. Shape: SPEC → IMPL → TST → TERMINAL.

| Phase | Plans | Status | Completed |
|-------|-------|--------|-----------|
| 325. SPEC — Design-Lock + Call-Graph Attestation + Shared-Surface Reconciliation | 3/3 | Complete | 2026-05-25 |
| 326. IMPL — The ONE Batched Contract Diff (all 7 items) | 8/8 | Complete | 2026-05-25 |
| 327. TST — Repro/Same-Results + No-Arb + EV + Regression Proofs | 6/6 | Complete | 2026-05-26 |
| 328. TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure | 4/4 | Complete | 2026-05-26 |

**Coverage:** 40/40 requirements mapped (325 SPEC: 5 · 326 IMPL: 25 · 327 TST: 9 · 328 TERMINAL: 1, re-attests all 40); 0 orphaned, 0 duplicated. Per-category: PFIX 3 · RFALL 5 · KEEP 5 · POOL 6 · BTOMB 3 · HERO 6 · SWAP 9 · BATCH 3. Closure verdict: all 7 surfaces shipped (presale-drain fix, redemption stETH-fallback, keeper rename + VAULT-code 75/20/5, AfKing pool recovery, gameover BURNIE tombstone, Degenerette hero 2-pt rescale, sDGNRS far-future salvage swap); RNG_FREEZE_INTACT; 0 NEW_FINDINGS; KNOWN_ISSUES_UNMODIFIED. One informational SWAP cash-share doc-drift advisory (USER-accepted ≤60% as canonical, NOT a finding). Full detail in `.planning/MILESTONES.md` + `audit/FINDINGS-v48.0.md` (chmod 444).

</details>

<details>
<summary>✅ v44.0–v47.0 (Phases 304-324) — SHIPPED</summary>

Full per-phase detail for v44.0 (304-308), v45.0 (309-314), v46.0 (316-320), and v47.0 (321-324) lives in `.planning/MILESTONES.md`. Summary:

- **v47.0** Rake-Free Presale + Lootbox-Boon Unification + Redemption/Degenerette/Cancel-Tombstone Bundle (321-324, shipped 2026-05-25; signal `MILESTONE_V47_AT_HEAD_da5c9d50989707c8964a9411e68c51ca1b1a25f2`). 4-phase SPEC→IMPL→TST→TERMINAL; 45/45 reqs. 2 MEDIUM findings (F-47-01 + F-47-02) DEFERRED→v48.0 (both RESOLVED_AT_V48). H-CANCEL-SWAP-MISS RESOLVED_AT_V47.
- **v46.0** Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal (316-320, shipped 2026-05-24; signal `MILESTONE_V46_AT_HEAD_16e9668a6de35cc0c809d81ce960aee137950687`). 6-phase FEATURE milestone with the dedicated GAS phase 319 (the break-even peg precedent v49.0 mirrors); the in-tree `AfKing` keeper shipped here. 1 MEDIUM finding H-CANCEL-SWAP-MISS DEFERRED→v47.0 (RESOLVED_AT_V47).
- **v45.0** VRF-Rotation Liveness Fix + Consolidate-Forward Delta Audit (309-314, shipped 2026-05-23, minimal close; signal `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`). The CATASTROPHE-class VRF-rotation orphan-index liveness fix; the `v45-vrf-freeze-invariant` north-star established here.
- **v44.0** sStonk Per-Day Redemption Refactor + Accounting Invariant Proof (304-308, shipped 2026-05-20; signal `MILESTONE_V44_AT_HEAD_6f0ba2963a10654ba554a8c333c5ee80c54a8349`). V-184 CATASTROPHE structurally closed; 13/13 invariants proven.

</details>

---
*Roadmap created: 2026-05-25 (v48.0)*
*v49.0 milestone added: 2026-05-26 (5 phases 329-333, SPEC→IMPL→GAS→TST→TERMINAL; 29 reqs / 7 categories; GAS-06 + TST-05 added at the Phase 329 discussion for the `autoResolve`→`degeneretteResolve` rename + flat ~1-BURNIE "lose" re-peg → 31 reqs)*
*Phase 329 planned: 2026-05-26 (3 plans / 2 waves — W1 329-01 ATTEST router+advance ∥ 329-02 ATTEST degeneretteResolve, W2 329-03 reconcile → 329-SPEC.md; all doc-only, zero contracts/*.sol)*
</content>
