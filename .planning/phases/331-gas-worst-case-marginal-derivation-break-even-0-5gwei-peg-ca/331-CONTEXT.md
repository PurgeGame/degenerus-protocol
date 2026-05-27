# Phase 331: GAS — Worst-Case Marginal Derivation + Break-Even @0.5gwei Peg Calibration - Context

**Gathered:** 2026-05-27
**Status:** Ready for planning
**Source:** Synthesized from 329 SPEC + ROADMAP/REQUIREMENTS + USER seed-scope decision (plan-directly path; no full discuss-phase — design already locked in 329 SPEC)

<domain>
## Phase Boundary

Calibrate the v49 keeper-router incentive constants from **measured worst-case marginal
gas** (theoretical-first, then measured — never a guess, never `--gas-report` numbers as the
peg) and land them under a **USER-approved contract gate** (the v46 Phase 319 precedent). The
applied 330 IMPL diff (commit `63bc16ca`) is the subject the peg measures against — its
constants are explicit `GAS-331 PLACEHOLDER` markers in code.

In scope:
- GAS-01: worst-case-first marginal gas per keeper category (`autoBuy`/`autoOpen`/`degeneretteResolve`) + router (`doWork`) overhead, then measured.
- GAS-02: re-peg all keeper bounties to flat-per-tx per-category break-even @0.5 gwei (BURNIE-denominated), per-item MARGINAL (CR-01 rule).
- GAS-04: keep the 1/2/4/6 stall ladder ADVANCE-ONLY; any ceiling extension faucet-bounded.
- GAS-05: WR-01-style round-trip guard — no positive-EV self-crank loop under the flat-per-tx model.
- GAS-06: rename `autoResolve`→`degeneretteResolve` + re-peg its bounty to a flat ~1-BURNIE "lose" (≥3 non-WWXRP gate).
- **Seed 1 + Seed 2** (USER-included 2026-05-27): keeper-specialized batch-buy path — aggregate shared-slot DGNRS affiliate writes (Seed 1) + replace `batchPurchase` per-player try/catch isolation with pre-validation (Seed 2). Touches the affiliate MONEY path → own delta-audit + liveness (no-brick) tests.

Out of scope (do NOT touch):
- Re-opening the 330 keeper-router architecture or the applied diff.
- The router-fold of `degeneretteResolve` (architecturally blocked — caller-supplied `(players[], betIds[])` has no O(1) on-chain discovery; router stays buy/open/advance only).
- Any RNG/freeze/result change — these are INCENTIVE-number and gas-shape changes only.

</domain>

<decisions>
## Implementation Decisions

### D-01 — GAS-01 worst-case marginal gas derivation (theoretical FIRST, then measured)
- Derive the theoretical worst-case (max-laden) marginal gas FIRST, per keeper category + the `doWork()` router overhead, BEFORE measurement (`feedback_gas_worst_case`).
- Then measure via a NEW `test/gas/RouterWorstCaseGas.t.sol` using the established `*WorstCaseGas.t.sol` idiom: Foundry `--isolate` + `vm.snapshotGas` section snapshots, amortized per-item over N≥32 items. NEVER `forge test --gas-report` numbers as the peg, NEVER a single-item total.
- This sizes the D-07 flat-per-tx model: per-category max-laden gas @0.5 gwei fixes the `1×` base unit + the `1 / 1.5 / 2` per-category ratios + the open `KNEE (~5)`.

### D-02 — GAS-02 re-peg to break-even @0.5 gwei (per-item MARGINAL)
- Calibrate the AfKing `GAS-331 PLACEHOLDER` constants from the D-01 data: `BOUNTY_ETH_TARGET` (break-even ETH target), `ADVANCE_RATIO_NUM=2`, `BUY_RATIO_NUM/DEN=3/2`, `OPEN_KNEE=5`, `DOWORK_BATCH=100` (`contracts/AfKing.sol:845-854`).
- CR-01 self-crank-faucet rule: peg the **per-item max-laden MARGINAL**, NEVER a per-call/single-box total. The open knee kills the small-batch corner (`1× × min(opened, KNEE)/KNEE`).
- Conversion math is level-invariant: `unit = (BOUNTY_ETH_TARGET * PRICE_COIN_UNIT) / mintPrice` (`AfKing.sol:869-870`); confirm invariance across mintPrice levels.
- Constants land under a **USER-approved gate** (v46 Phase 319 precedent `e4014f91`/`795e679d`).

