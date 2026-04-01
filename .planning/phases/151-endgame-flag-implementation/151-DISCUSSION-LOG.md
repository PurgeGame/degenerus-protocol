# Phase 151: Endgame Flag Implementation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md -- this log preserves the alternatives considered.

**Date:** 2026-03-31
**Phase:** 151-endgame-flag-implementation
**Areas discussed:** Drip projection math, Flag lifecycle & storage, BURNIE lootbox redirect, Removal scope

---

## Drip Projection Math

### Drip Rate

| Option | Description | Selected |
|--------|-------------|----------|
| Use 0.75% as specified | Projection deliberately conservative -- 0.75% accounts for not all drip reaching nextPool | ✓ |
| Use the real 1% rate | Projection matches actual futurePool drip rate; requirements need updating | |
| Different rate entirely | User specifies a different rate | |

**User's choice:** Use 0.75% as specified
**Notes:** None

### Computation Approach

| Option | Description | Selected |
|--------|-------------|----------|
| Closed-form | totalDrip = futurePool * (1 - 0.9925^n). Single exponentiation via repeated squaring. | ✓ |
| Iterative sum | Loop over remaining days, accumulate each term. Higher gas. | |
| You decide | Claude picks based on gas analysis | |

**User's choice:** Closed-form
**Notes:** None

### Precision Scale

| Option | Description | Selected |
|--------|-------------|----------|
| WAD-scale (1e18) | Standard DeFi fixed-point. Well-understood precision bounds. | ✓ |
| BPS-scale (1e4) | Lighter but risk of compounding rounding error over 120 iterations. | |
| You decide | Claude picks based on accuracy requirements | |

**User's choice:** WAD-scale (1e18)
**Notes:** None

---

## Flag Lifecycle & Storage

### Level Threshold

| Option | Description | Selected |
|--------|-------------|----------|
| L10+ (requirements) | Flag evaluation starts at level 10 and above | ✓ |
| L11+ (roadmap) | Flag evaluation starts at level 11 and above | |
| Different threshold | User specifies | |

**User's choice:** L10+ (requirements)
**Notes:** ROADMAP needs correction to match

### Flag Evaluation Location

| Option | Description | Selected |
|--------|-------------|----------|
| In advanceGame | Already handles purchase-phase entry and daily progression. Zero new entry points. | ✓ |
| At purchase time | Lazy evaluation -- compute and revert on each purchase attempt | |
| You decide | Claude picks placement | |

**User's choice:** In advanceGame
**Notes:** None

### Flag Storage

| Option | Description | Selected |
|--------|-------------|----------|
| Pack into existing slot | Pack bool into existing packed field. Zero additional cold SSTORE cost. | ✓ |
| New storage variable | Dedicated bool. Clearer but adds new slot. | |
| You decide | Claude picks most gas-efficient | |

**User's choice:** Pack into existing slot
**Notes:** None

### Auto-clear Timing

| Option | Description | Selected |
|--------|-------------|----------|
| Clear when lastPurchaseDay is set | Flag irrelevant once nextPool target met. BURNIE purchases reopen. | ✓ |
| Clear at level advance | Flag stays active through lastPurchaseDay. Safer but blocks BURNIE on final day. | |
| Different behavior | User specifies | |

**User's choice:** Clear when lastPurchaseDay is set
**Notes:** None

---

## BURNIE Lootbox Redirect

### Redirect Target

| Option | Description | Selected |
|--------|-------------|----------|
| Same +2 shift | Replace elapsed-time check with flag check, keep targetLevel = currentLevel + 2 | |
| True far-future (bit 22) | Redirect to far-future key space (level | (1 << 22)). More aggressive. | ✓ |
| Different target | User specifies | |

**User's choice:** True far-future (bit 22)
**Notes:** None

### Redirect Scope

| Option | Description | Selected |
|--------|-------------|----------|
| Only current-level rolls | If _rollTargetLevel produces currentLevel, redirect. Near-future rolls land normally. | ✓ |
| All ticket rolls | When flag active, ALL BURNIE lootbox tickets go to far-future. | |

**User's choice:** Only current-level rolls
**Notes:** Matches existing behavior pattern

---

## Removal Scope

### What Gets Deleted

| Option | Description | Selected |
|--------|-------------|----------|
| Remove both cutoffs | Delete cutoff constants/errors from MintModule and LootboxModule | ✓ (part of selected) |
| Remove + audit other 30-day refs | Same + audit all "30 days" references to confirm none are BURNIE ban related | ✓ |
| Different scope | User specifies | |

**User's choice:** Remove + audit other 30-day refs
**Notes:** GameOverModule and similar expected to be unrelated

### Error Naming

| Option | Description | Selected |
|--------|-------------|----------|
| New error name | Replace CoinPurchaseCutoff with name reflecting endgame flag | ✓ |
| Keep CoinPurchaseCutoff | Reuse existing to minimize ABI change | |
| You decide | Claude picks | |

**User's choice:** New error name
**Notes:** None

---

## Claude's Discretion

- Exact storage packing slot choice
- Internal function naming and organization
- Specific error name (must reflect endgame flag mechanism)

## Deferred Ideas

None -- discussion stayed within phase scope
