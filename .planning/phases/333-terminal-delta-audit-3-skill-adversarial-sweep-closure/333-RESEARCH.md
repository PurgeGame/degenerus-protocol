# Phase 333: TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + Closure - Research

**Researched:** 2026-05-27
**Domain:** v49.0 milestone-closure terminal (delta-audit + 3-skill adversarial sweep + atomic closure flip) — DOC-ONLY, zero contract mutation
**Confidence:** HIGH (4th repetition of a precedent-locked pattern; every mechanic verified against the live v48 Phase 328 deliverables + the frozen-subject git anchors)

## Summary

Phase 333 is the 4th repetition of a strongly-established TERMINAL audit-closure pattern (v44/308 → v45/314 → v46/320 → v47/324 → v48/328). The CONTEXT.md has already locked every decision (D-01..D-13); this research extracts the concrete, file-level "how" the planner mirrors from the v48 Phase 328 deliverables, and flags the handful of v49-specific divergences. There is essentially **no open design space** — this is a precedent-execution phase, not a from-first-principles one.

The phase has exactly 4 requirements (SWEEP-01/02/03 + BATCH-03) mapped to 4 plans that mirror the 328 structure verbatim: `333-01 DELTA-AUDIT` (SWEEP-02, read-only) ∥ `333-02 ADVERSARIAL-SWEEP` (SWEEP-01, read-only) run as a parallel wave against the FROZEN subject, then `333-03 FINDINGS-v49.0.md` (SWEEP-03, consumes 01+02), then `333-04 CLOSURE-FLIP` (BATCH-03, `autonomous:false`, LAST). The subject is FROZEN at `4c9f9d9b` (verified: `git diff 4c9f9d9b HEAD -- contracts/*.sol` is empty); the delta baseline is `0cc5d10f` (v48.0 closure HEAD). Nothing is pushed.

**Primary recommendation:** Clone the four 328-0X-PLAN.md files structurally, swap the v48 surface set (PFIX/RFALL/KEEP/POOL/BTOMB/HERO/SWAP) for the v49 blast radius (router/advance-rework/re-peg/micro-opts across 5 contract files), swap `1575f4a9`→`4c9f9d9b` (frozen) and `da5c9d50`→`0cc5d10f` (baseline), swap `MILESTONE_V48`→`MILESTONE_V49`, swap "40 reqs"→"36 reqs", and add the three v49-specific extra attestations D-06 demands (the 4 structural invariants from 329-SPEC, the OPEN-E 4-protection BLOCKING re-attest per GASOPT-05, VRF-freeze-intact under the router composition).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Delta-audit (SWEEP-02) | `.planning/` log (333-01-DELTA-AUDIT.md) | reads frozen `contracts/@4c9f9d9b` read-only | analysis artifact; never mutates the subject |
| Adversarial sweep (SWEEP-01) | `.planning/` log (333-02-ADVERSARIAL-LOG.md) | the 3 `$HOME/.claude/skills/*` personas + reads frozen subject | examination artifact; the orchestrator (Task-tool holder) dispatches skills |
| FINDINGS deliverable (SWEEP-03) | `audit/FINDINGS-v49.0.md` (tracked) | folds 333-01 §3/§5 + 333-02 §4 | publishable report; chmod 444 at closure |
| Closure flip (BATCH-03) | 5 `.planning/` docs + `audit/FINDINGS-v49.0.md` | the `MILESTONE_V49_AT_HEAD_<sha>` self-referential signal | atomic doc flip gated behind a single `autonomous:false` USER checkpoint |

Every tier here is documentation. ZERO `contracts/*.sol` writes anywhere in the phase. The only "trust boundary" is the human review gate before the closure signal is emitted. [VERIFIED: 328-01/02/03/04-PLAN.md threat models all record "(none introduced)"]

## Standard Stack

Not a software-stack phase — no packages installed. The "stack" is the toolset + the precedent artifacts.

### Core
| Tool / Artifact | Purpose | Why Standard |
|-----------------|---------|--------------|
| `git show <sha>:contracts/...` / `git diff <base>..<subject> -- contracts/` | Read-only access to the FROZEN subject + the v48→v49 delta | The sweep + delta probe the *actual* `4c9f9d9b` source, never from memory [VERIFIED: 328-01/02 read_first + action blocks] |
| `git diff 4c9f9d9b HEAD -- contracts/` (must be empty) | T-CONTRACTS guard — proves the subject stayed frozen | Re-run before the closure commit [VERIFIED: ran 2026-05-27, output empty] |
| `grep -niE` against `git show 4c9f9d9b:...` | Re-grep-verify every cited `file:line` against the frozen SHA | D-02 requires every anchor re-grep-verified, not recalled |
| `chmod 444 audit/FINDINGS-v49.0.md` | Lock the deliverable at closure HEAD | v44/v46/v47/v48 precedent (FINAL READ-only) [VERIFIED: FINDINGS-v35..v48 are `-r--r--r--`] |
| The 3 skill `SKILL.md` files | Persona fidelity across parallel spawns | Located at `$HOME/.claude/skills/{contract-auditor,zero-day-hunter,economic-analyst}/SKILL.md` [VERIFIED: all 3 exist] |

