# Mutation Campaign Report — v63 subject `a8b702a7`

**Subject (byte-frozen):** `a8b702a7` — contracts tree-hash
`2934d3d8987a09c5f073549a0cb499f6c5f28620`. The campaign mutates `contracts/*.sol`
only TRANSIENTLY (slither-mutate in-place edit + the runner's EXIT/INT/TERM restore
trap); `git diff a8b702a7 -- contracts/` is EMPTY before AND after every target and at
every checkpoint in this report. No persistent contract-source edit was ever committed.

**Harness:** `audit/mutation/run-campaign-v63.sh --single <ContractName>` (the kill-safe,
resumable, per-target runner from 395-01) driven against the COMPREHENSIVE oracle
`audit/mutation/oracle-comprehensive.sh` (the union of the 12 388-02-EXERCISED
green-baseline suites, via_ir inherited from `[profile.default]`). Target set =
`audit/mutation/TARGETS-v63.md` (the v63-CHANGED + solvency/RNG/packing-SPINE fix-site
functions, NAMED — not an all-files sweep).

---

## Campaign status: IN-PROGRESS (resumable)

This is the documented LONG-POLE (via_ir ≈ 30–90s per mutant; each mutant is one full
project compile + the 12-suite oracle run). It is paced per-target with `.DONE`
checkpoints so a 5h cap never strands a mutant. **One target (`BitPackingLib`) is fully
scored; the remaining five are NOT yet run and are recorded as resumable, NOT dropped.**
Re-invoking `run-campaign-v63.sh --single <ContractName>` resumes the next target from a
clean (trap-restored) tree; the completed target stays `.DONE` and is skipped.

| Target (TARGETS-v63 order) | Class | Status | Note |
|---|---|---|---|
| `BitPackingLib` | PACKING IDENTITY | **DONE** (scored below) | 4219s (~70 min) |
| `DegenerusGameStorage` | PACKING IDENTITY + SOLVENCY helpers | IN-PROGRESS / resumable | ~2361 LOC; multi-hour |
| `StakedDegenerusStonk` | SOLVENCY SPINE | NOT RUN / resumable | redemption claim-split |
| `BurnieCoinflip` | v63-CHANGED + RNG-adjacent | NOT RUN / resumable | emission rework |
| `DegenerusGameLootboxModule` | RNG DOMINANT + SOLVENCY | NOT RUN / resumable | ~2328 LOC; multi-hour |
| `DegenerusGameDecimatorModule` | RNG DOMINANT + v63-CHANGED | NOT RUN / resumable | ~1159 LOC |

**Resume command (next target):** `bash audit/mutation/run-campaign-v63.sh --single DegenerusGameStorage`
(then `StakedDegenerusStonk`, `BurnieCoinflip`, `DegenerusGameLootboxModule`,
`DegenerusGameDecimatorModule`). The full-campaign form
`bash audit/mutation/run-campaign-v63.sh` resumes at the first non-`.DONE` target.

---

## Harness fix applied this plan (Rule 1/3 — drove the runner past a false-abort gate)

The 395-01 runner's baseline-green gate
(`if echo "$out" | grep -qE 'No tests to run' || ! echo "$out" | grep -qE 'Suite result: ok'`)
tripped on a GREEN oracle and aborted EVERY target before any mutant ran (PROGRESS-v63.log
showed `BitPackingLib BASELINE_BAD(no-tests-or-red) abort-target` despite the oracle
printing 12 `Suite result: ok`). Root cause: under the runner's `set -uo pipefail`,
`echo "$out" | grep -q` lets `grep -q` exit on the FIRST match and close the pipe; `echo`
then takes SIGPIPE (141) and pipefail propagates 141 as the pipeline status, so
`! grep -qE 'Suite result: ok'` evaluated TRUE and the gate falsely aborted. This was
proven deterministic (a match near the head of the stream always SIGPIPEs the writer).
The fix replaced the two `echo "$out" | grep -qE` pipelines with SIGPIPE-safe here-strings
(`grep -qE ... <<<"$out"`). This is a test-harness correctness fix in `audit/`; it does
NOT touch `contracts/`. After the fix the gate passes on the green oracle and the campaign
runs (verified: `BitPackingLib` ran to completion, MUTATE_START → DONE).

---

## Bounded per-mutant oracle (the campaign profile)

The runner exports `FOUNDRY_FUZZ_RUNS=64 FOUNDRY_INVARIANT_RUNS=12 FOUNDRY_INVARIANT_DEPTH=48`
for the per-mutant runs (to keep ~70 mutants × per-mutant cost inside a window). via_ir is
inherited from `[profile.default]` (NOT the `lite` profile, which would drop via_ir).
Some fuzz suites pin their own `runs:` via inline `forge-config` directives (e.g. the
StakedStonk redemption fuzz at `runs: 10000`), which override the env down-scale — so the
bounded profile is a floor, not a uniform cap. **Every survivor is re-verified at FULL runs
(default profile, FOUNDRY_FUZZ_RUNS=1000, INVARIANT runs=256) in SURVIVOR-TRIAGE-v63.md
before being finalized FALSE/GENUINE** — a survivor the bounded run misses but a full run
kills is reclassified FALSE (bounded-run artifact).

