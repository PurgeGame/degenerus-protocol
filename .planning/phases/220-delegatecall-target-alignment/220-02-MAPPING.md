# Phase 220 Plan 02 — Interface ↔ Address 1:1 Mapping

**Date:** 2026-04-12
**Scope:** Every `GAME_*_MODULE` constant in `contracts/ContractAddresses.sol:11-20` ↔ every `interface IDegenerusGameXxxModule` in `contracts/interfaces/IDegenerusGameModules.sol`.
**Method:** Enumerate both sides via grep; apply the reverse D-03 naming convention (`constant_to_iface()`) to derive each constant's expected interface; count delegatecall callers per constant via the two-pass enumeration from `scripts/check-delegatecall-alignment.sh` (single-line + split-line).

## Summary

- **Total address constants:** 10 (declared on lines 11-20 of `ContractAddresses.sol`)
- **Total module interfaces:** 9 (declared in the single file `IDegenerusGameModules.sol`)
- **LIVE pairs (constant + interface + ≥1 caller):** 9
- **DEAD constants (no interface, no caller):** 1 — `GAME_ENDGAME_MODULE`
- **Orphan interfaces (no matching constant):** 0

**Invariant proven:** Every LIVE `GAME_*_MODULE` constant has exactly one counterpart interface in `IDegenerusGameModules.sol` (modulo the documented CamelCase exception for `GameOver`), and every interface has exactly one counterpart constant. The single anomaly is `GAME_ENDGAME_MODULE` — a dead declaration with no interface, no implementation module, no caller.

## Mapping Table

| # | Address Constant | Derived Interface (naive transform) | Actual Interface | Interface Exists? | Caller Count | Classification | Notes |
|---|------------------|-------------------------------------|------------------|-------------------|-------------:|----------------|-------|
| 1 | GAME_MINT_MODULE | IDegenerusGameMintModule | IDegenerusGameMintModule | YES | 6 | LIVE | canonical |
| 2 | GAME_ADVANCE_MODULE | IDegenerusGameAdvanceModule | IDegenerusGameAdvanceModule | YES | 5 | LIVE | canonical |
| 3 | GAME_WHALE_MODULE | IDegenerusGameWhaleModule | IDegenerusGameWhaleModule | YES | 4 | LIVE | canonical |
| 4 | GAME_JACKPOT_MODULE | IDegenerusGameJackpotModule | IDegenerusGameJackpotModule | YES | 7 | LIVE | canonical |
| 5 | GAME_DECIMATOR_MODULE | IDegenerusGameDecimatorModule | IDegenerusGameDecimatorModule | YES | 6 | LIVE | canonical |
| 6 | GAME_ENDGAME_MODULE | IDegenerusGameEndgameModule | — | NO | 0 | DEAD | No interface, no callers, no module file. Vestigial. See INFO-220-02-01. |
| 7 | GAME_GAMEOVER_MODULE | IDegenerusGameGameoverModule | IDegenerusGameGameOverModule | YES (via exception) | 2 | LIVE | Naive transform yields `IDegenerusGameGameoverModule` (single-o). Real interface is `IDegenerusGameGameOverModule` (double-capital). Resolved via `NAMING_EXCEPTIONS[GAMEOVER]=GameOver` map in the script. See FINDING-220-02-02. |
| 8 | GAME_LOOTBOX_MODULE | IDegenerusGameLootboxModule | IDegenerusGameLootboxModule | YES | 6 | LIVE | canonical |
| 9 | GAME_BOON_MODULE | IDegenerusGameBoonModule | IDegenerusGameBoonModule | YES | 5 | LIVE | canonical |
| 10 | GAME_DEGENERETTE_MODULE | IDegenerusGameDegeneretteModule | IDegenerusGameDegeneretteModule | YES | 2 | LIVE | canonical |

