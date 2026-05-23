# Phase 312: IMPL — VRF-Rotation Fix (Single Batched USER-APPROVED Diff) (IMPL) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-23
**Phase:** 312-impl-vrf-rotation-fix-single-batched-user-approved-diff-impl
**Areas discussed:** Re-issue helper, _setVrfConfig visibility, Zero-guard at MintModule:686

---

## Re-issue: helper vs inline

The re-issue (D-01/D-02) re-fires `requestRandomWords` on the new coordinator. 4 inline copies exist
today (mid-day @1102/1143 → `VRF_MIDDAY_CONFIRMATIONS`; daily @1587/1605 → `VRF_REQUEST_CONFIRMATIONS`;
byte-identical otherwise). The re-issue needs BOTH variants → inlining adds a 5th+6th copy.

| Option | Description | Selected |
|--------|-------------|----------|
| Helper, new code only | Extract `_requestVrfWord(uint16 confirmations)`; route only the NEW re-issue branches through it. Single-sources the new code without churning the 4 working sites in a security diff. | ✓ |
| Helper + retrofit all | Same helper, also route the existing 4 sites through it → zero inline copies, maximal single-source-of-truth. Larger diff (all in-module, low-risk). | |
| Inline, no helper | Mirror the existing inline pattern; add 2 more struct copies (6 total). Smallest diff; grows the drift surface. | |

**User's choice:** Helper, new code only (→ D-06).
**Notes:** Applies the user's standing single-source-of-truth ethos (Phase 310 D-01/D-02; the 311 D-04
dedup) to the NEW code only — keeps the security-critical diff minimal and reviewable. Full retrofit of
the 4 existing sites considered and deferred (CONTEXT Deferred Ideas).

---

## _setVrfConfig visibility

D-04's shared 3-field config-write helper. Both callers (`wireVrf`, `updateVrfCoordinatorAndSub`) live
in the SAME module (`DegenerusGameAdvanceModule`).

| Option | Description | Selected |
|--------|-------------|----------|
| private | Both callers same-contract → `private` suffices; least-privilege + frozen-no-future-proofing. SPEC's `internal` (310 cross-module precedent) doesn't transfer here. | |
| internal (SPEC literal) | Keep SPEC §4.2 verbatim. Functionally equivalent here; SPEC fidelity for this execution phase. | ✓ |

**User's choice:** internal (SPEC literal) (→ D-07).
**Notes:** Chose SPEC fidelity over the marginal `private` tightening; no SPEC override on visibility.

---

## Zero-guard at MintModule:686

Defense-in-depth `entropy == 0` guard at the Scenario-A consumer. SPEC §3.4 deliberately omitted it
(re-issue fills [N] structurally; §5 confirmed no residual orphan path).

| Option | Description | Selected |
|--------|-------------|----------|
| No guard (honor SPEC) | Honor the locked design; structural fill makes entropy==0 unreachable; 313 VTST-01/03 prove it; keeps the diff inside the ROADMAP touch set (AdvanceModule only). | ✓ |
| Add the guard | Cheap belt-and-suspenders circuit-breaker against any future re-orphaning refactor. Cost: expands diff to MintModule.sol + revisits a locked SPEC decision. | |

**User's choice:** No guard (honor SPEC) (→ D-08).
**Notes:** `MintModule.sol` therefore untouched this phase; the structural guarantee is proven by Phase
313 regression rather than a runtime guard.

---

## Claude's Discretion

- Exact `_requestVrfWord` signature/visibility (D-06) — confirmations param type matches the
  `VRFRandomWordsRequest.requestConfirmations` field / `VRF_*_CONFIRMATIONS` constants; lean `private` to
  match the existing AdvanceModule re-fire helpers (`_requestRng`/`_tryRequestRng`).
- The if/else branch structure inside `updateVrfCoordinatorAndSub` and the flag-read mechanics, subject
  to the verification items (VER-02/VER-03).

## Deferred Ideas

- Full retrofit of the 4 existing inline `requestRandomWords` sites through `_requestVrfWord` — deferred
  (D-06 scoped to new code only).
- Defense-in-depth zero-guard at `MintModule:686` — declined (D-08; honor SPEC §3.4).
- Queue+apply rotation (`pendingVrfRotationPacked`) — rejected by SPEC §6.1.
- Belt-and-suspenders gate-independent orphan backfill — SPEC §6.2 deferred.
- Non-VRF v44 backlog, V-081 regression, jackpot pending-pool new work — out of scope for v45.0.
