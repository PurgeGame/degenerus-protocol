---
phase: 220-delegatecall-target-alignment
reviewed: 2026-04-12T05:45:00Z
depth: standard
files_reviewed: 2
files_reviewed_list:
  - scripts/check-delegatecall-alignment.sh
  - Makefile
findings:
  critical: 0
  warning: 3
  info: 5
  total: 8
status: issues_found
---

# Phase 220: Code Review Report

**Reviewed:** 2026-04-12T05:45:00Z
**Depth:** standard
**Files Reviewed:** 2
**Status:** issues_found

## Summary

Static-analysis gate (`scripts/check-delegatecall-alignment.sh`) wires a
D-03 naming-convention check over 43 interface-bound delegatecall sites in
`contracts/`. The logic is sound and the gate passes on the current
codebase (43/43 ALIGNED, map preflight 9 LIVE + 1 DEAD). Negative tests
documented in 220-02-SUMMARY confirm it detects the misalignment /
orphan-constant scenarios it claims to.

No critical issues. Three warning-level robustness gaps concern future
fragility (trailing-slash CONTRACTS_DIR, single-file interface universe
assumption, and the 10-line preceding window for the target-address
lookup). Five info-level suggestions cover style, stale belt-and-suspenders
code, and parallel-make safety that is pre-existing but relevant now that
`check-delegatecall` is another prereq of both test targets.

No source files were modified. Review is read-only.

## Warnings

### WR-01: Trailing slash on `CONTRACTS_DIR` silently disables the interfaces/ and mocks/ filters

**File:** `scripts/check-delegatecall-alignment.sh:163,166`
**Issue:** The exclusion filters use string interpolation that breaks when
the caller passes a trailing slash:

```bash
| grep -v "^${dir}/interfaces/" | grep -v "^${dir}/mocks/"
```

With `CONTRACTS_DIR=contracts/` the regex expands to
`^contracts//interfaces/`, which never matches because `grep -rn`
normalizes input and never emits `contracts//`. I reproduced this:
`CONTRACTS_DIR=contracts/ ./scripts/check-delegatecall-alignment.sh` still
exits 0 today (43 sites) only because `contracts/interfaces/` and
`contracts/mocks/` happen to contain no matching selector / lone-interface
lines. The moment an interface file references `IFoo.fn.selector` (even in
a comment or a new NatSpec example block) or a mock gains a stub
delegatecall pattern, the filter will silently fail to exclude it and the
gate will either produce spurious sites or mis-classify real ones.

The sibling `scripts/check-interface-coverage.sh` avoids this by using
`grep --exclude-dir=interfaces --exclude-dir=mocks` (line 74/83) — same
script family, different idiom.

**Fix:** Strip the trailing slash once, or switch to `grep`'s native
exclusion:

```bash
# Option A: normalize once at the top
CONTRACTS_DIR="${CONTRACTS_DIR%/}"

# Option B: use grep's --exclude-dir, matching check-interface-coverage.sh
grep -rn --include='*.sol' --exclude-dir=interfaces --exclude-dir=mocks \
     -E 'IDegenerusGame[A-Za-z]+Module\.[a-zA-Z_]+\.selector' "$dir"
```

Option B is stronger because it survives any future caller convention.

### WR-02: Mapping preflight scans only `IDegenerusGameModules.sol` — new per-module interface files would silently slip the universe check

**File:** `scripts/check-delegatecall-alignment.sh:90,95`
**Issue:** `validate_mapping` hard-codes a single interface file:

```bash
local ifaces="${CONTRACTS_DIR}/interfaces/IDegenerusGameModules.sol"
...
interfaces=$(grep -oE 'interface IDegenerusGame[A-Za-z]+Module' "$ifaces" ...)
```

Today all nine module interfaces live in that file, so this works. But the
codebase has already split other interfaces into per-file form
(`IDegenerusGame.sol`, `IDegenerusQuests.sol`, etc.). If a module
interface is ever moved to its own file (e.g.,
`IDegenerusGameFutureModule.sol`) the preflight will silently stop seeing
it: no "constant without interface" match, no MAP_FAIL. The per-site loop
will still catch a misalignment if that interface is USED somewhere, but
the universe consistency guarantee the preflight promises (threat T-220-07
per 220-02-MAPPING.md) degrades to "subset consistency".

**Fix:** Scan the whole `interfaces/` tree rather than a single file:

```bash
interfaces=$(grep -rh --include='*.sol' -oE 'interface IDegenerusGame[A-Za-z]+Module' \
  "${CONTRACTS_DIR}/interfaces/" | awk '{print $2}' | sort -u)
```