### Supporting (the directly-reusable structural templates)
| Artifact | Path | Reuse |
|----------|------|-------|
| `328-01-PLAN.md` + `328-01-DELTA-AUDIT.md` | `.planning/milestones/v48.0-phases/328-.../` | the delta-audit plan + output shape → `333-01` [VERIFIED: read in full] |
| `328-02-PLAN.md` + `328-02-ADVERSARIAL-LOG.md` | same dir | the sweep plan (genuine-PARALLEL topology in the EXECUTION NOTE + §A/§B/§C/§D log shape) → `333-02` [VERIFIED] |
| `328-03-PLAN.md` | same dir | the FINDINGS authoring plan (9-section walk) → `333-03` [VERIFIED] |
| `328-04-PLAN.md` | same dir | the closure-flip plan (SHA orchestration + `autonomous:false` gate + T-PREMATURE/T-SHADRIFT/T-CONTRACTS threat model) → `333-04` [VERIFIED] |
| `audit/FINDINGS-v48.0.md` | `audit/` | the 9-section layout + §9a/§9b/§9c pattern + frontmatter fields → `FINDINGS-v49.0.md` [VERIFIED: headers + frontmatter read] |
| `.planning/MILESTONES.md` | `.planning/` | the v48.0 archive block (the format to prepend a v49.0 entry above) [VERIFIED: read] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Single-commit self-referential SHA (v48 actual) | 2-commit sequential-SHA (D-10 / brief wording) | **See "State of the Art" below** — v48 used SINGLE-commit; both yield a self-referential SHA. Mirror the v48 actual unless the planner has a reason to split. |
| 4-plan structure (D-11 / 328) | 3-plan (fold delta into FINDINGS) | The 4-plan split keeps the read-only logs (01∥02) parallelizable and the gated flip (04) isolated — the proven shape. |

**Installation:** None. No packages. (Package Legitimacy Audit + Environment Availability omitted — no external dependencies; all tools are `git`/`grep`/`chmod`/the local skills.)

## Architecture Patterns

### System Architecture Diagram — the closure data flow

```
  FROZEN SUBJECT (contracts/ @ 4c9f9d9b)          BASELINE (contracts/ @ 0cc5d10f)
         │  read-only (git show / git diff)               │
         ├───────────────────────────┬────────────────────┘
         ▼                           ▼
  ┌──────────────────┐      ┌─────────────────────────────────┐
  │ 333-01 DELTA      │      │ 333-02 ADVERSARIAL SWEEP         │   ← WAVE 1 (parallel,
  │  (SWEEP-02)       │      │  (SWEEP-01)                      │      both read-only)
  │ blast-radius      │      │ 3 skills GENUINE-PARALLEL,       │
  │ attribution +     │      │ run INLINE in orchestrator       │
  │ NON-WIDENING +    │      │ (holds Task tool) →              │
  │ 4 invariants +    │      │ §A charge / §B raw / §C dispo /  │
  │ OPEN-E 4-prot +   │      │ §D skeptic dual-gate             │
  │ VRF-freeze        │      │ → FINDING_CANDIDATE? (target 0)  │
  └────────┬─────────┘      └──────────────┬──────────────────┘
           │  §3/§5                         │  §4
           └───────────────┬───────────────┘
                           ▼
                ┌─────────────────────────┐
                │ 333-03 FINDINGS-v49.0.md │   ← WAVE 2 (consumes 01+02)
                │  (SWEEP-03) 9 sections,  │
                │  MILESTONE_V49_AT_HEAD_   │
                │  <sha> placeholder verbatim│
                └────────────┬─────────────┘
                             ▼
              ┌────────────────────────────────────┐
              │ 333-04 CLOSURE FLIP (BATCH-03)       │  ← WAVE 3 (autonomous:false, LAST)
              │  Task 1: USER gate (verdict+signal+  │
              │          new_findings disposition)   │  ← BLOCKING human-verify
              │  Task 2: resolve <sha> → own commit  │
              │          SHA → propagate verbatim →  │
              │          atomic 5-doc flip →         │
              │          chmod 444 → grep 0          │
              │          unresolved → commit         │
              │          (force-add .planning/) →    │
              │          NOTHING pushed              │
              └────────────────────────────────────┘
```

### Recommended Plan Structure (mirror 328; D-11)
```
.planning/phases/333-terminal-.../
├── 333-01-PLAN.md            # SWEEP-02 delta-audit, wave 1, autonomous:true, depends_on:[]
│   └── 333-01-DELTA-AUDIT.md     # output artifact
├── 333-02-PLAN.md            # SWEEP-01 adversarial sweep, wave 1, autonomous:true, depends_on:[]
│   └── 333-02-ADVERSARIAL-LOG.md # output artifact (§A/§B/§C/§D)
├── 333-03-PLAN.md            # SWEEP-03 FINDINGS authoring, wave 2, autonomous:true, depends_on:[333-01,333-02]
│   └── (writes audit/FINDINGS-v49.0.md)
└── 333-04-PLAN.md            # BATCH-03 closure flip, wave 3, autonomous:FALSE, depends_on:[333-03]
```

