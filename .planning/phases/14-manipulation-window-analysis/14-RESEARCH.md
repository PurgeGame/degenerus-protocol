# Phase 14: Manipulation Window Analysis - Research

**Researched:** 2026-03-14
**Domain:** VRF RNG adversarial timing analysis / smart contract security audit
**Confidence:** HIGH

## Summary

Phase 14 requires an exhaustive adversarial analysis of every temporal window between VRF entropy arrival and its consumption, determining what state can change within each window and whether an attacker can exploit that change. The analysis builds directly on Phase 12's inventory (9 daily + 8 lootbox consumption points, 27 entry points, 19 rngLockedFlag sites) and Phase 13's delta verification (all 8 v1.0 attacks confirmed PASS, 10 new attack vectors all SAFE).

The protocol has two independent VRF streams (daily and lootbox) with distinct temporal profiles. The daily path uses a two-phase commit: VRF callback stores `rngWordCurrent`, then `advanceGame` processes it with nudge adjustment. The lootbox path finalizes directly in the VRF callback. The 5-day jackpot draw sequence introduces inter-block windows where `rngLockedFlag` clears between daily `advanceGame` calls but `prizePoolFrozen` stays true. Each of these windows requires systematic analysis of what user actions are possible and whether they can influence outcomes.

**Primary recommendation:** Structure the analysis into 4 plans: (1) per-consumption-point state enumeration for daily and lootbox paths, (2) adversarial timeline for block builder and VRF front-running, (3) inter-block jackpot sequence analysis, (4) consolidated verdict table with evidence.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|-----------------|
| WINDOW-01 | For each RNG consumption point, complete enumeration of state that can change between VRF callback and consumption | Phase 12 inventoried 9 daily + 8 lootbox consumption points with co-state variables; this research maps the temporal windows and mutable state for each |
| WINDOW-02 | Adversarial timeline for block builder + VRF front-running covering both daily and mid-day paths | This research documents the two-phase commit (daily) vs direct-finalize (lootbox) temporal models and identifies block builder capabilities at each stage |
| WINDOW-03 | Inter-block manipulation windows during 5-day jackpot draw sequence | This research traces the rngLockedFlag/prizePoolFrozen lifecycle across jackpot days and identifies what entry points are available in the unlock gaps |
| WINDOW-04 | Verdict table rating each manipulation window as BLOCKED / SAFE BY DESIGN / EXPLOITABLE | This research provides the methodology and evidence framework for rendering verdicts |
</phase_requirements>

## Standard Stack

This phase produces audit analysis documents, not code. No library stack is needed.

### Analysis Tools
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Contract source reading | Trace execution paths and state mutations | Primary evidence source |
| Phase 12 inventory docs | Authoritative list of RNG variables, functions, data flows | Avoids re-deriving the inventory |
| Phase 13 delta docs | Prior attack surface verdicts to build upon | Avoids redundant re-analysis |
| v1.0 audit | Baseline security posture and attack scenario methodology | Established adversarial model |

## Architecture Patterns

### Analysis Structure

The analysis must be organized to systematically cover every RNG consumption point without gaps. The following structure maps to the 4 requirements:

```
audit/v1.2-manipulation-windows.md
  Section 1: Per-Consumption-Point Window Analysis (WINDOW-01)
    1a: Daily consumption points (D1-D9)
    1b: Lootbox consumption points (L1-L8)
  Section 2: Adversarial Timeline (WINDOW-02)
    2a: Daily VRF path timeline
    2b: Mid-day lootbox VRF path timeline
    2c: Block builder capabilities at each stage
  Section 3: Inter-Block Jackpot Sequence (WINDOW-03)
    3a: 5-day jackpot phase state machine
    3b: Available actions between advanceGame calls
    3c: Cross-day state mutation analysis
  Section 4: Verdict Table (WINDOW-04)
    4a: Consolidated verdicts with evidence
    4b: Comparison with v1.0 findings
```

### Temporal Model for Daily RNG Path

The daily VRF path has a multi-block temporal window:

```
Block N:     advanceGame() -> _requestRng() -> sets rngLockedFlag=true
             [VRF request sent to Chainlink]
Block N+K:   rawFulfillRandomWords() stores rngWordCurrent
             [rngLockedFlag still true, word awaits processing]
Block N+K+M: advanceGame() -> rngGate() -> _applyDailyRng()
             [nudge applied, word consumed for daily draws]
             -> _unlockRng() clears rngLockedFlag
```

**Window 1 (N to N+K):** VRF in-flight. rngLockedFlag=true blocks 12 entry points. Purchases go to write buffer. Pool frozen.
**Window 2 (N+K to N+K+M):** VRF word stored but not yet consumed. rngLockedFlag still true. Same restrictions as Window 1.
**Window 3 (N+K+M, within advanceGame):** Single transaction -- consumption is atomic with unlock.

