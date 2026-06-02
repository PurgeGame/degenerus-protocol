# Phase 357: TERMINAL — Delta Audit + 3-Skill Adversarial Sweep + FINDINGS-v56.0 + Closure Flip - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-06-02
**Phase:** 357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw
**Areas discussed:** F-356-01 fix sequencing, Push posture at close, XMODEL close, 5cb707f2 scope, Afking sub-hardening (pass-gate + purchase-grounding), Protocol-sub exemption

---

## F-356-01 fix sequencing

| Option | Description | Selected |
|--------|-------------|----------|
| Fix-first, audit the fixed subject | Author the fix at a USER-approved gate FIRST, re-run NON-WIDENING, re-freeze HEAD', then audit | ✓ |
| Audit-first, fix documented then landed | Freeze at 356 HEAD, document F-356-01 as a §4 finding, land the fix at the closure gate | |
| Separate mini-IMPL phase for the fix | Insert a dedicated tiny IMPL phase, keep 357 pure DOC-ONLY | |

**User's choice:** Fix-first, audit the fixed subject.
**Notes:** Closure HEAD = the actually-shippable subject (audited == shipped). The fix gate later
absorbed the two USER-directed hardening gates (see below) → 357-00 is a three-change contract gate.

---

## Push posture at close

| Option | Description | Selected |
|--------|-------------|----------|
| Close-and-stop (standing rule) | Apply the flip locally; pushing is a separate explicit USER step | |
| Close-then-prompt-to-push | Close locally, then at the gate flag the live contract is broken + offer to push, wait for GO | ✓ |

**User's choice:** Close-then-prompt-to-push.
**Notes:** Unlike every prior milestone ("nothing pushed"), the v56 contract subject (354+355) is
ALREADY public on origin/main and currently broken (affiliate rewards unreachable). The closure gate
must surface this + offer to push the fix + 5cb707f2 + the close, gated on explicit go-ahead. Nothing
auto-pushed.

---

## XMODEL Codex + Gemini close

| Option | Description | Selected |
|--------|-------------|----------|
| Best-effort augmentation | Claude 3-skill = primary gate; Codex + Gemini augment; CLI unavailable does NOT block | ✓ |
| Hard-gate (must produce dispositions) | Both Codex AND Gemini must run; closure HALTS if a CLI is unavailable | |

**User's choice:** Best-effort augmentation.
**Notes:** Matches XMODEL-01's "augment the TERMINAL adversarial close" wording; the cross-model close
is additive assurance, not a hard dependency on external tooling.

---

## 5cb707f2 (active-sub mustMintToday bypass) scope

| Option | Description | Selected |
|--------|-------------|----------|
| In-scope v56 surface, re-attest unmanipulable | Attribute the 8-line hunk AND charge the sweep to re-verify the advance-gate change | ✓ |
| Delta-audit attribution only | Attribute in the delta but no dedicated sweep effort | |

**User's choice:** In-scope v56 surface, re-attest unmanipulable.
**Notes:** Post-hardening the sweep re-attests the bypass is now SOUND (every active sub is a
pass-holding, purchase-grounded participant → no unfunded free-rider can claim it).

---

## Afking sub-hardening — phase structure

| Option | Description | Selected |
|--------|-------------|----------|
| Fold into the 357-00 contract gate | Bundle pass-gate + grounding + the F-356-01 stub into ONE gate, then audit the hardened subject | ✓ |
| Dedicated IMPL phase before 357 | Insert a focused hardening IMPL phase, keep 357 a clean audit-close | |

**User's choice:** Fold into the 357-00 contract gate.
**Notes:** Triggered by the user's question "does subscribe really not require a pass?" → surfaced that
subscribe is soft-gated (create-then-evict) and that passless/unfunded subs can occupy cap slots +
claim the 5cb707f2 bypass with no real buy.

---

## Afking sub-hardening — pass gate (Directive 1)

| Option | Description | Selected |
|--------|-------------|----------|
| Pass must cover current level | Revert unless `_passHorizonOf(subscriber) >= currentLevel` (deity always); keep crossing eviction | ✓ |
| Holds any pass (horizon > 0) | Revert only if no pass at all (looser) | |

**User's choice:** Pass must cover current level. VAULT/sDGNRS exempt; keep the per-iter crossing
eviction (`:942`) for passes outgrown mid-run.

---

## Afking sub-hardening — purchase grounding (Directive 2)

| Option | Description | Selected |
|--------|-------------|----------|
| Subscribe-time grounding | Revert subscribe unless purchased-today OR funded immediate cover-buy executes; :1124 left as-is | ✓ |
| Also tighten the :1124 advance bypass | Subscribe grounding AND require lastAutoBoughtDay == today at :1124 | |

**User's choice:** Subscribe-time grounding. Kills the unfunded-forfeit path for players; the
`5cb707f2` advance bypass is left as-is (now provably backed by a real buy).

---

## Protocol-sub exemption (Directive 3 — USER follow-up)

**User's statement:** "the protocol subs can be exempt from the must buy today rule."
**Resolution:** "Protocol subs" = `DegenerusVault` (`:483`) + `StakedDegenerusStonk` (`:388`) — the
only two self-subscribers, holding no pass and unfunded at construction. Exempt from BOTH new gates
(pass + must-buy). Load-bearing: naive gating without this exemption reverts their construction-time
self-subscribe and breaks deploy/bootstrap. USER confirmed the must-buy exemption explicitly; the
pass exemption stands identically.

---

## Claude's Discretion

- Plan shape (mirror 352 with a leading contract gate that may split into a contract sub-plan + a
  test-reconciliation sub-plan), sweep topology (genuine-PARALLEL inline), verdict target
  (F-356-01 = the one RESOLVED finding), requirement re-attestation (cite REQUIREMENTS.md), worktrees
  (sequential-on-main), FINDINGS §-structure (mirror v55).
- The exact "purchased today" predicate for D-12 left to IMPL (candidate signals enumerated in CONTEXT).

## Deferred Ideas

None — discussion stayed within scope. Any FINDING_CANDIDATE the sweep surfaces defaults to DEFER→v57
with fix design locked, adjudicated at the USER closure gate. The hardening (D-11/D-12/D-13) may
warrant formal new SEC-* REQ-IDs in REQUIREMENTS.md/ROADMAP before planning so the closure flip
re-attests them — flagged for the user at confirm.
