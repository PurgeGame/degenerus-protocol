# Requirements: Degenerus Protocol — v68.0 Pre-C4A Coverage Completion + AI-Verifiable RNG-Freeze Proof

**Defined:** 2026-06-17
**Core Value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins.
**Milestone goal:** Close the remaining *machine-driven* detection gaps that six manual cross-model audits (v62–v67) structurally cannot — measured test-suite kill-rate, deep stateful invariants, a self-verifying RNG-freeze-at-commitment proof, durable CI enforcement of the strong guarantees, and current-only comments — and ship that evidence so a paid Code4rena audit finds nothing.
**Method:** BUILD → MEASURE → INDEPENDENTLY VERIFY. The detection principles here are deliberately *different* from manual review: mutation measures whether the suite would actually fail on a regression; deep invariant fuzzing explores compositions humans can't enumerate; the RNG-freeze proof is generated then adversarially re-verified against source by an independent agent; cross-model council is reserved for the one closure pass on the exact submission commit.
**Subject:** HEAD `d0af2984`, `contracts/` tree `4970ba5b` (byte-frozen — unchanged since the v67 MIDRNG-02 re-freeze), held byte-stable for all detection work.
**Posture:** No contract LOGIC change. The ONLY `contracts/*.sol` edit in this milestone is the comment-only trim (COMMENTS), which is logic-inert and still routes through the standard contract-commit approval gate. All test / tooling / proof / CI additions commit autonomously.
**Assumptions:** Honest admin / governance (a legitimate coordinator rotation must not brick or corrupt; admin malice out of scope). Pre-launch, no live funds.

## v1 Requirements

Requirements for this milestone. Each maps to exactly one roadmap phase.

### FOUND — Foundation: Subject Freeze, Green Baseline & Tooling Starting State

- [ ] **FOUND-01**: The subject is byte-frozen at current HEAD, with the commit hash (`d0af2984`) and `contracts/`-tree hash (`4970ba5b`) recorded as the v68 freeze anchor; `git diff` against the anchor stays empty for all non-comment work.
- [ ] **FOUND-02**: A green baseline is captured and documented (forge full-suite pass/skip counts + hardhat parity) AND the starting state of every detection asset this milestone extends is inventoried — the existing invariant suites, the Halmos suite, the mutation harness + its `.DONE` checkpoints, and what CI gates run today — so each track's delta is measurable.

### MUT — Finish the Mutation Tail (measured kill-rate on the finding-hosting modules)

- [ ] **MUT-01**: The mutation harness is repaired so a campaign runs to completion — non-compiling slither-mutate mutants (the invalid-RR class that aborted the v64 `BurnieCoinflip` run, e.g. `for(...; revert(); )`) are pre-filtered and treated as skipped rather than aborting the run, on top of the existing SIGPIPE gate; the `.DONE` checkpoint / resume model is validated on a small target.
- [ ] **MUT-02**: The three never-scored RNG/payout modules — `Coinflip`, `DegenerusGameLootboxModule`, `DegenerusGameDecimatorModule` (the modules that hosted every prior real finding) — are mutation-scored to completion against the comprehensive oracle, with a per-module kill-rate recorded in a campaign report.
- [ ] **MUT-03**: Every surviving mutant is triaged oracle-hole vs. contract-robustness; each oracle-hole is closed with a regression that fails-without / passes-with the relevant assertion, and no survivor is left undispositioned (a documented "equivalent mutant" is a valid disposition).
- [ ] **MUT-04**: The v67 INFO-02 residual is pinned — a regression asserts the slot-46 `yieldAccumulator` overwrite stays safe by `creditFlip` being callback-free (fails if `creditFlip` ever gains a callback / `recordAmount != 0`), converting a "safe-by-structure on the frozen tree" note into an enforced invariant.

### INV — Deep Stateful Invariants + Close the `fail_on_revert` Blind Spot

- [ ] **INV-01**: The `fail_on_revert = false` blind spot is closed — every invariant handler ghost-asserts its expected success/failure so a "should-not-have-reverted" sequence becomes observable instead of being silently discarded (selectively enabling `fail_on_revert` where the handler set is clean is an acceptable form).
- [ ] **INV-02**: The full invariant net is run at a deep budget (a deep profile, multi-hour, materially beyond the CI default of runs=256/depth=128) with every property green; the budget used and any newly added properties are recorded.
- [ ] **INV-03**: Any property gap the deep run exposes — a reachable state the shallow CI never assembled, or a missing conservation/liveness property — is captured as a new invariant or a targeted regression.

