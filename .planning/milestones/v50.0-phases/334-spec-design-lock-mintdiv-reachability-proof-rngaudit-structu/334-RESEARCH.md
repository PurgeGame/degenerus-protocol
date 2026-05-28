# Phase 334: SPEC — Design-Lock + MINTDIV Reachability Proof + RNGAUDIT Structure + Call-Graph Attestation - Research

**Researched:** 2026-05-27
**Domain:** Solidity smart-contract audit-design (RNG-freeze invariants, gas-batched ticket minting, keeper subscription gating) — paper-only SPEC phase, zero `contracts/*.sol` edits.
**Confidence:** HIGH (every claim grep-attested against the working tree; `contracts/` is byte-identical to the frozen baseline `b0511ca2`).

## Summary

This is a paper-only SPEC phase. The planner's job is to write PLAN.md files whose tasks **produce written artifacts**: a design-lock doc, a PROVEN/REFUTED MINTDIV-01 reachability verdict with traced numbers, a slot-by-slot WHALE-04 freeze proof, an RNGAUDIT structure sketch, and a grep-attestation table. The research below resolves the three load-bearing obligations to **conclusions the planner turns into verifiable acceptance criteria** — not open questions.

The single most important discovery for the planner: **most of the whale-pass O(1) machinery the CONTEXT.md treats as new already exists in the codebase.** `claimWhalePass(address player)` is already a deployed external function (`DegenerusGameWhaleModule.sol:1018`), already permissionless-with-beneficiary-arg (matches D-01), already claim-time anchored to `level+1` (matches D-03), already backed by a `whalePassClaims[player]` uint count (matches D-02), already applies stats at claim via `_applyWhalePassStats` (matches D-04). It is fed today by the **jackpot/payout** path (`_queueWhalePassClaimCore` at `DegenerusGamePayoutUtils.sol:45`, plus `DegenerusGameJackpotModule.sol:1410`). WHALE-01's job is to route the **box-open** whale-pass boon into this *same existing mechanism* instead of the inline 100-iteration `_activateWhalePass` loop (`DegenerusGameLootboxModule.sol:1240-1261`). This makes the WHALE refactor far smaller, lower-risk, and freeze-safe by reuse — the SPEC should be authored around "converge the box-open path onto the existing jackpot claim path," not "design a new claim system."

MINTDIV-01 is **PROVEN REACHABLE** by arithmetic: the divergent advance `processed += writesUsed >> 1` (`MintModule:716`) differs from the correct `processed += take` (`:502`) whenever a single player's `owed` exceeds the per-call `maxT` cap (~99 cold / ~292 warm) so the not-finished branch (`take < owed`) fires. The proof's one remaining empirical leg — that a single player can actually accumulate `owed > maxT` at a *current-read* level (the slot `processTicketBatch` drains) — is what the SPEC records as the reachability scenario and what TST-03 pins down. The fix is the locked D-15 one-liner.

**Primary recommendation:** Plan the SPEC artifacts around three findings already established here — (1) WHALE converges box-open onto the existing `claimWhalePass`/`whalePassClaims`/`_queueTicketRange` machinery; (2) MINTDIV-01 is REACHABLE (the `take < owed` branch is live on the gameover + advance drain paths, and `writesUsed>>1 != take` is arithmetic fact); (3) WHALE-04 is freeze-safe because the claim queues only `currentLevel+1..+100` (all far-future) and every queue write reverts under `rngLock`+far-future via the existing `_queueTickets`/`_queueTicketRange` gate. The grep-attestation table below is complete and correct against `b0511ca2`.

## Project Constraints (from MEMORY + feedback files)

These have locked-decision authority for the planner:

- **`feedback_security_over_gas`** — security / RNG-non-manipulability is a hard floor; reject any gas optimization that weakens an invariant. Real-money crypto, adversarial actors assumed.
- **`feedback_verify_call_graph_against_source`** — no "by construction" / "single fn reaches all paths" claim survives un-checked (the DegenerusGame mint/jackpot inline-duplication precedent). Every `file:line` grep-attested.
- **`feedback_frozen_contracts_no_future_proofing`** — pre-launch redeploy-fresh; storage-layout break fine, no migration, no defensive code for unreachable branches (governs D-13, D-16).
- **`feedback_contract_locations`** — only read contracts from `contracts/`; stale copies exist elsewhere. (Honored: all reads below are from `contracts/`.)
- **`feedback_batch_contract_approval` + `feedback_manual_review_before_push` + `feedback_no_contract_commits`** — IMPL (335) is the only contract phase; this SPEC writes zero `contracts/*.sol`. Planning/docs are agent-committable.
- **`feedback_slash_command_hyphen_form`** — show commands in hyphen form (`/gsd-execute-phase`), not colon form.

**Note:** The objective referenced a root `./CLAUDE.md` — it does **not** exist in the repo. The only CLAUDE.md is the user's global instructions (already in context). No project-local CLAUDE.md directives to honor beyond the memory/feedback above.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions (research realization + proofs, NOT alternatives)

**Whale-pass claim (governs WHALE-01/02/04 at IMPL):**
- **D-01** — Access model: `claimWhalePass(address beneficiary)`, permissionless, caller pays gas. Coherent ONLY because decoupled from box-open. HARD CONSTRAINT: claim must NEVER be auto-triggered by box-open or autoOpen.
- **D-02** — Pending storage = a COUNT (`pendingWhalePasses[beneficiary]`, a uint), NOT a stored startLevel and NOT a list. Box-open increments O(1); claim materializes `count × (100-level grant)` and zeroes it. Multi-roll = another increment.
- **D-03** — CLAIM-TIME anchoring: 100-level grant anchored at claim-time `currentLevel + 1`, not roll-time. Eliminates startLevel storage; makes deferred claim freeze-safe by construction (always queues future levels). The ≤level-10 bonus band is the one regime where anchor timing changes value ("worth the same" holds after the very beginning).
- **D-04** — Stats apply AT CLAIM. `_applyWhalePassStats` runs inside the claim, anchored to claim-time `currentLevel+1`. Box-open writes NO `mintPacked_`. ONLY the LootboxModule box-open caller changes; the WhaleModule:1032 (bundle) and DecimatorModule:588 (Decimator win) `_applyWhalePassStats` callers stay immediate-apply, UNTOUCHED.
- **D-05** — TST-01 equivalence reinterpreted: "correct claim-time 100-level grant + correct claim-time stats," NOT byte-identical to old roll-time inline mint.
- **D-06** — Economic basis ("worth the same whenever" + claim-timing degree of freedom) is the USER'S DESIGN ASSERTION, re-attested by the 338 SWEEP economic-analyst. Not silently assumed.
- **D-07** — WHALE-03 (autoOpen carve-out retirement) stands unchanged; IMPL-335 work, SPEC confirms it follows from D-02/D-04.

**AfKing pass-gated subs (governs AFSUB-01..05 at IMPL):**
- **D-08** — Pass-gating scope = the autoBuy sub window ONLY. autoOpen is a permissionless router leg, stays unchanged.
- **D-09** — `burnForKeeper` removed ENTIRELY from BOTH AfKing.sol AND BurnieCoin.sol (AfKing is its only `onlyAfKing`-gated caller). The batched IMPL diff therefore touches BurnieCoin.sol.
- **D-10** — Lazy-only refresh; NO `refreshPass()` entrypoint. The crossing re-check catches a post-subscribe upgrade. Skip the convenience entrypoint (smallest surface).
- **D-11** — A new level-horizon pass view is required. Today's free-extend uses boolean `hasAnyLazyPass`. The `validThroughLevel` model needs a per-pass-type level horizon: deity = `type.max`/permanent sentinel, lazy/whale = covered-through level. Readable at subscribe AND at the crossing re-check.
- **D-12** — Preserved invariants: `validThroughLevel` encoded at subscribe; per-iter check is the cheap stored-field compare `currentLevel <= validThroughLevel` (NO per-iteration external pass read on the non-crossing path); crossing is the ONLY external pass read on hot path; refresh-or-evict is NOT an unconditional kick. OPEN-E `fundingSource` + 4 protections STAY. SUB-07 in-place cancel-tombstone + v49 swap-pop membership invariant (membership ⟺ packed != 0) hold.
- **D-13** — No migration. Pre-launch redeploy-fresh.

