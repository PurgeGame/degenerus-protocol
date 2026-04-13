# Degenerus Protocol -- Delta Findings Report (v27.0 Call-Site Integrity Audit)

**Audit Date:** 2026-04-13
**Methodology:** Three-phase call-site integrity audit: delegatecall target alignment (Phase 220), raw selector and hand-rolled calldata safety (Phase 221), external function classification coverage (Phase 222). All phases were executed by Claude (claude-opus-4-6) with structured reasoning, code review passes, and gsd-verifier re-checks.
**Scope:** Call-site integrity audit covering three axes -- delegatecall target alignment (Phase 220), raw selector and hand-rolled calldata safety (Phase 221), external function classification coverage (Phase 222). Scope: post-v26.0 delta; the v25.0 Master Delta Report (`audit/FINDINGS-v25.0.md`) and the v5.0 baseline (`audit/FINDINGS.md`) remain prior references.
**Contracts in scope:** DegenerusGame, DegenerusGameAdvanceModule, DegenerusGameJackpotModule, DegenerusGameDecimatorModule, DegenerusGameGameOverModule, DegenerusGameMintModule, DegenerusGameWhaleModule, DegenerusGameDegeneretteModule, DegenerusGameLootboxModule, DegenerusGameBoonModule, StakedDegenerusStonk, DegenerusStonk, BurnieCoin, BurnieCoinflip, DegenerusAffiliate, DegenerusJackpots, DegenerusQuests, DegenerusVault, DeityBoonViewer, Icons32Data, GNRUS, WrappedWrappedXRP, DegenerusGameStorage. Tooling and test scope added for v27.0: `scripts/check-delegatecall-alignment.sh`, `scripts/check-raw-selectors.sh`, `scripts/coverage-check.sh`, `scripts/lib/patchContractAddresses.js`, `Makefile`, `test/fuzz/FuturepoolSkim.t.sol`, `test/fuzz/CoverageGap222.t.sol`, `contracts/ContractAddresses.sol`, `contracts/interfaces/IDegenerusGameModules.sol`.

---

## Executive Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 16 |
| **Total** | **16** |

**Overall Assessment:** Zero exploitable vulnerabilities found across all three call-site integrity phases. Every finding is an informational observation on tooling robustness, test quality, or script comment hygiene -- no runtime, security, or correctness risk on production contracts. Phase-level verdicts: Phase 220 passed code review 9/9 (3 WR + 5 IN, all INFO-class), Phase 221 closed 13/13 (2 WR **resolved in-cycle** + 3 IN), Phase 222 re-verified 4/4 after Plan 222-03 landed the two VERIFICATION-gap fixes (4 WR, 2 of which were also the two verification gaps, plus 6 IN). Five observations were resolved in-cycle and carry resolving commit shas below.

This report is a delta supplement to the v5.0 Master Findings Report (`audit/FINDINGS.md`, 29 INFO) and the v25.0 Master Delta Findings Report (`audit/FINDINGS-v25.0.md`, 13 INFO). External auditors should read all three documents together. Regression verification of all 13 v25.0 findings (F-25-01 .. F-25-13) is provided in the Regression Appendix. No separate `FINDINGS-v26.0.md` document exists: the v26.0 milestone was design-focused (bonus jackpot split) and its accomplishments are captured in `.planning/MILESTONES.md`.

---

## Findings

### Phase 220: Delegatecall Target Alignment (6 findings)

#### F-27-01: Trailing slash on `CONTRACTS_DIR` silently disables interfaces/ and mocks/ filters

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 220 (220-REVIEW.md WR-220-01) |
| **Contract** | `scripts/check-delegatecall-alignment.sh` |
| **Function** | `:163,166` (exclusion filter regexes) |

The exclusion filters for `interfaces/` and `mocks/` use `grep -v "^${dir}/interfaces/"` which breaks when the caller passes a trailing slash. With `CONTRACTS_DIR=contracts/` the regex expands to `^contracts//interfaces/` and never matches because `grep -rn` normalizes input and never emits `contracts//`. The default `make check-delegatecall` invocation passes `contracts` without trailing slash, so CI is unaffected; the failure mode surfaces only in fixture-based gate self-tests that set `CONTRACTS_DIR=contracts/`. The sibling `scripts/check-interface-coverage.sh` avoids the issue by using `grep --exclude-dir=interfaces --exclude-dir=mocks`.

**Severity justification:** INFO because the gate default invocation (no trailing slash) is unaffected and the real-world risk is bounded to fixture self-tests. No exploit path exists on production contracts -- the gate still catches every alignment bug in the live codebase. Fix is a one-line normalization (`CONTRACTS_DIR="${CONTRACTS_DIR%/}"`).

---

#### F-27-02: Mapping preflight scans only `IDegenerusGameModules.sol`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 220 (220-REVIEW.md WR-220-02) |
| **Contract** | `scripts/check-delegatecall-alignment.sh` |
| **Function** | `validate_mapping` `:90,95` |

