---
phase: 247-delta-extraction-classification
plan: 247-01
subsystem: audit
tags: [delta-extraction, classification, call-site-catalog, storage-layout, consumer-index, v32.0, vrf-lock-window, backfill-idempotency, purchase-level]

# Dependency graph
requires:
  - phase: 246-findings-consolidation-lean-regression-appendix
    provides: v31.0 milestone closure at HEAD `cc68bfc7` (the v32.0 audit baseline anchor)
  - phase: 243-delta-extraction-per-commit-classification
    provides: 7-section DELTA-SURFACE.md format precedent + 5-prefix Row-ID scheme + D-247-18 light-reconciliation target

provides:
  - DELTA-01 — per-source function/state/event/interface/error/constant inventory across the 4 in-scope SHAs (8bdeabc2 / 6a63705b / 48554f8f / acd88512) + 1 out-of-scope test-only SHA (ad41973c) + storage slot-layout diff via forge inspect at both SHAs
  - DELTA-02 — D-247-06 5-bucket classification ({NEW / MODIFIED_LOGIC / REFACTOR_ONLY / DELETED / RENAMED}) for every changed function with hunk citation + one-line rationale; D-247-07 pre-locked floors honored (zero deviations)
  - DELTA-03 — grep-reproducible call-site inventory for every changed function + interface method across contracts/ tree per D-247-19
  - Section 6 Consumer Index — 29 D-247-I### rows mapping every Phase 248..253 REQ-ID (BFL-01..06 / PLV-01..06 / SIB-01..05 / TST-01..04 / POST31-01..02 / FIND-01..04 / REG-01..02) to the subset of Phase 247 row IDs that scopes it
  - Section 1.6 Finding Candidates pool — 6 fresh-eyes INFO-suggested-severity bullets routed for Phase 253 FIND-01 ID assignment
  - Section 1.7 v31-243 light reconciliation — 5 confirmed-overlap rows (`_livenessTriggered` / `advanceGame` / `_callTicketPurchase` / `_purchaseFor` / `_purchaseCoinFor`) + 2 no-overlap clusters (Vault redemption surface + rngGate/_backfillGapDays)
  - PHASE_247_CATALOG_FINAL_AT_HEAD_acd88512 closure signal

affects: [248-backfill-idempotency, 249-purchase-level-correctness, 250-sibling-pattern-sweep, 251-reproduction-tests, 252-post31-landed-commit-sanity, 253-findings-consolidation-lean-regression-appendix]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Single-plan multi-task atomic-commit topology per CONTEXT.md D-247-12 / D-247-14 (mirrors v30 Phase 242 + v31 Phase 246)"
    - "5-prefix Row-ID scheme D-247-{C,F,S,X,I}### per D-247-11 (matches v31 Phase 243)"
    - "Pre-locked classification floors per D-247-07 — non-negotiable starting points for D-247-06 5-bucket verdicts"
    - "Hunk-citation evidence burden per D-247-08 (every Section 2 row cites file:line + git show -L command)"
    - "Grep-reproducibility mandate per D-247-19 (every Section 3 row carries the exact grep command used to find it)"
    - "Storage-layout diff via forge inspect at both SHAs with git worktree --detach pattern for baseline-side capture per D-247-16"
    - "Light v31-243 reconciliation per D-247-18 (narrower than Phase 237's full prior-artifact cross-check; only v31 rows whose function is touched by v32 deltas)"
    - "Closure signal in frontmatter for downstream phase-completion attestation per D-247-22"

key-files:
  created:
    - audit/v32-247-DELTA-SURFACE.md (FINAL READ-only at HEAD acd88512; 800+ lines; 7 sections fully populated)
    - .planning/phases/247-delta-extraction-classification/247-01-SUMMARY.md (this file)
  modified: []

