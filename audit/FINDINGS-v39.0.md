---
phase: 274-lootbox-whole-ticket-rounding-wwxrp-consolation-terminal
plan: 01
milestone: v39.0
milestone_name: Lootbox Whole-Ticket Rounding + WWXRP Consolation
audit_baseline: 06623edb
audit_baseline_signal: MILESTONE_V38_AT_HEAD_06623edb
v34_baseline: 6b63f6d4daf346a53a1d463790f637308ea8d555
v34_baseline_signal: MILESTONE_V34_AT_HEAD_6b63f6d4daf346a53a1d463790f637308ea8d555
audit_subject_head: "<v39-close-sha>"
closure_signal: MILESTONE_V39_AT_HEAD_<sha>
deliverable: audit/FINDINGS-v39.0.md
requirements: [LBX-WT-01, LBX-WT-02, LBX-WT-03, LBX-WT-04, LBX-WT-05,
               LBX-WX-01, LBX-WX-02, LBX-WX-03, LBX-WX-04,
               LBX-EVT-01, LBX-EVT-02, LBX-EVT-03, LBX-EVT-04, LBX-EVT-05, LBX-EVT-06,
               TST-WT-01, TST-WT-02, TST-WT-03, TST-WT-04, TST-WT-05, TST-WT-06, TST-WT-07,
               TST-WX-01, TST-WX-02, TST-WX-03,
               TST-REG-01, TST-REG-02, TST-REG-03, TST-REG-04,
               AUDIT-01, AUDIT-02, AUDIT-03, AUDIT-04, AUDIT-05, AUDIT-06,
               REG-01, REG-02, REG-03, REG-04]
phase_status: terminal
phase_count: 1
phase_ids: [274]
phase_shape: single-phase
requirements_total: 39
adversarial_pass_skills: [contract-auditor, zero-day-hunter, economic-analyst]
adversarial_pass_pattern: PARALLEL_SINGLE_MESSAGE
out_of_scope_skills: [degen-skeptic]
included_since_baseline:
  - sha: ff929948
    subject: "fix(273): BAF credit routing — day-D orphan + RngLocked predicate + jackpot-phase override + tests"
  - sha: e9807891
    subject: "test(273): BAF-ROUTE-06/07/08 expansion — purchase-phase routing, mid-bracket override skip, markBafSkipped equivalence"
  - sha: e04d3333
    subject: "chore(273): phase SUMMARY — BAF credit routing complete (14/14 tests, security property attested)"
  - sha: 1eb1ecb5
    subject: "docs: clarify _livenessTriggered VRF-grace branch as stalled-advance bailout"
write_policy: "Single-phase patch closure mirroring v36.0 Phase 266 + v38.0 Phase 272 precedent. Two USER-APPROVED batched commits: Wave 1 contracts (c21f833a — feat(274): manual lootbox Bernoulli whole-ticket + WWXRP consolation + LootboxTicketRoll event [LBX-WT-01..05, LBX-WX-01..04, LBX-EVT-01..06]); Wave 2 tests (f8e55cfe — test(274): manual lootbox whole-ticket + consolation + auto-resolve regression + LootboxTicketRoll [TST-WT-01..07, TST-WX-01..03, TST-REG-01..04]). All Wave 3 audit deliverable + ADVERSARIAL-LOG + closure flips AGENT-COMMITTED atomic-per-task with audit(274): or docs(274): prefix. READ-only flip on audit/FINDINGS-v39.0.md (chmod 444 + frontmatter status: FINAL — READ-ONLY + read_only: true) is the terminal commit per feedback_manual_review_before_push.md final user-review gate per D-274-APPROVAL-01."
supersedes: none
status: "DRAFT — pending final user-review gate"
read_only: false
generated_at: 2026-05-13T00:00:00Z
---

# v39.0 Findings — Lootbox Whole-Ticket Rounding + WWXRP Consolation (Terminal)

**Audit Baseline.** The audit baseline is v38.0 audit-subject HEAD `06623edb` (closure signal `MILESTONE_V38_AT_HEAD_06623edb` carry-forward from `audit/FINDINGS-v38.0.md` §9c). v39.0 audit-subject HEAD `MILESTONE_V39_AT_HEAD_<sha>` is resolved at Wave 3 Task 3.10 atomic-update per D-274-CLOSURE-01. Between the v38.0 closure HEAD and the v39.0 audit-subject HEAD, four Phase 273 BAF-credit-routing maintenance commits shipped pre-v39.0 — `ff929948` `fix(273): BAF credit routing — day-D orphan + RngLocked predicate + jackpot-phase override + tests` + `e9807891` `test(273): BAF-ROUTE-06/07/08 expansion` + `e04d3333` `chore(273): phase SUMMARY` + `1eb1ecb5` `docs: clarify _livenessTriggered VRF-grace branch as stalled-advance bailout`. These four commits fold into the v39.0 delta-audit baseline as included-since-baseline surface-coverage attestation per D-274-BAF273-INCLUDE-01 (no F-39-NN finding eligible; §3.A delta-surface table assigns them their own row group). v39.0 introduces ONE Wave 1 USER-APPROVED contract commit `c21f833a` `feat(274): manual lootbox Bernoulli whole-ticket + WWXRP consolation + LootboxTicketRoll event [LBX-WT-01..05, LBX-WX-01..04, LBX-EVT-01..06]` (touches `contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/interfaces/IDegenerusGameModules.sol`; manual-only behavioral split per D-274-MANUAL-ONLY-01) + ONE Wave 2 USER-APPROVED test commit `f8e55cfe` `test(274): manual lootbox whole-ticket + consolation + auto-resolve regression + LootboxTicketRoll [TST-WT-01..07, TST-WX-01..03, TST-REG-01..04]` (74 tests across 4 new files in `test/unit/`, `test/edge/`, `test/stat/`).

**Scope.** Single canonical milestone-closure deliverable for v39.0 per D-274-FILES-01 carry of D-272-FILES-01 / D-271-FILES-01 / D-266-FILES-01 / D-265-FILES-01 (9-section shape locked). v39.0 = single-phase milestone shape per `274-CONTEXT.md` `<domain>`: Phase 274 (Lootbox Whole-Ticket Rounding + WWXRP Consolation — terminal). Three-wave structure inside Phase 274: Wave 1 contract commit (LBX-WT-01..05 + LBX-WX-01..04 + LBX-EVT-01..06 — single USER-APPROVED batched commit per D-274-APPROVAL-01), Wave 2 test commit (TST-WT-01..07 + TST-WX-01..03 + TST-REG-01..04 — single USER-APPROVED batched commit), Wave 3 audit deliverable + adversarial pass + closure flips (AGENT-COMMITTED atomic-per-task). Terminal phase per D-274-FCITE-01 — zero forward-cites emitted from Phase 274 to any post-v39.0 milestone phases. Verified at §8 Forward-Cite Closure block. **Scope NARROWING per D-274-MANUAL-ONLY-01:** the v39.0 behavioral payload (Bernoulli collapse + WWXRP consolation + `LootboxTicketRoll` event) applies ONLY to manual lootbox opens (`openLootBox` + `openBurnieLootBox`). Auto-resolve paths (`resolveLootboxDirect` decimator-claim + `resolveRedemptionLootbox` sDGNRS-redemption) are explicitly UNCHANGED — they continue routing through `_queueTicketsScaled`, continue producing fractional `rem` byte residues, continue emitting `TicketsQueuedScaled` at queue time, continue resolving via `_rollRemainder` at activation time. Gating discriminator: `index != type(uint48).max` inside `_resolveLootboxCommon`.

