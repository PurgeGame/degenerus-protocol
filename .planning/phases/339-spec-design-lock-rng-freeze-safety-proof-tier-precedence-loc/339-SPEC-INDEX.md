# Phase 339 — SPEC Index + Multi-Source Coverage Audit (BATCH-01 closure)

**Authored:** 2026-05-28
**Plan:** 339-04 (SPEC — Wave-2 integration / closure)
**Requirement:** BATCH-01 (the navigation + multi-source coverage closure that ties the Phase-339 SPEC together)
**Audit baseline:** v50.0 closure HEAD `812abeee2719c32d6973771ad2a66187fae75b80` (the minimal-close commit; no formal `MILESTONE_V50_AT_HEAD` signal was emitted) — `git diff 812abeee HEAD -- contracts/` is EMPTY (the only commits since `812abeee` are v51 planning docs).
**Verdict:** **ALL items COVERED, 0 MISSING.**

> This is the navigation + closure doc for the Phase-339 SPEC. It maps the six Phase-339 artifacts (the outputs of plans 339-01 / 339-02 / 339-03) to the five ROADMAP Phase-339 Success Criteria + the two phase requirements (BATCH-01, BINGO-06), and runs a multi-source coverage audit (GOAL / REQ / RESEARCH / CONTEXT) confirming every source item is COVERED with no silent scope reduction (the `scope_reduction_prohibition` floor). It cites the artifact filenames; it does NOT re-derive their content. Mirrors the v50.0 Phase-334 SPEC-INDEX precedent.

---

## 1. The six Phase-339 SPEC artifacts (the deliverable set)

| # | Artifact | Plan | Slice / SC | One-liner |
|---|----------|------|-----------|-----------|
| A1 | `339-BINGO06-FREEZE-PROOF.md` | 339-01 | SC2 | BINGO-06 RNG-freeze proof via a structured 3-class per-slot enumeration (D-04) — VERDICT **FREEZE-SAFE** (no `claimBingo` slot is a current-VRF-window output during `rngLock`); `v45-vrf-freeze-invariant` re-attested by name; race-start locked. |
| A2 | `339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md` | 339-01 | SC2 | The `traitBurnTicket` write-site IFF soundness theorem (D-02, sub-claims a/b/c) — VERDICT **SOUND** (`claimBingo` cannot be spoofed) + the D-03 whale-race ACCEPTED-BY-DESIGN non-finding. |
| A3 | `339-DESIGN-LOCK-BINGO.md` | 339-02 | SC1 | The settled `claimBingo` signature + `uint32` slot-width disposition + three-mapping storage shape (`uint24` key) + `traitId` derivation + module placement / delegatecall wiring + six reward constants verbatim + reward paths / dedup / no-op / cutoff. |
| A4 | `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md` | 339-02 | SC3 | The binding IMPL acceptance contract — `isQuadrantFirst` checked BEFORE `isSymbolFirst`, three-branch acceptance table, both-bits-marking on a quadrant-first, the suppression-is-also-a-bit-set double-pay-trap invariant. |
| A5 | `339-REBAL-JACK-ATTESTATION.md` | 339-03 | SC4 | The REBAL complete pool-BPS-set sums-to-10000 invariant (before + after the net-zero swap, supply unchanged, Pool.Reward 50B→100B) + the JACK final-day deletion clean-orphan + preserved-plumbing attestation. |
| A6 | `339-GREP-ATTESTATION-EDIT-ORDER.md` | 339-03 | SC5 | The empty-diff shortcut + a 22-anchor per-anchor grep table vs `812abeee` with drift corrections + the 4-step producer-before-consumer edit-order map binding for BATCH-02 at Phase 340. |

---

## 2. Artifact → Success-Criterion table

