---
phase: 280-delta-audit-findings-consolidation-terminal
plan: 01
milestone: v40.0
milestone_name: Unified Whole-Ticket Award Protocol + Whole-BURNIE Floor
audit_baseline: 6a7455d1
audit_baseline_signal: MILESTONE_V39_AT_HEAD_6a7455d1
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
audit_subject_head: "<sha>"
closure_signal: MILESTONE_V40_AT_HEAD_<sha>
deliverable: audit/FINDINGS-v40.0.md
requirements: [LBX-AR-01, LBX-AR-02, LBX-AR-03, LBX-AR-04, LBX-AR-05, LBX-AR-06,
               TST-LBX-AR-01, TST-LBX-AR-02, TST-LBX-AR-03, TST-LBX-AR-04, TST-LBX-AR-05, TST-LBX-AR-06,
               JPT-BR-01, JPT-BR-02, JPT-BR-03, JPT-BR-04, JPT-BR-05, JPT-BR-06,
               TST-JPT-BR-01, TST-JPT-BR-02, TST-JPT-BR-03, TST-JPT-BR-04,
               EVT-UNI-01, EVT-UNI-02, EVT-UNI-03, EVT-UNI-04, EVT-UNI-05, EVT-UNI-06, EVT-UNI-07, EVT-UNI-08,
               TST-EVT-UNI-01, TST-EVT-UNI-02, TST-EVT-UNI-03, TST-EVT-UNI-04, TST-EVT-UNI-05, TST-EVT-UNI-06,
               JPT-CLEAN-01, JPT-CLEAN-02, JPT-CLEAN-03, JPT-CLEAN-04, JPT-CLEAN-05, JPT-CLEAN-06,
               TST-CLEAN-01, TST-CLEAN-02, TST-CLEAN-03, TST-CROSS-01,
               BUR-01, BUR-02, BUR-03, BUR-04, BUR-05,
               TST-BUR-01, TST-BUR-02, TST-BUR-03, TST-BUR-04,
               AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06,
               REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
phase_count: 6
phase_ids: [275, 276, 277, 278, 279, 280]
phase_shape: multi-phase
requirements_total: 65
adversarial_pass_skills: [contract-auditor, zero-day-hunter, economic-analyst]
adversarial_pass_pattern: PARALLEL_SINGLE_MESSAGE
out_of_scope_skills: [degen-skeptic]
supersedes: none
status: "IN-PROGRESS"
read_only: false
generated_at: 2026-05-14T00:00:00Z
---

# v40.0 Findings — Unified Whole-Ticket Award Protocol + Whole-BURNIE Floor (Terminal)

**Audit Baseline.** The audit baseline is v39.0 audit-subject HEAD `6a7455d1` (closure signal `MILESTONE_V39_AT_HEAD_6a7455d1` carry-forward from `audit/FINDINGS-v39.0.md` §9c). v40.0 audit-subject HEAD `MILESTONE_V40_AT_HEAD_<sha>` is resolved at the Phase 280 terminal closure-flip task per D-40N-CLOSURE-01/02. The v40.0 audit subject is the 12-commit delta `git log 6a7455d1..HEAD -- contracts/ test/`: Phase 275 (`b6ed8fce` + `bb1b1abd`) auto-resolve LootboxModule Bernoulli; Phase 276 (`c473867e` + `1568fd5c`) JackpotModule `_jackpotTicketRoll` BAF Bernoulli; Phase 277 (`02fb7085` + `6fbee850` + `f7a6fccd`) event surface unification + sentinel retirement, where `f7a6fccd` is the CR-01 cold-bust WWXRP-consolation gap-closure remediation; Phase 278 (`8a81a87c` + `c3baf694` + `a91dac85`) JackpotModule cleanup + ENT-05 keccak refactor + wrapper retirement, where `a91dac85` is a stale `[02a]` MintModule byte-identity test-gate supersede touch; Phase 279 (`8ef4a010` + `37207743`) whole-BURNIE floor. There are no included-since-baseline maintenance commits between the v39.0 closure HEAD and the v40.0 open — all 12 commits are v40.0 phase work.

**Scope.** Single canonical milestone-closure deliverable for v40.0 per D-40N-FILES-01 carry of D-274-FILES-01 / D-272-FILES-01 / D-271-FILES-01 (9-section shape locked). v40.0 = **6-phase multi-phase milestone shape** per `.planning/REQUIREMENTS.md` (v33/v34/v35/v37 precedent, NOT the v36/v38/v39 single-phase pattern) — Phase 275 (LBX-AR, auto-resolve LootboxModule Bernoulli), Phase 276 (JPT-BR, JackpotModule:2216 BAF Bernoulli), Phase 277 (EVT-UNI, event surface unification + sentinel retirement), Phase 278 (JPT-CLEAN, JackpotModule cleanup + ENT-05 keccak refactor + wrapper retirement), Phase 279 (BUR, whole-BURNIE floor), Phase 280 (terminal delta audit). Each surface phase ran a USER-APPROVED batched contract commit + USER-APPROVED batched test commit per `feedback_no_contract_commits.md` + `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md`. Phase 280 is the SOLE terminal phase and is SOURCE-TREE FROZEN — zero `contracts/` and zero `test/` mutations; the only Phase 280 file changes are `audit/FINDINGS-v40.0.md` (this deliverable), `.planning/phases/280-.../280-01-ADVERSARIAL-LOG.md`, `KNOWN-ISSUES.md` (one entry removed per D-280-EXC04-01), and the 5 closure-flip docs (`ROADMAP.md` / `STATE.md` / `MILESTONES.md` / `PROJECT.md` / `REQUIREMENTS.md`) — all agent-committable.

**Write policy.** READ-only after the terminal Phase 280 closure-flip task per D-40N-APPROVAL-01 + D-274-APPROVAL-01 carry-forward chain. KNOWN-ISSUES.md is MODIFIED at v40 close per D-280-EXC04-01 — the line-31 EXC-04 "EntropyLib XOR-shift PRNG for BAF jackpot ticket rolls" entry is REMOVED OUTRIGHT because Phase 278 commit `8a81a87c` deleted `EntropyLib.entropyStep` entirely and swapped `_jackpotTicketRoll` to `EntropyLib.hash2` keccak self-mix — there is no xorshift PRNG and no xorshift consumer anywhere in `contracts/` at v40 HEAD. The Section 6b closure verdict for KNOWN-ISSUES.md is `KNOWN_ISSUES_MODIFIED`. Per `feedback_never_preapprove_contracts.md`, the agent does NOT pre-approve any contract change — every Phase 275-279 contract + test commit landed under a USER-APPROVED batched gate (see Section 9.NN commit-readiness register). Per `feedback_manual_review_before_push.md`, the user reviews this deliverable's full diff before any push; the READ-only flip on `audit/FINDINGS-v40.0.md` (chmod 444 + frontmatter `status: FINAL — READ-ONLY` + `read_only: true`) is the terminal action of the closure-flip task. This phase exercises `feedback_no_history_in_comments.md` (prose describes what IS at v40 close, not what changed), `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` (mandatory methodology for the Section 4 RNG surfaces (a)-(e)), and `feedback_gas_worst_case.md` (gas claims rest on theoretical-worst-case derivation).

---

## 2. Executive Summary

### Closure Verdict Summary

- **AUDIT-01:** Section 3.A delta-surface table covers every changed declaration across all 12 v40.0 commits `6a7455d1` to v40 HEAD with hunk-level evidence + `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, DOCS_ONLY}` classification per row. Five phase row groups (Phase 275 LBX-AR, Phase 276 JPT-BR, Phase 277 EVT-UNI, Phase 278 JPT-CLEAN, Phase 279 BUR) plus a Section 3.A summary line tallying row count + per-verdict distribution. The 2 remediation commits each carry a dedicated row: `f7a6fccd` MODIFIED_LOGIC (cold-bust WWXRP-consolation gap-closure), `a91dac85` DOCS_ONLY (stale `[02a]` MintModule byte-identity test-gate supersede).
- **AUDIT-02:** Section 3.A row coverage proportional to surface change for the 5 v40.0 phase contract+test commit pairs; each commit SHA resolves to its own Section 3.A row(s), grep-reproducible.
- **AUDIT-03:** Section 4 11-surface adversarial sweep (a)..(k) with a SAFE-bucket verdict per surface; RNG surfaces (a)-(e) carry a backward-trace attestation + a commitment-window attestation per `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md`; default zero F-40-NN finding blocks per D-40N-KI-01.
- **AUDIT-04:** 3-skill PARALLEL adversarial pass on the finished Section 4 draft per D-40N-ADVERSARIAL-01 — `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` spawn (PARALLEL via single message); `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. Adversarial-log at `.planning/phases/280-delta-audit-findings-consolidation-terminal/280-01-ADVERSARIAL-LOG.md`; zero residual FINDING_CANDIDATE.
- **AUDIT-05:** Section 6 KI walkthrough EXC-01..04 RE_VERIFIED at v40 HEAD; EXC-01/02/03 RE_VERIFIED-NEGATIVE-scope; EXC-04 recorded as STRUCTURALLY ELIMINATED at v40.0 (Phase 278 `8a81a87c` — `EntropyLib.entropyStep` deleted, `_jackpotTicketRoll` swapped to `EntropyLib.hash2` keccak self-mix) — KNOWN-ISSUES.md line-31 entry removed per D-280-EXC04-01; Section 6b closure verdict `KNOWN_ISSUES_MODIFIED`.
- **AUDIT-06:** Section 9c emits closure signal `MILESTONE_V40_AT_HEAD_<sha>` verbatim in 5 FINDINGS locations per D-40N-CLOSURE-01 (resolved at the terminal closure-flip task); plus 3 cross-document propagation locations. KNOWN-ISSUES.md MODIFIED per D-280-EXC04-01.
- **REG-01:** Section 5a — v39.0 closure signal `MILESTONE_V39_AT_HEAD_6a7455d1` re-verified NON-WIDENING at v40 HEAD for v39-touched surfaces NOT in v40 scope. The bits[152..167] manual-path slice (now shared with the auto-resolve branch in v40) is verified non-widening via per-resolution seed-uniqueness; `LootboxModule:1080` lootbox-spin BURNIE site is newly v40-scoped per BUR-01 and EXPLICITLY EXCLUDED from the non-widening proof (in-scope mutation). Degenerette + BURNIE coinflip + mint-boost ticket queue + mint-boost flip-credit `MintModule:1199` + advance bounty + affiliate DGNRS deity bonus + quest rewards byte-identical.
- **REG-02:** Section 5b — v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555` re-verified NON-WIDENING at v40 HEAD; TraitUtils + `_pickSoloQuadrant` + JackpotBucketLib byte-identical.
- **REG-03:** Section 5c / Section 6b 4-row KI envelope re-verifications — EXC-01/02/03 RE_VERIFIED-NEGATIVE-scope; EXC-04 STRUCTURALLY ELIMINATED at v40.0 (records the elimination, not a non-widening re-verification).
- **REG-04:** Section 5d per-finding PASS/SUPERSEDED row table walking `audit/FINDINGS-v25.0.md` to `audit/FINDINGS-v39.0.md` for findings referencing the v40-touched function/surface set.
- **Combined milestone closure:** `MILESTONE_V40_AT_HEAD_<sha>`.

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-40-NN: 0

Default expected per D-40N-KI-01 carry. The Bernoulli round-up extended to the auto-resolve LootboxModule branch (Phase 275) and the JackpotModule `_jackpotTicketRoll` path (Phase 276) is EV-neutral by construction: `E[whole_post] == scaledPre / TICKET_SCALE` exactly, identical to the v39.0 manual-path identity proven in `audit/FINDINGS-v39.0.md` Section 3.C. The bit-slice `[152..167]` reused on the auto-resolve branch is the same 16-bit slice the manual path consumes — but each `_resolveLootboxCommon` invocation derives a per-resolution `seed = keccak256(abi.encode(rngWord, player, day, amount))`, so the manual and auto-resolve consumers never share a seed value (each open/resolution is a distinct keccak preimage). The jackpot bit-slice `[200..215]` is 180+ bits separated from the existing `bits[0..12]` path/level consumers and reads a full-diffusion keccak word after the Phase 278 `EntropyLib.hash2(entropy, entropy)` self-mix swap. Storage layout is byte-identical at v40 HEAD vs `6a7455d1` for all modified modules (zero new storage slots, zero new state-declaration mutations). The event surface unification breaks the topic-hashes of `LootBoxOpened` / `BurnieLootOpen` / `JackpotTicketWin` — accepted per D-40N-EVT-BREAK-01 pre-launch (no live indexer; indexer rebuild expected regardless). The whole-BURNIE floor at the 3 RNG-amount sites is a pure-amount integer-division transformation upstream of existing `coinflip.creditFlip` / `creditFlipBatch` emit sites — sub-1-BURNIE residues evaporate per D-40N-BUR-DUST-01 (user-accepted). Severity ceiling for any v40-emitted F-40-NN: LOW (no value extraction beyond the existing prize space; EV invariant by construction; the variance increase is bounded and EV-neutral). Most likely severity for any inline-draft finding-candidate: INFO. Severity counts reconcile to the Section 4 F-40-NN block tally line by line.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v25-v39 player-reachability x value-extraction x determinism-break frame, carried forward as D-08 from v25 onward (D-40N-SEV-01 carry of D-274-SEV-01 / D-272-SEV-01).

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

Severity calibration for any F-40-NN that may surface during Section 4 adversarial-pass disposition: LOW ceiling (the Bernoulli collapse is EV-neutral by construction per the `E[whole_post] == scaledPre / TICKET_SCALE` exact identity; the player cannot extract value from the variance increase because expected value is invariant; storage layout byte-identical preserves a one-line revert path; the whole-BURNIE floor only ever rounds DOWN, so it cannot over-issue protocol value). INFO likely for documentation-only items. Per D-40N-KI-01 default path, zero F-40-NN blocks emit; severity-at-HEAD = N/A.

### D-09 KI Gating Rubric Reference

The Section 6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident).
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism.
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state).