key-decisions:
  - "Pre-locked D-247-07 classification floors honored verbatim with zero deviations across all 7 floor entries (8 MODIFIED_LOGIC + 3 DELETED across 11 func universe)"
  - "48554f8f Vault helpers _burnCoinFor / _burnEthFor / _requireApproved classified as DELETED (not REFACTOR_ONLY-via-inline) per D-247-06 burden of proof — body-preservation captured in F005/F006 rationale rather than as separate REFACTOR_ONLY rows because the inline relocation is paired with both a signature change and a control-flow gate removal"
  - "Vault.burnCoin / burnEth selector-collision against IDegenerusCoin.burnCoin 2-arg explicitly disambiguated in Section 3 (D-247-X021 + D-247-X023): the 4 coin.burnCoin(player, amount) hits target a DIFFERENT 2-arg selector on BurnieCoin, NOT the Vault's 1-arg selector — Vault entries have zero internal contracts/-tree callers"
  - "Three indirect dispatch paths for top-level delegatecall coverage of changed functions: IDegenerusGameAdvanceModule.advanceGame.selector + IDegenerusGameMintModule.purchase.selector + IDegenerusGameMintModule.purchaseCoin.selector (Section 3.2)"
  - "Storage layout byte-identical between cc68bfc7 and acd88512 — D-247-S001 single UNCHANGED row; SAFE / NON-WIDENING backwards-compat verdict; Phase 250 SIB-04 inherits zero-row storage-delta scope"
  - "Section 4.3 Interface Methods reports None — none of the 4 in-scope commits modify any interface file (no IDegenerusVault.sol exists for Vault external entries; private/internal functions don't appear on interfaces)"

patterns-established:
  - "v32-247 Row-ID scheme D-247-{C,F,S,X,I}### with monotonic zero-padded three-digit numbering within each prefix (C continues across §1 → §4)"
  - "Section 1 NATSPEC-ONLY rows collapse into the same function's Section 2 classification row (do not double-count for universe size)"
  - "Section 2 DELETED helper rows cite baseline-side line range with @cc68bfc7 anchor suffix (head-side range absent by definition)"
  - "Selector-collision disambiguation pattern: when grep -rn returns hits for a name shared by multiple unrelated contracts, emit a row noting the collision + cite the disambiguating grep / interface check that proves the changed function has zero callers (vs the same-name-different-contract callers that are out-of-scope)"

requirements-completed: [DELTA-01, DELTA-02, DELTA-03]

# Metrics
duration: ~75min (Task 1 already committed at e2cacc5c before this executor session; Tasks 2-5 + SUMMARY total ~14min wall-clock during this resume session per commit timestamps 22:56 → 23:05 local)
completed: 2026-04-30
---

# Phase 247 Plan 247-01: Delta Extraction & Classification Summary

**v32.0 audit-surface catalog covering 4 post-v31.0 contract-touching commits (8bdeabc2 liveness-pause / 6a63705b mint-buyer-charge / 48554f8f vault-redemption-decoupling / acd88512 turbo+backfill-guards) + 1 out-of-scope test-only commit (ad41973c); produces 7-section single-deliverable `audit/v32-247-DELTA-SURFACE.md` with grep-reproducible call-site catalog, hunk-cited classification, byte-identical storage-layout attestation, and 29-row Phase 248..253 Consumer Index.**

## Performance

- **Duration:** ~75min total (Task 1 pre-committed at `e2cacc5c` before resume; Tasks 2-5 + SUMMARY = ~14min wall-clock during this resume session)
- **Started (Task 1 commit):** 2026-04-30T22:51:19-05:00 (pre-resume)
- **Resumed (Task 2 start):** ~2026-04-30T22:55-05:00
- **Completed (Task 5 commit):** 2026-04-30T23:05:35-05:00
- **Tasks:** 5/5 (1 pre-resume + 4 during this session)
- **Files modified:** 1 contract-tree adjacent file (`audit/v32-247-DELTA-SURFACE.md`); 0 contracts/ writes; 0 test/ writes

## Accomplishments