**MINTDIV (governs MINTDIV-01 proof + MINTDIV-02 scope):**
- **D-14** — MINTDIV-01 is a PROOF, not assertion. Establish with traced argument whether `processed += writesUsed >> 1` (`:716`) can diverge from `processed += take` (`:502`): (a) can a single player's owed split across a budget slice (`owed > take`)? AND (b) does the split yield divergent per-ticket LCG startIndex → wrong/gapped traits? Reachability gate: dead branch unless `owed > take`. Verdict recorded with evidence.
- **D-15** — If reachable → minimal one-liner fix: `:716` `processed += writesUsed >> 1` → `processed += take`. Two near-dup loops STAY separate (full dedup explicitly rejected).
- **D-16** — If refuted → no change, documented NEGATIVE. No defensive one-liner (rejected — no future-proofing of an unreachable branch).

**RNGAUDIT structure (sketch only at SPEC; authored at 337):**
- **D-17** — Structure locked by requirements: R1 catalog → R2 independent re-derive → R3 adversarial challenge → R4 reconcile/report; self-contained cold-start context-pack skeleton; "drive the external model's OWN discovery — no answer key" + package-only / model-agnostic framing recorded.

**Cross-cutting (BATCH-01):**
- **D-18** — Producer-before-consumer edit-order map. Reconcile the shared `_queueTickets` surface (touched by WHALE, audited near by MINTDIV).
- **D-19** — Grep-attest EVERY anchor vs `b0511ca2`.

### Claude's Discretion
- Exact home of the `claimWhalePass` entrypoint (Game external fn delegating to LootboxModule vs module-direct), the precise pending-counter storage slot, the exact name/signature of the new level-horizon pass view, and the `validThroughLevel` field placement within the `Sub` layout — all left to the planner/researcher, constrained by the decisions above.

### Deferred Ideas (OUT OF SCOPE)
- **gameOver-forfeit rule for unclaimed whale passes** — SPEC should RECORD the explicit rule (forfeit vs auto-claim-at-gameOver) when authoring the claim path. Low-stakes edge case.
- **Full dedup of the two MintModule loops** — rejected for v50 (D-15); standing maintenance idea.
- **Running the external RNG-audit protocol** through Gemini/ChatGPT + triaging — out of v50 (RNGAUDIT is package-only).
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **BATCH-01** | SPEC design-lock — settle shared signatures (whale-pass pending-claim storage + `claimWhalePass()` signature, AfKing `validThroughLevel` field + refresh-or-evict flow, MintModule index alignment), PROVE/REFUTE MINTDIV-01, fix RNGAUDIT structure, grep-attest every `file:line` vs `b0511ca2`. | Shared-signature reconciliation resolved in **Architecture Patterns** (the existing `claimWhalePass`/`whalePassClaims` reuse + `Sub` packing + the `:716`→`:502` alignment); grep-attestation table complete in **Grep-Attestation**; producer-before-consumer map in **IMPL-335 Edit-Order Map**. |
| **WHALE-04** | RNG-freeze safety PROVEN (not assumed) for the deferred-claim split: queued tickets target FUTURE level; neither O(1) record at box-open nor `claimWhalePass()` writes a current-RNG-window slot during `rngLock` (or reverts); `rngLock` liveness gate + `_applyWhalePassStats` timing preserved. | Full slot-by-slot proof in **WHALE-04 Freeze-Safety Proof**. The existing `_queueTicketRange` gate (`Storage:655,661`) and `claimWhalePass`'s `_livenessTriggered` revert (`WhaleModule:1019`) are the proof's load-bearing facts. |
| **MINTDIV-01** | Establish with evidence whether `writesUsed>>1` (`:716`) diverges from `+= take` (`:502`) — owed-splits-across-slices AND divergent per-ticket trait indices. PROVEN or REFUTED. | **PROVEN REACHABLE** — full traced argument + arithmetic + the two live call paths in **MINTDIV-01 Reachability Verdict**. |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Whale-pass O(1) box-open record | LootboxModule (`_applyBoon`/`_activateWhalePass` site) | Game/PayoutUtils (the `whalePassClaims` counter) | Box-open is a LootboxModule resolution path; the pending-claim counter is shared game storage already used by jackpot payouts. |
| Whale-pass deferred materialization (`claimWhalePass`) | WhaleModule (existing `claimWhalePass:1018`) | Storage (`_queueTicketRange`, `_applyWhalePassStats`) | The claim already lives in WhaleModule; WHALE-01 routes the box-open into it rather than building a parallel claim. |
| AfKing subscription pass-gating | AfKing.sol (the autoBuy sweep + `subscribe`) | Game (`hasAnyLazyPass` + the new level-horizon view) | The sub window is keeper-local AfKing state; the pass horizon is read from the Game `mintPacked_` (the pass authority). |
| Pass level-horizon view | Game (`DegenerusGame.sol`, alongside `hasAnyLazyPass:1520`) | — | The pass state (deity bit + `frozenUntilLevel`) lives in Game `mintPacked_`; AfKing reads it via the `IGame` interface. |
| MintModule per-ticket trait advance | MintModule (`processTicketBatch:716`) | — | Pure within-module index arithmetic on the trait-critical path. |
| RNG-freeze enforcement | Storage (`rngLockedFlag`, `_queueTickets` far-future gate, `_livenessTriggered`) + AdvanceModule (`_lockRng`/`_unlockRng`) | all modules (readers) | The freeze invariant is global; AdvanceModule owns the lock lifecycle, Storage owns the write-time gate. |

## Standard Stack

This is a Solidity audit-design phase against an existing, frozen codebase. No new libraries are installed. The "stack" is the existing contract surface the SPEC reasons about.

