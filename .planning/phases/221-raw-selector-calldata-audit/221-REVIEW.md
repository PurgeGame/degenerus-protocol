---
phase: 221-raw-selector-calldata-audit
reviewed: 2026-04-12T00:00:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - scripts/check-raw-selectors.sh
  - Makefile
findings:
  critical: 0
  warning: 0
  info: 3
  total: 3
  resolved:
    - WR-221-01
    - WR-221-02
status: info_only
---

# Phase 221: Code Review Report

**Reviewed:** 2026-04-12
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

`scripts/check-raw-selectors.sh` is structurally sound and follows the Phase 220 pattern
well. The five scan patterns (A–E) are correctly implemented. All three decision-gate
requirements from CONTEXT D-01–D-09 are met. The Makefile wiring is correct — `check-raw-selectors`
is declared `.PHONY` and listed as a prerequisite of both `test-foundry` and `test-hardhat`.
The script runs clean against the current codebase (2 JUST, 0 FAIL, exit 0).

Two warnings and three info findings follow. None are blocking correctness bugs on the
current codebase, but two of them can produce silent false-negatives (wrong pass) under
plausible operator inputs.

---

## Warnings

### WR-221-01: Non-existent `CONTRACTS_DIR` silently passes instead of erroring — RESOLVED

**Status:** RESOLVED. Guard added at `scripts/check-raw-selectors.sh:29-32`: `[[ -d "$CONTRACTS_DIR" ]]` check exits 1 with stderr error when directory missing. Verified: `CONTRACTS_DIR=/tmp/nonexistent bash scripts/check-raw-selectors.sh` now exits 1 (was 0).

**File:** `scripts/check-raw-selectors.sh:103-105, 151`

**Issue:** When `CONTRACTS_DIR` is set to a path that does not exist (e.g., a typo in
the env-override used for gate self-tests), the script exits 0 with a PASS message.
Both code paths are responsible:

- Pattern A–D: `grep ... 2>/dev/null || true` swallows the "No such file" error and
  produces zero output, so the `while IFS=: read` loop body never runs.
- Pattern E: `find "$CONTRACTS_DIR" ... 2>/dev/null` also produces zero output
  for a missing directory.

The result is `fail_total=0`, `warn_total=0`, `justified_total=0` and the "no raw
selectors … (excluding …)" PASS line is printed despite no files having been scanned.

This matters for the gate self-test use-case (PLAN line 17: `CONTRACTS_DIR` env var
overrides). An operator typo or a broken CI config silently turns the gate into a no-op.

**Fix:** Add a directory existence check immediately after the `CONTRACTS_DIR` assignment:

```bash
CONTRACTS_DIR="${CONTRACTS_DIR:-contracts}"
if [[ ! -d "$CONTRACTS_DIR" ]]; then
  printf "%bFAIL%b CONTRACTS_DIR '%s' does not exist or is not a directory\n" \
    "$RED" "$NC" "$CONTRACTS_DIR" >&2
  exit 1
fi
```

---

### WR-221-02: `warn_total` is declared and tested but never incremented — RESOLVED

**Status:** RESOLVED via Option A (remove). Dead `warn_total=0` declaration, `&& warn_total == 0` summary test, and `(( warn_total > 0 )) && printf WARN...` exit-path line all removed from `scripts/check-raw-selectors.sh`. Summary logic simplified to `if (( fail_total == 0 ))`. Clean-tree gate still exits 0.

**File:** `scripts/check-raw-selectors.sh:84, 181, 193`

**Issue:** `warn_total=0` is declared at line 84. It is tested in the final summary
conditional at line 181 (`if (( fail_total == 0 && warn_total == 0 ))`) and printed
at line 193 (`(( warn_total > 0 )) && printf ... "$warn_total"`). No code path in the
script ever increments it.

The practical effect is zero today: `warn_total` is permanently 0, the branch at line
193 never fires, and the summary logic at line 181 is only affected in the sense that
the `warn_total == 0` condition is always trivially true. However, the presence of the
variable signals to a future maintainer that a WARN severity tier exists. If they add
a new check and forget that no increment path exists, WARNs will silently disappear
from the exit-code decision at line 181.

More concretely: the `check-delegatecall-alignment.sh` sibling exits 1 on `warn_total > 0`
(line 271), but `check-raw-selectors.sh` only exits 1 on `fail_total > 0` (line 194).
If `warn_total` were ever non-zero here it would not trigger exit 1, unlike the sibling —
an inconsistency that would be surprising to operators.

**Fix (option A — remove the tier):** If no WARN-class findings are anticipated, remove
`warn_total` entirely and simplify the summary:

```bash
# Remove line 84:  warn_total=0
# Remove line 181: && warn_total == 0
# Remove line 193: (( warn_total > 0 )) && ...
```

**Fix (option B — keep but wire the exit):** If a WARN tier may be needed later, make
exit behavior consistent with the sibling script (exit 1 on warn as well):

```bash
if (( fail_total > 0 || warn_total > 0 )); then exit 1; fi
```

---

## Info

### IN-221-01: Pattern D comment references "Phase 220" by name

**File:** `scripts/check-raw-selectors.sh:122-124`

**Issue:** The comment on line 122 reads:
> `# Pattern D — abi.encodeCall anywhere in production (CSI-06). Phase 220's`
> `# abi.encodeWithSelector covers the interface-bound case; keeping this gate`
> `# strict nudges future authors toward the audited form.`

Per `feedback_no_history_in_comments`, comments describe what IS, not what changed or
what phase introduced something. "Phase 220's abi.encodeWithSelector covers the
interface-bound case" is a design rationale cross-reference that ties the comment to
a historical artifact (phase number). A reader unfamiliar with the phase numbering
system gets no useful information from "Phase 220's".

**Fix:** Express the same design intent without the phase reference:

```bash
# Pattern D — abi.encodeCall anywhere in production (CSI-06).
# abi.encodeWithSelector(IFace.fn.selector, ...) is the interface-bound form that
# the delegatecall gate covers; abi.encodeCall bypasses that tether and is
# forbidden in production.
```

---

### IN-221-02: `grep --exclude-dir` strips full path to basename — creates asymmetry with Pattern E

**File:** `scripts/check-raw-selectors.sh:43-45`

**Issue:** Patterns A–D exclude `contracts/mocks` and `contracts/interfaces` via
`--exclude-dir="${p##*/}"`, which strips the path to its basename (`mocks`,
`interfaces`). GNU `grep --exclude-dir` applies basename matching at any depth, so
if a future contracts subtree were to contain a nested directory literally named `mocks`
or `interfaces`, that subtree would be silently excluded from the pattern A–D scan even
though it is not in the intended exclusion list.

Pattern E uses the full-path prefix `[[ "$file" == "$excl"/* ]]` which is correctly
scoped to only the declared paths.

The asymmetry means adding a new exclusion entry like `"${CONTRACTS_DIR}/vendor/mocks"`
to `EXCLUDE_PATHS` would cause Pattern A–D to exclude ALL directories named `mocks`
anywhere under `$CONTRACTS_DIR`, while Pattern E would correctly exclude only
`vendor/mocks/`.

On the current repo layout (where `mocks` and `interfaces` only appear as direct
children of `contracts/`) this is harmless. The risk is latent.

**Fix:** Align Patterns A–D to use full-path exclusion consistent with Pattern E.
Replace the `--exclude-dir` approach with a post-grep filter:

```bash
EXCLUDE_GREP_ARGS=()
for p in "${EXCLUDE_PATHS[@]}"; do
  EXCLUDE_GREP_ARGS+=( --exclude-dir="${p##*/}" )
done
```

Alternatively, pass `--exclude-dir` with the full relative path (not portable across
grep versions) or perform the filtering in `scan_simple` with a `grep -v` on the
excluded path prefixes, matching Pattern E's approach.

No code change is urgent given the current directory layout.

---

### IN-221-03: Pattern E `awk` window emits the opener line number, not the `abi.encode*` payload line

**File:** `scripts/check-raw-selectors.sh:132-178`

**Issue:** The Pattern E `awk` block emits `file:n` where `n` is the line number of
the `.call` / `.transferAndCall` opener, not the line where `abi.encode*` appears.
For DegenerusAdmin.sol this means the reported line is 911 (the `linkToken.transferAndCall(`
opener) rather than 914 (the `abi.encode(newSubId)` payload). The FAIL or JUST output
line reads:

```
JUST contracts/DegenerusAdmin.sol:911  abi.encode*(...) payload of low-level call ...
```

An auditor navigating directly to line 911 finds the call-site opener, not the
encode expression. For a single-line case (line 997) the opener and the payload are
on the same line, so there is no discrepancy. For split-argument cases (line 911–914)
the mismatch creates minor navigational friction.

This is cosmetic for the current codebase. If a future site has a deeper argument
split (opener on line N, `abi.encode*` on line N+3), the cited line will always be
the opener, which is still unambiguous about which call site is flagged.

**Fix (optional):** The awk block could record the first `abi.encode` line within the
window by scanning for it explicitly and emitting that line number instead of `n`. But
since the opener uniquely identifies the call site and the window is only 4 lines,
this is low priority.

---

_Reviewed: 2026-04-12_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