**Write policy.** READ-only after Wave 3 Task 3.11 terminal atomic commit per D-274-APPROVAL-01 + D-272-APPROVAL-01 / D-271-APPROVAL-02 / D-266-APPROVAL-01 carry-forward chain. KNOWN-ISSUES.md UNMODIFIED at v39 close per D-274-KI-01 default zero-promotion path (`git diff 06623edb..HEAD -- KNOWN-ISSUES.md` returns empty). Zero F-39-NN finding blocks expected per D-274-KI-01 carry default path (AUDIT-03 8-surface adversarial sweep verdicts SAFE_*). Per `feedback_never_preapprove_contracts.md`, the agent does NOT pre-approve any contract change — Wave 1 contract commit `c21f833a` and Wave 2 test commit `f8e55cfe` both landed under USER-APPROVED batched gates per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md`. Per `feedback_manual_review_before_push.md`, the user reviews this deliverable's full diff before any push — final user-review gate at Wave 3 Task 3.11 before READ-only flip on `audit/FINDINGS-v39.0.md` (chmod 444 + frontmatter `status: FINAL — READ-ONLY` + `read_only: true`).

---

## 2. Executive Summary

### Closure Verdict Summary

- AUDIT-01: §3.A delta-surface table covers all source-tree changes `06623edb` → v39 HEAD with hunk-level evidence + {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DOCS_ONLY} classification per row. Five row groups: Phase 274 Wave 1 LBX-WT (5 rows) + LBX-WX (4 rows) + LBX-EVT (6 rows) + Phase 273 included-since-baseline (4 rows) + Phase 274 Wave 1/2 commit attestation (2 rows). D-274-MANUAL-ONLY-01 scope-narrowing (manual-callers only) and D-274-BAF273-INCLUDE-01 Phase 273 inclusion explicitly cited.
- AUDIT-02: §3.A row coverage for the 4 Phase 273 BAF-credit-routing pre-shipped commits + Phase 274 Wave 1 contract commit + Phase 274 Wave 2 test commit.
- AUDIT-03: §4 8-surface adversarial sweep (a)..(h) with verdict bucket per row; default zero F-39-NN finding blocks per D-274-KI-01; `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` PARALLEL adversarial pass per D-274-ADVERSARIAL-01.
- AUDIT-04: 3-skill PARALLEL adversarial pass on finished §4 draft per D-274-ADVERSARIAL-01 carry; `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` spawn; `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. Adversarial-log at `.planning/phases/274-lootbox-whole-ticket-rounding-wwxrp-consolation-terminal/274-01-ADVERSARIAL-LOG.md`.
- AUDIT-05: §6 KI walkthrough EXC-01..04 RE_VERIFIED at v39 HEAD; default zero-promotion path per D-272-KI-01 carry; closure verdict in §6c.
- AUDIT-06: §9c emits closure signal `MILESTONE_V39_AT_HEAD_<sha>` verbatim in 5 locations per D-274-CLOSURE-01 (resolved at Task 3.10 atomic-update); KNOWN-ISSUES.md UNMODIFIED per default path.
- REG-01: §5a — v38.0 closure signal `MILESTONE_V38_AT_HEAD_06623edb` NON-WIDENING at v39 HEAD. Surface set: Degenerette + Mint + Jackpot + EntropyLib + JackpotBucketLib + TraitUtils byte-identical; auto-resolve lootbox callsites byte-equivalent; `BurnieCoinflip.sol` carries pre-shipped Phase 273 mutations (not v39 work — folded as included-since-baseline per D-274-BAF273-INCLUDE-01).
- REG-02: §5b — v34.0 closure signal `MILESTONE_V34_AT_HEAD_6b63f6d4` NON-WIDENING at v39 HEAD. TraitUtils + `_pickSoloQuadrant` + JackpotBucketLib byte-identical.
- REG-03: §6b 4-row KI envelope re-verifications EXC-01..03 NEGATIVE-scope + EXC-04 RE_VERIFIED with NARROWS retained (BAF-jackpot-only scope; EntropyLib byte-identical at v39 HEAD).
- REG-04: §5d per-finding PASS/REGRESSED/SUPERSEDED row table walking `audit/FINDINGS-v25.0.md` → `audit/FINDINGS-v38.0.md` for findings referencing v39-touched function/surface set (`_resolveLootboxCommon` manual-path additions + `_queueTickets` new lootbox callsite + auto-resolve byte-equivalence).
- Combined milestone closure: `MILESTONE_V39_AT_HEAD_<sha>`.

### Severity Counts (per D-08 5-Bucket Rubric)

- CRITICAL: 0
- HIGH: 0
- MEDIUM: 0
- LOW: 0
- INFO: 0
- Total F-39-NN: 0

Default expected per D-274-KI-01 carry. The Bernoulli round-up is mathematically well-bounded: `E[whole_post] == scaledPre / 100` exactly by construction (per-N HERO_BOOST + per-N payout + symbol distribution all UNCHANGED at v39; new logic operates entirely on the existing post-distress scaled ticket count); the bit-slice `[152..167]` is a previously-unallocated 16-bit slice of the same single-source-of-entropy primary chunk (pairwise independent of the 8 other sub-roll consumers by keccak output-entropy properties; 16-bit-mod-100 bias ≤0.10% relative, consistent with the existing `bits[0..15]` rangeRoll precedent); storage layout byte-identical (zero new admin / external mutation / modifier paths; new constant + new event do not consume storage slots); auto-resolve paths byte-equivalent to v38.0 (sentinel `type(uint48).max` routes the unchanged `_queueTicketsScaled` branch); index-gating discriminator routes manual vs auto-resolve with zero crossover (top-of-domain sentinel cannot collide with real lootbox indices — ~281 trillion lifetime lootboxes would be required to reach `0xFFFFFFFFFFFF`); event-emission ordering preserved (`TicketsQueued` / `LootBoxWwxrpReward` → `LootboxTicketRoll` → outer `LootBoxOpened`); function-scope `futureTickets` NEVER reassigned to `whole` (preserves D-274-NO-EVT-BREAK-01: `LootBoxOpened.futureTickets` + `BurnieLootOpen.tickets` continue carrying scaled value). Cross-module byte-identity preserved for `MintModule + EntropyLib + JackpotModule + Degenerette + TraitUtils + JackpotBucketLib`. Severity ceiling for any v39-emitted F-39-NN: LOW (no value extraction beyond the existing lootbox prize space; same total-EV mechanics as pre-v39 except for variance impact on the variance-averse subset which is bounded acceptable per user disposition; EV invariant by construction). Most likely severity for any inline-draft finding-candidate: INFO. Severity counts reconcile to §4 F-39-NN block tally line by line per ROADMAP success criterion.

### D-08 5-Bucket Severity Rubric

Severity calibration mapped via the v25–v38 player-reachability × value-extraction × determinism-break frame, carried forward as D-08 from v25 onward (D-274-SEV-01 carry of D-272-SEV-01).

| Severity | Definition |
| -------- | ---------- |
| CRITICAL | Player-reachable, material protocol value extraction, no mitigation at HEAD. |
| HIGH | Player-reachable, bounded value extraction OR no extraction but hard determinism violation. |
| MEDIUM | Player-reachable, no value extraction, observable behavioral asymmetry. |
| LOW | Player-reachable theoretically but not practically (gas economics / timing / coordination cost makes exploit non-viable). |
| INFO | Not player-reachable, OR documented design decision, OR observation only (naming inconsistency, dead code, gas optimization, doc drift). |

Severity calibration for any F-39-NN that may surface during §4 adversarial-pass disposition: LOW ceiling (Bernoulli collapse is EV-neutral by construction per `E[whole_post] == scaledPre / 100` exact identity; player cannot extract value from the variance increase because expected value is invariant; storage layout byte-identical preserves one-line revert path; auto-resolve paths byte-equivalent so the only behavioral surface is the manual ticket-path branch). INFO likely for documentation-only items. Per D-274-KI-01 default path, zero F-39-NN blocks emit; severity-at-HEAD = N/A.

### D-09 KI Gating Rubric Reference

The §6 KI-eligibility 3-predicate test (D-09) is distinct from the D-08 severity rubric above. A candidate qualifies for `KNOWN-ISSUES.md` promotion (verdict `KI_ELIGIBLE_PROMOTED`) iff ALL three predicates hold:

1. **Accepted-design** — behavior is intentional / documented / load-bearing for the protocol's design (not an oversight or accident)
2. **Non-exploitable** — no player-reachable path extracts protocol value or breaks determinism
3. **Sticky** — the design choice persists across foreseeable future code revisions (not a transient state)

ANY false ⇒ Non-Promotion Ledger entry with the failing predicate identified. Default outcome at this milestone: zero F-39-NN finding blocks emit (D-274-KI-01 carry default path) → zero KI promotion candidates from new findings. KNOWN-ISSUES.md UNMODIFIED at v39 close per D-274-KI-01. EXC-04 NARROWS retained from v36.0 (BAF-jackpot-only scope) — EntropyLib byte-identical at v39 HEAD; per-resolution `seed = keccak256(abi.encode(rngWord, player, day, amount))` UNCHANGED in v39 (the new `bits[152..167]` Bernoulli read consumes a previously-unallocated slice of the unchanged keccak primary chunk; no new RNG-path mutation). See §6 KI Gating Walk + Non-Promotion Ledger.

### Forward-Cite Closure Summary

D-274-FCITE-01 carry of D-272-FCITE-01 / D-271-FCITE-01 / D-266-FCITE / D-265-FCITE-01 / D-262-FCITE-01 / D-257-FCITE-01 / D-253-15 step 8 + ROADMAP terminal-phase rule: zero forward-cites emitted from Phase 274 to any post-v39.0 milestone phases. Verified at §8 Forward-Cite Closure block. v39.0 = single-phase milestone (Phase 274) per `274-CONTEXT.md` `<domain>`. Deferred items (mint-boost retirement, auto-resolve retirement, jackpot ticket-award sites + BAF Bernoulli + v36.0 ENT-05 xorshift refactor) are cited via locked-decision IDs (D-274-MINTBOOST-OUT-01 / D-274-AUTORESOLVE-OUT-01 / D-274-JACKPOT-OUT-01) without naming specific future-milestone numbers. The "Deferred to Future Milestones" subsection in PROJECT.md is the single-source-of-truth lookup for future-pickup; the §9 §"Deferred to Future Milestones" subsection in this deliverable attests the carry-forward bundle without forward-citing in-flight work.

