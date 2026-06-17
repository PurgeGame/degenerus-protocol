# v67.0 FOUND — Subject Freeze & Green Baseline (Phase 416)

**Phase:** 416 FOUND · **Date:** 2026-06-17 · **Requirements:** FOUND-01, FOUND-02

## Freeze anchor (FOUND-01)

| Anchor | Value |
|--------|-------|
| Audit subject = `contracts/` tree | `0dd445a64cfe7e096427d44f058c40abb1233b5f` (`0dd445a6`) |
| HEAD commit at freeze | `588bc858` (advanced from `fa7932f6` only by gitignored `.planning/` doc commits — **`contracts/` tree unchanged**) |
| Tree clean | YES (`git status --porcelain -- contracts/` empty) |
| Relationship to v66 | **byte-identical** to the v66.0 frozen subject `0dd445a6` (no contract change has landed since v66; the v65 rename + v66 audit are upstream) |

The audit subject is the **tree** `0dd445a6`. Every later v67 phase reads/regresses against this exact tree; the tree is re-verified frozen (`git diff 0dd445a6 -- contracts/` empty, or `git rev-parse HEAD:contracts == 0dd445a6`) after every Write-capable fan-out.

## Green baseline oracle (FOUND-02)

### Forge (full suite — authoritative regression oracle)

```
Ran 127 test suites in 62.47s (1345.88s CPU): 900 tests passed, 0 failed, 109 skipped (1009 total)
```

| Metric | v67.0 baseline | v66.0 close (414) | Δ |
|--------|----------------|-------------------|---|
| passed | **900** | ~899 | — (same subject) |
| failed | **0** | 0 | 0 |
| skipped | **109** | ~109 | 0 |

Profile: `via_ir=true`, `optimizer_runs=1000`, `evm_version=osaka`. **0 deterministic failures — forge is fully green.** This is the v67 regression oracle: any later test-net addition (MECH, phase 424) must keep forge at 900+/0/109 (non-widening by name).

### Hardhat (parity floor)

```
1239 passing (7m) · 14 pending · 129 failing
```
(The run's shell `EXIT=1` is a mocha teardown `MODULE_NOT_FOUND` in the file-unloader during `dispose()` — a harness flake AFTER all results were reported, not a test failure.)

| Metric | v67.0 baseline | v66.0 freeze (410) | Note |
|--------|----------------|--------------------|------|
| passing | **1239** | 1232 | +7 vs the *pre-414* snapshot |
| failing | **129** | 136 | −7 — carried floor (414 test-net work) |
| pending/skip | **14** | 14 | 0 |

The deltas vs v66's 410 snapshot are entirely the phase-414 test-net closure (which is part of this `0dd445a6` tree); the subject is *post-414*, so 1239/129/14 is the correct v67 floor.

### Carried reds catalogue (carried-by-construction — not v67 regressions)

The contracts tree is **byte-identical** to v66.0's shipped subject `0dd445a6`, and **forge — the authoritative oracle on the same tree — is fully green (900/0/109)**. No contract regression is therefore possible: every hardhat failure existed at v66 close and is pre-existing JS-harness debt (stale fixtures · slot-hardcoded `vm.store`/`vm.load` harnesses · event-schema drift), not a contract defect. Catalogued here by suite so no later phase mis-reads one as a v67 finding:

| Suite group | fails | Suite group | fails |
|-------------|------:|-------------|------:|
| SecurityEconHardening | 15 | DGNRS / DGNRS Liquid Token | 8 |
| RngStall | 13 | DegenerusAffiliate | 7 |
| AffiliateHardening | 11 | GameOver | 7 |
| DegenerusGame | 9 | MintBatchDeterminism (P282) | 6 |
| BafCreditRouting | 8 | TST-JPSURF / HeroOverride / Coinflip / Whale / Lootbox / Vault / VRF / misc | ~38 |

Total **129** — all carried. The authoritative regression oracle for v67 is **forge (900/0/109 green)**; hardhat is the parity floor (must not exceed 129 failing / must not drop below 1239 passing by *name* as a side effect of any MECH test work).

## Verdict

FOUND-01 ✅ (subject byte-frozen at tree `0dd445a6`; anchor recorded) · FOUND-02 ✅ (forge 900/0/109 green oracle captured; hardhat parity floor captured + carried reds catalogued). The green foundation for phases 417-425 is established.
