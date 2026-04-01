# Phase 69: Mutation Verdicts - Research

**Researched:** 2026-03-22
**Domain:** Solidity smart contract commitment window analysis -- VRF mutation verdicts
**Confidence:** HIGH

## Summary

Phase 69 consumes the Phase 68 inventory (51 variables, 121 mutation paths, 7 outcome categories) and produces binary SAFE/VULNERABLE verdicts for every variable. The core question is: "Can a non-admin actor mutate this variable between VRF request and fulfillment in a way that influences outcomes?"

The Phase 68 mutation surface catalog already contains the raw material for every verdict. 87 of 121 mutation paths are permissionless. The key analytical work is classifying each permissionless mutation by (1) which commitment window it falls within (daily vs mid-day), (2) what guards prevent it (rngLockedFlag, prizePoolFrozen, double-buffer, lootboxRngIndex keying), and (3) whether the mutation can actually influence an outcome determined by the VRF word currently in-flight.

A preliminary scan identifies two categories requiring careful analysis: (a) BurnieCoinflip's `depositCoinflip()` lacks an rngLockedFlag guard but targets future days via `_targetFlipDay()`, and (b) purchase-path writes to `currentPrizePool`/`prizePoolsPacked` during the mid-day lootbox commitment window (where prizePoolFrozen is NOT set). The former appears SAFE by design (bets target day+1, resolution uses current day's word); the latter requires outcome-influence analysis (does prize pool size affect any VRF-dependent computation during mid-day fulfillment?).

**Primary recommendation:** Structure verdicts per-variable with a three-column proof: (1) permissionless mutation paths from Phase 68, (2) guard analysis (what prevents mutation during each window), (3) outcome-influence chain (even if mutable, does it feed into outcome computation?). Group by protection mechanism for clarity.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CW-04 | Cross-reference proof that no external function callable by a non-admin actor can mutate any committed input between VRF request and fulfillment | Phase 68 mutation surface catalog provides the exhaustive list of 87 permissionless paths; this phase produces the cross-reference proof by analyzing each against both commitment windows (daily + mid-day) |
| MUT-01 | Each variable receives a binary verdict: SAFE (immutable in commitment window) or VULNERABLE (mutable by player action in window) | Phase 68 catalogs all 51 variables; this phase applies the verdict methodology per-variable with supporting evidence |
| MUT-02 | Every VULNERABLE variable includes a specific fix recommendation with severity rating | C4A severity taxonomy (Critical/High/Medium/Low/Info) applied to any variables that fail the SAFE test |
| MUT-03 | Call-graph analysis covers indirect mutation paths (A calls internal B which writes C) to at least 3 levels of depth | Phase 68 already tracked D0-D3+ depth for all 121 paths; this phase verifies completeness and adds any missed indirect paths |
</phase_requirements>

## Project Constraints (from CLAUDE.md)

- **Contract file authority:** Only read contracts from `contracts/` directory; stale copies exist elsewhere
- **No contract commits:** NEVER commit contracts/ or test/ changes without explicit user approval
- **Present and wait:** Present fix recommendations and wait for explicit approval before editing code
- **Backward trace discipline:** Every RNG audit must trace BACKWARD from each consumer to verify word was unknown at input commitment time
- **Commitment window check:** Every RNG audit must check what player-controllable state can change between VRF request and fulfillment
- **Core value:** Every finding a C4A warden could submit is identified and either fixed or documented as known before the audit begins

## Standard Stack

This phase is pure audit analysis -- no new libraries or tools required. The "stack" is the existing audit methodology and contract reading.

### Core Tools
| Tool | Purpose | Why Standard |
|------|---------|--------------|
| Solidity source reading | Primary evidence source for verdicts | All verdicts must cite contract line numbers |
| `forge inspect` | Authoritative slot number validation | Phase 68 validated all 51 slots; any new variables found need same treatment |
| Phase 68 inventory (`audit/v3.8-commitment-window-inventory.md`) | Input data: all 51 variables, 121 mutation paths, 7 outcome categories | This is the canonical inventory the verdicts consume |

### Audit Methodology
| Method | Purpose | When to Use |
|--------|---------|-------------|
| Guard analysis | Determine if rngLockedFlag/prizePoolFrozen/double-buffer blocks mutation | For every permissionless mutation path |
| Outcome-influence chain | Even if mutable, does it feed into outcome computation? | For mutations not blocked by guards |
| Temporal analysis | When is the variable read vs when can it be written? | For variables with index-keyed separation (lootbox, coinflip) |

## Architecture Patterns

### Verdict Document Structure

