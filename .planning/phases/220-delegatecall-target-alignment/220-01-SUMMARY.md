---
phase: 220-delegatecall-target-alignment
plan: 01
subsystem: audit-gating
tags: [bash, make, static-analysis, regression-gate, delegatecall, contract-audit]

requires:
  - phase: v27.0-scope
    provides: "CSI-01, CSI-03 requirement definitions"
  - phase: earlier-interface-gate
    provides: "scripts/check-interface-coverage.sh architecture + Makefile wiring pattern mirrored here"

provides:
  - "43-site per-call audit catalog proving zero MISALIGNED delegatecall targets in contracts/ on the clean codebase"
  - "scripts/check-delegatecall-alignment.sh regression gate (170 lines, exit 0 on clean, exit 1 on any cross-wiring)"
  - "Makefile target check-delegatecall wired as prerequisite of test-foundry and test-hardhat alongside check-interfaces"

affects:
  - "220-02 (endgame dead-constant audit) — reuses the same iface_to_constant transform and exception table"
  - "221 (raw selector audit) — gate is compatible with future additional markers like `// delegatecall-alignment: justified`"
  - "Every future contract change — check-delegatecall now blocks `make test` on any delegatecall/interface misalignment"

tech-stack:
  added: [bash-script-regression-gate]
  patterns:
    - "CONTRACTS_DIR env override pattern for gate self-tests — scripts operate on `${CONTRACTS_DIR:-contracts}` so fixture-based negative tests never mutate real contracts/"
    - "Fixture-based negative test: copy real tree to /tmp, sed-mutate only the copy, run gate with CONTRACTS_DIR pointing at fixture"
    - "Two-pass site enumeration (single-line + split-line) for multi-line `IFace.fn.selector` call sites"

key-files:
  created:
    - "scripts/check-delegatecall-alignment.sh — regression gate codifying CSI-01 at every one of 43 interface-bound encoding sites"
    - ".planning/phases/220-delegatecall-target-alignment/220-01-AUDIT.md — per-site verdict catalog"
  modified:
    - "Makefile — added check-delegatecall target + prerequisite wiring to both test targets"

key-decisions:
  - "iface_to_constant exception map: single entry `GameOverModule -> GAMEOVER_MODULE` (no underscore between Game and Over). All 8 other interfaces conform to pure CamelCase-to-UPPER_SNAKE."
  - "Script under set -euo pipefail: collect_sites Pass B must never exit non-zero from a trailing empty iteration; used explicit if/then + explicit `return 0` instead of short-circuit `&&`."
  - "No forge-build prereq for check-delegatecall: script reads source text only, so skipping ABI inspection cuts ~10s from the gate path."

patterns-established:
  - "Regression gate family pattern: bash script in scripts/, wired into Makefile as `check-*` target alongside existing gates, each with the same colored PASS/FAIL/WARN stdout and exit-0-on-clean contract. Future CSI-* phases (221, 222) should mirror this."
  - "CONTRACTS_DIR env var for gate negative testing: every future static-analysis gate should support overriding the target tree so its own regression test can run against a /tmp fixture without touching contracts/."

requirements-completed: [CSI-01, CSI-03]

duration: 12min
completed: 2026-04-12
---

# Phase 220 Plan 01: Delegatecall Target Alignment Summary

**Regression gate at scripts/check-delegatecall-alignment.sh codifies the D-03 interface-to-address naming convention across all 43 delegatecall sites — exit 1 on any cross-wiring, wired into Makefile as prereq of both test-foundry and test-hardhat.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-04-12T10:01:54Z
- **Completed:** 2026-04-12T10:14:38Z
- **Tasks:** 3
- **Files modified:** 3 created/modified (AUDIT.md, check-delegatecall-alignment.sh, Makefile)

## Accomplishments

- Per-site catalog of 43 interface-bound `abi.encodeWithSelector(IXxx.fn.selector, ...)` encoding sites in contracts/ (excluding interfaces/ and mocks/), every one ALIGNED on the clean codebase.
- `scripts/check-delegatecall-alignment.sh` — 170-line bash gate with colorized PASS/FAIL/WARN output, two-pass site enumeration (single-line + split-line) so all 43 sites including the 7 multi-line selector-split variants are covered, self-tests iface_to_constant against all 9 live interfaces before iterating sites, supports `CONTRACTS_DIR` env var for fixture-based negative testing.
- Makefile `check-delegatecall` target wired in 5 places (`.PHONY`, own target block, test-foundry prereq, test-hardhat prereq — 5 mentions total).
- Negative-test evidence captured via /tmp fixture: exit 1 with readable FAIL line naming the cross-wired module (see Negative Test Evidence section).
- CSI-01 (per-site alignment proof) and CSI-03 (regression gate) both satisfied.

## Task Commits

Each task was committed atomically:

1. **Task 1: Audit every interface-bound encoding site → 220-01-AUDIT.md** — `510c5d97` (docs)
2. **Task 2: Write scripts/check-delegatecall-alignment.sh** — `46db8aba` (feat)
3. **Task 3: Wire check-delegatecall into Makefile + negative test the gate** — `b10d4c41` (feat) — includes a bug fix to Task 2's script discovered during negative testing (set -e exit bug)

## Files Created/Modified

- `.planning/phases/220-delegatecall-target-alignment/220-01-AUDIT.md` — 43-row site catalog with per-site verdict (ALIGNED / MISALIGNED / NON_CONVENTIONAL / MAPPING_ERROR / JUSTIFIED per D-03), coverage-by-interface table, findings section. 100% ALIGNED — no misalignments found on the clean tree.
- `scripts/check-delegatecall-alignment.sh` — new executable regression gate. 170 lines. Architecture mirrors `scripts/check-interface-coverage.sh` (set -euo pipefail, colorized output, per-site OK/FAIL/WARN lines, summary tail, exit 0 on clean pass). Pass A (single-line `IFace.fn.selector`) + Pass B (split-line with `.selector` within 5 lines of lone interface token) together cover 43/43 sites.
- `Makefile` — added `check-delegatecall` target block under existing `check-interfaces`, appended `check-delegatecall` to `.PHONY` declaration, appended `check-delegatecall` to both `test-foundry` and `test-hardhat` prereq lists.

## Decisions Made