ANY false implies a Non-Promotion Ledger entry with the failing predicate identified. Default outcome at this milestone: zero F-40-NN finding blocks emit (D-40N-KI-01 carry default path) implies zero KI promotion candidates from new findings. KNOWN-ISSUES.md is MODIFIED at v40 close — but by a REMOVAL, not a promotion: the EXC-04 EntropyLib XOR-shift entry described a mechanism that no longer exists at v40 HEAD (Phase 278 `8a81a87c` deleted `EntropyLib.entropyStep` and `_jackpotTicketRoll` now reads `EntropyLib.hash2` keccak output). A structurally-eliminated mechanism fails the "Sticky" predicate trivially — there is nothing left to be sticky about — and a warden pre-disclosure doc reserved for *ongoing* protocol behavior should not carry an entry for code that is gone. See Section 6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

D-40N-FCITE-01 carry of D-274-FCITE-01 / D-272-FCITE-01 / D-271-FCITE-01 + D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 280 to any post-v40.0 milestone phases. Verified at Section 8 Forward-Cite Closure block. v40.0 = 6-phase multi-phase milestone (Phases 275-279 surface phases + Phase 280 terminal). Deferred items (LBX-02 fixture-coverage gap; superseded-baseline SURF `it.skip` cleanup) are cited via locked-decision IDs (`D-40N-LBX02-OUT-01`) without naming specific future-milestone numbers. The "Deferred to Future Milestones" subsection in PROJECT.md is the single-source-of-truth lookup for future-pickup; the Section 9 "Deferred to Future Milestones" subsection in this deliverable attests the carry-forward bundle without forward-citing in-flight work.

### Attestation Anchor

See Section 9 Milestone Closure Attestation for the D-253-15 step 9 attestation block triggering v40.0 milestone closure via signal `MILESTONE_V40_AT_HEAD_<sha>` (resolved at the Phase 280 terminal closure-flip task across 5 verbatim FINDINGS locations + 3 cross-document propagation locations per D-40N-CLOSURE-01).

---

## 3. Per-Phase Sections

v40.0 is a 6-phase multi-phase milestone. Sections 3a-3f below give one "What IS at v40.0 close" enumeration per phase, consumed from the per-phase SUMMARY / VERIFICATION / STORAGE-LAYOUT-DIFF / GAS-WORSTCASE artifacts — surface detail is not re-derived here. Section 3.A is the delta-surface table; Section 3.B is the zero-new-state attestation; Section 3.C is the conservation re-proof.

### 3a. Phase 275 — Auto-Resolve LootboxModule Bernoulli (LBX-AR)

**Source-tree changes since baseline:**
- USER-APPROVED Wave 1 contract commit `b6ed8fce` — `feat(275): auto-resolve lootbox Bernoulli whole-ticket [LBX-AR-01..06]`. One file: `contracts/modules/DegenerusGameLootboxModule.sol` (+29/-32 LOC). Storage layout byte-identical vs `6a7455d1` (83/83 storage entries, stripped diff empty per `275-A-STORAGE-LAYOUT-DIFF.md`). Bytecode -548 bytes deployed (19,191 to 18,643).
- USER-APPROVED Wave 2 test commit `bb1b1abd` — `test(275): auto-resolve lootbox whole-ticket + silent cold-bust + seed-uniqueness regression + mint-boost regression [TST-LBX-AR-01..06]`. 10 files (+1,236/-104 LOC): 6 new test files + 3 migrated v39-era tests + `package.json` `test:stat` wiring; 49 new `it()` blocks, all passing.