The output document should extend `audit/v3.8-commitment-window-inventory.md` (append a new section) rather than creating a separate file, maintaining the single-source-of-truth pattern established in Phase 68.

```
audit/v3.8-commitment-window-inventory.md (extended)
  +-- ## Mutation Verdicts (CW-04, MUT-01, MUT-02, MUT-03)
      +-- ### Verdict Methodology
      +-- ### Protection Mechanism Summary
      +-- ### Per-Variable Verdicts
      |   +-- #### DegenerusGameStorage Variables
      |   +-- #### BurnieCoinflip Variables
      |   +-- #### StakedDegenerusStonk Variables
      +-- ### Cross-Reference Proof (CW-04)
      +-- ### Vulnerability Report (MUT-02)
      +-- ### Call-Graph Depth Verification (MUT-03)
```

### Pattern 1: Guard-Based Classification

**What:** Group variables by their primary protection mechanism to avoid repeating the same guard analysis 51 times.

**Categories:**

1. **VRF-only write** -- Variable is only written by VRF coordinator or advanceGame. No permissionless external function writes it. SAFE by definition.
   - Examples: lootboxRngWordByIndex, lastLootboxRngWord, coinflipDayResult, rngWordByDay

2. **rngLockedFlag guarded** -- The permissionless write path checks `rngLockedFlag` and reverts during daily RNG window. Must separately verify mid-day window safety.
   - Examples: totalFlipReversals (reverseFlip), all StakedDegenerusStonk burn paths, setCoinflipAutoRebuy

3. **Double-buffer protected** -- ticketQueue/ticketsOwedPacked writes go to WRITE slot; reads come from READ slot. Swap happens atomically at RNG request.
   - Examples: ticketQueue[key], ticketsOwedPacked[key][player]

4. **Index-keyed separation** -- Variable is keyed by lootboxRngIndex. New writes use index+1; VRF fulfillment targets index-1. No overlap.
   - Examples: lootboxEth, lootboxDay, lootboxBaseLevelPacked, lootboxEvScorePacked, lootboxBurnie, lootboxDistressEth

5. **Freeze-gated** -- prizePoolFrozen redirects writes to pending accumulators during daily window. Must verify mid-day window behavior.
   - Examples: currentPrizePool (daily), prizePoolPendingPacked

6. **Permissionless and unguarded but outcome-irrelevant** -- Mutable during window but does not feed into any VRF-dependent outcome computation.
   - Examples: claimableWinnings (liability tracking), claimablePool, autoRebuyState, deityBySymbol

7. **Permissionless and mutable AND feeds into outcome** -- VULNERABLE candidates. Requires deepest analysis.
   - Candidates: coinflipBalance (depositCoinflip has no rngLockedFlag guard), bountyOwedTo (record flip path)

### Pattern 2: Two Commitment Windows

**What:** The protocol has two distinct VRF commitment windows with different protection levels.

| Window | Trigger | rngLockedFlag | prizePoolFrozen | Duration |
|--------|---------|---------------|-----------------|----------|
| Daily RNG | advanceGame -> _finalizeRngRequest | TRUE | TRUE | From _swapAndFreeze until advanceGame -> _unlockRng (single tx) |
| Mid-day lootbox | requestLootboxRng | FALSE | FALSE | From requestLootboxRng until rawFulfillRandomWords callback (multi-block) |

**Critical insight:** The daily window is a single atomic transaction (request + VRF callback happens in a later tx, but the request is guarded by rngLockedFlag which blocks most mutations). The mid-day window spans multiple blocks and has weaker guards.

**However:** The mid-day VRF fulfillment (`rawFulfillRandomWords` when `!rngLockedFlag`) ONLY writes `lootboxRngWordByIndex[index]`. It does NOT trigger advanceGame, rngGate, or any outcome computation. The word sits in storage until a player opens a lootbox or resolves a Degenerette bet. Therefore, the mid-day commitment window is about whether mutable state can influence the stored lootbox word itself -- which it cannot, because `rawFulfillRandomWords` directly stores the Chainlink-provided word.

The real question for mid-day is: can mutations between `requestLootboxRng` and `rawFulfillRandomWords` callback influence the LATER consumption of `lootboxRngWordByIndex`? The answer depends on what the consumption paths read at resolution time vs at VRF fulfillment time.

### Pattern 3: Verdict Evidence Format

**What:** Each verdict needs machine-verifiable evidence.

```
#### [Variable Name] (slot X) -- SAFE / VULNERABLE

**Permissionless writers:** [list from Phase 68 CW-03]
**Guard analysis:**
  - Daily window: [guarded by X / not applicable / ...]
  - Mid-day window: [guarded by Y / mutable but outcome-irrelevant / ...]
**Outcome influence:** [which categories from CW-02 consume this variable]
**Verdict:** SAFE -- [one-sentence proof]
```

