# Phase 335: IMPL — The ONE Batched Contract Diff (WHALE + AFSUB + MINTDIV-if-real) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-28
**Phase:** 335-impl-the-one-batched-contract-diff-whale-afsub-mintdiv-if-re
**Areas discussed:** gameOver-forfeit codification, Test-fixture migration policy, OPEN_BATCH flat-sizing re-confirmation method

> **Why so few areas:** Phase 334's 7-artifact SPEC (D-01..D-23, the 5-step edit-order map, the writer-vs-reader `_queueTickets` reconciliation, the WHALE-04 freeze proof, the MINTDIV-01 REACHABLE verdict, the grep-attestation table) locked virtually every design decision. The remaining gray areas were IMPL policy decisions — not design choices.

---

## Gray-area selection (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| Local-test scope | What counts as 'locally compiled/tested' before the HARD STOP? forge build only / + spot tests / + full forge test / + inline fixture repair. | |
| gameOver-forfeit | D-23 records forfeit, but deployed claimWhalePass only blocks on _livenessTriggered, not gameOver. Inherent / explicit revert / proactive zero-out at gameOver()? | ✓ |
| Test-fixture migration | Deleting paidThroughDay/burnForKeeper compile-breaks tests that read them. contracts/-only / minimal compile-fix / broader test/ alignment. | ✓ |
| OPEN_BATCH re-confirm | SC2 demands flat OPEN_BATCH re-confirmed under uniform O(1) opens. Math-only re-derivation / fresh forge gas measurement. | ✓ |

**User's choices:** gameOver-forfeit, Test-fixture migration, OPEN_BATCH re-confirm. (Local-test scope was skipped; Claude defaulted it to `forge build` + full `forge test`, NEW reds reconciled inside 335 per the cascade from the test-fixture-migration choice.)

---

## gameOver-forfeit codification

| Option | Description | Selected |
|--------|-------------|----------|
| Inherent forfeit (no change) | Keep deployed behavior: claim succeeds but queues phantom tickets that never materialize. Trusts no-future-levels structural property. Zero IMPL change. | (effectively selected — see below) |
| Explicit revert if gameOver | Add `if (gameOver) revert E();` to claimWhalePass. Tightens semantics, saves a useless storage write. One-line guard. | |
| No-op success: clear, don't queue | After gameOver, clear whalePassClaims[player] but skip queue + stats. Player bookkeeping zeroes without spurious writes. | |
| Proactive zero at gameOver() | Sweep whalePassClaims to zero when flipping gameOver=true. Requires iteration / generation counter. | |

**User's response (verbatim):** *"doesnt livenesstriggered already stop claimwhalepass?"*

