# Phase 376: IMPL — The ONE Batched Contract Diff (AFPAY + PACK + CURSE + SMITE) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-06
**Phase:** 376-impl-the-one-batched-contract-diff-afpay-pack-curse-smite
**Areas discussed:** Curse entrypoint placement

---

## Framing

The substance of this IMPL phase is locked by `.planning/SPEC-V61-DESIGN-LOCK.md` (the Phase-375 design-lock): D-01..D-05, the `purchaseWith`-dead / self-smite verdicts, all 29 re-attested anchors (4 corrected), exact signatures, and the full Track A/B producer-before-consumer edit order. So discussion was scoped to HOW-to-execute + the contract-boundary review posture, NOT what to build.

### Area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Done-definition at hard stop | forge-build-clean only vs also compile/run the existing suite for non-regression | |
| Hand-review packaging | raw git diff vs per-track/per-REQ annotated walkthrough + diff | |
| Executor plan granularity | one monolithic plan vs Track A/Track B sub-plans | |
| Curse entrypoint placement | where `decurse`/`smite` external entrypoints live vs the Game code-size ceiling | ✓ |

**User's choice:** Curse entrypoint placement only. The other three defaulted to established precedent (SC5 forge-build-clean gate · one batched diff for one approval · planner-chosen granularity).

---

## Curse entrypoint placement

Grounded on the scouted topology: `MintStreakUtils` is an abstract base inherited by both the Game and the delegatecall modules; `claimWinnings` is a direct Game function. So only the two new external entrypoints `decurse`/`smite` need a host (the mutators/cap/`curseCountOf`/APPLY are base helpers; the SET hook stays inline in `claimWinnings`).

| Option | Description | Selected |
|--------|-------------|----------|
| Stub → existing module | Thin Game dispatch stubs delegatecalling into an existing module (GameAfkingModule or MintModule). Keeps the Game lean (code-size safe); matches the SPEC's "new Game dispatch stubs" wording. Planner picks the exact module. RECOMMENDED. | ✓ |
| Inline in DegenerusGame | Define `decurse`/`smite` directly in DegenerusGame.sol next to `claimWinnings` — simplest wiring, but adds ~2 external fns of Game bytecode against the 24,576-byte ceiling. | |
| New GameCurseModule | A dedicated new delegatecall module — cleanest cohesion, zero Game bloat, but a new module + ContractAddresses address + interface + deployment wiring for ~2 small fns (overkill). | |

**User's choice:** Stub → existing module (the recommended option).
**Notes:** Exact host module deferred to the planner by code-size headroom + cohesion — preference order GameAfkingModule (afking-immunity cohesion + stub precedent), then MintModule (cure-adjacency + already burns BURNIE). The intrinsic guardrail (the reason placement mattered): `forge build` must confirm the Game stays under 24,576 bytes after the stubs land; if over, raise it as a blocker at hand-review, do not silently work around.

---

## Claude's Discretion

- Exact host module for `decurse`/`smite` (per the preference order above).
- Accessor-layer physical home (PACK-01); how `_maybeCurse` SET hooks into `claimWinnings`; `_recordLootboxMintDay` relocation to the MintStreakUtils base (CURSE-05); `contracts/test/SettleClaimableShortfallTester.sol` signature update for build-cleanliness.
- Plan granularity (one plan vs Track A / Track B) and hand-review packaging detail — defaulted to precedent.

## Deferred Ideas

None — discussion stayed within the 376 IMPL scope.
