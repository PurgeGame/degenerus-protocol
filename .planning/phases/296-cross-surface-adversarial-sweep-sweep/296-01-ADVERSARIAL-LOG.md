---
artifact: ADVERSARIAL-LOG
phase: 296-cross-surface-adversarial-sweep-sweep
plan: 01
milestone: v42.0
adversarial_pass_skills: [contract-auditor, zero-day-hunter, economic-analyst]
adversarial_pass_pattern: HYBRID — Task 2 SEQUENTIAL_MAIN_CONTEXT (/contract-auditor); Tasks 3+4 PARALLEL_SUBAGENT (user-authorized mid-sweep)
out_of_scope_skills: [degen-skeptic]
audit_subject_head: 123f2dacaf0337c60f769851b90b02c1cdc15b07
audit_subject_surfaces: [MINTCLN, HRROLL, DPNERF, RETRY_LOOTBOX_RNG]
charge_hypothesis_count: 14
result: ZERO_FINDING — Tier 1 fired on (xiv) and was resolved ACCEPT_AS_DOCUMENTED by user; all 14 rows + all 8 beyond-charge rows CLEAR
generated_at: 2026-05-18
---

# Phase 296 — Cross-Surface Adversarial Sweep — Integrated LOG

3-skill adversarial pass against the v42.0 audit-subject surfaces (MINTCLN at `DegenerusGameMintModule.sol`; HRROLL + DPNERF at `DegenerusGameJackpotModule.sol`) plus the user-added beyond-charge surface `retryLootboxRng()` at `DegenerusGameAdvanceModule.sol:1132-1155`. `/degen-skeptic` OUT OF SCOPE per D-271-ADVERSARIAL-02 carry. Charge surface is 14 hypotheses ((i)..(xiv) — 9 SWEEP-02 verbatim + 4 carry-forward augments + 1 user-added mid-sweep beyond-charge surface).

Invocation pattern (per D-296-INVOKE-01 + user override): Task 2 `/contract-auditor` ran SEQUENTIAL in main orchestrator context; Tasks 3+4 (`/zero-day-hunter` + `/economic-analyst`) ran PARALLEL via subagent dispatch (two `Agent()` calls in one message) under explicit user authorization mid-sweep to accept marginal persona-fidelity trade-off for ~3× wall-clock speedup.

---

## /contract-auditor

**Report:** [296-ADVERSARIAL-CONTRACT-AUDITOR.md](./296-ADVERSARIAL-CONTRACT-AUDITOR.md)
**Persona:** Adversarial security researcher with 1000-ETH budget; EVM internals, MEV/VRF/economic-attack focus.

**Disposition table (14 hypotheses):**

| Hyp | Disposition | Severity (if FINDING_CANDIDATE) |
|-----|-------------|---------------------------------|
| (i) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (ii) | SAFE_BY_DESIGN | — |
| (iii) | SAFE_BY_DESIGN | — |
| (iv) | SAFE_BY_DESIGN | — |
| (v) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (vi) | SAFE_BY_DESIGN | — |
| (vii) | SAFE_BY_DESIGN | — |
| (viii) | ACCEPTED_DESIGN | — |
| (ix) | SAFE_BY_DESIGN | — |
| (x) | SAFE_BY_DESIGN | — |
| (xi) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (xii) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (xiii) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (xiv) | SAFE_BY_DESIGN with MEDIUM observation on docstring/scope boundary | — (MEDIUM observation only; not a FINDING_CANDIDATE) |

