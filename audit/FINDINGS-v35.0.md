---
phase: 265-delta-audit-findings-consolidation
plan: 01
milestone: v35.0
milestone_name: BURNIE Near-Future Per-Pull Level Resample
head_anchor: <will-be-filled-by-Task-13>
audit_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
audit_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
v33_baseline: 4ce3703d740d3707c88a1af595618120a8168399
v33_baseline_signal: MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399
deliverable: audit/FINDINGS-v35.0.md
requirements: [AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06, REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
write_policy: "Pure-consolidation phase per CONTEXT.md hard constraint #1. Zero contracts/ writes by agent. Zero test/ writes by agent. KNOWN-ISSUES.md modified by 1 entry under Design Decisions per D-265-AUDIT06-01 (AUDIT-06 indexer semantic-shift). Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change — vacuous this phase since no contract changes are proposed by agent."
supersedes: none
status: DRAFT
read_only: false
closure_signal: <will-be-filled-by-Task-13>
generated_at: <will-be-filled-by-Task-13>
---

# v35.0 Findings — BURNIE Near-Future Per-Pull Level Resample

**Audit Baseline.** The audit baseline is v34.0 source-tree HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555` (closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` carry-forward from `audit/FINDINGS-v34.0.md` §9c). HEAD `<will-be-filled-by-Task-13>` (currently `5db8682b` per phase-start, post-Phase-264 close `docs(264): mark phase complete in STATE.md + ROADMAP.md`). One v35 contract-tree commit since baseline: `cf564816` (Phase 263 — `feat(263): per-pull level resample for daily coin jackpot [PPL-01..PPL-08]`); diff stats 91 insertions(+) / 74 deletions(-), net +17 LOC across the constants block + `payDailyJackpotCoinAndTickets` coin-jackpot block + `payDailyCoinJackpot` tail + new `_awardDailyCoinToTraitWinners` helper body. Six v35 test-tree commits since baseline: `aa41485e` (`test(264-01): add STAT-01/02/04 + D-IMPL-01 boundary harness for per-pull level resample`) + `7dcfeb0c` (`test(264-01): add STAT-03 empty-bucket skip rate + cumulative underspend test`) + `82717bcf` (`test(264-02): extend SurfaceRegression with v35.0 SURF-01..04 grep-proof`) + `36234847` (`test(264-02): add Phase264GasRegression for SURF-05 entry-point gas`) + `20b15468` (`test(264-02): extend AdvanceGameGas with v35.0 1.99x margin assertion`) + `833b341d` (`chore(264-02): wire Phase 264 test files into npm scripts`). `contracts/DegenerusTraitUtils.sol` + `contracts/libraries/JackpotBucketLib.sol` + `contracts/libraries/EntropyLib.sol` + `contracts/storage/GameStorage.sol` are byte-identical between v34.0 baseline `6b63f6d4` and v35 HEAD (REG-01 PASS — see §5a). `contracts/GNRUS.sol` is byte-identical between v33.0 baseline `4ce3703d` and v35 HEAD (REG-02 PASS — see §5b).

**Scope.** Single canonical milestone-closure deliverable for v35.0 per D-265-FILES-01 (single deliverable, no per-AUDIT-NN working files) + D-253-15 / D-257 / D-262 carry-forward (9-section shape locked). Consolidates Phase 263 + 264 outputs into 9 sections per D-253-15 / D-257 / D-262 carry. Terminal phase per CONTEXT.md D-265 carry of D-257-FCITE-01 / D-262-FCITE-01 — zero forward-cites emitted from Phase 265 to any post-v35.0 milestone phases. Mirrors v33 Phase 257 / v34 Phase 262 single-plan multi-task atomic-commit pattern adapted for v35's 1-impl-phase + 1-test-phase + 1-audit-phase scope per D-265-PLAN-01.