### D-03 — GAS-04 stall multiplier (ADVANCE-ONLY, faucet-bounded)
- Keep the 1/2/4/6 stall ladder ADVANCE-ONLY (the autoBuy stall ladder was deleted per D-07). Never lower existing thresholds.
- Any extreme-stall ceiling extension is added ABOVE the 2h tier and capped against the finite faucet pool. Whether to extend (and by how much) is DECIDED FROM the GAS data — does 6× cover stressed mainnet gas at a plausible deep stall? (Execution-time decision, derived not pre-set.)

### D-04 — GAS-05 round-trip guard (no positive-EV self-crank)
- WR-01-style regression guard proves no positive-EV self-crank loop under the flat-per-tx model. The hot corner: the open small-batch + low-gas case — per-box reward below the knee (`1×/KNEE`) ≤ a one-box tx's 0.5-gwei gas → a tiny mid-day open is −EV.
- Faucet bound holds; self-exclude + ETH-work-gate intact.
- Exploitability is judged against REAL prevailing gas (5–50+ gwei) + flip-credit illiquidity, NOT the 0.5-gwei peg ref (`feedback_bounty_exploit_uses_real_gas_not_peg_ref`).

### D-05 — GAS-06 `degeneretteResolve` rename + flat ~1-BURNIE re-peg
- Rename `autoResolve`→`degeneretteResolve` (+ internal `_autoResolveBet`→`_degeneretteResolveBet`, interfaces, tests).
- Re-peg `RESOLVE_FLAT_BURNIE` (`DegenerusGame.sol:1543`, currently `1e18`) from per-item break-even to a flat literal ~1-BURNIE flip-credit per tx (count-independent), gated at **≥3 successfully-resolved NON-WWXRP bets**: revert `NoWork()` on zero work; 1–2 resolved → resolved but UNPAID (lean = do-not-revert so a trailing tail is never stranded).
- WWXRP excluded from BOTH the gate count AND the reward (AUTO-04). AUTO-02 probe + per-item isolation + self-resolve (REW-04) preserved. Stays a SEPARATE call (NOT in the router).
- Anti-exploit basis (corrected — NOT the 0.5-gwei peg ref): the keeper pays REAL tx gas every call while ~1 BURNIE illiquid flip-credit ≤ `mintPrice/1000` ETH (≤0.00024 ETH even at the 0.24-ETH milestone) → every qualifying tx is a net loss at any realistic gas price; the ≥3 gate widens the margin.
- GAS sanity check (NOT a blocker): confirm ~1 BURNIE stays below real 3-resolution gas across the low-gas/high-mintPrice corner factoring flip-credit illiquidity; only lower the constant or add a scaled gate if a realistic corner flips positive. SPEC D-05f already verified no invariant requires losing-bet resolution before dropping the break-even incentive.