The five ROADMAP Phase-339 Success Criteria (the SPEC's acceptance contract), each mapped to the artifact(s) that satisfy it:

| Success Criterion (ROADMAP Phase 339) | Covering artifact(s) | Status |
|----------------------------------------|----------------------|--------|
| **SC1** — full bundle design settled in writing (`claimBingo` signature / module placement / storage shape / `uint32` slot-type width / reward constants reconciled, no intermediate broken state) | `339-DESIGN-LOCK-BINGO.md` (A3) | COVERED |
| **SC2** — BINGO-06 RNG-freeze safety PROVEN not assumed (per-slot enumeration; read-only of post-resolution `traitBurnTicket`; populated-only-after-level-L invariant; v45 re-attest; race-start locked) | `339-BINGO06-FREEZE-PROOF.md` (A1, the freeze proof) + `339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md` (A2, the D-02 soundness IFF the freeze proof's populated-only-after-resolution claim rests on, + the D-03 non-finding) | COVERED |
| **SC3** — tier-precedence rule design-locked (quadrant-first-before-symbol-first; both-bits-marking; suppression) as the IMPL acceptance contract | `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md` (A4) | COVERED |
| **SC4** — REBAL BPS-sum invariant (sum to 10000, supply unchanged) + JACK final-day deletion side-effects (clean orphan + preserved plumbing) attested | `339-REBAL-JACK-ATTESTATION.md` (A5) | COVERED |
| **SC5** — every cited `file:line` grep-attested vs `812abeee` + producer-before-consumer edit-order map | `339-GREP-ATTESTATION-EDIT-ORDER.md` (A6) | COVERED |

All five Success Criteria are COVERED by a delivered artifact: **SC1→A3, SC2→A1+A2, SC3→A4, SC4→A5, SC5→A6.**

---

## 3. Requirement → Artifact table

The two Phase-339 requirements (REQUIREMENTS.md / ROADMAP Phase 339 — `BATCH-01, BINGO-06`):

| Requirement | Description (abbrev.) | Covering artifact(s) | Plan(s) | Status |
|-------------|------------------------|----------------------|---------|--------|
| **BATCH-01** | SPEC design-lock — settle module placement / storage shape / slot width / reward constants / signature; resolve all 7 "Open before SPEC" items; grep-attest every `file:line` vs `812abeee` (cross-cutting) | `339-DESIGN-LOCK-BINGO.md` (A3) + `339-TIER-PRECEDENCE-ACCEPTANCE-CONTRACT.md` (A4) + `339-REBAL-JACK-ATTESTATION.md` (A5) + `339-GREP-ATTESTATION-EDIT-ORDER.md` (A6); plus the design-lock half of A2 (the D-03 whale-race written disposition feeds the SPEC's audit posture) | 339-02, 339-03 | COVERED |
| **BINGO-06** | RNG-freeze safety PROVEN, not assumed — `claimBingo` reads only post-resolution `traitBurnTicket`, writes only its own bitfields, touches no current-VRF-window output during `rngLock` | `339-BINGO06-FREEZE-PROOF.md` (A1, the freeze proof) — the `339-TRAITBURNTICKET-SOUNDNESS-ATTESTATION.md` (A2) soundness IFF SUPPORTS it (the populated-only-after-resolution invariant) | 339-01 | COVERED |

**Note:** BATCH-01 is the **cross-cutting design-lock requirement** — it spans the BINGO design-lock (A3), the tier-precedence acceptance contract (A4), the REBAL/JACK attestation (A5), and the grep-attestation + edit-order map (A6). BINGO-06 is the **single-artifact freeze-proof requirement** (A1), with A2's write-site soundness as its load-bearing support. (Per the plan 339-01 / 339-02 / 339-03 SUMMARY frontmatter: 339-01 `requirements-completed: [BINGO-06]`; 339-02 and 339-03 `requirements-completed: [BATCH-01]` — so BATCH-01 is carried by the plans 02/03 frontmatter and BINGO-06 by plan 01.)

---

## 4. Multi-Source Coverage Audit

The four source types every plan-phase must cover. Each item is mapped to a plan + artifact and marked COVERED.

### 4a. GOAL — the Phase-339 ROADMAP goal (the 5 Success Criteria)

The ROADMAP Phase-339 goal decomposes into exactly the 5 Success Criteria, each mapped in §2 above:

| GOAL item | Covered by | Status |
|-----------|-----------|--------|
| SC1 (full bundle design settled, no intermediate broken state) | A3 | COVERED |
| SC2 (BINGO-06 RNG-freeze safety PROVEN) | A1 + A2 | COVERED |
| SC3 (tier-precedence design-locked as the acceptance contract) | A4 | COVERED |
| SC4 (REBAL BPS-sum invariant + JACK final-day deletion side-effects) | A5 | COVERED |
| SC5 (grep-attestation vs `812abeee` + edit-order map) | A6 | COVERED |

GOAL: **5/5 COVERED.**

### 4b. REQ — the Phase-339 requirement IDs (each in a plan's `requirements:` field)

| REQ | Plan(s) carrying it (frontmatter `requirements:`) | Covered by | Status |
|-----|----------------------------------------------------|-----------|--------|
| BATCH-01 | 339-02, 339-03, 339-04 | A3 + A4 + A5 + A6 (+ A2 design-lock half) | COVERED |
| BINGO-06 | 339-01 | A1 (supported by A2) | COVERED |

(339-01 frontmatter requirements = BINGO-06; 339-02 / 339-03 / 339-04 frontmatter requirements = BATCH-01.) REQ: **2/2 COVERED.**

### 4c. RESEARCH — N/A (no `339-RESEARCH.md`; the locked plan doc is the substitute load-bearing source)

There is **no `339-RESEARCH.md`** for this phase, and this is **N/A — NOT a coverage gap.** Research was deliberately skipped per the milestone init (ROADMAP v51.0 §"Scope source": *"No research — a fully-specced contract feature with the game-theory / Monte-Carlo analysis already done in the plan doc"*; CONTEXT.md §domain: *"No research sub-phase (the design + game-theory/Monte-Carlo is already done in the plan doc)"*). The **substitute load-bearing source** is the locked design doc `.planning/PLAN-V51-CLAIMBINGO-COLOR-COMPLETION.md` — it carries the full reward economics, the validation sketch, the storage/constants, the game-theory / Monte-Carlo (mean ~182 tickets to a first bingo), the seven "Open before SPEC" items, and the "What this replaces" (JACK) section. Its load-bearing findings are fully consumed by the SPEC artifacts:

| Plan-doc load-bearing input (the RESEARCH substitute) | Covered by | Status |
|-------------------------------------------------------|-----------|--------|
| The reward economics + constants (regular 0.05% / symbol-first additive 0.1% / quadrant-first replacement 0.5%; BURNIE 1 000 / 2 000 / 5 000) | A3 §5 (verbatim) + A4 §3 (the acceptance table) | COVERED |
| The validation sketch + `traitId` derivation + tier-selection block (plan doc :101-131) | A3 §3 + A4 §2/§3 | COVERED |
| The freeze-safety-by-construction claim (Open-before-SPEC #5) — re-PROVEN, not assumed | A1 (the structured per-slot proof) + A2 (the write-site IFF the freeze claim rests on) | COVERED |
| The Monte-Carlo / whale-race framing (mean ~182 tickets; per-VRF-reveal race window) | A2 §"Whale-Race" (the D-03 ACCEPTED-BY-DESIGN non-finding) | COVERED |
| The "What this replaces" JACK final-day deletion + the REBAL co-requisite | A5 (REBAL BPS-sum + JACK clean-orphan/preserved-plumbing) | COVERED |
| The seven "Open before SPEC" items | the dedicated resolution table below (§4e) | COVERED |

RESEARCH: **N/A — not a gap.** The locked plan doc is the substitute load-bearing source and every load-bearing input is COVERED by a Phase-339 artifact.

### 4d. CONTEXT — every locked decision D-01..D-13 (`339-CONTEXT.md`)

Every locked decision is mapped to the artifact that covers it (per the plan's D→artifact map):

| Decision | Topic | Covering artifact | Status |
|----------|-------|-------------------|--------|
| **D-01** | slot-arg width — `claimBingo(uint256, uint8, uint32[8])`; the `uint32` ~4.29B cap unreachable, written disposition | A3 §1 / §1a | COVERED |
| **D-02** | full write-site soundness attestation (NOT a precedent-based hand-wave); the spoofing-resistance IFF | A2 (the IFF theorem + sub-claims a/b/c) | COVERED |
| **D-03** | whale-race ACCEPTED-BY-DESIGN written non-finding (per-VRF-reveal race window); race-start semantics | A2 §"Whale-Race" (+ A1 §"Race-start semantics") | COVERED |
| **D-04** | freeze-proof depth — structured per-slot enumeration (the DOMINANT-axis safe default) | A1 (the 3-class per-slot classification table) | COVERED |
| **D-05** | reward tiers + the six named constants (transcribed verbatim, not re-derived) | A3 §5 | COVERED |
| **D-06** | tier-precedence rule (quadrant-first-before-symbol-first; both bits; suppress) | A4 §2 / §3 | COVERED |
| **D-07** | per-player dedup `(level, quadrant)` + systemwide first keys (4 quadrant / 32 symbol) | A3 §2 / §6e + A4 §1 | COVERED |
| **D-08** | reward paths (`transferFromPool` clamped-return / `creditFlip`) + empty-pool no-op + `gameOver` cutoff + event-only leaderboard | A3 §6 | COVERED |
| **D-09** | `traitId = (quadrant<<6)|(c<<3)|symInQ` derivation; `[QQ][CCC][SSS]` layout | A3 §3 | COVERED |
| **D-10** | module placement — new `DegenerusGameBingoModule.sol`, delegatecalled via `GAME_BINGO_MODULE`; shared storage | A3 §4 (+ §2 storage placement) | COVERED |
| **D-11** | REBAL — complete pool-BPS set sums to 10000 (locate the missing 2000); supply unchanged | A5 PART 1 | COVERED |
| **D-12** | JACK — clean-orphan (sole use/emit inside the deleted branch) + preserved isFinalDay plumbing | A5 PART 2 | COVERED |
| **D-13** | grep-attest EVERY cited `file:line` vs `812abeee`; producer-before-consumer edit-order map | A6 (the 22-anchor table + the 4-step edit-order map) | COVERED |

CONTEXT: **D-01..D-13 all mapped to a covering artifact — 13/13 COVERED, 0 MISSING.**

### 4e. "Open before SPEC" resolution table (the seven plan-doc items)

Each of the seven plan-doc "Open before SPEC" items, shown resolved by a Phase-339 artifact (item 3 is a deliberate Out-of-Scope exclusion, not a gap):

| # | "Open before SPEC" item | Resolved by | Status |
|---|--------------------------|-------------|--------|
| 1 | Module placement (new module vs glue into Lootbox/Jackpot) | A3 (D-10: new `DegenerusGameBingoModule.sol`, delegatecalled from `DegenerusGame.claimBingo`) | RESOLVED |
| 2 | Slot type width (`uint32` vs implicit cap) | A3 §1a (D-01: `uint32`, cap-unreachable disposition written) | RESOLVED |
| 3 | View helper (frontend "which first-prizes are up for grabs / claimable for me") | Deliberate **Out-of-Scope exclusion** (REQUIREMENTS "Out of Scope (v51.0)" — deferred follow-up read-only module; NOT a Phase-339 artifact) | RESOLVED (as a recorded exclusion) |
| 4 | `traitBurnTicket` populated-only-after-level-L-resolution invariant | A2 (D-02 soundness IFF) + A1 (D-04 freeze proof attests the populated-only-after-resolution invariant) | RESOLVED |
| 5 | RNG-freeze interaction (`v45-vrf-freeze-invariant`) | A1 (the BINGO-06 freeze proof; v45 re-attested by name) | RESOLVED |
| 6 | Jackpot final-day deletion side-effects (no other consumers broken) | A5 PART 2 (D-12 JACK clean-orphan + preserved plumbing) | RESOLVED |
| 7 | Tier-precedence test coverage (quadrant-first suppresses symbol-first AND marks the bit) | A4 (the binding acceptance contract; the empirical TST-02 coverage lives at Phase 341) | RESOLVED |

All seven items resolved (item 3 = deliberate Out-of-Scope exclusion).

### 4f. Load-bearing Wave-1 source corrections (surfaced, NOT silently dropped)

Two load-bearing source corrections were recorded during Wave 1 and are carried into this coverage audit so the index is faithful (they STRENGTHEN the artifacts; they are not gaps):

1. **`traitBurnTicket` write-site (D-13 / 339-01).** The sole `traitBurnTicket` *writer* is **`contracts/modules/DegenerusGameMintModule.sol:603-643`** (inline-assembly batch append, keyed by the RNG-resolved `traitId` at `:586-587`). The plan/CONTEXT-cited `DegenerusGame.sol:2701 / 2730 / 2813` (all `view`: `sampleTraitTickets` / `sampleTraitTicketsAtLevel` / `getTickets`) and `JackpotModule:654` are **READ-side consumers**, NOT writers. The soundness IFF (A2) and the populated-only-after-resolution freeze invariant (A1) are anchored to the real writer; the design-lock (A3) and the grep table (A6) carry the correction. (Captured in A1, A2, A6; honored throughout A3, A5.)
2. **REBAL missing 2000 + JACK function name.** The REBAL complete pool-BPS set's missing 2000 bps = **`CREATOR_BPS = 2000` at `StakedDegenerusStonk.sol:291`** (the full set `{CREATOR 2000, WHALE 1000, AFFILIATE 3500, LOOTBOX 2000, REWARD 500, PRESALE_BOX 1000}` sums to 10000; the `:294-298` block alone sums to only 8000). And the JACK deletion's containing function is **`_handleSoloBucketWinner` (`:1305`)**, NOT `_paySoloBucket` as the plan/CONTEXT named it (the branch / constant / event / gate / caller lines are all confirmed at the cited line numbers — only the function name differs). (Captured in A5 §1.2 / §2.4 and consolidated in A6 §1.3.)

Neither is a contract drift between `812abeee` and HEAD (that diff is EMPTY) — both are plan-text-vs-source clarifications captured so no "by construction" citation ships uncorrected into IMPL 340. **Surfaced here rather than buried**, per the `feedback_verify_call_graph_against_source` rule.

---

## 5. Exclusions (not gaps — explicitly out of scope)

These are deliberately NOT covered by a Phase-339 artifact, and are NOT coverage gaps:

| Excluded item | Why excluded (not a gap) | Where it lives |
|---------------|--------------------------|----------------|
| Bingo progress view helper ("which (level, symbol) first-prizes are up for grabs / claimable for me") | Frontend read-only, deferred follow-up module — explicitly out of v51 scope | REQUIREMENTS "Out of Scope (v51.0)"; CONTEXT "Deferred Ideas"; resolved as Open-before-SPEC item 3 (§4e) |
| The internal 3-skill adversarial sweep + delta-audit + `audit/FINDINGS-v51.0.md` | DEFERRED → the v52 consolidated audit (cumulative v50 + v51 surface) per the USER minimal-close decision; the SPEC's freeze proof + tier-precedence lock + soundness attestation ARE the v51 security floor for this surface | REQUIREMENTS "Out of Scope (v51.0)" + "Future Requirements"; STATE.md "v50.0 + v51.0 AUDIT DEBT → v52" |
| Cross-level / multi-level bingo, 2nd/3rd-place ladders within a tier, commit-reveal anti-MEV, `Pool.Reward` refill automation, Q3 (Dice) special-case naming | Explicit non-goals (locked in the plan doc / REQUIREMENTS Out of Scope) | REQUIREMENTS "Out of Scope (v51.0)"; CONTEXT "Deferred Ideas" |
| The contract changes themselves (BINGO-01..05 + REBAL-01 + JACK-01/02 + BATCH-02) | Paper-only SPEC phase — zero `contracts/*.sol`. These land at IMPL 340 under the single-batched-diff HARD STOP (the edit-order map A6 governs their order) | REQUIREMENTS (Phase 340); ROADMAP Phase 340; A6 PART 2 |
| The empirical test proofs (TST-01..06) | Tests are authored at Phase 341 against the applied diff, not at SPEC. (TST-02 proves the tier-precedence suppression A4 specifies as the acceptance contract.) | REQUIREMENTS (Phase 341); ROADMAP Phase 341 |
| The TERMINAL minimal close + re-attestation (BATCH-03) | Phase 342 — re-attests all 18 v51.0 reqs + the atomic 5-doc closure flip; the deferred-sweep charge is enumerated for v52 there | REQUIREMENTS (Phase 342); ROADMAP Phase 342 |
| The REQUIREMENTS "Out of Scope (v51.0)" set | Explicitly excluded from the whole milestone | REQUIREMENTS "Out of Scope (v51.0)" |

---

## 6. Verdict

**ALL items COVERED, 0 MISSING.**

Per-source recap:

- **GOAL:** 5/5 Success Criteria covered (§2 / §4a) — SC1→A3, SC2→A1+A2, SC3→A4, SC4→A5, SC5→A6.
- **REQ:** 2/2 requirements covered (§3 / §4b) — BATCH-01 (carried by plans 02/03/04 frontmatter → A3+A4+A5+A6), BINGO-06 (carried by plan 01 frontmatter → A1, supported by A2).
- **RESEARCH:** N/A — not a gap (§4c). No `339-RESEARCH.md`; research was deliberately skipped per the milestone init; the locked plan doc `.planning/PLAN-V51-CLAIMBINGO-COLOR-COMPLETION.md` is the substitute load-bearing source and every load-bearing input is COVERED by a Phase-339 artifact.
- **CONTEXT:** D-01..D-13 all mapped to a covering artifact — **13/13 COVERED, 0 MISSING** (§4d).

The seven "Open before SPEC" items are each resolved by a Phase-339 artifact (§4e; item 3 = deliberate Out-of-Scope exclusion). The two load-bearing Wave-1 source corrections (the `traitBurnTicket` writer `= MintModule:603-643`, and the REBAL `CREATOR_BPS=2000`@`:291` + the `_handleSoloBucketWinner` function name) are surfaced in §4f, not buried.

**No source item was silently dropped (the `scope_reduction_prohibition` floor).** The exclusions in §5 are deliberate scope boundaries (the deferred view helper, the v52-deferred internal sweep, the explicit non-goals, the IMPL/TST/TERMINAL downstream work, and the REQUIREMENTS "Out of Scope (v51.0)" set), each recorded with its destination — not coverage gaps. The Phase-339 SPEC is complete: the full bundle design is settled (SC1, A3), the BINGO-06 RNG-freeze safety is PROVEN with the write-site soundness it rests on (SC2, A1+A2), the tier-precedence rule is design-locked as the IMPL acceptance contract (SC3, A4), the REBAL BPS-sum invariant + the JACK final-day deletion side-effects are attested (SC4, A5), and every cited `file:line` is grep-attested vs `812abeee` with the producer-before-consumer edit-order map confirmed (SC5, A6). IMPL 340 may consume this SPEC with zero "by construction" assumptions.

---
*Phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc — Plan 339-04 Task 1 (BATCH-01 coverage closure).*
*Authored: 2026-05-28 · Frozen baseline: 812abeee (contracts/ diff vs HEAD empty).*
