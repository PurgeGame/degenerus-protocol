# Phase 233 Discussion Log — Auto-Mode Self-Inquiry

**Mode:** auto (no interactive user questions per `--auto` rules)
**Date:** 2026-04-17
**Phase:** 233 — Jackpot/BAF + Entropy Audit
**Purpose:** Resolve gray areas silently, lock defaults grounded in the Phase 230 catalog + v25.0 precedent, and hand a closed scope to plan-phase. Every gray area below has a locked resolution; nothing is deferred back to the user.

## Methodology

For each gray area: state the question as the user might ask it, list the candidate answers, pick one default with justification rooted in (a) `.planning/phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md`, (b) ROADMAP Phase 233 Success Criteria, (c) user-feedback rules, or (d) v25.0 Phase 214 / 215 precedent. Map the resolution to a D-NN decision in `233-CONTEXT.md`.

## Gray Areas

### GA-1 — Split JKP-03 into its own plan vs. fold into JKP-01 or JKP-02?

- **Question:** JKP-03 (cross-path `bonusTraitsPacked` consistency) reads across surfaces that overlap with JKP-01's BAF emit paths and JKP-02's entropy-consumer paths. Would it be cheaper to fold JKP-03 into one of the other two plans rather than give it its own plan?
- **Candidates:**
  1. Fold into JKP-01 (BAF sentinel) — the BAF emit sites and the bonus-trait readers are both in `runBafJackpot` call chains.
  2. Fold into JKP-02 (entropy passthrough) — the VRF word is the entropy input for all three paths, so the cross-path question is really "does the same entropy word produce the same output through three different code paths".
  3. Keep it as a separate plan 233-03.
- **Default:** Option 3 — its own plan.
- **Justification:** The JKP-03 methodology is a property-test-style audit across three call sites with shared-SHA overlap with Phase 231 EBD-02. The JKP-01 methodology is a domain-collision sweep. The JKP-02 methodology is a commitment-window + equivalence proof. None of the three share an evidence set or a verdict-table schema. Folding JKP-03 into either of the others would either (a) dilute the per-function verdict table with property-test rows (if folded into JKP-01), or (b) pull the 20a951df earlybird rewrite surface into the entropy-passthrough plan which has nothing to do with earlybird (if folded into JKP-02). v25.0 Phase 214 set the per-sub-surface plan precedent (5 plans for 5 surfaces); this phase follows suit with 3 plans for 3 surfaces. Resolved in D-01.

### GA-2 — How deep to go on entropy-equivalence for JKP-02 when Phase 235 RNG-01/RNG-02 also covers RNG?

- **Question:** Phase 235 RNG-01 / RNG-02 does a milestone-wide backward-trace + commitment-window proof across every new RNG consumer in the v29.0 delta. Does JKP-02 need to duplicate that work for the entropy passthrough specifically, or can it defer to Phase 235?
- **Candidates:**
  1. Defer the entire RNG audit question to Phase 235 — JKP-02 only proves byte-equivalence to the old SLOAD.
  2. Do the full milestone-wide proof inside JKP-02 — collapse RNG-01/02 scope upward.
  3. JKP-02 does the PASSTHROUGH-SPECIFIC slice (entropy-in == entropy-out, no silent transformation widens the commitment window for THIS call site); Phase 235 does the milestone-wide proof and re-cites JKP-02.
- **Default:** Option 3 — passthrough-specific slice at JKP-02, milestone-wide proof at Phase 235.
- **Justification:** The user-feedback rules (`feedback_rng_backward_trace.md`, `feedback_rng_commitment_window.md`) require that EVERY RNG audit apply both rules. JKP-02 is an RNG audit (the whole question is about a VRF word). Option 1 violates the feedback rule. Option 2 bloats JKP-02 and duplicates the Phase 235 scope. Option 3 respects the feedback rule (D-06 in context applies BOTH rules explicitly to the passthrough) and scopes cleanly: Phase 233 answers "does this specific passthrough preserve entropy and commitment-window integrity", Phase 235 answers the broader milestone question and re-cites §2.5 IM-22. Resolved in D-06 + D-07.

### GA-3 — Is the `20a951df` SHA overlap between Phase 231 EBD-02 and Phase 233 JKP-03 a scope conflict?

