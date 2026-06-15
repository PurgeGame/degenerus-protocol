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

## Campaign status: BOUNDED — spine targets DONE, RNG modules CI-deferred (resumable)

This is the documented LONG-POLE (via_ir ≈ 30–90s per mutant; each mutant is one full
project compile + the 12-suite oracle run). It is paced per-target with `.DONE`
checkpoints so a 5h cap never strands a mutant. The campaign was deliberately **BOUNDED**
after the three SPINE targets: the packing-identity primitive (`BitPackingLib`), the
storage helpers (`DegenerusGameStorage`), and the solvency spine (`StakedDegenerusStonk`)
are all fully scored + triaged. The remaining three RNG/v63-changed modules are CI-DEFERRED
(via_ir cost ≈ overnight) and recorded as resumable, NOT dropped. Re-invoking
`run-campaign-v63.sh --single <ContractName>` resumes the next target from a clean
(trap-restored) tree; completed targets stay `.DONE` and are skipped.

| Target (TARGETS-v63 order) | Class | Status | Note |
|---|---|---|---|
| `BitPackingLib` | PACKING IDENTITY | **DONE** (scored below) | 4219s (~70 min); 55 survivors, 1 GENUINE (G-BPL-01, KILLED) |
| `DegenerusGameStorage` | PACKING IDENTITY + SOLVENCY helpers | **DONE** (scored below) | killed=2 uncaught=2 (1 real survivor S-DGS-01 FALSE, 1 compile-failure artifact) |
| `StakedDegenerusStonk` | SOLVENCY SPINE | **DONE** (scored below) | killed=152 uncaught=78 elapsed=10692s (~178 min); 76 distinct survivors, 6 GENUINE (K1–K6, ALL KILLED) |
| `BurnieCoinflip` | v63-CHANGED + RNG-adjacent | CI-DEFERRED / resumable | emission rework; already covered by 389–394 dual-net + BURNIE-04 |
| `DegenerusGameLootboxModule` | RNG DOMINANT + SOLVENCY | CI-DEFERRED / resumable | ~2328 LOC; via_ir overnight |
| `DegenerusGameDecimatorModule` | RNG DOMINANT + v63-CHANGED | CI-DEFERRED / resumable | ~1159 LOC; via_ir overnight |

### CI resume (the bounded tail)

The three CI-deferred targets resume EXACTLY via (run overnight / in CI under the via_ir
default profile; each is multi-hour):

```
bash audit/mutation/run-campaign-v63.sh --single BurnieCoinflip
bash audit/mutation/run-campaign-v63.sh --single DegenerusGameLootboxModule
bash audit/mutation/run-campaign-v63.sh --single DegenerusGameDecimatorModule
```

The full-campaign form `bash audit/mutation/run-campaign-v63.sh` resumes at the first
non-`.DONE` target (the three `.DONE` spine targets are skipped). **Cost:** via_ir ≈ 30–90s
per mutant × the module mutant count → ~overnight per module; this is why the tail is CI-
deferred rather than run in the interactive window. **Coverage note:** the BURNIE / redemption
surface these modules touch was already exhaustively covered by the 389–394 dual-net audit and
the BURNIE-04 fix-design workflow, so the deferred tail is incremental net-tightening, not an
open security gap. Any GENUINE survivor a deferred target produces on resume is triaged into
`SURVIVOR-TRIAGE-v63.md` and dispositioned in `MUTATION-FINDINGS-v63.md`.

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

### `DegenerusGameStorage` (PACKING IDENTITY + SOLVENCY helpers)

Runner summary (`PROGRESS-v63.log`: `DegenerusGameStorage DONE killed=2 uncaught=2`). The
`killed`/`uncaught` are the runner's grep heuristic; the AUTHORITATIVE survivor set is the
saved compilable mutants in `DegenerusGameStorage-mut-v63/DegenerusGameStorage/`, diffed
against the subject:

- `DegenerusGameStorage_RR_2.sol` — line 583 `return currentDay >= psd + 120;` → `revert()`
  (the `_isDistressMode` `level != 0` distress branch). **1 real compilable survivor**
  (S-DGS-01, FALSE — covered by the JS distress suites outside the forge-oracle union).
- `DegenerusGameStorage_RR_3.sol` — byte-identical to the subject (a slither restore artifact,
  NOT a survivor).
