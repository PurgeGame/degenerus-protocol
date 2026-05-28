# Phase 335: IMPL — The ONE Batched Contract Diff (WHALE + AFSUB + MINTDIV-if-real) - Context

**Gathered:** 2026-05-28
**Status:** Ready for planning

<domain>
## Phase Boundary

Land the three v50.0 RNG-adjacent contract refinements as **ONE reconciled `contracts/*.sol` + `test/*.t.sol` batched diff** under the Phase-334 SPEC's settled shared signatures, in the producer-before-consumer edit order (Storage → Game facade → LootboxModule → MintModule → AfKing+BurnieCoin), applied + locally compiled + `forge test`-green-or-known-baseline, then **HELD at the contract-commit boundary** for explicit USER hand-review (BATCH-02 HARD STOP per `feedback_wait_for_approval` / `feedback_no_contract_commits`).

**The three items in one diff:**
1. **WHALE** — the box-open whale-pass mint becomes an O(1) `whalePassClaims[beneficiary] += grant` (replacing the inline 100-iteration `_queueTickets` loop at `LootboxModule.sol:1250-1260`); the existing deployed `claimWhalePass(address)` (`WhaleModule:1018`) is the materialization endpoint (D-20 convergence onto existing machinery, NOT a parallel map); the early-game ≤10 bonus band is DROPPED (D-21); the 331 whale-pass-weighted `autoOpen` budget is retired and `OPEN_BATCH` returns to flat per-box sizing (WHALE-03).
2. **AFSUB** — `burnForKeeper` + `paidThroughDay`/`WINDOW_DAYS` are removed from `AfKing.sol` AND the `BurnieCoin.sol:472` implementation is deleted (D-09); `validThroughLevel` repurposes the `Sub` slot offset 5 (in-place); subscribe encodes the horizon from a new `lazyPassHorizon` view on the Game facade (deity = sentinel); per-iter check is a cheap stored-field compare (no per-iter pass SLOAD on the non-crossing path); the crossing reads `lazyPassHorizon` EXACTLY ONCE → refresh-or-evict (not unconditional kick); OPEN-E `fundingSource` + 4 protections + SUB-07 cancel-tombstone + v49 swap-pop invariant ALL preserved.
3. **MINTDIV** — the one-liner `MintModule.sol:716` `processed += writesUsed >> 1` → `+= take` (MINTDIV-01 PROVEN REACHABLE per D-22; D-15 ships, D-16 NEGATIVE branch does not apply).

**Audit baseline:** v49.0 closure HEAD `MILESTONE_V49_AT_HEAD_b0511ca29130c36cbe9bfb44e282c7379f9778c9`. The working tree under `contracts/` is byte-identical to `b0511ca2` (`git diff b0511ca2 HEAD -- contracts/` is EMPTY per the 334-GREP-ATTESTATION).

**This phase is autonomous up to the contract-commit boundary, then HARD STOPS.** The auto-advance is HELD per `feedback_pause_at_contract_phase_boundaries`.

</domain>

<spec_lock>
## Requirements (locked via the Phase-334 SPEC artifact set)

**10 requirements are locked for Phase 335** (WHALE-01, WHALE-02, WHALE-03, AFSUB-01, AFSUB-02, AFSUB-03, AFSUB-04, AFSUB-05, MINTDIV-02, BATCH-02 — see `.planning/REQUIREMENTS.md` and ROADMAP Phase 335 §Success Criteria 1–5).

**The Phase-334 SPEC is the design contract.** It is a multi-doc set (no single `335-SPEC.md`); the navigation/closure doc is `.planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-SPEC-INDEX.md`. Downstream agents (planner, executor) MUST read the seven artifacts before authoring or applying the diff. Requirements are not duplicated here.

**Decisions D-01..D-23 (locked in 334-CONTEXT.md) flow forward unchanged:**