### RNGPROOF — AI-Verifiable RNG-Freeze-at-Commitment Proof

- [ ] **RNGPROOF-01**: Every VRF/RNG consumer in the current net (the v66-derived corpus, re-confirmed against HEAD) is enumerated into a machine-readable freeze ledger; each entry states the freeze invariant formally — *the word/seed the consumer uses is fully determined at a commitment point `P`, and no actor-controllable input between `P` and the consumption point `C` can change which word is used or how the outcome is derived*.
- [ ] **RNGPROOF-02**: Each ledger entry carries source-anchored evidence an independent reader can re-check — commitment-point `file:line`, consumption-point `file:line`, the data-flow path between them, the enumerated input set with a frozen-at-`P` justification per input, and a verification recipe (grep/AST anchors + the exact predicate). The format is machine-parseable (structured markdown or JSON) so an AI can verify it against source without prose interpretation.
- [ ] **RNGPROOF-03**: Where a freeze is arithmetic or structural rather than self-evident, the ledger entry references a backing Halmos check or targeted test that discharges it.
- [ ] **RNGPROOF-04**: An independent agent adversarially re-verifies every ledger claim against frozen source — explicitly trying to find one consumer whose consumed word is NOT frozen-at-commitment — and the artifact (`audit/RNG-FREEZE-PROOF-v68.0.md` + machine-readable index) is published only after that pass returns zero unrefuted gaps.

### LAYOUT — Storage-Layout Snapshot CI Oracle (MECH-02 completion)

- [ ] **LAYOUT-01**: A golden `forge inspect <C> storageLayout` JSON snapshot is captured for `DegenerusGame` and every storage-bearing contract (the canonical `DegenerusGameStorage` layout inherited under delegatecall + the standalone state/token contracts) and committed as the authoritative layout fixture.
- [ ] **LAYOUT-02**: An oracle diffs live `forge inspect` layout vs. the golden and fails on any unexpected slot move (the whole-protocol blast-radius surface under 155 delegatecall sites); the ~30 slot-hardcoded test harnesses are migrated to read authoritative slots from `forge inspect` (or pinned against the golden) so a layout change can no longer pass silently.

### CI — Durable Enforcement of the Strong Guarantees