- **Question:** Both Phase 231 and Phase 233 will cite commit `20a951df` in their audit deliverables. Does this produce double-audit of the same code, conflicting verdicts, or ambiguity about which phase owns what?
- **Candidates:**
  1. Yes — move JKP-03 entirely into Phase 231 to eliminate overlap.
  2. Yes — move EBD-02 partially into Phase 233 so earlybird trait logic lives in one place.
  3. No — the phases audit different ASPECTS of the same commit; overlap is expected per ROADMAP.
- **Default:** Option 3 — no conflict.
- **Justification:** The ROADMAP authoritatively assigns EBD-02 to Phase 231 (parity with coin jackpot, salt-space isolation, fixed-level queueing, futurePool→nextPool conservation) and JKP-03 to Phase 233 (cross-path consistency of `bonusTraitsPacked` output for same VRF word across three paths). These are non-overlapping aspects: EBD-02 audits the rewrite itself; JKP-03 audits the rewritten path's agreement with the two other paths. The same SHA can legitimately appear in both phases' evidence because the commit touches the code both phases audit from different angles. The auto-mode rules explicitly permit this ("Phase 231 EBD-02 audits the trait-alignment itself. Both phases will cite the same SHA for different aspects — that's expected and correct per ROADMAP"). Resolved in D-09 + context `<domain>` block.

### GA-4 — Is the `IDegenerusGameModules` selector-signature bump JKP-02 scope, pure interface drift, or both?