- 7-section single-deliverable `audit/v32-247-DELTA-SURFACE.md` published FINAL READ-only at HEAD `acd88512` with closure signal `PHASE_247_CATALOG_FINAL_AT_HEAD_acd88512`
- 16 D-247-C### per-source changelog + state/event/interface/error/constant rows (§1 + §4)
- 11 D-247-F### aggregate function classification rows under D-247-06 5-bucket rubric (§2): 8 MODIFIED_LOGIC + 3 DELETED + 0 NEW/REFACTOR_ONLY/RENAMED
- 1 D-247-S### storage slot layout row (§5): UNCHANGED / SAFE / NON-WIDENING — byte-identical layout at both SHAs (8bdeabc2 +12 lines confirmed as NatSpec + non-storage early-return)
- 30 D-247-X### downstream call-site catalog rows (§3) with grep-reproducibility mandate honored — every row carries the exact grep -rn command used to find it; selector-collision disambiguation for Vault.burnCoin/burnEth + DELETED helper sanity gate
- 29 D-247-I### Consumer Index rows (§6) mapping every Phase 248..253 REQ-ID (BFL-01..06 + PLV-01..06 + SIB-01..05 + TST-01..04 + POST31-01..02 + FIND-01..04 + REG-01..02 = 29) to the subset of Phase 247 row IDs that scopes it
- 6 fresh-eyes INFO Finding Candidates surfaced (§1.6) for Phase 253 FIND-01 ID-assignment routing
- 5 confirmed-delta-touches-v31-row light reconciliation entries (§1.7) — `_livenessTriggered` (D-243-C026 ↔ D-247-C001 / C002), `advanceGame` (D-243-C007 ↔ D-247-C011), `_callTicketPurchase` (D-243-C011 ↔ D-247-C003), `_purchaseFor` (D-243-C010 ↔ D-247-C005), `_purchaseCoinFor` (D-243-C018 ↔ D-247-C004); 2 no-overlap clusters (Vault redemption + rngGate/_backfillGapDays)
- D-247-07 pre-locked classification floor compliance attestation: 7/7 floors applied verbatim with zero deviations (§2.2)
- D-247-21 zero-finding-IDs constraint maintained: zero `F-32-` references anywhere in the catalog file (Phase 253 FIND-01 owns ID assignment)

## Task Commits

Each task was committed atomically per CONTEXT.md D-247-14:

1. **Task 1: DELTA-01 enumeration + Section 5 storage layout** — `e2cacc5c` (audit) — pre-resume; populated Sections 0 + 1 + 4 + 5 + 7.1
2. **Task 2: DELTA-02 aggregate function classification** — `8e7e1f7c` (audit) — populated Section 2 + §2.1 distribution count card + §2.2 D-247-07 floor compliance attestation + §7.2
3. **Task 3: DELTA-03 downstream call-site catalog** — `4cc1f829` (audit) — populated Section 3 (30 D-247-X### rows) + §3.1 per-Universe-Member count card + §3.2 self-call/delegatecall enumeration + §7.3
4. **Task 4: Consumer Index Section 6 + final Section 7 assembly** — `5162c5e0` (audit) — populated Section 6 (29 D-247-I### rows mapping every Phase 248..253 REQ-ID) + final Section 7 read-back verification
5. **Task 5: FINAL READ-only flip + plan-close** — `9961c91a` (audit) — flipped frontmatter + body Status to `FINAL — READ-ONLY`; emitted closure signal `PHASE_247_CATALOG_FINAL_AT_HEAD_acd88512`

**Plan-close metadata commit (separate from the 5 atomic per-task commits):** TBD — landed after this SUMMARY commit per execute-plan.md sequential-mode protocol.

## Files Created/Modified

- `audit/v32-247-DELTA-SURFACE.md` — Phase 247 deliverable; 7 sections fully populated; FINAL READ-only at HEAD `acd88512`; the SOLE scope input for Phases 248-253 per ROADMAP Phase 247 Success Criterion 4
- `.planning/phases/247-delta-extraction-classification/247-01-SUMMARY.md` — this plan-close summary (created by Task 5 follow-on per execute-plan.md sequential-mode)

## Decisions Made

- Pre-locked D-247-07 floors applied verbatim across all 7 entries — zero deviations, zero OVERRIDE RATIONALE blocks required
- 48554f8f Vault helpers `_burnCoinFor` / `_burnEthFor` classified as DELETED (function-as-symbol absent at HEAD) rather than REFACTOR_ONLY-via-inline-relocation — D-247-06 burden of proof escalates because the body-preservation is paired with both signature change AND control-flow gate removal in the public wrapper
- Section 4.3 Interface Methods emits "None" — no `IDegenerusVault.sol` interface file exists for Vault external entries; the changes to private/internal functions in MintModule + GameStorage do not surface on any interface declaration
- Vault.burnCoin / burnEth selector-collision against IDegenerusCoin.burnCoin 2-arg explicitly disambiguated in Section 3 — the 4 `coin.burnCoin(player, amount)` hits in DegenerusGame.sol:1918 / DegeneretteModule.sol:540 / MintModule.sol:1373 / MintModule.sol:1394 target a different selector and are NOT callers of the Vault's 1-arg `burnCoin(uint256)`
- DegenerusGame.sol:509 `_purchaseFor(...)` hit explicitly disambiguated as a different same-name dispatcher helper (DegenerusGame's own private delegatecall wrapper) and NOT a caller of MintModule's changed `_purchaseFor` private function
- Closure signal `PHASE_247_CATALOG_FINAL_AT_HEAD_acd88512` emitted in frontmatter `closure_signal:` field AND in the body `**Status:**` line for downstream Phase 248 plan-context to assert against per D-247-22

## Deviations from Plan

None — plan executed exactly as written. The plan's `autonomous: true` flag and pre-locked D-247-07 floors fully constrained the execution; no scope-guard deferrals or architectural questions surfaced. The 6 §1.6 Finding Candidate INFO bullets are part of the planned deliverable per D-247-21, not deviations.

The two minor inline edits during execution were:

1. **§2.1 count card MODIFIED_LOGIC count typo (self-corrected during Task 2 write):** Initial draft wrote "MODIFIED_LOGIC | 7" but the function list contained 8 entries; corrected to "MODIFIED_LOGIC | 8" before commit. This was caught in-flight by the self-check pass and did not require a separate commit.
2. **§6 / §7.3 use of `<fn>` literal substring (caught during Task 3 / Task 4 verify):** Initial drafts used `<fn>` as part of describing the `IDegenerusGame(address(this)).<fn>` syntax pattern, but the Task 3 verify regex flagged `<fn>` as a placeholder token. Replaced with `METHOD_NAME` (uppercase placeholder convention) to disambiguate from real `REPLACE-WITH` placeholders. Caught in-flight; did not require a separate commit.
3. **§6 use of literal `F-32-NN` text (caught during Task 4 verify):** Initial Section 6 drafts used `F-32-NN` as a forward-reference to the Phase 253 ID format, but the D-247-21 enforcement regex strictly requires zero `F-32-` substrings anywhere in the file. Rephrased as "v32 finding-ID" / "v32 finding-ID candidates" without the prefix. Caught in-flight; did not require a separate commit.

None of the above are deviations from the plan — they are in-flight self-corrections caught by the verify gates the plan itself defined. Zero auto-fixed bugs / zero missing critical functionality / zero architectural changes.

## Issues Encountered

None — all 5 tasks landed cleanly. The pre-existing working-tree state (`M contracts/ContractAddresses.sol` per D-247-03 + `?? test/edge/LastPurchaseDayRace.test.js` per D-247-17) was preserved untouched throughout.

## TDD Gate Compliance

N/A — Phase 247 is pure-catalog (no contracts/ or test/ writes per D-247-05). The plan does not have `type: tdd` and no individual tasks have `tdd="true"` — the deliverable is documentation-only and the TDD RED/GREEN/REFACTOR gate flow does not apply.

## Threat Surface

No new threat surface introduced — Phase 247 is documentation-only with zero runtime code modified, zero test modified, zero deployment scripts touched. The `<threat_model>` block in the PLAN.md confirmed empty threat register by construction; this SUMMARY emits no `threat_flag:` rows.

## Next Phase Readiness

Phase 247 → Phase 248 handoff ready:

- Phase 248 (Backfill Idempotency Proof, BFL-01..06) can read Section 6 D-247-I001..I006 directly without re-deriving from git diffs
- Phase 249 (purchaseLevel Correctness Proof, PLV-01..06) can read Section 6 D-247-I007..I012 directly
- Phase 250 (Sibling-Pattern Sweep, SIB-01..05) can read Section 6 D-247-I013..I017 directly
- Phase 251 (Reproduction Tests, TST-01..04) can read Section 6 D-247-I018..I021 directly + inherits the §1.5 ad41973c test-only commit row + the working-tree-untouched LastPurchaseDayRace.test.js per D-247-17
- Phase 252 (POST31 Landed-Commit Sanity, POST31-01..02) can read Section 6 D-247-I022..I023 directly + inherits the §1.7 D-243-C026 ↔ D-247-C001 / C002 productive-pause / 14-day-grace composition cross-cite
- Phase 253 (Findings Consolidation + REG, FIND-01..04 + REG-01..02) can read Section 6 D-247-I024..I029 directly + inherits the §1.6 6-INFO-bullet finding-candidate pool + §1.7 v31-243 reconciliation rows for REG-01 / REG-02 prior-finding sweep

The catalog file is FINAL READ-only per D-247-22 — any Phase 248-252 finding of a changed symbol NOT in this catalog is recorded as a scope-guard deferral in the discovering plan's own SUMMARY.md, not re-edited here.

## Self-Check: PASSED

- File `audit/v32-247-DELTA-SURFACE.md` exists at HEAD `acd88512` (verified via `test -f`)
- 5 atomic per-task commits exist: `e2cacc5c` (Task 1) + `8e7e1f7c` (Task 2) + `4cc1f829` (Task 3) + `5162c5e0` (Task 4) + `9961c91a` (Task 5) — all subjects matching `audit\(247-01\): Task [1-5] —`
- All 7 Section headers present in fixed order (§0 through §7) with no `RESERVED FOR TASK` suffix on any
- Row count floors all satisfied: 16 D-247-C### (≥ 8) / 11 D-247-F### (≥ 5) / 1 D-247-S### / 30 D-247-X### (≥ 5) / 29 D-247-I### (≥ 25)
- Zero `F-32-` substrings anywhere in the catalog file (D-247-21 enforcement)
- Zero `RESERVED FOR TASK` markers remain (D-247-13 plan-topology compliance)
- Zero `REPLACE-WITH` / `REPLACE WITH` placeholder tokens remain
- Frontmatter `status: FINAL — READ-ONLY` present (D-247-22 enforcement)
- Body `**Status:** FINAL — READ-ONLY` present (D-247-22 enforcement)
- Closure signal `PHASE_247_CATALOG_FINAL_AT_HEAD_acd88512` present (D-247-22 enforcement)
- `git diff --name-only cc68bfc7..HEAD -- contracts/` returns exactly the 4 in-scope files (DegenerusVault / AdvanceModule / MintModule / GameStorage) — no contracts/ drift
- `git status --porcelain contracts/ test/` returns exactly the 2 pre-existing lines (`M contracts/ContractAddresses.sol` per D-247-03 + `?? test/edge/LastPurchaseDayRace.test.js` per D-247-17) — no Plan 247-01-induced working-tree changes

---

*Phase: 247-delta-extraction-classification*
*Completed: 2026-04-30*