### Temporal Model for Lootbox RNG Path

The lootbox VRF path finalizes in the callback:

```
Block N:     requestLootboxRng() -> VRF request
             [rngLockedFlag=false, rngRequestTime!=0]
Block N+K:   rawFulfillRandomWords() -> lootboxRngWordByIndex[index] = word
             [Word immediately available for consumers]
Block N+K+M: User calls openLootBox/resolveBets/etc.
             [Per-player entropy: keccak256(word, player, day, amount)]
```

**Window (N to N+K):** VRF in-flight. rngRequestTime!=0 blocks concurrent requests. Purchases still allowed (assigned to current lootboxRngIndex, word unknown).
**No exploitation window exists** because consumer outcomes are per-player-deterministic once the word is set.

### Temporal Model for 5-Day Jackpot Sequence

```
Day 0 (last purchase day):
  advanceGame -> rngGate -> _requestRng (rngLockedFlag=true, prizePoolFrozen=true)
  VRF arrives -> advanceGame processes -> jackpotPhaseFlag=true
  -> _unlockRng (rngLockedFlag=false) BUT prizePoolFrozen stays true

Day 1-4 (jackpot days):
  Each day: advanceGame -> rngGate -> _requestRng (rngLockedFlag=true)
  VRF arrives -> advanceGame processes daily draws
  -> _unlockRng (rngLockedFlag=false)

  INTER-BLOCK GAP: rngLockedFlag=false, prizePoolFrozen=true
  Available actions: purchases (write buffer), lootbox opens, coinflip deposits,
  degenerette bets/resolution, deity boons
  Blocked: deity pass purchase (? -- rngLockedFlag=false so NOT blocked),
           reverseFlip (rngLockedFlag=false so NOT blocked),
           claimDecimatorJackpot (prizePoolFrozen=true, BLOCKED)

Day 5 (final):
  Same as Day 1-4, then _endPhase -> _unfreezePool (prizePoolFrozen=false)
```

**Critical insight for inter-block analysis:** Between jackpot-day advanceGame calls, `rngLockedFlag` is false. This means `reverseFlip` (nudge) and `purchaseDeityPass` are callable. These are RNG influencers:
- `reverseFlip` adds nudge to NEXT day's VRF word. During jackpot phase, each day gets a fresh VRF, so nudges applied between Day N and Day N+1 affect Day N+1's draws.
- `purchaseDeityPass` changes `deityPassOwners` and `deityBySymbol`, which are co-state for jackpot winner selection.

Both of these were analyzed in v1.0 and Phase 13 and found SAFE, but the inter-block jackpot context needs explicit verification.

### Per-Consumption-Point Analysis Template

For each of the 17 consumption points (D1-D9, L1-L8), the analysis must document:

1. **Consumption point ID and location** (from Phase 12 inventory)
2. **Entropy source** (which VRF word, how derived)
3. **Co-state variables** (what other state feeds into the outcome calculation)
4. **Temporal window** (when is entropy committed vs. when is co-state read?)
5. **Mutable co-state during window** (which co-state variables CAN change between VRF arrival and consumption?)
6. **Entry points that can mutate co-state** (from Phase 12 entry point matrix)
7. **Guards preventing mutation** (rngLockedFlag, prizePoolFrozen, etc.)
8. **Verdict** (BLOCKED / SAFE BY DESIGN / EXPLOITABLE)

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| RNG consumption point list | Re-derive from contracts | Phase 12 data flow doc (v1.2-rng-data-flow.md Section 1.3 + 2.3) | Already verified and complete |
| Entry point x state matrix | Re-trace from source | Phase 12 cross-reference (v1.2-rng-data-flow.md Section 5) | 27 entry points already mapped |
| Guard analysis | Re-verify guards | Phase 12 guard analysis (v1.2-rng-functions.md Section 3) | 19 rngLockedFlag + 11 prizePoolFrozen sites documented |
| Attack scenario baselines | Start from scratch | v1.0 audit + Phase 13 delta docs | 8 scenarios already PASS, 10 new vectors already SAFE |
| Variable lifecycle traces | Re-read storage contract | Phase 12 variable inventory (v1.2-rng-storage-variables.md) | 9 direct + 19 influencing variables with full traces |

## Common Pitfalls

### Pitfall 1: Conflating VRF Callback with Consumption
**What goes wrong:** Assuming the VRF word is consumed when it arrives in `rawFulfillRandomWords`, when actually the daily path stores it in `rngWordCurrent` and defers consumption to the next `advanceGame` call.
**Why it happens:** The lootbox path DOES finalize in the callback, creating inconsistency.
**How to avoid:** Always distinguish the two temporal models (daily = two-phase commit, lootbox = direct finalize).
**Warning signs:** Analysis says "no window exists between arrival and consumption" for daily path.