### D-06 — Seed 1: aggregate shared-slot DGNRS affiliate writes across the keeper batch
- The WHOLE keeper batch credits the SAME `bytes32("DGNRS")` affiliate accumulator (KEEP-04; `DegenerusGame.sol` `_purchaseFor`/`_batchPurchaseUnit` ~`:1781` → two-tier 75/20/5 SDGNRS/VAULT, fixed addresses). Sum shared-slot contributions in memory across the batch + ONE SSTORE at the end (saves ~N−1 writes).
- ONLY shared-slot rewards aggregate. Player-specific credits (each player's own DGNRS alloc / claimable / BURNIE — distinct recipients) CANNOT be coalesced.
- Must sum only SUCCESSFUL (non-reverted) units. Extra coalesce possible if the SDGNRS/VAULT standing subs are processed in the same tx (buy-credit + affiliate-payee-credit share a slot).
- Quantify the win: count the affiliate module's per-buy SSTOREs.

### D-07 — Seed 2: replace `batchPurchase` per-player try/catch isolation with pre-validation
- Replace `batchPurchase`'s per-player `this._batchPurchaseUnit{value: slice}(...)` external-self-CALL try/catch with cheaper handling: pre-validate each player so the unit CANNOT revert, then call internally (no try/catch).
- Enumerate ALL `_batchPurchaseUnit` revert sources and pre-gate them (mirror the autoOpen RD-5 entry-gate technique from 330; AfKing `_resolveBuy` already does funding pre-checks).
- Pairs with Seed 1: the units RETURN their affiliate contribution; aggregate writes after the loop. Cleanest shape = a **keeper-specialized batch path** separate from the player-facing `_purchaseFor` (leaves the normal player path untouched).

### HARD CONSTRAINT (security floor — `feedback_security_over_gas`)
- A reverting / funding-skipped player must NEVER brick the whole keeper batch. Any try/catch replacement MUST preserve that liveness — the per-player isolation is a SECURITY property, not just hygiene.
- The affiliate money path (Seed 1 + Seed 2) needs its OWN delta-audit + tests (byte-identical money outcomes vs the pre-seed path; no double-credit; no skipped-player drain).

### Process / contract-boundary gates
- This is a CONTRACT phase. The plan that lands mainnet `.sol` constants/rename/seed code MUST be `autonomous: false` — HARD STOP at the contract boundary; confirm direction before executing (`feedback_pause_at_contract_phase_boundaries`).
- Batch ALL contract edits into ONE diff, present for ONE approval at the end (`feedback_batch_contract_approval`); no contract commit without hand-review (`feedback_wait_for_approval`); the commit-guard hook blocks commits while `contracts/*.sol` is dirty.
- INCENTIVE/gas-shape changes only — must NOT change RNG/freeze/resolution RESULTS. The rename must produce byte-identical resolution results (TST-05, Phase 332, proves this).
- Maximal storage packing within the security floor (`feedback_maximal_variable_packing`).
- `test/`, `contracts/test/`, `.planning/` commit freely; only mainnet `contracts/*.sol` are gated.

### Claude's Discretion
- The new gas-harness file structure / section-snapshot granularity (follow the `*WorstCaseGas.t.sol` idiom).
- The exact safety rounding applied above break-even when landing constants (round up for keeper-liveness margin, per the 319 precedent).
- Whether the keeper-specialized batch path is a new function vs a parameterized internal helper — decide from the revert-source enumeration.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### v49 SPEC design-lock (the locked decisions this phase calibrates)
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-SPEC.md` — D-07 flat-per-tx model, ratios, knee, ≥3 gate.
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-CONTEXT.md` — locked SPEC decisions.
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-ROUTER-ADVANCE.md` — router/advance call-graph attestation.
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-DEGENERETTE-RESOLVE.md` — degeneretteResolve call-graph attestation.

### Applied 330 IMPL (the subject the peg measures against — commit `63bc16ca`)
- `.planning/phases/330-impl-the-one-batched-contract-diff-router-advance-rework-mic/330-VERIFICATION.md`
- `.planning/phases/330-impl-the-one-batched-contract-diff-router-advance-rework-mic/330-ROUTER-REDESIGN-INTENT.md`
- `.planning/phases/330-impl-the-one-batched-contract-diff-router-advance-rework-mic/330-0*-SUMMARY.md` (what was built)

### Contracts (the placeholders to calibrate + the seed surfaces)
- `contracts/AfKing.sol:845-877` — `doWork()` + the `GAS-331 PLACEHOLDER` constants (`DOWORK_BATCH`, `ADVANCE_RATIO_NUM`, `BUY_RATIO_NUM/DEN`, `OPEN_KNEE`) + the `BOUNTY_ETH_TARGET`/`PRICE_COIN_UNIT`/`mintPrice` conversion.
- `contracts/DegenerusGame.sol:1540-1543` — `RESOLVE_FLAT_BURNIE` placeholder; `_purchaseFor`/`_batchPurchaseUnit` ~`:1781` (KEEP-04 DGNRS affiliate write path — Seed 1/2 surface); `batchPurchase` try/catch loop (Seed 2 surface).
- `contracts/modules/DegenerusGameDegeneretteModule.sol` — degenerette resolution path (GAS-06 rename + payout-table invariance).

### Gas-harness idiom (for the new `RouterWorstCaseGas.t.sol`)
- `test/gas/CrankOpenBoxWorstCaseGas.t.sol`
- `test/gas/CrankResolveBetWorstCaseGas.t.sol`
- `test/gas/SweepPerPlayerWorstCaseGas.t.sol`

### Peg-calibration precedent
- v46 Phase 319 GAS — USER-gated peg landing (commits `e4014f91`/`795e679d`); the CR-01 per-box marginal + WR-01 round-trip guard origin.

### Phase requirements
- `.planning/ROADMAP.md` — Phase 331 section (Goal + 5 Success Criteria).
- `.planning/REQUIREMENTS.md` — GAS-01, GAS-02, GAS-04, GAS-05, GAS-06.

</canonical_refs>

<specifics>
## Specific Ideas

- Placeholder constants to calibrate (exact, current values): `DOWORK_BATCH=100`, `ADVANCE_RATIO_NUM=2`, `BUY_RATIO_NUM=3`/`BUY_RATIO_DEN=2`, `OPEN_KNEE=5` (`AfKing.sol`); `RESOLVE_FLAT_BURNIE=1e18` (`DegenerusGame.sol`).
- Peg target: break-even at **0.5 gwei** (`AUTO_GAS_PRICE_REF` peg). Reward unit = `BOUNTY_ETH_TARGET * PRICE_COIN_UNIT / mintPrice`.
- Measurement: `forge` `--isolate`, `vm.snapshotGas` section snapshots, N≥32 amortization, per-item marginal.
- The ≥3 non-WWXRP `degeneretteResolve` gate reverts `NoWork()` only at zero work; 1–2 resolved = unpaid-but-not-reverted.

</specifics>

<deferred>
## Deferred Ideas

- Router-fold of `degeneretteResolve` — architecturally blocked (caller-supplied `(players[], betIds[])`, no O(1) discovery). The "one button" unification is a frontend concern. Router stays buy/open/advance only.
- TST-05 (proving the rename + re-peg byte-identical) is Phase 332, not here — though this phase confirms the exact `RESOLVE_FLAT_BURNIE` constant is sub-real-gas.

</deferred>

<scope_fence>
## Scope Fence

- Do NOT re-open or re-architect the 330 keeper-router diff.
- Do NOT change RNG, freeze windows, payout tables, or resolution RESULTS — incentive numbers + gas shape only.
- `degeneretteResolve` stays a SEPARATE call; do NOT fold it into `doWork()`.
- Seed 2 = a keeper-specialized batch path; do NOT alter the normal player-facing `batchPurchase`/`_purchaseFor` semantics.
- Liveness floor: no single player can brick the keeper batch (security property, not negotiable for gas).

</scope_fence>

<corrections>
## CORRECTION PASS (2026-05-27) — load-bearing fixes to the committed 331-01/331-04 conclusions

A correction pass re-measured the BUY + OPEN legs and re-derived the calibration. The committed
`331-GAS-DERIVATION.md` + `331-CALIBRATION.md` carry inline correction banners; this CONTEXT note
records the corrections for downstream agents (TST 332 / the gated 331-05). Harness commit `322fd972`.

1. **BUY marginal was measured on the REVERT-CATCH path (~40,224 WRONG → ~261,809 / clean N32 ~255,614
   CORRECT).** The old harness asserted "the buy landed" via AfKing's `lastAutoBoughtDay` day-stamp
   (`AfKing.sol:744`), which is set BEFORE the batched `IGame.batchPurchase` fires. The keeper buy is
   forced-lootbox (`_purchaseFor(player, 0, slice, "DGNRS", payKind)`, ticketQuantity=0,
   `DegenerusGame.sol:1806`), so a slice < `LOOTBOX_MIN (0.01 ether)` (`DegenerusGameMintModule.sol:1011`)
   REVERTED inside `batchPurchase`'s per-player try/catch (`:1773-1780`) while the day-stamp falsely
   passed. Corrected harness verifies the buy LANDED via `lootboxEthBase[index][player] > 0` and funds
   DirectEth slice == mp == LOOTBOX_MIN. **BUY is the MOST expensive per-item leg (~262k), not the
   cheapest** — inverting the 331-04 "buy cheapest → richest 1.5x" rationale.

2. **OPEN worst case omitted the whale-pass branch (the GAP).** A box-open whose boon roll selects the
   whale-pass boon (type 28, `BOON_WHALE_PASS`) runs `_activateWhalePass` (`DegenerusGameLootboxModule.sol:1240-1261`),
   a 100-iter `_queueTickets` loop — **~5,396,350 gas/box** (~60x the typical ~89k). RARE (boon weight
   8; needs a sizeable box / the >5 ETH `LOOTBOX_CLAIM_THRESHOLD` raises the budget). The >5 ETH "defer
   to claim" branches (`DegenerusGameJackpotModule.sol:1966/2029`, `DegenerusGameDecimatorModule.sol:583`)
   are the JACKPOT/DECIMATOR payout paths, NOT the per-box open path. Typical box marginal unchanged.

3. **Ceiling is 16.7M, not 30M.** Target ~9M average for the default box buy/open leg.

4. **`DOWORK_BATCH=100` SPLIT → `BUY_BATCH=50` + `OPEN_BATCH=100`** (331-GAS-DERIVATION §5.1). Buy at
   100 = ~26M > the 16.7M HARD ceiling; 50 ≈ 13.1M. Open at 100 ≈ 9M (target). The all-whale-pass
   corner (100×5.4M) exceeds 16.7M and is USER-ACCEPTED (boon rarity). The 331-05 diff is NO LONGER
   comment-only — the split is behavioral (gated).

5. **Reward-ratio re-analysis:** ratios STILL faucet-safe at the fixture B; advance-6x STILL the
   binding faucet ceiling (8.78e12 wei); the buy faucet ceiling ROSE (less binding). Buy
   under-reimbursement keeper-incentive implication FLAGGED (the buy leg is the binding INCENTIVE
   consideration if B is tuned upward — pulls against the faucet ceiling). Ratio values frozen (out of scope).

6. **rngLock disposition (USER-resolved):** BUYING lootboxes during rngLock is FINE (commit-before-
   reveal; `batchPurchase` has NO rngLock guard by design — RD-2). OPENING is blocked (autoOpen `:1671`
   no-op, openLootBox `:2162` revert, `:1683` word-gate). Two stale artifacts FLAGGED for 331-05: the
   `batchPurchase` docstring `:1739` falsely claims an rngLock entry-check (comment-only fix); and
   `testBatchPurchaseRngLockedRejectsWholeBatchAtEntry` (`CrankNonBrick.t.sol:360`) asserts the
   unwanted abort + FAILS against the live contract (a known baseline failure — asserts behavior the
   contract correctly does NOT have; NOT fixed in this pass).
</corrections>

---

*Phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca*
*Context synthesized: 2026-05-27 (plan-directly path — 329 SPEC complete, design locked; USER included both batch-purchase gas seeds)*
*Correction pass appended: 2026-05-27 (BUY revert-catch fix + whale-pass open branch + 16.7M ceiling + split caps + reward-ratio re-analysis + rngLock disposition)*