- The runner's `uncaught=2` also counted a `_queueTickets` line-595 RR (`if (quantity == 0)
  revert()`, missing `;`) that is a COMPILATION FAILURE, not a live survivor.

**Effective survivors: 1 (S-DGS-01, FALSE). 0 GENUINE.** Class = PACKING + SOLVENCY helpers;
no net hole on the protocol's overall coverage.

### `StakedDegenerusStonk` (SOLVENCY SPINE)

Runner summary (`PROGRESS-v63.log`: `StakedDegenerusStonk DONE killed=152 uncaught=78
elapsed=10692s` — a COMPLETE run, ~178 min). Authoritative survivor set from the
`--> UNCAUGHT` log entries:

| Mutant category | Survivors (UNCAUGHT) | Note |
|---|---|---|
| RR (line → `revert()`) | 55 | post-gameOver burn/drain + pool legs + views + constructor |
| CR (line commented out) | 23 | constructor allocations, metadata constants, ACL reverts, pool legs |
| **TOTAL distinct survivor lines** | **76** | (78 raw markers − 2 wrapped-line duplicates) |

- **Caught: 73; killed=152 (runner grep, inflated by the `UNCAUGHT` substring); authoritative
  caught = 73 of 151 compiling.** The live-game gambling-burn → `claimRedemption` path was
  comprehensively CAUGHT (the live settle legs 876–900 all caught) — the survivors are the
  POST-gameOver / non-redemption surface the oracle never drives.
- **GENUINE: 6 clusters (K1–K6), ALL KILLED** by `test/mutation/MutationKills.t.sol`.
- **FALSE: 70 survivors** (constructor deploy-only, ERC20 metadata, keeper cranks, deposit
  event/ACL, pure views, gameOver settle branch + batch-loop plumbing — see
  SURVIVOR-TRIAGE-v63.md §StakedDegenerusStonk F1–F6).
- **Byte-freeze after target:** tree-hash `2934d3d8987a09c5f073549a0cb499f6c5f28620`,
  `git diff a8b702a7 -- contracts/` EMPTY.

### Aggregate (bounded — the 3 scored SPINE targets)

| Target | Distinct survivors | GENUINE | KILLED-BY-TEST | ROUTED |
|---|---|---|---|---|
| `BitPackingLib` | 55 | 1 (G-BPL-01) | 1 | 0 |
| `DegenerusGameStorage` | 1 | 0 | 0 | 0 |
| `StakedDegenerusStonk` | 76 | 6 (K1–K6) | 6 | 0 |
| **BOUNDED TOTAL** | **132** | **7** | **7** | **0** |

**Aggregate disposition: 7 GENUINE survivors, ALL KILLED-BY-TEST, 0 ROUTED, 0 contract
defects.** The low raw mutation scores (BitPackingLib 29.5% tweak-heavy; the Stonk survivor
swarm) are the EXPECTED PACKING-IDENTITY / post-gameOver-coverage shapes, NOT solvency/RNG net
holes: the FALSE survivors are equivalent mutants (width-bounding masks over pre-clamped inputs),
deploy-only constructor mutations slither cannot re-deploy in the live fixture, or paths covered
OUTSIDE the comprehensive-forge-oracle union (JS distress / keeper suites). The 7 GENUINE oracle
gaps are all closed by deterministic regression tests, each validated fail-with-mutation /
pass-without. The aggregate will be recomputed across all 6 targets when the 3 CI-deferred RNG
modules are run (see §CI resume).

---

## Pacing / resume record

| Window event | Target | Outcome |
|---|---|---|
| Window 1 | `BitPackingLib` | ran MUTATE_START → DONE (4219s), scored |
| Window 1 | `setPacked` CR survivor re-verify | full-run oracle re-run IN PLACE, restored — triage |
| Window 1 | `DegenerusGameStorage` | DONE (115s/299s); 1 real survivor (S-DGS-01) |
| Window 2 | `StakedDegenerusStonk` | ran MUTATE_START → DONE (10692s, ~178 min); 76 survivors |
| Window 3 (Plan 03) | triage + kill-tests | 7 GENUINE survivors KILLED, each validated in place + restored |
| CI / future | the 3 deferred RNG modules | resume via `--single` (see §CI resume), skip the 3 spine `.DONE` checkpoints |

A cap-stop mid-target leaves the in-flight target's `.DONE` absent and `contracts/`
trap-restored (the runner's EXIT/INT/TERM trap `git checkout -- contracts/`); completed
`.DONE` targets are skipped on resume. Every kill-test validation (Plan 03) was a manual
in-place mutation done with the campaign runner stopped (no two processes mutate `contracts/`
at once); each was restored before the next.

---

## Final byte-freeze attestation (bounded-campaign close, Plan 03)

- `git rev-parse HEAD:contracts` == `2934d3d8987a09c5f073549a0cb499f6c5f28620`.
- `git diff a8b702a7 -- contracts/` — EMPTY (contracts/ byte-identical to `a8b702a7`).
- `forge test --match-path test/mutation/MutationKills.t.sol` — 8 passed, 0 failed (clean subject).
- No commit was made while any mutant (campaign or kill-test re-verification) was on disk.

**Bounded campaign closed: 3 SPINE targets scored + triaged, 7 GENUINE survivors KILLED-BY-TEST,
0 ROUTED, 0 contract defects, 3 RNG modules CI-deferred (resumable). contracts/ byte-identical
to `a8b702a7`.**