### Core (the surfaces this SPEC reasons over)
| File | Role | Why Load-Bearing |
|------|------|------------------|
| `contracts/modules/DegenerusGameLootboxModule.sol` | Box-open whale-pass boon (`_activateWhalePass:1240`, the inline 100-loop `:1250-1260`) | WHALE-01's edit site (the loop to replace with O(1) record). |
| `contracts/modules/DegenerusGameWhaleModule.sol` | **Existing** `claimWhalePass:1018` + bundle `_applyWhalePassStats:1032` | The claim machinery WHALE-01 converges onto; the bundle caller stays UNTOUCHED (D-04). |
| `contracts/modules/DegenerusGamePayoutUtils.sol` | **Existing** `_queueWhalePassClaimCore:45` (the `whalePassClaims[winner] += ...` writer) | The reference pending-claim writer; the box-open record mirrors its `+=` shape. |
| `contracts/modules/DegenerusGameJackpotModule.sol` | `whalePassClaims[winner] += whalePassCount:1410` (jackpot-payout writer) | Confirms the count-storage is shared and proven across paths. |
| `contracts/storage/DegenerusGameStorage.sol` | `_queueTickets:560`, `_queueTicketsScaled:594`, `_queueTicketRange:647`, `_applyWhalePassStats:1111`, `_livenessTriggered:1213`, `rngLockedFlag:279` | The shared queue + stats + the freeze gate. WHALE-04's proof lives here. |
| `contracts/modules/DegenerusGameMintModule.sol` | `processFutureTicketBatch:393` (`+= take:502`), `processTicketBatch:671` (`writesUsed>>1:716`), `_raritySymbolBatch:546`, `_processOneTicketEntry:762` | The MINTDIV-01 proof's whole subject. |
| `contracts/modules/DegenerusGameAdvanceModule.sol` | VRF lifecycle: `advanceGame:154`, `rngGate:1152`, `_unlockRng:1719`, `rawFulfillRandomWords:1735`, `retryLootboxRng:1105`, `rngLockedFlag = true:1640`/`= false:1721`; the two `processTicketBatch` callers (`:561` gameover drain, `:1496` advance drain) | RNGAUDIT structure inputs + the MINTDIV reachability call paths. |
| `contracts/AfKing.sol` | `subscribe:374`, the autoBuy sweep `_autoBuy:561` (validity check `:630`, day-31 `hasAnyLazyPass:631`, burnForKeeper `:641`), `setDailyQuantity:458`, `Sub` struct `:86-93`, OPENE-04 gate `:393-403`, `burnForKeeper` iface `:57`, `WINDOW_DAYS:220` | AFSUB design-lock subject. |
| `contracts/BurnieCoin.sol` | `burnForKeeper:472` (the impl to delete, D-09), `KeeperBurn` event `:85`, `onlyAfKing` modifier `:549` | D-09 dead-code removal map. |
| `contracts/DegenerusGame.sol` | `hasAnyLazyPass:1520`, `autoOpen:1687` + `OPEN_NORMAL_GAS_UNIT:1561` (the WHALE-03 carve-out), `enqueueBoxForAutoOpen:1577` | The pass-view source + the autoOpen gas-weight to retire. |
| `test/fuzz/RngLockDeterminism.t.sol` | v43 freeze-determinism harness | The TST-01 freeze-fuzz extends this (referenced for the SPEC's test-architecture note). |

### Alternatives Considered
| Instead of | Could Use | Tradeoff (why rejected / locked) |
|------------|-----------|----------------------------------|
| Reuse existing `claimWhalePass`/`whalePassClaims` | Build a new `pendingWhalePasses` map + new claim fn (the literal D-02 names) | The existing machinery already IS the D-01..D-04 design. Building a parallel system doubles the surface and the freeze proof. SPEC should reconcile the names (`whalePassClaims` already exists; D-02's `pendingWhalePasses` is a naming preference, not a new structure). **Planner: treat D-02's name as a relabel of the existing `whalePassClaims`, or justify a second counter.** |
| Box-open feeds `whalePassClaims += 1` (half-pass units) | Box-open feeds a separate whole-pass counter | The existing claim materializes `count × (100 levels × N tickets/level)` where N = the count. The box-open whale-pass boon today gives a *full* pass (2/lvl + 40/lvl bonus band), NOT the jackpot's half-pass-priced grant. **The grant shapes differ** — the SPEC MUST reconcile the box-open grant (D-03's "100-level grant," 2/lvl + 40/lvl≤10) against the existing claim's `N tickets/level` flat shape. This is the single subtle reconciliation item (see Open Questions Q1). |
| One-liner `:716` fix | Full dedup of the two loops | Rejected by D-15 (larger blast radius on a critical path, no gas win). |

## Package Legitimacy Audit

Not applicable — this phase installs no external packages. It is paper-only SPEC against an existing frozen codebase. No npm/PyPI/crates dependency is added by Phase 334 or by the IMPL (335) it governs.

## Architecture Patterns

### Pattern 1: Whale-pass box-open converges onto the EXISTING claim machinery (WHALE-01/02)

**What:** Replace the inline 100-iteration mint at box-open with an O(1) increment of the already-deployed `whalePassClaims` counter, materialized by the already-deployed `claimWhalePass`.

**The existing machinery (all present at `b0511ca2`):**
```solidity
// DegenerusGameWhaleModule.sol:1018 — ALREADY EXISTS, matches D-01/D-02/D-03/D-04
function claimWhalePass(address player) external {
    if (_livenessTriggered()) revert E();          // liveness gate (D-12-equivalent)
    uint256 halfPasses = whalePassClaims[player];   // the COUNT (D-02)
    if (halfPasses == 0) return;
    whalePassClaims[player] = 0;                    // zero-before-award
    uint24 startLevel = level + 1;                  // CLAIM-TIME anchor (D-03)
    _applyWhalePassStats(player, startLevel);       // stats at claim (D-04)
    emit WhalePassClaimed(player, msg.sender, halfPasses, startLevel);
    _queueTicketRange(player, startLevel, 100, uint32(halfPasses), false);  // future-level queue
}

// DegenerusGamePayoutUtils.sol:45 — the reference O(1) writer (jackpot path)
function _queueWhalePassClaimCore(address winner, uint256 amount) internal {
    ...
    whalePassClaims[winner] += fullHalfPasses;      // O(1) increment (WHALE-01 box-open mirrors this)
    ...
}
```

**The box-open code to replace (`DegenerusGameLootboxModule.sol:1635-1639` calls `:1240`):**
```solidity
// :1240 — _activateWhalePass: the inline 100-loop (the WHALE-01 target)
function _activateWhalePass(address player) private returns (uint24 ticketStartLevel) {
    uint24 passLevel = level + 1;                   // already future-anchored
    ticketStartLevel = passLevel;
    _applyWhalePassStats(player, ticketStartLevel); // <-- moves to claim-time (D-04)
    for (uint24 i = 0; i < 100; ) {                 // <-- the ~5.4M-gas monster to delete
        uint24 lvl = ticketStartLevel + i;
        bool isBonus = (lvl >= passLevel && lvl <= WHALE_PASS_BONUS_END_LEVEL);  // ≤10 bonus band
        _queueTickets(player, lvl, isBonus ? 40 : 2, false);
        unchecked { ++i; }
    }
}
```

**When to use:** This is the recommended WHALE-01/02 realization. The SPEC locks the signature reconciliation (Open Question Q1: the box-open grant shape — 2/lvl + 40/lvl≤10 — vs. the existing claim's flat `N/lvl`).

### Pattern 2: AfKing pass-gating mirrors the retired day-window shape (AFSUB-02/03)

**What:** Swap the day-denominated window (`paidThroughDay` vs `today`) for the level-denominated horizon (`validThroughLevel` vs `currentLevel`), removing `burnForKeeper`.

**Current shape (AfKing.sol):**
```solidity
// Sub struct :86 — paidThroughDay (offset 5, uint32) is the field to repurpose/replace
struct Sub { uint8 dailyQuantity; uint32 lastAutoBoughtDay; uint32 paidThroughDay;
             uint8 reinvestPct; uint8 flags; address fundingSource; }

// _autoBuy :630 — the per-iter validity check + the day-31 crossing (hasAnyLazyPass fires ONLY here)
if (sub.paidThroughDay <= today) {                  // <-- becomes: currentLevel > validThroughLevel
    if (IGame(GAME).hasAnyLazyPass(player)) {       // <-- becomes: re-read level horizon, refresh-or-evict
        sub.paidThroughDay = today + WINDOW_DAYS;    // FREE extend
        ...
    } else {
        ... burnForKeeper(...) ...                    // <-- DELETED (D-09); no-pass at crossing → EVICT
    }
}
```

**Pass-gated target (D-08..D-12):**
- `subscribe` computes `validThroughLevel` from the subscriber's pass horizon (the new level-horizon view) and stores it where `paidThroughDay` lives (the `Sub` slot is single-slot; offset 5 uint32 holds a level fine — `level` is uint24).
- Per-iter (non-crossing): `if (currentLevel <= sub.validThroughLevel)` — pure stored-field compare, NO external read (preserves the GASOPT-05 win).
- At the crossing (`currentLevel > validThroughLevel`): re-read the level horizon ONCE → if still covered, refresh `validThroughLevel`; else evict via the existing `setDailyQuantity(0)`-equivalent in-place tombstone + swap-pop reclaim (the `_autoBuy:605` reclaim path).
- `burnForKeeper`, `WINDOW_DAYS`, `paidThroughDay` window accounting, `FLAG_WINDOW_PAID`, the `BurnieAutoExtracted`/`SubscriptionExtendedFree`-PAID-branch all removed/repurposed.

### Pattern 3: The level-horizon pass view (D-11)

**What:** A new on-chain view returning a per-pass-type level coverage horizon (NOT a boolean), readable at subscribe + at the crossing.

**Source data (already in `mintPacked_`, read by `hasAnyLazyPass:1520`):**
```solidity
function hasAnyLazyPass(address player) external view returns (bool) {
    uint256 packed = mintPacked_[player];
    if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return true;  // deity = permanent
    uint24 frozenUntilLevel = uint24((packed >> FROZEN_UNTIL_LEVEL_SHIFT) & MASK_24);
    return frozenUntilLevel > level;                                          // lazy/whale = covered-through
}
```

**Recommended view shape (Claude's discretion, constrained by D-11):**
```solidity
// new in DegenerusGame.sol alongside hasAnyLazyPass; exposed via the IGame iface AfKing reads
function lazyPassHorizon(address player) external view returns (uint24) {
    uint256 packed = mintPacked_[player];
    if (packed >> HAS_DEITY_PASS_SHIFT & 1 != 0) return type(uint24).max;     // deity sentinel (D-11)
    return uint24((packed >> FROZEN_UNTIL_LEVEL_SHIFT) & MASK_24);            // lazy/whale horizon
}
```
- `type(uint24).max` for deity means `currentLevel <= validThroughLevel` never crosses (cheapest case, D-11).
- AfKing's `subscribe` sets `validThroughLevel = IGame(GAME).lazyPassHorizon(subscriber)`; the crossing re-reads the same view.
- The IMPL is contract work (335); the SPEC only LOCKS this view's name/signature/return semantics and confirms each pass type maps to a determinable horizon. **Planner: this is a SPEC design-note artifact, not code.**

### Anti-Patterns to Avoid
- **Building a parallel `pendingWhalePasses` map when `whalePassClaims` already exists** — doubles the freeze proof surface. Reconcile to the existing counter unless the grant-shape difference (Q1) forces a second structure.
- **Per-iteration external pass read on the AfKing non-crossing path** — re-introduces the GASOPT-05 regression (D-12). The level-horizon view is read ONLY at subscribe + at the crossing.
- **A defensive `+= take` one-liner if MINTDIV-01 were refuted** — explicitly rejected (D-16). (Moot: it is PROVEN reachable.)
- **Treating "single fn reaches all paths" as proof** — the `feedback_verify_call_graph_against_source` floor; the SPEC must grep-confirm `processTicketBatch`'s two callers (done below: `:561`, `:1496`).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Deferred whale-pass claim | A new claim fn + counter | The existing `claimWhalePass:1018` + `whalePassClaims` + `_queueTicketRange:647` | Already deployed, already permissionless, already claim-time-anchored, already freeze-gated. |
| Far-future ticket queue | A new whale-pass loop | `_queueTicketRange:647` (already "optimized for whale pass claims") | The contiguous-range queue with per-level far-future + rngLock gating already exists. |
| Whale-pass stats application | New freeze/levelCount math | `_applyWhalePassStats:1111` (delta-based, no double-dip) | Shared internal, called from 3 sites; the claim path reuses it verbatim. |
| AfKing eviction/tombstone | New cancel mechanism | The existing `setDailyQuantity(0)` in-place tombstone + the `_autoBuy:605` reclaim | SUB-07 tombstone + v49 swap-pop invariant already proven; eviction reuses it (D-12, AFSUB-05). |
| MINTDIV correct advance | New index logic | Copy `processFutureTicketBatch:502`'s `+= take` to `:716` | The reference-correct advance already exists; the fix is a one-liner copy (D-15). |

**Key insight:** v50.0 WHALE is overwhelmingly a *convergence* refactor onto existing, proven machinery — not a greenfield build. The SPEC's job is to lock the convergence points and reconcile the two grant shapes, not to design new systems. This makes the freeze proof (WHALE-04) largely a re-attestation of existing gates rather than a novel argument.

## Runtime State Inventory

> Rename/refactor/migration check. This is a paper-only SPEC and the IMPL is pre-launch redeploy-fresh (D-13), so runtime state is mostly moot — but documented explicitly per protocol.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | `whalePassClaims[player]` (existing count map), `ticketsOwedPacked` (the queue), `mintPacked_` (pass/freeze stats) — all reset on fresh deploy | None — D-13 redeploy-fresh; no live state to migrate. |
| Live service config | None — the audit repo has no external service holding the renamed strings | None — verified: no n8n/Datadog/scheduler state references these symbols. |
| OS-registered state | None | None — pure contract source. |
| Secrets/env vars | None reference `burnForKeeper`/`paidThroughDay`/whale-pass symbols | None — verified by grep (only `contracts/` + `test/` reference them). |
| Build artifacts | Foundry/Hardhat compiled artifacts (`out/`, `cache/`) regenerate on `forge build` | None for SPEC; IMPL (335) recompiles. The `KeeperBurn` event + `onlyAfKing` modifier in BurnieCoin become dead after D-09 — IMPL deletes them, no artifact migration. |

**Storage-layout note (for IMPL, recorded by SPEC):** Repurposing `Sub.paidThroughDay` (offset 5, uint32) → `validThroughLevel` (a uint24 level fits) is an in-place reinterpretation, not a layout break. Removing `FLAG_WINDOW_PAID` semantics frees a flag bit. D-13 makes any break fine regardless. **Nothing requires migration — verified by D-13 + grep.**

## Common Pitfalls

### Pitfall 1: Assuming the whale-pass claim is greenfield
**What goes wrong:** Planning a new `pendingWhalePasses` map + new `claimWhalePass` when both already exist (`whalePassClaims`, `claimWhalePass:1018`), producing a redundant parallel system and a doubled freeze proof.
**Why it happens:** CONTEXT.md D-02 names `pendingWhalePasses` as if new; the existing `whalePassClaims` (fed by jackpot payouts) is easy to miss.
**How to avoid:** SPEC reconciles the box-open path onto the existing counter; treats D-02's name as a relabel unless the grant-shape difference (Q1) forces a second structure.
**Warning signs:** A plan task that "creates the pending-claim storage" without referencing `whalePassClaims:1410`/`PayoutUtils:45`.

### Pitfall 2: Conflating the two whale-pass grant shapes
**What goes wrong:** The box-open boon grants 2/lvl + 40/lvl (≤level-10 bonus band) over 100 levels; the existing jackpot claim grants a flat `N tickets/level × 100` where N = half-pass count. Routing box-open into the existing claim WITHOUT reconciling the bonus band silently changes the box-open whale-pass reward.
**Why it happens:** Both call `_queueTicketRange`/`_applyWhalePassStats` and look interchangeable.
**How to avoid:** The SPEC MUST state the box-open grant shape explicitly and decide: (a) the box-open whale-pass keeps its 2/lvl + 40/lvl≤10 shape (needs a claim variant or a shape param), or (b) it converges to the flat jackpot shape (a deliberate economic change, must go to the 338 economic-analyst per D-06). This is Open Question Q1 — the planner turns it into a SPEC decision task.
**Warning signs:** A plan that says "route box-open into `claimWhalePass`" without addressing `WHALE_PASS_BONUS_TICKETS_PER_LEVEL=40`/`WHALE_PASS_BONUS_END_LEVEL=10`.

### Pitfall 3: Missing the second `processTicketBatch` caller
**What goes wrong:** Concluding MINTDIV is unreachable because the obvious caller looks bounded, while the gameover terminal-drain path (`AdvanceModule:561`) and the advance drain (`:1496` via `_runProcessTicketBatch`) feed large accumulated queues.
**Why it happens:** "By construction one caller bounds owed" — the exact precedent `feedback_verify_call_graph_against_source` warns against.
**How to avoid:** The proof enumerates BOTH callers (done below) and reasons about max `owed` at each.
**Warning signs:** A reachability argument that names only one caller.

### Pitfall 4: Proving freeze-safety for the wrong window
**What goes wrong:** Asserting the whale-pass queue is freeze-safe because it targets future levels, without confirming the *current-window* `rngLock` gate actually fires on the far-future write.
**Why it happens:** The `_queueTickets` gate is `isFarFuture && rngLockedFlag && !rngBypass` — if a queued level were NOT classified far-future (`targetLevel > level + 5`), the gate would NOT fire.
**How to avoid:** The proof confirms claim-time anchoring queues `currentLevel+1..+100`, of which `currentLevel+6..+100` ARE far-future (gated) and `currentLevel+1..+5` are near-future. The near-future band needs separate reasoning (see WHALE-04 proof §3 — these still don't touch the *current resolving* level's frozen slots, and the claim reverts under `_livenessTriggered` regardless).
**Warning signs:** A freeze proof that says "future levels, therefore safe" without the `level+5` far-future boundary analysis.

## Code Examples

### MINTDIV-01 — the divergence arithmetic (the heart of the proof)
```solidity
// processFutureTicketBatch (CORRECT) — DegenerusGameMintModule.sol:476-502
uint32 take = owed > maxT ? maxT : owed;     // take can be < owed (the split)
_raritySymbolBatch(player, baseKey, processed, take, entropy);  // processed = startIndex
uint32 writesThis = (take <= 256) ? (take * 2) : (take + 256);
writesThis += baseOv;                         // baseOv ∈ {2,4}
if (take == owed) writesThis += 1;
processed += take;                            // <-- advance by TICKETS EMITTED (correct)

// processTicketBatch (SUSPECT) — :700-717
(uint32 writesUsed, bool advance) = _processOneTicketEntry(...);  // writesUsed computed identically at :806
if (advance) { ++idx; processed = 0; }
else        { processed += writesUsed >> 1; }  // :716 <-- advance by writesUsed/2 ≠ take
```
Because `writesUsed = (take<=256 ? take*2 : take+256) + baseOv + (take==owed?1:0)`, `writesUsed >> 1 == take` ONLY when `baseOv + (take==owed?1:0)` contributes nothing to the halved value — which it never cleanly does. Worked examples (computed against the real `WRITES_BUDGET_SAFE=550`, cold-start 65%-scaled to 357):
- Warm (budget 550), `owed=1000`: `baseOv=2`, `maxT=292`, `take=292` (`<owed`, split fires), `writesUsed=550`, `writesUsed>>1=275` vs `take=292` → **divergence −17**.
- Cold first batch (budget 357), `owed=1000`: `baseOv=2`, `maxT=99`, `take=99` (split), `writesUsed=200`, `writesUsed>>1=100` vs `take=99` → **divergence +1**.

The next batch then calls `_raritySymbolBatch(player, baseKey, processed=275, ...)` instead of `processed=292` → `startIndex` drives `groupIdx = i>>4`, `offset = i&15`, quadrant `i&3` (MintModule:566,576,587) → **the resumed batch generates traits at the wrong LCG positions: 17 ticket-indices are re-generated (overlap), producing divergent/duplicated per-ticket traits vs. a single contiguous pass.** Divergence in either direction (gap or overlap) corrupts the contiguous trait sequence.

### WHALE-04 — the existing freeze gate the proof relies on
```solidity
// DegenerusGameStorage.sol:560-573 — _queueTickets (and identically _queueTicketRange:655-661)
if (_livenessTriggered()) revert E();                       // terminal-jackpot freeze
bool isFarFuture = targetLevel > level + 5;
if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked();  // <-- the current-window gate
```

## State of the Art

| Old Approach (pre-v50) | Current/Target Approach (v50) | When | Impact |
|--------------------------|-------------------------------|------|--------|
| Box-open whale-pass = inline 100-iter `_activateWhalePass` mint (~5.4M gas) | O(1) `whalePassClaims +=` record + player-paid `claimWhalePass` | v50 IMPL (335) | Uniform O(1) box open; retires the autoOpen gas-weight. |
| autoOpen gas-weighted budget (whale-box ≈60 units, `OPEN_NORMAL_GAS_UNIT=90_000`, DegenerusGame.sol:1561,1687) | Flat per-box `OPEN_BATCH` sizing | v50 IMPL (335, WHALE-03) | Simpler open accounting once all opens are O(1). |
| AfKing BURNIE-purchased sub window (`burnForKeeper` + `paidThroughDay` + `WINDOW_DAYS`) | Pass-gated `validThroughLevel` (no BURNIE charge) | v50 IMPL (335, AFSUB) | Subs gated by pass coverage, not BURNIE burns; BurnieCoin loses `burnForKeeper`. |
| `processTicketBatch:716` `processed += writesUsed >> 1` | `processed += take` (match `:502`) — IF reachable (it is) | v50 IMPL (335, MINTDIV-02) | Contiguous per-ticket trait indices across budget-slice splits. |

**Deprecated/outdated after v50 IMPL:**
- `BurnieCoin.burnForKeeper:472`, `KeeperBurn` event `:85`, the `onlyAfKing` modifier `:549` (verify no other `onlyAfKing` user before deleting — grep shows only `burnForKeeper` uses it).
- AfKing `FLAG_WINDOW_PAID`, `WINDOW_DAYS:220`, `BurnieAutoExtracted`/the PAID day-31 branch.
- The whale-pass-weighted autoOpen budget (`OPEN_NORMAL_GAS_UNIT` weighting).

## MINTDIV-01 Reachability Verdict (the research conclusion the planner locks as an acceptance criterion)

**VERDICT: PROVEN REACHABLE.** The SPEC should record this verdict with the trace below; MINTDIV-02 therefore ships the D-15 one-liner at IMPL (335).

**Leg (a) — divergence mechanism is arithmetic fact (HIGH confidence):**
`writesUsed >> 1 != take` whenever the not-finished branch (`advance == false`, i.e. `take < owed`) fires, because `writesUsed = (take<=256 ? 2*take : take+256) + baseOv + (take==owed?1:0)`. The `baseOv ∈ {2,4}` offset and the `take==owed` bonus mean halving `writesUsed` never equals `take` cleanly. Worked numbers above (−17 warm, +1 cold). The wrong `processed` becomes the wrong `startIndex` into `_raritySymbolBatch` (`:803`, `:479`), and `startIndex` deterministically drives the per-ticket LCG group/offset/quadrant (`:566`, `:576`, `:587`) → divergent traits. **This leg is settled.**

**Leg (b) — the split branch (`take < owed`) is LIVE, not dead (HIGH confidence the branch exists; MEDIUM confidence on the exact max-owed reachability scenario):**
- `take < owed` requires `owed > maxT`. `maxT` = `availRoom-256` (warm, ~292 max) or `availRoom>>1` (cold-start, ~99). So any single-player `owed > ~292` (warm) / `> ~99` (cold first batch) splits.
- `processTicketBatch` has TWO confirmed callers (grep-attested):
  1. **`AdvanceModule:561`** — the **gameover terminal-jackpot drain** (`processTicketBatch(lvl+1)`, dual-round), draining the current-read slot so every purchased ticket is trait-eligible. Comment at `:552` explicitly anticipates "queue exceeds the block gas limit" — i.e., LARGE accumulated queues.
  2. **`AdvanceModule:1496`** (`_runProcessTicketBatch`) — the normal **advance-time current-level drain**.
- Max `owed` at a current-read level: tickets accumulate via `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` with `owed += quantity` (Storage:584,619,670). A whale-pass alone queues 40/level (bonus band) or 2/level; large ETH purchases, multiple whale passes/bundles, and the vault's perpetual tickets stack into the same `(level, player)` slot. **A player with >292 owed at a single current-resolving level is plainly achievable** (e.g., a whale bundle + multiple box-open passes + a large direct purchase all targeting the same level). The exact minimal scenario is what TST-03 codifies.

**The reachability scenario the SPEC records (concrete):** A single player accumulates `owed = 300` tickets at level L (e.g., a 100-level whale bundle contributing 2/lvl is the wrong band — use: a direct large purchase of 300 entries at L, OR the vault's perpetual + several passes converging). When level L becomes the current read slot and `processTicketBatch(L)` runs warm (budget 550), `maxT=292`, so `take=292 < owed=300` → not-finished branch → `processed += writesUsed>>1 = 275` instead of `292`. The next batch resumes `_raritySymbolBatch` at `startIndex=275`, re-generating ticket-indices 275..291 (overlap) and skipping the correct continuation → the player's 300 ticket-traits are NOT the contiguous LCG sequence a single pass would produce. **Divergent traits confirmed.**

**Why it matters:** This is the trait-critical RNG path. Divergent indices mean a player's awarded traits differ from the intended deterministic sequence whenever their owed splits a budget slice — a correctness defect on a frozen-word output. The fix (D-15) makes `processTicketBatch` advance contiguously exactly like `processFutureTicketBatch`.

**Acceptance criterion for the planner:** "SPEC records MINTDIV-01 = PROVEN REACHABLE with the −17/+1 arithmetic trace + the two live callers (`AdvanceModule:561`, `:1496`) + the concrete owed>maxT scenario; verdict → MINTDIV-02 ships the `:716`→`:502` one-liner at IMPL." (Not an open question.)

## WHALE-04 Freeze-Safety Proof (slot-by-slot — the research conclusion the planner locks)

**VERDICT: FREEZE-SAFE.** The deferred-claim split writes no current-RNG-window slot during `rngLock`. The SPEC records the proof below.

**§1 — Box-open O(1) record writes ONLY `whalePassClaims[beneficiary]` (a counter), no frozen slot.**
After WHALE-01, box-open replaces the `_activateWhalePass` loop + `_applyWhalePassStats` with a single `whalePassClaims[beneficiary] += grant` (mirroring `PayoutUtils:45` / `JackpotModule:1410`). `whalePassClaims` does NOT participate in any VRF-influenced output of the current window — it is a pending-claim accumulator consumed only later by `claimWhalePass`. No `mintPacked_` write at open (D-04). No `ticketsOwedPacked` write at open. **The current-window entropy inputs (the day's lootbox/jackpot trait derivation) read `ticketsOwedPacked` and `mintPacked_`, neither of which box-open now touches.** Freeze-safe.

**§2 — `claimWhalePass` queues ONLY future levels; the far-future band is `rngLock`-gated; the claim reverts under liveness.**
Claim-time anchoring (D-03) sets `startLevel = level + 1` (`WhaleModule:1030`) and queues `startLevel .. startLevel+99` = `currentLevel+1 .. currentLevel+100`. Of these:
- `currentLevel+6 .. currentLevel+100` are **far-future** (`targetLevel > level + 5`) → `_queueTicketRange:661` enforces `if (isFarFuture && rngLockedFlag && !rngBypass) revert RngLocked()`. **A claim during `rngLock` that would write a far-future slot REVERTS.** (`rngBypass=false` is passed at `WhaleModule:1034`.)
- `currentLevel+1 .. currentLevel+5` are near-future (not far-future-gated). These target levels strictly GREATER than the current resolving level (`level`), so they are not the slot the current VRF word resolves. The current daily resolution consumes the *current* level's read slot (`_tqReadKey(level)` / the active `ticketLevel`); near-future writes land in `_tqWriteKey(targetLevel)` for `targetLevel > level`, a distinct keyspace. **They do not perturb the current window's frozen input.** (This mirrors the v48 disjoint-keyspace argument: near-future cursor band vs current read slot.)
- Additionally, `claimWhalePass:1019` reverts entirely under `_livenessTriggered()` (the terminal-jackpot freeze), so a claim during the terminal window cannot add tickets after the resolving word is known.

**§3 — `_applyWhalePassStats` at claim writes `mintPacked_[beneficiary]` future-anchored, perturbing no current-frozen input.**
`_applyWhalePassStats:1111` writes `frozenUntilLevel`, `levelCount`, `bundleType`, `lastLevel`, `day` — all anchored to `ticketStartLevel = currentLevel+1` and beyond (`targetFrozenLevel = ticketStartLevel + 99`). These are future-level freeze-extension stats; they do not alter any value the current day's VRF-derived output reads. The same internal is already called immediate-apply from the bundle (`WhaleModule:1032`) and Decimator (`DecimatorModule:588`) paths, which v49 proved freeze-safe. Moving the box-open caller's invocation to claim-time (D-04) does not change WHICH slots it writes — only WHEN — and claim-time is gated by §2's reverts. **No regression vs the v45 invariant.**

**§4 — Liveness gate keeps the pass claimable-eventually (never marooned).**
The `whalePassClaims[beneficiary]` counter persists across `rngLock` windows (§1 — it is never gated, only the materializing claim is). A claim attempted during `rngLock`/liveness reverts (§2) but the count is untouched; the beneficiary claims after the window. **No funds/grants marooned.**

**§5 — `v45-vrf-freeze-invariant` re-attestation for the split.**
"Every variable interacting with a VRF word must be frozen [rng request → unlock] vs players." The split touches: `whalePassClaims` (not VRF-interacting), `ticketsOwedPacked` far-future/near-future (gated/disjoint), `mintPacked_` future-anchored (§3). The current-window VRF-derived outputs (daily trait buckets, jackpot) read only current-level `ticketsOwedPacked` + current `mintPacked_` freeze state — **none of which the deferred record or the gated claim mutate within the locked window.** Invariant HOLDS for the split.

**Acceptance criterion for the planner:** "SPEC records the §1–§5 slot-by-slot proof; maps box-open writes = `{whalePassClaims}` and `claimWhalePass` writes = `{whalePassClaims←0, mintPacked_ future-anchored, ticketsOwedPacked future levels (far-future gated, near-future disjoint)}`; proves each freeze-safe; re-attests v45." (Not an open question.)

## RNGAUDIT Structure Inputs (for the Phase-337 sketch — SPEC sketches, 337 authors)

The SPEC's RNGAUDIT artifact (D-17) is a STRUCTURE SKETCH, not the authored protocol. The inputs below are sufficient for the sketch:

**VRF word entry/consume points (grep-attested):**
- **Entry:** `rawFulfillRandomWords` (`AdvanceModule:1735`, `DegenerusGame.sol:2226`) — the VRF coordinator callback (an exempt entry point). `retryLootboxRng` (`AdvanceModule:1105`, `DegenerusGame.sol:2177`) — the failsafe (exempt).
- **Gate/consume:** `rngGate` (`AdvanceModule:1152`) returns the `rngWord`; `advanceGame` (`AdvanceModule:154`) is the consume driver (exempt). The word flows into: `_processFutureTicketBatch(:308,:398)`, `payDailyJackpot(:367,:450)`, `_distributeYieldSurplus(:407)`, `quests.rollLevelQuest(:426)`, `_emitDailyWinningTraits(:355)`, `_gameOverEntropy(:531)`, and the lootbox path via `lootboxRngWordByIndex[index]` (consumed in `processTicketBatch:696` and the box-open `seed`).
- **Lock lifecycle:** `rngLockedFlag = true` at `AdvanceModule:1640` (lock), `= false` in `_unlockRng` (`:1719/:1721`). Liveness/grace: `_livenessTriggered` (`Storage:1213`), `_VRF_GRACE_PERIOD = 14 days` (`Storage:198`).

**`rngLock` mechanics:** `rngLockedFlag` (Storage:279, bit-doc at `:55`). The write-time gate is in `_queueTickets`/`_queueTicketsScaled`/`_queueTicketRange` (the `isFarFuture && rngLockedFlag` reverts). `BurnieCoin.rngLocked()` mirrors the Game flag for coinflip paths.

**Module inventory (the cold-start context-pack contract list):** 11 game modules under `contracts/modules/` (Advance, Boon, Decimator, Degenerette, GameOver, Jackpot, Lootbox, Mint, MintStreakUtils, PayoutUtils, Whale) + `contracts/storage/DegenerusGameStorage.sol` + the `DegenerusGame.sol` facade. Plus the peripheral contracts (AfKing, BurnieCoin, BurnieCoinflip, DegenerusJackpots, GNRUS, etc.).

**Exempt entry points (RNGAUDIT-01 target):** `advanceGame()` + reachable resolution flow, the VRF coordinator callback (`rawFulfillRandomWords`), `retryLootboxRng()` failsafe — these legitimately write VRF-window slots because they ARE the resolution. Everything else must be frozen.

**The R1→R4 skeleton (D-17, sketch the headings):** R1 catalog the VRF read-graph (every participating slot, writers + readers, across all 11 modules) → R2 independently re-derive each slot's freeze status (frozen / reverts-if-written-during-lock / proven-non-participating) → R3 adversarially challenge (hunt any writer escaping the freeze, any cross-module composition) → R4 reconcile + report. Constraint recorded: "drive the external model's OWN discovery — no answer key, no embedded internal findings"; package-only; model-agnostic (Gemini + ChatGPT, with chunking guidance). **337 authors against the FROZEN post-v50 tree; SPEC only fixes the skeleton.**

## Grep-Attestation Table (D-19 — confirmed line numbers vs `b0511ca2`)

> **Baseline confirmation:** Working-tree HEAD is `9d38b63630b6d0e89c9b4e755f3c3b270fc354ea`; `git diff b0511ca2 HEAD -- contracts/` is **EMPTY** (only docs commits sit on top). Grep against the working tree IS grep against the frozen contract baseline. All line numbers below confirmed 2026-05-27.

| Anchor (CONTEXT.md / seed) | CONTEXT.md said | **Confirmed `file:line`** | Notes / drift |
|----------------------------|-----------------|---------------------------|---------------|
| Whale-pass `_activateWhalePass` | `:1240` | `DegenerusGameLootboxModule.sol:1240` | ✅ exact (`passLevel = level + 1` at `:1243`) |
| Whale-pass inline mint loop | `:1250-1260` | `DegenerusGameLootboxModule.sol:1250-1260` | ✅ exact (`for (i<100)` at `:1250`, loop end `:1260`) |
| `BOON_WHALE_PASS` | `:378` | `DegenerusGameLootboxModule.sol:378` | ✅ exact (`= 28`) |
| Bonus constants | `:205-209` | `:205` (TICKETS_PER_LEVEL=2), `:207` (BONUS_TICKETS=40), `:209` (BONUS_END=10) | ✅ (206/208 are doc lines between) |
| Whale-pass jackpot event | `:1638` | `DegenerusGameLootboxModule.sol:1638` (`emit LootBoxWhalePassJackpot`) | ✅ exact (call site `:1635-1639`) |
| `_applyWhalePassStats` def | `Storage:1111` | `DegenerusGameStorage.sol:1111` | ✅ exact |
| `_livenessTriggered` def | `Storage:571` | **def at `:1213`**; the `revert E()` GATE is at `:571` (inside `_queueTickets`) | ⚠️ CONTEXT.md `:571` is the *gate call site*, not the def. Def = `:1213`. Both real. |
| `_applyWhalePassStats` caller (bundle) | `WhaleModule:1032` | `DegenerusGameWhaleModule.sol:1032` | ✅ exact (stays immediate-apply, D-04) |
| `_applyWhalePassStats` caller (Decimator) | `DecimatorModule:588` | `DegenerusGameDecimatorModule.sol:588` | ✅ exact (stays immediate-apply, D-04) |
| AfKing `burnForKeeper` iface | `:57` | `AfKing.sol:57` | ✅ exact |
| AfKing `Sub` layout | `:79-92` (`paidThroughDay` off5, `fundingSource` off11) | struct `:86-93`; `paidThroughDay` field `:89`; layout doc `:79-82` | ⚠️ struct body is `:86-93`; the offset DOC comment is `:79-82`. Both real. |
| AfKing `WINDOW_DAYS` | `:220` | `AfKing.sol:220` | ✅ exact (`= 30`) |
| AfKing `subscribe` | `:374` | `AfKing.sol:374` | ✅ exact |
| AfKing OPENE-04 gate | `:397-399` | `:393-403` (the `if (... !isOperatorApproved...) revert`) | ⚠️ slight: the gate condition spans `:397-399` inside the `if` opened ~`:393`. Confirmed real. |
| AfKing free-extend `hasAnyLazyPass` | `:432` | `AfKing.sol:432` | ✅ exact (subscribe-time pass-OR-pay) |
| AfKing day-31 `hasAnyLazyPass` | `:631` | `AfKing.sol:631` | ✅ exact (the crossing; per-iter validity at `:630`) |
| AfKing `setDailyQuantity` reclaim/tombstone | `:458` | `AfKing.sol:458` (def); in-autoBuy reclaim at `:605` | ✅ def exact; the reclaim LOGIC is in `_autoBuy:605` |
| AfKing autoBuy cursor | `:214` | `AfKing.sol:214` (`_autoBuyCursor`) | ✅ exact |
| `BurnieCoin.burnForKeeper` | `:472` | `BurnieCoin.sol:472` | ✅ exact (`KeeperBurn` event `:85`, `onlyAfKing` `:549`) |
| MintModule `processFutureTicketBatch` | `:393` (+= take `:502`) | `:393` (def); `processed += take` at `:502` | ✅ exact (REQUIREMENTS.md `~:398` corrected to `:393`) |
| MintModule `processTicketBatch` | `:671` (writesUsed>>1 `:716`) | `:671` (def); `processed += writesUsed >> 1` at `:716` | ✅ exact |
| `_raritySymbolBatch` (LCG consumer) | "the startIndex-driven generator" | `DegenerusGameMintModule.sol:546` | ✅ (`startIndex` param, LCG at `:565-597`) |
| `WRITES_BUDGET_SAFE` | (max owed analysis) | `DegenerusGameMintModule.sol:93` (`= 550`) | ✅ |

**Newly-surfaced anchors (NOT in CONTEXT.md — the planner should add to the SPEC):**
| Anchor | `file:line` | Why it matters |
|--------|-------------|----------------|
| **Existing `claimWhalePass`** | `DegenerusGameWhaleModule.sol:1018` | The deployed claim WHALE-01 converges onto (D-01..D-04 already realized). |
| **`whalePassClaims` counter (the existing pending storage)** | `PayoutUtils.sol:52`, `JackpotModule.sol:1410`, `WhaleModule.sol:1020/1024` | The D-02 counter already exists (jackpot-fed). |
| **`_queueWhalePassClaimCore`** | `DegenerusGamePayoutUtils.sol:45` | The reference O(1) writer the box-open record mirrors. |
| **`_queueTicketRange`** ("optimized for whale pass claims") | `DegenerusGameStorage.sol:647` | The contiguous far-future queue the claim uses; the freeze gate at `:655/:661`. |
| **`processTicketBatch` callers** | `AdvanceModule.sol:561` (gameover drain), `:1496` (`_runProcessTicketBatch`) | The two live callers proving MINTDIV-01 reachability. |
| **autoOpen gas-weight (WHALE-03)** | `DegenerusGame.sol:1561` (`OPEN_NORMAL_GAS_UNIT`), `:1687` (`autoOpen`), `:1728` (the `weighted +=` math) | The carve-out WHALE-03 retires. |
| **`hasAnyLazyPass` impl (the level-horizon source)** | `DegenerusGame.sol:1520` | Where the new `lazyPassHorizon` view lives (D-11). |

## IMPL-335 Edit-Order Map (D-18 — producer-before-consumer, recorded by SPEC)

The single batched diff (BATCH-02) must avoid any intermediate broken state. Recommended order:

1. **Storage / shared surface first (producers):**
   - `DegenerusGameStorage.sol` — no structural change needed if reusing `whalePassClaims` (it lives outside Storage, in the inherited state) + `_queueTicketRange`/`_applyWhalePassStats` (unchanged). Confirm the `whalePassClaims` declaration location (inherited mapping) for the box-open writer.
2. **Game facade (the new view + the autoOpen change):**
   - `DegenerusGame.sol` — add `lazyPassHorizon` view (D-11); retire the autoOpen gas-weight → flat `OPEN_BATCH` (WHALE-03); add/confirm the `claimWhalePass` external entrypoint home (Claude's discretion: delegate to WhaleModule vs expose the existing module fn).
3. **LootboxModule (the WHALE-01 consumer of the storage + the box-open record):**
   - Replace `_activateWhalePass`'s 100-loop + `_applyWhalePassStats` call with the O(1) `whalePassClaims += grant` record (reconcile the grant shape per Q1). Box-open writes no `mintPacked_`.
4. **MintModule (independent, if MINTDIV-01 reachable — it is):**
   - `:716` `processed += writesUsed >> 1` → `processed += take`. Isolated one-liner; no dependency ordering with WHALE.
5. **AfKing + BurnieCoin (the AFSUB cluster, mutually dependent on D-09):**
   - AfKing: remove `burnForKeeper` calls (`:437`, `:641`), the `paidThroughDay`/`WINDOW_DAYS` window, `FLAG_WINDOW_PAID`; repurpose the `Sub` slot → `validThroughLevel`; rewrite `subscribe` + the `_autoBuy:630` validity check + crossing refresh-or-evict (reads `lazyPassHorizon`). Preserve OPEN-E `fundingSource` + the tombstone/swap-pop reclaim.
   - BurnieCoin: delete `burnForKeeper:472` + `KeeperBurn:85` + the `onlyAfKing:549` modifier (after confirming no other `onlyAfKing` user — grep shows none).
   - **Order within the cluster:** delete the AfKing call sites BEFORE deleting the BurnieCoin impl (so the iface mismatch never compiles broken), OR delete both atomically in the single diff (the batched-diff model makes this a non-issue — it compiles as a whole).

**Shared `_queueTickets` reconciliation (D-18):** WHALE touches the queue indirectly (via `_queueTicketRange` in the claim path); MINTDIV audits the consumer (`processTicketBatch` reads `ticketsOwedPacked`). The two edits are on opposite ends of the same data (writer vs reader) and do NOT conflict — WHALE moves WHEN the queue is written (claim-time), MINTDIV fixes HOW the reader advances its index. The SPEC records that they are independent within the diff.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The box-open whale-pass grant (2/lvl + 40/lvl≤10) can be reconciled onto the existing `claimWhalePass`/`whalePassClaims` flat-`N/lvl` machinery via a shape param or a claim variant | Architecture Pattern 1, Pitfall 2 | If the shapes are irreconcilable without a 2nd counter, WHALE-01's surface grows; the SPEC must decide (Q1). LOW risk — both use `_queueTicketRange`; a per-level multiplier is the obvious bridge. |
| A2 | A single player can accumulate `owed > maxT` (~292 warm / ~99 cold) at one *current-read* level | MINTDIV-01 §leg(b) | If owed is somehow capped ≤ maxT at current-read levels, MINTDIV would be REFUTED. MEDIUM risk — large purchases + passes + vault tickets plainly stack; TST-03 codifies the exact scenario. The divergence MECHANISM (leg a) is certain regardless. |
| A3 | Removing `burnForKeeper` orphans `onlyAfKing` with no other user | State of the Art / Edit-Order | Grep confirms only `burnForKeeper` uses `onlyAfKing` in BurnieCoin. LOW risk — verified by grep. |
| A4 | `type(uint24).max` deity sentinel never crosses given `level` is uint24 | Pattern 3 | If `level` could reach `type(uint24).max` the sentinel would falsely cross — but that's ~16.7M levels, unreachable. LOW risk. |

**These are the only `[ASSUMED]` claims. A1 and A2 are the two the SPEC-authoring tasks should surface as explicit SPEC decisions / TST-03 targets — not silent.**

## Open Questions (RESOLVED)

Both questions below were RESOLVED by the USER at plan-phase time (2026-05-27) and locked in CONTEXT.md's Post-Research Reconciliation block. They are no longer open; the plans implement the resolutions.

1. **Whale-pass grant-shape reconciliation — RESOLVED (D-21).** USER chose **(b) converge to the existing flat shape**: routing box-open into the existing `claimWhalePass`/`whalePassClaims` machinery, the box-open whale pass adopts the existing flat per-level shape — the ≤level-10 `40/lvl` bonus band is DROPPED and the per-level rate aligns to the existing claim. This is a deliberate economic reduction; the value delta is routed to the 338 SWEEP economic-analyst per D-06. Single counter, simplest IMPL (no grant-shape param, no second counter). *(Original framing: box-open grants 2/lvl + 40/lvl(≤10) over 100 levels at `_activateWhalePass:1250-1256`; the existing `claimWhalePass` grants a flat `N/lvl × 100`; `_applyWhalePassStats` identical for both.)*

2. **gameOver-forfeit rule — RESOLVED (D-23).** Unclaimed `whalePassClaims` at `gameOver` are **forfeit** (no future levels to materialize); consistent with "claim whenever is fine" + the existing `_livenessTriggered` revert at `claimWhalePass:1019`. The SPEC records this as one sentence in the design-lock doc; no auto-claim-at-gameOver.

## Environment Availability

> The phase is paper-only (writes Markdown SPEC artifacts). The IMPL it governs (335) needs the toolchain below; documented for completeness so the SPEC's TST-architecture note is grounded.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Foundry (`forge`) | IMPL/TST compile + the v43 freeze-fuzz harness | (assumed present — v49 ran 666/42/17) | — | — |
| `git` | grep-attestation vs `b0511ca2` | ✓ | — | — |

**No external dependency blocks Phase 334** — it produces Markdown only. (The grep-attestation was performed with `git` + `grep`, both present.)

## Validation Architecture

> The phase produces written SPEC artifacts, not code. There is no test to run for Phase 334 itself. The SPEC's deliverables FEED the test phase (336), where TST-01/02/03/04 are authored. This section records the test-architecture inputs the SPEC should note so 336 plans cleanly.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (`forge test`) — the established v44–v49 harness |
| Freeze-fuzz harness | `test/fuzz/RngLockDeterminism.t.sol` (v43; TST-01 extends it) |
| Phase-334 verification | Document-completeness review (the 5 Success Criteria) — no code execution |

### Phase 334 acceptance (what makes the SPEC artifacts "done")
| SC | Artifact | Verifiable by |
|----|----------|---------------|
| SC1 | Design-lock doc with settled shared signatures (whale-pass storage + `claimWhalePass` sig; AfKing `validThroughLevel` + refresh-or-evict; MintModule alignment) + reconciled `_queueTickets` surface | Doc contains each signature + the Q1 grant-shape decision + the IMPL-335 edit-order map |
| SC2 | WHALE-04 freeze proof (§1–§5 slot-by-slot) | Doc maps box-open + claim writes to slots and proves each freeze-safe + re-attests v45 |
| SC3 | MINTDIV-01 verdict = PROVEN REACHABLE + the −17/+1 trace + 2 callers + concrete scenario | Doc records verdict → MINTDIV-02 ships the one-liner |
| SC4 | RNGAUDIT R1→R4 + context-pack skeleton sketch | Doc contains the round headings + the VRF entry/consume/lock inventory + the "no answer key" constraint |
| SC5 | Grep-attestation table vs `b0511ca2` with drift corrected | The table above (every anchor confirmed; `_livenessTriggered` def `:1213` vs gate `:571`, `Sub` `:86-93`, `processFutureTicketBatch` `:393` corrections recorded) |

### Wave 0 Gaps
- None for Phase 334 (no test infra needed — paper-only). The TST-01 freeze-fuzz gap (extending `RngLockDeterminism.t.sol`) is a Phase-336 concern, noted here only so the SPEC flags it for 336.

## Security Domain

> `security_enforcement` is effectively ON for this project (it is a smart-contract audit repo; `feedback_security_over_gas` is the hard floor). ASVS web categories are mostly N/A for on-chain Solidity; the relevant analog is the project's own RNG-freeze + economic-soundness invariant set.

### Applicable invariant categories (the project's analog to ASVS)

| Category | Applies | Standard Control |
|----------|---------|-----------------|
| RNG-freeze (every VRF-interacting slot frozen [request→unlock]) | YES | The `_queueTickets`/`_queueTicketRange` far-future + `rngLockedFlag` gate; `_livenessTriggered` terminal freeze; `v45-vrf-freeze-invariant`. WHALE-04 re-proves this for the split. |
| Trait-derivation correctness (deterministic per-ticket LCG) | YES | Contiguous `startIndex` advance; MINTDIV-02 aligns `:716`→`:502`. |
| Keeper/sub access control (consent boundary) | YES | OPEN-E subscribe-time `isOperatorApproved(fundingSource, subscriber)` gate (`AfKing:393-403`); the SUB is the consent unit (GASOPT-05). Preserved under pass-gating (AFSUB-04). |
| Economic soundness (claim-timing not abusable) | YES (deferred to SWEEP) | D-06: the claim-timing degree of freedom is the USER's assertion, re-attested by the 338 economic-analyst. SPEC records it as an assertion, not a proof. |

### Known threat patterns for this stack (v50-relevant)

| Pattern | STRIDE | Standard Mitigation (in scope for v50) |
|---------|--------|---------------------------------------|
| Add tickets after the resolving VRF word is known | Tampering | `_queueTickets` far-future+`rngLock` revert + `_livenessTriggered` revert (WHALE-04 §2). |
| Deferred-claim timing alters RNG-derived outcome | Tampering | Claim queues only future levels; current-window slots untouched (WHALE-04 §1–§3). 338 SWEEP charges this explicitly (SWEEP-01). |
| Trait-index divergence on owed-split | Tampering (silent correctness defect) | MINTDIV-02 contiguous advance (PROVEN reachable). |
| Sub eviction griefing / missed-day (H-CANCEL-SWAP-MISS class) | Denial of Service | In-place tombstone + swap-pop membership invariant preserved (AFSUB-05, D-12). |
| Third-party funding escalation (OPEN-E) | Elevation of Privilege | The 4 structural protections re-attested under pass-gating (AFSUB-04). |

## Sources

### Primary (HIGH confidence)
- The frozen contract source at working-tree HEAD `9d38b636` (= `b0511ca2` for `contracts/`, diff empty) — all `file:line` grep-attested directly. Files: `DegenerusGameLootboxModule.sol`, `DegenerusGameWhaleModule.sol`, `DegenerusGamePayoutUtils.sol`, `DegenerusGameJackpotModule.sol`, `DegenerusGameStorage.sol`, `DegenerusGameMintModule.sol`, `DegenerusGameAdvanceModule.sol`, `AfKing.sol`, `BurnieCoin.sol`, `DegenerusGame.sol`.
- `git diff b0511ca2 HEAD -- contracts/` → empty (baseline-tree-identity confirmation).
- The MINTDIV divergence arithmetic — computed against the real `WRITES_BUDGET_SAFE=550` + the `maxT`/`writesUsed` formulas read from source.
- `.planning/phases/334-.../334-CONTEXT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` (the locked decisions + success criteria).

### Secondary (MEDIUM confidence)
- Project MEMORY.md + feedback/seed files (`v49-whale-pass-claim-refactor-seed`, `v50-afking-pass-only-sub-simplify-seed`, `mintmodule-processed-advance-divergence-seed`, `v45-vrf-freeze-invariant`, `feedback_security_over_gas`, `feedback_verify_call_graph_against_source`, `feedback_frozen_contracts_no_future_proofing`) — design rationale + prior-decision context.

### Tertiary (LOW confidence)
- None. Every factual claim is grep-attested against source or computed from source constants.

## Metadata

**Confidence breakdown:**
- Standard stack / surfaces: HIGH — every `file:line` grep-confirmed against the frozen tree.
- MINTDIV-01 reachability mechanism (leg a): HIGH — arithmetic fact from source constants.
- MINTDIV-01 reachability scenario (leg b, max-owed): MEDIUM — the branch is provably live (2 callers, owed can exceed maxT); the exact minimal owed scenario is for TST-03 to codify (A2).
- WHALE-04 freeze proof: HIGH — built entirely on existing, grep-confirmed gates (`_queueTickets:571/573`, `_queueTicketRange:655/661`, `claimWhalePass:1019`).
- WHALE-01 convergence (existing machinery): HIGH — `claimWhalePass:1018` + `whalePassClaims` + `_queueTicketRange:647` confirmed present.
- Whale-pass grant-shape reconciliation (Q1): MEDIUM — the one genuine open design decision for the SPEC.
- AfKing pass-gating realization: HIGH — the day-window shape it mirrors is grep-confirmed (`_autoBuy:630-631`, `subscribe:374`, `Sub:86`).
- RNGAUDIT structure inputs: HIGH — VRF entry/consume/lock points grep-confirmed.

**Research date:** 2026-05-27
**Valid until:** Until the next `contracts/*.sol` edit (i.e., until IMPL 335 lands). The grep-attestation is exact against `b0511ca2` and stays valid as long as the baseline is unchanged. ~30 days for the design conclusions (stable, frozen subject).