`validate_mapping` hard-codes a single interface file (`${CONTRACTS_DIR}/interfaces/IDegenerusGameModules.sol`) when extracting the interface universe. All nine module interfaces currently live in that file so the check works today, but the codebase has already split other interfaces into per-file form (`IDegenerusGame.sol`, `IDegenerusQuests.sol`). If a module interface is ever moved to its own file, the preflight will silently stop seeing it: no "constant without interface" match, no MAP_FAIL. The per-site loop still catches misalignments where the interface is used, but the universe consistency guarantee (threat T-220-07) degrades to subset consistency.

**Severity justification:** INFO because the current codebase layout satisfies the single-file assumption and the per-site loop retains its misalignment-detection guarantee for any interface that is actually referenced. The degradation is to preflight completeness, not per-site safety. Fix is to scan the whole `interfaces/` tree with `grep -rh --include='*.sol' ... "${CONTRACTS_DIR}/interfaces/"`.

---

#### F-27-03: 10-line preceding window for target-address detection is fragile

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 220 (220-REVIEW.md WR-220-03) |
| **Contract** | `scripts/check-delegatecall-alignment.sh` |
| **Function** | per-site loop at `:212,219-220` |

The per-site loop builds a fixed 10-line window ending at the selector anchor and picks the LAST `.GAME_*_MODULE` in that window. Every delegatecall in `contracts/` spans 2-5 lines between target and selector -- well inside the window -- and functions are separated by comments so no prior call-site's target bleeds in. Two foreseeable refactors would break this without producing a FAIL: (1) a delegatecall whose argument list pushes the selector >10 lines below the target (heavily commented params, inline long struct literal) -- grep finds no `.GAME_*_MODULE`, `target=""`, site mis-classifies as "orphan selector" WARN; (2) two back-to-back delegatecalls with tight inline forms could invert ordering and `tail -1` picks the wrong constant.

**Severity justification:** INFO because every current site fits comfortably inside the 10-line window. Warnings still exit 1 today (the gate trips), but the reported message would be misleading for a misaligned call. A more robust structural anchor (find the `.delegatecall(` line first, then look in that line or the immediate preceding line for `.GAME_*_MODULE`) is available if the shape of delegatecall sites changes. The `10` magic also deserves a named `readonly WINDOW_LINES=10` constant for one-point tuning.

---

#### F-27-04: `self_test_transform()` duplicates work `validate_mapping()` already guarantees

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 220 (220-REVIEW.md IN-220-01) |
| **Contract** | `scripts/check-delegatecall-alignment.sh` |
| **Function** | `self_test_transform` `:140-155` |

`self_test_transform` iterates a hard-coded list of 9 interface names and asserts each `iface_to_constant(name)` lands in `ContractAddresses.sol`. Immediately afterwards, `validate_mapping` does the same thing over the LIVE universe (lines 99-127), which is strictly stronger because it's derived from source rather than pinned. The hard-coded list will rot: when a module is added or renamed, a contributor who updates `NAMING_EXCEPTIONS` and `ContractAddresses.sol` but forgets this list gets no signal -- the function passes for known names, `validate_mapping` still catches the new one.

**Severity justification:** INFO because the redundancy is strictly weaker than the adjacent preflight and carries no behavioral risk. The recommended fix is to delete `self_test_transform` outright or rewrite it to iterate the discovered universe. No current impact.

---

#### F-27-05: Parallel-make race on `ContractAddresses.sol` between Foundry and Hardhat branches

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 220 (220-REVIEW.md IN-220-03) |
| **Contract** | `Makefile:44` (pre-existing; Phase 220 adds `check-delegatecall` as another prereq of both sub-targets) |
| **Function** | `test: test-foundry test-hardhat` |

Under `make -j2 test`, Make will attempt to run `test-foundry` and `test-hardhat` concurrently. The `test-foundry` recipe mutates `ContractAddresses.sol` via `patchForFoundry.js` before compiling and restores it after the suite exits. The `test-hardhat` recipe reads the same file via Hardhat's compiler. If scheduled concurrently, `test-hardhat` will either compile against the patched Foundry addresses (incorrect) or catch the restore mid-write (non-deterministic). This is pre-existing -- the `test:` target existed before this PR -- but Phase 220 adds `check-delegatecall` as another prereq of both sub-targets, so the wire-up is worth flagging before the dependency list grows further.

**Severity justification:** INFO because default `make test` is serial; the race fires only under explicit `-j2+`. Recommended mitigation: declare `.NOTPARALLEL: test` or force serial execution via file-lock around the patch/restore pair.

---

#### F-27-06: Phase 220 gate script -- minor robustness notes

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 220 (220-REVIEW.md IN-220-02 + IN-220-04 + IN-220-05, folded per D-02) |
| **Contract** | `scripts/check-delegatecall-alignment.sh` |
| **Function** | multiple (`:94, :92-93, :206`) |

Three non-blocking robustness observations on the gate script, folded as one finding because each is a stylistic hardening opportunity with no current impact:

- **Sub-point A (IN-220-02, `:206`):** `site_count=$(printf '%s\n' "$sites" | grep -c . || true)` masks genuine pipeline failures (e.g., OOM, broken pipe). Under `set -euo pipefail` a masked failure silently becomes a zero count, which the `sites discovered: 0` line would report without error. Fix: `site_count=$(printf '%s\n' "$sites" | awk 'NF' | wc -l | tr -d ' ')`.
- **Sub-point B (IN-220-04, `:92-93`):** The `[[ -f "$addr" ]] || { printf "...FAIL ... missing"; return 1; }` path prints a bare "FAIL ... missing" line with no remediation hint, and the caller's generic "mapping-preflight failed -- fix the universe" wording is wrong for a missing-file case. Fix: inline hint `missing -- run from repo root or set CONTRACTS_DIR`.
- **Sub-point C (IN-220-05, `:94`):** `constants=$(grep -oE 'GAME_[A-Z_]+_MODULE' "$addr" | sort -u)` captures every `GAME_[A-Z_]+_MODULE` substring, including any that appears in comments. Today none do (grep shows 0 matches), but a future TODO or NatSpec example mentioning `GAME_FUTURE_MODULE` would be hallucinated as a "live" constant and the preflight would FAIL because no matching interface exists. Fix: tighten regex to the declaration form: `grep -oE 'constant[[:space:]]+GAME_[A-Z_]+_MODULE' "$addr" | awk '{print $NF}' | sort -u`.

**Severity justification:** INFO for each sub-point. None fires on the current codebase; all three are forward-looking portability / ergonomics improvements. The gate's correctness guarantee holds regardless.

---

### Phase 221: Raw Selector & Calldata Audit (5 findings)

#### F-27-07: Non-existent `CONTRACTS_DIR` silently passes

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 221 (221-REVIEW.md WR-221-01) |
| **Contract** | `scripts/check-raw-selectors.sh` |
| **Function** | top-level env handling `:103-105, :151` (pre-fix) |

When `CONTRACTS_DIR` pointed at a path that did not exist (e.g., typo in an env-override for gate self-tests), the script exited 0 with a PASS message. Both code paths were responsible: Patterns A-D used `grep ... 2>/dev/null || true` which swallowed the "No such file" error, and Pattern E's `find "$CONTRACTS_DIR" ... 2>/dev/null` also produced zero output for a missing directory. The result was `fail_total=0`, `warn_total=0`, `justified_total=0` and the "no raw selectors ... (excluding ...)" PASS line -- despite no files having been scanned.

**Severity justification:** INFO because the default CI invocation (no env override) is unaffected; the silent-pass path fired only under env-override self-tests or a broken CI config with a bogus path. No runtime risk on production contracts.

**Status:** Resolved in v27.0 (commit `f799da98`). Guard added at `scripts/check-raw-selectors.sh:29-32`: a `[[ -d "$CONTRACTS_DIR" ]]` check now exits 1 with a stderr error when the directory is missing. Verified post-fix: `CONTRACTS_DIR=/tmp/nonexistent bash scripts/check-raw-selectors.sh` exits 1 (was 0).

---

#### F-27-08: `warn_total` declared and tested but never incremented

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 221 (221-REVIEW.md WR-221-02) |
| **Contract** | `scripts/check-raw-selectors.sh` |
| **Function** | `:84, :181, :193` (pre-fix) |

`warn_total=0` was declared at line 84, tested in the final summary conditional at line 181 (`if (( fail_total == 0 && warn_total == 0 ))`), and printed at line 193 -- but no code path ever incremented it. Behavioral impact today was zero (`warn_total` was permanently 0), but the presence of the variable signalled a WARN severity tier that did not exist. If a maintainer added a new check and forgot that no increment path exists, WARNs would silently disappear from the exit-code decision. Inconsistent with sibling `check-delegatecall-alignment.sh` which exits 1 on `warn_total > 0`.

**Severity justification:** INFO because dead code only; no current behavioral risk. The consistency gap with the sibling script is a forward-looking maintenance concern, not a present bug.

**Status:** Resolved in v27.0 (commit `f799da98`, resolved via Option A -- remove the tier). The dead `warn_total=0` declaration, the `&& warn_total == 0` summary test, and the `(( warn_total > 0 )) && printf WARN...` exit-path line were all removed. Summary logic simplified to `if (( fail_total == 0 ))`. Clean-tree gate still exits 0.

---

#### F-27-09: Pattern D comment references "Phase 220" by name

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 221 (221-REVIEW.md IN-221-01) |
| **Contract** | `scripts/check-raw-selectors.sh` |
| **Function** | comment block `:122-124` |