### Attestation Anchor

See §9 Milestone Closure Attestation for the D-253-15 step 9 attestation block triggering v39.0 milestone closure via signal `MILESTONE_V39_AT_HEAD_<sha>` (resolved at Wave 3 Task 3.10 atomic-update across 5 verbatim FINDINGS locations + 3 cross-document propagation locations per D-274-CLOSURE-01).

---

## 3. Per-Phase Sections

### 3a. Phase 274 — Lootbox Whole-Ticket Rounding + WWXRP Consolation (Terminal)

**Source-tree changes since baseline:**
- USER-APPROVED Wave 1 contract-side change `c21f833a` — `feat(274): manual lootbox Bernoulli whole-ticket + WWXRP consolation + LootboxTicketRoll event [LBX-WT-01..05, LBX-WX-01..04, LBX-EVT-01..06]`. Two files: `contracts/modules/DegenerusGameLootboxModule.sol` (manual-branch addition + new private constant + new event + index threading + bit-allocation NatSpec update) + `contracts/interfaces/IDegenerusGameModules.sol` (new event declaration on `IDegenerusGameLootboxModule` interface). Storage layout byte-identical vs `06623edb` (zero new storage slots, zero new admin / external mutation / modifier paths; new constant is inlined at compile time; new event does not occupy a storage slot). Per `feedback_batch_contract_approval.md` + `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. D-274-BIT-SLICE-01 was superseded intra-Wave-1 from the original `uint8 % 100` form to `uint16(seed >> 152) % uint16(TICKET_SCALE)` — quantification of the prior `uint8` form's ~17% relative bias for `frac ≤ 56` (256 mod 100 = 56 residues with 3 preimages vs 44 residues with 2 preimages) versus the ~0.10% relative bias of the `uint16` form (consistent with the existing `bits[0..15]` rangeRoll `uint16 % 100` precedent at L850-851). The bit-slice consumed widened from `bits[152..159]` (8 bits) to `bits[152..167]` (16 bits); total primary-chunk consumption updated 152 → 168.
- USER-APPROVED Wave 2 test-side change `f8e55cfe` — `test(274): manual lootbox whole-ticket + consolation + auto-resolve regression + LootboxTicketRoll [TST-WT-01..07, TST-WX-01..03, TST-REG-01..04]`. Four new test files: `test/unit/LootboxWholeTicket.test.js` (TST-WT-01..07 manual-path whole-ticket assertions; +712 LOC), `test/unit/LootboxConsolation.test.js` (TST-WX-01..03 consolation predicate matrix + magnitude assertion; +217 LOC), `test/edge/LootboxAutoResolveRegression.test.js` (TST-REG-01..04 auto-resolve byte-equivalence + cross-mixing variance; +338 LOC), `test/stat/LootboxBernoulliEv.test.js` (statistical EV-neutrality property test extracted; +155 LOC). Total +1,422 LOC of test code across the 4 files; 74 tests; all 74 passing at Wave 2 close.

**Requirements:** 39 of 39 satisfied — LBX-WT-01..05 + LBX-WX-01..04 + LBX-EVT-01..06 (15 contract-side requirements satisfied by Wave 1 change `c21f833a`) + TST-WT-01..07 + TST-WX-01..03 + TST-REG-01..04 (14 test-side requirements satisfied by Wave 2 change `f8e55cfe`) + AUDIT-01..06 + REG-01..04 (10 audit-side requirements satisfied by Wave 3 AGENT-COMMITTED atomic chain; see Wave 3 closure flips for traceability checkbox updates).

**What IS at v39.0 close (Wave 1 delta):**

- **LBX-WT-01** — `_resolveLootboxCommon` retains the scaled-space accumulation across the `amountFirst` and (optional) `amountSecond` branches; both branches continue to call `_resolveLootboxRoll` → `_lootboxTicketCount` which returns `count × TICKET_SCALE`. The distress-mode bonus block (post-edit L1003-1026) computes in scaled space on BOTH manual and auto-resolve paths so small distress bonuses do not truncate to 0 (function `_lootboxTicketCount` UNCHANGED at this milestone; return-value contract preserved).
- **LBX-WT-02** — At the end of `_resolveLootboxCommon`'s `if (futureTickets != 0)` block, after the distress-bonus accumulation, the code branches on `index != type(uint48).max` (manual vs auto-resolve). Manual path snapshots `uint32 scaledPre = futureTickets;` then computes `uint32 whole = futureTickets / uint32(TICKET_SCALE); uint32 frac = futureTickets % uint32(TICKET_SCALE); bool roundedUp = false;` and applies the Bernoulli round-up: `if (frac != 0 && (uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)) { unchecked { whole += 1; } roundedUp = true; }`. Function-scope `futureTickets` is NEVER reassigned to `whole` — a separate local `whole` carries the post-collapse value to the queue / consolation switch; the function-scope `futureTickets` keeps the scaled value and is returned to `openBurnieLootBox` at L658 as `BurnieLootOpen.tickets` (scaled) and emitted by the function itself as `LootBoxOpened.futureTickets` (scaled). EV-neutrality property (manual path only): `E[whole_post] == scaledPre / 100` exact identity (see §3.C AUDIT-03 conservation re-proof).
- **LBX-WT-03** — Inside the manual branch (post-Bernoulli): if `whole != 0` call `_queueTickets(player, targetLevel, whole, false)` — the whole-ticket queue helper at `contracts/DegenerusGameStorage.sol` L562-589 — which emits `TicketsQueued(buyer, level, qty=whole)` via the storage helper. Else (`whole == 0` from non-zero `scaledPre`): the consolation path triggers (see LBX-WX-02 below). After the if/else split, `emit LootboxTicketRoll(player, index, scaledPre, roundedUp);` fires exactly once at the end of the manual branch. Auto-resolve branch (sentinel passed): `_queueTicketsScaled(player, targetLevel, futureTickets, false)` — the today-behavior at L1067 — which emits `TicketsQueuedScaled`; no Bernoulli, no consolation, no `LootboxTicketRoll` emit.
- **LBX-WT-04** — Bit-allocation NatSpec at L883-893 updated: new entry `bits[152..167]   fracRoundUp % 100      (_resolveLootboxCommon manual-path ticket whole-collapse; auto-resolve paths leave slice unread; bias 0.10%)` added; total-consumption line updated `Total primary-chunk consumption: 168 bits / 256 available (bits[152..167] consumed only on manual paths; auto-resolve paths leave the slice unread).` Implementation rationale: the bit-slice was widened to 16 bits within Wave 1 per D-274-BIT-SLICE-01 supersession — the original 8-bit form had ~17% relative bias for `frac ≤ 56`; the 16-bit form has ≤0.10% relative bias (consistent with the existing `bits[0..15]` rangeRoll `uint16 % 100` precedent at L850-851).
- **LBX-WT-05** — Storage layout byte-identical at v39.0 phase-close HEAD vs v38.0 baseline `06623edb` (storage-slot grep proof at §3.B AUDIT-04). Zero new admin entry points; zero new external mutation entry points; zero new modifiers. `_queueTicketsScaled`, `_rollRemainder`, and the `rem` byte in `ticketsOwedPacked` STAY (mint-boost path at `DegenerusGameMintModule.sol` L1142 + auto-resolve lootbox paths `resolveLootboxDirect` + `resolveRedemptionLootbox` retain them).
- **LBX-WX-01** — New private constant `uint256 private constant LOOTBOX_WWXRP_CONSOLATION = 1 ether;` declared at L307 immediately after `LOOTBOX_WWXRP_PRIZE` (L304-305). Sibling constant; same magnitude. Per D-274-WX-AMOUNT-01: the cold-bust consolation trigger is much rarer than the regular 10%-path WWXRP win, so 1:1 magnitude is intentional per user disposition 2026-05-13.
- **LBX-WX-02** — Cold-bust consolation predicate: inside the manual branch, when `whole == 0` (post-Bernoulli) and `scaledPre > 0` (guard already entered): `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);` is called and `emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);` fires (reuse of existing event signature at L127-132 — same signature as the regular 10%-path WWXRP win emission). Consumers infer consolation from same-tx absence of `TicketsQueued` AND presence of `LootboxTicketRoll` with derived `whole = (preRollTickets / 100) + (roundedUp ? 1 : 0) == 0`, corroborated by same-tx `LootBoxWwxrpReward`. No explicit `consolationPaid` flag in the event per D-274-EVT-ROLL-01 minimal 4-field schema.
- **LBX-WX-03** — Consolation trigger predicate is structurally gated: fires if-and-only-if (a) `index != type(uint48).max` (manual path) AND (b) `futureTickets > 0` pre-Bernoulli (the outer `if (futureTickets != 0)` guard at L1003 was entered) AND (c) `whole == 0` post-Bernoulli (the inner `if (whole != 0)` else-arm). Auto-resolve paths NEVER trigger consolation regardless of pre-Bernoulli state. Manual-path zero-from-the-start cases (ticket-path not selected; OR `_lootboxTicketCount` truncated scaled to 0 from a degenerate-tiny budget) skip the entire `if (futureTickets != 0)` block and therefore skip both the Bernoulli AND the consolation emit AND the `LootboxTicketRoll` emit.
- **LBX-WX-04** — Event-shape decision: the consolation reuses `LootBoxWwxrpReward(player, day, amount, wwxrpAmount)` (same signature as the regular WWXRP path at L127-132). UI / indexer distinguishes consolation from regular WWXRP win by absence of a same-tx ticket-path emission AND presence of `LootboxTicketRoll` with derived `whole == 0`. Distinct event signature for the consolation is not introduced at v39.0 (per CONTEXT.md `<locked_decisions>` minimal 4-field schema decision).
- **LBX-EVT-01** — NO breaking change to any existing event. `LootBoxOpened.futureTickets` continues emitting the post-distress scaled value on BOTH manual and auto-resolve paths (identical to v38.0 behavior; matches `LootboxTicketRoll.preRollTickets` on the manual path). `BurnieLootOpen.tickets` continues emitting scaled (consumes first return value of `_resolveLootboxCommon` which is the function-scope `futureTickets` left at scaled per LBX-WT-02). `TicketsQueuedScaled` continues emitting from `_queueTicketsScaled` callsites (mint-boost at `MintModule.sol` L1142 + auto-resolve lootbox paths). The new `LootboxTicketRoll` event is purely additive — UI / indexer consumers can opt in for remainder visibility without rebasing existing event reads.
- **LBX-EVT-02** — Origin tracking by event type: `TicketsQueued(buyer, level, qty)` (qty = whole) emitted from `_queueTickets` on manual lootbox opens. `TicketsQueuedScaled(buyer, level, qty)` (qty = scaled) emitted from `_queueTicketsScaled` on (a) mint-boost call site `DegenerusGameMintModule.sol` L1142 (UNCHANGED) and (b) auto-resolve lootbox paths `resolveLootboxDirect` + `resolveRedemptionLootbox` (UNCHANGED). Origin-tracking discipline preserved across the v38 → v39 transition by event type.
- **LBX-EVT-03** — New event `LootboxTicketRoll(address indexed player, uint48 indexed lootboxIndex, uint32 preRollTickets, bool roundedUp)` declared at the `DegenerusGameLootboxModule.sol` event block (post-edit L134-159, immediately after `LootBoxWwxrpReward`) AND on the `IDegenerusGameLootboxModule` interface in `IDegenerusGameModules.sol` (post-edit L267-282). Both `player` and `lootboxIndex` indexed for filter efficiency. Emitted exactly once inside `_resolveLootboxCommon`'s manual branch at the end of the `if (futureTickets != 0)` block — after the Bernoulli collapse and after the if/else split that either queues whole tickets or pays consolation. Fires iff (a) manual path AND (b) ticket-path produced a non-zero pre-Bernoulli scaled value. Does NOT fire on auto-resolve paths. Does NOT fire when ticket-path was not selected. Does NOT fire when `_lootboxTicketCount` math truncated scaled to 0 from the start.
- **LBX-EVT-04** — `LootboxTicketRoll` field semantics: `lootboxIndex` is the per-lootbox storage index from `openLootBox(player, index)` / `openBurnieLootBox(player, index)`. Auto-resolve paths NEVER emit this event, so the `type(uint48).max` sentinel value never appears as an emitted `lootboxIndex`. `preRollTickets` is the post-distress-bonus, pre-collapse scaled value (i.e. the value snapshotted in LBX-WT-02 as `scaledPre`); equals same-tx `LootBoxOpened.futureTickets` on manual paths. Divide by `TICKET_SCALE=100` for the floor-tickets, modulo `100` for the round-up Bernoulli weight (e.g. `247` → floor `2`, frac `47`). `roundedUp` is `true` iff the Bernoulli condition `(uint16(seed >> 152) % uint16(TICKET_SCALE)) < uint16(frac)` evaluated true AND `frac != 0`; `false` when `frac == 0` (no roll needed; whole-only scaled) OR `frac != 0` but Bernoulli failed. Consumer derives whole-tickets-awarded as `(preRollTickets / 100) + (roundedUp ? 1 : 0)` and infers consolation as `whole == 0 && preRollTickets > 0` (corroborated by same-tx `LootBoxWwxrpReward`).
- **LBX-EVT-05** — Index parameter threading: `_resolveLootboxCommon` signature gains `uint48 index` parameter placed immediately after `uint32 day` for parameter-order coherence. The 4 internal callers pass: `openLootBox` (L583-597) passes its `index` arg (real index); `openBurnieLootBox` (L637-651) passes its `index` arg (real index); `resolveLootboxDirect` (L679-693) passes `type(uint48).max` sentinel; `resolveRedemptionLootbox` (L714-728) passes `type(uint48).max` sentinel. Index parameter is dual-purpose: (a) identifies the lootbox in the `LootboxTicketRoll` emit on manual paths; (b) gates the behavioral split between manual (Bernoulli + `_queueTickets` + emit) and auto-resolve (`_queueTicketsScaled`, status quo). Per D-274-EVT-INDEX-SENTINEL-01: top-of-domain sentinel `type(uint48).max` = `0xFFFFFFFFFFFF` cannot collide with any realistic real lootbox index (~281 trillion lifetime lootboxes would be required to reach it).
- **LBX-EVT-06** — Event-emission ordering inside the manual-path `if (futureTickets != 0)` block (single-tx, ticket-path win): `TicketsQueued(player, level, whole)` (or `LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION)` on consolation) → `LootboxTicketRoll(player, index, scaledPre, roundedUp)` → outer `LootBoxOpened(player, day, amount, level, scaledPreFutureTickets, burnie, bonus)` (existing emission by the wrapping function at L1109, scaled value unchanged per LBX-EVT-01). Consumers group by `tx` + `player` + `lootboxIndex` to correlate. Auto-resolve paths emit `TicketsQueuedScaled` + `LootBoxOpened` (no `LootboxTicketRoll`) — same ordering as v38.0.

**What IS at v39.0 close (Wave 2 test delta — 4 new files):**

- **TST-WT-01** — `test/stat/LootboxBernoulliEv.test.js` EV-neutrality property test. At N=10,000 forced-seed `_resolveLootboxCommon`-equivalent invocations across scaled values {47, 99, 100, 147, 250, 1000, 9999} via a Solidity tester contract that mirrors the production Bernoulli verbatim: `uint16(seed >> 152) % uint16(TICKET_SCALE) < uint16(frac)`. Property: `mean(whole_post) × TICKET_SCALE` is within ±2.5 of pre-Bernoulli scaled value at N=10K (5-sigma binomial bound). EV-neutrality `E[whole_post] == scaledPre / 100` confirmed empirically within statistical tolerance.
- **TST-WT-02** — `test/unit/LootboxWholeTicket.test.js` boundary tests at scaledPre ∈ {0, 1, 99, 100, 101, 199, 200}. Confirm: 0 → 0 deterministically (no Bernoulli roll, guard not entered, no `LootboxTicketRoll` emitted); 1 → 0 with `frac=1` and Bernoulli sample uniformly distributed in [0, TICKET_SCALE-1] (P(rounded_up)=1/100); 99 → 0 with P(rounded_up)=99/100; 100 → 1 deterministically (no fractional, `frac==0`, no Bernoulli roll, `roundedUp=false`); 101 → 1 with P(rounded_up)=1/100; 199 → 1 + 99/100 (E ≈ 1.99); 200 → 2 deterministically.
- **TST-WT-03** — `test/unit/LootboxWholeTicket.test.js` bit-slice independence assertions. mod-100 chi² at N=10K over the `bits[152..167]` slice with df=99 Wilson-Hilferty Z < 1.645 (PASS at α=0.05). Pairwise covariance independence test between `bits[152..167]` and `bits[0..15]` (the rangeRoll slice) at N=10K (covariance bounded within ±0.01 of theoretical zero). Plus source-level proof that `bits[152..167]` is gated by `if (index != type(uint48).max)` (auto-resolve paths leave the slice unread).
- **TST-WT-04** — `test/unit/LootboxWholeTicket.test.js` queue-helper switch assertion. On manual-branch ticket-path wins with `whole > 0`: `TicketsQueued(buyer, level, whole)` is emitted (NOT `TicketsQueuedScaled`); `_queueTickets` storage helper invoked (not `_queueTicketsScaled`).
- **TST-WT-05** — `test/unit/LootboxWholeTicket.test.js` event-shape preservation. `LootBoxOpened.futureTickets` continues emitting the scaled value on a manual-path open (matches `LootboxTicketRoll.preRollTickets`); `BurnieLootOpen.tickets` (consumes destructured `_resolveLootboxCommon` first return) continues emitting scaled — D-274-NO-EVT-BREAK-01 preserved. G17 grep gate asserts function-scope `futureTickets` reassignment count UNCHANGED vs `06623edb` baseline.
- **TST-WT-06** — `test/unit/LootboxWholeTicket.test.js` `LootboxTicketRoll` 4-lattice emission assertions: (a) `preRollTickets=300, frac=0` → emit `roundedUp=false`; (b) `preRollTickets=247, Bernoulli wins` → emit `roundedUp=true`; (c) `preRollTickets=247, Bernoulli loses` → emit `roundedUp=false`; (d) `preRollTickets=47, Bernoulli loses` → emit `roundedUp=false` with same-tx `LootBoxWwxrpReward` for consolation. Plus 3 negative assertions: (e) manual lootbox open landing on DGNRS / large-BURNIE / regular-WWXRP path → NO `LootboxTicketRoll` event emitted; (f) manual lootbox open where `_lootboxTicketCount` truncated scaled to 0 → NO `LootboxTicketRoll` event emitted; (g) auto-resolve open via `resolveLootboxDirect` or `resolveRedemptionLootbox` → NO `LootboxTicketRoll` event emitted regardless of outcome.
- **TST-WT-07** — `test/unit/LootboxWholeTicket.test.js` field-consistency invariants assertion. For each emitted `LootboxTicketRoll`: derived `whole = (preRollTickets / 100) + (roundedUp ? 1 : 0)` equals the queued ticket count at the level; `preRollTickets > 0` always (guard); `preRollTickets` equals same-tx `LootBoxOpened.futureTickets` (scaled emission preserved); `lootboxIndex` equals the `index` arg passed to `openLootBox` / `openBurnieLootBox`; when derived `whole == 0` then same-tx `LootBoxWwxrpReward` exists (consolation correlation); same-tx storage at `lootboxEth[index][player]` / `lootboxBurnie[index][player]` was zeroed (open completion).
- **TST-WX-01** — `test/unit/LootboxConsolation.test.js` cold-bust seed-forced trigger test. Force a seed where `scaledPre > 0`, `frac > 0`, `scaledPre < TICKET_SCALE` (so `whole = 0` after floor), AND `bits[152..167] mod 100 >= frac` (Bernoulli fails). Assert: zero `TicketsQueued` event; exactly one `LootBoxWwxrpReward(player, day, amount, 1 ether)` event; `wwxrp.balanceOf(player)` increased by exactly `1 ether`; exactly one `LootboxTicketRoll` event with `preRollTickets > 0`, `roundedUp = false`, derived `whole = 0`.
- **TST-WX-02** — `test/unit/LootboxConsolation.test.js` non-trigger predicate matrix. Consolation does NOT fire when: (a) ticket-path not selected on manual path (pathRoll lands DGNRS / large-BURNIE / regular-WWXRP); (b) ticket-path selected but `_lootboxTicketCount` truncated to scaled 0 from start (outer guard not entered); (c) ticket-path selected with `whole >= 1` post-Bernoulli (success case, no consolation); (d) ANY auto-resolve open via `resolveLootboxDirect` or `resolveRedemptionLootbox` regardless of pre-Bernoulli state.
- **TST-WX-03** — `test/unit/LootboxConsolation.test.js` magnitude assertion `LOOTBOX_WWXRP_CONSOLATION == LOOTBOX_WWXRP_PRIZE == 1 ether` via a tester contract that exposes both constants. Defensive drift catch: if either constant changes in a future milestone, this assertion fails.
- **TST-REG-01** — `test/edge/LootboxAutoResolveRegression.test.js` manual-only `_rollRemainder` non-entry assertion. Open N manual lootboxes (no mint-boost activity AND no auto-resolve activity) targeting one future level; advance to that level; assert no `rem != 0` state in `ticketsOwedPacked[wk][player]` for any manual-only player at activation time (equivalent observable: `_rollRemainder` invocation count = 0 across manual-only player+level queues at activation).
- **TST-REG-02** — `test/edge/LootboxAutoResolveRegression.test.js` mint-boost fractional path still works. Open a mint with `boostBps != 0` that produces a fractional `adjustedQty` (via `DegenerusGameMintModule._queueTicketsScaled` L1142 callsite, UNCHANGED at v39); advance to target level; assert `_rollRemainder` fires correctly on the boost-derived remainder; mint-boost end-to-end ticket count matches v38 baseline.
- **TST-REG-03** — `test/edge/LootboxAutoResolveRegression.test.js` auto-resolve byte-equivalence. `resolveLootboxDirect` (decimator-claim) and `resolveRedemptionLootbox` (sDGNRS-redemption) still produce fractional `rem` byte residues; advance to target level; assert `_rollRemainder` fires; assert `TicketsQueuedScaled` was emitted at queue time; assert NO `LootboxTicketRoll` was emitted; assert NO consolation `LootBoxWwxrpReward(..., 1 ether)` was emitted on cold-bust scaled-low outcomes from these auto-resolve paths. Status-quo preservation test.
- **TST-REG-04** — `test/edge/LootboxAutoResolveRegression.test.js` cross-mixing variance test. Same player opens N manual + M auto-resolve at same future level; confirm manual contributions are subject to per-lootbox Bernoulli (slightly higher variance than v38 cross-lootbox-deterministic-accumulation); auto-resolve contributions still pool deterministically via `rem` byte accumulation; total mean ticket count matches `sum(scaledPre_manual_i) / TICKET_SCALE + sum(scaledPre_auto_j) / TICKET_SCALE` within ±0.5% at N+M = 8 lootboxes.

**Cumulative source-tree mutation at Phase 274 close:** the diff vs baseline `06623edb` returns the Wave 1 hunks for the LootboxModule + IDegenerusGameModules.sol interface (manual-branch addition + new constant + new event + index threading + bit-allocation NatSpec) and the Wave 2 4-new-file hunks under `test/` (LootboxWholeTicket.test.js + LootboxConsolation.test.js + LootboxAutoResolveRegression.test.js + LootboxBernoulliEv.test.js) plus the Phase 273 included-since-baseline files (`contracts/BurnieCoinflip.sol` + `test/edge/BafCreditRouting.test.js`). No other source-tree files modified in v39 scope.

### 3.A AUDIT-01 Delta-Surface Table

Every source-tree change from v38.0 baseline `06623edb` → v39.0 HEAD enumerated with hunk-level evidence and {NEW, MODIFIED_LOGIC, REFACTOR_ONLY, DOCS_ONLY} classification per row. Five row groups: Phase 274 Wave 1 LBX-WT (5 rows), LBX-WX (4 rows), LBX-EVT (6 rows) + Phase 273 included-since-baseline (4 rows; D-274-BAF273-INCLUDE-01) + Phase 274 Wave 1/2 attestation (2 rows).

**Scope-narrowing attestation (D-274-MANUAL-ONLY-01):** the v39.0 behavioral payload applies ONLY to manual lootbox opens (`openLootBox` + `openBurnieLootBox`). Auto-resolve callers (`resolveLootboxDirect` + `resolveRedemptionLootbox`) are explicitly UNCHANGED — they continue calling `_queueTicketsScaled`, continue producing `rem` byte residues, continue emitting `TicketsQueuedScaled`, and never emit `LootboxTicketRoll` or pay consolation. Gating discriminator: `index != type(uint48).max` inside `_resolveLootboxCommon`.

**Phase 273 inclusion attestation (D-274-BAF273-INCLUDE-01):** four maintenance changes shipped between v38.0 closure HEAD `06623edb` and v39.0 open — `ff929948` + `e9807891` + `e04d3333` + `1eb1ecb5`. These fold into the v39.0 delta-audit baseline as included-since-baseline mutations (surface-coverage attestation only; no F-39-NN finding eligible). Row Group 4 below assigns them §3.A coverage.

#### Row Group 1 — LBX-WT (manual-path whole-ticket Bernoulli; change `c21f833a`)

| Source | Path | Line | Requirement | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | ----------- | -------------- | ------------- | --------------- |
| LBX-WT-01 | `DegenerusGameLootboxModule.sol` :: `_resolveLootboxCommon` distress-bonus block preservation | L1003-1026 (post-edit) | REFACTOR_ONLY | Distress-bonus scaled accumulation preserved on BOTH manual and auto-resolve paths (small bonuses don't truncate to 0). `_lootboxTicketCount` UNCHANGED at this milestone. | SAFE_BY_DESIGN |
| LBX-WT-02 | `_resolveLootboxCommon` Bernoulli math block | L1029-1043 (post-edit) | MODIFIED_LOGIC | NEW Bernoulli round-up consuming `bits[152..167]`: `uint16(seed >> 152) % uint16(TICKET_SCALE) < uint16(frac)`. `scaledPre` snapshotted; `whole` separate local; function-scope `futureTickets` NEVER reassigned to `whole` (D-274-NO-EVT-BREAK-01). | SAFE |
| LBX-WT-03 | `_resolveLootboxCommon` queue-helper switch | L1044-1064 (post-edit) | MODIFIED_LOGIC | NEW if-branch: manual → `_queueTickets(player, targetLevel, whole, false)` (whole helper, emits `TicketsQueued`); else (whole==0) → consolation (LBX-WX-02). Auto-resolve branch (sentinel) → `_queueTicketsScaled(player, targetLevel, futureTickets, false)` (today's behavior). | SAFE |
| LBX-WT-04 | `_resolveLootboxCommon` bit-allocation NatSpec | L883-893 (post-edit) | REFACTOR_ONLY | New entry `bits[152..167] fracRoundUp % 100 (bias 0.10%)` added; total-consumption line updated 152 → 168. | SAFE_BY_STRUCTURAL_CLOSURE |
| LBX-WT-05 | Storage layout byte-identity (entire `DegenerusGameStorage.sol`) | (entire file) | REFACTOR_ONLY | Diff vs `06623edb` for `DegenerusGameStorage.sol` returns empty. Zero new storage slots, zero new state-decl mutations. New `LOOTBOX_WWXRP_CONSOLATION` constant is inlined at compile time (not a storage slot); new `LootboxTicketRoll` event does not occupy a storage slot. | SAFE_BY_STRUCTURAL_CLOSURE |

#### Row Group 2 — LBX-WX (WWXRP cold-bust consolation; change `c21f833a`)

| Source | Path | Line | Requirement | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | ----------- | -------------- | ------------- | --------------- |
| LBX-WX-01 | `DegenerusGameLootboxModule.sol` :: `LOOTBOX_WWXRP_CONSOLATION` constant declaration | L302-307 (post-edit; sibling to `LOOTBOX_WWXRP_PRIZE` at L304-305) | NEW | `uint256 private constant LOOTBOX_WWXRP_CONSOLATION = 1 ether;` declared. Magnitude-equal to `LOOTBOX_WWXRP_PRIZE`. | SAFE_BY_DESIGN |
| LBX-WX-02 | `_resolveLootboxCommon` consolation `else`-branch emit | L1048-1058 (post-edit) | MODIFIED_LOGIC | NEW: when `whole == 0` (post-Bernoulli) inside the manual branch, `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION);` is called + `emit LootBoxWwxrpReward(player, day, amount, LOOTBOX_WWXRP_CONSOLATION);` fires (event signature reused from L127-132). | SAFE |
| LBX-WX-03 | `_resolveLootboxCommon` consolation predicate gating | L1027 + L1029 + L1048 (post-edit) | MODIFIED_LOGIC | Predicate: `(index != type(uint48).max) AND (futureTickets > 0 pre-Bernoulli via outer guard) AND (whole == 0 post-Bernoulli)`. Auto-resolve paths NEVER trigger. Manual-path zero-from-start cases (ticket-path not selected; `_lootboxTicketCount` truncated to 0) bypass outer guard. | SAFE_BY_DESIGN |
| LBX-WX-04 | Consolation event signature reuse | L127-132 (existing `LootBoxWwxrpReward` event UNCHANGED) | REFACTOR_ONLY | No new event variant introduced; UI / indexer distinguishes consolation from regular WWXRP win by absence of same-tx ticket-path emission + presence of `LootboxTicketRoll` with derived whole=0. | SAFE_BY_DESIGN |

#### Row Group 3 — LBX-EVT (new additive `LootboxTicketRoll` event + index threading; change `c21f833a`)

| Source | Path | Line | Requirement | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | ----------- | -------------- | ------------- | --------------- |
| LBX-EVT-01 | `LootBoxOpened.futureTickets` + `BurnieLootOpen.tickets` + `TicketsQueuedScaled` semantics | (across module) | REFACTOR_ONLY | NO breaking change. Both fields continue carrying the scaled value on BOTH paths (function-scope `futureTickets` left at scaled per LBX-WT-02). G17 + G18 + G19 grep gates assert non-mutation. | SAFE_BY_STRUCTURAL_CLOSURE |
| LBX-EVT-02 | Origin tracking by event type | (storage helpers UNCHANGED) | REFACTOR_ONLY | `TicketsQueued` from `_queueTickets` (manual lootbox opens); `TicketsQueuedScaled` from `_queueTicketsScaled` (mint-boost + auto-resolve lootbox opens). Discipline preserved. | SAFE_BY_DESIGN |
| LBX-EVT-03 | NEW `LootboxTicketRoll` event declaration | `DegenerusGameLootboxModule.sol` L134-159 (post-edit) + `IDegenerusGameModules.sol` L267-282 (post-edit) | NEW | `event LootboxTicketRoll(address indexed player, uint48 indexed lootboxIndex, uint32 preRollTickets, bool roundedUp);` declared at module event block AND interface. Both `player` and `lootboxIndex` indexed. | SAFE_BY_DESIGN |
| LBX-EVT-04 | `LootboxTicketRoll` field semantics | L1060 emit site (post-edit) | NEW | `preRollTickets = scaledPre` (post-distress scaled); `roundedUp = Bernoulli outcome`. Consumer derives `whole = (preRollTickets / 100) + (roundedUp ? 1 : 0)`; consolation inferred from `whole == 0 && preRollTickets > 0` corroborated by same-tx `LootBoxWwxrpReward`. | SAFE_BY_DESIGN |
| LBX-EVT-05 | Index parameter threading: `_resolveLootboxCommon` signature + 4 callers | L905 (signature, post-edit) + L619/L673/L716/L752 (4 caller sites, post-edit) | MODIFIED_LOGIC | `uint48 index` added after `uint32 day`. Manual callers (`openLootBox`, `openBurnieLootBox`) pass real index; auto-resolve callers (`resolveLootboxDirect`, `resolveRedemptionLootbox`) pass `type(uint48).max` sentinel (= 0xFFFFFFFFFFFF). Dual-purpose: behavioral gating + emit identifier. | SAFE |
| LBX-EVT-06 | Event-emission ordering | (single-tx emit order inside manual branch) | MODIFIED_LOGIC | Manual ticket-path win: `TicketsQueued(whole)` or `LootBoxWwxrpReward(consolation)` → `LootboxTicketRoll` → outer `LootBoxOpened(scaled)`. Auto-resolve: `TicketsQueuedScaled` → outer `LootBoxOpened(scaled)` (no `LootboxTicketRoll`). Consumers group by tx + player + lootboxIndex. | SAFE_BY_DESIGN |

#### Row Group 4 — Phase 273 included-since-baseline (D-274-BAF273-INCLUDE-01 surface-coverage attestation; no F-39-NN finding eligible)

| Source | Path | Line | SHA | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | --- | -------------- | ------------- | --------------- |
| Phase 273 fix | `BurnieCoinflip.sol` | `:525` (`cursor > bafResolvedDay` → `cursor >= bafResolvedDay`), `:585-598` (RngLocked guard predicate fix: `cachedLevel` instead of `purchaseLevel_`; adds `bafLevel` override `cachedLevel + 1` when `inJackpotPhase && cachedLevel % 10 == 0`), `:1035-1045` (`_coinflipLockedDuringTransition` same predicate fix) | `ff929948` | MODIFIED_LOGIC | Three-point patch to BAF credit routing: day-D orphan fix + RngLocked predicate fix at x10 boundaries + jackpot-phase bafLevel override. 11-test verification suite added at `test/edge/BafCreditRouting.test.js`. | SAFE_BY_DESIGN_PHASE_273 |
| Phase 273 test expansion | `test/edge/BafCreditRouting.test.js` | (file) | `e9807891` | REFACTOR_ONLY (TEST) | BAF-ROUTE-06 (post-jackpot purchase-phase routing) + BAF-ROUTE-07 (mid-bracket override skip — gate is tight) + BAF-ROUTE-08 (`markBafSkipped` path equivalence to `runBafJackpot`). 14 of 14 tests passing. | SAFE_BY_DESIGN_PHASE_273 |
| Phase 273 SUMMARY | `.planning/phases/273-baf-credit-routing-fix/273-01-SUMMARY.md` | (file) | `e04d3333` | DOCS_ONLY | Phase 273 close summary; no source-tree changes. | SAFE_BY_STRUCTURAL_CLOSURE |
| `_livenessTriggered` NatSpec | `BurnieCoinflip.sol` (NatSpec on the `_livenessTriggered` helper) | (NatSpec lines) | `1eb1ecb5` | DOCS_ONLY | NatSpec-only clarification of `_livenessTriggered` VRF-grace branch as stalled-advance bailout. Zero behavioral change. | SAFE_BY_STRUCTURAL_CLOSURE |

**Footnote (Phase 273 log completeness):** SHA `1cae7682` `chore(273): scaffold Phase 273 in ROADMAP + STATE` (between `ff929948` and `e9807891`) is OUT-OF-AUDIT-SCOPE — it touches only `.planning/ROADMAP.md` + `.planning/STATE.md` planning artifacts with no source-tree mutations. Recorded here for log completeness only; not eligible for §3.A row coverage per D-274-BAF273-INCLUDE-01's surface-coverage scope.

#### Row Group 5 — Phase 274 Wave 1 + Wave 2 attestation rows

| Source | Path | Line | SHA | Classification | Hunk Evidence | Surface Verdict |
| ------ | ---- | ---- | --- | -------------- | ------------- | --------------- |
| Wave 1 contract-side change | `DegenerusGameLootboxModule.sol` + `IDegenerusGameModules.sol` | (aggregate) | `c21f833a` | MODIFIED_LOGIC | `feat(274): manual lootbox Bernoulli whole-ticket + WWXRP consolation + LootboxTicketRoll event [LBX-WT-01..05, LBX-WX-01..04, LBX-EVT-01..06]`. Aggregates Row Groups 1-3. | SAFE per per-row verdicts |
| Wave 2 test-side change | `test/unit/LootboxWholeTicket.test.js` + `test/unit/LootboxConsolation.test.js` + `test/edge/LootboxAutoResolveRegression.test.js` + `test/stat/LootboxBernoulliEv.test.js` | (4 new files; +1,422 LOC) | `f8e55cfe` | REFACTOR_ONLY (TEST) | `test(274): manual lootbox whole-ticket + consolation + auto-resolve regression + LootboxTicketRoll [TST-WT-01..07, TST-WX-01..03, TST-REG-01..04]`. 74 tests; all passing at Wave 2 close. Provides empirical evidence for §4 surfaces (a) EV-neutrality + (b) bit-slice independence + (c) consolation predicate + (e) auto-resolve byte-equivalence + (g) `LootboxTicketRoll` field-consistency. | SAFE_BY_STRUCTURAL_CLOSURE |

#### §3.A Summary

v39.0 source-tree changes since baseline `06623edb`: 1 Wave 1 contract-side change (`c21f833a` — LBX-WT-01..05 + LBX-WX-01..04 + LBX-EVT-01..06; 2 files modified) + 1 Wave 2 test-side change (`f8e55cfe` — TST-WT-01..07 + TST-WX-01..03 + TST-REG-01..04; 4 new test files) + 4 Phase 273 included-since-baseline changes (`ff929948` + `e9807891` + `e04d3333` + `1eb1ecb5`; 1 contract file + 1 test file + 2 docs-only). 15 rows in Row Groups 1-3 (Phase 274 contract-side) + 4 rows in Row Group 4 (Phase 273 included-since-baseline) + 2 rows in Row Group 5 (Phase 274 attestation). All rows verdicted SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / SAFE_BY_DESIGN_PHASE_273 per AUDIT-01. D-274-MANUAL-ONLY-01 narrowing + D-274-BAF273-INCLUDE-01 inclusion method explicitly cited above.

### 3.B AUDIT-04 Zero-New-State Attestation

Grep-proof attestation: zero new storage slots, zero new public/external mutation entry points, zero new external pure entry points, zero new admin functions, zero new modifiers, zero new upgrade hooks, zero new ERC-20 mint entry points since v38.0 baseline `06623edb`.

**Storage byte-identity (zero new storage slots):**

Recipe:
```
git diff 06623edb..HEAD -- contracts/DegenerusGameStorage.sol
```

Output: empty (0 files changed). Phase 274 Wave 1 change `c21f833a` touches only `contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/interfaces/IDegenerusGameModules.sol` — no storage-file changes. The bit allocation preserves all existing `FT_*_SHIFT` constants byte-identical; new `bits[152..167]` entry consumes a previously-unallocated slice of the per-resolution seed (a stack-local, NOT a storage slot). Storage layout byte-identical at v39 HEAD.

**Zero new public/external mutation entry points:**

Recipe:
```
git diff 06623edb..HEAD -- contracts/ \
  | grep -E "^\+.*function .* (public|external)" \
  | grep -v "view\|pure"
