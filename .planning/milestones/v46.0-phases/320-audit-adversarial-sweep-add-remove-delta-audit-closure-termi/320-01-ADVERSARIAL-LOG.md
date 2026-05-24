# Phase 320 Adversarial-Sweep Integrated Log — v46.0 Do-Work Crank + AfKing Auto-Rebuy Subscription + Legacy AFKing/ETH-Auto-Rebuy Removal (TERMINAL)

**Phase:** 320-audit-adversarial-sweep-add-remove-delta-audit-closure-termi
**Plan:** 01
**Integrated:** 2026-05-24
**Audit baseline:** v45.0 closure HEAD `MILESTONE_V45_AT_HEAD_62fb514bfcc8ad042a45cef960e5ff0ff6fbb801`
**Subject under probe:** v46.0 audit-subject HEAD — the batched Phase 317 ADD+REMOVE diff (`df4ef365`) + the 317-08 keeper/slot family + the Phase 319.1 OPEN-E diff (`42140ceb` + WR-01 `e1baa978`) + the Phase 319 GAS pegs (`e4014f91` + CR-01 `795e679d`) + the JGAS jackpot-split removal. SOURCE-TREE FROZEN reference: phase-start HEAD `30b5c89c` (contracts/+test/ byte-frozen since).

---

## §0 Invocation + Frame

**Composition (D-05 ADAPTIVE PARALLEL→HYBRID; realized = genuine PARALLEL_SUBAGENT):**
- **`/contract-auditor`** — dispatched FIRST as the sequential anchor subagent (runner: task-subagent); its MD anchored the parallel pair. Owns the structural/authority surface (SWP-AUTH, the SWP-OPENE four D-03 residual structural charges, SWP-REMOVE grep-clean + JGAS single-call).
- **`/zero-day-hunter` + `/economic-analyst`** — **PARALLEL_SUBAGENT** (dispatched as a single-message multi-Task block of two `Agent` calls). The Phase 320 sweep ran in the main orchestrator context, which DOES hold the Task tool, so genuine PARALLEL_SUBAGENT was the realized mode (mirroring v45 P314, NOT the HYBRID-fallback v42/v43/v44 used when the executor lacked Task). Both received the auditor MD + verbatim CHARGE as anchoring context. No fallback triggered. Each independently re-confirmed the OPEN-E audit subject (`grep -c fundingSource contracts/AfKing.sol == 21`), guarding against the stale pre-OPEN-E worktree copy.

**Out-of-scope skills (D-271-ADVERSARIAL-02 carry):** `/degen-skeptic`.
**In-scope skills (D-271-ADVERSARIAL-03 carry):** `/economic-analyst`.

**Governance applied:**
- **D-302-CONSENSUS-01 (carry)** — two-tier consensus (Tier-1 user-pause + Tier-2 auto-elevate + RE-PASS).
- **Dual-gate skeptic filter** (operationalizing `feedback_skeptic_pass_before_catastrophe`) — per-skill self-filter + orchestrator integration-time re-application; strict structural-protection arm (literal physical unreachability only); 3-condition EV lens with (a)-only hard discard, (b)+(c) severity-adjust.
- **Mutations policy** — zero `contracts/*.sol` + zero `test/*.sol` mutations during the pass (audit-only). The RE-PASS escape hatch was the ONLY path to a contract touch; **it was NOT taken in v46.0** — see §8 (the one surviving FINDING_CANDIDATE was USER-adjudicated to DEFER-to-v47.0 with the fix locked, keeping v46.0 SOURCE-TREE FROZEN).

**Per-skill invocation modes:**

| Skill | Mode | Runner | Self-discards | OPEN-E subject (fundingSource grep) |
| --- | --- | --- | --- | --- |
| `/contract-auditor` | PARALLEL_SUBAGENT (sequential anchor, dispatched first) | task-subagent | 0 | 21 |
| `/zero-day-hunter` | PARALLEL_SUBAGENT | task-subagent | 0 | 21 |
| `/economic-analyst` | PARALLEL_SUBAGENT | task-subagent | 0 | 21 |

---

## /contract-auditor

Source MD: `.planning/phases/320-.../320-ADVERSARIAL-CONTRACT-AUDITOR.md` · Invocation: `PARALLEL_SUBAGENT` (anchor) · Self-discards: 0