**Resolution:** YES. Claude traced the transitivity:
1. `gameOver = true` is set in exactly ONE place: `GameOverModule.handleGameOverDrain:145`.
2. That code path is reachable only via `_handleGameOverPath` (`AdvanceModule:596`), which early-returns at `:522` if `_livenessTriggered() == false`.
3. → gameOver flips ONLY when `_livenessTriggered() == true` (and only when `lastPurchaseDay == false && jackpotPhaseFlag == false`, the early-out at `Storage:1214`, AND a day-stall or VRF-stall is active).
4. Post-gameOver, level is frozen, `purchaseStartDay` is frozen, and the active-phase flags cannot be re-flipped (advance is blocked). The triggering condition only gets staler.
5. → `_livenessTriggered()` returns **true forever** post-gameOver → `claimWhalePass` (`WhaleModule:1019`'s `if (_livenessTriggered()) revert E();`) reverts forever.

**Outcome:** Decision D-IMPL-01 — **NO IMPL CHANGE** for gameOver-forfeit. D-23 is satisfied by the existing structural guard. The transitivity trace is now in CONTEXT.md as the load-bearing attestation for 338's economic-analyst.

**Notes:** This was a genuinely sharp question that saved both an IMPL edit and a defensive-revert-on-a-frozen-critical-path risk. The "inherent forfeit" option is the right answer, but the reasoning behind it (the gameOver-is-only-reachable-via-liveness structural property) is what makes it sound — not the "phantom tickets never materialize" framing in the original option description.

---

## Test-fixture migration policy

| Option | Description | Selected |
|--------|-------------|----------|
| Minimal compile-fix only | Touch test/ ONLY at compile-error sites — stub/comment broken assertions with `// V50-REMOVED: see 336` markers. forge build green; the marked test bodies may red on forge test. 336 inherits a clean list to migrate. | |
| Compile-fix + AfKing rewrite | Compile-fix + rewrite the AfKing test bodies (subscription/concurrency/funding-waterfall) to assert validThroughLevel/refresh-or-evict semantics in 335 itself. Pushes most of TST-02 into 335. | |
| Full alignment in 335 | Migrate ALL 7 test files (AfKing + whale-pass open/claim equivalence + the OPEN_BATCH gas oracle) in 335. Largest single diff; conflates 'apply the contract change' with 'prove behavioral correctness'. | ✓ |

**User's choice:** Full alignment in 335.

**Notes:** Sets the cascade that:
- The ONE batched diff spans `contracts/*.sol` + `test/*.t.sol` (~70 references across 7 test files migrate in 335), under the same USER hand-review HARD STOP.
- v49 precedent: Phase 330 IMPL `63bc16ca` shipped 5 contracts + 9 tests in one USER-approved batch. 335 follows the same pattern.
- 336's TST-01 (whale-pass equivalence) and TST-02 (AfKing pass-gated tests) substantially MOVE INTO 335; 336 narrows to the freeze-fuzz extension of `RngLockDeterminism.t.sol`, the MINTDIV same-traits regression (TST-03), and the formal NON-WIDENING attestation + v50.0 baseline ledger (TST-04).
- This also forces D-IMPL-03 (Local-test scope = full `forge test` green-or-known-baseline at HARD STOP) by construction — full alignment means the tests follow the new code in the same diff, so NEW reds are a v50 regression signal, not a fixture-migration artifact.

---

## OPEN_BATCH flat-sizing re-confirmation method

| Option | Description | Selected |
|--------|-------------|----------|
| Math-only re-derivation | Cite 331's ~89K typical-box figure, multiply by chosen flat OPEN_BATCH, attest under 16.7M with margin. No new measurement. | |
| Fresh measurement via KeeperOpenBoxWorstCaseGas (Recommended) | Re-run the existing gas harness against the v50.0 contract (auto-compiles under full alignment), record the new per-box figure, pick OPEN_BATCH from the actual measurement, attest under 16.7M. | ✓ |
| Fresh measurement + new worst-case-N harness | New forge test that opens N boxes and binary-searches OPEN_BATCH such that total < 16.7M with margin. Most rigorous; new code; arguably overkill. | |

**User's choice:** Fresh measurement via `KeeperOpenBoxWorstCaseGas`.

**Notes:** Leverages the existing harness (no new gas-measurement code). The flat OPEN_BATCH is *picked from the measurement* — the SUMMARY records the measured per-box figure, the chosen OPEN_BATCH, and the binding `chosen × measured ≤ 16.7M − headroom` attestation. The retired surfaces (`OPEN_NORMAL_GAS_UNIT = 90_000` at `:1561`, the `gasleft()` weighting at `:1687`, the `weighted += used / OPEN_NORMAL_GAS_UNIT` math at `:1728`) are deleted in the same diff. If the measurement reveals a ceiling overshoot under any reasonable OPEN_BATCH, STOP and re-spec — that would be a freeze-floor-class signal that WHALE-01's uniform-O(1)-opens assumption broke.

---

## Claude's Discretion

The Phase-334 SPEC's "Claude's Discretion" items flow forward unchanged (NOT re-asked during discuss-phase):

- **`claimWhalePass` entrypoint home (D-01):** the deployed `claimWhalePass(address)` at `WhaleModule:1018` is the existing public entrypoint (D-20). Whether to add a `DegenerusGame` external fn delegating to it, or to expose the module-direct path, is the planner's call.
- **`validThroughLevel` field width (D-11):** in-place repurpose of `Sub.paidThroughDay` (offset 5, `AfKing.sol:89`). Keep uint32 (zero packing churn) OR narrow to uint24 (mirror `level`'s width) — both acceptable.
- **`lazyPassHorizon` view name + signature (D-11):** the new per-pass-type horizon view on the Game facade; the planner picks the exact name and the `IGame` iface decl AfKing reads through.
- **Within-cluster ordering for the AfKing + BurnieCoin pair (D-18 / 334-IMPL-EDIT-ORDER-MAP §1 Step 5):** atomic-diff property makes either order safe; planner picks.

## Deferred Ideas

Recorded in CONTEXT.md `<deferred>`:
- Full dedup of the two MintModule loops (rejected for v50; future cycle).
- Running the external RNG-audit protocol through Gemini/ChatGPT (337 package-only; running is OUT of v50.0).
- The freeze-fuzz extension of `RngLockDeterminism.t.sol` (TST-01 freeze leg; lands at 336, not 335).
- The MINTDIV same-traits-across-split regression test (TST-03; lands at 336, not 335).
- The NON-WIDENING attestation + v50.0 baseline ledger replacing v49's `666/42/17` (TST-04; lands at 336, not 335).
- A proactive `refreshPass()` entrypoint (explicitly rejected at SPEC, D-10).