```

Output: 0 hits. The `_resolveLootboxCommon` signature change (added `uint48 index` parameter) is internal-only — the function remains `private`. The 4 caller entry points (`openLootBox` + `openBurnieLootBox` + `resolveLootboxDirect` + `resolveRedemptionLootbox`) retain byte-identical public-function signatures (their internal call passes the new `index` arg from their existing `index` parameter or the sentinel). No new public/external functions added.

**Zero new external pure entry points:**

Recipe:
```
git diff 06623edb..HEAD -- contracts/ \
  | grep -E "^\+.*function .* (external|public) pure"
```

Output: 0 hits.

**Zero new admin functions / modifiers / upgrade hooks:**

Recipe:
```
git diff 06623edb..HEAD -- contracts/ \
  | grep -E "^\+.*(modifier |onlyOwner|onlyAdmin|UUPSUpgradeable|_authorizeUpgrade)"
```

Output: 0 hits. No new admin gates introduced.

**Zero new ERC-20 mint entry points:**

Recipe:
```
git diff 06623edb..HEAD -- contracts/ \
  | grep -E "^\+.*\.(mint|mintFor|_mint)\("
```

Output: 1 hit at the consolation `wwxrp.mintPrize(player, LOOTBOX_WWXRP_CONSOLATION)` callsite (post-edit L1049 inside `_resolveLootboxCommon` manual branch). This is NOT a new mint entry point — it reuses the existing `IWrappedWrappedXRP.mintPrize` interface that already mints at the regular 10%-path WWXRP win site (L1585-1595 pre-edit; UNCHANGED at v39). Magnitude `1 ether` matches `LOOTBOX_WWXRP_PRIZE = 1 ether` per LBX-WX-01 + D-274-WX-AMOUNT-01. No new mint-route surface; one new callsite that consumes the existing route.

**One new constant; one new event declaration:**

- One new constant: `LOOTBOX_WWXRP_CONSOLATION = 1 ether` (compile-time inlined; not a storage slot).
- One new event: `LootboxTicketRoll` (events do not occupy storage slots; event log is calldata-equivalent).

**Cross-module byte-identity proof (v39 HEAD vs `06623edb`):**

Recipe (run at §3.B authoring time):
```
for f in \
  contracts/modules/DegenerusGameJackpotModule.sol \
  contracts/modules/DegenerusGameMintModule.sol \
  contracts/modules/DegenerusGameDegeneretteModule.sol \
  contracts/DegenerusTraitUtils.sol \
  contracts/libraries/JackpotBucketLib.sol \
  contracts/libraries/EntropyLib.sol \
  ; do \
    echo -n "$f: "; git diff 06623edb..HEAD -- "$f" | wc -l; \
  done