This also lets you drop the per-file existence check at line 93 (the
directory is guaranteed present by the interface-coverage gate upstream).

### WR-03: 10-line preceding window for target-address detection is fragile against future refactors

**File:** `scripts/check-delegatecall-alignment.sh:212,219-220`
**Issue:** The per-site loop builds a fixed 10-line window ending at the
selector anchor and picks the LAST `.GAME_*_MODULE` in that window:

```bash
window=$(awk -v n="$lineno" 'NR >= n - 10 && NR <= n' "$file")
...
target=$(printf '%s\n' "$window" | grep -oE '\.GAME_[A-Z_]+_MODULE' | tail -1 | sed -E 's/^\.//')
```

Today every delegatecall in `contracts/` spans 2-5 lines between target
and selector, well inside the window, and functions are separated by
comments so no prior call-site's target bleeds into the window. Two
foreseeable refactors would break this without producing a FAIL:

1. A delegatecall whose argument list pushes the selector >10 lines below
   the target (e.g., heavily-commented inline parameters, or an inlined
   long struct literal). The preceding-window grep finds no
   `.GAME_*_MODULE`, `target=""`, and the site gets classified as "orphan
   selector (no delegatecall target in 10-line window)" — a WARN, not a
   FAIL. Warnings still exit 1 today (line 277) so the gate trips, but the
   reported message is misleading (an orphan-selector warning on a real
   delegatecall will send the developer hunting for the wrong thing).
2. Two back-to-back delegatecalls tightly packed (e.g., `if/else` branches
   sharing a single output tuple). If the previous delegatecall's
   `.GAME_X_MODULE` lives in the window AFTER the current target line (it
   can't today because each `.GAME_*_MODULE` is above its own selector,
   but a future `(ok, data) = X.delegatecall(...); (ok2, data2) =
   Y.delegatecall(...)` inline form could invert ordering), `tail -1` will
   pick the wrong constant.

**Fix:** Anchor the search on the structure rather than a fixed window.
Walk backwards from the selector line to the FIRST `.delegatecall(` line,
then within that line (or the immediately preceding line for the dotted
split-style) extract the `.GAME_*_MODULE` token. Something like:

```bash
# Find the .delegatecall( line at or above the selector
dc_line=$(awk -v n="$lineno" '
  NR <= n && /\.delegatecall\(/ { m = NR }
  END { print m }' "$file")
# Extract .GAME_*_MODULE from that line or the immediately preceding line
target=$(awk -v n="$dc_line" 'NR == n - 1 || NR == n' "$file" \
  | grep -oE '\.GAME_[A-Z_]+_MODULE' | tail -1 | sed -E 's/^\.//')
```

This makes the check robust to argument-list size and defends against
ordering ambiguity. If the codebase won't grow new delegatecall patterns
(the scope is narrow by design), this is optional — but at minimum the
"orphan selector" wording at line 249 should hint that expanding the
window may help, and the `10` magic number deserves a `readonly
WINDOW_LINES=10` named constant at the top of the file for one-point
tuning.

## Info

### IN-01: `self_test_transform()` duplicates work `validate_mapping()` already guarantees

**File:** `scripts/check-delegatecall-alignment.sh:140-155`
**Issue:** `self_test_transform` iterates a hard-coded list of 9 interface
names and asserts each `iface_to_constant(name)` lands in
ContractAddresses.sol. Moments later, `validate_mapping` does the same
thing over the LIVE universe (lines 99-127), which is strictly stronger
because it's derived rather than pinned. The hard-coded list will rot:
when a module is added or renamed, a contributor who updates
`NAMING_EXCEPTIONS` and ContractAddresses.sol but forgets this list gets
no signal (the function passes for known names, `validate_mapping` still
catches the new one).

**Fix:** Either delete `self_test_transform` outright (Recommended — the
preflight is redundant with it) or rewrite it to iterate the discovered
universe rather than a static list:

```bash
self_test_transform() {
  local iface expected
  while IFS= read -r iface; do
    [[ -z "$iface" ]] && continue
    expected=$(iface_to_constant "$iface")
    [[ "$expected" =~ ^GAME_[A-Z0-9_]+_MODULE$ ]] \
      || { printf "...FAIL self-test: %s -> %s\n" "$iface" "$expected"; return 1; }
  done < <(grep -rh --include='*.sol' -oE 'interface IDegenerusGame[A-Za-z]+Module' \
           "${CONTRACTS_DIR}/interfaces/" | awk '{print $2}' | sort -u)
  return 0
}
```