The comment on line 122 reads "Pattern D -- abi.encodeCall anywhere in production (CSI-06). Phase 220's abi.encodeWithSelector covers the interface-bound case; keeping this gate strict nudges future authors toward the audited form." Per project convention `feedback_no_history_in_comments`, comments describe what IS -- not what changed or which phase introduced something. "Phase 220's abi.encodeWithSelector covers the interface-bound case" is a design rationale cross-reference that ties the comment to a historical artifact (phase number); a reader unfamiliar with the phase numbering gets no useful information from "Phase 220's".

**Severity justification:** INFO because cosmetic only -- the gate's enforcement is unaffected. Fix is to rewrite without the phase reference.

---

#### F-27-10: `grep --exclude-dir` strips full path to basename -- creates asymmetry with Pattern E

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 221 (221-REVIEW.md IN-221-02) |
| **Contract** | `scripts/check-raw-selectors.sh` |
| **Function** | `scan_simple` exclusions `:43-45` |

Patterns A-D exclude `contracts/mocks` and `contracts/interfaces` via `--exclude-dir="${p##*/}"`, which strips the path to its basename (`mocks`, `interfaces`). GNU `grep --exclude-dir` applies basename matching at any depth, so a future nested directory literally named `mocks` or `interfaces` under `contracts/` would be silently excluded from the Patterns A-D scan even though it is not in the intended exclusion list. Pattern E uses `[[ "$file" == "$excl"/* ]]` which is correctly scoped to only the declared paths. On the current repo layout (`mocks` and `interfaces` only as direct children of `contracts/`) this is harmless; the risk is latent.

**Severity justification:** INFO because latent -- no current directory layout triggers the asymmetry. Fix: align Patterns A-D to use full-path exclusion consistent with Pattern E (post-grep filter with `grep -v` on full prefixes).

---

#### F-27-11: Pattern E `awk` window emits opener line number, not `abi.encode*` payload line

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 221 (221-REVIEW.md IN-221-03) |
| **Contract** | `scripts/check-raw-selectors.sh` |
| **Function** | Pattern E awk block `:132-178` |

The Pattern E `awk` block emits `file:n` where `n` is the line number of the `.call` / `.transferAndCall` opener, not the line where `abi.encode*` appears. For `DegenerusAdmin.sol` the reported line is 911 (the `linkToken.transferAndCall(` opener) rather than 914 (the `abi.encode(newSubId)` payload). An auditor navigating directly to line 911 finds the call-site opener, not the encode expression. For a single-line case (line 997) opener and payload coincide.

**Severity justification:** INFO because cosmetic -- the opener uniquely identifies the call site, and the 4-line window makes the flagged site unambiguous. Minor navigational friction only.

---

### Phase 222: External Function Coverage Gap (5 findings)

#### F-27-12: `patchContractAddresses.js` VRF_KEY_HASH regex fails on multi-line format

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 222 (222-REVIEW.md WR-222-01) |
| **Contract** | `scripts/lib/patchContractAddresses.js` |
| **Function** | `:59-62` (VRF_KEY_HASH replacement), parallel concern at `:52-55` (DEPLOY_DAY_BOUNDARY) |

The regex `/bytes32 internal constant VRF_KEY_HASH = 0x[0-9a-fA-F]+;/` only matches when `=`, the hex literal, and the semicolon are on the same line. In `contracts/ContractAddresses.sol:8-9` `VRF_KEY_HASH` is declared across two lines:

```solidity
bytes32 internal constant VRF_KEY_HASH =
    0xabababababababababababababababababababababababababababababababab;
```

`src.replace()` with a non-matching regex returns the string unchanged, so the pipeline silently leaves the dummy key hash in place -- the deploy-time bytes32 constant retains the `0xabab...` value. The Plan 222-01 fix to `replaceAddressConstant` addressed the parallel case for addresses using `\s*`, but did not propagate to `VRF_KEY_HASH` or `DEPLOY_DAY_BOUNDARY`. `DEPLOY_DAY_BOUNDARY` currently fits on one line so the live pipeline works, but the same regression is latent.

**Severity justification:** INFO per D-04 default. The observation affects the deployment pipeline (silent no-op at patch time) rather than compiled bytecode or runtime behavior -- operators still have the opportunity to catch the dummy value in pre-deploy review. Promotion to LOW was considered because the silent failure reaches a security-sensitive field (VRF key hash), but the mitigation of "operator review before mainnet deploy" keeps this a tooling-robustness concern. A future cycle may escalate if an automated-deploy path removes that review gate. Recommended fix: `\s*` in both regexes plus a post-patch validation that counts `.replace()` return against input to fail loudly on silent no-ops.

---

#### F-27-13: `CoverageGap222.t.sol` reachability-only assertions (62 of 76 tests) and tautological `uint32 >= 0` check

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 222 (222-REVIEW.md WR-222-02 + 222-REVIEW.md WR-222-04 + 222-VERIFICATION.md Gap 1 -- consolidated per D-02 dedup rule) |
| **Contract** | `test/fuzz/CoverageGap222.t.sol` |
| **Function** | 62 of 76 tests (WR-222-02, pre-fix); `test_gap_lifecycle_purchase_then_advanceGame:60-63` (WR-222-04, pre-fix) |

