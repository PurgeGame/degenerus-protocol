# Phase 416: FOUND — Subject Freeze & Green Baseline - Context

**Gathered:** 2026-06-17
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped — audit foundation phase; the ROADMAP goal + success criteria are the spec)

<domain>
## Phase Boundary

Byte-freeze the v67.0 audit subject at HEAD and capture a documented GREEN baseline oracle (forge full-suite pass/skip counts + hardhat parity) as the v67 regression baseline. The subject `contracts/` tree is `0dd445a6` — byte-identical to the v66.0 frozen subject (no contract change has landed since; v65 rename + v66 audit are upstream). This phase does not hunt; it establishes the frozen anchor + green oracle every later phase reads/regresses against.

Requirements: FOUND-01 (freeze anchor recorded), FOUND-02 (green baseline captured + carried-reds catalogued).
</domain>

<decisions>
## Implementation Decisions

### Claude's Discretion
- Freeze anchor = `contracts/` tree hash `0dd445a6` (the audit subject is the TREE, which is unchanged since v66; the HEAD commit has advanced only via gitignored `.planning/` doc commits).
- Baseline = run the full forge suite + the hardhat suite fresh; record actual pass/fail/skip. Because the tree is byte-identical to v66's post-414 subject, the forge baseline is EXPECTED to match v66's closing count (~899 pass / 0 fail / ~109 skip) and the hardhat carried-floor; this phase VERIFIES that rather than assuming it.
- Any pre-existing reds are catalogued as carried-not-new (the known JS reds: DegenerusStonk/DGNRS pool-BPS, DGNRSLiquid deployWithGameOver — historically pre-existing).
</decisions>

<code_context>
## Existing Code Insights

- Subject = `DegenerusGame.sol` (2,485 L) + 13 `contracts/modules/*` delegatecall modules (~15.5k L) + synchronous callees (FLIP/Coinflip/Vault/sDGNRS/Affiliate).
- foundry.toml: via_ir=true, optimizer_runs=1000, evm_version=osaka (cold builds are slow).
- v66 baseline precedent: forge 889/0/110 at freeze (410), ~899/0/109 after the +10 test-net fixes (414).
</code_context>

<specifics>
## Specific Ideas

No grey areas — mechanical foundation phase. Deliverable = a `416-BASELINE.md` recording the freeze anchor + the measured forge/hardhat baseline + the carried-reds catalogue.
</specifics>

<deferred>
## Deferred Ideas
None.
</deferred>