**Disposition summary (full table + evidence anchors in source MD §1):**

| Hypothesis-ID | Verdict | Severity | Cross-skill |
| --- | --- | --- | --- |
| SWP-AUTH.burnForKeeper-ACL (`onlyAfKing`) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-AUTH.burnForKeeper-all-or-nothing (capacity check precedes state change) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-AUTH.creditFlip-ACL (`onlyFlipCreditors`) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-AUTH.creditFlip-one-per-tx (single bounty credit) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-AUTH.batchPurchase-keeper-gate (`:1692` AF_KING gate + `rngLockedFlag`) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-AUTH.batchPurchase-try/catch-strand-or-double-credit | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-OPENE.1 — no cross-account draw without consent (`:397-403` gate) | NEGATIVE-VERIFIED | N-A (bar: CATASTROPHE) | unanimous |
| SWP-OPENE.2 — default-self byte-identical (`address(0)` short-circuits `&&`) | NEGATIVE-VERIFIED | N-A (bar: FINDING) | unanimous |
| SWP-OPENE.3 — no escalation / no skip-kill spoof | NEGATIVE-VERIFIED | N-A (bar: FINDING) | consensus w/ hunter |
| SWP-OPENE.4 — trust-the-sub temporal bound | **SAFE_BY_DESIGN** | N-A | consensus w/ economist |
| SWP-OPENE.D-02 — BURNIE-funding overload | **SAFE_BY_DESIGN** | N-A | consensus w/ economist |
| SWP-REMOVE.A — ETH-auto-rebuy strand + RM kill-set grep-clean (ZERO) | NEGATIVE-VERIFIED | N-A | consensus w/ hunter |
| SWP-REMOVE.B — BURNIE 75bps collapse (no under/over-credit) | NEGATIVE-VERIFIED | N-A | consensus w/ economist |
| SWP-REMOVE.C — JGAS single-call + JGAS kill-set grep-clean (ZERO) | NEGATIVE-VERIFIED | N-A | consensus w/ hunter |

**Auditor summary:** 14 rows — 12 NEGATIVE-VERIFIED + 2 SAFE_BY_DESIGN; 0 FINDING_CANDIDATE; 0 self-discards. All four D-03 OPEN-E structural charges proven closed at `subscribe()` (the `:397-403` `isOperatorApproved`+`revert NotApproved` gate is the sole, subscribe-only auth; `address(0)` short-circuits to self). RM + JGAS kill sets grep-clean (ZERO); the only surviving afKing-named symbol is the kept `hasAnyLazyPass` (PROTO-01/RM-04, `DegenerusGame.sol:1472`). JGAS daily-ETH resolves single-call at the 305 ceiling, no resume stage.

---

## /zero-day-hunter

Source MD: `.planning/phases/320-.../320-ADVERSARIAL-ZERO-DAY-HUNTER.md` · Invocation: `PARALLEL_SUBAGENT` · Self-discards: 0

**Disposition summary (full table + evidence anchors in source MD §1):**

| Hypothesis-ID | Verdict | Severity | Cross-skill |
| --- | --- | --- | --- |
| SWP-GRIEF.faucet-roundtrip (bounty ≤ 0 self-crank) | NEGATIVE-VERIFIED | N-A | consensus w/ economist |
| SWP-GRIEF.unwanted-charge-timing (subscription-trigger griefing) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-GRIEF.depositFor-manipulation | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-SKIP.normal-sub-spoofs-exemption (`:729` keys on un-spoofable `player`) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-OPENE.3 — escalation / redirect-to-different-address | NEGATIVE-VERIFIED | N-A (bar: FINDING) | consensus w/ auditor |
| SWP-OPENE.3 — redirect spoofs skip-kill exemption (`:729` keys `player` not `src`) | NEGATIVE-VERIFIED | N-A (bar: FINDING) | consensus w/ auditor |
| SWP-REMOVE.ETH-auto-rebuy-strand (`_addClaimableEth` per winner) | NEGATIVE-VERIFIED | N-A | consensus w/ auditor |
| SWP-REMOVE.JGAS-resumeEthPool-strand (single `_processDailyEth`, conservation) | NEGATIVE-VERIFIED | N-A | consensus w/ auditor |
| SWP-COMPOSE.crank×removed-rebuy×OPENE-redirect (CEI debit before batchPurchase) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-COMPOSE.JGAS-single-call×crank-reward-claimable-race (rngLocked aborts whole-tx) | NEGATIVE-VERIFIED | N-A | unanimous |
| **SWP-COMPOSE.swap-pop-cancel-relocates-unprocessed-entry-behind-cursor (H-CANCEL-SWAP-MISS)** | **FINDING_CANDIDATE** | **MEDIUM** (revised up from LOW — §7) | **Tier-1 (single skill)** |

