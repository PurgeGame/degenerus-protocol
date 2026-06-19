# Phase 432: COUNCIL — Cross-Model Backfill + Frozen-Commit Sweep + RNG-Proof Verification

**Milestone:** v68.0
**Completed:** 2026-06-17
**Requirements:** COUNCIL-01, COUNCIL-02 (+ COUNCIL-03, the USER-requested RNG-proof cross-model verification)
**Subject:** logic-frozen `4970ba5b`. Council = Gemini + Codex via `council.sh`; Claude adjudicates every candidate against current source.
**Method note:** the archived 423 prompt steered codex onto the **pre-MIDRNG-02-fix commit `0bb7deca`** (it pastes that era's context), so codex's backfill re-derived the *already-fixed* bug. The two fresh prompts (frozen-sweep, rngproof-verify) both read the current tree `4970ba5b` (verified in their citations).

---

## COUNCIL-01 — Codex-423 VRFSWAP backfill ✅

- **Codex** (on the archived prompt's stale `0bb7deca` context) re-derived VRFSWAP-01/02/03 as "HIGH stale-`LR_MID_DAY`" — **this IS the MIDRNG-02 bug** (NET-2-found, council-missed in v67). On the current frozen tree the fix `73eb242a` clears the latch on the new-day drain (`AdvanceModule.sol:304-305`); `test_midDayLatch_clearsOnCrossDayDrain` is green. **REFUTED on current tree / = already-fixed.** Strong corroboration the fix targets a real defect.
- **Gemini** (on current code, cites `Module:1337`/`HUB:1826`) ruled VRFSWAP **REFUTED — "rotation logic is sound"**; co-residence masked-writes correct, gameover timer not reset, fallback nudge pre-subtracted.
- **NV-02 (new, INFO):** codex flagged the `word 0→1` mapping (`AdvanceModule:1417`) colliding with the `rngWord==1` "request-sent" sentinel (`:388`). Real logical pattern, reachability ≈ **2⁻²⁵⁶** (a VRF/fallback word being exactly 1). INFO — economically unreachable; documented.
- **Net:** VRFSWAP HOLD corroborated; MIDRNG-02 independently re-derived (real); 1 INFO.

## COUNCIL-02 — Frozen-commit sweep ✅

- **Codex** (current tree): **"No reachable robustness issue found."** All three v67 fixes verified clean — MIDRNG-02 latch (no regression), the 4 named payable guards present + correct, gas retune (all-evict max ≈358 evictions, materially <16.7M, progress preserved).
- **Gemini** raised 3 candidates — adjudicated:
  | Gemini candidate | Verdict |
  |---|---|
  | **[HIGH] subscriber-evict / jackpot gas composition** | **REFUTED.** `AdvanceModule.sol:688` — "the terminal jackpot runs in its own tx" (the v60 isolation). The subscriber STAGE is chunked across advance calls; codex confirms ≈358-evict max <16.7M; v67 BRICK-FIND-01 live harness measured 9.7M. Gemini missed the per-tx isolation. |
  | **[MEDIUM] mid-day fallback overwrite** | **LOW → = the known carried item.** The late mid-day word overwriting an *undrained* index is VRF-fair with no double-pay = the deferred `:1843/:1850 ==0`-guard (VRFSWAP-REROLL) already in v2. |
  | **[LOW] missing payable delegatecall guards** | **REAL — `COUNCIL-FIND-01` (LOW).** See below. |

### COUNCIL-FIND-01 (LOW) — 3 payable entrypoints missing the direct-call guard

Enumerating every `payable` module function vs the `address(this)==GAME` guard:
- **Guarded (the 4 DELEGATE-FIND-01 fixed):** `consumePurchaseBoost`, `checkAndClearExpiredBoon`, `consumeActivityBoon`, `resolveLootboxDirect`.
- **Guarded differently but SAFE:** `resolveRedemptionLootbox`, `creditRedemptionDirect` — both `require(msg.sender == SDGNRS)`, so a direct call reverts (no trap).
- **UNGUARDED (the find):** `buyPresaleBox` (MintModule:1840), `purchaseLazyPass` (WhaleModule:388), `purchaseDeityPass` (WhaleModule:539) — payable, delegatecall-only (take an operator-resolved `buyer` param), no `address(this)==GAME` guard. A direct call to the module would execute against its empty storage and **trap the caller's `msg.value`** — the exact DELEGATE-FIND-01 class, which v67 fixed for 4 entrypoints and **missed these 3**.

**Severity LOW** (caller foot-gun: a user/integrator who mistakenly calls the module address directly instead of the Game loses their ETH; no protocol-solvency impact, not attacker-leverageable against others). **Recommended gated fix:** add `if (address(this) != GAME) revert E();` to the three entrypoints (a ~3-line change, same shape as `095a7ac9`). **Not applied** — subject is logic-frozen this milestone; routed to the USER for a gated decision (natural to batch with the other deferred LOW hardenings, e.g. the `:1843 ==0` guard).

## COUNCIL-03 — Cross-model RNG-freeze-proof verification ✅ (USER request)

Both models independently re-verified the 429 proof against current source:
- **Gemini: CONCURS — "78/79 RNG-consumers frozen-at-commitment."** AGREES SEAM-RESOLVE is the one LOW prevrandao break; AGREES both HIGH-if-broken seams (REDEEMSEAM-08, FLIPESCROW-09) HOLD; independently verified JKPT-43. One **labeling nit**: `RNGF-ADV-10`/`-12` share SEAM-RESOLVE's `block.prevrandao` dependency and should be co-flagged (no risk-profile change).
- **Codex: AGREES on all 3 flagged claims** (SEAM-RESOLVE false/LOW, the two HIGH seams HOLD), but argued several lootbox claims are "outcome-not-fully-frozen" because `_rollTargetLevel(level+1, seed)` reads the **live level** at open (MED), plus live boon-mapping (LOW) and deity-slot post-reveal (LOW).
  - **Adjudication — codex MED REFUTED (USER-confirmed 2026-06-17):** source (`LootboxModule:549-555`) documents the anti-gaming design — the box rolls from the live level, BUT the **permissionless auto-open bounty opens every ready box ASAP and the holder cannot prevent it**, so the open level is **not player-timable**, and the **EV multiplier is FROZEN at deposit** (`score`). **USER confirmed: boxes are opened by an economically-incentivized auto-caller, AND there is no "better" level** — the level creates no exploitable EV gradient, so the vector fails on both counts (no timing control AND no favorable target). The live level is an input that affects the outcome but is **not actor-controllable**, so under the precise invariant ("no *actor-controllable* input changes the outcome") the freeze HOLDS. Codex applied the invariant too literally (any live input = break) without weighing actor-controllability/timing-removal.
  - Codex's LOWs (boon-mapping `LBX-06`, deity-slot `LBX-07`/`DEITYISSUE-02`) are the proof's **already-flagged** LOW / MUTABLE-INPUT items (bounded, by-design) — not new.
- **Net:** the proof's headline **78/79 freeze-holds is cross-model-confirmed**; the one LOW (SEAM-RESOLVE gameover-prevrandao magnitude) is unanimously agreed; no new freeze break survives adjudication.

## Verdict

COUNCIL-01/02/03 ✅. **0 new CATASTROPHE / 0 HIGH.** New: **1 LOW** (COUNCIL-FIND-01 — 3 unguarded payable entrypoints, documented + flagged for a gated fix) + **1 INFO** (NV-02 word==1, 2⁻²⁵⁶). The RNG-freeze proof is cross-model-confirmed (78/79); VRFSWAP HOLD corroborated; MIDRNG-02 independently re-derived (real, fixed). No contract change this milestone.

## Carried follow-on
- **Gated fix decision (USER):** `address(this)==GAME` guard on `buyPresaleBox` / `purchaseLazyPass` / `purchaseDeityPass` (COUNCIL-FIND-01).
- **Proof doc-hardening:** co-flag `RNGF-ADV-10`/`-12` (shared prevrandao dependency); add the actor-controllability note to the LBX live-level entries.