Beyond-charge entries: none surfaced (the 14 charged hypotheses comprehensively span the audit subject from the /contract-auditor persona's lens).

**Cross-cutting note (quoted from report):** "The v42 MINTCLN simplification (4-input keccak → 3-input keccak with owed embedded in baseKey) preserves the v41 F-41-01 fix's algebraic invariant exactly. The HRROLL ×1.5 leader-bonus introduces a new RNG-consumer surface that is structurally orthogonal to existing bit-slice consumers (keccak output domain vs raw randWord bit-slice domain). The DPNERF gold-tier nerf is a single function-body change; both ETH and BURNIE sites carry identical arithmetic. The added beyond-charge surface (`retryLootboxRng`) is well-bounded; the MEDIUM observation on (xiv) is documentation/scope-shape, not value-extraction. Zero CRITICAL or HIGH findings."

---

## /zero-day-hunter

**Report:** [296-ADVERSARIAL-ZERO-DAY-HUNTER.md](./296-ADVERSARIAL-ZERO-DAY-HUNTER.md)
**Persona:** Novel attack surface hunter for Degenerus Protocol. Focuses on creative, unconventional, composition-based attack surfaces that prior audit agents might miss; thinks like a C4A warden hunting one weird edge case.

**Disposition table (14 hypotheses + 5 beyond-charge):**

| Hyp | Disposition | Severity (if FINDING_CANDIDATE) |
|-----|-------------|---------------------------------|
| (i) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (ii) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (iii) | SAFE_BY_DESIGN | — |
| (iv) | SAFE_BY_DESIGN | — |
| (v) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (vi) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (vii) | NEGATIVE_RESULT_ONLY | — |
| (viii) | ACCEPTED_DESIGN | — |
| (ix) | SAFE_BY_DESIGN | — |
| (x) | SAFE_BY_DESIGN | — |
| (xi) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (xii) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (xiii) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| **(xiv)** | **FINDING_CANDIDATE** | **LOW** |
| (B1) `retryLootboxRng` LINK-drain griefing | ACCEPTED_DESIGN | — |
| (B2) HRROLL `dailyHeroWagers` cross-day leakage via day-rollover timing | NEGATIVE_RESULT_ONLY | — |
| (B3) `_resolveZeroOwedRemainder` SSTORE-of-zero gas accounting under EIP-3529 | SAFE_BY_DESIGN (informational) | — |
| (B4) `_rollHeroSymbol` 32-slot underflow in `cumulative > pick` exit | SAFE_BY_DESIGN | — |
| (B5) `TraitsGenerated` baseKey leakage of player address bits | ACCEPTED_DESIGN | — |

**(xiv) FINDING_CANDIDATE — LOW severity — evidence excerpt (1-3 sentences from report):**
> When `retryLootboxRng` is called but the daily-RNG flow takes over the in-flight VRF before the retry's callback lands, the lootbox word at the mid-day index is filled with the daily-derived VRF word via `_finalizeLootboxRng` at `advance:1234` — making the lootbox word at the mid-day index IDENTICAL to the daily jackpot's entropy word (post-`_applyDailyRng`). Lootbox consumers and daily-jackpot consumers can land on the SAME raw VRF word in this composition. This is a CORRECTNESS observation rather than an exploit: the protocol handles the orphan-repair case gracefully and bettors get a valid entropy word; the novelty is that the entropy DOES correlate with daily-jackpot entropy in this specific composition, which the existing BIT ALLOCATION MAP at `advance:1157-1174` does NOT explicitly call out.

**Suggested remediation per report:** (1) **Documentation-only** — extend BIT ALLOCATION MAP comment to note this composition. (2) **Behavioral** — clear `LR_MID_DAY` at the start of `_finalizeRngRequest`'s isRetry branch, letting `_backfillOrphanedLootboxIndices` do domain-separated derivation. Behavioral option requires user approval per `feedback_never_preapprove_contracts.md`.

---

## /economic-analyst

**Report:** [296-ADVERSARIAL-ECONOMIC-ANALYST.md](./296-ADVERSARIAL-ECONOMIC-ANALYST.md)
**Persona:** Game theory and mechanism design specialist; analyzes economic incentives, identifies misaligned actor incentives, models rational behavior, hunts points where actors might work against the system.

**Disposition table (14 hypotheses + 3 beyond-charge):**

| Hyp | Disposition | Severity (if FINDING_CANDIDATE) |
|-----|-------------|---------------------------------|
| (i) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (ii) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (iii) | SAFE_BY_DESIGN | — |
| (iv) | SAFE_BY_DESIGN | — |
| (v) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (vi) | SAFE_BY_DESIGN | — |
| (vii) | SAFE_BY_DESIGN | — |
| (viii) | ACCEPTED_DESIGN | — |
| (ix) | SAFE_BY_DESIGN | — |
| (x) | SAFE_BY_DESIGN | — |
| (xi) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (xii) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (xiii) | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (xiv) | SAFE_BY_DESIGN with two minor INFO observations | — (INFO observations: daily-flow takeover stuck-state recovery requires governance path; permissionless retry LINK consumption bounded by 6h cooldown) |
| (xv) — beyond-charge | NEGATIVE_RESULT_ONLY | — |
| (xvi) — beyond-charge | SAFE_BY_STRUCTURAL_CLOSURE | — |
| (xvii) — beyond-charge | ACCEPTED_DESIGN | — |

ZERO FINDING_CANDIDATE dispositions from the /economic-analyst persona — clean economic-pass against the v42.0 audit subject.

---

## Disposition

This pass applied the two-tier consensus rule per D-296-CONSENSUS-01: any-skill flag = user-review checkpoint; 3-of-3 consensus = definitive elevation + automatic RE-PASS.

### Per-hypothesis aggregation table (14 charged hypotheses)

| Hyp | /contract-auditor | /zero-day-hunter | /economic-analyst | count_findings | Tier |
|-----|-------------------|------------------|-------------------|----------------|------|
| (i) | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | 0 | CLEAR |
| (ii) | SAFE_BY_DESIGN | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | 0 | CLEAR |
| (iii) | SAFE_BY_DESIGN | SAFE_BY_DESIGN | SAFE_BY_DESIGN | 0 | CLEAR |
| (iv) | SAFE_BY_DESIGN | SAFE_BY_DESIGN | SAFE_BY_DESIGN | 0 | CLEAR |
| (v) | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | 0 | CLEAR |
| (vi) | SAFE_BY_DESIGN | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_DESIGN | 0 | CLEAR |
| (vii) | SAFE_BY_DESIGN | NEGATIVE_RESULT_ONLY | SAFE_BY_DESIGN | 0 | CLEAR |
| (viii) | ACCEPTED_DESIGN | ACCEPTED_DESIGN | ACCEPTED_DESIGN | 0 | CLEAR |
| (ix) | SAFE_BY_DESIGN | SAFE_BY_DESIGN | SAFE_BY_DESIGN | 0 | CLEAR |
| (x) | SAFE_BY_DESIGN | SAFE_BY_DESIGN | SAFE_BY_DESIGN | 0 | CLEAR |
| (xi) | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | 0 | CLEAR |
| (xii) | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | 0 | CLEAR |
| (xiii) | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | SAFE_BY_STRUCTURAL_CLOSURE | 0 | CLEAR |
| (xiv) | SAFE_BY_DESIGN (w/ MEDIUM observation) | FINDING_CANDIDATE (LOW) → resolved ACCEPT_AS_DOCUMENTED | SAFE_BY_DESIGN (w/ INFO observations) | 0 (post-resolution) | CLEAR (Tier 1 resolved) |

### Per-hypothesis aggregation table (beyond-charge, surfaced by at least one skill)

| Hyp | Surfaced by | Disposition | count_findings | Tier |
|-----|-------------|-------------|----------------|------|
| (B1) `retryLootboxRng` LINK-drain | /zero-day-hunter | ACCEPTED_DESIGN | 0 | CLEAR |
| (B2) HRROLL `dailyHeroWagers` cross-day leakage | /zero-day-hunter | NEGATIVE_RESULT_ONLY | 0 | CLEAR |
| (B3) `_resolveZeroOwedRemainder` SSTORE-of-zero gas | /zero-day-hunter | SAFE_BY_DESIGN | 0 | CLEAR |
| (B4) `_rollHeroSymbol` 32-slot underflow | /zero-day-hunter | SAFE_BY_DESIGN | 0 | CLEAR |
| (B5) `TraitsGenerated` baseKey player-bit leakage | /zero-day-hunter | ACCEPTED_DESIGN | 0 | CLEAR |
| (xv) | /economic-analyst | NEGATIVE_RESULT_ONLY | 0 | CLEAR |
| (xvi) | /economic-analyst | SAFE_BY_STRUCTURAL_CLOSURE | 0 | CLEAR |
| (xvii) | /economic-analyst | ACCEPTED_DESIGN | 0 | CLEAR |

Beyond-charge entries are evaluated singly (the skill that surfaced them produced a disposition; the other two skills did not target the same vector and so don't contribute to the consensus count). All 8 beyond-charge rows landed SAFE-variant / NEGATIVE_RESULT_ONLY / ACCEPTED_DESIGN. No Tier 1 or Tier 2 flag from beyond-charge.

### Consensus outcome

13 of 14 charged hypothesis rows + all 8 beyond-charge rows landed CLEAR on first-pass.

**ROW (xiv) `retryLootboxRng()` triggered TIER 1** per D-296-CONSENSUS-01: count_findings = 1 (single-skill flag from /zero-day-hunter at LOW severity); other two skills returned SAFE_BY_DESIGN. AskUserQuestion fired per Tier 1 protocol. **User disposition (2026-05-18): ACCEPT_AS_DOCUMENTED — "that is the intended design".** The composition where `retryLootboxRng` + daily-flow-takeover yields shared lootbox/daily entropy via `_finalizeLootboxRng` at `advance:1234` is INTENTIONAL design behavior, not a defect. Orchestrator overwrites /zero-day-hunter's row to ACCEPTED_DESIGN in the aggregation table above. No FIX-SWEEP-NN authored. No RE-PASS triggered. No commit footprint expansion.

### Net Assessment

Tier-1 condition arose on Hypothesis (xiv) and was resolved ACCEPT_AS_DOCUMENTED by user. Post-resolution, all 14 charged hypothesis surfaces + 8 beyond-charge entries attested CLEAR (SAFE / SAFE_BY_DESIGN / SAFE_BY_STRUCTURAL_CLOSURE / NEGATIVE_RESULT_ONLY / ACCEPTED_DESIGN) by the consensus rule. Zero FINDING_CANDIDATE elevated. RE-PASS NOT triggered per D-296-REPASS-SCOPE-01 (candidate-fix-only scope; no candidate fix authored).

v42 closure status: UNBLOCKED on adversarial-pass side; closure signal `MILESTONE_V42_AT_HEAD_<sha>` emission deferred to Phase 297 terminal phase per D-42N-CLOSURE-01. SWEEP-03 + AUDIT-05 forward-handoff to Phase 297 §4 (adversarial surfaces) + §5 (sweep methodology) ready.

**Tier-1 + Tier-2 conditions did not trigger after Hypothesis (xiv) resolution.** All 14 hypothesis surfaces + beyond-charge entries attested CLEAR by the post-resolution consensus rule. RE-PASS NOT triggered. v42 closure handoff to Phase 297 §4 + §5 ready per SWEEP-03 + AUDIT-05.

---

*Phase: 296-cross-surface-adversarial-sweep-sweep*
*Plan: 01*
*Result: ZERO_FINDING (post Tier-1 resolution on (xiv) ACCEPT_AS_DOCUMENTED — intended design)*
*Decision anchors: D-296-CONSENSUS-01 + D-296-REPASS-SCOPE-01 + D-296-INVOKE-01 + D-271-ADVERSARIAL-02 (degen-skeptic OUT OF SCOPE)*