**Hunter summary:** 11 rows — 10 NEGATIVE-VERIFIED + **1 FINDING_CANDIDATE** (H-CANCEL-SWAP-MISS); 0 self-discards. The novel/composition vectors are clean EXCEPT the cancel-relocation: external cancel `setDailyQuantity(0)` (`AfKing.sol:459`) calls `_removeFromSet` (swap-pop, `:825-837`) immediately, relocating an unprocessed tail subscriber behind a persisted mid-day `_sweepCursor` → that sub misses one day's auto-buy. This regresses the LOCKED SUB-07 "external cancel moves nothing" (`316-SPEC.md:152`). See §7/§8.

---

## /economic-analyst

Source MD: `.planning/phases/320-.../320-ADVERSARIAL-ECONOMIC-ANALYST.md` · Invocation: `PARALLEL_SUBAGENT` · Self-discards: 0

**Disposition summary (full table + evidence anchors in source MD §1):**

| Hypothesis-ID | Verdict | Severity | Cross-skill |
| --- | --- | --- | --- |
| SWP-ECON.recycle-loop (0.984×1.0075 ≈ 0.991 < 1; no perpetual loop) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-ECON.crank-self-fund-recycle (deferred negative-EV 50/50 stake) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-ECON.supply-ceiling (COINFLIP-gated `mintForGame` behind 50/50) | NEGATIVE-VERIFIED | N-A | unanimous |
| SWP-SKIP.funding-margin-griefer (kill predicate = victim's own pool vs own cost) | NEGATIVE-VERIFIED | N-A | consensus w/ hunter |
| SWP-OPENE.4 — trust-the-sub bounded drain | **SAFE_BY_DESIGN** | N-A | consensus w/ auditor |
| SWP-OPENE.D-02 — BURNIE-funding overload cost/benefit | **SAFE_BY_DESIGN** | N-A | consensus w/ auditor |
| SWP-REMOVE.B — 0.75% recycle collapse rounding/scaling residue | NEGATIVE-VERIFIED | N-A | consensus w/ auditor |
| BC.1 (beyond-charge) — stall-multiplier timing-MEV | NEGATIVE-VERIFIED | N-A | unanimous |
| BC.2 (beyond-charge) — reinvestPct claimable-recycle inflation | NEGATIVE-VERIFIED | N-A | unanimous |

**Economist summary:** 9 rows — 7 NEGATIVE-VERIFIED + 2 SAFE_BY_DESIGN; 0 FINDING_CANDIDATE; 0 self-discards. The crank bounty is a negative-EV deferred 50/50 coinflip stake (≈0.984× face); the 0.75% recycle is floor-rounded + capped + below the ~1.6% flip house edge (no loop); BURNIE supply throttled by the COINFLIP-gated mint behind the 50/50; the funding-margin kill predicate is caller-independent (the victim's own pool vs own cost — griefer EV-lens condition (a) fails); the trust-the-sub drain is bounded (sub lifetime + S-defunding + M-cancel) and the D-02 overload is consensual under D-01.

---

## §5 — Skeptic-Filter Discarded inline table

**Orchestrator integration-time re-application of the dual-gate filter** against the union of all 3 skills' FINDING_CANDIDATE sets (union size = 1: H-CANCEL-SWAP-MISS).

Per-skill self-discards (verbatim from each MD's `[skeptic-filter]` `discarded` array):
- `/contract-auditor`: `discarded: []`
- `/zero-day-hunter`: `discarded: []`
- `/economic-analyst`: `discarded: []`

Integration-time evaluation of H-CANCEL-SWAP-MISS:
- **Structural-protection arm (STRICT):** NOT discarded. The attack/miss is literally reachable — `setDailyQuantity(0)` is callable any time, `_removeFromSet` unconditionally swap-pops, and the relocation behind a persisted cursor is a concrete state the canceller reaches. It even manifests on a fully *legitimate* mid-day cancel (no attacker required). No literal physical unreachability → no discard.
- **EV-lens (a):** NOT a hard discard. As a *targeted* grief, (a) is weak (the swap moves whoever is the tail, not a chosen victim; the attacker forfeits its own sub). BUT the underlying correctness break — a relocated-behind-cursor pending entry being skipped — manifests **without any attacker**, so the "no exploitable scenario can be constructed" hard-discard does not apply.
- **(b)+(c):** severity-ADJUST only — see §7 (revised UP, not down, on the streak impact).

Orchestrator integration-time additional discards: **0** (the one FINDING_CANDIDATE survived the dual-gate filter and routed to Tier-1).

| Hypothesis-ID | Source skill | Structural-protection citation | EV-lens failed condition | Note |
| --- | --- | --- | --- | --- |
| (none) | (n/a) | (n/a) | (n/a) | Zero per-skill self-discards; H-CANCEL-SWAP-MISS survived the dual-gate filter (reachable; (a) does not hard-discard). |

---

## §6 — Integrated Disposition table (survivors only)

**Survivors = (union of all 3 skills' verdicts) − (Skeptic-Filter Discarded).** Discarded = 0; survivor count = **34 rows** (14 auditor + 11 hunter + 9 economist).

Aggregated by verdict:

| Verdict | Count |
| --- | --- |
| NEGATIVE-VERIFIED | 29 |
| SAFE_BY_DESIGN | 4 |
| FINDING_CANDIDATE | **1** |

**Surviving FINDING_CANDIDATE rows:**

| Hypothesis-ID | Source skill | Verdict | Severity tag | (b)+(c) rationale | Cross-skill consensus state |
| --- | --- | --- | --- | --- | --- |
| H-CANCEL-SWAP-MISS (SWP-COMPOSE.swap-pop-cancel-relocates-unprocessed-entry-behind-cursor) | /zero-day-hunter | FINDING_CANDIDATE | **MEDIUM** | (b) measurable: the relocated sub loses a day's auto-buy → mint-streak reset (up to −50% activity-score multiplier); (c) negative-EV as a deliberate grief but the correctness break fires on legitimate cancels too → severity revised UP, not down | **Tier-1 (single skill)** → user-pause → DEFER-to-v47.0 |

**SAFE_BY_DESIGN rows (informational — intentional protocol behaviors, NOT findings):**

| Hypothesis-ID | Source skill(s) | Rationale (D-01 trust boundary) |
| --- | --- | --- |
| SWP-OPENE.D-02 — BURNIE-funding overload | /contract-auditor + /economic-analyst | The operator-approval grant authorizes burning the source's general-wallet BURNIE + pending coinflip. Consensual by construction under D-01 (operator-approval IS the trust boundary; grantee = same person or a fixed/known contract). `allowBurnieFunding` flag DROPPED per D-02a. ACCEPTED-BY-DESIGN, not elevated. |
| SWP-OPENE.4 — trust-the-sub temporal bound | /contract-auditor + /economic-analyst | A later `setOperatorApproval(M,false)` revoke does NOT retroactively stop an active sub; the drain is BOUNDED by sub lifetime + S-defunding (`_poolOf` ETH / spending down BURNIE) + M-cancel. The by-design posture is the accepted bound, not a defect. |

---

## §7 — Severity-Revision Rationale table

The (b)+(c) arm adjusts the severity tag of surviving FINDING_CANDIDATE rows. The single surviving row was revised **UP** (the streak impact, surfaced at the Tier-1 user-pause, made the original LOW tag understate the harm).

| Hypothesis-ID | Original severity | Revised severity | Driving (b)/(c) signal | Rationale |
| --- | --- | --- | --- | --- |
| H-CANCEL-SWAP-MISS | LOW (zero-day self-tag: "1-day self-healing liveness miss, no fund loss, no double-buy") | **MEDIUM** | (b) the miss is NOT self-healing where it matters | The sweep *cursor* self-heals next day, but a skipped daily auto-buy = a skipped level mint → the per-consecutive-level mint streak (`DegenerusGameMintStreakUtils.sol` `_mintStreakEffective`, resets if a level is missed) RESETS to 0 → up to a **+50% activity-score multiplier permanently lost** for an innocent subscriber. Fires on any legitimate mid-day cancel behind the cursor. The original LOW under-weighted the streak; MEDIUM (arguably HIGH depending on the activity-score's economic weight). |

---

## §8 — Two-tier consensus verdict + adjudication

**Surviving FINDING_CANDIDATE rows after dual-gate skeptic filter:** 1 (H-CANCEL-SWAP-MISS).

| Tier | Definition | Count this pass |
| --- | --- | --- |
| Tier-2 (3-of-3 consensus FINDING_CANDIDATE on same hypothesis) | auto-elevate + RE-PASS per D-284-ADVERSARIAL-RE-PASS-01 | **0** |
| Tier-1 (any-skill FINDING_CANDIDATE after dual-gate filter) | AskUserQuestion user-pause per D-302-CONSENSUS-01 | **1 (H-CANCEL-SWAP-MISS)** |
| unanimous-NEGATIVE (no FINDING_CANDIDATE survives) | no elevation, no user-pause | n/a (1 survived) |

**Verdict: 1 Tier-1 MEDIUM FINDING_CANDIDATE — USER-adjudicated DEFER-to-v47.0 (fix locked).**

- H-CANCEL-SWAP-MISS was raised by a single skill (`/zero-day-hunter`) → Tier-1, NOT the Tier-2 3-of-3 auto-elevate. (The auditor's SWP-SKIP hand-off and the economist's funding-margin row touched the adjacent kill-predicate but did not independently surface the cancel-relocation, so consensus is single-skill.)
- The orchestrator verified the finding against source before the user-pause: `setDailyQuantity(0)` (`AfKing.sol:455-468`) → `_removeFromSet` swap-pop (`:825-837`); the LOCKED SUB-07 (`316-SPEC.md:152` / `REQUIREMENTS.md:52`) requires external cancel to "move nothing"; the IMPL also omitted the in-sweep `dailyQuantity==0` reclaim branch. Confirmed genuine IMPL-vs-LOCKED-SPEC divergence.
- **Tier-1 AskUserQuestion user-pause (2026-05-24): USER ADJUDICATED → DEFER-with-fix-locked-to-v47.0.** Rationale: (1) the fix direction is LOCKED — "don't move anyone, let the next sweep handle it" = restore the SUB-07 in-place tombstone + add the in-sweep tombstone-reclaim branch; (2) do NOT break v46.0 SOURCE-TREE FROZEN for it — the fix lands in the v47.0 single batched contract diff (the milestone whose contract surface is next to open). The finding is RECORDED in `audit/FINDINGS-v46.0.md` §4 and the v47.0 handoff.

**RE-PASS gate (in v46.0): NOT triggered.** The user chose DEFER, not elevate-in-v46. No `320-FIXREC-AUGMENT.md` authored for v46; no v46 RE-PASS dispatched; **zero `contracts/*.sol` + zero `test/*.sol` mutation in v46.0** — SOURCE-TREE FROZEN HELD. The fix is captured for v47.0 in `.planning/PLAN-V47-AFKING-CANCEL-TOMBSTONE.md` (v47.0 manifest item 7, an ISOLATED `AfKing.sol`-only surface) and registered in [[afking-cancel-tombstone-streak-finding]].

---

## §9 — Forward-cite placeholder for FINDINGS-v46.0.md §4 (Plan 04)

Plan 04 (320-04) resolves this forward-cite at the FINDINGS assembly. `audit/FINDINGS-v46.0.md` §4 reads this LOG's §6 integrated Disposition + §5 Skeptic-Filter Discarded + §7 Severity-Revision + §8 two-tier consensus verdict and writes the §4 adversarial-pass disposition section, recording:
- 3-skill genuine PARALLEL_SUBAGENT composition (no HYBRID-fallback; orchestrator held the Task tool).
- **34 disposition rows: 29 NEGATIVE-VERIFIED + 4 SAFE_BY_DESIGN + 1 FINDING_CANDIDATE.**
- The 1 FINDING_CANDIDATE = **H-CANCEL-SWAP-MISS (MEDIUM)**, Tier-1, USER-adjudicated DEFER-to-v47.0 (fix locked; SOURCE-TREE FROZEN held in v46.0).
- The four D-03 OPEN-E residual structural charges PROVEN; the D-02 BURNIE overload + the SWP-OPENE.4 trust-the-sub bound recorded SAFE_BY_DESIGN.
- Closure-verdict alignment: the locked `0 NEW_FINDINGS` clause is AMENDED to record the 1 deferred MEDIUM finding.

**`<FINDINGS-v46.0-§4-CROSS-CITE-PLACEHOLDER>`** — resolved at Plan 04 assembly.

---

## §10 — Phase Summary

**Phase 320 Adversarial Sweep COMPLETE — 1 Tier-1 MEDIUM finding (H-CANCEL-SWAP-MISS), USER-adjudicated DEFER-to-v47.0; otherwise clean.**

The v46.0 audit subject — the new `AfKing.sol` keeper (do-work crank + subscription + OPEN-E funding-source), the legacy-AFKing/ETH-auto-rebuy REMOVE, the JGAS jackpot-split removal, and the GAS pegs — survives the 3-skill adversarial gate with **1 FINDING_CANDIDATE across 34 enumerated disposition rows** (29 NEGATIVE-VERIFIED + 4 SAFE_BY_DESIGN + 1 FINDING_CANDIDATE).

Key structural protections confirmed:
- **OPEN-E four D-03 residual charges PROVEN** — cross-account draw reverts `NotApproved` at the subscribe-only `:397-403` gate (SWP-OPENE.1); `fundingSource==0` short-circuits to self, same single `_poolOf` slot, per-draw gas unchanged (SWP-OPENE.2); no redirect-to-a-different-non-approving-address and no source-keyed skip-kill spoof — the exemption keys on the un-spoofable `player`/subscriber identity at `:729`, never `src` (SWP-OPENE.3); the trust-the-sub drain is BOUNDED (SWP-OPENE.4, SAFE_BY_DESIGN).
- **D-02 BURNIE-funding overload SAFE_BY_DESIGN** — consensual under the D-01 operator-approval trust boundary; `allowBurnieFunding` DROPPED.
- **Authority surface clean** — `burnForKeeper` `onlyAfKing` + all-or-nothing (capacity check precedes state change); `creditFlip` `onlyFlipCreditors` + one bounty per tx; `batchPurchase` AF_KING-gated + per-player try/catch slice-refund (no strand, no double-credit).
- **REMOVE clean** — RM + JGAS kill sets grep-clean (ZERO); ETH winnings always credit to claimable; flat 75bps no under/over-credit; JGAS daily-ETH single-call at the 305 ceiling, no resume stage, nothing stranded by the dropped `resumeEthPool` carry.
- **Faucet bounded / griefing clean** — self-crank bounty ≤ 0; subscription-trigger and funding-margin griefs are caller-independent / negative-EV; no recycle loop; BURNIE supply throttled.

**The one crack: H-CANCEL-SWAP-MISS (MEDIUM).** External cancel swap-pops immediately instead of the LOCKED SUB-07 in-place tombstone, relocating an unprocessed tail behind a persisted mid-day cursor → that sub misses a day → mint-streak reset (up to −50% activity score). USER-adjudicated DEFER-to-v47.0 with the fix locked; v46.0 SOURCE-TREE FROZEN held (zero contracts/+test/ mutation). The v46.0 closure verdict's `0 NEW_FINDINGS` clause is amended accordingly at Plan 04.

RE-PASS (elevation) NOT triggered in v46.0 — the finding deferred to the v47.0 batched diff per the user adjudication. Plan 04 consolidates this LOG into `audit/FINDINGS-v46.0.md` §4.

---

*Integrated log authored 2026-05-24. All 3 per-skill MDs + this LOG are planner-private artifacts under `.planning/phases/320-*/`. Source-tree frozen throughout (zero contracts/+test/ mutation); the one finding routes to v47.0 per `.planning/PLAN-V47-AFKING-CANCEL-TOMBSTONE.md`.*