- **Whale (D-01..D-07, D-20..D-23):** permissionless `claimWhalePass(address beneficiary)` NEVER auto-triggered (D-01); `whalePassClaims[beneficiary]` REUSED — NOT a parallel map (D-02/D-20); claim-time `level+1` anchoring (D-03); stats apply AT CLAIM (D-04); box-open writes NO `mintPacked_` (D-04); TST-01 equivalence reinterpreted as correct-claim-time-grant, not byte-identical-to-old (D-05); economic delta re-attested by 338 (D-06/D-21); autoOpen carve-out retired → flat OPEN_BATCH (D-07); the existing claim endpoint at `WhaleModule:1018` is the convergence target (D-20); ≤10 bonus band DROPPED (D-21); MINTDIV-01 PROVEN REACHABLE → one-liner ships (D-22); gameOver-forfeit recorded (D-23 — see D-IMPL-01 below for the structural-guard attestation).
- **AfKing (D-08..D-13):** autoBuy-only gating (D-08); `burnForKeeper` deleted in BOTH `AfKing.sol` + `BurnieCoin.sol` (D-09); no `refreshPass()` entrypoint — lazy-only at the crossing (D-10); new `lazyPassHorizon` view (deity → sentinel; lazy/whale → covered-through; D-11); preserved invariants (cheap per-iter compare, single crossing read, refresh-or-evict, OPEN-E + 4 protections, SUB-07 + swap-pop; D-12); no migration — pre-launch redeploy-fresh (D-13).
- **MintModule (D-14..D-16):** MINTDIV-01 is a PROOF, not an assertion (D-14); reachable → minimal one-liner fix, loops STAY separate (D-15); NEGATIVE branch is N/A per D-22 (D-16).
- **Cross-cutting (D-17..D-19):** RNGAUDIT structure locked (D-17 — 337's job, not 335's); producer-before-consumer edit order (D-18); grep-attest every anchor vs `b0511ca2` (D-19, attested in 334-GREP-ATTESTATION.md — the working tree is byte-identical to the baseline).

**In scope (per the SPEC + the policy decisions below):** the three contract items + the test-fixture migration of all 7 affected test files in the same single batched diff (per D-IMPL-02 below); the existing `KeeperOpenBoxWorstCaseGas` harness re-run for the WHALE-03 flat OPEN_BATCH attestation (per D-IMPL-04 below); local `forge build` + `forge test` green-or-known-baseline at the HARD STOP (per D-IMPL-03 below).

**Out of scope:** running the external RNG-audit protocol (337 package-only); full MintModule loop dedup (D-15 — rejected for v50); the formal NON-WIDENING attestation + ledger + freeze-fuzz harness + MINTDIV same-traits regression (TST-04/TST-01/TST-02/TST-03 — 336); the v49.0 baseline `666/42/17` re-attestation (336); committing the diff (USER hand-review gate).

</spec_lock>

<decisions>
## Implementation Decisions

### D-IMPL-01 — `gameOver`-forfeit: NO IMPL CHANGE (D-23 holds by existing structural guard)

**The deployed `claimWhalePass` at `WhaleModule:1018` already enforces forfeit post-gameOver by structural transitivity** through `_livenessTriggered()` (`Storage:1213`). The trace:

1. `gameOver = true` is set in exactly ONE place: `GameOverModule.handleGameOverDrain:145`.
2. `handleGameOverDrain` is reached only via `_handleGameOverPath` (`AdvanceModule:596`).
3. `_handleGameOverPath` returns early at `:522` if `_livenessTriggered() == false` — so **gameOver can only flip when `_livenessTriggered() == true` at the moment of the flip**, which requires `lastPurchaseDay == false && jackpotPhaseFlag == false` (the early-out at `Storage:1214`) AND a day-stall (`lvl == 0 && day-psd > 7d` OR `lvl != 0 && day-psd > 120d`) or a VRF-stall (`rngRequestTime != 0 && block.timestamp - rngStart >= _VRF_GRACE_PERIOD`).
4. Post-gameOver, level is frozen, `purchaseStartDay` is frozen, and the active-phase flags cannot be re-flipped (advance is blocked). The day-stall (or VRF-stall) condition that triggered only gets staler.
5. → `_livenessTriggered()` returns **true forever** post-gameOver → `claimWhalePass` reverts forever (`WhaleModule:1019`'s `if (_livenessTriggered()) revert E();`).

**Forfeit is enforced structurally, by existing guard.** No `if (gameOver) revert` addition, no proactive zero-out at `gameOver()`, no clear-but-skip semantics. D-23 is satisfied by `_livenessTriggered`. 338's economic-analyst should re-attest this transitivity (not rebuild it).

### D-IMPL-02 — Test-fixture migration: FULL ALIGNMENT in 335

The **ONE batched diff spans `contracts/*.sol` + `test/*.t.sol`**, both committed under the same USER hand-review HARD STOP. Without test/ migration, `forge build` cannot succeed (~70 references across 7 test files directly interrogate `Sub.paidThroughDay`, `burnForKeeper()`, `hasAnyLazyPass()`, `OPEN_NORMAL_GAS_UNIT`, `_activateWhalePass` — all removed by the contract diff), making "applied + locally compiled/tested" impossible to demonstrate.

**v49 precedent:** Phase 330 IMPL `63bc16ca` shipped "5 contracts + 9 tests" in one USER-approved batch. 335 follows the same pattern.

**The 7 test files migrating in 335:**
- `test/fuzz/AfKingSubscription.t.sol` — `paidThroughDay` (×14), `burnForKeeper` (×11), `hasAnyLazyPass` (×3)
- `test/fuzz/AfKingFundingWaterfall.t.sol` — `paidThroughDay` (×5), `burnForKeeper` (×6), `hasAnyLazyPass` (×3)
- `test/fuzz/AfKingConcurrency.t.sol` — `paidThroughDay` (×18)
- `test/fuzz/KeeperNonBrick.t.sol` — `paidThroughDay` (×1), `hasAnyLazyPass` (×1)
- `test/fuzz/RngFreezeAndRemovalProofs.t.sol` — `hasAnyLazyPass` (×7)
- `test/gas/KeeperLeversAndPacking.t.sol` — `paidThroughDay` (×2), `burnForKeeper` (×2)
- `test/gas/RouterWorstCaseGas.t.sol` — `OPEN_NORMAL_GAS_UNIT` (×6), `_activateWhalePass` (×5)

The migrated test bodies assert the **new** pass-gated semantics (`validThroughLevel` compare, refresh-or-evict crossing, no per-iter pass SLOAD on the non-crossing path, OPEN-E re-attest), the O(1) box-open + claim equivalence (the WHALE-01/02 roundtrip), and the retired-carve-out flat-budget OPEN_BATCH path. **This effectively pulls TST-01 (whale-pass equivalence) and TST-02 (AfKing pass-gated sub coverage) into 335.** Phase 336 narrows accordingly to:
- the freeze-fuzz extension of `RngLockDeterminism.t.sol` (TST-01 freeze leg),
- the MINTDIV same-traits-across-split regression (TST-03),
- the formal NON-WIDENING attestation + a v50.0 baseline ledger replacing v49's `666/42/17` (TST-04).

### D-IMPL-03 — Local-test scope at the HARD STOP: `forge build` + full `forge test` green-or-known-baseline

The local verification before the USER hand-review:
1. `forge build` — must be green.
2. `forge test` (full suite) — any NEW red vs the v49 baseline `666/42/17`-by-NAME (per the 332 verification ledger) must be **reconciled inside 335**, NOT deferred. The test-fixture migration in D-IMPL-02 IS the reconciliation vehicle: tests follow the new code in the same diff.
3. The HARD STOP USER review covers a green-or-known-baseline suite — no NEW reds remain at hand-review.
4. If a NEW red surfaces that is genuinely a v50 regression (not a fixture-migration artifact), STOP and re-spec — do NOT push it to 336 as a fixture-migration issue. The full-alignment policy is precisely what makes this discrimination crisp.

### D-IMPL-04 — OPEN_BATCH flat-sizing re-confirmation: fresh measurement via `KeeperOpenBoxWorstCaseGas`

The WHALE-03 acceptance ("flat OPEN_BATCH re-confirmed to stay under the autoOpen tx-gas ceiling at the worst-case uniform open") is satisfied empirically:

- **Method:** re-run the existing harness `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` against the v50.0-applied contract (it auto-compiles under D-IMPL-02's full alignment). Record the new per-box gas figure (expected ~89K — uniform across whale-pass and non-whale-pass openers per D-02/D-04).
- **Pick:** flat `OPEN_BATCH` = floor((16.7M − headroom) / measured_per_box_gas), with a documented headroom margin (≥ 1 box worth, to absorb a worst-case-vs-typical drift). The 331-rescope picked `OPEN_BATCH = 100` against the gas-weighted path; the new flat picker drops the gas-weight indirection entirely.
- **Attest:** the SUMMARY records the measured per-box figure, the chosen OPEN_BATCH, and `chosen × measured ≤ 16.7M − headroom` as the binding attestation.
- **The retired surfaces:** delete `OPEN_NORMAL_GAS_UNIT = 90_000` (`DegenerusGame.sol:1561`), the autoOpen `gasleft()` weighting (`:1687`), and the `weighted += used / OPEN_NORMAL_GAS_UNIT` ceil-divide math (`:1728`). Replace the `weighted < maxCount` loop guard with the flat-count check.
- **If the measurement reveals a ceiling overshoot under any reasonable OPEN_BATCH:** STOP and re-spec — do NOT silently lower OPEN_BATCH below what 331 considered usable. This would be a freeze-floor-class signal that WHALE-01's "uniform O(1) opens" assumption broke.

### Claude's Discretion (flowed forward from 334-CONTEXT.md — NOT re-asked)

Constrained by the decisions above:

- **`claimWhalePass` entrypoint home (D-01 Claude's Discretion):** the deployed `claimWhalePass(address)` at `WhaleModule:1018` is the existing public entrypoint (D-20). Whether to add a `DegenerusGame` external fn delegating to it, or to expose the module-direct path directly, is the planner's call — both are coherent. The SPEC §1 Step 2 records that a facade-layer routing is acceptable.
- **`validThroughLevel` field width (D-11 Claude's Discretion):** in-place repurpose of `Sub.paidThroughDay` slot (offset 5, `AfKing.sol:89`) → `validThroughLevel`. Keep `uint32` (zero packing churn) OR narrow to `uint24` to mirror `level`'s width — both acceptable; the planner picks based on packing math vs codegen simplicity. The settled semantic is the *meaning* (a level horizon), not the exact width.
- **`lazyPassHorizon` view name + signature (D-11):** the new per-pass-type level-horizon view on the Game facade. Deity → `type(uint24).max` sentinel (or `type(uint32).max` if the field is uint32); lazy/whale → the covered-through `frozenUntilLevel`. Exact name and the iface decl AfKing reads it through are the planner's call.
- **Within-cluster ordering for the AfKing + BurnieCoin pair (D-18 / IMPL-EDIT-ORDER-MAP §1 Step 5):** the atomic-diff property makes either order safe (delete the AfKing call sites first → BurnieCoin impl second, OR delete both atomically in the same diff). Producer-before-consumer narrative PREFERS caller-first for reviewer clarity; planner picks.

### Folded Todos

None — no pending todos matched Phase 335 in the cross-reference scan.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner, executor) MUST read these before authoring or applying the diff.**

### Milestone scope (read first)
- `.planning/ROADMAP.md` — Phase 335 §Success Criteria 1–5; the v50.0 cross-cutting rule (re-attest every `file:line` vs `b0511ca2`; security/RNG-freeze floor; one batched diff + HARD STOP at the contract-commit boundary).
- `.planning/REQUIREMENTS.md` — Phase 335's 10 requirements: WHALE-01, WHALE-02, WHALE-03, AFSUB-01, AFSUB-02, AFSUB-03, AFSUB-04, AFSUB-05, MINTDIV-02, BATCH-02 (lines 13–22, 27, 48; also the §"Center-of-gravity notes" at :114).

### Phase-334 SPEC — the design contract (read in this order)
- `.planning/phases/334-spec-design-lock-mintdiv-reachability-proof-rngaudit-structu/334-SPEC-INDEX.md` — the navigation + multi-source coverage audit (GOAL 5/5, REQ 3/3, RESEARCH 6/6, CONTEXT 22/22+1 N/A); start here for the SPEC map.
- `.planning/phases/334-.../334-IMPL-EDIT-ORDER-MAP.md` — **the producer-before-consumer 5-step authoring order** (Storage → Game facade → LootboxModule → MintModule → AfKing+BurnieCoin) + the writer-vs-reader `_queueTickets` reconciliation (WHALE and MINTDIV commute within the diff).
- `.planning/phases/334-.../334-DESIGN-LOCK-WHALE-MINTDIV.md` — whale-pass O(1) claim convergence (D-20/D-21) + MintModule `:716`→`:502` alignment signatures + the autoOpen carve-out retirement (WHALE-03).
- `.planning/phases/334-.../334-DESIGN-LOCK-AFKING.md` — `validThroughLevel` placement + `lazyPassHorizon` view + refresh-or-evict + OPEN-E/SUB-07/swap-pop preservation criteria.
- `.planning/phases/334-.../334-WHALE04-FREEZE-PROOF.md` — the WHALE-04 freeze-safety proof (§1–§5 slot-by-slot RNG-freeze argument; VERDICT FREEZE-SAFE).
- `.planning/phases/334-.../334-MINTDIV01-REACHABILITY-VERDICT.md` — the MINTDIV-01 reachability VERDICT (PROVEN REACHABLE: −17 warm trace, 2 callers, owed=300 scenario) — the one-liner SHIPS.
- `.planning/phases/334-.../334-GREP-ATTESTATION.md` — every `file:line` cited across the v50.0 scope re-confirmed vs `b0511ca2` (5 drift corrections recorded); the working tree under `contracts/` is byte-identical to the baseline.
- `.planning/phases/334-.../334-CONTEXT.md` — the D-01..D-23 decision lock (flows forward unchanged into 335).
- `.planning/phases/334-.../334-RNGAUDIT-STRUCTURE-SKETCH.md` — context only (Phase 337 deliverable; not 335's job).

### Whale-pass surfaces (WHALE-01/02/03; D-IMPL-04)
- `contracts/modules/DegenerusGameLootboxModule.sol` — `_activateWhalePass:1240` + the 100-iter `_queueTickets` loop `:1250-1260` (deleted by WHALE-01); `BOON_WHALE_PASS:378`; bonus constants `:205-209` (the ≤10 band DROPPED per D-21; `WHALE_PASS_BONUS_TICKETS_PER_LEVEL=40` and `WHALE_PASS_BONUS_END_LEVEL=10` removed).
- `contracts/modules/DegenerusGameWhaleModule.sol:1018` — the existing deployed `claimWhalePass(address player)` (the convergence target per D-20); already permissionless-w/-beneficiary, `_livenessTriggered`-gated, `level+1`-anchored, calls `_applyWhalePassStats`, queues `_queueTicketRange(player, startLevel, 100, halfPasses, false)`.
- `contracts/modules/DegenerusGameWhaleModule.sol:1032` + `contracts/modules/DegenerusGameDecimatorModule.sol:588` — the two OTHER `_applyWhalePassStats` callers that stay immediate-apply, MUST NOT change (per D-04).
- `contracts/storage/DegenerusGameStorage.sol` — `_applyWhalePassStats:1111` (reused verbatim at claim-time, just relocated from the LootboxModule caller; the other two callers prove it is safe to keep immediate elsewhere); `_queueTicketRange:647`; `_livenessTriggered:1213` (the structural-guard for D-IMPL-01); `whalePassClaims` declared in inherited state (the producer slot Step 3 writes); `_simulatedDayIndex` / `_VRF_GRACE_PERIOD` (liveness-context for the D-IMPL-01 attestation).
- `contracts/modules/DegenerusGamePayoutUtils.sol:52` (`_queueWhalePassClaimCore`) + `contracts/modules/DegenerusGameJackpotModule.sol:1410` — the existing `whalePassClaims +=` writer to MIRROR for WHALE-01 (D-20).
- `contracts/DegenerusGame.sol` — `OPEN_NORMAL_GAS_UNIT:1561`, autoOpen weighting `:1687`, `weighted += used / OPEN_NORMAL_GAS_UNIT` math `:1728` (ALL deleted by WHALE-03 per D-07); the new `lazyPassHorizon` view inserted alongside `hasAnyLazyPass:1520` (D-11).

### AfKing surfaces (AFSUB-01..05; D-09..D-13)
- `contracts/AfKing.sol` — `IBurnie burnForKeeper:57` (deleted); `Sub` layout `:79-92` with `paidThroughDay` offset 5 (repurposed → `validThroughLevel` per D-11); `WINDOW_DAYS:220` (deleted); `subscribe:374`; OPENE-04 gate `:397-403` (PRESERVED); SUB-02 self-consent `:385-391` (PRESERVED); free-extend `hasAnyLazyPass:432` (deleted from subscribe path); subscribe-time PAID burn call `:437` (deleted); day-31 PAID burn call `:641` (deleted); day-31 `hasAnyLazyPass:631` (deleted); flags bit 0 `FLAG_WINDOW_PAID` `:433/:442/:634/:650` (freed); `setDailyQuantity:458` reclaim/tombstone (reused for refresh-or-evict — PRESERVED); autoBuy cursor `_autoBuyCursor:214`; the `_autoBuy:605` swap-pop reclaim (PRESERVED); the `_autoBuy:630-631` per-iter check (rewritten as `currentLevel <= sub.validThroughLevel`).
- `contracts/BurnieCoin.sol` — `KeeperBurn` event `:85` (deleted); `burnForKeeper:472` impl (deleted); `onlyAfKing` modifier `:549` (deleted — confirmed `burnForKeeper` is its ONLY user per the 334-DESIGN-LOCK-AFKING.md §5.2 grep).

### MintModule surface (MINTDIV-02; D-15/D-22)
- `contracts/modules/DegenerusGameMintModule.sol:716` — `processed += writesUsed >> 1` → `+= take` (the ONE-LINER; the reference is `processFutureTicketBatch:502`); the suspect call site `processTicketBatch:671` (the function whose `:716` is fixed); `WRITES_BUDGET_SAFE:93` (= 550, the budget binding the `−17`-warm trace); `_raritySymbolBatch` LCG consumer.

### Test files migrating in 335 (D-IMPL-02 full alignment)
- `test/fuzz/AfKingSubscription.t.sol` — assert the new `validThroughLevel` semantics + refresh-or-evict crossing + no per-iter pass SLOAD on non-crossing.
- `test/fuzz/AfKingFundingWaterfall.t.sol` — assert OPEN-E `fundingSource` 4 protections + pass-eviction-preserves-tombstone semantics.
- `test/fuzz/AfKingConcurrency.t.sol` — assert pass-gated sweep + the v49 swap-pop membership invariant.
- `test/fuzz/KeeperNonBrick.t.sol` — assert no-brick under pass-eviction + the H-CANCEL-SWAP-MISS class never reproduces.
- `test/fuzz/RngFreezeAndRemovalProofs.t.sol` — extend the v45 `RngLockDeterminism` model to cover the box-open `whalePassClaims +=` write (records-no-freeze) and the AfKing crossing's `lazyPassHorizon` read (non-RNG-window). Note: the deeper RNG-freeze fuzz proof of the deferred-claim path is 336's TST-01 freeze leg, not 335's.
- `test/gas/KeeperLeversAndPacking.t.sol` — re-pack the `Sub` slot oracle to the new `validThroughLevel` field.
- `test/gas/RouterWorstCaseGas.t.sol` — drop the whale-pass-weighted budget assertions; re-target the flat `OPEN_BATCH` oracle.
- `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` — the harness for D-IMPL-04's fresh OPEN_BATCH measurement (re-run against the v50.0 contract; not necessarily rewritten — it ALREADY measures the right thing, just emits the new uniform-cost figure).

### Invariants / preserved properties (must NOT regress)
- `v45-vrf-freeze-invariant` — re-attested by 334-WHALE04-FREEZE-PROOF; 335's IMPL must not introduce a new write into a frozen slot during `rngLock`.
- `open-e-operator-approval-trust-boundary` — the 4 OPEN-E structural protections (consent-gate-at-subscribe / default-self byte-identical / no-escalation / trust-the-sub temporal bound) survive pass-gating per D-12 / 334-DESIGN-LOCK-AFKING §6.1.
- `afking-cancel-tombstone-streak-finding` — the SUB-07 cancel-tombstone + v49 swap-pop invariant (membership ⟺ packed != 0) hold under pass-eviction; pass-eviction must NOT reproduce the H-CANCEL-SWAP-MISS missed-day class.

### Feedback / policy
- `feedback_security_over_gas` — security/RNG floor is a HARD constraint; D-IMPL-03 enforces it by requiring NEW reds to be reconciled inside 335 rather than deferred.
- `feedback_wait_for_approval` / `feedback_no_contract_commits` / `feedback_pause_at_contract_phase_boundaries` — the BATCH-02 HARD STOP at the contract-commit boundary; the auto-advance is HELD.
- `worktrees-reenabled-contracts-gate.md` — per-plan worktree gate; plans touching `contracts/` MUST set `autonomous: false` for the commit gate.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets (the convergence-vs-greenfield story)
- **`claimWhalePass(address) at WhaleModule:1018` ALREADY EXISTS** (D-20 — the entire convergence story). It is already permissionless-w/-beneficiary-arg, already `_livenessTriggered`-gated, already `level+1`-anchored, already zeroes `whalePassClaims` before applying, already calls `_applyWhalePassStats(player, startLevel)`, already queues `_queueTicketRange(player, startLevel, 100, halfPasses, false)`. WHALE-01's job is to wire the box-open boon onto this same machinery — NOT to author a parallel claim. **Pitfall:** do NOT introduce a `pendingWhalePasses[...]` map; that is a RELABEL of the existing `whalePassClaims` per D-02.
- **`_livenessTriggered:1213` is the structural guard** that satisfies D-23 (gameOver-forfeit) without any IMPL change — see D-IMPL-01 above for the transitivity trace.
- **`_applyWhalePassStats:1111` is shared across 3 callers** — only the LootboxModule path moves to claim-time; `WhaleModule:1032` (bundle purchase) and `DecimatorModule:588` (Decimator win) stay immediate-apply, untouched.
- **`processFutureTicketBatch:393` with `processed += take:502`** is the reference-correct contiguous advance the MINTDIV-02 one-liner copies — no new logic to author.
- **AfKing's `setDailyQuantity(0)` reclaim/tombstone path `:458`** is the eviction mechanism the refresh-or-evict crossing reuses (no new tombstone infra; the v49 swap-pop in `_autoBuy:605` is the reclaim).
- **`test/gas/KeeperOpenBoxWorstCaseGas.t.sol`** is the existing harness for D-IMPL-04's OPEN_BATCH re-measurement — leverages it directly, no new test code.

### Established Patterns
- **Queue-then-materialize** (`project_lootbox_delayed_finalization_intentional`) + **claimable-everywhere** (`universal-claimable-pay`) → the whale-pass O(1)-record + player-paid-claim fits the existing idiom.
- **Stored-field compare** (`paidThroughDay >= today` → `currentLevel <= validThroughLevel`) is the exact same cheap per-iter shape; GASOPT-05 win preserved by construction.
- **gameOver via liveness only** — the structural property that makes D-IMPL-01 sound (`AdvanceModule:596` → `:522` early-out → `GameOverModule:145` is the SOLE flip site).
- **v49 BATCH-02 precedent** — Phase 330 IMPL `63bc16ca` shipped 5 contracts + 9 tests in one USER-approved batch. 335 follows the same single-commit pattern.

### Integration Points
- **New `lazyPassHorizon` view** on `DegenerusGame.sol` alongside `hasAnyLazyPass:1520`; AfKing consumes it via the `IGame` iface at subscribe + at the crossing.
- **Box-open writer side** — `LootboxModule._activateWhalePass` replaces the inline loop with `whalePassClaims[beneficiary] += grant;` (mirroring `PayoutUtils:52`).
- **`BurnieCoin.sol` integration** — losing `burnForKeeper:472` + the `KeeperBurn:85` event + the `onlyAfKing:549` modifier. AfKing is its ONLY caller per the 334 grep; safe to delete the impl in the SAME diff.
- **MintModule** — one-line edit at `:716`. No interface change, no caller change. Independent of WHALE/AFSUB within the diff.
- **Test-side integration** — the 7 test files in `<canonical_refs>` migrate in lockstep. The `forge build` gate at HARD STOP is the integration oracle.

### Edit Sequence (LOCKED by 334-IMPL-EDIT-ORDER-MAP.md)
Producer-before-consumer, 5 steps:
1. `DegenerusGameStorage.sol` — confirm `whalePassClaims` slot (no edit).
2. `DegenerusGame.sol` — add `lazyPassHorizon` view; retire `OPEN_NORMAL_GAS_UNIT`/autoOpen weight/math; confirm `claimWhalePass` entrypoint home (facade routing per Claude's Discretion).
3. `DegenerusGameLootboxModule.sol` — replace `_activateWhalePass:1240` 100-loop + the `_applyWhalePassStats` call with O(1) `whalePassClaims += grant`; drop the ≤10 bonus band constants.
4. `DegenerusGameMintModule.sol` — `:716` `>>1` → `+= take`. Independent.
5. `AfKing.sol` + `BurnieCoin.sol` — the AFSUB cluster (delete AfKing call sites first or atomically with BurnieCoin impl; the atomic-diff property makes either safe).

The shared `_queueTickets` surface (WHALE writer-side, MINTDIV reader-side) is INDEPENDENT — the two edits commute within the diff per 334-IMPL-EDIT-ORDER-MAP §2.

</code_context>

<specifics>
## Specific Ideas

- **User catch during discussion (2026-05-28):** *"doesn't `_livenessTriggered` already stop `claimWhalePass`?"* → triggered the D-IMPL-01 transitivity trace; D-23 gameOver-forfeit is satisfied by the existing guard, NO IMPL change to `claimWhalePass`. This is now the load-bearing attestation for 338's economic-analyst re-attest of D-23.
- **D-IMPL-02 cascade (full alignment in 335):** v49's "5 contracts + 9 tests in one batch" precedent (Phase 330 IMPL `63bc16ca`) is the model. The HARD STOP USER review sees a unified diff, not contracts-only.
- **D-IMPL-04 measurement-first:** the existing `KeeperOpenBoxWorstCaseGas.t.sol` harness is leveraged directly — no new gas-measurement code. The flat `OPEN_BATCH` value is *picked from the measurement*, not from a pre-derived ceiling.

</specifics>

<deferred>
## Deferred Ideas

- **Full dedup of the two MintModule loops** — rejected for v50 (D-15); standing maintenance idea (security-floor-gated, no gas win) for a future cycle.
- **Running the external RNG-audit protocol** through Gemini/ChatGPT + triaging output — 337 is package-only; running is OUT of v50.0.
- **The freeze-fuzz extension of `RngLockDeterminism.t.sol` proving deferred record + claim perturb no current-window entropy** — TST-01's freeze leg lands at 336, not 335. 335's `RngFreezeAndRemovalProofs.t.sol` rewrite only handles the trivial assertions about the new write paths (`whalePassClaims +=` is not a frozen-slot write; `lazyPassHorizon` is not an RNG-window read).
- **The MINTDIV same-traits-across-split regression test** — TST-03 lands at 336, not 335. 335 only ships the one-liner contract fix.
- **The NON-WIDENING attestation + the v50.0 baseline ledger replacing v49's `666/42/17`** — TST-04 lands at 336, not 335. 335 produces the green-or-known-baseline suite that 336 then attests as the new baseline.
- **A proactive `refreshPass()` entrypoint** — explicitly rejected at SPEC (D-10); the lazy-only refresh at the crossing is sufficient. Standing "smallest-surface" decision, no IMPL action.

### Reviewed Todos (not folded)

None — no pending todos matched Phase 335 in the cross-reference scan.

</deferred>

---

*Phase: 335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re*
*Context gathered: 2026-05-28*