For VULNERABLE:
```
**Verdict:** VULNERABLE
**Severity:** [C4A rating]
**Attack scenario:** [concrete steps]
**Fix recommendation:** [specific code change]
```

### Anti-Patterns to Avoid

- **Guard-by-proxy assumption:** Do not assume a variable is safe just because its module is "only called by advanceGame." Verify the actual access control on the external entry point, not the internal call chain.
- **Single-window analysis:** Every variable must be analyzed against BOTH commitment windows (daily + mid-day). Phase 68 notes that requestLootboxRng does NOT set rngLockedFlag or prizePoolFrozen.
- **Outcome-irrelevance without proof:** Claiming a variable is "not outcome-affecting" requires tracing it through all 7 outcome categories in the backward-trace catalog. A variable that only appears in leaderboard tracking is different from one that appears in entropy computation.
- **Forward-only analysis:** Phase 68 found 17 variables missed by forward trace. The backward trace revealed purchase-time and burn-time commitments. Verdicts must cover all 51 variables, not just the forward-trace subset.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Variable inventory | Re-catalog variables from scratch | Phase 68 inventory (CW-01/CW-02/CW-03) | Already verified with forge inspect; re-doing risks inconsistency |
| Guard verification | Assume guards from memory | grep + line-number verification against actual contracts | Guards must be verified at the exact code location, not recalled |
| Slot numbers | Compute manually | `forge inspect` output | Authoritative source; Phase 68 already validated all 51 |
| C4A severity rating | Invent criteria | C4A severity taxonomy: High = direct fund loss, Medium = fund loss under specific conditions, Low = informational risk | Standard used across all prior milestones |

## Common Pitfalls

### Pitfall 1: Confusing "mutable" with "vulnerable"
**What goes wrong:** A variable is permissionlessly mutable during a commitment window, but the mutation cannot influence any VRF-dependent outcome. Calling it VULNERABLE creates a false positive.
**Why it happens:** The mutation surface catalog (CW-03) lists ALL mutation paths regardless of outcome influence. Not every mutable variable feeds into outcome computation.
**How to avoid:** For every mutable-during-window variable, trace it through the backward-trace catalog (CW-02). If it does not appear as an input to any of the 7 outcome categories, it is SAFE (mutable but outcome-irrelevant).
**Warning signs:** A VULNERABLE verdict that cannot name a specific outcome category it influences.

### Pitfall 2: Missing the mid-day window
**What goes wrong:** Verdicts only analyze the daily RNG window (rngLockedFlag=true) and miss that the mid-day lootbox window has weaker protections.
**Why it happens:** The daily window is the more obvious commitment window. requestLootboxRng is permissionless and does NOT set rngLockedFlag.
**How to avoid:** Every variable must have TWO lines of analysis: "Daily window: [status]" and "Mid-day window: [status]". Even if the mid-day path only stores a word without computation, variables consumed later by openLootBox or _resolveFullTicketBet must be assessed.
**Warning signs:** A verdict that says "guarded by rngLockedFlag" without addressing the mid-day case.

### Pitfall 3: depositCoinflip as false positive
**What goes wrong:** depositCoinflip() has no rngLockedFlag guard, writes to coinflipBalance, and coinflipBalance appears in Category 1 (Coinflip Win/Loss) backward trace. This looks VULNERABLE.
**Why it happens:** The guard is temporal, not boolean. `_targetFlipDay()` returns `currentDayView() + 1`, so deposits during today's commitment window target TOMORROW's coinflip, not today's. The current day's balance was committed in prior transactions.
**How to avoid:** Check the key used for coinflipBalance writes (targetDay = day+1) vs the key used for reads (epoch = current day). If they are different, the mutation is to a different variable instance.
**Warning signs:** VULNERABLE verdict on coinflipBalance that doesn't account for day-keying.