### Pitfall 2: Ignoring Inter-Block Gaps During Jackpot Phase
**What goes wrong:** Assuming rngLockedFlag is always true during the jackpot phase, when actually it clears between each day's advanceGame processing.
**Why it happens:** rngLockedFlag is only set during VRF in-flight and cleared by `_unlockRng` after daily processing.
**How to avoid:** Trace the exact rngLockedFlag lifecycle across the 5-day sequence, noting each unlock point.
**Warning signs:** Analysis says "deity pass purchase blocked during jackpot phase" without verifying rngLockedFlag state.

### Pitfall 3: Missing the Piggyback Pattern
**What goes wrong:** Analyzing daily and lootbox consumption independently when `_finalizeLootboxRng` during `rngGate` creates a cross-path interaction (daily word written to lootbox index).
**Why it happens:** The daily and lootbox streams appear independent but share the piggyback path.
**How to avoid:** Explicitly trace `_finalizeLootboxRng` calls at AdvanceModule:766 and :815, noting that the daily finalized word is also stored in `lootboxRngWordByIndex` and `lastLootboxRngWord`.
**Warning signs:** Analysis treats daily and lootbox entropy as completely independent without mentioning piggyback.

### Pitfall 4: Overlooking Co-State Changes vs. Direct RNG Manipulation
**What goes wrong:** Focusing only on whether the VRF word itself can be manipulated, when the real attack surface is changing co-state (bucket composition, queue content, deity pass ownership) that the VRF word indexes into.
**Why it happens:** VRF words are cryptographically secure, so analysis stops at "word is unpredictable."
**How to avoid:** For each consumption point, enumerate every co-state variable and check if ANY entry point can modify it during the relevant window.
**Warning signs:** Analysis gives "SAFE" verdict based solely on VRF unpredictability without analyzing co-state mutability.

### Pitfall 5: Incomplete Block Builder Model
**What goes wrong:** Assuming block builders can only reorder transactions, when they can also include/exclude transactions and read the VRF callback payload from the mempool before inclusion.
**Why it happens:** Standard MEV analysis focuses on reordering.
**How to avoid:** Model block builder as: can read all pending txs, can choose ordering, can include/exclude any tx, can sandwich, can delay inclusion by N blocks.
**Warning signs:** Analysis doesn't mention tx inclusion/exclusion as a capability.

## Code Examples

### Key Code: rngGate Daily Processing (AdvanceModule:737-783)

The central daily RNG gate. When VRF word is available for the current day:
1. `_applyDailyRng(day, currentWord)` applies nudge offset
2. `coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)` processes coinflips
3. `_finalizeLootboxRng(currentWord)` writes to lootbox index (piggyback)
4. Returns finalized word for jackpot processing

All three steps happen atomically within the `advanceGame` transaction. No user action can intervene between these steps.

### Key Code: Jackpot Phase Unlock (AdvanceModule:280-291 and :366-368)

Purchase phase daily jackpot:
```
payDailyJackpot(false, purchaseLevel, rngWord);  // line 280
_payDailyCoinJackpot(purchaseLevel, rngWord);     // line 281
_unlockRng(day);                                   // line 288
_unfreezePool();                                   // line 289
```

Jackpot phase coin+tickets completion:
```
payDailyJackpotCoinAndTickets(rngWord);           // line 356
_unlockRng(day);                                   // line 366
```

Note: `_unfreezePool` is NOT called between jackpot days -- only at phase end (line 362).

### Key Code: VRF Callback Routing (AdvanceModule:1326-1345)

```
if (rngLockedFlag) {
    rngWordCurrent = word;          // Daily path: stores for later advanceGame
} else {
    // Lootbox path: finalizes immediately
    index = lootboxRngRequestIndexById[requestId];
    lootboxRngWordByIndex[index] = word;
    vrfRequestId = 0;
    rngRequestTime = 0;
}
```

The routing is deterministic based on `rngLockedFlag` at callback time. A block builder cannot change which path executes because `rngLockedFlag` is only writable by `_finalizeRngRequest` (set true) and `_unlockRng`/`_unlockRngEmergency` (set false), both inside `advanceGame`.

## State of the Art

### Chainlink VRF Security Model

| Property | Value | Impact on Analysis |
|----------|-------|-------------------|
| VRF word unpredictability | Cryptographic guarantee (VRF proof verified on-chain) | Attacker cannot predict VRF output |
| VRF callback delivery | 1-N blocks after request (typically 1-3 on mainnet) | Window between request and callback is 1+ blocks |
| VRF callback tx visibility | Visible in mempool before inclusion | Block builder can read word before inclusion |
| VRF callback ordering | Block builder controls tx ordering within block | Builder can place user txs before/after callback |