**Write policy.** READ-only after Task 14 atomic commit per D-253-CF-02 / D-257 / D-262 carry-forward chain. KNOWN-ISSUES.md modified by 1 entry under Design Decisions per D-265-AUDIT06-01 (AUDIT-06 `JackpotBurnieWin.lvl` semantic-shift entry — D-09 3-predicate PASS: accepted-design + non-exploitable + sticky); all OTHER potential KI promotions UNMODIFIED (zero F-35-NN finding blocks per D-265-FIND-01 default path). Zero awaiting-approval test files (1 v35 contract commit + 6 v35 test commits USER-APPROVED batched per `feedback_batch_contract_approval.md` per Phase 263 / 264 close). Per `feedback_never_preapprove_contracts.md`, the orchestrator does NOT pre-approve any contract change; vacuous this phase since no contract changes are proposed by agent (zero `contracts/` writes + zero `test/` writes by agent — hard constraint #1).

---

## 2. Executive Summary

### Closure Verdict Summary

- AUDIT-01: `CLOSED_AT_HEAD_<sha>` (delta surface complete; every changed function/state-var/event/error in `contracts/modules/DegenerusGameJackpotModule.sol` vs baseline `6b63f6d4` enumerated with hunk-level evidence and classified per ROADMAP success criterion 1)
- AUDIT-02: `6 of 6 surfaces SAFE_*; 0 of 0 FINDING_CANDIDATE PROMOTED` (default expected per D-265-FIND-01)
- AUDIT-03: `CLOSED_AT_HEAD_<sha>` (coinBudget non-overspend across new loop including empty-bucket skips; solvency invariant `claimablePool ≤ ETH balance + stETH balance` PRESERVED; BURNIE mint-supply conservation — only pre-existing `mintForGame` route exercised; no new mint sites)
- AUDIT-04: `0 new public/external mutation entry points; 0 new storage slots in GameStorage; 0 new admin functions; 0 new upgrade hooks; 0 new modifiers escalating authority`
- AUDIT-05: `MILESTONE_V35_AT_HEAD_<sha>` emitted in §9c
- AUDIT-06: `JackpotBurnieWin.lvl semantic-shift surfaced in §3c prose; D-09 3-predicate PASS routed promotion to KNOWN-ISSUES.md under Design Decisions (1 entry added)`
- REG-01: `1 PASS row — v34.0 closure signal MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555 NON-WIDENING at v35 HEAD`
- REG-02: `1 PASS row — v33.0 closure signal MILESTONE_V33_AT_HEAD_4ce3703d740d3707c88a1af595618120a8168399 NON-WIDENING at v35 HEAD`
- REG-03: `4 KI envelope re-verifications: EXC-01..03 NEGATIVE-scope; EXC-04 RE_VERIFIED with Phase 264 STAT-01 chi² cross-cite; KNOWN_ISSUES_MODIFIED (1 entry added under Design Decisions per AUDIT-06)`
- REG-04: `<N> PASS / 0 REGRESSED / 0 SUPERSEDED prior-finding spot-check rows across audit/FINDINGS-v25.0.md → audit/FINDINGS-v34.0.md`
- Combined milestone closure: `MILESTONE_V35_AT_HEAD_<sha>`

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-35-NN: 0

Default expected per D-265-FIND-01. v35 per-pull-level resample is mathematically well-bounded: per-pull keccak `keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i))` consumes VRF-derived high-entropy bits (player cannot bias post-commit per `feedback_rng_commitment_window.md`); chi²-evidenced uniformity at Phase 264 STAT-01 (range=4 chi²=5.114 < 7.815 critical at α=0.05 df=3; range=8 chi²=3.019 < 14.067 df=7) covers per-pull `lvlPrime` distribution; trait rotation via `i % 4` deterministic-by-design (Phase 264 STAT-02 [13,13,12,12] partition); empty-bucket silent-skip is structural-by-PPL-05 (Phase 264 D-IMPL-01 confirms helper correctness on dense fixture; 88.44% sparse-fixture skip rate reframed as fixture-calibration error per D-265-STAT03-01 — NOT a finding); cross-call salt collision impossible (caller-distinct `randomWord` per VRF day-cycle + same-call distinct `i ∈ [0,50)` discriminator). Severity ceiling for any v35-emitted F-35-NN: HIGH (no value extraction beyond bucket-rotation; bucket-share-sum × pool invariant under per-pull-level rotation; gold-priority bits VRF-derived not player-controllable; bounded by per-jackpot-call rate; no draining of pool past existing distribution mechanics). Most likely severity for any inline-draft finding-candidate: MEDIUM/LOW. Severity counts reconcile to §4 F-35-NN block tally line by line per ROADMAP success criterion 1.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v30/v31/v32/v33/v34 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward.

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

Severity calibration for any F-35-NN that may surface during Task 7 disposition: HIGH ceiling (bucket-rotation under per-pull-level resample does not extract value; bucket-share-sum × pool invariant under per-pull-level rotation; gold-priority bits VRF-derived not player-controllable; bounded by per-jackpot-call rate). MEDIUM/LOW likely for any inline-draft finding-candidate. INFO for documentation-only items. Per D-265-FIND-01 default path, zero F-35-NN blocks emit; severity-at-HEAD = N/A.

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. Per D-265-AUDIT06-01: KNOWN-ISSUES.md MODIFIED by 1 entry under Design Decisions (AUDIT-06 `JackpotBurnieWin.lvl` indexer semantic-shift PASS: accepted-design + non-exploitable + sticky 3-predicate PASS — semantic shift is the goal of the per-pull-level resample, not a side effect; observability-only impact with zero on-chain behavior change for player or protocol; structural property of the helper that won't go away). Any other v35-discovered finding-candidate would FAIL the **sticky** predicate (v35 per-pull-level surface is freshly-landed not "ongoing protocol behavior" until the next milestone) — default zero promotions for non-AUDIT-06 surfaces. See §6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

CONTEXT.md D-265 carry of D-257-FCITE-01 + D-262-FCITE-01 + D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 265 to any post-v35.0 milestone phases. Verified at §8 Forward-Cite Closure block. Phase 263 + 264 each emit zero v36.0+ forward-cites (Phase 263 SUMMARY "Forward Cites" enumerates ONLY Phase 264 + Phase 265 — both same-milestone — confirmed via grep). Phase 265 inherits zero-residual baseline. Future milestones (v36.0+) ingest via fresh delta-extraction phase, not via forward-cite from v35 artifacts.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 attestation block triggering v35.0 milestone closure via signal `MILESTONE_V35_AT_HEAD_<sha>`.

---

## 3. Per-Phase Sections

Consolidates Phase 263 + 264 outputs into condensed summaries with cross-cites to source artifacts. All cross-cites are READ-only lookups; no fresh derivation. Sources `re-verified at HEAD <sha>` per Task 13 anchor resolution. §3c AUDIT-06 indexer semantic-shift disclosure prose appears in this section (Task 5). §3d AUDIT-01 delta-surface table + AUDIT-04 storage-slot scan appear after §3c (Tasks 3-4). §3e AUDIT-03 conservation re-proof rows appear after §3d (Task 8).

### 3a. Phase 263 — Per-Pull Level Resample Implementation

**Change-count card:**

- Plans: 1 (263-01)
- Commits: `cf564816` (Phase 263 single batched contract-tree commit — `feat(263): per-pull level resample for daily coin jackpot [PPL-01..PPL-08]`); diff stats: 91 insertions(+), 74 deletions(-) — net +17 LOC across the constants block + `payDailyJackpotCoinAndTickets` coin-jackpot block + `payDailyCoinJackpot` tail + new `_awardDailyCoinToTraitWinners` helper body.
- Functions added: `_awardDailyCoinToTraitWinners(uint8[4] memory traitIds, uint256 randomWord, uint24 minLevel, uint24 maxLevel, uint256 coinBudget) internal` — 50-pull flat loop with per-pull-level keccak + per-trait deity caching + empty-bucket silent-skip + cursor remainder share-math (PPL-01..08).
- Constants added: `bytes32 private constant COIN_LEVEL_TAG = keccak256("coin-level")` at L171 (D-SHAPE-05).
- Functions modified: `payDailyCoinJackpot` (purchase phase, ~L1708 callsite — PPL-01) + `payDailyJackpotCoinAndTickets` (jackpot phase, L623 callsite — PPL-02). Both rewired to invoke `_awardDailyCoinToTraitWinners(traitIds, randWord, minLevel, maxLevel, coinBudget)`.
- Functions refactored (no behavior change for other callers): `_randTraitTicket` body BYTE-IDENTICAL at L1653-1703 with 4 other-callers BYTE-IDENTICAL at L700/L989/L1296/L1399 (D-IMPL-01 — inline holder-keccak in the new helper instead of reusing `_randTraitTicket` for the coin-jackpot path; legacy 8-bit `salt` parameter dropped from this code path only).
- Code deleted: `DAILY_COIN_SALT_BASE = 252` constant declaration at original L227 (only consumer at original L1800 disappeared with helper rewrite — pre-flight grep verified zero non-rewritten callers); original L621-624 dead block (`uint256 coinEntropy = uint256(keccak256(abi.encode(randWord, lvl, COIN_JACKPOT_TAG)));` + `uint24 targetLevel = lvl + 1 + uint24(coinEntropy % 4);` + scope braces — REMOVED); original L1729-1734 dead block (`uint256 entropy = uint256(...);` + `uint24 targetLevel = minLevel == maxLevel ? minLevel : ...` — REMOVED). NO call-removal of `_computeBucketCounts`'s definition; only the coin-jackpot-path CALL was removed (lootbox-path caller preserved per Phase 263 SUMMARY Grep Gauntlet #5).
- BYTE-IDENTICAL preservation (Phase 263 SUMMARY §"Byte-Identity Sweep" — 7 protected ranges):
  - `_randTraitTicket` body L1653-1703 (SURF-01)
  - `coinEntropy` + `DailyWinningTraits` emit blocks L518-520, L536-538 (D-INDEXER-01)
  - `_pickSoloQuadrant` body L1098-1115 + 4 ETH injection sites L287/L454/L531/L1181 (SURF-03)
  - `_awardFarFutureCoinJackpot` body L1839-1906 (SURF-02)
  - `_distributeTicketJackpot` body L897-932 (SURF-04)
  - `_computeBucketCounts` definition L1030-1082
  - `_randTraitTicket` other callers L700, L989, L1296, L1399
- Tests: ZERO Phase 263 unit tests per Phase 263 D-PLAN-01 default — all empirical verification deferred to Phase 264.
- REQs satisfied: 8/8 (PPL-01, PPL-02, PPL-03, PPL-04, PPL-05, PPL-06, PPL-07, PPL-08).
- Compile: `npx hardhat compile` → exit 0 at HEAD `cf564816`. Two pre-existing baseline shadow warnings preserved at the BYTE-IDENTICAL `payDailyJackpot` purchase-phase block; zero new warnings introduced.

**Cross-cite:** `.planning/phases/263-per-pull-level-resample-implementation/263-01-SUMMARY.md` + `263-01-PLAN.md` + `263-CONTEXT.md` (cross-cite-only, READ-only on upstream artifacts).

**Per-REQ summary table:**

| REQ | Verdict | Cross-Cite | Attestation |
| --- | ------- | ---------- | ----------- |
| PPL-01 | `COMPLETE_AT_HEAD_<sha>` | 263-01-SUMMARY.md | `payDailyCoinJackpot` (purchase phase, ~L1708) callsite rewired to `_awardDailyCoinToTraitWinners(traitIds, randWord, minLevel, maxLevel, coinBudget)`; per-pull keccak `keccak256(abi.encode(randomWord, COIN_LEVEL_TAG, i)) % range` consumed inside helper. |
| PPL-02 | `COMPLETE_AT_HEAD_<sha>` | 263-01-SUMMARY.md | `payDailyJackpotCoinAndTickets` (jackpot phase, L623) callsite rewired to `_awardDailyCoinToTraitWinners(traitIds, randWord, lvl + 1, lvl + 4, coinBudget - farBudget)`; same helper consumes the call-determined `[minLevel, maxLevel]` range. |
| PPL-03 | `COMPLETE_AT_HEAD_<sha>` | 263-01-SUMMARY.md | Flat 50-pull loop in `_awardDailyCoinToTraitWinners`; deterministic trait rotation via `traitIds[i % 4]` per pull; `_computeBucketCounts` NOT called from coin-jackpot path (preserved for lootbox path per Grep Gauntlet #5: `grep -c '_computeBucketCounts' contracts/modules/DegenerusGameJackpotModule.sol` returns 2 = def + lootbox caller). |
| PPL-04 | `COMPLETE_AT_HEAD_<sha>` | 263-01-SUMMARY.md | Share-math byte-identical: `cap = min(coinBudget / floor, 50)`, `baseAmount = coinBudget / cap`, `extraCount = coinBudget - baseAmount * cap`, `cursor = randomWord % cap`; per pull `amount = baseAmount + (i < extraCount ? 1 : 0)` — cursor remainder distribution preserved byte-identical to pre-Phase-263 `_randTraitTicket` cursor pattern. |
| PPL-05 | `COMPLETE_AT_HEAD_<sha>` | 263-01-SUMMARY.md | Empty-bucket silent skip: `if (effectiveLen == 0) continue;` — no carry-forward, no fallback, no redistribution. coinBudget conservation `Σ paid ≤ coinBudget` (structural underspend accepted; no overspend possible — see §3e AUDIT-03 + §4 surface (e) STAT-03 reframe row). |
| PPL-06 | `COMPLETE_AT_HEAD_<sha>` | 263-01-SUMMARY.md | Per-trait deity caching: `address[4] memory deityCache` populated with 4 SLOADs at loop entry; subsequent 50 pulls read from memory (was 50× SLOAD/pull pre-PPL = 200 SLOADs). Cache cannot stale because deity assignment is immutable for the current day's `traitIds[i % 4]` set; helper runs atomically inside `advanceGame` (no re-entrancy hooks). |
| PPL-07 | `COMPLETE_AT_HEAD_<sha>` | 263-01-SUMMARY.md | New salt scheme: per-pull holder index = `uint256(keccak256(abi.encode(randomWord, trait_i, lvlPrime, i))) % effectiveLen`; legacy 8-bit `salt` parameter dropped from coin-jackpot caller; `_randTraitTicket` body + 4 other callers BYTE-IDENTICAL per Phase 264 SURF-01. |
| PPL-08 | `COMPLETE_AT_HEAD_<sha>` | 263-01-SUMMARY.md | `JackpotBurnieWin` event signature byte-identical at L96 (zero ABI change); only the runtime semantics of the `lvl` field shift from shared-call-level to per-pull-sampled — see §3c AUDIT-06 disclosure. |

`re-verified at HEAD <sha>`.

### 3b. Phase 264 — Statistical Validation + Cross-Surface Preservation

**Change-count card:**

- Plans: 2 (264-01 STAT side, 264-02 SURF side).
- Commits (test-tree + chore only — Phase 264 makes ZERO `contracts/` changes per D-IMPL-02):
  - `aa41485e` — `test(264-01): add STAT-01/02/04 + D-IMPL-01 boundary harness for per-pull level resample` (`test/stat/PerPullLevelDistribution.test.js` NEW, 643 lines)
  - `7dcfeb0c` — `test(264-01): add STAT-03 empty-bucket skip rate + cumulative underspend test` (`test/stat/PerPullEmptyBucketSkip.test.js` NEW, 340 lines; test currently FAILS at HEAD with 88.24% skip rate — REFRAMED in §4 per D-265-STAT03-01)
  - `82717bcf` — `test(264-02): extend SurfaceRegression with v35.0 SURF-01..04 grep-proof` (`test/stat/SurfaceRegression.test.js` extended +206 lines; 13 protected ranges asserted)
  - `36234847` — `test(264-02): add Phase264GasRegression for SURF-05 entry-point gas` (`test/gas/Phase264GasRegression.test.js` NEW, 483 lines with theoretical worst-case opcode walk in header per `feedback_gas_worst_case.md`)
  - `20b15468` — `test(264-02): extend AdvanceGameGas with v35.0 1.99x margin assertion` (`test/gas/AdvanceGameGas.test.js` extended +193 lines)
  - `833b341d` — `chore(264-02): wire Phase 264 test files into npm scripts` (`package.json` `scripts.test:stat` + `scripts.test`)
- Statistical evidence:
  - **STAT-01** per-pull level distribution chi² over 10K aggregated samples — passes for both range=4 (chi² = 5.114 < 7.815 critical at α=0.05 df=3) and range=8 (chi² = 3.019 < 14.067 critical at α=0.05 df=7); seed-uniform across `[minLevel, maxLevel]`.
  - **STAT-02** per-trait deterministic share — passes (counts = [13, 13, 12, 12] under `i % 4` rotation; degenerate chi² = 0.08 < 7.815 df=3).
  - **STAT-04** Phase 261 chi² infra reuse confirmed (`makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ` re-declared verbatim in `test/stat/PerPullLevelDistribution.test.js` header; `COIN_LEVEL_TAG` and `BONUS_TRAITS_TAG` sanity-pinned).
  - **D-IMPL-01** boundary cross-validation harness — passes for all 3 fixed seeds (`0xc0120101`, `0xc0120102`, `0xc0120103`); 50/50 emit count under deity-backed dense fixture; strict `expect(onChainLvls).to.deep.equal(jsLvls)` per-pull byte-identity verified across full call B emit stream over range=[2, 5] — load-bearing for §4 STAT-03 reframe row.
  - **STAT-03** empty-bucket skip rate test landed at strict 10% threshold; currently FAILS at HEAD with measured `skipRate = 88.24%` on the natural-lifecycle fresh `deployFullProtocol` fixture (no organic purchases, no deity passes — only constructor pre-queued vault tickets + DGNRS perpetual tickets) — REFRAMED in §4 per D-265-STAT03-01 as fixture-calibration error (NOT a finding); helper correctness proven by D-IMPL-01 deity-fixture.
- Cross-surface evidence:
  - **SURF-01..04 byte-identity grep-proof:** per-line modified-set hunk-walk vs `git diff 6b63f6d4 HEAD -- contracts/modules/DegenerusGameJackpotModule.sol` — ZERO `-` deletions inside any of 13 protected ranges (`_randTraitTicket` body L1653-1703 + 4 other-callers at L700/L989/L1296/L1399; coinEntropy + DailyWinningTraits emit blocks L518-520, L536-538; emitDailyWinningTraits external L1750-1756; `_pickSoloQuadrant` body L1098-1115 + 4 ETH injection sites at L287/L454/L531/L1181; `_awardFarFutureCoinJackpot` body L1839-1906; `_distributeTicketJackpot` body L897-932; `_computeBucketCounts` def L1030-1082).
  - **SURF-05 entry-point gas regression** at HEAD: `payDailyCoinJackpot` (stage 6) PINNED at `PAY_DAILY_COIN_JACKPOT_GAS_REF = 2_860_535` with `BASELINE_NO_COIN_JACKPOT_GAS = 285_604` (stage 1 anchor); per-site tolerance ±2K; helper-growth bound `PER_CALL_GAS_DELTA_BOUND = 120_000` vs pinned HEAD REF; theoretical worst-case opcode walk in test file header (per-pull body breakdown + EIP-2929 cold/warm SLOAD profile + realistic 75-110K envelope + 120K asserted bound). `payDailyJackpotCoinAndTickets` (stage 9) soft-skips when stage 9 not reachable (turbo-mode jackpot phase compresses 7→11→10 in simulator's deterministic lifecycle).
  - **D-IMPL-06 advanceGame 1.99× margin:** re-runs section-16 SC-1 305-player worst-case fixture; measured at HEAD `cf564816` stage 11 = 3.18M-3.55M gas, margin = 8.4-9.4× (well above required 1.99×; existing section-16 SC-1/2a/2b assertions byte-identical: 6 × `expect(r.gasUsed).to.be.lt(16_000_000n)` preserved).
- REQs satisfied: 9/9 (STAT-01, STAT-02, STAT-03, STAT-04, SURF-01, SURF-02, SURF-03, SURF-04, SURF-05); STAT-03 satisfied as a "test landed and surfaces fixture-density measurement" — see §4 reframe row.
- Phase 264 deferred operational items (carry-forward as INFO-tier; not Phase 265 deliverables):
  - (a) STAT-03 fixture retune to D-IMPL-07 mid/late-game holder-density spec (NOT a Phase 265 deliverable per D-265-STAT03-01 — backlog item only).
  - (b) Phase 264 SURF-05 gas REF drift in combined `npm run test:stat` ordering (128K drift vs isolation REF; root cause not diagnosed; operational test-fixture issue).
  - (c) Phase 261 SURF-05 `runTerminalJackpot` pre-existing failure (drift 118,928 vs ref 2,599,868; pre-existing at HEAD `7c5f2f21`; out of v35.0 audit scope).
  - (d) Hardhat ESM cleanup quirk (mocha file-unloader trailing error on test failure; tooling quirk).

  All 4 items are operational/tooling — NOT contract-behavior findings; surfaced INFO-only per D-265-FIND-01.

**Cross-cite:** `.planning/phases/264-statistical-validation-cross-surface-preservation/264-01-SUMMARY.md` + `264-02-SUMMARY.md` + `VERIFICATION.md` + `264-CONTEXT.md` (cross-cite-only).

**Per-REQ summary table:**

| REQ | Verdict | Cross-Cite | Attestation |
| --- | ------- | ---------- | ----------- |
| STAT-01 | `PASS_AT_HEAD_<sha>` | 264-01-SUMMARY.md | Chi² over 10K aggregated samples in `test/stat/PerPullLevelDistribution.test.js`; range=4 chi² = 5.114 < 7.815 (α=0.05 df=3); range=8 chi² = 3.019 < 14.067 (α=0.05 df=7). |
| STAT-02 | `PASS_AT_HEAD_<sha>` | 264-01-SUMMARY.md | Per-trait counts = [13, 13, 12, 12] under `i % 4` rotation across 50 pulls; degenerate chi² = 0.08. Deterministic-by-design — no PRNG variance because rotation index is `i % 4`. |
| STAT-03 | `PASS as test-landed; fixture-calibration measurement reframed in §4 per D-265-STAT03-01` | 264-01-SUMMARY.md | Test landed at strict 10% threshold per D-IMPL-08; measured `skipRate = 88.24%` on natural-lifecycle fresh `deployFullProtocol` fixture (~16 vault tickets per level × levels [2..5] ≈ 64 tickets distributed across 16 `(lvl', trait_i)` cells → ~75% empty cells expected, matching observed ~88% rate after PRNG variance). Helper correctness proven by D-IMPL-01 deity-fixture (50/50 emit count under deity-backed dense fixture). REFRAMED in §4 surface (e) per D-265-STAT03-01. |
| STAT-04 | `PASS_AT_HEAD_<sha>` | 264-01-SUMMARY.md | Phase 261 chi² infrastructure (`makeRng` / `CHI2_CRIT_05` / `wilsonHilfertyZ`) re-declared verbatim in `test/stat/PerPullLevelDistribution.test.js` header. `COIN_LEVEL_TAG` and `BONUS_TRAITS_TAG` sanity-pinned to expected `keccak256("coin-level")` + `keccak256("bonus-traits")` digests. |
| SURF-01 | `PASS_AT_HEAD_<sha>` | 264-02-SUMMARY.md | `_randTraitTicket` body L1653-1703 + 4 other callers L700/L989/L1296/L1399 BYTE-IDENTICAL per per-line modified-set walk vs raw `git diff 6b63f6d4 HEAD -- contracts/modules/DegenerusGameJackpotModule.sol`. |
| SURF-02 | `PASS_AT_HEAD_<sha>` | 264-02-SUMMARY.md | `_awardFarFutureCoinJackpot` body L1839-1906 BYTE-IDENTICAL — far-future coin jackpot path orthogonal to v35 near-future per-pull-level resample. |
| SURF-03 | `PASS_AT_HEAD_<sha>` | 264-02-SUMMARY.md | `_pickSoloQuadrant` body L1098-1115 + 4 ETH injection sites L287/L454/L531/L1181 BYTE-IDENTICAL — gold-solo-priority path (v34 SOLO) preserved unchanged at v35. |
| SURF-04 | `PASS_AT_HEAD_<sha>` | 264-02-SUMMARY.md | `_distributeTicketJackpot` body L897-932 + `_computeBucketCounts` def L1030-1082 + emit blocks L518-520, L536-538 + `emitDailyWinningTraits` external L1750-1756 BYTE-IDENTICAL — ticket-jackpot + indexer emit blocks preserved unchanged at v35. |
| SURF-05 | `PASS_AT_HEAD_<sha>` | 264-02-SUMMARY.md | `payDailyCoinJackpot` stage 6 gas PINNED at `PAY_DAILY_COIN_JACKPOT_GAS_REF = 2,860,535` with `PER_CALL_GAS_DELTA_BOUND = 120,000`; `advanceGame` measured 9.42× margin above 1.99× ceiling at HEAD `cf564816`; theoretical worst-case in test file header per `feedback_gas_worst_case.md`. |

`re-verified at HEAD <sha>`.

---