**What IS at v40.0 close (Phase 275 delta):**
- **LBX-AR-01/02** — The Bernoulli predicate `(uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)` is hoisted to shared function scope inside `_resolveLootboxCommon`. The auto-resolve branch (the `else` arm of the v39 `index != type(uint48).max` gate at Phase 275 close) calls `_queueTickets(player, targetLevel, whole, false)` — `_queueTicketsScaled` no longer appears in `DegenerusGameLootboxModule.sol`. EV-neutrality identity `E[whole_post] = scaledPre / TICKET_SCALE` carries verbatim from `audit/FINDINGS-v39.0.md` Section 4 (a).
- **LBX-AR-03** — Auto-resolve cold-bust is SILENT per D-40N-SILENT-01: `_queueTickets` at `DegenerusGameStorage.sol:568` early-returns on `quantity == 0`, so the `whole == 0` case queues nothing with no consolation mint and no `LootBoxWwxrpReward` emit.
- **LBX-AR-04** — Seed-uniqueness preserved across the 4 upstream auto-resolve callers: per-resolution `seed = keccak256(abi.encode(rngWord, player, day, amount))` derived once at `_resolveLootboxCommon` entry; the `DegenerusGame:1721` redemption-loop evolves `rngWord = keccak256(abi.encode(rngWord))` per 5-ETH chunk so each chunk's seed is distinct.
- **LBX-AR-05/06** — Storage layout byte-identical vs `6a7455d1`; `_rollRemainder` zero-invocation on auto-resolve queues (the `_queueTickets` path skips the rem-byte branch entirely). `_queueTicketsScaled` + `_rollRemainder` + the `rem` byte STAY for the mint-boost path at `DegenerusGameMintModule.sol:1142` per D-40N-MINTBOOST-OUT-01.

### 3b. Phase 276 — JackpotModule:2216 BAF Bernoulli (JPT-BR)

**Source-tree changes since baseline:**
- USER-APPROVED Wave 1 contract commit `c473867e` — `feat(276): jackpot ticket-roll Bernoulli whole-ticket [JPT-BR-01..06]`. One file: `contracts/modules/DegenerusGameJackpotModule.sol` (+36/-10 LOC). Storage layout byte-identical vs `6a7455d1` (83/83 storage entries, astId-normalized diff empty per `276-A-STORAGE-LAYOUT-DIFF.md`). Bytecode -513 bytes deployed.
- USER-APPROVED Wave 2 test commit `1568fd5c` — `test(276): jackpot ticket-roll Bernoulli + silent cold-bust + bit-slice independence + 2-roll uniqueness [TST-JPT-BR-01..04]`. 5 files (+965/-1 LOC): new `contracts/test/JackpotBernoulliTester.sol` external-pure tester + 3 test files + `package.json`; 29 tests, all passing.

**What IS at v40.0 close (Phase 276 delta):**
- **JPT-BR-01/02** — `_jackpotTicketRoll` applies an inline Bernoulli round-up reading `bits[200..215]` of the per-roll `entropy` chain (`scaledTickets` / `whole` / `frac` function-scope locals per D-276-INLINE-01); `whole = (scaledTickets / TICKET_SCALE) + (roundedUp ? 1 : 0)`. The `:2216` call site swaps from `_queueLootboxTickets(winner, targetLevel, quantityScaled, true)` to direct `_queueTickets(winner, targetLevel, whole, true)`.
- **JPT-BR-03** — Per-roll uniqueness: the entropy chain is evolved between the 2-roll pattern at `_awardJackpotTickets` (return-and-rethread), so each ticket-roll's `bits[200..215]` slice is distinct.
- **JPT-BR-04** — Jackpot cold-bust is SILENT per D-40N-SILENT-01: `_queueTickets` early-returns on `whole == 0`; no consolation in `_jackpotTicketRoll`.
- **JPT-BR-05/06** — Net gas-NEGATIVE (-513 bytes deployed bytecode corroborates; analytical approx -170 gas warm-path to approx -2,870/-4,970 gas cold-path). Bit-allocation NatSpec documents the `bits[200..215]` sub-roll and the 180+ bit separation from the `bits[0..12]` path/level consumers.
- **D-276-RNGBYPASS-01 disposition:** the `:2216` `_queueTickets` call passes `rngBypass = true` (NOT `false` as the literal REQUIREMENTS JPT-BR-02 text says — a Phase-275 copy-paste artifact). `_jackpotTicketRoll` runs inside `advanceGame` while `rngLockedFlag == true`; `false` would revert `advanceGame` on every far-future jackpot ticket roll. The prior `_queueLootboxTickets` wrapper already passed `true`; the swap preserves the bypass posture. This is a documented user-accepted override recorded in `276-VERIFICATION.md` — NOT a defect.

### 3c. Phase 277 — Event Surface Unification + Sentinel Retirement (EVT-UNI)

**Source-tree changes since baseline:**
- USER-APPROVED Wave 1 contract commit `02fb7085` — `feat(277): event surface unification + sentinel retirement [EVT-UNI-01..08]`. Three files: `contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/modules/DegenerusGameJackpotModule.sol` + `contracts/interfaces/IDegenerusGameModules.sol`.
- USER-APPROVED Wave 2 test commit `6fbee850` — `test(277): event surface unification test wave [TST-EVT-UNI-01..06]`. 7 paths: new `test/unit/EventSurfaceUnification.test.js` + 5 retargeted precedent test files + `package.json`; 107 passing across the 6 affected files.
- USER-APPROVED remediation commit `f7a6fccd` — `fix(277): pay cold-bust WWXRP consolation on manual paths + event-surface trims`. CR-01 BLOCKER gap-closure: the original Wave 1 re-gated the manual cold-bust consolation on `emitLootboxEvent`, which silently stopped `openBurnieLootBox` (a manual caller that passes `emitLootboxEvent = false` because it emits its own `BurnieLootOpen`) from paying `LOOTBOX_WWXRP_CONSOLATION`. The remediation introduced a dedicated `bool payColdBustConsolation` parameter (position 11 on `_resolveLootboxCommon`) decoupled from `emitLootboxEvent`; manual callers (`openLootBox`, `openBurnieLootBox`) pass `true`, auto-resolve callers pass `false`. The remediation also trimmed the event surface — removed the `bonusBurnie` field from `LootBoxOpened` and deleted the `LootBoxWwxrpReward` event (WWXRP payouts remain observable via the WWXRP ERC-20 `Transfer` event).

**What IS at v40.0 close (Phase 277 delta):**
- **EVT-UNI-01** — The v39.0-additive `LootboxTicketRoll` event is DELETED from both `IDegenerusGameModules.sol` and `DegenerusGameLootboxModule.sol`. Zero `LootboxTicketRoll` references remain anywhere in `contracts/`.
- **EVT-UNI-02/03** — `LootBoxOpened` is restructured: the v39 mislabeled `uint32 indexed index` (which the emit fed `day` into) is replaced by a real `uint48 indexed lootboxIndex` plus a separate non-indexed `uint32 day` field, plus a `bool roundedUp` final field. Per D-277-EVT-WIDE-01 + D-277-NO-PREROLL-01, `amount` / `burnie` stay `uint256` wei and NO `preRollTickets` field is added — `roundedUp` is the only new field; the off-chain `whole = (futureTickets / TICKET_SCALE) + (roundedUp ? 1 : 0)` derivation is arithmetically equivalent. `BurnieLootOpen` gains a single `bool roundedUp` field.
- **EVT-UNI-04** — `JackpotTicketWin` gains a `bool roundedUp` as the final, non-indexed field (the event keeps exactly 3 indexed params); `_jackpotTicketRoll` captures `roundedUp` purely inside the existing Bernoulli predicate and threads it to the emit, mirroring the LootboxModule capture pattern.
- **EVT-UNI-05/06** — The `index != type(uint48).max` behavior-gating sentinel is RETIRED — the dual-branch construct collapses to an unconditional `_queueTickets(player, targetLevel, whole, false)`. Per D-277-AR-SILENT-01 the auto-resolve emission shape resolves to option (b)-equivalent: auto-resolve callers (`resolveLootboxDirect`, `resolveRedemptionLootbox`) pass `index = 0` + `emitLootboxEvent = false` and stay silent on `LootBoxOpened`; auto-resolve ticket awards stay observable via the unified `_queueTickets` to `TicketsQueued`.
- **EVT-UNI-07/08** — Breaking event topic-hashes ACCEPTED per D-40N-EVT-BREAK-01. Measured deployed-bytecode delta at the Wave 1 commit: LootboxModule -527 bytes, JackpotModule +23 bytes (the `roundedUp` capture + 7th emit arg across 3 sites). Two `private` helper functions (`_lootboxBoonBudget`, `_accumulateLootboxRolls`) were extracted from `_resolveLootboxCommon` to resolve a viaIR stack-too-deep arising from the 4th named return — mechanical behavior-preserving refactors, no new entry points. The Phase 277 SECURITY audit attests all 8 declared threats CLOSED against the post-`f7a6fccd` code.

### 3d. Phase 278 — JackpotModule Cleanup + ENT-05 Keccak Refactor + Wrapper Retirement (JPT-CLEAN)