- [ ] **CI-01**: A scheduled CI job runs the strong-but-slow guarantees that per-PR CI skips — the Halmos proof suite, the deep-profile invariant sweep, and the mutation resume — and reports a real failure (not a silent skip) when any regresses, so a pre-C4A edit that breaks a proven invariant cannot ship green.
- [ ] **CI-02**: The fast gates — the LAYOUT layout-diff oracle and the EIP-170 deployed-bytecode ceiling check (binding at `DegenerusGameMintModule`'s ~1.4 KB headroom) — run in per-PR CI so a slot move or a near-ceiling overflow can't merge; the CI matrix (per-PR vs scheduled) is documented.

### COUNCIL — Close the Cross-Model Availability Gap on the Frozen Commit

- [ ] **COUNCIL-01**: The deferred Codex second-source for phase 423 (VRFSWAP rotation-liveness leads — grace-bailout reset chain, wasted-recovery, rotation-aborts-on-revert) is run and its dispositions recorded, closing the v67 coverage caveat.
- [ ] **COUNCIL-02**: One fresh cross-model council pass runs on the exact byte-frozen submission commit — explicitly sweeping the v67 in-milestone fixes themselves (MIDRNG-02 `73eb242a`, DELEGATE-FIND-01 `095a7ac9`, BRICK-FIND-01 gas `2aed5d28`) for any regression they introduced; every candidate is adversarially verified before it is recorded.

### COMMENTS — Comment Trim to Current-Only, Audit/Production-Relevant (contract-commit gate)

- [ ] **COMMENTS-01**: Every production `contracts/*.sol` comment carrying procedural/history debt (milestone/version refs like `v51.0`, plan/req/finding IDs like `D-348`/`SPEC-04`/`REVERT-02`, build-phase numbers, history narration like "previously/moved from/no longer", spec-line `.md` cites, audit-process tags like "re-attested") is trimmed — the procedural token stripped, the descriptive "what the code guarantees now" sentence kept; load-bearing invariant prose is rephrased into self-contained statements, never deleted wholesale.
- [ ] **COMMENTS-02**: The trim is a single batched, logic-inert diff (zero logic change, verified by a clean compile + a name-only/AST-level no-op check), with the two dense files (`sDGNRS.sol`, `GameAfkingModule.sol` ≈ 41% of the debt) done by hand and the long tail batched; it is presented for ONE USER contract-commit approval (the only approval gate in the milestone).

### TERMINAL — Evidence Pack + Closure

- [ ] **TERMINAL-01**: A canonical evidence pack `audit/COVERAGE-v68.0.md` (+ HTML report) records the measured mutation kill-rates, the deep-invariant budget/results, the RNG-freeze proof index + re-verification verdict, the LAYOUT + CI gates, and the comment-trim diff summary; the closure signal `MILESTONE_V68_AT_HEAD_<sha>` is recorded and the subject is confirmed logic-byte-frozen (only the comment-only trim touched `contracts/*.sol`).

## v2 Requirements

Deferred — not in this milestone's roadmap.

- **Optional `:1843`/`:1850` `lootboxRngWordByIndex[index] == 0` fulfill-write guard** + **423 rotation-timer hardening** (gate liveness off a non-rotation-resettable clock). USER-deferred LOW defense-in-depth under the honest-admin assumption (recoverable, not a brick); contract changes, not in this coverage milestone.
- **Echidna / Medusa coverage-guided fuzzing** — largely redundant with the existing Foundry invariant net (same properties); revisit only if the deep invariant sweep surfaces a near-miss that justifies corpus-guided digging.
- **Certora Prover unbounded formal verification** — strongest guarantee but worst ROI here (paid, hostile to via_ir + packed storage); reserved for a future permanent-verification posture, not pre-C4A bug extermination.

## Out of Scope

| Item | Reason |
|------|--------|
| Any contract LOGIC change | Coverage/proof/hygiene milestone on a logic-frozen subject; the only `.sol` edit is the comment-only trim |
| `capBucketCounts` exactness | USER ruling 2026-06-17: by-design fine — there is never more than 1 solo bucket, so the cap imprecision cannot bind. CLOSED; no fix, no formal proof |
| SEED-001 century quest-streak shield | Already shipped (USER) — not a pending item |
| New feature work / gas optimization | Out; security is the hard floor and this milestone adds no logic |
| Admin / governance malice | Honest-admin assumption stands; key-compromise out of scope |
| Full re-run of the manual audit hunt | Saturated across v62–v67 (0 CAT/0 HIGH); only the single COUNCIL closure pass on the frozen commit is in scope |
| Pushing any contract change without review | Standing rule — manual diff review + approval before any `contracts/*.sol` commit/push |

## Traceability

Each requirement maps to exactly one phase. v68.0 phases continue 425 → 426. Not reset.

| Requirement | Phase | Status |
|-------------|-------|--------|
| FOUND-01 | 426 FOUND | Pending |
| FOUND-02 | 426 FOUND | Pending |
| MUT-01 | 427 MUT | Pending |
| MUT-02 | 427 MUT | Pending |
| MUT-03 | 427 MUT | Pending |
| MUT-04 | 427 MUT | Pending |
| INV-01 | 428 INV | Pending |
| INV-02 | 428 INV | Pending |
| INV-03 | 428 INV | Pending |
| RNGPROOF-01 | 429 RNGPROOF | Pending |
| RNGPROOF-02 | 429 RNGPROOF | Pending |
| RNGPROOF-03 | 429 RNGPROOF | Pending |
| RNGPROOF-04 | 429 RNGPROOF | Pending |
| LAYOUT-01 | 430 LAYOUT | Pending |
| LAYOUT-02 | 430 LAYOUT | Pending |
| CI-01 | 431 CI | Pending |
| CI-02 | 431 CI | Pending |
| COUNCIL-01 | 432 COUNCIL | Pending |
| COUNCIL-02 | 432 COUNCIL | Pending |
| COMMENTS-01 | 433 COMMENTS | Pending |
| COMMENTS-02 | 433 COMMENTS | Pending |
| TERMINAL-01 | 434 TERMINAL | Pending |

**Coverage:**
- v1 requirements: 22 total
- Mapped to phases: 22 ✓ (1 requirement → exactly 1 phase; no orphans, no duplicates)
- Unmapped: 0 ✓
- Phases: 9 (426 FOUND · 427 MUT · 428 INV · 429 RNGPROOF · 430 LAYOUT · 431 CI · 432 COUNCIL · 433 COMMENTS · 434 TERMINAL)

---
*Requirements defined: 2026-06-17 — grounded in the `remaining-coverage-survey` workflow (mutation tail / deep-invariant / RNG-freeze-proof / layout-oracle / CI-durability / comment-debt), the carried v67 items, and a HEAD-confirmed read of the existing invariant + Halmos + mutation tooling.*