### Pitfall 4: Indirect mutation via advanceGame itself
**What goes wrong:** advanceGame is permissionless and writes to dozens of variables during VRF processing. If it's treated as "just a caller" rather than "the VRF processing function," indirect mutation paths through it get miscounted.
**Why it happens:** advanceGame writes during VRF processing are PART of the VRF processing, not external mutations of committed inputs. MUT-03 requires depth analysis, but writes BY the VRF processing pipeline to its own state are not commitment window violations.
**How to avoid:** Distinguish between (a) advanceGame writes that occur DURING VRF processing (these are the processing itself) and (b) a player calling advanceGame BETWEEN request and fulfillment (which triggers a DIFFERENT code path because the VRF word hasn't arrived yet).
**Warning signs:** Counting advanceGame's own VRF processing writes as "D1 permissionless mutations."

### Pitfall 5: prizePoolsPacked future pool mutation
**What goes wrong:** purchase() always writes to the future pool share of prizePoolsPacked (10% via PURCHASE_TO_FUTURE_BPS), even during both commitment windows. This is permissionless and unguarded.
**Why it happens:** prizePoolFrozen only protects currentPrizePool and next pool. Future pool accumulation is intentionally unfrozen.
**How to avoid:** Check whether future pool value is consumed by any VRF-dependent computation during the current commitment window. It feeds into _applyTimeBasedFutureTake and _consolidatePrizePools, but both run DURING advanceGame (after VRF fulfillment), not during a pending VRF request.
**Warning signs:** VULNERABLE verdict on prizePoolsPacked that doesn't trace when the future pool value is actually consumed.

## Code Examples

### Commitment Window Guard Pattern (verified)

The rngLockedFlag guard pattern used across the codebase:

```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol:1420
if (rngLockedFlag) revert RngLocked();
```

Applied in:
- `reverseFlip()` (AdvanceModule:1420) -- blocks during daily RNG
- `requestLootboxRng()` (AdvanceModule:675) -- prevents mid-day request during daily lock
- `purchaseDeityPass()` (WhaleModule:467) -- blocks deity purchases during daily RNG
- `depositCoinflip._setCoinflipAutoRebuy()` (BurnieCoinflip:706) -- blocks auto-rebuy toggle
- `burn()/burnWrapped()` (StakedDegenerusStonk:447,465) -- blocks redemption burns during daily RNG

NOT applied in:
- `depositCoinflip()` (BurnieCoinflip:225) -- no guard, but targets day+1 via _targetFlipDay
- `purchase()` (MintModule) -- no rngLockedFlag guard on purchase itself
- `placeFullTicketBets()` (DegeneretteModule) -- no rngLockedFlag guard

### Double-Buffer Protection (verified)

```solidity
// Source: contracts/storage/DegenerusGameStorage.sol:713-718
function _swapTicketSlot(uint24 purchaseLevel) internal {
    uint24 readKey = purchaseLevel ^ (ticketWriteSlot == 0 ? TICKET_SLOT_BIT : 0);
    if (ticketQueue[readKey].length != 0) revert QueueNotEmpty();
    ticketWriteSlot ^= 1;
    ticketsFullyProcessed = false;
}
```

Writes after swap go to the NEW write slot. Reads come from the OLD write slot (now the read slot).

### Index-Keyed Separation (verified)

```solidity
// Source: contracts/modules/DegenerusGameAdvanceModule.sol (requestLootboxRng)
// lootboxRngIndex is incremented BEFORE VRF request
lootboxRngIndex = newIdx;
// VRF fulfillment stores word at (newIdx - 1)
// New purchases use newIdx for their lootbox data
```

Purchases after the request use `lootboxRngIndex` (new value) while the pending VRF fulfillment targets `lootboxRngIndex - 1` (old value). Per-player lootbox data is keyed by index, so new purchases cannot influence the outcome of the pending VRF word.

### coinflipBalance Day-Keying (verified)

```solidity
// Source: contracts/BurnieCoinflip.sol:1060-1062
function _targetFlipDay() internal view returns (uint48) {
    return degenerusGame.currentDayView() + 1;
}
```

Deposits always target tomorrow. processCoinflipPayouts resolves today. No overlap.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Forward-only VRF audit | Forward + backward trace (per project memory) | v3.8 Phase 68 | Found 17 variables missed by forward trace |
| Per-module mutation search | Cross-module search (delegatecall shared storage) | v3.8 Phase 68 | Catches writes from modules that don't directly read the variable |
| Implicit guard assumptions | Explicit guard verification per entry point | This phase | Prevents false "safe" verdicts from assumed protections |

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Foundry (forge) + Hardhat |
| Config file | `foundry.toml` / `hardhat.config.js` |
| Quick run command | `forge test --match-path test/fuzz/VRFCore.t.sol -x` |
| Full suite command | `forge test` (Foundry) + `npx hardhat test` (Hardhat) |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CW-04 | No non-admin mutation of committed inputs between request and fulfillment | manual-only | N/A -- this is an audit document, not runnable code | N/A |
| MUT-01 | Every variable has SAFE/VULNERABLE verdict | manual-only | N/A -- verdicts are analytical, verified by cross-reference | N/A |
| MUT-02 | Every VULNERABLE variable has fix recommendation | manual-only | N/A -- fix recommendations are text, verified by review | N/A |
| MUT-03 | Call-graph depth >= 3 for all mutation surfaces | manual-only | N/A -- depth already tracked by Phase 68 at D0-D3+ | N/A |

**Justification for manual-only:** Phase 69 produces an audit document with analytical verdicts, not runnable code. The verdicts are verified by cross-referencing contract source against the Phase 68 inventory. Existing VRF fuzz tests (VRFCore.t.sol, VRFLifecycle.t.sol, VRFPathCoverage.t.sol) provide runtime coverage of VRF behavior but cannot test "this document correctly analyzes mutation paths."

### Sampling Rate
- **Per task commit:** Verify contract line references cited in verdicts still match source
- **Per wave merge:** Full cross-reference check of all verdicts against Phase 68 mutation surface summary
- **Phase gate:** All 51 variables have verdicts, all VULNERABLE variables have fixes, CW-04 proof is complete

### Wave 0 Gaps
None -- existing test infrastructure is not relevant to this purely analytical phase. The "tests" are the cross-reference proofs within the document itself.

## Open Questions

1. **depositCoinflip during mid-day window: truly no impact?**
   - What we know: depositCoinflip targets day+1 via _targetFlipDay(). processCoinflipPayouts resolves current day. No rngLockedFlag guard.
   - What's unclear: Could there be an edge case where currentDayView() changes between request and fulfillment (e.g., if advanceGame runs and increments the day while a mid-day VRF is pending)? Need to verify that mid-day VRF is only requested AFTER daily RNG is done (the guard at AdvanceModule:675 checks rngLockedFlag is false, meaning daily processing is complete).
   - Recommendation: Verify in contract code that mid-day VRF is mutually exclusive with daily advancement that changes the day counter. If so, depositCoinflip is SAFE by temporal separation.

2. **bountyOwedTo mutation during commitment window**
   - What we know: depositCoinflip can set bountyOwedTo if the deposit breaks the biggest-flip record. But the bounty path has `!game.rngLocked()` guard (BurnieCoinflip:645).
   - What's unclear: bountyOwedTo is read during processCoinflipPayouts to determine who gets the bounty. If set during mid-day window, does it affect the next daily resolution?
   - Recommendation: Verify that bountyOwedTo change during mid-day is benign because the bounty is a side-effect of daily resolution, not an outcome determined by the VRF word. The VRF word determines win/loss; the bounty recipient is independent of VRF randomness.

3. **claimableWinnings/claimablePool mutation scope**
   - What we know: These are modified by claimWinnings(), purchase() (claimable payment), placeFullTicketBets() (claimable payment). They track ETH liability.
   - What's unclear: Do any VRF outcome paths use claimableWinnings as an INPUT (not just output)?
   - Recommendation: Check all 7 backward-trace categories. claimableWinnings appears only as a WRITE destination in forward trace (payDailyJackpot credits winners). It is not an input to outcome computation. The Degenerette path caps payouts at 10% of currentPrizePool, not claimablePool. Likely SAFE.

## Sources

### Primary (HIGH confidence)
- `audit/v3.8-commitment-window-inventory.md` -- Phase 68 complete inventory (forward trace, backward trace, mutation surface)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- VRF fulfillment, rngGate, commitment guards
- `contracts/BurnieCoinflip.sol` -- depositCoinflip, processCoinflipPayouts, guard analysis
- `contracts/StakedDegenerusStonk.sol` -- burn guards, resolveRedemptionPeriod
- `contracts/storage/DegenerusGameStorage.sol` -- storage layout, double-buffer implementation
- `.planning/phases/68-commitment-window-inventory/68-01-SUMMARY.md` -- Phase 68 decisions and methodology
- `.planning/phases/68-commitment-window-inventory/68-02-SUMMARY.md` -- Mutation surface methodology
- `.planning/phases/68-commitment-window-inventory/68-VERIFICATION.md` -- Phase 68 verification (3/3 truths)

### Secondary (MEDIUM confidence)
- Project memory: `feedback_rng_backward_trace.md`, `feedback_rng_commitment_window.md` -- audit methodology requirements

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- no new tools needed, pure analytical phase consuming Phase 68 output
- Architecture: HIGH -- verdict structure directly follows from Phase 68 inventory format
- Pitfalls: HIGH -- all pitfalls identified from actual contract code analysis and Phase 68 findings

**Research date:** 2026-03-22
**Valid until:** Indefinite (contracts are static audit targets; validity depends on contract code not changing)