---

## Per-target mutation score

### `BitPackingLib` (PACKING IDENTITY — masked-RMW primitive + MASK/SHIFT constants)

Authoritative slither-mutate summary (`audit/mutation/BitPackingLib-v63.log`):

| Mutant category | Caught | Total (compiling) | Caught % |
|---|---|---|---|
| Revert (RR — body → `revert()`) | 1 | 1 | 100.0% |
| Comment (CR — line commented out) | 18 | 19 | 94.7% |
| Tweak (AOR / BOR / SBR on constants + body) | 4 | 58 | 6.9% |
| **TOTAL** | **23** | **78** | **mutation score 29.5%** |

- **Survivors (UNCAUGHT): 55** (PROGRESS-v63.log: `BitPackingLib DONE … uncaught=55`;
  the runner's `killed=109` is a grep artifact — `grep -ciE 'CAUGHT'` also counts the
  substring inside `UNCAUGHT` and the `COMPILATION FAILURE` lines, so the AUTHORITATIVE
  count is slither's `23 caught of 78 compiling` + `55 uncaught`).
- Survivor distribution by mutated line (`grep UNCAUGHT … | Line N`):
  - **Lines 33/36/39/42/45 (the `MASK_16/24/32/6/8` definitions): 41 survivors** —
    AOR (`-1` → `+1`/`/1`/`*1`/`%1`) + BOR (`<<` → `&`/`|`/`>>`/`^`) + SBR
    (`uint256`→`uint128`) on the mask constants.
  - **Lines 52–88 (the 13 `*_SHIFT` constants): 13 survivors** — SBR
    (`uint256`→`uint128`) type narrowing on a `constant` literal.
  - **Line 110 (the `setPacked` masked-RMW return body): 1 survivor** — CR (the return
    commented out → `setPacked` returns 0). [the noted 395-01 candidate; see triage]
- **Mutator totals among the 55 survivors:** 20 AOR, 16 BOR, 18 SBR, 1 CR.
- **Elapsed:** 4219s (~70 min).
- **Byte-freeze after target:** tree-hash `2934d3d8987a09c5f073549a0cb499f6c5f28620`,
  `git diff a8b702a7 -- contracts/` EMPTY.

### Aggregate (completed targets only)

| | Caught | Compiling mutants | Mutation score |
|---|---|---|---|
| **All completed targets (BitPackingLib)** | 23 | 78 | **29.5%** |

The aggregate will be recomputed across all targets when the remaining five are run
(resume per the status table). The low BitPackingLib tweak-score (6.9%) is the EXPECTED
PACKING-IDENTITY shape, NOT a solvency/RNG net hole: ~54 of the 55 survivors are
constant-definition mutations that the comprehensive oracle's pokes do not drive to an
asserted divergence because the mask is a width-BOUNDING value applied as `value & mask`
over inputs already within the field width (the documented BitPackingLib false-survivor
pattern). The triage adjudicates each survivor class FALSE vs GENUINE in
SURVIVOR-TRIAGE-v63.md; the single GENUINE net hole is the `setPacked` body-coverage gap.

---

## Pacing / resume record

| Window event | Target | Outcome |
|---|---|---|
| Window 1 (this plan) | `BitPackingLib` | ran MUTATE_START → DONE (4219s), scored above |
| Window 1 (this plan) | `setPacked` CR survivor re-verify | full-run oracle (default profile) re-run IN PLACE, restored — see triage |
| Window 1 (this plan) | `DegenerusGameStorage` | LAUNCHED (resumable; no `.DONE` yet) — carried IN-PROGRESS |
| Future windows | the remaining 5 targets | resume via `--single`, skip the `BitPackingLib.DONE` checkpoint |

A cap-stop mid-target leaves the in-flight target's `.DONE` absent and `contracts/`
trap-restored (the runner's EXIT/INT/TERM trap `git checkout -- contracts/`); the completed
`BitPackingLib.DONE` is skipped on resume. The `setPacked` re-verification was a manual
in-place mutation done with the campaign runner stopped (no two processes mutate
`contracts/` at once); it was restored before relaunching `DegenerusGameStorage`.

---

## Byte-freeze attestation (end of this window)

- `git rev-parse HEAD:contracts` == `2934d3d8987a09c5f073549a0cb499f6c5f28620`.
- `git diff a8b702a7 -- contracts/` — EMPTY.
- No commit was made while any mutant (campaign or re-verification) was in place.

**contracts/ byte-identical to `a8b702a7` after this campaign window.**

> NOTE: at the moment this report is committed, `DegenerusGameStorage` may be running in
> the background and transiently mutating `contracts/` — the runner restores via its trap.
> The commit step asserts `git diff a8b702a7 -- contracts/` EMPTY (and `git checkout --
> contracts/` if needed) immediately before staging, so this report is only committed
> against a byte-frozen tree.