Three closely related test-quality observations on the CRITICAL_GAP coverage test suite, consolidated into one finding because they were resolved by a single commit and share the same root cause (reachability without behavioral assertion):

- **Sub-point A (WR-222-02 / Gap 1 -- reachability-only assertions):** 62 of 76 tests ended in `(bool ok, ) = addr.call(...); ok; // silence unused; assertTrue(true, "reached")`. The pattern exercised selector dispatch (forge coverage registered the function entry hit), but verified no behavior. A function that reverted for the wrong reason, a guard that accepted when it should reject, or a calldata-length mismatch would all have passed these tests. The phase goal of exercising conditional-entry branches via forge coverage was satisfied, but regression safety was weak: 14 tests with real assertions (e.g., `test_gap_burnieCoin_approve`, `test_gap_icons32_*_asCreator_*`) had shown the correct pattern. **Status: Resolved in v27.0 (commit `ef83c5cd` -- Plan 222-03 Task 1).** 62 reachability-only tests rewritten to assert guard-rejection (`assertFalse(ok, ...)` minimum) or observable state change. Four orphan `// silence unused` comment lines removed from kept tests. Nine tests adjusted to use `assertTrue` on calls that legitimately succeed on the happy path (self-service setters, standard ERC20 approve, open `propose` / `createAffiliateCode`, no-op whale-pass claim).
- **Sub-point B (WR-222-04 -- uint32 tautology):** `test_gap_lifecycle_purchase_then_advanceGame` asserted `game.ticketsOwedView(lvl0, buyer) >= 0` -- always true for a `uint32`. Vacuous. **Status: Resolved in v27.0 (commit `ef83c5cd`).** `test_gap_lifecycle_purchase_then_advanceGame` now uses pre/post snapshot with `assertGt` instead of the tautological `uint32 >= 0` check.

**Severity justification:** INFO for each sub-point. The anti-`mintPackedFor` forge-coverage goal (unexercised surface detection) was structurally satisfied -- forge coverage DID register the entry branch hits. The weakness was in regression safety only, which is a test-quality concern and not a contract-correctness issue. Acceptable as INFO.

**Status:** Both sub-points above resolved in v27.0 by commit `ef83c5cd` (Plan 222-03 Task 1). Final state: 76 tests still pass (same as pre-edit), zero `assertTrue(true, ...)`, zero `// silence unused` comments. 222-VERIFICATION.md re-verified at 4/4 must-haves on 2026-04-12.

---

#### F-27-14: `coverage-check.sh` drift mode is not contract-scoped

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 222 (222-REVIEW.md WR-222-03 + 222-VERIFICATION.md Gap 2 -- consolidated per D-02 dedup rule) |
| **Contract** | `scripts/coverage-check.sh` |
| **Function** | `check_matrix_drift` `:89-164` (pre-fix, specifically the global `grep -qF` at `:104`) |

For each `external|public` function discovered in a source file, drift enforcement ran a `grep -qF` with a backtick-anchored function-name pattern against the matrix. This was a global search across the entire matrix. Multiple deployed contracts export identical names (`approve`, `transfer`, `transferFrom`, `burn`, `mint`, `burnAtGameOver`, `gameAdvance`). If `contracts/NewContract.sol` added a `transfer(address,uint256)` that was not classified for `NewContract`, the drift check PASSED because `BurnieCoin`'s row anchored the `transfer(` pattern somewhere in the matrix. Combined with D-05/D-06 exclusions (NON_DEPLOYABLE_TOP_LEVEL, NON_DEPLOYABLE_MODULES), the "every external function on every deployable artifact is classified" guarantee was only enforced at the function-NAME level across the whole file, not per (contract, function) pair. This weaker enforcement was the WR-03 / Gap 2 observation.

**Severity justification:** INFO. The drift check DID catch brand-new function names (no contract anywhere exported the name yet); it only failed for same-name additions. The 308-row matrix made the failure mode narrow. No CRITICAL_GAP was being masked on the production codebase at the time the finding was filed.