### Pattern 1: Genuine-PARALLEL 3-skill sweep (SWEEP-01) — the hard-won 314/324/328 lesson
**What:** Dispatch `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst` as **3 concurrent Task spawns** for ~3× wall-clock speedup.
**When to use:** Whenever the running context holds the Task tool.
**The critical nuance (D-02, 328-02 EXECUTION NOTE):** this requires the **ORCHESTRATOR to run the sweep plan INLINE in the main context** (which holds Task/Agent), NOT nested inside a `gsd-executor` (which lacks Task → forces a HYBRID/SEQUENTIAL_MAIN_CONTEXT fallback). The fallback is functional and preserves persona fidelity via the dedicated `SKILL.md` files, but is slower. **Record which path was actually used in §A of the log.**
**v48 outcome (the bar):** GENUINE PARALLEL_SUBAGENT, 16 disposition rows = 10 NEGATIVE-VERIFIED + 6 SAFE_BY_DESIGN + 0 FINDING_CANDIDATE. [VERIFIED: MILESTONES.md v48 archive block + commit `c1c32df5`]

```
# Source: 328-02-PLAN.md EXECUTION NOTE (verbatim mechanic)
# context block @-imports the 3 SKILL.md personas:
@$HOME/.claude/skills/contract-auditor/SKILL.md
@$HOME/.claude/skills/zero-day-hunter/SKILL.md
@$HOME/.claude/skills/economic-analyst/SKILL.md
# Task 1 writes §A CHARGE, runs the 3-skill pass (parallel Task spawns when available),
#   each probes `git show 4c9f9d9b:contracts/...` read-only, collects raw per-skill output (§B).
# Task 2 applies the skeptic dual-gate, builds the §C disposition table, writes §D attestation.
```

> ⚠️ Skill location correction: the brief states the skills "live in .claude/skills/". **They do NOT.** They live in `$HOME/.claude/skills/` (verified: `.claude/skills/` does not exist in the repo; all three `SKILL.md` files exist under `$HOME/.claude/skills/`). The 328 plans correctly `@$HOME/.claude/skills/...`. Mirror that.

### Pattern 2: The skeptic DUAL-GATE (SWEEP-01, every elevation)
**What:** `/degen-skeptic` is OUT as a *skill* (D-271-ADVERSARIAL-02), but the skeptic FUNCTION is the mandatory dual-gate applied to every elevation before it becomes a FINDING_CANDIDATE:
1. **Structural-protection lens** — does a structural mechanism already prevent the elevation?
2. **3-condition EV lens** — (a) manifests without an attacker / is positive-EV to execute, (b) magnitude is material, (c) severity survives the skeptic re-read.
**An elevation becomes a FINDING_CANDIDATE only if it survives BOTH gates.** Applied twice: per-skill self-arm AND orchestrator integration-time re-application (the v46 §4.4 / v47 §4.4 / v48 §4.4 dual-gate pattern). [VERIFIED: 328-02-PLAN.md interfaces block + FINDINGS-v48 §4.4]

### Pattern 3: Adversarial-log §A/§B/§C/§D structure
**Source:** 328-02-ADVERSARIAL-LOG.md + the 320/324 shape.
- **§A CHARGE** — the FIXED 3-skill set (`/degen-skeptic` OUT explicitly), the audit subject SHA (`4c9f9d9b`), the per-skill probe assignment, and the recorded execution path (PARALLEL_SUBAGENT / HYBRID / SEQUENTIAL_MAIN_CONTEXT).
- **§B raw per-skill output** — each skill's findings in its own format, honoring its Known Non-Issues list.
- **§C disposition table** — one row per probe per skill: `Probe ID | Skill | Surface | Disposition (NEGATIVE-VERIFIED / SAFE_BY_DESIGN / FINDING_CANDIDATE) | Skeptic-filter outcome | Tier (1 single-skill / 2 multi-skill consensus / n-a)`.
- **§D Skeptic-Reviewer Filter Attestation** — the dual-gate applied + any self-discards.

### Pattern 4: Single-USER-gate closure flip (BATCH-03)
**Source:** 328-04-PLAN.md (verbatim mechanic). Two tasks:
- **Task 1 (`checkpoint:human-verify`, gate="blocking"):** present the closure verdict (FINDINGS §9a) + the proposed `MILESTONE_V49_AT_HEAD_<sha>` signal string + any new_findings disposition. BLOCK for explicit USER approval. Resolve/propagate/flip NOTHING before approval. Does NOT auto-advance even with `auto_advance: true`.
- **Task 2 (`auto`, runs after approval):** verify `git diff 4c9f9d9b HEAD -- contracts/` empty → resolve the placeholder SHA → propagate VERBATIM in one pass → atomic 5-doc flip → chmod 444 → grep zero unresolved placeholders → commit (force-add `.planning/`) → NOTHING pushed.