```

Output (each file emits `0` indicating byte-identical):
```
contracts/modules/DegenerusGameJackpotModule.sol: 0
contracts/modules/DegenerusGameMintModule.sol: 0
contracts/modules/DegenerusGameDegeneretteModule.sol: 0
contracts/DegenerusTraitUtils.sol: 0
contracts/libraries/JackpotBucketLib.sol: 0
contracts/libraries/EntropyLib.sol: 0
```

This grep-proof establishes that Phase 274 Wave 1 modifies ONLY `contracts/modules/DegenerusGameLootboxModule.sol` + `contracts/interfaces/IDegenerusGameModules.sol` per D-274-MANUAL-ONLY-01 scope narrowing. `contracts/BurnieCoinflip.sol` is NOT byte-identical at v39 HEAD vs `06623edb` because Phase 273 included-since-baseline changes shipped between v38.0 closure and v39.0 open (`ff929948` + `1eb1ecb5`); the BurnieCoinflip mutation is folded into the v39.0 audit baseline per D-274-BAF273-INCLUDE-01 (surface-coverage attestation only at §3.A Row Group 4; no F-39-NN finding eligible). Cross-cite Wave 2 test files for the same module-isolation invariant at the harness level (the new test files only exercise lootbox-path entry points; do not touch other modules).

**Five-line zero-attestation roll-up** (one phrase per line for grep-tally clarity):

- zero new storage slots — `git diff 06623edb..HEAD -- contracts/DegenerusGameStorage.sol` empty.
- zero new public/external mutation entry points — `git diff 06623edb..HEAD -- contracts/ | grep -E "^\+.*function .* (public|external)" | grep -v "view|pure"` returns 0.
- zero new admin functions — `git diff 06623edb..HEAD -- contracts/ | grep -E "^\+.*(onlyOwner|onlyAdmin)"` returns 0.
- zero new modifiers — `git diff 06623edb..HEAD -- contracts/ | grep -E "^\+.*modifier "` returns 0.
- zero new upgrade hooks — `git diff 06623edb..HEAD -- contracts/ | grep -E "^\+.*(UUPSUpgradeable|_authorizeUpgrade)"` returns 0.

**Closing attestation:** Storage layout byte-identical at v39.0 closure HEAD vs v38.0 baseline `06623edb` per slot-by-slot grep-proof; zero new public/external mutation entry points; zero new external pure entry points; zero new admin functions; zero new modifiers; zero new upgrade hooks; one new constant (compile-time inlined); one new event declaration (event log is calldata-equivalent, not a storage slot); zero new ERC-20 mint-route surfaces (one new callsite consuming the existing `IWrappedWrappedXRP.mintPrize` route). Cross-module byte-identity preserved for `JackpotModule + MintModule + Degenerette + TraitUtils + JackpotBucketLib + EntropyLib` (D-274-MANUAL-ONLY-01 narrowing satisfied — only `DegenerusGameLootboxModule.sol` + `IDegenerusGameModules.sol` modified at v39). `BurnieCoinflip.sol` carries Phase 273 mutations (included-since-baseline per D-274-BAF273-INCLUDE-01).

### 3.C AUDIT-03 Conservation Re-Proof

Conservation re-proof across 4 domains: EV-neutrality of the Bernoulli round-up on manual paths; WWXRP supply conservation on the consolation path; bit-slice `[152..167]` pairwise independence vs other primary-chunk consumers; `rem`-byte invariant under the manual-path retirement. Closes the AUDIT-03 design contract per ROADMAP success criterion + REQUIREMENTS.md.

**(1) EV-neutrality of Bernoulli round-up on manual paths:**

The Bernoulli round-up on the manual branch implements floor + biased-coin-flip on the fractional remainder. For a pre-collapse scaled value `scaledPre`, with `whole_floor = scaledPre / 100` and `frac = scaledPre % 100`:

`P(roundedUp = true) = frac / 100   (Bernoulli condition: bits[152..167] mod 100 < frac)`
`P(roundedUp = false) = (100 - frac) / 100`

Expected post-collapse whole value:

`E[whole_post] = whole_floor × P(roundedUp = false) + (whole_floor + 1) × P(roundedUp = true)`
`             = whole_floor × (100 - frac) / 100 + (whole_floor + 1) × frac / 100`
`             = whole_floor + frac / 100`

Since `scaledPre = whole_floor × 100 + frac` by construction, we have `whole_floor + frac / 100 = scaledPre / 100`. Therefore:

`E[whole_post] × 100 == scaledPre`     (exact identity)
`E[whole_post] == scaledPre / 100`     (exact in rationals)

EV-preserving by construction. Per-lootbox variance is higher than the v38 cross-lootbox-deterministic-accumulation flow (where fractional `rem` accumulates across multiple manual lootboxes targeting the same future level and resolves to whole tickets at activation time via `_rollRemainder`). The variance increase is the documented tradeoff per CONTEXT.md `<specifics>`. EV is identical. Empirical witness: TST-WT-01 at N=10K seeds across {47, 99, 100, 147, 250, 1000, 9999} confirms `mean(whole_post) × 100` within ±2.5 of `scaledPre` (5-sigma binomial bound).

**(2) WWXRP supply conservation on the consolation path:**

The cold-bust consolation magnitude `LOOTBOX_WWXRP_CONSOLATION = 1 ether` matches the regular 10%-path WWXRP win magnitude `LOOTBOX_WWXRP_PRIZE = 1 ether` (LBX-WX-01 + D-274-WX-AMOUNT-01). Both call the same `IWrappedWrappedXRP.mintPrize(player, amount)` interface; both emit `LootBoxWwxrpReward(player, day, amount, wwxrpAmount)` with the same event signature (LBX-WX-04). No new WWXRP supply route introduced.

Cold-bust trigger probability bound (worst-case for WWXRP supply growth):

`P(consolation per manual lootbox open) = P(ticket-path selected) × P(scaledPre ∈ (0, 100)) × P(Bernoulli fails | scaledPre ∈ (0, 100))`

The middle factor is bounded above by `P(scaledPre < 100)` which depends on the ETH-amount budget vs the level-priced ticket cost; the worst case is high-price small-budget lootboxes (sub-1-ticket-budget). For such lootboxes, `frac` is uniformly distributed in [1, 99] under the keccak entropy assumption, so `P(Bernoulli fails | scaledPre ∈ (0, 100)) = E[(100 - frac) / 100] = 50/100 = 0.5`. Combined with the existing `LOOTBOX_WWXRP_PRIZE` regular-path probability `P(WWXRP path selected) ≈ 10%` (existing 10%-bracket from the path roll at `_resolveLootboxRoll`), the worst-case consolation contribution to WWXRP supply is bounded above by `0.5 × P(ticket-path selected) × P(sub-1-ticket-budget) × N_open` per unit time — a fraction of the existing WWXRP supply trajectory (the 10%-path mint contribution dominates by an order of magnitude). No supply-shock risk; supply trajectory bounded.

Empirical witness: TST-WX-03 magnitude assertion `LOOTBOX_WWXRP_CONSOLATION == LOOTBOX_WWXRP_PRIZE == 1 ether` (defensive drift catch).

**(3) Bit-slice `[152..167]` pairwise independence vs other primary-chunk consumers:**

The per-resolution `seed = keccak256(abi.encode(rngWord, player, day, amount))` is a single 256-bit primary chunk with the following sub-slice allocation at v39 (post-edit NatSpec L883-893):

```
bits[0..15]    rangeRoll % 100         (_resolveLootboxRoll path discriminator)
bits[16..47]   pathRoll                (_resolveLootboxRoll near/far offset)
bits[48..63]   tierRoll % 1000         (_resolveLootboxRoll tier selection)
bits[64..79]   nearOffset              (_resolveLootboxRoll near-tier offset)
bits[80..95]   varianceRoll % 20       (_resolveLootboxRoll large-BURNIE)
bits[96..119]  ticketVariance % 10000  (_lootboxTicketCount)
bits[120..151] boon roll % BOON_PPM_SCALE (_rollLootboxBoons)
bits[152..167] fracRoundUp % 100       (_resolveLootboxCommon manual-path; v39 NEW)
```

Total primary-chunk consumption: 168 / 256 bits. Bits[168..255] (88 bits) remain unallocated for future use.

By keccak output-entropy properties (the keccak-256 hash function is a cryptographic random oracle in the ideal-cipher sense, and the inputs to the keccak preimage include the VRF-derived `rngWord` which is unknown at the player's commitment point per `feedback_rng_backward_trace.md`), the 256 output bits are pairwise independent. Any disjoint pair of bit-slices is pairwise independent. The new `bits[152..167]` slice does not overlap with any existing slice (the prior maximum was `bits[151]` from the `boon roll` slice). Therefore the new slice is pairwise independent of all 7 prior consumers.

Modulo-bias analysis: `uint16 % 100` over a uniform 16-bit input produces a distribution with worst-case relative bias `656/65536 vs 655.36/65536 = 0.10%` (the 16-bit space has `65536 = 655 × 100 + 36` so 36 residues have 656 preimages and 64 residues have 655 preimages). This is consistent with the existing `bits[0..15]` rangeRoll `uint16 % 100` precedent at L850-851. Per CONTEXT.md `<locked_decisions> D-274-BIT-SLICE-01`: an 8-bit width was rejected because `uint8 % 100` over uniform 8-bit input has worst-case relative bias `3/256 vs 2/256 = 17%` for `frac ≤ 56` (256 mod 100 = 56 residues with 3 preimages; 44 residues with 2 preimages), which would systematically over-issue rounded-up tickets when `frac ≤ 56`. The 16-bit form eliminates that drift.

Empirical witness: TST-WT-03 mod-100 chi² at N=10K with df=99 Wilson-Hilferty Z < 1.645 (PASS at α=0.05); pairwise covariance test between `bits[152..167]` and `bits[0..15]` bounded within ±0.01 of theoretical zero at N=10K.

**(4) `rem`-byte invariant under manual-path retirement:**

Manual-path queues no longer write to the `rem` byte of `ticketsOwedPacked[wk][player]` because the whole-helper `_queueTickets(player, targetLevel, whole, false)` at `contracts/DegenerusGameStorage.sol` L562-589 writes the whole-ticket count directly to the appropriate slot WITHOUT touching the low byte (the `rem` byte is owned by `_queueTicketsScaled` at L596 only). On manual-path opens, the post-Bernoulli `whole` value is queued atomically; no fractional residue persists across activation.

Mint-boost path (at `DegenerusGameMintModule.sol` L1142 `_queueTicketsScaled` callsite) and auto-resolve lootbox paths (at L1067 in `_resolveLootboxCommon`'s auto-resolve branch) continue producing `rem` byte residues; activation-time `_rollRemainder` continues to function unchanged. TST-REG-01 confirms manual-only player+level queues no longer enter `_rollRemainder` at activation; TST-REG-02 confirms mint-boost still produces and resolves `rem`; TST-REG-03 confirms auto-resolve still produces and resolves `rem`; TST-REG-04 confirms cross-mixing variance posture (manual contributions are per-lootbox Bernoulli; auto-resolve contributions still pool deterministically).

**Closing conservation attestation:** EV-neutrality of the Bernoulli round-up holds `E[whole_post] = scaledPre / 100` exactly (per-lootbox variance higher than cross-lootbox-deterministic-accumulation is the documented tradeoff). WWXRP supply growth from the consolation path is bounded above by a fraction of the existing 10%-path WWXRP supply trajectory; same magnitude (`1 ether`) as the regular 10%-path WWXRP win; no new mint-route surface. Bit-slice `[152..167]` is pairwise independent of the 7 prior primary-chunk consumers by keccak output-entropy properties; mod-100 relative bias bounded at ≤0.10% (consistent with the existing `bits[0..15]` precedent). `rem` byte invariant: manual-path queues no longer write to `rem`; mint-boost + auto-resolve lootbox paths continue producing `rem` and resolving via `_rollRemainder` at activation.