**Source-tree changes since baseline:**
- USER-APPROVED Wave 1 contract commit `8a81a87c` — `feat(278): jackpot cleanup + ENT-05 keccak refactor + wrapper retirement [JPT-CLEAN-01..06]`. Four files: `contracts/modules/DegenerusGameJackpotModule.sol` + `contracts/libraries/EntropyLib.sol` + `contracts/storage/DegenerusGameStorage.sol` + `contracts/modules/DegenerusGameMintModule.sol` (the last a comment-only NatSpec touch). Storage layout byte-identical vs `6a7455d1` (171/171 layout lines, `forge inspect storage-layout` diff empty, sha256 cross-check identical per `278-01-STORAGE-LAYOUT-DIFF.md`). Bytecode -689 bytes deployed.
- USER-APPROVED Wave 2 test commit `c3baf694` — `test(278): ENT-05 keccak invariant + cross-surface mixing + wrapper-removal + whole-ticket event regression [TST-CLEAN-01..03 + TST-CROSS-01]`. 9 files (2 new test files + 6 modified + `package.json`) + 1 `contracts/test` NatSpec-only helper touch.
- USER-APPROVED remediation commit `a91dac85` — `test(278): supersede stale [02a] MintModule byte-identity gate`. A comment-only / test-gate supersede touch — the stale `[02a]` MintModule byte-identity assertion no longer applied after the Phase 278 wave; DOCS_ONLY classification.

**What IS at v40.0 close (Phase 278 delta):**
- **JPT-CLEAN-01/02/03** — All 3 `JackpotTicketWin` emit sites unify onto whole-ticket counts (`ticketCount` / `uint32(units)` / `whole`), each self-consistent with its adjacent `_queueTickets` storage-write argument; the `JackpotTicketWin` event definition (field types, indexed markers) is unchanged — only emitted values shift from `x TICKET_SCALE` scaled to whole.
- **JPT-CLEAN-04** — ENT-05 keccak refactor: `_jackpotTicketRoll` evolves `entropy` via `EntropyLib.hash2(entropy, entropy)` (a full-diffusion keccak self-mix) instead of the deleted xorshift `EntropyLib.entropyStep`. The low-bit path/level consumers (`entropy / 100`, `% 4`, `% 46`) and the `bits[200..215]` Bernoulli slice now read a full-diffusion keccak word. This intentionally CHANGES BAF roll output semantics for a given seed (not byte-equivalent to v39) — Roadmap SC2 permits this; the `JackpotTicketWin` topic-hash is unchanged.
- **JPT-CLEAN-05** — Dead-code retirement: `EntropyLib.entropyStep` is DELETED (the library keeps only `hash2`); the zero-caller `_queueLootboxTickets` wrapper is DELETED from `DegenerusGameStorage.sol`. Sibling helpers `_queueTickets`, `_queueTicketsScaled`, `_queueTicketRange` are untouched.
- **JPT-CLEAN-06** — Storage layout byte-identical vs `6a7455d1` for `DegenerusGameJackpotModule.sol`; bytecode NET-NEGATIVE (-689 bytes — the two function deletions remove more code than the swap adds).
- **TST-CLEAN-01/02/03 + TST-CROSS-01** — Post-keccak-refactor statistical invariant test (N=20,000 chi-square uniformity + 2-roll uniqueness + `bits[200..215]` independence under the keccak word), `_queueLootboxTickets` wrapper-removal regression, whole-ticket `JackpotTicketWin` emit regression, and a cross-surface `ticketsOwedPacked` rem-byte regression proving the 3 RNG-driven surfaces route through `_queueTickets` (whole, no rem write) while `_queueTicketsScaled` remains the sole rem-byte writer.

### 3e. Phase 279 — Whole-BURNIE Floor (BUR)

**Source-tree changes since baseline:**
- USER-APPROVED Wave 1 contract commit `8ef4a010` — `feat(279): whole-BURNIE floor at 3 RNG-amount sites + cursor-rotation dead-var removal [BUR-01..05]`. Two files: `contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/modules/DegenerusGameJackpotModule.sol`. Storage layout byte-identical vs `6a7455d1` for both modules (171/171 layout lines each, `forge inspect storage-layout` diff empty, sha256 cross-check identical per `279-01-STORAGE-LAYOUT-DIFF.md`).
- USER-APPROVED Wave 2 test commit `37207743` — `test(279): whole-BURNIE floor regression + invariant sweep + surface-regression re-cut [TST-BUR-01..04]`. 6 files (4 new test files, 35 new tests + 2 modified — `SurfaceRegression.test.js` SURF_01 re-cut + `package.json`).

**What IS at v40.0 close (Phase 279 delta):**
- **BUR-01** — `_resolveLootboxCommon` floors the post-bonus `burnieAmount` accumulator to a whole-BURNIE multiple via `burnieAmount = (burnieAmount / 1 ether) * 1 ether` before the `if (burnieAmount != 0)` guard; the floored value flows to `coinflip.creditFlip`, the `LootBoxOpened.burnie` event field, and the return tuple. The `burnieAmount` accumulation block was reordered to sit immediately after `_accumulateLootboxRolls` returns — a stack-depth-ceiling fix within D-279-BUR01-SITE-01 placement discretion (`_resolveLootboxCommon` is at the Solidity stack-depth ceiling; the floor statement does not compile at the originally-specified position).
- **BUR-02** — `_awardDailyCoinToTraitWinners` floors `baseAmount` via `((coinBudget / cap) / 1 ether) * 1 ether`; the `extra` / `cursor` declarations, both `++cursor`/wrap blocks, and the `amount += 1` cursor-rotation +1-wei distribution are FULLY DELETED per the A1 floor-per-winner mechanic (D-40N-BUR-FLOOR-01); `randomWord` and both `++i` increments are preserved. When `baseAmount < 1 ether` the full daily near-future BURNIE jackpot budget evaporates that day, accepted per D-40N-BUR-DUST-01.
- **BUR-03** — `_awardFarFutureCoinJackpot` floors `perWinner` via `((farBudget / found) / 1 ether) * 1 ether` before the unchanged `if (perWinner == 0) return` early-bail; when `perWinner < 1 ether` the 25% far-future BURNIE allocation evaporates that day.
- **BUR-04** — Storage layout byte-identical vs `6a7455d1` for both modules; zero new state variables / events / emit sites / modifiers / entry points. The whole-BURNIE floor is a pure-amount transformation upstream of existing emit sites; event-field values reflect post-floor amounts.
- **BUR-05** — Measured Phase-279-only bytecode delta: `DegenerusGameJackpotModule` -26 bytes (NET-NEGATIVE, as expected — the `extra`/`cursor` dead-var removal outweighs the 2 inline floors); `DegenerusGameLootboxModule` +140 bytes; total **+114 bytes NET-POSITIVE**. This deviates from the plan's BUR-05 NET-NEGATIVE expectation and is a documented user-accepted override recorded in `279-VERIFICATION.md`. Root cause: `_resolveLootboxCommon` was already at the Solidity stack-depth ceiling, so adding the BUR-01 floor statement forces the Yul optimizer into a less-compact stack schedule (the +140 is the optimizer's stack-spill workaround, not the cost of the `DIV`/`MUL` arithmetic). The BUR-01 floor is non-negotiable. For context, the cumulative bytecode delta vs the v39 baseline `6a7455d1` (spanning Phases 275-279) is -1,792 bytes. See Section 3.C for the INFO-tier disposition of this deviation.

### 3f. Phase 280 — Delta Audit + Findings Consolidation (Terminal)

**Source-tree changes since baseline:** NONE. Phase 280 is SOURCE-TREE FROZEN — `git diff 6a7455d1..HEAD -- contracts/ test/` is fully accounted for by the 12 Phase 275-279 commits; Phase 280 emits zero `contracts/` and zero `test/` mutations.