### Block Builder Adversarial Model

For this analysis, the adversary is assumed to have:
- **Read access:** Can read all pending transactions including VRF callback payload
- **Ordering control:** Can order transactions within a block they build
- **Inclusion control:** Can include or exclude any pending transaction
- **Multi-block persistence:** Can maintain position across multiple consecutive blocks (MEV-Boost)
- **No VRF control:** Cannot predict or influence the VRF random word
- **No protocol bypass:** Cannot call internal functions or bypass access controls

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual audit analysis (no automated tests) |
| Config file | N/A |
| Quick run command | N/A (document review) |
| Full suite command | N/A (document review) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WINDOW-01 | Per-consumption-point state enumeration | manual-only | Review audit/v1.2-manipulation-windows.md Section 1 | Wave 0 |
| WINDOW-02 | Adversarial timeline | manual-only | Review audit/v1.2-manipulation-windows.md Section 2 | Wave 0 |
| WINDOW-03 | Inter-block jackpot sequence | manual-only | Review audit/v1.2-manipulation-windows.md Section 3 | Wave 0 |
| WINDOW-04 | Verdict table | manual-only | Review audit/v1.2-manipulation-windows.md Section 4 | Wave 0 |

**Justification for manual-only:** This phase produces adversarial analysis documentation, not executable code. Verification is by document review against the per-consumption-point template and verdict criteria.

### Sampling Rate
- **Per task commit:** Verify section completeness against template
- **Per wave merge:** Cross-check verdicts against Phase 12 inventory (no consumption point missed)
- **Phase gate:** All 17 consumption points have verdicts; no EXPLOITABLE findings without escalation

### Wave 0 Gaps
None -- no test infrastructure needed for audit document production.

## Open Questions

1. **Deity pass purchase during jackpot inter-block gap**
   - What we know: rngLockedFlag=false between jackpot days, so `purchaseDeityPass` is NOT blocked by rngLockedFlag
   - What's unclear: Is there another guard (e.g., jackpotPhaseFlag check in deity purchase path) that blocks it?
   - Recommendation: Plan should explicitly trace deity pass purchase code path during jackpot phase to confirm whether it's gated by any condition other than rngLockedFlag

2. **reverseFlip during jackpot inter-block gap**
   - What we know: rngLockedFlag=false between jackpot days, so `reverseFlip` is callable. Nudges affect the next day's VRF word.
   - What's unclear: Is the economic cost of nudges ($100+ BURNIE compounding) sufficient to make this a non-concern, or does the jackpot prize value make it worth attempting?
   - Recommendation: Plan should calculate worst-case economic analysis -- max nudge count affordable by a whale vs. probability shift in 2^256 word space

3. **processTicketBatch entropy source during jackpot phase**
   - What we know: `processTicketBatch` reads `lastLootboxRngWord` for trait entropy. During jackpot phase, new purchases queue to write buffer and are processed mid-jackpot via `_swapTicketSlot` within `advanceGame`.
   - What's unclear: Which `lastLootboxRngWord` value is used for jackpot-phase ticket processing -- the piggybacked daily word or a prior lootbox word?
   - Recommendation: Plan should trace the exact `lastLootboxRngWord` value at the point jackpot-phase ticket processing occurs

## Sources

### Primary (HIGH confidence)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- rngGate, rawFulfillRandomWords, requestLootboxRng, advanceGame (direct source reading)
- `audit/v1.2-rng-data-flow.md` -- Phase 12 data flow diagrams and cross-reference matrix
- `audit/v1.2-rng-storage-variables.md` -- Phase 12 storage variable inventory with lifecycle traces
- `audit/v1.2-rng-functions.md` -- Phase 12 function catalogue and guard analysis
- `audit/v1.2-delta-attack-reverification.md` -- Phase 13 attack re-verification
- `audit/v1.2-delta-new-attack-surfaces.md` -- Phase 13 new attack surface analysis
- `audit/v1.0-rng-and-changes-audit.md` -- v1.0 baseline audit

### Secondary (MEDIUM confidence)
- Chainlink VRF v2.5 security model (training data, well-established)

## Metadata

**Confidence breakdown:**
- Temporal models: HIGH - derived directly from contract source code
- Consumption point inventory: HIGH - Phase 12 provides verified inventory
- Inter-block gap analysis: HIGH - rngLockedFlag lifecycle traced in contract source
- Block builder model: HIGH - standard MEV adversarial model, well-established
- Open questions (deity/nudge during jackpot): MEDIUM - need explicit code path tracing to confirm

**Research date:** 2026-03-14
**Valid until:** Indefinite (contract code is fixed, not a moving target)