### Anti-Patterns to Avoid
- **Nesting the sweep inside a gsd-executor** → kills genuine-parallel (executor lacks Task tool). Run 333-02 INLINE in the orchestrator. [D-02]
- **Probing from memory** → every cited `file:line` MUST be re-grep-verified against `4c9f9d9b`. [D-02]
- **Auto-advancing past the closure gate** → 333-04 Task 1 is `autonomous:false`/blocking; HELD at the closure boundary even with `auto_advance: true`. [D-10, feedback_wait_for_approval]
- **Hardcoding regression numbers** → cite `test/REGRESSION-BASELINE-v49.md` (666/42/17) as authoritative, do not re-derive. [D-09]
- **Auto-fixing a surfaced FINDING_CANDIDATE** → the subject is FROZEN; any fix is a NEW contract phase needing USER approval. Surface to the closure gate, do not patch. [D-04]
- **Leaving an unresolved `<sha>` placeholder** → final grep must confirm zero `MILESTONE_V49_AT_HEAD_<sha>` literal tokens remain (T-SHADRIFT). [D-10]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| FINDINGS 9-section layout | a new report structure | clone `audit/FINDINGS-v48.0.md` verbatim, swap content | D-13 mandates exact mirror; the planner reads v48 as the template |
| Adversarial-log shape | an ad-hoc disposition format | the §A/§B/§C/§D structure from 328-02 | proven across 320/324/328 |
| Closure-signal propagation | a bespoke find/replace | the single-pass verbatim substitution + grep-zero check | T-SHADRIFT guard; v44/v46/v47/v48 precedent |
| Delta attribution | re-reading every diff hunk fresh | `git diff 0cc5d10f 4c9f9d9b -- contracts/` (5 files) grouped by v49 work item | the diff *is* the blast radius; map hunk → work item |
| Regression arithmetic | re-running `forge test` + reclassifying | cite `test/REGRESSION-BASELINE-v49.md` | D-09; the ledger is authoritative |

**Key insight:** This is the 4th repetition — the single biggest risk is *re-deriving* mechanics that are already locked. Treat the 328 deliverables as fill-in-the-blanks templates.

## Runtime State Inventory

> This is a rename-adjacent milestone (the v49 IMPL renamed `Crank*`→`Keeper*` tests + `autoResolve`→`degeneretteResolve`), but **Phase 333 itself is a doc-only audit/closure phase that mutates NO runtime state.** The inventory below covers what the *delta-audit* must attribute as already-landed (in the v49 IMPL/TST, NOT Phase 333), so the planner does not mistake landed churn for new regression.

| Category | Items Found | Action Required (in 333) |
|----------|-------------|------------------|
| Stored data | None — no datastore touched by Phase 333. The v49 contract redesign (`63bc16ca`) is already frozen; no migration is a 333 task. | None — verified: 333 writes only `.planning/` + `audit/` |
| Live service config | None — verified: this repo is a smart-contract audit repo; no live services, no n8n/Datadog/Tailscale. | None |
| OS-registered state | None — verified: no Task Scheduler / pm2 / systemd in scope. | None |
| Secrets/env vars | None — verified: closure flip touches no secrets; commit-guard hook bypass var `CONTRACTS_COMMIT_APPROVED` is irrelevant (no `.sol` in the diff). | None |
| Build artifacts | None mutated by 333. The v49 IMPL already landed; the delta-audit READS `test/` churn (renames R073/R077/R096/R097, deletions D, adds A) but attributes them via the ledger — it does not rebuild anything. | None — cite `test/REGRESSION-BASELINE-v49.md` |

**Canonical question answer:** After Phase 333's doc flip, NO runtime system has any old/new string cached — because 333 changes no runtime state at all. The contract subject is byte-frozen at `4c9f9d9b` throughout.

## Common Pitfalls