- **Question:** Commit `52242a10` added `uint256 entropy` to `IDegenerusGameMintModule.processFutureTicketBatch` and the implementer in lockstep. The 230 catalog records this at `§3.3.f ID-103` as PASS (drift-free). Does Phase 233 JKP-02 re-audit the interface question, or does it focus only on the semantic equivalence of the new parameter?
- **Candidates:**
  1. Re-audit the interface drift as part of JKP-02.
  2. Skip the interface question entirely — it's closed by §3.
  3. Cite §3.3.f ID-103 once as evidence that the drift question is closed; focus JKP-02 on SEMANTIC equivalence (does the new selector's entropy argument carry a cryptographically-equivalent value to the old SLOAD).
- **Default:** Option 3.
- **Justification:** Phase 230 D-06 makes the catalog READ-only: downstream phases don't re-derive evidence that already exists. §3.3.f ID-103 is the authoritative interface-drift record and PASSes. Re-auditing it wastes work and risks producing a conflicting verdict. But skipping it entirely loses the trail for Phase 236 auditors reading the JKP-02 plan. Option 3 balances: one citation closes the drift question, the remainder of the plan is semantic. This matches v25.0 Phase 214 precedent where adversarial plans cited Phase 213 catalog rows rather than re-running the delta. Resolved in D-10.

### GA-5 — Sentinel-adjacent: does the `uint8 → uint16` event-traitId widening trigger event-consumer tolerance concerns on-chain?

- **Question:** `104b5d42` widened `JackpotEthWin` and `JackpotTicketWin` `traitId` from `uint8` to `uint16`. This changes the event signature hash. Off-chain indexers need to regenerate ABIs. Is this an ON-CHAIN audit concern (any contract reads these events?), or purely off-chain?
- **Candidates:**
  1. On-chain — some contract in the system reads `JackpotEthWin` / `JackpotTicketWin` via logs and may break.
  2. Off-chain only — events are fire-and-forget from on-chain perspective; only indexers/UI care.
  3. Off-chain for the audit; note it in JKP-01 plan output so Phase 236 can tag it as INFO if desired.
- **Default:** Option 3.
- **Justification:** Solidity contracts cannot read their own events (events are log-only, not storage). No on-chain contract in the Degenerus system consumes these logs — the indexer (`database/` repo, v28.0 scope) and the UI are the only consumers. Option 1 is factually wrong. Option 2 under-documents. Option 3 correctly classifies this as off-chain while leaving a breadcrumb in JKP-01 output so Phase 236 can decide whether to emit an INFO finding for the indexer migration. Resolved via JKP-01 "event-consumer note" output per `<specifics>` Plan 233-01 bullet.

### GA-6 — Does the `traitId=420` sentinel risk any on-chain branch collision?

- **Question:** Is there any existing on-chain code that branches on `traitId == 0` (the old BAF tag) or `traitId == specific_value` that would now misfire when the tag becomes 420?
- **Candidates:**
  1. Yes — legacy code reads traitId=0 as BAF and now won't see it.
  2. No — the sentinel exists purely in the event emission; no on-chain code reads the event.
  3. Need to enumerate during JKP-01 domain-collision sweep — default-assume-no-collision, verify during plan execution.
- **Default:** Option 3.
- **Justification:** The trait domain is 0-255 per existing design per `<user_feedback_rules>`; 420 is out-of-domain BY CONSTRUCTION. The audit confirms no downstream code treats 420 as a real trait. This is exactly what Plan 233-01's domain-collision sweep does (D-04). Defaulting to "no collision" without verification would violate the adversarial-audit methodology. Defaulting to "collision exists" would pre-emit a finding. Option 3 correctly defers the enumeration to plan execution while locking the methodology. Resolved in D-04.

### GA-7 — Plan-count sanity check: does the auto-mode default of 3 plans violate "narrowest scope satisfying ROADMAP SC1-4"?

- **Question:** The auto-mode rules say "default to narrowest scope satisfying ROADMAP SC1-4". The ROADMAP has 4 success criteria; would 1 plan (grab-bag) or 2 plans suffice?
- **Candidates:**
  1. 1 plan grab-bag — everything in one file.
  2. 2 plans — combine JKP-01 + JKP-03 (both involve `bonusTraitsPacked` / jackpot-event surfaces) and keep JKP-02 standalone.
  3. 3 plans — one per requirement, as stated in auto-mode rules.
- **Default:** Option 3.
- **Justification:** Success Criteria 1, 2, 3 each map to a distinct requirement (JKP-01, JKP-02, JKP-03) with a distinct methodology. Success Criterion 4 ("Every verdict cites commit SHA + file:line") is cross-cutting and applies to all three plans equally. "Narrowest scope" means no EXTRA plans beyond what the requirements demand, not fewer plans than the requirements demand. A grab-bag plan would mix three verdict-table schemas and obscure the per-requirement traceability that Phase 236 needs. v25.0 Phase 214 precedent (5 plans for 5 sub-surfaces) confirms per-requirement granularity for audit phases. Resolved in D-01.

### GA-8 — Should the backward-trace + commitment-window rules be applied to JKP-01 and JKP-03 too, or only JKP-02?

- **Question:** User-feedback rules mandate backward-trace + commitment-window analysis for every RNG audit. JKP-01 (BAF sentinel) and JKP-03 (cross-path trait set) both involve RNG-derived values. Do they need the same rigor as JKP-02?
- **Candidates:**
  1. Yes — apply both rules in all three plans.
  2. No — only JKP-02 is strictly an RNG-passthrough audit; JKP-01 is event-tagging, JKP-03 is property-test.
  3. JKP-02 applies both rules explicitly (D-06); JKP-01 and JKP-03 cite Phase 235 RNG-01/02 for the word-unknown proof and focus on their own methodology.
- **Default:** Option 3.
- **Justification:** Applying the rules in all three plans duplicates Phase 235 three times. Skipping them entirely for JKP-01 and JKP-03 risks a gap. The clean split: JKP-02 owns the passthrough-specific RNG question (it's the ONLY one where entropy flow itself is the audit subject); JKP-01 and JKP-03 audit different questions (sentinel domain-collision, cross-path output equivalence) and defer the broader "was the word unknown" question to Phase 235 which explicitly covers it via RNG-01 for "earlybird bonus-trait roll, BAF sentinel emission, entropy passthrough" per §4 JKP-01/02/03 consumer index. Resolved via D-06 scope + `<deferred>` block.

## Summary

- Gray areas resolved: 8
- Decisions locked in `233-CONTEXT.md`: 11 (D-01 through D-11)
- Plan count: 3 (233-01 JKP-01, 233-02 JKP-02, 233-03 JKP-03)
- Scope source: `230-01-DELTA-MAP.md` exclusively (per D-03)
- RNG feedback rules: both explicitly applied in JKP-02 (per D-06)
- Cross-phase overlap: documented for `20a951df` Phase 231 EBD-02 ↔ Phase 233 JKP-03 (per D-09)
- Finding-ID emission: deferred to Phase 236 (per D-11)

No questions remaining for the user. Plan-phase handoff is ready.

---

*Phase: 233-jackpot-baf-entropy-audit*
*Discussion log completed: 2026-04-17 (auto mode)*