### IN-02: `grep -c .` with `|| true` disables `set -o pipefail` in the `site_count` path

**File:** `scripts/check-delegatecall-alignment.sh:206`
**Issue:** `site_count=$(printf '%s\n' "$sites" | grep -c . || true)` is
correct for the `sites=""` case (grep returns 1, `|| true` masks it) but
it also masks a genuine pipeline failure (e.g., OOM, broken pipe). Under
`set -euo pipefail`, a masked pipeline failure becomes a silently-zero
count, which the subsequent `sites discovered: 0` line would report
without error. Low-likelihood but worth hardening now that the script is
a gate.

**Fix:**

```bash
site_count=$(printf '%s\n' "$sites" | awk 'NF' | wc -l | tr -d ' ')
```

`awk 'NF'` filters blank lines (matching `grep -c .` semantics) and `wc
-l` always exits 0 on a valid input stream.

### IN-03: Parallel-make `test` target races `ContractAddresses.sol` patcher between Foundry and Hardhat branches

**File:** `Makefile:44` (pre-existing; not introduced by this PR)
**Issue:** `test: test-foundry test-hardhat` — under `make -j2 test`, Make
will attempt to run `test-foundry` and `test-hardhat` concurrently. The
`test-foundry` recipe mutates `ContractAddresses.sol` via
`patchForFoundry.js` before compiling and restores it after the suite
exits. The `test-hardhat` recipe reads the same file (via Hardhat's
compiler). If scheduled concurrently, `test-hardhat` will either compile
against the patched Foundry addresses (incorrect) or catch the restore
mid-write (non-deterministic).

This is PRE-EXISTING (the `test:` target existed before this PR), but
Phase 220 adds `check-delegatecall` as another prereq of both sub-targets.
Worth flagging now so the wire-up doesn't accumulate future foot-guns.

**Fix:** Either document `.NOTPARALLEL` on the root target or force serial
execution of the dependency edge:

```makefile
# Ensure Foundry finishes (including ContractAddresses.sol restore) before Hardhat starts.
.NOTPARALLEL: test
test: test-foundry test-hardhat
```

Alternatively add a file-lock around the patch/restore pair. Not
blocking for this PR — call out in 220-VERIFICATION or open a follow-up.

### IN-04: `validate_mapping` existence check uses `return 1` but caller already handles failure at the `||` boundary

**File:** `scripts/check-delegatecall-alignment.sh:92-93`
**Issue:** The mapping preflight handles missing input files with:

```bash
[[ -f "$addr" ]] || { printf "%bFAIL%b %s missing\n" "$RED" "$NC" "$addr"; return 1; }
[[ -f "$ifaces" ]] || { printf "%bFAIL%b %s missing\n" "$RED" "$NC" "$ifaces"; return 1; }
```

These error messages print a bare "FAIL ... missing" line with no hint
about what to do. `self_test_transform` has an identical pattern at line
142. If either file is genuinely missing the gate exits 1 silently (the
calling-side `|| { ... ; exit 1; }` prints the generic "mapping-preflight
failed — fix the universe" message, which is wrong for a missing-file
case).

**Fix:** Escalate the error message so a fresh-clone user understands the
remediation:

```bash
[[ -f "$addr" ]] || { printf "%bFAIL%b %s missing — run from repo root or set CONTRACTS_DIR\n" "$RED" "$NC" "$addr"; return 1; }
```

### IN-05: `constants=$(grep -oE 'GAME_[A-Z_]+_MODULE' "$addr" | sort -u)` captures tokens in comments

**File:** `scripts/check-delegatecall-alignment.sh:94`
**Issue:** The regex extracts every `GAME_[A-Z_]+_MODULE` substring from
ContractAddresses.sol, including ones inside comments. Today none appear
in comments there (grep shows 0 matches), but if a future TODO or NatSpec
example mentions `GAME_FUTURE_MODULE`, the preflight will hallucinate a
"live" constant and FAIL because the matching interface is absent.

**Fix:** Tighten the regex to the declaration form only:

```bash
constants=$(grep -oE 'constant[[:space:]]+GAME_[A-Z_]+_MODULE' "$addr" \
  | awk '{print $NF}' | sort -u)
```

Same concern applies symmetrically to the interfaces regex at line 95
(solved by anchoring on `^interface `, which it already does — the
interface-side extraction is already robust).

---

_Reviewed: 2026-04-12T05:45:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