### Pitfall 1: SHA-orchestration model confusion (single-commit vs 2-commit)
**What goes wrong:** D-10 and the brief say "**2-commit** sequential-SHA orchestration", but the actual v48 Phase 328 closure used a **SINGLE-commit** self-referential orchestration. [VERIFIED: closure commit `57a796d1` "v48.0 CLOSURE FLIP — emit MILESTONE_V48_AT_HEAD_0cc5d10f + atomic 5-doc flip + chmod 444"; FINDINGS-v48 §9c says "resolved at the Phase 328 closure commit per the single-commit sequential-SHA closure orchestration"; the signal `0cc5d10f` IS that commit's own SHA.]
**Why it happens:** v44/v46/v47 may have used a 2-commit split (author-with-placeholder, then resolve-in-a-second-commit); v48 collapsed it to one commit whose own SHA is the resolved signal. CONTEXT D-10's "2-commit" wording is carried from the older precedent.
**How to avoid:** Both models produce the same self-referential result (the signal = the closure commit's own SHA). The mechanic that matters is: the placeholder `MILESTONE_V49_AT_HEAD_<sha>` resolves to the closure commit's own SHA, propagated verbatim in one pass, grep-zero verified. **Recommend mirroring the v48 single-commit actual** (simpler, the immediate precedent), but note this is a low-stakes choice — surface it to the planner as a discretionary detail, not a blocker. [ASSUMED that single-commit is preferred — confirm with the planner/user if they want strict D-10 literalism.]
**Warning signs:** A plan that schedules two separate closure commits where one suffices.

### Pitfall 2: Stating HEAD as `95aaf340` when it has advanced
**What goes wrong:** The brief states "Current HEAD = `95aaf340`". The actual current HEAD is `830eff56` (two doc-only commits since: `54437675` "capture phase context" + `830eff56` "record phase 333 context session"). [VERIFIED: `git rev-parse HEAD` + `git log 95aaf340..HEAD`]
**Why it happens:** The 333 CONTEXT/STATE capture commits landed after the brief was written.
**How to avoid:** The frozen-subject guard is `git diff 4c9f9d9b HEAD -- contracts/` (empty regardless of which doc commits HEAD points at) — it does NOT depend on HEAD being any specific SHA. The closure commit's own SHA (not yet created) becomes the signal. Do not hardcode `95aaf340`.
**Warning signs:** A plan referencing `95aaf340` as a live anchor.

### Pitfall 3: Mis-attributing test churn as regression
**What goes wrong:** The v49 `test/` diff includes 4 renames (R073/R077/R096/R097 `Crank*`→`Keeper*`), deletions (`CrankFaucetResistance.t.sol` deleted), and adds — counting these as new failures inflates the regression set.
**How to avoid:** NON-WIDENING = strict **failing-NAME-set equality** vs the v48 §2 union (NOT a count). The 42-red set == the v48.0 §2 union BY NAME (net-zero). The 17 reward-rehoming reds were DELETED (premise-retired), 5 files renamed. Cite `test/REGRESSION-BASELINE-v49.md` as authoritative. [D-09 / D-06]
**Warning signs:** A delta-audit that quotes "42 failures, up from 40" instead of name-set equality.

### Pitfall 4: Forgetting the v49-specific extra attestations (D-06)
**What goes wrong:** A bare NON-WIDENING diff table is INSUFFICIENT for v49 — D-06 requires three additional structural re-attestations the v48 delta did not need (because v48 had no structural-invariant SPEC of this kind).
**How to avoid:** The 333-01 delta-audit MUST additionally attest (see "Code Examples" §3.B extension below):
  1. **The 4 structural invariants (329-SPEC §2)** intact at closure HEAD, cross-ref'd to empirical proofs: (a) one-category early-return [TST-02], (b) frozen advance-consume [ADV-04/TST-01], (c) guaranteed free-fallback caller [D-04a], (d) single day-start epoch SATISFIED-BY-DELETION [GAS-03].
  2. **The OPEN-E 4-protection BLOCKING re-attestation (GASOPT-05)** — `:676` per-iteration `isOperatorApproved` was dropped, `:401` subscribe-time gate kept. The sweep MUST re-attest the 4 OPEN-E protections (consent-gate-at-subscribe / default-self byte-identical / no-escalation / trust-the-sub temporal bound) as a **HARD blocking condition before closure**; if it fails, the removal is REVERTED before the milestone ships.
  3. **VRF/RNG-freeze INTACT under the router composition** — no in-window SLOAD introduced by the unified same-tx path (v45 north-star; ADV-04/TST-01).
**Warning signs:** A 333-01 plan whose acceptance criteria stop at the diff-attribution table.

### Pitfall 5: Running 333-02 sweep nested (kills parallel)
Covered in Anti-Patterns. Restated as a pitfall because it is the single most-repeated execution mistake across 314/324: the sweep MUST run in the Task-tool-holding orchestrator context.

## Code Examples

Verified patterns from the live v48 deliverables (adapt SHAs/surfaces for v49):

### 1. Frozen-subject guard (used in every plan's verify block)
```bash
# Source: 328-04-PLAN.md Task 2 <automated> (adapted: 1575f4a9 → 4c9f9d9b)
cd /home/zak/Dev/PurgeGame/degenerus-audit \
  && test -z "$(git diff 4c9f9d9b HEAD -- contracts/)" \
  && test "$(stat -c '%a' audit/FINDINGS-v49.0.md)" = "444" \
  && ! grep -q "MILESTONE_V49_AT_HEAD_<sha>" audit/FINDINGS-v49.0.md
```

### 2. Delta-surface enumeration (333-01) — the v49 blast radius
```bash
# Source: 328-01-PLAN.md Task 1 action (adapted to the v49 baseline→subject range)
git diff 0cc5d10f 4c9f9d9b -- contracts/   # 5 files, +376 / -226 [VERIFIED 2026-05-27]
git log  --oneline 0cc5d10f..HEAD -- 'contracts/*.sol'  # exactly 2 commits:
#   63bc16ca  feat(330): v49.0 keeper-router redesign (BATCH-02, user-approved)
#   4c9f9d9b  feat(331-05): keeper-router gas — split buy/open batch + whale-pass-weighted autoOpen budget
```
The 5 changed contract files [VERIFIED via `git diff --stat`]:
| File | Lines | v49 work item(s) |
|------|-------|------------------|
| `contracts/AfKing.sol` | 318 | ROUTER-01..10 (parameterless `doWork`, `_autoBuy` refactor, RD-2 drop-guard, unified flat-per-tx `creditFlip` CEI-last, `BUY_BATCH`/`OPEN_BATCH` split, the 331 re-peg, GASOPT-04 drop `AutoBought`, GASOPT-05 drop `:676`) |
| `contracts/DegenerusGame.sol` | 196 | ADV-02 `advanceGame` wrapper decode, discovery views `advanceDue()`/`boxesPending()`/`keeperSnapshot()` (GASOPT-03), `autoOpen` RD-3/RD-5 rework, `degeneretteResolve` rename + GAS-06 re-peg, `batchPurchaseForKeeper` |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | 52 | ADV-01 remove 3 in-callee `creditFlip`s, ADV-02 `(mult,rewardable)` return shape, ADV-05 mid-day partial-drain `mult=1`, ADV-03 free-fallback callers intact |
| `contracts/modules/DegenerusGameMintModule.sol` | 30 | GASOPT-01 `owedMap` storage-pointer hoist (loop-invariant `rk`), the nested-mapping pointer |
| `contracts/interfaces/IDegenerusGameModules.sol` | 6 | the interface updates (signature changes for `doWork`/`autoOpen`/`autoBuy`/`advanceGame` return) |

> Note: the v49 blast radius is **5 files** (vs v48's 12). Smaller surface, but the *composition* risk (same-tx router bundling) is the genuinely-new attack vector — that is where 333-02 spends its deepest effort (D-01 TIER-A).

### 3. The §3.B Composition Attestation Matrix + the D-06 extra attestations (333-01)
```
# Source: 328-01-PLAN.md §3.B + CONTEXT D-06. The v49 matrix MUST attest:
#  (1) every contracts/+test/ hunk maps to exactly ONE v49 work item (no orphan hunks)
#  (2) the 4 structural invariants (329-SPEC §2) intact @ closure HEAD:
#        (a) one-category early-return        ← cross-ref TST-02
#        (b) frozen advance-consume (ADV-04)  ← cross-ref TST-01 (no in-window SLOAD)
#        (c) guaranteed free-fallback caller   ← AdvanceModule:1012, death-clock :109/:1199-1200/:1898,
#                                                 DegenerusVault.gameAdvance():527, StakedDegenerusStonk.gameAdvance():421
#        (d) single day-start epoch SATISFIED-BY-DELETION ← GAS-03 (autoBuy stall ladder deleted)
#  (3) OPEN-E 4-protection BLOCKING re-attest (GASOPT-05): :676 dropped, :401 kept
#        consent-gate-at-subscribe / default-self byte-identical / no-escalation / trust-the-sub temporal bound
#  (4) VRF/RNG-freeze INTACT under router composition (v45 north-star; ADV-04/TST-01)
#  (5) regression NON-WIDENING: cite test/REGRESSION-BASELINE-v49.md (666/42/17, 42-red == v48 §2 union BY NAME)
```

### 4. The 9-section FINDINGS-v49.0.md layout [VERIFIED: FINDINGS-v48.0.md header grep]
```
## 1. Audit Subject + Baseline      — subject 4c9f9d9b (= 63bc16ca redesign + 4c9f9d9b GAS),
                                       baseline 0cc5d10f (v48.0 closure HEAD); enumerate the 2 contract commits
## 2. Executive Summary             — Closure Verdict Summary / Verdict Math / Severity Counts /
                                       KI Gating Rubric Ref / Forward-Cite Closure Summary / Attestation Anchor
## 3. Per-Phase Sections            — §3a 329 SPEC / §3b 330 IMPL / §3c 331 GAS / §3d 332 TST / §3e 333 TERMINAL
   ### §3.A Delta-Surface Table         ← FOLD from 333-01 (5 surfaces NON-WIDENING)
   ### §3.B Composition Attestation Matrix ← FOLD from 333-01 (the 4 invariants + OPEN-E + VRF-freeze)
   ### §3.C Requirement Re-Attestation   ← all 36 v49.0 REQ-IDs attested at closure
## 4. Adversarial-Pass Disposition  ← FOLD from 333-02
   ### §4.1 Outcome / §4.2 FINDING_CANDIDATEs / §4.3 SAFE_BY_DESIGN rows / §4.4 Skeptic-Reviewer Filter Attestation
## 5. LEAN Regression Appendix      ← FOLD 333-01 regression attestation (666/42/17, cite the v49 ledger)
## 6. KI Gating Walk + KNOWN-ISSUES.md Re-Verification  (attest KNOWN-ISSUES byte-unmodified vs v48)
## 7. Prior-Artifact Cross-Cites    (329..332 phase artifacts + v44/v46/v47/v48 FINDINGS templates)
## 8. Forward-Cite Closure          (carry the v44 §9d 135-anchor register unchanged; record the v49.1/v50 seeds)
## 9. Milestone Closure Attestation
   ### 9a. Closure Verdict           (locked-target verdict + actual; amended only if a FINDING_CANDIDATE survived)
   ### 9b. 5-Phase Wave Summary      (329/330/331/332/333) + closure signal
   ### 9c. Closure Signal            MILESTONE_V49_AT_HEAD_<sha> + the verbatim propagation-target list
   ### 9d. Deferred Register         (the SWAP cash-share advisory carried-forward-unmodified per D-05;
                                       the v49.1/v50 seeds; "0 NEW findings deferred" if clean)
```
Frontmatter fields to mirror (adapt): `milestone: v49.0`, `audit_baseline: 0cc5d10f...`, `audit_baseline_signal: MILESTONE_V48_AT_HEAD_0cc5d10f...`, `source_tree_frozen_ref: 4c9f9d9b`, `audit_subject_head: "MILESTONE_V49_AT_HEAD_<sha>"` (placeholder), `closure_signal: MILESTONE_V49_AT_HEAD_<sha>` (placeholder), `deliverable: audit/FINDINGS-v49.0.md`, `new_findings: <count from 333-02>`, `new_findings_disposition: ...`.

### 5. The closure signal §9c propagation-target list (BATCH-03)
```
# Source: FINDINGS-v48.0 §9c (verbatim mechanic). The MILESTONE_V49_AT_HEAD_<sha> placeholder
#   resolves to the closure commit's OWN SHA and propagates VERBATIM to:
1. FINDINGS-v49.0.md frontmatter (closure_signal + audit_subject_head)
2. FINDINGS-v49.0.md §1 Audit Subject prose
3. FINDINGS-v49.0.md §9b / §9c references
4. ROADMAP.md            (v49.0 milestone flip + Phase 333 → Complete + Progress table row)
5. STATE.md              (Last Shipped Milestone move + signal + verdict + clear stale "Next:")
   MILESTONES.md         (prepend the v49.0 archive entry above the v48.0 block)
   PROJECT.md            (Current Milestone → v49.0 shipped)
6. REQUIREMENTS.md       (all 36 v49.0 REQ rows → closure attestation;
                          the 14 already-Complete [329 SPEC 4 + 331 GAS 5 + 332 TST 5] stay;
                          the 18 IMPL Pending [330] + the 4 TERMINAL [SWEEP-01/02/03 + BATCH-03] flip)
# Final: grep -q "MILESTONE_V49_AT_HEAD_<sha>" → must find ZERO literal <sha> tokens.
```

## State of the Art

| Old Approach (older precedent) | Current Approach (v48 actual — the immediate precedent) | When Changed | Impact |
|--------------------------------|---------------------------------------------------------|--------------|--------|
| 2-commit sequential-SHA closure (D-10 / brief wording, carried from v44/v46/v47) | **SINGLE-commit** self-referential closure (`57a796d1`: emit + flip + chmod 444 in one commit; signal = the commit's own SHA `0cc5d10f`) | v48 / Phase 328 | Mirror single-commit; both yield the self-referential SHA. Low-stakes. [VERIFIED] |
| Worktrees for parallel plans | **sequential-on-main, NO worktrees** (332 precedent: submodule + node_modules constraint; `no_worktree_paths:["contracts"]` is moot here since 333 touches no contracts) | 332 (D-12) | The read-only logs (333-01∥333-02) can still run as a parallel wave conceptually, but execute on main; the closure flip (333-04) must be atomic on main |

**Deprecated/outdated:**
- The brief's "skills live in `.claude/skills/`" — WRONG; they live in `$HOME/.claude/skills/`. [VERIFIED]
- The brief's "Current HEAD = `95aaf340`" — stale; HEAD is now `830eff56` (2 doc commits since). The frozen-subject guard does not depend on HEAD's SHA. [VERIFIED]
- The 332-CONTEXT pre-execution "16 deletions" estimate — became **17** at execution; use the ledger. [D-09]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Single-commit closure orchestration (mirroring v48 actual) is preferable to a strict-D-10 2-commit split | Pitfall 1 / State of the Art | LOW — both produce the same self-referential signal; the planner/user can choose either. Surfaced as a discretionary detail. |
| A2 | The 5-doc atomic flip targets (ROADMAP/STATE/MILESTONES/PROJECT/REQUIREMENTS) are unchanged from v48 | Pattern 4 / Code Examples §5 | LOW — verified against FINDINGS-v48 §9c + 328-04-PLAN.md; these are the locked BATCH-03 targets in CONTEXT D-10 |
| A3 | The v49 per-phase FINDINGS §3 sub-sections map 329=SPEC/330=IMPL/331=GAS/332=TST/333=TERMINAL (5 phases vs v48's 4) | Code Examples §4 | LOW — derived from REQUIREMENTS traceability; §9b becomes a 5-phase wave summary |

**Note:** No `[ASSUMED]` claim here is load-bearing for safety/compliance. The contract-security attestations (the 4 invariants, OPEN-E, VRF-freeze) are all cross-referenced to VERIFIED proofs (329-SPEC, TST-01/02, the ledger) — they are re-attestations of locked facts, not new assumptions.

## Open Questions (RESOLVED)

1. **Single-commit vs 2-commit closure orchestration**
   - What we know: v48 (the immediate precedent) used single-commit; D-10/brief say "2-commit".
   - What's unclear: whether the user wants strict D-10 literalism or the v48 actual.
   - **RESOLVED:** mirror the v48 single-commit actual (simpler, immediate precedent); the planner may note both in 333-04 and let the closure executor pick. Either way the signal = the closure commit's own SHA, propagated verbatim, grep-zero verified. Not a blocker — 333-04 implements this.

2. **Does any v49 FINDING_CANDIDATE need a pre-staged fix design?**
   - What we know: D-04 says a surviving MEDIUM+ defaults to DEFER→v50 with the fix design locked at the USER closure gate.
   - What's unclear: nothing — the working target is `0 NEW_FINDINGS` (D-03). If the sweep surfaces a candidate, the USER adjudicates at the 333-04 gate.
   - **RESOLVED:** plan for the clean-closure outcome (0 candidates); the 333-04 Task 1 gate already routes any candidate to USER adjudication without a contract fix in-phase.

## Project Constraints (from MEMORY + feedback files; no project-local CLAUDE.md exists)

> No `./CLAUDE.md` in the repo. The global `$HOME/.claude/CLAUDE.md` (self-check before delivering) + the MEMORY feedback files govern. The directives below are the ones that bind Phase 333.

- **No contract commits without hand-review** [feedback_wait_for_approval / feedback_manual_review_before_push]. MOOT here — 333 makes ZERO `.sol` edits. The commit-guard hook does NOT block (no `.sol` in the diff). The `autonomous:false` 333-04 Task 1 gate is the closure-verdict review, not a contract review.
- **Nothing pushed** [feedback_manual_review_before_push + CONTEXT posture]. The closure commits locally; never `git push`.
- **`.planning/` is gitignored → force-add planning docs** at commit time [feedback_contract_commit_guard_hook]. `audit/FINDINGS-v49.0.md` is tracked (not gitignored).
- **Commands shown to the user use the HYPHEN form** (`/gsd-execute-phase`, `/contract-auditor`), not the colon form [feedback_slash_command_hyphen_form].
- **Co-Authored-By trailer** on the closure commit per the global convention.
- **Security/RNG-non-manipulability is the hard floor** [feedback_security_over_gas]. The sweep re-attests VRF-freeze + the 4 invariants; a surfaced security defect is surfaced (DEFER/FIX), never silently accepted for gas.
- **Comments describe what IS, not what changed** [feedback_no_history_in_comments]. MOOT (no contract edits), but applies if any doc prose describes the subject.

## Sources

### Primary (HIGH confidence)
- `.planning/phases/333-.../333-CONTEXT.md` — the locked decisions D-01..D-13 (the spine)
- `.planning/milestones/v48.0-phases/328-.../328-01-PLAN.md`, `328-02-PLAN.md`, `328-03-PLAN.md`, `328-04-PLAN.md` — the 4 structural templates (read in full)
- `audit/FINDINGS-v48.0.md` — the 9-section layout + frontmatter + §9a/§9b/§9c closure pattern (headers + frontmatter + §9 read)
- `.planning/REQUIREMENTS.md` — SWEEP-01/02/03 + BATCH-03 wording (lines 53-61) + the 36-req traceability table
- `.planning/ROADMAP.md` — Phase 333 goal + the 4 Success Criteria (lines 119-127)
- `.planning/MILESTONES.md` — the v48.0 archive block (the prepend format)
- git anchors VERIFIED 2026-05-27: `git diff 4c9f9d9b HEAD -- contracts/*.sol` EMPTY; `git diff --stat 0cc5d10f 4c9f9d9b -- contracts/` = 5 files +376/-226; HEAD = `830eff56`; the 2 v49 contract commits `63bc16ca` + `4c9f9d9b`; `$HOME/.claude/skills/{contract-auditor,zero-day-hunter,economic-analyst}/SKILL.md` all exist; `.claude/skills/` does NOT exist; `config.json` `nyquist_validation:false` + `use_worktrees:true`/`no_worktree_paths:["contracts"]`
- `test/REGRESSION-BASELINE-v49.md` — cited as authoritative (666/42/17) per D-09 (not re-read; the ledger is the authority)

### Secondary (MEDIUM confidence)
- MEMORY.md topic indices ([[v49-keeper-router-redesign]], [[open-e-operator-approval-trust-boundary]], [[v45-vrf-freeze-invariant]]) — for the invariant cross-refs; the authoritative sources are 329-SPEC + the TST proofs

### Tertiary (LOW confidence)
- None. Every claim is grounded in a read file or a verified git command.

## Metadata

**Confidence breakdown:**
- Plan shape / mechanics: HIGH — 4 verbatim templates read; the pattern is on its 4th repetition
- Frozen-subject + blast-radius anchors: HIGH — all verified via git this session
- Closure orchestration: HIGH (mechanic) / MEDIUM (single-vs-2-commit choice) — v48 actual verified; D-10 wording diverges (documented as A1)
- v49-specific extra attestations (D-06): HIGH — sourced directly from CONTEXT D-06 + REQUIREMENTS GASOPT-05 + 329-SPEC invariant list
- Pitfalls: HIGH — derived from verified divergences (skill path, stale HEAD, ledger count, commit model)

**Research date:** 2026-05-27
**Valid until:** until the next contract commit advances HEAD past the frozen subject (the frozen-subject guard `git diff 4c9f9d9b HEAD -- contracts/` must stay empty — re-verify before the closure commit per T-CONTRACTS). The precedent templates are stable.