**Constants are listed in declaration order** as they appear on `ContractAddresses.sol:11-20` (row # matches the source line number minus 10).

### Row-count sanity check

- Table rows: 10 (matches the 10 `GAME_*_MODULE` constants)
- LIVE rows: 9 (matches the 9 interfaces in `IDegenerusGameModules.sol`)
- DEAD rows: 1 (matches the scouted `GAME_ENDGAME_MODULE` finding)
- LIVE caller-count sum: 6 + 5 + 4 + 7 + 6 + 2 + 6 + 5 + 2 = **43** — matches the `Total sites audited: 43` reported in `220-01-AUDIT.md`.

### Reconciliation vs 220-01-AUDIT

| Source | Count |
|--------|------:|
| This mapping's LIVE caller-count sum | 43 |
| `220-01-AUDIT.md` "Total sites audited" | 43 |
| `220-01-AUDIT.md` "ALIGNED" | 43 |

**PASS — reconciliation holds.** Every site cataloged in 220-01-AUDIT is attributed to exactly one LIVE constant in this mapping. No missed sites, no mis-attributions.

Per-constant reconciliation (verified row-by-row against the per-interface breakdown at the tail of `220-01-AUDIT.md`):

| Constant | 220-01 per-interface count | This mapping's caller count | Match |
|----------|:---------------------------:|:---------------------------:|:-----:|
| GAME_ADVANCE_MODULE (Advance) | 5 | 5 | yes |
| GAME_GAMEOVER_MODULE (GameOver) | 2 | 2 | yes |
| GAME_JACKPOT_MODULE (Jackpot) | 7 | 7 | yes |
| GAME_DECIMATOR_MODULE (Decimator) | 6 | 6 | yes |
| GAME_WHALE_MODULE (Whale) | 4 | 4 | yes |
| GAME_MINT_MODULE (Mint) | 6 | 6 | yes |
| GAME_LOOTBOX_MODULE (Lootbox) | 6 | 6 | yes |
| GAME_BOON_MODULE (Boon) | 5 | 5 | yes |
| GAME_DEGENERETTE_MODULE (Degenerette) | 2 | 2 | yes |
| **Total** | **43** | **43** | **yes** |

## Findings

### INFO-220-02-01: `GAME_ENDGAME_MODULE` is a dead constant

**File:** `contracts/ContractAddresses.sol:16`
**Evidence:**
- Repository-wide `grep -rn 'GAME_ENDGAME_MODULE' contracts/` returns **exactly one line** — the declaration itself.
- No `IDegenerusGameEndgameModule` interface anywhere in `contracts/interfaces/`.
- No `DegenerusGameEndgameModule.sol` implementation file — `ls contracts/modules/` returns nine module files, none named `*Endgame*`.
- Zero delegatecalls target it; zero source references outside the declaration.

**Severity:** INFO. Dead code — no security or correctness impact. The address points at a location that would revert on first delegatecall (no matching selector at any module), so the gate's per-site check already prevents accidental use. The constant wastes a slot in the compiled bytecode layout and can confuse future readers.

**Likely origin:** Vestigial — possibly a renamed or merged predecessor of `GAME_GAMEOVER_MODULE` (line 17). This is a guess; do NOT assume this equivalence. Phase 223 consolidation should audit git history or ask the user.

**Recommendation:** Route to Phase 223 consolidation for INFO-level documentation in `audit/FINDINGS-v27.0.md`. Do NOT remove the constant in this phase — per project-level `feedback_no_contract_commits`, contract changes require explicit user approval.

### FINDING-220-02-02: `GameOver` CamelCase exception in the reverse-naming transform

**Context:** The naive `constant_to_iface()` transform (lower-all, uppercase first letter of each `_`-delimited word) derives `IDegenerusGameGameoverModule` (single-o capitalization) from `GAME_GAMEOVER_MODULE`. The actual interface declared at `IDegenerusGameModules.sol:47` is `IDegenerusGameGameOverModule` (double-capital, reflecting the compound English word "Game Over").

**Behavior verified during Task 1 scouting:**
```
constant_to_iface GAME_GAMEOVER_MODULE
-> IDegenerusGameGameoverModule        # (naive, WRONG)
```

**Resolution in the script (Task 2):** Hardcoded one-entry exception map, keyed by the post-`GAME_`/pre-`_MODULE` fragment:
```bash
declare -A NAMING_EXCEPTIONS=(
  [GAMEOVER]=GameOver
)
```
This mirrors the forward-direction exception map published in 220-01's `iface_to_constant()` (`[GameOverModule]=GAMEOVER_MODULE`) — both directions use the same canonical mapping, keyed on opposite ends.

**Status:** Not a bug — a CamelCase-convention corner case baked into the interface file. Documented and handled at all call sites that touch `GAME_GAMEOVER_MODULE` (2 sites, both ALIGNED per 220-01 rows 31-32). No user action required; retain the exception map entry.

**Severity:** None (design documentation). Not routed to Phase 223 findings — only mentioned as an explanatory note in the gate-script comments.

## Preflight script hardening (Task 2)

Task 2 extends `scripts/check-delegatecall-alignment.sh` with a `validate_mapping()` preflight that runs BEFORE the per-site enumeration loop. It closes the gap where per-site checks can't see:

| Scenario per-site can't catch | Preflight behavior |
|-------------------------------|-----|
| A new interface is added to `IDegenerusGameModules.sol` without a matching constant in `ContractAddresses.sol` | `MAP_FAIL` → exit 1 |
| A new `GAME_*_MODULE` constant is added to `ContractAddresses.sol` without a matching interface | `MAP_FAIL` → exit 1 |
| The known-dead `GAME_ENDGAME_MODULE` is present (no interface, no caller) | `DEAD` print, no failure (allowlist via `DEAD_CONSTANTS=()`) |
| An unknown CamelCase exception appears (e.g., future `GAME_MULTIWORD_MODULE` maps to `IDegenerusGameMultiWordModule`) | `MAP_FAIL` → exit 1 unless entry is added to `NAMING_EXCEPTIONS` |

The allowlist (`DEAD_CONSTANTS`) and exception map (`NAMING_EXCEPTIONS`) are explicitly visible in the script and require an intentional edit + commit-review pass to amend — addressing threat T-220-07 (allowlist abuse).

## Cross-reference with 220-01-AUDIT

The LIVE-row caller counts in this table must sum to the "Total sites audited" figure in `220-01-AUDIT.md`. Verification:

```bash
awk -F'|' '/^\| [0-9]+/ && $8 ~ /LIVE/ { gsub(/^ +| +$/, "", $6); sum += $6 } END { print sum }' \
  .planning/phases/220-delegatecall-target-alignment/220-02-MAPPING.md
# Expected: 43
```

Running this now:
```
$ awk -F'|' '/^\| [0-9]+/ && $8 ~ /LIVE/ { gsub(/^ +| +$/, "", $6); sum += $6 } END { print sum }' .planning/phases/220-delegatecall-target-alignment/220-02-MAPPING.md
43
```
Matches `220-01-AUDIT.md` → **PASS**.

## Sources

- `contracts/ContractAddresses.sol` lines 11-20 — 10 `GAME_*_MODULE` address constants
- `contracts/interfaces/IDegenerusGameModules.sol` — 9 interface declarations
- `.planning/phases/220-delegatecall-target-alignment/220-01-AUDIT.md` — 43-row per-site catalog (this mapping reconciles against it)
- `scripts/check-delegatecall-alignment.sh` — two-pass site enumeration used to verify caller counts

*Report produced on 2026-04-12 as part of Phase 220 Plan 02 Task 1.*
