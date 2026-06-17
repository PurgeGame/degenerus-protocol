# Phase 410: FOUNDATION — Subject Freeze & Green Baseline - Context

**Gathered:** 2026-06-16
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped — mechanical phase, ROADMAP goal is the spec)

<domain>
## Phase Boundary

Byte-freeze the v66 audit subject and capture a documented GREEN baseline oracle that is the
regression floor every later lead is reproduced against.

**Subject (pinned):**
- Contract commit: `42c8e9c6` (= origin/main `bb0912a6` + the additive CurseChanged indexer-parity emit).
- `contracts/` tree hash: `0dd445a64cfe7e096427d44f058c40abb1233b5f` — the canonical freeze anchor.
  Doc/test commits on top do not touch `contracts/`, so freeze is verified by this tree hash, not by HEAD.

This phase covers FOUND-01 (freeze anchor recorded) and FOUND-02 (green baseline oracle documented;
pre-existing reds catalogued as carried-not-new).
</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
- Baseline = the full `forge test` suite (primary net) + the hardhat `npm test` suite (parity).
- Record forge pass/fail/skip totals and any failing/skipped test identities; record hardhat pass/fail.
- Do NOT run `hardhat compile --force` (regenerates `ContractAddresses.sol` and breaks the forge fixture).
- No contract changes in this phase (audit-only); freeze must remain byte-stable through milestone close.
</decisions>

<code_context>
## Existing Code Insights
- Subject is post-rename (v65) HEAD + the v66 pre-freeze CurseChanged emit (42/42 curse tests already green,
  EIP-170 OK, packed bytes byte-identical).
- Prior milestone baselines for reference: v65 forge 889/0/110 identical; the emit added only the LOG to the
  curse mutators (no test regression expected).
</code_context>

<specifics>
## Specific Ideas
- Deliverable: `410-FOUNDATION.md` (freeze anchor + baseline oracle) + `410-VERIFICATION.md`.
- The baseline oracle table must let a later phase diff its run against this one by name, not just raw counts.
</specifics>

<deferred>
## Deferred Ideas
None — discuss skipped.
</deferred>