**Status:** Resolved in v27.0 (commit `e0a1aa3e` -- Plan 222-03 Task 2). Preflight parser now populates `contract_fns[<section-key>]` from the matrix `### Contract:` headers; `check_matrix_drift` uses a scoped `;fn;` membership test instead of the global grep. Negative tests verified: the existing `DegenerusStonk __pokeCoverageGate` injection still fires `FAIL_DRIFT` with exit 1, and a new `DeityBoonViewer transfer` injection now fires `FAIL_DRIFT` (pre-fix it would have PASSED because `BurnieCoin`'s section already anchored the `transfer(` pattern). The fix also surfaced a real matrix drift the pre-fix global grep was masking: `DegenerusGame.sol`'s external self-call wrapper `emitDailyWinningTraits` (added in commit `e4064d67`) was only rowed under the `JackpotModule` section; a CRITICAL_GAP row was added to the `DegenerusGame.sol` section to close that drift. Script length: 285 lines (<= 300-line budget). 222-VERIFICATION.md re-verified at 4/4 must-haves on 2026-04-12.

---

#### F-27-15: Delegatecall/docstring clarity notes on `_emitDailyWinningTraits` and `payDailyCoinJackpot`

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 222 (222-REVIEW.md IN-222-01 + IN-222-02, folded per D-02) |
| **Contract** | `contracts/modules/DegenerusGameAdvanceModule.sol` |
| **Function** | `:857-870` (`payDailyCoinJackpot` site); `:872-875` (`_emitDailyWinningTraits` docstring) |

Two related advisory observations on the Phase 222 contract fix and surrounding delegatecall patterns:

- **Sub-point A (IN-222-01 -- `payDailyCoinJackpot` direct delegatecall):** Phase 222 routed `emitDailyWinningTraits` through a GAME self-call wrapper because it carries an `OnlyGame()` check on the JackpotModule. Confirmed for `payDailyJackpot`, `payDailyCoinJackpot`, and `distributeYieldSurplus` that none of those functions currently have an `OnlyGame()` check, so direct delegatecall remains correct. Informational only: if any of these later gain an `OnlyGame()` guard, the direct call will silently revert the outer `advanceGame()` transaction. A forward-looking gate enhancement -- extending `check-delegatecall-alignment.sh` to flag any module function with `OnlyGame()` called via direct delegatecall rather than through a GAME wrapper -- would mechanically prevent the next regression in this class.
- **Sub-point B (IN-222-02 -- `_emitDailyWinningTraits` docstring conflation):** The docstring at `:872-875` says "Self-call preserves msg.sender == address(this) across the delegatecall so the JackpotModule's OnlyGame check passes." Both statements are accurate, but the flow is slightly conflated: the self-call goes `AdvanceModule(delegatecall) -> GAME wrapper -> JackpotModule(delegatecall)`. The outer wrapper's `if (msg.sender != address(this)) revert E();` passes because the frame is still a delegatecall into GAME (originally invoked externally). The `OnlyGame()` check on JackpotModule then sees `msg.sender == address(GAME)` because the wrapper delegatecalls into JackpotModule. The clarity fix is a 2-3 line docstring rewrite that spells out the wrapper hop.

**Severity justification:** INFO for each sub-point. Sub-point A is a forward-looking enhancement, not a present correctness issue. Sub-point B is a documentation-clarity concern and does not affect bytecode or runtime.

---

#### F-27-16: Phase 222 comment hygiene and coverage-check gate robustness notes

| Field | Value |
|-------|-------|
| **Severity** | INFO |
| **Source** | Phase 222 (222-REVIEW.md IN-222-03 + IN-222-04 + IN-222-05 + IN-222-06, folded per D-02) |
| **Contract** | `test/fuzz/FuturepoolSkim.t.sol`, `scripts/coverage-check.sh`, `Makefile` |
| **Function** | multiple -- see sub-points |

Four non-blocking observations on Phase 222 deliverables, folded as one finding because each is a minor hardening / style suggestion with no current correctness impact:

- **Sub-point A (IN-222-03, `test/fuzz/FuturepoolSkim.t.sol:7-27`):** Header comments contain historical context (`v20.0`, a specific commit SHA reference, `D-01/D-02/D-03` labels and the "removed in v20.0" line) that violates project convention `feedback_no_history_in_comments`. The `D-01/D-02/D-03` decision references are load-bearing for matrix cross-reference and can be retained; the version and commit references should be dropped. INFO -- cosmetic.
- **Sub-point B (IN-222-04, `scripts/coverage-check.sh:200-204`):** When `lcov.info` does not exist, the coverage-regression check is skipped with a yellow WARN but the script continues. A CI environment that forgets to run `forge coverage` before `make coverage-check` will silently report PASS based only on drift + uncured-gap checks. Documented intentional behavior (header at lines 24-25), but a downstream consumer reading exit 0 might wrongly assume coverage was checked. Recommended: `STRICT=1` env var to escalate missing lcov to hard fail; or "PASS (lcov check skipped)" wording instead of just "PASS".
- **Sub-point C (IN-222-05, `Makefile:43-44`):** The `coverage-check` target invokes the script unconditionally. If `lcov.info` is stale (pre-dates last commit), the regression check runs against out-of-date data and misses recent regressions. No comparison against file mtimes or git HEAD is performed. Recommended: `coverage-check-fresh` target that re-runs `forge coverage --report lcov --ir-minimum` before `coverage-check`, or a stale-mtime warning.
- **Sub-point D (IN-222-06, `scripts/coverage-check.sh` various):** Minor bash regex/awk style -- backtick-inside-single-quoted regex portability (lines 191, 219, 225) and strict column-2 regex pattern at line 225 could fail silently if the matrix schema grows intermediate columns. Use hexcode escapes for backticks and allow any number of pre-COVERED columns for schema flexibility.

**Severity justification:** INFO for each sub-point. All four are forward-looking hardening notes; none changes the gate's correctness on the current codebase or matrix schema.

---

## Summary Statistics

### By Severity

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 16 |

### By Source Phase

| Phase | Description | Findings |
|-------|-------------|----------|
| 220 | Delegatecall Target Alignment | 6 (F-27-01 through F-27-06) |
| 221 | Raw Selector & Calldata Audit | 5 (F-27-07 through F-27-11) |
| 222 | External Function Coverage Gap | 5 (F-27-12 through F-27-16) |

### By Contract / Script

| Contract / Script | Findings |
|-------------------|----------|
| `scripts/check-delegatecall-alignment.sh` | 5 (F-27-01, F-27-02, F-27-03, F-27-04, F-27-06) |
| `Makefile` | 1 (F-27-05; sub-point C of F-27-16 also touches Makefile) |
| `scripts/check-raw-selectors.sh` | 5 (F-27-07, F-27-08, F-27-09, F-27-10, F-27-11) |
| `scripts/lib/patchContractAddresses.js` | 1 (F-27-12) |
| `test/fuzz/CoverageGap222.t.sol` | 1 (F-27-13) |
| `scripts/coverage-check.sh` | 2 (F-27-14; sub-points B & D of F-27-16) |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 1 (F-27-15) |
| `test/fuzz/FuturepoolSkim.t.sol` | 1 (sub-point A of F-27-16) |

---

## Audit Trail

Verdicts: **SAFE** = no exploitable vulnerabilities found; **SOUND** = proven correct from first principles or by complete static coverage.

| Phase | Scope | Plans | Findings | Verdict |
|-------|-------|-------|----------|---------|
| 220 | Delegatecall target alignment: 43-site per-call audit + static-analysis gate wiring + 1:1 interface/address mapping preflight | 2 | 8 raw (3 WR + 5 IN) / 6 consolidated INFO | SOUND |
| 221 | Raw selector & calldata audit: 5-pattern static-analysis gate (CSI-04/05/06) + findings catalog with 5 JUSTIFIED INFO sites | 2 | 5 raw (2 WR + 3 IN) / 5 consolidated INFO (2 resolved in-cycle) | SOUND |
| 222 | External-function coverage gap: `FuturepoolSkim.t.sol` compile fix + 308-function classification matrix + `CoverageGap222.t.sol` (76 tests) + `coverage-check.sh` gate + Plan 222-03 quality closure | 3 | 10 raw (4 WR + 6 IN) + 2 VERIFICATION gaps / 5 consolidated INFO (3 resolved in-cycle) | SOUND |
| **Total** | **3-phase call-site-integrity delta audit (v26.0-v27.0)** | **7** | **16 INFO** | **SAFE** |

---

## Regression Appendix -- v25.0 Findings

Regression verification of all 13 INFO findings from the v25.0 Master Delta Findings Report (`audit/FINDINGS-v25.0.md`). No `FINDINGS-v26.0.md` document exists -- the v26.0 milestone was design-focused (bonus jackpot split) and did not produce a formal findings doc; accomplishments are captured in `.planning/MILESTONES.md`. No v26.0 findings are therefore included in this appendix. Each v25.0 finding is checked against the current contract source with code-level evidence.

**Status key:**
- **HOLDS** -- still applies as-is (underlying code unchanged or semantically equivalent)
- **SUPERSEDED** -- code path restructured but the conclusion stands
- **FIXED** -- code change made the finding moot
- **INVALIDATED** -- changed circumstances invalidate the INFO-level observation

| Finding | Contract | Status | Evidence |
|---------|----------|--------|----------|
| F-25-01 | MintModule | HOLDS | `_purchaseFor` still present in `DegenerusGameMintModule.sol`; CEI ordering preserved. All called protocol contracts (affiliate, quests, coinflip) remain trusted with no callback paths; `rngLockedFlag` mutual exclusion still in place (`DegenerusGameStorage.sol:279`). |
| F-25-02 | DegeneretteModule | HOLDS | `_distributePayout` still present in `DegenerusGameDegeneretteModule.sol` (3 refs). `coin.mintForGame` and `sdgnrs.transferFromPool` are still the only post-state-write external calls; both remain one-way token operations with no caller callback. |
| F-25-03 | GameOverModule | HOLDS | `handleGameOverDrain` still present in `DegenerusGameGameOverModule.sol` (1 ref). Terminal-state `gameOver=true` toggle remains the safety mechanism; the multi-call pattern is safe by terminal-state exclusion. |
| F-25-04 | StakedDegenerusStonk | HOLDS | `transferFromPool` still present at `StakedDegenerusStonk.sol:405`; the self-win burn branch at `:419` ("Self-win: burn instead of no-op transfer, increasing value per remaining token") is unchanged. |
| F-25-05 | DegenerusGameStorage | HOLDS | `_setCurrentPrizePool` still present in `storage/DegenerusGameStorage.sol` (2 refs). Pool value bound (~1.2e26 wei) and uint128 max (~3.4e38 wei) unchanged; Phase 214-02's 10^12x safety margin verdict still applies. |
| F-25-06 | DegenerusGameAdvanceModule | HOLDS | `_consolidatePoolsAndRewardJackpots` still present at `DegenerusGameAdvanceModule.sol:630`; memory-batch pattern still in place (28 references to `memFuture`/`memCurrent`/`claimableDelta` across the module). The auto-rebuy storage writes during self-calls are still overwritten by the memory-batch writeback at the end of the function -- the design intent from v25.0 is preserved. |
| F-25-07 | DegenerusGameStorage / JackpotModule | HOLDS | `rngLockedFlag` still present at `storage/DegenerusGameStorage.sol:279` with 20 references across 5 files. Daily VRF locking asymmetry versus mid-day lootbox RNG isolation unchanged; index-advance isolation for lootbox remains documented at Storage `:238` and `:55`. |
| F-25-08 | DegenerusGameAdvanceModule | HOLDS | Gameover historical-VRF + `block.prevrandao` fallback still present at `DegenerusGameAdvanceModule.sol:1191-1221` (see comment "prevrandao adds unpredictability at the cost of 1-bit bias" and the `keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))` construction at `:1221`). 1-bit validator bias and structural mitigations (terminal event, 3-day stall trigger, diluted by historical words) unchanged. |
| F-25-09 | DegenerusGame (moved from AdvanceModule) | SUPERSEDED | The deterministic `keccak256(day, address(this))` fallback when no VRF word exists now lives in `DegenerusGame.sol:856-860` within `deityBoonData()` (`if (rngWord == 0) rngWord = uint256(keccak256(abi.encodePacked(day, address(this))));`). The code path was relocated from the original `_deityDailySeed` helper on AdvanceModule into a view function on the main Game contract, but the conclusion stands: the fallback fires only before the first `advanceGame` or during a prolonged VRF stall, affects cosmetic/utility display only, and is not an economic attack vector. |
| F-25-10 | DegenerusGame | HOLDS | `_processMintPayment` still present at `DegenerusGame.sol:903`; documentation at `:336` still reads "DirectEth: msg.value must be >= costWei (overage ignored for accounting)" and the earlybird `msg.value > costWei ? costWei : msg.value` bound at `:386` confirms the overpayment-retained semantics. `distributeYieldSurplus` still sweeps untracked surplus (JackpotModule `:737`). |
| F-25-11 | Multiple (all BPS arithmetic sites) | HOLDS | BPS integer-division truncation is a universal property of Solidity arithmetic with no workaround; the `distributeYieldSurplus` sweep mechanism remains in place (JackpotModule `:737`). 417 references to BPS / basis-point / `3000/10_000`-style patterns across 23 files confirm the pattern is unchanged. |
| F-25-12 | DegenerusGameStorage / DecimatorModule | HOLDS | `claimablePool` still present in `storage/DegenerusGameStorage.sol` (6 refs) with the documented `claimablePool >= SUM(claimableWinnings[*])` over-reservation invariant. Decimator settlement flow unchanged. |
| F-25-13 | DegenerusGameAdvanceModule, JackpotModule, DegenerusGameStorage | HOLDS | uint128 narrowing casts on pool variables remain in place across the five SSTORE sites catalogued by v25.0 Phase 216-02. Pool-value bound (~1.2e26 wei) vs uint128 max (~3.4e38 wei) unchanged; 10^12x safety margin unchanged. Phase 214-02's SAFE verdicts on the 75-site SSTORE catalogue still apply. |

*No milestone-level findings were produced during the v26.0-v27.0 cycle; the milestone-findings sub-section from v25.0 is therefore omitted.*

### Regression Summary

**Total items checked:** 13 (F-25-01 through F-25-13 from the v25.0 Master Delta Findings Report)

| Status | Count | Findings |
|--------|-------|----------|
| HOLDS | 12 | F-25-01, F-25-02, F-25-03, F-25-04, F-25-05, F-25-06, F-25-07, F-25-08, F-25-10, F-25-11, F-25-12, F-25-13 |
| SUPERSEDED | 1 | F-25-09 (deity-boon deterministic fallback moved from `AdvanceModule._deityDailySeed` into `DegenerusGame.deityBoonData`; same conclusion applies) |
| FIXED | 0 | -- |
| INVALIDATED | 0 | -- |

**Verdict:** No regressions detected. All 13 prior v25.0 findings remain in their documented state -- 12 unchanged (HOLDS) and 1 code-path-relocation with preserved conclusion (SUPERSEDED). The single SUPERSEDED finding (F-25-09) is a benign refactor: the deterministic keccak fallback moved from a private helper on `DegenerusGameAdvanceModule` into a view function on `DegenerusGame` during v26.0 / v27.0 cycle work but retains the same tier-3 "no VRF word yet" semantics and the same cosmetic-only, non-economic impact. No INFO-level observation has been invalidated by v26.0 or v27.0 changes.