**What IS at v40.0 close (Phase 280 delta):**
- `audit/FINDINGS-v40.0.md` — this 9-section terminal milestone-closure deliverable, agent-authored, FINAL READ-only (chmod 444) at the v40.0 closure HEAD.
- `.planning/phases/280-delta-audit-findings-consolidation-terminal/280-01-ADVERSARIAL-LOG.md` — the 3-skill PARALLEL adversarial validation log (`/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; `/degen-skeptic` OUT OF SCOPE).
- `KNOWN-ISSUES.md` — the line-31 EXC-04 "EntropyLib XOR-shift PRNG for BAF jackpot ticket rolls" entry REMOVED per D-280-EXC04-01 (clean deletion; the rationale lives in Section 6 of this deliverable, NOT in KNOWN-ISSUES.md, per `feedback_no_history_in_comments.md`). EXC-01/02/03 entries left untouched.
- `.planning/ROADMAP.md` + `.planning/STATE.md` + `.planning/MILESTONES.md` + `.planning/PROJECT.md` + `.planning/REQUIREMENTS.md` — atomic closure-flip applied at the terminal closure-flip task.

### 3.A AUDIT-01 Delta-Surface Table

Every source-tree change from v39.0 baseline `6a7455d1` to v40.0 HEAD enumerated with hunk-level evidence and `{NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DELETED, DOCS_ONLY}` classification per row. Five phase row groups (Phase 275 LBX-AR, Phase 276 JPT-BR, Phase 277 EVT-UNI, Phase 278 JPT-CLEAN, Phase 279 BUR). The 2 remediation commits each carry a DEDICATED row per the planner disposition: `f7a6fccd` MODIFIED_LOGIC, `a91dac85` DOCS_ONLY. The 12 commit SHAs are `b6ed8fce bb1b1abd c473867e 1568fd5c 02fb7085 6fbee850 f7a6fccd 8a81a87c c3baf694 a91dac85 8ef4a010 37207743` — `git diff --stat 6a7455d1..HEAD -- contracts/` shows 6 `contracts/` source files + 2 `contracts/test/` tester files changed, 378 insertions / 299 deletions.

**Reproduction recipe:**
```
git log --oneline 6a7455d1..HEAD -- contracts/ test/
git diff --stat 6a7455d1..HEAD -- contracts/ test/
git show <sha>   # per-commit hunk inspection
```

#### Row Group 1 — Phase 275 LBX-AR (auto-resolve LootboxModule Bernoulli)

| Source | Path | Line | SHA | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | --- | -------------- | ------------- | --------------- |
| LBX-AR-01 | `DegenerusGameLootboxModule.sol` :: `_resolveLootboxCommon` Bernoulli hoist | shared scope inside `if (futureTickets != 0)` block | `b6ed8fce` | MODIFIED_LOGIC | Bernoulli predicate `(uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)` hoisted to shared scope above the v39 sentinel gate; `whole`/`frac`/`roundedUp` function-scope locals. EV-neutrality `E[whole_post] = scaledPre / TICKET_SCALE` carries from v39 Section 3.C. | SAFE |
| LBX-AR-02 | `_resolveLootboxCommon` auto-resolve queue-helper swap | auto-resolve `else` arm | `b6ed8fce` | MODIFIED_LOGIC | Auto-resolve branch swaps `_queueTicketsScaled(player, targetLevel, futureTickets, false)` to `_queueTickets(player, targetLevel, whole, false)`. `_queueTicketsScaled` no longer appears in the module. | SAFE |
| LBX-AR-03 | Auto-resolve silent cold-bust | (no new code — `_queueTickets` early-return) | `b6ed8fce` | REFACTOR_ONLY | `_queueTickets` at `DegenerusGameStorage.sol:568` early-returns on `quantity == 0`; auto-resolve `whole == 0` queues nothing, no consolation, no event. D-40N-SILENT-01. | SAFE_BY_DESIGN |
| LBX-AR-04 | Seed-uniqueness across 4 upstream callers | `_resolveLootboxCommon` entry | `b6ed8fce` | REFACTOR_ONLY | Per-resolution `seed = keccak256(abi.encode(rngWord, player, day, amount))` derived once at entry; `DegenerusGame:1721` redemption-loop evolves `rngWord` per 5-ETH chunk. | SAFE_BY_DESIGN |
| LBX-AR-05/06 | Storage byte-identity + `_rollRemainder` zero-invocation | (entire file storage layout) | `b6ed8fce` | REFACTOR_ONLY | `275-A-STORAGE-LAYOUT-DIFF.md` PASS — 83/83 entries, stripped diff empty. `_queueTickets` path skips the rem-byte branch; mint-boost retains `_rollRemainder` per D-40N-MINTBOOST-OUT-01. | SAFE_BY_STRUCTURAL_CLOSURE |
| Phase 275 Wave 2 | 6 new test files + 3 migrated + `package.json` | `test/stat/`, `test/edge/`, `test/unit/` | `bb1b1abd` | REFACTOR_ONLY (TEST) | 49 new `it()` blocks (EV-neutrality N=10K + boundaries + silent cold-bust + seed-uniqueness chi2 + rem-byte + mint-boost regression); all passing. | SAFE_BY_STRUCTURAL_CLOSURE |

#### Row Group 2 — Phase 276 JPT-BR (JackpotModule:2216 BAF Bernoulli)

| Source | Path | Line | SHA | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | --- | -------------- | ------------- | --------------- |
| JPT-BR-01 | `DegenerusGameJackpotModule.sol` :: `_jackpotTicketRoll` inline Bernoulli | `:2227-2237` | `c473867e` | MODIFIED_LOGIC | Inline Bernoulli round-up reading `bits[200..215]` of the per-roll `entropy` chain: `scaledTickets`/`whole`/`frac` function-scope locals; `if (frac != 0 && (uint16(entropy >> 200) % uint16(TICKET_SCALE)) < uint16(frac)) { unchecked { whole += 1; } }`. | SAFE |
| JPT-BR-02 | `_jackpotTicketRoll` `:2216` call swap | `:2238` (post-edit) | `c473867e` | MODIFIED_LOGIC | `_queueLootboxTickets(winner, targetLevel, quantityScaled, true)` to `_queueTickets(winner, targetLevel, whole, true)`. `rngBypass = true` per D-276-RNGBYPASS-01 (advanceGame runs the roll while `rngLockedFlag == true`). | SAFE |
| JPT-BR-03 | Per-roll uniqueness via entropy rethread | `_awardJackpotTickets` 2-roll pattern | `c473867e` | REFACTOR_ONLY | The entropy chain is evolved between the 2 rolls; each roll's `bits[200..215]` slice is distinct. | SAFE_BY_DESIGN |
| JPT-BR-04 | Jackpot silent cold-bust | (no new code — `_queueTickets` early-return) | `c473867e` | REFACTOR_ONLY | `_queueTickets` early-returns on `whole == 0`; no consolation in `_jackpotTicketRoll`. D-40N-SILENT-01. | SAFE_BY_DESIGN |
| JPT-BR-05/06 | Bit-allocation NatSpec + storage byte-identity | NatSpec on `_jackpotTicketRoll`/`_awardJackpotTickets` | `c473867e` | REFACTOR_ONLY | `bits[200..215] jackpotTicketRoundUp % 100` sub-roll documented + 180+ bit separation from `bits[0..12]`. `276-A-STORAGE-LAYOUT-DIFF.md` PASS — 83/83 entries, astId-normalized diff empty. Bytecode -513 bytes. | SAFE_BY_STRUCTURAL_CLOSURE |
| Phase 276 Wave 2 | `JackpotBernoulliTester.sol` + 3 test files + `package.json` | `contracts/test/`, `test/stat/`, `test/unit/` | `1568fd5c` | REFACTOR_ONLY (TEST) | New `external pure` tester (slice offset `>> 200`) + EV-neutrality N=10K + silent cold-bust + chi2 independence + 2-roll uniqueness; 29 tests, all passing. | SAFE_BY_STRUCTURAL_CLOSURE |

#### Row Group 3 — Phase 277 EVT-UNI (event surface unification + sentinel retirement)

| Source | Path | Line | SHA | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | --- | -------------- | ------------- | --------------- |
| EVT-UNI-01 | `LootboxTicketRoll` event deletion | `IDegenerusGameModules.sol` + `DegenerusGameLootboxModule.sol` event block | `02fb7085` | DELETED | `event LootboxTicketRoll(...)` removed from interface + contract; zero `LootboxTicketRoll` references remain in `contracts/`. | SAFE_BY_STRUCTURAL_CLOSURE |
| EVT-UNI-02 | `LootBoxOpened` restructure | `DegenerusGameLootboxModule.sol:68-77` | `02fb7085` | MODIFIED_LOGIC | Mislabeled `uint32 indexed index` to real `uint48 indexed lootboxIndex` + separate non-indexed `uint32 day` + new `bool roundedUp` final field. `amount`/`burnie` stay `uint256` wei (D-277-EVT-WIDE-01); no `preRollTickets` (D-277-NO-PREROLL-01). Topic-hash break accepted per D-40N-EVT-BREAK-01. | SAFE |
| EVT-UNI-03 | `BurnieLootOpen` `roundedUp` field | `DegenerusGameLootboxModule.sol:88-96` | `02fb7085` | MODIFIED_LOGIC | Gains single `bool roundedUp`; pre-existing fields unchanged. `_resolveLootboxCommon` return tuple extended to end in `bool roundedUp`. | SAFE |
| EVT-UNI-04 | `JackpotTicketWin` `roundedUp` field | `DegenerusGameJackpotModule.sol:86-95` | `02fb7085` | MODIFIED_LOGIC | Gains `bool roundedUp` as final non-indexed field (3 indexed params preserved); `_jackpotTicketRoll` captures `roundedUp` inside the existing Bernoulli predicate; all 3 emit sites supply the 7th arg. | SAFE |
| EVT-UNI-05 | `index != type(uint48).max` sentinel retirement | `_resolveLootboxCommon` body | `02fb7085` | MODIFIED_LOGIC | Dual-branch sentinel construct collapses to unconditional `_queueTickets(player, targetLevel, whole, false)`. Auto-resolve callers pass `index = 0` + `emitLootboxEvent = false` (1:1 with the prior sentinel split). | SAFE |
| EVT-UNI-06 | Auto-resolve emission shape (D-277-AR-SILENT-01) | `resolveLootboxDirect` / `resolveRedemptionLootbox` | `02fb7085` | MODIFIED_LOGIC | Auto-resolve stays silent on `LootBoxOpened` (option (b)-equivalent); ticket awards observable via `_queueTickets` to `TicketsQueued`. | SAFE_BY_DESIGN |
| EVT-UNI-07/08 | viaIR helper extraction + bytecode delta | `_lootboxBoonBudget`, `_accumulateLootboxRolls` (new `private`) | `02fb7085` | REFACTOR_ONLY | Two `private` helpers extracted to resolve a viaIR stack-too-deep from the 4th named return — mechanical, behavior-preserving, no new entry points. Bytecode: LootboxModule -527, JackpotModule +23. | SAFE_BY_STRUCTURAL_CLOSURE |
| Phase 277 remediation | `_resolveLootboxCommon` `payColdBustConsolation` param + event-surface trim | `DegenerusGameLootboxModule.sol` `:960-981` signature + `:1068` gate | `f7a6fccd` | MODIFIED_LOGIC | CR-01 BLOCKER gap-closure: dedicated `bool payColdBustConsolation` param (position 11) decoupled from `emitLootboxEvent`; manual callers pass `true`, auto-resolve pass `false`. `openBurnieLootBox`'s cold-bust consolation restored. Event-surface trim: `bonusBurnie` field removed from `LootBoxOpened`, `LootBoxWwxrpReward` event deleted (WWXRP payouts observable via ERC-20 `Transfer`). | SAFE |
| Phase 277 Wave 2 | `EventSurfaceUnification.test.js` + 5 retargeted + `package.json` | `test/unit/`, `test/edge/` | `6fbee850` | REFACTOR_ONLY (TEST) | New 6-`describe` test file (topic-hash changes, `LootboxTicketRoll` removal, sentinel retirement, field consistency) + 5 precedent test files retargeted off stale Wave-1 assertions; 107 passing. | SAFE_BY_STRUCTURAL_CLOSURE |

#### Row Group 4 — Phase 278 JPT-CLEAN (cleanup + ENT-05 keccak refactor + wrapper retirement)

| Source | Path | Line | SHA | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | --- | -------------- | ------------- | --------------- |
| JPT-CLEAN-01/02/03 | `JackpotTicketWin` whole-ticket emit unification (3 sites) | `DegenerusGameJackpotModule.sol` 3 emit sites | `8a81a87c` | MODIFIED_LOGIC | All 3 `JackpotTicketWin` emits unify onto whole-ticket counts (`ticketCount`/`uint32(units)`/`whole`); event definition unchanged, only emitted values shift from `x TICKET_SCALE` scaled to whole. | SAFE |
| JPT-CLEAN-04 | ENT-05 keccak refactor — xorshift to keccak self-mix | `_jackpotTicketRoll:2200` | `8a81a87c` | MODIFIED_LOGIC | `entropy = EntropyLib.hash2(entropy, entropy)` (full-diffusion keccak self-mix) replaces the deleted xorshift `EntropyLib.entropyStep`. Intentionally CHANGES BAF roll output semantics for a given seed (not byte-equivalent to v39 — permitted). `JackpotTicketWin` topic-hash unchanged. | SAFE_BY_STRUCTURAL_CLOSURE |
| JPT-CLEAN-05 | `EntropyLib.entropyStep` deletion | `contracts/libraries/EntropyLib.sol` | `8a81a87c` | DELETED | `entropyStep` function + NatSpec deleted; `EntropyLib` keeps only `hash2`. Zero `EntropyLib.entropyStep` callsites remain in `contracts/`. | SAFE_BY_STRUCTURAL_CLOSURE |
| JPT-CLEAN-05 | `_queueLootboxTickets` wrapper deletion | `contracts/storage/DegenerusGameStorage.sol` | `8a81a87c` | DELETED | Zero-caller `_queueLootboxTickets` wrapper deleted (`JackpotModule.sol:2216` was its only caller — replaced by direct `_queueTickets` in Phase 276). Sibling helpers `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` untouched. | SAFE_BY_STRUCTURAL_CLOSURE |
| JPT-CLEAN-04 | MintModule comment touch | `DegenerusGameMintModule.sol:649` | `8a81a87c` | DOCS_ONLY | `_rollRemainder` design-rationale comment rewritten to drop the dead `entropyStep` name while keeping the keccak-over-XOR rationale. Comment-only; no codegen effect. | SAFE_BY_STRUCTURAL_CLOSURE |
| JPT-CLEAN-06 | Storage byte-identity + bytecode delta | (entire JackpotModule storage layout) | `8a81a87c` | REFACTOR_ONLY | `278-01-STORAGE-LAYOUT-DIFF.md` PASS — 171/171 layout lines, `forge inspect` diff empty, sha256 identical. Bytecode -689 bytes NET-NEGATIVE (two function deletions outweigh the swap). | SAFE_BY_STRUCTURAL_CLOSURE |
| Phase 278 Wave 2 | `Ent05KeccakRefactorInvariant.test.js` + `CrossSurfaceTicketMixing.test.js` + 6 modified + `package.json` | `test/stat/`, `test/integration/`, `test/fuzz/`, `test/unit/` | `c3baf694` | REFACTOR_ONLY (TEST) | Post-keccak-refactor statistical invariant (N=20K) + cross-surface rem-byte regression + wrapper-removal + whole-ticket emit regression; entropyStep replicas re-baselined onto the keccak `rollEvolve`. | SAFE_BY_STRUCTURAL_CLOSURE |
| Phase 278 remediation | Stale `[02a]` MintModule byte-identity test-gate supersede | `test/` (stale gate) | `a91dac85` | DOCS_ONLY | The stale `[02a]` MintModule byte-identity assertion no longer applied after the Phase 278 wave; comment-only / test-gate supersede touch. No `contracts/` mutation. | SAFE_BY_STRUCTURAL_CLOSURE |

#### Row Group 5 — Phase 279 BUR (whole-BURNIE floor)

| Source | Path | Line | SHA | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | --- | -------------- | ------------- | --------------- |
| BUR-01 | `_resolveLootboxCommon` `burnieAmount` floor | `DegenerusGameLootboxModule.sol:1023` | `8ef4a010` | MODIFIED_LOGIC | `burnieAmount = (burnieAmount / 1 ether) * 1 ether` before the `if (burnieAmount != 0)` guard; floored value flows to `creditFlip`, `LootBoxOpened.burnie`, return tuple. Burnie-accumulation block reordered after `_accumulateLootboxRolls` (stack-depth fix, D-279-BUR01-SITE-01 discretion). **Section 3.A prose note:** the BUR-01 floor contributes the dominant share of the +114-byte NET-POSITIVE Phase-279-only bytecode delta — a documented user-accepted override per `279-VERIFICATION.md`, NOT a defect (see Section 3.C INFO note). | SAFE |
| BUR-02 | `_awardDailyCoinToTraitWinners` `baseAmount` floor + `extra`/`cursor` dead-var removal | `DegenerusGameJackpotModule.sol:1789` | `8ef4a010` | MODIFIED_LOGIC | `baseAmount = ((coinBudget / cap) / 1 ether) * 1 ether`; `extra`/`cursor` declarations + both `++cursor`/wrap blocks + `amount += 1` cursor-rotation block FULLY DELETED per A1 mechanic (D-40N-BUR-FLOOR-01); `randomWord` + both `++i` preserved. Daily-budget evaporation when `baseAmount < 1 ether` accepted per D-40N-BUR-DUST-01. | SAFE |
| BUR-03 | `_awardFarFutureCoinJackpot` `perWinner` floor | `DegenerusGameJackpotModule.sol:1896` | `8ef4a010` | MODIFIED_LOGIC | `perWinner = ((farBudget / found) / 1 ether) * 1 ether` before the unchanged `if (perWinner == 0) return` early-bail at `:1897`. 25% far-future budget evaporation when `perWinner < 1 ether`. | SAFE |
| BUR-04 | Storage byte-identity for both modules | (LootboxModule + JackpotModule storage layout) | `8ef4a010` | REFACTOR_ONLY | `279-01-STORAGE-LAYOUT-DIFF.md` PASS — 171/171 layout lines each, `forge inspect` diff empty, sha256 identical for BOTH modules. Zero new state vars / events / emit sites / modifiers / entry points. | SAFE_BY_STRUCTURAL_CLOSURE |
| BUR-05 | Bytecode delta (+114 bytes NET-POSITIVE) | (deployed bytecode) | `8ef4a010` | REFACTOR_ONLY | Phase-279-only delta: JackpotModule -26 bytes (NET-NEGATIVE as expected); LootboxModule +140 bytes (Yul optimizer stack-spill in the stack-depth-saturated `_resolveLootboxCommon`); total +114 bytes. Documented user-accepted override per `279-VERIFICATION.md`. Cumulative vs `6a7455d1` (Phases 275-279): -1,792 bytes. **NOT a defect — no F-40-NN finding block opened (see Section 3.C INFO note).** | SAFE_BY_STRUCTURAL_CLOSURE |
| Phase 279 Wave 2 | 4 new test files + `SurfaceRegression.test.js` re-cut + `package.json` | `test/unit/`, `test/stat/` | `37207743` | REFACTOR_ONLY (TEST) | 35 new tests (floor regression at all 3 sites + invariant sweep `amount % 1 ether == 0` + mint-boost negative cross-site assertion); `SURF_01_PROTECTED_RANGES_V40` re-cut around the Phase 279 delta lines. | SAFE_BY_STRUCTURAL_CLOSURE |

#### Section 3.A Summary

v40.0 source-tree changes since baseline `6a7455d1`: 12 commits across 5 surface phases — 5 USER-APPROVED batched contract commits (`b6ed8fce`, `c473867e`, `02fb7085`, `8a81a87c`, `8ef4a010`) + 5 USER-APPROVED batched test commits (`bb1b1abd`, `1568fd5c`, `6fbee850`, `c3baf694`, `37207743`) + 2 remediation commits (`f7a6fccd` MODIFIED_LOGIC contract gap-closure, `a91dac85` DOCS_ONLY test-gate supersede). 32 Section 3.A rows across 5 row groups (Phase 275: 6 rows; Phase 276: 6 rows; Phase 277: 9 rows; Phase 278: 7 rows; Phase 279: 6 rows — 2 dedicated remediation rows included). Per-verdict distribution: every row verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE per AUDIT-01. Row count (32) >= the changed-declaration count derivable from `git diff --stat 6a7455d1..HEAD -- contracts/` (6 source files + 2 tester files = 8 changed files; ~15 changed declarations across `_resolveLootboxCommon`, `_jackpotTicketRoll`, `_awardDailyCoinToTraitWinners`, `_awardFarFutureCoinJackpot`, the 3 events, `entropyStep`, `_queueLootboxTickets`, the 2 new private helpers, and the `EntropyLib` library). Classification distribution: 14 MODIFIED_LOGIC + 4 DELETED + 12 REFACTOR_ONLY + 2 DOCS_ONLY. All 12 commit SHAs are grep-present in this section.

### 3.B AUDIT-04 Zero-New-State Attestation

Grep-proof attestation: zero new storage slots, zero new public/external mutation entry points, zero new external pure entry points, zero new admin functions, zero new modifiers, zero new upgrade hooks, zero new ERC-20 mint entry points since v39.0 baseline `6a7455d1`. Plus a clean-deletion attestation for the two Phase 278 deletions.

**Storage byte-identity (zero new storage slots):**

Recipe:
```
forge inspect contracts/modules/DegenerusGameLootboxModule.sol:DegenerusGameLootboxModule storage-layout
forge inspect contracts/modules/DegenerusGameJackpotModule.sol:DegenerusGameJackpotModule storage-layout
# vs the same at a detached worktree of 6a7455d1; diff after astId normalization
```

Output: per the per-phase STORAGE-LAYOUT-DIFF artifacts — `275-A` PASS (LootboxModule 83/83 entries, stripped diff empty), `276-A` PASS (JackpotModule 83/83 entries, astId-normalized diff empty), `278-01` PASS (JackpotModule 171/171 `forge inspect` lines, sha256 identical), `279-01` PASS (BOTH LootboxModule + JackpotModule 171/171 lines each, sha256 identical). Every v40.0 contract change touches only function bodies, event definitions, NatSpec, and function-scope locals — no contract-level state variable, mapping, or struct was added, removed, or reordered in any of the 6 modified source files. Storage layout byte-identical at v40 HEAD vs `6a7455d1` for `DegenerusGameLootboxModule.sol` and `DegenerusGameJackpotModule.sol`.

**Zero new public/external mutation entry points:**

Recipe:
```
git diff 6a7455d1..HEAD -- contracts/ \
  | grep -E "^\+.*function .* (public|external)" \
  | grep -v "view\|pure"
```

Output: 0 hits. Phase 277 added two `private` helpers (`_lootboxBoonBudget`, `_accumulateLootboxRolls`) — both `private` linkage, no ABI surface. `_resolveLootboxCommon` remains `private`. The 4 caller entry points (`openLootBox`, `openBurnieLootBox`, `resolveLootboxDirect`, `resolveRedemptionLootbox`) retain byte-identical public-function signatures. No new public/external functions added.

**Zero new admin functions / modifiers / upgrade hooks:**

Recipe:
```
git diff 6a7455d1..HEAD -- contracts/ \
  | grep -E "^\+.*(modifier |onlyOwner|onlyAdmin|UUPSUpgradeable|_authorizeUpgrade)"
```

Output: 0 hits. No new admin gates introduced.

**Zero new events / zero new emit sites at v40 HEAD net:**

The event surface NET-SHRINKS at v40.0: `LootboxTicketRoll` deleted (Phase 277), `LootBoxWwxrpReward` deleted (Phase 277 `f7a6fccd` remediation). The 3 retained events (`LootBoxOpened`, `BurnieLootOpen`, `JackpotTicketWin`) gained a `bool roundedUp` field each (Phase 277) — field additions to existing events, not new events; `LootBoxOpened` also lost its `bonusBurnie` field. No new emit sites: the whole-BURNIE floor (Phase 279) is a pure-amount transformation upstream of existing `coinflip.creditFlip` / `creditFlipBatch` callsites — event-field values reflect post-floor amounts.

**Clean-deletion attestation (the two Phase 278 deletions — zero orphaned callsites):**

Recipe:
```
grep -rn "EntropyLib.entropyStep" contracts/        # expected: empty
grep -rn "_queueLootboxTickets" contracts/          # expected: empty
```

Output: both empty. `EntropyLib.entropyStep` was deleted in Phase 278 `8a81a87c` — its sole live consumer `_jackpotTicketRoll` was swapped to `EntropyLib.hash2(entropy, entropy)` in the same commit, so the deletion left zero orphaned callsites. `_queueLootboxTickets` was deleted in the same commit — `JackpotModule.sol:2216` was its only caller and Phase 276 `c473867e` already swapped that callsite to direct `_queueTickets(whole)`, so the wrapper was zero-caller dead code at the time of deletion. Phase 278 `278-02` test wave TST-CLEAN-02 + the cross-surface `CrossSurfaceTicketMixing.test.js` independently assert zero remaining `_queueLootboxTickets` references and zero `EntropyLib.entropyStep` live references across `contracts/`.

**Zero new ERC-20 mint entry points:**

Recipe:
```
git diff 6a7455d1..HEAD -- contracts/ \
  | grep -E "^\+.*\.(mint|mintFor|mintPrize|_mint)\("
```

Output: the only `+` hits are the post-`f7a6fccd` re-positioning of the existing `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` callsite inside the manual-branch `if (payColdBustConsolation && whole == 0)` gate — this is NOT a new mint entry point; it reuses the existing `IWrappedWrappedXRP.mintPrize` route already present at v39. The whole-BURNIE floor adds zero mint routes (it floors an amount already flowing to the existing `coinflip.creditFlip` callsite). No new mint-route surface.

**Five-line zero-attestation roll-up** (one phrase per line for grep-tally clarity):

- zero new storage slots — per-phase STORAGE-LAYOUT-DIFF artifacts all PASS (LootboxModule + JackpotModule byte-identical vs `6a7455d1`).
- zero new public/external mutation entry points — `git diff 6a7455d1..HEAD -- contracts/ | grep -E "^\+.*function .* (public|external)" | grep -v "view|pure"` returns 0.
- zero new admin functions — `git diff 6a7455d1..HEAD -- contracts/ | grep -E "^\+.*(onlyOwner|onlyAdmin)"` returns 0.
- zero new modifiers — `git diff 6a7455d1..HEAD -- contracts/ | grep -E "^\+.*modifier "` returns 0.
- zero new upgrade hooks — `git diff 6a7455d1..HEAD -- contracts/ | grep -E "^\+.*(UUPSUpgradeable|_authorizeUpgrade)"` returns 0.

**Closing attestation:** Storage layout byte-identical at v40.0 closure HEAD vs v39.0 baseline `6a7455d1` for `DegenerusGameLootboxModule.sol` + `DegenerusGameJackpotModule.sol` per the 4 per-phase STORAGE-LAYOUT-DIFF artifacts; zero new public/external mutation entry points; zero new external pure entry points; zero new admin functions; zero new modifiers; zero new upgrade hooks. The event surface NET-SHRINKS (2 events deleted, 3 events gained a `bool roundedUp` field, `LootBoxOpened` lost `bonusBurnie`). The two Phase 278 deletions (`EntropyLib.entropyStep`, `_queueLootboxTickets`) are CLEAN — zero orphaned callsites, grep-confirmed. Zero new ERC-20 mint-route surfaces. The 2 new functions are `private` (no entry point surface). `DegenerusGameMintModule.sol` carries only a comment-only NatSpec touch (Phase 278 `8a81a87c`); its mint-boost logic (`_queueTicketsScaled` + `_rollRemainder` + `rem` byte) is byte-identical at v40 HEAD vs `6a7455d1` per D-40N-MINTBOOST-OUT-01.

### 3.C AUDIT-03 Conservation Re-Proof

Conservation re-proof across 3 domains: EV-neutrality of the Bernoulli round-up extended to the auto-resolve LootboxModule branch + the JackpotModule `_jackpotTicketRoll` path; bit-slice independence for the reused `[152..167]` slice (auto-resolve) and the `[200..215]` slice (jackpot); the whole-BURNIE floor amount-conservation posture. Closes the AUDIT-03 design contract.

**(1) EV-neutrality of the Bernoulli round-up extended to auto-resolve + jackpot paths:**

The Bernoulli round-up is the SAME floor + biased-coin-flip identity proven exactly in `audit/FINDINGS-v39.0.md` Section 3.C (1) for the v39 manual path, now applied to two additional surfaces. For a pre-collapse scaled value `scaledPre`, with `whole_floor = scaledPre / TICKET_SCALE` and `frac = scaledPre % TICKET_SCALE`:

```
P(roundedUp = true)  = frac / TICKET_SCALE   (Bernoulli condition: slice mod TICKET_SCALE < frac)
P(roundedUp = false) = (TICKET_SCALE - frac) / TICKET_SCALE
E[whole_post] = whole_floor * P(false) + (whole_floor + 1) * P(true)
             = whole_floor + frac / TICKET_SCALE
             = scaledPre / TICKET_SCALE          (exact in rationals, since scaledPre = whole_floor * TICKET_SCALE + frac)
```

EV-preserving by construction on BOTH the auto-resolve LootboxModule branch (Phase 275, reading `bits[152..167]` of the per-resolution `seed`) and the JackpotModule `_jackpotTicketRoll` path (Phase 276, reading `bits[200..215]` of the per-roll `entropy`). Per-resolution / per-roll variance is higher than the v39 cross-lootbox-deterministic-`rem`-byte accumulation flow — this is the documented TICKET-granularity tradeoff settled at D-40N-GRANULARITY-01 (1 ticket = 4 entries; 4x variance vs entry-granularity accepted in exchange for simpler storage). EV is invariant. Empirical witnesses: Phase 275 TST-LBX-AR-01 (`mean(whole_post) * TICKET_SCALE` within plus-or-minus max(1.5, 0.5%) of `scaledPre` at N=10K across {47,99,100,147,250,1000,9999}) + Phase 276 TST-JPT-BR-01 (within plus-or-minus 0.5% at N=10K).

**(2) Bit-slice independence — `[152..167]` reuse on auto-resolve + `[200..215]` on jackpot:**

The auto-resolve LootboxModule branch reads the SAME `bits[152..167]` 16-bit slice the v39 manual path consumes. This is NOT a collision risk: each `_resolveLootboxCommon` invocation derives a fresh per-resolution `seed = keccak256(abi.encode(rngWord, player, day, amount))` — the manual path (`openLootBox` / `openBurnieLootBox`) and the auto-resolve path (`resolveLootboxDirect` / `resolveRedemptionLootbox`) never share a `seed` value because each open / resolution is a distinct keccak preimage (distinct `rngWord` and/or distinct `player`/`day`/`amount` tuple). The slice is consumed at most once per `seed` after the Phase 275 hoist (the Bernoulli predicate sits in shared scope above the retired sentinel gate). By keccak output-entropy properties the slice is uniform mod `TICKET_SCALE` with <=0.10% relative bias (the 16-bit `uint16 % 100` bias bound, consistent with the existing `bits[0..15]` rangeRoll precedent). Empirical witness: Phase 275 TST-LBX-AR-04 (per-caller chi2 Wilson-Hilferty Z < 1.645; pairwise + cross-slice covariance < 50).

The jackpot `bits[200..215]` slice is 180+ bits separated from the existing `bits[0..12]` path/level consumers. After the Phase 278 ENT-05 keccak refactor, `_jackpotTicketRoll` evolves `entropy` via `EntropyLib.hash2(entropy, entropy)` (a full-diffusion keccak self-mix) — so the `bits[200..215]` slice reads a full-diffusion keccak word, not an xorshift word. Any slice of a full keccak word is full-entropy; the 180+ bit separation is structurally moot for a keccak word but is documented in the NatSpec for clarity. Empirical witnesses: Phase 276 TST-JPT-BR-03 (chi2 independence vs `bits[0..12]`, >=10K seeds) + Phase 278 TST-CLEAN-01 (post-keccak-refactor chi2 uniformity + 2-roll uniqueness + `bits[200..215]` independence at N=20K).

**(3) Whole-BURNIE floor amount-conservation posture (Phase 279):**

The whole-BURNIE floor at the 3 RNG-amount sites (`LootboxModule:1080` `burnieAmount`, `JackpotModule:1842` `baseAmount`, `JackpotModule:1922` `perWinner`) is a one-directional integer-division floor: `x = (x / 1 ether) * 1 ether`. It can only ever round DOWN — it cannot over-issue protocol value. Sub-1-BURNIE residues evaporate per D-40N-BUR-DUST-01 (user disposition 2026-05-13: "sub 1 burnie amounts are economically negligible"); per-spin per-player dust loss at `LootboxModule:1080` is bounded < 1 BURNIE; daily-budget evaporation at the 2 JackpotModule sites when `baseAmount < 1 ether` (near-future) or `perWinner < 1 ether` (far-future) is accepted. This is NOT a conservation violation — it is a conservative (solvency-favouring) rounding that aligns with the protocol-wide "all rounding favors solvency" design decision in KNOWN-ISSUES.md. The floor is silent per D-40N-BUR-SILENT-01: no consolation, no replacement event, no cursor-rotation residue redistribution; the existing `LootBoxOpened.burnie` + `JackpotBurnieWin.amount` + `FarFutureCoinJackpotWinner.perWinner` event fields emit the post-floor amounts. Empirical witness: Phase 279 TST-BUR-04 (invariant sweep N=20,000/site asserting `amount % 1 ether == 0` across all 3 sites) + the mint-boost negative cross-site assertion proving `MintModule:1199` flip-credit retains status-quo fractional emission per D-40N-BUR-MINTBOOST-OUT-01.

**INFO-tier 3c note — BUR-05 +114-byte NET-POSITIVE bytecode deviation (per `feedback_gas_worst_case.md` worst-case framing):**

Phase 279's BUR-05 plan expected a NET-NEGATIVE bytecode delta (the `extra`/`cursor` dead-var removal outweighing the 3 inline floors). The measured Phase-279-only delta was **+114 bytes NET-POSITIVE**: `DegenerusGameJackpotModule` -26 bytes (NET-NEGATIVE as expected — the `extra`/`cursor` removal outweighs the 2 added floors) but `DegenerusGameLootboxModule` +140 bytes, which dominates the aggregate. Theoretical worst-case derivation (the load-bearing analysis per `feedback_gas_worst_case.md`): the BUR-01 floor is two opcodes (`DIV` + `MUL`) of arithmetic — its theoretical worst-case runtime cost is ~10-15 gas flat. The +140-byte CODE-SIZE delta is NOT that arithmetic; it is the Yul optimizer's stack-spill workaround. `_resolveLootboxCommon` was already at the Solidity stack-depth ceiling — adding ANY statement forces the optimizer into a less-compact stack schedule (measured: the burnie-accumulation reorder ALONE that makes the floor compile is -96 bytes; reorder + floor together is +140). This is a documented user-accepted override recorded in `279-VERIFICATION.md` (the user explicitly approved committing as-is at the Phase 279 Task 3 checkpoint). A documented user-accepted bytecode-size deviation on a non-negotiable correctness floor is NOT a defect — no F-40-NN finding block is opened for it. Section 4 surfaces (j) and (k) attest the BUR floors SAFE on their own merits independent of the bytecode-size delta. For context, the cumulative bytecode delta vs the v39 baseline `6a7455d1` (spanning Phases 275-279) is -1,792 bytes — the v40.0 milestone NET-SHRINKS the deployed bytecode substantially.

**Closing conservation attestation:** EV-neutrality of the Bernoulli round-up holds `E[whole_post] = scaledPre / TICKET_SCALE` exactly on the auto-resolve LootboxModule branch and the JackpotModule `_jackpotTicketRoll` path (per-resolution / per-roll variance higher than the v39 `rem`-byte accumulation flow is the documented TICKET-granularity tradeoff per D-40N-GRANULARITY-01). The reused `bits[152..167]` slice on auto-resolve is collision-free because each `_resolveLootboxCommon` invocation derives a distinct per-resolution keccak `seed`; the `bits[200..215]` jackpot slice reads a full-diffusion keccak word after the Phase 278 ENT-05 refactor. The whole-BURNIE floor is a one-directional solvency-favouring integer-division floor that cannot over-issue protocol value; sub-1-BURNIE residues evaporate per D-40N-BUR-DUST-01. The BUR-05 +114-byte bytecode deviation is a documented user-accepted override (INFO-tier; no F-40-NN finding block).

---
