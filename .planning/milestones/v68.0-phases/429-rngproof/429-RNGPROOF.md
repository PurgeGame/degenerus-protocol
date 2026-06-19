# Phase 429: RNGPROOF — AI-Verifiable RNG-Freeze-at-Commitment Proof

**Milestone:** v68.0
**Completed:** 2026-06-17
**Requirements:** RNGPROOF-01, RNGPROOF-02, RNGPROOF-03, RNGPROOF-04
**Subject:** contracts tree `4970ba5b` (byte-identical to the frozen subject `d0af2984`; includes v67 fixes MIDRNG-02 `73eb242a`, DELEGATE-FIND-01 `095a7ac9`, BRICK gas `2aed5d28`)
**Method:** 9-cluster Workflow (`wf_a30938cb-9c4`, 19 agents) — re-confirm the v66 VRF-consumer net against the v68 frozen tree + formalize each into a machine-checkable freeze certificate (stage 1), then an INDEPENDENT adversarial verifier tries to refute each against current source (stage 2), then synthesis (stage 3).

---

## Deliverables

- **`audit/RNG-FREEZE-PROOF-v68.0.md`** (253 KB) — header (subject/method/totals), 9 per-cluster sections each with a per-consumer table (formal invariant · commitment point `file:line` · consumption site `file:line` · frozen-input enumeration · verification recipe · freezeClass · re-verify verdict), and a Residual/flagged section.
- **`audit/rng-freeze-proof-v68.index.json`** (86 KB) — the machine-readable array of 79 `{id, name, consumptionSite, commitmentPoint, freezeClass, freezeHolds, severityIfBroken, verificationRecipe}` records a future AI/CI re-checks against source. This is the self-verifying artifact.

## Result

- **79 VRF consumers** covered (the v66 net's 67 re-confirmed at HEAD + 12 broken-out/added; no v66 consumer removed). freezeClass: **FROZEN-AT-COMMIT 39 · CROSS-CONTRACT-SEAM 33 · NEEDS-PROOF 5 · MUTABLE-INPUT 2**.
- **freeze invariant HOLDS for 78 / 79.** No catastrophe; no exploitable freeze break on any live-game path.
- The independent re-verifier reproduced each entry's verification recipe against source; spot-checks of the cited `file:line` anchors (the redemption-roll derivation `rngGate:1261-1264`, the prevrandao-fallback twin `:1356-1361`, the `rngWordByDay[day]=finalWord` commitment) match real code — the proof is source-grounded.

## Dispositions (12 flagged / residual)

| ID | Cluster | Sev | Verdict |
|----|---------|-----|---------|
| **RNGF-SEAM-RESOLVE** | sDGNRS-Coinflip | LOW | **The only freezeHolds=false.** Gameover **prevrandao-fallback twin only**: ~1-bit `block.prevrandao` biases the `[25,175]` redemption-roll **MAGNITUDE** (not selection) on a gameover-terminal self-claim, reachable only after a forced ≥14-day total VRF outage. The normal + gameover-normal paths are fully frozen. = the known v66 row-9 / v67 prevrandao-fallback residual, independently re-derived. By-design last-resort liveness; any change is a separate gated contract decision (out of scope here). |
| RNGF-REDEEMSEAM-08 | Game | HIGH-if-broken | **HOLDS** — day+1 redemption word undrawn at submit, frozen before claim is callable. |
| RNGF-FLIPESCROW-09 | Game | HIGH-if-broken | **HOLDS** — coinflip day+1 result undrawn at submit; frozen before payout. |
| RNGF-JKPT-39 / -43 | Jackpot | MED (NEEDS-PROOF) | **HOLD** — unlock-discipline / dailyIdx-disjoint-slot; backed by RngReuseJackpotStraddle 3/3 + DegeneretteHeroScore 6/6 PASS. |
| RNGF-LBX-06 / -07, RNGF-DEGN-34, RNGF-DEC-03, RNGF-JKPT-36 / -37 | various | LOW | **All HOLD** — bounded by-design mutable inputs / drainable-magnitude seam / stale-JS-harness caveats (Foundry backing passes). |
| RNGF-BAF-07 | Jackpots-BAF | INFO | HOLDS; recipe cited a wrong anchor (`:644` vs actual `rngGate:1209-1210`) — doc fix only. |

## Carried follow-on (non-blocking, → 431 CI / minor test hardening)

- Promote `RngReuseJackpotStraddle` to a CI gate (→ 431).
- Un-skip the decimator determinism oracles (RngLockDeterminism sec4/sec13) + DEGN-34's `testDgnrsAwardStaysPerSpin`; repair the stale JS hero-override harness.
- Doc corrections: name the `totalFlipReversals` nudge as a frozen input (DEITYDATA-01 / BAFTRAIT-05 / BAFFAR-06); fix the DEC-03 / BAF-07 anchors.

## Verdict

RNGPROOF-01..04 ✅. The RNG-freeze-at-commitment invariant is now a machine-verifiable, source-anchored, independently-re-verified artifact: 78/79 consumers proven frozen-at-commitment, the single residual being the known LOW gameover-prevrandao magnitude bias. No contract change (audit/proof milestone on the frozen subject).