- **Single naming exception:** `GameOverModule → GAMEOVER_MODULE` (no underscore). Every other interface conforms to pure CamelCase-to-UPPER_SNAKE; the one-entry exception map is exercised at 2 call sites (rows 31, 32 of the audit catalog), both ALIGNED. Plan 220-02 will reuse this map for the reverse-direction `constant_to_iface()`.
- **Script reads source, not ABI:** Unlike `check-interfaces` which runs `forge build` first, this gate needs only text from contracts/ — so no forge-build prereq. Net effect: gate runs in under a second instead of ~10 seconds.
- **Exit code policy:** exit 0 iff `fail_total == 0 && warn_total == 0`. Orphan selectors (reference to `.selector` without a preceding `.GAME_XXX_MODULE.delegatecall(` within the 10-line window) count as WARN and also block, because either they indicate a non-canonical delegatecall form (which the gate should understand) or dead code (which should be documented before merging).
- **Allowlist via inline comment:** `// delegatecall-alignment: justified` within the 10-line window downgrades a FAIL or orphan to WARN (still visible in output, no longer exit-code blocking from the FAIL side) per D-07. No call site currently uses this marker; wired for future cross-wiring edge cases.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] collect_sites Pass B exited non-zero on final empty iteration under set -e**
- **Found during:** Task 3, Step 4 (negative test against fixture)
- **Issue:** `collect_sites` function's Pass B loop used `[[ -n "$sel_line" ]] && printf ...`. When the last `while` iteration saw an empty `$sel_line` (e.g., an import-only interface reference with no `.selector` in the following 5 lines), the `&&` short-circuit returned non-zero. Under `set -euo pipefail`, this propagated through the command substitution and `sites=$(collect_sites ...)` killed the script before the main loop could run. Observable only when the last grep-matched line happened to be an orphan import — which happened in the fixture's grep ordering but not the clean tree's.
- **Fix:** Replaced the short-circuit with an explicit `if [[ -n "$sel_line" ]]; then printf ...; fi` block, and added an explicit `return 0` at the end of `collect_sites`. Function now terminates successfully regardless of the final iteration's conditional.
- **Files modified:** scripts/check-delegatecall-alignment.sh
- **Verification:** Negative test now returns exit 1 with visible FAIL line (previously exited 1 silently with no per-site output). Clean-tree run still returns exit 0 with 43/43 OK lines. Both behaviors required for the gate to be useful.
- **Committed in:** b10d4c41 (Task 3 commit — the bug was surfaced while testing Task 2's output)

**2. [Rule 3 - Blocking] Modified negative-test procedure per prompt override**
- **Found during:** Task 3, Step 4 before execution
- **Issue:** Plan 220-01 Task 3 Step 4 originally directed `sed -i '687s/GAME_LOOTBOX_MODULE/...' contracts/DegenerusGame.sol` with a /tmp backup+restore. The prompt's `<critical_constraints>` and `<modified_negative_test>` blocks override this: real contracts/ must be byte-identical before and after execution.
- **Fix:** Followed the prompt-specified procedure: copy contracts/ to `/tmp/gsd-220-01-fixture/contracts`, sed-mutate the fixture only, run the script with `CONTRACTS_DIR=$FIXTURE/contracts`, cleanup fixture, verify real `git diff contracts/` unchanged against HEAD. Script was extended to support `CONTRACTS_DIR` env var override (default `contracts`) as required.
- **Files modified:** scripts/check-delegatecall-alignment.sh (CONTRACTS_DIR env override added during Task 2; negative test ran entirely in /tmp)
- **Verification:** `git diff contracts/` against HEAD shows zero lines touched by any of this plan's 3 commits. `git log HEAD~3..HEAD --name-only` lists only `.planning/phases/220.../220-01-AUDIT.md`, `scripts/check-delegatecall-alignment.sh`, and `Makefile`.
- **Committed in:** Behavioral change, reflected across all 3 task commits.

---

**Total deviations:** 2 auto-fixed (1 bug, 1 blocking-procedural override from prompt)
**Impact on plan:** Both deviations were required. The Rule 1 bug was a correctness issue in the gate itself — without the fix, a future misalignment fitting the same grep ordering would exit silently. The Rule 3 override honored the project-level `feedback_no_contract_commits` policy (per MEMORY.md) that contracts/ MUST NOT be touched even for temporary tests.

## Negative Test Evidence

Fixture-based procedure (no contracts/ modifications):

```
$ FIXTURE=/tmp/gsd-220-01-fixture
$ rm -rf "$FIXTURE" && mkdir -p "$FIXTURE" && cp -r contracts "$FIXTURE/contracts"
$ sed -i '687s/GAME_LOOTBOX_MODULE/GAME_BOON_MODULE/' "$FIXTURE/contracts/DegenerusGame.sol"
$ diff -q contracts/DegenerusGame.sol "$FIXTURE/contracts/DegenerusGame.sol"
Files contracts/DegenerusGame.sol and /tmp/gsd-220-01-fixture/contracts/DegenerusGame.sol differ
$ CONTRACTS_DIR="$FIXTURE/contracts" bash scripts/check-delegatecall-alignment.sh; echo "exit=$?"
...
FAIL /tmp/gsd-220-01-fixture/contracts/DegenerusGame.sol:690  IDegenerusGameLootboxModule expects GAME_LOOTBOX_MODULE but targets GAME_BOON_MODULE
...
FAIL 1 site(s) misaligned
exit=1
$ rm -rf "$FIXTURE"
$ git diff --stat contracts/ HEAD -- # output empty (vs my commits)
$ bash scripts/check-delegatecall-alignment.sh > /dev/null 2>&1; echo "$?"
0
$ make check-delegatecall > /dev/null 2>&1; echo "$?"
0
```

**Negative-test exit code:** 1 (required exit 1 — PASS)
**FAIL line:** `FAIL /tmp/gsd-220-01-fixture/contracts/DegenerusGame.sol:690  IDegenerusGameLootboxModule expects GAME_LOOTBOX_MODULE but targets GAME_BOON_MODULE` (required to name interface + expected + observed — PASS)
**Post-test real-tree status:** clean-tree `make check-delegatecall` returns 0, `bash scripts/check-delegatecall-alignment.sh` returns 0, `make check-interfaces` unchanged at 0 (no regression)

## Artifacts

- `.planning/phases/220-delegatecall-target-alignment/220-01-AUDIT.md` (108 lines, 57 pipe-rows including the 43 site rows + header/separator + coverage table)
- `scripts/check-delegatecall-alignment.sh` (170 lines, executable, exit 0 on clean)
- `Makefile` (57 lines total; 5 mentions of `check-delegatecall`)

## Issues Encountered

Pre-existing dirty state: `contracts/ContractAddresses.sol` carries a local WXRP constant addition from the user's dev state (known and documented in STATE.md blockers). Verified that none of this plan's 3 commits touched contracts/ (`git log HEAD~3..HEAD --name-only` shows only Makefile, scripts/check-delegatecall-alignment.sh, and .planning/...AUDIT.md).

## Next Phase Readiness

- CSI-01 and CSI-03 both satisfied — Phase 220 Plan 02 (endgame-dead-constant verification) can proceed immediately.
- The `iface_to_constant()` naming transform and `NAMING_EXCEPTIONS` map are now published in `scripts/check-delegatecall-alignment.sh` at known line ranges (34–49). Plan 220-02 should import the same exception table to keep both directions consistent.
- `GAME_ENDGAME_MODULE` remains an unreferenced address constant (zero call sites, no matching interface) — 220-02 will formally verify and recommend removal.

## Self-Check: PASSED

- [x] `git diff contracts/` — empty (vs my commits; pre-existing user WXRP change predates this plan)
- [x] `git diff test/` — empty
- [x] `make check-delegatecall` — exits 0
- [x] `make check-interfaces` — exits 0 (no regression)
- [x] `bash scripts/check-delegatecall-alignment.sh` — exits 0 on clean tree
- [x] Negative test recorded: fixture-based misalignment produced exit 1 with readable FAIL line
- [x] `wc -l scripts/check-delegatecall-alignment.sh` — 170 lines (≤200)
- [x] 220-01-AUDIT.md row count ≥41 (actual: 57 pipe-rows including header and coverage table; 43 site rows)
- [x] No files written outside the `<writable_targets>` list (git log HEAD~3..HEAD --name-only: Makefile, scripts/check-delegatecall-alignment.sh, .planning/phases/220.../220-01-AUDIT.md — all in allowlist)

---
*Phase: 220-delegatecall-target-alignment*
*Completed: 2026-04-12*
